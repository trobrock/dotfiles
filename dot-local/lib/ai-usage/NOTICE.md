# Upstream attribution

The provider collectors in `providers/claude`, `providers/codex`, and
`providers/fireworks` are adapted from the following files in Omarchy:

- `bin/omarchy-agent-usage-claude`
- `bin/omarchy-agent-usage-codex`
- `bin/omarchy-agent-usage-fireworks`

Source repository: <https://github.com/basecamp/omarchy>

Exact source commit: `b15ec6c6b3bac1e0406608f4a130f1684e734088`
(`origin/quattro` at the time these files were vendored).

The upstream project is MIT licensed. Its license text is reproduced exactly
in [`LICENSE.upstream`](LICENSE.upstream). The collectors have been adapted for
local executable, cache, configuration, privacy, and redirect-handling paths;
no credentials or live usage data are included.
