using Gee;
using Gtk;
using Dino.Entities;

public class Dino.Ui.AudioSettingsPopover : Gtk.Popover {

    public signal void microphone_selected(Plugins.MediaDevice device);
    public signal void speaker_selected(Plugins.MediaDevice device);
    public signal void microphone_volume_changed(double volume);
    public signal void speaker_volume_changed(double volume);
    public signal void digital_gain_changed(int gain_db, bool manual_mode);

    public Plugins.MediaDevice? current_microphone_device { get; set; }
    public Plugins.MediaDevice? current_speaker_device { get; set; }

    private HashMap<ListBoxRow, Plugins.MediaDevice> row_microphone_device = new HashMap<ListBoxRow, Plugins.MediaDevice>();
    private HashMap<ListBoxRow, Plugins.MediaDevice> row_speaker_device = new HashMap<ListBoxRow, Plugins.MediaDevice>();
    
    private Scale? microphone_volume_scale;
    private Scale? speaker_volume_scale;
    private Scale? digital_gain_scale;
    private Switch? digital_gain_switch;

    public AudioSettingsPopover() {
        Box box = new Box(Orientation.VERTICAL, 15);
        box.append(create_microphone_box());
        box.append(create_speaker_box());

        this.set_child(box);
    }
    
    public void set_microphone_volume(double volume) {
        if (microphone_volume_scale != null) {
            microphone_volume_scale.set_value(volume);
        }
    }
    
    public void set_digital_gain_db(int gain_db) {
        if (digital_gain_scale != null) {
            // Only update UI if we are in manual mode or just to reflect state?
            // Actually, we don't get updates FROM backend usually.
            // But if we did, we should be careful not to trigger loops.
            digital_gain_scale.set_value((double) gain_db);
        }
    }

    public void set_speaker_volume(double volume) {
        if (speaker_volume_scale != null) {
            speaker_volume_scale.set_value(volume);
        }
    }

    private Widget create_microphone_box() {
        Plugins.VideoCallPlugin call_plugin = Dino.Application.get_default().plugin_registry.video_call_plugin;
        Gee.List<Plugins.MediaDevice> devices = call_plugin.get_devices("audio", false);

        Box micro_box = new Box(Orientation.VERTICAL, 10);
        micro_box.append(new Label("<b>" + _("Microphones") + "</b>") { use_markup=true, xalign=0, can_focus=true /* grab initial focus*/ });

        if (devices.size == 0) {
            micro_box.append(new Label(_("No microphone found.")));
        } else {
            ListBox micro_list_box = new ListBox() { activate_on_single_click=true, selection_mode=SelectionMode.SINGLE };
            micro_list_box.set_header_func(listbox_header_func);
            Frame micro_frame = new Frame(null);
            micro_frame.set_child(micro_list_box);
            foreach (Plugins.MediaDevice device in devices) {
                Label display_name_label = new Label(device.display_name) { xalign=0 };
                Image image = new Image.from_icon_name("object-select-symbolic");
                if (current_microphone_device == null || current_microphone_device.id != device.id) {
                    image.opacity = 0;
                }
                this.notify["current-microphone-device"].connect(() => {
                    if (current_microphone_device == null || current_microphone_device.id != device.id) {
                        image.opacity = 0;
                    } else {
                        image.opacity = 1;
                    }
                });
                Box device_box = new Box(Orientation.HORIZONTAL, 0) { spacing=7 };
                device_box.append(image);
                Box label_box = new Box(Orientation.VERTICAL, 0);
                label_box.append(display_name_label);
                if (device.detail_name != null) {
                    Label detail_name_label = new Label(device.detail_name) { xalign=0 };
                    detail_name_label.add_css_class("dim-label");
                    detail_name_label.attributes = new Pango.AttrList();
                    detail_name_label.attributes.insert(Pango.attr_scale_new(0.8));
                    label_box.append(detail_name_label);
                }
                device_box.append(label_box);
                ListBoxRow list_box_row = new ListBoxRow();
                list_box_row.set_child(device_box);
                micro_list_box.append(list_box_row);

                row_microphone_device[list_box_row] = device;
            }
            micro_list_box.row_activated.connect((row) => {
                if (!row_microphone_device.has_key(row)) return;
                microphone_selected(row_microphone_device[row]);
                micro_list_box.unselect_row(row);
            });
            micro_box.append(micro_frame);
            
            // Volume slider for microphone
            Box volume_box = new Box(Orientation.HORIZONTAL, 8);
            volume_box.append(new Image.from_icon_name("microphone-sensitivity-low-symbolic"));
            microphone_volume_scale = new Scale.with_range(Orientation.HORIZONTAL, 0.0, 1.0, 0.05);
            microphone_volume_scale.set_value(1.0);
            microphone_volume_scale.hexpand = true;
            microphone_volume_scale.draw_value = false;
            microphone_volume_scale.value_changed.connect(() => {
                microphone_volume_changed(microphone_volume_scale.get_value());
            });
            volume_box.append(microphone_volume_scale);
            volume_box.append(new Image.from_icon_name("microphone-sensitivity-high-symbolic"));
            micro_box.append(volume_box);

            // Digital Gain Slider
            Box gain_box = new Box(Orientation.HORIZONTAL, 8);
            gain_box.append(new Label(_("WebRTC Gain:")));
            
            digital_gain_switch = new Switch();
            digital_gain_switch.valign = Align.CENTER;
            digital_gain_switch.active = false; // Default: OFF (Adaptive)
            gain_box.append(digital_gain_switch);
            
            digital_gain_scale = new Scale.with_range(Orientation.HORIZONTAL, 0.0, 30.0, 1.0);
            digital_gain_scale.set_value(9.0); // Default
            digital_gain_scale.hexpand = true;
            digital_gain_scale.draw_value = true;
            digital_gain_scale.value_pos = PositionType.RIGHT;
            digital_gain_scale.set_digits(0);
            digital_gain_scale.sensitive = false; // Initially disabled
            
            digital_gain_scale.value_changed.connect(() => {
                if (digital_gain_switch.active) {
                    digital_gain_changed((int) digital_gain_scale.get_value(), true);
                }
            });
            
            digital_gain_switch.notify["active"].connect(() => {
                bool is_active = digital_gain_switch.active;
                debug("AudioSettingsPopover: Switch toggled. Active: %s", is_active.to_string());
                digital_gain_scale.sensitive = is_active;
                if (is_active) {
                    digital_gain_changed((int) digital_gain_scale.get_value(), true);
                } else {
                    // Revert to default/adaptive
                    digital_gain_changed(9, false); // 9 is default
                }
            });
            
            gain_box.append(digital_gain_scale);
            micro_box.append(gain_box);
        }

        return micro_box;
    }

