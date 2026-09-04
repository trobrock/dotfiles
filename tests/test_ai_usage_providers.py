"""Security and normalization tests for the vendored usage providers."""

from __future__ import annotations

import contextlib
import datetime as dt
import importlib.machinery
import importlib.util
import io
import json
import os
import tempfile
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
PROVIDERS = ROOT / "dot-local/lib/ai-usage/providers"


def load_provider(name: str):
    loader = importlib.machinery.SourceFileLoader(f"tested_provider_{name}", str(PROVIDERS / name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


claude = load_provider("claude")
codex = load_provider("codex")
fireworks = load_provider("fireworks")


class ClaudeProviderTests(unittest.TestCase):
    def test_official_values_are_always_percent_scaled(self) -> None:
        expected = {0: 0, 0.5: 0.005, 1: 0.01, 37: 0.37, 100: 1}
        for raw, normalized in expected.items():
            with self.subTest(raw=raw):
                self.assertEqual(claude.normalize_utilization(raw, False), normalized)
        scoped = claude.scoped_limits(
            {"limits": [{
                "kind": "weekly_scoped",
                "percent": 0.5,
                "resets_at": "2099-01-01T00:00:00Z",
                "scope": {"model": {"display_name": "Opus"}},
            }]},
            False,
        )
        self.assertEqual(scoped[0]["percent"], 0.005)
        self.assertEqual(scoped[0]["label"], "Opus Weekly")

    def test_cached_fallback_requires_open_reset_and_discloses_staleness(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            future = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=1)).isoformat()
            past = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=1)).isoformat()
            (root / "claude-limits.json").write_text(json.dumps({
                "fetchedAtMs": 1,
                "limits": [
                    {"label": "open", "percent": 0.2, "resetsAt": future},
                    {"label": "closed", "percent": 0.9, "resetsAt": past},
                    {"label": "unknown", "percent": 0.7, "resetsAt": "bad"},
                ],
            }))
            with (
                mock.patch.object(claude, "cache_root", return_value=root),
                mock.patch.object(claude, "probe_limits", return_value={
                    "ok": False, "helpText": "Couldn't reach Anthropic's usage endpoint."
                }),
            ):
                result = claude.collect_limits("token", 0, True)
        self.assertEqual([item["label"] for item in result["limits"]], ["open"])
        self.assertIn("Last-known", result["usageStatusText"])
        self.assertIn("last-known", result["authHelpText"])

    def test_cache_io_is_private_and_does_not_follow_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            victim = root / "victim"
            victim.write_text("private victim")
            target = root / "cache.json"
            target.symlink_to(victim)
            self.assertIsNone(claude.read_fresh_json(target, 60))
            claude.write_json(target, {"safe": True})
            self.assertEqual(victim.read_text(), "private victim")
            self.assertEqual(json.loads(target.read_text()), {"safe": True})
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)

    def test_http_errors_and_retry_after_are_sanitized(self) -> None:
        secret = "token-SECRET /private/transcript response-body"
        headers = {"retry-after": secret}
        error = urllib.error.HTTPError(claude.USAGE_ENDPOINT, 500, secret, headers, io.BytesIO(secret.encode()))
        opener = mock.Mock()
        opener.open.side_effect = error
        with mock.patch.object(claude.urllib.request, "build_opener", return_value=opener):
            result = claude.probe_limits("bearer-secret")
        error.close()
        rendered = json.dumps(result)
        self.assertNotIn(secret, rendered)
        self.assertNotIn("bearer-secret", rendered)


class RedirectTests(unittest.TestCase):
    def test_authenticated_redirects_require_same_origin_https(self) -> None:
        for provider in (claude, fireworks):
            handler = provider.SameOriginRedirectHandler()
            request = urllib.request.Request("https://example.test/private")
            with self.subTest(provider=provider.__name__, redirect="cross-origin"):
                with self.assertRaises(urllib.error.HTTPError) as caught:
                    handler.redirect_request(request, None, 302, "", {}, "https://evil.test/")
                caught.exception.close()
            with self.subTest(provider=provider.__name__, redirect="downgrade"):
                with self.assertRaises(urllib.error.HTTPError) as caught:
                    handler.redirect_request(request, None, 302, "", {}, "http://example.test/")
                caught.exception.close()
            redirected = handler.redirect_request(request, None, 302, "", {}, "https://example.test/next")
            self.assertEqual(redirected.full_url, "https://example.test/next")


