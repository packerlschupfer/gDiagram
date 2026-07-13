# Drill-down workflow smoke test

This is the manual test plan for verifying the drill-down navigation
end-to-end. Run gDiagram on `context.puml` and walk through these
checkpoints.

## Setup

```bash
./build/src/gdiagram examples/plantuml/c4/multi-file/context.puml
```

## Headless verification (already automated)

Run from `/home/mrnice/Documents/Projects/gDiagram` after building:

```bash
# 1. context.puml renders cleanly with the right number of click regions
./build/src/gdiagram examples/plantuml/c4/multi-file/context.puml -e /tmp/c.svg -f svg
grep -oE '<title>[^<]+' /tmp/c.svg | sort -u
# Expected: customer, analyst, web, api, db, payments, email, ecommerce
```

```bash
# 2. Drill targets resolve correctly
ls examples/plantuml/c4/multi-file/{web,api,db}.puml
ls examples/plantuml/c4/multi-file/components/router.puml
```

```bash
# 3. Each drilled file also renders cleanly
for f in examples/plantuml/c4/multi-file/*.puml \
         examples/plantuml/c4/multi-file/*/*.puml; do
  ./build/src/gdiagram "$f" -e /tmp/_t.svg -f svg >/dev/null 2>&1 \
    && echo "OK   $f" || echo "FAIL $f"
done
# Expected: 6 OK lines (5 .puml files + components/router.puml)
```

## Visual checkpoints (manual)

These need a real session — gDiagram can't drive its own mouse.

### Canvas

- [ ] Background shows a subtle dotted grid (24px spacing)
- [ ] Dragging the diagram pans the dots WITH the diagram, not against it
- [ ] In dark mode, dots are white-ish on dark grey

### context.puml — top of the chain

- [ ] All 5 elements visible: customer (Person, dark blue), analyst (Person), 
      Online Store (boundary cluster), web/api/db (Containers, medium blue)
- [ ] External elements payments + email visible as grey rectangles
- [ ] No breadcrumb bar shown (this is a top-level document)
- [ ] Hover over `customer` → tooltip shows just "customer", no drill hint
      (no related file)
- [ ] Hover over `web` → tooltip shows "web\nDouble-click → web.puml"
- [ ] Hover over `web` → soft gold dashed border appears around it
- [ ] Hover off → gold border disappears

### Drill from context → web

- [ ] Double-click `web` → `web.puml` opens in a new tab
- [ ] New tab is auto-selected
- [ ] Breadcrumb bar appears: `← │ context › **web** │ Level 2`
- [ ] Back button (`←`) is enabled and circular

### Back navigation

- [ ] Click the `←` back button → tab switches to context.puml's tab
      (or opens it if closed)
- [ ] Press Alt+Left in `web.puml` → same as clicking back

### Deeper drill: api → router

- [ ] From context.puml, double-click `api` → api.puml opens
- [ ] Breadcrumb: `← │ context › **api** │ Level 2`
- [ ] In api.puml, hover `router` → tooltip shows "router\nDouble-click → components/router.puml"
- [ ] Double-click `router` → components/router.puml opens
- [ ] Breadcrumb: `← │ context › api › **router** │ Level 3`
- [ ] Click `context` in the breadcrumb → jumps to context.puml

### Right-click context menu

- [ ] Right-click `web` in context.puml → popover appears at click point
- [ ] Menu items: "Drill into web.puml", "Go to source line N", "Copy element name"
- [ ] Click "Copy element name" → clipboard contains "web"
- [ ] Right-click `customer` (no related file) → menu shows only
      "Go to source line N" + "Copy element name" (no "Drill into")

### Settings

- [ ] Open Preferences (Ctrl+,)
- [ ] Navigation page exists with view-list-symbolic icon
- [ ] Patterns row shows the comma-separated list
- [ ] Edit and apply: navigation should use the new patterns
- [ ] Reset button restores defaults
