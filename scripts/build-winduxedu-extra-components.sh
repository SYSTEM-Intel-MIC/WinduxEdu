#!/usr/bin/env bash
# Build audited WinduxEdu 1.0 optional Windows-style components.
# This script never executes upstream install.sh files.  It runs only explicit
# source builds and stages independent Debian packages into the shared PKGS dir.
set -euo pipefail

ROOT="${ROOT:-/workspace}"
OUT="${OUT:-$ROOT/artifacts}"
PKGS="${PKGS:-$OUT/packages}"
WORK="${WORK:-$OUT/work}"
SOURCE_CACHE="${WINDUXEDU_SOURCE_CACHE:-$OUT/source-cache}"
SOURCE_LOCK="$ROOT/packages/sources.lock.tsv"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

source_locked() {
    local id="$1" dst="$2" row url rev license role cache
    row="$(awk -F '\t' -v id="$id" '$1 == id { print; exit }' "$SOURCE_LOCK")"
    [ -n "$row" ] || die "source lock has no entry for $id"
    IFS=$'\t' read -r _ url rev license role <<<"$row"
    cache="$SOURCE_CACHE/${id}-${rev}"
    if [ ! -d "$cache/.git" ]; then
        rm -rf "$cache"
        mkdir -p "$(dirname "$cache")"
        git clone --filter=blob:none "$url" "$cache"
    fi
    # The restored cache belongs to the GitHub runner UID, while this recipe
    # deliberately runs as root in its isolated container.
    git config --global --add safe.directory "$cache"
    if ! git -C "$cache" cat-file -e "${rev}^{commit}" 2>/dev/null; then
        git -C "$cache" fetch --filter=blob:none origin "$rev"
    fi
    git -C "$cache" checkout --detach "$rev" >/dev/null
    [ "$(git -C "$cache" rev-parse HEAD)" = "$rev" ] || die "unexpected revision for $id"
    rm -rf "$dst"
    mkdir -p "$dst"
    git -C "$cache" archive "$rev" | tar -x -C "$dst"
}

make_deb() {
    local name="$1" version="$2" depends="$3" stage="$4" description="$5"
    mkdir -p "$stage/DEBIAN"
    cat > "$stage/DEBIAN/control" <<CONTROL
Package: $name
Version: $version
Architecture: amd64
Maintainer: SYSTEM-Intel-MIC <opensource@system-intel-mic.invalid>
Depends: $depends
Section: utils
Priority: optional
Description: $description
 WinduxEdu 1.0 bundled component built from a fixed upstream source revision.
CONTROL
    dpkg-deb --build --root-owner-group "$stage" "$PKGS/${name}_${version}_amd64.deb" >/dev/null
}

install_license() {
    local source="$1" stage="$2" package="$3"
    local license
    for license in LICENSE LICENSE.md License COPYING; do
        if [ -f "$source/$license" ]; then
            install -Dm644 "$source/$license" "$stage/usr/share/doc/$package/copyright"
            return 0
        fi
    done
    die "license file missing for $package"
}

install_desktop() {
    local stage="$1" file="$2" name="$3" exec="$4" icon="$5" categories="$6"
    install -Dm644 /dev/stdin "$stage/usr/share/applications/$file" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$name
Name[zh_CN]=$name
Comment=WinduxEdu 1.0 Windows-style system component
Exec=$exec
Icon=$icon
Terminal=false
Categories=$categories
DESKTOP
}

[ "$(id -u)" = 0 ] || die "this build must run as root inside the component build container"
command -v cargo >/dev/null 2>&1 || die "a modern Rust/Cargo toolchain is required (use rust:1.95-bookworm)"
command -v rustc >/dev/null 2>&1 || die "a modern Rust toolchain is required (use rust:1.95-bookworm)"
[ -f "$SOURCE_LOCK" ] || die "package source lock is missing: $SOURCE_LOCK"
mkdir -p "$PKGS" "$WORK" "$SOURCE_CACHE"
export DEBIAN_FRONTEND=noninteractive

log "installing extra-component build dependencies"
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl git build-essential cmake pkg-config gawk dpkg-dev \
    python3 python3-gi gir1.2-gtk-3.0 python3-tk \
    python3-pyqt5 python3-requests python3-pil python3-psutil python3-croniter \
    libpango1.0-dev \
    libpam0g-dev libgtk-4-dev libx11-dev libxi-dev libdrm-dev libfreetype-dev \
    libfontconfig1-dev libsystemd-dev libxcb-cursor0 libxcb-xinerama0

