# Code Refactoring Notes

This document tracks files that should be refactored/split in future versions.

## Files Needing Refactoring (v0.2.0+)

### 1. GraphvizRenderer.vala (4,128 lines) - HIGH PRIORITY
**Current:** Single monolithic file with all diagram rendering logic

**Proposed Split:**
```
src/core/renderer/
├── GraphvizRenderer.vala          # Base class, common utilities (500 lines)
├── SequenceDiagramRenderer.vala   # Sequence diagram rendering (~600 lines)
├── ClassDiagramRenderer.vala      # Class diagram rendering (~800 lines)
├── ActivityDiagramRenderer.vala   # Activity diagram rendering (~700 lines)
├── StateDiagramRenderer.vala      # State diagram rendering (~400 lines)
├── UseCaseDiagramRenderer.vala    # Use case rendering (~400 lines)
├── ComponentDiagramRenderer.vala  # Component rendering (~400 lines)
└── OtherDiagramRenderers.vala     # Object, Deployment, ER, MindMap (~400 lines)
```

**Benefits:**
- Easier to maintain and test individual diagram types
- Clearer separation of concerns
- Faster compilation (only changed renderers recompile)
- Easier for contributors to understand

---

### 2. ActivityDiagramParser.vala (2,455 lines) - MEDIUM PRIORITY
**Current:** All activity diagram parsing in one file

**Proposed Split:**
```
src/core/parser/activity/
├── ActivityDiagramParser.vala     # Main parser orchestration (~500 lines)
├── ActivityNodeParser.vala        # Node parsing logic (~800 lines)
├── ActivityEdgeParser.vala        # Edge/flow parsing (~600 lines)
├── ActivityPartitionParser.vala   # Partition handling (~400 lines)
└── ActivityStylingParser.vala     # Colors, styles, skinparam (~200 lines)
```

---

### 3. DocumentView.vala (2,257 lines) - MEDIUM PRIORITY
**Current:** Handles UI, rendering coordination, search, outline, etc.

**Proposed Split:**
```
src/ui/
├── DocumentView.vala              # Main view orchestration (~500 lines)
├── EditorPane.vala                # Source editor component (~400 lines)
├── OutlinePanel.vala              # Outline sidebar (~300 lines)
├── SearchBar.vala                 # Search/replace functionality (~300 lines)
├── DiagramRenderer.vala           # Rendering coordination (~400 lines)
└── KeyboardHandlers.vala          # Keyboard shortcuts (~200 lines)
```

---

## Files That Are Fine As-Is

- **MainWindow.vala** (862 lines) - Reasonable size
- **Lexer.vala** (741 lines) - Good size
- **Parser.vala** (641 lines) - Good size
- All other parsers (<1000 lines) - Acceptable

---

## Refactoring Guidelines

When splitting files:

1. **Create abstract base classes** for shared functionality
2. **Use composition** over deep inheritance
3. **Keep related code together** (don't over-split)
4. **Write tests first** before refactoring
5. **Split in small increments** with working code at each step
6. **Document interfaces** between split components

---

## Priority Order (for future releases)

**v0.2.0:**
1. Add --debug flag ✅ (Done in v0.1.1)
2. Enable test infrastructure
3. Split GraphvizRenderer.vala (highest impact)

**v0.3.0:**
1. Split ActivityDiagramParser.vala
2. Split DocumentView.vala

**v0.4.0+:**
1. Review and optimize other large parsers as needed

---

## Notes

- Keep one diagram type's renderer working before moving to next
- Maintain backward compatibility
- Use gradual refactoring (don't do all at once)
- Each refactoring should have tests to prevent regressions
