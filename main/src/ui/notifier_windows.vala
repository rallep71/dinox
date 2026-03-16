/*
 * Windows notification provider.
 *
 * Primary:  WinRT Toast Notifications (Win10+) — rich UI, action buttons
 *           for calls (Accept/Reject), click-to-open via COM callback.
 * Fallback: Shell_NotifyIcon balloon tips (Win7/8) — text-only, click opens
 *           conversation but no action buttons.
 *
 * Toast init is attempted once in the constructor. If it fails, all
 * subsequent calls silently fall through to balloon tips.
 */
using Gee;

using Dino.Entities;
using Xmpp;

namespace Dino.Ui {

    public class WindowsNotifier : NotificationProvider, Object {

        private StreamInteractor stream_interactor;
        private bool toast_available = false;

        /* Balloon-tip fallback state (used when toast is unavailable) */
        private static int pending_conversation_id = -1;
        private static int pending_call_id = -1;
        private static string pending_action = "";

        public WindowsNotifier(StreamInteractor stream_interactor) {
            this.stream_interactor = stream_interactor;

            /* Try to initialize WinRT Toast notifications */
            toast_available = ToastWin32.init(
                "DinoX",
                "im.github.rallep71.DinoX",
                on_toast_activated,
                null
            );
            if (toast_available) {
                message("WindowsNotifier: using WinRT Toast notifications");
            } else {
                message("WindowsNotifier: WinRT unavailable, using balloon tips");
            }
        }

        public double get_priority() {
            return 2;
        }

        /* ======= Notification methods ======= */

        public async void notify_message(Message message, Conversation conversation,
                                          string conversation_display_name,
                                          string? participant_display_name) {
            string text = message.body;
            if (participant_display_name != null) {
                text = @"$participant_display_name: $text";
            }
            if (toast_available) {
                string xml = build_simple_toast(conversation_display_name, text,
                    "open-conversation:%d".printf(conversation.id));
                ToastWin32.show(xml, "conv-%d".printf(conversation.id));
            } else {
                show_balloon(conversation_display_name, text, 1, conversation.id, "open-conversation");
            }
        }

        public async void notify_file(FileTransfer file_transfer, Conversation conversation,
                                       bool is_image, string conversation_display_name,
                                       string? participant_display_name) {
            string text;
            if (file_transfer.direction == Message.DIRECTION_SENT) {
                text = is_image ? _("Image sent") : _("File sent");
            } else {
                text = is_image ? _("Image received") : _("File received");
            }
            if (participant_display_name != null) {
                text = @"$participant_display_name: $text";
            }
            if (toast_available) {
                string xml = build_simple_toast(conversation_display_name, text,
                    "open-conversation:%d".printf(conversation.id));
                ToastWin32.show(xml, "conv-%d".printf(conversation.id));
            } else {
                show_balloon(conversation_display_name, text, 1, conversation.id, "open-conversation");
            }
        }

        public async void notify_call(Call call, Conversation conversation,
                                       bool video, bool multiparty,
                                       string conversation_display_name) {
            string body = video ? _("Incoming video call") : _("Incoming call");
            if (multiparty) {
                body = video ? _("Incoming video group call") : _("Incoming group call");
            }
            if (toast_available) {
                string xml = build_call_toast(conversation_display_name, body,
                    conversation.id, call.id);
                ToastWin32.show(xml, "call-%d".printf(call.id));
            } else {
                pending_call_id = call.id;
                show_balloon(conversation_display_name, body, 2, conversation.id, "open-conversation");
            }
        }

        public async void retract_call_notification(Call call, Conversation conversation) {
            if (toast_available) {
                ToastWin32.hide("call-%d".printf(call.id));
            } else if (pending_call_id == call.id) {
                SystrayWin32.hide_balloon();
                pending_call_id = -1;
            }
        }

        public async void notify_subscription_request(Conversation conversation) {
            string body = conversation.counterpart.to_string();
            if (toast_available) {
                string xml = build_simple_toast(_("Subscription request"), body,
                    "open-conversation:%d".printf(conversation.id));
                ToastWin32.show(xml, "sub-%d".printf(conversation.id));
            } else {
                show_balloon(_("Subscription request"), body, 1, conversation.id, "open-conversation");
            }
        }

        public async void notify_connection_error(Account account,
                                                    ConnectionManager.ConnectionError error) {
            string title = _("Reconnecting to %s...").printf(account.bare_jid.domainpart);
            string body = "";
            switch (error.source) {
                case ConnectionManager.ConnectionError.Source.SASL:
                    body = error.identifier == "channel-binding-required"
                        ? _("%s does not support SCRAM channel binding (MITM protection)").printf(account.bare_jid.domainpart)
                        : "Wrong password";
                    break;
                case ConnectionManager.ConnectionError.Source.TLS:
                    body = "Invalid TLS certificate";
                    break;
            }
            if (toast_available) {
                string xml = build_simple_toast(title, body,
                    "preferences-account:%d".printf(account.id));
                ToastWin32.show(xml, "conn-%d".printf(account.id));
            } else {
                pending_conversation_id = account.id;
                pending_action = "preferences-account";
                SystrayWin32.show_balloon(title, body, 2, on_balloon_click, null);
            }
        }

