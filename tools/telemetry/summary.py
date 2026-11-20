"""Summarize Fallout Forecast telemetry (JSONL from the collector).

    python tools/telemetry/summary.py telemetry.jsonl [--since 2026-11-20]

Prints installs/sessions per platform and GPU, frame-time percentiles from the
merged histograms, run results per map, and the worst spikes with the events
just before them.
"""
import argparse
import collections
import json

BUCKETS = [8, 12, 17, 25, 33, 50, 75, 100, 150, 250, 500, 1000, 2500, 5000, 10**6]


def pct(hist, p):
    total = sum(hist)
    if not total:
        return "-"
    seen = 0
    for i, n in enumerate(hist):
        seen += n
        if seen >= total * p:
            return f"<={BUCKETS[i]} ms" if BUCKETS[i] < 10**6 else ">5000 ms"
    return "?"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--since", default="")
    ap.add_argument("--spikes", type=int, default=25)
    args = ap.parse_args()
    sessions = {}
    hist = collections.defaultdict(lambda: [0] * len(BUCKETS))
    spikes = []
    runs = collections.defaultdict(lambda: collections.Counter())
    with open(args.file, encoding="utf-8") as f:
        for line in f:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if e.get("received", "") < args.since:
                continue
            d = e.get("data", {})
            sid = e.get("session")
            if e["kind"] == "session":
                sessions[sid] = d | {"install": e.get("install"), "protocol": e.get("protocol")}
            platform = "web" if e.get("web") else "desktop"
            if e["kind"] == "perf":
                for i, n in enumerate(d.get("hist", [])[: len(BUCKETS)]):
                    hist[platform][i] += int(n)
                for s in d.get("spikes", []):
                    gpu = sessions.get(sid, {}).get("adapter", "?")
                    spikes.append((s.get("ms", 0), platform, gpu, d.get("map", ""), s))
            if e["kind"] == "run_end":
                r = runs[d.get("map", "?")]
                r["runs"] += 1
                r["won"] += bool(d.get("won"))
                r["endless"] += bool(d.get("endless"))
                r["online"] += bool(d.get("online"))
    installs = {s.get("install") for s in sessions.values()}
    print(f"sessions {len(sessions)}  installs {len(installs)}")
    by = collections.Counter((("web" if s.get("web") else s.get("os", "?")), s.get("adapter", "?")) for s in sessions.values())
    for (plat, gpu), n in by.most_common(15):
        print(f"  {n:4d}  {plat:8s} {gpu}")
    print("\nframe times")
    for plat, h in hist.items():
        print(f"  {plat:8s} frames {sum(h):9d}  p50 {pct(h, .5)}  p95 {pct(h, .95)}  p99 {pct(h, .99)}")
    print("\nruns")
    for m, r in sorted(runs.items()):
        print(f"  {m or '?':14s} runs {r['runs']:4d}  won {r['won']:4d}  endless {r['endless']:4d}  online {r['online']:4d}")
    print(f"\nworst {args.spikes} spikes")
    for ms, plat, gpu, m, s in sorted(spikes, key=lambda x: -x[0])[: args.spikes]:
        before = ", ".join(map(str, s.get("before", [])))[:140]
        print(f"  {ms:6d} ms  {plat:7s} {m or s.get('scene', ''):14s} draws {s.get('draws', 0):4d}  {gpu[:28]:28s} after: {before}")


if __name__ == "__main__":
    main()
