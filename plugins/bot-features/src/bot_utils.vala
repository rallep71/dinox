// Static utility functions shared across bot-features plugin modules.
// Extracted from ai_integration.vala / telegram_bridge.vala / ejabberd_api.vala
// to eliminate code duplication (clone detection).

namespace Dino.Plugins.BotFeatures.BotUtils {

    // RFC 8259 compliant JSON string escaping (BUG-05 fix)
    public static string escape_json(string s) {
        var sb = new StringBuilder.sized(s.length);
        for (int i = 0; i < s.length; i++) {
            unichar c = s[i];
            if (c == '\\') sb.append("\\\\");
            else if (c == '"') sb.append("\\\"");
            else if (c == '\n') sb.append("\\n");
            else if (c == '\r') sb.append("\\r");
            else if (c == '\t') sb.append("\\t");
            else if (c < 0x20) sb.append("\\u%04x".printf(c));
            else sb.append_unichar(c);
        }
        return sb.str;
    }
}
