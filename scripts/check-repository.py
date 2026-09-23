#!/usr/bin/env python3
"""Check portable repository invariants without installing developer tooling."""
import json
import pathlib
import plistlib
import re
import subprocess

root = pathlib.Path(__file__).resolve().parent.parent
version = (root / "VERSION").read_text().strip()
assert re.fullmatch(r"\d+\.\d+\.\d+", version), "VERSION must be MAJOR.MINOR.PATCH"
with (root / "Resources/Info.plist").open("rb") as stream:
    plist = plistlib.load(stream)
assert plist["LSMinimumSystemVersion"] == "14.0"
assert plist["CFBundleIdentifier"] == "com.clipboardnative.macos"
for fixture in (root / "Tests/ClipletTests/Fixtures").glob("*.json"):
    json.loads(fixture.read_text())
for script in (root / "scripts").glob("*.sh"):
    subprocess.run(["zsh", "-n", str(script)], check=True)
assert "Package.resolved" not in (root / ".gitignore").read_text().splitlines()
assert (root / "LICENSE").read_text().startswith("MIT License")
print("Repository checks passed")
