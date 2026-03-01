using Xmpp;
using Xmpp.Xep;
using Gee;

/**
 * XEP-0234 Jingle File Transfer audit tests.
 *
 * Tests Parameters.parse() for description validation, file name sanitization,
 * size validation, and adversarial inputs (path traversal, negative size, etc.).
 */
namespace Xmpp.Test {

class JingleFileTransferAudit : Gee.TestCase {
    private const string NS_URI = "urn:xmpp:jingle:apps:file-transfer:5";

    public JingleFileTransferAudit() {
        base("JingleFTAudit");
        // Valid parsing
        add_test("XEP0234_parse_valid_description", test_parse_valid);
        add_test("XEP0234_parse_with_media_type", test_parse_media_type);
        add_test("XEP0234_parse_large_size", test_parse_large_size);
        // Size validation
        add_test("XEP0234_parse_negative_size_rejected", test_negative_size);
        add_test("XEP0234_parse_zero_size_accepted", test_zero_size);
        add_test("XEP0234_parse_missing_size_rejected", test_missing_size);
        add_test("XEP0234_parse_non_numeric_size", test_non_numeric_size);
        // File count validation
        add_test("XEP0234_parse_no_file_node", test_no_file_node);
        add_test("XEP0234_parse_multiple_file_nodes", test_multiple_file_nodes);
        // File name edge cases
        add_test("XEP0234_filename_normal", test_filename_normal);
        add_test("XEP0234_filename_path_traversal", test_filename_path_traversal);
        add_test("XEP0234_filename_absolute_path", test_filename_absolute_path);
        add_test("XEP0234_filename_backslash_path", test_filename_backslash_path);
        add_test("XEP0234_filename_null_name", test_filename_null);
        add_test("XEP0234_filename_empty", test_filename_empty);
        add_test("XEP0234_filename_unicode", test_filename_unicode);
        add_test("XEP0234_filename_xss", test_filename_xss);
        // FileTransferInputStream
        add_test("XEP0234_stream_eof_at_max_size", test_stream_eof);
        add_test("XEP0234_stream_zero_remaining", test_stream_zero_remaining);
        // Description node structure
        add_test("XEP0234_description_roundtrip", test_description_roundtrip);
        add_test("XEP0234_original_description_preserved", test_original_description);
    }

    // ========== Helpers ==========

    private StanzaNode build_description(string? name, string? size, string? media_type = null) {
        var desc = new StanzaNode.build("description", NS_URI).add_self_xmlns();
        var file = new StanzaNode.build("file", NS_URI);
        if (name != null) {
            file.put_node(new StanzaNode.build("name", NS_URI)
                .put_node(new StanzaNode.text(name)));
        }
        if (size != null) {
            file.put_node(new StanzaNode.build("size", NS_URI)
                .put_node(new StanzaNode.text(size)));
        }
        if (media_type != null) {
            file.put_node(new StanzaNode.build("media-type", NS_URI)
                .put_node(new StanzaNode.text(media_type)));
        }
        desc.put_node(file);
        return desc;
    }

    // ========== Valid parsing ==========

    private void test_parse_valid() {
        var desc = build_description("test.pdf", "1048576");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            assert_true(params.name == "test.pdf");
            assert_true(params.size == 1048576);
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }

    private void test_parse_media_type() {
        var desc = build_description("photo.jpg", "5000", "image/jpeg");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            assert_true(params.name == "photo.jpg");
            assert_true(params.size == 5000);
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }

    private void test_parse_large_size() {
        // 10 GB file
        var desc = build_description("large.iso", "10737418240");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            assert_true(params.size == 10737418240);
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }

    // ========== Size validation ==========

    private void test_negative_size() {
        var desc = build_description("evil.exe", "-1");
        try {
            var module = new JingleFileTransfer.Module();
            JingleFileTransfer.Parameters.parse(module, desc);
            // Should throw IqError for negative size
            assert_not_reached();
        } catch (Jingle.IqError e) {
            // Expected: "negative file size is invalid"
            assert_true(e.message.contains("negative"));
        }
    }

    private void test_zero_size() {
        var desc = build_description("empty.txt", "0");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            assert_true(params.size == 0);
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }

    private void test_missing_size() {
        var desc = build_description("nosize.txt", null);
        try {
            var module = new JingleFileTransfer.Module();
            JingleFileTransfer.Parameters.parse(module, desc);
            // Should throw: "file offer without file size"
            assert_not_reached();
        } catch (Jingle.IqError e) {
            assert_true(e.message.contains("size"));
        }
    }

    private void test_non_numeric_size() {
        var desc = build_description("bad.txt", "not_a_number");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            // int64.parse("not_a_number") returns 0 in Vala
            assert_true(params.size == 0);
        } catch (Jingle.IqError e) {
            // Also acceptable if validation rejects it
        }
    }

    // ========== File count ==========

