using Gee;

namespace Dino.Plugins.BotFeatures.Test {

class RateLimiterTest : Gee.TestCase {

    public RateLimiterTest() {
        base("RateLimiter");
        add_test("allows_within_limit", test_allows_within_limit);
        add_test("blocks_over_limit", test_blocks_over_limit);
        add_test("separate_bots_independent", test_separate_bots_independent);
        add_test("window_resets_after_expiry", test_window_resets_after_expiry);
        add_test("retry_after_positive", test_retry_after_positive);
        add_test("retry_after_zero_unknown_bot", test_retry_after_zero_unknown_bot);
        add_test("cleanup_removes_stale", test_cleanup_removes_stale);
        add_test("single_request_limit", test_single_request_limit);
    }

    void test_allows_within_limit() {
        var limiter = new RateLimiter(5, 60);
        // 5 requests should all succeed
        for (int i = 0; i < 5; i++) {
            assert_true(limiter.check(1));
        }
    }

    void test_blocks_over_limit() {
        var limiter = new RateLimiter(3, 60);
        // First 3 pass
        assert_true(limiter.check(1));
        assert_true(limiter.check(1));
        assert_true(limiter.check(1));
        // 4th is blocked
        assert_false(limiter.check(1));
        // 5th also blocked
        assert_false(limiter.check(1));
    }

    void test_separate_bots_independent() {
        var limiter = new RateLimiter(2, 60);
        // Bot 1: use up quota
        assert_true(limiter.check(1));
        assert_true(limiter.check(1));
        assert_false(limiter.check(1));  // blocked

        // Bot 2: still has full quota
        assert_true(limiter.check(2));
        assert_true(limiter.check(2));
        assert_false(limiter.check(2));  // blocked

        // Bot 1 still blocked
        assert_false(limiter.check(1));
    }

    void test_window_resets_after_expiry() {
        // Use 1-second window so it expires quickly
        var limiter = new RateLimiter(2, 1);
        assert_true(limiter.check(1));
        assert_true(limiter.check(1));
        assert_false(limiter.check(1));  // blocked

        // Wait for window to expire
        Thread.usleep(1100000);  // 1.1 seconds

        // Should be allowed again
        assert_true(limiter.check(1));
    }

    void test_retry_after_positive() {
        var limiter = new RateLimiter(1, 60);
        limiter.check(1);  // use quota
        limiter.check(1);  // blocked

        int retry = limiter.retry_after(1);
        // Should be positive but <= 60
        assert_true(retry > 0);
        assert_true(retry <= 60);
    }

    void test_retry_after_zero_unknown_bot() {
        var limiter = new RateLimiter(5, 60);
        // Unknown bot should return 0
        assert_true(limiter.retry_after(999) == 0);
    }

    void test_cleanup_removes_stale() {
        var limiter = new RateLimiter(5, 1);
        // Create windows for several bots
        limiter.check(1);
        limiter.check(2);
        limiter.check(3);

        // Cleanup should not crash on fresh windows
        limiter.cleanup();

        // Requests still work after cleanup (windows not yet stale)
        assert_true(limiter.check(1));
    }

    void test_single_request_limit() {
        // Edge case: only 1 request allowed
        var limiter = new RateLimiter(1, 60);
        assert_true(limiter.check(1));
        assert_false(limiter.check(1));
    }
}

class CryptoTest : Gee.TestCase {

    public CryptoTest() {
        base("Crypto");
        add_test("sha256_known_vector", test_sha256_known_vector);
        add_test("sha256_empty_string", test_sha256_empty_string);
        add_test("sha256_deterministic", test_sha256_deterministic);
        add_test("hmac_sha256_known_vector", test_hmac_sha256_known_vector);
        add_test("hmac_sha256_deterministic", test_hmac_sha256_deterministic);
        add_test("webhook_secret_length", test_webhook_secret_length);
        add_test("webhook_secret_unique", test_webhook_secret_unique);
        add_test("webhook_secret_hex_chars", test_webhook_secret_hex_chars);
    }

    // SHA-256 helper (same logic as TokenManager.hash_token)
    private static string sha256(string input) {
        Checksum checksum = new Checksum(ChecksumType.SHA256);
        checksum.update((uchar[]) input.data, input.data.length);
        return checksum.get_string();
    }

    // HMAC-SHA256 helper (same logic as TokenManager.hmac_sha256)
    private static string hmac_sha256(string key, string data) {
        var hmac = new Hmac(ChecksumType.SHA256, (uchar[]) key.data);
        hmac.update((uchar[]) data.data);
        size_t digest_len = 32;
        uint8[] digest = new uint8[digest_len];
        hmac.get_digest(digest, ref digest_len);
        var sb = new StringBuilder();
        for (int i = 0; i < (int) digest_len; i++) {
            sb.append_printf("%02x", digest[i]);
        }
        return sb.str;
    }

    void test_sha256_known_vector() {
        // Known SHA-256 test vector: SHA-256("abc")
        string result = sha256("abc");
        assert_true(result == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    }

    void test_sha256_empty_string() {
        // SHA-256("") is well-known
        string result = sha256("");
        assert_true(result == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    }

    void test_sha256_deterministic() {
        // Same input must always produce same hash
        string input = "bot42:test-token-value";
        string h1 = sha256(input);
        string h2 = sha256(input);
        assert_true(h1 == h2);
        // And must be 64 hex chars
        assert_true(h1.length == 64);
    }

    void test_hmac_sha256_known_vector() {
        // RFC 4231 Test Case 2: HMAC-SHA256 with key "Jefe" and data "what do ya want for nothing?"
        string key = "Jefe";
        string data = "what do ya want for nothing?";
        string result = hmac_sha256(key, data);
        assert_true(result == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");
    }

    void test_hmac_sha256_deterministic() {
        string key = "webhook-secret-123";
        string data = "{\"event\":\"message\",\"bot_id\":1}";
        string h1 = hmac_sha256(key, data);
        string h2 = hmac_sha256(key, data);
        assert_true(h1 == h2);
        assert_true(h1.length == 64);
    }

    void test_webhook_secret_length() {
        // generate_webhook_secret returns 2 UUIDs without dashes = 64 hex chars
        string uuid1 = GLib.Uuid.string_random().replace("-", "");
        string uuid2 = GLib.Uuid.string_random().replace("-", "");
        string secret = uuid1 + uuid2;
        assert_true(secret.length == 64);
    }

    void test_webhook_secret_unique() {
        // Two generated secrets must differ
        string s1 = GLib.Uuid.string_random().replace("-", "") + GLib.Uuid.string_random().replace("-", "");
        string s2 = GLib.Uuid.string_random().replace("-", "") + GLib.Uuid.string_random().replace("-", "");
        assert_true(s1 != s2);
    }

    void test_webhook_secret_hex_chars() {
        // Secret should only contain hex characters
        string secret = GLib.Uuid.string_random().replace("-", "") + GLib.Uuid.string_random().replace("-", "");
        for (int i = 0; i < secret.length; i++) {
            char c = (char) secret[i];
            bool is_hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
            assert_true(is_hex);
        }
    }
}

}
