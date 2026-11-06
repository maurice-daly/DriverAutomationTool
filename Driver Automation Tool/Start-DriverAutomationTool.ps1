<#
    Driver Automation Tool v2.0 -- Launcher
    Run this script to start the application
#>

[CmdletBinding()]
param (
    [ValidateSet('Dark', 'Light')]
    [string]$Theme = 'Dark',

    # Skip desktop shortcut creation/management for this launch (for admins who manage
    # shortcuts manually). A persistent equivalent is the CreateDesktopShortcut registry value.
    [switch]$NoShortcut,

    # Stay in the PowerShell that started the launcher, without asking about PowerShell 7, for
    # this launch. Also passed to the relaunched copy so it can never relaunch again.
    [switch]$NoRelaunch
)

$ErrorActionPreference = 'Stop'

# Resolve application root
$AppRoot = $PSScriptRoot

# Check for administrative privileges (required for HKLM registry access)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $errorMsg = "Driver Automation Tool requires administrative privileges. Please run as Administrator."
    Write-Warning $errorMsg

    # Load WPF assemblies for splash screen
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $adminSplash = [System.Windows.Window]::new()
    $adminSplash.WindowStyle = 'None'
    $adminSplash.AllowsTransparency = $true
    $adminSplash.Background = [System.Windows.Media.Brushes]::Transparent
    $adminSplash.WindowStartupLocation = 'CenterScreen'
    $adminSplash.Width = 460
    $adminSplash.Height = 220
    $adminSplash.Topmost = $true
    $adminSplash.ResizeMode = 'NoResize'
    $adminSplash.ShowInTaskbar = $true
    $adminSplash.Title = 'Driver Automation Tool'

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(240, 30, 30, 30))
    $border.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $border.Padding = [System.Windows.Thickness]::new(32, 28, 32, 28)

    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $border.Effect = $shadow

    $panel = [System.Windows.Controls.StackPanel]::new()
    $panel.HorizontalAlignment = 'Center'
    $panel.VerticalAlignment = 'Center'

    $iconText = [System.Windows.Controls.TextBlock]::new()
    $iconText.Text = [char]0xE7BA
    $iconText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $iconText.FontSize = 36
    $iconText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromRgb(232, 160, 53))
    $iconText.HorizontalAlignment = 'Center'
    $iconText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($iconText) | Out-Null

    $msgText = [System.Windows.Controls.TextBlock]::new()
    $msgText.Text = $errorMsg
    $msgText.FontSize = 14
    $msgText.TextWrapping = 'Wrap'
    $msgText.TextAlignment = 'Center'
    $msgText.Foreground = [System.Windows.Media.Brushes]::White
    $msgText.HorizontalAlignment = 'Center'
    $msgText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($msgText) | Out-Null

    $countdownText = [System.Windows.Controls.TextBlock]::new()
    $countdownText.Text = 'Closing in 5 seconds...'
    $countdownText.FontSize = 11
    $countdownText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromRgb(120, 120, 120))
    $countdownText.HorizontalAlignment = 'Center'
    $panel.Children.Add($countdownText) | Out-Null

    $border.Child = $panel
    $adminSplash.Content = $border

    $adminSplash.Add_Loaded({
        $script:countdown = 5
        $script:adminTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $script:adminTimer.Interval = [TimeSpan]::FromSeconds(1)
        $script:adminTimer.Add_Tick({
            $script:countdown--
            if ($script:countdown -le 0) {
                $script:adminTimer.Stop()
                $adminSplash.Close()
            } else {
                $countdownText.Text = "Closing in $script:countdown seconds..."
            }
        })
        $script:adminTimer.Start()
    })

    $adminSplash.ShowDialog() | Out-Null
    exit 1
}

