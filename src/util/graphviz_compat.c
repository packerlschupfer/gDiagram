/*
 * graphviz_compat.c - ABI compatibility wrapper for gvRenderData
 *
 * Upstream Graphviz (merged in 8160ee4f) changed gvRenderData's length
 * parameter from `unsigned int *` to `size_t *`. Older system packages
 * still use `unsigned int *`. The Vala VAPI declares `unsigned int`, so
 * on builds against the new API (size_t) we need to bridge the mismatch
 * to avoid stack corruption on 64-bit (size_t = 8 bytes, uint = 4 bytes).
 *
 * Meson detects which signature is available and defines
 * GRAPHVIZ_RENDER_DATA_SIZE_T when the size_t variant is found.
 */

#include <gvc.h>
#include <stddef.h>

int gdiagram_gvc_render_data(GVC_t *gvc, graph_t *g, const char *format,
                              char **result, unsigned int *length) {
#ifdef GRAPHVIZ_RENDER_DATA_SIZE_T
    /* Patched Graphviz uses size_t* for the length parameter */
    size_t actual_length = 0;
    int ret = gvRenderData(gvc, g, format, result, &actual_length);
    if (length != NULL) {
        *length = (unsigned int)actual_length;
    }
#else
    /* System Graphviz uses unsigned int* — pass through directly */
    int ret = gvRenderData(gvc, g, format, result, length);
#endif
    return ret;
}
