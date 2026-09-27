#!/usr/bin/env node
// claude-code-notify: desktop notification when a Claude Code session finishes a turn (Stop)
// or is waiting for you (Notification: permission_prompt / elicitation_dialog).
//
// Input: hook JSON on stdin. Output: Windows toast (WinRT via Windows PowerShell),
// macOS notification (osascript) or Linux notify-send.
// Log: ~/.claude/claude-notify.log. Never exits non-zero, so it can never block a session.
//
// Options (environment variables, e.g. via "env" in ~/.claude/settings.json):
//   CLAUDE_NOTIFY_LANG    en (default) | pl
//   CLAUDE_NOTIFY_SOUND   1 (default) | 0
//   CLAUDE_NOTIFY_STICKY  1 (default: toast stays until dismissed) | 0
//   CLAUDE_NOTIFY_FOCUS   1 (default: click switches to the Windows Terminal tab) | 0
//   CLAUDE_NOTIFY_DEBUG   1 prints the resolved text to stderr
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawn, spawnSync } = require('child_process');

function safe(fn, fallback) { try { return fn(); } catch { return fallback; } }
const opt = (name, def) => (process.env[name] === undefined || process.env[name] === '') ? def : process.env[name];
const on = (name, def) => !['0', 'false', 'off', 'no'].includes(String(opt(name, def ? '1' : '0')).toLowerCase());

const LOG = path.join(os.homedir(), '.claude', 'claude-notify.log');
function log(msg) {
  safe(() => { if (fs.statSync(LOG).size > 200 * 1024) fs.truncateSync(LOG, 0); }, null);
  safe(() => fs.appendFileSync(LOG, `${new Date().toISOString()} ${msg}\n`), null);
}

const STR = {
  en: { done: 'DONE', waiting: 'WAITING', idle: 'Session is waiting for your input', decide: 'Your decision is needed', show: 'Show', ok: 'OK', session: 'session' },
  pl: { done: 'GOTOWE', waiting: 'CZEKA', idle: 'Sesja czeka na Twój wkład', decide: 'Potrzebna Twoja decyzja', show: 'Pokaż', ok: 'OK', session: 'sesja' },
};
const T = STR[String(opt('CLAUDE_NOTIFY_LANG', 'en')).toLowerCase()] || STR.en;

const raw = safe(() => fs.readFileSync(0, 'utf8'), '') || '{}';
const input = safe(() => JSON.parse(raw), {});
const event = input.hook_event_name || 'Stop';
const cwd = input.cwd || process.cwd();
const sessionId = input.session_id || '';
const transcript = input.transcript_path || '';
const hasTranscript = !!transcript && fs.existsSync(transcript);

function readTail(file, bytes) {
  const fd = fs.openSync(file, 'r');
  try {
    const size = fs.fstatSync(fd).size;
    const start = Math.max(0, size - bytes);
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    return buf.toString('utf8');
  } finally { fs.closeSync(fd); }
}
function readHead(file, bytes) {
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(bytes);
    const n = fs.readSync(fd, buf, 0, bytes, 0);
    return buf.toString('utf8', 0, n);
  } finally { fs.closeSync(fd); }
}
const parseLines = text => text.split('\n').filter(Boolean).map(l => safe(() => JSON.parse(l), null)).filter(Boolean);

