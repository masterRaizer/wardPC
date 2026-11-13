param([switch]$AfterReboot)
# Ward installer fix v5.
# Root cause found on this PC: Microsoft Gaming Services (Xbox) starts a silent install of
# gameinputredist.msi at every boot, the transaction hangs and holds the Windows Installer
# lock, so every other install fails with 1618 / "Another installation is in progress".
# The stuck msiserver process cannot be killed, and Gaming Services restarts the install
# within seconds. Fix: disable Gaming Services autostart, reboot, install Ward, restore it.
# Everything is written next to this script.

$ErrorActionPreference = 'Continue'
$dir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$me    = $MyInvocation.MyCommand.Path
$exe   = Join-Path $dir 'Ward-1.0.0.exe'
$msi   = Join-Path $dir 'Ward-1.0.0.msi'
$log   = Join-Path $dir 'ward-install.log'
$diag  = Join-Path $dir $(if ($AfterReboot) { 'ward-diag-after-reboot.txt' } else { 'ward-diag.txt' })
$saved = Join-Path $dir 'gaming-services-starttypes.json'
$task  = 'WardInstallAfterReboot'
$gsNames = 'GamingServices', 'GamingServicesNet', 'GameInputRedistService'

Start-Transcript -Path $diag -Force | Out-Null
Write-Host "Ward install fix v5  $(Get-Date -Format s)  AfterReboot=$AfterReboot"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "Elevated: $isAdmin"
if (-not $isAdmin) { Write-Host 'ERROR: run as administrator (use fix-ward-install.cmd)'; Stop-Transcript | Out-Null; Read-Host 'Press Enter'; exit 1 }
try { [Console]::TreatControlCAsInput = $true } catch {}
Write-Host 'Working... do NOT close this window and do not click inside it (clicking pauses the script).'