class CodexProviderTests(unittest.TestCase):
    def test_child_environment_is_allowlisted(self) -> None:
        environment = {
            "HOME": "/safe/home",
            "PATH": "/bin",
            "LANG": "C.UTF-8",
            "LC_ALL": "C",
            "XDG_CONFIG_HOME": "/safe/config",
            "HTTPS_PROXY": "https://proxy.test",
            "SSL_CERT_FILE": "/safe/ca.pem",
            "CODEX_HOME": "/safe/codex",
            "AWS_SECRET_ACCESS_KEY": "cloud-secret",
            "OPENAI_API_KEY": "api-secret",
            "FIREWORKS_API_KEY": "other-secret",
        }
        with mock.patch.dict(os.environ, environment, clear=True):
            child = codex.runtime_env()
        self.assertEqual(child["CODEX_HOME"], "/safe/codex")
        self.assertEqual(child["HTTPS_PROXY"], "https://proxy.test")
        for forbidden in ("AWS_SECRET_ACCESS_KEY", "OPENAI_API_KEY", "FIREWORKS_API_KEY"):
            self.assertNotIn(forbidden, child)

    def test_malformed_rpc_windows_are_not_emitted(self) -> None:
        for value in (float("nan"), float("inf"), -1, 101, "secret/body"):
            with self.subTest(value=value):
                self.assertIsNone(codex.limit_window({"usedPercent": value}))

    def test_expired_rpc_token_has_actionable_status(self) -> None:
        proc = mock.Mock()
        proc.stdin = io.StringIO()
        with (
            mock.patch.object(codex, "find_command", return_value="/safe/codex"),
            mock.patch.object(codex.subprocess, "Popen", return_value=proc),
            mock.patch.object(codex, "rpc_request", side_effect=[
                {"result": {}},
                {"result": {"account": {"planType": "pro"}}},
                codex.CodexRpcError("auth_expired"),
            ]),
        ):
            result = codex.fetch_codex_rpc()
        self.assertEqual(result["usageStatusText"], "Codex sign-in expired")
        self.assertEqual(
            result["authHelpText"],
            "Run `codex login` to refresh your sign-in and restore limits.",
        )

    def test_rpc_error_classification_does_not_retain_response(self) -> None:
        secret = "token_expired bearer-secret /home/private/auth.json"
        error = codex.CodexRpcError(codex.rpc_error_kind({"message": secret}))
        self.assertEqual(error.kind, "auth_expired")
        self.assertNotIn(secret, str(error))

    def test_start_exception_is_fixed_and_default_stderr_is_quiet(self) -> None:
        secret = "TOKEN /home/private/session.jsonl response-body"
        stderr = io.StringIO()
        with (
            mock.patch.object(codex, "find_command", return_value="/safe/codex"),
            mock.patch.object(codex.subprocess, "Popen", side_effect=OSError(secret)) as popen,
            mock.patch.dict(os.environ, {"AI_USAGE_DEBUG": "0"}),
            contextlib.redirect_stderr(stderr),
        ):
            result = codex.fetch_codex_rpc()
        self.assertEqual(popen.call_args.args[0], ["/safe/codex", "-s", "read-only", "-a", "never", "app-server"])
        self.assertNotIn(secret, json.dumps(result))
        self.assertEqual(stderr.getvalue(), "")


class FireworksProviderTests(unittest.TestCase):
    def test_no_auth_is_a_full_record(self) -> None:
        with mock.patch.object(fireworks, "credentials", return_value=("", "")):
            record = fireworks.scan(fireworks.API_BASE_URL, Path("/not/read"))
        for key in (
            "schemaVersion", "id", "ready", "hasLocalStats", "limits",
            "todayPrompts", "todaySessions", "todayTotalTokens",
            "todayTokensByModel", "recentDays", "totalPrompts",
            "totalSessions", "activeDays", "activeDates", "modelUsage",
        ):
            self.assertIn(key, record)
        self.assertFalse(record["ready"])

    def test_invalid_numbers_and_excess_rows_are_bounded(self) -> None:
        today = dt.date(2026, 1, 2)
        rows = [
            {"startTime": "2026-01-02T00:00:00Z", "modelName": "bad", "promptTokens": value,
             "completionTokens": value}
            for value in ("NaN", "Infinity", -10)
        ]
        rows.extend({
            "startTime": "2026-01-02T00:00:00Z",
            "modelName": f"model-{index}",
            "promptTokens": 10**100,
            "completionTokens": 10**100,
        } for index in range(fireworks.MAX_BILLING_ROWS + 5))
        stats = fireworks.summarize_usage({"serverlessCosts": rows}, today)
        self.assertGreaterEqual(stats["todayTotalTokens"], 0)
        self.assertLessEqual(stats["todayTotalTokens"], fireworks.MAX_TOKEN_VALUE)
        self.assertLessEqual(len(stats["modelUsage"]), fireworks.MAX_MODELS + 1)
        self.assertNotIn("bad", stats["modelUsage"])
        self.assertNotIn("NaN", json.dumps(stats))

    def test_non_https_initial_request_is_rejected_without_network(self) -> None:
        client = fireworks.FireworksClient("api-secret", "http://example.test")
        with mock.patch.object(fireworks.urllib.request, "build_opener") as opener:
            with self.assertRaises(fireworks.FireworksError) as caught:
                client.request("/v1/accounts")
        opener.assert_not_called()
        self.assertNotIn("api-secret", fireworks.safe_error_help(caught.exception))

    def test_exception_help_never_exposes_arbitrary_text(self) -> None:
        secret = "account/key TOKEN response-body /private/config"
        self.assertNotIn(secret, fireworks.safe_error_help(fireworks.FireworksError(secret)))
        stderr = io.StringIO()
        with mock.patch.dict(os.environ, {"AI_USAGE_DEBUG": "0"}), contextlib.redirect_stderr(stderr):
            fireworks.debug_exception("scan", RuntimeError(secret))
        self.assertEqual(stderr.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
