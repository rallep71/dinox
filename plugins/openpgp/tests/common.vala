namespace OpenPgp.Test {

int main(string[] args) {
    GLib.Test.init(ref args);
    GLib.Test.set_nonfatal_assertions();
    TestSuite.get_root().add_suite(new StreamModuleLogicTest().get_suite());
    TestSuite.get_root().add_suite(new GPGKeylistParserTest().get_suite());
    TestSuite.get_root().add_suite(new ArmorParserTest().get_suite());
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

bool fail_if_not(bool exp, string? reason = null) {
    return fail_if(!exp, reason);
}

bool fail_if_not_eq_int(int left, int right, string? reason = null) {
    return fail_if_not(left == right, @"$(reason + ": " ?? "")$left != $right");
}

bool fail_if_not_eq_str(string left, string right, string? reason = null) {
    return fail_if_not(left == right, @"$(reason + ": " ?? "")$left != $right");
}

bool fail_if_null(void* what, string? reason = null) {
    return fail_if(what == null || (size_t)what == 0, reason);
}

}