function Write-DATLaunchBanner {
    <#
    .SYNOPSIS
        Writes the launch banner: "Driver Automation Tool" in ASCII art. The banner never stops
        the tool starting.
    #>
    [CmdletBinding()]
    param ()

    $banner = @"

    ____       _
   / __ \_____(_)   _____  _____
  / / / / ___/ / | / / _ \/ ___/
 / /_/ / /  / /| |/ /  __/ /
/_____/_/  /_/ |___/\___/_/              __  _
   /   | __  __/ /_____  ____ ___  ____/ /_(_)___  ____
  / /| |/ / / / __/ __ \/ __ ``__ \/ __  / __/ / __ \/ __ \
 / ___ / /_/ / /_/ /_/ / / / / / / /_/ / /_/ / /_/ / / / /
/_/  |_\__,_/\__/\____/_/ /_/ /_/\__,_/\__/_/\____/_/ /_/
  /_  __/___  ____  / /
   / / / __ \/ __ \/ /
  / / / /_/ / /_/ / /
 /_/  \____/\____/_/

"@
    Write-Host $banner -ForegroundColor Cyan
}

# Display launch banner
try {
    Write-DATLaunchBanner
} catch {
    Write-Host 'Driver Automation Tool' -ForegroundColor Cyan
}

# Set install directory in registry
$OldRegPath = "HKLM:\SOFTWARE\MSEndpointMgr\DriverAutomationTool"
$RegPath    = "HKLM:\SOFTWARE\DriverAutomationTool"

# Migrate settings from the legacy registry path on first run after upgrade
if ((Test-Path $OldRegPath) -and -not (Test-Path $RegPath)) {
    Write-Host "Migrating registry settings from legacy path to new path..." -ForegroundColor Yellow
    Copy-Item -Path $OldRegPath -Destination $RegPath -Recurse -Force
}

if (-not (Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}
New-ItemProperty -Path $RegPath -Name "InstallDirectory" -Value $AppRoot -PropertyType String -Force | Out-Null

function Find-DATPowerShell7 {
    <#
    .SYNOPSIS
        Finds the newest stable PowerShell 7 or later on this computer, for the relaunch offer.
    .DESCRIPTION
        Checks the default install folder, then every pwsh.exe on the PATH. A file counts only
        when its product name is PowerShell and its version is 7 or later; preview and release
        candidate builds are left out. A Microsoft Store install is reached through an app
        execution alias that has no version of its own, so its version is read from the Store
        package instead. Returns an object with Path and Version, or $null when none is found.

        -Path replaces the places searched, so the search can be tested against copies.
    #>
    [CmdletBinding()]
    param (
        [string[]]$Path
    )

    if (-not $PSBoundParameters.ContainsKey('Path')) {
        # ProgramW6432 is the 64-bit Program Files folder, even from a 32-bit Windows PowerShell
        $programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
        $Path = @(Join-Path $programFiles 'PowerShell\7\pwsh.exe') +
            @(Get-Command -Name 'pwsh.exe' -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
    }

    $best = $null
    foreach ($candidate in $Path) {
        if ([string]::IsNullOrWhiteSpace($candidate) -or (Split-Path -Path $candidate -Leaf) -ne 'pwsh.exe' -or
            -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }

        $version = $null
        $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($candidate)
        if ($info.FileMajorPart -gt 0) {
            if ($info.ProductName -ne 'PowerShell' -or "$($info.ProductVersion)" -match '^\d+\.\d+\.\d+-') { continue }
            $version = [version]::new($info.FileMajorPart, $info.FileMinorPart, $info.FileBuildPart)
        } elseif ($candidate -match '\\Microsoft\\WindowsApps\\pwsh\.exe$') {
            $package = Get-AppxPackage -Name 'Microsoft.PowerShell' -ErrorAction SilentlyContinue |
                Sort-Object -Property { [version]$_.Version } -Descending | Select-Object -First 1
            if ($package) {
                $packageVersion = [version]$package.Version
                $version = [version]::new($packageVersion.Major, $packageVersion.Minor, $packageVersion.Build)
            }
        }

        if ($null -ne $version -and $version.Major -ge 7 -and ($null -eq $best -or $version -gt $best.Version)) {
            $best = [pscustomobject]@{ Path = $candidate; Version = $version }
        }
    }
    return $best
}

function Get-DATPowerShell7LaunchAction {
    <#
    .SYNOPSIS
        Decides what the launcher does about PowerShell 7 when Windows PowerShell started it.
    .DESCRIPTION
        Returns Relaunch, Ask or Continue. With no PowerShell 7 found the launcher carries on.
        Otherwise LaunchInPowerShell7 (Common Settings > General) decides: Always relaunches,
        Never carries on, and Ask, a missing value or one the tool cannot read asks.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [AllowNull()][AllowEmptyString()][string]$Setting,
        [bool]$PowerShell7Found
    )

    if (-not $PowerShell7Found) { return 'Continue' }
    switch ("$Setting".Trim()) {
        'Always' { return 'Relaunch' }
        'Never'  { return 'Continue' }
        default  { return 'Ask' }
    }
}

function Read-DATPowerShell7Choice {
    <#
    .SYNOPSIS
        Asks in the console whether to relaunch in PowerShell 7.
    .DESCRIPTION
        Returns Yes, No, Always or Never. No is the default, and the answer when the host cannot
        ask (a non-interactive session).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][version]$Version,
        [Parameter(Mandatory)][string]$Path
    )

    $labels = @('Yes', 'No', 'Always', 'Never')
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', "Relaunch in PowerShell $Version this time"),
        [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Carry on in Windows PowerShell this time'),
        [System.Management.Automation.Host.ChoiceDescription]::new('&Always', 'Relaunch in PowerShell 7 now and every time the tool starts'),
        [System.Management.Automation.Host.ChoiceDescription]::new('Ne&ver', 'Carry on in Windows PowerShell and stop asking')
    )
    try {
        return $labels[$Host.UI.PromptForChoice('PowerShell 7', "PowerShell $Version is installed at $Path. Relaunch the tool in PowerShell 7?", $choices, 1)]
    } catch {
        return 'No'
    }
}

