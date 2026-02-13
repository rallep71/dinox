namespace Dino.Plugins.BotFeatures {

// Authentication middleware for the HTTP API
public class AuthMiddleware : Object {

    private TokenManager token_manager;
    private RateLimiter rate_limiter;

    public AuthMiddleware(TokenManager token_manager, RateLimiter rate_limiter) {
        this.token_manager = token_manager;
        this.rate_limiter = rate_limiter;
    }

    // Authenticate a request. Returns BotInfo if valid, null if rejected.
    // Sets appropriate error response on the Soup.ServerMessage if rejected.
    public BotInfo? authenticate(Soup.ServerMessage msg) {
        // Extract Bearer token from Authorization header
        var headers = msg.get_request_headers();
        string? auth_header = headers.get_one("Authorization");

        if (auth_header == null || !auth_header.has_prefix("Bearer ")) {
            send_error(msg, 401, "unauthorized", "Missing or invalid Authorization header. Use: Bearer <token>");
            return null;
        }

        string raw_token = auth_header.substring(7).strip();
        if (raw_token.length == 0) {
            send_error(msg, 401, "unauthorized", "Empty token");
            return null;
        }

        // Validate token
        BotInfo? bot = token_manager.validate_token(raw_token);
        if (bot == null) {
            send_error(msg, 401, "unauthorized", "Invalid or revoked token");
            return null;
        }

        // Rate limiting
        if (!rate_limiter.check(bot.id)) {
            int retry = rate_limiter.retry_after(bot.id);
            msg.get_response_headers().append("Retry-After", retry.to_string());
            send_error(msg, 429, "rate_limited", "Too many requests. Retry after %d seconds.".printf(retry));
            return null;
        }

        return bot;
    }

    public static void send_error(Soup.ServerMessage msg, uint status_code, string error_code, string description) {
        string json = "{\"ok\":false,\"error\":\"%s\",\"description\":\"%s\"}".printf(
            error_code, description.replace("\"", "\\\"")
        );
        msg.set_status(status_code, null);
        msg.set_response("application/json", Soup.MemoryUse.COPY, json.data);
    }

    public static void send_success(Soup.ServerMessage msg, string result_json) {
        string json = "{\"ok\":true,\"result\":%s}".printf(result_json);
        msg.set_status(200, null);
        msg.set_response("application/json", Soup.MemoryUse.COPY, json.data);
    }
}

}
