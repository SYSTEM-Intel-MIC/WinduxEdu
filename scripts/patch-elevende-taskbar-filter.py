#!/usr/bin/env python3
"""Make ElevenDE's custom taskbar honor EWMH skip-taskbar state.

Qt marks Widgets panels and invisible edge strips as Tool windows, which publish
_NET_WM_STATE_SKIP_TASKBAR.  Openbox correctly exposes those windows in its
client list, but the custom Shell previously ignored the state and drew a
permanent blank application button beside Start.

The same script also stabilizes the fullscreen auto-hide decision.  The Shell
asked only the *focused* window whether it was fullscreen, but the Seewo ink
overlay (com.seewo.easiminiapps.desktopinkannotation) is fullscreen+SKIP_TASKBAR
and never takes focus while its pen toolbar (not fullscreen) does.  Focus then
ping-ponged between a fullscreen and a non-fullscreen window and the taskbar was
XMapRaised/XUnmapWindow'd on every click -- the field report "开启批注时任务栏
闪烁".  The predicate now looks at every viewable client and settles for 250 ms
before the bar is mapped or unmapped.
"""
from __future__ import annotations

import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-elevende-taskbar-filter.py PATH/TO/shell/main.c")

path = Path(sys.argv[1])
if not path.is_file():
    raise SystemExit(f"ElevenDE Shell source not found: {path}")
text = path.read_text(encoding="utf-8")
# The markers live inside C block comments that continue on the same line, so
# match the bare tag instead of "/* TAG */" (the latter never matches).
if "WINDUXEDU-TASKBAR-SKIP-STATE" in text:
    raise SystemExit("WinduxEdu taskbar skip-state filter is already present")
if "WINDUXEDU-TASKBAR-FULLSCREEN-STABLE" in text:
    raise SystemExit("WinduxEdu taskbar fullscreen stabilization is already present")

old_atoms = '''        Atom wm_type_desktop = atom("_NET_WM_WINDOW_TYPE_DESKTOP");
        for (unsigned long i = 0; i < nitems && ntask < MAX_TASKS; i++) {
'''
new_atoms = '''        Atom wm_type_desktop = atom("_NET_WM_WINDOW_TYPE_DESKTOP");
        Atom wm_state_skip_taskbar = atom("_NET_WM_STATE_SKIP_TASKBAR");
        for (unsigned long i = 0; i < nitems && ntask < MAX_TASKS; i++) {
'''
if old_atoms not in text:
    raise SystemExit("ElevenDE taskbar window loop anchor was not found")
text = text.replace(old_atoms, new_atoms, 1)

old_insert = '''            if (tprop) XFree(tprop);
            tasks[ntask].win = ws[i];
'''
new_insert = '''            if (tprop) XFree(tprop);
            /* WINDUXEDU-TASKBAR-SKIP-STATE: honor the EWMH contract for Qt
               Tool/utility windows.  Widgets uses this for its permanent
               edge trigger and panel, which must never occupy an app button. */
            Atom stype = None;
            int sfmt = 0;
            unsigned long sn = 0, sa = 0;
            unsigned char *sprop = NULL;
            int skip_task = 0;
            if (XGetWindowProperty(dpy, ws[i], atom("_NET_WM_STATE"),
                                   0, 16, False, XA_ATOM, &stype, &sfmt,
                                   &sn, &sa, &sprop) == Success && sprop) {
                if (stype == XA_ATOM && sfmt == 32)
                    for (unsigned long si = 0; si < sn; si++)
                        if (((Atom *)sprop)[si] == wm_state_skip_taskbar) {
                            skip_task = 1;
                            break;
                        }
                XFree(sprop);
            }
            if (skip_task)
                continue;
            tasks[ntask].win = ws[i];
'''
if old_insert not in text:
    raise SystemExit("ElevenDE taskbar state insertion anchor was not found")
text = text.replace(old_insert, new_insert, 1)

