/*
 * GPG CLI Helper - Uses GPG command line instead of GPGME
 * This is more reliable on Windows/MINGW where GPGME has issues with homedir.
 * 
 * Copyright (C) 2025-2026 DinoX
 */

using Gee;

namespace GPGHelper {

private static bool initialized = false;
private static string? gpg_binary = null;
private static string? gpg_homedir = null;

// Mutex to serialize GPG calls - prevents crashes on Windows when multiple
// GPG processes run simultaneously and corrupt GLib's error handler stack
private static Mutex gpg_mutex;

/**
 * Simple key structure that mimics GPG.Key for compatibility
 */
public class Key : Object {
    public string fpr { get; set; }
    public string keyid { get; set; }
    public string uid { get; set; }
    public string email { get; set; }
    public bool secret { get; set; }
    public bool can_encrypt { get; set; default = true; }
    public bool can_sign { get; set; default = true; }
    public bool expired { get; set; default = false; }
    public bool revoked { get; set; default = false; }
    
    public Key(string fingerprint) {
        this.fpr = fingerprint;
        this.keyid = fingerprint.length >= 16 ? fingerprint.substring(fingerprint.length - 16) : fingerprint;
    }
}

/**
 * Decrypted data container
 */
public class DecryptedData {
    public uint8[] data { get; set; }
    public string filename { get; set; }
}

/**
 * Initialize the GPG helper - find gpg binary and set homedir
 */
private static void initialize() {
    if (initialized) return;
    
    // Find GPG binary
    gpg_binary = Environment.find_program_in_path("gpg");
    if (gpg_binary == null) {
        gpg_binary = "gpg";
    }
    
    // Get homedir from environment
    gpg_homedir = Environment.get_variable("GNUPGHOME");
    
    debug("GPGHelper (CLI): Initialized with gpg=%s, homedir=%s", 
            gpg_binary, gpg_homedir ?? "default");
    
    initialized = true;
}

/**
 * Build base GPG command with homedir
 * @param allow_interactive: if true, don't use --batch so pinentry can prompt for passphrase
 */
private static string[] get_base_command(bool allow_interactive = false) {
    initialize();
    
    var args = new ArrayList<string>();
    args.add(gpg_binary);
    
    if (gpg_homedir != null && gpg_homedir.length > 0) {
        args.add("--homedir");
        args.add(gpg_homedir);
    }
    
    if (!allow_interactive) {
        // Batch mode for non-interactive operations (listing keys, encrypting, etc.)
        args.add("--batch");
    }
    args.add("--yes");
    
    // NOTE: We do NOT use --pinentry-mode loopback here!
    // Instead, we let gpg-agent use its configured pinentry (pinentry-w32 on Windows)
    // to prompt the user for passphrase if needed.
    // The passphrase will be cached by gpg-agent for subsequent operations.
    
    return args.to_array();
}

/**
 * Build interactive GPG command (for signing, decrypting - operations that may need passphrase)
 */
private static string[] get_interactive_command() {
    return get_base_command(true);
}

/**
 * Run GPG command and return stdout
 */
private static string run_gpg(string[] extra_args, string? stdin_data = null) throws GLib.Error {
    var args = new ArrayList<string>();
    foreach (string arg in get_base_command()) {
        args.add(arg);
    }
    foreach (string arg in extra_args) {
        args.add(arg);
    }
    
    // Build command array
    string[] cmd = args.to_array();
    
    try {
        SubprocessFlags flags = SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE;
        if (stdin_data != null) {
            flags |= SubprocessFlags.STDIN_PIPE;
        }
        
        var subprocess = new Subprocess.newv(cmd, flags);
        
        Bytes? stdout_bytes = null;
        Bytes? stderr_bytes = null;
        
        if (stdin_data != null) {
            subprocess.communicate(new Bytes(stdin_data.data), null, out stdout_bytes, out stderr_bytes);
        } else {
            subprocess.communicate(null, null, out stdout_bytes, out stderr_bytes);
        }
        
        string stdout_str = "";
        if (stdout_bytes != null) {
            stdout_str = (string) stdout_bytes.get_data();
            if (stdout_str == null) stdout_str = "";
        }
        
        // Check for errors
        if (!subprocess.get_if_exited() || subprocess.get_exit_status() != 0) {
            string stderr_str = "";
            if (stderr_bytes != null) {
                stderr_str = (string) stderr_bytes.get_data();
                if (stderr_str != null && stderr_str.length > 0) {
                    debug("GPG stderr: %s", stderr_str);
                }
            }
        }
        
        return stdout_str;
    } catch (Error e) {
        throw e;
    }
}

/**
 * Internal GPG run WITHOUT mutex (caller must hold the lock)
 */
private static bool run_gpg_internal(string[] extra_args, string? stdin_data, out string stdout_str, out string stderr_str, out int exit_status, bool allow_interactive = false) {
    var args = new ArrayList<string>();
    foreach (string arg in get_base_command(allow_interactive)) {
        args.add(arg);
    }
    foreach (string arg in extra_args) {
        if (arg != null) {
            args.add(arg);
        }
    }
    
    stdout_str = "";
    stderr_str = "";
    exit_status = -1;
    
    // Build command array
    string[] cmd = new string[args.size];
    for (int i = 0; i < args.size; i++) {
        cmd[i] = args[i] ?? "";
    }
    
    // Debug: log command
    var cmd_str = new StringBuilder();
    foreach (string c in cmd) {
        cmd_str.append(c);
        cmd_str.append(" ");
    }
    debug("GPGHelper: Running command: %s", cmd_str.str);
    
    try {
        if (allow_interactive) {
            // Interactive mode (with Pinentry): NO PIPES to avoid Windows GLib crash
            var subprocess = new Subprocess.newv(cmd, SubprocessFlags.NONE);
            subprocess.wait();
            
            if (subprocess.get_if_exited()) {
                exit_status = subprocess.get_exit_status();
            } else {
                exit_status = -1;
            }
            
            stdout_str = "";
            stderr_str = "";
            return exit_status == 0;
        } else {
            // Non-interactive mode (batch): Pipes are safe
            SubprocessFlags flags = SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE;
            var subprocess = new Subprocess.newv(cmd, flags);
            
            Bytes? stdout_bytes = null;
            Bytes? stderr_bytes = null;
            subprocess.communicate(null, null, out stdout_bytes, out stderr_bytes);
            
            if (stdout_bytes != null) {
                stdout_str = (string) stdout_bytes.get_data();
                if (stdout_str == null) stdout_str = "";
            }
            if (stderr_bytes != null) {
                stderr_str = (string) stderr_bytes.get_data();
                if (stderr_str == null) stderr_str = "";
            }
            
            if (subprocess.get_if_exited()) {
                exit_status = subprocess.get_exit_status();
            } else {
                exit_status = -1;
            }
            
            return exit_status == 0;
        }
    } catch (Error e) {
        stdout_str = "";
        stderr_str = e.message;
        exit_status = -1;
        return false;
    }
}

/**
 * Simple synchronous GPG run (for simpler commands)
 * @param extra_args: additional arguments to pass to GPG
 * @param stdin_data: optional data to pass to GPG via temp file
 * @param allow_interactive: if true, allows pinentry to prompt for passphrase (no --batch)
 *                           When true, we avoid pipes to prevent Windows GLib crash
 */
private static bool run_gpg_sync(string[] extra_args, string? stdin_data, out string stdout_str, out string stderr_str, out int exit_status, bool allow_interactive = false) {
    // Lock mutex to serialize GPG calls - prevents Windows crashes from concurrent GPG processes
    gpg_mutex.lock();
    bool result = run_gpg_internal(extra_args, stdin_data, out stdout_str, out stderr_str, out exit_status, allow_interactive);
    gpg_mutex.unlock();
    return result;
}

/**
 * Encrypt text to ASCII armor for given key fingerprints
 */
public static string encrypt_armor(string plain, Key[] keys, int flags = 0) throws GLib.Error {
    initialize();
    
    debug("GPGHelper.encrypt_armor: Encrypting to %d keys", keys.length);
    
    if (keys.length == 0) {
        throw new IOError.FAILED("GPG encrypt failed: No recipient keys provided");
    }
    
    // Lock early to protect temp file operations
    gpg_mutex.lock();
    
    try {
        var args = new ArrayList<string>();
        args.add("--armor");
        args.add("--encrypt");
        args.add("--trust-model");
        args.add("always");
        
        foreach (Key key in keys) {
            args.add("-r");
            args.add(key.fpr);
        }
        
        // Write plaintext to temp file
        string temp_in = Path.build_filename(Environment.get_tmp_dir(), "dinox-enc-in-%d".printf(Random.int_range(0, 1000000)));
        string temp_out = temp_in + ".asc";
        FileUtils.set_contents(temp_in, plain);
        
        args.add("-o");
        args.add(temp_out);
        args.add(temp_in);
        
        string stdout_str, stderr_str;
        int exit_status;
        run_gpg_internal(args.to_array(), null, out stdout_str, out stderr_str, out exit_status);
        
        FileUtils.remove(temp_in);
        
        if (exit_status != 0) {
            gpg_mutex.unlock();
            throw new IOError.FAILED("GPG encrypt failed: %s", stderr_str);
        }
        
        string result;
        FileUtils.get_contents(temp_out, out result);
        FileUtils.remove(temp_out);
        
        gpg_mutex.unlock();
        return result;
    } catch (Error e) {
        gpg_mutex.unlock();
        throw e;
    }
}

/**
 * Sign and encrypt text to ASCII armor (for XEP-0374)
 * This creates a signed+encrypted OpenPGP message
 */
public static string sign_and_encrypt(string plain, Key[] recipients, Key? sign_key = null) throws GLib.Error {
    initialize();
    
    // Lock early to protect temp file operations
    gpg_mutex.lock();
    
    try {
        var args = new ArrayList<string>();
        args.add("--armor");
        args.add("--sign");
        args.add("--encrypt");
        args.add("--trust-model");
        args.add("always");
        
        if (sign_key != null) {
            args.add("-u");
            args.add(sign_key.fpr);
        }
        
        foreach (Key key in recipients) {
            args.add("-r");
            args.add(key.fpr);
        }
        
        // Write plaintext to temp file
        string temp_in = Path.build_filename(Environment.get_tmp_dir(), "dinox-signenc-in-%d".printf(Random.int_range(0, 1000000)));
        string temp_out = temp_in + ".asc";
        FileUtils.set_contents(temp_in, plain);
        
        args.add("-o");
        args.add(temp_out);
        args.add(temp_in);
        
        string stdout_str, stderr_str;
        int exit_status;
        // Use interactive mode (no --batch) so pinentry can prompt for passphrase
        run_gpg_internal(args.to_array(), null, out stdout_str, out stderr_str, out exit_status, true);
        
        FileUtils.remove(temp_in);
        
        if (exit_status != 0) {
            gpg_mutex.unlock();
            throw new IOError.FAILED("GPG sign+encrypt failed: %s", stderr_str);
        }
        
        string signenc_result;
        FileUtils.get_contents(temp_out, out signenc_result);
        FileUtils.remove(temp_out);
        
        gpg_mutex.unlock();
        return signenc_result;
    } catch (Error e) {
        gpg_mutex.unlock();
        throw e;
    }
}

/**
 * Encrypt file to binary for given key fingerprints
 */
public static uint8[] encrypt_file(string uri, Key[] keys, int flags, string file_name) throws GLib.Error {
    initialize();
    
    // Lock early to protect temp file operations
    gpg_mutex.lock();
    
    try {
        var args = new ArrayList<string>();
        args.add("--encrypt");
        args.add("--trust-model");
        args.add("always");
        args.add("--set-filename");
        args.add(file_name);
        
        foreach (Key key in keys) {
            args.add("-r");
            args.add(key.fpr);
        }
        
        string temp_out = Path.build_filename(Environment.get_tmp_dir(), "dinox-enc-out-%d.gpg".printf(Random.int_range(0, 1000000)));
        args.add("-o");
        args.add(temp_out);
        args.add(uri);
        
        string stdout_str, stderr_str;
        int exit_status;
        run_gpg_internal(args.to_array(), null, out stdout_str, out stderr_str, out exit_status);
        
        if (exit_status != 0) {
            gpg_mutex.unlock();
            throw new IOError.FAILED("GPG encrypt file failed: %s", stderr_str);
        }
        
        uint8[] result;
        FileUtils.get_data(temp_out, out result);
        FileUtils.remove(temp_out);
        
        gpg_mutex.unlock();
        return result;
    } catch (Error e) {
        gpg_mutex.unlock();
        throw e;
    }
}

/**
 * Decrypt ASCII armored text
 */
public static string decrypt(string encr) throws GLib.Error {
    initialize();
    
    // Lock early to protect temp file operations
    gpg_mutex.lock();
    
    try {
        string temp_in = Path.build_filename(Environment.get_tmp_dir(), "dinox-dec-in-%d.asc".printf(Random.int_range(0, 1000000)));
        string temp_out = Path.build_filename(Environment.get_tmp_dir(), "dinox-dec-out-%d".printf(Random.int_range(0, 1000000)));
        FileUtils.set_contents(temp_in, encr);
        
        string[] args = { "--decrypt", "-o", temp_out, temp_in };
        
        string stdout_str, stderr_str;
        int exit_status;
        // Use interactive mode (no --batch) so pinentry can prompt for passphrase
        run_gpg_internal(args, null, out stdout_str, out stderr_str, out exit_status, true);
        
        FileUtils.remove(temp_in);
        
        if (exit_status != 0) {
            gpg_mutex.unlock();
            throw new IOError.FAILED("GPG decrypt failed: %s", stderr_str);
        }
        
        string result;
        FileUtils.get_contents(temp_out, out result);
        FileUtils.remove(temp_out);
        
        gpg_mutex.unlock();
        return result;
    } catch (Error e) {
        gpg_mutex.unlock();
        throw e;
    }
}

/**
 * Decrypt binary data
 */
public static DecryptedData decrypt_data(uint8[] data) throws GLib.Error {
    initialize();
    
    // Lock early to protect temp file operations
    gpg_mutex.lock();
    
    try {
        string temp_in = Path.build_filename(Environment.get_tmp_dir(), "dinox-dec-in-%d.gpg".printf(Random.int_range(0, 1000000)));
        string temp_out = Path.build_filename(Environment.get_tmp_dir(), "dinox-dec-out-%d".printf(Random.int_range(0, 1000000)));
        FileUtils.set_data(temp_in, data);
        
        // Use --status-fd to get filename info
        string[] args = { "--decrypt", "--status-fd", "2", "-o", temp_out, temp_in };
        
        string stdout_str, stderr_str;
        int exit_status;
        // Use interactive mode (no --batch) so pinentry can prompt for passphrase
        run_gpg_internal(args, null, out stdout_str, out stderr_str, out exit_status, true);
        
        FileUtils.remove(temp_in);
        
        if (exit_status != 0) {
            gpg_mutex.unlock();
            throw new IOError.FAILED("GPG decrypt data failed: %s", stderr_str);
        }
        
        uint8[] result_data;
        FileUtils.get_data(temp_out, out result_data);
        FileUtils.remove(temp_out);
        
        // Parse filename from status output
        string filename = "";
        if (stderr_str.contains("[GNUPG:] PLAINTEXT")) {
            // Format: [GNUPG:] PLAINTEXT 62 0 filename
            foreach (string line in stderr_str.split("\n")) {
                if (line.contains("[GNUPG:] PLAINTEXT")) {
                    var parts = line.split(" ");
                    if (parts.length >= 5) {
                        filename = parts[4];
                    }
                    break;
                }
            }
        }
        
        gpg_mutex.unlock();
        return new DecryptedData() { data = result_data, filename = filename };
    } catch (Error e) {
        gpg_mutex.unlock();
        throw e;
    }
}

/**
 * Sign text (clear signature)
 */
public static string sign(string plain, int mode, Key? key = null) throws GLib.Error {
    initialize();
    
    // Lock early to protect temp file operations
    gpg_mutex.lock();
    
    try {
        string temp_in = Path.build_filename(Environment.get_tmp_dir(), "dinox-sign-in-%d".printf(Random.int_range(0, 1000000)));
        string temp_out = Path.build_filename(Environment.get_tmp_dir(), "dinox-sign-out-%d.asc".printf(Random.int_range(0, 1000000)));
        FileUtils.set_contents(temp_in, plain);
        
        var args = new ArrayList<string>();
        args.add("--armor");
        // XEP-0027 requires detached signature, not clearsign
        args.add("--detach-sign");
        
        if (key != null) {
            args.add("-u");
            args.add(key.fpr);
        }
        
        args.add("-o");
        args.add(temp_out);
        args.add(temp_in);
        
        string stdout_str, stderr_str;
        int exit_status;
        // Use interactive mode (no --batch) so pinentry can prompt for passphrase
        run_gpg_internal(args.to_array(), null, out stdout_str, out stderr_str, out exit_status, true);
        
        FileUtils.remove(temp_in);
        
        if (exit_status != 0) {
            gpg_mutex.unlock();
            throw new IOError.FAILED("GPG sign failed: %s", stderr_str);
        }
        
        string result;
        FileUtils.get_contents(temp_out, out result);
        FileUtils.remove(temp_out);
        
        gpg_mutex.unlock();
        return result;
    } catch (Error e) {
        gpg_mutex.unlock();
        throw e;
    }
}

/**
 * Result of signature verification
 */
public class SignatureVerifyResult {
    public string? key_id { get; set; }
    public bool verified { get; set; default = false; }  // true if signature is valid and key is in keyring
    public bool key_missing { get; set; default = false; }  // true if key is not in keyring
    
