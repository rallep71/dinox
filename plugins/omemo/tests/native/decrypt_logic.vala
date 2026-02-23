/**
 * Security audit tests for OMEMO decrypt helper functions.
 *
 * Tests: constant_time_compare (decrypt_v2.vala), arr_to_str (decrypt.vala).
 *
 * These functions were originally private. Changed to internal static
 * for testability.
 */

using Dino.Plugins.Omemo;

namespace Omemo.Test {

class DecryptLogicTest : Gee.TestCase {

    public DecryptLogicTest() {
        base("DecryptLogic");

        /* constant_time_compare */
        add_test("CWE208_equal_arrays_returns_true", test_ctc_equal);
        add_test("CWE208_unequal_arrays_returns_false", test_ctc_unequal);
        add_test("CWE208_different_length_returns_false", test_ctc_different_length);
        add_test("CWE208_empty_arrays_returns_true", test_ctc_empty);
        add_test("CWE208_single_byte_match", test_ctc_single_byte_match);
        add_test("CWE208_single_byte_mismatch", test_ctc_single_byte_mismatch);
        add_test("CWE208_all_zero_arrays_equal", test_ctc_all_zero);
        add_test("CWE208_one_bit_difference", test_ctc_one_bit_diff);
        add_test("CWE208_first_byte_differs", test_ctc_first_byte_differs);
        add_test("CWE208_last_byte_differs", test_ctc_last_byte_differs);

        /* arr_to_str */
        add_test("CONTRACT_arr_to_str_ascii", test_ats_ascii);
        add_test("CONTRACT_arr_to_str_empty", test_ats_empty);
        add_test("CONTRACT_arr_to_str_embedded_nul", test_ats_embedded_nul);
        add_test("CONTRACT_arr_to_str_utf8_multibyte", test_ats_utf8_multibyte);
        add_test("CONTRACT_arr_to_str_single_byte", test_ats_single_byte);
    }

    /* ===== constant_time_compare tests ===== */

    /**
     * CWE-208: Observable Timing Discrepancy.
     * Two identical arrays must compare as equal.
     */
    private void test_ctc_equal() {
        uint8[] a = { 0x01, 0x02, 0x03, 0x04 };
        uint8[] b = { 0x01, 0x02, 0x03, 0x04 };
        fail_if_not(Omemo2Decrypt.constant_time_compare(a, b),
            "CWE-208: identical arrays must return true");
    }

    /**
     * CWE-208: Different arrays must compare as unequal.
     */
    private void test_ctc_unequal() {
        uint8[] a = { 0x01, 0x02, 0x03, 0x04 };
        uint8[] b = { 0x01, 0x02, 0x03, 0x05 };
        fail_if(Omemo2Decrypt.constant_time_compare(a, b),
            "CWE-208: different arrays must return false");
    }

    /**
     * CWE-208: Arrays of different length must return false immediately.
     */
    private void test_ctc_different_length() {
        uint8[] a = { 0x01, 0x02, 0x03 };
        uint8[] b = { 0x01, 0x02, 0x03, 0x04 };
        fail_if(Omemo2Decrypt.constant_time_compare(a, b),
            "CWE-208: different lengths must return false");
    }

    /**
     * CWE-208: Two empty arrays are equal.
     */
    private void test_ctc_empty() {
        uint8[] a = {};
        uint8[] b = {};
        fail_if_not(Omemo2Decrypt.constant_time_compare(a, b),
            "CWE-208: empty arrays must return true");
    }

    /**
     * CWE-208: Single identical byte.
     */
    private void test_ctc_single_byte_match() {
        uint8[] a = { 0xFF };
        uint8[] b = { 0xFF };
        fail_if_not(Omemo2Decrypt.constant_time_compare(a, b),
            "CWE-208: single matching byte must return true");
    }

    /**
     * CWE-208: Single differing byte.
     */
    private void test_ctc_single_byte_mismatch() {
        uint8[] a = { 0xFE };
        uint8[] b = { 0xFF };
        fail_if(Omemo2Decrypt.constant_time_compare(a, b),
            "CWE-208: single mismatching byte must return false");
    }

