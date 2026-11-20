-- Keeps the agent from adding code comments. Comments already in the diff when
-- a session starts are left alone.

local find_script = [=[
base=$(git merge-base HEAD "$(git symbolic-ref -q --short refs/remotes/origin/HEAD || echo origin/main)" 2>/dev/null) || base=$1
[ -n "$base" ] || exit 0
globs="*.rb *.rake *.ru Gemfile Rakefile *.haml *.py *.go *.rs *.lua *.js *.jsx *.ts *.tsx *.css *.scss *.yml *.yaml *.sh"
set -f
{
  git diff "$base" -U0 --no-color --diff-filter=AM -- $globs
  git ls-files --others --exclude-standard -- $globs | while IFS= read -r path; do
    git diff --no-index -U0 --no-color /dev/null "$path"
  done
} | awk -v q="[\"'\`]" '
  /^\+\+\+ / { file = substr($0, 7); next }
  /^@@ /     { split($3, a, ","); line = substr(a[1], 2) + 0; next }
  /^\+/ {
    text = substr($0, 2)
    n = line++
    whole = (file ~ /\.lua$/) ? (text ~ /^[ \t]*--/) : (text ~ /^[ \t]*(#|\/\/|-#|\/\*|\*[ \/]|\*$)/)
    trailing = 0
    if (!whole && file !~ /\.lua$/ && match(text, /[ \t](#|\/\/)[ \t]/)) {
      before = substr(text, 1, RSTART)
      if (before !~ q && before !~ /[\/#]/ && before ~ /[^ \t]/) trailing = 1
    }
    if (!whole && !trailing) next
    if (text ~ /^[ \t]*#\{/) next
    if (text ~ /^#!/) next
    if (text ~ /^[ \t]*#!?\[/) next
    if (text ~ /^[ \t]*(#|\/\/|\/\*|--)[ \t]*$/) next
    if (text ~ /frozen_string_literal|rubocop:|eslint-|yamllint|@ts-|prettier-ignore|haml-lint:|shellcheck|noqa|type: ignore|go:(build|generate|embed)|nolint/) next
    if (text ~ /^#  / || text ~ /^# (== Schema|Table name:|Indexes|Foreign Keys|Check Constraints)/) next
    printf "%s:%d: %s\n", file, n, text
  }
' || exit 3
]=]

local baseline = nil
local start_head = ""
local repeats = {}
local warned = false

local function comment_lines()
  local ok, run = pcall(notch.exec, "sh", { "-c", find_script, "sh", start_head })
  local found = {}
  if not ok or type(run) ~= "table" or run.exit_code ~= 0 then
    if not warned then
      warned = true
      notch.ui.notify("no-comments: the comment check could not run, so comments are not being blocked", "warning")
    end
    return found
  end
  for line in (run.stdout or ""):gmatch("[^\n]+") do
    local file, text = line:match("^(.-):%d+: (.*)$")
    if file then found[#found + 1] = { key = file .. "\n" .. text, display = line } end
  end
  return found
end

local function counts(found)
  local by_key = {}
  for _, entry in ipairs(found) do by_key[entry.key] = (by_key[entry.key] or 0) + 1 end
  return by_key
end

local function new_comments()
  if not baseline then return {} end
  local seen, added = {}, {}
  for _, entry in ipairs(comment_lines()) do
    seen[entry.key] = (seen[entry.key] or 0) + 1
    if seen[entry.key] > (baseline[entry.key] or 0) then added[#added + 1] = entry.display end
  end
  return added
end

local function message(added)
  local shown = {}
  for i = 1, math.min(#added, 40) do shown[i] = added[i] end
  local more = #added > 40 and ("\n... and " .. (#added - 40) .. " more") or ""
  return "You added code comments. Comments are never allowed in code you write here.\n\n"
    .. table.concat(shown, "\n") .. more
    .. "\n\nDelete every one of these lines' comments now. Do not move the text into a string, a constant, "
    .. "or a differently styled comment. If code needs explaining, rename or restructure it, and put the "
    .. "explanation in your report or the PR description. If a listed line is not actually a comment, "
    .. "stop and tell the user; do not work around this check."
end

notch.on("before_agent_start", function(_event)
  if baseline then return end
  local ok, run = pcall(notch.exec, "sh", { "-c", "git rev-parse -q --verify HEAD 2>/dev/null; exit 0" })
  start_head = ok and type(run) == "table" and (run.stdout or ""):gsub("%s+", "") or ""
  baseline = counts(comment_lines())
end)

notch.on("session_change", function(_event)
  baseline = nil
  start_head = ""
  repeats = {}
  warned = false
end)

notch.on("tool_call", function(event)
  if event.name ~= "bash" or type(event.arguments) ~= "table" then return end
  local command = tostring(event.arguments.command or "")
  if not (command:find("git%s+commit") or command:find("git%s+push") or command:find("gh%s+pr%s+create")) then return end
  local added = new_comments()
  if #added == 0 then return end
  return { denied = true, reason = message(added) }
end)

notch.on("agent_end", function(_event)
  local added = new_comments()
  if #added == 0 then
    repeats = {}
    return
  end
  local signature = table.concat(added, "\n")
  repeats[signature] = (repeats[signature] or 0) + 1
  if repeats[signature] > 2 then
    notch.ui.notify("no-comments: the agent left " .. #added .. " comment line(s) after two reminders", "warning")
    return
  end
  return { follow_up = message(added) }
end)

notch.register_command({
  name = "allow-comments",
  description = "Accept the comment lines currently in the diff so the no-comments check stops flagging them",
  execute = function(_args)
    baseline = counts(comment_lines())
    repeats = {}
    return "no-comments: accepted the current comment lines for this session"
  end,
})
