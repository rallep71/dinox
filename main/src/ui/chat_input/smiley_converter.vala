using Gdk;
using Gee;
using Gtk;

using Dino.Entities;

namespace Dino.Ui {

class SmileyConverter {

    private TextView text_input;
    private static HashMap<string, string> smiley_translations = new HashMap<string, string>();

    static construct {
        smiley_translations[":)"] = "🙂";
        smiley_translations[":D"] = "😀";
        smiley_translations[";)"] = "😉";
        smiley_translations["O:)"] = "😇";
        smiley_translations["O:-)"] = "😇";
        smiley_translations["]:>"] = "😈";
        smiley_translations[":o"] = "😮";
        smiley_translations[":P"] = "😛";
        smiley_translations[";P"] = "😜";
        smiley_translations[":("] = "🙁";
        smiley_translations[":'("] = "😢";
        smiley_translations[":/"] = "😕";
        smiley_translations["<3"] = "❤️";
        smiley_translations[":*"] = "😘️";
        smiley_translations[":-*"] = "😘️";
    }

    public SmileyConverter(TextView text_input) {
        this.text_input = text_input;

        var text_input_key_events = new EventControllerKey() { name = "dino-smiley-converter-key-events" };
        text_input_key_events.key_pressed.connect(on_text_input_key_press);
        text_input.add_controller(text_input_key_events);
    }

    public bool on_text_input_key_press(uint keyval, uint keycode, Gdk.ModifierType state) {
        if (keyval == Key.space || keyval == Key.Return) {
            check_convert();
        }
        return false;
    }

    private void check_convert() {
        if (!Dino.Application.get_default().settings.convert_utf8_smileys) return;

        TextIter cursor_iter;
        text_input.buffer.get_iter_at_mark(out cursor_iter, text_input.buffer.get_insert());

        foreach (string smiley in smiley_translations.keys) {
            int smiley_chars = (int)smiley.length;
            
            TextIter start_iter = cursor_iter;
            if (!start_iter.backward_chars(smiley_chars)) {
                // If we couldn't go back enough chars, but we're at the start, check if the remaining text matches
                TextIter start_of_buffer;
                text_input.buffer.get_start_iter(out start_of_buffer);
                string remaining_text = text_input.buffer.get_text(start_of_buffer, cursor_iter, true);
                if (remaining_text == smiley) {
                    text_input.buffer.delete(ref start_of_buffer, ref cursor_iter);
                    text_input.buffer.insert_text(ref cursor_iter, smiley_translations[smiley], smiley_translations[smiley].length);
                    break;
                }
                continue;
            }

            string text = text_input.buffer.get_text(start_iter, cursor_iter, true);
            if (text == smiley) {
                bool is_whitespace_before = true;

                TextIter before_iter = start_iter;
                if (before_iter.backward_char()) {
                    unichar c = before_iter.get_char();
                    is_whitespace_before = c.isspace();
                }

                if (is_whitespace_before) {
                    text_input.buffer.delete(ref start_iter, ref cursor_iter);
                    text_input.buffer.insert_text(ref cursor_iter, smiley_translations[smiley], smiley_translations[smiley].length);
                    break;
                }
            }
        }
    }
}

}
