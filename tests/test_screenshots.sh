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
  assert_has "$FAKE/note.md" '- the main screen<br>![the main screen](/uploads/def/shot-01.png){width=480}'
  assert_has "$FAKE/note.md" '- after 1 seconds<br>![after 1 seconds](/uploads/def/after-1s.png){width=480}'
  assert_has "$(review_dir)/report.md" '- `shot-01.png` — the main screen'
}

test_uploads_fall_back_to_the_merge_requests_fork() {
  use_mr phone.apk org.example.phone
  export FAKE_UPLOAD_FAIL=fdroid%2Ffdroiddata
  run_tester 's\nthe main screen\n\n' -w 1 --keep 123
  assert_rc 0
  assert_has "$FAKE/note.md" '![the main screen](https://gitlab.com/-/project/555/uploads/abc/shot-01.png){width=480}'
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
  assert_has "$FAKE/note.md" "- menu [settings] \\\`x\\\`<br>![menu (settings) 'x'](/uploads/def/shot-01.png)"
}

test_caption_with_one_backtick_or_backslash_keeps_the_image() {
  use_mr phone.apk org.example.phone
  run_tester 's\nthe `Settings menu\\\n\n' -w 1 --keep 123
  assert_rc 0
  assert_has "$FAKE/note.md" "- the \\\`Settings menu\\\\<br>![the 'Settings menu/](/uploads/def/shot-01.png)"
}

# answers: Enter ends the run, nine questions take their default, then the notes
test_tester_notes_that_look_like_screenshots_are_left_alone() {
  use_mr phone.apk org.example.phone
  run_tester '\n\n\n\n\n\n\n\n\n\n- `config.png` — the icon is too big\n\n' -w 1 --keep 123
  assert_rc 0
  assert_has "$FAKE/note.md" '- `config.png` — the icon is too big'
}

test_notes_that_are_not_utf8_do_not_stop_the_post() {
  use_mr phone.apk org.example.phone
  run_tester '\n\n\n\n\n\n\n\n\n\ncaf\xe9\n\n' -w 1 --keep 123
  assert_rc 0
  assert_has "$FAKE/note.md" 'Tested `org.example.phone`'
}

test_glab_without_form_says_so_and_lists_the_screenshots() {
  use_mr phone.apk org.example.phone
  export FAKE_GLAB_OLD=1
  run_tester 's\nthe main screen\n\n' -w 1 --keep 123
  assert_rc 0
  assert_out "glab is too old to upload screenshots"
  assert_has "$FAKE/note.md" '- the main screen _(screenshot could not be uploaded)_'
}

test_app_that_stops_without_a_crash_is_noticed() {
  use_mr phone.apk org.example.phone
  export FAKE_GLAB_OFF=1 FAKE_GONE_AFTER=2
  run_tester 's\n\n\n' -w 1 --keep 123
  assert_rc 0
  grep -A1 'saved shot-01.png' "$T/out.txt" | grep -q 'not running any more' \
    || fail "the stopped app was not said right after the screenshot"
  assert_has "$(review_dir)/report.md" '- [ ] The app can start and work normally.'
  assert_has "$(review_dir)/report.md" 'The app was not running any more when the test ended'
}
