/**
 * MQTT Plugin Unit Tests
 *
 * Tests for pure utility functions in MqttUtils.
 * All tests are standalone — no MQTT broker, no DB, no UI required.
 *
 * Spec references:
 *   - MQTT 3.1.1 §4.7 (Topic Filter Matching)
 *   - Prosody mod_pubsub_mqtt (Topic Format)
 *   - OASIS MQTT 5.0 (QoS levels)
 */

using Dino.Plugins.Mqtt;

/* ── Topic Matching (MQTT 3.1.1 §4.7) ──────────────────────── */

class MqttTopicMatchTest : Gee.TestCase {

    public MqttTopicMatchTest() {
        base("MqttTopicMatch");

        /* Exact match */
        add_test("MQTT_3_1_1_exact_match", test_exact_match);
        add_test("MQTT_3_1_1_exact_match_multlevel", test_exact_match_multilevel);
        add_test("MQTT_3_1_1_exact_mismatch", test_exact_mismatch);

        /* # wildcard (multi-level) */
        add_test("MQTT_3_1_1_hash_matches_all", test_hash_matches_all);
        add_test("MQTT_3_1_1_hash_suffix_matches_subtree", test_hash_suffix);
        add_test("MQTT_3_1_1_hash_matches_deep_subtree", test_hash_deep_subtree);

        /* + wildcard (single-level) */
        add_test("MQTT_3_1_1_plus_single_level", test_plus_single_level);
        add_test("MQTT_3_1_1_plus_no_cross_level", test_plus_no_cross_level);
        add_test("MQTT_3_1_1_plus_middle_level", test_plus_middle_level);

        /* Combined wildcards */
        add_test("MQTT_3_1_1_plus_plus_exact", test_plus_plus_exact);
        add_test("MQTT_3_1_1_plus_hash_combined", test_plus_hash_combined);

        /* Edge cases */
        add_test("MQTT_3_1_1_empty_topic_no_match", test_empty_topic);
        add_test("MQTT_3_1_1_trailing_slash_exact", test_trailing_slash);
        add_test("MQTT_3_1_1_pattern_longer_than_topic", test_pattern_longer);
        add_test("MQTT_3_1_1_topic_longer_than_pattern", test_topic_longer);
    }

    private void test_exact_match() {
        assert_true(MqttUtils.topic_matches("home/temp", "home/temp"));
    }

    private void test_exact_match_multilevel() {
        assert_true(MqttUtils.topic_matches("home/living/temp", "home/living/temp"));
    }

    private void test_exact_mismatch() {
        assert_false(MqttUtils.topic_matches("home/temp", "home/humidity"));
    }

    private void test_hash_matches_all() {
        assert_true(MqttUtils.topic_matches("#", "any/topic/at/all"));
    }

    private void test_hash_suffix() {
        assert_true(MqttUtils.topic_matches("home/#", "home/living/temp"));
    }

    private void test_hash_deep_subtree() {
        assert_true(MqttUtils.topic_matches("home/#", "home/a/b/c/d/e"));
    }

    private void test_plus_single_level() {
        assert_true(MqttUtils.topic_matches("home/+/temp", "home/living/temp"));
    }

    private void test_plus_no_cross_level() {
        /* + must not cross level boundaries */
        assert_false(MqttUtils.topic_matches("home/+/temp", "home/living/room/temp"));
    }

    private void test_plus_middle_level() {
        assert_true(MqttUtils.topic_matches("+/sensors/+", "home/sensors/temp"));
    }

    private void test_plus_plus_exact() {
        assert_true(MqttUtils.topic_matches("+/+/temp", "home/living/temp"));
    }

    private void test_plus_hash_combined() {
        assert_true(MqttUtils.topic_matches("+/sensors/#", "home/sensors/temp/data"));
    }

    private void test_empty_topic() {
        assert_false(MqttUtils.topic_matches("home/temp", ""));
    }

    private void test_trailing_slash() {
        /* "a/b/" and "a/b" are different topics */
        assert_false(MqttUtils.topic_matches("a/b", "a/b/"));
    }

    private void test_pattern_longer() {
        assert_false(MqttUtils.topic_matches("a/b/c", "a/b"));
    }

