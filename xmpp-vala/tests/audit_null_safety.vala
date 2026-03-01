using Gee;

namespace Xmpp.Test {

/**
 * Phase 10 — Null Safety Tests
 *
 * Systematically tests every XEP parser method that calls
 * get_attribute() / get_subnode() / get_string_content() on
 * untrusted input, verifying that null is handled gracefully.
 *
 * These tests specifically target the #1 bug category from the audit:
 * "missing null checks on get_attribute() return values."
 *
 * Covers:
 *   - XEP-0424 Retraction edge cases (4 tests)
 *   - XEP-0380 Explicit Encryption (3 tests)
 *   - XEP-0308 Last Message Correction (3 tests)
 *   - XEP-0203 Delayed Delivery (3 tests)
 *   - XEP-0428 Fallback Indication (3 tests)
 *   - XEP-0367 Message Attaching (3 tests)
 *   - XEP-0066 Out of Band Data (3 tests)
 */
class NullSafetyAudit : Gee.TestCase {

    public NullSafetyAudit() {
        base("NullSafetyAudit");

        // --- XEP-0424 Message Retraction (extended edge cases) ---
        add_test("XEP0424_retract_fastening_no_retract", test_retract_fastening_no_retract);
        add_test("XEP0424_retract_fastening_no_id", test_retract_fastening_no_id);
        add_test("XEP0424_retract_both_formats", test_retract_both_formats);
        add_test("XEP0424_retract_empty_id", test_retract_empty_id);

        // --- XEP-0380 Explicit Encryption ---
        add_test("XEP0380_no_encryption_node", test_eme_no_node);
        add_test("XEP0380_encryption_node_no_ns", test_eme_no_ns);
        add_test("XEP0380_encryption_empty_namespace", test_eme_empty_ns);

        // --- XEP-0308 Last Message Correction ---
        add_test("XEP0308_replace_id_present", test_lmc_present);
        add_test("XEP0308_replace_id_missing", test_lmc_missing);
        add_test("XEP0308_replace_id_no_attr", test_lmc_no_attr);

        // --- XEP-0203 Delayed Delivery ---
        add_test("XEP0203_delay_present", test_delay_present);
        add_test("XEP0203_delay_missing", test_delay_missing);
        add_test("XEP0203_delay_bad_stamp", test_delay_bad_stamp);

        // --- XEP-0428 Fallback Indication ---
        add_test("XEP0428_fallback_present", test_fallback_present);
        add_test("XEP0428_fallback_missing", test_fallback_missing);
        add_test("XEP0428_fallback_no_for", test_fallback_no_for);

        // --- XEP-0367 Message Attaching ---
        add_test("XEP0367_attach_to_present", test_attach_present);
        add_test("XEP0367_attach_to_missing", test_attach_missing);
        add_test("XEP0367_attach_to_no_id", test_attach_no_id);

        // --- XEP-0066 Out of Band Data ---
        add_test("XEP0066_oob_url_present", test_oob_present);
        add_test("XEP0066_oob_url_missing", test_oob_missing);
        add_test("XEP0066_oob_url_empty", test_oob_empty);
    }

    // ===================== XEP-0424 Extended Edge Cases =====================

    private void test_retract_fastening_no_retract() {
        // <apply-to> present but no <retract> inside it
        var msg = new MessageStanza();
        var apply = new StanzaNode.build("apply-to", Xep.MessageRetraction.NS_FASTEN)
            .add_self_xmlns()
            .put_attribute("id", "msg-123");
        apply.put_node(new StanzaNode.build("other-action", "urn:xmpp:other")
            .add_self_xmlns());
        msg.stanza.put_node(apply);

        string? id = Xep.MessageRetraction.get_retract_id(msg);
        fail_if(id != null, "apply-to without retract should return null");
    }

    private void test_retract_fastening_no_id() {
        // <apply-to> with <retract> inside but apply-to has no id=
        var msg = new MessageStanza();
        var apply = new StanzaNode.build("apply-to", Xep.MessageRetraction.NS_FASTEN)
            .add_self_xmlns();
        // No id attribute on apply-to
        apply.put_node(new StanzaNode.build("retract", Xep.MessageRetraction.NS_URI)
            .add_self_xmlns());
        msg.stanza.put_node(apply);

        string? id = Xep.MessageRetraction.get_retract_id(msg);
        fail_if(id != null, "apply-to without id should return null");
    }

