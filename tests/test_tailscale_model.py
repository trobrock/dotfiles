from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULE = ROOT / "dot-config/quickshell/TailscaleModel.js"
NODE = shutil.which("node")


@unittest.skipIf(NODE is None, "node is required")
class TailscaleModelTests(unittest.TestCase):
    def node_eval(self, expression: str, data=None):
        script = (
            "const fs = require('fs');"
            f"const model = require({json.dumps(str(MODULE))});"
            "const data = JSON.parse(fs.readFileSync(0, 'utf8'));"
            f"const result = ({expression});"
            "process.stdout.write(JSON.stringify(result));"
        )
        result = subprocess.run(
            [NODE, "-e", script],
            input=json.dumps(data),
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertEqual(result.stderr, "")
        return json.loads(result.stdout or "null")

    def exit_table(self, rows):
        header = f"{'IP':<22}  {'HOSTNAME':<34}  {'COUNTRY':<18}  {'CITY':<18}  STATUS"
        lines = [header]
        for ip, host, country, city, status in rows:
            lines.append(f"{ip:<22}  {host:<34}  {country:<18}  {city:<18}  {status}")
        return "\n".join(lines)

    def test_sanitization_dns_ids_and_ip_validation(self):
        result = self.node_eval(
            "({"
            "cleanDns: model.cleanDnsName(data.dns),"
            "shortDns: model.shortDnsName(data.dns),"
            "display: model.displayHostName(data.host, data.dns),"
            "localhostDisplay: model.displayHostName('localhost', data.dns),"
            "ipv4: model.filterIPv4(data.ips4),"
            "ipv6: model.filterIPv6(data.ips6),"
            "goodId: model.normalizeOpaqueId(data.goodId),"
            "badId: model.normalizeOpaqueId(data.badId),"
            "linuxIcon: model.osIcon('linux'),"
            "unknownIcon: model.osIcon('plan9')"
            "})",
            {
                "dns": "Node.Example.TS.Net.\u202e",
                "host": "  Bad\u202e\u200b\x00\n Host   ",
                "ips4": [
                    "100.064.000.001",
                    "100.127.255.255",
                    "100.128.0.1",
                    "192.168.0.1",
                    "100.64.0.1",
                ],
                "ips6": [
                    "FD7A:115C:A1E0::1",
                    "fd7a:115c:a1e0:1::1",
                    "fd7a:115c:a1e1::1",
                    "fd7a:115c:a1e0::1",
                ],
                "goodId": "peer:Abc_123+/=@-",
                "badId": "bad id\t",
            },
        )
        self.assertEqual(result["cleanDns"], "node.example.ts.net")
        self.assertEqual(result["shortDns"], "node")
        self.assertEqual(result["display"], "Bad Host")
        self.assertEqual(result["localhostDisplay"], "node")
        self.assertEqual(result["ipv4"], ["100.64.0.1", "100.127.255.255"])
        self.assertEqual(
            result["ipv6"],
            [
                "fd7a:115c:a1e0:0:0:0:0:1",
                "fd7a:115c:a1e0:1:0:0:0:1",
            ],
        )
        self.assertEqual(result["goodId"], "peer:Abc_123+/=@-")
        self.assertEqual(result["badId"], "")
        self.assertEqual(result["linuxIcon"], "󰌽")
        self.assertEqual(result["unknownIcon"], "󰟀")

    def test_taildrop_capability_and_owner_fallback(self):
        result = self.node_eval(
            "({"
            "capMap: model.hasFileSharing({CapMap: {'https://tailscale.com/cap/file-sharing': []}}),"
            "caps: model.hasFileSharing({Capabilities: ['https://tailscale.com/cap/file-sharing']}),"
            "explicit: model.isTaildropTarget({TaildropTarget: 1, UserID: 'other'}, 'self'),"
            "fallbackSelf: model.isTaildropTarget({UserID: 'self'}, 'self'),"
            "fallbackOther: model.isTaildropTarget({UserID: 'other'}, 'self'),"
            "mullvadIcon: model.osIcon('mullvad')"
            "})"
        )
        self.assertTrue(result["capMap"])
        self.assertTrue(result["caps"])
        self.assertTrue(result["explicit"])
        self.assertTrue(result["fallbackSelf"])
        self.assertFalse(result["fallbackOther"])
        self.assertEqual(result["mullvadIcon"], "󰖂")

    def test_parse_status_caps_peers_sanitizes_and_filters(self):
        status = {
            "BackendState": "Running",
            "AuthURL": "javascript:alert(1)",
            "Self": {
                "HostName": "localhost",
                "DNSName": "Self.EXAMPLE.ts.net.",
                "TailscaleIPs": ["100.064.000.001", "192.168.0.9"],
                "UserID": "user-1",
                "Capabilities": ["https://tailscale.com/cap/file-sharing"],
            },
            "Peer": {},
        }
        for index in range(205):
            host = f"Peer {index}"
            if index == 0:
                host = "Peer\u202e\x00\n Name " + ("x" * 200)
            status["Peer"][f"peer{index:03d}"] = {
                "HostName": host,
                "DNSName": f"peer{index:03d}.example.ts.net.",
                "TailscaleIPs": [f"100.64.0.{(index % 250) + 1}", f"fd7a:115c:a1e0::{index + 1}"],
                "UserID": f"user-{index}",
                "Online": True,
                "OS": "linux" if index % 2 == 0 else "windows",
                "Tags": ["tag:alpha", "bad\x00tag"],
                "ExitNodeOption": index % 2 == 0,
            }
        status["Peer"]["bad id"] = {
            "ID": "bad id",
            "HostName": "Should Drop",
            "DNSName": "drop.example.ts.net",
            "TailscaleIPs": ["100.64.9.9"],
            "UserID": "user-x",
            "Online": True,
        }
        status["Peer"]["mullvad01"] = {
            "HostName": "se-sto-wg-001.mullvad.ts.net",
            "DNSName": "se-sto-wg-001.mullvad.ts.net",
            "TailscaleIPs": ["100.64.10.10"],
            "UserID": "user-m",
            "Online": True,
            "ExitNodeOption": True,
        }
        status["Peer"]["offline01"] = {
            "HostName": "Offline",
            "DNSName": "offline.example.ts.net",
            "TailscaleIPs": ["100.64.10.11"],
            "UserID": "user-o",
            "Online": False,
            "ExitNodeOption": True,
        }

        result = self.node_eval("model.parseStatus(data.raw)", {"raw": json.dumps(status)})
        self.assertTrue(result["ok"])
        self.assertFalse(result["unavailable"])
        self.assertTrue(result["running"])
        self.assertEqual(result["selfName"], "self")
        self.assertEqual(result["selfDnsName"], "self.example.ts.net")
        self.assertEqual(result["selfIp"], "100.64.0.1")
        self.assertEqual(result["selfUserId"], "user-1")
        self.assertTrue(result["fileSharing"])
        self.assertEqual(result["authUrl"], "")
        self.assertEqual(len(result["peers"]), 200)
        self.assertEqual(len(result["onlinePeers"]), 200)
        self.assertEqual(len(result["exitNodes"]), 100)
        self.assertFalse(any(peer["Mullvad"] for peer in result["peers"]))
        self.assertFalse(any(peer["id"] == "bad id" for peer in result["peers"]))
        self.assertFalse(any(peer["DisplayName"] == "Offline" for peer in result["peers"]))
        self.assertTrue(all(len(peer["DisplayName"]) <= 80 for peer in result["peers"]))
        self.assertIn(result["peers"][0]["OSIcon"], {"󰌽", "󰍲"})
        self.assertEqual(result["peers"][0]["Tags"], ["tag:alpha", "bad tag"])

    def test_parse_status_errors_and_login_url_validation_do_not_leak(self):
        valid = json.dumps({
            "BackendState": "NeedsLogin",
            "AuthURL": "https://login.tailscale.com/a/token_123",
            "Self": {},
            "Peer": {},
        })
        invalid_scheme = json.dumps({
            "BackendState": "NeedsLogin",
            "AuthURL": "javascript:alert(1)",
            "Self": {},
            "Peer": {},
        })
        invalid_space = json.dumps({
            "BackendState": "NeedsLogin",
            "AuthURL": "https://login.tailscale.com/a\nsecret",
            "Self": {},
            "Peer": {},
        })
        too_long = json.dumps({
            "BackendState": "NeedsLogin",
            "AuthURL": "https://login.tailscale.com/" + ("a" * 2050),
            "Self": {},
            "Peer": {},
        })
        secret = "NeverExposeThisSecret"

        result = self.node_eval(
            "({"
            "valid: model.parseStatus(data.valid).authUrl,"
            "invalidScheme: model.parseStatus(data.invalidScheme).authUrl,"
            "invalidSpace: model.parseStatus(data.invalidSpace).authUrl,"
            "tooLong: model.parseStatus(data.tooLong).authUrl,"
            "planValid: model.loginPlan(true, 'https://login.tailscale.com/a/token_123'),"
            "planInvalid: model.loginPlan(true, 'javascript:alert(1)'),"
            "foreignOrigin: model.validateAuthUrl('https://example.com/auth'),"
            "plainHttp: model.validateAuthUrl('http://login.tailscale.com/auth'),"
            "loginIp: model.validateAuthUrl('https://100.100.100.100/auth'),"
            "loginPort: model.validateAuthUrl('https://login.tailscale.com:443/a/token'),"
            "arbitraryPath: model.validateAuthUrl('https://login.tailscale.com/login'),"
            "queryRedirect: model.validateAuthUrl('https://login.tailscale.com/a/token?next=https://example.com'),"
            "malformed: model.parseStatus(data.malformed),"
            "oversized: model.parseStatus(data.oversized)"
            "})",
            {
                "valid": valid,
                "invalidScheme": invalid_scheme,
                "invalidSpace": invalid_space,
                "tooLong": too_long,
                "malformed": '{"secret":"' + secret,
                "oversized": "x" * (2 * 1024 * 1024 + 1),
            },
        )
        self.assertEqual(result["valid"], "https://login.tailscale.com/a/token_123")
        self.assertEqual(result["invalidScheme"], "")
        self.assertEqual(result["invalidSpace"], "")
        self.assertEqual(result["tooLong"], "")
        self.assertEqual(result["planValid"], {"authUrl": "https://login.tailscale.com/a/token_123", "command": []})
        self.assertEqual(result["planInvalid"], {"authUrl": "", "command": ["tailscale", "up"]})
        self.assertEqual(result["foreignOrigin"], "")
        self.assertEqual(result["plainHttp"], "")
        self.assertEqual(result["loginIp"], "")
        self.assertEqual(result["loginPort"], "")
        self.assertEqual(result["arbitraryPath"], "")
        self.assertEqual(result["queryRedirect"], "")
        self.assertFalse(result["malformed"]["ok"])
        self.assertTrue(result["malformed"]["unavailable"])
        self.assertFalse(result["oversized"]["ok"])
        self.assertTrue(result["oversized"]["unavailable"])
        encoded = json.dumps(result)
        self.assertNotIn(secret, encoded)
        self.assertNotIn("javascript:alert(1)", encoded)
        self.assertNotIn("https://login.tailscale.com/a\nsecret", encoded)

    def test_parse_accounts_variants_and_account_cap(self):
        array_variant = [
            {
                "id": f"acct-{index:02d}",
                "nickname": " Alice\u202e\x00 " if index == 0 else f"User {index}",
                "selected": index == 5,
            }
            for index in range(35)
        ]
        array_variant[34]["id"] = "bad id"
        object_variant = {
            "Profiles": {
                "prof-1": {
                    "Nickname": " Primary\u202e\x00 ",
                    "Tailnet": "Example.TS.Net.",
                    "Account": "alice@example.com",
                },
                "bad id": {"Nickname": "Ignored"},
                "prof-2": {
                    "Name": " Backup\u202e\x00 ",
                    "Account": "bob@example.com",
                },
            },
            "CurrentProfile": {"ID": "prof-1"},
        }

        result = self.node_eval(
            "({array: model.parseAccounts(data.array), object: model.parseAccounts(data.object)})",
            {"array": json.dumps(array_variant), "object": json.dumps(object_variant)},
        )
        self.assertEqual(len(result["array"]["accounts"]), 32)
        self.assertEqual(result["array"]["selectedAccountId"], "acct-05")
        self.assertEqual(result["array"]["selectedAccountLabel"], "User 5")
        self.assertEqual(result["array"]["accounts"][0]["nickname"], "Alice")
        self.assertFalse(any(account["id"] == "bad id" for account in result["array"]["accounts"]))

        self.assertEqual(len(result["object"]["accounts"]), 2)
        self.assertEqual(result["object"]["selectedAccountId"], "prof-1")
        self.assertEqual(result["object"]["selectedAccountLabel"], "Primary")
        self.assertEqual(result["object"]["accounts"][0]["tailnet"], "example.ts.net")
        self.assertEqual([account["id"] for account in result["object"]["accounts"]], ["prof-1", "prof-2"])

    def test_parse_exit_node_list_and_mullvad_region_options(self):
        rows = [
            ("100.64.0.10", "router.example.ts.net", "-", "-", "selected"),
            ("fd7a:115c:a1e0::2", "v6router.example.ts.net", "-", "-", "offline"),
            ("100.64.0.11", "se-sto-wg-001.mullvad.ts.net", "Sweden", "Stockholm", "-"),
            ("100.64.0.12", "se-sto-wg-002.mullvad.ts.net", "Sweden", "Stockholm", "-"),
            ("100.64.0.13", "se-any-wg-001.mullvad.ts.net", "Sweden", "Any", "-"),
        ]
        rows.extend(
            (
                f"100.64.{1 + (index // 250)}.{index % 250}",
                f"zz-region{index:03d}.mullvad.ts.net",
                f"ZZ Country {index:03d}",
                f"ZZ City {index:03d}",
                "active" if index == 3 else "-",
            )
            for index in range(130)
        )
        rows.extend(
            (
                f"100.65.{index // 250}.{index % 250}",
                f"exit{index:03d}.example.ts.net",
                "-",
                "-",
                "-",
            )
            for index in range(130)
        )
        rows.extend(
            [
                ("192.168.0.1", "badip.example.ts.net", "Nowhere", "City", "-"),
                ("100.64.0.99", "bad host", "Nowhere", "City", "-"),
            ]
        )

        result = self.node_eval(
            "(function() {"
            "  var nodes = model.parseExitNodeList(data.table);"
            "  var options = model.mullvadRegionOptions(nodes);"
            "  var alias = model.mullvadCountryOptions(nodes);"
            "  var router = null;"
            "  var v6 = null;"
            "  var stockholmCount = 0;"
            "  var anyCount = 0;"
            "  var hasCity003 = false;"
            "  var tailnetInOptions = false;"
            "  for (var i = 0; i < nodes.length; i++) {"
            "    if (nodes[i].HostName === 'router.example.ts.net') router = nodes[i];"
            "    if (nodes[i].HostName === 'v6router.example.ts.net') v6 = nodes[i];"
            "  }"
            "  for (var j = 0; j < options.length; j++) {"
            "    if (options[j].DisplayName === 'Stockholm, Sweden') stockholmCount += 1;"
            "    if (options[j].DisplayName === 'Any, Sweden') anyCount += 1;"
            "    if (options[j].DisplayName === 'ZZ City 003, ZZ Country 003') hasCity003 = true;"
            "    if (options[j].HostName === 'router.example.ts.net') tailnetInOptions = true;"
            "  }"
            "  return {"
            "    count: nodes.length,"
            "    router: router,"
            "    v6: v6,"
            "    optionsCount: options.length,"
            "    stockholmCount: stockholmCount,"
            "    anyCount: anyCount,"
            "    hasCity003: hasCity003,"
            "    tailnetInOptions: tailnetInOptions,"
            "    aliasEqual: JSON.stringify(alias) === JSON.stringify(options)"
            "  };"
            "})()",
            {"table": self.exit_table(rows)},
        )
        self.assertEqual(result["count"], 256)
        self.assertEqual(result["router"]["TailscaleIPs"], ["100.64.0.10"])
        self.assertTrue(result["router"]["ExitNode"])
        self.assertEqual(result["v6"]["TailscaleIPv6"], ["fd7a:115c:a1e0:0:0:0:0:2"])
        self.assertFalse(result["v6"]["Online"])
        self.assertEqual(result["optionsCount"], 128)
        self.assertEqual(result["stockholmCount"], 1)
        self.assertEqual(result["anyCount"], 0)
        self.assertTrue(result["hasCity003"])
        self.assertFalse(result["tailnetInOptions"])
        self.assertTrue(result["aliasEqual"])


if __name__ == "__main__":
    unittest.main()
