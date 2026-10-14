# Review an F-Droid app with fdroid-tester

This guide is for a tester who can use a terminal and an Android device but
does not need to know the script's internals. It walks from setup to a report
that an F-Droid maintainer can use.

The checklist mapping was checked against the
[F-Droid reviewing-new-apps guide](https://gitlab.com/fdroid/wiki/-/wikis/Internal/Reviewing-new-apps)
and this fork's script on 2026-10-14. Consult the live wiki for later changes.

- [Setup](#setup)
- [Review an app](#review-an-app)
- [Read and share the report](#read-and-share-the-report)
- [Checklist mapping](#how-the-report-maps-to-f-droids-review)
- [Local APKs and partial reviews](#local-apks-and-partial-reviews)
- [Android TV and root capture](#android-tv-and-rooted-devices)
- [Optional API keys](#optional-api-keys)
- [Troubleshooting](#troubleshooting)
- [Reviewer invitation template](#invite-someone-to-review-your-app)

## Setup

On Windows, start with [Windows setup and commands](windows.md). The walkthrough
and checklist below apply to both versions; use the PowerShell equivalents in
that guide for the Bash command examples.

### Install the computer tools

| Tool | Needed for |
| --- | --- |
| Bash 4.4 or newer | Running the script; macOS's bundled Bash is too old. |
| Python 3.6 or newer | Reading APK contents, JSON reports, and network captures. |
| `curl`, `unzip`, and `sha256sum` or `shasum` | Downloads, APK inspection, and identifying the tested file. |
| Android SDK Build-Tools (`aapt2`) | Reading the APK's manifest and device requirements, even with `--no-device`. |
| Android SDK Platform-Tools (`adb`) | Installing, launching, capturing screenshots, and reading device logs. |
| Git | Cloning the fork; not needed if the script was downloaded separately. |
| `glab` and a GitLab account (optional) | Posting the report and uploading screenshots automatically. |
| An editor (optional) | Editing the report before posting; selected from `VISUAL`, `EDITOR`, `nano`, then `vi`. |

On macOS, with Homebrew installed:

```bash
brew install bash python
export PATH="$(brew --prefix bash)/bin:$PATH"
bash --version
```

Use that terminal for the remaining steps. Installing Bash alone does not
change which `bash` the terminal finds; the `PATH` line selects Homebrew's
version. Add it to your shell configuration if you want it in new terminals.

On Debian or Ubuntu:

```bash
sudo apt update
sudo apt install bash python3 curl unzip coreutils git
bash --version
```

Install [Android Studio](https://developer.android.com/studio), open its SDK
Manager, and install **Android SDK Build-Tools** and **Android SDK
Platform-Tools** from the SDK Tools tab. Note the SDK location shown there.
Running the tester does not require building the app or installing Gradle.

Set the SDK path. These are common locations; use the actual SDK Manager path
if yours differs.

```bash
# macOS
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
```

```bash
# Linux
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
```

The script searches `ANDROID_HOME/build-tools/` for `aapt2`. It also accepts
`aapt2` on `PATH` or an SDK at `ANDROID_SDK_ROOT`. On macOS, if SDK discovery
fails, add the installed Build-Tools directory directly to `PATH`, for example:

```bash
# Replace 34.0.0 with the version installed in your SDK.
export PATH="$ANDROID_HOME/build-tools/34.0.0:$PATH"
```

If you already use Android's command-line tools, install Build-Tools and
Platform-Tools with [sdkmanager](https://developer.android.com/tools/sdkmanager)
instead. An SDK Platform (`android.jar`) is required only for this fork's
fixture tests, not for reviewing an APK.

### Get the tester

If you have not already cloned this fork:

```bash
git clone https://github.com/johnneerdael/fdroid-tester.git
cd fdroid-tester
```

Keep this terminal open in the repository directory for the setup checks below.
There is no separate package installation step for the tester itself.

### Connect the Android device

1. Enable Developer options and USB debugging on the device.
2. Connect it with a data-capable USB cable, unlock it, and accept the debugging authorization prompt.
3. Run `adb devices`. The chosen device must have state `device`, not `unauthorized` or `offline`.

Example output:

```text
List of devices attached
ABC123456    device
```

If several devices appear, use the chosen serial with **every** tester command:

```bash
SERIAL="ABC123456"
bash fdroid-tester.sh --check -s "$SERIAL"
```

For wireless devices, including TVs, establish the connection using
[Android's ADB instructions](https://developer.android.com/tools/adb#wireless).
Then use the exact identifier from `adb devices` with `-s`; it may be an
address and port rather than a USB serial.

The script checks CPU architecture and minimum Android SDK version, and warns
about a required TV feature. Check any other app-specific requirements yourself,
including root access, accounts, hardware, or external services.

### Prepare network capture

Install [PCAPdroid](https://f-droid.org/packages/com.emanuelef.remote_capture/)
on the device. The tester requires its version code to be at least 62 for
remote control. Open it once to complete any first-run setup. During the
review, allow its control prompt and VPN or root prompt when requested.

If PCAPdroid is missing or too old, the script offers to install the latest
GitHub release. Replacing a differently signed copy requires uninstalling it
and loses its settings; that action has a separate confirmation. Install the
F-Droid version yourself if that is your preferred source.

No API keys are required. Optional keys and capture modes are described below.

### Optional: enable automatic posting

Install [GitLab CLI](https://gitlab.com/gitlab-org/cli). On macOS:

```bash
brew install glab
glab auth login --hostname gitlab.com
glab auth status --hostname gitlab.com
```

Follow the [login instructions](https://docs.gitlab.com/cli/auth/login/);
if using a token, the tester needs the `api` scope. Use a recent `glab` with
`glab api --form` support for screenshot uploads. Automatic comments are posted
from your GitLab account. Without `glab`, the script still saves the report.

### Check readiness

From the cloned repository, with the device connected:

```bash
bash fdroid-tester.sh --check
```

Fix `✗` errors before starting. Read `!` warnings too: missing PCAPdroid or
GitLab login disables only that part, so `ready` is not a guarantee of a
complete device/network review. `--check` also refreshes the tracker cache and
may offer to install PCAPdroid; it does not install the app under review.

## Review an app

### 1. Choose the submission and read its description

Use the author's open `fdroid/fdroiddata` merge request, or pick one from the
[review-requested queue](https://gitlab.com/fdroid/fdroiddata/-/merge_requests/?sort=created_asc&state=opened&label_name[]=review-requested).
Read the full app description, Code Quality findings, and existing discussion.
Write down the main features to try. The script may display an English
summary, but that is not the full description.

An MR link or its numeric ID is accepted. Other repositories and GitHub pull
requests are not accepted. Downloaded APKs come from links in the MR's Code
Quality report; the pipeline must have produced readable Code Quality data
and an available APK. Other pipeline failures still need maintainer attention.

### 2. Start in a fresh session directory

After cloning, these commands create a session directory beside the script.
Choose an unused directory name for each run. Replace the example URL.

```bash
mkdir review-session-01
cd review-session-01
MR_URL="https://gitlab.com/fdroid/fdroiddata/-/merge_requests/123"
bash ../fdroid-tester.sh "$MR_URL"
```

With multiple devices or a longer startup watch:

```bash
SERIAL="ABC123456"
bash ../fdroid-tester.sh "$MR_URL" -s "$SERIAL" -w 30
```

Use one of these run commands per session. The script reuses an existing
valid APK with the same download filename. Reports for the same application
ID/version code share an output directory, and report/capture files can be
overwritten. A fresh directory avoids mixing builds and evidence.

### 3. Read the APK findings

The script selects an APK compatible with the connected device's native-code
architectures, then prints its package ID, version, minimum SDK, and SHA-256.
It lists permissions, tracker-code matches, embedded web addresses, browser
libraries, language hints, and manifest flags. It also reads the MR metadata
categories when available.

Treat these findings as leads. An embedded URL does not show that the app
contacted it, and a matching class name does not establish what it does at
runtime. Keep findings you need in your tester notes; not every terminal
message is copied into `report.md`.

### 4. Watch the first launch

If a copy of the app is already installed, the script offers to uninstall it
for a clean start. **Uninstalling deletes its app data.** Declining attempts
an in-place install; a different signing key may prevent that. Use a test
device or back up data you need, and disclose an upgrade test rather than a
clean install in the notes.

For an app declaring `INTERNET`, the script starts PCAPdroid before launching
the app. Allow the device prompts and wait for “PCAPdroid is recording.” It
stops an existing PCAPdroid capture first so this run gets its own capture.

Leave the device untouched for the startup watch (15 seconds, or `-w SECONDS`).
The script checks whether the app remains running, looks for a permission
prompt, and saves a startup screenshot. If the app cannot launch automatically,
open it as instructed and describe that in your notes.

### 5. Test the app yourself

Use the app on the device while the terminal waits:

- Try each main feature from the description, including saving/loading or playback where relevant.
- Deny optional permissions first; check whether basic functions still work and when permission prompts appear.
- Inspect onboarding, license/terms screens, sign-in requirements, and paid or online features.
- Open help, author, and donation links; check where they open.
- Inspect settings for language, update checks, and optional network features.
- On TV, test focus, directional navigation, Back, and feature access with the remote.

To capture evidence, type `s` and press Enter **in the terminal**, then type
an optional caption. Repeat for useful screens, especially a failure or a
permission prompt. Captions such as “Basic playback works after denying
notifications” tell a maintainer more than “main screen.”

Press Enter on its own at the screenshot prompt when finished. Traffic
capture stops at that point; the script pulls and summarizes it.

### 6. Answer from evidence

At each `y/n/s` question, use `y` for yes, `n` for no, and `s` for skipped or
unknown. **Enter accepts the displayed default**, often yes or no. Do not
accept a default for a feature or scan you did not check.

Read the question carefully: answering yes to finding a policy problem or
extra terms leaves the corresponding compliance statement unchecked. The
script reverses those answers when generating the report.

Add notes line by line; an empty line finishes them. Useful notes include the
features tested, exact reproduction steps, what permission was denied,
expected versus observed behavior, required accounts, and anything not tested.
Identify an author self-test explicitly if you are reviewing your own app.

## Read and share the report

The script prints the report, saves it, and offers an editor when one is
available. Set `EDITOR` before starting if needed, for example
`export EDITOR=nano`.

| Report notation | Meaning |
| --- | --- |
| `[x]` | The statement is marked true; read its wording to determine the implication. |
| `[ ]` | The statement is marked false. |
| `[ ]` with `(not checked)` | No conclusion was supplied; this needs testing or an explicit limitation. |

Most non-network statements describe desirable behavior. Several network
statements describe findings that need explanation or follow-up. For example,
these two checked boxes have different implications:

```markdown
- [x] The app can start and work normally.
- [x] Tracking domains connected.
```

Review automatically filled rows too. Use the mapping below to see how each
was derived. Correct unsupported conclusions in the editor and explain the
evidence in notes. Pay particular attention to the static tracker override and
the scan result rules.

When `glab` is ready, the script offers to post a comment to the same MR.
**The prompt defaults to yes: Enter posts; `n` keeps it local.** After agreement,
screenshots are uploaded to fdroiddata, falling back to the MR's source fork
if needed, and embedded in the comment. The local report keeps filenames.
Captures and other files are not automatically attached. Check the returned
comment link and verify that the images render.

Without automatic posting, open `report.md` in a text editor, paste its entire
contents into an MR comment, and attach the relevant PNGs in GitLab. Preview
before submitting; filenames alone do not upload images. If posting fails,
the local report remains available for this route.

Unless `--keep` was used, the script offers to remove the reviewed app at the
end. Enter accepts removal. It restores the device's previous stay-awake
setting on exit.

### Files to keep

Everything is relative to the directory from which the tester was launched:

| Path | Contents / when created |
| --- | --- |
| Downloaded `*.apk` | CI download(s); `--apk` uses the supplied file in its original location. |
| `<appid>_<versionCode>-review/report.md` | Checklist, tester notes, screenshot filenames, and expandable details, saved after the questions. |
| `after-<SECONDS>s.png` | Automatic startup screenshot, if successful. |
| `permission-on-start.png` | Screenshot when a startup permission prompt was detected. |
| `shot-01.png`, `shot-02.png`, … | Screenshots requested during manual testing. |
| `shots.tsv` | Screenshot filenames and captions for this run. |
| `traffic.pcap` | App-filtered capture, if recording and retrieval succeeded. |
| `crash.log` | Crash-buffer output when a startup or later crash was detected. |
| `codequality.json` | MR Code Quality data, when reviewing with MR context. |
| `<appid>.yml` | MR metadata, if fetched successfully. |

The last eight filenames are inside the review directory. The report identifies
the tested APK by name and SHA-256 and records the device when connected.
Keep the report and supporting files together; attach logs or captures only
when relevant, after checking for personal data or account information.

## How the report maps to F-Droid's review

The generated table uses the wiki's six Tester Review categories. This maps
all 17 checklist statements to the current implementation. “Automatic” means
the script fills an answer from a check or heuristic; it still needs review.

| Category / check | Evidence and how the script fills it | What the tester must establish |
| --- | --- | --- |
| Basic Function: normal operation | Startup process/crash checks plus your answer. A detected crash forces this row false. | Try normal use; a running process alone does not show that the UI or features work. |
| Basic Function: advertised features | Your answer; the script may show the English CI summary. | Compare actual behavior with the full description and list the functions tested. |
| Basic Function: distinctive icon | Your answer. | Inspect the launcher/app icon; screenshots can support the observation. |
| Policy Compliance: acceptable features | Static tracker/library hints plus your policy answer, reversed for the compliance row. | Review behavior against the current Inclusion Policy; explain concerns rather than treating a signature as a verdict. |
| Policy Compliance: suitable categories | Categories fetched from MR metadata, when available, plus your answer. | Compare them with the app's purpose; a local-only review has no MR metadata. |
| Policy Compliance: no extra terms | Your answer about extra terms, reversed for this row. | Inspect onboarding and features that introduce agreements or service requirements. |
| Permissions: optional permission denial | Permission list, startup prompt detection, and your answer. | Deny optional permissions and exercise the affected and basic functions; check prompt timing. |
| Permissions: justified all-files access | Automatic true if `MANAGE_EXTERNAL_STORAGE` is absent; otherwise asks whether it is necessary. | When present, assess whether the system file picker (SAF) could serve the feature. |
| Network Connections: any activity | Automatic from parsed startup/later destinations; asks you if capture is unavailable. | Confirm capture worked and exercise online features. No observed activity is limited to this session. |
| Network Connections: startup activity | Automatic from destinations first seen by the end of the watch period; otherwise your answer. | Explain the destination and purpose. A DNS lookup or transport connection alone does not establish a dependency on a web service. |
| Network Connections: automatic updates | Heuristic destination hints influence the prompt default; your answer fills the row. | Check settings/behavior and distinguish an update check from other uses of the same service. |
| Network Connections: unnecessary requests | Automatically flags recognized online-font or connectivity-check destinations; otherwise asks you. | Assess necessity and optionality, including online icons and requests the heuristic misses. |
| Network Connections: tracking | Automatic from tracker-tagged destinations; **static tracker-code matches also force this row true**. | Separate embedded code from observed contact. If only a code match exists, edit the row to unknown and explain it; investigate the match. |
| Network Connections: unexplained destinations | Destination list or embedded addresses plus your answer. | Compare observed traffic with the full description and ask the author about unexplained destinations. |
| Network Connections: unnecessary embedded browser | Static WebView/browser-library hints plus your answer about where links open. | Judge the actual use; an embedded browser can be part of the app's core purpose. |
| Language Support: usable English | Manifest locale hints plus your answer. | Navigate the UI; default resources can be English without an explicit English locale entry. |
| Security Scan: benign scanner result | VirusTotal link or API results plus your answer when needed. The API auto-checks this row when malicious count is zero. | Inspect suspicious results too, confirm a completed scan, and describe detections. A scan is not proof of safety. |

If the manifest has no `INTERNET` permission, the script replaces the seven
network rows with a note recording that fact. It does not perform a traffic
capture for that APK.

The separate
[Maintainer Review](https://gitlab.com/fdroid/wiki/-/wikis/Internal/Reviewing-new-apps#maintainer-review)
also concerns submission requirements, metadata, and inclusion decisions. The
tester surfaces CI warnings and metadata context but does not complete those
checks, set review labels, prove reproducibility, or merge the submission.

Use the wiki's follow-up guidance when a connection needs explanation:
discuss service dependencies that may warrant `NonFreeNet` or `TetheredNet`,
ask about removing unused `INTERNET` permission, and report requests that
could be removed or made optional. The script does not decide those outcomes.

### Limits that affect interpretation

- **A partial run remains partial.** With `--no-device`, no app is installed or exercised. Questions still appear and can default to positive answers. Choose `s` for anything not independently tested; if using prior device evidence, identify its build and session in notes.
- **Static inspection is a signature search.** It examines DEX class strings, resources, and selected Flutter native-code strings. Obfuscation, other native libraries, dynamically loaded code, and tracker-list coverage can hide findings. Missing tracker data disables that signature check.
- **Captured names are not decrypted content.** The parser uses DNS, TLS server names, and plain HTTP hosts when available; unnamed flows appear as address/port. DNS lookups are included. Destinations are grouped by first observation, so a later repeat of a startup destination need not appear again in the later list.
- **Network heuristics are incomplete.** The automatic “unnecessary” check recognizes selected font/connectivity destinations, not every unnecessary request. In VPN mode the tester requests QUIC blocking and private-DNS blocking; document capture conditions if they affect behavior.
- **Root capture may have fewer names.** App-filtered root capture can omit system-performed DNS. TLS/HTTP naming may still work; unnamed traffic needs manual investigation.
- **A local APK is identified, not authenticated against CI.** With MR context, the script always discloses local input and may warn on a package/version filename mismatch. It does not compare its hash or signature with the CI artifact.
- **A startup warning is evidence to inspect.** A process that exits is not always a crash, and prompt detection varies by Android UI. Use logs, screenshots, and manual reproduction to interpret it.

## Local APKs and partial reviews

From the repository directory:

```bash
# A local file: no GitLab MR lookup or posting.
bash fdroid-tester.sh --apk /absolute/path/to/app.apk

# The same file, with MR context and an offer to post there.
bash fdroid-tester.sh --apk /absolute/path/to/app.apk "$MR_URL"

# Inspect a CI APK without installing it.
bash fdroid-tester.sh "$MR_URL" --no-device
```

These are separate alternatives. The local-only path still attempts to refresh
Exodus tracker data and opens/queries VirusTotal as configured; it is not an
offline mode. A local APK with an MR still requires the MR Code Quality report
to be readable, although that report need not contain an APK download.

Use CI downloads for a submission review when possible. For a local-file test,
record where the file came from and why it was used. Do not present it as
verification of F-Droid's CI-built artifact.

## Android TV and rooted devices

A TV-only APK is launched through its `LEANBACK_LAUNCHER` activity. If it
requires `android.software.leanback` but the device does not declare it, the
script warns and asks whether to continue. Continuing tests a sideloaded app
on that device; it does not show that the F-Droid client would offer it there.
The report records that mismatch.

If `su` is available, the tester selects PCAPdroid root mode. PCAPdroid still
needs actual root access; detecting `su` does not grant it. To use VPN mode
instead, including after a root-access refusal:

```bash
bash fdroid-tester.sh "$MR_URL" -s "$SERIAL" --vpn
```

## Optional API keys

Keys live under `${XDG_CONFIG_HOME:-$HOME/.config}/fdroid-tester/`, one key per
file, on a single line. Create the directory and files with a text editor;
do not put credentials in a report or commit them to the repository.

On Windows, the PowerShell version defaults to `%APPDATA%\fdroid-tester` for
keys and `%LOCALAPPDATA%\fdroid-tester` for the tracker cache. The XDG variables,
when set, override those locations. See [Windows key setup](windows.md#optional-keys).

| File | Effect |
| --- | --- |
| `pcapdroid-api-key` | Skips PCAPdroid's control-authorization prompt. Obtain it through PCAPdroid's Settings → Control permissions menu. VPN/root authorization can still be needed. |
| `virustotal-api-key` | Looks up the APK hash and offers an upload if unknown; scans in the background and later collects the result. |

Without a VirusTotal key, the script opens the APK's hash page and asks for
your judgment. If the file is unknown, a scan requires an upload. VirusTotal
shares uploaded files with its partners; use `s` if the file cannot be shared
or no completed result is available. API uploads of unknown local files
default to no; CI-download uploads default to yes. A pending scan can be
skipped with Enter, followed by a manual check of the link.

The Exodus tracker list is cached under
`${XDG_CACHE_HOME:-$HOME/.cache}/fdroid-tester/` and refreshed after seven days
when reachable. A cached list may be older if the refresh fails.

## Troubleshooting

| Symptom | Next step |
| --- | --- |
| Bash version error or `mapfile` failure on macOS | Select Homebrew Bash with the setup `PATH` line. Verify `bash --version`, then rerun. |
| `aapt2` not found | Install SDK Build-Tools; set the correct `ANDROID_HOME`, or add the installed Build-Tools directory to `PATH`. Platform-Tools alone does not include `aapt2`. |
| Device is `unauthorized` or `offline` | Unlock and accept debugging authorization, or reconnect it. Confirm `adb devices` shows `device`. |
| More than one device | Pass `-s` with the exact identifier from `adb devices`. |
| `ready`, but no traffic capture/posting | Revisit the warnings; install PCAPdroid or configure `glab`. Those omissions do not necessarily fail `--check`. |
| No Code Quality report or no APK link | Check that the MR pipeline has run and produced a report and APK. Ask the author to rerun it if needed. |
| Artifact download fails | CI artifacts can expire. Ask for a fresh pipeline and start a new session directory. |
| No compatible APK / minimum SDK too high | Use a suitable device. SDK/ABI compatibility does not establish every app requirement. |
| `UPDATE_INCOMPATIBLE` | An installed copy has a different signing key. Use a separate device, or back up data and uninstall that copy before retrying. |
| PCAPdroid does not start | Open it manually, allow control and VPN/root access, then retry. On rooted devices, try `--vpn` if root capture was refused. |
| Earlier PCAPdroid capture will not stop | Allow the stop prompt, or stop it in PCAPdroid before rerunning. |
| `pcapng is not supported` or capture cannot be pulled | Use plain PCAP, confirm capture actually started/stopped, and check PCAPdroid's Download folder. Skip unverified network conclusions. |
| Network says none / only addresses appear | Exercise the relevant feature and confirm capture worked. Inspect `traffic.pcap` in a packet viewer; root-mode DNS and encrypted protocols may limit naming. |
| App has no automatic launcher | Open it manually when instructed and record the launch path. |
| Screenshot upload fails | Update `glab` if `--form` is missing, or attach PNGs manually. The comment may post successfully even when an image upload failed. |
| Report cannot be posted | Check `glab` login and API access, or paste `report.md` into the MR manually. Inspect the MR before retrying to avoid a duplicate comment. |
| Run interrupted / end of input | Use an interactive terminal and rerun in a fresh directory. After interruption, check PCAPdroid and stop any remaining capture; the exit cleanup does not stop it automatically. |

## Invite someone to review your app

Give the tester the exact fdroiddata MR, the device requirements, the full
description, and a short list of features that matter. Do not ask them to
agree with pre-filled answers. This template can be pasted into a review
request after replacing the bracketed fields:

```markdown
Could you test [app name] for its F-Droid submission?

- Submission: [fdroid/fdroiddata merge request URL]
- Description and main features: [link or short list]
- Device requirements: [Android version, phone/TV, other requirements]
- Accounts or external setup: [what is needed, or none]
- Please try: [specific features and permission-denial paths]

Use https://github.com/johnneerdael/fdroid-tester and follow its README setup
and reviewer guide. Run it with the submission URL so it downloads the APK
from F-Droid CI. While using the app, type s + Enter in the terminal for
screenshots, then Enter alone when finished.

Answer from what you tested; use s for anything you could not verify. Review
the generated report before posting it to the submission, and include the
features tested, failures/reproduction steps, and anything left untested.
Please note whether this is an independent review or an author self-test.
```

For a local-APK request, replace the CI-download instruction with the file's
download link and `--apk` command, and ask the tester to retain the local-file
disclosure in their report. A useful handoff makes the build and requested
testing explicit without pre-deciding the outcome.
