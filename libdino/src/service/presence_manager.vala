using Gee;

using Xmpp;
using Dino.Entities;

namespace Dino {
public class PresenceManager : StreamInteractionModule, Object {
    public static ModuleIdentity<PresenceManager> IDENTITY = new ModuleIdentity<PresenceManager>("presence_manager");
    public string id { get { return IDENTITY.id; } }

    public signal void show_received(Jid jid, Account account);
    public signal void received_offline_presence(Jid jid, Account account);
    public signal void received_subscription_request(Jid jid, Account account);
    public signal void received_subscription_approval(Jid jid, Account account);
    public signal void status_changed(string show, string? status_msg);

    private StreamInteractor stream_interactor;
    private HashMap<Jid, ArrayList<Jid>> resources = new HashMap<Jid, ArrayList<Jid>>(Jid.hash_bare_func, Jid.equals_bare_func);
    private Gee.List<Jid> subscription_requests = new ArrayList<Jid>(Jid.equals_func);

    private string current_show = "online";
    private string? current_status_msg = null;
    private Database? db = null;

    public string get_current_show() {
        return current_show;
    }

    public string? get_current_status_msg() {
        return current_status_msg;
    }

    public static void start(StreamInteractor stream_interactor, Database? db = null) {
        PresenceManager m = new PresenceManager(stream_interactor, db);
        stream_interactor.add_module(m);
    }

    private PresenceManager(StreamInteractor stream_interactor, Database? db = null) {
        this.stream_interactor = stream_interactor;
        this.db = db;
        stream_interactor.account_added.connect(on_account_added);
        stream_interactor.stream_negotiated.connect(on_stream_negotiated);

        // Restore persisted status from database
        if (db != null) {
            var settings = new Dino.Entities.Settings.from_db(db);
            string saved_show = settings.presence_show;
            string saved_msg = settings.presence_status_msg;
            if (saved_show != null && saved_show.strip() != "") {
                this.current_show = saved_show;
            }
            if (saved_msg != null && saved_msg.strip() != "") {
                this.current_status_msg = saved_msg;
            } else {
                this.current_status_msg = null;
            }
        }
    }

    public void set_status(string show, string? status_msg) {
        this.current_show = show;
        this.current_status_msg = status_msg;

        // Persist to database
        if (db != null) {
            var settings = new Dino.Entities.Settings.from_db(db);
            settings.presence_show = show;
            settings.presence_status_msg = status_msg ?? "";
        }

        status_changed(show, status_msg);

        foreach (Account account in stream_interactor.get_accounts()) {
            XmppStream? stream = stream_interactor.get_stream(account);
            if (stream != null) {
                send_current_presence(stream);
            }
        }
    }

    /**
     * Resend presence for a specific account (e.g., after OpenPGP key change)
     */
    public void resend_presence(Account account) {
        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream != null) {
            send_current_presence(stream);
        }
    }

    private void send_current_presence(XmppStream stream) {
        var presence_module = stream.get_module<Xmpp.Presence.Module>(Xmpp.Presence.Module.IDENTITY);
        var presence = new Xmpp.Presence.Stanza();
        if (current_show != "online") {
            presence.show = current_show;
        }
        presence.status = current_status_msg;
        presence_module.send_presence(stream, presence);
    }

    private void on_stream_negotiated(Account account, XmppStream stream) {
        // The initial presence already has the correct status injected
        // via on_pre_send_presence, so we don't need to send a second one.
        // Just fire our signal so the UI updates.
        status_changed(current_show, current_status_msg);
    }

    public string? get_last_show(Jid jid, Account account) {
        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream == null) return null;

        Xmpp.Presence.Stanza? presence = stream.get_flag(Presence.Flag.IDENTITY).get_presence(jid);
        if (presence == null) return null;

