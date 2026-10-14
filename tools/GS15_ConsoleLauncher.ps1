# GoldScalperM15 console launcher (runs hidden in the background, started at Windows logon).
# Opens / closes the console when the "Console" button on the MT5 chart is clicked:
#   the EA writes  Common\Files\GS15_console_request.txt  (TOGGLE / OPEN / CLOSE)
#   this script answers in  Common\Files\GS15_console_state.txt  (heartbeat + open/closed)
# No DLL imports in the EA: the EA only writes a file.
# Install / start: tools\Install-ConsoleLauncher.ps1. Stop: end "powershell" with this script in Task Manager,
# or create Common\Files\GS15_console_launcher_stop.txt.
param([string]$Root = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Continue'
$files   = "$env:APPDATA\MetaQuotes\Terminal\Common\Files"
$request = "$files\GS15_console_request.txt"
$state   = "$files\GS15_console_state.txt"
$stop    = "$files\GS15_console_launcher_stop.txt"
$console = Join-Path $Root 'tools\GS15_Console.ps1'
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$wt = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'

# One launcher at a time.
$mutex = New-Object Threading.Mutex($false, 'Local\GS15ConsoleLauncher')
if (-not $mutex.WaitOne(0)) { exit }

$pidFile = "$files\GS15_console_pid.txt"

# The console writes its PID while it runs: checking that PID is instant (a process scan takes seconds).
function Get-ConsolePid {
    try {
        $id = [int](Get-Content $pidFile -ErrorAction Stop | Select-Object -First 1)
        $p = Get-Process -Id $id -ErrorAction Stop
        if ($p.ProcessName -eq 'powershell') { return $id }
    } catch {}
    return 0
}

# Every console window (also ones opened from the shortcut), for Close.
function Get-AllConsolePids {
    @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -match 'GS15_Console\.ps1' -and $_.CommandLine -notmatch '-Snapshot' } |
      ForEach-Object { $_.ProcessId })
}

function Open-Console {
    if (Test-Path $wt) {
        Start-Process $wt -ArgumentList "-w new --size 74,48 --title `"GoldScalper console`" `"$ps`" -NoProfile -ExecutionPolicy Bypass -File `"$console`""
    } else {
        Start-Process $ps -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$console`""
    }
}

try {
    while (-not (Test-Path $stop)) {
        $open = (Get-ConsolePid) -ne 0
        if (Test-Path $request) {
            $cmd = ''
            try { $cmd = ([IO.File]::ReadAllText($request)).Trim().ToUpper() } catch {}
            Remove-Item $request -ErrorAction SilentlyContinue
            if ($cmd -eq 'OPEN' -or ($cmd -eq 'TOGGLE' -and -not $open)) {
                if (-not $open) {
                    Open-Console
                    $until = (Get-Date).AddSeconds(10)            # wait until the window has started
                    while ((Get-ConsolePid) -eq 0 -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 200 }
                }
            } elseif ($cmd -eq 'CLOSE' -or $cmd -eq 'TOGGLE') {
                $ids = @(Get-AllConsolePids) + @(Get-ConsolePid) | Where-Object { $_ -gt 0 } | Select-Object -Unique
                $ids | ForEach-Object { Stop-Process -Id $_ -ErrorAction SilentlyContinue }
                Remove-Item $pidFile -ErrorAction SilentlyContinue
            }
            Remove-Item $request -ErrorAction SilentlyContinue      # ignore clicks made while this one ran
            $open = (Get-ConsolePid) -ne 0
        }
        $text = "launcher={0:yyyy.MM.dd HH:mm:ss}`r`nconsole={1}`r`n" -f (Get-Date), $(if ($open) { 'open' } else { 'closed' })
        try { [IO.File]::WriteAllText($state, $text, [Text.Encoding]::ASCII) } catch {}
        Start-Sleep -Milliseconds 400
    }
} finally {
    Remove-Item $stop -ErrorAction SilentlyContinue
    try { [IO.File]::WriteAllText($state, "launcher=stopped`r`nconsole=unknown`r`n", [Text.Encoding]::ASCII) } catch {}
    $mutex.ReleaseMutex()
}