    /**
     * CWE-208: All-zero arrays are equal.
     */
    private void test_ctc_all_zero() {
        uint8[] a = { 0x00, 0x00, 0x00, 0x00 };
        uint8[] b = { 0x00, 0x00, 0x00, 0x00 };
        fail_if_not(Omemo2Decrypt.constant_time_compare(a, b),
            "CWE-208: all-zero arrays must return true");
    }

    /**
     * CWE-208: Single bit difference must be detected.
     */
    private void test_ctc_one_bit_diff() {
        uint8[] a = { 0x00, 0x00, 0x80, 0x00 };
        uint8[] b = { 0x00, 0x00, 0x00, 0x00 };
        fail_if(Omemo2Decrypt.constant_time_compare(a, b),
            "CWE-208: one-bit difference must return false");
    }

    /**
     * CWE-208: Difference in first byte.
     */
    private void test_ctc_first_byte_differs() {
        uint8[] a = { 0xFF, 0x02, 0x03, 0x04 };
        uint8[] b = { 0x00, 0x02, 0x03, 0x04 };
        fail_if(Omemo2Decrypt.constant_time_compare(a, b),
            "CWE-208: first byte difference must return false");
    }

    /**
     * CWE-208: Difference in last byte.
     */
    private void test_ctc_last_byte_differs() {
        uint8[] a = { 0x01, 0x02, 0x03, 0x00 };
        uint8[] b = { 0x01, 0x02, 0x03, 0xFF };
        fail_if(Omemo2Decrypt.constant_time_compare(a, b),
            "CWE-208: last byte difference must return false");
    }

    /* ===== arr_to_str tests ===== */

    /**
     * arr_to_str must convert a byte array to a null-terminated string.
     */
    private void test_ats_ascii() {
        uint8[] arr = { 'H', 'e', 'l', 'l', 'o' };
        string result = OmemoDecryptor.arr_to_str(arr);
        fail_if_not_eq_str(result, "Hello",
            "arr_to_str: ASCII bytes must produce correct string");
    }

    /**
     * arr_to_str with empty array must produce empty string.
     */
    private void test_ats_empty() {
        uint8[] arr = {};
        string result = OmemoDecryptor.arr_to_str(arr);
        fail_if_not_eq_str(result, "",
            "arr_to_str: empty array must produce empty string");
    }

    /**
     * arr_to_str with embedded NUL byte truncates at first NUL.
     *
     * This is a known characteristic of the (string) cast in Vala:
     * C strings terminate at the first NUL byte. If OMEMO decrypted
     * plaintext contains a NUL byte, data after it is silently lost.
     *
     * NOTE: This documents current behavior. A robust implementation
     * should use GLib.strndup or similar to preserve full data, but
     * XMPP message bodies are text and should never contain NUL.
     */
    private void test_ats_embedded_nul() {
        uint8[] arr = { 'A', 'B', 0x00, 'C', 'D' };
        string result = OmemoDecryptor.arr_to_str(arr);
        // String truncates at first NUL
        fail_if_not_eq_str(result, "AB",
            "arr_to_str: embedded NUL must truncate string (C behavior)");
    }

    /**
     * arr_to_str must handle valid UTF-8 multi-byte sequences.
     */
    private void test_ats_utf8_multibyte() {
        // "ä" = U+00E4 = 0xC3 0xA4 in UTF-8
        uint8[] arr = { 0xC3, 0xA4 };
        string result = OmemoDecryptor.arr_to_str(arr);
        fail_if_not_eq_str(result, "ä",
            "arr_to_str: UTF-8 ä must survive conversion");
    }

    /**
     * arr_to_str with single byte.
     */
    private void test_ats_single_byte() {
        uint8[] arr = { 'X' };
        string result = OmemoDecryptor.arr_to_str(arr);
        fail_if_not_eq_str(result, "X",
            "arr_to_str: single byte must produce single-char string");
    }
}

}
