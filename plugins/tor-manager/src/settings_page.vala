using Gtk;
using Adw;

namespace Dino.Plugins.TorManager {

    public class TorSettingsPage : Adw.PreferencesPage {
        private TorManager manager;

        public TorSettingsPage(TorManager manager) {
            this.manager = manager;
            this.title = "Tor Network";
            this.icon_name = "network-server-symbolic"; 
            this.name = "tor";

            var group = new Adw.PreferencesGroup();
            group.title = "Tor Connection";
            this.add(group);

            var switch_row = new Adw.ActionRow();
            switch_row.title = "Enable Integrated Tor";
            switch_row.subtitle = "Starts a private Tor process for DinoX";
            
            var toggle = new Switch();
            toggle.valign = Align.CENTER;
            toggle.active = manager.is_enabled;
            
            toggle.state_set.connect((state) => {
                manager.set_enabled(state);
                return false; 
            });
            
            switch_row.add_suffix(toggle);
            group.add(switch_row);
            
            // Bridge Config
             var bridge_group = new Adw.PreferencesGroup();
             bridge_group.title = "Bridges (Censorship Circumvention)";
             bridge_group.description = "Paste your bridge lines here (one per line). Required if Tor is blocked.";
             this.add(bridge_group);
             
             var box = new Box(Orientation.VERTICAL, 0);
             box.add_css_class("card");
             
             var scrolled = new ScrolledWindow();
             scrolled.min_content_height = 100;
             scrolled.propagate_natural_height = true;
             
             var text_view = new TextView();
             text_view.top_margin = 12;
             text_view.bottom_margin = 12;
             text_view.left_margin = 12;
             text_view.right_margin = 12;
             text_view.wrap_mode = WrapMode.WORD_CHAR;
             text_view.buffer.text = manager.controller.bridge_lines;
             
             text_view.buffer.changed.connect(() => {
                 manager.set_bridges(text_view.buffer.text);
             });

             scrolled.set_child(text_view);
             box.append(scrolled);
             bridge_group.add(box);

             var help_label = new Label("Get bridges at https://bridges.torproject.org/");
             help_label.add_css_class("dim-label");
             help_label.margin_top = 6;
             bridge_group.add(help_label);
        }
    }
}
