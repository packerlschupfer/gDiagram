// Engine, CLI and performance findings from the GUI/LSP smoke test: C4 stereotypes taking
// over type detection, the CLI's fixed --scale temp file and double preprocessing, the
// standard library include cache, quadratic lexing and SVG post-processing, and PNG exports
// larger than a Cairo image may be.
using GDiagram;

string? tmp_root = null;

string tmp_dir() {
    if (tmp_root == null) {
        try {
            tmp_root = DirUtils.make_tmp("gdiagram-engine-XXXXXX");
        } catch (FileError e) {
            error("mkdtemp: %s", e.message);
        }
    }
    return tmp_root;
}

string write_file(string name, string content) {
    string path = Path.build_filename(tmp_dir(), name);
    DirUtils.create_with_parents(Path.get_dirname(path), 0755);
    try {
        FileUtils.set_contents(path, content);
    } catch (FileError e) {
        error("write %s: %s", path, e.message);
    }
    return path;
}

void expect_type(DiagramType got, DiagramType want, string what) {
    if (got != want) {
        printerr("\n%s: detected %s, want %s\n", what, got.to_string(), want.to_string());
        assert_not_reached();
    }
}

void expect(bool ok, string what) {
    if (!ok) {
        printerr("\n%s\n", what);
        assert_not_reached();
    }
}

// Width and height from a PNG's IHDR chunk
void png_size(string path, out int width, out int height) {
    width = height = -1;
    uint8[] data;
    try {
        FileUtils.get_data(path, out data);
    } catch (FileError e) {
        return;
    }
    if (data.length < 24) {
        return;
    }
    width = (data[16] << 24) | (data[17] << 16) | (data[18] << 8) | data[19];
    height = (data[20] << 24) | (data[21] << 16) | (data[22] << 8) | data[23];
}

string gdiagram_bin() {
    string? bin = Environment.get_variable("GDIAGRAM_BIN");
    if (bin == null || !FileUtils.test(bin, FileTest.IS_EXECUTABLE)) {
        error("GDIAGRAM_BIN must name the built gdiagram binary");
    }
    return bin;
}

/**
 * Runs the gdiagram CLI with extra environment, waiting at most `timeout_s`. Returns
 * the exit status, or -1 when it had to be killed.
 */
int run_cli(string[] args, string[] env, int timeout_s, out string err_text) {
    err_text = "";
    var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
    launcher.setenv("GSETTINGS_BACKEND", "memory", true);
    foreach (string kv in env) {
        int eq = kv.index_of("=");
        launcher.setenv(kv.substring(0, eq), kv.substring(eq + 1), true);
    }
    string[] argv = { gdiagram_bin() };
    foreach (string a in args) {
        argv += a;
    }
    Subprocess proc;
    try {
        proc = launcher.spawnv(argv);
    } catch (Error e) {
        error("spawn: %s", e.message);
    }
    // stderr is read on a thread so a chatty child can't fill the pipe and stall
    var err_stream = proc.get_stderr_pipe();
    var reader = new Thread<string>("stderr", () => {
        var sb = new StringBuilder();
        var buf = new uint8[4096];
        try {
            ssize_t n;
            while ((n = err_stream.read(buf)) > 0) {
                sb.append_len((string) buf, n);
            }
        } catch (IOError e) {
        }
        return sb.str;
    });
    int64 deadline = get_monotonic_time() + timeout_s * 1000000L;
    bool done = false;
    proc.wait_async.begin(null, (obj, res) => {
        try {
            proc.wait_async.end(res);
        } catch (Error e) {
        }
        done = true;
    });
    while (!done) {
        if (get_monotonic_time() > deadline) {
            proc.force_exit();
            try {
                proc.wait();
            } catch (Error e) {
            }
            err_text = reader.join();
            return -1;
        }
        MainContext.default().iteration(false);
        Thread.usleep(20000);
    }
    err_text = reader.join();
    return proc.get_if_exited() ? proc.get_exit_status() : -1;
}

const string SMALL_CLASS = "@startuml\nclass Alpha\nclass Beta\nAlpha <|-- Beta\n@enduml\n";

// ---- 1. C4 stereotypes decide the type only on description elements ----

