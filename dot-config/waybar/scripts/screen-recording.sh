#!/usr/bin/env bash

state_dir="${XDG_RUNTIME_DIR:-/tmp}/record-screen"
pidfile="$state_dir/pid"

if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
  printf '{"text":"󰻂","tooltip":"Stop screen recording","class":"active"}\n'
else
  printf '{"text":""}\n'
fi
