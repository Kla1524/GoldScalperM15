# Adds (or with -Remove deletes) the Startup shortcut that asks to start MT5 GoldScalper at logon.
# Run it from your own Windows session (Install-Autostart.cmd / Remove-Autostart.cmd).
param([switch]$Remove)
$startup = [Environment]::GetFolderPath('Startup')
$lnkPath = Join-Path $startup 'MT5 GoldScalper Ask.lnk'
$log = Join-Path $PSScriptRoot 'autostart_log.txt'
if ($Remove) {
    if (Test-Path -LiteralPath $lnkPath) { Remove-Item -LiteralPath $lnkPath }
    Add-Content $log ("{0:yyyy-MM-dd HH:mm:ss} startup shortcut removed" -f (Get-Date))
    return
}
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$tmp = Join-Path $env:TEMP 'MT5 GoldScalper Ask.lnk'
$l = (New-Object -ComObject WScript.Shell).CreateShortcut($tmp)
$l.TargetPath = $ps
$l.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSScriptRoot\Start-MT5-Ask.ps1`""
$l.WorkingDirectory = $PSScriptRoot
$l.WindowStyle = 7
$l.IconLocation = 'D:\MT5_GoldScalper\terminal64.exe,0'
$l.Description = 'Asks at logon whether to start MT5 GoldScalper'
$l.Save()
Move-Item -LiteralPath $tmp -Destination $lnkPath -Force
Add-Content $log ("{0:yyyy-MM-dd HH:mm:ss} startup shortcut installed: {1}" -f (Get-Date), $lnkPath)
