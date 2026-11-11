#!/usr/bin/env python3
"""Capture bounded, timestamped app stacks while a core UI test stops logging."""
import datetime
import json
import pathlib
import subprocess
import sys
import time


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def watch(log, target_udid):
    last_size = -1
    last_change = time.monotonic()
    last_capture = 0.0
    captures = 0
    metadata = log.with_name(log.stem + "-samples.jsonl")
    while captures < 3:
        size = log.stat().st_size if log.exists() else 0
        now = time.monotonic()
        if size != last_size:
            last_size, last_change = size, now
        if size and now - last_change >= 20 and now - last_capture >= 60:
            processes = subprocess.run(["pgrep", "-x", "BARQ"], capture_output=True, text=True).stdout.split()
            for pid in processes[:3]:
                command = subprocess.run(["ps", "-p", pid, "-o", "command="], capture_output=True, text=True).stdout.strip()
                if not command:
                    continue
                # Record the actual executable path so simulator clones can be
                # distinguished from the requested destination during review.
                output = log.with_name(log.stem + "-sample-" + str(captures + 1) + "-" + pid + ".txt")
                event = {"startedAt": utc(), "pid": int(pid), "command": command,
                         "requestedUDID": target_udid, "logBytes": size,
                         "quietSeconds": round(now - last_change, 3), "sample": output.name}
                with metadata.open("a") as handle:
                    handle.write(json.dumps(event) + "\n")
                result = subprocess.run(["/usr/bin/sample", pid, "8", "1", "-file", str(output)],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                with metadata.open("a") as handle:
                    handle.write(json.dumps({"endedAt": utc(), "pid": int(pid),
                                             "sample": output.name, "exitCode": result.returncode}) + "\n")
            captures += 1
            last_capture = time.monotonic()
        time.sleep(1)


if __name__ == "__main__":
    watch(pathlib.Path(sys.argv[1]), sys.argv[2])
