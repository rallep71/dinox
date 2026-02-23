namespace Dino.Test {

int main(string[] args) {
    GLib.Test.init(ref args);
    GLib.Test.set_nonfatal_assertions();
    TestSuite.get_root().add_suite(new WeakMapTest().get_suite());
    TestSuite.get_root().add_suite(new JidTest().get_suite());
    TestSuite.get_root().add_suite(new FileManagerTest().get_suite());
    TestSuite.get_root().add_suite(new SecurityTest().get_suite());
    // Security Audit Tests (spec-based, expected to FAIL = bugs found)
    TestSuite.get_root().add_suite(new Dino.SecurityAudit.KeyDerivationAudit().get_suite());
    TestSuite.get_root().add_suite(new Dino.SecurityAudit.KeyManagerAudit().get_suite());
    TestSuite.get_root().add_suite(new Dino.SecurityAudit.TokenStorageAudit().get_suite());
    TestSuite.get_root().add_suite(new Dino.SecurityAudit.JSONInjectionAudit().get_suite());
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

}
