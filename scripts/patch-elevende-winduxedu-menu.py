#!/usr/bin/env python3
"""Patch only the disposable ElevenDE build copy for WinduxEdu menu policy."""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-elevende-winduxedu-menu.py PATH_TO_MAIN_C")
path = Path(sys.argv[1])
text = path.read_text()

old_zh_parse = '''            } else if (!strncmp(p, "Name[", 5) && strncmp(p, "Name[en", 7) &&
                       !zh[0]) {
                char *eq = strchr(p, '=');
                if (eq) snprintf(zh, sizeof zh, "%s", eq + 1);
            } else if (!strncmp(p, "Exec=", 5) && !ex[0]) {
'''
new_zh_parse = '''            } else if ((!strncmp(p, "Name[zh_CN]=", 12) ||
                        !strncmp(p, "Name[zh]=", 9)) && !zh[0]) {
                char *eq = strchr(p, '=');
                if (eq) snprintf(zh, sizeof zh, "%s", eq + 1);
            } else if (!strncmp(p, "Exec=", 5) && !ex[0]) {
'''
if new_zh_parse not in text:
    if old_zh_parse in text:
        text = text.replace(old_zh_parse, new_zh_parse, 1)
    elif "only accept a Name[xx] whose key matches THIS session's" in text:
        # ElevenDE 3.6 selects Name[xx] by the session locale itself, which is
        # strictly better than the WinduxEdu fallback: with the zh_CN session
        # locale exported by the patched elevende-session, Name[zh_CN] wins.
        pass
    else:
        raise SystemExit("WinduxEdu menu zh_CN parse marker not found")

old_locale = '''        if (!nm[0] && zh[0]) snprintf(nm, sizeof nm, "%s", zh);
        if (!nm[0]) continue;
'''
new_locale = '''        size_t zhl = strlen(zh);
        while (zhl && (zh[zhl-1] == '\\n' || zh[zhl-1] == '\\r')) zh[--zhl] = 0;
        /* WinduxEdu is zh_CN-first: use the desktop file's Chinese display
         * name when present, while retaining Name= as the fallback for other
         * locales. */
        const char *menu_lang = getenv("LANG");
        if (zh[0] && menu_lang && !strncmp(menu_lang, "zh", 2))
            snprintf(nm, sizeof nm, "%s", zh);
        else if (!nm[0] && zh[0])
            snprintf(nm, sizeof nm, "%s", zh);
        if (!nm[0]) continue;
'''
if new_locale not in text:
    if old_locale in text:
        text = text.replace(old_locale, new_locale, 1)
    elif "if (locnm[0]) snprintf(nm, sizeof nm, \"%s\", locnm);" in text:
        # ElevenDE 3.6 already prefers the locale-matched Name[xx] over Name=.
        # WinduxEdu's zh_CN-first rule is therefore satisfied by the session
        # locale that the WinduxEdu session policy exports.
        pass
    else:
        raise SystemExit("WinduxEdu menu locale marker not found")

