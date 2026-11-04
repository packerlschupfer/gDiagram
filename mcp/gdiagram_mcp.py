#!/usr/bin/env python3
"""An MCP server exposing gDiagram's check and render to an AI agent.

Why this is thin on purpose: `gdiagram --check --json` already emits a stable,
machine-readable contract (diagnostic codes, detected type, rendered size), so this
server does not interpret diagrams at all. It shells out and passes the result through.
Everything it knows comes from the CLI, which means the two cannot drift.

Standard library only. gDiagram ships as a .deb; a server that needed `pip install`
would be one more thing to go wrong on a machine that already has the binary.

Transport is MCP stdio: newline-delimited JSON-RPC 2.0 on stdin/stdout. Nothing but
protocol may be written to stdout — diagnostics go to stderr.
"""

import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile

SERVER_NAME = "gdiagram"
SERVER_VERSION = "0.1.0"
DEFAULT_PROTOCOL = "2024-11-05"
SUPPORTED_PROTOCOLS = {"2024-11-05", "2025-03-26", "2025-06-18"}

# A render of a very large diagram is slow but finite; never hang the client.
TIMEOUT_S = 120


def binary() -> str:
    return os.environ.get("GDIAGRAM_BIN") or shutil.which("gdiagram") or "gdiagram"


def log(msg: str) -> None:
    print(f"[gdiagram-mcp] {msg}", file=sys.stderr, flush=True)


def run_cli(args: list[str]) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            [binary()] + args,
            capture_output=True, text=True, timeout=TIMEOUT_S,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except FileNotFoundError:
        return 127, "", (
            f"gdiagram not found (looked for {binary()!r}). Install it, or set "
            f"GDIAGRAM_BIN to the binary."
        )
    except subprocess.TimeoutExpired:
        return 124, "", f"gdiagram timed out after {TIMEOUT_S}s"


def source_to_file(source: str, suffix: str) -> str:
    fd, path = tempfile.mkstemp(prefix="gdiagram-mcp-", suffix=suffix)
    with os.fdopen(fd, "w") as fh:
        fh.write(source)
    return path


def resolve_input(args: dict) -> tuple[str | None, str | None, bool]:
    """Returns (path, error, is_temp). Exactly one of source/path must be given."""
    source = args.get("source")
    path = args.get("path")
    if source and path:
        return None, "Give either `source` or `path`, not both.", False
    if path:
        if not os.path.isfile(path):
            return None, f"No such file: {path}", False
        return path, None, False
    if not source:
        return None, "One of `source` or `path` is required.", False
    # The extension decides PlantUML vs Mermaid when the content is ambiguous.
    suffix = ".mmd" if args.get("format") == "mermaid" else ".puml"
    return source_to_file(source, suffix), None, True


def tool_check(args: dict) -> dict:
    path, err, is_temp = resolve_input(args)
    if err:
        return {"content": [{"type": "text", "text": err}], "isError": True}
    try:
        code, out, errout = run_cli(["--check", "--json", path])
        if code not in (0, 1):
            return {"content": [{"type": "text", "text": errout.strip() or out.strip()}],
                    "isError": True}
        try:
            parsed = json.loads(out)
        except json.JSONDecodeError:
            return {"content": [{"type": "text", "text": out.strip() or errout.strip()}],
                    "isError": True}
        # A temp path in the output would be noise to the model.
        if is_temp:
            parsed["file"] = "<inline source>"
        return {"content": [{"type": "text", "text": json.dumps(parsed, indent=2)}]}
    finally:
        if is_temp and path:
            os.unlink(path)


def tool_render(args: dict) -> dict:
    fmt = (args.get("output_format") or "png").lower()
    if fmt not in ("png", "svg", "pdf"):
        return {"content": [{"type": "text", "text": f"Unknown output_format {fmt!r} (png, svg, pdf)."}],
                "isError": True}

    path, err, is_temp = resolve_input(args)
    if err:
        return {"content": [{"type": "text", "text": err}], "isError": True}

    out_path = args.get("output_path")
    out_is_temp = not out_path
    if out_is_temp:
        fd, out_path = tempfile.mkstemp(prefix="gdiagram-mcp-", suffix="." + fmt)
        os.close(fd)

    try:
        # -f explicitly: without it the CLI takes the format from the OUTPUT EXTENSION,
        # so output_format="svg" with output_path="x.png" wrote a PNG - and worse,
        # output_format="png" with output_path="x.svg" read the SVG back and returned it
        # to the model as {"mimeType": "image/png"} with XML inside the base64.
        cli = ["-e", out_path, "-f", fmt]
        theme = args.get("theme")
        if theme:
            cli += ["--theme", theme]
        cli.append(path)
        code, out, errout = run_cli(cli)
        if code != 0:
            detail = (errout.strip() + "\n" + out.strip()).strip()
            return {"content": [{"type": "text", "text": detail or "export failed"}],
                    "isError": True}

        content: list[dict] = []
        # Hand a PNG back as an image so the model can actually look at the diagram
        # rather than take the renderer's word for it.
        if fmt == "png":
            with open(out_path, "rb") as fh:
                content.append({
                    "type": "image",
                    "data": base64.b64encode(fh.read()).decode("ascii"),
                    "mimeType": "image/png",
                })
        note = f"Rendered to {out_path}" if not out_is_temp else "Rendered (inline, not saved)"
        content.append({"type": "text", "text": note})
        return {"content": content}
    finally:
        if is_temp and path:
            os.unlink(path)
        if out_is_temp and os.path.exists(out_path):
            os.unlink(out_path)


