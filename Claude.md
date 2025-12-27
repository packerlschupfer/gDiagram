# gPlantUML - Native GTK PlantUML Viewer

## Overview
gPlantUML is a native Linux application for viewing and editing PlantUML diagrams with live preview. Built with GTK4/Libadwaita, it provides a modern GNOME-integrated experience for working with UML diagrams.

## Architecture

### Technology Stack
- **Language**: Vala (compiles to C)
- **UI Framework**: GTK4 + Libadwaita
- **Rendering**: Graphviz (libgvc) + Cairo + librsvg
- **Build System**: Meson
- **Package Format**: Debian (.deb)

### Core Components

#### 1. Parser Layer (`src/core/parser/`)
Lexer-based parsers for each diagram type:
- **Lexer.vala** - Tokenizes PlantUML source
- **Token.vala** - Token types and definitions
- **Preprocessor.vala** - Handles !include, !define
- **Parser.vala** - Sequence diagram parser
- **ClassDiagramParser.vala** - Class diagrams
- **ActivityDiagramParser.vala** - Activity diagrams (orchestrator pattern)
  - **activity/** - 7 specialized parsers (actions, control flow, structure, metadata, etc.)
- **UseCaseDiagramParser.vala** - Use case diagrams
- **StateDiagramParser.vala** - State diagrams
- **ComponentDiagramParser.vala** - Component diagrams
- **ObjectDiagramParser.vala** - Object diagrams
- **DeploymentDiagramParser.vala** - Deployment diagrams
- **ERDiagramParser.vala** - Entity-relationship diagrams
- **MindMapDiagramParser.vala** - Mind maps and WBS

#### 2. AST Layer (`src/core/ast/`)
Object models representing parsed diagrams:
- **DiagramNode.vala** - Base types (Participant, Message, etc.)
- **Theme.vala** - Skinparam and styling
- **{Type}Diagram.vala** - Diagram-specific AST classes

#### 3. Renderer Layer (`src/core/renderer/`)
Graphviz-based rendering using facade pattern:
- **GraphvizRenderer.vala** - Facade delegating to specialized renderers
- **RenderUtils.vala** - Shared utilities (escape functions, SVG parsing, ElementRegion)
- **sequence/** - SequenceDiagramRenderer (lifeline-based layout)
- **structural/** - Class, Component, Object renderers
- **behavioral/** - Activity, UseCase, State renderers
- **specialized/** - Deployment, ER, MindMap renderers

#### 4. UI Layer (`src/ui/`)
GTK4/Libadwaita interface:
- **MainWindow.vala** - Application window
- **DocumentView.vala** - Source editor with GtkSourceView
- **PreviewPane.vala** - Live diagram preview with click-to-source navigation
- **ExportDialog.vala** - PNG/SVG/PDF export
- **PreferencesDialog.vala** - Settings
- **AIAssistantDialog.vala** - AI integration (future)
- **DiagramCompareDialog.vala** - Version comparison

#### 5. Application Core (`src/`)
- **Application.vala** - GtkApplication main class
- **Document.vala** - Document management and diagram type detection
- **services/AIService.vala** - AI integration service

## Key Features

### Diagram Type Support
1. **Sequence Diagrams** - Participants with lifelines, messages, activations, frames (alt/opt/loop/etc.)
2. **Class Diagrams** - Classes, interfaces, relationships, packages
3. **Activity Diagrams** - Actions, control flow, swimlanes, partitions, SDL shapes
4. **Use Case Diagrams** - Actors, use cases, packages
5. **State Diagrams** - States, transitions, composite states
6. **Component Diagrams** - Components, containers, interfaces, ports
7. **Object Diagrams** - Object instances, links
8. **Deployment Diagrams** - Nodes, artifacts, deployment
9. **ER Diagrams** - Entities, relationships, cardinality
10. **Mind Maps / WBS** - Hierarchical diagrams

### Rendering Features
- **Live Preview** - Real-time rendering as you type (debounced)
- **Click-to-Source** - Click elements to jump to source line
- **Export Formats** - PNG, SVG, PDF
- **Color Support** - Hex colors (#FF0000), named colors (red, lightblue)
- **Multi-line Labels** - HTML table-based rendering for complex labels
- **Themes** - Skinparam support for customization

### Sequence Diagram Specifics
- **Lifeline Layout** - Participants at top/bottom with vertical lifelines
- **Invisible Connection Points** - Clean arrows without visible dots
- **Multi-line Participants** - HTML TABLE cells for Title/SubTitle separation
- **Participant Types** - Different shapes (actor=octagon, database=cylinder, etc.)
- **Message Styles** - Solid/dotted arrows, open/closed arrowheads
- **Frames** - alt, opt, loop, par, critical, ref, break

### Component Diagram Specifics
- **Container Support** - Nested rectangles, frames, packages
- **Element Types** - rectangle, component, artifact, card, agent, queue, boundary, control, entity
- **Color Parsing** - Multi-word named colors (LightGreen, PeachPuff)
- **Auto-Detection** - Recognizes component diagrams by keywords

## Code Organization

### Refactored Architecture
The codebase uses separation of concerns with focused, maintainable files:

**Before Refactoring:**
- GraphvizRenderer.vala: 4,128 lines (monolithic)
- ActivityDiagramParser.vala: 2,455 lines (monolithic)

**After Refactoring:**
- GraphvizRenderer.vala: 325 lines (facade)
- ActivityDiagramParser.vala: 507 lines (orchestrator)
- 20 specialized files organized by responsibility

### Design Patterns
1. **Facade Pattern** - GraphvizRenderer delegates to specialized renderers
2. **Orchestrator Pattern** - ActivityDiagramParser coordinates specialized parsers
3. **Delegate Pattern** - Control flow parsers use callbacks for nested parsing
4. **Static Utilities** - RenderUtils, ActivityTextFormatter (pure functions)

## Build and Installation

### Build Commands
```bash
meson setup build
meson compile -C build
dpkg-buildpackage -us -uc -b
sudo dpkg -i ../gplantuml_0.1.0-1_amd64.deb
```

### Running
```bash
gplantuml                    # Launch GUI
gplantuml file.puml          # Open file (DBus issues - use GUI File→Open instead)
```

## Known Issues and Solutions

### Sequence Diagrams
- **Graphviz Limitations** - Perfect vertical lifelines difficult with Graphviz's constraint solver
- **Current Approach** - Lifeline-based with invisible connection points works well for most cases
- **Alternative** - Future: Custom SVG generation for pixel-perfect UML

### Component Diagrams
- **Nested Elements** - Must use `{ }` braces for containers
- **Color Syntax** - Use `#` prefix for both hex and named colors (parser strips # from named colors)

### Command Line
- **DBus Error** - Passing files via command line triggers "does not handle command line arguments"
- **Workaround** - Launch GUI first, then use File→Open

## Development Notes

### Adding New Diagram Types
1. Create parser in `src/core/parser/`
2. Create AST model in `src/core/ast/`
3. Create renderer in appropriate `src/core/renderer/` subdirectory
4. Add to GraphvizRenderer facade
5. Update DocumentView diagram type detection
6. Add to meson.build

### Color Handling
- **Parser** - Accepts colors with `#` prefix
- **Renderer** - Must normalize: strip `#` from named colors, keep for hex codes
- **Graphviz** - Only accepts `#` for hex codes (#FF0000), not named colors (#red)

### Multi-line Labels
- Use `\n` escape for simple line breaks
- Use HTML TABLE for structured content (separate boxes)
- Set `shape=plaintext` when using HTML labels to avoid double borders

## File Locations
- **Source**: `/home/mrnice/Documents/Projects/gPlantUML/src/`
- **Build**: `/home/mrnice/Documents/Projects/gPlantUML/build/`
- **Package**: `/home/mrnice/Documents/Projects/gPlantUML/../gplantuml_0.1.0-1_amd64.deb`
- **Installed Binary**: `/usr/bin/gplantuml`
- **Desktop File**: `/usr/share/applications/org.gnome.gPlantUML.desktop`

## Testing
Use test diagrams in `/tmp/` for quick validation:
- Sequence: Alice/Bob messages
- Component: Rectangle containers with nested elements
- All diagrams: Test colors, multi-line labels, special characters
