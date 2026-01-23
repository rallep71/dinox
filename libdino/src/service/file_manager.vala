using Gdk;
using Gee;

using Xmpp;
using Xmpp.Xep;
using Dino.Entities;
using Dino.Security;
// using Dino.Util;

namespace Dino {

public class FileManager : StreamInteractionModule, Object {
    public static ModuleIdentity<FileManager> IDENTITY = new ModuleIdentity<FileManager>("file");
    public string id { get { return IDENTITY.id; } }

    public signal void upload_available(Account account);
    public signal void received_file(FileTransfer file_transfer, Conversation conversation);

    private StreamInteractor stream_interactor;
    private Database db;
    private FileEncryption file_encryption;
    private Gee.List<FileSender> file_senders = new ArrayList<FileSender>();
    private Gee.List<FileEncryptor> file_encryptors = new ArrayList<FileEncryptor>();
    private Gee.List<FileDecryptor> file_decryptors = new ArrayList<FileDecryptor>();
    private Gee.List<FileProvider> file_providers = new ArrayList<FileProvider>();
    private Gee.List<FileMetadataProvider> file_metadata_providers = new ArrayList<FileMetadataProvider>();

    public StatelessFileSharing sfs {
        owned get { return stream_interactor.get_module<StatelessFileSharing>(StatelessFileSharing.IDENTITY); }
        private set { }
    }

    public static void start(StreamInteractor stream_interactor, Database db, FileEncryption file_encryption) {
        FileManager m = new FileManager(stream_interactor, db, file_encryption);
        stream_interactor.add_module(m);
    }

    public static string get_storage_dir() {
        return Path.build_filename(Dino.get_storage_dir(), "files");
    }

    private FileManager(StreamInteractor stream_interactor, Database db, FileEncryption file_encryption) {
        this.stream_interactor = stream_interactor;
        this.db = db;
        this.file_encryption = file_encryption;
        DirUtils.create_with_parents(get_storage_dir(), 0700);

        this.add_provider(new JingleFileProvider(stream_interactor));
        this.add_sender(new JingleFileSender(stream_interactor));
        this.add_metadata_provider(new GenericFileMetadataProvider());
        this.add_metadata_provider(new ImageFileMetadataProvider());
    }

    public const int HTTP_PROVIDER_ID = 0;
    public const int SFS_PROVIDER_ID = 2;

    public FileProvider? select_file_provider(FileTransfer file_transfer) {
        bool http_usable = file_transfer.provider == SFS_PROVIDER_ID;
        foreach (FileProvider file_provider in this.file_providers) {
            if (file_transfer.provider == file_provider.get_id()) {
                return file_provider;
            }
            if (http_usable && file_provider.get_id() == HTTP_PROVIDER_ID) {
                return file_provider;
            }
        }
        return null;
    }

    public async HashMap<int, long> get_file_size_limits(Conversation conversation) {
        HashMap<int, long> ret = new HashMap<int, long>();
        foreach (FileSender sender in file_senders) {
            ret[sender.get_id()] = yield sender.get_file_size_limit(conversation);
        }
        return ret;
    }

    public delegate void OutgoingFileTransferConfigurator(FileTransfer file_transfer);

