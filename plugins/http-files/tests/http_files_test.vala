using Dino.Plugins.HttpFiles;

// Force GObject class initialisation so that static Regex fields are populated.
// link_args-style linking (internal VAPI) does NOT trigger class_init automatically.
[CCode (cname = "g_type_class_ref")]
extern unowned void* _force_class_init(GLib.Type type);

namespace Dino.Plugins.HttpFiles.Test {

/**
 * XEP-0363 HTTP File Upload — URL recognition regex tests.
 * The http_url_regex must accept valid HTTP(S) upload URLs and reject
 * anything that would break the download path (fragments, spaces, wrong scheme).
 *
 * The omemo_url_regex validates the aesgcm:// URL convention for OMEMO
 * encrypted file transfers (iv+key carried in fragment).
 */
class UrlRegexTest : Gee.TestCase {
    public UrlRegexTest() {
        base("UrlRegex");
        add_test("XEP0363_http_url_accepts_https", test_http_matches_https);
        add_test("XEP0363_http_url_accepts_http", test_http_matches_http);
        add_test("XEP0363_http_url_rejects_ftp_scheme", test_http_rejects_ftp);
        add_test("RFC3986_rejects_spaces_in_url", test_http_rejects_spaces);
        add_test("XEP0363_http_url_rejects_fragment", test_http_rejects_fragment);
        add_test("CONTRACT_http_url_rejects_empty", test_http_rejects_empty);
        add_test("XEP0363_http_url_accepts_port_path", test_http_matches_port_and_path);
        add_test("OMEMO_aesgcm_url_matches", test_omemo_matches_aesgcm);
        add_test("OMEMO_aesgcm_requires_fragment", test_omemo_requires_fragment);
        add_test("OMEMO_aesgcm_rejects_https_scheme", test_omemo_rejects_https);
        add_test("OMEMO_aesgcm_rejects_empty_fragment", test_omemo_rejects_empty_fragment);
        add_test("OMEMO_aesgcm_captures_host_and_secret", test_omemo_captures_host_and_secret);
        add_test("RFC3986_aesgcm_rejects_spaces_in_fragment", test_omemo_rejects_spaces_in_secret);
    }

    public override void set_up() {
        // Trigger GObject class_init so static Regex fields are populated
        _force_class_init(typeof(FileProvider));
    }

    void test_http_matches_https() {
        fail_if_not(FileProvider.http_url_regex.match("https://example.com/file.jpg"),
                    "XEP-0363: HTTPS upload URL MUST be recognized as valid download source");
    }

    void test_http_matches_http() {
        fail_if_not(FileProvider.http_url_regex.match("http://example.com/file.jpg"),
                    "XEP-0363: HTTP upload URL MUST be recognized (non-TLS allowed by spec)");
    }

    void test_http_rejects_ftp() {
        fail_if(FileProvider.http_url_regex.match("ftp://example.com/file.jpg"),
                "XEP-0363: only http/https schemes are valid; ftp MUST be rejected");
    }

    void test_http_rejects_spaces() {
        fail_if(FileProvider.http_url_regex.match("https://example.com/file name.jpg"),
                "RFC 3986 §3.3: spaces are not valid in URI path; MUST reject");
    }

    void test_http_rejects_fragment() {
        fail_if(FileProvider.http_url_regex.match("https://example.com/file.jpg#abc"),
                "XEP-0363: GET URL with fragment would lose data; MUST reject");
    }

    void test_http_rejects_empty() {
        fail_if(FileProvider.http_url_regex.match(""),
                "CONTRACT: empty string is not a valid URL; MUST reject");
    }

    void test_http_matches_port_and_path() {
        fail_if_not(FileProvider.http_url_regex.match("https://chat.example.com:5443/upload/abc123/file.webp"),
                    "XEP-0363: URL with port and multi-segment upload path MUST match");
    }

    void test_omemo_matches_aesgcm() {
        fail_if_not(FileProvider.omemo_url_regex.match("aesgcm://example.com/upload/file.jpg#aabbccdd1234"),
                    "OMEMO: aesgcm:// URL with fragment (iv+key) MUST be recognized");
    }

