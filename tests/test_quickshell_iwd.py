from __future__ import annotations

import importlib.util
import io
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "dot-local/lib/quickshell/iwd_bridge.py"
SPEC = importlib.util.spec_from_file_location("quickshell_iwd_bridge", MODULE_PATH)
assert SPEC and SPEC.loader
bridge = importlib.util.module_from_spec(SPEC)
import sys
sys.modules[SPEC.name] = bridge
SPEC.loader.exec_module(bridge)


class FakeBackend:
    def __init__(self, view=None):
        self.view = view or make_view()
        self.refresh = lambda: None
        self.calls = []
        self.pending = None
        self.closed = False

    def set_refresh_callback(self, callback): self.refresh = callback
    def get_view(self): return self.view
    def _call(self, name, args, ok): self.calls.append((name, *args)); ok()
    def scan(self, station, ok, error): self._call("scan", (station,), ok)
    def power(self, station, enabled, ok, error): self._call("power", (station, enabled), ok)
    def disconnect(self, station, ok, error): self._call("disconnect", (station,), ok)
    def connect(self, station, path, passphrase, ok, error):
        self.calls.append(("connect", station, path, passphrase)); self.pending = (ok, error)
    def forget(self, path, ok, error): self._call("forget", (path,), ok)
    def autoconnect(self, path, enabled, ok, error): self._call("autoconnect", (path, enabled), ok)
    def cancel(self):
        if not self.pending: return False
        _, error = self.pending; self.pending = None; error("canceled"); return True
    def close(self): self.closed = True


def network(path="/private/station/network-one", name="Cafe", kind="psk", known="/private/known-one", auto=True, strength=-7000):
    return bridge.NetworkView(path, name, kind, False, known, auto, strength)


def make_view(networks=None, station="/private/station", owner_generation=0):
    return bridge.StateView(True, station, True, False, "disconnected", None, tuple(networks or [network()]), owner_generation)


def fixed_ids():
    count = 0
    def token():
        nonlocal count
        count += 1
        return f"opaque{count:04d}token"
    return bridge.OpaqueIds(token)


class SanitizerTests(unittest.TestCase):
    def test_controls_bidi_invisibles_and_separators_are_removed(self):
        dirty = "  Cafe\u202e\u200b\x00\n\t Name\u2028Tail\u2029  "
        self.assertEqual(bridge.sanitize_ssid(dirty), "Cafe NameTail")

    def test_whitespace_and_length_are_bounded(self):
        self.assertEqual(bridge.sanitize_ssid("a\u00a0 \t b"), "a b")
        self.assertEqual(len(bridge.sanitize_ssid("x" * 500)), 80)
        self.assertEqual(bridge.sanitize_ssid(123), "")

    def test_signal_is_bucketed(self):
        self.assertEqual([bridge.signal_bucket(x) for x in (-9000, -8000, -7000, -6000, -4000)], [0, 1, 2, 3, 4])


