# fdroid-tester extensions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `fdroid-tester.sh` with screenshots during the run (embedded when posted), Android TV app support, PCAPdroid root-mode capture and local-APK input, each as a separate upstream-ready change.

**Architecture:** All product changes stay inside the single bash script and its embedded Python helper, in upstream's style. A fork-only test harness (`tests/`) runs the real script against `aapt2`-built fixture APKs with fake `adb`, `curl`, `glab` and `open` on `PATH`, logging every call, so each feature is driven by failing tests first. Each feature lands on the fork's `main` through its own PR with the script change and its tests in separate commits; upstream PRs later cherry-pick only the script commits.

**Tech Stack:** bash ≥ 4.4 (Homebrew bash 5.3 here), Python 3 (embedded helper), Android build-tools `aapt2`, shellcheck, GitHub `gh`, GitLab `glab`.

**Spec:** `docs/superpowers/specs/2026-10-12-fdroid-tester-extensions-design.md`

## Global Constraints

- One script, `fdroid-tester.sh`; Python only inside its `tool.py` heredoc; no new dependencies.
- Upstream style: plain-English messages via `say`/`note`/`warn`/`ok`/`act`/`row`; comments explain why; commit subjects `#0 <sentence>`.
- Input stays line-based through `readline` (non-TTY use keeps working).
- `set -eu` stays; `[ cond ] && cmd` only where its failure cannot be a function's last status.
- No `tcpdump`, no iptables; root capture is PCAPdroid `-e root_capture true`.
- Tests and docs under `tests/` and `docs/superpowers/` never go into an upstream PR.
- Device work only on `192.168.51.53:5555` with an explicit `-s`; other connected devices are not touched.
- Nothing is posted to a real fdroiddata merge request without the owner's explicit yes.
- Every commit ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; every PR body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

## Review Focus

- PCAPdroid root-mode capture files: the link type and whether hosts are named; a run on the AM9 must show named HTTPS hosts (Task 7, step 4).
- GitLab's uploads API for a non-member on gitlab.com: which project accepts it and whether `full_path` is returned; a real upload must render in a Markdown preview (Task 7, step 6).
- The first `su -c id` on a Magisk device can show a root prompt for the shell and wait; the checks must not hang indefinitely (Task 7, step 3).
- 4K TV screenshots are large PNGs; the upload must succeed and the image must render at its `width` (Task 7, step 6).
- Captions with Markdown characters (`[`, `]`, backticks) must not break the embedded image; covered by `test_caption_with_brackets_is_safe_in_alt_text` (Task 3).

---

### Task 0: Merge the design branch into the fork's `main`

**Files:** none changed (spec and this plan are already on `feat/extensions-design`).

- [ ] **Step 1: Open the PR**

```bash
cd ~/Scripts/fdroid-tester/.worktrees/extensions-design
gh pr create --repo johnneerdael/fdroid-tester --base main --head feat/extensions-design \
  --title "Design and plan: screenshots, TV apps, root capture, local APK" \
  --body "Spec and implementation plan for this fork's additions. Fork-only: never part of an upstream PR.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

- [ ] **Step 2: Merge it** (documentation only; the owner approved both files in conversation)

```bash
gh pr merge --repo johnneerdael/fdroid-tester feat/extensions-design --merge
```

---

### Task 1: Test harness (fork only)

**Files:**
- Create: `tests/run.sh`, `tests/lib.sh`
- Create: `tests/stubs/adb`, `tests/stubs/curl`, `tests/stubs/glab`, `tests/stubs/open`
- Create: `tests/fixtures/png.py`, `tests/fixtures/pcap.py`
- Create: `tests/test_baseline.sh`

**Interfaces:**
- Produces, for all later test files (sourced by `run.sh`, each test runs in its own subshell with `set -e` after `new_case`):
  - `$HERE` (tests folder), `$SCRIPT` (script under test), `$APKS/{phone,net,tv}.apk` (packages `org.example.phone`, `org.example.net` with INTERNET, `org.example.tv` Leanback-only and Leanback-required; all versionCode 7, versionName 1.2.3)
  - `$T` (case folder), `$FAKE` (fake device/network state), `$RC` (script exit status), `$T/out.txt` (all output)
  - `use_mr <apk file in $APKS> <package>` — merge request !123, source project 555, CI APK `<package>_7.apk`, category Multimedia, summary "An example app"
  - `run_tester "<answers with \n>" <script args…>` — answers first, then 80 empty lines (defaults)
  - `review_dir` — prints `$T/work/${FAKE_APPID}_7-review`
  - `fail`, `assert_rc <n>`, `assert_out <ERE>`, `refute_out <ERE>`, `assert_has <file> <fixed string>`, `refute_has <file> <fixed string>`
  - Fake device switches (export them inside a test): files `$FAKE/root`, `$FAKE/features`, `$FAKE/screen.png`, `$FAKE/traffic.pcap`; env `FAKE_APPID`, `FAKE_CRASH_AFTER=<n screencaps>`, `FAKE_NO_LAUNCHER=1`, `FAKE_GLAB_OFF=1`, `FAKE_UPLOAD_FAIL="<project ids>"`
  - Logs: `$FAKE/calls.log` (adb), `$FAKE/curl.log`, `$FAKE/glab.log`, `$FAKE/note.md` (posted body)

- [ ] **Step 1: Create the worktree**

```bash
cd ~/Scripts/fdroid-tester && git fetch origin
git worktree add -b feat/test-harness .worktrees/test-harness origin/main
cd .worktrees/test-harness && mkdir -p tests/stubs tests/fixtures
```

- [ ] **Step 2: Write `tests/fixtures/png.py`**

```python
"""png.py W H: writes a W x H grey PNG to stdout (a fake screenshot)."""
import struct, sys, zlib

w, h = int(sys.argv[1]), int(sys.argv[2])


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


rows = b"".join(b"\x00" + b"\x80" * w for _ in range(h))
sys.stdout.buffer.write(b"\x89PNG\r\n\x1a\n"
                        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
                        + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
```

- [ ] **Step 3: Write `tests/fixtures/pcap.py`**

```python
"""pcap.py HOST LINKTYPE: a capture with one TLS ClientHello for HOST, stamped now."""
import struct, sys, time

host, link = sys.argv[1].encode(), int(sys.argv[2])
sni = struct.pack("!BH", 0, len(host)) + host
ext = struct.pack("!HHH", 0, len(sni) + 2, len(sni)) + sni
body = (b"\x03\x03" + b"\x00" * 32 + b"\x00" + b"\x00\x02\x00\x2f" + b"\x01\x00"
        + struct.pack("!H", len(ext)) + ext)
handshake = b"\x01" + len(body).to_bytes(3, "big") + body
tls = b"\x16\x03\x01" + struct.pack("!H", len(handshake)) + handshake
tcp = struct.pack("!HHIIBBHHH", 40000, 443, 1, 0, 5 << 4, 0x18, 65535, 0, 0)
ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, 20 + len(tcp) + len(tls), 1, 0, 64, 6, 0,
                 bytes([10, 0, 0, 2]), bytes([1, 2, 3, 4]))
packet = ip + tcp + tls
now = int(time.time())
sys.stdout.buffer.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, link)
                        + struct.pack("<IIII", now, 0, len(packet), len(packet)) + packet)
