using Dino.Security;

namespace Dino.Test {

/**
 * Tests for FileEncryption: AES-256-GCM encrypt/decrypt round-trips.
 * Verifies data integrity, wrong-password rejection, and edge cases.
 */
class SecurityTest : Gee.TestCase {

    public SecurityTest() {
        base("Security");
        add_test("encrypt_decrypt_roundtrip", test_encrypt_decrypt_roundtrip);
        add_test("encrypt_decrypt_empty", test_encrypt_decrypt_empty);
        add_test("encrypt_decrypt_large", test_encrypt_decrypt_large);
        add_test("encrypt_decrypt_unicode_password", test_encrypt_decrypt_unicode_password);
        add_test("wrong_password_fails", test_wrong_password_fails);
        add_test("ciphertext_differs_from_plaintext", test_ciphertext_differs_from_plaintext);
        add_test("two_encryptions_differ", test_two_encryptions_differ);
        add_test("data_too_short_fails", test_data_too_short_fails);
        add_test("deterministic_key_derivation", test_deterministic_key_derivation);
    }

    private void test_encrypt_decrypt_roundtrip() {
        string password = "test-password-123";
        string message = "Hello, DinoX! This is a secret message.";

        try {
            var enc = new FileEncryption(password);
            uint8[] plaintext = message.data;
            uint8[] encrypted = enc.encrypt_data(plaintext);
            uint8[] decrypted = enc.decrypt_data(encrypted);

            // Verify round-trip
            assert_true(decrypted.length == plaintext.length);
            for (int i = 0; i < plaintext.length; i++) {
                if (plaintext[i] != decrypted[i]) {
                    fail_if(true, @"Byte mismatch at position $i");
                    return;
                }
            }
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    private void test_encrypt_decrypt_empty() {
        try {
            var enc = new FileEncryption("password");
            uint8[] empty = {};
            uint8[] encrypted = enc.encrypt_data(empty);

            // Encrypted should contain at least IV (12) + Tag (16) = 28 bytes
            assert_true(encrypted.length >= 28);

            uint8[] decrypted = enc.decrypt_data(encrypted);
            assert_true(decrypted.length == 0);
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    private void test_encrypt_decrypt_large() {
        try {
            var enc = new FileEncryption("large-data-pw");

            // 64 KB of data
            uint8[] data = new uint8[65536];
            for (int i = 0; i < data.length; i++) {
                data[i] = (uint8)(i & 0xFF);
            }

            uint8[] encrypted = enc.encrypt_data(data);
            uint8[] decrypted = enc.decrypt_data(encrypted);

            assert_true(decrypted.length == data.length);
            for (int i = 0; i < data.length; i++) {
                if (data[i] != decrypted[i]) {
                    fail_if(true, @"Byte mismatch at position $i in 64KB data");
                    return;
                }
            }
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    private void test_encrypt_decrypt_unicode_password() {
        try {
            string unicode_pw = "パスワード🔐Tëst";
            var enc = new FileEncryption(unicode_pw);
            uint8[] data = "Unicode password test data".data;

            uint8[] encrypted = enc.encrypt_data(data);
            uint8[] decrypted = enc.decrypt_data(encrypted);

            assert_true(decrypted.length == data.length);
            string result = (string) decrypted;
            fail_if(result != "Unicode password test data", "Unicode pw round-trip failed");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    private void test_wrong_password_fails() {
        try {
            var enc1 = new FileEncryption("correct-password");
            var enc2 = new FileEncryption("wrong-password");

            uint8[] plaintext = "Secret data".data;
            uint8[] encrypted = enc1.encrypt_data(plaintext);

            // Decrypting with wrong password should fail (GCM tag check)
            try {
                enc2.decrypt_data(encrypted);
                // If we get here, the tag check didn't throw — that's a security bug
                fail_if(true, "Decryption with wrong password should have failed");
            } catch (Error e) {
                // Expected: tag verification failure
                assert_true(true);
            }
        } catch (Error e) {
            fail_if_reached(@"Unexpected error in setup: $(e.message)");
        }
    }

    private void test_ciphertext_differs_from_plaintext() {
        try {
            var enc = new FileEncryption("pw");
            uint8[] plaintext = "This must not appear in ciphertext".data;
            uint8[] encrypted = enc.encrypt_data(plaintext);

            // Ciphertext should be longer (IV + tag overhead)
            assert_true(encrypted.length > plaintext.length);

            // The ciphertext portion (after IV) should differ from plaintext
            bool all_same = true;
            int ct_start = 12; // After IV
            int ct_len = plaintext.length;
            for (int i = 0; i < ct_len && i + ct_start < encrypted.length; i++) {
                if (encrypted[i + ct_start] != plaintext[i]) {
                    all_same = false;
                    break;
                }
            }
            fail_if(all_same, "Ciphertext matches plaintext — encryption broken");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    private void test_two_encryptions_differ() {
        try {
            var enc = new FileEncryption("same-password");
            uint8[] data = "Same input".data;

            uint8[] ct1 = enc.encrypt_data(data);
            uint8[] ct2 = enc.encrypt_data(data);

            // Different random IVs → different ciphertexts
            bool differ = false;
            if (ct1.length != ct2.length) {
                differ = true;
            } else {
                for (int i = 0; i < ct1.length; i++) {
                    if (ct1[i] != ct2[i]) { differ = true; break; }
                }
            }
            fail_if(!differ, "Two encryptions of same data produced identical output — IV reuse bug");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }

    private void test_data_too_short_fails() {
        var enc = new FileEncryption("pw");

        // Less than IV_SIZE (12) + TAG_SIZE (16) = 28 bytes
        uint8[] too_short = {1, 2, 3, 4, 5};

        try {
            enc.decrypt_data(too_short);
            fail_if(true, "Decrypting too-short data should have thrown");
        } catch (Error e) {
            // Expected: "Data too short"
            assert_true(true);
        }
    }

    private void test_deterministic_key_derivation() {
        // Same password must produce same key (deterministic derivation)
        // We test this indirectly: data encrypted with pw A must decrypt with new instance of pw A
        try {
            var enc1 = new FileEncryption("deterministic-test");
            var enc2 = new FileEncryption("deterministic-test");

            uint8[] data = "Key derivation must be deterministic".data;
            uint8[] encrypted = enc1.encrypt_data(data);
            uint8[] decrypted = enc2.decrypt_data(encrypted);

            string result = (string) decrypted;
            fail_if(result != "Key derivation must be deterministic",
                    "Different FileEncryption instances with same password produced different keys");
        } catch (Error e) {
            fail_if_reached(@"Unexpected error: $(e.message)");
        }
    }
}

}
