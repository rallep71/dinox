using Gtk;

public class Dino.Ui.ViewModel.GeneralPreferencesPage : Object {
    public bool send_typing { get; set; }
    public bool send_marker { get; set; }
    public bool notifications { get; set; }
    public bool keep_background { get; set; }
    public bool convert_emojis { get; set; }
    public string color_scheme { get; set; }
}

[GtkTemplate (ui = "/im/github/rallep71/DinoX/preferences_window/general_preferences_page.ui")]
public class Dino.Ui.GeneralPreferencesPage : Adw.PreferencesPage {
    [GtkChild] private unowned Adw.SwitchRow typing_row;
    [GtkChild] private unowned Adw.SwitchRow marker_row;
    [GtkChild] private unowned Adw.SwitchRow notification_row;
    [GtkChild] private unowned Adw.SwitchRow keep_background_row;
    [GtkChild] private unowned Adw.SwitchRow emoji_row;
    [GtkChild] private unowned Adw.ComboRow color_scheme_row;

    public ViewModel.GeneralPreferencesPage model { get; set; default = new ViewModel.GeneralPreferencesPage(); }
    private Binding[] model_bindings = new Binding[0];

    construct {
        this.notify["model"].connect(on_model_changed);
        
        // Setup color scheme options
        var scheme_model = new Gtk.StringList(null);
        scheme_model.append("Default (Follow System)");
        scheme_model.append("Light");
        scheme_model.append("Dark");
        color_scheme_row.model = scheme_model;
    }

    private void on_model_changed() {
        foreach (Binding binding in model_bindings) {
            binding.unbind();
        }
        if (model != null) {
            model_bindings = new Binding[] {
                model.bind_property("send-typing", typing_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL),
                model.bind_property("send-marker", marker_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL),
                model.bind_property("notifications", notification_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL),
                model.bind_property("keep-background", keep_background_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL),
                model.bind_property("convert-emojis", emoji_row, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL)
            };
            
            // Bind color scheme with custom conversion
            model.notify["color-scheme"].connect(on_model_color_scheme_changed);
            color_scheme_row.notify["selected"].connect(on_ui_color_scheme_changed);
            on_model_color_scheme_changed();
        } else {
            model_bindings = new Binding[0];
        }
    }

    private void on_model_color_scheme_changed() {
        switch (model.color_scheme) {
            case "light":
                color_scheme_row.selected = 1;
                break;
            case "dark":
                color_scheme_row.selected = 2;
                break;
            default:
                color_scheme_row.selected = 0;
                break;
        }
    }

    private void on_ui_color_scheme_changed() {
        switch (color_scheme_row.selected) {
            case 1:
                model.color_scheme = "light";
                break;
            case 2:
                model.color_scheme = "dark";
                break;
            default:
                model.color_scheme = "default";
                break;
        }
    }
}
