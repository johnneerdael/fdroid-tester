"""Portable checks for CLI validation and the real native-process boundary.

Run with Python 3 and PowerShell 7 on Windows, macOS, or Linux. Full review
fixtures are exercised separately by tests/run.sh --powershell.
"""

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TESTER = ROOT / "fdroid-tester.ps1"
PWSH = shutil.which("pwsh")
if not PWSH:
    raise SystemExit("PowerShell 7 (pwsh) is required")

# Load the actual function definition through the PowerShell AST, without
# running the interactive entry point. No production-only test flags are needed.
BOOTSTRAP = r"""
param([string]$Tester, [string]$Request)
$ErrorActionPreference = 'Stop'
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $Tester, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors -join "`n") }
$definition = $ast.Find({param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Invoke-Native'
}, $false)
if (-not $definition) { throw 'native process boundary is missing' }
. ([scriptblock]::Create($definition.Extent.Text))
$spec = Get-Content -LiteralPath $Request -Raw | ConvertFrom-Json -AsHashtable
$result = Invoke-Native -Executable $spec.executable -Arguments $spec.arguments -OutputPath $spec.output
$result | ConvertTo-Json -Compress
"""


class PowerShellTests(unittest.TestCase):
    def run_cli(self, *arguments):
        return subprocess.run(
            [PWSH, "-NoProfile", "-File", str(TESTER), *arguments],
            capture_output=True, text=True, encoding="utf-8", timeout=20,
        )

    def native(self, code, *arguments, output=None):
        with tempfile.TemporaryDirectory(prefix="fdroid process ") as folder:
            folder = Path(folder)
            bootstrap = folder / "native boundary.ps1"
            bootstrap.write_text(BOOTSTRAP, encoding="utf-8")
            request = folder / "arguments.json"
            request.write_text(json.dumps({
                "executable": sys.executable,
                "arguments": ["-c", code, *arguments],
                "output": str(output) if output else "",
            }), encoding="utf-8")
            result = subprocess.run(
                [PWSH, "-NoProfile", "-File", str(bootstrap), str(TESTER), str(request)],
                capture_output=True, text=True, encoding="utf-8", timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            return json.loads(result.stdout)

    def test_native_arguments_keep_spaces_quotes_and_unicode(self):
        values = ['C:\\APK files\\app "review".apk', "café & $(not-a-command)"]
        result = self.native("import json,sys; print(json.dumps(sys.argv[1:]))", *values)
        self.assertEqual(result["Code"], 0)
        self.assertEqual(json.loads(result["Text"]), values)

    def test_binary_output_does_not_decode_or_change_bytes(self):
        with tempfile.TemporaryDirectory(prefix="fdroid screenshot ") as folder:
            output = Path(folder) / "screen bytes.png"
            result = self.native("import sys; sys.stdout.buffer.write(bytes([0,10,13,128,255]))", output=output)
            self.assertEqual(result["Code"], 0)
            self.assertEqual(output.read_bytes(), b"\x00\x0a\x0d\x80\xff")
            self.assertEqual(result["Text"], "")

    def test_child_stdin_is_closed_without_taking_review_answers(self):
        result = self.native("import sys; print(repr(sys.stdin.read()))")
        self.assertEqual(result["Text"].strip(), "''")

    def test_stdout_and_stderr_are_drained_and_exit_status_preserved(self):
        result = self.native("import sys; sys.stderr.write('e'*262144); sys.stdout.write('o'*262144); sys.exit(7)")
        self.assertEqual(result["Code"], 7)
        self.assertEqual(result["Text"], "o" * 262144)
        self.assertEqual(result["Error"], "e" * 262144)

    def test_missing_apk_is_rejected_before_any_device_work(self):
        result = self.run_cli("-Apk", str(ROOT / "nonexistent-fixture.apk"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("no such APK", result.stderr)

    def test_missing_option_value_and_invalid_watch_are_rejected(self):
        for arguments in [("-Serial",), ("-Watch", "-1"), ("-Watch", "tomorrow")]:
            with self.subTest(arguments=arguments):
                self.assertEqual(self.run_cli(*arguments).returncode, 2)

    def test_unknown_flag_and_multiple_submissions_are_rejected(self):
        for arguments in [("-NotAFlag",), ("123", "456")]:
            with self.subTest(arguments=arguments):
                self.assertEqual(self.run_cli(*arguments).returncode, 2)

    def test_numeric_submission_from_a_powershell_session_is_accepted(self):
        # Direct script calls pass numeric literals as Int32, unlike pwsh -File.
        with tempfile.TemporaryDirectory() as folder:
            caller = Path(folder) / "call.ps1"
            caller.write_text('param([string]$Tester)\n& $Tester 123 -Help\nexit $LASTEXITCODE\n')
            result = subprocess.run(
                [PWSH, "-NoProfile", "-File", str(caller), str(TESTER)],
                capture_output=True, text=True, encoding="utf-8", timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
