# fdroid-tester

Gather evidence for an F-Droid app review and turn it into a report ready for
the app's merge request. The script downloads a CI-built APK, inspects it,
installs it on your Android device, captures network traffic with PCAPdroid,
and collects screenshots and your observations.

Use it to help with F-Droid's
[Tester Review](https://gitlab.com/fdroid/wiki/-/wikis/Internal/Reviewing-new-apps#tester-review).
You still try the app's features and judge the findings. The generated report
supports a review; it does not approve an app for inclusion in F-Droid.

## Start here

- **Windows:** use the native [PowerShell 7 version](docs/windows.md); no Bash or WSL is required.
- **First run:** follow [setup](docs/reviewer-guide.md#setup), then the quick start below.
- **Review an app:** follow the [complete walkthrough](docs/reviewer-guide.md#review-an-app).
- **Understand the results:** read the [checklist mapping](docs/reviewer-guide.md#how-the-report-maps-to-f-droids-review).
- **Ask someone to review your app:** copy the [reviewer handoff](docs/reviewer-guide.md#invite-someone-to-review-your-app).
- **Something failed:** see [troubleshooting](docs/reviewer-guide.md#troubleshooting).

## Quick start

The commands below are for macOS and Linux. On Windows, follow
[Windows setup](docs/windows.md#setup), then run in PowerShell 7:

```powershell
pwsh -NoProfile -File .\fdroid-tester.ps1 -Check
$MR_URL = "https://gitlab.com/fdroid/fdroiddata/-/merge_requests/123"
pwsh -NoProfile -File .\fdroid-tester.ps1 $MR_URL
```

Both versions use the same review checklist and prompts. Replace the example
URL with your app's submission URL.

Run in an interactive terminal on macOS or Linux with Bash 4.4+, Python 3.6+,
`curl`, `unzip`, a SHA-256 tool, and Android SDK Build-Tools (`aapt2`). For a
device review, also install SDK Platform-Tools (`adb`), enable USB debugging,
and install [PCAPdroid](https://f-droid.org/packages/com.emanuelef.remote_capture/)
on the device if the app uses the internet. See [setup](docs/reviewer-guide.md#setup)
for installation commands, including the newer Bash required on macOS. If
you have already cloned the fork, skip the first two commands below.

```bash
git clone https://github.com/johnneerdael/fdroid-tester.git
cd fdroid-tester
bash fdroid-tester.sh --check
```

Check the warnings as well as errors: `ready` can still mean that traffic
capture or automatic posting is unavailable. A GitLab account and `glab` are
optional; you can paste the report into the merge request yourself.

Replace the example URL with the **open `fdroid/fdroiddata` merge request for
the app you want to review**. A GitHub pull request or an app's source-repo
merge request is not accepted.

```bash
MR_URL="https://gitlab.com/fdroid/fdroiddata/-/merge_requests/123"
bash fdroid-tester.sh "$MR_URL"
```

During the run:

1. Allow PCAPdroid's prompts on the device and wait for capture to start.
2. Leave the device untouched during the initial watch period (15 seconds by default).
3. Try the features in the app's description, including permission-denial paths.
4. Type `s` and press Enter **in the terminal** to save a screenshot; add a caption.
5. Press Enter on its own when finished, then answer the review questions.
6. Inspect and, if needed, edit the report before sharing it.

Answer `s` to skip a question you cannot verify. Many questions default to
yes or no; pressing Enter accepts that answer. At the final posting prompt,
**Enter means yes** when `glab` is ready. Type `n` to keep the report local.

The APK is downloaded into the directory where you run the command. The report
is saved in `<appid>_<versionCode>-review/report.md` there, with screenshots and
any captured traffic. Use a fresh working directory for each review session
to avoid reusing an older download or overwriting a previous report.

**Read each checkbox as a statement.** In the network section, a checked box
may identify tracking, an update check, or an unexplained connection. See
[how to read the report](docs/reviewer-guide.md#read-and-share-the-report)
before treating any checkbox as a successful check.

## Other ways to run

| Task | Command | What to expect |
| --- | --- | --- |
| Choose a device | `bash fdroid-tester.sh "$MR_URL" -s SERIAL` | Replace `SERIAL` with an entry from `adb devices`. |
| Watch startup longer | `bash fdroid-tester.sh "$MR_URL" -w 30` | Wait 30 seconds before interacting; manual testing can take as long as needed. |
| Leave the app installed | `bash fdroid-tester.sh "$MR_URL" --keep` | Skip the final removal prompt. |
| Test a local APK | `bash fdroid-tester.sh --apk /path/to/app.apk` | Generate a local report without reading or posting to GitLab. |
| Test a local APK with MR context | `bash fdroid-tester.sh --apk /path/to/app.apk "$MR_URL"` | Read the MR and offer posting; disclose that the tested APK was supplied locally. |
| Inspect without a device | `bash fdroid-tester.sh "$MR_URL" --no-device` | Produce a partial review; skip unverified device and network questions. |
| Force VPN capture on a rooted device | `bash fdroid-tester.sh "$MR_URL" --vpn` | Use PCAPdroid's VPN instead of root capture. |
| See all options | `bash fdroid-tester.sh --help` | Print CLI usage and optional key locations. |

Android TV apps use their Leanback launcher when they have no ordinary launcher
activity. Use a suitable TV device and test navigation with its remote; see
[Android TV](docs/reviewer-guide.md#android-tv-and-rooted-devices).

## About this fork

Based on [by-architect/fdroid-tester](https://github.com/by-architect/fdroid-tester).
This fork adds screenshots during manual testing and image embedding when
posting, Android TV support, PCAPdroid root capture with a `--vpn` override,
local APK input, a native Windows PowerShell 7 entry point, and fixes to the
macOS check display and interactive flow.
Licensed under [GPL-3.0-or-later](LICENSE).

For contributors, the fixture suite runs the script with fake device, network,
and GitLab commands. It needs the runtime tools above and an Android SDK
Platform containing `android.jar`; set `ANDROID_HOME` to that SDK.

```bash
bash tests/run.sh
# Also run the review fixtures against PowerShell 7 on macOS/Linux.
bash tests/run.sh --powershell
```

Portable PowerShell CLI/process checks run on Windows as well:

```powershell
python tests/test_powershell.py
```

Keep the embedded Python analysis helper synchronized between the two entry
points when changing APK, capture, or screenshot embedding logic.

These tests do not replace a review on a real device.
