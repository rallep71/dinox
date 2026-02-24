using Gee;
using Gdk;
using Gtk;

using Dino.Entities;

namespace Dino.Ui {

[GtkTemplate (ui = "/im/github/rallep71/DinoX/main_window.ui")]
public class MainWindow : Adw.ApplicationWindow {

    // Prevent AdwBreakpointBin warning: clamp natural >= minimum
    // (libadwaita AdwStatusPage can report min > natural at certain widths)
    // Also suppress horizontal baseline (GTK4 only supports vertical baselines)
    public override void measure(Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
        base.measure(orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
        if (natural < minimum) natural = minimum;
        if (orientation == Orientation.HORIZONTAL) {
            minimum_baseline = -1;
            natural_baseline = -1;
        }
    }

    public signal void conversation_selected(Conversation conversation);

    [GtkChild] public unowned Stack stack;
    [GtkChild] public unowned Adw.NavigationSplitView navigation_split_view;

    [GtkChild] public unowned Button add_chat_button;
    [GtkChild] public unowned Button add_group_button;
    [GtkChild] public unowned MenuButton status_button;
    [GtkChild] public unowned Image status_image;
    [GtkChild] public unowned MenuButton menu_button;

    [GtkChild] public unowned Adw.HeaderBar header_bar;
    [GtkChild] public unowned Adw.HeaderBar conversation_headerbar;
    [GtkChild] public unowned Adw.WindowTitle conversation_window_title;

    [GtkChild] public unowned ConversationView conversation_view;
    [GtkChild] public unowned ConversationSelector conversation_selector;
    [GtkChild] public unowned Adw.OverlaySplitView search_flap;
    [GtkChild] private unowned Stack left_stack;
    [GtkChild] private unowned Stack right_stack;
    [GtkChild] public unowned Adw.Bin search_frame;

    public GlobalSearch global_search;

    public WelcomePlaceholder welcome_placeholder = new WelcomePlaceholder();
    public NoAccountsPlaceholder accounts_placeholder = new NoAccountsPlaceholder();

    private Database db;
    private Config config;
    private StreamInteractor stream_interactor;

    class construct {
                // Fix für Windows Crash: Typ explizit registrieren
        typeof(Dino.Ui.NaturalSizeIncrease);
        var shortcut = new Shortcut(new KeyvalTrigger(Key.F, ModifierType.CONTROL_MASK), new CallbackAction((widget, args) => {
            ((MainWindow) widget).search_flap.show_sidebar = true;
            return false;
        }));
        add_shortcut(shortcut);
    }

    public MainWindow(Application application, StreamInteractor stream_interactor, Database db, Config config) {
        Object(application : application);
        this.db = db;
        this.config = config;
        this.stream_interactor = stream_interactor;

        this.title = "DinoX";

        this.add_css_class("dino-main");

        ((Widget)this).realize.connect(restore_window_size);

        conversation_selector.init(stream_interactor);
        conversation_selector.conversation_selected.connect_after(() => { navigation_split_view.show_content = true; });

        global_search = new GlobalSearch(stream_interactor);
        search_frame.set_child(global_search.get_widget());

        setup_header_bar();
        
        // Add class for plugins (e.g. TorManager) to find the sidebar header
        header_bar.add_css_class("dino-left");

        stack.add_named(welcome_placeholder, "welcome_placeholder");
        stack.add_named(accounts_placeholder, "accounts_placeholder");
    }

    public enum StackState {
        CLEAN_START,
        NO_ACTIVE_ACCOUNTS,
        NO_ACTIVE_CONVERSATIONS,
        CONVERSATION
    }

    public void set_stack_state(StackState stack_state) {
        if (stack_state == StackState.CONVERSATION) {
            left_stack.set_visible_child_name("content");
            right_stack.set_visible_child_name("content");
            stack.set_visible_child_name("main");
        } else if (stack_state == StackState.CLEAN_START) {
            stack.set_visible_child_name("welcome_placeholder");
        } else if (stack_state == StackState.NO_ACTIVE_ACCOUNTS) {
            stack.set_visible_child_name("accounts_placeholder");
        } else if (stack_state == StackState.NO_ACTIVE_CONVERSATIONS) {
            stack.set_visible_child_name("main");
            left_stack.set_visible_child_name("placeholder");
            right_stack.set_visible_child_name("placeholder");
        }
    }

    public void loop_conversations(bool backwards) {
        conversation_selector.loop_conversations(backwards);
    }

    public void restore_window_size() {
        // Set minimum size to prevent layout warnings and text clipping
        set_size_request(500, 300);
        
        // Default size if config values are invalid
        int width = config.window_width > 0 ? config.window_width : 900;
        int height = config.window_height > 0 ? config.window_height : 600;
        
        Gdk.Display? display = Gdk.Display.get_default();
        if (display != null) {
            Gdk.Surface? surface = get_surface();
            Gdk.Monitor? monitor = display.get_monitor_at_surface(surface);

            if (monitor != null &&
                    width <= monitor.geometry.width &&
                    height <= monitor.geometry.height) {
                set_default_size(width, height);
            } else {
                // Fallback to default size
                set_default_size(900, 600);
            }
        } else {
            // No display info, use default size
            set_default_size(width, height);
        }
        if (config.window_maximize) {
            maximize();
        }

        ((Widget)this).unrealize.connect(() => {
            save_window_size();
            config.window_maximize = this.maximized;
        });
    }

    public void save_window_size() {
        if (this.maximized) return;

        Gdk.Display? display = get_display();
        Gdk.Surface? surface = get_surface();
        if (display != null && surface != null) {
            Gdk.Monitor monitor = display.get_monitor_at_surface(surface);

            // Only store if the values have changed and are reasonable-looking.
            if (config.window_width != default_width && default_width > 0 && default_width <= monitor.geometry.width) {
                config.window_width = default_width;
            }
            if (config.window_height != default_height && default_height > 0 && default_height <= monitor.geometry.height) {
                config.window_height = default_height;
            }
        }
    }

    private void setup_header_bar() {
        add_chat_button.tooltip_text = Util.string_if_tooltips_active(_("Start Conversation"));
        add_group_button.tooltip_text = Util.string_if_tooltips_active(_("Join Channel"));
        status_button.tooltip_text = Util.string_if_tooltips_active(_("Set Status"));

        Builder menu_builder = new Builder.from_resource("/im/github/rallep71/DinoX/menu_app.ui");
        Menu menu_app = menu_builder.get_object("menu_app") as Menu;
        menu_button.set_menu_model(menu_app);

        Menu status_menu = new Menu();
        status_button.set_menu_model(status_menu);
        setup_status_menu(status_menu);
    }

    private void setup_status_menu(Menu status_menu) {
        var pm = this.stream_interactor.get_module<PresenceManager>(PresenceManager.IDENTITY);
        pm.status_changed.connect((show, msg) => {
            update_status_menu(status_menu, show);
        });
        // Initial update with persisted status
        update_status_menu(status_menu, pm.get_current_show()); 
    }

    private void update_status_menu(Menu status_menu, string current_status) {
        string[] statuses = {"online", "away", "dnd", "xa"};
        string[] labels = {_("Online"), _("Away"), _("Busy"), _("Not Available")};
        string[] active_emojis = {"🟢", "🟠", "🔴", "⭕"};
        string inactive_emoji = "⚪"; 

        status_menu.remove_all();
        
        apply_status_color(current_status);

        for (int i = 0; i < statuses.length; i++) {
            string emoji = (statuses[i] == current_status) ? active_emojis[i] : inactive_emoji;
            var item = new MenuItem(emoji + "  " + labels[i], "app.set-status");
            item.set_attribute("target", "s", statuses[i]);
            status_menu.append_item(item);
        }

        var status_msg_item = new MenuItem(_("Set Status Message…"), "app.set-status-message");
        status_menu.append_item(status_msg_item);
    }

    private void apply_status_color(string status) {
        status_image.remove_css_class("success");
        status_image.remove_css_class("warning");
        status_image.remove_css_class("error");
        status_image.remove_css_class("dim-label");

        switch (status) {
            case "online":
            case "chat":
                status_image.add_css_class("success");
                break;
            case "away":
                status_image.add_css_class("warning");
                break;
            case "xa":
                status_image.add_css_class("dim-label");
                break;
            case "dnd":
                status_image.add_css_class("error");
                break;
            case "offline":
            default:
                status_image.add_css_class("dim-label");
                break;
        }
    }
}

public class WelcomePlaceholder : MainWindowPlaceholder {
    public WelcomePlaceholder() {
        status_page.title = _("Welcome to DinoX!");
        status_page.description = _("Sign in or create an account to get started.");
        primary_button.label = _("Sign in");
        primary_button.visible = true;
        register_button.label = _("Create account");
        register_button.visible = true;
        secondary_button.label = _("Restore from Backup");
        secondary_button.visible = true;
    }
}

public class NoAccountsPlaceholder : MainWindowPlaceholder {
    public NoAccountsPlaceholder() {
        status_page.title = _("No active accounts");
        primary_button.label = _("Manage accounts");
        primary_button.visible = true;
    }
}

[GtkTemplate (ui = "/im/github/rallep71/DinoX/main_window_placeholder.ui")]
public class MainWindowPlaceholder : Box {
    [GtkChild] public unowned Adw.StatusPage status_page;
    [GtkChild] public unowned Button primary_button;
    [GtkChild] public unowned Button register_button;
    [GtkChild] public unowned Button secondary_button;
}

}
