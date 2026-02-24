int main(string[] args) {
    GLib.Test.init(ref args);
    GLib.Test.set_nonfatal_assertions();

    TestSuite.get_root().add_suite(new Dino.Plugins.HttpFiles.Test.UrlRegexTest().get_suite());
    TestSuite.get_root().add_suite(new Dino.Plugins.HttpFiles.Test.FileNameExtractionTest().get_suite());
    TestSuite.get_root().add_suite(new Dino.Plugins.HttpFiles.Test.SanitizeLogTest().get_suite());

    return GLib.Test.run();
}

void fail_if(bool condition, string? msg = null) {
    if (condition) GLib.Test.fail();
    if (condition && msg != null) GLib.Test.message("FAIL: %s", msg);
}

void fail_if_not(bool condition, string? msg = null) {
    fail_if(!condition, msg);
}

void fail_if_not_eq_str(string expected, string actual) {
    if (expected != actual) {
        GLib.Test.fail();
        GLib.Test.message("Expected '%s' but got '%s'", expected, actual);
    }
}

void fail_if_not_eq_int(int expected, int actual) {
    if (expected != actual) {
        GLib.Test.fail();
        GLib.Test.message("Expected %d but got %d", expected, actual);
    }
}

void fail_if_null(void* ptr, string? msg = null) {
    if (ptr == null) {
        GLib.Test.fail();
        if (msg != null) GLib.Test.message("FAIL (null): %s", msg);
    }
}
