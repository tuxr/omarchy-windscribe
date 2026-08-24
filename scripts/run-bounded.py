#!/usr/bin/env python3
"""Run a child with a wall-clock deadline and live stdout/stderr ceilings.

Quickshell StdioCollector is unbounded. Caps must be applied while reading so
a hung or chatty windscribe-cli cannot grow this wrapper or the shell.
"""
from __future__ import annotations

import os
import select
import subprocess
import sys
import time

DEADLINE_SEC = 20
MAX_STDOUT = 64 * 1024
MAX_STDERR = 16 * 1024
READ_CHUNK = 8192


def _kill(proc: subprocess.Popen[bytes]) -> None:
    if proc.poll() is not None:
        return
    proc.kill()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.wait()


def _take(buf: bytearray, chunk: bytes, limit: int) -> bool:
    room = limit - len(buf)
    if room > 0:
        buf.extend(chunk[:room])
    return len(chunk) > room


def main() -> int:
    if len(sys.argv) < 2:
        return 2

    proc = subprocess.Popen(
        sys.argv[1:],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
    )
    assert proc.stdout is not None
    assert proc.stderr is not None

    out_buf = bytearray()
    err_buf = bytearray()
    out_open = True
    err_open = True
    deadline = time.monotonic() + DEADLINE_SEC
    overflow = False
    timed_out = False

    try:
        while out_open or err_open:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                timed_out = True
                _kill(proc)
                break

            watch = []
            if out_open:
                watch.append(proc.stdout)
            if err_open:
                watch.append(proc.stderr)
            ready, _, _ = select.select(watch, [], [], min(0.2, remaining))

            if not ready:
                if proc.poll() is not None:
                    # Child exited; one last non-blocking drain.
                    ready = watch
                else:
                    continue

            for stream in ready:
                chunk = os.read(stream.fileno(), READ_CHUNK)
                if not chunk:
                    if stream is proc.stdout:
                        out_open = False
                    else:
                        err_open = False
                    continue
                if stream is proc.stdout:
                    overflow = _take(out_buf, chunk, MAX_STDOUT) or overflow
                else:
                    overflow = _take(err_buf, chunk, MAX_STDERR) or overflow

            if overflow:
                _kill(proc)
                break
    finally:
        if proc.poll() is None:
            _kill(proc)

    sys.stdout.buffer.write(out_buf)
    sys.stderr.buffer.write(err_buf)

    if timed_out:
        return 124
    if overflow:
        return 1
    return int(proc.wait())


if __name__ == "__main__":
    raise SystemExit(main())
