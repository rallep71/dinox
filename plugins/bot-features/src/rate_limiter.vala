using Gee;

namespace Dino.Plugins.BotFeatures {

public class RateLimiter : Object {

    // Per-bot rate limiting: max requests per window
    private int max_requests;
    private int window_seconds;
    private HashMap<int, RateWindow> windows = new HashMap<int, RateWindow>();

    public RateLimiter(int max_requests = 30, int window_seconds = 1) {
        this.max_requests = max_requests;
        // Guard: window_seconds must be at least 1 to prevent bypass
        this.window_seconds = window_seconds > 0 ? window_seconds : 1;
    }

    // Returns true if the request is allowed, false if rate limited
    public bool check(int bot_id) {
        int64 now = new DateTime.now_utc().to_unix();

        if (!windows.has_key(bot_id)) {
            windows[bot_id] = new RateWindow();
        }

        RateWindow w = windows[bot_id];

        // Reset window if expired
        if (now - w.window_start >= window_seconds) {
            w.window_start = now;
            w.request_count = 0;
        }

        if (w.request_count >= max_requests) {
            return false;
        }

        w.request_count++;
        return true;
    }

    // Get seconds until next window reset for a bot
    public int retry_after(int bot_id) {
        if (!windows.has_key(bot_id)) return 0;
        RateWindow w = windows[bot_id];
        int64 now = new DateTime.now_utc().to_unix();
        int remaining = window_seconds - (int)(now - w.window_start);
        return remaining > 0 ? remaining : 0;
    }

    // Cleanup stale windows periodically
    public void cleanup() {
        int64 now = new DateTime.now_utc().to_unix();
        var to_remove = new ArrayList<int>();
        foreach (var entry in windows.entries) {
            // Use int64 multiplication to prevent overflow with large window_seconds
            if (now - entry.value.window_start > (int64) window_seconds * 10) {
                to_remove.add(entry.key);
            }
        }
        foreach (int key in to_remove) {
            windows.unset(key);
        }
    }

    private class RateWindow {
        public int64 window_start = 0;
        public int request_count = 0;
    }
}

}
