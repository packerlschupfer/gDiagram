/*
 * Regression tests for the two PlantUML layout controls gDiagram used to drop:
 *
 *  1. "skinparam nodesep N" / "skinparam ranksep N" never reached Graphviz, so a file
 *     that asked for more room rendered byte-identical to one that did not.
 *  2. "-[hidden]->" option blocks: in the ER and ArchiMate parsers the "[" ended the
 *     arrow, so the link was dropped and "hidden" / the direction word turned into
 *     elements of their own.
 *
 * Both assert the DOT and the geometry that comes out of it.
 */
using GDiagram;

namespace LayoutControlTests {

    static DiagramEngine? shared_engine = null;

    DiagramEngine engine() {
        if (shared_engine == null) {
            shared_engine = new DiagramEngine("dot");
        }
        return shared_engine;
    }

    string dot_of(string source) {
        string? dot = engine().generate_dot(source, "layout.puml", null);
        assert(dot != null);
        return dot;
    }

    string svg_of(string source) {
        string path = Path.build_filename(Environment.get_tmp_dir(),
                                          "gdiagram-layout-%d.svg".printf(Random.int_range(0, 1 << 30)));
        assert(engine().export_to_svg(source, "layout.puml", null, path));
        string svg;
        try {
            FileUtils.get_contents(path, out svg);
        } catch (FileError e) {
            error("%s", e.message);
        }
        FileUtils.unlink(path);
        return svg;
    }

    // The page size Graphviz wrote: <svg width="62pt" height="116pt"
    void svg_page(string svg, out double width, out double height) {
        width = 0;
        height = 0;
        try {
            MatchInfo mi;
            assert(new Regex("<svg width=\"([0-9.]+)pt\" height=\"([0-9.]+)pt\"").match(svg, 0, out mi));
            width = double.parse(mi.fetch(1));
            height = double.parse(mi.fetch(2));
        } catch (RegexError e) {
            assert_not_reached();
        }
    }

    // The y of a node's <title>-identified group, taken from its first <ellipse>/<polygon>/<text>
    double svg_node_y(string svg, string id) {
        int t = svg.index_of("<title>%s</title>".printf(id));
        assert(t > 0);
        int end = svg.index_of("</g>", t);
        assert(end > t);
        string group = svg.substring(t, end - t);
        try {
            MatchInfo mi;
            assert(new Regex("<text[^>]* y=\"([-0-9.]+)\"").match(group, 0, out mi));
            return double.parse(mi.fetch(1));
        } catch (RegexError e) {
            assert_not_reached();
        }
    }

    const string CHAIN =
        "@startuml\n%s\nrectangle aaa\nrectangle bbb\nrectangle ccc\naaa --> bbb\nbbb --> ccc\n@enduml\n";
    const string FAN =
        "@startuml\n%s\nrectangle aaa\nrectangle bbb\nrectangle ccc\naaa --> bbb\naaa --> ccc\n@enduml\n";

    // 1. "skinparam ranksep" / "skinparam nodesep" reach the graph, in PlantUML's unit
    void test_skinparam_spacing_reaches_graphviz() {
        // Nothing is emitted when the file asks for nothing: the renderer's own look stays
        string plain = dot_of(CHAIN.printf(""));
        assert(!plain.contains("ranksep"));
        assert(!plain.contains("nodesep"));

        // PlantUML's values are pixels and it hands Graphviz value/72 (measured against
        // plantuml.jar 1.2026.8: every +72 of either grows its page by exactly 72 px)
        string spaced = dot_of(CHAIN.printf("skinparam nodesep 60\nskinparam ranksep 50"));
        assert(spaced.contains("nodesep=0.8333;"));
        assert(spaced.contains("ranksep=0.6944;"));

        // A bigger ranksep must actually make the page taller: two rank gaps, each
        // growing by (160-20)/72 inch = 140 pt
        double w_small, h_small, w_big, h_big;
        svg_page(svg_of(CHAIN.printf("skinparam ranksep 20")), out w_small, out h_small);
        svg_page(svg_of(CHAIN.printf("skinparam ranksep 160")), out w_big, out h_big);
        assert(h_big > h_small + 200);

        // and a bigger nodesep wider: bbb and ccc sit side by side under aaa
        svg_page(svg_of(FAN.printf("skinparam nodesep 20")), out w_small, out h_small);
        svg_page(svg_of(FAN.printf("skinparam nodesep 160")), out w_big, out h_big);
        assert(w_big > w_small + 100);

        // Non-numeric and PlantUML's own "unset" marker are ignored
        string junk = dot_of(CHAIN.printf("skinparam nodesep auto\nskinparam ranksep -1"));
        assert(!junk.contains("ranksep"));
        assert(!junk.contains("nodesep"));
    }

