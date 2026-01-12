using Dino.Entities;
using Xmpp;
using Gee;
using Crypto;

namespace Dino.Plugins.HttpFiles {

class EncryptedHttpFileSendData : HttpFileSendData {
    public uint8[] key;
    public uint8[] iv;
}

public class HttpFileSender : FileSender, Object {
    private StreamInteractor stream_interactor;
    private Database db;
    private Soup.Session session;
    private GLib.MainContext soup_context;
    private HashMap<Account, long> max_file_sizes = new HashMap<Account, long>(Account.hash_func, Account.equals_func);

    public HttpFileSender(StreamInteractor stream_interactor, Database db) {
        this.stream_interactor = stream_interactor;
        this.db = db;

        // libsoup is bound to the thread-default main context at creation time.
        // Ensure we always use this session from the same context.
        this.soup_context = GLib.MainContext.ref_thread_default();
        this.session = new Soup.Session();

        session.user_agent = @"Dino/$(Dino.get_short_version()) ";
        stream_interactor.stream_negotiated.connect(on_stream_negotiated);
        stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).build_message_stanza.connect(check_add_sfs_element);
    }

    private async void ensure_soup_context() {
        // `get_thread_default()` may be null even while running on the default main
        // context. `MainContext.invoke()` may execute callbacks immediately in some
        // situations; if that happens before we reach `yield`, it can cause re-entrant
        // recursion in Vala async state machines. Use an explicit Source attached to
        // the desired context to guarantee asynchronous resumption.
        if (soup_context.is_owner()) return;
        var idle = new GLib.IdleSource();
        idle.set_callback(() => {
            ensure_soup_context.callback();
            return GLib.Source.REMOVE;
        });
        idle.attach(soup_context);
        yield;
    }

    public async FileSendData? prepare_send_file(Conversation conversation, FileTransfer file_transfer, FileMeta file_meta) throws FileSendError {
        HttpFileSendData send_data;
        int64 upload_size = file_meta.size;

        if (file_transfer.encryption != Encryption.NONE) {
            var enc_data = new EncryptedHttpFileSendData();
            enc_data.key = new uint8[32];
            enc_data.iv = new uint8[12];
            Crypto.randomize(enc_data.key);
            Crypto.randomize(enc_data.iv);
            // AES-GCM adds 16 bytes auth tag
            upload_size += 16;
            send_data = enc_data;
        } else {
            send_data = new HttpFileSendData();
        }

        if (send_data == null) return null;

        Xmpp.XmppStream? stream = stream_interactor.get_stream(file_transfer.account);
        if (stream == null) return null;

        try {
            debug("http-files: requesting upload slot name='%s' size=%lld mime=%s",
                  file_transfer.server_file_name,
                  upload_size,
                  file_meta.mime_type ?? "(null)");
            var slot_result = yield stream_interactor.module_manager.get_module<Xmpp.Xep.HttpFileUpload.Module>(file_transfer.account, Xmpp.Xep.HttpFileUpload.Module.IDENTITY).request_slot(stream, file_transfer.server_file_name, upload_size, file_meta.mime_type);
            send_data.url_down = slot_result.url_get;
            send_data.url_up = slot_result.url_put;
            send_data.headers = slot_result.headers;
            debug("http-files: got slot url_get=%s url_put=%s", sanitize_url_for_log(send_data.url_down), sanitize_url_for_log(send_data.url_up));
        } catch (Xep.HttpFileUpload.HttpFileTransferError e) {
            throw new FileSendError.UPLOAD_FAILED("Http file upload XMPP error: %s".printf(e.message));
        }

        return send_data;
    }

    public async void send_file(Conversation conversation, FileTransfer file_transfer, FileSendData file_send_data, FileMeta file_meta) throws FileSendError {
        HttpFileSendData? send_data = file_send_data as HttpFileSendData;
        if (send_data == null) return;

        debug("http-files: send_file start encryption=%d conv_encryption=%d can_reference? computing...", (int) file_transfer.encryption, (int) conversation.encryption);

        bool can_reference_element = conversation.type_ == Conversation.Type.CHAT || 
                                      conversation.type_ == Conversation.Type.GROUPCHAT_PM || (
                // The stable stanza ID XEP is not clear about an announcing MUC having to attach stanza-ids, thus we also check for MAM, which requires this.
                stream_interactor.get_module<EntityInfo>(EntityInfo.IDENTITY).has_feature_cached(conversation.account, conversation.counterpart, Xep.UniqueStableStanzaIDs.NS_URI) &&
                stream_interactor.get_module<EntityInfo>(EntityInfo.IDENTITY).has_feature_cached(conversation.account, conversation.counterpart, Xmpp.MessageArchiveManagement.NS_URI)
            );

        // Share unencrypted files via SFS (only if we'll be able to reference messages)
        if (conversation.encryption == Encryption.NONE && can_reference_element) {
            debug("http-files: sending as SFS+attachment (unencrypted), url=%s", sanitize_url_for_log(send_data.url_down));
            // Announce the file share
            Entities.Message file_share_message = stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).create_out_message(null, conversation);
            file_transfer.info = file_share_message.id.to_string();
            file_transfer.file_sharing_id = Xmpp.random_uuid();
            stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).send_xmpp_message(file_share_message, conversation);

