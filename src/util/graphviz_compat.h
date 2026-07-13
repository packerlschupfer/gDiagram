#ifndef GRAPHVIZ_COMPAT_H
#define GRAPHVIZ_COMPAT_H

#include <gvc.h>

int gdiagram_gvc_render_data(GVC_t *gvc, graph_t *g, const char *format,
                              char **result, unsigned int *length);

#endif /* GRAPHVIZ_COMPAT_H */
