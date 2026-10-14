#Requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Original Bash workflow / embedded Python: Copyright (C) 2026 by-architect
# Based on by-architect/fdroid-tester and this fork's Bash review workflow.
# Run with pwsh -NoProfile -File fdroid-tester.ps1 MR_URL [options].
# No Bash, WSL, unzip, or external hash utility is required.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[string[]]$Cli = @($args)
$Version = '1.0.0'
$Repo = 'fdroid/fdroiddata'
$Project = 'fdroid%2Ffdroiddata'
$Api = 'https://gitlab.com/api/v4'
$PcapPackage = 'com.emanuelef.remote_capture'
$Serial = ''; $Watch = 15; $NoDevice = $false; $Keep = $false
$MrArgument = ''; $CheckOnly = $false; $ForceVpn = $false; $ApkArgument = ''

function Show-Usage {
    Write-Host @'
usage: fdroid-tester.ps1 MR_URL_OR_NUMBER [options]
       fdroid-tester.ps1 -Apk FILE [MR_URL_OR_NUMBER] [options]
       fdroid-tester.ps1 -Check [-Serial SERIAL]

  -Serial SERIAL (-s)   choose an adb device
  -Watch SECONDS (-w)   startup watch, default 15 seconds
  -NoDevice            inspect only; device questions remain unverified
  -Keep                leave the app installed without a removal prompt
  -Vpn (--vpn)         force PCAPdroid VPN mode on a rooted device
  -Apk FILE (--apk FILE) use a local APK; without an MR, no GitLab lookup/posting
  -Check               check tools/device; may offer to install PCAPdroid
  -Version             print the version
  -Help (-h)           show this help

Bash-style long flags (--apk, --check, --no-device, etc.) are also accepted.
Capture: without --vpn, a rooted device records in root mode.
The APK is downloaded into the current directory. Evidence is saved beside it
in <appid>_<versionCode>-review/. Run in an interactive terminal.
Optional key files: pcapdroid-api-key and virustotal-api-key in the config
folder (%APPDATA%\fdroid-tester on Windows, or $XDG_CONFIG_HOME/fdroid-tester).
'@
}

# Parse explicitly so both PowerShell names and existing Bash-style flags work.
try {
    for ($i = 0; $i -lt $Cli.Count; $i++) {
        $option = $Cli[$i].ToLowerInvariant()
        switch ($option) {
            { $_ -in '-serial', '-s', '-watch', '-w', '-apk', '--apk' } {
                if ($i + 1 -ge $Cli.Count) { throw "$($Cli[$i]) needs a value" }
                $value = $Cli[++$i]
                if ($option -in '-serial', '-s') { $Serial = $value }
                elseif ($option -in '-watch', '-w') {
                    if ($value -notmatch '^\d+$' -or -not [int]::TryParse($value, [ref]$Watch)) {
                        throw '-w wants a number of seconds'
                    }
                } else {
                    if (-not (Test-Path -LiteralPath $value -PathType Leaf) -or (Get-Item -LiteralPath $value).Length -eq 0) {
                        throw "no such APK: $value"
                    }
                    $ApkArgument = (Resolve-Path -LiteralPath $value).ProviderPath
                }
            }
            { $_ -in '-nodevice', '--no-device' } { $NoDevice = $true }
            { $_ -in '-keep', '--keep' } { $Keep = $true }
            { $_ -in '-vpn', '--vpn' } { $ForceVpn = $true }
            { $_ -in '-check', '--check' } { $CheckOnly = $true }
            { $_ -in '-version', '--version' } { Write-Host "fdroid-tester $Version"; exit 0 }
            { $_ -in '-help', '--help', '-h' } { Show-Usage; exit 0 }
            default {
                if ($Cli[$i].StartsWith('-')) { throw "unknown option: $($Cli[$i])" }
                if ($MrArgument) { throw 'one merge request at a time' }
                $MrArgument = $Cli[$i]
            }
        }
    }
} catch { [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)"); exit 2 }

if (-not $MrArgument -and -not $ApkArgument -and -not $CheckOnly) {
    Write-Host 'Choose an open fdroid/fdroiddata merge request and run this script with its URL:'
    Write-Host 'https://gitlab.com/fdroid/fdroiddata/-/merge_requests/?state=opened&label_name[]=review-requested'
    Show-Usage
    exit 0
}

function Step([string]$Text) { Write-Host "`n━━ $Text" -ForegroundColor Cyan }
function Say([string]$Text) { Write-Host "   $Text" }
function Warn([string]$Text) { Write-Host "   ! $Text" -ForegroundColor Yellow }
function Ok([string]$Text) { Write-Host "   ✓ $Text" -ForegroundColor Green }
function Act([string]$Text) { Write-Host "   ➜ $Text" -ForegroundColor Blue }
function Read-Answer {
    $answer = [Console]::ReadLine()
    if ($null -eq $answer) { throw 'end of input — this script needs an interactive terminal' }
    return $answer
}
function Confirm([string]$Question, [bool]$Default = $false) {
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    Write-Host "   $Question $hint " -NoNewline
    $answer = Read-Answer
    if (-not $answer) { return $Default }
    return $answer -match '^[yY]'
}
function Ask([string]$Question, [string]$Default = 's') {
    while ($true) {
        Write-Host "   $Question [y/n/s=skip, Enter=$Default] " -NoNewline
        $answer = Read-Answer
        if (-not $answer) { return $Default }
        if ($answer -match '^[yYnNsS]') { return $answer.Substring(0, 1).ToLowerInvariant() }
    }
}
function Find-Program([string[]]$Names) {
    foreach ($name in $Names) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    return ''
}

# ArgumentList preserves spaces without shell interpolation. Close child stdin:
# adb must never consume the tester's answers. Copy binary output as bytes;
# PowerShell's text pipeline/redirection can corrupt PNGs in older PS versions.
function Invoke-Native {
    param([string]$Executable, [string[]]$Arguments = @(), [string]$OutputPath = '')
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.WorkingDirectory = (Get-Location).ProviderPath
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $stream = $null
    try {
        [void]$process.Start()
        $process.StandardInput.Close()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if ($OutputPath) {
            $stream = [IO.File]::Create($OutputPath)
            $outputTask = $process.StandardOutput.BaseStream.CopyToAsync($stream)
        } else { $outputTask = $process.StandardOutput.ReadToEndAsync() }
        $process.WaitForExit()
        $outputTask.GetAwaiter().GetResult() | Out-Null
        $text = if ($OutputPath) { '' } else { $outputTask.Result }
        return [pscustomobject]@{ Code = $process.ExitCode; Text = $text; Error = $errorTask.GetAwaiter().GetResult() }
    } finally {
        if ($stream) { $stream.Dispose() }
        $process.Dispose()
    }
}
function Adb([string[]]$Arguments, [string]$OutputPath = '') {
    $parameters = @()
    if ($Serial) { $parameters += @('-s', $Serial) }
    $parameters += $Arguments
    return Invoke-Native -Executable $AdbProgram -Arguments $parameters -OutputPath $OutputPath
}
function Shell([string[]]$Arguments) { return (Adb -Arguments (@('shell') + $Arguments)).Text.Replace("`r", '').TrimEnd("`n") }
function Curl([string[]]$Arguments) { return Invoke-Native -Executable $CurlProgram -Arguments $Arguments }
function Read-Json([string]$Path) { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable }
function Write-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false)) }
function Read-Key([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $line = Get-Content -LiteralPath $Path -TotalCount 1
    if ($null -eq $line) { return '' }
    return $line.Trim()
}
function Field([string]$Text, [string]$Pattern) {
    $match = [regex]::Match($Text, $Pattern, [Text.RegularExpressions.RegexOptions]::Multiline)
    if ($match.Success) { return $match.Groups[1].Value }
    return ''
}
function Apk-Abis([string]$Path) {
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        return @($zip.Entries | ForEach-Object {
            if ($_.FullName -match '^lib/([^/]+)/') { $Matches[1] }
        } | Sort-Object -Unique)
    } finally { $zip.Dispose() }
}
function Abi-Rank([string[]]$Abis) {
    if ($Abis.Count -eq 0) { return 0 }
    if (-not $DeviceAbis) { return 1 }
    $rank = 1
    foreach ($abi in $DeviceAbis.Split(',')) {
        if ($abi -in $Abis) { return $rank }
        $rank++
    }
    return 999
}
function Capture-Running { return (Shell @('dumpsys', 'activity', 'services', $PcapPackage)) -match 'CaptureService' }
function Capture-Stop {
    [void](Shell (@('am', 'start', '-n', "$PcapPackage/.activities.CaptureCtrl", '-e', 'action', 'stop') + $ControlKey))
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        if (-not (Capture-Running)) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}
function Open-Url([string]$Url) {
    try {
        if ($IsWindows) { Start-Process $Url | Out-Null }
        elseif ($IsMacOS) { [void](Invoke-Native -Executable (Find-Program @('open')) -Arguments @($Url)) }
        elseif ($env:DISPLAY -or $env:WAYLAND_DISPLAY) { [void](Invoke-Native -Executable (Find-Program @('xdg-open')) -Arguments @($Url)) }
        else { return $false }
        return $true
    } catch { return $false }
}

