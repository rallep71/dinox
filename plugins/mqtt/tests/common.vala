int main(string[] args) {
    GLib.Test.init(ref args);
    GLib.Test.set_nonfatal_assertions();

    /* MQTT 3.1.1 §4.7 — Topic filter matching (wildcards +, #) */
    TestSuite.get_root().add_suite(new MqttTopicMatchTest().get_suite());

    /* Prosody mod_pubsub_mqtt — Topic display format conversion */
    TestSuite.get_root().add_suite(new ProsodyFormatTest().get_suite());

    /* Contract — Numeric value extraction from payloads */
    TestSuite.get_root().add_suite(new NumericExtractTest().get_suite());

    /* Contract — Unicode sparkline chart generation */
    TestSuite.get_root().add_suite(new SparklineTest().get_suite());

    /* Contract — Sparkline character set */
    TestSuite.get_root().add_suite(new SparkCharsTest().get_suite());

    /* Contract — Bridge message formatting */
    TestSuite.get_root().add_suite(new BridgeFormatTest().get_suite());

    /* Contract — String truncation */
    TestSuite.get_root().add_suite(new TruncateTest().get_suite());

    /* Contract — Local host detection (TLS warning) */
    TestSuite.get_root().add_suite(new LocalHostTest().get_suite());

    /* Contract — MqttConnectionConfig model */
    TestSuite.get_root().add_suite(new ConnectionConfigTest().get_suite());

    return GLib.Test.run();
}
