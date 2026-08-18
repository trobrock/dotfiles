#!/usr/bin/env python3
"""Privacy-minimising, persistent JSON-lines bridge for iwd.

The protocol-facing code is deliberately independent of D-Bus.  IwdBackend is
only constructed by main(), which keeps unit tests and --fixture off the system
bus.
"""

from __future__ import annotations

import json
import os
import secrets
import signal
import sys
import unicodedata
from dataclasses import dataclass
from typing import Any, Callable, Protocol

MAX_INPUT = 16 * 1024
MAX_NETWORKS = 50
MAX_NAME = 80
MAX_SEQ = 2_147_483_647
CONNECT_TIMEOUT = 45
CONNECT_DBUS_TIMEOUT = 60
REGISTER_AGENT_DBUS_TIMEOUT = 30
DISCONNECT_DBUS_TIMEOUT = 30
CLOSE_DISCONNECT_TIMEOUT = 5

IWD = "net.connman.iwd"
DBUS = "org.freedesktop.DBus"
OBJMGR = "org.freedesktop.DBus.ObjectManager"
PROPS = "org.freedesktop.DBus.Properties"
STATION = IWD + ".Station"
NETWORK = IWD + ".Network"
KNOWN = IWD + ".KnownNetwork"
DEVICE = IWD + ".Device"
AGENT_MANAGER = IWD + ".AgentManager"
AGENT = IWD + ".Agent"
CANCELED_ERROR = AGENT + ".Error.Canceled"

STATION_STATES = {"connected", "disconnected", "connecting", "disconnecting", "roaming"}
NETWORK_TYPES = {"open", "psk", "8021x", "wep"}
ERROR_CODES = {
    IWD + ".Aborted": "aborted",
    IWD + ".Busy": "busy",
    IWD + ".Failed": "failed",
    IWD + ".NoAgent": "no_agent",
    IWD + ".NotSupported": "unsupported",
    IWD + ".Timeout": "timeout",
    IWD + ".InProgress": "busy",
    IWD + ".NotConfigured": "not_configured",
    IWD + ".NotConnected": "not_connected",
    IWD + ".NotFound": "not_found",
    IWD + ".InvalidArguments": "invalid_request",
    IWD + ".AlreadyExists": "busy",
    IWD + ".Error.InvalidArguments": "invalid_request",
    IWD + ".Error.Failed": "failed",
    IWD + ".Error.AlreadyExists": "busy",
    IWD + ".Error.NotFound": "not_found",
    IWD + ".Error.NotSupported": "unsupported",
}


def sanitize_ssid(value: Any) -> str:
    """Return a bounded display value without control/format separators."""
    if not isinstance(value, str):
        return ""
    chars: list[str] = []
    for char in value:
        if unicodedata.category(char) in {"Cc", "Cf", "Zl", "Zp"}:
            continue
        chars.append(char if not char.isspace() else " ")
    return " ".join("".join(chars).split())[:MAX_NAME]


def signal_bucket(raw: Any) -> int:
    """Map iwd's 100*dBm range to five privacy-safe display buckets."""
    try:
        value = int(raw)
    except (TypeError, ValueError, OverflowError):
        return 0
    if value >= -5000:
        return 4
    if value >= -6500:
        return 3
    if value >= -7500:
        return 2
    if value >= -8500:
        return 1
    return 0


def dbus_error_name(error: Any) -> str:
    try:
        name = error.get_dbus_name()
    except Exception:
        return ""
    return name if isinstance(name, str) else ""


def map_dbus_error(error: Any) -> str:
    """Map only an exact D-Bus error-name allowlist; never inspect messages."""
    return ERROR_CODES.get(dbus_error_name(error), "failed")


class OpaqueIds:
    """Random per-process identifiers with no derivation from object paths."""

    def __init__(self, token_factory: Callable[[], str] | None = None) -> None:
        self._factory = token_factory or (lambda: secrets.token_urlsafe(16))
        self._path_to_id: dict[str, str] = {}
        self._id_to_path: dict[str, str] = {}
        self._generation = 0
        self._allocation = 0

    def for_path(self, path: str) -> str:
        found = self._path_to_id.get(path)
        if found is not None:
            return found
        while True:
            random_part = self._factory()
            if isinstance(random_part, str) and 8 <= len(random_part) <= 64 and random_part.isascii():
                break
        self._allocation += 1
        # The non-secret suffix prevents accidental factory reuse from making an
        # identifier from an invalidated station valid again.  It contains no
        # object-path data; the random prefix remains the opaque component.
        suffix = f".{self._generation:x}.{self._allocation:x}"
        token = random_part[:64 - len(suffix)] + suffix
        self._path_to_id[path] = token
        self._id_to_path[token] = path
        return token

    def path_for(self, token: str) -> str | None:
        return self._id_to_path.get(token)

    def retain(self, paths: set[str]) -> None:
        for path in tuple(self._path_to_id):
            if path not in paths:
                token = self._path_to_id.pop(path)
                self._id_to_path.pop(token, None)

    def clear(self) -> None:
        self._path_to_id.clear()
        self._id_to_path.clear()
        self._generation += 1
        self._allocation = 0

    invalidate = clear


@dataclass(frozen=True)
class NetworkView:
    path: str
    name: str
    kind: str
    connected: bool
    known_path: str | None
    autoconnect: bool
    strength: int


