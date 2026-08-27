#!/usr/bin/env bash
set -uo pipefail

brew_bin="$(command -v brew || true)"
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [[ -n "$brew_bin" || ! -x "$candidate" ]] || brew_bin="$candidate"
done
if [[ -n "$brew_bin" ]]; then
  export PATH="$(dirname "$brew_bin"):$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
fi

if [[ "${1:-}" == "--check" ]]; then
  [[ -n "$brew_bin" ]] && { "$brew_bin" outdated --formula; "$brew_bin" outdated --cask; }
  launchctl print system/com.alejandro.daily-softwareupdate 2>/dev/null | grep -E 'state|runs|last exit code' || true
  command -v mas >/dev/null 2>&1 && mas outdated
  exit 0
fi

mkdir -p "$HOME/Library/Logs"
exec >>"$HOME/Library/Logs/mac-mini-maintenance.log" 2>&1
printf '\n[%s] daily maintenance\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/mac-mini-maintenance.XXXXXX")"
report="$tmp_dir/report.txt"
printf 'Mac mini automatic update report\n\n' >"$report"
important=0
failed=0

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

append_report() {
  printf '%s\n' "$1" >>"$report"
}

run_capture() {
  local label="$1"
  local output="$2"
  shift 2
  printf '\n--- %s ---\n' "$label"
  "$@" 2>&1 | tee "$output"
  local rc="${PIPESTATUS[0]}"
  printf '[%s exit=%s]\n' "$label" "$rc"
  return "$rc"
}

record_matches() {
  local output="$1"
  local pattern="$2"
  local matches
  matches="$(grep -E "$pattern" "$output" 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    while IFS= read -r line; do
      printf '  %s\n' "$line" >>"$report"
    done <<<"$matches"
  fi
}

if [[ -n "$brew_bin" ]]; then
  brew_update="$tmp_dir/brew-update.txt"
  brew_formula="$tmp_dir/brew-formula.txt"
  brew_cask="$tmp_dir/brew-cask.txt"

  if ! run_capture 'Homebrew metadata update' "$brew_update" "$brew_bin" update; then
    append_report 'Homebrew metadata update failed; package upgrades may be incomplete.'
    failed=1
    important=1
  fi
  if ! run_capture 'Homebrew formula upgrades' "$brew_formula" "$brew_bin" upgrade --formula --yes; then
    append_report 'Homebrew formula upgrade failed.'
    failed=1
    important=1
  fi
  if grep -Eq '(^==> Upgraded| -> )' "$brew_formula"; then
    append_report 'Homebrew formulae changed:'
    record_matches "$brew_formula" '(^==> Upgraded| -> )'
    important=1
  fi
  if ! run_capture 'Homebrew cask upgrades' "$brew_cask" "$brew_bin" upgrade --cask --greedy-auto-updates --yes; then
    append_report 'Homebrew application upgrade failed.'
    failed=1
    important=1
  fi
  if grep -Eq '(^==> Upgraded| -> )' "$brew_cask"; then
    append_report 'Homebrew applications changed:'
    record_matches "$brew_cask" '(^==> Upgraded| -> )'
    important=1
  fi
else
  append_report 'Homebrew is not installed or could not be resolved.'
  failed=1
  important=1
fi


system_daemon="$tmp_dir/system-daemon.txt"
if launchctl print system/com.alejandro.daily-softwareupdate >"$system_daemon" 2>&1; then
  if grep -q 'state = running' "$system_daemon"; then
    append_report 'macOS system update job is still running; installation may require a restart or owner authentication.'
    important=1
  fi
  if grep -Eq 'last exit code = [1-9]' "$system_daemon"; then
    append_report 'Important: the privileged macOS update job last exited unsuccessfully:'
    record_matches "$system_daemon" 'last exit code = .*'
    failed=1
    important=1
  fi
else
  append_report 'Important: the privileged macOS update LaunchDaemon is not loaded.'
  failed=1
  important=1
fi
system_log="$tmp_dir/system-update-log.txt"
if [[ -f /var/log/alejandro-softwareupdate.log ]]; then
  tail -50 /var/log/alejandro-softwareupdate.log >"$system_log"
  if grep -Eq 'Downloaded:|Failed to authenticate|Failed to install|Install failed' "$system_log"; then
    append_report 'Important: the macOS system updater recorded a download/install issue:'
    record_matches "$system_log" 'Downloaded:|Failed to authenticate|Failed to install|Install failed'
    failed=1
    important=1
  fi
fi

if command -v mas >/dev/null 2>&1; then
  mas_outdated="$tmp_dir/mas-outdated.txt"
  mas_upgrade="$tmp_dir/mas-upgrade.txt"
  mas_bin="$(command -v mas)"
  if ! run_capture 'Mac App Store update check' "$mas_outdated" "$mas_bin" outdated; then
    append_report 'Mac App Store update check failed.'
    failed=1
    important=1
  elif [[ -s "$mas_outdated" ]]; then
    append_report 'Mac App Store updates were found:'
    record_matches "$mas_outdated" '.*'
    important=1
    if ! run_capture 'Mac App Store upgrades' "$mas_upgrade" /usr/bin/sudo -n "$mas_bin" upgrade; then
      append_report 'Mac App Store upgrades failed; administrator authentication may be required.'
      failed=1
    else
      append_report 'Mac App Store upgrade command completed.'
    fi
  fi
else
  append_report 'mas is not installed; Mac App Store updates were skipped.'
  failed=1
  important=1
fi

if (( important )); then
  printf '\n[%s] Telegram update report:\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
  send_result="$(tgcli send text --to -1004420303603 --topic 3 --message "$(cat "$report")" --parse-mode none 2>&1)"
  printf '%s\n' "$send_result"
  if ! grep -q 'Message sent successfully' <<<"$send_result"; then
    printf 'Telegram notification failed.\n'
    failed=1
  else
    printf 'Telegram notification sent to Alex Command Center topic 3.\n'
  fi
else
  printf 'No important updates or failures; Telegram notification suppressed.\n'
fi

if (( failed )); then
  exit 1
fi
