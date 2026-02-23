namespace Xmpp.Test {

/**
 * Tests for XEP-0313 Message Archive Management stanza construction and parsing.
 * Verifies query construction, result-set parsing, and MAM message flag handling.
 */
class MAMTest : Gee.TestCase {

    private const string MAM_NS = "urn:xmpp:mam:2";
    private const string RSM_NS = "urn:xmpp:rsm";
    private const string FORWARD_NS = "urn:xmpp:forward:0";
    private const string DELAY_NS = "urn:xmpp:delay";
    private const string DATAFORMS_NS = "jabber:x:data";

    public MAMTest() {
        base("MAM");
        add_test("query_node", test_query_node);
        add_test("query_with_queryid", test_query_with_queryid);
        add_test("fin_complete", test_fin_complete);
        add_test("fin_incomplete", test_fin_incomplete);
        add_test("fin_rsm_parsing", test_fin_rsm_parsing);
        add_test("fin_missing_rsm", test_fin_missing_rsm);
        add_test("result_wrapper", test_result_wrapper);
        add_test("message_flag", test_message_flag);
    }

    private void test_query_node() {
        // Build: <query xmlns="urn:xmpp:mam:2" queryid="q1"/>
        StanzaNode query = new StanzaNode.build("query", MAM_NS)
            .add_self_xmlns()
            .put_attribute("queryid", "q1");

        fail_if_not_eq_str(query.name, "query");
        fail_if_not_eq_str(query.ns_uri, MAM_NS);
        fail_if_not_eq_str(query.get_attribute("queryid"), "q1");
    }

    private void test_query_with_queryid() {
        // Verify queryid survives round-trip
        string qid = "unique-query-42";
        StanzaNode query = new StanzaNode.build("query", MAM_NS)
            .add_self_xmlns()
            .put_attribute("queryid", qid);

        string? retrieved = query.get_attribute("queryid");
        fail_if_not_eq_str(retrieved, qid);
    }

    private void test_fin_complete() {
        // Build: <fin xmlns="urn:xmpp:mam:2" complete="true">
        //          <set xmlns="urn:xmpp:rsm">
        //            <first>id-001</first>
        //            <last>id-050</last>
        //          </set>
        //        </fin>
        StanzaNode fin = new StanzaNode.build("fin", MAM_NS)
            .add_self_xmlns()
            .put_attribute("complete", "true", MAM_NS)
            .put_node(
                new StanzaNode.build("set", RSM_NS)
                    .add_self_xmlns()
                    .put_node(new StanzaNode.build("first", RSM_NS).put_node(new StanzaNode.text("id-001")))
                    .put_node(new StanzaNode.build("last", RSM_NS).put_node(new StanzaNode.text("id-050")))
            );

        // Parse complete attribute
        string? complete_str = fin.get_attribute("complete", MAM_NS);
        fail_if_not_eq_str(complete_str, "true");

        // Parse RSM
        StanzaNode? rsm = fin.get_subnode("set", RSM_NS);
        fail_if(rsm == null, "RSM set node missing");

        string? first = rsm.get_deep_string_content("first");
        string? last = rsm.get_deep_string_content("last");
        fail_if_not_eq_str(first, "id-001");
        fail_if_not_eq_str(last, "id-050");
    }

    private void test_fin_incomplete() {
        // <fin xmlns="urn:xmpp:mam:2"> (no complete attribute = incomplete)
        StanzaNode fin = new StanzaNode.build("fin", MAM_NS)
            .add_self_xmlns()
            .put_node(
                new StanzaNode.build("set", RSM_NS)
                    .add_self_xmlns()
                    .put_node(new StanzaNode.build("first", RSM_NS).put_node(new StanzaNode.text("a")))
                    .put_node(new StanzaNode.build("last", RSM_NS).put_node(new StanzaNode.text("z")))
            );

        bool complete = fin.get_attribute_bool("complete", false, MAM_NS);
        fail_if(complete, "fin without complete attr should default to false");
    }

    private void test_fin_rsm_parsing() {
        // Verify both first and last are null when RSM contains no children
        StanzaNode fin = new StanzaNode.build("fin", MAM_NS)
            .add_self_xmlns()
            .put_node(new StanzaNode.build("set", RSM_NS).add_self_xmlns());

        StanzaNode? rsm = fin.get_subnode("set", RSM_NS);
        fail_if(rsm == null, "RSM set node missing");

        string? first = rsm.get_deep_string_content("first");
        string? last = rsm.get_deep_string_content("last");
        // Both must be null (empty result set)
        fail_if(first != null, "first should be null for empty RSM");
        fail_if(last != null, "last should be null for empty RSM");
    }

    private void test_fin_missing_rsm() {
        // <fin> without <set> is malformed
        StanzaNode fin = new StanzaNode.build("fin", MAM_NS).add_self_xmlns();

        StanzaNode? rsm = fin.get_subnode("set", RSM_NS);
        fail_if(rsm != null, "RSM should be null when not present");
    }

    private void test_result_wrapper() {
        // Build a MAM result wrapper:
        // <result xmlns="urn:xmpp:mam:2" queryid="q1" id="msg-28836">
        //   <forwarded xmlns="urn:xmpp:forward:0">
        //     <message from="user@example.com" .../>
        //   </forwarded>
        // </result>
        StanzaNode result = new StanzaNode.build("result", MAM_NS)
            .add_self_xmlns()
            .put_attribute("queryid", "q1", MAM_NS)
            .put_attribute("id", "msg-28836", MAM_NS)
            .put_node(
                new StanzaNode.build("forwarded", FORWARD_NS)
                    .add_self_xmlns()
                    .put_node(
                        new StanzaNode.build("message")
                            .put_attribute("from", "user@example.com")
                    )
            );

        // Extract queryid and id
        string? qid = result.get_attribute("queryid", MAM_NS);
        string? mam_id = result.get_attribute("id", MAM_NS);
        fail_if_not_eq_str(qid, "q1");
        fail_if_not_eq_str(mam_id, "msg-28836");

        // Navigate to inner message
        StanzaNode? message = result.get_deep_subnode(
            FORWARD_NS + ":forwarded",
            "jabber:client" + ":message"
        );
        fail_if(message == null, "inner message not found in result/forwarded");
        fail_if_not_eq_str(message.get_attribute("from"), "user@example.com");
    }

    private void test_message_flag() {
        // Test MessageFlag data object
        try {
            Jid sender = new Jid("archive@example.com");
            DateTime time = new DateTime.utc(2026, 2, 23, 10, 30, 0);
            var flag = new MessageArchiveManagement.MessageFlag(sender, time, "mam-id-1", "query-1");

            fail_if_not_eq_str(flag.sender_jid.to_string(), "archive@example.com");
            fail_if_not_eq_str(flag.mam_id, "mam-id-1");
            fail_if_not_eq_str(flag.query_id, "query-1");
            fail_if(flag.server_time == null, "server_time should not be null");
        } catch (InvalidJidError e) {
            fail_if_reached(@"Unexpected JID error: $(e.message)");
        }
    }
}

}
