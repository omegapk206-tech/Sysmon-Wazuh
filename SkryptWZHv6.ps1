
$ErrorActionPreference = "Stop"

$LogDirectory = "C:\!APP"
$LogPath = Join-Path $LogDirectory "WymuszenieZmianyHasla.log"
$NetExe = "$env:SystemRoot\System32\net.exe"

if (-not (Test-Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message" -Encoding UTF8
}

try {
    Write-Log "========== START SKRYPTU =========="

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Brak uprawnien administratora."
    }

    Write-Log "Konfiguracja polityki hasel."

    & $NetExe accounts /minpwlen:8 /uniquepw:24 /minpwage:5

    if ($LASTEXITCODE -ne 0) {
        throw "Blad konfiguracji polityki hasel: $LASTEXITCODE"
    }

    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop

    $ExcludedUsers = @("motoadmin2", "omega")

    $Success = 0
    $Skipped = 0
    $Failed = 0

    foreach ($User in Get-LocalUser) {

        if (-not $User.Enabled) {
            Write-Log "POMINIETO: $($User.Name) - konto wylaczone."
            $Skipped++
            continue
        }

        if ($ExcludedUsers -contains $User.Name.ToLowerInvariant()) {
            Write-Log "POMINIETO: $($User.Name) - konto chronione."
            $Skipped++
            continue
        }

        if ($User.SID.Value -match '-500$') {
            Write-Log "POMINIETO: $($User.Name) - Administrator RID 500."
            $Skipped++
            continue
        }

        try {
            Write-Log "PRZETWARZANIE: $($User.Name)"

            # Wylaczenie Password never expires
            Set-LocalUser -Name $User.Name -PasswordNeverExpires $false -ErrorAction Stop

            # Wymaganie hasla
            & $NetExe user "$($User.Name)" /passwordreq:yes

            if ($LASTEXITCODE -ne 0) {
                throw "NET USER passwordreq error: $LASTEXITCODE"
            }

            # Wymuszenie zmiany hasla przez ADSI
            $AdsiUser = [ADSI]"WinNT://$env:COMPUTERNAME/$($User.Name),user"

            $AdsiUser.Put("PasswordExpired", [int]1)
            $AdsiUser.SetInfo()

            # Weryfikacja ustawien
            $Check = Get-LocalUser -Name $User.Name
            $AdsiCheck = [ADSI]"WinNT://$env:COMPUTERNAME/$($User.Name),user"

            if (-not $Check.PasswordRequired) {
                throw "PasswordRequired = False"
            }

            if ($Check.PasswordNeverExpires) {
                throw "PasswordNeverExpires = True"
            }

            if ([int]$AdsiCheck.Get("PasswordExpired") -ne 1) {
                throw "PasswordExpired nie zostal ustawiony."
            }

            Write-Log "OK: $($User.Name) - haslo wymagane, wygasanie wlaczone, zmiana przy nastepnym logowaniu wymagana."

            $Success++
        }
        catch {
            Write-Log "BLAD KONTA: $($User.Name) - $($_.Exception.Message)"
            $Failed++
        }
    }

    Write-Log "========== PODSUMOWANIE =========="
    Write-Log "Sukces: $Success"
    Write-Log "Pominieto: $Skipped"
    Write-Log "Bledy: $Failed"
    Write-Log "========== KONIEC =========="

    if ($Failed -gt 0) {
        exit 1
    }

    exit 0
}
catch {
    Write-Log "BLAD KRYTYCZNY: $($_.Exception.Message)"
    exit 1
}
