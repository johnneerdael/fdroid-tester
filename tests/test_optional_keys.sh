# Empty files created while setting up keys must behave like absent keys.
test_empty_optional_key_files_are_treated_as_unconfigured() {
  use_mr net.apk org.example.net
  mkdir -p "$T/home/config/fdroid-tester"
  : > "$T/home/config/fdroid-tester/virustotal-api-key"
  : > "$T/home/config/fdroid-tester/pcapdroid-api-key"
  python3 "$HERE/fixtures/pcap.py" example.org 101 > "$FAKE/traffic.pcap"
  export FAKE_GLAB_OFF=1
  run_tester '' -w 1 --keep 123
  assert_rc 0
  assert_has "$(review_dir)/report.md" 'example.org'
  refute_has "$FAKE/calls.log" '-e api_key'
}
