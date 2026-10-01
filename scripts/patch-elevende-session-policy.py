#!/usr/bin/env python3
"""Apply the WinduxEdu Live/installed ElevenDE login policy to a build copy.

ElevenDE 3.6 restructured the session script (helpers became functions, the
shell is supervised with a restart cap and the cleanup block moved into
session_cleanup), so every hunk either targets the layout it finds or verifies
that the pinned upstream already provides the behaviour WinduxEdu used to add.
"""
from __future__ import annotations

import sys
from pathlib import Path

path = Path(sys.argv[1]) if len(sys.argv) == 2 else None
if path is None or not path.is_file():
    raise SystemExit("usage: patch-elevende-session-policy.py PATH/TO/session/elevende-session")

HELPER_STOP = '''    # WinduxEdu session helpers (touch mapping, screen keyboard, Seewo
    # toolbar) write a pid file; only signal a process that is still that
    # helper, never a recycled pid.
    for h in winduxedu-touch-fix winduxedu-oskd winduxedu-seewo-toolbar; do
        [ -f "/tmp/winduxedu-$h.pid" ] || continue
        hpid="$(cat "/tmp/winduxedu-$h.pid" 2>/dev/null)"
        if [ -n "$hpid" ] && [ -r "/proc/$hpid/cmdline" ] && \\
                grep -aq "winduxedu-$h" "/proc/$hpid/cmdline" 2>/dev/null; then
            kill "$hpid" 2>/dev/null
        fi
        rm -f "/tmp/winduxedu-$h.pid"
    done
'''

old = '''if [ -x /usr/local/bin/elevende-lock ]; then
    echo "elevende-session: login gate"
    /usr/local/bin/elevende-lock --login || true
    echo "elevende-session: unlocked"
fi
'''
new = '''# WINDUXEDU session helpers start before the login gate: the screen keyboard
# has to be available while the lock screen asks for a password, and the
# touchscreen mapping must be in place before anyone touches the display.
start_winduxedu_helpers() {
    for h in winduxedu-touch-fix winduxedu-oskd winduxedu-seewo-toolbar; do
        [ -x "/usr/local/bin/$h" ] || continue
        echo "winduxedu: starting $h"
        /usr/local/bin/$h >>"/tmp/winduxedu-$h.log" 2>&1 &
        echo "$!" >"/tmp/winduxedu-$h.pid"
    done
}
start_winduxedu_helpers

# WINDUXEDU-SESSION-POLICY: Live media enters its disposable user session
# directly. Installed systems retain ElevenDE's own Win11-style login gate;
# no external display-manager greeter is involved.
if [ "${WINDUXEDU_LIVE_SESSION:-0}" != "1" ] && [ ! -d /run/live ] && \\
        [ -x /usr/local/bin/elevende-lock ]; then
    echo "elevende-session: ElevenDE native login gate"
    /usr/local/bin/elevende-lock --login || true
    echo "elevende-session: unlocked"
else
    echo "elevende-session: Live session bypasses the login gate"
fi
'''
text = path.read_text(encoding="utf-8")
if "WINDUXEDU-SESSION-POLICY" in text:
    raise SystemExit("WinduxEdu session policy is already present")
if old not in text:
    raise SystemExit("ElevenDE login gate marker was not found")
text = text.replace(old, new, 1)

# Shell startup: ElevenDE 3.6 supervises the shell from a capped restart loop
# in the session script itself, which already provides the "no restart storm"
# guarantee this hunk used to add.
old_shell = '''echo "elevende-session: starting shell"
/usr/local/bin/elevende-shell >/tmp/elevende-shell.log 2>&1 &
SHELL_PID=$!
'''
new_shell = '''echo "elevende-session: starting shell"
# The shell owns the desktop, taskbar and desktop icons.  It must remain a
# single long-lived process: restarting it from a tight loop during RandR
# transitions repeatedly recreates the taskbar and can leave temporary blank
# icon surfaces.  Exit diagnostics stay in /tmp/elevende-shell.log for the
# session-level recovery path rather than inducing a restart storm here.
/usr/local/bin/elevende-shell >/tmp/elevende-shell.log 2>&1 &
SHELL_PID=$!
'''
if old_shell in text:
    text = text.replace(old_shell, new_shell, 1)
elif "SHELL_TRY" in text and "-lt 3" in text:
    # ElevenDE 3.6 already restarts the shell at most three times per session.
    pass
else:
    raise SystemExit("ElevenDE shell startup marker was not found")

old_dbus = '''export DBUS_SESSION_BUS_ADDRESS
export DBUS_SESSION_BUS_PID
'''
new_dbus = '''export DBUS_SESSION_BUS_ADDRESS
export DBUS_SESSION_BUS_PID

# loginctl power, suspend and reboot actions need a desktop polkit agent.  Do
# not bypass authorization with sudo or a policy relaxation; run the standard
# agent inside the user session so approved actions get a visible prompt.
POLKIT_PID=""
if command -v lxqt-policykit-agent >/dev/null 2>&1; then
    lxqt-policykit-agent >/tmp/elevende-polkit.log 2>&1 &
    POLKIT_PID=$!
fi
'''
if old_dbus not in text:
    raise SystemExit("ElevenDE D-Bus session marker was not found")
text = text.replace(old_dbus, new_dbus, 1)

# Cleanup: 3.5.1 ended the script inline, 3.6 collects the pids in
# session_cleanup().  Support both so the locked revision stays explicit.
old_cleanup = '''[ -n "${DBUS_PID:-}" ] && kill "$DBUS_PID" 2>/dev/null || true
exit $rc
'''
old_cleanup_36 = '''    [ -n "${DBUS_PID:-}" ] && kill "$DBUS_PID" 2>/dev/null
    true
}
'''
new_cleanup_36 = '''    [ -n "${POLKIT_PID:-}" ] && kill "$POLKIT_PID" 2>/dev/null
''' + HELPER_STOP + '''    [ -n "${DBUS_PID:-}" ] && kill "$DBUS_PID" 2>/dev/null
    true
}
'''
if old_cleanup in text:
    text = text.replace(
        old_cleanup,
        '''[ -n "${POLKIT_PID:-}" ] && kill "$POLKIT_PID" 2>/dev/null || true
'''
        + HELPER_STOP
        + '''[ -n "${DBUS_PID:-}" ] && kill "$DBUS_PID" 2>/dev/null || true
exit $rc
''',
        1,
    )
elif old_cleanup_36 in text:
    text = text.replace(old_cleanup_36, new_cleanup_36, 1)
else:
    raise SystemExit("ElevenDE session cleanup marker was not found")

old_locale = '''export LANG=C.UTF-8
export LC_ALL=C.UTF-8
'''
new_locale = '''# WinduxEdu is Chinese-first.  Keep desktop entry localization and application
# labels coherent with the image locale instead of forcing the C locale.
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
export LANGUAGE=zh_CN:zh
'''
if old_locale not in text:
    raise SystemExit("ElevenDE session locale marker was not found")
text = text.replace(old_locale, new_locale, 1)
path.write_text(text, encoding="utf-8")
print("patched ElevenDE session for Live bypass, native login and zh_CN locale")
