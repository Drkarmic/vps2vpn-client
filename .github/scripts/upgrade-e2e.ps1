# End-to-end check of the in-app update on a throwaway CI machine, the way
# CommonAction.installUpdate runs it: install the OLD release and start it,
# run the NEW setup with windowsUpdateArguments (lib/common/app_update.dart),
# then quit the app as handleExit does. The setup must wait for the app,
# install over it, keep the user's settings and open the new version again.
# Never run this on a real PC: it installs the app and ends processes.
param(
  [Parameter(Mandatory)][string]$Old,
  [Parameter(Mandatory)][string]$New,
  [string]$Out = 'upgrade'
)

$ErrorActionPreference = 'Stop'
if (-not $env:GITHUB_ACTIONS) { throw 'CI only: this installs vps2vpn and ends processes' }
New-Item -ItemType Directory -Force $Out | Out-Null
$failures = [System.Collections.Generic.List[string]]::new()
function Check($ok, $what) {
  if ($ok) { "PASS  $what" } else { "FAIL  $what"; $failures.Add($what) }
}
function VersionOf($setup) {
  if ((Split-Path $setup -Leaf) -match 'vps2vpn-(?:dev-)?v?(\d+\.\d+\.\d+)') { return $Matches[1] }
  throw "no version in $setup"
}
function Running() {
  Get-Process vps2vpn -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }
}

$oldVersion = VersionOf $Old
$newVersion = VersionOf $New
"upgrade $oldVersion -> $newVersion"
$dir = Join-Path $env:ProgramFiles 'vps2vpn'
$exe = Join-Path $dir 'vps2vpn.exe'
$prefs = Join-Path $env:APPDATA 'vps2vpn\vps2vpn\shared_preferences.json'
# A real user accepts the disclaimer once; the app reads this to do the same.
$env:FLCLASH_ACCEPT_DISCLAIMER = '1'

try {
  # 1. The old release, installed and running, with settings of its own.
  $p = Start-Process $Old -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "`"/LOG=$(Join-Path $Out 'install-old.log')`"" -Wait -PassThru
  Check ($p.ExitCode -eq 0) "old installer exit code 0 (got $($p.ExitCode))"
  $oldHash = (Get-FileHash $exe).Hash
  "old vps2vpn.exe file version: $((Get-Item $exe).VersionInfo.FileVersion)"
  $app = Start-Process $exe -PassThru
  Start-Sleep 20
  Check (-not $app.HasExited) 'old version running'
  Check (Test-Path $prefs) 'old version wrote its settings'
  $marker = 'vps2vpn-upgrade-check'
  if (Test-Path $prefs) {
    $d = Get-Content $prefs -Raw | ConvertFrom-Json
    $d | Add-Member -Force "flutter.$marker" $marker
    # The app rewrites this file; restart it on the marked copy.
    Get-Process vps2vpn, vps2vpnCore -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 3
    $d | ConvertTo-Json -Depth 50 -Compress | Set-Content $prefs -Encoding utf8
    $app = Start-Process $exe -PassThru
    Start-Sleep 15
  }

  # 2. The update, started the way the app starts it.
  $update = Start-Process $New -ArgumentList '/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/updatefrom=$($app.Id)", "`"/LOG=$(Join-Path $Out 'install-new.log')`"" -PassThru
  Start-Sleep 5
  Check (-not $update.HasExited) 'setup waits while the app is still running'
  Check ((Get-FileHash $exe).Hash -eq $oldHash) 'nothing replaced before the app quits'

  # 3. The app quits (handleExit), the setup carries on.
  Stop-Process -Id $app.Id -Force
  Get-Process vps2vpnCore -ErrorAction SilentlyContinue | Stop-Process -Force
  if (-not $update.WaitForExit(180000)) { Check $false 'setup finished within 3 minutes' }
  else { Check ($update.ExitCode -eq 0) "update exit code 0 (got $($update.ExitCode))" }

  # 4. The new version is in place and was opened again.
  Check ((Get-FileHash $exe).Hash -ne $oldHash) 'vps2vpn.exe replaced'
  $fileVersion = (Get-Item $exe).VersionInfo.FileVersion
  "new vps2vpn.exe file version: $fileVersion"
  Check ("$fileVersion" -like "$newVersion*") "installed version is $newVersion"
  $deadline = (Get-Date).AddSeconds(60)
  while (-not (Running) -and (Get-Date) -lt $deadline) { Start-Sleep 1 }
  Check ([bool](Running)) 'the updated app was opened again'
  Start-Sleep 10
  Check ([bool](Running)) 'the updated app keeps running'
  Check ((Test-Path $prefs) -and (Get-Content $prefs -Raw).Contains($marker)) "the user's settings survived the update"
  Check ((Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
    Get-ItemProperty -ErrorAction SilentlyContinue | Where-Object { "$($_.DisplayName)" -like 'vps2vpn*' }).Count -eq 1) 'one installation registered'
} finally {
  Get-Process vps2vpn, vps2vpnCore -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Copy-Item $prefs (Join-Path $Out 'shared_preferences.json') -ErrorAction SilentlyContinue
}

if ($failures.Count) { "`n$($failures.Count) check(s) failed:"; $failures; exit 1 }
"`nall checks passed"