```

- [ ] **Step 4: Write `tests/stubs/adb`**

```bash
#!/usr/bin/env bash
# Fake adb for the tests: one device, its state in $FAKE, every call logged.
set -u
printf '%s\n' "$*" >> "$FAKE/calls.log"
[ "${1-}" = -s ] && shift 2
cmd="${1-}"; shift || true
caps() { cat "$FAKE/screencaps" 2>/dev/null || echo 0; }
case "$cmd" in
  start-server) exit 0 ;;
  version) echo "Android Debug Bridge version 1.0.41"; exit 0 ;;
  devices) printf 'List of devices attached\nFAKE01\tdevice\n'; exit 0 ;;
  install) touch "$FAKE/installed"; echo Success; exit 0 ;;
  uninstall) rm -f "$FAKE/installed"; echo Success; exit 0 ;;
  exec-out) echo $(( $(caps) + 1 )) > "$FAKE/screencaps"; cat "$FAKE/screen.png"; exit 0 ;;
  logcat)
    [ "${1-}" = -c ] && exit 0
    if [ -n "${FAKE_CRASH_AFTER:-}" ] && [ "$(caps)" -ge "$FAKE_CRASH_AFTER" ]; then
      printf 'FATAL EXCEPTION: main\nProcess: %s, PID: 4321\n' "$FAKE_APPID"
    fi
    exit 0 ;;
  pull) cp "$FAKE/traffic.pcap" "$2" 2>/dev/null; exit $? ;;
  shell) ;;
  *) echo "fake adb: unknown command $cmd" >&2; exit 1 ;;
esac
line="$*"
case "$line" in
  "getprop ro.product.cpu.abilist") echo "arm64-v8a,armeabi-v7a" ;;
  "getprop ro.build.version.sdk") echo 34 ;;
  "getprop ro.build.version.release") echo 14 ;;
  "getprop ro.product.manufacturer") echo Fake ;;
  "getprop ro.product.model") echo Box ;;
  "dumpsys package com.emanuelef.remote_capture") printf '    versionCode=80 minSdk=21\n    versionName=1.8.6\n' ;;
  "dumpsys activity services com.emanuelef.remote_capture")
    [ -e "$FAKE/capturing" ] && echo "  * ServiceRecord{1 u0 com.emanuelef.remote_capture/.CaptureService}" ;;
  "am start -n com.emanuelef.remote_capture/.activities.CaptureCtrl -e action start"*) touch "$FAKE/capturing" ;;
  "am start -n com.emanuelef.remote_capture/.activities.CaptureCtrl -e action stop"*) rm -f "$FAKE/capturing" ;;
  "pm path "*) [ -e "$FAKE/installed" ] && echo "package:/data/app/${line#pm path }/base.apk" ;;
  "pm list features") cat "$FAKE/features" ;;
  "su -c id")
    if [ -e "$FAKE/root" ]; then echo "uid=0(root) gid=0(root)"
    else echo "/system/bin/sh: su: inaccessible or not found"; exit 127; fi ;;
  "pidof "*) [ -e "$FAKE/installed" ] && echo 4321 ;;
  "settings get global stay_on_while_plugged_in") echo 0 ;;
  "date +%s") date +%s ;;
  "monkey "*)
    if [ -n "${FAKE_NO_LAUNCHER:-}" ]; then echo "** No activities found to run, monkey aborted."
    else echo "Events injected: 1"; fi ;;
  *) : ;;   # svc, input, dumpsys window, am start of the app, rm, …: accepted silently
esac
exit 0
```

- [ ] **Step 5: Write `tests/stubs/curl`**

```bash
#!/usr/bin/env bash
# Fake curl for the tests: serves the fixtures in $FAKE by address.
set -u
printf '%s\n' "$*" >> "$FAKE/curl.log"
out=""; fmt=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -w) fmt="$2"; shift ;;
    -m|-H|-F) shift ;;
    http*) url="$1" ;;
  esac
  shift
done
serve() { if [ -n "$out" ]; then cp "$1" "$out"; else cat "$1"; fi; }
code=200
case "$url" in
  *reports.exodus-privacy.eu.org*) printf '{"trackers": {}}' > "$FAKE/trackers.json"; serve "$FAKE/trackers.json" ;;
  */projects/fdroid%2Ffdroiddata) : ;;
  */projects/fdroid%2Ffdroiddata/merge_requests/*) serve "$FAKE/mr.json" ;;
  *codequality_reports.json) serve "$FAKE/cq.json" ;;
  *.apk) serve "$FAKE/app.apk" ;;
  */repository/files/metadata%2F*) serve "$FAKE/meta.yml" ;;
  *) code=404; [ -n "$fmt" ] || exit 22 ;;
esac
[ -n "$fmt" ] && printf '%s' "$code"
exit 0
```

- [ ] **Step 6: Write `tests/stubs/glab` and `tests/stubs/open`**

`tests/stubs/glab`:

```bash
#!/usr/bin/env bash
# Fake glab for the tests: a logged-in user, uploads and notes kept in $FAKE.
set -u
printf '%s\n' "$*" >> "$FAKE/glab.log"
case "$*" in
  "auth status"*) [ -z "${FAKE_GLAB_OFF:-}" ] ;;
  "api user") echo '{"username": "tester"}' ;;
  "api --method POST projects/"*"/uploads -F file=@"*)
    project="${4#projects/}"; project="${project%/uploads}"; name="$(basename "${6#file=@}")"
    case " ${FAKE_UPLOAD_FAIL:-} " in *" $project "*) echo '{"message": "403 Forbidden"}'; exit 1 ;; esac
    if [ "$project" = "fdroid%2Ffdroiddata" ]; then
      printf '{"url": "/uploads/def/%s"}\n' "$name"
    else
      printf '{"url": "/uploads/abc/%s", "full_path": "/-/project/%s/uploads/abc/%s"}\n' "$name" "$project" "$name"
    fi ;;
  "api --method POST projects/"*"/notes -F body=@"*) cp "${6#body=@}" "$FAKE/note.md"; echo '{"id": 77}' ;;
  *) echo "fake glab: unknown call $*" >&2; exit 1 ;;
esac
```

`tests/stubs/open`:

```bash
#!/usr/bin/env bash
# Fake open: the tests never start a browser.
printf '%s\n' "$*" >> "$FAKE/open.log"
```

Then: `chmod +x tests/stubs/*`

- [ ] **Step 7: Write `tests/lib.sh`**

```bash
# Helpers for the tests: fixture APKs, a fake device, running the script, checks.

AAPT2="$(ls -d "${ANDROID_HOME:?set ANDROID_HOME to the Android SDK}"/build-tools/*/aapt2 | sort -V | tail -1)"
ANDROID_JAR="$(ls -d "$ANDROID_HOME"/platforms/android-*/android.jar | sort -V | tail -1)"

build_apk() {  # build_apk <out.apk> <package> <launcher|tv> [INTERNET]
  local out="$1" pkg="$2" kind="$3" perm="" feature="" category=LAUNCHER dir
  dir="$(mktemp -d)"
  [ "${4-}" = INTERNET ] && perm='<uses-permission android:name="android.permission.INTERNET"/>'
  if [ "$kind" = tv ]; then
    category=LEANBACK_LAUNCHER
    feature='<uses-feature android:name="android.software.leanback" android:required="true"/>'
  fi
  cat > "$dir/AndroidManifest.xml" <<EOF
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$pkg"
    android:versionCode="7" android:versionName="1.2.3">
  <uses-sdk android:minSdkVersion="21" android:targetSdkVersion="34"/>
  $perm
  $feature
  <application android:label="Example">
    <activity android:name=".Main" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.$category"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
EOF
  "$AAPT2" link -o "$out" -I "$ANDROID_JAR" --manifest "$dir/AndroidManifest.xml"
  rm -rf "$dir"
}

