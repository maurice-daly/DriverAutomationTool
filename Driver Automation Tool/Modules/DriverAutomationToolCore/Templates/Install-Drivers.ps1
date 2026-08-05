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
    [switch]$WhatIf
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
        [Parameter(Mandatory)][ValidateSet('Success','PendingReboot','AlreadyCurrent','NoContent','RetryScheduled','Failed')][string]$Result,
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

        # Running attempt counter -- lets reporting spot devices stuck retrying/failing
        $priorAttempts = 0
        try { $priorAttempts = [int](Get-ItemProperty -Path $RegPath -Name 'AttemptCount' -ErrorAction SilentlyContinue).AttemptCount } catch { $priorAttempts = 0 }
        Set-ItemProperty -Path $RegPath -Name 'AttemptCount' -Value ($priorAttempts + 1) -Type DWord -Force

        if ($Result -in @('Success','PendingReboot','AlreadyCurrent')) {
            Set-ItemProperty -Path $RegPath -Name 'LastSuccessUtc' -Value $nowUtc -Force
            # Successful (or no-op) run -- clear any prior deferral/failure reason so custom
            # reporting reflects the current healthy state rather than a stale cause.
            Remove-ItemProperty -Path $RegPath -Name 'Reason' -Force -ErrorAction SilentlyContinue
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
{{TOAST_FUNCTIONS}}
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
    $VersionRegPath = 'HKLM:\SOFTWARE\DriverAutomationTool\Drivers\{{OEM}}\{{Model}}'
{{TOAST_BLOCK}}
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
        Write-CMTraceLog "Starting PNPUtil driver installation from $ExtractPath..."
        $pnpArgs = "/add-driver `"$ExtractPath\*.inf`" /subdirs /install"
        Write-CMTraceLog "PNPUtil arguments: $pnpArgs"

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
{{STATUS_TOAST_ERROR_BLOCK}}
    exit 1
}
finally {
    # Clean up temp files that may have been left behind on any exit path
    foreach ($tmpFile in @("$env:TEMP\dism_stdout.txt", "$env:TEMP\dism_stderr.txt",
                           "$env:TEMP\robocopy_stdout.txt",
                           "$env:TEMP\pnp_stdout.txt", "$env:TEMP\pnp_stderr.txt")) {
        if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
    }
}