class SnapshotPrivacyTests(unittest.TestCase):
    def test_caps_networks_and_emits_no_paths_or_addresses(self):
        networks = [network(f"/secret/device/net-{i}", f"Generic {i}", "open", None, False, -4000) for i in range(55)]
        events = []
        app = bridge.Bridge(FakeBackend(make_view(networks)), events.append, fixed_ids())
        app.handle({"command": "snapshot", "seq": 7})
        state = events[-1]
        self.assertEqual(state["seq"], 7)
        self.assertEqual(len(state["networks"]), 50)
        encoded = json.dumps(state)
        self.assertNotIn("/secret", encoded)
        self.assertNotIn("device", encoded)
        self.assertNotIn("AA:BB:CC:DD:EE:FF", encoded)
        self.assertTrue(all(item["id"].startswith("opaque") for item in state["networks"]))

    def test_type_and_station_state_allowlists(self):
        view = bridge.StateView(True, "/s", True, False, "evil", None, (network(kind="hotspot"),))
        events = []
        bridge.Bridge(FakeBackend(view), events.append, fixed_ids()).send_snapshot()
        self.assertEqual(events[0]["stationState"], "disconnected")
        self.assertEqual(events[0]["networks"][0]["type"], "unknown")

    def test_station_and_unavailable_snapshots_invalidate_all_ids(self):
        backend = FakeBackend(make_view())
        events = []
        app = bridge.Bridge(backend, events.append, fixed_ids())
        app.send_snapshot()
        first = events[-1]["networks"][0]["id"]
        backend.view = make_view(station="/replacement/station")
        app.send_snapshot()
        second = events[-1]["networks"][0]["id"]
        self.assertNotEqual(first, second)
        self.assertIsNone(app.ids.path_for(first))

        backend.view = bridge.StateView(False)
        app.send_snapshot()
        self.assertIsNone(app.ids.path_for(second))
        backend.view = make_view(station="/replacement/station")
        app.send_snapshot()
        self.assertNotEqual(second, events[-1]["networks"][0]["id"])

    def test_daemon_owner_generation_invalidates_reused_paths(self):
        backend = FakeBackend(make_view(owner_generation=1))
        events = []
        app = bridge.Bridge(backend, events.append, fixed_ids())
        app.send_snapshot()
        first = events[-1]["networks"][0]["id"]

        backend.view = make_view(owner_generation=3)
        app.send_snapshot()
        second = events[-1]["networks"][0]["id"]
        self.assertNotEqual(first, second)
        self.assertIsNone(app.ids.path_for(first))

        events.clear()
        app.handle({"command": "connect", "id": first})
        self.assertEqual(events[-1]["code"], "stale_id")
        self.assertEqual(backend.calls, [])

    def test_identifier_maps_remain_bounded_during_churn(self):
        backend = FakeBackend()
        app = bridge.Bridge(backend, lambda _event: None, fixed_ids())
        for generation in range(20):
            backend.view = make_view([
                network(f"/generation/{generation}/{index}", kind="open", known=None)
                for index in range(75)
            ])
            app.send_snapshot()
            self.assertLessEqual(len(app.ids._path_to_id), bridge.MAX_NETWORKS)
            self.assertLessEqual(len(app.ids._id_to_path), bridge.MAX_NETWORKS)
            self.assertLessEqual(len(app._id_station), bridge.MAX_NETWORKS)


class ValidationAndMutationTests(unittest.TestCase):
    def setUp(self):
        self.backend = FakeBackend()
        self.events = []
        self.app = bridge.Bridge(self.backend, self.events.append, fixed_ids())
        self.app.send_snapshot()
        self.token = self.events[-1]["networks"][0]["id"]
        self.events.clear()

    def test_field_and_type_allowlists(self):
        bad = [
            {"command": "power", "enabled": 1},
            {"command": "scan", "extra": True},
            {"command": "snapshot", "seq": True},
            {"command": "connect", "id": self.token, "passphrase": "short"},
            {"command": "connect", "id": self.token, "username": "private-user"},
            {"command": "connect", "id": self.token, "privateKeyPassphrase": "private-secret"},
            ["snapshot"],
        ]
        for value in bad:
            self.app.handle(value)
            self.assertEqual(self.events[-1]["code"], "invalid_request")
        self.assertEqual(self.backend.calls, [])
        self.app.handle({"command": "not-allowed", "seq": 23})
        self.assertEqual(self.events[-1]["seq"], 23)
        self.assertEqual(self.events[-1]["command"], "invalid")

    def test_revalidates_stale_identifier(self):
        self.backend.view = make_view([])
        # make_view's default is intentional, so use an explicit empty StateView.
        self.backend.view = bridge.StateView(True, "/private/station", True, False, "disconnected", None, ())
        self.app.handle({"command": "connect", "id": self.token})
        self.assertEqual(self.events[-1]["code"], "stale_id")
        self.assertEqual(self.backend.calls, [])

    def test_rejects_identifier_after_selected_station_changes(self):
        self.backend.view = make_view([network()], station="/other/station")
        self.app.handle({"command": "forget", "id": self.token})
        self.assertEqual(self.events[-1]["code"], "stale_id")

    def test_connect_policy_and_secret_is_not_output(self):
        unknown = network("/private/unknown", "Allowed SSID", "psk", None, False)
        enterprise = network("/private/eap", "Enterprise SSID", "8021x", None, False)
        self.backend.view = make_view([unknown, enterprise])
        self.app.send_snapshot()
        ids = {item["name"]: item["id"] for item in self.events[-1]["networks"]}
        self.app.handle({"command": "connect", "id": ids["Allowed SSID"]})
        self.assertEqual(self.events[-1]["code"], "secret_required")
        self.app.handle({"command": "connect", "id": ids["Enterprise SSID"], "passphrase": "NeverOutputThis"})
        self.assertEqual(self.events[-1]["code"], "unsupported")
        self.app.handle({"command": "connect", "id": ids["Allowed SSID"], "passphrase": "NeverOutputThis"})
        self.assertEqual(
            self.backend.calls[-1],
            ("connect", "/private/station", "/private/unknown", "NeverOutputThis"),
        )
        self.assertNotIn("NeverOutputThis", json.dumps(self.events))

    def test_known_and_open_reject_unneeded_secret(self):
        self.app.handle({"command": "connect", "id": self.token, "passphrase": "NotSentAnywhere"})
        self.assertEqual(self.events[-1]["code"], "invalid_request")
        self.assertEqual(self.backend.calls, [])

    def test_psk_accepts_only_printable_ascii(self):
        unknown = network(kind="psk", known=None)
        self.backend.view = make_view([unknown])
        self.app.send_snapshot()
        token = self.events[-1]["networks"][0]["id"]
        for phrase in ("abcdefg\n", "abcdefg\x7f", "abcdefgé", "abcdefg\u202e"):
            self.app.handle({"command": "connect", "id": token, "passphrase": phrase})
            self.assertEqual(self.events[-1]["code"], "invalid_request")
        self.app.handle({"command": "connect", "id": token, "passphrase": "abcdefgh"})
        self.assertEqual(self.backend.calls[-1][-1], "abcdefgh")


