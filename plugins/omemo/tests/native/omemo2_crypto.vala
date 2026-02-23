/**
 * Security audit tests for OMEMO 2 encrypt/decrypt pipeline.
 *
 * Tests omemo2_encrypt_payload() and omemo2_decrypt_payload() —
 * the pure crypto core: HKDF-SHA-256 → AES-256-CBC-PKCS7 → HMAC-SHA-256.
 *
 * XEP-0384 v0.8 Section 4:
 *   mk = random 32 bytes
 *   HKDF(mk, salt=32_zeros, info="OMEMO Payload") → enc_key[32] | auth_key[32] | iv[16]
 *   ciphertext = AES-256-CBC-PKCS7(enc_key, iv, SCE_plaintext)
 *   auth_tag = HMAC-SHA-256(auth_key, ciphertext)[0:16]
 *   message_key = mk || auth_tag  (48 bytes)
 */

namespace Omemo.Test {

class Omemo2CryptoTest : Gee.TestCase {

    public Omemo2CryptoTest() {
        base("Omemo2Crypto");

        /* Roundtrip */
        add_test("XEP0384v08_encrypt_decrypt_roundtrip", test_roundtrip);
        add_test("XEP0384v08_roundtrip_empty_plaintext", test_roundtrip_empty);
        add_test("XEP0384v08_roundtrip_large_plaintext", test_roundtrip_large);

        /* Output format */
        add_test("XEP0384v08_mk_with_tag_is_48_bytes", test_mk_tag_length);
        add_test("XEP0384v08_ciphertext_padded_to_block", test_ciphertext_padded);

        /* Determinism */
        add_test("XEP0384v08_same_mk_same_plaintext_same_output", test_deterministic);
        add_test("XEP0384v08_different_mk_different_ciphertext", test_different_mk);

        /* HMAC integrity */
        add_test("XEP0384v08_tampered_ciphertext_fails_hmac", test_tampered_ciphertext);
        add_test("XEP0384v08_tampered_tag_fails_hmac", test_tampered_tag);
        add_test("XEP0384v08_truncated_mk_and_tag_rejected", test_truncated_key);

        /* Edge cases */
        add_test("XEP0384v08_single_byte_plaintext", test_single_byte);
        add_test("XEP0384v08_exactly_16_byte_plaintext", test_block_aligned);
    }

    /* ===== Helpers ===== */

    private uint8[] make_mk(uint8 fill = 0x42) {
        uint8[] mk = new uint8[32];
        for (int i = 0; i < 32; i++) mk[i] = fill;
        return mk;
    }

    private uint8[] make_plaintext(string s) {
        return s.data;
    }

    /* ===== Roundtrip tests ===== */

    /**
     * XEP-0384 v0.8 S4: encrypt then decrypt must recover original plaintext.
     */
    private void test_roundtrip() {
        uint8[] mk = make_mk(0xAA);
        uint8[] plain = make_plaintext("Hello OMEMO 2!");
        try {
            uint8[] ct;
            uint8[] mk_tag;
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk, plain, out ct, out mk_tag);

            uint8[] recovered = Dino.Plugins.Omemo.Omemo2Decrypt.omemo2_decrypt_payload(ct, mk_tag);

            fail_if_not_eq_int(recovered.length, plain.length,
                "XEP-0384: roundtrip must recover same length");
            for (int i = 0; i < plain.length; i++) {
                if (recovered[i] != plain[i]) {
                    GLib.Test.message("XEP-0384: roundtrip byte mismatch at index %d: got 0x%02x, expected 0x%02x", i, recovered[i], plain[i]);
                    GLib.Test.fail();
                    return;
                }
            }
        } catch (GLib.Error e) {
            GLib.Test.message("XEP-0384: roundtrip threw: %s", e.message);
            GLib.Test.fail();
        }
    }

