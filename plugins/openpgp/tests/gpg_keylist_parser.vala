/**
 * Security audit tests for GPGHelper.parse_keylist_output().
 *
 * Tests the colon-format parser extracted from get_keylist().
 * No GPG binary needed — pure string → List<Key> transformation.
 *
 * Reference: GnuPG doc/DETAILS, --with-colons format
 *   Record types: pub, sec, fpr, uid, ssb, sub
 *   Field 2: validity (o, q, n, m, f, u, r, e, d)
 *   Field 10: user ID / fingerprint
 */

using Gee;
using GPGHelper;

namespace OpenPgp.Test {

class GPGKeylistParserTest : Gee.TestCase {

    public GPGKeylistParserTest() {
        base("GPGKeylistParser");

        /* Basic parsing */
        add_test("GPG_keylist_empty_output", test_empty_output);
        add_test("GPG_keylist_single_pub_key", test_single_pub_key);
        add_test("GPG_keylist_secret_key", test_secret_key);
        add_test("GPG_keylist_expired_key", test_expired_key);
        add_test("GPG_keylist_revoked_key", test_revoked_key);

        /* Email extraction */
        add_test("GPG_keylist_email_extraction", test_email_extraction);
        add_test("GPG_keylist_uid_no_email", test_uid_no_email);
        add_test("GPG_keylist_uid_malformed_brackets", test_uid_malformed_brackets);

        /* Fingerprint / key ID */
        add_test("GPG_keylist_keyid_from_fpr", test_keyid_from_fpr);
        add_test("GPG_keylist_short_fingerprint", test_short_fingerprint);

        /* Subkeys */
        add_test("GPG_keylist_subkey_fpr_skipped", test_subkey_fpr_skipped);

        /* Multiple keys */
        add_test("GPG_keylist_multiple_keys", test_multiple_keys);

        /* Edge cases */
        add_test("GPG_keylist_no_uid_no_add", test_no_uid_no_add);
        add_test("GPG_keylist_no_fpr_no_add", test_no_fpr_no_add);
        add_test("GPG_keylist_malformed_lines", test_malformed_lines);
        add_test("GPG_keylist_only_first_uid", test_only_first_uid);
    }

    /* ===== Basic parsing ===== */

    private void test_empty_output() {
        var keys = GPGHelper.parse_keylist_output("");
        fail_if_not_eq_int(keys.size, 0,
            "GPG: empty output must produce empty key list");
    }

    private void test_single_pub_key() {
        string output = "pub:u:::::::::\nfpr:::::::::ABCDEF1234567890ABCDEF1234567890ABCDEF12:\nuid:::::::::Alice <alice@example.com>:\n";
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 1, "GPG: single pub key must produce 1 key");
        fail_if(keys[0].secret, "GPG: pub key must not be marked secret");
        fail_if(keys[0].expired, "GPG: valid key must not be expired");
        fail_if(keys[0].revoked, "GPG: valid key must not be revoked");
    }