class AgentTests(unittest.TestCase):
    def test_secret_is_one_use_and_target_bound(self):
        secret = "UniquePassphrase"
        agent = bridge.OneUseAgent("/target", secret)
        with self.assertRaises(bridge.AgentCanceled): agent.request_passphrase("/wrong")
        self.assertTrue(agent.has_secret)
        self.assertEqual(agent.request_passphrase("/target"), secret)
        self.assertFalse(agent.has_secret)
        with self.assertRaises(bridge.AgentCanceled): agent.request_passphrase("/target")
        self.assertNotIn(secret, repr(agent.__dict__))

    def test_every_non_psk_secret_method_rejects(self):
        agent = bridge.OneUseAgent("/target", "UniquePassphrase")
        for method, args in [
            (agent.request_private_key_passphrase, ("/target",)),
            (agent.request_user_name_and_password, ("/target",)),
            (agent.request_user_password, ("/target", "user")),
            (agent.reject, ()),
        ]:
            with self.assertRaises(bridge.AgentCanceled): method(*args)
        self.assertTrue(agent.has_secret)

    def test_cancel_and_release_clear_and_notify(self):
        calls = []
        for action in ("cancel", "release"):
            agent = bridge.OneUseAgent("/target", "UniquePassphrase", lambda: calls.append(action))
            getattr(agent, action)()
            self.assertFalse(agent.has_secret)
        self.assertEqual(calls, ["cancel", "release"])


class ErrorAndCleanupTests(unittest.TestCase):
    class Error:
        def __init__(self, name, message="runtime SSID and secret"): self.name, self.message = name, message
        def get_dbus_name(self): return self.name
        def __str__(self): return self.message

    def test_error_mapping_uses_only_exact_names(self):
        self.assertEqual(bridge.map_dbus_error(self.Error("net.connman.iwd.Busy")), "busy")
        self.assertEqual(bridge.map_dbus_error(self.Error("net.connman.iwd.Timeout")), "timeout")
        self.assertEqual(bridge.map_dbus_error(self.Error("net.connman.iwd.Busy.extra")), "failed")
        self.assertEqual(bridge.map_dbus_error(RuntimeError("secret")), "failed")



