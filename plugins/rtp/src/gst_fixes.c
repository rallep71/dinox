#include <gst/gst.h>
#include <gst/video/video.h>

GstVideoInfo *gst_video_frame_get_video_info(GstVideoFrame *frame) {
    return &frame->info;
}

void *gst_video_frame_get_data(GstVideoFrame *frame, size_t* length) {
    *length = frame->info.height * frame->info.stride[0];
    return frame->data[0];
}

GstPadProbeReturn rtp_deep_copy_buffer_probe(GstPad *pad, GstPadProbeInfo *info, gpointer user_data) {
    GstBuffer *buf = GST_PAD_PROBE_INFO_BUFFER(info);
    if (!buf) return GST_PAD_PROBE_OK;

    guint n = gst_buffer_n_memory(buf);
    if (n == 0) return GST_PAD_PROBE_OK;

    // Pin every memory block by keeping it mapped during the entire deep-copy.
    // The old validate-then-copy approach had a TOCTOU race: PipeWire could
    // recycle DMA-BUF backing memory between our unmap and gst_buffer_copy_deep,
    // causing SIGSEGV inside gst_buffer_copy_into / memmove.
    GstMapInfo *maps = g_newa(GstMapInfo, n);
    guint mapped = 0;
    for (guint i = 0; i < n; i++) {
        GstMemory *mem = gst_buffer_peek_memory(buf, i);
        if (!mem || !gst_memory_map(mem, &maps[i], GST_MAP_READ)) {
            for (guint j = 0; j < mapped; j++) {
                gst_memory_unmap(gst_buffer_peek_memory(buf, j), &maps[j]);
            }
            return GST_PAD_PROBE_DROP;
        }
        mapped++;
    }

    // Memory is pinned — deep copy is safe
    GstBuffer *copy = gst_buffer_copy_deep(buf);

    for (guint i = 0; i < mapped; i++) {
        gst_memory_unmap(gst_buffer_peek_memory(buf, i), &maps[i]);
    }

    if (copy) {
        gst_buffer_unref(buf);
        info->data = copy;
    }
    return GST_PAD_PROBE_OK;
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
