using Dino.Ui.ViewModel.PreferencesRow;

/**
 * GObject Property/Signal Contract Tests for PreferencesRow View Models
 *
 * Spec: GObject property system (GLib Reference Manual, Section "GObject properties")
 *   - g_object_set/get MUST round-trip values
 *   - notify signal MUST fire on property change
 *   - Signal emission MUST invoke connected handlers
 *
 * These view models are the data layer for GTK preference UI rows.
 * They have ZERO GTK dependencies and are pure GObject classes.
 */
namespace Dino.Ui.Test {

class PreferencesRowTest : Gee.TestCase {

    public PreferencesRowTest() {
        base("PreferencesRow");

        // GObject property contract: Any (base class)
        add_test("GObject_Text_title_roundtrip", test_text_title);
        add_test("GObject_Text_text_roundtrip", test_text_text);
        add_test("GObject_Text_media_type_nullable", test_text_media_nullable);

        // GObject property contract: Entry
        add_test("GObject_Entry_text_roundtrip", test_entry_text);
        add_test("GObject_Entry_changed_signal_fires", test_entry_changed_signal);
        add_test("GObject_Entry_notify_on_text_change", test_entry_notify);

        // GObject property contract: PrivateText
        add_test("GObject_PrivateText_text_roundtrip", test_private_text);
        add_test("GObject_PrivateText_changed_signal_fires", test_private_changed);

        // GObject property contract: Toggle
        add_test("GObject_Toggle_state_default_false", test_toggle_default);
        add_test("GObject_Toggle_state_roundtrip", test_toggle_state);
        add_test("GObject_Toggle_subtitle_roundtrip", test_toggle_subtitle);

        // GObject property contract: ComboBox
        add_test("GObject_ComboBox_items_list_operations", test_combobox_items);
        add_test("GObject_ComboBox_active_item_roundtrip", test_combobox_active);

        // GObject property contract: Button
        add_test("GObject_Button_text_roundtrip", test_button_text);
        add_test("GObject_Button_clicked_signal_fires", test_button_clicked);

        // Inheritance: all subtypes are-a Any
        add_test("GObject_inheritance_all_subtypes_are_Any", test_inheritance);
    }

    // --- Text (also tests Any base properties) ---

    void test_text_title() {
        var row = new Text();
        row.title = "Account Name";
        fail_if_not_eq_str("Account Name", row.title);

        // Change title
        row.title = "Updated";
        fail_if_not_eq_str("Updated", row.title);
    }

    void test_text_text() {
        var row = new Text();
        row.text = "Hello World";
        fail_if_not_eq_str("Hello World", row.text);
    }

    void test_text_media_nullable() {
        var row = new Text();
        // Default should be null
        assert_true(row.media_type == null, "media_type should default to null");
        assert_true(row.media_uri == null, "media_uri should default to null");

        // Set values
        row.media_type = "image/png";
        row.media_uri = "/path/to/image.png";
        fail_if_not_eq_str("image/png", row.media_type);
        fail_if_not_eq_str("/path/to/image.png", row.media_uri);

        // Reset to null
        row.media_type = null;
        assert_true(row.media_type == null, "media_type should accept null");
    }

    // --- Entry ---

    void test_entry_text() {
        var row = new Entry();
        row.title = "Username";
        row.text = "alice@example.com";
        fail_if_not_eq_str("alice@example.com", row.text);
        fail_if_not_eq_str("Username", row.title);
    }

    void test_entry_changed_signal() {
        var row = new Entry();
        int signal_count = 0;
        row.changed.connect(() => {
            signal_count++;
        });

        // Emit signal
        row.changed();
        fail_if_not_eq_int(1, signal_count);

        // Emit again
        row.changed();
        fail_if_not_eq_int(2, signal_count);
    }

    void test_entry_notify() {
        var row = new Entry();
        int notify_count = 0;
        row.notify["text"].connect(() => {
            notify_count++;
        });

        row.text = "first";
        fail_if_not_eq_int(1, notify_count);

        row.text = "second";
        fail_if_not_eq_int(2, notify_count);
    }

    // --- PrivateText ---

    void test_private_text() {
        var row = new PrivateText();
        row.text = "s3cr3t";
        fail_if_not_eq_str("s3cr3t", row.text);
    }

    void test_private_changed() {
        var row = new PrivateText();
        bool fired = false;
        row.changed.connect(() => { fired = true; });
        row.changed();
        assert_true(fired, "PrivateText changed signal must fire");
    }

    // --- Toggle ---

    void test_toggle_default() {
        var row = new Toggle();
        // GObject bool properties default to false
        assert_false(row.state, "Toggle state should default to false");
    }

    void test_toggle_state() {
        var row = new Toggle();
        row.state = true;
        assert_true(row.state, "Toggle state should be true after set");
        row.state = false;
        assert_false(row.state, "Toggle state should be false after reset");
    }

    void test_toggle_subtitle() {
        var row = new Toggle();
        row.subtitle = "Enable notifications";
        fail_if_not_eq_str("Enable notifications", row.subtitle);
    }

    // --- ComboBox ---

    void test_combobox_items() {
        var row = new ComboBox();

        // Items list starts empty
        fail_if_not_eq_int(0, row.items.size);

        // Add items
        row.items.add("Option A");
        row.items.add("Option B");
        row.items.add("Option C");
        fail_if_not_eq_int(3, row.items.size);
        fail_if_not_eq_str("Option A", row.items[0]);
        fail_if_not_eq_str("Option B", row.items[1]);
        fail_if_not_eq_str("Option C", row.items[2]);

        // Remove item
        row.items.remove_at(1);
        fail_if_not_eq_int(2, row.items.size);
        fail_if_not_eq_str("Option C", row.items[1]);
    }

    void test_combobox_active() {
        var row = new ComboBox();
        row.items.add("First");
        row.items.add("Second");

        row.active_item = 0;
        fail_if_not_eq_int(0, row.active_item);

        row.active_item = 1;
        fail_if_not_eq_int(1, row.active_item);
    }

    // --- Button ---

    void test_button_text() {
        var row = new Button();
        row.button_text = "Save";
        fail_if_not_eq_str("Save", row.button_text);
    }

    void test_button_clicked() {
        var row = new Button();
        int click_count = 0;
        row.clicked.connect(() => {
            click_count++;
        });

        row.clicked();
        fail_if_not_eq_int(1, click_count);

        row.clicked();
        row.clicked();
        fail_if_not_eq_int(3, click_count);
    }

    // --- Inheritance ---

    void test_inheritance() {
        // All subtypes MUST be instances of Any
        assert_true(new Text() is Any, "Text must be-a Any");
        assert_true(new Entry() is Any, "Entry must be-a Any");
        assert_true(new PrivateText() is Any, "PrivateText must be-a Any");
        assert_true(new Toggle() is Any, "Toggle must be-a Any");
        assert_true(new ComboBox() is Any, "ComboBox must be-a Any");
        assert_true(new Button() is Any, "Button must be-a Any");

        // Title property must be accessible through base type
        Any any = new Text();
        any.title = "Base Access";
        fail_if_not_eq_str("Base Access", any.title);
    }
}

}
