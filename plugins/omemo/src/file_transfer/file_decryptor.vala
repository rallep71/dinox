using Dino.Entities;

using Crypto;
using Omemo;

namespace Dino.Plugins.Omemo {

public class OmemoHttpFileReceiveData : HttpFileReceiveData {
  public string original_url;
}

public class OmemoFileDecryptor : FileDecryptor, Object {

  private const uint KEY_SIZE = 32;

  // Historically Dino expected the iv+key fragment to be hex. Some clients (e.g. Conversations)
  // may use different encodings (base64 or url-safe base64). We therefore only validate the
  // scheme/fragment structure and decode the secret more flexibly.
  private Regex url_regex = /^aesgcm:\/\/([^\s#]+)#([^\s]+)$/; // vala-lint=space-before-paren

  public Encryption get_encryption () {
    return Encryption.OMEMO;
  }

  public FileReceiveData prepare_get_meta_info (Conversation conversation, FileTransfer file_transfer, FileReceiveData receive_data) {
    // ESFS data is already ready -- URL is https://, key/iv are stored
    if ((receive_data as EsfsHttpFileReceiveData) != null) return receive_data;

    HttpFileReceiveData? http_receive_data = receive_data as HttpFileReceiveData;
    if (http_receive_data == null) {
      warning ("OMEMO: prepare_get_meta_info called with non-HTTP receive data");
      return receive_data;
    }
    if ((receive_data as OmemoHttpFileReceiveData) != null) return receive_data;

    var omemo_http_receive_data = new OmemoHttpFileReceiveData ();
    omemo_http_receive_data.url = aesgcm_to_https_link (http_receive_data.url);
    omemo_http_receive_data.original_url = http_receive_data.url;

    return omemo_http_receive_data;
  }

  public FileMeta prepare_download_file (Conversation conversation, FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta) {
    if (file_meta.file_name != null) {
      file_meta.file_name = file_meta.file_name.split ("#")[0];
    }
    return file_meta;
  }

  public bool can_decrypt_file (Conversation conversation, FileTransfer file_transfer, FileReceiveData receive_data) {
    // ESFS encrypted transfers (XEP-0448)
    if ((receive_data as EsfsHttpFileReceiveData) != null) return true;

    HttpFileReceiveData? http_file_receive = receive_data as HttpFileReceiveData;
    if (http_file_receive == null) return false;

    if ((receive_data as OmemoHttpFileReceiveData) != null) return true;
    return this.url_regex.match (http_file_receive.url);
  }

  public async InputStream decrypt_file (InputStream encrypted_stream, Conversation conversation, FileTransfer file_transfer, FileReceiveData receive_data) throws FileReceiveError {
    try {
      // ESFS (XEP-0448) decryption -- key/iv from SFS metadata
      EsfsHttpFileReceiveData? esfs_data = receive_data as EsfsHttpFileReceiveData;
      if (esfs_data != null) {
        if (file_transfer.encryption == Encryption.NONE) {
          file_transfer.encryption = Encryption.OMEMO;
        }
        debug ("ESFS: Decrypting file %s cipher=%s key_len=%d iv_len=%d",
               file_transfer.file_name, esfs_data.esfs_cipher,
               esfs_data.esfs_key.length, esfs_data.esfs_iv.length);
        return decrypt_esfs_stream (encrypted_stream, esfs_data);
      }

      // Legacy aesgcm:// decryption
      OmemoHttpFileReceiveData? omemo_http_receive_data = receive_data as OmemoHttpFileReceiveData;
      if (omemo_http_receive_data == null) {
          throw new FileReceiveError.DECRYPTION_FAILED ("Missing OMEMO receive data");
      }

      uint8[] iv;
      uint8[] key;
      if (!try_extract_iv_and_key (omemo_http_receive_data.original_url, out iv, out key)) {
        throw new FileReceiveError.DECRYPTION_FAILED ("Unsupported aesgcm:// secret encoding");
      }

      // Only set encryption if not already determined by the file provider
      // (e.g. PGP conversations also use aesgcm:// for file transport)
      if (file_transfer.encryption == Encryption.NONE) {
          file_transfer.encryption = Encryption.OMEMO;
      }
      debug ("Decrypting file %s from %s (encryption=%d)", file_transfer.file_name, file_transfer.server_file_name, (int) file_transfer.encryption);

      SymmetricCipher cipher = new SymmetricCipher ("AES-GCM");
      cipher.set_key (key);
      cipher.set_iv (iv);
      return new ConverterInputStream (encrypted_stream, new SymmetricCipherDecrypter ((owned) cipher, 16));

    } catch (GLib.Error e) {
      throw new FileReceiveError.DECRYPTION_FAILED ("OMEMO file decryption error: %s".printf (e.message));
    }
  }

  private bool try_extract_iv_and_key (string aesgcm_link, out uint8[] iv, out uint8[] key) {
    iv = new uint8[0];
    key = new uint8[0];

    MatchInfo match_info;
    if (!this.url_regex.match (aesgcm_link, 0, out match_info)) {
      return false;
    }

    string secret = match_info.fetch (2);
    uint8[] iv_and_key;
    if (!try_decode_secret (secret, out iv_and_key)) {
      return false;
    }

    // Supported layouts: iv(12)+key(32)=44 bytes, iv(16)+key(32)=48 bytes.
    if (iv_and_key.length != 44 && iv_and_key.length != 48) {
      return false;
    }
    if (iv_and_key.length <= KEY_SIZE) {
      return false;
    }

    iv = iv_and_key[0:iv_and_key.length - KEY_SIZE];
    key = iv_and_key[iv_and_key.length - KEY_SIZE:iv_and_key.length];
    return true;
  }

  private bool try_decode_secret (string secret, out uint8[] bytes) {
    bytes = new uint8[0];

    // Fast path: hex (legacy)
    if (is_hex (secret) && (secret.length % 2) == 0) {
      bytes = hex_to_bin (secret.up ());
      return true;
    }

    // Fallback: base64 / url-safe base64 (common in other clients)
    string normalized = normalize_base64 (secret);
    bytes = Base64.decode (normalized);
    return bytes.length > 0;
  }

  private bool is_hex (string s) {
    for (int i = 0; i < s.length; i++) {
      unichar c = s.get_char (i);
      bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
      if (!ok) return false;
    }
    return s.length > 0;
  }

  private uint8[] hex_to_bin (string hex) {
    uint8[] bin = new uint8[hex.length / 2];
    const string HEX = "0123456789ABCDEF";
    for (int i = 0; i < hex.length / 2; i++) {
      bin[i] = (uint8) (HEX.index_of_char (hex[i * 2]) << 4) | HEX.index_of_char (hex[i * 2 + 1]);
    }
    return bin;
  }

  private string normalize_base64 (string input) {
    // Convert url-safe base64 to standard base64 and add padding.
    string s = input.replace ("-", "+").replace ("_", "/");
    int rem = s.length % 4;
    if (rem == 2) s += "==";
    else if (rem == 3) s += "=";
    else if (rem != 0) {
      // Invalid base64 length
      return input;
    }
    return s;
  }

  private string aesgcm_to_https_link (string aesgcm_link) {
    MatchInfo match_info;
    if (!this.url_regex.match (aesgcm_link, 0, out match_info)) {
      return aesgcm_link;
    }
    return "https://" + match_info.fetch (1);
  }

  /**
   * Decrypt an ESFS (XEP-0448) encrypted file stream.
   * Supports aes-256-cbc-pkcs7 (Kaidan) and aes-256-gcm-nopadding (DinoX).
   */
  private InputStream decrypt_esfs_stream (InputStream encrypted_stream, EsfsHttpFileReceiveData esfs_data) throws GLib.Error {
    uint8[] key = esfs_data.esfs_key;
    uint8[] iv = esfs_data.esfs_iv;
    string cipher_uri = esfs_data.esfs_cipher;

    if (cipher_uri.contains ("aes-256-cbc-pkcs7") || cipher_uri.contains ("aes-256-cbc")) {
      // AES-256-CBC with PKCS7 padding
      // AES block size is 16 bytes, so IV must be 16 bytes
      uint8[] cbc_iv = iv;
      if (iv.length > 16) {
        cbc_iv = iv[0:16];
        debug ("ESFS: Truncating CBC IV from %d to 16 bytes", iv.length);
      }

      // Read entire ciphertext, decrypt with CBC, output decrypted stream
      // Since SymmetricCipherDecrypter expects streaming but CBC-PKCS7 needs
      // the full data for padding removal, we read all and decrypt in one shot.
      var buffer = new GLib.ByteArray ();
      uint8[] chunk = new uint8[65536];
      while (true) {
        ssize_t n = encrypted_stream.read (chunk);
        if (n <= 0) break;
        buffer.append (chunk[0:n]);
      }

      uint8[] plaintext;
      size_t plaintext_len;
      int rc = omemo2_aes_256_cbc_pkcs7_decrypt (out plaintext, out plaintext_len,
          key, cbc_iv, buffer.data);
      if (rc != 0) {
        throw new GLib.Error (Quark.from_string ("esfs"), 1,
            "ESFS AES-256-CBC-PKCS7 decryption failed (rc=%d)", rc);
      }
      plaintext.length = (int) plaintext_len;
      debug ("ESFS: CBC decrypted %u bytes -> %zu bytes", buffer.len, plaintext_len);
      return new MemoryInputStream.from_data (plaintext);

    } else if (cipher_uri.contains ("aes-256-gcm")) {
      // AES-256-GCM: Kaidan/QXmpp may not append auth tag, so taglen=0 for interop.
      // This means ciphertext is NOT authenticated -- log a warning.
      warning ("ESFS: GCM decryption without auth tag verification (interop mode)");
      SymmetricCipher cipher = new SymmetricCipher ("AES256-GCM");
      cipher.set_key (key);
      cipher.set_iv (iv);
      return new ConverterInputStream (encrypted_stream, new SymmetricCipherDecrypter ((owned) cipher, 0));

    } else {
      throw new GLib.Error (Quark.from_string ("esfs"), 2,
          "ESFS: Unsupported or missing cipher: %s", cipher_uri);
    }
  }
}

}
