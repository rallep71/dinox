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

// GPG Worker Queue — all GPG subprocess calls are serialized through a single
// worker thread.  This eliminates mutex double-release bugs, deadlock risks,
// and prevents Windows crashes from concurrent GPG subprocess spawning.
private static AsyncQueue<GpgJob>? job_queue = null;
private static Thread<void*>? worker_thread = null;
private static Mutex result_mutex;
private static Cond result_cond;
private static int worker_started = 0;

private static Mutex secret_keys_mutex;

// Cache for has_secret_keys() - thread-safe check
private static bool has_secret_keys_checked = false;
private static bool has_secret_keys_cached = false;

/**
 * Job submitted to the GPG worker queue.
 */
public class GpgJob {
    public string[] extra_args;
    public string? stdin_data;
    public bool allow_interactive;
    public string caller;

    // Results (set by worker thread)
    public string stdout_str = "";
    public string stderr_str = "";
    public int exit_status = -1;
    public bool result = false;
    public bool completed = false;

    public GpgJob(string[] args, string? stdin_input, bool interactive, string caller_name) {
        this.extra_args = args;
        this.stdin_data = stdin_input;
        this.allow_interactive = interactive;
        this.caller = caller_name;
    }
}

/**
 * Ensure the single GPG worker thread is running.
 * Thread-safe using atomic compare-and-swap.
 */
private static void ensure_worker_started() {
    if (AtomicInt.compare_and_exchange(ref worker_started, 0, 1)) {
        job_queue = new AsyncQueue<GpgJob>();
        worker_thread = new Thread<void*>("gpg-worker", gpg_worker_func);
        debug("GPGHelper: Worker thread started");
    }
}

/**
 * GPG worker thread — pops jobs from the queue and executes them one at a time.
 * Only ONE GPG subprocess is ever active, eliminating all concurrency issues.
 */
private static void* gpg_worker_func() {
    debug("GPGHelper: Worker thread running (thread %lld)", (int64) Thread.self<void*>());
    while (true) {
        GpgJob job = job_queue.pop();

        debug("GPGHelper [%s]: Worker executing job", job.caller);

        job.result = run_gpg_internal(
            job.extra_args, job.stdin_data,
            out job.stdout_str, out job.stderr_str,
            out job.exit_status, job.allow_interactive
        );

        debug("GPGHelper [%s]: Worker completed (exit=%d)", job.caller, job.exit_status);

        // Signal completion to the waiting submitter
        result_mutex.lock();
        job.completed = true;
        result_cond.broadcast();
        result_mutex.unlock();
    }
}

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
    // Ensure the worker queue is running
    ensure_worker_started();
    
    if (initialized) return;
    
    // Find GPG binary
    gpg_binary = Environment.find_program_in_path("gpg");
    if (gpg_binary == null) {
        gpg_binary = "gpg";
    }
    
    // Get homedir from environment
    gpg_homedir = Environment.get_variable("GNUPGHOME");
    
    // CRITICAL: Verify homedir exists before any GPG operation
    // After Panic Wipe, the directory may be deleted but env var still set
    if (gpg_homedir != null && gpg_homedir.length > 0) {
        if (!FileUtils.test(gpg_homedir, FileTest.IS_DIR)) {
            debug("GPGHelper: GNUPGHOME does not exist: %s, creating...", gpg_homedir);
            if (DirUtils.create_with_parents(gpg_homedir, 0700) != 0) {
                warning("GPGHelper: Cannot create GNUPGHOME: %s - falling back to system default", gpg_homedir);
                gpg_homedir = null;  // Fall back to system default
            }
        }
    }
    
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
    
    // Debug: print command
    var cmd_str = string.joinv(" ", cmd);
    debug("GPGHelper.run_gpg_internal: Running: %s", cmd_str);
    
    try {
        if (allow_interactive) {
            // Interactive mode (with Pinentry): NO PIPES to avoid Windows GLib crash
            debug("GPGHelper.run_gpg_internal: Interactive mode, creating subprocess...");
            var subprocess = new Subprocess.newv(cmd, SubprocessFlags.NONE);
            debug("GPGHelper.run_gpg_internal: Waiting for subprocess...");
            subprocess.wait();
            debug("GPGHelper.run_gpg_internal: Subprocess finished");
            
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
            debug("GPGHelper.run_gpg_internal: Batch mode, creating subprocess with pipes...");
            SubprocessFlags flags = SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE;
            var subprocess = new Subprocess.newv(cmd, flags);
            
            Bytes? stdout_bytes = null;
            Bytes? stderr_bytes = null;
            debug("GPGHelper.run_gpg_internal: Communicating with subprocess...");
            subprocess.communicate(null, null, out stdout_bytes, out stderr_bytes);
            debug("GPGHelper.run_gpg_internal: Communication complete");
            
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
            
            debug("GPGHelper.run_gpg_internal: Exit status=%d, stdout_len=%d, stderr_len=%d", 
                  exit_status, stdout_str.length, stderr_str.length);
            return exit_status == 0;
        }
    } catch (Error e) {
        debug("GPGHelper.run_gpg_internal: Exception: %s", e.message);
        stdout_str = "";
        stderr_str = e.message;
        exit_status = -1;
        return false;
    }
}