class BackendOperationTests(unittest.TestCase):
    class Error:
        def __init__(self, name="net.connman.iwd.Failed"): self.name = name
        def get_dbus_name(self): return self.name

    class Timers:
        def __init__(self):
            self.next_id = 1
            self.callbacks = {}
            self.removed = []

        def timeout_add_seconds(self, _seconds, callback):
            timer = self.next_id
            self.next_id += 1
            self.callbacks[timer] = callback
            return timer

        def source_remove(self, timer):
            self.removed.append(timer)
            self.callbacks.pop(timer, None)

        def fire(self, timer):
            callback = self.callbacks.pop(timer)
            callback()

    class Proxy:
        def __init__(self):
            self.registers = []
            self.unregisters = []
            self.connects = []
            self.disconnects = []

        def RegisterAgent(self, path, **callbacks): self.registers.append((path, callbacks))
        def UnregisterAgent(self, path, **callbacks): self.unregisters.append((path, callbacks))
        def Connect(self, **callbacks): self.connects.append(callbacks)
        def Disconnect(self, **callbacks): self.disconnects.append(callbacks)

    class Bus:
        def __init__(self):
            self.objects = {}
            self.added = []
            self.removed = []

        def get_object(self, _service, path):
            return self.objects.setdefault(str(path), BackendOperationTests.Proxy())

        def add_signal_receiver(self, callback, **kwargs): self.added.append((callback, kwargs))
        def remove_signal_receiver(self, callback, **kwargs): self.removed.append((callback, kwargs))

    class DBus:
        @staticmethod
        def Interface(obj, _interface): return obj
        @staticmethod
        def ObjectPath(path): return path

    class Agent:
        def __init__(self, core):
            self.core = core
            self.cleared = False
            self.removed = False
        def clear(self): self.cleared = True; self.core.clear()
        def remove_from_connection(self): self.removed = True

    def setUp(self):
        self.bus = self.Bus()
        self.timers = self.Timers()
        self.backend = bridge.IwdBackend.__new__(bridge.IwdBackend)
        self.backend.bus = self.bus
        self.backend.glib = self.timers
        self.backend.dbus = self.DBus
        self.backend.refresh = lambda: None
        self.backend.pending = None
        self.backend.receivers = []
        self.results = []
        self.agents = []

        def make_agent(_dbus, _bus, _path, core):
            agent = self.Agent(core)
            self.agents.append(agent)
            return agent

        self.agent_patch = mock.patch.object(bridge, "_make_dbus_agent", make_agent)
        self.agent_patch.start()

    def tearDown(self):
        self.agent_patch.stop()

    def connect(self, suffix="a", phrase=None):
        self.backend.connect(
            f"/station/{suffix}", f"/network/{suffix}", phrase,
            lambda: self.results.append((suffix, "ok")),
            lambda code: self.results.append((suffix, code)),
        )
        return self.backend.pending

    def test_stale_generation_callbacks_cannot_affect_new_operation(self):
        op_a = self.connect("a", "abcdefgh")
        manager = self.bus.get_object(bridge.IWD, "/net/connman/iwd")
        register_a = manager.registers[-1][1]
        register_a["reply_handler"]()
        connect_a = self.bus.get_object(bridge.IWD, "/network/a").connects[-1]

        self.assertTrue(self.backend.cancel())
        speculative_a = self.bus.get_object(bridge.IWD, "/station/a").disconnects[-1]
        speculative_a["reply_handler"]()
        self.assertIs(self.backend.pending, op_a)
        connect_a["error_handler"](self.Error())
        self.assertEqual(self.results, [("a", "canceled")])

        op_b = self.connect("b", "ijklmnop")
        self.assertIs(self.backend.pending, op_b)
        register_b = manager.registers[-1][1]
        unregister_count = len(manager.unregisters)
        register_a["reply_handler"]()
        self.assertEqual(len(manager.unregisters), unregister_count + 1)
        register_a["error_handler"](self.Error())
        connect_a["reply_handler"]()
        connect_a["error_handler"](self.Error())
        speculative_a["error_handler"](self.Error())
        self.assertIs(self.backend.pending, op_b)
        self.assertEqual(self.bus.get_object(bridge.IWD, "/network/b").connects, [])

        register_b["reply_handler"]()
        connect_b = self.bus.get_object(bridge.IWD, "/network/b").connects[-1]
        self.assertEqual(connect_b["timeout"], bridge.CONNECT_DBUS_TIMEOUT)
        connect_b["reply_handler"]()
        self.assertEqual(self.results[-1], ("b", "ok"))
        self.assertIsNot(op_a, op_b)

    def test_disconnect_before_connect_then_success_needs_second_disconnect(self):
        op = self.connect("cancel")
        connect_call = self.bus.get_object(bridge.IWD, "/network/cancel").connects[-1]
        self.assertTrue(op["connect_started"])
        self.assertTrue(self.backend.cancel())
        self.assertIs(self.backend.pending, op)
        disconnects = self.bus.get_object(bridge.IWD, "/station/cancel").disconnects
        self.assertEqual(len(disconnects), 1)
        self.assertEqual(disconnects[0]["timeout"], bridge.DISCONNECT_DBUS_TIMEOUT)

        # A speculative Disconnect terminal callback cannot release Connect.
        disconnects[0]["reply_handler"]()
        self.assertIs(self.backend.pending, op)
        self.connect("blocked")
        self.assertEqual(self.results[-1], ("blocked", "busy"))
        self.assertIs(self.backend.pending, op)

        # Connect success queues a distinct post-success Disconnect.
        connect_call["reply_handler"]()
        self.assertIs(self.backend.pending, op)
        self.assertEqual(len(disconnects), 2)
        self.assertEqual(op["post_success_disconnect_state"], "pending")
        # Duplicate/stale Connect and speculative callbacks are harmless.
        connect_call["error_handler"](self.Error())
        disconnects[0]["error_handler"](self.Error())
        self.assertIs(self.backend.pending, op)
        disconnects[1]["reply_handler"]()
        self.assertEqual(self.results[-1], ("cancel", "canceled"))
        self.assertIsNone(self.backend.pending)

    def test_post_success_disconnect_failure_reports_failure(self):
        op = self.connect("cancel-failed")
        connect_call = self.bus.get_object(bridge.IWD, "/network/cancel-failed").connects[-1]
        self.assertTrue(self.backend.cancel())
        connect_call["reply_handler"]()
        disconnects = self.bus.get_object(bridge.IWD, "/station/cancel-failed").disconnects
        disconnects[-1]["error_handler"](self.Error("net.connman.iwd.Failed"))
        self.assertEqual(self.results[-1], ("cancel-failed", "failed"))
        self.assertIsNone(self.backend.pending)

    def test_connect_error_while_aborting_preserves_abort_code(self):
        op = self.connect("connect-error")
        call = self.bus.get_object(bridge.IWD, "/network/connect-error").connects[-1]
        deadline = op["deadline"]
        self.timers.fire(deadline)
        self.assertIs(self.backend.pending, op)
        call["error_handler"](self.Error("net.connman.iwd.Failed"))
        self.assertEqual(self.results, [("connect-error", "timeout")])
        self.assertIsNone(self.backend.pending)

    def test_local_timeout_has_no_release_watchdog(self):
        op = self.connect("timeout")
        deadline = op["deadline"]
        self.timers.fire(deadline)
        self.assertTrue(op["aborting"])
        self.assertEqual(op["abort_code"], "timeout")
        self.assertIs(self.backend.pending, op)
        self.assertNotIn("abort_timeout", op)
        self.assertEqual(self.results, [])

    def test_cancel_before_registration_waits_for_registration_success(self):
        op = self.connect("agent", "abcdefgh")
        manager = self.bus.get_object(bridge.IWD, "/net/connman/iwd")
        registration = manager.registers[-1][1]
        self.assertEqual(registration["timeout"], bridge.REGISTER_AGENT_DBUS_TIMEOUT)
        self.agents[-1].core.cancel()
        self.assertTrue(op["aborting"])
        self.assertFalse(self.agents[-1].core.has_secret)
        self.assertFalse(self.agents[-1].removed)
        self.assertIs(self.backend.pending, op)
        self.assertEqual(self.bus.get_object(bridge.IWD, "/network/agent").connects, [])

        registration["reply_handler"]()
        self.assertEqual(self.results, [("agent", "canceled")])
        self.assertIsNone(self.backend.pending)
        self.assertEqual(self.bus.get_object(bridge.IWD, "/network/agent").connects, [])
        self.assertGreaterEqual(len(manager.unregisters), 1)
        self.assertTrue(self.agents[-1].removed)

    def test_cancel_before_registration_waits_for_registration_error(self):
        op = self.connect("register-error", "abcdefgh")
        registration = self.bus.get_object(
            bridge.IWD, "/net/connman/iwd"
        ).registers[-1][1]
        self.assertTrue(self.backend.cancel())
        self.assertIs(self.backend.pending, op)
        registration["error_handler"](self.Error())
        self.assertEqual(self.results, [("register-error", "canceled")])
        self.assertIsNone(self.backend.pending)
        self.assertEqual(
            self.bus.get_object(bridge.IWD, "/network/register-error").connects, []
        )

    def test_owner_changes_refresh_abort_and_receiver_is_removed(self):
        refreshes = []
        self.backend.refresh = lambda: refreshes.append(True)
        self.backend._subscribe()
        owner, kwargs = next(
            item for item in self.bus.added if item[1]["signal_name"] == "NameOwnerChanged"
        )
        self.assertEqual(kwargs["arg0"], bridge.IWD)
        op = self.connect("owner", "abcdefgh")
        owner(bridge.IWD, ":1.1", "")
        self.assertIsNone(self.backend.pending)
        self.assertEqual(self.results, [("owner", "unavailable")])
        self.assertTrue(self.agents[-1].cleared)
        owner(bridge.IWD, "", ":1.2")
        self.assertEqual(len(refreshes), 2)
        self.backend.close()
        self.assertEqual(len(self.bus.removed), 4)
        self.assertIsNotNone(op)

    def test_close_synchronously_disconnects_and_clears_agent_with_bound(self):
        self.backend.receivers = []
        self.connect("close", "abcdefgh")
        self.backend.close()
        self.assertIsNone(self.backend.pending)
        self.assertTrue(self.agents[-1].cleared)
        self.assertTrue(self.agents[-1].removed)
        manager = self.bus.get_object(bridge.IWD, "/net/connman/iwd")
        self.assertEqual(len(manager.unregisters), 1)
        disconnects = self.bus.get_object(bridge.IWD, "/station/close").disconnects
        self.assertEqual(len(disconnects), 1)
        self.assertEqual(disconnects[0]["timeout"], bridge.CLOSE_DISCONNECT_TIMEOUT)
        self.assertNotIn("reply_handler", disconnects[0])
        self.assertEqual(self.results, [])


