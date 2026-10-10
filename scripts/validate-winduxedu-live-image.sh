#!/usr/bin/env bash
# Verify the finished WinduxEdu 1.0 ISO, not merely the source configuration.
# This is intentionally read-only: it extracts selected files from the final
# squashfs and checks installer-critical paths, package entry points and the
# narrow Live-session sudo rule.
set -euo pipefail

validation_error() {
    status="$?"
    echo "final ISO validation failed near line $1" >&2
    exit "$status"
}
trap 'validation_error $LINENO' ERR

# Full squashfs verification must recreate device nodes and security xattrs;
# run as root so permission warnings are not mistaken for data corruption.
[ "$(id -u)" = 0 ] || {
    echo 'run final ISO validation as root (sudo) for full squashfs integrity checking' >&2
    exit 2
}

[ "$#" -eq 1 ] || {
    echo "usage: $0 WinduxEdu-1.0-amd64-livecd.iso" >&2
    exit 2
}

ISO="$1"
[ -s "$ISO" ] || {
    echo "ISO is missing or empty: $ISO" >&2
    exit 1
}
for command in xorriso unsquashfs lsinitramfs grep; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "required command is unavailable: $command" >&2
        exit 1
    }
done

WORK="$(mktemp -d)"
cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT
FS="$WORK/filesystem.squashfs"
LIST="$WORK/squashfs.list"

INITRD="$WORK/initrd.img"
xorriso -osirrox on -indev "$ISO" \
    -extract /live/filesystem.squashfs "$FS" \
    -extract /live/initrd.img "$INITRD" >/dev/null 2>&1
[ -s "$FS" ] || {
    echo "final ISO lacks /live/filesystem.squashfs" >&2
    exit 1
}
[ -s "$INITRD" ] || {
    echo "final ISO lacks /live/initrd.img" >&2
    exit 1
}
# A kernel panic reporting "No working init found" is detectable without a VM.
# Fully enumerate the archive to force decompression, then require its init entry.
INITRD_LIST="$WORK/initrd.list"
if ! lsinitramfs "$INITRD" > "$INITRD_LIST" || ! grep -qx 'init' "$INITRD_LIST"; then
    echo 'final ISO contains an invalid Live initrd or lacks its /init entry' >&2
    exit 1
fi

# Listing the directory tree is insufficient: a damaged compressed data block
# can leave names visible while applications fail at runtime. Fully expand the
# squashfs before any path-level inspection so a corrupt ISO cannot pass CI.
FULL_ROOT="$WORK/full-root"
if ! unsquashfs -d "$FULL_ROOT" "$FS" >/dev/null; then
    echo 'final ISO contains a corrupt or unreadable squashfs data block' >&2
    exit 1
fi
unsquashfs -l "$FS" > "$LIST"

require_path() {
    local path="$1"
    grep -q -E "(^|/)${path//./\\.}$" "$LIST" || {
        echo "missing path in final squashfs: /$path" >&2
        exit 1
    }
}

# includes.chroot preserves whatever mode the checkout carries, and a checkout
# from a non-POSIX filesystem can hand a helper over without its bit, which
# silently drops it from the session helper loop ([ -x ] || continue).
require_exec() {
    local path="$1"
    [ -x "$FULL_ROOT/$path" ] || {
        echo "not executable in final squashfs: /$path" >&2
        exit 1
    }
}

cat_image_file() {
    local path="$1" output="$2"
    unsquashfs -cat "$FS" "$path" > "$output"
}

# Calamares unpackfs must contain these executables and functional modules.
require_path 'usr/bin/unsquashfs'
require_path 'usr/bin/rsync'
require_path 'usr/bin/chvt'
require_path 'etc/calamares/branding/winduxedu/show.qml'
require_path 'etc/calamares/branding/winduxedu/stylesheet.qss'
require_path 'etc/calamares/modules/winduxedu-postinstall.conf'
require_path 'usr/local/libexec/winduxedu-target-postinstall.sh'
require_path 'usr/local/libexec/winduxedu-installed-cleanup'
require_path 'etc/systemd/system/winduxedu-installed-cleanup.service'
require_path 'usr/local/bin/winduxedu-installer'
require_path 'usr/local/sbin/winduxedu-live-session-init'
require_path 'usr/local/sbin/winduxedu-elevende-display'
require_path 'usr/local/bin/winduxedu-power-action'
require_path 'usr/local/bin/winduxedu-logout'
require_path 'usr/local/libexec/winduxedu-privileged-action'
require_path 'usr/share/polkit-1/actions/im.system-intel-mic.winduxedu.privileged-action.policy'
require_path 'etc/systemd/system/winduxedu-elevende-display.service'
require_path 'etc/systemd/system/graphical.target.wants/winduxedu-elevende-display.service'
require_path 'etc/systemd/system/multi-user.target.wants/winduxedu-live-session-init.service'
require_path 'usr/local/share/elevende-shell/icons/64x64/apps/winduxedu-installer.svg'
# The 教育版设置 settings page is a real, reachable page, not just a nav label:
# it resolves its glyph through the shared settings-nav-<id>.png convention.
require_path 'usr/local/share/elevende-shell/icons/64x64/apps/settings-nav-edu.png'
# UEFI install: grub2-common owns both tools Calamares' postinstall runs, and
# the image must seed /etc/default/grub itself (Debian bookworm only ships it
# from grub-cloud-amd64, which is the reported "update-grub missing" failure).
for grub_path in usr/sbin/update-grub usr/sbin/grub-install etc/default/grub; do
    require_path "$grub_path"
done

# The system must use ElevenDE's native display/session chain, never LightDM.
if grep -qE '/(usr/sbin/)?lightdm|/etc/lightdm' "$LIST"; then
    echo 'final ISO still contains LightDM files' >&2
    exit 1
fi
DISPLAY_SERVICE="$WORK/winduxedu-elevende-display.service"
cat_image_file 'etc/systemd/system/winduxedu-elevende-display.service' "$DISPLAY_SERVICE"
grep -q '^ExecStart=/usr/local/sbin/winduxedu-elevende-display$' "$DISPLAY_SERVICE"
grep -q '^Conflicts=display-manager.service lightdm.service$' "$DISPLAY_SERVICE"
LIVE_INIT="$WORK/winduxedu-live-session-init"
cat_image_file 'usr/local/sbin/winduxedu-live-session-init' "$LIVE_INIT"
! grep -qE 'chpasswd|lightdm|nopasswdlogin' "$LIVE_INIT"
SESSION_SCRIPT="$WORK/elevende-session"
cat_image_file 'usr/local/bin/elevende-session' "$SESSION_SCRIPT"
grep -q 'WINDUXEDU-SESSION-POLICY' "$SESSION_SCRIPT"
grep -q 'Live session bypasses the login gate' "$SESSION_SCRIPT"
# The WinduxEdu session helpers (touchscreen mapping, screen keyboard and the
# Seewo toolbar) must be started before the login gate so they are available
# while the lock screen is asking for a password, and must be tracked by pid
# file so the session can stop them again.
grep -q 'start_winduxedu_helpers' "$SESSION_SCRIPT"
# Both lists must carry the same helpers: a start/stop mismatch leaves the
# audio bootstrap and the shortcut repair loop running past logout.
helper_list_occurrences="$(grep -c \
    'winduxedu-touch-fix winduxedu-oskd winduxedu-seewo-toolbar winduxedu-media-notify winduxedu-audio-session winduxedu-desktop-tidy' \
    "$SESSION_SCRIPT" || true)"
