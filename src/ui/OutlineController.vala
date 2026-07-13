namespace GDiagram {
    /**
     * Populates the outline sidebar list from a parsed diagram AST.
     *
     * DocumentView owns the outline widgets (the ListBox, revealer, stats bar
     * and lint/validate/complexity buttons) and passes the ListBox in here.
     * The controller owns only the *content* population: the per-diagram-type
     * update_outline_from_* methods and the dispatch that picks one for the
     * rendered type.
     *
     * Row activation (click-to-source) is wired here — the controller extracts
     * the searchable label text from the clicked row and emits
     * navigate_to_element(); DocumentView connects that signal to its own
     * text-search + preview-highlight logic (which needs the source buffer and
     * preview pane it still owns).
     */
    public class OutlineController : Object {
        private Gtk.ListBox outline_list;

        // Emitted when the user activates an outline row. The argument is the
        // cleaned-up search key (first label segment) DocumentView should
        // navigate to in the source and highlight in the preview.
        public signal void navigate_to_element(string search_key);

        public OutlineController(Gtk.ListBox outline_list) {
            this.outline_list = outline_list;

            // Handle row activation to navigate to the element.
            // The displayed label is the cleaned-up form — "Customer / A
            // logged-in shopper" — while the source has the original
            // "Customer\nA logged-in shopper". Search for just the first
            // segment (the primary label) which is much more likely to be
            // unique enough to land on the right line.
            outline_list.row_activated.connect((row) => {
                var box = row.child as Gtk.Box;
                if (box == null) return;
                var child = box.get_first_child();
                if (child == null) return;
                child = child.get_next_sibling();  // Skip icon
                var label = child as Gtk.Label;
                if (label == null) return;

                string text = label.label;
                // Strip leading whitespace — mindmap/gantt rows use "  " to
                // indicate nesting in the outline but the source has no
                // indent prefix.
                text = text.strip();
                if (text.length == 0) return;
                // If the label starts with "Foo: bar" (e.g. "Title: ..."),
                // drop the "Foo: " prefix so we search for the content.
                int colon = text.index_of(":");
                if (colon > 0 && colon < text.length - 1 && text[colon + 1] == ' ') {
                    text = text.substring(colon + 2).strip();
                }
                if (text.length == 0) return;
                // Use only the first / -separated segment. The outline formats
                // multi-line element labels as "primary / description" where
                // `primary` is what appears in the source.
                int slash = text.index_of(" / ");
                string search_key = slash > 0 ? text.substring(0, slash) : text;
                search_key = search_key.strip();
                if (search_key.length == 0) return;
                navigate_to_element(search_key);
            });
        }

        // Dispatch: pick the per-type population method for the rendered
        // diagram. Generic Graphviz-passthrough PlantUML types have no AST and
        // leave the outline untouched.
        public void update(DiagramType diagram_type, Object? ast) {
            switch (diagram_type) {
                case DiagramType.MERMAID_FLOWCHART:
                    update_outline_from_mermaid_flowchart((MermaidFlowchart) ast);
                    break;
                case DiagramType.MERMAID_SEQUENCE:
                    update_outline_from_mermaid_sequence((MermaidSequenceDiagram) ast);
                    break;
                case DiagramType.MERMAID_STATE:
                    update_outline_from_mermaid_state((MermaidStateDiagram) ast);
                    break;
                case DiagramType.MERMAID_CLASS:
                    update_outline_from_mermaid_class((MermaidClassDiagram) ast);
                    break;
                case DiagramType.MERMAID_ER:
                    update_outline_from_mermaid_er((MermaidERDiagram) ast);
                    break;
                case DiagramType.MERMAID_GANTT:
                    update_outline_from_mermaid_gantt((MermaidGantt) ast);
                    break;
                case DiagramType.MERMAID_PIE:
                    update_outline_from_mermaid_pie((MermaidPie) ast);
                    break;
                case DiagramType.MERMAID_USER_JOURNEY:
                    update_outline_from_mermaid_user_journey((MermaidUserJourney) ast);
                    break;
                case DiagramType.MERMAID_GIT_GRAPH:
                    update_outline_from_mermaid_git_graph((MermaidGitGraph) ast);
                    break;
                case DiagramType.MERMAID_MINDMAP:
                    update_outline_from_mermaid_mindmap((MermaidMindmap) ast);
                    break;
                case DiagramType.MERMAID_TIMELINE:
                    update_outline_from_mermaid_timeline((MermaidTimeline) ast);
                    break;
                case DiagramType.MERMAID_QUADRANT:
                    update_outline_from_mermaid_quadrant((MermaidQuadrant) ast);
                    break;
                case DiagramType.MERMAID_XYCHART:
                    update_outline_from_mermaid_xychart((MermaidXYChart) ast);
                    break;
                case DiagramType.MERMAID_KANBAN:
                    update_outline_from_mermaid_kanban((MermaidKanban) ast);
                    break;
                case DiagramType.MERMAID_SANKEY:
                    update_outline_from_mermaid_sankey((MermaidSankey) ast);
                    break;
                case DiagramType.MERMAID_REQUIREMENT:
                    update_outline_from_mermaid_requirement((MermaidRequirement) ast);
                    break;
                case DiagramType.MERMAID_BLOCK:
                    update_outline_from_mermaid_block((MermaidBlock) ast);
                    break;
                case DiagramType.MERMAID_PACKET:
                    update_outline_from_mermaid_packet((MermaidPacket) ast);
                    break;
                case DiagramType.MERMAID_C4:
                    update_outline_from_mermaid_c4((MermaidC4) ast);
                    break;
                case DiagramType.MERMAID_ARCHITECTURE:
                    update_outline_from_mermaid_architecture((MermaidArchitecture) ast);
                    break;
                case DiagramType.MERMAID_ZENUML:
                    update_outline_from_mermaid_zenuml((MermaidZenUML) ast);
                    break;
                case DiagramType.MERMAID_RADAR:
                    update_outline_from_mermaid_radar((MermaidRadar) ast);
                    break;
                case DiagramType.MERMAID_TREEMAP:
                    update_outline_from_mermaid_treemap((MermaidTreemap) ast);
                    break;
                case DiagramType.CLASS:
                    update_outline_from_class_diagram((ClassDiagram) ast);
                    break;
                case DiagramType.ACTIVITY:
                    update_outline_from_activity_diagram((ActivityDiagram) ast);
                    break;
                case DiagramType.USECASE:
                    update_outline_from_usecase_diagram((UseCaseDiagram) ast);
                    break;
                case DiagramType.STATE:
                    update_outline_from_state_diagram((StateDiagram) ast);
                    break;
                case DiagramType.COMPONENT:
                    update_outline_from_component_diagram((ComponentDiagram) ast);
                    break;
                case DiagramType.OBJECT:
                    update_outline_from_object_diagram((ObjectDiagram) ast);
                    break;
                case DiagramType.DEPLOYMENT:
                    update_outline_from_deployment_diagram((DeploymentDiagram) ast);
                    break;
                case DiagramType.ER_DIAGRAM:
                    update_outline_from_er_diagram((ERDiagram) ast);
                    break;
                case DiagramType.MINDMAP:
                case DiagramType.WBS:
                    update_outline_from_mindmap_diagram((MindMapDiagram) ast);
                    break;
                case DiagramType.GANTT:
                    update_outline_from_gantt_diagram((PumlGanttDiagram) ast);
                    break;
                case DiagramType.JSON_DIAGRAM:
                    update_outline_from_json_diagram((JsonDiagram) ast);
                    break;
                case DiagramType.YAML_DIAGRAM:
                    update_outline_from_yaml_diagram((YamlDiagram) ast);
                    break;
                case DiagramType.CHRONOLOGY:
                    update_outline_from_chronology_diagram((ChronologyDiagram) ast);
                    break;
                case DiagramType.TIMING:
                    update_outline_from_timing_diagram((TimingDiagram) ast);
                    break;
                case DiagramType.NWDIAG:
                    update_outline_from_nwdiag_diagram((NwdiagDiagram) ast);
                    break;
                case DiagramType.ARCHIMATE:
                    update_outline_from_archimate_diagram((ArchimateDiagram) ast);
                    break;
                case DiagramType.SEQUENCE:
                    update_outline_from_sequence_diagram((SequenceDiagram) ast);
                    break;
                default:
                    // Generic Graphviz-passthrough PlantUML types: no outline AST.
                    break;
            }
        }

        private void clear_outline() {
            while (outline_list.get_first_child() != null) {
                outline_list.remove(outline_list.get_first_child());
            }
        }

        // ==================== PlantUML outline population ====================

        private void update_outline_from_class_diagram(ClassDiagram diagram) {
            clear_outline();

            // Add title if present
            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add classes
            foreach (var c in diagram.classes) {
                string icon = "view-list-symbolic";
                if (c.class_type == ClassType.INTERFACE) {
                    icon = "view-list-bullet-symbolic";
                } else if (c.class_type == ClassType.ABSTRACT) {
                    icon = "view-list-compact-symbolic";
                }
                add_outline_item(c.name, icon);
            }
        }

        private void update_outline_from_sequence_diagram(SequenceDiagram diagram) {
            clear_outline();

            // Add title if present
            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add participants
            foreach (var p in diagram.participants) {
                add_outline_item(p.name, "avatar-default-symbolic");
            }
        }

        private void update_outline_from_activity_diagram(ActivityDiagram diagram) {
            clear_outline();

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add main activities/actions
            foreach (var node in diagram.nodes) {
                string icon = "system-run-symbolic";
                if (node.node_type == ActivityNodeType.START) {
                    add_outline_item("Start", "media-playback-start-symbolic");
                } else if (node.node_type == ActivityNodeType.STOP) {
                    add_outline_item("Stop", "media-playback-stop-symbolic");
                } else if (node.node_type == ActivityNodeType.ACTION && node.label != null) {
                    add_outline_item(node.label, icon);
                } else if (node.partition != null) {
                    add_outline_item("Partition: " + node.partition, "view-list-symbolic");
                }
            }
        }

        private void update_outline_from_state_diagram(StateDiagram diagram) {
            clear_outline();

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add states
            foreach (var state in diagram.states) {
                string icon = "view-grid-symbolic";
                string display_name = state.label ?? state.id;
                add_outline_item(display_name, icon);
            }
        }

        private void update_outline_from_usecase_diagram(UseCaseDiagram diagram) {
            clear_outline();

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add actors
            foreach (var actor in diagram.actors) {
                add_outline_item(actor.name, "avatar-default-symbolic");
            }

            // Add use cases
            foreach (var uc in diagram.use_cases) {
                add_outline_item(uc.name, "emblem-system-symbolic");
            }

            // Add packages
            foreach (var pkg in diagram.packages) {
                add_outline_item(pkg.name, "folder-symbolic");
            }
        }

        private void update_outline_from_component_diagram(ComponentDiagram diagram) {
            clear_outline();

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add components
            foreach (var comp in diagram.components) {
                string display_name = comp.label ?? comp.id;
                add_outline_item(display_name, "package-x-generic-symbolic");
            }

            // Add interfaces
            foreach (var iface in diagram.interfaces) {
                string display_name = iface.label ?? iface.id;
                add_outline_item(display_name, "view-list-bullet-symbolic");
            }
        }

        private void update_outline_from_object_diagram(ObjectDiagram diagram) {
            clear_outline();

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add objects
            foreach (var obj in diagram.objects) {
                add_outline_item(obj.name, "view-list-bullet-symbolic");
            }
        }

        private void update_outline_from_deployment_diagram(DeploymentDiagram diagram) {
            clear_outline();

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add nodes
            foreach (var node in diagram.nodes) {
                string display_name = node.label ?? node.id;
                add_outline_item(display_name, "computer-symbolic");
            }
        }

        private void update_outline_from_er_diagram(ERDiagram diagram) {
            clear_outline();

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add entities
            foreach (var entity in diagram.entities) {
                add_outline_item(entity.name, "view-list-symbolic");
            }
        }

        private void update_outline_from_mindmap_diagram(MindMapDiagram diagram) {
            clear_outline();

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add root node and its children
            if (diagram.root != null) {
                add_outline_item(diagram.root.text, "view-paged-symbolic");
                foreach (var child in diagram.root.children) {
                    add_outline_item("  " + child.text, "view-paged-symbolic");
                }
            }
        }

        private void update_outline_from_gantt_diagram(PumlGanttDiagram diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            string? current_section = null;
            foreach (var task in diagram.tasks) {
                if (task.section != null && task.section != current_section) {
                    current_section = task.section;
                    add_outline_item("── %s".printf(task.section), "folder-symbolic");
                }
                string icon = task.is_milestone ? "starred-symbolic" : "view-list-bullet-symbolic";
                add_outline_item("%s (%d days)".printf(task.name, task.duration_days), icon);
            }
        }

        private void update_outline_from_json_diagram(JsonDiagram diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            if (diagram.root != null && !diagram.root.is_leaf()) {
                foreach (var child in diagram.root.children) {
                    string key = child.key ?? "";
                    if (child.is_leaf()) {
                        add_outline_item("%s: %s".printf(key, child.get_display_value()), "view-list-bullet-symbolic");
                    } else {
                        string type_hint = (child.node_type == JsonNodeType.OBJECT) ? "{ }" : "[ ]";
                        add_outline_item("%s %s".printf(key, type_hint), "folder-symbolic");
                    }
                }
            }
        }

        private void update_outline_from_yaml_diagram(YamlDiagram diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            if (diagram.root != null) {
                foreach (var child in diagram.root.children) {
                    string key = child.key ?? "";
                    if (child.node_type == YamlNodeType.SCALAR) {
                        string val = child.value ?? "";
                        add_outline_item("%s: %s".printf(key, val), "view-list-bullet-symbolic");
                    } else {
                        string type_hint = (child.node_type == YamlNodeType.SEQUENCE) ? "[ ]" : "{ }";
                        add_outline_item("%s %s".printf(key, type_hint), "folder-symbolic");
                    }
                }
            }
        }

        private void update_outline_from_chronology_diagram(ChronologyDiagram diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var ev in diagram.events) {
                add_outline_item("%s (%s)".printf(ev.name, ev.date_str), "appointment-symbolic");
            }
        }

        private void update_outline_from_timing_diagram(TimingDiagram diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var sig in diagram.signals) {
                string type_label;
                switch (sig.signal_type) {
                    case SignalType.BINARY: type_label = "Binary"; break;
                    case SignalType.CLOCK:  type_label = "Clock"; break;
                    case SignalType.ANALOG: type_label = "Analog"; break;
                    case SignalType.ROBUST: type_label = "Robust"; break;
                    default:               type_label = "Concise"; break;
                }
                add_outline_item("%s [%s]".printf(sig.label, type_label), "media-playback-start-symbolic");
            }
        }

        private void update_outline_from_nwdiag_diagram(NwdiagDiagram diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var net in diagram.networks) {
                int node_count = net.nodes.size;
                string label = "%s (%d node%s)".printf(
                    net.name, node_count, node_count == 1 ? "" : "s");
                add_outline_item(label, "network-server-symbolic");
            }
        }

        private void update_outline_from_archimate_diagram(ArchimateDiagram diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var elem in diagram.elements) {
                string layer_label = archimate_layer_name(elem.layer);
                string label = "[%s] %s".printf(layer_label, elem.label);
                add_outline_item(label, "object-select-symbolic");
            }
        }

        private string archimate_layer_name(ArchimateLayer layer) {
            switch (layer) {
                case ArchimateLayer.BUSINESS:       return "Business";
                case ArchimateLayer.APPLICATION:    return "Application";
                case ArchimateLayer.TECHNOLOGY:     return "Technology";
                case ArchimateLayer.MOTIVATION:     return "Motivation";
                case ArchimateLayer.PHYSICAL:       return "Physical";
                case ArchimateLayer.IMPLEMENTATION: return "Implementation";
                case ArchimateLayer.STRATEGY:       return "Strategy";
                default:                            return "Element";
            }
        }

        // ==================== Mermaid outline population ====================

        private void update_outline_from_mermaid_flowchart(MermaidFlowchart diagram) {
            clear_outline();
            foreach (var node in diagram.nodes) {
                string label = (node.text.length > 0 && node.text != node.id) ? node.text : node.id;
                add_outline_item(label, "view-list-symbolic");
            }
        }

        private void update_outline_from_mermaid_sequence(MermaidSequenceDiagram diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var actor in diagram.actors) {
                add_outline_item(actor.get_display_name(), "avatar-default-symbolic");
            }
        }

        private void update_outline_from_mermaid_state(MermaidStateDiagram diagram) {
            clear_outline();
            foreach (var state in diagram.states) {
                if (state.state_type == MermaidStateType.NORMAL) {
                    string lbl = (state.description != null && state.description.length > 0)
                        ? state.description : state.id;
                    add_outline_item(lbl, "view-grid-symbolic");
                }
            }
        }

        private void update_outline_from_mermaid_class(MermaidClassDiagram diagram) {
            clear_outline();
            foreach (var cls in diagram.classes) {
                add_outline_item(cls.name, "view-list-symbolic");
            }
        }

        private void update_outline_from_mermaid_er(MermaidERDiagram diagram) {
            clear_outline();
            foreach (var entity in diagram.entities) {
                add_outline_item(entity.name, "view-list-symbolic");
            }
        }

        private void update_outline_from_mermaid_gantt(MermaidGantt diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var section in diagram.sections) {
                add_outline_item(section.name, "view-list-symbolic");
                foreach (var task in section.tasks) {
                    add_outline_item("  " + task.description, "task-due-symbolic");
                }
            }
        }

        private void update_outline_from_mermaid_pie(MermaidPie diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            double total = diagram.get_total();
            foreach (var slice in diagram.slices) {
                string pct = total > 0 ? " (%.1f%%)".printf(slice.value / total * 100) : "";
                add_outline_item(slice.label + pct, "view-list-bullet-symbolic");
            }
        }

        private void update_outline_from_mermaid_user_journey(MermaidUserJourney diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var section in diagram.sections) {
                add_outline_item(section.name, "view-list-symbolic");
                foreach (var task in section.tasks) {
                    add_outline_item("  " + task.description, "task-due-symbolic");
                }
            }
        }

        private void update_outline_from_mermaid_git_graph(MermaidGitGraph diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var branch in diagram.branches) {
                add_outline_item(branch.name, "vcs-branch-symbolic");
                foreach (var commit in branch.commits) {
                    string lbl = (commit.tag != null && commit.tag.length > 0)
                        ? commit.id + " [" + commit.tag + "]"
                        : commit.id;
                    add_outline_item("  " + lbl, "vcs-commit-symbolic");
                }
            }
        }

        private void update_outline_from_mermaid_mindmap(MermaidMindmap diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            if (diagram.root != null) {
                add_mindmap_node_to_outline(diagram.root, 0);
            }
        }

        private void update_outline_from_mermaid_timeline(MermaidTimeline diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            string? last_section = null;
            foreach (var period in diagram.periods) {
                if (period.section_name != null && period.section_name != last_section) {
                    add_outline_item("Section: %s".printf(period.section_name), "view-list-symbolic");
                    last_section = period.section_name;
                }
                add_outline_item(period.label, "media-playback-start-symbolic");
                foreach (var evt in period.events) {
                    add_outline_item("  " + evt.text, "view-list-bullet-symbolic");
                }
            }
        }

        private void update_outline_from_mermaid_quadrant(MermaidQuadrant diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            if (diagram.x_axis_left.length > 0 || diagram.x_axis_right.length > 0) {
                add_outline_item("X: %s → %s".printf(diagram.x_axis_left, diagram.x_axis_right), "view-list-symbolic");
            }
            if (diagram.y_axis_bottom.length > 0 || diagram.y_axis_top.length > 0) {
                add_outline_item("Y: %s → %s".printf(diagram.y_axis_bottom, diagram.y_axis_top), "view-list-symbolic");
            }
            foreach (var pt in diagram.points) {
                add_outline_item("  %s [%.2f, %.2f]".printf(pt.label, pt.x, pt.y), "view-list-bullet-symbolic");
            }
        }

        private void update_outline_from_mermaid_xychart(MermaidXYChart diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            if (diagram.x_labels.size > 0) {
                add_outline_item("X-axis: %d categories".printf(diagram.x_labels.size), "view-list-symbolic");
            }
            if (diagram.y_axis_label.length > 0) {
                string y_info = "Y: %s".printf(diagram.y_axis_label);
                if (diagram.has_y_range) {
                    y_info += " [%.0f → %.0f]".printf(diagram.y_min, diagram.y_max);
                }
                add_outline_item(y_info, "view-list-symbolic");
            }
            int bar_idx = 0;
            int line_idx = 0;
            foreach (var s in diagram.series) {
                string label;
                if (s.series_type == XYSeriesType.BAR) {
                    bar_idx++;
                    label = "Bar series %d (%d values)".printf(bar_idx, s.values.size);
                } else {
                    line_idx++;
                    label = "Line series %d (%d values)".printf(line_idx, s.values.size);
                }
                add_outline_item("  " + label, "view-list-bullet-symbolic");
            }
        }

        private void update_outline_from_mermaid_kanban(MermaidKanban diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var col in diagram.columns) {
                add_outline_item(
                    "%s (%d)".printf(col.label, col.cards.size),
                    "view-list-symbolic"
                );
                foreach (var card in col.cards) {
                    add_outline_item("  " + card.label, "view-list-bullet-symbolic");
                }
            }
        }

        private void update_outline_from_mermaid_block(MermaidBlock diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var node in diagram.nodes) {
                string icon = node.is_group ? "folder-symbolic" : "emblem-documents-symbolic";
                add_outline_item(node.label, icon);
            }
            foreach (var edge in diagram.edges) {
                string label = edge.label != null ? " [%s]".printf(edge.label) : "";
                add_outline_item(
                    "%s --> %s%s".printf(edge.source, edge.target, label),
                    "go-next-symbolic"
                );
            }
        }

        private void update_outline_from_mermaid_packet(MermaidPacket diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var field in diagram.fields) {
                add_outline_item("%d-%d: %s".printf(field.bit_start, field.bit_end, field.label), "view-list-bullet-symbolic");
            }
        }

        private void update_outline_from_mermaid_c4(MermaidC4 diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            add_outline_item("Type: C4%s".printf(diagram.c4_type), "preferences-system-symbolic");
            foreach (var el in diagram.elements) {
                string type_str;
                string icon;
                switch (el.element_type) {
                    case C4ElementType.PERSON:
                        type_str = el.is_external ? "Person_Ext" : "Person";
                        icon = "system-users-symbolic";
                        break;
                    case C4ElementType.CONTAINER:
                        type_str = el.is_db ? "ContainerDb" : "Container";
                        icon = "drive-harddisk-symbolic";
                        break;
                    case C4ElementType.COMPONENT:
                        type_str = "Component";
                        icon = "view-grid-symbolic";
                        break;
                    case C4ElementType.DEPLOYMENT_NODE:
                        type_str = "Node";
                        icon = "network-server-symbolic";
                        break;
                    default:
                        type_str = el.is_external ? "System_Ext" : "System";
                        icon = "computer-symbolic";
                        break;
                }
                add_outline_item("%s: %s".printf(type_str, el.label), icon);
            }
            foreach (var rel in diagram.relationships) {
                string dir_str = rel.direction.length > 0 ? "_" + rel.direction : "";
                string rel_type = rel.is_bidirectional ? "BiRel" : "Rel" + dir_str;
                add_outline_item("%s: %s -> %s".printf(rel_type, rel.from_id, rel.to_id), "go-next-symbolic");
            }
        }

        private void update_outline_from_mermaid_architecture(MermaidArchitecture diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var grp in diagram.groups) {
                string parent_str = grp.parent_id != null ? " (in %s)".printf(grp.parent_id) : "";
                add_outline_item("Group: %s%s".printf(grp.label, parent_str), "folder-symbolic");
            }
            foreach (var svc in diagram.services) {
                string group_str = svc.group_id != null ? " (in %s)".printf(svc.group_id) : "";
                string icon = svc.is_junction ? "media-record-symbolic" : "network-server-symbolic";
                string label = svc.is_junction ? "Junction: %s%s".printf(svc.id, group_str)
                                               : "Service: %s [%s]%s".printf(svc.label, svc.icon, group_str);
                add_outline_item(label, icon);
            }
            foreach (var edge in diagram.edges) {
                string edge_type = edge.directed ? "-->" : "--";
                add_outline_item("%s:%s %s %s:%s".printf(edge.from_id, edge.from_side, edge_type, edge.to_side, edge.to_id), "go-next-symbolic");
            }
        }

        private void update_outline_from_mermaid_zenuml(MermaidZenUML diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var p in diagram.participants) {
                add_outline_item("%s: %s".printf(p.actor_type, p.name), "user-symbolic");
            }
            if (diagram.messages.size > 0) {
                add_outline_item("Messages: %d".printf(diagram.messages.size), "mail-send-symbolic");
            }
        }

        private void update_outline_from_mermaid_radar(MermaidRadar diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var axis in diagram.axes) {
                add_outline_item("Axis: %s".printf(axis.label), "go-next-symbolic");
            }
            foreach (var curve in diagram.curves) {
                add_outline_item("Curve: %s".printf(curve.label), "utilities-system-monitor-symbolic");
            }
        }

        private void update_outline_from_mermaid_treemap(MermaidTreemap diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var root in diagram.roots) {
                double total = root.total_value();
                string label = total > 0.0
                    ? "%s (%.0f)".printf(root.label, total)
                    : root.label;
                add_outline_item(label, "go-next-symbolic");
            }
        }

        private void update_outline_from_mermaid_requirement(MermaidRequirement diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var elem in diagram.elements) {
                bool is_element = elem.req_type.down() == "element";
                string icon = is_element ? "applications-system-symbolic" : "emblem-documents-symbolic";
                add_outline_item("%s: %s".printf(elem.req_type, elem.name), icon);
            }
            foreach (var rel in diagram.relationships) {
                add_outline_item(
                    "%s -%s-> %s".printf(rel.source, rel.rel_type, rel.target),
                    "go-next-symbolic"
                );
            }
        }

        private void update_outline_from_mermaid_sankey(MermaidSankey diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            var nodes = diagram.get_nodes();
            foreach (var node in nodes) {
                add_outline_item(node, "go-next-symbolic");
            }
        }

        // ==================== Outline item helpers ====================

        private void add_mindmap_node_to_outline(MindmapNode node, int indent) {
            string prefix = string.nfill(indent * 2, ' ');
            add_outline_item(prefix + node.label, "view-list-bullet-symbolic");
            foreach (var child in node.children) {
                add_mindmap_node_to_outline(child, indent + 1);
            }
        }

        private void add_outline_item(string text, string icon_name) {
            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            box.margin_start = 6;
            box.margin_end = 6;
            box.margin_top = 3;
            box.margin_bottom = 3;

            var icon = new Gtk.Image.from_icon_name(icon_name);
            icon.add_css_class("dim-label");
            box.append(icon);

            // Normalize the outline label text. Multi-line component labels
            // like "Web App\n[React]\nUI" (common in C4) keep their \n as
            // two literal characters for graphviz to render at draw time.
            // The outline list is single-line so we turn each \n into a
            // " / " separator, strip any remaining inline PlantUML markup,
            // and collapse runs of whitespace.
            string clean = text;
            if (clean.contains("\\n")) {
                clean = clean.replace("\\n", " / ");
            }
            // Real newline chars (rare but possible) also become separators
            if (clean.contains("\n")) {
                clean = clean.replace("\n", " / ");
            }
            clean = RenderUtils.strip_plantuml_markup(clean);

            var label = new Gtk.Label(clean);
            label.xalign = 0;
            label.ellipsize = Pango.EllipsizeMode.END;
            box.append(label);

            outline_list.append(box);
        }
    }
}
