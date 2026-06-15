<#
.SYNOPSIS
    Determines whether the client device is currently inside a configured Driver
    Automation Tool maintenance window.

.DESCRIPTION
    Evaluates the maintenance-window schedule against the device's LOCAL time using the
    same logic the Driver Automation Tool embeds in its Intune requirement rules:

      - Daily windows  : entries with no 'Day' property apply every day.
      - Weekly windows : entries with a 'Day' property apply only on that weekday.
      - Overnight windows that cross midnight (e.g. 22:00 to 05:00) are supported --
        the device is "inside" the window if the current time is at/after Start OR
        at/before End.

    The schedule can be supplied three ways (checked in this order):
      1. -MaintenanceWindowsJson  : a JSON array string passed directly.
      2. -ConfigPath              : a JSON file containing either the array, or an object
                                    with MaintenanceWindowEnabled / MaintenanceWindows.
      3. Registry (default)       : HKLM:\SOFTWARE\DriverAutomationTool
                                    (MaintenanceWindowEnabled + MaintenanceWindows).

    When the feature is disabled or no windows are configured, the device is treated as
    ALWAYS inside the window (i.e. installs are not blocked) -- matching the tool's
    behaviour where packages built without a maintenance window install normally.

.PARAMETER MaintenanceWindowsJson
    JSON array of window objects, e.g.
      '[{"Start":"17:00","End":"09:00"}]'                       (Daily)
      '[{"Day":"Saturday","Start":"22:00","End":"05:00"}]'      (Weekly)

.PARAMETER ConfigPath
    Path to a JSON config/export file containing the schedule.

.PARAMETER RegistryPath
    Override the registry key the schedule is read from.
    Default: HKLM:\SOFTWARE\DriverAutomationTool

.PARAMETER Quiet
    Suppress the human-readable status line; only the exit code is returned.

.OUTPUTS
    Writes a status line to the output stream and sets the exit code:
      0  = inside the maintenance window (or no window configured -> always applicable)
      1  = outside the maintenance window

.EXAMPLE
    .\Test-DATMaintenanceWindow.ps1
    Reads the schedule from the registry and reports the current status.

.EXAMPLE
    .\Test-DATMaintenanceWindow.ps1 -MaintenanceWindowsJson '[{"Start":"17:00","End":"09:00"}]'
    Evaluates an explicit daily 17:00 -> 09:00 overnight window.

.EXAMPLE
    if ((.\Test-DATMaintenanceWindow.ps1 -Quiet; $LASTEXITCODE) -eq 0) { Install-Update }
    Use the exit code to gate an action.
#>
[CmdletBinding()]
param (
    [string]$MaintenanceWindowsJson = '',
    [string]$ConfigPath = '',
    [string]$RegistryPath = 'HKLM:\SOFTWARE\DriverAutomationTool',
    [switch]$Quiet
)

function Write-Status {
    param ([string]$Message)
    if (-not $Quiet) { Write-Output $Message }
}

# --- 1. Resolve the schedule JSON from the chosen source ---------------------------------
$json = ''
$mwEnabled = $true

if (-not [string]::IsNullOrWhiteSpace($MaintenanceWindowsJson)) {
    $json = $MaintenanceWindowsJson
}
elseif (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Write-Status "Config file not found: $ConfigPath"
        exit 1
    }
    try {
        $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        Write-Status "Failed to parse config file: $($_.Exception.Message)"
        exit 1
    }
    if ($cfg -is [System.Array]) {
        # File is the windows array itself
        $json = ($cfg | ConvertTo-Json -Compress)
    } else {
        if ($cfg.PSObject.Properties['MaintenanceWindowEnabled']) {
            $mwEnabled = [bool]$cfg.MaintenanceWindowEnabled
        }
        if ($cfg.PSObject.Properties['MaintenanceWindows'] -and $cfg.MaintenanceWindows) {
            $json = (@($cfg.MaintenanceWindows) | ConvertTo-Json -Compress)
        }
    }
}
else {
    # Registry (default)
    $enabledVal = (Get-ItemProperty -Path $RegistryPath -Name 'MaintenanceWindowEnabled' -ErrorAction SilentlyContinue).MaintenanceWindowEnabled
    if ($null -ne $enabledVal) { $mwEnabled = ($enabledVal -eq 1) }
    $json = (Get-ItemProperty -Path $RegistryPath -Name 'MaintenanceWindows' -ErrorAction SilentlyContinue).MaintenanceWindows
}

# --- 2. Disabled / no schedule => always applicable (do not block) -----------------------
if (-not $mwEnabled) {
    Write-Status "Maintenance window disabled -- treated as always inside the window."
    exit 0
}
if ([string]::IsNullOrWhiteSpace($json)) {
    Write-Status "No maintenance window configured -- treated as always inside the window."
    exit 0
}

try {
    $windows = @($json | ConvertFrom-Json)
} catch {
    Write-Status "Could not parse maintenance window schedule -- treated as always inside the window."
    exit 0
}
if ($windows.Count -eq 0) {
    Write-Status "No maintenance window configured -- treated as always inside the window."
    exit 0
}

# --- 3. Evaluate against the device's local time -----------------------------------------
$nowDay = (Get-Date).DayOfWeek.ToString()
$now    = (Get-Date).TimeOfDay

# Daily entries (no Day) apply every day; Weekly entries apply only on their weekday.
$applicable = $windows | Where-Object {
    (-not $_.PSObject.Properties['Day']) -or [string]::IsNullOrEmpty($_.Day) -or ($_.Day -eq $nowDay)
}

$inWindow = $false
$matchedWindow = $null
foreach ($w in $applicable) {
    $s = "$($w.Start)".Split(':')
    $e = "$($w.End)".Split(':')
    if ($s.Count -ne 2 -or $e.Count -ne 2) { continue }
    try {
        $start = [timespan]::new([int]$s[0], [int]$s[1], 0)
        $end   = [timespan]::new([int]$e[0], [int]$e[1], 0)
    } catch { continue }

    if ($start -le $end) {
        # Same-day window
        if ($now -ge $start -and $now -le $end) { $inWindow = $true; $matchedWindow = $w; break }
    } else {
        # Window spans midnight (e.g. 22:00 -> 05:00)
        if ($now -ge $start -or $now -le $end) { $inWindow = $true; $matchedWindow = $w; break }
    }
}

# --- 4. Report ---------------------------------------------------------------------------
$nowStr = $now.ToString('hh\:mm')
if ($inWindow) {
    Write-Status "INSIDE maintenance window (day=$nowDay, time=$nowStr, window=$($matchedWindow.Start)-$($matchedWindow.End))."
    exit 0
} else {
    Write-Status "OUTSIDE maintenance window (day=$nowDay, time=$nowStr)."
    exit 1
}