    private void test_secret_key() {
        string output = "sec:u:::::::::\nfpr:::::::::ABCDEF1234567890ABCDEF1234567890ABCDEF12:\nuid:::::::::Bob <bob@example.com>:\n";
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 1, "GPG: single sec key must produce 1 key");
        fail_if_not(keys[0].secret, "GPG: sec key must be marked secret");
    }

    private void test_expired_key() {
        string output = "pub:e:::::::::\nfpr:::::::::ABCDEF1234567890ABCDEF1234567890ABCDEF12:\nuid:::::::::Expired <exp@example.com>:\n";
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 1, "GPG: expired key must be parsed");
        fail_if_not(keys[0].expired, "GPG: validity 'e' must set expired=true");
        fail_if(keys[0].revoked, "GPG: expired key must not be revoked");
    }

    private void test_revoked_key() {
        string output = "pub:r:::::::::\nfpr:::::::::ABCDEF1234567890ABCDEF1234567890ABCDEF12:\nuid:::::::::Revoked <rev@example.com>:\n";
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 1, "GPG: revoked key must be parsed");
        fail_if_not(keys[0].revoked, "GPG: validity 'r' must set revoked=true");
        fail_if(keys[0].expired, "GPG: revoked key must not be expired");
    }

    /* ===== Email extraction ===== */

    private void test_email_extraction() {
        string output = "pub:u:::::::::\nfpr:::::::::ABCDEF1234567890ABCDEF1234567890ABCDEF12:\nuid:::::::::Alice Smith <alice@example.com>:\n";
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 1, "GPG: key must be parsed");
        fail_if_not_eq_str(keys[0].email, "alice@example.com",
            "GPG: email must be extracted from <...> in uid");
        fail_if_not_eq_str(keys[0].uid, "Alice Smith <alice@example.com>",
            "GPG: full uid must be preserved");
    }

    private void test_uid_no_email() {
        string output = "pub:u:::::::::\nfpr:::::::::ABCDEF1234567890ABCDEF1234567890ABCDEF12:\nuid:::::::::Just A Name:\n";
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 1, "GPG: key with no-email uid must be parsed");
        fail_if_not_eq_str(keys[0].uid, "Just A Name",
            "GPG: uid without email must be preserved");
        fail_if(keys[0].email != null,
            "GPG: uid without <...> must have null email");
    }

    private void test_uid_malformed_brackets() {
        // > before < — malformed
        string output = "pub:u:::::::::\nfpr:::::::::ABCDEF1234567890ABCDEF1234567890ABCDEF12:\nuid:::::::::Name >bad< stuff:\n";
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 1, "GPG: key with malformed uid must be parsed");
        // The parser does index_of("<") and index_of(">") separately
        // With ">bad<", index_of("<") = 9, index_of(">") = 5, end < start → no extraction
        fail_if(keys[0].email != null,
            "GPG: malformed brackets (> before <) must not extract email");
    }

    /* ===== Fingerprint / key ID ===== */

    private void test_keyid_from_fpr() {
        string fpr40 = "ABCDEF1234567890ABCDEF1234567890ABCDEF12";
        string output = "pub:u:::::::::\nfpr:::::::::" + fpr40 + ":\nuid:::::::::Test <t@t.com>:\n";
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 1, "GPG: key must be parsed");
        fail_if_not_eq_str(keys[0].fpr, fpr40,
            "GPG: full 40-char fingerprint must be stored");
        // keyid = last 16 chars
        fail_if_not_eq_str(keys[0].keyid, "34567890ABCDEF12",
            "GPG: keyid must be last 16 chars of fingerprint");
    }

    private void test_short_fingerprint() {
        // Fingerprint shorter than 16 chars — edge case
        string short_fpr = "ABCDEF";
        string output = "pub:u:::::::::\nfpr:::::::::" + short_fpr + ":\nuid:::::::::Test <t@t.com>:\n";
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 1, "GPG: key with short fpr must be parsed");
        // keyid should be same as fpr when < 16 chars
        fail_if_not_eq_str(keys[0].keyid, short_fpr,
            "GPG: short fingerprint must be used as keyid directly");
    }

    /* ===== Subkeys ===== */

    private void test_subkey_fpr_skipped() {
        // ssb record should reset expect_fpr, so its fpr line is ignored
        string output = string.join("\n",
            "pub:u:::::::::",
            "fpr:::::::::AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555:",
            "uid:::::::::Main Key <main@example.com>:",
            "ssb:u:::::::::",
            "fpr:::::::::FFFF6666GGGG7777HHHH8888IIII9999JJJJ0000:",
            ""
        );
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 1, "GPG: subkey must not create separate key");
        fail_if_not_eq_str(keys[0].fpr, "AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555",
            "GPG: primary key fingerprint must be used, not subkey");
    }

    /* ===== Multiple keys ===== */

    private void test_multiple_keys() {
        string output = string.join("\n",
            "pub:u:::::::::",
            "fpr:::::::::AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555:",
            "uid:::::::::Alice <alice@a.com>:",
            "pub:u:::::::::",
            "fpr:::::::::1111222233334444555566667777888899990000:",
            "uid:::::::::Bob <bob@b.com>:",
            ""
        );
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 2, "GPG: two pub keys must produce 2 entries");
        fail_if_not_eq_str(keys[0].uid, "Alice <alice@a.com>",
            "GPG: first key uid must be Alice");
        fail_if_not_eq_str(keys[1].uid, "Bob <bob@b.com>",
            "GPG: second key uid must be Bob");
    }

    /* ===== Edge cases ===== */

    private void test_no_uid_no_add() {
        // Key with fpr but no uid record — must NOT be added
        string output = "pub:u:::::::::\nfpr:::::::::ABCDEF1234567890ABCDEF1234567890ABCDEF12:\n";
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 0,
            "GPG: key without uid must not be added to list");
    }

    private void test_no_fpr_no_add() {
        // Key with uid but no fpr (empty fingerprint) — must NOT be added
        string output = "pub:u:::::::::\nuid:::::::::Name <n@n.com>:\n";
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 0,
            "GPG: key without fingerprint must not be added to list");
    }

    private void test_malformed_lines() {
        // Lines with < 2 fields, random garbage
        string output = "garbage\n:\npub\nfpr:::::::::FPR40CHARS000000000000000000000000FPR40CH:\nuid:::::::::OK <ok@ok.com>:\n";
        var keys = GPGHelper.parse_keylist_output(output);
        // "pub" alone has only 1 field after split(":") → parts.length < 2 → skipped
        // But actually "pub" has no colons, so split(":") gives ["pub"] → length 1 → skipped
        // So no current_key is set, fpr and uid are attached to nothing
        // FINDING: a "pub" line without colons is silently ignored
        fail_if_not_eq_int(keys.size, 0,
            "GPG: malformed pub line (no colons) must not create key");
    }

    private void test_only_first_uid() {
        // Multiple uid records — only first should be captured
        string output = string.join("\n",
            "pub:u:::::::::",
            "fpr:::::::::ABCDEF1234567890ABCDEF1234567890ABCDEF12:",
            "uid:::::::::First UID <first@example.com>:",
            "uid:::::::::Second UID <second@example.com>:",
            ""
        );
        var keys = GPGHelper.parse_keylist_output(output);
        fail_if_not_eq_int(keys.size, 1, "GPG: multiple UIDs must still produce 1 key");
        fail_if_not_eq_str(keys[0].uid, "First UID <first@example.com>",
            "GPG: only first UID must be captured (parser checks uid == null)");
        fail_if_not_eq_str(keys[0].email, "first@example.com",
            "GPG: email must come from first UID");
    }
}

}
