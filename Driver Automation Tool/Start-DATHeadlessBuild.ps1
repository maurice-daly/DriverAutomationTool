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
if ($config.ToastTimeoutAction -ne 'RemindMeLater') { $processingParams['ToastTimeoutAction'] = $config.ToastTimeoutAction }
if ($config.MaxDeferrals -gt 0) { $processingParams['MaxDeferrals'] = $config.MaxDeferrals }
if ($config.BIOSRestartDelayMinutes -gt 0) { $processingParams['RestartDelaySeconds'] = $config.BIOSRestartDelayMinutes * 60 }

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

try {
    Start-DATModelProcessing @processingParams

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

    exit 0
} catch {
    Write-Error "[Headless] Build failed: $_"
    exit 1
}
