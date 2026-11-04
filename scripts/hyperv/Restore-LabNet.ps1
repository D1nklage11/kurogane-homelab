#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restores the Kurogane lab network on the Hyper-V host.

.DESCRIPTION
    Windows "Network reset" (and some driver/VPN reinstalls) delete Hyper-V
    virtual switches. This script brings the lab network back:
      1. Internal switch "LabNet"
      2. Host address 192.168.100.1/24 on "vEthernet (LabNet)" (lab gateway)
      3. NAT "LabNAT" for 192.168.100.0/24 (internet access for the VMs)
      4. Lab VMs' network adapters connected back to "LabNet"
    Safe to re-run: every step checks the current state first.

.EXAMPLE
    .\Restore-LabNet.ps1
    .\Restore-LabNet.ps1 -VMNames DC01,DC02,FS01,EX01
#>
param(
    [string]   $SwitchName = 'LabNet',
    [string]   $NatName    = 'LabNAT',
    [string]   $HostIP     = '192.168.100.1',
    [int]      $Prefix     = 24,
    [string]   $Subnet     = '192.168.100.0/24',
    [string[]] $VMNames    = @('DC01', 'DC02', 'FS01', 'EX01', 'WS-DEV01', 'WS-DESIGN01')
)

$ErrorActionPreference = 'Stop'
$alias = "vEthernet ($SwitchName)"

# 1. Switch
if (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue) {
    Write-Host "[ok]   Switch '$SwitchName' exists"
} else {
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
    Write-Host "[new]  Switch '$SwitchName' created (Internal)" -ForegroundColor Green
}

# 2. Host IP (lab gateway)
$ip = Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object IPAddress -eq $HostIP
if ($ip) {
    Write-Host "[ok]   $HostIP/$Prefix is set on '$alias'"
} else {
    New-NetIPAddress -InterfaceAlias $alias -IPAddress $HostIP -PrefixLength $Prefix | Out-Null
    Write-Host "[new]  $HostIP/$Prefix set on '$alias'" -ForegroundColor Green
}

# 3. NAT: recreate if missing or pointing to another prefix
$nat = Get-NetNat -ErrorAction SilentlyContinue | Where-Object InternalIPInterfaceAddressPrefix -eq $Subnet
if ($nat -and $nat.Name -eq $NatName) {
    Write-Host "[ok]   NAT '$NatName' for $Subnet exists"
} else {
    if ($nat) { $nat | Remove-NetNat -Confirm:$false }
    New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $Subnet | Out-Null
    Write-Host "[new]  NAT '$NatName' for $Subnet created" -ForegroundColor Green
}

# 4. Reconnect lab VMs
foreach ($vm in $VMNames) {
    if (-not (Get-VM -Name $vm -ErrorAction SilentlyContinue)) {
        Write-Host "[skip] VM '$vm' not found" -ForegroundColor Yellow
        continue
    }
    foreach ($nic in Get-VMNetworkAdapter -VMName $vm) {
        if ($nic.SwitchName -eq $SwitchName) {
            Write-Host "[ok]   $vm ($($nic.Name)) is on '$SwitchName'"
        } else {
            $nic | Connect-VMNetworkAdapter -SwitchName $SwitchName
            Write-Host "[new]  $vm ($($nic.Name)) connected to '$SwitchName'" -ForegroundColor Green
        }
    }
}

# Summary
Write-Host ''
Get-VM | Get-VMNetworkAdapter | Format-Table VMName, SwitchName, Status -AutoSize
Write-Host "Check: ping 192.168.100.10, then from a VM: Test-NetConnection 1.1.1.1 -Port 443"
