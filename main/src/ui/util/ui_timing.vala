namespace Dino.Ui {

public class UiTiming : Object {
    private static int enabled_cached = -1;

    public static bool enabled() {
        if (enabled_cached == -1) {
            enabled_cached = (Environment.get_variable("DINOX_UI_TIMING") != null) ? 1 : 0;
        }
        return enabled_cached == 1;
    }

    public static int64 now_us() {
        return GLib.get_monotonic_time();
    }

    public static void log_ms(string label, int64 start_us) {
        if (!enabled()) return;
        double ms = (now_us() - start_us) / 1000.0;
        GLib.message("UI-TIMING %s: %.2f ms", label, ms);
    }
}

}
