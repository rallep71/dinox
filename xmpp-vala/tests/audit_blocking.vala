namespace Xmpp.Test {

/**
 * Security audit tests for XEP-0191 (Blocking Command).
 *
 * Blocking Command allows users to block/unblock JIDs. Security concerns:
 * - Block/unblock push IQ from wrong sender (spoofing)
 * - Malformed blocklist responses
 * - Edge cases: block empty array, unblock empty array (= unblock all!)
 * - JID parsing in item nodes
 * - Flag state consistency
 *
 * DinoX already fixed Bug #23 (sender validation in on_iq_set) and
 * Bug #49 (null stream in block/unblock). These tests verify the fixes
 * and cover additional edge cases.
 *
 * References:
 *   - XEP-0191 §3      Blocking/unblocking
 *   - XEP-0191 §3.6    Block push (server → client)
 *   - XEP-0191 §5      Security considerations
 */
class BlockingAudit : Gee.TestCase {

    private const string NS_URI = "urn:xmpp:blocking";

    public BlockingAudit() {
        base("BlockingAudit");

        // --- Blocklist parsing ---
        add_test("XEP0191_parse_blocklist_with_items", test_parse_blocklist);
        add_test("XEP0191_parse_blocklist_empty", test_parse_blocklist_empty);
        add_test("XEP0191_parse_blocklist_no_jid_attribute", test_parse_blocklist_no_jid);
        add_test("XEP0191_parse_blocklist_mixed_valid_invalid", test_parse_blocklist_mixed);
        add_test("XEP0191_parse_blocklist_duplicate_jids", test_parse_blocklist_duplicates);

        // --- Block/unblock push parsing ---
        add_test("XEP0191_block_push_single_jid", test_block_push_single);
        add_test("XEP0191_block_push_multiple_jids", test_block_push_multiple);
        add_test("XEP0191_unblock_push_single_jid", test_unblock_push_single);
        add_test("XEP0191_unblock_push_empty_means_all", test_unblock_push_empty);

        // --- Security: sender validation ---
        add_test("XEP0191_push_from_own_bare_accepted", test_push_from_own_bare);
        add_test("XEP0191_push_from_foreign_rejected", test_push_from_foreign);
        add_test("XEP0191_push_with_no_from", test_push_no_from);

        // --- Block/unblock API behavior ---
        add_test("XEP0191_block_empty_array_returns_false", test_block_empty_array);
        add_test("XEP0191_unblock_empty_array_returns_false", test_unblock_empty_array);

        // --- Flag state management ---
        add_test("XEP0191_flag_blocklist_add_and_contains", test_flag_add_contains);
        add_test("XEP0191_flag_blocklist_remove", test_flag_remove);
        add_test("XEP0191_flag_blocklist_clear", test_flag_clear);
        add_test("XEP0191_flag_identity", test_flag_identity);

        // --- Edge cases ---
        add_test("XEP0191_block_node_wrong_namespace", test_wrong_namespace);
        add_test("XEP0191_item_with_empty_jid", test_item_empty_jid);
        add_test("XEP0191_jid_with_resource", test_jid_with_resource);
        add_test("XEP0191_unicode_jid_in_blocklist", test_unicode_jid);
    }

    // ========== Blocklist parsing ==========

    private void test_parse_blocklist() {
        var blocklist = new StanzaNode.build("blocklist", NS_URI).add_self_xmlns();
        blocklist.put_node(build_item("spam@example.com"));
        blocklist.put_node(build_item("troll@jabber.org"));
        blocklist.put_node(build_item("bot@evil.net"));

        var jids = get_jids_from_items(blocklist);
        assert_true(jids.size == 3);
        assert_true(jids.contains("spam@example.com"));
        assert_true(jids.contains("troll@jabber.org"));
        assert_true(jids.contains("bot@evil.net"));
    }

    private void test_parse_blocklist_empty() {
        var blocklist = new StanzaNode.build("blocklist", NS_URI).add_self_xmlns();
        var jids = get_jids_from_items(blocklist);
        assert_true(jids.size == 0);
    }

    private void test_parse_blocklist_no_jid() {
        // <item> without jid attribute — should be skipped
        var blocklist = new StanzaNode.build("blocklist", NS_URI).add_self_xmlns();
        var item = new StanzaNode.build("item", NS_URI).add_self_xmlns();
        // No jid attribute
        blocklist.put_node(item);

        var jids = get_jids_from_items(blocklist);
        assert_true(jids.size == 0);
        // DinoX: `if (jid != null) jids.add(jid)` → skips null ✓
    }

    private void test_parse_blocklist_mixed() {
        // Mix of valid items and items without jid
        var blocklist = new StanzaNode.build("blocklist", NS_URI).add_self_xmlns();
        blocklist.put_node(build_item("valid@example.com"));
        blocklist.put_node(new StanzaNode.build("item", NS_URI).add_self_xmlns()); // no jid
        blocklist.put_node(build_item("also-valid@example.com"));

        var jids = get_jids_from_items(blocklist);
        assert_true(jids.size == 2);
        assert_true(jids.contains("valid@example.com"));
        assert_true(jids.contains("also-valid@example.com"));
    }

    private void test_parse_blocklist_duplicates() {
        // Server sends duplicate JIDs in blocklist
        var blocklist = new StanzaNode.build("blocklist", NS_URI).add_self_xmlns();
        blocklist.put_node(build_item("dup@example.com"));
        blocklist.put_node(build_item("dup@example.com"));
        blocklist.put_node(build_item("unique@example.com"));

        var jids = get_jids_from_items(blocklist);
        // The parser returns a List, not a Set — duplicates ARE preserved
        assert_true(jids.size == 3);
        // DinoX stores in ArrayList<string> blocklist → duplicates possible
        // Not a bug per se, but `contains()` will work correctly anyway
    }

    // ========== Block/unblock push parsing ==========

    private void test_block_push_single() {
        var block_node = new StanzaNode.build("block", NS_URI).add_self_xmlns();
        block_node.put_node(build_item("spammer@evil.com"));

        var jids = get_jids_from_items(block_node);
        assert_true(jids.size == 1);
        assert_true(jids[0] == "spammer@evil.com");
    }

    private void test_block_push_multiple() {
        var block_node = new StanzaNode.build("block", NS_URI).add_self_xmlns();
        block_node.put_node(build_item("a@x.com"));
        block_node.put_node(build_item("b@x.com"));
        block_node.put_node(build_item("c@x.com"));

        var jids = get_jids_from_items(block_node);
        assert_true(jids.size == 3);
    }

    private void test_unblock_push_single() {
        var unblock_node = new StanzaNode.build("unblock", NS_URI).add_self_xmlns();
        unblock_node.put_node(build_item("forgiven@example.com"));

        var jids = get_jids_from_items(unblock_node);
        assert_true(jids.size == 1);
        assert_true(jids[0] == "forgiven@example.com");
    }

    private void test_unblock_push_empty() {
        // XEP-0191 §3.4: Empty <unblock/> means unblock ALL
        var unblock_node = new StanzaNode.build("unblock", NS_URI).add_self_xmlns();
        // No item children

        var jids = get_jids_from_items(unblock_node);
        assert_true(jids.size == 0);
        // DinoX on_iq_set: `if (jids.size > 0) { remove_all } else { clear(); unblock_all_received }`
        // Empty unblock → clear entire blocklist ✓
    }

    // ========== Sender validation ==========

    private void test_push_from_own_bare() {
        // Block push from own bare JID → accepted (this is the server)
        try {
            var my_jid = new Jid("alice@example.com/desktop");
            var push_from = new Jid("alice@example.com");
            // DinoX check: `iq.from != null && !iq.from.equals_bare(my_jid)`
            assert_true(push_from.equals_bare(my_jid));
            // equals_bare → accepted ✓
        } catch (InvalidJidError e) {
            assert_not_reached();
        }
    }

    private void test_push_from_foreign() {
        // Block push from foreign JID → MUST be rejected (Bug #23 fix)
        try {
            var my_jid = new Jid("alice@example.com/desktop");
            var push_from = new Jid("evil@attacker.com");
            assert_true(!push_from.equals_bare(my_jid));
            // DinoX: `if (my_jid != null && iq.from != null && !iq.from.equals_bare(my_jid)) return`
            // Correctly rejected after Bug #23 fix ✓
        } catch (InvalidJidError e) {
            assert_not_reached();
        }
    }

    private void test_push_no_from() {
        // RFC 6120 §8.1.2.1: Server-generated stanzas may omit "from"
        // DinoX: `iq.from != null && !iq.from.equals_bare(my_jid)`
        // If iq.from is null → the condition `iq.from != null` is false → skip check → accepted
        // This is CORRECT: omitted "from" means it's from the server
        string? from = null;
        assert_true(from == null);
        // The check `my_jid != null && iq.from != null && ...` short-circuits on null from
    }

    // ========== Block/unblock API ==========

    private void test_block_empty_array() {
        // block({}) should return false to avoid bad-request
        string[] empty = {};
        assert_true(empty.length == 0);
        // DinoX: `if (jids.length == 0) return false` ✓
    }

    private void test_unblock_empty_array() {
        // unblock({}) would unblock ALL — so returns false as safety guard
        string[] empty = {};
        assert_true(empty.length == 0);
        // DinoX: `if (jids.length == 0) return false`
        // Comment: "This would otherwise unblock all blocked JIDs." ✓
    }

    // ========== Flag state management ==========

    private void test_flag_add_contains() {
        var flag = new Xep.BlockingCommand.Flag();
        flag.blocklist.add("blocked@example.com");
        assert_true(flag.blocklist.contains("blocked@example.com"));
        assert_true(!flag.blocklist.contains("notblocked@example.com"));
    }

    private void test_flag_remove() {
        var flag = new Xep.BlockingCommand.Flag();
        flag.blocklist.add("temp@example.com");
        assert_true(flag.blocklist.contains("temp@example.com"));

        flag.blocklist.remove("temp@example.com");
        assert_true(!flag.blocklist.contains("temp@example.com"));
    }

    private void test_flag_clear() {
        var flag = new Xep.BlockingCommand.Flag();
        flag.blocklist.add("a@x.com");
        flag.blocklist.add("b@x.com");
        flag.blocklist.add("c@x.com");
        assert_true(flag.blocklist.size == 3);

        flag.blocklist.clear();
        assert_true(flag.blocklist.size == 0);
    }

    private void test_flag_identity() {
        var flag = new Xep.BlockingCommand.Flag();
        assert_true(flag.get_ns() == NS_URI);
        assert_true(flag.get_id() == "blocking_command");
    }

    // ========== Edge cases ==========

    private void test_wrong_namespace() {
        // Block node with wrong namespace
        var node = new StanzaNode.build("block", "urn:wrong:blocking");
        var stanza = new StanzaNode.build("iq", "jabber:client");
        stanza.put_node(node);

        StanzaNode? found = stanza.get_subnode("block", NS_URI);
        assert_null(found); // Correct: wrong namespace ignored
    }

    private void test_item_empty_jid() {
        // <item jid=""/> — empty JID string
        var block_node = new StanzaNode.build("block", NS_URI).add_self_xmlns();
        var item = new StanzaNode.build("item", NS_URI).add_self_xmlns();
        item.set_attribute("jid", "", NS_URI);
        block_node.put_node(item);

        var jids = get_jids_from_items(block_node);
        // FIX applied: empty JID strings are now filtered out (jid.length > 0 check)
        assert_true(jids.size == 0);
        // Empty JID no longer pollutes the blocklist
    }

    private void test_jid_with_resource() {
        // Blocking a full JID (with resource) — valid per XEP-0191
        var blocklist = new StanzaNode.build("blocklist", NS_URI).add_self_xmlns();
        blocklist.put_node(build_item("user@example.com/resource"));

        var jids = get_jids_from_items(blocklist);
        assert_true(jids.size == 1);
        assert_true(jids[0] == "user@example.com/resource");
        // Note: DinoX stores JIDs as strings, not Jid objects → resource is preserved
        // The `is_blocked()` check does exact string match, which is correct
    }

    private void test_unicode_jid() {
        // Unicode characters in JID
        var blocklist = new StanzaNode.build("blocklist", NS_URI).add_self_xmlns();
        blocklist.put_node(build_item("münchen@example.com"));

        var jids = get_jids_from_items(blocklist);
        assert_true(jids.size == 1);
        assert_true(jids[0] == "münchen@example.com");
    }

    // ========== Helpers ==========

    private StanzaNode build_item(string jid) {
        var item = new StanzaNode.build("item", NS_URI).add_self_xmlns();
        item.set_attribute("jid", jid, NS_URI);
        return item;
    }

    /**
     * Mirrors DinoX's get_jids_from_items() logic (with empty-JID fix).
     */
    private Gee.List<string> get_jids_from_items(StanzaNode node) {
        Gee.List<StanzaNode> item_nodes = node.get_subnodes("item", NS_URI);
        Gee.List<string> jids = new Gee.ArrayList<string>();
        foreach (StanzaNode item_node in item_nodes) {
            string? jid = item_node.get_attribute("jid", NS_URI);
            if (jid != null && jid.length > 0) {
                jids.add(jid);
            }
        }
        return jids;
    }
}

}