old_filter = '''        if (!ex[0]) continue;
        App *a = &apps[napps];
'''
new_filter = '''        if (!ex[0]) continue;
        /* Keep power and session commands in ElevenDE's dedicated Start/SAS
         * controls, never as duplicate unsafe entries under All apps. */
        if (ci_strstr(ex, "winduxedu-installer") || ci_strstr(ex, "calamares") ||
            ci_strstr(ex, "install-system") || ci_strstr(ex, "debian-installer") ||
            ci_strstr(de->d_name, "winduxedu-installer") ||
            ci_strstr(de->d_name, "install-system") || ci_strstr(de->d_name, "calamares") ||
            ci_strstr(de->d_name, "debian-installer") ||
            !strcmp(nm, "安装 WinduxEdu") || !strcmp(nm, "安装系统") ||
            ci_strstr(nm, "install winduxedu") || ci_strstr(nm, "install system") ||
            ci_strstr(ex, "systemctl poweroff") || ci_strstr(ex, "systemctl reboot") ||
            ci_strstr(ex, "systemctl suspend") || ci_strstr(ex, "loginctl terminate-session") ||
            ci_strstr(ex, "loginctl lock-session") || ci_strstr(ex, "gnome-session-quit") ||
            ci_strstr(ex, "lxqt-leave") || ci_strstr(ex, "xfce4-session-logout") ||
            ci_strstr(ex, "mate-session-save") || ci_strstr(ex, "openbox --exit") ||
            ci_strstr(ex, "winduxedu-power-action") || ci_strstr(ex, "shutdown") ||
            ci_strstr(ex, "poweroff") || ci_strstr(ex, "reboot") ||
            ci_strstr(ex, "suspend") || ci_strstr(ex, "logout") ||
            ci_strstr(ex, "lockscreen") || ci_strstr(de->d_name, "shutdown") ||
            ci_strstr(de->d_name, "restart") || ci_strstr(de->d_name, "reboot") ||
            ci_strstr(de->d_name, "logout") || ci_strstr(de->d_name, "logoff") ||
            ci_strstr(de->d_name, "lockscreen") || ci_strstr(de->d_name, "lxqt-leave") ||
            ci_strstr(de->d_name, "lxqt-shutdown") || ci_strstr(de->d_name, "lxqt-reboot") ||
            ci_strstr(de->d_name, "lxqt-suspend") || ci_strstr(de->d_name, "lxqt-lock") ||
            !strcmp(nm, "注销") ||
            !strcmp(nm, "关机") || !strcmp(nm, "重启") || !strcmp(nm, "重新启动") ||
            !strcmp(nm, "睡眠") || !strcmp(nm, "挂起") ||
            !strcmp(nm, "锁屏") || !strcmp(nm, "锁定") ||
            ci_strstr(nm, "shutdown") || ci_strstr(nm, "restart") ||
            ci_strstr(nm, "reboot") || ci_strstr(nm, "logout") ||
            ci_strstr(nm, "logoff") || ci_strstr(nm, "lockscreen"))
            continue;
        App *a = &apps[napps];
'''
if new_filter not in text:
    if old_filter not in text:
        raise SystemExit("WinduxEdu menu command-filter marker not found")
    text = text.replace(old_filter, new_filter, 1)

old_dedupe = '''    /* dedupe by exec (keep first occurrence) */
    for (int i = 0; i < napps; i++)
        for (int j = i + 1; j < napps; j++)
            if (!strcmp(apps[i].exec, apps[j].exec)) {
                memmove(&apps[j], &apps[j + 1],
                        (size_t)(napps - j - 1) * sizeof(App));
                napps--;
                j--;
            }
    app_dirs_watch_snapshot();
'''
new_dedupe = '''    /* XDG directories are scanned from user/local to system. Keep the first
     * item by desktop ID as well as by Exec so WinduxEdu-owned launchers replace
     * upstream entries even when the adapter changes their command line. */
    for (int i = 0; i < napps; i++)
        for (int j = i + 1; j < napps; j++)
            if (!strcmp(apps[i].exec, apps[j].exec) ||
                !strcmp(apps[i].desktop_id, apps[j].desktop_id)) {
                memmove(&apps[j], &apps[j + 1],
                        (size_t)(napps - j - 1) * sizeof(App));
                napps--;
                j--;
            }
    app_dirs_watch_snapshot();
'''
if new_dedupe not in text:
    if old_dedupe not in text:
        raise SystemExit("WinduxEdu menu dedupe marker not found")
    text = text.replace(old_dedupe, new_dedupe, 1)

