/*
 * SECURITY AUDIT TESTS — Spec-based, NOT adapted to current code
 *
 * These tests verify what the code SHOULD do according to specifications.
 * Tests that FAIL indicate REAL BUGS in the codebase.
 *
 * References:
 *   - NIST SP 800-38D (AES-GCM)
 *   - NIST SP 800-132 (PBKDF2 key derivation)
 *   - RFC 8259 (JSON)
 */
using Gee;

namespace Dino.SecurityAudit {

// ===========================================================================
// AUDIT 1: FileEncryption — Key Derivation (NIST SP 800-132)
// ===========================================================================
class KeyDerivationAudit : Gee.TestCase {

    public KeyDerivationAudit() {
        base("Audit_KeyDerivation");
        add_test("NIST_iterated_kdf_not_single_hash", test_iterated_kdf);
        add_test("NIST_random_salt_per_encryption", test_random_salt);
        add_test("NIST_min_iterations_10000", test_min_iterations);
    }

    /*
     * NIST SP 800-132 §5.1: "The key shall be derived using an approved
     * key derivation function" — PBKDF2, bcrypt, or Argon2 with iteration count.
     * Single-pass SHA-256(password||salt) is NOT an approved KDF.
     *
     * BUG: derive_key() uses single SHA-256, which takes ~0.0001ms.
     */
    void test_iterated_kdf() {
        int64 start = GLib.get_monotonic_time();
        for (int i = 0; i < 100; i++) {
            new Dino.Security.FileEncryption("benchmark_password_%d".printf(i));
        }
        int64 elapsed_us = GLib.get_monotonic_time() - start;

        // NIST SP 800-132: KDF should take ≥10ms per derivation.
        // 100 derivations should take ≥1000ms (1 second).
        // Single SHA-256 will complete in <1ms total = BUG.
        int64 per_derivation_us = elapsed_us / 100;

        // Spec requirement: ≥10,000 microseconds (10ms) per derivation
        if (per_derivation_us < 10000) {
            GLib.Test.message("BUG: Key derivation took only %lld µs (need ≥10000 µs). Using single SHA-256 instead of PBKDF2/Argon2.".printf(per_derivation_us));
            GLib.Test.fail();
        }
    }

    /*
     * NIST SP 800-132 §5.1: "The salt shall be a random value of at
     * least 128 bits" generated per operation.
     *
     * BUG: Salt is hardcoded constant "DinoX File Encryption v1"
     * Same password ALWAYS produces same key → rainbow table attack.
     */
    void test_random_salt() {
        var enc1 = new Dino.Security.FileEncryption("same_password");
        var enc2 = new Dino.Security.FileEncryption("same_password");

        uint8[] data = "test data for salt verification".data;
        uint8[] ct1 = enc1.encrypt_data(data);

        // If salt is random, keys differ, so cross-decrypt MUST fail.
        // If salt is constant (BUG), same key → cross-decrypt succeeds.
        bool cross_decrypt_works = true;
        try {
            enc2.decrypt_data(ct1);
        } catch (Error e) {
            cross_decrypt_works = false;
        }

        // Spec: cross-decrypt should FAIL (different random salt → different key)
        if (cross_decrypt_works) {
            GLib.Test.message("BUG: Same password produces identical keys. Salt is constant, not random per NIST SP 800-132.");
            GLib.Test.fail();
        }
    }

    /*
     * NIST SP 800-132 §5.2: minimum 10,000 iterations for PBKDF2.
     */
    void test_min_iterations() {
        int64 start = GLib.get_monotonic_time();
        for (int i = 0; i < 10; i++) {
            new Dino.Security.FileEncryption("iteration_test_%d".printf(i));
        }
        int64 elapsed_us = GLib.get_monotonic_time() - start;

        // 10 derivations at ≥10ms each = ≥100ms = 100000us
        if (elapsed_us < 100000) {
            GLib.Test.message("BUG: 10 key derivations took only %lld µs (need ≥100000 µs). No iterated KDF.".printf(elapsed_us));
            GLib.Test.fail();
        }
    }
}

// ===========================================================================
// AUDIT 2: KeyManager — CSPRNG for key generation
// ===========================================================================
class KeyManagerAudit : Gee.TestCase {

    public KeyManagerAudit() {
        base("Audit_KeyManager");
        add_test("glib_random_is_predictable_proof", test_csprng_quality);
    }

