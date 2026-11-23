#!/usr/bin/env python3
"""Run the isolated FOTIQ chat journey on a new, disposable local iPhone simulator."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

KIT = Path(__file__).resolve().parent
TEST = "BARQUITests/AnalystSyntheticSendUITests/testTenSyntheticSendsAfterThreeLongTurnsAndRelaunch"
ARCHIVE = Path("Library/Application Support/analyst-conversations.json")


def sim(*args, timeout=45):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True, timeout=timeout).strip()


def verify_archive(seed, saved, log, udid):
    assert f"FOTIQ_AX_REPLAY actualUDID={udid}" in log, "Device mismatch"
    assert len(saved) == 1 and saved[0]["turns"][:3] == seed[0]["turns"], "Seed changed"
    turns = saved[0]["turns"][3:]
    assert len(turns) == 11
    for i, turn in enumerate(turns, 1):
        reply = turn["answer"]
        assert not turn.get("error") and turn["question"] in reply["answer"]
        assert reply["sources"] == [{"name": "Synthetic diagnostic fixture — not live"}]
        if i <= 10:
            assert f"FOTIQ_AX_REPLAY restored={i} stage=verified" in log
    assert turns[-1]["question"] == "Synthetic restoration follow-up: verify saved history"
    assert "stage=full-restore-and-followup-verified" in log


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--video", action="store_true", help="Film after functional success with this kit")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.exit(2, "Requires a Mac with Xcode and an installed iOS 26 Simulator runtime.\n")
    head = (KIT / "head.txt").read_text().strip()
    success = KIT / ("functional-" + head + ".json")
    if args.video and not success.exists():
        parser.exit(2, "Run the functional pass first.\n")
    runtime_list = json.loads(sim("list", "runtimes", "-j"))["runtimes"]
    runtimes = [v for v in runtime_list if v.get("isAvailable") and v["identifier"].split(".")[-1].startswith("iOS-26-")]
    if os.getenv("FOTIQ_REQUIRE_NEW_INTEL_RUNTIME") == "1":
        runtimes = [v for v in runtimes if tuple(map(int, v["version"].split("."))) >= (26, 4)]
    if not runtimes:
        parser.exit(2, "No eligible installed iOS 26 simulator runtime.\n")
    runtime = max(runtimes, key=lambda v: tuple(map(int, v["version"].split("."))))
    output = Path(tempfile.mkdtemp(prefix="video-" if args.video else "functional-", dir=KIT))
    print("Evidence:", output, flush=True)
    control = output / "recording-control"
    env = {**os.environ, "FOTIQ_RECORDING_CONTROL": str(control)}
    env.pop("TEST_RUNNER_FOTIQ_RECORD_VIDEO", None)
    recorder = None
    products = KIT / "Products"
    runs = list(products.glob("*.xctestrun"))
    assert len(runs) == 1
    seed_path = KIT / "seed.json"
    device = sim("create", "FOTIQ offline " + output.name, "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro", runtime["identifier"])
    try:
        sim("boot", device)
        sim("bootstatus", device, "-b", timeout=120)
        sim("install", device, str(products / "Debug-iphonesimulator/BARQ.app"), timeout=120)
        archive = Path(sim("get_app_container", device, "ae.barq.football", "data")) / ARCHIVE
        archive.parent.mkdir(parents=True, exist_ok=True)
        with archive.open("xb") as f:
            f.write(seed_path.read_bytes())
        if args.video:
            control.mkdir()
            subprocess.run([sys.executable, str(KIT / "record-core.py"), str(output), "--prepare", device], env=env, check=True)
            (control / "enabled").touch()
            env.update(TEST_RUNNER_FOTIQ_RECORD_VIDEO="1", TEST_RUNNER_FOTIQ_RECORDING_CONTROL=str(control))
            recorder = subprocess.Popen([sys.executable, str(KIT / "record-core.py"), str(output)], env=env)
        cmd = [
               "xcodebuild", "test-without-building", "-xctestrun", str(runs[0]), "-destination", "id=" + device,
               "-parallel-testing-enabled", "NO", "-only-testing:" + TEST, "-resultBundlePath", str(output / "chat.xcresult")]
        with (output / "test.log").open("w") as log:
            subprocess.run([sys.executable, str(KIT / "run-core-command.py"), "900", *cmd],
                           env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        archive = Path(sim("get_app_container", device, "ae.barq.football", "data")) / ARCHIVE
        verify_archive(json.loads(seed_path.read_bytes()), json.loads(archive.read_bytes()), (output / "test.log").read_text(), device)
        result = {"head": head, "simulator": device, "runtime": runtime["version"], "restored": 10,
                  "followUp": True, "transport": "synthetic", "video": args.video}
        if args.video:
            events = [json.loads(s) for s in (output / "recording-events.jsonl").read_text().splitlines()]
            assert [e["phase"] for e in events if e["stage"] == "capture-confirmed" and e["udid"] == device] == ["analyst", "restored"]
            result["mp4SHA256"] = {}
            for phase in ("analyst", "restored"):
                movie = output / (phase + "-uncut.mp4")
                assert movie.stat().st_size > 0
                result["mp4SHA256"][phase] = hashlib.sha256(movie.read_bytes()).hexdigest()
        (output / "result.json").write_text(json.dumps(result, indent=2))
        if not args.video:
            success.write_text(json.dumps(result))
        print(json.dumps(result))
    finally:
        if recorder:
            recorder.terminate()
            recorder.wait(timeout=25)
        try:
            sim("shutdown", device)
        finally:
            sim("delete", device)


if __name__ == "__main__":
    main()