void test_c4_stereotypes_do_not_hijack_detection() {
    expect_type(TypeDetector.detect_plantuml(
        "@startuml\nabstract class AbstractList\nclass ArrayList <<Container>>\nAbstractList <|-- ArrayList\n@enduml\n"),
        DiagramType.CLASS, "class with <<Container>>");
    expect_type(TypeDetector.detect_plantuml(
        "@startuml\nparticipant Bob <<System>>\nAlice -> Bob : hello\n@enduml\n"),
        DiagramType.SEQUENCE, "participant with <<System>>");
    expect_type(TypeDetector.detect_plantuml(
        "@startuml\nstate Idle <<system>>\n[*] --> Idle\nIdle --> Running\n@enduml\n"),
        DiagramType.STATE, "state with <<system>>");
    expect_type(TypeDetector.detect_plantuml(
        "@startuml\nclass Order <<person>>\nclass Line\nOrder *-- Line\n@enduml\n"),
        DiagramType.CLASS, "class with <<person>>");
    // "database" and "queue" are sequence participant keywords as well as the two
    // non-rectangle elements C4 draws, and the sequence signals have to win: both of
    // these render as sequence diagrams in plantuml.jar, not as component diagrams.
    expect_type(TypeDetector.detect_plantuml(
        "@startuml\nactor User\ndatabase DB <<System>>\nUser -> DB : query\n@enduml\n"),
        DiagramType.SEQUENCE, "database participant with <<System>>");
    expect_type(TypeDetector.detect_plantuml(
        "@startuml\nactor User\nqueue Q <<System>>\nUser -> Q : push\n@enduml\n"),
        DiagramType.SEQUENCE, "queue participant with <<System>>");
    // A database beside anything a sequence diagram cannot hold is still C4
    expect_type(TypeDetector.detect_plantuml(
        "@startuml\ndatabase \"DB\" <<container_db>> as db\ncomponent \"Web\" as web\nweb --> db\n@enduml\n"),
        DiagramType.COMPONENT, "database <<container_db>> beside a component");

    // Hand-written C4 (rectangles with the C4 stereotypes) stays a component diagram
    expect_type(TypeDetector.detect_plantuml(
        "@startuml\nrectangle \"Customer\" <<person>> as customer\n" +
        "rectangle \"Store\" <<system_boundary>> as store {\n" +
        "  rectangle \"Web\" <<container>> as web\n  database \"DB\" <<container_db>> as db\n}\n" +
        "customer --> web : Uses\nweb --> db : Reads\n@enduml\n"),
        DiagramType.COMPONENT, "native C4 rectangles");
    // A rectangle with <<boundary>>
    expect_type(TypeDetector.detect_plantuml(
        "@startuml\nrectangle \"Edge\" <<boundary>> as edge {\n  rectangle \"A\" as a\n}\n@enduml\n"),
        DiagramType.COMPONENT, "rectangle <<boundary>>");

    // The C4 stdlib expansion (rectangles and skinparam rectangle<<person>> blocks)
    var engine = new DiagramEngine("dot");
    var r = engine.parse(
        "@startuml\n!include <C4/C4_Container>\nPerson(user, \"User\")\n" +
        "System_Boundary(sb, \"Shop\") {\n  Container(web, \"Web\", \"Go\")\n}\nRel(user, web, \"Uses\")\n@enduml\n",
        null, null);
    expect_type(r.diagram_type, DiagramType.COMPONENT, "C4 stdlib include");
}

// ---- 2. CLI --scale renders to a private temp file ----

