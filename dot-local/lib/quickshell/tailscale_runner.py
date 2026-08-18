#!/usr/bin/env python3
"""Small, allowlisted Tailscale command runner for Quickshell.

It deliberately accepts a tiny command language rather than an executable or
an argument vector from the UI.  Child output is relayed as it arrives, but is
bounded before it reaches the UI's collectors.
"""

from __future__ import annotations

import ipaddress
import json
import os
import re
import resource
import selectors
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Any, Callable, Sequence

TAILSCALE = "/usr/bin/tailscale"
PKEXEC = "/usr/bin/pkexec"

MIB = 1024 * 1024
STATUS_STDOUT_LIMIT = 2 * MIB
ACCOUNTS_STDOUT_LIMIT = 512 * 1024
EXIT_NODES_STDOUT_LIMIT = MIB
UP_STDOUT_LIMIT = 16 * 1024
STDERR_LIMIT = 4 * 1024
ACTION_STDOUT_LIMIT = 4 * 1024

READ_TIMEOUT = 15.0
ACTION_TIMEOUT = 45.0
SEND_TIMEOUT = 600.0
MAX_FILES = 32
MAX_PATH = 4096
OUTPUT_LIMIT_MESSAGE = b"OUTPUT_LIMIT\n"
REQUEST_ENV = "QUICKSHELL_TAILSCALE_REQUEST"
MAX_REQUEST_BYTES = 132 * 1024

_OPAQUE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:+/=\-@]{0,119}$")
_USER = re.compile(r"^[A-Za-z_][A-Za-z0-9._-]{0,31}$")
_DNS_LABEL = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")


@dataclass(frozen=True, eq=False)
class CommandSpec:
    argv: tuple[str, ...]
    stdout_limit: int
    stderr_limit: int
    timeout: float

    def __iter__(self):
        return iter(self.argv)

    def __len__(self) -> int:
        return len(self.argv)

    def __getitem__(self, index: int) -> str:
        return self.argv[index]

    def __eq__(self, other: object) -> bool:
        if isinstance(other, CommandSpec):
            return (self.argv, self.stdout_limit, self.stderr_limit, self.timeout) == (
                other.argv, other.stdout_limit, other.stderr_limit, other.timeout
            )
        if isinstance(other, (list, tuple)):
            return tuple(other) == self.argv
        return NotImplemented


@dataclass(frozen=True)
class RunResult:
    """Outcome from :func:`run_bounded`; output itself is streamed, not kept."""

    returncode: int
    timed_out: bool = False
    output_limited: bool = False


def validate_opaque_id(value: Any) -> bool:
    """Accept only the bounded opaque profile identifiers exposed by the UI."""
    return isinstance(value, str) and bool(_OPAQUE_ID.fullmatch(value))


def validate_user(value: Any) -> bool:
    """Validate the local operator name without accepting shell-like syntax."""
    return isinstance(value, str) and bool(_USER.fullmatch(value))


def validate_dns(value: Any) -> bool:
    """Accept a normal ASCII DNS name (with an optional final root dot)."""
    if not isinstance(value, str) or not value or len(value) > 253 or any(ord(c) > 127 for c in value):
        return False
    name = value[:-1] if value.endswith(".") else value
    if not name or len(name) > 253:
        return False
    return all(bool(_DNS_LABEL.fullmatch(label)) for label in name.split("."))


def validate_target(value: Any) -> bool:
    """Allow only a Tailscale IPv4/IPv6 address or a DNS target name."""
    if not isinstance(value, str) or not value or len(value) > 253:
        return False
    try:
        address = ipaddress.ip_address(value)
    except ValueError:
        return validate_dns(value)
    if isinstance(address, ipaddress.IPv4Address):
        return address in ipaddress.ip_network("100.64.0.0/10")
    return address in ipaddress.ip_network("fd7a:115c:a1e0::/48")


def validate_path(value: Any) -> bool:
    """A path is intentionally not resolved or stat'ed before handing it on."""
    return (
        isinstance(value, str)
        and 0 < len(value) <= MAX_PATH
        and value.startswith("/")
        and "\0" not in value
    )


def validate_paths(values: Any) -> bool:
    return isinstance(values, (list, tuple)) and 1 <= len(values) <= MAX_FILES and all(
        validate_path(value) for value in values
    )


def _spec(argv: Sequence[str], stdout_limit: int, timeout: float, stderr_limit: int = STDERR_LIMIT) -> CommandSpec:
    return CommandSpec(tuple(argv), stdout_limit, stderr_limit, timeout)


def request_from_environment(environ: Any) -> list[str]:
    if not hasattr(environ, "pop"):
        raise ValueError("invalid request")
    raw = environ.pop(REQUEST_ENV, "")
    if not isinstance(raw, str) or not raw or len(raw.encode("utf-8")) > MAX_REQUEST_BYTES:
        raise ValueError("invalid request")
    try:
        value = json.loads(raw)
    except (TypeError, ValueError):
        raise ValueError("invalid request") from None
    if not isinstance(value, list) or not value or not all(isinstance(item, str) for item in value):
        raise ValueError("invalid request")
    return value


