namespace Dino.Ui.Test {

int main(string[] args) {
    GLib.Test.init(ref args);
    GLib.Test.set_nonfatal_assertions();
    TestSuite.get_root().add_suite(new PreferencesRowTest().get_suite());
    TestSuite.get_root().add_suite(new UiHelperAudit().get_suite());
    return GLib.Test.run();
}

bool fail_if(bool exp, string? reason = null) {
    if (exp) {
        if (reason != null) GLib.Test.message(reason);
        GLib.Test.fail();
        return true;
    }
    return false;
}

void fail_if_reached(string? reason = null) {
    fail_if(true, reason);
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

void assert_null(void* ptr, string? reason = null) {
    if (ptr != null) {
        if (reason != null) GLib.Test.message(reason);
        GLib.Test.fail();
    }
}

}