# ---- fullscreen auto-hide: settle + whole-desktop scan --------------------
old_probe = '''    if (prop) XFree(prop);
    return fs;
}

static void bar_set_hidden(int hide) {
'''
new_probe = '''    if (prop) XFree(prop);
    return fs;
}

/* WINDUXEDU-TASKBAR-FULLSCREEN-STABLE: decide "the taskbar must be hidden"
   from the whole desktop instead of from _NET_ACTIVE_WINDOW alone.

   Why: the Seewo ink-annotation overlay is fullscreen but SKIP_TASKBAR, so
   Openbox never makes it the active window; its pen toolbar is the window that
   takes focus.  Asking only g_active therefore alternated between a fullscreen
   and a non-fullscreen answer on every click inside the annotation UI, and the
   bar was unmapped/mapped in lockstep.

   Scanning every viewable client makes the answer independent of focus, and
   holding the answer for SETTLE seconds before acting on it keeps a transient
   overlay (ink layer popping up, a window dragged out of maximize) from
   strobing the bar.  The rescan is rate limited because the main loop spins at
   ~60 Hz while the bar is hidden and each window costs two X round-trips. */
static int bar_fullscreen_should_hide(void) {
    static const double SCAN_EVERY = 0.10;  /* client-list rescan interval   */
    static const double SETTLE     = 0.25;  /* fullscreen must outlive this  */
    static double scanned = 0.0;
    static double appeared = 0.0;
    static int present = 0;
    double now = now_sec();
    if (now - scanned >= SCAN_EVERY) {
        Atom type = None;
        int fmt = 0;
        unsigned long nitems = 0, after = 0;
        unsigned char *prop = NULL;
        scanned = now;
        present = 0;
        /* _NET_CLIENT_LIST_STACKING is what the WM keeps live; fall back to
           _NET_CLIENT_LIST for a WM that only publishes the plain list. */
        if (!(XGetWindowProperty(dpy, root, atom("_NET_CLIENT_LIST_STACKING"),
                                 0, 0x1000, False, XA_WINDOW, &type, &fmt,
                                 &nitems, &after, &prop) == Success &&
              prop && type == XA_WINDOW)) {
            if (prop) { XFree(prop); prop = NULL; }
            type = None;
            nitems = 0;
            if (!(XGetWindowProperty(dpy, root, atom("_NET_CLIENT_LIST"),
                                     0, 0x1000, False, XA_WINDOW, &type, &fmt,
                                     &nitems, &after, &prop) == Success &&
                  prop && type == XA_WINDOW)) {
                if (prop) XFree(prop);
                prop = NULL;
            }
        }
        if (prop) {
            Window *ws = (Window *)prop;
            for (unsigned long i = 0; i < nitems && !present; i++) {
                XWindowAttributes wa;
                /* Our own windows are never fullscreen clients; refresh_tasks()
                   skips the same three when it builds the task list. */
                if (ws[i] == win_bar || ws[i] == win_menu || ws[i] == win_desk)
                    continue;
                if (!XGetWindowAttributes(dpy, ws[i], &wa))
                    continue;               /* stale XID still in the list */
                if (wa.map_state != IsViewable)
                    continue;               /* iconified / mid-unmap: unseen */
                if (window_is_fullscreen(ws[i]))
                    present = 1;
            }
            XFree(prop);
        }
        if (present) {
            if (appeared == 0.0) appeared = now;
        } else {
            appeared = 0.0;                 /* leaving fullscreen is instant */
        }
    }
    return present && appeared != 0.0 && (now - appeared) >= SETTLE;
}

static void bar_set_hidden(int hide) {
'''
if old_probe not in text:
    raise SystemExit("ElevenDE window_is_fullscreen anchor was not found")
text = text.replace(old_probe, new_probe, 1)

