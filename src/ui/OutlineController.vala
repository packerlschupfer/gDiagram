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
     *
     * Entries form a tree (composite states, sections, branches, mind map
     * branches): rows with children get an expander, collapsed entries stay
     * collapsed across re-renders, and set_filter() narrows the list to
     * matching entries and their parents.
     */
    public class OutlineController : Object {
        // Owned by DocumentView. Not held here: the list holds this controller through its
        // filter function, and a strong reference back would keep both alive forever.
        private unowned Gtk.ListBox outline_list;

        // Entries of the last populated diagram; the rows are rebuilt from these
        private Gee.ArrayList<OutlineNode> roots = new Gee.ArrayList<OutlineNode>();
        // Class diagram: association class -> "A, B", the classes it associates
        private Gee.HashMap<UmlClass, string> association_ends = new Gee.HashMap<UmlClass, string>();
        // Keys (OutlineNode.key()) of collapsed entries, kept across the rebuild after every render
        private Gee.HashSet<string> collapsed_paths = new Gee.HashSet<string>();
        private string filter_text = "";
        private Gee.HashSet<OutlineNode> matching = new Gee.HashSet<OutlineNode>();

        // Emitted when the user activates an outline row. The argument is the
        // cleaned-up search key (first label segment) DocumentView should
        // navigate to in the source and highlight in the preview.
        public signal void navigate_to_element(string search_key);

        public OutlineController(Gtk.ListBox outline_list) {
            this.outline_list = outline_list;
            outline_list.set_filter_func(row_visible);

            // Handle row activation to navigate to the element.
            // The displayed label is the cleaned-up form — "Customer / A
            // logged-in shopper" — while the source has the original
            // "Customer\nA logged-in shopper". Search for just the first
            // segment (the primary label) which is much more likely to be
            // unique enough to land on the right line.
            outline_list.row_activated.connect((row) => {
                var outline_row = row as OutlineRow;
                if (outline_row == null) return;

                string text = outline_row.node.text;
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
                    return;
            }
            rebuild_rows();
        }

        private void clear_outline() {
            roots.clear();
        }

        // ==================== PlantUML outline population ====================

        private void update_outline_from_class_diagram(ClassDiagram diagram) {
            clear_outline();

            // Add title if present
            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // "(A, B) .. C": C is shown with the classes it associates
            association_ends.clear();
            foreach (var rel in diagram.relationships) {
                foreach (var assoc in rel.association_classes) {
                    association_ends[assoc] = "%s, %s".printf(rel.from.name, rel.to.name);
                }
            }

            // Packages list their nested packages and classes; the other classes are top level
            var packaged = new Gee.HashSet<UmlClass>();
            foreach (var pkg in diagram.packages) {
                add_class_package_to_outline(pkg, null, packaged);
            }
            foreach (var c in diagram.classes) {
                if (!packaged.contains(c)) {
                    add_class_to_outline(c, null);
                }
            }
        }

        private void add_class_package_to_outline(ClassPackage pkg, OutlineNode? parent, Gee.HashSet<UmlClass> packaged) {
            var node = add_outline_item(pkg.label ?? pkg.name, "folder-symbolic", parent);
            foreach (var child in pkg.children) {
                add_class_package_to_outline(child, node, packaged);
            }
            foreach (var c in pkg.classes) {
                packaged.add(c);
                add_class_to_outline(c, node);
            }
        }

        private void add_class_to_outline(UmlClass c, OutlineNode? parent) {
            string icon = "view-list-symbolic";
            if (c.class_type == ClassType.INTERFACE) {
                icon = "view-list-bullet-symbolic";
            } else if (c.class_type == ClassType.ABSTRACT) {
                icon = "view-list-bullet-symbolic";
            }
            // "primary / description": navigation searches the primary part
            string? ends = association_ends[c];
            add_outline_item(ends != null ? "%s / association of %s".printf(c.name, ends) : c.name, icon, parent);
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

            // Combined fragments, nested fragments under the one that encloses them
            // (a fragment is listed before its nested ones)
            var frame_nodes = new Gee.HashMap<SequenceFrame, OutlineNode>();
            foreach (var frame in diagram.frames) {
                OutlineNode? parent = null;
                if (frame.parent != null && frame_nodes.has_key(frame.parent)) {
                    parent = frame_nodes[frame.parent];
                }
                frame_nodes[frame] = add_outline_item(sequence_frame_text(frame), "view-dual-symbolic", parent);
            }

            // "newpage" breaks
            if (diagram.page_count > 1) {
                int page = 1;
                foreach (var ev in diagram.events) {
                    var page_break = ev as PageBreakEvent;
                    if (page_break == null) continue;
                    page++;
                    string title = page_break.title ?? "";
                    add_outline_item(title.length > 0 ? "Page %d: %s".printf(page, title) : "Page %d".printf(page),
                                     "document-new-symbolic");
                }
            }
        }

        private static string sequence_frame_text(SequenceFrame frame) {
            string kind;
            switch (frame.frame_type) {
                case SequenceFrameType.ALT:      kind = "alt"; break;
                case SequenceFrameType.OPT:      kind = "opt"; break;
                case SequenceFrameType.LOOP:     kind = "loop"; break;
                case SequenceFrameType.PAR:      kind = "par"; break;
                case SequenceFrameType.BREAK:    kind = "break"; break;
                case SequenceFrameType.CRITICAL: kind = "critical"; break;
                case SequenceFrameType.REF:      kind = "ref"; break;
                case SequenceFrameType.ELSE:     kind = "else"; break;
                default:                         kind = "group"; break;
            }
            string text = (frame.condition ?? frame.label ?? "").strip();
            // A ref's text may span lines: its first line is enough
            int newline = text.index_of("\n");
            if (newline >= 0) text = text.substring(0, newline).strip();
            return text.length > 0 ? "%s: %s".printf(kind, text) : kind;
        }

        private void update_outline_from_activity_diagram(ActivityDiagram diagram) {
            clear_outline();

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Swimlanes, partitions and groups are boxes in the preview and clickable
            // there, so they are rows here too, each listing the steps inside it. A
            // nested block hangs off its enclosing one.
            var partition_rows = new Gee.HashMap<string, OutlineNode>();
            foreach (var partition in diagram.partitions) {
                OutlineNode? parent = partition.parent != null ? partition_rows[partition.parent] : null;
                var row = add_outline_item(
                    "%s: %s".printf(partition.is_swimlane ? "Swimlane" : "Partition", partition.name),
                    partition.is_swimlane ? "view-dual-symbolic" : "view-list-symbolic", parent);
                partition_rows[partition.key] = row;
            }

            // Add main activities/actions
            foreach (var node in diagram.nodes) {
                string icon = "system-run-symbolic";
                OutlineNode? parent = node.partition != null ? partition_rows[node.partition] : null;
                if (node.node_type == ActivityNodeType.START) {
                    add_outline_item("Start", "media-playback-start-symbolic", parent);
                } else if (node.node_type == ActivityNodeType.STOP) {
                    add_outline_item("Stop", "media-playback-stop-symbolic", parent);
                } else if (node.node_type == ActivityNodeType.ACTION && node.label != null) {
                    add_outline_item(node.label, icon, parent);
                }
            }
        }

        private void update_outline_from_state_diagram(StateDiagram diagram) {
            clear_outline();

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Add states; a composite state lists its nested states under it
            foreach (var state in diagram.states) {
                add_state_to_outline(state, null);
            }
        }

        private void add_state_to_outline(State state, OutlineNode? parent) {
            // [*] start and end points and other generated pseudo-states (_history_0) are unnamed
            if (state.state_type == StateType.INITIAL || state.state_type == StateType.FINAL ||
                ElementInspector.is_synthetic_id(state.id)) return;
            var node = add_outline_item(state.label ?? state.id, "view-grid-symbolic", parent);
            // Concurrent regions ("--" / "||") list their states under "Region N"
            int max_region = 0;
            foreach (var nested in state.nested_states) {
                max_region = int.max(max_region, nested.region);
            }
            if (state.region_separator == null || max_region == 0) {
                foreach (var nested in state.nested_states) {
                    add_state_to_outline(nested, node);
                }
                return;
            }
            for (int region = 0; region <= max_region; region++) {
                OutlineNode? region_node = null;
                foreach (var nested in state.nested_states) {
                    if (nested.region != region) continue;
                    if (nested.state_type == StateType.INITIAL || nested.state_type == StateType.FINAL ||
                        ElementInspector.is_synthetic_id(nested.id)) continue;
                    if (region_node == null) {
                        region_node = add_outline_item("Region %d".printf(region + 1), "view-dual-symbolic", node);
                    }
                    add_state_to_outline(nested, region_node);
                }
            }
        }

        private void update_outline_from_usecase_diagram(UseCaseDiagram diagram) {
            clear_outline();

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Packages and rectangles list the actors and use cases inside them
            var in_package = new Gee.HashSet<Object>();
            foreach (var pkg in diagram.packages) {
                var pkg_node = add_outline_item(pkg.name, "folder-symbolic");
                foreach (var actor in pkg.actors) {
                    in_package.add(actor);
                    add_outline_item(actor.name, "avatar-default-symbolic", pkg_node);
                }
                foreach (var uc in pkg.use_cases) {
                    in_package.add(uc);
                    add_outline_item(uc.name, "emblem-system-symbolic", pkg_node);
                }
            }

            foreach (var actor in diagram.actors) {
                if (!in_package.contains(actor)) {
                    add_outline_item(actor.name, "avatar-default-symbolic");
                }
            }
            foreach (var uc in diagram.use_cases) {
                if (!in_package.contains(uc)) {
                    add_outline_item(uc.name, "emblem-system-symbolic");
                }
            }
        }

        private void update_outline_from_component_diagram(ComponentDiagram diagram) {
            clear_outline();

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Ports (port/portin/portout) sit on the component or node that declares them
            // and are clickable in the preview, so each is listed under its owner
            component_port_rows = new Gee.HashMap<string, Gee.ArrayList<ComponentPort>>();
            var loose_ports = new Gee.ArrayList<ComponentPort>();
            foreach (var port in diagram.ports) {
                if (port.parent_component == null) {
                    loose_ports.add(port);
                    continue;
                }
                var owned_ports = component_port_rows[port.parent_component];
                if (owned_ports == null) {
                    owned_ports = new Gee.ArrayList<ComponentPort>();
                    component_port_rows[port.parent_component] = owned_ports;
                }
                owned_ports.add(port);
            }

            // Add components; containers list what they contain
            var nested = new Gee.HashSet<Component>();
            foreach (var comp in diagram.components) {
                collect_component_children(comp, nested);
            }
            foreach (var comp in diagram.components) {
                if (!nested.contains(comp)) {
                    add_component_to_outline(comp, null);
                }
            }
            foreach (var port in loose_ports) {
                add_port_to_outline(port, null);
            }
            component_port_rows = null;

            // Add interfaces
            foreach (var iface in diagram.interfaces) {
                string display_name = iface.label ?? iface.id;
                add_outline_item(display_name, "view-list-bullet-symbolic");
            }
        }

        // Ports of the component diagram being populated, by owning component id
        private Gee.HashMap<string, Gee.ArrayList<ComponentPort>>? component_port_rows = null;

        private void add_port_to_outline(ComponentPort port, OutlineNode? parent) {
            string kind = port.port_type == PortType.IN ? "Port in"
                        : (port.port_type == PortType.OUT ? "Port out" : "Port");
            // An unnamed port ("_port_3") has nothing to navigate to
            string name = port.label ?? port.id;
            if (ElementInspector.is_synthetic_id(name)) {
                return;
            }
            add_outline_item("%s: %s".printf(kind, name), "go-next-symbolic", parent);
        }

        private void collect_component_children(Component comp, Gee.HashSet<Component> nested) {
            foreach (var child in comp.children) {
                nested.add(child);
                collect_component_children(child, nested);
            }
        }

        private void add_component_to_outline(Component comp, OutlineNode? parent) {
            string icon = comp.is_container ? "folder-symbolic" : "package-x-generic-symbolic";
            var node = add_outline_item(comp.label ?? comp.id, icon, parent);
            foreach (var child in comp.children) {
                add_component_to_outline(child, node);
            }
            var ports = component_port_rows != null ? component_port_rows[comp.id] : null;
            if (ports != null) {
                foreach (var port in ports) {
                    add_port_to_outline(port, node);
                }
            }
        }

        private void update_outline_from_object_diagram(ObjectDiagram diagram) {
            clear_outline();

            if (diagram.title != null) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }

            // Packages list their nested packages and objects; the other objects are top level
            var packaged = new Gee.HashSet<ObjectInstance>();
            foreach (var pkg in diagram.packages) {
                add_object_package_to_outline(pkg, null, packaged);
            }
            foreach (var obj in diagram.objects) {
                if (!packaged.contains(obj)) {
                    add_outline_item(obj.name, "view-list-bullet-symbolic");
                }
            }
        }

        private void add_object_package_to_outline(ObjectPackage pkg, OutlineNode? parent, Gee.HashSet<ObjectInstance> packaged) {
            var node = add_outline_item(pkg.label ?? pkg.name, "folder-symbolic", parent);
            foreach (var child in pkg.children) {
                add_object_package_to_outline(child, node, packaged);
            }
            foreach (var obj in pkg.objects) {
                packaged.add(obj);
                add_outline_item(obj.name, "view-list-bullet-symbolic", node);
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
                add_puml_mindmap_node_to_outline(diagram.root, null);
            }
        }

        private void add_puml_mindmap_node_to_outline(MindMapNode node, OutlineNode? parent) {
            var item = add_outline_item(node.text, "view-paged-symbolic", parent);
            foreach (var child in node.children) {
                add_puml_mindmap_node_to_outline(child, item);
            }
        }

        private void update_outline_from_gantt_diagram(PumlGanttDiagram diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            // Rows in source order: a "-- separator --" lists the tasks below it
            OutlineNode? section_node = null;
            foreach (var row in diagram.rows) {
                if (row.separator != null) {
                    section_node = add_outline_item(row.separator.length > 0 ? row.separator : "Separator",
                                                    "folder-symbolic");
                    continue;
                }
                var task = row.task;
                if (task == null) continue;
                string text;
                if (task.is_milestone) {
                    text = "%s (milestone)".printf(task.name);
                } else if (task.completion_pct >= 0) {
                    text = "%s (%s, %d%%)".printf(task.name, days_text(task.duration_days), task.completion_pct);
                } else {
                    text = "%s (%s)".printf(task.name, days_text(task.duration_days));
                }
                string icon = task.is_milestone ? "starred-symbolic" : "view-list-bullet-symbolic";
                add_outline_item(text, icon, section_node);
            }
        }

        private static string days_text(int days) {
            return days == 1 ? "1 day" : "%d days".printf(days);
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
                add_outline_item("%s (%s)".printf(ev.name, ev.date_str), "x-office-calendar-symbolic");
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
                    case SignalType.RECTANGLE: type_label = "Rectangle"; break;
                    default:               type_label = "Concise"; break;
                }
                add_outline_item("%s [%s]".printf(sig.label, type_label), "media-playback-start-symbolic");
            }
            if (diagram.messages.size > 0) {
                var messages = add_outline_item("Messages", "mail-send-symbolic");
                foreach (var msg in diagram.messages) {
                    string arrow = "%s@%g -> %s@%g".printf(msg.from_signal, msg.from_time, msg.to_signal, msg.to_time);
                    string label = msg.label ?? "";
                    add_outline_item(label.length > 0 ? "%s: %s".printf(arrow, label) : arrow,
                                     "mail-send-symbolic", messages);
                }
            }
            foreach (var hl in diagram.highlights) {
                string caption = hl.caption ?? "";
                string range = "%g to %g".printf(hl.from_time, hl.to_time);
                add_outline_item(caption.length > 0 ? "Highlight %s: %s".printf(range, caption)
                                                    : "Highlight %s".printf(range),
                                 "preferences-color-symbolic");
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

        // Subgraphs are containers, like PlantUML packages and both languages' composite
        // states: their nodes (and nested subgraphs) hang under them instead of being listed
        // flat next to every other node. `diagram.nodes` holds every node of the diagram,
        // subgraph members included, so the ones a subgraph claimed are collected first.
        private void update_outline_from_mermaid_flowchart(MermaidFlowchart diagram) {
            clear_outline();
            var grouped = new Gee.HashSet<FlowchartNode>();
            foreach (var subgraph in diagram.subgraphs) {
                collect_subgraph_nodes(subgraph, grouped);
            }
            foreach (var subgraph in diagram.subgraphs) {
                add_flowchart_subgraph_to_outline(subgraph, null);
            }
            foreach (var node in diagram.nodes) {
                if (!grouped.contains(node)) {
                    add_flowchart_node_to_outline(node, null);
                }
            }
        }

        private void collect_subgraph_nodes(FlowchartSubgraph subgraph, Gee.HashSet<FlowchartNode> into) {
            foreach (var node in subgraph.nodes) into.add(node);
            foreach (var inner in subgraph.subgraphs) collect_subgraph_nodes(inner, into);
        }

        private void add_flowchart_subgraph_to_outline(FlowchartSubgraph subgraph, OutlineNode? parent) {
            string label = subgraph.title != null && subgraph.title.length > 0
                ? subgraph.title : subgraph.id;
            var node = add_outline_item(label, "folder-symbolic", parent);
            foreach (var inner in subgraph.subgraphs) {
                add_flowchart_subgraph_to_outline(inner, node);
            }
            foreach (var child in subgraph.nodes) {
                add_flowchart_node_to_outline(child, node);
            }
        }

        private void add_flowchart_node_to_outline(FlowchartNode node, OutlineNode? parent) {
            string label = (node.text.length > 0 && node.text != node.id) ? node.text : node.id;
            add_outline_item(label, "view-list-symbolic", parent);
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
                var section_node = add_outline_item(section.name, "view-list-symbolic");
                foreach (var task in section.tasks) {
                    add_outline_item(task.description, "task-due-symbolic", section_node);
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
                var section_node = add_outline_item(section.name, "view-list-symbolic");
                foreach (var task in section.tasks) {
                    add_outline_item(task.description, "task-due-symbolic", section_node);
                }
            }
        }

        private void update_outline_from_mermaid_git_graph(MermaidGitGraph diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var branch in diagram.branches) {
                var branch_node = add_outline_item(branch.name, "network-workgroup-symbolic");
                foreach (var commit in branch.commits) {
                    string lbl = (commit.tag != null && commit.tag.length > 0)
                        ? commit.id + " [" + commit.tag + "]"
                        : commit.id;
                    add_outline_item(lbl, "media-record-symbolic", branch_node);
                }
            }
        }

        private void update_outline_from_mermaid_mindmap(MermaidMindmap diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            if (diagram.root != null) {
                add_mindmap_node_to_outline(diagram.root, null);
            }
        }

        private void update_outline_from_mermaid_timeline(MermaidTimeline diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            string? last_section = null;
            OutlineNode? section_node = null;
            foreach (var period in diagram.periods) {
                if (period.section_name != null && period.section_name != last_section) {
                    section_node = add_outline_item("Section: %s".printf(period.section_name), "view-list-symbolic");
                    last_section = period.section_name;
                }
                OutlineNode? parent = period.section_name != null ? section_node : null;
                var period_node = add_outline_item(period.label, "media-playback-start-symbolic", parent);
                foreach (var evt in period.events) {
                    add_outline_item(evt.text, "view-list-bullet-symbolic", period_node);
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
                var col_node = add_outline_item(
                    "%s (%d)".printf(col.label, col.cards.size),
                    "view-list-symbolic"
                );
                foreach (var card in col.cards) {
                    add_outline_item(card.label, "view-list-bullet-symbolic", col_node);
                }
            }
        }

        private void update_outline_from_mermaid_block(MermaidBlock diagram) {
            clear_outline();
            if (diagram.title != null && diagram.title.length > 0) {
                add_outline_item("Title: %s".printf(diagram.title), "text-x-generic-symbolic");
            }
            foreach (var node in diagram.nodes) {
                // "space" fills an empty grid cell: nothing to navigate to
                if (node.is_space) continue;
                string icon = node.is_group ? "folder-symbolic" : "text-x-generic-symbolic";
                string label = (node.label != null && node.label.length > 0) ? node.label : node.id;
                add_outline_item(label, icon);
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
                add_outline_item("%s: %s".printf(p.actor_type, p.name), "avatar-default-symbolic");
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
                add_outline_item("Curve: %s".printf(curve.label), "applications-graphics-symbolic");
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
                string icon = is_element ? "applications-system-symbolic" : "text-x-generic-symbolic";
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

        private void add_mindmap_node_to_outline(MindmapNode node, OutlineNode? parent) {
            var item = add_outline_item(node.label, "view-list-bullet-symbolic", parent);
            foreach (var child in node.children) {
                add_mindmap_node_to_outline(child, item);
            }
        }

        // Adds an entry under `parent` (top level when null). The rows are built
        // afterwards by rebuild_rows(), so a parent gets its expander once it has children.
        private OutlineNode add_outline_item(string text, string icon_name, OutlineNode? parent = null) {
            return OutlineNode.append(parent != null ? parent.children : roots, clean_label(text), icon_name, parent);
        }

        // Normalize the outline label text. Multi-line component labels
        // like "Web App\n[React]\nUI" (common in C4) keep their \n as
        // two literal characters for graphviz to render at draw time.
        // The outline list is single-line so we turn each \n into a
        // " / " separator, strip any remaining inline PlantUML markup,
        // and collapse runs of whitespace.
        private static string clean_label(string text) {
            // One line of plain text: the first label line, without sprites (<$person>),
            // "==" heading marks and creole ("Web App\\n[React]\\nUI" -> "Web App")
            string clean = ElementInspector.display_label(text);
            if (clean.length == 0) {
                clean = text.replace("\\n", " ").replace("\n", " ").strip();
            }
            return RenderUtils.strip_plantuml_markup(clean);
        }

        private void rebuild_rows() {
            while (outline_list.get_first_child() != null) {
                outline_list.remove(outline_list.get_first_child());
            }
            foreach (var node in roots) {
                append_rows(node, 0);
            }
            refresh_matches();
            outline_list.invalidate_filter();
        }

        private void append_rows(OutlineNode node, int depth) {
            var row = new OutlineRow(node, depth, collapsed_paths.contains(node.key()));
            // A method handler, not a closure: the row keeps no reference to the controller
            row.expander_toggled.connect(on_expander_toggled);
            outline_list.append(row);
            foreach (var child in node.children) {
                append_rows(child, depth + 1);
            }
        }

        private void on_expander_toggled(OutlineRow row, bool collapsed) {
            if (collapsed) {
                collapsed_paths.add(row.node.key());
            } else {
                collapsed_paths.remove(row.node.key());
            }
            outline_list.invalidate_filter();
        }

        // Search: show matching entries and the parents leading to them, collapsed or not
        public void set_filter(string text) {
            filter_text = text.strip().down();
            refresh_matches();
            outline_list.invalidate_filter();
        }

        private void refresh_matches() {
            matching.clear();
            if (filter_text.length == 0) return;
            foreach (var node in roots) {
                mark_matches(node);
            }
        }

        private bool mark_matches(OutlineNode node) {
            bool match = node.text.down().contains(filter_text);
            foreach (var child in node.children) {
                if (mark_matches(child)) match = true;
            }
            if (match) matching.add(node);
            return match;
        }

        private bool row_visible(Gtk.ListBoxRow row) {
            var outline_row = row as OutlineRow;
            if (outline_row == null) return true;
            if (filter_text.length > 0) return matching.contains(outline_row.node);
            for (var p = outline_row.node.parent; p != null; p = p.parent) {
                if (collapsed_paths.contains(p.key())) return false;
            }
            return true;
        }
    }

    internal class OutlineRow : Gtk.ListBoxRow {
        public OutlineNode node;
        public signal void expander_toggled(bool collapsed);
        private Gtk.Image? expander = null;
        private bool is_collapsed;

        public OutlineRow(OutlineNode node, int depth, bool collapsed) {
            this.node = node;

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            box.margin_start = 6 + depth * 16;
            box.margin_end = 6;
            box.margin_top = 3;
            box.margin_bottom = 3;

            if (node.children.size > 0) {
                // A plain image keeps the row compact; its click is claimed so
                // toggling does not also navigate to the element
                expander = IconCache.image(this, collapsed ? "pan-end-symbolic" : "pan-down-symbolic");
                expander.tooltip_text = "Expand or collapse";
                is_collapsed = collapsed;
                var click = new Gtk.GestureClick();
                // A method handler: a closure capturing the gesture (and the row) formed a
                // gesture <-> closure cycle, so no expandable row was ever freed
                click.pressed.connect(on_expander_pressed);
                expander.add_controller(click);
                box.append(expander);
            } else {
                // Leaves line up with their expandable siblings
                var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
                spacer.width_request = 16;
                box.append(spacer);
            }

            // One shared paintable per icon name (IconCache): an outline of 60 rows used to
            // ask the icon theme 120 times, once per row image, on every single render
            var icon = IconCache.image(this, node.icon_name);
            icon.add_css_class("dim-label");
            box.append(icon);

            var label = new Gtk.Label(node.text);
            label.xalign = 0;
            label.ellipsize = Pango.EllipsizeMode.END;
            label.tooltip_text = node.text;
            box.append(label);

            child = box;
        }

        private void on_expander_pressed(Gtk.GestureClick click, int n_press, double x, double y) {
            click.set_state(Gtk.EventSequenceState.CLAIMED);
            is_collapsed = !is_collapsed;
            IconCache.set_image(expander, is_collapsed ? "pan-end-symbolic" : "pan-down-symbolic");
            expander_toggled(is_collapsed);
        }
    }
}
