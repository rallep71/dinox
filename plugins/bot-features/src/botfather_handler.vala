using Gee;
using Dino.Entities;

namespace Dino.Plugins.BotFeatures {

// Chat command handler for @BotFather-style interactive bot management.
// Users interact with the BotFather by sending commands in a special conversation,
// or these commands can be invoked from the bot-manager UI.
public class BotfatherHandler : Object {

    private Dino.Application app;
    private BotRegistry registry;
    private TokenManager token_manager;

    public BotfatherHandler(Dino.Application app, BotRegistry registry, TokenManager token_manager) {
        this.app = app;
        this.registry = registry;
        this.token_manager = token_manager;
    }

    // Process a BotFather command from a user. Returns a response string.
    public string process_command(string owner_jid, string command_text) {
        string[] parts = command_text.strip().split(" ", 2);
        string cmd = parts[0].down();
        string? args = parts.length > 1 ? parts[1].strip() : null;

        switch (cmd) {
            case "/newbot":
                return cmd_newbot(owner_jid, args);
            case "/mybots":
                return cmd_mybots(owner_jid);
            case "/deletebot":
                return cmd_deletebot(owner_jid, args);
            case "/token":
                return cmd_token(owner_jid, args);
            case "/revoke":
                return cmd_revoke(owner_jid, args);
            case "/setcommands":
                return cmd_setcommands(owner_jid, args);
            case "/setdescription":
                return cmd_setdescription(owner_jid, args);
            case "/status":
                return cmd_status(owner_jid, args);
            case "/help":
            case "/start":
                return cmd_help();
            default:
                return "Unbekannter Befehl. Tippe /help fuer eine Liste der verfuegbaren Befehle.";
        }
    }

    // /newbot <name> -- Create a new bot
    private string cmd_newbot(string owner_jid, string? name) {
        if (name == null || name.strip().length == 0) {
            return "Bitte gib einen Namen fuer den Bot an:\n/newbot MeinBot";
        }

        string bot_name = name.strip();

        // Check max bots per user
        var existing = registry.get_bots_by_owner(owner_jid);
        if (existing.size >= 20) {
            return "Du hast bereits 20 Bots. Loesche zuerst einen mit /deletebot.";
        }

        // Create the bot
        string dummy_hash = "";
        int bot_id = registry.create_bot(bot_name, owner_jid, dummy_hash, "personal");

        // Generate token
        string raw_token = token_manager.generate_token(bot_id);

        registry.log_action(bot_id, "created", "owner=%s".printf(owner_jid));

        return "Bot '%s' wurde erstellt! (ID: %d)\n\nDein API-Token (nur einmal sichtbar!):\n\n%s\n\nBewahre diesen Token sicher auf. Du kannst ihn mit /token %d erneut generieren (der alte wird ungueltig).".printf(
            bot_name, bot_id, raw_token, bot_id);
    }

    // /mybots -- List all bots owned by the user
    private string cmd_mybots(string owner_jid) {
        var bots = registry.get_bots_by_owner(owner_jid);
        if (bots.size == 0) {
            return "Du hast noch keine Bots. Erstelle einen mit /newbot <Name>.";
        }

        var sb = new StringBuilder("Deine Bots:\n\n");
        foreach (BotInfo bot in bots) {
            sb.append("  #%d  %s  [%s]  Modus: %s\n".printf(
                bot.id, bot.name ?? "?", bot.status ?? "?", bot.mode ?? "?"));
        }
        sb.append("\nGesamt: %d Bot(s)".printf(bots.size));
        return sb.str;
    }

    // /deletebot <id> -- Delete a bot
    private string cmd_deletebot(string owner_jid, string? id_str) {
        if (id_str == null) {
            return "Bitte gib die Bot-ID an: /deletebot <ID>\nSiehe /mybots fuer deine Bot-IDs.";
        }

        int bot_id = int.parse(id_str.strip());
        BotInfo? bot = registry.get_bot_by_id(bot_id);
        if (bot == null || bot.owner_jid != owner_jid) {
            return "Bot #%d nicht gefunden oder gehoert dir nicht.".printf(bot_id);
        }

        string bot_name = bot.name ?? "?";
        registry.delete_bot(bot_id);
        registry.log_action(bot_id, "deleted", "owner=%s".printf(owner_jid));

        return "Bot '%s' (ID: %d) wurde geloescht. Token ist ungueltig.".printf(bot_name, bot_id);
    }

    // /token <id> -- Regenerate token for a bot
    private string cmd_token(string owner_jid, string? id_str) {
        if (id_str == null) {
            return "Bitte gib die Bot-ID an: /token <ID>";
        }

        int bot_id = int.parse(id_str.strip());
        BotInfo? bot = registry.get_bot_by_id(bot_id);
        if (bot == null || bot.owner_jid != owner_jid) {
            return "Bot #%d nicht gefunden oder gehoert dir nicht.".printf(bot_id);
        }

        string raw_token = token_manager.regenerate_token(bot_id);
        return "Neuer Token fuer '%s' (ID: %d):\n\n%s\n\nDer alte Token ist jetzt ungueltig.".printf(
            bot.name ?? "?", bot_id, raw_token);
    }

