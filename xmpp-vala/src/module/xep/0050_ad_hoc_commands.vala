using Gee;

namespace Xmpp.Xep.AdHocCommands {

public const string NS_URI = "http://jabber.org/protocol/commands";

public class Module : XmppStreamModule, Iq.Handler {
    public static ModuleIdentity<Module> IDENTITY = new ModuleIdentity<Module>(NS_URI, "0050_ad_hoc_commands");

    private HashMap<string, CommandHandler> registered_commands = new HashMap<string, CommandHandler>();

    public delegate void CommandCallback(XmppStream stream, Iq.Stanza iq, Command command);

    // Register a local ad-hoc command that this entity can execute
    public void register_command(XmppStream stream, string node, string name, CommandHandler handler) {
        registered_commands[node] = handler;
    }

    public void unregister_command(XmppStream stream, string node) {
        registered_commands.unset(node);
    }

    // Execute a remote ad-hoc command (as initiator)
    public async Command? execute(XmppStream stream, Jid target, string node, DataForms.DataForm? form = null) {
        StanzaNode command_node = new StanzaNode.build("command", NS_URI)
            .add_self_xmlns()
            .put_attribute("node", node)
            .put_attribute("action", "execute");

        if (form != null) {
            command_node.put_node(form.get_submit_node());
        }

        Iq.Stanza iq = new Iq.Stanza.set(command_node) { to = target };

        try {
            Iq.Stanza result = yield stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq_async(stream, iq);
            if (result.is_error()) return null;
            StanzaNode? cmd_node = result.stanza.get_subnode("command", NS_URI);
            if (cmd_node == null) return null;
            return Command.from_node(cmd_node);
        } catch (GLib.Error e) {
            warning("Ad-hoc command execute failed: %s", e.message);
            return null;
        }
    }

    // Continue a multi-step command session
    public async Command? proceed(XmppStream stream, Jid target, string node, string sessionid,
                                   string action, DataForms.DataForm? form = null) {
        StanzaNode command_node = new StanzaNode.build("command", NS_URI)
            .add_self_xmlns()
            .put_attribute("node", node)
            .put_attribute("sessionid", sessionid)
            .put_attribute("action", action);

        if (form != null) {
            command_node.put_node(form.get_submit_node());
        }

        Iq.Stanza iq = new Iq.Stanza.set(command_node) { to = target };

        try {
            Iq.Stanza result = yield stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq_async(stream, iq);
            if (result.is_error()) return null;
            StanzaNode? cmd_node = result.stanza.get_subnode("command", NS_URI);
            if (cmd_node == null) return null;
            return Command.from_node(cmd_node);
        } catch (GLib.Error e) {
            warning("Ad-hoc command proceed failed: %s", e.message);
            return null;
        }
    }

    // Cancel a multi-step command session
    public async bool cancel(XmppStream stream, Jid target, string node, string sessionid) {
        StanzaNode command_node = new StanzaNode.build("command", NS_URI)
            .add_self_xmlns()
            .put_attribute("node", node)
            .put_attribute("sessionid", sessionid)
            .put_attribute("action", "cancel");

        Iq.Stanza iq = new Iq.Stanza.set(command_node) { to = target };

        try {
            Iq.Stanza result = yield stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq_async(stream, iq);
            return !result.is_error();
        } catch (GLib.Error e) {
            warning("Ad-hoc command cancel failed: %s", e.message);
            return false;
        }
    }

    // List available commands on a remote entity
    public async Gee.List<CommandItem>? list_commands(XmppStream stream, Jid target) {
        var disco = stream.get_module<ServiceDiscovery.Module>(ServiceDiscovery.Module.IDENTITY);
        ServiceDiscovery.ItemsResult? items_result = yield disco.request_items(stream, target);
        if (items_result == null) return null;

        var commands = new ArrayList<CommandItem>();
        foreach (ServiceDiscovery.Item item in items_result.items) {
            commands.add(new CommandItem(item.jid, item.node ?? "", item.name ?? ""));
        }
        return commands;
    }

    // Handle incoming IQ set requests for registered commands
    public async void on_iq_set(XmppStream stream, Iq.Stanza iq) {
        StanzaNode? command_node = iq.stanza.get_subnode("command", NS_URI);
        if (command_node == null) return;

        string? node = command_node.get_attribute("node");
        if (node == null) {
            send_error(stream, iq, "bad-request");
            return;
        }

        CommandHandler? handler = registered_commands[node];
        if (handler == null) {
            send_error(stream, iq, "item-not-found");
            return;
        }

        Command incoming = Command.from_node(command_node);
        incoming.from = iq.from;

        yield handler.handle_command(stream, iq, incoming);
    }

    // Handle incoming IQ get requests (disco#items for commands list)
    public async void on_iq_get(XmppStream stream, Iq.Stanza iq) {
        // IQ gets are not used for ad-hoc commands execution (only IQ set)
        // Discovery is handled by XEP-0030
    }

