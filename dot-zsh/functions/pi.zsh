function pi() {
  local -a flags
  [[ -n "$PI_DEFAULT_PROVIDER" ]] && flags+=(--provider "$PI_DEFAULT_PROVIDER")
  [[ -n "$PI_DEFAULT_MODEL" ]]    && flags+=(--model    "$PI_DEFAULT_MODEL")

  if whence -p pi >/dev/null; then
    command pi "${flags[@]}" "$@"
  elif command -v mise >/dev/null 2>&1; then
    mise exec npm:@earendil-works/pi-coding-agent -- pi "${flags[@]}" "$@"
  else
    print -u2 "pi: executable not found"
    return 127
  fi
}