void test_cli_scale_private_temp_file() {
    string doc = write_file("scale/doc.puml", SMALL_CLASS);
    string tmp = Path.build_filename(tmp_dir(), "scale", "tmp");
    DirUtils.create_with_parents(tmp, 0700);
    string log = Path.build_filename(tmp_dir(), "scale", "convert.log");
    string bin_dir = Path.build_filename(tmp_dir(), "scale", "bin");
    DirUtils.create_with_parents(bin_dir, 0755);
    // A stand-in ImageMagick: logs the image it was given and copies it to the output
    string fake = write_file("scale/bin/convert",
        "#!/bin/sh\necho \"$1\" >> \"$FAKE_CONVERT_LOG\"\n[ -n \"$FAKE_CONVERT_FAIL\" ] && exit 3\ncp \"$1\" \"$6\"\n");
    FileUtils.chmod(fake, 0755);
    string path_env = "PATH=" + bin_dir + ":" + (Environment.get_variable("PATH") ?? "/usr/bin:/bin");

    string[] outputs = { Path.build_filename(tmp_dir(), "scale", "a.png"), Path.build_filename(tmp_dir(), "scale", "b.png") };
    foreach (string output in outputs) {
        string err;
        int rc = run_cli({ doc, "-e", output, "-f", "png", "--scale" },
                         { path_env, "TMPDIR=" + tmp, "FAKE_CONVERT_LOG=" + log }, 60, out err);
        expect(rc == 0, "--scale export failed (%d): %s".printf(rc, err));
        expect(FileUtils.test(output, FileTest.EXISTS), "--scale wrote no output");
    }
    string logged;
    try {
        FileUtils.get_contents(log, out logged);
    } catch (FileError e) {
        error("convert never ran: %s", e.message);
    }
    string[] paths = logged.strip().split("\n");
    expect(paths.length == 2, "expected two convert runs, got: " + logged);
    foreach (string p in paths) {
        expect(p != "/tmp/gdiagram_cli_export.png", "--scale rendered to the fixed /tmp path");
        expect(p.has_prefix(tmp + "/"), "--scale temp file not in TMPDIR: " + p);
        expect(!FileUtils.test(p, FileTest.EXISTS), "--scale left its temp file behind: " + p);
    }
    expect(paths[0] != paths[1], "two --scale exports shared one temp file");

    // A failing convert is an error, and the temp file is still removed
    string err2;
    int rc2 = run_cli({ doc, "-e", Path.build_filename(tmp_dir(), "scale", "c.png"), "-f", "png", "--scale" },
                      { path_env, "TMPDIR=" + tmp, "FAKE_CONVERT_LOG=" + log, "FAKE_CONVERT_FAIL=1" }, 60, out err2);
    expect(rc2 == 1, "failed convert should exit 1, got %d".printf(rc2));
    try {
        var dir = Dir.open(tmp);
        expect(dir.read_name() == null, "temp files left in TMPDIR after a failed convert");
    } catch (FileError e) {
        error("open tmp: %s", e.message);
    }
}

// ---- 3. The CLI preprocesses once ----

// The include is a FIFO that delivers its text once: a second preprocessing pass
// blocks opening it again, so the export only finishes when it preprocessed once.
void test_cli_preprocesses_once() {
    string dir = Path.build_filename(tmp_dir(), "once");
    DirUtils.create_with_parents(dir, 0755);
    string fifo = Path.build_filename(dir, "parts.iuml");
    expect(Posix.mkfifo(fifo, 0600) == 0, "mkfifo failed");
    string doc = write_file("once/doc.puml", "@startuml\n!include parts.iuml\nclass Alpha\nAlpha --> Beta\n@enduml\n");

    Posix.signal(Posix.Signal.PIPE, Posix.SIG_IGN);
    var writer = new Thread<bool>("fifo-writer", () => {
        var fs = FileStream.open(fifo, "w");
        if (fs != null) {
            fs.puts("class Beta\n");
        }
        return true;
    });

    foreach (string format in new string[] { "dot" }) {
        string output = Path.build_filename(dir, "out." + format);
        string err;
        int rc = run_cli({ doc, "-e", output, "-f", format }, {}, 20, out err);
        expect(rc == 0, "export with a read-once include did not finish (rc %d, killed = -1): %s".printf(rc, err));
        string dot;
        try {
            FileUtils.get_contents(output, out dot);
        } catch (FileError e) {
            error("no output: %s", e.message);
        }
        expect(dot.contains("Beta"), "included class missing from the export");
    }
    // Unblock the writer if the child never opened the pipe
    int fd = Posix.open(fifo, Posix.O_RDONLY | Posix.O_NONBLOCK);
    writer.join();
    if (fd >= 0) {
        Posix.close(fd);
    }

    // An unresolved include still exits 1 and still writes the partial export
    string bad = write_file("once/bad.puml", "@startuml\n!include missing_theme.iuml\nclass Alpha\n@enduml\n");
    string bad_out = Path.build_filename(dir, "bad.svg");
    string err_bad;
    int rc_bad = run_cli({ bad, "-e", bad_out, "-f", "svg" }, {}, 60, out err_bad);
    expect(rc_bad == 1, "unresolved include should exit 1, got %d".printf(rc_bad));
    expect(FileUtils.test(bad_out, FileTest.EXISTS), "partial export not written");
    expect(err_bad.contains("Cannot resolve include"), "include error not reported: " + err_bad);
}

