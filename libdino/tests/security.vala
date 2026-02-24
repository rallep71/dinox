using Dino.Security;

namespace Dino.Test {

/**
 * Spec-based tests for FileEncryption (AES-256-GCM + PBKDF2).
 *
 * References:
 *   - NIST SP 800-38D (AES-GCM): ciphertext length, IV/tag sizes, authentication
 *   - NIST SP 800-132 (PBKDF2): key derivation, salt requirements
 *   - RFC 5116 §5.1 (AEAD_AES_256_GCM): output format constraints
 */
class SecurityTest : Gee.TestCase {

    // Expected format: SALT(16) + IV(12) + Ciphertext + TAG(16)
    private const int SALT_SIZE = 16;
    private const int IV_SIZE = 12;
    private const int TAG_SIZE = 16;
    private const int OVERHEAD = 44;  // SALT + IV + TAG

    public SecurityTest() {
        base("Security");
        // NIST SP 800-38D: GCM correctness
        add_test("SP800_38D_ciphertext_length_equals_plaintext", test_gcm_ciphertext_length);
        add_test("SP800_38D_authentication_rejects_wrong_key", test_gcm_authentication);
        add_test("SP800_38D_tag_is_128_bits", test_gcm_tag_size);
        add_test("SP800_38D_iv_is_96_bits", test_gcm_iv_size);
        add_test("SP800_38D_empty_plaintext_produces_only_overhead", test_gcm_empty_plaintext);
        // RFC 5116: IND-CPA (ciphertext indistinguishability)
        add_test("RFC5116_ind_cpa_different_nonces", test_ind_cpa);
        add_test("RFC5116_ciphertext_not_plaintext", test_ciphertext_not_plaintext);
        // NIST SP 800-132: PBKDF2 key derivation
        add_test("SP800_132_same_password_cross_instance_decrypt", test_cross_instance_decrypt);
        add_test("SP800_132_unicode_password_roundtrip", test_unicode_password);
        // NIST SP 800-38D: AES-GCM robustness
        add_test("SP800_38D_reject_truncated_ciphertext", test_reject_truncated);
        add_test("SP800_38D_reject_corrupted_tag", test_reject_corrupted_tag);
        add_test("SP800_38D_large_plaintext_64KB_roundtrip", test_large_plaintext);
        // Legacy format fallback (pre-v1.1.2.7 compatibility)
        add_test("LEGACY_fallback_decrypt_data_roundtrip", test_legacy_fallback_decrypt_data);
        add_test("LEGACY_fallback_sets_flag", test_legacy_fallback_sets_flag);
        add_test("LEGACY_current_format_clears_flag", test_current_format_clears_flag);
        add_test("LEGACY_fallback_wrong_password_rejects", test_legacy_wrong_password);
        add_test("LEGACY_fallback_cross_instance", test_legacy_cross_instance);
        // Stream encrypt/decrypt roundtrip
        add_test("SP800_38D_stream_encrypt_decrypt_roundtrip", test_stream_roundtrip_sync);
        add_test("SP800_38D_stream_large_64KB_roundtrip", test_stream_large_roundtrip_sync);
        add_test("SP800_38D_stream_wrong_password_rejects", test_stream_wrong_password_sync);
    }

