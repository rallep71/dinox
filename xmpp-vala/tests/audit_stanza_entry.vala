using Gee;

namespace Xmpp.Test {

/**
 * Security Audit: StanzaEntry.encoded_val XML entity decode
 *
 * The encoded_val setter on StanzaEntry processes untrusted XML character
 * references (&#xNN;, &#NN;, &amp;, &lt;, &gt;, &apos;, &quot;) from
 * incoming stanzas. Incorrect parsing can lead to XSS if entities are
 * partially decoded, or crashes if substring arithmetic is wrong.
 *
 * Bug #20: encoded_val substring arithmetic is inverted.
 *   In the line: tmp.substring(start+3, start-end-3)
 *   The second parameter is *length*, but `start - end - 3` is always
 *   negative when end > start (which is always true because end is found
 *   after start). This should be `end - start - 3`. The same issue
 *   applies to the decimal branch: `start - end - 2` should be
 *   `end - start - 2`. This causes incorrect parsing of numeric
 *   character references like &#x41; or &#65;.
 *
 * Also tests get_attribute_bool edge cases.
 */
class StanzaEntryAudit : Gee.TestCase {

    public StanzaEntryAudit() {
        base("StanzaEntryAudit");

        // --- encoded_val: named entities ---
        add_test("XEP0115_5_1_amp_entity_decoded", test_amp_entity);
        add_test("XEP0115_5_1_lt_entity_decoded", test_lt_entity);
        add_test("XEP0115_5_1_gt_entity_decoded", test_gt_entity);
        add_test("XEP0115_5_1_apos_entity_decoded", test_apos_entity);
        add_test("XEP0115_5_1_quot_entity_decoded", test_quot_entity);
        add_test("XML_all_named_entities_combined", test_all_named_entities);

        // --- encoded_val: numeric character references ---
        add_test("XML_hex_char_ref_basic", test_hex_char_ref);
        add_test("XML_decimal_char_ref_basic", test_decimal_char_ref);
        add_test("XML_hex_char_ref_unicode", test_hex_char_ref_unicode);
        add_test("XML_numeric_ref_with_trailing_text", test_numeric_ref_trailing);
        add_test("XML_multiple_numeric_refs", test_multiple_numeric_refs);

        // --- encoded_val: malformed / adversarial input ---
        add_test("XML_unclosed_numeric_ref_no_crash", test_unclosed_ref);
        add_test("XML_empty_numeric_ref_no_crash", test_empty_numeric_ref);
        add_test("XML_hash_without_semicolon_no_crash", test_hash_no_semi);

        // --- encoded_val: round-trip ---
        add_test("XML_entity_encode_decode_roundtrip", test_roundtrip);

        // --- get_attribute_bool ---
        add_test("RFC6120_bool_true_string", test_bool_true);
        add_test("RFC6120_bool_one_is_true", test_bool_one);
        add_test("RFC6120_bool_false_string", test_bool_false);
        add_test("RFC6120_bool_zero_is_false", test_bool_zero);
        add_test("RFC6120_bool_missing_returns_default", test_bool_missing);
        add_test("RFC6120_bool_garbage_is_false", test_bool_garbage);
    }

    // Helper: create a StanzaAttribute and set encoded_val, return decoded val
    private string? decode(string encoded) {
        var attr = new StanzaAttribute.build("", "test", "");
        attr.encoded_val = encoded;
        return attr.val;
    }

    // --- Named entities ---

    private void test_amp_entity() {
        // &amp; MUST decode to &
        // Note: &amp; is decoded LAST in the implementation to avoid double-decode
        fail_if_not_eq_str(decode("hello &amp; world"), "hello & world",
            "&amp; should decode to &");
    }

    private void test_lt_entity() {
        fail_if_not_eq_str(decode("a &lt; b"), "a < b",
            "&lt; should decode to <");
    }

    private void test_gt_entity() {
        fail_if_not_eq_str(decode("a &gt; b"), "a > b",
            "&gt; should decode to >");
    }

    private void test_apos_entity() {
        fail_if_not_eq_str(decode("it&apos;s"), "it's",
            "&apos; should decode to '");
    }

    private void test_quot_entity() {
        fail_if_not_eq_str(decode("say &quot;hi&quot;"), "say \"hi\"",
            "&quot; should decode to double-quote");
    }

