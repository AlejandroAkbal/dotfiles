#!/usr/bin/env bash
set -u

export PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
port=9119
marker="$HOME/.hermes/.hermes-update-in-progress"
pid_file="$HOME/.hermes/serve-supervisor.pid"

owner_pid() {
  lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | head -1
}

is_hermes_serve() {
  ps -p "$1" -o command= 2>/dev/null | grep -Fq 'hermes serve '
}

if [[ "${1:-}" == "--check" ]]; then
  owner="$(owner_pid)"
  [[ -n "$owner" ]] || exit 1
  [[ "$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | wc -l | tr -d ' ')" == 1 ]] || exit 1
  is_hermes_serve "$owner"
  [[ "$(ps -p "$owner" -o ppid= | tr -d ' ')" == "$(<"$pid_file")" ]]
  exit
fi

printf '%s\n' "$$" >"$pid_file"
child=
cleanup() {
  [[ -n "$child" ]] && kill -TERM "$child" 2>/dev/null || true
  rm -f "$pid_file"
}
trap 'exit 0' TERM INT
trap cleanup EXIT

while true; do
  while [[ -e "$marker" ]]; do sleep 1; done

  owner="$(owner_pid)"
  if [[ -n "$owner" ]]; then
    if is_hermes_serve "$owner"; then
      kill -TERM "$owner" 2>/dev/null || true
      while kill -0 "$owner" 2>/dev/null; do sleep 1; done
    else
      printf 'Port %s is owned by an unknown process; refusing to replace it.\n' "$port" >&2
      sleep 10
      continue
    fi
  fi

  hermes serve --host 127.0.0.1 --port "$port" &
  child=$!
  wait "$child"
  child=
  sleep 1
done