        public async void notify_muc_invite(Account account, Jid room_jid,
                                              Jid from_jid, string inviter_display_name) {
            string display_room = room_jid.bare_jid.to_string();
            string body = _("%s invited you to %s").printf(inviter_display_name, display_room);
            Conversation group_conversation = stream_interactor.get_module<ConversationManager>(
                ConversationManager.IDENTITY).create_conversation(room_jid, account, Conversation.Type.GROUPCHAT);

            if (toast_available) {
                string xml = build_simple_toast(
                    _("Invitation to %s").printf(display_room), body,
                    "open-muc-join:%d".printf(group_conversation.id));
                ToastWin32.show(xml, "muc-%d".printf(group_conversation.id));
            } else {
                show_balloon(_("Invitation to %s").printf(display_room), body,
                    1, group_conversation.id, "open-muc-join");
            }
        }

        public async void notify_voice_request(Conversation conversation, Jid from_jid) {
            string display_name = Util.get_participant_display_name(stream_interactor, conversation, from_jid);
            string display_room = Util.get_conversation_display_name(stream_interactor, conversation);
            string body = _("%s requests the permission to write in %s").printf(display_name, display_room);

            if (toast_available) {
                string xml = build_simple_toast(_("Permission request"), body,
                    "open-conversation:%d".printf(conversation.id));
                ToastWin32.show(xml, "voice-%d".printf(conversation.id));
            } else {
                show_balloon(_("Permission request"), body, 1, conversation.id, "open-conversation");
            }
        }

        public async void retract_content_item_notifications() {
            if (toast_available) {
                /* Toast notifications are tagged per-conversation, no blanket hide needed.
                 * Individual toasts expire naturally or are removed per-conversation. */
            } else {
                SystrayWin32.hide_balloon();
            }
        }

        public async void retract_conversation_notifications(Conversation conversation) {
            if (toast_available) {
                ToastWin32.hide("conv-%d".printf(conversation.id));
            } else if (pending_conversation_id == conversation.id) {
                SystrayWin32.hide_balloon();
            }
        }

        /* ======= Toast XML builders ======= */

        /* Standard toast: title + body, click opens action */
        private static string build_simple_toast(string title, string body, string launch_args) {
            return "<toast launch=\"%s\"><visual><binding template=\"ToastGeneric\"><text>%s</text><text>%s</text></binding></visual></toast>".printf(
                Markup.escape_text(launch_args),
                Markup.escape_text(title),
                Markup.escape_text(body)
            );
        }

        /* Call toast: scenario=incomingCall, Accept/Reject buttons, looping call sound */
        private static string build_call_toast(string caller, string body,
                                                int conv_id, int call_id) {
            return ("<toast scenario=\"incomingCall\" launch=\"%s\">" +
                    "<visual><binding template=\"ToastGeneric\">" +
                    "<text>%s</text><text>%s</text>" +
                    "</binding></visual>" +
                    "<actions>" +
                    "<action content=\"%s\" arguments=\"%s\" activationType=\"foreground\"/>" +
                    "<action content=\"%s\" arguments=\"%s\" activationType=\"foreground\"/>" +
                    "</actions>" +
                    "<audio src=\"ms-winsoundevent:Notification.Looping.Call\" loop=\"true\"/>" +
                    "</toast>").printf(
                Markup.escape_text("open-conversation:%d".printf(conv_id)),
                Markup.escape_text(caller),
                Markup.escape_text(body),
                Markup.escape_text(_("Reject")),
                Markup.escape_text("reject-call:%d:%d".printf(conv_id, call_id)),
                Markup.escape_text(_("Accept")),
                Markup.escape_text("accept-call:%d:%d".printf(conv_id, call_id))
            );
        }

        /* ======= Toast activation callback ======= */

        /* Called on GTK main thread when user clicks toast body or button.
         * Parses the action:arg1:arg2 string and dispatches to app actions. */
        private static void on_toast_activated(string action_args, void* user_data) {
            string[] parts = action_args.split(":");
            if (parts.length < 2) return;

            string action = parts[0];
            int id1 = int.parse(parts[1]);

            var app = GLib.Application.get_default();
            if (app == null) return;

            switch (action) {
                case "open-conversation":
                case "open-muc-join":
                case "preferences-account":
                    app.activate_action(action, new Variant.int32(id1));
                    break;
                case "accept-call":
                case "reject-call":
                    if (parts.length >= 3) {
                        int id2 = int.parse(parts[2]);
                        app.activate_action(action, new Variant.tuple(new Variant[]{
                            new Variant.int32(id1), new Variant.int32(id2)
                        }));
                    }
                    break;
            }
        }

        /* ======= Balloon fallback helpers ======= */

        private void show_balloon(string title, string body, int icon_type,
                                   int conversation_id, string action) {
            pending_conversation_id = conversation_id;
            pending_action = action;
            SystrayWin32.show_balloon(title, body, icon_type, on_balloon_click, null);
        }

        private static void on_balloon_click(void* user_data) {
            if (pending_conversation_id < 0 || pending_action == "") return;

            int conv_id = pending_conversation_id;
            string action = pending_action;
            pending_conversation_id = -1;
            pending_action = "";

            Idle.add(() => {
                var app = GLib.Application.get_default();
                if (app != null) {
                    app.activate_action(action, new Variant.int32(conv_id));
                }
                return Source.REMOVE;
            });
        }
    }
}
