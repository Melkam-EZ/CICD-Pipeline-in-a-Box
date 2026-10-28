"""Sanity tests for the repo itself (layout, scripts, config). Run from the repo root:
    python3 -m unittest discover -s tests -v
"""
import importlib.util
import os
import re
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

REQUIRED_FILES = [
    "README.md", "STEPS.md", "DIAGRAM_PROMPT.md", ".gitignore", ".gitattributes",
    ".env.example", "docker-compose.yml",
    "runner/Dockerfile", "runner/config.yaml",
    "sample-app/Dockerfile", "sample-app/app/main.py", "sample-app/tests/test_app.py",
    "sample-app/deploy/deploy.sh", "sample-app/.gitea/workflows/pipeline.yaml",
    "scripts/lib.sh", "scripts/setup.sh", "scripts/preflight.sh", "scripts/up.sh",
    "scripts/smoke.sh", "scripts/demo.sh", "scripts/destroy.sh",
]
SCRIPTS = [f for f in REQUIRED_FILES if f.endswith(".sh")]


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        return fh.read()


class LayoutTests(unittest.TestCase):
    def test_required_files_exist(self):
        for rel in REQUIRED_FILES:
            self.assertTrue(os.path.isfile(os.path.join(ROOT, rel)), f"missing {rel}")

    def test_scripts_have_shebang_and_strict_mode(self):
        for rel in SCRIPTS:
            text = read(rel)
            self.assertTrue(text.startswith("#!/usr/bin/env bash"), rel)
            if not rel.endswith("lib.sh"):
                self.assertRegex(text, r"set -[eu]*o? ?pipefail|set -[a-z]*u[a-z]*o pipefail", rel)

    def test_no_crlf_line_endings(self):
        for rel in SCRIPTS + ["docker-compose.yml"]:
            with open(os.path.join(ROOT, rel), "rb") as fh:
                self.assertNotIn(b"\r\n", fh.read(), rel)


class ConfigTests(unittest.TestCase):
    @unittest.skipUnless(importlib.util.find_spec("yaml"), "PyYAML not installed")
    def test_yaml_files_parse(self):
        import yaml
        for rel in ["docker-compose.yml", "runner/config.yaml",
                    "sample-app/.gitea/workflows/pipeline.yaml"]:
            with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
                self.assertIsInstance(yaml.safe_load(fh), dict, rel)

    def test_compose_has_three_services_bound_to_localhost(self):
        text = read("docker-compose.yml")
        for svc in ("gitea:", "registry:", "runner:"):
            self.assertIn(f"  {svc}", text)
        for line in re.findall(r'-\s*"(\d+\.\d+\.\d+\.\d+:)?\d+:\d+"', text):
            self.assertEqual(line, "127.0.0.1:", "port published on a non-localhost address")
        self.assertNotIn('"0.0.0.0:', text)

    def test_pipeline_uses_registered_runner_label(self):
        self.assertIn("runs-on: host", read("sample-app/.gitea/workflows/pipeline.yaml"))
        self.assertIn("GITEA_RUNNER_LABELS: host:host", read("docker-compose.yml"))

    def test_steps_file_covers_chmod_and_security_group(self):
        steps = read("STEPS.md")
        self.assertIn("chmod +x scripts/*.sh", steps)
        self.assertIn("sample-app/deploy/*.sh", steps)
        self.assertRegex(steps, r"(?i)security group")
        self.assertRegex(steps, r"(?i)port 22")


if __name__ == "__main__":
    unittest.main()
