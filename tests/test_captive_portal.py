from __future__ import annotations

import importlib.util
import json
import pathlib
import subprocess
import sys
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "dot-local/lib/quickshell/captive_portal.py"
SPEC = importlib.util.spec_from_file_location("quickshell_captive_portal", MODULE_PATH)
assert SPEC and SPEC.loader
portal = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = portal
SPEC.loader.exec_module(portal)


class UrlTests(unittest.TestCase):
    def test_safe_url_accepts_http_and_https_without_credentials(self):
        self.assertEqual(portal.safe_url("http://example.com/login"), "http://example.com/login")
        self.assertEqual(portal.safe_url("/login", "http://example.com/check"), "http://example.com/login")
        self.assertIsNone(portal.safe_url("file:///etc/passwd"))
        self.assertIsNone(portal.safe_url("https://user:secret@example.com/"))
        self.assertIsNone(portal.safe_url("http://example.com/\nnext"))
        self.assertIsNone(portal.safe_url("http://example.com:bad/"))


class LinkStateTests(unittest.TestCase):
    def test_parses_connected_link_portal_and_dhcp_dns(self):
        state = portal.parse_link_state({
            "OperationalState": "routable",
            "SSID": "Cafe",
            "BSSID": "00:11:22:33:44:55",
            "CaptivePortal": "https://portal.example/login",
            "DNS": [{"AddressString": "10.0.0.1", "ConfigSource": "DHCPv4"}],
        })
        self.assertTrue(state.connected)
        self.assertEqual(state.identity, "Cafe\x1f00:11:22:33:44:55")
        self.assertEqual(state.advertised_portal, "https://portal.example/login")
        self.assertTrue(state.has_dhcp_dns)

    def test_rejects_untrusted_portal_url(self):
        state = portal.parse_link_state({
            "OperationalState": "routable",
            "SSID": "Cafe",
            "CaptivePortal": "javascript:alert(1)",
        })
        self.assertIsNone(state.advertised_portal)


class AssistantTests(unittest.TestCase):
    def setUp(self):
        self.events = []
        self.link = {
            "OperationalState": "routable",
            "SSID": "Cafe",
            "BSSID": "00:11:22:33:44:55",
            "DNS": [{"AddressString": "10.0.0.1", "ConfigSource": "DHCPv4"}],
        }
        self.commands = []

        def run(args, **kwargs):
            self.commands.append(args)
            if args[0] == "/usr/bin/networkctl":
                return subprocess.CompletedProcess(args, 0, json.dumps(self.link), "")
            return subprocess.CompletedProcess(args, 0, "", "")

        self.run = run

    @mock.patch.object(portal.os, "access", return_value=True)
    @mock.patch.object(portal.os.path, "isfile", return_value=True)
    @mock.patch.object(portal.time, "sleep")
    def test_failed_public_probe_uses_wifi_dns_and_detects_portal(self, _sleep, _isfile, _access):
        probes = iter([
            portal.ProbeResult("offline"),
            portal.ProbeResult("captive", "http://portal.example/login"),
        ])
        assistant = portal.PortalAssistant("wlan0", self.events.append, self.run, lambda: next(probes))

        assistant.check()

        self.assertEqual(assistant.status, "captive")
        self.assertTrue(assistant.dns_override)
        self.assertIn([portal.PKEXEC, portal.DNS_HELPER, "enable", "wlan0"], self.commands)
        self.assertEqual(self.events[-1]["url"], "http://portal.example/login")

    @mock.patch.object(portal.os, "access", return_value=True)
    @mock.patch.object(portal.os.path, "isfile", return_value=True)
    def test_online_probe_removes_temporary_dns_override(self, _isfile, _access):
        assistant = portal.PortalAssistant("wlan0", self.events.append, self.run, lambda: portal.ProbeResult("online"))
        assistant.identity = "Cafe\x1f00:11:22:33:44:55"
        assistant.dns_override = True
        assistant.status = "captive"

        assistant.check()

        self.assertEqual(assistant.status, "online")
        self.assertFalse(assistant.dns_override)
        self.assertIn([portal.PKEXEC, portal.DNS_HELPER, "disable", "wlan0"], self.commands)

    @mock.patch.object(portal.os, "access", return_value=True)
    @mock.patch.object(portal.os.path, "isfile", return_value=True)
    def test_disconnect_reverts_override(self, _isfile, _access):
        self.link = {"OperationalState": "off", "SSID": ""}
        assistant = portal.PortalAssistant("wlan0", self.events.append, self.run)
        assistant.dns_override = True

        assistant.check()

        self.assertEqual(assistant.status, "disconnected")
        self.assertFalse(assistant.dns_override)
        self.assertIn([portal.PKEXEC, portal.DNS_HELPER, "disable", "wlan0"], self.commands)

    def test_advertised_capport_api_must_confirm_captive_state(self):
        self.link["CaptivePortal"] = "https://portal.example/api"
        self.link["DNS"] = []
        assistant = portal.PortalAssistant(
            "wlan0",
            self.events.append,
            self.run,
            lambda: portal.ProbeResult("offline"),
            lambda url: portal.ProbeResult("captive", "https://portal.example/start"),
        )

        assistant.check()

        self.assertEqual(assistant.status, "captive")
        self.assertEqual(assistant.portal_url, "https://portal.example/start")
    @mock.patch.object(portal.os, "access", return_value=True)
    @mock.patch.object(portal.os.path, "isfile", return_value=True)
    @mock.patch.object(portal.time, "sleep")
    def test_plain_outage_does_not_keep_wifi_dns_override(self, _sleep, _isfile, _access):
        assistant = portal.PortalAssistant("wlan0", self.events.append, self.run, lambda: portal.ProbeResult("offline"))

        assistant.check()

        self.assertEqual(assistant.status, "offline")
        self.assertFalse(assistant.dns_override)
        self.assertIn([portal.PKEXEC, portal.DNS_HELPER, "enable", "wlan0"], self.commands)
        self.assertIn([portal.PKEXEC, portal.DNS_HELPER, "disable", "wlan0"], self.commands)


