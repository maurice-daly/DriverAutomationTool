<#
    Driver Automation Tool v2.0 -- Launcher
    Run this script to start the application
#>

[CmdletBinding()]
param (
    [ValidateSet('Dark', 'Light')]
    [string]$Theme = 'Dark'
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

# Display launch banner
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

# Create desktop shortcut (idempotent -- only creates if missing or pointing to wrong location)
$desktopPath = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktopPath 'Driver Automation Tool.lnk'
$launcherPath = Join-Path $AppRoot 'Start-DriverAutomationTool.ps1'
$iconPath = Join-Path $AppRoot 'Branding\DATLogo.ico'
$needsShortcut = $true
if (Test-Path $shortcutPath) {
    $existing = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
    if ($existing.Arguments -like "*$launcherPath*") {
        $needsShortcut = $false
    }
}
if ($needsShortcut) {
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$launcherPath`""
    $shortcut.WorkingDirectory = $AppRoot
    $shortcut.Description = 'Driver Automation Tool'
    if (Test-Path $iconPath) {
        $shortcut.IconLocation = "$iconPath,0"
    }
    $shortcut.Save()
    # Set "Run as administrator" flag (byte 21, bit 0x20 in the .lnk binary)
    $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
    $bytes[21] = $bytes[21] -bor 0x20
    [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)
    Write-Host "Desktop shortcut created: $shortcutPath" -ForegroundColor Green
}

# Launch the application
$MainApp = Join-Path $AppRoot "UI\MainApplication.ps1"
& $MainApp -Theme $Theme
