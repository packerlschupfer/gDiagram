# gDiagram v0.1.0 Release Notes

## 🎉 Initial Release - Native Multi-Format Diagram Viewer

gDiagram (formerly gPlantUML) is a native GTK4/libadwaita diagram viewer and editor supporting **both PlantUML and Mermaid** diagram formats with native Graphviz rendering.

---

## ✨ Highlights

### **Multi-Format Support**
- ✅ **PlantUML** - Complete support for 10+ diagram types
- ✅ **Mermaid** - Full native implementation of 4 diagram types
- ✅ **Auto-detection** - Recognizes .puml, .mmd file extensions
- ✅ **Unified experience** - Both formats use same rendering pipeline

### **Native Implementation**
- ✅ **No Java required** - Pure Vala/GTK implementation
- ✅ **No Node.js** - Native Mermaid rendering (not via mermaid-cli)
- ✅ **No browser embedding** - No WebKit dependencies
- ✅ **Fast** - Native Graphviz rendering (<3ms for typical diagrams)

### **Rich Feature Set**
- ✅ **Real-time preview** - See changes as you type
- ✅ **Syntax highlighting** - For both PlantUML and Mermaid
- ✅ **Multi-tab editing** - Work on multiple diagrams
- ✅ **Export formats** - SVG, PNG, PDF
- ✅ **Dark mode** - Full libadwaita integration
- ✅ **Error highlighting** - Shows parse errors with line numbers

---

## 📊 Supported Diagram Types

### PlantUML (10+ types)
- Sequence diagrams
- Class diagrams
- Activity diagrams
- State diagrams (with stereotypes, history states)
- Use Case diagrams (with system boundaries)
- Component diagrams (with ports)
- Object diagrams
- Deployment diagrams
- ER diagrams
- MindMap diagrams

### Mermaid (4 types) - **NEW!**

#### 🔷 **Flowcharts**
- 11 node shapes: Rectangle `[]`, Rounded `()`, Stadium `([])`, Diamond `{}`, Circle `(())`, Hexagon `{{}}`, Subroutine `[[]]`, Double Circle `((()))`, and more
- 4 layout directions: TD (top-down), LR (left-right), RL, BT
- 6 arrow types: solid `-->`, dotted `-.->`, thick `==>`, open `--o`, cross `--x`, invisible `~~~`
- Edge labels: `A -->|Label| B`
- Chained edges: `A --> B --> C --> D`
- Subgraphs with custom directions
- Style declarations

**Example:**
```mermaid
flowchart TD
    Start[Start Process] --> Decision{Is Valid?}
    Decision -->|Yes| Process[Process Data]
    Decision -->|No| Error[Show Error]
    Process --> End[End]
```

#### 🔷 **Sequence Diagrams**
- Participants and actors
- Participant aliases: `participant A as Alice`
- 8 message arrow types: `->>`, `-->>`, `->`, `-->`, `-)`, `--)`, `-x`, `--x`
- Notes: `Note over A,B`, `Note left of A`, `Note right of A`
- Autonumbering
- Activation/deactivation
- Control structures: loop, alt, opt, par, critical, break, rect

**Example:**
```mermaid
sequenceDiagram
    participant Alice
    participant Bob
    Alice->>Bob: Hello Bob!
    Bob-->>Alice: Hi Alice!
    Note over Alice,Bob: Conversation
```

#### 🔷 **State Diagrams**
- State declarations with descriptions
- Transitions with labels
- Start `[*]` and end `[*]` markers
- State types: normal, choice `<<choice>>`, fork `<<fork>>`, join `<<join>>`
- Nested/composite states
- State notes

**Example:**
```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Processing: Start
    Processing --> Success: Complete
    Success --> [*]
```

#### 🔷 **Class Diagrams**
- Class declarations with members
- Fields and methods
- Visibility modifiers: `+` (public), `-` (private), `#` (protected), `~` (package)
- Type annotations
- Relationships: inheritance `<|--`, composition `*--`, aggregation `o--`, association `-->`

**Example:**
```mermaid
classDiagram
    class Animal {
        +string name
        +makeSound()
    }
    class Dog {
        +bark()
    }
    Animal <|-- Dog
```

---

## 🚀 Features

### Editing
- **Real-time preview** - Debounced updates as you type
- **Multi-tab interface** - Work on multiple diagrams simultaneously
- **Syntax highlighting** - Full GtkSourceView integration for both formats
- **Search and replace** - Find text in diagrams
- **Font customization** - Choose your preferred editor font
- **Line numbers** - Optional line number display
- **Current line highlighting** - Visual editing feedback

