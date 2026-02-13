using GLib;

namespace Dino.Plugins.BotFeatures {

public class TokenManager : Object {

    private BotRegistry registry;

    public TokenManager(BotRegistry registry) {
        this.registry = registry;
    }

    // Generate a new API token for a bot. Returns the raw token (shown once to user).
    // The SHA-256 hash is stored in the database.
    public string generate_token(int bot_id) {
        string raw_token = create_raw_token(bot_id);
        string hash = hash_token(raw_token);
        registry.update_bot_token_hash(bot_id, hash);
        registry.log_action(bot_id, "token_generated");
        return raw_token;
    }

    // Validate a Bearer token from an API request.
    // Returns the BotInfo if valid, null otherwise.
    public BotInfo? validate_token(string raw_token) {
        string hash = hash_token(raw_token);
        BotInfo? bot = registry.get_bot_by_token_hash(hash);
        if (bot != null && bot.status == "active") {
            registry.update_bot_last_active(bot.id);
            return bot;
        }
        return null;
    }

    // Revoke a bot's token (sets hash to empty, effectively invalidating it)
    public void revoke_token(int bot_id) {
        registry.update_bot_token_hash(bot_id, "");
        registry.log_action(bot_id, "token_revoked");
    }

    // Regenerate token: revoke old, create new
    public string regenerate_token(int bot_id) {
        revoke_token(bot_id);
        return generate_token(bot_id);
    }

    // Create a raw token string: "bot<bot_id>:<uuid4>"
    private string create_raw_token(int bot_id) {
        string uuid = GLib.Uuid.string_random();
        return "bot%d:%s".printf(bot_id, uuid);
    }

    // SHA-256 hash of a token string
    public static string hash_token(string token) {
        Checksum checksum = new Checksum(ChecksumType.SHA256);
        checksum.update((uchar[]) token.data, token.data.length);
        return checksum.get_string();
    }

    // Generate a webhook secret (random 32-byte hex string)
    public static string generate_webhook_secret() {
        string uuid1 = GLib.Uuid.string_random().replace("-", "");
        string uuid2 = GLib.Uuid.string_random().replace("-", "");
        return uuid1 + uuid2;
    }

    // HMAC-SHA256 for webhook signatures
    public static string hmac_sha256(string key, string data) {
        var hmac = new Hmac(ChecksumType.SHA256, (uchar[]) key.data);
        hmac.update((uchar[]) data.data);
        // GLib.Hmac doesn't have get_string(), we need to get the digest
        size_t digest_len = 32;
        uint8[] digest = new uint8[digest_len];
        hmac.get_digest(digest, ref digest_len);
        var sb = new StringBuilder();
        for (int i = 0; i < (int) digest_len; i++) {
            sb.append_printf("%02x", digest[i]);
        }
        return sb.str;
    }
}

}
