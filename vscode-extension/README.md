# gDiagram - PlantUML & Mermaid for VS Code

Native PlantUML and Mermaid diagram editor with live preview, powered by the `gdiagram-lsp` language server.

## Features

- Live preview with zoom, pan, and click-to-source navigation
- Syntax highlighting for PlantUML and Mermaid
- 50 diagram type templates with snippets
- Export to PNG, SVG, and PDF
- Dark/light theme support following VS Code theme
- No Java or Node.js runtime required

## Requirements

- The `gdiagram-lsp` binary must be installed and available on PATH (or configure `gdiagram.lspPath`)

## Usage

1. Open a `.puml` or `.mmd` file
2. Press `Ctrl+Shift+V` to open the live preview
3. Edit the diagram source and see changes in real time

## Commands

| Command | Shortcut | Description |
|---------|----------|-------------|
| gDiagram: Show Preview | `Ctrl+Shift+V` | Open live preview panel |
| gDiagram: Export as PNG | | Export diagram to PNG |
| gDiagram: Export as SVG | | Export diagram to SVG |
| gDiagram: Export as PDF | | Export diagram to PDF |
| gDiagram: New Diagram from Template | | Create diagram from template gallery |

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `gdiagram.lspPath` | `gdiagram-lsp` | Path to the gdiagram-lsp binary |
| `gdiagram.theme` | `auto` | Diagram color theme |
| `gdiagram.autoPreview` | `true` | Auto-show preview on file open |
