using Gee;
using Gdk;

namespace Dino.Ui.Test {

/**
 * Security Audit: UI Helper Pure Functions
 *
 * Tests namespace-level functions in Dino.Ui.Util (helper.vala)
 * that are pure logic with no GTK widget instantiation.
 *
 * Covers:
 *   - Presence color mapping (XMPP show values)
 *   - RGBA to hex string conversion
 *   - 24h format flag
 *   - DateTime formatting
 *   - URL detection regex (security-critical: prevents phishing link misparse)
 *   - Bracket matching pairs
 *   - Whitespace summarization
 *   - Emoji counting (ICU-based)
 *   - Text markup formatting (bold/italic/code/strikethrough)
 */
class UiHelperAudit : Gee.TestCase {

    public UiHelperAudit() {
        base("UiHelperAudit");

        // Presence colors
        add_test("XMPP_color_for_show_online", test_color_online);
        add_test("XMPP_color_for_show_away", test_color_away);
        add_test("XMPP_color_for_show_chat", test_color_chat);
        add_test("XMPP_color_for_show_xa", test_color_xa);
        add_test("XMPP_color_for_show_dnd", test_color_dnd);
        add_test("XMPP_color_for_show_unknown_default", test_color_unknown);

        // RGBA hex conversion
        add_test("CONTRACT_rgba_to_hex_red", test_rgba_red);
        add_test("CONTRACT_rgba_to_hex_green", test_rgba_green);
        add_test("CONTRACT_rgba_to_hex_blue", test_rgba_blue);
        add_test("CONTRACT_rgba_to_hex_white", test_rgba_white);
        add_test("CONTRACT_rgba_to_hex_transparent", test_rgba_transparent);
        add_test("CONTRACT_rgba_to_hex_clamp_overflow", test_rgba_clamp);

        // Time format
        add_test("CONTRACT_is_24h_format_returns_true", test_is_24h);
        add_test("CONTRACT_format_time_24h", test_format_time_24h);
        add_test("CONTRACT_format_time_uses_24h_branch", test_format_time_branch);

        // URL regex
        add_test("RFC3986_url_regex_matches_https", test_url_https);
        add_test("RFC3986_url_regex_matches_http", test_url_http);
        add_test("RFC3986_url_regex_matches_xmpp", test_url_xmpp);
        add_test("RFC3986_url_regex_matches_mailto", test_url_mailto);
        add_test("RFC3986_url_regex_no_plain_text", test_url_no_plain);
        add_test("RFC3986_url_regex_matches_ftp", test_url_ftp);
        add_test("RFC3986_url_regex_embedded_in_text", test_url_embedded);

        // Matching chars
        add_test("CONTRACT_matching_chars_paren", test_match_paren);
        add_test("CONTRACT_matching_chars_bracket", test_match_bracket);
        add_test("CONTRACT_matching_chars_brace", test_match_brace);

        // Whitespace summarization
        add_test("CONTRACT_summarize_ws_multiple_spaces", test_ws_spaces);
        add_test("CONTRACT_summarize_ws_tabs", test_ws_tabs);
        add_test("CONTRACT_summarize_ws_newlines", test_ws_newlines);
        add_test("CONTRACT_summarize_ws_mixed", test_ws_mixed);
        add_test("CONTRACT_summarize_ws_no_change", test_ws_no_change);
        add_test("CONTRACT_summarize_ws_empty", test_ws_empty);

        // Emoji counting (ICU)
        add_test("ICU_emoji_count_single", test_emoji_single);
        add_test("ICU_emoji_count_multiple", test_emoji_multiple);
        add_test("ICU_emoji_count_text_returns_neg1", test_emoji_text);
        add_test("ICU_emoji_count_mixed_returns_neg1", test_emoji_mixed);
        add_test("ICU_emoji_count_empty", test_emoji_empty);
        add_test("ICU_emoji_count_zwj_sequence", test_emoji_zwj);
        add_test("ICU_emoji_count_variation_selector", test_emoji_vs16);

        // Text markup
        add_test("CONTRACT_markup_bold", test_markup_bold);
        add_test("CONTRACT_markup_italic", test_markup_italic);
        add_test("CONTRACT_markup_code", test_markup_code);
        add_test("CONTRACT_markup_strikethrough", test_markup_strike);
        add_test("CONTRACT_markup_plain_no_change", test_markup_plain);
        add_test("CONTRACT_markup_link_detection", test_markup_link);
        add_test("CONTRACT_markup_highlight_word", test_markup_highlight);
        add_test("CONTRACT_markup_escape_entities", test_markup_escape);
    }

    // --- Presence Colors (XMPP RFC 6121 show values) ---

    private void test_color_online() {
        fail_if_not_eq_str("#9CCC65", Util.color_for_show("online"));
    }