// ---- 4. Standard library include cache ----

const string C4_DOC = "@startuml\n!include <C4/C4_Container>\nPerson(customer, \"Customer\")\n" +
    "System_Boundary(c1, \"Store\") {\n  Container(web, \"Web\", \"React\")\n}\nRel(customer, web, \"Uses\")\n@enduml\n";

string fresh_preprocess(string source, string? base_path) {
    Preprocessor.clear_include_cache();
    return new Preprocessor().process(source, base_path);
}

void test_stdlib_include_cache() {
    Preprocessor.clear_include_cache();
    string reference = new Preprocessor().process(C4_DOC, null);
    expect(reference.contains("<<person>>"), "C4 stdlib did not expand");
    expect(Preprocessor.include_cache_hits() == 0, "hit on an empty cache");

    // Another preprocessor (another tab / LSP document) reuses the expansion
    var second = new Preprocessor();
    string again = second.process(C4_DOC, null);
    expect(Preprocessor.include_cache_hits() >= 1, "C4 include was not served from the cache");
    expect(again == reference, "cached C4 expansion differs from a fresh one");
    expect(!second.has_errors(), "cached expansion reported errors");

    // A document that redefines a C4 procedure after the include: its own output uses its
    // procedure, and the next document still gets the stdlib's
    string custom_doc = "@startuml\n!include <C4/C4_Container>\n" +
        "!unquoted procedure Person($alias, $label, $descr=\"\", $sprite=\"\", $tags=\"\", $link=\"\", $type=\"\")\n" +
        "rectangle \"MINE_$label\" as $alias\n!endprocedure\nPerson(x, \"Y\")\n@enduml\n";
    string custom = new Preprocessor().process(custom_doc, null);
    expect(custom.contains("MINE_Y"), "redefined procedure not used");
    string after = new Preprocessor().process(C4_DOC, null);
    expect(after == reference, "a document's redefinition leaked into the cached stdlib state");
    expect(!after.contains("MINE_"), "redefinition leaked");

    // State before the include is part of the key: a define the stdlib reads changes the result
    string pre_doc = "@startuml\n!$tagDefaultLegend = \"PRE_INCLUDE_LEGEND\"\n" + C4_DOC.substring("@startuml\n".length);
    string with_pre = new Preprocessor().process(pre_doc, null);
    expect(with_pre == fresh_preprocess(pre_doc, null), "include after a variable differs from a fresh run");

    // No macro state leaks into a document without the include, on the same instance too
    var reused = new Preprocessor();
    reused.process(C4_DOC, null);
    string plain = reused.process("@startuml\nPerson(user, \"User\")\n@enduml\n", null);
    expect(plain.contains("Person(user, \"User\")"), "C4 macros leaked into a document without the include");
    var engine = new DiagramEngine("dot");
    engine.parse(C4_DOC, null, null);
    string plain2 = engine.preprocess("@startuml\nPerson(user, \"User\")\n@enduml\n", null);
    expect(plain2.contains("Person(user, \"User\")"), "C4 macros leaked between engine parses");
}

void copy_dir(string from, string to) {
    DirUtils.create_with_parents(to, 0755);
    try {
        var dir = Dir.open(from);
        string? name;
        while ((name = dir.read_name()) != null) {
            uint8[] data;
            FileUtils.get_data(Path.build_filename(from, name), out data);
            FileUtils.set_data(Path.build_filename(to, name), data);
        }
    } catch (FileError e) {
        error("copy %s: %s", from, e.message);
    }
}

void append_to(string path, string text) {
    try {
        string content;
        FileUtils.get_contents(path, out content);
        FileUtils.set_contents(path, content + text);
    } catch (FileError e) {
        error("append %s: %s", path, e.message);
    }
}

