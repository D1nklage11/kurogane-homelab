# New-KuroganeShareGroups.ps1
# Creates Domain Local access groups for FS01 shared folders (AGDLP model)
# and nests role groups (GG_*) into them.
# Run on a domain controller in PowerShell as a domain admin.

Import-Module ActiveDirectory
$ErrorActionPreference = "Stop"

$domain      = Get-ADDomain
$ouPath      = "OU=Resources,OU=Groups,OU=Kurogane,$($domain.DistinguishedName)"
# "Domain Users" is looked up by its well-known RID 513, so the script
# works regardless of the OS language
$domainUsers = (Get-ADGroup -Identity "$($domain.DomainSID.Value)-513").SamAccountName

# Folder -> who gets Read/Write and who gets Read-only
$matrix = [ordered]@{
    "Assets"     = @{ RW = @("GG_Art");        RO = @("GG_Dev", "GG_Design") }
    "Builds"     = @{ RW = @("GG_Dev");        RO = @("GG_QA", "GG_Design", "GG_Management") }
    "GameDesign" = @{ RW = @("GG_Design");     RO = @("GG_Dev", "GG_Art", "GG_QA", "GG_Management") }
    "QA-Reports" = @{ RW = @("GG_QA");         RO = @("GG_Dev", "GG_Design", "GG_Management") }
    "Management" = @{ RW = @("GG_Management"); RO = @() }
    "Finance"    = @{ RW = @("GG_Finance");    RO = @("GG_Management") }
    "IT"         = @{ RW = @("GG_IT");         RO = @() }
    "Public"     = @{ RW = @($domainUsers);    RO = @() }
}

foreach ($folder in $matrix.Keys) {
    foreach ($access in "RW", "RO") {

        $members = $matrix[$folder][$access]
        if ($members.Count -eq 0) { continue }

        $groupName = "DL_FS_${folder}_${access}"
        $desc      = if ($access -eq "RW") { "Read/write" } else { "Read-only" }

        try {
            if (-not (Get-ADGroup -Filter "Name -eq '$groupName'")) {
                New-ADGroup -Name $groupName `
                            -GroupScope DomainLocal `
                            -GroupCategory Security `
                            -Path $ouPath `
                            -Description "$desc access to \\FS01\Shares\$folder"
                Write-Host "Created group: $groupName" -ForegroundColor Green
            }
            else {
                Write-Host "Group exists: $groupName" -ForegroundColor Yellow
            }

            Add-ADGroupMember -Identity $groupName -Members $members
            Write-Host "  members: $($members -join ', ')"
        }
        catch {
            Write-Host "ERROR on $groupName : $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "Check with:"
Write-Host "Get-ADGroup -Filter `"Name -like 'DL_FS_*'`" | Sort-Object Name | ForEach-Object { '{0}: {1}' -f `$_.Name, ((Get-ADGroupMember `$_).Name -join ', ') }"
