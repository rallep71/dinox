using Gee;

using Xmpp;
using Dino.Entities;

namespace Dino {

public class BlockingManager : StreamInteractionModule, Object {
    public static ModuleIdentity<BlockingManager> IDENTITY = new ModuleIdentity<BlockingManager>("blocking_manager");
    public string id { get { return IDENTITY.id; } }

    public signal void block_changed(Account account, Jid jid);

    private StreamInteractor stream_interactor;

    public static void start(StreamInteractor stream_interactor) {
        BlockingManager m = new BlockingManager(stream_interactor);
        stream_interactor.add_module(m);
    }

    private BlockingManager(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
        
        stream_interactor.stream_negotiated.connect((account, stream) => {
            stream.get_module(Xmpp.Xep.BlockingCommand.Module.IDENTITY).block_push_received.connect((stream, jids) => {
                foreach (string jid_str in jids) {
                    try {
                        block_changed(account, new Jid(jid_str));
                    } catch (Error e) {
                        warning("BlockingManager: Failed to process block push for %s: %s", jid_str, e.message);
                    }
                }
            });
            stream.get_module(Xmpp.Xep.BlockingCommand.Module.IDENTITY).unblock_push_received.connect((stream, jids) => {
                foreach (string jid_str in jids) {
                    try {
                        block_changed(account, new Jid(jid_str));
                    } catch (Error e) {
                        warning("BlockingManager: Failed to process unblock push for %s: %s", jid_str, e.message);
                    }
                }
            });
        });
    }

    public bool is_blocked(Account account, Jid jid) {
        XmppStream stream = stream_interactor.get_stream(account);
        return stream != null && stream.get_module(Xmpp.Xep.BlockingCommand.Module.IDENTITY).is_blocked(stream, jid.to_string());
    }

    public void block(Account account, Jid jid) {
        XmppStream stream = stream_interactor.get_stream(account);
        stream.get_module(Xmpp.Xep.BlockingCommand.Module.IDENTITY).block(stream, { jid.to_string() });
        // Emit signal immediately for UI responsiveness
        block_changed(account, jid);
    }

    public void unblock(Account account, Jid jid) {
        XmppStream stream = stream_interactor.get_stream(account);
        stream.get_module(Xmpp.Xep.BlockingCommand.Module.IDENTITY).unblock(stream, { jid.to_string() });
        // Emit signal immediately for UI responsiveness
        block_changed(account, jid);
    }

    public bool is_supported(Account account) {
        XmppStream stream = stream_interactor.get_stream(account);
        return stream != null && stream.get_module(Xmpp.Xep.BlockingCommand.Module.IDENTITY).is_supported(stream);
    }
}

}