void test_stdlib_edit_invalidates_cache() {
    string? bundled = null;
    foreach (string d in Preprocessor.stdlib_dirs()) {
        if (FileUtils.test(Path.build_filename(d, "C4", "C4_Container.puml"), FileTest.EXISTS)) {
            bundled = d;
            break;
        }
    }
    expect(bundled != null, "bundled C4 stdlib not found");
    string copy = Path.build_filename(tmp_dir(), "stdlib");
    copy_dir(Path.build_filename(bundled, "C4"), Path.build_filename(copy, "C4"));
    string? old_env = Environment.get_variable("GDIAGRAM_STDLIB_DIR");
    Environment.set_variable("GDIAGRAM_STDLIB_DIR", copy, true);

    Preprocessor.clear_include_cache();
    string first = new Preprocessor().process(C4_DOC, null);
    expect(!first.contains("EDIT_MARK"), "unexpected mark");
    new Preprocessor().process(C4_DOC, null);
    expect(Preprocessor.include_cache_hits() >= 1, "copied stdlib not cached");

    // The included file itself
    append_to(Path.build_filename(copy, "C4", "C4_Container.puml"), "\nrectangle \"TOP_EDIT_MARK\" as top_mark\n");
    string edited = new Preprocessor().process(C4_DOC, null);
    expect(edited.contains("TOP_EDIT_MARK"), "edit of the included stdlib file not picked up");
    // A file it includes in turn
    append_to(Path.build_filename(copy, "C4", "C4.puml"), "\nrectangle \"NESTED_EDIT_MARK\" as nested_mark\n");
    string nested = new Preprocessor().process(C4_DOC, null);
    expect(nested.contains("NESTED_EDIT_MARK"), "edit of a nested stdlib file not picked up");
    expect(nested.contains("TOP_EDIT_MARK"), "earlier edit lost");

    if (old_env != null) {
        Environment.set_variable("GDIAGRAM_STDLIB_DIR", old_env, true);
    } else {
        Environment.unset_variable("GDIAGRAM_STDLIB_DIR");
    }
    Preprocessor.clear_include_cache();
}

// The modification time of `path`, in whole seconds and microseconds
void mtime_of(string path, out uint64 secs, out uint32 usecs) {
    secs = 0;
    usecs = 0;
    try {
        var info = File.new_for_path(path).query_info(
            FileAttribute.TIME_MODIFIED + "," + FileAttribute.TIME_MODIFIED_USEC, FileQueryInfoFlags.NONE);
        secs = info.get_attribute_uint64(FileAttribute.TIME_MODIFIED);
        usecs = info.get_attribute_uint32(FileAttribute.TIME_MODIFIED_USEC);
    } catch (Error e) {
        error("stat %s: %s", path, e.message);
    }
}

void set_mtime(string path, uint64 secs, uint32 usecs) {
    try {
        var info = new FileInfo();
        info.set_attribute_uint64(FileAttribute.TIME_MODIFIED, secs);
        info.set_attribute_uint32(FileAttribute.TIME_MODIFIED_USEC, usecs);
        File.new_for_path(path).set_attributes_from_info(info, FileQueryInfoFlags.NONE);
    } catch (Error e) {
        error("touch %s: %s", path, e.message);
    }
}

void test_local_include_edit_picked_up() {
    string inc = write_file("local/inc.iuml", "class Gamma\n");
    string doc_path = write_file("local/doc.puml", "@startuml\n!include inc.iuml\n@enduml\n");
    string doc = "@startuml\n!include inc.iuml\n@enduml\n";
    var engine = new DiagramEngine("dot");
    expect(engine.preprocess(doc, doc_path).contains("class Gamma"), "include not expanded");
    // Same size, newer modification time
    write_file("local/inc.iuml", "class Delta\n");
    try {
        var info = new FileInfo();
        info.set_attribute_uint64(FileAttribute.TIME_MODIFIED, (uint64) (get_real_time() / 1000000 + 10));
        File.new_for_path(inc).set_attributes_from_info(info, FileQueryInfoFlags.NONE);
    } catch (Error e) {
        error("touch: %s", e.message);
    }
    expect(engine.preprocess(doc, doc_path).contains("class Delta"), "same-size edit not picked up");
    // Different size
    write_file("local/inc.iuml", "class Epsilon\nclass Zeta\n");
    string third = engine.preprocess(doc, doc_path);
    expect(third.contains("class Epsilon") && !third.contains("Delta"), "edited include not picked up");
}