log "packaging WinduxEdu Troubleshooting through PyQt5 compatibility binding"
SRC="$WORK/winduxedu-troubleshooting"; source_locked winduxedu-troubleshooting "$SRC"
STAGE="$WORK/pkg-winduxedu-troubleshooting"
install -Dm644 "$SRC/main.py" "$STAGE/usr/lib/winduxedu-troubleshooting/main.py"
sed -i 's/from PySide6\.QtCore import QThread, Signal/from PyQt5.QtCore import QThread, pyqtSignal as Signal/; s/from PySide6\.QtWidgets import (/from PyQt5.QtWidgets import (/' "$STAGE/usr/lib/winduxedu-troubleshooting/main.py"
install -Dm755 /dev/stdin "$STAGE/usr/bin/winduxedu-troubleshooting" <<'SH'
#!/bin/sh
exec python3 /usr/lib/winduxedu-troubleshooting/main.py "$@"
SH
install_desktop "$STAGE" "winduxedu-troubleshooting.desktop" "Troubleshooting" "winduxedu-troubleshooting" "dialog-information" "System;Settings;"
install_license "$SRC" "$STAGE" "winduxedu-troubleshooting"
make_deb "winduxedu-troubleshooting" "1.0.0+winduxedu2" "python3, python3-pyqt5" "$STAGE" "WinduxEdu Windows-style troubleshooting helper"

log "packaging WinduxEdu Sticky Keys"
SRC="$WORK/linux-sticky-keys"; source_locked linux-sticky-keys "$SRC"
STAGE="$WORK/pkg-winduxedu-sticky-keys"
install -Dm644 "$SRC/Linux-Sticky-keys.py" "$STAGE/usr/lib/winduxedu-sticky-keys/upstream-main.py"
# Do not make a desktop tool grab /dev/input as root.  Use the X keyboard
# extension through setxkbmap so the preference is per-session and reversible.
install -Dm755 /dev/stdin "$STAGE/usr/lib/winduxedu-sticky-keys/main.py" <<'PY'
#!/usr/bin/env python3
import subprocess, tkinter as tk
root = tk.Tk(); root.title("粘滞键"); root.geometry("560x310"); root.configure(bg="#ffffff")
state = tk.BooleanVar(value=False)
def apply():
    subprocess.run(["setxkbmap", "-option", "stickykeys" if state.get() else ""], check=False)
    hint.config(text="已启用" if state.get() else "已关闭")
tk.Label(root, text="粘滞键", font=("Sans", 24, "bold"), bg="#ffffff", fg="#202020").pack(anchor="w", padx=34, pady=(30, 8))
tk.Label(root, text="让 Ctrl、Alt、Shift 和 Super 可逐次按下组合使用。", font=("Sans", 13), bg="#ffffff", fg="#505050").pack(anchor="w", padx=34)
tk.Checkbutton(root, text="启用粘滞键", variable=state, command=apply, font=("Sans", 15), bg="#ffffff", activebackground="#ffffff").pack(anchor="w", padx=34, pady=28)
hint=tk.Label(root, text="已关闭", font=("Sans", 12), bg="#ffffff", fg="#666666"); hint.pack(anchor="w", padx=34)
tk.Button(root, text="关闭", command=root.destroy, bg="#0f6cbd", fg="white", relief="flat", padx=22, pady=7).pack(anchor="e", padx=34, pady=24)
root.mainloop()
PY
install -Dm755 /dev/stdin "$STAGE/usr/bin/winduxedu-sticky-keys" <<'SH'
#!/bin/sh
exec python3 /usr/lib/winduxedu-sticky-keys/main.py "$@"
SH
install_desktop "$STAGE" "winduxedu-sticky-keys.desktop" "Sticky Keys" "preferences-desktop-accessibility" "preferences-desktop-accessibility" "Settings;Accessibility;"
install_license "$SRC" "$STAGE" "winduxedu-sticky-keys"
make_deb "winduxedu-sticky-keys" "1.0.1+winduxedu3" "python3, python3-tk, x11-xkb-utils" "$STAGE" "WinduxEdu Sticky Keys accessibility preferences"

log "packaging Widgets"
SRC="$WORK/windows-widgets"; source_locked windows-widgets "$SRC"
python3 "$ROOT/scripts/patch-winduxedu-component-sources.py" widgets "$SRC"
STAGE="$WORK/pkg-winduxedu-widgets"
install -d "$STAGE/usr/lib/winduxedu-widgets"
cp -a "$SRC/widget_panel" "$STAGE/usr/lib/winduxedu-widgets/"
install -Dm755 /dev/stdin "$STAGE/usr/bin/winduxedu-widgets" <<'SH'
#!/bin/sh
export PYTHONPATH=/usr/lib/winduxedu-widgets${PYTHONPATH:+:$PYTHONPATH}
exec python3 -m widget_panel.main "$@"
SH
install_desktop "$STAGE" "winduxedu-widgets.desktop" "Widgets" "winduxedu-widgets" "preferences-desktop-widget" "Utility;"
install_license "$SRC" "$STAGE" "winduxedu-widgets"
make_deb "winduxedu-widgets" "1.0.0+winduxedu2" "python3, python3-pyqt5, python3-requests, python3-pil" "$STAGE" "Windows-style desktop widgets for WinduxEdu"