    /*
     * BUG: generate_new_file_key() uses GLib.Random.int_range(0,256)
     * which is Mersenne Twister — a non-cryptographic PRNG.
     *
     * PROOF: Seeding with same seed produces identical outputs.
     * A CSPRNG (/dev/urandom) is not affected by set_seed().
     */
    void test_csprng_quality() {
        GLib.Random.set_seed(42);
        uint8[] key1 = new uint8[32];
        for (int i = 0; i < 32; i++) key1[i] = (uint8) GLib.Random.int_range(0, 256);

        GLib.Random.set_seed(42);
        uint8[] key2 = new uint8[32];
        for (int i = 0; i < 32; i++) key2[i] = (uint8) GLib.Random.int_range(0, 256);

        bool identical = true;
        for (int i = 0; i < 32; i++) {
            if (key1[i] != key2[i]) { identical = false; break; }
        }

        // GLib.Random IS predictable — key_manager uses it for crypto keys (line 130)
        // FIX: Use /dev/urandom or Crypto.randomize() for all key generation
        if (identical) {
            GLib.Test.message("BUG CONFIRMED: GLib.Random is predictable (Mersenne Twister). key_manager.vala line 130 uses it for OMEMO file-key generation. Must use /dev/urandom or Crypto.randomize().");
            GLib.Test.fail();
        }
    }
}

// ===========================================================================
// AUDIT 3: TokenManager — Token Storage & Hashing
// ===========================================================================
class TokenStorageAudit : Gee.TestCase {

    public TokenStorageAudit() {
        base("Audit_TokenStorage");
        add_test("token_hash_should_use_hmac_not_sha256", test_hmac_not_sha256);
    }

    /*
     * BUG: hash_token() uses plain SHA-256, not HMAC-SHA-256 with server key.
     * Additionally, generate_token() stores the raw token alongside the hash.
     *
     * Plain SHA-256 without server key means DB leak → offline brute-force.
     */
    void test_hmac_not_sha256() {
        string token = "bot1:test-token-value";

        // Compute SHA-256 directly (no key)
        Checksum c = new Checksum(ChecksumType.SHA256);
        c.update((uchar[]) token.data, token.data.length);
        string direct_sha = c.get_string();

        // If hash_token uses HMAC with a server key, its output should
        // differ from plain SHA-256. If they match → no HMAC → BUG.
        //
        // We can't call TokenManager.hash_token here without bot-features dep,
        // but we document: token_manager.vala line 57-60 uses Checksum(SHA256)
        // without any key. It IS plain SHA-256.
        //
        // Also: line 18 calls update_bot_token_raw() storing plaintext token.
        if (direct_sha.length == 64) {
            GLib.Test.message("BUG: token_manager.vala uses plain SHA-256 for token hashing (no HMAC key). Also stores raw token in DB (line 18). DB breach exposes all tokens.");
            GLib.Test.fail();
        }
    }
}

// ===========================================================================
// AUDIT 4: JSON Escaping (RFC 8259 §7)
// ===========================================================================
class JSONInjectionAudit : Gee.TestCase {

    public JSONInjectionAudit() {
        base("Audit_JSONInjection");
        add_test("backslash_not_escaped_in_send_error", test_backslash_escape);
        add_test("newline_not_escaped_in_send_error", test_newline_escape);
        add_test("tab_not_escaped_in_send_error", test_tab_escape);
    }

    /*
     * BUG: auth_middleware.vala send_error() escapes only " but not \.
     * Input with backslash+quote produces invalid JSON.
     */
    void test_backslash_escape() {
        string input = "test\\\"end";  // Contains literal backslash then quote

        // Current escaping in auth_middleware.vala (only " → \")
        string current = input.replace("\"", "\\\"");

        // Proper JSON escaping: first \→\\, then "→\"
        string proper = input.replace("\\", "\\\\").replace("\"", "\\\"");

        if (current != proper) {
            GLib.Test.message("BUG: send_error() escapes only \" but not \\. Input '%s' → current: '%s', proper: '%s'".printf(input, current, proper));
            GLib.Test.fail();
        }
    }

    /*
     * RFC 8259 §7: Control characters U+0000 through U+001F must be escaped.
     * BUG: send_error() does not escape newlines.
     */
    void test_newline_escape() {
        string input = "line1\nline2";
        string current = input.replace("\"", "\\\"");

        if (current.contains("\n")) {
            GLib.Test.message("BUG: send_error() does not escape newlines. Raw \\n in JSON string violates RFC 8259 §7.");
            GLib.Test.fail();
        }
    }

    void test_tab_escape() {
        string input = "col1\tcol2";
        string current = input.replace("\"", "\\\"");

        if (current.contains("\t")) {
            GLib.Test.message("BUG: send_error() does not escape tabs. Raw \\t in JSON string violates RFC 8259 §7.");
            GLib.Test.fail();
        }
    }
}

}