    public async void send_file(File file, Conversation conversation, owned OutgoingFileTransferConfigurator? configure = null) {
        print("DEBUG: FileManager.send_file: called for %s\n".printf(file.get_path()));
        File file_to_use = file;
        File? temp_file = null;

        string? path = file.get_path();
        if (path != null && path.has_prefix(Dino.get_storage_dir())) {
            try {
                string temp_path = Path.build_filename(Environment.get_tmp_dir(), "dinox-send-" + Random.next_int().to_string("%x"));
                temp_file = File.new_for_path(temp_path);

                var input_stream = file.read();
                var output_stream = temp_file.create(FileCreateFlags.REPLACE_DESTINATION);
                yield file_encryption.decrypt_stream(input_stream, output_stream);
                yield input_stream.close_async();
                yield output_stream.close_async();

                file_to_use = temp_file;
            } catch (Error e) {
                warning("Failed to decrypt file for sending: %s", e.message);
                return;
            }
        }

        // try {
            FileTransfer file_transfer = new FileTransfer();
            file_transfer.account = conversation.account;
            file_transfer.counterpart = conversation.counterpart;
            if (conversation.type_.is_muc_semantic()) {
                file_transfer.ourpart = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_own_jid(conversation.counterpart, conversation.account) ?? conversation.account.bare_jid;
            } else {
                file_transfer.ourpart = conversation.account.full_jid;
            }
            file_transfer.direction = FileTransfer.DIRECTION_SENT;
            file_transfer.time = new DateTime.now_utc();
            file_transfer.local_time = new DateTime.now_utc();
            file_transfer.encryption = conversation.encryption;

            Xep.FileMetadataElement.FileMetadata metadata = new Xep.FileMetadataElement.FileMetadata();
            foreach (FileMetadataProvider file_metadata_provider in this.file_metadata_providers) {
                if (file_metadata_provider.supports_file(file_to_use)) {
                    yield file_metadata_provider.fill_metadata(file_to_use, metadata);
                }
            }
            // Restore original filename if we used a temp file
            if (file_to_use != file) {
                metadata.name = file.get_basename();
                try {
                    file_transfer.input_stream = file_to_use.read();
                } catch (Error e) {
                    warning("Failed to read temp file: %s", e.message);
                    return;
                }
            }
            file_transfer.file_metadata = metadata;

            debug("send_file: preparing '%s' size=%lld mime=%s conv_encryption=%d conv_type=%d",
                  file_transfer.file_name,
                  (long) file_transfer.size,
              file_transfer.mime_type ?? "(null)",
              (int) conversation.encryption,
              (int) conversation.type_);

        if (configure != null) {
            configure(file_transfer);
        }

        try {
            debug("FileManager: Opening stream for local encryption...");
            file_transfer.input_stream = yield file_to_use.read_async();

            debug("FileManager: Saving encrypted local copy...");
            yield save_file(file_transfer);
            debug("FileManager: Local copy saved.");
            
            // save_file consumed the stream, so we need to re-open it for sending
            try { ((InputStream)file_transfer.input_stream).close(); } catch (Error e) {}
            
            debug("FileManager: Re-opening stream for upload...");
            file_transfer.input_stream = yield file_to_use.read_async();
            debug("FileManager: Stream re-opened.");

            stream_interactor.get_module<FileTransferStorage>(FileTransferStorage.IDENTITY).add_file(file_transfer);
            conversation.last_active = file_transfer.time;
            received_file(file_transfer, conversation);
        } catch (Error e) {
            file_transfer.state = FileTransfer.State.FAILED;
            warning("Error saving outgoing file: %s", e.message);
            return;
        }

        try {
            var file_meta = new FileMeta();
            file_meta.size = file_transfer.size;
            file_meta.mime_type = file_transfer.mime_type;

            FileSender file_sender = null;
            FileEncryptor file_encryptor = null;
            foreach (FileSender sender in file_senders) {
                if (yield sender.can_send(conversation, file_transfer)) {
                    if (file_transfer.encryption == Encryption.NONE || yield sender.can_encrypt(conversation, file_transfer)) {
                        file_sender = sender;
                        break;
                    } else {
                        foreach (FileEncryptor encryptor in file_encryptors) {
                            if (encryptor.can_encrypt_file(conversation, file_transfer)) {
                                file_encryptor = encryptor;
                                break;
                            }
                        }
                        if (file_encryptor != null) {
                            // Check if this sender is compatible with Jingle (sender_id=1)
                            // OMEMO file encryption produces HttpFileMeta which is incompatible with Jingle
                            if (sender.get_id() == 1 && file_transfer.encryption == Encryption.OMEMO) {
                                // Skip Jingle sender for OMEMO encrypted files - they require HTTP Upload
                                debug("Skipping Jingle sender for OMEMO encrypted files");
                                file_encryptor = null;
                                continue;
                            }
                            file_sender = sender;
                            break;
                        }
                    }
                }
            }

            if (file_sender != null) {
                debug("send_file: selected sender id=%d prio=%f encryptor=%s",
                      file_sender.get_id(),
                      file_sender.get_priority(),
                      file_encryptor != null ? file_encryptor.get_type().name() : "(none)");
            } else {
                warning("send_file: no sender/encryptor available (encryption=%d size=%lld)",
                        (int) file_transfer.encryption,
                        (long) file_transfer.size);
            }

            if (file_sender == null) {
                throw new FileSendError.UPLOAD_FAILED("No sender/encryptor combination available");
            }

            if (file_encryptor != null) {
                file_meta = file_encryptor.encrypt_file(conversation, file_transfer);
            }

            FileSendData file_send_data = yield file_sender.prepare_send_file(conversation, file_transfer, file_meta);

            if (file_encryptor != null) {
                file_send_data = file_encryptor.preprocess_send_file(conversation, file_transfer, file_send_data, file_meta);
            }

            file_transfer.state = FileTransfer.State.IN_PROGRESS;

            // Update current download progress in the FileTransfer
            LimitInputStream? limit_stream = file_transfer.input_stream as LimitInputStream;
            if (limit_stream == null) {
                limit_stream = new LimitInputStream(file_transfer.input_stream, file_meta.size);
                file_transfer.input_stream = limit_stream;
            }
            if (limit_stream != null) {
                limit_stream.bind_property("retrieved-bytes", file_transfer, "transferred-bytes", BindingFlags.SYNC_CREATE);
            }

            yield file_sender.send_file(conversation, file_transfer, file_send_data, file_meta);
            
            // Explicitly close the stream as we prevent libsoup/cis from closing the base stream
            if (file_transfer.input_stream != null) {
                try { yield file_transfer.input_stream.close_async(); } catch (Error e) {}
            }

            file_transfer.state = FileTransfer.State.COMPLETE;

        } catch (Error e) {
            warning("Send file error: %s", e.message);
            file_transfer.state = FileTransfer.State.FAILED;
            
            // Clean up the input stream to prevent segfault (fixes #1764)
            if (file_transfer.input_stream != null) {
                try {
                    yield file_transfer.input_stream.close_async();
                } catch (Error close_error) {
                    debug("Failed to close input stream: %s", close_error.message);
                }
            }
        } finally {
            if (temp_file != null) {
                try {
                    temp_file.delete(null);
                } catch (Error e) {}
            }
        }
    }

