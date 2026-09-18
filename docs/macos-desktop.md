# macOS desktop: Hyprland parity

The Linux machine runs Arch + Hyprland with a custom Quickshell bar
(`dot-config/quickshell`). This documents the macOS stand-in and, more
importantly, where it cannot match.

| Concern | Linux | macOS |
| --- | --- | --- |
| Compositor / WM | Hyprland | AeroSpace (`dot-config/aerospace/aerospace.toml`) |
| Bar | Quickshell (`dot-config/quickshell`) | sketchybar (`dot-config/sketchybar`) |
| Window borders | Hyprland `general.col.*` | `borders`, launched by AeroSpace |
| Launcher | Quickshell launcher | Raycast |
| Notifications | Quickshell toasts | native macOS Notification Center |
| Volume / brightness OSD | Quickshell OSD | native macOS HUD |
| Screenshots | `hyprshot` | native `cmd+shift+3/4/5` |

## Why Option is SUPER

On a PC keyboard the bottom row is Ctrl-Super-Alt; on a Mac keyboard it is
Ctrl-Option-Command. **Option therefore sits in the same physical position as
the Hyprland SUPER key**, which keeps muscle memory intact. It also avoids
fighting macOS, which reserves a large number of cmd combinations
(`cmd+Q`/`W`/`H`/`Space`, `cmd+1..9` for browser tabs).

## Keybinds

`alt` below is Option. Source of truth is
`dot-config/hypr/hyprland/binds.conf` on the Linux side.

| Action | Hyprland | AeroSpace |
| --- | --- | --- |
| Focus left/down/up/right | `SUPER h/j/k/l` | `alt-h/j/k/l` |
| Move window | `SUPER SHIFT h/j/k/l` | `alt-shift-h/j/k/l` |
| Switch workspace 1-9 | `SUPER 1..9` | `alt-1..9` |
| Send window to workspace | `SUPER SHIFT 1..9` | `alt-shift-1..9` |
| Close window | `SUPER W` | `alt-w` |
| Fullscreen | `SUPER F` | `alt-f` |
| Toggle floating | `SUPER V` | `alt-v` |
| Toggle split orientation | `SUPER P` | `alt-p` |
| Group / accordion | `SUPER G` | `alt-g` |
| Cycle within group | `SUPER CTRL h/l` | `alt-ctrl-h/l` |
| Terminal | `SUPER Q` | `alt-q` (Ghostty) |
| Browser | `SUPER Return` | `alt-enter` (Chrome) |
| File manager | `SUPER E` | `alt-e` (Finder) |
| btop / lazydocker | `SUPER T` / `SUPER D` | `alt-t` / `alt-d` |
| 1Password | `SUPER slash` | `alt-slash` |
| Bluetooth panel | `SUPER B` | `alt-b` |
| Wi-Fi panel | `SUPER N` | `alt-n` |
| Lock | `SUPER ESC` | `alt-esc` |
| Power menu | `SUPER SHIFT/CTRL ESC` | `alt-shift-esc` / `alt-ctrl-esc` |
| Scratchpad | `SUPER S` | `alt-s` (emulated) |
| Send to scratchpad | `SUPER SHIFT S` | `alt-shift-s` |
| Headphones | `SUPER SHIFT CTRL H` | `alt-ctrl-shift-h` |
| Resize | mouse only | `alt-minus` / `alt-equal` |
| Service mode | n/a | `alt-shift-semicolon` |

### Deliberate divergences

- **Launcher stays on `cmd+Space`.** Hyprland uses `SUPER+Space`, but Raycast's
  hotkey was intentionally left alone. Only `raycastGlobalHotkey` is
  reachable via `defaults` — it currently reads `Command-49`, where 49 is the
  Space keyCode. `defaults write com.raycast.macos raycastGlobalHotkey
  "Option-49"` followed by a Raycast restart is the likely equivalent, but the
  modifier spelling has **not** been verified; setting it in Raycast's settings
  UI is the safe route.
- **Clipboard history has no bind.** Hyprland uses `SUPER+SHIFT+C`. Raycast
  stores per-command hotkeys in its internal database, not in `defaults`, so
  this can only be set in Raycast's settings UI.
- **`alt-tab` is workspace back-and-forth**, not the `special:typingmind` deck,
  which is a Linux-only app workspace.
- **Screenshots** keep the native macOS bindings instead of emulating
  `hyprshot`. Hyprland's screen-recording binds (`SUPER SHIFT R/G/W`) have no
  equivalent here.
