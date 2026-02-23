/**
 * Security audit tests for PGP armor parsing functions.
 *
 * Tests:
 *   Module.extract_signature_from_armor()  — XEP-0027 detached signatures
 *   Module.extract_encrypted_from_armor()  — XEP-0027 PGP MESSAGE extraction
 *
 * These functions extract base64 content from GPG ASCII-armor output.
 * The signature parser has a known fragility: a +30 magic offset fallback
 * when \n\n (blank line separator) is missing after the header.
 */

using Dino.Plugins.OpenPgp;

namespace OpenPgp.Test {

class ArmorParserTest : Gee.TestCase {

    public ArmorParserTest() {
        base("ArmorParser");

        /* extract_signature_from_armor */
        add_test("XEP0027_sig_normal_armor", test_sig_normal);
        add_test("XEP0027_sig_with_hash_header", test_sig_with_hash);
        add_test("XEP0027_sig_multiline_base64", test_sig_multiline);
        add_test("XEP0027_sig_with_checksum", test_sig_checksum);
        add_test("XEP0027_sig_no_begin_header", test_sig_no_begin);
        add_test("XEP0027_sig_no_end_footer", test_sig_no_end);
        add_test("XEP0027_sig_crlf_endings", test_sig_crlf);
        add_test("XEP0027_sig_fallback_no_blank_line", test_sig_no_blank_line);
        add_test("XEP0027_sig_empty_base64", test_sig_empty_b64);

        /* extract_encrypted_from_armor */
        add_test("XEP0027_enc_normal_armor", test_enc_normal);
        add_test("XEP0027_enc_no_header", test_enc_no_header);
        add_test("XEP0027_enc_no_blank_line", test_enc_no_blank_line);
        add_test("XEP0027_enc_no_footer", test_enc_no_footer);
        add_test("XEP0027_enc_crlf", test_enc_crlf);
        add_test("XEP0027_enc_multiline", test_enc_multiline);
        add_test("XEP0027_enc_with_version_header", test_enc_with_version);
    }

    /* ===== extract_signature_from_armor ===== */

    /**
     * XEP-0027: Normal PGP SIGNATURE armor with blank line separator.
     */
    private void test_sig_normal() {
        string armor = "-----BEGIN PGP SIGNATURE-----\n\niQIzBAABCAAdFiEE\n-----END PGP SIGNATURE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_signature_from_armor(armor);
        fail_if_null(result, "XEP-0027: normal signature must be extracted");
        fail_if_not_eq_str(result, "iQIzBAABCAAdFiEE",
            "XEP-0027: base64 data must be extracted from signature armor");
    }

    /**
     * XEP-0027: Signature armor with Hash: header before blank line.
     */
    private void test_sig_with_hash() {
        string armor = "-----BEGIN PGP SIGNATURE-----\nHash: SHA256\n\niQIzBAABCAAdFiEE\n-----END PGP SIGNATURE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_signature_from_armor(armor);
        fail_if_null(result, "XEP-0027: signature with Hash header must be extracted");
        fail_if_not_eq_str(result, "iQIzBAABCAAdFiEE",
            "XEP-0027: Hash header must be skipped, only base64 extracted");
    }

    /**
     * XEP-0027: Multi-line base64 content (64-char wrapped).
     */
    private void test_sig_multiline() {
        string b64_line1 = "iQIzBAABCAAdFiEEabcdefghij1234567890klmnopqrstuvwxyzABCDEFGHIJ";
        string b64_line2 = "KLMNOPQRSTUVWXYZ0123456789abcdefgh";
        string armor = "-----BEGIN PGP SIGNATURE-----\n\n" + b64_line1 + "\n" + b64_line2 + "\n-----END PGP SIGNATURE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_signature_from_armor(armor);
        fail_if_null(result, "XEP-0027: multiline signature must be extracted");
        // Newlines within are preserved (not joined) — the function does .strip() but
        // internal newlines are kept
        fail_if(result == null || !result.contains(b64_line1),
            "XEP-0027: first line of base64 must be present in result");
    }

    /**
     * XEP-0027: Signature with CRC24 checksum line (=XXXX).
     */
    private void test_sig_checksum() {
        string armor = "-----BEGIN PGP SIGNATURE-----\n\niQIzBAABCAAdFiEE\n=abc0\n-----END PGP SIGNATURE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_signature_from_armor(armor);
        fail_if_null(result, "XEP-0027: signature with checksum must be extracted");
        // Checksum line is included in the extracted content
        fail_if(result == null || !result.contains("=abc0"),
            "XEP-0027: checksum line must be included in extracted signature");
    }

    /**
     * XEP-0027: Missing BEGIN header returns null.
     */
    private void test_sig_no_begin() {
        string armor = "not a signature at all\niQIzBAABCAAdFiEE\n-----END PGP SIGNATURE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_signature_from_armor(armor);
        fail_if(result != null,
            "XEP-0027: missing BEGIN header must return null");
    }

    /**
     * XEP-0027: Missing END footer returns null.
     */
    private void test_sig_no_end() {
        string armor = "-----BEGIN PGP SIGNATURE-----\n\niQIzBAABCAAdFiEE\n";
        string? result = Dino.Plugins.OpenPgp.Module.extract_signature_from_armor(armor);
        fail_if(result != null,
            "XEP-0027: missing END footer must return null");
    }

