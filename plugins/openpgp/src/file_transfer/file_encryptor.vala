using Dino.Entities;

namespace Dino.Plugins.OpenPgp {

public class PgpFileEncryptor : Dino.FileEncryptor, Object {

    StreamInteractor stream_interactor;

    public PgpFileEncryptor(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
    }

    public bool can_encrypt_file(Conversation conversation, FileTransfer file_transfer) {
        return conversation.encryption == Encryption.PGP;
    }

    public FileMeta encrypt_file(Conversation conversation, FileTransfer file_transfer) throws FileSendError {
        FileMeta file_meta = new FileMeta();

        try {
            GPGHelper.Key[] keys = stream_interactor.get_module<Manager>(Manager.IDENTITY).get_key_fprs(conversation);

            // Read from input_stream (the original file), not from get_file()
            // because get_file() returns the disk-encrypted local copy.
            string temp_in = Path.build_filename(Environment.get_tmp_dir(),
                "dinox-pgp-in-%d".printf(GLib.Random.int_range(0, 1000000)));
            {
                var temp_file = File.new_for_path(temp_in);
                var os = temp_file.create(FileCreateFlags.PRIVATE);
                uint8[] buf = new uint8[8192];
                ssize_t read_bytes;
                while ((read_bytes = file_transfer.input_stream.read(buf)) > 0) {
                    os.write(buf[0:read_bytes]);
                }
                os.close();
            }

            uint8[] enc_content = GPGHelper.encrypt_file(temp_in, keys, 0, file_transfer.file_name);
            GPGHelper.secure_delete_file(temp_in);

            file_transfer.input_stream = new MemoryInputStream.from_data(enc_content, GLib.free);
            // Set encryption to NONE so that HttpFileSender.prepare_send_file()
            // creates a plain HttpFileSendData (no AES-GCM key/iv, correct size).
            // The file content is already GPG-encrypted; the message body will
            // be PGP-encrypted via encrypt_message = true in preprocess_send_file().
            file_transfer.encryption = Encryption.NONE;
            // Keep original filename + ".pgp" so receiving clients know the file type
            // e.g. "photo.jpg.pgp" → strip .pgp → display as JPEG
            string base_name = file_transfer.file_name ?? Xmpp.random_uuid();
            file_transfer.server_file_name = base_name + ".pgp";
            file_meta.size = enc_content.length;
            file_meta.mime_type = "application/pgp-encrypted";
        } catch (Error e) {
            throw new FileSendError.ENCRYPTION_FAILED("PGP file encryption error: %s".printf(e.message));
        }
        debug("PgpFileEncryptor: encrypted %s -> %s (%lld bytes)", file_transfer.file_name, file_transfer.server_file_name, file_meta.size);

        return file_meta;
    }

    public FileSendData? preprocess_send_file(Conversation conversation, FileTransfer file_transfer, FileSendData file_send_data, FileMeta file_meta) {
        HttpFileSendData? send_data = file_send_data as HttpFileSendData;
        if (send_data == null) return null;

        // Restore encryption to PGP (was set to NONE in encrypt_file() to prevent
        // AES-GCM wrapping). The message containing the download URL must be
        // PGP-encrypted so the URL is not transmitted in cleartext.
        file_transfer.encryption = Encryption.PGP;
        send_data.encrypt_message = true;
        return file_send_data;
    }
}

}
