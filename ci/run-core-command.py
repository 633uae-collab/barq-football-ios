"""Bound a command and its process group, including inherited output pipes."""
import datetime
import os
import signal
import subprocess
import sys
import time


def stamp(event, **fields):
    print(event + ' utc=' + datetime.datetime.now(datetime.timezone.utc).isoformat()
          + ''.join(' ' + key + '=' + str(value) for key, value in fields.items()), file=sys.stderr, flush=True)


def signal_group(pid, sig):
    try:
        os.killpg(pid, sig)
        return True
    except ProcessLookupError:
        return False


def cleanup_group(child):
    # A leader exiting on TERM does not mean its descendants closed stdout.
    # The old implementation only escalated while the leader was alive, so a
    # descendant ignoring TERM could hold the shell's tee open indefinitely.
    if signal_group(child.pid, signal.SIGTERM):
        try:
            child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            pass
        # Always escalate the GROUP, even after wait reaps the leader. Do not
        # probe killpg(..., 0): on the hosted macOS runner this returned EPERM
        # after TERM and replaced the expected timeout result with a traceback.
        signal_group(child.pid, signal.SIGKILL)
    try:
        child.wait(timeout=3)
    except subprocess.TimeoutExpired:
        stamp('FOTIQ_COMMAND_CLEANUP_INCOMPLETE', pid=child.pid)


def run(seconds, command):
    deadline = os.environ.get('FOTIQ_CORE_DEADLINE_EPOCH')
    if deadline:
        seconds = min(seconds, float(deadline) - time.time())
    if seconds <= 0:
        stamp('FOTIQ_COMMAND_TIMEOUT', reason='job-evidence-reserve')
        return 124
    stamp('FOTIQ_COMMAND_START', budgetSeconds=round(seconds, 3))
    child = subprocess.Popen(command, start_new_session=True)
    try:
        result = child.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        stamp('FOTIQ_COMMAND_TIMEOUT', pid=child.pid)
        result = 124
    finally:
        cleanup_group(child)
    stamp('FOTIQ_COMMAND_END', exitCode=result)
    return result


if __name__ == '__main__':
    sys.exit(run(float(sys.argv[1]), sys.argv[2:]))