@dataclass(frozen=True)
class StateView:
    available: bool
    station_path: str | None = None
    powered: bool = False
    scanning: bool = False
    station_state: str = "disconnected"
    connected_path: str | None = None
    networks: tuple[NetworkView, ...] = ()
    owner_generation: int = 0


class Backend(Protocol):
    def set_refresh_callback(self, callback: Callable[[], None]) -> None: ...
    def get_view(self) -> StateView: ...
    def scan(self, station: str, ok: Callable[[], None], error: Callable[[str], None]) -> None: ...
    def power(self, station: str, enabled: bool, ok: Callable[[], None], error: Callable[[str], None]) -> None: ...
    def disconnect(self, station: str, ok: Callable[[], None], error: Callable[[str], None]) -> None: ...
    def connect(self, station: str, path: str, passphrase: str | None, ok: Callable[[], None], error: Callable[[str], None]) -> None: ...
    def forget(self, known_path: str, ok: Callable[[], None], error: Callable[[str], None]) -> None: ...
    def autoconnect(self, known_path: str, enabled: bool, ok: Callable[[], None], error: Callable[[str], None]) -> None: ...
    def cancel(self) -> bool: ...
    def close(self) -> None: ...


class Bridge:
    """Validate protocol input and expose only redacted state."""

    def __init__(
        self,
        backend: Backend,
        emit: Callable[[dict[str, Any]], None],
        ids: OpaqueIds | None = None,
        debounce: Callable[[Callable[[], None]], None] | None = None,
    ) -> None:
        self.backend = backend
        self.emit = emit
        self.ids = ids or OpaqueIds()
        self._id_station: dict[str, str] = {}
        self._selected_station: str | None = None
        self._owner_generation: int | None = None
        self._debounce = debounce or (lambda callback: callback())
        self._refresh_queued = False
        backend.set_refresh_callback(self.request_refresh)

    def request_refresh(self) -> None:
        if self._refresh_queued:
            return
        self._refresh_queued = True

        def refresh() -> None:
            self._refresh_queued = False
            self.send_snapshot()

        self._debounce(refresh)

    def _clear_ids(self) -> None:
        self.ids.clear()
        self._id_station.clear()
        self._selected_station = None

    def _state(self) -> tuple[StateView, dict[str, NetworkView]]:
        view = self.backend.get_view()
        if self._owner_generation != view.owner_generation:
            self._clear_ids()
            self._owner_generation = view.owner_generation
        station = view.station_path if view.available else None
        if station is None:
            self._clear_ids()
            return view, {}
        if self._selected_station != station:
            self._clear_ids()
            self._selected_station = station
        networks = view.networks[:MAX_NETWORKS]
        self.ids.retain({network.path for network in networks})
        self._id_station.clear()
        indexed: dict[str, NetworkView] = {}
        for network in networks:
            token = self.ids.for_path(network.path)
            self._id_station[token] = station
            indexed[token] = network
        return view, indexed

    def send_snapshot(self, seq: int | None = None) -> None:
        try:
            view, indexed = self._state()
        except Exception:
            self._clear_ids()
            self.emit(self._unavailable_snapshot(seq, "failed"))
            return
        event: dict[str, Any] = {
            "event": "snapshot",
            "status": "ok",
            "code": "ok",
            "available": bool(view.available),
            "powered": bool(view.powered) if view.available else False,
            "scanning": bool(view.scanning) if view.available else False,
            "stationState": view.station_state if view.station_state in STATION_STATES else "disconnected",
            "connectedId": None,
            "networks": [],
        }
        if seq is not None:
            event["seq"] = seq
        if view.available:
            connected_id = next(
                (token for token, network in indexed.items() if network.path == view.connected_path),
                None,
            )
            if connected_id is not None:
                event["connectedId"] = connected_id
            for token, network in indexed.items():
                event["networks"].append(
                    {
                        "id": token,
                        "name": sanitize_ssid(network.name),
                        "type": network.kind if network.kind in NETWORK_TYPES else "unknown",
                        "connected": bool(network.connected),
                        "known": network.known_path is not None,
                        "autoconnect": bool(network.autoconnect) if network.known_path else False,
                        "signal": signal_bucket(network.strength),
                    }
                )
        self.emit(event)

    @staticmethod
    def _unavailable_snapshot(seq: int | None, code: str) -> dict[str, Any]:
        result: dict[str, Any] = {
            "event": "snapshot", "status": "error", "code": code,
            "available": False, "powered": False, "scanning": False,
            "stationState": "disconnected", "connectedId": None, "networks": [],
        }
        if seq is not None:
            result["seq"] = seq
        return result

    def _result(self, command: str, code: str, seq: int | None) -> None:
        result: dict[str, Any] = {
            "event": "result", "command": command,
            "status": "ok" if code == "ok" else "error", "code": code,
        }
        if seq is not None:
            result["seq"] = seq
        self.emit(result)

    def _callbacks(self, command: str, seq: int | None) -> tuple[Callable[[], None], Callable[[str], None]]:
        done = False

        def finish(code: str) -> None:
            nonlocal done
            if done:
                return
            done = True
            self._result(command, code, seq)
            self.request_refresh()

        def succeeded() -> None:
            finish("ok")

        def failed(code: str) -> None:
            allowed = set(ERROR_CODES.values()) | {
                "canceled", "stale_id", "secret_required", "unavailable"
            }
            if code in allowed:
                finish(code)
            else:
                finish("failed")

        return succeeded, failed

    @staticmethod
    def _validate(message: Any) -> tuple[str, int | None, str | None]:
        if not isinstance(message, dict) or not message or not all(isinstance(key, str) for key in message):
            return "", None, "invalid_request"
        seq = message.get("seq")
        if seq is not None and (isinstance(seq, bool) or not isinstance(seq, int) or not 0 <= seq <= MAX_SEQ):
            return "", None, "invalid_request"
        command = message.get("command")
        if not isinstance(command, str) or command not in {
            "snapshot", "scan", "power", "disconnect", "connect", "forget", "autoconnect", "cancel"
        }:
            return "", seq, "invalid_request"
        fields = {
            "snapshot": {"command", "seq"}, "scan": {"command", "seq"},
            "power": {"command", "seq", "enabled"}, "disconnect": {"command", "seq"},
            "connect": {"command", "seq", "id", "passphrase"},
            "forget": {"command", "seq", "id"},
            "autoconnect": {"command", "seq", "id", "enabled"},
            "cancel": {"command", "seq"},
        }[command]
        if set(message) - fields:
            return command, seq, "invalid_request"
        if command in {"power", "autoconnect"} and not isinstance(message.get("enabled"), bool):
            return command, seq, "invalid_request"
        if command in {"connect", "forget", "autoconnect"}:
            token = message.get("id")
            if not isinstance(token, str) or not 8 <= len(token) <= 64 or not token.isascii():
                return command, seq, "invalid_request"
        if command == "connect" and "passphrase" in message:
            phrase = message["passphrase"]
            if (
                not isinstance(phrase, str)
                or not 8 <= len(phrase) <= 63
                or any(ord(char) < 0x20 or ord(char) > 0x7E for char in phrase)
            ):
                return command, seq, "invalid_request"
        return command, seq, None

    def handle(self, message: Any) -> None:
        command, seq, invalid = self._validate(message)
        if invalid:
            self._result(command or "invalid", invalid, seq)
            return
        if command == "snapshot":
            self.send_snapshot(seq)
            return
        try:
            view, indexed = self._state()  # fresh view before every mutation
        except Exception:
            self._clear_ids()
            self._result(command, "failed", seq)
            return
        if not view.available or view.station_path is None:
            self._result(command, "unavailable", seq)
            return
        ok, error = self._callbacks(command, seq)
        try:
            if command == "scan":
                self.backend.scan(view.station_path, ok, error)
            elif command == "power":
                self.backend.power(view.station_path, message["enabled"], ok, error)
            elif command == "disconnect":
                self.backend.disconnect(view.station_path, ok, error)
            elif command == "cancel":
                self.backend.cancel()
                self._result(command, "ok", seq)
                self.request_refresh()
            else:
                network = indexed.get(message["id"])
                if (network is None or self.ids.path_for(message["id"]) != network.path
                        or self._id_station.get(message["id"]) != view.station_path):
                    self._result(command, "stale_id", seq)
                    return
                if command == "connect":
                    phrase = message.get("passphrase")
                    if network.kind in {"8021x", "wep"} or network.kind not in {"open", "psk"}:
                        self._result(command, "unsupported", seq)
                    elif network.kind == "psk" and network.known_path is None and phrase is None:
                        self._result(command, "secret_required", seq)
                    elif (network.kind == "open" or network.known_path is not None) and phrase is not None:
                        self._result(command, "invalid_request", seq)
                    else:
                        self.backend.connect(view.station_path, network.path, phrase, ok, error)
                elif network.known_path is None:
                    self._result(command, "stale_id", seq)
                elif command == "forget":
                    self.backend.forget(network.known_path, ok, error)
                else:
                    self.backend.autoconnect(network.known_path, message["enabled"], ok, error)
        except Exception:
            error("failed")


