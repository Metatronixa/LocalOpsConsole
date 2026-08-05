param(
    [Parameter(Mandatory)]
    [string]$ComputerName,
    [ValidateSet("HKLM", "HKCU", "HKU", "HKCR")]
    [string]$Hive = "HKLM",
    [string]$Path = "SOFTWARE\Microsoft\Windows NT\CurrentVersion"
)

try {
    $hiveEnum = switch ($Hive) {
        "HKLM" { [Microsoft.Win32.RegistryHive]::LocalMachine }
        "HKCU" { [Microsoft.Win32.RegistryHive]::CurrentUser }
        "HKU"  { [Microsoft.Win32.RegistryHive]::Users }
        "HKCR" { [Microsoft.Win32.RegistryHive]::ClassesRoot }
    }

    $base = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey($hiveEnum, $ComputerName)
    $key = $base.OpenSubKey($Path)
    if (-not $key) {
        return New-ApiResult -Success $false -Message "Key not found: ${Hive}\$Path on $ComputerName"
    }

    $values = @()
    foreach ($name in $key.GetValueNames()) {
        $val = $key.GetValue($name)
        if ($val -is [Array]) { $val = ($val -join ", ") }
        $values += [PSCustomObject]@{
            Name  = if ([string]::IsNullOrEmpty($name)) { "(Default)" } else { $name }
            Type  = [string]$key.GetValueKind($name)
            Data  = [string]$val
        }
    }

    $subkeys = @($key.GetSubKeyNames() | Select-Object -First 100)

    $key.Close()
    $base.Close()

    return New-ApiResult -Success $true -Message "Remote registry ${Hive}\$Path" -Data ([PSCustomObject]@{
        ComputerName = $ComputerName
        Hive         = $Hive
        Path         = $Path
        Values       = @($values)
        SubKeys      = @($subkeys)
    })
}
catch {
    return New-ApiResult -Success $false -Message "Remote registry failed: $($_.Exception.Message). Ensure Remote Registry service is running on the target and firewalls allow RPC."
}
