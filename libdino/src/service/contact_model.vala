using Xmpp;
using Gee;
using Qlite;

using Dino.Entities;

public class Dino.Model.ConversationDisplayName : Object {
    public string display_name { get; set; }
}

namespace Dino {
    public class ContactModels : StreamInteractionModule, Object {
        public static ModuleIdentity<ContactModels> IDENTITY = new ModuleIdentity<ContactModels>("contact_models");
        public string id { get { return IDENTITY.id; } }

        private StreamInteractor stream_interactor;
        private HashMap<Conversation, Model.ConversationDisplayName> conversation_models = new HashMap<Conversation, Model.ConversationDisplayName>(Conversation.hash_func, Conversation.equals_func);

        public static void start(StreamInteractor stream_interactor) {
            ContactModels m = new ContactModels(stream_interactor);
            stream_interactor.add_module(m);
        }

        private ContactModels(StreamInteractor stream_interactor) {
            this.stream_interactor = stream_interactor;

            stream_interactor.get_module<MucManager>(MucManager.IDENTITY).room_info_updated.connect((account, jid) => {
                debug("room_info_updated received for %s", jid.to_string());
                check_update_models(account, jid, Conversation.Type.GROUPCHAT);
            });
            stream_interactor.get_module<MucManager>(MucManager.IDENTITY).private_room_occupant_updated.connect((account, room, occupant) => {
                check_update_models(account, room, Conversation.Type.GROUPCHAT);
            });
            stream_interactor.get_module<MucManager>(MucManager.IDENTITY).subject_set.connect((account, jid, subject) => {
                check_update_models(account, jid, Conversation.Type.GROUPCHAT);
            });
            stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).updated_roster_item.connect((account, jid, roster_item) => {
                check_update_models(account, jid, Conversation.Type.CHAT);
            });

            /* React to plugin-set nickname changes (e.g. MQTT bot conversations) */
            stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).conversation_activated.connect((conversation) => {
                if (conversation.nickname != null && conversation.nickname.strip() != "") {
                    var display_name_model = conversation_models[conversation];
                    if (display_name_model != null) {
                        string new_name = Dino.get_conversation_display_name(stream_interactor, conversation, "%s (%s)");
                        if (display_name_model.display_name != new_name) {
                            display_name_model.display_name = new_name;
                        }
                    }
                }
            });
        }

        private void check_update_models(Account account, Jid jid, Conversation.Type conversation_ty) {
            var conversation = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).get_conversation(jid, account, conversation_ty);
            if (conversation == null) {
                debug("check_update_models: No conversation for %s", jid.to_string());
                return;
            }
            var display_name_model = conversation_models[conversation];
            if (display_name_model == null) {
                debug("check_update_models: No display_name_model for %s", jid.to_string());
                return;
            }
            string new_name = Dino.get_conversation_display_name(stream_interactor, conversation, "%s (%s)");
            debug("check_update_models: Updating display name for %s to '%s'", jid.to_string(), new_name);
            display_name_model.display_name = new_name;
        }

        public Model.ConversationDisplayName get_display_name_model(Conversation conversation) {
            if (conversation_models.has_key(conversation)) return conversation_models[conversation];

            var model = new Model.ConversationDisplayName();
            model.display_name = Dino.get_conversation_display_name(stream_interactor, conversation, "%s (%s)");
            conversation_models[conversation] = model;
            return model;
        }
    }
}
