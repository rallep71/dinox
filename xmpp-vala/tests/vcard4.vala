using Xmpp;
using Xmpp.Xep.VCard4;

namespace Xmpp.Test {

class VCard4Test : Gee.TestCase {
    public VCard4Test() {
        base("VCard4");
        add_async_test("serialization", (cb) => { test_serialization.begin(cb); });
        add_async_test("parsing", (cb) => { test_parsing.begin(cb); });
    }

    private async void test_serialization(Gee.TestFinishedCallback cb) {
        var vcard = new VCard4.create();
        vcard.full_name = "Max Mustermann";
        vcard.nickname = "Mäxchen";
        vcard.email = "max@example.com";
        vcard.tel = "+49123456789";
        vcard.role = "Developer";
        
        // Verify the underlying node structure
        var node = vcard.node;
        fail_if_not_eq_str(node.name, "vcard");
        fail_if_not_eq_str(node.ns_uri, Xmpp.Xep.VCard4.NS_URI);
        
        // Check specific fields
        var fn = node.get_subnode("fn", Xmpp.Xep.VCard4.NS_URI);
        fail_if(fn == null, "FN node missing");
        var fn_text = fn.get_subnode("text", Xmpp.Xep.VCard4.NS_URI);
        fail_if(fn_text == null, "FN text node missing");
        fail_if_not_eq_str(fn_text.get_string_content(), "Max Mustermann");

        var email = node.get_subnode("email", Xmpp.Xep.VCard4.NS_URI);
        fail_if(email == null, "EMAIL node missing");
        fail_if_not_eq_str(email.get_subnode("text", Xmpp.Xep.VCard4.NS_URI).get_string_content(), "max@example.com");

        cb();
    }

    private async void test_parsing(Gee.TestFinishedCallback cb) {
        try {
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
            
            fail_if_not_eq_str(vcard.full_name, "Alice");
            fail_if_not_eq_str(vcard.nickname, "Ali");
            fail_if_not_eq_str(vcard.email, "alice@example.org");
            fail_if_not_eq_str(vcard.tel, "12345");
            fail_if_not_eq_str(vcard.title, "Manager");
            fail_if_not_eq_str(vcard.org, "Wonderland Inc.");
            fail_if(vcard.url != null, "URL should be null");

        } catch (Error e) {
            fail_if_reached("Unexpected error: " + e.message);
        }
        cb();
    }
}

}
