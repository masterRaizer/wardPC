# Ward 1.0.0 -> fix1: исправленный ward-desktop jar + ядро Xray v26.11.9
$ErrorActionPreference = 'Stop'
$JarName = 'ward-desktop-1.0.0-e812b7fd1b33d7d13a8cbb65d52b2.jar'
$JarSha  = '8946e5e208ca8bbb43b10c2a2e99d51e665eb32f83c8f70a93706989cf72a036'
$XraySha = '1ca7a2cf61ba2c5d20b21a80d405b57933939751081cb289f07bd8ddf7cc3185'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Fail($m) { Write-Host "ОШИБКА: $m" -ForegroundColor Red; Read-Host 'Enter - выход'; exit 1 }
function Sha($p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower() }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Start-Process powershell -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$($MyInvocation.MyCommand.Path)`"")
    exit
}

try {
    $newJar  = Join-Path $Here "files\$JarName"
    $newXray = Join-Path $Here 'files\xray.exe'
    if (-not (Test-Path $newJar) -or -not (Test-Path $newXray)) { Fail 'рядом нет папки files - распакуйте архив целиком' }
    if ((Sha $newJar) -ne $JarSha)   { Fail 'jar в архиве повреждён (не совпала контрольная сумма)' }
    if ((Sha $newXray) -ne $XraySha) { Fail 'xray.exe в архиве повреждён (не совпала контрольная сумма)' }

    # где установлен Ward
    $cands = @()
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        Get-ItemProperty $k -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq 'Ward' -and $_.InstallLocation } |
            ForEach-Object { $cands += $_.InstallLocation }
    }
    $cands += "$env:ProgramFiles\Ward", "${env:ProgramFiles(x86)}\Ward", "$env:LOCALAPPDATA\Ward", "$env:LOCALAPPDATA\Programs\Ward"
    Get-Process Ward -ErrorAction SilentlyContinue | ForEach-Object { if ($_.Path) { $cands += (Split-Path -Parent $_.Path) } }
    $dir = $cands | Where-Object { $_ -and (Test-Path (Join-Path $_ "app\$JarName")) } | Select-Object -First 1
    if (-not $dir) {
        $dir = (Read-Host 'Ward не найден. Вставьте путь к папке, где лежит Ward.exe').Trim('"',' ')
        if (-not (Test-Path (Join-Path $dir "app\$JarName"))) { Fail "в '$dir' нет app\$JarName (нужен именно Ward 1.0.0)" }
    }
    $dir = $dir.TrimEnd('\')
    Write-Host "Ward найден: $dir"
    $jar  = Join-Path $dir "app\$JarName"
    $xray = Join-Path $dir 'app\resources\xray.exe'

    # закрыть Ward и его ядро
    Get-Process Ward -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process xray -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $xray } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # резервная копия
    $bak = Join-Path $dir ("backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $bak | Out-Null
    Copy-Item -LiteralPath $jar -Destination $bak
    if (Test-Path $xray) { Copy-Item -LiteralPath $xray -Destination $bak }
    Write-Host "Старые файлы сохранены: $bak"

    Copy-Item -LiteralPath $newJar  -Destination $jar  -Force
    Copy-Item -LiteralPath $newXray -Destination $xray -Force
    if ((Sha $jar) -ne $JarSha -or (Sha $xray) -ne $XraySha) { Fail 'файлы скопировались с ошибкой, верните их из папки backup' }

    $ver = (& $xray version 2>&1 | Select-Object -First 1)
    Write-Host "Ядро: $ver" -ForegroundColor Green
    Write-Host 'Готово. Запускаю Ward...' -ForegroundColor Green
    Start-Process explorer.exe (Join-Path $dir 'Ward.exe')
} catch {
    Fail $_.Exception.Message
}
Read-Host 'Enter - выход'
