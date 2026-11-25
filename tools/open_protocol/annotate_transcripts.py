#!/usr/bin/env python3
"""Build docs/open-protocol/transcripts/ from raw capture logs.

  python tools/open_protocol/annotate_transcripts.py --raw-dir <capture dir>

Inputs are the complete logs written by capture_transcripts.py
({thin,full}-{json,bin}.jsonl). Outputs per log:
  <name>.md     annotated session; sections follow the session lifecycle, the
                first frame of each kind is shown (hex for binary),
                repeats are counted per section.
  <name>.jsonl  every low-rate frame plus every 20th high-rate frame, in order
                (a sampled but order-preserving copy of the complete log).
"""

from __future__ import annotations

import argparse
import collections
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "docs/open-protocol/transcripts"

THIN_HIGH = {"in", "snap"}
FULL_HIGH = {"_push_transform", "_relay_transform", "_sync_enemies", "_apply_vitals", "_sync_progress",
             "_rtt_ping", "_rtt_pong", "_flight", "_ready_changed", "_private_state", "_request_shot",
             "_shot_fx", "_spawn", "_remove", "_spawn_enemy", "_despawn_enemy", "_enemy_impacts",
             "_receive_hits", "_receive_group_warning", "_equip_state", "_stock", "_votes_rpc"}
SHOW = {"in": 2, "snap": 1, "ev": 6}
SAMPLE_EVERY = 20

