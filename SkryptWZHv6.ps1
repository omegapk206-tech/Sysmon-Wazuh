
$ErrorActionPreference = "Stop"

$ExcludedUsers = @("Motoadmin2", "Omega")

net accounts /minpwlen:10
net accounts /maxpwage:365
net accounts /minpwage:1
net accounts /uniquepw:5

$PolicyFile = "$env:TEMP\password-policy.cfg"
$DatabaseFile = "$env:TEMP\password-policy.sdb"

secedit /export /cfg $PolicyFile /quiet

$config = Get-Content $PolicyFile

if ($config -match 'PasswordComplexity\s*=') {
    $config = $config -replace 'PasswordComplexity\s*=\s*\d+', 'PasswordComplexity = 1'
}
else {
    $config += "PasswordComplexity = 1"
}

Set-Content $PolicyFile $config -Encoding Unicode

secedit /configure /db $DatabaseFile /cfg $PolicyFile /areas SECURITYPOLICY /quiet

$Users = Get-LocalUser | Where-Object {
    $_.Enabled -eq $true -and
    $_.Name -notin $ExcludedUsers -and
    $_.SID.Value -notmatch '-(500|501|503|504)$'
}

foreach ($Account in $Users) {
    Set-LocalUser -Name $Account.Name -PasswordNeverExpires $false

    $UserObject = [ADSI]"WinNT://$env:COMPUTERNAME/$($Account.Name),user"
    $UserObject.PasswordExpired = 1
    $UserObject.SetInfo()
}

$RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

Set-ItemProperty -Path $RegistryPath -Name "PasswordExpiryWarning" -Value 14 -Type DWord