if [ "${helper_list_occurrences:-0}" -lt 2 ]; then
    echo "the session helper list is not registered for both start and stop" >&2
    exit 1
fi
# The stop loop matches the helper's own path in /proc/<pid>/cmdline; $h
# already carries the winduxedu- prefix, so a doubled prefix would make every
# kill silently no-op and leave helpers running past logout.
! grep -q 'winduxedu-winduxedu' "$SESSION_SCRIPT"
# Calamares' 免密码登录 choice is only an `autologin` group membership, so the
# session has to honour the marker file winduxedu-target-postinstall writes.
grep -q '/etc/winduxedu/autologin' "$SESSION_SCRIPT"
DISPLAY_LAUNCHER="$WORK/winduxedu-elevende-display"
cat_image_file 'usr/local/sbin/winduxedu-elevende-display' "$DISPLAY_LAUNCHER"
grep -q 'if \[ -f "\$LOGOUT_MARKER" \]' "$DISPLAY_LAUNCHER"
grep -q 'explicit logout; restarting native ElevenDE session' "$DISPLAY_LAUNCHER"
# An unexpected session exit must keep the Xorg that is already healthy on VT7
# and respawn the session instead of ending the service: the end of the service
# killed the server, and every restart that followed had to reclaim display :0,
# which a stale /tmp/.X0-lock turned into a permanent Xorg failure loop.
grep -q 'X_LOCK=/tmp/.X0-lock' "$DISPLAY_LAUNCHER" || {
    echo 'the display launcher no longer clears a stale Xorg display lock' >&2
    exit 1
}
grep -q 'wait "\$SESSION_PID" || session_rc=\$?' "$DISPLAY_LAUNCHER" || {
    echo 'the display launcher loses the session status under set -e' >&2
    exit 1
}
grep -q 'session-respawn=' "$DISPLAY_LAUNCHER" || {
    echo 'the display launcher no longer respawns an unexpected session exit' >&2
    exit 1
}
# The evidence has to survive the failure it documents, which means its own
# transient unit (a child of this service is killed with the service) and a
# bounded, once-per-boot report so the smoke run's serial tail keeps it.
grep -q 'systemd-run --unit=winduxedu-smoke-probe' "$DISPLAY_LAUNCHER" || {
    echo 'the guest state probe is still a child of the display service' >&2
    exit 1
}
grep -q 'display service failure evidence' "$DISPLAY_LAUNCHER" || {
    echo 'the display launcher records no failure evidence on the console' >&2
    exit 1
}
grep -q 'x-status dead' "$DISPLAY_LAUNCHER" || {
    echo 'the display launcher cannot tell a dead Xorg from a dead session' >&2
    exit 1
}
POWER_BRIDGE="$WORK/winduxedu-power-action"
cat_image_file 'usr/local/bin/winduxedu-power-action' "$POWER_BRIDGE"
grep -q '^exec pkexec /usr/local/libexec/winduxedu-privileged-action "\$action"$' "$POWER_BRIDGE"
LOGOUT_HELPER="$WORK/winduxedu-logout"
cat_image_file 'usr/local/bin/winduxedu-logout' "$LOGOUT_HELPER"
grep -q 'winduxedu-elevende-logout' "$LOGOUT_HELPER"
grep -q 'exec openbox --exit' "$LOGOUT_HELPER"
PRIVILEGED_ACTION="$WORK/winduxedu-privileged-action"
cat_image_file 'usr/local/libexec/winduxedu-privileged-action' "$PRIVILEGED_ACTION"
! grep -q '\$@' "$PRIVILEGED_ACTION"
grep -q 'systemctl --no-wall' "$PRIVILEGED_ACTION"
TARGET_POSTINSTALL="$WORK/winduxedu-target-postinstall"
cat_image_file 'usr/local/libexec/winduxedu-target-postinstall.sh' "$TARGET_POSTINSTALL"
! grep -qE 'pkill[[:space:]]+-USR1[[:space:]]+-x[[:space:]]+elevende-shell' "$TARGET_POSTINSTALL"
grep -q '/usr/local/libexec/winduxedu-installed-cleanup' "$TARGET_POSTINSTALL"
grep -q 'systemctl enable winduxedu-installed-cleanup.service' "$TARGET_POSTINSTALL"
INSTALLED_CLEANUP="$WORK/winduxedu-installed-cleanup"
cat_image_file 'usr/local/libexec/winduxedu-installed-cleanup' "$INSTALLED_CLEANUP"
! grep -qE 'read[[:space:]]+-r[[:space:]]+-d' "$INSTALLED_CLEANUP"
! grep -qE '/usr/(local/)?share/applications/\{' "$INSTALLED_CLEANUP"
grep -q 'for home_dir in /home/\* /root /etc/skel; do' "$INSTALLED_CLEANUP"
grep -q 'clean_desktop_dir "\$home_dir/Desktop"' "$INSTALLED_CLEANUP"
grep -q "'/etc/skel/Desktop/Install WinduxEdu.desktop'" "$INSTALLED_CLEANUP"
CLEANUP_SERVICE="$WORK/winduxedu-installed-cleanup.service"
cat_image_file 'etc/systemd/system/winduxedu-installed-cleanup.service' "$CLEANUP_SERVICE"
grep -q '^Before=winduxedu-elevende-display.service$' "$CLEANUP_SERVICE"
grep -q '^ExecStart=/usr/local/libexec/winduxedu-installed-cleanup$' "$CLEANUP_SERVICE"
POLKIT_POLICY="$WORK/winduxedu-privileged-action.policy"
cat_image_file 'usr/share/polkit-1/actions/im.system-intel-mic.winduxedu.privileged-action.policy' "$POLKIT_POLICY"
grep -q 'id="im.system-intel-mic.winduxedu.privileged-action"' "$POLKIT_POLICY"
grep -q '<allow_active>auth_self</allow_active>' "$POLKIT_POLICY"
LIVE_POLKIT_RULE="$WORK/49-winduxedu-calamares.rules"
cat_image_file 'etc/polkit-1/rules.d/49-winduxedu-calamares.rules' "$LIVE_POLKIT_RULE"
grep -q 'im.system-intel-mic.winduxedu.privileged-action' "$LIVE_POLKIT_RULE"
grep -q 'subject.isInGroup("sudo")' "$LIVE_POLKIT_RULE"
grep -q 'polkit.Result.YES' "$LIVE_POLKIT_RULE"
! grep -q 'org.freedesktop.policykit.exec' "$LIVE_POLKIT_RULE"

