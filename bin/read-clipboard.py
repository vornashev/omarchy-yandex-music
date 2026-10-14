#!/usr/bin/env python3
"""Read one Wayland text selection off the UI thread, with byte/time limits."""
import json
import os
import resource
import selectors
import signal
import subprocess
import sys
import time

MAX_BYTES = 16 * 1024
TIMEOUT = 1.0


def read_selection(primary=False):
    """Return UTF-8 only after EOF; never publish partial or oversized input."""
    command = ["wl-paste", "--no-newline", "--type", "text"]
    if primary:
        command.append("--primary")
    deadline = time.monotonic() + TIMEOUT
    with subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, start_new_session=True) as process:
        try:
            os.set_blocking(process.stdout.fileno(), False)
            data = bytearray()
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                while True:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or not selector.select(remaining):
                        raise ValueError("Clipboard timed out")
                    chunk = os.read(process.stdout.fileno(), min(4096, MAX_BYTES + 1 - len(data)))
                    if not chunk:
                        break
                    data.extend(chunk)
                    if len(data) > MAX_BYTES:
                        raise ValueError("Clipboard exceeds 16 KiB")
            remaining = deadline - time.monotonic()
            if remaining <= 0 or process.wait(timeout=remaining) != 0:
                raise ValueError("Clipboard unavailable")
            return data.decode("utf-8", errors="strict")
        finally:
            # wl-paste may fork a streaming copier; stop the entire isolated
            # group before reaping its leader, including on successful EOF.
            if process.returncode is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            process.wait()


def main():
    if sys.argv[1:] not in ([], ["--primary"]):
        return 2
    # Bound the receiver too, not just the pipe collected by this process.
    resource.setrlimit(resource.RLIMIT_AS, (128 * 1024 * 1024, 128 * 1024 * 1024))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    try:
        text = read_selection(bool(sys.argv[1:]))
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return 1
    print(json.dumps(text, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
