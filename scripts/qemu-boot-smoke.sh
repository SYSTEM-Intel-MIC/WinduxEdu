#!/bin/bash
# Bounded BIOS/UEFI boot smoke for the finished WinduxEdu ISO.  A menu that
# merely renders is insufficient: send Return to select the default Live item,
# then retain a final graphical frame and fail on QEMU-level diagnostics.
set -euo pipefail

usage() {
    echo "usage: $0 ISO_PATH bios|uefi [seconds]" >&2
    exit 2
}

[ "$#" -ge 2 ] || usage
ISO="$1"
MODE="$2"
SECONDS="${3:-420}"
RENDER_WAIT="${WINDUXEDU_QEMU_RENDER_WAIT:-340}"
# First frame, captured well before the final one.  Comparing the two is what
# separates "the desktop never rendered" from "it rendered and then lost the
# framebuffer", and a slow first boot must not be mistaken for the former.
EARLY_WAIT="${WINDUXEDU_QEMU_EARLY_WAIT:-60}"
MONITOR_WAIT=20
BOOT_MENU_WAIT=8
CAPTURE_GRACE=10
MIN_RUNTIME=$((MONITOR_WAIT + BOOT_MENU_WAIT + RENDER_WAIT + CAPTURE_GRACE))
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
VISUAL_VALIDATOR="$SCRIPT_DIR/validate-qemu-visual-frame.py"
[ -s "$ISO" ] || { echo "ISO is missing or empty: $ISO" >&2; exit 1; }
case "$MODE" in bios|uefi) ;; *) usage ;; esac
if [ "$SECONDS" -lt "$MIN_RUNTIME" ]; then
    echo "QEMU timeout ${SECONDS}s is shorter than the required ${MIN_RUNTIME}s startup/capture budget" >&2
    exit 2
fi
if [ "$EARLY_WAIT" -le 0 ] || [ "$EARLY_WAIT" -ge "$RENDER_WAIT" ]; then
    echo "WINDUXEDU_QEMU_EARLY_WAIT must fall strictly between 0 and RENDER_WAIT (${RENDER_WAIT}s)" >&2
    exit 2
fi
for command in qemu-system-x86_64 timeout socat python3; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "required command is unavailable: $command" >&2
        exit 1
    }
done

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
MONITOR="$WORK/monitor.sock"
FRAME="${WINDUXEDU_QEMU_SMOKE_FRAME:-${ISO}.${MODE}.ppm}"
EARLY_FRAME="${ISO}.${MODE}.early.ppm"
LOG="$WORK/qemu.log"
rm -f "$FRAME" "$EARLY_FRAME"

# virtio-vga is the supported automated graphics test adapter. Standard VGA
# is retained as a documented compatibility follow-up rather than being used
# to infer whether the ElevenDE session has visibly rendered.  Prefer KVM when
# the runner exposes /dev/kvm (GitHub-hosted Linux runners do) and fall back
# to TCG in ordered -accel chain form; TCG needs several minutes to reach a
# rendered session, while KVM boots the live desktop in well under a minute.
QEMU=(qemu-system-x86_64 -m 2048 -smp 2 -accel kvm -accel tcg -no-reboot -no-shutdown \
      -vga virtio -display none -monitor "unix:${MONITOR},server=on,wait=off" \
      -serial "file:${WORK}/serial.log" \
      -cdrom "$ISO" -boot d)
if [ "$MODE" = uefi ]; then
    if [ -n "${OVMF_CODE:-}" ]; then
        OVMF_IMAGE="$OVMF_CODE"
    elif [ -s /usr/share/OVMF/OVMF_CODE.fd ]; then
        OVMF_IMAGE=/usr/share/OVMF/OVMF_CODE.fd
    else
        OVMF_IMAGE=/usr/share/ovmf/OVMF.fd
    fi
    [ -s "$OVMF_IMAGE" ] || { echo "OVMF firmware not found: $OVMF_IMAGE" >&2; exit 1; }
    QEMU+=(-machine q35 -bios "$OVMF_IMAGE")
