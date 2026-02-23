using Gee;

namespace Xmpp.Test {

/**
 * Security Audit: XEP-0300 Cryptographic Hashes
 *
 * Tests hash_type_to_string / hash_string_to_type roundtrip and
 * Hash.compute against known SHA-256 test vectors.
 *
 * Bug #21: hash_string_to_type("md5") returns null.
 *   hash_type_to_string(ChecksumType.MD5) correctly returns "md5",
 *   but hash_string_to_type("md5") is missing from the switch and
 *   returns null. This means MD5 hashes received from peers cannot
 *   be verified, breaking XEP-0300 interop for MD5 (though MD5 is
 *   deprecated, it may still be sent by legacy clients).
 */
class CryptoHashAudit : Gee.TestCase {

    public CryptoHashAudit() {
        base("CryptoHashAudit");

        // --- hash_type_to_string ---
        add_test("XEP0300_sha1_type_to_string", test_sha1_to_str);
        add_test("XEP0300_sha256_type_to_string", test_sha256_to_str);
        add_test("XEP0300_sha384_type_to_string", test_sha384_to_str);
        add_test("XEP0300_sha512_type_to_string", test_sha512_to_str);
        add_test("XEP0300_md5_type_to_string", test_md5_to_str);

        // --- hash_string_to_type ---
        add_test("XEP0300_sha1_string_to_type", test_sha1_from_str);
        add_test("XEP0300_sha256_string_to_type", test_sha256_from_str);
        add_test("XEP0300_sha384_string_to_type", test_sha384_from_str);
        add_test("XEP0300_sha512_string_to_type", test_sha512_from_str);
        add_test("XEP0300_md5_string_to_type_BUG21", test_md5_from_str);
        add_test("XEP0300_unknown_string_returns_null", test_unknown_from_str);

        // --- roundtrip ---
        add_test("XEP0300_sha256_roundtrip", test_sha256_roundtrip);

        // --- Hash.compute known vectors ---
        add_test("XEP0300_sha256_compute_empty", test_compute_sha256_empty);
        add_test("XEP0300_sha256_compute_abc", test_compute_sha256_abc);
        add_test("XEP0300_sha1_compute_abc", test_compute_sha1_abc);
    }

    // --- hash_type_to_string ---

    private void test_sha1_to_str() {
        fail_if_not_eq_str(
            Xep.CryptographicHashes.hash_type_to_string(ChecksumType.SHA1),
            "sha-1", "SHA1 → 'sha-1'");
    }

    private void test_sha256_to_str() {
        fail_if_not_eq_str(
            Xep.CryptographicHashes.hash_type_to_string(ChecksumType.SHA256),
            "sha-256", "SHA256 → 'sha-256'");
    }

    private void test_sha384_to_str() {
        fail_if_not_eq_str(
            Xep.CryptographicHashes.hash_type_to_string(ChecksumType.SHA384),
            "sha-384", "SHA384 → 'sha-384'");
    }

    private void test_sha512_to_str() {
        fail_if_not_eq_str(
            Xep.CryptographicHashes.hash_type_to_string(ChecksumType.SHA512),
            "sha-512", "SHA512 → 'sha-512'");
    }

    private void test_md5_to_str() {
        fail_if_not_eq_str(
            Xep.CryptographicHashes.hash_type_to_string(ChecksumType.MD5),
            "md5", "MD5 → 'md5'");
    }

    // --- hash_string_to_type ---

    private void test_sha1_from_str() {
        ChecksumType? t = Xep.CryptographicHashes.hash_string_to_type("sha-1");
        fail_if(t == null, "'sha-1' should map to SHA1");
        if (t != null) fail_if_not(t == ChecksumType.SHA1, "should be SHA1");
    }

    private void test_sha256_from_str() {
        ChecksumType? t = Xep.CryptographicHashes.hash_string_to_type("sha-256");
        fail_if(t == null, "'sha-256' should map to SHA256");
        if (t != null) fail_if_not(t == ChecksumType.SHA256, "should be SHA256");
    }

    private void test_sha384_from_str() {
        ChecksumType? t = Xep.CryptographicHashes.hash_string_to_type("sha-384");
        fail_if(t == null, "'sha-384' should map to SHA384");
        if (t != null) fail_if_not(t == ChecksumType.SHA384, "should be SHA384");
    }

    private void test_sha512_from_str() {
        ChecksumType? t = Xep.CryptographicHashes.hash_string_to_type("sha-512");
        fail_if(t == null, "'sha-512' should map to SHA512");
        if (t != null) fail_if_not(t == ChecksumType.SHA512, "should be SHA512");
    }

    private void test_md5_from_str() {
        // Bug #21: "md5" is missing from hash_string_to_type switch
        ChecksumType? t = Xep.CryptographicHashes.hash_string_to_type("md5");
        fail_if(t == null, "Bug #21: 'md5' should map to MD5 but returns null (asymmetry)");
    }

    private void test_unknown_from_str() {
        ChecksumType? t = Xep.CryptographicHashes.hash_string_to_type("blake2b-256");
        fail_if(t != null, "Unknown hash name should return null");
    }

    // --- roundtrip ---

    private void test_sha256_roundtrip() {
        string s = Xep.CryptographicHashes.hash_type_to_string(ChecksumType.SHA256);
        ChecksumType? t = Xep.CryptographicHashes.hash_string_to_type(s);
        fail_if(t == null, "type→string→type roundtrip must not lose SHA256");
        if (t != null) fail_if_not(t == ChecksumType.SHA256, "roundtrip should return SHA256");
    }

    // --- Hash.compute known vectors ---

    private void test_compute_sha256_empty() {
        // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        // Base64: 47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=
        uint8[] empty = {};
        var hash = new Xep.CryptographicHashes.Hash.compute(ChecksumType.SHA256, empty);
        fail_if_not_eq_str(hash.algo, "sha-256", "algo should be 'sha-256'");
        fail_if_not_eq_str(hash.val, "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=",
            "SHA-256 of empty should match known vector");
    }

    private void test_compute_sha256_abc() {
        // SHA-256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
        // Base64: ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=
        uint8[] abc = "abc".data;
        var hash = new Xep.CryptographicHashes.Hash.compute(ChecksumType.SHA256, abc);
        fail_if_not_eq_str(hash.val, "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=",
            "SHA-256 of 'abc' should match NIST vector");
    }

    private void test_compute_sha1_abc() {
        // SHA-1("abc") = a9993e364706816aba3e25717850c26c9cd0d89d
        // Base64: qZk+NkcGgWq6PiVxeFDCbJzQ2J0=
        uint8[] abc = "abc".data;
        var hash = new Xep.CryptographicHashes.Hash.compute(ChecksumType.SHA1, abc);
        fail_if_not_eq_str(hash.algo, "sha-1", "algo should be 'sha-1'");
        fail_if_not_eq_str(hash.val, "qZk+NkcGgWq6PiVxeFDCbJzQ2J0=",
            "SHA-1 of 'abc' should match known vector");
    }
}

}