    private void test_topic_longer() {
        assert_false(MqttUtils.topic_matches("a/b", "a/b/c"));
    }
}

/* ── Prosody Topic Display Format ───────────────────────────── */

class ProsodyFormatTest : Gee.TestCase {

    public ProsodyFormatTest() {
        base("ProsodyFormat");

        add_test("PROSODY_pubsub_basic_conversion", test_basic_conversion);
        add_test("PROSODY_pubsub_with_subdomain", test_subdomain);
        add_test("PROSODY_pubsub_slashes_in_node", test_slashes_in_node);
        add_test("PROSODY_non_prosody_topic_unchanged", test_non_prosody);
        add_test("PROSODY_no_dot_in_host_unchanged", test_no_dot_in_host);
        add_test("PROSODY_empty_node_unchanged", test_empty_node);
        add_test("PROSODY_pubsub_at_start_unchanged", test_pubsub_at_start);
    }

    private void test_basic_conversion() {
        string result = MqttUtils.format_topic_display(
            "pubsub.example.org/pubsub/sensors");
        assert_true(result == "sensors (PubSub@pubsub.example.org)");
    }

    private void test_subdomain() {
        string result = MqttUtils.format_topic_display(
            "mqtt.chat.example.com/pubsub/home/temp");
        assert_true(result == "home/temp (PubSub@mqtt.chat.example.com)");
    }

    private void test_slashes_in_node() {
        string result = MqttUtils.format_topic_display(
            "example.org/pubsub/home/sensors/temp");
        assert_true(result == "home/sensors/temp (PubSub@example.org)");
    }

    private void test_non_prosody() {
        string result = MqttUtils.format_topic_display("home/sensors/temp");
        assert_true(result == "home/sensors/temp");
    }

    private void test_no_dot_in_host() {
        /* "localhost/pubsub/test" — host has no dot → not Prosody format */
        string result = MqttUtils.format_topic_display("localhost/pubsub/test");
        assert_true(result == "localhost/pubsub/test");
    }

    private void test_empty_node() {
        /* "example.org/pubsub/" — empty node → leave unchanged */
        string result = MqttUtils.format_topic_display("example.org/pubsub/");
        assert_true(result == "example.org/pubsub/");
    }

    private void test_pubsub_at_start() {
        /* "/pubsub/test" — empty host → leave unchanged */
        string result = MqttUtils.format_topic_display("/pubsub/test");
        assert_true(result == "/pubsub/test");
    }
}

/* ── Numeric Extraction ─────────────────────────────────────── */

class NumericExtractTest : Gee.TestCase {

    public NumericExtractTest() {
        base("NumericExtract");

        add_test("CONTRACT_plain_integer", test_plain_integer);
        add_test("CONTRACT_plain_double", test_plain_double);
        add_test("CONTRACT_plain_negative", test_plain_negative);
        add_test("CONTRACT_whitespace_trimmed", test_whitespace);
        add_test("CONTRACT_json_double_field", test_json_double);
        add_test("CONTRACT_json_int_field", test_json_int);
        add_test("CONTRACT_json_no_numeric_returns_null", test_json_no_numeric);
        add_test("CONTRACT_non_numeric_returns_null", test_non_numeric);
        add_test("CONTRACT_empty_string_returns_null", test_empty);
        add_test("CONTRACT_json_nested_first_numeric", test_json_first_numeric);
    }

    private void test_plain_integer() {
        double? v = MqttUtils.try_extract_numeric("42");
        assert_true(v != null);
        assert_true(Math.fabs(v - 42.0) < 0.001);
    }

    private void test_plain_double() {
        double? v = MqttUtils.try_extract_numeric("22.5");
        assert_true(v != null);
        assert_true(Math.fabs(v - 22.5) < 0.001);
    }

    private void test_plain_negative() {
        double? v = MqttUtils.try_extract_numeric("-3.14");
        assert_true(v != null);
        assert_true(Math.fabs(v - (-3.14)) < 0.001);
    }

    private void test_whitespace() {
        double? v = MqttUtils.try_extract_numeric("  99  ");
        assert_true(v != null);
        assert_true(Math.fabs(v - 99.0) < 0.001);
    }

