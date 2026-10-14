# Review apps from Windows with PowerShell 7

`fdroid-tester.ps1` runs the review workflow natively from PowerShell 7. It
supports CI APK downloads, local APKs, Android/TV device testing, PCAPdroid VPN
or root capture, screenshots, and the same checklist report as the Bash version.
It does not need Bash, WSL, `unzip`, or a separate SHA-256 command.

## Setup

### 1. Install the computer tools

- Install [PowerShell 7](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows). Use `pwsh`, not the built-in Windows PowerShell 5.1 (`powershell.exe`).
- Install [Python 3](https://www.python.org/downloads/windows/). Make a working `python`, `python3`, or `py -3` available; the script checks for Python 3.6+.
- Install [Android Studio](https://developer.android.com/studio). In its SDK Manager, install **Android SDK Build-Tools** and **Android SDK Platform-Tools**, and note the SDK location.
- Install Git if cloning the fork, or download and extract the repository ZIP instead.

With WinGet available, PowerShell can be installed from a terminal:

```powershell
winget install --id Microsoft.PowerShell --source winget
```

Open a new **PowerShell 7** terminal, then check it:

```powershell
$PSVersionTable.PSVersion
python --version
curl.exe --version
```

If Python is exposed only through its launcher, use `py -3 --version` instead.
`curl.exe` is included in current Windows versions; the script selects the
executable rather than PowerShell's historical `curl` alias.

Set the SDK location if it differs from the default below, and add `adb` to
this terminal's path:

```powershell
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PATH = "$env:ANDROID_HOME\platform-tools;$env:PATH"
adb version
```

The script searches the SDK's `build-tools` directories for `aapt2.exe`, or
uses an `aapt2` executable already on `PATH`. An SDK Platform (`android.jar`)
is not needed for reviewing an APK.

### 2. Get the fork

```powershell
git clone https://github.com/johnneerdael/fdroid-tester.git
Set-Location fdroid-tester
```

For a ZIP download, open PowerShell in the extracted repository directory.
If Windows blocks the downloaded script, review it and unblock that file:

```powershell
Unblock-File .\fdroid-tester.ps1
```

If the terminal's execution policy still blocks local scripts, use a
session-only setting when permitted by your organization:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

This setting applies only to this PowerShell session. Run the following
commands in that same session. See Microsoft's
[execution policy guidance](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)
if a managed policy prevents it.

### 3. Connect the device and check readiness

Enable USB debugging, connect and unlock the device, and accept its debugging
authorization prompt. Install
[PCAPdroid](https://f-droid.org/packages/com.emanuelef.remote_capture/)
on the device for network testing. Then run:

```powershell
adb devices
& .\fdroid-tester.ps1 -Check
```

The device should have state `device`. If several devices are connected,
choose the exact serial from `adb devices`:

```powershell
$SERIAL = "ABC123456"
& .\fdroid-tester.ps1 -Check -Serial $SERIAL
```

Fix errors and read warnings: `ready` can still mean that network capture or
automatic posting is unavailable. PCAPdroid installation may be offered during
the check. Nothing is installed without the corresponding confirmation.

For automatic posting, install [GitLab CLI](https://gitlab.com/gitlab-org/cli)
and run `glab auth login --hostname gitlab.com`. It needs API access and a
recent version supporting `glab api --form` for screenshot uploads. Otherwise,
paste the saved report into the MR yourself.

## Run a review

Replace the example URL with the app's open **fdroid/fdroiddata** merge request.
Use a new session directory for each review to keep APKs and evidence separate:

```powershell
$MR_URL = "https://gitlab.com/fdroid/fdroiddata/-/merge_requests/123"
New-Item -ItemType Directory review-session-01
Set-Location review-session-01
& ..\fdroid-tester.ps1 $MR_URL
```

With a chosen device and longer startup watch:

```powershell
& ..\fdroid-tester.ps1 $MR_URL -Serial $SERIAL -Watch 30
```

Use one run command per session. Follow the
[review walkthrough](reviewer-guide.md#review-an-app): leave the device untouched
during startup, then exercise its features. Type `s` and press Enter in the
terminal to take a screenshot and add a caption; Enter alone finishes manual
testing. Answer `s` for a review question you cannot verify.

The report and evidence go into `<appid>_<versionCode>-review` in the session
directory. Many questions default to yes/no. **At the posting prompt, Enter
means yes; type `n` to keep the report local.** A checked network box can
record a concern. Read the
[checklist mapping](reviewer-guide.md#how-the-report-maps-to-f-droids-review)
before sharing the report.

## Options

Examples below assume the repository directory. From a session directory,
use `..\fdroid-tester.ps1` instead.

| Task | PowerShell option | Bash-style equivalent accepted by the PS1 |
| --- | --- | --- |
| Choose device | `-Serial SERIAL` | `-s SERIAL` |
| Startup watch | `-Watch 30` | `-w 30` |
| Local APK | `-Apk "C:\APK files\app.apk"` | `--apk "C:\APK files\app.apk"` |
| Inspect without a device | `-NoDevice` | `--no-device` |
| Leave installed | `-Keep` | `--keep` |
| Force VPN capture | `-Vpn` | `--vpn` |
| Check setup | `-Check` | `--check` |
| Show usage / version | `-Help` / `-Version` | `--help` / `--version` |

```powershell
# Local report, without GitLab MR lookup or posting.
& .\fdroid-tester.ps1 -Apk "C:\APK files\app.apk"

# Local APK with MR context; the report discloses local input.
& .\fdroid-tester.ps1 -Apk "C:\APK files\app.apk" $MR_URL

# Partial review only; skip unverified device questions.
& .\fdroid-tester.ps1 $MR_URL -NoDevice
```

These are alternatives. Local-file testing still checks tracker data and
VirusTotal as configured; it is not an offline mode. A local APK is not
verified against the CI artifact. Android TV and root capture work as described
in the [shared guide](reviewer-guide.md#android-tv-and-rooted-devices).

## Optional keys

Store one key per file, on a single line, in `%APPDATA%\fdroid-tester`:

```powershell
New-Item -ItemType Directory -Force "$env:APPDATA\fdroid-tester"
notepad "$env:APPDATA\fdroid-tester\pcapdroid-api-key"
# Only if you already have a VirusTotal API key:
notepad "$env:APPDATA\fdroid-tester\virustotal-api-key"
```

PCAPdroid's key skips control prompts; device VPN/root approval can still be
needed. A VirusTotal key enables hash lookup and optional background scanning.
Uploads are shared with VirusTotal's partners; unknown local files default to
**no upload**. See the [key and scan details](reviewer-guide.md#optional-api-keys).

The tracker cache defaults to `%LOCALAPPDATA%\fdroid-tester`. `XDG_CONFIG_HOME`
and `XDG_CACHE_HOME`, if set, override the corresponding parent directories.
On macOS/Linux, the PS1 uses the same XDG/default locations as the Bash script.

## Troubleshooting and verification

- If the script is blocked, follow the setup's `Unblock-File` and execution-policy steps; use PowerShell 7 rather than ISE or PowerShell 5.1.
- If Python opens the Store or cannot run, install a working Python interpreter/launcher and reopen the terminal.
- If `adb` or `aapt2` is missing, verify the SDK path and install both SDK tool packages. Windows USB device drivers may also be required.
- If editing is needed, Notepad is selected by default on Windows. `VISUAL` or `EDITOR` can select another editor executable; use its executable path without extra arguments.
- If a scan is pending, Enter skips waiting in an interactive console. Redirected input waits for completion instead.
- For device, capture, artifact, or posting problems, use the [shared troubleshooting table](reviewer-guide.md#troubleshooting).

Run portable CLI and native-process checks with Python and PowerShell 7:

```powershell
python tests/test_powershell.py
```

The full review fixture suite uses Bash on macOS/Linux:
`bash tests/run.sh --powershell`. It fakes the device, network, and GitLab
services. Passing those tests is not a real Windows/device review; use `-Check`
and complete a device session to validate your own Windows setup.
