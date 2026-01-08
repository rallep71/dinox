using Gtk;
using Adw;
using Dino.Entities;
using Xmpp;
using Gee;

namespace Dino.Ui {

public class UserSearchDialog : Adw.Dialog {
    private StreamInteractor stream_interactor;
    private Account account;
    private UserSearch user_search;
    private Jid? search_component_jid;

    private Box content_box;
    private Box form_box;
    private ListBox results_list;
    private Button search_button;
    private Gtk.Spinner spinner;
    private Entry search_entry; // Simple fallback if no form
    private string? initial_query = null;
    private bool use_legacy_search = false;

    public signal void contact_selected(Jid jid);

    public UserSearchDialog(StreamInteractor stream_interactor, Account account, string? initial_query = null) {
        this.stream_interactor = stream_interactor;
        this.account = account;
        this.user_search = new UserSearch(stream_interactor);
        this.initial_query = initial_query;
        
        this.title = _("Search User Directory");
        this.content_width = 500;
        this.content_height = 600;

        setup_ui();
        init_search.begin();
    }

    private void setup_ui() {
        var toolbar_view = new Adw.ToolbarView();
        var header_bar = new Adw.HeaderBar();
        toolbar_view.add_top_bar(header_bar);

        var cancel_button = new Button.with_label(_("Close"));
        cancel_button.clicked.connect(() => close());
        header_bar.pack_start(cancel_button);

        content_box = new Box(Orientation.VERTICAL, 12);
        content_box.margin_top = 12;
        content_box.margin_bottom = 12;
        content_box.margin_start = 12;
        content_box.margin_end = 12;

        form_box = new Box(Orientation.VERTICAL, 6);
        content_box.append(form_box);

        search_button = new Button.with_label(_("Search"));
        search_button.add_css_class("suggested-action");
        search_button.clicked.connect(on_search_clicked);
        search_button.sensitive = false;
        content_box.append(search_button);

        spinner = new Spinner();
        content_box.append(spinner);

        var scrolled = new ScrolledWindow();
        scrolled.vexpand = true;
        results_list = new ListBox();
        results_list.selection_mode = SelectionMode.NONE;
        results_list.add_css_class("boxed-list");
        scrolled.child = results_list;
        content_box.append(scrolled);

        toolbar_view.content = content_box;
        this.child = toolbar_view;
    }

    private async void init_search() {
        spinner.start();
        
        // Add timeout for search component discovery
        var timeout_source = new TimeoutSource(5000); // 5 seconds timeout
        timeout_source.set_callback(() => {
            if (search_component_jid == null) {
                spinner.stop();
                var label = new Label(_("Search directory discovery timed out."));
                form_box.append(label);
            }
            return false;
        });
        timeout_source.attach(null);

        search_component_jid = yield user_search.find_search_component(account);
        
        if (search_component_jid == null) {
            spinner.stop();
            // Label already added by timeout or we add it here if it finished but failed
            if (form_box.get_first_child() == null) {
                var label = new Label(_("No search directory found on this server."));
                form_box.append(label);
            }
            return;
        }

        // Get fields
        spinner.start();
        // Add timeout for getting fields
        var fields_timeout = new TimeoutSource(5000);
        bool fields_timed_out = false;
        fields_timeout.set_callback(() => {
            fields_timed_out = true;
            use_legacy_search = true;
            spinner.stop();
            if (form_box.get_first_child() == null) {
                var label = new Label(_("Retrieving search form timed out. Using fallback."));
                form_box.append(label);
                
                // Fallback UI on timeout
                search_entry = new Entry();
                search_entry.placeholder_text = _("Search term...");
                form_box.append(search_entry);
                search_entry.activate.connect(on_search_clicked);
                search_button.sensitive = true;
            }
            return false;
        });
        fields_timeout.attach(null);

        var form = yield user_search.get_search_fields(account, search_component_jid);
        spinner.stop();
        fields_timeout.destroy();

        if (fields_timed_out) return;

        if (form != null) {
            build_form_ui(form);
        } else {
            // Fallback UI
            if (search_entry == null) { // Only if not already added by timeout
                search_entry = new Entry();
                search_entry.placeholder_text = _("Search term...");
                form_box.append(search_entry);
                search_entry.activate.connect(on_search_clicked);
            }
        }
        search_button.sensitive = true;
    }

    private HashMap<string, Entry> form_entries = new HashMap<string, Entry>();

    private void build_form_ui(Xmpp.Xep.DataForms.DataForm form) {
        foreach (var field in form.fields) {
            if (field.type_ == Xmpp.Xep.DataForms.DataForm.Type.HIDDEN) continue;
            
            var row = new Adw.ActionRow();
            row.title = field.label ?? field.var;
            
            var entry = new Entry();
            entry.hexpand = true;
            entry.valign = Align.CENTER;
            row.add_suffix(entry);
            
            form_box.append(row);
            form_entries[field.var] = entry;
            
            // Pre-fill if we have an initial query and this looks like a search field
            if (initial_query != null && (field.var == "search" || field.var == "first" || field.var == "last" || field.var == "nick" || field.var == "email")) {
                entry.text = initial_query;
            }
            
            entry.activate.connect(on_search_clicked);
        }
        
        // Auto-search if we have a query
        if (initial_query != null) {
            do_search.begin();
            initial_query = null; // Only once
        }
    }

