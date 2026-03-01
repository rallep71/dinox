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

// Plain data holder for SNI properties.
// D-Bus registration is done manually via systray_sni_dbus.c
// so we can export IconPixmap as the correct a(iiay) type.
public class StatusNotifierItem : Object {

    public string status { get; set; default = "Active"; }
    public string icon_name { get; set; default = "im.github.rallep71.DinoX"; }
    public string title { get; set; default = "DinoX"; }
    public string category { get; set; default = "Communications"; }
    public string id { get; set; default = "dinox"; }
    public bool item_is_menu { get; set; default = false; }
    public string icon_theme_path { get; set; default = ""; }

    // IconPixmap variant of type a(iiay) for Qt-based trays (Quickshell, etc.)
    private GLib.Variant? _icon_pixmap = null;

    public signal void activate(int x, int y);
    public signal void secondary_activate(int x, int y);

    // Return the D-Bus value for a given property name
    public GLib.Variant? get_dbus_property(string name) {
        switch (name) {
            case "Status":        return new Variant.string(status);
            case "IconName":      return new Variant.string(icon_name);
            case "IconThemePath": return new Variant.string(icon_theme_path);
            case "Title":         return new Variant.string(title);
            case "Category":      return new Variant.string(category);
            case "Id":            return new Variant.string(id);
            case "ItemIsMenu":    return new Variant.boolean(item_is_menu);
            case "Menu":          return new Variant.object_path("/MenuBar");
            case "IconPixmap":    return get_icon_pixmap();
            default:              return null;
        }
    }

    private GLib.Variant get_icon_pixmap() {
        if (_icon_pixmap != null) return _icon_pixmap;
        return new Variant("a(iiay)", null);
    }

    // Load icon PNGs as ARGB32 pixel data for IconPixmap.
    // If any loaded, clears icon_name so Qt trays use pixel data.
    public void load_icon_pixmaps() {
        string icon_id = "im.github.rallep71.DinoX";
        int[] sizes = {32, 48};

        string? hicolor = find_hicolor_dir(icon_id);
        if (hicolor == null) {
            debug("Systray: no hicolor dir found for IconPixmap");
            return;
        }

        var builder = new VariantBuilder(new VariantType("a(iiay)"));
        int count = 0;

        foreach (int sz in sizes) {
            string path = Path.build_filename(hicolor, "%dx%d".printf(sz, sz), "apps", icon_id + ".png");
            uint8[]? argb = load_png_as_argb32(path, sz);
            if (argb == null) continue;

            var bytes_builder = new VariantBuilder(new VariantType("ay"));
            foreach (uint8 b in argb) {
                bytes_builder.add("y", b);
            }
            builder.add("(ii@ay)", (int32) sz, (int32) sz, bytes_builder.end());
            count++;
            debug("Systray: IconPixmap loaded %dx%d", sz, sz);
        }

        if (count > 0) {
            _icon_pixmap = builder.end();
            // Keep icon_name set! Tray hosts that support IconPixmap will use
            // the pixel data; older hosts fall back to IconName + IconThemePath.
            debug("Systray: IconPixmap ready (%d sizes)", count);
        }
    }

    private string? find_hicolor_dir(string icon_id) {
        string[] dirs = {};

        string? appdir = Environment.get_variable("APPDIR");
        if (appdir != null) {
            dirs += Path.build_filename(appdir, "usr", "share", "icons", "hicolor");
        }

        string? xdg = Environment.get_variable("XDG_DATA_DIRS");
        if (xdg != null) {
            foreach (string d in xdg.split(":")) {
                if (d.length > 0) dirs += Path.build_filename(d, "icons", "hicolor");
            }
        }
        dirs += "/usr/share/icons/hicolor";

        foreach (string dir in dirs) {
            string test = Path.build_filename(dir, "48x48", "apps", icon_id + ".png");
            if (FileUtils.test(test, FileTest.IS_REGULAR)) return dir;
        }
        return null;
    }

