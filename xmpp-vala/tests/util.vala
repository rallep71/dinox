using Xmpp.Util;

namespace Xmpp.Test {

/**
 * Spec-based tests for hex string parsing utility.
 *
 * Contract: from_hex() MUST parse leading hex digits from the string
 * and return the numeric value. Non-hex characters terminate parsing.
 * An empty or non-hex-starting string returns 0.
 *
 * This follows XML Schema xs:hexBinary parsing semantics where
 * only valid hexadecimal characters [0-9a-fA-F] have defined behavior.
 */
class UtilTest : Gee.TestCase {
    public UtilTest() {
        base("util");

        // Empty string → 0
        add_hex_test(0x0, "");
        // Valid full hex string
        add_hex_test(0x123abc, "123abc");
        // "0x" prefix is NOT valid hex → 0 (only raw hex digits)
        add_hex_test(0x0, "0x123abc");
        // Leading hex char "A" then non-hex → parses only "A" = 10
        add_hex_test(0xa, "A quick brown fox jumps over the lazy dog.");
        // Whitespace-padded "FEED" → only "FEED" hex portion
        add_hex_test(0xfeed, "   FEED ME   ");
    }

    private void add_hex_test(int expected, string str) {
        string test_name = @"from_hex(\"$(str)\")";
        add_test(test_name, () => {
            fail_if_not_eq_int(expected, (int)from_hex(str));
        });
    }
}

}
