#!/usr/bin/env python3
"""Record explicit core phases; preflight before XCTest, never capture expired requests."""
import json
import os
import pathlib
import signal
import subprocess
import sys
import time

control = pathlib.Path(os.environ.get("FOTIQ_RECORDING_CONTROL", "/tmp/fotiq-core-recording"))
process = None
log_handle = None


def event(output, stage, **fields):
    row = {"stage": stage, "time": time.time(), **fields}
    with (output / "recording-events.jsonl").open("a") as handle:
        handle.write(json.dumps(row) + "\n")
    print("FOTIQ_RECORDING " + json.dumps(row), flush=True)


def stop():
    global process, log_handle
    if process is not None:
        if process.poll() is None:
            process.send_signal(signal.SIGINT)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        process = None
    if log_handle is not None:
        log_handle.close()
        log_handle = None


def terminate(*_):
    stop()
    raise SystemExit(0)


def prepare(output, udid):
    # simctl discovery can block on a busy host. Do it before the UI test,
    # outside its unchanged 20-second recording handshake, with a bound.
    event(output, "preflight-begin", udid=udid)
    devices = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "booted", "-j"], timeout=15))
    if not any(d["udid"] == udid for group in devices["devices"].values() for d in group):
        raise ValueError("Configured XCTest simulator is not booted")
    (control / "prepared.json").write_text(json.dumps({"udid": udid, "time": time.time()}))
    event(output, "preflight-ready", udid=udid)


def require_current(request):
    if time.time() >= request["expiresAt"] or (control / ("cancelled-" + request["id"])).exists():
        raise TimeoutError("Recording request expired or cancelled")


def handle(output, request):
    global process, log_handle
    result = {"id": request["id"], "ok": False}
    event(output, "request-received", request=request)
    try:
        if request["action"] == "start":
            require_current(request)
            stop()
            phase = request["phase"]
            if phase not in ("analyst", "restored"):
                raise ValueError("Unknown recording phase")
            udid = request["udid"]
            prepared = json.loads((control / "prepared.json").read_text())
            if udid != prepared["udid"]:
                raise ValueError("Actual XCTest simulator differs from preflight simulator")
            require_current(request)
            log = output / (phase + "-recording.log")
            log_handle = log.open("w")
            event(output, "capture-spawn", udid=udid, phase=phase)
            process = subprocess.Popen(
                ["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264",
                 str(output / (phase + "-uncut.mp4"))], stdout=log_handle, stderr=log_handle)
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                require_current(request)
                if process.poll() is not None:
                    raise RuntimeError("Recorder exited before confirmation")
                if "Recording started" in log.read_text():
                    break
                time.sleep(0.1)
            else:
                raise RuntimeError("Recorder did not confirm capture")
            require_current(request)
            event(output, "capture-confirmed", udid=udid, phase=phase)
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
    temporary = control / "ack.tmp"
    temporary.write_text(json.dumps(result))
    temporary.replace(control / "ack.json")
    event(output, "ack-written", request=request, result=result)


def main():
    output = pathlib.Path(sys.argv[1])
    control.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    if len(sys.argv) == 4 and sys.argv[2] == "--prepare":
        prepare(output, sys.argv[3])
        return
    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    last_id = None
    while True:
        request_path = control / "request.json"
        if request_path.exists():
            request = json.loads(request_path.read_text())
            if request["id"] != last_id:
                last_id = request["id"]
                handle(output, request)
        if process is not None and (control / ("cancelled-" + last_id)).exists():
            event(output, "capture-cancelled", id=last_id)
            stop()
        time.sleep(0.1)


if __name__ == "__main__":
    main()