def build_command(args: Sequence[str]) -> CommandSpec:
    """Build one literal command or raise ``ValueError`` for every other input."""
    if not isinstance(args, (list, tuple)) or not all(isinstance(arg, str) for arg in args):
        raise ValueError("invalid command")
    values = list(args)
    if values == ["status"]:
        return _spec((TAILSCALE, "status", "--json"), STATUS_STDOUT_LIMIT, READ_TIMEOUT)
    if values == ["accounts"]:
        return _spec((TAILSCALE, "switch", "--list", "--json"), ACCOUNTS_STDOUT_LIMIT, READ_TIMEOUT)
    if values == ["exit-nodes"]:
        return _spec((TAILSCALE, "exit-node", "list"), EXIT_NODES_STDOUT_LIMIT, READ_TIMEOUT)
    if values == ["up"]:
        return _spec((TAILSCALE, "up"), UP_STDOUT_LIMIT, ACTION_TIMEOUT)
    if values == ["down"]:
        return _spec((TAILSCALE, "down"), ACTION_STDOUT_LIMIT, ACTION_TIMEOUT)
    if len(values) == 2 and values[0] == "switch" and validate_opaque_id(values[1]):
        return _spec((TAILSCALE, "switch", values[1]), ACTION_STDOUT_LIMIT, ACTION_TIMEOUT)
    if len(values) == 2 and values[0] == "set-exit" and (values[1] == "" or validate_target(values[1])):
        return _spec((TAILSCALE, "set", "--exit-node=" + values[1]), ACTION_STDOUT_LIMIT, ACTION_TIMEOUT)
    if len(values) == 2 and values[0] == "authorize" and validate_user(values[1]):
        return _spec((PKEXEC, TAILSCALE, "set", "--operator=" + values[1]), ACTION_STDOUT_LIMIT, ACTION_TIMEOUT)
    if len(values) >= 3 and values[0] == "send" and validate_target(values[1]) and validate_paths(values[2:]):
        # The target is an operand, never an option.  Its colon is required by
        # tailscale file cp and is added only after target validation.
        return _spec(
            (TAILSCALE, "file", "cp", "--update-interval=0", "--", *values[2:], values[1] + ":"),
            ACTION_STDOUT_LIMIT,
            SEND_TIMEOUT,
        )
    raise ValueError("invalid command")


def core_dumps_disabled() -> bool:
    """Check all core-dump controls inherited by the helper."""
    try:
        soft, hard = resource.getrlimit(resource.RLIMIT_CORE)
        if soft != 0 or hard != 0:
            return False
        with open("/proc/self/coredump_filter", "r", encoding="ascii") as handle:
            return bool(re.fullmatch(r"0+\n?", handle.read()))
    except (OSError, ValueError, AttributeError):
        return False


def setup_core_protection() -> bool:
    """Lower core limits and verify Linux's coredump-filter fail-closed state."""
    try:
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        with open("/proc/self/coredump_filter", "w", encoding="ascii") as handle:
            handle.write("0\n")
    except (OSError, ValueError, AttributeError):
        return False
    return core_dumps_disabled()


def _as_binary_stream(stream: Any) -> Any:
    return getattr(stream, "buffer", stream)


def _write(stream: Any, data: bytes) -> None:
    if not data:
        return
    try:
        stream.write(data)
    except TypeError:
        stream.write(data.decode("utf-8", "replace"))
    try:
        stream.flush()
    except (AttributeError, OSError):
        pass


def _kill_group(process: Any) -> None:
    """Kill the session started for a child, including any descendants."""
    try:
        pid = int(process.pid)
        if pid > 0:
            try:
                os.killpg(pid, signal.SIGTERM)
            except OSError:
                pass
            try:
                os.killpg(pid, signal.SIGKILL)
            except OSError:
                pass
            return
    except (AttributeError, TypeError, ValueError):
        pass
    try:
        process.kill()
    except (AttributeError, OSError):
        pass


def _close_stream(selector: Any, stream: Any) -> None:
    try:
        selector.unregister(stream)
    except Exception:
        pass
    try:
        stream.close()
    except (AttributeError, OSError):
        pass