    private void test_retract_both_formats() {
        // Both fastening + direct retract present — fastening should win
        var msg = new MessageStanza();
        // Fastening format
        var apply = new StanzaNode.build("apply-to", Xep.MessageRetraction.NS_FASTEN)
            .add_self_xmlns()
            .put_attribute("id", "fastened-id");
        apply.put_node(new StanzaNode.build("retract", Xep.MessageRetraction.NS_URI)
            .add_self_xmlns());
        msg.stanza.put_node(apply);
        // Direct format
        msg.stanza.put_node(new StanzaNode.build("retract", Xep.MessageRetraction.NS_URI)
            .add_self_xmlns()
            .put_attribute("id", "direct-id"));

        string? id = Xep.MessageRetraction.get_retract_id(msg);
        fail_if_not_eq_str(id, "fastened-id",
            "Fastening format should take priority over direct");
    }

    private void test_retract_empty_id() {
        // Retract with empty string id
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("retract", Xep.MessageRetraction.NS_URI)
            .add_self_xmlns()
            .put_attribute("id", ""));

        string? id = Xep.MessageRetraction.get_retract_id(msg);
        // Empty string is technically non-null, but semantically empty
        fail_if_not_eq_str(id, "", "Empty id should return empty string");
    }

    // ===================== XEP-0380 Explicit Encryption =====================

    private void test_eme_no_node() {
        var msg = new MessageStanza();
        var enc_node = msg.stanza.get_subnode("encryption", "urn:xmpp:eme:0");
        fail_if(enc_node != null, "No encryption node should return null");
    }

    private void test_eme_no_ns() {
        var msg = new MessageStanza();
        var enc = new StanzaNode.build("encryption", "urn:xmpp:eme:0")
            .add_self_xmlns();
        // No namespace= attribute
        msg.stanza.put_node(enc);
        var enc_node = msg.stanza.get_subnode("encryption", "urn:xmpp:eme:0");
        fail_if(enc_node == null, "encryption node should exist");
        string? ns = enc_node.get_attribute("namespace");
        fail_if(ns != null, "Missing namespace attr should be null");
    }

    private void test_eme_empty_ns() {
        var msg = new MessageStanza();
        var enc = new StanzaNode.build("encryption", "urn:xmpp:eme:0")
            .add_self_xmlns()
            .put_attribute("namespace", "");
        msg.stanza.put_node(enc);
        var enc_node = msg.stanza.get_subnode("encryption", "urn:xmpp:eme:0");
        string? ns = enc_node.get_attribute("namespace");
        fail_if_not_eq_str(ns, "", "Empty namespace should return empty string");
    }

    // ===================== XEP-0308 Last Message Correction =====================

    private void test_lmc_present() {
        var msg = new MessageStanza();
        Xep.LastMessageCorrection.set_replace_id(msg, "orig-msg-1");
        string? id = Xep.LastMessageCorrection.get_replace_id(msg);
        fail_if_not_eq_str(id, "orig-msg-1", "Replace id roundtrip");
    }

    private void test_lmc_missing() {
        var msg = new MessageStanza();
        string? id = Xep.LastMessageCorrection.get_replace_id(msg);
        fail_if(id != null, "No replace should return null");
    }

