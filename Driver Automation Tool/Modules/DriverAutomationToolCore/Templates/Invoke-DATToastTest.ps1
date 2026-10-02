<#
    Driver Automation Tool - Toast Notification Test Script
    Author: Maurice Daly
    Organization: MSEndpointMgr
    Copyright: (c) Maurice Daly. All rights reserved.
    Update type: {{UPDATE_TYPE}}
    Simulated outcome: {{SIMULATED_OUTCOME}}
    Platform: {{TARGET_PLATFORM}}
    Version: {{Version}}
    Generated: {{Generated}}

    Runs the toast notification gate and status toasts of a real {{UPDATE_TYPE}} package on any
    device, without installing drivers, flashing firmware or restarting. The gate and the status
    toast launcher are copied verbatim from the install script the tool generates with the same
    settings, so what the user sees here is what a real package shows. Every step the real package
    would take after the prompt is written to the log instead of being carried out.

    Deferral state is kept under HKLM:\SOFTWARE\DriverAutomationTool\ToastTest, never under the
    keys a real package reads. When a real package would exit 1618 (the user deferred, did not
    answer, or a BIOS device is on battery) the test exits 1618 too and is not detected, so Intune /
    ConfigMgr retries it as it would the real package. Otherwise it exits 0 once the flow has been
    walked through. Run with -Uninstall to remove the test state.
#>
param (
    [switch]$Uninstall
)

