# gDiagram MCP server

Exposes gDiagram to an MCP client (Claude Code, Claude Desktop) as two tools:

| tool | what it does |
|---|---|
| `check_diagram` | Validates PlantUML/Mermaid source without writing a file. Returns the JSON from `gdiagram --check --json`: `ok`, detected format and type, rendered pixel size, and diagnostics with stable codes. |
| `render_diagram` | Renders to PNG, SVG or PDF. A PNG comes back **as an image**, so the model can look at the diagram instead of trusting the renderer. |

Both accept either inline `source` or a `path`.

## Why it is this thin

`gdiagram --check --json` is already the machine-readable contract. This server shells out
and passes the result through — it does not parse diagrams, and it has no model of what a
diagram is. The CLI and the MCP server therefore cannot drift apart.

It uses the Python **standard library only**. gDiagram ships as a .deb; a server that
needed `pip install` would be one more thing to go wrong on a machine that already has the
binary.

## Requirements

`gdiagram` 0.1.8 or newer on `PATH` (or point `GDIAGRAM_BIN` at it) and Python 3.10+.
Older gdiagram builds have no `--check` and `check_diagram` will fail against them.

## Setup

Claude Code:

```bash
claude mcp add gdiagram -- python3 /path/to/gDiagram/mcp/gdiagram_mcp.py
```

Or in a project's `.mcp.json`:

```json
{
  "mcpServers": {
    "gdiagram": {
      "command": "python3",
      "args": ["/path/to/gDiagram/mcp/gdiagram_mcp.py"],
      "env": { "GDIAGRAM_BIN": "/usr/bin/gdiagram" }
    }
  }
}
```

## The warnings are the point

`check_diagram` reports two things an author cannot see from a successful render here,
because gDiagram is more permissive than PlantUML:

- **`exceeds-plantuml-crop`** — the drawing is over 4096 px, where PlantUML silently
  truncates it (it exits 0 and writes a cropped image). Fix: `scale max 4000 width`.
- **`escaped-quote`** — a `\"` inside a quoted name. PlantUML rejects the *whole file*.
  Fix: `<U+0022>`.

Warnings do not make `ok` false: the file renders here, it just may not travel.

## Testing

```bash
GDIAGRAM_BIN=build/src/gdiagram python3 mcp/test_gdiagram_mcp.py
```

Spawns the server and talks real JSON-RPC to it over stdio — handshake, `tools/list`,
both tools, and the error paths. It is wired into `meson test` as "MCP server tests".
