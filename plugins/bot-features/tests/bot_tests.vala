using Gee;

namespace Dino.Plugins.BotFeatures.Test {

/**
 * Rate limiter contract tests.
 *
 * RateLimiter implements a sliding-window rate limiter per IETF RFC 6585 §4
 * ("429 Too Many Requests") spirit: requests exceeding max_requests within
 * window_seconds MUST be rejected. These tests verify the contract:
 *
 * CONTRACT-1: Exactly max_requests allowed per window
 * CONTRACT-2: Request max_requests+1 MUST be blocked
 * CONTRACT-3: Per-key isolation (one key's quota does not affect another)
 * CONTRACT-4: Window expiry resets quota
 * CONTRACT-5: retry_after returns seconds until window reset
 * CONTRACT-6: Cleanup removes stale state without affecting live windows
 * CONTRACT-7: window_seconds ≤ 0 MUST be clamped to 1 (security invariant)
 */
class RateLimiterTest : Gee.TestCase {

    public RateLimiterTest() {
        base("RateLimiter");
        // CONTRACT-1 + CONTRACT-2: exact boundary
        add_test("CONTRACT1_allows_exactly_max_requests", test_allows_exactly_max);
        add_test("CONTRACT2_blocks_request_max_plus_one", test_blocks_over_limit);
        // CONTRACT-3: per-key isolation
        add_test("CONTRACT3_separate_keys_independent", test_separate_keys_independent);
        // CONTRACT-4: window expiry
        add_test("CONTRACT4_window_resets_after_expiry", test_window_resets_after_expiry);
        // CONTRACT-5: retry_after
        add_test("CONTRACT5_retry_after_positive_when_blocked", test_retry_after_positive);
        add_test("CONTRACT5_retry_after_zero_unknown_key", test_retry_after_zero_unknown);
        // CONTRACT-6: cleanup
        add_test("CONTRACT6_cleanup_preserves_live_windows", test_cleanup_preserves_live);
        // CONTRACT-7: window_seconds guard
        add_test("CONTRACT7_window_seconds_clamped_to_1", test_window_seconds_clamped);
        // CONTRACT-8: Edge case max_requests=1
        add_test("CONTRACT8_single_request_limit", test_single_request_limit);
    }

    /**
     * CONTRACT-1: Exactly max_requests calls to check() with the same key
     * MUST all return true.
     */
    void test_allows_exactly_max() {
        var limiter = new RateLimiter(5, 60);
        for (int i = 0; i < 5; i++) {
            assert_true(limiter.check(1));
        }
    }

    /**
     * CONTRACT-2: The (max_requests+1)-th call MUST return false.
     * Subsequent calls also remain blocked.
     */
    void test_blocks_over_limit() {
        var limiter = new RateLimiter(3, 60);
        assert_true(limiter.check(1));
        assert_true(limiter.check(1));
        assert_true(limiter.check(1));
        // 4th is blocked
        assert_false(limiter.check(1));
        // 5th also blocked
        assert_false(limiter.check(1));
    }

    /**
     * CONTRACT-3: Keys are isolated. Exhausting key A's quota
     * MUST NOT affect key B.
     */
    void test_separate_keys_independent() {
        var limiter = new RateLimiter(2, 60);
        // Key 1: exhaust quota
        assert_true(limiter.check(1));
        assert_true(limiter.check(1));
        assert_false(limiter.check(1));

        // Key 2: full quota available
        assert_true(limiter.check(2));
        assert_true(limiter.check(2));
        assert_false(limiter.check(2));

        // Key 1 still blocked
        assert_false(limiter.check(1));
    }

    /**
     * CONTRACT-4: After window_seconds have elapsed, the window MUST
     * reset and allow max_requests again.
     */
    void test_window_resets_after_expiry() {
        var limiter = new RateLimiter(2, 1);
        assert_true(limiter.check(1));
        assert_true(limiter.check(1));
        assert_false(limiter.check(1));

        // Wait for window to expire
        Thread.usleep(1100000);  // 1.1 seconds

        // Window expired — quota reset
        assert_true(limiter.check(1));
    }

