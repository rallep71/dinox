#include <gst/video/video.h>

GstVideoInfo *gst_video_frame_get_video_info(GstVideoFrame *frame) {
    return &frame->info;
}

void *gst_video_frame_get_data(GstVideoFrame *frame, size_t* length) {
    *length = frame->info.height * frame->info.stride[0];
    return frame->data[0];
}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
GList *rtp_get_source_stats_structures(const GstStructure *stats) {
    GList *list = NULL;
    const GValue *val;
    GValueArray *arr;
    guint i;

    val = gst_structure_get_value(stats, "source-stats");
    if (!val) return NULL;

    // G_TYPE_VALUE_ARRAY is deprecated, but rtpbin uses it.
    // We use g_type_from_name to avoid the deprecation warning.
    GType type_value_array = g_type_from_name("GValueArray");
    if (type_value_array == G_TYPE_INVALID || !G_VALUE_HOLDS(val, type_value_array)) return NULL;

    arr = g_value_get_boxed(val);
    if (!arr) return NULL;

    for (i = 0; i < arr->n_values; i++) {
        GValue *v = g_value_array_get_nth(arr, i);
        if (G_VALUE_HOLDS(v, GST_TYPE_STRUCTURE)) {
            GstStructure *s = g_value_get_boxed(v);
            list = g_list_prepend(list, s);
        }
    }
    
    return g_list_reverse(list);
}
#pragma GCC diagnostic pop
