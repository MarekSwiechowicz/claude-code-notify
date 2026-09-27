# Background helper for click-to-focus. Started (hidden) by notify.js on every toast; a mutex keeps
# it a singleton. It inherits the terminal's privilege level, so when Windows Terminal runs elevated
# this process is elevated too and may control it, which the medium-integrity process spawned by the
# toast click cannot (UIPI). Waits for ~/.claude/claude-notify-focus.json written by focus.ps1,
# runs "wt -w 0 focus-tab -t N" with the right WT_SESSION and brings the window to the front.
# Exits when no WindowsTerminal process is left.
$ErrorActionPreference = 'SilentlyContinue'
$log = Join-Path $env:USERPROFILE '.claude\claude-notify.log'
$req = Join-Path $env:USERPROFILE '.claude\claude-notify-focus.json'
function Log($m) { try { Add-Content -LiteralPath $log -Value ("{0} watcher: {1}" -f (Get-Date -Format o), $m) } catch {} }

$created = $false
$mutex = New-Object System.Threading.Mutex($false, 'Local\ClaudeCodeNotifyFocusWatcher', [ref]$created)
if (-not $created) { exit 0 }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32W {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
}
"@
function Bring([IntPtr]$h) {
  if ($h -eq [IntPtr]::Zero) { return }
  if ([Win32W]::IsIconic($h)) { [void][Win32W]::ShowWindow($h, 9) }
  $fg = [Win32W]::GetForegroundWindow()
  $fgThread = [Win32W]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
  $me = [Win32W]::GetCurrentThreadId()
  [void][Win32W]::AttachThreadInput($me, $fgThread, $true)
  # the ALT tap unlocks SetForegroundWindow when Windows does not consider us the foreground process
  [Win32W]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [Win32W]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
  [void][Win32W]::SetForegroundWindow($h)
  [void][Win32W]::AttachThreadInput($me, $fgThread, $false)
}

$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Log "start pid=$PID elevated=$elev"
$wt = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
if (-not (Test-Path $wt)) { $wt = 'wt.exe' }

$idle = 0
while ($true) {
  Start-Sleep -Milliseconds 250
  if (Test-Path $req) {
    $r = $null
    try { $r = Get-Content -LiteralPath $req -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    Remove-Item -LiteralPath $req -Force
    if ($r -and $r.index -ge 0 -and ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [int64]$r.ts) -lt 60) {
      if ($r.session) { $env:WT_SESSION = "$($r.session)" } else { Remove-Item Env:WT_SESSION -ErrorAction SilentlyContinue }
      $p = Start-Process -FilePath $wt -ArgumentList @('-w', '0', 'focus-tab', '-t', "$($r.index)") -PassThru -WindowStyle Hidden -Wait
      $proc = $null
      if ($r.wtpid) { $proc = Get-Process -Id ([int]$r.wtpid) -ErrorAction SilentlyContinue }
      if (-not $proc -or $proc.MainWindowHandle -eq 0) { $proc = Get-Process WindowsTerminal | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1 }
      if ($proc) { Bring ([IntPtr]$proc.MainWindowHandle) }
      Log "focus-tab -t $($r.index) exit=$($p.ExitCode) wtpid=$($proc.Id) ('$($r.title)')"
    }
    $idle = 0
  } else {
    $idle++
    if ($idle % 60 -eq 0 -and -not (Get-Process WindowsTerminal -ErrorAction SilentlyContinue)) { Log 'exit, no WindowsTerminal left'; break }
  }
}
