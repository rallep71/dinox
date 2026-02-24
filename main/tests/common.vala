namespace Dino.Ui.Test {

int main(string[] args) {
    GLib.Test.init(ref args);
    GLib.Test.set_nonfatal_assertions();
    TestSuite.get_root().add_suite(new PreferencesRowTest().get_suite());
    TestSuite.get_root().add_suite(new UiHelperAudit().get_suite());
    return GLib.Test.run();
}

void fail_if_not_eq_str(string expected, string actual) {
    if (expected != actual) {
        GLib.Test.message(@"Expected \"$(expected)\" but got \"$(actual)\"");
        GLib.Test.fail();
    }
}

void fail_if_not_eq_int(int expected, int actual) {
    if (expected != actual) {
        GLib.Test.message(@"Expected $(expected) but got $(actual)");
        GLib.Test.fail();
    }
}

void assert_true(bool condition, string? reason = null) {
    if (!condition) {
        if (reason != null) GLib.Test.message(reason);
        GLib.Test.fail();
    }
}

void assert_false(bool condition, string? reason = null) {
    if (condition) {
        if (reason != null) GLib.Test.message(reason);
        GLib.Test.fail();
    }
}

}
