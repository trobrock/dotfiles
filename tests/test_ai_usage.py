"""Backend and vendored collector regression tests (no network or real user data)."""

from __future__ import annotations

import contextlib
import datetime as dt
import json
import os
import runpy
import sqlite3
import stat
import subprocess
import tempfile
import textwrap
import time
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "dot-local/bin/ai-usage"
PROVIDERS = ROOT / "dot-local/lib/ai-usage/providers"


def record(provider_id: str, count: int = 1, scope: str = "device") -> dict:
    today = dt.datetime.now().date().isoformat()
    return {
        "schemaVersion": 1,
        "id": provider_id,
        "name": provider_id.title(),
        "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "ready": True,
        "hasLocalStats": True,
        "scope": scope,
        "limits": [],
        "tierLabel": "local",
        "authHelpText": "local",
        "todayPrompts": count,
        "todaySessions": count,
        "todayTotalTokens": count,
        "todayTokensByModel": {"m": count},
        "recentDays": [{"date": today, "messageCount": count}],
        "totalPrompts": count,
        "totalSessions": count,
        "activeDays": 1,
        "activeDates": [today],
        "modelUsage": {
            "m": {
                "inputTokens": count,
                "outputTokens": 0,
                "cacheReadInputTokens": 0,
                "cacheCreationInputTokens": 0,
            }
        },
    }


def snapshot_provider(provider_id: str, count_value: int, scope: str = "device") -> dict:
    return {
        **record(provider_id, count_value, scope),
        "providerId": provider_id,
        "providerName": provider_id.title(),
    }


def snapshot(device: str, updated: str, providers: dict, local_date: str | None = None) -> dict:
    return {
        "schemaVersion": 1,
        "deviceId": device,
        "updatedAt": updated,
        "localDate": local_date or dt.datetime.now().date().isoformat(),
        "providers": providers,
    }


def make_provider(
    path: Path,
    provider_id: str,
    *,
    sleep: float = 0,
    malformed: bool = False,
) -> None:
    body = (
        "print('not-json')"
        if malformed
        else f"print(json.dumps({record(provider_id)!r}))"
    )
    path.write_text(
        textwrap.dedent(
            f"""\
            #!/usr/bin/env python3
            import json, os, time
            time.sleep({sleep!r})
            open({str(path.parent.parent / 'flags')!r}, 'a').write({provider_id!r} + ':' + ' '.join(__import__('sys').argv[1:]) + '\\n')
            {body}
            """
        )
    )
    path.chmod(0o755)


def environment(tmp_path: Path, providers: Path | None = None) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "HOME": str(tmp_path / "home"),
            "XDG_STATE_HOME": str(tmp_path / "state"),
            "XDG_CACHE_HOME": str(tmp_path / "cache"),
            "XDG_CONFIG_HOME": str(tmp_path / "config"),
            "XDG_DATA_HOME": str(tmp_path / "data"),
            "FLAG_LOG": str(tmp_path / "flags"),
            "AI_USAGE_PROVIDER_DIR": str(providers or PROVIDERS),
            "CLAUDE_CONFIG_DIR": str(tmp_path / "home/.claude"),
            "CODEX_HOME": str(tmp_path / "home/.codex"),
            "FIREWORKS_AUTH_PATH": str(tmp_path / "home/.fireworks/auth.ini"),
        }
    )
    for name in (
        "FIREWORKS_API_KEY",
        "FIREWORKS_ACCOUNT_ID",
        "AI_USAGE_SYNC_DIR",
        "AI_USAGE_SYNC_FILE_NAME",
        "AI_USAGE_SYNC_DEVICE_ID",
        "AI_USAGE_PROVIDERS",
    ):
        env.pop(name, None)
    return env


class AiUsageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.tmp_path = Path(self.tempdir.name)

    def invoke(
        self,
        *args: str,
        env_extra: dict[str, str] | None = None,
        check: bool = True,
    ) -> tuple[subprocess.CompletedProcess[str], dict]:
        env = environment(self.tmp_path)
        env.update(env_extra or {})
        result = subprocess.run(
            [str(CLI), *args], env=env, text=True, capture_output=True
        )
        if check:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return result, json.loads(result.stdout)

    def test_update_concurrent_flags_retention_and_private_modes(self) -> None:
        providers = self.tmp_path / "providers"
        providers.mkdir()
        for provider_id in ("claude", "codex", "fireworks"):
            make_provider(providers / provider_id, provider_id, sleep=0.35)
        env = environment(self.tmp_path, providers)

        started = time.monotonic()
        first = subprocess.run(
            [str(CLI), "update", "--force", "--except", "fireworks"],
            env=env,
            text=True,
            capture_output=True,
        )
        elapsed = time.monotonic() - started
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
        self.assertLess(elapsed, 0.65, "provider collectors did not run concurrently")
        payload = json.loads(first.stdout)
        self.assertEqual(
            [item["id"] for item in payload["providers"]], ["claude", "codex"]
        )
        self.assertEqual(
            set((self.tmp_path / "flags").read_text().splitlines()),
            {"claude:--force", "codex:--force"},
        )
        usage = self.tmp_path / "state/quickshell/agents/usage"
        self.assertEqual(stat.S_IMODE(usage.stat().st_mode), 0o700)
        for path in usage.glob("*.json"):
            with self.subTest(path=path.name):
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

        # A malformed replacement reports an error while the valid record survives.
        make_provider(providers / "claude", "claude", malformed=True)
        failed = subprocess.run(
            [str(CLI), "update", "claude"],
            env=env,
            text=True,
            capture_output=True,
        )
        data = json.loads(failed.stdout)
        self.assertEqual(failed.returncode, 1)
        retained = next(
            item for item in data["providers"] if item["id"] == "claude"
        )
        self.assertEqual(retained["totalPrompts"], 1)
        self.assertEqual(
            data["errors"],
            [
                {
                    "id": "claude",
                    "message": "Provider collector returned invalid data",
                }
            ],
        )

    def test_enable_list_limits_only_and_numeric_validation(self) -> None:
        providers = self.tmp_path / "providers"
        providers.mkdir()
        for provider_id in ("claude", "codex", "fireworks"):
            make_provider(providers / provider_id, provider_id)
        env = environment(self.tmp_path, providers)
        env["AI_USAGE_PROVIDERS"] = "claude,codex"
        done = subprocess.run(
            [str(CLI), "refresh-limits", "codex"],
            env=env,
            text=True,
            capture_output=True,
        )
        self.assertEqual(done.returncode, 0, done.stderr + done.stdout)
        self.assertEqual(json.loads(done.stdout)["providers"][0]["id"], "codex")
        self.assertEqual((self.tmp_path / "flags").read_text(), "codex:--limits-only\n")

        # JSON's non-standard NaN and bools in numeric fields are rejected.
        for numeric_value in ("true", "NaN"):
            with self.subTest(numeric_value=numeric_value):
                (providers / "claude").write_text(
                    "#!/bin/sh\nprintf '%s\\n' "
                    f"'{{\"schemaVersion\":1,\"id\":\"claude\","
                    f"\"totalPrompts\":{numeric_value}}}'\n"
                )
                (providers / "claude").chmod(0o755)
                bad = subprocess.run(
                    [str(CLI), "update", "claude"],
                    env=env,
                    text=True,
                    capture_output=True,
                )
                self.assertEqual(bad.returncode, 1)
                self.assertEqual(
                    json.loads(bad.stdout)["errors"][0]["message"],
                    "Provider collector returned invalid data",
                )

    def test_sync_additive_account_max_union_models_and_bad_snapshots(self) -> None:
        env = environment(self.tmp_path)
        state = self.tmp_path / "state/quickshell/agents/usage"
        state.mkdir(parents=True)
        (state / "claude.json").write_text(json.dumps(record("claude", 2)))
        (state / "fireworks.json").write_text(
            json.dumps(record("fireworks", 4, "account"))
        )
        sync = self.tmp_path / "sync"
        sync.mkdir()
        today = dt.datetime.now().date().isoformat()
        other_day = (dt.datetime.now().date() - dt.timedelta(days=1)).isoformat()
        remote = {
            "schemaVersion": 1,
            "deviceId": "remote",
            "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
            "localDate": today,
            "providers": {
                "claude": {**record("claude", 3), "providerId": "claude", "providerName": "Claude"},
                "fireworks": {
                    **record("fireworks", 9, "account"),
                    "providerId": "fireworks", "providerName": "Fireworks",
                },
            },
        }
        remote["providers"]["claude"]["activeDates"] = [other_day]
        (sync / "remote.json").write_text(json.dumps(remote))
        (sync / "broken.json").write_text("{")
        (sync / "linked.json").symlink_to(sync / "remote.json")
        env.update(
            {
                "AI_USAGE_SYNC_DIR": str(sync),
                "AI_USAGE_SYNC_FILE_NAME": "local.json",
                "AI_USAGE_SYNC_DEVICE_ID": "local",
            }
        )
        result = subprocess.run(
            [str(CLI), "show"], env=env, text=True, capture_output=True
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        payload = json.loads(result.stdout)
        by_id = {item["id"]: item for item in payload["providers"]}
        self.assertEqual(by_id["claude"]["todayTotalTokens"], 5)
        # Account-scoped data is taken wholesale from the newest snapshot;
        # the just-written local value supersedes the older remote peak.
        self.assertEqual(by_id["fireworks"]["todayTotalTokens"], 4)
        self.assertEqual(by_id["claude"]["modelUsage"]["m"]["inputTokens"], 5)
        self.assertEqual(by_id["claude"]["activeDates"], sorted([today, other_day]))
        # Local account metadata is not merged.
        self.assertEqual(by_id["fireworks"]["tierLabel"], "local")
        self.assertEqual(payload["sync"]["deviceCount"], 2)
        self.assertEqual(payload["sync"]["devices"], ["local", "remote"])
        self.assertIn("Ignored 2 invalid usage snapshots", payload["sync"]["status"])
        self.assertEqual(stat.S_IMODE((sync / "local.json").stat().st_mode), 0o600)

    def test_sync_rejects_unsafe_name_and_directory_symlink(self) -> None:
        real = self.tmp_path / "real"
        real.mkdir()
        link = self.tmp_path / "link"
        link.symlink_to(real, target_is_directory=True)

        cases = (
            (
                {"AI_USAGE_SYNC_DIR": str(link)},
                "Usage sync directory is unsafe",
            ),
            (
                {
                    "AI_USAGE_SYNC_DIR": str(real),
                    "AI_USAGE_SYNC_FILE_NAME": "../bad.json",
                },
                "Usage sync filename is unsafe",
            ),
        )
        for env_extra, expected in cases:
            with self.subTest(expected=expected):
                _, data = self.invoke("show", env_extra=env_extra)
                self.assertEqual(data["sync"]["status"], expected)

    def test_provider_environment_is_deny_by_default_and_provider_specific(self) -> None:
        providers = self.tmp_path / "providers"
        providers.mkdir()
        expected = {
            "claude": {"CLAUDE_CONFIG_DIR"},
            "codex": {"CODEX_HOME"},
            "fireworks": {
                "FIREWORKS_API_KEY", "FIREWORKS_ACCOUNT_ID",
                "FIREWORKS_AUTH_PATH", "FIREWORKS_CONFIG_PATH",
            },
        }
        provider_only = set().union(*expected.values())
        logs = {}
        for provider_id in expected:
            log = self.tmp_path / f"{provider_id}-env.json"
            logs[provider_id] = log
            script = providers / provider_id
            script.write_text(textwrap.dedent(f"""\
                #!/usr/bin/env python3
                import json, os
                open({str(log)!r}, "w").write(json.dumps(dict(os.environ)))
                print(json.dumps({record(provider_id)!r}))
            """))
            script.chmod(0o755)
        env = environment(self.tmp_path, providers)
        env.update({
            "AWS_SECRET_ACCESS_KEY": "aws-secret",
            "GITHUB_TOKEN": "github-secret",
            "GOOGLE_APPLICATION_CREDENTIALS": "/secret/cloud.json",
            "OPENAI_API_KEY": "openai-secret",
            "ANTHROPIC_API_KEY": "anthropic-secret",
            "UNRELATED_TOKEN": "other-secret",
            "LC_SECRET": "locale-shaped-secret",
            "FIREWORKS_API_KEY": "fireworks-secret",
            "FIREWORKS_ACCOUNT_ID": "account",
            "FIREWORKS_CONFIG_PATH": str(self.tmp_path / "fw.json"),
        })
        done = subprocess.run([str(CLI), "update"], env=env, text=True, capture_output=True)
        self.assertEqual(done.returncode, 0, done.stderr + done.stdout)
        forbidden = {
            "AWS_SECRET_ACCESS_KEY", "GITHUB_TOKEN", "GOOGLE_APPLICATION_CREDENTIALS",
            "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "UNRELATED_TOKEN", "FLAG_LOG", "LC_SECRET",
        }
        for provider_id, log in logs.items():
            with self.subTest(provider=provider_id):
                received = json.loads(log.read_text())
                self.assertEqual(received["HOME"], env["HOME"])
                self.assertEqual(received["PATH"], env["PATH"])
                self.assertFalse(forbidden & received.keys())
                self.assertEqual(provider_only & received.keys(), expected[provider_id])

    def test_codex_expired_sign_in_message_survives_sanitization(self) -> None:
        providers = self.tmp_path / "providers"
        providers.mkdir()
        crafted = record("codex")
        crafted.update({
            "usageStatusText": "Codex sign-in expired",
            "authHelpText": "Run `codex login` to refresh your sign-in and restore limits.",
        })
        script = providers / "codex"
        script.write_text("#!/usr/bin/env python3\nimport json\nprint(json.dumps(" + repr(crafted) + "))\n")
        script.chmod(0o755)
        env = environment(self.tmp_path, providers)
        done = subprocess.run([str(CLI), "update", "codex"], env=env, text=True, capture_output=True)
        self.assertEqual(done.returncode, 0, done.stderr + done.stdout)
        output = json.loads(done.stdout)["providers"][0]
        self.assertEqual(output["usageStatusText"], "Codex sign-in expired")
        self.assertEqual(
            output["authHelpText"],
            "Run `codex login` to refresh your sign-in and restore limits.",
        )

    def test_provider_dto_strips_unknown_bounds_strings_and_rejects_bad_numbers(self) -> None:
        providers = self.tmp_path / "providers"
        providers.mkdir()
        env = environment(self.tmp_path, providers)
        crafted = record("claude")
        crafted.update({
            "name": "N" * 200 + "\x1b[31m",
            "unknownSecret": "do-not-retain",
            "authHelpText": "/home/alice/private/token.json\nsecret",
            "todayTokensByModel": {"m" * 200 + "\x00tail": 2},
            "modelUsage": {"m": {"inputTokens": 1, "unknownTokens": 99}},
            "limits": [{"label": "L" * 300, "percent": 0.5, "unknown": "x"}],
        })
        script = providers / "claude"
        script.write_text("#!/usr/bin/env python3\nimport json\nprint(json.dumps(" + repr(crafted) + "))\n")
        script.chmod(0o755)
        done = subprocess.run([str(CLI), "update", "claude"], env=env, text=True, capture_output=True)
        self.assertEqual(done.returncode, 0, done.stderr + done.stdout)
        output = json.loads(done.stdout)["providers"][0]
        self.assertNotIn("unknownSecret", output)
        self.assertLessEqual(len(output["name"]), 96)
        self.assertNotIn("\x1b", output["name"])
        self.assertNotIn("/home/alice", output["authHelpText"])
        self.assertEqual(len(next(iter(output["todayTokensByModel"]))), 128)
        self.assertEqual(output["modelUsage"]["m"], {"inputTokens": 1})
        self.assertEqual(set(output["limits"][0]), {"label", "percent"})
        self.assertEqual(len(output["limits"][0]["label"]), 128)
        retained = json.loads((self.tmp_path / "state/quickshell/agents/usage/claude.json").read_text())
        self.assertEqual(retained, output)

        bad_values = (
            {"totalPrompts": True},
            {"totalPrompts": -1},
            {"totalPrompts": 1 << 63},
            {"limits": [{"percent": 1.01}]},
            {"balance": {"remaining": -0.01}},
        )
        for changes in bad_values:
            with self.subTest(changes=changes):
                bad_record = record("codex")
                bad_record.update(changes)
                script = providers / "codex"
                script.write_text("#!/usr/bin/env python3\nimport json\nprint(json.dumps(" + repr(bad_record) + "))\n")
                script.chmod(0o755)
                failed = subprocess.run([str(CLI), "update", "codex"], env=env, text=True, capture_output=True)
                self.assertEqual(failed.returncode, 1)
                self.assertEqual(json.loads(failed.stdout)["errors"][-1]["message"], "Provider collector returned invalid data")

    def test_sync_duplicate_device_stale_today_and_normal_addition(self) -> None:
        env = environment(self.tmp_path)
        state = self.tmp_path / "state/quickshell/agents/usage"
        state.mkdir(parents=True)
        (state / "claude.json").write_text(json.dumps(record("claude", 2)))
        sync_dir = self.tmp_path / "sync"
        sync_dir.mkdir()
        today = dt.datetime.now().date().isoformat()
        yesterday = (dt.datetime.now().date() - dt.timedelta(days=1)).isoformat()
        old = snapshot("remote", "2030-01-01T00:00:00+00:00", {"claude": snapshot_provider("claude", 30)})
        newest_stats = snapshot_provider("claude", 3)
        newest_stats["activeDates"] = [yesterday]
        newest_stats["recentDays"] = [{"date": today, "messageCount": 3}, {"date": yesterday, "messageCount": 7}]
        newest = snapshot("remote", "2030-01-02T00:00:00Z", {"claude": newest_stats}, yesterday)
        (sync_dir / "old.json").write_text(json.dumps(old))
        (sync_dir / "new.json").write_text(json.dumps(newest))
        env.update({"AI_USAGE_SYNC_DIR": str(sync_dir), "AI_USAGE_SYNC_FILE_NAME": "local.json", "AI_USAGE_SYNC_DEVICE_ID": "local"})
        result = subprocess.run([str(CLI), "show"], env=env, text=True, capture_output=True, check=True)
        data = json.loads(result.stdout)
        claude = data["providers"][0]
        # The duplicate old file is ignored; stale all-time values remain but stale today is zero.
        self.assertEqual(claude["totalPrompts"], 5)
        self.assertEqual(claude["todayPrompts"], 2)
        self.assertEqual(claude["todayTokensByModel"], {"m": 2})
        recent = {row["date"]: row["messageCount"] for row in claude["recentDays"]}
        self.assertEqual(recent[today], 2)
        self.assertEqual(recent[yesterday], 7)
        self.assertEqual(claude["syncDevices"], ["local", "remote"])
        written = json.loads((sync_dir / "local.json").read_text())
        self.assertEqual(written["localDate"], today)
        self.assertEqual(dt.datetime.fromisoformat(written["updatedAt"]).utcoffset(), dt.timedelta(0))

    def test_sync_mixed_scopes_and_account_newest_decrease(self) -> None:
        state = self.tmp_path / "state/quickshell/agents/usage"
        state.mkdir(parents=True)
        sync_dir = self.tmp_path / "sync"
        sync_dir.mkdir()
        (state / "claude.json").write_text(json.dumps(record("claude", 2, "device")))
        (state / "fireworks.json").write_text(json.dumps(record("fireworks", 10, "account")))
        (sync_dir / "mixed.json").write_text(json.dumps(snapshot(
            "mixed", "2031-01-01T00:00:00Z",
            {"claude": snapshot_provider("claude", 50, "account")},
        )))
        (sync_dir / "account-old.json").write_text(json.dumps(snapshot(
            "billing", "2031-01-01T00:00:00Z",
            {"fireworks": snapshot_provider("fireworks", 20, "account")},
        )))
        (sync_dir / "account-new.json").write_text(json.dumps(snapshot(
            "billing", "2031-01-02T00:00:00Z",
            {"fireworks": snapshot_provider("fireworks", 3, "account")},
        )))
        env = environment(self.tmp_path)
        env.update({"AI_USAGE_SYNC_DIR": str(sync_dir), "AI_USAGE_SYNC_FILE_NAME": "local.json", "AI_USAGE_SYNC_DEVICE_ID": "local"})
        result = subprocess.run([str(CLI), "show"], env=env, text=True, capture_output=True, check=True)
        data = json.loads(result.stdout)
        by_id = {item["id"]: item for item in data["providers"]}
        self.assertEqual(by_id["claude"]["totalPrompts"], 2)
        self.assertNotIn("syncEnabled", by_id["claude"])
        self.assertIn("Ignored conflicting scope for claude", data["sync"]["status"])
        self.assertEqual(by_id["fireworks"]["totalPrompts"], 3)
        self.assertEqual(by_id["fireworks"]["syncDevices"], ["billing", "local"])
        self.assertEqual(by_id["fireworks"]["tierLabel"], "local")
        self.assertEqual(by_id["fireworks"]["authHelpText"], "Fireworks usage details are unavailable.")

    def test_sync_invalid_timestamp_malformed_overflow_and_read_bounds(self) -> None:
        state = self.tmp_path / "state/quickshell/agents/usage"
        state.mkdir(parents=True)
        (state / "claude.json").write_text(json.dumps(record("claude", MAX_TEST := (1 << 63) - 1)))
        sync_dir = self.tmp_path / "sync"
        sync_dir.mkdir()
        today = dt.datetime.now().date().isoformat()
        (sync_dir / "invalid-time.json").write_text(json.dumps({
            **snapshot("badtime", "not-a-time", {"claude": snapshot_provider("claude", 1)}),
        }))
        (sync_dir / "malformed.json").write_text("{")
        (sync_dir / "oversized.json").write_text("{}" + " " * (1024 * 1024))
        (sync_dir / "overflow.json").write_text(json.dumps(snapshot(
            "overflow", "2032-01-01T00:00:00Z",
            {"claude": snapshot_provider("claude", 1)}, today,
        )))
        # Stay below the file-count limit while exceeding the aggregate byte budget.
        padding = " " * 900_000
        for index in range(19):
            payload = snapshot(f"bulk{index}", f"2030-01-{index + 1:02d}T00:00:00Z", {})
            (sync_dir / f"bulk-{index:02d}.json").write_text(json.dumps(payload) + padding)
        env = environment(self.tmp_path)
        env.update({"AI_USAGE_SYNC_DIR": str(sync_dir), "AI_USAGE_SYNC_FILE_NAME": "local.json", "AI_USAGE_SYNC_DEVICE_ID": "local"})
        result = subprocess.run([str(CLI), "show"], env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        data = json.loads(result.stdout)
        self.assertEqual(data["providers"][0]["totalPrompts"], MAX_TEST)
        self.assertIn("invalid usage snapshot", data["sync"]["status"])
        self.assertIn("Ignored overflowing usage for claude", data["sync"]["status"])
        # Some bulk files fit, proving reads stop on total bytes rather than crashing.
        self.assertLess(data["sync"]["deviceCount"], 21)

    def test_sync_file_count_is_bounded(self) -> None:
        sync_dir = self.tmp_path / "sync"
        sync_dir.mkdir()
        for index in range(260):
            value = snapshot(f"device{index}", "2030-01-01T00:00:00Z", {})
            (sync_dir / f"device-{index:03d}.json").write_text(json.dumps(value))
        _, data = self.invoke(
            "show",
            env_extra={
                "AI_USAGE_SYNC_DIR": str(sync_dir),
                "AI_USAGE_SYNC_FILE_NAME": "local.json",
                "AI_USAGE_SYNC_DEVICE_ID": "local",
            },
        )
        self.assertLessEqual(data["sync"]["deviceCount"], 256)
        self.assertIn("Usage snapshot file limit reached", data["sync"]["status"])

    def test_claude_native_pi_omp_and_opencode_scanners(self) -> None:
        env = environment(self.tmp_path)
        home = Path(env["HOME"])
        today = dt.datetime.now().astimezone().isoformat()
        project = home / ".claude/projects/p"
        project.mkdir(parents=True)
        # Duplicate message ids are counted once, and all token categories survive.
        native = {
            "type": "assistant",
            "timestamp": today,
            "sessionId": "s",
            "message": {
                "role": "assistant",
                "id": "same",
                "model": "claude-native",
                "usage": {
                    "input_tokens": 2,
                    "output_tokens": 3,
                    "cache_read_input_tokens": 4,
                    "cache_creation_input_tokens": 5,
                },
            },
        }
        (project / "one.jsonl").write_text(
            json.dumps(native) + "\n" + json.dumps(native) + "\n"
        )
        for folder, model in ((".pi", "claude-pi"), (".omp", "claude-omp")):
            session = home / folder / "agent/sessions/p/a.jsonl"
            session.parent.mkdir(parents=True)
            session.write_text(
                json.dumps(
                    {
                        "type": "message",
                        "id": model,
                        "timestamp": today,
                        "message": {
                            "role": "assistant",
                            "provider": "anthropic",
                            "model": model,
                            "usage": {
                                "input": 1,
                                "output": 1,
                                "cacheRead": 1,
                                "cacheWrite": 1,
                            },
                        },
                    }
                )
                + "\n"
            )
        db = Path(env["XDG_DATA_HOME"]) / "opencode/opencode.db"
        db.parent.mkdir(parents=True)
        with contextlib.closing(sqlite3.connect(db)) as connection, connection:
            connection.execute("CREATE TABLE message(session_id TEXT, data TEXT)")
            connection.execute(
                "INSERT INTO message VALUES (?, ?)",
                (
                    "o",
                    json.dumps(
                        {
                            "role": "assistant",
                            "providerID": "anthropic",
                            "modelID": "x/claude-open",
                            "time": {"created": int(time.time() * 1000)},
                            "tokens": {
                                "input": 2,
                                "output": 2,
                                "reasoning": 1,
                                "cache": {"read": 1, "write": 1},
                            },
                        }
                    ),
                ),
            )
        result = subprocess.run(
            [str(PROVIDERS / "claude"), "--force"],
            env=env,
            text=True,
            capture_output=True,
            check=True,
        )
        data = json.loads(result.stdout)
        self.assertEqual(data["todayTotalTokens"], 29)
        self.assertEqual(data["totalPrompts"], 4)
        self.assertEqual(
            data["modelUsage"]["claude-native"],
            {
                "inputTokens": 2,
                "outputTokens": 3,
                "cacheReadInputTokens": 4,
                "cacheCreationInputTokens": 5,
            },
        )
        self.assertEqual(data["usageStatusText"], "Waiting for auth")

    def test_codex_native_pi_omp_opencode_and_limits_fixture(self) -> None:
        env = environment(self.tmp_path)
        home = Path(env["HOME"])
        today = dt.datetime.now().astimezone().isoformat()
        native = home / ".codex/sessions/today/a.jsonl"
        native.parent.mkdir(parents=True)
        native.write_text(
            "\n".join(
                [
                    json.dumps(
                        {"type": "turn_context", "payload": {"model": "gpt-native"}}
                    ),
                    json.dumps(
                        {
                            "timestamp": today,
                            "type": "event_msg",
                            "payload": {
                                "type": "token_count",
                                "info": {
                                    "last_token_usage": {
                                        "input_tokens": 10,
                                        "cached_input_tokens": 4,
                                        "cache_write_input_tokens": 0,
                                        "output_tokens": 3,
                                    }
                                },
                            },
                        }
                    ),
                ]
            )
            + "\n"
        )
        for folder, provider, api, model in (
            (".pi", "openai-codex", "", "gpt-pi"),
            (".omp", "custom", "openai-codex-responses", "gpt-omp"),
        ):
            path = home / folder / "agent/sessions/p/a.jsonl"
            path.parent.mkdir(parents=True)
            path.write_text(
                json.dumps(
                    {
                        "type": "message",
                        "id": model,
                        "timestamp": today,
                        "message": {
                            "role": "assistant",
                            "provider": provider,
                            "api": api,
                            "model": model,
                            "usage": {
                                "input": 1,
                                "output": 2,
                                "cacheRead": 3,
                                "cacheWrite": 4,
                            },
                        },
                    }
                )
                + "\n"
            )
        db = Path(env["XDG_DATA_HOME"]) / "opencode/opencode.db"
        db.parent.mkdir(parents=True)
        with contextlib.closing(sqlite3.connect(db)) as connection, connection:
            connection.execute("CREATE TABLE message(session_id TEXT, data TEXT)")
            connection.execute(
                "INSERT INTO message VALUES (?, ?)",
                (
                    "o",
                    json.dumps(
                        {
                            "role": "assistant",
                            "providerID": "openai",
                            "modelID": "x/gpt-open",
                            "time": {"created": int(time.time() * 1000)},
                            "tokens": {
                                "input": 2,
                                "output": 2,
                                "reasoning": 1,
                                "cache": {"read": 1, "write": 1},
                            },
                        }
                    ),
                ),
            )
        binary = self.tmp_path / "bin/codex"
        binary.parent.mkdir()
        binary.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import json, sys
                for line in sys.stdin:
                    request=json.loads(line); method=request.get('method'); ident=request.get('id')
                    if ident is None: continue
                    result={}
                    if method == 'account/read': result={'account': {'planType': 'pro'}}
                    if method == 'account/rateLimits/read': result={'rateLimits': {'primary': {'usedPercent': 25, 'windowDurationMins': 300, 'resetsAt': 2000000000}}}
                    print(json.dumps({'id': ident, 'result': result}), flush=True)
                """
            )
        )
        binary.chmod(0o755)
        env["PATH"] = str(binary.parent) + os.pathsep + env["PATH"]
        result = subprocess.run(
            [str(PROVIDERS / "codex"), "--force"],
            env=env,
            text=True,
            capture_output=True,
            check=True,
        )
        data = json.loads(result.stdout)
        self.assertEqual(data["todayTotalTokens"], 40)
        self.assertEqual(data["totalPrompts"], 4)
        self.assertEqual(
            set(data["modelUsage"]),
            {"gpt-native", "gpt-pi", "gpt-omp", "gpt-open"},
        )
        self.assertEqual(data["tierLabel"], "pro")
        self.assertEqual(data["limits"][0]["percent"], 0.25)

    def test_fireworks_fixture_token_categories_and_no_auth(self) -> None:
        isolated_env = environment(self.tmp_path)
        with mock.patch.dict(os.environ, isolated_env, clear=True):
            module = runpy.run_path(
                str(PROVIDERS / "fireworks"), run_name="collector_fixture"
            )
            today = dt.datetime.now().astimezone().date()
            stats = module["summarize_usage"](
                {
                    "serverlessCosts": [
                        {
                            "startTime": dt.datetime.combine(
                                today, dt.time.min
                            ).astimezone(dt.timezone.utc).isoformat(),
                            "group": {
                                "model_name": "accounts/x/models/deepseek-r1p2"
                            },
                            "promptTokens": 10,
                            "cachedPromptTokens": 4,
                            "completionTokens": 3,
                        }
                    ]
                },
                today,
            )
        self.assertEqual(stats["todayTotalTokens"], 13)
        self.assertEqual(
            stats["modelUsage"]["deepseek-r1.2"],
            {
                "inputTokens": 6,
                "outputTokens": 3,
                "cacheReadInputTokens": 4,
                "cacheCreationInputTokens": 0,
            },
        )
        result = subprocess.run(
            [str(PROVIDERS / "fireworks")],
            env=isolated_env,
            text=True,
            capture_output=True,
            check=True,
        )
        no_auth = json.loads(result.stdout)
        self.assertFalse(no_auth["ready"])
        self.assertEqual(no_auth["scope"], "account")
        self.assertIn("FIREWORKS_API_KEY", no_auth["authHelpText"])


if __name__ == "__main__":
    unittest.main()