    private void test_json_double() {
        double? v = MqttUtils.try_extract_numeric(
            """{"temperature": 22.1, "unit": "°C"}""");
        assert_true(v != null);
        assert_true(Math.fabs(v - 22.1) < 0.001);
    }

    private void test_json_int() {
        double? v = MqttUtils.try_extract_numeric(
            """{"count": 7}""");
        assert_true(v != null);
        assert_true(Math.fabs(v - 7.0) < 0.001);
    }

    private void test_json_no_numeric() {
        double? v = MqttUtils.try_extract_numeric(
            """{"status": "ok", "msg": "hello"}""");
        assert_true(v == null);
    }

    private void test_non_numeric() {
        double? v = MqttUtils.try_extract_numeric("hello world");
        assert_true(v == null);
    }

    private void test_empty() {
        double? v = MqttUtils.try_extract_numeric("");
        assert_true(v == null);
    }

    private void test_json_first_numeric() {
        /* Should return the FIRST numeric field */
        double? v = MqttUtils.try_extract_numeric(
            """{"name": "sensor-1", "value": 42.5, "alarm": 100}""");
        assert_true(v != null);
        assert_true(Math.fabs(v - 42.5) < 0.001);
    }
}

/* ── Sparkline Generation ───────────────────────────────────── */

class SparklineTest : Gee.TestCase {

    public SparklineTest() {
        base("Sparkline");

        add_test("CONTRACT_ascending_values", test_ascending);
        add_test("CONTRACT_descending_values", test_descending);
        add_test("CONTRACT_constant_values", test_constant);
        add_test("CONTRACT_two_values_min_max", test_two_values);
        add_test("CONTRACT_single_value_returns_null", test_single_null);
        add_test("CONTRACT_empty_returns_null", test_empty_null);
        add_test("CONTRACT_length_matches_input", test_length);
        add_test("CONTRACT_stats_min_max_avg", test_stats);
    }

    private void test_ascending() {
        double[] vals = { 0, 1, 2, 3, 4, 5, 6, 7 };
        string? s = MqttUtils.build_sparkline(vals);
        assert_true(s != null);
        /* First char should be lowest block, last should be highest */
        assert_true(s.has_prefix("▁"));
        assert_true(s.has_suffix("█"));
    }

    private void test_descending() {
        double[] vals = { 7, 6, 5, 4, 3, 2, 1, 0 };
        string? s = MqttUtils.build_sparkline(vals);
        assert_true(s != null);
        assert_true(s.has_prefix("█"));
        assert_true(s.has_suffix("▁"));
    }

    private void test_constant() {
        double[] vals = { 5, 5, 5, 5, 5 };
        string? s = MqttUtils.build_sparkline(vals);
        assert_true(s != null);
        /* All identical → range < 0.001 → range forced to 1.0
         * (v-min)/1.0 * 7 = 0 → index 0 or clamped
         * All chars should be identical */
        unichar first = s.get_char(0);
        for (int i = 1; i < 5; i++) {
            assert_true(s.get_char(s.index_of_nth_char(i)) == first);
        }
    }

    private void test_two_values() {
        double[] vals = { 0, 100 };
        string? s = MqttUtils.build_sparkline(vals);
        assert_true(s != null);
        assert_true(s == "▁█");
    }

    private void test_single_null() {
        double[] vals = { 42 };
        string? s = MqttUtils.build_sparkline(vals);
        assert_true(s == null);
    }

    private void test_empty_null() {
        double[] vals = {};
        string? s = MqttUtils.build_sparkline(vals);
        assert_true(s == null);
    }

    private void test_length() {
        double[] vals = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
        string? s = MqttUtils.build_sparkline(vals);
        assert_true(s != null);
        /* Each sparkline char is a multi-byte Unicode char (3 bytes UTF-8) */
        assert_true(s.char_count() == 10);
    }

    private void test_stats() {
        double[] vals = { 10, 20, 30 };
        double min, max, avg;
        MqttUtils.sparkline_stats(vals, out min, out max, out avg);
        assert_true(Math.fabs(min - 10.0) < 0.001);
        assert_true(Math.fabs(max - 30.0) < 0.001);
        assert_true(Math.fabs(avg - 20.0) < 0.001);
    }
}