# Verify the installed, hook-mutated Calamares settings rather than source
# templates. A missing sequence entry recreates the historical module-load
# failure, so both the instance and the sequence reference are mandatory.
SETTINGS="$WORK/settings.conf"
cat_image_file 'etc/calamares/settings.conf' "$SETTINGS"
grep -q -E '^[[:space:]]*branding:[[:space:]]*winduxedu[[:space:]]*$' "$SETTINGS"
grep -q -E '^[[:space:]]*-[[:space:]]*id:[[:space:]]*winduxedu-postinstall[[:space:]]*$' "$SETTINGS"
grep -q -E '^[[:space:]]*module:[[:space:]]*shellprocess[[:space:]]*$' "$SETTINGS"
grep -q -E '^[[:space:]]*config:[[:space:]]*winduxedu-postinstall\.conf[[:space:]]*$' "$SETTINGS"
grep -q -E '^[[:space:]]*-[[:space:]]*shellprocess@winduxedu-postinstall[[:space:]]*$' "$SETTINGS"

# The passwordless exception belongs only to the disposable Live user and only
# to the Calamares binary. Broad NOPASSWD rules are explicitly rejected.
SUDOERS="$WORK/winduxedu-installer.sudoers"
cat_image_file 'etc/sudoers.d/winduxedu-installer' "$SUDOERS"
grep -q -E '^user ALL=\(root\) NOPASSWD: SETENV: /usr/bin/calamares$' "$SUDOERS"
if grep -q -E 'NOPASSWD:[[:space:]]*(ALL|ALL[[:space:]]*$)' "$SUDOERS"; then
    echo 'Live installer sudoers rule is broader than Calamares only' >&2
    exit 1
fi

DESKTOP="$WORK/winduxedu-installer.desktop"
cat_image_file 'usr/share/applications/winduxedu-installer.desktop' "$DESKTOP"
grep -q -E '^Exec=(/usr/local/bin/)?winduxedu-installer([[:space:]]|$)' "$DESKTOP"
if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$DESKTOP"
fi

# ElevenDE and every audited, user-facing extra component must appear in the
# final filesystem. These checks catch package staging regressions that package
# metadata alone cannot see.
for path in \
    usr/local/bin/elevende-session \
    usr/local/libexec/winduxedu-component-launch \
    usr/share/themes/ElevenDE/gtk-3.0/gtk.css \
    usr/bin/winduxedu-store \
    usr/bin/winduxedu-troubleshooting \
    usr/bin/winduxedu-sticky-keys \
    usr/bin/winduxedu-widgets \
    usr/bin/winduxedu-windowshit \
    usr/bin/winsat \
    usr/bin/winver \
    usr/bin/winduxedu-ipconfig \
    usr/local/bin/sas-screen \
    usr/local/bin/winduxedu-edu-settings \
    usr/local/bin/winduxedu-touch-fix \
    usr/local/bin/winduxedu-touch-calibrate \
    usr/local/bin/winduxedu-oskd \
    usr/local/bin/winduxedu-seewo-toolbar \
    usr/local/bin/winduxedu-media-notify \
    usr/local/bin/winduxedu-audio-session \
    usr/local/bin/winduxedu-desktop-tidy \
    usr/local/bin/xterm \
    usr/local/libexec/winduxedu-edu-apply \
    usr/local/libexec/winduxedu-edu-uninstall \
    usr/local/share/applications/winduxedu-touch-calibrate.desktop \
    usr/local/share/applications/peazip.desktop \
    etc/X11/xorg.conf.d/99-winduxedu-touchscreen.conf \
    etc/X11/xorg.conf.d/99-winduxedu-serverflags.conf \
    etc/winduxedu/edu-settings.conf \
    etc/skel/.config/fcitx5/config \
    etc/skel/.config/fcitx5/profile \
    etc/skel/.config/onlyoffice/DesktopEditors.conf \
    etc/udev/rules.d/99-winduxedu-automount.rules \
    etc/udev/rules.d/99-winduxedu-touchscreen.rules \
    usr/share/applications/com.seewo.easisidebar.desktop; do
    require_path "$path"
done

# The session helper loop skips anything without its executable bit, so an
# entry that exists but lost the bit is as good as missing: every helper the
# session starts (and every entry the user clicks) must be executable.
for exec_path in \
    usr/local/bin/elevende-session \
    usr/local/bin/winduxedu-touch-fix \
    usr/local/bin/winduxedu-touch-calibrate \
    usr/local/bin/winduxedu-oskd \
    usr/local/bin/winduxedu-seewo-toolbar \
    usr/local/bin/winduxedu-media-notify \
    usr/local/bin/winduxedu-audio-session \
    usr/local/bin/winduxedu-desktop-tidy \
    usr/local/bin/xterm \
    usr/local/bin/winduxedu-edu-settings \
    usr/bin/onboard \
    usr/local/libexec/winduxedu-edu-apply \
    usr/local/libexec/winduxedu-edu-uninstall \
    usr/local/sbin/winduxedu-elevende-display \
    usr/local/sbin/winduxedu-live-session-init \
    usr/local/sbin/winduxedu-smoke-diagnostics; do
    require_exec "$exec_path"
done

# SAS footer power actions must share Start's fixed-function bridge rather
# than attempting unprivileged systemctl calls that silently fail after install.
if ! strings -el "$FULL_ROOT/usr/local/bin/sas-screen" | grep -q '/usr/local/bin/winduxedu-power-action'; then
    echo 'final ISO SAS binary does not route power actions through WinduxEdu bridge' >&2
    exit 1
fi

# The taskbar auto-hide decision must look at *every* viewable client with a
# 250 ms settle: judging by _NET_ACTIVE_WINDOW alone is what let the Seewo
# ink-annotation overlay flip the bar on every focus change inside the
# annotation UI (field report: 批注开启时任务栏闪烁).  The patch announces
# itself through the shell's own startup log line.
require_path 'usr/local/bin/elevende-shell'
require_exec 'usr/local/bin/elevende-shell'
if ! strings "$FULL_ROOT/usr/local/bin/elevende-shell" |
    grep -qF 'fullscreen scan=every-viewable-client settle=250ms'; then
    echo 'final ISO elevende-shell lacks the WinduxEdu fullscreen taskbar policy' >&2
    exit 1
fi
if ! strings "$FULL_ROOT/usr/local/bin/elevende-shell" | grep -qF 'skip-taskbar filter'; then
    echo 'final ISO elevende-shell lacks the WinduxEdu skip-taskbar filter' >&2
    exit 1
fi
# 希沃白板 execve's straight into libunistring.so.2; without the shared object
# it exits before drawing anything and the desktop icon appears dead, so the
# compatibility layer declares the amd64 library explicitly.
require_path 'usr/lib/x86_64-linux-gnu/libunistring.so.2'

# All WinduxEdu third-party components resolve to curated Windows 11 aliases in
# the ElevenDE icon theme.  Checking the final squashfs catches both package
# staging omissions and upstream icon-generation overwrites.
for icon in \
    linux-pcmanager \
    linux-regedit \
    winduxedu-device-manager \
    microsoft-edge \
    winduxedu-store \
    copilot-for-linux \
    peazip \
    winduxedu-troubleshooting \
    winduxedu-sticky-keys \
    winduxedu-widgets \
    winduxedu-windowshit \
    winduxedu-winsat \
    winduxedu-winver; do
    require_path "usr/local/share/elevende-shell/icons/64x64/apps/${icon}.png"
done

