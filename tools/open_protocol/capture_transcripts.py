#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["websockets==15.0.1"]
# ///
"""Capture real Open Protocol sessions for docs/open-protocol/transcripts/.

Starts a local dedicated server under tools/open_protocol/capture_harness.gd
(real server code, storm timers shortened), then drives one Thin client and one
Full client through connect -> lobby -> run -> combat -> mutation draft ->
results -> lobby -> leave, recording every frame both ways.

  uv run tools/open_protocol/capture_transcripts.py --godot <path-to-godot-console> \
      --session json   # thin ws/json + full ws/json
  uv run tools/open_protocol/capture_transcripts.py --godot <...> --session bin
      # thin tcp/bin + full tcp/bin

Raw logs go to --raw-dir (complete, every frame). Then run
tools/open_protocol/annotate_transcripts.py to build the Markdown transcripts.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "thin_client"))

import full_client as fc  # noqa: E402
from fake_client import binary_snapshot  # noqa: E402

REPO = HERE.parent.parent
T0 = time.monotonic()


def now_ms() -> int:
    return int((time.monotonic() - T0) * 1000)


class Recorder:
    def __init__(self, path: Path, label: str, transport: str, enc: str) -> None:
        self.fh = open(path, "w", encoding="utf-8")
        self.lock = threading.Lock()
        self.write({"meta": {"label": label, "transport": transport, "enc": enc}})

    def write(self, row: dict) -> None:
        with self.lock:
            self.fh.write(json.dumps(row, separators=(",", ":")) + "\n")
            self.fh.flush()

    def frame(self, direction: str, text: str | None = None, data: bytes | None = None, decoded=None) -> None:
        row = {"t": now_ms(), "dir": direction}
        if text is not None:
            row["text"] = text
        if data is not None:
            row["hex"] = data.hex()
        if decoded is not None:
            row["msg"] = decoded
        self.write(row)

    def note(self, text: str) -> None:
        self.write({"t": now_ms(), "note": text})


def open_transport(kind: str, host: str, port: int):
    if kind == "ws":
        return fc.WebSocketTransport(host, port)
    return fc.TcpLengthTransport(host, port)


def yaw_pitch_to(src, dst):
    dx, dy, dz = (dst[i] - src[i] for i in range(3))
    yaw = math.atan2(-dx, -dz)
    pitch = math.atan2(dy, math.hypot(dx, dz))
    return yaw, pitch


class ThinBot(threading.Thread):
    def __init__(self, args, rec: Recorder, transport: str, enc: str, stop: threading.Event) -> None:
        super().__init__(daemon=True)
        self.args, self.rec, self.enc, self.stop = args, rec, enc, stop
        port = args.thin_port if transport == "ws" else args.thin_tcp_port
        self.tr = open_transport(transport, args.host, port)
        self.state = ""
        self.snap = None
        self.seq = 0
        self.you = 0
        self.done = False
        self.error = None
        self.saw = set()
        self.ready_for = None

    def send(self, msg: dict) -> None:
        text = json.dumps(msg, separators=(",", ":"))
        self.tr.send_text(text)
        self.rec.frame("c2s", text=text, decoded=msg)

    def send_input(self, mv, yaw, pitch, buttons) -> None:
        self.seq += 1
        if self.enc == "bin":
            raw = struct.pack("<BIhhhhHBb", 1, self.seq, round(mv[0] * 32767), round(mv[1] * 32767),
                              round(yaw * 1000), round(pitch * 1000), buttons, 0, 0)
            self.tr.send_binary(raw)
            self.rec.frame("c2s", data=raw, decoded={"t": "in", "seq": self.seq, "mv": mv, "yaw": round(yaw, 3),
                                                     "pitch": round(pitch, 3), "b": buttons, "slot": 0, "wheel": 0})
        else:
            self.send({"t": "in", "seq": self.seq, "mv": mv, "yaw": round(yaw, 3), "pitch": round(pitch, 3),
                       "b": buttons, "slot": 0, "wheel": 0})

    def handle(self, is_text: bool, data: bytes) -> dict:
        if is_text:
            text = data.decode("utf-8")
            msg = json.loads(text)
            self.rec.frame("s2c", text=text, decoded=msg)
        else:
            msg = binary_snapshot(data)
            self.rec.frame("s2c", data=data, decoded=msg)
        t = msg.get("t")
        self.saw.add(t)
        if t == "status":
            self.state = msg["state"]
        elif t == "welcome":
            self.you = msg["you"]
        elif t == "snap":
            self.snap = msg
        elif t == "draft":
            self.send({"t": "choice", "kind": "mutation", "i": 0})
        elif t == "error":
            self.error = msg.get("msg")
        return msg

    def pump(self, seconds: float = 0.0) -> None:
        end = time.monotonic() + seconds
        while True:
            pkt = self.tr.recv(timeout=0.005)
            if pkt is not None:
                self.handle(*pkt)
                continue
            if time.monotonic() >= end:
                return

    def run(self) -> None:
        try:
            self._run()
        except Exception as exc:  # noqa: BLE001
            self.error = f"{type(exc).__name__}: {exc}"
            self.rec.note(f"thin bot stopped: {self.error}")
        finally:
            self.done = True

    def _run(self) -> None:
        hello = {"t": "hello", "v": 1, "tier": "thin", "enc": self.enc, "name": "Thin Bot",
                 "client": "capture-thin/1", "rate": self.args.rate}
        self.send(hello)
        self.pump(1.0)
        self.send({"t": "ping", "ms": 4242})
        self.send({"t": "lobby", "a": "chat", "text": "thin bot online"})
        self.send({"t": "lobby", "a": "vote", "map": self.args.map})
        self.pump(0.8)
        self.send({"t": "lobby", "a": "ready", "v": True})
        while self.state != "run" and not self.stop.is_set():
            self.pump(0.05)
        self.send({"t": "map_req"})
        next_in = time.monotonic()
        flip = False
        results_at = None
        while not self.stop.is_set():
            self.pump(0.0)
            if self.state == "results" and results_at is None:
                results_at = time.monotonic()
            if self.state == "lobby" and results_at is not None:
                self.pump(1.0)
                self.send({"t": "leave"})
                drain(self.pump, self.rec)
                return
            if self.state != "run" or time.monotonic() < next_in:
                time.sleep(0.002)
                continue
            next_in += 1 / 30
            mv, yaw, pitch, buttons = [0.0, 0.0], 0.0, 0.0, 0
            snap = self.snap
            if snap:
                me = snap["you"]
                yaw, pitch = me["yaw"], 0.0
                eye = [me["pos"][0], me["pos"][1] + 1.65, me["pos"][2]]
                enemies = [e for e in snap["enemies"] if e["type"] != "cumulus"]
                if enemies:
                    target = min(enemies, key=lambda e: math.dist(e["pos"], me["pos"]))
                    yaw, pitch = yaw_pitch_to(eye, [target["pos"][0], target["pos"][1] + 0.9, target["pos"][2]])
                    gun = me["slots"][me["slot"] - 1] if me["slot"] >= 1 else None
                    if math.dist(target["pos"], me["pos"]) < 22:
                        if gun and gun.get("ammo") == 0:
                            buttons = 32
                        else:
                            buttons = 1 | 2 if flip else 2
                phase = snap["weather"]["phase"]
                key = (phase, snap["weather"]["wave"])
                if phase in ("calm", "clearing") and snap["weather"]["phase_time_left"] > 3.2                         and self.ready_for != key and flip:
                    self.ready_for = key
                    buttons |= 1024
            flip = not flip
            self.send_input(mv, yaw, pitch, buttons)


class FullBot(threading.Thread):
    def __init__(self, args, rec: Recorder, transport: str, enc: str, stop: threading.Event, markers: dict) -> None:
        super().__init__(daemon=True)
        self.args, self.rec, self.enc, self.stop, self.markers = args, rec, enc, stop, markers
        port = args.thin_port if transport == "ws" else args.thin_tcp_port
        self.tr = open_transport(transport, args.host, port)
        self.you = 0
        self.protocol = 0
        self.roster: dict[int, dict] = {}
        self.map_id = ""
        self.running = False
        self.confirmed = False
        self.finished_at = None
        self.lobby_after_results = False
        self.run_id = 0
        self.rows = [[] for _ in range(5)]
        self.slot = 0
        self.enemies: dict[int, list[float]] = {}
        self.pos = [0.0, 0.0, 0.0]
        self.home = [0.0, 0.0, 0.0]
        self.yaw = 0.0
        self.phase = (0, 1, 0.0)
        self.ready_sent_for = None
        self.done = False
        self.error = None

    def control(self, msg: dict) -> None:
        text = json.dumps(msg, separators=(",", ":"))
        self.tr.send_text(text)
        self.rec.frame("c2s", text=text, decoded=msg)

    def rpc(self, node: str, method: str, args: list, rel: bool = True, mode: int | None = None) -> None:
        if mode is None:
            mode = fc.TRANSFER_RELIABLE if rel else fc.TRANSFER_UNRELIABLE_ORDERED
        decoded = {"t": "rpc", "node": node, "method": method, "args": args, "ch": 0,
                   "rel": mode == fc.TRANSFER_RELIABLE}
        if self.enc == "bin":
            raw = fc.encode_full_bin_rpc(node, method, args, ch=0, mode=mode)
            self.tr.send_binary(raw)
            self.rec.frame("c2s", data=raw, decoded=decoded)
        else:
            text = json.dumps(decoded, separators=(",", ":"))
            self.tr.send_text(text)
            self.rec.frame("c2s", text=text, decoded=decoded)

    def me(self) -> str:
        return f"Main/Players/P_{self.you}"

    def holder(self) -> str:
        return f"{self.me()}/Head/Camera3D/WeaponHolder"

    def handle(self, is_text: bool, data: bytes) -> None:
        if is_text:
            text = data.decode("utf-8")
            msg = json.loads(text)
            self.rec.frame("s2c", text=text, decoded=msg)
        else:
            msg = fc.decode_full_bin(data)
            self.rec.frame("s2c", data=data, decoded=msg)
        t = msg.get("t")
        if t == "welcome":
            self.you, self.protocol = msg["you"], msg["game_protocol"]
        if t == "error":
            self.error = msg.get("msg")
        if t != "rpc":
            return
        node, method, a = msg["node"], msg["method"], msg.get("args", [])
        if node == "Net" and method == "_rtt_ping":
            self.rpc("Net", "_rtt_pong", [int(a[0])], mode=fc.TRANSFER_UNRELIABLE)
        elif node == "Net" and method == "_push_roster":
            self.roster = fc.decode_roster_arg(a[0])
            if self.finished_at is not None and time.monotonic() - self.finished_at > 4.0:
                self.lobby_after_results = True
        elif node == "Net" and method == "_start_run":
            self.running, self.map_id = True, a[0]
            ids = sorted(self.roster)
            spawns = self.markers["maps"][self.map_id]["player_spawn"]
            spawn = spawns[ids.index(self.you) % len(spawns)] if self.you in ids else spawns[0]
            self.home = list(spawn["pos"])
            self.pos = list(self.home)
            # A real port loads the level here, then reports in.
            self.rpc("Net", "_report_in_run", [True])
        elif node == "Net" and method == "_confirm_run_ready":
            self.confirmed = True
            self.rpc(self.me(), "_report_exposure", [False, False])
            if self.run_id:
                self.rpc("Main/RunLoot", "_request_starter", [self.run_id, 1])
        elif node == "Main/RunLoot" and method == "_snapshot":
            self.run_id = int(a[0])
        elif node == self.holder() and method == "_private_state":
            self.rows, self.slot = a[2], int(a[4])
        elif node == "Main/Enemies" and method == "_spawn_enemy":
            self.enemies[int(a[0])] = fc_vec(a[2])
        elif node == "Main/Enemies" and method == "_sync_enemies":
            ids = a[0]["v"] if isinstance(a[0], dict) else a[0]
            pts = a[1]["v"] if isinstance(a[1], dict) else a[1]
            for i, eid in enumerate(ids):
                self.enemies[int(eid)] = list(pts[i])
        elif node == "Main/Enemies" and method in ("_despawn_enemy",):
            self.enemies.pop(int(a[0]), None)
        elif node == "Main/Enemies" and method == "_retire_enemies":
            ids = a[0]["v"] if isinstance(a[0], dict) else a[0]
            for eid in ids:
                self.enemies.pop(int(eid), None)
        elif node == "WeatherManager" and method == "_receive_phase":
            self.phase = (int(a[0]), int(a[1]), float(a[2]))
            if self.phase[0] in (0, 4) and self.confirmed:
                self.ready_sent_for = None
        elif node == "GameManager/MutationRoll" and method == "_deal_rpc":
            self.rpc("GameManager/MutationRoll", "_request_vote", [0])
        elif node == self.me() and method == "_teleport":
            self.pos = list(a[0]["v"][3]) if isinstance(a[0], dict) else self.pos
        elif node == "GameManager" and method == "_finish":
            self.finished_at = time.monotonic()

    def pump(self, seconds: float = 0.0) -> None:
        end = time.monotonic() + seconds
        while True:
            pkt = self.tr.recv(timeout=0.005)
            if pkt is not None:
                self.handle(*pkt)
                continue
            if time.monotonic() >= end:
                return

    def run(self) -> None:
        try:
            self._run()
        except Exception as exc:  # noqa: BLE001
            self.error = f"{type(exc).__name__}: {exc}"
            self.rec.note(f"full bot stopped: {self.error}")
        finally:
            self.done = True

    def _run(self) -> None:
        self.control({"t": "hello", "v": 1, "tier": "full", "enc": self.enc, "client": "capture-full/1"})
        self.pump(1.0)
        hello = json.dumps({"name": "Full Bot", "color": 3, "skin": 1, "colors": []}, separators=(",", ":"))
        self.rpc("Net", "_hello", [hello, self.protocol])
        self.pump(0.8)
        self.rpc("Net", "_request_chat", ["full bot online"])
        self.rpc("Net", "_request_map_vote", [self.args.map])
        self.pump(1.5)
        self.rpc("Net", "_request_ready", [True])
        next_tf = time.monotonic()
        next_shot = time.monotonic()
        step = 0
        reported_out = False
        while not self.stop.is_set():
            self.pump(0.0)
            if self.lobby_after_results:
                self.pump(1.0)
                self.control({"t": "leave"})
                drain(self.pump, self.rec)
                return
            if self.finished_at is not None:
                if not reported_out and time.monotonic() - self.finished_at > 4.5:
                    reported_out = True
                    self.rpc("Net", "_report_in_run", [False])
                time.sleep(0.005)
                continue
            if not self.confirmed:
                time.sleep(0.005)
                continue
            now = time.monotonic()
            if self.phase[0] in (0, 4) and self.ready_sent_for != self.phase and self.phase[2] > 3.5:
                self.ready_sent_for = self.phase
                self.rpc("GameManager", "_request_ready", [])
            if now >= next_tf:
                next_tf += 0.05
                step += 1
                angle = step * 0.05
                prev = list(self.pos)
                self.pos = [self.home[0] + math.cos(angle) * 1.5, self.home[1], self.home[2] + math.sin(angle) * 1.5]
                vel = [(self.pos[i] - prev[i]) / 0.05 for i in range(3)]
                if not self.enemies:
                    self.yaw = math.atan2(-vel[0], -vel[2]) if any(vel) else self.yaw
                self.rpc(self.me(), "_push_transform", [fc.v_vec3(*self.pos), self.yaw, 0.0, fc.v_vec3(*vel)], rel=False)
            item = self.rows[self.slot] if 0 <= self.slot < 5 else []
            if self.enemies and item and now >= next_shot:
                eye = [self.pos[0], self.pos[1] + 1.65, self.pos[2]]
                eid, epos = min(self.enemies.items(), key=lambda kv: math.dist(kv[1], self.pos))
                if math.dist(epos, self.pos) < 30:
                    aim = [epos[0], epos[1] + 0.9, epos[2]]
                    d = [aim[i] - eye[i] for i in range(3)]
                    n = math.sqrt(sum(c * c for c in d)) or 1.0
                    d = [c / n for c in d]
                    self.yaw = math.atan2(-d[0], -d[2])
                    serial, count = int(item[0]), int(item[3])
                    if count > 0:
                        self.rpc(self.holder(), "_request_shot",
                                 [self.run_id, serial, fc.v_vec3(*eye), fc.v_vec3(*d), False, True])
                        next_shot = now + 0.2
                    else:
                        self.rpc(self.holder(), "_action", [self.run_id, "reload", serial, -1])
                        next_shot = now + 2.0
            time.sleep(0.002)


def drain(pump, rec: Recorder) -> None:
    """After leave the server closes the socket; that close is the expected end."""
    try:
        pump(2.0)
    except (EOFError, OSError) as exc:
        rec.note(f"transport closed by server after leave ({type(exc).__name__})")


def fc_vec(v):
    if isinstance(v, dict):
        return list(v["v"])
    return list(v)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--session", choices=("json", "bin"), default="json")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=17777)
    parser.add_argument("--thin-port", type=int, default=17780)
    parser.add_argument("--thin-tcp-port", type=int, default=17781)
    parser.add_argument("--map", default="pinecrest")
    parser.add_argument("--rate", type=int, default=0, help="Thin snapshot rate (default 10 for json, 20 for bin)")
    parser.add_argument("--raw-dir", default=str(Path(os.environ.get("TEMP", "/tmp")) / "open-protocol-capture"))
    parser.add_argument("--timeout", type=float, default=420)
    parser.add_argument("--no-server", action="store_true", help="use an already running harness server")
    args = parser.parse_args()
    if not args.rate:
        args.rate = 10 if args.session == "json" else 20
    raw = Path(args.raw_dir)
    raw.mkdir(parents=True, exist_ok=True)
    markers = json.loads((REPO / "docs/open-protocol/level-markers.json").read_text(encoding="utf-8"))
    transport = "ws" if args.session == "json" else "tcp"
    server = None
    if not args.no_server:
        env = dict(os.environ, FALLOUT_TELEMETRY_URL="http://127.0.0.1:1/")
        log = open(raw / f"server-{args.session}.log", "w", encoding="utf-8")
        server = subprocess.Popen([args.godot, "--headless", "--path", str(REPO), "--audio-driver", "Dummy",
                                   "-s", "tools/open_protocol/capture_harness.gd", "--", "--server",
                                   f"--port={args.port}", f"--thin-port={args.thin_port}",
                                   f"--thin-tcp-port={args.thin_tcp_port}", "--map", args.map],
                                  stdout=log, stderr=subprocess.STDOUT, env=env)
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if "Open Protocol listeners" in (raw / f"server-{args.session}.log").read_text(encoding="utf-8", errors="replace"):
                break
            time.sleep(0.3)
        time.sleep(0.5)
    stop = threading.Event()
    thin_rec = Recorder(raw / f"thin-{args.session}.jsonl", f"thin {transport}/{args.session}", transport, args.session)
    full_rec = Recorder(raw / f"full-{args.session}.jsonl", f"full {transport}/{args.session}", transport, args.session)
    full = FullBot(args, full_rec, transport, args.session, stop, markers)
    full.start()
    time.sleep(0.4)
    thin = ThinBot(args, thin_rec, transport, args.session, stop)
    thin.start()
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline and not (thin.done and full.done):
        time.sleep(0.2)
    stop.set()
    for bot in (thin, full):
        bot.join(3)
        try:
            bot.tr.close()
        except Exception:  # noqa: BLE001
            pass
    if server:
        time.sleep(1.0)
        server.terminate()
        server.wait(10)
    print(f"thin: done={thin.done} error={thin.error} saw={sorted(thin.saw)}")
    print(f"full: done={full.done} error={full.error} finished={full.finished_at is not None} lobby={full.lobby_after_results}")
    print(f"raw logs in {raw}")
    return 0 if thin.error is None and full.error is None and full.lobby_after_results else 1


if __name__ == "__main__":
    sys.exit(main())
