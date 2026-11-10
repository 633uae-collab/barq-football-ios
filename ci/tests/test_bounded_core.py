"""Real subprocess regressions: a dead leader must not leave a pipe open."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

RUNNER = Path(__file__).resolve().parents[1] / 'run-core-command.py'


class BoundedCoreTests(unittest.TestCase):
    def invoke(self, command, budget='0.5', extra=(), deadline=None):
        env = dict(os.environ)
        env.pop('FOTIQ_CORE_DEADLINE_EPOCH', None)
        if deadline is not None:
            env['FOTIQ_CORE_DEADLINE_EPOCH'] = str(deadline)
        proc = subprocess.Popen([sys.executable, str(RUNNER), budget, *extra,
                                 sys.executable, '-c', command],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                start_new_session=True, env=env)
        try:
            output, _ = proc.communicate(timeout=9)
            return proc.returncode, output.decode()
        except subprocess.TimeoutExpired as error:
            # Clean up only this test's synthetic grandchild, including old-runner regression.
            partial = (error.output or b'').decode()
            for line in partial.splitlines():
                if line.startswith('CHILD_PID='):
                    try:
                        os.kill(int(line.split('=')[1]), signal.SIGKILL)
                    except ProcessLookupError:
                        pass
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.communicate(timeout=3)
            self.fail('runner/descendant kept stdout open past the outer deadline')

    def test_preserves_failure_code(self):
        code, output = self.invoke("print('expected failure', flush=True); raise SystemExit(7)")
        self.assertEqual(code, 7)
        self.assertIn('expected failure', output)

    def test_timeout(self):
        code, output = self.invoke('import time; time.sleep(60)')
        self.assertEqual(code, 124)
        self.assertIn('FOTIQ_COMMAND_TIMEOUT', output)

    def test_expired_job_budget_does_not_start_child(self):
        code, output = self.invoke("print('MUST_NOT_RUN')", deadline=time.time() - 1)
        self.assertEqual(code, 124)
        self.assertNotIn('MUST_NOT_RUN', output)
        self.assertIn('job-evidence-reserve', output)

    def test_job_budget_caps_longer_command_budget(self):
        code, output = self.invoke('import time; time.sleep(60)', budget='60', deadline=time.time() + 0.5)
        self.assertEqual(code, 124)
        self.assertIn('FOTIQ_COMMAND_TIMEOUT', output)

    def orphan(self, wait):
        return """import os, signal, time
pid = os.fork()
if pid == 0:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    print('CHILD_PID=' + str(os.getpid()), flush=True)
    time.sleep(60)
else:
    time.sleep(%s)
""" % wait

    def test_normal_exit_cleans_pipe_holding_descendant(self):
        code, output = self.invoke(self.orphan('0.1'), budget='2')
        self.assertEqual(code, 0)
        self.assertIn('CHILD_PID=', output)

    def test_timeout_kills_descendant_even_when_leader_accepts_term(self):
        code, output = self.invoke(self.orphan('60'))
        self.assertEqual(code, 124)
        self.assertIn('FOTIQ_COMMAND_TIMEOUT', output)


if __name__ == '__main__':
    unittest.main()
