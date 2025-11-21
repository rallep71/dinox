using Gtk;
using Adw;

using Dino.Entities;
using Dino.Ui;
using Xmpp;

public class Dino.Ui.Application : Adw.Application, Dino.Application {
    private const string[] KEY_COMBINATION_QUIT = {"<Ctrl>Q", null};
    private const string[] KEY_COMBINATION_ADD_CHAT = {"<Ctrl>T", null};
    private const string[] KEY_COMBINATION_ADD_CONFERENCE = {"<Ctrl>G", null};
    private const string[] KEY_COMBINATION_LOOP_CONVERSATIONS = {"<Ctrl>Tab", null};
    private const string[] KEY_COMBINATION_LOOP_CONVERSATIONS_REV = {"<Ctrl><Shift>Tab", null};
    private const string[] KEY_COMBINATION_SHOW_SETTINGS = {"<Ctrl>comma", null};

    public MainWindow window;
    public MainWindowController controller;
    private SystrayManager? systray_manager = null;

    public Database db { get; set; }
    public Dino.Entities.Settings settings { get; set; }
    private Config config { get; set; }
    public StreamInteractor stream_interactor { get; set; }
    public Plugins.Registry plugin_registry { get; set; default = new Plugins.Registry(); }
    public SearchPathGenerator? search_path_generator { get; set; }

    internal static bool print_version = false;
    private const OptionEntry[] options = {
        { "version", 0, 0, OptionArg.NONE, ref print_version, "Display version number", null },
        { null }
    };

    public Application() throws Error {
        Object(application_id: "im.dino.Dino", flags: ApplicationFlags.HANDLES_OPEN);
        init();
        Environment.set_application_name("Dino");
        Gtk.Window.set_default_icon_name("im.dino.Dino");

        create_actions();
        add_main_option_entries(options);

        startup.connect(() => {
            if (print_version) {
                print(@"Dino $(Dino.get_version())\n");
                Process.exit(0);
            }

            NotificationEvents notification_events = stream_interactor.get_module(NotificationEvents.IDENTITY);
            get_notifications_dbus.begin((_, res) => {
                DBusNotifications? dbus_notifications = get_notifications_dbus.end(res);
                if (dbus_notifications != null) {
                    FreeDesktopNotifier free_desktop_notifier = new FreeDesktopNotifier(stream_interactor, dbus_notifications);
                    notification_events.register_notification_provider.begin(free_desktop_notifier);
                } else {
                    notification_events.register_notification_provider.begin(new GNotificationsNotifier(stream_interactor));
                }
            });

            notification_events.notify_content_item.connect((content_item, conversation) => {
                // Set urgency hint also if (normal) notifications are disabled
                // Don't set urgency hint in GNOME, produces "Window is active" notification
                var desktop_env = Environment.get_variable("XDG_CURRENT_DESKTOP");
                if (desktop_env == null || !desktop_env.down().contains("gnome")) {
                    if (this.active_window != null) {
//                        this.active_window.urgency_hint = true;
                    }
                }
            });
            stream_interactor.get_module(FileManager.IDENTITY).add_metadata_provider(new Util.AudioVideoFileMetadataProvider());
            
            // Initialize systray
            systray_manager = new SystrayManager(this);
        });

        activate.connect(() => {
            if (window == null) {
                controller = new MainWindowController(this, stream_interactor, db);
                config = new Config(db);
                window = new MainWindow(this, stream_interactor, db, config);
                controller.set_window(window);
                if ((get_flags() & ApplicationFlags.IS_SERVICE) == ApplicationFlags.IS_SERVICE) window.hide_on_close = true;
                
                // Connect systray to window
                if (systray_manager != null) {
                    systray_manager.set_window(window);
                }
            }
            window.present();
        });
    }

    public void handle_uri(string jid, string query, Gee.Map<string, string> options) {
        switch (query) {
            case "join":
                show_join_muc_dialog(null, jid);
                break;
            case "message":
                Gee.List<Account> accounts = stream_interactor.get_accounts();
                Jid parsed_jid = null;
                try {
                    parsed_jid = new Jid(jid);
                } catch (InvalidJidError ignored) {
                    // Ignored
                }
                if (accounts.size == 1 && parsed_jid != null) {
                    Conversation conversation = stream_interactor.get_module(ConversationManager.IDENTITY).create_conversation(parsed_jid, accounts[0], Conversation.Type.CHAT);
                    stream_interactor.get_module(ConversationManager.IDENTITY).start_conversation(conversation);
                    controller.select_conversation(conversation);
                } else {
                    AddChatDialog dialog = new AddChatDialog(stream_interactor, stream_interactor.get_accounts());
                    dialog.set_filter(jid);
                    dialog.set_transient_for(window);
                    dialog.added.connect((conversation) => {
                        controller.select_conversation(conversation);
                    });
                    dialog.present();
                }
                break;
        }
    }