    private void test_color_away() {
        fail_if_not_eq_str("#FFCA28", Util.color_for_show("away"));
    }

    private void test_color_chat() {
        fail_if_not_eq_str("#66BB6A", Util.color_for_show("chat"));
    }

    private void test_color_xa() {
        fail_if_not_eq_str("#EF5350", Util.color_for_show("xa"));
    }

    private void test_color_dnd() {
        fail_if_not_eq_str("#EF5350", Util.color_for_show("dnd"));
    }

    private void test_color_unknown() {
        fail_if_not_eq_str("#BDBDBD", Util.color_for_show("offline"));
        fail_if_not_eq_str("#BDBDBD", Util.color_for_show(""));
        fail_if_not_eq_str("#BDBDBD", Util.color_for_show("bogus"));
    }

    // --- RGBA to Hex ---

    private void test_rgba_red() {
        Gdk.RGBA red = { 1.0f, 0.0f, 0.0f, 1.0f };
        fail_if_not_eq_str("#FF0000FF", Util.rgba_to_hex(red));
    }

    private void test_rgba_green() {
        Gdk.RGBA green = { 0.0f, 1.0f, 0.0f, 1.0f };
        fail_if_not_eq_str("#00FF00FF", Util.rgba_to_hex(green));
    }

    private void test_rgba_blue() {
        Gdk.RGBA blue = { 0.0f, 0.0f, 1.0f, 1.0f };
        fail_if_not_eq_str("#0000FFFF", Util.rgba_to_hex(blue));
    }

    private void test_rgba_white() {
        Gdk.RGBA white = { 1.0f, 1.0f, 1.0f, 1.0f };
        fail_if_not_eq_str("#FFFFFFFF", Util.rgba_to_hex(white));
    }

    private void test_rgba_transparent() {
        Gdk.RGBA transparent = { 0.0f, 0.0f, 0.0f, 0.0f };
        fail_if_not_eq_str("#00000000", Util.rgba_to_hex(transparent));
    }

    private void test_rgba_clamp() {
        // Values > 1.0 should be clamped to 1.0
        Gdk.RGBA over = { 2.0f, -1.0f, 0.5f, 1.0f };
        string hex = Util.rgba_to_hex(over);
        // red=2.0 clamped to 1.0 → FF, green=-1.0 clamped to 0.0 → 00
        fail_if_not_eq_str("#FF0080FF", Util.rgba_to_hex(over));
    }

    // --- Time Format ---

    private void test_is_24h() {
        assert_true(Util.is_24h_format(), "is_24h_format should return true");
    }

    private void test_format_time_24h() {
        var dt = new DateTime.local(2026, 2, 23, 14, 30, 0);
        string result = Util.format_time(dt, "%H∶%M", "%l∶%M %p");
        // Since is_24h_format() returns true, should use 24h format
        assert_true(result.contains("14"), "24h format should contain '14' for 2:30 PM");
    }

    private void test_format_time_branch() {
        var dt = new DateTime.local(2026, 1, 1, 9, 5, 0);
        string result = Util.format_time(dt, "TWENTY_FOUR", "TWELVE");
        // is_24h_format() returns true → should pick format_24h
        assert_true(result == "TWENTY_FOUR", "format_time should select 24h format string");
    }

    // --- URL Regex ---

    private void test_url_https() {
        var regex = Util.get_url_regex();
        assert_true(regex.match("https://example.com"), "Should match https URL");
    }

    private void test_url_http() {
        var regex = Util.get_url_regex();
        assert_true(regex.match("http://example.com/path?q=1"), "Should match http URL with path");
    }

    private void test_url_xmpp() {
        var regex = Util.get_url_regex();
        assert_true(regex.match("xmpp:user@example.com"), "Should match xmpp: URI");
    }

    private void test_url_mailto() {
        var regex = Util.get_url_regex();
        assert_true(regex.match("mailto:user@example.com"), "Should match mailto: URI");
    }

    private void test_url_no_plain() {
        var regex = Util.get_url_regex();
        assert_false(regex.match("just plain text"), "Should NOT match plain text");
    }

    private void test_url_ftp() {
        var regex = Util.get_url_regex();
        assert_true(regex.match("ftp://files.example.com/pub"), "Should match ftp URL");
    }

    private void test_url_embedded() {
        var regex = Util.get_url_regex();
        MatchInfo info;
        regex.match("Check out https://example.com/page for details", 0, out info);
        assert_true(info.matches(), "Should match URL embedded in text");
        string url = info.fetch(0);
        assert_true(url.has_prefix("https://example.com"), "Extracted URL should start with https://example.com");
    }

    // --- Matching Chars ---

    private void test_match_paren() {
        var map = Util.get_matching_chars();
        assert_true(map.has_key(')'), "Should map ) → (");
        assert_true(map[')'] == '(', "Close paren should map to open paren");
    }

