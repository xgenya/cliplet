#!/usr/bin/env python3
"""Run an isolated package startup check with a bounded lifetime."""
import pathlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
subprocess.run([str(app / "Contents/MacOS/ClipboardNative"), "--smoke-test"],
               cwd=app.parent, check=True, timeout=30)
