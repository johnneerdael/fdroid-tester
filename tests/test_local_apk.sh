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
  assert_has "$(review_dir)/report.md" "Tested a local APK, not one downloaded from this merge request's CI."
}

test_local_apk_the_merge_request_did_not_build_is_flagged() {
  use_mr phone.apk org.example.phone
  export FAKE_GLAB_OFF=1 FAKE_APPID=org.example.net
  run_tester "" -w 1 --keep --apk "$APKS/net.apk" 123
  assert_rc 0
  assert_out "org.example.net_7.apk is not one this merge request's CI built"
  assert_has "$(review_dir)/report.md" 'It is not one of the APKs this merge request'"'"'s CI built (`org.example.net_7.apk`).'
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

test_local_apk_without_a_merge_request_needs_no_gitlab() {
  export FAKE_GITLAB_DOWN=1
  run_tester "" -w 1 --keep --apk "$APKS/phone.apk"
  assert_rc 0
  refute_has "$FAKE/glab.log" "api user"
  refute_has "$FAKE/curl.log" "gitlab.com"
}

test_local_apk_without_a_merge_request_offers_the_editor() {
  run_tester "" -w 1 --keep --apk "$APKS/phone.apk"
  assert_rc 0
  assert_out "Edit the report\\? "
}

test_local_apk_for_a_merge_request_whose_ci_built_nothing_is_flagged() {
  use_mr phone.apk org.example.phone
  printf '{"new_errors": []}' > "$FAKE/cq.json"
  export FAKE_GLAB_OFF=1
  run_tester "" -w 1 --keep --apk "$APKS/phone.apk" 123
  assert_rc 0
  assert_has "$(review_dir)/report.md" 'It is not one of the APKs this merge request'"'"'s CI built (`org.example.phone_7.apk`).'
}
