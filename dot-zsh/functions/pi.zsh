function pi() {
  local -a flags

  # pi's package-management subcommands are only recognized when they are the
  # first argument. Do not prepend provider/model defaults for those commands,
  # otherwise `pi update` becomes `pi --provider ... --model ... update` and the
  # CLI treats it like a normal prompt instead of the update command.
  case "$1" in
    install|remove|uninstall|update|list|config)
      ;;
    *)
      [[ -n "$PI_DEFAULT_PROVIDER" ]] && flags+=(--provider "$PI_DEFAULT_PROVIDER")
      [[ -n "$PI_DEFAULT_MODEL" ]]    && flags+=(--model    "$PI_DEFAULT_MODEL")
      ;;
  esac

  if whence -p pi >/dev/null; then
    command pi "${flags[@]}" "$@"
  elif command -v mise >/dev/null 2>&1; then
    mise exec npm:@earendil-works/pi-coding-agent -- pi "${flags[@]}" "$@"
  else
    print -u2 "pi: executable not found"
    return 127
  fi
}
