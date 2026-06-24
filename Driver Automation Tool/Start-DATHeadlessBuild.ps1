<#
.SYNOPSIS
    Headless CLI runner for Driver Automation Tool scheduled/unattended builds.
.DESCRIPTION
    Loads a BuildConfig.json file, imports the DriverAutomationToolCore module,
    and processes all configured models without launching the UI.
.PARAMETER ConfigPath
    Path to a BuildConfig.json file. Defaults to Settings\BuildConfig.json.
#>
[CmdletBinding()]
param (
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot

# Default config path
if ([string]::IsNullOrEmpty($ConfigPath)) {
    $ConfigPath = Join-Path $scriptRoot 'Settings\BuildConfig.json'
}

# Import core module
$modulePath = Join-Path $scriptRoot 'Modules\DriverAutomationToolCore\DriverAutomationToolCore.psd1'
if (-not (Test-Path $modulePath)) {
    Write-Error "Core module not found: $modulePath"
    exit 1
}
Import-Module $modulePath -Force

# Override execution mode -- module default uses [Environment]::UserInteractive which
# is $true in a console session. Headless builds are always 'Scheduled Task'.
$global:ExecutionMode = 'Scheduled Task'

# Load and validate config
try {
    $config = Import-DATBuildConfig -ConfigPath $ConfigPath
    Write-Host "[Headless] Loaded config: $($config.Models.Count) model(s), Platform=$($config.Platform), PackageType=$($config.PackageType)"
} catch {
    Write-Error "Failed to load build config: $_"
    exit 1
}

# Resolve paths (use config overrides if specified, otherwise default to script-relative)
$packagePath  = if ($config.PackagePath) { $config.PackagePath } else { Join-Path $scriptRoot 'Packages' }
$storagePath  = if ($config.TempPath)    { $config.TempPath }    else { Join-Path $scriptRoot 'Temp' }

# Ensure paths exist
foreach ($dir in @($packagePath, $storagePath)) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        Write-Host "[Headless] Created directory: $dir"
    }
}

# Align the module temp directory with the configured storage path BEFORE the pre-fetch
# below. Catalog helpers (Get-DATBiosCatalog / Get-DATOEMModelInfo) cache to
# $global:TempDirectory; without this the pre-fetch would read/write the module default
# (<scriptRoot>\Temp) while Start-DATModelProcessing later uses $storagePath, causing the
# pre-fetch to consult a stale/empty cache and resolve no version (#817). Setting it here
# keeps both phases consistent. Start-DATModelProcessing sets the same value again.
$global:TempDirectory = $storagePath

# Log the resolved paths and cleanup setting up front so scheduled-run logs make it obvious
# where downloads/extraction land, where finished packages go, and whether the temp folder
# will be cleared on exit (#816 diagnostics).
Write-Host "[Headless] Temp/storage path : $storagePath"
Write-Host "[Headless] Package path      : $packagePath"
Write-Host "[Headless] CleanTempOnExit    : $($config.CleanTempOnExit)"
Write-DATLogEntry -Value "[Headless] Temp/storage path: $storagePath" -Severity 1
Write-DATLogEntry -Value "[Headless] Package path: $packagePath" -Severity 1
Write-DATLogEntry -Value "[Headless] CleanTempOnExit: $($config.CleanTempOnExit)" -Severity 1

# Create a headless registry path for state tracking
$headlessRegPath = 'HKCU:\SOFTWARE\DriverAutomationTool\Headless'
if (-not (Test-Path $headlessRegPath)) {
    New-Item -Path $headlessRegPath -Force | Out-Null
}