    private uint8[]? load_png_as_argb32(string path, int size) {
        if (!FileUtils.test(path, FileTest.IS_REGULAR)) return null;

        try {
            var pb = new Gdk.Pixbuf.from_file_at_size(path, size, size);
            if (pb == null) return null;
            if (!pb.get_has_alpha()) pb = pb.add_alpha(false, 0, 0, 0);

            int w = pb.get_width();
            int h = pb.get_height();
            int rs = pb.get_rowstride();
            unowned uint8[] px = pb.get_pixels();

            // GdkPixbuf RGBA -> SNI ARGB32 network byte order (A R G B)
            uint8[] argb = new uint8[w * h * 4];
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int s = y * rs + x * 4;
                    int d = (y * w + x) * 4;
                    argb[d]     = px[s + 3]; // A
                    argb[d + 1] = px[s];     // R
                    argb[d + 2] = px[s + 1]; // G
                    argb[d + 3] = px[s + 2]; // B
                }
            }
            return argb;
        } catch (Error e) {
            return null;
        }
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

        // Hide window immediately for instant visual feedback
        if (window != null) {
            window.hide();
        }

        // Cleanup systray (DBus unregister etc.)
        cleanup();

        // Use disconnect_all() to close connections WITHOUT firing account_removed.
        // stream_interactor.disconnect_account() fires account_removed which
        // causes the OMEMO plugin to DELETE all identity keys and sessions.
        debug("Systray: Disconnecting all accounts...");
        application.stream_interactor.connection_manager.disconnect_all();

        finalize_quit();
    }
    
    private void finalize_quit() {
        // Graceful GTK quit — triggers application.shutdown() for final cleanup.
        // shutdown() handles cleanup_temp_files() and disconnect_all() (no-op since
        // connections are already cleared above).
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
            
            // Set IconThemePath so the desktop can find the icon.
            // AppImage: use bundled icons; regular install: system icons.
            string? appdir = Environment.get_variable("APPDIR");
            if (appdir != null) {
                string theme_path = Path.build_filename(appdir, "usr", "share", "icons");
                if (FileUtils.test(theme_path, FileTest.IS_DIR)) {
                    status_notifier.icon_theme_path = theme_path;
                    debug("Systray: IconThemePath set to %s", theme_path);
                }
            } else {
                // Regular install: also set path for Qt trays that need explicit lookup
                status_notifier.icon_theme_path = "/usr/share/icons";
            }

            // Load inline pixel data for Qt-based trays (Quickshell, etc.)
            status_notifier.load_icon_pixmaps();
            
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
            
            // Register SNI via C helper (supports IconPixmap a(iiay) type)
            dbus_id = SniDbus.register(connection, "/StatusNotifierItem",
                sni_get_property_cb, sni_method_call_cb, (void*) this);
            
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

    // --- Static D-Bus callbacks for the C helper ---

    private static GLib.Variant? sni_get_property_cb(string property_name, void* user_data) {
        unowned SystrayManager self = (SystrayManager) user_data;
        if (self.status_notifier == null) return null;
        return self.status_notifier.get_dbus_property(property_name);
    }

    private static void sni_method_call_cb(string method_name, GLib.Variant parameters,
                                            GLib.DBusMethodInvocation invocation, void* user_data) {
        unowned SystrayManager self = (SystrayManager) user_data;
        switch (method_name) {
            case "Activate":
            case "SecondaryActivate":
                self.toggle_window_visibility();
                invocation.return_value(null);
                break;
            case "ContextMenu":
                debug("Systray: ContextMenu called");
                invocation.return_value(null);
                break;
            case "Scroll":
                invocation.return_value(null);
                break;
            default:
                invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod",
                    "Unknown method: " + method_name);
                break;
        }
    }

    // Emit D-Bus signals (replaces [DBus] auto-generated signal emission)
    private void emit_new_icon() {
        if (connection != null && !connection.is_closed()) {
            SniDbus.emit_signal(connection, "/StatusNotifierItem", "NewIcon");
        }
    }

    private void emit_new_status(string new_status_value) {
        if (connection != null && !connection.is_closed()) {
            SniDbus.emit_signal(connection, "/StatusNotifierItem",
                "NewStatus", new Variant("(s)", new_status_value));
        }
    }
}

[DBus (name = "org.kde.StatusNotifierWatcher")]
interface StatusNotifierWatcher : Object {
    public abstract async void register_status_notifier_item(string service) throws Error;
}

}
