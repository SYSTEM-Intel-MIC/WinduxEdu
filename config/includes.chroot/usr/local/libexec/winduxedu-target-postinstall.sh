#!/bin/sh
set -eu

# This script runs inside the newly installed target through Calamares
# shellprocess. It must be safe to run more than once.
TARGET=/

# The Live image starts a temporary `user` session directly. The installed
# system must never preserve that identity or bypass authentication: ElevenDE's
# own Win11-style login gate authenticates the Calamares-created account.
if command -v systemctl >/dev/null 2>&1; then
    systemctl disable winduxedu-live-session-init.service >/dev/null 2>&1 || true
fi
rm -f /etc/systemd/system/winduxedu-live-session-init.service \
      /etc/systemd/system/multi-user.target.wants/winduxedu-live-session-init.service \
      /usr/local/sbin/winduxedu-live-session-init
rm -rf /etc/lightdm /etc/systemd/system/lightdm.service.d
rm -f /etc/xdg/autostart/winduxedu-desktop-trust.desktop
# The Live account is created at boot and must never be selected should its
# passwd entry happen to be visible while Calamares runs. Clear the image's
# Live session file first, then require the account created by Calamares.
rm -f /etc/winduxedu/session-user
human_accounts=$(awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "nobody" && $1 != "user" && $1 != "live" {print $1}' /etc/passwd)
installed_account=$(printf '%s\n' "$human_accounts" | sed '/^$/d' | tail -n1)
if [ -z "$installed_account" ]; then
    echo 'WinduxEdu: Calamares did not create an installed session account' >&2
    exit 1
fi
install -Dm644 /dev/stdin /etc/winduxedu/session-user <<EOF
$installed_account
EOF

# The installer's "免密码登录" checkbox is applied by Calamares only as group
# membership: Config::groupsForThisUser() appends `autologinGroup` (autologin)
# solely when doAutoLogin() is set, and the displaymanager module then writes
# a config for a greeter WinduxEdu does not ship, so the choice would be lost
# and ElevenDE's own login gate would still ask for a password.  Turn the
# group back into the signal elevende-session reads.
rm -f /etc/winduxedu/autologin
if id -nG "$installed_account" 2>/dev/null | tr ' ' '\n' | grep -qx autologin; then
    install -Dm644 /dev/stdin /etc/winduxedu/autologin <<'EOF'
Installed account was created with password-free automatic login.
EOF
fi
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable winduxedu-installed-cleanup.service >/dev/null 2>&1 || true
    # Replace anything occupying the .wants path (a flattened regular file
    # from a Windows checkout is not a symlink and defeats enablement).
    rm -f /etc/systemd/system/graphical.target.wants/winduxedu-elevende-display.service
    systemctl enable winduxedu-elevende-display.service >/dev/null 2>&1 || true
fi

# Calamares executes this after the selected account exists.  Use the shared
# installed-only cleaner so the system menu, inherited skeleton Desktop and
# already-created user Desktop/XDG directories are handled as one operation.
if [ -x /usr/local/libexec/winduxedu-installed-cleanup ]; then
    /usr/local/libexec/winduxedu-installed-cleanup
else
    echo 'WinduxEdu: installed-only installer cleanup helper is missing' >&2
    exit 1
fi

# Keep one Widgets process: WinduxEdu supplies the system XDG autostart entry.
# Remove an upstream per-user copy which older media created after a settings
# save and which then duplicated edge strips on every subsequent login.
find /home /root /etc/skel -type f -path '*/.config/autostart/widget-panel.desktop' -delete 2>/dev/null || true

# Keep the WinduxEdu GRUB theme self-contained in the installed target. Copy
# both the theme and its relative desktop-image asset before running grub-mkconfig.
THEME_SRC=/usr/share/winduxedu/branding/theme.txt
[ -f "$THEME_SRC" ] || THEME_SRC=/boot/grub/themes/winduxedu/theme.txt
WALL_SRC=/usr/share/winduxedu/branding/winduxedu-aurora-wallpaper.png
[ -f "$WALL_SRC" ] || WALL_SRC=/boot/grub/themes/winduxedu/winduxedu-aurora-wallpaper.png
if [ -f "$THEME_SRC" ] && [ -f "$WALL_SRC" ]; then
    install -Dm644 "$THEME_SRC" /boot/grub/themes/winduxedu/theme.txt
    install -Dm644 "$WALL_SRC" /boot/grub/themes/winduxedu/winduxedu-aurora-wallpaper.png
    mkdir -p /etc/default/grub.d
    cat > /etc/default/grub.d/00-winduxedu.cfg <<'EOF'
GRUB_DISTRIBUTOR="WinduxEdu"
GRUB_THEME="/boot/grub/themes/winduxedu/theme.txt"
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=6
GRUB_DEFAULT=0
GRUB_DISABLE_OS_PROBER=false
EOF
else
    # Never leave a dangling GRUB_THEME which produces a boot-time error.
    rm -f /etc/default/grub.d/00-winduxedu.cfg
fi

# Use ElevenDE's own lock program for installed sessions.  xss-lock observes
# idle/DPMS state without requiring LightDM or a second locker implementation.
if command -v xss-lock >/dev/null 2>&1 && [ -x /usr/local/bin/elevende-lock ]; then
    install -Dm644 /dev/stdin /etc/xdg/autostart/winduxedu-lock.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=WinduxEdu Screen Lock
Name[zh_CN]=WinduxEdu 锁屏
Exec=sh -c 'xset s 600 600; xset +dpms; xset dpms 0 0 900; exec xss-lock --transfer-sleep-lock -- /usr/local/bin/elevende-lock --lock'
OnlyShowIn=ElevenDE;Openbox;
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
fi

# Ensure a display change is restored on the next login when saved by Settings.
install -Dm755 /dev/stdin /usr/local/bin/winduxedu-restore-display <<'EOF'
#!/bin/sh
set -eu
[ -n "${DISPLAY:-}" ] || exit 0
[ -f "$HOME/.config/winduxedu/display.conf" ] || exit 0
mode=$(sed -n '1p' "$HOME/.config/winduxedu/display.conf")
[ -n "$mode" ] || exit 0
output=$(xrandr 2>/dev/null | awk '/ connected/{print $1; exit}')
[ -n "$output" ] || exit 0
# The Shell handles root ConfigureNotify and polls root geometry itself.  Do
# not signal it after RandR: elevende-shell intentionally has no SIGUSR1
# handler, so the default signal action kills the desktop and leaves gray root.
xrandr --output "$output" --mode "$mode" >/dev/null 2>&1 || true
EOF
install -Dm644 /dev/stdin /etc/xdg/autostart/winduxedu-restore-display.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=WinduxEdu Display Restore
Exec=/usr/local/bin/winduxedu-restore-display
OnlyShowIn=ElevenDE;LXDE;Openbox;
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

# Preserve the password entered in Calamares and make the created human user
# eligible for sudo without changing or resetting its password.
if getent group sudo >/dev/null 2>&1; then
    if [ -n "$installed_account" ]; then
        usermod -aG sudo "$installed_account" >/dev/null 2>&1 || true
    fi
fi

# Refresh device state and initramfs so firmware already present in the target
# is discovered without requiring a second manual driver step.
command -v udevadm >/dev/null 2>&1 && udevadm trigger --action=add || true
command -v depmod >/dev/null 2>&1 && depmod -a || true
command -v update-initramfs >/dev/null 2>&1 && update-initramfs -u -k all || true

# Regenerate GRUB only after the target theme and defaults are present.
# Both tools come from grub2-common and the ISO validator asserts them too.
# This step used to be `command -v update-grub && update-grub || true`, which
# made a missing tool indistinguishable from success and left the installed
# system without /boot/grub/grub.cfg -- the reported UEFI install failure.
if [ ! -x /usr/sbin/update-grub ]; then
    echo 'WinduxEdu: /usr/sbin/update-grub is missing on the target' >&2
    exit 1
fi
if [ ! -x /usr/sbin/grub-install ]; then
    echo 'WinduxEdu: /usr/sbin/grub-install is missing on the target' >&2
    exit 1
fi
if [ ! -f /etc/default/grub ]; then
    echo 'WinduxEdu: /etc/default/grub is missing on the target' >&2
    exit 1
fi
update-grub
if [ ! -s /boot/grub/grub.cfg ]; then
    echo 'WinduxEdu: update-grub did not produce /boot/grub/grub.cfg' >&2
    exit 1
fi

# Perform one more hardware/firmware probe at first boot, when the installed
# kernel and target udev database are active. Optional firmware never blocks
# graphical login.
install -Dm644 /dev/stdin /etc/systemd/system/winduxedu-driver-probe.service <<'EOF'
[Unit]
Description=WinduxEdu hardware and firmware probe
After=local-fs.target systemd-udev-settle.service
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'udevadm trigger --action=add; depmod -a; update-initramfs -u -k all; if command -v fwupdmgr >/dev/null 2>&1; then fwupdmgr get-devices || true; fi'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable winduxedu-driver-probe.service >/dev/null 2>&1 || true
fi
