# New-KuroganeUsers.ps1
# Bulk-create Kurogane Digital users from a CSV file.
# Run on a domain controller in PowerShell as a domain admin.
# Prerequisites: OUs Kurogane\Users\<Department>, groups GG_<Department>,
# alternative UPN suffix kurogane.test.

param(
    [string]$CsvPath = "C:\Scripts\users.csv"
)

Import-Module ActiveDirectory

$domainDN  = (Get-ADDomain).DistinguishedName      # DC=corp,DC=kurogane,DC=test
$upnSuffix = "kurogane-digital.ru"   # sign-in as login@kurogane-digital.ru, same as email
$password  = Read-Host "Initial password for all new users" -AsSecureString

Import-Csv -Path $CsvPath | ForEach-Object {

    $ou    = "OU=$($_.OU),OU=Users,OU=Kurogane,$domainDN"
    $group = "GG_$($_.OU)"
    $name  = "$($_.FirstName) $($_.LastName)"

    # Skip existing accounts so the script is safe to re-run
    if (Get-ADUser -Filter "SamAccountName -eq '$($_.Login)'") {
        Write-Warning "$($_.Login) already exists, skipping"
        return
    }

    New-ADUser `
        -Name                  $name `
        -DisplayName           $name `
        -GivenName             $_.FirstName `
        -Surname               $_.LastName `
        -SamAccountName        $_.Login `
        -UserPrincipalName     "$($_.Login)@$upnSuffix" `
        -Department            $_.Department `
        -Title                 $_.Title `
        -Company               "Kurogane Digital" `
        -Path                  $ou `
        -AccountPassword       $password `
        -ChangePasswordAtLogon $true `
        -Enabled               $true

    Add-ADGroupMember -Identity $group -Members $_.Login

    Write-Host "Created: $($_.Login) -> $($_.OU), group $group" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Check with:"
Write-Host "Get-ADUser -Filter * -SearchBase 'OU=Users,OU=Kurogane,$domainDN' | Measure-Object"
