using Gee;
using Gtk;

using Dino.Entities;
using Xmpp;

namespace Dino.Ui.ConversationSummary {

class ChatStatePopulator : Plugins.ConversationItemPopulator, Plugins.ConversationAdditionPopulator, Object {

    public string id { get { return "chat_state"; } }

    private StreamInteractor? stream_interactor;
    private Conversation? current_conversation;
    private Plugins.ConversationItemCollection? item_collection;

    private MetaChatStateItem? meta_item;
    private ulong received_state_handler_id = 0;
    private ulong message_sent_handler_id = 0;

    public ChatStatePopulator(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
    }

    public void init(Conversation conversation, Plugins.ConversationItemCollection item_collection, Plugins.WidgetType type) {
        // Disconnect previous handlers if any
        close(conversation);

        current_conversation = conversation;
        this.item_collection = item_collection;
        this.meta_item = null;

        received_state_handler_id = stream_interactor.get_module<CounterpartInteractionManager>(CounterpartInteractionManager.IDENTITY).received_state.connect((conv, state) => {
            if (current_conversation != null && current_conversation.equals(conv)) {
                update_chat_state();
            }
        });
        message_sent_handler_id = stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).message_sent.connect((message, conv) => {
            if (conv.equals(current_conversation)) {
                update_chat_state();
            }
        });

        update_chat_state();
    }

    public void close(Conversation conversation) {
        if (received_state_handler_id != 0) {
            stream_interactor.get_module<CounterpartInteractionManager>(CounterpartInteractionManager.IDENTITY).disconnect(received_state_handler_id);
            received_state_handler_id = 0;
        }
        if (message_sent_handler_id != 0) {
            stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).disconnect(message_sent_handler_id);
            message_sent_handler_id = 0;
        }
    }

    public void populate_timespan(Conversation conversation, DateTime from, DateTime to) { }

    private void update_chat_state() {
        Gee.List<Jid>? typing_jids = stream_interactor.get_module<CounterpartInteractionManager>(CounterpartInteractionManager.IDENTITY).get_typing_jids(current_conversation);

        if (meta_item != null && typing_jids == null) {
            // Remove state (stoped typing)
            item_collection.remove_item(meta_item);
            meta_item = null;
        } else if (meta_item != null && typing_jids != null) {
            // Update state (other people typing in MUC)
            meta_item.set_new(typing_jids);
        } else if (typing_jids != null) {
            // New state (started typing)
            meta_item = new MetaChatStateItem(stream_interactor, current_conversation, typing_jids);
            item_collection.insert_item(meta_item);
        }
    }
}

private class MetaChatStateItem : Plugins.MetaConversationItem {
    public override DateTime time { get; set; default=new DateTime.now_utc().add_years(10); }

    private StreamInteractor stream_interactor;
    private Conversation conversation;
    private Gee.List<Jid> jids = new ArrayList<Jid>();
    private Label label;
    private AvatarPicture picture;

    public MetaChatStateItem(StreamInteractor stream_interactor, Conversation conversation, Gee.List<Jid> jids) {
        this.stream_interactor = stream_interactor;
        this.conversation = conversation;
        this.jids = jids;
    }

    public override Object? get_widget(Plugins.ConversationItemWidgetInterface outer, Plugins.WidgetType widget_type) {
        label = new Label("") { xalign=0, vexpand=true };
        label.add_css_class("dim-label");
        picture = new AvatarPicture() { margin_top=2, valign=Align.START };

        Box image_content_box = new Box(Orientation.HORIZONTAL, 8);
        image_content_box.append(picture);
        image_content_box.append(label);

        update();
        return image_content_box;
    }

    public override Gee.List<Plugins.MessageAction>? get_item_actions(Plugins.WidgetType type) { return null; }

    public void set_new(Gee.List<Jid> jids) {
        this.jids = jids;
        update();
    }

    private void update() {
        if (picture == null || label == null) return;

        Gee.List<string> display_names = new ArrayList<string>();
        foreach (Jid jid in jids) {
            display_names.add(Util.get_participant_display_name(stream_interactor, conversation, jid));
        }
        string new_text = "";
        if (jids.size > 3) {
            new_text = _("%s, %s and %i others are typing…").printf(display_names[0], display_names[1], jids.size - 2);
            picture.model = new ViewModel.CompatAvatarPictureModel(stream_interactor)
                    .add_participant(conversation, jids[0])
                    .add_participant(conversation, jids[1])
                    .add_participant(conversation, jids[2])
                    .add("+");
        } else if (jids.size == 3) {
            new_text = _("%s, %s and %s are typing…").printf(display_names[0], display_names[1], display_names[2]);
            picture.model = new ViewModel.CompatAvatarPictureModel(stream_interactor)
                    .add_participant(conversation, jids[0])
                    .add_participant(conversation, jids[1])
                    .add_participant(conversation, jids[2]);
        } else if (jids.size == 2) {
            new_text =_("%s and %s are typing…").printf(display_names[0], display_names[1]);
            picture.model = new ViewModel.CompatAvatarPictureModel(stream_interactor)
                    .add_participant(conversation, jids[0])
                    .add_participant(conversation, jids[1]);
        } else {
            new_text = _("%s is typing…").printf(display_names[0]);
            picture.model = new ViewModel.CompatAvatarPictureModel(stream_interactor)
                    .add_participant(conversation, jids[0]);
        }

        label.label = new_text;
    }
}

}
