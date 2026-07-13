# Multi-file C4 example — drill-down navigation

This directory demonstrates gDiagram's drill-down navigation. Each
file is a different level of the C4 model; double-clicking elements
in the preview pane navigates between them.

## Files

| File | C4 level | Reached by |
|------|----------|------------|
| [`context.puml`](context.puml) | System Context | Open this first |
| [`web.puml`](web.puml) | Container — Web App internals | Double-click `web` in `context.puml` |
| [`api.puml`](api.puml) | Container — API internals | Double-click `api` in `context.puml` |
| [`db.puml`](db.puml) | Container — Database schema | Double-click `db` in `context.puml` |
| [`orders.puml`](orders.puml) | Component — Order Service code view | Double-click `orders` in `api.puml` |

## How navigation works

1. Open `context.puml` in gDiagram
2. **Double-click** the `web` rectangle in the preview pane
3. `web.puml` opens in a new tab. The breadcrumb above the preview shows:
   `context › web`
4. Click `context` in the breadcrumb to jump back
5. From `context.puml`, double-click `api` instead
6. From `api.puml`, double-click `orders` to drill in another level
7. Breadcrumb now shows `context › api › orders`

## How gDiagram finds the related file

When you double-click an element with alias `foo`, gDiagram tries
these filenames in the same directory, in order:

1. `foo.puml`
2. `foo.mmd`
3. `<currentbase>-foo.puml` (e.g. `context-foo.puml`)
4. `<currentbase>-foo.mmd`
5. `foo-container.puml`
6. `foo-component.puml`
7. `foo_container.puml`
8. `foo_component.puml`

The first match wins. If nothing matches, the click is logged but
nothing else happens (no error dialog).
