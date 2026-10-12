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
