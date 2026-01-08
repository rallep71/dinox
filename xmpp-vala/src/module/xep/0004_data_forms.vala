using Gee;

namespace Xmpp.Xep.DataForms {

public const string NS_URI = "jabber:x:data";

public class DataForm {

    public StanzaNode stanza_node { get; set; }
    public Gee.List<Field> fields = new ArrayList<Field>();
    public string? form_type = null;
    public string? instructions = null;
    public string? title = null;

    public StanzaNode get_submit_node() {
        stanza_node.set_attribute("type", "submit");
        return stanza_node;
    }

    public enum Type {
        BOOLEAN,
        FIXED,
        HIDDEN,
        JID_MULTI,
        LIST_SINGLE,
        LIST_MULTI,
        TEXT_PRIVATE,
        TEXT_SINGLE,
    }

    public class Option {
        public string label { get; set; }
        public string value { get; set; }

        public Option(string label, string value) {
            this.label = label;
            this.value = value;
        }
    }

    public class Field : Object {
        public StanzaNode node { get; set; }
        public string? label {
            get { return node.get_attribute("label", NS_URI); }
            set { node.set_attribute("label", value); }
        }
        public Type? type_ = null;
        public string? var {
            get { return node.get_attribute("var", NS_URI); }
            set { node.set_attribute("var", value); }
        }

        public Field() {
            this.node = new StanzaNode.build("field", NS_URI);
        }

        public Field.from_node(StanzaNode node) {
            this.node = node;
        }

        public Gee.List<string> get_values() {
            Gee.List<string> ret = new ArrayList<string>();
            Gee.List<StanzaNode> value_nodes = node.get_subnodes("value", NS_URI);
            foreach (StanzaNode node in value_nodes) {
                ret.add(node.get_string_content());
            }
            return ret;
        }

        public string get_value_string() {
            Gee.List<string> values = get_values();
            return values.size > 0 ? values[0] : "";
        }

        public void set_value_string(string val) {
            StanzaNode? value_node = node.get_subnode("value", NS_URI);
            if (value_node == null) {
                value_node = new StanzaNode.build("value", NS_URI);
                node.put_node(value_node);
            }
            value_node.sub_nodes.clear();
            value_node.put_node(new StanzaNode.text(val));
        }

        internal Gee.List<Option>? get_options() {
            Gee.List<Option> ret = new ArrayList<Option>();
            Gee.List<StanzaNode> option_nodes = node.get_subnodes("option", NS_URI);
            foreach (StanzaNode node in option_nodes) {
                Option option = new Option(node.get_attribute("label", NS_URI), node.get_subnode("value").get_string_content());
                ret.add(option);
            }
            return ret;
        }
    }

    public class BooleanField : Field {
        public bool value {
            get { return get_value_string() == "1"; }
            set { set_value_string(value ? "1" : "0"); }
        }
        public BooleanField(StanzaNode node) {
            base.from_node(node);
            type_ = Type.BOOLEAN;
        }
    }

    public class FixedField : Field {
        public string value {
            owned get { return get_value_string(); }
            set { set_value_string(value); }
        }
        public FixedField(StanzaNode node) {
            base.from_node(node);
            type_ = Type.FIXED;
        }
    }

    public class HiddenField : Field {
        public HiddenField() {
            base();
            type_ = Type.HIDDEN;
            node.put_attribute("type", "hidden");
        }
        public HiddenField.from_node(StanzaNode node) {
            base.from_node(node);
            type_ = Type.HIDDEN;
        }
    }

    public class JidMultiField : Field {
        public Gee.List<Option> options { owned get { return get_options(); } }
        public Gee.List<string> value { get; set; }
        public JidMultiField(StanzaNode node) {
            base.from_node(node);
            type_ = Type.JID_MULTI;
        }
    }