# --- Start menu: outside-click dismissal -----------------------------------
# ElevenDE 3.6 put the "press outside closes the menu" block behind an
# `else if` that follows a branch which already matches XI_RawButtonPress, so
# the block can never run.  The menu therefore stayed open over an
# application window and kept swallowing presses that the window underneath
# should have received, which is what reads as "开始菜单点击失效".
old_dismiss = '''                    if (ck->evtype == XI_RawButtonPress) phys_btn = 1;
                    else if (ck->evtype == XI_RawButtonRelease) phys_btn = 0;
                    else if (ck->evtype == XI_RawKeyPress && ck->data) {
                        XIRawEvent *re = (XIRawEvent *)ck->data;
                        if (super_down && re->detail != k_win1 &&
                            re->detail != k_win2)
                            super_combo = 1;   /* Win+<something> combo */
                    }
                    else if (ck->evtype == XI_RawButtonPress) {
                        /* Win11 behavior without any pointer grab: a
                         * physical press OUTSIDE our UI closes the Start
                         * menu / search / flyouts. Raw events see every
                         * press regardless of which window receives it. */
                        if ((menu_visible || search_visible || ctx_visible ||
                             pinm_visible) && !pointer_over_own_ui())
                            menu_hide();     /* hides power/pinm/ctx too */
                        if (net_visible && !pointer_over_own_ui())
                            net_hide();      /* quick-settings panel */
                    }
'''
new_dismiss = '''                    if (ck->evtype == XI_RawButtonPress) {
                        phys_btn = 1;
                        /* Win11 behavior without any pointer grab: a
                         * physical press OUTSIDE our UI closes the Start
                         * menu / search / flyouts. Raw events see every
                         * press regardless of which window receives it.
                         * WinduxEdu: this branch used to sit behind an
                         * `else if` that followed a branch already matching
                         * XI_RawButtonPress, i.e. it was unreachable. */
                        if ((menu_visible || search_visible || ctx_visible ||
                             pinm_visible) && !pointer_over_own_ui())
                            menu_hide();     /* hides power/pinm/ctx too */
                        if (net_visible && !pointer_over_own_ui())
                            net_hide();      /* quick-settings panel */
                    }
                    else if (ck->evtype == XI_RawButtonRelease) phys_btn = 0;
                    else if (ck->evtype == XI_RawKeyPress && ck->data) {
                        XIRawEvent *re = (XIRawEvent *)ck->data;
                        if (super_down && re->detail != k_win1 &&
                            re->detail != k_win2)
                            super_combo = 1;   /* Win+<something> combo */
                    }
'''
if new_dismiss not in text:
    if old_dismiss not in text:
        raise SystemExit("WinduxEdu menu outside-dismiss marker not found")
    text = text.replace(old_dismiss, new_dismiss, 1)

# --- Start menu: a tap must never be cancelled before its own release ------
# gp_tick() treats "XQueryPointer says the button is up" as "the release was
# lost" and disarms the gesture.  The release is frequently still sitting in
# our own socket at that point: press and release are dispatched at the top of
# the loop, the redraw/refresh work in between can take milliseconds, and a
# quick touchscreen tap lands its release inside that window.  The queued
# release then found gp_kind == GP_NONE and launched nothing, so the tap in the
# All apps list simply did nothing.  Give up only when there is nothing left
# to read, and never start a long-press once the button is already up.
old_tick = '''    {
        Window rr, cr; int rx, ry, wx, wy; unsigned int m = 0;
        if (XQueryPointer(dpy, root, &rr, &cr, &rx, &ry, &wx, &wy, &m) &&
            !(m & Button1Mask)) { gp_reset(); return; }
    }
'''
new_tick = '''    {
        Window rr, cr; int rx, ry, wx, wy; unsigned int m = 0;
        if (XQueryPointer(dpy, root, &rr, &cr, &rx, &ry, &wx, &wy, &m) &&
            !(m & Button1Mask)) {
            /* The server may already know the button is up while the release
             * event itself is still unread in our socket; cancelling here
             * would swallow that tap. */
            if (!XPending(dpy)) gp_reset();
            return;
        }
    }
'''
if new_tick not in text:
    if old_tick not in text:
        raise SystemExit("WinduxEdu menu tap-safety marker not found")
    text = text.replace(old_tick, new_tick, 1)

path.write_text(text)
print(f"patched WinduxEdu menu policy in {path}")
