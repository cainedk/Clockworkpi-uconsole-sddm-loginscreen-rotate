# uconsole-sddm-rotation-fix

Fixes the SDDM login screen showing up in the wrong orientation on the
ClockworkPi uConsole, when the KDE Plasma desktop itself is already rotated
correctly after login.

## Provenance

This script and its documentation were developed with the assistance of an
LLM (Claude, by Anthropic), during an interactive debugging session on real
uConsole hardware. Every step — the root-cause diagnosis, each config file
checked, and each fix — was verified against actual command output
(`journalctl`, `xrandr`, file contents) on the device before being folded
into the script below. It is not a generic/untested AI suggestion; it's a
record of what was actually confirmed to work on one specific board.

That said:
- It has only been tested on **one** uConsole (CM5, Debian trixie, KDE
  Plasma 6, SDDM), as of September 2026.
- Review the script before running it as root, especially if your setup
  differs (different image, different panel, non-KDE desktop, etc).
- Issues and PRs from people who've tried it on other configurations are
  very welcome — that's the best way to make this more broadly reliable.

## The problem

SDDM's login greeter runs as its own session, as the `sddm` system user,
before your desktop session starts. It does not inherit your KDE/KWin
display rotation. On Wayland, there's a known upstream bug where the
Wayland greeter reads `kwinoutputconfig.json` (even if copied to the
`sddm` user's home) but ignores the rotation field specifically.

## The fix

Force SDDM to use the X11 greeter just for the login screen (your actual
desktop session can stay on Wayland after you log in), and have it run
`xrandr --rotate` via SDDM's `Xsetup` hook, which only runs under the X11
greeter.

Concretely, this means three things need to be correct:

1. `/etc/sddm.conf.d/display.conf` sets `DisplayServer=x11`.
2. `/etc/sddm.conf.d/rotation.conf` sets `DisplayCommand` to
   `/usr/share/sddm/scripts/Xsetup` (some uConsole images instead point
   this at a dead `/usr/local/bin/sddm-rotate` script left over from
   first-boot wizard logic — it has no rotation code in it).
3. `/usr/share/sddm/scripts/Xsetup` contains a correct
   `xrandr --output <your-output> --rotate <direction>` line, with the
   right output name (don't assume `DSI-1` — check with `xrandr -q`).

## Usage

```bash
sudo ./fix-sddm-rotation.sh [rotate_direction]
```

`rotate_direction` is one of `normal`, `left`, `right`, `inverted`
(default: `right`).

The script auto-detects your connected display output, writes clean
versions of all three config pieces above, and restarts SDDM to apply the
change. It's safe to re-run.

## If it still doesn't work

```bash
sudo journalctl -u sddm -b --no-pager | tail -60
```

Look for a line like `Running display setup script
".../Xsetup"` to confirm it's being invoked at all, and check for any
`output DSI-x not found` warning, which means the output name is wrong for
your hardware.

## License

MIT (or add your preferred license here).
