# Creates "GoldScalper Console" shortcuts on the Desktop and in the Start menu that open
# tools\GS15_Console.ps1 (same as double-clicking GS15_Console.bat).
#   powershell -ExecutionPolicy Bypass -File tools\Make-ConsoleShortcut.ps1
param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'

$script = Join-Path $Root 'tools\GS15_Console.ps1'
if (-not (Test-Path $script)) { throw "Console script not found: $script" }
$icon = 'C:\Program Files\MetaTrader 5\terminal64.exe'
if (-not (Test-Path $icon)) { $icon = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }

$shell = New-Object -ComObject WScript.Shell
$targets = @(
    [Environment]::GetFolderPath('Desktop'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'GoldScalperM15')
)
foreach ($dir in $targets) {
    New-Item -ItemType Directory -Force $dir | Out-Null
    # WScript.Shell cannot save to non-ASCII paths (e.g. a Thai "Desktop" folder name):
    # build it in TEMP, then move it with PowerShell.
    $tmp = Join-Path $env:TEMP 'GoldScalper Console.lnk'
    $lnk = $shell.CreateShortcut($tmp)
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $wt = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
    if (Test-Path $wt) {
        # Windows Terminal: a new window sized for the whole panel and the event journal.
        $lnk.TargetPath = $wt
        $lnk.Arguments  = "-w new --size 74,48 --title `"GoldScalper console`" `"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$script`""
    } else {
        $lnk.TargetPath = $ps
        $lnk.Arguments  = "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
    }
    $lnk.WorkingDirectory = $Root
    $lnk.IconLocation     = "$icon,0"
    $lnk.Description      = 'GoldScalperM15 console: live status, controls and event journal'
    $lnk.Save()
    Move-Item -LiteralPath $tmp -Destination (Join-Path $dir 'GoldScalper Console.lnk') -Force
    "Created: $(Join-Path $dir 'GoldScalper Console.lnk')"
}
