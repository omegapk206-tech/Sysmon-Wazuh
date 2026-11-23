<#
.SYNOPSIS
    Wymusza zmianę hasła przy następnym logowaniu dla kont lokalnych.
.DESCRIPTION
    Skrypt pomija konta: motoadmin2, omega, wbudowany Administrator oraz konta wyłączone.
    Przed wymuszeniem zmiany wyłącza opcję "hasło nigdy nie wygasa" (PasswordNeverExpires),
    ponieważ przy jej włączonym stanie Windows ignoruje żądanie wymuszenia zmiany hasła.
    Wymaga uruchomienia z uprawnieniami administracyjnymi (ESET Local System).
    Lokalizacja pliku: C:\!APP\SkryptWZHv6.ps1
#>

# --- Konfiguracja ---
$WykluczoneKonta = @("motoadmin2", "omega", "Administrator")
$NazwaSkryptu     = "SkryptWZHv6"
$KatalogSkryptu   = "C:\!APP"

# Logowanie startowe
Write-Output "[$NazwaSkryptu] Rozpoczęcie działania..."

# Weryfikacja katalogu C:\!APP (informacyjnie)
if (-not (Test-Path -LiteralPath $KatalogSkryptu)) {
    Write-Warning "[$NazwaSkryptu] Katalog $KatalogSkryptu nie istnieje. Sprawdź dystrybucję pliku."
} else {
    Write-Output "[$NazwaSkryptu] Katalog roboczy: $KatalogSkryptu"
}

# Pobranie listy kont lokalnych
try {
    $KontaLokalne = Get-LocalUser -ErrorAction Stop
} catch {
    Write-Error "[$NazwaSkryptu] Błąd krytyczny: Nie można pobrać listy kont lokalnych. $_"
    exit 1
}

$ZmienioneKonta = 0
$PominieteKonta = 0

foreach ($Konto in $KontaLokalne) {
    $Nazwa = $Konto.Name

    # 1. Wykluczenia po nazwie
    if ($WykluczoneKonta -contains $Nazwa) {
        Write-Output "[$NazwaSkryptu] Pomijam (wykluczone): $Nazwa"
        $PominieteKonta++
        continue
    }

    # 2. Wbudowany Administrator (SID kończący się na -500) – zabezpieczenie na wypadek zmiany nazwy
    if ($Konto.SID.Value -like "*-500") {
        Write-Output "[$NazwaSkryptu] Pomijam (wbudowany Administrator): $Nazwa"
        $PominieteKonta++
        continue
    }

    # 3. Konto wyłączone
    if (-not $Konto.Enabled) {
        Write-Output "[$NazwaSkryptu] Pomijam (konto wyłączone): $Nazwa"
        $PominieteKonta++
        continue
    }

    # 4. KROK 1: Wyłącz "hasło nigdy nie wygasa" (warunek konieczny)
    #    Bez tego Windows ignoruje /logonpasswordchg:yes.
    $WylaczonoNeverExpires = $false
    try {
        Set-LocalUser -Name $Nazwa -PasswordNeverExpires $false -ErrorAction Stop
        Write-Output "[$NazwaSkryptu] Wyłączono 'hasło nigdy nie wygasa' dla: $Nazwa"
        $WylaczonoNeverExpires = $true
    } catch {
        # Fallback: wmic (starsze systemy / gdy Set-LocalUser zawiedzie)
        try {
            $wmicOut = wmic useraccount where "name='$Nazwa'" set PasswordExpires=True 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Output "[$NazwaSkryptu] Wyłączono 'hasło nigdy nie wygasa' (wmic) dla: $Nazwa"
                $WylaczonoNeverExpires = $true
            } else {
                Write-Warning "[$NazwaSkryptu] Nie udało się wyłączyć 'nigdy nie wygasa' dla $Nazwa. Wynik: $wmicOut"
            }
        } catch {
            Write-Warning "[$NazwaSkryptu] Błąd wyłączania 'nigdy nie wygasa' dla $Nazwa : $_"
        }
    }

    # 5. KROK 2: Wymuś zmianę hasła przy następnym logowaniu
    #    Puste hasło "" w net user pozwala obejść znany problem z flagą.
    try {
        $Wynik = net user $Nazwa "" /logonpasswordchg:yes 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Output "[$NazwaSkryptu] SUKCES: Wymuszono zmianę hasła dla: $Nazwa"
            $ZmienioneKonta++
        } else {
            Write-Warning "[$NazwaSkryptu] OSTRZEŻENIE: Nie udało się wymusić zmiany dla $Nazwa. Wynik: $Wynik"
        }
    } catch {
        Write-Error "[$NazwaSkryptu] BŁĄD podczas wymuszania zmiany dla $Nazwa : $_"
    }
}

# Podsumowanie
Write-Output "[$NazwaSkryptu] Zakończono. Zmieniono: $ZmienioneKonta, Pominięto: $PominieteKonta."