# The generated override must route through the shared ElevenDE adapter and
# refer to the matching icon alias rather than an upstream generic fallback.
COMPONENT_DESKTOP="$WORK/winduxedu-store.desktop"
cat_image_file 'usr/local/share/applications/winduxedu-store.desktop' "$COMPONENT_DESKTOP"
grep -q '^Exec=/usr/local/libexec/winduxedu-component-launch winduxedu-store$' "$COMPONENT_DESKTOP"
grep -q '^Icon=winduxedu-store$' "$COMPONENT_DESKTOP"
if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$COMPONENT_DESKTOP"
fi

# User-requested upstream helpers must not remain in All Apps.  Validate the
# actual expanded filesystem rather than trusting the hook source.
for removed_entry in picom.desktop lxqt-config-session.desktop kbd-layout-viewer5.desktop calamares.desktop install-system.desktop guvcview.desktop guvcview-viewer.desktop; do
    if [ -e "$FULL_ROOT/usr/share/applications/$removed_entry" ] || [ -e "$FULL_ROOT/usr/local/share/applications/$removed_entry" ]; then
        echo "final ISO still exposes a removed desktop entry: $removed_entry" >&2
        exit 1
    fi
done
TERMINAL_ENTRY="$WORK/xterm.desktop"
cat_image_file 'usr/local/share/applications/xterm.desktop' "$TERMINAL_ENTRY"
grep -q 'DejaVu Sans Mono' "$TERMINAL_ENTRY"
grep -q 'XTerm\*background:#000000' "$TERMINAL_ENTRY"
# Requested: XTerm stays installed but leaves the Start menu; the desktop
# shortcut is a separate copy that must NOT carry NoDisplay.
grep -qx 'NoDisplay=true' "$TERMINAL_ENTRY"
XTERM_SHORTCUT="$WORK/xterm-shortcut"
cat_image_file 'etc/skel/Desktop/终端.desktop' "$XTERM_SHORTCUT"
! grep -q '^NoDisplay=' "$XTERM_SHORTCUT"
FONTCONF="$WORK/winduxedu-fontconfig.xml"
cat_image_file 'etc/fonts/local.conf' "$FONTCONF"
grep -q '<family>DejaVu Sans Mono</family>' "$FONTCONF"
grep -q '<family>Noto Sans CJK SC</family>' "$FONTCONF"
! grep -q '<test name="lang" compare="contains"><string>zh</string></test>' "$FONTCONF"
XTERM_RESOURCES="$WORK/elevende-xresources"
cat_image_file 'etc/X11/Xresources.d/elevende' "$XTERM_RESOURCES"
grep -q '^XTerm\*faceName: DejaVu Sans Mono,Noto Sans CJK SC$' "$XTERM_RESOURCES"
grep -q '^XTerm\*cjkWidth: false$' "$XTERM_RESOURCES"
grep -q '^XTerm\*background: #000000$' "$XTERM_RESOURCES"

# ---- field report round 2 -------------------------------------------------
# All checks below validate the expanded filesystem, never the hook source,
# so a packaging regression cannot hide behind a correct script.

# (6) Duplicate apt sources could not be reproduced -- the evidence had been
# deleted before it reached us -- so the image prints its whole apt picture on
# every run and only a *literally* duplicated line fails.  That keeps the next
# occurrence in CI's log instead of in the classroom.
echo '--- apt sources shipped in the final image ---'
if [ -f "$FULL_ROOT/etc/apt/sources.list" ]; then
    sed 's/^/  /' "$FULL_ROOT/etc/apt/sources.list"
else
    echo '  (no /etc/apt/sources.list)'