            // Upload file
            yield upload(file_transfer, send_data, file_meta);

            // Wait until we know the server id of the file share message (in MUCs; we get that from the reflected message)
            if (conversation.type_.is_muc_semantic()) {
                if (file_share_message.server_id == null) {
                    ulong server_id_notify_id = file_share_message.notify["server-id"].connect(() => {
                        Idle.add(send_file.callback);
                    });
                    yield;
                    file_share_message.disconnect(server_id_notify_id);
                }
            }

            file_transfer.sfs_sources.add(new Xep.StatelessFileSharing.HttpSource() { url=send_data.url_down } );

            // Send source attachment
            MessageStanza stanza = new MessageStanza() { to = conversation.counterpart, type_ = conversation.type_ == GROUPCHAT ? MessageStanza.TYPE_GROUPCHAT : MessageStanza.TYPE_CHAT };
            stanza.body = send_data.url_down;
            Xep.OutOfBandData.add_url_to_message(stanza, send_data.url_down);
            var sources = new ArrayList<Xep.StatelessFileSharing.Source>();
            sources.add(new Xep.StatelessFileSharing.HttpSource() { url = send_data.url_down });
            string attach_to_id = MessageStorage.get_reference_id(file_share_message);
            Xep.StatelessFileSharing.set_sfs_attachment(stanza, attach_to_id, file_transfer.file_sharing_id, sources);

            var stream = stream_interactor.get_stream(conversation.account);
            if (stream == null) throw new FileSendError.UPLOAD_FAILED("No stream");

