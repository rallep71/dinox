namespace Xmpp.Test {

int main(string[] args) {
    GLib.Test.init(ref args);
    GLib.Test.set_nonfatal_assertions();
    TestSuite.get_root().add_suite(new Xmpp.Test.StanzaTest().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.UtilTest().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.JidTest().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.ColorTest().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.VCard4Test().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.Xep0448Test().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.StreamManagementTest().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.MAMTest().get_suite());
    // Security Audit Tests (spec-based, expected to FAIL = bugs found)
    TestSuite.get_root().add_suite(new Xmpp.Test.StreamManagementAudit().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.OmemoAudit().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.OpenPgpAudit().get_suite());
    // Tier 4 Security Audit Tests
    TestSuite.get_root().add_suite(new Xmpp.Test.StanzaEntryAudit().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.CryptoHashAudit().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.EntityCapsAudit().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.ProtocolParserAudit().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.UtilAudit().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.XepRoundtripAudit().get_suite());
    TestSuite.get_root().add_suite(new Xmpp.Test.Socks5Audit().get_suite());
    // MUJI Group Call Security Audit (XEP-0272, XEP-0482, XEP-0167)
    TestSuite.get_root().add_suite(new Xmpp.Test.MujiAudit().get_suite());
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

delegate void ErrorFunc() throws Error;

bool fail_if_not(bool exp, string? reason = null) {
    return fail_if(!exp, reason);
}

bool fail_if_not_eq_node(StanzaNode left, StanzaNode right, string? reason = null) {
    if (fail_if_not_eq_str(left.name, right.name, @"$(reason + ": " ?? "")name mismatch")) return true;
    if (fail_if_not_eq_str(left.val, right.val, @"$(reason + ": " ?? "")val mismatch")) return true;
    if (left.name == "#text") return false;
    if (fail_if_not_eq_str(left.ns_uri, right.ns_uri, @"$(reason + ": " ?? "")ns_uri mismatch")) return true;
    if (fail_if_not_eq_int(left.sub_nodes.size, right.sub_nodes.size, @"$(reason + ": " ?? "")sub node count mismatch")) return true;
    if (fail_if_not_eq_int(left.attributes.size, right.attributes.size, @"$(reason + ": " ?? "")attributes count mismatch")) return true;
    for (var i = 0; i < left.sub_nodes.size; i++) {
        if (fail_if_not_eq_node(left.sub_nodes[i], right.sub_nodes[i], @"$(reason + ": " ?? "")$(i+1)th subnode mismatch")) return true;
    }
    for (var i = 0; i < left.attributes.size; i++) {
        if (fail_if_not_eq_attr(left.attributes[i], right.attributes[i], @"$(reason + ": " ?? "")$(i+1)th attribute mismatch")) return true;
    }
    return false;
}

bool fail_if_not_eq_attr(StanzaAttribute left, StanzaAttribute right, string? reason = null) {
    if (fail_if_not_eq_str(left.name, right.name, @"$(reason + ": " ?? "")name mismatch")) return true;
    if (fail_if_not_eq_str(left.val, right.val, @"$(reason + ": " ?? "")val mismatch")) return true;
    if (fail_if_not_eq_str(left.ns_uri, right.ns_uri, @"$(reason + ": " ?? "")ns_uri mismatch")) return true;
    return false;
}

bool fail_if_not_eq_int(int left, int right, string? reason = null) {
    return fail_if_not(left == right, @"$(reason + ": " ?? "")$left != $right");
}

bool fail_if_not_eq_uint(uint left, uint right, string? reason = null) {
    return fail_if_not(left == right, @"$(reason + ": " ?? "")$left != $right");
}

private float float_to_accuracy(float f, float accuracy) {
    return (float) (Math.round(f * Math.pow(10, accuracy)) / Math.pow(10, accuracy));
}

private float double_to_accuracy(double f, float accuracy) {
    return (float) (Math.round(f * Math.pow(10, accuracy)) / Math.pow(10, accuracy));
}

bool fail_if_not_eq_float(float left, float right, float accuracy = 3, string? reason = null) {
    return fail_if_not(float_to_accuracy(left, accuracy) == float_to_accuracy(right, accuracy), @"$(reason + ": " ?? "")$left != $right");
}

bool fail_if_not_eq_double(double left, double right, float accuracy = 3, string? reason = null) {
    return fail_if_not(double_to_accuracy(left, accuracy) == double_to_accuracy(right, accuracy), @"$(reason + ": " ?? "")$left != $right");
}

bool fail_if_not_eq_str(string? left, string? right, string? reason = null) {
    bool nullcheck = (left == null) != (right == null);
    if (left == null) left = "(null)";
    if (right == null) right = "(null)";
    return fail_if_not(!nullcheck && left == right, @"$(reason + ": " ?? "")'$left' != '$right'");
}

bool fail_if_eq_str(string? left, string? right, string? reason = null) {
    bool nullcheck = (left == null && right != null) || (left != null && right == null);
    if (left == null) left = "(null)";
    if (right == null) right = "(null)";
    return fail_if(!nullcheck && left == right, @"$(reason + ": " ?? "")'$left' == '$right'");
}

}