fi
if [ -d "$FULL_ROOT/etc/apt/sources.list.d" ]; then
    for source_file in "$FULL_ROOT"/etc/apt/sources.list.d/*; do
        [ -f "$source_file" ] || continue
        echo "  # ${source_file#$FULL_ROOT/}"
        sed 's/^/  /' "$source_file"
    done
fi
apt_source_lines() {
    local source_file
    if [ -f "$FULL_ROOT/etc/apt/sources.list" ]; then
        grep -hEv '^[[:space:]]*(#|$)' "$FULL_ROOT/etc/apt/sources.list" || true
    fi
    if [ -d "$FULL_ROOT/etc/apt/sources.list.d" ]; then
        for source_file in "$FULL_ROOT"/etc/apt/sources.list.d/*; do
            [ -f "$source_file" ] || continue
            grep -hEv '^[[:space:]]*(#|$)' "$source_file" || true
        done
    fi
    return 0
}
duplicated_sources="$(apt_source_lines | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' | sort | uniq -d)"
if [ -n "$duplicated_sources" ]; then
    echo 'duplicate apt source line(s) in the final image:' >&2
    printf '  %s\n' "$duplicated_sources" >&2
    exit 1
fi

# (1) ONLYOFFICE must keep one window with tabs instead of one window per
# double-clicked document.
grep -qx 'editorWindowMode = true' \
    "$FULL_ROOT/etc/skel/.config/onlyoffice/DesktopEditors.conf" || {
    echo 'ONLYOFFICE single-window mode is not set in the skeleton' >&2
    exit 1
}

# (3) Typing Chinese must go back to English on a plain Shift press.  fcitx5's
# compiled default only recognises the left shift key, so both keys are
# configured explicitly (and Deactivate covers the "session started in
# English" state where AltTrigger deliberately does nothing).
FCITX_CONF="$FULL_ROOT/etc/skel/.config/fcitx5/config"
grep -qx 'AltTriggerKeys=Shift_L Shift_R' "$FCITX_CONF" || {
    echo 'fcitx5 Shift trigger is not configured for both shift keys' >&2
    exit 1
}
grep -qx 'DeactivateKeys=Shift_L Shift_R' "$FCITX_CONF" || {
    echo 'fcitx5 Shift deactivate trigger is missing' >&2
    exit 1
}

# (4) Double-clicking an archive must reach PeaZip: the record has to launch
# through the adapter, its entry point has to resolve inside the image, and it
# has to be the registered default for archives.
PEAZIP_ENTRY="$FULL_ROOT/usr/local/share/applications/peazip.desktop"
PEAZIP_EXEC="$(sed -n 's/^Exec=//p' "$PEAZIP_ENTRY" | head -n1)"
case "$PEAZIP_EXEC" in
    /usr/local/libexec/winduxedu-component-launch\ *) ;;
    *)
        echo "PeaZip entry does not launch through the adapter: $PEAZIP_EXEC" >&2
        exit 1
        ;;
esac
PEAZIP_CMD="${PEAZIP_EXEC#*winduxedu-component-launch }"
PEAZIP_CMD="${PEAZIP_CMD%% *}"
case "$PEAZIP_CMD" in
    /*) peazip_resolved="$FULL_ROOT$PEAZIP_CMD" ;;
    *)
        # The hook may have resolved to various locations; check all common ones.
        peazip_resolved=""
        for cand in \
            "$FULL_ROOT/usr/bin/$PEAZIP_CMD" \
            "$FULL_ROOT/usr/local/bin/$PEAZIP_CMD" \
            "$FULL_ROOT/usr/lib/peazip/$PEAZIP_CMD" \
            "$FULL_ROOT/opt/peazip/$PEAZIP_CMD"; do
            if [ -x "$cand" ]; then
                peazip_resolved="$cand"
                break
            fi
        done
        if [ -z "$peazip_resolved" ]; then
            echo "PeaZip entry point does not resolve inside the image: $PEAZIP_CMD" >&2
            exit 1
        fi
        ;;
esac
if [ ! -x "$peazip_resolved" ]; then
    echo "PeaZip entry point does not resolve inside the image: $PEAZIP_CMD" >&2
    exit 1
fi
grep -q '^MimeType=.*application/zip' "$PEAZIP_ENTRY" || {
    echo 'PeaZip entry does not advertise application/zip' >&2
    exit 1
}
grep -qx 'application/zip=peazip.desktop' "$FULL_ROOT/etc/xdg/mimeapps.list" || {
    echo 'application/zip has no PeaZip default handler' >&2
    exit 1
}
for vendor_peazip in "$FULL_ROOT"/usr/share/applications/peazip*.desktop; do
    [ -f "$vendor_peazip" ] || continue
    echo "vendor PeaZip record still competes with ours: ${vendor_peazip#$FULL_ROOT/}" >&2
    exit 1
done

# (5) Image viewer defaults to eog (GNOME Image Viewer) instead of Edge.
for img_mime in image/jpeg image/png image/gif image/bmp image/x-ico image/tiff \
    image/webp image/svg+xml image/x-portable-pixmap image/x-portable-bitmap \
    image/x-portable-graymap image/x-xcf image/x-xcf-gimp; do
    grep -qx "$img_mime=eog.desktop" "$FULL_ROOT/etc/xdg/mimeapps.list" || {
        echo "image MIME type $img_mime does not default to eog.desktop" >&2
        exit 1
    }
done

# (6) Automount udev rule for removable media.
[ -f "$FULL_ROOT/etc/udev/rules.d/99-winduxedu-automount.rules" ] || {
    echo 'missing 99-winduxedu-automount.rules' >&2
    exit 1
}
grep -q 'RUN+="/usr/bin/udisksctl mount' "$FULL_ROOT/etc/udev/rules.d/99-winduxedu-automount.rules" || {
    echo 'automount rule does not call udisksctl mount' >&2
    exit 1
}

# (7) The requested desktop, on top of 此电脑 / 主目录 / Edge / 终端.
# Mirror ElevenDE theme_find(): a bare Icon= only renders if the shell can open
# it from its own namespace, /usr/share/pixmaps or a hicolor/theme directory,
# and an absolute one only if the file is readable.  Anything else is the blank
# generic glyph the field report described.
icon_art_resolves() {
    local name="${1//./\\.}"
    grep -q -E \
        "(^|/)(usr/local/share/elevende-shell/icons/(32x32|48x48|64x64|128x128|256x256|scalable)/(apps|places|devices|mimetypes)|usr/share/pixmaps|usr/share/icons/(hicolor|Adwaita|Papirus|Kali|gnome|Adwaita-Dark)/(16x16|22x22|24x24|32x32|48x48|64x64|96x96|128x128|256x256|512x512|scalable)/(apps|places|devices|mimetypes))/${name}\\.(png|svg)$" \
        "$LIST"
}
for shortcut in 希沃白板 班级优化大师 视频展台 希沃管家 微信 QQ 钉钉 ONLYOFFICE; do
    shortcut_file="$FULL_ROOT/etc/skel/Desktop/$shortcut.desktop"
    [ -s "$shortcut_file" ] || {
        echo "missing desktop shortcut in the skeleton: $shortcut" >&2
        exit 1
    }
    grep -q '^Name=' "$shortcut_file" || {
        echo "desktop shortcut has no Name: $shortcut" >&2
        exit 1
    }
    grep -q '^Exec=' "$shortcut_file" || {
        echo "desktop shortcut has no Exec: $shortcut" >&2
        exit 1
    }
    ! grep -q '^NoDisplay=true' "$shortcut_file" || {
        echo "desktop shortcut is hidden by NoDisplay: $shortcut" >&2
        exit 1
    }
    ! grep -q '^Hidden=true' "$shortcut_file" || {
        echo "desktop shortcut is hidden by Hidden: $shortcut" >&2
        exit 1
    }
    # The icon is the half of the field report that a Name/Exec check cannot
    # see.  theme_find() takes the value verbatim: an absolute path has to be
    # openable, a bare name has to exist in the shell's own icon namespace,
    # and anything else renders as a blank generic glyph on the teacher's
    # desktop.  Vendor entries name /opt/apps/... paths, which is exactly why
    # hook 1550 publishes the art and rewrites the record to a short name.
    shortcut_icon="$(sed -n 's/^Icon=//p' "$shortcut_file" | head -n 1)"
    [ -n "$shortcut_icon" ] || {
        echo "desktop shortcut has no Icon=: $shortcut" >&2
        exit 1
    }
    case "$shortcut_icon" in
    /*)
        [ -r "$FULL_ROOT$shortcut_icon" ] || {
            echo "desktop shortcut $shortcut points at an unreadable Icon= ($shortcut_icon)" >&2
            exit 1
        }
        ;;
    *)
        icon_art_resolves "$shortcut_icon" || {
            echo "desktop shortcut $shortcut has no art for Icon= ($shortcut_icon) anywhere the shell looks" >&2
            exit 1
        }
        ;;
    esac
done

# Touchscreen stack.  A panel reaches X through three gates -- libudev has to
# tag the node, an InputClass has to leave it enabled (the last matching one
# decides "Ignore"), and the libinput driver has to be the one bound.  Each is
# a separate way for the keyboard to keep working while touch is dead, so each
# is checked on the finished image rather than on the configuration that was
# supposed to produce it.
for input_pkg in xserver-xorg-core xserver-xorg-input-libinput xinput \
    xinput-calibrator libinput-tools; do
    grep -qx "Package: $input_pkg" "$FULL_ROOT/var/lib/dpkg/status" || {
        echo "$input_pkg is not installed" >&2
        exit 1
    }
done
TOUCH_CLASS="$WORK/winduxedu-touchscreen.conf"
cat_image_file 'etc/X11/xorg.conf.d/99-winduxedu-touchscreen.conf' "$TOUCH_CLASS"
grep -q 'MatchIsTouchscreen "on"' "$TOUCH_CLASS" || {
    echo 'the touchscreen InputClass does not match touchscreens' >&2
    exit 1
}
grep -q 'MatchProduct "touch" "Touch" "TOUCH"' "$TOUCH_CLASS" || {
    echo 'the touchscreen InputClass has no case-complete name-keyed rescue section' >&2
    exit 1
}
grep -q 'Driver "libinput"' "$TOUCH_CLASS" || {
    echo 'the touchscreen InputClass does not bind libinput' >&2
    exit 1
}
! grep -qiE 'Option[[:space:]]+"Ignore"[[:space:]]+"(true|on|yes|1)"' "$TOUCH_CLASS" || {
    echo 'the touchscreen InputClass disables the devices it matches' >&2
    exit 1
}
TOUCH_RULE="$WORK/winduxedu-touchscreen.rules"
cat_image_file 'etc/udev/rules.d/99-winduxedu-touchscreen.rules' "$TOUCH_RULE"
grep -q 'ENV{ID_INPUT_TOUCHSCREEN}="1"' "$TOUCH_RULE" || {
    echo 'the touchscreen udev rule does not tag the device as a touchscreen' >&2
    exit 1
}
# A node libudev never tagged with ID_INPUT at all is invisible to the X
# server's udev backend: no InputClass can reach a device X did not add.
grep -q 'ENV{ID_INPUT}="1"' "$TOUCH_RULE" || {
    echo 'the touchscreen udev rule does not set ID_INPUT' >&2
    exit 1
}
# A touchpad must never be re-tagged: the rule is only a rescue for panels,
# and a laptop's touchpad keeps working through its own libudev tag.
grep -q 'ENV{ID_INPUT_TOUCHPAD}!="1"' "$TOUCH_RULE" || {
    echo 'the touchscreen udev rule does not exclude touchpads' >&2
    exit 1
}
# "Option Ignore" is decided by the last matching InputClass, so a snippet
# that disables the touch node wins purely by sorting after ours.
for xconf in "$FULL_ROOT"/etc/X11/xorg.conf.d/*.conf; do
    [ -f "$xconf" ] || continue
    case "$(basename "$xconf")" in
    99-winduxedu-*) continue ;;
    esac
    grep -qiE 'Option[[:space:]]+"Ignore"[[:space:]]+"(true|on|yes|1)"' "$xconf" || continue
    if [ "$(basename "$xconf")" \> "99-winduxedu-touchscreen.conf" ]; then
        echo "$xconf disables input devices and sorts after the WinduxEdu touchscreen class" >&2
        exit 1
    fi
done
# The main config file is parsed after every conf.d directory, so a vendor
# /etc/X11/xorg.conf that switches hotplug off cannot be overridden there.
if [ -f "$FULL_ROOT/etc/X11/xorg.conf" ] && \
        grep -qiE '^[[:space:]]*Option[[:space:]]+"Auto(Add|Enable)Devices"[[:space:]]+"(false|off|no|0)"' \
        "$FULL_ROOT/etc/X11/xorg.conf"; then
    echo '/etc/X11/xorg.conf disables hotplug; the touch node would never be added' >&2
    exit 1
fi

# (8) The screen keyboard is onboard now; the retired matchbox-keyboard must
# be neither installed nor referenced by the supervisor.
grep -qx 'Package: onboard' "$FULL_ROOT/var/lib/dpkg/status" || {
    echo 'onboard is not installed' >&2
    exit 1
}
if grep -qx 'Package: matchbox-keyboard' "$FULL_ROOT/var/lib/dpkg/status" ||
    grep -qx 'Package: matchbox-keyboard-im' "$FULL_ROOT/var/lib/dpkg/status"; then
    echo 'matchbox-keyboard is still installed' >&2
    exit 1
fi
OSKD_HELPER="$WORK/winduxedu-oskd"
cat_image_file 'usr/local/bin/winduxedu-oskd' "$OSKD_HELPER"
grep -q '\["onboard"\]' "$OSKD_HELPER" || {
    echo 'winduxedu-oskd does not start onboard' >&2
    exit 1
}
# Only the launch command matters here: the helper still documents the swap in
# its docstring and comments.
! grep -q '\["matchbox-keyboard"\]' "$OSKD_HELPER"

# (9) (10) List every terminal record All Apps would show.  Debian ships
# debian-xterm.desktop / debian-uxterm.desktop rather than xterm.desktop --
# which is why the old removal silently never matched -- and their bare
# "xterm" Exec is also why the Start menu terminal had the wrong font.
# NoDisplay records are invisible and are only listed for reference.
visible_terminals=0
for stock_entry in "$FULL_ROOT"/usr/share/applications/*.desktop \
    "$FULL_ROOT"/usr/local/share/applications/*.desktop; do
    [ -f "$stock_entry" ] || continue
    grep -Eq '^Exec=([^[:space:]]*/)?(u|l|koi8r)?xterm([[:space:]]|$)' "$stock_entry" ||
        continue
    if grep -q '^NoDisplay=true' "$stock_entry" ||
        grep -q '^Hidden=true' "$stock_entry"; then
        echo "  (hidden) ${stock_entry#$FULL_ROOT/}"
        continue
    fi
    visible_terminals=$((visible_terminals + 1))
    echo "  ${stock_entry#$FULL_ROOT/}"
