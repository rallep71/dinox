using Gee;
using Xmpp;
using Dino.Entities;

namespace Dino.Plugins.BotFeatures {

// Manages XMPP streams for bot accounts.
// In "personal" mode, bots share the user's existing stream.
// In "server" mode, bots have their own XMPP sessions.
public class SessionPool : Object {

    private Dino.Application app;
    // Map bot_id -> Account to track which DinoX account a personal bot uses
    private HashMap<int, Account> personal_bindings = new HashMap<int, Account>();

    public SessionPool(Dino.Application app) {
        this.app = app;
    }

    // For personal mode: bind a bot to the user's active account
    public void bind_personal(int bot_id, Account account) {
        personal_bindings[bot_id] = account;
    }

    public void unbind(int bot_id) {
        personal_bindings.unset(bot_id);
    }

    // Get the XMPP stream for a bot.
    // For personal mode, returns the user's connected stream.
    public XmppStream? get_stream(BotInfo bot) {
        if (bot.mode == "personal") {
            Account? account = personal_bindings[bot.id];
            if (account == null) {
                // Try to use the first active account
                account = get_first_active_account();
                if (account != null) {
                    personal_bindings[bot.id] = account;
                }
            }
            if (account != null) {
                return app.stream_interactor.get_stream(account);
            }
        }
        // For server mode, we would have dedicated connections
        // This is a Phase 2 feature
        return null;
    }

    // Get a Jid to send from for a personal-mode bot
    public Jid? get_sender_jid(BotInfo bot) {
        if (bot.mode == "personal") {
            Account? account = personal_bindings[bot.id];
            if (account == null) account = get_first_active_account();
            if (account != null) {
                return account.bare_jid;
            }
        }
        // For server mode, the bot has its own JID
        if (bot.jid != null) {
            try {
                return new Jid(bot.jid);
            } catch (Error e) {
                warning("Invalid bot JID: %s", bot.jid);
            }
        }
        return null;
    }

    public Account? get_account_for_bot(BotInfo bot) {
        if (bot.mode == "personal") {
            Account? account = personal_bindings[bot.id];
            if (account == null) account = get_first_active_account();
            return account;
        }
        return null;
    }

    private Account? get_first_active_account() {
        foreach (Account account in app.stream_interactor.get_accounts()) {
            if (app.stream_interactor.get_stream(account) != null) {
                return account;
            }
        }
        return null;
    }

    public void disconnect_all() {
        personal_bindings.clear();
    }
}

}