    private void create_actions() {
        SimpleAction preferences_action = new SimpleAction("preferences", null);
        preferences_action.activate.connect(show_preferences_window);
        add_action(preferences_action);
        set_accels_for_action("app.preferences", KEY_COMBINATION_SHOW_SETTINGS);

        SimpleAction preferences_account_action = new SimpleAction("preferences-account", VariantType.INT32);
        preferences_account_action.activate.connect((variant) => {
            Account? account = db.get_account_by_id(variant.get_int32());
            if (account == null) return;
            show_preferences_account_window(account);
        });
        add_action(preferences_account_action);

        SimpleAction about_action = new SimpleAction("about", null);
        about_action.activate.connect(show_about_window);
        add_action(about_action);

        SimpleAction quit_action = new SimpleAction("quit", null);
        quit_action.activate.connect(quit);
        add_action(quit_action);
        set_accels_for_action("app.quit", KEY_COMBINATION_QUIT);
        
        // Systray actions
        SimpleAction show_window_action = new SimpleAction("show-window", null);
        show_window_action.activate.connect(() => {
            if (systray_manager != null) {
                window.present();
            }
        });
        add_action(show_window_action);
        
        SimpleAction hide_window_action = new SimpleAction("hide-window", null);
        hide_window_action.activate.connect(() => {
            if (systray_manager != null && window != null) {
                window.hide();
            }
        });
        add_action(hide_window_action);

        SimpleAction open_conversation_action = new SimpleAction("open-conversation", VariantType.INT32);
        open_conversation_action.activate.connect((variant) => {
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(variant.get_int32());
            if (conversation != null) controller.select_conversation(conversation);
            Util.present_window(window);
        });
        add_action(open_conversation_action);

        SimpleAction open_conversation_details_action = new SimpleAction("open-conversation-details", new VariantType.tuple(new VariantType[]{VariantType.INT32, VariantType.STRING}));
        open_conversation_details_action.activate.connect((variant) => {
            int conversation_id = variant.get_child_value(0).get_int32();
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(conversation_id);
            if (conversation == null) return;

            string stack_value = variant.get_child_value(1).get_string();

            var conversation_details = ConversationDetails.setup_dialog(conversation, stream_interactor);
            conversation_details.stack.visible_child_name = stack_value;
            conversation_details.present(window);
        });
        add_action(open_conversation_details_action);

        SimpleAction deny_subscription_action = new SimpleAction("deny-subscription", VariantType.INT32);
        deny_subscription_action.activate.connect((variant) => {
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(variant.get_int32());
            if (conversation == null) return;
            stream_interactor.get_module(PresenceManager.IDENTITY).deny_subscription(conversation.account, conversation.counterpart);
        });
        add_action(deny_subscription_action);

        SimpleAction contacts_action = new SimpleAction("add_chat", null);
        contacts_action.activate.connect(() => {
            AddChatDialog add_chat_dialog = new AddChatDialog(stream_interactor, stream_interactor.get_accounts());
            add_chat_dialog.set_transient_for(window);
            add_chat_dialog.added.connect((conversation) => controller.select_conversation(conversation));
            add_chat_dialog.present();
        });
        add_action(contacts_action);
        set_accels_for_action("app.add_chat", KEY_COMBINATION_ADD_CHAT);

        SimpleAction conference_action = new SimpleAction("add_conference", null);
        conference_action.activate.connect(() => {
            AddConferenceDialog add_conference_dialog = new AddConferenceDialog(stream_interactor);
            add_conference_dialog.set_transient_for(window);
            add_conference_dialog.present();
        });
        add_action(conference_action);
        set_accels_for_action("app.add_conference", KEY_COMBINATION_ADD_CONFERENCE);

        SimpleAction accept_muc_invite_action = new SimpleAction("open-muc-join", VariantType.INT32);
        accept_muc_invite_action.activate.connect((variant) => {
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(variant.get_int32());
            if (conversation == null) return;
            show_join_muc_dialog(conversation.account, conversation.counterpart.to_string());
        });
        add_action(accept_muc_invite_action);

        SimpleAction accept_voice_request_action = new SimpleAction("accept-voice-request", new VariantType.tuple(new VariantType[]{VariantType.INT32, VariantType.STRING}));
        accept_voice_request_action.activate.connect((variant) => {
            int conversation_id = variant.get_child_value(0).get_int32();
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(conversation_id);
            if (conversation == null) return;

            string nick = variant.get_child_value(1).get_string();
            stream_interactor.get_module(MucManager.IDENTITY).change_role(conversation.account, conversation.counterpart, nick, "participant");
        });
        add_action(accept_voice_request_action);

        SimpleAction loop_conversations_action = new SimpleAction("loop_conversations", null);
        loop_conversations_action.activate.connect(() => { window.loop_conversations(false); });
        add_action(loop_conversations_action);
        set_accels_for_action("app.loop_conversations", KEY_COMBINATION_LOOP_CONVERSATIONS);

        SimpleAction loop_conversations_bw_action = new SimpleAction("loop_conversations_bw", null);
        loop_conversations_bw_action.activate.connect(() => { window.loop_conversations(true); });
        add_action(loop_conversations_bw_action);
        set_accels_for_action("app.loop_conversations_bw", KEY_COMBINATION_LOOP_CONVERSATIONS_REV);

        SimpleAction accept_call_action = new SimpleAction("accept-call", new VariantType.tuple(new VariantType[]{VariantType.INT32, VariantType.INT32}));
        accept_call_action.activate.connect((variant) => {
            int conversation_id = variant.get_child_value(0).get_int32();
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(conversation_id);
            if (conversation == null) return;

            int call_id = variant.get_child_value(1).get_int32();
            Call? call = stream_interactor.get_module(CallStore.IDENTITY).get_call_by_id(call_id, conversation);
            CallState? call_state = stream_interactor.get_module(Calls.IDENTITY).call_states[call];
            if (call_state == null) return;

            call_state.accept();

            var call_window = new CallWindow();
            call_window.controller = new CallWindowController(call_window, call_state, stream_interactor);
            call_window.present();
        });
        add_action(accept_call_action);

        SimpleAction deny_call_action = new SimpleAction("reject-call", new VariantType.tuple(new VariantType[]{VariantType.INT32, VariantType.INT32}));
        deny_call_action.activate.connect((variant) => {
            int conversation_id = variant.get_child_value(0).get_int32();
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(conversation_id);
            if (conversation == null) return;

            int call_id = variant.get_child_value(1).get_int32();
            Call? call = stream_interactor.get_module(CallStore.IDENTITY).get_call_by_id(call_id, conversation);
            CallState? call_state = stream_interactor.get_module(Calls.IDENTITY).call_states[call];
            if (call_state == null) return;

            call_state.reject();
        });
        add_action(deny_call_action);
    }

