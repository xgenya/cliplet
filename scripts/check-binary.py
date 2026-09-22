#!/usr/bin/env python3
"""Verify release architecture, deployment target and debug-symbol identity."""
import pathlib
import re
import subprocess
import sys

binary, symbols = map(pathlib.Path, sys.argv[1:3])

def output(*arguments):
    return subprocess.check_output(arguments, text=True)

def identities(path):
    text = output("xcrun", "dwarfdump", "--uuid", str(path))
    result = dict((architecture, uuid) for uuid, architecture in
                  re.findall(r"UUID: ([A-F0-9-]+) \(([^)]+)\)", text))
    assert result, f"No UUIDs found in {path}"
    return result

assert identities(binary) == identities(symbols), "dSYM does not match the executable"
assert set(identities(binary)) == {"arm64"}, "Release must contain only the Apple Silicon (arm64) architecture"
build_versions = output("xcrun", "vtool", "-show-build", str(binary))
minimums = re.findall(r"minos\s+([\d.]+)", build_versions)
assert minimums == ["14.0"], "Unexpected minimum macOS version"
sdks = re.findall(r"sdk\s+([\d.]+)", build_versions)
expected_sdk = output("xcrun", "--sdk", "macosx", "--show-sdk-version").strip()
assert sdks == [expected_sdk], "Linked SDK must match the build SDK"
assert int(expected_sdk.split(".")[0]) >= 26, "Liquid Glass requires building with macOS SDK 26 or later"
print("Apple Silicon architecture, deployment target, linked SDK and dSYM UUID verified")
