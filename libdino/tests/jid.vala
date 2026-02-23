using Xmpp;

namespace Dino.Test {

/**
 * Spec-based JID parsing tests per RFC 7622.
 *
 * References:
 *   - RFC 7622 §3.1: JID format: [ localpart "@" ] domainpart [ "/" resourcepart ]
 *   - RFC 7622 §3.2: domainpart is REQUIRED
 *   - RFC 7622 §3.3: localpart is OPTIONAL
 *   - RFC 7622 §3.4: resourcepart is OPTIONAL
 */
class JidTest : Gee.TestCase {

    public JidTest() {
        base("Jid");
        add_test("RFC7622_parse_full_jid", test_parse);
        add_test("RFC7622_components_constructor", test_components);
        add_test("RFC7622_with_resource", test_with_res);
    }

    /**
     * RFC 7622 §3.1: "user@example.com/res" MUST parse to
     * localpart="user", domainpart="example.com", resourcepart="res".
     */
    private void test_parse() {
        try {
            Jid jid = new Jid("user@example.com/res");
            fail_if(jid.localpart != "user");
            fail_if(jid.domainpart != "example.com");
            fail_if(jid.resourcepart != "res");
            fail_if(jid.to_string() != "user@example.com/res");
        } catch (InvalidJidError e) {
            fail_if_reached(@"Unexpected InvalidJidError: $(e.message)");
        }
    }

    /**
     * RFC 7622 §3.1: Component-based construction MUST produce
     * the same result as string parsing.
     */
    private void test_components() {
        try {
            Jid jid = new Jid.components("user", "example.com", "res");
            fail_if(jid.localpart != "user");
            fail_if(jid.domainpart != "example.com");
            fail_if(jid.resourcepart != "res");
            fail_if(jid.to_string() != "user@example.com/res");
        } catch (InvalidJidError e) {
            fail_if_reached(@"Unexpected InvalidJidError: $(e.message)");
        }
    }

    /**
     * RFC 7622 §3.4: Adding a resourcepart to a bare JID
     * MUST produce a full JID with all three components.
     */
    private void test_with_res() {
        try {
            Jid bare = new Jid("user@example.com");
            Jid jid = bare.with_resource("res");
            fail_if(jid.localpart != "user");
            fail_if(jid.domainpart != "example.com");
            fail_if(jid.resourcepart != "res");
            fail_if(jid.to_string() != "user@example.com/res");
        } catch (InvalidJidError e) {
            fail_if_reached(@"Unexpected InvalidJidError: $(e.message)");
        }
    }
}

}
