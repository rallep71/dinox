/**
 * MqttUtils — Pure utility functions for the MQTT plugin.
 *
 * All methods are static and free of runtime/DB/UI dependencies.
 * This enables standalone unit testing without the full plugin.
 *
 * Extracted from: alert_manager.vala, bridge_manager.vala, bot_conversation.vala
 */

namespace Dino.Plugins.Mqtt {

public class MqttUtils : Object {

    /**
     * MQTT 3.1.1 §4.7 — Topic filter matching with wildcards.
     *
     * Supports:
     *   - Exact match: "home/temp" matches "home/temp"
     *   - Single-level wildcard (+): "home/+/temp" matches "home/living/temp"
     *   - Multi-level wildcard (#): "home/#" matches "home/living/temp"
     *   - Universal wildcard: "#" matches everything
     *
     * @param pattern  The topic filter pattern (may contain + and #)
     * @param topic    The incoming concrete topic name
     * @return true if the topic matches the filter pattern
     */
    public static bool topic_matches(string pattern, string topic) {
        if (pattern == topic) return true;
        if (pattern == "#") return true;

        string[] rule_parts = pattern.split("/");
        string[] topic_parts = topic.split("/");

        int ri = 0;
        int ti = 0;
        while (ri < rule_parts.length && ti < topic_parts.length) {
            if (rule_parts[ri] == "#") return true;
            if (rule_parts[ri] == "+") {
                ri++;
                ti++;
                continue;
            }
            if (rule_parts[ri] != topic_parts[ti]) return false;
            ri++;
            ti++;
        }

        return ri == rule_parts.length && ti == topic_parts.length;
    }

    /**
     * Prosody topic format conversion.
     *
     * Prosody mod_pubsub_mqtt uses topic format: HOST/pubsub/NODE
     * (e.g. "pubsub.example.org/pubsub/sensors").
     *
     * This converts to human-readable: "sensors (PubSub@pubsub.example.org)"
     *
     * Non-Prosody topics are returned unchanged.
     *
     * @param topic  The MQTT topic string
     * @return Human-readable topic display string
     */
    public static string format_topic_display(string topic) {
        if (topic.contains("/pubsub/")) {
            int pubsub_idx = topic.index_of("/pubsub/");
            if (pubsub_idx > 0) {
                string host = topic.substring(0, pubsub_idx);
                string node = topic.substring(pubsub_idx + 8);  /* skip /pubsub/ */
                if (host.contains(".") && node.length > 0) {
                    return "%s (PubSub@%s)".printf(node, host);
                }
            }
        }
        return topic;
    }

    /**
     * Extract a numeric value from a payload string.
     *
     * Attempts:
     *   1. Direct double parse of the trimmed string
     *   2. JSON: first numeric field value from a JSON object
     *
     * @param payload  The MQTT message payload
     * @return The numeric value, or null if not extractable
     */
    public static double? try_extract_numeric(string payload) {
        string trimmed = payload.strip();

        /* Empty string is not numeric */
        if (trimmed == "") return null;

        /* Try direct parse */
        double val;
        if (double.try_parse(trimmed, out val)) {
            return val;
        }

        /* Try JSON: first numeric field */
        if (trimmed.has_prefix("{")) {
            try {
                var parser = new Json.Parser();
                parser.load_from_data(trimmed, -1);
                var root = parser.get_root();
                if (root != null && root.get_node_type() == Json.NodeType.OBJECT) {
                    var obj = root.get_object();
                    foreach (string member in obj.get_members()) {
                        var node = obj.get_member(member);
                        if (node.get_node_type() == Json.NodeType.VALUE) {
                            var vt = node.get_value_type();
                            if (vt == typeof(double)) {
                                return node.get_double();
                            } else if (vt == typeof(int64)) {
                                return (double) node.get_int();
                            }
                        }
                    }
                }
            } catch (GLib.Error e) {
                /* not valid JSON */
            }
        }

        return null;
    }

