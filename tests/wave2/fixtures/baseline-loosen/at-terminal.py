# at-terminal.py <answer> <cmd> [args...] — run cmd with a terminal (pty) on stdin and type
# <answer> + Enter into it: how the fixtures stand in for a USER at their own terminal (#348).
# Exit 77 where Python has no pty (Windows / Git Bash): the caller skips the case.
import os, subprocess, sys
try:
    import pty
except ImportError:
    sys.exit(77)
master, slave = pty.openpty()
os.write(master, (sys.argv[1] + "\n").encode())
rc = subprocess.call(sys.argv[2:], stdin=slave)
os.close(slave); os.close(master)
sys.exit(rc)
