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

    $earlyLog = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\DriverAutomationTool.log'

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

$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\DriverAutomationTool.log"

function Write-CMTraceLog {
    param (
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('1','2','3')][string]$Severity = '1',
        [string]$Component = 'DriverAutomationTool'
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
{{TOAST_FUNCTIONS}}
try {
    Write-CMTraceLog "=========================================="
    if ($WhatIf) { Write-CMTraceLog "*** WHATIF MODE -- no drivers will be installed ***" -Severity 2 }
    Write-CMTraceLog "Driver Automation Tool - Install Starting"
    Write-CMTraceLog "OEM: {{OEM}} | Model: {{Model}}"
    Write-CMTraceLog "OS: {{OS}} | Package Version: {{Version}}"
    Write-CMTraceLog "Script Generated: {{Generated}}"
    Write-CMTraceLog "=========================================="

    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
{{TOAST_BLOCK}}
    $WimFile = Join-Path $ScriptDir "DriverPackage.wim"
    $ExtractPath = Join-Path $env:ProgramData "DriverAutomationTool\Extract"
    $VersionRegPath = 'HKLM:\SOFTWARE\DriverAutomationTool\Drivers\{{OEM}}\{{Model}}'

    Write-CMTraceLog "Script directory: $ScriptDir"
    Write-CMTraceLog "WIM file path: $WimFile"
    Write-CMTraceLog "Extract target: $ExtractPath"
    Write-CMTraceLog "Version registry path: $VersionRegPath"

    if (-not (Test-Path $WimFile)) {
        Write-CMTraceLog "ERROR: WIM file not found at $WimFile" -Severity 3
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
    try {
        Write-CMTraceLog "Extracting driver package WIM directly to: $ExtractPath"
        Expand-WindowsImage -ImagePath $WimFile -ApplyPath $ExtractPath -Index 1 -ErrorAction Stop
        Write-CMTraceLog "WIM extraction completed successfully"
    } catch [System.Exception] {
        Write-CMTraceLog "ERROR: Failed to extract driver package WIM file. Error: $($_.Exception.Message)" -Severity 3
        exit 1
    }

    $extractedFiles = (Get-ChildItem -Path $ExtractPath -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-CMTraceLog "WIM extraction complete. Files extracted: $extractedFiles"

    # Find all INF files for driver installation
    $infFiles = Get-ChildItem -Path $ExtractPath -Recurse -Filter "*.inf" -File -ErrorAction SilentlyContinue
    $infCount = ($infFiles | Measure-Object).Count
    Write-CMTraceLog "Found $infCount INF driver files to process"

    if ($infCount -eq 0) {
        Write-CMTraceLog "WARNING: No INF files found in extracted drivers" -Severity 2
        exit 0
    }

    # Install drivers using PNPUtil
    # Use SysNative to bypass WoW64 file system redirection when the IME runs as 32-bit
    $sysNativePath = Join-Path $env:SystemRoot "SysNative\pnputil.exe"
    $system32Path  = Join-Path $env:SystemRoot "System32\pnputil.exe"
    $pnpUtilPath   = if (Test-Path $sysNativePath) { $sysNativePath } else { $system32Path }
    Write-CMTraceLog "PNPUtil path resolved to: $pnpUtilPath"
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

        # Known PNPUtil exit codes:
        #   0    = Success, no reboot required
        #   1    = Partial success / some drivers not added (treated as success)
        #   259  = ERROR_NO_MORE_ITEMS -- all drivers already staged/current (success)
        #   3010 = ERROR_SUCCESS_REBOOT_REQUIRED -- success, reboot needed
        # Anything else is a genuine failure.
        if ($pnpProcess.ExitCode -notin @(0, 1, 259, 3010)) {
            Write-CMTraceLog "ERROR: PNPUtil reported a failure (exit code $($pnpProcess.ExitCode))" -Severity 3
            exit 1
        }
        if ($pnpProcess.ExitCode -eq 3010) {
            Write-CMTraceLog "PNPUtil: reboot required to complete driver installation" -Severity 2
        }
        if ($pnpProcess.ExitCode -eq 259) {
            Write-CMTraceLog "PNPUtil: all drivers already staged -- no new drivers added"
        }
    }

    # Write version marker to registry for detection
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
