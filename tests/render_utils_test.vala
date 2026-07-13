namespace GDiagram.Tests {
    public class RenderUtilsTests {

        // ── strip_plantuml_markup ────────────────────────────────

        public static void test_strip_size_markers() {
            string r = RenderUtils.strip_plantuml_markup("<size:12>Hello</size>");
            assert(r == "Hello");
        }

        public static void test_strip_color_markers() {
            string r = RenderUtils.strip_plantuml_markup("<color:#FF0000>Red</color>");
            assert(r == "Red");
        }

        public static void test_strip_bold_italic() {
            string r = RenderUtils.strip_plantuml_markup("**Bold** and //italic//");
            assert(r == "Bold and italic");
        }

        public static void test_strip_link_with_text() {
            string r = RenderUtils.strip_plantuml_markup("[[https://example.com Click here]]");
            assert(r == "Click here");
        }

        public static void test_strip_link_bare() {
            string r = RenderUtils.strip_plantuml_markup("[[https://example.com]]");
            assert(r == "https://example.com");
        }

        public static void test_strip_leading_heading() {
            string r = RenderUtils.strip_plantuml_markup("== Customer");
            assert(r == "Customer");
        }

        public static void test_strip_inner_heading_after_newline() {
            // Newline + "== " marker that survived markup wrapping
            string r = RenderUtils.strip_plantuml_markup("Customer\\n== More");
            assert(r == "Customer\\nMore");
        }

        public static void test_strip_handles_spaced_size_marker() {
            // The component parser tokenizes labels with spaces around
            // punctuation, producing "< size : 12 >" instead of "<size:12>".
            // strip should tolerate that.
            string r = RenderUtils.strip_plantuml_markup("< size : 12 >Hello< / size >");
            assert(r == "Hello");
        }

        public static void test_strip_collapses_multiple_newlines() {
            string r = RenderUtils.strip_plantuml_markup("A\\n\\n\\nB");
            assert(r == "A\\nB");
        }

        public static void test_strip_trims_leading_trailing_newlines() {
            string r = RenderUtils.strip_plantuml_markup("\\nHello\\n");
            assert(r == "Hello");
        }

        public static void test_strip_full_c4_label() {
            // Real label out of C4-PlantUML expansion
            string raw = "<\\n== Web App\\n//<size:12>[React]</size>//\\n\\nUI";
            string r = RenderUtils.strip_plantuml_markup(raw);
            // Expect Web App, [React], UI on separate lines (no leading <,
            // no <size>, no //, no double-newlines)
            assert(r.contains("Web App"));
            assert(r.contains("[React]"));
            assert(r.contains("UI"));
            assert(!r.contains("<size"));
            assert(!r.contains("//"));
            assert(!r.has_prefix("<"));
            assert(!r.has_prefix("\\n"));
        }

        public static void test_strip_null_and_empty() {
            assert(RenderUtils.strip_plantuml_markup(null) == "");
            assert(RenderUtils.strip_plantuml_markup("") == "");
        }

        public static void test_strip_passes_through_clean_text() {
            // Plain text shouldn't be changed
            string r = RenderUtils.strip_plantuml_markup("Just plain text");
            assert(r == "Just plain text");
        }

        // ── Fuzz: adversarial inputs that must not hang or crash ────────

        public static void test_fuzz_strip_only_markup() {
            // Everything gets stripped.
            string r = RenderUtils.strip_plantuml_markup("<size:12></size>");
            assert(r == "");
        }

        public static void test_fuzz_strip_unclosed_markup() {
            // Unclosed markers — regex shouldn't loop.
            string r = RenderUtils.strip_plantuml_markup("<size:12>hello");
            // Don't assert on the exact output; just that it terminates
            // and produces something.
            assert(r != null);
        }

        public static void test_fuzz_strip_only_slashes() {
            // Nothing but // // //
            string r = RenderUtils.strip_plantuml_markup("// // //");
            assert(r != null);
        }

        public static void test_fuzz_strip_only_backslash_n() {
            // Literally just \n repeated — hits the trim-prefix/suffix
            // loop at the end of strip_plantuml_markup.
            string r = RenderUtils.strip_plantuml_markup("\\n\\n\\n\\n");
            assert(r == "");
        }

        public static void test_fuzz_strip_single_backslash_n() {
            // Odd case: length 2, all prefix.
            string r = RenderUtils.strip_plantuml_markup("\\n");
            assert(r == "");
        }

        public static void test_fuzz_strip_very_long_input() {
            var sb = new StringBuilder();
            for (int i = 0; i < 1000; i++) {
                sb.append("<size:12>word</size> **bold** //italic// [[link]]\\n");
            }
            string r = RenderUtils.strip_plantuml_markup(sb.str);
            assert(r != null);
            assert(r.contains("word"));
            assert(!r.contains("<size"));
            assert(!r.contains("**"));
        }

        public static void test_fuzz_strip_deeply_nested_links() {
            // [[ inside [[ ]] — regex is non-greedy but edge-casey
            string r = RenderUtils.strip_plantuml_markup("[[outer [[inner]] text]]");
            assert(r != null);
        }

        public static void test_fuzz_strip_unicode() {
            string r = RenderUtils.strip_plantuml_markup("日本語 <size:12>テスト</size> 한국어");
            assert(r.contains("日本語"));
            assert(r.contains("テスト"));
            assert(r.contains("한국어"));
            assert(!r.contains("<size"));
        }

        public static void test_fuzz_strip_zero_width_input() {
            // Single-char inputs that could trip substring bounds.
            assert(RenderUtils.strip_plantuml_markup(" ") == "");
            assert(RenderUtils.strip_plantuml_markup("<") != null);
            assert(RenderUtils.strip_plantuml_markup("[") != null);
            assert(RenderUtils.strip_plantuml_markup("*") != null);
            assert(RenderUtils.strip_plantuml_markup("/") != null);
        }

        // ── parse_svg_regions fuzz ────────────────────────────────────

        public static void test_fuzz_svg_empty() {
            var regions = new Gee.ArrayList<ElementRegion>();
            uint8[] empty = new uint8[0];
            RenderUtils.parse_svg_regions(empty, regions);
            assert(regions.size == 0);
        }

        public static void test_fuzz_svg_garbage_bytes() {
            var regions = new Gee.ArrayList<ElementRegion>();
            // Random non-SVG bytes including high-bit set (invalid UTF-8).
            uint8[] garbage = { 0x00, 0xff, 0xfe, 0xab, 0xcd, 0x01, 0x80 };
            RenderUtils.parse_svg_regions(garbage, regions);
            // Must not crash.
            assert(regions != null);
        }

        public static void test_fuzz_svg_valid_no_nodes() {
            var regions = new Gee.ArrayList<ElementRegion>();
            string svg = "<?xml version=\"1.0\"?><svg viewBox=\"0 0 100 100\"></svg>";
            RenderUtils.parse_svg_regions(svg.data, regions);
            assert(regions.size == 0);
        }

        public static void test_fuzz_svg_node_with_polygon() {
            var regions = new Gee.ArrayList<ElementRegion>();
            string svg = "<?xml version=\"1.0\"?>" +
                "<svg viewBox=\"0 0 200 200\">" +
                "<g class=\"graph\" transform=\"scale(1 1) rotate(0) translate(4 196)\">" +
                "<g id=\"node1\" class=\"node\"><title>Alice</title>" +
                "<polygon points=\"10,20 30,20 30,40 10,40\"/>" +
                "</g></g></svg>";
            RenderUtils.parse_svg_regions(svg.data, regions);
            assert(regions.size == 1);
            assert(regions.get(0).name == "Alice");
        }

        public static void test_fuzz_svg_malformed_viewbox() {
            var regions = new Gee.ArrayList<ElementRegion>();
            string svg = "<?xml version=\"1.0\"?>" +
                "<svg viewBox=\"not a real viewbox\">" +
                "<g class=\"node\"><title>X</title>" +
                "<polygon points=\"0,0 10,0 10,10 0,10\"/>" +
                "</g></svg>";
            RenderUtils.parse_svg_regions(svg.data, regions);
            // May or may not produce a region; must not crash.
            assert(regions != null);
        }

        public static void test_fuzz_svg_malformed_polygon_points() {
            var regions = new Gee.ArrayList<ElementRegion>();
            string svg = "<?xml version=\"1.0\"?>" +
                "<svg viewBox=\"0 0 100 100\">" +
                "<g class=\"node\"><title>Bad</title>" +
                "<polygon points=\"garbage,data notapoint 1,2,3,4\"/>" +
                "</g></svg>";
            RenderUtils.parse_svg_regions(svg.data, regions);
            assert(regions != null);
        }

        public static void test_fuzz_svg_title_with_arrow() {
            // Titles containing "->" are edges; must be skipped.
            // Graphviz encodes `->` in SVG titles as `&#45;&gt;` — that's
            // the exact form parse_svg_regions looks for.
            var regions = new Gee.ArrayList<ElementRegion>();
            string svg = "<?xml version=\"1.0\"?>" +
                "<svg viewBox=\"0 0 100 100\">" +
                "<g class=\"node\"><title>A&#45;&gt;B</title>" +
                "<polygon points=\"0,0 10,10\"/>" +
                "</g>" +
                "<g class=\"node\"><title>Alice</title>" +
                "<polygon points=\"20,20 30,30 30,20 20,30\"/>" +
                "</g></svg>";
            RenderUtils.parse_svg_regions(svg.data, regions);
            // Only Alice should make it through (edge was skipped).
            assert(regions.size == 1);
            assert(regions.get(0).name == "Alice");
        }

        public static void test_fuzz_svg_embedded_nul() {
            var regions = new Gee.ArrayList<ElementRegion>();
            // SVG bytes with an embedded NUL in the middle. Would break
            // the naive `(string) svg_data` cast without the length-aware
            // substring guard.
            string prefix = "<?xml version=\"1.0\"?><svg viewBox=\"0 0 100 100\">";
            string suffix = "<g class=\"node\"><title>X</title>" +
                "<polygon points=\"0,0 10,10\"/></g></svg>";
            int total_len = prefix.length + 1 + suffix.length;
            uint8[] bytes = new uint8[total_len];
            int i = 0;
            for (int j = 0; j < prefix.length; j++) bytes[i++] = (uint8) prefix[j];
            bytes[i++] = 0;  // embedded NUL
            for (int j = 0; j < suffix.length; j++) bytes[i++] = (uint8) suffix[j];
            // Must not crash. Region extraction past the NUL may or may
            // not happen depending on how the cast is implemented.
            RenderUtils.parse_svg_regions(bytes, regions);
            assert(regions != null);
        }

        // ── escape_label / escape_id / escape_record_label fuzz ──────

        public static void test_fuzz_escape_label_null_and_empty() {
            assert(RenderUtils.escape_label(null) == "");
            assert(RenderUtils.escape_label("") == "");
        }

        public static void test_fuzz_escape_label_dot_metachars() {
            // Characters that have meaning in DOT and must be escaped.
            string r = RenderUtils.escape_label("\"quoted\"");
            assert(r == "\\\"quoted\\\"");

            string r2 = RenderUtils.escape_label("back\\slash");
            assert(r2 == "back\\\\slash");

            string r3 = RenderUtils.escape_label("line1\nline2");
            assert(r3 == "line1\\nline2");
        }

        public static void test_fuzz_escape_label_looks_like_dot() {
            // Labels that look like DOT syntax — must be escaped so they
            // can't break out of the quoted string context.
            string r = RenderUtils.escape_label("a \" ; { } -> b");
            // Must contain escaped quote and no unescaped bare quote.
            assert(r.contains("\\\""));
            // Unescaped `"` would be a problem — ensure the only
            // double-quote in the result is the escaped form.
            int unescaped_quotes = 0;
            for (int i = 0; i < r.length; i++) {
                if (r[i] == '"' && (i == 0 || r[i-1] != '\\')) unescaped_quotes++;
            }
            assert(unescaped_quotes == 0);
        }

        public static void test_fuzz_escape_label_unicode() {
            string r = RenderUtils.escape_label("日本語 ←→ 한국어");
            assert(r.contains("日本語"));
            assert(r.contains("한국어"));
        }

        public static void test_fuzz_escape_label_invalid_utf8() {
            // Deliberately-broken UTF-8 bytes as a Vala string.
            uint8[] bad = { (uint8)'A', 0xff, 0xfe, 0x80, (uint8)'Z', 0 };
            // Construct a Vala string from the bytes. The 0 terminator
            // makes this a valid C string; the intermediate bytes are
            // invalid UTF-8 sequences.
            unowned string s = (string) bad;
            string r = RenderUtils.escape_label(s);
            // Must not crash; result should contain A and Z.
            assert(r.contains("A"));
            assert(r.contains("Z"));
        }

        public static void test_fuzz_escape_label_control_chars() {
            // Tab, CR, form feed, etc.
            string r = RenderUtils.escape_label("a\tb\rc\x0Cd");
            // Output must be non-null and not contain raw newlines.
            assert(r != null);
            assert(!r.contains("\n"));
        }

        public static void test_fuzz_escape_label_already_escaped_n() {
            // `\n` in the input is a literal 2-char sequence that should
            // be preserved (not re-escaped to `\\n`).
            string r = RenderUtils.escape_label("a\\nb");
            assert(r == "a\\nb");
        }

        public static void test_fuzz_escape_label_very_long() {
            var sb = new StringBuilder();
            for (int i = 0; i < 10000; i++) {
                sb.append("word ");
            }
            string r = RenderUtils.escape_label(sb.str);
            assert(r != null);
            assert(r.length >= sb.str.length);
        }

        public static void test_fuzz_escape_id_null_and_empty() {
            assert(RenderUtils.escape_id(null) == "n_empty");
            assert(RenderUtils.escape_id("") == "n_empty");
        }

        public static void test_fuzz_escape_id_only_punctuation() {
            // No alphanumeric chars — each becomes an underscore.
            string r = RenderUtils.escape_id("!@#$%^&*()");
            // Must be a valid DOT identifier: no leading digit, all alnum/_
            assert(r != null);
            assert(r.length > 0);
            for (int i = 0; i < r.length; i++) {
                char c = r[i];
                bool valid = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                    || (c >= '0' && c <= '9') || c == '_';
                assert(valid);
            }
        }

        public static void test_fuzz_escape_id_starts_with_digit() {
            // DOT identifiers can't start with digit — must be prefixed.
            string r = RenderUtils.escape_id("42answer");
            assert(r.has_prefix("n_"));
        }

        public static void test_fuzz_escape_id_unicode() {
            // Unicode chars should be replaced with underscores.
            string r = RenderUtils.escape_id("日本語");
            assert(r != null);
            for (int i = 0; i < r.length; i++) {
                char c = r[i];
                bool valid = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                    || (c >= '0' && c <= '9') || c == '_';
                assert(valid);
            }
        }

        public static void test_fuzz_escape_record_label_brackets() {
            string r = RenderUtils.escape_record_label("a<b>c{d}e");
            assert(r == "a\\<b\\>c\\{d\\}e");
        }

        public static void test_fuzz_svg_very_large() {
            var regions = new Gee.ArrayList<ElementRegion>();
            var sb = new StringBuilder();
            sb.append("<?xml version=\"1.0\"?><svg viewBox=\"0 0 1000 1000\">");
            for (int i = 0; i < 500; i++) {
                sb.append_printf(
                    "<g class=\"node\"><title>n%d</title>" +
                    "<polygon points=\"%d,%d %d,%d %d,%d %d,%d\"/></g>",
                    i, i, i, i+10, i, i+10, i+10, i, i+10
                );
            }
            sb.append("</svg>");
            RenderUtils.parse_svg_regions(sb.str.data, regions);
            assert(regions.size == 500);
        }

        public static void main(string[] args) {
            Test.init(ref args);
            Test.add_func("/render_utils/strip-size", test_strip_size_markers);
            Test.add_func("/render_utils/strip-color", test_strip_color_markers);
            Test.add_func("/render_utils/strip-bold-italic", test_strip_bold_italic);
            Test.add_func("/render_utils/strip-link-text", test_strip_link_with_text);
            Test.add_func("/render_utils/strip-link-bare", test_strip_link_bare);
            Test.add_func("/render_utils/strip-leading-heading", test_strip_leading_heading);
            Test.add_func("/render_utils/strip-inner-heading", test_strip_inner_heading_after_newline);
            Test.add_func("/render_utils/strip-spaced-size", test_strip_handles_spaced_size_marker);
            Test.add_func("/render_utils/strip-collapse-newlines", test_strip_collapses_multiple_newlines);
            Test.add_func("/render_utils/strip-trim-newlines", test_strip_trims_leading_trailing_newlines);
            Test.add_func("/render_utils/strip-full-c4-label", test_strip_full_c4_label);
            Test.add_func("/render_utils/strip-null-empty", test_strip_null_and_empty);
            Test.add_func("/render_utils/strip-clean-text", test_strip_passes_through_clean_text);
            Test.add_func("/render_utils/fuzz/only-markup", test_fuzz_strip_only_markup);
            Test.add_func("/render_utils/fuzz/unclosed", test_fuzz_strip_unclosed_markup);
            Test.add_func("/render_utils/fuzz/only-slashes", test_fuzz_strip_only_slashes);
            Test.add_func("/render_utils/fuzz/only-backslash-n", test_fuzz_strip_only_backslash_n);
            Test.add_func("/render_utils/fuzz/single-backslash-n", test_fuzz_strip_single_backslash_n);
            Test.add_func("/render_utils/fuzz/very-long", test_fuzz_strip_very_long_input);
            Test.add_func("/render_utils/fuzz/nested-links", test_fuzz_strip_deeply_nested_links);
            Test.add_func("/render_utils/fuzz/unicode", test_fuzz_strip_unicode);
            Test.add_func("/render_utils/fuzz/zero-width", test_fuzz_strip_zero_width_input);
            Test.add_func("/render_utils/fuzz/svg-empty", test_fuzz_svg_empty);
            Test.add_func("/render_utils/fuzz/svg-garbage", test_fuzz_svg_garbage_bytes);
            Test.add_func("/render_utils/fuzz/svg-no-nodes", test_fuzz_svg_valid_no_nodes);
            Test.add_func("/render_utils/fuzz/svg-polygon-node", test_fuzz_svg_node_with_polygon);
            Test.add_func("/render_utils/fuzz/svg-bad-viewbox", test_fuzz_svg_malformed_viewbox);
            Test.add_func("/render_utils/fuzz/svg-bad-polygon", test_fuzz_svg_malformed_polygon_points);
            Test.add_func("/render_utils/fuzz/svg-arrow-title", test_fuzz_svg_title_with_arrow);
            Test.add_func("/render_utils/fuzz/svg-embedded-nul", test_fuzz_svg_embedded_nul);
            Test.add_func("/render_utils/fuzz/svg-very-large", test_fuzz_svg_very_large);
            Test.add_func("/render_utils/fuzz/esc-label-null", test_fuzz_escape_label_null_and_empty);
            Test.add_func("/render_utils/fuzz/esc-label-meta", test_fuzz_escape_label_dot_metachars);
            Test.add_func("/render_utils/fuzz/esc-label-dot-syntax", test_fuzz_escape_label_looks_like_dot);
            Test.add_func("/render_utils/fuzz/esc-label-unicode", test_fuzz_escape_label_unicode);
            Test.add_func("/render_utils/fuzz/esc-label-bad-utf8", test_fuzz_escape_label_invalid_utf8);
            Test.add_func("/render_utils/fuzz/esc-label-control", test_fuzz_escape_label_control_chars);
            Test.add_func("/render_utils/fuzz/esc-label-escaped-n", test_fuzz_escape_label_already_escaped_n);
            Test.add_func("/render_utils/fuzz/esc-label-long", test_fuzz_escape_label_very_long);
            Test.add_func("/render_utils/fuzz/esc-id-null", test_fuzz_escape_id_null_and_empty);
            Test.add_func("/render_utils/fuzz/esc-id-punct", test_fuzz_escape_id_only_punctuation);
            Test.add_func("/render_utils/fuzz/esc-id-digit", test_fuzz_escape_id_starts_with_digit);
            Test.add_func("/render_utils/fuzz/esc-id-unicode", test_fuzz_escape_id_unicode);
            Test.add_func("/render_utils/fuzz/esc-record-brackets", test_fuzz_escape_record_label_brackets);
            Test.run();
        }
    }
}
