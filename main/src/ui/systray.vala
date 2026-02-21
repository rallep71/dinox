/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Linux Systray - StatusNotifierItem (SNI) with libdbusmenu.
 * Works natively on KDE, Cinnamon, MATE, XFCE.
 * On GNOME, requires AppIndicator/KStatusNotifierItem extension.
 * Falls back to GApplication.hold() if no SNI watcher is available.
 */

using Gtk;
using Gee;
using Dbusmenu;
using GLib;

namespace Dino.Ui {

[DBus (name = "org.kde.StatusNotifierItem")]
public class StatusNotifierItem : Object {
    
    public string status { get; set; default = "Active"; }
    public string icon_name { get; set; default = "im.github.rallep71.DinoX"; }
    public string title { get; set; default = "DinoX"; }
    public string category { get; set; default = "Communications"; }
    public string id { get; set; default = "dinox"; }
    public bool item_is_menu { get; set; default = false; }

    // IconThemePath tells the StatusNotifierHost where to look for the icon.
    // Critical for AppImage/Flatpak where the icon is not in the system theme.
    public string icon_theme_path { get; set; default = ""; }
    
    // Menu is exported on /MenuBar
    public ObjectPath menu { 
        owned get { return new ObjectPath("/MenuBar"); }
    }
    
    [DBus (name = "NewIcon")]
    public signal void new_icon();
    
    [DBus (name = "NewStatus")]
    public signal void new_status(string status);
    
    public signal void activate(int x, int y);
    public signal void secondary_activate(int x, int y);
    
    [DBus (name = "Activate")]
    public void dbus_activate(int x, int y) throws Error {
        activate(x, y);
    }
    
    [DBus (name = "SecondaryActivate")]
    public void dbus_secondary_activate(int x, int y) throws Error {
        secondary_activate(x, y);
    }
    
    [DBus (name = "ContextMenu")]
    public void context_menu(int x, int y) throws Error {
        debug("Systray: ContextMenu called at (%d, %d)", x, y);
    }
    
    [DBus (name = "Scroll")]
    public void scroll(int delta, string orientation) throws Error {
    }
    
    public void update_icon(string icon) throws Error {
        icon_name = icon;
        new_icon();
    }
    
    public void update_status(string new_status_value) throws Error {
        status = new_status_value;
        new_status(new_status_value);
    }
}

public class SystrayManager : Object {
    
    private unowned Application application;
    public MainWindow? window;
    private StatusNotifierItem? status_notifier;
    private Dbusmenu.Server? menu_server;
    private uint dbus_id = 0;
    private DBusConnection? connection;
    private Dbusmenu.Menuitem[] status_items;
    private ulong status_changed_id = 0;
    private uint watcher_id = 0;
    private bool sni_registered = false;
    
    public bool is_hidden = false;
    
    public SystrayManager(Application application) {
        this.application = application;
        initialize_dbus.begin();
    }
    
    public void set_window(MainWindow window) {
        this.window = window;
        
        window.close_request.connect(() => {
            // Check if background mode is enabled
            if (Dino.Application.get_default().settings.keep_background) {
                // Keep running in background - just hide the window
                hide_window();
                return true;  // Prevent window destruction
            } else {
                // User wants normal quit - quit the application
                quit_application();
                return true;  // Handler handled
            }
        });
    }
    
    public void quit_application() {
        debug("Systray: quit_application() called");
        
        // Cleanup systray first
        cleanup();
        
        // Disconnect XMPP accounts gracefully (sends <presence type="unavailable"/>)
        var accounts = application.stream_interactor.get_accounts();
        debug("Systray: Disconnecting all accounts...");
        
        // Safety timer: force exit after 3 seconds if graceful disconnect hangs
        uint force_timer = Timeout.add(3000, () => {
            warning("Systray: Graceful disconnect timed out after 3s, forcing exit");
            finalize_quit();
            return false;
        });
        
        // Use disconnect_all() to close connections WITHOUT firing account_removed.
        // stream_interactor.disconnect_account() fires account_removed which
        // causes the OMEMO plugin to DELETE all identity keys and sessions.
        application.stream_interactor.connection_manager.disconnect_all();
        Source.remove(force_timer);
        finalize_quit();
    }
    
