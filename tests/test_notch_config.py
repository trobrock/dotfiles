import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class NotchConfigTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads((ROOT / "dot-config/notch/config.json").read_text())

    def test_profiles_are_provider_isolated(self):
        for name, provider in (("personal", "openai-codex"), ("work", "anthropic")):
            profile = self.config["profiles"][name]
            self.assertEqual(profile["provider"], provider)
            self.assertEqual(profile["allowed_providers"], [provider])
            self.assertNotIn("credential_ref", profile)

    def test_each_profile_maps_the_full_team(self):
        expected = {
            "lead", "explorer", "researcher", "product", "architect", "designer", "developer",
            "qa", "reviewer", "security", "release", "documentation",
        }
        self.assertEqual(set(self.config["roles"]), expected)
        for profile in self.config["profiles"].values():
            self.assertEqual(set(profile["role_models"]), expected)

    def test_profiles_route_by_reasoning_tier(self):
        high = {"lead", "researcher", "product", "architect", "designer", "reviewer", "security"}
        medium = {"developer", "qa", "release"}
        low = {"explorer", "documentation"}
        for name, models in (
            ("personal", ("gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-luna")),
            ("work", ("claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5")),
        ):
            profile = self.config["profiles"][name]
            self.assertEqual(profile["model"], models[0])
            self.assertEqual(profile["thinking_level"], "high")
            for roles, model, thinking in (
                (high, models[0], "high"),
                (medium, models[1], "medium"),
                (low, models[2], "low"),
            ):
                for role in roles:
                    with self.subTest(profile=name, role=role):
                        self.assertEqual(profile["role_models"][role], model)
                        self.assertEqual(self.config["roles"][role]["thinking"], thinking)

    def test_explorer_and_researcher_remain_read_only(self):
        for name in ("explorer", "researcher"):
            self.assertIn("read-only", self.config["roles"][name]["instructions"])
        self.assertIn("deeper", self.config["roles"]["explorer"]["when_to_use"])
        self.assertIn("deep research", self.config["roles"]["researcher"]["when_to_use"])

    def test_roles_have_selection_guidance(self):
        for name, role in self.config["roles"].items():
            with self.subTest(role=name):
                guidance = role["when_to_use"]
                self.assertTrue(guidance.startswith("Use when "))
                self.assertLessEqual(len(guidance), 200)
                self.assertNotEqual(guidance, role["instructions"])

    def test_roles_have_instructions_without_hard_work_caps(self):
        for role in self.config["roles"].values():
            self.assertTrue(role["instructions"].strip())
            self.assertIn(role["thinking"], {"low", "medium", "high"})
            self.assertGreaterEqual(role["max_output_chars"], 1000)
            for limit in ("timeout_seconds", "max_turns", "max_cost_usd"):
                self.assertEqual(role.get(limit, 0), 0)


if __name__ == "__main__":
    unittest.main()
