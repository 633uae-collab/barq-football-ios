import importlib.util
import json
import pathlib
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('recorder', pathlib.Path(__file__).parents[1] / 'record-core.py')
recorder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recorder)


class RecorderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = pathlib.Path(self.temp.name)
        recorder.control = self.output
        recorder.process = None
        recorder.log_handle = None
        self.request = dict(id='test-id', action='start', phase='analyst', udid='actual-device', expiresAt=time.time() + 20)
        (self.output / 'prepared.json').write_text(json.dumps({'udid': 'actual-device'}))
        self.addCleanup(recorder.stop)

    def ack(self):
        return json.loads((self.output / 'ack.json').read_text())

    def test_expired_start_never_launches_capture(self):
        self.request['expiresAt'] = time.time() - 1
        with patch.object(recorder.subprocess, 'Popen') as spawn:
            recorder.handle(self.output, self.request)
            spawn.assert_not_called()
        self.assertFalse(self.ack()['ok'])

    def test_cancelled_start_never_launches_capture(self):
        (self.output / 'cancelled-test-id').touch()
        with patch.object(recorder.subprocess, 'Popen') as spawn:
            recorder.handle(self.output, self.request)
            spawn.assert_not_called()
        self.assertFalse(self.ack()['ok'])

    def test_wrong_actual_device_rejected(self):
        self.request['udid'] = 'another-clone'
        with patch.object(recorder.subprocess, 'Popen') as spawn:
            recorder.handle(self.output, self.request)
            spawn.assert_not_called()
        self.assertFalse(self.ack()['ok'])

    def test_start_uses_actual_device_without_discovery_in_handshake(self):
        child = Mock()
        child.poll.return_value = None
        def spawn(args, **kwargs):
            self.assertEqual(args[3], 'actual-device')
            kwargs['stderr'].write('Recording started\n')
            kwargs['stderr'].flush()
            return child
        with patch.object(recorder.subprocess, 'Popen', side_effect=spawn), patch.object(recorder.subprocess, 'check_output') as discover:
            recorder.handle(self.output, self.request)
            discover.assert_not_called()
        self.assertTrue(self.ack()['ok'])
        recorder.handle(self.output, {'id': 'stop-id', 'action': 'stop'})
        child.send_signal.assert_called_once_with(recorder.signal.SIGINT)
        self.assertTrue(self.ack()['ok'])

    def test_request_expiring_during_spawn_cannot_report_success(self):
        child = Mock()
        child.poll.return_value = None
        def spawn(*args, **kwargs):
            self.request['expiresAt'] = time.time() - 1
            return child
        with patch.object(recorder.subprocess, 'Popen', side_effect=spawn):
            recorder.handle(self.output, self.request)
        self.assertFalse(self.ack()['ok'])
        child.send_signal.assert_called_once_with(recorder.signal.SIGINT)

    def test_preflight_is_bounded_and_requires_booted_device(self):
        with patch.object(recorder.subprocess, 'check_output', return_value=b'{"devices":{"iOS":[{"udid":"actual-device"}]}}') as discover:
            recorder.prepare(self.output, 'actual-device')
            self.assertEqual(discover.call_args.kwargs['timeout'], 15)
        with patch.object(recorder.subprocess, 'check_output', return_value=b'{"devices":{}}'):
            with self.assertRaises(ValueError):
                recorder.prepare(self.output, 'another-device')


if __name__ == '__main__':
    unittest.main()
