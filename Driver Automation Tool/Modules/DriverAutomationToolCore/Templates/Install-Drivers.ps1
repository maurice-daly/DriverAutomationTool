<#
    Driver Automation Tool - Driver Install Script
    Author: Maurice Daly
    Organization: MSEndpointMgr
    Copyright: (c) Maurice Daly. All rights reserved.
    OEM: {{OEM}}
    Model: {{Model}}
    OS: {{OS}}
    Version: {{Version}}
    Generated: {{Generated}}
#>
param (
    [switch]$WhatIf,
    # Run as the Intune / ConfigMgr uninstall command: rolls the drivers back to the ones this
    # version replaced, using the rollback data recorded at install time.
    [switch]$Uninstall
)

# --- 64-bit Relaunch Guard ---
# The Intune Management Extension may launch PowerShell as a 32-bit process.
# Registry writes from WOW64 land in HKLM\SOFTWARE\WOW6432Node and PNPUtil may
# not work correctly. Relaunch under native 64-bit PowerShell if needed.
if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
    Write-Warning "32-bit PowerShell detected -- relaunching under 64-bit PowerShell..."

    $earlyLog = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\DriverAutomationTool-Drivers.log'

    # Guard: script must have been invoked with -File so the path is resolvable
    $scriptPath = $MyInvocation.MyCommand.Path
    if ([string]::IsNullOrEmpty($scriptPath)) {
        Write-Warning "ERROR: Cannot determine script path -- MyInvocation.MyCommand.Path is empty. Use 'powershell.exe -File <script>' rather than dot-sourcing or &."
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [ERROR] 64-bit relaunch failed: script path is empty (run with -File parameter)" | Out-File -FilePath $earlyLog -Encoding UTF8 -Append
        exit 1
    }

    # IMPORTANT: Do NOT fall back to System32 -- from a 32-bit process, System32 is
    # WOW64-redirected to SysWOW64, which would just relaunch another 32-bit session.
    # SysNative is the WOW64 alias that resolves to the real (64-bit) System32.
    $relaunchPath = "$env:SystemRoot\SysNative\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $relaunchPath)) {
        Write-Warning "ERROR: 64-bit PowerShell not found at '$relaunchPath' -- cannot relaunch."
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [ERROR] 64-bit relaunch failed: SysNative path not accessible" | Out-File -FilePath $earlyLog -Encoding UTF8 -Append
        exit 1
    }

    $relaunchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$scriptPath`"")
    if ($WhatIf) { $relaunchArgs += '-WhatIf' }
    if ($Uninstall) { $relaunchArgs += '-Uninstall' }
    Write-Host "INFO: Launching 64-bit process: $relaunchPath $($relaunchArgs -join ' ')" -ForegroundColor Cyan
    try {
        $proc = Start-Process -FilePath $relaunchPath -ArgumentList $relaunchArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
        Write-Host "INFO: 64-bit process exited with code $($proc.ExitCode)" -ForegroundColor Cyan
        exit $proc.ExitCode
    } catch {
        Write-Warning "ERROR: 64-bit relaunch failed: $($_.Exception.Message)"
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [ERROR] 64-bit relaunch failed: $($_.Exception.Message)" | Out-File -FilePath $earlyLog -Encoding UTF8 -Append
        exit 1
    }
}

$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\DriverAutomationTool-Drivers.log"

function Write-CMTraceLog {
    param (
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('1','2','3')][string]$Severity = '1',
        [string]$Component = 'DriverAutomationTool-Drivers'
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $Time = Get-Date -Format "HH:mm:ss.fff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    $LogEntry = "<![LOG[$Message]LOG]!><time=""$Time+000"" date=""$Date"" component=""$Component"" context="""" type=""$Severity"" thread=""$PID"" file="""">"
    $LogDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8 -ErrorAction SilentlyContinue

    # Console output with severity-appropriate formatting
    switch ($Severity) {
        '1' { Write-Host "[$Timestamp] [INFO] $Message" }
        '2' { Write-Host "[$Timestamp] [WARN] $Message" -ForegroundColor Yellow }
        '3' { Write-Host "[$Timestamp] [ERROR] $Message" -ForegroundColor Red }
    }
}

function Set-DATInstallStatus {
    <#
        Records a machine-readable status record alongside the version marker so custom
        reporting (registry scraping) can see the outcome of the LAST run -- including
        failures, which otherwise leave no registry trace at all. Written on every real
        (non-WhatIf) exit path, success or failure. Exit codes are stored as strings so
        negative / large tool codes (e.g. -1, HRESULTs) survive intact.
    #>
    param (
        [Parameter(Mandatory)][string]$RegPath,
        [Parameter(Mandatory)][ValidateSet('Success','PendingReboot','AlreadyCurrent','NoContent','RetryScheduled','Failed','RolledBack')][string]$Result,
        [int]$ToolExitCode = 0,
        [int]$ScriptExitCode = 0,
        [string]$Phase = '',
        [string]$ErrorMessage = ''
    )
    try {
        if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
        $nowUtc = (Get-Date).ToUniversalTime().ToString('o')
        Set-ItemProperty -Path $RegPath -Name 'LastResult'         -Value $Result                   -Force
        Set-ItemProperty -Path $RegPath -Name 'LastRunUtc'         -Value $nowUtc                   -Force
        Set-ItemProperty -Path $RegPath -Name 'LastToolExitCode'   -Value ([string]$ToolExitCode)   -Force
        Set-ItemProperty -Path $RegPath -Name 'LastScriptExitCode' -Value ([string]$ScriptExitCode) -Force
        Set-ItemProperty -Path $RegPath -Name 'LastErrorPhase'     -Value $Phase                    -Force
        Set-ItemProperty -Path $RegPath -Name 'LastError'          -Value $ErrorMessage             -Force
        # Whether this run installed silently during Autopilot provisioning (Test-DATAutopilotProvisioning)
        $installContext = if ($script:DATAutopilot -and $script:DATAutopilot.InProvisioning) { "AutopilotProvisioning:$($script:DATAutopilot.Phase)" } else { 'Standard' }
        Set-ItemProperty -Path $RegPath -Name 'LastInstallContext' -Value $installContext           -Force

        # Running attempt counter -- lets reporting spot devices stuck retrying/failing
        $priorAttempts = 0
        try { $priorAttempts = [int](Get-ItemProperty -Path $RegPath -Name 'AttemptCount' -ErrorAction SilentlyContinue).AttemptCount } catch { $priorAttempts = 0 }
        Set-ItemProperty -Path $RegPath -Name 'AttemptCount' -Value ($priorAttempts + 1) -Type DWord -Force

        if ($Result -in @('Success','PendingReboot','AlreadyCurrent')) {
            Set-ItemProperty -Path $RegPath -Name 'LastSuccessUtc' -Value $nowUtc -Force
            # Successful (or no-op) run -- clear any prior deferral/failure reason so custom
            # reporting reflects the current healthy state rather than a stale cause.
            Remove-ItemProperty -Path $RegPath -Name 'Reason' -Force -ErrorAction SilentlyContinue

            # Clear the toast deferral/snooze counters now the update has been applied, prestaged
            # or confirmed current. Only the "max deferrals reached" path cleared these before, so
            # after a normal "Update Now" / auto-install / already-current completion the old
            # DeferralCount lingered -- polluting custom reporting AND bleeding into the next driver
            # update's deferral budget. The counter is scoped per update type (Toast\Drivers); the
            # legacy shared 'Toast' values are also cleared so devices upgraded from the
            # pre-scoping build don't leave stale data behind at the old path.
            foreach ($toastStateKey in @('HKLM:\SOFTWARE\DriverAutomationTool\Toast\Drivers', 'HKLM:\SOFTWARE\DriverAutomationTool\Toast')) {
                if (-not (Test-Path $toastStateKey)) { continue }
                $hadDeferralState = ($null -ne (Get-ItemProperty -Path $toastStateKey -Name 'DeferralCount' -ErrorAction SilentlyContinue).DeferralCount) -or `
                                    ($null -ne (Get-ItemProperty -Path $toastStateKey -Name 'SnoozeUntil'   -ErrorAction SilentlyContinue).SnoozeUntil)
                Remove-ItemProperty -Path $toastStateKey -Name 'DeferralCount' -Force -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $toastStateKey -Name 'SnoozeUntil'   -Force -ErrorAction SilentlyContinue
                if ($hadDeferralState) {
                    Write-CMTraceLog "Cleared toast deferral state (DeferralCount/SnoozeUntil) under '$toastStateKey' after '$Result' -- reset for the next update cycle"
                }
            }
        } else {
            # Deferral (RetryScheduled) or failure (Failed/NoContent) -- surface a single
            # human-readable reason for reporting. Prefer the supplied message, falling back
            # to the phase, then the raw result label.
            $reasonText = if (-not [string]::IsNullOrEmpty($ErrorMessage)) {
                $ErrorMessage
            } elseif (-not [string]::IsNullOrEmpty($Phase)) {
                "$Result ($Phase)"
            } else {
                $Result
            }
            Set-ItemProperty -Path $RegPath -Name 'Reason' -Value $reasonText -Force
        }
    } catch {
        Write-CMTraceLog "WARNING: Failed to write install status to registry -- $($_.Exception.Message)" -Severity 2
    }
}