    private void show_preferences_window() {
        Ui.PreferencesDialog dialog = new Ui.PreferencesDialog();
        dialog.model.populate(db, stream_interactor);
        dialog.present(window);
    }

    private void show_preferences_account_window(Account account) {
        Ui.PreferencesDialog dialog = new Ui.PreferencesDialog();
        dialog.model.populate(db, stream_interactor);
        dialog.accounts_page.account_chosen(account);
        dialog.present(window);
    }

    private void show_about_window() {
        string? version = Dino.get_version().strip().length == 0 ? null : Dino.get_version();
        if (version != null && !version.contains("git")) {
            switch (version.substring(0, 3)) {
                case "0.2": version = @"$version - Mexican Caribbean Coral Reefs"; break;
                case "0.3": version = @"$version - Theikenmeer"; break;
                case "0.4": version = @"$version - Ilulissat"; break;
                case "0.5": version = @"$version - Alentejo"; break;
            }
        }

        Adw.AboutDialog about_dialog = new Adw.AboutDialog();
        about_dialog.application_icon = "im.dino.Dino";
        about_dialog.application_name = "DinoX";
        about_dialog.issue_url = "https://github.com/rallep71/dinox/issues";
        about_dialog.title = _("About DinoX");
        about_dialog.version = version;
        about_dialog.website = "https://github.com/rallep71/dinox";
        about_dialog.copyright = "Copyright © 2016-2025 - Dino Team\nCopyright © 2025 - Ralf Peter";
        about_dialog.license_type = License.GPL_3_0;
        about_dialog.comments = "Modern XMPP client with extended features";
        
        string[] developers = {
            "Dino Team (original authors)",
            "Ralf Peter (fork maintainer)",
            null
        };
        about_dialog.developers = developers;
        about_dialog.present(window);
    }

    private void show_join_muc_dialog(Account? account, string jid) {
        var window = new Gtk.Window();
        window.transient_for = this.window;
        window.modal = true;
        window.title = _("Join Channel");
        window.default_width = 400;
        window.default_height = 300;

        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        window.child = box;

        var header = new Adw.HeaderBar();
        box.append(header);

        var cancel_button = new Gtk.Button.with_label(_("Cancel"));
        cancel_button.clicked.connect(() => window.destroy());
        header.pack_start(cancel_button);

        var ok_button = new Gtk.Button.with_label(_("Join"));
        ok_button.add_css_class("suggested-action");
        header.pack_end(ok_button);

        ConferenceDetailsFragment conference_fragment = new ConferenceDetailsFragment(stream_interactor) { ok_button=ok_button };
        conference_fragment.jid = jid;
        if (account != null)  {
            conference_fragment.account = account;
        }
        box.append(conference_fragment);

        conference_fragment.joined.connect(() => {
            window.destroy();
        });

        window.present();
    }
}