/**
 * The case the test above steps around by dating the file ten seconds into the future:
 * two writes of the same length inside one filesystem timestamp tick (~4 ms here). The
 * second modification time is then bit-for-bit the first, which is what the filesystem
 * really hands out — reproduced exactly by writing the recorded time back. The include
 * text cache served the first content for the second file, for every !include, not just
 * stdlib ones.
 */
void test_same_tick_same_size_include_edit() {
    string inc = write_file("tick/inc.iuml", "class Alpha\n");
    string doc_path = write_file("tick/doc.puml", "@startuml\n!include inc.iuml\n@enduml\n");
    string doc = "@startuml\n!include inc.iuml\n@enduml\n";
    var engine = new DiagramEngine("dot");

    uint64 secs;
    uint32 usecs;
    mtime_of(inc, out secs, out usecs);
    expect(engine.preprocess(doc, doc_path).contains("class Alpha"), "include not expanded");

    // Same length, same modification time to the microsecond
    write_file("tick/inc.iuml", "class Bravo\n");
    set_mtime(inc, secs, usecs);
    uint64 secs2;
    uint32 usecs2;
    mtime_of(inc, out secs2, out usecs2);
    expect(secs2 == secs && usecs2 == usecs, "the test could not reproduce an unchanged mtime");
    string second = engine.preprocess(doc, doc_path);
    expect(second.contains("class Bravo") && !second.contains("class Alpha"),
           "a same-size edit inside one clock tick was served from the cache");

    // And once more, so the cache cannot simply be off
    write_file("tick/inc.iuml", "class Charl\n");
    set_mtime(inc, secs, usecs);
    expect(engine.preprocess(doc, doc_path).contains("class Charl"), "third same-size edit not picked up");
}

const string WRAP_DOC = "@startuml\n!include <C4/Wrap>\n@enduml\n";

/**
 * The include cache is process-wide (GUI tabs, LSP documents) and its key deliberately
 * leaves the document's own file out of the included set, so two documents that differ
 * only in which file they are share one entry. That is wrong as soon as the include can
 * reach the document itself: that document skips it as a circular include of itself and
 * says so, and it used to be handed the other document's expansion instead — silently,
 * without the diagnostic.
 */
void test_include_cache_is_per_document() {
    string stdlib = Path.build_filename(tmp_dir(), "selfstdlib");
    write_file("selfstdlib/C4/helper.puml", "class HelperBody\n");
    write_file("selfstdlib/C4/Wrap.puml", "!include helper.puml\nclass WrapBody\n");
    string plain_doc = write_file("selfdoc/plain.puml", WRAP_DOC);
    string helper_doc = Path.build_filename(stdlib, "C4", "helper.puml");

    string? old_env = Environment.get_variable("GDIAGRAM_STDLIB_DIR");
    Environment.set_variable("GDIAGRAM_STDLIB_DIR", stdlib, true);
    Preprocessor.clear_include_cache();

    // An ordinary document expands the wrapper and the file it includes, and caches it
    string plain = new Preprocessor().process(WRAP_DOC, plain_doc);
    expect(plain.contains("class WrapBody") && plain.contains("class HelperBody"),
           "the wrapper include did not expand");
    expect(!plain.contains("Circular include"), "an ordinary document reported a cycle");

    // The same source, preprocessed as C4/helper.puml itself: the wrapper's include of
    // helper.puml is the document, so it is skipped and reported
    string self = new Preprocessor().process(WRAP_DOC, helper_doc);
    expect(self.contains("Circular include skipped"),
           "the document's own file was not reported as a cycle:\n" + self);
    expect(!self.contains("class HelperBody"),
           "the document's own body was pasted in from another document's cache entry:\n" + self);
    expect(self.contains("class WrapBody"), "the wrapper itself did not expand");

    // The ordinary document is still cached and still right
    int hits_before = Preprocessor.include_cache_hits();
    string plain_again = new Preprocessor().process(WRAP_DOC, plain_doc);
    expect(plain_again == plain, "the ordinary document's expansion changed");
    expect(Preprocessor.include_cache_hits() > hits_before, "the include cache stopped working");

    if (old_env != null) {
        Environment.set_variable("GDIAGRAM_STDLIB_DIR", old_env, true);
    } else {
        Environment.unset_variable("GDIAGRAM_STDLIB_DIR");
    }
    Preprocessor.clear_include_cache();
}

