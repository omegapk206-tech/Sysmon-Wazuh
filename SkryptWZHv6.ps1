$ErrorActionPreference = 'Stop'

$ExcludedUsers = @('motoadmin2')
$AdminGroup = Get-LocalGroup -SID 'S-1-5-32-544'

$AdminSids = @(
    Get-LocalGroupMember -Group $AdminGroup |
    ForEach-Object { $_.SID.Value }
)

$Users = Get-LocalUser | Where-Object {
    $_.Enabled -and
    $_.Name -notin $ExcludedUsers -and
    $_.SID.Value -notin $AdminSids
}

foreach ($User in $Users) {
    try {
        # Umożliw zmianę hasła i ustaw jego wygasanie
        Set-LocalUser -SID $User.SID `
            -PasswordNeverExpires $false `
            -UserMayChangePassword $true

        # Wymuś zmianę hasła przy następnym logowaniu
        $LocalAccount = [ADSI]"WinNT://$env:COMPUTERNAME/$($User.Name),user"
        $LocalAccount.PasswordExpired = 1
        $LocalAccount.SetInfo()

        Write-Host "OK: $($User.Name)" -ForegroundColor Green
    }
    catch {
        Write-Warning "BŁĄD: $($User.Name) — $($_.Exception.Message)"
    }
}
