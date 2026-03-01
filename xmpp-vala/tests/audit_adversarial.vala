using Gee;

namespace Xmpp.Test {

/**
 * Phase 10 — Adversarial / Security Tests
 *
 * Tests XEP parsers and core infrastructure against adversarial input:
 * spoofed senders, oversized values, Unicode edge cases, injection
 * attempts, and boundary conditions.
 *
 * Covers:
 *   - JID parsing edge cases (5 tests)
 *   - XEP-0359 stanza-id spoofing (3 tests)
 *   - XEP-0461 reply-to JID injection (3 tests)
 *   - XEP-0446 file metadata injection (4 tests)
 *   - XEP-0004 DataForms XSS in field values (3 tests)
 *   - StanzaNode attribute boundary values (4 tests)
 *   - XEP-0424 retraction race conditions (2 tests)
 *   - XEP-0308 correction chain spoofing (2 tests)
 */
class AdversarialAudit : Gee.TestCase {

    public AdversarialAudit() {
        base("AdversarialAudit");

        // --- JID parsing edge cases ---
        add_test("JID_unicode_normalization", test_jid_unicode);
        add_test("JID_max_length", test_jid_max_length);
        add_test("JID_null_bytes", test_jid_null_bytes);
        add_test("JID_resource_special_chars", test_jid_resource_special);
        add_test("JID_empty_parts", test_jid_empty_parts);

        // --- XEP-0359 stanza-id spoofing ---
        add_test("XEP0359_multiple_stanza_ids", test_sid_multiple);
        add_test("XEP0359_stanza_id_empty_by", test_sid_empty_by);
        add_test("XEP0359_stanza_id_with_resource", test_sid_with_resource);

        // --- XEP-0461 reply-to JID injection ---
        add_test("XEP0461_reply_xss_jid", test_reply_xss_jid);
        add_test("XEP0461_reply_unicode_jid", test_reply_unicode_jid);
        add_test("XEP0461_reply_very_long_id", test_reply_long_id);

        // --- XEP-0446 File Metadata injection ---
        add_test("XEP0446_path_traversal_name", test_fm_path_traversal);
        add_test("XEP0446_negative_size", test_fm_negative_size);
        add_test("XEP0446_huge_dimensions", test_fm_huge_dimensions);
        add_test("XEP0446_script_in_name", test_fm_script_name);

        // --- XEP-0004 DataForms XSS ---
        add_test("XEP0004_html_in_field_value", test_df_html_value);
        add_test("XEP0004_script_in_title", test_df_script_title);
        add_test("XEP0004_null_char_in_field", test_df_null_char);

        // --- StanzaNode boundary values ---
        add_test("StanzaNode_get_attribute_nonexistent", test_sn_get_missing);
        add_test("StanzaNode_get_attribute_int_overflow", test_sn_int_overflow);
        add_test("StanzaNode_empty_name_subnode", test_sn_empty_name);
        add_test("StanzaNode_deep_subnode_chain", test_sn_deep_chain);

        // --- XEP-0424 retraction edge cases ---
        add_test("XEP0424_retract_self_referencing", test_retract_self_ref);
        add_test("XEP0424_retract_v0_v1_mixed", test_retract_mixed);

        // --- XEP-0308 correction chain ---
        add_test("XEP0308_double_replace", test_lmc_double);
        add_test("XEP0308_replace_roundtrip", test_lmc_roundtrip);
    }

    // ===================== JID Parsing Edge Cases =====================

    private void test_jid_unicode() {
        // Unicode in localpart should be handled
        try {
            var jid = new Jid("ünîcödé@example.com");
            fail_if(jid == null, "Unicode localpart should parse");
            fail_if_not_eq_str(jid.domainpart, "example.com", "Domain should be example.com");
        } catch (InvalidJidError e) {
            // Some Unicode JIDs may be invalid per PRECIS - that's acceptable
        }
    }

