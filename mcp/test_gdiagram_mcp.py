#!/usr/bin/env python3
"""Drives the MCP server over real stdio and checks the protocol it speaks.

Not a mock: the server is spawned, messages go over its stdin/stdout, and the gdiagram
binary underneath actually renders. A protocol server that is only unit-tested tends to
be one that no client can talk to.

Run: GDIAGRAM_BIN=build/src/gdiagram python3 mcp/test_gdiagram_mcp.py
"""
import base64
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "gdiagram_mcp.py")

GOOD = "@startuml\nAlice -> Bob : hi\n@enduml\n"
BAD = "@startuml\nAlice -> : hi\n@enduml\n"
UNPORTABLE = '@startuml\nparticipant "NVS \\"boot\\"" as P\nP -> P : x\n@enduml\n'

failures = []


def check(label, condition, detail=""):
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        failures.append(label)


class Server:
    def __init__(self):
        env = dict(os.environ)
        self.proc = subprocess.Popen(
            [sys.executable, "-I", SERVER],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, env=env, bufsize=1,
        )
        self.next_id = 0

    def send(self, method, params=None, notify=False):
        msg = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            msg["params"] = params
        if not notify:
            self.next_id += 1
            msg["id"] = self.next_id
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()
        if notify:
            return None
        line = self.proc.stdout.readline()
        return json.loads(line) if line else None

    def raw(self, line):
        """Send a literal line - for malformed input a well-formed client cannot produce."""
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()
        out = self.proc.stdout.readline()
        return json.loads(out) if out else None

    def close(self):
        self.proc.stdin.close()
        self.proc.wait(timeout=10)


def main():
    if not os.environ.get("GDIAGRAM_BIN"):
        print("GDIAGRAM_BIN is unset; the server would use whatever `gdiagram` is on PATH,")
        print("which may predate --check. Set it to the build you want tested.")
    s = Server()

    print("handshake")
    r = s.send("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                              "clientInfo": {"name": "test", "version": "0"}})
    check("initialize replies", r is not None and "result" in r, r)
    check("echoes a supported protocol version",
          r["result"]["protocolVersion"] == "2024-11-05", r["result"].get("protocolVersion"))
    check("declares the tools capability", "tools" in r["result"]["capabilities"])
    check("names itself", r["result"]["serverInfo"]["name"] == "gdiagram")

    # A notification must produce no reply at all; answering one corrupts the stream.
    s.send("notifications/initialized", notify=True)

    print("tools/list")
    r = s.send("tools/list")
    names = [t["name"] for t in r["result"]["tools"]]
    check("lists both tools", sorted(names) == ["check_diagram", "render_diagram"], names)
    for tool in r["result"]["tools"]:
        check(f"{tool['name']} has an object schema",
              tool["inputSchema"]["type"] == "object")

    print("check_diagram")
    r = s.send("tools/call", {"name": "check_diagram", "arguments": {"source": GOOD}})
    payload = json.loads(r["result"]["content"][0]["text"])
    check("valid source is ok", payload["ok"] is True, payload)
    check("reports the type", payload["type"] == "sequence", payload.get("type"))
    check("hides the temp path", payload["file"] == "<inline source>", payload.get("file"))
    check("no isError on a valid diagram", not r["result"].get("isError"))

    r = s.send("tools/call", {"name": "check_diagram", "arguments": {"source": BAD}})
    payload = json.loads(r["result"]["content"][0]["text"])
    check("broken source is not ok", payload["ok"] is False, payload)
    check("carries a parse diagnostic",
          any(d["code"] == "parse" for d in payload["diagnostics"]), payload["diagnostics"])

    r = s.send("tools/call", {"name": "check_diagram", "arguments": {"source": UNPORTABLE}})
    payload = json.loads(r["result"]["content"][0]["text"])
    check("unportable source still renders (ok)", payload["ok"] is True, payload)
    check("but warns about the escaped quote",
          any(d["code"] == "escaped-quote" for d in payload["diagnostics"]),
          payload["diagnostics"])

    print("render_diagram")
    r = s.send("tools/call", {"name": "render_diagram", "arguments": {"source": GOOD}})
    kinds = [c["type"] for c in r["result"]["content"]]
    check("returns an image for png", "image" in kinds, kinds)
    img = next(c for c in r["result"]["content"] if c["type"] == "image")
    raw = base64.b64decode(img["data"])
    check("the image really is a PNG", raw[:8] == b"\x89PNG\r\n\x1a\n", raw[:8])
    check("mime type is set", img["mimeType"] == "image/png")

    with tempfile.TemporaryDirectory() as td:
        out = os.path.join(td, "kept.svg")
        r = s.send("tools/call", {"name": "render_diagram",
                                  "arguments": {"source": GOOD, "output_format": "svg",
                                                "output_path": out}})
        check("writes the file it was given", os.path.exists(out))
        if os.path.exists(out):
            with open(out) as fh:
                check("and it is SVG", "<svg" in fh.read(400))

    r = s.send("tools/call", {"name": "render_diagram", "arguments": {"source": BAD}})
    check("a broken render is an isError", r["result"].get("isError") is True, r["result"])

    print("errors")
    r = s.send("tools/call", {"name": "no_such_tool", "arguments": {}})
    check("unknown tool is a JSON-RPC error", "error" in r, r)

    r = s.send("tools/call", {"name": "check_diagram",
                              "arguments": {"source": GOOD, "path": "/tmp/x"}})
    check("source+path is rejected", r["result"].get("isError") is True, r["result"])

    r = s.send("tools/call", {"name": "check_diagram", "arguments": {}})
    check("neither source nor path is rejected", r["result"].get("isError") is True, r["result"])

    r = s.send("tools/call", {"name": "check_diagram", "arguments": {"path": "/nonexistent.puml"}})
    check("missing file is rejected", r["result"].get("isError") is True, r["result"])

    r = s.send("unknown/method")
    check("unknown method is -32601", r.get("error", {}).get("code") == -32601, r)

    # The server used to call .get() on whatever arrived, so a batch or a string `params`
    # raised out of main() and killed it mid-session. Malformed input must be answered,
    # and the next request must still work.
    print("robustness")
    r = s.raw('[{"id":1,"method":"ping"}]')
    check("a batch is refused, not fatal", r.get("error", {}).get("code") == -32600, r)
    r = s.raw('{"id":99,"method":"tools/call","params":"not-an-object"}')
    check("non-object params is -32602", r.get("error", {}).get("code") == -32602, r)
    r = s.raw('{"id":98,"method":"ping"}')
    check("ping is answered with an empty result", r.get("result") == {}, r)
    r = s.send("tools/list")
    check("server survived all of that", "result" in r, r)

    # The CLI takes its format from the output EXTENSION unless -f is given, so this
    # combination used to write a PNG - and the png path would have handed the model an
    # SVG labelled image/png.
    with tempfile.TemporaryDirectory() as td:
        out = os.path.join(td, "misnamed.png")
        s.send("tools/call", {"name": "render_diagram",
                              "arguments": {"source": GOOD, "output_format": "svg",
                                            "output_path": out}})
        with open(out, "rb") as fh:
            head = fh.read(5)
        check("output_format wins over the extension", head == b"<?xml", head)

    s.close()
    print()
    if failures:
        print(f"{len(failures)} FAILED: {', '.join(failures)}")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
