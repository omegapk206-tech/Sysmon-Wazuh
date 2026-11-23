
$ErrorActionPreference = "Stop"
$LogDirectory = "C:\!APP"
$LogPath = Join-Path $LogDirectory "WymuszenieZmianyHasla.log"

if (!(Test-Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    Add-Content -LiteralPath $LogPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message" -Encoding UTF8
}

try {
    Write-Log "========== START SKRYPTWZHv6 =========="

    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

    if (!$Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Brak uprawnien - uruchamiam ponownie jako administrator."
        $Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $Process = Start-Process -FilePath "$PSHOME\powershell.exe" -ArgumentList $Arguments -Verb RunAs -Wait -PassThru
        Write-Log "Proces administratora zakonczony. Kod: $($Process.ExitCode)"
        exit $Process.ExitCode
    }

    Write-Log "Uruchomiono z uprawnieniami administratora."

    $NetExe = "$env:SystemRoot\System32\net.exe"

    & $NetExe accounts /minpwlen:8 /uniquepw:24 /minpwage:5

    if ($LASTEXITCODE -ne 0) {
        throw "Blad konfiguracji polityki hasel: $LASTEXITCODE"
    }

    Write-Log "Polityka hasel skonfigurowana."

    Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction Stop

    $Excluded = @("motoadmin2", "omega")
    $Success = 0
    $Skipped = 0
    $Failed = 0

    foreach ($User in Get-LocalUser) {

        if (!$User.Enabled) {
            Write-Log "POMINIETO: $($User.Name) - konto wylaczone."
            $Skipped++
            continue
        }

        if ($Excluded -contains $User.Name) {
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

            $AdsiUser = [ADSI]("WinNT://{0}/{1},user" -f $env:COMPUTERNAME, $User.Name)

            # Haslo wymagane
            $AdsiUser.Put("PasswordRequired", [bool]$true)

            # Usuniecie Password never expires
            $Flags = [int]$AdsiUser.Get("UserFlags")
            $Flags = $Flags -band (-bnot 0x10000)
            $AdsiUser.Put("UserFlags", $Flags)

            # Wymuszenie zmiany hasla
            $AdsiUser.Put("PasswordExpired", [int]1)

            $AdsiUser.SetInfo()

            # Ponowne odczytanie ustawien
            $Check = [ADSI]("WinNT://{0}/{1},user" -f $env:COMPUTERNAME, $User.Name)

            $Required = [bool]$Check.Get("PasswordRequired")
            $Expired = [int]$Check.Get("PasswordExpired")
            $CheckFlags = [int]$Check.Get("UserFlags")
            $NeverExpires = (($CheckFlags -band 0x10000) -ne 0)

            if (!$Required) {
                throw "PasswordRequired nie zostal ustawiony."
            }

            if ($Expired -eq 0) {
                throw "PasswordExpired nie zostal ustawiony."
            }

            if ($NeverExpires) {
                throw "Password never expires nadal jest aktywne."
            }

            Write-Log "OK: $($User.Name) - haslo wymagane, wygasanie wylaczone, zmiana przy nastepnym logowaniu."
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
