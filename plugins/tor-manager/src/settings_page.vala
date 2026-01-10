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

        public TorSettingsPage(TorManager manager) {
            this.manager = manager;
            this.title = "Tor Network";
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
                manager.set_enabled(state);
                return false; 
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
            
            var bridges_switch = new Switch();
            bridges_switch.valign = Align.CENTER;
            bridges_switch.active = manager.use_bridges;

            use_bridges_row.add_suffix(bridges_switch);
            bridge_group.add(use_bridges_row);
             
             var box = new Box(Orientation.VERTICAL, 0);
             box.add_css_class("card");
             box.sensitive = manager.use_bridges;
             
             var scrolled = new ScrolledWindow();
             scrolled.min_content_height = 100;
             scrolled.propagate_natural_height = true;
             
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
                on_use_bridges_toggled.begin(state);
                box.sensitive = state;
                fetch_row.sensitive = state;
                return true; // handled
            });

            // Sync main switch if manager changes state (e.g. crash or external change)
            manager.notify["is-enabled"].connect(() => {
                if (toggle.active != manager.is_enabled) {
                     toggle.active = manager.is_enabled;
                }
            });


             var help_label = new Label("Alternatively get bridges at https://bridges.torproject.org/");
             help_label.add_css_class("dim-label");
             help_label.margin_top = 6;
             bridge_group.add(help_label);
        }

        private async void on_use_bridges_toggled(bool state) {
            main_switch_row.sensitive = false;
            yield manager.update_use_bridges(state);
            main_switch_row.sensitive = true;
        }

        private void on_bridges_text_changed_debounced() {
            if (debounce_timeout_id != 0) {
                Source.remove(debounce_timeout_id);
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
                var dlg = new Adw.MessageDialog(
                    this.get_root() as Gtk.Window,
                    "Error fetching challenge",
                    e.message
                );
                dlg.add_response("ok", "OK");
                dlg.present();
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
                var err_dlg = new Adw.MessageDialog(this.get_root() as Gtk.Window, "Image Error", "Could not load CAPTCHA image.");
                err_dlg.add_response("ok", "OK");
                err_dlg.present();
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

            var dlg = new Adw.MessageDialog(
               this.get_root() as Gtk.Window,
               "Solve CAPTCHA",
               "Please type the characters you see in the image to receive bridges."
            );
            
            dlg.set_extra_child(content_area);
            dlg.add_response("cancel", "Cancel");
            dlg.add_response("submit", "Submit");
            dlg.set_response_appearance("submit", Adw.ResponseAppearance.SUGGESTED);
            
             // Handle Submit on Enter in Entry
            entry.activate.connect(() => {
                dlg.response("submit");
            });
            
            dlg.response.connect((response) => {
                if (response == "submit") {
                    string solution = entry.text;
                    submit_solution.begin(client, challenge.challenge, solution);
                }
            });
            
            dlg.present();
            entry.grab_focus();
        }

        private async void submit_solution(MoatClient client, string challenge_id, string solution) {
            try {
                string[] bridges = yield client.check_solution(challenge_id, solution);
                
                if (bridges.length > 0) {
                    StringBuilder sb = new StringBuilder();
                    foreach (string b in bridges) {
                        sb.append(b);
                        sb.append("\n");
                    }
                    
                    // Update Text Area
                    bridge_input_view.buffer.text = sb.str;
                    
                    var success_dlg = new Adw.MessageDialog(this.get_root() as Gtk.Window, "Success", "Received %d fresh bridges.".printf(bridges.length));
                    success_dlg.add_response("ok", "OK");
                    success_dlg.present();
                } else {
                     var fail_dlg = new Adw.MessageDialog(this.get_root() as Gtk.Window, "Failed", "No bridges received. Maybe the solution was wrong?");
                     fail_dlg.add_response("retry", "Try Again");
                     fail_dlg.add_response("cancel", "Cancel");
                     
                     fail_dlg.response.connect((resp) => {
                        if (resp == "retry") {
                            on_fetch_clicked.begin(); // Restart flow
                        }
                     });
                     
                     fail_dlg.present();
                }
                
            } catch (Error e) {
                var err_dlg = new Adw.MessageDialog(this.get_root() as Gtk.Window, "Error", e.message);
                err_dlg.add_response("ok", "OK");
                err_dlg.present();
            }
        }
    }
}