class ProtocolTests(unittest.TestCase):
    def run_fixture(self, payload: bytes):
        source = io.BytesIO(payload)
        output = io.StringIO()
        bridge.run_fixture(source, output)
        return [json.loads(line) for line in output.getvalue().splitlines()], output.getvalue()

    def test_fixture_state_changes_and_secret_redaction(self):
        initial, _ = self.run_fixture(b'{"command":"snapshot","seq":1}\n')
        state = initial[-1]
        names = {item["name"]: item["id"] for item in state["networks"]}
        secret = "FixturePassphrase"
        payload = (json.dumps({"command": "connect", "id": names["Secure Network"], "passphrase": secret, "seq": 2}) + "\n" +
                   json.dumps({"command": "snapshot", "seq": 3}) + "\n").encode()
        events, raw = self.run_fixture(payload)
        # IDs are per-process, so obtain and use one in a single protocol session below.
        self.assertTrue(events[0]["code"] in {"stale_id", "invalid_request"})
        self.assertNotIn(secret, raw)

        backend = bridge.FixtureBackend(); output = []
        app = bridge.Bridge(backend, output.append, fixed_ids()); app.send_snapshot()
        token = next(item["id"] for item in output[-1]["networks"] if item["name"] == "Secure Network")
        app.handle({"command": "connect", "id": token, "passphrase": secret, "seq": 4})
        app.handle({"command": "snapshot"})
        self.assertEqual(output[-1]["stationState"], "connected")
        self.assertNotIn(secret, json.dumps(output))

    def test_bounded_and_duplicate_lines_are_rejected(self):
        events, _ = self.run_fixture(b"x" * (bridge.MAX_INPUT + 20) + b"\n" + b'{"command":"snapshot","command":"scan"}\n')
        self.assertEqual([event["code"] for event in events], ["invalid_request", "invalid_request"])

    def test_line_drain_processes_final_unterminated_line_once(self):
        backend = FakeBackend()
        events = []
        app = bridge.Bridge(backend, events.append, fixed_ids())
        drain = bridge.LineDrain(app)
        drain.feed(b'{"command":"snapshot","seq":41}')
        self.assertEqual(events, [])
        drain.finish()
        drain.finish()
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["seq"], 41)

    def test_line_drain_handles_data_before_hup_style_eof(self):
        backend = FakeBackend()
        events = []
        app = bridge.Bridge(backend, events.append, fixed_ids())
        drain = bridge.LineDrain(app)
        drain.feed(b'{"command":"snapshot","seq":42}\n')
        drain.feed(b'{"command":"snapshot","seq":43}')
        drain.finish()
        self.assertEqual([event["seq"] for event in events], [42, 43])

    def test_fixture_stderr_contract(self):
        stdin = io.StringIO("SyntheticSSID\nSyntheticPassphrase\n")
        stdout, stderr = io.StringIO(), io.StringIO()
        with mock.patch.object(sys, "stdin", stdin), mock.patch.object(sys, "stdout", stdout), mock.patch.object(sys, "stderr", stderr):
            self.assertEqual(bridge.main(["--fixture"]), 0)
        self.assertEqual(len(stdout.getvalue().splitlines()), 2)
        self.assertEqual(stderr.getvalue(), "")
        self.assertNotIn("SyntheticSSID", stderr.getvalue())
        self.assertNotIn("SyntheticPassphrase", stderr.getvalue())


