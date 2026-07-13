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
#include <stdio.h>
#include <string.h>

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

/*
 * Graphviz writes diagnostics straight to stderr through agerr(). One of them is
 * noise for us: with splines=ortho it warns "Orthogonal edges do not currently
 * handle edge labels. Try using xlabels." on every labelled edge. We use labels
 * there deliberately — an xlabel is placed after layout, knows nothing about
 * clusters, and ended up drawn on container borders and clipped by their titles —
 * and a post-pass moves any label a line still runs through. The warning is
 * therefore not actionable by the user, and it reached them on every class diagram
 * with a labelled link. Everything else Graphviz says still goes to stderr.
 */
/*
 * agerr() reports one diagnostic in three calls: the level ("Warning"), the separator
 * (": ") and then the message. The first two are therefore held back until the message
 * arrives, and all three are dropped together when it is the one we silence; otherwise
 * what was held is printed first, so other diagnostics read exactly as before.
 */
static char gdiagram_agerr_held[128];
static size_t gdiagram_agerr_held_len = 0;

static int gdiagram_agerr_is_prefix(const char *text) {
    return strcmp(text, "Warning") == 0 || strcmp(text, "Error") == 0 ||
           strcmp(text, "Fatal") == 0   || strcmp(text, ": ") == 0;
}

static int gdiagram_agerr_filter(char *text) {
    if (text == NULL) {
        return 0;
    }
    if (gdiagram_agerr_is_prefix(text)) {
        size_t room = sizeof gdiagram_agerr_held - gdiagram_agerr_held_len - 1;
        if (room > 0) {
            strncat(gdiagram_agerr_held, text, room);
            gdiagram_agerr_held_len = strlen(gdiagram_agerr_held);
        }
        return 0;
    }
    if (strstr(text, "Orthogonal edges do not currently handle edge labels") != NULL) {
        gdiagram_agerr_held[0] = '\0';
        gdiagram_agerr_held_len = 0;
        return 0;
    }
    if (gdiagram_agerr_held_len > 0) {
        fputs(gdiagram_agerr_held, stderr);
        gdiagram_agerr_held[0] = '\0';
        gdiagram_agerr_held_len = 0;
    }
    return fputs(text, stderr);
}

void gdiagram_gvc_quiet_ortho_label_warning(void) {
    agseterrf(gdiagram_agerr_filter);
}