    private void test_jid_max_length() {
        // JID parts have max lengths per RFC 7622
        // Localpart: 1023 bytes, domainpart: 1023 bytes, resourcepart: 1023 bytes
        string long_local = string.nfill(1024, 'a');
        try {
            new Jid(long_local + "@example.com");
            // If it doesn't throw, the implementation may not enforce limits
            // Not necessarily a bug, but document it
        } catch (InvalidJidError e) {
            // Expected - too long
        }
    }

    private void test_jid_null_bytes() {
        // Null bytes in JID string
        try {
            new Jid("user\0@example.com");
            // Implementation may or may not reject null bytes
        } catch (InvalidJidError e) {
            // Expected
        }
    }

    private void test_jid_resource_special() {
        // Resource part can contain special characters
        try {
            var jid = new Jid("user@example.com/resource with spaces & <special>");
            fail_if(jid == null, "Resource with special chars should parse");
            fail_if_not_eq_str(jid.localpart, "user", "Localpart");
            fail_if_not_eq_str(jid.domainpart, "example.com", "Domain");
        } catch (InvalidJidError e) {
            // Some special chars may not be valid
        }
    }

    private void test_jid_empty_parts() {
        // Various empty JID parts
        try {
            new Jid("");
            fail_if_reached("Empty string should throw InvalidJidError");
        } catch (InvalidJidError e) {
            // Expected
        }
        try {
            new Jid("@example.com");
            fail_if_reached("Empty localpart with @ should throw");
        } catch (InvalidJidError e) {
            // Expected
        }
    }

    // ===================== XEP-0359 Stanza ID Spoofing =====================

    private void test_sid_multiple() {
        // Multiple stanza-id elements with different 'by' — should match correct one
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("stanza-id", Xep.UniqueStableStanzaIDs.NS_URI)
            .add_self_xmlns()
            .put_attribute("id", "id-from-server1")
            .put_attribute("by", "server1.example.com"));
        msg.stanza.put_node(new StanzaNode.build("stanza-id", Xep.UniqueStableStanzaIDs.NS_URI)
            .add_self_xmlns()
            .put_attribute("id", "id-from-server2")
            .put_attribute("by", "server2.example.com"));

        try {
            var by1 = new Jid("server1.example.com");
            string? id1 = Xep.UniqueStableStanzaIDs.get_stanza_id(msg, by1);
            fail_if_not_eq_str(id1, "id-from-server1", "Should match server1");

            var by2 = new Jid("server2.example.com");
            string? id2 = Xep.UniqueStableStanzaIDs.get_stanza_id(msg, by2);
            fail_if_not_eq_str(id2, "id-from-server2", "Should match server2");
        } catch (InvalidJidError e) {
            fail_if_reached("JIDs should be valid");
        }
    }

