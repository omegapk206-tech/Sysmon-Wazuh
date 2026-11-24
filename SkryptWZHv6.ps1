# =====================================================
# POLITYKA HASEL WINDOWS 11
# Wszystkie konta lokalne poza:
# Motoadmin2, Omega i kontami systemowymi
# =====================================================

# Konta wyłączone z polityki
$ExcludedUsers = @(
    "Motoadmin2",
    "Omega"
)

# 1. Ustawienia lokalnej polityki haseł
Write-Host "Konfiguracja polityki haseł..." -ForegroundColor Cyan

# Minimalna długość hasła: 10 znaków
net accounts /minpwlen:10

# Maksymalny okres ważności: 365 dni
net accounts /maxpwage:365

# Minimalny okres między zmianami: 1 dzień
net accounts /minpwage:1

# Historia: zapamiętywanie 5 poprzednich haseł
net accounts /uniquepw:5

# 2. Włączenie wymogu złożoności haseł
secedit /export /cfg "$env:TEMP\password-policy.cfg" /quiet

$config = Get-Content "$env:TEMP\password-policy.cfg"

if ($config -match 'PasswordComplexity\s*=') {
    $config = $config -replace 'PasswordComplexity\s*=\s*\d+', 'PasswordComplexity = 1'
}
else {
    $config += "PasswordComplexity = 1"
}

Set-Content "$env:TEMP\password-policy.cfg" $config -Encoding Unicode

secedit /configure /db "$env:TEMP\password-policy.sdb" `
    /cfg "$env:TEMP\password-policy.cfg" /areas SECURITYPOLICY /quiet

# 3. Ustawienie wymuszania zmiany hasła
Write-Host "Konfiguracja kont użytkowników..." -ForegroundColor Cyan

$Users = Get-LocalUser | Where-Object {
    $_.Enabled -eq $true -and
    $_.Name -notin $ExcludedUsers -and
    $_.SID.Value -notmatch '-(500|501|503|504)$'
}

foreach ($Account in $Users) {

    try {
        # Hasło wygasa zgodnie z polityką 365 dni
        Set-LocalUser -Name $Account.Name `
            -PasswordNeverExpires $false

        # Użytkownik musi zmienić hasło przy następnym logowaniu
        Set-LocalUser -Name $Account.Name `
            -PasswordExpired $true

        Write-Host "Skonfigurowano: $($Account.Name)" -ForegroundColor Green
    }
    catch {
        Write-Host "Błąd: $($Account.Name) - $_" -ForegroundColor Red
    }
}

# 4. Wyświetlenie aktualnej polityki
Write-Host "`nAktualna polityka haseł:" -ForegroundColor Yellow
net accounts

Write-Host "`nZakończono konfigurację." -ForegroundColor Green
# Przypominanie 14 dni przed wygaśnięciem hasła
$RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

Set-ItemProperty `
    -Path $RegistryPath `
    -Name "PasswordExpiryWarning" `
    -Value 14 `
    -Type DWord

Write-Host "Ustawiono przypomnienie 14 dni przed wygaśnięciem hasła."
