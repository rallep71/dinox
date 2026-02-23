using GLib;

namespace Dino.Security {

public class KeyManager : Object {
    private const string SCHEMA_NAME = "im.dino.omemo.database.key";
    private const string KEY_LABEL = "DinoX OMEMO Database Key";
    private const string KEY_ATTRIBUTE = "db_name";
    private const string KEY_VALUE = "omemo.db";

    /**
     * Get or create the OMEMO database encryption key.
     * On Windows (or when org.freedesktop.secrets is unavailable):
     *   stores the key in a file at <config_dir>/dinox/omemo.key
     * On Linux with working secrets service:
     *   stores the key in the GNOME Keyring / KDE Wallet via libsecret
     */
    public static string get_or_create_db_key() throws Error {
        // Always try file-based key first (works everywhere, required on Windows)
        string? file_key = try_file_based_key();
        if (file_key != null) {
            return file_key;
        }

#if !WINDOWS
        // On Linux, try the secrets service (GNOME Keyring / KDE Wallet)
        try {
            string? secret_key = try_secrets_service();
            if (secret_key != null) {
                return secret_key;
            }
        } catch (Error e) {
            // Secrets service not available (e.g. no D-Bus, Wayland without keyring, etc.)
            // Fall through to generate a new file-based key
            warning("KeyManager: Secrets service unavailable (%s), using file-based key storage", e.message);
        }
#endif

        // No existing key found anywhere — generate a new one
        return generate_new_file_key();
    }

    /**
     * Try to read existing key from file, or return null if no key file exists.
     * Throws if key file exists but is unreadable (to prevent data loss).
     */
    private static string? try_file_based_key() throws Error {
        string key_dir = get_key_dir();
        string key_file_path = Path.build_filename(key_dir, "omemo.key");
        File key_file = File.new_for_path(key_file_path);

        if (key_file.query_exists()) {
            try {
                uint8[] content;
                if (key_file.load_contents(null, out content, null)) {
                    string key_str = ((string)content).strip();
                    if (key_str.length > 0) {
                        debug("KeyManager: Loaded key from file %s", key_file_path);
                        return key_str;
                    }
                }
            } catch (Error e) {
                // CRITICAL: If we can't read an existing key file, we MUST NOT generate a new one
                // as this would make the existing omemo.db unreadable!
                warning("KeyManager: Could not read existing key file: %s", e.message);
                throw new IOError.FAILED("Cannot read existing OMEMO key file at %s. Database would become inaccessible.", key_file_path);
            }
        }

        return null;
    }

#if !WINDOWS
    /**
     * Try to get key from the system secrets service (libsecret / GNOME Keyring).
     * Returns null if no key stored yet, throws if the service is not available.
     */
    private static string? try_secrets_service() throws Error {
        var schema = new Secret.Schema(SCHEMA_NAME, Secret.SchemaFlags.NONE,
            KEY_ATTRIBUTE, Secret.SchemaAttributeType.STRING
        );

        string? password = Secret.password_lookup_sync(schema, null, KEY_ATTRIBUTE, KEY_VALUE);

        if (password != null) {
            debug("KeyManager: Loaded key from secrets service");
            return password;
        }

        // No key stored yet — generate one and store it in the secrets service
        uint8[] key_bytes = new uint8[32];
        var file = File.new_for_path("/dev/urandom");
        var input = file.read();
        size_t bytes_read;
        input.read_all(key_bytes, out bytes_read);
        if (bytes_read != 32) {
            throw new IOError.FAILED("Could not read enough random bytes from /dev/urandom");
        }

        StringBuilder hex = new StringBuilder();
        foreach (uint8 b in key_bytes) {
            hex.append_printf("%02x", b);
        }
        string new_key = hex.str;

        Secret.password_store_sync(schema, Secret.COLLECTION_DEFAULT, KEY_LABEL, new_key, null, KEY_ATTRIBUTE, KEY_VALUE);
        debug("KeyManager: Generated and stored new key in secrets service");

        return new_key;
    }
#endif

    /**
     * Generate a new file-based key and save it.
     * Only allowed when no omemo.db exists yet (to prevent orphaning an existing DB).
     */
    private static string generate_new_file_key() throws Error {
        string key_dir = get_key_dir();

        // Safety check: if omemo.db exists but no key file, we MUST NOT generate a new key
        string omemo_db_path = Path.build_filename(key_dir, "omemo.db");
        if (FileUtils.test(omemo_db_path, FileTest.EXISTS)) {
            throw new IOError.FAILED("OMEMO database exists at %s but key file is missing. Cannot recover — would make database inaccessible.", omemo_db_path);
        }

        // Generate 32 random bytes as hex key using CSPRNG
        uint8[] key_bytes = new uint8[32];
        Crypto.randomize(key_bytes);  // Uses GCrypt CSPRNG, not Mersenne Twister

        StringBuilder hex = new StringBuilder();
        foreach (uint8 b in key_bytes) {
            hex.append_printf("%02x", b);
        }
        string new_key = hex.str;

        // Save to file
        if (!FileUtils.test(key_dir, FileTest.EXISTS)) {
            DirUtils.create_with_parents(key_dir, 0700);
        }
        string key_file_path = Path.build_filename(key_dir, "omemo.key");
        File key_file = File.new_for_path(key_file_path);
        key_file.replace_contents(new_key.data, null, false, FileCreateFlags.PRIVATE, null);

        debug("KeyManager: Generated and saved new key to %s", key_file_path);
        return new_key;
    }

    /**
     * Get the directory for storing key files.
     */
    private static string get_key_dir() {
        string config_dir = Environment.get_user_data_dir();
        return Path.build_filename(config_dir, "dinox");
    }
}

}