    // /revoke <id> -- Revoke token without generating a new one
    private string cmd_revoke(string owner_jid, string? id_str) {
        if (id_str == null) {
            return "Bitte gib die Bot-ID an: /revoke <ID>";
        }

        int bot_id = int.parse(id_str.strip());
        BotInfo? bot = registry.get_bot_by_id(bot_id);
        if (bot == null || bot.owner_jid != owner_jid) {
            return "Bot #%d nicht gefunden oder gehoert dir nicht.".printf(bot_id);
        }

        token_manager.revoke_token(bot_id);
        registry.update_bot_status(bot_id, "disabled");

        return "Token fuer '%s' (ID: %d) wurde widerrufen. Der Bot ist jetzt deaktiviert.\nGeneriere einen neuen Token mit /token %d".printf(
            bot.name ?? "?", bot_id, bot_id);
    }

    // /setcommands <id> /cmd1 - beschreibung, /cmd2 - beschreibung
    private string cmd_setcommands(string owner_jid, string? args) {
        if (args == null) {
            return "Nutzung: /setcommands <ID> /befehl1 - Beschreibung, /befehl2 - Beschreibung";
        }

        string[] tokens = args.strip().split(" ", 2);
        if (tokens.length < 2) {
            return "Nutzung: /setcommands <ID> /befehl1 - Beschreibung, /befehl2 - Beschreibung";
        }

        int bot_id = int.parse(tokens[0].strip());
        BotInfo? bot = registry.get_bot_by_id(bot_id);
        if (bot == null || bot.owner_jid != owner_jid) {
            return "Bot #%d nicht gefunden oder gehoert dir nicht.".printf(bot_id);
        }

        string commands_str = tokens[1].strip();
        var commands = new ArrayList<CommandInfo>();

        foreach (string part in commands_str.split(",")) {
            string trimmed = part.strip();
            if (trimmed.length == 0) continue;

            string[] cmd_parts = trimmed.split("-", 2);
            string command = cmd_parts[0].strip();
            string? description = cmd_parts.length > 1 ? cmd_parts[1].strip() : null;
            if (command.has_prefix("/")) command = command.substring(1);
            commands.add(new CommandInfo(command, description));
        }

        if (commands.size == 0) {
            return "Keine gueltige Befehle erkannt. Format: /cmd - Beschreibung";
        }

        registry.set_bot_commands(bot_id, commands);
        return "%d Befehl(e) gesetzt fuer '%s'.".printf(commands.size, bot.name ?? "?");
    }

    // /setdescription <id> <text>
    private string cmd_setdescription(string owner_jid, string? args) {
        if (args == null) {
            return "Nutzung: /setdescription <ID> <Beschreibungstext>";
        }

        string[] tokens = args.strip().split(" ", 2);
        if (tokens.length < 2) {
            return "Nutzung: /setdescription <ID> <Beschreibungstext>";
        }

        int bot_id = int.parse(tokens[0].strip());
        BotInfo? bot = registry.get_bot_by_id(bot_id);
        if (bot == null || bot.owner_jid != owner_jid) {
            return "Bot #%d nicht gefunden oder gehoert dir nicht.".printf(bot_id);
        }

        // Update description directly via SQL
        registry.bot.update()
            .with(registry.bot.id, "=", bot_id)
            .set(registry.bot.description, tokens[1].strip())
            .perform();

        return "Beschreibung fuer '%s' aktualisiert.".printf(bot.name ?? "?");
    }

    // /status [id] -- Show bot status
    private string cmd_status(string owner_jid, string? id_str) {
        if (id_str == null) {
            // Show overall status
            var bots = registry.get_bots_by_owner(owner_jid);
            int active = 0;
            foreach (BotInfo b in bots) {
                if (b.status == "active") active++;
            }
            return "Status: %d Bot(s) gesamt, %d aktiv.\nHTTP API: localhost:7842".printf(bots.size, active);
        }

        int bot_id = int.parse(id_str.strip());
        BotInfo? bot = registry.get_bot_by_id(bot_id);
        if (bot == null || bot.owner_jid != owner_jid) {
            return "Bot #%d nicht gefunden oder gehoert dir nicht.".printf(bot_id);
        }

        var sb = new StringBuilder();
        sb.append("Bot: %s (ID: %d)\n".printf(bot.name ?? "?", bot.id));
        sb.append("Status: %s\n".printf(bot.status ?? "?"));
        sb.append("Modus: %s\n".printf(bot.mode ?? "?"));
        sb.append("JID: %s\n".printf(bot.jid ?? "(persoenlich)"));
        sb.append("Webhook: %s\n".printf(bot.webhook_enabled ? (bot.webhook_url ?? "?") : "deaktiviert"));

        var cmds = registry.get_bot_commands(bot.id);
        if (cmds.size > 0) {
            sb.append("Befehle: %d\n".printf(cmds.size));
        }

        return sb.str;
    }

    // /help -- Show available commands
    private string cmd_help() {
        return "DinoX BotFather - Bot-Verwaltung\n\n" +
            "Verfuegbare Befehle:\n" +
            "  /newbot <Name>         - Neuen Bot erstellen\n" +
            "  /mybots                - Alle Bots auflisten\n" +
            "  /deletebot <ID>        - Bot loeschen\n" +
            "  /token <ID>            - Token neu generieren\n" +
            "  /revoke <ID>           - Token widerrufen (Bot deaktivieren)\n" +
            "  /setcommands <ID> ...  - Bot-Befehle setzen\n" +
            "  /setdescription <ID> . - Bot-Beschreibung setzen\n" +
            "  /status [ID]           - Status anzeigen\n" +
            "  /help                  - Diese Hilfe\n\n" +
            "HTTP API: http://localhost:7842\n" +
            "Doku: /bot/getMe, /bot/sendMessage, /bot/getUpdates, ...";
    }
}

}