# Write WIM engine and compression settings to $global:RegPath so the core module picks them up.
# The UI saves these under HKLM:\SOFTWARE\DriverAutomationTool; headless must do the same
# when the BuildConfig overrides them, otherwise the module defaults to DISM.
if (-not [string]::IsNullOrEmpty($config.WimEngine)) {
    $validEngines = @('dism', 'wimlib', '7zip')
    if ($config.WimEngine -in $validEngines) {
        Set-DATRegistryValue -Name 'WimEngine' -Value $config.WimEngine -Type String
        Write-Host "[Headless] WIM engine set to: $($config.WimEngine)"
    } else {
        Write-Host "[Headless] Warning: Invalid WimEngine '$($config.WimEngine)' -- valid values: $($validEngines -join ', ')"
    }
}
if (-not [string]::IsNullOrEmpty($config.CompressionLevel)) {
    $validLevels = @('none', 'fast', 'max')
    if ($config.CompressionLevel -in $validLevels) {
        Set-DATRegistryValue -Name 'DismCompression' -Value $config.CompressionLevel -Type String
        Write-Host "[Headless] Compression level set to: $($config.CompressionLevel)"
    } else {
        Write-Host "[Headless] Warning: Invalid CompressionLevel '$($config.CompressionLevel)' -- valid values: $($validLevels -join ', ')"
    }
}

# Guard: Microsoft models do not support standalone BIOS packages
$headlessModels = $config.Models
if ($config.PackageType -eq 'BIOS') {
    $msModels = @($headlessModels | Where-Object { $_.OEM -eq 'Microsoft' })
    if ($msModels.Count -gt 0 -and $msModels.Count -eq @($headlessModels).Count) {
        Write-Error "[Headless] All selected models are Microsoft. BIOS packages are not supported for Microsoft Surface devices (firmware is delivered via driver updates). Use PackageType 'Drivers' or 'All'."
        exit 1
    }
    if ($msModels.Count -gt 0) {
        $msNames = ($msModels | ForEach-Object { $_.Model }) -join ', '
        Write-Host "[Headless] Excluding $($msModels.Count) Microsoft model(s) from BIOS build (firmware delivered via driver updates): $msNames"
        $headlessModels = @($headlessModels | Where-Object { $_.OEM -ne 'Microsoft' })
    }
}

# Resolve catalog versions for the skip-if-current guard (#807).
# BuildConfig models carry no catalog Version/BIOSVersion, so in scheduled/headless mode the
# skip-if-current check in Start-DATModelProcessing was always disabled -- causing packages
# already at the current version to be fully downloaded, extracted and (re)packaged before
# being skipped at the ConfigMgr/Intune stage. Resolve them up front, exactly as the UI does
# during model enumeration, so unchanged packages are skipped before any heavy work.
if ($config.Platform -in @('Configuration Manager', 'Intune') -and @($headlessModels).Count -gt 0) {
    # Driver versions -- enumerate the OEM catalogs once per distinct OS, match by OEM + Model.
    if ($config.PackageType -in @('Drivers', 'All')) {
        try {
            $driverModels = @($headlessModels | Where-Object { $_.OEM -ne 'Microsoft' })
            foreach ($osGroup in ($driverModels | Group-Object -Property OS)) {
                $osValue = $osGroup.Name
                if ([string]::IsNullOrEmpty($osValue)) { continue }
                $groupOEMs = @($osGroup.Group | ForEach-Object { $_.OEM } | Sort-Object -Unique)
                Write-Host "[Headless] Resolving driver catalog versions for '$osValue' ($($groupOEMs -join ', '))..."
                $catalogModels = @(Get-DATOEMModelInfo -RequiredOEMs $groupOEMs -OS $osValue -Architecture $config.Architecture)
                foreach ($m in $osGroup.Group) {
                    # Exact model-name match first.
                    $match = $catalogModels | Where-Object { $_.OEM -eq $m.OEM -and $_.Model -eq $m.Model } | Select-Object -First 1
                    # Fallback: match on overlapping baseboard/SystemSKU values. The BuildConfig
                    # model name (the UI display name) frequently differs from the OEM catalog
                    # SystemName (e.g. HP "Elite x360 1040 14 inch G11 2-in-1" vs catalog
                    # "EliteBook 1040 14 inch G11"), so an exact-name match alone leaves the
                    # version empty and disables skip-if-current, forcing a full download (#817).
                    if (-not $match -and -not [string]::IsNullOrEmpty($m.Baseboards)) {
                        $modelBoards = @("$($m.Baseboards)" -split '[,;\s]+' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
                        if ($modelBoards.Count -gt 0) {
                            $match = $catalogModels | Where-Object {
                                $_.OEM -eq $m.OEM -and -not [string]::IsNullOrEmpty($_.Baseboards) -and
                                @("$($_.Baseboards)" -split '[,;\s]+' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ -in $modelBoards }).Count -gt 0
                            } | Select-Object -First 1
                            if ($match) {
                                Write-Host "[Headless] Matched '$($m.Model)' to catalog model '$($match.Model)' via baseboard ($($m.Baseboards))"
                            }
                        }
                    }
                    if ($match -and -not [string]::IsNullOrEmpty($match.Version)) { $m.Version = $match.Version }
                }
            }
        } catch {
            Write-Host "[Headless] Warning: Driver catalog version resolution failed -- skip-if-current may be bypassed: $($_.Exception.Message)"
        }
    }
    # BIOS versions -- lightweight JSON catalog lookup by baseboard.
    if ($config.PackageType -in @('BIOS', 'All')) {
        try {
            $headlessBiosCatalog = Get-DATBiosCatalog
            foreach ($m in $headlessModels) {
                if ($m.OEM -eq 'Microsoft') { continue }
                $bb = if ($m.Baseboards -is [array]) { $m.Baseboards -join ',' } else { [string]$m.Baseboards }
                if ([string]::IsNullOrEmpty($bb)) { continue }
                $biosMatch = Find-DATBiosPackage -OEM $m.OEM -Baseboards $bb -Catalog $headlessBiosCatalog
                if ($biosMatch -and -not [string]::IsNullOrEmpty($biosMatch.Version)) { $m.BIOSVersion = $biosMatch.Version }
            }
        } catch {
            Write-Host "[Headless] Warning: BIOS catalog version resolution failed -- skip-if-current may be bypassed: $($_.Exception.Message)"
        }
    }
}

