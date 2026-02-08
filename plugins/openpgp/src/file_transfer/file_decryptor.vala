using Dino.Entities;

namespace Dino.Plugins.OpenPgp {

public class PgpFileDecryptor : FileDecryptor, Object {

    public Encryption get_encryption() {
        return Encryption.PGP;
    }

    public FileReceiveData prepare_get_meta_info(Conversation conversation, FileTransfer file_transfer, FileReceiveData receive_data) {
        return receive_data;
    }

    public FileMeta prepare_download_file(Conversation conversation, FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta) {
        return file_meta;
    }

    public bool can_decrypt_file(Conversation conversation, FileTransfer file_transfer, FileReceiveData receive_data) {
        return file_transfer.file_name.has_suffix("pgp") || file_transfer.mime_type == "application/pgp-encrypted";
    }

    public async InputStream decrypt_file(InputStream encrypted_stream, Conversation conversation, FileTransfer file_transfer, FileReceiveData receive_data) throws FileReceiveError {
        try {
            uint8[] buf = new uint8[256];
            ByteArray data = new ByteArray();
            size_t len = -1;
            do {
                len = yield encrypted_stream.read_async(buf);
                data.append(buf[0:len]);
            } while(len > 0);

            GPGHelper.DecryptedData clear_data = GPGHelper.decrypt_data(data.data);
            if (file_transfer.encryption == Encryption.NONE) {
                file_transfer.encryption = Encryption.PGP;
            }
            if (clear_data.filename != null && clear_data.filename != "") {
                debug("Decrypting file %s from %s", clear_data.filename, file_transfer.file_name);
                file_transfer.file_name = clear_data.filename;
            } else if (file_transfer.file_name.has_suffix(".pgp")) {
                debug("Decrypting file %s from %s", file_transfer.file_name.substring(0, file_transfer.file_name.length - 4), file_transfer.file_name);
                file_transfer.file_name = file_transfer.file_name.substring(0, file_transfer.file_name.length - 4);
            }

            // Update mime type based on the actual (decrypted) filename so the UI
            // can display images/videos inline instead of showing a generic file icon.
            bool uncertain;
            string? guessed_type = ContentType.guess(file_transfer.file_name, null, out uncertain);
            if (guessed_type != null && guessed_type != "application/octet-stream") {
                file_transfer.mime_type = guessed_type;
            }

            return new MemoryInputStream.from_data(clear_data.data, GLib.free);
        } catch (Error e) {
            throw new FileReceiveError.DECRYPTION_FAILED("PGP file decryption error: %s".printf(e.message));
        }
    }
}

}
