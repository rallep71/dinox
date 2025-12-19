using Gdk;
using GLib;
using Gee;

using Xmpp;
using Xmpp.Xep;
using Dino.Entities;


namespace Dino {
    public interface FileMetadataProvider : Object {
        public abstract bool supports_file(File file);
        public abstract async void fill_metadata(File file, Xep.FileMetadataElement.FileMetadata metadata);
    }

    class GenericFileMetadataProvider: Dino.FileMetadataProvider, Object {
        public bool supports_file(File file) {
            return true;
        }

        public async void fill_metadata(File file, Xep.FileMetadataElement.FileMetadata metadata) {
            FileInfo info;
            try {
                info = file.query_info("*", FileQueryInfoFlags.NONE);
            } catch (GLib.Error e) {
                warning("Failed to query file info: %s", e.message);
                return;
            }

            metadata.name = info.get_display_name();
            metadata.mime_type = info.get_content_type();
            if (metadata.name.has_suffix(".m4a")) {
                metadata.mime_type = "audio/mp4";
            }
            metadata.size = info.get_size();
            metadata.date = info.get_modification_date_time();

            var checksum_types = new ArrayList<ChecksumType>.wrap(new ChecksumType[] { ChecksumType.SHA256, ChecksumType.SHA512 });
            var file_hashes = yield compute_file_hashes(file, checksum_types);

            metadata.hashes.add(new CryptographicHashes.Hash.with_checksum(ChecksumType.SHA256, file_hashes[ChecksumType.SHA256]));
            metadata.hashes.add(new CryptographicHashes.Hash.with_checksum(ChecksumType.SHA512, file_hashes[ChecksumType.SHA512]));
        }
    }

    public class ImageFileMetadataProvider: Dino.FileMetadataProvider, Object {
        public bool supports_file(File file) {
            string mime_type;
            try {
                mime_type = file.query_info("*", FileQueryInfoFlags.NONE).get_content_type();
            } catch (GLib.Error e) {
                return false;
            }
            return Dino.Util.is_pixbuf_supported_mime_type(mime_type);
        }

        private static bool bytes_contains_ascii_ci(uint8[] data, int data_len, string needle) {
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

        private static bool looks_like_svg_file(File file) {
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

                // gzip magic => likely SVGZ (and in general unsafe for pixbuf decoding here)
                if (len >= 2 && buf[0] == 0x1f && buf[1] == 0x8b) return true;

                if (bytes_contains_ascii_ci(buf, len, "<svg")) return true;
                if (bytes_contains_ascii_ci(buf, len, "<!doctype svg")) return true;
                if (bytes_contains_ascii_ci(buf, len, "http://www.w3.org/2000/svg")) return true;
            } catch (Error e) {
                // If we can't read it, don't assume SVG.
            }

            return false;
        }

        private const int[] THUMBNAIL_DIMS = { 1, 2, 3, 4, 8 };
        private const string IMAGE_TYPE = "png";
        private const string MIME_TYPE = "image/png";

        public async void fill_metadata(File file, Xep.FileMetadataElement.FileMetadata metadata) {
            // Do not invoke the SVG loader (librsvg/gdk-pixbuf) in Flatpak runtimes due to crashes.
            // Some files may be mislabeled (e.g. SVGZ content with image/png mime type).
            if (looks_like_svg_file(file)) {
                return;
            }

            Pixbuf pixbuf;
            try {
                pixbuf = new Pixbuf.from_stream(yield file.read_async());
            } catch (GLib.Error e) {
                warning("Failed to create pixbuf from stream: %s", e.message);
                return;
            }
            metadata.width = pixbuf.get_width();
            metadata.height = pixbuf.get_height();
            float ratio = (float)metadata.width / (float) metadata.height;

            int thumbnail_width = -1;
            int thumbnail_height = -1;
            float diff = float.INFINITY;
            for (int i = 0; i < THUMBNAIL_DIMS.length; i++) {
                int test_width = THUMBNAIL_DIMS[i];
                int test_height = THUMBNAIL_DIMS[THUMBNAIL_DIMS.length - 1 - i];
                float test_ratio = (float)test_width / (float)test_height;
                float test_diff = (test_ratio - ratio).abs();
                if (test_diff < diff) {
                    thumbnail_width = test_width;
                    thumbnail_height = test_height;
                    diff = test_diff;
                }
            }

            Pixbuf thumbnail_pixbuf = pixbuf.scale_simple(thumbnail_width, thumbnail_height, InterpType.BILINEAR);
            uint8[] buffer;
            try {
                thumbnail_pixbuf.save_to_buffer(out buffer, IMAGE_TYPE);
            } catch (GLib.Error e) {
                warning("Failed to save thumbnail to buffer: %s", e.message);
                return;
            }
            var thumbnail = new Xep.JingleContentThumbnails.Thumbnail();
            thumbnail.data = new Bytes.take(buffer);
            thumbnail.media_type = MIME_TYPE;
            thumbnail.width = thumbnail_width;
            thumbnail.height = thumbnail_height;
            metadata.thumbnails.add(thumbnail);
        }
    }
}