SOURCE_PROPS = {
    "source": {"type": "string", "description": "Diagram source text (PlantUML or Mermaid)."},
    "path": {"type": "string", "description": "Path to a diagram file. Use instead of `source`."},
    "format": {"type": "string", "enum": ["plantuml", "mermaid"],
               "description": "Hint for inline `source` when the syntax is ambiguous."},
}

TOOLS = [
    {
        "name": "check_diagram",
        "description": (
            "Validate PlantUML or Mermaid source without rendering a file. Returns JSON: "
            "ok, detected format and type, rendered pixel size, and diagnostics with stable "
            "codes. Errors mean it will not render; warnings mean it renders in gDiagram but "
            "may not survive elsewhere (e.g. `exceeds-plantuml-crop`, `escaped-quote`). "
            "Use this before rendering, and after writing any diagram source."
        ),
        "inputSchema": {"type": "object", "properties": dict(SOURCE_PROPS), "required": []},
    },
    {
        "name": "render_diagram",
        "description": (
            "Render PlantUML or Mermaid source to PNG, SVG or PDF. A PNG is returned as an "
            "image so it can be inspected directly. Give `output_path` to keep the file."
        ),
        "inputSchema": {
            "type": "object",
            "properties": dict(SOURCE_PROPS, **{
                "output_format": {"type": "string", "enum": ["png", "svg", "pdf"],
                                  "description": "Default png."},
                "output_path": {"type": "string",
                                "description": "Where to write. Omitted: a temp file, not kept."},
                "theme": {"type": "string", "enum": ["auto", "light", "dark", "grayscale"],
                          "description": "Pins exported colours; `auto` is not reproducible."},
            }),
            "required": [],
        },
    },
]

HANDLERS = {"check_diagram": tool_check, "render_diagram": tool_render}


def error(msg_id, code: int, message: str) -> dict:
    return {"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": message}}


def handle(msg) -> dict | None:
    # A batch (a JSON array) is legal in the 2025-03-26 revision, and a client may send
    # anything at all. Neither may take the server down: it used to call .get() on
    # whatever arrived, and a string or list params raised straight out of main().
    if isinstance(msg, list):
        return error(None, -32600, "Batched requests are not supported; send one per line.")
    if not isinstance(msg, dict):
        return error(None, -32600, "A JSON-RPC message must be an object.")

    method = msg.get("method")
    msg_id = msg.get("id")

    # A notification has no id and must never be answered.
    if msg_id is None:
        return None
    if not isinstance(method, str):
        return error(msg_id, -32600, "Missing or non-string `method`.")

    params = msg.get("params")
    if params is not None and not isinstance(params, dict):
        return error(msg_id, -32602, "`params` must be an object.")
    params = params or {}

    # Required by every protocol revision this server advertises; a client that
    # health-checks with ping would otherwise read the server as broken.
    if method == "ping":
        return {"jsonrpc": "2.0", "id": msg_id, "result": {}}

    if method == "initialize":
        asked = params.get("protocolVersion")
        version = asked if asked in SUPPORTED_PROTOCOLS else DEFAULT_PROTOCOL
        return {
            "jsonrpc": "2.0", "id": msg_id,
            "result": {
                "protocolVersion": version,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            },
        }

    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": msg_id, "result": {"tools": TOOLS}}

    if method == "tools/call":
        name = params.get("name")
        handler = HANDLERS.get(name)
        if handler is None:
            return error(msg_id, -32602, f"Unknown tool: {name}")
        arguments = params.get("arguments")
        if not isinstance(arguments, dict):
            arguments = {}
        try:
            return {"jsonrpc": "2.0", "id": msg_id, "result": handler(arguments)}
        except Exception as exc:  # a tool must not take the server down
            log(f"{name} failed: {exc!r}")
            return {"jsonrpc": "2.0", "id": msg_id,
                    "result": {"content": [{"type": "text", "text": f"{name} failed: {exc}"}],
                               "isError": True}}

    return error(msg_id, -32601, f"Method not found: {method}")


def main() -> int:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as exc:
            log(f"ignoring unparseable line: {exc}")
            continue
        try:
            reply = handle(msg)
        except Exception as exc:  # last line of defence: never die on one bad message
            log(f"handler raised: {exc!r}")
            reply = error(msg.get("id") if isinstance(msg, dict) else None,
                          -32603, f"Internal error: {exc}")
        if reply is not None:
            print(json.dumps(reply), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