// ---- 5. Linear lexing and SVG post-processing ----

void test_lexer_is_linear() {
    var sb = new StringBuilder();
    int i = 0;
    while (sb.len < 1000000) {
        sb.append_printf("class C%d <<entity>> {\n  +name : String\n}\nC%d --> C%d : \"label %d\"\n", i, i, i + 1, i);
        i++;
    }
    var timer = new Timer();
    var tokens = new Lexer(sb.str).scan_all();
    double secs = timer.elapsed();
    expect(tokens.size > 100000, "too few tokens");
    expect(secs < 5.0, "lexing 1 MB took %.1f s".printf(secs));
}

void test_split_text_join_is_linear() {
    var sb = new StringBuilder("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100pt\" height=\"100pt\">\n");
    int i = 0;
    while (sb.len < 4000000) {
        sb.append_printf("<text text-anchor=\"start\" x=\"10\" y=\"%d\" font-family=\"Sans\" font-size=\"14.00\">async </text>\n", i);
        sb.append_printf("<text text-anchor=\"start\" x=\"50\" y=\"%d\" font-family=\"Sans\" font-size=\"10.00\">(dashed)</text>\n", i);
        i++;
    }
    sb.append("</svg>\n");
    var timer = new Timer();
    string joined = ComponentDiagramRenderer.join_split_text(sb.str);
    double secs = timer.elapsed();
    expect(joined.contains("<tspan"), "spans were not joined");
    expect(secs < 5.0, "joining split text in 4 MB of SVG took %.1f s".printf(secs));
}

// ---- 6. PNG exports scale down to the Cairo size limit ----

void test_png_scaled_to_cairo_limit() {
    RenderUtils.png_downscale_note = null;
    string svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100px\" height=\"40000px\">" +
        "<rect width=\"100\" height=\"40000\" fill=\"red\"/></svg>";
    string path = Path.build_filename(tmp_dir(), "tall_svg.png");
    expect(RenderUtils.export_svg_to_png(svg.data, path), "tall SVG PNG export failed");
    int w, h;
    png_size(path, out w, out h);
    int cap = (int) RenderUtils.MAX_SURFACE_SIDE;
    expect(h == cap && w == (int) Math.floor(100 * (double) cap / 40000),
           "tall SVG PNG is %dx%d, want a %d px tall page".printf(w, h, cap));
    expect(RenderUtils.png_downscale_note != null, "no downscale note");

    // A small image is untouched and leaves no note
    RenderUtils.png_downscale_note = null;
    string small = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"120px\" height=\"80px\"><rect width=\"120\" height=\"80\"/></svg>";
    expect(RenderUtils.export_svg_to_png(small.data, path), "small PNG export failed");
    png_size(path, out w, out h);
    expect(w == 120 && h == 80, "small PNG is %dx%d".printf(w, h));
    expect(RenderUtils.png_downscale_note == null, "note for an image that fits");

    // A renderer's own PNG export: a tall class diagram (it failed with InvalidSize)
    var sb = new StringBuilder("@startuml\n");
    for (int i = 0; i < 400; i++) {
        sb.append_printf("class C%d\n", i);
    }
    for (int i = 0; i < 399; i++) {
        sb.append_printf("C%d --> C%d\n", i, i + 1);
    }
    sb.append("@enduml\n");
    string class_png = Path.build_filename(tmp_dir(), "tall_class.png");
    RenderUtils.png_downscale_note = null;
    expect(new DiagramEngine("dot").export_to_png(sb.str, null, null, class_png), "tall class diagram PNG export failed");
    png_size(class_png, out w, out h);
    expect(h == cap && w > 0 && w < cap, "tall class PNG is %dx%d".printf(w, h));
    expect(RenderUtils.png_downscale_note != null, "no downscale note for the class diagram");
}

