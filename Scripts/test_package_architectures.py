#!/usr/bin/env python3
"""Exercise release architecture guards without signing credentials or builds."""

import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


class PackageArchitecturesTest(unittest.TestCase):
    def test_invalid_options_fail_before_packaging(self):
        for script in ("package_app.sh", "package_release.sh", "verify_release.sh"):
            for args in (("--arch",), ("--arch", "i386"), ("--arch", "arm64", "extra", "extra")):
                with self.subTest(script=script, args=args):
                    result = subprocess.run(
                        ["/bin/bash", str(ROOT / "Scripts" / script), *args],
                        capture_output=True,
                        text=True,
                    )
                    self.assertNotEqual(result.returncode, 0)

    def test_both_executables_require_exact_architectures(self):
        with tempfile.TemporaryDirectory(prefix="crawlbar-architecture-test-") as temporary:
            directory = Path(temporary)
            app = directory / "CrawlBar.app"
            contents = app / "Contents"
            for relative in ("MacOS/CrawlBar", "Helpers/crawlbar"):
                executable = contents / relative
                executable.parent.mkdir(parents=True, exist_ok=True)
                executable.touch()
            version = next(
                line.split("=", 1)[1].strip('"')
                for line in (ROOT / "version.env").read_text().splitlines()
                if line.startswith("CRAWLBAR_VERSION=")
            )
            (contents / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "com.vincentkoc.CrawlBar",
                "CFBundleShortVersionString": version,
            }))
            tools = directory / "bin"
            tools.mkdir()
            # Isolate the architecture guard from credential-only identity
            # checks. Real packaged-app signatures are verified separately.
            (tools / "codesign").write_text(
                "#!/bin/sh\n"
                "echo 'Authority=Developer ID Application: OpenClaw Foundation (FWJYW4S8P8)'\n"
                "echo 'TeamIdentifier=FWJYW4S8P8'\n"
                "echo 'Identifier=com.vincentkoc.CrawlBar'\n"
                "echo 'CodeDirectory v=20500 size=123 flags=0x10000(runtime)'\n"
            )
            (tools / "lipo").write_text(
                '#!/bin/sh\ncase "$2" in\n'
                '  */Helpers/*) echo "$TEST_HELPER_ARCH" ;;\n'
                '  *) echo "$TEST_APP_ARCH" ;;\nesac\n'
            )
            for tool in tools.iterdir():
                tool.chmod(0o755)
            for selected, expected in (("arm64", "arm64"), ("x86_64", "x86_64"), ("universal", "arm64 x86_64")):
                for app_arch, helper_arch, succeeds in (
                    (expected, expected, True),
                    (expected, "arm64e", False),
                    ("arm64e", expected, False),
                    (expected + " arm64e", expected, False),
                ):
                    with self.subTest(selected=selected, app=app_arch, helper=helper_arch):
                        result = subprocess.run(
                            ["/bin/bash", str(ROOT / "Scripts/verify_release.sh"), "--arch", selected, str(app)],
                            env={**os.environ, "PATH": f"{tools}:{os.environ['PATH']}", "TEST_APP_ARCH": app_arch, "TEST_HELPER_ARCH": helper_arch},
                            capture_output=True,
                            text=True,
                        )
                        self.assertEqual(result.returncode == 0, succeeds, result.stderr)


if __name__ == "__main__":
    unittest.main()