old_update = '''/* Windows 11 behaviour: a fullscreen client hides the taskbar; sweeping the
   pointer against the bottom edge brings it back until the pointer leaves.
   Root/pointer motion events do NOT reach us while a fullscreen client owns
   the pointer, so the reveal is polled with XQueryPointer instead. */
static void bar_fullscreen_update(void) {
    int fs = window_is_fullscreen(g_active);
    if (fs != bar_hidden) bar_set_hidden(fs);
    if (bar_hidden && win_bar) {
        Window r1, c1;
        int rx, ry, wx, wy;
        unsigned int mask;
        if (XQueryPointer(dpy, root, &r1, &c1, &rx, &ry, &wx, &wy, &mask)) {
            int at_edge = ry >= scr_h - 4;
            if (at_edge && !bar_peeked) {
                XMapRaised(dpy, win_bar);
                bar_peeked = 1;
                bar_dirty = 1;
            } else if (bar_peeked && ry < scr_h - BAR_H - 8) {
                XUnmapWindow(dpy, win_bar);
                bar_peeked = 0;
                bar_dirty = 1;
            }
        }
    }
}
'''
new_update = '''/* Windows 11 behaviour: a fullscreen client hides the taskbar; sweeping the
   pointer against the bottom edge brings it back until the pointer leaves.
   Root/pointer motion events do NOT reach us while a fullscreen client owns
   the pointer, so the reveal is polled with XQueryPointer instead.
   WINDUXEDU-TASKBAR-FULLSCREEN-STABLE: both the hide decision and the reveal
   are debounced, and the hide decision no longer depends on which window owns
   focus (see bar_fullscreen_should_hide). */
static void bar_fullscreen_update(void) {
    double now = now_sec();
    int hide = bar_fullscreen_should_hide();
    if (hide != bar_hidden) bar_set_hidden(hide);
    if (bar_hidden && win_bar) {
        Window r1, c1;
        int rx, ry, wx, wy;
        unsigned int mask;
        if (XQueryPointer(dpy, root, &r1, &c1, &rx, &ry, &wx, &wy, &mask)) {
            int at_edge = ry >= scr_h - 4;
            /* Same spatial hysteresis as before: reveal at the very bottom
               row, keep it until the pointer clears the bar's top edge. */
            int want = bar_peeked ? (ry >= scr_h - BAR_H - 8) : at_edge;
            static int last_want = -1;
            static double changed = 0.0;
            if (want != last_want) { last_want = want; changed = now; }
            /* A pointer that merely grazes the bottom row while the teacher is
               drawing (the ink toolbar already occupies y >= 822) must not map
               and unmap the bar on every pass. */
            if (want != bar_peeked && (now - changed) >= 0.25) {
                if (want) XMapRaised(dpy, win_bar);
                else      XUnmapWindow(dpy, win_bar);
                bar_peeked = want;
                bar_dirty = 1;
            }
        }
    }
}
'''
if old_update not in text:
    raise SystemExit("ElevenDE bar_fullscreen_update anchor was not found")
text = text.replace(old_update, new_update, 1)

old_banner = '''    fprintf(stderr, "[elevende] Xkb stateNotify %s: Super key tracking\\n",
            xkb_ok ? "enabled" : "UNAVAILABLE (Super menu toggle disabled)");
'''
new_banner = '''    /* Machine-checkable marker: scripts/validate-winduxedu-live-image.sh
       greps the shipped shell binary for this literal, which proves the
       WinduxEdu taskbar patches were compiled in and survived a rebuild. */
    fprintf(stderr, "[elevende] WinduxEdu taskbar: skip-taskbar filter + "
                    "fullscreen scan=every-viewable-client settle=250ms\\n");
    fprintf(stderr, "[elevende] Xkb stateNotify %s: Super key tracking\\n",
            xkb_ok ? "enabled" : "UNAVAILABLE (Super menu toggle disabled)");
'''
if old_banner not in text:
    raise SystemExit("ElevenDE startup banner anchor was not found")
text = text.replace(old_banner, new_banner, 1)

old_note = '''        /* Fullscreen auto-hide: hide the taskbar while the active client is
           fullscreen and reveal it on a bottom-edge sweep. Polled every pass
           (select() idles at 150 ms, so the reveal is at most ~150 ms late). */
        bar_fullscreen_update();
'''
new_note = '''        /* Fullscreen auto-hide: hide the taskbar while any viewable client is
           fullscreen and reveal it on a bottom-edge sweep. Polled every pass;
           bar_fullscreen_should_hide() rescans the client list at ~10 Hz and
           settles for 250 ms before the bar is mapped or unmapped. */
        bar_fullscreen_update();
'''
if old_note not in text:
    raise SystemExit("ElevenDE fullscreen auto-hide note anchor was not found")
text = text.replace(old_note, new_note, 1)

path.write_text(text, encoding="utf-8")
print(f"patched EWMH skip-taskbar filtering in {path}")
print(f"stabilized fullscreen taskbar auto-hide in {path}")
