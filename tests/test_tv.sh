# Android TV apps: Leanback launch, TV requirement, "device" wording.

test_tv_app_opens_through_its_leanback_activity() {
  use_mr tv.apk org.example.tv
  printf 'feature:android.software.leanback\n' > "$FAKE/features"
  export FAKE_NO_LAUNCHER=1 FAKE_GLAB_OFF=1
  run_tester "" -w 1 --keep 123
  assert_rc 0
  assert_has "$FAKE/calls.log" "shell am start -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER -n org.example.tv/org.example.tv.Main"
  refute_has "$FAKE/calls.log" "monkey"
  refute_out "open it by hand"
}

# Some Android TV boxes (e.g. Ugoos AM9 Pro, Android 14) do not declare the
# Leanback feature, yet run TV apps installed with adb.
test_tv_app_on_a_device_without_leanback_warns_and_continues() {
  use_mr tv.apk org.example.tv
  export FAKE_NO_LAUNCHER=1 FAKE_GLAB_OFF=1
  run_tester "" -w 1 --keep 123
  assert_rc 0
  assert_out "this app requires Android TV, and this device does not declare it"
  assert_has "$FAKE/calls.log" "install -r"
  assert_has "$(review_dir)/report.md" "The device does not declare Android TV (android.software.leanback)"
}

test_tv_app_on_a_device_without_leanback_can_be_stopped() {
  use_mr tv.apk org.example.tv
  run_tester "n\n" -w 1 --keep 123
  assert_rc 1
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
