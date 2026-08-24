#!/usr/bin/env python3
"""Run a child with a wall-clock deadline and live stdout/stderr ceilings.

Quickshell StdioCollector is unbounded. Caps must be applied while reading so
a hung or chatty windscribe-cli cannot grow this wrapper or the shell.

The child is started in its own session so timeout/overflow can SIGKILL the
whole process group, including grandchildren.
"""
from __future__ import annotations

import os
import select
import signal
import subprocess
import sys
import time

DEADLINE_SEC = 20
MAX_STDOUT = 64 * 1024
MAX_STDERR = 16 * 1024
READ_CHUNK = 8192


def _kill(proc: subprocess.Popen[bytes]) -> None:
    # start_new_session makes the child the group leader (pgid == pid).
    # Kill the group even if the leader already exited so grandchildren die.
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        if proc.poll() is None:
            proc.kill()
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            proc.wait()
        except ProcessLookupError:
            pass
    except ProcessLookupError:
        pass


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
        start_new_session=True,
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
        _kill(proc)

    sys.stdout.buffer.write(out_buf)
    sys.stderr.buffer.write(err_buf)

    if timed_out:
        return 124
    if overflow:
        return 1
    rc = proc.poll()
    if rc is None:
        return int(proc.wait())
    return int(rc)


if __name__ == "__main__":
    raise SystemExit(main())
