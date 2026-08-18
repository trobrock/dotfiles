from __future__ import annotations

import builtins
import importlib.util
import io
import json
import pathlib
import signal
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "dot-local/lib/quickshell/tailscale_runner.py"
SPEC = importlib.util.spec_from_file_location("quickshell_tailscale_runner", MODULE_PATH)
assert SPEC and SPEC.loader
runner = importlib.util.module_from_spec(SPEC)
import sys
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)


class CommandTests(unittest.TestCase):
    def argv(self, args):
        return list(runner.build_command(args).argv)

    def test_every_mode_has_an_exact_literal_argv(self):
        self.assertEqual(self.argv(["status"]), ["/usr/bin/tailscale", "status", "--json"])
        self.assertEqual(self.argv(["accounts"]), ["/usr/bin/tailscale", "switch", "--list", "--json"])
        self.assertEqual(self.argv(["exit-nodes"]), ["/usr/bin/tailscale", "exit-node", "list"])
        self.assertEqual(self.argv(["up"]), ["/usr/bin/tailscale", "up"])
        self.assertEqual(self.argv(["down"]), ["/usr/bin/tailscale", "down"])
        self.assertEqual(self.argv(["switch", "acct:One_2"]), ["/usr/bin/tailscale", "switch", "acct:One_2"])
        self.assertEqual(self.argv(["set-exit", "100.64.2.3"]), ["/usr/bin/tailscale", "set", "--exit-node=100.64.2.3"])
        self.assertEqual(self.argv(["set-exit", ""]), ["/usr/bin/tailscale", "set", "--exit-node="])
        self.assertEqual(self.argv(["authorize", "person.name"]), ["/usr/bin/pkexec", "/usr/bin/tailscale", "set", "--operator=person.name"])
        self.assertEqual(
            self.argv(["send", "fd7a:115c:a1e0::1", "/tmp/a", "/tmp/b"]),
            ["/usr/bin/tailscale", "file", "cp", "--update-interval=0", "--", "/tmp/a", "/tmp/b", "fd7a:115c:a1e0::1:"],
        )

    def test_environment_request_is_bounded_parsed_and_removed(self):
        environ = {runner.REQUEST_ENV: json.dumps(["switch", "acct:One_2"]), "KEEP": "yes"}
        self.assertEqual(runner.request_from_environment(environ), ["switch", "acct:One_2"])
        self.assertNotIn(runner.REQUEST_ENV, environ)
        self.assertEqual(environ["KEEP"], "yes")

        invalid = [
            {},
            {runner.REQUEST_ENV: "not-json"},
            {runner.REQUEST_ENV: json.dumps("status")},
            {runner.REQUEST_ENV: json.dumps([])},
            {runner.REQUEST_ENV: "x" * (runner.MAX_REQUEST_BYTES + 1)},
        ]
        for value in invalid:
            with self.subTest(value_type=type(value.get(runner.REQUEST_ENV)).__name__):
                with self.assertRaises(ValueError):
                    runner.request_from_environment(value)

    def test_rejects_injection_and_wrong_mode_shapes(self):
        invalid = [
            [], ["status", "--evil"], ["switch", "x;id"], ["set-exit", "8.8.8.8"],
            ["set-exit", "$(id)"], ["authorize", "person;id"],
            ["send", "node.example", "relative"], ["send", "node.example", "/x", "--flag"],
            ["send", "node.example:evil", "/x"], ["send", "node.example", "/x\0bad"],
            ["send", "node.example"] + [f"/x/{n}" for n in range(33)],
        ]
        for args in invalid:
            with self.subTest(args=args):
                with self.assertRaises(ValueError):
                    runner.build_command(args)

    def test_validators_cover_tailnet_ranges_dns_ids_users_and_paths(self):
        self.assertTrue(runner.validate_opaque_id("peer:Abc_123+/=@-"))
        self.assertFalse(runner.validate_opaque_id("peer id"))
        self.assertTrue(runner.validate_target("100.127.255.255"))
        self.assertFalse(runner.validate_target("100.128.0.1"))
        self.assertTrue(runner.validate_target("fd7a:115c:a1e0:1::1"))
        self.assertFalse(runner.validate_target("fd7a:115c:a1e1::1"))
        self.assertTrue(runner.validate_target("node.example.ts.net"))
        self.assertFalse(runner.validate_target("-node.example"))
        self.assertTrue(runner.validate_user("A_user.name-1"))
        self.assertFalse(runner.validate_user("user name"))
        self.assertTrue(runner.validate_path("/does/not/need/to/exist"))
        self.assertFalse(runner.validate_path("relative"))


class FakeStream:
    def __init__(self, fd): self.fd = fd; self.closed = False
    def fileno(self): return self.fd
    def close(self): self.closed = True


class FakeProcess:
    def __init__(self):
        self.pid = 987654321
        self.stdout, self.stderr = FakeStream(10), FakeStream(11)
        self.waited = False
    def wait(self, timeout=None): self.waited = True; return 0


