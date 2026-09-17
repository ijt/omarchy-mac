#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

lid_suspend="$ROOT/bin/omarchy-system-lid-suspend"
lid_open="$ROOT/bin/omarchy-system-lid-open"
dropin="$ROOT/etc/systemd/logind.conf.d/30-lid-ignore.conf"
hook="$ROOT/default/systemd/system-sleep/wake-session"

grep -F 'HandleLidSwitch=ignore' "$dropin" >/dev/null
grep -F 'HandleLidSwitchExternalPower=ignore' "$dropin" >/dev/null
pass "logind ignores lid close so Hyprland can debounce"

grep -F 'omarchy-system-lid-suspend' "$ROOT/bin/omarchy-system-lid-close" >/dev/null
pass "lid close starts a debounced suspend after locking"

grep -F 'omarchy-system-lid-open' "$hook" >/dev/null
grep -F 'sleep 1' "$hook" >/dev/null
pass "sleep hook wakes the session after thaw"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
runtime="$tmpdir/run"
mkdir -p "$runtime"

setup() {
  mock_bin="$tmpdir/bin"
  call_log="$tmpdir/calls"
  mkdir -p "$mock_bin"
  : >"$call_log"

  cat >"$mock_bin/omarchy-hw-laptop-closed" <<SH
#!/bin/bash
exit ${1:-0}
SH
  cat >"$mock_bin/omarchy-hw-external-monitors" <<SH
#!/bin/bash
exit ${2:-1}
SH
  cat >"$mock_bin/omarchy-toggle-enabled" <<'SH'
#!/bin/bash
[[ $1 == suspend-off ]] && exit 1
exit 1
SH
  cat >"$mock_bin/systemctl" <<SH
#!/bin/bash
echo systemctl "\$*" >>"$call_log"
SH
  chmod +x "$mock_bin"/*
}

setup 0 1
XDG_RUNTIME_DIR="$runtime" OMARCHY_LID_SUSPEND_DELAY=0.2 PATH="$mock_bin:$PATH" \
  "$lid_suspend"
sleep 0.5
mapfile -t calls <"$call_log"
[[ ${calls[0]} == "systemctl suspend" ]] ||
  fail "undocked closed lid suspends after the debounce" "calls: ${calls[*]}"
pass "undocked closed lid suspends after the debounce"

: >"$call_log"
setup 0 0
XDG_RUNTIME_DIR="$runtime" OMARCHY_LID_SUSPEND_DELAY=0.2 PATH="$mock_bin:$PATH" \
  "$lid_suspend"
sleep 0.5
mapfile -t calls <"$call_log" || true
[[ ${#calls[@]} -eq 0 ]] ||
  fail "docked lid close does not suspend" "calls: ${calls[*]}"
pass "docked lid close does not suspend"

: >"$call_log"
setup 0 1
XDG_RUNTIME_DIR="$runtime" OMARCHY_LID_SUSPEND_DELAY=1 PATH="$mock_bin:$PATH" \
  "$lid_suspend"
# Wait for the child to record its pid before cancelling.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -f $runtime/omarchy-lid-suspend.pid ]] && break
  sleep 0.05
done
XDG_RUNTIME_DIR="$runtime" PATH="$mock_bin:$PATH" "$lid_open"
sleep 1.2
mapfile -t calls <"$call_log" || true
[[ ${#calls[@]} -eq 0 ]] ||
  fail "opening the lid cancels a pending suspend" "calls: ${calls[*]}"
pass "opening the lid cancels a pending suspend"
