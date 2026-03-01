using Gee;

namespace Dino.Plugins.BotFeatures {

/**
 * AI Integration for dedicated bots.
 * Supports:
 *   - OpenAI (GPT-4, GPT-4o, o1, ...)
 *   - Claude / Anthropic (claude-sonnet-4-20250514, Haiku, Opus)
 *   - Google Gemini (gemini-pro, gemini-1.5-pro, gemini-2.0-flash)
 *   - Groq (llama-3.3-70b, mixtral, gemma2)
 *   - Mistral (mistral-large, mistral-medium)
 *   - Ollama (lokal: llama3, phi3, gemma, ...)
 *   - OpenClaw (autonomer AI-Agent / Orchestrator)
 *   - Jede OpenAI-kompatible API (vLLM, LM Studio, text-generation-webui, ...)
 *
 * Settings per bot (in bot_registry):
 *   bot_{id}_ai_enabled      = "true" / "false"
 *   bot_{id}_ai_endpoint     = API URL
 *   bot_{id}_ai_key          = API key (empty for Ollama)
 *   bot_{id}_ai_model        = model name
 *   bot_{id}_ai_system       = system prompt
 *   bot_{id}_ai_type         = "openai" / "claude" / "gemini" / "ollama"
 */
public class AiIntegration : Object {

    private BotRegistry registry;
    private Soup.Session http;

    // Per-bot conversation history (last N messages for context)
    private HashMap<string, ArrayList<ChatMessage>> histories;
    private const int MAX_HISTORY = 20;
    private const int MAX_HISTORY_KEYS = 100;  // BUG-13 fix: max unique bot+JID combos

    // Provider preset info
    public class ProviderPreset {
        public string ai_type;
        public string endpoint;
        public ProviderPreset(string ai_type, string endpoint) {
            this.ai_type = ai_type;
            this.endpoint = endpoint;
        }
    }

    // Provider presets: name -> ProviderPreset
    private HashMap<string, ProviderPreset> presets;

    public AiIntegration(BotRegistry registry) {
        this.registry = registry;
        this.http = new Soup.Session();
        this.http.timeout = 60;
        this.histories = new HashMap<string, ArrayList<ChatMessage>>();

        // Initialize provider presets
        presets = new HashMap<string, ProviderPreset>();
        presets["openai"]  = new ProviderPreset("openai", "https://api.openai.com/v1/chat/completions");
        presets["claude"]  = new ProviderPreset("claude", "https://api.anthropic.com/v1/messages");
        presets["gemini"]  = new ProviderPreset("gemini", "https://generativelanguage.googleapis.com/v1beta");
        presets["groq"]    = new ProviderPreset("openai", "https://api.groq.com/openai/v1/chat/completions");
        presets["mistral"] = new ProviderPreset("openai", "https://api.mistral.ai/v1/chat/completions");
        presets["ollama"]  = new ProviderPreset("ollama", "http://localhost:11434");
        presets["deepseek"]= new ProviderPreset("openai", "https://api.deepseek.com/v1/chat/completions");
        presets["perplexity"] = new ProviderPreset("openai", "https://api.perplexity.ai/chat/completions");
        presets["openclaw"]  = new ProviderPreset("openclaw", "http://localhost:18789/hooks/agent");
    }

    public class ChatMessage {
        public string role;
        public string content;
        public ChatMessage(string role, string content) {
            this.role = role;
            this.content = content;
        }
    }

    // Check if AI is enabled for a bot
    public bool is_enabled(int bot_id) {
        string? val = registry.get_setting("bot_%d_ai_enabled".printf(bot_id));
        return val == "true";
    }

    // Configure AI for a bot
    public void configure(int bot_id, string ai_type, string endpoint, string api_key,
                          string model, string system_prompt) {
        string prefix = "bot_%d_ai".printf(bot_id);
        registry.set_setting(prefix + "_enabled", "true");
        registry.set_setting(prefix + "_type", ai_type);
        registry.set_setting(prefix + "_endpoint", endpoint);
        registry.set_setting(prefix + "_key", api_key);
        registry.set_setting(prefix + "_model", model);
        registry.set_setting(prefix + "_system", system_prompt);
        message("AI: Configured for bot %d: type=%s model=%s endpoint=%s", bot_id, ai_type, model, endpoint);
    }