new_case() {  # a fresh case: $T/work is where the script runs, $FAKE the device
  T="$(mktemp -d)"
  FAKE="$T/fake"
  mkdir -p "$FAKE" "$T/work" "$T/home"
  python3 "$HERE/fixtures/png.py" 4 2 > "$FAKE/screen.png"
  printf 'feature:android.hardware.touchscreen\n' > "$FAKE/features"
  export FAKE FAKE_APPID=org.example.phone
  echo "case folder: $T"
}

use_mr() {  # use_mr <apk in $APKS> <package> — merge request !123 whose CI built it
  cp "$APKS/$1" "$FAKE/app.apk"
  export FAKE_APPID="$2"
  cat > "$FAKE/mr.json" <<EOF
{"title": "New app: Example", "state": "opened", "author": {"username": "dev"},
 "labels": ["review-requested"], "web_url": "https://gitlab.com/fdroid/fdroiddata/-/merge_requests/123",
 "sha": "0123abcd", "source_project_id": 555}
EOF
  cat > "$FAKE/cq.json" <<EOF
{"new_errors": [
 {"description": "Signed APK: https://gitlab.com/fdroid/fdroiddata/-/jobs/1/artifacts/raw/tmp/${2}_7.apk", "severity": "info"},
 {"description": "Fastlane/Triple-T in en-US: summary (An example app), name (Example)", "severity": "info"}]}
EOF
  printf 'Categories:\n  - Multimedia\n' > "$FAKE/meta.yml"
}

run_tester() {  # run_tester "<answers>" <args…> — answers, then Enter for every default
  local answers="$1"; shift
  RC=0
  ( cd "$T/work" && { printf '%b' "$answers"; yes '' | head -80; } \
      | PATH="$HERE/stubs:$BASH_DIR:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$T/home" \
        XDG_CACHE_HOME="$T/home/cache" XDG_CONFIG_HOME="$T/home/config" \
        EDITOR=true VISUAL=true "$BASH" "$SCRIPT" "$@" ) > "$T/out.txt" 2>&1 || RC=$?
}

review_dir() { printf '%s' "$T/work/${FAKE_APPID}_7-review"; }

fail() {
  printf 'FAIL: %s\n' "$*"
  [ -f "$T/out.txt" ] && tail -25 "$T/out.txt"
  return 1
}
assert_rc()  { [ "$RC" = "$1" ] || fail "exit status $RC, wanted $1"; }
assert_out() { grep -qE -- "$1" "$T/out.txt" || fail "output lacks /$1/"; }
refute_out() { ! grep -qE -- "$1" "$T/out.txt" || fail "output has /$1/"; }
assert_has() { grep -qF -- "$2" "$1" 2>/dev/null || fail "$1 lacks: $2"; }
refute_has() { ! grep -qF -- "$2" "$1" 2>/dev/null || fail "$1 has: $2"; }
```

- [ ] **Step 8: Write `tests/run.sh`**

```bash
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
[ "${#failed[@]}" = 0 ]
```

Then: `chmod +x tests/run.sh`

- [ ] **Step 9: Write `tests/test_baseline.sh`** (pins upstream behaviour that must survive every feature)

```bash
# The unchanged flow: an fdroiddata merge request, its CI APK, a posted report.

test_check_only_is_ready() {
  run_tester "" --check
  assert_rc 0
  assert_out "ready"
}

test_mr_run_writes_and_posts_the_report() {
  use_mr phone.apk org.example.phone
  run_tester "" -w 1 --keep 123
  assert_rc 0
  assert_has "$(review_dir)/report.md" 'Tested `org.example.phone` 1.2.3 (7)'
  assert_has "$(review_dir)/report.md" '- [x] The app can start and work normally.'
  [ -s "$(review_dir)/after-1s.png" ] || fail "no after-1s.png"
  assert_has "$FAKE/note.md" 'Tested `org.example.phone` 1.2.3 (7)'
}

test_mr_run_records_traffic() {
  use_mr net.apk org.example.net
  python3 "$HERE/fixtures/pcap.py" example.org 101 > "$FAKE/traffic.pcap"
  export FAKE_GLAB_OFF=1
  run_tester "" -w 1 --keep 123
  assert_rc 0
  assert_out "connections in the first 1 seconds"
  assert_has "$(review_dir)/report.md" "example.org"
}
```

- [ ] **Step 10: Run the harness against the unchanged script**

Run: `ANDROID_HOME=~/Library/Android/sdk /opt/homebrew/bin/bash tests/run.sh`
Expected: `3 passed, 0 failed`. If a baseline test fails, fix the harness (stub output or answers), never the script; the script is upstream's.

- [ ] **Step 11: Commit, push, PR, merge**

```bash
git add tests
git commit -m "#0 Test harness: the real script against fixture APKs and a fake device

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin feat/test-harness
gh pr create --repo johnneerdael/fdroid-tester --base main --head feat/test-harness \
  --title "Test harness for this fork" --body "Fork-only tests: fixture APKs built with aapt2, fake adb/curl/glab/open, baseline tests of the unchanged flow. Validation: 3 passed, 0 failed.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

Comment `@codex review` on the PR; wait for Codex's completed review of the head (thumbs-up or findings); address findings; then `gh pr merge --merge`. If Codex never starts on this fork, stop and report it as a blocker.

---

### Task 2: Android TV apps (upstream PR 1)

**Files:**
- Modify: `fdroid-tester.sh` (badging parse after `LOCALES=`; device check after the minSdk `die`; launch block in step 4; "phone" → "device" wording)
- Create: `tests/test_tv.sh`

**Interfaces:**
- Consumes: Task 1 harness.
- Produces: shell variables `LAUNCH_ACT`, `TV_ACT`, `NEEDS_TV` (0/1); messages say "device".

- [ ] **Step 1: Worktree**

```bash
cd ~/Scripts/fdroid-tester && git fetch origin
git worktree add -b feat/tv-apps .worktrees/tv-apps origin/main && cd .worktrees/tv-apps
```

- [ ] **Step 2: Write the failing tests `tests/test_tv.sh`**

```bash
# Android TV apps: Leanback launch, TV requirement, "device" wording.

test_tv_app_opens_through_its_leanback_activity() {
  use_mr tv.apk org.example.tv
  printf 'feature:android.software.leanback\n' > "$FAKE/features"
  export FAKE_NO_LAUNCHER=1 FAKE_GLAB_OFF=1
  run_tester "" -w 1 --keep 123
  assert_rc 0
  assert_has "$FAKE/calls.log" "shell am start -n org.example.tv/org.example.tv.Main"
  refute_has "$FAKE/calls.log" "monkey"
  refute_out "open it by hand"
}

test_tv_app_stops_on_a_device_without_leanback() {
  use_mr tv.apk org.example.tv
  run_tester "" -w 1 --keep 123
  assert_rc 1
  assert_out "this app needs Android TV; the device is not one"
  refute_has "$FAKE/calls.log" "install -r"
}

test_phone_app_still_opens_through_the_launcher() {
  use_mr phone.apk org.example.phone
  export FAKE_GLAB_OFF=1
  run_tester "" -w 1 --keep 123
  assert_rc 0
  assert_has "$FAKE/calls.log" "monkey -p org.example.phone -c android.intent.category.LAUNCHER 1"
}

test_messages_say_device_not_phone() {
  use_mr phone.apk org.example.phone
  export FAKE_GLAB_OFF=1
  run_tester "" -w 1 --keep 123
  assert_out "4\. On the device"
  refute_out "[Tt]he phone|your phone|a phone|no phone"
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `ANDROID_HOME=~/Library/Android/sdk /opt/homebrew/bin/bash tests/run.sh tv_\|device_not\|launcher`
Expected: `test_tv_app_opens…`, `test_tv_app_stops…`, `test_messages_say…` FAIL; `test_phone_app_still…` passes.

- [ ] **Step 4: Read the launch entries and the TV requirement** — after the line `LOCALES="$(bget "s/^locales: //p" | tr -d "'")"` add:

