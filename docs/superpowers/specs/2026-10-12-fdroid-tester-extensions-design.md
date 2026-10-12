# fdroid-tester extensions: screenshots, TV apps, root capture, local APK

Date: 2026-10-12. Status: design approved in conversation; this spec awaits review.

## Purpose

`fdroid-tester.sh` (by-architect, GPL-3.0) already does most of an F-Droid
"Tester Review": it reads an fdroiddata merge request and its Code Quality
report, downloads the CI-built APK, inspects it (permissions, Exodus trackers,
addresses, WebView, languages, flags), installs it, records the app's traffic
with PCAPdroid, watches the first seconds for a crash or permission prompt,
asks only what a person must judge, writes the wiki's report template and
offers to post it with `glab`.

We want it to support a tester who navigates the app by hand and wants to
capture evidence while doing so, on Android TV devices as well as phones, on a
rooted box without a VPN prompt, and for a local APK.

Intended use: first an author self-test of our own MRs (fdroiddata !50236
ProjectM TV, !52248 ProjectM Android), clearly labelled as such; then tester
reports for other apps in the `review-requested` queue.

## Decisions

- Extend fdroid-tester; no new tool and no graphical UI. The interactive
  terminal run, with a screenshot key, is the UI.
- Keep upstream's style: one bash script, the embedded Python helper, plain
  English messages, no new dependencies, commit subjects `#0 <sentence>`.
- Fork `johnneerdael/fdroid-tester`. Each feature is a branch from
  `upstream/main` and becomes its own upstream PR, opened only after the owner
  has seen it. The fork's `main` merges all features and is what we run.
- This spec and the implementation plan live only on the fork's `main`
  (`docs/superpowers/`), never in an upstream PR branch.
- Network capture on rooted devices uses PCAPdroid's root mode
  (`root_capture=true`); no `tcpdump` binary, no iptables rules.
- Screenshots are embedded in the posted report.

## Out of scope

Graphical UI, real `tcpdump`/NFLOG capture, VirusTotal changes beyond the
existing behaviour, changes to the report's questions other than those listed
below, automatic posting without confirmation.

## Feature 1: screenshots during the run (upstream PR 1)

Current behaviour: step 4 prints what to try and waits for Enter.

New behaviour:

- The prompt reads `s + Enter: take a screenshot · Enter: done`. Input stays
  line-based through the existing `readline` helper, so piped/non-TTY use is
  unchanged.
- `s` saves `shot-NN.png` (two digits, counting from 01) in the review folder
  via `adb exec-out screencap -p`, then asks for an optional one-line caption
  (Enter skips). Captions are kept in `shots.tsv` (`file<TAB>caption`).
- After each shot the script checks `pidof` and the crash buffer; a crash is
  reported immediately and recorded as today (`CRASHED=later`, `crash.log`).
- The existing automatic shots (`permission-on-start.png`, `after-<N>s.png`)
  join the list with fixed captions ("permission prompt on start", "after N
  seconds").
- Report: a `**Screenshots:**` section after the tester notes and before
  `<details>`. Unposted reports list the file names with captions.
- Posting: before the note is created, each image is uploaded with
  `glab api --method POST projects/<MR source project>/uploads -F file=@…`,
  or to the target project if that is refused, and the report's
  screenshot section is rewritten with the returned Markdown and caption.
  A failed upload leaves that image out with a line saying so; the note is
  still posted. The local `report.md` keeps file names.

Risk to verify: which project the uploads API accepts for a non-member
(fdroiddata vs the MR's source fork). The fallback order above covers both.

## Feature 2: Android TV apps (upstream PR 2)

- Launch: read `launchable-activity` and `leanback-launchable-activity` from
  `aapt2 dump badging`. With a normal launcher activity, keep today's
  `monkey` launch. With only a Leanback one, start it with
  `am start -n <appid>/<activity>`. With neither, keep today's "open it by
  hand" warning.
- Requirement check: if the APK has a required `uses-feature`
  `android.software.leanback` and the device does not list that feature
  (`pm list features`), stop before installing: "this app needs Android TV;
  the device is not one".
- Wording: "phone" becomes "device" in messages, comments and the report
  sentence ("Tested … on <device>"). Variable names are left alone.

## Feature 3: root capture (upstream PR 3)

- Checks: when a device is connected and PCAPdroid is usable, run
  `su -c id`; uid 0 means root. Row: `root: yes — PCAPdroid records in root
  mode, no VPN prompt`. Option `--vpn` forces VPN mode.
- Start: add `-e root_capture true` and omit the VPN-only extras
  (`block_quic`, `auto_block_private_dns`). Message on first use: accept
  PCAPdroid's root access prompt on the device.
- Parsing: confirm the link type PCAPdroid writes in root mode and extend
  `cmd_pcap` if it is not one the parser handles (Ethernet 1, Linux SLL 113,
  raw IP by default).
- Host names: in root mode the system resolver performs DNS on the app's
  behalf, so DNS packets are not in an app-filtered capture. Names then come
  from TLS SNI and HTTP `Host`; other flows show as `IP:port`. The report's
  Details line says which mode recorded the traffic. Only if a device run shows
  too many bare addresses: capture unfiltered with `dump_extensions`, keep all
  DNS answers for the name map, and keep only flows whose trailer UID is the
  app's. That fallback is a separate decision, not part of this PR by default.

## Feature 4: local APK (upstream PR 4)

- `--apk FILE` accepts a local APK.
- With an MR: steps 1 and the Code Quality read run as today; the APK is
  taken from FILE instead of downloaded. If FILE's app ID and version code
  match none of the report's APK file names (`<appid>_<code>.apk`), warn and
  continue.
- Without an MR: steps 1 and the Code Quality read are skipped; there are no
  CI warnings, permissions come from the APK, the categories question is asked
  without metadata, and step 7 (posting) is skipped; the report is saved.
- The ABI check against the device still applies to FILE.

## Validation

- Every change: `bash -n fdroid-tester.sh`; `shellcheck` when installed,
  without introducing new warnings relative to upstream; `--check` and
  `--help` runs.
- Device: AM9 at `192.168.51.53:5555` (Android 14, rooted), explicitly
  selected with `-s`. Other connected devices belong to other tasks and are
  not touched. PCAPdroid is installed through the script's own GitHub install
  path on first use.
- Runs per relevant feature: root mode and `--vpn`, with ProjectM TV from
  !50236's CI APK and the ProjectM Android APK from !52248 (whether it installs
  on a non-touch box is part of the result). `--apk` runs with and without an
  MR.
- Uploads are exercised against our own fdroiddata fork project; rendering
  is checked with GitLab's Markdown preview API. Nothing is posted to a real
  MR without the owner's explicit yes.

## Delivery

1. Spec (this file) merged to the fork's `main` after review.
2. Implementation plan on the fork's `main`.
3. For each feature: branch from `upstream/main`, implement, validate, PR into
   the fork's `main` with a Codex review where the integration is enabled
   (otherwise reported as a blocker, not skipped), merge.
4. Upstream PRs prepared from the same feature branches and opened after the
   owner has seen them.