    // Configure using a preset provider name
    public string configure_preset(int bot_id, string provider, string api_key, string model) {
        string provider_lower = provider.down();
        if (!presets.has_key(provider_lower)) {
            var sb = new StringBuilder();
            sb.append("Unbekannter Anbieter: %s\n\nVerfuegbare Anbieter:\n".printf(provider));
            foreach (var key in presets.keys) {
                sb.append("  %s\n".printf(key));
            }
            return sb.str;
        }

        ProviderPreset preset = presets[provider_lower];
        string ai_type = preset.ai_type;
        string endpoint = preset.endpoint;

        configure(bot_id, ai_type, endpoint,
                  api_key == "-" ? "" : api_key, model,
                  "Du bist ein hilfreicher Assistent.");

        return "KI konfiguriert und aktiviert!\nAnbieter: %s\nTyp: %s\nModell: %s".printf(
            provider_lower, ai_type, model);
    }

    // Disable AI for a bot
    public void disable(int bot_id) {
        registry.set_setting("bot_%d_ai_enabled".printf(bot_id), "false");
        // Clear history
        clear_history(bot_id, "all");
        message("AI: Disabled for bot %d", bot_id);
    }

    // Clear conversation history
    public void clear_history(int bot_id, string from_jid) {
        if (from_jid == "all") {
            var to_remove = new ArrayList<string>();
            foreach (var key in histories.keys) {
                if (key.has_prefix("%d:".printf(bot_id))) {
                    to_remove.add(key);
                }
            }
            foreach (var key in to_remove) {
                histories.unset(key);
            }
        } else {
            string hkey = "%d:%s".printf(bot_id, from_jid);
            histories.unset(hkey);
        }
    }

    // Get current AI config as status string
    public string get_status(int bot_id) {
        string prefix = "bot_%d_ai".printf(bot_id);
        bool enabled = is_enabled(bot_id);
        if (!enabled) {
            return "KI: deaktiviert";
        }
        string ai_type = registry.get_setting(prefix + "_type") ?? "openai";
        string model = registry.get_setting(prefix + "_model") ?? "?";
        string endpoint = registry.get_setting(prefix + "_endpoint") ?? "?";
        string system = registry.get_setting(prefix + "_system") ?? "(Standard)";
        return "KI: aktiv\nTyp: %s\nModell: %s\nEndpunkt: %s\nSystem-Prompt: %s".printf(
            ai_type, model, endpoint, system);
    }

    // Get help text for available providers
    public string get_providers_help() {
        return "Verfuegbare KI-Anbieter:\n\n" +
            "openai    - OpenAI (gpt-4, gpt-4o, gpt-4o-mini, o1)\n" +
            "claude    - Anthropic (claude-sonnet-4-20250514, claude-3-haiku, claude-3-opus)\n" +
            "gemini    - Google (gemini-2.0-flash, gemini-1.5-pro, gemini-pro)\n" +
            "groq      - Groq (llama-3.3-70b-versatile, mixtral-8x7b)\n" +
            "mistral   - Mistral (mistral-large-latest, mistral-medium)\n" +
            "deepseek  - DeepSeek (deepseek-chat, deepseek-coder)\n" +
            "perplexity- Perplexity (sonar-medium, sonar-small)\n" +
            "ollama    - Lokal (llama3, phi3, gemma, mistral, ...)\n" +
            "openclaw  - OpenClaw Agent (autonomous AI orchestrator)\n\n" +
            "Einrichten:\n" +
            "/ki setup <anbieter> <api_key> <model>\n\n" +
            "Beispiele:\n" +
            "/ki setup openai sk-abc123 gpt-4o\n" +
            "/ki setup claude sk-ant-abc123 claude-sonnet-4-20250514\n" +
            "/ki setup gemini AIza-abc123 gemini-2.0-flash\n" +
            "/ki setup groq gsk_abc123 llama-3.3-70b-versatile\n" +
            "/ki setup ollama - llama3\n" +
            "/ki setup openclaw <token> agent";
    }

