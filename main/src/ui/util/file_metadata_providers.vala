using Dino.Entities;
using Xmpp;
using Xmpp.Xep;
using Gst;

namespace Dino.Ui.Util {

public class AudioVideoFileMetadataProvider: Dino.FileMetadataProvider, GLib.Object {
    public bool supports_file(File file) {
        string? mime_type = null;
        try {
            var info = file.query_info("*", FileQueryInfoFlags.NONE);
            mime_type = Dino.normalize_mime_type(info.get_content_type(), file.get_basename());
        } catch (Error e) {
            warning("Failed to query file info: %s", e.message);
            return false;
        }
        if (mime_type == null) {
            return false;
        }
        return mime_type.has_prefix("audio") || mime_type.has_prefix("video");
    }

    public async void fill_metadata(File file, Xep.FileMetadataElement.FileMetadata metadata) {
        // Use a minimal GStreamer pipeline with ONLY fakesink to query duration.
        // NEVER use Gtk.MediaFile — it creates playbin with autoaudiosink/autovideosink
        // which registers as a PipeWire client and stays open permanently.
        var pipeline = new Gst.Pipeline("metadata-query");
        var src = Gst.ElementFactory.make("uridecodebin", "meta-src");
        var sink = Gst.ElementFactory.make("fakesink", "meta-sink");

        if (src == null || sink == null) {
            warning("Cannot create metadata query pipeline");
            return;
        }

        src.set("uri", file.get_uri());
        pipeline.add_many(src, sink);

        // Dynamic pad linking from uridecodebin
        src.pad_added.connect((pad) => {
            var sink_pad = sink.get_static_pad("sink");
            if (sink_pad != null && !sink_pad.is_linked()) {
                pad.link(sink_pad);
            }
        });

        // Go to PAUSED to let uridecodebin discover the stream
        pipeline.set_state(State.PAUSED);

        Gst.Bus bus = pipeline.get_bus();
        bool got_result = false;

        // Wait for ASYNC_DONE (= pipeline fully prerolled) or ERROR, max 3 seconds
        Gst.Message? msg = bus.timed_pop_filtered(3 * Gst.SECOND,
            Gst.MessageType.ASYNC_DONE | Gst.MessageType.ERROR);

        if (msg != null && msg.type == Gst.MessageType.ASYNC_DONE) {
            int64 duration_ns = 0;
            if (pipeline.query_duration(Gst.Format.TIME, out duration_ns) && duration_ns > 0) {
                // Convert nanoseconds to milliseconds
                metadata.length = (int)(duration_ns / (Gst.SECOND / 1000));
                got_result = true;
            }
        }

        if (!got_result) {
            debug("AudioVideoFileMetadataProvider: could not query duration for %s", file.get_uri());
        }

        // Immediately tear down — no PipeWire entry left behind
        pipeline.set_state(State.NULL);
        pipeline = null;
    }
}

}