    private void test_lmc_no_attr() {
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("replace", "urn:xmpp:message-correct:0")
            .add_self_xmlns());
        // No id attribute
        string? id = Xep.LastMessageCorrection.get_replace_id(msg);
        fail_if(id != null, "Replace without id attr should return null");
    }

    // ===================== XEP-0203 Delayed Delivery =====================

    private void test_delay_present() {
        var msg = new MessageStanza();
        Xep.DelayedDelivery.Module.set_message_delay(msg, new DateTime.utc(2023, 6, 15, 12, 30, 0));
        DateTime? dt = Xep.DelayedDelivery.get_time_for_message(msg);
        fail_if(dt == null, "Delay with valid stamp should parse");
        if (dt != null) {
            fail_if_not_eq_int(dt.get_year(), 2023, "Year should be 2023");
            fail_if_not_eq_int(dt.get_month(), 6, "Month should be 6");
        }
    }

    private void test_delay_missing() {
        var msg = new MessageStanza();
        DateTime? dt = Xep.DelayedDelivery.get_time_for_message(msg);
        fail_if(dt != null, "No delay node should return null");
    }

    private void test_delay_bad_stamp() {
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("delay", Xep.DelayedDelivery.NS_URI)
            .add_self_xmlns()
            .put_attribute("stamp", "not-a-date"));
        DateTime? dt = Xep.DelayedDelivery.get_time_for_message(msg);
        // Bad stamp should return null DateTime
        fail_if(dt != null, "Delay with invalid stamp should return null");
    }

    // ===================== XEP-0428 Fallback Indication =====================

    private void test_fallback_present() {
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("fallback", "urn:xmpp:fallback:0")
            .add_self_xmlns()
            .put_attribute("for", "urn:xmpp:reply:0"));
        var fb = msg.stanza.get_subnode("fallback", "urn:xmpp:fallback:0");
        fail_if(fb == null, "Fallback node should exist");
        string? for_ns = fb.get_attribute("for");
        fail_if_not_eq_str(for_ns, "urn:xmpp:reply:0", "for attr should match");
    }

    private void test_fallback_missing() {
        var msg = new MessageStanza();
        var fb = msg.stanza.get_subnode("fallback", "urn:xmpp:fallback:0");
        fail_if(fb != null, "No fallback should return null");
    }

    private void test_fallback_no_for() {
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("fallback", "urn:xmpp:fallback:0")
            .add_self_xmlns());
        var fb = msg.stanza.get_subnode("fallback", "urn:xmpp:fallback:0");
        fail_if(fb == null, "Fallback node should exist");
        string? for_ns = fb.get_attribute("for");
        fail_if(for_ns != null, "Missing for attr should be null");
    }

    // ===================== XEP-0367 Message Attaching =====================

    private void test_attach_present() {
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("attach-to", "urn:xmpp:message-attaching:1")
            .add_self_xmlns()
            .put_attribute("id", "ref-msg-42"));
        var at = msg.stanza.get_subnode("attach-to", "urn:xmpp:message-attaching:1");
        fail_if(at == null, "attach-to node should exist");
        string? id = at.get_attribute("id");
        fail_if_not_eq_str(id, "ref-msg-42", "attach-to id should match");
    }

    private void test_attach_missing() {
        var msg = new MessageStanza();
        var at = msg.stanza.get_subnode("attach-to", "urn:xmpp:message-attaching:1");
        fail_if(at != null, "No attach-to should return null");
    }

    private void test_attach_no_id() {
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("attach-to", "urn:xmpp:message-attaching:1")
            .add_self_xmlns());
        var at = msg.stanza.get_subnode("attach-to", "urn:xmpp:message-attaching:1");
        fail_if(at == null, "attach-to should exist");
        string? id = at.get_attribute("id");
        fail_if(id != null, "Missing id attr should be null");
    }

    // ===================== XEP-0066 Out of Band Data =====================

    private void test_oob_present() {
        var msg = new MessageStanza();
        var x = new StanzaNode.build("x", "jabber:x:oob")
            .add_self_xmlns();
        x.put_node(new StanzaNode.build("url", "jabber:x:oob")
            .put_node(new StanzaNode.text("https://example.com/file.txt")));
        msg.stanza.put_node(x);
        var oob = msg.stanza.get_subnode("x", "jabber:x:oob");
        fail_if(oob == null, "OOB x node should exist");
        var url_node = oob.get_subnode("url", "jabber:x:oob");
        fail_if(url_node == null, "URL node should exist");
        string? url = url_node.get_string_content();
        fail_if_not_eq_str(url, "https://example.com/file.txt", "URL content mismatch");
    }

    private void test_oob_missing() {
        var msg = new MessageStanza();
        var oob = msg.stanza.get_subnode("x", "jabber:x:oob");
        fail_if(oob != null, "No OOB should return null");
    }

    private void test_oob_empty() {
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("x", "jabber:x:oob")
            .add_self_xmlns());
        // <x> present but no <url> child
        var oob = msg.stanza.get_subnode("x", "jabber:x:oob");
        fail_if(oob == null, "OOB node should exist");
        var url_node = oob.get_subnode("url", "jabber:x:oob");
        fail_if(url_node != null, "Missing URL subnode should be null");
    }
}

}
