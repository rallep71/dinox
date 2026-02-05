using GLib;

namespace Dino.Security {

public class KeyManager : Object {
    private const string SCHEMA_NAME = "im.dino.omemo.database.key";
    private const string KEY_LABEL = "DinoX OMEMO Database Key";
    private const string KEY_ATTRIBUTE = "db_name";
    private const string KEY_VALUE = "omemo.db";

    public static string get_or_create_db_key() throws Error {
#if WINDOWS
        string config_dir = Environment.get_user_data_dir(); // e.g. AppData/Local
        string key_dir = Path.build_filename(config_dir, "dinox");
        string key_file_path = Path.build_filename(key_dir, "omemo.key");
        File key_file = File.new_for_path(key_file_path);

        if (key_file.query_exists()) {
            try {
                uint8[] content;
                if (key_file.load_contents(null, out content, null)) {
                    string key_str = ((string)content).strip();
                    if (key_str.length > 0) return key_str;
                }
            } catch (Error e) {
                // CRITICAL: If we can't read an existing key file, we MUST NOT generate a new one
                // as this would make the existing omemo.db unreadable!
                warning("KeyManager: Could not read existing key file: %s", e.message);
                throw new IOError.FAILED("Cannot read existing OMEMO key file. Database would become inaccessible.");
            }
        }

        // Only generate new key if the file does NOT exist
        // Check if omemo.db exists - if so, we MUST NOT generate a new key
        string omemo_db_path = Path.build_filename(key_dir, "omemo.db");
        if (FileUtils.test(omemo_db_path, FileTest.EXISTS)) {
            throw new IOError.FAILED("OMEMO database exists but key file is missing. Cannot recover.");
        }

        // Generate new key (Simple fallback for Windows)
        uint8[] key_bytes = new uint8[32];
        for(int i=0; i<32; i++) {
            key_bytes[i] = (uint8) Random.int_range(0, 256);
        }

        StringBuilder hex = new StringBuilder();
        foreach (uint8 b in key_bytes) {
            hex.append_printf("%02x", b);
        }
        string new_key = hex.str;

        try {
            if (!FileUtils.test(key_dir, FileTest.EXISTS)) {
                DirUtils.create_with_parents(key_dir, 0700);
            }
            key_file.replace_contents(new_key.data, null, false, FileCreateFlags.PRIVATE, null);
        } catch (Error e) {
            warning("KeyManager: Failed to save key file: %s", e.message);
        }
        
        return new_key;
#else
        var schema = new Secret.Schema(SCHEMA_NAME, Secret.SchemaFlags.NONE,
            KEY_ATTRIBUTE, Secret.SchemaAttributeType.STRING
        );

        string? password = Secret.password_lookup_sync(schema, null, KEY_ATTRIBUTE, KEY_VALUE);

        if (password != null) {
            return password;
        }

        // Generate new key from /dev/urandom
        uint8[] key_bytes = new uint8[32];
        try {
            var file = File.new_for_path("/dev/urandom");
            var input = file.read();
            size_t bytes_read;
            input.read_all(key_bytes, out bytes_read);
            if (bytes_read != 32) {
                throw new IOError.FAILED("Could not read enough random bytes");
            }
        } catch (Error e) {
            warning("KeyManager: Failed to generate random key: %s", e.message);
            throw e;
        }
        
        StringBuilder hex = new StringBuilder();
        foreach (uint8 b in key_bytes) {
            hex.append_printf("%02x", b);
        }
        string new_key = hex.str;

        Secret.password_store_sync(schema, Secret.COLLECTION_DEFAULT, KEY_LABEL, new_key, null, KEY_ATTRIBUTE, KEY_VALUE);
        
        return new_key;
#endif
    }
}

}
