# Krok 1: Wyłącz "hasło nigdy nie wygasa" dla tego konta
# Metoda A (preferowana, jeśli Get-LocalUser działa w Twoim środowisku):
Set-LocalUser -Name $Nazwa -PasswordNeverExpires $false -ErrorAction SilentlyContinue

# Metoda B (zapasowa, jeśli Set-LocalUser zawiedzie):
if ($LASTEXITCODE -ne 0) {
    wmic useraccount where "name='$Nazwa'" set PasswordExpires=True 2>&1 | Out-Null
}

# Krok 2: Wymuś zmianę hasła przy następnym logowaniu
# Uwaga: podanie pustego hasła "" pomaga obejść znany problem z flagą
$Wynik = net user $Nazwa "" /logonpasswordchg:yes 2>&1
