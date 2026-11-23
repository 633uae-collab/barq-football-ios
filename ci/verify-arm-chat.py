#!/usr/bin/env python3
"""Run the prebuilt iOS chat kit once and measure RSS of its verified simulator app."""
import argparse
import json
from pathlib import Path
import platform
import re
import statistics
import subprocess
import sys
import time

HEAD = "e98ff73c661b76b5c5982d9ccaea90f49bcf8402"
UUID = r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}"
APP = re.compile(r"/CoreSimulator/Devices/(" + UUID + r")/data/Containers/Bundle/Application/[^/]+/BARQ\.app/BARQ$")
TURN = re.compile(r"FOTIQ_AX_REPLAY question=(\d+) stage=(input-start|verified) utc=([\d.]+)")


def sample():
    rows = subprocess.check_output(["/bin/ps", "-Aww", "-o", "pid=,rss=,comm="],
                                   text=True, timeout=3).splitlines()
    now = time.time()
    found = []
    for row in rows:
        fields = row.split(None, 2)
        if len(fields) == 3:
            match = APP.search(fields[2])
            if match:
                found.append((match[1].upper(), {
                    "utc": now, "pid": int(fields[0]), "rssMiB": int(fields[1]) / 1024
                }))
    return found


def evaluate(log, rows, complete):
    times = {(int(i), stage): float(t) for i, stage, t in TURN.findall(log)}
    turns = {}
    for i in range(1, 11):
        start = times.get((i, "input-start"))
        end = times.get((i, "verified"))
        if start is not None and end is not None and end >= start:
            turns[i] = (start, end)
    report = {"status": "insufficient", "samples": len(rows),
              "turnSeconds": {i: round(b - a, 2) for i, (a, b) in turns.items()},
              "peakRSSMiB": max((r["rssMiB"] for r in rows), default=None)}
    if not complete or len(turns) != 10:
        return report
    finish = re.search(r"FOTIQ_AX_REPLAY stage=complete utc=([\d.]+)", log)
    if not finish:
        return report

    def window(ids):
        return [(i, r) for i in ids for r in rows if turns[i][0] <= r["utc"] <= turns[i][1]]

    early, late = window((2, 3, 4)), window((8, 9, 10))
    first = {r["pid"] for _, r in early + late}
    if len(first) != 1:
        return report
    restored = [r for r in rows if turns[10][1] < r["utc"] <= float(finish[1]) and r["pid"] not in first]
    report["restoredProcessIDs"] = sorted({r["pid"] for r in restored})
    report["originalProcessID"] = next(iter(first))
    for group in (early, late):
        if len(group) < 3 or len({i for i, _ in group}) < 2:
            return report
    if len(restored) < 2 or len(report["restoredProcessIDs"]) != 1:
        return report
    before, after = [statistics.median(r["rssMiB"] for _, r in group) for group in (early, late)]
    tolerance = max(32, before * 0.25)
    report.update(earlyMedianMiB=before, lateMedianMiB=after, growthMiB=after - before,
                  allowedGrowthMiB=tolerance, restoredPeakMiB=max(r["rssMiB"] for r in restored),
                  status="within-budget" if after - before <= tolerance else "above-budget")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kit", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if (platform.system(), platform.machine()) != ("Darwin", "arm64"):
        parser.exit(2, "Requires native Apple Silicon macOS.\n")
    kit = args.kit.resolve()
    if (kit / "head.txt").read_text().strip() != HEAD:
        parser.exit(2, "Unexpected simulator package revision.\n")
    args.output.mkdir(parents=True, exist_ok=False)
    previous = set(kit.glob("functional-*/"))
    with (args.output / "functional.log").open("w") as log:
        run = subprocess.Popen([sys.executable, str(kit / "run.py")], stdout=log, stderr=subprocess.STDOUT)
        samples = []
        missed = 0
        while run.poll() is None:
            try:
                samples.extend(sample())
            except (OSError, subprocess.SubprocessError):
                missed += 1
            try:
                run.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
    folders = set(kit.glob("functional-*/")) - previous
    evidence = next(iter(folders)) if len(folders) == 1 else None
    log = (evidence / "test.log").read_text(errors="replace") if evidence and (evidence / "test.log").exists() else ""
    device = re.search(r"FOTIQ_AX_REPLAY actualUDID=(" + UUID + ")", log)
    rows = [r for uid, r in samples if device and uid == device[1].upper()]
    result = {}
    if evidence and (evidence / "result.json").is_file():
        result = json.loads((evidence / "result.json").read_text())
    passed = bool(run.returncode == 0 and device and result.get("head") == HEAD
                  and result.get("simulator", "").upper() == device[1].upper()
                  and result.get("restored") == 10 and result.get("followUp") is True
                  and result.get("transport") == "synthetic")
    report = evaluate(log, rows, passed)
    report.update(functionalPassed=passed, kitHead=HEAD, launcherExit=run.returncode, missedPolls=missed,
                  actualUDID=device[1] if device else None, runtime=result.get("runtime"))
    (args.output / "memory.json").write_text(json.dumps(report, indent=2) + "\n")
    (args.output / "rss.jsonl").write_text("".join(json.dumps(r) + "\n" for r in rows))
    print(json.dumps(report, indent=2))
    return 0 if passed and report["status"] == "within-budget" else 1


if __name__ == "__main__":
    sys.exit(main())
