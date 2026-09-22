#!/usr/bin/env python3
"""Run the publisher's draft step against a synthetic GitHub CLI."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parent.parent
TAG = "v0.6.0"


class ReleaseDraftTests(unittest.TestCase):
    def run_draft_step(self, releases, *, api_error=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = root / "state.json"
            state.write_text(json.dumps({"releases": releases, "calls": [], "api_error": api_error}))
            gh = root / "gh"
            gh.write_text("#!/usr/bin/env python3\n" + textwrap.dedent('''\
                import json, os, sys
                from pathlib import Path
                path = Path(os.environ["TEST_RELEASE_STATE"])
                state = json.loads(path.read_text())
                args = sys.argv[1:]
                state["calls"].append(args)
                path.write_text(json.dumps(state))
                if args[0] == "api":
                    endpoint = args[1]
                    if state["api_error"]:
                        sys.exit(1)
                    if "/releases?" in endpoint:
                        from urllib.parse import parse_qs
                        query = parse_qs(endpoint.split("?", 1)[1])
                        page = int(query["page"][0])
                        print(json.dumps(state["releases"][(page-1)*100:page*100]))
                    elif "/releases/tags/" in endpoint:
                        # GitHub's tag endpoint excludes drafts, even for writers.
                        print("Not Found", file=sys.stderr)
                        sys.exit(1)
                    else:
                        raise SystemExit("Unexpected API endpoint")
                elif args[:2] == ["release", "create"]:
                    state["releases"].insert(0, {"id": 42, "tag_name": args[2], "draft": True})
                    path.write_text(json.dumps(state))
                elif args[:2] != ["release", "edit"]:
                    raise SystemExit("Unexpected CLI command")
                '''))
            gh.chmod(0o755)
            curl = root / "curl"
            curl.write_text("#!/usr/bin/env python3\n" + textwrap.dedent('''\
                import json, os, sys
                from pathlib import Path
                state = json.loads(Path(os.environ["TEST_RELEASE_STATE"]).read_text())
                release = next((r for r in state["releases"]
                                if r["tag_name"] == os.environ["RELEASE_TAG"] and not r["draft"]), None)
                Path(sys.argv[sys.argv.index("--output") + 1]).write_text(json.dumps(release))
                print("503" if state["api_error"] else "200" if release else "404", end="")
                '''))
            curl.chmod(0o755)
            (root / "release-notes.md").write_text("Synthetic release notes\n")
            output = root / "env"
            output.touch()
            workflow = (ROOT / ".github/workflows/publish.yml").read_text()
            step = workflow.split("      - name: Create or resume draft\n", 1)[1]
            step = step.split("      - name:", 1)[0].split("        run: |\n", 1)[1]
            result = subprocess.run(
                ["/bin/bash", "-c", textwrap.dedent(step)],
                env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}",
                     "TEST_RELEASE_STATE": str(state), "RUNNER_TEMP": str(root),
                     "GITHUB_ENV": str(output), "GITHUB_REPOSITORY": "example/crawlbar",
                     "GH_TOKEN": "synthetic-test-token", "GITHUB_API_URL": "https://api.example.invalid",
                     "RELEASE_TAG": TAG},
                capture_output=True, text=True,
            )
            return result, output.read_text(), json.loads(state.read_text())["calls"]

    def test_existing_draft_on_later_page_is_resumed_by_id(self):
        releases = [{"id": n + 100, "tag_name": f"v1.0.{n}", "draft": False} for n in range(100)]
        releases.append({"id": 42, "tag_name": TAG, "draft": True})
        result, output, calls = self.run_draft_step(releases)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("RELEASE_ID=42\n", output)
        self.assertTrue(any("page=2" in call[1] for call in calls if call[0] == "api"))
        self.assertFalse(any(call[:2] == ["release", "create"] for call in calls))
        self.assertTrue(any(call[:2] == ["release", "edit"] for call in calls))

    def test_absent_release_is_created_and_its_id_retained(self):
        result, output, calls = self.run_draft_step([])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("RELEASE_ID=42\n", output)
        self.assertEqual(sum(call[:2] == ["release", "create"] for call in calls), 1)

    def test_published_release_cannot_be_changed(self):
        result, output, calls = self.run_draft_step([{"id": 42, "tag_name": TAG, "draft": False}])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output, "")
        self.assertFalse(any(call[0] == "release" for call in calls))

    def test_api_failure_never_creates_a_release(self):
        result, output, calls = self.run_draft_step([], api_error=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output, "")
        self.assertFalse(any(call[0] == "release" for call in calls))


if __name__ == "__main__":
    unittest.main()
