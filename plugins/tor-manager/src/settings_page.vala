using Gtk;
using Adw;
using Gdk;
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

        public TorSettingsPage(TorManager manager) {
            this.manager = manager;
            this.title = "Tor";
            this.icon_name = "network-server-symbolic"; 
            this.name = "tor";

            var group = new Adw.PreferencesGroup();
            group.title = "Tor Connection";
            this.add(group);

            main_switch_row = new Adw.ActionRow();
            main_switch_row.title = "Enable Integrated Tor";
            main_switch_row.subtitle = "Starts a private Tor process for DinoX";
            
            var toggle = new Switch();
            toggle.valign = Align.CENTER;
            toggle.active = manager.is_enabled;
            
            toggle.state_set.connect((state) => {
                toggle.state = state;
                manager.set_enabled.begin(state);
                return true; 
            });
            
            main_switch_row.add_suffix(toggle);
            group.add(main_switch_row);
            
            // Bridge Config
             var bridge_group = new Adw.PreferencesGroup();
             bridge_group.title = "Bridges (Censorship Circumvention)";
             bridge_group.description = "Required if Tor is blocked by your ISP or government.";
             this.add(bridge_group);

             // Use Bridges Switch
            var use_bridges_row = new Adw.ActionRow();
            use_bridges_row.title = "Use Bridges";
            use_bridges_row.subtitle = "Hides the fact that you are using Tor.";
            
            bridges_switch = new Switch();
            bridges_switch.valign = Align.CENTER;
            bridges_switch.active = manager.use_bridges;

            use_bridges_row.add_suffix(bridges_switch);
            bridge_group.add(use_bridges_row);


            // Fascist Firewall Switch
            var firewall_row = new Adw.ActionRow();
            firewall_row.title = "Firewall Mode (Port 80/443 Only)";
            firewall_row.subtitle = "Only connect to bridges using standard web ports. Helps behind strict firewalls.";
             
            firewall_switch = new Switch();
            firewall_switch.valign = Align.CENTER;
            firewall_switch.active = manager.force_firewall_ports;
            
            // Warning Label for Firewall + Bridges
            warning_label = new Label("Warning: Only bridges on port 80/443 will work when Firewall Mode is enabled!");
            warning_label.add_css_class("error"); // Red text
            warning_label.halign = Align.START;
            warning_label.wrap = true;
            warning_label.xalign = 0;
            warning_label.margin_start = 12;
            warning_label.margin_bottom = 12;
            warning_label.visible = false;
            
            firewall_switch.state_set.connect((state) => {
                 firewall_switch.state = state;
                 on_firewall_toggled.begin(state);
                 update_warning();
                 return true;
            });

            firewall_row.add_suffix(firewall_switch);
            bridge_group.add(firewall_row);
            bridge_group.add(warning_label);
            
            update_warning();


             var box = new Box(Orientation.VERTICAL, 0);
             box.add_css_class("card");
             box.sensitive = manager.use_bridges;
             
             // Label for manual input
             var manual_label = new Label("Bridge List (Auto or Manual Entry)");
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

             // Action Row for Fetching
             var fetch_row = new Adw.ActionRow();
             fetch_row.title = "Request Fresh Bridges";
             fetch_row.subtitle = "Connects to Tor Project (Moat) to fetch unblocked bridges.";
             fetch_row.sensitive = manager.use_bridges;
             
             fetch_button = new Button.with_label("Request");
             fetch_button.valign = Align.CENTER;
             fetch_button.clicked.connect(on_fetch_clicked);
             
             fetch_row.add_suffix(fetch_button);
             bridge_group.add(fetch_row);

            // Connect signal late to ensure all widgets exist
            bridges_switch.state_set.connect((state) => {
                bridges_switch.state = state;
                on_use_bridges_toggled.begin(state);
                box.sensitive = state;
                fetch_row.sensitive = state;
                firewall_row.sensitive = state; 
                update_warning();
                return true; // handled
            });

            // Init sensitive state
            firewall_row.sensitive = manager.use_bridges;

            // Sync main switch if manager changes state (e.g. crash or external change)
            manager.notify["is-enabled"].connect(() => {
                if (toggle.active != manager.is_enabled) {
                     toggle.active = manager.is_enabled;
                }
            });


             var help_label = new Label("Alternatively get bridges at https://bridges.torproject.org/");
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
            fetch_button.label = "Loading...";
            
            try {
                var client = new MoatClient();
                var challenge = yield client.fetch_challenge();
                
                // Show Dialog
                prompt_captcha_solution(client, challenge);
                
            } catch (Error e) {
                var dlg = new Adw.AlertDialog(
                    "Error fetching challenge",
                    e.message
                );
                dlg.add_response("ok", "OK");
                dlg.present(this.get_root() as Gtk.Window);
            } finally {
                fetch_button.sensitive = true;
                fetch_button.label = "Request";
            }
        }

        private void prompt_captcha_solution(MoatClient client, MoatChallenge challenge) {
            // Decode Base64 Image
            uchar[] data = Base64.decode(challenge.image);
            var bytes = new Bytes(data);
            var stream = new MemoryInputStream.from_bytes(bytes);
            
            Texture texture = null;
            try {
                var pixbuf = new Gdk.Pixbuf.from_stream(stream, null);
                texture = Gdk.Texture.for_pixbuf(pixbuf);
            } catch (Error e) {
                warning("Failed to create texture from captcha: %s", e.message);
                var err_dlg = new Adw.AlertDialog("Image Error", "Could not load CAPTCHA image.");
                err_dlg.add_response("ok", "OK");
                err_dlg.present(this.get_root() as Gtk.Window);
                return;
            }

            // Build Custom Dialog Content
            var content_area = new Box(Orientation.VERTICAL, 12);
            content_area.margin_top = 12;
            content_area.margin_bottom = 12;
            content_area.margin_start = 12;
            content_area.margin_end = 12;
            
            var image_widget = new Picture.for_paintable(texture);
            image_widget.height_request = 100;
            image_widget.content_fit = ContentFit.CONTAIN;
            content_area.append(image_widget);
            
            var entry = new Entry();
            entry.placeholder_text = "Type characters from image...";
            content_area.append(entry);

            var dlg = new Adw.AlertDialog(
               "Solve CAPTCHA",
               "Please type the characters you see in the image to receive bridges."
            );
            
            dlg.extra_child = content_area;
            dlg.add_response("cancel", "Cancel");
            dlg.add_response("submit", "Submit");
            dlg.set_response_appearance("submit", Adw.ResponseAppearance.SUGGESTED);
            dlg.default_response = "submit";
            
             // Handle Submit on Enter in Entry
            entry.activates_default = true;
            
            dlg.response.connect((response) => {
                if (response == "submit") {
                    string solution = entry.text;
                    submit_solution.begin(client, challenge.challenge, solution);
                }
            });
            
            dlg.present(this.get_root() as Gtk.Window);
            entry.grab_focus();
        }

        private async void submit_solution(MoatClient client, string challenge_id, string solution) {
            try {
                string[] bridges = yield client.check_solution(challenge_id, solution);
                
                if (bridges.length > 0) {
                    // Sort bridges to prefer port 443/80
                    int good_ports = 0;
                    Gee.ArrayList<string> sorted_bridges = new Gee.ArrayList<string>();
                    foreach(string b in bridges) {
                         if (b.contains(":443 ") || b.contains(":80 ") || b.contains(":4433 ")) {
                             sorted_bridges.insert(0, b);
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
                    
                    // Update Text Area
                    debug("TorSettingsPage: Applying new bridges (sorted) to UI:\n%s", new_bridges_text);
                    
                    // Use flag to prevent double-save via debounce
                    ignore_text_changes = true;
                    // Force a delete-insert cycle to ensure GTK updates the view
                    bridge_input_view.buffer.set_text(""); 
                    while (MainContext.default().pending()) MainContext.default().iteration(false); // Force UI redraw for a split second
                    bridge_input_view.buffer.set_text(new_bridges_text);
                    ignore_text_changes = false;

                    // Explicitly save and restart Tor immediately
                    debug("TorSettingsPage: Explicitly saving new bridges...");
                    yield manager.set_bridges(new_bridges_text);

                    string msg = "Received %d fresh bridges.".printf(bridges.length);
                    if (good_ports > 0) {
                        msg += "\n\nGood news! We found %d bridges on common ports (443/80). These are prioritized.".printf(good_ports);
                    } else {
                        msg += "\n\nWarning: None of the bridges use standard ports (443/80). If you are behind a strict firewall, you might need to try again.";
                    }

                    var success_dlg = new Adw.AlertDialog("Success", msg);
                    success_dlg.add_response("ok", "OK");
                    if (good_ports == 0) {
                         success_dlg.add_response("retry", "Try Again");
                    }

                    success_dlg.response.connect((resp) => {
                        if (resp == "retry") {
                            on_fetch_clicked.begin(); 
                        }
                    });

                    success_dlg.present(this.get_root() as Gtk.Window);
                } else {
                     var fail_dlg = new Adw.AlertDialog("Failed", "No bridges received. Maybe the solution was wrong?");
                     fail_dlg.add_response("retry", "Try Again");
                     fail_dlg.add_response("cancel", "Cancel");
                     
                     fail_dlg.response.connect((resp) => {
                        if (resp == "retry") {
                            on_fetch_clicked.begin(); // Restart flow
                        }
                     });
                     
                     fail_dlg.present(this.get_root() as Gtk.Window);
                }
                
            } catch (Error e) {
                var err_dlg = new Adw.AlertDialog("Error", e.message);
                err_dlg.add_response("ok", "OK");
                err_dlg.present(this.get_root() as Gtk.Window);
            }
        }
    }
}