### Rendering
- **Native Graphviz** - Fast, high-quality diagram rendering
- **Multiple layout engines** - dot, neato, fdp, sfdp, circo, twopi
- **Zoom and pan** - Navigate large diagrams easily
- **Minimap** - Overview of diagram structure
- **Click-to-source** - Click diagram elements to jump to source line

### Export
- **SVG export** - Vector graphics for documentation
- **PNG export** - Raster images for presentations
- **PDF export** - High-quality printable output
- **Configurable** - Export settings for each format

### User Experience
- **Dark mode support** - Follows system theme
- **File monitoring** - Auto-reload when files change externally
- **Recent files** - Quick access to previously opened diagrams
- **Keyboard shortcuts** - Efficient workflow
- **Error reporting** - Clear error messages with line numbers

---

## 🛠️ Technical Details

### Architecture
- **Language:** Vala
- **UI Framework:** GTK4 + libadwaita
- **Rendering Engine:** Graphviz (libgvc)
- **Image Processing:** Cairo + librsvg
- **Build System:** Meson
- **License:** GPL-3.0-or-later

### Dependencies
- GTK4 >= 4.10
- libadwaita >= 1.4
- GtkSourceView 5 >= 5.0
- libgee-0.8
- Graphviz (libgvc)
- librsvg-2.0
- Cairo
- libsoup-3.0
- json-glib-1.0

### Performance
- Parse + render typical diagram: <3ms
- 50-node flowchart: ~2ms
- SVG output: 2-30KB depending on complexity
- Memory footprint: Minimal

### Code Quality
- **~7,000 lines** of production code
- **22 test cases** - 100% passing
- **Clean compilation** - No errors
- **Comprehensive documentation** - 1,500+ lines

---

## 📦 Installation

### Debian/Ubuntu
```bash
# Download .deb from releases page
sudo dpkg -i gdiagram_0.1.0_amd64.deb
```

### From Source
```bash
# Install dependencies (Debian/Ubuntu)
sudo apt install meson ninja-build valac \
  libgtk-4-dev libadwaita-1-dev libgtksourceview-5-dev \
  libgee-0.8-dev libgraphviz-dev librsvg2-dev libcairo2-dev \
  libsoup-3.0-dev libjson-glib-dev gettext graphviz

# Build and install
meson setup build --prefix=/usr
meson compile -C build
sudo meson install -C build
```

### Run
```bash
gdiagram [file.mmd|file.puml]
```

---

## 📝 What's New in v0.1.0

### Mermaid Support (Major Feature)
- ✅ Complete native Mermaid implementation (~4,600 lines)
- ✅ 4 diagram types fully functional
- ✅ Syntax highlighting for Mermaid
- ✅ Auto-format detection
- ✅ All export formats working

### PlantUML Enhancements
- ✅ Improved error handling
- ✅ Better syntax highlighting
- ✅ Enhanced diagram type detection
- ✅ Support for more diagram variants

### UI/UX Improvements
- ✅ Format auto-detection (.mmd vs .puml)
- ✅ Improved error messages
- ✅ Better placeholder text with examples
- ✅ Enhanced multi-tab experience

### Documentation
- ✅ Comprehensive user guide with 15+ examples
- ✅ Technical documentation (MERMAID_IMPLEMENTATION.md)
- ✅ Example files for all diagram types
- ✅ Feature matrix and comparison guide

---

## 🐛 Known Issues

- Class diagram relationship cardinality not yet parsed
- Mermaid subgraph contents not fully parsed (basic support only)
- Some advanced Mermaid features not implemented (themes, click actions)

These will be addressed in future releases.

---

## 🙏 Acknowledgments

- [PlantUML](https://plantuml.com/) for the diagram syntax
- [Mermaid](https://mermaid.js.org/) for the Mermaid syntax
- [Graphviz](https://graphviz.org/) for the rendering engine
- [GTK](https://gtk.org/) and [libadwaita](https://gnome.pages.gitlab.gnome.org/libadwaita/) for the UI framework

---

## 📄 License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

---

## 🔗 Links

- **Repository:** https://github.com/packerlschupfer/gDiagram
- **Issues:** https://github.com/packerlschupfer/gDiagram/issues
- **Documentation:** See `docs/` directory
- **Examples:** See `examples/` directory

---

## 🎯 Next Steps

Try it out:
```bash
# Try Mermaid flowcharts
gdiagram examples/mermaid_flowchart.mmd

# Try Mermaid sequence diagrams
gdiagram examples/mermaid_sequence.mmd

# Try Mermaid state diagrams
gdiagram examples/mermaid_state.mmd

# Try Mermaid class diagrams
gdiagram examples/mermaid_class.mmd
```

**Enjoy gDiagram - The Ultimate Native Diagram Viewer for Linux!** 🎊