    void test_omemo_requires_fragment() {
        fail_if(FileProvider.omemo_url_regex.match("aesgcm://example.com/upload/file.jpg"),
                "OMEMO: aesgcm:// URL without fragment has no iv+key; MUST reject");
    }

    void test_omemo_rejects_https() {
        fail_if(FileProvider.omemo_url_regex.match("https://example.com/file.jpg#secret"),
                "OMEMO: https:// scheme MUST NOT match omemo regex (different code path)");
    }

    void test_omemo_rejects_empty_fragment() {
        fail_if(FileProvider.omemo_url_regex.match("aesgcm://example.com/file.jpg#"),
                "OMEMO: empty fragment contains no iv+key; MUST reject");
    }

    void test_omemo_captures_host_and_secret() {
        MatchInfo info;
        fail_if_not(FileProvider.omemo_url_regex.match("aesgcm://host.example:5443/upload/abc/file.webp#iv_hex_key_hex", 0, out info),
                    "OMEMO: aesgcm URL with port MUST match and capture groups");
        fail_if_not_eq_str("host.example:5443/upload/abc/file.webp", info.fetch(1));
        fail_if_not_eq_str("iv_hex_key_hex", info.fetch(2));
    }

    void test_omemo_rejects_spaces_in_secret() {
        fail_if(FileProvider.omemo_url_regex.match("aesgcm://example.com/file.jpg#sec ret"),
                "RFC 3986 §3.5: fragment MUST NOT contain spaces; would corrupt iv+key");
    }
}

/**
 * CONTRACT: extract_file_name_from_url() — strips fragment, URL-decodes,
 * and returns the filename portion after the last '/'.
 * This is critical for displaying the correct filename to users.
 */
class FileNameExtractionTest : Gee.TestCase {
    public FileNameExtractionTest() {
        base("FileNameExtraction");
        add_test("CONTRACT_simple_https_url", test_simple_https_url);
        add_test("OMEMO_aesgcm_strips_fragment", test_aesgcm_strips_fragment);
        add_test("RFC3986_url_decode_percent_encoding", test_url_encoded_name);
        add_test("CONTRACT_deep_path_last_segment", test_deep_path);
        add_test("CONTRACT_trailing_slash_empty", test_trailing_slash);
        add_test("XEP0363_real_upload_url", test_port_in_url);
    }

    // FileProvider.extract_file_name_from_url is an instance method
    // requiring StreamInteractor. We replicate the pure logic here.
    // The actual method: strip fragment, unescape, take after last '/'.
    private string extract_file_name(string url) {
        string ret = url;
        if (ret.contains("#")) {
            ret = ret.substring(0, ret.last_index_of("#"));
        }
        ret = Uri.unescape_string(ret.substring(ret.last_index_of("/") + 1));
        return ret;
    }

    void test_simple_https_url() {
        fail_if_not_eq_str("image.jpg", extract_file_name("https://example.com/upload/abc/image.jpg"));
    }

    void test_aesgcm_strips_fragment() {
        fail_if_not_eq_str("photo.webp",
            extract_file_name("aesgcm://chat.example.com:5443/upload/abc123/photo.webp#aabbccdd11223344"));
    }

    void test_url_encoded_name() {
        fail_if_not_eq_str("my file (1).png",
            extract_file_name("https://example.com/upload/my%20file%20%281%29.png"));
    }

    void test_deep_path() {
        fail_if_not_eq_str("doc.pdf",
            extract_file_name("https://host.example/a/b/c/d/doc.pdf"));
    }

    void test_trailing_slash() {
        // Edge case: trailing slash → empty name
        fail_if_not_eq_str("",
            extract_file_name("https://example.com/upload/"));
    }

