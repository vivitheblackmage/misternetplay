#!/usr/bin/env python3
"""Run a command and answer ssh/scp password prompts in it.

A MiSTer's root filesystem is read-only, so ssh-copy-id cannot store a key,
and a script without a terminal cannot answer ssh's password prompt. This
gives the command a pseudo-terminal and types the password whenever a line
ends in "password:".

  SSHPW=1 python3 -I tools/sshpw.py <command> [args...]

SSHPW is the password (MiSTer default: 1). tools/deploy.sh uses this by itself.
Exit status is the command's.
"""
import os, pty, select, sys, time

if len(sys.argv) < 2 or "SSHPW" not in os.environ:
    sys.exit(__doc__)

pw = os.environ["SSHPW"].encode()
timeout = float(os.environ.get("SSHPW_TIMEOUT", "1800"))

pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])

tail = b""
deadline = time.time() + timeout
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 1)
    if not r:
        continue
    try:
        data = os.read(fd, 4096)
    except OSError:          # child closed the terminal
        break
    if not data:
        break
    sys.stdout.write(data.decode(errors="replace"))
    sys.stdout.flush()
    tail = (tail + data)[-200:]
    if tail.lower().rstrip().endswith(b"password:"):
        os.write(fd, pw + b"\n")
        tail = b""
else:
    os.kill(pid, 9)
    print("sshpw: timed out after %d s" % timeout, file=sys.stderr)

_, status = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(status))
