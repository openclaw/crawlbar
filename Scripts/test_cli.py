#!/usr/bin/env python3
"""Exercise crawler CLI contracts with a synthetic home and no saved credentials."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    binary = str(Path(sys.argv[1]).resolve())
    failures = []

    def expect(condition, message):
        if not condition:
            failures.append(message)

    with tempfile.TemporaryDirectory(prefix="crawlbar-cli-test-") as temporary:
        home = Path(temporary)
        manifests = home / "manifests"
        manifests.mkdir()
        config_path = home / ".crawlbar/config.json"
        config_path.parent.mkdir()
        native = home / "fixture.toml"
        credential = "opaque-fixture-value"
        native.write_text('[auth]\ncredential = "' + credential + '"\n[settings]\nlabel = "original"\n')
        crawler = home / "fixturecrawl"
        crawler.write_text(
            '#!/bin/sh\n'
            'if [ "$1" = status ]; then\n'
            '  printf \'%s\\n\' \'{"state":"current","summary":"Fixture ready"}\'\n'
            '  exit 0\n'
            'fi\n'
            'if [ "$1" = query ] && [ "$2" != needle ]; then exit 42; fi\n'
            'if [ "$FIXTURE_CREDENTIAL" != "opaque-fixture-value" ]; then\n'
            '  echo "fixture credential missing" >&2\n'
            '  exit 41\n'
            'fi\n'
            'printf \'%s\\n\' "$FIXTURE_CREDENTIAL"\n'
        )
        crawler.chmod(0o755)
        manifest = {
            "id": "fixture", "display_name": "Fixture", "binary": {"name": str(crawler)},
            "paths": {"default_config": str(native)},
            "commands": {"status": ["status"], "doctor": ["doctor"], "query": ["query"]},
            "capabilities": ["status", "doctor", "search"],
            "config_options": [
                {"id": "credential", "kind": "secret", "env_var": "FIXTURE_CREDENTIAL", "config_key": "auth.credential"},
                {"id": "label", "config_key": "settings.label"},
            ],
        }
        (manifests / "fixture.json").write_text(json.dumps(manifest))
        config = {"version": 3, "manifest_directories": [str(manifests)], "apps": []}
        config_path.write_text(json.dumps(config))
        environment = {"PATH": "/usr/bin:/bin", "CFFIXED_USER_HOME": str(home)}

        def run(*arguments):
            return subprocess.run([binary, *arguments], env=environment, capture_output=True, text=True, timeout=15)

        # Refuse all writes unless Foundation is using the disposable home.
        if run("config", "path").stdout.strip() != str(config_path):
            raise RuntimeError("CLI did not select the isolated configuration")
        metadata = run("metadata", "--json")
        metadata.check_returncode()
        config["apps"] = [
            {"id": row["id"], "enabled": False, "show_in_menu_bar": False}
            for row in json.loads(metadata.stdout) if row["id"] != "fixture"
        ]
        config_path.write_text(json.dumps(config))

        query = run("query", "--app", "fixture", "--json", "--", "needle")
        expect(query.returncode == 0, "query loads native execution credentials")
        expect(credential not in query.stdout + query.stderr, "query output redacts injected credentials")
        if query.returncode == 0:
            expect("[REDACTED]" in json.loads(query.stdout)[0]["stdout"], "query preserves redacted command output")
        doctor = run("doctor", "--app", "fixture", "--json")
        expect(doctor.returncode == 0 and credential not in doctor.stdout, "ordinary actions retain credential handling")

        updated = run("config", "set", "--app", "fixture", "--key", "label", "--value", "changed")
        expect(updated.returncode == 0, "config set accepts discovered crawlers without a saved app row")
        value = run("config", "get", "--app", "fixture", "--key", "label", "--json")
        expect(value.returncode == 0 and json.loads(value.stdout)[0].get("value") == "changed", "custom crawler configuration round-trips")
        literal = run("config", "set", "--app=fixture", "--key=label", "--value=--json")
        expect(literal.returncode == 0, "attached option values preserve flag-like text")
        literal_value = run("config", "get", "--app", "fixture", "--key", "label", "--json")
        expect(literal_value.returncode == 0 and json.loads(literal_value.stdout)[0].get("value") == "--json",
               "flag-like configuration values round-trip")
        cleared = run("config", "set", "--app", "fixture", "--key", "label", "--value", "")
        expect(cleared.returncode == 0, "an explicitly empty value still clears configuration")
        empty = run("config", "get", "--app", "fixture", "--key", "label", "--json")
        expect(empty.returncode == 0 and json.loads(empty.stdout)[0].get("value") is None, "cleared values are removed")
        expect(credential in native.read_text(), "editing nonsecret values preserves native credentials")
        expect(credential not in config_path.read_text(), "native credentials stay out of main configuration")

        for arguments in [
            ("status", "--app"),
            ("config", "get", "--app", "fixture", "--key"),
            ("dev", "register", "--app", "fixture", "--binary"),
            ("config", "set", "--app", "fixture", "--key", "label", "--value"),
        ]:
            for suffix in [(), ("--json",)]:
                result = run(*arguments, *suffix)
                expect(result.returncode != 0 and not result.stdout and "requires a value" in result.stderr,
                       "missing option values fail before command execution: " + arguments[-1] + str(suffix))

        persisted = json.loads(config_path.read_text())
        persisted["apps"].append({"id": "orphan", "config_values": {"label": "old"}})
        config_path.write_text(json.dumps(persisted))
        orphan = run("config", "set", "--app", "orphan", "--key", "label", "--value", "kept")
        expect(orphan.returncode == 0, "existing orphaned configuration remains editable")
        saved = json.loads(config_path.read_text())
        expect(next(row for row in saved["apps"] if row["id"] == "orphan")["config_values"]["label"] == "kept",
               "orphaned configuration updates persist")
        unknown = run("config", "set", "--app", "unknown", "--key", "label", "--value", "invalid")
        expect(unknown.returncode != 0, "unknown crawlers still fail configuration writes")

    for failure in failures:
        print("FAIL: " + failure, file=sys.stderr)
    if failures:
        return 1
    print("crawlbar CLI contracts ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
