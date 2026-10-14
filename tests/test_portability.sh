# A text-decoding screenshot path would corrupt this PNG; compare actual bytes.
test_screenshot_preserves_binary_bytes() {
  use_mr phone.apk org.example.phone
  export FAKE_GLAB_OFF=1
  run_tester 's\nproof\n\n' -w 1 --keep 123
  assert_rc 0
  cmp "$FAKE/screen.png" "$(review_dir)/shot-01.png" || fail "screenshot bytes changed"
}

# Splitting a native argument on whitespace would inspect/install the wrong file.
test_local_apk_path_with_spaces_is_one_argument() {
  mkdir -p "$T/APK files"
  cp "$APKS/phone.apk" "$T/APK files/application build.apk"
  run_tester '' -w 1 --keep --apk "$T/APK files/application build.apk"
  assert_rc 0
  assert_has "$(review_dir)/report.md" 'APK: `application build.apk`'
  assert_has "$(review_dir)/report.md" "$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$APKS/phone.apk")"
}

# A no-device inspection must preserve the tester's explicit unknown answers.
test_no_device_review_keeps_unverified_answers_unknown() {
  run_tester 's\ns\ns\ns\ns\ns\ns\ns\ns\n' --no-device --apk "$APKS/phone.apk"
  assert_rc 0
  assert_has "$(review_dir)/report.md" 'The app can start and work normally. _(not checked)_'
  assert_has "$(review_dir)/report.md" 'The functions in the description are implemented. _(not checked)_'
  [ ! -e "$(review_dir)/after-15s.png" ] || fail "no-device run took a screenshot"
}
