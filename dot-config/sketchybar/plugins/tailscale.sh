#!/usr/bin/env bash
# Tailscale status + popup, standing in for TailscaleMenu.qml.
#
# StatusIsland.qml colors: running -> subtext (monochrome), needs login ->
# yellow, otherwise overlay. The Linux bar uses a vendored Tailscale SVG; a
# nerd-font VPN glyph stands in here.

set -uo pipefail

source "$CONFIG_DIR/theme.sh"

state() {
  tailscale status --json 2>/dev/null | jq -r '.BackendState // "Unknown"'
}

render_popup() {
  local backend=$1
  sketchybar --remove '/tailscale.popup\./' >/dev/null 2>&1

  local self exit_node
  self=$(tailscale status --json 2>/dev/null |
    jq -r '.Self.DNSName // "" | rtrimstr(".")')
  exit_node=$(tailscale status --json 2>/dev/null |
    jq -r '[.Peer[]? | select(.ExitNode == true) | .DNSName | rtrimstr(".")] | first // "none"')

  local commands=()
  commands+=(--add item tailscale.popup.header popup."$NAME"
             --set      tailscale.popup.header icon.drawing=off
                                               label="${self:-Tailscale} ($backend)"
                                               label.color="$TEXT"
                                               label.padding_left=10
                                               label.padding_right=10)

  commands+=(--add item tailscale.popup.exit popup."$NAME"
             --set      tailscale.popup.exit icon.drawing=off
                                             label="Exit node: $exit_node"
                                             label.color="$SUBTEXT"
                                             label.padding_left=10
                                             label.padding_right=10)

  local action label
  if [ "$backend" = "Running" ]; then
    action="tailscale down"
    label="Disconnect"
  else
    action="tailscale up"
    label="Connect"
  fi

  commands+=(--add item tailscale.popup.toggle popup."$NAME"
             --set      tailscale.popup.toggle icon.drawing=off
                                               label="$label"
                                               label.color="$SUBTEXT"
                                               label.padding_left=10
                                               label.padding_right=10
                                               click_script="$action; sketchybar --set $NAME popup.drawing=off")

  sketchybar "${commands[@]}"
}

backend=$(state)

case "${1:-}" in
  toggle_popup)
    render_popup "$backend"
    sketchybar --set "$NAME" popup.drawing=toggle
    exit 0
    ;;
esac

case "$backend" in
  Running)
    color=$SUBTEXT
    ;;
  NeedsLogin | NeedsMachineAuth)
    color=$YELLOW
    ;;
  *)
    color=$OVERLAY
    ;;
esac

sketchybar --set "$NAME" icon="$GLYPH_TAILSCALE" icon.color="$color"