    private void finalize_quit() {
        // Ensure cache is cleaned up
        application.cleanup_temp_files();
        
        // Graceful GTK quit — triggers application.shutdown() for final cleanup
        debug("Systray: Calling application.quit()");
        application.quit();
        
        // Force exit as fallback — Flatpak sometimes doesn't quit cleanly
        debug("Systray: Force exit - Process.exit(0)");
        Process.exit(0);
    }
    
    private async void initialize_dbus() {
        try {
            var conn = yield Bus.get(BusType.SESSION);
            if (disposed) return;
            connection = conn;
            
            status_notifier = new StatusNotifierItem();
            status_notifier.activate.connect(on_activate);
            status_notifier.secondary_activate.connect(on_secondary_activate);
            
            // Set IconThemePath for AppImage/Flatpak so the desktop can find the icon.
            // APPDIR env is set by AppRun; for normal installs this stays empty (system theme).
            string? appdir = Environment.get_variable("APPDIR");
            if (appdir != null) {
                string theme_path = Path.build_filename(appdir, "usr", "share", "icons");
                if (FileUtils.test(theme_path, FileTest.IS_DIR)) {
                    status_notifier.icon_theme_path = theme_path;
                    debug("Systray: IconThemePath set to %s", theme_path);
                }
            }
            
            // Initialize Dbusmenu Server
            menu_server = new Dbusmenu.Server("/MenuBar");
            
            var root = new Dbusmenu.Menuitem();
            root.property_set(Dbusmenu.MENUITEM_PROP_CHILD_DISPLAY, "submenu");
            menu_server.set_root(root);
            
            string[] statuses = {"online", "away", "dnd", "xa"};
            string[] labels = {_("Online"), _("Away"), _("Busy"), _("Not Available")};
            status_items = new Dbusmenu.Menuitem[statuses.length];

            for (int i = 0; i < statuses.length; i++) {
                var s = statuses[i];
                var item = new Dbusmenu.Menuitem();
                item.property_set(Dbusmenu.MENUITEM_PROP_LABEL, labels[i]);
                item.property_set_bool(Dbusmenu.MENUITEM_PROP_ENABLED, true);
                item.property_set_bool(Dbusmenu.MENUITEM_PROP_VISIBLE, true);
                item.item_activated.connect((timestamp) => {
                    application.activate_action("set-status", new Variant.string(s));
                });
                status_items[i] = item;
                root.child_append(item);
            }

            // Connect to PresenceManager status changes
            var pm = application.stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY);
            status_changed_id = pm.status_changed.connect((show, msg) => {
                update_status_items(show);
            });
            update_status_items(pm.get_current_show());

            // Separator
            var item_sep = new Dbusmenu.Menuitem();
            item_sep.property_set(Dbusmenu.MENUITEM_PROP_TYPE, Dbusmenu.CLIENT_TYPES_SEPARATOR);
            item_sep.property_set_bool(Dbusmenu.MENUITEM_PROP_VISIBLE, true);
            root.child_append(item_sep);
            
            // Quit Item
            var item_quit = new Dbusmenu.Menuitem();
            item_quit.property_set(Dbusmenu.MENUITEM_PROP_LABEL, _("Quit"));
            item_quit.property_set_bool(Dbusmenu.MENUITEM_PROP_ENABLED, true);
            item_quit.property_set_bool(Dbusmenu.MENUITEM_PROP_VISIBLE, true);
            item_quit.property_set(Dbusmenu.MENUITEM_PROP_ICON_NAME, "application-exit-symbolic");
            item_quit.item_activated.connect((timestamp) => {
                // Use a small timeout to ensure we are completely out of the Dbusmenu signal handler stack
                Timeout.add(50, () => {
                    quit_application();
                    return false;
                });
            });
            root.child_append(item_quit);
            
            debug("Systray: Dbusmenu.Server initialized on /MenuBar");
            
            dbus_id = connection.register_object("/StatusNotifierItem", status_notifier);
            
            debug("Systray: StatusNotifierItem registered on D-Bus");
            
            start_watching();
            
        } catch (Error e) {
            warning("Systray: Failed to initialize D-Bus: %s", e.message);
            // Fallback: hold application so it stays alive when window is hidden
            application.hold();
            debug("Systray: Using GApplication.hold() fallback for background mode");
        }
    }
    