    /**
     * CONTRACT-5a: retry_after for a blocked key MUST return
     * a positive integer ≤ window_seconds.
     */
    void test_retry_after_positive() {
        var limiter = new RateLimiter(1, 60);
        limiter.check(1);  // use quota
        limiter.check(1);  // blocked

        int retry = limiter.retry_after(1);
        assert_true(retry > 0);
        assert_true(retry <= 60);
    }

    /**
     * CONTRACT-5b: retry_after for an unknown key MUST return 0
     * (no waiting needed — key has no prior history).
     */
    void test_retry_after_zero_unknown() {
        var limiter = new RateLimiter(5, 60);
        assert_true(limiter.retry_after(999) == 0);
    }

    /**
     * CONTRACT-6: cleanup() removes only stale windows (>10× window_seconds old).
     * Live windows MUST be preserved and functional.
     */
    void test_cleanup_preserves_live() {
        var limiter = new RateLimiter(5, 1);
        limiter.check(1);
        limiter.check(2);
        limiter.check(3);

        // Cleanup on fresh windows — must not corrupt state
        limiter.cleanup();

        // Live windows still functional
        assert_true(limiter.check(1));
    }

    /**
     * CONTRACT-7: window_seconds ≤ 0 is a security violation (infinite window
     * or division by zero). Constructor MUST clamp to at least 1.
     */
    void test_window_seconds_clamped() {
        // window_seconds=0 → should be clamped to 1 internally
        var limiter = new RateLimiter(2, 0);
        assert_true(limiter.check(1));
        assert_true(limiter.check(1));
        assert_false(limiter.check(1));

        // Should reset after ~1 second (clamped to 1)
        Thread.usleep(1100000);
        assert_true(limiter.check(1));
    }

    /**
     * Edge case: max_requests=1 means exactly one request, then blocked.
     */
    void test_single_request_limit() {
        var limiter = new RateLimiter(1, 60);
        assert_true(limiter.check(1));
        assert_false(limiter.check(1));
    }
}

/**
 * Cryptographic hash and HMAC tests.
 *
 * References:
 *   - FIPS 180-4 §B.1–B.3: SHA-256 test vectors
 *   - RFC 4231 §4.2–4.4: HMAC-SHA-256 test cases
 *   - NIST SP 800-63B §5.1.1: Minimum 112-bit secret entropy
 */
class CryptoTest : Gee.TestCase {

    public CryptoTest() {
        base("Crypto");
        // FIPS 180-4 test vectors
        add_test("FIPS180_4_sha256_abc", test_sha256_abc);
        add_test("FIPS180_4_sha256_empty", test_sha256_empty);
        add_test("FIPS180_4_sha256_multiblock", test_sha256_multiblock);
        add_test("FIPS180_4_sha256_digest_is_256_bits", test_sha256_digest_256_bits);
        // RFC 4231 test vectors
        add_test("RFC4231_case2_hmac_sha256", test_hmac_rfc4231_case2);
        add_test("RFC4231_case3_hmac_sha256", test_hmac_rfc4231_case3);
        // Webhook secret entropy (NIST SP 800-63B)
        add_test("SP800_63B_secret_min_128_bit_entropy", test_secret_entropy);
        add_test("SP800_63B_secret_uniqueness_no_collision", test_secret_unique);
    }

    // SHA-256 helper (mirrors TokenManager.hash_token)
    private static string sha256(string input) {
        Checksum checksum = new Checksum(ChecksumType.SHA256);
        checksum.update((uchar[]) input.data, input.data.length);
        return checksum.get_string();
    }

    // HMAC-SHA256 helper (mirrors TokenManager.hmac_sha256)
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