    private void send_error(XmppStream stream, Iq.Stanza request, string condition) {
        ErrorStanza error_stanza;
        if (condition == "item-not-found") {
            error_stanza = new ErrorStanza.item_not_found();
        } else {
            error_stanza = new ErrorStanza.bad_request(condition);
        }
        Iq.Stanza error_iq = new Iq.Stanza.error(request, error_stanza) {
            to = request.from
        };
        stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq(stream, error_iq);
    }

    public override void attach(XmppStream stream) {
        stream.get_module<Iq.Module>(Iq.Module.IDENTITY).register_for_namespace(NS_URI, this);
        stream.get_module<ServiceDiscovery.Module>(ServiceDiscovery.Module.IDENTITY).add_feature(stream, NS_URI);
    }

    public override void detach(XmppStream stream) {
        stream.get_module<Iq.Module>(Iq.Module.IDENTITY).unregister_from_namespace(NS_URI, this);
        stream.get_module<ServiceDiscovery.Module>(ServiceDiscovery.Module.IDENTITY)
            .remove_feature(stream, NS_URI);
    }

    public override string get_ns() { return NS_URI; }
    public override string get_id() { return IDENTITY.id; }
}

// Represents an ad-hoc command result / state
public class Command : Object {
    public string? node { get; set; }
    public string? sessionid { get; set; }
    public Status status { get; set; default = Status.EXECUTING; }
    public DataForms.DataForm? form { get; set; }
    public Gee.List<string> actions { get; set; default = null; }
    public string? execute_action { get; set; }  // default action
    public Jid? from { get; set; }
    public Gee.List<NoteItem> notes { get; set; default = null; }

    construct {
        actions = new ArrayList<string>();
        notes = new ArrayList<NoteItem>();
    }

    public enum Status {
        EXECUTING,
        COMPLETED,
        CANCELED;

        public static Status from_string(string? s) {
            switch (s) {
                case "completed": return COMPLETED;
                case "canceled": return CANCELED;
                default: return EXECUTING;
            }
        }

        public string to_string() {
            switch (this) {
                case COMPLETED: return "completed";
                case CANCELED: return "canceled";
                default: return "executing";
            }
        }
    }

    public static Command from_node(StanzaNode node) {
        var cmd = new Command();
        cmd.node = node.get_attribute("node");
        cmd.sessionid = node.get_attribute("sessionid");
        cmd.status = Status.from_string(node.get_attribute("status"));

        // Parse form
        StanzaNode? x_node = node.get_subnode("x", DataForms.NS_URI);
        if (x_node != null) {
            cmd.form = new DataForms.DataForm.from_node(x_node);
        }

        // Parse allowed actions
        StanzaNode? actions_node = node.get_subnode("actions", NS_URI);
        if (actions_node != null) {
            cmd.execute_action = actions_node.get_attribute("execute");
            foreach (StanzaNode child in actions_node.sub_nodes) {
                cmd.actions.add(child.name);
            }
        }

        // Parse notes
        foreach (StanzaNode note_node in node.get_subnodes("note", NS_URI)) {
            string? type = note_node.get_attribute("type");
            string? text = note_node.get_string_content();
            if (text != null) {
                cmd.notes.add(new NoteItem(type ?? "info", text));
            }
        }

        return cmd;
    }

    // Build a response command node for sending back
    public StanzaNode to_node() {
        var node = new StanzaNode.build("command", NS_URI)
            .add_self_xmlns();

        if (this.node != null) node.put_attribute("node", this.node);
        if (this.sessionid != null) node.put_attribute("sessionid", this.sessionid);
        node.put_attribute("status", this.status.to_string());

        if (this.form != null) {
            node.put_node(this.form.stanza_node);
        }

        if (this.actions.size > 0) {
            var actions_node = new StanzaNode.build("actions", NS_URI);
            if (this.execute_action != null) {
                actions_node.put_attribute("execute", this.execute_action);
            }
            foreach (string action in this.actions) {
                actions_node.put_node(new StanzaNode.build(action, NS_URI));
            }
            node.put_node(actions_node);
        }

        foreach (NoteItem note in this.notes) {
            var note_node = new StanzaNode.build("note", NS_URI)
                .put_attribute("type", note.type_);
            note_node.put_node(new StanzaNode.text(note.text));
            node.put_node(note_node);
        }

        return node;
    }
}

public class NoteItem : Object {
    public string type_ { get; set; }
    public string text { get; set; }

    public NoteItem(string type, string text) {
        this.type_ = type;
        this.text = text;
    }
}

// Item returned by disco#items list of commands
public class CommandItem : Object {
    public Jid jid { get; set; }
    public string node { get; set; }
    public string name { get; set; }

    public CommandItem(Jid jid, string node, string name) {
        this.jid = jid;
        this.node = node;
        this.name = name;
    }
}

// Interface for handling incoming ad-hoc command requests
public interface CommandHandler : Object {
    public abstract async void handle_command(XmppStream stream, Iq.Stanza iq, Command command);
}

}
