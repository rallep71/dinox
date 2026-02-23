using Xmpp;
using Xmpp.Xep.VCard4;

namespace Xmpp.Test {

/**
 * Spec-based tests for RFC 6350 vCard 4.0 and RFC 6351 xCard XML.
 *
 * References:
 *   - RFC 6350 §6: vCard properties (FN, NICKNAME, EMAIL, TEL, TITLE, ORG, URL)
 *   - RFC 6351 §3: xCard XML representation (urn:ietf:params:xml:ns:vcard-4.0)
 *   - RFC 6350 §6.2.1: FN is REQUIRED (cardinality 1*)
 */
class VCard4Test : Gee.TestCase {
    public VCard4Test() {
        base("VCard4");
        add_async_test("RFC6351_serialization_structure", (cb) => { test_serialization.begin(cb); });
        add_async_test("RFC6351_parse_xcard_xml", (cb) => { test_parsing.begin(cb); });
    }

    /**
     * RFC 6351 §3: vCard properties MUST be serialized as xCard elements
     * under <vcard xmlns='urn:ietf:params:xml:ns:vcard-4.0'>.
     * Each property has a <text> child holding the value.
     *
     * RFC 6350 §6.2.1: FN is mandatory.
     * RFC 6350 §6.2.2: N (structured name) is optional.
     * RFC 6350 §6.3.2: NICKNAME is optional.
     * RFC 6350 §6.4.2: EMAIL is optional.
     * RFC 6350 §6.4.1: TEL is optional.
     * RFC 6350 §6.6.2: ROLE is optional.
     */
    private async void test_serialization(Gee.TestFinishedCallback cb) {
        var vcard = new VCard4.create();
        vcard.full_name = "Max Mustermann";
        vcard.nickname = "Mäxchen";
        vcard.email = "max@example.com";
        vcard.tel = "+49123456789";
        vcard.role = "Developer";
        
        // RFC 6351: Root element must be <vcard> in vCard 4.0 namespace
        var node = vcard.node;
        fail_if_not_eq_str(node.name, "vcard");
        fail_if_not_eq_str(node.ns_uri, Xmpp.Xep.VCard4.NS_URI);
        
        // RFC 6350 §6.2.1: FN (formatted name) is REQUIRED
        var fn = node.get_subnode("fn", Xmpp.Xep.VCard4.NS_URI);
        fail_if(fn == null, "RFC 6350 §6.2.1: FN node is REQUIRED");
        var fn_text = fn.get_subnode("text", Xmpp.Xep.VCard4.NS_URI);
        fail_if(fn_text == null, "RFC 6351: FN must have <text> child");
        fail_if_not_eq_str(fn_text.get_string_content(), "Max Mustermann");

        // RFC 6350 §6.4.2: EMAIL
        var email = node.get_subnode("email", Xmpp.Xep.VCard4.NS_URI);
        fail_if(email == null, "RFC 6350 §6.4.2: EMAIL node missing");
        fail_if_not_eq_str(email.get_subnode("text", Xmpp.Xep.VCard4.NS_URI).get_string_content(), "max@example.com");

        cb();
    }

    /**
     * RFC 6351 §3: Parse real xCard XML and verify all properties.
     * Tests parsing from the wire format, not just internal serialization.
     */
    private async void test_parsing(Gee.TestFinishedCallback cb) {
        try {
            // Real xCard XML per RFC 6351
            string xml = """
                <vcard xmlns='urn:ietf:params:xml:ns:vcard-4.0'>
                    <fn><text>Alice</text></fn>
                    <nickname><text>Ali</text></nickname>
                    <email><text>alice@example.org</text></email>
                    <tel><text>12345</text></tel>
                    <title><text>Manager</text></title>
                    <org><text>Wonderland Inc.</text></org>
                </vcard>
            """;

            var reader = new StanzaReader.for_string(xml);
            var node = yield reader.read_node();
            
            var vcard = new VCard4(node);
            
            // RFC 6350 §6.2.1: FN (mandatory)
            fail_if_not_eq_str(vcard.full_name, "Alice");
            // RFC 6350 §6.2.2: NICKNAME
            fail_if_not_eq_str(vcard.nickname, "Ali");
            // RFC 6350 §6.4.2: EMAIL
            fail_if_not_eq_str(vcard.email, "alice@example.org");
            // RFC 6350 §6.4.1: TEL
            fail_if_not_eq_str(vcard.tel, "12345");
            // RFC 6350 §6.6.1: TITLE
            fail_if_not_eq_str(vcard.title, "Manager");
            // RFC 6350 §6.6.4: ORG
            fail_if_not_eq_str(vcard.org, "Wonderland Inc.");
            // RFC 6350 §6.7.8: URL (not in XML → must be null)
            fail_if(vcard.url != null, "RFC 6350: absent URL should be null");

        } catch (Error e) {
            fail_if_reached("Unexpected error: " + e.message);
        }
        cb();
    }
}

}
