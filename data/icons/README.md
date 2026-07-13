# gDiagram Icons

## Icon Variations

The gDiagram icon comes in multiple variations to ensure perfect integration
with different desktop themes and contexts.

### Main Icon
- **org.gnome.gDiagram.svg** - Primary application icon
- Scalable SVG format
- Works with both light and dark themes
- Follows GNOME icon guidelines

### Symbolic Icons (Planned)
- **org.gnome.gDiagram-symbolic.svg** - Symbolic variant for panels
- Monochrome design
- Adapts to theme colors
- Used in:
  - System tray
  - GNOME Shell
  - Panel indicators
  - Notification areas

### Size Variants (Auto-generated)
The SVG icon is automatically rendered at multiple sizes:
- 16x16 - Small UI elements
- 24x24 - Toolbars
- 32x32 - Lists
- 48x48 - Medium icons
- 64x64 - Large icons
- 128x128 - High DPI displays
- 256x256 - Extra high DPI
- 512x512 - Maximum quality

### File Type Icons
- **text-x-plantuml.svg** - PlantUML file icon (.puml)
- **text-x-mermaid.svg** - Mermaid file icon (.mmd)
- Associated with gDiagram in file manager
- Shows diagram preview in tooltip (if supported)

### Theme Integration

#### Light Theme
- Full color icon
- Clear visibility on light backgrounds
- Subtle shadow for depth

#### Dark Theme
- Automatically adapts contrast
- Maintains brand colors
- Optimized for dark backgrounds

### MIME Type Icons
Registered MIME types:
- `text/x-plantuml` - .puml, .plantuml, .pu files
- `text/x-mermaid` - .mmd, .mermaid files

## Icon Design Guidelines

### Color Palette
- Primary: Blue (#4A90E2) - Represents diagrams/connections
- Secondary: Green (#27AE60) - Represents growth/visualization
- Accent: Orange (#E67E22) - Represents creativity

### Design Elements
- Geometric shapes (representing nodes)
- Connected paths (representing edges)
- Clean, modern aesthetic
- Scalable at all sizes
- Recognizable at small sizes

### Accessibility
- High contrast
- Color-blind friendly
- Clear at all sizes
- Meaningful even in grayscale

## Installation

Icons are automatically installed to:
```
/usr/share/icons/hicolor/scalable/apps/org.gnome.gDiagram.svg
```

After installation, update icon cache:
```bash
sudo gtk4-update-icon-cache -f /usr/share/icons/hicolor
```

## Future Enhancements

Planned icon additions:
- Symbolic variant for GNOME Shell
- Individual icons per diagram type
- Custom cursors for diagram editing
- Loading/progress icons
- Status indicators

---

*Icons follow GNOME Human Interface Guidelines and FreeDesktop.org Icon Theme Specification*
