using Gdk;
using Dino.Entities;
using Xmpp;
using Xmpp.Xep;
using Gee;
using Gtk;

[GtkTemplate (ui = "/im/github/rallep71/DinoX/preferences_window/preferences_dialog.ui")]
public class Dino.Ui.PreferencesDialog : Adw.PreferencesDialog {
    [GtkChild] public unowned Dino.Ui.PreferencesWindowAccounts accounts_page;
    [GtkChild] public unowned Dino.Ui.PreferencesWindowContacts contacts_page;
    [GtkChild] public unowned Dino.Ui.PreferencesWindowEncryption encryption_page;
    [GtkChild] public unowned Dino.Ui.GeneralPreferencesPage general_page;
    public Dino.Ui.AccountPreferencesSubpage account_page = new Dino.Ui.AccountPreferencesSubpage();

    [GtkChild] public unowned ViewModel.PreferencesDialog model { get; }

    public signal void backup_requested();
    public signal void restore_backup_requested();
    public signal void show_data_location();
    public signal void change_db_password_requested();
    public signal void clear_cache_requested();
    public signal void reset_database_requested();
    public signal void factory_reset_requested();

    construct {
        this.bind_property("model", accounts_page, "model", BindingFlags.SYNC_CREATE);
        this.bind_property("model", contacts_page, "model", BindingFlags.SYNC_CREATE);
        this.bind_property("model", account_page, "model", BindingFlags.SYNC_CREATE);
        this.bind_property("model", encryption_page, "model", BindingFlags.SYNC_CREATE);

        accounts_page.account_chosen.connect((account) => {
            model.selected_account = model.account_details[account];
            this.push_subpage(account_page);
        });
        
        general_page.backup_requested.connect(() => backup_requested());
        general_page.restore_backup_requested.connect(() => restore_backup_requested());
        general_page.show_data_location.connect(() => show_data_location());
        general_page.change_db_password_requested.connect(() => change_db_password_requested());
        general_page.clear_cache_requested.connect(() => clear_cache_requested());
        general_page.reset_database_requested.connect(() => reset_database_requested());
        general_page.factory_reset_requested.connect(() => factory_reset_requested());
    }
}