THIN_NOTES = {
    "hello": "First frame on the socket, always JSON text even for `enc:\"bin\"` (spec-common §4, spec-thin §2).",
    "welcome": "Server accepted the hello: `you` is the roster id, `rate/radius/max_enemies` echo the negotiated values (spec-thin §2).",
    "status": "Connection state machine update (spec-thin §3). `run` is the only state where `in`/`choice` are applied.",
    "lobby": "Full lobby state; sent on every change, never as a delta (spec-thin §4).",
    "pong": "Echo of the client's `ping.ms` (spec-common §6).",
    "load": "Load this level now; snapshots start after the following `status run` (spec-thin §3).",
    "map": "Coarse collision outline for renderers without assets (spec-thin §8).",
    "in": "Control frame at 30 Hz; `seq` strictly increases, `b` is the button bitmask (spec-thin §5).",
    "snap": "Complete authoritative state; `ack` = last applied input seq (spec-thin §6/§7).",
    "ev": "One-shot events batched after a snapshot (spec-thin §9).",
    "draft": "Mutation draft opened (wave 2+ Calm); answer with `choice` (spec-thin §10).",
    "choice": "Vote for card index `i` (zero-based).",
    "draft_done": "Draft resolved; close the card UI.",
    "results": "End-of-run summary, after `status results`; the lobby follows ~5 s later (spec-thin §11).",
    "leave": "Clean exit: server answers `status disconnected` and closes (spec-common §7).",
    "map_req": "Ask for the current level outline.",
}
FULL_NOTES = {
    "hello": "Open Protocol hello selecting the Full tier; JSON text even for `enc:\"bin\"` (spec-common §4).",
    "welcome": "Transport-level acceptance. `you` is the real Godot peer id; `game_protocol` must equal the client's (spec-full §2).",
    "Net._hello": "Game-level handshake RPC: arg0 is a JSON *string*, arg1 the game protocol (spec-full §3).",
    "Net._push_roster": "Roster broadcast: `Dictionary[int peer_id -> {name,ready,color,skin}]` + lobby voting state (spec-full §4).",
    "Net._rtt_ping": "1 Hz latency probe; answer `Net._rtt_pong(seq)` unreliably (client-responsibilities §RTT).",
    "Net._rtt_pong": "Echo of `_rtt_ping.seq`.",
    "Net._chat_rpc": "Chat relay; sent to every peer, including the sender.",
    "Net._start_run": "Run starts on this concrete map id: load the level, build `Main/Players/P_<id>` for every roster peer, then `_report_in_run(true)` (spec-full §5).",
    "Net._report_in_run": "Client finished loading (`true`) or unloaded the run scene (`false`).",
    "Net._confirm_run_ready": "Last frame of the catch-up burst. Only now may run-scoped RPCs be sent (spec-full §5).",
    "GameManager._sync_tape_state": "Catch-up #1: endless-tape state (choice pending, endless, victory locked).",
    "WeatherManager._receive_phase": "Phase change: `[phase enum, wave, seconds_left]`. Count down locally (client-responsibilities §Weather).",
    "WeatherManager._receive_intensity": "Catch-up only: current smoothed storm intensity.",
    "WeatherManager._override": "Storm intensity override (-1 = none).",
    "GameManager._sync_decon": "Shared decon charge pool.",
    "GameManager/MutationRoll._sync_active": "Active enemy/player mutation id lists (typed `Array[String]` in binary!).",
    "GameManager/CrateManager._snapshot": "Vending cabinets `{key: [[item,tier,price,offer_serial],...]}` and airdrop.",
    "Main/Enemies._sync_progress": "Wave progress for the HUD at ~3.6 Hz: wave, remaining, total, recovery, endless score.",
    "WeatherManager._sync_puddles": "Puddle growth keyed by *absolute* NodePath (`{\"_t\":\"dict\"}` form).",
    "Main/RunLoot._snapshot": "World pickups/effects snapshot; arg0 is the `run_id` for RPCs with a `run` argument.",
    "_equip_state": "Public held item per player (relayed to everyone including the owner).",
    "_private_state": "Owner-only authoritative inventory; drop updates with `rev <= last` (client-responsibilities §Inventory).",
    "Main/RunLoot._request_starter": "Pick a starter kit (0 pump_shotgun, 1 nail_driver, 2 service_revolver).",
    "Main/RunLoot._starter_accepted": "Starter kit granted.",
    "_report_exposure": "Owner-reported shelter/puddle state; the host trusts it for acid drain (client-responsibilities §Exposure).",
    "_push_transform": "Owner transform at 20 Hz, unreliable-ordered (client-responsibilities §Movement).",
    "_relay_transform": "Host relay of a player's transform to every run peer, *including the owner* (ignore your own).",
    "_apply_vitals": "Host-owned vitals at 5 Hz: hp, suit, state, bleed, tarp, max_hp, static charge, invulnerable.",
    "GameManager._request_ready": "Skip the rest of Calm/Clearing (counts toward the all-ready threshold).",
    "GameManager._ready_changed": "Ready-up tally `[count, needed]` (broadcast).",
    "Main/Enemies._spawn_enemy": "Spawn `[net_id, kind enum, pos, small, elite, miniboss_wave]`.",
    "Main/Enemies._sync_enemies": "20 Hz batch: PackedInt32Array ids, PackedVector3Array positions, PackedFloat32Array yaws.",
    "Main/Enemies._despawn_enemy": "Enemy died: `[net_id, drops, at, throw_vec, critical]`.",
    "_request_shot": "Hitscan request: `[run_id, serial, origin(eye), dir, aiming, predicted]`; host resolves hits (client-responsibilities §Weapons).",
    "_shot_fx": "Authoritative shot effect with `traces[[end, impact]]`, relayed to everyone; skip local re-play when `predicted` and it is yours.",
    "_receive_hits": "Hit markers for your shots: `[[killed, critical, pos, damage, enemy_id], ...]`.",
    "GameManager/MutationRoll._deal_rpc": "Mutation draft: enemy mutation id + 3 player mutation card ids. Vote with `_request_vote(i)`.",
    "GameManager/MutationRoll._request_vote": "Vote for card index.",
    "GameManager/MutationRoll._votes_rpc": "Vote tally `[n0, n1, n2]`.",
    "GameManager/MutationRoll._result_rpc": "Draft result: `[pick, enemy_list, player_list, granted]`; resume the Calm countdown after 2.2 s.",
    "GameManager._finish": "Run over: `[won, results]`. Show results, unload, send `_report_in_run(false)`; next `_push_roster` is the lobby.",
    "Main/RunLoot._spawn": "World pickup appeared: `[run_id, pickup_id, [pos, item[], flavor, claim_peer]]`.",
    "Main/RunLoot._remove": "World pickup collected/expired: `[run_id, pickup_id, collector]`.",
    "GameManager._banner": "Centre-screen banner text, colour, seconds.",
    "WeatherManager._strike": "Lightning: negative seed = ambient, positive = tactical (item) strike.",
    "leave": "Clean exit. The server removes the peer and closes the socket.",
}


def key_of(tier: str, msg: dict) -> str:
    if tier == "thin" or msg.get("t") != "rpc":
        return str(msg.get("t"))
    return msg["method"]