void test_fit_surface_size() {
    double w = 50000, h = 1000;
    double f = RenderUtils.fit_surface_size(ref w, ref h);
    expect(w == RenderUtils.MAX_SURFACE_SIDE && h == Math.floor(1000 * f), "wide fit %gx%g".printf(w, h));
    w = 30000; h = 30000;
    RenderUtils.fit_surface_size(ref w, ref h);
    expect(w * h <= RenderUtils.MAX_SURFACE_PIXELS && Math.fabs(w - h) < 1, "pixel cap %gx%g".printf(w, h));
    w = 800; h = 600;
    expect(RenderUtils.fit_surface_size(ref w, ref h) == 1.0 && w == 800 && h == 600, "fitting size changed");

    // Both sides were floored, so an aspect ratio past 1:32767 rounded the short one to
    // zero and Cairo then refused the surface, reported as a plain "export failed"
    RenderUtils.png_downscale_note = null;
    w = 1; h = 100000;
    RenderUtils.fit_surface_size(ref w, ref h);
    expect(w >= 1 && h >= 1 && h <= RenderUtils.MAX_SURFACE_SIDE, "1x100000 became %gx%g".printf(w, h));
    expect(RenderUtils.png_downscale_note != null && !RenderUtils.png_downscale_note.contains("x0 "),
           "downscale note: %s".printf(RenderUtils.png_downscale_note ?? "(none)"));

    // A size no int can hold must not print as -2147483648 or collapse to 0x0
    RenderUtils.png_downscale_note = null;
    w = 1e200; h = 1e200;
    RenderUtils.fit_surface_size(ref w, ref h);
    expect(w >= 1 && h >= 1, "1e200 square became %gx%g".printf(w, h));
    expect(RenderUtils.png_downscale_note == null || !RenderUtils.png_downscale_note.contains("-"),
           "downscale note has a negative size: %s".printf(RenderUtils.png_downscale_note ?? "(none)"));

    // NaN is not a size: it slipped past "width <= 0" and came out as a negative int
    RenderUtils.png_downscale_note = null;
    w = Math.sqrt(-1.0); h = 100;
    expect(RenderUtils.fit_surface_size(ref w, ref h) == 1.0, "a NaN width was scaled");
    expect(RenderUtils.png_downscale_note == null, "a NaN width left a note: %s".printf(
           RenderUtils.png_downscale_note ?? "(none)"));

    // End to end: the PNG a 1-pixel-wide, very tall drawing exports to
    RenderUtils.png_downscale_note = null;
    string thin = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1px\" height=\"100000px\">" +
        "<rect width=\"1\" height=\"100000\" fill=\"blue\"/></svg>";
    string thin_path = Path.build_filename(tmp_dir(), "thin.png");
    expect(RenderUtils.export_svg_to_png(thin.data, thin_path), "1x100000 PNG export failed");
    int tw, th;
    png_size(thin_path, out tw, out th);
    expect(tw >= 1 && th >= 1 && th <= RenderUtils.MAX_SURFACE_SIDE, "1x100000 PNG is %dx%d".printf(tw, th));
}

int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/engine/c4-stereotypes-detection", test_c4_stereotypes_do_not_hijack_detection);
    Test.add_func("/engine/cli-scale-private-temp", test_cli_scale_private_temp_file);
    Test.add_func("/engine/cli-preprocess-once", test_cli_preprocesses_once);
    Test.add_func("/engine/stdlib-include-cache", test_stdlib_include_cache);
    Test.add_func("/engine/stdlib-edit-invalidates", test_stdlib_edit_invalidates_cache);
    Test.add_func("/engine/local-include-edit", test_local_include_edit_picked_up);
    Test.add_func("/engine/same-tick-include-edit", test_same_tick_same_size_include_edit);
    Test.add_func("/engine/include-cache-per-document", test_include_cache_is_per_document);
    Test.add_func("/engine/lexer-linear", test_lexer_is_linear);
    Test.add_func("/engine/split-text-join-linear", test_split_text_join_is_linear);
    Test.add_func("/engine/png-cairo-limit", test_png_scaled_to_cairo_limit);
    Test.add_func("/engine/fit-surface-size", test_fit_surface_size);
    return Test.run();
}
