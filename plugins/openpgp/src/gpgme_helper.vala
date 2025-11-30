using Gee;
using GPG;

namespace GPGHelper {

private static bool initialized = false;

public static string encrypt_armor(string plain, Key[] keys, EncryptFlags flags) throws GLib.Error {
    global_mutex.lock();
    try {
        initialize();
        Data plain_data = Data.create_from_memory(plain.data, false);
        Context context = Context.create();
        context.set_armor(true);
        Data enc_data = context.op_encrypt(keys, flags, plain_data);
        return get_string_from_data(enc_data);
    } finally {
        global_mutex.unlock();
    }
}

public static uint8[] encrypt_file(string uri, Key[] keys, EncryptFlags flags, string file_name) throws GLib.Error {
    global_mutex.lock();
    try {
        initialize();
        Data plain_data = Data.create_from_file(uri);
        plain_data.set_file_name(file_name);
        Context context = Context.create();
        context.set_armor(true);
        Data enc_data = context.op_encrypt(keys, flags, plain_data);
        return get_uint8_from_data(enc_data);
    } finally {
        global_mutex.unlock();
    }
}

public static string decrypt(string encr) throws GLib.Error {
    global_mutex.lock();
    try {
        initialize();
        Data enc_data = Data.create_from_memory(encr.data, false);
        Context context = Context.create();
        Data dec_data = context.op_decrypt(enc_data);
        return get_string_from_data(dec_data);
    } finally {
        global_mutex.unlock();
    }
}

public class DecryptedData {
    public uint8[] data { get; set; }
    public string filename { get; set; }
}

public static DecryptedData decrypt_data(uint8[] data) throws GLib.Error {
    global_mutex.lock();
    try {
        initialize();
        Data enc_data = Data.create_from_memory(data, false);
        Context context = Context.create();
        Data dec_data = context.op_decrypt(enc_data);
        DecryptResult* dec_res = context.op_decrypt_result();
        return new DecryptedData() { data=get_uint8_from_data(dec_data), filename=dec_res->file_name};
    } finally {
        global_mutex.unlock();
    }
}

public static string sign(string plain, SigMode mode, Key? key = null) throws GLib.Error {
    global_mutex.lock();
    try {
        initialize();
        Data plain_data = Data.create_from_memory(plain.data, false);
        Context context = Context.create();
        if (key != null) context.signers_add(key);
        Data signed_data = context.op_sign(plain_data, mode);
        return get_string_from_data(signed_data);
    } finally {
        global_mutex.unlock();
    }
}

public static string? get_sign_key(string signature, string? text) throws GLib.Error {
    global_mutex.lock();
    try {
        initialize();
        Data sig_data = Data.create_from_memory(signature.data, false);
        Data text_data;
        if (text != null) {
            text_data = Data.create_from_memory(text.data, false);
        } else {
            text_data = Data.create();
        }
        Context context = Context.create();
        context.op_verify(sig_data, text_data);
        VerifyResult* verify_res = context.op_verify_result();
        if (verify_res == null || verify_res.signatures == null) return null;
        return verify_res.signatures.fpr;
    } finally {
        global_mutex.unlock();
    }
}

public static Gee.List<Key> get_keylist(string? pattern = null, bool secret_only = false) throws GLib.Error {
    global_mutex.lock();
    try {
        initialize();

        Gee.List<Key> keys = new ArrayList<Key>();
        Context context = Context.create();
        
        // First get fingerprints using gpg command (more reliable)
        Gee.List<string> fingerprints = new ArrayList<string>();
        try {
            string[] argv;
            if (secret_only) {
                argv = { "gpg", "--list-secret-keys", "--with-colons" };
            } else {
                argv = { "gpg", "--list-keys", "--with-colons" };
            }
            if (pattern != null) {
                argv += pattern;
            }
            
            string stdout_str, stderr_str;
            int exit_status;
            Process.spawn_sync(null, argv, null, SpawnFlags.SEARCH_PATH,
                null, out stdout_str, out stderr_str, out exit_status);
            
            if (exit_status == 0) {
                bool expect_main_fpr = false;  // Only collect fpr after sec:/pub:, not after ssb:/sub:
                foreach (string line in stdout_str.split("\n")) {
                    if (line.has_prefix("sec:") || line.has_prefix("pub:")) {
                        // Main key - next fpr line is what we want
                        expect_main_fpr = true;
                    } else if (line.has_prefix("ssb:") || line.has_prefix("sub:")) {
                        // Subkey - ignore its fpr
                        expect_main_fpr = false;
                    } else if (line.has_prefix("fpr:") && expect_main_fpr) {
                        var parts = line.split(":");
                        if (parts.length > 9 && parts[9].length > 0) {
                            fingerprints.add(parts[9]);
                            expect_main_fpr = false;  // Only take first fpr after sec:/pub:
                        }
                    }
                }
            }
        } catch (Error e) {
            warning("Error getting key list from gpg: %s", e.message);
            // Fallback to GPGME
            context.op_keylist_start(pattern, secret_only ? 1 : 0);
            try {
                while (true) {
                    Key key = context.op_keylist_next();
                    fingerprints.add(key.fpr);
                }
            } catch (Error e2) {
                if (e2.code != GPGError.ErrorCode.EOF) throw e2;
            }
            context.op_keylist_end();
        }
        
        // Now get full key data for each fingerprint
        foreach (string fpr in fingerprints) {
            try {
                Key full_key = context.get_key(fpr, secret_only);
                keys.add(full_key);
            } catch (Error e) {
                warning("Could not load key %s: %s", fpr, e.message);
            }
        }
        
        return keys;
    } finally {
        global_mutex.unlock();
    }
}

public static Key? get_public_key(string sig) throws GLib.Error {
    return get_key(sig, false);
}

public static Key? get_private_key(string sig) throws GLib.Error {
    return get_key(sig, true);
}

private static Key? get_key(string sig, bool priv) throws GLib.Error {
    global_mutex.lock();
    try {
        initialize();
        Context context = Context.create();
        Key key = context.get_key(sig, priv);
        return key;
    } finally {
        global_mutex.unlock();
    }
}

private static string get_string_from_data(Data data) {
    const size_t BUF_SIZE = 256;
    data.seek(0);
    uint8[] buf = new uint8[BUF_SIZE + 1];
    ssize_t len = 0;
    string res = "";
    do {
        len = data.read(buf, BUF_SIZE);
        if (len > 0) {
            buf[len] = 0;
            res += (string) buf;
        }
    } while (len > 0);
    return res;
}

private static uint8[] get_uint8_from_data(Data data) {
    const size_t BUF_SIZE = 256;
    data.seek(0);
    uint8[] buf = new uint8[BUF_SIZE + 1];
    ssize_t len = 0;
    ByteArray res = new ByteArray();
    do {
        len = data.read(buf, BUF_SIZE);
        if (len > 0) {
            res.append(buf[0:len]);
        }
    } while (len > 0);
    return res.data;
}

private static void initialize() {
    if (!initialized) {
        check_version();
        initialized = true;
    }
}

}