/* ── Bridge Message Formatting ──────────────────────────────── */

class BridgeFormatTest : Gee.TestCase {

    public BridgeFormatTest() {
        base("BridgeFormat");

        add_test("CONTRACT_full_format", test_full);
        add_test("CONTRACT_payload_format", test_payload);
        add_test("CONTRACT_short_format", test_short);
        add_test("CONTRACT_short_truncates_at_200", test_short_truncate);
        add_test("CONTRACT_unknown_defaults_full", test_unknown_default);
    }

    private void test_full() {
        string msg = MqttUtils.format_bridge_message(
            "full", "home/temp", "22.5");
        assert_true(msg == "MQTT [home/temp]\n22.5");
    }

    private void test_payload() {
        string msg = MqttUtils.format_bridge_message(
            "payload", "home/temp", "22.5");
        assert_true(msg == "22.5");
    }

    private void test_short() {
        string msg = MqttUtils.format_bridge_message(
            "short", "home/temp", "22.5");
        assert_true(msg == "[home/temp] 22.5");
    }

    private void test_short_truncate() {
        /* Build a 250-char payload */
        var sb = new StringBuilder();
        for (int i = 0; i < 250; i++) sb.append_c('x');
        string long_payload = sb.str;

        string msg = MqttUtils.format_bridge_message(
            "short", "t", long_payload);

        /* Short format truncates payload to 200 chars */
        /* "[t] " = 4 chars prefix, payload truncated to 200 = "xxx...xxx..." */
        assert_true(msg.length <= 4 + 200);
        assert_true(msg.has_suffix("..."));
    }

    private void test_unknown_default() {
        /* Unknown format type defaults to "full" */
        string msg = MqttUtils.format_bridge_message(
            "something", "home/temp", "22.5");
        assert_true(msg == "MQTT [home/temp]\n22.5");
    }
}

/* ── String Truncation ──────────────────────────────────────── */

class TruncateTest : Gee.TestCase {

    public TruncateTest() {
        base("TruncateStr");

        add_test("CONTRACT_short_unchanged", test_short_unchanged);
        add_test("CONTRACT_exact_length_unchanged", test_exact_length);
        add_test("CONTRACT_over_length_truncated", test_over_length);
        add_test("CONTRACT_ellipsis_appended", test_ellipsis);
        add_test("CONTRACT_truncated_length_exact", test_truncated_length);
    }

    private void test_short_unchanged() {
        assert_true(MqttUtils.truncate_string("hi", 10) == "hi");
    }

    private void test_exact_length() {
        assert_true(MqttUtils.truncate_string("12345", 5) == "12345");
    }

    private void test_over_length() {
        string result = MqttUtils.truncate_string("1234567890", 7);
        assert_true(result != "1234567890");
    }

    private void test_ellipsis() {
        string result = MqttUtils.truncate_string("1234567890", 7);
        assert_true(result.has_suffix("..."));
    }

    private void test_truncated_length() {
        string result = MqttUtils.truncate_string("1234567890", 7);
        assert_true(result.length == 7);  /* "1234..." */
    }
}

/* ── Spark Chars Array ──────────────────────────────────────── */

class SparkCharsTest : Gee.TestCase {

    public SparkCharsTest() {
        base("SparkChars");

        add_test("CONTRACT_8_levels", test_8_levels);
        add_test("CONTRACT_ascending_unicode_blocks", test_ascending_blocks);
    }

    private void test_8_levels() {
        assert_true(MqttUtils.SPARK_CHARS.length == 8);
    }

    private void test_ascending_blocks() {
        /* Each char should be a single Unicode character */
        for (int i = 0; i < 8; i++) {
            assert_true(MqttUtils.SPARK_CHARS[i].char_count() == 1);
        }
        /* First is lowest block (U+2581), last is full block (U+2588) */
        assert_true(MqttUtils.SPARK_CHARS[0] == "▁");
        assert_true(MqttUtils.SPARK_CHARS[7] == "█");
    }
}

/* ── Local Host Detection ───────────────────────────────────── */

class LocalHostTest : Gee.TestCase {

