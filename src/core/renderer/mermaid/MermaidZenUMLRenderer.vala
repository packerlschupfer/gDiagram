/* MermaidZenUMLRenderer.vala — Mermaid ZenUML renderer */
namespace GDiagram {

/**
 * ZenUML is a sequence diagram: participants with dashed lifelines, nested calls with
 * activation bars, dashed returns, frames for if / loop / opt / par / try blocks and
 * "1.2.1" message numbers. It is laid out by MermaidSeqLayout, like Mermaid's own
 * sequence diagrams; it used to be a numbered Graphviz graph of the participants.
 */
public class MermaidZenUMLRenderer : Object {
    private unowned Gvc.Context ctx;
    private Gee.ArrayList<ElementRegion> regions;

    public MermaidZenUMLRenderer(Gvc.Context ctx,
                                   Gee.ArrayList<ElementRegion> regions,
                                   string engine) {
        this.ctx = ctx;
        this.regions = regions;
    }

    // Participant heads keep their name as the node id (click-to-source finds it)
    private static string head_id(string name) {
        return "\"%s\"".printf(name.replace("\\", "\\\\").replace("\"", "\\\""));
    }

    private static string kind_of(ZenParticipant p) {
        if (p.is_starter) {
            return "starter";
        }
        switch (p.actor_type.down()) {
            case "actor":
            case "boundary":
            case "control":
            case "entity":
            case "database":
            case "collections":
            case "queue":
                return p.actor_type.down();
            default:
                return "participant";
        }
    }

    private static string frame_label(string keyword) {
        switch (keyword) {
            case "if":       return "Alt";
            case "loop":
            case "while":
            case "for":
            case "forEach":  return "Loop";
            case "opt":      return "Opt";
            case "par":      return "Par";
            case "try":      return "Try";
            case "critical": return "Critical";
            default:         return "Section";
        }
    }

    private MermaidSeqLayout build_layout(MermaidZenUML diagram) {
        var lay = new MermaidSeqLayout();
        lay.zen = true;
        lay.title = diagram.title;
        var index = new Gee.HashMap<string, int>();
        foreach (var p in diagram.participants) {
            var lp = new SeqLayParticipant(p.is_starter ? "" : p.name, head_id(p.name));
            lp.foot_id = head_id(p.name + "_end");
            lp.kind = kind_of(p);
            lp.fill = p.color;
            lp.stereotype = p.stereotype;
            lp.line = p.source_line;
            index.set(p.name, lay.participants.size);
            lay.participants.add(lp);
        }
        var seen = new Gee.HashSet<string>();
        foreach (var ev in diagram.events) {
            switch (ev.kind) {
                case ZenEventKind.MESSAGE: {
                    var msg = ev.message;
                    if (!index.has_key(msg.from_name) || !index.has_key(msg.to_name)) {
                        break;
                    }
                    if (msg.is_create && !seen.contains(msg.to_name) && msg.from_name != msg.to_name) {
                        var ce = new SeqLayEvent(SeqLayKind.CREATE);
                        ce.a = index.get(msg.to_name);
                        lay.events.add(ce);
                    }
                    seen.add(msg.from_name);
                    seen.add(msg.to_name);
                    var le = new SeqLayEvent(SeqLayKind.MESSAGE);
                    le.a = index.get(msg.from_name);
                    le.b = index.get(msg.to_name);
                    le.text = msg.method;
                    le.comment = msg.comment;
                    le.number = msg.number;
                    le.line = msg.source_line;
                    le.node_id = "_zm%d".printf(diagram.messages.index_of(msg));
                    if (msg.is_return) {
                        le.dotted = true;
                    } else if (msg.is_async) {
                        le.head = SeqLayHead.OPEN;
                    } else {
                        le.activate_target = !msg.is_create || msg.has_body;
                    }
                    lay.events.add(le);
                    break;
                }
                case ZenEventKind.BODY_END: {
                    if (ev.participant == null || !index.has_key(ev.participant)) {
                        break;
                    }
                    var le = new SeqLayEvent(SeqLayKind.DEACTIVATE);
                    le.a = index.get(ev.participant);
                    lay.events.add(le);
                    break;
                }
                case ZenEventKind.BLOCK_START: {
                    var le = new SeqLayEvent(SeqLayKind.FRAME_START);
                    le.frame_label = frame_label(ev.keyword ?? "");
                    le.text = ev.condition;
                    le.line = ev.source_line;
                    lay.events.add(le);
                    break;
                }
                case ZenEventKind.BLOCK_SECTION: {
                    var le = new SeqLayEvent(SeqLayKind.FRAME_SECTION);
                    le.text = ev.condition;
                    le.line = ev.source_line;
                    lay.events.add(le);
                    break;
                }
                case ZenEventKind.BLOCK_END:
                    lay.events.add(new SeqLayEvent(SeqLayKind.FRAME_END));
                    break;
            }
        }
        return lay;
    }

    public string generate_dot(MermaidZenUML diagram) {
        return build_layout(diagram).generate_dot(ctx);
    }

    public uint8[]? render_to_svg(MermaidZenUML diagram) {
        return build_layout(diagram).render_svg(ctx);
    }

    public Cairo.ImageSurface? render_to_surface(MermaidZenUML diagram) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return null;

        try {
            var stream = new MemoryInputStream.from_data(svg_data);
            var handle = new Rsvg.Handle.from_stream_sync(stream, null, Rsvg.HandleFlags.FLAGS_NONE, null);

            double width, height;
            RenderUtils.svg_page_size(handle, 400, 300, out width, out height);

            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)width, (int)height);
            var cr = new Cairo.Context(surface);

            cr.set_source_rgb(1, 1, 1);
            cr.paint();

            var viewport = Rsvg.Rectangle() {
                x = 0,
                y = 0,
                width = width,
                height = height
            };
            handle.render_document(cr, viewport);

            var element_lines = new Gee.HashMap<string, int>();
            foreach (var p in diagram.participants) {
                if (p.source_line > 0)
                    element_lines.set(p.name, p.source_line);
            }
            for (int i = 0; i < diagram.messages.size; i++) {
                if (diagram.messages[i].source_line > 0) {
                    element_lines.set("_zm%d".printf(i), diagram.messages[i].source_line);
                }
            }
            RenderUtils.parse_svg_regions(svg_data, regions, element_lines, width, height);
            return surface;
        } catch (Error e) {
            warning("Failed to render ZenUML SVG: %s", e.message);
            return null;
        }
    }

    public bool export_to_png(MermaidZenUML diagram, string filename) {
        // The shared path: scaled down to fit the Cairo image size limit
        return RenderUtils.export_svg_to_png(render_to_svg(diagram), filename);
    }

    public bool export_to_svg(MermaidZenUML diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.write_svg_to_file(svg_data, filename);
    }

    public bool export_to_pdf(MermaidZenUML diagram, string filename) {
        uint8[]? svg_data = render_to_svg(diagram);
        if (svg_data == null) return false;
        return RenderUtils.export_svg_to_pdf(svg_data, filename);
    }
}

}
