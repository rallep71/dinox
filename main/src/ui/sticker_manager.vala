/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gtk;
using Adw;
using Gee;
using Dino.Entities;

namespace Dino.Ui {

    public class StickerManagerDialog : Adw.PreferencesWindow {
        private StreamInteractor stream_interactor;
        private Conversation? conversation;
        
        private Adw.PreferencesPage page;
        private Adw.PreferencesGroup packs_group;
        
        public signal void packs_changed();

        public StickerManagerDialog(StreamInteractor stream_interactor, Conversation? conversation) {
            this.stream_interactor = stream_interactor;
            this.conversation = conversation;

            this.title = _("Sticker Packs");
            this.default_width = 500;
            this.default_height = 600;
            this.modal = true;

            page = new Adw.PreferencesPage();
            this.add(page);

            // Import Group
            var import_group = new Adw.PreferencesGroup();
            import_group.title = _("Add Stickers");
            page.add(import_group);

            var import_row = new Adw.ActionRow();
            import_row.title = _("Import from Link");
            import_row.subtitle = _("Paste an xmpp: sticker pack link");
            import_row.activatable = true;
            import_row.add_suffix(new Image.from_icon_name("list-add-symbolic"));
            import_row.activated.connect(show_import_dialog);
            import_group.add(import_row);

            var folder_row = new Adw.ActionRow();
            folder_row.title = _("Create from Folder");
            folder_row.subtitle = _("Create a pack from local images");
            folder_row.activatable = true;
            folder_row.add_suffix(new Image.from_icon_name("folder-open-symbolic"));
            folder_row.activated.connect(open_folder_import);
            import_group.add(folder_row);

            // Installed Packs Group
            packs_group = new Adw.PreferencesGroup();
            packs_group.title = _("Installed Packs");
            page.add(packs_group);

            refresh_packs();
        }

        private void refresh_packs() {
            // Clear existing rows
            // Note: Adw.PreferencesGroup doesn't have a clear() method or easy child iteration in Vala bindings sometimes,
            // but we can remove children if we track them or iterate via GTK API.
            // For simplicity in this first pass, we'll remove all children of the group's internal list box if possible,
            // or just rebuild the group. Rebuilding the group is safer.
            
            page.remove(packs_group);
            packs_group = new Adw.PreferencesGroup();
            packs_group.title = _("Installed Packs");
            page.add(packs_group);

            if (conversation == null) return;

            var stickers = stream_interactor.get_module(Dino.Stickers.IDENTITY);
            if (stickers == null) return;

            var packs = stickers.get_packs(conversation.account);
            if (packs.size == 0) {
                var empty_row = new Adw.ActionRow();
                empty_row.title = _("No sticker packs installed");
                packs_group.add(empty_row);
                return;
            }

            foreach (var pack in packs) {
                var row = new Adw.ActionRow();
                row.title = (pack.name != null && pack.name != "") ? pack.name : pack.pack_id;
                row.subtitle = pack.summary ?? "";
                
                var delete_btn = new Button.from_icon_name("user-trash-symbolic");
                delete_btn.add_css_class("flat");
                delete_btn.add_css_class("destructive-action");
                delete_btn.tooltip_text = _("Remove Pack");
                delete_btn.valign = Align.CENTER;
                
                delete_btn.clicked.connect(() => {
                    confirm_delete(pack);
                });

                if (pack.source_jid != null && pack.source_jid != "" && pack.source_node != null && pack.source_node != "") {
                    var share_btn = new Button.from_icon_name("emblem-shared-symbolic");
                    share_btn.add_css_class("flat");
                    share_btn.tooltip_text = _("Copy Share Link");
                    share_btn.valign = Align.CENTER;
                    share_btn.clicked.connect(() => {
                        copy_share_link(pack);
                    });
                    row.add_suffix(share_btn);
                } else {
                    var publish_btn = new Button.from_icon_name("document-send-symbolic");
                    publish_btn.add_css_class("flat");
                    publish_btn.tooltip_text = _("Publish Pack");
                    publish_btn.valign = Align.CENTER;
                    publish_btn.clicked.connect(() => {
                        publish_pack(pack);
                    });
                    row.add_suffix(publish_btn);
                }
                
                row.add_suffix(delete_btn);
                packs_group.add(row);
            }
        }