    public LocalHostTest() {
        base("LocalHost");

        add_test("LOCAL_localhost", test_localhost);
        add_test("LOCAL_127_0_0_1", test_loopback_ipv4);
        add_test("LOCAL_ipv6_loopback", test_loopback_ipv6);
        add_test("LOCAL_192_168_x", test_rfc1918_class_c);
        add_test("LOCAL_10_x", test_rfc1918_class_a);
        add_test("LOCAL_172_16_x", test_rfc1918_172_16);
        add_test("LOCAL_172_31_x", test_rfc1918_172_31);
        add_test("NON_LOCAL_172_32_x", test_non_rfc1918_172_32);
        add_test("LOCAL_dot_local", test_dot_local);
        add_test("LOCAL_dot_lan", test_dot_lan);
        add_test("LOCAL_dot_home", test_dot_home);
        add_test("NON_LOCAL_public_ip", test_public_ip);
        add_test("NON_LOCAL_domain", test_public_domain);
        add_test("LOCAL_empty_string", test_empty);
        add_test("LOCAL_case_insensitive", test_case_insensitive);
    }

    private void test_localhost() {
        assert_true(MqttUtils.is_local_host("localhost"));
    }

    private void test_loopback_ipv4() {
        assert_true(MqttUtils.is_local_host("127.0.0.1"));
    }

    private void test_loopback_ipv6() {
        assert_true(MqttUtils.is_local_host("::1"));
    }

    private void test_rfc1918_class_c() {
        assert_true(MqttUtils.is_local_host("192.168.1.100"));
    }

    private void test_rfc1918_class_a() {
        assert_true(MqttUtils.is_local_host("10.0.0.1"));
    }

    private void test_rfc1918_172_16() {
        assert_true(MqttUtils.is_local_host("172.16.0.1"));
    }

    private void test_rfc1918_172_31() {
        assert_true(MqttUtils.is_local_host("172.31.255.254"));
    }

    private void test_non_rfc1918_172_32() {
        assert_false(MqttUtils.is_local_host("172.32.0.1"));
    }

    private void test_dot_local() {
        assert_true(MqttUtils.is_local_host("myserver.local"));
    }

    private void test_dot_lan() {
        assert_true(MqttUtils.is_local_host("mqtt.lan"));
    }

    private void test_dot_home() {
        assert_true(MqttUtils.is_local_host("broker.home"));
    }

    private void test_public_ip() {
        assert_false(MqttUtils.is_local_host("8.8.8.8"));
    }

    private void test_public_domain() {
        assert_false(MqttUtils.is_local_host("mqtt.example.com"));
    }

    private void test_empty() {
        assert_true(MqttUtils.is_local_host(""));
    }

    private void test_case_insensitive() {
        assert_true(MqttUtils.is_local_host("LOCALHOST"));
        assert_true(MqttUtils.is_local_host("MyServer.LOCAL"));
    }
}

/* ── MqttConnectionConfig Tests ─────────────────────────────── */

class ConnectionConfigTest : Gee.TestCase {

    public ConnectionConfigTest() {
        base("ConnectionConfig");

        add_test("CONFIG_defaults", test_defaults);
        add_test("CONFIG_copy_preserves_all", test_copy);
        add_test("CONFIG_copy_is_independent", test_copy_independent);
        add_test("CONFIG_connection_differs_host", test_differs_host);
        add_test("CONFIG_connection_differs_port", test_differs_port);
        add_test("CONFIG_connection_differs_tls", test_differs_tls);
        add_test("CONFIG_connection_same", test_same_connection);
        add_test("CONFIG_get_topic_list_basic", test_topic_list_basic);
        add_test("CONFIG_get_topic_list_whitespace", test_topic_list_whitespace);
        add_test("CONFIG_get_topic_list_empty", test_topic_list_empty);
        add_test("CONFIG_to_debug_string", test_debug_string);
    }