class OneUseAgent:
    """In-memory one-target secret holder used by the exported D-Bus agent."""

    def __init__(self, target: str, passphrase: str, canceled: Callable[[], None] | None = None) -> None:
        self._target = target
        self._secret: str | None = passphrase
        self._canceled = canceled or (lambda: None)

    @property
    def has_secret(self) -> bool:
        return self._secret is not None

    def request_passphrase(self, target: str) -> str:
        if target != self._target or self._secret is None:
            raise AgentCanceled()
        secret = self._secret
        self._secret = None
        return secret

    def request_private_key_passphrase(self, *_args: Any) -> None:
        raise AgentCanceled()

    def request_user_name_and_password(self, *_args: Any) -> None:
        raise AgentCanceled()

    def request_user_password(self, *_args: Any) -> None:
        raise AgentCanceled()

    def reject(self, *_args: Any) -> None:
        raise AgentCanceled()

    def cancel(self, *_args: Any) -> None:
        self.clear()
        self._canceled()

    def release(self) -> None:
        self.clear()
        self._canceled()

    def clear(self) -> None:
        self._secret = None
        self._target = ""


class AgentCanceled(Exception):
    pass


class FixtureBackend:
    """Deterministic no-bus backend for UI and protocol tests."""

    def __init__(self) -> None:
        self.refresh: Callable[[], None] = lambda: None
        self.powered = True
        self.scanning = False
        self.state = "disconnected"
        self.connected: str | None = None
        self.pending = False
        self.items: list[dict[str, Any]] = [
            {"path": "/fixture/open", "name": "Open Network", "kind": "open", "known": None, "auto": False, "strength": -4200},
            {"path": "/fixture/saved", "name": "Saved Network", "kind": "psk", "known": "/fixture/known/saved", "auto": True, "strength": -6100},
            {"path": "/fixture/secure", "name": "Secure Network", "kind": "psk", "known": None, "auto": False, "strength": -7300},
            {"path": "/fixture/enterprise", "name": "Enterprise Network", "kind": "8021x", "known": None, "auto": False, "strength": -8700},
        ]

    def set_refresh_callback(self, callback: Callable[[], None]) -> None: self.refresh = callback

    def get_view(self) -> StateView:
        networks = tuple(NetworkView(i["path"], i["name"], i["kind"], i["path"] == self.connected, i["known"], i["auto"], i["strength"]) for i in self.items[:MAX_NETWORKS])
        return StateView(True, "/fixture/station", self.powered, self.scanning, self.state, self.connected, networks)

    def scan(self, _station: str, ok: Callable[[], None], _error: Callable[[str], None]) -> None:
        self.scanning = True; self.refresh(); self.scanning = False; ok()

    def power(self, _station: str, enabled: bool, ok: Callable[[], None], _error: Callable[[str], None]) -> None:
        self.powered = enabled
        if not enabled: self.connected = None; self.state = "disconnected"
        ok()

    def disconnect(self, _station: str, ok: Callable[[], None], error: Callable[[str], None]) -> None:
        if self.connected is None: error("not_connected"); return
        self.connected = None; self.state = "disconnected"; ok()

    def connect(self, _station: str, path: str, passphrase: str | None, ok: Callable[[], None], error: Callable[[str], None]) -> None:
        if self.pending: error("busy"); return
        self.pending = True
        # Deliberately never retain or emit passphrase.
        passphrase = None
        self.connected = path; self.state = "connected"; self.pending = False; ok()

    def forget(self, known_path: str, ok: Callable[[], None], error: Callable[[str], None]) -> None:
        for item in self.items:
            if item["known"] == known_path:
                item["known"] = None; item["auto"] = False; ok(); return
        error("not_found")

    def autoconnect(self, known_path: str, enabled: bool, ok: Callable[[], None], error: Callable[[str], None]) -> None:
        for item in self.items:
            if item["known"] == known_path:
                item["auto"] = enabled; ok(); return
        error("not_found")

    def cancel(self) -> bool:
        was_pending = self.pending; self.pending = False; return was_pending

    def close(self) -> None: self.pending = False