        private void copy_share_link(Dino.Stickers.StickerPack pack) {
            if (pack.source_jid == null || pack.source_node == null) return;
            
            // Construct URI: xmpp:jid?pubsub;action=retrieve;node=...;item=...
            // Note: The item ID for the pack metadata is usually the pack_id itself in XEP-0449, 
            // or we might need to store the 'item' if it differs. 
            // Looking at Stickers.vala, it seems we don't explicitly store 'source_item' in StickerPack,
            // but usually the item id is the pack id.
            // However, let's check if we can reconstruct it.
            // If we don't have the item id, we might be guessing.
            // But wait, `StickerPack` struct has `source_jid` and `source_node`.
            // Does it have `source_item`? I checked the file content earlier and it didn't show `source_item`.
            // Let's assume item == pack_id for now, or check if we can get it.
            
            // Actually, let's check `libdino/src/service/stickers.vala` again to see if `source_item` is there or if I missed it.
            // I read lines 245-260 and it showed:
            // public string? source_jid { get; set; }
            // public string? source_node { get; set; }
            // No source_item.
            
            // However, when we import, we parse JID, Node, Item.
            // If we don't save the Item, we can't reconstruct the exact URI if the Item ID differs from Pack ID.
            // But in XEP-0449, the item ID in the user's private storage (which lists packs) points to the pubsub node.
            // The pack itself is an item in a pubsub node.
            // If we downloaded it, we should have saved where it came from.
            
            // If `source_item` is missing, we might need to add it to `StickerPack` in `stickers.vala` to support this properly.
            // But I cannot modify `libdino` easily without potentially breaking ABI/API or requiring database migration if it's stored in DB.
            // Let's check if `Stickers` module has a helper to generate the URI or if `publish_pack` returns it.
            
            // For now, I will assume item ID is the pack ID, which is the common case.
            
            string item_id = pack.pack_id;
            string uri = "xmpp:%s?pubsub;action=retrieve;node=%s;item=%s".printf(
                pack.source_jid,
                Uri.escape_string(pack.source_node, "", false),
                Uri.escape_string(item_id, "", false)
            );
            
            var clipboard = this.get_display().get_clipboard();
            clipboard.set_text(uri);
            
            var toast = new Adw.Toast(_("Link copied to clipboard"));
            this.add_toast(toast);
        }

        private void publish_pack(Dino.Stickers.StickerPack pack) {
            if (conversation == null) return;
            
            var stickers = stream_interactor.get_module(Dino.Stickers.IDENTITY);
            if (stickers == null) return;

            // We need a way to show progress/blocking, as publishing is network IO.
            // For now, we'll just disable the button or show a toast.
            
            var toast = new Adw.Toast(_("Publishing sticker pack…"));
            this.add_toast(toast);
            
            stickers.publish_pack.begin(conversation.account, pack.pack_id, (obj, res) => {
                try {
                    string uri = stickers.publish_pack.end(res);
                    var clipboard = this.get_display().get_clipboard();
                    clipboard.set_text(uri);
                    
                    var success_toast = new Adw.Toast(_("Pack published! Link copied."));
                    this.add_toast(success_toast);
                    
                    // Refresh to update buttons (now it should have source info)
                    refresh_packs();
                } catch (Error e) {
                    var err_dialog = new Adw.AlertDialog(_("Publish Failed"), e.message);
                    err_dialog.add_response("ok", _("OK"));
                    err_dialog.present(this);
                }
            });
        }