    // Send a message to the AI and get a response asynchronously
    public async string? ask(int bot_id, string from_jid, string question) {
        string prefix = "bot_%d_ai".printf(bot_id);
        string? ai_type = registry.get_setting(prefix + "_type") ?? "openai";
        string? endpoint = registry.get_setting(prefix + "_endpoint");
        string? api_key = registry.get_setting(prefix + "_key") ?? "";
        string? model = registry.get_setting(prefix + "_model");
        string? system_prompt = registry.get_setting(prefix + "_system") ?? "Du bist ein hilfreicher Assistent.";

        if (endpoint == null || model == null) {
            return "KI nicht konfiguriert.\n\n" + get_providers_help();
        }

        // Build conversation history
        string hkey = "%d:%s".printf(bot_id, from_jid);
        if (!histories.has_key(hkey)) {
            // BUG-13 fix: Evict oldest entries if we have too many unique conversations
            if (histories.size >= MAX_HISTORY_KEYS) {
                // Remove first key (oldest insertion)
                string? oldest_key = null;
                foreach (var key in histories.keys) {
                    oldest_key = key;
                    break;
                }
                if (oldest_key != null) histories.unset(oldest_key);
            }
            histories[hkey] = new ArrayList<ChatMessage>();
        }
        var history = histories[hkey];
        history.add(new ChatMessage("user", question));

        // Trim history
        while (history.size > MAX_HISTORY) {
            history.remove_at(0);
        }

        string? response = null;
        try {
            switch (ai_type) {
                case "ollama":
                    response = yield ask_ollama(endpoint, model, system_prompt, history);
                    break;
                case "claude":
                    response = yield ask_claude(endpoint, api_key, model, system_prompt, history);
                    break;
                case "gemini":
                    response = yield ask_gemini(endpoint, api_key, model, system_prompt, history);
                    break;
                case "openclaw":
                    response = yield ask_openclaw(endpoint, api_key, history);
                    break;
                default: // openai and all compatible APIs
                    response = yield ask_openai(endpoint, api_key, model, system_prompt, history);
                    break;
            }
        } catch (Error e) {
            warning("AI: Request failed: %s", e.message);
            return "KI-Fehler: %s".printf(e.message);
        }

        if (response != null) {
            history.add(new ChatMessage("assistant", response));
            while (history.size > MAX_HISTORY) {
                history.remove_at(0);
            }
        }

        return response;
    }

    // ──────────────────────────────────────────
    // OpenAI-compatible API (OpenAI, Groq, Mistral, DeepSeek, Perplexity, vLLM, LM Studio)
    // ──────────────────────────────────────────
    private async string? ask_openai(string endpoint, string api_key, string model,
                                      string system_prompt, ArrayList<ChatMessage> history) throws Error {
        var sb = new StringBuilder();
        sb.append("{\"model\":\"%s\",\"messages\":[".printf(escape_json(model)));
        sb.append("{\"role\":\"system\",\"content\":\"%s\"}".printf(escape_json(system_prompt)));
        foreach (var msg in history) {
            sb.append(",{\"role\":\"%s\",\"content\":\"%s\"}".printf(
                escape_json(msg.role), escape_json(msg.content)));
        }
        sb.append("],\"max_tokens\":2048,\"temperature\":0.7}");

        var request = new Soup.Message("POST", endpoint);
        request.set_request_body_from_bytes("application/json", new Bytes.take(sb.str.data));
        if (api_key != null && api_key != "") {
            request.get_request_headers().append("Authorization", "Bearer " + api_key);
        }

        var response = yield http.send_and_read_async(request, GLib.Priority.DEFAULT, null);
        uint status = request.get_status();

        if (status < 200 || status >= 300) {
            string body_text = (string) response.get_data();
            warning("AI OpenAI: HTTP %u - %s", status, body_text);
            return "KI HTTP-Fehler %u".printf(status);
        }

        string body_text = (string) response.get_data();
        var parser = new Json.Parser();
        parser.load_from_data(body_text, -1);
        var root = parser.get_root().get_object();

        if (root.has_member("choices")) {
            var choices = root.get_array_member("choices");
            if (choices.get_length() > 0) {
                var choice = choices.get_object_element(0);
                var message_obj = choice.get_object_member("message");
                return message_obj.get_string_member("content");
            }
        }

        if (root.has_member("error")) {
            var err = root.get_object_member("error");
            return "KI-Fehler: %s".printf(err.get_string_member("message"));
        }

        return "KI: Unerwartete Antwort";
    }

