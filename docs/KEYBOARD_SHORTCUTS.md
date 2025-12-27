# gDiagram Keyboard Shortcuts

## Quick Reference

### File Operations
| Shortcut | Action |
|----------|--------|
| `Ctrl+N` | New tab |
| `Ctrl+O` | Open file |
| `Ctrl+S` | Save file |
| `Ctrl+Shift+S` | Save as |
| `Ctrl+W` | Close tab |
| `Ctrl+Q` | Quit application |

### Editing
| Shortcut | Action |
|----------|--------|
| `Ctrl+Z` | Undo |
| `Ctrl+Shift+Z` | Redo |
| `Ctrl+X` | Cut |
| `Ctrl+C` | Copy |
| `Ctrl+V` | Paste |
| `Ctrl+A` | Select all |
| `Ctrl+F` | Find |
| `Ctrl+H` | Find and replace |
| `Ctrl+G` | Go to line |

### View
| Shortcut | Action |
|----------|--------|
| `Ctrl+Plus` | Zoom in preview |
| `Ctrl+Minus` | Zoom out preview |
| `Ctrl+0` | Reset zoom to 100% |
| `Ctrl+\\` | Toggle outline sidebar |
| `F11` | Toggle fullscreen |

### Export
| Shortcut | Action |
|----------|--------|
| `Ctrl+E` | Export dialog |
| `Ctrl+Shift+P` | Export to PNG |
| `Ctrl+Shift+S` | Export to SVG |
| `Ctrl+Shift+D` | Export to PDF |

### Navigation
| Shortcut | Action |
|----------|--------|
| `Ctrl+Tab` | Next tab |
| `Ctrl+Shift+Tab` | Previous tab |
| `Ctrl+1-9` | Jump to tab 1-9 |
| `Alt+Left` | Back in navigation |
| `Alt+Right` | Forward in navigation |

### Diagram Specific
| Shortcut | Action |
|----------|--------|
| `Ctrl+R` | Force re-render |
| `Ctrl+M` | Minimap toggle |
| `Ctrl+L` | Layout engine selector |
| `Ctrl+,` | Preferences |

### Search
| Shortcut | Action |
|----------|--------|
| `Ctrl+F` | Open search |
| `Enter` | Find next |
| `Shift+Enter` | Find previous |
| `Escape` | Close search |

## Tips & Tricks

### Efficient Workflow

**Split View**
- Use the split pane to see code and preview side-by-side
- Adjust split orientation in preferences (horizontal/vertical)

**Real-Time Preview**
- Preview updates automatically as you type (debounced)
- Adjust debounce delay in preferences (default: 300ms)

**Multi-Tab Editing**
- Work on multiple diagrams simultaneously
- Each tab maintains independent state
- Quick switching with `Ctrl+Tab`

### Editor Features

**Syntax Highlighting**
- Automatic based on file extension (.mmd, .puml)
- Keywords, arrows, strings, and comments all highlighted
- Works for both PlantUML and Mermaid

**Error Highlighting**
- Parse errors highlighted in red
- Shows line and column numbers
- Helpful error messages with context

**Line Numbers**
- Toggle in preferences
- Click to jump to line
- Helpful for error navigation

### Preview Features

**Zoom & Pan**
- Scroll wheel to zoom
- Click and drag to pan
- Minimap for navigation (Ctrl+M)
- Reset zoom with Ctrl+0

**Click to Source**
- Click diagram elements to jump to source line
- Works for most diagram types
- Helpful for large diagrams

### Export Options

**Quick Export**
- `Ctrl+Shift+P` for PNG
- `Ctrl+Shift+S` for SVG (vector)
- `Ctrl+Shift+D` for PDF

**Export Dialog**
- `Ctrl+E` for full dialog
- Choose format
- Select export location
- Preview before export

### Mermaid-Specific Tips

**Flowchart Styling**
```mermaid
classDef myStyle fill:#90EE90,stroke:#228B22,stroke-width:2
class MyNode myStyle
style AnotherNode fill:#FFB6C1
```

**Interactive Elements**
```mermaid
click NodeId "https://example.com" "Click to visit"
```

**Best Practices**
- Use meaningful node IDs
- Add labels for clarity
- Group related nodes in subgraphs
- Color-code by function (success=green, error=red)
- Keep flowcharts under 30 nodes for readability

### Performance Tips

**Fast Editing**
- Diagram caching keeps things instant
- <3ms rendering for typical diagrams
- No lag even for complex diagrams

**Large Diagrams**
- Use subgraphs to organize
- Consider splitting very large diagrams
- Use different layout engines (dot, neato, fdp)

## Advanced Features

### Layout Engines
Try different engines for different diagram types:
- **dot** - Hierarchical (default, best for flowcharts)
- **neato** - Spring model (good for networks)
- **fdp** - Force-directed (organic layouts)
- **sfdp** - Scalable force-directed (large graphs)
- **circo** - Circular layout
- **twopi** - Radial layout

Change in: Preferences → Layout Engine

### File Monitoring
- gDiagram auto-reloads when files change externally
- Great for watching generated diagrams
- Notification banner shows when reloading

### Recent Files
- Access recently opened files quickly
- Configurable maximum (default: 10)
- Persists between sessions

## Customization

### Editor Preferences
- Font family and size
- Line numbers
- Current line highlighting
- Render delay (debounce)

### Theme
- Follows system theme automatically
- Dark mode fully supported
- High contrast themes work great

### Split Orientation
- Horizontal (default) - Editor on left
- Vertical - Editor on top
- Change in preferences

## Getting Help

### Documentation
- Press `F1` for help (if implemented)
- Check `docs/` directory
- See `examples/` for samples

### Troubleshooting
- Check error messages carefully
- Verify syntax against examples
- Try simpler diagram first
- Check GitHub issues for known problems

---

**Master these shortcuts and become a gDiagram power user!** ⚡