// Session title: the last "ai-title" entry in the transcript (same text Claude Code puts on the terminal tab).
function aiTitle() {
  if (!hasTranscript) return '';
  const lines = parseLines(safe(() => readTail(transcript, 4 * 1024 * 1024), ''));
  for (let i = lines.length - 1; i >= 0; i--) if (lines[i].type === 'ai-title' && lines[i].aiTitle) return lines[i].aiTitle;
  return '';
}
// Before the session gets a title: the first user prompt.
function firstPrompt() {
  if (!hasTranscript) return '';
  for (const m of parseLines(safe(() => readHead(transcript, 256 * 1024), ''))) {
    if (m.type !== 'user' || !m.message) continue;
    const c = m.message.content;
    const text = typeof c === 'string' ? c : Array.isArray(c) ? c.filter(x => x.type === 'text' && x.text).map(x => x.text).join(' ') : '';
    if (text && !text.startsWith('<')) return text;
  }
  return '';
}
function sessionName() {
  const dir = path.join(os.homedir(), '.claude', 'sessions');
  for (const f of safe(() => fs.readdirSync(dir).filter(f => f.endsWith('.json')), [])) {
    const j = safe(() => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')), null);
    if (j && j.sessionId === sessionId && j.name) return j.name;
  }
  return '';
}
function lastAssistantText() {
  if (!hasTranscript) return '';
  const lines = parseLines(safe(() => readTail(transcript, 512 * 1024), ''));
  for (let i = lines.length - 1; i >= 0; i--) {
    const m = lines[i];
    if (m.type !== 'assistant' || !m.message || !Array.isArray(m.message.content)) continue;
    const texts = m.message.content.filter(c => c.type === 'text' && c.text).map(c => c.text);
    if (texts.length) return texts.join(' ');
  }
  return '';
}
function squash(s, max) {
  const t = String(s || '').replace(/\s+/g, ' ').trim();
  return t.length > max ? t.slice(0, max - 1) + '…' : t;
}

const title = aiTitle() || squash(firstPrompt(), 60) || path.basename(cwd);
const tag = sessionName() || path.basename(cwd);
const waiting = event === 'Notification';
const head = waiting ? `⏳ ${T.waiting}: ${title}` : `✅ ${T.done}: ${title}`;
const body = waiting ? squash(input.message || input.title || T.decide, 200) : squash(lastAssistantText() || T.idle, 200);
const footer = `${T.session} ${tag} · ${path.basename(cwd)}`;

if (on('CLAUDE_NOTIFY_DEBUG', false)) console.error(`${head}\n${body}\n${footer}`);
log(`event=${event} session=${sessionId.slice(0, 8)} title="${title}" tag=${tag} transcript=${hasTranscript}`);

function run(cmd, args, label) {
  let err = '';
  // Do NOT use detached: a PowerShell without the parent's console exits 0 without showing the toast.
  const p = spawn(cmd, args, { stdio: ['ignore', 'ignore', 'pipe'], windowsHide: true });
  p.stderr.on('data', d => { err += d; });
  p.on('error', e => log(`${label} spawn error: ${e.message}`));
  p.on('close', code => log(`${label} exit=${code}${err && !err.startsWith('#< CLIXML') ? ' stderr=' + squash(err, 300) : ''}`));
}
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

if (process.platform === 'win32') {
  const PS = fs.existsSync('C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe')
    ? 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe' : 'powershell.exe';
  const titleB64 = Buffer.from(title, 'utf8').toString('base64url');

  // Click-to-focus: the tab index is resolved NOW (from this process UI Automation can see the
  // Windows Terminal tabs; a process launched by the toast click cannot). The click then only
  // asks the background helper (focus-watcher.ps1) to run "wt focus-tab -t N".
  let tabIndex = -1, wtPid = 0;
  const focus = on('CLAUDE_NOTIFY_FOCUS', true) && !!process.env.WT_SESSION;
  if (focus) {
    try {
      const r = spawnSync(PS, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', path.join(__dirname, 'tabindex.ps1'), '-B64', titleB64],
        { encoding: 'utf8', timeout: 6000, windowsHide: true });
      const [a, b] = String(r.stdout || '').trim().split(';');
      if (Number.isInteger(parseInt(a, 10))) tabIndex = parseInt(a, 10);
      if (Number.isInteger(parseInt(b, 10))) wtPid = parseInt(b, 10);
    } catch {}
    log(`tab index=${tabIndex} wtpid=${wtPid}`);
    try { spawn('wscript.exe', ['//B', '//Nologo', path.join(__dirname, 'focus-watcher.vbs')], { stdio: 'ignore', windowsHide: true }).on('error', () => {}); } catch {}
  }
  const wtSession = String(process.env.WT_SESSION || '').replace(/[^0-9a-fA-F-]/g, '');
  const launch = `claudefocus:${tabIndex}.${wtSession}.${wtPid}.${titleB64}`;

  const sticky = on('CLAUDE_NOTIFY_STICKY', true);
  const sound = on('CLAUDE_NOTIFY_SOUND', true);
  const clickable = focus && tabIndex >= 0;
  const xml = `<toast${sticky ? ' scenario="reminder"' : ''} duration="long"${clickable ? ` activationType="protocol" launch="${esc(launch)}"` : ''}>` +
    `<visual><binding template="ToastGeneric">` +
    `<text hint-maxLines="1">${esc(head)}</text><text>${esc(body)}</text>` +
    `<text placement="attribution">${esc(footer)}</text>` +
    `</binding></visual>` +
    `<actions>` +
    (clickable ? `<action content="${esc(T.show)}" arguments="${esc(launch)}" activationType="protocol"/>` : '') +
    `<action content="${esc(T.ok)}" arguments="dismiss" activationType="system"/>` +
    `</actions>` +
    (sound ? `<audio src="ms-winsoundevent:Notification.${sticky ? 'Reminder' : 'Default'}"/>` : '<audio silent="true"/>') +
    `</toast>`;
  const b64 = Buffer.from(xml, 'utf8').toString('base64');
  const tagSafe = tag.replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 60);
  const ps = [
    '$ErrorActionPreference = "Stop"',
    '[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null',
    '[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null',
    '$doc = New-Object Windows.Data.Xml.Dom.XmlDocument',
    `$doc.LoadXml([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("${b64}")))`,
    '$t = New-Object Windows.UI.Notifications.ToastNotification $doc',
    `$t.Tag = "${tagSafe}"`,          // a new toast from the same session replaces the previous one
    '$t.Group = "claude-code"',
    '$appId = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe"',
    '[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($t)',
  ].join('; ');
  // -EncodedCommand: the script travels as base64 UTF-16LE, no quoting battles on the command line
  run(PS, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', Buffer.from(ps, 'utf16le').toString('base64')], 'powershell');
} else if (process.platform === 'darwin') {
  const q = s => String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  const snd = on('CLAUDE_NOTIFY_SOUND', true) ? ' sound name "Glass"' : '';
  run('osascript', ['-e', `display notification "${q(body)}" with title "${q(head)}" subtitle "${q(footer)}"${snd}`], 'osascript');
} else {
  run('notify-send', ['--app-name=Claude Code', head, `${body}\n${footer}`], 'notify-send');
}