            stream.get_module<MessageModule>(MessageModule.IDENTITY).send_message.begin(stream, stanza);
        }
        // Share encrypted files without SFS
        else {
            debug("http-files: sending encrypted or non-referenceable; uploading first url=%s", sanitize_url_for_log(send_data.url_down));
            yield upload(file_transfer, send_data, file_meta);

            // Construct aesgcm URL if encrypted
            if (send_data is EncryptedHttpFileSendData) {
                var enc_data = (EncryptedHttpFileSendData) send_data;
                string iv_hex = "";
                foreach (uint8 b in enc_data.iv) iv_hex += "%02x".printf(b);
                string key_hex = "";
                foreach (uint8 b in enc_data.key) key_hex += "%02x".printf(b);
                
                // Format: aesgcm://host/path#iv_hex+key_hex
                string http_url = send_data.url_down;
                string path_part = http_url;
                if (http_url.has_prefix("https://")) path_part = http_url.substring(8);
                else if (http_url.has_prefix("http://")) path_part = http_url.substring(7);
                
                send_data.url_down = "aesgcm://%s#%s%s".printf(path_part, iv_hex, key_hex);
            }

            // For encrypted sends, include SFS metadata in the (encrypted) message stanza.
            // This improves interoperability with clients that expect SFS + sticker references.
            if (file_transfer.file_sharing_id == null || file_transfer.file_sharing_id == "") {
                file_transfer.file_sharing_id = Xmpp.random_uuid();
            }

            // IMPORTANT: Do not leak OMEMO file keys in cleartext.
            // `send_data.url_down` is an aesgcm:// URL that contains iv+key in the fragment.
            // Publish only the transport URL (https://, without fragment) via SFS.
            string sfs_url = send_data.url_down;
            if (sfs_url.has_prefix("aesgcm://")) {
                sfs_url = "https://" + sfs_url.substring("aesgcm://".length);
            }
            int fragment_index = sfs_url.index_of("#");
            if (fragment_index >= 0) {
                sfs_url = sfs_url.substring(0, fragment_index);
            }
            debug("http-files: derived transport url for SFS sources=%s", sanitize_url_for_log(sfs_url));
            file_transfer.add_sfs_source(new Xep.StatelessFileSharing.HttpSource() { url = sfs_url });

            Entities.Message message = stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).create_out_message(send_data.url_down, conversation);
            file_transfer.info = message.id.to_string();

            // Add XEP-0448 Encryption Data to the message stanza
            if (send_data is EncryptedHttpFileSendData) {
                var enc_data = (EncryptedHttpFileSendData) send_data;
                var sfs_encryption = new Xep.StatelessFileSharing.EncryptionData();
                sfs_encryption.key = enc_data.key;
                sfs_encryption.iv = enc_data.iv;
                
                // We need to hook into the message building process to inject the SFS element.
                // Since we don't have a direct way to modify the stanza here before it's sent by MessageProcessor,
                // we can use the 'build_message_stanza' signal or similar, but that's global.
                // Alternatively, we can manually construct the SFS element and attach it if MessageProcessor allows.
                
                // Better approach: The MessageProcessor emits 'build_message_stanza'. We can connect to it temporarily?
                // Or, we can use the fact that we are in a plugin.
                
                // Actually, let's look at how SFS is usually attached.
                // In 'send_file' above (unencrypted branch), it does:
                // Xep.StatelessFileSharing.set_sfs_attachment(stanza, attach_to_id, file_transfer.file_sharing_id, sources);
                // But that's for attaching to an existing message.
                
                // Here we are creating a new message.
                // We can use a one-shot signal handler on the message processor for this specific message ID?
                // Or we can just attach the SFS element to the message object if it supports it?
                // The 'Entities.Message' object doesn't hold arbitrary stanza nodes.
                
                // Let's use a signal connection on the message processor for this specific send.
                ulong signal_id = 0;
                signal_id = stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).build_message_stanza.connect((msg, stanza, conv) => {
                    if (msg.id == message.id) {
                        var sources = new ArrayList<Xep.StatelessFileSharing.Source>();
                        sources.add(new Xep.StatelessFileSharing.HttpSource() { url = sfs_url });
                        
                        Xep.StatelessFileSharing.set_sfs_element(stanza, file_transfer.file_sharing_id, file_transfer.file_metadata, sources, sfs_encryption);
                        stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).disconnect(signal_id);
                    }
                });
            }

            message.encryption = send_data.encrypt_message ? conversation.encryption : Encryption.NONE;
            debug("http-files: sending message body url=%s message.encryption=%d", sanitize_url_for_log(send_data.url_down), (int) message.encryption);
            stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).send_xmpp_message(message, conversation);
        }
    }

    public async bool can_send(Conversation conversation, FileTransfer file_transfer) {
        if (!max_file_sizes.has_key(conversation.account)) return false;

        return file_transfer.size < max_file_sizes[conversation.account];
    }

    public async long get_file_size_limit(Conversation conversation) {
        long? max_size = max_file_sizes[conversation.account];
        if (max_size != null) {
            return max_size;
        }
        return -1;
    }

    public async bool can_encrypt(Conversation conversation, FileTransfer file_transfer) {
        return conversation.encryption != Encryption.NONE;
    }

    public async bool is_upload_available(Conversation conversation) {
        lock (max_file_sizes) {
            return max_file_sizes.has_key(conversation.account);
        }
    }

#if !SOUP_3_0
    private static void transfer_more_bytes(InputStream stream, Soup.MessageBody body) {
        uint8[] bytes = new uint8[4096];
        ssize_t read = stream.read(bytes);
        if (read == 0) {
            body.complete();
            return;
        }
        bytes.length = (int)read;
        body.append_buffer(new Soup.Buffer.take(bytes));
    }