/**
 * Submit a GPG operation to the worker queue and wait for completion.
 * Serializes all GPG subprocess calls through the single worker thread.
 * Safe to call from any thread — the caller blocks until the operation completes.
 */
private static bool run_gpg_sync(string[] extra_args, string? stdin_data, out string stdout_str, out string stderr_str, out int exit_status, bool allow_interactive = false) {
    ensure_worker_started();

    var job = new GpgJob(extra_args, stdin_data, allow_interactive, "run_gpg_sync");
    job_queue.push(job);

    // Wait for the worker to complete this job
    result_mutex.lock();
    while (!job.completed) {
        result_cond.wait(result_mutex);
    }
    result_mutex.unlock();

    stdout_str = job.stdout_str;
    stderr_str = job.stderr_str;
    exit_status = job.exit_status;
    return job.result;
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
    
    var args = new ArrayList<string>();
    args.add("--armor");
    args.add("--encrypt");
    args.add("--trust-model");
    args.add("always");
    
    foreach (Key key in keys) {
        args.add("-r");
        args.add(key.fpr);
        debug("GPGHelper.encrypt_armor: Adding recipient %s", key.fpr);
    }
    
    // Write plaintext to temp file
    string temp_in = Path.build_filename(Environment.get_tmp_dir(), "dinox-enc-in-%d".printf(Random.int_range(0, 1000000)));
    string temp_out = temp_in + ".asc";
    debug("GPGHelper.encrypt_armor: Writing to temp file %s", temp_in);
    FileUtils.set_contents(temp_in, plain);
    debug("GPGHelper.encrypt_armor: Temp file written, size=%d", plain.length);
    
    args.add("-o");
    args.add(temp_out);
    args.add(temp_in);
    
    string stdout_str, stderr_str;
    int exit_status;
    debug("GPGHelper.encrypt_armor: Calling GPG...");
    // Serialized through the worker queue — no manual lock needed
    run_gpg_sync(args.to_array(), null, out stdout_str, out stderr_str, out exit_status);
    debug("GPGHelper.encrypt_armor: GPG returned, exit=%d", exit_status);
    
    FileUtils.remove(temp_in);
    
    if (exit_status != 0) {
        debug("GPGHelper.encrypt_armor: GPG failed: %s", stderr_str);
        throw new IOError.FAILED("GPG encrypt failed: %s", stderr_str);
    }
    
    debug("GPGHelper.encrypt_armor: Reading output file %s", temp_out);
    string result;
    FileUtils.get_contents(temp_out, out result);
    FileUtils.remove(temp_out);
    
    debug("GPGHelper.encrypt_armor: Success, result length=%d", result.length);
    return result;
}

/**
 * Sign and encrypt text to ASCII armor (for XEP-0374)
 * This creates a signed+encrypted OpenPGP message
 */
public static string sign_and_encrypt(string plain, Key[] recipients, Key? sign_key = null) throws GLib.Error {
    initialize();
    
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
    // Serialized through the worker queue
    run_gpg_sync(args.to_array(), null, out stdout_str, out stderr_str, out exit_status, true);
    
    FileUtils.remove(temp_in);
    
    if (exit_status != 0) {
        throw new IOError.FAILED("GPG sign+encrypt failed: %s", stderr_str);
    }
    
    string signenc_result;
    FileUtils.get_contents(temp_out, out signenc_result);
    FileUtils.remove(temp_out);
    
    return signenc_result;
}

/**
 * Encrypt file to binary for given key fingerprints
 */
