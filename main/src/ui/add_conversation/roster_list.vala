using Gee;
using Gtk;

using Dino.Entities;
using Xmpp;

namespace Dino.Ui {

protected class RosterList {

    public signal void conversation_selected(Conversation? conversation);
    private StreamInteractor stream_interactor;
    private Gee.List<Account> accounts;
    private ulong[] handler_ids = new ulong[0];

    private ListBox list_box = new ListBox();
    private HashMap<Account, HashMap<Jid, ListBoxRow>> rows = new HashMap<Account, HashMap<Jid, ListBoxRow>>(Account.hash_func, Account.equals_func);

    private Gee.List<Roster.Item> pending_items = new Gee.ArrayList<Roster.Item>();
    private Account? pending_account;
    private int pending_account_index = 0;
    private const int BATCH_SIZE = 2;

    public RosterList(StreamInteractor stream_interactor, Gee.List<Account> accounts) {
        this.stream_interactor = stream_interactor;
        this.accounts = accounts;

        handler_ids += stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).removed_roster_item.connect( (account, jid) => {
            if (accounts.contains(account)) {
                remove_row(account, jid);
            }
        });
        handler_ids += stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).updated_roster_item.connect( (account, jid) => {
            if (accounts.contains(account)) {
                update_row(account, jid);
            }
        });
        list_box.destroy.connect(() => {
            foreach (ulong handler_id in handler_ids) stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).disconnect(handler_id);
        });

        // Initialize row maps for all accounts
        foreach (Account a in accounts) {
            rows[a] = new HashMap<Jid, ListBoxRow>(Jid.hash_func, Jid.equals_func);
        }

        // Defer roster population — 150ms delay lets dialog animation complete first
        Timeout.add(150, () => {
            start_deferred_load();
            return false;
        });
    }

    private void start_deferred_load() {
        pending_account_index = 0;
        load_next_account();
    }

    private void load_next_account() {
        if (pending_account_index >= accounts.size) {
            // All accounts loaded — final sort/filter once
            list_box.invalidate_sort();
            list_box.invalidate_filter();
            return;
        }

        pending_account = accounts[pending_account_index];
        var roster = stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).get_roster(pending_account);
        pending_items.clear();
        pending_items.add_all(roster);

        if (pending_items.size == 0) {
            pending_account_index++;
            load_next_account();
            return;
        }

        load_batch(0);
    }

    private void load_batch(int offset) {
        if (pending_account == null) return;

        int end = int.min(offset + BATCH_SIZE, pending_items.size);
        bool show_account = accounts.size > 1;

        for (int i = offset; i < end; i++) {
            Roster.Item item = pending_items[i];
            ListRow row = new ListRow.from_jid(stream_interactor, item.jid, pending_account, show_account);
            ListBoxRow list_box_row = new ListBoxRow() { child=row };
            rows[pending_account][item.jid] = list_box_row;
            list_box.append(list_box_row);
        }

        if (end < pending_items.size) {
            // More items in this account — 10ms pause gives GTK time to repaint
            Timeout.add(10, () => {
                load_batch(end);
                return false;
            });
        } else {
            // This account done — move to next
            pending_account_index++;
            if (pending_account_index < accounts.size) {
                Timeout.add(10, () => {
                    load_next_account();
                    return false;
                });
            } else {
                // All done — final sort/filter
                list_box.invalidate_sort();
                list_box.invalidate_filter();
            }
        }
    }

    private void remove_row(Account account, Jid jid) {
        if (rows.has_key(account) && rows[account].has_key(jid)) {
            list_box.remove(rows[account][jid]);
            rows[account].unset(jid);
        }
    }

    private void update_row(Account account, Jid jid) {
        remove_row(account, jid);
        ListRow row = new ListRow.from_jid(stream_interactor, jid, account, accounts.size > 1);
        ListBoxRow list_box_row = new ListBoxRow() { child=row };
        rows[account][jid] = list_box_row;
        list_box.append(list_box_row);
        list_box.invalidate_sort();
        list_box.invalidate_filter();
    }

    public ListBox get_list_box() {
        return list_box;
    }
}

}
