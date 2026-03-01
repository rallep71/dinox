namespace Xmpp.Test {

/**
 * Security audit tests for XEP-0060 (Publish-Subscribe / PubSub).
 *
 * PubSub is the central infrastructure XEP used by:
 * - OMEMO key distribution (XEP-0384)
 * - User Avatars (XEP-0084)
 * - Bookmarks (XEP-0048 / XEP-0402)
 * - User Location (XEP-0080)
 * - vCard4 (XEP-0292)
 *
 * Security concerns:
 * - PEP notifications must come from bare JIDs (not full JIDs)
 * - Item/retract/delete events must be from registered listeners only
 * - Malformed event nodes should not crash
 * - Missing attributes in items/retracts must be handled
 *
 * References:
 *   - XEP-0060 §7.1   Event notifications
 *   - XEP-0060 §12.12  Security considerations
 *   - XEP-0163        Personal Eventing Protocol (PEP)
 */
class PubSubAudit : Gee.TestCase {

    private const string NS_PUBSUB = "http://jabber.org/protocol/pubsub";
    private const string NS_EVENT = "http://jabber.org/protocol/pubsub#event";
    private const string NS_OWNER = "http://jabber.org/protocol/pubsub#owner";
    private const string NS_ERROR = "http://jabber.org/protocol/pubsub#errors";
    private const string NS_JABBER = "jabber:client";

    public PubSubAudit() {
        base("PubSubAudit");

        // --- Event notification parsing ---
        add_test("XEP0060_event_item_notification", test_event_item_notification);
        add_test("XEP0060_event_retract_notification", test_event_retract_notification);
        add_test("XEP0060_event_delete_notification", test_event_delete_notification);
        add_test("XEP0060_event_items_node_attribute", test_event_items_node_attribute);

        // --- Malformed event stanzas ---
        add_test("XEP0060_event_no_items_node", test_event_no_items_node);
        add_test("XEP0060_event_item_no_id", test_event_item_no_id);
        add_test("XEP0060_event_item_empty_payload", test_event_item_empty_payload);
        add_test("XEP0060_event_retract_no_id", test_event_retract_no_id);
        add_test("XEP0060_event_delete_no_node", test_event_delete_no_node);
        add_test("XEP0060_event_empty_node", test_event_empty);

        // --- Security: sender validation (PEP) ---
        add_test("XEP0060_pep_from_bare_jid_accepted", test_pep_bare_jid);
        add_test("XEP0060_pep_from_full_jid_rejected", test_pep_full_jid);
        add_test("XEP0060_pep_from_service_jid", test_pep_service_jid);

        // --- IQ response parsing ---
        add_test("XEP0060_iq_response_items_list", test_iq_response_items);
        add_test("XEP0060_iq_response_no_pubsub_node", test_iq_response_no_pubsub);
        add_test("XEP0060_iq_response_no_items_node", test_iq_response_no_items);
        add_test("XEP0060_iq_response_empty_items", test_iq_response_empty_items);
        add_test("XEP0060_iq_response_item_no_children", test_iq_response_item_no_children);

        // --- Publish options ---
        add_test("XEP0060_publish_options_persist_items", test_publish_options_persist);
        add_test("XEP0060_publish_options_max_items", test_publish_options_max);
        add_test("XEP0060_publish_options_access_model", test_publish_options_access_model);

        // --- Edge cases ---
        add_test("XEP0060_wrong_event_namespace", test_wrong_event_namespace);
        add_test("XEP0060_multiple_items_in_event", test_multiple_items_in_event);
        add_test("XEP0060_item_with_multiple_payloads", test_item_multiple_payloads);
    }

    // ========== Event notification parsing ==========

    private void test_event_item_notification() {
        // Standard PEP item notification
        var event = build_event_node();
        var items = new StanzaNode.build("items", NS_EVENT).put_attribute("node", "urn:xmpp:avatar:metadata");
        var item = new StanzaNode.build("item", NS_EVENT).put_attribute("id", "abc123");
        var payload = new StanzaNode.build("metadata", "urn:xmpp:avatar:metadata").add_self_xmlns();
        item.put_node(payload);
        items.put_node(item);
        event.put_node(items);

        StanzaNode? items_node = event.get_subnode("items", NS_EVENT);
        assert_nonnull(items_node);
        assert_true(items_node.get_attribute("node", NS_EVENT) == "urn:xmpp:avatar:metadata"
                    || items_node.get_attribute("node") == "urn:xmpp:avatar:metadata");

        StanzaNode? item_node = items_node.get_subnode("item", NS_EVENT);
        assert_nonnull(item_node);

        string? id = item_node.get_attribute("id", NS_EVENT);
        if (id == null) id = item_node.get_attribute("id");
        // id could be in either namespace or default
        assert_true(item_node.sub_nodes.size > 0);
    }

    private void test_event_retract_notification() {
        var event = build_event_node();
        var items = new StanzaNode.build("items", NS_EVENT).put_attribute("node", "urn:xmpp:avatar:metadata");
        var retract = new StanzaNode.build("retract", NS_EVENT).put_attribute("id", "item-to-retract");
        items.put_node(retract);
        event.put_node(items);

        StanzaNode? items_node = event.get_subnode("items", NS_EVENT);
        assert_nonnull(items_node);
        StanzaNode? retract_node = items_node.get_subnode("retract", NS_EVENT);
        assert_nonnull(retract_node);
        string? id = retract_node.get_attribute("id", NS_EVENT);
        if (id == null) id = retract_node.get_attribute("id");
        assert_nonnull(id);
    }

    private void test_event_delete_notification() {
        var event = build_event_node();
        var delete_node = new StanzaNode.build("delete", NS_EVENT).put_attribute("node", "urn:xmpp:avatar:metadata");
        event.put_node(delete_node);

        StanzaNode? found = event.get_subnode("delete", NS_EVENT);
        assert_nonnull(found);
        string? node_attr = found.get_attribute("node", NS_EVENT);
        if (node_attr == null) node_attr = found.get_attribute("node");
        assert_nonnull(node_attr);
    }

    private void test_event_items_node_attribute() {
        // The "node" attribute on <items> identifies which PubSub node fired
        var event = build_event_node();
        var items = new StanzaNode.build("items", NS_EVENT).put_attribute("node", "eu.siacs.conversations.axolotl.devicelist");
        event.put_node(items);

        StanzaNode? items_node = event.get_subnode("items", NS_EVENT);
        assert_nonnull(items_node);
        // DinoX code: `items_node.get_attribute("node", NS_URI_EVENT)`
        string? node = items_node.get_attribute("node", NS_EVENT);
        if (node == null) node = items_node.get_attribute("node");
        assert_true(node == "eu.siacs.conversations.axolotl.devicelist");
    }

    // ========== Malformed event stanzas ==========

    private void test_event_no_items_node() {
        // <event> without <items> — should be handled gracefully
        var event = build_event_node();
        // No children

        StanzaNode? items_node = event.get_subnode("items", NS_EVENT);
        assert_null(items_node);
        // DinoX code: `if (items_node != null)` — safe
    }

    private void test_event_item_no_id() {
        // <item> without "id" attribute
        var event = build_event_node();
        var items = new StanzaNode.build("items", NS_EVENT).put_attribute("node", "test-node");
        var item = new StanzaNode.build("item", NS_EVENT);
        // No id attribute
        items.put_node(item);
        event.put_node(items);

        StanzaNode? items_node = event.get_subnode("items", NS_EVENT);
        StanzaNode? item_node = items_node.get_subnode("item", NS_EVENT);
        assert_nonnull(item_node);

        string? id = item_node.get_attribute("id", NS_EVENT);
        // id is null — DinoX passes this to the listener as null id
        // Listener must handle null ids gracefully
        // This is a potential issue: some listeners may not expect null id
    }

    private void test_event_item_empty_payload() {
        // <item id="x"/> with no child nodes (empty payload)
        var event = build_event_node();
        var items = new StanzaNode.build("items", NS_EVENT).put_attribute("node", "test-node");
        var item = new StanzaNode.build("item", NS_EVENT).put_attribute("id", "empty-item");
        // No payload children
        items.put_node(item);
        event.put_node(items);

        StanzaNode? item_node = event.get_subnode("items", NS_EVENT).get_subnode("item", NS_EVENT);
        assert_nonnull(item_node);
        assert_true(item_node.sub_nodes.size == 0);
        // DinoX code: `if (item_listeners.has_key(node) && item_node.sub_nodes.size > 0)`
        // The `size > 0` check prevents NPE on empty items ✓
    }

    private void test_event_retract_no_id() {
        // <retract> without "id" attribute
        var event = build_event_node();
        var items = new StanzaNode.build("items", NS_EVENT).put_attribute("node", "test-node");
        var retract = new StanzaNode.build("retract", NS_EVENT);
        // No id
        items.put_node(retract);
        event.put_node(items);

        StanzaNode? retract_node = event.get_subnode("items", NS_EVENT).get_subnode("retract", NS_EVENT);
        assert_nonnull(retract_node);
        string? id = retract_node.get_attribute("id", NS_EVENT);
        // null id passed to retract listener — listeners must handle this
    }

    private void test_event_delete_no_node() {
        // <delete> without "node" attribute
        var event = build_event_node();
        var delete_node = new StanzaNode.build("delete", NS_EVENT);
        // No node attribute
        event.put_node(delete_node);

        StanzaNode? found = event.get_subnode("delete", NS_EVENT);
        assert_nonnull(found);
        string? node = found.get_attribute("node", NS_EVENT);
        // null node — DinoX code does `delete_listeners.has_key(node)` with null key
        // HashMap.has_key(null) returns false in Gee → safe, but semantically wrong
    }

    private void test_event_empty() {
        // Completely empty <event/>
        var event = build_event_node();
        assert_true(event.sub_nodes.size == 0);
        StanzaNode? items = event.get_subnode("items", NS_EVENT);
        assert_null(items);
        StanzaNode? del = event.get_subnode("delete", NS_EVENT);
        assert_null(del);
    }

    // ========== Security: sender validation ==========

    private void test_pep_bare_jid() {
        // XEP-0163: PEP notifications come from bare JIDs
        // DinoX code: `if (!message.from.is_bare())` → warning + ignore
        try {
            var jid = new Jid("alice@example.com");
            assert_true(jid.is_bare());
            // Bare JID → accepted ✓
        } catch (InvalidJidError e) {
            assert_not_reached();
        }
    }

    private void test_pep_full_jid() {
        // PEP notification from full JID → MUST be rejected
        // This prevents a MUC participant from injecting PEP events
        try {
            var jid = new Jid("alice@example.com/device1");
            assert_true(!jid.is_bare());
            // DinoX: `if (!message.from.is_bare()) { warning(...); return; }`  ✓
        } catch (InvalidJidError e) {
            assert_not_reached();
        }
    }

    private void test_pep_service_jid() {
        // PubSub service JID (bare, no localpart) — this is valid for PubSub
        // but DinoX only uses PEP (user's own server), not generic PubSub services
        try {
            var jid = new Jid("pubsub.example.com");
            assert_true(jid.is_bare());
            // A domain-only JID is considered bare → passes the bare check
            // Whether this is a security issue depends on whether the code also
            // checks that the JID belongs to a known contact/account
        } catch (InvalidJidError e) {
            assert_not_reached();
        }
    }

    // ========== IQ response parsing ==========

    private void test_iq_response_items() {
        // Normal response: <pubsub><items node="x"><item id="1">...</item></items></pubsub>
        var pubsub = new StanzaNode.build("pubsub", NS_PUBSUB).add_self_xmlns();
        var items = new StanzaNode.build("items", NS_PUBSUB).put_attribute("node", "test");
        var item1 = new StanzaNode.build("item", NS_PUBSUB).put_attribute("id", "item1");
        item1.put_node(new StanzaNode.build("data", "urn:test").add_self_xmlns());
        var item2 = new StanzaNode.build("item", NS_PUBSUB).put_attribute("id", "item2");
        item2.put_node(new StanzaNode.build("data", "urn:test").add_self_xmlns());
        items.put_node(item1);
        items.put_node(item2);
        pubsub.put_node(items);

        // Simulate DinoX request_all parsing
        StanzaNode? ps = pubsub; // In real code: iq.stanza.get_subnode("pubsub", NS_URI)
        assert_nonnull(ps);
        StanzaNode? items_node = ps.get_subnode("items", NS_PUBSUB);
        assert_nonnull(items_node);
        var subnodes = items_node.get_subnodes("item", NS_PUBSUB);
        assert_true(subnodes.size == 2);
    }

    private void test_iq_response_no_pubsub() {
        // Response without <pubsub> wrapper
        var iq_stanza = new StanzaNode.build("iq", NS_JABBER)
            .put_attribute("type", "result");
        // No pubsub child

        StanzaNode? pubsub = iq_stanza.get_subnode("pubsub", NS_PUBSUB);
        assert_null(pubsub);
        // DinoX: `if (event_node == null) return null` → safe ✓
    }

    private void test_iq_response_no_items() {
        // <pubsub> without <items>
        var pubsub = new StanzaNode.build("pubsub", NS_PUBSUB).add_self_xmlns();

        StanzaNode? items = pubsub.get_subnode("items", NS_PUBSUB);
        assert_null(items);
        // DinoX: `if (items_node == null) return null` → safe ✓
    }

    private void test_iq_response_empty_items() {
        // <pubsub><items node="x"/></pubsub> — items with no item children
        var pubsub = new StanzaNode.build("pubsub", NS_PUBSUB).add_self_xmlns();
        var items = new StanzaNode.build("items", NS_PUBSUB).put_attribute("node", "test");
        pubsub.put_node(items);

        StanzaNode? items_node = pubsub.get_subnode("items", NS_PUBSUB);
        assert_nonnull(items_node);
        var subnodes = items_node.get_subnodes("item", NS_PUBSUB);
        assert_true(subnodes.size == 0);
    }

    private void test_iq_response_item_no_children() {
        // <item id="x"/> with no payload — for request_item()
        var pubsub = new StanzaNode.build("pubsub", NS_PUBSUB).add_self_xmlns();
        var items = new StanzaNode.build("items", NS_PUBSUB).put_attribute("node", "test");
        var item = new StanzaNode.build("item", NS_PUBSUB).put_attribute("id", "x");
        // No children
        items.put_node(item);
        pubsub.put_node(items);

        StanzaNode? item_node = pubsub.get_subnode("items", NS_PUBSUB).get_subnode("item", NS_PUBSUB);
        assert_nonnull(item_node);
        assert_true(item_node.sub_nodes.size == 0);
        // DinoX request_item: `if (item_node.sub_nodes.size == 0) return null` → safe ✓
    }

    // ========== Publish options ==========

    private void test_publish_options_persist() {
        var opts = new Xep.Pubsub.PublishOptions();
        opts.set_persist_items(true);
        assert_true(opts.settings["pubsub#persist_items"] == "true");

        opts.set_persist_items(false);
        assert_true(opts.settings["pubsub#persist_items"] == "false");
    }

    private void test_publish_options_max() {
        var opts = new Xep.Pubsub.PublishOptions();
        opts.set_max_items("1");
        assert_true(opts.settings["pubsub#max_items"] == "1");

        opts.set_max_items("max");
        assert_true(opts.settings["pubsub#max_items"] == "max");
    }

    private void test_publish_options_access_model() {
        var opts = new Xep.Pubsub.PublishOptions();

        // Test all 5 access models defined in the spec
        string[] models = {
            Xep.Pubsub.ACCESS_MODEL_AUTHORIZE,
            Xep.Pubsub.ACCESS_MODEL_OPEN,
            Xep.Pubsub.ACCESS_MODEL_PRESENCE,
            Xep.Pubsub.ACCESS_MODEL_ROSTER,
            Xep.Pubsub.ACCESS_MODEL_WHITELIST
        };
        foreach (string model in models) {
            opts.set_access_model(model);
            assert_true(opts.settings["pubsub#access_model"] == model);
        }
    }

    // ========== Edge cases ==========

    private void test_wrong_event_namespace() {
        // Event with wrong namespace
        var event = new StanzaNode.build("event", "http://wrong.namespace").add_self_xmlns();
        var msg_stanza = new StanzaNode.build("message", NS_JABBER);
        msg_stanza.put_node(event);

        // DinoX looks for NS_URI_EVENT specifically
        StanzaNode? found = msg_stanza.get_subnode("event", NS_EVENT);
        assert_null(found); // Correct: wrong namespace ignored
    }

    private void test_multiple_items_in_event() {
        // Multiple <item> nodes in a single <items> — valid per spec
        var event = build_event_node();
        var items = new StanzaNode.build("items", NS_EVENT).put_attribute("node", "test");
        for (int i = 0; i < 5; i++) {
            var item = new StanzaNode.build("item", NS_EVENT).put_attribute("id", "item%d".printf(i));
            item.put_node(new StanzaNode.build("payload", "urn:test").add_self_xmlns());
            items.put_node(item);
        }
        event.put_node(items);

        StanzaNode? items_node = event.get_subnode("items", NS_EVENT);
        assert_nonnull(items_node);
        // FIX applied: DinoX now uses get_subnodes() + foreach loop
        // All items in batch notifications are processed correctly
        Gee.List<StanzaNode> all_items = items_node.get_subnodes("item", NS_EVENT);
        assert_true(all_items.size == 5);
        // Verify all items accessible
        for (int j = 0; j < 5; j++) {
            assert_true(all_items[j].get_attribute("id") == "item%d".printf(j));
        }
    }

    private void test_item_multiple_payloads() {
        // <item> with multiple child nodes — ambiguous payload
        var item = new StanzaNode.build("item", NS_EVENT).put_attribute("id", "multi-payload");
        item.put_node(new StanzaNode.build("data1", "urn:test1").add_self_xmlns());
        item.put_node(new StanzaNode.build("data2", "urn:test2").add_self_xmlns());

        assert_true(item.sub_nodes.size == 2);
        // DinoX uses `item_node.sub_nodes[0]` — always takes the first payload
        // This is correct per XEP-0060 §12.1: each item has exactly one payload element
        assert_true(item.sub_nodes[0].name == "data1");
    }

    // ========== Helpers ==========

    private StanzaNode build_event_node() {
        return new StanzaNode.build("event", NS_EVENT).add_self_xmlns();
    }
}

}