#endif

    private async void upload(FileTransfer file_transfer, HttpFileSendData file_send_data, FileMeta file_meta) throws FileSendError {
        Xmpp.XmppStream? stream = stream_interactor.get_stream(file_transfer.account);
        if (stream == null) return;

        yield ensure_soup_context();

        var put_message = new Soup.Message("PUT", file_send_data.url_up);
        
        InputStream upload_stream = file_transfer.input_stream;
        int64 upload_size = file_meta.size;

        if (file_send_data is EncryptedHttpFileSendData) {
            var enc_data = (EncryptedHttpFileSendData) file_send_data;
            try {
                var cipher = new SymmetricCipher("AES256-GCM");
                cipher.set_key(enc_data.key);
                cipher.set_iv(enc_data.iv);
                // GCM tag length is 16
                var encrypter = new SymmetricCipherEncrypter((owned) cipher, 16);
                upload_stream = new ConverterInputStream(upload_stream, encrypter);
                upload_size += 16;
            } catch (Crypto.Error e) {
                throw new FileSendError.UPLOAD_FAILED("Encryption setup failed: %s".printf(e.message));
            }
        }

#if SOUP_3_0
        string transfer_host = "";
        try {
            transfer_host = Uri.parse(file_send_data.url_up, UriFlags.NONE).get_host();
        } catch (GLib.Error e) {
            warning("Failed to parse URI: %s", e.message);
        }
        put_message.accept_certificate.connect((peer_cert, errors) => { return ConnectionManager.on_invalid_certificate(transfer_host, peer_cert, errors); });
        put_message.set_request_body(file_meta.mime_type, upload_stream, (ssize_t) upload_size);
#else

        put_message.request_headers.set_content_type(file_meta.mime_type, null);
        put_message.request_headers.set_content_length(upload_size);
        put_message.request_body.set_accumulate(false);
        put_message.wrote_headers.connect(() => transfer_more_bytes(upload_stream, put_message.request_body));
        put_message.wrote_chunk.connect(() => transfer_more_bytes(upload_stream, put_message.request_body));
#endif
        foreach (var entry in file_send_data.headers.entries) {
            put_message.request_headers.append(entry.key, entry.value);
        }
        try {
            debug("http-files: uploading via PUT %s (%lld bytes)", sanitize_url_for_log(file_send_data.url_up), (long) upload_size);
#if SOUP_3_0
            yield session.send_async(put_message, GLib.Priority.LOW, file_transfer.cancellable);
#else
            yield session.send_async(put_message, file_transfer.cancellable);
#endif
            if (put_message.status_code < 200 || put_message.status_code >= 300) {
                throw new FileSendError.UPLOAD_FAILED("HTTP status code %s".printf(put_message.status_code.to_string()));
            }
            debug("http-files: upload finished status=%u", put_message.status_code);
        } catch (GLib.Error e) {
            throw new FileSendError.UPLOAD_FAILED("HTTP upload error: %s".printf(e.message));
        }
    }

    private static string sanitize_url_for_log(string? url) {
        if (url == null) return "(null)";
        string s = url;
        int hash = s.index_of("#");
        if (hash >= 0) s = s.substring(0, hash) + "#…";
        // Avoid spewing huge query strings in logs.
        int q = s.index_of("?");
        if (q >= 0 && q < s.length) {
            s = s.substring(0, q) + "?…";
        }
        return s;
    }

    private void on_stream_negotiated(Account account, XmppStream stream) {
        stream_interactor.module_manager.get_module<Xmpp.Xep.HttpFileUpload.Module>(account, Xmpp.Xep.HttpFileUpload.Module.IDENTITY).feature_available.connect((stream, max_file_size) => {
            lock (max_file_sizes) {
                max_file_sizes[account] = max_file_size;
            }
            upload_available(account);
        });
    }

    private void check_add_sfs_element(Entities.Message message, Xmpp.MessageStanza message_stanza, Conversation conversation) {
        FileTransfer? file_transfer = stream_interactor.get_module<FileTransferStorage>(FileTransferStorage.IDENTITY).get_file_by_message_id(message.id, conversation);
        if (file_transfer == null) return;

        // NOTE: Our OMEMO implementation only encrypts the body and leaves other stanza nodes in cleartext.
        // Adding SFS elements to OMEMO messages can therefore leak metadata and/or break interoperability
        // (hash verification vs encrypted payload, missing key material, etc.).
        if (message.encryption == Encryption.NONE) {
            Xep.StatelessFileSharing.set_sfs_element(message_stanza, file_transfer.file_sharing_id, file_transfer.file_metadata, file_transfer.sfs_sources);
        }

        if (file_transfer.is_sticker && file_transfer.sticker_pack_id != null) {
            var sticker = new Xmpp.Xep.Stickers.StickerReference();
            sticker.pack_id = file_transfer.sticker_pack_id;
            // Only include jid/node if this sticker pack is not from our own PEP node
            if (file_transfer.sticker_pack_jid != null) sticker.jid = file_transfer.sticker_pack_jid;
            if (file_transfer.sticker_pack_node != null) sticker.node = file_transfer.sticker_pack_node;
            Xmpp.Xep.Stickers.set_sticker(message_stanza, sticker);
        }

        Xep.MessageProcessingHints.set_message_hint(message_stanza, Xep.MessageProcessingHints.HINT_STORE);
    }

    public int get_id() { return 0; }

    public float get_priority() { return 100; }
}

}