def note_key(tier: str, msg: dict) -> str | None:
    if tier == "thin" or msg.get("t") != "rpc":
        return str(msg.get("t"))
    full = f"{msg['node']}.{msg['method']}"
    if full in FULL_NOTES:
        return full
    return msg["method"] if msg["method"] in FULL_NOTES else None


def hex_block(hx: str, tcp: bool, payload_size: int) -> str:
    data = bytes.fromhex(hx)
    lines = []
    if tcp:
        lines.append("len " + payload_size.to_bytes(4, "little").hex(" ") + f"   (raw TCP prefix: {payload_size} bytes)")
    for i in range(0, len(data), 16):
        lines.append(f"{i:04x} " + data[i:i + 16].hex(" "))
    return "\n".join(lines)


def compact(value, limit: int) -> str:
    text = json.dumps(value, separators=(",", ":"), ensure_ascii=False)
    return text if len(text) <= limit else text[: limit - 1] + "…"


def section_of(tier: str, row: dict, state: dict) -> str | None:
    msg = row.get("msg") or {}
    t = msg.get("t")
    if tier == "thin":
        if t == "welcome":
            return "Handshake and lobby"
        if t == "status":
            s = msg["state"]
            if s == "lobby" and state.get("ran"):
                return "Back in the lobby"
            if s == "loading":
                state["ran"] = True
                return "Loading"
            if s == "results":
                return "Results"
            if s == "disconnected":
                return "Leave"
        if t == "draft":
            return "Mutation draft"
        if t == "snap":
            w = msg["weather"]
            key = (w["phase"], w["wave"])
            if state.get("phase") != key:
                state["phase"] = key
                return f"Run: wave {w['wave']} {w['phase']}"
        if t == "leave":
            return "Leave"
        return None
    if t == "welcome":
        return "Handshake"
    if t == "leave":
        return "Leave"
    if t != "rpc":
        return None
    m = f"{msg['node']}.{msg['method']}"
    if m == "Net._push_roster" and not state.get("lobby"):
        state["lobby"] = True
        return "Lobby"
    if m == "Net._start_run":
        return "Run start and catch-up burst"
    if m == "WeatherManager._receive_phase" and row["dir"] == "s2c" and state.get("confirmed")             and not state.get("finished"):
        names = ["calm", "mutation_roll", "drizzle", "downpour", "clearing"]
        phase, wave = int(msg["args"][0]), int(msg["args"][1])
        return f"Run: wave {wave} {names[phase] if phase < 5 else phase}"
    if m == "Net._confirm_run_ready":
        state["confirmed"] = True
    if m == "GameManager/MutationRoll._deal_rpc":
        return "Mutation draft"
    if m == "GameManager._finish":
        state["finished"] = True
        return "Results and return to the lobby"
    return None


