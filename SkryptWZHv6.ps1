<#
.SYNOPSIS
    Wymusza zmianę hasła przy następnym logowaniu dla kont lokalnych.
.DESCRIPTION
    Skrypt pomija konta: motoadmin2, omega, wbudowany Administrator oraz konta wyłączone.
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

    # 4. Wymuszenie zmiany hasła przy następnym logowaniu
    try {
        $Wynik = net user $Nazwa /logonpasswordchg:yes 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Output "[$NazwaSkryptu] SUKCES: Wymuszono zmianę hasła dla: $Nazwa"
            $ZmienioneKonta++
        } else {
            Write-Warning "[$NazwaSkryptu] OSTRZEŻENIE: Nie udało się zmienić dla $Nazwa. Wynik: $Wynik"
        }
    } catch {
        Write-Error "[$NazwaSkryptu] BŁĄD podczas przetwarzania $Nazwa : $_"
    }
}

# Podsumowanie
Write-Output "[$NazwaSkryptu] Zakończono. Zmieniono: $ZmienioneKonta, Pominięto: $PominieteKonta."
