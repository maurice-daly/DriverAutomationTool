<#
    Driver Automation Tool - BIOS Install Script
    Author: Maurice Daly
    Organization: MSEndpointMgr
    Copyright: (c) Maurice Daly. All rights reserved.
    OEM: {{OEM}}
    Model: {{Model}}
    OS: {{OS}}
    Version: {{Version}}
    Generated: {{Generated}}

    Prerequisites:
    - The packaging pipeline must pre-extract HP SoftPaqs and Lenovo self-extracting
      archives before WIM capture so the internal flash utilities (HPFirmwareUpdRec64.exe,
      winuptp.exe, etc.) are discoverable after WIM extraction.
    - Dell BIOS executables are self-contained updaters run directly with /s /l /p switches.
      Flash64W.exe is NOT used (it is a WinPE-only wrapper).
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

    $earlyLog = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\DriverAutomationTool-BIOS.log'

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

$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\DriverAutomationTool-BIOS.log"

function Write-CMTraceLog {
    param (
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('1','2','3')][string]$Severity = '1',
        [string]$Component = 'DriverAutomationTool-BIOS'
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

function Get-BIOSPasswordFromRegistry {
    <#
    .SYNOPSIS
        Retrieves and decrypts a BIOS password from the registry.
        The password is stored as a DPAPI-encrypted SecureString blob (machine-scope),
        set by Set-DATBIOSPassword or the Intune proactive remediation script.
        Decryption only succeeds when running as SYSTEM on the same machine that encrypted it.
    #>
    $regPath = 'HKLM:\SOFTWARE\DriverAutomationTool\BIOS'
    try {
        $encryptedBlob = (Get-ItemProperty -Path $regPath -Name 'Password' -ErrorAction SilentlyContinue).Password
        if ([string]::IsNullOrEmpty($encryptedBlob)) {
            Write-CMTraceLog "No BIOS password configured in registry -- proceeding without password"
            return $null
        }

        $secureString = ConvertTo-SecureString -String $encryptedBlob -ErrorAction Stop
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
        try {
            $plaintext = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }

        Write-CMTraceLog "BIOS password decrypted successfully from registry"
        return $plaintext
    } catch {
        Write-CMTraceLog "WARNING: Failed to decrypt BIOS password -- $($_.Exception.Message). Proceeding without password." -Severity 2
        return $null
    }
}

function Invoke-BIOSFlashUtility {
    <#
    .SYNOPSIS
        Executes a BIOS flash utility and captures output for logging.
    #>
    param (
        [Parameter(Mandatory)][string]$FilePath,
        [string]$Arguments,
        [int]$TimeoutSeconds = 600
    )

    Write-CMTraceLog "Executing: $FilePath $Arguments"

    $stdOut = Join-Path $env:TEMP "bios_stdout.txt"
    $stdErr = Join-Path $env:TEMP "bios_stderr.txt"

    $processParams = @{
        FilePath               = $FilePath
        NoNewWindow            = $true
        Wait                   = $true
        PassThru               = $true
        RedirectStandardOutput = $stdOut
        RedirectStandardError  = $stdErr
    }
    if (-not [string]::IsNullOrEmpty($Arguments)) {
        $processParams['ArgumentList'] = $Arguments
    }

    try {
        $process = Start-Process @processParams -ErrorAction Stop
    } catch {
        Write-CMTraceLog "ERROR: Failed to launch BIOS flash utility '$FilePath' -- $($_.Exception.Message)" -Severity 3
        return -1
    }

    if (Test-Path $stdOut) {
        $output = Get-Content $stdOut -ErrorAction SilentlyContinue
        foreach ($line in $output) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { Write-CMTraceLog "BIOS Flash: $line" }
        }
        Remove-Item $stdOut -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $stdErr) {
        $errOutput = Get-Content $stdErr -ErrorAction SilentlyContinue
        foreach ($line in $errOutput) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { Write-CMTraceLog "BIOS Flash Error: $line" -Severity 2 }
        }
        Remove-Item $stdErr -Force -ErrorAction SilentlyContinue
    }

    Write-CMTraceLog "BIOS flash utility exit code: $($process.ExitCode)"
    return $process.ExitCode
}

