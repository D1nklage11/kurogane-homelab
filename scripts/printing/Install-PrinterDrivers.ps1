# Install-PrinterDrivers.ps1 - runs at computer startup as SYSTEM (GPO C_WS_PrinterDrivers)
# Pre-installs printer drivers so users can connect to shared printers
# while driver installation is restricted to administrators (PrintNightmare hardening).
$drivers = @('Microsoft PCL6 Class Driver')
foreach ($d in $drivers) {
    if (-not (Get-PrinterDriver -Name $d -ErrorAction SilentlyContinue)) { Add-PrinterDriver -Name $d }
}
