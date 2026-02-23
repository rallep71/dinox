int main(string[] args) {
    GLib.Test.init(ref args);
    GLib.Test.set_nonfatal_assertions();

    TestSuite.get_root().add_suite(new Dino.Plugins.BotFeatures.Test.RateLimiterTest().get_suite());
    TestSuite.get_root().add_suite(new Dino.Plugins.BotFeatures.Test.CryptoTest().get_suite());
    // Security Audit Tests (spec-based, expected to FAIL = bugs found)
    TestSuite.get_root().add_suite(new Dino.Plugins.BotFeatures.Test.RateLimiterAudit().get_suite());
    TestSuite.get_root().add_suite(new Dino.Plugins.BotFeatures.Test.JSONEscapeAudit().get_suite());

    return GLib.Test.run();
}
