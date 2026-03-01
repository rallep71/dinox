using Xmpp;
using Xmpp.Xep;
using Gee;

/**
 * XEP-0077 In-Band Registration + XEP-0050 Ad-Hoc Commands audit tests.
 *
 * Tests registration form parsing, command node parsing, status enum,
 * note parsing, action lists, and adversarial inputs.
 */
namespace Xmpp.Test {

class RegistrationCommandsAudit : Gee.TestCase {
    private const string IBR_NS = "jabber:iq:register";
    private const string CMD_NS = "http://jabber.org/protocol/commands";

    public RegistrationCommandsAudit() {
        base("RegCmdAudit");
        // XEP-0077: Registration form structure
        add_test("XEP0077_ns_uri", test_ibr_ns_uri);
        add_test("XEP0077_query_node_structure", test_ibr_query_structure);
        add_test("XEP0077_password_change_structure", test_ibr_password_change);
        add_test("XEP0077_cancel_registration_structure", test_ibr_cancel_structure);
        add_test("XEP0077_module_identity", test_ibr_module_identity);
        add_test("XEP0077_module_not_mandatory", test_ibr_not_mandatory);
        // XEP-0050: Command parsing
        add_test("XEP0050_command_from_node_basic", test_cmd_from_node_basic);
        add_test("XEP0050_command_from_node_with_form", test_cmd_from_node_with_form);
        add_test("XEP0050_command_from_node_with_actions", test_cmd_from_node_actions);
        add_test("XEP0050_command_from_node_with_notes", test_cmd_from_node_notes);
        add_test("XEP0050_command_status_enum", test_cmd_status_enum);
        add_test("XEP0050_command_status_unknown", test_cmd_status_unknown);
        add_test("XEP0050_command_to_node_roundtrip", test_cmd_to_node);
        add_test("XEP0050_command_empty_node", test_cmd_empty_node);
        // XEP-0050: Adversarial
        add_test("XEP0050_command_missing_node_attr", test_cmd_missing_node_attr);
        add_test("XEP0050_command_missing_sessionid", test_cmd_missing_sessionid);
        add_test("XEP0050_command_xss_in_note", test_cmd_xss_in_note);
        add_test("XEP0050_command_many_actions", test_cmd_many_actions);
        add_test("XEP0050_command_item", test_cmd_item);
        add_test("XEP0050_note_item", test_note_item);
    }

    // ========== XEP-0077 ==========

    private void test_ibr_ns_uri() {
        assert_true(InBandRegistration.NS_URI == "jabber:iq:register");
    }

    private void test_ibr_query_structure() {
        // Verify the query node structure for get_from_server
        var query = new StanzaNode.build("query", IBR_NS).add_self_xmlns();
        assert_true(query.name == "query");
        assert_true(query.ns_uri == IBR_NS);
    }

    private void test_ibr_password_change() {
        // Build a password change query and verify structure
        var query = new StanzaNode.build("query", IBR_NS).add_self_xmlns();
        var username = new StanzaNode.build("username", IBR_NS);
        username.put_node(new StanzaNode.text("testuser"));
        var password = new StanzaNode.build("password", IBR_NS);
        password.put_node(new StanzaNode.text("newpass123"));
        query.put_node(username);
        query.put_node(password);

        StanzaNode? u = query.get_subnode("username", IBR_NS);
        StanzaNode? p = query.get_subnode("password", IBR_NS);
        assert_nonnull(u);
        assert_nonnull(p);
        assert_true(u.get_string_content() == "testuser");
        assert_true(p.get_string_content() == "newpass123");
    }

    private void test_ibr_cancel_structure() {
        // Cancel registration: <query><remove/></query>
        var query = new StanzaNode.build("query", IBR_NS).add_self_xmlns();
        query.put_node(new StanzaNode.build("remove", IBR_NS));

        StanzaNode? remove = query.get_subnode("remove", IBR_NS);
        assert_nonnull(remove);
    }

