#!/usr/bin/env python3
"""Run a child with a wall-clock deadline and stdout/stderr byte ceilings.

Quickshell StdioCollector is unbounded. The marketplace requires the
producer to stop first so a hung or chatty windscribe-cli cannot grow
the long-lived shell without limit.
"""
from __future__ import annotations

import subprocess
import sys

DEADLINE_SEC = 20
MAX_STDOUT = 64 * 1024
MAX_STDERR = 16 * 1024


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    cmd = sys.argv[1:]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=DEADLINE_SEC)
        sys.stdout.buffer.write(proc.stdout[:MAX_STDOUT])
        sys.stderr.buffer.write(proc.stderr[:MAX_STDERR])
        return int(proc.returncode)
    except subprocess.TimeoutExpired as exc:
        sys.stdout.buffer.write((exc.stdout or b"")[:MAX_STDOUT])
        sys.stderr.buffer.write((exc.stderr or b"")[:MAX_STDERR])
        return 124


if __name__ == "__main__":
    raise SystemExit(main())
