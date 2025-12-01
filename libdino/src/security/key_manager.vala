using GLib;

namespace Dino.Security {

public class KeyManager : Object {
    private const string SCHEMA_NAME = "im.dino.omemo.database.key";
    private const string KEY_LABEL = "DinoX OMEMO Database Key";
    private const string KEY_ATTRIBUTE = "db_name";
    private const string KEY_VALUE = "omemo.db";

    public static string get_or_create_db_key() throws Error {
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
    }
}

}
