"""Bound a diagnostic child process group, leaving time to upload evidence."""
import datetime
import os
import signal
import subprocess
import sys


def run(seconds, command):
    child = subprocess.Popen(command, start_new_session=True)
    try:
        return child.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        print("FOTIQ_COMMAND_TIMEOUT utc=" + datetime.datetime.now(datetime.timezone.utc).isoformat(), flush=True)
        os.killpg(child.pid, signal.SIGTERM)
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait(timeout=5)
        return 124


if __name__ == "__main__":
    sys.exit(run(float(sys.argv[1]), sys.argv[2:]))
