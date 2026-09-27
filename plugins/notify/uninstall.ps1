# Windows only. Removes the claudefocus: protocol registration and the copied click handler.
# The hooks themselves go away when you uninstall the plugin (/plugin uninstall notify).
$ErrorActionPreference = 'SilentlyContinue'
Remove-Item -Path 'HKCU:\Software\Classes\claudefocus' -Recurse -Force
Remove-Item -Path (Join-Path $env:LOCALAPPDATA 'claude-code-notify') -Recurse -Force
Get-Process powershell | Where-Object { $_.CommandLine -like '*focus-watcher.ps1*' } | Stop-Process -Force
Write-Host 'claude-code-notify: click-to-focus removed.'
