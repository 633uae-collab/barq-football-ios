#!/usr/bin/env python3
"""Fail CI when the real simulator launch misses FOTIQ's motion budgets."""

from pathlib import Path
import re
import sys


FINISH = re.compile(
    r"FINISH firstLaunch=(true|false) elapsed=([0-9.]+) "
    r"ready=(true|false) maxFrameGap=([0-9.]+)"
)


def fail(message: str) -> None:
    raise SystemExit(f"launch timing verification failed: {message}")


if len(sys.argv) != 2:
    fail("expected one launch-timing.log path")

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
rows = [
    {
        "firstLaunch": match.group(1) == "true",
        "elapsed": float(match.group(2)),
        "ready": match.group(3) == "true",
        "gap": float(match.group(4)),
    }
    for match in FINISH.finditer(text)
]
firstLaunch = [row for row in rows if row["firstLaunch"]]
quick = [row for row in rows if not row["firstLaunch"]]

if not firstLaunch:
    fail("no measured first-launch completion")
if not quick:
    fail("no measured quick-launch completion")

for row in rows:
    kind = "firstLaunch" if row["firstLaunch"] else "quick"
    if not row["ready"]:
        fail(f"{kind} exposed a destination that was not ready")
    if row["gap"] > 0.25:
        fail(f"{kind} maxFrameGap {row['gap']:.3f}s exceeds 0.250s")
    if not 0.8 <= row["elapsed"] < 1.0:
        fail(f"{kind} duration {row['elapsed']:.3f}s is outside 0.80-1.00s")

print(
    "launch timing verified: "
    f"{len(firstLaunch)} firstLaunch, {len(quick)} quick; "
    f"worst gap={max(row['gap'] for row in rows):.3f}s"
)
