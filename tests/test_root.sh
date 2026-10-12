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
