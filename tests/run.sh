#!/usr/bin/env bash
# Runs the tests against the real script with a fake device and network:
#   tests/run.sh [--script path/to/fdroid-tester.sh] [test name filter]
set -u
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" = 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
  echo "bash 4.4 or newer is needed (macOS: brew install bash)" >&2; exit 2
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../fdroid-tester.sh"; FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --script) SCRIPT="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift ;;
    *) FILTER="$1" ;;
  esac
  shift
done
BASH_DIR="$(dirname "$BASH")"
. "$HERE/lib.sh"
APKS="$(mktemp -d)"
build_apk "$APKS/phone.apk" org.example.phone launcher
build_apk "$APKS/net.apk" org.example.net launcher INTERNET
build_apk "$APKS/tv.apk" org.example.tv tv
for f in "$HERE"/test_*.sh; do . "$f"; done
passed=0; failed=()
for t in $(declare -F | awk '{print $3}' | grep '^test_' | grep -e "$FILTER"); do
  # not inside "if": set -e must stay active in the test
  ( set -e; new_case; "$t" ) > "$APKS/$t.log" 2>&1
  if [ $? = 0 ]; then
    passed=$((passed + 1)); printf 'ok   %s\n' "$t"
  else
    failed+=("$t"); printf 'FAIL %s\n' "$t"; sed 's/^/     /' "$APKS/$t.log" | tail -30
  fi
done
printf '\n%s passed, %s failed\n' "$passed" "${#failed[@]}"
# a filter that matches nothing must not look like a passing run
if [ $((passed + ${#failed[@]})) = 0 ]; then echo "no test matches '$FILTER'" >&2; exit 1; fi
[ "${#failed[@]}" = 0 ]