class IwdBackend:
    """dbus-python/GLib backend.  It never accesses privacy-sensitive keys."""

    def __init__(self, bus: Any, glib: Any, dbus_module: Any) -> None:
        self.bus, self.glib, self.dbus = bus, glib, dbus_module
        self.refresh: Callable[[], None] = lambda: None
        self.pending: dict[str, Any] | None = None
        self.iwd_available = True
        self.owner_generation = 0
        self.receivers: list[tuple[Callable[..., None], dict[str, Any]]] = []
        self._subscribe()

    def set_refresh_callback(self, callback: Callable[[], None]) -> None: self.refresh = callback

    def _manager(self) -> Any:
        return self.dbus.Interface(self.bus.get_object(IWD, "/"), OBJMGR)

    def _objects(self) -> dict[Any, Any]:
        return self._manager().GetManagedObjects()

    @staticmethod
    def _selected(objects: dict[Any, Any]) -> str | None:
        candidates = [str(path) for path, interfaces in objects.items() if STATION in interfaces]
        return min(candidates) if candidates else None

    def get_view(self) -> StateView:
        if not getattr(self, "iwd_available", True):
            return StateView(False, owner_generation=self.owner_generation)
        objects = self._objects()
        station = self._selected(objects)
        if station is None:
            return StateView(False, owner_generation=self.owner_generation)
        interfaces = objects.get(self.dbus.ObjectPath(station), objects.get(station, {}))
        station_props = interfaces.get(STATION, {})
        device_props = interfaces.get(DEVICE, {})
        ordered = self.dbus.Interface(self.bus.get_object(IWD, station), STATION).GetOrderedNetworks()
        entries: list[NetworkView] = []
        for network_path, strength in list(ordered)[:MAX_NETWORKS]:
            path = str(network_path)
            network_ifaces = objects.get(network_path, objects.get(path, {}))
            props = network_ifaces.get(NETWORK, {})
            known_value = props.get("KnownNetwork")
            candidate_known = str(known_value) if known_value is not None else None
            known_ifaces = objects.get(known_value, objects.get(candidate_known, {})) if known_value is not None else {}
            known_path = candidate_known if KNOWN in known_ifaces else None
            auto = bool(known_ifaces.get(KNOWN, {}).get("AutoConnect", False)) if known_path else False
            entries.append(NetworkView(
                path, str(props.get("Name", "")), str(props.get("Type", "unknown")),
                bool(props.get("Connected", False)), known_path, auto, int(strength),
            ))
        connected_value = station_props.get("ConnectedNetwork")
        state = str(station_props.get("State", "disconnected"))
        return StateView(
            True, station, bool(device_props.get("Powered", False)),
            bool(station_props.get("Scanning", False)),
            state if state in STATION_STATES else "disconnected",
            str(connected_value) if connected_value is not None else None, tuple(entries),
            self.owner_generation,
        )

    def _subscribe(self) -> None:
        def changed(interface: Any, _changed: Any, _invalid: Any, **_kw: Any) -> None:
            if str(interface) in {STATION, NETWORK, KNOWN, DEVICE}:
                self.refresh()

        def interfaces(_path: Any, values: Any, **_kw: Any) -> None:
            if any(str(key) in {STATION, NETWORK, KNOWN, DEVICE} for key in values):
                self.refresh()

        def owner_changed(_name: Any, _old_owner: Any, new_owner: Any, **_kw: Any) -> None:
            self.owner_generation = getattr(self, "owner_generation", 0) + 1
            self.iwd_available = bool(str(new_owner))
            if not self.iwd_available:
                op = self.pending
                if op is not None:
                    self._finish_connect(op, "unavailable")
            self.refresh()

        specs = [
            (changed, {"signal_name": "PropertiesChanged", "dbus_interface": PROPS, "bus_name": IWD}),
            (interfaces, {"signal_name": "InterfacesAdded", "dbus_interface": OBJMGR, "bus_name": IWD}),
            (interfaces, {"signal_name": "InterfacesRemoved", "dbus_interface": OBJMGR, "bus_name": IWD}),
            (owner_changed, {
                "signal_name": "NameOwnerChanged", "dbus_interface": DBUS,
                "bus_name": DBUS, "arg0": IWD,
            }),
        ]
        for callback, kwargs in specs:
            self.bus.add_signal_receiver(callback, **kwargs)
            self.receivers.append((callback, kwargs))

    def _call(self, path: str, interface: str, method: str, args: tuple[Any, ...], ok: Callable[[], None], error: Callable[[str], None]) -> None:
        try:
            proxy = self.dbus.Interface(self.bus.get_object(IWD, path), interface)

            def replied(*_args: Any) -> None:
                ok()

            def failed(exc: Any) -> None:
                error(map_dbus_error(exc))

            getattr(proxy, method)(*args, reply_handler=replied, error_handler=failed)
        except Exception as exc:
            error(map_dbus_error(exc))

    def scan(self, station: str, ok: Callable[[], None], error: Callable[[str], None]) -> None:
        self._call(station, STATION, "Scan", (), ok, error)

    def power(self, station: str, enabled: bool, ok: Callable[[], None], error: Callable[[str], None]) -> None:
        self._call(station, PROPS, "Set", (DEVICE, "Powered", self.dbus.Boolean(enabled)), ok, error)

    def disconnect(self, station: str, ok: Callable[[], None], error: Callable[[str], None]) -> None:
        self._call(station, STATION, "Disconnect", (), ok, error)

    def forget(self, known_path: str, ok: Callable[[], None], error: Callable[[str], None]) -> None:
        self._call(known_path, KNOWN, "Forget", (), ok, error)

    def autoconnect(self, known_path: str, enabled: bool, ok: Callable[[], None], error: Callable[[str], None]) -> None:
        self._call(known_path, PROPS, "Set", (KNOWN, "AutoConnect", self.dbus.Boolean(enabled)), ok, error)

    def connect(
        self,
        station: str,
        path: str,
        passphrase: str | None,
        ok: Callable[[], None],
        error: Callable[[str], None],
    ) -> None:
        if self.pending is not None:
            error("busy")
            return
        op: dict[str, Any] = {
            "station": station,
            "path": path,
            "ok": ok,
            "error": error,
            "deadline": 0,
            "aborting": False,
            "abort_code": None,
            "agent_object": None,
            "agent_path": None,
            "registration_state": "none",
            "connect_started": False,
            "connect_state": "none",
            "speculative_disconnect_started": False,
            "post_success_disconnect_state": "none",
        }
        self.pending = op
        try:
            def deadline() -> bool:
                self._begin_abort(op, "timeout")
                return False

            op["deadline"] = self.glib.timeout_add_seconds(CONNECT_TIMEOUT, deadline)
            if passphrase is None:
                self._start_connect(op)
                return

            def agent_canceled() -> None:
                self._begin_abort(op, "canceled")

            core = OneUseAgent(path, passphrase, agent_canceled)
            agent_path = "/org/quickshell/IwdAgent/" + secrets.token_hex(16)
            op["agent_path"] = agent_path
            op["agent_object"] = _make_dbus_agent(self.dbus, self.bus, agent_path, core)
            manager = self.dbus.Interface(
                self.bus.get_object(IWD, "/net/connman/iwd"), AGENT_MANAGER
            )

            def registered(*_args: Any) -> None:
                if self.pending is not op:
                    self._unregister_path(agent_path)
                    return
                if op["registration_state"] != "pending":
                    return
                op["registration_state"] = "registered"
                if op["aborting"]:
                    # Registration itself is now terminal.  Do not start Connect;
                    # unregister the exact agent whose registration just won.
                    self._unregister_path(agent_path)
                    op["registration_state"] = "unregistering"
                    self._finish_connect(op, op["abort_code"])
                    return
                self._start_connect(op)

            def register_error(exc: Any) -> None:
                if self.pending is not op or op["registration_state"] != "pending":
                    return
                op["registration_state"] = "error"
                if op["aborting"]:
                    self._finish_connect(op, op["abort_code"])
                    return
                self._finish_connect(op, map_dbus_error(exc))

            op["registration_state"] = "pending"
            manager.RegisterAgent(
                self.dbus.ObjectPath(agent_path),
                reply_handler=registered,
                error_handler=register_error,
                timeout=REGISTER_AGENT_DBUS_TIMEOUT,
            )
        except Exception as exc:
            if self.pending is op:
                self._finish_connect(op, map_dbus_error(exc))

    def _start_connect(self, op: dict[str, Any]) -> None:
        if self.pending is not op or op["aborting"]:
            return
        try:
            proxy = self.dbus.Interface(self.bus.get_object(IWD, op["path"]), NETWORK)

            def connected(*_args: Any) -> None:
                if self.pending is not op or op["connect_state"] != "pending":
                    return
                op["connect_state"] = "success"
                if op["aborting"]:
                    self._queue_post_success_disconnect(op)
                    return
                self._finish_connect(op, "ok")

            def connect_error(exc: Any) -> None:
                if self.pending is not op or op["connect_state"] != "pending":
                    return
                op["connect_state"] = "error"
                if op["aborting"]:
                    self._finish_connect(op, op["abort_code"])
                    return
                self._finish_connect(op, map_dbus_error(exc))

            # Set this immediately before making the async call: once true, no
            # abort path may release the operation before this call's callback.
            op["connect_started"] = True
            op["connect_state"] = "pending"
            proxy.Connect(
                reply_handler=connected,
                error_handler=connect_error,
                timeout=CONNECT_DBUS_TIMEOUT,
            )
        except Exception as exc:
            if self.pending is op:
                op["connect_state"] = "error"
                if op["aborting"]:
                    self._finish_connect(op, op["abort_code"])
                else:
                    self._finish_connect(op, map_dbus_error(exc))

    def _remove_source(self, op: dict[str, Any], key: str) -> None:
        source = op.get(key, 0)
        op[key] = 0
        if not source:
            return
        try:
            self.glib.source_remove(source)
        except Exception:
            pass

    def _unregister_path(self, path: str | None) -> None:
        if path is None:
            return
        try:
            manager = self.dbus.Interface(
                self.bus.get_object(IWD, "/net/connman/iwd"), AGENT_MANAGER
            )

            def ignored_reply(*_args: Any) -> None:
                return None

            def ignored_error(_exc: Any) -> None:
                return None

            manager.UnregisterAgent(
                self.dbus.ObjectPath(path),
                reply_handler=ignored_reply,
                error_handler=ignored_error,
            )
        except Exception:
            pass

    def _clear_agent(self, op: dict[str, Any], unregister: bool) -> None:
        obj = op.get("agent_object")
        path = op.get("agent_path")
        op["agent_object"] = None
        if obj is not None:
            obj.clear()
        if unregister:
            self._unregister_path(path)
        if obj is not None:
            try:
                obj.remove_from_connection()
            except Exception:
                pass

    def _finish_connect(self, op: dict[str, Any], code: str) -> None:
        if self.pending is not op:
            return
        self.pending = None
        self._remove_source(op, "deadline")
        self._clear_agent(op, op.get("registration_state") in {"registered"})
        if code == "ok":
            op["ok"]()
        else:
            op["error"](code)

    def _queue_speculative_disconnect(self, op: dict[str, Any]) -> None:
        """Try to interrupt Connect, but never treat this callback as terminal."""
        if (self.pending is not op or not op["aborting"]
                or not op["connect_started"] or op["speculative_disconnect_started"]):
            return
        op["speculative_disconnect_started"] = True
        try:
            proxy = self.dbus.Interface(
                self.bus.get_object(IWD, op["station"]), STATION
            )

            def refreshed(*_args: Any) -> None:
                if self.pending is op and op["aborting"]:
                    self.refresh()

            proxy.Disconnect(
                reply_handler=refreshed,
                error_handler=refreshed,
                timeout=DISCONNECT_DBUS_TIMEOUT,
            )
        except Exception:
            if self.pending is op and op["aborting"]:
                self.refresh()

    def _queue_post_success_disconnect(self, op: dict[str, Any]) -> None:
        """Disconnect after an aborted Connect succeeded; its callback is terminal."""
        if (self.pending is not op or not op["aborting"]
                or op["post_success_disconnect_state"] != "none"):
            return
        op["post_success_disconnect_state"] = "pending"
        try:
            proxy = self.dbus.Interface(
                self.bus.get_object(IWD, op["station"]), STATION
            )

            def disconnected(*_args: Any) -> None:
                if (self.pending is op and op["aborting"]
                        and op["post_success_disconnect_state"] == "pending"):
                    op["post_success_disconnect_state"] = "terminal"
                    self._finish_connect(op, op["abort_code"])

            def disconnect_failed(exc: Any) -> None:
                if (self.pending is op and op["aborting"]
                        and op["post_success_disconnect_state"] == "pending"):
                    op["post_success_disconnect_state"] = "terminal"
                    code = map_dbus_error(exc)
                    self._finish_connect(op, op["abort_code"] if code == "not_connected" else "failed")

            proxy.Disconnect(
                reply_handler=disconnected,
                error_handler=disconnect_failed,
                timeout=DISCONNECT_DBUS_TIMEOUT,
            )
        except Exception:
            if self.pending is op and op["aborting"]:
                op["post_success_disconnect_state"] = "terminal"
                self._finish_connect(op, "failed")

    def _begin_abort(self, op: dict[str, Any], code: str) -> None:
        if self.pending is not op or op["aborting"]:
            return
        op["aborting"] = True
        op["abort_code"] = code
        self._remove_source(op, "deadline")
        # Always erase the secret immediately.  While RegisterAgent is pending,
        # retain the exported object until that exact registration call ends.
        if op.get("registration_state") == "pending":
            obj = op.get("agent_object")
            if obj is not None:
                obj.clear()
        else:
            was_registered = op.get("registration_state") == "registered"
            self._clear_agent(op, was_registered)
            if was_registered:
                op["registration_state"] = "unregistering"
        if op["connect_started"]:
            self._queue_speculative_disconnect(op)
        elif op.get("registration_state") != "pending":
            # There is no outstanding remote callback capable of starting a
            # connection, so cancellation can complete immediately.
            self._finish_connect(op, code)

    def cancel(self) -> bool:
        op = self.pending
        if op is None:
            return False
        self._begin_abort(op, "canceled")
        return True

    def close(self) -> None:
        op = self.pending
        if op is not None:
            self.pending = None
            self._remove_source(op, "deadline")
            op["aborting"] = True
            op["abort_code"] = "canceled"
            self._clear_agent(op, op.get("agent_path") is not None)
            try:
                # EOF/SIGTERM shutdown cannot run another async main-loop turn.
                # Make one bounded synchronous disconnect request for every
                # active operation, including one still registering its agent.
                proxy = self.dbus.Interface(
                    self.bus.get_object(IWD, op["station"]), STATION
                )
                proxy.Disconnect(timeout=CLOSE_DISCONNECT_TIMEOUT)
            except Exception:
                pass
        for callback, kwargs in self.receivers:
            try:
                self.bus.remove_signal_receiver(callback, **kwargs)
            except Exception:
                pass
        self.receivers.clear()

    def probe(self) -> dict[str, Any]:
        objects = self._objects()
        stations = [path for path, interfaces in objects.items() if STATION in interfaces]
        # Exercise the documented read-only ordered API, but retain no paths or values.
        for path in sorted(stations, key=str)[:51]:
            try: self.dbus.Interface(self.bus.get_object(IWD, path), STATION).GetOrderedNetworks()
            except Exception: pass
        counts = lambda interface: min(51, sum(1 for values in objects.values() if interface in values))
        return {
            "available": bool(stations),
            "stationCount": counts(STATION), "networkCount": counts(NETWORK), "knownCount": counts(KNOWN),
            "hasStationInterface": counts(STATION) > 0, "hasNetworkInterface": counts(NETWORK) > 0,
            "hasKnownNetworkInterface": counts(KNOWN) > 0, "hasDeviceInterface": counts(DEVICE) > 0,
        }