        return presence.show;
    }

    public string? get_last_status_msg(Jid jid, Account account) {
        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream == null) return null;

        Xmpp.Presence.Stanza? presence = stream.get_flag(Presence.Flag.IDENTITY).get_presence(jid);
        if (presence == null) return null;

        return presence.status;
    }

    public Gee.List<Jid>? get_full_jids(Jid jid, Account account) {
        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream != null) {
            Xmpp.Presence.Flag flag = stream.get_flag(Presence.Flag.IDENTITY);
            if (flag == null) return null;
            return flag.get_resources(jid.bare_jid);
        }
        return null;
    }

    public bool exists_subscription_request(Account account, Jid jid) {
        return subscription_requests.contains(jid);
    }

    public void request_subscription(Account account, Jid jid) {
        XmppStream stream = stream_interactor.get_stream(account);
        if (stream != null) stream.get_module<Xmpp.Presence.Module>(Xmpp.Presence.Module.IDENTITY).request_subscription(stream, jid.bare_jid);
    }

    public void approve_subscription(Account account, Jid jid) {
        XmppStream stream = stream_interactor.get_stream(account);
        if (stream != null) {
            stream.get_module<Xmpp.Presence.Module>(Xmpp.Presence.Module.IDENTITY).approve_subscription(stream, jid.bare_jid);
            subscription_requests.remove(jid);
        }
    }

    public void deny_subscription(Account account, Jid jid) {
        XmppStream stream = stream_interactor.get_stream(account);
        if (stream != null) {
            stream.get_module<Xmpp.Presence.Module>(Xmpp.Presence.Module.IDENTITY).deny_subscription(stream, jid.bare_jid);
            subscription_requests.remove(jid);
        }
    }

    public void cancel_subscription(Account account, Jid jid) {
        XmppStream stream = stream_interactor.get_stream(account);
        if (stream != null) stream.get_module<Xmpp.Presence.Module>(Xmpp.Presence.Module.IDENTITY).cancel_subscription(stream, jid.bare_jid);
    }

    private void on_account_added(Account account) {
        stream_interactor.module_manager.get_module<Presence.Module>(account, Presence.Module.IDENTITY).pre_send_presence_stanza.connect(on_pre_send_presence);
        stream_interactor.module_manager.get_module<Presence.Module>(account, Presence.Module.IDENTITY).received_available_show.connect((stream, jid, show) =>
            on_received_available_show(account, jid, show)
        );
        stream_interactor.module_manager.get_module<Presence.Module>(account, Presence.Module.IDENTITY).received_unavailable.connect((stream, presence) =>
            on_received_unavailable(account, presence.from)
        );
        stream_interactor.module_manager.get_module<Presence.Module>(account, Presence.Module.IDENTITY).received_subscription_request.connect((stream, jid) => {
            if (!subscription_requests.contains(jid)) {
                subscription_requests.add(jid);
            }
            received_subscription_request(jid, account);
        });
        stream_interactor.module_manager.get_module<Presence.Module>(account, Presence.Module.IDENTITY).received_subscription_approval.connect((stream, jid) => {
            received_subscription_approval(jid, account);
        });
    }

    /**
     * Inject current status into any outgoing broadcast presence stanza.
     * This ensures the initial presence after stream negotiation already
     * carries the correct show/status, avoiding a brief "online" flash.
     */
    private void on_pre_send_presence(XmppStream stream, Xmpp.Presence.Stanza presence) {
        // Only modify broadcast presence (no 'to', no 'type') — don't touch subscriptions etc.
        if (presence.to != null || presence.type_ != Xmpp.Presence.Stanza.TYPE_AVAILABLE) return;
        if (current_show != "online" && (presence.show == null || presence.show == "online")) {
            presence.show = current_show;
        }
        if (current_status_msg != null && current_status_msg.strip() != "" && presence.status == null) {
            presence.status = current_status_msg;
        }
    }

    private void on_received_available_show(Account account, Jid jid, string show) {
        lock (resources) {
            if (!resources.has_key(jid)){
                resources[jid] = new ArrayList<Jid>(Jid.equals_func);
            }
            if (!resources[jid].contains(jid)) {
                resources[jid].add(jid);
            }
        }
        show_received(jid, account);
    }

    private void on_received_unavailable(Account account, Jid jid) {
        lock (resources) {
            if (resources.has_key(jid)) {
                resources[jid].remove(jid);
                if (resources[jid].size == 0 || jid.is_bare()) {
                    resources.unset(jid);
                }
            }
        }
        received_offline_presence(jid, account);
    }
}
}