public static uint8[] encrypt_file(string uri, Key[] keys, int flags, string file_name) throws GLib.Error {
    initialize();
    
    var args = new ArrayList<string>();
    args.add("--sign");
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
    // Serialized through the worker queue
    run_gpg_sync(args.to_array(), null, out stdout_str, out stderr_str, out exit_status);
    
    if (exit_status != 0) {
        throw new IOError.FAILED("GPG encrypt file failed: %s", stderr_str);
    }
    
    uint8[] result;
    FileUtils.get_data(temp_out, out result);
    FileUtils.remove(temp_out);
    
    return result;
}

/**
 * Check if we have the secret key needed to decrypt a message.
 * Uses --list-packets in batch mode to extract recipient key IDs,
 * then checks if we have any of those keys.
 * This avoids starting pinentry for messages we can't decrypt anyway.
 */
private static bool can_decrypt_message(string temp_in) {
    // Use --list-packets to see which keys the message is encrypted to
    // This is a batch operation that doesn't require passphrase
    string[] args = { "--list-packets", "--list-only", temp_in };
    
    string stdout_str, stderr_str;
    int exit_status;
    // Serialized through the worker queue
    run_gpg_sync(args, null, out stdout_str, out stderr_str, out exit_status, false);
    
    // GPG outputs key IDs in format like:
    // :pubkey enc packet: version 3, algo 16, keyid 282580F966E14B2E
    // We need to extract those keyids and check if we have any of them
    
    var recipient_keyids = new ArrayList<string>();
    string combined_output = stdout_str + "\n" + stderr_str;
    
    foreach (string line in combined_output.split("\n")) {
        if (line.contains("keyid ")) {
            int keyid_pos = line.index_of("keyid ");
            if (keyid_pos >= 0) {
                string keyid_part = line.substring(keyid_pos + 6).strip();
                // keyid is 16 hex chars
                if (keyid_part.length >= 16) {
                    string keyid = keyid_part.substring(0, 16);
                    recipient_keyids.add(keyid.up());
                    debug("GPGHelper: Message encrypted to keyid %s", keyid);
                }
            }
        }
    }
    
    if (recipient_keyids.size == 0) {
        // Couldn't determine recipients, try to decrypt anyway
        debug("GPGHelper: Could not determine message recipients, attempting decrypt");
        return true;
    }
    
    // Check if we have any of these secret keys
    // Safe to call get_keylist here — each queue submission is independent
    try {
        var our_keys = get_keylist(null, true);  // secret_only = true
        foreach (var our_key in our_keys) {
            // Check by keyid (last 16 chars of fingerprint)
            string our_keyid = our_key.fpr.length >= 16 ? 
                our_key.fpr.substring(our_key.fpr.length - 16).up() : our_key.fpr.up();
            if (recipient_keyids.contains(our_keyid)) {
                debug("GPGHelper: We have secret key %s for this message", our_keyid);
                return true;
            }
        }
    } catch (Error e) {
        // On error, try to decrypt anyway
        debug("GPGHelper: Error checking our keys: %s", e.message);
        return true;
    }
    
    debug("GPGHelper: We don't have any secret key for recipients: %s", 
          string.joinv(", ", recipient_keyids.to_array()));
    return false;
}

/**
 * Decrypt ASCII armored text
 */
