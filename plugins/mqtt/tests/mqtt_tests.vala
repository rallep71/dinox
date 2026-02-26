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