def _make_dbus_agent(dbus: Any, bus: Any, path: str, core: OneUseAgent) -> Any:
    class ExportedAgent(dbus.service.Object):
        def __init__(self) -> None: super().__init__(bus, path)
        def clear(self) -> None: core.clear()

        @dbus.service.method(AGENT, in_signature="o", out_signature="s")
        def RequestPassphrase(self, network: Any) -> str:
            try: return core.request_passphrase(str(network))
            except AgentCanceled: raise dbus.exceptions.DBusException("Canceled", name=CANCELED_ERROR)

        @dbus.service.method(AGENT, in_signature="o", out_signature="s")
        def RequestPrivateKeyPassphrase(self, network: Any) -> str:
            try: core.request_private_key_passphrase(str(network))
            except AgentCanceled: raise dbus.exceptions.DBusException("Canceled", name=CANCELED_ERROR)
            raise dbus.exceptions.DBusException("Canceled", name=CANCELED_ERROR)

        @dbus.service.method(AGENT, in_signature="o", out_signature="ss")
        def RequestUserNameAndPassword(self, network: Any) -> tuple[str, str]:
            try: core.request_user_name_and_password(str(network))
            except AgentCanceled: raise dbus.exceptions.DBusException("Canceled", name=CANCELED_ERROR)
            raise dbus.exceptions.DBusException("Canceled", name=CANCELED_ERROR)

        @dbus.service.method(AGENT, in_signature="os", out_signature="s")
        def RequestUserPassword(self, network: Any, user: Any) -> str:
            try: core.request_user_password(str(network), str(user))
            except AgentCanceled: raise dbus.exceptions.DBusException("Canceled", name=CANCELED_ERROR)
            raise dbus.exceptions.DBusException("Canceled", name=CANCELED_ERROR)

        @dbus.service.method(AGENT, in_signature="s", out_signature="", no_reply=True)
        def Cancel(self, _reason: Any) -> None: core.cancel()

        @dbus.service.method(AGENT, in_signature="", out_signature="", no_reply=True)
        def Release(self) -> None: core.release()

    return ExportedAgent()