    private void start_watching() {
        // Watch for KDE/Freedesktop StatusNotifierWatcher
        watcher_id = Bus.watch_name(BusType.SESSION, "org.kde.StatusNotifierWatcher",
            BusNameWatcherFlags.NONE,
            (conn, name, owner) => {
                debug("Systray: StatusNotifierWatcher appeared owned by %s", owner);
                register_with_watcher.begin();
            },
            (conn, name) => {
                debug("Systray: StatusNotifierWatcher vanished");
                if (!sni_registered) {
                    // No watcher available - use hold() fallback for background mode
                    application.hold();
                    debug("Systray: No SNI watcher found, using GApplication.hold() fallback");
                }
            }
        );
    }
    
    private async void register_with_watcher() {
        if (disposed || connection == null) return;

        string[] watchers = {
            "org.kde.StatusNotifierWatcher",
            "org.x.StatusNotifierWatcher"
        };
        
        bool registered = false;
        foreach (string watcher_name in watchers) {
            try {
                if (disposed || connection == null) return;
                StatusNotifierWatcher watcher = yield connection.get_proxy(
                    watcher_name,
                    "/StatusNotifierWatcher",
                    DBusProxyFlags.NONE
                );
                
                if (disposed || connection == null) return;
                string service_name = connection.unique_name;
                yield watcher.register_status_notifier_item(service_name);
                
                debug("Systray: Successfully registered with %s as %s", watcher_name, service_name);
                registered = true;
                sni_registered = true;
                break;
                
            } catch (Error e) {
                continue;
            }
        }
        
        if (!registered) {
            warning("Systray: No StatusNotifierWatcher available - tray icon will not be visible");
            // Fallback: hold application so it stays alive when window is hidden
            application.hold();
            debug("Systray: Using GApplication.hold() fallback for background mode");
        }
    }
    
    private void on_activate(int x, int y) {
        toggle_window_visibility();
    }
    
    private void on_secondary_activate(int x, int y) {
        toggle_window_visibility();
    }
    
    public void toggle_window_visibility() {
        if (window == null) return;
        
        if (is_hidden || !window.is_visible()) {
            show_window();
        } else {
            hide_window();
        }
    }
    
    private void show_window() {
        if (window == null) return;
        
        window.present();
        window.set_visible(true);
        is_hidden = false;
    }
    
    private void hide_window() {
        if (window == null) return;
        
        window.set_visible(false);
        is_hidden = true;
    }
    
    private void update_status_items(string current_status) {
        if (status_items == null) return;

        string[] statuses = {"online", "away", "dnd", "xa"};
        string[] labels = {_("Online"), _("Away"), _("Busy"), _("Not Available")};
        string[] active_emojis = {"🟢", "🟠", "🔴", "⭕"};
        string inactive_emoji = "⚪"; 

        for (int i = 0; i < statuses.length; i++) {
            if (status_items[i] == null) continue;
            
            string emoji = (statuses[i] == current_status) ? active_emojis[i] : inactive_emoji;
            status_items[i].property_set(Dbusmenu.MENUITEM_PROP_LABEL, emoji + "  " + labels[i]);
        }
    }
    
    private bool disposed = false;
    
    public void cleanup() {
        if (disposed) {
            return;
        }
        disposed = true;
        
        if (watcher_id != 0) {
            Bus.unwatch_name(watcher_id);
            watcher_id = 0;
        }
        
        if (status_changed_id != 0) {
            var pm = application.stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY);
            SignalHandler.disconnect(pm, status_changed_id);
            status_changed_id = 0;
        }

        if (connection != null && !connection.is_closed() && dbus_id != 0) {
            connection.unregister_object(dbus_id);
            dbus_id = 0;
        }
        
        status_items = null;
        menu_server = null;
        status_notifier = null;
        connection = null;
    }

    ~SystrayManager() {
        cleanup();
    }
}

[DBus (name = "org.kde.StatusNotifierWatcher")]
interface StatusNotifierWatcher : Object {
    public abstract async void register_status_notifier_item(string service) throws Error;
}

}
