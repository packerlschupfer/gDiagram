/*
 * Vala binding for the gvRenderData ABI compatibility wrapper.
 *
 * Use GraphvizCompat.render_data() instead of Gvc.Context.render_data()
 * to avoid stack corruption when linked against the patched Graphviz
 * that uses size_t instead of unsigned int for the length parameter.
 */
[CCode (cheader_filename = "graphviz_compat.h")]
namespace GraphvizCompat {
    [CCode (cname = "gdiagram_gvc_render_data")]
    public static int render_data (
        Gvc.Context context,
        Gvc.Graph graph,
        [CCode (type = "char*")] string format,
        [CCode (array_length_type = "unsigned int", type = "char**")] out uint8[] output_data
    );
}
