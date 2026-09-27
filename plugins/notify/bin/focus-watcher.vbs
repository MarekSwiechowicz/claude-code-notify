' Starts focus-watcher.ps1 as a hidden, independent process (no console flash).
' Called by notify.js on every toast; the watcher itself makes sure only one instance runs (mutex).
Dim sh, dir
Set sh = CreateObject("WScript.Shell")
dir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
sh.Run "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "focus-watcher.ps1""", 0, False