    // 2. The user's value beats a renderer's own built-in default
    void test_skinparam_spacing_beats_builtin_defaults() {
        // Activity: the renderer sets ranksep=0.28 / nodesep=0.15 itself
        string activity = dot_of("@startuml\nstart\n:one;\n:two;\nstop\n@enduml\n");
        assert(activity.contains("ranksep=0.28;") && activity.contains("nodesep=0.15;"));
        string activity_set = dot_of("@startuml\nskinparam ranksep 150\nskinparam nodesep 90\n" +
                                     "start\n:one;\n:two;\nstop\n@enduml\n");
        assert(!activity_set.contains("ranksep=0.28;") && !activity_set.contains("nodesep=0.15;"));
        assert(activity_set.contains("ranksep=2.0833;") && activity_set.contains("nodesep=1.2500;"));

        // Mind map: nodesep=0.3 / ranksep=0.5
        string mind = dot_of("@startmindmap\n* root\n** a\n** b\n@endmindmap\n");
        assert(mind.contains("nodesep=0.3;") && mind.contains("ranksep=0.5;"));
        string mind_set = dot_of("@startmindmap\nskinparam nodesep 72\n* root\n** a\n** b\n@endmindmap\n");
        assert(!mind_set.contains("nodesep=0.3;") && mind_set.contains("nodesep=1.0000;"));

        // Class: labelled side-by-side links widen the gap to nodesep=0.9 on their own
        string flat = "@startuml\n%s\nclass A\nclass B\nA \"1\" -right-> \"many\" B\n@enduml\n";
        assert(dot_of(flat.printf("")).contains("nodesep=0.9;"));
        string flat_set = dot_of(flat.printf("skinparam nodesep 216"));
        assert(!flat_set.contains("nodesep=0.9;"));
        assert(flat_set.contains("nodesep=3.0000;"));
    }

    // 3. Every PlantUML type whose renderer emits a Graphviz graph honours them
    void test_skinparam_spacing_every_graphviz_type() {
        string spacing = "skinparam nodesep 60\nskinparam ranksep 50\n";
        string[] sources = {
            "@startuml\n" + spacing + "rectangle a\nrectangle b\na --> b\n@enduml\n",         // component
            "@startuml\n" + spacing + "node a\nnode b\na --> b\n@enduml\n",                   // deployment
            "@startuml\n" + spacing + "class A\nclass B\nA --> B\n@enduml\n",                 // class
            "@startuml\n" + spacing + "object A\nobject B\nA --> B\n@enduml\n",               // object
            "@startuml\n" + spacing + "state A\nstate B\nA --> B\n@enduml\n",                 // state
            "@startuml\n" + spacing + "usecase A\nactor B\nB --> A\n@enduml\n",               // use case
            "@startuml\n" + spacing + "entity A\nentity B\nA ||--o{ B\n@enduml\n",            // ER
            "@startuml\n" + spacing + "start\n:one;\nstop\n@enduml\n",                        // activity
            "@startmindmap\n" + spacing + "* root\n** a\n@endmindmap\n",                      // mind map
            // ArchiMate: the parser used to throw every skinparam line away
            "@startuml\n" + spacing + "archimate #Business \"One\" as one\n" +
            "archimate #Business \"Two\" as two\none --> two\n@enduml\n",
        };
        foreach (string src in sources) {
            string dot = dot_of(src);
            assert(dot.contains("nodesep=0.8333;"));
            assert(dot.contains("ranksep=0.6944;"));
        }
    }

    // 4. "-[hidden]->" is laid out but not drawn, in every type that takes an arrow
    void test_hidden_arrow_constrains_without_drawing() {
        string src = "@startuml\nrectangle aaa\nrectangle bbb\naaa -[hidden]down-> bbb\n@enduml\n";
        string dot = dot_of(src);
        assert(dot.contains("style=invis"));

        // Graphviz draws nothing for it: no edge group at all in the SVG
        string svg = svg_of(src);
        assert(!svg.contains("class=\"edge\""));

        // but it still ranks the two: bbb ends up below aaa, and the page is taller
        // than the same file without the link, where they sit side by side
        assert(svg_node_y(svg, "aaa") < svg_node_y(svg, "bbb"));
        double w_free, h_free, w_hidden, h_hidden;
        svg_page(svg_of("@startuml\nrectangle aaa\nrectangle bbb\n@enduml\n"), out w_free, out h_free);
        svg_page(svg, out w_hidden, out h_hidden);
        assert(h_hidden > h_free);
        assert(w_hidden < w_free);

        // "-[hidden]right->" puts them on one rank instead
        string right = dot_of("@startuml\nrectangle aaa\nrectangle bbb\naaa -[hidden]right-> bbb\n@enduml\n");
        assert(right.contains("style=invis"));
        assert(right.contains("rank=same"));

        // The same arrow in every other type that takes one
        string[] sources = {
            "@startuml\nnode aaa\nnode bbb\naaa -[hidden]down-> bbb\n@enduml\n",       // deployment
            "@startuml\nclass A\nclass B\nA -[hidden]down-> B\n@enduml\n",             // class
            "@startuml\nobject A\nobject B\nA -[hidden]down-> B\n@enduml\n",           // object
            "@startuml\nstate A\nstate B\nA -[hidden]down-> B\n@enduml\n",             // state
            "@startuml\nusecase A\nusecase B\nA -[hidden]down-> B\n@enduml\n",         // use case
            "@startuml\n:one;\n-[hidden]->\n:two;\n@enduml\n",                         // activity
        };
        foreach (string s in sources) {
            assert(dot_of(s).contains("invis"));
        }
    }

