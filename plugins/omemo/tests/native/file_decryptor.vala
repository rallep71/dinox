/**
 * Security audit tests for OMEMO file decryptor helper functions.
 *
 * Tests the pure functions: is_hex, hex_to_bin, normalize_base64,
 * aesgcm_to_https_link, and the URL→key extraction pipeline.
 *
 * These functions were originally private. Changed to internal static
 * for testability (Bug #15: normalize_base64 rem==1 silently passes).
 */

using Dino.Plugins.Omemo;

namespace Omemo.Test {

class FileDecryptorTest : Gee.TestCase {

    public FileDecryptorTest() {
        base("FileDecryptor");

        /* is_hex */
        add_test("RFC_is_hex_valid_lowercase", test_is_hex_valid_lowercase);
        add_test("RFC_is_hex_valid_uppercase", test_is_hex_valid_uppercase);
        add_test("RFC_is_hex_valid_mixed", test_is_hex_valid_mixed);
        add_test("RFC_is_hex_empty_is_false", test_is_hex_empty_is_false);
        add_test("RFC_is_hex_non_hex_char_false", test_is_hex_non_hex_char_false);
        add_test("RFC_is_hex_space_is_false", test_is_hex_space_is_false);
        add_test("RFC_is_hex_url_safe_base64_is_false", test_is_hex_url_safe_base64);

        /* hex_to_bin */
        add_test("RFC_hex_to_bin_known_vector", test_hex_to_bin_known_vector);
        add_test("RFC_hex_to_bin_empty", test_hex_to_bin_empty);
        add_test("RFC_hex_to_bin_all_ff", test_hex_to_bin_all_ff);
        add_test("RFC_hex_to_bin_all_00", test_hex_to_bin_all_00);

        /* normalize_base64 */
        add_test("RFC4648_normalize_base64_rem_0_unchanged", test_normalize_base64_rem_0);
        add_test("RFC4648_normalize_base64_rem_2_adds_double_pad", test_normalize_base64_rem_2);
        add_test("RFC4648_normalize_base64_rem_3_adds_single_pad", test_normalize_base64_rem_3);
        add_test("RFC4648_normalize_base64_rem_1_is_invalid", test_normalize_base64_rem_1);
        add_test("RFC4648_normalize_base64_url_safe_to_standard", test_normalize_base64_url_safe);
        add_test("RFC4648_normalize_base64_empty_string", test_normalize_base64_empty);

        /* aesgcm → https */
        add_test("XEP0454_aesgcm_to_https_strips_fragment", test_aesgcm_to_https_basic);
        add_test("XEP0454_aesgcm_to_https_preserves_path", test_aesgcm_to_https_path);
        add_test("XEP0454_aesgcm_to_https_non_aesgcm_unchanged", test_aesgcm_to_https_non_aesgcm);
    }

    /* ===== is_hex tests ===== */

    private void test_is_hex_valid_lowercase() {
        fail_if_not(OmemoFileDecryptor.is_hex("0123456789abcdef"),
            "lowercase hex must be accepted");
    }

    private void test_is_hex_valid_uppercase() {
        fail_if_not(OmemoFileDecryptor.is_hex("AABBCCDD"),
            "uppercase hex must be accepted");
    }

    private void test_is_hex_valid_mixed() {
        fail_if_not(OmemoFileDecryptor.is_hex("aAbBcC01"),
            "mixed case hex must be accepted");
    }

    private void test_is_hex_empty_is_false() {
        fail_if(OmemoFileDecryptor.is_hex(""),
            "empty string is NOT valid hex");
    }

    private void test_is_hex_non_hex_char_false() {
        fail_if(OmemoFileDecryptor.is_hex("ZZZZ"),
            "non-hex chars must be rejected");
    }

    private void test_is_hex_space_is_false() {
        fail_if(OmemoFileDecryptor.is_hex("AA BB"),
            "spaces in hex must be rejected");
    }

    private void test_is_hex_url_safe_base64() {
        // URL-safe base64 contains chars like - and _ which are NOT hex
        fail_if(OmemoFileDecryptor.is_hex("abc-def_ghi"),
            "URL-safe base64 chars (-_) must not be accepted as hex");
    }

    /* ===== hex_to_bin tests ===== */

    private void test_hex_to_bin_known_vector() {
        uint8[] result = OmemoFileDecryptor.hex_to_bin("AABBCCDD");
        fail_if_not_eq_int(result.length, 4, "length must be 4");
        fail_if_not_eq_int(result[0], 0xAA, "byte 0 must be 0xAA");
        fail_if_not_eq_int(result[1], 0xBB, "byte 1 must be 0xBB");
        fail_if_not_eq_int(result[2], 0xCC, "byte 2 must be 0xCC");
        fail_if_not_eq_int(result[3], 0xDD, "byte 3 must be 0xDD");
    }

