' claudefocus: protocol launcher. Runs focus.ps1 without a console window flash.
' Registered by install.ps1 as: wscript.exe //B "<this file>" "%1"
Dim sh, dir, url
Set sh = CreateObject("WScript.Shell")
dir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
If WScript.Arguments.Count > 0 Then url = WScript.Arguments(0) Else url = ""
sh.Run "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "focus.ps1"" """ & url & """", 0, False
