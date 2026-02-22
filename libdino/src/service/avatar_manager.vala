/*
 * Copyright (C) 2025 Ralf Peter <dinox@handwerker.jetzt>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

using Gdk;
using Gee;
using Qlite;

using Xmpp;
using Dino.Entities;
using Dino.Security;

namespace Dino {

public class AvatarManager : StreamInteractionModule, Object {
    public static ModuleIdentity<AvatarManager> IDENTITY = new ModuleIdentity<AvatarManager>("avatar_manager");
    public string id { get { return IDENTITY.id; } }

    public signal void received_avatar(Jid jid, Account account);
    public signal void fetched_avatar(Jid jid, Account account);

    private enum Source {
        USER_AVATARS,
        VCARD
    }

    private StreamInteractor stream_interactor;
    private Database db;
    private FileEncryption file_encryption;
    private string folder = null;
    private HashMap<Jid, string> user_avatars = new HashMap<Jid, string>(Jid.hash_func, Jid.equals_func);
    private HashMap<Jid, string> vcard_avatars = new HashMap<Jid, string>(Jid.hash_func, Jid.equals_func);
    private HashSet<string> pending_fetch = new HashSet<string>();
    private HashMap<string, Bytes> avatar_bytes_cache = new HashMap<string, Bytes>();
    private const int MAX_AVATAR_CACHE_SIZE = 200;
    private const int MAX_PIXEL = 192;

    private static bool bytes_contains_ascii_ci(uint8[] data, int data_len, string needle) {
        if (needle == null || needle == "") return false;
        int nlen = needle.length;
        if (nlen <= 0) return false;
        if (data_len < nlen) return false;

        for (int i = 0; i <= data_len - nlen; i++) {
            bool match = true;
            for (int j = 0; j < nlen; j++) {
                uint8 b = data[i + j];
                char c = (char) b;
                char nc = needle[j];
                if (c >= 'A' && c <= 'Z') c = (char) (c - 'A' + 'a');
                if (nc >= 'A' && nc <= 'Z') nc = (char) (nc - 'A' + 'a');
                if (c != nc) {
                    match = false;
                    break;
                }
            }
            if (match) return true;
        }
        return false;
    }

    private static bool looks_like_svg_file(File file) {
        try {
            string? path = file.get_path();
            if (path != null) {
                string lower = path.down();
                if (lower.has_suffix(".svg") || lower.has_suffix(".svgz")) return true;
            }

            FileInputStream s = file.read(null);
            uint8[] buf = new uint8[8192];
            ssize_t n = s.read(buf, null);
            try { s.close(null); } catch (Error e) { }
            if (n <= 0) return false;

            int len = (int) n;
            if (len > (int) buf.length) len = (int) buf.length;

            if (len >= 2 && buf[0] == 0x1f && buf[1] == 0x8b) return true;
            if (bytes_contains_ascii_ci(buf, len, "<svg")) return true;
            if (bytes_contains_ascii_ci(buf, len, "<!doctype svg")) return true;
            if (bytes_contains_ascii_ci(buf, len, "http://www.w3.org/2000/svg")) return true;
        } catch (Error e) {
            // If we can't read it, don't assume SVG.
        }
        return false;
    }

    public static void start(StreamInteractor stream_interactor, Database db, FileEncryption file_encryption) {
        AvatarManager m = new AvatarManager(stream_interactor, db, file_encryption);
        stream_interactor.add_module(m);
    }

    private AvatarManager(StreamInteractor stream_interactor, Database db, FileEncryption file_encryption) {
        this.stream_interactor = stream_interactor;
        this.db = db;
        this.file_encryption = file_encryption;

        File old_avatars = File.new_build_filename(Dino.get_storage_dir(), "avatars");
        File new_avatars = File.new_build_filename(Dino.get_cache_dir(), "avatars");
        this.folder = new_avatars.get_path();

        // Move old avatar location to new one
        if (old_avatars.query_exists()) {
            if (!new_avatars.query_exists()) {
                // Move old avatars folder (~/.local/share/dino) to new location (~/.cache/dino)
                try {
                    new_avatars.get_parent().make_directory_with_parents();
                } catch (Error e) {
                    warning("AvatarManager: Failed to create parent directory for avatars: %s", e.message);
                }
                try {
                    old_avatars.move(new_avatars, FileCopyFlags.NONE);
                    debug("Avatars directory %s moved to %s", old_avatars.get_path(), new_avatars.get_path());
                } catch (Error e) {
                    warning("AvatarManager: Failed to move old avatars directory: %s", e.message);
                }
            } else {
                // If both old and new folders exist, remove the old one
                try {
                    FileEnumerator enumerator = old_avatars.enumerate_children("standard::*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                    FileInfo info = null;
                    while ((info = enumerator.next_file()) != null) {
                        FileUtils.remove(Path.build_filename(old_avatars.get_path(), info.get_name()));
                    }
                    DirUtils.remove(old_avatars.get_path());
                } catch (Error e) {
                    warning("AvatarManager: Failed to remove old avatars directory: %s", e.message);
                }
            }
        }

        // Create avatar folder
        try {
            new_avatars.make_directory_with_parents();
        } catch (IOError e) {
            // Directory might already exist; that's fine.
            if (e.code != IOError.EXISTS) {
                warning("AvatarManager: Failed to create avatars directory: %s", e.message);
            }
        } catch (Error e) {
            warning("AvatarManager: Failed to create avatars directory: %s", e.message);
        }

        // Pre-load ALL avatar hashes from DB into memory BEFORE connecting signals.
        // This ensures hashes are available when ConversationManager creates sidebar
        // rows during account_added (which fires before AvatarManager.on_account_added).
        foreach (Row row in db.avatar.select({db.avatar.jid_id, db.avatar.hash, db.avatar.type_})) {
            try {
                string hash = row[db.avatar.hash];
                if (hash == null || hash.strip() == "") continue;
                Jid jid = db.get_jid_by_id(row[db.avatar.jid_id]);
                if (jid == null) continue;
                int type = row[db.avatar.type_];
                if (type == Source.USER_AVATARS) {
                    user_avatars[jid] = hash;
                } else if (type == Source.VCARD && !user_avatars.has_key(jid)) {
                    vcard_avatars[jid] = hash;
                }
            } catch (InvalidJidError e) {
                // skip invalid JIDs
            }
        }

        stream_interactor.account_added.connect(on_account_added);
        stream_interactor.stream_negotiated.connect(on_stream_negotiated);
        stream_interactor.module_manager.initialize_account_modules.connect((_, modules) => {
            modules.add(new Xep.UserAvatars.Module());
            modules.add(new Xep.VCard.Module());
        });
    }

    public Bytes? get_avatar_bytes(Account account, Jid jid_) {
        string? hash = get_avatar_hash(account, jid_);
        if (hash == null) return null;

        // Check in-memory cache first (avoids file I/O + AES decrypt)
        if (avatar_bytes_cache.has_key(hash)) {
            return avatar_bytes_cache[hash];
        }

        File file = File.new_for_path(Path.build_filename(folder, hash));
        if (!file.query_exists()) {
            fetch_and_store_for_jid.begin(account, jid_);
            return null;
        } else {
            try {
                uint8[] data;
                if (!FileUtils.get_data(file.get_path(), out data)) return null;
                uint8[] plaintext = file_encryption.decrypt_data(data);
                Bytes result = new Bytes(plaintext);

                // Cache the decrypted bytes (evict oldest if full)
                if (avatar_bytes_cache.size >= MAX_AVATAR_CACHE_SIZE) {
                    var iter = avatar_bytes_cache.map_iterator();
                    if (iter.next()) {
                        iter.unset();
                    }
                }
                avatar_bytes_cache[hash] = result;

                return result;
            } catch (Error e) {
                warning("Failed to decrypt avatar: %s", e.message);
                try {
                    file.delete();
                    debug("Deleted corrupt avatar file: %s", file.get_path());
                    fetch_and_store_for_jid.begin(account, jid_);
                } catch (Error e2) {
                    warning("Failed to delete corrupted avatar: %s", e2.message);
                }
                return null;
            }
        }
    }

    private string? get_avatar_hash(Account account, Jid jid_) {
        Jid jid = jid_;
        if (!stream_interactor.get_module<MucManager>(MucManager.IDENTITY).is_groupchat_occupant(jid_, account)) {
            jid = jid_.bare_jid;
        }
        if (user_avatars.has_key(jid)) {
            return user_avatars[jid];
        } else if (vcard_avatars.has_key(jid)) {
            return vcard_avatars[jid];
        } else {
            return null;
        }
    }

    public bool has_avatar(Account account, Jid jid) {
        return get_avatar_hash(account, jid) != null;
    }

    /**
     * Clears in-memory avatar caches. Must be called after DB purge_caches()
     * to ensure consistency between DB and memory state.
     */
    public void purge_in_memory_caches() {
        user_avatars.clear();
        vcard_avatars.clear();
        pending_fetch.clear();
        avatar_bytes_cache.clear();
    }

    public async void publish(Account account, File file) {
        debug("Publish avatar from %s", file.get_uri());
        FileInputStream file_stream = null;
        try {
            if (looks_like_svg_file(file)) {
                warning("AvatarManager: Refusing to publish SVG/SVGZ avatar (avoids Flatpak SVG loader crash).");
                return;
            }
            file_stream = file.read();
            Pixbuf pixbuf = new Pixbuf.from_stream(file_stream);
            if (pixbuf.width >= pixbuf.height && pixbuf.width > MAX_PIXEL) {
                int dest_height = (int) ((float) MAX_PIXEL / pixbuf.width * pixbuf.height);
                pixbuf = pixbuf.scale_simple(MAX_PIXEL, dest_height, InterpType.BILINEAR);
            } else if (pixbuf.height > pixbuf.width && pixbuf.width > MAX_PIXEL) {
                int dest_width = (int) ((float) MAX_PIXEL / pixbuf.height * pixbuf.width);
                pixbuf = pixbuf.scale_simple(dest_width, MAX_PIXEL, InterpType.BILINEAR);
            }
            uint8[] buffer;
            pixbuf.save_to_buffer(out buffer, "png");
            XmppStream stream = stream_interactor.get_stream(account);
            if (stream != null) {
                // 1. Publish via PEP (XEP-0084)
                Xmpp.Xep.UserAvatars.publish_png(stream, buffer, pixbuf.width, pixbuf.height);
                debug("Publishing %u png bytes via user-avatars.", buffer.length);
                
                // 2. Publish via vCard-temp (XEP-0054) for compatibility (Conversations etc.)
                try {
                    var vcard = yield Xmpp.Xep.VCard.fetch_vcard(stream);
                    if (vcard == null) vcard = new Xmpp.Xep.VCard.VCardInfo();
                    
                    vcard.photo = new Bytes(buffer);
                    vcard.photo_type = "image/png";
                    
                    yield Xmpp.Xep.VCard.publish_vcard(stream, vcard);
                    debug("Published avatar to vCard-temp (XEP-0054).");
                    
                    // Update local cache immediately
                    string sha1 = Checksum.compute_for_data(ChecksumType.SHA1, buffer);
                    set_avatar_hash(account, account.bare_jid, sha1, Source.VCARD);
                } catch (Error e) {
                    warning("Failed to publish vCard-temp avatar: %s", e.message);
                }
            } else {
                warning("No stream when trying to publish.");
            }
        } catch (Error e) {
            warning(e.message);
        } finally {
            try {
                if (file_stream != null) file_stream.close();
            } catch (Error e) {
                // Ignore
            }
        }
    }

    public void unset_avatar(Account account) {
        XmppStream stream = stream_interactor.get_stream(account);
        if (stream == null) return;
        Xmpp.Xep.UserAvatars.unset_avatar(stream);
        unset_vcard_avatar.begin(stream, account);
    }

    private async void unset_vcard_avatar(XmppStream stream, Account account) {
        try {
            Iq.Stanza iq = new Iq.Stanza.get(new StanzaNode.build("vCard", "vcard-temp").add_self_xmlns());
            Iq.Stanza iq_res = yield stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq_async(stream, iq);

            if (iq_res.is_error()) return;

            StanzaNode? vcard = iq_res.stanza.get_subnode("vCard", "vcard-temp");
            if (vcard == null) return;

            // Create a new vCard node to ensure clean state
            StanzaNode new_vcard = new StanzaNode.build("vCard", "vcard-temp");
            new_vcard.add_self_xmlns();

            // Copy all children except PHOTO
            foreach (var child in vcard.sub_nodes) {
                if (child.name != "PHOTO") {
                    new_vcard.put_node(child);
                }
            }

            // Do NOT add any PHOTO element. This removes it entirely.

            Iq.Stanza iq_set = new Iq.Stanza.set(new_vcard);
            Iq.Stanza iq_set_res = yield stream.get_module<Iq.Module>(Iq.Module.IDENTITY).send_iq_async(stream, iq_set);
            
            if (iq_set_res.is_error()) return;

            // Manually update local cache and notify UI
            Jid jid = account.bare_jid;
            
            // Delete the old avatar file from disk if it exists
            string? old_hash = null;
            
            // Check both vcard_avatars and user_avatars
            if (vcard_avatars.has_key(jid)) {
                old_hash = vcard_avatars[jid];
                vcard_avatars.unset(jid);
            }
            
            if (user_avatars.has_key(jid)) {
                string? user_hash = user_avatars[jid];
                if (old_hash == null) old_hash = user_hash;
                user_avatars.unset(jid);
            }
            
            if (old_hash != null) {
                File old_file = File.new_for_path(Path.build_filename(folder, old_hash));
                if (old_file.query_exists()) {
                    try {
                        old_file.delete();
                    } catch (Error e) {
                        warning("Failed to delete old avatar file: %s", e.message);
                    }
                }
            }
            
            // Remove from database for both sources
            remove_avatar_hash(account, jid, Source.VCARD);
            remove_avatar_hash(account, jid, Source.USER_AVATARS);
            
            received_avatar(jid, account);

        } catch (Error e) {
            warning("Failed to unset vCard avatar: %s", e.message);
        }
    }

    private void on_account_added(Account account) {
        stream_interactor.module_manager.get_module<Xep.UserAvatars.Module>(account, Xep.UserAvatars.Module.IDENTITY).received_avatar_hash.connect((stream, jid, id) =>
            on_user_avatar_received(account, jid, id)
        );
        stream_interactor.module_manager.get_module<Xep.UserAvatars.Module>(account, Xep.UserAvatars.Module.IDENTITY).avatar_removed.connect((stream, jid) => {
            on_user_avatar_removed(account, jid);
        });
        stream_interactor.module_manager.get_module<Xep.VCard.Module>(account, Xep.VCard.Module.IDENTITY).received_avatar_hash.connect((stream, jid, id) =>
            on_vcard_avatar_received(account, jid, id)
        );

        foreach (var entry in get_avatar_hashes(account, Source.USER_AVATARS).entries) {
            on_user_avatar_received(account, entry.key, entry.value);
        }
        foreach (var entry in get_avatar_hashes(account, Source.VCARD).entries) {
            on_vcard_avatar_received(account, entry.key, entry.value);
        }
    }

    /**
     * On reconnect, re-fetch any avatars where we have a hash but the image file is missing.
     * This handles the case after clear_cache or corrupted files.
     */
    private void on_stream_negotiated(Account account, XmppStream stream) {
        // Collect JIDs with known hashes but missing avatar files
        var missing = new Gee.ArrayList<Jid>();
        foreach (var entry in user_avatars.entries) {
            if (!has_image(entry.value)) {
                missing.add(entry.key);
            }
        }
        foreach (var entry in vcard_avatars.entries) {
            if (!user_avatars.has_key(entry.key) && !has_image(entry.value)) {
                missing.add(entry.key);
            }
        }
        if (missing.size > 0) {
            debug("AvatarManager: %d avatars need re-fetch after reconnect for %s", missing.size, account.bare_jid.to_string());
            refetch_missing_avatars.begin(account, missing);
        }
    }

    private async void refetch_missing_avatars(Account account, Gee.ArrayList<Jid> jids) {
        foreach (Jid jid in jids) {
            yield fetch_and_store_for_jid(account, jid);
        }
    }

    private void on_user_avatar_received(Account account, Jid jid_, string id) {
        if (id == null || id.strip() == "") return;
        Jid jid = jid_.bare_jid;

        if (!user_avatars.has_key(jid) || user_avatars[jid] != id) {
            user_avatars[jid] = id;
            set_avatar_hash(account, jid, id, Source.USER_AVATARS);
        }
        received_avatar(jid, account);
    }

    private void on_user_avatar_removed(Account account, Jid jid_) {
        Jid jid = jid_.bare_jid;
        user_avatars.unset(jid);
        remove_avatar_hash(account, jid, Source.USER_AVATARS);
        received_avatar(jid, account);
    }

    public void on_vcard_avatar_received(Account account, Jid jid_, string id) {
        if (id == null || id.strip() == "") return;
        bool is_gc = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).might_be_groupchat(jid_.bare_jid, account);
        Jid jid = is_gc ? jid_ : jid_.bare_jid;

        if (!vcard_avatars.has_key(jid) || vcard_avatars[jid] != id) {
            vcard_avatars[jid] = id;
            if (jid.is_bare()) { // don't save MUC occupant avatars
                set_avatar_hash(account, jid, id, Source.VCARD);
            }
        }
        received_avatar(jid, account);
    }

    public void set_avatar_hash(Account account, Jid jid, string hash, int type) {
        db.avatar.insert()
            .value(db.avatar.jid_id, db.get_jid_id(jid))
            .value(db.avatar.account_id, account.id)
            .value(db.avatar.hash, hash)
            .value(db.avatar.type_, type)
            .perform();
    }

    public void remove_avatar_hash(Account account, Jid jid, int type) {
        db.avatar.delete()
            .with(db.avatar.jid_id, "=", db.get_jid_id(jid))
            .with(db.avatar.account_id, "=", account.id)
            .with(db.avatar.type_, "=", type)
            .perform();
    }

    public HashMap<Jid, string> get_avatar_hashes(Account account, int type) {
        HashMap<Jid, string> ret = new HashMap<Jid, string>(Jid.hash_func, Jid.equals_func);
        foreach (Row row in db.avatar.select({db.avatar.jid_id, db.avatar.hash})
                .with(db.avatar.type_, "=", type)
                .with(db.avatar.account_id, "=", account.id)) {
            try {
                ret[db.get_jid_by_id(row[db.avatar.jid_id])] = row[db.avatar.hash];
            } catch (Xmpp.InvalidJidError e) {
                warning("Invalid JID in avatar DB: %s", e.message);
            }
        }
        return ret;
    }

    public async bool fetch_and_store_for_jid(Account account, Jid jid) {
        int source = -1;
        string? hash = null;
        if (user_avatars.has_key(jid)) {
            hash = user_avatars[jid];
            source = 1;
        } else if (vcard_avatars.has_key(jid)) {
            hash = vcard_avatars[jid];
            source = 2;
        } else {
            return false;
        }

        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream == null || !stream.negotiation_complete) return false;

        return yield fetch_and_store(stream, account, jid, source, hash);
    }

    private async bool fetch_and_store(XmppStream stream, Account account, Jid jid, int source, string? hash) {
        if (hash == null || pending_fetch.contains(hash)) return false;

        pending_fetch.add(hash);
        Bytes? bytes = null;
        if (source == 1) {
            bytes = yield Xmpp.Xep.UserAvatars.fetch_image(stream, jid, hash);
        } else if (source == 2) {
            bytes = yield Xmpp.Xep.VCard.fetch_image(stream, jid, hash);
            if (bytes == null && jid.is_bare()) {
                db.avatar.delete().with(db.avatar.jid_id, "=", db.get_jid_id(jid)).perform();
            }
        }

        if (bytes != null) {
            yield store_image(hash, bytes);
            fetched_avatar(jid, account);
        }
        pending_fetch.remove(hash);
        return bytes != null;
    }

    public async void store_image(string id, Bytes data) {
        File file = File.new_for_path(Path.build_filename(folder, id));
        try {
            if (file.query_exists()) file.delete();

            uint8[] plaintext = data.get_data();
            uint8[] ciphertext = file_encryption.encrypt_data(plaintext);

            DataOutputStream fos = new DataOutputStream(file.create(FileCreateFlags.REPLACE_DESTINATION));
            yield fos.write_async(ciphertext);
            yield fos.close_async();
        } catch (Error e) {
            warning("Error writing avatar file: %s", e.message);
            // Ignore: we failed in storing, so we refuse to display later...
        }
    }

    public bool has_image(string id) {
        File file = File.new_for_path(Path.build_filename(folder, id));
        return file.query_exists();
    }
}

}