class WrapperTests(unittest.TestCase):
    def test_wrapper_hardens_then_uses_absolute_isolated_python(self):
        # Preserve the launcher's relative layout in a temporary tree so its
        # production absolute-Python path can execute a harmless inspection stub.
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            bindir = root / "bin"
            libdir = root / "lib/quickshell"
            bindir.mkdir()
            libdir.mkdir(parents=True)
            wrapper = bindir / "quickshell-iwd"
            shutil.copy2(ROOT / "dot-local/bin/quickshell-iwd", wrapper)
            stub = libdir / "iwd_bridge.py"
            stub.write_text(
                "import json, resource, sys\n"
                "with open('/proc/self/coredump_filter', encoding='ascii') as f:\n"
                "    filt = f.read().strip()\n"
                "print(json.dumps({'limits': resource.getrlimit(resource.RLIMIT_CORE), "
                "'filter': filt, 'isolated': sys.flags.isolated, 'args': sys.argv[1:]}))\n",
                encoding="utf-8",
            )
            result = subprocess.run(
                [str(wrapper), "harmless-argument"],
                check=True,
                text=True,
                capture_output=True,
            )
            report = json.loads(result.stdout)
            self.assertEqual(report["limits"], [0, 0])
            self.assertRegex(report["filter"], r"^0+$")
            self.assertEqual(report["isolated"], 1)
            self.assertEqual(report["args"], ["harmless-argument"])
            self.assertEqual(result.stderr, "")