# ---------------- helpers ----------------
function Get-ProcInfo($id) {
    try { Get-CimInstance Win32_Process -Filter "ProcessId=$id" -OperationTimeoutSec 5 -ErrorAction Stop } catch { $null }
}
function Get-ScPid($name) {
    $line = sc.exe queryex $name | Where-Object { $_ -match '(PID|ID_)\S*\s*:\s*\d+' } | Select-Object -First 1
    if ($line -match '(\d+)\s*$') { [int]$Matches[1] } else { 0 }
}
function Get-SvcState { (Get-Service msiserver).Status }
function Test-SvcBusy { (sc.exe queryex msiserver | Out-String) -match 'NOT_STOPPABLE' }
function Kill-Pid($id, $why) {
    if (-not $id) { return }
    Write-Host "taskkill PID $id ($why)"
    cmd.exe /c "taskkill /F /PID $id 2>&1" | Out-String | Write-Host
}
function Show-MsiProcs($title) {
    Write-Host "`n== $title"
    $svcPid = Get-ScPid 'msiserver'
    $list = @(Get-Process msiexec -ErrorAction SilentlyContinue)
    if (-not $list) { Write-Host '(no msiexec.exe running)'; return }
    foreach ($gp in $list) {
        $role = if ($gp.Id -eq $svcPid) { 'SERVICE' } else { 'client' }
        Write-Host ("PID {0} [{1}] started {2}" -f $gp.Id, $role, $gp.StartTime)
        $p = Get-ProcInfo $gp.Id
        if ($p) {
            Write-Host ("   cmd: {0}" -f $p.CommandLine)
            $par = Get-ProcInfo $p.ParentProcessId
            Write-Host ("   parent: PID {0} {1}" -f $p.ParentProcessId, $(if ($par) { $par.Name } else { '(exited)' }))
        }
    }
}
function Get-MsiEvents($hours) {
    try { Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'MsiInstaller'; StartTime = (Get-Date).AddHours(-$hours) } -ErrorAction Stop | Sort-Object TimeCreated }
    catch { @() }
}
function Get-OpenTransaction {
    $ev = @(Get-MsiEvents 12)
    $begin = $ev | Where-Object Id -eq 1040 | Select-Object -Last 1
    $end   = $ev | Where-Object Id -eq 1042 | Select-Object -Last 1
    if (-not $begin -or ($end -and $end.TimeCreated -ge $begin.TimeCreated)) { return $null }
    $pkg = $null; try { $pkg = [string]$begin.Properties[0].Value } catch {}
    [pscustomobject]@{ Time = $begin.TimeCreated; Package = $pkg }
}
function Get-StartType($name) {
    $q = sc.exe qc $name | Out-String
    if ($q -match 'DISABLED') { 'disabled' }
    elseif ($q -match 'AUTO_START' -and $q -match 'DELAYED') { 'delayed-auto' }
    elseif ($q -match 'AUTO_START') { 'auto' }
    elseif ($q -match 'DEMAND_START') { 'demand' }
    else { $null }
}
function Stop-GamingServices {
    foreach ($gs in $gsNames) {
        if (-not (Get-Service $gs -ErrorAction SilentlyContinue)) { continue }
        sc.exe stop $gs | Out-Null
        for ($i = 0; $i -lt 10; $i++) { if ((Get-Service $gs).Status -eq 'Stopped') { break }; Start-Sleep 1 }
        if ((Get-Service $gs).Status -ne 'Stopped') { Kill-Pid (Get-ScPid $gs) "$gs did not stop" }
        Write-Host ("  {0}: {1}, start type {2}" -f $gs, (Get-Service $gs).Status, (Get-StartType $gs))
    }
    Get-Process gamingservices, gamingservicesnet, GameInputRedistService -ErrorAction SilentlyContinue | ForEach-Object { Kill-Pid $_.Id $_.ProcessName }
    # GameInput client installs started by Gaming Services
    $svcPid = Get-ScPid 'msiserver'
    Get-Process msiexec -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $svcPid } | ForEach-Object { Kill-Pid $_.Id 'msiexec client' }
}
function Disable-GamingServices {
    $orig = @{}
    if (Test-Path $saved) { try { (Get-Content $saved -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $orig[$_.Name] = $_.Value } } catch {} }
    foreach ($gs in $gsNames) {
        if (-not (Get-Service $gs -ErrorAction SilentlyContinue)) { continue }
        $t = Get-StartType $gs
        if (-not $orig.ContainsKey($gs) -and $t -and $t -ne 'disabled') { $orig[$gs] = $t }
        $r = sc.exe config $gs start= disabled | Out-String
        Write-Host ("  disable {0} (was {1}): {2}" -f $gs, $t, ($r -replace '\s+', ' ').Trim())
    }
    $orig | ConvertTo-Json | Set-Content -Path $saved -Encoding ASCII
    Write-Host "  original start types saved to $saved"
}
function Restore-GamingServices {
    if (-not (Test-Path $saved)) { Write-Host '  nothing to restore'; return }
    $orig = Get-Content $saved -Raw | ConvertFrom-Json
    foreach ($prop in $orig.PSObject.Properties) {
        $r = sc.exe config $prop.Name start= $prop.Value | Out-String
        Write-Host ("  restore {0} -> {1}: {2}" -f $prop.Name, $prop.Value, ($r -replace '\s+', ' ').Trim())
    }
    Remove-Item $saved -Force
    Write-Host '  Gaming Services will start again at next boot (and may retry its GameInput install).'
}
function Ensure-Msi {
    Write-Host "`n== Extracting MSI from Ward-1.0.0.exe"
    $expected = 'FC20685D8A71E6A69D71C528C8E04BDCE4FF4A9CBCA6249D98E063587F75FFBF'
    if (-not (Test-Path $msi) -or (Get-FileHash $msi -Algorithm SHA256).Hash -ne $expected) {
        $bytes = [IO.File]::ReadAllBytes($exe); $len = 86537049
        $buf = New-Object byte[] $len; [Array]::Copy($bytes, 579252, $buf, 0, $len)
        [IO.File]::WriteAllBytes($msi, $buf); $bytes = $null; $buf = $null; [GC]::Collect()
    }
    $ok = (Get-FileHash $msi -Algorithm SHA256).Hash -eq $expected
    Write-Host "MSI sha256 ok: $ok"
    Unblock-File $msi -ErrorAction SilentlyContinue
    return $ok
}
function Install-Ward {
    Write-Host "`n== Installing Ward (progress window only, folder C:\Program Files\Ward)"
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /passive /norestart /l*v `"$log`"" -PassThru
    $t0 = Get-Date
    while (-not $p.HasExited) {
        Start-Sleep 10
        $el = [int]((Get-Date) - $t0).TotalSeconds
        $sz = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
        Write-Host ("  ...{0}s, log {1} KB" -f $el, [int]($sz / 1KB))
        if ($el -ge 1200) { Write-Host '  giving up waiting after 20 min'; break }
    }
    $code = if ($p.HasExited) { $p.ExitCode } else { -1 }
    $meaning = @{ 0 = 'SUCCESS'; 3010 = 'SUCCESS, reboot required'; 1618 = 'another install still holds the lock'; 1602 = 'cancelled'; 1603 = 'fatal error - see ward-install.log'; 1601 = 'Windows Installer service unavailable'; 1625 = 'blocked by policy'; 1638 = 'another version already installed'; -1 = 'still running' }[$code]
    Write-Host "msiexec exit code: $code  $meaning"
    if ($code -ne 0 -and $code -ne 3010 -and (Test-Path $log)) {
        Select-String -Path $log -Pattern 'Return value 3|MainEngineThread is returning|1618' -ErrorAction SilentlyContinue |
            Select-Object -Last 15 | ForEach-Object { Write-Host ('  ' + $_.Line) }
    }
    return $code
}
function Wait-LockFree($sec) {
    for ($i = 0; $i -lt $sec; $i += 5) { if (-not (Test-SvcBusy)) { return $true }; Start-Sleep 5 }
    return (-not (Test-SvcBusy))
}
function Finish($code) {
    Stop-Transcript | Out-Null
    Write-Host "`nDiagnostics: $diag`nInstall log: $log"
    Read-Host 'Done. Press Enter to close'
    exit $code
}

