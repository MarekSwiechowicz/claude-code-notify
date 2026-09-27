---
description: Enable click-to-focus on Windows (registers the claudefocus: URL protocol, no admin needed)
allowed-tools: Bash, PowerShell, Read
---

Set up click-to-focus for the notify plugin. Do exactly this and nothing else:

1. If the platform is not Windows, tell the user that notifications already work here and that click-to-focus is Windows Terminal only. Stop.
2. Run the installer, which copies the click handler to `%LOCALAPPDATA%\claude-code-notify` and registers the `claudefocus:` protocol under HKCU (no administrator rights required):

```
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/install.ps1"
```

3. Report the installer output. Then send a test notification so the user can try clicking it:

```
echo '{"hook_event_name":"Stop","cwd":"'"$PWD"'"}' | bash "${CLAUDE_PLUGIN_ROOT}/bin/notify.sh"
```

4. Tell the user: clicking the toast (or its "Show" button) switches to this session's Windows Terminal tab. Options live in `~/.claude/settings.json` under `env`: `CLAUDE_NOTIFY_LANG`, `CLAUDE_NOTIFY_SOUND`, `CLAUDE_NOTIFY_STICKY`, `CLAUDE_NOTIFY_FOCUS`. Diagnostics: `~/.claude/claude-notify.log`. To remove: `powershell -File "${CLAUDE_PLUGIN_ROOT}/uninstall.ps1"`.