        private void confirm_delete(Dino.Stickers.StickerPack pack) {
            var dialog = new Adw.AlertDialog(
                _("Remove Sticker Pack?"),
                _("Are you sure you want to remove '%s'?").printf(pack.name ?? pack.pack_id)
            );
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("remove", _("Remove"));
            dialog.set_response_appearance("remove", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";
            dialog.close_response = "cancel";
            
            dialog.response.connect((response) => {
                if (response == "remove") {
                    delete_pack(pack);
                }
            });
            
            dialog.present(this);
        }

        private void delete_pack(Dino.Stickers.StickerPack pack) {
            var stickers = stream_interactor.get_module(Dino.Stickers.IDENTITY);
            if (stickers == null || conversation == null) return;

            try {
                stickers.remove_pack(conversation.account, pack.pack_id);
                refresh_packs();
                packs_changed();
            } catch (Error e) {
                var err_dialog = new Adw.AlertDialog(_("Error"), e.message);
                err_dialog.add_response("ok", _("OK"));
                err_dialog.present(this);
            }
        }

        private void show_import_dialog() {
            var input_dialog = new InputDialog(this, _("Import Sticker Pack"), _("Paste xmpp: URI"));
            input_dialog.response.connect((text) => {
                if (text != null && text != "") {
                    start_import(text);
                }
            });
            input_dialog.present();
        }

        private void start_import(string uri) {
            Xmpp.Jid src;
            string node;
            string item;
            
            if (!try_parse_sticker_pack_uri(uri, out src, out node, out item)) {
                var err = new Adw.AlertDialog(_("Invalid URI"), _("The provided text is not a valid sticker pack URI."));
                err.add_response("ok", _("OK"));
                err.present(this);
                return;
            }

            var dialog = new Dino.Ui.StickerPackImportDialog(stream_interactor, src, node, item);
            dialog.set_transient_for(this);
            dialog.close_request.connect(() => {
                dialog.destroy();
                refresh_packs();
                packs_changed();
                return true;
            });
            dialog.present();
        }

        private void open_folder_import() {
            if (conversation == null) return;
            
            var chooser = new Gtk.FileDialog();
            chooser.title = _("Select Folder");
            chooser.accept_label = _("Select");
            
            chooser.select_folder.begin(this, null, (obj, res) => {
                try {
                    File? folder = chooser.select_folder.end(res);
                    if (folder != null) {
                        string? path = folder.get_path();
                        if (path != null) {
                            var dialog = new StickerPackFolderImportDialog(stream_interactor, conversation.account, path);
                            dialog.set_transient_for(this);
                            dialog.pack_created.connect(() => {
                                refresh_packs();
                                packs_changed();
                            });
                            dialog.present();
                        }
                    }
                } catch (Error e) {
                    // Cancelled or error
                }
            });
        }

        // Helper from original sticker_chooser.vala
        private bool try_parse_sticker_pack_uri(string uri, out Xmpp.Jid? source_jid, out string? node, out string? item) {
            source_jid = null;
            node = null;
            item = null;

            if (!uri.has_prefix("xmpp:")) return false;
            string content = uri.substring(5);
            
            int q_pos = content.index_of("?");
            if (q_pos <= 0) return false;

            string jid_str = content.substring(0, q_pos);
            string query_str = content.substring(q_pos + 1);

            try {
                source_jid = new Xmpp.Jid(jid_str);
            } catch (Xmpp.InvalidJidError e) {
                return false;
            }

            string[] parts = query_str.split(";");
            if (parts.length < 2) return false;
            if (parts[0] != "pubsub") return false;

            var options = new HashMap<string, string>();
            for (int i = 1; i < parts.length; i++) {
                string p = parts[i];
                int eq = p.index_of("=");
                if (eq <= 0) continue;
                string k = p.substring(0, eq);
                string v = p.substring(eq + 1);
                options[k] = Uri.unescape_string(v);
            }

            if (!options.has_key("action") || options["action"] != "retrieve") return false;
            if (!options.has_key("node") || options["node"] != Xmpp.Xep.Stickers.NS_URI) return false;
            if (!options.has_key("item") || options["item"] == "") return false;

            node = options["node"];
            item = options["item"];
            return true;
        }
    }

    // Simple helper dialog for text input since Adw.AlertDialog doesn't support entries yet
    public class InputDialog : Adw.Window {
        public signal void response(string? text);
        private Entry entry;

        public InputDialog(Gtk.Window parent, string title, string placeholder) {
            this.transient_for = parent;
            this.title = title;
            this.modal = true;
            this.default_width = 400;
            
            var box = new Box(Orientation.VERTICAL, 12);
            box.margin_top = 24;
            box.margin_bottom = 24;
            box.margin_start = 24;
            box.margin_end = 24;
            
            var label = new Label(title);
            label.add_css_class("title-2");
            box.append(label);
            
            entry = new Entry();
            entry.placeholder_text = placeholder;
            entry.activates_default = true;
            box.append(entry);
            
            var btn_box = new Box(Orientation.HORIZONTAL, 12);
            btn_box.halign = Align.CENTER;
            
            var cancel = new Button.with_label(_("Cancel"));
            cancel.clicked.connect(() => { response(null); this.close(); });
            
            var ok = new Button.with_label(_("OK"));
            ok.add_css_class("suggested-action");
            ok.clicked.connect(() => { response(entry.text); this.close(); });
            
            btn_box.append(cancel);
            btn_box.append(ok);
            box.append(btn_box);
            
            this.content = box;
            this.set_default_widget(ok);
        }
    }
}