# ================= after reboot =================
if ($AfterReboot) {
    schtasks.exe /Delete /TN $task /F 2>&1 | Out-String | Write-Host     # one-shot
    try { Write-Host ("Boot time: {0}" -f (Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5).LastBootUpTime) } catch {}
    Write-Host 'Waiting for Windows to settle (20 s)...'; Start-Sleep 20
    Show-MsiProcs 'msiexec processes after reboot'
    Write-Host ("installer busy: {0}" -f (Test-SvcBusy))
    if (-not (Wait-LockFree 180)) {
        $tx = Get-OpenTransaction
        Write-Host ("ERROR: the installer is still busy. Open transaction: {0} {1}" -f $tx.Time, $tx.Package)
        Show-MsiProcs 'msiexec processes'
        Restore-GamingServices; Finish 4
    }
    if (-not (Ensure-Msi)) { Restore-GamingServices; Finish 2 }
    $code = Install-Ward
    Write-Host "`n== Restoring Gaming Services"
    Restore-GamingServices
    Finish $code
}

# ================= normal run =================
try { Write-Host ("Boot time: {0}" -f (Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5).LastBootUpTime) } catch {}
Show-MsiProcs 'msiexec processes BEFORE fix'
Write-Host ("`ninstaller busy with a transaction: {0}" -f (Test-SvcBusy))
$tx = Get-OpenTransaction
if ($tx) { Write-Host ("open transaction since {0}: {1}" -f $tx.Time, $tx.Package) }

$ip = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\InProgress'
if (Test-Path $ip) { Get-ItemProperty $ip | Format-List | Out-String | Write-Host; Remove-Item $ip -Recurse -Force; Write-Host 'stale InProgress key REMOVED' }

Write-Host "`n== Pausing Gaming Services (Xbox) - it keeps restarting the GameInput install"
Disable-GamingServices
Stop-GamingServices

Write-Host "`n== Trying to free the installer lock without reboot"
if (Test-SvcBusy) {
    Kill-Pid (Get-ScPid 'msiserver') 'Windows Installer service stuck in the GameInput transaction'
    [void](Wait-LockFree 20)
} elseif ((Get-SvcState) -ne 'Stopped') { sc.exe stop msiserver | Out-Null; Start-Sleep 3 }
Write-Host ("installer busy: {0}   service: {1}" -f (Test-SvcBusy), (Get-SvcState))

if (-not (Test-SvcBusy)) {
    if (-not (Ensure-Msi)) { Restore-GamingServices; Finish 2 }
    $code = Install-Ward
    Write-Host "`n== Restoring Gaming Services"
    Restore-GamingServices
    Finish $code
}

# lock can only be released by a reboot -> install automatically after it
Write-Host "`n== The stuck transaction can only be cleared by a reboot."
Write-Host 'Gaming Services autostart is disabled now, so after the reboot nothing will grab the lock.'
$user = "$env:USERDOMAIN\$env:USERNAME"
try {
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$me`" -AfterReboot"
    $trg = New-ScheduledTaskTrigger -AtLogOn -User $user
    $pr  = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $task -Action $act -Trigger $trg -Principal $pr -Force -ErrorAction Stop | Out-Null
    Write-Host "One-time task '$task' registered: after you log in, Ward installs by itself, then Gaming Services is restored and the task deletes itself."
} catch {
    Write-Host "Could not register the task ($($_.Exception.Message)). After reboot run fix-ward-install.cmd again."
}
Stop-Transcript | Out-Null
$ans = Read-Host "`nReboot now? Type Y and press Enter (anything else = reboot later yourself)"
if ($ans -match '^[yY]' -or ($ans.Length -gt 0 -and ([int][char]$ans[0] -eq 0x0434 -or [int][char]$ans[0] -eq 0x0414))) { Restart-Computer -Force }