$Work = ''; $StayAwake = ''; $ScanJob = $null; $ControlKey = @()
$AdbProgram = ''; $DeviceAbis = ''; $DeviceSdk = ''; $DeviceDescription = ''
$PcapOk = $false; $RootCapture = $false; $CanPost = $false
$CacheRoot = if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } elseif ($IsWindows) { $env:LOCALAPPDATA } else { Join-Path $env:HOME '.cache' }
$ConfigRoot = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } elseif ($IsWindows) { $env:APPDATA } else { Join-Path $env:HOME '.config' }
$Cache = Join-Path $CacheRoot 'fdroid-tester'
$Config = Join-Path $ConfigRoot 'fdroid-tester'
$TrackerPath = Join-Path $Cache 'trackers.json'
$PcapKeyFile = Join-Path $Config 'pcapdroid-api-key'
$VtKeyFile = Join-Path $Config 'virustotal-api-key'

try {
    Step '0. Checks'
    $failures = 0
    function Row([string]$State, [string]$Name, [string]$Detail) {
        $mark = switch ($State) { 'ok' { '✓' }; 'warn' { '!' }; 'fail' { '✗' }; default { '·' } }
        Write-Host ('   {0} {1,-11} {2}' -f $mark, $Name, $Detail)
        if ($State -eq 'fail') { $script:failures++ }
    }
    Row ok PowerShell $PSVersionTable.PSVersion.ToString()
    $CurlProgram = Find-Program @('curl.exe', 'curl')
    if ($CurlProgram) { Row ok curl $CurlProgram } else { Row fail curl 'curl.exe is needed (included with current Windows)' }
    $PythonProgram = ''; $PythonPrefix = @()
    foreach ($candidate in @('python3', 'python', 'py')) {
        $program = Find-Program @($candidate)
        if (-not $program) { continue }
        $prefix = if ($candidate -eq 'py') { @('-3') } else { @() }
        $result = Invoke-Native -Executable $program -Arguments ($prefix + @('-c', 'import sys; sys.exit(sys.version_info < (3, 6))'))
        if ($result.Code -eq 0) { $PythonProgram = $program; $PythonPrefix = $prefix; break }
    }
    if ($PythonProgram) { Row ok python3 $PythonProgram } else { Row fail python3 'Python 3.6 or newer is needed' }
    $Sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($IsWindows) { Join-Path $env:LOCALAPPDATA 'Android\Sdk' } else { Join-Path $env:HOME 'Android/Sdk' }
    $AaptProgram = Find-Program @('aapt2.exe', 'aapt2')
    if (-not $AaptProgram -and (Test-Path -LiteralPath (Join-Path $Sdk 'build-tools'))) {
        $directories = Get-ChildItem -LiteralPath (Join-Path $Sdk 'build-tools') -Directory | Sort-Object { [version]($_.Name -replace '-.*$', '') } -Descending
        foreach ($directory in $directories) {
            $candidate = Join-Path $directory.FullName $(if ($IsWindows) { 'aapt2.exe' } else { 'aapt2' })
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $AaptProgram = $candidate; break }
        }
    }
    if ($AaptProgram) { Row ok aapt2 $AaptProgram } else { Row fail aapt2 'not found — install Android SDK Build-Tools or set ANDROID_HOME' }
    $LocalOnly = $ApkArgument -and -not $MrArgument
    if ($LocalOnly) { Row info gitlab.com 'not needed without a merge request' }
    elseif ($CurlProgram -and (Curl @('-fsS', '-m', '20', '-o', $(if ($IsWindows) { 'NUL' } else { '/dev/null' }), "$Api/projects/$Project")).Code -eq 0) { Row ok gitlab.com 'reachable' }
    else { Row fail gitlab.com "cannot reach $Api" }
    [void][IO.Directory]::CreateDirectory($Cache)
    if ($CurlProgram -and (-not (Test-Path -LiteralPath $TrackerPath) -or (Get-Item -LiteralPath $TrackerPath).LastWriteTime -lt (Get-Date).AddDays(-7))) {
        $part = "$TrackerPath.part"
        if ((Curl @('-fsS', '-m', '30', '-o', $part, 'https://reports.exodus-privacy.eu.org/api/trackers')).Code -eq 0) {
            Move-Item -LiteralPath $part -Destination $TrackerPath -Force
        } elseif (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part }
    }
    $trackerCount = -1
    try { $trackerCount = (Read-Json $TrackerPath)['trackers'].Count } catch { }
    if ($trackerCount -ge 0) { Row ok Exodus "$trackerCount trackers in the list" } else { Row warn Exodus 'could not fetch the tracker list — the tracker check is off' }

    $missingDevice = $false; $pcapNeeded = $false
    if ($NoDevice) { Row info device 'skipped (--no-device)' }
    else {
        $AdbProgram = Find-Program @('adb.exe', 'adb')
        if (-not $AdbProgram) { Row warn adb 'not installed — the device part is off'; $missingDevice = $true }
        else {
            [void](Adb @('start-server'))
            Row ok adb (Adb @('version')).Text.Trim()
            $devices = @()
            foreach ($line in ((Adb @('devices')).Text -split '\r?\n')) {
                if ($line -match '^(\S+)\s+(device|unauthorized|offline|recovery|bootloader)\b') {
                    $devices += @{ Serial = $Matches[1]; State = $Matches[2] }
                }
            }
            $state = ''
            if ($Serial) { foreach ($device in $devices) { if ($device.Serial -eq $Serial) { $state = $device.State } } }
            elseif ($devices.Count -gt 1) { $state = 'many' }
            elseif ($devices.Count -eq 1) { $state = $devices[0].State }
            switch ($state) {
                'device' {
                    $DeviceAbis = Shell @('getprop', 'ro.product.cpu.abilist')
                    $DeviceSdk = Shell @('getprop', 'ro.build.version.sdk')
                    $DeviceDescription = '{0} {1}, Android {2} (SDK {3})' -f (Shell @('getprop', 'ro.product.manufacturer')), (Shell @('getprop', 'ro.product.model')), (Shell @('getprop', 'ro.build.version.release')), $DeviceSdk
                    Row ok device "$DeviceDescription — $DeviceAbis"
                    $info = Shell @('dumpsys', 'package', $PcapPackage)
                    $pcapCode = Field $info 'versionCode=(\d+)'
                    $pcapVersion = Field $info 'versionName=(\S+)'
                    if (-not $pcapCode -or [int]$pcapCode -lt 62) { Row warn PCAPdroid 'missing or too old — the network check needs it'; $pcapNeeded = $true }
                    else { $PcapOk = $true; Row ok PCAPdroid "$pcapVersion — allow its control prompt on the device" }
                    if ($ForceVpn) { Row info root 'not used (--vpn)' }
                    elseif (Shell @('command', '-v', 'su')) { $RootCapture = $true; Row ok root 'yes — PCAPdroid records in root mode, no VPN prompt' }
                    else { Row info root 'no — PCAPdroid records through its VPN' }
                }
                'unauthorized' { Row fail device 'has not allowed this computer — accept the USB debugging prompt' }
                'offline' { Row fail device 'offline — reconnect it' }
                'many' { Row fail device 'multiple devices connected — pick one with -s' }
                '' {
                    if ($Serial) { Row fail device "$Serial is not connected" }
                    else { Row warn device 'none connected — plug it in with USB debugging on'; $missingDevice = $true }
                }
                default { Row fail device "device is in state '$state'" }
            }
        }
    }
    $GlabProgram = Find-Program @('glab.exe', 'glab')
    if ($LocalOnly) { Row info glab 'not needed without a merge request' }
    elseif (-not $GlabProgram) { Row warn glab 'not installed — paste the report yourself' }
    elseif ((Invoke-Native $GlabProgram @('auth', 'status', '--hostname', 'gitlab.com')).Code -ne 0) { Row warn glab 'not logged in — run glab auth login --hostname gitlab.com' }
    else {
        try {
            $user = (Invoke-Native $GlabProgram @('api', 'user')).Text | ConvertFrom-Json -AsHashtable
            if ($user['username']) { $CanPost = $true; Row ok glab "logged in as @$($user['username'])" }
            else { Row warn glab "the API refused — the token needs the 'api' scope" }
        } catch { Row warn glab "the API refused — the token needs the 'api' scope" }
    }
    $EditorProgram = ''
    foreach ($editor in @($env:VISUAL, $env:EDITOR, $(if ($IsWindows) { 'notepad.exe' } else { 'nano' }), 'vi')) {
        if ($editor) { $EditorProgram = Find-Program @($editor); if ($EditorProgram) { break } }
    }
    if ($EditorProgram) { Row ok editor $EditorProgram } else { Row warn editor 'none found — edit report.md manually before sharing' }
    if (Read-Key $VtKeyFile) { Row ok VirusTotal 'API key set — scanned automatically' } else { Row ok VirusTotal 'opens in your browser at the end' }
    if ($failures -gt 0) { throw 'fix the ✗ lines above, then run again' }

    if ($pcapNeeded) {
        Act "https://f-droid.org/packages/$PcapPackage/"
        if (Confirm 'Or install the latest version from GitHub onto the device now?' $true) {
            $releaseResult = Curl @('-fsS', '-m', '30', 'https://api.github.com/repos/emanuele-f/PCAPdroid/releases/latest')
            if ($releaseResult.Code -eq 0) {
                $release = $releaseResult.Text | ConvertFrom-Json -AsHashtable
                $asset = @($release['assets'] | Where-Object { $_['name'].EndsWith('.apk') } | Select-Object -First 1)
                if ($asset.Count) {
                    $download = Join-Path $Cache $asset[0]['name']
                    if ((Curl @('-fL', '-o', "$download.part", $asset[0]['browser_download_url'])).Code -eq 0) {
                        Move-Item -LiteralPath "$download.part" -Destination $download -Force
                        $identity = (Invoke-Native $AaptProgram @('dump', 'badging', $download)).Text
                        if ((Field $identity "^package: name='([^']+)'") -ne $PcapPackage) { throw 'the download is not PCAPdroid — not installing it' }
                        $install = Adb @('install', '-r', $download)
                        if ($install.Code -ne 0 -and ($install.Text + $install.Error) -match 'UPDATE_INCOMPATIBLE') {
                            if (Confirm 'Uninstall it and install the GitHub one? (its settings are lost)') {
                                [void](Adb @('uninstall', $PcapPackage)); $install = Adb @('install', $download)
                            }
                        }
                        if ($install.Code -eq 0) { $PcapOk = $true; Ok 'PCAPdroid installed' } else { Warn 'PCAPdroid install failed — carrying on without capture' }
                    } else { Warn 'PCAPdroid download failed' }
                } else { Warn 'the latest release has no APK' }
            } else { Warn 'could not reach GitHub' }
        }
    }
    if ($CheckOnly) { Ok 'ready'; exit 0 }
    if ($missingDevice) {
        if (-not (Confirm 'Carry on with the checks that need no device?' $true)) { exit 1 }
        $NoDevice = $true
    }
    $Work = Join-Path ([IO.Path]::GetTempPath()) ('fdroid-tester-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($Work)
    if (-not $NoDevice) {
        $StayAwake = Shell @('settings', 'get', 'global', 'stay_on_while_plugged_in')
        if ($StayAwake -match '^\d+$') {
            [void](Shell @('svc', 'power', 'stayon', 'true'))
            [void](Shell @('input', 'keyevent', 'KEYCODE_WAKEUP'))
        } else { $StayAwake = '' }
    }
    # Keep this Python helper in sync with the embedded helper in fdroid-tester.sh.
    # It uses only the standard library; the rest of the workflow is PowerShell.
    $HelperSource = @'
import json, re, struct, sys, zipfile

def out(*cols):
    print("\t".join(str(c).replace("\t", " ").replace("\n", " ") for c in cols))

# --- mr <mr.json>: shell assignments
def cmd_mr(path):
    import shlex
    m = json.load(open(path))
    vals = {
        "MR_TITLE": m.get("title", ""), "MR_STATE": m.get("state", ""),
        "MR_AUTHOR": (m.get("author") or {}).get("username", ""),
        "MR_LABELS": ",".join(m.get("labels") or []), "MR_URL": m.get("web_url", ""),
        "MR_SHA": m.get("sha") or "", "MR_SRC": m.get("source_project_id") or "",
    }
    for k, v in vals.items():
        print(f"{k}={shlex.quote(str(v))}")

# --- cq <codequality.json>: APK / PERM / WARN / SUMMARY lines
def cmd_cq(path):
    d = json.load(open(path))
    seen = set()
    for key in ("new_errors", "existing_errors"):
        for e in d.get(key) or []:
            desc = (e.get("description") or "").strip()
            sev = e.get("severity") or "-"
            if desc in seen:
                continue
            seen.add(desc)
            m = re.match(r"(Signed APK|Reproducible build APK): (\S+)", desc)
            if m:
                out("APK", m.group(2)); continue
            if desc.startswith("Permission "):
                out("PERM", sev, desc.split(" ", 1)[1]); continue
            m = re.match(r"Fastlane/Triple-T in en-US: summary \((.*?)\), name", desc)
            if m:
                out("SUMMARY", m.group(1)); continue
            if sev != "info":
                out("WARN", sev, desc[:300])

# --- static <apk> <trackers.json> <abi or ->: what the code holds
NOISE = re.compile(r"""^(schemas\.android\.com|www\.w3\.org|ns\.adobe\.com|xml\.org|
  (www\.)?apache\.org|xmlpull\.org|json-schema\.org|(www\.)?example\.(com|org|net)|
  localhost|schemas\.microsoft\.com|purl\.org|xmlns\.com|schema\.org|(www\.)?xmlsoap\.org|
  .*\.xsd|[0-9.]+|ns\.android\.com|developer\.android\.com|.*\.googlesource\.com|
  (www\.)?opensource\.org|(www\.)?gnu\.org|issuetracker\.google\.com|goo\.gle|
  (www\.)?unicode\.org|(www\.)?ietf\.org|tools\.ietf\.org)$""", re.X)

def flag_host(host, path, net_sigs):
    if host in ("fonts.googleapis.com", "fonts.gstatic.com"):
        return "online fonts"
    if host == "api.github.com" or "/releases/latest" in (path or ""):
        return "update check?"
    if "generate_204" in (path or "") or host.startswith("connectivitycheck."):
        return "connectivity check"
    for name, rx in net_sigs:
        if rx.search(host):
            return "tracker: " + name
    for dom, name in KNOWN:
        if host == dom or host.endswith("." + dom):
            return "tracker: " + name
    return ""

# Well-known tracker addresses the Exodus network rules do not cover.
KNOWN = (("app-measurement.com", "Google Firebase Analytics"), ("crashlytics.com", "Crashlytics"),
         ("doubleclick.net", "Google Ads"), ("googlesyndication.com", "Google Ads"),
         ("googleadservices.com", "Google Ads"), ("graph.facebook.com", "Facebook SDK"))

# Some Exodus network rules are as broad as "\.google\.com"; a rule that also
# matches these ordinary addresses would flag every app, so it is left out.
COMMON = ("www.google.com", "maps.google.com", "fonts.googleapis.com", "www.gstatic.com",
          "github.com", "api.github.com", "www.facebook.com", "play.google.com")

def load_trackers(path):
    code, net = [], []
    try:
        t = json.load(open(path)).get("trackers", {})
    except Exception:
        return code, net
    for tr in t.values():
        for sig, lst in ((tr.get("code_signature"), code), (tr.get("network_signature"), net)):
            if sig and len(sig) > 3:
                try:
                    rx = re.compile(sig, re.M)
                    if lst is net and any(rx.search(h) for h in COMMON):
                        continue
                    lst.append((tr["name"], rx))
                except re.error:
                    pass
    return code, net

def cmd_static(apk, trackers, abi):
    z = zipfile.ZipFile(apk)
    names = z.namelist()
    code_sigs, net_sigs = load_trackers(trackers)
    classes, blobs = set(), []
    for n in names:
        if re.fullmatch(r"classes\d*\.dex", n):
            b = z.read(n); blobs.append(b)
            for m in re.finditer(rb"L([A-Za-z0-9_$/]{3,200});", b):
                classes.add(m.group(1).decode().replace("/", "."))
    if "resources.arsc" in names:
        blobs.append(z.read("resources.arsc"))
    flutter = [n for n in names if n.endswith("/libapp.so")]
    pick = [n for n in flutter if abi != "-" and n.startswith(f"lib/{abi}/")] or flutter[:1]
    for n in pick:
        blobs.append(z.read(n))
    if flutter:
        out("FLUTTER", "yes")
    text = "\n".join(sorted(classes))
    for name, rx in code_sigs:
        m = rx.search(text)
        if m:
            line = text[text.rfind("\n", 0, m.start()) + 1: text.find("\n", m.start())]
            out("TRACKER", name, line)
    for cls, why in (("com.google.android.gms.", "Google Play Services"),
                     ("com.google.firebase.", "Firebase")):
        if cls in text:
            out("NONFREE", why)
    if re.search(r"^android\.webkit\.WebView$", text, re.M):
        out("WEBVIEW", "android.webkit.WebView")
    if re.search(r"^(io\.flutter\.plugins\.webviewflutter|org\.mozilla\.geckoview)\.", text, re.M):
        out("WEBVIEW", "embedded browser library")
    hosts = {}
    for b in blobs:
        for m in re.finditer(rb"https?://([A-Za-z0-9][A-Za-z0-9.-]{2,252}\.[A-Za-z]{2,24})(/[\x21-\x7e]{0,200})?", b):
            host = m.group(1).decode().lower()
            path = (m.group(2) or b"").decode(errors="replace")
            if NOISE.match(host):
                continue
            f = flag_host(host, path, net_sigs)
            if host not in hosts or (f and not hosts[host]):
                hosts[host] = f
        if b"generate_204" in b and not any(v == "connectivity check" for v in hosts.values()):
            out("HINT", "connectivity check", "the code holds 'generate_204'")
    for h in sorted(hosts):
        out("HOST", h, hosts[h])

# --- pcap <file> <t_launch> <t_start_end> <trackers.json>: CONN lines
def dns_name(p, off, depth=0):
    labels = []
    if depth > 10:
        return "", off
    while off < len(p):
        n = p[off]
        if n == 0:
            off += 1; break
        if n & 0xC0 == 0xC0:
            if off + 1 >= len(p): break
            ptr = ((n & 0x3F) << 8) | p[off + 1]
            name, _ = dns_name(p, ptr, depth + 1)
            labels.append(name); off += 2
            return ".".join(l for l in labels if l), off
        labels.append(p[off + 1: off + 1 + n].decode(errors="replace")); off += 1 + n
    return ".".join(labels), off

def parse_dns(p, ipmap, names, ts):
    if len(p) < 12: return
    qd, an = struct.unpack("!HH", p[4:8])
    off, qname = 12, ""
    for _ in range(qd):
        qname, off = dns_name(p, off); off += 4
        if qname: names.setdefault(qname.lower(), ts)
    for _ in range(an):
        if off + 10 > len(p): return
        _, off = dns_name(p, off)
        typ, _, _, rdlen = struct.unpack("!HHIH", p[off:off + 10]); off += 10
        rd = p[off:off + rdlen]; off += rdlen
        if qname and typ == 1 and rdlen == 4:
            ipmap[".".join(map(str, rd))] = qname.lower()
        elif qname and typ == 28 and rdlen == 16:
            import ipaddress
            ipmap[str(ipaddress.IPv6Address(rd))] = qname.lower()

def tls_sni(p):
    try:
        if len(p) < 43 or p[0] != 0x16 or p[5] != 0x01: return None
        off = 43
        off += 1 + p[off]                                   # session id
        off += 2 + struct.unpack("!H", p[off:off + 2])[0]   # cipher suites
        off += 1 + p[off]                                   # compression
        end = off + 2 + struct.unpack("!H", p[off:off + 2])[0]; off += 2
        while off + 4 <= min(end, len(p)):
            et, el = struct.unpack("!HH", p[off:off + 4]); off += 4
            if et == 0:
                n = struct.unpack("!H", p[off + 3:off + 5])[0]
                return p[off + 5:off + 5 + n].decode(errors="replace").lower()
            off += el
    except (IndexError, struct.error):
        pass
    return None

def cmd_pcap(path, t_launch, t_end, trackers):
    import ipaddress
    t_launch, t_end = float(t_launch), float(t_end)
    _, net_sigs = load_trackers(trackers)
    data = open(path, "rb").read()
    if not data:
        out("NONE", "no packets"); return     # the header comes with the first packet
    if len(data) < 24:
        out("ERROR", "the capture file is cut short"); return
    magic = data[:4]
    if magic == b"\x0a\x0d\x0d\x0a":
        out("ERROR", "pcapng is not supported — switch PCAPdroid back to plain PCAP"); return
    end = "<" if magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1") else ">"
    nano = magic in (b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\x3c\x4d")
    link = struct.unpack(end + "I", data[20:24])[0]
    off, ipmap, names, flows = 24, {}, {}, {}
    while off + 16 <= len(data):
        sec, frac, incl, _ = struct.unpack(end + "IIII", data[off:off + 16]); off += 16
        pkt = data[off:off + incl]; off += incl
        ts = sec + frac / (1e9 if nano else 1e6)
        if link == 1:
            if len(pkt) < 14: continue
            pkt = pkt[14:]
        elif link == 113:
            pkt = pkt[16:]
        if not pkt: continue
        ver = pkt[0] >> 4
        if ver == 4 and len(pkt) >= 20:
            ihl = (pkt[0] & 15) * 4; proto = pkt[9]
            src, dst = str(ipaddress.IPv4Address(pkt[12:16])), str(ipaddress.IPv4Address(pkt[16:20]))
            l4 = pkt[ihl:]
        elif ver == 6 and len(pkt) >= 40:
            proto = pkt[6]
            src, dst = str(ipaddress.IPv6Address(pkt[8:24])), str(ipaddress.IPv6Address(pkt[24:40]))
            l4 = pkt[40:]
        else:
            continue
        if proto == 17 and len(l4) >= 8:
            sp, dp = struct.unpack("!HH", l4[:4]); pay = l4[8:]
            if 53 in (sp, dp):
                parse_dns(pay, ipmap, names, ts); continue
        elif proto == 6 and len(l4) >= 20:
            sp, dp = struct.unpack("!HH", l4[:4]); pay = l4[(l4[12] >> 4) * 4:]
        else:
            continue
        key = (proto, frozenset(((src, sp), (dst, dp))))
        if key not in flows:
            flows[key] = {"ts": ts, "dst": dst, "port": dp, "name": None}
        f = flows[key]
        if pay and not f["name"]:
            sni = tls_sni(pay)
            if sni:
                f["name"] = sni
            else:
                m = re.match(rb"(GET|POST|PUT|HEAD|DELETE|OPTIONS|PATCH) [^\r\n]*\r\n(?:.*\r\n)*?[Hh]ost: ([^\r\n:]+)", pay)
                if m:
                    f["name"] = m.group(2).decode(errors="replace").lower() + " (plain http!)"
    seen = {}
    for f in flows.values():
        name = f["name"] or ipmap.get(f["dst"]) or f"{f['dst']}:{f['port']}"
        seen[name] = min(f["ts"], seen.get(name, f["ts"]))
    for n, ts in names.items():
        if not any(k.startswith(n) for k in seen):
            seen[n + " (looked up)"] = ts
    if not seen:
        out("NONE", "no connections"); return
    for name, ts in sorted(seen.items(), key=lambda kv: kv[1]):
        when = "start" if ts <= t_end else "later"
        out("CONN", when, name, flag_host(name.split(" ")[0], "", net_sigs))

# --- vt <response.json>
def cmd_vt(path):
    a = json.load(open(path)).get("data", {}).get("attributes", {})
    if "last_analysis_stats" in a:        # a file report: already scanned
        st, status = a["last_analysis_stats"], "completed"
    else:                                 # an analysis: queued, in-progress, completed
        st, status = a.get("stats", {}), a.get("status", "queued")
    out("VT", status, st.get("malicious", 0), st.get("suspicious", 0),
        st.get("harmless", 0) + st.get("undetected", 0))

# --- jget <file> <key path…>: one value out of a JSON file
def cmd_jget(path, *keys):
    v = json.load(open(path))
    for k in keys:
        v = v.get(k, {}) if isinstance(v, dict) else {}
    print(v if isinstance(v, str) else "")

# --- cats <metadata.yml>
def cmd_cats(path):
    cats, on = [], False
    for line in open(path, encoding="utf-8", errors="replace"):
        if re.match(r"^Categories:", line):
            on = True; continue
        if on:
            m = re.match(r"^\s*-\s*(.+?)\s*$", line)
            if m: cats.append(m.group(1)); continue
            break
    print(", ".join(cats))

# --- embed <report.md> <uploads.tsv> <folder>: the report as posted, its
# screenshot lines turned into images (uploads.tsv: file<TAB>path on gitlab.com)
def png_size(path):
    try:
        with open(path, "rb") as f:
            head = f.read(24)
    except OSError:
        return 0, 0
    if len(head) < 24 or head[:8] != b"\x89PNG\r\n\x1a\n":   # cut short: no size
        return 0, 0
    return struct.unpack(">II", head[16:24])

def cmd_embed(report, uploads, folder):
    up = {}
    for line in open(uploads, encoding="utf-8", errors="replace"):
        f, _, path = line.rstrip("\n").partition("\t")
        if f and path:
            up[f] = path
    # a byte that is not UTF-8 (notes typed in another encoding) must not stop the post
    out = open(sys.stdout.fileno(), "w", encoding="utf-8", errors="replace", closefd=False)
    section = False                        # only the screenshot list is rewritten
    for line in open(report, encoding="utf-8", errors="replace"):
        if line.startswith("**Screenshots:**"):
            section = True
        elif line.startswith("<details>"):
            section = False
        m = section and re.match(r"- `([^`]+\.png)`(?: — (.*))?$", line.rstrip("\n"))
        if not m:
            out.write(line)
            continue
        f, cap = m.group(1), m.group(2) or ""
        text = cap or f
        shown = text.replace("\\", "\\\\").replace("`", "\\`")
        if f not in up:
            out.write(f"- {shown} _(screenshot could not be uploaded)_\n")
            continue
        url = up[f]
        if url.startswith("/-/"):          # uploaded to another project: a full address
            url = "https://gitlab.com" + url
        w, h = png_size(f"{folder}/{f}")
        # brackets, backticks and backslashes would end or swallow the image
        alt = text.translate(str.maketrans("[]`\\", "()'/"))
        out.write(f"- {shown}<br>![{alt}]({url}){{width={240 if h > w else 480}}}\n")
    out.flush()

{"mr": cmd_mr, "cq": cmd_cq, "static": cmd_static, "pcap": cmd_pcap,
 "vt": cmd_vt, "jget": cmd_jget, "cats": cmd_cats, "embed": cmd_embed}[sys.argv[1]](*sys.argv[2:])
'@
    $HelperPath = Join-Path $Work 'tool.py'
    Write-Utf8 $HelperPath $HelperSource
    function Helper([string[]]$Arguments) {
        $result = Invoke-Native -Executable $PythonProgram -Arguments ($PythonPrefix + @($HelperPath) + $Arguments)
        if ($result.Code -ne 0) { throw "APK/capture helper failed: $($result.Error)" }
        return $result.Text.TrimEnd("`r", "`n")
    }

    Step '1. Merge request'
    $Iid = ''; $MrUrl = ''; $MrSource = ''; $MrSha = ''; $Summary = ''
    $ApkUrls = @(); $CiWarnings = @(); $Categories = ''
    if (-not $MrArgument) { Say "none — testing $([IO.Path]::GetFileName($ApkArgument)) on its own" }
    else {
        if ($MrArgument -match '^\d+$') { $Iid = $MrArgument }
        elseif ($MrArgument -match '^(?:https?://)?gitlab\.com/fdroid/fdroiddata/-/merge_requests/(\d+)(?:[/?#].*)?$') { $Iid = $Matches[1] }
        else { throw "not an fdroiddata merge request: $MrArgument" }
        $mrPath = Join-Path $Work 'mr.json'
        if ((Curl @('-fsS', '-o', $mrPath, "$Api/projects/$Project/merge_requests/$Iid")).Code -ne 0) { throw "could not read merge request !$Iid" }
        $mr = Read-Json $mrPath
        $MrUrl = $mr['web_url']; $MrSource = [string]$mr['source_project_id']; $MrSha = [string]$mr['sha']
        Say "!$Iid $($mr['title'])"
        if ($mr['state'] -ne 'opened') { Warn 'this merge request is not open' }
        if ('review-requested' -in $mr['labels']) { Ok 'labelled review-requested: waiting for a tester' }
        $cqPath = Join-Path $Work 'codequality.json'
        $status = ''
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            $status = (Curl @('-sS', '-o', $cqPath, '-w', '%{http_code}', "https://gitlab.com/$Repo/-/merge_requests/$Iid/codequality_reports.json")).Text.Trim()
            if ($status -ne '204') { break }
            Start-Sleep -Seconds 3
        }
        if ($status -ne '200') { throw "no Code Quality report for !$Iid (HTTP $status) — has its pipeline run?" }
        foreach ($line in ((Helper @('cq', $cqPath)) -split '\r?\n')) {
            $columns = $line -split "`t"
            switch ($columns[0]) {
                'APK' { $ApkUrls += $columns[1] }
                'WARN' { $CiWarnings += "$($columns[1]): $($columns[2])" }
                'SUMMARY' { $Summary = $columns[1] }
            }
        }
        foreach ($warning in $CiWarnings) { Warn "CI: $warning" }
        if ($ApkUrls.Count -eq 0 -and -not $ApkArgument) { throw 'the report has no APK — the build failed or has not run' }
    }

    Step '2. APK'
    $Apk = ''; $ApkAbis = @(); $best = 999
    if ($ApkArgument) {
        $Apk = $ApkArgument; $ApkAbis = @(Apk-Abis $Apk)
        if ((Abi-Rank $ApkAbis) -eq 999) { throw "the APK does not run on this device ($DeviceAbis)" }
    } else {
        foreach ($url in $ApkUrls) {
            $file = Join-Path (Get-Location).ProviderPath ([IO.Path]::GetFileName(([uri]$url).AbsolutePath))
            $valid = $false
            if (Test-Path -LiteralPath $file) { try { $abis = @(Apk-Abis $file); $valid = $true } catch { } }
            if (-not $valid) {
                if ((Curl @('-fL', '-o', "$file.part", $url)).Code -ne 0) {
                    if (Test-Path -LiteralPath "$file.part") { Remove-Item -LiteralPath "$file.part" }
                    Warn 'could not download it — CI artifacts expire; ask the author to re-run the pipeline'; continue
                }
                Move-Item -LiteralPath "$file.part" -Destination $file -Force
                $abis = @(Apk-Abis $file)
            }
            $rank = Abi-Rank $abis
            if ($rank -lt $best) { $Apk = $file; $ApkAbis = $abis; $best = $rank }
        }
        if (-not $Apk) { throw "none of the APKs runs on this device ($DeviceAbis)" }
    }
    $badgingResult = Invoke-Native $AaptProgram @('dump', 'badging', $Apk)
    if ($badgingResult.Code -ne 0) { throw 'aapt2 could not read the APK' }
    $Badging = $badgingResult.Text
    $AppId = Field $Badging "^package: name='([^']+)'"
    $VersionCode = Field $Badging "^package: .*versionCode='([^']+)'"
    $VersionName = Field $Badging "^package: .*versionName='([^']+)'"
    if (-not $AppId -or -not $VersionCode) { throw 'APK has no readable package ID or version code' }
    $MinSdk = Field $Badging "^minSdkVersion:'([^']+)'"
    $TargetSdk = Field $Badging "^targetSdkVersion:'([^']+)'"
    $LaunchActivity = Field $Badging "^launchable-activity: name='([^']+)'"
    $TvActivity = Field $Badging "^leanback-launchable-activity: name='([^']+)'"
    $Locales = Field $Badging '^locales: (.*)'
    $Manifest = (Invoke-Native $AaptProgram @('dump', 'xmltree', '--file', 'AndroidManifest.xml', $Apk)).Text
    $Sha256 = (Get-FileHash -LiteralPath $Apk -Algorithm SHA256).Hash.ToLowerInvariant()
    $Out = Join-Path (Get-Location).ProviderPath "${AppId}_${VersionCode}-review"
    [void][IO.Directory]::CreateDirectory($Out)
    if ($Iid) { Copy-Item -LiteralPath $cqPath -Destination (Join-Path $Out 'codequality.json') }
    $NotFromCi = $false
    if ($ApkArgument -and $Iid -and "${AppId}_${VersionCode}.apk" -notin @($ApkUrls | ForEach-Object { [IO.Path]::GetFileName(([uri]$_).AbsolutePath) })) {
        $NotFromCi = $true; Warn "${AppId}_${VersionCode}.apk is not one this merge request's CI built — testing it anyway"
    }
    Say "$AppId $VersionName ($VersionCode) — minSdk $MinSdk, targetSdk $TargetSdk"
    Say "sha256 $Sha256"
    if ($DeviceSdk -and $MinSdk -and [int]$MinSdk -gt [int]$DeviceSdk) { throw "the app needs Android SDK $MinSdk, the device has $DeviceSdk" }
    $NoLeanback = $false
    if (-not $NoDevice -and $Badging -match "(?m)^\s*uses-feature: name='android.software.leanback'\r?$" -and (Shell @('pm', 'list', 'features')) -notmatch '(?m)^feature:android.software.leanback$') {
        $NoLeanback = $true; Warn 'this app requires Android TV, and this device does not declare it (android.software.leanback)'
        Say "F-Droid's client would hide the app on this device; installed with adb, it may still run"
        if (-not (Confirm 'Test it anyway?' $true)) { exit 1 }
    }

    Step '3. Inside the APK'
    $Permissions = @([regex]::Matches($Badging, "(?m)^uses-permission: name='([^']+)'") | ForEach-Object { $_.Groups[1].Value })
    $HasInternet = 'android.permission.INTERNET' -in $Permissions
    $SpecialPermissions = @($Permissions | Where-Object { $_ -match '^android\.permission\.(MANAGE_EXTERNAL_STORAGE|QUERY_ALL_PACKAGES|REQUEST_INSTALL_PACKAGES|ACCESS_BACKGROUND_LOCATION|SYSTEM_ALERT_WINDOW|WRITE_SETTINGS|PACKAGE_USAGE_STATS|READ_LOGS|BIND_ACCESSIBILITY_SERVICE|BIND_DEVICE_ADMIN)$' } | ForEach-Object { $_ -replace '^android\.permission\.', '' })
    $RuntimePermissions = @($Permissions | Where-Object { $_ -match '^android\.permission\.' -and $_ -match '(CAMERA|RECORD_AUDIO|_LOCATION$|_CONTACTS$|GET_ACCOUNTS|_CALENDAR$|_SMS$|RECEIVE_MMS|RECEIVE_WAP_PUSH|READ_PHONE_STATE|READ_PHONE_NUMBERS|CALL_PHONE|ANSWER_PHONE_CALLS|_CALL_LOG$|ADD_VOICEMAIL|USE_SIP|BODY_SENSORS|ACTIVITY_RECOGNITION|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|READ_MEDIA_|BLUETOOTH_(SCAN|CONNECT|ADVERTISE)|NEARBY_WIFI_DEVICES|UWB_RANGING|POST_NOTIFICATIONS)' } | ForEach-Object { $_ -replace '^android\.permission\.', '' })
    Say "$($Permissions.Count) permissions"
    foreach ($permission in $Permissions) { Say $permission }
    $Debuggable = $Badging -match '(?m)^application-debuggable' -or $Manifest -match 'debuggable\([^)]*\)=(true|0xffffffff)'
    $Cleartext = $Manifest -match 'usesCleartextTraffic\([^)]*\)=(true|0xffffffff)'
    if ($Debuggable) { Warn 'the APK is debuggable' }
    if ($Cleartext) { Warn 'plain http allowed (usesCleartextTraffic)' }
    if ($Manifest -match 'testOnly\([^)]*\)=(true|0xffffffff)') { Warn 'the APK is marked testOnly' }
    Say "languages: $Locales — verify English on the device"
    $primaryAbi = '-'
    foreach ($abi in $DeviceAbis.Split(',')) { if ($abi -in $ApkAbis) { $primaryAbi = $abi; break } }
    $StaticTrackers = @(); $NonFreeLibraries = @(); $Hosts = @(); $WebView = ''
    foreach ($line in ((Helper @('static', $Apk, $TrackerPath, $primaryAbi)) -split '\r?\n')) {
        $columns = $line -split "`t"
        switch ($columns[0]) {
            'TRACKER' { $StaticTrackers += "$($columns[1]) ($($columns[2]))"; Warn "tracker code: $($columns[1])" }
            'NONFREE' { $NonFreeLibraries += $columns[1]; Warn "non-free library hint: $($columns[1])" }
            'HOST' { $Hosts += $columns[1]; Say "web address in the code (not necessarily contacted): $($columns[1])" }
            'WEBVIEW' { $WebView = $columns[1]; Say "uses a WebView ($WebView) — check actual use" }
            'HINT' { Say "$($columns[1]): $($columns[2])" }
            'FLUTTER' { Say 'Flutter app — addresses also read from libapp.so' }
        }
    }
    if ($MrSource -and $MrSha) {
        $metadata = Join-Path $Work 'metadata.yml'
        if ((Curl @('-fsS', '-o', $metadata, "$Api/projects/$MrSource/repository/files/metadata%2F$AppId.yml/raw?ref=$MrSha")).Code -eq 0) {
            Copy-Item -LiteralPath $metadata -Destination (Join-Path $Out "$AppId.yml")
            $Categories = Helper @('cats', $metadata); Say "categories: $Categories"
        }
    }

    # VirusTotal lookup happens before device testing. An optional thread job
    # uploads/polls in parallel; no scan or upload is inferred from an unknown hash.
    $VtLink = "https://www.virustotal.com/gui/file/$Sha256"
    $VtApi = 'https://www.virustotal.com/api/v3'
    $VtResult = ''; $VtMalicious = -1; $VtKey = ''
    $VtKey = Read-Key $VtKeyFile
    $vtPath = Join-Path $Work 'vt.json'
    function Read-Vt([string]$Path) {
        $columns = (Helper @('vt', $Path)) -split "`t"
        if ($columns[1] -eq 'completed') {
            $script:VtMalicious = [int]$columns[2]
            $script:VtResult = "$($columns[2]) malicious, $($columns[3]) suspicious, $($columns[4]) clean"
            Say "VirusTotal: $VtResult"
        }
    }
    if ($VtKey) {
        $status = (Curl @('-sS', '-m', '60', '-o', $vtPath, '-w', '%{http_code}', '-H', "x-apikey: $VtKey", "$VtApi/files/$Sha256")).Text.Trim()
        if ($status -eq '200') { Read-Vt $vtPath }
        elseif ($status -eq '404') {
            $question = if ($ApkArgument) { 'VirusTotal has not seen this local file — upload it? VirusTotal shares uploads with its partners' } else { 'VirusTotal has not seen this APK — upload it for a scan?' }
            if (Confirm $question (-not [bool]$ApkArgument)) {
                $ScanJob = Start-ThreadJob -ArgumentList $CurlProgram, $Apk, $VtKey, $vtPath -ScriptBlock {
                    param($curlFile, $apkFile, $key, $resultFile)
                    $apiUrl = 'https://www.virustotal.com/api/v3'
                    $uploadUrl = "$apiUrl/files"
                    if ((Get-Item -LiteralPath $apkFile).Length -gt 33554432) {
                        $response = & $curlFile -fsS -m 60 -H "x-apikey: $key" "$apiUrl/files/upload_url" 2>$null
                        if ($LASTEXITCODE -ne 0) { throw 'could not get VirusTotal upload URL' }
                        $uploadUrl = ($response | ConvertFrom-Json).data
                    }
                    $response = & $curlFile -fsS -m 900 -H "x-apikey: $key" -F "file=@$apkFile" $uploadUrl 2>$null
                    if ($LASTEXITCODE -ne 0) { throw 'VirusTotal upload failed' }
                    $analysisId = ($response | ConvertFrom-Json).data.id
                    for ($attempt = 0; $attempt -lt 45; $attempt++) {
                        Start-Sleep -Seconds 20
                        $response = & $curlFile -fsS -m 60 -H "x-apikey: $key" "$apiUrl/analyses/$analysisId" 2>$null
                        if ($LASTEXITCODE -ne 0) { continue }
                        if (($response | ConvertFrom-Json).data.attributes.status -eq 'completed') {
                            [IO.File]::WriteAllText($resultFile, ($response -join "`n")); return
                        }
                    }
                    throw 'VirusTotal scan took longer than 15 minutes'
                }
                Ok 'uploading and scanning in the background — the result comes in later'
            }
        } else { Warn "VirusTotal lookup failed (HTTP $status) — check the link manually" }
    }

    $Crashed = 'n'; $Gone = $false; $StartPrompt = ''; $Captured = $false; $PcapError = ''
    $ConnectionsStart = @(); $ConnectionsLater = @(); $Shots = [Collections.Generic.List[object]]::new()
    $shotsFile = Join-Path $Out 'shots.tsv'; Write-Utf8 $shotsFile ''
    function Add-Shot([string]$File, [string]$Caption) {
        $Shots.Add(@{ File = $File; Caption = $Caption })
        [IO.File]::AppendAllText($shotsFile, "$File`t$Caption`n", [Text.UTF8Encoding]::new($false))
    }
    function Screenshot([string]$File, [string]$Caption) {
        $path = Join-Path $Out $File
        $result = Adb -Arguments @('exec-out', 'screencap', '-p') -OutputPath $path
        if ($result.Code -eq 0 -and (Get-Item -LiteralPath $path).Length -gt 0) { Add-Shot $File $Caption; return $true }
        Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
        return $false
    }
    function Check-Alive {
        if ($Crashed -ne 'n') { return }
        $crashBuffer = (Adb @('logcat', '-d', '-b', 'crash')).Text
        if ($crashBuffer.Contains("Process: $AppId")) {
            Write-Utf8 (Join-Path $Out 'crash.log') $crashBuffer
            Warn 'it crashed while you used it (crash.log saved)'; $script:Crashed = 'later'
        } elseif (Shell @('pidof', $AppId)) { $script:Gone = $false }
        elseif (-not $Gone) { $script:Gone = $true; Warn 'the app is not running any more — unless you closed it, it stopped unexpectedly' }
    }
    if (-not $NoDevice) {
        Step '4. On the device'
        $locked = (Shell @('dumpsys', 'window')) + (Shell @('dumpsys', 'activity', 'activities'))
        if ($locked -match '(mKeyguardShowing|isKeyguardShowing|mShowingLockscreen|mDreamingLockscreen)=true') {
            Act 'unlock the device — waiting'
            for ($attempt = 0; $attempt -lt 120; $attempt++) {
                if (((Shell @('dumpsys', 'window')) + (Shell @('dumpsys', 'activity', 'activities'))) -notmatch '(mKeyguardShowing|isKeyguardShowing|mShowingLockscreen|mDreamingLockscreen)=true') { break }
                Start-Sleep -Seconds 1
            }
        }
        if (Shell @('pm', 'path', $AppId)) {
            Warn "$AppId is already installed"
            if (Confirm 'Uninstall it first, for a clean first start? (its data is deleted)' $true) {
                if ((Adb @('uninstall', $AppId)).Code -ne 0) { throw 'could not uninstall it' }
            }
        }
        $install = Adb @('install', '-r', $Apk)
        if ($install.Code -ne 0) { throw "install failed: $($install.Text) $($install.Error)" }
        Ok 'installed'
        $pcapName = "fdroid-tester-$AppId.pcap"
        if ($HasInternet -and $PcapOk) {
            $pcapKey = Read-Key $PcapKeyFile
            if ($pcapKey) { $ControlKey = @('-e', 'api_key', $pcapKey) }
            [void](Shell @('rm', '-f', "/sdcard/Download/PCAPdroid/$pcapName"))
            if (Capture-Running) {
                Warn 'PCAPdroid is already recording — stopping its earlier capture'
                if ($ControlKey.Count -eq 0) { Act "on the device: allow PCAPdroid's prompt to stop its earlier capture" }
                if (-not (Capture-Stop)) { throw 'PCAPdroid is still recording an earlier capture — stop it in PCAPdroid, then run again' }
            }
            $mode = if ($RootCapture) { @('-e', 'root_capture', 'true') } else { @('-e', 'block_quic', 'always', '-e', 'auto_block_private_dns', 'true') }
            [void](Shell (@('am', 'start', '-n', "$PcapPackage/.activities.CaptureCtrl", '-e', 'action', 'start', '-e', 'pcap_dump_mode', 'pcap_file', '-e', 'pcap_name', $pcapName, '-e', 'app_filter', $AppId) + $mode + $ControlKey))
            Act "on the device: allow PCAPdroid's control and VPN/root prompts"
            for ($attempt = 0; $attempt -lt 90; $attempt++) {
                if (Capture-Running) { $Captured = $true; break }
                Start-Sleep -Seconds 1
            }
            if ($Captured) { Ok 'PCAPdroid is recording' }
            else {
                Warn 'PCAPdroid did not start within 90 seconds'
                if (-not (Confirm 'Carry on without the network check?' $true)) { throw 'start PCAPdroid by hand, then run again' }
            }
        } elseif ($HasInternet) { Warn 'no network check — PCAPdroid is missing or too old' }
        [void](Adb @('logcat', '-c'))
        $launchTime = Shell @('date', '+%s')
        if (-not $LaunchActivity -and $TvActivity) {
            $launch = Adb @('shell', 'am', 'start', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.LEANBACK_LAUNCHER', '-n', "$AppId/$TvActivity")
            if ($launch.Code -ne 0) { Warn 'could not open its TV activity — open it by hand' }
        } else {
            $launch = Adb @('shell', 'monkey', '-p', $AppId, '-c', 'android.intent.category.LAUNCHER', '1')
            if ($launch.Text -match 'No activities found') { Warn 'the app has no launcher icon to open — open it by hand' }
        }
        Act "watching the first $Watch seconds — don't touch the device yet"
        for ($second = 0; $second -lt $Watch; $second++) {
            Start-Sleep -Seconds 1
            if (-not $StartPrompt -and (Shell @('dumpsys', 'window')) -match 'mCurrentFocus=.*GrantPermissionsActivity') {
                [void](Shell @('uiautomator', 'dump', '/sdcard/fdroid-tester.xml'))
                $xml = Shell @('cat', '/sdcard/fdroid-tester.xml')
                $StartPrompt = Field $xml 'text="([^"]*)" resource-id="[^"]*permission_message"'
                [void](Shell @('rm', '-f', '/sdcard/fdroid-tester.xml'))
                if (-not $StartPrompt) { $StartPrompt = 'a permission prompt' }
                [void](Screenshot 'permission-on-start.png' 'permission prompt on start')
            }
        }
        $watchEnd = Shell @('date', '+%s')
        [void](Screenshot "after-${Watch}s.png" "after $Watch seconds")
        $crashBuffer = (Adb @('logcat', '-d', '-b', 'crash')).Text
        if (-not (Shell @('pidof', $AppId)) -or $crashBuffer.Contains("Process: $AppId")) {
            $Crashed = 'y'; Write-Utf8 (Join-Path $Out 'crash.log') $crashBuffer
            Warn "the app is not running after $Watch seconds — it probably crashed"
        } else { Ok "still running after $Watch seconds" }
        if ($StartPrompt) { Warn "asks for a permission on start: $StartPrompt" }
        Act "Now use the app. $Summary"
        Say 'Try main features; deny optional permissions; inspect terms, settings, language and links.'
        Act 's + Enter: take a screenshot · Enter: done'
        while ($true) {
            Write-Host '   ➜ ' -NoNewline
            $line = Read-Answer
            if (-not $line) { break }
            if ($line -match '^[sS]$') {
                $number = 1
                do { $file = 'shot-{0:d2}.png' -f $number; $number++ } while (Test-Path -LiteralPath (Join-Path $Out $file))
                # Write binary bytes first, then ask for the caption, as in Bash.
                $result = Adb -Arguments @('exec-out', 'screencap', '-p') -OutputPath (Join-Path $Out $file)
                if ($result.Code -eq 0 -and (Get-Item -LiteralPath (Join-Path $Out $file)).Length -gt 0) {
                    Write-Host '   caption (Enter for none): ' -NoNewline
                    $caption = Read-Answer; Add-Shot $file $caption; Ok "saved $file"; Check-Alive
                } else { Remove-Item -LiteralPath (Join-Path $Out $file) -ErrorAction SilentlyContinue; Warn 'the screenshot failed' }
            } else { Say 's + Enter takes a screenshot; Enter alone when you are done' }
        }
        Check-Alive
        if ($Captured) {
            if ($ControlKey.Count -eq 0) { Act "on the device: allow PCAPdroid's prompt to stop the capture" }
            if (-not (Capture-Stop)) { Warn 'PCAPdroid is still recording — stop it in the app; the file may be cut short' }
            $trafficPath = Join-Path $Out 'traffic.pcap'
            if ((Adb @('pull', "/sdcard/Download/PCAPdroid/$pcapName", $trafficPath)).Code -eq 0) {
                [void](Shell @('rm', '-f', "/sdcard/Download/PCAPdroid/$pcapName"))
                foreach ($line in ((Helper @('pcap', $trafficPath, $launchTime, $watchEnd, $TrackerPath)) -split '\r?\n')) {
                    $columns = $line -split "`t"
                    if ($columns[0] -eq 'CONN') {
                        $destination = $columns[2]
                        if ($columns.Count -gt 3 -and $columns[3]) { $destination += "  ← $($columns[3])" }
                        if ($columns[1] -eq 'start') { $ConnectionsStart += $destination } else { $ConnectionsLater += $destination }
                    } elseif ($columns[0] -eq 'ERROR') { $PcapError = $columns[1]; Warn $PcapError }
                }
                if ($ConnectionsStart.Count) { Say "connections in the first $Watch seconds:"; $ConnectionsStart | ForEach-Object { Say $_ } }
                $ConnectionsLater | ForEach-Object { Say "while in use: $_" }
            } else { $Captured = $false; Warn 'could not fetch the capture from Download/PCAPdroid/' }
        }
    }

    if ($ScanJob) {
        if ($ScanJob.State -in 'Running', 'NotStarted') {
            Say 'VirusTotal is still scanning — press Enter to skip or wait for its result'
            while ($ScanJob.State -in 'Running', 'NotStarted') {
                # Do not leave a pending ReadLineAsync that could consume a later
                # review answer when the scan finishes before Enter is pressed.
                if (-not [Console]::IsInputRedirected -and [Console]::KeyAvailable) {
                    if ([Console]::ReadKey($true).Key -eq [ConsoleKey]::Enter) { Stop-Job $ScanJob; break }
                }
                Start-Sleep -Milliseconds 500
            }
        }
        if ($ScanJob.State -eq 'Completed') { Read-Vt $vtPath }
        else { Warn 'VirusTotal scan incomplete — check the link manually' }
    }

    Step '5. What you saw'
    function Yes-If([bool]$Condition) { if ($Condition) { return 'y' }; return 'n' }
    $NetSeen = 's'; $NetStart = 's'; $NetExtra = 's'; $NetTrack = 's'
    if ($Captured -and -not $PcapError) {
        $NetSeen = Yes-If ($ConnectionsStart.Count + $ConnectionsLater.Count -gt 0)
        $NetStart = Yes-If ($ConnectionsStart.Count -gt 0)
        $NetExtra = Yes-If (($ConnectionsStart + $ConnectionsLater -join "`n") -match 'online fonts|connectivity check')
        $NetTrack = Yes-If (($ConnectionsStart + $ConnectionsLater -join "`n") -match 'tracker:')
    }
    if ($StaticTrackers.Count) { $NetTrack = 'y' }
    if ($NoDevice) { Act 'no device in this run — answer from what you saw on a device, or s to skip' }
    $works = Ask 'Did it start and work normally?' $(if ($Crashed -ne 'n' -or $Gone) { 'n' } else { 'y' })
    if ($Crashed -ne 'n') { $works = 'n' }
    $features = Ask 'Do the main features from its description work?' 'y'
    $icon = Ask 'Does it have its own icon (not the stock Android/Flutter one)?' 'y'
    $policy = Ask 'Anything against the Inclusion Policy (ads, paid unlock, non-free service)?' 'n'
    $cats = Ask "Do the categories fit ($Categories)?" $(if (-not $MrArgument) { 's' } elseif ($Categories) { 'y' } else { 'n' })
    $terms = Ask 'Did it ask you to accept terms other than the FOSS license?' 'n'
    $optional = Ask 'Does it work without the optional permissions?' 'y'
    $storage = 'y'
    if ('MANAGE_EXTERNAL_STORAGE' -in $SpecialPermissions) { $storage = Ask 'Is all-files access really needed — could the system file picker (SAF) not do the job?' 'n' }
    $updates = 's'; $unclear = 's'; $browser = 's'
    if ($HasInternet) {
        if ($NetSeen -eq 's') { $NetSeen = Ask 'Did the app connect to anything at all?' $(if ($Hosts.Count) { 'y' } else { 'n' }) }
        if ($NetStart -eq 's') { $NetStart = Ask 'Did it connect to anything as soon as it opened?' 'n' }
        $updates = Ask 'Does it check for updates by itself?' $(if (($ConnectionsStart + $ConnectionsLater -join "`n") -match 'update check') { 'y' } else { 'n' })
        if ($NetExtra -eq 's') { $NetExtra = Ask 'Did it load fonts or icons online, or ping a server just to test the connection?' 'n' }
        if ($NetTrack -eq 's') { $NetTrack = Ask 'Did it contact any tracking or analytics service?' 'n' }
        $unclear = Ask 'Is any of these connections not explained in its description?' 'n'
        $browser = Ask 'Did a link (author page, help…) open inside the app instead of the browser?' 'n'
    }
    $english = Ask 'Is it usable in English?' 'y'
    $scanOk = 's'
    if ($VtResult -and $VtMalicious -eq 0) { $scanOk = 'y' }
    else {
        if (-not $VtResult) {
            if (Open-Url $VtLink) { Act 'VirusTotal is open in your browser' } else { Act "open $VtLink" }
            Act 'if the file is unknown, upload it manually only if it may be shared'
            if ($ApkArgument) { Warn 'this is a local file: VirusTotal shares uploads with its partners' }
            Say $Apk
        } else { Say "VirusTotal: $VtResult — $VtLink" }
        $scanOk = Ask 'Do all or most scanners say it is clean?' $(if ($VtMalicious -gt 2) { 'n' } else { 'y' })
    }
    Say 'Is there anything you want to add to the report?'
    Say 'type it line by line, then Enter on an empty line — or just Enter to skip'
    $notes = [Collections.Generic.List[string]]::new()
    while ($true) { Write-Host '   > ' -NoNewline; $line = Read-Answer; if (-not $line) { break }; $notes.Add($line) }

    $report = [Text.StringBuilder]::new()
    function Line([string]$Text = '') { [void]$report.AppendLine($Text) }
    function Box([string]$Answer, [string]$Text) {
        $mark = if ($Answer -eq 'y') { 'x' } else { ' ' }
        $suffix = if ($Answer -eq 's') { ' _(not checked)_' } else { '' }
        Line "- [$mark] $Text$suffix"
    }
    function Negate([string]$Answer) { if ($Answer -eq 'y') { return 'n' }; if ($Answer -eq 'n') { return 'y' }; return 's' }
    function Category([string]$Name) { Line; Line "</td></tr><tr><td>$Name</td><td>"; Line }
    $deviceText = if ($DeviceDescription) { " on $DeviceDescription" } else { '' }
    Line ('Tested `{0}` {1} ({2}){3}.' -f $AppId, $VersionName, $VersionCode, $deviceText)
    Line; Line '<table><thead><tr><th>Category</th><th>Checklist</th></tr></thead><tbody><tr><td>Basic Function</td><td>'; Line
    Box $works 'The app can start and work normally.'
    Box $features 'The functions in the description are implemented.'
    Box $icon 'The app has a unique icon (instead of a default one).'
    Category 'Policy Compliance'
    Box (Negate $policy) "Features don't violate F-Droid's Inclusion Policy."
    Box $cats 'The Categories field is set properly.'
    Box (Negate $terms) "Doesn't require accepting any terms other than the FOSS license."
    Category 'Permissions'
    Box $optional 'The app can be used without granting optional runtime permissions.'
    Box $storage "The app doesn't require unnecessary MANAGE_EXTERNAL_STORAGE permission."
    Category 'Network Connections'
    if (-not $HasInternet) { Line '- No `INTERNET` permission.' }
    else {
        Box $NetSeen 'Network connection is observed.'
        Box $NetStart 'The app connects to web services on start.'
        Box $updates 'The app checks for update automatically.'
        Box $NetExtra 'The app has unnecessary connections (online fonts, icons, connectivity check).'
        Box $NetTrack 'Tracking domains connected.'
        Box $unclear 'Connections not described clearly in description.'
        Box $browser 'Unnecessary in-app webview presents in the app.'
    }
    Category 'Language Support'; Box $english 'The app has English support.'
    Category 'Security Scan'; Box $scanOk 'All or most vendors on VirusTotal or similar scanning services indicate the app is benign.'
    Line; Line '</td></tr></tbody></table>'; Line
    if ($notes.Count) { Line '**Notes from the tester:**'; Line; foreach ($line in $notes) { Line "$line  " }; Line }
    if ($Shots.Count) {
        Line '**Screenshots:**'; Line
        foreach ($shot in $Shots) {
            $caption = if ($shot.Caption) { " — $($shot.Caption)" } else { '' }
            Line ('- `{0}`{1}' -f $shot.File, $caption)
        }
        Line
    }
    Line '<details>'; Line '<summary>Details</summary>'; Line
    Line ('- APK: `{0}` (sha256 `{1}`)' -f [IO.Path]::GetFileName($Apk), $Sha256)
    if ($NoLeanback) { Line '- The device does not declare Android TV (android.software.leanback), which the app requires; installed with adb anyway.' }
    if ($ApkArgument -and $Iid) {
        Line "- Tested a local APK, not one downloaded from this merge request's CI."
        if ($NotFromCi) { Line ('- It is not one of the APKs this merge request''s CI built (`{0}_{1}.apk`).' -f $AppId, $VersionCode) }
    }
    if ($Crashed -ne 'n') {
        Line ('- Crashed ({0}). Log:' -f $(if ($Crashed -eq 'y') { 'on start' } else { 'while in use' }))
        Line '```'; foreach ($line in (Get-Content -LiteralPath (Join-Path $Out 'crash.log') -TotalCount 40)) { Line $line }; Line '```'
    }
    if ($Gone) { Line '- The app was not running any more when the test ended, and left no crash log (closed, or stopped).' }
    if ($StartPrompt) { Line "- Asks for a permission on start: $StartPrompt" }
    if ($SpecialPermissions.Count) { Line "- Special permissions: $($SpecialPermissions -join ' ')" }
    if ($RuntimePermissions.Count) { Line "- Runtime permissions: $($RuntimePermissions -join ' ')" }
    if ($Cleartext) { Line '- `usesCleartextTraffic` is on (plain http allowed).' }
    if ($Debuggable) { Line '- The APK is debuggable.' }
    if ($StaticTrackers.Count) { Line '- Tracker code (Exodus signatures):'; foreach ($tracker in $StaticTrackers) { Line "  - $tracker" } }
    if ($NonFreeLibraries.Count) { Line "- Non-free libraries: $($NonFreeLibraries -join ' ')" }
    if ($Captured -and -not $PcapError) {
        $modeName = if ($RootCapture) { 'root' } else { 'VPN' }
        Line "- Connections (PCAPdroid, $modeName mode), first ${Watch}s after launch:"
        if ($ConnectionsStart.Count) { foreach ($connection in $ConnectionsStart) { Line ('  - `{0}`' -f $connection) } } else { Line '  none' }
        Line '- Connections while in use:'
        if ($ConnectionsLater.Count) { foreach ($connection in $ConnectionsLater) { Line ('  - `{0}`' -f $connection) } } else { Line '  none' }
        if ($RootCapture) { Line "- In root mode the app's DNS lookups are made by the system, so connections are named from TLS and HTTP only; the others show as address:port." }
    } elseif ($HasInternet) { Line '- Network not captured.' }
    Line "- VirusTotal: $VtResult — $VtLink"; Line; Line '</details>'
    $ReportPath = Join-Path $Out 'report.md'
    Write-Utf8 $ReportPath $report.ToString()
    Step '6. Report'; Write-Host $report.ToString(); Ok "saved to $ReportPath"
    if ($Iid) { Step "7. Post to !$Iid" } else { Step '7. The report' }
    $left = ([regex]::Matches($report.ToString(), '\(not checked\)')).Count
    if ($left) { Warn "$left box(es) still say (not checked)" }
    if ($EditorProgram -and (Confirm "Edit the report$(if ($Iid) { ' before posting' })?" ($left -gt 0))) {
        # Inherit the terminal for interactive editors, but preserve argument boundaries.
        $editorStart = [Diagnostics.ProcessStartInfo]::new()
        $editorStart.FileName = $EditorProgram
        $editorStart.UseShellExecute = $false
        $editorStart.ArgumentList.Add($ReportPath)
        $editorProcess = [Diagnostics.Process]::Start($editorStart)
        try {
            $editorProcess.WaitForExit()
            if ($editorProcess.ExitCode -ne 0) { Warn 'the editor exited with an error' }
        } finally { $editorProcess.Dispose() }
    }
    if (-not $Iid) { Say "no merge request — the report stays in $ReportPath" }
    elseif (-not $CanPost) { Say "glab is not ready — paste $ReportPath into $MrUrl yourself" }
    elseif (Confirm "Post the report as a comment on ${MrUrl}?" $true) {
        $bodyPath = $ReportPath
        if ($Shots.Count) {
            $uploads = [Text.StringBuilder]::new()
            $canUpload = (Invoke-Native $GlabProgram @('api', '--help')).Text.Contains('--form')
            if (-not $canUpload) { Warn 'glab is too old to upload screenshots (it needs --form)' }
            foreach ($shot in $Shots) {
                $uploadPath = ''
                if ($canUpload) {
                    foreach ($target in @($Project, $MrSource)) {
                        if (-not $target) { continue }
                        $result = Invoke-Native $GlabProgram @('api', '--method', 'POST', "projects/$target/uploads", '--form', "file=@$(Join-Path $Out $shot.File)")
                        if ($result.Code -ne 0) { continue }
                        try {
                            $uploaded = $result.Text | ConvertFrom-Json -AsHashtable
                            if ($uploaded['full_path']) { $uploadPath = $uploaded['full_path'] }
                            elseif ($target -eq $Project) { $uploadPath = $uploaded['url'] }
                            if ($uploadPath) { break }
                        } catch { }
                    }
                }
                if ($uploadPath) { [void]$uploads.AppendLine("$($shot.File)`t$uploadPath") }
                else { Warn "could not upload $($shot.File) — the comment says so in its place" }
            }
            $uploadsPath = Join-Path $Work 'uploads.tsv'; Write-Utf8 $uploadsPath $uploads.ToString()
            $bodyPath = Join-Path $Work 'post.md'; Write-Utf8 $bodyPath (Helper @('embed', $ReportPath, $uploadsPath, $Out))
        }
        $result = Invoke-Native $GlabProgram @('api', '--method', 'POST', "projects/$Project/merge_requests/$Iid/notes", '-F', "body=@$bodyPath")
        if ($result.Code -eq 0) {
            $note = $result.Text | ConvertFrom-Json -AsHashtable
            Ok "posted: $MrUrl#note_$($note['id'])"
        } else { Warn "glab could not post it — paste $ReportPath yourself" }
    } else { Say "not posted — it stays in $ReportPath" }
    if (-not $NoDevice -and -not $Keep -and (Confirm 'Remove the app from the device now?' $true)) {
        if ((Adb @('uninstall', $AppId)).Code -eq 0) { Ok 'removed' } else { Warn 'could not remove the app' }
    }
} catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
} finally {
    if ($ScanJob) { Remove-Job -Job $ScanJob -Force -ErrorAction SilentlyContinue }
    if ($StayAwake) { try { [void](Adb @('shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', $StayAwake)) } catch { } }
    if ($Work -and (Test-Path -LiteralPath $Work)) { Remove-Item -LiteralPath $Work -Recurse -Force }
}
