$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# 1. DEFINICJA ŚCIEŻEK - SZUKAMY TWOJEJ BINARKI
# Sysnative to tunel, który pozwala 32-bitowemu Wazuhowi wejść do C:\Windows\
$Paths = @(
    "$env:WinDir\sysnative\Sysmon64.exe", 
    "C:\Windows\Sysmon64.exe",
    "$env:WinDir\System32\Sysmon64.exe"
)

$SysmonPath = ""
foreach ($p in $Paths) { 
    if (Test-Path $p) { 
        $SysmonPath = $p
        break 
    } 
}

$WazuhDir = if (Test-Path "C:\Program Files (x86)\ossec-agent") { "C:\Program Files (x86)\ossec-agent" } else { "C:\Program Files\ossec-agent" }

$Version = "0"; $LiveHash = "BRAK"; $SharedHash = "BRAK"; $ReloadAttempted = "false"; $ReloadSucceeded = "false"

# 2. POBIERANIE DANYCH Z SYSMONA
if ($SysmonPath) {
    try { $Version = (Get-Item $SysmonPath).VersionInfo.FileVersion } catch { $Version = "BLAD_UPRAWNIEN" }
    
    # Próba wyciągnięcia hasha
    $RawOutput = & $SysmonPath -c -accepteula 2>&1 | Out-String
    if ($RawOutput -match 'SHA256=([A-Fa-f0-9]{64})') {
        $LiveHash = $Matches[1].ToUpper()
    }
} else {
    $Version = "NIE_ZNALEZIONO_SYSMON64_EXE"
}

# 3. POBIERANIE HASHU Z PLIKU WAZUHA (Shared)
$SharedConfigPath = Join-Path $WazuhDir "shared\sysmonconfig.xml"
if (Test-Path $SharedConfigPath) {
    $SharedHash = (Get-FileHash -Path $SharedConfigPath -Algorithm SHA256).Hash.ToUpper()
}

# 4. LOGIKA UNIWERSALNA (Reload jeśli BRAK lub inne hashe)
if ($SharedHash -ne "BRAK") {
    $NeedsReload = $false
    $StartStatus = $LiveHash

    if ($LiveHash -eq "BRAK") {
        # Scenariusz dla komputerów gdzie nie da się odczytać hasha
        $NeedsReload = $true
        $StartStatus = "BYL_BRAK_WYMUSZONO"
    } 
    elseif ($LiveHash -ne $SharedHash) {
        # Scenariusz gdy konfig jest po prostu stary
        $NeedsReload = $true
    }

    if ($NeedsReload -and $SysmonPath) {
        $ReloadAttempted = "true"
        # PRZEŁADOWANIE
        & $SysmonPath -c $SharedConfigPath -accepteula > $null 2>&1
        Start-Sleep -Seconds 2
        
        # Sprawdzenie czy teraz widać hash
        $RawAfter = & $SysmonPath -c -accepteula 2>&1 | Out-String
        if ($RawAfter -match 'SHA256=([A-Fa-f0-9]{64})') {
            $EndHash = $Matches[1].ToUpper()
            if ($EndHash -eq $SharedHash) { 
                $ReloadSucceeded = "true"
                $LiveHash = $EndHash 
            }
        } else {
            # Jeśli nadal BRAK, ale Sysmon przyjął komendę (ExitCode 0)
            if ($LASTEXITCODE -eq 0) { $ReloadSucceeded = "true" }
        }
    }
}

# 5. JSON - WYNIK DLA DASHBOARDU
$result = [ordered]@{
    "check-sysmon.version"           = $Version
    "check-sysmon.start_config_hash" = $StartStatus
    "check-sysmon.target_config_hash" = $SharedHash
    "check-sysmon.end_config_hash"   = $LiveHash
    "check-sysmon.reload_attempted"  = $ReloadAttempted
    "check-sysmon.reload_succeeded"  = $ReloadSucceeded
}

[Console]::WriteLine(($result | ConvertTo-Json -Compress))
exit 0