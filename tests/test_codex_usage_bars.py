#!/usr/bin/env python3
"""Focused stdlib tests for codex-usage-bars' cached JSON interface."""

from __future__ import annotations

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).parents[1] / "dot-local" / "bin" / "codex-usage-bars"
LOADER = importlib.machinery.SourceFileLoader("codex_usage_bars", str(SCRIPT))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
assert SPEC is not None
usage = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(usage)


class JsonStatusTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.cache = Path(self.tempdir.name) / "usage.json"
        self.env = mock.patch.dict(
            os.environ,
            {
                "CODEX_USAGE_BARS_CACHE": str(self.cache),
                "CODEX_USAGE_BARS_MODE": "used",
                "CODEX_USAGE_BARS_TTL": "60",
                "CODEX_USAGE_BARS_API_SPEND_DAYS": "7",
                "CODEX_USAGE_BARS_API_SPEND": "auto",
                "CODEX_USAGE_BARS_CCUSAGE_CMD": "",
                "CODEX_USAGE_BARS_JSON_REFRESH_WAIT": "",
            },
        )
        self.env.start()
        self.addCleanup(self.env.stop)

    def write_cache(
        self,
        *,
        fetched_at: float = 1_000,
        percentages: dict[str, float | None] | None = None,
        five_hour: dict[str, float | None] | None = None,
        states: dict[str, dict[str, float]] | None = None,
        api_spend: dict[str, float] | None = None,
    ) -> None:
        with mock.patch.object(usage.time, "time", return_value=fetched_at):
            usage.write_cache(
                "tmux-output",
                percentages or {"codex": 30.0, "claude": 40.0},
                five_hour or {"codex": 80.0, "claude": 50.0},
                states
                or {
                    "codex": {"last_attempt_at": fetched_at, "last_success_at": fetched_at},
                    "claude": {"last_attempt_at": fetched_at, "last_success_at": fetched_at},
                    "apispend": {},
                },
                api_spend,
            )

    def print_json(self, now: float) -> tuple[str, dict[str, object]]:
        output = io.StringIO()
        with mock.patch.object(usage.time, "time", return_value=now), contextlib.redirect_stdout(output):
            result = usage.print_json_status()
        self.assertEqual(result, 0)
        line = output.getvalue().rstrip("\n")
        return line, json.loads(line)

    def test_fresh_cache_outputs_complete_compact_status_without_refresh(self) -> None:
        self.write_cache(api_spend={"total": 12.5})
        with mock.patch.object(usage, "spawn_refresh") as spawn:
            line, payload = self.print_json(1_010)

        spawn.assert_not_called()
        self.assertNotIn(": ", line)
        self.assertNotIn(", ", line)
        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(payload["generated_at"], 1010)
        self.assertEqual(payload["fetched_at"], 1000)
        self.assertEqual(payload["mode"], "used")
        self.assertFalse(payload["cache_stale"])
        self.assertFalse(payload["stale"])
        self.assertEqual(payload["providers"]["codex"]["data_at"], 1000)
        self.assertFalse(payload["providers"]["codex"]["stale"])
        self.assertEqual(
            payload["providers"]["codex"]["weekly"],
            {"used_percent": 30.0, "display_percent": 30.0},
        )
        self.assertEqual(
            payload["providers"]["codex"]["five_hour"],
            {"used_percent": 80.0, "display_percent": 80.0},
        )
        self.assertEqual(payload["providers"]["codex"]["health"]["status"], "healthy")
        # auto mode does not leak cached API spend when subscription data exists.
        self.assertNotIn("api_spend", payload)

    def test_stale_cache_is_printed_and_background_refresh_is_triggered(self) -> None:
        self.write_cache()
        with (
            mock.patch.object(usage, "spawn_refresh") as spawn,
            mock.patch.object(usage, "refresh_cache") as refresh,
        ):
            _, payload = self.print_json(1_061)

        self.assertTrue(payload["cache_stale"])
        self.assertTrue(payload["stale"])
        self.assertTrue(payload["providers"]["codex"]["stale"])
        self.assertEqual(payload["providers"]["claude"]["weekly"]["used_percent"], 40.0)
        spawn.assert_called_once_with()
        refresh.assert_not_called()

    def test_missing_five_hour_window_is_null_and_never_copied_from_weekly(self) -> None:
        self.write_cache(
            percentages={"codex": 20.0, "claude": 40.0},
            five_hour={"codex": None, "claude": None},
        )
        payload = usage.build_json_status(
            usage.read_cache(), stale=False, generated_at=1_010
        )
        for name, weekly in (("codex", 20.0), ("claude", 40.0)):
            provider = payload["providers"][name]
            self.assertTrue(provider["available"])
            self.assertEqual(provider["weekly"]["used_percent"], weekly)
            self.assertEqual(
                provider["five_hour"],
                {"used_percent": None, "display_percent": None},
            )

        # Legacy caches that predate severity_percentages are also unavailable,
        # rather than reviving the weekly value as a five-hour metric.
        cached = usage.read_cache()
        self.assertIsNotNone(cached)
        cached.pop("severity_percentages")
        payload = usage.build_json_status(cached, stale=False, generated_at=1_010)
        self.assertIsNone(payload["providers"]["codex"]["five_hour"]["used_percent"])

    def test_fetchers_leave_absent_five_hour_window_unavailable(self) -> None:
        codex_payload = {
            "rate_limit": {
                "primary_window": {
                    "limit_window_seconds": 7 * 24 * 60 * 60,
                    "used_percent": 31,
                }
            }
        }
        with (
            mock.patch.object(usage, "read_codex_auth", return_value=("token", None)),
            mock.patch.object(usage, "request_json", return_value=codex_payload),
        ):
            self.assertEqual(usage.fetch_codex_percents(), (31.0, None))

        claude_payload = {"seven_day": {"utilization": 42}}
        with (
            mock.patch.object(usage, "claude_access_token", return_value="token"),
            mock.patch.object(usage, "request_json", return_value=claude_payload),
        ):
            self.assertEqual(usage.fetch_claude_percents(), (42.0, None))

    def test_missing_provider_is_explicit_and_backoff_is_sanitized(self) -> None:
        self.write_cache(
            percentages={"codex": 20.0, "claude": None},
            five_hour={"codex": 25.0, "claude": None},
            states={
                "codex": {"last_attempt_at": 1_000, "last_success_at": 1_000},
                "claude": {
                    "last_attempt_at": 1_000,
                    "last_error_at": 1_000,
                    "next_attempt_at": 1_200,
                    "internal_detail": "sensitive-marker-not-exported",
                },
                "apispend": {},
            },
        )
        with mock.patch.object(usage, "spawn_refresh"):
            line, payload = self.print_json(1_010)

        claude = payload["providers"]["claude"]
        self.assertFalse(claude["available"])
        self.assertIsNone(claude["data_at"])
        self.assertTrue(claude["stale"])
        self.assertTrue(payload["stale"])
        self.assertEqual(claude["weekly"], {"used_percent": None, "display_percent": None})
        self.assertEqual(claude["health"]["status"], "backoff")
        self.assertTrue(claude["health"]["in_backoff"])
        self.assertEqual(claude["health"]["next_attempt_at"], 1200)
        self.assertNotIn("sensitive-marker-not-exported", line)
        self.assertNotIn("api_spend", payload)

    def test_no_cache_performs_one_synchronous_initial_refresh(self) -> None:
        def refresh() -> bool:
            self.write_cache(fetched_at=2_000)
            return True

        with (
            mock.patch.object(usage, "refresh_cache", side_effect=refresh) as refresh_mock,
            mock.patch.object(usage, "spawn_refresh") as spawn,
        ):
            _, payload = self.print_json(2_000)

        refresh_mock.assert_called_once_with()
        spawn.assert_not_called()
        self.assertFalse(payload["stale"])
        self.assertEqual(payload["fetched_at"], 2000)

    def test_failed_refresh_retains_data_but_marks_provider_and_top_level_stale(self) -> None:
        self.write_cache()
        with (
            mock.patch.dict(os.environ, {"CODEX_USAGE_BARS_API_SPEND": "off"}),
            mock.patch.object(usage.time, "time", return_value=1_061),
            mock.patch.object(
                usage, "fetch_codex_percents", side_effect=usage.UsageError("offline")
            ),
            mock.patch.object(usage, "fetch_claude_percents") as claude_fetch,
            mock.patch.object(usage, "log_provider_failure"),
        ):
            self.assertTrue(usage.refresh_cache())

        claude_fetch.assert_not_called()  # its provider TTL is still fresh
        cached = usage.read_cache()
        self.assertIsNotNone(cached)
        payload = usage.build_json_status(cached, stale=False, generated_at=1_061)
        codex = payload["providers"]["codex"]
        self.assertEqual(codex["weekly"]["used_percent"], 30.0)
        self.assertEqual(codex["data_at"], 1000)
        self.assertTrue(codex["stale"])
        self.assertEqual(codex["health"]["status"], "backoff")
        self.assertFalse(payload["cache_stale"])
        self.assertTrue(payload["stale"])

    def test_api_spend_visibility_respects_off_auto_and_on(self) -> None:
        self.write_cache(api_spend={"total": 12.5})
        cached = usage.read_cache()
        self.assertIsNotNone(cached)

        with mock.patch.dict(os.environ, {"CODEX_USAGE_BARS_API_SPEND": "off"}):
            self.assertNotIn(
                "api_spend", usage.build_json_status(cached, stale=False, generated_at=1_010)
            )
        with mock.patch.dict(os.environ, {"CODEX_USAGE_BARS_API_SPEND": "auto"}):
            self.assertNotIn(
                "api_spend", usage.build_json_status(cached, stale=False, generated_at=1_010)
            )
        with mock.patch.dict(os.environ, {"CODEX_USAGE_BARS_API_SPEND": "on"}):
            payload = usage.build_json_status(cached, stale=False, generated_at=1_010)
            self.assertEqual(payload["api_spend"]["total"], 12.5)

        self.write_cache(
            percentages={"codex": None, "claude": None},
            five_hour={"codex": None, "claude": None},
            states={
                "codex": {},
                "claude": {},
                "apispend": {"last_attempt_at": 1_000, "last_success_at": 1_000},
            },
            api_spend={"total": 4.25},
        )
        with mock.patch.dict(os.environ, {"CODEX_USAGE_BARS_API_SPEND": "auto"}):
            payload = usage.build_json_status(
                usage.read_cache(), stale=False, generated_at=1_010
            )
        self.assertEqual(payload["api_spend"]["total"], 4.25)
        self.assertEqual(payload["api_spend"]["data_at"], 1000)
        self.assertFalse(payload["api_spend"]["stale"])

    def test_bool_and_nonfinite_cached_metrics_are_unavailable_and_not_serialized(self) -> None:
        cached = {
            "fetched_at": 1_000,
            "output": "codex 99% claude 98%",
            "percentages": {"codex": True, "claude": float("nan")},
            "severity_percentages": {"codex": float("inf"), "claude": False},
            "provider_state": {
                "codex": {"last_success_at": 1_000},
                "claude": {"last_success_at": 1_000},
                "apispend": {"last_success_at": 1_000},
            },
            "api_spend": {"total": float("-inf")},
        }
        payload = usage.build_json_status(cached, stale=False, generated_at=1_010)
        for provider in ("codex", "claude"):
            self.assertFalse(payload["providers"][provider]["available"])
            self.assertIsNone(payload["providers"][provider]["data_at"])
        self.assertNotIn("api_spend", payload)
        serialized = usage.render_json_status(cached, stale=False)
        self.assertNotIn("NaN", serialized)
        self.assertNotIn("Infinity", serialized)

    def test_invalid_fetched_metric_is_rejected_and_old_value_retained(self) -> None:
        self.write_cache()
        previous = usage.read_cache()
        with (
            mock.patch.object(usage.time, "time", return_value=1_061),
            mock.patch.object(usage, "fetch_codex_percents", return_value=(True, float("nan"))),
            mock.patch.object(usage, "fetch_claude_percents") as claude_fetch,
            mock.patch.object(usage, "log_provider_failure"),
        ):
            percentages, severity, states = usage.collect_percentages(previous)
        claude_fetch.assert_not_called()
        self.assertEqual(percentages["codex"], 30.0)
        self.assertEqual(severity["codex"], 80.0)
        self.assertEqual(states["codex"]["last_success_at"], 1000)
        self.assertEqual(states["codex"]["last_error_at"], 1061)

    def test_malformed_cache_safely_emits_unavailable_json_without_network(self) -> None:
        self.cache.write_text("{not-json", encoding="utf-8")
        with (
            mock.patch.object(usage, "refresh_cache", return_value=False) as refresh,
            mock.patch.object(usage, "spawn_refresh") as spawn,
        ):
            _, payload = self.print_json(1_000)
        refresh.assert_called_once_with()
        spawn.assert_called_once_with()
        self.assertTrue(payload["cache_stale"])
        self.assertTrue(payload["stale"])
        self.assertFalse(payload["providers"]["codex"]["available"])

    def test_forced_json_refreshes_synchronously_and_emits_new_cache(self) -> None:
        self.write_cache(fetched_at=1_000)

        def refresh() -> bool:
            self.write_cache(fetched_at=2_000, percentages={"codex": 7.0, "claude": 8.0})
            return True

        output = io.StringIO()
        with (
            mock.patch.object(usage, "refresh_cache", side_effect=refresh) as refresh_mock,
            mock.patch.object(usage, "spawn_refresh") as spawn,
            mock.patch.object(usage.time, "time", return_value=2_000),
            contextlib.redirect_stdout(output),
        ):
            self.assertEqual(usage.print_json_status(force_refresh=True), 0)
        refresh_mock.assert_called_once_with()
        spawn.assert_not_called()
        payload = json.loads(output.getvalue())
        self.assertEqual(payload["fetched_at"], 2000)
        self.assertEqual(payload["providers"]["codex"]["weekly"]["used_percent"], 7.0)

    def test_forced_json_coalesces_with_lock_owner_and_waits_for_cache_change(self) -> None:
        self.write_cache(fetched_at=1_000)
        usage.lock_file().write_text("other-pid", encoding="ascii")

        def complete_refresh(_seconds: float) -> None:
            self.write_cache(fetched_at=2_000, percentages={"codex": 9.0, "claude": 10.0})
            usage.lock_file().unlink()

        output = io.StringIO()
        with (
            mock.patch.object(usage, "refresh_cache", return_value=False) as refresh,
            mock.patch.object(usage.time, "sleep", side_effect=complete_refresh) as sleep,
            mock.patch.object(usage.time, "time", return_value=2_000),
            contextlib.redirect_stdout(output),
        ):
            self.assertEqual(usage.print_json_status(force_refresh=True), 0)
        refresh.assert_called_once_with()
        sleep.assert_called_once_with(usage.JSON_REFRESH_POLL_SECONDS)
        payload = json.loads(output.getvalue())
        self.assertEqual(payload["fetched_at"], 2000)
        self.assertEqual(payload["providers"]["codex"]["weekly"]["used_percent"], 9.0)

    def test_forced_json_timeout_marks_even_recent_cached_fallback_stale(self) -> None:
        self.write_cache(fetched_at=2_000)
        usage.lock_file().write_text("other-pid", encoding="ascii")
        self.addCleanup(lambda: usage.lock_file().unlink(missing_ok=True))
        output = io.StringIO()
        with (
            mock.patch.dict(os.environ, {"CODEX_USAGE_BARS_JSON_REFRESH_WAIT": "0"}),
            mock.patch.object(usage, "refresh_cache", return_value=False),
            mock.patch.object(usage.time, "time", return_value=2_000),
            contextlib.redirect_stdout(output),
        ):
            self.assertEqual(usage.print_json_status(force_refresh=True), 0)
        payload = json.loads(output.getvalue())
        self.assertEqual(payload["fetched_at"], 2000)
        self.assertTrue(payload["cache_stale"])
        self.assertTrue(payload["stale"])
        self.assertEqual(
            payload["refresh_error"],
            "Usage refresh did not complete; retained data may be stale",
        )

    def test_json_coalesce_wait_budget_uses_operation_timeouts_and_fast_override(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "CODEX_USAGE_BARS_TIMEOUT": "4",
                "CODEX_USAGE_BARS_CCUSAGE_TIMEOUT": "7",
                "CODEX_USAGE_BARS_API_SPEND": "on",
            },
        ):
            self.assertEqual(usage.json_refresh_wait_seconds(), 20.0)
        with mock.patch.dict(
            os.environ, {"CODEX_USAGE_BARS_JSON_REFRESH_WAIT": "0.125"}
        ):
            self.assertEqual(usage.json_refresh_wait_seconds(), 0.125)

    def test_unavailable_ccusage_respects_normal_failure_backoff(self) -> None:
        previous = {
            "provider_state": {
                "apispend": {
                    "last_attempt_at": 1_000,
                    "last_error_at": 1_000,
                    "next_attempt_at": 1_300,
                }
            }
        }
        with (
            mock.patch.object(usage.time, "time", return_value=1_010),
            mock.patch.object(usage, "fetch_api_spend") as fetch,
        ):
            spend, state = usage.collect_api_spend(previous)
        fetch.assert_not_called()
        self.assertIsNone(spend)
        self.assertEqual(state["next_attempt_at"], 1_300)

    def fetch_ccusage_payload(self, payload: object) -> float:
        with (
            mock.patch.object(usage, "ccusage_command", return_value=["ccusage"]),
            mock.patch.object(
                usage.subprocess, "check_output", return_value=json.dumps(payload)
            ),
        ):
            return usage.fetch_api_spend()

    def test_ccusage_requires_an_object_and_never_defaults_to_npx(self) -> None:
        with mock.patch.object(usage.shutil, "which", return_value=None):
            with self.assertRaisesRegex(usage.UsageError, "not installed"):
                usage.ccusage_command()

        with self.assertRaisesRegex(usage.UsageError, "non-object JSON"):
            self.fetch_ccusage_payload([])

        with mock.patch.dict(
            os.environ, {"CODEX_USAGE_BARS_CCUSAGE_CMD": "custom-ccusage --flag"}
        ):
            self.assertEqual(usage.ccusage_command(), ["custom-ccusage", "--flag"])

    def test_ccusage_rejects_objects_without_valid_daily_or_total_schema(self) -> None:
        with self.assertRaisesRegex(usage.UsageError, "valid total or daily"):
            self.fetch_ccusage_payload({})

        with (
            mock.patch.object(usage.time, "time", return_value=1_000),
            mock.patch.object(usage, "ccusage_command", return_value=["ccusage"]),
            mock.patch.object(usage.subprocess, "check_output", return_value="{}"),
            mock.patch.object(usage, "log_provider_failure"),
        ):
            spend, state = usage.collect_api_spend()
        self.assertIsNone(spend)
        self.assertNotIn("last_success_at", state)
        self.assertEqual(state["last_error_at"], 1_000)

        for daily in (None, {}, "not-a-list", 0, False):
            with self.subTest(daily=daily):
                with self.assertRaisesRegex(usage.UsageError, "was not a list"):
                    self.fetch_ccusage_payload({"daily": daily})

    def test_ccusage_accepts_explicit_empty_daily_list_as_zero(self) -> None:
        self.assertEqual(self.fetch_ccusage_payload({"daily": []}), 0.0)

    def test_ccusage_accepts_finite_aggregate_total_or_valid_daily_rows(self) -> None:
        self.assertEqual(
            self.fetch_ccusage_payload({"totals": {"totalCost": 12.5}}), 12.5
        )
        self.assertEqual(
            self.fetch_ccusage_payload(
                {"daily": [{"totalCost": 1.25}, {"totalCost": 2.5}]}
            ),
            3.75,
        )

    def test_ccusage_rejects_bool_nonfinite_and_invalid_costs(self) -> None:
        invalid_payloads = (
            {"totals": {"totalCost": True}},
            {"totals": {"totalCost": float("inf")}},
            {"totals": [], "daily": []},
            {"totals": {"totalCost": 1.0}, "daily": "not-a-list"},
            {"daily": [{"totalCost": True}]},
            {"daily": [{"totalCost": float("nan")}]},
            {"daily": [{"totalCost": "1.25"}]},
            {"daily": [{}]},
            {"totals": {"totalCost": 1.0}, "daily": [None]},
            {"daily": [{"totalCost": 1e308}, {"totalCost": 1e308}]},
        )
        for payload in invalid_payloads:
            with self.subTest(payload=payload):
                with self.assertRaises(usage.UsageError):
                    self.fetch_ccusage_payload(payload)

    def test_remaining_mode_helper_has_used_and_display_percentages(self) -> None:
        self.write_cache()
        with mock.patch.dict(os.environ, {"CODEX_USAGE_BARS_MODE": "remaining"}):
            payload = usage.build_json_status(usage.read_cache(), stale=False, generated_at=1_010)
        self.assertEqual(payload["mode"], "remaining")
        self.assertEqual(
            payload["providers"]["codex"]["weekly"],
            {"used_percent": 30.0, "display_percent": 70.0},
        )

    def test_existing_tmux_helper_output_is_unchanged_for_fresh_cache(self) -> None:
        self.write_cache()
        output = io.StringIO()
        with (
            mock.patch.object(usage.time, "time", return_value=1_010),
            mock.patch.object(usage, "spawn_refresh") as spawn,
            contextlib.redirect_stdout(output),
        ):
            self.assertEqual(usage.print_status(), 0)
        spawn.assert_not_called()
        self.assertEqual(output.getvalue(), "tmux-output\n")


class SecurityHardeningTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.root = Path(self.tempdir.name)
        self.log = self.root / "private" / "usage.log"
        self.cache = self.root / "private-cache" / "usage.json"
        self.env = mock.patch.dict(
            os.environ,
            {
                "CODEX_USAGE_BARS_LOG": str(self.log),
                "CODEX_USAGE_BARS_CACHE": str(self.cache),
                "CODEX_USAGE_BARS_ALLOW_INSECURE_HTTP": "",
            },
        )
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_cross_origin_redirect_is_rejected_before_headers_are_forwarded(self) -> None:
        request = urllib.request.Request(
            "https://provider.example/usage",
            headers={
                "Authorization": "Bearer example-credential",
                "ChatGPT-Account-ID": "example-account",
            },
        )
        handler = usage.SameOriginRedirectHandler()
        with (
            mock.patch.object(
                urllib.request.HTTPRedirectHandler, "redirect_request"
            ) as default_redirect,
            self.assertRaisesRegex(usage.UsageError, "cross-origin"),
        ):
            handler.redirect_request(
                request,
                None,
                302,
                "Found",
                {},
                "https://other.example/usage",
            )
        default_redirect.assert_not_called()

    def test_non_https_and_unsafe_endpoint_urls_are_rejected_without_network(self) -> None:
        with mock.patch.object(usage.urllib.request, "build_opener") as build_opener:
            with self.assertRaisesRegex(usage.UsageError, "must use HTTPS"):
                usage.request_json("http://provider.example/usage", {})
            with self.assertRaisesRegex(usage.UsageError, "user information"):
                usage.request_json("https://name@provider.example/usage", {})
            with self.assertRaisesRegex(usage.UsageError, "fragment"):
                usage.request_json("https://provider.example/usage#section", {})
        build_opener.assert_not_called()

    def test_insecure_http_requires_explicit_test_development_opt_in(self) -> None:
        class Response:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return None

            def read(self) -> bytes:
                return b'{}'

        opener = mock.Mock()
        opener.open.return_value = Response()
        with (
            mock.patch.dict(
                os.environ, {"CODEX_USAGE_BARS_ALLOW_INSECURE_HTTP": "1"}
            ),
            mock.patch.object(
                usage.urllib.request, "build_opener", return_value=opener
            ) as build_opener,
        ):
            self.assertEqual(
                usage.request_json("http://localhost.example/usage", {}), {}
            )
        self.assertIsInstance(
            build_opener.call_args.args[0], usage.SameOriginRedirectHandler
        )

    def test_http_error_and_log_omit_query_and_response_body(self) -> None:
        endpoint = "https://provider.example/usage?opaque-marker=value"
        error = urllib.error.HTTPError(
            endpoint,
            429,
            "Limited",
            {"Retry-After": "17"},
            io.BytesIO(b"response-body-marker"),
        )
        opener = mock.Mock()
        opener.open.side_effect = error
        with mock.patch.object(
            usage.urllib.request, "build_opener", return_value=opener
        ):
            with self.assertRaises(usage.HTTPUsageError) as raised:
                usage.request_json(endpoint, {"Authorization": "Bearer example"})

        message = str(raised.exception)
        self.assertIn("HTTP 429", message)
        self.assertIn("https://provider.example/usage", message)
        self.assertIn("Retry-After: 17s", message)
        self.assertNotIn("opaque-marker", message)
        self.assertNotIn("response-body-marker", message)

        usage.log_provider_failure("codex", raised.exception)
        logged = self.log.read_text(encoding="utf-8")
        self.assertNotIn("opaque-marker", logged)
        self.assertNotIn("response-body-marker", logged)
        self.assertNotIn("?", logged)

    def test_log_and_new_parent_are_private(self) -> None:
        usage.log_provider_failure("codex", usage.UsageError("offline"))
        self.assertEqual(self.log.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.log.parent.stat().st_mode & 0o777, 0o700)

        os.chmod(self.log, 0o644)
        usage.log_provider_failure("claude", usage.UsageError("offline"))
        self.assertEqual(self.log.stat().st_mode & 0o777, 0o600)

    def test_log_refuses_to_follow_symlink(self) -> None:
        self.log.parent.mkdir(mode=0o700)
        target = self.root / "existing-user-file"
        target.write_text("keep\n", encoding="utf-8")
        self.log.symlink_to(target)

        usage.log_provider_failure("codex", usage.UsageError("offline"))
        self.assertEqual(target.read_text(encoding="utf-8"), "keep\n")
        self.assertTrue(self.log.is_symlink())

    def test_atomic_cache_and_new_parent_are_private(self) -> None:
        with mock.patch.object(usage.time, "time", return_value=1_000):
            usage.write_cache("output", {}, {}, {}, None)
        self.assertEqual(self.cache.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.cache.parent.stat().st_mode & 0o777, 0o700)