    // ──────────────────────────────────────────
    // Anthropic Claude API
    // ──────────────────────────────────────────
    private async string? ask_claude(string endpoint, string api_key, string model,
                                      string system_prompt, ArrayList<ChatMessage> history) throws Error {
        var sb = new StringBuilder();
        sb.append("{\"model\":\"%s\",\"max_tokens\":2048,\"system\":\"%s\",\"messages\":[".printf(
            escape_json(model), escape_json(system_prompt)));

        bool first = true;
        foreach (var msg in history) {
            if (!first) sb.append(",");
            sb.append("{\"role\":\"%s\",\"content\":\"%s\"}".printf(
                escape_json(msg.role), escape_json(msg.content)));
            first = false;
        }
        sb.append("]}");

        var request = new Soup.Message("POST", endpoint);
        request.set_request_body_from_bytes("application/json", new Bytes.take(sb.str.data));
        request.get_request_headers().append("x-api-key", api_key);
        request.get_request_headers().append("anthropic-version", "2023-06-01");
        request.get_request_headers().append("Content-Type", "application/json");

        var response = yield http.send_and_read_async(request, GLib.Priority.DEFAULT, null);
        uint status = request.get_status();

        if (status < 200 || status >= 300) {
            string body_text = (string) response.get_data();
            warning("AI Claude: HTTP %u - %s", status, body_text);
            return "KI HTTP-Fehler %u".printf(status);
        }

        string body_text = (string) response.get_data();
        var parser = new Json.Parser();
        parser.load_from_data(body_text, -1);
        var root = parser.get_root().get_object();

        // Claude response: { "content": [{"type": "text", "text": "..."}] }
        if (root.has_member("content")) {
            var content = root.get_array_member("content");
            if (content.get_length() > 0) {
                var block = content.get_object_element(0);
                if (block.has_member("text")) {
                    return block.get_string_member("text");
                }
            }
        }

        if (root.has_member("error")) {
            var err = root.get_object_member("error");
            return "Claude-Fehler: %s".printf(err.get_string_member("message"));
        }

        return "KI: Unerwartete Claude-Antwort";
    }

    // ──────────────────────────────────────────
    // Google Gemini API
    // ──────────────────────────────────────────
    private async string? ask_gemini(string endpoint, string api_key, string model,
                                      string system_prompt, ArrayList<ChatMessage> history) throws Error {
        // Gemini URL: {endpoint}/models/{model}:generateContent?key={api_key}
        string base_url = endpoint;
        if (base_url.has_suffix("/")) base_url = base_url.substring(0, base_url.length - 1);
        string url = "%s/models/%s:generateContent?key=%s".printf(base_url, model, api_key);

        var sb = new StringBuilder();
        sb.append("{");

        // System instruction
        sb.append("\"systemInstruction\":{\"parts\":[{\"text\":\"%s\"}]},".printf(escape_json(system_prompt)));

        // Contents (conversation history)
        sb.append("\"contents\":[");
        bool first = true;
        foreach (var msg in history) {
            if (!first) sb.append(",");
            // Gemini uses "user" and "model" (not "assistant")
            string role = msg.role == "assistant" ? "model" : "user";
            sb.append("{\"role\":\"%s\",\"parts\":[{\"text\":\"%s\"}]}".printf(
                role, escape_json(msg.content)));
            first = false;
        }
        sb.append("],");

        // Generation config
        sb.append("\"generationConfig\":{\"temperature\":0.7,\"maxOutputTokens\":2048}");
        sb.append("}");

        var request = new Soup.Message("POST", url);
        request.set_request_body_from_bytes("application/json", new Bytes.take(sb.str.data));

        var response = yield http.send_and_read_async(request, GLib.Priority.DEFAULT, null);
        uint status = request.get_status();

        if (status < 200 || status >= 300) {
            string body_text = (string) response.get_data();
            warning("AI Gemini: HTTP %u - %s", status, body_text);
            return "KI HTTP-Fehler %u".printf(status);
        }

        string body_text = (string) response.get_data();
        var parser = new Json.Parser();
        parser.load_from_data(body_text, -1);
        var root = parser.get_root().get_object();

        // Gemini response: { "candidates": [{"content": {"parts": [{"text": "..."}]}}] }
        if (root.has_member("candidates")) {
            var candidates = root.get_array_member("candidates");
            if (candidates.get_length() > 0) {
                var candidate = candidates.get_object_element(0);
                if (candidate.has_member("content")) {
                    var content = candidate.get_object_member("content");
                    if (content.has_member("parts")) {
                        var parts = content.get_array_member("parts");
                        if (parts.get_length() > 0) {
                            var part = parts.get_object_element(0);
                            if (part.has_member("text")) {
                                return part.get_string_member("text");
                            }
                        }
                    }
                }
            }
        }

        if (root.has_member("error")) {
            var err = root.get_object_member("error");
            return "Gemini-Fehler: %s".printf(err.get_string_member("message"));
        }

        return "KI: Unerwartete Gemini-Antwort";
    }

