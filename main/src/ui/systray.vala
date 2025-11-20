using Gtk;
using Gee;
using Dbusmenu;

namespace Dino.Ui {

[DBus (name = "org.kde.StatusNotifierItem")]
public class StatusNotifierItem : Object {
    
    public string status { get; set; default = "Active"; }
    public string icon_name { get; set; default = "im.dino.Dino"; }
    public string title { get; set; default = "Dino"; }
    public string category { get; set; default = "Communications"; }
    public string id { get; set; default = "dino"; }
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
    public void dbus_activate(int x, int y) {
        activate(x, y);
    }
    
    [DBus (name = "SecondaryActivate")]
    public void dbus_secondary_activate(int x, int y) {
        secondary_activate(x, y);
    }
    
    [DBus (name = "ContextMenu")]
    public void context_menu(int x, int y) {
        print("Systray: ContextMenu called at (%d, %d) - Cinnamon should show DBusMenu\n", x, y);
        // Menu is supposed to be handled via DBusMenu by the StatusNotifierHost
        // But Cinnamon has a bug and shows empty white field
    }
    
    [DBus (name = "Scroll")]
    public void scroll(int delta, string orientation) {
    }
    
    public void update_icon(string icon) {
        icon_name = icon;
        new_icon();
    }
    
    public void update_status(string new_status_value) {
        status = new_status_value;
        new_status(new_status_value);
    }
}

public class SystrayManager : Object {
    
    private Application application;
    public MainWindow? window;
    private StatusNotifierItem? status_notifier;
    private Dbusmenu.Server? menu_server;
    private Dbusmenu.Menuitem? item_show;
    private uint dbus_id = 0;
    private DBusConnection? connection;
    
    public bool is_hidden = false;
    
    public SystrayManager(Application application) {
        this.application = application;
        initialize_dbus.begin();
    }
    
    public void set_window(MainWindow window) {
        this.window = window;
        
        window.close_request.connect(() => {
            hide_window();
            return true;
        });
    }
    
    private async void initialize_dbus() {
        try {
            connection = yield Bus.get(BusType.SESSION);
            
            status_notifier = new StatusNotifierItem();
            status_notifier.activate.connect(on_activate);
            status_notifier.secondary_activate.connect(on_secondary_activate);
            
            // Initialize Dbusmenu Server
            menu_server = new Dbusmenu.Server("/MenuBar");
            
            var root = new Dbusmenu.Menuitem();
            root.property_set(Dbusmenu.MENUITEM_PROP_CHILD_DISPLAY, "submenu");
            menu_server.set_root(root);
            
            // Show/Hide Item
            item_show = new Dbusmenu.Menuitem();
            item_show.property_set(Dbusmenu.MENUITEM_PROP_LABEL, _("Hide Window"));
            item_show.property_set(Dbusmenu.MENUITEM_PROP_ENABLED, "true");
            item_show.property_set(Dbusmenu.MENUITEM_PROP_VISIBLE, "true");
            item_show.property_set(Dbusmenu.MENUITEM_PROP_ICON_NAME, "view-restore-symbolic");
            item_show.item_activated.connect((timestamp) => {
                toggle_window_visibility();
            });
            root.child_append(item_show);
            
            // Separator
            var item_sep = new Dbusmenu.Menuitem();
            item_sep.property_set(Dbusmenu.MENUITEM_PROP_TYPE, Dbusmenu.CLIENT_TYPES_SEPARATOR);
            item_sep.property_set(Dbusmenu.MENUITEM_PROP_VISIBLE, "true");
            root.child_append(item_sep);
            
            // Quit Item
            var item_quit = new Dbusmenu.Menuitem();
            item_quit.property_set(Dbusmenu.MENUITEM_PROP_LABEL, _("Quit"));
            item_quit.property_set(Dbusmenu.MENUITEM_PROP_ENABLED, "true");
            item_quit.property_set(Dbusmenu.MENUITEM_PROP_VISIBLE, "true");
            item_quit.property_set(Dbusmenu.MENUITEM_PROP_ICON_NAME, "application-exit-symbolic");
            item_quit.item_activated.connect((timestamp) => {
                application.activate_action("quit", null);
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
        string[] watchers = {
            "org.kde.StatusNotifierWatcher",
            "org.x.StatusNotifierWatcher"
        };
        
        bool registered = false;
        foreach (string watcher_name in watchers) {
            try {
                StatusNotifierWatcher watcher = yield connection.get_proxy(
                    watcher_name,
                    "/StatusNotifierWatcher",
                    DBusProxyFlags.NONE
                );
                
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
        
        if (item_show != null) {
            item_show.property_set(Dbusmenu.MENUITEM_PROP_LABEL, _("Hide Window"));
        }
    }
    
    private void hide_window() {
        if (window == null) return;
        
        window.set_visible(false);
        is_hidden = true;
        
        if (item_show != null) {
            item_show.property_set(Dbusmenu.MENUITEM_PROP_LABEL, _("Show Window"));
        }
    }
    
    ~SystrayManager() {
        if (connection != null && dbus_id != 0) {
            connection.unregister_object(dbus_id);
        }
    }
}

[DBus (name = "org.kde.StatusNotifierWatcher")]
interface StatusNotifierWatcher : Object {
    public abstract async void register_status_notifier_item(string service) throws Error;
}

// Removed DBusMenuExporter class

}