    private void test_defaults() {
        var cfg = new MqttConnectionConfig();
        assert_false(cfg.enabled);
        assert_true(cfg.broker_host == "");
        assert_true(cfg.broker_port == 1883);
        assert_false(cfg.tls);
        assert_false(cfg.use_xmpp_auth);
        assert_true(cfg.username == "");
        assert_true(cfg.password == "");
        assert_true(cfg.topics == "");
        assert_true(cfg.bot_enabled);
        assert_true(cfg.bot_name == "MQTT Bot");
        assert_true(cfg.server_type == "unknown");
        assert_false(cfg.freetext_enabled);
        assert_true(cfg.freetext_publish_topic == "");
        assert_true(cfg.freetext_qos == 1);
        assert_false(cfg.freetext_retain);
        assert_true(cfg.publish_presets_json == "[]");
    }

    private void test_copy() {
        var orig = new MqttConnectionConfig();
        orig.enabled = true;
        orig.broker_host = "mqtt.example.com";
        orig.broker_port = 8883;
        orig.tls = true;
        orig.use_xmpp_auth = true;
        orig.username = "alice";
        orig.password = "secret";
        orig.topics = "home/#,office/#";
        orig.bot_name = "MyBot";
        orig.freetext_enabled = true;
        orig.freetext_publish_topic = "cmds/in";

        var copy = orig.copy();
        assert_true(copy.enabled);
        assert_true(copy.broker_host == "mqtt.example.com");
        assert_true(copy.broker_port == 8883);
        assert_true(copy.tls);
        assert_true(copy.use_xmpp_auth);
        assert_true(copy.username == "alice");
        assert_true(copy.password == "secret");
        assert_true(copy.topics == "home/#,office/#");
        assert_true(copy.bot_name == "MyBot");
        assert_true(copy.freetext_enabled);
        assert_true(copy.freetext_publish_topic == "cmds/in");
    }

    private void test_copy_independent() {
        var orig = new MqttConnectionConfig();
        orig.broker_host = "old.host";
        var copy = orig.copy();
        copy.broker_host = "new.host";
        /* Original must remain unchanged */
        assert_true(orig.broker_host == "old.host");
        assert_true(copy.broker_host == "new.host");
    }

    private void test_differs_host() {
        var a = new MqttConnectionConfig();
        var b = new MqttConnectionConfig();
        a.broker_host = "host1";
        b.broker_host = "host2";
        assert_true(a.connection_differs(b));
    }

    private void test_differs_port() {
        var a = new MqttConnectionConfig();
        var b = new MqttConnectionConfig();
        a.broker_port = 1883;
        b.broker_port = 8883;
        assert_true(a.connection_differs(b));
    }

    private void test_differs_tls() {
        var a = new MqttConnectionConfig();
        var b = new MqttConnectionConfig();
        a.tls = false;
        b.tls = true;
        assert_true(a.connection_differs(b));
    }

    private void test_same_connection() {
        var a = new MqttConnectionConfig();
        var b = new MqttConnectionConfig();
        a.broker_host = "same.host";
        b.broker_host = "same.host";
        /* Topics differ but connection params don't → should NOT differ */
        a.topics = "home/#";
        b.topics = "office/#";
        assert_false(a.connection_differs(b));
    }

    private void test_topic_list_basic() {
        var cfg = new MqttConnectionConfig();
        cfg.topics = "home/#,office/temp,garden/+/status";
        string[] list = cfg.get_topic_list();
        assert_true(list.length == 3);
        assert_true(list[0] == "home/#");
        assert_true(list[1] == "office/temp");
        assert_true(list[2] == "garden/+/status");
    }

    private void test_topic_list_whitespace() {
        var cfg = new MqttConnectionConfig();
        cfg.topics = "  home/# , office/temp , garden/status  ";
        string[] list = cfg.get_topic_list();
        assert_true(list.length == 3);
        assert_true(list[0] == "home/#");
        assert_true(list[1] == "office/temp");
        assert_true(list[2] == "garden/status");
    }

    private void test_topic_list_empty() {
        var cfg = new MqttConnectionConfig();
        cfg.topics = "";
        string[] list = cfg.get_topic_list();
        assert_true(list.length == 0);
    }

    private void test_debug_string() {
        var cfg = new MqttConnectionConfig();
        cfg.enabled = true;
        cfg.broker_host = "test";
        string dbg = cfg.to_debug_string();
        assert_true(dbg.contains("enabled=true"));
        assert_true(dbg.contains("host=test"));
    }
}
