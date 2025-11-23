using Gee;
using Gtk;
using Dino.Entities;
using Xmpp;

namespace Dino.Ui.ConversationSummary {

public class MetaStatusItem : Plugins.MetaConversationItem {
    public string message;
    
    public MetaStatusItem(string message, DateTime time) {
        this.message = message;
        this.time = time;
    }
    
    public override DateTime time { get; set; }

    public override Object? get_widget(Plugins.ConversationItemWidgetInterface outer, Plugins.WidgetType widget_type) {
        Label label = new Label(message);
        label.add_css_class("dim-label");
        label.add_css_class("status-message");
        label.halign = Align.CENTER;
        label.margin_top = 5;
        label.margin_bottom = 5;
        return label;
    }
    
    public override Gee.List<Plugins.MessageAction>? get_item_actions(Plugins.WidgetType type) { return null; }
}

class StatusPopulator : Plugins.ConversationItemPopulator, Plugins.ConversationAdditionPopulator, Object {

    public string id { get { return "status_populator"; } }

    private StreamInteractor stream_interactor;
    private Conversation? current_conversation;
    private Plugins.ConversationItemCollection? item_collection;

    public StatusPopulator(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
    }

    public void init(Conversation conversation, Plugins.ConversationItemCollection item_collection, Plugins.WidgetType type) {
        this.current_conversation = conversation;
        this.item_collection = item_collection;

        var muc_manager = stream_interactor.get_module(MucManager.IDENTITY);
        muc_manager.self_removed.connect(on_self_removed);
        muc_manager.occupant_removed.connect(on_occupant_removed);
        muc_manager.occupant_affiliation_updated.connect(on_affiliation_updated);
    }

    public void close(Conversation conversation) {
        var muc_manager = stream_interactor.get_module(MucManager.IDENTITY);
        muc_manager.self_removed.disconnect(on_self_removed);
        muc_manager.occupant_removed.disconnect(on_occupant_removed);
        muc_manager.occupant_affiliation_updated.disconnect(on_affiliation_updated);
        current_conversation = null;
    }

    public void populate_timespan(Conversation conversation, DateTime after, DateTime before) { }

    private void on_self_removed(Account account, Jid room_jid, Xep.Muc.StatusCode code, string? reason) {
        if (current_conversation == null || !current_conversation.account.equals(account) || !current_conversation.counterpart.equals_bare(room_jid)) return;

        string msg = "";
        switch (code) {
            case Xep.Muc.StatusCode.BANNED: msg = _("You have been banned from this room."); break;
            case Xep.Muc.StatusCode.REMOVED_MEMBERS_ONLY: msg = _("You have been removed because you are not a member."); break;
            case Xep.Muc.StatusCode.KICKED: msg = _("You have been kicked from this room."); break;
            case Xep.Muc.StatusCode.REMOVED_SHUTDOWN: msg = _("The room has been destroyed."); break;
            default: 
                if ((int)code == 307) msg = _("You have been kicked from this room.");
                else if ((int)code == 332) msg = _("The room has been destroyed.");
                else msg = _("You have been removed from this room.");
                break;
        }

        if (reason != null && reason != "") {
            msg += " " + _("Reason: %s").printf(reason);
        }
        
        item_collection.insert_item(new MetaStatusItem(msg, new DateTime.now_utc()));
    }

    private void on_occupant_removed(Account account, Jid room_jid, Jid occupant_jid, Xep.Muc.StatusCode code) {
        if (current_conversation == null || !current_conversation.account.equals(account) || !current_conversation.counterpart.equals_bare(room_jid)) return;

        string nick = occupant_jid.resourcepart;
        string msg = "";
        switch (code) {
            case Xep.Muc.StatusCode.BANNED: msg = _("%s has been banned.").printf(nick); break;
            case Xep.Muc.StatusCode.KICKED: msg = _("%s has been kicked.").printf(nick); break;
            case Xep.Muc.StatusCode.REMOVED_MEMBERS_ONLY: msg = _("%s has been removed because they are not a member.").printf(nick); break;
            default:
                if ((int)code == 307) msg = _("%s has been kicked.").printf(nick);
                else if ((int)code == 301) msg = _("%s has been banned.").printf(nick);
                break;
        }

        if (msg != "") {
            item_collection.insert_item(new MetaStatusItem(msg, new DateTime.now_utc()));
        }
    }

    private void on_affiliation_updated(Account account, Jid room_jid, Jid occupant_jid, Xep.Muc.Affiliation affiliation) {
        if (current_conversation == null || !current_conversation.account.equals(account) || !current_conversation.counterpart.equals_bare(room_jid)) return;

        string nick = occupant_jid.resourcepart;
        string msg = "";
        switch (affiliation) {
            case Xep.Muc.Affiliation.OWNER: msg = _("%s is now an owner.").printf(nick); break;
            case Xep.Muc.Affiliation.ADMIN: msg = _("%s is now an admin.").printf(nick); break;
            case Xep.Muc.Affiliation.MEMBER: msg = _("%s is now a member.").printf(nick); break;
            case Xep.Muc.Affiliation.OUTCAST: msg = _("%s has been banned.").printf(nick); break;
            case Xep.Muc.Affiliation.NONE: msg = _("%s's affiliation has been removed.").printf(nick); break;
        }
        
        if (msg != "") {
            item_collection.insert_item(new MetaStatusItem(msg, new DateTime.now_utc()));
        }
    }
}

}