# Build splat for Start-DATModelProcessing (matches function signature)
$processingParams = @{
    ScriptDirectory = $scriptRoot
    RegPath         = $global:RegPath
    SelectedModels  = $headlessModels
    RunningMode     = $config.Platform
    PackageType     = $config.PackageType
    PackagePath     = $packagePath
    StoragePath     = $storagePath
}
if ($config.DisableToast) { $processingParams['DisableToast'] = $true }
if ($config.DisableRestart) { $processingParams['DisableRestart'] = $true }
if ($config.AlarmMode) { $processingParams['AlarmMode'] = $true }
if ($config.CreateIntuneWinOnly) { $processingParams['CreateIntuneWinOnly'] = $true }
if ($config.ToastTimeoutAction -ne 'RemindMeLater') { $processingParams['ToastTimeoutAction'] = $config.ToastTimeoutAction }
if ($config.MaxDeferrals -gt 0) { $processingParams['MaxDeferrals'] = $config.MaxDeferrals }
if ($config.BIOSRestartDelayMinutes -gt 0) { $processingParams['RestartDelaySeconds'] = $config.BIOSRestartDelayMinutes * 60 }

# Maintenance window -- serialize the configured schedule to JSON for the requirement scripts
if ($config.MaintenanceWindowEnabled -and $config.MaintenanceWindows -and @($config.MaintenanceWindows).Count -gt 0) {
    $mwJson = ConvertTo-Json @($config.MaintenanceWindows) -Compress
    $processingParams['MaintenanceWindowsJson'] = $mwJson
    Write-Host "[Headless] Maintenance window enabled ($($config.MaintenanceWindowMode)) -- $(@($config.MaintenanceWindows).Count) window(s)"
}

# Teams notifications
if ($config.TeamsNotificationsEnabled -and -not [string]::IsNullOrEmpty($config.TeamsWebhookUrl)) {
    $processingParams['TeamsNotificationsEnabled'] = $true
    $processingParams['TeamsWebhookUrl'] = $config.TeamsWebhookUrl
}

# Normalise platform name -- BuildConfig accepts 'ConfigMgr' or 'Configuration Manager'
if ($config.Platform -in @('ConfigMgr', 'Configuration Manager')) {
    $processingParams['RunningMode'] = 'Configuration Manager'
}