    private void test_all_named_entities() {
        string input = "&lt;a href=&quot;url&quot;&gt;Tom &amp; Jerry&apos;s&lt;/a&gt;";
        string expected = "<a href=\"url\">Tom & Jerry's</a>";
        fail_if_not_eq_str(decode(input), expected,
            "All five named entities should decode correctly in combination");
    }

    // --- Numeric character references ---
    // Bug #20: substring arithmetic is inverted (start-end-3 should be end-start-3)

    private void test_hex_char_ref() {
        // &#x41; = 'A'
        string? result = decode("&#x41;");
        fail_if_not_eq_str(result, "A",
            "&#x41; (hex) should decode to 'A' (Bug #20: substring arithmetic)");
    }

    private void test_decimal_char_ref() {
        // &#65; = 'A'
        string? result = decode("&#65;");
        fail_if_not_eq_str(result, "A",
            "&#65; (decimal) should decode to 'A' (Bug #20: substring arithmetic)");
    }

    private void test_hex_char_ref_unicode() {
        // &#x263A; = '☺' (U+263A WHITE SMILING FACE)
        string? result = decode("&#x263A;");
        fail_if_not_eq_str(result, "☺",
            "&#x263A; should decode to ☺");
    }

    private void test_numeric_ref_trailing() {
        string? result = decode("&#x48;ello");
        fail_if_not_eq_str(result, "Hello",
            "&#x48;ello should decode to 'Hello'");
    }

    private void test_multiple_numeric_refs() {
        // &#x48;&#x49; = "HI"
        string? result = decode("&#x48;&#x49;");
        fail_if_not_eq_str(result, "HI",
            "Multiple hex refs should decode correctly");
    }

    // --- Malformed input ---

    private void test_unclosed_ref() {
        // &#x41 without closing ; — should not crash
        // The implementation checks end < start and breaks
        string? result = decode("&#x41 no semicolon");
        // Should not crash; exact result depends on implementation
        fail_if(result == null, "Unclosed numeric ref should not return null");
    }

    private void test_empty_numeric_ref() {
        // &#; — empty numeric ref
        string? result = decode("&#;");
        fail_if(result == null, "Empty numeric ref should not crash");
    }

    private void test_hash_no_semi() {
        // &# at end of string with no ;
        string? result = decode("test&#");
        fail_if(result == null, "Trailing &# should not crash");
    }

    // --- Round-trip ---

    private void test_roundtrip() {
        // Setting val directly and reading encoded_val, then setting it back
        var attr = new StanzaAttribute.build("", "test", "Tom & <Jerry> 'quoted' \"string\"");
        string? encoded = attr.encoded_val;
        fail_if(encoded == null, "encoded_val getter should not return null");

        var attr2 = new StanzaAttribute.build("", "test", "");
        attr2.encoded_val = encoded;
        fail_if_not_eq_str(attr2.val, attr.val,
            "Round-trip encode→decode should preserve original string");
    }

    // --- get_attribute_bool ---

    private void test_bool_true() {
        var node = new StanzaNode.build("test", "ns").add_self_xmlns()
            .put_attribute("flag", "true");
        fail_if_not(node.get_attribute_bool("flag", false) == true,
            "'true' should parse as bool true");
    }

    private void test_bool_one() {
        var node = new StanzaNode.build("test", "ns").add_self_xmlns()
            .put_attribute("flag", "1");
        fail_if_not(node.get_attribute_bool("flag", false) == true,
            "'1' should parse as bool true");
    }

    private void test_bool_false() {
        var node = new StanzaNode.build("test", "ns").add_self_xmlns()
            .put_attribute("flag", "false");
        fail_if_not(node.get_attribute_bool("flag", true) == false,
            "'false' should parse as bool false");
    }

    private void test_bool_zero() {
        var node = new StanzaNode.build("test", "ns").add_self_xmlns()
            .put_attribute("flag", "0");
        fail_if_not(node.get_attribute_bool("flag", true) == false,
            "'0' should parse as bool false");
    }

    private void test_bool_missing() {
        var node = new StanzaNode.build("test", "ns").add_self_xmlns();
        fail_if_not(node.get_attribute_bool("flag", true) == true,
            "Missing attribute should return default (true)");
        fail_if_not(node.get_attribute_bool("flag", false) == false,
            "Missing attribute should return default (false)");
    }

    private void test_bool_garbage() {
        var node = new StanzaNode.build("test", "ns").add_self_xmlns()
            .put_attribute("flag", "maybe");
        fail_if_not(node.get_attribute_bool("flag", true) == false,
            "Unrecognized string should parse as false (not default)");
    }
}

}
