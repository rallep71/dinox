using Gtk;
using Adw;
using GLib;

namespace Dino.Plugins.TorManager {

    public class TorSettingsPage : Adw.PreferencesPage {
        private TorManager manager;
        private TextView bridge_input_view;
        private Button fetch_button;
        private Adw.ActionRow main_switch_row;
        private uint debounce_timeout_id = 0;
        private bool ignore_text_changes = false;
        
        private Switch firewall_switch;
        private Switch bridges_switch;
        private Label warning_label;
        private Gtk.DropDown transport_dropdown;

        public TorSettingsPage(TorManager manager) {
            this.manager = manager;
            this.title = _("Tor");
            this.icon_name = "network-server-symbolic"; 
            this.name = "tor";

            var group = new Adw.PreferencesGroup();
            group.title = _("Tor Connection");
            this.add(group);

            main_switch_row = new Adw.ActionRow();
            main_switch_row.title = _("Enable Integrated Tor");
            main_switch_row.subtitle = _("Starts a private Tor process for DinoX");
            
            var toggle = new Switch();
            toggle.valign = Align.CENTER;
            toggle.active = manager.is_enabled;
            
            toggle.notify["active"].connect(() => {
                if (manager.is_enabled != toggle.active) {
                    manager.set_enabled.begin(toggle.active);
                }
            });
            
            main_switch_row.add_suffix(toggle);
            group.add(main_switch_row);
            
            // Bridge Config
             var bridge_group = new Adw.PreferencesGroup();
             bridge_group.title = _("Bridges (Censorship Circumvention)");
             bridge_group.description = _("Required if Tor is blocked. Supports obfs4 and WebTunnel bridges.");
             this.add(bridge_group);

             // Use Bridges Switch
            var use_bridges_row = new Adw.ActionRow();
            use_bridges_row.title = _("Use Bridges");
            use_bridges_row.subtitle = _("Hides the fact that you are using Tor.");
            
            bridges_switch = new Switch();
            bridges_switch.valign = Align.CENTER;
            bridges_switch.active = manager.use_bridges;

            use_bridges_row.add_suffix(bridges_switch);
            bridge_group.add(use_bridges_row);


            // Fascist Firewall Switch
            var firewall_row = new Adw.ActionRow();
            firewall_row.title = _("Firewall Mode (Port 80/443 Only)");
            firewall_row.subtitle = _("Only connect to bridges using standard web ports. Helps behind strict firewalls.");
             
            firewall_switch = new Switch();
            firewall_switch.valign = Align.CENTER;
            firewall_switch.active = manager.force_firewall_ports;
            
            // Warning Label for Firewall + Bridges
            warning_label = new Label(_("Warning: Only bridges on port 80/443 will work when Firewall Mode is enabled!"));
            warning_label.add_css_class("error"); // Red text
            warning_label.halign = Align.START;
            warning_label.wrap = true;
            warning_label.xalign = 0;
            warning_label.margin_start = 12;
            warning_label.margin_bottom = 12;
            warning_label.visible = false;
            
            firewall_switch.notify["active"].connect(() => {
                on_firewall_toggled.begin(firewall_switch.active);
                update_warning();
            });

            firewall_row.add_suffix(firewall_switch);
            bridge_group.add(firewall_row);
            bridge_group.add(warning_label);
            
            update_warning();


             var box = new Box(Orientation.VERTICAL, 0);
             box.add_css_class("card");
             box.sensitive = manager.use_bridges;
             
             // Label for manual input
             var manual_label = new Label(_("Bridge List (Auto or Manual Entry)"));
             manual_label.halign = Align.START;
             manual_label.margin_start = 12;
             manual_label.margin_top = 12;
             manual_label.add_css_class("heading");
             box.append(manual_label);

             var scrolled = new ScrolledWindow();
             scrolled.min_content_height = 100;
             scrolled.propagate_natural_height = true;
             // Add frame for input look
             scrolled.add_css_class("frame"); 
             
             bridge_input_view = new TextView();
             bridge_input_view.top_margin = 12;
             bridge_input_view.bottom_margin = 12;
             bridge_input_view.left_margin = 12;
             bridge_input_view.right_margin = 12;
             bridge_input_view.wrap_mode = WrapMode.WORD_CHAR;
             bridge_input_view.buffer.text = manager.controller.bridge_lines;
             
             bridge_input_view.buffer.changed.connect(() => {
                 on_bridges_text_changed_debounced();
             });

             scrolled.set_child(bridge_input_view);
             box.append(scrolled);
             bridge_group.add(box);

             // Action Row for Fetching with transport selector
             var fetch_row = new Adw.ActionRow();
             fetch_row.title = _("Request Fresh Bridges");
             fetch_row.subtitle = _("Fetches bridges from Tor Project. Choose transport type:");
             fetch_row.sensitive = manager.use_bridges;

             // Transport type dropdown: obfs4 or webtunnel
             string[] transport_labels = { "obfs4", "WebTunnel" };
             transport_dropdown = new Gtk.DropDown.from_strings(transport_labels);
             transport_dropdown.selected = 1; // Default: WebTunnel (best for strict firewalls)
             transport_dropdown.valign = Align.CENTER;
             fetch_row.add_suffix(transport_dropdown);
             
             fetch_button = new Button.with_label(_("Request"));
             fetch_button.valign = Align.CENTER;
             fetch_button.clicked.connect(() => { on_fetch_clicked.begin(); });
             
             fetch_row.add_suffix(fetch_button);
             bridge_group.add(fetch_row);

            // Connect signal late to ensure all widgets exist
            bridges_switch.notify["active"].connect(() => {
                bool active = bridges_switch.active;
                on_use_bridges_toggled.begin(active);
                box.sensitive = active;
                fetch_row.sensitive = active;
                firewall_row.sensitive = active;
                update_warning();
            });

            // Init sensitive state
            firewall_row.sensitive = manager.use_bridges;

            // Sync main switch if manager changes state (e.g. crash or external change)
            manager.notify["is-enabled"].connect(() => {
                if (toggle.active != manager.is_enabled) {
                     toggle.active = manager.is_enabled;
                }
            });


             var help_label = new Label(_("WebTunnel (port 443, looks like HTTPS) is best for strict firewalls. obfs4 is more widely available. Both fetch instantly without CAPTCHA."));
             help_label.add_css_class("dim-label");
             help_label.margin_top = 6;
             help_label.wrap = true;
             help_label.xalign = 0;
             help_label.halign = Align.START;
             bridge_group.add(help_label);
        }

