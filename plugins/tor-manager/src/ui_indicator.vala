using Gtk;
using Adw;
using GLib;

namespace Dino.Plugins.TorManager {

    public class TorIndicator : Object {
        private TorManager manager;
        private MenuButton button;
        private Image icon;
        private Switch? toggle_switch;
        
        public TorIndicator(TorManager manager) {
            this.manager = manager;
            
            // We need to wait for the window to be available
            // If called from 'activate', window should be there or created shortly.
            var app = GLib.Application.get_default() as Gtk.Application;
            if (app != null) {
                app.activate.connect(() => {
                    // Give the app a moment to create the window in its own activate handler
                    Timeout.add(100, () => {
                        init_ui(app);
                        return false;
                    });
                });
                
                // If already active (e.g. plugin loaded late)
                if (app.active_window != null) {
                     init_ui(app);
                }
            }
        }

        private void init_ui(Gtk.Application app) {
            if (button != null) return; // Already initialized

            var window = app.active_window;
            if (window == null) return;

            var header = find_sidebar_header(window);
            if (header != null) {
                create_button();
                // Add before the menu button (which is pack_end)
                // If we use pack_end, it adds to the right. 
                // Existing menu is pack_end. If we pack_end, we might end up to the left or right of it depending on order.
                // Usually pack_end adds inner-most. So if menu is already there, we might be to the left of it.
                header.pack_end(button);
            } else {
                warning("TorManager: Could not find sidebar header bar to attach indicator.");
            }
        }
        
        private Adw.HeaderBar? find_sidebar_header(Widget root) {
            if (root is Adw.HeaderBar) {
                if (root.has_css_class("dino-left")) return (Adw.HeaderBar)root;
            }
            
            for (var child = root.get_first_child(); child != null; child = child.get_next_sibling()) {
                var found = find_sidebar_header(child);
                if (found != null) return found;
            }
            return null;
        }

        private void create_button() {
            button = new MenuButton();
            button.has_frame = false;
            button.tooltip_text = "Tor Network";
            
            // Icon
            icon = new Image.from_icon_name("network-server-symbolic");
            button.child = icon;
            
            // Popover
            var popover = new Popover();
            var box = new Box(Orientation.VERTICAL, 6);
            box.margin_top = 12;
            box.margin_bottom = 12;
            box.margin_start = 12; 
            box.margin_end = 12;
            box.set_size_request(250, -1);
            
            // Title
            var title = new Label("Tor Network");
            title.add_css_class("title-4");
            title.halign = Align.START;
            box.append(title);
            
            // Status Text
            var status_label = new Label("Checking status...");
            status_label.add_css_class("dim-label");
            status_label.halign = Align.START;
            status_label.wrap = true;
            status_label.xalign = 0;
            box.append(status_label);

            // Toggle Switch in a row (Simple HBox to avoid ListBoxRow requirements)
            var row_box = new Box(Orientation.HORIZONTAL, 12);
            row_box.margin_top = 6;
            
            var row_label = new Label("Enable Tor");
            row_label.halign = Align.START;
            row_label.hexpand = true;
            row_box.append(row_label);

            toggle_switch = new Switch();
            toggle_switch.valign = Align.CENTER;
            
            // Bind State
            toggle_switch.active = manager.is_enabled;
            
            // Connect signal to manager
            // Simplify: Let the switch toggle visually instantly (default behavior), just sync the manager
            toggle_switch.notify["active"].connect(() => {
                 if (manager.is_enabled != toggle_switch.active) {
                     manager.set_enabled(toggle_switch.active);
                 }
            });

            // Update UI from Manager (if changed externally or reverted)
            manager.notify["is-enabled"].connect(() => {
                if (toggle_switch.active != manager.is_enabled) {
                    toggle_switch.active = manager.is_enabled;
                }
            });
            
            row_box.append(toggle_switch);
            box.append(row_box);

            // Settings Button
            var settings_btn = new Button.with_label("Network Settings");
            settings_btn.add_css_class("pill");
            settings_btn.clicked.connect(() => {
                popover.popdown();
                // Close popover and open prefs
                var app = GLib.Application.get_default();
                if (app != null) {
                    // Invoke standard preferences action
                    // Note: direct activation uses the short name, not the "app." prefixed name used in Gtk Actionable
                     app.activate_action("preferences", null);
                }
            });
            box.append(settings_btn);
            
            popover.set_child(box);
            button.popover = popover;

            // Connect Signals for UI Updates
            manager.controller.notify["is-running"].connect(() => { update_icon(status_label); });
            manager.controller.bootstrap_status.connect((percent, summary) => {
                 // Update tooltip or status
                 status_label.label = "Bootstrap: %d%% (%s)".printf(percent, summary);
                 if (percent == 100) {
                     update_icon(status_label, true);
                 }
            });
            
            update_icon(status_label);
        }

        private void update_icon(Label status_label, bool fully_bootstrapped = false) {
            if (manager.controller.is_running) {
                // Determine color/state
                if (fully_bootstrapped || status_label.label.contains("100%")) {
                     icon.add_css_class("success"); // Use 'success' or 'accent'
                     icon.remove_css_class("warning");
                     icon.remove_css_class("error");
                     
                     string mode = manager.use_bridges ? "Bridges" : "Direct";
                     button.tooltip_text = "Tor Connected (%s)".printf(mode);
                     status_label.label = "Connected (%s)".printf(mode);
                } else {
                     icon.add_css_class("warning"); 
                     icon.remove_css_class("success");
                     button.tooltip_text = "Tor Starting...";
                     if (!status_label.label.contains("Bootstrap")) status_label.label = "Starting...";
                }
            } else {
                icon.remove_css_class("success");
                icon.remove_css_class("warning");
                button.tooltip_text = "Tor Disabled";
                status_label.label = "Tor is disabled";
            }
        }
    }
}