    // ──────────────────────────────────────────
    // Ollama native API (lokal)
    // ──────────────────────────────────────────
    private async string? ask_ollama(string endpoint, string model,
                                      string system_prompt, ArrayList<ChatMessage> history) throws Error {
        string url = endpoint;
        if (!url.has_suffix("/api/chat")) {
            if (url.has_suffix("/")) url = url.substring(0, url.length - 1);
            url = url + "/api/chat";
        }

        var sb = new StringBuilder();
        sb.append("{\"model\":\"%s\",\"stream\":false,\"messages\":[".printf(escape_json(model)));
        sb.append("{\"role\":\"system\",\"content\":\"%s\"}".printf(escape_json(system_prompt)));
        foreach (var msg in history) {
            sb.append(",{\"role\":\"%s\",\"content\":\"%s\"}".printf(
                escape_json(msg.role), escape_json(msg.content)));
        }
        sb.append("]}");

        var request = new Soup.Message("POST", url);
        request.set_request_body_from_bytes("application/json", new Bytes.take(sb.str.data));

        var response = yield http.send_and_read_async(request, GLib.Priority.DEFAULT, null);
        uint status = request.get_status();

        if (status < 200 || status >= 300) {
            string body_text = (string) response.get_data();
            warning("AI Ollama: HTTP %u - %s", status, body_text);
            return "KI HTTP-Fehler %u".printf(status);
        }

        string body_text = (string) response.get_data();
        var parser = new Json.Parser();
        parser.load_from_data(body_text, -1);
        var root = parser.get_root().get_object();

        if (root.has_member("message")) {
            var msg_obj = root.get_object_member("message");
            return msg_obj.get_string_member("content");
        }

        return "KI: Unerwartete Ollama-Antwort";
    }

    // ──────────────────────────────────────────
    // OpenClaw Agent API (autonomous orchestrator)
    // ──────────────────────────────────────────
    private async string? ask_openclaw(string endpoint, string api_key,
                                       ArrayList<ChatMessage> history) throws Error {
        // OpenClaw uses a simple {"message": "..."} format
        // Only send the last user message (agent manages its own context)
        string last_msg = "";
        for (int i = history.size - 1; i >= 0; i--) {
            if (history[i].role == "user") {
                last_msg = history[i].content;
                break;
            }
        }

        var sb = new StringBuilder();
        sb.append("{\"message\":\"%s\"}".printf(escape_json(last_msg)));

        var request = new Soup.Message("POST", endpoint);
        request.set_request_body_from_bytes("application/json", new Bytes.take(sb.str.data));
        if (api_key != null && api_key != "") {
            request.get_request_headers().append("Authorization", "Bearer " + api_key);
        }

        var response = yield http.send_and_read_async(request, GLib.Priority.DEFAULT, null);
        uint status = request.get_status();

        if (status < 200 || status >= 300) {
            string body_text = (string) response.get_data();
            warning("AI OpenClaw: HTTP %u - %s", status, body_text);
            return "OpenClaw HTTP error %u".printf(status);
        }

        string body_text = (string) response.get_data();
        if (body_text == null || body_text.strip() == "") {
            return "OpenClaw: Empty response";
        }

        // Try JSON response first
        try {
            var parser = new Json.Parser();
            parser.load_from_data(body_text, -1);
            var root = parser.get_root();
            if (root != null && root.get_node_type() == Json.NodeType.OBJECT) {
                var obj = root.get_object();
                // Try common response fields
                foreach (string field in new string[]{"response", "text", "message", "content", "reply", "result"}) {
                    if (obj.has_member(field)) {
                        var node = obj.get_member(field);
                        if (node.get_node_type() == Json.NodeType.VALUE) {
                            return node.get_string();
                        }
                    }
                }
                // If JSON but no known field, return the whole body
                return body_text.strip();
            }
        } catch (Error e) {
            // Not JSON - treat as plain text
        }

        return body_text.strip();
    }

    public void shutdown() {
        http.abort();
    }

    // Cleanup all settings for a bot
    public void cleanup(int bot_id) {
        string prefix = "bot_%d_ai".printf(bot_id);
        registry.delete_setting(prefix + "_enabled");
        registry.delete_setting(prefix + "_type");
        registry.delete_setting(prefix + "_endpoint");
        registry.delete_setting(prefix + "_key");
        registry.delete_setting(prefix + "_model");
        registry.delete_setting(prefix + "_system");
        clear_history(bot_id, "all");
    }

    // RFC 8259 compliant JSON string escaping (BUG-05 fix)
    private static string escape_json(string s) {
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

} // namespace