    // 5. The ER parser let "[" end the arrow: the link was dropped and "hidden" and
    // the direction word became entities of their own
    void test_hidden_arrow_er() {
        string er = dot_of("@startuml\nentity A\nentity B\nentity C\n" +
                           "A -[hidden]right-> B\nA --> C\n@enduml\n");
        // No ghost entity made out of "hidden" or the direction word
        assert(!er.contains("{hidden}"));
        assert(!er.contains("right -> "));
        assert(er.contains("A -> B [style=invis"));
        assert(er.contains("A -> C [style=solid"));

        // The other option words keep working through the same path
        string styled = dot_of("@startuml\nentity A\nentity B\nA -[#red,bold]-> B\n@enduml\n");
        assert(styled.contains("style=bold") && styled.contains("color=\"red\""));
    }

    // 6. The ArchiMate parser kept the option block in the source element's name
    void test_hidden_arrow_archimate() {
        string arch = dot_of("@startuml\narchimate #Business \"Resource\" as res\n" +
                             "archimate #Business \"Other\" as oth\n" +
                             "archimate #Business \"Third\" as thr\n" +
                             "res -[hidden]right-> oth\nres --> thr\n@enduml\n");
        // The source element was "res", not "res -" with the option block glued on
        assert(arch.contains("\"res\" -> \"oth\" [style=invis"));
        assert(arch.contains("\"res\" -> \"thr\" [style=solid"));

        // and the hidden link still ranks them: nothing drawn, Resource above Other
        string svg = svg_of("@startuml\narchimate #Business \"Resource\" as res\n" +
                            "archimate #Business \"Other\" as oth\nres -[hidden]down-> oth\n@enduml\n");
        assert(!svg.contains("class=\"edge\""));
        assert(svg_node_y(svg, "res") < svg_node_y(svg, "oth"));
    }

    public static 
    // A GUI process calls setlocale(); a headless export does not. On a German desktop the
// spacing attributes came out as "nodesep=0,8333" and Graphviz refused the whole graph
// with "syntax error near ','" — the preview failed while the CLI was fine, which is
// exactly how it reached a user. Every number we write into DOT or SVG must be C-formatted.
    void test_spacing_is_locale_independent() {
    string? had = Intl.setlocale(LocaleCategory.NUMERIC, null);
    string[] comma_locales = { "de_AT.utf8", "de_DE.UTF-8", "de_DE.utf8", "fr_FR.UTF-8", "es_ES.UTF-8" };
    string? used = null;
    foreach (string loc in comma_locales) {
        if (Intl.setlocale(LocaleCategory.NUMERIC, loc) != null) {
            // only useful if this locale really formats with a comma
            if ("%.2f".printf(1.5) == "1,50") {
                used = loc;
                break;
            }
        }
    }
    if (used == null) {
        Intl.setlocale(LocaleCategory.NUMERIC, had ?? "C");
        Test.skip("no comma-decimal locale installed; cannot prove the locale guard here");
        return;
    }

    string dot = dot_of("@startuml\nskinparam nodesep 60\nskinparam ranksep 50\n" +
                               "rectangle A\nrectangle B\nA --> B\n@enduml");
    Intl.setlocale(LocaleCategory.NUMERIC, had ?? "C");

    if (dot.contains("nodesep=0,") || dot.contains("ranksep=0,")) {
        printerr("\nFAILED: locale-formatted spacing in the DOT (%s):\n%s\n", used, dot);
        assert_not_reached();
    }
    assert(dot.contains("nodesep=0.8333"));
    assert(dot.contains("ranksep=0.6944"));
    }

int main(string[] args) {
        Test.init(ref args);
        Test.add_func("/layout/skinparam-spacing-reaches-graphviz", test_skinparam_spacing_reaches_graphviz);
        Test.add_func("/layout/spacing-locale-independent", test_spacing_is_locale_independent);
        Test.add_func("/layout/skinparam-spacing-beats-builtin-defaults", test_skinparam_spacing_beats_builtin_defaults);
        Test.add_func("/layout/skinparam-spacing-every-graphviz-type", test_skinparam_spacing_every_graphviz_type);
        Test.add_func("/layout/hidden-arrow-constrains-without-drawing", test_hidden_arrow_constrains_without_drawing);
        Test.add_func("/layout/hidden-arrow-er", test_hidden_arrow_er);
        Test.add_func("/layout/hidden-arrow-archimate", test_hidden_arrow_archimate);
        return Test.run();
    }
}