class FakeSelector:
    def __init__(self, batches): self.batches = list(batches); self.registered = []; self.closed = False
    def register(self, stream, _events, name): self.registered.append((stream, name))
    def unregister(self, _stream): pass
    def select(self, _timeout): return self.batches.pop(0) if self.batches else []
    def close(self): self.closed = True


class BoundedRunTests(unittest.TestCase):

    def test_streams_bounded_stdout_without_a_shell(self):
        # One data event and one EOF event for each synthetic pipe.
        # The selector's stream objects must be the process streams, so use
        # events created after replacing them in a small factory below.
        process = FakeProcess()
        selector = FakeSelector([
            [(type("K", (), {"fileobj": process.stdout, "data": "stdout"})(), 0)],
            [(type("K", (), {"fileobj": process.stdout, "data": "stdout"})(), 0)],
            [(type("K", (), {"fileobj": process.stderr, "data": "stderr"})(), 0)],
        ])
        output, errors, calls = io.BytesIO(), io.BytesIO(), []
        reads = {10: [b"hello", b""], 11: [b""]}
        with mock.patch.object(runner.os, "read", lambda fd, _n: reads[fd].pop(0)), mock.patch.object(runner.os, "killpg"):
            result = runner.run_bounded(runner.CommandSpec(("/usr/bin/tailscale", "down"), 8, 32, 5),
                popen_factory=lambda *a, **kw: (calls.append((a, kw)) or process), selector_factory=lambda: selector,
                stdout=output, stderr=errors, clock=lambda: 1.0)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(output.getvalue(), b"hello")
        self.assertEqual(errors.getvalue(), b"")
        self.assertFalse(calls[0][1]["shell"])
        self.assertTrue(calls[0][1]["start_new_session"])

    def test_stdout_and_stderr_caps_kill_the_group_and_emit_generic_marker(self):
        for channel in ("stdout", "stderr"):
            with self.subTest(channel=channel):
                process = FakeProcess()
                stream = process.stdout if channel == "stdout" else process.stderr
                key = lambda item, name: type("K", (), {"fileobj": item, "data": name})()
                selector = FakeSelector([[(key(stream, channel), 0)]])
                reads = {10: [b"abcdef" if channel == "stdout" else b""], 11: [b"abcdefgh" if channel == "stderr" else b""]}
                out, err = io.BytesIO(), io.BytesIO()
                with mock.patch.object(runner.os, "read", lambda fd, _n: reads[fd].pop(0)), mock.patch.object(runner.os, "killpg") as killpg:
                    result = runner.run_bounded(runner.CommandSpec(("/usr/bin/tailscale", "down"), 4, 20, 5),
                        popen_factory=lambda *_a, **_kw: process, selector_factory=lambda: selector,
                        stdout=out, stderr=err, clock=lambda: 1.0)
                self.assertTrue(result.output_limited)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b"OUTPUT_LIMIT", err.getvalue())
                self.assertLessEqual(len(out.getvalue()), 4)
                self.assertLessEqual(len(err.getvalue()), 20)
                self.assertGreaterEqual(killpg.call_count, 1)

    def test_timeout_kills_synthetic_process_group(self):
        process = FakeProcess()
        selector = FakeSelector([])
        ticks = iter([0.0, 2.0])
        with mock.patch.object(runner.os, "killpg") as killpg:
            result = runner.run_bounded(runner.CommandSpec(("/usr/bin/tailscale", "status"), 20, 20, 1),
                popen_factory=lambda *_a, **_kw: process, selector_factory=lambda: selector,
                stdout=io.BytesIO(), stderr=io.BytesIO(), clock=lambda: next(ticks))
        self.assertTrue(result.timed_out)
        self.assertEqual(result.returncode, 124)
        self.assertTrue(process.waited)
        self.assertGreaterEqual(killpg.call_count, 1)


class CoreProtectionTests(unittest.TestCase):
    def test_core_check_requires_both_limits_and_zero_filter(self):
        fake_open = mock.mock_open(read_data="0\n")
        with mock.patch.object(runner.resource, "getrlimit", return_value=(0, 0)), mock.patch.object(builtins, "open", fake_open):
            self.assertTrue(runner.core_dumps_disabled())
        with mock.patch.object(runner.resource, "getrlimit", return_value=(0, 1)):
            self.assertFalse(runner.core_dumps_disabled())

    def test_setup_lowers_limits_then_verifies(self):
        with mock.patch.object(runner.resource, "setrlimit") as setrlimit, mock.patch.object(runner, "core_dumps_disabled", return_value=True), mock.patch.object(builtins, "open", mock.mock_open()):
            self.assertTrue(runner.setup_core_protection())
        setrlimit.assert_called_once_with(runner.resource.RLIMIT_CORE, (0, 0))


if __name__ == "__main__":
    unittest.main()