if [ "${WINDUXEDU_SKIP_RUST_COMPONENTS:-0}" != "1" ]; then
log "building namespaced WinduxEdu command compatibility tools"
SRC="$WORK/windowshit"; source_locked windowshit "$SRC"
cargo build --manifest-path "$SRC/Cargo.toml" --release --locked
STAGE="$WORK/pkg-winduxedu-windowshit"
install -d "$STAGE/usr/lib/winduxedu-windowshit/bin" "$STAGE/usr/bin"
for bin in ipconfig ping tracert pathping whoami hostname ver where tree findstr getmac type sort more clip tasklist taskkill systeminfo fc choice replace expand makecab shutdown robocopy; do
    if [ -x "$SRC/target/release/$bin" ]; then
        install -m755 "$SRC/target/release/$bin" "$STAGE/usr/lib/winduxedu-windowshit/bin/$bin"
        ln -s "../lib/winduxedu-windowshit/bin/$bin" "$STAGE/usr/bin/winduxedu-$bin"
    fi
done
install -Dm755 /dev/stdin "$STAGE/usr/bin/winduxedu-windowshit" <<'SH'
#!/bin/sh
printf '%s\n' 'WinduxEdu 命令兼容工具使用 winduxedu-ipconfig、winduxedu-tasklist、winduxedu-systeminfo 等命名空间。'
SH
install_desktop "$STAGE" "winduxedu-windowshit.desktop" "WinduxEdu Commands" "WinduxEdu 命令" "utilities-terminal" "System;Utility;"
install_license "$SRC" "$STAGE" "winduxedu-windowshit"
make_deb "winduxedu-windowshit" "0.1.1+winduxedu2" "libc6" "$STAGE" "Namespaced WinduxEdu command compatibility tools"
fi

log "packaging WinSAT"
SRC="$WORK/winsat"; source_locked winsat "$SRC"
# Brand user-visible assessment strings as WinduxEdu without changing the
# upstream Windows-platform detection that protects its *nix execution path.
python3 - "$SRC/src/pywinsat/ui/locales.py" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
replacements = {
    "Windows 体验指数": "WinduxEdu 体验指数",
    "Windows Experience Index": "WinduxEdu Experience Index",
    "正在准备 Windows，请不要关闭计算机。": "正在准备 WinduxEdu，请不要关闭计算机。",
    "Preparing Windows, please do not turn off your computer.": "Preparing WinduxEdu, please do not turn off your computer.",
    "Windows 体验指数按 1.0 至 9.9 的等级评估关键系统组件": "WinduxEdu 体验指数按 1.0 至 9.9 的等级评估关键系统组件",
    "The Windows Experience Index assesses key system components on a scale of 1.0 to 9.9": "The WinduxEdu Experience Index assesses key system components on a scale of 1.0 to 9.9",
}
for old, new in replacements.items():
    s = s.replace(old, new)
p.write_text(s, encoding="utf-8")
PY
STAGE="$WORK/pkg-winduxedu-winsat"
install -d "$STAGE/usr/lib/winduxedu-winsat"
cp -a "$SRC/src/pywinsat" "$STAGE/usr/lib/winduxedu-winsat/"
install -Dm755 /dev/stdin "$STAGE/usr/bin/winsat" <<'SH'
#!/bin/sh
export PYTHONPATH=/usr/lib/winduxedu-winsat${PYTHONPATH:+:$PYTHONPATH}
# Desktop launch has no arguments: open the upstream graphical WEI view.
# Explicit CLI arguments remain available for terminal users.
if [ "$#" -eq 0 ]; then
    exec python3 -m pywinsat gui --lang zh
fi
exec python3 -m pywinsat "$@"
SH
install_desktop "$STAGE" "winduxedu-winsat.desktop" "WinduxEdu Experience Index" "WinduxEdu 体验指数" "applications-system" "System;Utility;"
install_license "$SRC" "$STAGE" "winduxedu-winsat"
make_deb "winduxedu-winsat" "1.0.1+winduxedu3" "python3, python3-tk" "$STAGE" "WinduxEdu experience-index style benchmark tool"

log "building About WinduxEdu (winver)"
SRC="$WORK/linux-winver"; source_locked linux-winver "$SRC"
make -C "$SRC"
STAGE="$WORK/pkg-winduxedu-winver"
install -Dm755 "$SRC/winver" "$STAGE/usr/lib/winduxedu-winver/winver"
install -Dm755 /dev/stdin "$STAGE/usr/bin/winver" <<'SH'
#!/bin/sh
exec /usr/lib/winduxedu-winver/winver "$@"
SH
install_desktop "$STAGE" "winduxedu-winver.desktop" "About WinduxEdu" "winver" "help-about" "System;Settings;"
install_license "$SRC" "$STAGE" "winduxedu-winver"
make_deb "winduxedu-winver" "1.0.0+winduxedu2" "libc6, libgtk-4-1" "$STAGE" "WinduxEdu version information"

install -Dm644 "$SOURCE_LOCK" "$PKGS/WINDUXEDU-1.0-COMPONENTS.txt"
log "built WinduxEdu 1.0 extra component packages"
