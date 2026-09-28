---
description: Remove click-to-focus on Windows (unregisters the claudefocus: protocol and stops the helper)
allowed-tools: Bash, PowerShell
---

Remove the click-to-focus setup of the notify plugin. Do exactly this and nothing else:

1. If the platform is not Windows, tell the user there is nothing to remove here. Stop.
2. Run the uninstaller, which deletes the `claudefocus:` protocol key under HKCU, removes `%LOCALAPPDATA%\claude-code-notify` and stops the background helper:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/uninstall.ps1"
```

3. Report the output. Remind the user that notifications themselves keep working until the plugin is uninstalled with `/plugin uninstall notify@claude-code-notify`.
