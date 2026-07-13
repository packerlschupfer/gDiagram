// PlantUML fidelity review (September 2026): object, YAML/JSON, nwdiag, ArchiMate and
// chronology diagrams. Each test was checked to fail without its fix.

using GDiagram;

string engine_dot(string source) {
    var engine = new DiagramEngine("dot");
    string? dot = engine.generate_dot(source, "test.puml", null);
    assert(dot != null);
    return dot;
}

Object parse_ast(string source, DiagramType expected) {
    var engine = new DiagramEngine("dot");
    var r = engine.parse(source, "test.puml", null);
    if (r.diagram_type != expected) {
        stderr.printf("detected %s, expected %s\n", r.diagram_type.to_string(), expected.to_string());
        assert_not_reached();
    }
    return r.ast;
}

void fail_with(string label, string message, string dot) {
    stderr.printf("[%s] %s in:\n%s\n", label, message, dot);
    assert_not_reached();
}

void assert_has(string label, string dot, string needle) {
    if (!dot.contains(needle)) {
        fail_with(label, "missing '%s'".printf(needle), dot);
    }
}

void assert_lacks(string label, string dot, string needle) {
    if (dot.contains(needle)) {
        fail_with(label, "unexpected '%s'".printf(needle), dot);
    }
}

int count_substr(string hay, string needle) {
    int n = 0;
    int pos = 0;
    while ((pos = hay.index_of(needle, pos)) >= 0) {
        n++;
        pos += needle.length;
    }
    return n;
}

// O1. "diamond dia" is one diamond junction
void test_object_diamond() {
    string src = "@startuml\nobject o1\nobject o2\ndiamond dia\no1 --> dia\no2 --> dia\n@enduml";
    var d = (ObjectDiagram) parse_ast(src, DiagramType.OBJECT);
    assert(d.objects.size == 3);
    assert(d.find_object("diamond") == null);
    assert(d.find_object("dia").is_diamond);
    string dot = engine_dot(src);
    assert_has("diamond", dot, "dia [shape=diamond");
}

// O2. "json Name { ... }" is one table node; with a bare class line the file stays an
// object diagram
void test_object_json_element() {
    string src = "@startuml\nclass Class\nobject Object\njson JSON {\n   \"fruit\":\"Apple\",\n   \"color\": [\"Red\", \"Green\"]\n}\nObject --> JSON\n@enduml";
    var d = (ObjectDiagram) parse_ast(src, DiagramType.OBJECT);
    assert(d.objects.size == 3);
    assert(d.find_object("json") == null && d.find_object("fruit") == null);
    var json = d.find_object("JSON");
    assert(json.json_root != null && json.json_root.children.size == 2);
    assert(json.json_root.children[1].node_type == JsonNodeType.ARRAY);
    assert(d.find_object("Class").is_class);
    string dot = engine_dot(src);
    assert_has("json", dot, "JSON [shape=plaintext");
    assert_has("json", dot, ">fruit</font></td><td align=\"left\"><font color=");
    assert_has("json", dot, ">Green</font>");
    assert_has("json", dot, "Object -> JSON");
}

// O3. A map row holding a link spans the map; the title keeps its partial bold
void test_object_map_rows_and_title() {
    string dot = engine_dot("@startuml\nobject London\nmap \"Map **Capital**\" as CC {\n  UK *-> London\n  USA => Washington\n}\n@enduml");
    assert_has("map", dot, "<TD PORT=\"r0\" COLSPAN=\"2\">UK</TD>");
    assert_has("map", dot, "<TD PORT=\"r1\" ALIGN=\"LEFT\">USA</TD><TD ALIGN=\"LEFT\">Washington</TD>");
    assert_has("map", dot, "Map <b>Capital</b>");
    assert_lacks("map", dot, "<B>Map");
}

// Y1. A list of mappings: each "- name: x" item holds its following keys
void test_yaml_list_of_mappings() {
    var d = (YamlDiagram) parse_ast("@startyaml\ncontainers:\n  - name: app\n    image: app:2\n    ports:\n      - containerPort: 8080\n  - name: side\n    image: side:1\n@endyaml",
                                    DiagramType.YAML_DIAGRAM);
    var containers = d.root.children[0];
    assert(containers.key == "containers" && containers.node_type == YamlNodeType.SEQUENCE);
    assert(containers.children.size == 2);
    var first = containers.children[0];
    assert(first.node_type == YamlNodeType.MAPPING && first.children.size == 3);
    assert(first.children[0].key == "name" && first.children[0].value == "app");
    assert(first.children[1].key == "image" && first.children[1].value == "app:2");
    assert(first.children[2].key == "ports" && first.children[2].node_type == YamlNodeType.SEQUENCE);
    assert(first.children[2].children[0].children[0].value == "8080");
    assert(containers.children[1].children[1].value == "side:1");
}

// Y2. Block scalars, empty values and quoted values
void test_yaml_scalars() {
    var d = (YamlDiagram) parse_ast("@startyaml\nkey: \"quoted: value\"\nempty:\nmulti: |\n  line1\n  line2\nlast: x\n@endyaml",
                                    DiagramType.YAML_DIAGRAM);
    assert(d.root.children.size == 4);
    assert(d.root.children[0].value == "quoted: value");
    assert(d.root.children[1].node_type == YamlNodeType.SCALAR && d.root.children[1].value == "");
    assert(d.root.children[2].node_type == YamlNodeType.SCALAR && d.root.children[2].value == "line1\nline2");
    assert(d.root.children[3].key == "last");
}

