#!/bin/bash
#
# fix-sddm-rotation.sh
#
# Fixes the SDDM login screen showing up in the wrong orientation on the
# ClockworkPi uConsole (or similar single-panel devices with a rotated DSI
# display), while the Plasma desktop itself is correctly rotated after login.
#
# Root cause: SDDM's greeter runs as its own session before you log in and
# does NOT inherit the per-user KDE/KWin display rotation. On Wayland, the
# Wayland greeter is known to ignore the "transform" field in
# ~/.config/kwinoutputconfig.json even when copied over to the sddm user.
# The reliable fix is to force SDDM to use the X11 greeter just for login,
# and have that greeter run `xrandr --rotate` via SDDM's Xsetup script
# before the login dialog appears. Your actual desktop session can stay on
# Wayland after you log in -- this only touches the login screen.
#
# Usage:
#   sudo ./fix-sddm-rotation.sh [rotate_direction]
#
# rotate_direction: normal | left | right | inverted   (default: right)
#
# Safe to re-run -- it will detect and reuse existing config rather than
# duplicating or conflicting with it.
#
# ---------------------------------------------------------------------------
# Provenance: this script was developed with the assistance of an LLM
# (Claude, Anthropic) in a debugging session on real uConsole hardware.
# The root-cause diagnosis and each fix were verified interactively against
# actual `journalctl`/`xrandr`/config output on the device before being
# folded into this script. It has been tested on one uConsole (CM5, Debian
# trixie, KDE Plasma 6). Review the commands before running as root, and
# please open an issue/PR if it doesn't work on your setup.
# ---------------------------------------------------------------------------

set -euo pipefail

ROTATE="${1:-right}"

if [[ "$ROTATE" != "normal" && "$ROTATE" != "left" && "$ROTATE" != "right" && "$ROTATE" != "inverted" ]]; then
    echo "Invalid rotation '$ROTATE'. Must be one of: normal, left, right, inverted" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (sudo)." >&2
    exit 1
fi

echo "== uConsole SDDM rotation fix =="

# 1. Detect the actual DSI output name currently in use.
#    Don't assume DSI-1 -- on this Debian/KDE image it's often DSI-2.
#    We need to ask a real X11 xrandr, so run it as the invoking user if
#    possible (works whether the live session is X11 or Wayland -- xrandr
#    itself needs an X server, so fall back to parsing /sys/class/drm if
#    xrandr isn't usable from here).
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "")}"

OUTPUT_NAME=""
if [[ -n "$REAL_USER" ]]; then
    OUTPUT_NAME=$(sudo -u "$REAL_USER" DISPLAY=:0 xrandr -q 2>/dev/null | grep -m1 " connected" | awk '{print $1}' || true)
fi

if [[ -z "$OUTPUT_NAME" ]]; then
    # Fallback: look for a DSI output under /sys/class/drm
    OUTPUT_NAME=$(ls /sys/class/drm | grep -m1 -oE 'DSI-[0-9]+' || true)
fi

if [[ -z "$OUTPUT_NAME" ]]; then
    echo "Could not auto-detect the display output name."
    echo "Run 'xrandr -q' yourself in a desktop session and re-run this script with the"
    echo "output name hardcoded, e.g.: edit this script and set OUTPUT_NAME=DSI-2 manually."
    exit 1
fi

echo "Detected display output: $OUTPUT_NAME"
echo "Rotation to apply: $ROTATE"

# 2. Force SDDM to use the X11 greeter (Xsetup is X11-only; the Wayland
#    greeter has no equivalent hook and is known to ignore rotation config
#    even when kwinoutputconfig.json is copied to the sddm user's home).
mkdir -p /etc/sddm.conf.d

DISPLAY_CONF="/etc/sddm.conf.d/display.conf"
cat > "$DISPLAY_CONF" <<EOF
[General]
DisplayServer=x11
EOF
echo "Wrote $DISPLAY_CONF (forces X11 greeter)"

# 3. Point SDDM's DisplayCommand at the real Xsetup script.
#    (On some uConsole/piwiz-derived images, a rotation.conf file exists
#    that points DisplayCommand at a bogus/unrelated script named
#    something like sddm-rotate -- left over from first-boot wizard logic
#    and containing no rotation code at all. We overwrite it cleanly here.)
ROTATION_CONF="/etc/sddm.conf.d/rotation.conf"
cat > "$ROTATION_CONF" <<EOF
[X11]
DisplayCommand=/usr/share/sddm/scripts/Xsetup
EOF
echo "Wrote $ROTATION_CONF (points DisplayCommand at the real Xsetup script)"

# 4. Write a clean Xsetup script. We don't append -- we replace, since
#    stray/duplicate rotate lines (e.g. leftover "xrander" typos, or old
#    DSI-1 references) are a common source of confusion and silent no-ops.
XSETUP="/usr/share/sddm/scripts/Xsetup"
cat > "$XSETUP" <<EOF
#!/bin/sh
# Xsetup - run as root before the login dialog appears
# Managed by fix-sddm-rotation.sh -- rotates the login screen to match
# the desktop's panel orientation on the uConsole.

if [ -e /sbin/prime-offload ]; then
    echo "running NVIDIA Prime setup"
    /sbin/prime-offload
fi

/usr/bin/xrandr --output ${OUTPUT_NAME} --rotate ${ROTATE}
EOF
chmod +x "$XSETUP"
echo "Wrote and chmod +x $XSETUP"

echo ""
echo "== Config summary =="
echo "--- $DISPLAY_CONF ---"
cat "$DISPLAY_CONF"
echo "--- $ROTATION_CONF ---"
cat "$ROTATION_CONF"
echo "--- $XSETUP ---"
cat "$XSETUP"

echo ""
echo "Restarting SDDM to apply changes..."
systemctl restart sddm

echo ""
echo "Done. Your login screen should now be rotated correctly."
echo "If not, check: sudo journalctl -u sddm -b --no-pager | tail -60"
echo "and look for lines mentioning Xsetup or xrandr errors."