def compact_emit(stream: Any) -> Callable[[dict[str, Any]], None]:
    def emit(value: dict[str, Any]) -> None:
        data = (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
        if hasattr(stream, "buffer"):
            stream.buffer.write(data); stream.buffer.flush()
        else:
            stream.write(data.decode("utf-8")); stream.flush()
    return emit


def process_line(raw: bytes, bridge: Bridge) -> None:
    if len(raw) > MAX_INPUT:
        bridge._result("invalid", "invalid_request", None)
        return

    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate")
            result[key] = value
        return result

    try:
        message = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
        bridge._result("invalid", "invalid_request", None)
        return
    bridge.handle(message)


class LineDrain:
    """Incrementally parse bounded JSON lines, including one final EOF line."""

    def __init__(self, bridge: Bridge) -> None:
        self.bridge = bridge
        self.buffer = bytearray()
        self.dropping = False
        self.finished = False

    def feed(self, chunk: bytes) -> None:
        if self.finished or not chunk:
            return
        for part in chunk.splitlines(keepends=True):
            has_newline = part.endswith(b"\n")
            if self.dropping:
                if has_newline:
                    self.dropping = False
                continue
            self.buffer.extend(part)
            payload_size = len(self.buffer) - (1 if has_newline else 0)
            if payload_size > MAX_INPUT:
                self.bridge._result("invalid", "invalid_request", None)
                self.buffer.clear()
                self.dropping = not has_newline
            elif has_newline:
                process_line(bytes(self.buffer[:-1]), self.bridge)
                self.buffer.clear()

    def finish(self) -> None:
        if self.finished:
            return
        self.finished = True
        if self.buffer and not self.dropping:
            process_line(bytes(self.buffer), self.bridge)
        self.buffer.clear()


def run_fixture(instream: Any = None, outstream: Any = None) -> int:
    instream = sys.stdin if instream is None else instream
    outstream = sys.stdout if outstream is None else outstream
    backend = FixtureBackend()
    bridge = Bridge(backend, compact_emit(outstream))
    source = instream.buffer if hasattr(instream, "buffer") else instream
    try:
        while True:
            raw = source.readline(MAX_INPUT + 2)
            if raw in (b"", ""): break
            if isinstance(raw, str): raw = raw.encode("utf-8")
            if len(raw) > MAX_INPUT + 1 or (len(raw) > MAX_INPUT and not raw.endswith(b"\n")):
                bridge._result("invalid", "invalid_request", None)
                while raw and not raw.endswith(b"\n"):
                    raw = source.readline(MAX_INPUT + 2)
                    if isinstance(raw, str): raw = raw.encode("utf-8")
                continue
            process_line(raw[:-1] if raw.endswith(b"\n") else raw, bridge)
    finally:
        backend.close()
    return 0


def _load_dbus() -> tuple[Any, Any, Any]:
    import dbus
    import dbus.mainloop.glib
    import dbus.service
    from gi.repository import GLib
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    return dbus, dbus.SystemBus(), GLib


def run_persistent() -> int:
    dbus, bus, glib = _load_dbus()
    backend = IwdBackend(bus, glib, dbus)
    loop = glib.MainLoop()
    output = compact_emit(sys.stdout)
    source_id = 0

    def debounce(callback: Callable[[], None]) -> None:
        def dispatch() -> bool:
            callback()
            return False

        glib.timeout_add(100, dispatch)

    bridge = Bridge(backend, output, debounce=debounce)
    drain = LineDrain(bridge)

    def readable(_fd: Any, condition: Any) -> bool:
        terminal = bool(condition & (glib.IO_HUP | glib.IO_ERR))
        while True:
            try:
                chunk = os.read(0, 4096)
            except BlockingIOError:
                return True
            except OSError:
                drain.finish()
                loop.quit()
                return False
            if not chunk:
                drain.finish()
                loop.quit()
                return False
            drain.feed(chunk)
            if not terminal:
                return True

    source_id = glib.io_add_watch(0, glib.IO_IN | glib.IO_HUP | glib.IO_ERR, readable)
    old_term = signal.getsignal(signal.SIGTERM)
    terminating = False

    def terminate(*_args: Any) -> None:
        nonlocal terminating
        terminating = True
        loop.quit()

    signal.signal(signal.SIGTERM, terminate)
    try:
        loop.run()
        if not terminating:
            drain.finish()
    finally:
        if source_id:
            try: glib.source_remove(source_id)
            except Exception: pass
        signal.signal(signal.SIGTERM, old_term)
        backend.close()
    return 0


def probe() -> int:
    result = {
        "available": False, "stationCount": 0, "networkCount": 0, "knownCount": 0,
        "hasStationInterface": False, "hasNetworkInterface": False,
        "hasKnownNetworkInterface": False, "hasDeviceInterface": False,
    }
    backend: IwdBackend | None = None
    try:
        dbus, bus, glib = _load_dbus()
        backend = IwdBackend(bus, glib, dbus)
        result = backend.probe()
    except Exception:
        pass
    finally:
        if backend is not None:
            try:
                backend.close()
            except Exception:
                pass
    compact_emit(sys.stdout)(result)
    return 0


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    try:
        if args == ["--fixture"]: return run_fixture()
        if args == ["--probe"]: return probe()
        if not args: return run_persistent()
        sys.stderr.write("IWD_BRIDGE_STARTUP_FAILED\n")
        return 2
    except Exception:
        sys.stderr.write("IWD_BRIDGE_FATAL\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