function Suspend-BitLockerForReboot {
    <#
    .SYNOPSIS
        Suspends BitLocker on the OS drive for one reboot cycle to allow BIOS flashing.
    #>
    try {
        $blv = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
        if ($blv -and $blv.ProtectionStatus -eq 'On') {
            Write-CMTraceLog "BitLocker is enabled on $($env:SystemDrive) -- suspending for 1 reboot cycle"
            Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 -ErrorAction Stop
            $script:BitLockerSuspended = $true
            Write-CMTraceLog "BitLocker suspended successfully"
        } else {
            Write-CMTraceLog "BitLocker is not enabled on $($env:SystemDrive) -- no action needed"
        }
    } catch {
        Write-CMTraceLog "WARNING: Failed to suspend BitLocker: $($_.Exception.Message)" -Severity 2
        Write-CMTraceLog "BIOS update will proceed -- flash utility may handle BitLocker on its own" -Severity 2
    }
}

function Resume-BitLockerProtection {
    <#
    .SYNOPSIS
        Re-enables BitLocker protection after a failed BIOS flash to avoid leaving the drive unprotected.
    #>
    try {
        $blv = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
        if ($blv -and $blv.ProtectionStatus -eq 'Off') {
            Write-CMTraceLog "Re-enabling BitLocker protection after failed BIOS flash"
            Resume-BitLocker -MountPoint $env:SystemDrive -ErrorAction Stop
            Write-CMTraceLog "BitLocker protection re-enabled successfully"
        }
    } catch {
        Write-CMTraceLog "WARNING: Failed to re-enable BitLocker: $($_.Exception.Message)" -Severity 2
    }
}