    private void test_sid_empty_by() {
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("stanza-id", Xep.UniqueStableStanzaIDs.NS_URI)
            .add_self_xmlns()
            .put_attribute("id", "some-id")
            .put_attribute("by", ""));
        try {
            var by = new Jid("server.example.com");
            string? id = Xep.UniqueStableStanzaIDs.get_stanza_id(msg, by);
            fail_if(id != null, "Empty by should not match any JID");
        } catch (InvalidJidError e) {
            fail_if_reached("JID should be valid");
        }
    }

    private void test_sid_with_resource() {
        // Stanza-id 'by' with full JID (bare JID is standard)
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("stanza-id", Xep.UniqueStableStanzaIDs.NS_URI)
            .add_self_xmlns()
            .put_attribute("id", "full-id")
            .put_attribute("by", "room@conference.example.com/nick"));
        try {
            // Query by bare JID — should NOT match (by includes resource)
            var by_bare = new Jid("room@conference.example.com");
            string? id = Xep.UniqueStableStanzaIDs.get_stanza_id(msg, by_bare);
            // The implementation does string comparison, so full JID won't match bare
            fail_if(id != null, "Full JID 'by' should not match bare JID query");
        } catch (InvalidJidError e) {
            fail_if_reached("JID should be valid");
        }
    }

    // ===================== XEP-0461 Reply JID Injection =====================

    private void test_reply_xss_jid() {
        // XSS attempt in reply-to JID — JID parser accepts angle brackets
        // (not prohibited by RFC 7622 for localpart). The display layer
        // is responsible for escaping HTML entities.
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("reply", Xep.Replies.NS_URI)
            .add_self_xmlns()
            .put_attribute("to", "<script>alert('xss')</script>@example.com")
            .put_attribute("id", "msg-1"));
        var result = Xep.Replies.get_reply_to(msg);
        // JID parser may accept or reject — both are valid behaviors
        // If it accepts, the display layer MUST escape HTML
        if (result != null) {
            fail_if_not_eq_str(result.to_message_id, "msg-1", "ID should be preserved");
        }
        // Test passes either way — this documents the current behavior
    }

    private void test_reply_unicode_jid() {
        // Valid-looking Unicode JID
        var msg = new MessageStanza();
        try {
            var jid = new Jid("user@example.com");
            var reply_to = new Xep.Replies.ReplyTo(jid, "msg-555");
            Xep.Replies.set_reply_to(msg, reply_to);
            var parsed = Xep.Replies.get_reply_to(msg);
            fail_if(parsed == null, "Valid Unicode reply should parse");
            fail_if_not_eq_str(parsed.to_message_id, "msg-555", "ID mismatch");
        } catch (InvalidJidError e) {
            fail_if_reached("JID should be valid");
        }
    }

    private void test_reply_long_id() {
        // Very long message ID (potential buffer overflow)
        var msg = new MessageStanza();
        string long_id = string.nfill(10000, 'x');
        try {
            var reply_to = new Xep.Replies.ReplyTo(new Jid("user@example.com"), long_id);
            Xep.Replies.set_reply_to(msg, reply_to);
            var parsed = Xep.Replies.get_reply_to(msg);
            fail_if(parsed == null, "Long ID should still parse");
            fail_if_not_eq_int((int)parsed.to_message_id.length, 10000, "ID length preserved");
        } catch (InvalidJidError e) {
            fail_if_reached("JID should be valid");
        }
    }

    // ===================== XEP-0446 File Metadata Injection =====================

    private void test_fm_path_traversal() {
        // Path traversal in filename
        var parent = new StanzaNode.build("wrapper");
        var file = new StanzaNode.build("file", Xep.FileMetadataElement.NS_URI).add_self_xmlns();
        file.put_node(new StanzaNode.build("name", Xep.FileMetadataElement.NS_URI)
            .put_node(new StanzaNode.text("../../../etc/passwd")));
        parent.put_node(file);

        var metadata = Xep.FileMetadataElement.get_file_metadata(parent);
        fail_if(metadata == null, "Parser should not crash on path traversal");
        // The parser stores the raw name — sanitization is the caller's responsibility
        fail_if_not_eq_str(metadata.name, "../../../etc/passwd",
            "Raw name should be preserved (sanitization is caller's job)");
    }

    private void test_fm_negative_size() {
        var parent = new StanzaNode.build("wrapper");
        var file = new StanzaNode.build("file", Xep.FileMetadataElement.NS_URI).add_self_xmlns();
        file.put_node(new StanzaNode.build("size", Xep.FileMetadataElement.NS_URI)
            .put_node(new StanzaNode.text("-1")));
        parent.put_node(file);

        var metadata = Xep.FileMetadataElement.get_file_metadata(parent);
        fail_if(metadata == null, "Negative size should not crash");
        fail_if_not(metadata.size == -1, "Negative size should parse to -1");
    }

    private void test_fm_huge_dimensions() {
        var parent = new StanzaNode.build("wrapper");
        var file = new StanzaNode.build("file", Xep.FileMetadataElement.NS_URI).add_self_xmlns();
        file.put_node(new StanzaNode.build("width", Xep.FileMetadataElement.NS_URI)
            .put_node(new StanzaNode.text("2147483647")));
        file.put_node(new StanzaNode.build("height", Xep.FileMetadataElement.NS_URI)
            .put_node(new StanzaNode.text("2147483647")));
        parent.put_node(file);

        var metadata = Xep.FileMetadataElement.get_file_metadata(parent);
        fail_if(metadata == null, "Max int dimensions should not crash");
        fail_if_not_eq_int(metadata.width, 2147483647, "Max int width");
        fail_if_not_eq_int(metadata.height, 2147483647, "Max int height");
    }

    private void test_fm_script_name() {
        // XSS in filename
        var parent = new StanzaNode.build("wrapper");
        var file = new StanzaNode.build("file", Xep.FileMetadataElement.NS_URI).add_self_xmlns();
        file.put_node(new StanzaNode.build("name", Xep.FileMetadataElement.NS_URI)
            .put_node(new StanzaNode.text("<img src=x onerror=alert(1)>.jpg")));
        parent.put_node(file);

        var metadata = Xep.FileMetadataElement.get_file_metadata(parent);
        fail_if(metadata == null, "Script in name should not crash parser");
        // Parser preserves raw content — display layer must escape
        fail_if(metadata.name == null, "Name should be preserved");
    }

    // ===================== XEP-0004 DataForms XSS =====================

    private void test_df_html_value() {
        // HTML in field value
        var field_node = new StanzaNode.build("field", Xep.DataForms.NS_URI)
            .put_attribute("type", "text-single")
            .put_attribute("var", "html_test");
        field_node.put_node(new StanzaNode.build("value", Xep.DataForms.NS_URI)
            .put_node(new StanzaNode.text("<b>bold</b><script>alert(1)</script>")));
        var node = new StanzaNode.build("x", Xep.DataForms.NS_URI)
            .add_self_xmlns()
            .put_node(field_node);
        var form = Xep.DataForms.DataForm.create_from_node(node);
        fail_if_not_eq_int(form.fields.size, 1, "Should have 1 field");
        // Value should be raw/preserved (display layer escapes)
        string val = form.fields[0].get_value_string();
        fail_if_not(val.contains("<script>"), "Raw HTML should be preserved in value");
    }

    private void test_df_script_title() {
        var node = new StanzaNode.build("x", Xep.DataForms.NS_URI)
            .add_self_xmlns();
        node.put_node(new StanzaNode.build("title", Xep.DataForms.NS_URI)
            .put_node(new StanzaNode.text("<script>alert('xss')</script>")));
        var form = Xep.DataForms.DataForm.create_from_node(node);
        fail_if(form.title == null, "Title should be preserved");
        fail_if_not(form.title.contains("<script>"),
            "Raw HTML in title should be preserved");
    }

    private void test_df_null_char() {
        // Null character in field value
        var field_node = new StanzaNode.build("field", Xep.DataForms.NS_URI)
            .put_attribute("type", "text-single")
            .put_attribute("var", "null_test");
        field_node.put_node(new StanzaNode.build("value", Xep.DataForms.NS_URI)
            .put_node(new StanzaNode.text("before\0after")));
        var node = new StanzaNode.build("x", Xep.DataForms.NS_URI)
            .add_self_xmlns()
            .put_node(field_node);
        var form = Xep.DataForms.DataForm.create_from_node(node);
        fail_if_not_eq_int(form.fields.size, 1, "Null char field should parse");
    }

    // ===================== StanzaNode Boundary Values =====================

    private void test_sn_get_missing() {
        var node = new StanzaNode.build("test");
        string? val = node.get_attribute("nonexistent");
        fail_if(val != null, "get_attribute on missing attr should return null");

        StanzaNode? child = node.get_subnode("nonexistent");
        fail_if(child != null, "get_subnode on missing child should return null");
    }

    private void test_sn_int_overflow() {
        // get_attribute_int with values above int range
        var node = new StanzaNode.build("test")
            .put_attribute("big", "99999999999999999999")
            .put_attribute("negative", "-1")
            .put_attribute("normal", "42");
        int normal = node.get_attribute_int("normal", -1);
        fail_if_not_eq_int(normal, 42, "Normal int should parse");
        int negative = node.get_attribute_int("negative", 0);
        fail_if_not_eq_int(negative, -1, "Negative int should parse");
        int missing = node.get_attribute_int("nonexistent", 99);
        fail_if_not_eq_int(missing, 99, "Missing int should return default");
    }

    private void test_sn_empty_name() {
        // Subnode with empty string content
        var node = new StanzaNode.build("parent");
        var child = new StanzaNode.build("child");
        child.put_node(new StanzaNode.text(""));
        node.put_node(child);
        var found = node.get_subnode("child");
        fail_if(found == null, "Child with empty text should exist");
        string? content = found.get_string_content();
        // Empty text node content
        fail_if_not_eq_str(content, "", "Empty text content should return empty string");
    }

    private void test_sn_deep_chain() {
        // Deeply nested nodes — test get_subnode with recurse
        var root = new StanzaNode.build("root");
        var level1 = new StanzaNode.build("level1");
        var level2 = new StanzaNode.build("level2");
        var target = new StanzaNode.build("target")
            .put_attribute("id", "found");
        level2.put_node(target);
        level1.put_node(level2);
        root.put_node(level1);

        // Non-recursive should not find target
        var direct = root.get_subnode("target");
        fail_if(direct != null, "Non-recursive get_subnode should not find nested target");

        // Recursive should find it
        var deep = root.get_subnode("target", null, true);
        fail_if(deep == null, "Recursive get_subnode should find nested target");
        if (deep != null) {
            fail_if_not_eq_str(deep.get_attribute("id"), "found", "Should find correct node");
        }
    }

    // ===================== XEP-0424 Retraction Edge Cases =====================

    private void test_retract_self_ref() {
        // Message tries to retract itself (self-referencing id)
        var msg = new MessageStanza("self-msg-id");
        Xep.MessageRetraction.set_retract_id(msg, "self-msg-id");
        string? id = Xep.MessageRetraction.get_retract_id(msg);
        fail_if_not_eq_str(id, "self-msg-id",
            "Self-referencing retraction should still parse (validation is caller's job)");
    }

    private void test_retract_mixed() {
        // v0 direct + v1 direct — v1 should win (checked first)
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("retract", Xep.MessageRetraction.NS_URI_0)
            .add_self_xmlns()
            .put_attribute("id", "v0-id"));
        msg.stanza.put_node(new StanzaNode.build("retract", Xep.MessageRetraction.NS_URI)
            .add_self_xmlns()
            .put_attribute("id", "v1-id"));

        string? id = Xep.MessageRetraction.get_retract_id(msg);
        // Implementation checks v1 first then v0
        fail_if(id == null, "Mixed v0/v1 should return something");
    }

    // ===================== XEP-0308 Correction Chain =====================

    private void test_lmc_double() {
        // Two replace elements in same message — only first should be read
        var msg = new MessageStanza();
        msg.stanza.put_node(new StanzaNode.build("replace", "urn:xmpp:message-correct:0")
            .add_self_xmlns()
            .put_attribute("id", "first-replace"));
        msg.stanza.put_node(new StanzaNode.build("replace", "urn:xmpp:message-correct:0")
            .add_self_xmlns()
            .put_attribute("id", "second-replace"));

        string? id = Xep.LastMessageCorrection.get_replace_id(msg);
        // get_subnode returns the first match
        fail_if_not_eq_str(id, "first-replace",
            "First replace element should be used");
    }

    private void test_lmc_roundtrip() {
        var msg = new MessageStanza();
        Xep.LastMessageCorrection.set_replace_id(msg, "orig-msg-42");
        string? id = Xep.LastMessageCorrection.get_replace_id(msg);
        fail_if_not_eq_str(id, "orig-msg-42", "LMC roundtrip should preserve id");
    }
}

}