function Invoke-DATPowerShell7Relaunch {
    <#
    .SYNOPSIS
        Offers PowerShell 7 when Windows PowerShell started the launcher, and relaunches in it.
    .DESCRIPTION
        Reads LaunchInPowerShell7 from -RegPath (see Get-DATPowerShell7LaunchAction), asks when
        it is Ask, and saves Always or Never when either is chosen. The relaunch runs
        -LauncherPath with -LauncherArguments in this console, already elevated; the caller
        includes -NoRelaunch so the new copy cannot offer again.

        Returns the relaunched tool's exit code, or $null to carry on in this PowerShell. A failed
        check or relaunch is reported and never stops the tool starting.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$RegPath,
        [Parameter(Mandatory)][string]$LauncherPath,
        [string[]]$LauncherArguments = @()
    )

    $pwsh7 = $null
    try {
        $setting = [string](Get-ItemProperty -Path $RegPath -Name 'LaunchInPowerShell7' -ErrorAction SilentlyContinue).LaunchInPowerShell7
        # Never skips the search too, so a declined offer costs nothing at each start
        if ($setting.Trim() -ne 'Never') { $pwsh7 = Find-DATPowerShell7 }
        $action = Get-DATPowerShell7LaunchAction -Setting $setting -PowerShell7Found ($null -ne $pwsh7)
    } catch {
        Write-Host "PowerShell 7 check skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return $null
    }

    if ($action -eq 'Ask') {
        Write-Host ''
        $choice = Read-DATPowerShell7Choice -Version $pwsh7.Version -Path $pwsh7.Path
        if ($choice -eq 'Always' -or $choice -eq 'Never') {
            try {
                New-ItemProperty -Path $RegPath -Name 'LaunchInPowerShell7' -Value $choice -PropertyType String -Force | Out-Null
                Write-Host 'Choice saved -- change it in Common Settings > General.' -ForegroundColor DarkGray
            } catch {
                Write-Host "Choice not saved: $($_.Exception.Message)" -ForegroundColor DarkYellow
            }
        }
        $action = if ($choice -eq 'Yes' -or $choice -eq 'Always') { 'Relaunch' } else { 'Continue' }
    }
    if ($action -ne 'Relaunch') { return $null }

    # Start-Process -NoNewWindow shares this console without capturing its output, which a direct
    # call inside a function would. It joins arguments with spaces, so quote any that have one.
    $argumentLine = (@('-ExecutionPolicy', 'Bypass', '-File', $LauncherPath) + $LauncherArguments | ForEach-Object {
        if ($_ -match '\s') { "`"$_`"" } else { $_ }
    }) -join ' '
    # The relaunched copy writes its own banner
    try { Clear-Host } catch { }
    try {
        $process = Start-Process -FilePath $pwsh7.Path -ArgumentList $argumentLine -NoNewWindow -PassThru -ErrorAction Stop
        # Reading Handle now keeps ExitCode available once the process has ended
        $null = $process.Handle
        # WaitForExit rather than -Wait: -Wait also waits for any process the tool leaves running
        $process.WaitForExit()
        return $process.ExitCode
    } catch {
        Write-Host "Could not start PowerShell 7 ($($_.Exception.Message)) -- carrying on in Windows PowerShell." -ForegroundColor DarkYellow
        return $null
    }
}

# Report the PowerShell running the tool and, under Windows PowerShell, offer PowerShell 7 when it
# is installed.
$engineName = if ($PSVersionTable.PSEdition -eq 'Core') { 'PowerShell' } else { 'Windows PowerShell' }
Write-Host "  PowerShell    : " -NoNewline -ForegroundColor DarkGray
Write-Host "$engineName $($PSVersionTable.PSVersion)" -ForegroundColor White

if (-not $NoRelaunch -and $PSVersionTable.PSVersion.Major -lt 7) {
    $relaunchArgs = @('-Theme', $Theme, '-NoRelaunch')
    if ($NoShortcut) { $relaunchArgs += '-NoShortcut' }
    $relaunchExitCode = Invoke-DATPowerShell7Relaunch -RegPath $RegPath -LauncherPath $PSCommandPath -LauncherArguments $relaunchArgs
    if ($null -ne $relaunchExitCode) { exit $relaunchExitCode }
}

function Update-DATDesktopShortcut {
    <#
    .SYNOPSIS
        Puts the tool's desktop shortcut on the chosen desktop and removes this launcher's
        shortcut from the other one.
    .DESCRIPTION
        AllUsers puts the shortcut on the Public desktop, so one shortcut is shared by every
        admin profile on the machine instead of one copy per user (#916). CurrentUser puts it on
        the desktop of the account running the tool only, for admins who do not want it shown
        to everyone who signs in.

        Switching the setting moves the shortcut the next time the tool starts: the shortcut on
        the other desktop is removed and one is made on the chosen desktop. Only the running
        account's desktop is reachable, so another admin's per-user copy is removed the next
        time that admin starts the tool. A shortcut is removed only when it starts this
        launcher, never an unrelated shortcut with the same name.

        The desktops are parameters rather than looked up here so the move can be tested
        against temporary folders. Returns the path of the shortcut it maintains, or an empty
        string when the chosen desktop could not be found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][AllowEmptyString()][string]$AppRoot,
        [ValidateSet('AllUsers', 'CurrentUser')][string]$Scope = 'AllUsers',
        [Parameter(Mandatory)][AllowEmptyString()][string]$AllUsersDesktop,
        [Parameter(Mandatory)][AllowEmptyString()][string]$UserDesktop,
        [string]$ShortcutName = 'Driver Automation Tool.lnk'
    )

    $launcherPath = Join-Path $AppRoot 'Start-DriverAutomationTool.ps1'
    $iconPath = Join-Path $AppRoot 'Branding\DATLogo.ico'
    $wshShell = New-Object -ComObject WScript.Shell

    # A plain substring test rather than -like: brackets in an install path are wildcard sets
    # to -like, which made a shortcut to the same launcher look like someone else's.
    $startsThisLauncher = {
        param ([string]$Path)
        $lnk = $wshShell.CreateShortcut($Path)
        return ("$($lnk.Arguments)".IndexOf($launcherPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
    }

    if ($Scope -eq 'CurrentUser') {
        $keepDesktop = $UserDesktop
        $dropDesktop = $AllUsersDesktop
    } else {
        $keepDesktop = $AllUsersDesktop
        $dropDesktop = $UserDesktop
    }

    if ([string]::IsNullOrWhiteSpace($keepDesktop) -or -not (Test-Path -LiteralPath $keepDesktop)) {
        Write-Host "Desktop shortcut not created: the $(if ($Scope -eq 'CurrentUser') { 'current user' } else { 'Public' }) desktop folder was not found." -ForegroundColor DarkYellow
        return ''
    }
    $shortcutPath = Join-Path $keepDesktop $ShortcutName

    # Idempotent -- only create if missing or pointing to a different launcher
    if (-not ((Test-Path -LiteralPath $shortcutPath) -and (& $startsThisLauncher $shortcutPath))) {
        $shortcut = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$launcherPath`""
        $shortcut.WorkingDirectory = $AppRoot
        $shortcut.Description = 'Driver Automation Tool'
        if (Test-Path -LiteralPath $iconPath) {
            $shortcut.IconLocation = "$iconPath,0"
        }
        $shortcut.Save()
        # Set "Run as administrator" flag (byte 21, bit 0x20 in the .lnk binary)
        $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
        $bytes[21] = $bytes[21] -bor 0x20
        [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)
        Write-Host "Desktop shortcut created: $shortcutPath" -ForegroundColor Green
    }

    # Remove this launcher's shortcut from the desktop that was not chosen. Under AllUsers this
    # is also what clears the per-user copies left by versions before the Public desktop.
    if (-not [string]::IsNullOrWhiteSpace($dropDesktop)) {
        try {
            $otherShortcut = Join-Path $dropDesktop $ShortcutName
            if (($otherShortcut -ne $shortcutPath) -and (Test-Path -LiteralPath $otherShortcut) -and (& $startsThisLauncher $otherShortcut)) {
                Remove-Item -LiteralPath $otherShortcut -Force -ErrorAction Stop
                Write-Host "Removed desktop shortcut from the $(if ($Scope -eq 'CurrentUser') { 'Public' } else { 'current user' }) desktop: $otherShortcut" -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host "Could not remove the desktop shortcut from the other desktop: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    return $shortcutPath
}

# Maintain the desktop shortcut. DesktopShortcutCurrentUserOnly (Common Settings > General)
# chooses the running user's desktop over the Public one. Honors the CreateDesktopShortcut
# registry toggle (default on) and the -NoShortcut switch for admins who manage shortcuts
# manually. A shortcut failure is reported and never stops the tool from starting.
$shortcutSettings = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
$shortcutDisabled = $NoShortcut -or ($shortcutSettings.CreateDesktopShortcut -eq 0)

if ($shortcutDisabled) {
    Write-Host "Desktop shortcut management skipped (disabled)." -ForegroundColor DarkGray
} else {
    try {
        $shortcutScope = if ($shortcutSettings.DesktopShortcutCurrentUserOnly -eq 1) { 'CurrentUser' } else { 'AllUsers' }
        Update-DATDesktopShortcut -AppRoot $AppRoot -Scope $shortcutScope `
            -AllUsersDesktop ([Environment]::GetFolderPath('CommonDesktopDirectory')) `
            -UserDesktop ([Environment]::GetFolderPath('Desktop')) | Out-Null
    } catch {
        Write-Host "Desktop shortcut could not be updated: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

# Launch the application
$MainApp = Join-Path $AppRoot "UI\MainApplication.ps1"
& $MainApp -Theme $Theme
