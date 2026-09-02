# Quickshell bar

A Quickshell 0.3 bar for Hyprland using Catppuccin Mocha colors and
CaskaydiaCove Nerd Font. Hyprland starts it through `quickshell-bar`.

## Run

The normal top-edge bar reserves 32 px:

```sh
quickshell-bar
```

Stop the managed instance with:

```sh
quickshell-bar stop
```

The launcher prefers `qs`, falls back to `quickshell`, and resolves the config
from `$QUICKSHELL_BAR_CONFIG`, `~/.config/quickshell`, then this checkout. Run
`quickshell-bar help` for launcher details; arguments after the command or `--`
are forwarded to Quickshell.

## Non-exclusive preview

```sh
quickshell-bar test
```

Test mode puts the bar on the bottom edge with `ExclusionMode.Ignore`. It does
not reserve screen space and may overlap windows. Bar actions still affect the
live system.

## Launcher

The same Quickshell process provides a focused-monitor launcher:

- `Super+Space` opens application search.
- Start a query with `=` or choose **Calc** to evaluate with `qalc`; Enter copies the result.
- `Super+Shift+C`, `$`, or **Clipboard** searches clipboard history; Enter copies the selected item.
- Tab and Shift+Tab change modes. Up/Down select, Enter activates, and Escape closes.

Applications come from Quickshell's desktop-entry index. Elephant remains only
as the private clipboard-history backend; clipboard content is bounded in
memory and is never logged or persisted by Quickshell.

For debugging, the zero-argument IPC calls avoid command-line parser differences:

```sh
qs -p "$HOME/.config/quickshell" ipc call launcher showApps
qs -p "$HOME/.config/quickshell" ipc call launcher showCalc
qs -p "$HOME/.config/quickshell" ipc call launcher showClipboard
qs -p "$HOME/.config/quickshell" ipc call launcher hide
```

## Power and session menu

`Super+Ctrl+Escape` opens a compact menu on the focused monitor. Lock, suspend,
and hibernate run when selected. Log out, restart, and shut down first show an
inline confirmation with **Cancel** selected by default. Use arrows or Tab to
select, Enter or Space to activate, and Escape to go back or close the menu.
Clicking the dimmed background also closes it. `Super+Escape` still locks
immediately. Both `Super+Ctrl+Escape` and `Super+Shift+Escape` open the menu so
there is no unconfirmed logout shortcut.

The `powerMenu` IPC target provides only visibility, selection, and display
controls; it cannot execute or confirm an action.

## Bluetooth panel

`Super+B` or the bar's Bluetooth icon opens the native panel. Bar clicks target
that bar's monitor; the shortcut targets the focused monitor. Use Up/Down or Tab
to select the adapter, scan control, and devices; Enter or Space activates, `F`
requests forgetting a paired device, and Escape goes back or closes the panel.

Scanning is explicit and stops after 30 seconds. Closing the panel stops only a
scan started by this panel. Pairing uses Quickshell's native BlueZ API and does
not provide a passkey/PIN agent; devices requiring one need an external BlueZ
agent.

## Wi-Fi panel

`Super+N` or the bar's network-status icon opens the Wi-Fi panel. Bar clicks
target that bar's monitor; the shortcut targets the focused monitor. Use
Up/Down or Tab to select, Enter or Space to activate, `A` to toggle a saved
network's autoconnect setting, `F` to request forgetting it, and Escape to go
back or close.

Scanning is always explicit: select **Scan** to refresh the list. The panel uses
iwd for Wi-Fi and is intended for systems using iwd with systemd-networkd; it
does not invoke NetworkManager or `iwctl`. Unknown PSK credentials are held only
in the password field, passed once over the private JSON-line bridge, and
cleared on cancel, submit, or panel close. Enterprise (802.1X), WEP, unknown
security types, and passkey/enterprise credential flows are not supported.
Closing the panel does not cancel an in-progress connection; its visible Cancel
control does.

## Tailscale panel

Left-click the bar's Tailscale mark to open the full panel on that bar's
monitor. Right-click toggles Tailscale directly. The panel can connect or
disconnect, open an explicit browser login, switch profiles, browse online
peers, copy peer addresses or names, send files with Taildrop, and select or
clear tailnet and Mullvad exit nodes. Operator authorization uses Polkit only
when Tailscale denies profile access.