    /**
     * NIST SP 800-38D §7: AES-GCM ciphertext length MUST equal plaintext length.
     * The output format is SALT(16) + IV(12) + CT(N) + TAG(16), so
     * total output = plaintext.length + 44.
     */
    private void test_gcm_ciphertext_length() {
        try {
            var enc = new FileEncryption("test-password");
            int[] sizes = {0, 1, 15, 16, 17, 255, 1024};
            foreach (int size in sizes) {
                uint8[] pt = new uint8[size];
                for (int i = 0; i < size; i++) pt[i] = (uint8)(i & 0xFF);
                uint8[] ct = enc.encrypt_data(pt);

                int expected_len = OVERHEAD + size;
                if (ct.length != expected_len) {
                    fail_if(true, @"NIST SP 800-38D violation: plaintext=$size, expected output=$expected_len, got=$(ct.length)");
                    return;
                }
            }
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * NIST SP 800-38D §7.2: GCM decryption MUST reject ciphertext
     * encrypted under a different key (authentication failure).
     */
    private void test_gcm_authentication() {
        try {
            var enc1 = new FileEncryption("correct-password");
            var enc2 = new FileEncryption("wrong-password");

            uint8[] ct = enc1.encrypt_data("Secret data".data);
            try {
                enc2.decrypt_data(ct);
                fail_if(true, "NIST SP 800-38D: Decryption with wrong key MUST fail (tag mismatch)");
            } catch (Error e) {
                // Expected: authentication tag verification failure
                assert_true(true);
            }
        } catch (Error e) {
            fail_if_reached(@"Setup error: $(e.message)");
        }
    }

    /**
     * NIST SP 800-38D §5.2.1.2: Tag length for AES-256-GCM SHOULD be 128 bits (16 bytes).
     * The last 16 bytes of output are the tag.
     */
    private void test_gcm_tag_size() {
        try {
            var enc = new FileEncryption("pw");
            uint8[] ct = enc.encrypt_data("test".data);

            // Format: SALT(16) + IV(12) + CT(4) + TAG(16) = 48
            assert_true(ct.length == OVERHEAD + 4);

            // Flip a bit in the tag region (last 16 bytes)
            uint8[] corrupted = new uint8[ct.length];
            Memory.copy(corrupted, ct, ct.length);
            corrupted[ct.length - 1] ^= 0x01;

            try {
                enc.decrypt_data(corrupted);
                fail_if(true, "SP 800-38D: Corrupted 128-bit tag must be rejected");
            } catch (Error e) {
                assert_true(true);
            }
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * NIST SP 800-38D §8.2: IV for AES-GCM SHOULD be 96 bits (12 bytes).
     * Bytes [SALT_SIZE .. SALT_SIZE+12) are the IV. They should be random.
     */
    private void test_gcm_iv_size() {
        try {
            var enc = new FileEncryption("pw");
            uint8[] ct1 = enc.encrypt_data("same".data);
            uint8[] ct2 = enc.encrypt_data("same".data);

            // IVs at bytes [16..28) must differ between encryptions
            bool iv_differs = false;
            for (int i = SALT_SIZE; i < SALT_SIZE + IV_SIZE; i++) {
                if (ct1[i] != ct2[i]) { iv_differs = true; break; }
            }
            fail_if(!iv_differs, "SP 800-38D §8.2: Each encryption MUST use a unique 96-bit IV");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * NIST SP 800-38D: Empty plaintext produces only overhead.
     * Output = SALT(16) + IV(12) + TAG(16) = 44 bytes, zero ciphertext bytes.
     */
    private void test_gcm_empty_plaintext() {
        try {
            var enc = new FileEncryption("pw");
            uint8[] ct = enc.encrypt_data({});
            if (ct.length != OVERHEAD) {
                fail_if(true, @"SP 800-38D: Empty plaintext must produce exactly $(OVERHEAD) bytes, got $(ct.length)");
                return;
            }
            uint8[] dec = enc.decrypt_data(ct);
            assert_true(dec.length == 0);
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * RFC 5116 §5.1 (AEAD_AES_256_GCM): Same plaintext encrypted twice
     * MUST produce different ciphertexts (IND-CPA property).
     * Guaranteed by random salt + random IV.
     */
    private void test_ind_cpa() {
        try {
            var enc = new FileEncryption("same-password");
            uint8[] pt = "Same input".data;
            uint8[] ct1 = enc.encrypt_data(pt);
            uint8[] ct2 = enc.encrypt_data(pt);

            bool differ = false;
            if (ct1.length != ct2.length) { differ = true; }
            else {
                for (int i = 0; i < ct1.length; i++) {
                    if (ct1[i] != ct2[i]) { differ = true; break; }
                }
            }
            fail_if(!differ, "RFC 5116: Two encryptions of same plaintext MUST produce different output (IND-CPA)");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * RFC 5116: Ciphertext portion must not contain plaintext.
     * CT bytes are at offset [SALT_SIZE+IV_SIZE .. length-TAG_SIZE).
     */
    private void test_ciphertext_not_plaintext() {
        try {
            var enc = new FileEncryption("pw");
            uint8[] pt = "This must not appear in ciphertext".data;
            uint8[] ct = enc.encrypt_data(pt);

            // Check that the ciphertext region doesn't match plaintext
            int ct_start = SALT_SIZE + IV_SIZE;
            bool all_same = true;
            for (int i = 0; i < pt.length; i++) {
                if (ct[ct_start + i] != pt[i]) { all_same = false; break; }
            }
            fail_if(all_same, "RFC 5116: Ciphertext must not equal plaintext (encryption not applied)");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * NIST SP 800-132: Same password + embedded salt → same derived key.
     * Two FileEncryption instances with same password MUST cross-decrypt
     * (salt is embedded in ciphertext, not per-instance).
     */
    private void test_cross_instance_decrypt() {
        try {
            var enc1 = new FileEncryption("deterministic-test");
            var enc2 = new FileEncryption("deterministic-test");
            uint8[] pt = "Cross-instance decryption must work".data;
            uint8[] ct = enc1.encrypt_data(pt);
            uint8[] dec = enc2.decrypt_data(ct);

            assert_true(dec.length == pt.length);
            for (int i = 0; i < pt.length; i++) {
                if (pt[i] != dec[i]) {
                    fail_if(true, @"SP 800-132: Cross-instance decrypt byte mismatch at pos $i");
                    return;
                }
            }
        } catch (Error e) {
            fail_if_reached(@"SP 800-132: Cross-instance decrypt failed: $(e.message)");
        }
    }

    /**
     * NIST SP 800-132 §5.3: PBKDF2 MUST handle arbitrary-length passwords
     * including multi-byte UTF-8 characters.
     */
    private void test_unicode_password() {
        try {
            string pw = "パスワード🔐Tëst";
            var enc = new FileEncryption(pw);
            uint8[] pt = "Unicode password test data".data;
            uint8[] ct = enc.encrypt_data(pt);
            uint8[] dec = enc.decrypt_data(ct);

            string result = (string) dec;
            fail_if(result != "Unicode password test data",
                    "SP 800-132: Unicode password roundtrip failed");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    /**
     * Robustness: Data shorter than OVERHEAD (44 bytes) MUST be rejected.
     * Format requires at least SALT(16) + IV(12) + TAG(16).
     */
    private void test_reject_truncated() {
        var enc = new FileEncryption("pw");
        uint8[] short_data = {1, 2, 3, 4, 5};

        try {
            enc.decrypt_data(short_data);
            fail_if(true, "Truncated data (<44 bytes) MUST be rejected");
        } catch (Error e) {
            assert_true(true);
        }
    }

    /**
     * NIST SP 800-38D §7.2: Corrupted authentication tag MUST cause
     * decryption to fail. Verifies that tag integrity check works.
     */
    private void test_reject_corrupted_tag() {
        try {
            var enc = new FileEncryption("pw");
            uint8[] ct = enc.encrypt_data("important data".data);

            // Corrupt the GCM tag (last 16 bytes)
            uint8[] corrupted = new uint8[ct.length];
            Memory.copy(corrupted, ct, ct.length);
            for (int i = ct.length - TAG_SIZE; i < ct.length; i++) {
                corrupted[i] ^= 0xFF;
            }

            try {
                enc.decrypt_data(corrupted);
                fail_if(true, "SP 800-38D: Corrupted tag MUST be rejected");
            } catch (Error e) {
                assert_true(true);
            }
        } catch (Error e) {
            fail_if_reached(@"Setup error: $(e.message)");
        }
    }

    /**
     * NIST SP 800-38D: AES-GCM must handle large inputs (multi-block).
     * GCM uses GHASH which processes 128-bit blocks. 64KB = 4096 blocks.
     */
    private void test_large_plaintext() {
        try {
            var enc = new FileEncryption("large-data-pw");
            uint8[] pt = new uint8[65536];
            for (int i = 0; i < pt.length; i++) pt[i] = (uint8)(i & 0xFF);

            uint8[] ct = enc.encrypt_data(pt);
            // Verify format: output = 44 + 65536
            if (ct.length != OVERHEAD + 65536) {
                fail_if(true, @"SP 800-38D: 64KB plaintext should produce $(OVERHEAD + 65536) output, got $(ct.length)");
                return;
            }

            uint8[] dec = enc.decrypt_data(ct);
            assert_true(dec.length == pt.length);
            for (int i = 0; i < pt.length; i++) {
                if (pt[i] != dec[i]) {
                    fail_if(true, @"SP 800-38D: 64KB roundtrip byte mismatch at pos $i");
                    return;
                }
            }
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    // ===== Legacy Format Fallback Tests (pre-v1.1.2.7 compatibility) =====

    /**
     * Legacy format: SALT(8) + IV(16) + CT + TAG(8) = 32 bytes overhead.
     * decrypt_data() MUST transparently fall back when current format fails.
     */
    private void test_legacy_fallback_decrypt_data() {
        try {
            var enc = new FileEncryption("legacy-test-pw");
            uint8[] pt = "Legacy encrypted data from old DinoX".data;

            // Encrypt in legacy format (simulates pre-v1.1.2.7 data)
            uint8[] ct_legacy = enc.encrypt_data_legacy(pt);

            // Legacy overhead = 8 + 16 + 8 = 32
            if (ct_legacy.length != 32 + pt.length) {
                fail_if(true, @"Legacy format overhead wrong: expected $(32 + pt.length), got $(ct_legacy.length)");
                return;
            }

            // decrypt_data MUST handle this via fallback
            uint8[] dec = enc.decrypt_data(ct_legacy);

            assert_true(dec.length == pt.length);
            for (int i = 0; i < pt.length; i++) {
                if (pt[i] != dec[i]) {
                    fail_if(true, @"Legacy fallback byte mismatch at pos $i");
                    return;
                }
            }
        } catch (Error e) {
            fail_if_reached(@"Legacy fallback decrypt failed: $(e.message)");
        }
    }

    /**
     * After decrypting legacy data, last_decrypt_used_legacy MUST be true.
     */
    private void test_legacy_fallback_sets_flag() {
        try {
            var enc = new FileEncryption("flag-test-pw");
            uint8[] pt = "Flag test".data;
            uint8[] ct_legacy = enc.encrypt_data_legacy(pt);
            enc.decrypt_data(ct_legacy);

            fail_if(!enc.last_decrypt_used_legacy,
                    "last_decrypt_used_legacy MUST be true after legacy fallback");
        } catch (Error e) {
            fail_if_reached(@"Error: $(e.message)");
        }
    }

    /**
     * After decrypting current-format data, last_decrypt_used_legacy MUST be false.
     */
    private void test_current_format_clears_flag() {
        try {
            var enc = new FileEncryption("flag-test-pw");
            uint8[] pt = "Current format".data;

            // First decrypt legacy to set the flag
            uint8[] ct_legacy = enc.encrypt_data_legacy(pt);
            enc.decrypt_data(ct_legacy);
            assert_true(enc.last_decrypt_used_legacy);

            // Now decrypt current format — flag must be cleared
            uint8[] ct_current = enc.encrypt_data(pt);
            enc.decrypt_data(ct_current);

            fail_if(enc.last_decrypt_used_legacy,
                    "last_decrypt_used_legacy MUST be false after current-format decrypt");
        } catch (Error e) {
            fail_if_reached(@"Error: $(e.message)");
        }
    }

    /**
     * Legacy-format data encrypted with password A MUST be rejected by password B.
     * Both current and legacy format attempts must fail.
     */
    private void test_legacy_wrong_password() {
        try {
            var enc_a = new FileEncryption("password-A");
            var enc_b = new FileEncryption("password-B");
            uint8[] pt = "Secret".data;
            uint8[] ct_legacy = enc_a.encrypt_data_legacy(pt);

            try {
                enc_b.decrypt_data(ct_legacy);
                fail_if(true, "Legacy data with wrong password MUST be rejected");
            } catch (Error e) {
                // Expected
                assert_true(true);
            }
        } catch (Error e) {
            fail_if_reached(@"Setup error: $(e.message)");
        }
    }

    /**
     * Legacy-format data MUST be decryptable by a different FileEncryption
     * instance with the same password (cross-instance, same as current format).
     */
    private void test_legacy_cross_instance() {
        try {
            var enc1 = new FileEncryption("cross-legacy");
            var enc2 = new FileEncryption("cross-legacy");
            uint8[] pt = "Cross-instance legacy".data;
            uint8[] ct_legacy = enc1.encrypt_data_legacy(pt);
            uint8[] dec = enc2.decrypt_data(ct_legacy);

            assert_true(dec.length == pt.length);
            string result = (string) dec;
            fail_if(result != "Cross-instance legacy",
                    "Cross-instance legacy decrypt mismatch");
        } catch (Error e) {
            fail_if_reached(@"Error: $(e.message)");
        }
    }

    // ===== Stream Encrypt/Decrypt Tests =====

    /** Helper: run an async function synchronously via MainLoop. */
    private delegate void AsyncRunner();
    private static void run_async(owned AsyncRunner runner) {
        var loop = new MainLoop();
        runner();
        loop.quit();
    }

    /**
     * encrypt_stream + decrypt_stream roundtrip MUST reproduce plaintext.
     * Tests the streaming GCM tag holdback logic.
     */
    private void test_stream_roundtrip_sync() {
        var loop = new MainLoop();
        test_stream_roundtrip.begin((obj, res) => {
            test_stream_roundtrip.end(res);
            loop.quit();
        });
        loop.run();
    }

    private async void test_stream_roundtrip() {
        try {
            var enc = new FileEncryption("stream-test-pw");
            uint8[] pt = "Stream encryption roundtrip test data with some content".data;

            // Encrypt to memory
            var pt_stream = new MemoryInputStream.from_data(pt);
            var ct_out = new MemoryOutputStream.resizable();
            yield enc.encrypt_stream(pt_stream, ct_out, null);
            ct_out.close();

            // Decrypt from memory
            uint8[] ct_data = ct_out.steal_data();
            ct_data.length = (int) ct_out.get_data_size();
            var ct_stream = new MemoryInputStream.from_data(ct_data);
            var dec_out = new MemoryOutputStream.resizable();
            yield enc.decrypt_stream(ct_stream, dec_out, null);
            dec_out.close();

            uint8[] dec_data = dec_out.steal_data();
            dec_data.length = (int) dec_out.get_data_size();

            if (dec_data.length != pt.length) {
                fail_if(true, @"Stream roundtrip length mismatch: expected $(pt.length), got $(dec_data.length)");
                return;
            }
            for (int i = 0; i < pt.length; i++) {
                if (pt[i] != dec_data[i]) {
                    fail_if(true, @"Stream roundtrip byte mismatch at pos $i");
                    return;
                }
            }
        } catch (Error e) {
            fail_if_reached(@"Stream roundtrip error: $(e.message)");
        }
    }

    /**
     * Stream encrypt/decrypt with 64KB data (multi-block GCM, multi-chunk stream).
     * Exercises the tag holdback buffer logic across many read iterations.
     */
    private void test_stream_large_roundtrip_sync() {
        var loop = new MainLoop();
        test_stream_large_roundtrip.begin((obj, res) => {
            test_stream_large_roundtrip.end(res);
            loop.quit();
        });
        loop.run();
    }

    private async void test_stream_large_roundtrip() {
        try {
            var enc = new FileEncryption("stream-large-pw");
            uint8[] pt = new uint8[65536];
            for (int i = 0; i < pt.length; i++) pt[i] = (uint8)(i & 0xFF);

            var pt_stream = new MemoryInputStream.from_data(pt);
            var ct_out = new MemoryOutputStream.resizable();
            yield enc.encrypt_stream(pt_stream, ct_out, null);
            ct_out.close();

            uint8[] ct_data = ct_out.steal_data();
            ct_data.length = (int) ct_out.get_data_size();
            var ct_stream = new MemoryInputStream.from_data(ct_data);
            var dec_out = new MemoryOutputStream.resizable();
            yield enc.decrypt_stream(ct_stream, dec_out, null);
            dec_out.close();

            uint8[] dec_data = dec_out.steal_data();
            dec_data.length = (int) dec_out.get_data_size();

            if (dec_data.length != pt.length) {
                fail_if(true, @"Stream 64KB length mismatch: expected $(pt.length), got $(dec_data.length)");
                return;
            }
            for (int i = 0; i < pt.length; i++) {
                if (pt[i] != dec_data[i]) {
                    fail_if(true, @"Stream 64KB byte mismatch at pos $i");
                    return;
                }
            }
        } catch (Error e) {
            fail_if_reached(@"Stream 64KB error: $(e.message)");
        }
    }

    /**
     * Stream decrypt with wrong password MUST fail (GCM tag mismatch).
     */
    private void test_stream_wrong_password_sync() {
        var loop = new MainLoop();
        test_stream_wrong_password.begin((obj, res) => {
            test_stream_wrong_password.end(res);
            loop.quit();
        });
        loop.run();
    }

    private async void test_stream_wrong_password() {
        try {
            var enc1 = new FileEncryption("correct-stream-pw");
            var enc2 = new FileEncryption("wrong-stream-pw");
            uint8[] pt = "Secret stream data".data;

            // Encrypt
            var pt_stream = new MemoryInputStream.from_data(pt);
            var ct_out = new MemoryOutputStream.resizable();
            yield enc1.encrypt_stream(pt_stream, ct_out, null);
            ct_out.close();

            // Decrypt with wrong password
            uint8[] ct_data = ct_out.steal_data();
            ct_data.length = (int) ct_out.get_data_size();
            var ct_stream = new MemoryInputStream.from_data(ct_data);
            var dec_out = new MemoryOutputStream.resizable();
            try {
                yield enc2.decrypt_stream(ct_stream, dec_out, null);
                fail_if(true, "Stream decrypt with wrong password MUST fail");
            } catch (Error e) {
                // Expected: tag mismatch
                assert_true(true);
            }
        } catch (Error e) {
            fail_if_reached(@"Setup error: $(e.message)");
        }
    }
}

}
