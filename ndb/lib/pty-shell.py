#!/usr/bin/env python3
"""Termdebug startup shell: leave its program PTY unowned for the inferior.

Neovim makes terminal jobs session leaders with a controlling terminal. The
bundled Termdebug's idle `tail` therefore owns the PTY that GDB later tries to
claim for the inferior. Detach only that helper, not GDB or the MI transport.
All other shell commands are forwarded to the original Neovim shell.
"""
import fcntl
import os
from pathlib import Path
import shlex
import signal
import select
import sys
import termios


if sys.argv[1:] == ["-c", "tail -f /dev/null;#gdb program"]:
    # TIOCNOTTY sends SIGHUP to the former foreground process group. Survive our
    # own detach, then restore normal hangup handling for Neovim's job cleanup.
    previous = signal.signal(signal.SIGHUP, signal.SIG_IGN)
    fcntl.ioctl(0, termios.TIOCNOTTY)
    signal.signal(signal.SIGHUP, previous)
    Path(os.environ["NDB_PTY_READY"]).touch()
    # Without a controlling terminal this helper no longer receives the PTY's
    # hangup signal. Watch for master closure instead, without reading stdin
    # (which belongs to the inferior), so quitting/crashing Neovim cannot leak it.
    poller = select.poll()
    poller.register(0, select.POLLHUP | select.POLLERR)
    poller.poll()
else:
    shell = shlex.split(os.environ["NDB_ORIGINAL_SHELL"])
    os.execvp(shell[0], shell + sys.argv[1:])