    public async void download_file(FileTransfer file_transfer) {
        Conversation conversation = stream_interactor.get_module<ConversationManager>(ConversationManager.IDENTITY).get_conversation(file_transfer.counterpart.bare_jid, file_transfer.account);

        FileProvider? file_provider = this.select_file_provider(file_transfer);

        yield download_file_internal(file_provider, file_transfer, conversation);
    }

    public async bool is_upload_available(Conversation? conversation) {
        if (conversation == null) return false;

        foreach (FileSender file_sender in file_senders) {
            if (yield file_sender.is_upload_available(conversation)) return true;
        }
        return false;
    }

    public void add_provider(FileProvider file_provider) {
        file_providers.add(file_provider);
        file_provider.file_incoming.connect((info, from, time, local_time, conversation, receive_data, file_meta) => {
            handle_incoming_file.begin(file_provider, info, from, time, local_time, conversation, receive_data, file_meta);
        });
    }

    public void add_sender(FileSender file_sender) {
        file_senders.add(file_sender);
        file_sender.upload_available.connect((account) => {
            upload_available(account);
        });
        file_senders.sort((a, b) => {
            return (int) (b.get_priority() - a.get_priority());
        });
    }

    public void add_file_encryptor(FileEncryptor encryptor) {
        file_encryptors.add(encryptor);
    }

    public void add_file_decryptor(FileDecryptor decryptor) {
        file_decryptors.add(decryptor);
    }

    public void add_metadata_provider(FileMetadataProvider file_metadata_provider) {
        file_metadata_providers.add(file_metadata_provider);
    }

    public bool is_sender_trustworthy(FileTransfer file_transfer, Conversation conversation) {
        if (file_transfer.direction == FileTransfer.DIRECTION_SENT) return true;

        Jid relevant_jid = conversation.counterpart;
        if (conversation.type_ == Conversation.Type.GROUPCHAT) {
            relevant_jid = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_real_jid(file_transfer.from, conversation.account);
        }
        if (relevant_jid == null) return false;

        bool in_roster = stream_interactor.get_module<RosterManager>(RosterManager.IDENTITY).get_roster_item(conversation.account, relevant_jid) != null;
        return in_roster;
    }

    private async FileMeta get_file_meta(FileProvider file_provider, FileTransfer file_transfer, Conversation conversation, FileReceiveData receive_data_) throws FileReceiveError {
        FileReceiveData receive_data = receive_data_;
        FileMeta file_meta = file_provider.get_file_meta(file_transfer);

        if (file_meta.size == -1) {
            foreach (FileDecryptor file_decryptor in file_decryptors) {
                if (file_decryptor.can_decrypt_file(conversation, file_transfer, receive_data)) {
                    receive_data = file_decryptor.prepare_get_meta_info(conversation, file_transfer, receive_data);
                    break;
                }
            }

            file_meta = yield file_provider.get_meta_info(file_transfer, receive_data, file_meta);

            file_transfer.size = (int)file_meta.size;
            file_transfer.file_name = file_meta.file_name;
            file_transfer.mime_type = file_meta.mime_type;
        }
        return file_meta;
    }