class CliCompatibilityTests(unittest.TestCase):
    def test_no_arg_and_unknown_arg_still_use_tmux_status(self) -> None:
        for argv in ([str(SCRIPT)], [str(SCRIPT), "--unknown"]):
            with (
                self.subTest(argv=argv),
                mock.patch.object(sys, "argv", argv),
                mock.patch.object(usage, "print_status", return_value=23) as status,
            ):
                self.assertEqual(usage.main(), 23)
                status.assert_called_once_with()

    def test_refresh_and_json_dispatch(self) -> None:
        with (
            mock.patch.object(sys, "argv", [str(SCRIPT), "--refresh", "--ignored"]),
            mock.patch.object(usage, "refresh_cache", return_value=True) as refresh,
        ):
            self.assertEqual(usage.main(), 0)
            refresh.assert_called_once_with()

        with (
            mock.patch.object(sys, "argv", [str(SCRIPT), "--json"]),
            mock.patch.object(usage, "print_json_status", return_value=29) as json_status,
        ):
            self.assertEqual(usage.main(), 29)
            json_status.assert_called_once_with()

        with (
            mock.patch.object(sys, "argv", [str(SCRIPT), "--json", "--refresh"]),
            mock.patch.object(usage, "print_json_status", return_value=31) as json_status,
        ):
            self.assertEqual(usage.main(), 31)
            json_status.assert_called_once_with(force_refresh=True)

        with (
            mock.patch.object(sys, "argv", [str(SCRIPT), "--json", "--ignored"]),
            mock.patch.object(usage, "print_json_status", return_value=29) as json_status,
        ):
            self.assertEqual(usage.main(), 29)
            json_status.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
