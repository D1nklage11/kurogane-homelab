# Install-WindowsExporter.ps1 - computer startup script (GPO C_SRV_Monitoring), runs as SYSTEM
# Installs or updates windows_exporter and enables collectors by the server's roles.
$version = '0.31.8'
$msi     = "\\FS01\Software$\windows_exporter\windows_exporter-$version-amd64.msi"
$cfgDir  = "$env:ProgramData\windows_exporter"
$cfg     = Join-Path $cfgDir 'config.yaml'
Start-Transcript -Path "$env:SystemRoot\Temp\Install-WindowsExporter.log" -Append | Out-Null
try {
    # 1. Collectors by installed roles
    $c = [System.Collections.Generic.List[string]]@('[defaults]')
    $f = Get-WindowsFeature | Where-Object Installed | Select-Object -ExpandProperty Name
    if ($f -contains 'AD-Domain-Services')  { $c.Add('ad'); $c.Add('time') }
    if ($f -contains 'DNS')                 { $c.Add('dns') }
    if ($f -contains 'DHCP')                { $c.Add('dhcp') }
    if ($f -contains 'FS-Resource-Manager') { $c.Add('fsrmquota') }
    if ($f -contains 'ADCS-Cert-Authority') { $c.Add('adcs') }
    if ($f -contains 'Print-Server')        { $c.Add('printer') }
    if (Get-Service MSExchangeIS -ErrorAction SilentlyContinue) { $c.Add('exchange') }
    $wanted = "collectors:`n  enabled: `"$($c -join ',')`"`nlog:`n  level: warn`n"

    # 2. Config file: the exporter reads it at service start
    New-Item $cfgDir -ItemType Directory -Force | Out-Null
    $changed = -not (Test-Path $cfg) -or ((Get-Content $cfg -Raw) -ne $wanted)
    if ($changed) { [IO.File]::WriteAllText($cfg, $wanted); "[cfg]  $($c -join ',')" }

    # 3. Install / upgrade; reinstall if the service does not use our config file
    $inst = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
            Where-Object DisplayName -like 'windows_exporter*' | Select-Object -First 1
    $svc  = Get-CimInstance Win32_Service -Filter "Name='windows_exporter'"
    $usesCfg = $svc -and $svc.PathName -like "*$cfg*"
    if (-not $inst -or $inst.DisplayVersion -notlike "$version*" -or -not $usesCfg) {
        if ($inst -and -not $usesCfg) {
            Start-Process msiexec.exe -ArgumentList "/x $($inst.PSChildName) /qn /norestart" -Wait
        }
        $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList `
            "/i `"$msi`" /qn /norestart CONFIG_FILE=`"$cfg`" /L*v `"$env:SystemRoot\Temp\windows_exporter-msi.log`""
        if ($p.ExitCode -notin 0, 3010) { throw "msiexec exit code $($p.ExitCode)" }
        "[new]  windows_exporter $version"
    } elseif ($changed) {
        Restart-Service windows_exporter
        "[restart] collectors changed"
    } else {
        "[ok]   windows_exporter ${version}: $($c -join ',')"
    }
} catch { "[fail] $_" }
Stop-Transcript | Out-Null
