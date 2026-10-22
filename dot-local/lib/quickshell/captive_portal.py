#!/usr/bin/env python3
"""Detect captive portals and temporarily prefer DHCP-provided DNS."""

from __future__ import annotations

import http.client
import json
import os
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from typing import Any, Callable
from urllib.parse import urljoin, urlsplit
from urllib.request import ProxyHandler, Request, build_opener

CHECK_URL = "http://connectivitycheck.gstatic.com/generate_204"
MAX_INPUT = 4096
MAX_URL = 2048
CHECK_TIMEOUT = 5
ONLINE_INTERVAL = 60
PROBLEM_INTERVAL = 12
DNS_HELPER = "/usr/local/libexec/quickshell-captive-portal-dns"
PKEXEC = "/usr/bin/pkexec"


def safe_url(value: Any, base: str | None = None) -> str | None:
    if not isinstance(value, str) or not value or len(value) > MAX_URL:
        return None
    if any(ord(char) < 0x20 or ord(char) == 0x7F for char in value):
        return None
    candidate = urljoin(base, value) if base else value
    try:
        parsed = urlsplit(candidate)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname:
            return None
        if parsed.username is not None or parsed.password is not None:
            return None
        _ = parsed.port
    except (TypeError, ValueError):
        return None
    return candidate


@dataclass(frozen=True)
class LinkState:
    connected: bool
    identity: str
    advertised_portal: str | None
    has_dhcp_dns: bool


def parse_link_state(raw: Any) -> LinkState:
    if not isinstance(raw, dict):
        return LinkState(False, "", None, False)
    operational = raw.get("OperationalState")
    ssid = raw.get("SSID") if isinstance(raw.get("SSID"), str) else ""
    connected = operational in {"routable", "degraded", "enslaved"} and bool(ssid)
    identity_parts = [ssid]
    for key in ("BSSID", "HardwareAddress"):
        value = raw.get(key)
        if isinstance(value, str) and value:
            identity_parts.append(value)
            break
    portal = safe_url(raw.get("CaptivePortal"))
    dns = raw.get("DNS") if isinstance(raw.get("DNS"), list) else []
    has_dhcp_dns = any(
        isinstance(item, dict)
        and isinstance(item.get("AddressString"), str)
        and str(item.get("ConfigSource", "")).startswith(("DHCP", "RouterAdvertisement"))
        for item in dns
    )
    return LinkState(connected, "\x1f".join(identity_parts), portal, has_dhcp_dns)


@dataclass(frozen=True)
class ProbeResult:
    state: str
    url: str | None = None


class NoRedirect(http.client.HTTPConnection):
    """Marker retained for tests and clear intent; probes use HTTPConnection directly."""


def probe(url: str = CHECK_URL, timeout: int = CHECK_TIMEOUT) -> ProbeResult:
    parsed = urlsplit(url)
    if parsed.scheme != "http" or not parsed.hostname:
        return ProbeResult("offline")
    port = parsed.port or 80
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query
    connection = http.client.HTTPConnection(parsed.hostname, port, timeout=timeout)
    try:
        connection.request(
            "GET",
            path,
            headers={
                "Host": parsed.netloc,
                "User-Agent": "quickshell-captive-portal/1",
                "Cache-Control": "no-cache",
                "Connection": "close",
            },
        )
        response = connection.getresponse()
        response.read(128)
        if response.status == 204:
            return ProbeResult("online")
        location = safe_url(response.getheader("Location"), url)
        if 300 <= response.status < 400 and location:
            return ProbeResult("captive", location)
        if 200 <= response.status < 400:
            return ProbeResult("captive", url)
        return ProbeResult("offline")
    except (OSError, http.client.HTTPException):
        return ProbeResult("offline")
    finally:
        connection.close()


def probe_capport(url: str, timeout: int = CHECK_TIMEOUT) -> ProbeResult:
    """Read a bounded RFC 8908 captive portal API response."""
    candidate = safe_url(url)
    if not candidate:
        return ProbeResult("offline")
    request = Request(candidate, headers={"Accept": "application/captive+json", "User-Agent": "quickshell-captive-portal/1"})
    try:
        with build_opener(ProxyHandler({})).open(request, timeout=timeout) as response:
            if response.status != 200:
                return ProbeResult("offline")
            data = response.read(16 * 1024 + 1)
            if len(data) > 16 * 1024:
                return ProbeResult("offline")
            payload = json.loads(data)
    except (OSError, ValueError):
        return ProbeResult("offline")
    if not isinstance(payload, dict) or not isinstance(payload.get("captive"), bool):
        return ProbeResult("offline")
    if payload["captive"]:
        portal_url = safe_url(payload.get("user-portal-url"))
        return ProbeResult("captive", portal_url) if portal_url else ProbeResult("offline")
    return ProbeResult("online")


