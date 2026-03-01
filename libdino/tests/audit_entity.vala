using Gee;
using Xmpp;

namespace Dino.Test {

/**
 * Phase 10 — Entity Pure-Logic Tests
 *
 * Tests pure functions and property logic in Dino.Entities.Message
 * and Dino.Entities.FileTransfer without database or stream dependencies.
 *
 * Covers:
 *   - Message type string conversion (4 tests)
 *   - Message.Type.is_muc_semantic (3 tests)
 *   - Message equality and hashing (5 tests)
 *   - Message marked state guard (3 tests)
 *   - Message body validation (4 tests)
 *   - FileTransfer.file_name sanitization (8 tests)
 *   - FileTransfer.server_file_name fallback (2 tests)
 */
class EntityAudit : Gee.TestCase {

    public EntityAudit() {
        base("EntityAudit");

        // --- Message Type String ---
        add_test("Message_set_type_chat", test_msg_type_chat);
        add_test("Message_set_type_groupchat", test_msg_type_gc);
        add_test("Message_get_type_unknown", test_msg_type_unknown);
        add_test("Message_type_roundtrip", test_msg_type_roundtrip);

        // --- Message.Type.is_muc_semantic ---
        add_test("Message_is_muc_groupchat", test_muc_semantic_gc);
        add_test("Message_is_muc_gc_pm", test_muc_semantic_pm);
        add_test("Message_is_muc_chat_false", test_muc_semantic_chat);

        // --- Message equality ---
        add_test("Message_equals_same_body_id", test_eq_same);
        add_test("Message_equals_different_body", test_eq_diff_body);
        add_test("Message_equals_null", test_eq_null);
        add_test("Message_hash_non_null", test_hash_non_null);
        add_test("Message_hash_null_body", test_hash_null_body);

        // --- Message Marked guard ---
        add_test("Message_marked_normal_set", test_marked_normal);
        add_test("Message_marked_read_blocks_received", test_marked_guard);
        add_test("Message_marked_sequence", test_marked_sequence);

        // --- Message body validation ---
        add_test("Message_body_null", test_body_null);
        add_test("Message_body_normal", test_body_normal);
        add_test("Message_body_empty", test_body_empty);
        add_test("Message_body_make_valid", test_body_make_valid);

        // --- FileTransfer.file_name sanitization ---
        add_test("FT_filename_normal", test_ft_normal);
        add_test("FT_filename_path_strip", test_ft_path_strip);
        add_test("FT_filename_dot", test_ft_dot);
        add_test("FT_filename_slash", test_ft_slash);
        add_test("FT_filename_hidden", test_ft_hidden);
        add_test("FT_filename_traversal", test_ft_traversal);
        add_test("FT_filename_double_dot", test_ft_double_dot);
        add_test("FT_filename_space", test_ft_space);

        // --- FileTransfer.server_file_name ---
        add_test("FT_server_name_fallback", test_ft_server_fallback);
        add_test("FT_server_name_explicit", test_ft_server_explicit);
    }

    // ===================== Message Type String =====================

    private void test_msg_type_chat() {
        var m = new Entities.Message("test");
        m.set_type_string("chat");
        fail_if_not(m.type_ == Entities.Message.Type.CHAT, "Should be CHAT");
    }

    private void test_msg_type_gc() {
        var m = new Entities.Message("test");
        m.set_type_string("groupchat");
        fail_if_not(m.type_ == Entities.Message.Type.GROUPCHAT, "Should be GROUPCHAT");
    }

    private void test_msg_type_unknown() {
        var m = new Entities.Message("test");
        // Default type_ is UNKNOWN
        string type_str = m.get_type_string();
        fail_if_not_eq_str(type_str, "normal", "UNKNOWN should map to 'normal'");
    }

    private void test_msg_type_roundtrip() {
        var m = new Entities.Message("test");
        m.set_type_string("chat");
        fail_if_not_eq_str(m.get_type_string(), "chat", "chat roundtrip");
        m.set_type_string("groupchat");
        fail_if_not_eq_str(m.get_type_string(), "groupchat", "groupchat roundtrip");
    }

    // ===================== Message.Type.is_muc_semantic =====================

    private void test_muc_semantic_gc() {
        fail_if_not(Entities.Message.Type.GROUPCHAT.is_muc_semantic(),
            "GROUPCHAT should be MUC semantic");
    }

    private void test_muc_semantic_pm() {
        fail_if_not(Entities.Message.Type.GROUPCHAT_PM.is_muc_semantic(),
            "GROUPCHAT_PM should be MUC semantic");
    }

    private void test_muc_semantic_chat() {
        fail_if(Entities.Message.Type.CHAT.is_muc_semantic(),
            "CHAT should NOT be MUC semantic");
    }

    // ===================== Message Equality =====================

    private void test_eq_same() {
        var m1 = new Entities.Message("Hello");
        m1.stanza_id = "id-1";
        var m2 = new Entities.Message("Hello");
        m2.stanza_id = "id-1";
        fail_if_not(m1.equals(m2), "Same stanza_id + body should be equal");
    }

    private void test_eq_diff_body() {
        var m1 = new Entities.Message("Hello");
        m1.stanza_id = "id-1";
        var m2 = new Entities.Message("World");
        m2.stanza_id = "id-1";
        fail_if(m1.equals(m2), "Different body should not be equal");
    }

