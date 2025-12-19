/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

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
    private const string[] KEY_COMBINATION_PANIC_WIPE = {"<Ctrl><Shift><Alt>P", null};

    public MainWindow window;
    public MainWindowController controller;
    private SystrayManager? systray_manager = null;

    public Database db { get; set; }
    public string? db_key { get; set; }
    public Dino.Entities.Settings settings { get; set; }
    private Config config { get; set; }
    public StreamInteractor stream_interactor { get; set; }
    public Plugins.Registry plugin_registry { get; set; default = new Plugins.Registry(); }
    public SearchPathGenerator? search_path_generator { get; set; }

    // Plugins are loaded after the encrypted DB has been unlocked.
    public Plugins.Loader? plugin_loader { get; set; }

    internal static bool print_version = false;
    private const OptionEntry[] options = {
        { "version", 0, 0, OptionArg.NONE, ref print_version, "Display version number", null },
        { null }
    };

    private bool core_ready = false;
    private bool pending_activate = false;
    private string? pending_xmpp_uri = null;

    private const int MAX_UNLOCK_TRIES = 3;
    private int unlock_failures = 0;
    private Adw.ApplicationWindow? unlock_parent = null;
    private bool unlock_window_centered_once = false;

    private bool is_first_run_no_db() {
        string db_path = Path.build_filename(Dino.Application.get_storage_dir(), "dino.db");
        return !FileUtils.test(db_path, FileTest.EXISTS);
    }

    private Adw.ApplicationWindow ensure_unlock_window() {
        if (unlock_parent == null) {
            unlock_parent = new Adw.ApplicationWindow(this);
            unlock_parent.title = "DinoX";
            unlock_parent.default_width = 460;
            unlock_parent.default_height = 260;
            unlock_parent.resizable = false;
            unlock_parent.modal = true;

            // Until the encrypted database is unlocked we don't have access to the user's
            // persisted color scheme preference. Use a consistent dark unlock screen.
            Adw.StyleManager.get_default().color_scheme = Adw.ColorScheme.FORCE_DARK;

            // Cinnamon/Muffin often places small modal windows at (0,0). Center it once on map.
            ((Gtk.Widget)unlock_parent).map.connect(() => {
                if (unlock_parent == null) return;
                if (unlock_window_centered_once) return;
                if (this.active_window != null) return;

                if (try_center_unlock_window_on_monitor((!)unlock_parent)) {
                    unlock_window_centered_once = true;
                }
            });
        }

        // Center the unlock window over the main window when available.
        if (this.active_window != null && this.active_window != unlock_parent) {
            unlock_parent.transient_for = this.active_window;
        }
        unlock_parent.present();
        return (!)unlock_parent;
    }

    private bool try_center_unlock_window_on_monitor(Adw.ApplicationWindow win) {
#if HAVE_X11
        // GTK4 has no generic "center on screen" API. On X11 we can move the window explicitly.
        Gdk.Display? gdk_display = win.get_display();
        Gdk.Surface? gdk_surface = win.get_surface();
        if (gdk_display == null || gdk_surface == null) return false;

        var x11_display = gdk_display as Gdk.X11.Display;
        var x11_surface = gdk_surface as Gdk.X11.Surface;
        if (x11_display == null || x11_surface == null) return false;

        Gdk.Monitor? monitor = gdk_display.get_monitor_at_surface(gdk_surface);
        if (monitor == null) return false;

        Gdk.Rectangle area = monitor.geometry;
        var x11_monitor = monitor as Gdk.X11.Monitor;
        if (x11_monitor != null) {
            area = x11_monitor.get_workarea();
        }

        int w = win.default_width > 0 ? win.default_width : 460;
        int h = win.default_height > 0 ? win.default_height : 260;

        int x = area.x + (area.width - w) / 2;
        int y = area.y + (area.height - h) / 2;
        if (x < area.x) x = area.x;
        if (y < area.y) y = area.y;

        unowned X.Display xdisplay = x11_display.get_xdisplay();
        xdisplay.move_window(x11_surface.get_xid(), x, y);
        xdisplay.flush();
        return true;
#else
        return false;
#endif
    }

    private void set_unlock_window_content(Gtk.Widget child) {
        var win = ensure_unlock_window();
        win.set_content(child);
    }

    private delegate void UnlockFormAction();

    private Gtk.Widget build_unlock_form(string heading, string body, Gtk.Widget form, string primary_label, UnlockFormAction primary_action) {
        var outer = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        outer.margin_top = 18;
        outer.margin_bottom = 18;
        outer.margin_start = 18;
        outer.margin_end = 18;

        var title = new Gtk.Label(heading);
        title.halign = Gtk.Align.START;
        title.wrap = true;
        title.add_css_class("title-2");

        var subtitle = new Gtk.Label(body);
        subtitle.halign = Gtk.Align.START;
        subtitle.wrap = true;

        outer.append(title);
        outer.append(subtitle);
        outer.append(form);

        var buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12);
        buttons.halign = Gtk.Align.END;

        var cancel_btn = new Gtk.Button.with_label(_("Beenden"));
        cancel_btn.clicked.connect(() => {
            Process.exit(0);
        });

        var primary_btn = new Gtk.Button.with_label(primary_label);
        primary_btn.add_css_class("suggested-action");
        primary_btn.clicked.connect(() => {
            primary_action();
        });

        buttons.append(cancel_btn);
        buttons.append(primary_btn);
        outer.append(buttons);

        var clamp = new Adw.Clamp() {
            maximum_size = 520,
            tightening_threshold = 520,
            child = outer,
            halign = Align.FILL,
            valign = Align.CENTER
        };

        return clamp;
    }

    public Application() throws Error {
        Object(application_id: "im.github.rallep71.DinoX", flags: ApplicationFlags.HANDLES_OPEN);
        Environment.set_application_name("DinoX");
        Gtk.Window.set_default_icon_name("im.github.rallep71.DinoX");
        add_main_option_entries(options);

        // Register core (libdino) option entries early (before command line parsing).
        ((Dino.Application)this).ensure_core_options_registered();

        // Panic wipe should be available even before unlocking.
        create_pre_unlock_actions();

        // Capture xmpp: URIs only while locked (avoid duplicate handling once core is ready).
        open.connect((files, hint) => {
            if (core_ready) return;
            if (files.length != 1) {
                warning("Can't handle more than one URI at once.");
                return;
            }
            File file = files[0];
            if (!file.has_uri_scheme("xmpp")) {
                warning("xmpp:-URI expected");
                return;
            }
            pending_xmpp_uri = file.get_uri();
            activate();
        });

        startup.connect(() => {
            if (print_version) {
                stdout.printf("Dino %s\n", Dino.get_version());
                stdout.flush();
                Process.exit(0);
            }

            // Require unlock before initializing the core.
            prompt_unlock();
        });

        activate.connect(() => {
            if (!core_ready) {
                pending_activate = true;
                return;
            }
            if (window == null) {
                controller = new MainWindowController(this, stream_interactor, db);
                config = new Config(db);
                window = new MainWindow(this, stream_interactor, db, config);
                controller.set_window(window);
                // Always enable hide_on_close - we'll control quit behavior in close_request handler
                window.hide_on_close = true;
                
                // Connect systray to window
                if (systray_manager != null) {
                    systray_manager.set_window(window);
                }
            }
            window.present();

            if (pending_xmpp_uri != null) {
                handle_pending_xmpp_uri((!)pending_xmpp_uri);
                pending_xmpp_uri = null;
            }
        });
    }

    private void prompt_unlock() {
        if (core_ready) return;

        if (is_first_run_no_db()) {
            prompt_set_password();
            return;
        }

        var password_entry = new Gtk.PasswordEntry();
        password_entry.hexpand = true;
        password_entry.show_peek_icon = true;

        var form = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        var label = new Gtk.Label(_("Passwort"));
        label.halign = Gtk.Align.START;
        form.append(label);
        form.append(password_entry);

        string heading = _("DinoX entsperren");
        string body = _("Bitte Passwort eingeben, um die verschlüsselte Datenbank zu öffnen.");
        if (unlock_failures > 0) {
            body = _("Falsches Passwort. Versuch %d/%d").printf(unlock_failures + 1, MAX_UNLOCK_TRIES);
        }

        UnlockFormAction do_unlock = () => {
            string password = password_entry.text ?? "";
            if (password.strip().length == 0) {
                unlock_failures++;
                warning("Unlock failed: empty password");
                if (unlock_failures >= MAX_UNLOCK_TRIES) {
                    panic_wipe_and_exit();
                }
                prompt_unlock();
                return;
            }
            try {
                this.db_key = password;
                ((Dino.Application)this).init();

                if (plugin_loader != null) {
                    plugin_loader.load_all();
                }
                create_ui_actions();
                core_ready = true;

                apply_color_scheme(settings.color_scheme);
                settings.notify["color-scheme"].connect(() => {
                    apply_color_scheme(settings.color_scheme);
                });

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
                    var desktop_env = Environment.get_variable("XDG_CURRENT_DESKTOP");
                    if (desktop_env == null || !desktop_env.down().contains("gnome")) {
                        if (this.active_window != null) {
//                            this.active_window.urgency_hint = true;
                        }
                    }
                });
                stream_interactor.get_module(FileManager.IDENTITY).add_metadata_provider(new Util.AudioVideoFileMetadataProvider());

                systray_manager = new SystrayManager(this);

                if (unlock_parent != null) {
                    unlock_parent.close();
                    unlock_parent = null;
                }

                if (pending_activate) {
                    pending_activate = false;
                    activate();
                }
            } catch (Error e) {
                unlock_failures++;
                warning("Unlock failed: %s", e.message);
                if (unlock_failures >= MAX_UNLOCK_TRIES) {
                    panic_wipe_and_exit();
                }
                prompt_unlock();
            }
        };

        password_entry.activate.connect(() => do_unlock());
        set_unlock_window_content(build_unlock_form(heading, body, form, _("Entsperren"), do_unlock));
    }

    private void prompt_set_password() {
        if (core_ready) return;

        var password_entry = new Gtk.PasswordEntry();
        password_entry.hexpand = true;
        password_entry.show_peek_icon = true;

        var password_entry_confirm = new Gtk.PasswordEntry();
        password_entry_confirm.hexpand = true;
        password_entry_confirm.show_peek_icon = true;

        var form = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        var l1 = new Gtk.Label(_("Passwort"));
        l1.halign = Gtk.Align.START;
        var l2 = new Gtk.Label(_("Passwort bestätigen"));
        l2.halign = Gtk.Align.START;
        form.append(l1);
        form.append(password_entry);
        form.append(l2);
        form.append(password_entry_confirm);

        string heading = _("Passwort festlegen");
        string body = _("Bei der ersten Nutzung musst du ein Passwort setzen. Ohne Passwort kann DinoX die verschlüsselte Datenbank nicht öffnen.");
        if (unlock_failures > 0) {
            body = _("Ungültiges Passwort. Versuch %d/%d").printf(unlock_failures + 1, MAX_UNLOCK_TRIES);
        }

        UnlockFormAction do_set = () => {
            string password = password_entry.text ?? "";
            string password2 = password_entry_confirm.text ?? "";

            if (password.strip().length == 0) {
                unlock_failures++;
                warning("Set password failed: empty password");
            } else if (password != password2) {
                unlock_failures++;
                warning("Set password failed: mismatch");
            } else {
                try {
                    this.db_key = password;
                    ((Dino.Application)this).init();

                    if (plugin_loader != null) {
                        plugin_loader.load_all();
                    }
                    create_ui_actions();
                    core_ready = true;

                    apply_color_scheme(settings.color_scheme);
                    settings.notify["color-scheme"].connect(() => {
                        apply_color_scheme(settings.color_scheme);
                    });

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
                        var desktop_env = Environment.get_variable("XDG_CURRENT_DESKTOP");
                        if (desktop_env == null || !desktop_env.down().contains("gnome")) {
                            if (this.active_window != null) {
//                            this.active_window.urgency_hint = true;
                            }
                        }
                    });
                    stream_interactor.get_module(FileManager.IDENTITY).add_metadata_provider(new Util.AudioVideoFileMetadataProvider());

                    systray_manager = new SystrayManager(this);

                    if (unlock_parent != null) {
                        unlock_parent.close();
                        unlock_parent = null;
                    }
                    if (pending_activate) {
                        pending_activate = false;
                        activate();
                    }
                    return;
                } catch (Error e) {
                    unlock_failures++;
                    warning("Set password failed: %s", e.message);
                }
            }

            if (unlock_failures >= MAX_UNLOCK_TRIES) {
                panic_wipe_and_exit();
            }

            prompt_set_password();
        };

        password_entry_confirm.activate.connect(() => do_set());
        set_unlock_window_content(build_unlock_form(heading, body, form, _("Passwort setzen"), do_set));
    }

    private void create_pre_unlock_actions() {
        SimpleAction panic_wipe_action = new SimpleAction("panic-wipe", null);
        panic_wipe_action.activate.connect((variant) => {
            panic_wipe_and_exit();
        });
        add_action(panic_wipe_action);
        set_accels_for_action("app.panic-wipe", KEY_COMBINATION_PANIC_WIPE);
    }

    private void handle_pending_xmpp_uri(string uri) {
        if (!uri.contains(":")) {
            warning("Invalid URI");
            return;
        }
        string r = uri.split(":", 2)[1];
        string[] m = r.split("?", 2);
        string jid = m[0];
        while (jid.length > 0 && jid[0] == '/') {
            jid = jid.substring(1);
        }
        jid = Uri.unescape_string(jid);
        try {
            jid = new Xmpp.Jid(jid).to_string();
        } catch (Xmpp.InvalidJidError e) {
            warning("Received invalid jid in xmpp:-URI: %s", e.message);
        }
        string query = "message";
        Gee.Map<string, string> options = new Gee.HashMap<string, string>();
        if (m.length == 2) {
            string[] cmds = m[1].split(";");
            query = cmds[0];
            for (int i = 1; i < cmds.length; ++i) {
                string[] opt = cmds[i].split("=", 2);
                options[Uri.unescape_string(opt[0])] = opt.length == 2 ? Uri.unescape_string(opt[1]) : "";
            }
        }
        handle_uri(jid, query, options);
    }

    private void panic_wipe_and_exit() {
        try {
            wipe_dir(Path.build_filename(Environment.get_user_data_dir(), "dinox"));
            wipe_dir(Path.build_filename(Environment.get_user_config_dir(), "dinox"));
            wipe_dir(Path.build_filename(Environment.get_user_cache_dir(), "dinox"));
        } catch (Error e) {
            warning("Panic wipe failed: %s", e.message);
        }
        Process.exit(0);
    }

    private void wipe_dir(string path) throws Error {
        if (!FileUtils.test(path, FileTest.EXISTS)) return;
        File root = File.new_for_path(path);
        wipe_file_recursive(root);
    }

    private void wipe_file_recursive(File f) throws Error {
        FileType t = f.query_file_type(FileQueryInfoFlags.NONE, null);

        if (t == FileType.DIRECTORY) {
            FileEnumerator? en = null;
            try {
                en = f.enumerate_children("standard::name,standard::type", FileQueryInfoFlags.NONE, null);
                FileInfo? info;
                while ((info = en.next_file(null)) != null) {
                    File child = f.get_child(info.get_name());
                    wipe_file_recursive(child);
                }
            } catch (Error e) {
                // Best effort.
            }
            try { f.delete(null); } catch (Error e) { }
        } else {
            try { f.delete(null); } catch (Error e) { }
        }
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
            case "pubsub":
                // Example: xmpp:romeo@montague.lit?pubsub;action=retrieve;node=urn:xmpp:stickers:0;item=EpRv...
                if (!options.has_key("action") || options["action"] != "retrieve") return;
                if (!options.has_key("node") || options["node"] != Xmpp.Xep.Stickers.NS_URI) return;
                if (!options.has_key("item") || options["item"] == "") return;
                try {
                    var src = new Xmpp.Jid(jid);
                    var dialog = new Dino.Ui.StickerPackImportDialog(stream_interactor, src, options["node"], options["item"]);
                    dialog.set_transient_for(window);
                    dialog.present();
                } catch (Xmpp.InvalidJidError e) {
                    warning("Invalid JID in pubsub URI: %s", e.message);
                }
                break;
        }
    }

    private void create_ui_actions() {
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

        SimpleAction set_status_action = new SimpleAction("set-status", VariantType.STRING);
        set_status_action.activate.connect((variant) => {
            string status = variant.get_string();
            stream_interactor.get_module(PresenceManager.IDENTITY).set_status(status, null);
        });
        add_action(set_status_action);

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
        dialog.backup_requested.connect(() => {
            string data_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox");
            create_backup(data_dir);
        });
        dialog.restore_backup_requested.connect(() => restore_from_backup());
        dialog.show_data_location.connect(() => show_data_location_dialog());
        dialog.change_db_password_requested.connect(() => show_change_db_password_dialog());
        dialog.clear_cache_requested.connect(() => clear_cache());
        dialog.reset_database_requested.connect(() => reset_database());
        dialog.factory_reset_requested.connect(() => factory_reset());
        dialog.present(window);
    }

    private void show_change_db_password_dialog() {
        if (this.db_key == null) {
            warning("Cannot change database password: db_key is not set");
            return;
        }

        var old_entry = new Gtk.PasswordEntry();
        old_entry.hexpand = true;
        old_entry.show_peek_icon = true;

        var new_entry = new Gtk.PasswordEntry();
        new_entry.hexpand = true;
        new_entry.show_peek_icon = true;

        var new_entry_confirm = new Gtk.PasswordEntry();
        new_entry_confirm.hexpand = true;
        new_entry_confirm.show_peek_icon = true;

        var grid = new Gtk.Grid();
        grid.row_spacing = 12;
        grid.column_spacing = 12;
        grid.margin_top = 6;
        grid.margin_bottom = 6;
        grid.margin_start = 6;
        grid.margin_end = 6;

        var l_old = new Gtk.Label(_("Aktuelles Passwort"));
        l_old.halign = Gtk.Align.START;
        var l_new = new Gtk.Label(_("Neues Passwort"));
        l_new.halign = Gtk.Align.START;
        var l_new2 = new Gtk.Label(_("Neues Passwort bestätigen"));
        l_new2.halign = Gtk.Align.START;

        grid.attach(l_old, 0, 0, 1, 1);
        grid.attach(old_entry, 0, 1, 1, 1);
        grid.attach(l_new, 0, 2, 1, 1);
        grid.attach(new_entry, 0, 3, 1, 1);
        grid.attach(l_new2, 0, 4, 1, 1);
        grid.attach(new_entry_confirm, 0, 5, 1, 1);

        var dialog = new Adw.AlertDialog(
            _("Datenbank-Passwort ändern"),
            _("Dieses Passwort wird verwendet, um deine lokalen DinoX-Daten zu verschlüsseln.")
        );
        dialog.extra_child = grid;
        dialog.add_response("cancel", _("Abbrechen"));
        dialog.add_response("change", _("Ändern"));
        dialog.default_response = "change";
        dialog.close_response = "cancel";

        dialog.response.connect((response) => {
            if (response != "change") return;

            string old_pw = old_entry.text ?? "";
            string new_pw = new_entry.text ?? "";
            string new_pw2 = new_entry_confirm.text ?? "";

            if (old_pw != (!)this.db_key) {
                warning("Change DB password failed: wrong current password");
                Idle.add(() => { show_change_db_password_dialog(); return false; });
                return;
            }
            if (new_pw.strip().length == 0) {
                warning("Change DB password failed: empty new password");
                Idle.add(() => { show_change_db_password_dialog(); return false; });
                return;
            }
            if (new_pw != new_pw2) {
                warning("Change DB password failed: mismatch");
                Idle.add(() => { show_change_db_password_dialog(); return false; });
                return;
            }

            try {
                db.rekey(new_pw);
                this.db_key = new_pw;
            } catch (Error e) {
                warning("Change DB password failed: %s", e.message);
                Idle.add(() => { show_change_db_password_dialog(); return false; });
                return;
            }
        });

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
        about_dialog.application_icon = "im.github.rallep71.DinoX";
        about_dialog.application_name = "DinoX";
        about_dialog.issue_url = "https://github.com/rallep71/dinox/issues";
        about_dialog.title = _("About DinoX");
        about_dialog.version = version;
        about_dialog.website = "https://github.com/rallep71/dinox";
        about_dialog.copyright = "Copyright © 2025 - Ralf Peter\nCopyright © 2016-2025 - Dino Team";
        about_dialog.license_type = License.GPL_3_0;
        about_dialog.comments = _("Modern XMPP client with extended features");
        
        // Add debug info with data location
        string config_dir = Path.build_filename(Environment.get_user_config_dir(), "dinox");
        string data_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox");
        string cache_dir = Path.build_filename(Environment.get_user_cache_dir(), "dinox");
        
        string support_info = _("User Data Locations") + """
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

""" + _("Configuration:") + """
%s

""" + _("Data & Database:") + """
%s

""" + _("Cache:") + """
%s

ℹ """ + _("Info:") + """
""" + _("Your personal data (accounts, messages, files) is stored separately from the application.") + """

""" + _("When you update DinoX, your data remains intact.") + """

""" + _("Use Settings → General → Backup User Data to create a backup.");
        support_info = support_info.printf(config_dir, data_dir, cache_dir);
        
        about_dialog.debug_info = support_info;
        about_dialog.debug_info_filename = "dinox-data-locations.txt";
        
        string[] developers = {
            "Ralf Peter (DinoX Maintainer)",
            "Dino Team (Dino Project)",
            null
        };
        about_dialog.developers = developers;
        
        about_dialog.present(window);
    }
    
    public void restore_from_backup() {
        var file_chooser = new Gtk.FileDialog();
        file_chooser.title = _("Select Backup File");
        file_chooser.modal = true;
        
        // Filter for backup files (both encrypted and unencrypted)
        var filter = new Gtk.FileFilter();
        filter.add_pattern("*.tar.gz");
        filter.add_pattern("*.tar.gz.gpg");
        filter.add_pattern("*.tgz");
        filter.set_filter_name(_("Backup Files (*.tar.gz, *.tar.gz.gpg)"));
        
        var filters = new GLib.ListStore(typeof(Gtk.FileFilter));
        filters.append(filter);
        file_chooser.filters = filters;
        file_chooser.default_filter = filter;
        
        file_chooser.open.begin(window, null, (obj, res) => {
            GLib.File? file = null;
            try {
                file = file_chooser.open.end(res);
            } catch (Error err) {
                // User cancelled
                return;
            }
            
            if (file != null) {
                string path = file.get_path();
                // Check if encrypted backup
                if (path.has_suffix(".gpg")) {
                    show_password_dialog_for_restore(path);
                } else {
                    confirm_restore_backup(path, null);
                }
            }
        });
    }
    
    private void show_password_dialog_for_restore(string backup_path) {
        var dialog = new Adw.AlertDialog(
            _("Enter Backup Password"),
            _("This backup is encrypted. Please enter the password to decrypt it.")
        );
        
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
        box.margin_start = 24;
        box.margin_end = 24;
        
        var password_entry = new Gtk.PasswordEntry();
        password_entry.show_peek_icon = true;
        password_entry.placeholder_text = _("Password");
        password_entry.activates_default = true;
        
        box.append(password_entry);
        dialog.set_extra_child(box);
        
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("ok", _("Decrypt & Restore"));
        dialog.set_response_appearance("ok", Adw.ResponseAppearance.SUGGESTED);
        dialog.set_default_response("ok");
        dialog.set_close_response("cancel");
        
        // Enable OK button only when password is entered
        dialog.set_response_enabled("ok", false);
        password_entry.changed.connect(() => {
            dialog.set_response_enabled("ok", password_entry.text.length > 0);
        });
        
        dialog.response.connect((response) => {
            if (response == "ok" && password_entry.text.length > 0) {
                confirm_restore_backup(backup_path, password_entry.text);
            }
        });
        
        dialog.present(window);
    }
    
    private void confirm_restore_backup(string backup_path, string? password) {
        var dialog = new Adw.AlertDialog(
            _("Restore from Backup"),
            _("This will replace all current data with the backup.\n\n<b>Current accounts, messages and settings will be overwritten!</b>\n\nDinoX will restart after restoring.")
        );
        dialog.body_use_markup = true;
        
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("restore", _("Restore Backup"));
        dialog.set_response_appearance("restore", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_default_response("cancel");
        dialog.set_close_response("cancel");
        
        dialog.response.connect((response) => {
            if (response == "restore") {
                perform_restore_backup(backup_path, password);
            }
        });
        
        dialog.present(window);
    }
    
    private void perform_restore_backup(string backup_path, string? password = null) {
        // Show progress dialog with spinner
        var progress_dialog = new Adw.AlertDialog(
            password != null ? _("Decrypting Backup...") : _("Restoring Backup..."),
            _("Please wait, this may take a moment...")
        );
        
        var spinner = new Gtk.Spinner();
        spinner.spinning = true;
        spinner.width_request = 48;
        spinner.height_request = 48;
        spinner.halign = Gtk.Align.CENTER;
        spinner.margin_top = 12;
        spinner.margin_bottom = 12;
        
        progress_dialog.set_extra_child(spinner);
        progress_dialog.set_close_response("none"); // Prevent closing
        progress_dialog.present(window);
        
        // Capture password for use in thread
        string? restore_password = password;
        string backup_file = backup_path;
        
        // Run in background thread
        new Thread<void*>("restore-backup", () => {
            string tar_path = backup_file;
            bool decrypt_success = true;
            string? error_message = null;
            
            // If encrypted, decrypt first
            if (restore_password != null && backup_file.has_suffix(".gpg")) {
                tar_path = Path.build_filename(Environment.get_tmp_dir(), "dinox-restore-temp.tar.gz");
                
                // Update dialog to show decryption progress
                Idle.add(() => {
                    progress_dialog.heading = _("Decrypting Backup...");
                    progress_dialog.body = _("Decrypting encrypted backup file...");
                    return false;
                });
                
                // Use gpg with passphrase via command line
                // Note: We need to use spawn_command_line_sync for proper argument handling
                string gpg_command = "gpg --batch --yes --decrypt --pinentry-mode loopback --passphrase %s --output %s %s".printf(
                    Shell.quote(restore_password),
                    Shell.quote(tar_path),
                    Shell.quote(backup_file)
                );
                
                int exit_status = -1;
                string? stdout_str = null;
                string? stderr_str = null;
                try {
                    Process.spawn_command_line_sync(
                        gpg_command,
                        out stdout_str,
                        out stderr_str,
                        out exit_status
                    );
                    decrypt_success = (exit_status == 0);
                    if (!decrypt_success) {
                        error_message = stderr_str ?? "GPG decryption failed";
                        warning("GPG decrypt failed (exit %d): %s", exit_status, error_message);
                    }
                } catch (Error err) {
                    decrypt_success = false;
                    error_message = err.message;
                    warning("Failed to run GPG decrypt: %s", err.message);
                }
                
                if (!decrypt_success) {
                    Idle.add(() => {
                        progress_dialog.force_close();
                        
                        var error_dialog = new Adw.AlertDialog(
                            _("Decryption Failed"),
                            _("Could not decrypt the backup file.\n\nPlease check if the password is correct.")
                        );
                        error_dialog.add_response("ok", _("OK"));
                        error_dialog.present(window);
                        return false;
                    });
                    return null;
                }
            }
            
            // Update dialog to show extraction progress
            Idle.add(() => {
                progress_dialog.heading = _("Restoring Backup...");
                progress_dialog.body = _("Extracting files from backup...");
                return false;
            });
            
            // Extract backup to user directories
            string[] argv = {
                "tar",
                "-xzf",
                tar_path,
                "-C", Environment.get_user_data_dir(),
                "--overwrite"
            };
            
            string? stderr_str = null;
            int exit_status = -1;
            bool success = false;
            
            try {
                Process.spawn_sync(
                    null,
                    argv,
                    null,
                    SpawnFlags.SEARCH_PATH,
                    null,
                    null,
                    out stderr_str,
                    out exit_status
                );
                success = (exit_status == 0);
                if (!success && stderr_str != null) {
                    error_message = stderr_str;
                }
            } catch (Error err) {
                error_message = err.message;
                warning("Failed to restore backup: %s", err.message);
            }
            
            // Also extract config if it exists in the backup
            if (success) {
                string[] argv_config = {
                    "tar",
                    "-xzf",
                    tar_path,
                    "-C", Environment.get_user_config_dir(),
                    "--overwrite",
                    "--strip-components=0"
                };
                
                try {
                    Process.spawn_sync(
                        null,
                        argv_config,
                        null,
                        SpawnFlags.SEARCH_PATH,
                        null,
                        null,
                        null,
                        null
                    );
                } catch (Error err) {
                    // Config extraction might fail if backup doesn't have config, that's ok
                }
            }
            
            // Clean up temporary decrypted file if we created one
            if (restore_password != null && tar_path != backup_file) {
                FileUtils.unlink(tar_path);
            }
            
            if (success) {
                // Sync filesystem to ensure all files are written
                try {
                    Process.spawn_command_line_sync("sync", null, null, null);
                } catch (Error err) {
                    // Ignore sync errors
                }
                
                // Clear OMEMO sessions to force re-negotiation after restore
                clear_omemo_sessions_after_restore();
                
                Idle.add(() => {
                    progress_dialog.heading = _("Restore Complete!");
                    progress_dialog.body = _("DinoX will now restart...");
                    
                    // Restart after a short delay to ensure files are synced
                    Timeout.add(2000, () => {
                        restart_application();
                        return false;
                    });
                    return false;
                });
            } else {
                Idle.add(() => {
                    progress_dialog.force_close();
                    
                    var error_dialog = new Adw.AlertDialog(
                        _("Restore Failed"),
                        _("Could not restore the backup file.\n\nError: %s").printf(error_message ?? _("Unknown error"))
                    );
                    error_dialog.add_response("ok", _("OK"));
                    error_dialog.present(window);
                    return false;
                });
            }
            
            return null;
        });
    }
    
    private void clear_omemo_sessions_after_restore() {
        // After restoring from backup, OMEMO sessions may be stale.
        // The backup contains old session data that doesn't match the current
        // server state. We need to clear all sessions to force re-negotiation.
        
        // Try both possible locations for omemo.db
        string[] possible_paths = {
            Path.build_filename(Environment.get_user_data_dir(), "dinox", "omemo.db"),
            Path.build_filename(Environment.get_user_config_dir(), "dinox", "omemo.db")
        };
        
        foreach (string omemo_db_path in possible_paths) {
            if (FileUtils.test(omemo_db_path, FileTest.EXISTS)) {
                try {
                    // Use sqlite3 command to clear sessions table
                    string[] argv = {
                        "sqlite3",
                        omemo_db_path,
                        "DELETE FROM session;"
                    };
                    
                    Process.spawn_sync(
                        null,
                        argv,
                        null,
                        SpawnFlags.SEARCH_PATH,
                        null,
                        null,
                        null,
                        null
                    );
                    
                    debug("Cleared OMEMO sessions from %s after backup restore", omemo_db_path);
                } catch (Error err) {
                    warning("Failed to clear OMEMO sessions: %s", err.message);
                }
            }
        }
    }
    
    private void show_data_location_dialog() {
        string config_dir = Path.build_filename(Environment.get_user_config_dir(), "dinox");
        string data_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox");
        string cache_dir = Path.build_filename(Environment.get_user_cache_dir(), "dinox");
        
        var dialog = new Adw.AlertDialog(
            _("User Data Locations"),
            null
        );
        
        string message = """<b>%s</b>
%s

<b>%s</b>
%s

<b>%s</b>
%s

<small>%s</small>""".printf(
            Markup.escape_text(_("Configuration:")),
            Markup.escape_text(config_dir),
            Markup.escape_text(_("Data & Database:")),
            Markup.escape_text(data_dir),
            Markup.escape_text(_("Cache:")),
            Markup.escape_text(cache_dir),
            Markup.escape_text(_("Your personal data (accounts, messages, files) is stored separately from the application. When you update DinoX, your data remains intact."))
        );
        
        dialog.body_use_markup = true;
        dialog.body = message;
        dialog.add_response("close", _("Close"));
        dialog.set_response_appearance("close", Adw.ResponseAppearance.DEFAULT);
        dialog.present(window);
    }
    
    private void clear_cache() {
        string cache_dir = Path.build_filename(Environment.get_user_cache_dir(), "dinox");
        
        var dialog = new Adw.AlertDialog(
            _("Clear Cache"),
            _("This will delete cached files, avatars and previews.\n\nThey will be re-downloaded when needed.")
        );
        
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("clear", _("Clear Cache"));
        dialog.set_response_appearance("clear", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_default_response("cancel");
        dialog.set_close_response("cancel");
        
        dialog.response.connect((response) => {
            if (response == "clear") {
                perform_clear_cache(cache_dir);
            }
        });
        
        dialog.present(window);
    }
    
    private void perform_clear_cache(string cache_dir) {
        var toast_overlay = window.get_first_child() as Adw.ToastOverlay;
        
        new Thread<void*>("clear-cache", () => {
            int64 freed_bytes = 0;
            bool success = true;
            
            try {
                freed_bytes = delete_directory_contents(cache_dir);
            } catch (Error err) {
                success = false;
                warning("Failed to clear cache: %s", err.message);
            }
            
            Idle.add(() => {
                if (toast_overlay != null) {
                    Adw.Toast toast;
                    if (success) {
                        string size_str = format_size(freed_bytes);
                        toast = new Adw.Toast(_("Cache cleared (%s freed)").printf(size_str));
                        toast.timeout = 3;
                    } else {
                        toast = new Adw.Toast(_("Failed to clear cache"));
                        toast.timeout = 3;
                    }
                    toast_overlay.add_toast(toast);
                }
                return false;
            });
            
            return null;
        });
    }
    
    private int64 delete_directory_contents(string path) throws Error {
        int64 total_size = 0;
        var dir = Dir.open(path);
        string? name;
        while ((name = dir.read_name()) != null) {
            string full_path = Path.build_filename(path, name);
            FileInfo info = File.new_for_path(full_path).query_info(
                FileAttribute.STANDARD_TYPE + "," + FileAttribute.STANDARD_SIZE, 
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS
            );
            
            if (info.get_file_type() == FileType.DIRECTORY) {
                total_size += delete_directory_contents(full_path);
                DirUtils.remove(full_path);
            } else {
                total_size += info.get_size();
                FileUtils.unlink(full_path);
            }
        }
        return total_size;
    }
    
    private void reset_database() {
        var dialog = new Adw.AlertDialog(
            _("Reset Database"),
            _("This will delete all messages, files and OMEMO encryption keys.\n\n<b>Your accounts will remain, but you will lose all chat history and need to re-verify encryption with your contacts.</b>\n\nThis action cannot be undone!")
        );
        dialog.body_use_markup = true;
        
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("reset", _("Reset Database"));
        dialog.set_response_appearance("reset", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_default_response("cancel");
        dialog.set_close_response("cancel");
        
        dialog.response.connect((response) => {
            if (response == "reset") {
                perform_reset_database();
            }
        });
        
        dialog.present(window);
    }
    
    private void perform_reset_database() {
        string data_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox");
        string db_path = Path.build_filename(data_dir, "dino.db");
        
        // Close the database before deleting
        // We need to restart the app after this
        
        var toast_overlay = window.get_first_child() as Adw.ToastOverlay;
        if (toast_overlay != null) {
            var toast = new Adw.Toast(_("Resetting database... DinoX will restart."));
            toast.timeout = 2;
            toast_overlay.add_toast(toast);
        }
        
        // Delay the actual reset to let the toast show
        Timeout.add(2000, () => {
            // Delete the database file
            FileUtils.unlink(db_path);
            FileUtils.unlink(db_path + "-shm");
            FileUtils.unlink(db_path + "-wal");
            
            // Also delete OMEMO data
            string omemo_dir = Path.build_filename(data_dir, "omemo");
            try {
                delete_directory_contents(omemo_dir);
                DirUtils.remove(omemo_dir);
            } catch (Error err) {
                // Ignore if doesn't exist
            }
            
            // Restart the application
            restart_application();
            return false;
        });
    }
    
    private void factory_reset() {
        var dialog = new Adw.AlertDialog(
            _("Factory Reset"),
            _("<b>⚠️ WARNING: This will delete ALL data!</b>\n\n• All accounts\n• All messages and files\n• All encryption keys\n• All settings\n\nThis is irreversible. Make sure to create a backup first!")
        );
        dialog.body_use_markup = true;
        
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("backup", _("Create Backup First"));
        dialog.add_response("reset", _("Delete Everything"));
        dialog.set_response_appearance("reset", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_default_response("cancel");
        dialog.set_close_response("cancel");
        
        dialog.response.connect((response) => {
            if (response == "reset") {
                // Show second confirmation
                confirm_factory_reset();
            } else if (response == "backup") {
                string data_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox");
                create_backup(data_dir);
            }
        });
        
        dialog.present(window);
    }
    
    private void confirm_factory_reset() {
        var dialog = new Adw.AlertDialog(
            _("Are you absolutely sure?"),
            _("Type 'DELETE' to confirm factory reset.\n\nThis will permanently remove all your DinoX data.")
        );
        
        var entry = new Gtk.Entry();
        entry.placeholder_text = "DELETE";
        entry.margin_start = 24;
        entry.margin_end = 24;
        dialog.set_extra_child(entry);
        
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("confirm", _("Confirm Delete"));
        dialog.set_response_appearance("confirm", Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_default_response("cancel");
        dialog.set_close_response("cancel");
        
        // Disable confirm button until correct text is entered
        dialog.set_response_enabled("confirm", false);
        entry.changed.connect(() => {
            dialog.set_response_enabled("confirm", entry.text == "DELETE");
        });
        
        dialog.response.connect((response) => {
            if (response == "confirm" && entry.text == "DELETE") {
                perform_factory_reset();
            }
        });
        
        dialog.present(window);
    }
    
    private void perform_factory_reset() {
        string data_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox");
        string config_dir = Path.build_filename(Environment.get_user_config_dir(), "dinox");
        string cache_dir = Path.build_filename(Environment.get_user_cache_dir(), "dinox");
        
        var toast_overlay = window.get_first_child() as Adw.ToastOverlay;
        if (toast_overlay != null) {
            var toast = new Adw.Toast(_("Factory reset in progress... DinoX will restart."));
            toast.timeout = 2;
            toast_overlay.add_toast(toast);
        }
        
        Timeout.add(2000, () => {
            // Delete everything
            try {
                delete_directory_contents(data_dir);
                DirUtils.remove(data_dir);
            } catch (Error err) {
                warning("Failed to delete data dir: %s", err.message);
            }
            
            try {
                delete_directory_contents(config_dir);
                DirUtils.remove(config_dir);
            } catch (Error err) {
                warning("Failed to delete config dir: %s", err.message);
            }
            
            try {
                delete_directory_contents(cache_dir);
                DirUtils.remove(cache_dir);
            } catch (Error err) {
                warning("Failed to delete cache dir: %s", err.message);
            }
            
            // Restart the application
            restart_application();
            return false;
        });
    }
    
    private void restart_application() {
        // Get the executable path
        string? exe_path = null;
        try {
            exe_path = FileUtils.read_link("/proc/self/exe");
        } catch (Error err) {
            // Fallback to argv[0]
            warning("Could not read /proc/self/exe: %s", err.message);
        }
        
        // First quit the current instance completely, then spawn new one
        // We use a small delay script to ensure the old process is gone
        if (exe_path != null) {
            try {
                // Use bash to delay the restart slightly to ensure clean shutdown
                string restart_cmd = "sleep 0.5 && %s &".printf(Shell.quote(exe_path));
                string[] spawn_args = { "bash", "-c", restart_cmd };
                Process.spawn_async(null, spawn_args, null, SpawnFlags.SEARCH_PATH, null, null);
            } catch (Error err) {
                warning("Failed to restart: %s", err.message);
            }
        }
        
        // Hard exit to prevent any cleanup that might overwrite restored data
        // This is intentional after backup restore to preserve the restored database
        Process.exit(0);
    }
    
    private void create_backup(string data_dir) {
        // First ask if user wants to encrypt the backup
        var encrypt_dialog = new Adw.AlertDialog(
            _("Backup Encryption"),
            _("Do you want to encrypt the backup with a password?\n\nEncrypted backups are more secure but require the password to restore.")
        );
        
        encrypt_dialog.add_response("no", _("No Encryption"));
        encrypt_dialog.add_response("yes", _("Encrypt with Password"));
        encrypt_dialog.set_response_appearance("yes", Adw.ResponseAppearance.SUGGESTED);
        encrypt_dialog.set_default_response("no");
        encrypt_dialog.set_close_response("no");
        
        encrypt_dialog.response.connect((response) => {
            if (response == "yes") {
                show_password_dialog_for_backup(data_dir);
            } else {
                show_backup_file_chooser(data_dir, null);
            }
        });
        
        encrypt_dialog.present(window);
    }
    
    private void show_password_dialog_for_backup(string data_dir) {
        var dialog = new Adw.AlertDialog(
            _("Set Backup Password"),
            _("Enter a password to encrypt the backup.\n\n<b>Important:</b> Remember this password! Without it, the backup cannot be restored.")
        );
        dialog.body_use_markup = true;
        
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        box.margin_start = 24;
        box.margin_end = 24;
        
        var password_label = new Gtk.Label(_("Password (minimum 4 characters)"));
        password_label.halign = Gtk.Align.START;
        password_label.add_css_class("dim-label");
        
        var password_entry = new Gtk.PasswordEntry();
        password_entry.show_peek_icon = true;
        password_entry.placeholder_text = _("Password");
        
        var confirm_label = new Gtk.Label(_("Confirm Password"));
        confirm_label.halign = Gtk.Align.START;
        confirm_label.add_css_class("dim-label");
        confirm_label.margin_top = 8;
        
        var confirm_entry = new Gtk.PasswordEntry();
        confirm_entry.show_peek_icon = true;
        confirm_entry.placeholder_text = _("Confirm Password");
        confirm_entry.activates_default = true;
        
        var status_label = new Gtk.Label("");
        status_label.halign = Gtk.Align.START;
        status_label.add_css_class("dim-label");
        status_label.margin_top = 8;
        
        box.append(password_label);
        box.append(password_entry);
        box.append(confirm_label);
        box.append(confirm_entry);
        box.append(status_label);
        
        dialog.set_extra_child(box);
        
        dialog.add_response("cancel", _("Cancel"));
        dialog.add_response("ok", _("Create Encrypted Backup"));
        dialog.set_response_appearance("ok", Adw.ResponseAppearance.SUGGESTED);
        dialog.set_default_response("ok");
        dialog.set_close_response("cancel");
        
        // Disable OK until passwords match
        dialog.set_response_enabled("ok", false);
        
        password_entry.changed.connect(() => {
            string pw1 = password_entry.text;
            string pw2 = confirm_entry.text;
            if (pw1.length < 4) {
                status_label.label = _("Password too short");
            } else if (pw2.length > 0 && pw1 != pw2) {
                status_label.label = _("Passwords do not match");
            } else if (pw1.length >= 4 && pw1 == pw2) {
                status_label.label = _("✓ Passwords match");
            } else {
                status_label.label = "";
            }
            dialog.set_response_enabled("ok", pw1.length >= 4 && pw1 == pw2);
        });
        
        confirm_entry.changed.connect(() => {
            string pw1 = password_entry.text;
            string pw2 = confirm_entry.text;
            if (pw1.length < 4) {
                status_label.label = _("Password too short");
            } else if (pw2.length > 0 && pw1 != pw2) {
                status_label.label = _("Passwords do not match");
            } else if (pw1.length >= 4 && pw1 == pw2) {
                status_label.label = _("✓ Passwords match");
            } else {
                status_label.label = "";
            }
            dialog.set_response_enabled("ok", pw1.length >= 4 && pw1 == pw2);
        });
        
        dialog.response.connect((response) => {
            if (response == "ok") {
                show_backup_file_chooser(data_dir, password_entry.text);
            }
        });
        
        dialog.present(window);
    }
    
    private void show_backup_file_chooser(string data_dir, string? password) {
        var file_chooser = new Gtk.FileDialog();
        file_chooser.title = _("Select Backup Location");
        file_chooser.modal = true;
        
        var now = new DateTime.now_local();
        string extension = password != null ? ".tar.gz.gpg" : ".tar.gz";
        string default_name = "dinox-backup-%s%s".printf(now.format("%Y%m%d-%H%M%S"), extension);
        file_chooser.initial_name = default_name;
        
        file_chooser.save.begin(window, null, (obj, res) => {
            GLib.File? file = null;
            try {
                file = file_chooser.save.end(res);
            } catch (Error err) {
                // User cancelled
                return;
            }
            
            if (file != null) {
                string backup_path = file.get_path();
                perform_backup(data_dir, backup_path, password);
            }
        });
    }
    
    private void checkpoint_databases() {
        // Checkpoint the main database to flush WAL to main file
        try {
            db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
        } catch (Error e) {
            warning("Failed to checkpoint main database: %s", e.message);
        }
        
        // Also checkpoint omemo.db and pgp.db via sqlite3 command
        string data_dir = Path.build_filename(Environment.get_user_data_dir(), "dinox");
        string[] db_files = { "omemo.db", "pgp.db" };
        
        foreach (string db_file in db_files) {
            string db_path = Path.build_filename(data_dir, db_file);
            if (FileUtils.test(db_path, FileTest.EXISTS)) {
                try {
                    string[] argv = { "sqlite3", db_path, "PRAGMA wal_checkpoint(TRUNCATE);" };
                    Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, null);
                } catch (Error e) {
                    warning("Failed to checkpoint %s: %s", db_file, e.message);
                }
            }
        }
    }
    
    private void perform_backup(string data_dir, string backup_path, string? password = null) {
        // Checkpoint all databases to ensure WAL data is written to main files
        checkpoint_databases();
        
        // Create progress dialog with spinner
        var progress_dialog = new Adw.AlertDialog(
            password != null ? _("Creating Encrypted Backup...") : _("Creating Backup..."),
            _("Please wait while your data is being backed up.")
        );
        
        var spinner = new Gtk.Spinner();
        spinner.spinning = true;
        spinner.width_request = 48;
        spinner.height_request = 48;
        spinner.halign = Gtk.Align.CENTER;
        spinner.margin_top = 12;
        spinner.margin_bottom = 12;
        progress_dialog.set_extra_child(spinner);
        
        // No close button during backup
        progress_dialog.set_close_response("");
        
        progress_dialog.present(window);
        
        // Capture password for use in thread
        string? backup_password = password;
        
        // Capture directories for thread
        string data_directory = data_dir;
        
        // Run backup in background
        new Thread<void*>("backup", () => {
            bool success = false;
            string? stderr_str = null;
            string temp_tar_path = backup_path;
            
            // If encrypting, create tar.gz first in temp dir, then encrypt to final path
            if (backup_password != null) {
                // Create temp tar.gz file (without .gpg extension)
                temp_tar_path = Path.build_filename(Environment.get_tmp_dir(), "dinox-backup-temp.tar.gz");
            }
            
            // Check if data directory exists
            bool data_exists = FileUtils.test(data_directory, FileTest.IS_DIR);
            
            if (!data_exists) {
                stderr_str = _("No data directory found to backup");
                Idle.add(() => {
                    spinner.spinning = false;
                    progress_dialog.heading = _("Backup Failed");
                    progress_dialog.body = stderr_str;
                    progress_dialog.set_extra_child(null);
                    progress_dialog.add_response("close", _("Close"));
                    progress_dialog.set_default_response("close");
                    progress_dialog.set_close_response("close");
                    return false;
                });
                return null;
            }
            
            // Build tar command - backup the data directory
            // DinoX stores all data in ~/.local/share/dinox (get_user_data_dir)
            string[] argv = { "tar", "-czf", temp_tar_path, "-C", Environment.get_user_data_dir(), "dinox" };
            
            string? stdout_str = null;
            int exit_status = -1;
            
            try {
                Process.spawn_sync(
                    null,
                    argv,
                    null,
                    SpawnFlags.SEARCH_PATH,
                    null,
                    out stdout_str,
                    out stderr_str,
                    out exit_status
                );
                success = (exit_status == 0);
            } catch (Error err) {
                stderr_str = err.message;
            }
            
            // If password provided, encrypt with GPG
            if (success && backup_password != null) {
                // Use spawn_command_line_sync for proper argument handling with quoted password
                string gpg_command = "gpg --batch --yes --symmetric --cipher-algo AES256 --pinentry-mode loopback --passphrase %s --output %s %s".printf(
                    Shell.quote(backup_password),
                    Shell.quote(backup_path),
                    Shell.quote(temp_tar_path)
                );
                
                string? gpg_stdout = null;
                string? gpg_stderr = null;
                try {
                    Process.spawn_command_line_sync(
                        gpg_command,
                        out gpg_stdout,
                        out gpg_stderr,
                        out exit_status
                    );
                    success = (exit_status == 0);
                    if (!success) {
                        stderr_str = gpg_stderr ?? "GPG encryption failed";
                        warning("GPG encrypt failed (exit %d): %s", exit_status, stderr_str);
                    }
                    
                    // Delete temporary unencrypted file
                    FileUtils.unlink(temp_tar_path);
                } catch (Error err) {
                    stderr_str = err.message;
                    success = false;
                    warning("Failed to run GPG encrypt: %s", err.message);
                }
            }
            
            // Get file size if successful
            string size_str = "";
            if (success) {
                try {
                    var file = File.new_for_path(backup_path);
                    FileInfo info = file.query_info(FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
                    int64 size = info.get_size();
                    size_str = format_size(size);
                } catch (Error err) {
                    // Ignore size check error
                }
            }
            
            // Update dialog on main thread
            string final_stderr = stderr_str;
            string final_size = size_str;
            bool was_encrypted = backup_password != null;
            Idle.add(() => {
                spinner.spinning = false;
                progress_dialog.set_extra_child(null);
                progress_dialog.add_response("close", _("Close"));
                progress_dialog.set_default_response("close");
                progress_dialog.set_close_response("close");
                
                if (success) {
                    string msg;
                    if (was_encrypted) {
                        progress_dialog.heading = _("Encrypted Backup Created");
                        msg = final_size.length > 0 ? 
                            _("Your encrypted backup was created successfully.\n\nSize: %s").printf(final_size) :
                            _("Your encrypted backup was created successfully.");
                    } else {
                        progress_dialog.heading = _("Backup Created");
                        msg = final_size.length > 0 ? 
                            _("Your backup was created successfully.\n\nSize: %s").printf(final_size) :
                            _("Your backup was created successfully.");
                    }
                    progress_dialog.body = msg;
                } else {
                    progress_dialog.heading = _("Backup Failed");
                    string msg = final_stderr != null && final_stderr.length > 0 ? 
                        final_stderr : _("Unknown error");
                    progress_dialog.body = _("Backup failed: %s").printf(msg);
                }
                return false;
            });
            
            return null;
        });
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

    private void apply_color_scheme(string scheme) {
        var style_manager = Adw.StyleManager.get_default();
        switch (scheme) {
            case "light":
                style_manager.color_scheme = Adw.ColorScheme.FORCE_LIGHT;
                break;
            case "dark":
                style_manager.color_scheme = Adw.ColorScheme.FORCE_DARK;
                break;
            default:
                style_manager.color_scheme = Adw.ColorScheme.DEFAULT;
                break;
        }
    }

    public override void shutdown() {
        if (systray_manager != null) {
            systray_manager.cleanup();
            systray_manager = null;
        }
        
        // Disconnect all accounts to clean up XMPP connections
        if (stream_interactor != null) {
            var accounts = stream_interactor.get_accounts();
            foreach (var account in accounts) {
                stream_interactor.disconnect_account.begin(account);
            }
        }
        
        base.shutdown();
    }
}

