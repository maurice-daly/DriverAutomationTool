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
    [switch]$NoShortcut
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

function ConvertTo-DATConsolePixelMap {
    <#
    .SYNOPSIS
        Draws a hand-made pixel map as console text, for the launch banner.
    .DESCRIPTION
        Each string in -Map is one row of pixels; each character is looked up in -Palette
        (character -> 0xRRGGBB), and characters not in the palette are transparent, showing
        the console background. Each character cell shows two pixels stacked, drawn with
        half-block characters in 24-bit VT colour, so pixels stay square. Returns one string
        per text row; every row ends with a colour reset.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)][string[]]$Map,
        [Parameter(Mandatory)][hashtable]$Palette
    )

    $width = ($Map | Measure-Object -Property Length -Maximum).Maximum
    # Pixel colour, or -1 for transparent (including past the end of a short or odd last row)
    $pixelAt = {
        param ([int]$X, [int]$Y)
        if ($Y -ge $Map.Count -or $X -ge $Map[$Y].Length) { return -1 }
        $key = [string]$Map[$Y][$X]
        if ($Palette.ContainsKey($key)) { return [int]$Palette[$key] }
        return -1
    }

    # Escape and block characters by code point: PS 5.1 reads a BOM-less script as Windows-1252
    $esc = [char]27
    $upperHalf = [char]0x2580
    $lowerHalf = [char]0x2584
    $rows = for ($y = 0; $y -lt $Map.Count; $y += 2) {
        $line = [System.Text.StringBuilder]::new()
        for ($x = 0; $x -lt $width; $x++) {
            $top = & $pixelAt $x $y
            $bottom = & $pixelAt $x ($y + 1)
            $topRgb = "$(($top -shr 16) -band 255);$(($top -shr 8) -band 255);$($top -band 255)"
            $bottomRgb = "$(($bottom -shr 16) -band 255);$(($bottom -shr 8) -band 255);$($bottom -band 255)"
            if ($top -ge 0 -and $bottom -ge 0) {
                [void]$line.Append("$esc[38;2;${topRgb};48;2;${bottomRgb}m$upperHalf")
            } elseif ($top -ge 0) {
                [void]$line.Append("$esc[49;38;2;${topRgb}m$upperHalf")
            } elseif ($bottom -ge 0) {
                [void]$line.Append("$esc[49;38;2;${bottomRgb}m$lowerHalf")
            } else {
                [void]$line.Append("$esc[0m ")
            }
        }
        [void]$line.Append("$esc[0m")
        $line.ToString()
    }
    return $rows
}

function Write-DATLaunchBanner {
    <#
    .SYNOPSIS
        Writes the launch banner: "Driver Automation Tool" in ASCII art, then the MMS logo with
        "MMS Midway Edition" beside it.
    .DESCRIPTION
        The MMS logo is drawn only when the console understands VT colour codes and output is
        not redirected; otherwise "MMS Midway Edition" is written on its own. The logo is a
        pixel map in this function, so it needs no image file. The banner never stops the tool
        starting.
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

    $edition = 'MMS Midway Edition'
    # MMS logo: '#' white lettering, '.' red speech bubble, ' ' console background
    $mmsMap = @(
        '.............................',
        '.............................',
        '..##....##.##....##..#######.',
        '..###..###.###..###.##.......',
        '..########.########.##.......',
        '..##.##.##.##.##.##..######..',
        '..##....##.##....##.......##.',
        '..##....##.##....##.......##.',
        '..##....##.##....##.#######..',
        '.............................',
        '.............................',
        '  ....                       ',
        '  ...                        ',
        '  ..                         ',
        '  .                          '
    )

    $useImages = $false
    try { $useImages = (-not [Console]::IsOutputRedirected) -and ($Host.UI.SupportsVirtualTerminal -eq $true) } catch { }
    if (-not $useImages) {
        Write-Host "  $edition" -ForegroundColor Red
        Write-Host ''
        return
    }

    $mmsLines = @(ConvertTo-DATConsolePixelMap -Map $mmsMap -Palette @{ '#' = 0xFFFFFF; '.' = 0xFF0000 })
    $esc = [char]27
    # The text sits on the row through the middle of the lettering
    $editionRow = 2
    for ($i = 0; $i -lt $mmsLines.Count; $i++) {
        $text = if ($i -eq $editionRow) { "   $esc[1;97m$edition$esc[0m" } else { '' }
        Write-Host "  $($mmsLines[$i])$text"
    }
    Write-Host ''
}

# Display launch banner
try {
    Write-DATLaunchBanner
} catch {
    Write-Host 'Driver Automation Tool -- MMS Midway Edition' -ForegroundColor Cyan
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
