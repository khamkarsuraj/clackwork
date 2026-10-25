#!/usr/bin/env python3
"""Saves and compares latency reports from the app (issue #46).

A report is the JSON the app prints after "latency-report: ", from the bench
(-latencyBench) or the live probe (-measureLatency).

Usage:
  scripts/latency_report.py save <out.json> --commit <sha>   < report-line-json
  scripts/latency_report.py compare <old.json> <new.json>
  scripts/latency_report.py self-test

compare prints each part side by side and exits with status 1 when the new
run's total p95 is over the 20 ms budget, or more than 1 ms worse than the old
run's. It warns when the two runs were taken on different setups, since then
the numbers aren't like for like.
"""

import datetime
import json
import sys

BUDGET_MS = 20.0
ALLOWED_REGRESSION_MS = 1.0
# Wired and built-in outputs report a few ms; Bluetooth reports 100 ms or more.
BLUETOOTH_LIKE_MS = 50.0
# Context fields that change the numbers; a difference makes the comparison unfair.
SETUP_FIELDS = ["configuration", "macModel", "outputDevice", "ioBufferFrames", "deviceSampleRate",
                "profile", "intervalMs"]


def verdict(old, new):
    """Returns a list of reasons the new report fails, empty when it passes."""
    reasons = []
    new_p95 = new["parts"]["total"]["p95"]
    if new_p95 > BUDGET_MS:
        reasons.append(f"total p95 {new_p95:.1f} ms is over the {BUDGET_MS:.0f} ms budget")
    if old is not None:
        old_p95 = old["parts"]["total"]["p95"]
        if new_p95 - old_p95 > ALLOWED_REGRESSION_MS:
            reasons.append(f"total p95 is {new_p95 - old_p95:.1f} ms worse than before "
                           f"({old_p95:.1f} -> {new_p95:.1f} ms)")
    return reasons


def setup_differences(old, new):
    old_ctx, new_ctx = old.get("context", {}), new.get("context", {})
    return [f"{field}: {old_ctx.get(field)} -> {new_ctx.get(field)}"
            for field in SETUP_FIELDS if old_ctx.get(field) != new_ctx.get(field)]


def save(out_path, commit, line):
    report = json.loads(line)
    report["commit"] = commit
    report["date"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    with open(out_path, "w") as f:
        json.dump(report, f, indent=2, sort_keys=True)
        f.write("\n")
    ctx = report.get("context", {})
    print(f"  output: {ctx.get('outputDevice', '?')}, audio path {report['audioPathMs']:.1f} ms "
          f"({ctx.get('ioBufferFrames', '?')} frames at {ctx.get('deviceSampleRate', '?')} Hz)")
    if (ctx.get("outputLatencyMs") or 0) > BLUETOOTH_LIKE_MS:
        print(f"  warning: output latency {ctx['outputLatencyMs']:.0f} ms looks like Bluetooth; "
              "measure with built-in speakers or wired output")
    for name in sorted(report["parts"]):
        part = report["parts"][name]
        print(f"  {name:<9} p50 {part['p50']:5.2f}  p95 {part['p95']:5.2f}  max {part['max']:5.2f} ms")
    reasons = verdict(None, report)
    for reason in reasons:
        print(f"FAIL: {reason}")
    return 1 if reasons else 0


def compare(old_path, new_path):
    with open(old_path) as f:
        old = json.load(f)
    with open(new_path) as f:
        new = json.load(f)
    print(f"old: {old.get('commit', '?')} {old.get('date', '')}")
    print(f"new: {new.get('commit', '?')} {new.get('date', '')}")
    for difference in setup_differences(old, new):
        print(f"warning: different setup, {difference}")
    print(f"{'part':<9} {'stat':<4} {'old':>7} {'new':>7} {'change':>8}")
    for name in sorted(set(old["parts"]) & set(new["parts"])):
        for stat in ("p50", "p95", "max"):
            a, b = old["parts"][name][stat], new["parts"][name][stat]
            print(f"{name:<9} {stat:<4} {a:7.2f} {b:7.2f} {b - a:+8.2f}")
    reasons = verdict(old, new)
    for reason in reasons:
        print(f"FAIL: {reason}")
    if not reasons:
        print("PASS")
    return 1 if reasons else 0


def self_test():
    def report(p95, device="Speakers"):
        return {"parts": {"total": {"p50": p95 - 1, "p95": p95, "max": p95 + 1}},
                "context": {"outputDevice": device}}

    assert verdict(None, report(12)) == []
    assert len(verdict(None, report(21))) == 1, "over budget"
    assert verdict(report(12), report(12.9)) == [], "within the allowed 1 ms"
    assert len(verdict(report(12), report(13.5))) == 1, "1.5 ms worse"
    assert verdict(report(12), report(8)) == [], "faster is fine"
    assert len(verdict(report(19.5), report(21))) == 2, "over budget and worse"
    assert setup_differences(report(12), report(12)) == []
    assert setup_differences(report(12), report(12, device="AirPods")) == ["outputDevice: Speakers -> AirPods"]
    print("self-test passed")
    return 0


def main(args):
    if len(args) >= 3 and args[0] == "save" and "--commit" in args:
        return save(args[1], args[args.index("--commit") + 1], sys.stdin.read())
    if len(args) == 3 and args[0] == "compare":
        return compare(args[1], args[2])
    if args == ["self-test"]:
        return self_test()
    print(__doc__.strip())
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
