# at-terminal.py <answer> <cmd> [args...] — run cmd with a terminal (pty) on stdin and type
# <answer> + Enter into it: how the fixtures stand in for a USER at their own terminal (#348).
# <answer> "--silent" types nothing: a pty-backed agent harness whose terminal nobody answers.
# The child is killed after 60s (exit 124) so a prompt that never times out fails, not hangs.
# Exit 77 where Python has no pty (Windows / Git Bash): the caller skips the case.
import os, subprocess, sys
try:
    import pty
except ImportError:
    sys.exit(77)
master, slave = pty.openpty()
if sys.argv[1] != "--silent":
    os.write(master, (sys.argv[1] + "\n").encode())
p = subprocess.Popen(sys.argv[2:], stdin=slave)
try:
    rc = p.wait(timeout=60)
except subprocess.TimeoutExpired:
    p.kill(); p.wait(); rc = 124
os.close(slave); os.close(master)
sys.exit(rc)