# Platform-specific settings
switch ($config.Platform) {
    'Intune' {
        if ($config.Intune) {
            $tenantId = $config.Intune.TenantId
            $appId    = $config.Intune.AppId
            $appSecret = $config.Intune.AppSecret

            # If no credentials in config, try reading from registry (UI-saved DPAPI-encrypted secret)
            if ([string]::IsNullOrEmpty($tenantId) -or [string]::IsNullOrEmpty($appId) -or [string]::IsNullOrEmpty($appSecret)) {
                $uiRegPath = 'HKCU:\SOFTWARE\DriverAutomationTool'
                $uiReg = Get-ItemProperty -Path $uiRegPath -ErrorAction SilentlyContinue
                if ($uiReg) {
                    if ([string]::IsNullOrEmpty($tenantId) -and $uiReg.IntuneTenantId) { $tenantId = $uiReg.IntuneTenantId }
                    if ([string]::IsNullOrEmpty($appId) -and $uiReg.IntuneAppId) { $appId = $uiReg.IntuneAppId }
                    if ([string]::IsNullOrEmpty($appSecret) -and $uiReg.IntuneClientSecret) {
                        try {
                            $secString = ConvertTo-SecureString -String $uiReg.IntuneClientSecret -ErrorAction Stop
                            $appSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secString))
                            Write-Host "[Headless] Intune credentials loaded from registry (DPAPI)"
                        } catch {
                            Write-Host "[Headless] Warning: Could not decrypt saved client secret: $($_.Exception.Message)"
                        }
                    }
                }
            }

            if ([string]::IsNullOrEmpty($tenantId) -or [string]::IsNullOrEmpty($appId) -or [string]::IsNullOrEmpty($appSecret)) {
                Write-Error "[Headless] Intune mode requires TenantId, AppId, and AppSecret in BuildConfig.json or saved in the UI registry."
                exit 1
            }

            Write-Host "[Headless] Authenticating to Intune (tenant: $tenantId, app: $appId)..."
            $authResult = Connect-DATIntuneGraphClientCredential -TenantId $tenantId -AppId $appId -ClientSecret $appSecret
            if (-not $authResult.Success) {
                Write-Error "[Headless] Intune authentication failed: $($authResult.Error)"
                exit 1
            }
            Write-Host "[Headless] Intune authentication successful (expires: $($authResult.ExpiresOn))"

            # Pass the live token to the processing function
            $authStatus = Get-DATIntuneAuthStatus
            $processingParams['IntuneAuthToken'] = $authStatus.Token
        }
    }
    { $_ -in @('ConfigMgr', 'Configuration Manager') } {
        if ($config.ConfigMgr) {
            if ($config.ConfigMgr.SiteServer) { $processingParams['SiteServer'] = $config.ConfigMgr.SiteServer }
            if ($config.ConfigMgr.SiteCode) { $processingParams['SiteCode'] = $config.ConfigMgr.SiteCode }
            if ($config.ConfigMgr.DistributionPointGroups -and $config.ConfigMgr.DistributionPointGroups.Count -gt 0) {
                $processingParams['DistributionPointGroups'] = $config.ConfigMgr.DistributionPointGroups
            }
            if ($config.ConfigMgr.DistributionPoints -and $config.ConfigMgr.DistributionPoints.Count -gt 0) {
                $processingParams['DistributionPoints'] = $config.ConfigMgr.DistributionPoints
            }
            if ($config.ConfigMgr.DistributionPriority) { $processingParams['DistributionPriority'] = $config.ConfigMgr.DistributionPriority }
            if ($config.ConfigMgr.EnableBinaryDeltaReplication -eq $true) { $processingParams['EnableBinaryDeltaReplication'] = $true }
            if ($null -ne $config.ConfigMgr.ConsoleFolderID -and $config.ConfigMgr.ConsoleFolderID -ge 0) {
                $processingParams['ConsoleFolderID'] = [int]$config.ConfigMgr.ConsoleFolderID
            }
        }
    }
}

