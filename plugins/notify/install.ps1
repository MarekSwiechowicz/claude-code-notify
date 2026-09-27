# Windows only. Enables click-to-focus: registers the claudefocus: URL protocol (HKCU, no admin
# needed) so that clicking a toast switches to the Windows Terminal tab of that session.
# Copies the click handler to %LOCALAPPDATA%\claude-code-notify so the registry entry keeps
# working across plugin updates (the plugin cache path changes with every version).
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'bin'
$dst = Join-Path $env:LOCALAPPDATA 'claude-code-notify'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
foreach ($f in 'focus.vbs', 'focus.ps1') { Copy-Item -LiteralPath (Join-Path $src $f) -Destination $dst -Force }

$base = 'HKCU:\Software\Classes\claudefocus'
New-Item -Path $base -Force | Out-Null
Set-ItemProperty -Path $base -Name '(Default)' -Value 'URL:Claude Code focus'
Set-ItemProperty -Path $base -Name 'URL Protocol' -Value ''
New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value ('wscript.exe //B "{0}\focus.vbs" "%1"' -f $dst)

Write-Host "claude-code-notify: click-to-focus installed."
Write-Host "  handler:  $dst\focus.vbs"
Write-Host "  registry: HKCU\Software\Classes\claudefocus"
Write-Host "Run uninstall.ps1 to remove both."