class DiscoveryTests(unittest.TestCase):
    def test_discovers_connected_predictably_named_wifi(self):
        payload = {"Interfaces": [
            {"Name": "eth0", "Type": "ether", "OperationalState": "routable"},
            {"Name": "wlp0s20f3", "Type": "wlan", "OperationalState": "routable", "SSID": "Cafe"},
        ]}
        run = lambda args, **kwargs: subprocess.CompletedProcess(args, 0, json.dumps(payload), "")
        self.assertEqual(portal.discover_wireless_interface(run), "wlp0s20f3")


class StaticIntegrationTests(unittest.TestCase):
    def test_quickshell_wires_service_prompt_and_menu(self):
        shell = (ROOT / "dot-config/quickshell/shell.qml").read_text()
        menu = (ROOT / "dot-config/quickshell/WifiMenu.qml").read_text()
        self.assertIn("property CaptivePortalService captivePortalService", shell)
        self.assertIn("CaptivePortalPrompt", shell)
        self.assertIn("portalService: shell.captivePortalService", shell)
        self.assertIn('return "Sign-in required"', menu)
        self.assertIn("root.portalService.openPortal()", menu)

    def test_privileged_helper_is_narrow_and_policy_matches_exact_path(self):
        helper = (ROOT / "system/usr/local/libexec/quickshell-captive-portal-dns").read_text()
        policy = (ROOT / "system/usr/share/polkit-1/actions/com.trobrock.quickshell.captive-portal-dns.policy").read_text()
        self.assertIn("/sys/class/net/$1/wireless", helper)
        self.assertIn('/usr/bin/resolvectl domain "$interface"', helper)
        self.assertIn('/usr/bin/resolvectl revert "$interface"', helper)
        self.assertNotIn("eval", helper)
        self.assertIn("<allow_active>yes</allow_active>", policy)
        self.assertIn("/usr/local/libexec/quickshell-captive-portal-dns", policy)


if __name__ == "__main__":
    unittest.main()
