using Gee;

namespace Xmpp.Test {

/**
 * Security Audit: XEP stanza roundtrip tests
 *
 * Tests set→get roundtrips for XEP modules that process untrusted
 * incoming stanzas. Verifies that data survives a full cycle through
 * the XML builder and parser.
 *
 * Covers:
 *   - XEP-0424 Message Retraction: set/get retract_id (v0, v1, fastening)
 *   - XEP-0380 Explicit Encryption: set/get encryption tag
 *   - XEP-0359 Unique Stable Stanza IDs: set/get origin_id, stanza_id
 */
class XepRoundtripAudit : Gee.TestCase {

    public XepRoundtripAudit() {
        base("XepRoundtripAudit");

        // --- XEP-0424 Message Retraction ---
        add_test("XEP0424_retract_v1_roundtrip", test_retract_v1_roundtrip);
        add_test("XEP0424_retract_direct_v1", test_retract_direct_v1);
        add_test("XEP0424_retract_direct_v0", test_retract_direct_v0);
        add_test("XEP0424_retract_no_retraction", test_retract_none);
        add_test("XEP0424_retract_missing_id", test_retract_missing_id);

        // --- XEP-0380 Explicit Encryption ---
        add_test("XEP0380_encryption_tag_roundtrip", test_eme_roundtrip);
        add_test("XEP0380_encryption_tag_with_name", test_eme_with_name);
        add_test("XEP0380_encryption_tag_missing", test_eme_missing);

        // --- XEP-0359 Unique Stable Stanza IDs ---
        add_test("XEP0359_origin_id_roundtrip", test_origin_id_roundtrip);
        add_test("XEP0359_origin_id_missing", test_origin_id_missing);
        add_test("XEP0359_stanza_id_roundtrip", test_stanza_id_roundtrip);
        add_test("XEP0359_stanza_id_wrong_by", test_stanza_id_wrong_by);
    }

    // ===================== XEP-0424 Message Retraction =====================

    private void test_retract_v1_roundtrip() {
        var msg = new MessageStanza();
        Xep.MessageRetraction.set_retract_id(msg, "msg-123");
        string? id = Xep.MessageRetraction.get_retract_id(msg);
        fail_if_not_eq_str(id, "msg-123",
            "Retraction v1 roundtrip should preserve message ID");
    }

    private void test_retract_direct_v1() {
        // Build a stanza with direct <retract> child (not fastened)
        var msg = new MessageStanza();
        var retract = new StanzaNode.build("retract", Xep.MessageRetraction.NS_URI)
            .add_self_xmlns()
            .put_attribute("id", "direct-v1-id");
        msg.stanza.put_node(retract);

        string? id = Xep.MessageRetraction.get_retract_id(msg);
        fail_if_not_eq_str(id, "direct-v1-id",
            "Direct v1 retract should return id");
    }

    private void test_retract_direct_v0() {
        // Build a stanza with direct <retract> child in v0 namespace
        var msg = new MessageStanza();
        var retract = new StanzaNode.build("retract", Xep.MessageRetraction.NS_URI_0)
            .add_self_xmlns()
            .put_attribute("id", "direct-v0-id");
        msg.stanza.put_node(retract);

        string? id = Xep.MessageRetraction.get_retract_id(msg);
        fail_if_not_eq_str(id, "direct-v0-id",
            "Direct v0 retract should return id");
    }

    private void test_retract_none() {
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("body").put_node(
            new StanzaNode.text("Hello")));
        string? id = Xep.MessageRetraction.get_retract_id(msg);
        fail_if(id != null, "Message without retraction should return null");
    }

    private void test_retract_missing_id() {
        // Retract element present but no id attribute
        var msg = new MessageStanza();
        var retract = new StanzaNode.build("retract", Xep.MessageRetraction.NS_URI)
            .add_self_xmlns();
        // No id attribute set
        msg.stanza.put_node(retract);

        string? id = Xep.MessageRetraction.get_retract_id(msg);
        fail_if(id != null, "Retract without id attribute should return null");
    }

    // ===================== XEP-0380 Explicit Encryption =====================

    private void test_eme_roundtrip() {
        var msg = new MessageStanza();
        Xep.ExplicitEncryption.add_encryption_tag_to_message(
            msg, "eu.siacs.conversations.axolotl");
        string? ns = Xep.ExplicitEncryption.get_encryption_tag(msg);
        fail_if_not_eq_str(ns, "eu.siacs.conversations.axolotl",
            "Encryption tag namespace should roundtrip");
    }

    private void test_eme_with_name() {
        var msg = new MessageStanza();
        Xep.ExplicitEncryption.add_encryption_tag_to_message(
            msg, "urn:xmpp:omemo:2", "OMEMO");
        string? ns = Xep.ExplicitEncryption.get_encryption_tag(msg);
        fail_if_not_eq_str(ns, "urn:xmpp:omemo:2",
            "Encryption tag should return namespace even when name is set");
    }

    private void test_eme_missing() {
        var msg = new MessageStanza();
        string? ns = Xep.ExplicitEncryption.get_encryption_tag(msg);
        fail_if(ns != null, "Message without encryption tag should return null");
    }

    // ===================== XEP-0359 Unique Stable Stanza IDs =====================

    private void test_origin_id_roundtrip() {
        var msg = new MessageStanza();
        Xep.UniqueStableStanzaIDs.set_origin_id(msg, "origin-abc-123");
        string? id = Xep.UniqueStableStanzaIDs.get_origin_id(msg);
        fail_if_not_eq_str(id, "origin-abc-123",
            "Origin ID should roundtrip through set/get");
    }

    private void test_origin_id_missing() {
        var msg = new MessageStanza();
        string? id = Xep.UniqueStableStanzaIDs.get_origin_id(msg);
        fail_if(id != null, "Message without origin-id should return null");
    }

    private void test_stanza_id_roundtrip() {
        var msg = new MessageStanza();
        // Build stanza-id node manually (there's no set_stanza_id in the module)
        var node = new StanzaNode.build("stanza-id", Xep.UniqueStableStanzaIDs.NS_URI)
            .add_self_xmlns()
            .put_attribute("id", "server-id-456")
            .put_attribute("by", "room@conference.example.com");
        msg.stanza.put_node(node);

        Jid by;
        try {
            by = new Jid("room@conference.example.com");
        } catch (InvalidJidError e) {
            fail_if_reached(@"JID parse failed: $(e.message)");
            return;
        }
        string? id = Xep.UniqueStableStanzaIDs.get_stanza_id(msg, by);
        fail_if_not_eq_str(id, "server-id-456",
            "Stanza ID should be found when 'by' matches");
    }

    private void test_stanza_id_wrong_by() {
        var msg = new MessageStanza();
        var node = new StanzaNode.build("stanza-id", Xep.UniqueStableStanzaIDs.NS_URI)
            .add_self_xmlns()
            .put_attribute("id", "server-id-789")
            .put_attribute("by", "room@conference.example.com");
        msg.stanza.put_node(node);

        Jid wrong_by;
        try {
            wrong_by = new Jid("other@conference.example.com");
        } catch (InvalidJidError e) {
            fail_if_reached(@"JID parse failed: $(e.message)");
            return;
        }
        string? id = Xep.UniqueStableStanzaIDs.get_stanza_id(msg, wrong_by);
        fail_if(id != null, "Stanza ID should return null when 'by' doesn't match");
    }
}

}
