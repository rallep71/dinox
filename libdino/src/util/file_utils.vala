// File content detection utilities (shared across avatar_manager, sfs_metadata).
// Extracted to eliminate code duplication (clone detection).

namespace Dino.FileDetectionUtils {

    // Case-insensitive byte-level search for an ASCII needle in a binary buffer.
    public static bool bytes_contains_ascii_ci(uint8[] data, int data_len, string needle) {
        if (needle == null || needle == "") return false;
        int nlen = needle.length;
        if (nlen <= 0) return false;
        if (data_len < nlen) return false;

        for (int i = 0; i <= data_len - nlen; i++) {
            bool match = true;
            for (int j = 0; j < nlen; j++) {
                uint8 b = data[i + j];
                char c = (char) b;
                char nc = needle[j];
                if (c >= 'A' && c <= 'Z') c = (char) (c - 'A' + 'a');
                if (nc >= 'A' && nc <= 'Z') nc = (char) (nc - 'A' + 'a');
                if (c != nc) {
                    match = false;
                    break;
                }
            }
            if (match) return true;
        }
        return false;
    }

    // Heuristic SVG/SVGZ detection by extension and magic bytes.
    public static bool looks_like_svg_file(File file) {
        try {
            string? path = file.get_path();
            if (path != null) {
                string lower = path.down();
                if (lower.has_suffix(".svg") || lower.has_suffix(".svgz")) return true;
            }

            FileInputStream s = file.read(null);
            uint8[] buf = new uint8[8192];
            ssize_t n = s.read(buf, null);
            try { s.close(null); } catch (Error e) { }
            if (n <= 0) return false;

            int len = (int) n;
            if (len > (int) buf.length) len = (int) buf.length;

            // gzip magic => likely SVGZ
            if (len >= 2 && buf[0] == 0x1f && buf[1] == 0x8b) return true;
            if (bytes_contains_ascii_ci(buf, len, "<svg")) return true;
            if (bytes_contains_ascii_ci(buf, len, "<!doctype svg")) return true;
            if (bytes_contains_ascii_ci(buf, len, "http://www.w3.org/2000/svg")) return true;
        } catch (Error e) {
            // If we can't read it, don't assume SVG.
        }
        return false;
    }
}
