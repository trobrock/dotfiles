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

## Runtime data

Provider, SSID, device, and account data stays out of the repository. AI
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
- [System tray](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.SystemTray/SystemTray/)
- [Hyprland integration](https://quickshell.org/docs/v0.3.0/types/Quickshell.Hyprland/Hyprland/)
