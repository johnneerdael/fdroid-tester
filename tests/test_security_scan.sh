# API results must make it into the actual report, not just a terminal message.
test_known_virustotal_result_is_saved_in_report() {
  mkdir -p "$T/home/config/fdroid-tester"
  echo test-key > "$T/home/config/fdroid-tester/virustotal-api-key"
  printf '{"data":{"attributes":{"last_analysis_stats":{"malicious":0,"suspicious":0,"undetected":12,"harmless":2}}}}' > "$FAKE/vt-file.json"
  run_tester '' -w 1 --keep --apk "$APKS/phone.apk"
  assert_rc 0
  assert_has "$(review_dir)/report.md" '0 malicious, 0 suspicious, 14 clean'
  assert_has "$(review_dir)/report.md" '- [x] All or most vendors on VirusTotal'
  refute_has "$FAKE/curl.log" 'file=@'
}

# Allow enough real startup time for the 20-second background scan poll. A
# queued scan or upload-only implementation cannot satisfy these expectations.
test_confirmed_virustotal_upload_collects_completed_background_result() {
  mkdir -p "$T/home/config/fdroid-tester"
  echo test-key > "$T/home/config/fdroid-tester/virustotal-api-key"
  printf '{"data":{"id":"fixture-analysis"}}' > "$FAKE/vt-upload.json"
  printf '{"data":{"attributes":{"status":"completed","stats":{"malicious":0,"suspicious":0,"undetected":9,"harmless":1}}}}' > "$FAKE/vt-analysis.json"
  run_tester 'y\n' -w 22 --keep --apk "$APKS/phone.apk"
  assert_rc 0
  assert_has "$(review_dir)/report.md" '0 malicious, 0 suspicious, 10 clean'
  assert_has "$(review_dir)/report.md" '- [x] All or most vendors on VirusTotal'
}
