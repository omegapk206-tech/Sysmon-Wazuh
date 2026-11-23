<#
.SYNOPSIS
    Wymusza zmianę hasła przy następnym logowaniu dla kont lokalnych.
.DESCRIPTION
    Skrypt pomija konta: motoadmin2, omega, wbudowany Administrator oraz konta wyłączone.
    Wymaga uruchomienia z uprawnieniami administracyjnymi (ESET Local System).
#>

# --- Konfiguracja ---
$WykluczoneKonta = @("motoadmin2", "omega", "Administrator")
$NazwaSkryptu = "SkryptWZHv6"

# Logowanie startowe
Write-Output "[$NazwaSkryptu] Rozpoczęcie działania..."

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
    
    # 1. Sprawdzenie wykluczeń (nazwa)
    if ($WykluczoneKonta -contains $Nazwa) {
        Write-Output "[$NazwaSkryptu] Pomijam (wykluczone): $Nazwa"
        $PominieteKonta++
        continue
    }

    # 2. Sprawdzenie czy konto jest wbudowane (SID kończący się na -500 to wbudowany Administrator)
    #    Chociaż wykluczyliśmy "Administrator" po nazwie, to zabezpieczenie na wypadek zmiany nazwy.
    if ($Konto.SID.Value -like "*-500") {
        Write-Output "[$NazwaSkryptu] Pomijam (wbudowany Administrator): $Nazwa"
        $PominieteKonta++
        continue
    }

    # 3. Sprawdzenie czy konto jest wyłączone
    if (-not $Konto.Enabled) {
        Write-Output "[$NazwaSkryptu] Pomijam (konto wyłączone): $Nazwa"
        $PominieteKonta++
        continue
    }

    # 4. Wymuszenie zmiany hasła przy następnym logowaniu
    # Używamy net user, ponieważ Set-LocalUser nie ma bezpośredniego parametru do wymuszenia zmiany,
    # a PasswordNeverExpires=$true (zgodnie z opisem) blokuje standardowe metody.
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
