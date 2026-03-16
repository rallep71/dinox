/*
 * Windows notification provider using Shell_NotifyIcon balloon tips.
 * Provides native Windows tray notifications with click-to-open support.
 * No action buttons (Windows limitation for balloon tips), but clicking
 * the notification opens the relevant conversation.
 */
using Gee;

using Dino.Entities;
using Xmpp;

namespace Dino.Ui {

    public class WindowsNotifier : NotificationProvider, Object {

        private StreamInteractor stream_interactor;

        // Track the conversation ID associated with the current balloon
        private static int pending_conversation_id = -1;
        private static int pending_call_id = -1;
        private static string pending_action = "";

        public WindowsNotifier(StreamInteractor stream_interactor) {
            this.stream_interactor = stream_interactor;
        }

        public double get_priority() {
            return 2;  // Higher than GNotifications (0) and FreeDesktop (1)
        }

        public async void notify_message(Message message, Conversation conversation, string conversation_display_name, string? participant_display_name) {
            string text = message.body;
            if (participant_display_name != null) {
                text = @"$participant_display_name: $text";
            }
            show_balloon(conversation_display_name, text, 1, conversation.id, "open-conversation");
        }

        public async void notify_file(FileTransfer file_transfer, Conversation conversation, bool is_image, string conversation_display_name, string? participant_display_name) {
            string text;
            if (file_transfer.direction == Message.DIRECTION_SENT) {
                text = is_image ? _("Image sent") : _("File sent");
            } else {
                text = is_image ? _("Image received") : _("File received");
            }
            if (participant_display_name != null) {
                text = @"$participant_display_name: $text";
            }
            show_balloon(conversation_display_name, text, 1, conversation.id, "open-conversation");
        }

        public async void notify_call(Call call, Conversation conversation, bool video, bool multiparty, string conversation_display_name) {
            string body = video ? _("Incoming video call") : _("Incoming call");
            if (multiparty) {
                body = video ? _("Incoming video group call") : _("Incoming group call");
            }
            pending_call_id = call.id;
            show_balloon(conversation_display_name, body, 2, conversation.id, "open-conversation");
        }

        public async void retract_call_notification(Call call, Conversation conversation) {
            if (pending_call_id == call.id) {
                SystrayWin32.hide_balloon();
                pending_call_id = -1;
            }
        }

        public async void notify_subscription_request(Conversation conversation) {
            string body = conversation.counterpart.to_string();
            show_balloon(_("Subscription request"), body, 1, conversation.id, "open-conversation");
        }

        public async void notify_connection_error(Account account, ConnectionManager.ConnectionError error) {
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
            // Connection errors: click opens preferences
            pending_conversation_id = account.id;
            pending_action = "preferences-account";
            SystrayWin32.show_balloon(title, body, 2, on_balloon_click, null);
        }

        public async void notify_muc_invite(Account account, Jid room_jid, Jid from_jid, string inviter_display_name) {
            string display_room = room_jid.bare_jid.to_string();
            string body = _("%s invited you to %s").printf(inviter_display_name, display_room);
            Conversation group_conversation = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).create_conversation(room_jid, account, Conversation.Type.GROUPCHAT);
            show_balloon(_("Invitation to %s").printf(display_room), body, 1, group_conversation.id, "open-muc-join");
        }

        public async void notify_voice_request(Conversation conversation, Jid from_jid) {
            string display_name = Util.get_participant_display_name(stream_interactor, conversation, from_jid);
            string display_room = Util.get_conversation_display_name(stream_interactor, conversation);
            string body = _("%s requests the permission to write in %s").printf(display_name, display_room);
            show_balloon(_("Permission request"), body, 1, conversation.id, "open-conversation");
        }

        public async void retract_content_item_notifications() {
            SystrayWin32.hide_balloon();
        }

        public async void retract_conversation_notifications(Conversation conversation) {
            if (pending_conversation_id == conversation.id) {
                SystrayWin32.hide_balloon();
            }
        }

        // Helper: show balloon and set up click callback
        private void show_balloon(string title, string body, int icon_type, int conversation_id, string action) {
            pending_conversation_id = conversation_id;
            pending_action = action;
            SystrayWin32.show_balloon(title, body, icon_type, on_balloon_click, null);
        }

        // Static callback invoked by Win32 when user clicks the balloon
        private static void on_balloon_click(void* user_data) {
            if (pending_conversation_id < 0 || pending_action == "") return;

            int conv_id = pending_conversation_id;
            string action = pending_action;
            pending_conversation_id = -1;
            pending_action = "";

            // Dispatch to app action on the main thread
            Idle.add(() => {
                var app = GLib.Application.get_default();
                if (app != null) {
                    if (action == "preferences-account") {
                        app.activate_action(action, new Variant.int32(conv_id));
                    } else {
                        app.activate_action(action, new Variant.int32(conv_id));
                    }
                }
                return Source.REMOVE;
            });
        }
    }
}