    /**
     * Unicode sparkline block characters (8 levels).
     * Index 0 = lowest bar, index 7 = highest bar.
     */
    public const string[] SPARK_CHARS = {
        "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"
    };

    /**
     * Build a Unicode sparkline string from numeric values.
     *
     * Maps values to 8-level block characters based on min/max range.
     * Returns null if fewer than 2 values are provided.
     *
     * @param values  Array of numeric values
     * @return Sparkline string, or null if insufficient data
     */
    public static string? build_sparkline(double[] values) {
        if (values.length < 2) return null;

        double min_val = values[0];
        double max_val = values[0];
        for (int i = 1; i < values.length; i++) {
            if (values[i] < min_val) min_val = values[i];
            if (values[i] > max_val) max_val = values[i];
        }

        double range = max_val - min_val;
        if (range < 0.001) range = 1.0;  /* avoid div by zero for constant values */

        var sb = new StringBuilder();
        foreach (double v in values) {
            int idx = (int) (((v - min_val) / range) * 7.0 + 0.5);
            if (idx < 0) idx = 0;
            if (idx > 7) idx = 7;
            sb.append(SPARK_CHARS[idx]);
        }

        return sb.str;
    }

    /**
     * Sparkline statistics: min, max, average.
     *
     * @param values  Array of numeric values (must be non-empty)
     * @param out_min  Output: minimum value
     * @param out_max  Output: maximum value
     * @param out_avg  Output: average value
     */
    public static void sparkline_stats(double[] values,
                                       out double out_min,
                                       out double out_max,
                                       out double out_avg) {
        if (values.length == 0) {
            out_min = 0;
            out_max = 0;
            out_avg = 0;
            return;
        }
        out_min = values[0];
        out_max = values[0];
        double sum = 0;
        foreach (double v in values) {
            if (v < out_min) out_min = v;
            if (v > out_max) out_max = v;
            sum += v;
        }
        out_avg = sum / values.length;
    }

    /**
     * Truncate a string to a maximum length, appending "..." if truncated.
     *
     * @param s        The input string
     * @param max_len  Maximum allowed length (must be > 3)
     * @return The original or truncated string
     */
    public static string truncate_string(string s, int max_len) {
        if (s.length <= max_len) return s;
        return s.substring(0, max_len - 3) + "...";
    }

    /**
     * Format a bridge message according to the specified format type.
     *
     * Formats:
     *   - "payload": Raw payload only
     *   - "short":   "[topic] payload" (truncated to 200 chars)
     *   - "full":    "MQTT [topic]\npayload" (default)
     *
     * @param format_type  One of "full", "payload", "short"
     * @param topic_name   The MQTT topic
     * @param payload      The message payload
     * @return Formatted message string
     */
    public static string format_bridge_message(string format_type,
                                                string topic_name,
                                                string payload) {
        switch (format_type) {
            case "payload":
                return payload;
            case "short":
                return "[%s] %s".printf(topic_name, truncate_string(payload, 200));
            default: /* "full" */
                return "MQTT [%s]\n%s".printf(topic_name, payload);
        }
    }

    /**
     * Check if a host string refers to a local/private network address.
     *
     * Returns true for:
     *   - localhost, 127.0.0.1, ::1
     *   - RFC 1918 private ranges: 10.x, 192.168.x, 172.16-31.x
     *   - Common local domain suffixes: .local, .lan, .home
     */
    public static bool is_local_host(string host) {
        string h = host.down().strip();
        if (h == "" ) return true;  /* empty = probably auto-detect → local */
        if (h == "localhost" || h == "127.0.0.1" || h == "::1") return true;
        if (h.has_prefix("192.168.")) return true;
        if (h.has_prefix("10.")) return true;
        if (h.has_prefix("172.")) {
            string[] parts = h.split(".");
            if (parts.length >= 2) {
                int second = int.parse(parts[1]);
                if (second >= 16 && second <= 31) return true;
            }
        }
        if (h.has_suffix(".local") || h.has_suffix(".lan") || h.has_suffix(".home")) return true;
        return false;
    }
}

} // namespace
