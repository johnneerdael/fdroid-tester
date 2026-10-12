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