function Compare-BIOSVersion {
    <#
    .SYNOPSIS
        Compares the current installed BIOS version against the available version.
        Returns $true if the available version is newer (update needed).
    #>
    param (
        [Parameter(Mandatory)][string]$AvailableBIOSVersion,
        [Parameter(Mandatory)][string]$Manufacturer
    )

    $currentBIOS = $null
    try {
        $currentBIOS = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
    } catch {
        Write-CMTraceLog "ERROR: Failed to query Win32_BIOS via WMI -- $($_.Exception.Message)" -Severity 3
        return $true  # Proceed with update if we cannot determine current version
    }
    $currentVersion = $currentBIOS.SMBIOSBIOSVersion.Trim()

    Write-CMTraceLog "Current BIOS version: $currentVersion"
    Write-CMTraceLog "Available BIOS version: $AvailableBIOSVersion"

    switch -Wildcard ($Manufacturer) {
        '*Dell*' {
            try {
                # Validate that both versions are in x.y.z format before comparing
                $availableIsVersion = $AvailableBIOSVersion -match '^\d+(\.\d+){1,3}$'
                $currentIsVersion = $currentVersion -like '*.*.*'

                if ($currentIsVersion -and $availableIsVersion) {
                    # x.y.z format -- use System.Version comparison
                    if ([System.Version]$AvailableBIOSVersion -gt [System.Version]$currentVersion) {
                        Write-CMTraceLog "Dell: Newer BIOS available ($AvailableBIOSVersion > $currentVersion)"
                        return $true
                    }
                } elseif ($currentVersion -like 'A*') {
                    # Legacy Axx format
                    if ($availableIsVersion) {
                        # Moving from Axx to x.y.z -- treat as upgrade
                        Write-CMTraceLog "Dell: Format change detected (A-series to versioned) -- update available"
                        return $true
                    } elseif ($AvailableBIOSVersion -gt $currentVersion) {
                        Write-CMTraceLog "Dell: Newer BIOS available ($AvailableBIOSVersion > $currentVersion)"
                        return $true
                    }
                } else {
                    # Available version is a DAT package date stamp (ddMMyyyy) -- cannot compare
                    Write-CMTraceLog "Dell: Package version '$AvailableBIOSVersion' is not a BIOS version -- skipping comparison, proceeding with update" -Severity 2
                    return $true
                }
            } catch {
                Write-CMTraceLog "WARNING: Dell BIOS version comparison failed -- $($_.Exception.Message). Proceeding with update." -Severity 2
                return $true
            }
        }
        '*Lenovo*' {
            try {
                # Lenovo uses BIOS release dates in yyyyMMdd or ddMMyyyy format
                $currentReleaseDate = $currentBIOS.ReleaseDate.ToString('yyyyMMdd')
                Write-CMTraceLog "Lenovo: Current BIOS release date: $currentReleaseDate"
                Write-CMTraceLog "Lenovo: Available BIOS version: $AvailableBIOSVersion"

                # Compare version strings -- Lenovo typically embeds date or incremental version
                if ($AvailableBIOSVersion -gt $currentVersion) {
                    Write-CMTraceLog "Lenovo: Newer BIOS available"
                    return $true
                }
            } catch {
                Write-CMTraceLog "WARNING: Lenovo BIOS version comparison failed -- $($_.Exception.Message). Proceeding with update." -Severity 2
                return $true
            }
        }
        '*HP*' {
            try {
                $AvailableBIOSVersion = $AvailableBIOSVersion.TrimEnd('.').Split(' ')[0]

                switch -Wildcard ($currentVersion) {
                    '*ver*' {
                        # Older HP format: "68xxx Ver. F.xx"
                        if ($currentVersion -match '\.F\.\d+$') {
                            $parsedCurrent = ($currentVersion -split 'Ver\.')[1].Trim()
                            if ([int]($AvailableBIOSVersion.TrimStart('F.')) -gt [int]($parsedCurrent.TrimStart('F.'))) {
                                Write-CMTraceLog "HP: Newer BIOS available (F-series format)"
                                return $true
                            }
                        } else {
                            $parsedCurrent = [System.Version](($currentVersion).TrimStart($currentVersion.Split('.')[0]).TrimStart('.').Trim().Split(' ')[0])
                            if ([System.Version]$AvailableBIOSVersion -gt $parsedCurrent) {
                                Write-CMTraceLog "HP: Newer BIOS available (versioned format)"
                                return $true
                            }
                        }
                    }
                    default {
                        # Newer HP format: Major.Minor from SystemBiosMajorVersion/SystemBiosMinorVersion
                        $currentFormatted = "$($currentBIOS.SystemBiosMajorVersion).$($currentBIOS.SystemBiosMinorVersion)"
                        if ([System.Version]$AvailableBIOSVersion -gt [System.Version]$currentFormatted) {
                            Write-CMTraceLog "HP: Newer BIOS available ($AvailableBIOSVersion > $currentFormatted)"
                            return $true
                        }
                    }
                }
            } catch {
                Write-CMTraceLog "WARNING: HP BIOS version comparison failed -- $($_.Exception.Message). Proceeding with update." -Severity 2
                return $true
            }
        }
        '*Microsoft*' {
            try {
                # Surface firmware -- version comparison
                if ([System.Version]$AvailableBIOSVersion -gt [System.Version]$currentVersion) {
                    Write-CMTraceLog "Microsoft: Newer firmware available ($AvailableBIOSVersion > $currentVersion)"
                    return $true
                }
            } catch {
                Write-CMTraceLog "WARNING: Microsoft BIOS version comparison failed -- $($_.Exception.Message). Proceeding with update." -Severity 2
                return $true
            }
        }
        default {
            Write-CMTraceLog "Unknown manufacturer '$Manufacturer' -- skipping version comparison, proceeding with update" -Severity 2
            return $true
        }
    }

    Write-CMTraceLog "BIOS is already up to date -- no update required"
    return $false
}
{{TOAST_FUNCTIONS}}
try {
    Write-CMTraceLog "=========================================="
    if ($WhatIf) { Write-CMTraceLog "*** WHATIF MODE -- no BIOS changes will be applied ***" -Severity 2 }
    Write-CMTraceLog "Driver Automation Tool - BIOS Install Starting"
    Write-CMTraceLog "OEM: {{OEM}} | Model: {{Model}}"
    Write-CMTraceLog "OS: {{OS}} | Package Version: {{Version}}"
    Write-CMTraceLog "Script Generated: {{Generated}}"
    Write-CMTraceLog "=========================================="

    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $WimFile = Join-Path $ScriptDir "DriverPackage.wim"
    $ExtractPath = Join-Path $env:ProgramData "DriverAutomationTool\Extract"
    $VersionRegPath = 'HKLM:\SOFTWARE\DriverAutomationTool\BIOS\{{OEM}}\{{Model}}'
    $Manufacturer = '{{OEM}}'

    Write-CMTraceLog "Script directory: $ScriptDir"
    Write-CMTraceLog "WIM file path: $WimFile"
    Write-CMTraceLog "Extract target: $ExtractPath"
    Write-CMTraceLog "Version registry path: $VersionRegPath"
    Write-CMTraceLog "Manufacturer: $Manufacturer"

    if (-not (Test-Path $WimFile)) {
        Write-CMTraceLog "ERROR: WIM file not found at $WimFile" -Severity 3
        exit 1
    }

    $wimSize = [math]::Round((Get-Item $WimFile).Length / 1MB, 2)
    Write-CMTraceLog "WIM file size: $wimSize MB"

    # -- BIOS Version Check ------------------------------------------------------
    # Compare versions BEFORE prompting the user -- no point showing a toast if
    # the BIOS is already current.
    Write-CMTraceLog "Performing BIOS version comparison..."
    $updateNeeded = Compare-BIOSVersion -AvailableBIOSVersion '{{Version}}' -Manufacturer $Manufacturer

    if (-not $updateNeeded) {
        Write-CMTraceLog "BIOS is current -- no update will be applied"

        # Write version marker to registry so detection script sees the package as installed
        if (-not (Test-Path $VersionRegPath)) {
            New-Item -Path $VersionRegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $VersionRegPath -Name 'Version' -Value '{{Version}}' -Force
        Set-ItemProperty -Path $VersionRegPath -Name 'InstalledDate' -Value (Get-Date -Format 'o') -Force
        Set-ItemProperty -Path $VersionRegPath -Name 'OS' -Value '{{OS}}' -Force
        Write-CMTraceLog "Version marker written to registry (already current): $VersionRegPath"

        Write-CMTraceLog "=========================================="
        Write-CMTraceLog "BIOS update skipped -- already up to date"
        Write-CMTraceLog "=========================================="
        exit 0
    }

    # -- Toast Notification Gate (only reached when an update IS needed) ----------
{{TOAST_BLOCK}}

    # -- Extract WIM -------------------------------------------------------------
    if (Test-Path $ExtractPath) {
        Write-CMTraceLog "Removing previous BIOS extraction at $ExtractPath"
        Remove-Item -Path $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -Path $ExtractPath -ItemType Directory -Force | Out-Null
    Write-CMTraceLog "Created extraction directory: $ExtractPath"

    # Extract WIM contents directly using Expand-WindowsImage (DISM /Apply-Image)
    # This avoids mounting entirely, bypassing WOF overlay issues where
    # WIM-mounted files have FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS causing
    # both Copy-Item and robocopy to fail with error 4350 / 0x10FE
    try {
        Write-CMTraceLog "Extracting BIOS package WIM directly to: $ExtractPath"
        Expand-WindowsImage -ImagePath $WimFile -ApplyPath $ExtractPath -Index 1 -ErrorAction Stop
        Write-CMTraceLog "WIM extraction completed successfully"
    } catch [System.Exception] {
        Write-CMTraceLog "ERROR: Failed to extract BIOS package WIM file. Error: $($_.Exception.Message)" -Severity 3
        exit 1
    }

    $extractedFiles = (Get-ChildItem -Path $ExtractPath -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-CMTraceLog "WIM extraction complete. Files extracted: $extractedFiles"

    # -- Suspend BitLocker -------------------------------------------------------
    $script:BitLockerSuspended = $false
    $script:FlashSucceeded = $false
    $flashExitCode = $null

    if ($WhatIf) {
        Write-CMTraceLog "WHATIF: Would suspend BitLocker for 1 reboot cycle" -Severity 2
    } else {
        Suspend-BitLockerForReboot
    }

    # -- Retrieve BIOS Password (if configured) ---------------------------------
    $biosPassword = Get-BIOSPasswordFromRegistry

    # -- Manufacturer-Specific BIOS Flash ----------------------------------------

    switch -Wildcard ($Manufacturer) {

        # -- Dell ----------------------------------------------------------------
        # Dell BIOS downloads are self-contained executables (e.g. Latitude_5x40_1.25.0.exe).
        # They are run directly -- Flash64W.exe is a WinPE-only wrapper and is NOT used here.
        # Switches: /s = silent, /l=<log> = log file, /p=<pwd> = BIOS password
        '*Dell*' {
            Write-CMTraceLog "Dell BIOS update detected -- searching for BIOS executable"

            # Dell BIOS packages contain a single self-contained updater executable
            $allExes = @(Get-ChildItem -Path $ExtractPath -Recurse -Filter "*.exe" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'Flash64W.exe' })

            if ($allExes.Count -eq 1) {
                $biosExe = $allExes[0]
            } elseif ($allExes.Count -gt 1) {
                # Multiple exes -- pick the largest (the BIOS updater is typically the biggest file)
                $biosExe = $allExes | Sort-Object Length -Descending | Select-Object -First 1
                Write-CMTraceLog "Dell: Multiple executables found -- using largest as BIOS updater: $($biosExe.Name) ($([math]::Round($biosExe.Length / 1MB, 2)) MB)" -Severity 2
            } else {
                $biosExe = $null
            }

            if (-not $biosExe) {
                Write-CMTraceLog "ERROR: No Dell BIOS executable found in extracted content" -Severity 3
                exit 1
            }

            Write-CMTraceLog "Dell BIOS executable found: $($biosExe.FullName)"

            # -- AC power check -- Dell BIOS updaters refuse to flash on battery (exit code 10) --
            if (-not $WhatIf) {
                try {
                    $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($battery) {
                        # BatteryStatus 2 = AC power connected
                        if ($battery.BatteryStatus -ne 2) {
                            Write-CMTraceLog "AC power adapter not detected (BatteryStatus=$($battery.BatteryStatus)). Dell BIOS updates require AC power -- will retry on next Intune cycle." -Severity 2
                            exit 1618  # ERROR_INSTALL_ALREADY_RUNNING -- tells Intune to retry
                        }
                        Write-CMTraceLog "AC power confirmed (BatteryStatus=$($battery.BatteryStatus))"
                    } else {
                        Write-CMTraceLog "No battery detected -- assuming desktop, skipping AC power check"
                    }
                } catch {
                    Write-CMTraceLog "WARNING: Could not check AC power status -- $($_.Exception.Message). Proceeding with flash." -Severity 2
                }
            }

            # Build arguments: /s = silent, /l = log output
            $dellLogFile = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\DellBIOSFlash.log'
            $flashArgs = "/s /l=$dellLogFile"
            if (-not [string]::IsNullOrEmpty($biosPassword)) {
                $flashArgs += " /p=$biosPassword"
                Write-CMTraceLog "BIOS password will be applied to flash command"
            }

            if ($WhatIf) {
                Write-CMTraceLog "WHATIF: Would execute Dell BIOS update: $($biosExe.FullName) $flashArgs" -Severity 2
                $flashExitCode = 0
            } else {
                $flashExitCode = Invoke-BIOSFlashUtility -FilePath $biosExe.FullName -Arguments $flashArgs
            }

            # Dell exit codes:
            #   0 = success (no reboot needed)
            #   1 = success (soft reboot required)
            #   2 = success (hard reboot required)
            #   6 = already up to date (treat as success)
            #  10 = AC power not detected (should be pre-empted by the check above, but handle defensively)
            if ($flashExitCode -in @(0, 1, 2, 6)) {
                Write-CMTraceLog "Dell BIOS update completed successfully (exit code: $flashExitCode)"
            } elseif ($flashExitCode -eq 10) {
                Write-CMTraceLog "Dell BIOS update returned exit code 10 -- AC power adapter not connected. Will retry on next Intune cycle." -Severity 2
                exit 1618  # ERROR_INSTALL_ALREADY_RUNNING -- tells Intune to retry
            } else {
                Write-CMTraceLog "ERROR: Dell BIOS update failed with exit code: $flashExitCode" -Severity 3
                exit 1
            }
        }

        # -- HP / Hewlett-Packard ------------------------------------------------
        '*HP*' {
            Write-CMTraceLog "HP BIOS update detected -- searching for flash utility"

            # HP uses HPFirmwareUpdRec64.exe or HPBIOSUPDREC64.exe
            $flashUtil = Get-ChildItem -Path $ExtractPath -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^(HPFirmwareUpdRec64|HPBIOSUPDREC64|HPQFlash64)\.exe$' } |
                Select-Object -First 1

            if (-not $flashUtil) {
                # Fallback: locate any HP BIOS-related exe
                $flashUtil = Get-ChildItem -Path $ExtractPath -Recurse -Filter "*.exe" -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match 'HP|BIOS|Firmware' } | Select-Object -First 1
            }

            if (-not $flashUtil) {
                Write-CMTraceLog "ERROR: No HP BIOS flash utility found in extracted content" -Severity 3
                exit 1
            }

            Write-CMTraceLog "HP flash utility found: $($flashUtil.FullName)"

            # Build arguments: -s = silent, -r = do not reboot, -b = suspend BitLocker if needed
            # -f = folder containing firmware update files
            $flashArgs = "-s -r -b -f`"$($flashUtil.DirectoryName)`""

            # HP flash utilities require a BIN password file (not a plaintext password).
            # If a pre-existing BIN file was bundled with the package, use it directly.
            # Otherwise, generate one at runtime using Write-HPFirmwarePasswordFile from HP CMSL.
            $hpPasswordBinFile = $null
            $hpBundledBinFile = Join-Path $ScriptDir 'HPPasswordFile.bin'

            if (Test-Path $hpBundledBinFile) {
                # Pre-existing BIN file was provided by the admin and embedded in the package
                $hpPasswordBinFile = $hpBundledBinFile
                Write-CMTraceLog "Using bundled HP password BIN file: $hpPasswordBinFile"
                $flashArgs += " -p`"$hpPasswordBinFile`""
                Write-CMTraceLog "BIOS password BIN file will be applied to flash command"
            } elseif (-not [string]::IsNullOrEmpty($biosPassword)) {
                $hpPasswordBinFile = Join-Path $env:TEMP 'DAT_BIOSPassword.bin'
                try {
                    # Check for HP CMSL module availability
                    if (-not (Get-Command -Name 'Write-HPFirmwarePasswordFile' -ErrorAction SilentlyContinue)) {
                        Write-CMTraceLog "HP CMSL module not found -- attempting to install HPCMSL" -Severity 2
                        Install-Module -Name 'HPCMSL' -Force -AcceptLicense -Scope AllUsers -ErrorAction Stop
                        Import-Module -Name 'HPCMSL' -ErrorAction Stop
                        Write-CMTraceLog "HPCMSL module installed and imported successfully"
                    }

                    Write-CMTraceLog "Generating HP firmware password BIN file"
                    Write-HPFirmwarePasswordFile -Password $biosPassword -OutputFile $hpPasswordBinFile -ErrorAction Stop
                    Write-CMTraceLog "HP password BIN file created at: $hpPasswordBinFile"

                    $flashArgs += " -p`"$hpPasswordBinFile`""
                    Write-CMTraceLog "BIOS password BIN file will be applied to flash command"
                } catch {
                    Write-CMTraceLog "ERROR: Failed to generate HP firmware password BIN file -- $($_.Exception.Message)" -Severity 3
                    # Clean up partial file if it exists
                    if (Test-Path $hpPasswordBinFile) { Remove-Item $hpPasswordBinFile -Force -ErrorAction SilentlyContinue }
                    exit 1
                }
            }

            if ($WhatIf) {
                Write-CMTraceLog "WHATIF: Would execute HP BIOS flash: $($flashUtil.FullName) $flashArgs" -Severity 2
                $flashExitCode = 0
            } else {
                $flashExitCode = Invoke-BIOSFlashUtility -FilePath $flashUtil.FullName -Arguments $flashArgs
            }

            # Clean up the password BIN file if it was generated at runtime (not the bundled one)
            if ($hpPasswordBinFile -and $hpPasswordBinFile -ne $hpBundledBinFile -and (Test-Path $hpPasswordBinFile)) {
                Remove-Item $hpPasswordBinFile -Force -ErrorAction SilentlyContinue
                Write-CMTraceLog "HP password BIN file cleaned up"
            }

            # HP exit codes: 0 = success, 3010 = success (reboot required)
            if ($flashExitCode -in @(0, 3010)) {
                Write-CMTraceLog "HP BIOS flash completed successfully (exit code: $flashExitCode)"
            } else {
                Write-CMTraceLog "ERROR: HP BIOS flash failed with exit code: $flashExitCode" -Severity 3
                exit 1
            }
        }

        # -- Lenovo --------------------------------------------------------------
        '*Lenovo*' {
            Write-CMTraceLog "Lenovo BIOS update detected -- searching for flash utility"

            # Lenovo ThinkPad uses WinUPTP64.exe (64-bit) or WinUPTP.exe (32-bit)
            $flashUtil = $null
            $flashType = $null

            if ([Environment]::Is64BitOperatingSystem) {
                $flashUtil = Get-ChildItem -Path $ExtractPath -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq 'WinUPTP64.exe' } | Select-Object -First 1
            }
            if (-not $flashUtil) {
                $flashUtil = Get-ChildItem -Path $ExtractPath -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq 'WinUPTP.exe' } | Select-Object -First 1
            }
            if ($flashUtil) { $flashType = 'WinUPTP' }

            # Lenovo ThinkCentre/ThinkStation use Flash64.cmd (64-bit) or Flash.cmd
            if (-not $flashUtil) {
                $flashCmd = $null
                if ([Environment]::Is64BitOperatingSystem) {
                    $flashCmd = Get-ChildItem -Path $ExtractPath -Recurse -Filter "Flash64.cmd" -File -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                }
                if (-not $flashCmd) {
                    $flashCmd = Get-ChildItem -Path $ExtractPath -Recurse -Filter "Flash.cmd" -File -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                }

                if ($flashCmd) {
                    $flashType = 'FlashCmd'
                    Write-CMTraceLog "Lenovo Flash.cmd found: $($flashCmd.FullName)"

                    # Flash.cmd switches: /quiet = silent, /sccm = SCCM/Intune mode, /ign = ignore errors
                    $cmdArgs = "/quiet /sccm /ign"
                    if (-not [string]::IsNullOrEmpty($biosPassword)) {
                        $cmdArgs += " /pass:$biosPassword"
                        Write-CMTraceLog "BIOS password will be applied to Flash.cmd command"
                    }

                    if ($WhatIf) {
                        Write-CMTraceLog "WHATIF: Would execute Lenovo Flash.cmd: $($flashCmd.FullName) $cmdArgs" -Severity 2
                        $flashExitCode = 0
                    } else {
                        $flashExitCode = Invoke-BIOSFlashUtility -FilePath "cmd.exe" -Arguments "/c `"$($flashCmd.FullName)`" $cmdArgs"
                    }

                    if ($flashExitCode -in @(0, 1)) {
                        Write-CMTraceLog "Lenovo BIOS flash (Flash.cmd) completed successfully (exit code: $flashExitCode)"
                    } else {
                        Write-CMTraceLog "ERROR: Lenovo BIOS flash (Flash.cmd) failed with exit code: $flashExitCode" -Severity 3
                        exit 1
                    }
                    break
                }

                # Fallback: any BIOS-related exe
                $flashUtil = Get-ChildItem -Path $ExtractPath -Recurse -Filter "*.exe" -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match 'Flash|BIOS|winuptp' } | Select-Object -First 1
                if ($flashUtil) { $flashType = 'WinUPTP' }
            }

            if (-not $flashUtil) {
                Write-CMTraceLog "ERROR: No Lenovo BIOS flash utility found in extracted content" -Severity 3
                exit 1
            }

            Write-CMTraceLog "Lenovo flash utility found: $($flashUtil.FullName) (type: $flashType)"

            # WinUPTP switches: /S = silent (capital S, forward slash per Lenovo documentation)
            $flashArgs = '/S'
            if (-not [string]::IsNullOrEmpty($biosPassword)) {
                $flashArgs += " /pass:$biosPassword"
                Write-CMTraceLog "BIOS password will be applied to flash command"
            }

            if ($WhatIf) {
                Write-CMTraceLog "WHATIF: Would execute Lenovo BIOS flash: $($flashUtil.FullName) $flashArgs" -Severity 2
                $flashExitCode = 0
            } else {
                $flashExitCode = Invoke-BIOSFlashUtility -FilePath $flashUtil.FullName -Arguments $flashArgs
            }

            # Lenovo exit codes: 0 = success, 1 = success (reboot required)
            if ($flashExitCode -in @(0, 1)) {
                Write-CMTraceLog "Lenovo BIOS flash completed successfully (exit code: $flashExitCode)"
            } else {
                Write-CMTraceLog "ERROR: Lenovo BIOS flash failed with exit code: $flashExitCode" -Severity 3
                exit 1
            }
        }

        # -- Microsoft (Surface) ------------------------------------------------
        '*Microsoft*' {
            Write-CMTraceLog "Microsoft Surface firmware update detected -- searching for MSI package"

            # Surface firmware is delivered as an MSI
            $msiFile = Get-ChildItem -Path $ExtractPath -Recurse -Filter "*.msi" -File -ErrorAction SilentlyContinue |
                Select-Object -First 1

            if (-not $msiFile) {
                Write-CMTraceLog "ERROR: No MSI firmware package found in extracted content" -Severity 3
                exit 1
            }

            Write-CMTraceLog "Surface firmware MSI found: $($msiFile.FullName)"

            $msiLog = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\DAT_SurfaceFirmware.log"
            $flashArgs = "/i `"$($msiFile.FullName)`" /quiet /norestart /l*v `"$msiLog`""

            if ($WhatIf) {
                Write-CMTraceLog "WHATIF: Would execute Surface firmware install: msiexec.exe $flashArgs" -Severity 2
                $flashExitCode = 0
            } else {
                $flashExitCode = Invoke-BIOSFlashUtility -FilePath "msiexec.exe" -Arguments $flashArgs
            }

            # MSI exit codes: 0 = success, 3010 = success (reboot required)
            if ($flashExitCode -in @(0, 3010)) {
                Write-CMTraceLog "Surface firmware install completed successfully (exit code: $flashExitCode)"
            } else {
                Write-CMTraceLog "ERROR: Surface firmware install failed with exit code: $flashExitCode" -Severity 3
                Write-CMTraceLog "MSI log available at: $msiLog" -Severity 2
                exit 1
            }
        }

        default {
            Write-CMTraceLog "ERROR: Unsupported manufacturer '$Manufacturer' for BIOS update" -Severity 3
            exit 1
        }
    }

    $script:FlashSucceeded = $true

    # -- Write version marker to registry for detection --------------------------------------
    if ($WhatIf) {
        Write-CMTraceLog "WHATIF: Would write version '{{Version}}' to registry at $VersionRegPath" -Severity 2
    } else {
        if (-not (Test-Path $VersionRegPath)) {
            New-Item -Path $VersionRegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $VersionRegPath -Name 'Version' -Value '{{Version}}' -Force
        Set-ItemProperty -Path $VersionRegPath -Name 'InstalledDate' -Value (Get-Date -Format 'o') -Force
        Set-ItemProperty -Path $VersionRegPath -Name 'OS' -Value '{{OS}}' -Force
        Write-CMTraceLog "Version marker written to registry: $VersionRegPath = {{Version}}"
    }

    # -- Clean up extracted files ----------------------------------------------------
    Write-CMTraceLog "BIOS update complete. Cleaning up extracted files..."
    Remove-Item -Path $ExtractPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-CMTraceLog "Cleanup complete."

{{STATUS_TOAST_BLOCK}}
    Write-CMTraceLog "=========================================="
    if ($WhatIf) {
        Write-CMTraceLog "WHATIF: BIOS update simulation completed -- no changes were made"
    } else {
        Write-CMTraceLog "BIOS firmware prestaged successfully"
        if ($flashExitCode -in @(2, 1, 3010)) {
            $RestartDelaySeconds = 180
            Write-CMTraceLog "Scheduling system restart in $RestartDelaySeconds seconds to apply BIOS update"
            shutdown.exe /r /t $RestartDelaySeconds /c "BIOS firmware update prestaged by Driver Automation Tool. Your system will restart in $RestartDelaySeconds seconds to apply the update. Please save your work." /d p:1:18
            Write-CMTraceLog "Restart scheduled -- shutdown.exe exit code: $LASTEXITCODE"
            Write-CMTraceLog "=========================================="
            exit 3010
        }
    }
    Write-CMTraceLog "=========================================="

    exit 0
}
catch {
    Write-CMTraceLog "FATAL ERROR: $($_.Exception.Message)" -Severity 3
    Write-CMTraceLog "Stack: $($_.ScriptStackTrace)" -Severity 3
{{STATUS_TOAST_ERROR_BLOCK}}
    exit 1
}
finally {
    # Re-enable BitLocker if it was suspended and the flash did not succeed
    if ($script:BitLockerSuspended -and -not $script:FlashSucceeded) {
        Resume-BitLockerProtection
    }

    # Clean up temp files that may have been left behind on any exit path
    foreach ($tmpFile in @("$env:TEMP\dism_stdout.txt", "$env:TEMP\dism_stderr.txt",
                           "$env:TEMP\robocopy_stdout.txt",
                           "$env:TEMP\bios_stdout.txt", "$env:TEMP\bios_stderr.txt")) {
        if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
    }
}
