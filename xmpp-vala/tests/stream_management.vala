namespace Xmpp.Test {

/**
 * Tests for XEP-0198 Stream Management stanza construction and parsing.
 * Verifies that enable/resume/ack stanzas are built correctly and that
 * h-counter values are parsed from server responses.
 */
class StreamManagementTest : Gee.TestCase {

    private const string SM_NS = "urn:xmpp:sm:3";

    public StreamManagementTest() {
        base("StreamManagement");
        add_test("enable_stanza", test_enable_stanza);
        add_test("resume_stanza", test_resume_stanza);
        add_test("ack_stanza", test_ack_stanza);
        add_test("request_stanza", test_request_stanza);
        add_test("parse_enabled", test_parse_enabled);
        add_test("parse_resumed", test_parse_resumed);
        add_test("parse_ack", test_parse_ack);
        add_test("parse_failed", test_parse_failed);
        add_test("h_counter_overflow", test_h_counter_overflow);
        add_test("features_check", test_features_check);
    }

    // --- Stanza construction tests ---

    private void test_enable_stanza() {
        // Build: <enable xmlns="urn:xmpp:sm:3" resume="true"/>
        StanzaNode node = new StanzaNode.build("enable", SM_NS)
            .add_self_xmlns()
            .put_attribute("resume", "true");

        fail_if_not_eq_str(node.name, "enable");
        fail_if_not_eq_str(node.ns_uri, SM_NS);
        fail_if_not_eq_str(node.get_attribute("resume"), "true");
    }

    private void test_resume_stanza() {
        // Build: <resume xmlns="urn:xmpp:sm:3" h="42" previd="session-abc-123"/>
        int h = 42;
        string session_id = "session-abc-123";

        StanzaNode node = new StanzaNode.build("resume", SM_NS)
            .add_self_xmlns()
            .put_attribute("h", h.to_string())
            .put_attribute("previd", session_id);

        fail_if_not_eq_str(node.name, "resume");
        fail_if_not_eq_str(node.get_attribute("h"), "42");
        fail_if_not_eq_str(node.get_attribute("previd"), "session-abc-123");
    }

    private void test_ack_stanza() {
        // Build: <a xmlns="urn:xmpp:sm:3" h="17"/>
        int h = 17;
        StanzaNode node = new StanzaNode.build("a", SM_NS)
            .add_self_xmlns()
            .put_attribute("h", h.to_string());

        fail_if_not_eq_str(node.name, "a");
        fail_if_not_eq_str(node.get_attribute("h"), "17");
    }

    private void test_request_stanza() {
        // Build: <r xmlns="urn:xmpp:sm:3"/>
        StanzaNode node = new StanzaNode.build("r", SM_NS).add_self_xmlns();

        fail_if_not_eq_str(node.name, "r");
        fail_if_not_eq_str(node.ns_uri, SM_NS);
        fail_if_not_eq_int(node.sub_nodes.size, 0);
    }

    // --- Response parsing tests ---

    private void test_parse_enabled() {
        // Parse: <enabled xmlns="urn:xmpp:sm:3" id="some-long-sm-id" resume="true"/>
        StanzaNode node = new StanzaNode.build("enabled", SM_NS)
            .add_self_xmlns()
            .put_attribute("id", "some-long-sm-id", SM_NS)
            .put_attribute("resume", "true");

        fail_if_not_eq_str(node.name, "enabled");
        string? session_id = node.get_attribute("id", SM_NS);
        fail_if_not_eq_str(session_id, "some-long-sm-id");
    }

    private void test_parse_resumed() {
        // Parse: <resumed xmlns="urn:xmpp:sm:3" h="255" previd="session-xyz"/>
        StanzaNode node = new StanzaNode.build("resumed", SM_NS)
            .add_self_xmlns()
            .put_attribute("h", "255", SM_NS)
            .put_attribute("previd", "session-xyz");

        string? h_str = node.get_attribute("h", SM_NS);
        fail_if(h_str == null, "h attribute missing from resumed stanza");
        int h = int.parse(h_str);
        fail_if_not_eq_int(h, 255);
    }

    private void test_parse_ack() {
        // Parse: <a xmlns="urn:xmpp:sm:3" h="100"/>
        StanzaNode node = new StanzaNode.build("a", SM_NS)
            .add_self_xmlns()
            .put_attribute("h", "100", SM_NS);

        string? h_str = node.get_attribute("h", SM_NS);
        fail_if(h_str == null, "h attribute missing from ack");
        int parsed_h = int.parse(h_str);
        fail_if_not_eq_int(parsed_h, 100);
    }

    private void test_parse_failed() {
        // <failed xmlns="urn:xmpp:sm:3" h="50"><item-not-found .../></failed>
        StanzaNode node = new StanzaNode.build("failed", SM_NS)
            .add_self_xmlns()
            .put_attribute("h", "50", SM_NS)
            .put_node(new StanzaNode.build("item-not-found", "urn:ietf:params:xml:ns:xmpp-stanzas"));

        fail_if_not_eq_str(node.name, "failed");

        string? h_acked = node.get_attribute("h", SM_NS);
        fail_if(h_acked == null, "h attribute missing from failed stanza");
        fail_if_not_eq_int(int.parse(h_acked), 50);

        // Verify error child node exists (different namespace than parent)
        string STANZA_ERROR_NS = "urn:ietf:params:xml:ns:xmpp-stanzas";
        StanzaNode? error_node = node.get_subnode("item-not-found", STANZA_ERROR_NS);
        fail_if(error_node == null, "item-not-found child missing");
    }

    private void test_h_counter_overflow() {
        // h is 32-bit unsigned in spec (2^32 - 1 max), but Vala int is signed 32-bit
        // Test that large values parse correctly within int range
        StanzaNode node = new StanzaNode.build("a", SM_NS)
            .add_self_xmlns()
            .put_attribute("h", "2147483647", SM_NS); // INT32_MAX

        string? h_str = node.get_attribute("h", SM_NS);
        int h = int.parse(h_str);
        fail_if_not_eq_int(h, 2147483647);
    }

    private void test_features_check() {
        // Build a features node that contains sm, then verify lookup
        StanzaNode features = new StanzaNode.build("features", "http://etherx.jabber.org/streams")
            .put_node(new StanzaNode.build("sm", SM_NS).add_self_xmlns());

        StanzaNode? sm_node = features.get_subnode("sm", SM_NS);
        fail_if(sm_node == null, "sm feature not found in features node");
        fail_if_not_eq_str(sm_node.ns_uri, SM_NS);
    }
}

}