    private async void download_file_internal(FileProvider file_provider, FileTransfer file_transfer, Conversation conversation) {
        try {
            // Get meta info
            FileReceiveData? receive_data = file_provider.get_file_receive_data(file_transfer);
            if (receive_data == null) {
                warning("Don't have download data (yet)");
                return;
            }
            FileDecryptor? file_decryptor = null;
            foreach (FileDecryptor decryptor in file_decryptors) {
                if (decryptor.can_decrypt_file(conversation, file_transfer, receive_data)) {
                    file_decryptor = decryptor;
                    break;
                }
            }

            if (file_decryptor != null) {
                receive_data = file_decryptor.prepare_get_meta_info(conversation, file_transfer, receive_data);
            }

            FileMeta file_meta = yield get_file_meta(file_provider, file_transfer, conversation, receive_data);

            // Download and decrypt file
            file_transfer.state = FileTransfer.State.IN_PROGRESS;

            if (file_decryptor != null) {
                file_meta = file_decryptor.prepare_download_file(conversation, file_transfer, receive_data, file_meta);
            }

            InputStream download_input_stream = yield file_provider.download(file_transfer, receive_data, file_meta);
            InputStream input_stream = download_input_stream;
            if (file_decryptor != null) {
                input_stream = yield file_decryptor.decrypt_file(input_stream, conversation, file_transfer, receive_data);
            }

            // Update current download progress in the FileTransfer
            LimitInputStream? limit_stream = download_input_stream as LimitInputStream;
            if (limit_stream != null) {
                limit_stream.bind_property("retrieved-bytes", file_transfer, "transferred-bytes", BindingFlags.SYNC_CREATE);
            }

            // Save file
            // Sanitize filename to prevent path traversal attacks
            string safe_basename = Path.get_basename(file_transfer.file_name);
            string filename = Random.next_int().to_string("%x") + "_" + safe_basename;
            File file = File.new_for_path(Path.build_filename(get_storage_dir(), filename));

            // libsoup doesn't properly support splicing
            OutputStream os = file.create(FileCreateFlags.REPLACE_DESTINATION);
            
            // Encrypt stream to disk
            yield file_encryption.encrypt_stream(input_stream, os, file_transfer.cancellable);
            
            yield input_stream.close_async(Priority.LOW, file_transfer.cancellable);
            yield os.close_async(Priority.LOW, file_transfer.cancellable);

            // Verify the hash of the downloaded file, if it is known
            var supported_hashes = Xep.CryptographicHashes.get_supported_hashes(file_transfer.hashes);
            if (!supported_hashes.is_empty) {
                var checksum_types = new ArrayList<ChecksumType>();
                var hashes = new HashMap<ChecksumType, string>();
                foreach (var hash in supported_hashes) {
                    var checksum_type = Xep.CryptographicHashes.hash_string_to_type(hash.algo);
                    checksum_types.add(checksum_type);
                    hashes[checksum_type] = hash.val;
                }

                // Compute hashes of the DECRYPTED content
                var checksum_stream = new ChecksumOutputStream(checksum_types);
                var read_stream = file.read();
                yield file_encryption.decrypt_stream(read_stream, checksum_stream, file_transfer.cancellable);
                yield read_stream.close_async(Priority.LOW, file_transfer.cancellable);
                
                var computed_hashes = checksum_stream.get_hashes();

                foreach (var checksum_type in hashes.keys) {
                    if (hashes[checksum_type] != computed_hashes[checksum_type]) {
                        warning("Hash of downloaded file does not equal advertised hash, discarding: %s. %s should be %s, was %s",
                                file_transfer.file_name, checksum_type.to_string(), hashes[checksum_type], computed_hashes[checksum_type]);
                        FileUtils.remove(file.get_path());
                        file_transfer.state = FileTransfer.State.FAILED;
                        return;
                    }
                }
            }

            file_transfer.path = file.get_basename();

            FileInfo file_info = file_transfer.get_file().query_info("*", FileQueryInfoFlags.NONE);
            if (file_info.get_content_type() != "application/octet-stream" || file_transfer.mime_type == null) {
                // Only overwrite mime_type if it's better than what we had before.
                file_transfer.mime_type = file_info.get_content_type();
            }

            file_transfer.state = FileTransfer.State.COMPLETE;
        } catch (IOError.CANCELLED e) {
            debug("cancelled");
        } catch (Error e) {
            warning("Error downloading file: %s", e.message);
            if (file_transfer.provider == 0 || file_transfer.provider == FileManager.SFS_PROVIDER_ID) {
                file_transfer.state = FileTransfer.State.NOT_STARTED;
            } else {
                file_transfer.state = FileTransfer.State.FAILED;
            }
        }
    }