    private Widget create_speaker_box() {
        Plugins.VideoCallPlugin call_plugin = Dino.Application.get_default().plugin_registry.video_call_plugin;
        Gee.List<Plugins.MediaDevice> devices = call_plugin.get_devices("audio", true);

        Box speaker_box = new Box(Orientation.VERTICAL, 10);
        speaker_box.append(new Label("<b>" + _("Speakers") +"</b>") { use_markup=true, xalign=0 });

        if (devices.size == 0) {
            speaker_box.append(new Label(_("No speaker found.")));
        } else {
            ListBox speaker_list_box = new ListBox() { activate_on_single_click=true, selection_mode=SelectionMode.SINGLE };
            speaker_list_box.set_header_func(listbox_header_func);
            speaker_list_box.row_selected.connect((row) => {

            });
            Frame speaker_frame = new Frame(null);
            speaker_frame.set_child(speaker_list_box);
            foreach (Plugins.MediaDevice device in devices) {
                Label display_name_label = new Label(device.display_name) { xalign=0 };
                Image image = new Image.from_icon_name("object-select-symbolic");
                if (current_speaker_device == null || current_speaker_device.id != device.id) {
                    image.opacity = 0;
                }
                this.notify["current-speaker-device"].connect(() => {
                    if (current_speaker_device == null || current_speaker_device.id != device.id) {
                        image.opacity = 0;
                    } else {
                        image.opacity = 1;
                    }
                });
                Box device_box = new Box(Orientation.HORIZONTAL, 0) { spacing=7 };
                device_box.append(image);
                Box label_box = new Box(Orientation.VERTICAL, 0) { visible = true };
                label_box.append(display_name_label);
                if (device.detail_name != null) {
                    Label detail_name_label = new Label(device.detail_name) { xalign=0 };
                    detail_name_label.add_css_class("dim-label");
                    detail_name_label.attributes = new Pango.AttrList();
                    detail_name_label.attributes.insert(Pango.attr_scale_new(0.8));
                    label_box.append(detail_name_label);
                }
                device_box.append(label_box);
                ListBoxRow list_box_row = new ListBoxRow();
                list_box_row.set_child(device_box);
                speaker_list_box.append(list_box_row);

                row_speaker_device[list_box_row] = device;
            }
            speaker_list_box.row_activated.connect((row) => {
                if (!row_speaker_device.has_key(row)) return;
                speaker_selected(row_speaker_device[row]);
                speaker_list_box.unselect_row(row);
            });
            speaker_box.append(speaker_frame);
            
            // Volume slider for speaker
            Box volume_box = new Box(Orientation.HORIZONTAL, 8);
            volume_box.append(new Image.from_icon_name("audio-volume-low-symbolic"));
            speaker_volume_scale = new Scale.with_range(Orientation.HORIZONTAL, 0.0, 1.0, 0.05);
            speaker_volume_scale.set_value(1.0);
            speaker_volume_scale.hexpand = true;
            speaker_volume_scale.draw_value = false;
            speaker_volume_scale.value_changed.connect(() => {
                speaker_volume_changed(speaker_volume_scale.get_value());
            });
            volume_box.append(speaker_volume_scale);
            volume_box.append(new Image.from_icon_name("audio-volume-high-symbolic"));
            speaker_box.append(volume_box);
        }

        return speaker_box;
    }

    private void listbox_header_func(ListBoxRow row, ListBoxRow? before_row) {
        if (row.get_header() == null && before_row != null) {
            row.set_header(new Separator(Orientation.HORIZONTAL));
        }
    }

}