    public class ListSingleField : Field {
        public Gee.List<Option> options { owned get { return get_options(); } }
        public string value {
            owned get { return get_value_string(); }
            set { set_value_string(value); }
        }
        public ListSingleField(StanzaNode node) {
            base.from_node(node);
            type_ = Type.LIST_SINGLE;
            node.set_attribute("type", "list-single");
        }
    }

    public class ListMultiField : Field {
        public Gee.List<Option> options { owned get { return get_options(); } }
        public Gee.List<string> value { get; set; }
        public ListMultiField(StanzaNode node) {
            base.from_node(node);
            type_ = Type.LIST_MULTI;
        }
    }

    public class TextPrivateField : Field {
        public string value {
            owned get { return get_value_string(); }
            set { set_value_string(value); }
        }
        public TextPrivateField(StanzaNode node) {
            base.from_node(node);
            type_ = Type.TEXT_PRIVATE;
        }
    }

    public class TextSingleField : Field {
        public string value {
            owned get { return get_value_string(); }
            set { set_value_string(value); }
        }
        public TextSingleField(StanzaNode node) {
            base.from_node(node);
            type_ = Type.TEXT_SINGLE;
        }
    }

    // TODO text-multi

    public Gee.List<Gee.List<Field>> items = new ArrayList<Gee.List<Field>>();

    internal DataForm.from_node(StanzaNode node) {
        this.stanza_node = node;

        Gee.List<StanzaNode> field_nodes = node.get_subnodes("field", NS_URI);
        foreach (StanzaNode field_node in field_nodes) {
            parse_field(field_node, fields);
        }

        Gee.List<StanzaNode> item_nodes = node.get_subnodes("item", NS_URI);
        foreach (StanzaNode item_node in item_nodes) {
            var item_fields = new ArrayList<Field>();
            Gee.List<StanzaNode> item_field_nodes = item_node.get_subnodes("field", NS_URI);
            foreach (StanzaNode field_node in item_field_nodes) {
                parse_field(field_node, item_fields);
            }
            items.add(item_fields);
        }

        StanzaNode? instructions_node = node.get_subnode("instructions", NS_URI);
        if (instructions_node != null) {
            instructions = instructions_node.get_string_content();
        }

        StanzaNode? title_node = node.get_subnode("title", NS_URI);
        if (title_node != null) {
            title = title_node.get_string_content();
        }
    }

    private void parse_field(StanzaNode field_node, Gee.List<Field> target_list) {
        string? type = field_node.get_attribute("type", NS_URI);
        // If type is missing, it's text-single by default usually, or we infer?
        // For items, type might be missing.
        if (type == null) type = "text-single"; 

        switch (type) {
            case "boolean":
                target_list.add(new BooleanField(field_node)); break;
            case "fixed":
                target_list.add(new FixedField(field_node)); break;
            case "hidden":
                HiddenField field = new HiddenField.from_node(field_node);
                if (field.var == "FORM_TYPE") {
                    this.form_type = field.get_value_string();
                    break;
                }
                target_list.add(field); break;
            case "jid-multi":
                target_list.add(new JidMultiField(field_node)); break;
            case "list-single":
                target_list.add(new ListSingleField(field_node)); break;
            case "list-multi":
                target_list.add(new ListMultiField(field_node)); break;
            case "text-private":
                target_list.add(new TextPrivateField(field_node)); break;
            case "text-single":
                target_list.add(new TextSingleField(field_node)); break;
            case "jid-single": // Add jid-single support as it's common in search results
                target_list.add(new TextSingleField(field_node)); break; 
            default:
                target_list.add(new TextSingleField(field_node)); break;
        }
    }

    public DataForm(string type = "form") {
        this.stanza_node = new StanzaNode.build("x", NS_URI).add_self_xmlns();
        this.stanza_node.set_attribute("type", type);
    }

    public static DataForm? create_from_node(StanzaNode node) {
        return new DataForm.from_node(node);
    }

    public void add_field(Field field) {
        fields.add(field);
        stanza_node.put_node(field.node);
    }
}

}