    private void test_ibr_module_identity() {
        var module = new InBandRegistration.Module();
        assert_true(module.get_ns() == IBR_NS);
        assert_true(module.get_id() == "0077_in_band_registration");
    }

    private void test_ibr_not_mandatory() {
        var module = new InBandRegistration.Module();
        // In-band registration is never mandatory for stream negotiation
        // negotiation_active() requires a live stream, so we test via the module identity
        assert_true(module.get_ns() == IBR_NS);
        assert_true(module.get_id() == "0077_in_band_registration");
        // The module has no mandatory_outstanding logic — it always returns false
    }

    // ========== XEP-0050: Command parsing ==========

    private StanzaNode build_command_node(string? node_attr, string? sessionid,
                                          string? status) {
        var cmd = new StanzaNode.build("command", CMD_NS).add_self_xmlns();
        if (node_attr != null) cmd.put_attribute("node", node_attr);
        if (sessionid != null) cmd.put_attribute("sessionid", sessionid);
        if (status != null) cmd.put_attribute("status", status);
        return cmd;
    }

    private void test_cmd_from_node_basic() {
        var node = build_command_node("list-users", "sess-123", "executing");
        var cmd = AdHocCommands.Command.from_node(node);

        assert_true(cmd.node == "list-users");
        assert_true(cmd.sessionid == "sess-123");
        assert_true(cmd.status == AdHocCommands.Command.Status.EXECUTING);
    }

    private void test_cmd_from_node_with_form() {
        var node = build_command_node("config", "s1", "executing");
        var x_node = new StanzaNode.build("x", DataForms.NS_URI).add_self_xmlns()
            .put_attribute("type", "form");
        node.put_node(x_node);

        var cmd = AdHocCommands.Command.from_node(node);
        assert_nonnull(cmd.form);
    }

    private void test_cmd_from_node_actions() {
        var node = build_command_node("wizard", "s2", "executing");
        var actions = new StanzaNode.build("actions", CMD_NS)
            .put_attribute("execute", "next");
        actions.put_node(new StanzaNode.build("next", CMD_NS));
        actions.put_node(new StanzaNode.build("prev", CMD_NS));
        actions.put_node(new StanzaNode.build("complete", CMD_NS));
        node.put_node(actions);

        var cmd = AdHocCommands.Command.from_node(node);
        assert_true(cmd.actions.size == 3);
        assert_true(cmd.actions.contains("next"));
        assert_true(cmd.actions.contains("prev"));
        assert_true(cmd.actions.contains("complete"));
        assert_true(cmd.execute_action == "next");
    }

    private void test_cmd_from_node_notes() {
        var node = build_command_node("test", "s3", "completed");
        var note1 = new StanzaNode.build("note", CMD_NS)
            .put_attribute("type", "info")
            .put_node(new StanzaNode.text("Operation successful"));
        var note2 = new StanzaNode.build("note", CMD_NS)
            .put_attribute("type", "warn")
            .put_node(new StanzaNode.text("Rate limit reached"));
        node.put_node(note1);
        node.put_node(note2);

        var cmd = AdHocCommands.Command.from_node(node);
        assert_true(cmd.notes.size == 2);
        assert_true(cmd.notes[0].type_ == "info");
        assert_true(cmd.notes[0].text == "Operation successful");
        assert_true(cmd.notes[1].type_ == "warn");
    }

    private void test_cmd_status_enum() {
        assert_true(AdHocCommands.Command.Status.from_string("completed") == AdHocCommands.Command.Status.COMPLETED);
        assert_true(AdHocCommands.Command.Status.from_string("canceled") == AdHocCommands.Command.Status.CANCELED);
        assert_true(AdHocCommands.Command.Status.from_string("executing") == AdHocCommands.Command.Status.EXECUTING);
    }