fi

set +e
timeout --foreground "${SECONDS}s" "${QEMU[@]}" 2>"$LOG" &
TIMEOUT_PID=$!
set -e

# Give firmware/ISOLINUX a bounded opportunity to render, then confirm the
# default Live entry.  This avoids treating a static boot menu as a success.
for _ in $(seq 1 "$MONITOR_WAIT"); do
    [ -S "$MONITOR" ] && break
    sleep 1
done
[ -S "$MONITOR" ] || {
    cat "$LOG" >&2 || true
    echo "QEMU $MODE did not expose a monitor socket" >&2
    exit 1
}
sleep "$BOOT_MENU_WAIT"
printf 'sendkey ret\n' | socat - UNIX-CONNECT:"$MONITOR" >/dev/null 2>&1 || {
    cat "$LOG" >&2 || true
    echo "QEMU $MODE could not select the default Live entry" >&2
    exit 1
}
# Preserve a frame only after the bounded Live/Xorg/session startup window.
# Under TCG the native C/Xlib shell may still be drawing after Xorg itself has
# exposed a gray root window. Keep this window long enough to distinguish that
# intermediate state from a usable rendered ElevenDE desktop.
sleep "$EARLY_WAIT"
printf 'screendump %s\n' "$EARLY_FRAME" | socat - UNIX-CONNECT:"$MONITOR" >/dev/null 2>&1 || true
sleep $((RENDER_WAIT - EARLY_WAIT))
printf 'screendump %s\n' "$FRAME" | socat - UNIX-CONNECT:"$MONITOR" >/dev/null 2>&1 || true

set +e
wait "$TIMEOUT_PID"
rc=$?
set -e
cat "$LOG"
# The guest serial console is the only place early-boot failures (initramfs,
# live-boot media probes, systemd unit errors) and the smoke-diagnostics dump
# become visible, so always print its tail next to the visual verdict. 600
# lines leaves room for the second diagnostics block emitted shortly before
# the final capture.
if [ -s "$WORK/serial.log" ]; then
    echo "--- guest serial console (last 600 lines) ---"
    tail -n 600 "$WORK/serial.log"
    echo "--- end guest serial console ---"
fi
# The early frame is diagnostic context only: it reports whether the desktop
# was already up at EARLY_WAIT, but never decides the verdict. A black early
# frame followed by a rendered final frame is a slow boot; the reverse means
# the session painted and then lost the framebuffer.
if [ -s "$EARLY_FRAME" ]; then
    echo "--- early frame (${EARLY_WAIT}s after boot selection) ---"
    python3 "$VISUAL_VALIDATOR" "$EARLY_FRAME" 2>&1 \
        || echo "early frame is not a rendered desktop yet (informational only)" >&2
    echo "--- end early frame ---"
else
    echo "no early frame was captured (informational only)" >&2
fi
[ -s "$FRAME" ] || {
    echo "QEMU $MODE did not produce a post-selection graphical frame" >&2
    exit 1
}
echo "--- final frame (${RENDER_WAIT}s after boot selection) ---"
python3 "$VISUAL_VALIDATOR" "$FRAME"
echo "--- end final frame ---"
# Timeout means the guest remained alive past the bounded post-selection boot
# interval; immediate exits or host-visible firmware errors fail the job.
if [ "$rc" -ne 124 ]; then
    echo "QEMU $MODE boot smoke failed with exit status $rc" >&2
    exit 1
fi
if grep -qiE 'could not open|failed to load|no bootable device|fatal' "$LOG"; then
    echo "QEMU $MODE emitted a boot failure diagnostic" >&2
    exit 1
fi
echo "QEMU $MODE boot smoke passed after ${SECONDS}s (frame: $FRAME)"