- **No notification binds.** `SUPER comma` and friends drive the Quickshell
  notification service, which has no macOS counterpart.

## Scratchpad emulation

AeroSpace has no special workspaces. `dot-local/bin/aerospace-scratchpad`
approximates `togglespecialworkspace`: it summons the named workspace onto the
focused monitor, or returns to the previous workspace if that one is already
focused. Unlike Hyprland it does **not** overlay the scratchpad on top of the
current workspace.

It is invoked as `/bin/zsh -c "aerospace-scratchpad ..."` because AeroSpace's
`exec-and-forget` runs without a shell and with a PATH that excludes
`~/.local/bin`:

```
PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin
```

Check it with `aerospace list-exec-env-vars`.

## Bar

`dot-config/sketchybar` mirrors the Quickshell design system.
`theme.sh` holds the Catppuccin Mocha tokens and is the file to keep in sync
with `dot-config/quickshell/Theme.qml`.

Layout, matching `Bar.qml`:

- **left** — workspaces, minimal style: colored label plus a 14x2 underline
  indicator, no pill. Workspaces 1-5 always show; 6-9 appear only when occupied.
- **center** — upcoming calendar event, hidden when there is none.
- **right** — `tailscale coffee bluetooth wifi mic battery | audio | clock`,
  icon-only and monochrome, taking on color only to signal a problem.

Flat groups mean modules have no background of their own; 1x14 surface1
dividers separate them, reproducing `components/BarDivider.qml`.

### sketchybar constraints worth knowing

- **Only `CONFIG_DIR` is exported to scripts.** `PLUGIN_DIR` and `SCRIPT_DIR`
  are plain shell variables in `sketchybarrc` and are empty inside plugins, so
  `theme.sh` re-derives them. Verify with `aerospace list-exec-env-vars`'
  equivalent: add a probe item that dumps its environment.
- **`background.padding_left/right` does not inset a background.** It is
  accepted silently and has no effect; the background always spans the item's
  content width. The 14px workspace indicator is produced by sizing the content
  (3px label padding) and pushing the gap outward with 5px item padding.
- **Use `center`, not `e`, to center an item.** Both are accepted, but `e`
  lands well right of center.
- **The bar border cannot be limited to one edge.** `border_width` draws around
  the whole bar; because the bar is flush with the top of the screen, only the
  bottom hairline reads as a visible line.
- **`--query <item>` never reports background state**, so indicator colors have
  to be verified visually rather than by querying.
- Scripts run under Homebrew bash 5 (`brew "bash"`), but plugins avoid
  `mapfile` so they stay runnable by hand under macOS's `/bin/bash` 3.2.

### Modules with no macOS equivalent

- **AI usage pill** — intentionally not ported to this machine.
- **Wi-Fi signal strength** — the Linux bar buckets RSSI into five glyphs, but
  macOS 26 exposes RSSI only to root (`wdutil info`); it is absent from both
  `ioreg` and `ipconfig`. The bar shows connected/disconnected only.
- **Headphone audio glyph** — the only reliable source is
  `system_profiler SPAudioDataType`, which takes about a second and is far too
  slow for a bar refresh.
- **Notification toasts, OSD, and the Quickshell launcher** — owned by macOS or
  Raycast.

Note that `networksetup -getairportnetwork` is unreliable on macOS 26: it
reports "You are not associated with an AirPort network" while Wi-Fi is up. The
Wi-Fi plugin reads `ipconfig getsummary` instead.

## Lock behavior

`alt-esc` runs `pmset displaysleepnow`, which only actually locks if the screen
lock delay is immediate. Set it under
**System Settings > Lock Screen > Require password after screen saver begins**
to *immediately*, otherwise the display sleeps unlocked.

## Manual steps after a fresh install

`bin/install` starts sketchybar and AeroSpace, but these need the GUI:

1. Grant **Accessibility** permission to AeroSpace (it cannot move windows
   without it).
2. Set the Lock Screen password delay to immediate (see above).
3. Optionally set the Raycast clipboard-history hotkey in Raycast settings.

## Known gaps

These are properties of macOS, not oversights:

- **No animations.** Hyprland's bezier window/workspace animations have no
  equivalent; AeroSpace switches instantly.
- **No per-window blur, opacity, or rounding.** `decoration { rounding, blur,
  shadow }` cannot be reproduced.
- **Different tiling model.** AeroSpace uses an i3-style tree; it will not
  auto-alternate splits the way Hyprland's `dwindle` does.
- AeroSpace warns that `config-version = 1` is outdated. Migrating to version 2
  changes command semantics and has not been done.
