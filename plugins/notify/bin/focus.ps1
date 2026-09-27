# Runs when the toast is clicked, via the claudefocus: URL protocol registered by install.ps1.
# URL format: claudefocus:<tab index or -1>.<WT_SESSION or empty>.<WindowsTerminal pid or 0>.<base64url title>
#
# Hands the request to focus-watcher.ps1 through a file. The watcher was started by the hook, so it
# inherits the terminal's privilege level; this process runs at medium integrity and, when Windows
# Terminal is elevated ("Run as administrator"), UIPI would not let it control the window at all.
# Falls back to driving wt.exe / UI Automation directly when no watcher is running.
param(
  [Parameter(Mandatory = $true)][string]$Url,
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$log = Join-Path $env:USERPROFILE '.claude\claude-notify.log'
function Log($m) { try { Add-Content -LiteralPath $log -Value ("{0} focus: {1}" -f (Get-Date -Format o), $m) } catch {} }

$tabIndex = -1; $wtSession = ''; $wtPid = 0
try {
  $payload = $Url -replace '^claudefocus:/*', '' -replace '/$', ''
  if ($payload -match '^(-?\d+)\.([0-9a-fA-F-]*)\.(\d+)\.(.*)$') { $tabIndex = [int]$Matches[1]; $wtSession = $Matches[2]; $wtPid = [int]$Matches[3]; $b64 = $Matches[4] }
  else { $b64 = $payload }
  $b64 = $b64.Replace('-', '+').Replace('_', '/')
  while ($b64.Length % 4 -ne 0) { $b64 += '=' }
  $title = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
} catch { Log "bad url: $Url"; exit 0 }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
"@
function Bring([IntPtr]$h) {
  if ($h -eq [IntPtr]::Zero) { return }
  if ([Win32]::IsIconic($h)) { [void][Win32]::ShowWindow($h, 9) }   # SW_RESTORE
  $fg = [Win32]::GetForegroundWindow()
  $fgThread = [Win32]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
  $me = [Win32]::GetCurrentThreadId()
  [void][Win32]::AttachThreadInput($me, $fgThread, $true)
  [void][Win32]::SetForegroundWindow($h)
  [void][Win32]::AttachThreadInput($me, $fgThread, $false)
}

if ($tabIndex -ge 0) {
  if ($DryRun) { "wt focus-tab -t $tabIndex session=$wtSession wtpid=$wtPid ($title)"; exit 0 }
  $watcherAlive = $false
  try { $m = [System.Threading.Mutex]::OpenExisting('Local\ClaudeCodeNotifyFocusWatcher'); $m.Dispose(); $watcherAlive = $true } catch {}
  if ($watcherAlive) {
    $req = Join-Path $env:USERPROFILE '.claude\claude-notify-focus.json'
    $obj = @{ index = $tabIndex; session = $wtSession; wtpid = $wtPid; title = $title; ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
    [IO.File]::WriteAllText($req, ($obj | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
    Log "request handed to watcher: -t $tabIndex wtpid=$wtPid ('$title')"
    exit 0
  }
  # No watcher: drive wt.exe directly (works when the terminal is not elevated).
  $wt = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
  if (-not (Test-Path $wt)) { $wt = 'wt.exe' }
  if ($wtSession) { $env:WT_SESSION = $wtSession }   # "wt -w 0" picks the window by WT_SESSION
  $p = Start-Process -FilePath $wt -ArgumentList @('-w', '0', 'focus-tab', '-t', "$tabIndex") -PassThru -WindowStyle Hidden -Wait
  Log "direct wt focus-tab -t $tabIndex exit=$($p.ExitCode) ('$title')"
  $proc = $null
  if ($wtPid) { $proc = Get-Process -Id $wtPid -ErrorAction SilentlyContinue }
  if (-not $proc -or $proc.MainWindowHandle -eq 0) { $proc = Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1 }
  if ($proc) { Bring ([IntPtr]$proc.MainWindowHandle) }
  exit 0
}

# Last resort (no tab index): search by title through UI Automation.
function Plain([string]$s) {
  $d = $s.Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object Text.StringBuilder
  foreach ($c in $d.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
  }
  ($sb.ToString() -replace '[^\p{L}\p{N} ]', ' ' -replace '\s+', ' ').Trim().ToLowerInvariant()
}
$want = Plain $title
if (-not $want) { Log 'empty title'; exit 0 }
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$AE = [System.Windows.Automation.AutomationElement]
$winCond = New-Object System.Windows.Automation.PropertyCondition($AE::ClassNameProperty, 'CASCADIA_HOSTING_WINDOW_CLASS')
$tabCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::TabItem)
$best = $null; $bestWin = $null; $bestScore = 0
foreach ($w in $AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $winCond)) {
  foreach ($t in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCond)) {
    $name = Plain $t.Current.Name
    $score = 0
    if ($name -eq $want) { $score = 3 }
    elseif ($name.EndsWith($want) -or $name.Contains($want)) { $score = 2 }
    elseif ($want.Contains($name) -and $name.Length -ge 6) { $score = 1 }
    if ($score -gt $bestScore) { $best = $t; $bestWin = $w; $bestScore = $score }
  }
}
if (-not $best) { Log "no tab for '$title'"; exit 0 }
if ($DryRun) { "MATCH: $($best.Current.Name)"; exit 0 }
$best.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
Bring ([IntPtr]$bestWin.Current.NativeWindowHandle)
Log "UIA selected '$($best.Current.Name)'"
exit 0