// Y3. JSON and YAML are nested tables linked by dashed arrows, highlights coloured
void test_data_tables() {
    string dot = engine_dot("@startjson\n#highlight \"database\" / \"host\"\n{\n  \"app\": \"MyApp\",\n  \"database\": {\"host\": \"localhost\", \"port\": 5432},\n  \"features\": [\"auth\", \"cache\"],\n  \"debug\": false\n}\n@endjson");
    assert(count_substr(dot, "<table border=\"1\"") == 3);
    assert_has("json", dot, "t0:p0:e -> t1");
    assert_has("json", dot, "t0:p1:e -> t2");
    assert_has("json", dot, "bgcolor=\"#CCFF02\"><font color=\"#000000\"><b>host</b>");
    assert_has("json", dot, "☐ false");
    assert_lacks("json", dot, "\"MyApp\"");
    assert_lacks("json", dot, "<b>0</b>");
    string yaml = engine_dot("@startyaml\n<style>\nyamlDiagram {\n  highlight {\n    BackGroundColor red\n  }\n}\n</style>\n#highlight \"a\"\na: 1\nb:\n  c: 2\n@endyaml");
    assert(count_substr(yaml, "<table border=\"1\"") == 2);
    assert_has("yaml", yaml, "t0:p0:e -> t1");
    assert_has("yaml style", yaml, "bgcolor=\"red\"");
}

// N1/N2. A node on two networks is drawn once, linked to both; groups are drawn
void test_nwdiag_shared_nodes_and_groups() {
    string dot = engine_dot("@startnwdiag\nnwdiag {\n  network a {\n    address = \"10.0.0.x/24\"\n    fw [address = \"10.0.0.1\"]\n  }\n  network b {\n    fw [address = \"10.1.0.1\"]\n    web [address = \"10.1.0.2\", shape = \"database\"]\n  }\n  group {\n    color = \"#FFaaaa\"\n    web\n  }\n}\n@endnwdiag");
    assert(count_substr(dot, "label=\"fw\"") == 1);
    assert_has("nwdiag", dot, "net_0_m0 -> node_0 [weight=10 label=\"10.0.0.1\"]");
    assert_has("nwdiag", dot, "node_0 -> net_1_m0 [weight=10 label=\"10.1.0.1\"]");
    assert_has("nwdiag", dot, "subgraph cluster_group_0");
    assert_has("nwdiag", dot, "fillcolor=\"#FFaaaa\"");
    assert_has("nwdiag", dot, "label=\"web\" shape=cylinder");
}

// R1/R2. Indented archimate lines are ArchiMate, drawn in PlantUML's layer colours
void test_archimate_layers() {
    string src = "@startuml\nrectangle \"Biz\" {\n  archimate #Business \"Sales Rep\" as sales <<Role>>\n}\nrectangle \"App\" {\n  archimate #Application \"CRM\" as crm <<ApplicationComponent>>\n  archimate #Technology \"Server\" as srv <<Node>>\n}\nsales --> crm\n@enduml";
    parse_ast(src, DiagramType.ARCHIMATE);
    string dot = engine_dot(src);
    assert_has("archimate", dot, "fillcolor=\"#FFFFCC\"");
    assert_has("archimate", dot, "fillcolor=\"#C2F0FF\"");
    assert_has("archimate", dot, "fillcolor=\"#C9FFC9\"");
}

// C1. Events read in chronological order down one side; times are kept
void test_chronology_order() {
    string src = "@startchronology\n[B] happens on 1971-10-03 12:00:00\n[A] happens on 1969-10-29\n[C] happens on 1971-10-03 9:30\n@endchronology";
    var d = (ChronologyDiagram) parse_ast(src, DiagramType.CHRONOLOGY);
    assert(d.events[0].date_str == "1971-10-03 12:00:00");
    var sorted = ChronologyDiagramRenderer.sorted_events(d);
    assert(sorted[0].name == "A" && sorted[1].name == "C" && sorted[2].name == "B");
    string dot = engine_dot(src);
    assert(dot.index_of("<b>A</b>") < dot.index_of("<b>C</b>") && dot.index_of("<b>C</b>") < dot.index_of("<b>B</b>"));
    assert_has("chronology", dot, "{ rank=same; spine_1; event_1 }");
    assert_lacks("chronology", dot, "event_1 -> spine_1");
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/review/data/object_diamond", test_object_diamond);
    Test.add_func("/review/data/object_json_element", test_object_json_element);
    Test.add_func("/review/data/object_map_rows_and_title", test_object_map_rows_and_title);
    Test.add_func("/review/data/yaml_list_of_mappings", test_yaml_list_of_mappings);
    Test.add_func("/review/data/yaml_scalars", test_yaml_scalars);
    Test.add_func("/review/data/data_tables", test_data_tables);
    Test.add_func("/review/data/nwdiag_shared_nodes_and_groups", test_nwdiag_shared_nodes_and_groups);
    Test.add_func("/review/data/archimate_layers", test_archimate_layers);
    Test.add_func("/review/data/chronology_order", test_chronology_order);
    return Test.run();
}
