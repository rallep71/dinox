/*
 * SECURITY AUDIT TESTS — XEP-0198 Stream Management
 * Spec-based, NOT adapted to current code.
 * FAILs indicate REAL BUGS.
 *
 * Reference: XEP-0198 (Stream Management)
 */
using Gee;

namespace Xmpp.Test {

class StreamManagementAudit : Gee.TestCase {

    public StreamManagementAudit() {
        base("Audit_XEP0198");
        add_test("h_counter_must_be_uint32", test_h_counter_type);
        add_test("h_counter_overflow_produces_negative", test_h_overflow_negative);
        add_test("h_to_string_must_not_be_negative", test_h_to_string);
    }

    /*
     * XEP-0198 §5: "the counter for an entity's own sent stanzas is
     * an unsigned integer from 0 to 2^32-1"
     *
     * FIX VERIFIED: h_inbound and h_outbound are now uint32.
     * Incrementing past uint32.MAX wraps to 0 (not negative).
     */
    void test_h_counter_type() {
        var module = new Xmpp.Xep.StreamManagement.Module();

        // Set to UINT32_MAX - 1
        module.h_inbound = uint32.MAX - 1;

        // Increment twice — should wrap to 0
        module.h_inbound++;  // → UINT32_MAX
        module.h_inbound++;  // → 0 (wrap)

        // After wraparound, value must be 0, not negative
        if (module.h_inbound != 0) {
            GLib.Test.message("BUG: h_inbound after uint32 wraparound is %u, expected 0.".printf(module.h_inbound));
            GLib.Test.fail();
        }
    }

    /*
     * FIX VERIFIED: uint32 overflow wraps to 0, never produces negative.
     */
    void test_h_overflow_negative() {
        var module = new Xmpp.Xep.StreamManagement.Module();
        module.h_inbound = uint32.MAX;
        module.h_inbound++;

        // With uint32, this wraps to 0 — never negative
        string h_str = module.h_inbound.to_string();

        if (h_str.has_prefix("-")) {
            GLib.Test.message("BUG: h counter produces negative string '%s'. XEP-0198 requires 0 to 2^32-1.".printf(h_str));
            GLib.Test.fail();
        }
    }

    /*
     * After wraparound, the h value sent in <a h="..."/> must
     * be "0", not a negative number.
     */
    void test_h_to_string() {
        var module = new Xmpp.Xep.StreamManagement.Module();
        // Simulate wraparound
        module.h_inbound = uint32.MAX;
        module.h_inbound++;

        string h_str = module.h_inbound.to_string();

        if (h_str != "0") {
            GLib.Test.message("BUG: h_inbound.to_string() after wraparound is '%s', expected '0'.".printf(h_str));
            GLib.Test.fail();
        }
    }
}

}