Use `J`/`K` or Up/Down to select and Enter or Space to activate. `T` toggles,
`R` refreshes, `X` opens exit nodes, and Escape goes back or closes. Peer detail
also supports `C` for address, `N` for name, `D` for DNS name, and `S` for
Taildrop. File selection uses the desktop portal-backed Qt file dialog.

Status, profile, peer, and exit-node data is bounded and sanitized before it is
shown. Commands use literal argument arrays, raw command errors are never shown
or logged, browser login links open only after an explicit action, and the IPC
target exposes no tailnet data. The implementation is adapted from Omarchy's
MIT-licensed Tailscale widget; exact source and license details are under
`assets/tailscale/`.

## Notifications and OSD

Notifications are compact, ephemeral top-right toasts. Expired or dismissed
notifications are destroyed; there is no history or notification tray. A **Copy
code** action appears when a nearby MFA-related phrase and 4–8 character code
are detected; copying does not dismiss the notification.

- `Super+,` dismisses the latest toast.
- `Super+Shift+,` dismisses every toast.
- `Super+Ctrl+,` toggles do not disturb. Notifications received while DND is on are dropped.
- Volume, mute, microphone, brightness, power-profile, and DND changes use the shared bottom-center OSD.

The power profile switches to **balanced** when AC power is connected and to
**power saver** when it is disconnected. This happens only when the power source
changes (and once when the bar starts), so selecting another profile from the
bar remains effective until the next plug or unplug event.

## Runtime data

Provider, SSID, device, tailnet, and account data stays out of the repository. AI
provider records use mode `0600` under
`$XDG_STATE_HOME/quickshell/agents/usage`, and scanner caches use
`$XDG_CACHE_HOME/quickshell/agent-usage`, with the usual home-directory
fallbacks. Credentials come from each provider's existing login and are never
written into this repository.

The AI dashboard runs `ai-usage update` every 15 minutes and keeps the last
valid Claude, Codex, and Fireworks record if one collector fails. It includes
subscription limits and resets, seven-day/model token charts, prepaid balance,
and local usage from native CLIs, Pi/OMP, and OpenCode. Left-click opens the
dashboard, middle-click changes provider, and right-click launches Pi. Refresh
inside the panel forces a rescan.

Optional runtime configuration is environment-only:

```sh
AI_USAGE_PROVIDERS=claude,codex
AI_USAGE_AGENT_COMMAND='["ghostty","-e","pi"]'
AI_USAGE_SYNC_DIR="$HOME/Sync/ai-usage"
AI_USAGE_SYNC_DEVICE_ID=laptop
AI_USAGE_SYNC_FILE_NAME=laptop.json
```

Omit `AI_USAGE_SYNC_DIR` to keep cross-device aggregation off. Fireworks can
read its existing `FIREWORKS_API_KEY`, `firectl`, or OpenCode login and optional
funding metadata from `~/.config/quickshell-agent-usage/fireworks.json`.
Provider collectors and assets are adapted from Omarchy Quattro under MIT;
exact source commits and license text are recorded beside the vendored files.

## Checks

```sh
quickshell-bar self-test
QUICKSHELL_BAR_CONFIG="$HOME/.config/quickshell" quickshell-bar test
QT_LOGGING_RULES='quickshell.*=true' quickshell-bar test
qmllint -I dot-config/quickshell $(find dot-config/quickshell -name '*.qml')
```

For `qmlls`, an empty local `.qmlls.ini` can be useful. Do not commit generated
versions containing machine-specific build or import paths.

## Upstream API references

- [Quickshell guide](https://quickshell.org/docs/v0.3.0/guide/)
- [Quickshell 0.3 type reference](https://quickshell.org/docs/v0.3.0/types/)
- [PanelWindow](https://quickshell.org/docs/v0.3.0/types/Quickshell/PanelWindow/)
- [Process](https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/Process/)
- [SplitParser](https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/SplitParser/)
- [PipeWire](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Pipewire/Pipewire/)
- [UPower and power profiles](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.UPower/)
- [Hyprland integration](https://quickshell.org/docs/v0.3.0/types/Quickshell.Hyprland/Hyprland/)
