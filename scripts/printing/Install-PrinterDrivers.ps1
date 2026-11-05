# Install-PrinterDrivers.ps1 - runs at computer startup as SYSTEM (GPO C_WS_PrinterDrivers)
# Pre-installs printer drivers: users cannot install drivers themselves (PrintNightmare hardening).
# Vendor-signed packages need the vendor cert in Trusted Publishers (same GPO, Public Key Policies).
$log = "$env:SystemRoot\Temp\Install-PrinterDrivers.log"
Start-Transcript -Path $log -Append | Out-Null

$drivers = @(
    @{ Name = 'Microsoft PCL6 Class Driver'; Inf = $null }                               # inbox v4 driver
    @{ Name = 'HP Universal Printing PCL 6'; Inf = '\\FS01\Drivers$\HPUPD\hpcu360u.inf' } # v3, same version as on FS01
)

foreach ($d in $drivers) {
    if (Get-PrinterDriver -Name $d.Name -ErrorAction SilentlyContinue) { "[ok]   $($d.Name)"; continue }
    try {
        if ($d.Inf) {
            $tmp = "$env:SystemRoot\Temp\PrinterDriver"
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item (Split-Path $d.Inf) $tmp -Recurse -Force -ErrorAction Stop
            pnputil.exe /add-driver (Join-Path $tmp (Split-Path $d.Inf -Leaf))
            $rc = $LASTEXITCODE
            Remove-Item $tmp -Recurse -Force
            if ($rc -ne 0) { throw "pnputil exit code $rc" }
        }
        Add-PrinterDriver -Name $d.Name -ErrorAction Stop
        "[new]  $($d.Name)"
    } catch {
        "[fail] $($d.Name): $_"
    }
}

Stop-Transcript | Out-Null
