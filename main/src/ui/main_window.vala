using Gee;
using Gdk;
using Gtk;

using Dino.Entities;

namespace Dino.Ui {

[GtkTemplate (ui = "/im/github/rallep71/DinoX/main_window.ui")]
public class MainWindow : Adw.ApplicationWindow {

    public signal void conversation_selected(Conversation conversation);

    [GtkChild] public unowned Stack stack;
    [GtkChild] public unowned Adw.NavigationSplitView navigation_split_view;

    [GtkChild] public unowned Button add_chat_button;
    [GtkChild] public unowned Button add_group_button;
    [GtkChild] public unowned MenuButton menu_button;

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

        this.title = "Dino";

        this.add_css_class("dino-main");

        ((Widget)this).realize.connect(restore_window_size);

        conversation_selector.init(stream_interactor);
        conversation_selector.conversation_selected.connect_after(() => { navigation_split_view.show_content = true; });

        global_search = new GlobalSearch(stream_interactor);
        search_frame.set_child(global_search.get_widget());

        setup_header_bar();

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
        Gdk.Display? display = Gdk.Display.get_default();
        if (display != null) {
            Gdk.Surface? surface = get_surface();
            Gdk.Monitor? monitor = display.get_monitor_at_surface(surface);

            if (monitor != null &&
                    config.window_width <= monitor.geometry.width &&
                    config.window_height <= monitor.geometry.height) {
                set_default_size(config.window_width, config.window_height);
            }
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

        Builder menu_builder = new Builder.from_resource("/im/github/rallep71/DinoX/menu_app.ui");
        Menu menu_app = menu_builder.get_object("menu_app") as Menu;
        menu_button.set_menu_model(menu_app);

        setup_status_menu(menu_app);
    }

    private void setup_status_menu(Menu menu_app) {
        // Traverse to find the status section
        // Structure: Menu -> Section -> Submenu (Status) -> Section -> Items
        
        MenuModel? section = menu_app.get_item_link(0, Menu.LINK_SECTION);
        if (section == null) return;
        
        MenuModel? status_submenu = section.get_item_link(0, Menu.LINK_SUBMENU);
        if (status_submenu == null) return;
        
        MenuModel? status_section = status_submenu.get_item_link(0, Menu.LINK_SECTION);
        if (status_section == null) return;
        
        Menu? status_menu = status_section as Menu;
        if (status_menu == null) return;
        
        var pm = this.stream_interactor.get_module(PresenceManager.IDENTITY);
        pm.status_changed.connect((show, msg) => {
            update_status_menu(status_menu, show);
        });
        // Initial update (default to online if not set, or fetch from PM if exposed)
        update_status_menu(status_menu, "online"); 
    }

    private void update_status_menu(Menu status_menu, string current_status) {
        string[] statuses = {"online", "away", "dnd", "xa"};
        string[] labels = {_("Online"), _("Away"), _("Busy"), _("Not Available")};
        string[] active_emojis = {"🟢", "🟠", "🔴", "⭕"};
        string inactive_emoji = "⚪"; 

        status_menu.remove_all();
        
        for (int i = 0; i < statuses.length; i++) {
            string emoji = (statuses[i] == current_status) ? active_emojis[i] : inactive_emoji;
            var item = new MenuItem(emoji + "  " + labels[i], "app.set-status");
            item.set_attribute("target", "s", statuses[i]);
            status_menu.append_item(item);
        }
    }
}

public class WelcomePlaceholder : MainWindowPlaceholder {
    public WelcomePlaceholder() {
        status_page.title = _("Welcome to Dino!");
        status_page.description = _("Sign in or create an account to get started.");
        primary_button.label = _("Set up account");
        primary_button.visible = true;
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
    [GtkChild] public unowned Button secondary_button;
}

}