# --- 64-bit Relaunch Guard ---
# Same as the install scripts: registry writes from a 32-bit host would land in WOW6432Node.
if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
    Write-Warning "32-bit PowerShell detected -- relaunching under 64-bit PowerShell..."

    $earlyLog = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs\DriverAutomationTool-ToastTest.log'

    $scriptPath = $MyInvocation.MyCommand.Path
    if ([string]::IsNullOrEmpty($scriptPath)) {
        Write-Warning "ERROR: Cannot determine script path -- run with 'powershell.exe -File <script>'."
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [ERROR] 64-bit relaunch failed: script path is empty (run with -File parameter)" | Out-File -FilePath $earlyLog -Encoding UTF8 -Append
        exit 1
    }

    $relaunchPath = "$env:SystemRoot\SysNative\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $relaunchPath)) {
        Write-Warning "ERROR: 64-bit PowerShell not found at '$relaunchPath' -- cannot relaunch."
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [ERROR] 64-bit relaunch failed: SysNative path not accessible" | Out-File -FilePath $earlyLog -Encoding UTF8 -Append
        exit 1
    }

    $relaunchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$scriptPath`"")
    if ($Uninstall) { $relaunchArgs += '-Uninstall' }
    try {
        $proc = Start-Process -FilePath $relaunchPath -ArgumentList $relaunchArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
        exit $proc.ExitCode
    } catch {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [ERROR] 64-bit relaunch failed: $($_.Exception.Message)" | Out-File -FilePath $earlyLog -Encoding UTF8 -Append
        exit 1
    }
}

$LogFile = Join-Path $env:ProgramData "Microsoft\IntuneManagementExtension\Logs\DriverAutomationTool-ToastTest.log"

function Write-CMTraceLog {
    param (
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('1','2','3')][string]$Severity = '1',
        [string]$Component = 'DriverAutomationTool-ToastTest'
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $Time = Get-Date -Format "HH:mm:ss.fff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    $LogEntry = "<![LOG[$Message]LOG]!><time=""$Time+000"" date=""$Date"" component=""$Component"" context="""" type=""$Severity"" thread=""$PID"" file="""">"
    $LogDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8 -ErrorAction SilentlyContinue

    switch ($Severity) {
        '1' { Write-Host "[$Timestamp] [INFO] $Message" }
        '2' { Write-Host "[$Timestamp] [WARN] $Message" -ForegroundColor Yellow }
        '3' { Write-Host "[$Timestamp] [ERROR] $Message" -ForegroundColor Red }
    }
}

$TestUpdateType      = '{{UPDATE_TYPE}}'
$SimulatedOutcome    = '{{SIMULATED_OUTCOME}}'
$TestPackageVersion  = '{{Version}}'
$ToastEnabled        = {{TOAST_ENABLED}}
$SilentDuringAutopilot = {{SILENT_DURING_AUTOPILOT}}
$DisableRestart      = {{DISABLE_RESTART}}
$RestartDelaySeconds = {{RESTART_DELAY_SECONDS}}
$TestRegPath         = "HKLM:\SOFTWARE\DriverAutomationTool\ToastTest\$TestUpdateType"
# Must match the state key the gate was repointed at when this script was built.
$TestStatePath       = "$TestRegPath\GateState"

function Set-DATInstallStatus {
    # Stand-in for the install scripts' status writer, which the toast gate calls when the user
    # defers. The test never writes an install result; it logs what a real package would record.
    param (
        [Parameter(Mandatory)][string]$RegPath,
        [Parameter(Mandatory)][string]$Result,
        [int]$ToolExitCode = 0,
        [int]$ScriptExitCode = 0,
        [string]$Phase = '',
        [string]$ErrorMessage = ''
    )
    $detail = if (-not [string]::IsNullOrEmpty($ErrorMessage)) { " -- $ErrorMessage" } else { '' }
    Write-CMTraceLog "[Simulated] A real package would record LastResult=$Result (phase $Phase, exit code $ScriptExitCode) under $RegPath$detail"
}

function Set-DATToastTestResult {
    # The summary the detection rule and the administrator read. PackageVersion is only written
    # on a completed run, so a crashed or deferred test is not detected as installed.
    param ([System.Collections.IDictionary]$Values)
    try {
        if (-not (Test-Path $TestRegPath)) { New-Item -Path $TestRegPath -Force -ErrorAction Stop | Out-Null }
        foreach ($key in $Values.Keys) {
            Set-ItemProperty -Path $TestRegPath -Name $key -Value ([string]$Values[$key]) -Force -ErrorAction Stop
        }
    } catch {
        Write-CMTraceLog "WARNING: Failed to record the test result under $TestRegPath -- $($_.Exception.Message)" -Severity 2
    }
}

function Show-DATTestStatusToast {
    # Shows one of the staged status toasts through the real launcher and returns its outcome.
    param ([Parameter(Mandatory)][string]$ToastScriptName)
    if (-not $ToastEnabled) {
        Write-CMTraceLog "[StatusToast] Toasts are disabled in this build -- a real package would not show $ToastScriptName"
        return 'NotShown: toasts disabled'
    }
    Write-CMTraceLog "[StatusToast] Showing $ToastScriptName"
    Show-DATStatusToast -ToastScript (Join-Path $ScriptDir $ToastScriptName)
    return "$script:DATLastStatusToastOutcome"
}

function Test-DATTestPackageWim {
    # The real package expands DriverPackage.wim before it installs anything. The test package
    # carries a small WIM so the same expansion can be tried on the device; it is applied to a
    # test folder and removed again.
    $wimFile = Join-Path $ScriptDir 'DriverPackage.wim'
    if (-not (Test-Path $wimFile)) {
        Write-CMTraceLog "[Simulated] DriverPackage.wim is missing from the content -- a real package would fail here with exit code 1" -Severity 3
        return $false
    }
    $wimSizeKB = [math]::Round((Get-Item $wimFile).Length / 1KB, 1)
    Write-CMTraceLog "[WimCheck] DriverPackage.wim present ($wimSizeKB KB)"
    $testExtract = Join-Path $env:ProgramData 'DriverAutomationTool\ToastTest\Extract'
    try {
        if (Test-Path $testExtract) { Remove-Item -Path $testExtract -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -Path $testExtract -ItemType Directory -Force | Out-Null
        Expand-WindowsImage -ImagePath $wimFile -Index 1 -ApplyPath $testExtract -ErrorAction Stop | Out-Null
        $fileCount = @(Get-ChildItem -Path $testExtract -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-CMTraceLog "[WimCheck] Expanded the test WIM to $testExtract ($fileCount file(s)) -- WIM expansion works on this device"
        return $true
    } catch {
        Write-CMTraceLog "[WimCheck] Expanding the test WIM failed: $($_.Exception.Message) -- a real package would fail at the same step" -Severity 3
        return $false
    } finally {
        Remove-Item -Path $testExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}
{{TOAST_FUNCTIONS}}
function Invoke-DATTestToastGate {
    # The real package's toast gate. Two edits were made when this script was built: the gate's
    # deferral state lives under the ToastTest key, and 'exit 1618' became 'return 1618' so the
    # test can report the deferral instead of ending there. Dot-source it so the gate's variables
    # (the user's answer and why) stay readable afterwards.
{{TOAST_GATE}}
    return 0
}
{{PROGRESS_FUNCTIONS}}
function Invoke-DATTestInstallProgress {
    # The real package's install progress notification (when this build has it on), driven through
    # the steps a real install reports with simulated timings. Does nothing when it is off.
    param ([bool]$Failed)
    Start-DATInstallProgress -ToastScript (Join-Path $ScriptDir 'Show-ProgressToast.ps1')
    if (-not $script:DATProgress) { return }
    Write-CMTraceLog "[Simulated] Showing the install progress notification with simulated steps"
    Start-Sleep -Seconds 3
    if ($TestUpdateType -eq 'Drivers') {
        $simulatedDrivers = 40
        for ($i = 0; $i -le $simulatedDrivers; $i++) {
            Set-DATInstallProgress -Step 2 -Total $simulatedDrivers -Done $i
            Start-Sleep -Milliseconds 250
        }
        Set-DATInstallProgress -Step 3
        Start-Sleep -Seconds 2
    } else {
        Set-DATInstallProgress -Step 2
        Start-Sleep -Seconds 3
        Set-DATInstallProgress -Step 3
        Start-Sleep -Seconds 5
    }
    Complete-DATInstallProgress -Outcome $(if ($Failed) { 'Failed' } else { 'Success' })
}
{{PROVISIONING_FUNCTIONS}}
function Save-DATAutopilotSignalSnapshot {
    # Exports the registry values the Autopilot provisioning check reads, plus who owns the shell,
    # so the detection rule can be checked against what the device really had at this moment
    # (Phase 0 of docs/Autopilot.md). Kept locally under ProgramData; the newest 20 are kept.
    $snapshotDir = Join-Path $env:ProgramData 'DriverAutomationTool\ToastTest\AutopilotSignals'
    try {
        if (-not (Test-Path $snapshotDir)) { New-Item -Path $snapshotDir -ItemType Directory -Force -ErrorAction Stop | Out-Null }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
        $exports = @(@{ Key = 'HKLM\SOFTWARE\Microsoft\Windows\Autopilot\EnrollmentStatusTracking'; Name = 'EnrollmentStatusTracking' })
        foreach ($enrollment in @(Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue)) {
            if (Test-Path -LiteralPath "$($enrollment.PSPath)\FirstSync") {
                $exports += @{ Key = "HKLM\SOFTWARE\Microsoft\Enrollments\$($enrollment.PSChildName)\FirstSync"; Name = "FirstSync-$($enrollment.PSChildName)" }
            }
        }
        foreach ($export in $exports) {
            $file = Join-Path $snapshotDir "$stamp-$($export.Name).reg"
            & $regExe export $export.Key $file /y 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-CMTraceLog "[Autopilot] Signal snapshot: $file" }
            else { Write-CMTraceLog "[Autopilot] Signal snapshot: $($export.Key) not present" }
        }
        $owners = @(Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
            $owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction SilentlyContinue
            if ($owner -and $owner.ReturnValue -eq 0) { "$($owner.Domain)\$($owner.User)" }
        })
        Write-CMTraceLog "[Autopilot] Shell (explorer.exe) owner: $(if ($owners.Count -gt 0) { $owners -join ', ' } else { 'none running' })"
        Get-ChildItem -Path $snapshotDir -Filter '*.reg' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 20 | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {
        Write-CMTraceLog "[Autopilot] Could not save the signal snapshot: $($_.Exception.Message)" -Severity 2
    }
}

if ($Uninstall) {
    Write-CMTraceLog "Toast test uninstall -- removing $TestRegPath"
    Remove-Item -Path $TestRegPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $env:ProgramData 'DriverAutomationTool\ToastTest\AutopilotSignals') -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}

try {
    Write-CMTraceLog "=========================================="
    Write-CMTraceLog "Driver Automation Tool - Toast Notification Test ($TestUpdateType)"
    Write-CMTraceLog "*** TEST PACKAGE -- nothing is installed, flashed or restarted ***" -Severity 2
    Write-CMTraceLog "Test package version: $TestPackageVersion | Platform: {{TARGET_PLATFORM}} | Generated: {{Generated}}"
    Write-CMTraceLog "Simulated install outcome: $SimulatedOutcome"
    Write-CMTraceLog "=========================================="

    $deviceOEM = 'Unknown'
    $deviceModel = 'Unknown'
    try {
        $ctxCs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $ctxOs = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $deviceOEM = "$($ctxCs.Manufacturer)".Trim()
        $deviceModel = "$($ctxCs.Model)".Trim()
        Write-CMTraceLog "Device: $deviceOEM | Model: $deviceModel | SKU: $($ctxCs.SystemSKUNumber)"
        Write-CMTraceLog "OS: $($ctxOs.Caption) ($($ctxOs.Version)) | Build: $($ctxOs.BuildNumber)"
        Write-CMTraceLog "Computer: $env:COMPUTERNAME | Architecture: $env:PROCESSOR_ARCHITECTURE"
        Write-CMTraceLog "PowerShell: $($PSVersionTable.PSVersion) | 64-bit process: $([Environment]::Is64BitProcess) | Session: $([System.Diagnostics.Process]::GetCurrentProcess().SessionId)"
        Write-CMTraceLog "Signed-in user (Win32_ComputerSystem): $(if ($ctxCs.UserName) { $ctxCs.UserName } else { 'none' })"
    } catch {
        Write-CMTraceLog "WARNING: Could not gather full device context -- $($_.Exception.Message)" -Severity 2
    }

    Write-CMTraceLog "[Settings] Toast prompts         : $(if ($ToastEnabled) { 'Enabled' } else { 'Disabled' })"
    Write-CMTraceLog "[Settings] No-response action    : {{TOAST_TIMEOUT_ACTION}}"
    Write-CMTraceLog "[Settings] Maximum deferrals     : {{MAX_DEFERRALS}}"
    Write-CMTraceLog "[Settings] Critical notification : {{ALARM_MODE}}"
    Write-CMTraceLog "[Settings] Silent in Autopilot   : $(if ($SilentDuringAutopilot) { 'On' } else { 'Off' })"
    if ($TestUpdateType -eq 'BIOS') {
        Write-CMTraceLog "[Settings] Automatic restart     : $(if ($DisableRestart) { 'Disabled' } else { "Enabled ($RestartDelaySeconds second delay)" })"
    }

    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    # Only used in log lines: the stand-in Set-DATInstallStatus never writes to it.
    $VersionRegPath = "HKLM:\SOFTWARE\DriverAutomationTool\$TestUpdateType\$deviceOEM\$deviceModel"
    Write-CMTraceLog "Script directory: $ScriptDir"
    Write-CMTraceLog "Test result key: $TestRegPath (a real package would report to $VersionRegPath)"

    if ($TestUpdateType -eq 'BIOS') {
        try {
            $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
            Write-CMTraceLog "[Simulated] Current BIOS: $($bios.SMBIOSBIOSVersion) (released $($bios.ReleaseDate)). A real package compares this with its own version first and exits 0 without prompting when the device is already current."
        } catch {
            Write-CMTraceLog "Could not read the current BIOS version: $($_.Exception.Message)" -Severity 2
        }
    }

    # A real DAT package that is showing a prompt right now owns the shared scheduled task and
    # result files. Stepping in would cancel its prompt, so retry later instead.
    # A task with no toast process behind it is a leftover from an earlier run (older builds never
    # removed it, because their clean-up passed the folder without its trailing backslash). Remove
    # it rather than retry forever. The task state alone is not enough: it can read Ready while its
    # toast is still on screen.
    $busyTask = Get-ScheduledTask -TaskPath '\Driver Automation Tool\' -TaskName 'User Toast Notification' -ErrorAction SilentlyContinue
    $liveToast = $null
    if ($busyTask) {
        $liveToast = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match 'Show-ToastNotification|Show-StatusToast' } | Select-Object -First 1
    }
    if ($busyTask -and "$($busyTask.State)" -ne 'Running' -and -not $liveToast) {
        Write-CMTraceLog "Removing a leftover '\Driver Automation Tool\User Toast Notification' task (state: $($busyTask.State), no toast process running) -- no notification is in progress" -Severity 2
        Unregister-ScheduledTask -TaskPath '\Driver Automation Tool\' -TaskName 'User Toast Notification' -Confirm:$false -ErrorAction SilentlyContinue
        $busyTask = $null
    }
    if ($busyTask) {
        Write-CMTraceLog "Another Driver Automation Tool notification is in progress (scheduled task '\Driver Automation Tool\User Toast Notification' exists) -- exiting 1618 so the test runs again later" -Severity 2
        exit 1618
    }

    $promptOutcome  = 'NotShown'
    $toastAnswer    = ''
    $wouldExitCode  = 0
    $statusToast    = ''
    $restartOutcome = ''
    $proceed        = $true

    # The real package's Autopilot provisioning check, run for real. The status toasts and the
    # progress notification below read its result just as they do in a real package.
    $script:DATAutopilot = Test-DATAutopilotProvisioning
    Save-DATAutopilotSignalSnapshot

    if (-not $ToastEnabled) {
        $promptOutcome = 'Disabled'
        Write-CMTraceLog "[TestResult] Toast prompts are disabled in this build -- a real package would install straight away without asking the user"
    } elseif ($script:DATAutopilot.InProvisioning) {
        $promptOutcome = 'AutopilotProvisioning'
        Write-CMTraceLog "[TestResult] Autopilot provisioning detected ($($script:DATAutopilot.Phase)) -- a real package would install without prompting, without deferrals and without notifications"
    } else {
        # A snooze recorded by an earlier test run would make the gate exit without prompting.
        $priorSnooze = (Get-ItemProperty -Path $TestStatePath -Name 'SnoozeUntil' -ErrorAction SilentlyContinue).SnoozeUntil
        if ($priorSnooze) {
            Write-CMTraceLog "[TestMode] Clearing the snooze an earlier test run recorded ($priorSnooze). A real package would exit 1618 without prompting until then."
            Remove-ItemProperty -Path $TestStatePath -Name 'SnoozeUntil' -Force -ErrorAction SilentlyContinue
        }
        $priorDeferrals = (Get-ItemProperty -Path $TestStatePath -Name 'DeferralCount' -ErrorAction SilentlyContinue).DeferralCount
        if ($null -ne $priorDeferrals) {
            Write-CMTraceLog "[TestMode] Deferrals recorded by earlier test runs: $priorDeferrals (run with -Uninstall to reset)"
        }

        Write-CMTraceLog "[TestMode] Running the real toast gate"
        $gateOutput = @(. Invoke-DATTestToastGate)
        $gateExit = 0
        if ($gateOutput.Count -gt 0) { try { $gateExit = [int]$gateOutput[-1] } catch { $gateExit = 0 } }
        $toastAnswer = "$toastResult"

        if ($gateExit -eq 1618) {
            $proceed = $false
            $wouldExitCode = 1618
            $promptOutcome = if ($userDeferred) { 'RemindMeLater' } else { 'NoResponse' }
            Write-CMTraceLog "[TestResult] The user did not agree to the update ($promptOutcome). A real package would stop here and exit 1618, so the update is retried after the 4 hour snooze. Nothing else would happen on this run."
        } elseif ($forceInstall) {
            $promptOutcome = 'MaximumDeferralsReached'
            Write-CMTraceLog "[TestResult] The deferral limit was reached. A real package would show the final notice and install without asking."
        } elseif (-not $explorerProc) {
            $promptOutcome = 'NoUserSignedIn'
            Write-CMTraceLog "[TestResult] Nobody is signed in. A real package would install silently."
        } elseif (Test-DATSetupAccount -UserName $loggedOnUser) {
            $promptOutcome = 'SetupAccount'
            Write-CMTraceLog "[TestResult] The shell belongs to the Windows setup account ($loggedOnUser). A real package would install silently."
        } elseif ($userConsented) {
            $promptOutcome = 'UpdateNow'
            Write-CMTraceLog "[TestResult] The user chose Update Now. A real package would install now."
        } else {
            $promptOutcome = 'NoResponse'
            Write-CMTraceLog "[TestResult] No answer was given ($noResponseReason). The no-response action is InstallNow, so a real package would install now."
        }
    }

    if ($proceed -and $TestUpdateType -eq 'Drivers') {
        $wimOk = Test-DATTestPackageWim
        $extractPath = Join-Path $env:ProgramData 'DriverAutomationTool\Extract'
        Write-CMTraceLog "[Simulated] A real package would expand DriverPackage.wim to $extractPath and run: pnputil.exe /add-driver `"$extractPath\*.inf`" /subdirs /install"
        Invoke-DATTestInstallProgress -Failed (-not $wimOk -or $SimulatedOutcome -eq 'Failure')
        if (-not $wimOk -or $SimulatedOutcome -eq 'Failure') {
            $wouldExitCode = 1
            Write-CMTraceLog "[Simulated] Driver install failure. A real package would record the failure, show the issues notification and exit 1." -Severity 2
            $statusToast = Show-DATTestStatusToast -ToastScriptName 'Show-StatusToast-Issues.ps1'
        } elseif ($SimulatedOutcome -eq 'SuccessRestart') {
            $wouldExitCode = 3010
            Write-CMTraceLog "[Simulated] PNPUtil returned 3010: the drivers are installed but need a restart"
            $statusToast = Show-DATTestStatusToast -ToastScriptName 'Show-StatusToast-SuccessRestart.ps1'
            Write-CMTraceLog "[RestartNotice] Driver install needs a restart (PNPUtil 3010). No automatic restart is scheduled for drivers. User notification: $statusToast" -Severity $(if ($statusToast -eq 'Shown') { 1 } else { 2 })
            Write-CMTraceLog "[Simulated] A real package would exit 3010 and leave the restart to Intune / ConfigMgr"
        } else {
            Write-CMTraceLog "[Simulated] PNPUtil returned 0: the drivers are installed"
            $statusToast = Show-DATTestStatusToast -ToastScriptName 'Show-StatusToast-Success.ps1'
            Write-CMTraceLog "[Simulated] A real package would record the version marker and exit 0"
        }
    }

    if ($proceed -and $TestUpdateType -eq 'BIOS') {
        # AC power: checked for real, as a real package would do before flashing.
        $onBattery = $false
        try {
            $batteries = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)
            if ($batteries.Count -eq 0) {
                Write-CMTraceLog "[ACPower] No battery found -- the device is on mains power"
            } else {
                # BatteryStatus 2 = on AC power; anything else means it is running on the battery.
                $onBattery = -not ($batteries | Where-Object { $_.BatteryStatus -eq 2 })
                Write-CMTraceLog "[ACPower] Battery status: $(($batteries | ForEach-Object { $_.BatteryStatus }) -join ', ') -- $(if ($onBattery) { 'running on battery' } else { 'on AC power' })"
            }
        } catch {
            Write-CMTraceLog "[ACPower] Could not read the battery state: $($_.Exception.Message)" -Severity 2
        }

        if ($onBattery) {
            $wouldExitCode = 1618
            Write-CMTraceLog "[Simulated] The device is on battery. A real package would show the connect-power notification and exit 1618 so the update is retried later." -Severity 2
            $statusToast = Show-DATTestStatusToast -ToastScriptName 'Show-StatusToast-BIOSACPower.ps1'
        } else {
            try {
                $blv = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
                Write-CMTraceLog "[Simulated] BitLocker on $($env:SystemDrive): $($blv.ProtectionStatus). $(if ("$($blv.ProtectionStatus)" -eq 'On') { 'A real package would suspend it for one restart before flashing.' } else { 'Nothing to suspend.' })"
            } catch {
                Write-CMTraceLog "[Simulated] BitLocker state not available ($($_.Exception.Message))"
            }
            Write-CMTraceLog "[Simulated] A real package would expand DriverPackage.wim and stage the firmware with the $deviceOEM update tool"
            $wimOk = Test-DATTestPackageWim
            Invoke-DATTestInstallProgress -Failed (-not $wimOk -or $SimulatedOutcome -eq 'Failure')

            if (-not $wimOk -or $SimulatedOutcome -eq 'Failure') {
                $wouldExitCode = 1
                Write-CMTraceLog "[Simulated] BIOS update failure. A real package would record the failure, show the BIOS issues notification and exit 1." -Severity 2
                $statusToast = Show-DATTestStatusToast -ToastScriptName 'Show-StatusToast-BIOSIssues.ps1'
            } else {
                Write-CMTraceLog "[Simulated] Firmware prestaged: it applies on the next restart"
                $statusToast = Show-DATTestStatusToast -ToastScriptName 'Show-StatusToast-BIOSSuccess.ps1'
                $wouldExitCode = 3010
                $restartNoticeShown = $statusToast -eq 'Shown'
                Write-CMTraceLog "[RestartNotice] Prestaged/restart notice to user: $statusToast" -Severity $(if ($restartNoticeShown) { 1 } else { 2 })

                if ($script:DATAutopilot.InProvisioning) {
                    $restartOutcome = 'Left to the Enrollment Status Page (Autopilot provisioning)'
                    Write-CMTraceLog "[Simulated] Autopilot provisioning: a real package would schedule no restart and exit 3010. The firmware applies at the next restart."
                } elseif ($DisableRestart) {
                    $restartOutcome = 'Disabled by policy'
                    Write-CMTraceLog "[Simulated] Automatic restart is disabled. A real package would exit 3010 and leave the restart to the user."
                } else {
                    # The real package's restart decision, taken from its install script. It only
                    # reads state and logs; the restart itself is never scheduled here.
                    $focusAssistBlocking = $false
{{FOCUS_ASSIST_BLOCK}}
                    if ($focusAssistBlocking) {
                        $restartOutcome = 'Suppressed by Focus Assist'
                        Write-CMTraceLog "[Simulated] A real package would NOT restart (Focus Assist / Do Not Disturb). It would exit 3010 and the update would apply on the next manual restart."
                    } else {
                        $restartOutcome = "Restart in $RestartDelaySeconds seconds"
                        $restartMinutes = [math]::Round($RestartDelaySeconds / 60, 0)
                        Write-CMTraceLog "[Simulated] A real package would re-check BitLocker and run: shutdown.exe /r /t $RestartDelaySeconds (restart in $restartMinutes minute(s)). This test does NOT restart the device."
                    }
                }
            }
        }
    }

    Write-CMTraceLog "=========================================="
    Write-CMTraceLog "[Summary] Prompt outcome     : $promptOutcome$(if ($toastAnswer) { " (toast result: $toastAnswer)" })"
    Write-CMTraceLog "[Summary] Autopilot          : $(if ($script:DATAutopilot.InProvisioning) { "provisioning ($($script:DATAutopilot.Phase))" } else { 'not provisioning' }) -- $($script:DATAutopilot.Evidence)"
    if ($statusToast)    { Write-CMTraceLog "[Summary] Status notification: $statusToast" }
    if ($restartOutcome) { Write-CMTraceLog "[Summary] Restart decision   : $restartOutcome" }
    # A deferral must not be detected as installed: exit 1618 like the real package so the
    # deployment shows a retry and runs the test again. Every other outcome completes the test.
    $testExitCode = if ($wouldExitCode -eq 1618) { $wouldExitCode } else { 0 }
    Write-CMTraceLog "[Summary] A real package would exit with code $wouldExitCode. The test exits $testExitCode."
    Write-CMTraceLog "=========================================="

    $resultValues = [ordered]@{
        LastRunUtc       = (Get-Date).ToUniversalTime().ToString('o')
        SimulatedOutcome = $SimulatedOutcome
        PromptOutcome    = $promptOutcome
        ToastResult      = $toastAnswer
        StatusToast      = $statusToast
        RestartDecision  = $restartOutcome
        AutopilotPhase   = $script:DATAutopilot.Phase
        AutopilotEvidence = $script:DATAutopilot.Evidence
        WouldExitCode    = $wouldExitCode
        LogFile          = $LogFile
        LastError        = ''
    }
    if ($testExitCode -eq 0) { $resultValues['PackageVersion'] = $TestPackageVersion }
    Set-DATToastTestResult -Values $resultValues
    exit $testExitCode
}
catch {
    Write-CMTraceLog "FATAL ERROR in the toast test: $($_.Exception.Message)" -Severity 3
    Write-CMTraceLog "Stack: $($_.ScriptStackTrace)" -Severity 3
    Set-DATToastTestResult -Values ([ordered]@{
        LastRunUtc = (Get-Date).ToUniversalTime().ToString('o')
        LastError  = $_.Exception.Message
    })
    exit 1
}
finally {
    Stop-DATInstallProgress
}
