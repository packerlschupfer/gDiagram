namespace GDiagram.Tests {
    public class PreprocessorTests {
        public static void test_define_simple_substitution() {
            var p = new Preprocessor();
            string src = """@startuml
!define TITLE Hello
title TITLE
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("title Hello"));
            assert(!res.contains("title TITLE"));
        }

        public static void test_define_color_value() {
            var p = new Preprocessor();
            string src = """@startuml
!define BORDER #c2410c
skinparam ClassBorderColor BORDER
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("ClassBorderColor #c2410c"));
        }

        public static void test_define_word_boundary() {
            // MAX must NOT replace inside MAXIMUM, MAX_LENGTH, or PMAX.
            var p = new Preprocessor();
            string src = """@startuml
!define MAX 100
class MAXIMUM
class MAX_LENGTH
note: MAX is MAX
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("class MAXIMUM"));
            assert(res.contains("class MAX_LENGTH"));
            assert(res.contains("note: 100 is 100"));
        }

        public static void test_define_empty_value() {
            var p = new Preprocessor();
            string src = """@startuml
!define DEBUG
note: DEBUG mode
@enduml""";
            string res = p.process(src, null);
            // DEBUG should be replaced with empty string
            assert(res.contains("note:  mode"));
        }

        public static void test_undef() {
            var p = new Preprocessor();
            string src = """@startuml
!define X foo
line1: X
!undef X
line2: X
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("line1: foo"));
            assert(res.contains("line2: X"));
        }

        public static void test_parameterized_define_simple() {
            // !define BOX(name) class name expands to "class Foo" at the call site.
            var p = new Preprocessor();
            string src = """@startuml
!define BOX(name) class name
BOX(Foo)
@enduml""";
            string res = p.process(src, null);
            assert(!p.has_errors());
            assert(res.contains("class Foo"));
            // The original BOX(Foo) call should NOT survive in the output
            assert(!res.contains("BOX(Foo)"));
        }

        public static void test_parameterized_define_multiple_args() {
            var p = new Preprocessor();
            string src = """@startuml
!define REL(from, to, label) from --> to : label
REL(Alice, Bob, hello)
@enduml""";
            string res = p.process(src, null);
            assert(!p.has_errors());
            assert(res.contains("Alice --> Bob : hello"));
        }

        public static void test_parameterized_define_quoted_arg_with_comma() {
            // Quoted argument containing a comma should not be split.
            var p = new Preprocessor();
            string src = """@startuml
!define LBL(text) note: text
LBL("hello, world")
@enduml""";
            string res = p.process(src, null);
            assert(!p.has_errors());
            assert(res.contains("note: \"hello, world\""));
        }

        public static void test_parameterized_define_dollar_param() {
            // Body uses $name form
            var p = new Preprocessor();
            string src = """@startuml
!define CLS($name) class $name
CLS(Foo)
@enduml""";
            string res = p.process(src, null);
            assert(!p.has_errors());
            assert(res.contains("class Foo"));
        }

        public static void test_unquoted_procedure_simple() {
            var p = new Preprocessor();
            string src = """@startuml
!unquoted procedure Box($name)
class $name
!endprocedure
Box(Foo)
@enduml""";
            string res = p.process(src, null);
            assert(!p.has_errors());
            assert(res.contains("class Foo"));
        }

        public static void test_procedure_multi_line_body() {
            var p = new Preprocessor();
            string src = """@startuml
!unquoted procedure Pair($a, $b)
class $a
class $b
$a --> $b
!endprocedure
Pair(Alice, Bob)
@enduml""";
            string res = p.process(src, null);
            assert(!p.has_errors());
            assert(res.contains("class Alice"));
            assert(res.contains("class Bob"));
            assert(res.contains("Alice --> Bob"));
        }

        public static void test_quoted_procedure_keeps_quotes() {
            // !procedure (without 'unquoted') should NOT strip quotes from
            // string arguments — they substitute verbatim.
            var p = new Preprocessor();
            string src = """@startuml
!procedure Note($text)
note: $text
!endprocedure
Note("hello")
@enduml""";
            string res = p.process(src, null);
            assert(!p.has_errors());
            assert(res.contains("note: \"hello\""));
        }

        public static void test_unquoted_procedure_strips_quotes() {
            // !unquoted procedure SHOULD strip surrounding quotes.
            var p = new Preprocessor();
            string src = """@startuml
!unquoted procedure Lbl($text)
note: $text
!endprocedure
Lbl("hello")
@enduml""";
            string res = p.process(src, null);
            assert(!p.has_errors());
            assert(res.contains("note: hello"));
            assert(!res.contains("note: \"hello\""));
        }

        public static void test_default_param_values_used_when_arg_missing() {
            var p = new Preprocessor();
            string src = """@startuml
!unquoted procedure Person($alias, $label="Anon", $descr="")
note as $alias
$label
$descr
end note
!endprocedure
Person(u1, "Alice", "an actor")
Person(u2)
@enduml""";
            string res = p.process(src, null);
            assert(!p.has_errors());
            // First call: all 3 args provided
            assert(res.contains("note as u1"));
            assert(res.contains("Alice"));
            assert(res.contains("an actor"));
            // Second call: only alias given, $label and $descr fall back to defaults
            assert(res.contains("note as u2"));
            assert(res.contains("Anon"));
        }

        public static void test_default_param_values_partial_args() {
            var p = new Preprocessor();
            string src = """@startuml
!unquoted procedure Greet($who, $greeting="Hello")
$greeting, $who!
!endprocedure
Greet(World)
Greet(World, "Hi")
@enduml""";
            string res = p.process(src, null);
            assert(!p.has_errors());
            assert(res.contains("Hello, World!"));
            assert(res.contains("Hi, World!"));
        }

        public static void test_unterminated_procedure_logs_error() {
            var p = new Preprocessor();
            string src = """@startuml
!unquoted procedure Foo($x)
class $x
@enduml""";
            p.process(src, null);
            assert(p.has_errors());
        }

        public static void test_ifdef_taken_branch() {
            var p = new Preprocessor();
            string src = """@startuml
!define DEBUG
!ifdef DEBUG
class DebugMode
!endif
class Always
@enduml""";
            string res = p.process(src, null);
            assert(!p.has_errors());
            assert(res.contains("class DebugMode"));
            assert(res.contains("class Always"));
        }

        public static void test_ifdef_skipped_branch() {
            var p = new Preprocessor();
            string src = """@startuml
!ifdef DEBUG
class ShouldNotAppear
!endif
class Always
@enduml""";
            string res = p.process(src, null);
            assert(!p.has_errors());
            assert(!res.contains("class ShouldNotAppear"));
            assert(res.contains("class Always"));
        }

        public static void test_ifndef_skipped_when_defined() {
            var p = new Preprocessor();
            string src = """@startuml
!define DEBUG
!ifndef DEBUG
class ShouldNotAppear
!endif
@enduml""";
            string res = p.process(src, null);
            assert(!res.contains("class ShouldNotAppear"));
        }

        public static void test_ifndef_taken_when_undefined() {
            var p = new Preprocessor();
            string src = """@startuml
!ifndef DEBUG
class Production
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("class Production"));
        }

        public static void test_ifdef_else() {
            var p = new Preprocessor();
            string src = """@startuml
!ifdef DEBUG
class A
!else
class B
!endif
@enduml""";
            string res = p.process(src, null);
            assert(!res.contains("class A"));
            assert(res.contains("class B"));
        }

        public static void test_ifdef_else_taken() {
            var p = new Preprocessor();
            string src = """@startuml
!define DEBUG
!ifdef DEBUG
class A
!else
class B
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("class A"));
            assert(!res.contains("class B"));
        }

        public static void test_nested_ifdef() {
            var p = new Preprocessor();
            string src = """@startuml
!define OUTER
!ifdef OUTER
!ifdef INNER
class InnerOnly
!else
class OuterOnly
!endif
!endif
@enduml""";
            string res = p.process(src, null);
            assert(!res.contains("class InnerOnly"));
            assert(res.contains("class OuterOnly"));
        }

        public static void test_if_string_equality_taken() {
            var p = new Preprocessor();
            string src = """@startuml
!define MODE "prod"
!if $MODE == "prod"
class Production
!else
class Dev
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("class Production"));
            assert(!res.contains("class Dev"));
        }

        public static void test_if_string_equality_skipped() {
            var p = new Preprocessor();
            string src = """@startuml
!define MODE "dev"
!if $MODE == "prod"
class Production
!else
class Dev
!endif
@enduml""";
            string res = p.process(src, null);
            assert(!res.contains("class Production"));
            assert(res.contains("class Dev"));
        }

        public static void test_if_numeric_comparison() {
            var p = new Preprocessor();
            string src = """@startuml
!define LEVEL 5
!if $LEVEL > 3
class HighLevel
!endif
!if $LEVEL > 10
class TooHigh
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("class HighLevel"));
            assert(!res.contains("class TooHigh"));
        }

        public static void test_if_logical_and_or() {
            var p = new Preprocessor();
            string src = """@startuml
!define A "yes"
!define B "no"
!if $A == "yes" && $B == "yes"
class Both
!endif
!if $A == "yes" || $B == "yes"
class Either
!endif
@enduml""";
            string res = p.process(src, null);
            assert(!res.contains("class Both"));
            assert(res.contains("class Either"));
        }

        public static void test_if_negation() {
            // X="false" is truthy-false, so !$X is true → branch taken.
            // (X == "yes") is false, so !(X == "yes") is true → branch taken.
            var p = new Preprocessor();
            string src = """@startuml
!define X "false"
!if !$X
class XIsFalsy
!endif
!if !($X == "yes")
class NotYes
!endif
!define Y "true"
!if !$Y
class YIsFalsy
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("class XIsFalsy"));
            assert(res.contains("class NotYes"));
            assert(!res.contains("class YIsFalsy"));
        }

        public static void test_function_simple_return() {
            var p = new Preprocessor();
            string src = """@startuml
!function double($x)
!return $x * 2
!endfunction
!if double(5) == 10
class TenIsDouble
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("class TenIsDouble"));
        }

        public static void test_function_string_return() {
            var p = new Preprocessor();
            string src = """@startuml
!function greet($name)
!return "Hello, " + $name
!endfunction
!if greet("World") == "Hello, World"
class Greeted
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("class Greeted"));
        }

        public static void test_function_conditional_return() {
            var p = new Preprocessor();
            string src = """@startuml
!function classify($n)
!if $n > 100
!return "big"
!endif
!return "small"
!endfunction
!if classify(50) == "small"
class IsSmall
!endif
!if classify(500) == "big"
class IsBig
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("class IsSmall"));
            assert(res.contains("class IsBig"));
        }

        public static void test_builtin_substr_strpos_strlen() {
            var p = new Preprocessor();
            string src = """@startuml
!if %strlen("hello") == 5
class Len5
!endif
!if %substr("hello world", 6) == "world"
class GotWorld
!endif
!if %substr("hello world", 0, 5) == "hello"
class GotHello
!endif
!if %strpos("hello world", "world") == 6
class FoundWorld
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("class Len5"));
            assert(res.contains("class GotWorld"));
            assert(res.contains("class GotHello"));
            assert(res.contains("class FoundWorld"));
        }

        public static void test_builtin_upper_lower() {
            var p = new Preprocessor();
            string src = """@startuml
!if %upper("hello") == "HELLO"
class Up
!endif
!if %lower("WORLD") == "world"
class Down
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("class Up"));
            assert(res.contains("class Down"));
        }

        public static void test_builtin_function_exists() {
            var p = new Preprocessor();
            string src = """@startuml
!define FOO bar
!if %function_exists("FOO")
class FooDefined
!endif
!if %function_exists("BAZ")
class BazDefined
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("class FooDefined"));
            assert(!res.contains("class BazDefined"));
        }

        public static void test_builtin_is_dark() {
            var p = new Preprocessor();
            string src = """@startuml
!if %is_dark("#000000")
class BlackIsDark
!endif
!if %is_dark("#FFFFFF")
class WhiteIsDark
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res.contains("class BlackIsDark"));
            assert(!res.contains("class WhiteIsDark"));
        }

        public static void test_endif_without_if_logs_error() {
            var p = new Preprocessor();
            string src = "@startuml\n!endif\n@enduml";
            p.process(src, null);
            assert(p.has_errors());
        }

        public static void test_no_directive_no_substitution() {
            var p = new Preprocessor();
            string src = "@startuml\nclass Foo\n@enduml";
            string res = p.process(src, null);
            assert(res.contains("class Foo"));
        }

        // =================================================================
        // Fuzz: adversarial inputs that have historically broken
        // preprocessors. Each must terminate without crashing or hanging.
        // =================================================================

        public static void test_fuzz_recursive_macro() {
            var p = new Preprocessor();
            // Macro that names itself — must not infinite-loop.
            string src = """@startuml
!define X X
title X
@enduml""";
            string res = p.process(src, null);
            assert(res != null);
        }

        public static void test_fuzz_mutually_recursive_macros() {
            var p = new Preprocessor();
            string src = """@startuml
!define A B
!define B A
title A
@enduml""";
            string res = p.process(src, null);
            assert(res != null);
        }

        public static void test_fuzz_unterminated_if() {
            var p = new Preprocessor();
            string src = """@startuml
!if 1 == 1
class Foo
@enduml""";
            string res = p.process(src, null);
            assert(res != null);
        }

        public static void test_fuzz_unterminated_while() {
            var p = new Preprocessor();
            string src = """@startuml
!while 1
class Foo
@enduml""";
            string res = p.process(src, null);
            assert(res != null);
        }

        public static void test_fuzz_deeply_nested_ifdef() {
            var p = new Preprocessor();
            var sb = new StringBuilder();
            sb.append("@startuml\n");
            for (int i = 0; i < 20; i++) {
                sb.append_printf("!define M%d 1\n", i);
                sb.append_printf("!ifdef M%d\n", i);
            }
            sb.append("class Deep\n");
            for (int i = 0; i < 20; i++) {
                sb.append("!endif\n");
            }
            sb.append("@enduml\n");
            string res = p.process(sb.str, null);
            assert(res != null);
            assert(res.contains("class Deep"));
        }

        public static void test_fuzz_malformed_directives() {
            var p = new Preprocessor();
            string[] garbage = {
                "@startuml\n!define\n@enduml",
                "@startuml\n!define X\n@enduml",
                "@startuml\n!\n@enduml",
                "@startuml\n!undef\n@enduml",
                "@startuml\n!if\n!endif\n@enduml",
                "@startuml\n!ifdef FOO BAR BAZ\n!endif\n@enduml",
                "@startuml\n!include\n@enduml",
                "@startuml\n!include /nonexistent/file/path.puml\n@enduml",
            };
            foreach (var src in garbage) {
                string res = p.process(src, null);
                assert(res != null);
            }
        }

        // Expression evaluator fuzz ──────────────────────────────────

        public static void test_fuzz_expr_division_by_zero() {
            var p = new Preprocessor();
            string src = """@startuml
!if 10 / 0 == 0
class DivByZeroHandled
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res != null);
        }

        public static void test_fuzz_expr_unterminated_string() {
            var p = new Preprocessor();
            string src = """@startuml
!if "unterminated == "unterminated"
class X
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res != null);
        }

        public static void test_fuzz_expr_deeply_nested_parens() {
            var p = new Preprocessor();
            var sb = new StringBuilder();
            sb.append("@startuml\n!if ");
            for (int i = 0; i < 50; i++) sb.append("(");
            sb.append("1 == 1");
            for (int i = 0; i < 50; i++) sb.append(")");
            sb.append("\nclass Nested\n!endif\n@enduml");
            string res = p.process(sb.str, null);
            assert(res != null);
            assert(res.contains("class Nested"));
        }

        public static void test_fuzz_expr_mismatched_parens() {
            var p = new Preprocessor();
            string src = """@startuml
!if (1 == 1
class Mismatched
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res != null);
        }

        public static void test_fuzz_expr_chr_out_of_range() {
            var p = new Preprocessor();
            // Negative, zero, and too-large codepoints must not crash.
            string src = """@startuml
!define A %chr(-5)
!define B %chr(0)
!define C %chr(9999999)
!define D %chr(65)
class X_A_B_C_D
@enduml""";
            string res = p.process(src, null);
            assert(res != null);
        }

        public static void test_fuzz_expr_substr_out_of_bounds() {
            var p = new Preprocessor();
            string src = """@startuml
!define A %substr("hello", 99)
!define B %substr("hello", -99)
!define C %substr("hello", 0, 999)
!define D %substr("hello", 2, -1)
!define E %substr("", 0)
class OutOfBounds
@enduml""";
            string res = p.process(src, null);
            assert(res != null);
            assert(res.contains("class OutOfBounds"));
        }

        public static void test_fuzz_expr_empty() {
            var p = new Preprocessor();
            // Empty expression after !if — should not hang.
            string src = """@startuml
!if
class Empty
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res != null);
        }

        public static void test_fuzz_expr_only_operators() {
            var p = new Preprocessor();
            string src = """@startuml
!if + - * / && || == != < > <= >=
class OpsOnly
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res != null);
        }

        public static void test_fuzz_expr_is_dark_edge_cases() {
            var p = new Preprocessor();
            string src = """@startuml
!define A %is_dark("#000000")
!define B %is_dark("#FFFFFF")
!define C %is_dark("not a color")
!define D %is_dark("")
!define E %is_dark("#XYZ")
!define F %is_dark("#FFF")
class IsDarkCases
@enduml""";
            string res = p.process(src, null);
            assert(res != null);
            assert(res.contains("class IsDarkCases"));
        }

        public static void test_include_path_normalization() {
            // Two files that !include each other via different path
            // spellings that resolve to the same canonical file. The
            // circular-include detector must recognise them as the same
            // to avoid runaway recursion hitting MAX_INCLUDE_DEPTH.
            string tmp_dir = GLib.Path.build_filename(Environment.get_tmp_dir(),
                "gdiagram_inctest");
            DirUtils.create_with_parents(tmp_dir, 0755);

            string a_path = GLib.Path.build_filename(tmp_dir, "a.puml");
            // Reach a.puml via a `./` normalised form. The old
            // get_canonical_path used raw string equality, so `a.puml`
            // and `./a.puml` hashed to different keys and the guard
            // failed open.
            string b_body = "!include ./a.puml\nclass FromB\n";
            string a_body = "!include b.puml\nclass FromA\n";
            try {
                FileUtils.set_contents(a_path, a_body);
                FileUtils.set_contents(
                    GLib.Path.build_filename(tmp_dir, "b.puml"),
                    b_body);
            } catch (Error e) { return; }

            var p = new Preprocessor();
            string main = "@startuml\n!include %s\n@enduml\n".printf(a_path);
            string res = p.process(main, null);
            // Must terminate. Both files contribute their class decls
            // exactly once; the second include of a.puml is recognised
            // as circular and skipped.
            assert(res.contains("class FromA"));
            assert(res.contains("class FromB"));
            // And no "maximum include depth exceeded" error.
            bool saw_depth_error = false;
            foreach (var err in p.errors) {
                if (err.message.contains("depth")) saw_depth_error = true;
            }
            assert(!saw_depth_error);

            FileUtils.unlink(a_path);
            FileUtils.unlink(GLib.Path.build_filename(tmp_dir, "b.puml"));
            DirUtils.remove(tmp_dir);
        }

        public static void test_fuzz_expr_multiple_dots_in_number() {
            var p = new Preprocessor();
            // read_number accepts any number of dots; downstream double.parse
            // handles only the first decimal. Must not crash.
            string src = """@startuml
!if 1.2.3.4 == 1.2
class WeirdNumber
!endif
@enduml""";
            string res = p.process(src, null);
            assert(res != null);
        }

        public static void test_fuzz_very_long_input() {
            var p = new Preprocessor();
            var sb = new StringBuilder();
            sb.append("@startuml\n");
            for (int i = 0; i < 5000; i++) {
                sb.append_printf("class C%d\n", i);
            }
            sb.append("@enduml\n");
            string res = p.process(sb.str, null);
            assert(res != null);
            assert(res.contains("class C0"));
            assert(res.contains("class C4999"));
        }

        public static void main(string[] args) {
            Test.init(ref args);
            Test.add_func("/preprocessor/define-simple", test_define_simple_substitution);
            Test.add_func("/preprocessor/define-color", test_define_color_value);
            Test.add_func("/preprocessor/define-word-boundary", test_define_word_boundary);
            Test.add_func("/preprocessor/define-empty", test_define_empty_value);
            Test.add_func("/preprocessor/undef", test_undef);
            Test.add_func("/preprocessor/param-define-simple", test_parameterized_define_simple);
            Test.add_func("/preprocessor/param-define-multi", test_parameterized_define_multiple_args);
            Test.add_func("/preprocessor/param-define-quoted-arg", test_parameterized_define_quoted_arg_with_comma);
            Test.add_func("/preprocessor/param-define-dollar", test_parameterized_define_dollar_param);
            Test.add_func("/preprocessor/proc-unquoted-simple", test_unquoted_procedure_simple);
            Test.add_func("/preprocessor/proc-multi-line-body", test_procedure_multi_line_body);
            Test.add_func("/preprocessor/proc-quoted-keeps-quotes", test_quoted_procedure_keeps_quotes);
            Test.add_func("/preprocessor/proc-unquoted-strips-quotes", test_unquoted_procedure_strips_quotes);
            Test.add_func("/preprocessor/proc-default-params", test_default_param_values_used_when_arg_missing);
            Test.add_func("/preprocessor/proc-default-partial", test_default_param_values_partial_args);
            Test.add_func("/preprocessor/proc-unterminated-error", test_unterminated_procedure_logs_error);
            Test.add_func("/preprocessor/ifdef-taken", test_ifdef_taken_branch);
            Test.add_func("/preprocessor/ifdef-skipped", test_ifdef_skipped_branch);
            Test.add_func("/preprocessor/ifndef-skipped", test_ifndef_skipped_when_defined);
            Test.add_func("/preprocessor/ifndef-taken", test_ifndef_taken_when_undefined);
            Test.add_func("/preprocessor/ifdef-else", test_ifdef_else);
            Test.add_func("/preprocessor/ifdef-else-taken", test_ifdef_else_taken);
            Test.add_func("/preprocessor/nested-ifdef", test_nested_ifdef);
            Test.add_func("/preprocessor/if-eq-taken", test_if_string_equality_taken);
            Test.add_func("/preprocessor/if-eq-skipped", test_if_string_equality_skipped);
            Test.add_func("/preprocessor/if-numeric", test_if_numeric_comparison);
            Test.add_func("/preprocessor/if-and-or", test_if_logical_and_or);
            Test.add_func("/preprocessor/if-negation", test_if_negation);
            Test.add_func("/preprocessor/function-simple", test_function_simple_return);
            Test.add_func("/preprocessor/function-string-return", test_function_string_return);
            Test.add_func("/preprocessor/function-conditional-return", test_function_conditional_return);
            Test.add_func("/preprocessor/builtin-substr-strpos-strlen", test_builtin_substr_strpos_strlen);
            Test.add_func("/preprocessor/builtin-upper-lower", test_builtin_upper_lower);
            Test.add_func("/preprocessor/builtin-function-exists", test_builtin_function_exists);
            Test.add_func("/preprocessor/builtin-is-dark", test_builtin_is_dark);
            Test.add_func("/preprocessor/endif-stray", test_endif_without_if_logs_error);
            Test.add_func("/preprocessor/no-directive", test_no_directive_no_substitution);
            Test.add_func("/preprocessor/fuzz/recursive-macro", test_fuzz_recursive_macro);
            Test.add_func("/preprocessor/fuzz/mutual-recursive", test_fuzz_mutually_recursive_macros);
            Test.add_func("/preprocessor/fuzz/unterminated-if", test_fuzz_unterminated_if);
            Test.add_func("/preprocessor/fuzz/unterminated-while", test_fuzz_unterminated_while);
            Test.add_func("/preprocessor/fuzz/deep-nested-ifdef", test_fuzz_deeply_nested_ifdef);
            Test.add_func("/preprocessor/fuzz/malformed-directives", test_fuzz_malformed_directives);
            Test.add_func("/preprocessor/fuzz/very-long-input", test_fuzz_very_long_input);
            Test.add_func("/preprocessor/fuzz/expr-div-zero", test_fuzz_expr_division_by_zero);
            Test.add_func("/preprocessor/fuzz/expr-unterm-string", test_fuzz_expr_unterminated_string);
            Test.add_func("/preprocessor/fuzz/expr-deep-parens", test_fuzz_expr_deeply_nested_parens);
            Test.add_func("/preprocessor/fuzz/expr-mismatched-parens", test_fuzz_expr_mismatched_parens);
            Test.add_func("/preprocessor/fuzz/expr-chr-range", test_fuzz_expr_chr_out_of_range);
            Test.add_func("/preprocessor/fuzz/expr-substr-bounds", test_fuzz_expr_substr_out_of_bounds);
            Test.add_func("/preprocessor/fuzz/expr-empty", test_fuzz_expr_empty);
            Test.add_func("/preprocessor/fuzz/expr-only-ops", test_fuzz_expr_only_operators);
            Test.add_func("/preprocessor/fuzz/expr-is-dark", test_fuzz_expr_is_dark_edge_cases);
            Test.add_func("/preprocessor/fuzz/expr-multi-dot-num", test_fuzz_expr_multiple_dots_in_number);
            Test.add_func("/preprocessor/include-path-normalization", test_include_path_normalization);
            Test.run();
        }
    }
}