    private void on_search_clicked() {
        do_search.begin();
    }

    private async void do_search() {
        search_button.sensitive = false;
        spinner.start();
        
        // Clear previous results
        var child = results_list.get_first_child();
        while (child != null) {
            results_list.remove(child);
            child = results_list.get_first_child();
        }

        Xmpp.Xep.DataForms.DataForm form = new Xmpp.Xep.DataForms.DataForm("submit");
        
        bool has_fields = false;
        foreach (var entry in form_entries.entries) {
            if (entry.value.text != "") {
                var field = new Xmpp.Xep.DataForms.DataForm.Field();
                field.var = entry.key;
                field.set_value_string(entry.value.text);
                form.add_field(field);
                has_fields = true;
            }
        }

        if (!has_fields && search_entry != null && search_entry.text != "") {
            // Fallback: we assume 'nick' is a supported field
            var field = new Xmpp.Xep.DataForms.DataForm.Field();
            field.var = "nick";
            field.set_value_string(search_entry.text);
            form.add_field(field);
        }

        // Add timeout for search execution
        bool timed_out = false;
        var timeout = new TimeoutSource(5000); // 5 seconds timeout for the first attempt
        timeout.set_callback(() => {
            timed_out = true;
            print("DEBUG: Primary search timed out, triggering fallback immediately.\n");
            do_fallback_search.begin(form);
            return false;
        });
        timeout.attach(null);

        var results = yield user_search.perform_search(account, search_component_jid, form, use_legacy_search);
        
        if (timed_out) {
            // If timeout already fired, we ignore this result (or we could merge it, but let's keep it simple)
            print("DEBUG: Primary search returned after timeout, ignoring.\n");
            return;
        }
        timeout.destroy();

        // If results are null (error) or empty, and we haven't tried the main server yet
        if ((results == null || results.size == 0) && search_component_jid.to_string() != account.domainpart) {
             print("DEBUG: Search on component failed or empty, trying server directly: %s\n", account.domainpart);
             yield do_fallback_search(form);
             return;
        }

        show_results(results);
    }
    private async void do_fallback_search(Xmpp.Xep.DataForms.DataForm form) {
         // Try searching the server directly as a fallback
         Jid server_jid;
         try {
             server_jid = new Jid(account.domainpart);
         } catch (Xmpp.InvalidJidError e) {
             warning("Invalid domain JID: %s", e.message);
             return;
         }
         
         bool timed_out = false;
         var fallback_timeout = new TimeoutSource(25000); // Increased to 25s
         fallback_timeout.set_callback(() => {
            timed_out = true;
            print("DEBUG: Fallback search timed out.\n");
            spinner.stop();
            search_button.sensitive = true;
            var label = new Label(_("Fallback search request timed out."));
            results_list.append(label);
            return false;
         });
         fallback_timeout.attach(null);
         
         // For fallback to main server, we use legacy search (true) to be safe and compatible
         var results = yield user_search.perform_search(account, server_jid, form, true);
         
         if (timed_out) {
             print("DEBUG: Fallback search returned after timeout, ignoring.\n");
             return;
         }
         fallback_timeout.destroy();
         
         show_results(results);
    }

    private void show_results(Gee.List<Xmpp.Xep.Search.Item>? results) {
        spinner.stop();
        search_button.sensitive = true;

        // Clear previous results (in case we are running fallback after a partial failure)
        var child = results_list.get_first_child();
        while (child != null) {
            results_list.remove(child);
            child = results_list.get_first_child();
        }

        if (results != null) {
            foreach (var item in results) {
                var row = new Adw.ActionRow();
                row.title = item.jid.to_string();
                
                string details = "";
                foreach (var field in item.fields.entries) {
                    if (field.key != "jid") {
                        details += "%s: %s, ".printf(field.key, field.value);
                    }
                }
                if (details.length > 2) details = details.substring(0, details.length - 2);
                row.subtitle = details;

                var add_btn = new Button.from_icon_name("list-add-symbolic");
                add_btn.valign = Align.CENTER;
                add_btn.add_css_class("flat");
                add_btn.clicked.connect(() => {
                    contact_selected(item.jid);
                    close();
                });
                row.add_suffix(add_btn);

                results_list.append(row);
            }
            if (results.size == 0) {
                var label = new Label(_("No results found."));
                results_list.append(label);
            }
        } else {
             var label = new Label(_("Search failed."));
             results_list.append(label);
        }
    }
}

}