        private async void on_use_bridges_toggled(bool state) {
            main_switch_row.sensitive = false;
            yield manager.update_use_bridges(state);
            main_switch_row.sensitive = true;
        }

        private void update_warning() {
            if (warning_label != null && bridges_switch != null && firewall_switch != null) {
                warning_label.visible = bridges_switch.active && firewall_switch.active;
            }
        }

        private async void on_firewall_toggled(bool state) {
            main_switch_row.sensitive = false;
            yield manager.update_firewall_ports(state);
            main_switch_row.sensitive = true;
        }

        private void on_bridges_text_changed_debounced() {
            if (ignore_text_changes) return;
            
            if (debounce_timeout_id != 0) {
                Source.remove(debounce_timeout_id);
                debounce_timeout_id = 0;
            }
            debounce_timeout_id = Timeout.add(1500, () => {
                commit_bridges_text.begin();
                debounce_timeout_id = 0;
                return false;
            });
        }

        private async void commit_bridges_text() {
            main_switch_row.sensitive = false;
            yield manager.set_bridges(bridge_input_view.buffer.text);
            main_switch_row.sensitive = true;
        }

        private async void on_fetch_clicked() {
            fetch_button.sensitive = false;
            fetch_button.label = _("Loading...");
            
            // Get selected transport from dropdown
            string transport = transport_dropdown.selected == 0 ? "obfs4" : "webtunnel";
            
            try {
                var client = new BridgeClient();
                string[] bridges = yield client.fetch_bridges(transport);
                yield apply_fetched_bridges(bridges, transport);
            } catch (Error e) {
                var dlg = new Adw.AlertDialog(
                    _("Error fetching bridges"),
                    e.message
                );
                dlg.add_response("ok", _("OK"));
                dlg.present(this.get_root() as Gtk.Window);
            } finally {
                fetch_button.sensitive = true;
                fetch_button.label = _("Request");
            }
        }

        private async void apply_fetched_bridges(string[] bridges, string transport) {
            if (bridges.length > 0) {
                // Sort bridges: prefer webtunnel, then obfs4 on port 443/80
                int good_ports = 0;
                Gee.ArrayList<string> sorted_bridges = new Gee.ArrayList<string>();
                foreach(string b in bridges) {
                     if (b.has_prefix("webtunnel ")) {
                         sorted_bridges.insert(0, b);
                         good_ports++;
                     } else if (b.contains(":443 ") || b.contains(":80 ") || b.contains(":4433 ")) {
                         sorted_bridges.insert(good_ports, b);
                         good_ports++;
                     } else {
                         sorted_bridges.add(b);
                     }
                }

                StringBuilder sb = new StringBuilder();
                foreach (string b in sorted_bridges) {
                    sb.append(b);
                    sb.append("\n");
                }
                
                string new_bridges_text = sb.str;
                
                debug("TorSettingsPage: Applying new bridges (sorted) to UI:\n%s", new_bridges_text);
                
                ignore_text_changes = true;
                bridge_input_view.buffer.set_text(""); 
                while (MainContext.default().pending()) MainContext.default().iteration(false);
                bridge_input_view.buffer.set_text(new_bridges_text);
                ignore_text_changes = false;

                debug("TorSettingsPage: Explicitly saving new bridges...");
                yield manager.set_bridges(new_bridges_text);

                string msg = _("Received %d %s bridge(s).").printf(bridges.length, transport);

                if (good_ports > 0) {
                    msg += "\n" + _("%d bridge(s) on standard ports (443/80).").printf(good_ports);
                }

                var success_dlg = new Adw.AlertDialog(_("Success"), msg);
                success_dlg.add_response("ok", _("OK"));
                if (good_ports == 0) {
                     success_dlg.add_response("retry", _("Try Again"));
                }

                success_dlg.response.connect((resp) => {
                    if (resp == "retry") {
                        on_fetch_clicked.begin(); 
                    }
                });

                success_dlg.present(this.get_root() as Gtk.Window);
            } else {
                 var fail_dlg = new Adw.AlertDialog(_("Failed"), _("No bridges received. The server may be temporarily unavailable."));
                 fail_dlg.add_response("retry", _("Try Again"));
                 fail_dlg.add_response("cancel", _("Cancel"));
                 
                 fail_dlg.response.connect((resp) => {
                    if (resp == "retry") {
                        on_fetch_clicked.begin();
                    }
                 });
                 
                 fail_dlg.present(this.get_root() as Gtk.Window);
            }
        }
    }
}