    public SignatureVerifyResult() {}
}

/**
 * Verify signature and get signing key fingerprint
 * Returns detailed result including whether key is in keyring
 */
public static SignatureVerifyResult verify_signature(string signature, string? text) throws GLib.Error {
    initialize();
    
    // Lock early to protect temp file operations
    gpg_mutex.lock();
    
    var result = new SignatureVerifyResult();
    
    try {
        string temp_sig = Path.build_filename(Environment.get_tmp_dir(), "dinox-verify-sig-%d.asc".printf(Random.int_range(0, 1000000)));
        string temp_status = Path.build_filename(Environment.get_tmp_dir(), "dinox-verify-status-%d.txt".printf(Random.int_range(0, 1000000)));
        FileUtils.set_contents(temp_sig, signature);
        
        var args = new ArrayList<string>();
        args.add("--verify");
        args.add("--status-file");
        args.add(temp_status);
        args.add(temp_sig);
        
        string? temp_text = null;
        if (text != null) {
            temp_text = Path.build_filename(Environment.get_tmp_dir(), "dinox-verify-txt-%d".printf(Random.int_range(0, 1000000)));
            FileUtils.set_contents(temp_text, text);
            args.add(temp_text);
        }
        
        string stdout_str, stderr_str;
        int exit_status;
        run_gpg_internal(args.to_array(), null, out stdout_str, out stderr_str, out exit_status);
        
        FileUtils.remove(temp_sig);
        if (temp_text != null) {
            FileUtils.remove(temp_text);
        }
        
        // Read status from file
        string status_output = "";
        if (FileUtils.test(temp_status, FileTest.EXISTS)) {
            try {
                FileUtils.get_contents(temp_status, out status_output);
            } catch (Error e) {
                debug("GPGHelper.verify_signature: Could not read status file: %s", e.message);
            }
            FileUtils.remove(temp_status);
        }
        
        gpg_mutex.unlock();
        
        // Debug: log GPG output
        debug("GPGHelper.verify_signature: GPG status:\n%s", status_output);
        debug("GPGHelper.verify_signature: GPG stderr:\n%s", stderr_str);
        debug("GPGHelper.verify_signature: GPG exit: %d", exit_status);
        
        // Parse fingerprint from status output
        foreach (string line in status_output.split("\n")) {
            if (line.contains("[GNUPG:] VALIDSIG")) {
                var parts = line.split(" ");
                if (parts.length >= 3) {
                    result.key_id = parts[2];
                    result.verified = true;
                    debug("GPGHelper.verify_signature: VALID signature from key: %s", parts[2]);
                    return result;
                }
            }
            if (line.contains("[GNUPG:] GOODSIG")) {
                var parts = line.split(" ");
                if (parts.length >= 3) {
                    result.key_id = parts[2];
                    result.verified = true;
                    debug("GPGHelper.verify_signature: GOOD signature from key: %s", parts[2]);
                    return result;
                }
            }
        }
        
        // Key not in keyring - extract key ID anyway
        foreach (string line in status_output.split("\n")) {
            if (line.contains("[GNUPG:] ERRSIG")) {
                var parts = line.split(" ");
                if (parts.length >= 3) {
                    result.key_id = parts[2];
                    result.key_missing = true;
                    debug("GPGHelper.verify_signature: Key %s NOT in keyring (ERRSIG)", parts[2]);
                    return result;
                }
            }
            if (line.contains("[GNUPG:] NO_PUBKEY")) {
                var parts = line.split(" ");
                if (parts.length >= 3) {
                    result.key_id = parts[2];
                    result.key_missing = true;
                    debug("GPGHelper.verify_signature: Key %s NOT in keyring (NO_PUBKEY)", parts[2]);
                    return result;
                }
            }
        }
        
        debug("GPGHelper.verify_signature: Could not find any key ID in output");
        return result;
    } catch (Error e) {
        gpg_mutex.unlock();
        throw e;
    }
}

/**
 * Verify signature and get signing key fingerprint (simple version for compatibility)
 */
public static string? get_sign_key(string signature, string? text) throws GLib.Error {
    var result = verify_signature(signature, text);
    return result.key_id;
}

/**
 * Get list of keys
 */
public static Gee.List<Key> get_keylist(string? pattern = null, bool secret_only = false) throws GLib.Error {
    initialize();
    
    var keys = new ArrayList<Key>();
    
    var args = new ArrayList<string>();
    if (secret_only) {
        args.add("--list-secret-keys");
    } else {
        args.add("--list-keys");
    }
    args.add("--with-colons");
    args.add("--with-fingerprint");
    if (pattern != null && pattern.length > 0) {
        args.add(pattern);
    }
    
    string stdout_str, stderr_str;
    int exit_status;
    run_gpg_sync(args.to_array(), null, out stdout_str, out stderr_str, out exit_status);
    
    if (exit_status != 0 && !stderr_str.contains("No public key") && !stderr_str.contains("No secret key")) {
        // Only throw if it's a real error, not "key not found"
        if (stderr_str.length > 0 && !stderr_str.contains("not found")) {
            debug("GPG list keys warning: %s", stderr_str);
        }
    }
    
    // Parse output
    Key? current_key = null;
    bool expect_fpr = false;
    
    foreach (string line in stdout_str.split("\n")) {
        var parts = line.split(":");
        if (parts.length < 2) continue;
        
        string record_type = parts[0];
        
        if (record_type == "sec" || record_type == "pub") {
            // Start of a new key
            expect_fpr = true;
            if (parts.length >= 5) {
                // Check validity
                string validity = parts[1];
                bool expired = validity == "e";
                bool revoked = validity == "r";
                
                current_key = new Key("");
                current_key.secret = (record_type == "sec");
                current_key.expired = expired;
                current_key.revoked = revoked;
            }
        } else if (record_type == "fpr" && expect_fpr && current_key != null) {
            if (parts.length >= 10) {
                current_key.fpr = parts[9];
                current_key.keyid = current_key.fpr.length >= 16 ? 
                    current_key.fpr.substring(current_key.fpr.length - 16) : current_key.fpr;
            }
            expect_fpr = false;
        } else if (record_type == "uid" && current_key != null && current_key.uid == null) {
            if (parts.length >= 10) {
                current_key.uid = parts[9];
                // Extract email
                if (current_key.uid.contains("<") && current_key.uid.contains(">")) {
                    int start = current_key.uid.index_of("<") + 1;
                    int end = current_key.uid.index_of(">");
                    if (end > start) {
                        current_key.email = current_key.uid.substring(start, end - start);
                    }
                }
                // Add key to list when we have uid
                if (current_key.fpr.length > 0) {
                    keys.add(current_key);
                }
            }
        } else if (record_type == "ssb" || record_type == "sub") {
            // Subkey - don't collect fpr
            expect_fpr = false;
        }
    }
    
    return keys;
}

/**
 * Get a public key by fingerprint or key ID
 */
public static Key? get_public_key(string sig) throws GLib.Error {
    var keys = get_keylist(sig, false);
    foreach (Key k in keys) {
        if (k.fpr == sig || k.keyid == sig || k.fpr.has_suffix(sig)) {
            return k;
        }
    }
    return keys.size > 0 ? keys[0] : null;
}

/**
 * Get a private key by fingerprint or key ID
 */
public static Key? get_private_key(string sig) throws GLib.Error {
    var keys = get_keylist(sig, true);
    foreach (Key k in keys) {
        if (k.fpr == sig || k.keyid == sig || k.fpr.has_suffix(sig)) {
            return k;
        }
    }
    return keys.size > 0 ? keys[0] : null;
}

/**
 * Export public key in ASCII armor format
 */
public static string? export_public_key(string key_id) throws GLib.Error {
    initialize();
    
    string[] args = { "--armor", "--export", key_id };
    
    string stdout_str, stderr_str;
    int exit_status;
    run_gpg_sync(args, null, out stdout_str, out stderr_str, out exit_status);
    
    if (exit_status != 0 || stdout_str.length == 0) {
        debug("GPG export failed: %s", stderr_str);
        return null;
    }
    
    return stdout_str;
}

/**
 * Import a key from ASCII armor
 */
public static bool import_key(string armored_key) throws GLib.Error {
    initialize();
    
    // Validate that the key looks like ASCII armor
    string trimmed = armored_key.strip();
    if (!trimmed.has_prefix("-----BEGIN PGP")) {
        warning("GPGHelper: import_key: Invalid key format - not ASCII armored");
        return false;
    }
    if (!trimmed.has_suffix("-----")) {
        warning("GPGHelper: import_key: Invalid key format - incomplete ASCII armor");
        return false;
    }
    
    string temp_key = Path.build_filename(Environment.get_tmp_dir(), "dinox-import-%d.asc".printf(Random.int_range(0, 1000000)));
    FileUtils.set_contents(temp_key, armored_key);
    
    string[] args = { "--import", temp_key };
    
    string stdout_str, stderr_str;
    int exit_status;
    run_gpg_sync(args, null, out stdout_str, out stderr_str, out exit_status);
    
    FileUtils.remove(temp_key);
    
    if (exit_status != 0 && stderr_str.contains("radix64")) {
        warning("GPGHelper: import_key: Key has invalid base64 encoding, ignoring");
        return false;
    }
    
    return exit_status == 0;
}

/**
 * Default keyserver for key lookups
 */
public const string DEFAULT_KEYSERVER = "hkps://keys.openpgp.org";

/**
 * Upload a public key to a keyserver
 * @param key_id: The key ID or fingerprint to upload
 * @param keyserver: The keyserver URL (default: keys.openpgp.org)
 * @return true if successful
 */
public static bool upload_key_to_keyserver(string key_id, string keyserver = DEFAULT_KEYSERVER) throws GLib.Error {
    initialize();
    
    debug("GPGHelper: Uploading key %s to keyserver %s", key_id, keyserver);
    
    string[] args = { "--keyserver", keyserver, "--send-keys", key_id };
    
    string stdout_str, stderr_str;
    int exit_status;
    run_gpg_sync(args, null, out stdout_str, out stderr_str, out exit_status);
    
    if (exit_status != 0) {
        debug("GPGHelper: Failed to upload key to keyserver: %s", stderr_str);
        return false;
    }
    
    debug("GPGHelper: Successfully uploaded key %s to %s", key_id, keyserver);
    return true;
}

/**
 * Download a key from a keyserver
 * @param key_id: The key ID or fingerprint to download
 * @param keyserver: The keyserver URL (default: keys.openpgp.org)
 * @return true if key was found and imported
 */
public static bool download_key_from_keyserver(string key_id, string keyserver = DEFAULT_KEYSERVER) throws GLib.Error {
    initialize();
    
    debug("GPGHelper: Searching for key %s on keyserver %s", key_id, keyserver);
    
    // Try with import-minimal first (for keys without verified UID on keys.openpgp.org)
    string[] args = { 
        "--keyserver", keyserver, 
        "--keyserver-options", "import-minimal",
        "--recv-keys", key_id 
    };
    
    string stdout_str, stderr_str;
    int exit_status;
    run_gpg_sync(args, null, out stdout_str, out stderr_str, out exit_status);
    
    // If that failed, check if it's because of "no user ID" - keys.openpgp.org strips unverified UIDs
    if (exit_status != 0 && (stderr_str.contains("Keine User-ID") || stderr_str.contains("no user ID"))) {
        debug("GPGHelper: Key %s has no verified UID on keyserver. Trying direct API download...", key_id);
        
        // Try to download directly via keys.openpgp.org API (works even without verified UID)
        if (download_key_from_openpgp_org_api(key_id)) {
            return true;
        }
        
        // Try Ubuntu keyserver as fallback (doesn't strip UIDs)
        debug("GPGHelper: Trying alternative keyserver (Ubuntu)...");
        string alt_keyserver = "hkps://keyserver.ubuntu.com";
        string[] alt_args = { "--keyserver", alt_keyserver, "--recv-keys", key_id };
        run_gpg_sync(alt_args, null, out stdout_str, out stderr_str, out exit_status);
        
        if (exit_status == 0) {
            debug("GPGHelper: Successfully imported key %s from %s", key_id, alt_keyserver);
            return true;
        }
    }
    
    if (exit_status != 0) {
        debug("GPGHelper: Key %s not found on keyserver or import failed: %s", key_id, stderr_str);
        return false;
    }
    
    debug("GPGHelper: Successfully imported key %s from %s", key_id, keyserver);
    return true;
}

/**
 * Download key directly from keys.openpgp.org API
 * This works even for keys without verified email (no UID)
 */
private static bool download_key_from_openpgp_org_api(string key_id) {
    try {
        // Normalize key ID to uppercase and remove 0x prefix
        string normalized_id = key_id.up().replace("0X", "");
        
        // keys.openpgp.org API endpoint
        string url = "https://keys.openpgp.org/vks/v1/by-keyid/" + normalized_id;
        
        debug("GPGHelper: Fetching key from API: %s", url);
        
        // Create temp file for binary key data
        string temp_key = Path.build_filename(Environment.get_tmp_dir(), 
                                              "dinox-keyimport-%d.gpg".printf(Random.int_range(0, 1000000)));
        
        // Use curl to download to file (API returns binary data, not ASCII-armored)
        string curl_path = "curl";
#if WINDOWS
        curl_path = "curl.exe";
#endif
        
        string[] curl_args = { curl_path, "-s", "-f", "-o", temp_key, url };
        
        // Use Subprocess instead of Process.spawn_sync for Windows stability
        try {
            var subprocess = new Subprocess.newv(curl_args, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            Bytes? stdout_bytes = null;
            Bytes? stderr_bytes = null;
            subprocess.communicate(null, null, out stdout_bytes, out stderr_bytes);
            
            int curl_exit = subprocess.get_if_exited() ? subprocess.get_exit_status() : -1;
            
            if (curl_exit != 0) {
                string curl_stderr = stderr_bytes != null ? (string) stderr_bytes.get_data() : "";
                debug("GPGHelper: API download failed (exit=%d): %s", curl_exit, curl_stderr ?? "");
                FileUtils.remove(temp_key);
                return false;
            }
        } catch (Error e) {
            debug("GPGHelper: curl execution failed: %s", e.message);
            FileUtils.remove(temp_key);
            return false;
        }
        
        // Check file size
        int64 file_size = 0;
        try {
            var file = File.new_for_path(temp_key);
            var info = file.query_info("standard::size", FileQueryInfoFlags.NONE);
            file_size = info.get_size();
        } catch (Error e) {
            debug("GPGHelper: Could not get file size: %s", e.message);
        }
        
        if (file_size < 100) {
            debug("GPGHelper: Downloaded key file too small: %lld bytes", file_size);
            FileUtils.remove(temp_key);
            return false;
        }
        
        debug("GPGHelper: Got key from API, size: %lld bytes", file_size);
        
        // Import the key from file
        string[] import_args = { "--import", temp_key };
        string import_stdout, import_stderr;
        int import_exit;
        run_gpg_sync(import_args, null, out import_stdout, out import_stderr, out import_exit);
        
        FileUtils.remove(temp_key);
        
        if (import_exit == 0 || import_stderr.contains("imported") || import_stderr.contains("importiert")) {
            debug("GPGHelper: Successfully imported key %s from API", key_id);
            return true;
        } else {
            debug("GPGHelper: Import from API failed: %s", import_stderr);
            return false;
        }
    } catch (Error e) {
        debug("GPGHelper: API download error: %s", e.message);
        return false;
    }
}

/**
 * Search for a key on keyserver by email or key ID
 * Returns list of key IDs found
 */
public static Gee.List<string> search_keyserver(string query, string keyserver = DEFAULT_KEYSERVER) throws GLib.Error {
    initialize();
    
    var results = new ArrayList<string>();
    
    debug("GPGHelper: Searching keyserver %s for: %s", keyserver, query);
    
    string[] args = { "--keyserver", keyserver, "--search-keys", "--batch", "--with-colons", query };
    
    string stdout_str, stderr_str;
    int exit_status;
    run_gpg_sync(args, null, out stdout_str, out stderr_str, out exit_status);
    
    // Parse output for key IDs
    foreach (string line in stdout_str.split("\n")) {
        if (line.has_prefix("pub:")) {
            var parts = line.split(":");
            if (parts.length > 1 && parts[1].length > 0) {
                results.add(parts[1]);
            }
        }
    }
    
    debug("GPGHelper: Found %d key(s) on keyserver", results.size);
    return results;
}

/**
 * Check if a private key requires a passphrase
 * @param key_fpr: The key fingerprint to check
 * @return true if the key requires a passphrase, false if it has no passphrase
 */
public static bool key_requires_passphrase(string key_fpr) {
    initialize();
    
    // Try to sign with an empty passphrase in loopback mode
    // If it succeeds, the key has no passphrase protection
    string temp_in = Path.build_filename(Environment.get_tmp_dir(), "dinox-pwcheck-%d".printf(Random.int_range(0, 1000000)));
    string temp_out = temp_in + ".asc";
    
    try {
        FileUtils.set_contents(temp_in, "test");
    } catch (Error e) {
        return true;  // Assume protected on error
    }
    
    string[] args = {
        "--batch", "--yes", "--pinentry-mode", "loopback",
        "--passphrase", "",  // Empty passphrase
        "-u", key_fpr,
        "--sign", "--armor", "-o", temp_out, temp_in
    };
    
    string stdout_str, stderr_str;
    int exit_status;
    run_gpg_sync(args, null, out stdout_str, out stderr_str, out exit_status, false);
    
    // Cleanup temp files
    FileUtils.remove(temp_in);
    FileUtils.remove(temp_out);
    
    if (exit_status == 0) {
        // Empty passphrase worked = key has no passphrase
        debug("GPGHelper: Key %s has NO passphrase protection", key_fpr);
        return false;
    } else {
        // Empty passphrase failed = key is protected
        debug("GPGHelper: Key %s requires passphrase", key_fpr);
        return true;
    }
}

}