```bash
LAUNCH_ACT="$(bget "s/^launchable-activity: name='\([^']*\)'.*/\1/p")"
TV_ACT="$(bget "s/^leanback-launchable-activity: name='\([^']*\)'.*/\1/p")"
# A TV app that requires Android TV lists the Leanback feature as required.
NEEDS_TV=0
printf '%s\n' "$BADGING" | grep -qE "^[[:space:]]*uses-feature: name='android.software.leanback'$" && NEEDS_TV=1
```

- [ ] **Step 5: Stop early on a device that is not a TV** — after the block that ends `die "the app needs Android SDK $MINSDK, …"` / `fi`, add:

```bash
if [ "$NO_DEVICE" = 0 ] && [ "$NEEDS_TV" = 1 ] \
   && ! ash pm list features | grep -qx 'feature:android.software.leanback'; then
  die "this app needs Android TV; the device is not one"
fi
```

- [ ] **Step 6: Launch through the Leanback entry** — replace

```bash
  if "${ADB[@]}" shell monkey -p "$APPID" -c android.intent.category.LAUNCHER 1 2>&1 | grep -q 'No activities found'; then
    warn "the app has no launcher icon to open — open it by hand"
  fi
```

with

```bash
  if [ -z "$LAUNCH_ACT" ] && [ -n "$TV_ACT" ]; then
    # A TV-only app has no ordinary launcher entry, only the Leanback one.
    "${ADB[@]}" shell am start -n "$APPID/$TV_ACT" >/dev/null 2>&1 \
      || warn "could not open its TV activity — open it by hand"
  elif "${ADB[@]}" shell monkey -p "$APPID" -c android.intent.category.LAUNCHER 1 2>&1 | grep -q 'No activities found'; then
    warn "the app has no launcher icon to open — open it by hand"
  fi
```

- [ ] **Step 7: "phone" becomes "device"**

```bash
perl -pi -e 's/\bphone\b/device/g' fdroid-tester.sh
grep -n -i 'phone' fdroid-tester.sh
```

Expected remaining matches only: `NO_PHONE_FOUND` (several), `phone_locked` (four), `READ_PHONE_STATE|READ_PHONE_NUMBERS`. Then read every changed line (`git diff -U0 | grep '^[-+]' | less`) and fix any sentence that reads wrongly; line 5's header becomes "…on a device, …" and also add "(a phone or an Android TV)" there:

```bash
# fdroid-tester.sh — test an app from an fdroiddata merge request on a device
# (a phone or an Android TV), the way F-Droid's "Tester Review" asks for, and
# write the report to post.
```

- [ ] **Step 8: Run all tests**

Run: `ANDROID_HOME=~/Library/Android/sdk /opt/homebrew/bin/bash tests/run.sh`
Expected: all pass (`7 passed, 0 failed`).

- [ ] **Step 9: Lint**

```bash
/opt/homebrew/bin/bash -n fdroid-tester.sh
git show origin/main:fdroid-tester.sh > /tmp/base.sh
shellcheck -f gcc /tmp/base.sh | sed 's/^[^:]*:[0-9]*:[0-9]*: //' | sort > /tmp/sc-base.txt
shellcheck -f gcc fdroid-tester.sh | sed 's/^[^:]*:[0-9]*:[0-9]*: //' | sort > /tmp/sc-new.txt
comm -13 /tmp/sc-base.txt /tmp/sc-new.txt
```

Expected: `comm` prints nothing (no new warning kinds).

- [ ] **Step 10: Commit (script and tests separately), push, PR, review, merge**

```bash
git add fdroid-tester.sh
git commit -m "#0 Test Android TV apps: open them through their Leanback entry, stop on a device that is not a TV, and say device instead of phone

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git add tests/test_tv.sh
git commit -m "#0 Tests for Android TV apps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin feat/tv-apps
gh pr create --repo johnneerdael/fdroid-tester --base main --head feat/tv-apps \
  --title "Android TV apps" --body "<what changed, validation output, the upstream commit is the first one>

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

Comment `@codex review`; address every finding with a quick targeted check (the affected test file only), push, re-request; merge once the current head has Codex's clean review.

---

### Task 3: Screenshots during the run, embedded when posted (upstream PR 2)

**Files:**
- Modify: `fdroid-tester.sh` (step 4 helpers and run loop; report section; `tool.py` `embed`; step 7 uploads; header comment)
- Create: `tests/test_screenshots.sh`

**Interfaces:**
- Consumes: Task 1 harness; Task 2 wording ("device").
- Produces: `SHOTS` array of `file<TAB>caption`; `$OUT/shots.tsv`; functions `add_shot <file> <caption>`, `take_shot`, `check_alive`, `upload_shot <png>` (prints a gitlab.com path, status 1 when no project took it); helper `tool embed <report.md> <uploads.tsv> <folder>`; report lines ``- `<file>`[ — <caption>]`` under `**Screenshots:**`.

- [ ] **Step 1: Worktree** — `git fetch origin && git worktree add -b feat/screenshots .worktrees/screenshots origin/main`

- [ ] **Step 2: Write the failing tests `tests/test_screenshots.sh`**

```bash
# Screenshots while the tester uses the app, and in the posted report.

test_screenshots_are_taken_and_listed() {
  use_mr phone.apk org.example.phone
  export FAKE_GLAB_OFF=1
  run_tester 's\nthe main screen\ns\n\n\n' -w 1 --keep 123
  assert_rc 0
  [ -s "$(review_dir)/shot-01.png" ] && [ -s "$(review_dir)/shot-02.png" ] || fail "screenshots missing"
  assert_has "$(review_dir)/report.md" '- `after-1s.png` — after 1 seconds'
  assert_has "$(review_dir)/report.md" '- `shot-01.png` — the main screen'
  assert_has "$(review_dir)/report.md" '- `shot-02.png`'
  assert_has "$(review_dir)/shots.tsv" "$(printf 'shot-01.png\tthe main screen')"
}

test_screenshot_numbers_continue_after_an_earlier_run() {
  use_mr phone.apk org.example.phone
  export FAKE_GLAB_OFF=1
  mkdir -p "$(review_dir)" && cp "$FAKE/screen.png" "$(review_dir)/shot-01.png"
  run_tester 's\n\n\n' -w 1 --keep 123
  assert_rc 0
  assert_has "$(review_dir)/report.md" '- `shot-02.png`'
  refute_has "$(review_dir)/report.md" '- `shot-01.png`'
}

test_other_input_during_the_run_is_explained() {
  use_mr phone.apk org.example.phone
  export FAKE_GLAB_OFF=1
  run_tester 'x\n\n' -w 1 --keep 123
  assert_rc 0
  assert_out "s \+ Enter takes a screenshot; Enter alone when you are done"
}

