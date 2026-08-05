<#
    Remove-DATStaleBIOSMarkers.ps1

    One-time remediation. Removes Driver Automation Tool BIOS version markers that are recorded
    AHEAD of the BIOS version actually installed on the device. A failed or rolled-back flash can
    leave the marker "tattooed" at the target version, which makes the detection rule report the
    update as installed and blocks any re-run. Clearing the stale marker lets the device
    re-evaluate as "update required" so Intune/ConfigMgr re-runs the BIOS upgrade.

    Silent, idempotent, run in SYSTEM context. PowerShell 5.1 compatible. Only a marker whose
    recorded version is strictly greater than the live firmware version (clean dotted versions)
    is removed; markers that match or are behind the firmware are left untouched.

    Log: C:\ProgramData\DriverAutomationTool\Logs\Remove-DATStaleBIOSMarkers.log

    DISCLAIMER: This script is provided "as is", without warranty of any kind, express or
    implied. The author accepts no liability for any damage or data loss arising from its use.
    Use at your own risk and validate in a test environment before deploying to production.
#>

# Relaunch in 64-bit PowerShell when running as a 32-bit process on a 64-bit OS. The BIOS markers
# live in the 64-bit registry view, so a 32-bit host (how Intune/ConfigMgr often invoke scripts)
# would be redirected to WOW6432Node and miss them. Sysnative bypasses the file-system redirector.
if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
    $ps64 = Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $ps64) {
        $proc = Start-Process -FilePath $ps64 -Wait -PassThru -WindowStyle Hidden `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        exit $proc.ExitCode
    }
}

$ErrorActionPreference = 'Stop'
$BiosRoot = 'HKLM:\SOFTWARE\DriverAutomationTool\BIOS'
$LogPath = "$env:ProgramData\DriverAutomationTool\Logs\Remove-DATStaleBIOSMarkers.log"

function Write-Log {
    param ([Parameter(Mandatory)][string]$Message)
    $line = "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) $Message"
    try {
        $dir = Split-Path -Parent $LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

try {
    Write-Log "==== Remove-DATStaleBIOSMarkers starting ===="

    if (-not (Test-Path -LiteralPath $BiosRoot)) {
        Write-Log "No BIOS marker root at $BiosRoot -- nothing to do."
        exit 0
    }

    # Live firmware version for this device.
    $liveVersion = $null
    try {
        $liveBios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        if ($liveBios -and $liveBios.SMBIOSBIOSVersion) { $liveVersion = ([string]$liveBios.SMBIOSBIOSVersion).Trim() }
    } catch { $liveVersion = $null }

    if ([string]::IsNullOrWhiteSpace($liveVersion)) {
        Write-Log "Live BIOS version could not be read -- leaving all markers untouched."
        exit 0
    }
    Write-Log "Live firmware BIOS version: $liveVersion"

    $liveParsed = $null
    $liveIsVersion = [System.Version]::TryParse($liveVersion, [ref]$liveParsed)

    $removed = 0
    foreach ($oemKey in (Get-ChildItem -LiteralPath $BiosRoot -ErrorAction SilentlyContinue)) {
        foreach ($modelKey in (Get-ChildItem -LiteralPath $oemKey.PSPath -ErrorAction SilentlyContinue)) {
            $oemName = Split-Path -Leaf $oemKey.PSPath
            $modelName = Split-Path -Leaf $modelKey.PSPath

            $props = Get-ItemProperty -LiteralPath $modelKey.PSPath -ErrorAction SilentlyContinue
            $markerVersion = if ($props -and $props.PSObject.Properties['Version']) { [string]$props.Version } else { $null }
            if ([string]::IsNullOrWhiteSpace($markerVersion)) { continue }

            # Remove only when both parse as versions and the marker is strictly ahead of firmware.
            $markerParsed = $null
            $markerIsVersion = [System.Version]::TryParse($markerVersion.Trim(), [ref]$markerParsed)
            if (-not ($liveIsVersion -and $markerIsVersion -and ($markerParsed -gt $liveParsed))) {
                Write-Log "[$oemName\$modelName] Marker $markerVersion not ahead of firmware $liveVersion -- left untouched."
                continue
            }

            try {
                foreach ($name in 'Version', 'PendingReboot', 'PendingRebootBootTime') {
                    Remove-ItemProperty -LiteralPath $modelKey.PSPath -Name $name -Force -ErrorAction SilentlyContinue
                }
                $removed++
                Write-Log "[$oemName\$modelName] Removed stale marker ($markerVersion ahead of firmware $liveVersion)."
            } catch {
                Write-Log "[$oemName\$modelName] Failed to remove marker: $($_.Exception.Message)"
            }
        }
    }

    Write-Log "Complete. Stale markers removed: $removed."
    Write-Log "==== Remove-DATStaleBIOSMarkers finished ===="
    exit 0
}
catch {
    Write-Log "Unexpected error: $($_.Exception.Message)"
    exit 1
}
