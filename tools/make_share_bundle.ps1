# Collects source, rules, settings and backtest results into one folder (and a .zip) to share for review,
# with personal data removed: account numbers, MQL5 / GitHub logins, e-mail addresses and IP addresses.
#   powershell -ExecutionPolicy Bypass -File tools\make_share_bundle.ps1 -Name GS15_baseline_20261015 -Suite reports\experiments\suite_20261015
param(
    [Parameter(Mandatory)] [string]$Name,
    [Parameter(Mandatory)] [string[]]$Suite,          # one or more suite folders (relative to the repo or absolute)
    [string]$Repo = 'D:\EA_Trade_lab\repo',
    [string]$OutRoot = 'D:\EA_Trade_lab\share',
    [string[]]$Mask = @()                              # extra literal strings to remove (e.g. an account number)
)
$ErrorActionPreference = 'Stop'
$Suite = @($Suite | ForEach-Object { $_ -split ',' } | Where-Object { $_ })   # -File passes a list as one string
$Mask  = @($Mask  | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$out = Join-Path $OutRoot $Name
if (Test-Path $out) { throw "$out exists - choose another name" }
New-Item -ItemType Directory -Force "$out\src", "$out\presets", "$out\docs", "$out\results" | Out-Null

Copy-Item "$Repo\GoldScalperM15.mq5", "$Repo\GS15_SMC.mqh" "$out\src\"
if (Test-Path "$Repo\tools\SMC_Tests.mq5") { Copy-Item "$Repo\tools\SMC_Tests.mq5" "$out\src\" }
Copy-Item "$Repo\presets\*.set" "$out\presets\" -ErrorAction SilentlyContinue
foreach ($d in 'SMC_RULES.md', 'CODE_REVIEW.md') { if (Test-Path "$Repo\docs\$d") { Copy-Item "$Repo\docs\$d" "$out\docs\" } }
foreach ($s in $Suite) {
    $src = if ([IO.Path]::IsPathRooted($s)) { $s } else { Join-Path $Repo $s }
    $dst = Join-Path "$out\results" (Split-Path $src -Leaf)
    Copy-Item $src $dst -Recurse
    Remove-Item "$dst\DONE" -ErrorAction SilentlyContinue
}
$commit = git -C $Repo rev-parse --short HEAD
$branch = git -C $Repo rev-parse --abbrev-ref HEAD
Set-Content "$out\VERSION.txt" "branch $branch, commit $commit, made $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -Encoding UTF8

# Personal data: account numbers (6-12 digits after login/account words, and any -Mask string),
# MQL5 / GitHub logins, e-mail addresses, IPv4 addresses (except 127.0.0.1), Windows user paths.
$patterns = @(
    '(?i)(login|account|acc\.?)(\s*[#:=]?\s*)\d{6,12}',
    '(?i)activated for ''[^'']+''',
    '[\w.+-]+@[\w-]+\.[\w.]+',
    '\b(?!127\.0\.0\.1\b)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b',
    '(?i)C:\\Users\\[^\\]+'
)
$repl = @('$1$2<account>', 'activated for ''<login>''', '<email>', '<ip>', 'C:\Users\<user>')
$changed = 0
foreach ($f in Get-ChildItem $out -Recurse -File | Where-Object { $_.Extension -in '.mq5', '.mqh', '.md', '.set', '.csv', '.htm', '.html', '.log', '.txt', '.ini' }) {
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $enc = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { [Text.Encoding]::Unicode } else { New-Object Text.UTF8Encoding $false }
    $t = $enc.GetString($bytes)
    if ($enc -is [Text.UnicodeEncoding]) { $t = $t.TrimStart([char]0xFEFF) }
    $o = $t
    for ($i = 0; $i -lt $patterns.Count; $i++) { $t = [regex]::Replace($t, $patterns[$i], $repl[$i]) }
    foreach ($m in $Mask) { if ($m) { $t = $t.Replace($m, '<masked>') } }
    if ($t -ne $o) {
        if ($enc -is [Text.UnicodeEncoding]) { [IO.File]::WriteAllText($f.FullName, $t, [Text.Encoding]::Unicode) } else { [IO.File]::WriteAllText($f.FullName, $t, $enc) }
        $changed++
    }
}
$zip = "$out.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path "$out\*" -DestinationPath $zip
"{0}: {1} files, {2} cleaned, zip {3:N0} KB" -f $out, (Get-ChildItem $out -Recurse -File).Count, $changed, ((Get-Item $zip).Length / 1KB)