done
echo "  visible stock terminal records: $visible_terminals (0 expected)"
if [ "$visible_terminals" -ne 0 ]; then
    echo 'All Apps still exposes a stock terminal record' >&2
    exit 1
fi
# Every entry point runs through the profile wrapper.
XTERM_WRAPPER="$WORK/xterm-wrapper"
cat_image_file 'usr/local/bin/xterm' "$XTERM_WRAPPER"
grep -q -- '-fa "DejaVu Sans Mono,Noto Sans CJK SC"' "$XTERM_WRAPPER"
grep -q 'XTerm\*cjkWidth:false' "$XTERM_WRAPPER"

# (11) Every sidebar mini-app entry point must survive a bare execve: a script
# without a shebang makes .NET's Process.Start do nothing at all.
for miniapp in "$FULL_ROOT"/etc/EasiSideBar/MiniApps/*; do
    [ -f "$miniapp" ] || continue
    [ -s "$miniapp" ] || continue
    miniapp_exec="$(sed -n 's/^ExecutablePath=//p' "$miniapp" | head -n1)"
    [ -n "$miniapp_exec" ] || continue
    miniapp_target="$FULL_ROOT$miniapp_exec"
    [ -f "$miniapp_target" ] || {
        echo "sidebar entry point missing: $miniapp_exec" >&2
        exit 1
    }
    case "$(head -c4 "$miniapp_target" | od -An -tx1 | tr -d ' \n')" in
        7f454c46* | 2321*) ;;
        *)
            # The hook leaves a non-ELF binary alone (an interpreter line
            # would corrupt it), but a *text* target without a shebang is the
            # exact "click does nothing" failure this item is about.
            if LC_ALL=C grep -Iq '' "$miniapp_target"; then
                echo "sidebar entry point has no shebang: $miniapp_exec" >&2
                exit 1
            fi
            ;;
    esac
done

# (12) Nothing pulls pipewire in -- ElevenDE starts through a system service,
# not a systemd user session -- so the session owns an audio bootstrap and a
# shortcut repair loop, and both must be registered with the helper list.
AUDIO_HELPER="$WORK/winduxedu-audio-session"
cat_image_file 'usr/local/bin/winduxedu-audio-session' "$AUDIO_HELPER"
grep -q 'pactl info' "$AUDIO_HELPER"
grep -q 'pipewire-pulse' "$AUDIO_HELPER"
TIDY_HELPER="$WORK/winduxedu-desktop-tidy"
cat_image_file 'usr/local/bin/winduxedu-desktop-tidy' "$TIDY_HELPER"
grep -q 'repair_dir' "$TIDY_HELPER"

# (5) The education switches must be observable, and every source the applier
# restores from must exist: otherwise the page reverts itself two seconds later
# ("勾选后自动取消") and 希沃管家开机自启 can never come back at all.
EDU_SETTINGS="$WORK/winduxedu-edu-settings"
cat_image_file 'usr/local/bin/winduxedu-edu-settings' "$EDU_SETTINGS"
grep -q '^escalate() {' "$EDU_SETTINGS"
grep -q 'edu-escalation.log' "$EDU_SETTINGS"
! grep -q 'exec pkexec' "$EDU_SETTINGS"
EDU_APPLY="$WORK/winduxedu-edu-apply"
cat_image_file 'usr/local/libexec/winduxedu-edu-apply' "$EDU_APPLY"
grep -q 'restore_autostart com.seewo.terminalmanager.desktop required' "$EDU_APPLY"
grep -q 'restore_autostart com.seewo.easisidebar.desktop required' "$EDU_APPLY"
grep -q 'sanitize_autostart' "$EDU_APPLY"
# The switch key must only become visible once the effect really happened, or
# a failed escalation still looks like a success and the page reverts a
# correct value instead of reporting the failure.
apply_line="$(grep -n 'sidebar-autostart) apply_sidebar' "$EDU_APPLY" |
    cut -d: -f1 || true)"
persist_line="$(grep -n '^persist_key$' "$EDU_APPLY" | tail -n1 |
    cut -d: -f1 || true)"
if [ -z "$apply_line" ] || [ -z "$persist_line" ] ||
    [ "$persist_line" -le "$apply_line" ]; then
    echo 'winduxedu-edu-apply must persist the switch key only after the effect' >&2
    exit 1
fi
# Every 希沃 package the settings page labels has to be reachable from the
# uninstall button, otherwise clicking it silently does nothing.
EDU_UNINSTALL="$WORK/winduxedu-edu-uninstall"
cat_image_file 'usr/local/libexec/winduxedu-edu-uninstall' "$EDU_UNINSTALL"
for seewo_pkg in $(grep -oE 'com\.seewo\.[a-z0-9.]+' "$EDU_SETTINGS" | sort -u); do
    grep -q "$seewo_pkg" "$EDU_UNINSTALL" || {
        echo "seewo package $seewo_pkg is offered by the settings page but missing from the uninstall allow-list" >&2
        exit 1
    }
done
# And hook 1550 must really have kept the restore copy (it backs the vendor
# autostart entry up before dropping it, seeding from the menu entry when the
# vendor deb installs none).
[ -s "$FULL_ROOT/usr/share/winduxedu/vendor-autostart/com.seewo.terminalmanager.desktop" ] || {
    echo '希沃管家 autostart entry was not backed up; 教育版设置 cannot restore it' >&2
    exit 1
}

# The collected proprietary teaching applications must be installed: eight
# collected apps plus the seven sidebar components (希沃侧边栏, its UDI hotspot
# dependency and five 希沃 miniapps, among them 桌面批注).  希沃管家
# (com.seewo.terminalmanager), whose bogus "libstdc++6 (<< 9)" clause hook 1550
# rewrites out of the control file before handing it to apt.
DPKG_STATUS="$FULL_ROOT/var/lib/dpkg/status"
for edu_package in \
    onlyoffice-desktopeditors \
    com.seewo.easinote5 \
    com.seewo.easicare \
    com.seewo.easicamera \
    com.seewo.terminalmanager \
    linuxqq \
    wechat \
    com.alibabainc.dingtalk \
    com.seewo.easisidebar \
    udi-hotspot-service \
    com.seewo.easiminiapps.desktopscreenshot \
    com.seewo.easiminiapps.desktoptimer \
    com.seewo.easiminiapps.luckyrandom \
    com.seewo.easiminiapps.rollcall \
    com.seewo.easiminiapps.desktopinkannotation; do
    grep -qx "Package: $edu_package" "$DPKG_STATUS" || {
        echo "proprietary teaching application missing from dpkg status: $edu_package" >&2
        exit 1
    }
done
# Menu visibility: the whiteboard and terminal-manager entries only ship under
# /opt/apps/..., so the install hook must have exported a real, non-empty
# /usr/share/applications counterpart.  The terminal manager DEB ships a
# zero-byte placeholder there, so an existence test alone would not suffice.
require_path 'usr/share/applications/com.seewo.easinote5.desktop'
require_path 'usr/share/applications/com.alibabainc.dingtalk.desktop'
require_path 'usr/share/applications/com.seewo.terminalmanager.desktop'
[ -s "$FULL_ROOT/usr/share/applications/com.seewo.terminalmanager.desktop" ] || {
    echo 'exported Seewo Terminal Manager menu entry is empty' >&2
    exit 1
}
# Vendor boot-time activations stay off in a generic Live image: the MAXHUB
# alfred D-Bus service, the Seewo NIC script and the hotspot unit are masked
# through /etc/systemd/system (unit files themselves remain dpkg-owned), and
# the terminal manager's *session* autostart entry is removed.  All three
# still launch on demand from the menu where the vendor intends them to.
for masked_unit in \
    com.cvte.maxhub.alfred.service \
    disable-seewo-network-card.service \
    com.ifpdos.udi.hotspot.service; do
    mask_target="$(readlink "$FULL_ROOT/etc/systemd/system/$masked_unit" 2>/dev/null || true)"
    [ "$mask_target" = "/dev/null" ] || {
        echo "vendor unit is not masked in the final image: $masked_unit (got: ${mask_target:-absent})" >&2
        exit 1
    }
done
# 希沃管家 is the deliberate exception and must never be masked again: the
# SeewoServiceAssistant window reads its data from hugo_launcher, so a masked
# backend is what produced "Cannot read property 'data' of undefined".  The
# Live image has no installer step that could enable it later, hence the
# activation link has to be present in the shipped filesystem.
require_path 'usr/lib/systemd/system/com.seewo.terminalmanager.service'
[ -L "$FULL_ROOT/etc/systemd/system/com.seewo.terminalmanager.service" ] && {
    echo 'Seewo Terminal Manager backend is masked in the final image' >&2
    exit 1
}
[ -L "$FULL_ROOT/etc/systemd/system/multi-user.target.wants/com.seewo.terminalmanager.service" ] || {
    echo 'Seewo Terminal Manager backend is not enabled at boot in the final image' >&2
    exit 1
}
if [ -e "$FULL_ROOT/etc/xdg/autostart/com.seewo.terminalmanager.desktop" ]; then
    echo 'Seewo Terminal Manager autostart entry survived into the final image' >&2
    exit 1
fi

# 希沃侧边栏 registers a *user* systemd unit, so its default-off switch lives
# in the global /etc/systemd/user namespace instead of /etc/systemd/system.
# Both the mask and the absence of an activation link are required: the sidebar
# is third-party internet software (non-open-source, unrelated to WinduxEdu /
# SYSTEM-Intel-MIC) and 教育版设置 → 侧边栏 is what turns it on.
sidebar_mask="$(readlink "$FULL_ROOT/etc/systemd/user/com.seewo.easisidebar.service" 2>/dev/null || true)"
[ "$sidebar_mask" = "/dev/null" ] || {
    echo "the sidebar user unit is not globally masked (got: ${sidebar_mask:-absent})" >&2
    exit 1
}
for wants_link in \
    "$FULL_ROOT/etc/systemd/user/default.target.wants/com.seewo.easisidebar.service" \
    "$FULL_ROOT/etc/systemd/user/graphical-session.target.wants/com.seewo.easisidebar.service"; do
    if [ -e "$wants_link" ] || [ -L "$wants_link" ]; then
        echo "the sidebar user unit still has an activation link: ${wants_link#$FULL_ROOT}" >&2
        exit 1
    fi
done
# The 批注 (desktop ink annotation) tool is a *sidebar* miniapp: its postinst
# drops miniapp.info into /etc/EasiSideBar/MiniApps and the sidebar builds its
# toolbar entry from that file, so a missing registration means no 批注.
annotation_info="$FULL_ROOT/etc/EasiSideBar/MiniApps/com.cvte.seewo.desktop_annotation"
if [ ! -s "$annotation_info" ]; then
    echo "sidebar annotation miniapp registration missing: ${annotation_info#$FULL_ROOT}" >&2
    exit 1
fi
grep -q 'DesktopInkAnnotation' "$annotation_info" || {
    echo "sidebar annotation registration does not point at DesktopInkAnnotation" >&2
    exit 1
}
[ -x "$FULL_ROOT/opt/apps/com.seewo.easiminiapps.desktopinkannotation/files/bin/DesktopInkAnnotation" ] || {
    echo "the annotation binary is missing from the image" >&2
    exit 1
}
# EasiSideBar hard-codes "Noto Sans CJK SC" in its Avalonia host and declares
# no Depends, so the font is a hard requirement: without it the unit crash-
# loops with StandardOutput=null and the failure is invisible in the journal.
grep -qx 'Package: fonts-noto-cjk' "$DPKG_STATUS" || {
    echo 'fonts-noto-cjk is missing; EasiSideBar would crash-loop on first start' >&2
    exit 1
}

# 希沃白板 (task): the menu entry must launch the real EasiNote5 program from
# the vendor's program directory, never the wrapper shell script.
EASI_DESKTOP_FILE="$WORK/easinote5.desktop"
cat_image_file 'usr/share/applications/com.seewo.easinote5.desktop' "$EASI_DESKTOP_FILE"
grep -Eq '^Exec=.*(/EasiNote5|winduxedu-easinote5)([[:space:]]|$)' "$EASI_DESKTOP_FILE"
if grep -Eq '^Exec=.*\.sh([[:space:]]|$)' "$EASI_DESKTOP_FILE"; then
    echo 'the EasiNote5 menu entry still launches a vendor shell script' >&2
    exit 1
fi

# 钉钉 (task): the vendor's own Debian library-removal loop only executes
# inside `for file in $(ls /home)`, which never runs while the image still has
# an empty /home.  Hook 1550 re-runs it; these are the members that made the
# bundled web view die with a GLIBC_... symbol lookup error against the system
# libgtk-3.so.0.
DT_FILES_ROOT="$FULL_ROOT/opt/apps/com.alibabainc.dingtalk/files"
[ -d "$DT_FILES_ROOT" ] || {
    echo 'DingTalk release directory is missing from the final image' >&2
    exit 1
}
# files/ carries the versioned release next to Chromium's locales/crashpad/...
# siblings, so no single child directory may be taken as "the" release: the
# whole tree is what ships, and the whole tree is what gets checked.
if [ -z "$(find "$DT_FILES_ROOT" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print -quit)" ]; then
    echo 'DingTalk ships no release directory in the final image' >&2
    exit 1
fi
for stale in libm.so.6 libstdc++.so.6 libstdc++.so.6.0.25 \
    libgbm.so.1.0.0 libGLX.so.0.0.0 libGLdispatch.so.0.0.0; do
    if [ -n "$(find "$DT_FILES_ROOT" -name "$stale" \( -type f -o -type l \) -print -quit)" ]; then
        echo "DingTalk still ships an incompatible bundled library: $stale" >&2
        exit 1
    fi
done

# ONLYOFFICE (task): it must be the system-wide default application/pdf
# handler, and must advertise the MIME type itself so the association sticks.
MIMEAPPS_LIST="$WORK/mimeapps.list"
cat_image_file 'etc/xdg/mimeapps.list' "$MIMEAPPS_LIST"
oo_entry="$(grep -m1 '^application/pdf=' "$MIMEAPPS_LIST" | cut -d= -f2 || true)"
case "$oo_entry" in
    onlyoffice*.desktop) ;;
    *)
        echo "application/pdf is not handled by ONLYOFFICE: ${oo_entry:-absent}" >&2
        exit 1
        ;;
esac
require_path "usr/share/applications/$oo_entry"
OO_DESKTOP_FILE="$WORK/onlyoffice.desktop"
cat_image_file "usr/share/applications/$oo_entry" "$OO_DESKTOP_FILE"
grep -q '^MimeType=.*application/pdf' "$OO_DESKTOP_FILE"

# Double-clicking a Windows program must reach Wine: ElevenDE hands every file
# to xdg-open, i.e. to the default recorded here, so an absent or dangling
# entry is what made .exe inert.
exe_entry="$(grep -m1 '^application/x-ms-dos-executable=' "$MIMEAPPS_LIST" |
    cut -d= -f2 || true)"
[ -n "$exe_entry" ] || {
    echo 'application/x-ms-dos-executable has no default handler in the final image' >&2
    exit 1
}
EXE_DESKTOP_FILE=""
for exe_candidate in "$FULL_ROOT/usr/share/applications/$exe_entry" \
    "$FULL_ROOT/usr/local/share/applications/$exe_entry"; do
    [ -f "$exe_candidate" ] || continue
    EXE_DESKTOP_FILE="$exe_candidate"
    break
done
[ -n "$EXE_DESKTOP_FILE" ] || {
    echo "default .exe handler desktop entry is missing: $exe_entry" >&2
    exit 1
}
grep -qi '^Exec=.*wine' "$EXE_DESKTOP_FILE" || {
    echo "default .exe handler does not run Wine: $exe_entry" >&2
    exit 1
}
grep -q '^MimeType=.*application/x-ms-dos-executable' "$EXE_DESKTOP_FILE" || {
    echo "handler does not advertise application/x-ms-dos-executable: $exe_entry" >&2
    exit 1
}

# All Apps must not surface session/power helpers as regular applications.  This
# validates the fully installed filesystem rather than trusting the source hook.
for desktop_file in "$FULL_ROOT"/usr/share/applications/*.desktop "$FULL_ROOT"/usr/local/share/applications/*.desktop; do
    [ -f "$desktop_file" ] || continue
    if grep -Eqi \
        '^(Name|Name\[zh_CN\]|GenericName|Comment)=.*(Shutdown|Shut Down|Power Off|Restart|Reboot|Log ?Out|Logoff|Logout|Suspend|Sleep|Hibernate|Lock Screen|Lock Session|关机|重启|重新启动|注销|登出|睡眠|挂起|休眠|锁屏|锁定)' \
        "$desktop_file" || \
       grep -Eqi \
        '^Exec=.*(systemctl[[:space:]]+(poweroff|reboot|suspend|hibernate)|loginctl[[:space:]]+(poweroff|reboot|suspend|hibernate|terminate-session|lock-session)|lxqt-leave|xfce4-session-logout|mate-session-save|openbox[[:space:]]+--exit|gnome-session-quit|(^|[[:space:]])(poweroff|reboot|shutdown|logout|logoff|xscreensaver-command|dm-tool)[[:space:]])' \
        "$desktop_file"; then
        echo "final ISO still exposes a forbidden system-command desktop entry: ${desktop_file#$FULL_ROOT/}" >&2
        exit 1
    fi
done

printf 'WinduxEdu 1.0 final ISO content validation passed: %s\n' "$ISO"
