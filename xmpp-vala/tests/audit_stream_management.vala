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
     * BUG: h_inbound and h_outbound are Vala `int` (signed 32-bit).
     * They overflow to negative at 2^31.
     */
    void test_h_counter_type() {
        var module = new Xmpp.Xep.StreamManagement.Module();

        // Set to INT_MAX (2147483647) — valid per XEP (< 2^32-1)
        module.h_inbound = int.MAX;

        // Increment — should be 2147483648, still valid per XEP
        module.h_inbound++;

        // XEP says this MUST be ≥ 0 since it's unsigned
        if (module.h_inbound < 0) {
            GLib.Test.message("BUG: h_inbound overflowed to %d. XEP-0198 requires unsigned 32-bit counter.".printf(module.h_inbound));
            GLib.Test.fail();
        }
    }

    /*
     * At INT_MAX+1, signed int wraps to -2147483648.
     * This would produce <a h="-2147483648"/> — invalid per XEP.
     */
    void test_h_overflow_negative() {
        var module = new Xmpp.Xep.StreamManagement.Module();
        module.h_inbound = int.MAX;
        module.h_inbound++;

        // The stanza would contain h="<negative_number>"
        string h_str = module.h_inbound.to_string();

        if (h_str.has_prefix("-")) {
            GLib.Test.message("BUG: h counter produces negative string '%s'. XEP-0198 requires 0 to 2^32-1.".printf(h_str));
            GLib.Test.fail();
        }
    }

    /*
     * After 2^31 increments, the h value sent in <a h="..."/> must
     * still be a valid non-negative number.
     */
    void test_h_to_string() {
        // Simulate h_inbound after receiving 2^31 + 100 stanzas
        int h = int.MAX;
        for (int i = 0; i < 101; i++) h++;

        string val = h.to_string();

        // Must be non-negative and parseable
        int64 parsed = int64.parse(val);
        if (parsed < 0) {
            GLib.Test.message("BUG: After 2^31+100 stanzas, h='%s' (parsed=%lld). Must be non-negative per XEP-0198.".printf(val, parsed));
            GLib.Test.fail();
        }
    }
}

}