test_crash_after_a_screenshot_is_said_at_once() {
  use_mr phone.apk org.example.phone
  export FAKE_GLAB_OFF=1 FAKE_CRASH_AFTER=2
  run_tester 's\n\n\n' -w 1 --keep 123
  assert_rc 0
  grep -A1 'saved shot-01.png' "$T/out.txt" | grep -q 'it crashed while you used it' \
    || fail "the crash was not said right after the screenshot"
  assert_has "$(review_dir)/report.md" "Crashed (while in use)"
}

test_posted_report_embeds_the_screenshots() {
  use_mr phone.apk org.example.phone
  run_tester 's\nthe main screen\n\n' -w 1 --keep 123
  assert_rc 0
  assert_has "$FAKE/note.md" '- the main screen<br>![the main screen](https://gitlab.com/-/project/555/uploads/abc/shot-01.png){width=480}'
  assert_has "$FAKE/note.md" '- after 1 seconds<br>![after 1 seconds](https://gitlab.com/-/project/555/uploads/abc/after-1s.png){width=480}'
  assert_has "$(review_dir)/report.md" '- `shot-01.png` — the main screen'
}

test_uploads_fall_back_to_fdroiddata() {
  use_mr phone.apk org.example.phone
  export FAKE_UPLOAD_FAIL=555
  run_tester 's\nthe main screen\n\n' -w 1 --keep 123
  assert_rc 0
  assert_has "$FAKE/note.md" '![the main screen](/uploads/def/shot-01.png){width=480}'
}

test_failed_upload_is_said_in_the_post() {
  use_mr phone.apk org.example.phone
  export FAKE_UPLOAD_FAIL="555 fdroid%2Ffdroiddata"
  run_tester 's\nthe main screen\n\n' -w 1 --keep 123
  assert_rc 0
  assert_out "could not upload shot-01.png"
  assert_has "$FAKE/note.md" '- the main screen _(screenshot could not be uploaded)_'
}

test_portrait_screenshots_are_narrower() {
  use_mr phone.apk org.example.phone
  python3 "$HERE/fixtures/png.py" 2 4 > "$FAKE/screen.png"
  run_tester 's\n\n\n' -w 1 --keep 123
  assert_rc 0
  assert_has "$FAKE/note.md" 'shot-01.png){width=240}'
}

