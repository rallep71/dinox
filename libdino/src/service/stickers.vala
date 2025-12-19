using Gee;
using Gdk;
using Soup;

using Dino.Entities;
using Xmpp;
using Xmpp.Xep;

namespace Dino {

public errordomain StickerError {
    INVALID_URI,
    NOT_CONNECTED,
    NOT_FOUND,
    RESTRICTED,
    DOWNLOAD_FAILED,
    PUBLISH_FAILED,
}

public class Stickers : StreamInteractionModule, Object {
    public static ModuleIdentity<Stickers> IDENTITY = new ModuleIdentity<Stickers>("stickers");
    public string id { get { return IDENTITY.id; } }

    private StreamInteractor stream_interactor;
    private Database db;
    private Soup.Session http;
    private GLib.MainContext http_context;

    private const string STICKERS_NODE = Xmpp.Xep.Stickers.NS_URI;
    private const int THUMB_SIZE = 48;

    private static bool bytes_contains_ascii_ci(uint8[] data, string needle) {
        if (needle == null || needle == "") return false;
        int nlen = needle.length;
        if (nlen <= 0) return false;
        if (data.length < (size_t) nlen) return false;

        for (int i = 0; i <= (int) data.length - nlen; i++) {
            bool match = true;
            for (int j = 0; j < nlen; j++) {
                uint8 b = data[i + j];
                char c = (char) b;
                char nc = needle[j];
                // ASCII case-insensitive compare.
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

    private static bool looks_like_svg_file(string path) {
        if (path == null || path == "") return false;

        string lower_path = path.down();
        if (lower_path.has_suffix(".svg") || lower_path.has_suffix(".svgz")) {
            return true;
        }

        try {
            File f = File.new_for_path(path);
            FileInputStream s = f.read();
            // Read only a small prefix; enough for XML/SVG headers.
            uint8[] buf = new uint8[8192];
            ssize_t n = s.read(buf, null);
            try { s.close(); } catch (Error e) { }
            if (n <= 0) return false;

            // Slice to actual read length.
            uint8[] head = buf[0:(int) n];

            // SVGZ is gzip-compressed; if a pack mislabeled SVGZ as a raster type we must avoid decoding.
            if (head.length >= 2 && head[0] == 0x1f && head[1] == 0x8b) {
                return true;
            }

            // Common SVG signatures.
            if (bytes_contains_ascii_ci(head, "<svg")) return true;
            if (bytes_contains_ascii_ci(head, "<!doctype svg")) return true;
            if (bytes_contains_ascii_ci(head, "http://www.w3.org/2000/svg")) return true;
        } catch (Error e) {
            // If we can't read it, don't assume SVG.
        }

        return false;
    }

    public static void start(StreamInteractor stream_interactor, Database db) {
        var m = new Stickers(stream_interactor, db);
        stream_interactor.add_module(m);
    }

    private Stickers(StreamInteractor stream_interactor, Database db) {
        this.stream_interactor = stream_interactor;
        this.db = db;

        // libsoup binds to the thread-default main context at creation time.
        // Make sure we always use it from that same context.
        this.http_context = GLib.MainContext.ref_thread_default();
        this.http = new Soup.Session();
        this.http.user_agent = @"Dino/$(Dino.get_short_version()) ";

        DirUtils.create_with_parents(get_stickers_dir(), 0700);
    }

    private async void ensure_http_context() {
        // `get_thread_default()` may be null even while running on the default main
        // context. `invoke()` executes callbacks immediately if the context is already
        // owned by the current thread; using `is_owner()` avoids re-entrant recursion.
        if (http_context.is_owner()) return;
        http_context.invoke(() => {
            ensure_http_context.callback();
            return false;
        });
        yield;
    }

    public static string get_stickers_dir() {
        return Path.build_filename(Dino.get_storage_dir(), "stickers");
    }

    private static string get_pack_dir(string pack_id) {
        return Path.build_filename(get_stickers_dir(), pack_id);
    }

    private static string get_pack_thumbs_dir(string pack_id) {
        return Path.build_filename(get_pack_dir(pack_id), "thumbs");
    }

    private class ThumbJob : Object {
        public string source_path;
        public string thumb_path;

        public ThumbJob(string source_path, string thumb_path) {
            this.source_path = source_path;
            this.thumb_path = thumb_path;
        }
    }

    private static AsyncQueue<ThumbJob>? thumb_queue;
    private static bool thumb_worker_started = false;

    private static void ensure_thumb_worker() {
        if (thumb_worker_started) return;
        thumb_worker_started = true;
        thumb_queue = new AsyncQueue<ThumbJob>();

        new Thread<void*>("stickers-thumbgen", () => {
            while (true) {
                ThumbJob job = thumb_queue.pop();

                // Best-effort: if something else created it already, skip.
                if (FileUtils.test(job.thumb_path, FileTest.EXISTS)) continue;

                DirUtils.create_with_parents(Path.get_dirname(job.thumb_path), 0700);

                try {
                    var pixbuf = new Pixbuf.from_file_at_scale(job.source_path, THUMB_SIZE, THUMB_SIZE, true);
                    pixbuf = pixbuf.apply_embedded_orientation();
                    pixbuf.save(job.thumb_path, "png");
                } catch (Error e) {
                    // best-effort
                }
            }
            // unreachable
            // return null;
        });
    }

    public static string? get_thumbnail_path_for_item(StickerItem item) {
        if (item.pack_id == null || item.pack_id == "") return null;
        if (item.local_path == null || item.local_path == "") return null;

        string base_name;
        if (item.hash_value != null && item.hash_value != "") {
            base_name = filename_safe_base64(item.hash_value);
        } else {
            // Fallback for older/incomplete items.
            base_name = Checksum.compute_for_string(ChecksumType.SHA1, item.local_path);
        }

        return Path.build_filename(get_pack_thumbs_dir(item.pack_id), base_name + ".png");
    }

    private static void maybe_generate_thumbnail(string pack_id, StickerItem item) {
        if (item.local_path == null || item.local_path == "") return;

        // Thumbnail generation is best-effort. Some loaders (notably SVG via librsvg)
        // have caused crashes in the Flatpak runtime when importing sticker packs.
        // Skip thumbnailing for non-raster/unknown types; the UI can still generate
        // thumbnails lazily when needed.
        if (item.media_type != null && item.media_type != "") {
            switch (item.media_type) {
                case "image/png":
                case "image/jpeg":
                case "image/jpg":
                case "image/webp":
                case "image/gif":
                    break;
                default:
                    return;
            }
        } else {
            return;
        }

        // Do not trust the declared mime-type fully: some packs contain SVG data mislabeled as
        // image/png or similar. Loading SVG via gdk-pixbuf/librsvg has been observed to crash in
        // Flatpak runtimes.
        if (looks_like_svg_file(item.local_path)) {
            return;
        }

        string? thumb_path = get_thumbnail_path_for_item(item);
        if (thumb_path == null || thumb_path == "") return;
        if (FileUtils.test(thumb_path, FileTest.EXISTS)) return;

        // Generating thumbnails can be expensive (decode/scale). Do it off the
        // main thread to avoid UI stalls; the UI can still lazy-generate on demand.
        ensure_thumb_worker();
        if (thumb_queue != null) {
            thumb_queue.push(new ThumbJob(item.local_path, thumb_path));
        }
    }

    private static string filename_safe_base64(string b64) {
        // URL-safe-ish, and also file-system-safe-ish.
        return b64.replace("/", "_").replace("+", "-").replace("=", "");
    }

    public class StickerPack : Object {
        public string pack_id { get; set; }
        public string? name { get; set; }
        public string? summary { get; set; }
        public bool restricted { get; set; }
        public string? source_jid { get; set; }
        public string? source_node { get; set; }
    }

    public class StickerItem : Object {
        public string pack_id { get; set; }
        public int position { get; set; }
        public string? desc { get; set; }
        public string? media_type { get; set; }
        public string? hash_algo { get; set; }
        public string? hash_value { get; set; }
        public string? source_url { get; set; }
        public string? local_path { get; set; }
    }

    public Gee.List<StickerPack> get_packs(Account account) {
        var packs = new ArrayList<StickerPack>();
        foreach (var row in db.sticker_pack.select().with(db.sticker_pack.account_id, "=", account.id)) {
            var p = new StickerPack();
            p.pack_id = row[db.sticker_pack.pack_id];
            p.name = row[db.sticker_pack.name];
            p.summary = row[db.sticker_pack.summary];
            p.restricted = row[db.sticker_pack.restricted];
            p.source_jid = row[db.sticker_pack.source_jid];
            p.source_node = row[db.sticker_pack.source_node];
            packs.add(p);
        }
        return packs;
    }

    public Gee.List<StickerItem> get_items(Account account, string pack_id) {
        var items = new ArrayList<StickerItem>();
        var q = db.sticker_item.select()
            .with(db.sticker_item.account_id, "=", account.id)
            .with(db.sticker_item.pack_id, "=", pack_id)
            .order_by(db.sticker_item.position, "ASC");
        foreach (var row in q) {
            var it = new StickerItem();
            it.pack_id = row[db.sticker_item.pack_id];
            it.position = row[db.sticker_item.position];
            it.desc = row[db.sticker_item.desc];
            it.media_type = row[db.sticker_item.media_type];
            it.hash_algo = row[db.sticker_item.hash_algo];
            it.hash_value = row[db.sticker_item.hash_value];
            it.source_url = row[db.sticker_item.source_url];
            it.local_path = row[db.sticker_item.local_path];
            items.add(it);
        }
        return items;
    }

    public async StickerPack import_pack(Account account, Jid source_jid, string node, string pack_id) throws Error {
        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream == null) throw new StickerError.NOT_CONNECTED("Not connected");

        StanzaNode? pack_node = yield stream.get_module(Pubsub.Module.IDENTITY).request_item(stream, source_jid, node, pack_id);
        if (pack_node == null) throw new StickerError.NOT_FOUND("Sticker pack not found");
        if (pack_node.name != "pack" || pack_node.ns_uri != Xmpp.Xep.Stickers.NS_URI) {
            throw new StickerError.INVALID_URI("PubSub item is not a sticker pack");
        }

        var parsed_pack = parse_pack(pack_node);
        parsed_pack.pack_id = pack_id;
        parsed_pack.source_jid = source_jid.to_string();
        parsed_pack.source_node = node;

        if (parsed_pack.restricted) throw new StickerError.RESTRICTED("Sticker pack is restricted");

        // Store pack metadata
        db.sticker_pack.upsert()
            .value(db.sticker_pack.account_id, account.id, true)
            .value(db.sticker_pack.pack_id, pack_id, true)
            .value(db.sticker_pack.source_jid, parsed_pack.source_jid)
            .value(db.sticker_pack.source_node, parsed_pack.source_node)
            .value(db.sticker_pack.name, parsed_pack.name)
            .value(db.sticker_pack.summary, parsed_pack.summary)
            .value(db.sticker_pack.restricted, parsed_pack.restricted)
            .perform();

        // Replace items
        db.exec(@"DELETE FROM sticker_item WHERE account_id=$(account.id) AND pack_id='$(pack_id.replace("'", "''"))'");

        var items = parse_items(pack_node, pack_id);
        int pos = 0;
        foreach (var item in items) {
            item.position = pos++;

            if (item.source_url != null && item.hash_value != null) {
                string ext = guess_extension(item.media_type);
                string file_name = filename_safe_base64(item.hash_value) + ext;
                string pack_dir = Path.build_filename(get_stickers_dir(), pack_id);
                DirUtils.create_with_parents(pack_dir, 0700);
                string local_path = Path.build_filename(pack_dir, file_name);

                try {
                    yield download_to_file(item.source_url, local_path);
                    item.local_path = local_path;
                    maybe_generate_thumbnail(pack_id, item);
                } catch (Error e) {
                    warning("Failed to download sticker %s: %s", item.source_url, e.message);
                    // Keep pack usable; item just won't be sendable offline.
                }
            }

            db.sticker_item.insert()
                .value(db.sticker_item.account_id, account.id)
                .value(db.sticker_item.pack_id, pack_id)
                .value(db.sticker_item.position, item.position)
                .value(db.sticker_item.desc, item.desc)
                .value(db.sticker_item.media_type, item.media_type)
                .value(db.sticker_item.hash_algo, item.hash_algo)
                .value(db.sticker_item.hash_value, item.hash_value)
                .value(db.sticker_item.source_url, item.source_url)
                .value(db.sticker_item.local_path, item.local_path)
                .perform();
        }

        // Duplicate to our own PEP node
        var my_jid = stream.get_flag(Xmpp.Bind.Flag.IDENTITY).my_jid.bare_jid;
        bool published = yield stream.get_module(Pubsub.Module.IDENTITY).publish(stream, my_jid, STICKERS_NODE, pack_id, pack_node,
            new Pubsub.PublishOptions().set_persist_items(true).set_max_items("max").set_send_last_published_item("never").set_access_model(Pubsub.ACCESS_MODEL_OPEN)
        );
        if (!published) {
            warning("Failed to publish imported sticker pack %s to PEP", pack_id);
        }

        return parsed_pack;
    }

    public async StickerPack preview_pack(Account account, Jid source_jid, string node, string pack_id) throws Error {
        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream == null) throw new StickerError.NOT_CONNECTED("Not connected");

        StanzaNode? pack_node = yield stream.get_module(Pubsub.Module.IDENTITY).request_item(stream, source_jid, node, pack_id);
        if (pack_node == null) throw new StickerError.NOT_FOUND("Sticker pack not found");
        if (pack_node.name != "pack" || pack_node.ns_uri != Xmpp.Xep.Stickers.NS_URI) {
            throw new StickerError.INVALID_URI("PubSub item is not a sticker pack");
        }

        var parsed_pack = parse_pack(pack_node);
        parsed_pack.pack_id = pack_id;
        parsed_pack.source_jid = source_jid.to_string();
        parsed_pack.source_node = node;

        if (parsed_pack.restricted) throw new StickerError.RESTRICTED("Sticker pack is restricted");

        return parsed_pack;
    }

    public void remove_pack(Account account, string pack_id) throws Error {
        // Remove DB entries
        string pack_id_escaped = pack_id.replace("'", "''");
        db.exec(@"DELETE FROM sticker_item WHERE account_id=$(account.id) AND pack_id='$(pack_id_escaped)'");
        db.exec(@"DELETE FROM sticker_pack WHERE account_id=$(account.id) AND pack_id='$(pack_id_escaped)'");

        // Remove downloaded files (best-effort)
        string pack_dir = Path.build_filename(get_stickers_dir(), pack_id);
        try {
            delete_dir_recursive(File.new_for_path(pack_dir));
        } catch (Error e) {
            // best effort; DB removal is the important part
            warning("Failed to remove sticker pack dir %s: %s", pack_dir, e.message);
        }
    }

    public async void send_sticker(Conversation conversation, string pack_id, StickerItem item) throws Error {
        if (item.local_path == null) throw new StickerError.DOWNLOAD_FAILED("Sticker file not available locally");

        var file_manager = stream_interactor.get_module(FileManager.IDENTITY);

        var cfg = new OutgoingStickerConfig(pack_id, (item.desc != null && item.desc != "") ? item.desc : null);

        file_manager.send_file.begin(File.new_for_path(item.local_path), conversation, (file_transfer) => {
            file_transfer.is_sticker = true;
            file_transfer.sticker_pack_id = cfg.pack_id;
            file_transfer.sticker_pack_node = STICKERS_NODE;
            file_transfer.sticker_pack_jid = null;

            // Ensure fallback body is emoji-like desc if we have it
            if (cfg.desc != null) {
                file_transfer.desc = cfg.desc;
            }
        });
    }

    private class OutgoingStickerConfig : Object {
        public string pack_id { get; construct; }
        public string? desc { get; construct; }

        public OutgoingStickerConfig(string pack_id, string? desc) {
            Object(
                pack_id: pack_id.dup(),
                desc: desc != null ? ((!)desc).dup() : null
            );
        }
    }

    private async void download_to_file(string url, string dest_path) throws Error {
        yield ensure_http_context();
        var msg = new Soup.Message("GET", url);
        var bytes = yield http.send_and_read_async(msg, GLib.Priority.LOW, null);
        if (msg.status_code < 200 || msg.status_code >= 300) {
            throw new StickerError.DOWNLOAD_FAILED(@"HTTP $(msg.status_code)" );
        }

        // Bytes may contain NULs; write as binary.
        unowned uint8[] data = bytes.get_data();
        var file = File.new_for_path(dest_path);
        var out = file.replace(null, false, FileCreateFlags.REPLACE_DESTINATION);
        size_t written = 0;
        out.write_all(data, out written);
        out.close();
    }

    public async string create_pack_from_folder(Account account, string folder_path, bool publish) throws Error {
        File folder = File.new_for_path(folder_path);
        FileType folder_type = folder.query_file_type(FileQueryInfoFlags.NONE, null);
        if (folder_type != FileType.DIRECTORY) throw new StickerError.INVALID_URI("Not a folder");

        string pack_id = Xmpp.random_uuid();
        string name = folder.get_basename() ?? pack_id;

        string pack_dir = Path.build_filename(get_stickers_dir(), pack_id);
        DirUtils.create_with_parents(pack_dir, 0700);

        // Store pack metadata
        db.sticker_pack.upsert()
            .value(db.sticker_pack.account_id, account.id, true)
            .value(db.sticker_pack.pack_id, pack_id, true)
            .value(db.sticker_pack.source_jid, "")
            .value(db.sticker_pack.source_node, "")
            .value(db.sticker_pack.name, name)
            .value(db.sticker_pack.summary, "")
            .value(db.sticker_pack.restricted, false)
            .perform();

        // Ensure we don't collide
        db.exec(@"DELETE FROM sticker_item WHERE account_id=$(account.id) AND pack_id='$(pack_id.replace("'", "''"))'");

        var items = new ArrayList<StickerItem>();
        var enumerator = folder.enumerate_children("standard::name,standard::type,standard::size,standard::content-type", FileQueryInfoFlags.NONE, null);
        FileInfo info;
        while ((info = enumerator.next_file(null)) != null) {
            if (info.get_file_type() != FileType.REGULAR) continue;

            string? content_type = info.get_content_type();
            if (content_type == null || !content_type.has_prefix("image/")) {
                // Ignore non-images
                continue;
            }

            var child = folder.get_child(info.get_name());
            string? path = child.get_path();
            if (path == null || path == "") continue;

            // Compute sha-256 hash (base64) and basic metadata
            Bytes bytes = child.load_bytes(null, null);
            unowned uint8[] data = bytes.get_data();
            var hash = new Xmpp.Xep.CryptographicHashes.Hash.compute(ChecksumType.SHA256, data);

            // Copy into our stickers cache dir so the pack remains usable even if the original folder changes.
            string ext = guess_extension(content_type);
            string file_name = filename_safe_base64(hash.val) + ext;
            string local_path = Path.build_filename(pack_dir, file_name);
            try {
                // Only copy if missing; keep existing file if already present.
                if (!FileUtils.test(local_path, FileTest.EXISTS)) {
                    child.copy(File.new_for_path(local_path), FileCopyFlags.OVERWRITE, null, null);
                }
            } catch (Error e) {
                warning("Failed to copy sticker into cache: %s", e.message);
                local_path = path;
            }

            var it = new StickerItem();
            it.pack_id = pack_id;
            it.position = items.size;
            it.desc = null;
            it.media_type = content_type;
            it.hash_algo = hash.algo;
            it.hash_value = hash.val;
            it.source_url = null;
            it.local_path = local_path;
            items.add(it);

            maybe_generate_thumbnail(pack_id, it);

            db.sticker_item.insert()
                .value(db.sticker_item.account_id, account.id)
                .value(db.sticker_item.pack_id, pack_id)
                .value(db.sticker_item.position, it.position)
                .value(db.sticker_item.desc, it.desc)
                .value(db.sticker_item.media_type, it.media_type)
                .value(db.sticker_item.hash_algo, it.hash_algo)
                .value(db.sticker_item.hash_value, it.hash_value)
                .value(db.sticker_item.source_url, it.source_url)
                .value(db.sticker_item.local_path, it.local_path)
                .perform();
        }
        enumerator.close(null);

        if (items.size == 0) throw new StickerError.NOT_FOUND("No images found in folder");

        if (!publish) {
            return "";
        }

        return yield publish_pack(account, pack_id);
    }

    public async string publish_pack(Account account, string pack_id) throws Error {
        XmppStream? stream = stream_interactor.get_stream(account);
        if (stream == null) throw new StickerError.NOT_CONNECTED("Not connected");

        // Load pack metadata
        StickerPack? pack = null;
        foreach (var p in get_packs(account)) {
            if (p.pack_id == pack_id) {
                pack = p;
                break;
            }
        }
        if (pack == null) throw new StickerError.NOT_FOUND("Sticker pack not found");
        if (pack.restricted) throw new StickerError.RESTRICTED("Sticker pack is restricted");

        // Ensure we have items
        var items = get_items(account, pack_id);
        if (items.size == 0) throw new StickerError.NOT_FOUND("Sticker pack is empty");

        var upload = stream.get_module(Xmpp.Xep.HttpFileUpload.Module.IDENTITY);
        if (upload == null) throw new StickerError.PUBLISH_FAILED("HTTP File Upload (XEP-0363) is not available");

        var pubsub = stream.get_module(Pubsub.Module.IDENTITY);
        if (pubsub == null) throw new StickerError.PUBLISH_FAILED("PubSub module unavailable");

        // Upload any item that doesn't have a source URL yet
        foreach (var it in items) {
            if (it.source_url != null && it.source_url != "") continue;
            if (it.local_path == null || it.local_path == "") {
                warning("Sticker item has no local path; skipping upload");
                continue;
            }

            File f = File.new_for_path(it.local_path);
            FileInfo finfo = f.query_info("standard::size", FileQueryInfoFlags.NONE, null);
            int64 size = finfo.get_size();

            string filename = f.get_basename() ?? (it.hash_value ?? Xmpp.random_uuid());
            string? ct = (it.media_type != null && it.media_type != "") ? it.media_type : "application/octet-stream";
            var slot = yield upload.request_slot(stream, filename, size, ct);

            yield upload_file_to_slot(slot.url_put, slot.headers, f, ct, size, account.domainpart);

            it.source_url = slot.url_get;

            // Update existing row (older DBs don't have a UNIQUE constraint needed for UPSERT).
            db.sticker_item.update()
                .with(db.sticker_item.account_id, "=", account.id)
                .with(db.sticker_item.pack_id, "=", pack_id)
                .with(db.sticker_item.position, "=", it.position)
                .set(db.sticker_item.desc, it.desc)
                .set(db.sticker_item.media_type, it.media_type)
                .set(db.sticker_item.hash_algo, it.hash_algo)
                .set(db.sticker_item.hash_value, it.hash_value)
                .set(db.sticker_item.source_url, it.source_url)
                .set(db.sticker_item.local_path, it.local_path)
                .perform();
        }

        // Build and publish sticker pack to our PEP node
        StanzaNode pack_node = build_pack_node(pack.name, pack.summary, items);
        var bind = stream.get_flag(Xmpp.Bind.Flag.IDENTITY);
        if (bind == null || bind.my_jid == null) throw new StickerError.NOT_CONNECTED("Not connected");
        var my_jid = bind.my_jid.bare_jid;
        bool published = yield pubsub.publish(
            stream,
            my_jid,
            STICKERS_NODE,
            pack_id,
            pack_node,
            new Pubsub.PublishOptions().set_persist_items(true).set_max_items("max").set_send_last_published_item("never").set_access_model(Pubsub.ACCESS_MODEL_OPEN)
        );
        if (!published) throw new StickerError.PUBLISH_FAILED("Failed to publish sticker pack");

        // Store source info for sharing
        db.sticker_pack.upsert()
            .value(db.sticker_pack.account_id, account.id, true)
            .value(db.sticker_pack.pack_id, pack_id, true)
            .value(db.sticker_pack.source_jid, my_jid.to_string())
            .value(db.sticker_pack.source_node, STICKERS_NODE)
            .value(db.sticker_pack.name, pack.name ?? pack_id)
            .value(db.sticker_pack.summary, pack.summary ?? "")
            .value(db.sticker_pack.restricted, false)
            .perform();

        string node_enc = Uri.escape_string(STICKERS_NODE, null, false);
        string item_enc = Uri.escape_string(pack_id, null, false);
        return @"xmpp:$(my_jid.to_string())?pubsub;action=retrieve;node=$(node_enc);item=$(item_enc)";
    }

    private async void upload_file_to_slot(string url_put, Gee.Map<string, string>? headers, File file, string? content_type, int64 size, string cert_domain) throws Error {
        yield ensure_http_context();
        var put_message = new Soup.Message("PUT", url_put);
#if SOUP_3_0
        put_message.accept_certificate.connect((peer_cert, errors) => { return ConnectionManager.on_invalid_certificate(cert_domain, peer_cert, errors); });
        InputStream input_stream = file.read(null);
        string ct = (content_type != null && content_type != "") ? content_type : "application/octet-stream";
        put_message.set_request_body(ct, input_stream, (ssize_t) size);
#else
        // Older libsoup not supported here
#endif

        if (headers != null) {
            foreach (var entry in headers.entries) {
                put_message.request_headers.append(entry.key, entry.value);
            }
        }

        yield http.send_async(put_message, GLib.Priority.LOW, null);
        if (put_message.status_code < 200 || put_message.status_code >= 300) {
            throw new StickerError.DOWNLOAD_FAILED(@"HTTP $(put_message.status_code)" );
        }
    }

    private static StanzaNode build_pack_node(string? name, string? summary, Gee.List<StickerItem> items) {
        StanzaNode pack_node = new StanzaNode.build("pack", Xmpp.Xep.Stickers.NS_URI).add_self_xmlns();
        if (name != null && name != "") {
            pack_node.put_node(new StanzaNode.build("name", Xmpp.Xep.Stickers.NS_URI).put_node(new StanzaNode.text(name)));
        }
        if (summary != null && summary != "") {
            pack_node.put_node(new StanzaNode.build("summary", Xmpp.Xep.Stickers.NS_URI).put_node(new StanzaNode.text(summary)));
        }

        foreach (var it in items) {
            StanzaNode item_node = new StanzaNode.build("item", Xmpp.Xep.Stickers.NS_URI);

            var meta = new Xmpp.Xep.FileMetadataElement.FileMetadata();
            if (it.local_path != null) {
                meta.name = Path.get_basename(it.local_path);
            }
            meta.mime_type = it.media_type;
            meta.size = -1;
            if (it.local_path != null) {
                try {
                    var finfo = File.new_for_path(it.local_path).query_info("standard::size", FileQueryInfoFlags.NONE, null);
                    meta.size = finfo.get_size();
                } catch (Error e) {
                    meta.size = -1;
                }
            }
            if (it.hash_value != null && it.hash_algo != null) {
                ChecksumType? t = Xmpp.Xep.CryptographicHashes.hash_string_to_type(it.hash_algo);
                if (t != null) {
                    meta.hashes.add(new Xmpp.Xep.CryptographicHashes.Hash.with_checksum(t, it.hash_value));
                }
            }
            item_node.put_node(meta.to_stanza_node());

            if (it.source_url != null) {
                StanzaNode sources_node = new StanzaNode.build("sources", Xmpp.Xep.StatelessFileSharing.NS_URI).add_self_xmlns();
                sources_node.put_node(Xmpp.Xep.HttpSchemeForUrlData.to_stanza_node(it.source_url));
                item_node.put_node(sources_node);
            }

            pack_node.put_node(item_node);
        }

        return pack_node;
    }

    private static void delete_dir_recursive(File file) throws Error {
        FileType t;
        try {
            var info = file.query_info("standard::type", FileQueryInfoFlags.NONE, null);
            t = info.get_file_type();
        } catch (Error e) {
            // Doesn't exist or not accessible
            return;
        }

        if (t == FileType.DIRECTORY) {
            var enumerator = file.enumerate_children("standard::name,standard::type", FileQueryInfoFlags.NONE, null);
            FileInfo child_info;
            while ((child_info = enumerator.next_file(null)) != null) {
                var child = file.get_child(child_info.get_name());
                delete_dir_recursive(child);
            }
            enumerator.close(null);
            try {
                file.delete(null);
            } catch (Error e) {
                // might be non-empty due to races; ignore
            }
        } else {
            try {
                file.delete(null);
            } catch (Error e) {
                // ignore
            }
        }
    }

    private static string guess_extension(string? media_type) {
        if (media_type == null) return "";
        switch (media_type) {
            case "image/png": return ".png";
            case "image/gif": return ".gif";
            case "image/webp": return ".webp";
            case "image/jpeg": return ".jpg";
            case "image/svg+xml": return ".svg";
            default: return "";
        }
    }

    private static StickerPack parse_pack(StanzaNode pack_node) {
        var pack = new StickerPack();
        // name/summary: pick first without lang preference
        var name_node = pack_node.get_subnode("name", Xmpp.Xep.Stickers.NS_URI);
        if (name_node != null) pack.name = name_node.get_string_content();
        var summary_node = pack_node.get_subnode("summary", Xmpp.Xep.Stickers.NS_URI);
        if (summary_node != null) pack.summary = summary_node.get_string_content();
        pack.restricted = pack_node.get_subnode("restricted", Xmpp.Xep.Stickers.NS_URI) != null;
        return pack;
    }

    private static Gee.List<StickerItem> parse_items(StanzaNode pack_node, string pack_id) {
        var items = new ArrayList<StickerItem>();
        foreach (var item_node in pack_node.get_subnodes("item", Xmpp.Xep.Stickers.NS_URI)) {
            var it = new StickerItem();
            it.pack_id = pack_id;

            var metadata = Xep.FileMetadataElement.get_file_metadata(item_node);
            if (metadata != null) {
                it.desc = metadata.desc;
                it.media_type = metadata.mime_type;
                if (metadata.hashes.size > 0) {
                    // pick first
                    it.hash_algo = metadata.hashes[0].algo;
                    it.hash_value = metadata.hashes[0].val;
                }
            }

            var sources_node = item_node.get_subnode("sources", Xep.StatelessFileSharing.NS_URI);
            if (sources_node != null) {
                it.source_url = Xep.HttpSchemeForUrlData.get_url(sources_node);
            }

            items.add(it);
        }
        return items;
    }
}

}