def build(raw: Path, name: str) -> None:
    rows = [json.loads(line) for line in raw.read_text(encoding="utf-8").splitlines() if line.strip()]
    meta = rows[0]["meta"]
    tier = name.split("-")[0]
    tcp = meta["transport"] == "tcp"
    high = THIN_HIGH if tier == "thin" else FULL_HIGH
    md = [f"# {tier.title()} tier session — {meta['transport']}/{meta['enc']}", ""]
    md += [
        f"Captured from a local dedicated server (Godot 4.7.2, game protocol from `welcome`), transport "
        f"**{meta['transport']}**, encoding **{meta['enc']}**, by `tools/open_protocol/capture_transcripts.py` "
        f"under `tools/open_protocol/capture_harness.gd` (real server code; only the storm timers were shortened, "
        f"wave-1 stragglers were finished off after 9 s and the run was ended through `GameManager.finish(false)` "
        f"6 s into wave 2 so the session fits in about two minutes). A second bot of the other tier played in the "
        f"same lobby, so its traffic appears too.",
        "",
        "`C→S` is client to server, `S→C` server to client, `+t` is seconds since capture start. "
        + ("Binary frames are shown as hex (the raw TCP length prefix is shown on its own line) with the decoded "
           "value underneath. " if meta["enc"] == "bin" else "")
        + "Long previews can be truncated; TCP prefixes always describe the full payload. Repeats are counted at the end of the section. "
        f"The order-preserving sampled log is [`{name}.jsonl`]({name}.jsonl).",
        "",
    ]
    sampled = [rows[0]]
    seen_notes: set[str] = set()
    state: dict = {}
    shown: collections.Counter = collections.Counter()
    elided: collections.Counter = collections.Counter()
    counts: collections.Counter = collections.Counter()
    open_block = False

    def close_section():
        nonlocal open_block
        if open_block:
            md.append("```")
            open_block = False
        if elided:
            md.append("")
            md.append("Repeats not shown in this section: " + ", ".join(
                f"{n}× `{k}`" for k, n in sorted(elided.items(), key=lambda kv: -kv[1])) + ".")
        md.append("")
        elided.clear()
        shown.clear()

    def ensure_block():
        nonlocal open_block
        if not open_block:
            md.append("```text")
            open_block = True

    for row in rows[1:]:
        if "note" in row:
            ensure_block()
            md.append(f"# {row['note']}")
            sampled.append(row)
            continue
        msg = row.get("msg") or {}
        k = key_of(tier, msg)
        counts[k] += 1
        if k not in high or counts[k] % SAMPLE_EVERY == 1:
            sampled.append(row)
        title = section_of(tier, row, state)
        if title and title == state.get("title"):
            title = None
        if title:
            state["title"] = title
            close_section()
            md.append(f"## {title}")
            md.append("")
        ev_key = k
        if tier == "thin" and k == "ev":
            ev_key = "ev:" + ",".join(sorted({e["e"] for e in msg["list"]}))
        limit = SHOW.get(k, 2 if k in high else 99)
        if tier == "thin" and k == "ev":
            limit = 1
        if shown[(row["dir"], ev_key)] >= limit:
            elided[f"{'C→S' if row['dir'] == 'c2s' else 'S→C'} {k}"] += 1
            continue
        shown[(row["dir"], ev_key)] += 1
        nk = note_key(tier, msg)
        notes = THIN_NOTES if tier == "thin" else FULL_NOTES
        if nk and nk in notes and nk not in seen_notes:
            seen_notes.add(nk)
            close_block = open_block
            if close_block:
                md.append("```")
                open_block = False
            md.append(f"> {notes[nk]}")
            md.append("")
        ensure_block()
        arrow = "C→S" if row["dir"] == "c2s" else "S→C"
        stamp = f"+{row['t'] / 1000:7.3f}s {arrow}"
        if "hex" in row:
            payload_size = len(row["hex"]) // 2
            md.append(f"{stamp} binary {payload_size} bytes")
            first = shown[(row["dir"], ev_key)] == 1
            hx = row["hex"] if first or len(row["hex"]) <= 256 else row["hex"][:256]
            md.append(hex_block(hx, tcp, payload_size) + ("" if hx == row["hex"] else "\n     … (hex truncated)"))
            md.append("     = " + compact(msg, 4000 if first else 600))
        else:
            first = shown[(row["dir"], ev_key)] == 1
            if tcp:
                md.append(f"{stamp} text (raw TCP prefix {len(row['text'].encode()).to_bytes(4, 'little').hex(' ')})")
                md.append("     " + (row["text"] if first and len(row["text"]) < 6000 else compact(msg, 600)))
            else:
                md.append(f"{stamp} " + (row["text"] if first and len(row["text"]) < 6000 else compact(msg, 600)))
    close_section()
    md.append("## Frame totals")
    md.append("")
    md.append("| Kind | Frames |")
    md.append("| --- | ---: |")
    for k, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        md.append(f"| `{k}` | {n} |")
    md.append("")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{name}.md").write_text("\n".join(md), encoding="utf-8")
    with open(OUT / f"{name}.jsonl", "w", encoding="utf-8") as fh:
        fh.write(json.dumps({"meta": dict(meta, sampled=f"every low-rate frame; every {SAMPLE_EVERY}th of {sorted(high)}")}) + "\n")
        for row in sampled[1:]:
            fh.write(json.dumps(row, separators=(",", ":")) + "\n")
    print(f"wrote {name}.md ({sum(counts.values())} frames) and {name}.jsonl ({len(sampled) - 1} frames)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--raw-dir", required=True)
    args = parser.parse_args()
    for name in ("thin-json", "thin-bin", "full-json", "full-bin"):
        path = Path(args.raw_dir) / f"{name}.jsonl"
        if path.exists():
            build(path, name)


if __name__ == "__main__":
    main()
