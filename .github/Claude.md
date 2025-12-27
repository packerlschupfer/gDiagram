# gPlantUML Development Guide for Claude

## Quick Reference

### Project Type
Native Linux GTK4 application written in Vala for viewing/editing PlantUML diagrams.

### Common Tasks

#### Build and Install
```bash
meson compile -C build
dpkg-buildpackage -us -uc -b
sudo dpkg -i ../gplantuml_0.1.0-1_amd64.deb
```

#### Testing
```bash
gplantuml  # Launch GUI, use File→Open to test diagrams
# Don't use command-line file argument (DBus issues)
```

#### Add New Files to Build
Edit `src/meson.build` and add to the source list.

### Architecture Patterns

#### Renderers (Facade Pattern)
All diagram renderers follow this pattern:
```vala
public class XxxDiagramRenderer : Object {
    private unowned Gvc.Context context;
    private Gee.ArrayList<ElementRegion> last_regions;
    private string layout_engine;

    public XxxDiagramRenderer(unowned Gvc.Context ctx, ...) { }
    public string generate_dot(XxxDiagram diagram) { }
    public uint8[]? render_to_svg(XxxDiagram diagram) { }
    public Cairo.ImageSurface? render_to_surface(XxxDiagram diagram) { }
    public bool export_to_png/svg/pdf(...) { }
}
```

GraphvizRenderer.vala is a facade that delegates to these specialized renderers.

#### Parsers (Orchestrator Pattern)
- Main parser (e.g., ActivityDiagramParser) orchestrates specialized parsers
- Specialized parsers handle specific syntax (edges, actions, control flow, etc.)
- State passed by reference (`ref int current`)

### Important Conventions

#### Color Handling
**CRITICAL**: Graphviz only accepts `#` prefix for hex codes, NOT named colors.

**Parser**: Accepts both `#red` and `#FF0000`
**Renderer**: Must call `normalize_color()`:
```vala
private string? normalize_color(string? color) {
    if (color.has_prefix("#")) {
        string value = color.substring(1);
        if (is_hex_color(value)) return color;  // Keep #FF0000
        return value;  // Return 'red' not '#red'
    }
    return color;
}
```

#### Multi-line Labels
For structured content (separate boxes):
```vala
// Use HTML TABLE with BORDER="0", CELLBORDER="1"
// Set shape=plaintext to avoid double borders
```

For simple multi-line:
```vala
// Use \n escape in label string
```

### Common Bugs to Avoid

1. **Color Warnings** - Always normalize colors before passing to Graphviz
2. **Double Borders** - Use `shape=plaintext` with HTML labels
3. **Participant Lookup** - Keep `name` simple for matching, use `display_label` for rendering
4. **Token Consumption** - Ensure all tokens within brackets/blocks are consumed
5. **Hex Detection** - Only 3 or 6 character hex strings, check each character

### Code Style
- No emojis unless requested
- Keep functions focused (<100 lines when possible)
- Use `RenderUtils` for shared escape/sanitize functions
- Comment complex parsing logic
- Preserve UTF-8 handling (lexer may tokenize multi-byte chars separately)

### Git Workflow
- Work on main branch
- Squash commits for releases
- Use descriptive commit messages with "Fix:", "Refactor:", "Add:" prefixes
- Force push allowed (user's personal project)

### Debugging Tips
- Use `--debug` flag for verbose output (limited help due to GUI nature)
- Create test files in `/tmp/` for quick validation
- Check generated DOT with `generate_xxx_dot()` methods
- Verify token consumption with lexer output
