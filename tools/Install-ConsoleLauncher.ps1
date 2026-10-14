# Installs the console launcher so the "Console" button on the MT5 chart can open / close the
# PowerShell console: adds a hidden shortcut to the Windows Startup folder and starts it now.
#   powershell -ExecutionPolicy Bypass -File tools\Install-ConsoleLauncher.ps1 [-Remove]
param([string]$Root = (Split-Path $PSScriptRoot -Parent), [switch]$Remove)
$ErrorActionPreference = 'Stop'

$launcher = Join-Path $Root 'tools\GS15_ConsoleLauncher.ps1'
$startup  = [Environment]::GetFolderPath('Startup')
$lnkPath  = Join-Path $startup 'GoldScalper Console Launcher.lnk'
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$argLine = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcher`" -Root `"$Root`""

if ($Remove) {
    Set-Content "$env:APPDATA\MetaQuotes\Terminal\Common\Files\GS15_console_launcher_stop.txt" 'stop'
    if (Test-Path -LiteralPath $lnkPath) { Remove-Item -LiteralPath $lnkPath }
    'Launcher removed from Startup and asked to stop.'
    return
}

# WScript.Shell cannot save to non-ASCII paths: build in TEMP, then move.
$tmp = Join-Path $env:TEMP 'GoldScalper Console Launcher.lnk'
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($tmp)
$lnk.TargetPath  = $ps
$lnk.Arguments   = $argLine
$lnk.WindowStyle = 7          # minimized; the script itself runs hidden
$lnk.WorkingDirectory = $Root
$lnk.Description = 'Opens / closes the GoldScalperM15 console when the Console button on the MT5 chart is clicked'
$lnk.Save()
Move-Item -LiteralPath $tmp -Destination $lnkPath -Force
"Startup shortcut: $lnkPath"

Start-Process $ps -ArgumentList $argLine -WindowStyle Hidden
'Launcher started.'