public static string decrypt(string encr) throws GLib.Error {
    initialize();
    
    string temp_in = Path.build_filename(Environment.get_tmp_dir(), "dinox-dec-in-%d.asc".printf(Random.int_range(0, 1000000)));
    string temp_out = Path.build_filename(Environment.get_tmp_dir(), "dinox-dec-out-%d".printf(Random.int_range(0, 1000000)));
    FileUtils.set_contents(temp_in, encr);
    
    // First check if we have the secret key needed
    // This prevents Windows crashes from starting pinentry for messages we can't decrypt
    if (!can_decrypt_message(temp_in)) {
        FileUtils.remove(temp_in);
        throw new IOError.FAILED("GPG decrypt failed: no secret key available for this message");
    }
    
    string stdout_str, stderr_str;
    int exit_status;
    bool decryption_ok = false;
    
    // First try batch mode - this works if gpg-agent has passphrase cached
    // Serialized through the worker queue
    string[] batch_args = { "--batch", "--yes", "--decrypt", "--status-fd", "2", "--ignore-crc-error", "-o", temp_out, temp_in };
    debug("GPGHelper.decrypt: Trying batch mode first...");
    run_gpg_sync(batch_args, null, out stdout_str, out stderr_str, out exit_status, false);
    
    decryption_ok = stderr_str.contains("[GNUPG:] DECRYPTION_OKAY") || 
                    stderr_str.contains("[GNUPG:] GOODMDC");
    
    // If batch mode failed, try interactive mode for passphrase
    if (!decryption_ok && exit_status != 0) {
        debug("GPGHelper.decrypt: Batch mode failed, trying interactive mode...");
        if (FileUtils.test(temp_out, FileTest.EXISTS)) {
            FileUtils.remove(temp_out);
        }
        
        string[] interactive_args = { "--decrypt", "--status-fd", "2", "--ignore-crc-error", "-o", temp_out, temp_in };
        run_gpg_sync(interactive_args, null, out stdout_str, out stderr_str, out exit_status, true);
        
        decryption_ok = stderr_str.contains("[GNUPG:] DECRYPTION_OKAY") || 
                        stderr_str.contains("[GNUPG:] GOODMDC");
    }
    
    FileUtils.remove(temp_in);
    
    if (!decryption_ok && exit_status != 0) {
        if (FileUtils.test(temp_out, FileTest.EXISTS)) {
            FileUtils.remove(temp_out);
        }
        throw new IOError.FAILED("GPG decrypt failed (exit %d): no secret key or passphrase error", exit_status);
    }
    
    if (!FileUtils.test(temp_out, FileTest.EXISTS)) {
        throw new IOError.FAILED("GPG decrypt failed: output file not created");
    }
    
    string result;
    FileUtils.get_contents(temp_out, out result);
    FileUtils.remove(temp_out);
    debug("GPGHelper.decrypt: Success, decrypted %d chars", result.length);
    
    return result;
}

/**
 * Decrypt binary data
 */