def discover_wireless_interface(run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run) -> str | None:
    try:
        result = run(
            ["/usr/bin/networkctl", "list", "--json=short"],
            capture_output=True,
            text=True,
            timeout=4,
            check=False,
        )
        if result.returncode != 0 or len(result.stdout) > 512 * 1024:
            return None
        payload = json.loads(result.stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    interfaces = payload.get("Interfaces") if isinstance(payload, dict) else None
    if not isinstance(interfaces, list):
        return None
    wireless = [item for item in interfaces if isinstance(item, dict) and item.get("Type") == "wlan" and isinstance(item.get("Name"), str)]
    connected = next((item for item in wireless if item.get("SSID") and item.get("OperationalState") in {"routable", "degraded"}), None)
    selected = connected or (wireless[0] if wireless else None)
    if not selected:
        return None
    name = selected["Name"]
    if not name or len(name) > 32 or any(char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-" for char in name):
        return None
    return name


class PortalAssistant:
    def __init__(
        self,
        interface: str,
        emit: Callable[[dict[str, Any]], None],
        run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
        probe_fn: Callable[[], ProbeResult] = probe,
        capport_fn: Callable[[str], ProbeResult] = probe_capport,
    ) -> None:
        self.interface = interface
        self.emit = emit
        self.run = run
        self.probe_fn = probe_fn
        self.capport_fn = capport_fn
        self.identity = ""
        self.status = "disconnected"
        self.portal_url: str | None = None
        self.dns_override = False
        self.last_error = ""
        self._published: tuple[str, str | None, bool, str] | None = None
        self.browser: subprocess.Popen[Any] | None = None
        self.browser_profile: str | None = None
        self.force_check = True

    def switch_interface(self, interface: str) -> None:
        if interface == self.interface:
            return
        self.close_browser()
        self.set_dns_override(False, force=True)
        self.interface = interface
        self.identity = ""
        self.dns_override = False
        self.set_dns_override(False, force=True)
        self.publish("checking")

    def link_state(self) -> LinkState:
        try:
            result = self.run(
                ["/usr/bin/networkctl", "status", self.interface, "--json=short"],
                capture_output=True,
                text=True,
                timeout=4,
                check=False,
            )
            if result.returncode != 0 or len(result.stdout) > 256 * 1024:
                return LinkState(False, "", None, False)
            return parse_link_state(json.loads(result.stdout))
        except (OSError, ValueError, subprocess.SubprocessError):
            return LinkState(False, "", None, False)

    def publish(self, status: str, url: str | None = None, error: str = "") -> None:
        clean_url = safe_url(url) if url else None
        current = (status, clean_url, self.dns_override, error)
        changed = current != self._published
        self.status, self.portal_url, self.last_error = status, clean_url, error
        if changed:
            self._published = current
            self.emit(
                {
                    "event": "status",
                    "status": status,
                    "url": clean_url or "",
                    "dnsOverride": self.dns_override,
                    "error": error,
                }
            )

    def set_dns_override(self, enabled: bool, force: bool = False) -> bool:
        if enabled == self.dns_override and not force:
            return True
        action = "enable" if enabled else "disable"
        if not os.path.isfile(DNS_HELPER) or not os.access(DNS_HELPER, os.X_OK):
            return False
        try:
            result = self.run(
                [PKEXEC, DNS_HELPER, action, self.interface],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=15,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            return False
        if result.returncode != 0:
            return False
        self.dns_override = enabled
        return True

    def check(self) -> int:
        link = self.link_state()
        if not link.connected:
            self.close_browser()
            dns_ok = self.set_dns_override(False)
            self.identity = ""
            self.publish("disconnected", error="" if dns_ok else "Could not restore public DNS")
            return PROBLEM_INTERVAL

        new_connection = link.identity != self.identity
        if new_connection:
            self.close_browser()
            dns_ok = self.set_dns_override(False)
            self.identity = link.identity
            self.publish("checking", error="" if dns_ok else "Could not restore public DNS")

        result = self.probe_fn()
        if result.state == "online":
            self.close_browser()
            dns_ok = self.set_dns_override(False)
            self.publish("online", error="" if dns_ok else "Could not restore public DNS")
            return ONLINE_INTERVAL

        if result.state == "captive":
            dns_ok = not link.has_dhcp_dns or self.set_dns_override(True, force=True)
            self.publish("captive", result.url or CHECK_URL, "" if dns_ok else "Could not switch to the Wi-Fi DNS")
            return PROBLEM_INTERVAL

        dns_error = ""
        if link.has_dhcp_dns and not self.dns_override:
            if self.set_dns_override(True):
                time.sleep(0.35)
                result = self.probe_fn()
            else:
                dns_error = "Could not switch to the Wi-Fi DNS"

        if result.state == "online":
            self.close_browser()
            dns_ok = self.set_dns_override(False)
            self.publish("online", error="" if dns_ok else "Could not restore public DNS")
            return ONLINE_INTERVAL

        if result.state == "captive":
            self.publish("captive", result.url or CHECK_URL, dns_error)
            return PROBLEM_INTERVAL

        if link.advertised_portal:
            capport = self.capport_fn(link.advertised_portal)
            if capport.state == "captive" and capport.url:
                self.publish("captive", capport.url, dns_error)
                return PROBLEM_INTERVAL

        # DHCP DNS is only retained while a portal is confirmed. A normal
        # outage must not silently change the user's resolver preference.
        restored = self.set_dns_override(False)
        error = dns_error
        if not restored:
            error = "Could not restore public DNS"
        if not error:
            error = "No internet response"
        self.publish("offline", None, error)
        return PROBLEM_INTERVAL

    def open_portal(self) -> bool:
        url = safe_url(self.portal_url)
        if self.status != "captive" or not url:
            return False
        if self.browser and self.browser.poll() is None:
            return True
        browser = next((path for name in ("chromium", "google-chrome-stable", "google-chrome") if (path := shutil.which(name))), None)
        if not browser:
            self.publish("captive", url, "Chromium is not installed")
            return False
        runtime = os.environ.get("XDG_RUNTIME_DIR")
        if not runtime or not os.path.isdir(runtime):
            self.publish("captive", url, "Secure runtime directory is unavailable")
            return False
        profile = tempfile.mkdtemp(prefix="captive-portal-", dir=runtime)
        os.chmod(profile, 0o700)
        try:
            process = subprocess.Popen(
                [
                    browser,
                    "--app=" + url,
                    "--user-data-dir=" + profile,
                    "--no-first-run",
                    "--no-default-browser-check",
                    "--disable-sync",
                ],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError:
            shutil.rmtree(profile, ignore_errors=True)
            self.publish("captive", url, "Could not open the sign-in window")
            return False
        self.browser, self.browser_profile = process, profile
        threading.Thread(target=self._cleanup_browser, args=(process, profile), daemon=True).start()
        return True

    def _cleanup_browser(self, process: subprocess.Popen[Any], profile: str) -> None:
        try:
            process.wait()
        finally:
            shutil.rmtree(profile, ignore_errors=True)
            if self.browser is process:
                self.browser = None
                self.browser_profile = None

    def close_browser(self) -> None:
        process = self.browser
        profile = self.browser_profile
        if process and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=2)
                except (OSError, subprocess.TimeoutExpired):
                    pass
            except OSError:
                pass
        if profile:
            shutil.rmtree(profile, ignore_errors=True)
        if self.browser is process:
            self.browser = None
            self.browser_profile = None

    def close(self) -> None:
        self.close_browser()
        self.set_dns_override(False)


def write_event(message: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main() -> int:
    configured_interface = os.environ.get("CAPTIVE_PORTAL_INTERFACE", "")
    interface = configured_interface or discover_wireless_interface()
    if not interface or len(interface) > 32 or any(char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-" for char in interface):
        return 2
    assistant = PortalAssistant(interface, write_event)
    # Reconcile a route left by an earlier crash before checking this link.
    assistant.set_dns_override(False, force=True)
    next_check = 0.0

    def stop(_signum: int, _frame: Any) -> None:
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        while True:
            now = time.monotonic()
            if assistant.force_check or now >= next_check:
                assistant.force_check = False
                if not configured_interface:
                    active_interface = discover_wireless_interface()
                    if active_interface:
                        assistant.switch_interface(active_interface)
                interval = assistant.check()
                next_check = time.monotonic() + interval
            timeout = max(0.0, min(1.0, next_check - time.monotonic()))
            readable, _, _ = select.select([sys.stdin], [], [], timeout)
            if not readable:
                continue
            line = sys.stdin.readline(MAX_INPUT + 1)
            if not line:
                break
            if len(line) > MAX_INPUT or not line.endswith("\n"):
                continue
            try:
                message = json.loads(line)
            except ValueError:
                continue
            if not isinstance(message, dict) or set(message) != {"command"}:
                continue
            command = message.get("command")
            if command == "open":
                assistant.open_portal()
            elif command == "check":
                assistant.force_check = True
            elif command == "stop":
                break
    except KeyboardInterrupt:
        pass
    finally:
        assistant.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
