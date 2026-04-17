$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$SysmonPath = @("C:\Windows\sysmon64.exe", "C:\Windows\sysmon.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$WazuhDir  = @("C:\Program Files (x86)\ossec-agent", "C:\Program Files\ossec-agent") | Where-Object { Test-Path $_ } | Select-Object -First 1

$Version = 0
$StartConfigHash = ""
$LiveConfigHash = ""
$SharedConfigHash = ""
$ReloadAttempted = $false
$ReloadSucceeded = $false

# Confirm what version--if any--of Sysmon is present. A version of zero means Sysmon is absent.
if ($SysmonPath) {
    try {
        $Version = (Get-Item $SysmonPath).VersionInfo.FileVersion
    } catch {
        $Version = 0
    }
}

# Bail with terse output if Sysmon absent.
if ($Version -eq 0) {
    $result = @{
        "check-sysmon.version" = "$Version"
    }
    [Console]::WriteLine(($result | ConvertTo-Json -Compress))
    exit 0
}

# Get live Sysmon config hash
$ConfigHashLine = (& $SysmonPath -c 2>$null) | Where-Object { $_ -match '^\s*-\s*Config hash:\s*SHA256=' } | Select-Object -First 1
if ($ConfigHashLine -and ($ConfigHashLine -match 'SHA256=([A-Fa-f0-9]{64})')) {
    $LiveConfigHash = $Matches[1].ToUpper()
}

# Compare to shared config and reload if needed
if ($LiveConfigHash) {
    $StartConfigHash = $LiveConfigHash
    $SharedConfigPath = Join-Path $WazuhDir "shared\sysmonconfig.xml"

    if (Test-Path $SharedConfigPath) {
        $SharedConfigHash = (Get-FileHash -Path $SharedConfigPath -Algorithm SHA256).Hash.ToUpper()

        if ($LiveConfigHash -ne $SharedConfigHash) {
            $ReloadAttempted = $true

            # Suppress all stdout/stderr from Sysmon reload command
            & $SysmonPath -c $SharedConfigPath > $null 2>&1

            Start-Sleep -Milliseconds 500

            # Reacquire live hash
            $ConfigHashLine = (& $SysmonPath -c 2>$null) | Where-Object { $_ -match '^\s*-\s*Config hash:\s*SHA256=' } | Select-Object -First 1
            if ($ConfigHashLine -and ($ConfigHashLine -match 'SHA256=([A-Fa-f0-9]{64})')) {
                $LiveConfigHash = $Matches[1].ToUpper()
            }

            if ($LiveConfigHash -eq $SharedConfigHash) {
                $ReloadSucceeded = $true
            }
        }
    }
}

# Report findings and results as a single-line JSON record
$result = [ordered]@{
    "check-sysmon.version" = "$Version"
    "check-sysmon.start_config_hash" = "$StartConfigHash"
    "check-sysmon.target_config_hash" = "$SharedConfigHash"
    "check-sysmon.end_config_hash" = "$LiveConfigHash"
    "check-sysmon.reload_attempted" = if ($ReloadAttempted) { "true" } else { "false" }
}

if ($ReloadAttempted) {
    $result["check-sysmon.reload_succeeded"] = if ($ReloadSucceeded) { "true" } else { "false" }
}

[Console]::WriteLine(($result | ConvertTo-Json -Compress))
exit 0