    /**
     * FIPS 180-4 §B.1: SHA-256("abc") =
     * ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
     */
    void test_sha256_abc() {
        string result = sha256("abc");
        assert_true(result == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    }

    /**
     * FIPS 180-4: SHA-256("") =
     * e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
     */
    void test_sha256_empty() {
        string result = sha256("");
        assert_true(result == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    }

    /**
     * FIPS 180-4 §B.2: SHA-256 of the 448-bit message:
     * "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
     *
     * This tests multi-block processing (message > 512 bits after padding).
     */
    void test_sha256_multiblock() {
        string input = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
        string result = sha256(input);
        assert_true(result == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    }

    /**
     * FIPS 180-4 §1: SHA-256 output MUST be exactly 256 bits = 32 bytes = 64 hex chars.
     */
    void test_sha256_digest_256_bits() {
        string result = sha256("any input");
        assert_true(result.length == 64);
        // Verify all chars are hex
        for (int i = 0; i < result.length; i++) {
            char c = (char) result[i];
            bool is_hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
            assert_true(is_hex);
        }
    }

    /**
     * RFC 4231 Test Case 2:
     *   Key = "Jefe"
     *   Data = "what do ya want for nothing?"
     *   HMAC-SHA-256 = 5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843
     */
    void test_hmac_rfc4231_case2() {
        string result = hmac_sha256("Jefe", "what do ya want for nothing?");
        assert_true(result == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");
    }

    /**
     * RFC 4231 Test Case 3:
     *   Key = 0xaa repeated 20 times
     *   Data = 0xdd repeated 50 times
     *   HMAC-SHA-256 = 773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe
     */
    void test_hmac_rfc4231_case3() {
        // Build key: 20 bytes of 0xaa
        uint8[] key_bytes = new uint8[20];
        for (int i = 0; i < 20; i++) key_bytes[i] = 0xaa;

        // Build data: 50 bytes of 0xdd
        uint8[] data_bytes = new uint8[50];
        for (int i = 0; i < 50; i++) data_bytes[i] = 0xdd;

        // Use raw byte HMAC since key/data are binary
        var hmac = new Hmac(ChecksumType.SHA256, key_bytes);
        hmac.update(data_bytes);
        size_t digest_len = 32;
        uint8[] digest = new uint8[digest_len];
        hmac.get_digest(digest, ref digest_len);
        var sb = new StringBuilder();
        for (int i = 0; i < (int) digest_len; i++) {
            sb.append_printf("%02x", digest[i]);
        }

        assert_true(sb.str == "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe");
    }

    /**
     * NIST SP 800-63B §5.1.1: Secrets MUST have at least 112 bits of entropy.
     * Our webhook secrets use 2×UUID4 = 2×122 = 244 random bits → 64 hex chars.
     * The hex representation MUST be at least 128 bits (32 hex chars).
     */
    void test_secret_entropy() {
        string uuid1 = GLib.Uuid.string_random().replace("-", "");
        string uuid2 = GLib.Uuid.string_random().replace("-", "");
        string secret = uuid1 + uuid2;

        // 64 hex chars = 256 bits of hex representation ≥ 128-bit minimum
        assert_true(secret.length == 64);

        // Verify hex-only encoding (no non-hex chars from UUID format)
        for (int i = 0; i < secret.length; i++) {
            char c = (char) secret[i];
            bool is_hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
            assert_true(is_hex);
        }
    }

    /**
     * Two independently generated secrets MUST differ (collision probability
     * for 244 random bits is ~2^-244 ≈ 0).
     */
    void test_secret_unique() {
        string s1 = GLib.Uuid.string_random().replace("-", "") + GLib.Uuid.string_random().replace("-", "");
        string s2 = GLib.Uuid.string_random().replace("-", "") + GLib.Uuid.string_random().replace("-", "");
        assert_true(s1 != s2);
    }
}

}
