namespace Dino.Test {

/**
 * Security Audit: FileTransfer.file_name sanitization
 *
 * The file_name setter strips path components and prevents:
 *   - Path traversal attacks (../../etc/passwd)
 *   - Hidden file creation (.ssh/authorized_keys)
 *   - Empty/separator-only filenames
 *
 * Also tests is_esfs_jid / register_esfs_jid registry.
 */
class FileTransferAudit : Gee.TestCase {

    public FileTransferAudit() {
        base("FileTransferAudit");

        // --- file_name sanitization ---
        add_test("PathTraversal_dotdot_stripped", test_path_traversal);
        add_test("PathTraversal_absolute_path_stripped", test_absolute_path);
        add_test("HiddenFile_dot_prefix_guarded", test_hidden_file);
        add_test("HiddenFile_dotdot_special", test_dotdot_name);
        add_test("Separator_only_becomes_unknown", test_separator_only);
        add_test("Dot_only_becomes_unknown", test_dot_only);
        add_test("Normal_filename_preserved", test_normal_filename);
        add_test("Filename_with_spaces_preserved", test_filename_spaces);

        // --- ESFS JID registry ---
        add_test("ESFS_register_and_check", test_esfs_register);
        add_test("ESFS_unknown_jid_false", test_esfs_unknown);
    }

    // Helper: create FileTransfer, set file_name, return sanitized value
    private string sanitize(string input) {
        var ft = new Dino.Entities.FileTransfer();
        ft.file_name = input;
        return ft.file_name;
    }

    // --- file_name sanitization ---

    private void test_path_traversal() {
        // ../../etc/passwd should be stripped to "passwd"
        string result = sanitize("../../etc/passwd");
        fail_if_not_eq_str(result, "passwd",
            "Path traversal should be stripped to basename");
    }

    private void test_absolute_path() {
        string result = sanitize("/etc/shadow");
        fail_if_not_eq_str(result, "shadow",
            "Absolute path should be stripped to basename");
    }

    private void test_hidden_file() {
        // .bashrc should get underscore prefix → "_.bashrc"
        string result = sanitize(".bashrc");
        fail_if_not_eq_str(result, "_.bashrc",
            "Hidden file should get underscore prefix");
    }

    private void test_dotdot_name() {
        // ".." as filename → Path.get_basename("..") = ".."
        // Then has_prefix(".") → "_" + ".." = "_.."
        string result = sanitize("..");
        fail_if(result == "..", "'..' should not be kept as-is");
    }

    private void test_separator_only() {
        // "/" as filename → Path.get_basename("/") = "/"
        // Then check: "/" == Path.DIR_SEPARATOR_S → "unknown filename"
        string result = sanitize("/");
        fail_if_not_eq_str(result, "unknown filename",
            "Separator-only should become 'unknown filename'");
    }

    private void test_dot_only() {
        // "." as filename → Path.get_basename(".") = "."
        // Then check: "." == "." → "unknown filename"
        string result = sanitize(".");
        fail_if_not_eq_str(result, "unknown filename",
            "Dot-only should become 'unknown filename'");
    }

    private void test_normal_filename() {
        string result = sanitize("photo.jpg");
        fail_if_not_eq_str(result, "photo.jpg",
            "Normal filename should be preserved");
    }

    private void test_filename_spaces() {
        string result = sanitize("my photo.jpg");
        fail_if_not_eq_str(result, "my photo.jpg",
            "Filename with spaces should be preserved");
    }

    // --- ESFS JID registry ---

    private void test_esfs_register() {
        string test_jid = "esfs-test-" + GLib.get_monotonic_time().to_string() + "@example.com";
        Dino.Entities.FileTransfer.register_esfs_jid(test_jid);
        fail_if_not(Dino.Entities.FileTransfer.is_esfs_jid(test_jid),
            "Registered JID should be found by is_esfs_jid");
    }

    private void test_esfs_unknown() {
        fail_if(Dino.Entities.FileTransfer.is_esfs_jid("never-registered@nowhere.test"),
            "Unregistered JID should return false");
    }
}

}
