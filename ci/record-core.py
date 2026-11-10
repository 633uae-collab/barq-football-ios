#!/usr/bin/env python3
"""Record only explicit core-test phases on the XCTest runner's simulator."""
import json
import pathlib
import signal
import subprocess
import sys
import time

control = pathlib.Path("/tmp/fotiq-core-recording")
output = pathlib.Path(sys.argv[1])
control.mkdir(parents=True, exist_ok=True)
output.mkdir(parents=True, exist_ok=True)
process = None
log_handle = None
last_id = None


def stop():
    global process, log_handle
    if process is not None:
        if process.poll() is None:
            process.send_signal(signal.SIGINT)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        process = None
    if log_handle is not None:
        log_handle.close()
        log_handle = None


def terminate(*_):
    stop()
    raise SystemExit(0)


signal.signal(signal.SIGTERM, terminate)
signal.signal(signal.SIGINT, terminate)
while True:
    request_path = control / "request.json"
    if request_path.exists():
        request = json.loads(request_path.read_text())
        if request["id"] != last_id:
            last_id = request["id"]
            result = {"id": last_id, "ok": False}
            try:
                if request["action"] == "start":
                    stop()
                    phase = request["phase"]
                    if phase not in ("analyst", "restored"):
                        raise ValueError("Unknown recording phase")
                    udid = request["udid"]
                    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "booted", "-j"]))
                    if not any(d["udid"] == udid for group in devices["devices"].values() for d in group):
                        raise ValueError("XCTest simulator is not booted")
                    path = output / (phase + "-uncut.mp4")
                    log = output / (phase + "-recording.log")
                    log_handle = log.open("w")
                    process = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo",
                                                "--codec=h264", str(path)],
                                               stdout=log_handle, stderr=log_handle)
                    deadline = time.monotonic() + 10
                    while time.monotonic() < deadline:
                        if process.poll() is not None:
                            raise RuntimeError("Recorder exited before confirmation")
                        if "Recording started" in log.read_text():
                            break
                        time.sleep(0.1)
                    else:
                        raise RuntimeError("Recorder did not confirm capture")
                    result.update({"udid": udid, "phase": phase})
                elif request["action"] == "stop":
                    stop()
                else:
                    raise ValueError("Unknown recording action")
                result["ok"] = True
            except Exception as error:
                result["error"] = str(error)
                stop()
            result["time"] = time.time()
            with (output / "recording-events.jsonl").open("a") as handle:
                handle.write(json.dumps({"request": request, "result": result}) + "\n")
            temporary = control / "ack.tmp"
            temporary.write_text(json.dumps(result))
            temporary.replace(control / "ack.json")
    time.sleep(0.1)