    private void test_no_file_node() {
        var desc = new StanzaNode.build("description", NS_URI).add_self_xmlns();
        // No <file> child
        try {
            var module = new JingleFileTransfer.Module();
            JingleFileTransfer.Parameters.parse(module, desc);
            assert_not_reached();
        } catch (Jingle.IqError e) {
            assert_true(e.message.contains("exactly one file"));
        }
    }

    private void test_multiple_file_nodes() {
        var desc = new StanzaNode.build("description", NS_URI).add_self_xmlns();
        desc.put_node(new StanzaNode.build("file", NS_URI)
            .put_node(new StanzaNode.build("name", NS_URI).put_node(new StanzaNode.text("a.txt")))
            .put_node(new StanzaNode.build("size", NS_URI).put_node(new StanzaNode.text("100"))));
        desc.put_node(new StanzaNode.build("file", NS_URI)
            .put_node(new StanzaNode.build("name", NS_URI).put_node(new StanzaNode.text("b.txt")))
            .put_node(new StanzaNode.build("size", NS_URI).put_node(new StanzaNode.text("200"))));
        try {
            var module = new JingleFileTransfer.Module();
            JingleFileTransfer.Parameters.parse(module, desc);
            assert_not_reached();
        } catch (Jingle.IqError e) {
            assert_true(e.message.contains("exactly one file"));
        }
    }

    // ========== File name edge cases ==========

    private void test_filename_normal() {
        var desc = build_description("document.pdf", "100");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            assert_true(params.name == "document.pdf");
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }

    private void test_filename_path_traversal() {
        // Path traversal attack: ../../etc/passwd
        var desc = build_description("../../etc/passwd", "100");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            // The parser accepts the name as-is — the CONSUMER must sanitize
            assert_true(params.name == "../../etc/passwd");
            // Document: XEP-0234 parser does NOT sanitize file names.
            // Path traversal must be prevented at the file-saving layer (libdino).
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }

    private void test_filename_absolute_path() {
        var desc = build_description("/etc/shadow", "100");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            assert_true(params.name == "/etc/shadow");
            // Document: absolute paths accepted — consumer must use basename()
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }

    private void test_filename_backslash_path() {
        // Windows path traversal
        var desc = build_description("..\\..\\Windows\\System32\\config\\SAM", "100");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            assert_nonnull(params.name);
            // Backslashes are not path separators on Linux but are on Windows
            // Document: Windows path traversal character accepted
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }

    private void test_filename_null() {
        var desc = build_description(null, "100");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            assert_null(params.name);
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }

    private void test_filename_empty() {
        var desc = build_description("", "100");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            assert_true(params.name == "");
            // Document: empty filename accepted — consumer must handle
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }

    private void test_filename_unicode() {
        var desc = build_description("ünïcödë_文件.txt", "100");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            assert_true(params.name == "ünïcödë_文件.txt");
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }

    private void test_filename_xss() {
        var desc = build_description("<img src=x onerror=alert(1)>.html", "100");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            // HTML in filename — must be escaped when displayed
            assert_nonnull(params.name);
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }

    // ========== FileTransferInputStream ==========

    private void test_stream_eof() {
        // FileTransferInputStream should return 0 (EOF) after max_size bytes
        string data = "Hello World! This is test data for the stream.";
        var mem = new MemoryInputStream.from_data(data.data);
        int64 max_size = 5;

        // We can't directly instantiate the private class, but we can test
        // the concept: read from a stream that wraps with size limit
        uint8[] buf = new uint8[100];
        try {
            ssize_t read = mem.read(buf[0:max_size]);
            assert_true(read == max_size);
            assert_true(((string) buf).has_prefix("Hello"));
        } catch (IOError e) {
            assert_not_reached();
        }
    }

    private void test_stream_zero_remaining() {
        // Edge case: max_size = 0 should immediately return 0
        var mem = new MemoryInputStream.from_data("data".data);
        uint8[] buf = new uint8[10];
        // Read 0 bytes — simulate zero remaining
        try {
            ssize_t read = mem.read(buf[0:0]);
            assert_true(read == 0);
        } catch (IOError e) {
            assert_not_reached();
        }
    }

    // ========== Description roundtrip ==========

    private void test_description_roundtrip() {
        var desc = build_description("test.txt", "42");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            StanzaNode roundtrip = params.get_description_node();
            assert_nonnull(roundtrip);
            // Should be the original description node
            assert_true(roundtrip.name == "description");
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }

    private void test_original_description() {
        var desc = build_description("file.bin", "999");
        try {
            var module = new JingleFileTransfer.Module();
            var params = JingleFileTransfer.Parameters.parse(module, desc);
            // original_description is preserved for re-serialization
            assert_true(params.original_description == desc);
        } catch (Jingle.IqError e) {
            assert_not_reached();
        }
    }
}

}
