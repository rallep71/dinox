using Gdk;
using GLib;
using Gee;

using Xmpp;
using Xmpp.Xep;
using Dino.Entities;


namespace Dino {
    /**
     * Normalize MIME type - Windows sometimes returns incomplete MIME types
     * like "text" instead of "text/plain"
     */
    public static string normalize_mime_type(string? content_type, string? filename = null) {
        if (content_type == null || content_type == "") {
            return "application/octet-stream";
        }
        
        // If already contains "/", it's valid
        if (content_type.contains("/")) {
            return content_type;
        }
        
        // Windows sometimes returns just the type without subtype
        // Try to guess based on content and filename
        switch (content_type.down()) {
            case "text":
                if (filename != null) {
                    string lower = filename.down();
                    if (lower.has_suffix(".html") || lower.has_suffix(".htm")) return "text/html";
                    if (lower.has_suffix(".css")) return "text/css";
                    if (lower.has_suffix(".js")) return "text/javascript";
                    if (lower.has_suffix(".xml")) return "text/xml";
                    if (lower.has_suffix(".csv")) return "text/csv";
                    if (lower.has_suffix(".md")) return "text/markdown";
                }
                return "text/plain";
            case "image":
                if (filename != null) {
                    string lower = filename.down();
                    if (lower.has_suffix(".png")) return "image/png";
                    if (lower.has_suffix(".jpg") || lower.has_suffix(".jpeg")) return "image/jpeg";
                    if (lower.has_suffix(".gif")) return "image/gif";
                    if (lower.has_suffix(".webp")) return "image/webp";
                    if (lower.has_suffix(".svg")) return "image/svg+xml";
                    if (lower.has_suffix(".bmp")) return "image/bmp";
                }
                return "image/png";
            case "audio":
                if (filename != null) {
                    string lower = filename.down();
                    if (lower.has_suffix(".mp3")) return "audio/mpeg";
                    if (lower.has_suffix(".ogg") || lower.has_suffix(".oga")) return "audio/ogg";
                    if (lower.has_suffix(".wav")) return "audio/wav";
                    if (lower.has_suffix(".m4a")) return "audio/mp4";
                    if (lower.has_suffix(".flac")) return "audio/flac";
                }
                return "audio/mpeg";
            case "video":
                if (filename != null) {
                    string lower = filename.down();
                    if (lower.has_suffix(".mp4") || lower.has_suffix(".m4v")) return "video/mp4";
                    if (lower.has_suffix(".webm")) return "video/webm";
                    if (lower.has_suffix(".ogv")) return "video/ogg";
                    if (lower.has_suffix(".avi")) return "video/x-msvideo";
                    if (lower.has_suffix(".mkv")) return "video/x-matroska";
                }
                return "video/mp4";
            case "application":
                return "application/octet-stream";
            default:
                return "application/octet-stream";
        }
    }

    public interface FileMetadataProvider : Object {
        public abstract bool supports_file(File file);
        public abstract async void fill_metadata(File file, Xep.FileMetadataElement.FileMetadata metadata);
    }

    class GenericFileMetadataProvider: Dino.FileMetadataProvider, Object {
        public bool supports_file(File file) {
            return true;
        }

        public async void fill_metadata(File file, Xep.FileMetadataElement.FileMetadata metadata) {
            debug("GenericFileMetadataProvider: Processing %s", file.get_path());
            FileInfo info;
            try {
                info = file.query_info("*", FileQueryInfoFlags.NONE);
            } catch (GLib.Error e) {
                warning("Failed to query file info: %s", e.message);
                return;
            }

            metadata.name = info.get_display_name();
            metadata.mime_type = normalize_mime_type(info.get_content_type(), metadata.name);
            if (metadata.name.has_suffix(".m4a")) {
                metadata.mime_type = "audio/mp4";
            }
            metadata.size = info.get_size();
            metadata.date = info.get_modification_date_time();

            // Skip hashing for files larger than 50MB to avoid stability issues and long delays
            if (metadata.size < 50 * 1024 * 1024) {
                var checksum_types = new ArrayList<ChecksumType>.wrap(new ChecksumType[] { ChecksumType.SHA256, ChecksumType.SHA512 });
                var file_hashes = yield compute_file_hashes(file, checksum_types);

                metadata.hashes.add(new CryptographicHashes.Hash.with_checksum(ChecksumType.SHA256, file_hashes[ChecksumType.SHA256]));
                metadata.hashes.add(new CryptographicHashes.Hash.with_checksum(ChecksumType.SHA512, file_hashes[ChecksumType.SHA512]));
            }
        }
    }

    public class ImageFileMetadataProvider: Dino.FileMetadataProvider, Object {
        public bool supports_file(File file) {
            string mime_type;
            try {
                var info = file.query_info("*", FileQueryInfoFlags.NONE);
                mime_type = normalize_mime_type(info.get_content_type(), file.get_basename());
            } catch (GLib.Error e) {
                return false;
            }
            return Dino.Util.is_pixbuf_supported_mime_type(mime_type);
        }

        // Delegate to shared FileUtils (clone removal)
        private static bool looks_like_svg_file(File file) {
            return Dino.FileDetectionUtils.looks_like_svg_file(file);
        }

        private const int[] THUMBNAIL_DIMS = { 1, 2, 3, 4, 8 };
        private const string IMAGE_TYPE = "png";
        private const string MIME_TYPE = "image/png";

        public async void fill_metadata(File file, Xep.FileMetadataElement.FileMetadata metadata) {
            debug("ImageFileMetadataProvider: Processing %s", file.get_path());
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

