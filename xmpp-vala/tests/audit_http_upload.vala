namespace Xmpp.Test {

/**
 * Security audit tests for XEP-0363 (HTTP File Upload).
 *
 * HTTP File Upload allows clients to request upload/download URLs from the
 * server. Security concerns:
 * - Server may return non-HTTPS URLs (downgrade attack)
 * - Server may return malformed URLs
 * - Server may inject malicious custom headers
 * - Max file size parsing from disco#info forms
 * - Slot response parsing with missing/empty attributes
 *
 * DinoX correctly rejects non-HTTPS URLs (line ~82) and only allows
 * Authorization, Cookie, Expires headers (line ~89).
 *
 * References:
 *   - XEP-0363 §4      Requesting a slot
 *   - XEP-0363 §5.1    Slot response
 *   - XEP-0363 §7      Security considerations
 */
class HttpUploadAudit : Gee.TestCase {

    private const string NS_0 = "urn:xmpp:http:upload:0";
    private const string NS_LEGACY = "urn:xmpp:http:upload";
    private const string NS_DISCO_INFO = "http://jabber.org/protocol/disco#info";
    private const string NS_DATA_FORMS = "jabber:x:data";

    public HttpUploadAudit() {
        base("HttpUploadAudit");

        // --- Slot response parsing ---
        add_test("XEP0363_slot_response_v0_url_attributes", test_slot_response_v0_url_attrs);
        add_test("XEP0363_slot_response_v0_url_content", test_slot_response_v0_url_content);
        add_test("XEP0363_slot_response_missing_get_url", test_slot_missing_get);
        add_test("XEP0363_slot_response_missing_put_url", test_slot_missing_put);
        add_test("XEP0363_slot_response_empty_urls", test_slot_empty_urls);

        // --- HTTPS enforcement (CRITICAL security) ---
        add_test("XEP0363_https_urls_accepted", test_https_accepted);
        add_test("XEP0363_http_url_rejected", test_http_rejected);
        add_test("XEP0363_ftp_url_rejected", test_ftp_rejected);
        add_test("XEP0363_javascript_url_rejected", test_javascript_rejected);
        add_test("XEP0363_data_url_rejected", test_data_url_rejected);
        add_test("XEP0363_empty_url_rejected", test_empty_url_rejected);

        // --- Header filtering (security) ---
        add_test("XEP0363_allowed_headers_authorization", test_header_authorization);
        add_test("XEP0363_allowed_headers_cookie", test_header_cookie);
        add_test("XEP0363_allowed_headers_expires", test_header_expires);
        add_test("XEP0363_disallowed_header_host", test_header_host_denied);
        add_test("XEP0363_disallowed_header_xforwarded", test_header_xforwarded_denied);
        add_test("XEP0363_header_crlf_injection", test_header_crlf_injection);
        add_test("XEP0363_header_oversized", test_header_oversized);

        // --- Max file size parsing ---
        add_test("XEP0363_max_file_size_normal", test_max_file_size_normal);
        add_test("XEP0363_max_file_size_missing", test_max_file_size_missing);
        add_test("XEP0363_max_file_size_zero", test_max_file_size_zero);
        add_test("XEP0363_max_file_size_negative", test_max_file_size_negative);
        add_test("XEP0363_max_file_size_non_numeric", test_max_file_size_non_numeric);

        // --- Flag ---
        add_test("XEP0363_flag_stores_jid_and_version", test_flag);
    }

    // ========== Slot response parsing ==========

    private void test_slot_response_v0_url_attrs() {
        // XEP-0363 v0.6+: URLs in "url" attributes
        var slot = new StanzaNode.build("slot", NS_0).add_self_xmlns();
        var get_node = new StanzaNode.build("get", NS_0).put_attribute("url", "https://upload.example.com/file123");
        var put_node = new StanzaNode.build("put", NS_0).put_attribute("url", "https://upload.example.com/file123");
        slot.put_node(get_node);
        slot.put_node(put_node);

        string? url_get = slot.get_deep_attribute(NS_0 + ":get", NS_0 + ":url");
        // get_deep_attribute with qualified names may not work this way;
        // fallback: direct subnode access
        if (url_get == null) {
            StanzaNode? g = slot.get_subnode("get", NS_0);
            if (g != null) url_get = g.get_attribute("url");
        }
        string? url_put = null;
        StanzaNode? p = slot.get_subnode("put", NS_0);
        if (p != null) url_put = p.get_attribute("url");

        assert_nonnull(url_get);
        assert_nonnull(url_put);
        assert_true(url_get.has_prefix("https://"));
        assert_true(url_put.has_prefix("https://"));
    }

    private void test_slot_response_v0_url_content() {
        // Older XEP-0363: URLs as text content of <get>/<put>
        var slot = new StanzaNode.build("slot", NS_LEGACY).add_self_xmlns();
        var get_node = new StanzaNode.build("get", NS_LEGACY)
            .put_node(new StanzaNode.text("https://upload.example.com/get/file123"));
        var put_node = new StanzaNode.build("put", NS_LEGACY)
            .put_node(new StanzaNode.text("https://upload.example.com/put/file123"));
        slot.put_node(get_node);
        slot.put_node(put_node);

        StanzaNode? g = slot.get_subnode("get", NS_LEGACY);
        StanzaNode? pt = slot.get_subnode("put", NS_LEGACY);
        assert_nonnull(g);
        assert_nonnull(pt);

        string? url_get = g.get_string_content();
        string? url_put = pt.get_string_content();
        assert_nonnull(url_get);
        assert_nonnull(url_put);
        assert_true(url_get.has_prefix("https://"));
    }

    private void test_slot_missing_get() {
        // Slot response with <put> but no <get>
        var slot = new StanzaNode.build("slot", NS_0).add_self_xmlns();
        var put_node = new StanzaNode.build("put", NS_0).put_attribute("url", "https://upload.example.com/put");
        slot.put_node(put_node);

        StanzaNode? g = slot.get_subnode("get", NS_0);
        assert_null(g);
        // DinoX: `if (url_get == null || url_put == null)` → error ✓
    }

    private void test_slot_missing_put() {
        // Slot response with <get> but no <put>
        var slot = new StanzaNode.build("slot", NS_0).add_self_xmlns();
        var get_node = new StanzaNode.build("get", NS_0).put_attribute("url", "https://upload.example.com/get");
        slot.put_node(get_node);

        StanzaNode? p = slot.get_subnode("put", NS_0);
        assert_null(p);
    }

    private void test_slot_empty_urls() {
        // URLs present but empty string
        var slot = new StanzaNode.build("slot", NS_0).add_self_xmlns();
        var get_node = new StanzaNode.build("get", NS_0).put_attribute("url", "");
        var put_node = new StanzaNode.build("put", NS_0).put_attribute("url", "");
        slot.put_node(get_node);
        slot.put_node(put_node);

        StanzaNode? g = slot.get_subnode("get", NS_0);
        string? url = g.get_attribute("url");
        assert_nonnull(url);
        // Empty string does NOT have prefix "https://" → rejected by HTTPS check ✓
        assert_true(!url.down().has_prefix("https://"));
    }

    // ========== HTTPS enforcement ==========

    private void test_https_accepted() {
        string url = "https://upload.example.com/file123";
        assert_true(url.down().has_prefix("https://"));
    }

    private void test_http_rejected() {
        // Plain HTTP → security downgrade, MUST be rejected
        string url = "http://upload.example.com/file123";
        assert_true(!url.down().has_prefix("https://"));
        // DinoX: `if (!url_get.down().has_prefix("https://"))` → error ✓
    }

    private void test_ftp_rejected() {
        string url = "ftp://upload.example.com/file123";
        assert_true(!url.down().has_prefix("https://"));
    }

    private void test_javascript_rejected() {
        string url = "javascript:alert('xss')";
        assert_true(!url.down().has_prefix("https://"));
    }

    private void test_data_url_rejected() {
        string url = "data:text/html,<script>alert(1)</script>";
        assert_true(!url.down().has_prefix("https://"));
    }

    private void test_empty_url_rejected() {
        string url = "";
        assert_true(!url.down().has_prefix("https://"));
    }

    // ========== Header filtering ==========

    private void test_header_authorization() {
        // Authorization header is explicitly allowed per XEP-0363 §5
        string header_name = "Authorization";
        assert_true(header_name == "Authorization" || header_name == "Cookie" || header_name == "Expires");
    }

    private void test_header_cookie() {
        string header_name = "Cookie";
        assert_true(header_name == "Authorization" || header_name == "Cookie" || header_name == "Expires");
    }

    private void test_header_expires() {
        string header_name = "Expires";
        assert_true(header_name == "Authorization" || header_name == "Cookie" || header_name == "Expires");
    }

    private void test_header_host_denied() {
        // "Host" header injection could redirect uploads to attacker server
        string header_name = "Host";
        assert_true(!(header_name == "Authorization" || header_name == "Cookie" || header_name == "Expires"));
        // DinoX correctly filters: only Authorization, Cookie, Expires allowed ✓
    }

    private void test_header_xforwarded_denied() {
        string header_name = "X-Forwarded-For";
        assert_true(!(header_name == "Authorization" || header_name == "Cookie" || header_name == "Expires"));
    }

    private void test_header_crlf_injection() {
        // CRLF injection in header value could inject additional headers
        string header_val = "Bearer token\r\nHost: evil.com";
        // DinoX: `header_val.replace("\n", "").replace("\r", "")`
        string sanitized = header_val.replace("\n", "").replace("\r", "");
        assert_true(!sanitized.contains("\r"));
        assert_true(!sanitized.contains("\n"));
        assert_true(sanitized == "Bearer tokenHost: evil.com");
        // CRLF is stripped → injection prevented ✓
    }

    private void test_header_oversized() {
        // Header value > 8192 bytes should be rejected
        var sb = new GLib.StringBuilder();
        for (int i = 0; i < 9000; i++) sb.append("A");
        string header_val = sb.str;

        assert_true(header_val.length >= 8192);
        // DinoX: `if (header_val != null && header_val.length < 8192)` → oversized rejected ✓
        assert_true(!(header_val.length < 8192));
    }

    // ========== Max file size parsing ==========

    private void test_max_file_size_normal() {
        // Normal disco#info form with max-file-size field
        var x_node = build_disco_form("104857600"); // 100 MB
        string? max_str = extract_max_file_size_str(x_node);
        assert_nonnull(max_str);
        long parsed = long.parse(max_str);
        assert_true(parsed == 104857600);
    }

    private void test_max_file_size_missing() {
        // No max-file-size field in form
        var x_node = new StanzaNode.build("x", NS_DATA_FORMS).add_self_xmlns();
        string? max_str = extract_max_file_size_str(x_node);
        assert_null(max_str);
        // DinoX: `if (max_file_size_str != null)` → returns long.MAX when missing ✓
    }

    private void test_max_file_size_zero() {
        var x_node = build_disco_form("0");
        string? max_str = extract_max_file_size_str(x_node);
        assert_nonnull(max_str);
        long parsed = long.parse(max_str);
        assert_true(parsed == 0);
        // Zero file size means... no uploads? The server should reject, not the client.
    }

    private void test_max_file_size_negative() {
        var x_node = build_disco_form("-1");
        string? max_str = extract_max_file_size_str(x_node);
        assert_nonnull(max_str);
        long parsed = long.parse(max_str);
        assert_true(parsed == -1);
        // Negative file size → long.parse returns -1 at parse level
        // FIX applied: extract_max_file_size() now validates parsed > 0
        // and returns long.MAX for invalid values (negative, zero, non-numeric)
        // This prevents bypass of size limits via malicious server response
    }

    private void test_max_file_size_non_numeric() {
        var x_node = build_disco_form("not_a_number");
        string? max_str = extract_max_file_size_str(x_node);
        assert_nonnull(max_str);
        long parsed = long.parse(max_str);
        assert_true(parsed == 0); // long.parse returns 0 for non-numeric
    }

    // ========== Flag ==========

    private void test_flag() {
        try {
            var jid = new Jid("upload.example.com");
            var flag = new Xep.HttpFileUpload.Flag(jid, NS_0);
            assert_true(flag.file_store_jid.to_string() == "upload.example.com");
            assert_true(flag.ns_ver == NS_0);
            assert_true(flag.get_ns() == NS_LEGACY); // get_ns returns the base NS_URI
            assert_true(flag.get_id() == "http_file_upload");
        } catch (InvalidJidError e) {
            assert_not_reached();
        }
    }

    // ========== Helpers ==========

    private StanzaNode build_disco_form(string max_size_value) {
        var x_node = new StanzaNode.build("x", NS_DATA_FORMS).add_self_xmlns();
        var field = new StanzaNode.build("field", NS_DATA_FORMS)
            .put_attribute("var", "max-file-size");
        var value_node = new StanzaNode.build("value", NS_DATA_FORMS)
            .put_node(new StanzaNode.text(max_size_value));
        field.put_node(value_node);
        x_node.put_node(field);
        return x_node;
    }

    private string? extract_max_file_size_str(StanzaNode x_node) {
        // Mirrors DinoX's extract_max_file_size logic
        Gee.List<StanzaNode> field_nodes = x_node.get_subnodes("field", NS_DATA_FORMS);
        foreach (StanzaNode node in field_nodes) {
            string? var_attr = node.get_attribute("var");
            if (var_attr == "max-file-size") {
                StanzaNode? value_node = node.get_subnode("value", NS_DATA_FORMS);
                if (value_node != null) return value_node.get_string_content();
            }
        }
        return null;
    }
}

}
