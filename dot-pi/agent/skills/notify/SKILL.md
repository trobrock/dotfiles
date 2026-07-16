---
name: notify
description: Send mobile push notifications through ntfy, but only when the user explicitly asks to be notified. Do not notify merely because the user will be away or a command, build, test, monitor, or other task may take a long time.
---

# ntfy notifications

Send notifications using the scripts in this skill directory. Configuration is private and stored outside the dotfiles repository under `~/.config/pi-notify/`.

Only send or arrange a notification when the user explicitly requests one. Never infer that a notification is wanted from the task duration, the use of a monitor, or the user saying they will be away.

## Long-running commands

When the user explicitly requests a notification for a long-running command started with `monitor_command`, wrap the actual command so it sends its own completion notification:

```bash
~/.pi/agent/skills/notify/run-and-notify --title "Build" -- command arg1 arg2
```

Pass that complete invocation as `monitor_command`'s `command`. Use a concise title identifying the task. The wrapper preserves the wrapped command's exit status and sends success or failure plus elapsed time.

If shell syntax is required, explicitly invoke a shell:

```bash
~/.pi/agent/skills/notify/run-and-notify --title "Deploy" -- bash -lc 'command1 && command2'
```

Do not interpolate or include credentials in notification titles or messages. Avoid putting secret-bearing command arguments into shell command strings.

## Direct notifications

```bash
~/.pi/agent/skills/notify/notify --title "Pi" "Task completed"
~/.pi/agent/skills/notify/notify --title "Tests failed" --priority high --tags warning "3 test failures"
printf '%s\n' "Multiline message" | ~/.pi/agent/skills/notify/notify --title "Pi"
```

Priorities: `min`, `low`, `default`, `high`, `max`, or numeric `1` through `5`.

When the user explicitly requests a notification for a monitor that cannot be wrapped, such as `monitor_github_pr_checks`, call `notify` immediately when the monitor wakes. Wrapping is preferred because it can notify while Pi is idle.

## Configuration

If configuration is missing, run:

```bash
~/.pi/agent/skills/notify/setup
```

This creates an unguessable topic and stores it in `~/.config/pi-notify/topic`, with mode `0600`. It defaults to `https://ntfy.sh`. The topic is a secret and must never be committed or printed in normal responses.

Configuration can instead be supplied through `NTFY_SERVER`, `NTFY_TOPIC`, and optional `NTFY_TOKEN` environment variables. File configuration uses `server`, `topic`, and optional `token` in `~/.config/pi-notify/`. An access token is sent as `Authorization: Bearer ...`.

After setup, tell the user to install the ntfy mobile app, add `https://ntfy.sh` (or their configured server), and subscribe using the topic printed by `setup`. Send a test only after setup succeeds.