public static DecryptedData decrypt_data(uint8[] data) throws GLib.Error {
    initialize();
    
    string temp_in = Path.build_filename(Environment.get_tmp_dir(), "dinox-dec-in-%d.gpg".printf(Random.int_range(0, 1000000)));
    string temp_out = Path.build_filename(Environment.get_tmp_dir(), "dinox-dec-out-%d".printf(Random.int_range(0, 1000000)));
    
    FileUtils.set_data(temp_in, data);
    
    // First check if we have the secret key needed
    if (!can_decrypt_message(temp_in)) {
        FileUtils.remove(temp_in);
        throw new IOError.FAILED("GPG decrypt data failed: no secret key available for this message");
    }
    
    string stdout_str, stderr_str;
    int exit_status;
    bool decryption_ok = false;
    
    // First try batch mode - works if gpg-agent has passphrase cached
    // Serialized through the worker queue
    string[] batch_args = { "--batch", "--yes", "--decrypt", "--status-fd", "2", "--ignore-crc-error", "-o", temp_out, temp_in };
    debug("GPGHelper.decrypt_data: Trying batch mode first...");
    run_gpg_sync(batch_args, null, out stdout_str, out stderr_str, out exit_status, false);
    
    decryption_ok = stderr_str.contains("[GNUPG:] DECRYPTION_OKAY") || 
                    stderr_str.contains("[GNUPG:] GOODMDC");
    
    // If batch mode failed, try interactive mode for passphrase
    if (!decryption_ok && exit_status != 0) {
        debug("GPGHelper.decrypt_data: Batch mode failed, trying interactive mode...");
        if (FileUtils.test(temp_out, FileTest.EXISTS)) {
            FileUtils.remove(temp_out);
        }
        
        string[] interactive_args = { "--decrypt", "--status-fd", "2", "--ignore-crc-error", "-o", temp_out, temp_in };
        run_gpg_sync(interactive_args, null, out stdout_str, out stderr_str, out exit_status, true);
        
        decryption_ok = stderr_str.contains("[GNUPG:] DECRYPTION_OKAY") || 
                        stderr_str.contains("[GNUPG:] GOODMDC");
    }
    
    FileUtils.remove(temp_in);
    
    if (!decryption_ok && exit_status != 0) {
        if (FileUtils.test(temp_out, FileTest.EXISTS)) {
            FileUtils.remove(temp_out);
        }
        throw new IOError.FAILED("GPG decrypt data failed (exit %d): no secret key or passphrase error", exit_status);
    }
    
    if (!FileUtils.test(temp_out, FileTest.EXISTS)) {
        throw new IOError.FAILED("GPG decrypt data failed: output file not created");
    }
    
    uint8[] result_data;
    FileUtils.get_data(temp_out, out result_data);
    FileUtils.remove(temp_out);
    debug("GPGHelper.decrypt_data: Success, decrypted %d bytes", result_data.length);
    
    // Parse filename from status output
    string filename = "";
    if (stderr_str.contains("[GNUPG:] PLAINTEXT")) {
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
    
    return new DecryptedData() { data = result_data, filename = filename };
}

/**
 * Sign text (clear signature)
 */
public static string sign(string plain, int mode, Key? key = null) throws GLib.Error {
    initialize();
    
    // Check if key requires passphrase
    // With the worker queue there is no deadlock risk — each call is an independent queue submission
    bool needs_passphrase = true;
    if (key != null) {
        needs_passphrase = key_requires_passphrase(key.fpr);
    }
    
    string temp_in = Path.build_filename(Environment.get_tmp_dir(), "dinox-sign-in-%d".printf(Random.int_range(0, 1000000)));
    string temp_out = Path.build_filename(Environment.get_tmp_dir(), "dinox-sign-out-%d.asc".printf(Random.int_range(0, 1000000)));
    FileUtils.set_contents(temp_in, plain);
    
    var args = new ArrayList<string>();
    args.add("--armor");
    // XEP-0027 requires detached signature, not clearsign
    args.add("--detach-sign");
    
    // If key has no passphrase, use batch mode to avoid pinentry issues on Windows
    if (!needs_passphrase) {
        args.add("--batch");
        args.add("--yes");
        args.add("--pinentry-mode");
        args.add("loopback");
        args.add("--passphrase");
        args.add("");
    }
    
    if (key != null) {
        args.add("-u");
        args.add(key.fpr);
    }
    
    args.add("-o");
    args.add(temp_out);
    args.add(temp_in);
    
    string stdout_str, stderr_str;
    int exit_status;
    // Serialized through the worker queue
    run_gpg_sync(args.to_array(), null, out stdout_str, out stderr_str, out exit_status, needs_passphrase);
    
    FileUtils.remove(temp_in);
    
    if (exit_status != 0) {
        throw new IOError.FAILED("GPG sign failed: %s", stderr_str);
    }
    
    string result;
    FileUtils.get_contents(temp_out, out result);
    FileUtils.remove(temp_out);
    
    return result;
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
    
    var result = new SignatureVerifyResult();
    
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
    // Serialized through the worker queue
    run_gpg_sync(args.to_array(), null, out stdout_str, out stderr_str, out exit_status);
    
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
}

/**
 * Verify signature and get signing key fingerprint (simple version for compatibility)
 */
public static string? get_sign_key(string signature, string? text) throws GLib.Error {
    var result = verify_signature(signature, text);
    return result.key_id;
}

/**
 * Check if the user has any secret (private) keys.
 * Returns true if at least one secret key exists, false otherwise.
 * This is used to avoid attempting decryption when no keys are available.
 * Result is cached to avoid repeated GPG calls.
 * Thread-safe implementation to prevent race conditions.
 */
public static bool has_secret_keys() {
    // Quick check for cached result
    secret_keys_mutex.lock();
    if (has_secret_keys_checked) {
        bool result = has_secret_keys_cached;
        secret_keys_mutex.unlock();
        return result;
    }
    secret_keys_mutex.unlock();
    
    // Not cached, need to query GPG.
    // Do this OUTSIDE secret_keys_mutex to avoid blocking on the queue
    bool found_keys = false;
    try {
        var keys = get_keylist(null, true);  // secret_only = true
        found_keys = keys.size > 0;
        debug("GPGHelper.has_secret_keys: %s", found_keys ? "yes" : "no");
    } catch (Error e) {
        warning("GPGHelper.has_secret_keys: Error checking for keys: %s", e.message);
        found_keys = false;
    }
    
    // Update cache while holding the mutex
    secret_keys_mutex.lock();
    has_secret_keys_cached = found_keys;
    has_secret_keys_checked = true;
    secret_keys_mutex.unlock();
    
    return found_keys;
}

/**
 * Invalidate the has_secret_keys cache (call after key import/generation)
 * Thread-safe implementation.
 */
public static void invalidate_secret_keys_cache() {
    secret_keys_mutex.lock();
    has_secret_keys_checked = false;
    secret_keys_mutex.unlock();
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
    
    // Normalize line endings for cross-platform compatibility
    string normalized = trimmed.replace("\r\n", "\n");
    
    // Additional validation: check for invalid characters in base64 body
    // radix64 uses standard base64 alphabet: A-Z, a-z, 0-9, +, /, =
    // If we find - or _ in the body (not in headers), it's base64url which GPG doesn't understand
    int body_start = normalized.index_of("\n\n");
    if (body_start < 0) {
        // Try single newline after header line
        int first_nl = normalized.index_of("\n");
        if (first_nl > 0) {
            body_start = first_nl;
        }
    }
    if (body_start > 0) {
        string body = normalized.substring(body_start);
        int end_marker = body.index_of("-----END");
        if (end_marker > 0) {
            string key_body = body.substring(0, end_marker);
            // Check for base64url characters that will cause radix64 errors
            // Character 0x2d is '-' (dash)
            if (key_body.contains("-") || key_body.contains("_")) {
                debug("GPGHelper: import_key: Key contains base64url characters (- or _), skipping to avoid radix64 errors");
                return false;
            }
        }
    }
    
    string temp_key = Path.build_filename(Environment.get_tmp_dir(), "dinox-import-%d.asc".printf(Random.int_range(0, 1000000)));
    try {
        FileUtils.set_contents(temp_key, normalized);
    } catch (Error e) {
        warning("GPGHelper: import_key: Failed to write temp file: %s", e.message);
        return false;
    }
    
    string[] args = { "--import", temp_key };
    
    string stdout_str, stderr_str;
    int exit_status;
    run_gpg_sync(args, null, out stdout_str, out stderr_str, out exit_status);
    
    FileUtils.remove(temp_key);
    
    // Don't crash on radix64 errors - just log and return false
    if (exit_status != 0) {
        if (stderr_str != null && (stderr_str.contains("radix64") || stderr_str.contains("invalid packet"))) {
            debug("GPGHelper: import_key: Key has invalid encoding (radix64/packet error), ignoring");
            return false;
        }
        debug("GPGHelper: import_key: GPG returned error %d: %s", exit_status, stderr_str ?? "unknown");
        return false;
    }
    
    // Invalidate has_secret_keys cache so incoming messages can be decrypted immediately
    invalidate_secret_keys_cache();
    debug("GPGHelper: import_key: Success, secret keys cache invalidated");
    
    return true;
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
    
    // Use --recv-keys with the key ID directly (no interactive selection needed)
    // For fingerprints and key IDs, this works without user interaction
    string[] args = { 
        "--keyserver", keyserver, 
        "--keyserver-options", "import-minimal,no-self-sigs-only",
        "--recv-keys", key_id 
    };
    
    string stdout_str, stderr_str;
    int exit_status;
    run_gpg_sync(args, null, out stdout_str, out stderr_str, out exit_status);
    
    // If that failed, try alternative methods
    // keys.openpgp.org may return "no data" or "no user ID" for keys without verified email
    if (exit_status != 0) {
        debug("GPGHelper: HKP failed for %s, stderr: %s", key_id, stderr_str);
        
        // Always try API and Ubuntu keyserver as fallback when HKP fails
        debug("GPGHelper: Key %s not found via HKP, trying direct API download...", key_id);
        
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
    // Normalize key ID to uppercase and remove 0x prefix
    string normalized_id = key_id.up().replace("0X", "").replace(" ", "");
        
        // keys.openpgp.org API endpoint
        // Use by-fingerprint for full fingerprints (40 chars), by-keyid for short IDs (16 chars)
        string url;
        if (normalized_id.length >= 40) {
            url = "https://keys.openpgp.org/vks/v1/by-fingerprint/" + normalized_id;
        } else {
            url = "https://keys.openpgp.org/vks/v1/by-keyid/" + normalized_id;
        }
        
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
        // Use import-minimal to accept keys without user ID (keys.openpgp.org strips unverified UIDs)
        string[] import_args = { "--import-options", "import-minimal", "--import", temp_key };
        string import_stdout, import_stderr;
        int import_exit;
        run_gpg_sync(import_args, null, out import_stdout, out import_stderr, out import_exit);
        
        FileUtils.remove(temp_key);
        
        // Check if import succeeded - GPG may still skip keys without UID
        if (import_stderr.contains("ohne User-ID") || import_stderr.contains("no user ID")) {
            debug("GPGHelper: Key has no User-ID, trying with keep-ownertrust...");
            // Key has no UID - this is a limitation of keys.openpgp.org
            // The key cannot be used for encryption without a UID
            // Return false so we try other sources
            return false;
        }
        
        if (import_exit == 0 || import_stderr.contains("imported") || import_stderr.contains("importiert")) {
            debug("GPGHelper: Successfully imported key %s from API", key_id);
            return true;
        } else {
            debug("GPGHelper: Import from API failed: %s", import_stderr);
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