def run_bounded(
    command: CommandSpec | Sequence[str],
    stdout_limit: int | None = None,
    stderr_limit: int | None = None,
    timeout: float | None = None,
    *,
    popen_factory: Callable[..., Any] = subprocess.Popen,
    selector_factory: Callable[[], Any] = selectors.DefaultSelector,
    stdout: Any = None,
    stderr: Any = None,
    clock: Callable[[], float] = time.monotonic,
) -> RunResult:
    """Run a literal argv with bounded, incremental output and a hard deadline.

    Injection points are intentionally present for unit tests; production uses
    only ``subprocess.Popen`` with ``shell=False`` and a new process session.
    """
    if isinstance(command, CommandSpec):
        argv = command.argv
        stdout_limit = command.stdout_limit if stdout_limit is None else stdout_limit
        stderr_limit = command.stderr_limit if stderr_limit is None else stderr_limit
        timeout = command.timeout if timeout is None else timeout
    else:
        argv = tuple(command)
    if (not argv or not all(isinstance(item, str) for item in argv)
            or stdout_limit is None or stderr_limit is None or timeout is None
            or stdout_limit < 0 or stderr_limit < len(OUTPUT_LIMIT_MESSAGE) or timeout <= 0):
        raise ValueError("invalid bounded command")

    out = _as_binary_stream(sys.stdout if stdout is None else stdout)
    err = _as_binary_stream(sys.stderr if stderr is None else stderr)
    process: Any = None
    selector: Any = None
    old_handlers: list[tuple[int, Any]] = []
    terminated = False
    timed_out = False
    output_limited = False
    counts = {"stdout": 0, "stderr": 0}
    # Reserve the generic diagnostic so even a stderr flood cannot make the
    # parent collector exceed its advertised cap.
    child_limits = {"stdout": stdout_limit, "stderr": stderr_limit - len(OUTPUT_LIMIT_MESSAGE)}

    try:
        process = popen_factory(
            list(argv), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            shell=False, close_fds=True, start_new_session=True, bufsize=0,
        )
        if process.stdout is None or process.stderr is None:
            raise OSError("missing pipes")

        def on_signal(signum: int, _frame: Any) -> None:
            nonlocal terminated
            terminated = True
            _kill_group(process)
            raise SystemExit(128 + signum)

        for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
            try:
                old_handlers.append((signum, signal.signal(signum, on_signal)))
            except (ValueError, OSError):  # non-main test threads / restricted runtimes
                pass

        selector = selector_factory()
        selector.register(process.stdout, selectors.EVENT_READ, "stdout")
        selector.register(process.stderr, selectors.EVENT_READ, "stderr")
        open_streams = 2
        deadline = clock() + timeout
        while open_streams:
            remaining_time = deadline - clock()
            if remaining_time <= 0:
                timed_out = True
                terminated = True
                _kill_group(process)
                break
            events = selector.select(min(0.25, remaining_time))
            for key, _mask in events:
                stream = key.fileobj
                channel = key.data
                try:
                    chunk = os.read(stream.fileno(), 65536)
                except BlockingIOError:
                    continue
                except OSError:
                    chunk = b""
                if not chunk:
                    _close_stream(selector, stream)
                    open_streams -= 1
                    continue
                allowed = child_limits[channel] - counts[channel]
                if len(chunk) <= allowed:
                    _write(out if channel == "stdout" else err, chunk)
                    counts[channel] += len(chunk)
                    continue
                if allowed > 0:
                    _write(out if channel == "stdout" else err, chunk[:allowed])
                    counts[channel] += allowed
                output_limited = True
                terminated = True
                _kill_group(process)
                break
            if terminated:
                break
            # Once both pipes have closed the child has been fully drained.

        if timed_out:
            _write(err, b"TIMEOUT\n")
        elif output_limited:
            _write(err, OUTPUT_LIMIT_MESSAGE)
    except (OSError, ValueError):
        # Do not expose executable paths, process errors, or exception text.
        if process is None:
            _write(err, b"TAILSCALE_FAILED\n")
        terminated = True
        if process is not None:
            _kill_group(process)
    finally:
        if selector is not None:
            for stream in (getattr(process, "stdout", None), getattr(process, "stderr", None)):
                if stream is not None:
                    _close_stream(selector, stream)
            try:
                selector.close()
            except Exception:
                pass
        if process is not None:
            if terminated:
                _kill_group(process)
            try:
                returncode = process.wait(timeout=1)
            except TypeError:
                returncode = process.wait()
            except (subprocess.TimeoutExpired, OSError):
                _kill_group(process)
                returncode = 1
        else:
            returncode = 1
        for signum, previous in old_handlers:
            try:
                signal.signal(signum, previous)
            except (ValueError, OSError):
                pass

    if timed_out:
        return RunResult(124, timed_out=True)
    if output_limited:
        return RunResult(1, output_limited=True)
    return RunResult(int(returncode), False, False)


def main(args: Sequence[str] | None = None) -> int:
    if not setup_core_protection():
        _write(_as_binary_stream(sys.stderr), b"TAILSCALE_BRIDGE_STARTUP_FAILED\n")
        return 1
    try:
        values = list(sys.argv[1:] if args is None else args)
        if values == ["request"]:
            values = request_from_environment(os.environ)
        spec = build_command(values)
    except ValueError:
        _write(_as_binary_stream(sys.stderr), b"TAILSCALE_BRIDGE_INVALID\n")
        return 2
    try:
        return run_bounded(spec).returncode
    except Exception:
        # A bridge failure is intentionally generic; never include argv or a
        # subprocess exception, both of which may contain tailnet data.
        _write(_as_binary_stream(sys.stderr), b"TAILSCALE_FAILED\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