function Get-DATInfDriverInfo {
    # Parse an INF's [Version] section for the driver metadata the reporting service needs.
    # DriverVersion is the join key -- it matches Win32_PnPSignedDriver.DriverVersion exactly.
    param ([Parameter(Mandatory)][string]$InfPath)
    try {
        $text = Get-Content -LiteralPath $InfPath -Raw -ErrorAction Stop
    } catch {
        return $null
    }
    $dv    = [regex]::Match($text, '(?im)^\s*DriverVer\s*=\s*([\d/]+)\s*,\s*([\d\.]+)')
    $prov  = [regex]::Match($text, '(?im)^\s*Provider\s*=\s*(.+)$')
    $cls   = [regex]::Match($text, '(?im)^\s*Class\s*=\s*(.+)$')
    $cguid = [regex]::Match($text, '(?im)^\s*ClassGuid\s*=\s*(.+)$')
    $cat   = [regex]::Match($text, '(?im)^\s*CatalogFile\s*(?:\.[^=\s]+)?\s*=\s*(.+)$')
    $hwids = [regex]::Matches($text, '(?im)(PCI|USB|ACPI|HID|SWC|HDAUDIO)\\[^\s,;"]+') |
             ForEach-Object { $_.Value } | Sort-Object -Unique

    # Normalise the DriverVer date part (MM/DD/YYYY, culture-invariant) to yyyy-MM-dd
    $driverDate = ''
    if ($dv.Success) {
        try {
            $driverDate = [datetime]::ParseExact($dv.Groups[1].Value.Trim(), 'MM/dd/yyyy',
                [System.Globalization.CultureInfo]::InvariantCulture).ToString('yyyy-MM-dd')
        } catch {
            try { $driverDate = ([datetime]$dv.Groups[1].Value).ToString('yyyy-MM-dd') } catch { $driverDate = '' }
        }
    }

    # Provider is often a %Token% referencing the [Strings] section -- resolve it when possible
    $provider = if ($prov.Success) { ($prov.Groups[1].Value -replace ';.*$', '').Trim() } else { '' }
    if ($provider -match '^%(.+)%$') {
        $tok = $Matches[1]
        $strMatch = [regex]::Match($text, "(?im)^\s*$([regex]::Escape($tok))\s*=\s*`"?([^`"\r\n;]+)")
        if ($strMatch.Success) { $provider = $strMatch.Groups[1].Value.Trim() }
    }

    [pscustomobject]@{
        Inf           = [System.IO.Path]::GetFileName($InfPath)
        DriverVersion = if ($dv.Success) { $dv.Groups[2].Value.Trim() } else { '' }
        DriverDate    = $driverDate
        Provider      = $provider
        Class         = if ($cls.Success)   { ($cls.Groups[1].Value   -replace ';.*$', '').Trim() } else { '' }
        ClassGuid     = if ($cguid.Success) { ($cguid.Groups[1].Value -replace ';.*$', '').Trim() } else { '' }
        CatalogFile   = if ($cat.Success)   { ($cat.Groups[1].Value   -replace ';.*$', '').Trim() } else { '' }
        HardwareIds   = @($hwids)
    }
}

function Write-DATDriversAddedReport {
    # Emits an INF-level catalog of the drivers this package added, for the Driver & BIOS
    # Patch Management reporting service. Written to ProgramData\DriverAutomationTool\Reports
    # as DriversAdded.json, rolling the previous copies to .1.json .. .5.json (keep 5).
    param (
        [Parameter(Mandatory)][string]$ExtractPath,
        [string]$OEM,
        [string]$Model,
        [string]$OS,
        [string]$PackageVersion,
        [string]$PackageReleaseDate
    )
    try {
        $reportDir = Join-Path $env:ProgramData 'DriverAutomationTool\Reports'
        if (-not (Test-Path $reportDir)) { New-Item -Path $reportDir -ItemType Directory -Force | Out-Null }
        $reportBase = Join-Path $reportDir 'DriversAdded'
        $reportFile = "$reportBase.json"

        # Device architecture equals the package target at install time
        $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
            'AMD64' { 'x64' }
            'ARM64' { 'arm64' }
            'x86'   { 'x86' }
            default { $env:PROCESSOR_ARCHITECTURE }
        }

        # Device SystemSKU / baseboard -- lets the service match by SKU rather than model name
        $deviceSku = ''
        try {
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($cs.SystemSKUNumber)) {
                $deviceSku = $cs.SystemSKUNumber.Trim()
            } else {
                $bb = (Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue).Product
                if (-not [string]::IsNullOrWhiteSpace($bb)) { $deviceSku = $bb.Trim() }
            }
        } catch { }

        # Package release date arrives as an 8-digit yyyyMMdd stamp (or empty) -- normalise
        $releaseDate = ''
        if ($PackageReleaseDate -match '^\d{8}$') {
            $releaseDate = '{0}-{1}-{2}' -f $PackageReleaseDate.Substring(0, 4),
                $PackageReleaseDate.Substring(4, 2), $PackageReleaseDate.Substring(6, 2)
        }

        $infFiles = Get-ChildItem -Path $ExtractPath -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue
        $records = New-Object System.Collections.Generic.List[object]
        foreach ($inf in $infFiles) {
            $info = Get-DATInfDriverInfo -InfPath $inf.FullName
            if ($null -eq $info -or [string]::IsNullOrEmpty($info.DriverVersion)) { continue }
            $relPath = $inf.FullName.Substring($ExtractPath.Length).TrimStart('\', '/') -replace '\\', '/'
            $records.Add([pscustomobject]@{
                OEM                = $OEM
                Model              = $Model
                OS                 = $OS
                Architecture       = $arch
                PackageVersion     = $PackageVersion
                PackageReleaseDate = $releaseDate
                PackageFileName    = 'DriverPackage.wim'
                SystemSku          = $deviceSku
                ComputerName       = $env:COMPUTERNAME
                InstalledUtc       = (Get-Date).ToUniversalTime().ToString('o')
                Inf                = $info.Inf
                InfPath            = $relPath
                DriverVersion      = $info.DriverVersion
                DriverDate         = $info.DriverDate
                Provider           = $info.Provider
                Class              = $info.Class
                ClassGuid          = $info.ClassGuid
                CatalogFile        = $info.CatalogFile
                HardwareIds        = $info.HardwareIds
            })
        }

        if ($records.Count -eq 0) {
            Write-CMTraceLog "DriversAdded report: no parseable INFs found -- report not written" -Severity 2
            return
        }

        # Roll the existing reports over, keeping the previous 5 (DriversAdded.1.json .. .5.json)
        if (Test-Path $reportFile) {
            $oldest = "$reportBase.5.json"
            if (Test-Path $oldest) { Remove-Item -Path $oldest -Force -ErrorAction SilentlyContinue }
            for ($i = 4; $i -ge 1; $i--) {
                $src = "$reportBase.$i.json"
                if (Test-Path $src) { Move-Item -Path $src -Destination "$reportBase.$($i + 1).json" -Force -ErrorAction SilentlyContinue }
            }
            Move-Item -Path $reportFile -Destination "$reportBase.1.json" -Force -ErrorAction SilentlyContinue
        }

        # ConvertTo-Json collapses a single-element array to an object in PS 5.1 -- force an array
        $json = $records.ToArray() | ConvertTo-Json -Depth 6
        if ($records.Count -eq 1) { $json = "[$json]" }
        Set-Content -Path $reportFile -Value $json -Encoding UTF8 -Force
        Write-CMTraceLog "DriversAdded report written: $reportFile ($($records.Count) INF record(s))"
    } catch {
        Write-CMTraceLog "WARNING: Failed to write DriversAdded report -- $($_.Exception.Message)" -Severity 2
    }
}
# --- Rollback manifest -------------------------------------------------------------------------
# PNPUtil /add-driver leaves the packages it displaces in the driver store, so a later rollback can
# delete what this install added and let each device fall back to the driver it had before. That
# needs a record of which store packages this run added and which bindings it changed -- captured
# here as snapshots taken either side of PNPUtil. Every step is best effort: a failure is logged
# and never fails the install.

function Get-DATDriverPackageId {
    # The store's own identity for a published package (e.g. 'e1d.inf_amd64_0a1b2c3d4e5f6a7b').
    # Published names are reused once a package is deleted, so the rollback compares this before
    # deleting anything by name.
    param ([Parameter(Mandatory)][string]$PublishedName)
    try {
        return "$((Get-ItemProperty -Path "HKLM:\SYSTEM\DriverDatabase\DriverInfFiles\$PublishedName" -Name 'Active' -ErrorAction Stop).Active)"
    } catch {
        return ''
    }
}

function Get-DATDriverStoreSnapshot {
    # Third-party packages in the driver store, keyed by published name (oemNN.inf).
    # Get-WindowsDriver reads them through the DISM API, which unlike 'pnputil /enum-drivers' is
    # not localised. The DriverDatabase registry key is the fallback and gives names only.
    $packages = @{}
    try {
        foreach ($d in @(Get-WindowsDriver -Online -ErrorAction Stop)) {
            if ([string]::IsNullOrEmpty($d.Driver)) { continue }
            $name = "$($d.Driver)".ToLowerInvariant()
            $packages[$name] = [pscustomobject]@{
                PublishedName = $name
                PackageId     = Get-DATDriverPackageId -PublishedName $name
                OriginalName  = [System.IO.Path]::GetFileName("$($d.OriginalFileName)")
                Provider      = "$($d.ProviderName)"
                Class         = "$($d.ClassName)"
                Version       = "$($d.Version)"
            }
        }
        return [pscustomobject]@{ Source = 'Get-WindowsDriver'; Packages = $packages }
    } catch {
        Write-CMTraceLog "[Rollback] Get-WindowsDriver failed ($($_.Exception.Message)) -- reading the driver store from the registry instead" -Severity 2
    }
    try {
        $packages = @{}
        $infKeys = Get-ChildItem -Path 'HKLM:\SYSTEM\DriverDatabase\DriverInfFiles' -ErrorAction Stop |
            Where-Object { $_.PSChildName -match '^oem\d+\.inf$' }
        foreach ($k in @($infKeys)) {
            $name = $k.PSChildName.ToLowerInvariant()
            $packages[$name] = [pscustomobject]@{
                PublishedName = $name; PackageId = Get-DATDriverPackageId -PublishedName $name
                OriginalName = ''; Provider = ''; Class = ''; Version = ''
            }
        }
        return [pscustomobject]@{ Source = 'Registry'; Packages = $packages }
    } catch {
        Write-CMTraceLog "[Rollback] Could not read the driver store -- $($_.Exception.Message)" -Severity 2
        return $null
    }
}

function Get-DATDeviceDriverBinding {
    # Device instance ID -> the driver package bound to that device.
    $bindings = @{}
    try {
        foreach ($d in @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop)) {
            if ([string]::IsNullOrEmpty($d.DeviceID) -or [string]::IsNullOrEmpty($d.InfName)) { continue }
            $bindings[$d.DeviceID] = [pscustomobject]@{
                DeviceId      = $d.DeviceID
                DeviceName    = "$($d.DeviceName)"
                DeviceClass   = "$($d.DeviceClass)"
                InfName       = "$($d.InfName)".ToLowerInvariant()
                DriverVersion = "$($d.DriverVersion)"
                Provider      = "$($d.DriverProviderName)"
            }
        }
        return $bindings
    } catch {
        Write-CMTraceLog "[Rollback] Could not read the device driver bindings -- $($_.Exception.Message)" -Severity 2
        return $null
    }
}

function Get-DATRollbackPlan {
    # Compares the snapshots taken either side of PNPUtil:
    #   AddedPackages     - store packages that did not exist before (a package that was already
    #                       staged is not listed, so a rollback never deletes it)
    #   ChangedDevices    - devices now bound to a different package
    #   DisplacedPackages - third-party packages those devices used before. Inbox drivers are
    #                       always present, so only oemNN.inf packages need keeping.
    param (
        [Parameter(Mandatory)][hashtable]$StoreBefore,
        [Parameter(Mandatory)][hashtable]$StoreAfter,
        [Parameter(Mandatory)][hashtable]$BindingsBefore,
        [Parameter(Mandatory)][hashtable]$BindingsAfter
    )
    $added = @($StoreAfter.Keys | Where-Object { -not $StoreBefore.ContainsKey($_) } | Sort-Object |
        ForEach-Object { $StoreAfter[$_] })
    $addedNames = @($added | ForEach-Object { $_.PublishedName })

    $changed = New-Object System.Collections.Generic.List[object]
    foreach ($id in @($BindingsAfter.Keys | Sort-Object)) {
        if (-not $BindingsBefore.ContainsKey($id)) { continue }
        $old = $BindingsBefore[$id]
        $new = $BindingsAfter[$id]
        if ($old.InfName -eq $new.InfName -and $old.DriverVersion -eq $new.DriverVersion) { continue }
        $changed.Add([pscustomobject]@{
            DeviceId        = $id
            DeviceName      = $new.DeviceName
            DeviceClass     = $new.DeviceClass
            PreviousInf     = $old.InfName
            PreviousVersion = $old.DriverVersion
            PreviousProvider = $old.Provider
            NewInf          = $new.InfName
            NewVersion      = $new.DriverVersion
        })
    }

    $displaced = @($changed | ForEach-Object { $_.PreviousInf } |
        Where-Object { $_ -match '^oem\d+\.inf$' -and $addedNames -notcontains $_ } |
        Sort-Object -Unique | ForEach-Object {
            $pkg = if ($StoreAfter.ContainsKey($_)) { $StoreAfter[$_] } elseif ($StoreBefore.ContainsKey($_)) { $StoreBefore[$_] } else { $null }
            [pscustomobject]@{
                PublishedName = $_
                PackageId     = if ($pkg) { "$($pkg.PackageId)" } else { '' }
                OriginalName  = if ($pkg) { $pkg.OriginalName } else { '' }
                Provider      = if ($pkg) { $pkg.Provider } else { '' }
                Class         = if ($pkg) { $pkg.Class } else { '' }
                Version       = if ($pkg) { $pkg.Version } else { '' }
                InStore       = $StoreAfter.ContainsKey($_)
            }
        })

    [pscustomobject]@{
        AddedPackages     = $added
        ChangedDevices    = $changed.ToArray()
        DisplacedPackages = $displaced
    }
}

function New-DATRollbackFolder {
    # The uninstall path re-installs these exports as SYSTEM, so the folder gets a protected ACL:
    # SYSTEM and Administrators only. A folder that already exists but is owned by anyone else was
    # not created by this script and is discarded rather than trusted.
    param ([Parameter(Mandatory)][string]$Path)
    $trustedSids = @('S-1-5-18', 'S-1-5-32-544')
    if (Test-Path -LiteralPath $Path) {
        $owner = $null
        try { $owner = (Get-Acl -LiteralPath $Path).GetOwner([System.Security.Principal.SecurityIdentifier]).Value } catch { }
        if ($trustedSids -notcontains $owner) {
            Write-CMTraceLog "[Rollback] Discarding '$Path' -- owned by '$owner', not SYSTEM or Administrators" -Severity 2
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
    }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null }
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in $trustedSids) {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            (New-Object System.Security.Principal.SecurityIdentifier($sid)), 'FullControl',
            'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function Save-DATRollbackManifest {
    # Writes Rollback.json for this package version and exports the displaced packages next to it,
    # so a rollback still works after Windows Update or Disk Cleanup has removed them from the
    # store. The manifest records a SHA256 for every exported file, and its own SHA256 goes into
    # the HKLM version marker -- the rollback verifies both before installing anything, so files
    # changed on disk are refused. Returns the manifest path, or $null.
    param (
        [Parameter(Mandatory)][string]$RollbackRoot,
        [Parameter(Mandatory)][string]$ModelKey,
        [Parameter(Mandatory)][string]$PackageVersion,
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string]$StoreSource,
        [Parameter(Mandatory)][string]$PnpUtilPath,
        [int]$PnpUtilExitCode = 0,
        [string]$PreviousVersion = '',
        [string]$OEM = '',
        [string]$Model = '',
        [string]$OS = ''
    )
    New-DATRollbackFolder -Path $RollbackRoot
    $versionDir = Join-Path $RollbackRoot "Drivers\$ModelKey\$($PackageVersion -replace '[\\/:*?"<>|]', '_')"
    if (Test-Path -LiteralPath $versionDir) { Remove-Item -LiteralPath $versionDir -Recurse -Force -ErrorAction Stop }
    New-Item -Path $versionDir -ItemType Directory -Force -ErrorAction Stop | Out-Null

    $warnings = New-Object System.Collections.Generic.List[string]
    if ($PnpUtilExitCode -eq 3010) {
        $warnings.Add('PNPUtil returned 3010 -- some bindings only change after the restart, so ChangedDevices may be incomplete')
    }
    if ($StoreSource -ne 'Get-WindowsDriver') {
        $warnings.Add("Driver store read from $StoreSource -- package metadata (class, version) is not recorded")
    }

    $exported = New-Object System.Collections.Generic.List[object]
    foreach ($pkg in @($Plan.DisplacedPackages)) {
        $entry = [ordered]@{
            PublishedName = $pkg.PublishedName
            PackageId     = $pkg.PackageId
            OriginalName  = $pkg.OriginalName
            Provider      = $pkg.Provider
            Class         = $pkg.Class
            Version       = $pkg.Version
            InStore       = $pkg.InStore
            ExportPath    = ''
            Files         = @()
        }
        if (-not $pkg.InStore) {
            $warnings.Add("$($pkg.PublishedName) was no longer in the driver store and could not be exported")
            $exported.Add([pscustomobject]$entry)
            continue
        }
        $relDir = "Export\$([System.IO.Path]::GetFileNameWithoutExtension($pkg.PublishedName))"
        $exportDir = Join-Path $versionDir $relDir
        New-Item -Path $exportDir -ItemType Directory -Force | Out-Null
        $exportOut = & $PnpUtilPath /export-driver $pkg.PublishedName "$exportDir" 2>&1
        $exportCode = $LASTEXITCODE
        if ($exportCode -ne 0) {
            Write-CMTraceLog "[Rollback] Export of $($pkg.PublishedName) failed (exit $exportCode): $(($exportOut | Out-String).Trim())" -Severity 2
            $warnings.Add("Export of $($pkg.PublishedName) failed (PNPUtil exit $exportCode)")
            Remove-Item -LiteralPath $exportDir -Recurse -Force -ErrorAction SilentlyContinue
            $exported.Add([pscustomobject]$entry)
            continue
        }
        $entry.ExportPath = $relDir
        $entry.Files = @(Get-ChildItem -LiteralPath $exportDir -Recurse -File | ForEach-Object {
            [pscustomobject]@{
                Path   = $_.FullName.Substring($versionDir.Length).TrimStart('\')
                Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        })
        $sizeMB = [math]::Round((($entry.Files | ForEach-Object { (Get-Item -LiteralPath (Join-Path $versionDir $_.Path)).Length } |
            Measure-Object -Sum).Sum) / 1MB, 1)
        Write-CMTraceLog "[Rollback] Exported displaced package $($pkg.PublishedName) ($($pkg.OriginalName) $($pkg.Version)) -- $($entry.Files.Count) file(s), $sizeMB MB"
        $exported.Add([pscustomobject]$entry)
    }

    $manifest = [ordered]@{
        SchemaVersion     = 1
        OEM               = $OEM
        Model             = $Model
        OS                = $OS
        PackageVersion    = $PackageVersion
        PreviousVersion   = $PreviousVersion
        ComputerName      = $env:COMPUTERNAME
        CreatedUtc        = (Get-Date).ToUniversalTime().ToString('o')
        PnpUtilExitCode   = $PnpUtilExitCode
        StoreSource       = $StoreSource
        AddedPackages     = @($Plan.AddedPackages)
        ChangedDevices    = @($Plan.ChangedDevices)
        DisplacedPackages = $exported.ToArray()
        Warnings          = $warnings.ToArray()
    }
    $manifestPath = Join-Path $versionDir 'Rollback.json'
    Set-Content -LiteralPath $manifestPath -Value ([pscustomobject]$manifest | ConvertTo-Json -Depth 6) -Encoding UTF8 -Force -ErrorAction Stop
    foreach ($w in $warnings) { Write-CMTraceLog "[Rollback] $w" -Severity 2 }
    return $manifestPath
}

function Remove-DATStaleRollbackData {
    # Keeps the rollback data for the newest few versions of this model; a rollback only ever
    # steps back from the installed version, so older sets are just disk space.
    param (
        [Parameter(Mandatory)][string]$ModelDir,
        [int]$Keep = 2
    )
    try {
        $stale = @(Get-ChildItem -LiteralPath $ModelDir -Directory -ErrorAction Stop |
            Sort-Object CreationTimeUtc -Descending | Select-Object -Skip $Keep)
        foreach ($dir in $stale) {
            Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
            Write-CMTraceLog "[Rollback] Removed rollback data for older version $($dir.Name)"
        }
    } catch {
        Write-CMTraceLog "[Rollback] Could not prune older rollback data -- $($_.Exception.Message)" -Severity 2
    }
}

# --- Rollback (uninstall command) --------------------------------------------------------------

function Invoke-DATPnpUtil {
    # Runs PNPUtil and returns its exit code. The output is logged but never parsed: it is
    # localised, so every decision is made on the exit code.
    param (
        [Parameter(Mandatory)][string]$PnpUtilPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $out = & $PnpUtilPath @Arguments 2>&1
    $code = $LASTEXITCODE
    foreach ($line in @($out)) {
        if (-not [string]::IsNullOrWhiteSpace("$line")) { Write-CMTraceLog "PNPUtil: $line" }
    }
    Write-CMTraceLog "PNPUtil $($Arguments -join ' ') -- exit code $code"
    return $code
}

function Test-DATSamePackage {
    # True when the store entry is the package the manifest recorded under that published name.
    # Prefers the store's package ID; falls back to original INF name and version. When neither
    # side recorded enough to compare, the name alone is trusted.
    param ($Recorded, $Current)
    if ($null -eq $Current) { return $false }
    if ($Recorded.PackageId -and $Current.PackageId) { return ($Recorded.PackageId -eq $Current.PackageId) }
    if ($Recorded.OriginalName -and $Current.OriginalName) {
        return ($Recorded.OriginalName -eq $Current.OriginalName -and "$($Recorded.Version)" -eq "$($Current.Version)")
    }
    return $true
}

function Invoke-DATDriverRollback {
    <#
        Undoes the install recorded in this version's rollback manifest:
          1. Verifies the manifest against the hash in the HKLM version marker, then copies the
             exported packages into a fresh SYSTEM-only folder and verifies every file's hash there
             (so nothing can be swapped between the check and PNPUtil reading it).
          2. Stages the displaced packages back into the driver store.
          3. Deletes the packages the install added, so each device falls back to its previous
             driver. Firmware packages are kept (firmware cannot be rolled back this way), and a
             storage controller package is only removed when every device using it has its
             previous driver available -- a storage device with no driver will not boot.
          4. Re-installs the displaced packages and rescans devices, then reports which devices
             are back on their previous driver.
          5. Sets the version marker back to the previous version so detection reports this
             version as not installed.
        Returns the uninstall exit code: 0 nothing to roll back, 3010 rolled back (restart to
        finish), 1 refused or failed (the marker is left alone so it can be retried).
    #>
    param (
        [Parameter(Mandatory)][string]$RegPath,
        [Parameter(Mandatory)][string]$PackageVersion,
        [Parameter(Mandatory)][string]$PnpUtilPath,
        [string]$StagingRoot = (Join-Path $env:SystemRoot 'Temp')
    )

    $marker = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
    if (-not $marker -or "$($marker.Version)" -ne $PackageVersion) {
        # Also the ConfigMgr supersedence case: an older Application's uninstall must not undo a
        # newer install.
        $installedText = if ($marker -and $marker.Version) { "version $($marker.Version) is installed" } else { 'no version is recorded' }
        Write-CMTraceLog "[Rollback] $installedText, not $PackageVersion -- nothing for this package to roll back"
        return 0
    }

    $manifestPath = "$($marker.RollbackManifest)"
    $expectedHash = "$($marker.RollbackManifestSha256)"
    if ([string]::IsNullOrEmpty($manifestPath) -or [string]::IsNullOrEmpty($expectedHash)) {
        $msg = "No rollback data was recorded when version $PackageVersion was installed (an older build installed it, or recording failed) -- the drivers were left in place"
        Write-CMTraceLog "[Rollback] $msg" -Severity 3
        Set-DATInstallStatus -RegPath $RegPath -Result 'Failed' -Phase 'Rollback' -ScriptExitCode 1 -ErrorMessage $msg
        return 1
    }

    # Hash and parse the same bytes, so the file cannot change between the two.
    try {
        $manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
    } catch {
        $msg = "Rollback manifest could not be read ($manifestPath): $($_.Exception.Message)"
        Write-CMTraceLog "[Rollback] $msg" -Severity 3
        Set-DATInstallStatus -RegPath $RegPath -Result 'Failed' -Phase 'Rollback' -ScriptExitCode 1 -ErrorMessage $msg
        return 1
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $actualHash = [System.BitConverter]::ToString($sha.ComputeHash($manifestBytes)).Replace('-', '') } finally { $sha.Dispose() }
    if ($actualHash -ne $expectedHash) {
        $msg = "Rollback manifest does not match the hash recorded at install time -- it has been changed, so nothing was rolled back"
        Write-CMTraceLog "[Rollback] $msg (expected $expectedHash, found $actualHash)" -Severity 3
        Set-DATInstallStatus -RegPath $RegPath -Result 'Failed' -Phase 'RollbackVerify' -ScriptExitCode 1 -ErrorMessage $msg
        return 1
    }
    $manifest = [System.Text.Encoding]::UTF8.GetString($manifestBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    if ("$($manifest.PackageVersion)" -ne $PackageVersion) {
        $msg = "Rollback manifest is for version $($manifest.PackageVersion), not $PackageVersion -- nothing was rolled back"
        Write-CMTraceLog "[Rollback] $msg" -Severity 3
        Set-DATInstallStatus -RegPath $RegPath -Result 'Failed' -Phase 'RollbackVerify' -ScriptExitCode 1 -ErrorMessage $msg
        return 1
    }
    $previousVersion = if ($manifest.PreviousVersion) { "$($manifest.PreviousVersion)" } else { "$($marker.PreviousVersion)" }
    Write-CMTraceLog "[Rollback] Manifest verified: created $($manifest.CreatedUtc), $(@($manifest.AddedPackages).Count) added package(s), $(@($manifest.ChangedDevices).Count) changed device(s), $(@($manifest.DisplacedPackages).Count) displaced package(s)"
    Write-CMTraceLog "[Rollback] Rolling back $PackageVersion -> $(if ($previousVersion) { $previousVersion } else { 'the drivers present before the first DAT install' })"
    foreach ($w in @($manifest.Warnings)) { Write-CMTraceLog "[Rollback] Recorded at install: $w" -Severity 2 }

    $versionDir = Split-Path -Parent $manifestPath
    $stageDir = Join-Path $StagingRoot "DAT-Rollback-$([guid]::NewGuid().ToString('N'))"
    $rebootNeeded = $false
    $keptPackages = New-Object System.Collections.Generic.List[string]
    $failedPackages = New-Object System.Collections.Generic.List[string]
    try {
        # 1. Copy the exports into a protected folder and verify them there
        New-DATRollbackFolder -Path $stageDir
        $restoreSets = New-Object System.Collections.Generic.List[object]
        foreach ($pkg in @($manifest.DisplacedPackages)) {
            if ([string]::IsNullOrEmpty($pkg.ExportPath)) { continue }
            foreach ($f in @($pkg.Files)) {
                $rel = "$($f.Path)"
                if ([string]::IsNullOrEmpty($rel) -or [System.IO.Path]::IsPathRooted($rel) -or $rel -match '(^|[\\/])\.\.([\\/]|$)') {
                    throw "Rollback manifest lists an unsafe file path '$rel'"
                }
                $dst = Join-Path $stageDir $rel
                $dstDir = Split-Path -Parent $dst
                if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -Path $dstDir -ItemType Directory -Force | Out-Null }
                Copy-Item -LiteralPath (Join-Path $versionDir $rel) -Destination $dst -Force -ErrorAction Stop
                if ((Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash -ne "$($f.Sha256)") {
                    throw "Exported file '$rel' does not match the hash recorded at install time"
                }
            }
            $infs = @(Get-ChildItem -LiteralPath (Join-Path $stageDir $pkg.ExportPath) -Filter '*.inf' -File -Recurse -ErrorAction SilentlyContinue)
            $restoreSets.Add([pscustomobject]@{ Package = $pkg; Infs = $infs })
        }
        Write-CMTraceLog "[Rollback] Verified $($restoreSets.Count) exported package(s) in $stageDir"

        $store = Get-DATDriverStoreSnapshot
        $bindings = Get-DATDeviceDriverBinding
        if (-not $store -or -not $bindings) { throw 'Could not read the driver store or device bindings' }

        # 2. Stage the displaced packages. A previous driver counts as available when the store
        #    still holds that exact package or its export was staged again.
        $availablePrevious = @{}
        foreach ($pkg in @($manifest.DisplacedPackages)) {
            if (Test-DATSamePackage -Recorded $pkg -Current $store.Packages[$pkg.PublishedName]) {
                $availablePrevious[$pkg.PublishedName] = $true
            }
        }
        foreach ($set in $restoreSets) {
            $staged = $false
            foreach ($inf in $set.Infs) {
                $code = Invoke-DATPnpUtil -PnpUtilPath $PnpUtilPath -Arguments @('/add-driver', $inf.FullName)
                if ($code -in @(0, 259, 3010)) { $staged = $true }
            }
            if ($staged) { $availablePrevious[$set.Package.PublishedName] = $true }
            else { Write-CMTraceLog "[Rollback] Could not stage the previous package $($set.Package.PublishedName) ($($set.Package.OriginalName))" -Severity 2 }
        }

        # 3. Delete what the install added
        $changedById = @{}
        foreach ($chg in @($manifest.ChangedDevices)) { $changedById[$chg.DeviceId] = $chg }
        $storageClasses = @('SCSIAdapter', 'HDC')
        foreach ($added in @($manifest.AddedPackages)) {
            $name = "$($added.PublishedName)"
            $current = $store.Packages[$name]
            if ($null -eq $current) {
                Write-CMTraceLog "[Rollback] $name is no longer in the driver store -- nothing to remove"
                continue
            }
            if (-not (Test-DATSamePackage -Recorded $added -Current $current)) {
                Write-CMTraceLog "[Rollback] Keeping $name -- the name now belongs to a different package ($($current.OriginalName) $($current.Version))" -Severity 2
                $keptPackages.Add("$name (name reused)")
                continue
            }
            $class = if ($current.Class) { "$($current.Class)" } else { "$($added.Class)" }
            if ($class -eq 'Firmware') {
                Write-CMTraceLog "[Rollback] Keeping $name ($($added.OriginalName)) -- firmware cannot be rolled back by removing its driver package" -Severity 2
                $keptPackages.Add("$name (firmware)")
                continue
            }
            if ([string]::IsNullOrEmpty($class) -or $storageClasses -contains $class) {
                $unsafe = @($bindings.Values | Where-Object { $_.InfName -eq $name } | Where-Object {
                    $chg = $changedById[$_.DeviceId]
                    (-not $chg) -or ($chg.PreviousInf -match '^oem\d+\.inf$' -and -not $availablePrevious.ContainsKey($chg.PreviousInf))
                })
                if ($unsafe.Count -gt 0) {
                    Write-CMTraceLog "[Rollback] Keeping $name ($($added.OriginalName), class '$class') -- $($unsafe.Count) device(s) using it have no known previous driver: $(($unsafe | ForEach-Object { $_.DeviceName }) -join '; ')" -Severity 2
                    $keptPackages.Add("$name (no fallback driver)")
                    continue
                }
            }
            $code = Invoke-DATPnpUtil -PnpUtilPath $PnpUtilPath -Arguments @('/delete-driver', $name, '/uninstall')
            if ($code -eq 3010) { $rebootNeeded = $true }
            if ($code -in @(0, 3010)) {
                Write-CMTraceLog "[Rollback] Removed $name ($($added.OriginalName) $($added.Version))"
            } else {
                Write-CMTraceLog "[Rollback] Failed to remove $name ($($added.OriginalName)) -- PNPUtil exit $code" -Severity 3
                $failedPackages.Add($name)
            }
        }

        # 4. Put the previous drivers back on their devices
        foreach ($set in $restoreSets) {
            foreach ($inf in $set.Infs) {
                $code = Invoke-DATPnpUtil -PnpUtilPath $PnpUtilPath -Arguments @('/add-driver', $inf.FullName, '/install')
                if ($code -eq 3010) { $rebootNeeded = $true }
            }
        }
        $code = Invoke-DATPnpUtil -PnpUtilPath $PnpUtilPath -Arguments @('/scan-devices')
        if ($code -eq 3010) { $rebootNeeded = $true }

        $bindingsAfter = Get-DATDeviceDriverBinding
        $restored = 0
        $notRestored = 0
        foreach ($chg in @($manifest.ChangedDevices)) {
            $now = if ($bindingsAfter) { $bindingsAfter[$chg.DeviceId] } else { $null }
            if ($null -eq $now) {
                Write-CMTraceLog "[Rollback]   $($chg.DeviceName): not present now -- cannot confirm" -Severity 2
                $notRestored++
                continue
            }
            # A re-staged package gets a new published name, so for oemNN.inf compare the version.
            $isPrevious = if ($chg.PreviousInf -match '^oem\d+\.inf$') {
                $now.InfName -match '^oem\d+\.inf$' -and $now.DriverVersion -eq $chg.PreviousVersion
            } else {
                $now.InfName -eq $chg.PreviousInf
            }
            if ($isPrevious) {
                $restored++
                Write-CMTraceLog "[Rollback]   $($chg.DeviceName): back on $($now.InfName) $($now.DriverVersion)"
            } else {
                $notRestored++
                Write-CMTraceLog "[Rollback]   $($chg.DeviceName): now $($now.InfName) $($now.DriverVersion), expected $($chg.PreviousInf) $($chg.PreviousVersion) -- a restart may complete it" -Severity 2
            }
        }
        if ($notRestored -gt 0) { $rebootNeeded = $true }
        Write-CMTraceLog "[Rollback] Devices back on their previous driver: $restored of $(@($manifest.ChangedDevices).Count)"
    } catch {
        $msg = "Rollback stopped: $($_.Exception.Message)"
        Write-CMTraceLog "[Rollback] $msg" -Severity 3
        Set-DATInstallStatus -RegPath $RegPath -Result 'Failed' -Phase 'Rollback' -ScriptExitCode 1 -ErrorMessage $msg
        return 1
    } finally {
        Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($failedPackages.Count -gt 0) {
        $msg = "Rollback incomplete: could not remove $($failedPackages -join ', ') -- run the uninstall again, or remove them with pnputil /delete-driver"
        Write-CMTraceLog "[Rollback] $msg" -Severity 3
        Set-DATInstallStatus -RegPath $RegPath -Result 'Failed' -Phase 'Rollback' -ScriptExitCode 1 -ErrorMessage $msg
        return 1
    }

    # 5. Hand the version marker back to the previous version
    if ($previousVersion) {
        Set-ItemProperty -Path $RegPath -Name 'Version' -Value $previousVersion -Force
    } else {
        Remove-ItemProperty -Path $RegPath -Name 'Version' -ErrorAction SilentlyContinue
    }
    foreach ($valueName in @('PreviousVersion', 'PendingReboot', 'PendingRebootBootTime', 'RollbackManifest', 'RollbackManifestSha256')) {
        Remove-ItemProperty -Path $RegPath -Name $valueName -ErrorAction SilentlyContinue
    }
    Set-ItemProperty -Path $RegPath -Name 'InstalledDate' -Value (Get-Date -Format 'o') -Force
    Set-ItemProperty -Path $RegPath -Name 'RolledBackFrom' -Value $PackageVersion -Force
    Set-ItemProperty -Path $RegPath -Name 'RolledBackUtc' -Value ((Get-Date).ToUniversalTime().ToString('o')) -Force
    $summary = "Rolled back from $PackageVersion to $(if ($previousVersion) { $previousVersion } else { 'the pre-DAT drivers' })"
    if ($keptPackages.Count -gt 0) { $summary += "; kept $($keptPackages -join ', ')" }
    $exitCode = if ($rebootNeeded -or @($manifest.AddedPackages).Count -gt 0) { 3010 } else { 0 }
    Set-DATInstallStatus -RegPath $RegPath -Result 'RolledBack' -Phase 'Rollback' -ScriptExitCode $exitCode -ErrorMessage $summary
    Write-CMTraceLog "[Rollback] $summary"
    Remove-Item -LiteralPath $versionDir -Recurse -Force -ErrorAction SilentlyContinue
    return $exitCode
}

{{TOAST_FUNCTIONS}}
{{PROGRESS_FUNCTIONS}}
{{PROVISIONING_FUNCTIONS}}
# Uninstall command: roll the drivers back to what this install replaced (Invoke-DATDriverRollback).
# Older builds pointed the Intune uninstall command at this script without a switch, so an
# uninstall assignment re-installed the drivers instead.
if ($Uninstall) {
    $uninstallRegPath = 'HKLM:\SOFTWARE\DriverAutomationTool\Drivers\{{OEM}}\{{ModelKey}}'
    Write-CMTraceLog "=========================================="
    Write-CMTraceLog "Driver Automation Tool - Driver Rollback Starting"
    Write-CMTraceLog "OEM: {{OEM}} | Model: {{Model}} | Package Version: {{Version}}"
    Write-CMTraceLog "Script Generated: {{Generated}}"
    Write-CMTraceLog "=========================================="
    $uninstallPnpUtil = Join-Path $env:SystemRoot 'SysNative\pnputil.exe'
    if (-not (Test-Path $uninstallPnpUtil)) { $uninstallPnpUtil = Join-Path $env:SystemRoot 'System32\pnputil.exe' }
    $uninstallExit = 1
    try {
        $uninstallExit = Invoke-DATDriverRollback -RegPath $uninstallRegPath -PackageVersion '{{Version}}' -PnpUtilPath $uninstallPnpUtil
    } catch {
        Write-CMTraceLog "FATAL ERROR during rollback: $($_.Exception.Message)" -Severity 3
        Write-CMTraceLog "Stack: $($_.ScriptStackTrace)" -Severity 3
        Set-DATInstallStatus -RegPath $uninstallRegPath -Result 'Failed' -Phase 'Rollback' -ScriptExitCode 1 -ErrorMessage $_.Exception.Message
        $uninstallExit = 1
    }
    Write-CMTraceLog "Driver rollback finished -- exit code $uninstallExit"
    Write-CMTraceLog "=========================================="
    exit $uninstallExit
}

try {
    Write-CMTraceLog "=========================================="
    if ($WhatIf) { Write-CMTraceLog "*** WHATIF MODE -- no drivers will be installed ***" -Severity 2 }
    Write-CMTraceLog "Driver Automation Tool - Install Starting"
    Write-CMTraceLog "OEM: {{OEM}} | Model: {{Model}}"
    Write-CMTraceLog "OS: {{OS}} | Package Version: {{Version}}"
    Write-CMTraceLog "Script Generated: {{Generated}}"
    Write-CMTraceLog "=========================================="

    # -- Verbose device / environment context (aids Intune and custom log troubleshooting) --
    try {
        $ctxCs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $ctxOs = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        Write-CMTraceLog "Device: $($ctxCs.Manufacturer) | Model: $($ctxCs.Model) | SKU: $($ctxCs.SystemSKUNumber)"
        Write-CMTraceLog "OS: $($ctxOs.Caption) ($($ctxOs.Version)) | Build: $($ctxOs.BuildNumber)"
        Write-CMTraceLog "Computer: $env:COMPUTERNAME | Architecture: $env:PROCESSOR_ARCHITECTURE"
        Write-CMTraceLog "PowerShell: $($PSVersionTable.PSVersion) | 64-bit process: $([Environment]::Is64BitProcess)"
    } catch {
        Write-CMTraceLog "WARNING: Could not gather full device context -- $($_.Exception.Message)" -Severity 2
    }

    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    # Defined before the toast gate so the deferral-reason logging inside the toast block can
    # record status against the per-model key when a user snoozes the update.
    $VersionRegPath = 'HKLM:\SOFTWARE\DriverAutomationTool\Drivers\{{OEM}}\{{ModelKey}}'

    # Autopilot provisioning is decided once, before the toast gate. Nobody can answer a prompt
    # while the Enrollment Status Page runs, so the gate (prompt, deferrals, snooze) is skipped and
    # the progress notification and status toasts stay hidden. Deferral state is left untouched.
    $script:DATAutopilot = Test-DATAutopilotProvisioning
    if ($script:DATAutopilot.InProvisioning) {
        Write-CMTraceLog "[Autopilot] Installing without prompting during Autopilot provisioning ($($script:DATAutopilot.Phase))"
    } else {
{{TOAST_BLOCK}}
    }
    # Optional install progress notification (no-op unless enabled for this package)
    Start-DATInstallProgress -ToastScript (Join-Path $ScriptDir 'Show-ProgressToast.ps1')
    $WimFile = Join-Path $ScriptDir "DriverPackage.wim"
    $ExtractPath = Join-Path $env:ProgramData "DriverAutomationTool\Extract"
    $installPhase = 'Init'
    $driverToolExitCode = 0

    Write-CMTraceLog "Script directory: $ScriptDir"
    Write-CMTraceLog "WIM file path: $WimFile"
    Write-CMTraceLog "Extract target: $ExtractPath"
    Write-CMTraceLog "Version registry path: $VersionRegPath"

    if (-not (Test-Path $WimFile)) {
        Write-CMTraceLog "ERROR: WIM file not found at $WimFile" -Severity 3
        if (-not $WhatIf) { Set-DATInstallStatus -RegPath $VersionRegPath -Result 'Failed' -Phase 'WimMissing' -ScriptExitCode 1 -ErrorMessage "Driver package WIM not found at $WimFile" }
        exit 1
    }

    $wimSize = [math]::Round((Get-Item $WimFile).Length / 1MB, 2)
    Write-CMTraceLog "WIM file size: $wimSize MB"

    # Clean previous extraction if it exists
    if (Test-Path $ExtractPath) {
        Write-CMTraceLog "Removing previous driver extraction at $ExtractPath"
        Remove-Item -Path $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Create extraction directory
    New-Item -Path $ExtractPath -ItemType Directory -Force | Out-Null
    Write-CMTraceLog "Created extraction directory: $ExtractPath"

    # Extract WIM contents directly using Expand-WindowsImage (DISM /Apply-Image)
    # This avoids mounting entirely, bypassing WOF overlay issues where
    # WIM-mounted files have FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS causing
    # both Copy-Item and robocopy to fail with error 4350 / 0x10FE
    $installPhase = 'Extraction'
    try {
        Write-CMTraceLog "Extracting driver package WIM directly to: $ExtractPath"
        Set-DATInstallProgress -Step 1 -MeasurePath $ExtractPath -WimFile $WimFile
        Expand-WindowsImage -ImagePath $WimFile -ApplyPath $ExtractPath -Index 1 -ErrorAction Stop
        Write-CMTraceLog "WIM extraction completed successfully"
    } catch [System.Exception] {
        Write-CMTraceLog "ERROR: Failed to extract driver package WIM file. Error: $($_.Exception.Message)" -Severity 3
        if (-not $WhatIf) { Set-DATInstallStatus -RegPath $VersionRegPath -Result 'Failed' -Phase 'Extraction' -ScriptExitCode 1 -ErrorMessage $_.Exception.Message }
        exit 1
    }

    $extractedFiles = (Get-ChildItem -Path $ExtractPath -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-CMTraceLog "WIM extraction complete. Files extracted: $extractedFiles"

    # Find all INF files for driver installation
    $infFiles = Get-ChildItem -Path $ExtractPath -Recurse -Filter "*.inf" -File -ErrorAction SilentlyContinue
    $infCount = ($infFiles | Measure-Object).Count
    Write-CMTraceLog "Found $infCount INF driver files to process"
    foreach ($infF in $infFiles) {
        Write-CMTraceLog "  INF: $($infF.FullName.Substring($ExtractPath.Length).TrimStart('\','/'))"
    }

    if ($infCount -eq 0) {
        Write-CMTraceLog "WARNING: No INF files found in extracted drivers" -Severity 2
        if (-not $WhatIf) { Set-DATInstallStatus -RegPath $VersionRegPath -Result 'NoContent' -Phase 'InfScan' -ScriptExitCode 0 -ErrorMessage 'No INF driver files were found in the extracted package' }
        exit 0
    }

    # Install drivers using PNPUtil
    # Use SysNative to bypass WoW64 file system redirection when the IME runs as 32-bit
    $sysNativePath = Join-Path $env:SystemRoot "SysNative\pnputil.exe"
    $system32Path  = Join-Path $env:SystemRoot "System32\pnputil.exe"
    $pnpUtilPath   = if (Test-Path $sysNativePath) { $sysNativePath } else { $system32Path }
    Write-CMTraceLog "PNPUtil path resolved to: $pnpUtilPath"
    $installPhase = 'DriverInstall'
    $driverRebootRequired = $false
    if ($WhatIf) {
        Write-CMTraceLog "WHATIF: Would install drivers via PNPUtil from $ExtractPath" -Severity 2
        Write-CMTraceLog "WHATIF: PNPUtil arguments: /add-driver `"$ExtractPath\*.inf`" /subdirs /install" -Severity 2
    } else {
        # Rollback baseline -- the driver store and device bindings before PNPUtil changes them
        Write-CMTraceLog "[Rollback] Capturing the driver store and device bindings before install..."
        $rollbackStoreBefore    = Get-DATDriverStoreSnapshot
        $rollbackBindingsBefore = Get-DATDeviceDriverBinding
        if ($rollbackStoreBefore -and $rollbackBindingsBefore) {
            Write-CMTraceLog "[Rollback] Baseline: $($rollbackStoreBefore.Packages.Count) third-party store package(s) ($($rollbackStoreBefore.Source)), $($rollbackBindingsBefore.Count) device binding(s)"
        }

        Write-CMTraceLog "Starting PNPUtil driver installation from $ExtractPath..."
        $pnpArgs = "/add-driver `"$ExtractPath\*.inf`" /subdirs /install"
        Write-CMTraceLog "PNPUtil arguments: $pnpArgs"
        Set-DATInstallProgress -Step 2 -Total $infCount -CountFile "$env:TEMP\pnp_stdout.txt"

        try {
            $pnpProcess = Start-Process -FilePath $pnpUtilPath -ArgumentList $pnpArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\pnp_stdout.txt" -RedirectStandardError "$env:TEMP\pnp_stderr.txt" -ErrorAction Stop
        } catch {
            Write-CMTraceLog "ERROR: Failed to launch pnputil.exe -- $($_.Exception.Message)" -Severity 3
            Set-DATInstallStatus -RegPath $VersionRegPath -Result 'Failed' -Phase 'PnpUtilLaunch' -ScriptExitCode 1 -ErrorMessage $_.Exception.Message
            exit 1
        }

        if (Test-Path "$env:TEMP\pnp_stdout.txt") {
            $pnpOutput = Get-Content "$env:TEMP\pnp_stdout.txt" -ErrorAction SilentlyContinue
            foreach ($line in $pnpOutput) {
                if (-not [string]::IsNullOrWhiteSpace($line)) { Write-CMTraceLog "PNPUtil: $line" }
            }
            Remove-Item "$env:TEMP\pnp_stdout.txt" -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path "$env:TEMP\pnp_stderr.txt") {
            $pnpErr = Get-Content "$env:TEMP\pnp_stderr.txt" -ErrorAction SilentlyContinue
            foreach ($line in $pnpErr) {
                if (-not [string]::IsNullOrWhiteSpace($line)) { Write-CMTraceLog "PNPUtil Error: $line" -Severity 2 }
            }
            Remove-Item "$env:TEMP\pnp_stderr.txt" -Force -ErrorAction SilentlyContinue
        }

        Write-CMTraceLog "PNPUtil completed with exit code: $($pnpProcess.ExitCode)"
        $driverToolExitCode = $pnpProcess.ExitCode

        # Known PNPUtil exit codes:
        #   0    = Success, no reboot required
        #   1    = Partial success / some drivers not added (treated as success)
        #   259  = ERROR_NO_MORE_ITEMS -- all drivers already staged/current (success)
        #   3010 = ERROR_SUCCESS_REBOOT_REQUIRED -- success, reboot needed
        # Anything else is a genuine failure.
        if ($pnpProcess.ExitCode -notin @(0, 1, 259, 3010)) {
            Write-CMTraceLog "ERROR: PNPUtil reported a failure (exit code $($pnpProcess.ExitCode))" -Severity 3
            Set-DATInstallStatus -RegPath $VersionRegPath -Result 'Failed' -Phase 'PnpUtil' -ToolExitCode $pnpProcess.ExitCode -ScriptExitCode 1 -ErrorMessage "PNPUtil returned failure exit code $($pnpProcess.ExitCode)"
            exit 1
        }
        if ($pnpProcess.ExitCode -eq 3010) {
            Write-CMTraceLog "PNPUtil: reboot required to complete driver installation" -Severity 2
            $driverRebootRequired = $true
        }
        if ($pnpProcess.ExitCode -eq 259) {
            Write-CMTraceLog "PNPUtil: all drivers already staged -- no new drivers added"
        }
        Set-DATInstallProgress -Step 3
    }

    # Record what this install changed, for a later rollback. A re-run of the version that is
    # already installed keeps the existing manifest: its snapshots would show nothing added and
    # overwrite the record of the real install.
    $previousVersion = ''
    $rollbackManifestPath = $null
    if (-not $WhatIf) {
        $installPhase = 'RollbackManifest'
        try {
            $priorVersion = (Get-ItemProperty -Path $VersionRegPath -Name 'Version' -ErrorAction SilentlyContinue).Version
            $priorManifest = (Get-ItemProperty -Path $VersionRegPath -Name 'RollbackManifest' -ErrorAction SilentlyContinue).RollbackManifest
            if ($priorVersion -and $priorVersion -ne '{{Version}}') { $previousVersion = "$priorVersion" }
            if ($priorVersion -eq '{{Version}}' -and $priorManifest -and (Test-Path -LiteralPath $priorManifest)) {
                Write-CMTraceLog "[Rollback] Version {{Version}} was already installed -- keeping its rollback manifest: $priorManifest"
            } elseif (-not ($rollbackStoreBefore -and $rollbackBindingsBefore)) {
                Write-CMTraceLog "[Rollback] No baseline was captured -- rollback data is not recorded for this install" -Severity 2
            } else {
                $rollbackStoreAfter    = Get-DATDriverStoreSnapshot
                $rollbackBindingsAfter = Get-DATDeviceDriverBinding
                if ($rollbackStoreAfter -and $rollbackBindingsAfter) {
                    $rollbackPlan = Get-DATRollbackPlan -StoreBefore $rollbackStoreBefore.Packages -StoreAfter $rollbackStoreAfter.Packages `
                        -BindingsBefore $rollbackBindingsBefore -BindingsAfter $rollbackBindingsAfter
                    Write-CMTraceLog "[Rollback] Added $(@($rollbackPlan.AddedPackages).Count) store package(s), changed $(@($rollbackPlan.ChangedDevices).Count) device binding(s), displaced $(@($rollbackPlan.DisplacedPackages).Count) third-party package(s)"
                    foreach ($chg in @($rollbackPlan.ChangedDevices)) {
                        Write-CMTraceLog "[Rollback]   $($chg.DeviceName) [$($chg.DeviceClass)]: $($chg.PreviousInf) $($chg.PreviousVersion) -> $($chg.NewInf) $($chg.NewVersion)"
                    }
                    $rollbackRoot = Join-Path $env:ProgramData 'DriverAutomationTool\Rollback'
                    $rollbackManifestPath = Save-DATRollbackManifest -RollbackRoot $rollbackRoot -ModelKey '{{ModelKey}}' `
                        -PackageVersion '{{Version}}' -Plan $rollbackPlan -StoreSource $rollbackStoreAfter.Source `
                        -PnpUtilPath $pnpUtilPath -PnpUtilExitCode $driverToolExitCode -PreviousVersion $previousVersion `
                        -OEM '{{OEM}}' -Model '{{Model}}' -OS '{{OS}}'
                    Write-CMTraceLog "[Rollback] Manifest written: $rollbackManifestPath"
                    Remove-DATStaleRollbackData -ModelDir (Join-Path $rollbackRoot 'Drivers\{{ModelKey}}')
                }
            }
        } catch {
            $rollbackManifestPath = $null
            Write-CMTraceLog "[Rollback] WARNING: Could not record rollback data -- $($_.Exception.Message). The install itself is unaffected." -Severity 2
        }
        $installPhase = 'DriverInstall'
    }

    # Write version marker to registry for detection
    # PNPUtil exit code 3010 means the new drivers were staged but require a reboot to actually
    # bind/activate (common for drivers replacing an in-use device such as GPU/audio/chipset).
    # Until that reboot happens the device is still running the OLD driver, so the marker is
    # tagged as "PendingReboot" and the detection script will not trust it as installed until it
    # can confirm (via LastBootUpTime) that a reboot has actually occurred since it was staged.
    # Without this, a device whose reboot never happens would report as Installed in Intune
    # forever despite still running the old drivers.
    if ($WhatIf) {
        Write-CMTraceLog "WHATIF: Would write version '{{Version}}' to registry at $VersionRegPath" -Severity 2
    } else {
        if (-not (Test-Path $VersionRegPath)) {
            New-Item -Path $VersionRegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $VersionRegPath -Name 'Version' -Value '{{Version}}' -Force
        Set-ItemProperty -Path $VersionRegPath -Name 'InstalledDate' -Value (Get-Date -Format 'o') -Force
        Set-ItemProperty -Path $VersionRegPath -Name 'OS' -Value '{{OS}}' -Force
        if ($previousVersion) {
            Set-ItemProperty -Path $VersionRegPath -Name 'PreviousVersion' -Value $previousVersion -Force
        }
        if ($rollbackManifestPath) {
            # The manifest's hash lives in HKLM, which only administrators can write, so a rollback
            # can prove the manifest on disk is the one this install wrote.
            $manifestHash = (Get-FileHash -LiteralPath $rollbackManifestPath -Algorithm SHA256).Hash
            Set-ItemProperty -Path $VersionRegPath -Name 'RollbackManifest' -Value $rollbackManifestPath -Force
            Set-ItemProperty -Path $VersionRegPath -Name 'RollbackManifestSha256' -Value $manifestHash -Force
        } elseif ($previousVersion) {
            # A new version was installed without rollback data -- the old values describe the
            # previous version and must not be used to roll this one back.
            Remove-ItemProperty -Path $VersionRegPath -Name 'RollbackManifest' -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $VersionRegPath -Name 'RollbackManifestSha256' -ErrorAction SilentlyContinue
        }
        if ($driverRebootRequired) {
            try {
                $bootTimeNow = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
                Set-ItemProperty -Path $VersionRegPath -Name 'PendingReboot' -Value 1 -Type DWord -Force
                Set-ItemProperty -Path $VersionRegPath -Name 'PendingRebootBootTime' -Value $bootTimeNow.ToString('o') -Force
                Write-CMTraceLog "Version marker written to registry: $VersionRegPath = {{Version}} (PendingReboot -- not yet applied)"
            } catch {
                Write-CMTraceLog "WARNING: Failed to record PendingReboot boot time -- $($_.Exception.Message)" -Severity 2
                Write-CMTraceLog "Version marker written to registry: $VersionRegPath = {{Version}} (PendingReboot -- not yet applied)"
            }
        } else {
            Remove-ItemProperty -Path $VersionRegPath -Name 'PendingReboot' -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $VersionRegPath -Name 'PendingRebootBootTime' -ErrorAction SilentlyContinue
            Write-CMTraceLog "Version marker written to registry: $VersionRegPath = {{Version}}"
        }

        $statusResult = if ($driverRebootRequired) { 'PendingReboot' } else { 'Success' }
        Set-DATInstallStatus -RegPath $VersionRegPath -Result $statusResult -ToolExitCode $driverToolExitCode -ScriptExitCode 0 -Phase 'Complete'
    }

    # Emit the INF-level "DriversAdded" report for the patch-management reporting service.
    # Runs while the extracted INFs are still present (before cleanup) and only for a real install.
    if (-not $WhatIf) {
        Write-DATDriversAddedReport -ExtractPath $ExtractPath -OEM '{{OEM}}' -Model '{{Model}}' `
            -OS '{{OS}}' -PackageVersion '{{Version}}' -PackageReleaseDate '{{ReleaseDate}}'
    }

    # Clean up extracted drivers to save disk space
    Write-CMTraceLog "Driver installation complete. Cleaning up extracted files..."
    Remove-Item -Path $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-CMTraceLog "Cleanup complete."

    Complete-DATInstallProgress -Outcome Success
{{STATUS_TOAST_BLOCK}}
    Write-CMTraceLog "=========================================="
    if ($WhatIf) {
        Write-CMTraceLog "WHATIF: Driver installation simulation completed -- no changes were made"
    } else {
        Write-CMTraceLog "Driver installation completed successfully"
    }
    Write-CMTraceLog "=========================================="
    exit 0
}
catch {
    Write-CMTraceLog "FATAL ERROR: $($_.Exception.Message)" -Severity 3
    Write-CMTraceLog "Stack: $($_.ScriptStackTrace)" -Severity 3
    if (-not $WhatIf -and $VersionRegPath) {
        $phaseForStatus = if ($installPhase) { $installPhase } else { 'Unknown' }
        Set-DATInstallStatus -RegPath $VersionRegPath -Result 'Failed' -Phase $phaseForStatus -ToolExitCode $driverToolExitCode -ScriptExitCode 1 -ErrorMessage $_.Exception.Message
    }
    Complete-DATInstallProgress -Outcome Failed
{{STATUS_TOAST_ERROR_BLOCK}}
    exit 1
}
finally {
    # Closes the progress notification on any exit path that did not report an outcome
    Stop-DATInstallProgress
    # Clean up temp files that may have been left behind on any exit path
    foreach ($tmpFile in @("$env:TEMP\dism_stdout.txt", "$env:TEMP\dism_stderr.txt",
                           "$env:TEMP\robocopy_stdout.txt",
                           "$env:TEMP\pnp_stdout.txt", "$env:TEMP\pnp_stderr.txt")) {
        if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
    }
}
