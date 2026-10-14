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
  local runner=("$BASH" "$SCRIPT")
  if [ "$TEST_POWERSHELL" = 1 ]; then
    runner=("$PWSH_BIN" -NoProfile -File "$SCRIPT")
  fi
  RC=0
  ( cd "$T/work" && { printf '%b' "$answers"; yes '' | head -80; } \
      | PATH="$HERE/stubs:$BASH_DIR:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$T/home" \
        XDG_CACHE_HOME="$T/home/cache" XDG_CONFIG_HOME="$T/home/config" \
        EDITOR=true VISUAL=true "${runner[@]}" "$@" ) > "$T/out.txt" 2>&1 || RC=$?
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