class ProbeTests(unittest.TestCase):
    def test_probe_contains_only_counts_and_presence(self):
        class Interface:
            def GetOrderedNetworks(self): return [("/private/network", -4000)]
        class DBus:
            @staticmethod
            def Interface(_object, _interface): return Interface()
        class Bus:
            @staticmethod
            def get_object(_service, _path): return object()
        backend = bridge.IwdBackend.__new__(bridge.IwdBackend)
        backend.dbus, backend.bus = DBus, Bus()
        backend._objects = lambda: {
            "/private/station": {bridge.STATION: {}, bridge.DEVICE: {"Address": "AA:BB", "Name": "wlan-private"}},
            "/private/network": {bridge.NETWORK: {"Name": "PrivateSSID"}},
            "/private/known": {bridge.KNOWN: {"LastConnectedTime": "private"}},
        }
        result = backend.probe()
        self.assertEqual(result["stationCount"], 1)
        self.assertEqual(result["networkCount"], 1)
        self.assertEqual(result["knownCount"], 1)
        encoded = json.dumps(result)
        for private in ("/private", "PrivateSSID", "AA:BB", "wlan-private", "LastConnectedTime"):
            self.assertNotIn(private, encoded)
        self.assertEqual(set(result), {
            "available", "stationCount", "networkCount", "knownCount", "hasStationInterface",
            "hasNetworkInterface", "hasKnownNetworkInterface", "hasDeviceInterface",
        })


if __name__ == "__main__":
    unittest.main()