Write-Host "[Headless] Starting build at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "[Headless] Processing $($config.Models.Count) model(s)..."

$buildExitCode = 0

try {
    Start-DATModelProcessing @processingParams

    # Optionally generate the ConfigMgr XML Logic Package after a successful build (ConfigMgr only)
    if ($config.Platform -in @('ConfigMgr', 'Configuration Manager') -and $config.ConfigMgr -and
        ($config.ConfigMgr.GenerateXmlLogicPackage -eq $true)) {
        try {
            Write-Host "[Headless] Generating ConfigMgr XML Logic Package..."
            Write-DATLogEntry -Value "[Headless] Generating ConfigMgr XML Logic Package" -Severity 1
            $xmlLogicParams = @{
                SiteServer  = $config.ConfigMgr.SiteServer
                SiteCode    = $config.ConfigMgr.SiteCode
                PackagePath = $packagePath
            }
            if ($config.ConfigMgr.DistributionPriority) { $xmlLogicParams['Priority'] = $config.ConfigMgr.DistributionPriority }
            if ($config.ConfigMgr.CreateXmlLogicPackage -eq $true) {
                $xmlLogicParams['CreatePackage'] = $true
                if ($config.ConfigMgr.DistributionPointGroups -and $config.ConfigMgr.DistributionPointGroups.Count -gt 0) {
                    $xmlLogicParams['DistributionPointGroups'] = $config.ConfigMgr.DistributionPointGroups
                }
                if ($config.ConfigMgr.DistributionPoints -and $config.ConfigMgr.DistributionPoints.Count -gt 0) {
                    $xmlLogicParams['DistributionPoints'] = $config.ConfigMgr.DistributionPoints
                }
                if ($config.ConfigMgr.EnableBinaryDeltaReplication -eq $true) { $xmlLogicParams['EnableBinaryDeltaReplication'] = $true }
            }
            $xmlLogicResult = New-DATXmlLogicPackage @xmlLogicParams
            Write-Host "[Headless] XML Logic Package: $($xmlLogicResult.PackageCount) package(s), status '$($xmlLogicResult.Status)'$(if ($xmlLogicResult.PackageID) { " (package $($xmlLogicResult.PackageID))" })"
            Write-DATLogEntry -Value "[Headless] XML Logic Package generated: $($xmlLogicResult.PackageCount) package(s), status '$($xmlLogicResult.Status)', XmlPath '$($xmlLogicResult.XmlPath)'" -Severity 1
        } catch {
            Write-DATLogEntry -Value "[Headless] XML Logic Package generation failed: $($_.Exception.Message)" -Severity 3
            Write-Host "[Headless] XML Logic Package generation failed: $($_.Exception.Message)"
        }
    }

    # Submit telemetry summary (per-model reports are sent inside Start-DATModelProcessing)
    try {
        $finalReg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
        $fDriverPkgs = 0; $fBiosPkgs = 0
        if ($finalReg.CompletedDriverPackages) { [int]::TryParse($finalReg.CompletedDriverPackages, [ref]$fDriverPkgs) | Out-Null }
        if ($finalReg.CompletedBiosPackages) { [int]::TryParse($finalReg.CompletedBiosPackages, [ref]$fBiosPkgs) | Out-Null }
        Write-DATLogEntry -Value "[Headless] Submitting telemetry summary (drivers: $fDriverPkgs, BIOS: $fBiosPkgs, models: $($config.Models.Count), platform: $($config.Platform))" -Severity 1
        Send-DATSummaryReport -DriverPackagesCreated $fDriverPkgs `
            -BiosPackagesCreated $fBiosPkgs `
            -ModelsProcessed $config.Models.Count `
            -Platform $config.Platform `
            -ExecutionMode 'Scheduled Task'
        Write-DATLogEntry -Value "[Headless] Telemetry summary submitted successfully" -Severity 1
        Write-Host "[Headless] Telemetry summary submitted (drivers: $fDriverPkgs, BIOS: $fBiosPkgs)"
    } catch {
        Write-DATLogEntry -Value "[Headless] Telemetry summary failed: $($_.Exception.Message)" -Severity 3
        Write-Host "[Headless] Telemetry summary failed: $($_.Exception.Message)"
    }

    Write-DATLogEntry -Value "[Headless] Build completed successfully at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Severity 1
} catch {
    $buildExitCode = 1
    Write-Error "[Headless] Build failed: $_"
    try { Write-DATLogEntry -Value "[Headless] Build failed: $($_.Exception.Message)" -Severity 3 } catch { }
} finally {
    # Clean temporary storage in a finally block so it ALWAYS runs -- on success AND when the
    # build throws part-way through (#816). Previously this lived on the success path inside the
    # try, so any terminating error (made more likely by $ErrorActionPreference = 'Stop') jumped
    # straight to the catch and left the temp folder full. Honours the "Clean temporary storage
    # on exit" setting; defaults to enabled when the config omits the field.
    $cleanEnabled  = [bool]$config.CleanTempOnExit
    $storageHasPath = -not [string]::IsNullOrWhiteSpace($storagePath)
    $storageExists  = $storageHasPath -and (Test-Path $storagePath)
    Write-DATLogEntry -Value "[Headless] Cleanup check -- CleanTempOnExit=$cleanEnabled, StoragePath='$storagePath', Exists=$storageExists" -Severity 1
    Write-Host "[Headless] Cleanup check -- CleanTempOnExit=$cleanEnabled, StoragePath='$storagePath', Exists=$storageExists"

    if ($cleanEnabled -and $storageHasPath -and $storageExists) {
        Write-Host "[Headless] Cleaning temporary storage: $storagePath"
        Write-DATLogEntry -Value "[Headless] Cleaning temporary storage: $storagePath" -Severity 1

        # Log exactly what is present in the temp folder before we start removing it, so the
        # log shows which paths are being targeted (and what is left behind afterwards).
        $preItems = @(Get-ChildItem -Path $storagePath -Force -ErrorAction SilentlyContinue)
        Write-DATLogEntry -Value "[Headless] Cleanup: $($preItems.Count) item(s) found under '$storagePath'" -Severity 1
        Write-Host "[Headless] Cleanup: $($preItems.Count) item(s) found under '$storagePath'"
        foreach ($pi in $preItems) {
            Write-DATLogEntry -Value "[Headless] Cleanup target: $($pi.FullName)" -Severity 1
            Write-Host "[Headless] Cleanup target: $($pi.FullName)"
        }

        # Release file locks before deletion -- this is the step the headless path was missing
        # (#816). Driver/BIOS packaging leaves DISM/dismhost holding handles (and sometimes a
        # WIM still mounted) inside the temp folder; Remove-Item then fails on those folders and
        # only the unlocked top-level catalog files are removed, leaving the bulk on disk. The
        # UI shutdown handler already does this, which is why the GUI cleaned up correctly.

        # 0. Release in-process .NET file handles. Headless runs WIM capture and hash streams in
        #    THIS process (the UI cleans at app exit, long after its build runspace is disposed),
        #    so force a GC + finalizer pass to close any lingering handles before deletion.
        [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers(); [System.GC]::Collect()

        # 1. Kill orphaned DISM/dismhost processes that may hold handles in the temp folder
        $orphanProcs = @()
        foreach ($procName in @('dismhost', 'dism')) {
            $orphanProcs += @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
        }
        if ($orphanProcs.Count -gt 0) {
            Write-DATLogEntry -Value "[Headless] Cleanup: Stopping $($orphanProcs.Count) orphaned DISM process(es) before temp removal" -Severity 1
            foreach ($proc in $orphanProcs) {
                try { $proc.Kill() } catch { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
            }
        }

        # 2. Discard any stale WIM mount registry entries and run DISM image cleanup so a
        #    left-over mounted image (e.g. after an aborted build) releases its directory lock.
        $dismMountKey = 'HKLM:\SOFTWARE\Microsoft\WIMMount\Mounted Images'
        $hasMountedImages = (Test-Path $dismMountKey) -and
            @(Get-ChildItem $dismMountKey -ErrorAction SilentlyContinue).Count -gt 0
        if ($hasMountedImages) {
            Write-DATLogEntry -Value "[Headless] Cleanup: Clearing stale WIM mount registry entries" -Severity 1
            Get-ChildItem $dismMountKey -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            try {
                $dismClean = Start-Process -FilePath "$env:SystemRoot\System32\dism.exe" `
                    -ArgumentList '/Cleanup-Wim' -WindowStyle Hidden -PassThru
                $dismClean.WaitForExit(10000)
                if (-not $dismClean.HasExited) { $dismClean.Kill() }
            } catch {
                Write-DATLogEntry -Value "[Headless] Warning: DISM /Cleanup-Wim failed: $($_.Exception.Message)" -Severity 2
            }
        }

        # 3. Remove the temp content over several passes. Killed dismhost processes and released
        #    handles can take a moment to settle, so retry locked items with a GC + short pause
        #    between passes rather than giving up after a single retry.
        $removeTempContent = {
            $remaining = @(Get-ChildItem -Path $storagePath -Force -ErrorAction SilentlyContinue)
            $failed = @()
            foreach ($item in $remaining) {
                try {
                    Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                    Write-DATLogEntry -Value "[Headless] Cleanup: Removed $($item.FullName)" -Severity 1
                } catch {
                    $failed += $item
                    Write-DATLogEntry -Value "[Headless] Warning: Cleanup failed for $($item.FullName): $($_.Exception.Message)" -Severity 2
                }
            }
            return $failed
        }

        $stillFailed = @()
        for ($pass = 1; $pass -le 4; $pass++) {
            $stillFailed = @(& $removeTempContent)
            if ($stillFailed.Count -eq 0) { break }
            if ($pass -lt 4) {
                Write-DATLogEntry -Value "[Headless] Cleanup: $($stillFailed.Count) item(s) still locked after pass $pass -- retrying" -Severity 2
                [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
                Start-Sleep -Milliseconds 750
            }
        }

        if ($stillFailed.Count -gt 0) {
            Write-DATLogEntry -Value "[Headless] Warning: Temporary storage cleanup incomplete -- $($stillFailed.Count) item(s) could not be removed (still in use): $storagePath" -Severity 3
            Write-Host "[Headless] Warning: $($stillFailed.Count) temp item(s) could not be removed (still in use)."
            foreach ($sf in $stillFailed) {
                Write-DATLogEntry -Value "[Headless] Cleanup remaining: $($sf.FullName)" -Severity 3
                Write-Host "[Headless] Cleanup remaining: $($sf.FullName)"
            }
        } else {
            Write-DATLogEntry -Value "[Headless] Temporary storage cleanup finished: $storagePath" -Severity 1
            Write-Host "[Headless] Temporary storage cleanup finished: $storagePath"
        }
    } else {
        $skipReason = if (-not $cleanEnabled) {
            'CleanTempOnExit is disabled'
        } elseif (-not $storageHasPath) {
            'storage path is empty'
        } elseif (-not $storageExists) {
            "storage path does not exist ('$storagePath')"
        } else {
            'unknown reason'
        }
        Write-DATLogEntry -Value "[Headless] Temporary storage retained -- $skipReason" -Severity 2
        Write-Host "[Headless] Temporary storage retained -- $skipReason"
    }

    # Self-cleanup: remove the scheduled task if it was a once-off run
    try {
        $task = Get-ScheduledTask -TaskPath '\Driver Automation Tool\' -TaskName 'Scheduled Package Build' -ErrorAction SilentlyContinue
        if ($task -and $task.Triggers.Count -gt 0) {
            $isOnce = $task.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskTimeTrigger' }
            if ($isOnce) {
                Unregister-ScheduledTask -TaskPath '\Driver Automation Tool\' -TaskName 'Scheduled Package Build' -Confirm:$false
                Write-Host "[Headless] Once-off scheduled task removed after completion."
            }
        }
    } catch {
        Write-Host "[Headless] Warning: Could not clean up scheduled task: $($_.Exception.Message)"
    }
}

exit $buildExitCode
