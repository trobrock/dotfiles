-- https://wiki.hypr.land/Configuring/Basics/Autostart/

local terminal = "uwsm app -- ghostty"

hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm app -- hyprpaper")
    hl.exec_cmd("uwsm app -- quickshell-bar")
    hl.exec_cmd("systemctl --user start hypridle.service")
    hl.exec_cmd("systemctl --user start elephant.service")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("systemctl --user start hyprvoice.service")

    hl.exec_cmd("uswm app -- slack", { workspace = "3 silent" })
    hl.exec_cmd(terminal, { workspace = "2 silent" })
end)
