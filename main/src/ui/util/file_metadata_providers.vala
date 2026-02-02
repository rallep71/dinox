using Dino.Entities;
using Xmpp;
using Xmpp.Xep;
using Gtk;

namespace Dino.Ui.Util {

public class AudioVideoFileMetadataProvider: Dino.FileMetadataProvider, Object {
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
        MediaFile media = MediaFile.for_file(file);
        if (!media.prepared) {
            ulong prepared_sig = 0;
            ulong error_sig = 0;
            uint timeout_id = 0;
            bool resumed = false;

            prepared_sig = media.notify["prepared"].connect((o, p) => {
                if (!resumed) {
                    resumed = true;
                    if (prepared_sig > 0) media.disconnect(prepared_sig);
                    if (error_sig > 0) media.disconnect(error_sig);
                    if (timeout_id > 0) Source.remove(timeout_id);
                    fill_metadata.callback();
                }
            });
            error_sig = media.notify["error"].connect((o, p) => {
                if (!resumed) {
                    resumed = true;
                    if (prepared_sig > 0) media.disconnect(prepared_sig);
                    if (error_sig > 0) media.disconnect(error_sig);
                    if (timeout_id > 0) Source.remove(timeout_id);
                    fill_metadata.callback();
                }
            });
            // 2 seconds timeout to prevent hanging the send process
            timeout_id = Timeout.add(2000, () => {
                if (!resumed) {
                    resumed = true;
                    if (prepared_sig > 0) media.disconnect(prepared_sig);
                    if (error_sig > 0) media.disconnect(error_sig);
                    timeout_id = 0;
                    fill_metadata.callback();
                }
                return Source.REMOVE;
            });

            yield;
        }

        if (media.prepared && media.duration > 0) {
            metadata.length = media.duration / 1000;
        }
    }
}

}