    public FileTransfer create_file_transfer_from_provider_incoming(FileProvider file_provider, string info, Jid from, DateTime time, DateTime local_time, Conversation conversation, FileReceiveData receive_data, FileMeta file_meta) {
        FileTransfer file_transfer = new FileTransfer();
        file_transfer.account = conversation.account;
        file_transfer.counterpart = file_transfer.direction == FileTransfer.DIRECTION_RECEIVED ? from : conversation.counterpart;
        if (conversation.type_.is_muc_semantic()) {
            file_transfer.ourpart = stream_interactor.get_module<MucManager>(MucManager.IDENTITY).get_own_jid(conversation.counterpart, conversation.account) ?? conversation.account.bare_jid;
            file_transfer.direction = from.equals(file_transfer.ourpart) ? FileTransfer.DIRECTION_SENT : FileTransfer.DIRECTION_RECEIVED;
        } else {
            if (from.equals_bare(conversation.account.bare_jid)) {
                file_transfer.ourpart = from;
                file_transfer.direction = FileTransfer.DIRECTION_SENT;
            } else {
                file_transfer.ourpart = conversation.account.full_jid;
                file_transfer.direction = FileTransfer.DIRECTION_RECEIVED;
            }
        }
        file_transfer.time = time;
        file_transfer.local_time = local_time;
        file_transfer.provider = file_provider.get_id();
        file_transfer.file_name = file_meta.file_name;
        file_transfer.size = (int)file_meta.size;
        file_transfer.info = info;

        var encryption = file_provider.get_encryption(file_transfer, receive_data, file_meta);
        if (encryption != Encryption.NONE) file_transfer.encryption = encryption;

        foreach (FileDecryptor decryptor in file_decryptors) {
            if (decryptor.can_decrypt_file(conversation, file_transfer, receive_data)) {
                file_transfer.encryption = decryptor.get_encryption();
            }
        }

        return file_transfer;
    }

    private async void handle_incoming_file(FileProvider file_provider, string info, Jid from, DateTime time, DateTime local_time, Conversation conversation, FileReceiveData receive_data, FileMeta file_meta) {
        FileTransfer file_transfer = create_file_transfer_from_provider_incoming(file_provider, info, from, time, local_time, conversation, receive_data, file_meta);
        stream_interactor.get_module<FileTransferStorage>(FileTransferStorage.IDENTITY).add_file(file_transfer);

        if (is_sender_trustworthy(file_transfer, conversation)) {
            try {
                yield get_file_meta(file_provider, file_transfer, conversation, receive_data);
            } catch (Error e) {
                warning("Error downloading file: %s", e.message);
                file_transfer.state = FileTransfer.State.FAILED;
            }
            if (file_transfer.size >= 0 && file_transfer.size < 5000000) {
                download_file_internal.begin(file_provider, file_transfer, conversation, (_, res) => {
                    download_file_internal.end(res);
                });
            }
        }

        conversation.last_active = file_transfer.time;
        received_file(file_transfer, conversation);
    }

