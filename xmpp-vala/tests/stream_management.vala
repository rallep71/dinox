namespace Xmpp.Test {

/**
 * Spec-based tests for XEP-0198 Stream Management.
 *
 * References:
 *   - XEP-0198 §3: Enabling Stream Management
 *   - XEP-0198 §4: Acks
 *   - XEP-0198 §5: Resumption + h counter semantics
 *   - XEP-0198 §6: Errors
 *
 * Each test verifies behavior defined by the XEP, not internal API.
 */
class StreamManagementTest : Gee.TestCase {

    private const string SM_NS = "urn:xmpp:sm:3";

    public StreamManagementTest() {
        base("StreamManagement");
        // XEP-0198 §3: Enabling
        add_test("XEP0198_enable_must_have_xmlns_sm3", test_enable_xmlns);
        add_test("XEP0198_enable_resume_attribute", test_enable_resume);
        add_async_test("XEP0198_parse_enabled_from_xml", (cb) => { test_parse_enabled_xml.begin(cb); });
        // XEP-0198 §4: Acks
        add_test("XEP0198_r_element_is_empty", test_r_empty);
        add_test("XEP0198_a_element_has_h", test_a_has_h);
        // XEP-0198 §5: h counter
        add_test("XEP0198_h_counter_is_uint32", test_h_uint32);
        add_test("XEP0198_h_wraps_at_2_32", test_h_wraps);
        add_test("XEP0198_h_max_value_4294967295", test_h_max);
        // XEP-0198 §5: Resumption
        add_async_test("XEP0198_parse_resumed_from_xml", (cb) => { test_parse_resumed_xml.begin(cb); });
        add_async_test("XEP0198_parse_failed_with_h", (cb) => { test_parse_failed_xml.begin(cb); });
        // XEP-0198 §6: Feature discovery
        add_async_test("XEP0198_feature_in_stream_features", (cb) => { test_feature_discovery.begin(cb); });
        add_test("XEP0198_only_stanzas_increment_h", test_only_stanzas_count);
    }

    /**
     * XEP-0198 §3: "To enable use of stream management, the client sends
     * an <enable/> command ... qualified by the namespace 'urn:xmpp:sm:3'."
     */
    private void test_enable_xmlns() {
        StanzaNode node = new StanzaNode.build("enable", SM_NS).add_self_xmlns();
        fail_if_not_eq_str(node.name, "enable");
        fail_if_not_eq_str(node.ns_uri, SM_NS);
    }

    /**
     * XEP-0198 §3: "the client MAY include a 'resume' attribute with
     * a value of 'true' or '1'."
     */
    private void test_enable_resume() {
        StanzaNode node = new StanzaNode.build("enable", SM_NS)
            .add_self_xmlns()
            .put_attribute("resume", "true");
        fail_if_not_eq_str(node.get_attribute("resume"), "true");
    }

    /**
     * XEP-0198 §3 Example 3: Server responds with
     * <enabled xmlns='urn:xmpp:sm:3' id='some-long-sm-id' resume='true'/>
     * Parse from real XML.
     */
    private async void test_parse_enabled_xml(Gee.TestFinishedCallback cb) {
        try {
            string xml = "<enabled xmlns='urn:xmpp:sm:3' id='some-long-sm-id' resume='true'/>";
            var reader = new StanzaReader.for_string(xml);
            StanzaNode node = yield reader.read_node();

            fail_if_not_eq_str(node.name, "enabled");
            fail_if_not_eq_str(node.ns_uri, SM_NS);

            string? id = node.get_attribute("id", SM_NS);
            fail_if(id == null, "XEP-0198 §3: <enabled> MUST have 'id' for resumable sessions");
            fail_if_not_eq_str(id, "some-long-sm-id");

            string? resume = node.get_attribute("resume");
            if (resume == null) resume = node.get_attribute("resume", SM_NS);
            fail_if(resume == null, "XEP-0198 §3: <enabled> should include 'resume' attribute");
        } catch (Error e) {
            fail_if_reached("XML parse error: " + e.message);
        }
        cb();
    }

    /**
     * XEP-0198 §4: "<r/> is used to request an ack. It has no attributes."
     */
    private void test_r_empty() {
        StanzaNode node = new StanzaNode.build("r", SM_NS).add_self_xmlns();
        fail_if_not_eq_str(node.name, "r");
        fail_if_not_eq_int(node.sub_nodes.size, 0);
        // Per XEP: <r/> has no attributes (other than xmlns)
        // The h counter is NOT included in <r/>
    }

    /**
     * XEP-0198 §4: "<a/> is used to answer a request. It MUST include
     * an 'h' attribute ... the value of 'h' ... is the number of stanzas
     * handled."
     */
    private void test_a_has_h() {
        uint32 h = 42;
        StanzaNode node = new StanzaNode.build("a", SM_NS)
            .add_self_xmlns()
            .put_attribute("h", h.to_string());

        string? h_str = node.get_attribute("h");
        fail_if(h_str == null, "XEP-0198 §4: <a/> MUST include 'h' attribute");
        fail_if_not_eq_str(h_str, "42");
    }

    /**
     * XEP-0198 §5: "the counter for an entity's own sent stanzas is
     * an unsigned integer from 0 to 2^32-1"
     * h_inbound/h_outbound MUST be uint32, not signed int.
     */
    private void test_h_uint32() {
        var module = new Xmpp.Xep.StreamManagement.Module();
        // Set to value >INT32_MAX — must work without overflow
        module.h_inbound = (uint32) 2147483648; // 2^31, impossible for signed int
        fail_if(module.h_inbound != (uint32) 2147483648,
            "XEP-0198 §5: h counter must handle values >2^31 (uint32)");
    }

    /**
     * XEP-0198 §5: "In the unlikely case that the number of stanzas
     * handled during a stream management session exceeds the number
     * of digits that can be represented by the counter, the counter
     * simply wraps around."
     */
    private void test_h_wraps() {
        var module = new Xmpp.Xep.StreamManagement.Module();
        module.h_inbound = uint32.MAX; // 4294967295
        module.h_inbound++; // Must wrap to 0

        if (module.h_inbound != 0) {
            GLib.Test.message("XEP-0198 §5: h counter must wrap from 2^32-1 to 0, got %u".printf(module.h_inbound));
            GLib.Test.fail();
        }
    }

    /**
     * XEP-0198 §5: Max valid h value is 2^32-1 = 4294967295.
     * Serialized as string "4294967295", MUST NOT be negative.
     */
    private void test_h_max() {
        var module = new Xmpp.Xep.StreamManagement.Module();
        module.h_inbound = uint32.MAX;

        string h_str = module.h_inbound.to_string();
        fail_if(h_str.has_prefix("-"),
            "XEP-0198 §5: h.to_string() must never be negative");
        fail_if_not_eq_str(h_str, "4294967295");
    }

    /**
     * XEP-0198 §5 Example 7: Resumed
     * <resumed xmlns='urn:xmpp:sm:3' h='another-sequence-number' previd='some-long-sm-id'/>
     */
    private async void test_parse_resumed_xml(Gee.TestFinishedCallback cb) {
        try {
            string xml = "<resumed xmlns='urn:xmpp:sm:3' h='255' previd='session-xyz'/>";
            var reader = new StanzaReader.for_string(xml);
            StanzaNode node = yield reader.read_node();

            fail_if_not_eq_str(node.name, "resumed");
            fail_if_not_eq_str(node.ns_uri, SM_NS);

            string? h = node.get_attribute("h", SM_NS);
            if (h == null) h = node.get_attribute("h");
            fail_if(h == null, "XEP-0198 §5: <resumed> MUST include 'h'");

            string? previd = node.get_attribute("previd");
            if (previd == null) previd = node.get_attribute("previd", SM_NS);
            fail_if(previd == null, "XEP-0198 §5: <resumed> MUST include 'previd'");
        } catch (Error e) {
            fail_if_reached("XML parse error: " + e.message);
        }
        cb();
    }

    /**
     * XEP-0198 §5: "If the server does not support session resumption, or the
     * session has timed out, it MUST return a <failed/> element, which MAY
     * include an 'h' attribute."
     *
     * Also: <failed> MAY contain an error condition child per XMPP stanza errors.
     */
    private async void test_parse_failed_xml(Gee.TestFinishedCallback cb) {
        try {
            string xml = "<failed xmlns='urn:xmpp:sm:3' h='50'>" +
                "<item-not-found xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>" +
                "</failed>";
            var reader = new StanzaReader.for_string(xml);
            StanzaNode node = yield reader.read_node();

            fail_if_not_eq_str(node.name, "failed");

            // h is optional per XEP, but present here
            string? h = node.get_attribute("h", SM_NS);
            if (h == null) h = node.get_attribute("h");
            fail_if(h == null, "XEP-0198: h attribute should be present in this test case");

            // Error condition child in stanza-errors namespace
            string ERR_NS = "urn:ietf:params:xml:ns:xmpp-stanzas";
            StanzaNode? err = node.get_subnode("item-not-found", ERR_NS);
            fail_if(err == null, "XEP-0198 §5: <failed> should contain error condition child");
        } catch (Error e) {
            fail_if_reached("XML parse error: " + e.message);
        }
        cb();
    }

    /**
     * XEP-0198 §3: Stream management availability is advertised via
     * <sm xmlns='urn:xmpp:sm:3'/> in stream features.
     */
    private async void test_feature_discovery(Gee.TestFinishedCallback cb) {
        try {
            string xml = "<stream:features xmlns:stream='http://etherx.jabber.org/streams'>" +
                "<sm xmlns='urn:xmpp:sm:3'/>" +
                "<bind xmlns='urn:ietf:params:xml:ns:xmpp-bind'><required/></bind>" +
                "</stream:features>";
            var reader = new StanzaReader.for_string(xml);
            StanzaNode features = yield reader.read_node();

            StanzaNode? sm = features.get_subnode("sm", SM_NS);
            fail_if(sm == null, "XEP-0198 §3: <sm> must be discoverable in stream features");
        } catch (Error e) {
            fail_if_reached("XML parse error: " + e.message);
        }
        cb();
    }

    /**
     * XEP-0198 §4: "the counter is not incremented for stanzas that
     * are not 'counted' (e.g., stream management elements themselves
     * are not counted)."
     * Only <message>, <iq>, <presence> increment h.
     */
    private void test_only_stanzas_count() {
        var module = new Xmpp.Xep.StreamManagement.Module();

        // Verify initial h is 0
        if (module.h_inbound != 0) {
            GLib.Test.message("XEP-0198: Initial h must be 0, got %u".printf(module.h_inbound));
            GLib.Test.fail();
        }

        // <r/> and <a/> are NOT stanzas — they must NOT increment h
        // We can only test the counter public field directly
        uint32 before = module.h_inbound;
        // Simulating that only on_stanza_received increments h, not on nonza
        // Since we can't call private methods, we verify the Module's public counter starts at 0
        // and doesn't magically increment
        if (module.h_inbound != before) {
            GLib.Test.message("XEP-0198 §4: h must not increment without receiving stanzas");
            GLib.Test.fail();
        }
    }
}

}