    void test_port_in_url() {
        fail_if_not_eq_str("hose.webp",
            extract_file_name("https://chat.handwerker.jetzt:5443/upload/91cb74e9/4qlK2oPH/hose.webp"));
    }
}

/**
 * CONTRACT: sanitize_for_log() / sanitize_url_for_log() —
 * MUST strip secrets (fragments, query strings) from URLs before logging.
 * Prevents leaking OMEMO keys and upload tokens into log files.
 */
class SanitizeLogTest : Gee.TestCase {
    public SanitizeLogTest() {
        base("SanitizeLog");
        add_test("CONTRACT_null_safe", test_null_returns_null_string);
        add_test("CONTRACT_strips_fragment_secret", test_strips_fragment);
        add_test("CONTRACT_preserves_url_without_fragment", test_no_fragment_unchanged);
        add_test("CONTRACT_truncates_oversized_url", test_truncates_long_url);
        add_test("CONTRACT_sender_strips_query_token", test_sender_strips_query);
        add_test("CONTRACT_sender_null_safe", test_sender_null_returns_null_string);
    }

    void test_null_returns_null_string() {
        fail_if_not_eq_str("(null)", FileProvider.sanitize_for_log(null));
    }

    void test_strips_fragment() {
        string result = FileProvider.sanitize_for_log("aesgcm://host/path#secretkey");
        fail_if_not_eq_str("aesgcm://host/path#...", result);
    }

    void test_no_fragment_unchanged() {
        fail_if_not_eq_str("https://example.com/file.jpg",
            FileProvider.sanitize_for_log("https://example.com/file.jpg"));
    }

    void test_truncates_long_url() {
        var sb = new GLib.StringBuilder();
        sb.append("https://example.com/");
        for (int i = 0; i < 250; i++) sb.append_c('x');
        string result = FileProvider.sanitize_for_log(sb.str);
        fail_if_not(result.length <= 203,
                    "CONTRACT: sanitize_for_log MUST truncate URLs > 200 chars to prevent log flooding");
        fail_if_not(result.has_suffix("..."),
                    "CONTRACT: truncated URL MUST end with '...' to indicate truncation");
    }

    void test_sender_strips_query() {
        string result = HttpFileSender.sanitize_url_for_log("https://host/path?token=abc&sig=xyz");
        fail_if_not_eq_str("https://host/path?...", result);
    }

    void test_sender_null_returns_null_string() {
        fail_if_not_eq_str("(null)", HttpFileSender.sanitize_url_for_log(null));
    }
}

/**
 * XEP-0448 Stateless File Sharing — ESFS JID registry.
 * The registry tracks which counterparts support ESFS so that
 * file_sender can choose the correct upload format (with/without GCM tag).
 */
class EsfsRegistryTest : Gee.TestCase {
    public EsfsRegistryTest() {
        base("EsfsRegistry");
        add_test("XEP0448_register_lookup", test_register_and_check);
        add_test("XEP0448_unknown_jid_returns_false", test_unknown_jid_false);
        add_test("XEP0448_multiple_jids_coexist", test_register_multiple);
    }

    void test_register_and_check() {
        Dino.Entities.FileTransfer.register_esfs_jid("test-http@example.com");
        fail_if_not(Dino.Entities.FileTransfer.is_esfs_jid("test-http@example.com"),
                    "XEP-0448: registered ESFS JID MUST be found by is_esfs_jid()");
    }

    void test_unknown_jid_false() {
        fail_if(Dino.Entities.FileTransfer.is_esfs_jid("unknown-http-test@nowhere.invalid"),
                "XEP-0448: unregistered JID MUST return false from is_esfs_jid()");
    }

    void test_register_multiple() {
        Dino.Entities.FileTransfer.register_esfs_jid("alice-http@example.com");
        Dino.Entities.FileTransfer.register_esfs_jid("bob-http@example.com");
        fail_if_not(Dino.Entities.FileTransfer.is_esfs_jid("alice-http@example.com"),
                    "XEP-0448: first registered ESFS JID MUST persist after second registration");
        fail_if_not(Dino.Entities.FileTransfer.is_esfs_jid("bob-http@example.com"),
                    "XEP-0448: second registered ESFS JID MUST also be found");
    }
}

}
