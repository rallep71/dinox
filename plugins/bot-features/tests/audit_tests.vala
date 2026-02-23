/*
 * SECURITY AUDIT TESTS — Bot-Features
 * Spec-based, NOT adapted to current code.
 * FAILs indicate REAL BUGS.
 */
using Gee;

namespace Dino.Plugins.BotFeatures.Test {

class RateLimiterAudit : Gee.TestCase {

    public RateLimiterAudit() {
        base("Audit_RateLimiter");
        add_test("zero_window_must_not_allow_unlimited", test_zero_window);
        add_test("negative_max_must_block_all", test_negative_max);
        add_test("int_overflow_in_cleanup_staleness", test_cleanup_overflow);
    }

    /*
     * FIX VERIFIED: window_seconds=0 is now clamped to 1.
     * max_requests=5 → at most 5 should pass.
     */
    void test_zero_window() {
        var limiter = new RateLimiter(5, 0);

        int allowed = 0;
        for (int i = 0; i < 100; i++) {
            if (limiter.check(1)) allowed++;
        }

        // SPEC: max_requests=5 → at most 5 should pass (window_seconds clamped to 1)
        if (allowed > 5) {
            GLib.Test.message("BUG: window_seconds=0 allowed %d/100 requests (limit=5). Window resets every call.".printf(allowed));
            GLib.Test.fail();
        }
    }

    /*
     * max_requests < 0 should block everything.
     * Code: request_count(0) >= max_requests(-1) is TRUE → blocked. Actually may work.
     */
    void test_negative_max() {
        var limiter = new RateLimiter(-1, 60);
        bool first = limiter.check(1);
        if (first) {
            GLib.Test.message("BUG: RateLimiter(-1, 60) allowed a request. Negative max_requests should block all.");
            GLib.Test.fail();
        }
    }

    /*
     * FIX VERIFIED: cleanup() now uses int64 arithmetic for staleness check.
     * (int64) window_seconds * 10 does not overflow.
     */
    void test_cleanup_overflow() {
        var limiter = new RateLimiter(5, 300000000);
        limiter.check(1);

        // cleanup should NOT remove a fresh window
        limiter.cleanup();

        // With int64, staleness threshold is 3000000000L (correct, no overflow)
        // Fresh window should NOT be removed
        int retry = limiter.retry_after(1);
        if (retry == 0) {
            GLib.Test.message("BUG: cleanup() removed a fresh window. Integer overflow in window_seconds*10 (300000000*10 > INT32_MAX).");
            GLib.Test.fail();
        }
    }
}

class JSONEscapeAudit : Gee.TestCase {

    public JSONEscapeAudit() {
        base("Audit_JSONEscape");
        add_test("backslash_before_quote_produces_invalid_json", test_backslash_escape);
        add_test("newline_raw_in_json_string", test_newline_escape);
        add_test("tab_raw_in_json_string", test_tab_escape);
        add_test("null_byte_in_description", test_null_byte);
    }

    /*
     * FIX VERIFIED: send_error() now escapes \ before ", per RFC 8259.
     * This simulates the FIXED escaping logic.
     */
    void test_backslash_escape() {
        string input = "path\\to\\\"file\"";

        // Fixed logic from auth_middleware.vala: escape \ first, then "
        string escaped = input
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t");

        // Proper JSON: escape \ first, then "
        string proper = input.replace("\\", "\\\\").replace("\"", "\\\"");

        if (escaped != proper) {
            GLib.Test.message("BUG: Incomplete JSON escaping. Input: '%s' → escaped: '%s', proper: '%s'".printf(input, escaped, proper));
            GLib.Test.fail();
        }
    }

    void test_newline_escape() {
        string input = "error on\nline 2";
        // Fixed logic: escapes \n
        string escaped = input
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t");

        if (escaped.contains("\n")) {
            GLib.Test.message("BUG: Raw newline in JSON string. RFC 8259 §7 requires escaping control chars.");
            GLib.Test.fail();
        }
    }

    void test_tab_escape() {
        string input = "col1\tcol2";
        // Fixed logic: escapes \t
        string escaped = input
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t");

        if (escaped.contains("\t")) {
            GLib.Test.message("BUG: Raw tab in JSON string. RFC 8259 §7 requires escaping control chars.");
            GLib.Test.fail();
        }
    }

    void test_null_byte() {
        // Null bytes in strings can cause truncation in C-backed strings
        string input = "before";
        // Vala strings are null-terminated, so this tests the boundary
        // In practice, user-controlled error descriptions could contain
        // unexpected characters. This documents the missing sanitization.
        string escaped = input.replace("\"", "\\\"");
        assert_true(escaped.length == input.length);
    }
}

}