test_caption_with_brackets_is_safe_in_alt_text() {
  use_mr phone.apk org.example.phone
  run_tester 's\nmenu [settings] `x`\n\n' -w 1 --keep 123
  assert_rc 0
  assert_has "$FAKE/note.md" '![menu (settings) `x`](https://gitlab.com/-/project/555/uploads/abc/shot-01.png)'
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `ANDROID_HOME=~/Library/Android/sdk /opt/homebrew/bin/bash tests/run.sh screenshot\|upload\|caption\|crash_after\|other_input`
Expected: all nine FAIL (no `s` handling; the run ends at the first empty line).

- [ ] **Step 4: Screenshot helpers** — directly after the line `SHOT=""` that precedes `if [ "$NO_DEVICE" = 0 ]; then` / `step "4. On the device"`, add:

```bash
# Screenshots, the automatic ones and those taken while the app is in use, in
# order as "file<TAB>caption": they go into the report.
SHOTS=()
: > "$OUT/shots.tsv"
add_shot() {  # add_shot <file in the review folder> <caption>
  SHOTS+=("$1"$'\t'"$2")
  printf '%s\t%s\n' "$1" "$2" >> "$OUT/shots.tsv"
}
# check_alive — a crash while the app is in use is said at once, not only at the end
check_alive() {
  [ "$CRASHED" = n ] || return 0
  "${ADB[@]}" logcat -d -b crash 2>/dev/null | grep -q "Process: $APPID" || return 0
  "${ADB[@]}" logcat -d -b crash > "$OUT/crash.log" 2>/dev/null || true
  warn "it crashed while you used it (crash.log saved)"
  CRASHED=later
}
take_shot() {  # take_shot — a screenshot now, with a caption typed by the tester
  local n=1 f cap
  while [ -e "$OUT/$(printf 'shot-%02d.png' "$n")" ]; do n=$((n + 1)); done
  f="$(printf 'shot-%02d.png' "$n")"
  if ! "${ADB[@]}" exec-out screencap -p > "$OUT/$f" 2>/dev/null || [ ! -s "$OUT/$f" ]; then
    rm -f "$OUT/$f"; warn "the screenshot failed"; return 0
  fi
  printf '   %scaption (Enter for none):%s ' "$B" "$R" >&2
  readline cap
  add_shot "$f" "$cap"
  ok "saved $f"
  check_alive
}
```

- [ ] **Step 5: Count the automatic screenshots** — replace

```bash
      "${ADB[@]}" exec-out screencap -p > "$OUT/permission-on-start.png" 2>/dev/null || true
```

with

```bash
      if "${ADB[@]}" exec-out screencap -p > "$OUT/permission-on-start.png" 2>/dev/null; then
        add_shot permission-on-start.png "permission prompt on start"
      fi
```

and replace

```bash
  SHOT="$OUT/after-${WATCH}s.png"
  "${ADB[@]}" exec-out screencap -p > "$SHOT" 2>/dev/null || SHOT=""
```

with

```bash
  SHOT="$OUT/after-${WATCH}s.png"
  if "${ADB[@]}" exec-out screencap -p > "$SHOT" 2>/dev/null; then add_shot "${SHOT##*/}" "after $WATCH seconds"
  else SHOT=""; fi
```

- [ ] **Step 6: The run loop** — replace `  pause "Press Enter when you are done…"` with

```bash
  act "s + Enter: take a screenshot · Enter: done"
  while :; do
    printf '   %s➜%s ' "$BLU" "$R" >&2
    readline line
    case "$line" in
      [sS]) take_shot ;;
      "") break ;;
      *) note "s + Enter takes a screenshot; Enter alone when you are done" ;;
    esac
  done
```

- [ ] **Step 7: Screenshots in the report** — inside the `{ … } > "$REPORT"` block, between the tester-notes `fi` and `printf '<details>\n<summary>Details</summary>\n\n'`, add:

```bash
  if [ "${#SHOTS[@]}" -gt 0 ]; then
    printf '**Screenshots:**\n\n'
    for s in "${SHOTS[@]}"; do
      c="${s#*$'\t'}"
      printf -- '- `%s`%s\n' "${s%%$'\t'*}" "${c:+ — $c}"
    done
    printf '\n'
  fi
```

- [ ] **Step 8: `embed` in the Python helper** — before the line starting `{"mr": cmd_mr,` add:

```python
# --- embed <report.md> <uploads.tsv> <folder>: the report as posted, its
# screenshot lines turned into images (uploads.tsv: file<TAB>path on gitlab.com)
def png_size(path):
    try:
        with open(path, "rb") as f:
            head = f.read(24)
    except OSError:
        return 0, 0
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return 0, 0
    return struct.unpack(">II", head[16:24])

def cmd_embed(report, uploads, folder):
    up = {}
    for line in open(uploads, encoding="utf-8"):
        f, _, path = line.rstrip("\n").partition("\t")
        if f and path:
            up[f] = path
    for line in open(report, encoding="utf-8"):
        m = re.match(r"- `([^`]+\.png)`(?: — (.*))?$", line.rstrip("\n"))
        if not m:
            print(line, end="")
            continue
        f, cap = m.group(1), m.group(2) or ""
        text = cap or f
        if f not in up:
            print(f"- {text} _(screenshot could not be uploaded)_")
            continue
        url = up[f]
        if url.startswith("/-/"):          # uploaded to another project: a full address
            url = "https://gitlab.com" + url
        w, h = png_size(f"{folder}/{f}")
        alt = text.replace("[", "(").replace("]", ")")
        print(f"- {text}<br>![{alt}]({url}){{width={240 if h > w else 480}}}")
```

and add `"embed": cmd_embed,` to the dispatch dict (after `"cats": cmd_cats`).

- [ ] **Step 9: Upload and embed when posting** — just above the line `if [ "$CAN_POST" = 0 ]; then` in step 7, add:

```bash
# upload_shot <png> — uploads it for the comment and prints its path on
# gitlab.com: the merge request's own fork first, then fdroiddata.
upload_shot() {
  local p v
  for p in "$MR_SRC" "${MR_REPO//\//%2F}"; do
    [ -n "$p" ] || continue
    glab api --method POST "projects/$p/uploads" -F "file=@$1" > "$WORK/up.json" 2>/dev/null || continue
    v="$(tool jget "$WORK/up.json" full_path)"
    if [ -z "$v" ] && [ "$p" = "${MR_REPO//\//%2F}" ]; then v="$(tool jget "$WORK/up.json" url)"; fi
    if [ -n "$v" ]; then printf '%s' "$v"; return 0; fi
  done
  return 1
}
```

then replace

```bash
elif confirm "Post the report as a comment on $MR_URL?" y; then
  if glab api --method POST "projects/${MR_REPO//\//%2F}/merge_requests/$IID/notes" \
       -F "body=@$REPORT" > "$WORK/note.json" 2>&1; then
```

with

```bash
elif confirm "Post the report as a comment on $MR_URL?" y; then
  BODY="$REPORT"
  if [ "${#SHOTS[@]}" -gt 0 ]; then
    say "uploading the screenshots…"
    : > "$WORK/uploads.tsv"
    for s in "${SHOTS[@]}"; do
      f="${s%%$'\t'*}"
      if up="$(upload_shot "$OUT/$f")"; then printf '%s\t%s\n' "$f" "$up" >> "$WORK/uploads.tsv"
      else warn "could not upload $f — the comment says so in its place"; fi
    done
    tool embed "$REPORT" "$WORK/uploads.tsv" "$OUT" > "$WORK/post.md"
    BODY="$WORK/post.md"
  fi
  if glab api --method POST "projects/${MR_REPO//\//%2F}/merge_requests/$IID/notes" \
       -F "body=@$BODY" > "$WORK/note.json" 2>&1; then
```

- [ ] **Step 10: Header comment** — in the numbered list at the top, after item 4's lines, add:

```bash
#      while you use it, s + Enter takes a screenshot; they all go into the
#      report, as images when it is posted
```

- [ ] **Step 11: Run all tests; lint** — `tests/run.sh` (expected: all pass, `16 passed, 0 failed`), then `bash -n` and the shellcheck comparison from Task 2 step 9.

- [ ] **Step 12: Commit (script, then tests), push, PR, Codex review, merge** — as Task 2 step 10, subject `#0 Take screenshots while using the app with s + Enter, and embed them when the report is posted`.

---

### Task 4: Root capture with PCAPdroid (upstream PR 3)

**Files:**
- Modify: `fdroid-tester.sh` (options and usage; checks in the `device)` case; capture start in step 4; report Details)
- Create: `tests/test_root.sh`

**Interfaces:**
- Consumes: Task 1 harness.
- Produces: `FORCE_VPN` (0/1, option `--vpn`), `ROOT` (0/1), `CAP_MODE` (`root`|`VPN`).

- [ ] **Step 1: Worktree** — `git fetch origin && git worktree add -b feat/root-capture .worktrees/root-capture origin/main`

- [ ] **Step 2: Write the failing tests `tests/test_root.sh`**

```bash
# PCAPdroid root mode on rooted devices; --vpn keeps the VPN.

test_rooted_device_records_in_root_mode() {
  use_mr net.apk org.example.net
  touch "$FAKE/root"
  python3 "$HERE/fixtures/pcap.py" example.org 101 > "$FAKE/traffic.pcap"
  export FAKE_GLAB_OFF=1
  run_tester "" -w 1 --keep 123
  assert_rc 0
  assert_out "root +yes — PCAPdroid records in root mode, no VPN prompt"
  assert_has "$FAKE/calls.log" "-e root_capture true"
  refute_has "$FAKE/calls.log" "block_quic"
  assert_has "$(review_dir)/report.md" "Connections (PCAPdroid, root mode)"
  assert_has "$(review_dir)/report.md" "example.org"
}

test_vpn_option_keeps_vpn_mode_on_a_rooted_device() {
  use_mr net.apk org.example.net
  touch "$FAKE/root"
  python3 "$HERE/fixtures/pcap.py" example.org 101 > "$FAKE/traffic.pcap"
  export FAKE_GLAB_OFF=1
  run_tester "" -w 1 --keep --vpn 123
  assert_rc 0
  assert_out "root +not used \(--vpn\)"
  assert_has "$FAKE/calls.log" "-e block_quic always"
  refute_has "$FAKE/calls.log" "root_capture"
  assert_has "$(review_dir)/report.md" "Connections (PCAPdroid, VPN mode)"
}

test_device_without_root_uses_the_vpn() {
  use_mr net.apk org.example.net
  python3 "$HERE/fixtures/pcap.py" example.org 101 > "$FAKE/traffic.pcap"
  export FAKE_GLAB_OFF=1
  run_tester "" -w 1 --keep 123
  assert_rc 0
  assert_out "root +no — PCAPdroid records through its VPN"
  assert_has "$FAKE/calls.log" "-e block_quic always"
  refute_has "$FAKE/calls.log" "root_capture"
}

test_help_lists_the_vpn_option() {
  run_tester "" --help
  assert_rc 0
  assert_out "--vpn"
}
```

- [ ] **Step 3: Run them to see them fail** — `tests/run.sh root\|vpn` → four FAIL (`--vpn` is an unknown option, no root row).

- [ ] **Step 4: Option** — change `SERIAL=""; WATCH=15; NO_DEVICE=0; KEEP=0; MR_ARG=""; CHECK_ONLY=0` to add `; FORCE_VPN=0`; in the option `case` add before `--check)`:

```bash
    --vpn) FORCE_VPN=1 ;;
```

and in `usage()` after the `--keep` lines add:

```
  --vpn          record with PCAPdroid's VPN even when the device has root
                 (with root, it records in root mode: no VPN prompt)
```

- [ ] **Step 5: Root check** — add `ROOT=0` to the line `DEV_ABIS=""; DEV_SDK=""; …`; in the `device)` case, right after the PCAPdroid `if … fi` (the one ending with `else row ok PCAPdroid "$PCAP_VER — it asks …"; fi` / `fi`), add:

```bash
      # With root, PCAPdroid records without its VPN: nothing to confirm on
      # the device but its root access, once.
      if [ "$FORCE_VPN" = 1 ]; then
        row info root "not used (--vpn)"
      elif ash su -c id | grep -q '^uid=0'; then
        ROOT=1; row ok root "yes — PCAPdroid records in root mode, no VPN prompt"
      else
        row info root "no — PCAPdroid records through its VPN"
      fi
```

- [ ] **Step 6: Start the capture in root mode** — replace

```bash
      ash am start -n "$PCAP_PKG/.activities.CaptureCtrl" -e action start \
        -e pcap_dump_mode pcap_file -e pcap_name "$PCAP_NAME" -e app_filter "$APPID" \
        -e block_quic always -e auto_block_private_dns true "${KEY[@]}" >/dev/null
      if [ "${#KEY[@]}" -eq 0 ]; then
        act "on the device: allow PCAPdroid's control prompt (and the VPN prompt, the first time)"
```

with

```bash
      # The VPN-only settings do not apply in root mode.
      MODE=(-e block_quic always -e auto_block_private_dns true); FIRST="the VPN prompt"
      if [ "$ROOT" = 1 ]; then MODE=(-e root_capture true); FIRST="its root access prompt"; fi
      ash am start -n "$PCAP_PKG/.activities.CaptureCtrl" -e action start \
        -e pcap_dump_mode pcap_file -e pcap_name "$PCAP_NAME" -e app_filter "$APPID" \
        "${MODE[@]}" "${KEY[@]}" >/dev/null
      if [ "${#KEY[@]}" -eq 0 ]; then
        act "on the device: allow PCAPdroid's control prompt (and $FIRST, the first time)"
```

and directly after that `if` block's `note "tip: …"` line and its `fi`, add:

```bash
      if [ "${#KEY[@]}" -gt 0 ] && [ "$ROOT" = 1 ]; then
        act "on the device: allow PCAPdroid's root access prompt, the first time"
      fi
```

- [ ] **Step 7: Say the mode in the report** — add `CAP_MODE=VPN; [ "$ROOT" = 1 ] && CAP_MODE=root` on its own line just before `REPORT="$OUT/report.md"`, then replace

```bash
    printf -- '- Connections (PCAPdroid), first %ss after launch:' "$WATCH"
```

with

```bash
    printf -- '- Connections (PCAPdroid, %s mode), first %ss after launch:' "$CAP_MODE" "$WATCH"
```

and after the `printf -- '- Connections while in use:'` line's following `if … fi`, add:

```bash
    if [ "$ROOT" = 1 ]; then
      printf -- '- In root mode the app'\''s DNS lookups are made by the system, so connections are named from TLS and HTTP only; the others show as address:port.\n'
    fi
```

- [ ] **Step 8: Run all tests; lint** — all pass; `bash -n`; shellcheck comparison.

- [ ] **Step 9: Commit (script, then tests), push, PR, Codex review, merge** — subject `#0 Record in PCAPdroid's root mode on a rooted device, with --vpn to keep the VPN`.

---

### Task 5: Local APK (upstream PR 4)

**Files:**
- Modify: `fdroid-tester.sh` (options, usage, no-argument help; step 1; step 2; categories question; step 7)
- Create: `tests/test_local_apk.sh`

**Interfaces:**
- Consumes: Task 1 harness; `MR_SRC`, `IID` (empty without a merge request) as used by Task 3's `upload_shot`.
- Produces: option `--apk FILE` → `APK_ARG`.

- [ ] **Step 1: Worktree** — `git fetch origin && git worktree add -b feat/local-apk .worktrees/local-apk origin/main`

- [ ] **Step 2: Write the failing tests `tests/test_local_apk.sh`**

```bash
# A local APK, with or without its merge request.

test_local_apk_without_a_merge_request() {
  run_tester "" -w 1 --keep --apk "$APKS/phone.apk"
  assert_rc 0
  assert_out "none — testing phone.apk on its own"
  refute_has "$FAKE/curl.log" "merge_requests"
  assert_has "$(review_dir)/report.md" 'Tested `org.example.phone` 1.2.3 (7)'
  assert_has "$(review_dir)/report.md" "The Categories field is set properly. _(not checked)_"
  refute_out "Post to"
  refute_has "$FAKE/glab.log" "/notes"
}

test_local_apk_with_its_merge_request_skips_the_download() {
  use_mr phone.apk org.example.phone
  cp "$APKS/phone.apk" "$T/org.example.phone_7.apk"
  export FAKE_GLAB_OFF=1
  run_tester "" -w 1 --keep --apk "$T/org.example.phone_7.apk" 123
  assert_rc 0
  refute_has "$FAKE/curl.log" ".apk"
  refute_out "not one this merge request's CI built"
}

test_local_apk_the_merge_request_did_not_build_is_flagged() {
  use_mr phone.apk org.example.phone
  export FAKE_GLAB_OFF=1 FAKE_APPID=org.example.net
  run_tester "" -w 1 --keep --apk "$APKS/net.apk" 123
  assert_rc 0
  assert_out "org.example.net_7.apk is not one this merge request's CI built"
}

test_missing_local_apk_is_refused() {
  run_tester "" --apk "$T/nope.apk"
  assert_rc 2
  assert_out "no such APK: "
}

test_help_lists_the_apk_option() {
  run_tester "" --help
  assert_rc 0
  assert_out "--apk FILE"
}
```

- [ ] **Step 3: Run them to see them fail** — `tests/run.sh local_apk\|apk_option` → five FAIL.

- [ ] **Step 4: Option, usage, help** — add `; APK_ARG=""` to the variables line; in the option `case` before `--check)`:

```bash
    --apk) APK_ARG="${2-}"; shift
           [ -s "$APK_ARG" ] || { printf 'no such APK: %s\n' "$APK_ARG" >&2; exit 2; } ;;
```

In `usage()` change the first line pair to

```
usage: fdroid-tester.sh <merge request link or number> [options]
       fdroid-tester.sh --apk FILE [merge request link or number] [options]
       fdroid-tester.sh --check [-s SERIAL]
```

and add after the `--keep` lines

```
  --apk FILE     test this APK instead of downloading the merge request's;
                 without a merge request, nothing is read from or posted to
                 gitlab.com
```

Change `if [ -z "$MR_ARG" ] && [ "$CHECK_ONLY" = 0 ]; then` (the "Which app do you want to test?" help) to `if [ -z "$MR_ARG" ] && [ -z "$APK_ARG" ] && [ "$CHECK_ONLY" = 0 ]; then`.

- [ ] **Step 5: Step 1 without a merge request** — directly after `step "1. Merge request"` insert

```bash
IID=""; MR_URL=""; MR_SRC=""; MR_SHA=""; APK_URLS=(); CI_PERMS=(); CI_WARN=(); SUMMARY=""
if [ -z "$MR_ARG" ]; then
  note "none — testing ${APK_ARG##*/} on its own"
else
```

indent nothing else; delete the later line `APK_URLS=(); CI_PERMS=(); CI_WARN=(); SUMMARY=""`; replace

```bash
[ "${#APK_URLS[@]}" -gt 0 ] || die "the report has no APK — the 'fdroid build' job failed or has not run; nothing to test yet"
ok "${#APK_URLS[@]} APK(s) in the report"
```

with

```bash
if [ "${#APK_URLS[@]}" -gt 0 ]; then ok "${#APK_URLS[@]} APK(s) in the report"
elif [ -z "$APK_ARG" ]; then die "the report has no APK — the 'fdroid build' job failed or has not run; nothing to test yet"
fi
fi
```

(the final `fi` closes the `if [ -z "$MR_ARG" ]`).

- [ ] **Step 6: Step 2 with a local file** — replace `APK=""; BEST=999; APK_ABIS=""` and the download `for` loop through `[ -n "$APK" ] || die "none of the APKs runs on this device ($DEV_ABIS)"` with

```bash
APK=""; BEST=999; APK_ABIS=""
if [ -n "$APK_ARG" ]; then
  APK="$(cd "$(dirname "$APK_ARG")" && pwd)/$(basename "$APK_ARG")"
  APK_ABIS="$(apk_abis "$APK")"
  note "  native code: ${APK_ABIS:-none}"
  [ -n "$(rank "$APK_ABIS")" ] || die "${APK##*/} does not run on this device ($DEV_ABIS)"
else
  # (the existing download loop, unchanged)
  for url in "${APK_URLS[@]}"; do
    …
  done
  [ -n "$APK" ] || die "none of the APKs runs on this device ($DEV_ABIS)"
fi
```

keeping the loop body exactly as it is. After the `OUT=…` / `mkdir -p "$OUT"` lines replace `cp "$WORK/cq.json" "$OUT/codequality.json"` with

```bash
[ -n "$MR_ARG" ] && cp "$WORK/cq.json" "$OUT/codequality.json"
if [ -n "$APK_ARG" ] && [ "${#APK_URLS[@]}" -gt 0 ] \
   && ! printf '%s\n' "${APK_URLS[@]##*/}" | grep -qxF "${APPID}_${VCODE}.apk"; then
  warn "${APPID}_${VCODE}.apk is not one this merge request's CI built — testing it anyway"
fi
```

- [ ] **Step 7: Categories without metadata** — replace

```bash
if [ -n "$CATS" ]; then yns Q_CATS "Do the categories fit ($CATS)?" y
```

with

```bash
if [ -z "$MR_ARG" ]; then yns Q_CATS "Do the app's categories fit? (no merge request, so no metadata to read)" s
elif [ -n "$CATS" ]; then yns Q_CATS "Do the categories fit ($CATS)?" y
```

- [ ] **Step 8: No posting without a merge request** — wrap step 7: replace `step "7. Post to !$IID"` with

```bash
if [ -z "$IID" ]; then
  note "no merge request — the report stays in ${REPORT#"$PWD"/}"
else
step "7. Post to !$IID"
```

and put `fi` directly before the final `if [ "$NO_DEVICE" = 0 ] && [ "$KEEP" = 0 ]; then` (the "Remove the app" question stays outside).

- [ ] **Step 9: Run all tests; lint** — all pass; `bash -n`; shellcheck comparison.

- [ ] **Step 10: Commit (script, then tests), push, PR, Codex review, merge** — subject `#0 Test a local APK with --apk, with or without its merge request`.

---

### Task 6: Fork `main` check and README note

**Files:**
- Modify: `README.md` (fork only)

- [ ] **Step 1: Full run on the fork's main** — `git -C ~/Scripts/fdroid-tester pull` then `ANDROID_HOME=~/Library/Android/sdk /opt/homebrew/bin/bash tests/run.sh` → all pass (`25 passed, 0 failed`).

- [ ] **Step 2: README** (branch `feat/fork-readme`, PR, merge) — append:

```markdown

### This fork

Adds screenshots while you use the app (`s` + Enter, embedded when the report
is posted), Android TV apps, PCAPdroid's root mode on rooted devices (`--vpn`
keeps the VPN) and `--apk FILE` for a local APK. Each is offered upstream as
its own pull request. `tests/run.sh` runs the script against fixture APKs and a
fake device (needs bash 4.4+, Python 3 and Android build-tools).
```

---

### Task 7: Device validation on the AM9 (blocked until it authorises this computer)

**Files:** none; results recorded in the PRs and reported to the owner.

- [ ] **Step 1: Check the device** — `adb devices -l | grep 192.168.51.53` must show `device`. If it shows `unauthorized`, stop and ask the owner to accept the prompt on the TV. Then `D=192.168.51.53:5555; adb -s $D shell am get-current-user` and `adb -s $D shell pm list features | grep leanback`.

- [ ] **Step 2: Checks and PCAPdroid install** — `~/Scripts/fdroid-tester/fdroid-tester.sh --check -s 192.168.51.53:5555`; accept the script's offer to install PCAPdroid from GitHub. Expected: `✓ PCAPdroid …`, a `root` row.

- [ ] **Step 3: First `su -c id`** — note whether Magisk shows a prompt for the shell, how long `--check` waits, and what happens if it is denied (Review Focus 3). If it can hang longer than about 15 seconds, open a review-fix on Task 4's branch that runs the check in the background with a timeout.

- [ ] **Step 4: Root-mode run with ProjectM TV** — in a scratch folder: `fdroid-tester.sh -s 192.168.51.53:5555 --keep https://gitlab.com/fdroid/fdroiddata/-/merge_requests/50236`. Start music in another app first; take two screenshots with captions; open Settings › collection download if available. Do not post (answer n). Then check `traffic.pcap`'s link type: `python3 -c "import struct;print(struct.unpack('<I',open('traffic.pcap','rb').read()[20:24])[0])"`. Expected 101 (raw IP) or a type the parser reads. If it is 276 (Linux SLL2), add to `cmd_pcap` before `if not pkt:`: `elif link == 276: pkt = pkt[20:]`, with a harness test using `pcap.py … 276` after prefixing 20 bytes in the fixture. Confirm the report names HTTPS hosts (Review Focus 1).

- [ ] **Step 5: VPN-mode run with ProjectM Android** — `fdroid-tester.sh -s 192.168.51.53:5555 --vpn --keep https://gitlab.com/fdroid/fdroiddata/-/merge_requests/52248`; record whether the phone app installs and opens on the box.

- [ ] **Step 6: Uploads and rendering** (Review Focus 2 and 4) — upload one 4K screenshot from step 4 to our own fdroiddata fork (project 86928125): `glab api --method POST projects/86928125/uploads -F file=@shot-01.png`; note whether `full_path` is present. Render: `glab api --method POST markdown -f text='![x](https://gitlab.com<full_path>){width=480}' -f gfm=true -f project=fdroid/fdroiddata` and check the HTML has an `<img` with that address. Also try the same upload against `fdroid%2Ffdroiddata` to learn whether a non-member may upload there; do not post any note.

- [ ] **Step 7: Report** — summarise each run (mode, prompts, link type, named hosts, upload result) to the owner. Nothing is posted to !50236 or !52248 unless the owner says so; an author self-test note, if wanted, says plainly that the author ran it.

---

### Task 8: Upstream PRs (opened only after the owner has seen them)

**Files:** none new; branches on the fork.

- [ ] **Step 1: Branches** — for each feature in order TV apps, screenshots, root capture, local APK:

```bash
cd ~/Scripts/fdroid-tester && git fetch upstream origin
git worktree add -b upstream/tv-apps .worktrees/up-tv-apps upstream/main
cd .worktrees/up-tv-apps && git cherry-pick <script commit of feat/tv-apps>
```

the next one based on the previous (`upstream/screenshots` from `upstream/tv-apps`, and so on). Resolve conflicts by keeping upstream lines plus the feature's change only; `bash -n` and the fork harness against each branch's script: `~/Scripts/fdroid-tester/tests/run.sh --script fdroid-tester.sh` (the tests of later features are expected to fail on earlier branches; the baseline tests and that feature's own tests must pass).

- [ ] **Step 2: Drafts** — write each PR's title and body (what changed for testers, how it was tested, the stacked order) and show them to the owner with the branch links.

- [ ] **Step 3: Open** — only after the owner says yes: `gh pr create --repo by-architect/fdroid-tester --base main --head johnneerdael:upstream/tv-apps …`, one at a time; later ones say they build on the previous PR.
