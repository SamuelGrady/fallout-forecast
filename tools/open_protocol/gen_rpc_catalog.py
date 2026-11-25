#!/usr/bin/env python3
"""Render docs/open-protocol/rpc-catalog.md from docs/open-protocol/open-protocol-schema.json.

  python tools/open_protocol/gen_rpc_catalog.py

Run after tools/open_protocol/gen_schema.gd whenever Net.PROTOCOL changes.
"""

import json
from pathlib import Path

DOCS = Path(__file__).resolve().parents[2] / "docs/open-protocol"
SCOPES = {
    "host": "client → server",
    "single_peer": "server → one peer",
    "run_peers": "server → peers in the run",
    "all_peers": "server → every connected peer",
}


def signature(rpc: dict) -> str:
    parts = []
    for arg in rpc["args"]:
        text = f"{arg['name']}: {arg['type']}"
        if arg.get("optional"):
            text += f" = {json.dumps(arg.get('default'))}"
        parts.append(text)
    return f"{rpc['method']}({', '.join(parts)})"


def main() -> None:
    schema = json.loads((DOCS / "open-protocol-schema.json").read_text(encoding="utf-8"))
    out = [
        "# RPC catalog (generated)",
        "",
        f"Generated from [open-protocol-schema.json](open-protocol-schema.json) by "
        f"`tools/open_protocol/gen_rpc_catalog.py`. Game protocol **{schema['game_protocol']}**, "
        f"{schema['rpc_count']} RPCs on {schema['node_count']} node scripts. Every RPC is `call_remote` "
        "(never delivered back to the caller by Godot itself); *relayed* RPCs are re-sent by the server to "
        "every relevant peer **including the originator**. Mode `authority` means only the server may send it; "
        "`any_peer` RPCs on player nodes are validated by the server against the sender.",
        "",
        "Semantics and when to send each client → server RPC are in "
        "[client-responsibilities.md](client-responsibilities.md); wire encoding is in "
        "[spec-full.md](spec-full.md).",
        "",
    ]
    by_node: dict[str, list] = {}
    for rpc in schema["rpcs"]:
        by_node.setdefault(rpc["node"], []).append(rpc)
    for node in schema["nodes"]:
        path = node["node"]
        out += [f"## `{path}`", "", f"{node['notes']} Script `{node['script']}`, available: {node['phase']}.", ""]
        out += ["| Direction | Delivery | Signature |", "| --- | --- | --- |"]
        for rpc in sorted(by_node.get(path, []), key=lambda r: (r["direction"], r["method"])):
            direction = "relayed (server → all incl. sender)" if rpc["direction"] == "relayed" else SCOPES.get(rpc["scope"], rpc["scope"])
            mode = rpc["transfer_mode"].replace("_", " ")
            out.append(f"| {direction} | {mode}, ch {rpc['channel']}, `{rpc['rpc_mode']}` | `{signature(rpc)}` |")
        out.append("")
    (DOCS / "rpc-catalog.md").write_text("\n".join(out), encoding="utf-8", newline="\n")
    print(f"wrote {DOCS / 'rpc-catalog.md'}")


if __name__ == "__main__":
    main()
