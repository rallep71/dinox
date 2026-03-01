using Gee;

using Dino.Entities;
using Xmpp;

namespace Dino.Plugins.HttpFiles {

public class FileProvider : Dino.FileProvider, Object {

    private StreamInteractor stream_interactor;
    private Dino.Database dino_db;
    private Soup.Session session;
    private GLib.MainContext soup_context;
    public static Regex http_url_regex = /^https?:\/\/([^\s#]*)$/; // Spaces are invalid in URLs and we can't use fragments for downloads
    // OMEMO aesgcm:// links carry the secret (iv+key) in the fragment. Different clients may
    // encode the fragment differently (hex, base64, urlsafe base64), so only validate the
    // rough structure here and let the OMEMO decryptor parse the secret.
    public static Regex omemo_url_regex = /^aesgcm:\/\/([^\s#]+)#([^\s]+)$/;

    public static string sanitize_for_log(string? s) {
        if (s == null) return "(null)";
        string out = s;
        // Never log secrets in fragments.
        int hash = out.index_of("#");
        if (hash >= 0) out = out.substring(0, hash) + "#...";
        // Keep logs small.
        if (out.length > 200) out = out.substring(0, 200) + "...";
        return out;
    }

    public FileProvider(StreamInteractor stream_interactor, Dino.Database dino_db) {
        this.stream_interactor = stream_interactor;
        this.dino_db = dino_db;

        // libsoup is bound to the thread-default main context at creation time.
        // We may be called from non-UI contexts, so always hop back before using the session.
        this.soup_context = GLib.MainContext.ref_thread_default();
        this.session = new Soup.Session();

        session.user_agent = @"Dino/$(Dino.get_short_version()) ";
        stream_interactor.get_module<MessageProcessor>(MessageProcessor.IDENTITY).received_pipeline.connect(new ReceivedMessageListener(this));
    }

    public void shutdown() {
        session.abort();
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

    private class ReceivedMessageListener : MessageListener {

        public string[] after_actions_const = new string[]{ "STORE" };
        public override string action_group { get { return "MESSAGE_REINTERPRETING"; } }
        public override string[] after_actions { get { return after_actions_const; } }

        private FileProvider outer;
        private StreamInteractor stream_interactor;

        public ReceivedMessageListener(FileProvider outer) {
            this.outer = outer;
            this.stream_interactor = outer.stream_interactor;
        }

        public override async bool run(Entities.Message message, Xmpp.MessageStanza stanza, Conversation conversation) {
            if (Xep.StatelessFileSharing.get_file_shares(stanza) != null || Xep.StatelessFileSharing.get_source_attachments(stanza) != null) {
                return false;
            }

            string? oob_url = Xmpp.Xep.OutOfBandData.get_url_from_message(stanza);

            // Determine the file URL candidate:
            // - If OOB element present: use that URL (standard file transfer)
            // - If no OOB but body is an aesgcm:// URL: treat as OMEMO file transfer
            // - If no OOB and body is a plain http(s):// URL: this is a normal text
            //   message with a link, NOT a file transfer — do not intercept
            string? url_candidate = null;
            if (oob_url != null) {
                url_candidate = oob_url;
            } else if (message.body != null && FileProvider.omemo_url_regex.match(message.body)) {
                url_candidate = message.body;
            }

            bool normal_file = url_candidate != null && FileProvider.http_url_regex.match(url_candidate);
            bool omemo_file = url_candidate != null && FileProvider.omemo_url_regex.match(url_candidate);
            if (normal_file || omemo_file) {
                debug("http-files: incoming legacy file message normal=%s omemo=%s url_from=%s url=%s body='%s'",
                      normal_file.to_string(),
                      omemo_file.to_string(),
                      oob_url != null ? "oob" : "body",
                      FileProvider.sanitize_for_log(url_candidate),
                      FileProvider.sanitize_for_log(message.body));
                outer.on_file_message(message, stanza, conversation, url_candidate);
                return true;
            }
            return false;
        }
    }

    private void on_file_message(Entities.Message message, Xmpp.MessageStanza stanza, Conversation conversation, string url) {
        // Always store the message database ID so lookups (deletion, reactions, etc.) work.
        string additional_info = message.id.to_string();

        var receive_data = new HttpFileReceiveData();
        receive_data.url = url;

        var file_meta = new HttpFileMeta();
        file_meta.file_name = extract_file_name_from_url(url);
        file_meta.message = message;
        
        // Try to get metadata from SFS element
        var file_shares = Xep.StatelessFileSharing.get_file_shares(stanza);
        if (file_shares != null && !file_shares.is_empty) {
            var sfs_metadata = file_shares[0].metadata;
            if (sfs_metadata != null) {
                if (sfs_metadata.mime_type != null) file_meta.mime_type = sfs_metadata.mime_type;
                if (sfs_metadata.name != null) file_meta.file_name = sfs_metadata.name;
                if (sfs_metadata.size != -1) file_meta.size = sfs_metadata.size;
            }
        }

        file_incoming(additional_info, message.from, message.time, message.local_time, conversation, receive_data, file_meta);
    }

    public async FileMeta get_meta_info(FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta) throws FileReceiveError {
        HttpFileReceiveData? http_receive_data = receive_data as HttpFileReceiveData;
        if (http_receive_data == null) return file_meta;

        yield ensure_soup_context();

        var head_message = new Soup.Message("HEAD", http_receive_data.url);
        head_message.request_headers.append("Accept-Encoding", "identity");

#if SOUP_3_0
        string transfer_host = "";
        try {
            transfer_host = Uri.parse(http_receive_data.url, UriFlags.NONE).get_host();
        } catch (Error e) {
            warning("Failed to parse URI: %s", e.message);
        }
        head_message.accept_certificate.connect((peer_cert, errors) => { return ConnectionManager.on_invalid_certificate(transfer_host, peer_cert, errors, dino_db); });
#endif


        try {
#if SOUP_3_0
            yield session.send_async(head_message, GLib.Priority.LOW, null);
#else
            yield session.send_async(head_message, null);
#endif
        } catch (Error e) {
            throw new FileReceiveError.GET_METADATA_FAILED("HEAD request failed");
        }

        uint head_status = head_message.status_code;
        if (head_status < 200 || head_status >= 300) {
            throw new FileReceiveError.GET_METADATA_FAILED("HEAD request returned HTTP %u".printf(head_status));
        }

        string? content_type = null, content_length = null;
        head_message.response_headers.foreach((name, val) => {
            if (name.down() == "content-type") content_type = val;
            if (name.down() == "content-length") content_length = val;
        });
        file_meta.mime_type = content_type;
        if (content_length != null) {
            file_meta.size = int64.parse(content_length);
        }

        return file_meta;
    }

    public Encryption get_encryption(FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta) {
        // Propagate the message-level encryption (PGP, OMEMO, etc.) to the file transfer.
        // The file content is AES-GCM encrypted (aesgcm:// URL), while the message carrying
        // the decryption key is encrypted with the conversation's encryption (e.g. PGP/OMEMO).
        HttpFileMeta? http_meta = file_meta as HttpFileMeta;
        if (http_meta != null && http_meta.message != null && http_meta.message.encryption != Encryption.NONE) {
            return http_meta.message.encryption;
        }
        return Encryption.NONE;
    }

    public async InputStream download(FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta) throws IOError {
        HttpFileReceiveData? http_receive_data = receive_data as HttpFileReceiveData;
        if (http_receive_data == null) {
            throw new IOError.INVALID_ARGUMENT("Missing HTTP receive data");
        }

        yield ensure_soup_context();

        var get_message = new Soup.Message("GET", http_receive_data.url);

#if SOUP_3_0
        string transfer_host = "";
        try {
            transfer_host = Uri.parse(http_receive_data.url, UriFlags.NONE).get_host();
        } catch (Error e) {
            warning("Failed to parse URI: %s", e.message);
        }
        get_message.accept_certificate.connect((peer_cert, errors) => { return ConnectionManager.on_invalid_certificate(transfer_host, peer_cert, errors, dino_db); });
#endif

        try {
#if SOUP_3_0
            InputStream stream = yield session.send_async(get_message, GLib.Priority.LOW, file_transfer.cancellable);
#else
            InputStream stream = yield session.send_async(get_message, file_transfer.cancellable);
#endif
            uint status = get_message.status_code;
            if (status < 200 || status >= 300) {
                throw new IOError.FAILED("HTTP download failed: status %u".printf(status));
            }
            if (file_meta.size != -1) {
                return new LimitInputStream(stream, file_meta.size);
            } else {
                return stream;
            }
        } catch (Error e) {
            throw new IOError.FAILED(e.message);
        }

    }

    public FileMeta get_file_meta(FileTransfer file_transfer) throws FileReceiveError {
        if (file_transfer.provider == FileManager.SFS_PROVIDER_ID) {
            var file_meta = new HttpFileMeta();
            file_meta.size = file_transfer.size;
            file_meta.mime_type = file_transfer.mime_type;
            file_meta.file_name = file_transfer.file_name;
            file_meta.message = null;
            return file_meta;
        }

        // Legacy HTTP file transfers may persist the URL in info.
        if (file_transfer.info != null && file_transfer.info.has_prefix("url:")) {
            string url = file_transfer.info.substring("url:".length);
            var file_meta = new HttpFileMeta();
            file_meta.size = file_transfer.size;
            file_meta.mime_type = file_transfer.mime_type;
            file_meta.file_name = extract_file_name_from_url(url);
            file_meta.message = null;
            return file_meta;
        }

        Conversation? conversation = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).get_conversation(file_transfer.counterpart.bare_jid, file_transfer.account);
        if (conversation == null) throw new FileReceiveError.GET_METADATA_FAILED("No conversation");

        Message? message = stream_interactor.get_module<MessageStorage>(MessageStorage.IDENTITY).get_message_by_id(int.parse(file_transfer.info), conversation);
        if (message == null) throw new FileReceiveError.GET_METADATA_FAILED("No message");

        var file_meta = new HttpFileMeta();
        file_meta.size = file_transfer.size;
        file_meta.mime_type = file_transfer.mime_type;

        file_meta.file_name = extract_file_name_from_url(message.body);

        file_meta.message = message;

        return file_meta;
    }

    public FileReceiveData? get_file_receive_data(FileTransfer file_transfer) {
        if (file_transfer.provider == FileManager.SFS_PROVIDER_ID) {
            if (!file_transfer.sfs_sources.is_empty) {
                // Check for ESFS encrypted source first
                var esfs_source = file_transfer.sfs_sources.get(0) as Xep.StatelessFileSharing.EsfsHttpSource;
                if (esfs_source != null) {
                    var receive_data = new EsfsHttpFileReceiveData();
                    receive_data.url = esfs_source.url;
                    receive_data.esfs_key = esfs_source.key;
                    receive_data.esfs_iv = esfs_source.iv;
                    receive_data.esfs_cipher = esfs_source.cipher_uri;
                    return receive_data;
                }
                // Regular HTTP source
                var http_source = file_transfer.sfs_sources.get(0) as Xep.StatelessFileSharing.HttpSource;
                if (http_source != null) {
                    var receive_data = new HttpFileReceiveData();
                    receive_data.url = http_source.url;
                    return receive_data;
                }
            }
            return null;
        }

        if (file_transfer.info != null && file_transfer.info.has_prefix("url:")) {
            var receive_data = new HttpFileReceiveData();
            receive_data.url = file_transfer.info.substring("url:".length);
            return receive_data;
        }

        Conversation? conversation = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).get_conversation(file_transfer.counterpart.bare_jid, file_transfer.account);
        if (conversation == null) return null;

        Message? message = stream_interactor.get_module<MessageStorage>(MessageStorage.IDENTITY).get_message_by_id(int.parse(file_transfer.info), conversation);
        if (message == null) return null;

        var receive_data = new HttpFileReceiveData();
        receive_data.url = message.body;

        return receive_data;
    }

    public string extract_file_name_from_url(string url) {
        string ret = url;
        if (ret.contains("#")) {
            ret = ret.substring(0, ret.last_index_of("#"));
        }
        ret = Uri.unescape_string(ret.substring(ret.last_index_of("/") + 1));
        return ret;
    }

    public int get_id() { return 0; }
}

}