    /**
     * XEP-0384 v0.8: Empty plaintext must roundtrip (PKCS7 pads to 16 bytes).
     */
    private void test_roundtrip_empty() {
        uint8[] mk = make_mk(0xBB);
        uint8[] plain = {};
        try {
            uint8[] ct;
            uint8[] mk_tag;
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk, plain, out ct, out mk_tag);
            uint8[] recovered = Dino.Plugins.Omemo.Omemo2Decrypt.omemo2_decrypt_payload(ct, mk_tag);
            fail_if_not_eq_int(recovered.length, 0,
                "XEP-0384: empty plaintext must roundtrip to empty");
        } catch (GLib.Error e) {
            GLib.Test.message("XEP-0384: empty roundtrip threw: %s", e.message);
            GLib.Test.fail();
        }
    }

    /**
     * XEP-0384 v0.8: Large plaintext (4 KB) must roundtrip.
     */
    private void test_roundtrip_large() {
        uint8[] mk = make_mk(0xCC);
        uint8[] plain = new uint8[4096];
        for (int i = 0; i < 4096; i++) plain[i] = (uint8)(i & 0xFF);
        try {
            uint8[] ct;
            uint8[] mk_tag;
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk, plain, out ct, out mk_tag);
            uint8[] recovered = Dino.Plugins.Omemo.Omemo2Decrypt.omemo2_decrypt_payload(ct, mk_tag);
            fail_if_not_eq_int(recovered.length, 4096,
                "XEP-0384: 4KB plaintext must roundtrip");
            for (int i = 0; i < 4096; i++) {
                if (recovered[i] != plain[i]) {
                    GLib.Test.message("XEP-0384: 4KB roundtrip mismatch at %d", i);
                    GLib.Test.fail();
                    return;
                }
            }
        } catch (GLib.Error e) {
            GLib.Test.message("XEP-0384: 4KB roundtrip threw: %s", e.message);
            GLib.Test.fail();
        }
    }

    /* ===== Output format ===== */

    /**
     * XEP-0384 v0.8 S4: mk_with_tag must be exactly 48 bytes (32 mk + 16 HMAC).
     */
    private void test_mk_tag_length() {
        uint8[] mk = make_mk(0xDD);
        uint8[] plain = make_plaintext("test");
        try {
            uint8[] ct;
            uint8[] mk_tag;
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk, plain, out ct, out mk_tag);
            fail_if_not_eq_int(mk_tag.length, 48,
                "XEP-0384: mk_with_tag must be 48 bytes (32+16)");
            // First 32 bytes must be the original mk
            for (int i = 0; i < 32; i++) {
                if (mk_tag[i] != mk[i]) {
                    GLib.Test.message("XEP-0384: mk_tag[%d] = 0x%02x, expected mk[%d] = 0x%02x", i, mk_tag[i], i, mk[i]);
                    GLib.Test.fail();
                    return;
                }
            }
        } catch (GLib.Error e) {
            GLib.Test.message("XEP-0384: %s", e.message);
            GLib.Test.fail();
        }
    }

    /**
     * XEP-0384 v0.8: AES-256-CBC with PKCS7 padding produces ciphertext
     * that is a multiple of 16 bytes and at least plaintext.length + 1.
     */
    private void test_ciphertext_padded() {
        uint8[] mk = make_mk(0xEE);
        uint8[] plain = make_plaintext("exactly15chars!");  // 15 bytes
        try {
            uint8[] ct;
            uint8[] mk_tag;
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk, plain, out ct, out mk_tag);
            fail_if(ct.length % 16 != 0,
                "XEP-0384: ciphertext must be multiple of 16 (AES block size)");
            fail_if(ct.length < plain.length,
                "XEP-0384: ciphertext must be >= plaintext length");
        } catch (GLib.Error e) {
            GLib.Test.message("XEP-0384: %s", e.message);
            GLib.Test.fail();
        }
    }

    /* ===== Determinism ===== */

    /**
     * XEP-0384 v0.8: Same mk + same plaintext must produce identical output.
     * (The pipeline has no RNG — IV is derived from HKDF.)
     */
    private void test_deterministic() {
        uint8[] mk = make_mk(0x11);
        uint8[] plain = make_plaintext("deterministic");
        try {
            uint8[] ct1, ct2;
            uint8[] mk_tag1, mk_tag2;
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk, plain, out ct1, out mk_tag1);
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk, plain, out ct2, out mk_tag2);
            fail_if_not_eq_int(ct1.length, ct2.length,
                "XEP-0384: deterministic encrypt must produce same ciphertext length");
            for (int i = 0; i < ct1.length; i++) {
                if (ct1[i] != ct2[i]) {
                    GLib.Test.message("XEP-0384: ciphertext mismatch at %d", i);
                    GLib.Test.fail();
                    return;
                }
            }
        } catch (GLib.Error e) {
            GLib.Test.message("XEP-0384: %s", e.message);
            GLib.Test.fail();
        }
    }

    /**
     * XEP-0384 v0.8: Different mk must produce different ciphertext
     * (different HKDF output → different enc_key → different ciphertext).
     */
    private void test_different_mk() {
        uint8[] mk1 = make_mk(0x11);
        uint8[] mk2 = make_mk(0x22);
        uint8[] plain = make_plaintext("same plaintext");
        try {
            uint8[] ct1, ct2;
            uint8[] mk_tag1, mk_tag2;
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk1, plain, out ct1, out mk_tag1);
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk2, plain, out ct2, out mk_tag2);
            // At least one byte must differ
            bool all_same = true;
            int min_len = ct1.length < ct2.length ? ct1.length : ct2.length;
            for (int i = 0; i < min_len; i++) {
                if (ct1[i] != ct2[i]) { all_same = false; break; }
            }
            if (ct1.length != ct2.length) all_same = false;
            fail_if(all_same,
                "XEP-0384: different mk must produce different ciphertext");
        } catch (GLib.Error e) {
            GLib.Test.message("XEP-0384: %s", e.message);
            GLib.Test.fail();
        }
    }

    /* ===== HMAC integrity ===== */

    /**
     * XEP-0384 v0.8: Tampered ciphertext must fail HMAC verification.
     */
    private void test_tampered_ciphertext() {
        uint8[] mk = make_mk(0x33);
        uint8[] plain = make_plaintext("tamper test");
        try {
            uint8[] ct;
            uint8[] mk_tag;
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk, plain, out ct, out mk_tag);
            // Flip one bit in ciphertext
            ct[0] ^= 0x01;
            try {
                Dino.Plugins.Omemo.Omemo2Decrypt.omemo2_decrypt_payload(ct, mk_tag);
                GLib.Test.message("XEP-0384: tampered ciphertext must fail HMAC");
                GLib.Test.fail();
            } catch (GLib.Error e) {
                // Expected — HMAC verification failed
                fail_if(!e.message.contains("HMAC"),
                    "XEP-0384: error must mention HMAC");
            }
        } catch (GLib.Error e) {
            GLib.Test.message("XEP-0384: encrypt threw: %s", e.message);
            GLib.Test.fail();
        }
    }

    /**
     * XEP-0384 v0.8: Tampered auth tag must fail HMAC verification.
     */
    private void test_tampered_tag() {
        uint8[] mk = make_mk(0x44);
        uint8[] plain = make_plaintext("tag tamper test");
        try {
            uint8[] ct;
            uint8[] mk_tag;
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk, plain, out ct, out mk_tag);
            // Flip one bit in auth tag (bytes 32-47)
            mk_tag[40] ^= 0x01;
            try {
                Dino.Plugins.Omemo.Omemo2Decrypt.omemo2_decrypt_payload(ct, mk_tag);
                GLib.Test.message("XEP-0384: tampered auth tag must fail HMAC");
                GLib.Test.fail();
            } catch (GLib.Error e) {
                fail_if(!e.message.contains("HMAC"),
                    "XEP-0384: error must mention HMAC");
            }
        } catch (GLib.Error e) {
            GLib.Test.message("XEP-0384: encrypt threw: %s", e.message);
            GLib.Test.fail();
        }
    }

    /**
     * XEP-0384 v0.8: mk_and_tag shorter than 48 bytes must be rejected.
     */
    private void test_truncated_key() {
        uint8[] mk = make_mk(0x55);
        uint8[] plain = make_plaintext("truncate test");
        try {
            uint8[] ct;
            uint8[] mk_tag;
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk, plain, out ct, out mk_tag);
            // Truncate mk_tag to 30 bytes
            uint8[] short_key = mk_tag[0:30];
            try {
                Dino.Plugins.Omemo.Omemo2Decrypt.omemo2_decrypt_payload(ct, short_key);
                GLib.Test.message("XEP-0384: truncated key must be rejected");
                GLib.Test.fail();
            } catch (GLib.Error e) {
                fail_if(!e.message.contains("too short"),
                    "XEP-0384: error must mention 'too short'");
            }
        } catch (GLib.Error e) {
            GLib.Test.message("XEP-0384: encrypt threw: %s", e.message);
            GLib.Test.fail();
        }
    }

    /* ===== Edge cases ===== */

    /**
     * XEP-0384 v0.8: Single-byte plaintext must encrypt and roundtrip.
     * PKCS7 pads 1 byte to 16 bytes.
     */
    private void test_single_byte() {
        uint8[] mk = make_mk(0x66);
        uint8[] plain = { 0x42 };
        try {
            uint8[] ct;
            uint8[] mk_tag;
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk, plain, out ct, out mk_tag);
            fail_if_not_eq_int(ct.length, 16,
                "XEP-0384: 1-byte plaintext must pad to 16 bytes ciphertext");
            uint8[] recovered = Dino.Plugins.Omemo.Omemo2Decrypt.omemo2_decrypt_payload(ct, mk_tag);
            fail_if_not_eq_int(recovered.length, 1,
                "XEP-0384: 1-byte roundtrip length");
            fail_if(recovered[0] != 0x42,
                "XEP-0384: 1-byte roundtrip value");
        } catch (GLib.Error e) {
            GLib.Test.message("XEP-0384: %s", e.message);
            GLib.Test.fail();
        }
    }

    /**
     * XEP-0384 v0.8: Exactly 16-byte plaintext (block-aligned).
     * PKCS7 adds a full 16-byte padding block → 32 bytes ciphertext.
     */
    private void test_block_aligned() {
        uint8[] mk = make_mk(0x77);
        uint8[] plain = new uint8[16];
        for (int i = 0; i < 16; i++) plain[i] = (uint8)i;
        try {
            uint8[] ct;
            uint8[] mk_tag;
            Dino.Plugins.Omemo.Omemo2Encrypt.omemo2_encrypt_payload(mk, plain, out ct, out mk_tag);
            fail_if_not_eq_int(ct.length, 32,
                "XEP-0384: 16-byte plaintext with PKCS7 must produce 32 bytes");
            uint8[] recovered = Dino.Plugins.Omemo.Omemo2Decrypt.omemo2_decrypt_payload(ct, mk_tag);
            fail_if_not_eq_int(recovered.length, 16,
                "XEP-0384: 16-byte roundtrip length");
        } catch (GLib.Error e) {
            GLib.Test.message("XEP-0384: %s", e.message);
            GLib.Test.fail();
        }
    }
}

}
