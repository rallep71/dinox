using Gee;
using Gtk;

using Dino.Entities;

namespace Dino.Ui {

class AccountComboBox : Box {

    private DropDown dropdown;

    public Account? active_account {
        get {
            return dropdown.selected_item as Account;
        }
        set {
            if (value == null) {
                return;
            }
            
            var list_model = dropdown.model as GLib.ListStore;
            if (list_model != null) {
                for (uint i = 0; i < list_model.get_n_items(); i++) {
                    var item = list_model.get_item(i) as Account;
                    if (item != null && item.equals(value)) {
                        dropdown.selected = i;
                        break;
                    }
                }
            }
        }
    }

    private StreamInteractor? stream_interactor;

    construct {
        orientation = Orientation.HORIZONTAL;
        spacing = 0;
        
        // Create empty model and set expression immediately to avoid GTK warnings
        var empty_model = new GLib.ListStore(typeof(Account));
        dropdown = new DropDown(empty_model, new PropertyExpression(typeof(Account), null, "display_name"));
        dropdown.hexpand = true;
        append(dropdown);
        
        dropdown.notify["selected-item"].connect(() => {
            notify_property("active-account");
        });
    }

    public void initialize(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;

        var list_store = new GLib.ListStore(typeof(Account));
        foreach (Account account in stream_interactor.get_accounts()) {
            if (account.enabled) {
                list_store.append(account);
            }
        }
        
        dropdown.model = list_store;
        dropdown.expression = new PropertyExpression(typeof(Account), null, "display_name");
        
        if (list_store.get_n_items() > 0) {
            dropdown.selected = 0;
        }
    }
}

}
