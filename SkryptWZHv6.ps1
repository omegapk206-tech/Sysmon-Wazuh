
# ============================================================
# WYMUSZENIE ZMIANY HASLA - KONTA LOKALNE
# Windows 10 / Windows 11 / Microsoft Intune
#
# Wyjatki:
#   motoadmin2
#   omega
#   Wbudowany Administrator (RID 500)
#
# Polityka:
#   Minimalna dlugosc: 8 znakow
#   Historia hasel: 24
#   Minimalny czas zmiany: 5 dni
# ============================================================

$ErrorActionPreference = "Stop"

# Katalog i plik logu
$LogDirectory = "C:\!APP"
$LogPath = Join-Path $LogDirectory "WymuszenieZmianyHasla.log"

if (-not (Test-Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}
$NetExe = "$env:SystemRoot\System32\net.exe"

# Utworzenie katalogu logow
if (-not (Test-Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message)

    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -Path $LogPath -Value $Line -Encoding UTF8
}

try {

    Write-Log "========== START SKRYPTU =========="

    # --------------------------------------------------------
    # 1. Sprawdzenie uprawnien administratora
    # --------------------------------------------------------

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

    if (-not $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )) {
        throw "Skrypt nie zostal uruchomiony z uprawnieniami administratora."
    }

    # --------------------------------------------------------
    # 2. Konfiguracja lokalnej polityki hasel
    # --------------------------------------------------------

    Write-Log "Konfiguracja polityki hasel."

    & $NetExe accounts /minpwlen:8 /uniquepw:24 /minpwage:5

    if ($LASTEXITCODE -ne 0) {
        throw "Blad konfiguracji polityki hasel. Kod: $LASTEXITCODE"
    }

    # --------------------------------------------------------
    # 3. Konta wykluczone
    # --------------------------------------------------------

    $ExcludedUsers = @(
        "motoadmin2",
        "omega"
    )

    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop

    $Users = Get-LocalUser

    $Success = 0
    $Skipped = 0
    $Failed = 0

    # --------------------------------------------------------
    # 4. Przetwarzanie kont lokalnych
    # --------------------------------------------------------

    foreach ($User in $Users) {

        # Pomijanie kont wylaczonych
        if (-not $User.Enabled) {
            Write-Log "POMINIETO: $($User.Name) - konto wylaczone."
            $Skipped++
            continue
        }

        # Pomijanie kont chronionych
        if ($ExcludedUsers -contains $User.Name) {
            Write-Log "POMINIETO: $($User.Name) - konto chronione."
            $Skipped++
            continue
        }

        # Pomijanie wbudowanego Administratora (RID 500)
        if ($User.SID.Value -match '-500$') {
            Write-Log "POMINIETO: $($User.Name) - wbudowany Administrator."
            $Skipped++
            continue
        }

        try {

            Write-Log "PRZETWARZANIE: $($User.Name)"

            # Wylaczenie opcji Password never expires
            Set-LocalUser -Name $User.Name -PasswordNeverExpires $false

            # Wymaganie hasla i wymuszenie jego zmiany
            & $NetExe user "$($User.Name)" /passwordreq:yes /logonpasswordchg:yes

            if ($LASTEXITCODE -ne 0) {
                throw "NET USER zwrocil kod bledu: $LASTEXITCODE"
            }

            # Kontrola wymagalnosci hasla
            $Check = Get-LocalUser -Name $User.Name

            if (-not $Check.PasswordRequired) {
                throw "Konto nadal nie wymaga hasla."
            }

            Write-Log "OK: $($User.Name) - PasswordRequired=Yes, PasswordNeverExpires=No, zmiana przy logowaniu ustawiona."

            $Success++

        }
        catch {

            Write-Log "BLAD KONTA: $($User.Name) - $($_.Exception.Message)"
            $Failed++
        }
    }

    # --------------------------------------------------------
    # 5. Podsumowanie
    # --------------------------------------------------------

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
