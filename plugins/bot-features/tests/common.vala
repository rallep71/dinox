int main(string[] args) {
    GLib.Test.init(ref args);

    TestSuite.get_root().add_suite(new Dino.Plugins.BotFeatures.Test.RateLimiterTest().get_suite());
    TestSuite.get_root().add_suite(new Dino.Plugins.BotFeatures.Test.CryptoTest().get_suite());

    return GLib.Test.run();
}