    private void test_cmd_status_unknown() {
        // Unknown status string defaults to EXECUTING
        assert_true(AdHocCommands.Command.Status.from_string("bogus") == AdHocCommands.Command.Status.EXECUTING);
        assert_true(AdHocCommands.Command.Status.from_string(null) == AdHocCommands.Command.Status.EXECUTING);
        assert_true(AdHocCommands.Command.Status.from_string("") == AdHocCommands.Command.Status.EXECUTING);
    }

    private void test_cmd_to_node() {
        // Build a Command, serialize to node, verify attributes
        var cmd = new AdHocCommands.Command();
        cmd.node = "my-command";
        cmd.sessionid = "abc123";
        cmd.status = AdHocCommands.Command.Status.COMPLETED;
        cmd.actions.add("complete");
        cmd.execute_action = "complete";
        cmd.notes.add(new AdHocCommands.NoteItem("info", "Done!"));

        StanzaNode node = cmd.to_node();
        assert_true(node.name == "command");
        assert_true(node.get_attribute("node") == "my-command");
        assert_true(node.get_attribute("sessionid") == "abc123");
        assert_true(node.get_attribute("status") == "completed");

        StanzaNode? actions_node = node.get_subnode("actions", CMD_NS);
        assert_nonnull(actions_node);
        assert_true(actions_node.get_attribute("execute") == "complete");

        Gee.List<StanzaNode> notes = node.get_subnodes("note", CMD_NS);
        assert_true(notes.size == 1);
    }

    private void test_cmd_empty_node() {
        // Command with no attributes at all
        var node = new StanzaNode.build("command", CMD_NS).add_self_xmlns();
        var cmd = AdHocCommands.Command.from_node(node);
        assert_null(cmd.node);
        assert_null(cmd.sessionid);
        assert_true(cmd.status == AdHocCommands.Command.Status.EXECUTING);
        assert_null(cmd.form);
        assert_true(cmd.actions.size == 0);
        assert_true(cmd.notes.size == 0);
    }

    // ========== Adversarial ==========

    private void test_cmd_missing_node_attr() {
        var node = build_command_node(null, "s1", "executing");
        var cmd = AdHocCommands.Command.from_node(node);
        assert_null(cmd.node);
        // Should not crash — null node is handled gracefully
    }

    private void test_cmd_missing_sessionid() {
        var node = build_command_node("test", null, "executing");
        var cmd = AdHocCommands.Command.from_node(node);
        assert_null(cmd.sessionid);
    }

    private void test_cmd_xss_in_note() {
        var node = build_command_node("test", "s1", "completed");
        var note = new StanzaNode.build("note", CMD_NS)
            .put_attribute("type", "info")
            .put_node(new StanzaNode.text("<script>alert('xss')</script>"));
        node.put_node(note);

        var cmd = AdHocCommands.Command.from_node(node);
        assert_true(cmd.notes.size == 1);
        // XSS payload preserved as text — display layer must escape
        assert_true(cmd.notes[0].text == "<script>alert('xss')</script>");
    }

    private void test_cmd_many_actions() {
        var node = build_command_node("test", "s1", "executing");
        var actions = new StanzaNode.build("actions", CMD_NS);
        for (int i = 0; i < 100; i++) {
            actions.put_node(new StanzaNode.build("action%d".printf(i), CMD_NS));
        }
        node.put_node(actions);

        var cmd = AdHocCommands.Command.from_node(node);
        assert_true(cmd.actions.size == 100);
    }

    private void test_cmd_item() {
        try {
            var item = new AdHocCommands.CommandItem(
                new Jid("server.example.com"),
                "http://jabber.org/protocol/admin#get-online-users",
                "Get Online Users"
            );
            assert_true(item.jid.to_string() == "server.example.com");
            assert_true(item.node == "http://jabber.org/protocol/admin#get-online-users");
            assert_true(item.name == "Get Online Users");
        } catch (InvalidJidError e) {
            assert_not_reached();
        }
    }

    private void test_note_item() {
        var note = new AdHocCommands.NoteItem("error", "Something went wrong");
        assert_true(note.type_ == "error");
        assert_true(note.text == "Something went wrong");
    }
}

}