    private void test_eq_null() {
        var m = new Entities.Message("Hello");
        fail_if(m.equals(null), "Message.equals(null) should be false");
    }

    private void test_hash_non_null() {
        var m = new Entities.Message("Hello");
        uint h = Entities.Message.hash_func(m);
        fail_if_not(h != 0, "Hash of non-null body should be non-zero");
    }

    private void test_hash_null_body() {
        var m = new Entities.Message(null);
        uint h = Entities.Message.hash_func(m);
        fail_if_not(h == 0, "Hash of null body should be 0");
    }

    // ===================== Message Marked Guard =====================

    private void test_marked_normal() {
        var m = new Entities.Message("test");
        m.marked = Entities.Message.Marked.SENT;
        fail_if_not(m.marked == Entities.Message.Marked.SENT, "Should be SENT");
    }

    private void test_marked_guard() {
        var m = new Entities.Message("test");
        m.marked = Entities.Message.Marked.READ;
        // Now try to set RECEIVED — guard should prevent downgrade
        m.marked = Entities.Message.Marked.RECEIVED;
        fail_if_not(m.marked == Entities.Message.Marked.READ,
            "Setting RECEIVED when already READ should be blocked");
    }

    private void test_marked_sequence() {
        var m = new Entities.Message("test");
        m.marked = Entities.Message.Marked.NONE;
        fail_if_not(m.marked == Entities.Message.Marked.NONE, "Start at NONE");
        m.marked = Entities.Message.Marked.SENDING;
        fail_if_not(m.marked == Entities.Message.Marked.SENDING, "Move to SENDING");
        m.marked = Entities.Message.Marked.SENT;
        fail_if_not(m.marked == Entities.Message.Marked.SENT, "Move to SENT");
        m.marked = Entities.Message.Marked.RECEIVED;
        fail_if_not(m.marked == Entities.Message.Marked.RECEIVED, "Move to RECEIVED");
        m.marked = Entities.Message.Marked.READ;
        fail_if_not(m.marked == Entities.Message.Marked.READ, "Move to READ");
    }

    // ===================== Message Body Validation =====================

    private void test_body_null() {
        var m = new Entities.Message(null);
        fail_if(m.body != null, "Null body should stay null");
    }

    private void test_body_normal() {
        var m = new Entities.Message("Hello World");
        fail_if_not_eq_str(m.body, "Hello World", "Normal body");
    }

    private void test_body_empty() {
        var m = new Entities.Message("");
        fail_if_not_eq_str(m.body, "", "Empty body should be preserved");
    }

    private void test_body_make_valid() {
        // body setter calls make_valid() — should handle encoding issues
        var m = new Entities.Message("Valid UTF-8: äöü");
        fail_if_not_eq_str(m.body, "Valid UTF-8: äöü", "UTF-8 body should be preserved");
    }

    // ===================== FileTransfer.file_name Sanitization =====================

    private void test_ft_normal() {
        var ft = new Entities.FileTransfer();
        ft.file_name = "photo.jpg";
        fail_if_not_eq_str(ft.file_name, "photo.jpg", "Normal filename");
    }

    private void test_ft_path_strip() {
        var ft = new Entities.FileTransfer();
        ft.file_name = "/path/to/secret/file.txt";
        fail_if_not_eq_str(ft.file_name, "file.txt",
            "Path should be stripped to basename");
    }

    private void test_ft_dot() {
        var ft = new Entities.FileTransfer();
        ft.file_name = ".";
        fail_if_not_eq_str(ft.file_name, "unknown filename",
            "'.' should become 'unknown filename'");
    }

    private void test_ft_slash() {
        var ft = new Entities.FileTransfer();
        ft.file_name = "/";
        fail_if_not_eq_str(ft.file_name, "unknown filename",
            "'/' should become 'unknown filename'");
    }

    private void test_ft_hidden() {
        var ft = new Entities.FileTransfer();
        ft.file_name = ".bashrc";
        fail_if_not_eq_str(ft.file_name, "_.bashrc",
            "Hidden file should get '_' prefix");
    }

    private void test_ft_traversal() {
        var ft = new Entities.FileTransfer();
        ft.file_name = "../../../etc/passwd";
        fail_if_not_eq_str(ft.file_name, "passwd",
            "Path traversal should be stripped to basename");
    }

    private void test_ft_double_dot() {
        var ft = new Entities.FileTransfer();
        ft.file_name = "..";
        // ".." → basename is ".." → starts with "." → becomes "_.."
        fail_if_not(ft.file_name != null, "Double dot should not crash");
    }

    private void test_ft_space() {
        var ft = new Entities.FileTransfer();
        ft.file_name = "my file (1).txt";
        fail_if_not_eq_str(ft.file_name, "my file (1).txt",
            "Filename with spaces should be preserved");
    }

    // ===================== FileTransfer.server_file_name =====================

    private void test_ft_server_fallback() {
        var ft = new Entities.FileTransfer();
        ft.file_name = "local.txt";
        // server_file_name not set — should fall back to file_name
        fail_if_not_eq_str(ft.server_file_name, "local.txt",
            "server_file_name should fall back to file_name");
    }

    private void test_ft_server_explicit() {
        var ft = new Entities.FileTransfer();
        ft.file_name = "local.txt";
        ft.server_file_name = "server.txt";
        fail_if_not_eq_str(ft.server_file_name, "server.txt",
            "Explicit server_file_name should override");
    }
}

}
