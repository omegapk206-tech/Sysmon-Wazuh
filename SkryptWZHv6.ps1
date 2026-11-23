
# SkryptWZHv6.ps1
# Konfiguracja lokalnych kont użytkownikow Windows 10/11

$ErrorActionPreference = "Stop"

$LogDirectory = "C:\!APP"
$LogPath = Join-Path $LogDirectory "WymuszenieZmianyHasla.log"

if (!(Test-Path -LiteralPath $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $Line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    Add-Content -LiteralPath $LogPath -Value $Line -Encoding UTF8
}

function Invoke-LoggedCommand {
    param(
        [string]$Description,
        [scriptblock]$Command
    )

    try {
        & $Command
        if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
            throw "Kod wyjscia: $LASTEXITCODE"
        }
        Write-Log "OK: $Description"
        return $true
    }
    catch {
        Write-Log "BLAD: $Description - $($_.Exception.Message)"
        return $false
    }
}

Write-Log "========== START SKRYPTWZHv6 =========="

# Kontrola uprawnien
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

if (!$Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "BLAD: Skrypt nie ma uprawnien administratora."
    exit 1
}

Write-Log "Uruchomiono jako: $($Identity.Name)"

# Polityka haseł komputera
try {
    & net.exe accounts /minpwlen:8 /uniquepw:24 /minpwage:5
    if ($LASTEXITCODE -ne 0) {
        throw "net accounts zwrocil kod $LASTEXITCODE"
    }
    Write-Log "OK: Polityka hasel: minimum 8 znakow, historia 24, minimalny wiek 5 dni."
}
catch {
    Write-Log "BLAD POLITYKI HASel: $($_.Exception.Message)"
}

# Moduł kont lokalnych
try {
    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop
}
catch {
    Write-Log "BLAD: Nie mozna zaladowac Microsoft.PowerShell.LocalAccounts: $($_.Exception.Message)"
    exit 1
}

$Success = 0
$Skipped = 0
$Errors = 0

$ProtectedAccounts = @("motoadmin2", "omega")

try {
    $Users = Get-LocalUser -ErrorAction Stop
}
catch {
    Write-Log "BLAD: Nie mozna pobrac listy kont: $($_.Exception.Message)"
    exit 1
}

foreach ($User in $Users) {

    # Pomijanie kont wylaczonych
    if (!$User.Enabled) {
        Write-Log "POMINIETO: $($User.Name) - konto wylaczone."
        $Skipped++
        continue
    }

    # Pomijanie kont chronionych
    if ($ProtectedAccounts -contains $User.Name) {
        Write-Log "POMINIETO: $($User.Name) - konto chronione."
        $Skipped++
        continue
    }

    # Pomijanie wbudowanego Administratora po SID RID 500
    if ($User.SID.Value -match '-500$') {
        Write-Log "POMINIETO: $($User.Name) - wbudowane konto Administrator."
        $Skipped++
        continue
    }

    Write-Log "PRZETWARZANIE: $($User.Name)"
    $AccountErrors = 0

    # 1. Wymaganie hasla
    try {
        & net.exe user $User.Name /passwordreq:yes
        if ($LASTEXITCODE -ne 0) {
            throw "net user zwrocil kod $LASTEXITCODE"
        }
        Write-Log "OK: $($User.Name) - PasswordRequired."
    }
    catch {
        Write-Log "BLAD PasswordRequired: $($User.Name) - $($_.Exception.Message)"
        $AccountErrors++
    }

    # 2. Haslo ma wygasac
    try {
        Set-LocalUser -Name $User.Name -PasswordNeverExpires $false -ErrorAction Stop
        Write-Log "OK: $($User.Name) - PasswordNeverExpires=False."
    }
    catch {
        Write-Log "BLAD PasswordNeverExpires: $($User.Name) - $($_.Exception.Message)"
        $AccountErrors++
    }

    # 3. Wymuszenie zmiany hasla przy nastepnym logowaniu
    try {
        $AdsiPath = "WinNT://$env:COMPUTERNAME/$($User.Name),user"
        $AdsiUser = [ADSI]$AdsiPath
        $AdsiUser.Put("PasswordExpired", [int]1)
        $AdsiUser.SetInfo()
        Write-Log "OK: $($User.Name) - ustawiono PasswordExpired=1."
    }
    catch {
        Write-Log "BLAD PasswordExpired: $($User.Name) - $($_.Exception.Message)"
        $AccountErrors++
    }

    # 4. Weryfikacja ustawienia PasswordNeverExpires
    try {
        $CheckUser = Get-LocalUser -Name $User.Name -ErrorAction Stop
        if ($CheckUser.PasswordNeverExpires) {
            throw "Haslo nadal ma ustawienie PasswordNeverExpires=True"
        }
        Write-Log "OK: $($User.Name) - weryfikacja PasswordNeverExpires."
    }
    catch {
        Write-Log "BLAD WERYFIKACJI: $($User.Name) - $($_.Exception.Message)"
        $AccountErrors++
    }

    if ($AccountErrors -eq 0) {
        $Success++
        Write-Log "ZAKONCZONO POPRAWNIE: $($User.Name)"
    }
    else {
        $Errors++
        Write-Log "KONTO Z BLEDAMI: $($User.Name), liczba bledow: $AccountErrors"
    }
}

Write-Log "========== PODSUMOWANIE =========="
Write-Log "Sukces: $Success"
Write-Log "Pominieto: $Skipped"
Write-Log "Bledy: $Errors"
Write-Log "========== KONIEC =========="

if ($Errors -gt 0) {
    exit 1
}
else {
    exit 0
}
