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
grep -q 'single long-lived process' "$SESSION_SCRIPT"
DISPLAY_LAUNCHER="$WORK/winduxedu-elevende-display"
cat_image_file 'usr/local/sbin/winduxedu-elevende-display' "$DISPLAY_LAUNCHER"
grep -q 'if \[ -f "\$LOGOUT_MARKER" \]' "$DISPLAY_LAUNCHER"
grep -q 'explicit logout; restarting native ElevenDE session' "$DISPLAY_LAUNCHER"
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
grep -q 'systemctl --no-wall poweroff' "$PRIVILEGED_ACTION"
grep -q 'systemctl --no-wall reboot' "$PRIVILEGED_ACTION"
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
    usr/local/bin/sas-screen; do
    require_path "$path"
done

# SAS footer power actions must share Start's fixed-function bridge rather
# than attempting unprivileged systemctl calls that silently fail after install.
if ! strings -el "$FULL_ROOT/usr/local/bin/sas-screen" | grep -q '/usr/local/bin/winduxedu-power-action'; then
    echo 'final ISO SAS binary does not route power actions through WinduxEdu bridge' >&2
    exit 1
fi

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
for removed_entry in picom.desktop lxqt-config-session.desktop kbd-layout-viewer5.desktop calamares.desktop install-system.desktop; do
    if [ -e "$FULL_ROOT/usr/share/applications/$removed_entry" ] || [ -e "$FULL_ROOT/usr/local/share/applications/$removed_entry" ]; then
        echo "final ISO still exposes a removed desktop entry: $removed_entry" >&2
        exit 1
    fi
done
TERMINAL_ENTRY="$WORK/xterm.desktop"
cat_image_file 'usr/local/share/applications/xterm.desktop' "$TERMINAL_ENTRY"
grep -q 'DejaVu Sans Mono' "$TERMINAL_ENTRY"
grep -q 'XTerm\*background:#000000' "$TERMINAL_ENTRY"
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

# The collected proprietary teaching applications must be installed, including
# 希沃管家 (com.seewo.terminalmanager), whose bogus "libstdc++6 (<< 9)" clause
# hook 1550 rewrites out of the control file before handing it to apt.
DPKG_STATUS="$FULL_ROOT/var/lib/dpkg/status"
for edu_package in \
    onlyoffice-desktopeditors \
    com.seewo.easinote5 \
    com.seewo.easicare \
    com.seewo.easicamera \
    com.seewo.terminalmanager \
    linuxqq \
    wechat \
    com.alibabainc.dingtalk; do
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
# Vendor boot-time activations stay off in a generic Live image: the terminal
# manager daemon, the MAXHUB alfred D-Bus service and the Seewo NIC script are
# masked through /etc/systemd/system (unit files themselves remain dpkg-owned),
# and the terminal manager's session autostart entry is removed.  All three
# still launch on demand from the menu where the vendor intends them to.
for masked_unit in \
    com.seewo.terminalmanager.service \
    com.cvte.maxhub.alfred.service \
    disable-seewo-network-card.service; do
    mask_target="$(readlink "$FULL_ROOT/etc/systemd/system/$masked_unit" 2>/dev/null || true)"
    [ "$mask_target" = "/dev/null" ] || {
        echo "vendor unit is not masked in the final image: $masked_unit (got: ${mask_target:-absent})" >&2
        exit 1
    }
done
if [ -e "$FULL_ROOT/etc/xdg/autostart/com.seewo.terminalmanager.desktop" ]; then
    echo 'Seewo Terminal Manager autostart entry survived into the final image' >&2
    exit 1
fi

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
