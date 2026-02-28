namespace Dino.Plugins.BotFeatures {

public class WebhookDispatcher : Object {

    private Soup.Session session;
    private const int MAX_RETRIES = 3;
    private const int TIMEOUT_SECONDS = 10;

    public WebhookDispatcher() {
        session = new Soup.Session();
        session.timeout = TIMEOUT_SECONDS;
    }

    // Dispatch a webhook POST with HMAC-SHA256 signature
    public void dispatch(string url, string secret, string payload) {
        dispatch_async.begin(url, secret, payload);
    }

    private async void dispatch_async(string url, string secret, string payload) {
        string signature = TokenManager.hmac_sha256(secret, payload);

        for (int attempt = 0; attempt < MAX_RETRIES; attempt++) {
            try {
                var msg = new Soup.Message("POST", url);
                msg.set_request_body_from_bytes("application/json",
                    new Bytes.take(payload.data));
                msg.get_request_headers().append("X-Bot-Signature", "sha256=" + signature);
                msg.get_request_headers().append("X-Bot-Delivery", GLib.Uuid.string_random());
                msg.get_request_headers().append("User-Agent", "DinoX-BotAPI/1.0");

                yield session.send_and_read_async(msg, GLib.Priority.DEFAULT, null);

                uint status = msg.get_status();
                if (status >= 200 && status < 300) {
                    return; // Success
                }

                warning("Webhook dispatch to %s returned status %u (attempt %d/%d)",
                    url, status, attempt + 1, MAX_RETRIES);

                // BUG-21 fix: Don't retry client errors (4xx) — they will never succeed
                if (status >= 400 && status < 500) {
                    warning("Webhook: Client error %u, not retrying", status);
                    return;
                }

            } catch (Error e) {
                warning("Webhook dispatch to %s failed: %s (attempt %d/%d)",
                    url, e.message, attempt + 1, MAX_RETRIES);
            }

            // Wait before retry (exponential backoff: 1s, 2s, 4s)
            if (attempt < MAX_RETRIES - 1) {
                yield delay_ms(1000 * (1 << attempt));
            }
        }

        warning("Webhook dispatch to %s failed after %d attempts", url, MAX_RETRIES);
    }

    private async void delay_ms(int ms) {
        GLib.Timeout.add(ms, () => {
            delay_ms.callback();
            return GLib.Source.REMOVE;
        });
        yield;
    }
}

}