    private void test_hex_to_bin_empty() {
        uint8[] result = OmemoFileDecryptor.hex_to_bin("");
        fail_if_not_eq_int(result.length, 0, "empty hex must produce empty array");
    }

    private void test_hex_to_bin_all_ff() {
        uint8[] result = OmemoFileDecryptor.hex_to_bin("FFFF");
        fail_if_not_eq_int(result.length, 2, "length must be 2");
        fail_if_not_eq_int(result[0], 0xFF, "byte 0 must be 0xFF");
        fail_if_not_eq_int(result[1], 0xFF, "byte 1 must be 0xFF");
    }

    private void test_hex_to_bin_all_00() {
        uint8[] result = OmemoFileDecryptor.hex_to_bin("0000");
        fail_if_not_eq_int(result.length, 2, "length must be 2");
        fail_if_not_eq_int(result[0], 0x00, "byte 0 must be 0x00");
        fail_if_not_eq_int(result[1], 0x00, "byte 1 must be 0x00");
    }

    /* ===== normalize_base64 tests ===== */

    private void test_normalize_base64_rem_0() {
        // length=4, rem=0 → no padding needed
        string result = OmemoFileDecryptor.normalize_base64("AAAA");
        fail_if_not_eq_str(result, "AAAA",
            "RFC 4648: rem=0 must stay unchanged");
    }

    private void test_normalize_base64_rem_2() {
        // length=2, rem=2 → append "=="
        string result = OmemoFileDecryptor.normalize_base64("AA");
        fail_if_not_eq_str(result, "AA==",
            "RFC 4648: rem=2 must get == padding");
    }

    private void test_normalize_base64_rem_3() {
        // length=3, rem=3 → append "="
        string result = OmemoFileDecryptor.normalize_base64("AAA");
        fail_if_not_eq_str(result, "AAA=",
            "RFC 4648: rem=3 must get = padding");
    }

    /**
     * BUG #15 (FIXED): normalize_base64 with rem==1 now returns "".
     *
     * Base64 can NEVER have length ≡ 1 (mod 4). A valid base64 string
     * encodes 6 bits per character; groups of 4 chars = 24 bits = 3 bytes.
     * Remainder 1 means 6 bits, which is less than 1 byte — impossible.
     *
     * RFC 4648 S3.5: "Implementations MUST reject the encoded data
     * if it contains characters outside the base alphabet."
     *
     * Previously the code returned the malformed input, causing
     * Base64.decode() to produce garbage. Now returns "" so
     * try_decode_secret() fails gracefully.
     */
    private void test_normalize_base64_rem_1() {
        // length=1, rem=1 → INVALID base64 length → must return ""
        string result = OmemoFileDecryptor.normalize_base64("A");
        fail_if_not_eq_str(result, "",
            "RFC 4648: rem=1 is invalid, must return empty string");
        // Also test with length=5 (rem=1)
        string result5 = OmemoFileDecryptor.normalize_base64("ABCDE");
        fail_if_not_eq_str(result5, "",
            "RFC 4648: length 5 (rem=1) is invalid, must return empty string");
    }

    private void test_normalize_base64_url_safe() {
        // URL-safe chars: - → +, _ → /
        string result = OmemoFileDecryptor.normalize_base64("ab-_");
        fail_if_not_eq_str(result, "ab+/",
            "RFC 4648 S5: URL-safe chars must be converted to standard base64");
    }

    private void test_normalize_base64_empty() {
        string result = OmemoFileDecryptor.normalize_base64("");
        fail_if_not_eq_str(result, "",
            "empty string rem=0 must return empty");
    }

    /* ===== aesgcm_to_https_link tests ===== */

    private void test_aesgcm_to_https_basic() {
        var dec = new OmemoFileDecryptor();
        string result = dec.aesgcm_to_https_link(
            "aesgcm://example.com/file.jpg#aabbccdd");
        fail_if_not_eq_str(result, "https://example.com/file.jpg",
            "XEP-0454: aesgcm URL must become https without fragment");
    }

    private void test_aesgcm_to_https_path() {
        var dec = new OmemoFileDecryptor();
        string result = dec.aesgcm_to_https_link(
            "aesgcm://upload.example.com/path/to/file.bin#0123456789abcdef");
        fail_if_not_eq_str(result, "https://upload.example.com/path/to/file.bin",
            "XEP-0454: full path must be preserved");
    }

    private void test_aesgcm_to_https_non_aesgcm() {
        var dec = new OmemoFileDecryptor();
        string result = dec.aesgcm_to_https_link("https://example.com/file.jpg");
        // Non-aesgcm URL should be returned unchanged
        fail_if_not_eq_str(result, "https://example.com/file.jpg",
            "non-aesgcm URL must pass through unchanged");
    }
}

}
