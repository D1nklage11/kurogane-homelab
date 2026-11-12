# Install-ZabbixAgent.ps1 - computer startup script (GPO C_SRV_Monitoring), runs as SYSTEM
# Installs Zabbix agent 2 (active + passive checks). Host metadata = server role,
# the Zabbix server uses it for auto-registration (creates the host, links templates).
$version = '8.0.0'
$msi     = "\\FS01\Software$\zabbix\zabbix_agent2-$version-windows-amd64-openssl.msi"
$server  = '192.168.100.40'
$svcName = 'Zabbix Agent 2'
Start-Transcript -Path "$env:SystemRoot\Temp\Install-ZabbixAgent.log" -Append | Out-Null
try {
    # 1. Role -> host metadata
    $f = Get-WindowsFeature | Where-Object Installed | Select-Object -ExpandProperty Name
    $role = if (Get-Service MSExchangeIS -ErrorAction SilentlyContinue) { 'exchange' }
            elseif ($f -contains 'AD-Domain-Services')  { 'dc' }
            elseif ($f -contains 'FS-Resource-Manager') { 'fs' }
            else                                        { 'server' }
    $meta = "windows-$role"

    # 2. What is installed now
    $inst = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
            Where-Object DisplayName -like 'Zabbix Agent 2*' | Select-Object -First 1
    $svc  = Get-CimInstance Win32_Service -Filter "Name='$svcName'"
    $cfg  = $null
    if ($svc -and $svc.PathName -match '(?:-c|--config)\s+"?([^"]+?\.conf)') { $cfg = $Matches[1] }
    $metaOk = $cfg -and (Test-Path $cfg) -and
              (Select-String -Path $cfg -Pattern "^HostMetadata=$meta\s*$" -Quiet)

    # 3. Install, reinstall (other version or other role) or nothing
    if (-not $inst -or $inst.DisplayVersion -notlike "$version*" -or -not $metaOk) {
        if ($inst) {
            Start-Process msiexec.exe -ArgumentList "/x $($inst.PSChildName) /qn /norestart" -Wait
        }
        $arguments = "/i `"$msi`" /qn /norestart /l*v `"$env:SystemRoot\Temp\zabbix_agent2-msi.log`"" +
                     " SERVER=$server SERVERACTIVE=$server HOSTNAME=$env:COMPUTERNAME" +
                     " HOSTMETADATA=$meta SKIP=fw"
        $p = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru
        if ($p.ExitCode -notin 0, 3010) { throw "msiexec exit code $($p.ExitCode)" }
        "[new]  Zabbix agent 2 $version, $env:COMPUTERNAME, metadata $meta"
    } else {
        if ((Get-Service $svcName).Status -ne 'Running') { Start-Service $svcName; "[start] service was stopped" }
        "[ok]   Zabbix agent 2 ${version}: $env:COMPUTERNAME, metadata $meta"
    }
} catch { "[fail] $_" }
Stop-Transcript | Out-Null