    /**
     * XEP-0027: Signature with CRLF line endings.
     * The function does NOT normalize \r\n. If GPG outputs CRLF,
     * \n\n won't match \r\n\r\n, triggering the +30 fallback.
     */
    private void test_sig_crlf() {
        string armor = "-----BEGIN PGP SIGNATURE-----\r\n\r\niQIzBAABCAAdFiEE\r\n-----END PGP SIGNATURE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_signature_from_armor(armor);
        // FRAGILITY: \r\n\r\n contains \n\n at offset +1, so it works
        // But the +2 skip lands inside the \r\n pair
        // Let's see what actually happens
        if (result != null) {
            // Should contain the base64 data, possibly with extra \r
            fail_if(result == null || !result.contains("iQIzBAABCAAdFiEE"),
                "XEP-0027: CRLF armor must still extract base64 data");
        } else {
            // If null, the CRLF handling is broken
            GLib.Test.message("FINDING: CRLF signatures are not handled by extract_signature_from_armor");
            GLib.Test.fail();
        }
    }

    /**
     * XEP-0027: Fallback path when blank line separator is missing.
     *
     * Previously used a +30 magic offset that caused off-by-one errors.
     * Bug #18: extracted "----END PGP SIGNATURE-----" instead of base64 data.
     * FIXED: now uses index_of("\n", begin_marker) + 1.
     */
    private void test_sig_no_blank_line() {
        // Signature with only single newline (no blank line separator)
        string armor = "-----BEGIN PGP SIGNATURE-----\niQIzBAABCAAdFiEE\n-----END PGP SIGNATURE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_signature_from_armor(armor);
        fail_if_null(result, "XEP-0027: fallback path must extract signature data");
        fail_if_not_eq_str(result, "iQIzBAABCAAdFiEE",
            "XEP-0027: fallback must extract base64 data, not footer (Bug #18 fix)");
    }

    /**
     * XEP-0027: Empty base64 content between headers.
     */
    private void test_sig_empty_b64() {
        string armor = "-----BEGIN PGP SIGNATURE-----\n\n\n-----END PGP SIGNATURE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_signature_from_armor(armor);
        // Content between blank line and END is just a \n, stripped → ""
        if (result != null) {
            fail_if_not_eq_str(result, "",
                "XEP-0027: empty content must produce empty string");
        }
        // null is also acceptable
    }

    /* ===== extract_encrypted_from_armor ===== */

    /**
     * XEP-0027: Normal PGP MESSAGE armor.
     */
    private void test_enc_normal() {
        string armor = "-----BEGIN PGP MESSAGE-----\n\nhQIMAxwanFLE4e/4\n-----END PGP MESSAGE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_encrypted_from_armor(armor);
        fail_if_null(result, "XEP-0027: normal PGP MESSAGE must be extracted");
        fail_if_not_eq_str(result, "hQIMAxwanFLE4e/4",
            "XEP-0027: base64 data must be extracted from PGP MESSAGE armor");
    }

    /**
     * XEP-0027: Missing BEGIN header returns null.
     */
    private void test_enc_no_header() {
        string input = "just some text\n-----END PGP MESSAGE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_encrypted_from_armor(input);
        fail_if(result != null,
            "XEP-0027: missing BEGIN header must return null");
    }

    /**
     * XEP-0027: Missing blank line separator returns null.
     * (Unlike signature parser, the encrypted parser does NOT have a fallback)
     */
    private void test_enc_no_blank_line() {
        string armor = "-----BEGIN PGP MESSAGE-----\nhQIMAxwanFLE4e/4\n-----END PGP MESSAGE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_encrypted_from_armor(armor);
        fail_if(result != null,
            "XEP-0027: missing blank line must return null (no fallback)");
    }

    /**
     * XEP-0027: Missing END footer returns null.
     */
    private void test_enc_no_footer() {
        string armor = "-----BEGIN PGP MESSAGE-----\n\nhQIMAxwanFLE4e/4\n";
        string? result = Dino.Plugins.OpenPgp.Module.extract_encrypted_from_armor(armor);
        fail_if(result != null,
            "XEP-0027: missing END footer must return null");
    }

    /**
     * XEP-0027: CRLF line endings (Windows GPG).
     * The function normalizes \r\n to \n, so this should work.
     */
    private void test_enc_crlf() {
        string armor = "-----BEGIN PGP MESSAGE-----\r\n\r\nhQIMAxwanFLE4e/4\r\n-----END PGP MESSAGE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_encrypted_from_armor(armor);
        fail_if_null(result, "XEP-0027: CRLF armor must be extracted");
        fail_if_not_eq_str(result, "hQIMAxwanFLE4e/4",
            "XEP-0027: CRLF normalization must produce same result as LF");
    }

    /**
     * XEP-0027: Multi-line base64 content.
     */
    private void test_enc_multiline() {
        string armor = "-----BEGIN PGP MESSAGE-----\n\nAABBCCDD\nEEFFGGHH\n-----END PGP MESSAGE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_encrypted_from_armor(armor);
        fail_if_null(result, "XEP-0027: multiline encrypted content must be extracted");
        fail_if(result == null || !result.contains("AABBCCDD"),
            "XEP-0027: first line must be present");
        fail_if(result == null || !result.contains("EEFFGGHH"),
            "XEP-0027: second line must be present");
    }

    /**
     * XEP-0027: Armor with Version: header line.
     */
    private void test_enc_with_version() {
        string armor = "-----BEGIN PGP MESSAGE-----\nVersion: GnuPG v2.2.0\n\nhQIMAxwanFLE4e/4\n-----END PGP MESSAGE-----";
        string? result = Dino.Plugins.OpenPgp.Module.extract_encrypted_from_armor(armor);
        fail_if_null(result, "XEP-0027: armor with Version header must be extracted");
        fail_if_not_eq_str(result, "hQIMAxwanFLE4e/4",
            "XEP-0027: Version header must be skipped, only base64 extracted");
    }
}

}