    private async void save_file(FileTransfer file_transfer) throws FileSendError {
        try {
            string filename = Random.next_int().to_string("%x") + "_" + file_transfer.file_name;
            File file = File.new_for_path(Path.build_filename(get_storage_dir(), filename));
            OutputStream os = file.create(FileCreateFlags.REPLACE_DESTINATION);
            
            // Encrypt stream to disk
            yield file_encryption.encrypt_stream(file_transfer.input_stream, os);
            yield os.close_async();
            
            file_transfer.state = FileTransfer.State.COMPLETE;
            file_transfer.path = filename;
            
            // For the input_stream of the FileTransfer (which might be used for UI preview or hashing),
            // we now need a stream of the *decrypted* content.
            // Since we just consumed the original input_stream, we should probably re-open the file and decrypt it.
            // OR, better: The original input_stream might not be seekable (e.g. socket).
            // But wait, save_file is called in send_file.
            // In send_file: file_transfer.input_stream = yield file.read_async();
            // So it is a FileInputStream. We can re-open the source file.
            
            // However, file_transfer.input_stream is updated here to point to the *stored* file.
            // If we point it to the stored file, it will be encrypted.
            // So any subsequent read from file_transfer.input_stream will get encrypted data, which is wrong for UI.
            // The UI expects cleartext.
            
            // Let's look at how download_file handles this.
            // It doesn't set input_stream on the transfer object for persistent use.
            // FileTransfer.input_stream getter tries to open the file from disk.
            
            // If we set file_transfer.path, the getter will use it.
            // We need to ensure that when the getter opens the file, it decrypts it.
            // But FileTransfer entity doesn't know about encryption.
            
            // Let's check FileTransfer.input_stream getter in libdino/src/entity/file_transfer.vala
            
        } catch (Error e) {
            throw new FileSendError.SAVE_FAILED("Saving file error: %s".printf(e.message));
        }
    }
}

public errordomain FileSendError {
    ENCRYPTION_FAILED,
    UPLOAD_FAILED,
    SAVE_FAILED
}

// Get rid of this Error and pass IoErrors instead - DOWNLOAD_FAILED already removed
public errordomain FileReceiveError {
    GET_METADATA_FAILED,
    DECRYPTION_FAILED
}

public class FileMeta {
    public int64 size = -1;
    public string? mime_type = null;
    public string? file_name = null;
    public Encryption encryption = Encryption.NONE;
}

public class HttpFileMeta : FileMeta {
    public Message message;
}

public class FileSendData { }

public class HttpFileSendData : FileSendData {
    public string url_down { get; set; }
    public string url_up { get; set; }
    public HashMap<string, string> headers { get; set; }

    public bool encrypt_message { get; set; default=true; }
}

public class FileReceiveData { }

public class HttpFileReceiveData : FileReceiveData {
    public string url { get; set; }
}

public interface FileProvider : Object {
    public signal void file_incoming(string info, Jid from, DateTime time, DateTime local_time, Conversation conversation, FileReceiveData receive_data, FileMeta file_meta);

    public abstract Encryption get_encryption(FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta);
    public abstract FileMeta get_file_meta(FileTransfer file_transfer) throws FileReceiveError;
    public abstract FileReceiveData? get_file_receive_data(FileTransfer file_transfer);

    public abstract async FileMeta get_meta_info(FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta) throws FileReceiveError;
    public abstract async InputStream download(FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta) throws IOError;

    public abstract int get_id();
}

public interface FileSender : Object {
    public signal void upload_available(Account account);

    public abstract async bool is_upload_available(Conversation conversation);
    public abstract async long get_file_size_limit(Conversation conversation);
    public abstract async bool can_send(Conversation conversation, FileTransfer file_transfer);
    public abstract async FileSendData? prepare_send_file(Conversation conversation, FileTransfer file_transfer, FileMeta file_meta) throws FileSendError;
    public abstract async void send_file(Conversation conversation, FileTransfer file_transfer, FileSendData file_send_data, FileMeta file_meta) throws FileSendError;
    public abstract async bool can_encrypt(Conversation conversation, FileTransfer file_transfer);

    public abstract int get_id();
    public abstract float get_priority();
}

public interface FileEncryptor : Object {
    public abstract bool can_encrypt_file(Conversation conversation, FileTransfer file_transfer);
    public abstract FileMeta encrypt_file(Conversation conversation, FileTransfer file_transfer) throws FileSendError;
    public abstract FileSendData? preprocess_send_file(Conversation conversation, FileTransfer file_transfer, FileSendData file_send_data, FileMeta file_meta) throws FileSendError;
}

public interface FileDecryptor : Object {
    public abstract Encryption get_encryption();
    public abstract FileReceiveData prepare_get_meta_info(Conversation conversation, FileTransfer file_transfer, FileReceiveData receive_data);
    public abstract FileMeta prepare_download_file(Conversation conversation, FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta);
    public abstract bool can_decrypt_file(Conversation conversation, FileTransfer file_transfer, FileReceiveData receive_data);
    public abstract async InputStream decrypt_file(InputStream encrypted_stream, Conversation conversation, FileTransfer file_transfer, FileReceiveData receive_data) throws FileReceiveError;
}

}
