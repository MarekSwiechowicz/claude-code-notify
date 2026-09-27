# Prints "<tab index>;<WindowsTerminal pid>" for the Windows Terminal tab whose title matches
# the given one (base64url UTF-8), or "-1;0". Called by notify.js while the toast is being sent,
# because a process launched by the toast click cannot see the tabs through UI Automation.
param([Parameter(Mandatory = $true)][string]$B64)
$ErrorActionPreference = 'SilentlyContinue'
try {
  $b = $B64.Replace('-', '+').Replace('_', '/')
  while ($b.Length % 4 -ne 0) { $b += '=' }
  $title = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b))
} catch { '-1;0'; exit 0 }

# Windows Terminal shows the title without diacritics, so compare after stripping them.
function Plain([string]$s) {
  $d = $s.Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object Text.StringBuilder
  foreach ($c in $d.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
  }
  ($sb.ToString() -replace '[^\p{L}\p{N} ]', ' ' -replace '\s+', ' ').Trim().ToLowerInvariant()
}
$want = Plain $title
if (-not $want) { '-1;0'; exit 0 }

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$AE = [System.Windows.Automation.AutomationElement]
$winCond = New-Object System.Windows.Automation.PropertyCondition($AE::ClassNameProperty, 'CASCADIA_HOSTING_WINDOW_CLASS')
$tabCond = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::TabItem)

# Second field: pid of the Windows Terminal window that owns the matched tab (used to bring that
# window to the front when several are open).
$bestIdx = -1; $bestScore = 0; $wtPid = 0
foreach ($w in $AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $winCond)) {
  $i = 0
  foreach ($t in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCond)) {
    $name = Plain $t.Current.Name
    $score = 0
    if ($name -eq $want) { $score = 3 }
    elseif ($name.EndsWith($want) -or $name.Contains($want)) { $score = 2 }
    elseif ($want.Contains($name) -and $name.Length -ge 6) { $score = 1 }
    if ($score -gt $bestScore) { $bestIdx = $i; $bestScore = $score; $wtPid = $w.Current.ProcessId }
    $i++
  }
}
"$bestIdx;$wtPid"