    private void test_match_bracket() {
        var map = Util.get_matching_chars();
        assert_true(map.has_key(']'), "Should map ] → [");
        assert_true(map[']'] == '[', "Close bracket should map to open bracket");
    }

    private void test_match_brace() {
        var map = Util.get_matching_chars();
        assert_true(map.has_key('}'), "Should map } → {");
        assert_true(map['}'] == '{', "Close brace should map to open brace");
    }

    // --- Whitespace Summarization ---

    private void test_ws_spaces() {
        fail_if_not_eq_str("a b c", Util.summarize_whitespaces_to_space("a  b   c"));
    }

    private void test_ws_tabs() {
        fail_if_not_eq_str("a b", Util.summarize_whitespaces_to_space("a\tb"));
    }

    private void test_ws_newlines() {
        fail_if_not_eq_str("a b", Util.summarize_whitespaces_to_space("a\nb"));
    }

    private void test_ws_mixed() {
        fail_if_not_eq_str("a b c", Util.summarize_whitespaces_to_space("a \t\n b \n\t c"));
    }

    private void test_ws_no_change() {
        fail_if_not_eq_str("hello world", Util.summarize_whitespaces_to_space("hello world"));
    }

    private void test_ws_empty() {
        fail_if_not_eq_str("", Util.summarize_whitespaces_to_space(""));
    }

    // --- Emoji Count (ICU) ---

    private void test_emoji_single() {
        int count = Util.get_only_emoji_count("😀");
        fail_if_not_eq_int(1, count);
    }

    private void test_emoji_multiple() {
        int count = Util.get_only_emoji_count("😀😀😀");
        fail_if_not_eq_int(3, count);
    }

    private void test_emoji_text() {
        int count = Util.get_only_emoji_count("hello");
        fail_if_not_eq_int(-1, count);
    }

    private void test_emoji_mixed() {
        int count = Util.get_only_emoji_count("hello 😀");
        fail_if_not_eq_int(-1, count);
    }

    private void test_emoji_empty() {
        int count = Util.get_only_emoji_count("");
        fail_if_not_eq_int(0, count);
    }

    private void test_emoji_zwj() {
        // Family emoji: Person + ZWJ + Person + ZWJ + Child
        // 👨‍👩‍👧 = U+1F468 U+200D U+1F469 U+200D U+1F467
        int count = Util.get_only_emoji_count("👨\u200D👩\u200D👧");
        fail_if_not_eq_int(1, count);
    }

    private void test_emoji_vs16() {
        // Digit + VS16 = emoji presentation
        // 1️⃣ = U+0031 U+FE0F U+20E3
        int count = Util.get_only_emoji_count("1\uFE0F\u20E3");
        fail_if_not_eq_int(1, count);
    }

    // --- Text Markup ---

    private void test_markup_bold() {
        string result = Util.parse_add_markup("hello *world*", null, false, true);
        assert_true(result.contains("<b>"), "*word* should produce <b> tag");
        assert_true(result.contains("world"), "bold text content should be preserved");
    }

    private void test_markup_italic() {
        string result = Util.parse_add_markup("hello _world_", null, false, true);
        assert_true(result.contains("<i>"), "_word_ should produce <i> tag");
    }

    private void test_markup_code() {
        string result = Util.parse_add_markup("hello `code`", null, false, true);
        assert_true(result.contains("<tt>"), "`word` should produce <tt> tag");
    }

    private void test_markup_strike() {
        string result = Util.parse_add_markup("hello ~strike~", null, false, true);
        assert_true(result.contains("<s>"), "~word~ should produce <s> tag");
    }

    private void test_markup_plain() {
        string result = Util.parse_add_markup("hello world", null, false, false);
        // With parse_text_markup=false and parse_links=false, just escape
        assert_true(result == "hello world", "Plain text without markup should pass through");
    }

    private void test_markup_link() {
        string result = Util.parse_add_markup("visit https://example.com now", null, true, false);
        assert_true(result.contains("<a href="), "URL should be wrapped in <a> tag");
        assert_true(result.contains("https://example.com"), "URL should be preserved in link");
    }

    private void test_markup_highlight() {
        string result = Util.parse_add_markup("hello world", "world", false, false);
        assert_true(result.contains("<b>"), "Highlight word should be wrapped in <b>");
    }

    private void test_markup_escape() {
        string result = Util.parse_add_markup("<script>alert('xss')</script>", null, false, false);
        assert_true(result.contains("&lt;"), "< should be escaped to &lt;");
        assert_true(result.contains("&gt;"), "> should be escaped to &gt;");
        assert_false(result.contains("<script>"), "Raw <script> tag must NOT appear in output");
    }
}

}
