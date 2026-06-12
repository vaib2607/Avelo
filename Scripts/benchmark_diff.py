#!/usr/bin/env python3
import json
import sys

if len(sys.argv) != 3:
    print("usage: benchmark_diff.py before.json after.json", file=sys.stderr)
    sys.exit(2)

with open(sys.argv[1], "r", encoding="utf-8") as f:
    before = json.load(f)
with open(sys.argv[2], "r", encoding="utf-8") as f:
    after = json.load(f)

before_metrics = {m["name"]: m for m in before.get("metrics", [])}
after_metrics = {m["name"]: m for m in after.get("metrics", [])}

for name in sorted(before_metrics.keys() & after_metrics.keys()):
    b = float(before_metrics[name]["durationSeconds"])
    a = float(after_metrics[name]["durationSeconds"])
    pct = 0.0 if b == 0 else ((b - a) / b) * 100.0
    print(f"{name}: before={b:.3f}s after={a:.3f}s delta={pct:.1f}%")

for name in sorted(after_metrics.keys() - before_metrics.keys()):
    print(f"{name}: before=missing after={float(after_metrics[name]['durationSeconds']):.3f}s delta=unverified")
