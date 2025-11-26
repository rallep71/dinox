/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;
using Gee;
using Dbusmenu;

namespace Dino.Ui {

[DBus (name = "org.kde.StatusNotifierItem")]
public class StatusNotifierItem : Object {
    
    public string status { get; set; default = "Active"; }
    public string icon_name { get; set; default = "im.github.rallep71.DinoX"; }
    public string title { get; set; default = "DinoX"; }
    public string category { get; set; default = "Communications"; }
    public string id { get; set; default = "dinox"; }
    public bool item_is_menu { get; set; default = false; }
    
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
        print("Systray: ContextMenu called at (%d, %d) - Cinnamon should show DBusMenu\n", x, y);
        // Menu is supposed to be handled via DBusMenu by the StatusNotifierHost
        // But Cinnamon has a bug and shows empty white field
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
        print("Systray: quit_application() called\n");
        
        // Cleanup systray first
        cleanup();
        
        // Disconnect XMPP accounts - fire and forget
        var accounts = application.stream_interactor.get_accounts();
        print("Systray: Disconnecting %d accounts...\n", accounts.size);
        foreach (var account in accounts) {
            application.stream_interactor.disconnect_account.begin(account);
        }
        
        // Try graceful GTK quit
        print("Systray: Calling application.quit()\n");
        application.quit();
        
        // Force exit immediately - Flatpak doesn't quit cleanly otherwise
        print("Systray: Force exit - Process.exit(0)\n");
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
            var pm = application.stream_interactor.get_module(PresenceManager.IDENTITY);
            status_changed_id = pm.status_changed.connect((show, msg) => {
                update_status_items(show);
            });
            update_status_items("online");

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
            
            print("Systray: Dbusmenu.Server initialized on /MenuBar\n");
            
            dbus_id = connection.register_object("/StatusNotifierItem", status_notifier);
            
            print("Systray: StatusNotifierItem registered on D-Bus\n");
            
            yield register_with_watcher();
            
        } catch (Error e) {
            print("Systray: Failed to initialize D-Bus: %s\n", e.message);
        }
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
                
                print("Systray: Successfully registered with %s as %s\n", watcher_name, service_name);
                registered = true;
                break;
                
            } catch (Error e) {
                continue;
            }
        }
        
        if (!registered) {
            print("Systray: No StatusNotifierWatcher available\n");
        }
    }
    
    private void on_activate(int x, int y) {
        toggle_window_visibility();
    }
    
    private void on_secondary_activate(int x, int y) {
        // Cinnamon calls ContextMenu instead of SecondaryActivate
        // This is rarely called - the DBusMenu is shown instead
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
        
        if (status_changed_id != 0) {
            var pm = application.stream_interactor.get_module(PresenceManager.IDENTITY);
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

// Removed DBusMenuExporter class

}
