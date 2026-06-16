<#
    Driver Automation Tool v2.0 - Main Application
    Modern WPF UI with rounded design
    Author: Maurice Daly
#>

param (
    [ValidateSet('Dark', 'Light')]
    [string]$Theme = 'Dark'
)

# Resolve paths
$AppRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrEmpty($AppRoot)) { $AppRoot = $PSScriptRoot }
$UIPath = Join-Path $AppRoot "UI"
$ModulesPath = Join-Path $AppRoot "Modules"

# Wrap all startup operations in a single try/catch so that any failure surfaces
# a visible error dialog instead of silently terminating.
try {

# Load WPF assemblies (#2 — WPF assembly load failure)
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ModelItem implements INotifyPropertyChanged so that WPF bindings update automatically
# when Selected changes — no manual visual-tree walking required.
$_existingType = ([System.Management.Automation.PSTypeName]'ModelItem').Type
$_needsCompile = (-not $_existingType) -or (-not $_existingType.GetProperty('BIOSVersion'))
if ($_needsCompile) {
    if ($_existingType) {
        Write-Warning "ModelItem type is stale (missing BIOSVersion). Recompiling with a new name is not possible in the same AppDomain. BIOSVersion column may be empty until a fresh PowerShell process is used."
    }
    try {
    Add-Type -ReferencedAssemblies @('System.ComponentModel', 'System.ObjectModel', 'System.Runtime') -TypeDefinition @'
using System.ComponentModel;
public class ModelItem : INotifyPropertyChanged {
    public event PropertyChangedEventHandler PropertyChanged;
    private bool _selected;
    public bool Selected {
        get { return _selected; }
        set {
            if (_selected != value) {
                _selected = value;
                var h = PropertyChanged;
                if (h != null) h(this, new PropertyChangedEventArgs("Selected"));
            }
        }
    }
    public string OEM        { get; set; }
    public string Model      { get; set; }
    public string OS         { get; set; }
    public string Build      { get; set; }
    public string Baseboards { get; set; }
    public bool   HasGFX     { get; set; }
    public string GFXBrand   { get; set; }
    public string CustomDriverPath { get; set; }
    public string Version    { get; set; }
    public string BIOSVersion { get; set; }
}
'@
    } catch {
        # Type already exists in AppDomain — cannot redefine
    }
}

# Import core module (#6 — module import failure)
$CoreModulePath = Join-Path $ModulesPath "DriverAutomationToolCore\DriverAutomationToolCore.psd1"
if (-not (Test-Path $CoreModulePath)) {
    throw "Core module not found at: $CoreModulePath"
}
Import-Module $CoreModulePath -Force -ErrorAction Stop

# Load theme definitions (#7 — dot-source failure)
$ThemePath = Join-Path $UIPath "Themes\ThemeDefinitions.ps1"
if (-not (Test-Path $ThemePath)) {
    throw "Theme definitions not found at: $ThemePath"
}
. $ThemePath

# Load XAML (#1 — XAML parse failure)
$XamlPath = Join-Path $UIPath "MainWindow.xaml"
[xml]$Xaml = Get-Content $XamlPath -Raw -ErrorAction Stop

# Create XmlNodeReader and load window
$Reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [System.Windows.Markup.XamlReader]::Load($Reader)

# Set window icon from DATLogo.ico (#11 — corrupted icon crash)
$icoPath = Join-Path $AppRoot "Branding\DATLogo.ico"
if (Test-Path $icoPath) {
    try {
        $Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create(
            [Uri]::new($icoPath, [UriKind]::Absolute))
    } catch {
        Write-Warning "Failed to load application icon: $($_.Exception.Message)"
    }
}

} catch {
    # Ensure PresentationFramework is available for the error dialog
    try { Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue } catch { }
    $startupError = "Driver Automation Tool failed to start:`n`n$($_.Exception.Message)`n`nStack:`n$($_.ScriptStackTrace)"
    try {
        [System.Windows.MessageBox]::Show($startupError, 'Driver Automation Tool — Startup Error', 'OK', 'Error') | Out-Null
    } catch {
        Write-Error $startupError
    }
    return
}

# Safety net — prevent unhandled Dispatcher exceptions from terminating the process.
# Without this, ANY uncaught exception on a DispatcherTimer tick or event handler
# kills the entire application with no visible error.
# IMPORTANT: The handler must NOT update the UI or write console output for transient
# resource errors (e.g. "Not enough quota"), otherwise it triggers layout/redraw,
# which throws more errors, creating an infinite cascade.
$script:LastUnhandledErrorTick = 0
$script:UnhandledErrorCount    = 0
try {
    $exceptionHandler = {
        param($sender, $e)
        $e.Handled = $true
        try {
            $errMsg = $e.Exception.Message
            $now = [Environment]::TickCount

            # Suppress transient Win32 resource-pressure errors entirely — they resolve
            # once the initial layout pass completes and retrying just makes it worse.
            if ($errMsg -match 'quota|Not enough storage|desktop heap') { return }

            # Throttle: if the same error fires rapidly (< 2 s apart) more than 3 times,
            # stop writing to console/UI to avoid cascading GDI/layout pressure.
            if (($now - $script:LastUnhandledErrorTick) -lt 2000) {
                $script:UnhandledErrorCount++
                if ($script:UnhandledErrorCount -gt 3) { return }
            } else {
                $script:UnhandledErrorCount = 0
            }
            $script:LastUnhandledErrorTick = $now

            $msg = "Unhandled UI exception: $errMsg"
            Write-Warning $msg
            $statusCtrl = $Window.FindName('txt_Status')
            if ($statusCtrl) { $statusCtrl.Text = $msg }
        } catch { }
    }

    if ($null -ne [System.Windows.Application]::Current) {
        [System.Windows.Application]::Current.Add_DispatcherUnhandledException($exceptionHandler)
    } else {
        $Window.Dispatcher.Add_UnhandledException($exceptionHandler)
    }
} catch {
    Write-Warning "Could not register unhandled-exception safety net: $($_.Exception.Message)"
}

# Find all named elements
$namedElements = $Xaml.SelectNodes('//*[@*[local-name()="Name"]]')
$controls = @{}
foreach ($node in $namedElements) {
    $name = $node.GetAttribute("Name", "http://schemas.microsoft.com/winfx/2006/xaml")
    if ([string]::IsNullOrEmpty($name)) { $name = $node.GetAttribute("x:Name") }
    if ([string]::IsNullOrEmpty($name)) { $name = $node.Name }
    if (-not [string]::IsNullOrEmpty($name)) {
        $element = $Window.FindName($name)
        if ($null -ne $element) {
            $controls[$name] = $element
            Set-Variable -Name $name -Value $element -Scope Script
        }
    }
}

#region Theme Application

$script:CurrentTheme = $Theme
$script:ThemeDictionary = $null

function Set-DATApplicationTheme {
    param ([string]$ThemeName)

    $newDict = Get-DATThemeResourceDictionary -ThemeName $ThemeName

    # Remove previous theme dictionary if one exists
    if ($null -ne $script:ThemeDictionary) {
        $Window.Resources.MergedDictionaries.Remove($script:ThemeDictionary) | Out-Null
    }

    # Add new theme dictionary via MergedDictionaries for reliable DynamicResource updates
    $Window.Resources.MergedDictionaries.Add($newDict)
    $script:ThemeDictionary = $newDict
    $script:CurrentTheme = $ThemeName
}

# Apply initial theme
Set-DATApplicationTheme -ThemeName $Theme

#endregion Theme Application

#region Window Chrome (Custom Title Bar)

# Enable dragging on title bar
$TitleBar.Add_MouseLeftButtonDown({
    $Window.DragMove()
})

# Double-click to maximize/restore
$TitleBar.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($e.ClickCount -eq 2) {
        if ($Window.WindowState -eq 'Maximized') {
            $Window.WindowState = 'Normal'
        } else {
            $Window.WindowState = 'Maximized'
        }
    }
})

$btn_Minimize.Add_Click({ $Window.WindowState = 'Minimized' })

$btn_Maximize.Add_Click({
    if ($Window.WindowState -eq 'Maximized') {
        $Window.WindowState = 'Normal'
        $btn_Maximize.Content = [char]0xE739
    } else {
        $Window.WindowState = 'Maximized'
        $btn_Maximize.Content = [char]0xE923
    }
})

$btn_Close.Add_Click({ $Window.Close() })

$btn_ThemeToggle.Add_Click({
    try {
        if ($script:CurrentTheme -eq 'Dark') {
            Set-DATApplicationTheme -ThemeName 'Light'
        } else {
            Set-DATApplicationTheme -ThemeName 'Dark'
        }
        # Update the build progress modal if it's open
        Update-DATBuildModalTheme
    } catch {
        Write-DATActivityLog "Theme toggle failed: $($_.Exception.Message)" -Level Error
    }
})

$btn_TitleBarCoffee.Add_Click({
    Start-Process 'https://www.buymeacoffee.com/modaly'
})

#endregion Window Chrome

#region Activity Log

# Thread-safe log queue for background → UI communication
$script:LogQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

# Visual tree helper — finds the first descendant of a given type name
function Find-DATVisualChild {
    param ($Parent, [string]$TypeName)
    for ($i = 0; $i -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent); $i++) {
        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $i)
        if ($child.GetType().Name -eq $TypeName) { return $child }
        $result = Find-DATVisualChild -Parent $child -TypeName $TypeName
        if ($null -ne $result) { return $result }
    }
    return $null
}

function Write-DATActivityLog {
    param (
        [string]$Message,
        [ValidateSet('Info', 'Warn', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    # Activity log panel removed — route messages to the CMTrace log file only
    $severity = switch ($Level) {
        'Error' { '3' }
        'Warn'  { '2' }
        default { '1' }
    }
    try { Write-DATLogEntry -Value $Message -Severity $severity } catch { }
}

function Invoke-DATLogQueueDrain {
    if ($null -eq $script:LogQueue) { return }
    # Drain any queued messages to the log file, parsing [SOURCE:...] markers for the loading modal
    $msg = $null
    while ($script:LogQueue.TryDequeue([ref]$msg)) {
        # Check for structured source status markers: [SOURCE:Name:Status] or [SOURCE:Name:Status:Detail]
        if ($msg -match '^\[SOURCE:([^:]+):([^:\]]+)(?::([^\]]*))?\]$') {
            $srcName   = $Matches[1]
            $srcStatus = $Matches[2]
            $srcDetail = $Matches[3]
            try { Update-DATLoadingSourceStatus -Source $srcName -Status $srcStatus -Detail $srcDetail } catch { }
            continue  # Don't log the marker itself
        }
        try { Write-DATLogEntry -Value $msg -Severity 1 } catch { }
    }
}

#endregion Activity Log

#region Themed Dialogs

function Show-DATConfirmDialog {
    param (
        [string]$Title = "Confirm",
        [string]$Message,
        [string]$Icon = [char]0xE7BA,
        [string]$ConfirmLabel = "Yes, Delete"
    )

    $script:dialogResult = $false
    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])

    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background = [System.Windows.Media.Brushes]::Transparent
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $Window
    $dlg.Width = 440
    $dlg.SizeToContent = 'Height'
    $dlg.Topmost = $true
    $dlg.ResizeMode = 'NoResize'
    $dlg.ShowInTaskbar = $false

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(245, $bgColor.R, $bgColor.G, $bgColor.B))
    $border.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $border.Padding = [System.Windows.Thickness]::new(28, 24, 28, 24)
    $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $border.Effect = $shadow

    $panel = [System.Windows.Controls.StackPanel]::new()

    # Warning icon
    $iconText = [System.Windows.Controls.TextBlock]::new()
    $iconText.Text = $Icon
    $iconText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $iconText.FontSize = 28
    $iconText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusWarning']))
    $iconText.HorizontalAlignment = 'Center'
    $iconText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($iconText) | Out-Null

    # Title
    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.Text = $Title
    $titleText.FontSize = 16
    $titleText.FontWeight = [System.Windows.FontWeights]::Bold
    $titleText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $titleText.HorizontalAlignment = 'Center'
    $titleText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($titleText) | Out-Null

    # Message
    $msgText = [System.Windows.Controls.TextBlock]::new()
    $msgText.Text = $Message
    $msgText.FontSize = 13
    $msgText.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $msgText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $msgText.HorizontalAlignment = 'Center'
    $msgText.TextAlignment = [System.Windows.TextAlignment]::Center
    $msgText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 24)
    $panel.Children.Add($msgText) | Out-Null

    # Button row
    $btnGrid = [System.Windows.Controls.Grid]::new()
    $col1 = [System.Windows.Controls.ColumnDefinition]::new(); $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col2 = [System.Windows.Controls.ColumnDefinition]::new(); $col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $btnGrid.ColumnDefinitions.Add($col1)
    $btnGrid.ColumnDefinitions.Add($col2)

    # Yes button (danger style)
    $btnYes = [System.Windows.Controls.Button]::new()
    $btnYes.Height = 36
    $btnYes.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
    $btnYes.Cursor = [System.Windows.Input.Cursors]::Hand
    $yesTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonDanger'])" CornerRadius="8" Padding="16,8">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonDangerHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnYes.Template = $yesTemplate
    $btnYes.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonPrimaryForeground']))
    $btnYes.FontSize = 13
    $btnYes.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnYes.Content = $ConfirmLabel
    [System.Windows.Controls.Grid]::SetColumn($btnYes, 0)
    $btnYes.Add_Click({ $script:dialogResult = $true; $dlg.Close() })
    $btnGrid.Children.Add($btnYes) | Out-Null

    # No button (secondary style)
    $btnNo = [System.Windows.Controls.Button]::new()
    $btnNo.Height = 36
    $btnNo.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
    $btnNo.Cursor = [System.Windows.Input.Cursors]::Hand
    $noTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonSecondary'])" CornerRadius="8" Padding="16,8">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonSecondaryHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnNo.Template = $noTemplate
    $btnNo.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonSecondaryForeground']))
    $btnNo.FontSize = 13
    $btnNo.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnNo.Content = "Cancel"
    [System.Windows.Controls.Grid]::SetColumn($btnNo, 1)
    $btnNo.Add_Click({ $script:dialogResult = $false; $dlg.Close() })
    $btnGrid.Children.Add($btnNo) | Out-Null

    $panel.Children.Add($btnGrid) | Out-Null
    $border.Child = $panel
    $dlg.Content = $border

    $dlg.ShowDialog() | Out-Null
    return $script:dialogResult
}

function Show-DATInfoDialog {
    param (
        [string]$Title = "Information",
        [string]$Message,
        [ValidateSet('Success', 'Error', 'Warning', 'Info')]
        [string]$Type = 'Info',
        [string]$ButtonLabel = 'OK'
    )

    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])

    # Map type to icon and colour
    switch ($Type) {
        'Success' { $iconChar = [string][char]0xE73E; $iconColor = $theme['StatusSuccess'] }
        'Error'   { $iconChar = [string][char]0xEA39; $iconColor = $theme['StatusError'] }
        'Warning' { $iconChar = [string][char]0xE7BA; $iconColor = $theme['StatusWarning'] }
        default   { $iconChar = [string][char]0xE946; $iconColor = $theme['StatusInfo'] }
    }

    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background = [System.Windows.Media.Brushes]::Transparent
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $Window
    $dlg.Width = 440
    $dlg.SizeToContent = 'Height'
    $dlg.Topmost = $true
    $dlg.ResizeMode = 'NoResize'
    $dlg.ShowInTaskbar = $false

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(245, $bgColor.R, $bgColor.G, $bgColor.B))
    $border.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $border.Padding = [System.Windows.Thickness]::new(28, 24, 28, 24)
    $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $border.Effect = $shadow

    $panel = [System.Windows.Controls.StackPanel]::new()

    # Icon
    $iconText = [System.Windows.Controls.TextBlock]::new()
    $iconText.Text = $iconChar
    $iconText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $iconText.FontSize = 28
    $iconText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($iconColor))
    $iconText.HorizontalAlignment = 'Center'
    $iconText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($iconText) | Out-Null

    # Title
    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.Text = $Title
    $titleText.FontSize = 16
    $titleText.FontWeight = [System.Windows.FontWeights]::Bold
    $titleText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $titleText.HorizontalAlignment = 'Center'
    $titleText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($titleText) | Out-Null

    # Message
    $msgText = [System.Windows.Controls.TextBlock]::new()
    $msgText.Text = $Message
    $msgText.FontSize = 13
    $msgText.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $msgText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $msgText.HorizontalAlignment = 'Center'
    $msgText.TextAlignment = [System.Windows.TextAlignment]::Center
    $msgText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 24)
    $panel.Children.Add($msgText) | Out-Null

    # OK button (primary style)
    $btnOk = [System.Windows.Controls.Button]::new()
    $btnOk.Height = 36
    $btnOk.HorizontalAlignment = 'Stretch'
    $btnOk.Cursor = [System.Windows.Input.Cursors]::Hand
    $okTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonPrimary'])" CornerRadius="8" Padding="16,8">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonPrimaryHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnOk.Template = $okTemplate
    $btnOk.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonPrimaryForeground']))
    $btnOk.FontSize = 13
    $btnOk.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnOk.Content = $ButtonLabel
    $btnOk.Add_Click({ $dlg.Close() })
    $panel.Children.Add($btnOk) | Out-Null

    $border.Child = $panel
    $dlg.Content = $border
    $dlg.ShowDialog() | Out-Null
}

function Show-DATConfirmDialog {
    param (
        [string]$Title = "Confirm",
        [string]$Message,
        [ValidateSet('Success', 'Error', 'Warning', 'Info')]
        [string]$Type = 'Info',
        [string]$ConfirmLabel = 'Yes',
        [string]$CancelLabel = 'No'
    )

    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])

    switch ($Type) {
        'Success' { $iconChar = [string][char]0xE73E; $iconColor = $theme['StatusSuccess'] }
        'Error'   { $iconChar = [string][char]0xEA39; $iconColor = $theme['StatusError'] }
        'Warning' { $iconChar = [string][char]0xE7BA; $iconColor = $theme['StatusWarning'] }
        default   { $iconChar = [string][char]0xE946; $iconColor = $theme['StatusInfo'] }
    }

    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background = [System.Windows.Media.Brushes]::Transparent
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $Window
    $dlg.Width = 440
    $dlg.SizeToContent = 'Height'
    $dlg.Topmost = $true
    $dlg.ResizeMode = 'NoResize'
    $dlg.ShowInTaskbar = $false

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(245, $bgColor.R, $bgColor.G, $bgColor.B))
    $border.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $border.Padding = [System.Windows.Thickness]::new(28, 24, 28, 24)
    $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $border.Effect = $shadow

    $panel = [System.Windows.Controls.StackPanel]::new()

    # Icon
    $iconText = [System.Windows.Controls.TextBlock]::new()
    $iconText.Text = $iconChar
    $iconText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $iconText.FontSize = 28
    $iconText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($iconColor))
    $iconText.HorizontalAlignment = 'Center'
    $iconText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($iconText) | Out-Null

    # Title
    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.Text = $Title
    $titleText.FontSize = 16
    $titleText.FontWeight = [System.Windows.FontWeights]::Bold
    $titleText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $titleText.HorizontalAlignment = 'Center'
    $titleText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($titleText) | Out-Null

    # Message
    $msgText = [System.Windows.Controls.TextBlock]::new()
    $msgText.Text = $Message
    $msgText.FontSize = 13
    $msgText.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $msgText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $msgText.HorizontalAlignment = 'Center'
    $msgText.TextAlignment = [System.Windows.TextAlignment]::Center
    $msgText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 24)
    $panel.Children.Add($msgText) | Out-Null

    # Button row
    $btnPanel = [System.Windows.Controls.Grid]::new()
    $col1 = [System.Windows.Controls.ColumnDefinition]::new()
    $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col2 = [System.Windows.Controls.ColumnDefinition]::new()
    $col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $btnPanel.ColumnDefinitions.Add($col1)
    $btnPanel.ColumnDefinitions.Add($col2)

    # Confirm button (primary)
    $btnConfirm = [System.Windows.Controls.Button]::new()
    $btnConfirm.Height = 36
    $btnConfirm.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnConfirm.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
    $confirmTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonPrimary'])" CornerRadius="8" Padding="16,8">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonPrimaryHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnConfirm.Template = $confirmTemplate
    $btnConfirm.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonPrimaryForeground']))
    $btnConfirm.FontSize = 13
    $btnConfirm.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnConfirm.Content = $ConfirmLabel
    $btnConfirm.Add_Click({ $dlg.Tag = $true; $dlg.Close() })
    [System.Windows.Controls.Grid]::SetColumn($btnConfirm, 0)
    $btnPanel.Children.Add($btnConfirm) | Out-Null

    # Cancel button (secondary)
    $btnCancel = [System.Windows.Controls.Button]::new()
    $btnCancel.Height = 36
    $btnCancel.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnCancel.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
    $cancelTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonSecondary'])" CornerRadius="8" Padding="16,8">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonSecondaryHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnCancel.Template = $cancelTemplate
    $btnCancel.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonSecondaryForeground']))
    $btnCancel.FontSize = 13
    $btnCancel.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnCancel.Content = $CancelLabel
    $btnCancel.Add_Click({ $dlg.Tag = $false; $dlg.Close() })
    [System.Windows.Controls.Grid]::SetColumn($btnCancel, 1)
    $btnPanel.Children.Add($btnCancel) | Out-Null

    $panel.Children.Add($btnPanel) | Out-Null

    $border.Child = $panel
    $dlg.Content = $border
    $dlg.ShowDialog() | Out-Null
    return ($dlg.Tag -eq $true)
}

function Show-DATLoadingSourcesModal {
    <#
    .SYNOPSIS
        Shows a non-modal overlay listing each selected OEM with a live loading/success/error indicator.
        Call Update-DATLoadingSourceStatus to update individual OEM states.
        The modal auto-closes when all OEMs reach 'OK' or 'Error' status, or can be closed early.
    #>
    param (
        [Parameter(Mandatory)][string[]]$OEMs
    )

    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])

    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background = [System.Windows.Media.Brushes]::Transparent
    $dlg.Width = 440
    # Set Owner for centering; fall back to CenterScreen if the main window isn't shown yet
    try {
        $dlg.Owner = $Window
        $dlg.WindowStartupLocation = 'CenterOwner'
    } catch {
        $dlg.WindowStartupLocation = 'CenterScreen'
    }
    $dlg.SizeToContent = 'Height'
    $dlg.Topmost = $true
    $dlg.ResizeMode = 'NoResize'
    $dlg.ShowInTaskbar = $false

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(245, $bgColor.R, $bgColor.G, $bgColor.B))
    $border.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $border.Padding = [System.Windows.Thickness]::new(28, 24, 28, 24)
    $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $border.Effect = $shadow

    $panel = [System.Windows.Controls.StackPanel]::new()

    # Spinner icon
    $iconText = [System.Windows.Controls.TextBlock]::new()
    $iconText.Text = [string][char]0xF16A
    $iconText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $iconText.FontSize = 28
    $iconText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor']))
    $iconText.HorizontalAlignment = 'Center'
    $iconText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($iconText) | Out-Null

    # Title
    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.Text = "Loading Sources"
    $titleText.FontSize = 16
    $titleText.FontWeight = [System.Windows.FontWeights]::Bold
    $titleText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $titleText.HorizontalAlignment = 'Center'
    $titleText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($titleText) | Out-Null

    # Subtitle
    $subtitleText = [System.Windows.Controls.TextBlock]::new()
    $subtitleText.Text = "Downloading and parsing OEM catalogs..."
    $subtitleText.FontSize = 13
    $subtitleText.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $subtitleText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $subtitleText.HorizontalAlignment = 'Center'
    $subtitleText.TextAlignment = [System.Windows.TextAlignment]::Center
    $subtitleText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 24)
    $panel.Children.Add($subtitleText) | Out-Null

    # Per-OEM status rows
    $script:SourceStatusLabels = @{}
    $script:SourceStatusIcons  = @{}

    $loadingBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $fgBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))

    foreach ($oem in $OEMs) {
        $row = [System.Windows.Controls.DockPanel]::new()
        $row.Margin = [System.Windows.Thickness]::new(0, 3, 0, 3)

        # Status icon (spinner initially)
        $statusIcon = [System.Windows.Controls.TextBlock]::new()
        $statusIcon.Text = [string][char]0xF16A  # sync/loading glyph
        $statusIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $statusIcon.FontSize = 14
        $statusIcon.Foreground = $loadingBrush
        $statusIcon.VerticalAlignment = 'Center'
        $statusIcon.Width = 24
        [System.Windows.Controls.DockPanel]::SetDock($statusIcon, 'Left')
        $row.Children.Add($statusIcon) | Out-Null

        # OEM name
        $oemLabel = [System.Windows.Controls.TextBlock]::new()
        $oemLabel.Text = $oem
        $oemLabel.FontSize = 13
        $oemLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
        $oemLabel.Foreground = $fgBrush
        $oemLabel.VerticalAlignment = 'Center'
        $oemLabel.Width = 90
        [System.Windows.Controls.DockPanel]::SetDock($oemLabel, 'Left')
        $row.Children.Add($oemLabel) | Out-Null

        # Status text
        $statusLabel = [System.Windows.Controls.TextBlock]::new()
        $statusLabel.Text = "Waiting..."
        $statusLabel.FontSize = 12
        $statusLabel.Foreground = $loadingBrush
        $statusLabel.VerticalAlignment = 'Center'
        $statusLabel.HorizontalAlignment = 'Right'
        $row.Children.Add($statusLabel) | Out-Null

        $panel.Children.Add($row) | Out-Null

        $script:SourceStatusLabels[$oem] = $statusLabel
        $script:SourceStatusIcons[$oem]  = $statusIcon
    }

    # OEM Links row (always present)
    $oemLinksRow = [System.Windows.Controls.DockPanel]::new()
    $oemLinksRow.Margin = [System.Windows.Thickness]::new(0, 3, 0, 3)
    $oemLinksIcon = [System.Windows.Controls.TextBlock]::new()
    $oemLinksIcon.Text = [string][char]0xF16A
    $oemLinksIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $oemLinksIcon.FontSize = 14
    $oemLinksIcon.Foreground = $loadingBrush
    $oemLinksIcon.VerticalAlignment = 'Center'
    $oemLinksIcon.Width = 24
    [System.Windows.Controls.DockPanel]::SetDock($oemLinksIcon, 'Left')
    $oemLinksRow.Children.Add($oemLinksIcon) | Out-Null
    $oemLinksLabel = [System.Windows.Controls.TextBlock]::new()
    $oemLinksLabel.Text = "OEM Links"
    $oemLinksLabel.FontSize = 13
    $oemLinksLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
    $oemLinksLabel.Foreground = $fgBrush
    $oemLinksLabel.VerticalAlignment = 'Center'
    $oemLinksLabel.Width = 90
    [System.Windows.Controls.DockPanel]::SetDock($oemLinksLabel, 'Left')
    $oemLinksRow.Children.Add($oemLinksLabel) | Out-Null
    $oemLinksStatus = [System.Windows.Controls.TextBlock]::new()
    $oemLinksStatus.Text = "Waiting..."
    $oemLinksStatus.FontSize = 12
    $oemLinksStatus.Foreground = $loadingBrush
    $oemLinksStatus.VerticalAlignment = 'Center'
    $oemLinksStatus.HorizontalAlignment = 'Right'
    $oemLinksRow.Children.Add($oemLinksStatus) | Out-Null
    # Insert OEM Links row at the top of the OEM list (after subtitle)
    $panel.Children.Insert(3, $oemLinksRow)
    $script:SourceStatusLabels['OEMLinks'] = $oemLinksStatus
    $script:SourceStatusIcons['OEMLinks']  = $oemLinksIcon

    # BIOS lookup row
    $biosRow = [System.Windows.Controls.DockPanel]::new()
    $biosRow.Margin = [System.Windows.Thickness]::new(0, 3, 0, 3)
    $biosIcon = [System.Windows.Controls.TextBlock]::new()
    $biosIcon.Text = [string][char]0xF16A
    $biosIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $biosIcon.FontSize = 14
    $biosIcon.Foreground = $loadingBrush
    $biosIcon.VerticalAlignment = 'Center'
    $biosIcon.Width = 24
    [System.Windows.Controls.DockPanel]::SetDock($biosIcon, 'Left')
    $biosRow.Children.Add($biosIcon) | Out-Null
    $biosLabel = [System.Windows.Controls.TextBlock]::new()
    $biosLabel.Text = "BIOS Catalog"
    $biosLabel.FontSize = 13
    $biosLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
    $biosLabel.Foreground = $fgBrush
    $biosLabel.VerticalAlignment = 'Center'
    $biosLabel.Width = 90
    [System.Windows.Controls.DockPanel]::SetDock($biosLabel, 'Left')
    $biosRow.Children.Add($biosLabel) | Out-Null
    $biosStatus = [System.Windows.Controls.TextBlock]::new()
    $biosStatus.Text = "Waiting..."
    $biosStatus.FontSize = 12
    $biosStatus.Foreground = $loadingBrush
    $biosStatus.VerticalAlignment = 'Center'
    $biosStatus.HorizontalAlignment = 'Right'
    $biosRow.Children.Add($biosStatus) | Out-Null
    $panel.Children.Add($biosRow) | Out-Null
    $script:SourceStatusLabels['BIOS'] = $biosStatus
    $script:SourceStatusIcons['BIOS']  = $biosIcon

    $border.Child = $panel
    $dlg.Content = $border

    # Store reference so the refresh timer can update/close it
    $script:LoadingSourcesDlg = $dlg
    $dlg.Show()
}

function Update-DATLoadingSourceStatus {
    <#
    .SYNOPSIS
        Updates the status icon and text for a specific source in the Loading Sources modal.
    #>
    param (
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][ValidateSet('Loading','OK','Error','Cached')]
        [string]$Status,
        [string]$Detail
    )

    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $label = $script:SourceStatusLabels[$Source]
    $icon  = $script:SourceStatusIcons[$Source]
    if ($null -eq $label -or $null -eq $icon) { return }

    switch ($Status) {
        'Loading' {
            $icon.Text = [string][char]0xF16A
            $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor']))
            $label.Text = if ($Detail) { $Detail } else { "Loading..." }
            $label.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor']))
        }
        'OK' {
            $icon.Text = [string][char]0xE73E
            $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusSuccess']))
            $label.Text = if ($Detail) { $Detail } else { "Loaded" }
            $label.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusSuccess']))
        }
        'Cached' {
            $icon.Text = [string][char]0xE73E
            $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusSuccess']))
            $label.Text = if ($Detail) { $Detail } else { "Cached" }
            $label.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusSuccess']))
        }
        'Error' {
            $icon.Text = [string][char]0xEA39
            $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusError']))
            $label.Text = if ($Detail) { $Detail } else { "Failed" }
            $label.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusError']))
        }
    }
}

function Close-DATLoadingSourcesModal {
    <#
    .SYNOPSIS
        Closes the Loading Sources modal if it is open.
    #>
    if ($null -ne $script:LoadingSourcesDlg) {
        try { $script:LoadingSourcesDlg.Close() } catch { }
        $script:LoadingSourcesDlg = $null
    }
}

function Show-DATBuildSummaryDialog {
    <#
    .SYNOPSIS
        Shows a post-build summary modal with per-type package success/fail counts.
    #>
    param (
        [int]$TotalModels,
        [int]$DriverSuccess,
        [int]$BiosSuccess,
        [string]$PackageType = 'Drivers',
        [string]$Elapsed = '',
        [bool]$HadErrors = $false
    )

    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])

    # Overall status
    if ($HadErrors) {
        $iconChar = [string][char]0xE7BA
        $iconColor = $theme['StatusWarning']
        $title = "Build Completed with Errors"
    } else {
        $iconChar = [string][char]0xE73E
        $iconColor = $theme['StatusSuccess']
        $title = "Build Completed Successfully"
    }

    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background = [System.Windows.Media.Brushes]::Transparent
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $Window
    $dlg.Width = 440
    $dlg.SizeToContent = 'Height'
    $dlg.Topmost = $true
    $dlg.ResizeMode = 'NoResize'
    $dlg.ShowInTaskbar = $false

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(245, $bgColor.R, $bgColor.G, $bgColor.B))
    $border.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $border.Padding = [System.Windows.Thickness]::new(28, 24, 28, 24)
    $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $border.Effect = $shadow

    $panel = [System.Windows.Controls.StackPanel]::new()

    # Icon
    $iconText = [System.Windows.Controls.TextBlock]::new()
    $iconText.Text = $iconChar
    $iconText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $iconText.FontSize = 32
    $iconText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($iconColor))
    $iconText.HorizontalAlignment = 'Center'
    $iconText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($iconText) | Out-Null

    # Title
    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.Text = $title
    $titleText.FontSize = 16
    $titleText.FontWeight = [System.Windows.FontWeights]::Bold
    $titleText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $titleText.HorizontalAlignment = 'Center'
    $titleText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $panel.Children.Add($titleText) | Out-Null

    # Summary grid
    $fgBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $dimBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $successBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusSuccess']))
    $errorBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusError']))

    $grid = [System.Windows.Controls.Grid]::new()
    $grid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 20)
    # Columns: Label | Succeeded | Failed
    $col1 = [System.Windows.Controls.ColumnDefinition]::new(); $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col2 = [System.Windows.Controls.ColumnDefinition]::new(); $col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col3 = [System.Windows.Controls.ColumnDefinition]::new(); $col3.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $grid.ColumnDefinitions.Add($col1) | Out-Null
    $grid.ColumnDefinitions.Add($col2) | Out-Null
    $grid.ColumnDefinitions.Add($col3) | Out-Null

    # Build rows based on package type
    $rows = @()
    $showDrivers = $PackageType -in @('Drivers', 'All')
    $showBios = $PackageType -in @('BIOS', 'All')
    if ($showDrivers) {
        $driverFailed = [math]::Max(0, $TotalModels - $DriverSuccess)
        $rows += @{ Label = 'Driver Packages'; Success = $DriverSuccess; Failed = $driverFailed }
    }
    if ($showBios) {
        $biosFailed = [math]::Max(0, $TotalModels - $BiosSuccess)
        $rows += @{ Label = 'BIOS Packages'; Success = $BiosSuccess; Failed = $biosFailed }
    }

    # Header row
    $row0 = [System.Windows.Controls.RowDefinition]::new(); $row0.Height = [System.Windows.GridLength]::new(28)
    $grid.RowDefinitions.Add($row0) | Out-Null
    foreach ($hdr in @(@{Col=1;Text='Succeeded'},@{Col=2;Text='Failed'})) {
        $h = [System.Windows.Controls.TextBlock]::new()
        $h.Text = $hdr.Text
        $h.FontSize = 12
        $h.FontWeight = [System.Windows.FontWeights]::SemiBold
        $h.Foreground = $dimBrush
        $h.HorizontalAlignment = 'Center'
        $h.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetRow($h, 0)
        [System.Windows.Controls.Grid]::SetColumn($h, $hdr.Col)
        $grid.Children.Add($h) | Out-Null
    }

    $rowIndex = 1
    foreach ($r in $rows) {
        $rd = [System.Windows.Controls.RowDefinition]::new(); $rd.Height = [System.Windows.GridLength]::new(32)
        $grid.RowDefinitions.Add($rd) | Out-Null

        # Label
        $lbl = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text = $r.Label
        $lbl.FontSize = 13
        $lbl.Foreground = $fgBrush
        $lbl.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetRow($lbl, $rowIndex)
        [System.Windows.Controls.Grid]::SetColumn($lbl, 0)
        $grid.Children.Add($lbl) | Out-Null

        # Success count
        $suc = [System.Windows.Controls.TextBlock]::new()
        $suc.Text = "$($r.Success)"
        $suc.FontSize = 14
        $suc.FontWeight = [System.Windows.FontWeights]::Bold
        $suc.Foreground = $successBrush
        $suc.HorizontalAlignment = 'Center'
        $suc.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetRow($suc, $rowIndex)
        [System.Windows.Controls.Grid]::SetColumn($suc, 1)
        $grid.Children.Add($suc) | Out-Null

        # Failed count
        $fail = [System.Windows.Controls.TextBlock]::new()
        $fail.Text = "$($r.Failed)"
        $fail.FontSize = 14
        $fail.FontWeight = [System.Windows.FontWeights]::Bold
        $fail.Foreground = if ($r.Failed -gt 0) { $errorBrush } else { $dimBrush }
        $fail.HorizontalAlignment = 'Center'
        $fail.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetRow($fail, $rowIndex)
        [System.Windows.Controls.Grid]::SetColumn($fail, 2)
        $grid.Children.Add($fail) | Out-Null

        $rowIndex++
    }

    # Total models row
    $rdTotal = [System.Windows.Controls.RowDefinition]::new(); $rdTotal.Height = [System.Windows.GridLength]::new(32)
    $grid.RowDefinitions.Add($rdTotal) | Out-Null

    # Separator
    $sep = [System.Windows.Controls.Border]::new()
    $sep.Height = 1
    $sep.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $sep.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
    $sep.VerticalAlignment = 'Top'
    [System.Windows.Controls.Grid]::SetRow($sep, $rowIndex)
    [System.Windows.Controls.Grid]::SetColumnSpan($sep, 3)
    $grid.Children.Add($sep) | Out-Null

    $totalLbl = [System.Windows.Controls.TextBlock]::new()
    $totalLbl.Text = "Models Processed"
    $totalLbl.FontSize = 13
    $totalLbl.FontWeight = [System.Windows.FontWeights]::SemiBold
    $totalLbl.Foreground = $fgBrush
    $totalLbl.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetRow($totalLbl, $rowIndex)
    [System.Windows.Controls.Grid]::SetColumn($totalLbl, 0)
    $grid.Children.Add($totalLbl) | Out-Null

    $totalVal = [System.Windows.Controls.TextBlock]::new()
    $totalVal.Text = "$TotalModels"
    $totalVal.FontSize = 14
    $totalVal.FontWeight = [System.Windows.FontWeights]::Bold
    $totalVal.Foreground = $fgBrush
    $totalVal.HorizontalAlignment = 'Center'
    $totalVal.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetRow($totalVal, $rowIndex)
    [System.Windows.Controls.Grid]::SetColumn($totalVal, 1)
    [System.Windows.Controls.Grid]::SetColumnSpan($totalVal, 2)
    $grid.Children.Add($totalVal) | Out-Null

    $panel.Children.Add($grid) | Out-Null

    # Elapsed time
    if (-not [string]::IsNullOrEmpty($Elapsed)) {
        $elapsedText = [System.Windows.Controls.TextBlock]::new()
        $elapsedText.Text = "Elapsed: $Elapsed"
        $elapsedText.FontSize = 12
        $elapsedText.Foreground = $dimBrush
        $elapsedText.HorizontalAlignment = 'Center'
        $elapsedText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
        $panel.Children.Add($elapsedText) | Out-Null
    }

    # OK button
    $btnOk = [System.Windows.Controls.Button]::new()
    $btnOk.Height = 36
    $btnOk.HorizontalAlignment = 'Stretch'
    $btnOk.Cursor = [System.Windows.Input.Cursors]::Hand
    $okTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonPrimary'])" CornerRadius="8" Padding="16,8">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonPrimaryHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnOk.Template = $okTemplate
    $btnOk.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonPrimaryForeground']))
    $btnOk.FontSize = 13
    $btnOk.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnOk.Content = 'OK'
    $btnOk.Add_Click({ $dlg.Close() })
    $panel.Children.Add($btnOk) | Out-Null

    $border.Child = $panel
    $dlg.Content = $border
    $dlg.ShowDialog() | Out-Null
}

#endregion Themed Dialogs

function Show-DATCustomDriverDialog {
    param (
        [string]$ModelName,
        [string]$ExistingPath
    )

    $script:customDriverResult = $null
    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor  = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])
    $fgColor  = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground'])
    $dimColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder'])
    $accent   = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor'])
    $borderClr = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowBorder'])

    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background = [System.Windows.Media.Brushes]::Transparent
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $Window
    $dlg.Width = 520
    $dlg.SizeToContent = 'Height'
    $dlg.Topmost = $true
    $dlg.ResizeMode = 'NoResize'
    $dlg.ShowInTaskbar = $false

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new($bgColor)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(20)
    $border.Padding = [System.Windows.Thickness]::new(28, 24, 28, 24)
    $border.Effect = [System.Windows.Media.Effects.DropShadowEffect]@{
        BlurRadius = 30; Opacity = 0.4; ShadowDepth = 0
        Color = [System.Windows.Media.Colors]::Black
    }
    $dlg.Content = $border

    $panel = [System.Windows.Controls.StackPanel]::new()
    $border.Child = $panel

    # Icon + title
    $icon = [System.Windows.Controls.TextBlock]::new()
    $icon.Text = [string][char]0xE710
    $icon.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe MDL2 Assets")
    $icon.FontSize = 28
    $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new($accent)
    $icon.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $panel.Children.Add($icon) | Out-Null

    $title = [System.Windows.Controls.TextBlock]::new()
    $title.Text = "Add Custom Drivers — $ModelName"
    $title.FontSize = 16
    $title.FontWeight = [System.Windows.FontWeights]::Bold
    $title.Foreground = [System.Windows.Media.SolidColorBrush]::new($fgColor)
    $title.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $title.TextWrapping = 'Wrap'
    $panel.Children.Add($title) | Out-Null

    # Note
    $note = [System.Windows.Controls.TextBlock]::new()
    $note.Text = "All drivers extracted from the selected source directory will be injected into the created driver package before WIM creation. This does not apply to the 'Download Only' mode."
    $note.FontSize = 12
    $note.TextWrapping = 'Wrap'
    $note.Foreground = [System.Windows.Media.SolidColorBrush]::new($dimColor)
    $note.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $panel.Children.Add($note) | Out-Null

    # Path label
    $pathLabel = [System.Windows.Controls.TextBlock]::new()
    $pathLabel.Text = "Driver Source Directory"
    $pathLabel.FontSize = 12
    $pathLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
    $pathLabel.Foreground = [System.Windows.Media.SolidColorBrush]::new($fgColor)
    $pathLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
    $panel.Children.Add($pathLabel) | Out-Null

    # Path row: TextBox + Browse button
    $pathRow = [System.Windows.Controls.Grid]::new()
    $col1 = [System.Windows.Controls.ColumnDefinition]::new()
    $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col2 = [System.Windows.Controls.ColumnDefinition]::new()
    $col2.Width = [System.Windows.GridLength]::Auto
    $pathRow.ColumnDefinitions.Add($col1)
    $pathRow.ColumnDefinitions.Add($col2)
    $pathRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($pathRow) | Out-Null

    $txtPath = [System.Windows.Controls.TextBox]::new()
    $txtPath.FontSize = 12
    $txtPath.Padding = [System.Windows.Thickness]::new(8, 6, 8, 6)
    $txtPath.VerticalContentAlignment = 'Center'
    $txtPath.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputBackground']))
    $txtPath.Foreground = [System.Windows.Media.SolidColorBrush]::new($fgColor)
    $txtPath.BorderBrush = [System.Windows.Media.SolidColorBrush]::new($borderClr)
    $txtPath.BorderThickness = [System.Windows.Thickness]::new(1)
    if (-not [string]::IsNullOrEmpty($ExistingPath)) { $txtPath.Text = $ExistingPath }
    [System.Windows.Controls.Grid]::SetColumn($txtPath, 0)
    $pathRow.Children.Add($txtPath) | Out-Null

    $btnBrowse = [System.Windows.Controls.Button]::new()
    $btnBrowse.Content = "Browse..."
    $btnBrowse.FontSize = 12
    $btnBrowse.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnBrowse.Padding = [System.Windows.Thickness]::new(12, 6, 12, 6)
    $btnBrowse.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $btnBrowse.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnBrowse.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonPrimaryForeground']))
    $browseTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonPrimary'])" CornerRadius="6" Padding="12,6" TextElement.Foreground="$($theme['ButtonPrimaryForeground'])">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonPrimaryHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnBrowse.Template = $browseTemplate
    [System.Windows.Controls.Grid]::SetColumn($btnBrowse, 1)
    $pathRow.Children.Add($btnBrowse) | Out-Null

    # Validation status panel
    $validPanel = [System.Windows.Controls.StackPanel]::new()
    $validPanel.Orientation = 'Horizontal'
    $validPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $validPanel.Visibility = 'Collapsed'
    $panel.Children.Add($validPanel) | Out-Null

    $validIcon = [System.Windows.Controls.TextBlock]::new()
    $validIcon.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe MDL2 Assets")
    $validIcon.FontSize = 16
    $validIcon.VerticalAlignment = 'Center'
    $validIcon.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $validPanel.Children.Add($validIcon) | Out-Null

    $validText = [System.Windows.Controls.TextBlock]::new()
    $validText.FontSize = 12
    $validText.VerticalAlignment = 'Center'
    $validText.TextWrapping = 'Wrap'
    $validPanel.Children.Add($validText) | Out-Null

    # Validation function
    $validatePath = {
        $path = $txtPath.Text.Trim()
        if ([string]::IsNullOrEmpty($path) -or -not (Test-Path $path -PathType Container)) {
            $validPanel.Visibility = 'Collapsed'
            $btnApply.IsEnabled = $false
            return
        }
        $infFiles = Get-ChildItem -Path $path -Filter '*.inf' -Recurse -File -ErrorAction SilentlyContinue
        $infCount = @($infFiles).Count
        $validPanel.Visibility = 'Visible'
        if ($infCount -gt 0) {
            $validIcon.Text = [string][char]0xE73E  # checkmark
            $validIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString('#2ECC40'))
            $validText.Text = "Valid driver source — $infCount .inf file(s) found"
            $validText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString('#2ECC40'))
            $btnApply.IsEnabled = $true
        } else {
            $validIcon.Text = [string][char]0xE783  # warning
            $validIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString('#E8A035'))
            $validText.Text = "No .inf files found in this directory"
            $validText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString('#E8A035'))
            $btnApply.IsEnabled = $false
        }
    }

    # Browse button
    $btnBrowse.Add_Click({
        $fbd = [System.Windows.Forms.FolderBrowserDialog]::new()
        $fbd.Description = "Select a folder containing driver .inf files"
        $fbd.ShowNewFolderButton = $false
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtPath.Text = $fbd.SelectedPath
            & $validatePath
        }
    })

    # Re-validate when the user types a path manually
    $txtPath.Add_TextChanged({ & $validatePath })

    # Button row
    $btnRow = [System.Windows.Controls.StackPanel]::new()
    $btnRow.Orientation = 'Horizontal'
    $btnRow.HorizontalAlignment = 'Right'
    $panel.Children.Add($btnRow) | Out-Null

    $btnApply = [System.Windows.Controls.Button]::new()
    $btnApply.Content = "Apply"
    $btnApply.FontSize = 13
    $btnApply.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnApply.Height = 36
    $btnApply.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $btnApply.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnApply.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonPrimaryForeground']))
    $applyTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonPrimary'])" CornerRadius="8" Padding="16,8" TextElement.Foreground="$($theme['ButtonPrimaryForeground'])">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonPrimaryHover'])"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="bd" Property="Opacity" Value="0.4"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnApply.Template = $applyTemplate
    $btnApply.IsEnabled = $false
    $btnRow.Children.Add($btnApply) | Out-Null

    $btnCancel = [System.Windows.Controls.Button]::new()
    $btnCancel.Content = "Cancel"
    $btnCancel.FontSize = 13
    $btnCancel.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnCancel.Height = 36
    $btnCancel.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnCancel.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonSecondaryForeground']))
    $cancelTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonSecondary'])" CornerRadius="8" Padding="16,8" TextElement.Foreground="$($theme['ButtonSecondaryForeground'])">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonSecondaryHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnCancel.Template = $cancelTemplate
    $btnRow.Children.Add($btnCancel) | Out-Null

    $btnApply.Add_Click({
        $script:customDriverResult = $txtPath.Text.Trim()
        $dlg.Close()
    })
    $btnCancel.Add_Click({
        $script:customDriverResult = $null
        $dlg.Close()
    })

    # If existing path was provided, run initial validation
    if (-not [string]::IsNullOrEmpty($ExistingPath)) { & $validatePath }

    $dlg.ShowDialog() | Out-Null
    return $script:customDriverResult
}

function Show-DATEntraGroupSearchDialog {
    <#
    .SYNOPSIS
        Modal dialog that searches Entra ID groups and returns the selected group.
    #>
    param (
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][ValidateSet('Available', 'Required')][string]$Intent
    )

    $script:entraGroupResult = $null
    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor   = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])
    $fgColor   = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground'])
    $dimColor  = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder'])
    $accent    = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor'])
    $borderClr = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowBorder'])
    $gridBg    = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['GridBackground'])
    $gridSel   = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['GridSelection'])
    $gridSelFg = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['GridSelectionForeground'])
    $gridAlt   = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['GridAlternate'])
    $gridHdr   = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['GridHeader'])
    $gridHdrFg = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['GridHeaderForeground'])

    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background = [System.Windows.Media.Brushes]::Transparent
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $Window
    $dlg.Width = 750
    $dlg.Height = 660
    $dlg.Topmost = $true
    $dlg.ResizeMode = 'NoResize'
    $dlg.ShowInTaskbar = $false

    $outerBorder = [System.Windows.Controls.Border]::new()
    $outerBorder.Background = [System.Windows.Media.SolidColorBrush]::new($bgColor)
    $outerBorder.CornerRadius = [System.Windows.CornerRadius]::new(20)
    $outerBorder.Padding = [System.Windows.Thickness]::new(28, 24, 28, 24)
    $outerBorder.Effect = [System.Windows.Media.Effects.DropShadowEffect]@{
        BlurRadius = 30; Opacity = 0.4; ShadowDepth = 0
        Color = [System.Windows.Media.Colors]::Black
    }
    $dlg.Content = $outerBorder

    $panel = [System.Windows.Controls.StackPanel]::new()
    $outerBorder.Child = $panel

    # Intent icon + title
    $intentColor = if ($Intent -eq 'Required') {
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusWarning'])
    } else { $accent }
    $intentIcon = if ($Intent -eq 'Required') { [string][char]0xE7BA } else { [string][char]0xE73E }

    $titleIcon = [System.Windows.Controls.TextBlock]::new()
    $titleIcon.Text = $intentIcon
    $titleIcon.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe MDL2 Assets")
    $titleIcon.FontSize = 28
    $titleIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new($intentColor)
    $titleIcon.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $panel.Children.Add($titleIcon) | Out-Null

    $title = [System.Windows.Controls.TextBlock]::new()
    $title.Text = "Assign Package — $Intent"
    $title.FontSize = 16
    $title.FontWeight = [System.Windows.FontWeights]::Bold
    $title.Foreground = [System.Windows.Media.SolidColorBrush]::new($fgColor)
    $title.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
    $panel.Children.Add($title) | Out-Null

    $subtitle = [System.Windows.Controls.TextBlock]::new()
    $subtitle.Text = $AppName
    $subtitle.FontSize = 12
    $subtitle.Foreground = [System.Windows.Media.SolidColorBrush]::new($dimColor)
    $subtitle.TextTrimming = 'CharacterEllipsis'
    $subtitle.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $panel.Children.Add($subtitle) | Out-Null

    # Quick-assign buttons: All Users / All Devices
    $quickLabel = [System.Windows.Controls.TextBlock]::new()
    $quickLabel.Text = "Quick Assign"
    $quickLabel.FontSize = 12
    $quickLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
    $quickLabel.Foreground = [System.Windows.Media.SolidColorBrush]::new($fgColor)
    $quickLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
    $panel.Children.Add($quickLabel) | Out-Null

    $btnSecFg = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonSecondaryForeground'])

    $quickRow = [System.Windows.Controls.StackPanel]::new()
    $quickRow.Orientation = 'Horizontal'
    $quickRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $panel.Children.Add($quickRow) | Out-Null

    $quickBtnTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonSecondary'])" CornerRadius="8"
            Padding="14,8" BorderBrush="$borderClr" BorderThickness="1"
            TextElement.Foreground="$($theme['ButtonSecondaryForeground'])">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonSecondaryHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)

    foreach ($quickEntry in @(
        @{ Label = 'All Users';   Icon = [string][char]0xE716; Id = 'acacacac-9df4-4c7d-9d50-4ef0226f57a9'; Desc = 'Target all licensed users' },
        @{ Label = 'All Devices'; Icon = [string][char]0xE7F4; Id = 'adadadad-808e-44e2-905a-0b7873a8a531'; Desc = 'Target all devices' }
    )) {
        $qStack = [System.Windows.Controls.StackPanel]::new()
        $qStack.Orientation = 'Horizontal'

        $qIcon = [System.Windows.Controls.TextBlock]::new()
        $qIcon.Text = $quickEntry.Icon
        $qIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $qIcon.FontSize = 14
        $qIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new($btnSecFg)
        $qIcon.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
        $qIcon.VerticalAlignment = 'Center'
        $qStack.Children.Add($qIcon) | Out-Null

        $qText = [System.Windows.Controls.TextBlock]::new()
        $qText.Text = $quickEntry.Label
        $qText.FontSize = 12
        $qText.FontWeight = [System.Windows.FontWeights]::SemiBold
        $qText.Foreground = [System.Windows.Media.SolidColorBrush]::new($btnSecFg)
        $qText.VerticalAlignment = 'Center'
        $qStack.Children.Add($qText) | Out-Null

        $qBtn = [System.Windows.Controls.Button]::new()
        $qBtn.Content = $qStack
        $qBtn.Height = 34
        $qBtn.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
        $qBtn.Cursor = [System.Windows.Input.Cursors]::Hand
        $qBtn.Template = $quickBtnTemplate
        $qBtn.Tag = [PSCustomObject]@{
            DisplayName = $quickEntry.Label
            Description = $quickEntry.Desc
            GroupType   = 'Virtual'
            ObjectId    = $quickEntry.Id
        }
        $qBtn.Add_Click({
            param($s, $e)
            $script:entraGroupResult = @{
                GroupId   = $s.Tag.ObjectId
                GroupName = $s.Tag.DisplayName
                GroupType = $s.Tag.GroupType
                Intent    = $Intent
            }
            $dlg.Close()
        })
        $quickRow.Children.Add($qBtn) | Out-Null
    }

    # Search label
    $searchLabel = [System.Windows.Controls.TextBlock]::new()
    $searchLabel.Text = "Search Entra ID Groups"
    $searchLabel.FontSize = 12
    $searchLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
    $searchLabel.Foreground = [System.Windows.Media.SolidColorBrush]::new($fgColor)
    $searchLabel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
    $panel.Children.Add($searchLabel) | Out-Null

    # Search row: TextBox + Search button
    $searchRow = [System.Windows.Controls.Grid]::new()
    $sCol1 = [System.Windows.Controls.ColumnDefinition]::new()
    $sCol1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $sCol2 = [System.Windows.Controls.ColumnDefinition]::new()
    $sCol2.Width = [System.Windows.GridLength]::Auto
    $searchRow.ColumnDefinitions.Add($sCol1)
    $searchRow.ColumnDefinitions.Add($sCol2)
    $searchRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($searchRow) | Out-Null

    $txtSearch = [System.Windows.Controls.TextBox]::new()
    $txtSearch.FontSize = 12
    $txtSearch.Padding = [System.Windows.Thickness]::new(8, 6, 8, 6)
    $txtSearch.VerticalContentAlignment = 'Center'
    $txtSearch.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputBackground']))
    $txtSearch.Foreground = [System.Windows.Media.SolidColorBrush]::new($fgColor)
    $txtSearch.BorderBrush = [System.Windows.Media.SolidColorBrush]::new($borderClr)
    $txtSearch.BorderThickness = [System.Windows.Thickness]::new(1)
    [System.Windows.Controls.Grid]::SetColumn($txtSearch, 0)
    $searchRow.Children.Add($txtSearch) | Out-Null

    $btnSearch = [System.Windows.Controls.Button]::new()
    $btnSearch.Content = "Search"
    $btnSearch.FontSize = 12
    $btnSearch.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnSearch.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
    $btnSearch.Cursor = [System.Windows.Input.Cursors]::Hand
    $searchBtnTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonPrimary'])" CornerRadius="6" Padding="12,6" TextElement.Foreground="$($theme['ButtonPrimaryForeground'])">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonPrimaryHover'])"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="bd" Property="Opacity" Value="0.4"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnSearch.Template = $searchBtnTemplate
    [System.Windows.Controls.Grid]::SetColumn($btnSearch, 1)
    $searchRow.Children.Add($btnSearch) | Out-Null

    # Status text
    $txtStatus = [System.Windows.Controls.TextBlock]::new()
    $txtStatus.FontSize = 11
    $txtStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new($dimColor)
    $txtStatus.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
    $txtStatus.Text = "Type a group name and press Search"
    $panel.Children.Add($txtStatus) | Out-Null

    # Results ListView
    $listGroups = [System.Windows.Controls.ListView]::new()
    $listGroups.Height = 220
    $listGroups.Background = [System.Windows.Media.SolidColorBrush]::new($gridBg)
    $listGroups.Foreground = [System.Windows.Media.SolidColorBrush]::new($fgColor)
    $listGroups.BorderBrush = [System.Windows.Media.SolidColorBrush]::new($borderClr)
    $listGroups.BorderThickness = [System.Windows.Thickness]::new(1)
    $listGroups.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)

    # GridView columns
    $gridView = [System.Windows.Controls.GridView]::new()
    $colName = [System.Windows.Controls.GridViewColumn]::new()
    $colName.Header = "Group Name"
    $colName.Width = 280
    $colName.DisplayMemberBinding = [System.Windows.Data.Binding]::new("DisplayName")
    $gridView.Columns.Add($colName)

    $colDesc = [System.Windows.Controls.GridViewColumn]::new()
    $colDesc.Header = "Description"
    $colDesc.Width = 310
    $colDesc.DisplayMemberBinding = [System.Windows.Data.Binding]::new("Description")
    $gridView.Columns.Add($colDesc)

    $colType = [System.Windows.Controls.GridViewColumn]::new()
    $colType.Header = "Type"
    $colType.Width = 80
    $colType.DisplayMemberBinding = [System.Windows.Data.Binding]::new("GroupType")
    $gridView.Columns.Add($colType)

    # Style column headers with custom template to match ModernColumnHeader
    $colHeaderStyle = [System.Windows.Markup.XamlReader]::Parse(@"
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
       TargetType="GridViewColumnHeader">
    <Setter Property="Background" Value="$($theme['GridHeader'])"/>
    <Setter Property="Foreground" Value="$($theme['GridHeaderForeground'])"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="GridViewColumnHeader">
                <Border x:Name="bd" Background="{TemplateBinding Background}"
                        BorderBrush="$($theme['WindowBorder'])" BorderThickness="0,0,1,1"
                        Padding="10,8">
                    <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="Left"/>
                </Border>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="bd" Property="Background" Value="$($theme['SidebarHover'])"/>
                    </Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>
"@)
    $listGroups.Resources.Add([type]'System.Windows.Controls.GridViewColumnHeader', $colHeaderStyle)

    # Style ListViewItems with custom template to match ModernDataGridRow
    $itemStyle = [System.Windows.Markup.XamlReader]::Parse(@"
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
       TargetType="ListViewItem">
    <Setter Property="Background" Value="$($theme['GridBackground'])"/>
    <Setter Property="Foreground" Value="$($theme['WindowForeground'])"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
    <Setter Property="Padding" Value="0"/>
    <Setter Property="Margin" Value="0"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="Template">
        <Setter.Value>
            <ControlTemplate TargetType="ListViewItem">
                <Border x:Name="bd" Background="{TemplateBinding Background}"
                        BorderThickness="0" Padding="0" SnapsToDevicePixels="True">
                    <GridViewRowPresenter VerticalAlignment="Center"
                                          Margin="0,6,0,6"/>
                </Border>
                <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="bd" Property="Background" Value="$($theme['SidebarHover'])"/>
                    </Trigger>
                    <Trigger Property="IsSelected" Value="True">
                        <Setter TargetName="bd" Property="Background" Value="$($theme['GridSelection'])"/>
                        <Setter Property="Foreground" Value="$($theme['GridSelectionForeground'])"/>
                    </Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>
"@)
    $listGroups.ItemContainerStyle = $itemStyle
    $listGroups.AlternationCount = 2

    # Alternating row trigger (applied via AlternationIndex)
    $altTrigger = [System.Windows.Trigger]::new()
    $altTrigger.Property = [System.Windows.Controls.ItemsControl]::AlternationIndexProperty
    $altTrigger.Value = 1
    $altTrigger.Setters.Add([System.Windows.Setter]::new(
        [System.Windows.Controls.Control]::BackgroundProperty,
        [System.Windows.Media.SolidColorBrush]::new($gridAlt)))
    $itemStyle.Triggers.Add($altTrigger)

    # Themed scrollbar styles matching the main tool
    $scrollStyles = [System.Windows.Markup.XamlReader]::Parse(@"
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Style x:Key="DlgScrollThumb" TargetType="Thumb">
        <Setter Property="SnapsToDevicePixels" Value="True"/>
        <Setter Property="OverridesDefaultStyle" Value="True"/>
        <Setter Property="IsTabStop" Value="False"/>
        <Setter Property="Focusable" Value="False"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Thumb">
                    <Border x:Name="thumbBorder" CornerRadius="5"
                            Background="$($theme['ScrollThumb'])" Margin="1"/>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="thumbBorder" Property="Background" Value="$($theme['ScrollThumbHover'])"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style x:Key="DlgScrollTrackBtn" TargetType="RepeatButton">
        <Setter Property="SnapsToDevicePixels" Value="True"/>
        <Setter Property="OverridesDefaultStyle" Value="True"/>
        <Setter Property="IsTabStop" Value="False"/>
        <Setter Property="Focusable" Value="False"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="RepeatButton">
                    <Border Background="Transparent"/>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <ControlTemplate x:Key="DlgVertSB" TargetType="ScrollBar">
        <Border Background="$($theme['ScrollTrack'])" CornerRadius="5" Width="10">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.DecreaseRepeatButton>
                    <RepeatButton Style="{StaticResource DlgScrollTrackBtn}" Command="ScrollBar.PageUpCommand"/>
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                    <Thumb Style="{StaticResource DlgScrollThumb}"/>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                    <RepeatButton Style="{StaticResource DlgScrollTrackBtn}" Command="ScrollBar.PageDownCommand"/>
                </Track.IncreaseRepeatButton>
            </Track>
        </Border>
    </ControlTemplate>
    <ControlTemplate x:Key="DlgHorizSB" TargetType="ScrollBar">
        <Border Background="$($theme['ScrollTrack'])" CornerRadius="5" Height="10">
            <Track x:Name="PART_Track" IsDirectionReversed="False">
                <Track.DecreaseRepeatButton>
                    <RepeatButton Style="{StaticResource DlgScrollTrackBtn}" Command="ScrollBar.PageLeftCommand"/>
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                    <Thumb Style="{StaticResource DlgScrollThumb}"/>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                    <RepeatButton Style="{StaticResource DlgScrollTrackBtn}" Command="ScrollBar.PageRightCommand"/>
                </Track.IncreaseRepeatButton>
            </Track>
        </Border>
    </ControlTemplate>
    <Style TargetType="ScrollBar">
        <Setter Property="SnapsToDevicePixels" Value="True"/>
        <Setter Property="OverridesDefaultStyle" Value="True"/>
        <Style.Triggers>
            <Trigger Property="Orientation" Value="Vertical">
                <Setter Property="Width" Value="6"/>
                <Setter Property="Height" Value="Auto"/>
                <Setter Property="Template" Value="{StaticResource DlgVertSB}"/>
            </Trigger>
            <Trigger Property="Orientation" Value="Horizontal">
                <Setter Property="Width" Value="Auto"/>
                <Setter Property="Height" Value="6"/>
                <Setter Property="Template" Value="{StaticResource DlgHorizSB}"/>
            </Trigger>
        </Style.Triggers>
    </Style>
</ResourceDictionary>
"@)
    $listGroups.Resources.MergedDictionaries.Add($scrollStyles)

    $listGroups.View = $gridView
    $panel.Children.Add($listGroups) | Out-Null

    # Selected group info
    $txtSelected = [System.Windows.Controls.TextBlock]::new()
    $txtSelected.FontSize = 11
    $txtSelected.Foreground = [System.Windows.Media.SolidColorBrush]::new($dimColor)
    $txtSelected.TextWrapping = 'Wrap'
    $txtSelected.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $txtSelected.Text = "No group selected"
    $panel.Children.Add($txtSelected) | Out-Null

    # Button row
    $btnRow = [System.Windows.Controls.StackPanel]::new()
    $btnRow.Orientation = 'Horizontal'
    $btnRow.HorizontalAlignment = 'Right'
    $panel.Children.Add($btnRow) | Out-Null

    $btnAssign = [System.Windows.Controls.Button]::new()
    $btnAssign.Content = "Assign"
    $btnAssign.FontSize = 13
    $btnAssign.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnAssign.Height = 36
    $btnAssign.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $btnAssign.Cursor = [System.Windows.Input.Cursors]::Hand
    $assignBtnBg = if ($Intent -eq 'Required') { $theme['StatusWarning'] } else { $theme['ButtonPrimary'] }
    $assignBtnHover = if ($Intent -eq 'Required') { $theme['ButtonDangerHover'] } else { $theme['ButtonPrimaryHover'] }
    $assignTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$assignBtnBg" CornerRadius="8" Padding="16,8" TextElement.Foreground="$($theme['ButtonPrimaryForeground'])">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$assignBtnHover"/>
        </Trigger>
        <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="bd" Property="Opacity" Value="0.4"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnAssign.Template = $assignTemplate
    $btnAssign.IsEnabled = $false
    $btnRow.Children.Add($btnAssign) | Out-Null

    $btnDlgCancel = [System.Windows.Controls.Button]::new()
    $btnDlgCancel.Content = "Cancel"
    $btnDlgCancel.FontSize = 13
    $btnDlgCancel.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnDlgCancel.Height = 36
    $btnDlgCancel.Cursor = [System.Windows.Input.Cursors]::Hand
    $cancelBtnTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonSecondary'])" CornerRadius="8" Padding="16,8" TextElement.Foreground="$($theme['ButtonSecondaryForeground'])">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonSecondaryHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnDlgCancel.Template = $cancelBtnTemplate
    $btnRow.Children.Add($btnDlgCancel) | Out-Null

    # === Event Handlers ===

    # Track selected group
    $script:selectedGroup = $null

    $listGroups.Add_SelectionChanged({
        $item = $listGroups.SelectedItem
        if ($null -ne $item) {
            $script:selectedGroup = $item
            $typeLabel = $item.GroupType
            $txtSelected.Text = "Selected: $($item.DisplayName) ($typeLabel) — $($item.ObjectId)"
            $txtSelected.Foreground = [System.Windows.Media.SolidColorBrush]::new($accent)
            $btnAssign.IsEnabled = $true
        } else {
            $script:selectedGroup = $null
            $txtSelected.Text = "No group selected"
            $txtSelected.Foreground = [System.Windows.Media.SolidColorBrush]::new($dimColor)
            $btnAssign.IsEnabled = $false
        }
    })

    # Search handler
    $doSearch = {
        $query = $txtSearch.Text.Trim()
        if ($query.Length -lt 2) {
            $txtStatus.Text = "Please enter at least 2 characters"
            $txtStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusWarning']))
            return
        }

        $txtStatus.Text = "Searching..."
        $txtStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new($dimColor)

        # Force UI update
        [System.Windows.Forms.Application]::DoEvents()

        try {
            $groups = Search-DATEntraGroups -SearchText $query
            $listGroups.Items.Clear()
            $script:selectedGroup = $null
            $btnAssign.IsEnabled = $false
            $txtSelected.Text = "No group selected"
            $txtSelected.Foreground = [System.Windows.Media.SolidColorBrush]::new($dimColor)

            # Inject "All Users" and "All Devices" virtual entries when the search matches
            $virtualEntries = @(
                @{ DisplayName = 'All Users';   Description = 'Target all licensed users'; GroupType = 'Virtual'; ObjectId = 'acacacac-9df4-4c7d-9d50-4ef0226f57a9' },
                @{ DisplayName = 'All Devices'; Description = 'Target all devices';        GroupType = 'Virtual'; ObjectId = 'adadadad-808e-44e2-905a-0b7873a8a531' }
            )
            foreach ($v in $virtualEntries) {
                if ($v.DisplayName -like "*$query*") {
                    $listGroups.Items.Add([PSCustomObject]$v) | Out-Null
                }
            }

            if ($null -ne $groups -and @($groups).Count -gt 0) {
                foreach ($g in @($groups)) {
                    $groupType = if ($g.groupTypes -contains 'DynamicMembership') { 'Dynamic' }
                                 elseif ($g.securityEnabled) { 'Security' }
                                 elseif ($g.mailEnabled) { 'M365' }
                                 else { 'Other' }
                    $listGroups.Items.Add([PSCustomObject]@{
                        DisplayName = $g.displayName
                        Description = if ($g.description) { $g.description } else { '-' }
                        GroupType   = $groupType
                        ObjectId    = $g.id
                    }) | Out-Null
                }
            }

            $totalCount = $listGroups.Items.Count
            if ($totalCount -eq 0) {
                $txtStatus.Text = "No groups found matching '$query'"
                $txtStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusWarning']))
                return
            }

            $txtStatus.Text = "$totalCount group(s) found"
            $txtStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusSuccess']))
        } catch {
            $txtStatus.Text = "Search failed: $($_.Exception.Message)"
            $txtStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusError']))
        }
    }

    $btnSearch.Add_Click({ & $doSearch })

    # Auto-search: fire after 2 seconds of typing inactivity
    $autoSearchTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $autoSearchTimer.Interval = [TimeSpan]::FromSeconds(2)
    $autoSearchTimer.Add_Tick({
        $autoSearchTimer.Stop()
        if ($txtSearch.Text.Trim().Length -ge 2) { & $doSearch }
    })
    $txtSearch.Add_TextChanged({
        $autoSearchTimer.Stop()
        if ($txtSearch.Text.Trim().Length -ge 2) {
            $txtStatus.Text = "Searching in 2s..."
            $txtStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new($dimColor)
            $autoSearchTimer.Start()
        }
    })
    $dlg.Add_Closed({ $autoSearchTimer.Stop() })

    # Enter key triggers search immediately
    $txtSearch.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq 'Return') { $autoSearchTimer.Stop(); & $doSearch; $e.Handled = $true }
    })

    $btnAssign.Add_Click({
        if ($null -ne $script:selectedGroup) {
            $script:entraGroupResult = @{
                GroupId     = $script:selectedGroup.ObjectId
                GroupName   = $script:selectedGroup.DisplayName
                GroupType   = $script:selectedGroup.GroupType
                Intent      = $Intent
            }
            $dlg.Close()
        }
    })

    $btnDlgCancel.Add_Click({
        $script:entraGroupResult = $null
        $dlg.Close()
    })

    $dlg.ShowDialog() | Out-Null
    return $script:entraGroupResult
}

function Show-DATPackageRetentionModal {
    <#
    .SYNOPSIS
        Shows a modal that runs Invoke-DATPackageRetention in the background, lists
        what was deleted, then auto-closes on completion.
    #>
    param (
        [Parameter(Mandatory)][string[]]$ModelKeys,   # e.g. "OEM|Model|OS|Arch|PackageType"
        [int]$RetainCount = 0,
        [string]$SiteServer,
        [string]$SiteCode,
        [switch]$Intune
    )

    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])

    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle      = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background       = [System.Windows.Media.Brushes]::Transparent
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner            = $Window
    $dlg.Width            = 520
    $dlg.SizeToContent    = 'Height'
    $dlg.Topmost          = $true
    $dlg.ResizeMode       = 'NoResize'
    $dlg.ShowInTaskbar    = $false

    $border = [System.Windows.Controls.Border]::new()
    $border.Background    = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(245, $bgColor.R, $bgColor.G, $bgColor.B))
    $border.CornerRadius  = [System.Windows.CornerRadius]::new(20)
    $border.Padding       = [System.Windows.Thickness]::new(28, 24, 28, 24)
    $border.BorderBrush   = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius    = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color         = [System.Windows.Media.Colors]::Black
    $border.Effect        = $shadow

    $panel = [System.Windows.Controls.StackPanel]::new()

    # Icon
    $iconText = [System.Windows.Controls.TextBlock]::new()
    $iconText.Text        = [string][char]0xE74D   # Delete / bin icon
    $iconText.FontFamily  = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $iconText.FontSize    = 32
    $iconText.Foreground  = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusWarning']))
    $iconText.HorizontalAlignment = 'Center'
    $iconText.Margin      = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($iconText) | Out-Null

    # Title
    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.Text       = 'Cleaning Up Superseded Packages'
    $titleText.FontSize   = 16
    $titleText.FontWeight = [System.Windows.FontWeights]::Bold
    $titleText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $titleText.HorizontalAlignment = 'Center'
    $titleText.Margin     = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $panel.Children.Add($titleText) | Out-Null

    # Sub-title
    $subText = [System.Windows.Controls.TextBlock]::new()
    $subText.Text         = 'Removing older versions. This may take a moment...'
    $subText.FontSize     = 12
    $subText.Foreground   = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $subText.HorizontalAlignment = 'Center'
    $subText.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $subText.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $panel.Children.Add($subText) | Out-Null

    # Progress ring (infinite spinner)
    $spinner = [System.Windows.Controls.ProgressBar]::new()
    $spinner.IsIndeterminate = $true
    $spinner.Height   = 4
    $spinner.Margin   = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $spinner.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor']))
    $panel.Children.Add($spinner) | Out-Null

    # Results list (hidden until complete)
    $resultsPanel = [System.Windows.Controls.StackPanel]::new()
    $resultsPanel.Visibility = 'Collapsed'
    $resultsPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $panel.Children.Add($resultsPanel) | Out-Null

    # Close button (hidden until complete)
    $btnClose = [System.Windows.Controls.Button]::new()
    $btnClose.Height     = 34
    $btnClose.Width      = 100
    $btnClose.HorizontalAlignment = 'Center'
    $btnClose.Visibility = 'Collapsed'
    $btnClose.Cursor     = [System.Windows.Input.Cursors]::Hand
    $btnClose.BorderThickness = [System.Windows.Thickness]::new(0)
    $btnCloseXaml = @"
<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
                 xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
                 TargetType='Button'>
    <Border x:Name='bd' Background='$($theme['ButtonPrimary'])' CornerRadius='8' Padding='16,8'>
        <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property='IsMouseOver' Value='True'>
            <Setter TargetName='bd' Property='Background' Value='$($theme['ButtonPrimaryHover'])'/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@
    $btnClose.Template = [System.Windows.Markup.XamlReader]::Parse($btnCloseXaml)
    $btnCloseTb = [System.Windows.Controls.TextBlock]::new()
    $btnCloseTb.Text = 'Close'
    $btnCloseTb.FontSize = 13
    $btnCloseTb.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnCloseTb.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonPrimaryForeground']))
    $btnClose.Content = $btnCloseTb
    $btnClose.Add_Click({ $dlg.Close() })
    $panel.Children.Add($btnClose) | Out-Null

    $border.Child  = $panel
    $dlg.Content   = $border

    # Run retention in a background runspace so the UI stays responsive
    $dlg.Add_ContentRendered({
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.ApartmentState = 'STA'
        $rs.ThreadOptions  = 'ReuseThread'
        $rs.Open()
        $rs.SessionStateProxy.SetVariable('ModelKeys',   $ModelKeys)
        $rs.SessionStateProxy.SetVariable('RetainCount', $RetainCount)
        $rs.SessionStateProxy.SetVariable('SiteServer',  $SiteServer)
        $rs.SessionStateProxy.SetVariable('SiteCode',    $SiteCode)
        $rs.SessionStateProxy.SetVariable('RunIntune',   $Intune.IsPresent)
        # Pass the module path so the runspace can import the core module
        $rs.SessionStateProxy.SetVariable('CoreModulePath',
            (Get-Module -Name DriverAutomationToolCore).Path)

        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript({
            Import-Module $CoreModulePath -Force -ErrorAction Stop
            $allResults = [System.Collections.Generic.List[pscustomobject]]::new()
            foreach ($key in $ModelKeys) {
                $parts = $key -split '\|'
                $invokeParams = @{
                    OEM         = $parts[0]
                    Model       = $parts[1]
                    OS          = $parts[2]
                    Architecture= if ($parts.Count -gt 3) { $parts[3] } else { 'x64' }
                    PackageType = if ($parts.Count -gt 4) { $parts[4] } else { 'Drivers' }
                    RetainCount = $RetainCount
                }
                if ($SiteServer -and $SiteCode) {
                    $invokeParams['SiteServer'] = $SiteServer
                    $invokeParams['SiteCode']   = $SiteCode
                }
                if ($RunIntune) { $invokeParams['Intune'] = $true }
                $r = Invoke-DATPackageRetention @invokeParams
                foreach ($item in $r) { $allResults.Add($item) }
            }
            return $allResults.ToArray()
        })

        $asyncResult = $ps.BeginInvoke()

        # Poll every 500 ms on the Dispatcher
        $pollTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $pollTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $pollTimer.Add_Tick({
            if ($asyncResult.IsCompleted) {
                $pollTimer.Stop()
                $retentionResults = @()
                try { $retentionResults = $ps.EndInvoke($asyncResult) } catch { }
                try { $ps.Dispose(); $rs.Dispose() } catch { }

                $spinner.Visibility = 'Collapsed'

                if ($retentionResults.Count -eq 0) {
                    $noAction = [System.Windows.Controls.TextBlock]::new()
                    $noAction.Text      = 'No superseded packages found to remove.'
                    $noAction.FontSize  = 12
                    $noAction.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
                    $noAction.HorizontalAlignment = 'Center'
                    $noAction.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
                    $resultsPanel.Children.Add($noAction) | Out-Null
                } else {
                    $subText.Text = "$($retentionResults.Count) package(s) processed."
                    foreach ($r in $retentionResults) {
                        $row = [System.Windows.Controls.Grid]::new()
                        $col0 = [System.Windows.Controls.ColumnDefinition]::new(); $col0.Width = [System.Windows.GridLength]::Auto
                        $col1 = [System.Windows.Controls.ColumnDefinition]::new(); $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
                        $col2 = [System.Windows.Controls.ColumnDefinition]::new(); $col2.Width = [System.Windows.GridLength]::Auto
                        $row.ColumnDefinitions.Add($col0); $row.ColumnDefinitions.Add($col1); $row.ColumnDefinitions.Add($col2)
                        $row.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)

                        $statusIcon = [System.Windows.Controls.TextBlock]::new()
                        $statusIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
                        $statusIcon.FontSize   = 12
                        $statusIcon.Margin     = [System.Windows.Thickness]::new(0, 0, 8, 0)
                        $statusIcon.VerticalAlignment = 'Center'
                        if ($r.Action -eq 'Deleted') {
                            $statusIcon.Text = [string][char]0xE73E
                            $statusIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusSuccess']))
                        } else {
                            $statusIcon.Text = [string][char]0xEA39
                            $statusIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusError']))
                        }
                        [System.Windows.Controls.Grid]::SetColumn($statusIcon, 0)
                        $row.Children.Add($statusIcon) | Out-Null

                        $nameBlock = [System.Windows.Controls.TextBlock]::new()
                        $nameBlock.Text      = "$($r.Name) v$($r.Version)"
                        $nameBlock.FontSize  = 12
                        $nameBlock.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                            [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
                        $nameBlock.TextTrimming = 'CharacterEllipsis'
                        $nameBlock.VerticalAlignment = 'Center'
                        [System.Windows.Controls.Grid]::SetColumn($nameBlock, 1)
                        $row.Children.Add($nameBlock) | Out-Null

                        $platBlock = [System.Windows.Controls.TextBlock]::new()
                        $platBlock.Text     = $r.Platform
                        $platBlock.FontSize = 11
                        $platBlock.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                            [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
                        $platBlock.Margin   = [System.Windows.Thickness]::new(8, 0, 0, 0)
                        $platBlock.VerticalAlignment = 'Center'
                        [System.Windows.Controls.Grid]::SetColumn($platBlock, 2)
                        $row.Children.Add($platBlock) | Out-Null

                        $resultsPanel.Children.Add($row) | Out-Null
                    }
                }

                $resultsPanel.Visibility = 'Visible'
                $btnClose.Visibility     = 'Visible'
                $dlg.SizeToContent       = [System.Windows.SizeToContent]::Height
            }
        })
        $pollTimer.Start()
    })

    $dlg.ShowDialog() | Out-Null
}

function Show-DATCustomBuildCompleteDialog {
    param (
        [int]$DriverCount,
        [string]$WimSize,
        [string]$PackagePath
    )

    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])

    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background = [System.Windows.Media.Brushes]::Transparent
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $Window
    $dlg.Width = 440
    $dlg.SizeToContent = 'Height'
    $dlg.Topmost = $true
    $dlg.ResizeMode = 'NoResize'
    $dlg.ShowInTaskbar = $false

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(245, $bgColor.R, $bgColor.G, $bgColor.B))
    $border.CornerRadius = [System.Windows.CornerRadius]::new(20)
    $border.Padding = [System.Windows.Thickness]::new(28, 24, 28, 24)
    $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $border.Effect = $shadow

    $panel = [System.Windows.Controls.StackPanel]::new()

    # Success icon
    $iconText = [System.Windows.Controls.TextBlock]::new()
    $iconText.Text = [string][char]0xE73E
    $iconText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $iconText.FontSize = 32
    $iconText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusSuccess']))
    $iconText.HorizontalAlignment = 'Center'
    $iconText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($iconText) | Out-Null

    # Title
    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.Text = "Package Created Successfully"
    $titleText.FontSize = 16
    $titleText.FontWeight = [System.Windows.FontWeights]::Bold
    $titleText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $titleText.HorizontalAlignment = 'Center'
    $titleText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 20)
    $panel.Children.Add($titleText) | Out-Null

    # Details grid
    $detailGrid = [System.Windows.Controls.Grid]::new()
    $detailGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 24)
    $colLabel = [System.Windows.Controls.ColumnDefinition]::new()
    $colLabel.Width = [System.Windows.GridLength]::new(120)
    $colValue = [System.Windows.Controls.ColumnDefinition]::new()
    $colValue.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $detailGrid.ColumnDefinitions.Add($colLabel)
    $detailGrid.ColumnDefinitions.Add($colValue)
    $row1 = [System.Windows.Controls.RowDefinition]::new(); $row1.Height = [System.Windows.GridLength]::Auto
    $row2 = [System.Windows.Controls.RowDefinition]::new(); $row2.Height = [System.Windows.GridLength]::Auto
    $detailGrid.RowDefinitions.Add($row1)
    $detailGrid.RowDefinitions.Add($row2)

    $lblDrivers = [System.Windows.Controls.TextBlock]::new()
    $lblDrivers.Text = "Drivers Included"
    $lblDrivers.FontSize = 13
    $lblDrivers.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $lblDrivers.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    [System.Windows.Controls.Grid]::SetRow($lblDrivers, 0)
    [System.Windows.Controls.Grid]::SetColumn($lblDrivers, 0)
    $detailGrid.Children.Add($lblDrivers) | Out-Null

    $valDrivers = [System.Windows.Controls.TextBlock]::new()
    $valDrivers.Text = "$DriverCount"
    $valDrivers.FontSize = 13
    $valDrivers.FontWeight = [System.Windows.FontWeights]::SemiBold
    $valDrivers.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $valDrivers.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    [System.Windows.Controls.Grid]::SetRow($valDrivers, 0)
    [System.Windows.Controls.Grid]::SetColumn($valDrivers, 1)
    $detailGrid.Children.Add($valDrivers) | Out-Null

    $lblWim = [System.Windows.Controls.TextBlock]::new()
    $lblWim.Text = "WIM Size"
    $lblWim.FontSize = 13
    $lblWim.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    [System.Windows.Controls.Grid]::SetRow($lblWim, 1)
    [System.Windows.Controls.Grid]::SetColumn($lblWim, 0)
    $detailGrid.Children.Add($lblWim) | Out-Null

    $valWim = [System.Windows.Controls.TextBlock]::new()
    $valWim.Text = "$WimSize MB"
    $valWim.FontSize = 13
    $valWim.FontWeight = [System.Windows.FontWeights]::SemiBold
    $valWim.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    [System.Windows.Controls.Grid]::SetRow($valWim, 1)
    [System.Windows.Controls.Grid]::SetColumn($valWim, 1)
    $detailGrid.Children.Add($valWim) | Out-Null

    $panel.Children.Add($detailGrid) | Out-Null

    # Button row
    $btnGrid = [System.Windows.Controls.Grid]::new()
    $bc1 = [System.Windows.Controls.ColumnDefinition]::new(); $bc1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $bc2 = [System.Windows.Controls.ColumnDefinition]::new(); $bc2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $btnGrid.ColumnDefinitions.Add($bc1)
    $btnGrid.ColumnDefinitions.Add($bc2)

    # Open Location button
    $btnOpen = [System.Windows.Controls.Button]::new()
    $btnOpen.Height = 36
    $btnOpen.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
    $btnOpen.Cursor = [System.Windows.Input.Cursors]::Hand
    $openTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonPrimary'])" CornerRadius="8" Padding="16,8">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonPrimaryHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnOpen.Template = $openTemplate
    $btnOpen.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonPrimaryForeground']))
    $btnOpen.FontSize = 13
    $btnOpen.FontWeight = [System.Windows.FontWeights]::SemiBold

    $openContent = [System.Windows.Controls.TextBlock]::new()
    $openIcon = [System.Windows.Documents.Run]::new([string][char]0xE838)
    $openIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $openContent.Inlines.Add($openIcon)
    $openContent.Inlines.Add([System.Windows.Documents.Run]::new("  Open Location"))
    $btnOpen.Content = $openContent

    [System.Windows.Controls.Grid]::SetColumn($btnOpen, 0)
    $btnOpen.Add_Click({
        if (Test-Path $PackagePath) {
            Start-Process explorer.exe -ArgumentList "`"$PackagePath`""
        }
        $dlg.Close()
    }.GetNewClosure())
    $btnGrid.Children.Add($btnOpen) | Out-Null

    # Close button
    $btnClose = [System.Windows.Controls.Button]::new()
    $btnClose.Height = 36
    $btnClose.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
    $btnClose.Cursor = [System.Windows.Input.Cursors]::Hand
    $closeTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonSecondary'])" CornerRadius="8" Padding="16,8">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonSecondaryHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnClose.Template = $closeTemplate
    $btnClose.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonSecondaryForeground']))
    $btnClose.FontSize = 13
    $btnClose.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnClose.Content = "Close"
    [System.Windows.Controls.Grid]::SetColumn($btnClose, 1)
    $btnClose.Add_Click({ $dlg.Close() })
    $btnGrid.Children.Add($btnClose) | Out-Null

    $panel.Children.Add($btnGrid) | Out-Null
    $border.Child = $panel
    $dlg.Content = $border

    $dlg.ShowDialog() | Out-Null
}

#region Build Progress Modal

# Script-scoped state for the build progress modal
$script:BuildModal = $null
$script:BuildModalRows = @{}
$script:BuildModalPackageType = 'Drivers'

function Show-DATBuildProgressModal {
    <#
    .SYNOPSIS
        Shows a non-blocking overlay window with per-model pipeline stage indicators.
        Each model gets a row with circles for each stage connected by lines.
        Stages: Download → Extract → Package → Upload (Intune only)
    #>
    param (
        [Parameter(Mandatory)][array]$Models,
        [string]$Platform = 'Download Only',
        [string]$PackageType = 'Drivers'
    )

    # Close any existing modal
    if ($script:BuildModal) {
        try { $script:BuildModal.Close() } catch { }
        $script:BuildModal = $null
    }
    $script:BuildModalRows = @{}
    $script:BuildModalPackageType = $PackageType

    # Determine stages based on platform
    $stages = @('Download', 'Extract')
    if ($Platform -ne 'Download Only') {
        $stages += 'Package'
    }
    if ($Platform -eq 'Intune') {
        $stages += 'Upload'
    }

    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])

    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background = [System.Windows.Media.Brushes]::Transparent
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $Window
    $dlg.Width = 620
    $dlg.MaxHeight = 600
    $dlg.SizeToContent = 'Height'
    $dlg.Topmost = $false
    $dlg.ResizeMode = 'NoResize'
    $dlg.ShowInTaskbar = $false

    # Outer border with shadow
    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(250, $bgColor.R, $bgColor.G, $bgColor.B))
    $border.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $border.Padding = [System.Windows.Thickness]::new(24, 20, 24, 20)
    $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $border.Effect = $shadow

    $outerPanel = [System.Windows.Controls.StackPanel]::new()

    # Title row with close button
    $titleGrid = [System.Windows.Controls.Grid]::new()
    $tc1 = [System.Windows.Controls.ColumnDefinition]::new(); $tc1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $tc2 = [System.Windows.Controls.ColumnDefinition]::new(); $tc2.Width = [System.Windows.GridLength]::Auto
    $titleGrid.ColumnDefinitions.Add($tc1)
    $titleGrid.ColumnDefinitions.Add($tc2)

    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.Text = "Build Progress"
    $titleText.FontSize = 15
    $titleText.FontWeight = [System.Windows.FontWeights]::Bold
    $titleText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $titleText.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($titleText, 0)
    $titleGrid.Children.Add($titleText) | Out-Null

    $btnClose = [System.Windows.Controls.Button]::new()
    $btnClose.Content = [string][char]0xE711  # X / Cancel
    $btnClose.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $btnClose.FontSize = 12
    $btnClose.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $btnClose.Background = [System.Windows.Media.Brushes]::Transparent
    $btnClose.BorderThickness = [System.Windows.Thickness]::new(0)
    $btnClose.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnClose.ToolTip = "Close"
    [System.Windows.Controls.Grid]::SetColumn($btnClose, 1)
    $btnClose.Add_Click({
        if ($script:BuildModal) {
            $owner = $script:BuildModal.Owner
            try { $script:BuildModal.Close() } catch { }
            $script:BuildModal = $null
            $script:BuildModalRows = @{}
            if ($owner) { $owner.Activate() }
        }
    })
    $titleGrid.Children.Add($btnClose) | Out-Null

    $titleGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $outerPanel.Children.Add($titleGrid) | Out-Null

    # Stage header row (show stage labels)
    $headerGrid = [System.Windows.Controls.Grid]::new()
    $hcModel = [System.Windows.Controls.ColumnDefinition]::new()
    $hcModel.Width = [System.Windows.GridLength]::new(180)
    $headerGrid.ColumnDefinitions.Add($hcModel)
    foreach ($s in $stages) {
        $hcStage = [System.Windows.Controls.ColumnDefinition]::new()
        $hcStage.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $headerGrid.ColumnDefinitions.Add($hcStage)
    }

    # Empty cell for model column
    $emptyLabel = [System.Windows.Controls.TextBlock]::new()
    $emptyLabel.Text = "Model"
    $emptyLabel.FontSize = 11
    $emptyLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
    $emptyLabel.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    [System.Windows.Controls.Grid]::SetColumn($emptyLabel, 0)
    $headerGrid.Children.Add($emptyLabel) | Out-Null

    $stageHeaderLabels = @()
    for ($i = 0; $i -lt $stages.Count; $i++) {
        $stageLabel = [System.Windows.Controls.TextBlock]::new()
        $stageLabel.Text = $stages[$i]
        $stageLabel.FontSize = 11
        $stageLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
        $stageLabel.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
        $stageLabel.HorizontalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($stageLabel, ($i + 1))
        $headerGrid.Children.Add($stageLabel) | Out-Null
        $stageHeaderLabels += $stageLabel
    }
    $headerGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
    $outerPanel.Children.Add($headerGrid) | Out-Null

    # Scrollable model list (show 5 rows before scrolling: 5 × 46px = 230)
    $scrollViewer = [System.Windows.Controls.ScrollViewer]::new()
    $scrollViewer.VerticalScrollBarVisibility = 'Auto'
    $scrollViewer.MaxHeight = 230

    # Apply themed thin scrollbar to the modal window
    $scrollBarXaml = @"
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
       TargetType="ScrollBar">
    <Setter Property="SnapsToDevicePixels" Value="True"/>
    <Setter Property="OverridesDefaultStyle" Value="True"/>
    <Style.Triggers>
        <Trigger Property="Orientation" Value="Vertical">
            <Setter Property="Width" Value="6"/>
            <Setter Property="Height" Value="Auto"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Border Background="$($theme['ScrollTrack'])" CornerRadius="3" Width="6">
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton SnapsToDevicePixels="True" OverridesDefaultStyle="True" IsTabStop="False" Focusable="False" Command="ScrollBar.PageUpCommand">
                                        <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template>
                                    </RepeatButton>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb SnapsToDevicePixels="True" OverridesDefaultStyle="True" IsTabStop="False" Focusable="False">
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="Thumb">
                                                <Border x:Name="thumbBorder" CornerRadius="3" Background="$($theme['ScrollThumb'])" Margin="1">
                                                    <Border.Style>
                                                        <Style TargetType="Border">
                                                            <Style.Triggers>
                                                                <Trigger Property="IsMouseOver" Value="True">
                                                                    <Setter Property="Background" Value="$($theme['ScrollThumbHover'])"/>
                                                                </Trigger>
                                                            </Style.Triggers>
                                                        </Style>
                                                    </Border.Style>
                                                </Border>
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton SnapsToDevicePixels="True" OverridesDefaultStyle="True" IsTabStop="False" Focusable="False" Command="ScrollBar.PageDownCommand">
                                        <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template>
                                    </RepeatButton>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Trigger>
    </Style.Triggers>
</Style>
"@
    $scrollBarStyle = [System.Windows.Markup.XamlReader]::Parse($scrollBarXaml)
    $dlg.Resources.Add([System.Windows.Controls.Primitives.ScrollBar], $scrollBarStyle)

    $modelPanel = [System.Windows.Controls.StackPanel]::new()

    $colorPending  = $theme['PipelinePending']
    $colorActive   = $theme['AccentColor']
    $colorSuccess  = '#22C55E'
    $colorError    = $theme['StatusError']
    $colorLine     = $theme['PipelineConnector']

    # For 'All' package type, expand each model into two rows: Drivers then BIOS
    # Microsoft models skip the BIOS row (firmware is delivered via driver injection)
    $displayModels = if ($PackageType -eq 'All') {
        $expanded = [System.Collections.ArrayList]::new()
        foreach ($m in $Models) {
            [void]$expanded.Add([PSCustomObject]@{ OEM = $m.OEM; Model = $m.Model; Phase = 'Drivers' })
            if ($m.OEM -ne 'Microsoft') {
                [void]$expanded.Add([PSCustomObject]@{ OEM = $m.OEM; Model = $m.Model; Phase = 'BIOS' })
            }
        }
        $expanded
    } else {
        $Models
    }

    $separatorsList = @()
    $modelIndex = 0
    foreach ($model in $displayModels) {
        $modelPhase = if ($model.PSObject.Properties.Name -contains 'Phase') { $model.Phase } else { '' }
        $modelKey = if ($modelPhase) { "$($model.OEM)|$($model.Model) ($modelPhase)" } else { "$($model.OEM)|$($model.Model)" }
        $modelIndex++

        $rowGrid = [System.Windows.Controls.Grid]::new()
        $rowGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
        $rowGrid.Height = 40

        $rcModel = [System.Windows.Controls.ColumnDefinition]::new()
        $rcModel.Width = [System.Windows.GridLength]::new(180)
        $rowGrid.ColumnDefinitions.Add($rcModel)
        foreach ($s in $stages) {
            $rcStage = [System.Windows.Controls.ColumnDefinition]::new()
            $rcStage.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $rowGrid.ColumnDefinitions.Add($rcStage)
        }

        # Model label + subtitle wrapper
        $labelPanel = [System.Windows.Controls.StackPanel]::new()
        $labelPanel.Orientation = 'Vertical'
        $labelPanel.VerticalAlignment = 'Center'

        $modelLabel = [System.Windows.Controls.TextBlock]::new()
        $modelLabel.Text = "$($model.OEM) $($model.Model)"
        $modelLabel.FontSize = 12
        $modelLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
        $modelLabel.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
        $modelLabel.TextTrimming = 'CharacterEllipsis'
        $modelLabel.ToolTip = "$($model.OEM) $($model.Model)"
        $labelPanel.Children.Add($modelLabel) | Out-Null

        $subtitleLabel = [System.Windows.Controls.TextBlock]::new()
        $subtitleLabel.FontSize = 10
        $subtitleLabel.FontStyle = [System.Windows.FontStyles]::Italic
        $subtitleLabel.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
        $subtitleLabel.TextTrimming = 'CharacterEllipsis'
        $subtitleLabel.Visibility = 'Collapsed'
        if ($modelPhase) {
            $subtitleLabel.Text = $modelPhase
            $subtitleLabel.Visibility = 'Visible'
        }
        $labelPanel.Children.Add($subtitleLabel) | Out-Null

        [System.Windows.Controls.Grid]::SetColumn($labelPanel, 0)
        $rowGrid.Children.Add($labelPanel) | Out-Null

        # Stage circles with split half-connector lines
        # Each stage cell is a 3-column grid: [left-half connector | circle | right-half connector]
        # First stage has no left connector; last stage has no right connector.
        $stageCircles = @{}
        $stageIcons = @{}
        $rightConns = @{}
        $leftConns = @{}
        for ($i = 0; $i -lt $stages.Count; $i++) {
            $stagePanel = [System.Windows.Controls.Grid]::new()
            $stagePanel.HorizontalAlignment = 'Stretch'
            $stagePanel.VerticalAlignment = 'Center'

            $colL = [System.Windows.Controls.ColumnDefinition]::new()
            $colL.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $colC = [System.Windows.Controls.ColumnDefinition]::new()
            $colC.Width = [System.Windows.GridLength]::Auto
            $colR = [System.Windows.Controls.ColumnDefinition]::new()
            $colR.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $stagePanel.ColumnDefinitions.Add($colL)
            $stagePanel.ColumnDefinitions.Add($colC)
            $stagePanel.ColumnDefinitions.Add($colR)

            # Left half-connector (from left cell edge to circle — not for first stage)
            if ($i -gt 0) {
                $lc = [System.Windows.Controls.Border]::new()
                $lc.Height = 2
                $lc.Background = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString($colorLine))
                $lc.HorizontalAlignment = 'Stretch'
                $lc.VerticalAlignment = 'Center'
                [System.Windows.Controls.Grid]::SetColumn($lc, 0)
                $stagePanel.Children.Add($lc) | Out-Null
                $leftConns[$stages[$i]] = $lc
            }

            # Right half-connector (from circle to right cell edge — not for last stage)
            if ($i -lt ($stages.Count - 1)) {
                $rc = [System.Windows.Controls.Border]::new()
                $rc.Height = 2
                $rc.Background = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString($colorLine))
                $rc.HorizontalAlignment = 'Stretch'
                $rc.VerticalAlignment = 'Center'
                [System.Windows.Controls.Grid]::SetColumn($rc, 2)
                $stagePanel.Children.Add($rc) | Out-Null
                $rightConns[$stages[$i]] = $rc
            }

            # Circle border (center column)
            $circle = [System.Windows.Controls.Border]::new()
            $circle.Width = 26
            $circle.Height = 26
            $circle.CornerRadius = [System.Windows.CornerRadius]::new(13)
            $circle.Background = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($colorPending))
            $circle.HorizontalAlignment = 'Center'
            $circle.VerticalAlignment = 'Center'
            $circle.BorderThickness = [System.Windows.Thickness]::new(2)
            $circle.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($colorPending))

            # Icon inside circle (checkmark, spinner, x, or number)
            $icon = [System.Windows.Controls.TextBlock]::new()
            $icon.Text = "$($i + 1)"
            $icon.FontSize = 11
            $icon.FontWeight = [System.Windows.FontWeights]::Bold
            $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
            $icon.HorizontalAlignment = 'Center'
            $icon.VerticalAlignment = 'Center'

            $circle.Child = $icon
            [System.Windows.Controls.Grid]::SetColumn($circle, 1)
            $stagePanel.Children.Add($circle) | Out-Null

            [System.Windows.Controls.Grid]::SetColumn($stagePanel, ($i + 1))
            $rowGrid.Children.Add($stagePanel) | Out-Null

            $stageCircles[$stages[$i]] = $circle
            $stageIcons[$stages[$i]] = $icon
        }

        # Build connector dict: each entry = @(rightHalf of stage i, leftHalf of stage i+1)
        $stageConnectors = @{}
        for ($i = 0; $i -lt ($stages.Count - 1); $i++) {
            $parts = @()
            if ($rightConns.ContainsKey($stages[$i]))     { $parts += $rightConns[$stages[$i]] }
            if ($leftConns.ContainsKey($stages[$i + 1]))  { $parts += $leftConns[$stages[$i + 1]] }
            $stageConnectors[$stages[$i]] = $parts
        }

        # Separator line between models (except last)
        if ($modelIndex -lt $displayModels.Count) {
            $sep = [System.Windows.Controls.Border]::new()
            $sep.Height = 1
            $sep.Background = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['PipelineConnector']))
            $sep.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
            $modelPanel.Children.Add($rowGrid) | Out-Null
            $modelPanel.Children.Add($sep) | Out-Null
            $separatorsList += $sep
        } else {
            $modelPanel.Children.Add($rowGrid) | Out-Null
        }

        $script:BuildModalRows[$modelKey] = @{
            Circles    = $stageCircles
            Icons      = $stageIcons
            Connectors = $stageConnectors
            Label      = $modelLabel
            Subtitle   = $subtitleLabel
            Stages  = $stages
            Status  = @{}
        }
        foreach ($s in $stages) {
            $script:BuildModalRows[$modelKey].Status[$s] = 'Pending'
        }
    }

    $scrollViewer.Content = $modelPanel
    $outerPanel.Children.Add($scrollViewer) | Out-Null

    # Packaging note — shown only when a model is at the Package stage
    $script:BuildModalPackagingNote = [System.Windows.Controls.TextBlock]::new()
    $script:BuildModalPackagingNote.Text = 'Please note, it can take several minutes for packaging to complete.'
    $script:BuildModalPackagingNote.FontSize = 11
    $script:BuildModalPackagingNote.FontStyle = [System.Windows.FontStyles]::Italic
    $script:BuildModalPackagingNote.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $script:BuildModalPackagingNote.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
    $script:BuildModalPackagingNote.HorizontalAlignment = 'Center'
    $script:BuildModalPackagingNote.Visibility = 'Collapsed'
    $outerPanel.Children.Add($script:BuildModalPackagingNote) | Out-Null

    $border.Child = $outerPanel
    $dlg.Content = $border

    # Allow dragging
    $border.Add_MouseLeftButtonDown({
        param($s, $e)
        try { $dlg.DragMove() } catch { }
    }.GetNewClosure())

    $script:BuildModal = $dlg
    $script:BuildModalStages = $stages
    $script:BuildModalElements = @{
        Border       = $border
        TitleText    = $titleText
        CloseButton  = $btnClose
        ModelHeader  = $emptyLabel
        StageHeaders = $stageHeaderLabels
        Separators   = $separatorsList
    }

    # Register centering handlers once so modal stays centered on the parent window
    if (-not $script:BuildModalCenteringRegistered) {
        $centerAction = {
            if ($script:BuildModal -and $script:BuildModal.IsVisible) {
                $o = $script:BuildModal.Owner
                if ($o) {
                    $script:BuildModal.Left = $o.Left + ($o.ActualWidth - $script:BuildModal.ActualWidth) / 2
                    $script:BuildModal.Top = $o.Top + ($o.ActualHeight - $script:BuildModal.ActualHeight) / 2
                }
            }
        }
        $Window.Add_LocationChanged($centerAction)
        $Window.Add_SizeChanged($centerAction)
        $script:BuildModalCenteringRegistered = $true
    }

    # Show non-blocking
    $dlg.Show()
}

function Update-DATBuildModalTheme {
    <#
    .SYNOPSIS
        Re-applies the current theme colors to an open build progress modal.
        Call this when the user toggles themes while the modal is visible.
    #>
    if (-not $script:BuildModal -or -not $script:BuildModal.IsVisible) { return }

    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $el = $script:BuildModalElements
    if (-not $el) { return }

    # Outer border
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])
    $el.Border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(250, $bgColor.R, $bgColor.G, $bgColor.B))
    $el.Border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))

    # Title and close button
    $el.TitleText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $el.CloseButton.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))

    # Header labels
    $placeholderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $el.ModelHeader.Foreground = $placeholderBrush
    foreach ($lbl in $el.StageHeaders) { $lbl.Foreground = $placeholderBrush }

    # Separators
    $connBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['PipelineConnector']))
    foreach ($sep in $el.Separators) { $sep.Background = $connBrush }

    # Packaging note
    if ($script:BuildModalPackagingNote) {
        $script:BuildModalPackagingNote.Foreground = $placeholderBrush
    }

    # Update scrollbar style
    $scrollBarXaml = @"
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
       TargetType="ScrollBar">
    <Setter Property="SnapsToDevicePixels" Value="True"/>
    <Setter Property="OverridesDefaultStyle" Value="True"/>
    <Style.Triggers>
        <Trigger Property="Orientation" Value="Vertical">
            <Setter Property="Width" Value="6"/>
            <Setter Property="Height" Value="Auto"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Border Background="$($theme['ScrollTrack'])" CornerRadius="3" Width="6">
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton SnapsToDevicePixels="True" OverridesDefaultStyle="True" IsTabStop="False" Focusable="False" Command="ScrollBar.PageUpCommand">
                                        <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template>
                                    </RepeatButton>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb SnapsToDevicePixels="True" OverridesDefaultStyle="True" IsTabStop="False" Focusable="False">
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="Thumb">
                                                <Border x:Name="thumbBorder" CornerRadius="3" Background="$($theme['ScrollThumb'])" Margin="1">
                                                    <Border.Style>
                                                        <Style TargetType="Border">
                                                            <Style.Triggers>
                                                                <Trigger Property="IsMouseOver" Value="True">
                                                                    <Setter Property="Background" Value="$($theme['ScrollThumbHover'])"/>
                                                                </Trigger>
                                                            </Style.Triggers>
                                                        </Style>
                                                    </Border.Style>
                                                </Border>
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton SnapsToDevicePixels="True" OverridesDefaultStyle="True" IsTabStop="False" Focusable="False" Command="ScrollBar.PageDownCommand">
                                        <RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template>
                                    </RepeatButton>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Trigger>
    </Style.Triggers>
</Style>
"@
    $scrollBarStyle = [System.Windows.Markup.XamlReader]::Parse($scrollBarXaml)
    $script:BuildModal.Resources[[System.Windows.Controls.Primitives.ScrollBar]] = $scrollBarStyle

    # Re-apply per-row theme colors: labels, and re-render each stage's current state
    $fgBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    foreach ($key in $script:BuildModalRows.Keys) {
        $row = $script:BuildModalRows[$key]
        $parts = $key -split '\|', 2
        $row.Label.Foreground = $fgBrush
        foreach ($s in $row.Stages) {
            Update-DATBuildModalStage -OEM $parts[0] -Model $parts[1] -Stage $s -State $row.Status[$s]
        }
    }
}

function Update-DATBuildModalStage {
    <#
    .SYNOPSIS
        Updates a specific model's stage circle to a new state.
    .PARAMETER OEM
        The OEM name.
    .PARAMETER Model
        The model name.
    .PARAMETER Stage
        The pipeline stage: Download, Extract, Package, Upload
    .PARAMETER State
        The state: Active, Success, Error, Pending
    #>
    param (
        [string]$OEM,
        [string]$Model,
        [ValidateSet('Download','Extract','Package','Upload')][string]$Stage,
        [ValidateSet('Pending','Active','Success','Error','Skipped')][string]$State
    )

    if (-not $script:BuildModal -or -not $script:BuildModalRows) { return }

    $modelKey = "$OEM|$Model"
    $row = $script:BuildModalRows[$modelKey]
    if (-not $row) { return }
    if (-not $row.Circles.ContainsKey($Stage)) { return }

    $circle = $row.Circles[$Stage]
    $icon = $row.Icons[$Stage]
    $row.Status[$Stage] = $State

    $theme = Get-DATTheme -ThemeName $script:CurrentTheme

    # Show/hide the packaging note based on whether any model has Package stage active
    if ($Stage -eq 'Package' -and $script:BuildModalPackagingNote) {
        if ($State -eq 'Active') {
            $script:BuildModalPackagingNote.Visibility = 'Visible'
        } else {
            # Hide only if no other model is actively packaging
            $anyPackaging = $false
            foreach ($k in $script:BuildModalRows.Keys) {
                if ($k -ne $modelKey -and $script:BuildModalRows[$k].Status.ContainsKey('Package') -and
                    $script:BuildModalRows[$k].Status['Package'] -eq 'Active') {
                    $anyPackaging = $true
                    break
                }
            }
            if (-not $anyPackaging) {
                $script:BuildModalPackagingNote.Visibility = 'Collapsed'
            }
        }
    }

    switch ($State) {
        'Active' {
            $circle.Background = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor']))
            $circle.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColorLight']))
            $icon.Text = [string][char]0xE916  # Stopwatch icon
            $icon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            $icon.FontSize = 12
            $icon.Foreground = [System.Windows.Media.Brushes]::White
        }
        'Success' {
            $circle.Background = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString('#22C55E'))
            $circle.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString('#4ADE80'))
            $icon.Text = [string][char]0xE73E  # Checkmark
            $icon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            $icon.FontSize = 13
            $icon.Foreground = [System.Windows.Media.Brushes]::White
            # Turn the connector line halves after this stage green
            if ($row.Connectors.ContainsKey($Stage)) {
                foreach ($connPart in $row.Connectors[$Stage]) {
                    $connPart.Background = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.ColorConverter]::ConvertFromString('#22C55E'))
                }
            }
        }
        'Error' {
            $circle.Background = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusError']))
            $circle.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString('#F87171'))
            $icon.Text = [string][char]0xE711  # X mark
            $icon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            $icon.FontSize = 12
            $icon.Foreground = [System.Windows.Media.Brushes]::White
        }
        'Pending' {
            $stageIdx = [array]::IndexOf($row.Stages, $Stage)
            $circle.Background = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['PipelinePending']))
            $circle.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['PipelinePending']))
            $icon.Text = "$($stageIdx + 1)"
            $icon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe UI')
            $icon.FontSize = 11
            $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
        }
        'Skipped' {
            $circle.Background = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['PipelinePending']))
            $circle.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['PipelinePending']))
            $circle.Opacity = 0.4
            $icon.Text = [string][char]0xE738  # Blocked / minus icon
            $icon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
            $icon.FontSize = 11
            $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
            $icon.Opacity = 0.5
            # Dim connector lines
            if ($row.Connectors.ContainsKey($Stage)) {
                foreach ($connPart in $row.Connectors[$Stage]) {
                    $connPart.Opacity = 0.3
                }
            }
        }
    }
}

function Update-DATBuildModalFromRegistry {
    <#
    .SYNOPSIS
        Reads RunningMode and CurrentJob from registry to update the modal.
        Called from the build progress timer tick.
    #>
    if (-not $script:BuildModal -or -not $script:BuildModalRows) { return }
    if (-not $global:SelectedModels -or $global:SelectedModels.Count -eq 0) { return }

    $regValues = $null
    try {
        $regValues = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
    } catch { return }
    if (-not $regValues) { return }

    $currentJob = 0
    $null = [int]::TryParse([string]$regValues.CurrentJob, [ref]$currentJob)
    if ($currentJob -le 0) { return }

    $runningMode = [string]$regValues.RunningMode
    $runningState = [string]$regValues.RunningState
    $runningMessage = [string]$regValues.RunningMessage

    # Don't update modal while the background runspace is still initializing
    # (module import, Intune pre-fetch, etc.) -- RunningMode may be stale from a previous build
    if ($runningState -eq 'Starting') { return }

    # Track CompletedJobs to detect per-model failures
    $currentCompletedJobs = 0
    $null = [int]::TryParse([string]$regValues.CompletedJobs, [ref]$currentCompletedJobs)

    # Get current model info
    $modelIdx = $currentJob - 1
    if ($modelIdx -ge $global:SelectedModels.Count) { return }
    $currentModel = $global:SelectedModels[$modelIdx]
    $oem = $currentModel.OEM
    $modelName = $currentModel.Model

    # When 'All' package type, use PackagePhase registry value to target the correct row
    $packagePhase = [string]$regValues.PackagePhase
    $modelDisplayName = if ($script:BuildModalPackageType -eq 'All') {
        if ($packagePhase -eq 'BIOS') { "$modelName (BIOS)" } else { "$modelName (Drivers)" }
    } else {
        $modelName
    }
    $modelKey = "$oem|$modelDisplayName"

    if (-not $script:BuildModalRows.ContainsKey($modelKey)) { return }

    # Detect BIOS no-match via RunningMode — tied to CurrentJob so no race conditions
    if ($runningMode -eq 'BiosNoMatch') {
        $row = $script:BuildModalRows[$modelKey]
        $alreadySkipped = $false
        foreach ($s in $row.Stages) {
            if ($row.Status[$s] -eq 'Skipped') { $alreadySkipped = $true; break }
        }
        if (-not $alreadySkipped) {
            foreach ($s in $row.Stages) {
                Update-DATBuildModalStage -OEM $oem -Model $modelDisplayName -Stage $s -State Skipped
            }
            # Update model label to show "No match found"
            if ($row.Label) {
                $theme = Get-DATTheme -ThemeName $script:CurrentTheme
                $row.Label.Text = "$oem $modelName — No match found"
                $row.Label.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
                $row.Label.FontStyle = [System.Windows.FontStyles]::Italic
                $row.Label.ToolTip = "No BIOS update found in catalog for $oem $modelName"
            }
        }
        return
    }

    # Detect per-model failure when CurrentJob advances
    # If CurrentJob moved forward but CompletedJobs didn't increment, the previous model failed
    if ($currentJob -gt $script:BuildProgressLastJob -and $script:BuildProgressLastJob -gt 0) {
        if ($currentCompletedJobs -le $script:BuildProgressLastCompletedJobs) {
            # Previous model failed — mark its active stage(s) as Error
            $failedModelIdx = $script:BuildProgressLastJob - 1
            if ($failedModelIdx -ge 0 -and $failedModelIdx -lt $global:SelectedModels.Count) {
                $failedModel = $global:SelectedModels[$failedModelIdx]
                $failedKeys = if ($script:BuildModalPackageType -eq 'All') {
                    @("$($failedModel.OEM)|$($failedModel.Model) (Drivers)", "$($failedModel.OEM)|$($failedModel.Model) (BIOS)")
                } else {
                    @("$($failedModel.OEM)|$($failedModel.Model)")
                }
                foreach ($failedKey in $failedKeys) {
                    if ($script:BuildModalRows.ContainsKey($failedKey)) {
                        $failedRow = $script:BuildModalRows[$failedKey]
                        $failedDisplayModel = ($failedKey -split '\|', 2)[1]
                        foreach ($s in $failedRow.Stages) {
                            if ($failedRow.Status[$s] -eq 'Active') {
                                Update-DATBuildModalStage -OEM $failedModel.OEM -Model $failedDisplayModel -Stage $s -State Error
                            }
                        }
                    }
                }
            }
        }
    }
    $script:BuildProgressLastJob = $currentJob
    $script:BuildProgressLastCompletedJobs = $currentCompletedJobs

    # Mark all completed models as fully succeeded (skip models marked as Error or Skipped)
    for ($i = 0; $i -lt $modelIdx; $i++) {
        $prevModel = $global:SelectedModels[$i]
        $prevKeys = if ($script:BuildModalPackageType -eq 'All') {
            @("$($prevModel.OEM)|$($prevModel.Model) (Drivers)", "$($prevModel.OEM)|$($prevModel.Model) (BIOS)")
        } else {
            @("$($prevModel.OEM)|$($prevModel.Model)")
        }
        foreach ($prevKey in $prevKeys) {
            if ($script:BuildModalRows.ContainsKey($prevKey)) {
                $prevRow = $script:BuildModalRows[$prevKey]
                $prevDisplayModel = ($prevKey -split '\|', 2)[1]
                # Skip rows that have any Error or Skipped stage
                $skipRow = $false
                foreach ($s in $prevRow.Stages) {
                    if ($prevRow.Status[$s] -in @('Error', 'Skipped')) { $skipRow = $true; break }
                }
                if (-not $skipRow) {
                    foreach ($s in $prevRow.Stages) {
                        if ($prevRow.Status[$s] -ne 'Success') {
                            Update-DATBuildModalStage -OEM $prevModel.OEM -Model $prevDisplayModel -Stage $s -State Success
                        }
                    }
                }
            }
        }
    }

    # When 'All' mode transitions from Drivers to BIOS for the same model, complete the Drivers row
    if ($script:BuildModalPackageType -eq 'All' -and $packagePhase -eq 'BIOS') {
        $driversKey = "$oem|$modelName (Drivers)"
        if ($script:BuildModalRows.ContainsKey($driversKey)) {
            $driversRow = $script:BuildModalRows[$driversKey]
            $skipDrivers = $false
            foreach ($s in $driversRow.Stages) {
                if ($driversRow.Status[$s] -in @('Error', 'Skipped')) { $skipDrivers = $true; break }
            }
            if (-not $skipDrivers) {
                foreach ($s in $driversRow.Stages) {
                    if ($driversRow.Status[$s] -ne 'Success') {
                        Update-DATBuildModalStage -OEM $oem -Model "$modelName (Drivers)" -Stage $s -State Success
                    }
                }
            }
        }
    }

    # Map RunningMode to pipeline stage
    $currentStage = switch -Wildcard ($runningMode) {
        'Download'           { 'Download'; break }
        'Download*'          { 'Download'; break }
        'Extracting'         { 'Extract'; break }
        'Extract*'           { 'Extract'; break }
        'Packaging'          { 'Package'; break }
        'WIM*'               { 'Package'; break }
        'Package*'           { 'Package'; break }
        'Intune*'            { 'Upload'; break }
        'Upload*'            { 'Upload'; break }
        default              { 'Download'; break }
    }

    # If RunningMode says "Download Completed", mark Download as success and set Extract as active
    if ($runningMode -eq 'Download Completed') {
        Update-DATBuildModalStage -OEM $oem -Model $modelDisplayName -Stage 'Download' -State Success
        $currentStage = 'Extract'
    }
    if ($runningMode -eq 'Extract Ready') {
        Update-DATBuildModalStage -OEM $oem -Model $modelDisplayName -Stage 'Download' -State Success
        Update-DATBuildModalStage -OEM $oem -Model $modelDisplayName -Stage 'Extract' -State Success
        $currentStage = 'Package'
    }

    $row = $script:BuildModalRows[$modelKey]

    # Mark stages before the current one as success (for current model)
    $stageOrder = $row.Stages
    $currentStageIdx = [array]::IndexOf($stageOrder, $currentStage)
    for ($i = 0; $i -lt $currentStageIdx; $i++) {
        if ($row.Status[$stageOrder[$i]] -ne 'Success') {
            Update-DATBuildModalStage -OEM $oem -Model $modelDisplayName -Stage $stageOrder[$i] -State Success
        }
    }

    # Set current stage to active
    if ($currentStageIdx -ge 0 -and $currentStageIdx -lt $stageOrder.Count) {
        if ($row.Status[$stageOrder[$currentStageIdx]] -ne 'Success' -and $row.Status[$stageOrder[$currentStageIdx]] -ne 'Error') {
            Update-DATBuildModalStage -OEM $oem -Model $modelDisplayName -Stage $stageOrder[$currentStageIdx] -State Active
        }
    }

    # Handle error state
    if ($runningState -eq 'Error' -and $currentStageIdx -ge 0 -and $currentStageIdx -lt $stageOrder.Count) {
        Update-DATBuildModalStage -OEM $oem -Model $modelDisplayName -Stage $stageOrder[$currentStageIdx] -State Error
    }
}

function Close-DATBuildProgressModal {
    <#
    .SYNOPSIS
        Closes the build progress modal and marks all remaining models as complete.
    .PARAMETER MarkAllSuccess
        If true, mark all pending stages as success. If false, leave them as-is.
    #>
    param (
        [switch]$MarkAllSuccess
    )

    if (-not $script:BuildModal) { return }

    if ($script:BuildModalRows) {
        foreach ($key in $script:BuildModalRows.Keys) {
            $parts = $key -split '\|', 2
            $row = $script:BuildModalRows[$key]
            if ($MarkAllSuccess) {
                # All succeeded — mark any remaining Pending/Active as Success
                foreach ($s in $row.Stages) {
                    if ($row.Status[$s] -eq 'Pending' -or $row.Status[$s] -eq 'Active') {
                        Update-DATBuildModalStage -OEM $parts[0] -Model $parts[1] -Stage $s -State Success
                    }
                }
            } else {
                # Errors occurred — mark any Active stages as Error (these are the failed stages)
                foreach ($s in $row.Stages) {
                    if ($row.Status[$s] -eq 'Active') {
                        Update-DATBuildModalStage -OEM $parts[0] -Model $parts[1] -Stage $s -State Error
                    }
                }
            }
        }
    }

    # Auto-close after a short delay (2s for success, 5s for errors so user can see the state)
    $closeDelay = if ($MarkAllSuccess) { 2 } else { 5 }
    $script:BuildModalCloseTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:BuildModalCloseTimer.Interval = [TimeSpan]::FromSeconds($closeDelay)
    $script:BuildModalCloseTimer.Add_Tick({
        $script:BuildModalCloseTimer.Stop()
        if ($script:BuildModal) {
            $owner = $script:BuildModal.Owner
            try { $script:BuildModal.Close() } catch { }
            $script:BuildModal = $null
            $script:BuildModalRows = @{}
            if ($owner) { $owner.Activate() }
        }
    })
    $script:BuildModalCloseTimer.Start()
}

#endregion Build Progress Modal

#region Navigation

$allViews = @('view_ModelSelection', 'view_Packages', 'view_ConfigMgr', 'view_Distribution', 'view_IntuneSettings', 'view_IntuneOptions', 'view_IntunePackageMgmt', 'view_BIOSSecurity', 'view_CommonSettings', 'view_CustomDriverPack', 'view_Log', 'view_ModernMgmt', 'view_About')
$navMap = @{
    'nav_ModelSelection'       = 'view_ModelSelection'
    'nav_Packages'             = 'view_Packages'
    'nav_ConfigMgr'            = 'view_ConfigMgr'
    'nav_ConfigMgrEnvironment' = 'view_ConfigMgr'
    'nav_Distribution'         = 'view_Distribution'
    'nav_IntuneSettings'       = 'view_IntuneSettings'
    'nav_IntuneAuth'           = 'view_IntuneSettings'
    'nav_IntuneOptions'        = 'view_IntuneOptions'
    'nav_IntunePackageMgmt'    = 'view_IntunePackageMgmt'
    'nav_BIOSSecurity'         = 'view_BIOSSecurity'
    'nav_CommonSettings'       = 'view_CommonSettings'
    'nav_CustomDriverPack'     = 'view_CustomDriverPack'
    'nav_Log'                  = 'view_Log'
    'nav_ModernMgmt'           = 'view_ModernMgmt'
    'nav_About'                = 'view_About'
}

$allNavButtons = @('nav_ModelSelection', 'nav_ConfigMgr', 'nav_IntuneSettings', 'nav_CommonSettings', 'nav_CustomDriverPack', 'nav_Log', 'nav_ModernMgmt', 'nav_About')
$subNavButtons = @('nav_Packages', 'nav_Distribution', 'nav_ConfigMgrEnvironment', 'nav_IntuneAuth', 'nav_IntuneOptions', 'nav_IntunePackageMgmt', 'nav_BIOSSecurity')
$configMgrSubPanel = $Window.FindName('panel_ConfigMgrSub')
$intuneSubPanel = $Window.FindName('panel_IntuneSub')

function Set-DATActiveView {
    param ([string]$ViewName, [string]$NavButtonName)

    # Hide all views
    foreach ($v in $allViews) {
        $ctrl = $Window.FindName($v)
        if ($null -ne $ctrl) { $ctrl.Visibility = 'Collapsed' }
    }

    # Show target view
    $targetView = $Window.FindName($ViewName)
    if ($null -ne $targetView) { $targetView.Visibility = 'Visible' }

    # Auto-load packages when navigating to Package Management
    if ($ViewName -eq 'view_Packages') {
        Invoke-DATPackageRefresh
    }

    # Update main nav button styles
    $activeStyle = $Window.FindResource('NavButtonActive')
    $normalStyle = $Window.FindResource('NavButton')
    foreach ($nb in $allNavButtons) {
        $navBtn = $Window.FindName($nb)
        if ($null -ne $navBtn) {
            if ($nb -eq $NavButtonName) {
                $navBtn.Style = $activeStyle
            } else {
                $navBtn.Style = $normalStyle
            }
        }
    }

    # Update sub nav button styles
    $subActiveStyle = $Window.FindResource('SubNavButtonActive')
    $subNormalStyle = $Window.FindResource('SubNavButton')
    foreach ($sb in $subNavButtons) {
        $subBtn = $Window.FindName($sb)
        if ($null -ne $subBtn) {
            if ($sb -eq $NavButtonName) {
                $subBtn.Style = $subActiveStyle
            } else {
                $subBtn.Style = $subNormalStyle
            }
        }
    }

    # Keep ConfigMgr parent highlighted when a sub-item is active
    $configMgrBtn = $Window.FindName('nav_ConfigMgr')
    if ($NavButtonName -in @('nav_Packages', 'nav_Distribution', 'nav_ConfigMgrEnvironment') -or $NavButtonName -eq 'nav_ConfigMgr') {
        $configMgrBtn.Style = $activeStyle
    }

    # Keep Intune parent highlighted when a sub-item is active
    $intuneBtn = $Window.FindName('nav_IntuneSettings')
    if ($NavButtonName -in @('nav_IntuneAuth', 'nav_IntuneOptions', 'nav_IntunePackageMgmt', 'nav_BIOSSecurity') -or $NavButtonName -eq 'nav_IntuneSettings') {
        $intuneBtn.Style = $activeStyle
    }
}

# Smooth expand/collapse animation for sub-menu panels
function Start-DATPanelAnimation {
    param ($Panel, [bool]$Expand, [scriptblock]$OnComplete)

    $Panel.ClipToBounds = $true

    if ($Expand) {
        # Make visible first so we can measure
        $Panel.Visibility = 'Visible'
        $Panel.MaxHeight = 0
        $Panel.UpdateLayout()
        $Panel.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        $targetHeight = $Panel.DesiredSize.Height

        $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
        $anim.From = 0
        $anim.To = $targetHeight
        $anim.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(200))
        $anim.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase
        $anim.EasingFunction.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut

        $anim.Add_Completed({
            $Panel.BeginAnimation([System.Windows.FrameworkElement]::MaxHeightProperty, $null)
            $Panel.MaxHeight = [double]::PositiveInfinity
            if ($null -ne $OnComplete) { & $OnComplete }
        }.GetNewClosure())

        $Panel.BeginAnimation([System.Windows.FrameworkElement]::MaxHeightProperty, $anim)
    } else {
        $currentHeight = $Panel.ActualHeight

        $anim = New-Object System.Windows.Media.Animation.DoubleAnimation
        $anim.From = $currentHeight
        $anim.To = 0
        $anim.Duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(200))
        $anim.EasingFunction = New-Object System.Windows.Media.Animation.QuadraticEase
        $anim.EasingFunction.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseIn

        $anim.Add_Completed({
            $Panel.BeginAnimation([System.Windows.FrameworkElement]::MaxHeightProperty, $null)
            $Panel.Visibility = 'Collapsed'
            $Panel.MaxHeight = [double]::PositiveInfinity
            if ($null -ne $OnComplete) { & $OnComplete }
        }.GetNewClosure())

        $Panel.BeginAnimation([System.Windows.FrameworkElement]::MaxHeightProperty, $anim)
    }
}

# ConfigMgr button toggles sub-menu and navigates to ConfigMgr Environment view
$nav_ConfigMgr = $Window.FindName('nav_ConfigMgr')
$nav_ConfigMgr.Add_Click({
    if ($configMgrSubPanel.Visibility -eq 'Visible') {
        Start-DATPanelAnimation -Panel $configMgrSubPanel -Expand $false
    } else {
        if ($intuneSubPanel.Visibility -eq 'Visible') {
            Start-DATPanelAnimation -Panel $intuneSubPanel -Expand $false
        }
        Start-DATPanelAnimation -Panel $configMgrSubPanel -Expand $true
        Set-DATActiveView -ViewName 'view_ConfigMgr' -NavButtonName 'nav_ConfigMgrEnvironment'
    }
})

# Intune button toggles sub-menu and navigates to Authentication view
$nav_IntuneSettings = $Window.FindName('nav_IntuneSettings')
$nav_IntuneSettings.Add_Click({
    if ($intuneSubPanel.Visibility -eq 'Visible') {
        Start-DATPanelAnimation -Panel $intuneSubPanel -Expand $false
    } else {
        if ($configMgrSubPanel.Visibility -eq 'Visible') {
            Start-DATPanelAnimation -Panel $configMgrSubPanel -Expand $false
        }
        Start-DATPanelAnimation -Panel $intuneSubPanel -Expand $true
        Set-DATActiveView -ViewName 'view_IntuneSettings' -NavButtonName 'nav_IntuneAuth'
    }
})

# Wire up sub-nav button clicks (Packages, Distribution)
foreach ($subKey in $subNavButtons) {
    $btn = $Window.FindName($subKey)
    if ($null -ne $btn) {
        $viewTarget = $navMap[$subKey]
        $navName = $subKey
        $btn.Add_Click([scriptblock]::Create("Set-DATActiveView -ViewName '$viewTarget' -NavButtonName '$navName'"))
    }
}

# Wire up remaining navigation button clicks (excluding ConfigMgr and Intune which are handled above)
foreach ($navKey in $navMap.Keys) {
    if ($navKey -eq 'nav_ConfigMgr' -or $navKey -eq 'nav_IntuneSettings' -or $navKey -in $subNavButtons) { continue }
    $btn = $Window.FindName($navKey)
    if ($null -ne $btn) {
        $viewTarget = $navMap[$navKey]
        $navName = $navKey
        $btn.Add_Click([scriptblock]::Create("Set-DATActiveView -ViewName '$viewTarget' -NavButtonName '$navName'"))
    }
}

#endregion Navigation

#region Model Selection Logic

# OEM multi-select pill dropdown controls
$btn_OEMToggle = $Window.FindName('btn_OEMToggle')
$txt_OEMDisplay = $Window.FindName('txt_OEMDisplay')
$popup_OEM = $Window.FindName('popup_OEM')
$script:OEMCheckboxes = @{
    'Acer'      = $Window.FindName('chk_OEM_Acer')
    'Dell'      = $Window.FindName('chk_OEM_Dell')
    'HP'        = $Window.FindName('chk_OEM_HP')
    'Lenovo'    = $Window.FindName('chk_OEM_Lenovo')
    'Microsoft' = $Window.FindName('chk_OEM_Microsoft')
}
$script:OEMBorders = @{
    'Acer'      = $Window.FindName('border_OEM_Acer')
    'Dell'      = $Window.FindName('border_OEM_Dell')
    'HP'        = $Window.FindName('border_OEM_HP')
    'Lenovo'    = $Window.FindName('border_OEM_Lenovo')
    'Microsoft' = $Window.FindName('border_OEM_Microsoft')
}

function Get-DATSelectedOEMs {
    $selected = @()
    foreach ($entry in $script:OEMCheckboxes.GetEnumerator()) {
        if ($entry.Value.IsChecked -eq $true) { $selected += $entry.Key }
    }
    return $selected
}

function Update-DATOEMDisplayText {
    $selected = Get-DATSelectedOEMs
    if ($selected.Count -eq 0) {
        $txt_OEMDisplay.Text = 'Select OEMs...'
    } elseif ($selected.Count -le 3) {
        $txt_OEMDisplay.Text = $selected -join ', '
    } else {
        $txt_OEMDisplay.Text = "$($selected.Count) selected"
    }
}

function Update-DATOEMSelectionHighlight {
    $brushSelected = $Window.FindResource('ButtonPrimary')
    $brushTransparent = [System.Windows.Media.Brushes]::Transparent
    foreach ($entry in $script:OEMCheckboxes.GetEnumerator()) {
        $border = $script:OEMBorders[$entry.Key]
        if ($null -ne $border) {
            $border.Background = if ($entry.Value.IsChecked -eq $true) { $brushSelected } else { $brushTransparent }
        }
    }
}

# Wire checkbox change events to update display text and highlight
foreach ($chk in $script:OEMCheckboxes.Values) {
    $chk.Add_Checked({ Update-DATOEMDisplayText; Update-DATOEMSelectionHighlight })
    $chk.Add_Unchecked({ Update-DATOEMDisplayText; Update-DATOEMSelectionHighlight })
}

# Check for HP CMSL module availability
$script:HPCMSLAvailable = $null -ne (Get-Module -ListAvailable -Name HPCMSL -ErrorAction SilentlyContinue)
if (-not $script:HPCMSLAvailable) {
    $script:OEMCheckboxes['HP'].IsEnabled = $false
    $script:OEMCheckboxes['HP'].IsChecked = $false
    $script:OEMCheckboxes['HP'].Content = 'HP (CMSL not installed)'
    $script:OEMCheckboxes['HP'].ToolTip = 'Install the HPCMSL module to enable HP support: Install-Module HPCMSL'
    Write-DATActivityLog "HP CMSL module not found. HP device support is disabled. Install with: Install-Module HPCMSL" -Level Warn
    Write-DATLogEntry -Value "[Warning] - HP CMSL module (HPCMSL) not found. HP OEM selection disabled. Install with: Install-Module HPCMSL" -Severity 2
}

$script:ModelData = [System.Collections.ObjectModel.ObservableCollection[ModelItem]]::new()
$grid_Models.ItemsSource = $script:ModelData

# Toggle Selected on a ModelItem. Because ModelItem implements INotifyPropertyChanged,
# setting .Selected automatically notifies WPF and the bound CheckBox updates instantly —
# no visual-tree walking, no UpdateLayout() calls needed.
function Set-DATModelItemToggle {
    param($item)
    if ($null -eq $item) { return }
    $item.Selected = -not $item.Selected
    Update-DATBuildButtonState
    Save-DATModelSelections
}

# Mouse click: walk up to the DataGridRow and toggle.
$grid_Models.Add_PreviewMouseLeftButtonDown({
    param($s, $e)
    $dep = $e.OriginalSource
    while ($null -ne $dep -and $dep -isnot [System.Windows.Controls.DataGridRow]) {
        if ($dep -is [System.Windows.Controls.Primitives.DataGridColumnHeader]) { return }
        $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
    }
    if ($null -eq $dep) { return }
    Set-DATModelItemToggle -item ($dep.DataContext -as [ModelItem])
})

# Space bar: toggle the currently selected row.
$grid_Models.Add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -ne [System.Windows.Input.Key]::Space) { return }
    Set-DATModelItemToggle -item ($grid_Models.SelectedItem -as [ModelItem])
    $e.Handled = $true  # prevent DataGrid's default Space behaviour (cell editing)
})

# Checkbox column sorting: checked items first on initial click
$grid_Models.Add_Sorting({
    param($s, $e)
    if ($e.Column.SortMemberPath -ne 'Selected') { return }
    $e.Handled = $true
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($script:ModelData)
    $view.SortDescriptions.Clear()

    # Toggle direction; default to descending (checked first)
    $currentDir = $e.Column.SortDirection
    if ($currentDir -eq [System.ComponentModel.ListSortDirection]::Descending) {
        $newDir = [System.ComponentModel.ListSortDirection]::Ascending
    } else {
        $newDir = [System.ComponentModel.ListSortDirection]::Descending
    }
    $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('Selected', $newDir))
    $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('OEM', [System.ComponentModel.ListSortDirection]::Ascending))
    $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('Model', [System.ComponentModel.ListSortDirection]::Ascending))
    $e.Column.SortDirection = $newDir
})

# Model detail panel: show package details when a row is selected
$grid_Models.Add_SelectionChanged({
    param($s, $e)
    $item = $grid_Models.SelectedItem -as [ModelItem]
    if ($null -eq $item) {
        $panel_ModelDetail.Visibility = 'Collapsed'
        return
    }
    $txt_ModelDetail_OEM.Text        = $item.OEM
    $txt_ModelDetail_Model.Text      = $item.Model
    $txt_ModelDetail_OS.Text         = $item.OS
    $txt_ModelDetail_Build.Text      = $item.Build
    $txt_ModelDetail_Baseboards.Text = if ($item.Baseboards) { $item.Baseboards } else { '—' }
    $txt_ModelDetail_Version.Text    = if ($item.Version) { $item.Version } else { '—' }
    try { $txt_ModelDetail_BIOS.Text = if ($item.BIOSVersion) { $item.BIOSVersion } else { '—' } } catch { $txt_ModelDetail_BIOS.Text = '—' }

    # NVIDIA GFX indicator
    if ($item.HasGFX) {
        $txt_ModelDetail_GFX.Text       = $item.GFXBrand
        $txt_ModelDetail_GFX.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom('#76B900')
    } else {
        $txt_ModelDetail_GFX.Text       = 'None'
        $txt_ModelDetail_GFX.Foreground = $txt_ModelDetail_OEM.TryFindResource('InputPlaceholder')
    }

    # Custom drivers path
    $txt_ModelDetail_CustomPath.Text = if (-not [string]::IsNullOrEmpty($item.CustomDriverPath)) { $item.CustomDriverPath } else { 'None' }

    $panel_ModelDetail.Visibility = 'Visible'
})

# Context menu: Add Custom Drivers
$ctx_AddCustomDrivers = $grid_Models.ContextMenu.Items | Where-Object { $_.Name -eq 'ctx_AddCustomDrivers' }
$ctx_ClearCustomDrivers = $grid_Models.ContextMenu.Items | Where-Object { $_.Name -eq 'ctx_ClearCustomDrivers' }
$ctx_ForcePackageUpdate = $grid_Models.ContextMenu.Items | Where-Object { $_.Name -eq 'ctx_ForcePackageUpdate' }

$ctx_AddCustomDrivers.Add_Click({
    $selectedItem = $grid_Models.SelectedItem
    if ($null -eq $selectedItem) { return }
    $result = Show-DATCustomDriverDialog -ModelName $selectedItem.Model -ExistingPath $selectedItem.CustomDriverPath
    if ($null -ne $result) {
        $selectedItem.CustomDriverPath = $result
        $txt_ModelDetail_CustomPath.Text = $result
        Write-DATActivityLog "Custom drivers set for $($selectedItem.OEM) $($selectedItem.Model): $result" -Level Info
    }
})

$ctx_ClearCustomDrivers.Add_Click({
    $selectedItem = $grid_Models.SelectedItem
    if ($null -eq $selectedItem) { return }
    if (-not [string]::IsNullOrEmpty($selectedItem.CustomDriverPath)) {
        $selectedItem.CustomDriverPath = $null
        $txt_ModelDetail_CustomPath.Text = 'None'
        Write-DATActivityLog "Custom drivers cleared for $($selectedItem.OEM) $($selectedItem.Model)" -Level Info
    }
})

$ctx_ForcePackageUpdate.Add_Click({
    $selectedItem = $grid_Models.SelectedItem
    if ($null -eq $selectedItem) { return }

    $selectedPlatform = if ($null -ne $cmb_Platform.SelectedItem) { $cmb_Platform.SelectedItem.Content } else { 'Download Only' }

    $confirmMsg = "Force update will replace the existing package for:`n`n$($selectedItem.OEM) $($selectedItem.Model)`n`nPlatform: $selectedPlatform`n`nThis will overwrite the current package content and redistribute."
    $result = Show-DATConfirmDialog -Title "Confirm Force Package Update" -Message $confirmMsg -ConfirmLabel "Yes, Continue"
    if (-not $result) { return }

    # Tag the model for force update
    if (-not ($selectedItem.PSObject.Properties.Name -contains 'ForceUpdate')) {
        $selectedItem | Add-Member -NotePropertyName 'ForceUpdate' -NotePropertyValue $true -Force
    } else {
        $selectedItem.ForceUpdate = $true
    }

    # Ensure model is selected
    $selectedItem.Selected = $true

    Write-DATActivityLog "Force update queued for $($selectedItem.OEM) $($selectedItem.Model) on $selectedPlatform" -Level Info
    $txt_Status.Text = "Force update queued — click Build Package to proceed."
    $txt_Status.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
    Update-DATBuildButtonState
})

# Enable/disable Clear option based on whether the right-clicked model has a custom path
$grid_Models.ContextMenu.Add_Opened({
    # Sync theme resources into the ContextMenu (separate visual tree from Window)
    $ctxMenu = $grid_Models.ContextMenu
    $themeDict = Get-DATThemeResourceDictionary -ThemeName $script:CurrentTheme
    $ctxMenu.Resources.MergedDictionaries.Clear()
    $ctxMenu.Resources.MergedDictionaries.Add($themeDict)

    $selectedItem = $grid_Models.SelectedItem
    $hasCDP = ($null -ne $selectedItem) -and -not [string]::IsNullOrEmpty($selectedItem.CustomDriverPath)
    $ctx_ClearCustomDrivers.IsEnabled = $hasCDP
    if ($hasCDP) {
        $ctx_ClearCustomDrivers.Header = "Clear Custom Drivers ($($selectedItem.CustomDriverPath))"
    } else {
        $ctx_ClearCustomDrivers.Header = "Clear Custom Drivers"
    }

    # Enable Force Update when a model is selected (works on any platform)
    $ctx_ForcePackageUpdate.IsEnabled = ($null -ne $selectedItem)
    if ($selectedItem -and $selectedItem.ForceUpdate -eq $true) {
        $ctx_ForcePackageUpdate.Header = "Force Existing Package Update (queued)"
    } else {
        $ctx_ForcePackageUpdate.Header = "Force Existing Package Update"
    }

    # Set DAT logo on the context menu header
    $headerLogo = $grid_Models.ContextMenu.Items[0].Template.FindName('ctx_HeaderLogo', $grid_Models.ContextMenu.Items[0])
    if ($null -ne $headerLogo -and $null -ne $script:bitmapImage) {
        $headerLogo.Source = $script:bitmapImage
    }
})

# Suppress auto-refresh during initial load/restore
$script:SuppressModelRefresh = $true

# Save Package Type immediately on change so the selection persists across restarts
$cmb_PackageType.Add_SelectionChanged({
    if ($script:SuppressModelRefresh) { return }
    $selected = if ($null -ne $cmb_PackageType.SelectedItem) { $cmb_PackageType.SelectedItem.Content } else { 'Drivers' }
    Set-DATRegistryValue -Name "PackageType" -Value "$selected" -Type String
})

# Helper to programmatically invoke the Refresh Models button click
function Invoke-DATRefreshModelsClick {
    $peer = New-Object System.Windows.Automation.Peers.ButtonAutomationPeer($btn_RefreshModels)
    $invokeProvider = $peer.GetPattern([System.Windows.Automation.Peers.PatternInterface]::Invoke)
    $invokeProvider.Invoke()
}

# Refresh models when OS or Architecture selection changes
$cmb_OS.Add_SelectionChanged({
    if ($script:SuppressModelRefresh) { return }
    if ((Get-DATSelectedOEMs).Count -gt 0 -and $null -ne $cmb_OS.SelectedItem) {
        # Save current selections before refresh clears the model list
        if ($script:ModelData.Count -gt 0) { Save-DATModelSelections }
        Invoke-DATRefreshModelsClick
    }
})

$cmb_Architecture.Add_SelectionChanged({
    if ($script:SuppressModelRefresh) { return }
    if ((Get-DATSelectedOEMs).Count -gt 0 -and $null -ne $cmb_OS.SelectedItem) {
        # Save current selections before refresh clears the model list
        if ($script:ModelData.Count -gt 0) { Save-DATModelSelections }
        Invoke-DATRefreshModelsClick
    }
})

$btn_RefreshModels.Add_Click({
    # Capture selections on UI thread
    $selectedOEMs = Get-DATSelectedOEMs
    $selectedOS = if ($null -ne $cmb_OS.SelectedItem) { $cmb_OS.SelectedItem.Content } else { $null }
    $selectedArch = if ($null -ne $cmb_Architecture.SelectedItem) { $cmb_Architecture.SelectedItem.Content } else { "x64" }

    $selectedPlatformValue = if ($null -ne $cmb_Platform.SelectedItem) { $cmb_Platform.SelectedItem.Content } else { "Download Only" }

    # Save selections to registry for next launch
    Set-DATRegistryValue -Name "SelectedOEMs" -Value ($selectedOEMs -join ',') -Type String
    Set-DATRegistryValue -Name "OS" -Value "$selectedOS" -Type String
    Set-DATRegistryValue -Name "Architecture" -Value "$selectedArch" -Type String
    Set-DATRegistryValue -Name "Platform" -Value "$selectedPlatformValue" -Type String
    $selectedPackageType = if ($null -ne $cmb_PackageType.SelectedItem) { $cmb_PackageType.SelectedItem.Content } else { 'Drivers' }
    Set-DATRegistryValue -Name "PackageType" -Value "$selectedPackageType" -Type String

    Write-DATActivityLog "Selected OEMs: $($selectedOEMs -join ', ')" -Level Info
    Write-DATActivityLog "OS: $selectedOS | Architecture: $selectedArch | Platform: $selectedPlatformValue" -Level Info

    if ($selectedOEMs.Count -eq 0 -or [string]::IsNullOrEmpty($selectedOS)) {
        Write-DATActivityLog "Validation failed - select at least one OEM and an OS." -Level Warn
        $txt_Status.Text = "Please select at least one OEM and an operating system."
        return
    }

    # Update UI state
    $txt_Status.Text = "Refreshing models..."
    $progress_Job.Visibility = 'Visible'
    $progress_Job.IsIndeterminate = $true
    $btn_RefreshModels.IsEnabled = $false
    $script:ModelData.Clear()
    Write-DATActivityLog "Starting model refresh..." -Level Info

    # Show the Loading Sources modal
    Show-DATLoadingSourcesModal -OEMs $selectedOEMs

    # Create background runspace with shared log queue
    $script:RefreshRunspace = [runspacefactory]::CreateRunspace()
    $script:RefreshRunspace.ApartmentState = 'STA'
    $script:RefreshRunspace.Open()

    # Pass the log queue into the runspace so it can post messages
    $script:RefreshRunspace.SessionStateProxy.SetVariable('LogQueue', $script:LogQueue)

    $script:RefreshPS = [powershell]::Create()
    $script:RefreshPS.Runspace = $script:RefreshRunspace
    [void]$script:RefreshPS.AddScript({
        param($CoreModulePath, $RequiredOEMs, $OS, $Architecture, $PackageType)

        function Write-Log {
            param([string]$Message, [string]$Level = 'Info')
            $ts = Get-Date -Format 'HH:mm:ss'
            $pfx = switch ($Level) { 'Info' { '[INFO]' } 'Warn' { '[WARN]' } 'Error' { '[ERROR]' } 'Success' { '[OK]' } default { '[INFO]' } }
            $LogQueue.Enqueue("$ts $pfx $Message")
            # Also write to the log file via the core module
            $severity = switch ($Level) { 'Error' { '3' } 'Warn' { '2' } default { '1' } }
            try { Write-DATLogEntry -Value $Message -Severity $severity } catch { }
        }

        # Cache freshness check — returns $true if the file exists and was modified within $MaxAgeHours
        function Test-CatalogFresh {
            param([string]$FilePath, [int]$MaxAgeHours = 24)
            if (-not (Test-Path $FilePath)) { return $false }
            $age = (Get-Date) - (Get-Item $FilePath).LastWriteTime
            return $age.TotalHours -lt $MaxAgeHours
        }

        try {
            Write-Log "Importing core module..."
            Import-Module $CoreModulePath -Force -ErrorAction Stop
            Write-Log "Core module loaded successfully." -Level Success
        } catch {
            Write-Log "Failed to import module: $($_.Exception.Message)" -Level Error
            return @([PSCustomObject]@{ _Error = $_.Exception.Message })
        }

        # Inline model retrieval with per-step logging
        $TempDir = Join-Path $env:TEMP "DriverAutomationTool"
        if (-not (Test-Path $TempDir)) { New-Item -Path $TempDir -ItemType Directory -Force | Out-Null }

        $OEMLinksURL = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/OEMLinks.xml"
        $OEMLinksCache = Join-Path $TempDir "OEMLinks.xml"

        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $proxyParams = Get-DATWebRequestProxy
            if ($proxyParams -isnot [hashtable]) { $proxyParams = @{} }

            $LogQueue.Enqueue('[SOURCE:OEMLinks:Loading]')
            if (Test-CatalogFresh -FilePath $OEMLinksCache) {
                Write-Log "Using cached OEM catalog (less than 24h old)."
                [xml]$OEMLinks = Get-Content -Path $OEMLinksCache -Raw
                $LogQueue.Enqueue('[SOURCE:OEMLinks:Cached]')
            } else {
                Write-Log "Downloading OEM catalog from GitHub..."
                $webResponse = $null
                for ($retryAttempt = 1; $retryAttempt -le 3; $retryAttempt++) {
                    try {
                        $webResponse = Invoke-WebRequest -Uri $OEMLinksURL -UseBasicParsing -TimeoutSec 30 @proxyParams
                        break
                    } catch {
                        if ($retryAttempt -lt 3) {
                            Write-Log "OEM catalog download attempt $retryAttempt failed: $($_.Exception.Message). Retrying in 5s..." -Level Warn
                            Start-Sleep -Seconds 5
                    } else {
                        throw
                    }
                }
                }
                # Save to cache for future freshness checks
                $webResponse.Content | Set-Content -Path $OEMLinksCache -Force
                [xml]$OEMLinks = $webResponse.Content
                Write-Log "OEM catalog loaded (version $($OEMLinks.OEM.Version))." -Level Success
                $LogQueue.Enqueue('[SOURCE:OEMLinks:OK]')
            }
        } catch {
            Write-Log "Failed to download OEM catalog: $($_.Exception.Message)" -Level Error
            $LogQueue.Enqueue('[SOURCE:OEMLinks:Error]')
            return @([PSCustomObject]@{ _Error = "Cannot download OEM catalog: $($_.Exception.Message)" })
        }

        $WindowsBuild = $($OS).Split(" ")[2]
        $WindowsVersion = $OS.Trim("$WindowsBuild").TrimEnd()
        Write-Log "Parsed OS: Version=$WindowsVersion Build=$WindowsBuild"
        $OEMSupportedModels = @()

        foreach ($OEM in $RequiredOEMs) {
            Write-Log "--- Processing $OEM ---"
            $LogQueue.Enqueue("[SOURCE:${OEM}:Loading]")
            switch ($OEM) {
                "HP" {
                    $HPLink = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "HP" }).Link | Where-Object { $_.Type -eq "XMLCabinetSource" } | Select-Object -ExpandProperty URL -First 1
                    if ([string]::IsNullOrEmpty($HPLink)) {
                        Write-Log "No HP XMLCabinetSource URL found in OEM catalog." -Level Error
                        continue
                    }
                    Write-Log "HP catalog URL: $HPLink"
                    $HPCabFile = [string]($HPLink | Split-Path -Leaf)
                    $HPXMLFile = $HPCabFile.TrimEnd(".cab") + ".xml"
                    try {
                        $HPCabPath = Join-Path $TempDir $HPCabFile
                        $HPXMLPath = Join-Path $TempDir $HPXMLFile
                        if (Test-CatalogFresh -FilePath $HPXMLPath) {
                            Write-Log "Using cached HP catalog (less than 24h old)."
                            $LogQueue.Enqueue('[SOURCE:HP:Cached]')
                        } else {
                            Write-Log "Downloading HP driver pack catalog..."
                            $proxyParams = Get-DATWebRequestProxy
                            Invoke-WebRequest -Uri $HPLink -OutFile $HPCabPath -UseBasicParsing -TimeoutSec 60 @proxyParams
                            Write-Log "Extracting $HPCabFile..."
                            & expand.exe "$HPCabPath" -F:* "$TempDir" -R 2>&1 | Out-Null
                        }
                        if (-not (Test-Path $HPXMLPath)) {
                            Write-Log "Extracted XML not found at $HPXMLPath" -Level Error
                            continue
                        }
                        [xml]$HPModelXML = Get-Content -Path $HPXMLPath -Raw
                        $HPPacks = $HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
                        $HPMatches = $HPPacks | Where-Object { $_.OSName -match $WindowsVersion -and $_.OSName -match $WindowsBuild }
                        $count = @($HPMatches).Count
                        Write-Log "HP: Found $count matching driver packs." -Level Success
                        $LogQueue.Enqueue("[SOURCE:HP:OK:$count models]")
                        foreach ($Model in $HPMatches) {
                            $modelName = $($($Model.SystemName).TrimStart("HP")).Trim()
                            $OEMSupportedModels += [PSCustomObject]@{
                                OEM        = "HP"
                                Model      = $modelName
                                Baseboards = $Model.SystemId
                                OS         = $WindowsVersion
                                'OS Build' = $WindowsBuild
                                Version    = (Get-Date -Format 'ddMMyyyy')
                            }
                        }
                    } catch {
                        Write-Log "HP processing failed: $($_.Exception.Message)" -Level Error
                        $LogQueue.Enqueue('[SOURCE:HP:Error]')
                    }
                }
                "Dell" {
                    $DellLink = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "XMLCabinetSource" } | Select-Object -ExpandProperty URL -First 1
                    if ([string]::IsNullOrEmpty($DellLink)) {
                        Write-Log "No Dell XMLCabinetSource URL found in OEM catalog." -Level Error
                        continue
                    }
                    Write-Log "Dell catalog URL: $DellLink"
                    $DellCabFile = [string]($DellLink | Split-Path -Leaf)
                    $DellXMLFile = $DellCabFile.TrimEnd(".cab") + ".xml"
                    $DellWindowsVersion = $WindowsVersion.Replace(" ", "")
                    try {
                        $DellCabPath = Join-Path $TempDir $DellCabFile
                        $DellXMLPath = Join-Path $TempDir $DellXMLFile
                        if (Test-CatalogFresh -FilePath $DellXMLPath) {
                            Write-Log "Using cached Dell catalog (less than 24h old)."
                            $LogQueue.Enqueue('[SOURCE:Dell:Cached]')
                        } elseif (-not (Test-Path $DellCabPath) -or -not (Test-CatalogFresh -FilePath $DellCabPath)) {
                            Write-Log "Downloading Dell driver pack catalog..."
                            $proxyParams = Get-DATWebRequestProxy
                            Invoke-WebRequest -Uri $DellLink -OutFile $DellCabPath -UseBasicParsing -TimeoutSec 60 @proxyParams
                            Write-Log "Extracting $DellCabFile..."
                            & expand.exe "$DellCabPath" -F:* "$TempDir" -R 2>&1 | Out-Null
                        } else {
                            Write-Log "Extracting cached $DellCabFile..."
                            & expand.exe "$DellCabPath" -F:* "$TempDir" -R 2>&1 | Out-Null
                        }
                        if (-not (Test-Path $DellXMLPath)) {
                            Write-Log "Extracted Dell XML not found at $DellXMLPath" -Level Error
                            continue
                        }
                        [xml]$DellModelXML = Get-Content -Path $DellXMLPath -Raw
                        $DellPkgs = $DellModelXML.driverpackmanifest.driverpackage
                        $DellMatchingPkgs = $DellPkgs | Where-Object {
                            ($_.SupportedOperatingSystems.OperatingSystem.osCode -eq "$DellWindowsVersion") -and
                            ($_.SupportedOperatingSystems.OperatingSystem.osArch -match $Architecture)
                        }
                        $DellModels = $DellMatchingPkgs | Select-Object @{ Name = "SystemName"; Expression = { $_.SupportedSystems.Brand.Model.name | Select-Object -First 1 } },
                        @{ Name = "SystemID"; Expression = { $_.SupportedSystems.Brand.Model.SystemID } },
                        @{ Name = "DellVersion"; Expression = { $_.dellVersion } } -Unique |
                        Where-Object { $_.SystemName -gt $null }
                        $count = @($DellModels).Count
                        Write-Log "Dell: Found $count matching models." -Level Success
                        $LogQueue.Enqueue("[SOURCE:Dell:OK:$count models]")
                        foreach ($Model in $DellModels) {
                            $sysIds = $Model.SystemID | Where-Object { $_ } | Select-Object -Unique
                            $OEMSupportedModels += [PSCustomObject]@{
                                OEM        = "Dell"
                                Model      = $Model.SystemName
                                Baseboards = $(if ($sysIds) { $sysIds -join "," } else { "" })
                                OS         = $WindowsVersion
                                'OS Build' = $WindowsBuild
                                Version    = $Model.DellVersion
                            }
                        }
                    } catch {
                        Write-Log "Dell processing failed: $($_.Exception.Message)" -Level Error
                        $LogQueue.Enqueue('[SOURCE:Dell:Error]')
                    }
                }
                "Lenovo" {
                    $LenovoLink = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Lenovo" }).Link | Where-Object { $_.Type -eq "XMLSource" } | Select-Object -ExpandProperty URL -First 1
                    if ([string]::IsNullOrEmpty($LenovoLink)) {
                        Write-Log "No Lenovo XMLSource URL found in OEM catalog." -Level Error
                        continue
                    }
                    Write-Log "Lenovo catalog URL: $LenovoLink"
                    $LenovoFile = [string]($LenovoLink | Split-Path -Leaf)
                    try {
                        $LenovoFilePath = Join-Path $TempDir $LenovoFile
                        if (Test-CatalogFresh -FilePath $LenovoFilePath) {
                            Write-Log "Using cached Lenovo catalog (less than 24h old)."
                            $LogQueue.Enqueue('[SOURCE:Lenovo:Cached]')
                        } else {
                            Write-Log "Downloading Lenovo model catalog..."
                            $proxyParams = Get-DATWebRequestProxy
                            Invoke-WebRequest -Uri $LenovoLink -OutFile $LenovoFilePath -UseBasicParsing -TimeoutSec 60 @proxyParams
                        }
                        [xml]$LenovoModelXML = Get-Content -Path $LenovoFilePath
                        $LenovoDrivers = $LenovoModelXML.ModelList.Model
                        $WinVer = "Win" + "$($WindowsVersion.Split(' ')[1])"
                        Write-Log "Filtering Lenovo models for $WinVer build $WindowsBuild..."
                        $LenovoModels = ($LenovoDrivers | Where-Object {
                            ($_.SCCM.Version -eq $WindowsBuild -and $_.SCCM.OS -eq $WinVer)
                        } | Sort-Object).Name
                        $count = @($LenovoModels).Count
                        Write-Log "Lenovo: Found $count matching models." -Level Success
                        $LogQueue.Enqueue("[SOURCE:Lenovo:OK:$count models]")
                        foreach ($Model in $LenovoModels) {
                            $modelNode = $LenovoDrivers | Where-Object { $_.Name -eq $Model } | Select-Object -First 1
                            $baseboards = $modelNode.Types.Type
                            $baseboardStr = if ($null -ne $baseboards) { ([string]$baseboards).Replace(" ", ",").Trim() } else { "" }
                            # Get driver pack date from the matching SCCM node
                            $sccmNode = $modelNode.SCCM | Where-Object { $_.Version -eq $WindowsBuild -and $_.OS -eq $WinVer } | Select-Object -First 1
                            $lenovoDate = if ($sccmNode.date) { $sccmNode.date } else { '' }
                            # Check for supplemental NVIDIA GFX driver package
                            $gfxNode = $modelNode.GFX | Where-Object { $_.os -eq $WinVer -and $_.version -eq $WindowsBuild } | Select-Object -First 1
                            $hasGFX = $null -ne $gfxNode
                            $gfxBrand = if ($hasGFX) { $gfxNode.brand } else { $null }
                            if ($hasGFX) { Write-Log "Lenovo: $Model has supplemental $gfxBrand GFX driver package" }
                            $OEMSupportedModels += [PSCustomObject]@{
                                OEM        = "Lenovo"
                                Model      = $Model
                                Baseboards = $baseboardStr
                                OS         = $WindowsVersion
                                'OS Build' = $WindowsBuild
                                HasGFX     = $hasGFX
                                GFXBrand   = $gfxBrand
                                Version    = $lenovoDate
                            }
                        }
                    } catch {
                        Write-Log "Lenovo processing failed: $($_.Exception.Message)" -Level Error
                        $LogQueue.Enqueue('[SOURCE:Lenovo:Error]')
                    }
                }
                "Microsoft" {
                    # OEM LINK Temporary MS Hard Link
                    $MSLink = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/OSDMSDrivers.xml"
                    Write-Log "Microsoft catalog URL: $MSLink"
                    try {
                        $MSFilePath = Join-Path $TempDir "OSDMSDrivers.xml"
                        if (Test-CatalogFresh -FilePath $MSFilePath) {
                            Write-Log "Using cached Microsoft catalog (less than 24h old)."
                            $LogQueue.Enqueue('[SOURCE:Microsoft:Cached]')
                        } else {
                            Write-Log "Downloading Microsoft Surface catalog to $MSFilePath..."
                            $proxyParams = Get-DATWebRequestProxy
                            Invoke-WebRequest -Uri $MSLink -OutFile $MSFilePath -UseBasicParsing -TimeoutSec 15 @proxyParams
                            Write-Log "Microsoft catalog downloaded successfully." -Level Success
                        }
                        $MSFileSize = [math]::Round((Get-Item $MSFilePath).Length / 1KB, 1)
                        Write-Log "Reading Microsoft catalog from $MSFilePath ($($MSFileSize) KB)"
                        $MSModelList = Import-Clixml -Path $MSFilePath
                        $MSModelTotal = @($MSModelList).Count
                        Write-Log "Microsoft catalog contains $MSModelTotal total entries."
                        if ($MSModelTotal -gt 0) {
                            $sampleProperties = ($MSModelList | Select-Object -First 1).PSObject.Properties.Name -join ', '
                            Write-Log "Microsoft catalog properties: $sampleProperties"
                            $availableOSVersions = ($MSModelList | Select-Object -ExpandProperty OSVersion -ErrorAction SilentlyContinue | Sort-Object -Unique) -join ', '
                            Write-Log "Microsoft catalog OS versions: $availableOSVersions"
                        }
                        Write-Log "Filtering Microsoft models where OSVersion matches '$WindowsVersion'..."
                        $MSArchFilter = if ($Architecture -eq 'Arm64') { 'arm64' } else { 'amd64' }
                        Write-Log "Microsoft architecture filter: $MSArchFilter (from $Architecture)"
                        $MSFiltered = $MSModelList | Where-Object { $_.OSVersion -match $WindowsVersion -and $_.OSArchitecture -eq $MSArchFilter }
                        $MSModels = $MSFiltered | Group-Object -Property Model
                        $count = @($MSModels).Count
                        Write-Log "Microsoft: Found $count matching models after filtering." -Level $(if ($count -gt 0) { 'Success' } else { 'Warn' })
                        $LogQueue.Enqueue("[SOURCE:Microsoft:OK:$count models]")
                        if ($count -eq 0) {
                            Write-Log "No Microsoft models matched OSVersion='$WindowsVersion'. Check catalog OS versions above." -Level Warn
                        }
                        foreach ($MSModelGroup in $MSModels) {
                            $products = ($MSModelGroup.Group | Select-Object -ExpandProperty Product -Unique) -join ','
                            $latestEntry = $MSModelGroup.Group | Sort-Object { try { [datetime]$_.ReleaseDate } catch { [datetime]::MinValue } } -Descending | Select-Object -First 1
                            $msVersion = if ($latestEntry.ReleaseDate) { $latestEntry.ReleaseDate } else { '' }
                            $OEMSupportedModels += [PSCustomObject]@{
                                OEM        = "Microsoft"
                                Model      = $MSModelGroup.Name
                                Baseboards = $products
                                OS         = $WindowsVersion
                                'OS Build' = $WindowsBuild
                                Version    = $msVersion
                            }
                        }
                    } catch {
                        Write-Log "Microsoft processing failed: $($_.Exception.Message)" -Level Error
                        $LogQueue.Enqueue('[SOURCE:Microsoft:Error]')
                    }
                }
                "Acer" {
                    $AcerLink = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Acer" }).Link | Where-Object { $_.Type -eq "XMLSource" } | Select-Object -ExpandProperty URL -First 1
                    if ([string]::IsNullOrEmpty($AcerLink)) {
                        Write-Log "No Acer XMLSource URL found in OEM catalog." -Level Error
                        continue
                    }
                    Write-Log "Acer catalog URL: $AcerLink"
                    $AcerFile = [string]($AcerLink | Split-Path -Leaf)
                    try {
                        $AcerFilePath = Join-Path $TempDir $AcerFile
                        if (Test-CatalogFresh -FilePath $AcerFilePath) {
                            Write-Log "Using cached Acer catalog (less than 24h old)."
                            $LogQueue.Enqueue('[SOURCE:Acer:Cached]')
                        } else {
                            Write-Log "Downloading Acer model catalog..."
                            $proxyParams = Get-DATWebRequestProxy
                            Invoke-WebRequest -Uri $AcerLink -OutFile $AcerFilePath -UseBasicParsing -TimeoutSec 60 @proxyParams
                        }
                        [xml]$AcerModelXML = Get-Content -Path $AcerFilePath
                        $AcerDrivers = $AcerModelXML.ModelList.Model
                        $WinVer = "Win" + "$($WindowsVersion.Split(' ')[1])"
                        $AcerModels = ($AcerDrivers | Where-Object {
                            ($_.SCCM.Version -eq $WindowsBuild -and $_.SCCM.OS -eq $WinVer)
                        } | Sort-Object).Name
                        $count = @($AcerModels).Count
                        Write-Log "Acer: Found $count matching models." -Level Success
                        $LogQueue.Enqueue("[SOURCE:Acer:OK:$count models]")
                        foreach ($Model in $AcerModels) {
                            $OEMSupportedModels += [PSCustomObject]@{
                                OEM        = "Acer"
                                Model      = $Model
                                Baseboards = $Model
                                OS         = $WindowsVersion
                                'OS Build' = $WindowsBuild
                                Version    = (Get-Date -Format 'ddMMyyyy')
                            }
                        }
                    } catch {
                        Write-Log "Acer processing failed: $($_.Exception.Message)" -Level Error
                        $LogQueue.Enqueue('[SOURCE:Acer:Error]')
                    }
                }
            }
        }

        $totalCount = @($OEMSupportedModels).Count
        Write-Log "=== Complete: $totalCount total models found ===" -Level Success

        # ── BIOS version lookup: always enrich models with BIOS version from catalog ──
        if ($totalCount -gt 0) {
            Write-Log "Looking up BIOS versions for $totalCount models..."
            $LogQueue.Enqueue('[SOURCE:BIOS:Loading]')
            try {
                $biosCatalog = Get-DATBiosCatalog
            } catch {
                Write-Log "Failed to fetch BIOS catalog: $($_.Exception.Message)" -Level Warn
                $biosCatalog = @()
            }

            # Pre-build a device→entry hashtable for fast O(1) lookups instead of scanning per model
            $biosDeviceMap = @{}
            foreach ($entry in $biosCatalog) {
                if ([string]::IsNullOrEmpty($entry.SupportedDevices) -or [string]::IsNullOrEmpty($entry.DownloadURL)) { continue }
                $devices = $entry.SupportedDevices -split '[;\s]+' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ }
                foreach ($dev in $devices) {
                    $key = "$($entry.Manufacturer)|$dev"
                    $existing = $biosDeviceMap[$key]
                    if ($null -eq $existing) {
                        $biosDeviceMap[$key] = $entry
                    } else {
                        # Keep the entry with the latest release date
                        try {
                            if ([datetime]$entry.ReleaseDate -gt [datetime]$existing.ReleaseDate) {
                                $biosDeviceMap[$key] = $entry
                            }
                        } catch { }
                    }
                }
            }

            $biosMatched = 0
            foreach ($model in $OEMSupportedModels) {
                try {
                    # Microsoft Surface BIOS is updated via driver injection -- use driver version as BIOS version
                    if ($model.OEM -eq 'Microsoft') {
                        if (-not [string]::IsNullOrEmpty($model.Version)) {
                            $model | Add-Member -NotePropertyName 'BIOSVersion' -NotePropertyValue $model.Version -Force
                            $biosMatched++
                        }
                        continue
                    }
                    if ($model.OEM -eq 'Acer') {
                        # Acer uses XML catalog — use the existing function
                        $biosEntry = Find-DATBiosPackage -OEM $model.OEM -Baseboards $model.Baseboards -Catalog $biosCatalog
                    } else {
                        # Fast hashtable lookup for Dell/HP/Lenovo/Microsoft
                        $biosEntry = $null
                        $boards = $model.Baseboards -split '[,;\s]+' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ }
                        foreach ($board in $boards) {
                            $biosEntry = $biosDeviceMap["$($model.OEM)|$board"]
                            if ($null -ne $biosEntry) { break }
                        }
                    }
                    if ($null -ne $biosEntry -and -not [string]::IsNullOrEmpty($biosEntry.Version)) {
                        $model | Add-Member -NotePropertyName 'BIOSVersion' -NotePropertyValue $biosEntry.Version -Force
                        $biosMatched++
                    }
                } catch {
                    # Silently skip models with no BIOS match
                }
            }
            Write-Log "BIOS version lookup complete. Matched $biosMatched of $totalCount models." -Level Success
            $LogQueue.Enqueue("[SOURCE:BIOS:OK:$biosMatched matched]")
        }

        return $OEMSupportedModels
    })
    [void]$script:RefreshPS.AddArgument($CoreModulePath)
    [void]$script:RefreshPS.AddArgument($selectedOEMs)
    [void]$script:RefreshPS.AddArgument($selectedOS)
    [void]$script:RefreshPS.AddArgument($selectedArch)
    [void]$script:RefreshPS.AddArgument($selectedPackageType)

    $script:RefreshAsyncResult = $script:RefreshPS.BeginInvoke()

    # Poll for completion + drain log queue (keeps UI responsive)
    $script:RefreshTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:RefreshTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:RefreshTimer.Add_Tick({
        # Drain any pending log messages from the background thread
        Invoke-DATLogQueueDrain

        if ($script:RefreshAsyncResult.IsCompleted) {
            $script:RefreshTimer.Stop()

            # Final drain
            Invoke-DATLogQueueDrain

            try {
                $models = $script:RefreshPS.EndInvoke($script:RefreshAsyncResult)
                $streamErrors = $script:RefreshPS.Streams.Error

                # Show any stream errors in the activity log
                foreach ($streamErr in $streamErrors) {
                    Write-DATActivityLog "Stream error: $($streamErr.Exception.Message)" -Level Error
                }

                # Check for returned error object
                $errorResult = $models | Where-Object { $_ -is [PSCustomObject] -and $_._Error }
                if ($errorResult) {
                    Write-DATActivityLog "Fatal error: $($errorResult._Error)" -Level Error
                    $txt_Status.Text = "Error: $($errorResult._Error)"
                } else {
                    foreach ($model in ($models | Sort-Object OEM, Model)) {
                        if ($null -ne $model -and -not [string]::IsNullOrEmpty($model.Model) -and $null -eq $model._Error) {
                            $modelItem = [ModelItem]@{
                                Selected   = $false
                                OEM        = $model.OEM
                                Model      = $model.Model
                                OS         = $model.OS
                                Build      = $model.'OS Build'
                                Baseboards = $model.Baseboards
                                HasGFX     = if ($model.HasGFX) { $true } else { $false }
                                GFXBrand   = if ($model.GFXBrand) { $model.GFXBrand } else { '' }
                                Version    = if ($model.Version) { $model.Version } else { '' }
                            }
                            # BIOSVersion set separately — property may not exist on stale cached type
                            try { $modelItem.BIOSVersion = if ($model.BIOSVersion) { $model.BIOSVersion } else { '' } } catch { }
                            $script:ModelData.Add($modelItem)
                        }
                    }

                    $txt_ModelCount.Text = "$($script:ModelData.Count) models"
                    if ($script:ModelData.Count -gt 0) {
                        $txt_Status.Text = "Loaded $($script:ModelData.Count) supported models."
                        Write-DATActivityLog "Populated grid with $($script:ModelData.Count) models." -Level Success

                        # Log a per-OEM summary (counts only — individual models go to the log file)
                        $oemGroups = $script:ModelData | Group-Object -Property OEM | Sort-Object Name
                        foreach ($grp in $oemGroups) {
                            Write-DATActivityLog "  $($grp.Name): $($grp.Count) model(s)" -Level Info
                        }

                        # Auto-select models matching known Intune devices
                        Update-DATKnownModelSelection
                        # Restore previously saved model selections
                        Restore-DATModelSelections
                        # Persist the merged selection state (saved JSON + known models) immediately
                        Save-DATModelSelections
                    } else {
                        $txt_Status.Text = "No models found for the selected criteria."
                        Write-DATActivityLog "No models matched the selected criteria." -Level Warn
                    }
                }
            } catch {
                $txt_Status.Text = "Error processing results: $($_.Exception.Message)"
                Write-DATActivityLog "Result processing error: $($_.Exception.Message)" -Level Error
            } finally {
                $script:RefreshPS.Dispose()
                $script:RefreshRunspace.Dispose()
                $progress_Job.Visibility = 'Collapsed'
                $progress_Job.IsIndeterminate = $false
                $btn_RefreshModels.IsEnabled = $true
                Update-DATBuildButtonState
                # Auto-close the Loading Sources modal after a brief delay so users can see final status
                $script:SourceCloseTimer = [System.Windows.Threading.DispatcherTimer]::new()
                $script:SourceCloseTimer.Interval = [TimeSpan]::FromMilliseconds(1200)
                $script:SourceCloseTimer.Add_Tick({
                    $script:SourceCloseTimer.Stop()
                    Close-DATLoadingSourcesModal
                })
                $script:SourceCloseTimer.Start()
            }
        }
    })
    $script:RefreshTimer.Start()
})

# Model search filter - uses CollectionView to preserve sort state
$txt_ModelSearch.Add_TextChanged({
    $searchText = $txt_ModelSearch.Text
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($script:ModelData)
    if ([string]::IsNullOrEmpty($searchText)) {
        $view.Filter = $null
    } else {
        $view.Filter = [System.Predicate[object]]{
            param($item)
            $item.Model -like "*$searchText*" -or $item.OEM -like "*$searchText*"
        }
    }
    $grid_Models.ItemsSource = $view
})

$btn_SelectAll.Add_Click({
    # INPC fires for each item — CheckBoxes update automatically, no Refresh() needed
    foreach ($item in $script:ModelData) { $item.Selected = $true }
    Update-DATBuildButtonState
    Save-DATModelSelections
})

$btn_DeselectAll.Add_Click({
    foreach ($item in $script:ModelData) { $item.Selected = $false }
    Update-DATBuildButtonState
    Save-DATModelSelections
})

function Update-DATBuildButtonState {
    $selectedCount = ($script:ModelData | Where-Object { $_.Selected }).Count
    $btn_Build.IsEnabled = ($selectedCount -gt 0)
    $btn_Schedule.IsEnabled = ($selectedCount -gt 0)
    if ($script:ModelData.Count -gt 0) {
        $txt_ModelCount.Text = "$selectedCount of $($script:ModelData.Count) selected"
    }
}

function Save-DATModelSelections {
    <#
    .SYNOPSIS
        Persists the currently selected models to a JSON file in Settings\.
        Called when a build starts so selections are remembered across sessions.
        Stores OEM, Model and Baseboards so selections can be restored by baseboard
        match even when the model list changes (e.g. after an OS change).
    #>
    $settingsDir = Join-Path $global:ScriptDirectory 'Settings'
    if (-not (Test-Path $settingsDir)) { New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null }
    $jsonPath = Join-Path $settingsDir 'SelectedModels.json'

    $selections = @($script:ModelData | Where-Object { $_.Selected } | ForEach-Object {
        @{ OEM = $_.OEM; Model = $_.Model; Baseboards = $_.Baseboards }
    })
    $json = if ($selections.Count -eq 0) { '[]' } else { $selections | ConvertTo-Json -Depth 2 -Compress }
    Set-Content -Path $jsonPath -Value $json -Encoding UTF8 -Force
}

function Restore-DATModelSelections {
    <#
    .SYNOPSIS
        Restores previously selected models from the JSON file after a model refresh.
        First matches on OEM + Model name, then falls back to OEM + Baseboards overlap
        so selections survive OS changes where model names may differ but hardware IDs stay the same.
    #>
    $jsonPath = Join-Path $global:ScriptDirectory 'Settings\SelectedModels.json'
    if (-not (Test-Path $jsonPath)) { return }

    try {
        $saved = Get-Content -Path $jsonPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not $saved -or $saved.Count -eq 0) { return }

        # Build a HashSet for fast OEM|Model lookup
        $savedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $saved) {
            [void]$savedSet.Add("$($entry.OEM)|$($entry.Model)")
        }

        # Build per-OEM baseboard lookup: OEM -> set of individual baseboard values
        $savedBoardsByOEM = @{}
        foreach ($entry in $saved) {
            if ([string]::IsNullOrEmpty($entry.Baseboards)) { continue }
            $oem = $entry.OEM
            if (-not $savedBoardsByOEM.ContainsKey($oem)) {
                $savedBoardsByOEM[$oem] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }
            foreach ($bb in ($entry.Baseboards -split '[,;]+')) {
                $bb = $bb.Trim()
                if ($bb -ne '') { [void]$savedBoardsByOEM[$oem].Add($bb) }
            }
        }

        $matchCount = 0
        foreach ($item in $script:ModelData) {
            # Primary: exact OEM + Model match
            if ($savedSet.Contains("$($item.OEM)|$($item.Model)")) {
                $item.Selected = $true
                $matchCount++
                continue
            }

            # Fallback: OEM matches and any baseboard value overlaps
            if (-not [string]::IsNullOrEmpty($item.Baseboards) -and $savedBoardsByOEM.ContainsKey($item.OEM)) {
                $itemBoards = $item.Baseboards -split '[,;]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
                foreach ($bb in $itemBoards) {
                    if ($savedBoardsByOEM[$item.OEM].Contains($bb)) {
                        $item.Selected = $true
                        $matchCount++
                        break
                    }
                }
            }
        }

        if ($matchCount -gt 0) {
            Write-DATActivityLog "Restored $matchCount previously selected models" -Level Success
            Update-DATBuildButtonState
        }
    } catch {
        Write-DATActivityLog "Could not restore model selections: $($_.Exception.Message)" -Level Warn
    }
}

#endregion Model Selection Logic

#region Build Process

$btn_Build.Add_Click({
    # Check EULA acceptance before allowing build
    $eulaCheck = (Get-ItemProperty -Path $global:RegPath -Name "EULAAccepted" -ErrorAction SilentlyContinue).EULAAccepted
    if ($eulaCheck -ne "True") {
        # Navigate to About page and highlight the EULA requirement
        Set-DATActiveView -ViewName 'view_About' -NavButtonName 'nav_About'
        $txt_EulaWarning.Visibility = 'Visible'
        $txt_Status.Text = "Please accept the EULA to continue."
        Write-DATActivityLog "Build blocked — EULA not yet accepted" -Level Warn
        return
    }

    # Guard: prevent a second build while one is already running
    if ($script:BuildPS -and $script:BuildAsyncResult -and -not $script:BuildAsyncResult.IsCompleted) {
        $txt_Status.Text = "A build is already in progress. Use Abort to stop it first."
        Write-DATActivityLog "Build blocked — a build runspace is already running" -Level Warn
        return
    }

    # Guard: ensure the target platform is connected before building
    $buildPlatform = if ($null -ne $cmb_Platform.SelectedItem) { $cmb_Platform.SelectedItem.Content } else { 'Download Only' }
    if ($buildPlatform -eq 'Configuration Manager' -and [string]::IsNullOrEmpty($global:SiteCode)) {
        Show-DATInfoDialog -Title 'ConfigMgr Not Connected' `
            -Message 'Please connect to Configuration Manager before building packages. Navigate to ConfigMgr Settings to configure the site server connection.' `
            -Type Warning -ButtonLabel 'OK'
        Write-DATActivityLog "Build blocked — Configuration Manager not connected" -Level Warn
        return
    }
    if ($buildPlatform -eq 'Intune') {
        $authCheck = Get-DATIntuneAuthStatus
        if (-not $authCheck.IsAuthenticated) {
            Show-DATInfoDialog -Title 'Intune Not Connected' `
                -Message 'Please connect to Microsoft Intune before building packages. Navigate to Intune Settings > Environment to sign in.' `
                -Type Warning -ButtonLabel 'OK'
            Write-DATActivityLog "Build blocked — Intune not connected" -Level Warn
            return
        }
    }

    $selectedModels = $script:ModelData | Where-Object { $_.Selected -eq $true }
    if ($selectedModels.Count -eq 0) {
        $txt_Status.Text = "No models selected."
        return
    }

    # Read package type early so we can guard against invalid combinations
    $buildPackageType = if ($null -ne $cmb_PackageType -and $null -ne $cmb_PackageType.SelectedItem) { $cmb_PackageType.SelectedItem.Content } else { 'Drivers' }

    # Guard: Microsoft models do not support standalone BIOS packages
    if ($buildPackageType -eq 'BIOS') {
        $msModels = @($selectedModels | Where-Object { $_.OEM -eq 'Microsoft' })
        if ($msModels.Count -eq $selectedModels.Count) {
            # All selected models are Microsoft -- block the build entirely
            Show-DATInfoDialog -Title 'BIOS Packages Not Supported' `
                -Message "Microsoft Surface devices receive BIOS/firmware updates through the driver update process. Please select 'Drivers' or 'All' as the package type instead." `
                -Type Info -ButtonLabel 'OK'
            Write-DATActivityLog "Build blocked -- BIOS package type not supported for Microsoft models (firmware is included in driver updates)" -Level Warn
            return
        } elseif ($msModels.Count -gt 0) {
            # Mix of Microsoft and other OEMs -- warn and continue with non-Microsoft only
            $nonMsModels = @($selectedModels | Where-Object { $_.OEM -ne 'Microsoft' })
            $msNames = ($msModels | ForEach-Object { $_.Model }) -join ', '
            Show-DATInfoDialog -Title 'Microsoft Models Excluded' `
                -Message "Microsoft Surface devices receive BIOS/firmware updates through the driver update process. The following models will be skipped for BIOS packaging:`n`n$msNames`n`nProceeding with $($nonMsModels.Count) remaining model$(if ($nonMsModels.Count -ne 1) { 's' })." `
                -Type Warning -ButtonLabel 'Continue'
            Write-DATActivityLog "Microsoft models excluded from BIOS build: $msNames" -Level Warn
            # Replace selectedModels with non-Microsoft only
            $selectedModels = $nonMsModels
            if ($selectedModels.Count -eq 0) {
                $txt_Status.Text = "No eligible models remaining."
                return
            }
        }
    }

    $btn_Build.IsEnabled = $false
    $btn_Abort.IsEnabled = $true
    $progress_Job.Visibility = 'Visible'
    $progress_Job.IsIndeterminate = $false
    $progress_Job.Maximum = $selectedModels.Count
    $progress_Job.Value = 0

    # Store selected configuration (null-safe — #5)
    $selectedPlatform = if ($null -ne $cmb_Platform.SelectedItem) { $cmb_Platform.SelectedItem.Content } else { 'Download Only' }
    $selectedOS = if ($null -ne $cmb_OS.SelectedItem) { $cmb_OS.SelectedItem.Content } else { $null }
    $selectedArch = if ($null -ne $cmb_Architecture.SelectedItem) { $cmb_Architecture.SelectedItem.Content } else { 'x64' }

    Set-DATRegistryValue -Name "Platform" -Value "$selectedPlatform" -Type String
    Set-DATRegistryValue -Name "OS" -Value "$selectedOS" -Type String
    Set-DATRegistryValue -Name "Architecture" -Value "$selectedArch" -Type String

    $global:SelectedModels = [System.Collections.ArrayList]::new()
    foreach ($model in $selectedModels) {
        $modelObj = [PSCustomObject]@{
            OEM              = $model.OEM
            Model            = $model.Model
            Baseboards       = $model.Baseboards
            OS               = $selectedOS
            Architecture     = $selectedArch
            CustomDriverPath = $model.CustomDriverPath
            Version          = $model.Version
            BIOSVersion      = $(try { $model.BIOSVersion } catch { '' })
            ForceUpdate      = [bool]$model.ForceUpdate
        }
        $global:SelectedModels.Add($modelObj) | Out-Null
    }

    $global:SelectedModelCount = $global:SelectedModels.Count
    Save-DATModelSelections
    Set-DATRegistryValue -Name "SelectedModelCount" -Value "$($global:SelectedModelCount)" -Type String
    Set-DATRegistryValue -Name "TotalJobs" -Value "$($global:SelectedModelCount)" -Type String
    Set-DATRegistryValue -Name "CurrentJob" -Value "1" -Type String
    Set-DATRegistryValue -Name "CompletedJobs" -Value "0" -Type String
    Set-DATRegistryValue -Name "RunningState"  -Value "Starting" -Type String
    Set-DATRegistryValue -Name "RunningMode"   -Value "Download" -Type String
    Set-DATRegistryValue -Name "PackagePhase"  -Value "" -Type String
    Set-DATRegistryValue -Name "RunningMessage" -Value "Starting process. Checking pre-requisites..." -Type String
    Set-DATRegistryValue -Name "DownloadSize" -Value "---" -Type String
    Set-DATRegistryValue -Name "BytesTransferred" -Value "0" -Type String
    Set-DATRegistryValue -Name "DownloadBytes" -Value "0" -Type String
    Set-DATRegistryValue -Name "DownloadSpeed" -Value "---" -Type String

    $txt_Status.Text = "Building $($global:SelectedModelCount) packages..."
    $txt_Status.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['WindowForeground']))
    Write-DATActivityLog "Starting build for $($global:SelectedModelCount) models" -Level Info

    # Track elapsed time and show running status
    $script:BuildStartTime = Get-Date
    $pill_BuildStatus.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['AccentColor']))
    $txt_BuildStatusIcon.Text = [string][char]0xE916
    $txt_BuildStatusText.Text = "Running"
    $pill_BuildStatus.Visibility = 'Visible'
    $txt_BuildElapsed.Text = "00:00:00"
    $txt_BuildElapsed.Visibility = 'Visible'
    $script:BuildCompletionHandled = $false
    $script:BuildProgressLastJob = 0
    $script:BuildProgressLastCompletedJobs = 0
    $script:BuildLastLoggedMode = ''
    $script:BuildLastLoggedPct = -1

    # Show build progress panel
    $panel_BuildProgress.Visibility = 'Visible'
    $txt_BuildCurrentJob.Text = "1"
    $txt_BuildRemaining.Text = "$($global:SelectedModelCount)"
    $txt_BuildFileSize.Text = "---"
    $txt_BuildJobStatus.Text = "Starting process. Checking pre-requisites..."
    $progress_Download.Value = 0
    $txt_BuildDownloadPercent.Text = "0%"
    $txt_BuildDownloadSpeed.Text = ""
    $txt_BuildProgressLabel.Text = "Download:"

    # Show build progress modal with per-model pipeline stages
    Show-DATBuildProgressModal -Models $global:SelectedModels -Platform $selectedPlatform -PackageType $buildPackageType

    # Launch processing in a background job
    $script:BuildRunspace = [runspacefactory]::CreateRunspace()
    $script:BuildRunspace.ApartmentState = 'STA'
    $script:BuildRunspace.Open()
    $script:BuildPS = [powershell]::Create()
    $script:BuildPS.Runspace = $script:BuildRunspace
    [void]$script:BuildPS.AddScript({
        param($ModulePath, $ScriptDir, $RegPath, $RunningMode, $SelectedModels, $StoragePath, $PackagePath, $IntuneToken, $DisableToast, $SiteServer, $SiteCode, $PackageType, $DPGroups, $DPs, $DistPriority, $DebugBuildPath, $CustomBrandingPath, $HPPasswordBinPath, $ToastTimeoutAction, $MaxDeferrals, $TeamsWebhookUrl, $TeamsNotificationsEnabled, $CustomToastTitle, $CustomToastBody)
        try {
        Import-Module $ModulePath -Force
        $procParams = @{
            ScriptDirectory = $ScriptDir
            RegPath         = $RegPath
            RunningMode     = $RunningMode
            SelectedModels  = $SelectedModels
            StoragePath     = $StoragePath
            PackagePath     = $PackagePath
            IntuneAuthToken = $IntuneToken
        }
        if ($DisableToast) { $procParams['DisableToast'] = $true }
        if ($ToastTimeoutAction -ne 'RemindMeLater') { $procParams['ToastTimeoutAction'] = $ToastTimeoutAction }
        if ($MaxDeferrals -gt 0) { $procParams['MaxDeferrals'] = $MaxDeferrals }
        if (-not [string]::IsNullOrEmpty($DebugBuildPath)) { $procParams['DebugBuildPath'] = $DebugBuildPath }
        if (-not [string]::IsNullOrEmpty($CustomBrandingPath)) { $procParams['CustomBrandingPath'] = $CustomBrandingPath }
        if (-not [string]::IsNullOrEmpty($HPPasswordBinPath)) { $procParams['HPPasswordBinPath'] = $HPPasswordBinPath }
        if (-not [string]::IsNullOrEmpty($CustomToastTitle)) { $procParams['CustomToastTitle'] = $CustomToastTitle }
        if (-not [string]::IsNullOrEmpty($CustomToastBody)) { $procParams['CustomToastBody'] = $CustomToastBody }
        if (-not [string]::IsNullOrEmpty($SiteServer)) { $procParams['SiteServer'] = $SiteServer }
        if (-not [string]::IsNullOrEmpty($SiteCode)) { $procParams['SiteCode'] = $SiteCode }
        if (-not [string]::IsNullOrEmpty($PackageType)) { $procParams['PackageType'] = $PackageType }
        if ($DPGroups -and $DPGroups.Count -gt 0) { $procParams['DistributionPointGroups'] = $DPGroups }
        if ($DPs -and $DPs.Count -gt 0) { $procParams['DistributionPoints'] = $DPs }
        if (-not [string]::IsNullOrEmpty($DistPriority)) { $procParams['DistributionPriority'] = $DistPriority }
        if ($TeamsNotificationsEnabled -and -not [string]::IsNullOrEmpty($TeamsWebhookUrl)) {
            $procParams['TeamsNotificationsEnabled'] = $true
            $procParams['TeamsWebhookUrl'] = $TeamsWebhookUrl
        }
        Start-DATModelProcessing @procParams
        } catch [System.Management.Automation.PipelineStoppedException] {
            # Abort signal received — set registry state and exit cleanly
            try { Set-ItemProperty -Path $RegPath -Name 'RunningState' -Value 'Aborted' -Force -ErrorAction SilentlyContinue } catch {}
        }
    })
    $modulePath = Join-Path $PSScriptRoot "..\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psd1"

    # Read user-configured storage paths from registry
    $regConfig = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
    $tempStoragePath = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.TempStoragePath)) { $regConfig.TempStoragePath } else { Join-Path $global:ScriptDirectory 'Temp' }
    $packageStoragePath = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.PackageStoragePath)) { $regConfig.PackageStoragePath } else { $null }

    # Pass Intune auth token for Intune mode
    $intuneToken = if ($selectedPlatform -eq 'Intune') {
        # The token is stored in the module's script scope - use the exported accessor
        $authStatus = Get-DATIntuneAuthStatus
        if ($authStatus.IsAuthenticated) {
            # Access the module-internal token via the module's session state
            $coreModule = Get-Module -Name DriverAutomationToolCore
            if ($coreModule) {
                & $coreModule { $script:IntuneAuthToken }
            } else { $null }
        } else {
            Write-DATActivityLog "Intune platform selected but not authenticated. Build aborted." -Level Warn
            $txt_Status.Text = "Please authenticate to Intune before building packages."
            $txt_Status.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
            $btn_Build.IsEnabled = $true
            $btn_Abort.IsEnabled = $false
            $progress_Job.Visibility = 'Collapsed'
            $pill_BuildStatus.Visibility = 'Collapsed'
            $txt_BuildElapsed.Visibility = 'Collapsed'
            $panel_BuildProgress.Visibility = 'Collapsed'
            return
        }
    } else { $null }

    # Read the Disable Toast checkbox state (Intune only)
    $disableToast = ($selectedPlatform -eq 'Intune') -and ($chk_DisableToastPrompt.IsChecked -eq $true)

    # Read toast behaviour settings (Intune only)
    $biosTimeoutAction = if ($cmb_BIOSTimeoutAction.SelectedIndex -eq 1) { 'InstallNow' } else { 'RemindMeLater' }
    $biosMaxDeferrals  = if (($chk_EnableMaxDeferrals.IsChecked -eq $true) -and
        (-not [string]::IsNullOrEmpty($txt_MaxDeferrals.Text)) -and
        ($txt_MaxDeferrals.Text -match '^\d+$')) { [int]$txt_MaxDeferrals.Text } else { 0 }

    # Read the Debug Package Build state (Intune only)
    $debugBuildPath = if (($selectedPlatform -eq 'Intune') -and ($chk_DebugPackageBuild.IsChecked -eq $true) -and
        (-not [string]::IsNullOrEmpty($txt_DebugBuildPath.Text))) { $txt_DebugBuildPath.Text } else { $null }

    # Gather ConfigMgr settings for Configuration Manager mode
    $cmSiteServer = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.SiteServer)) { $regConfig.SiteServer } else { $null }
    $cmSiteCode = $global:SiteCode
    $cmPackageType = if ($null -ne $cmb_PackageType -and $null -ne $cmb_PackageType.SelectedItem) { $cmb_PackageType.SelectedItem.Content } else { 'Drivers' }
    $cmDPGroups = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.SelectedDPGroups)) { @($regConfig.SelectedDPGroups -split '\|') } else { @() }
    $cmDPs = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.SelectedDPs)) { @($regConfig.SelectedDPs -split '\|') } else { @() }
    $cmDistPriority = if ($null -ne $cmb_DistPriority -and $null -ne $cmb_DistPriority.SelectedItem) { $cmb_DistPriority.SelectedItem.Content } else { 'Normal' }

    [void]$script:BuildPS.AddArgument((Resolve-Path $modulePath).Path)
    [void]$script:BuildPS.AddArgument($global:ScriptDirectory)
    [void]$script:BuildPS.AddArgument($global:RegPath)
    [void]$script:BuildPS.AddArgument($selectedPlatform)
    [void]$script:BuildPS.AddArgument($global:SelectedModels.ToArray())
    [void]$script:BuildPS.AddArgument($tempStoragePath)
    [void]$script:BuildPS.AddArgument($packageStoragePath)
    [void]$script:BuildPS.AddArgument($intuneToken)
    [void]$script:BuildPS.AddArgument($disableToast)
    [void]$script:BuildPS.AddArgument($cmSiteServer)
    [void]$script:BuildPS.AddArgument($cmSiteCode)
    [void]$script:BuildPS.AddArgument($cmPackageType)
    [void]$script:BuildPS.AddArgument($cmDPGroups)
    [void]$script:BuildPS.AddArgument($cmDPs)
    [void]$script:BuildPS.AddArgument($cmDistPriority)
    [void]$script:BuildPS.AddArgument($debugBuildPath)
    [void]$script:BuildPS.AddArgument($script:CustomBrandingImagePath)
    [void]$script:BuildPS.AddArgument($script:HPPasswordBinPath)
    [void]$script:BuildPS.AddArgument($biosTimeoutAction)
    [void]$script:BuildPS.AddArgument($biosMaxDeferrals)

    # Teams notification settings
    $teamsEnabled = $chk_TeamsNotifications.IsChecked -eq $true
    $teamsUrl = $txt_TeamsWebhookUrl.Text
    [void]$script:BuildPS.AddArgument($teamsUrl)
    [void]$script:BuildPS.AddArgument($teamsEnabled)

    # Custom toast text (Intune only)
    $customToastTitle = if ($selectedPlatform -eq 'Intune') { $txt_CustomToastTitle.Text } else { $null }
    $customToastBody = if ($selectedPlatform -eq 'Intune') { $txt_CustomToastBody.Text } else { $null }
    [void]$script:BuildPS.AddArgument($customToastTitle)
    [void]$script:BuildPS.AddArgument($customToastBody)

    $script:BuildAsyncResult = $script:BuildPS.BeginInvoke()

    # Poll registry for progress updates (mirrors original timer_JobMonitor)
    $script:BuildProgressTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:BuildProgressTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:BuildProgressTimer.Add_Tick({
        # Guard against disposed-object access after window close (#14)
        if ($script:WindowClosing) { try { $script:BuildProgressTimer.Stop() } catch {}; return }
        try {

        # If completion already handled (normal finish or abort), just wait for runspace to fully stop
        if ($script:BuildCompletionHandled) {
            if ($null -eq $script:BuildAsyncResult -or $script:BuildAsyncResult.IsCompleted) {
                $script:BuildProgressTimer.Stop()
                if ($null -ne $script:BuildAsyncResult) {
                    try { $script:BuildPS.EndInvoke($script:BuildAsyncResult) } catch {
                        # Suppress expected abort noise — "pipeline stopped" and "object disposed"
                        # are normal when the runspace was forcibly stopped by the Abort button
                        $msg = $_.Exception.Message
                        if ($msg -notmatch 'pipeline.*stopped|object.*disposed|disposed.*object') {
                            Write-DATActivityLog "Build error: $msg" -Level Error
                        }
                    }
                    try {
                        foreach ($streamErr in $script:BuildPS.Streams.Error) {
                            if ($streamErr.Exception.Message -notmatch 'pipeline.*stopped|object.*disposed') {
                                Write-DATActivityLog "Background error: $($streamErr.Exception.Message)" -Level Error
                            }
                        }
                    } catch {
                        # Runspace may already be disposed — log only unexpected errors
                        if ($_.Exception.Message -notmatch 'object.*disposed|disposed.*object') {
                            Write-DATActivityLog "Error reading build stream: $($_.Exception.Message)" -Level Warn
                        }
                    }
                    try { $script:BuildPS.Dispose(); $script:BuildRunspace.Dispose() } catch { }
                    $script:BuildAsyncResult = $null
                    $script:BuildPS        = $null
                }
            }
            return
        }

        # Update elapsed time
        if ($script:BuildStartTime) {
            $elapsed = (Get-Date) - $script:BuildStartTime
            $txt_BuildElapsed.Text = "{0:hh\:mm\:ss}" -f $elapsed
        }

        # Update build progress modal from registry
        Update-DATBuildModalFromRegistry

        # Read registry for progress
        $regValues = $null
        try {
            $regValues = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
        } catch { }

        if ($regValues) {
            $stateMessage = [string]$regValues.RunningMessage
            $fileSize = [string]$regValues.DownloadSize
            $fileBytesSize = [string]$regValues.DownloadBytes
            $bytesTransferred = [string]$regValues.BytesTransferred
            $downloadSpeed = [string]$regValues.DownloadSpeed
            $currentJob = $regValues.CurrentJob
            $completedJobs = $regValues.CompletedJobs
            $totalJobs = $regValues.TotalJobs

            # Update status text
            if (-not [string]::IsNullOrEmpty($stateMessage)) {
                $txt_BuildJobStatus.Text = $stateMessage
            }

            # Determine current phase label
            $runMode = [string]$regValues.RunningMode
            if ($runMode -like 'Intune*' -or $runMode -like 'Upload*') {
                $txt_BuildProgressLabel.Text = "Upload:"
            } else {
                $txt_BuildProgressLabel.Text = "Download:"
            }

            # Relay phase transitions and milestones to the activity log
            if (-not [string]::IsNullOrEmpty($runMode) -and $runMode -ne $script:BuildLastLoggedMode) {
                # Phase changed — log the transition with the current message
                $logMsg = if (-not [string]::IsNullOrEmpty($stateMessage)) { $stateMessage } else { $runMode }
                Write-DATActivityLog $logMsg -Level Info
                $script:BuildLastLoggedMode = $runMode
                $script:BuildLastLoggedPct = -1
            }
            # Log upload/download progress at 25% intervals
            if (-not [string]::IsNullOrEmpty($stateMessage) -and $stateMessage -match '(\d+)%') {
                $msgPct = [int]$Matches[1]
                $pctMilestone = [math]::Floor($msgPct / 25) * 25
                if ($pctMilestone -gt 0 -and $pctMilestone -gt $script:BuildLastLoggedPct) {
                    Write-DATActivityLog $stateMessage -Level Info
                    $script:BuildLastLoggedPct = $pctMilestone
                }
            }

            # Update file size label
            if (-not [string]::IsNullOrEmpty($fileSize)) {
                $txt_BuildFileSize.Text = $fileSize
            }

            # Update download progress — cast to [long] to avoid string comparison pitfalls
            $fileBytesLong     = [long]0
            $bytesTransferLong = [long]0
            $null = [long]::TryParse($fileBytesSize,     [ref]$fileBytesLong)
            $null = [long]::TryParse($bytesTransferred,  [ref]$bytesTransferLong)

            if ($fileBytesLong -gt 0 -and $bytesTransferLong -gt 0) {
                $downloadPct = [math]::Min(100, [math]::Round(($bytesTransferLong / $fileBytesLong) * 100, 0))
                $progress_Download.Value = $downloadPct
                $txt_BuildDownloadPercent.Text = "$downloadPct%"
            }

            # Update download speed label
            if (-not [string]::IsNullOrEmpty($downloadSpeed) -and $downloadSpeed -ne '---') {
                $txt_BuildDownloadSpeed.Text = $downloadSpeed
            } else {
                $txt_BuildDownloadSpeed.Text = ""
            }

            # Update counters and overall progress (#12 — safe int parse)
            $completed = 0; $total = 0; $current = 0
            $hasJobs = $false
            if ($null -ne $completedJobs -and $null -ne $totalJobs) {
                $hasJobs = [int]::TryParse([string]$completedJobs, [ref]$completed) -and
                           [int]::TryParse([string]$totalJobs, [ref]$total)
            }
            if ($hasJobs -and $total -gt 0) {
                $null = [int]::TryParse([string]$currentJob, [ref]$current)
                if ($current -le 0) { $current = $completed + 1 }

                $txt_BuildCurrentJob.Text = "$current / $total"
                $txt_BuildRemaining.Text = "$([math]::Max(0, $total - $completed))"

                if ($completed -le $total) {
                    $progress_Job.Value = $completed
                }
            }
        }

        # Detect completion from registry state OR runspace completing
        $isRegistryComplete = $false
        if ($regValues) {
            $runState = [string]$regValues.RunningState
            $isRegistryComplete = ($runState -eq 'Completed' -or $runState -eq 'CompletedWithErrors')
            # If state is Aborted, the abort handler owns cleanup — skip completion processing
            if ($runState -eq 'Aborted') {
                try { $script:BuildProgressTimer.Stop() } catch {}
                return
            }
        }
        $isRunspaceComplete = ($null -ne $script:BuildAsyncResult) -and $script:BuildAsyncResult.IsCompleted

        if ($isRegistryComplete -or $isRunspaceComplete) {
            $script:BuildCompletionHandled = $true

            # If runspace is done, clean it up now and stop the timer
            $streamErrors = @()
            if ($isRunspaceComplete) {
                $script:BuildProgressTimer.Stop()
                try { $script:BuildPS.EndInvoke($script:BuildAsyncResult) } catch {
                    # Only suppress expected pipeline/disposed noise (#3)
                    $msg = $_.Exception.Message
                    if ($msg -notmatch 'pipeline.*stopped|object.*disposed|disposed.*object') {
                        Write-DATActivityLog "Build error: $msg" -Level Error
                    }
                }
                $streamErrors = @($script:BuildPS.Streams.Error)
                foreach ($streamErr in $streamErrors) {
                    Write-DATActivityLog "Background error: $($streamErr.Exception.Message)" -Level Error
                }
                try { $script:BuildPS.Dispose(); $script:BuildRunspace.Dispose() } catch { }
            }
            # If only registry complete (runspace still running), timer continues for cleanup

            # Always re-read registry AFTER EndInvoke — $regValues was captured at the start of
            # this tick and may be stale (the runspace writes its final state just before it exits,
            # so a tick that fires exactly on completion would see the old "Running" snapshot).
            $finalReg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
            $finalMessage = if ($finalReg -and -not [string]::IsNullOrEmpty($finalReg.RunningMessage)) {
                $finalReg.RunningMessage
            } else { "Build process completed." }

            # Freeze elapsed time
            $totalElapsed = if ($script:BuildStartTime) {
                $e = (Get-Date) - $script:BuildStartTime
                "{0:hh\:mm\:ss}" -f $e
            } else { "" }
            $txt_BuildElapsed.Text = $totalElapsed
            $script:BuildStartTime = $null

            # Determine success or failure (#12 — safe int parse)
            $runningState = if ($finalReg) { [string]$finalReg.RunningState } else { "" }
            $fCompJobs = 0; $fTotalJobs = 1
            if ($finalReg -and $finalReg.CompletedJobs) { $null = [int]::TryParse([string]$finalReg.CompletedJobs, [ref]$fCompJobs) }
            if ($finalReg -and $finalReg.TotalJobs)     { $null = [int]::TryParse([string]$finalReg.TotalJobs, [ref]$fTotalJobs); if ($fTotalJobs -le 0) { $fTotalJobs = 1 } }
            $hadErrors = ($streamErrors.Count -gt 0) -or
                         ($finalMessage -match 'failed|error|aborted') -or
                         ($runningState -eq 'CompletedWithErrors') -or
                         ($fCompJobs -lt $fTotalJobs)
            $isNoMatch = ($runningState -eq 'CompletedNoMatch')
            if ($isNoMatch) {
                # BIOS-only build with no catalog matches — show warning amber state
                $theme = Get-DATTheme -ThemeName $script:CurrentTheme
                $pill_BuildStatus.Background = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusWarning']))
                $txt_BuildStatusIcon.Text = [string][char]0xE7BA  # Warning icon
                $txt_BuildStatusIcon.Foreground = [System.Windows.Media.Brushes]::Black
                $txt_BuildStatusText.Text = "No Match"
                $txt_BuildStatusText.Foreground = [System.Windows.Media.Brushes]::Black
                $txt_Status.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusWarning']))
            } elseif ($hadErrors) {
                $pill_BuildStatus.Background = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString(
                        (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
                $txt_BuildStatusIcon.Text = [string][char]0xEA39
                $txt_BuildStatusText.Text = "Failed"
                $txt_Status.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString(
                        (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
            } else {
                $pill_BuildStatus.Background = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString(
                        (Get-DATTheme -ThemeName $script:CurrentTheme)['ButtonSuccess']))
                $txt_BuildStatusIcon.Text = [string][char]0xE73E
                $txt_BuildStatusText.Text = "Succeeded"
                $txt_Status.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString(
                        (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusSuccess']))
            }

            $panel_BuildProgress.Visibility = 'Collapsed'
            $progress_Job.Visibility = 'Collapsed'
            $btn_Build.IsEnabled = $true
            $btn_Abort.IsEnabled = $false
            $txt_Status.Text = "$finalMessage ($totalElapsed)"
            Write-DATActivityLog "$finalMessage (elapsed: $totalElapsed)" -Level $(if ($hadErrors) { 'Error' } elseif ($isNoMatch) { 'Warn' } else { 'Success' })

            # Close build progress modal — mark remaining as success if build succeeded (skip no-match)
            Close-DATBuildProgressModal -MarkAllSuccess:$(-not $hadErrors -and -not $isNoMatch)

            # Show build summary dialog with per-type success/fail counts
            try {
                $sumReg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
                $sumDriverPkgs = 0; $sumBiosPkgs = 0
                if ($sumReg.CompletedDriverPackages) { [int]::TryParse($sumReg.CompletedDriverPackages, [ref]$sumDriverPkgs) | Out-Null }
                if ($sumReg.CompletedBiosPackages) { [int]::TryParse($sumReg.CompletedBiosPackages, [ref]$sumBiosPkgs) | Out-Null }
                $sumPkgType = if ($sumReg.PackageType) { [string]$sumReg.PackageType } else { 'Drivers' }
                Show-DATBuildSummaryDialog -TotalModels $fTotalJobs `
                    -DriverSuccess $sumDriverPkgs -BiosSuccess $sumBiosPkgs `
                    -PackageType $sumPkgType -Elapsed $totalElapsed -HadErrors $hadErrors
            } catch {
                Write-DATLogEntry -Value "[UI] Build summary dialog error: $($_.Exception.Message)" -Severity 2
            }

            # Submit telemetry summary for this build session
            try {
                $telePlatform = if ($null -ne $cmb_Platform.SelectedItem) { $cmb_Platform.SelectedItem.Content } else { 'Unknown' }
                $fDriverPkgs = 0
                $fBiosPkgs = 0
                $finalReg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
                if ($finalReg.CompletedDriverPackages) { [int]::TryParse($finalReg.CompletedDriverPackages, [ref]$fDriverPkgs) | Out-Null }
                if ($finalReg.CompletedBiosPackages) { [int]::TryParse($finalReg.CompletedBiosPackages, [ref]$fBiosPkgs) | Out-Null }
                Send-DATSummaryReport -DriverPackagesCreated $fDriverPkgs `
                    -BiosPackagesCreated $fBiosPkgs `
                    -ModelsProcessed $fTotalJobs `
                    -Platform $telePlatform `
                    -ExecutionMode $global:ExecutionMode
            } catch {
                Write-DATLogEntry -Value "[Telemetry] Summary report failed: $($_.Exception.Message)" -Severity 2
            }

            # Package retention post-run cleanup
            if (-not $hadErrors -and -not $isNoMatch -and
                $null -ne $chk_PackageRetentionEnabled -and $chk_PackageRetentionEnabled.IsChecked) {
                try {
                    # Build the list of model keys from the selected models grid
                    $retainCount = 0
                    if ($null -ne $cmb_RetentionCount -and $cmb_RetentionCount.SelectedItem) {
                        $retainCount = [int]$cmb_RetentionCount.SelectedItem.Content
                    }
                    $platform = if ($null -ne $cmb_Platform.SelectedItem) { $cmb_Platform.SelectedItem.Content } else { '' }
                    $isIntune  = $platform -match 'Intune'
                    $isCM      = $platform -match 'ConfigMgr|SCCM|MECM'
                    $selectedOS   = if ($null -ne $cmb_OperatingSystem.SelectedItem) { $cmb_OperatingSystem.SelectedItem.Content } else { 'Windows 11' }
                    $selectedArch = if ($null -ne $cmb_Architecture.SelectedItem)     { $cmb_Architecture.SelectedItem.Content }     else { 'x64' }
                    $modelKeys = @()
                    if ($null -ne $script:SelectedModels) {
                        $modelKeys = @($script:SelectedModels | ForEach-Object {
                            "$($_.OEM)|$($_.Model)|$selectedOS|$selectedArch|$($_.PackageType)"
                        })
                    }
                    if ($modelKeys.Count -gt 0) {
                        $retentionParams = @{
                            ModelKeys   = $modelKeys
                            RetainCount = $retainCount
                        }
                        if ($isCM) {
                            $cmSiteServer = if ($null -ne $txt_SiteServer) { $txt_SiteServer.Text } else { '' }
                            $cmSiteCode   = if ($null -ne $txt_SiteCode)   { $txt_SiteCode.Text }   else { '' }
                            if ($cmSiteServer -and $cmSiteCode) {
                                $retentionParams['SiteServer'] = $cmSiteServer
                                $retentionParams['SiteCode']   = $cmSiteCode
                            }
                        }
                        if ($isIntune) { $retentionParams['Intune'] = $true }
                        Show-DATPackageRetentionModal @retentionParams
                    }
                } catch {
                    Write-DATLogEntry -Value "[Retention] Post-build cleanup error: $($_.Exception.Message)" -Severity 2
                }
            }
        }
        } catch {
            # Safety net — prevent timer tick exceptions from crashing the WPF app
            try { $script:BuildProgressTimer.Stop() } catch {}
        }
    })
    $script:BuildProgressTimer.Start()
})

$btn_Abort.Add_Click({
    try {
        # Update UI immediately — do NOT block the UI thread with Stop()/EndInvoke()
        $txt_Status.Text = "Aborting..."

        # Stop the progress timer so no more progress updates fire
        if ($script:BuildProgressTimer) {
            try { $script:BuildProgressTimer.Stop() } catch {}
        }

        # Signal abort via registry FIRST — the monitoring loop checks this and exits early
        Set-DATRegistryValue -Name "RunningState" -Type String -Value "Aborted"

        # Kill child processes inline on the UI thread.  Process kills are sub-millisecond
        # each, so they will NOT freeze the UI.  The previous ThreadPool approach shared the
        # PowerShell session state with the UI thread — concurrent cmdlet execution from two
        # threads corrupted the session state and crashed the process seconds later.

        # Kill any child process registered in the registry (curl / DISM)
        try {
            $RegProps = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
            $RunningProcessID   = $RegProps.RunningProcessID
            $RunningProcessName = $RegProps.RunningProcess
            $pidVal = 0
            if (-not [string]::IsNullOrEmpty($RunningProcessID) -and [int]::TryParse($RunningProcessID, [ref]$pidVal)) {
                if ($pidVal -gt 0 -and $pidVal -ne $PID) {
                    Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue
                }
            } elseif (-not [string]::IsNullOrEmpty($RunningProcessName) -and
                      $RunningProcessName -notmatch '^(powershell|pwsh)$') {
                Get-Process -Name $RunningProcessName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }
        } catch {}

        # Kill orphaned DISM/dismhost processes
        foreach ($procName in @('dismhost', 'dism')) {
            Get-Process -Name $procName -ErrorAction SilentlyContinue | ForEach-Object {
                try { $_.Kill() } catch {}
            }
        }

        # Kill any running HP SoftPaq self-extracting processes (SP*.exe)
        Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -match '^SP\d+$'
        } | ForEach-Object {
            try { $_.Kill() } catch {}
        }

        # Kill any running curl processes spawned by the tool
        Get-Process -Name 'curl' -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_.Kill() } catch {}
        }

        # Signal the runspace to stop — BeginStop is fire-and-forget, does NOT block the UI thread.
        # The runspace will complete asynchronously; CleanupTimer below handles Dispose once done.
        if ($script:BuildPS) {
            try { [void]$script:BuildPS.BeginStop($null, $null) } catch {}
        }

        # Fire-and-forget DISM cleanup — runs in a separate process so no session state conflict.
        # The Window.Closing handler also does this, but we want to clean up promptly after abort.
        try {
            Start-Process -FilePath "$env:SystemRoot\System32\dism.exe" `
                -ArgumentList '/Cleanup-Wim' -WindowStyle Hidden
        } catch {}

        # Close build progress modal without marking remaining as success
        if ($script:BuildModal) {
            try { $script:BuildModal.Close() } catch { }
            $script:BuildModal = $null
            $script:BuildModalRows = @{}
        }

        $panel_BuildProgress.Visibility = 'Collapsed'
        $progress_Job.Visibility = 'Collapsed'
        $btn_Build.IsEnabled = $true
        $btn_Abort.IsEnabled = $false

        # Show aborted status with elapsed time
        $totalElapsed = if ($script:BuildStartTime) {
            $e = (Get-Date) - $script:BuildStartTime
            "{0:hh\:mm\:ss}" -f $e
        } else { "" }
        $txt_BuildElapsed.Text = $totalElapsed
        $pill_BuildStatus.Background = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
        $txt_BuildStatusIcon.Text = [string][char]0xE7BA
        $txt_BuildStatusIcon.Foreground = [System.Windows.Media.Brushes]::Black
        $txt_BuildStatusText.Text = "Aborted"
        $txt_BuildStatusText.Foreground = [System.Windows.Media.Brushes]::Black
        $txt_Status.Text = "Build process aborted ($totalElapsed)"
    } catch {
        # Catch-all for the abort handler — prevents unhandled exceptions from crashing WPF
        try { $txt_Status.Text = "Abort encountered an error: $($_.Exception.Message)" } catch {}
    } finally {
        $script:BuildStartTime = $null
        $script:BuildCompletionHandled = $true

        # Start a lightweight cleanup timer that waits for the runspace to fully stop,
        # then disposes it — all off the UI thread (just a polling check every 500ms).
        $script:CleanupTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:CleanupTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $script:CleanupTimer.Add_Tick({
            try {
                if ($null -eq $script:BuildAsyncResult -or $script:BuildAsyncResult.IsCompleted) {
                    $script:CleanupTimer.Stop()
                    if ($script:BuildAsyncResult) {
                        try { $script:BuildPS.EndInvoke($script:BuildAsyncResult) } catch {}
                    }
                    try { $script:BuildPS.Dispose()      } catch {}
                    try { $script:BuildRunspace.Dispose() } catch {}

                    # Kill any DISM/dismhost processes orphaned by the now-stopped runspace
                    foreach ($procName in @('dismhost', 'dism')) {
                        Get-Process -Name $procName -ErrorAction SilentlyContinue | ForEach-Object {
                            try { $_.Kill() } catch {}
                        }
                    }
                    $script:BuildAsyncResult = $null
                    $script:BuildPS          = $null
                    $script:BuildRunspace    = $null
                }
            } catch {
                # Safety net — prevent timer tick exceptions from crashing the app
                try { $script:CleanupTimer.Stop() } catch {}
            }
        })
        $script:CleanupTimer.Start()
    }
})

#endregion Build Process

#region ConfigMgr Connection

# Site Server Info panel controls
$panel_SiteServerInfo = $Window.FindName('panel_SiteServerInfo')
$txt_ServerIP = $Window.FindName('txt_ServerIP')
$txt_ServerSiteCode = $Window.FindName('txt_ServerSiteCode')
$txt_ServerCMVersion = $Window.FindName('txt_ServerCMVersion')
$txt_ServerOSVersion = $Window.FindName('txt_ServerOSVersion')
$txt_ServerPackageCount = $Window.FindName('txt_ServerPackageCount')

# Package chart controls
$panel_PackageChart = $Window.FindName('panel_PackageChart')
$arc_Drivers = $Window.FindName('arc_Drivers')
$arc_Bios = $Window.FindName('arc_Bios')
$arc_Other = $Window.FindName('arc_Other')
$txt_ChartDriverCount = $Window.FindName('txt_ChartDriverCount')
$txt_ChartBiosCount = $Window.FindName('txt_ChartBiosCount')
$txt_ChartOtherCount = $Window.FindName('txt_ChartOtherCount')

# Manufacturer chart controls
$arc_Mfr_Dell = $Window.FindName('arc_Mfr_Dell')
$arc_Mfr_HP = $Window.FindName('arc_Mfr_HP')
$arc_Mfr_Lenovo = $Window.FindName('arc_Mfr_Lenovo')
$arc_Mfr_Microsoft = $Window.FindName('arc_Mfr_Microsoft')
$arc_Mfr_Acer = $Window.FindName('arc_Mfr_Acer')
$arc_Mfr_Other = $Window.FindName('arc_Mfr_Other')
$txt_MfrDellCount = $Window.FindName('txt_MfrDellCount')
$txt_MfrHPCount = $Window.FindName('txt_MfrHPCount')
$txt_MfrLenovoCount = $Window.FindName('txt_MfrLenovoCount')
$txt_MfrMicrosoftCount = $Window.FindName('txt_MfrMicrosoftCount')
$txt_MfrAcerCount = $Window.FindName('txt_MfrAcerCount')
$txt_MfrOtherCount = $Window.FindName('txt_MfrOtherCount')

function New-DATDonutArc {
    param (
        [double]$StartAngle,
        [double]$SweepAngle,
        [double]$CenterX = 60,
        [double]$CenterY = 60,
        [double]$Radius = 42
    )
    if ($SweepAngle -le 0) { return $null }
    # Clamp to avoid full-circle rendering issues
    if ($SweepAngle -ge 360) { $SweepAngle = 359.99 }

    $startRad = ($StartAngle - 90) * [Math]::PI / 180
    $endRad = ($StartAngle + $SweepAngle - 90) * [Math]::PI / 180

    $x1 = $CenterX + $Radius * [Math]::Cos($startRad)
    $y1 = $CenterY + $Radius * [Math]::Sin($startRad)
    $x2 = $CenterX + $Radius * [Math]::Cos($endRad)
    $y2 = $CenterY + $Radius * [Math]::Sin($endRad)

    $largeArc = if ($SweepAngle -gt 180) { 1 } else { 0 }

    $geometry = [System.Windows.Media.StreamGeometry]::new()
    $ctx = $geometry.Open()
    $ctx.BeginFigure([System.Windows.Point]::new($x1, $y1), $false, $false)
    $ctx.ArcTo(
        [System.Windows.Point]::new($x2, $y2),
        [System.Windows.Size]::new($Radius, $Radius),
        0,
        ($largeArc -eq 1),
        [System.Windows.Media.SweepDirection]::Clockwise,
        $true,
        $false
    )
    $ctx.Close()
    $geometry.Freeze()
    return $geometry
}

function Update-DATPackageDonutChart {
    param ([int]$DriverCount, [int]$BiosCount, [int]$OtherCount)

    $txt_ChartDriverCount.Text = $DriverCount.ToString('N0')
    $txt_ChartBiosCount.Text = $BiosCount.ToString('N0')
    $txt_ChartOtherCount.Text = $OtherCount.ToString('N0')

    $total = $DriverCount + $BiosCount + $OtherCount
    if ($total -eq 0) {
        $arc_Drivers.Data = $null
        $arc_Bios.Data = $null
        $arc_Other.Data = $null
        return
    }

    $driverSweep = ($DriverCount / $total) * 360
    $biosSweep = ($BiosCount / $total) * 360
    $otherSweep = ($OtherCount / $total) * 360

    $startAngle = 0.0
    $arc_Drivers.Data = New-DATDonutArc -StartAngle $startAngle -SweepAngle $driverSweep
    $startAngle += $driverSweep
    $arc_Bios.Data = New-DATDonutArc -StartAngle $startAngle -SweepAngle $biosSweep
    $startAngle += $biosSweep
    $arc_Other.Data = New-DATDonutArc -StartAngle $startAngle -SweepAngle $otherSweep
}

function Update-DATManufacturerDonutChart {
    param ([hashtable]$Counts)

    $txt_MfrDellCount.Text = ($Counts['Dell']).ToString('N0')
    $txt_MfrHPCount.Text = ($Counts['HP']).ToString('N0')
    $txt_MfrLenovoCount.Text = ($Counts['Lenovo']).ToString('N0')
    $txt_MfrMicrosoftCount.Text = ($Counts['Microsoft']).ToString('N0')
    $txt_MfrAcerCount.Text = ($Counts['Acer']).ToString('N0')
    $txt_MfrOtherCount.Text = ($Counts['Other']).ToString('N0')

    $total = ($Counts.Values | Measure-Object -Sum).Sum
    $arcMap = @{
        'Dell'      = $arc_Mfr_Dell
        'HP'        = $arc_Mfr_HP
        'Lenovo'    = $arc_Mfr_Lenovo
        'Microsoft' = $arc_Mfr_Microsoft
        'Acer'      = $arc_Mfr_Acer
        'Other'     = $arc_Mfr_Other
    }

    if ($total -eq 0) {
        foreach ($arc in $arcMap.Values) { $arc.Data = $null }
        return
    }

    $startAngle = 0.0
    foreach ($key in @('Dell', 'HP', 'Lenovo', 'Microsoft', 'Acer', 'Other')) {
        $sweep = ($Counts[$key] / $total) * 360
        $arcMap[$key].Data = New-DATDonutArc -StartAngle $startAngle -SweepAngle $sweep
        $startAngle += $sweep
    }
}

function Reset-DATSiteServerInfoPanel {
    $txt_ServerIP.Text = [char]0x2014
    $txt_ServerSiteCode.Text = [char]0x2014
    $txt_ServerCMVersion.Text = [char]0x2014
    $txt_ServerOSVersion.Text = [char]0x2014
    $txt_ServerPackageCount.Text = [char]0x2014
    $panel_SiteServerInfo.Visibility = 'Collapsed'
    $panel_PackageChart.Visibility = 'Collapsed'
}

function Invoke-DATConfigMgrConnect {
    param ([string]$SiteServer, [bool]$UseSSL)

    if ([string]::IsNullOrEmpty($SiteServer)) {
        $txt_SiteCode.Foreground = $Window.FindResource('StatusWarning')
        $txt_SiteCode.Text = "Please enter a site server."
        Reset-DATSiteServerInfoPanel
        return
    }

    # Show attempting status
    $txt_SiteCode.Foreground = $Window.FindResource('StatusInfo')
    $txt_SiteCode.Text = "Attempting connection..."
    Reset-DATSiteServerInfoPanel
    $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [action]{})

    try {
        Connect-DATConfigMgr -SiteServer $SiteServer -WinRMOverSSL $UseSSL | Out-Null
        if (-not [string]::IsNullOrEmpty($global:SiteCode)) {
            $txt_SiteCode.Foreground = $Window.FindResource('StatusSuccess')
            $txt_SiteCode.Text = "Connected - Site Code: $($global:SiteCode)"
            Set-DATRegistryValue -Name "SiteServer" -Value $SiteServer -Type String
            Set-DATRegistryValue -Name "WinRMSSL" -Value ([int]$UseSSL) -Type DWord

            # Populate site server information panel
            $txt_ServerSiteCode.Text = $global:SiteCode

            # IP Address
            try {
                $ipAddresses = [System.Net.Dns]::GetHostAddresses($SiteServer) |
                    Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                    Select-Object -ExpandProperty IPAddressToString
                $txt_ServerIP.Text = if ($ipAddresses) { ($ipAddresses -join ', ') } else { 'Unable to resolve' }
            } catch {
                $txt_ServerIP.Text = 'Unable to resolve'
            }

            # ConfigMgr Version
            try {
                Write-DATActivityLog "[WMI] \\$SiteServer\root\SMS\Site_$($global:SiteCode) : SMS_Site" -Level Info
                $cmVersion = Get-WmiObject -ComputerName $SiteServer -Namespace "root\SMS\Site_$($global:SiteCode)" -Class SMS_Site -ErrorAction Stop |
                    Select-Object -ExpandProperty Version
                $txt_ServerCMVersion.Text = if ($cmVersion) { $cmVersion } else { 'Not available' }
                Write-DATActivityLog "[WMI] ConfigMgr version: $cmVersion" -Level Info
            } catch {
                $txt_ServerCMVersion.Text = 'Not available'
            }

            # Server OS Version
            try {
                Write-DATActivityLog "[WMI] \\$SiteServer\root\cimv2 : Win32_OperatingSystem" -Level Info
                $osInfo = Get-WmiObject -ComputerName $SiteServer -Class Win32_OperatingSystem -ErrorAction Stop
                $txt_ServerOSVersion.Text = if ($osInfo) { "$($osInfo.Caption) ($($osInfo.Version))" } else { 'Not available' }
                Write-DATActivityLog "[WMI] Site server OS: $($osInfo.Caption) ($($osInfo.Version))" -Level Info
            } catch {
                $txt_ServerOSVersion.Text = 'Not available'
            }

            # Package Count and Breakdown
            try {
                Write-DATActivityLog "[WMI] \\$SiteServer\root\SMS\Site_$($global:SiteCode) : SMS_Package (all packages)" -Level Info
                $allPackages = Get-WmiObject -ComputerName $SiteServer -Namespace "root\SMS\Site_$($global:SiteCode)" -Class SMS_Package -ErrorAction Stop
                $packageCount = ($allPackages | Measure-Object).Count
                $txt_ServerPackageCount.Text = $packageCount.ToString('N0')

                # Count packages by naming convention
                Write-DATActivityLog "[WMI] SMS_Package query returned $packageCount package(s)" -Level Info
                $driverCount = ($allPackages | Where-Object { $_.Name -like 'Drivers -*' } | Measure-Object).Count
                $biosCount = ($allPackages | Where-Object { $_.Name -like 'Bios Update -*' } | Measure-Object).Count
                $otherCount = $packageCount - $driverCount - $biosCount
                Write-DATActivityLog "[WMI] Package breakdown: $driverCount driver, $biosCount BIOS, $otherCount other" -Level Info

                Update-DATPackageDonutChart -DriverCount $driverCount -BiosCount $biosCount -OtherCount $otherCount

                # Count packages by manufacturer
                $mfrCounts = @{
                    'Dell'      = ($allPackages | Where-Object { $_.Name -match '- Dell ' } | Measure-Object).Count
                    'HP'        = ($allPackages | Where-Object { $_.Name -match '- HP ' -or $_.Name -match '- Hewlett-Packard ' } | Measure-Object).Count
                    'Lenovo'    = ($allPackages | Where-Object { $_.Name -match '- Lenovo ' } | Measure-Object).Count
                    'Microsoft' = ($allPackages | Where-Object { $_.Name -match '- Microsoft ' } | Measure-Object).Count
                    'Acer'      = ($allPackages | Where-Object { $_.Name -match '- Acer ' } | Measure-Object).Count
                }
                $mfrCounts['Other'] = $packageCount - ($mfrCounts.Values | Measure-Object -Sum).Sum

                Update-DATManufacturerDonutChart -Counts $mfrCounts
                $panel_PackageChart.Visibility = 'Visible'
            } catch {
                $txt_ServerPackageCount.Text = 'Not available'
            }

            $panel_SiteServerInfo.Visibility = 'Visible'

            # Populate Distribution Points and DP Groups
            $savedDPs = @()
            $savedDPGroups = @()
            try {
                $dpConfig = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
                if (-not [string]::IsNullOrEmpty($dpConfig.SelectedDPs)) {
                    $savedDPs = @($dpConfig.SelectedDPs -split '\|')
                }
                if (-not [string]::IsNullOrEmpty($dpConfig.SelectedDPGroups)) {
                    $savedDPGroups = @($dpConfig.SelectedDPGroups -split '\|')
                }
            } catch { }

            try {
                Write-DATActivityLog "[WMI] \\$SiteServer\root\SMS\Site_$($global:SiteCode) : SMS_SystemResourceList (Distribution Points)" -Level Info
                $script:DPData.Clear()
                $dpList = Get-DATDistributionPoints -SiteCode $global:SiteCode -SiteServer $SiteServer
                Write-DATActivityLog "[WMI] Distribution Points found: $(@($dpList).Count)" -Level Info
                foreach ($dp in $dpList) {
                    $script:DPData.Add([PSCustomObject]@{ Selected = ($dp -in $savedDPs); Name = $dp })
                }
            } catch {
                Write-DATLogEntry -Value "[Warning] - Failed to query distribution points: $($_.Exception.Message)" -Severity 2
            }

            try {
                Write-DATActivityLog "[WMI] \\$SiteServer\root\SMS\Site_$($global:SiteCode) : SMS_DistributionPointGroup" -Level Info
                $script:DPGroupData.Clear()
                $dpGroups = Get-DATDistributionPointGroups -SiteCode $global:SiteCode -SiteServer $SiteServer
                Write-DATActivityLog "[WMI] DP Groups found: $(@($dpGroups).Count)" -Level Info
                foreach ($grp in $dpGroups) {
                    $script:DPGroupData.Add([PSCustomObject]@{ Selected = ($grp -in $savedDPGroups); Name = $grp })
                }
            } catch {
                Write-DATLogEntry -Value "[Warning] - Failed to query DP groups: $($_.Exception.Message)" -Severity 2
            }

            # Enable ConfigMgr known model lookup if toggle is on
            if ($chk_KnownModels.IsChecked) {
                $btn_ConfigMgrKnownModelLookup.IsEnabled = $true
                Invoke-DATConfigMgrKnownModelLookup
            }
        } else {
            $txt_SiteCode.Foreground = $Window.FindResource('StatusWarning')
            $txt_SiteCode.Text = "Connection failed - no site code returned."
        }
    } catch {
        $txt_SiteCode.Foreground = $Window.FindResource('StatusError')
        $txt_SiteCode.Text = "Error: $($_.Exception.Message)"
    }
}

$btn_ConnectConfigMgr.Add_Click({
    Invoke-DATConfigMgrConnect -SiteServer $txt_SiteServer.Text -UseSSL $chk_WinRMSSL.IsChecked
})

$chk_WinRMSSL.Add_Checked({
    Set-DATRegistryValue -Name 'WinRMSSL' -Value 1 -Type DWord
})
$chk_WinRMSSL.Add_Unchecked({
    Set-DATRegistryValue -Name 'WinRMSSL' -Value 0 -Type DWord
})

$txt_SiteServer.Add_TextChanged({
    $val = $txt_SiteServer.Text.Trim()
    $btn_ConnectConfigMgr.IsEnabled = ($val.Length -gt 0)
})

#endregion ConfigMgr Connection

#region Known Model Lookup

$chk_KnownModels = $Window.FindName('chk_KnownModels')
$txt_KnownModelsState = $Window.FindName('txt_KnownModelsState')
$btn_ConfigMgrKnownModelLookup = $Window.FindName('btn_ConfigMgrKnownModelLookup')
$btn_ConfigMgrViewModels = $Window.FindName('btn_ConfigMgrViewModels')
$txt_ConfigMgrKnownModelStatus = $Window.FindName('txt_ConfigMgrKnownModelStatus')

function Update-DATConfigMgrKnownModelSelection {
    <#
    .SYNOPSIS
        Checks models in grid_Models that match known ConfigMgr devices.
        Matches on Model name first, then falls back to Make+Model.
    #>
    if (-not $script:ConfigMgrKnownDevices -or $script:ModelData.Count -eq 0) { return }
    if (-not $chk_KnownModels.IsChecked) { return }

    # Build lookup sets for fast matching
    $knownModels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $knownMakeModel = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($device in $script:ConfigMgrKnownDevices) {
        [void]$knownModels.Add($device.Model)
        [void]$knownMakeModel.Add("$($device.Make)|$($device.Model)")
    }

    $matchCount = 0
    foreach ($item in $script:ModelData) {
        if ($knownModels.Contains($item.Model)) {
            $item.Selected = $true
            $matchCount++
        }
        elseif ($knownMakeModel.Contains("$($item.OEM)|$($item.Model)")) {
            $item.Selected = $true
            $matchCount++
        }
    }

    if ($matchCount -gt 0) {
        Write-DATActivityLog "Auto-selected $matchCount models matching known ConfigMgr devices" -Level Success
        Update-DATBuildButtonState

        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($script:ModelData)
        $view.SortDescriptions.Clear()
        $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('Selected', [System.ComponentModel.ListSortDirection]::Descending))
        $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('OEM', [System.ComponentModel.ListSortDirection]::Ascending))
        $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('Model', [System.ComponentModel.ListSortDirection]::Ascending))

        foreach ($col in $grid_Models.Columns) {
            if ($col.SortMemberPath -eq 'Selected') {
                $col.SortDirection = [System.ComponentModel.ListSortDirection]::Descending
            } else {
                $col.SortDirection = $null
            }
        }
    }
}

function Invoke-DATConfigMgrKnownModelLookup {
    if ([string]::IsNullOrEmpty($global:SiteCode) -or [string]::IsNullOrEmpty($global:SiteServer)) {
        $txt_ConfigMgrKnownModelStatus.Text = "Please connect to Configuration Manager first."
        $txt_ConfigMgrKnownModelStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
        return
    }

    $btn_ConfigMgrKnownModelLookup.IsEnabled = $false
    $btn_ConfigMgrViewModels.IsEnabled = $false
    $txt_ConfigMgrKnownModelStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusInfo']))
    $txt_ConfigMgrKnownModelStatus.Text = "Connecting to $($global:SiteServer)..."
    Write-DATActivityLog "Starting ConfigMgr known model lookup via CIM on $($global:SiteServer)" -Level Info

    $siteServer = $global:SiteServer
    $siteCode = $global:SiteCode

    $script:ConfigMgrModelLookupState = [hashtable]::Synchronized(@{
        Status   = 'Running'
        Progress = "Connecting to $siteServer..."
        Result   = $null
        Error    = $null
    })

    $script:ConfigMgrModelLookupPS = [powershell]::Create()
    $script:ConfigMgrModelLookupPS.AddScript({
        param ($CoreModulePath, $State, $Server, $Code)
        Import-Module $CoreModulePath -Force

        try {
            $result = Get-DATConfigMgrKnownModels -SiteServer $Server -SiteCode $Code -OnProgress {
                param ($msg)
                $State.Progress = $msg
            }
            $State.Result = $result
            $State.Status = 'Complete'
        }
        catch {
            $State.Error = $_.Exception.Message
            $State.Status = 'Failed'
        }
    })
    [void]$script:ConfigMgrModelLookupPS.AddArgument($CoreModulePath)
    [void]$script:ConfigMgrModelLookupPS.AddArgument($script:ConfigMgrModelLookupState)
    [void]$script:ConfigMgrModelLookupPS.AddArgument($siteServer)
    [void]$script:ConfigMgrModelLookupPS.AddArgument($siteCode)

    $script:ConfigMgrModelLookupAsync = $script:ConfigMgrModelLookupPS.BeginInvoke()

    $script:ConfigMgrModelLookupTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ConfigMgrModelLookupTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:ConfigMgrModelLookupTimer.Add_Tick({
        $state = $script:ConfigMgrModelLookupState

        $txt_ConfigMgrKnownModelStatus.Text = $state.Progress

        if ($state.Status -eq 'Complete') {
            $script:ConfigMgrModelLookupTimer.Stop()
            $result = $state.Result
            $makeCount = @($result.Makes).Count
            $modelCount = @($result.Models).Count
            $txt_ConfigMgrKnownModelStatus.Text = "Discovered $makeCount makes and $modelCount models"
            $txt_ConfigMgrKnownModelStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusSuccess']))
            $btn_ConfigMgrKnownModelLookup.IsEnabled = $true
            $btn_ConfigMgrViewModels.IsEnabled = $true

            $script:ConfigMgrKnownMakes = $result.Makes
            $script:ConfigMgrKnownModels = $result.Models
            $script:ConfigMgrKnownDevices = $result.Devices

            Write-DATActivityLog "ConfigMgr known model lookup complete: $makeCount makes, $modelCount models" -Level Success

            $devicesByMake = $result.Devices | Group-Object -Property Make | Sort-Object Name
            foreach ($makeGrp in $devicesByMake) {
                Write-DATActivityLog "  $($makeGrp.Name): $($makeGrp.Count) model(s)" -Level Info
                foreach ($dev in ($makeGrp.Group | Sort-Object Model)) {
                    Write-DATActivityLog "    - $($dev.Model)" -Level Info
                }
            }

            Update-DATConfigMgrKnownModelSelection

            $script:ConfigMgrModelLookupPS.Dispose()
            $script:ConfigMgrModelLookupPS = $null
        }
        elseif ($state.Status -eq 'Failed') {
            $script:ConfigMgrModelLookupTimer.Stop()
            $txt_ConfigMgrKnownModelStatus.Text = "Failed: $($state.Error)"
            $txt_ConfigMgrKnownModelStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
            $btn_ConfigMgrKnownModelLookup.IsEnabled = $true
            Write-DATActivityLog "ConfigMgr known model lookup failed: $($state.Error)" -Level Error

            $script:ConfigMgrModelLookupPS.Dispose()
            $script:ConfigMgrModelLookupPS = $null
        }
    })
    $script:ConfigMgrModelLookupTimer.Start()
}

function Show-DATConfigMgrKnownModelsDialog {
    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background = [System.Windows.Media.Brushes]::Transparent
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $Window
    $dlg.Width = 700
    $dlg.Height = 550
    $dlg.Topmost = $true
    $dlg.ResizeMode = 'NoResize'
    $dlg.ShowInTaskbar = $false

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(245, 30, 41, 59))
    $border.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $border.Padding = [System.Windows.Thickness]::new(24, 20, 24, 20)
    $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString('#334155'))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $border.Effect = $shadow

    $mainPanel = [System.Windows.Controls.Grid]::new()
    $row0 = [System.Windows.Controls.RowDefinition]::new(); $row0.Height = [System.Windows.GridLength]::new(0, [System.Windows.GridUnitType]::Auto)
    $row1 = [System.Windows.Controls.RowDefinition]::new(); $row1.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $row2 = [System.Windows.Controls.RowDefinition]::new(); $row2.Height = [System.Windows.GridLength]::new(0, [System.Windows.GridUnitType]::Auto)
    $mainPanel.RowDefinitions.Add($row0)
    $mainPanel.RowDefinitions.Add($row1)
    $mainPanel.RowDefinitions.Add($row2)

    $headerGrid = [System.Windows.Controls.Grid]::new()
    $hCol1 = [System.Windows.Controls.ColumnDefinition]::new(); $hCol1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $hCol2 = [System.Windows.Controls.ColumnDefinition]::new(); $hCol2.Width = [System.Windows.GridLength]::new(0, [System.Windows.GridUnitType]::Auto)
    $headerGrid.ColumnDefinitions.Add($hCol1)
    $headerGrid.ColumnDefinitions.Add($hCol2)

    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.FontSize = 16
    $titleText.FontWeight = [System.Windows.FontWeights]::Bold
    $titleText.Foreground = [System.Windows.Media.Brushes]::White
    $titleText.VerticalAlignment = 'Center'
    $r1 = [System.Windows.Documents.Run]::new([char]0xE8A7)
    $r1.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $r2 = [System.Windows.Documents.Run]::new("  ConfigMgr Known Makes & Models")
    $titleText.Inlines.Add($r1)
    $titleText.Inlines.Add($r2)
    [System.Windows.Controls.Grid]::SetColumn($titleText, 0)
    $headerGrid.Children.Add($titleText) | Out-Null

    $btnClose = [System.Windows.Controls.Button]::new()
    $btnClose.Content = [char]0xE711
    $btnClose.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $btnClose.FontSize = 14
    $btnClose.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString('#94A3B8'))
    $btnClose.Background = [System.Windows.Media.Brushes]::Transparent
    $btnClose.BorderThickness = [System.Windows.Thickness]::new(0)
    $btnClose.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnClose.Width = 30; $btnClose.Height = 30
    $btnClose.Add_Click({ $dlg.Close() })
    [System.Windows.Controls.Grid]::SetColumn($btnClose, 1)
    $headerGrid.Children.Add($btnClose) | Out-Null

    [System.Windows.Controls.Grid]::SetRow($headerGrid, 0)
    $headerGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $mainPanel.Children.Add($headerGrid) | Out-Null

    $deviceCount = @($script:ConfigMgrKnownDevices).Count
    $makeCount = @($script:ConfigMgrKnownMakes).Count

    $items = [System.Collections.ObjectModel.ObservableCollection[PSObject]]::new()
    foreach ($device in $script:ConfigMgrKnownDevices) {
        $items.Add([PSCustomObject]@{
            Make  = $device.Make
            Model = $device.Model
        })
    }

    $dgXaml = @"
<DataGrid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
          xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
          AutoGenerateColumns="False" IsReadOnly="True"
          CanUserAddRows="False" CanUserDeleteRows="False"
          HeadersVisibility="Column" GridLinesVisibility="Horizontal"
          BorderThickness="0"
          Background="#0F172A"
          RowBackground="#0F172A"
          AlternatingRowBackground="#1E293B"
          Foreground="#F8FAFC"
          FontSize="13"
          HorizontalGridLinesBrush="#1E293B"
          VerticalScrollBarVisibility="Auto"
          HorizontalScrollBarVisibility="Disabled">
    <DataGrid.ColumnHeaderStyle>
        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Setter Property="BorderBrush" Value="#334155"/>
        </Style>
    </DataGrid.ColumnHeaderStyle>
    <DataGrid.CellStyle>
        <Style TargetType="DataGridCell">
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="DataGridCell">
                        <Border Padding="{TemplateBinding Padding}" Background="{TemplateBinding Background}">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </DataGrid.CellStyle>
    <DataGrid.Columns>
        <DataGridTextColumn Header="Make" Width="*" Binding="{Binding Make}"/>
        <DataGridTextColumn Header="Model" Width="2*" Binding="{Binding Model}"/>
    </DataGrid.Columns>
</DataGrid>
"@
    $dg = [System.Windows.Markup.XamlReader]::Parse($dgXaml)
    $dg.ItemsSource = $items

    $dgBorder = [System.Windows.Controls.Border]::new()
    $dgBorder.CornerRadius = [System.Windows.CornerRadius]::new(10)
    $dgBorder.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString('#334155'))
    $dgBorder.BorderThickness = [System.Windows.Thickness]::new(1)
    $dgBorder.ClipToBounds = $true
    $dgBorder.Child = $dg
    [System.Windows.Controls.Grid]::SetRow($dgBorder, 1)
    $mainPanel.Children.Add($dgBorder) | Out-Null

    $footerGrid = [System.Windows.Controls.Grid]::new()
    $fCol1 = [System.Windows.Controls.ColumnDefinition]::new(); $fCol1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $fCol2 = [System.Windows.Controls.ColumnDefinition]::new(); $fCol2.Width = [System.Windows.GridLength]::new(0, [System.Windows.GridUnitType]::Auto)
    $footerGrid.ColumnDefinitions.Add($fCol1)
    $footerGrid.ColumnDefinitions.Add($fCol2)

    $summaryText = [System.Windows.Controls.TextBlock]::new()
    $summaryText.Text = "$makeCount makes, $deviceCount unique models from hardware inventory"
    $summaryText.FontSize = 12
    $summaryText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString('#94A3B8'))
    $summaryText.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($summaryText, 0)
    $footerGrid.Children.Add($summaryText) | Out-Null

    $btnDone = [System.Windows.Controls.Button]::new()
    $btnDone.Height = 34
    $btnDone.Cursor = [System.Windows.Input.Cursors]::Hand
    $doneTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="#334155" CornerRadius="8" Padding="20,8">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="#475569"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnDone.Template = $doneTemplate
    $btnDone.Foreground = [System.Windows.Media.Brushes]::White
    $btnDone.FontSize = 13
    $btnDone.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnDone.Content = "Close"
    $btnDone.Add_Click({ $dlg.Close() })
    [System.Windows.Controls.Grid]::SetColumn($btnDone, 1)
    $footerGrid.Children.Add($btnDone) | Out-Null

    [System.Windows.Controls.Grid]::SetRow($footerGrid, 2)
    $footerGrid.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
    $mainPanel.Children.Add($footerGrid) | Out-Null

    $border.Child = $mainPanel
    $dlg.Content = $border

    $dlg.ShowDialog() | Out-Null
}

$chk_KnownModels.Add_Checked({
    Set-DATRegistryValue -Name 'KnownModelsOnly' -Value 1 -Type DWord
    $txt_KnownModelsState.Text = 'On'
    $txt_KnownModelsState.Foreground = $Window.FindResource('AccentColor')
    if (-not [string]::IsNullOrEmpty($global:SiteCode)) {
        $btn_ConfigMgrKnownModelLookup.IsEnabled = $true
        Invoke-DATConfigMgrKnownModelLookup
    }
})
$chk_KnownModels.Add_Unchecked({
    Set-DATRegistryValue -Name 'KnownModelsOnly' -Value 0 -Type DWord
    $txt_KnownModelsState.Text = 'Off'
    $txt_KnownModelsState.Foreground = $Window.FindResource('InputPlaceholder')
    $btn_ConfigMgrKnownModelLookup.IsEnabled = $false
    $btn_ConfigMgrViewModels.IsEnabled = $false
})

$btn_ConfigMgrKnownModelLookup.Add_Click({
    Invoke-DATConfigMgrKnownModelLookup
})

$btn_ConfigMgrViewModels.Add_Click({
    if (-not $script:ConfigMgrKnownDevices) {
        return
    }
    Show-DATConfigMgrKnownModelsDialog
})

#endregion Known Model Lookup

#region Intune Known Model Lookup

$chk_IntuneKnownModels = $Window.FindName('chk_IntuneKnownModels')
$txt_IntuneKnownModelsState = $Window.FindName('txt_IntuneKnownModelsState')
$btn_IntuneKnownModelLookup = $Window.FindName('btn_IntuneKnownModelLookup')
$btn_IntuneViewModels = $Window.FindName('btn_IntuneViewModels')
$txt_IntuneKnownModelStatus = $Window.FindName('txt_IntuneKnownModelStatus')

function Update-DATKnownModelSelection {
    <#
    .SYNOPSIS
        Checks models in grid_Models that match known Intune devices.
        Matches on Model name first, then falls back to Make+Model.
    #>
    if (-not $script:IntuneKnownDevices -or $script:ModelData.Count -eq 0) { return }
    if (-not $chk_IntuneKnownModels.IsChecked) { return }

    # Build lookup sets for fast matching
    $knownModels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $knownMakeModel = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($device in $script:IntuneKnownDevices) {
        [void]$knownModels.Add($device.Model)
        [void]$knownMakeModel.Add("$($device.Make)|$($device.Model)")
    }

    $matchCount = 0
    foreach ($item in $script:ModelData) {
        # Try model name match first
        if ($knownModels.Contains($item.Model)) {
            $item.Selected = $true
            $matchCount++
        }
        # Fall back to make+model match
        elseif ($knownMakeModel.Contains("$($item.OEM)|$($item.Model)")) {
            $item.Selected = $true
            $matchCount++
        }
    }

    if ($matchCount -gt 0) {
        Write-DATActivityLog "Auto-selected $matchCount models matching known Intune devices" -Level Success
        Update-DATBuildButtonState

        # Sort grid so checked (known) models appear at the top
        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($script:ModelData)
        $view.SortDescriptions.Clear()
        $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('Selected', [System.ComponentModel.ListSortDirection]::Descending))
        $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('OEM', [System.ComponentModel.ListSortDirection]::Ascending))
        $view.SortDescriptions.Add([System.ComponentModel.SortDescription]::new('Model', [System.ComponentModel.ListSortDirection]::Ascending))

        # Update column header sort indicator
        foreach ($col in $grid_Models.Columns) {
            if ($col.SortMemberPath -eq 'Selected') {
                $col.SortDirection = [System.ComponentModel.ListSortDirection]::Descending
            } else {
                $col.SortDirection = $null
            }
        }
    }
}

function Invoke-DATIntuneKnownModelLookup {
    if (-not (Test-DATIntuneAuth)) {
        $txt_IntuneKnownModelStatus.Text = "Please authenticate to Intune first."
        $txt_IntuneKnownModelStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
        return
    }

    $btn_IntuneKnownModelLookup.IsEnabled = $false
    $btn_IntuneViewModels.IsEnabled = $false
    $txt_IntuneKnownModelStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusInfo']))
    $txt_IntuneKnownModelStatus.Text = "Querying Graph..."
    Write-DATActivityLog "Starting Intune known model lookup via Graph API" -Level Info

    # Capture auth state before launching background runspace
    $intuneAuthToken = (Get-DATIntuneAuthStatus).Token
    $graphBaseUrl = "https://graph.microsoft.com/beta"

    # Shared state for background progress reporting
    $script:IntuneModelLookupState = [hashtable]::Synchronized(@{
        Status   = 'Running'
        Progress = 'Querying Graph...'
        Result   = $null
        Error    = $null
    })

    $script:IntuneModelLookupPS = [powershell]::Create()
    $script:IntuneModelLookupPS.AddScript({
        param ($CoreModulePath, $State, $Token, $BaseUrl)
        Import-Module $CoreModulePath -Force

        try {
            $result = Get-DATIntuneKnownModels -AuthToken $Token -GraphBaseUrl $BaseUrl -OnProgress {
                param ($msg)
                $State.Progress = $msg
            }
            $State.Result = $result
            $State.Status = 'Complete'
        }
        catch {
            $State.Error = $_.Exception.Message
            $State.Status = 'Failed'
        }
    })
    [void]$script:IntuneModelLookupPS.AddArgument($CoreModulePath)
    [void]$script:IntuneModelLookupPS.AddArgument($script:IntuneModelLookupState)
    [void]$script:IntuneModelLookupPS.AddArgument($intuneAuthToken)
    [void]$script:IntuneModelLookupPS.AddArgument($graphBaseUrl)

    $script:IntuneModelLookupAsync = $script:IntuneModelLookupPS.BeginInvoke()

    # Poll for progress updates
    $script:IntuneModelLookupTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:IntuneModelLookupTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:IntuneModelLookupTimer.Add_Tick({
        $state = $script:IntuneModelLookupState

        $txt_IntuneKnownModelStatus.Text = $state.Progress

        if ($state.Status -eq 'Complete') {
            $script:IntuneModelLookupTimer.Stop()
            $result = $state.Result
            $makeCount = @($result.Makes).Count
            $modelCount = @($result.Models).Count
            $txt_IntuneKnownModelStatus.Text = "Discovered $makeCount makes and $modelCount models"
            $txt_IntuneKnownModelStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusSuccess']))
            $btn_IntuneKnownModelLookup.IsEnabled = $true
            $btn_IntuneViewModels.IsEnabled = $true

            # Store results for model filtering
            $script:IntuneKnownMakes = $result.Makes
            $script:IntuneKnownModels = $result.Models
            $script:IntuneKnownDevices = $result.Devices

            Write-DATActivityLog "Intune known model lookup complete: $makeCount makes, $modelCount models" -Level Success

            # Log the full discovered model list grouped by make
            $devicesByMake = $result.Devices | Group-Object -Property Make | Sort-Object Name
            foreach ($makeGrp in $devicesByMake) {
                Write-DATActivityLog "  $($makeGrp.Name): $($makeGrp.Count) model(s)" -Level Info
                foreach ($dev in ($makeGrp.Group | Sort-Object Model)) {
                    Write-DATActivityLog "    - $($dev.Model)" -Level Info
                }
            }

            # Auto-select matching models in the grid if populated
            Update-DATKnownModelSelection

            $script:IntuneModelLookupPS.Dispose()
            $script:IntuneModelLookupPS = $null
        }
        elseif ($state.Status -eq 'Failed') {
            $script:IntuneModelLookupTimer.Stop()
            $txt_IntuneKnownModelStatus.Text = "Failed: $($state.Error)"
            $txt_IntuneKnownModelStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
            $btn_IntuneKnownModelLookup.IsEnabled = $true
            Write-DATActivityLog "Intune known model lookup failed: $($state.Error)" -Level Error

            $script:IntuneModelLookupPS.Dispose()
            $script:IntuneModelLookupPS = $null
        }
    })
    $script:IntuneModelLookupTimer.Start()
}

$chk_IntuneKnownModels.Add_Checked({
    Set-DATRegistryValue -Name 'IntuneKnownModelsOnly' -Value 1 -Type DWord
    $txt_IntuneKnownModelsState.Text = 'On'
    $txt_IntuneKnownModelsState.Foreground = $Window.FindResource('AccentColor')
    if (Test-DATIntuneAuth) {
        $btn_IntuneKnownModelLookup.IsEnabled = $true
        Invoke-DATIntuneKnownModelLookup
    }
})
$chk_IntuneKnownModels.Add_Unchecked({
    Set-DATRegistryValue -Name 'IntuneKnownModelsOnly' -Value 0 -Type DWord
    $txt_IntuneKnownModelsState.Text = 'Off'
    $txt_IntuneKnownModelsState.Foreground = $Window.FindResource('InputPlaceholder')
    $btn_IntuneKnownModelLookup.IsEnabled = $false
    $btn_IntuneViewModels.IsEnabled = $false
})

$btn_IntuneKnownModelLookup.Add_Click({
    Invoke-DATIntuneKnownModelLookup
})

$btn_IntuneViewModels.Add_Click({
    if (-not $script:IntuneKnownDevices) {
        return
    }
    Show-DATIntuneKnownModelsDialog
})

function Show-DATIntuneKnownModelsDialog {
    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background = [System.Windows.Media.Brushes]::Transparent
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $Window
    $dlg.Width = 700
    $dlg.Height = 550
    $dlg.Topmost = $true
    $dlg.ResizeMode = 'NoResize'
    $dlg.ShowInTaskbar = $false

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(245, 30, 41, 59))
    $border.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $border.Padding = [System.Windows.Thickness]::new(24, 20, 24, 20)
    $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString('#334155'))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $border.Effect = $shadow

    $mainPanel = [System.Windows.Controls.Grid]::new()
    $row0 = [System.Windows.Controls.RowDefinition]::new(); $row0.Height = [System.Windows.GridLength]::new(0, [System.Windows.GridUnitType]::Auto)
    $row1 = [System.Windows.Controls.RowDefinition]::new(); $row1.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $row2 = [System.Windows.Controls.RowDefinition]::new(); $row2.Height = [System.Windows.GridLength]::new(0, [System.Windows.GridUnitType]::Auto)
    $mainPanel.RowDefinitions.Add($row0)
    $mainPanel.RowDefinitions.Add($row1)
    $mainPanel.RowDefinitions.Add($row2)

    # Header row with title and close button
    $headerGrid = [System.Windows.Controls.Grid]::new()
    $hCol1 = [System.Windows.Controls.ColumnDefinition]::new(); $hCol1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $hCol2 = [System.Windows.Controls.ColumnDefinition]::new(); $hCol2.Width = [System.Windows.GridLength]::new(0, [System.Windows.GridUnitType]::Auto)
    $headerGrid.ColumnDefinitions.Add($hCol1)
    $headerGrid.ColumnDefinitions.Add($hCol2)

    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.FontSize = 16
    $titleText.FontWeight = [System.Windows.FontWeights]::Bold
    $titleText.Foreground = [System.Windows.Media.Brushes]::White
    $titleText.VerticalAlignment = 'Center'
    $r1 = [System.Windows.Documents.Run]::new([char]0xE8A7)
    $r1.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $r2 = [System.Windows.Documents.Run]::new("  Known Makes & Models")
    $titleText.Inlines.Add($r1)
    $titleText.Inlines.Add($r2)
    [System.Windows.Controls.Grid]::SetColumn($titleText, 0)
    $headerGrid.Children.Add($titleText) | Out-Null

    $btnClose = [System.Windows.Controls.Button]::new()
    $btnClose.Content = [char]0xE711
    $btnClose.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $btnClose.FontSize = 14
    $btnClose.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString('#94A3B8'))
    $btnClose.Background = [System.Windows.Media.Brushes]::Transparent
    $btnClose.BorderThickness = [System.Windows.Thickness]::new(0)
    $btnClose.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnClose.Width = 30; $btnClose.Height = 30
    $btnClose.Add_Click({ $dlg.Close() })
    [System.Windows.Controls.Grid]::SetColumn($btnClose, 1)
    $headerGrid.Children.Add($btnClose) | Out-Null

    [System.Windows.Controls.Grid]::SetRow($headerGrid, 0)
    $headerGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $mainPanel.Children.Add($headerGrid) | Out-Null

    # Summary text
    $deviceCount = @($script:IntuneKnownDevices).Count
    $makeCount = @($script:IntuneKnownMakes).Count

    # Build data items from paired make/model data
    $items = [System.Collections.ObjectModel.ObservableCollection[PSObject]]::new()
    foreach ($device in $script:IntuneKnownDevices) {
        $items.Add([PSCustomObject]@{
            Make  = $device.Make
            Model = $device.Model
        })
    }

    # DataGrid
    $dgXaml = @"
<DataGrid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
          xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
          AutoGenerateColumns="False" IsReadOnly="True"
          CanUserAddRows="False" CanUserDeleteRows="False"
          HeadersVisibility="Column" GridLinesVisibility="Horizontal"
          BorderThickness="0"
          Background="#0F172A"
          RowBackground="#0F172A"
          AlternatingRowBackground="#1E293B"
          Foreground="#F8FAFC"
          FontSize="13"
          HorizontalGridLinesBrush="#1E293B"
          VerticalScrollBarVisibility="Auto"
          HorizontalScrollBarVisibility="Disabled">
    <DataGrid.ColumnHeaderStyle>
        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Setter Property="BorderBrush" Value="#334155"/>
        </Style>
    </DataGrid.ColumnHeaderStyle>
    <DataGrid.CellStyle>
        <Style TargetType="DataGridCell">
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="DataGridCell">
                        <Border Padding="{TemplateBinding Padding}" Background="{TemplateBinding Background}">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </DataGrid.CellStyle>
    <DataGrid.Columns>
        <DataGridTextColumn Header="Make" Width="*" Binding="{Binding Make}"/>
        <DataGridTextColumn Header="Model" Width="2*" Binding="{Binding Model}"/>
    </DataGrid.Columns>
</DataGrid>
"@
    $dg = [System.Windows.Markup.XamlReader]::Parse($dgXaml)
    $dg.ItemsSource = $items

    $dgBorder = [System.Windows.Controls.Border]::new()
    $dgBorder.CornerRadius = [System.Windows.CornerRadius]::new(10)
    $dgBorder.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString('#334155'))
    $dgBorder.BorderThickness = [System.Windows.Thickness]::new(1)
    $dgBorder.ClipToBounds = $true
    $dgBorder.Child = $dg
    [System.Windows.Controls.Grid]::SetRow($dgBorder, 1)
    $mainPanel.Children.Add($dgBorder) | Out-Null

    # Footer with summary and close button
    $footerGrid = [System.Windows.Controls.Grid]::new()
    $fCol1 = [System.Windows.Controls.ColumnDefinition]::new(); $fCol1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $fCol2 = [System.Windows.Controls.ColumnDefinition]::new(); $fCol2.Width = [System.Windows.GridLength]::new(0, [System.Windows.GridUnitType]::Auto)
    $footerGrid.ColumnDefinitions.Add($fCol1)
    $footerGrid.ColumnDefinitions.Add($fCol2)

    $summaryText = [System.Windows.Controls.TextBlock]::new()
    $summaryText.Text = "$makeCount makes, $deviceCount unique models discovered (Windows only)"
    $summaryText.FontSize = 12
    $summaryText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString('#94A3B8'))
    $summaryText.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($summaryText, 0)
    $footerGrid.Children.Add($summaryText) | Out-Null

    $btnDone = [System.Windows.Controls.Button]::new()
    $btnDone.Height = 34
    $btnDone.Cursor = [System.Windows.Input.Cursors]::Hand
    $doneTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="#334155" CornerRadius="8" Padding="20,8">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="#475569"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnDone.Template = $doneTemplate
    $btnDone.Foreground = [System.Windows.Media.Brushes]::White
    $btnDone.FontSize = 13
    $btnDone.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnDone.Content = "Close"
    $btnDone.Add_Click({ $dlg.Close() })
    [System.Windows.Controls.Grid]::SetColumn($btnDone, 1)
    $footerGrid.Children.Add($btnDone) | Out-Null

    [System.Windows.Controls.Grid]::SetRow($footerGrid, 2)
    $footerGrid.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
    $mainPanel.Children.Add($footerGrid) | Out-Null

    $border.Child = $mainPanel
    $dlg.Content = $border

    $dlg.ShowDialog() | Out-Null
}

#endregion Intune Known Model Lookup

#region Distribution Points

$grid_DPs = $Window.FindName('grid_DPs')
$grid_DPGroups = $Window.FindName('grid_DPGroups')

$script:DPData = [System.Collections.ObjectModel.ObservableCollection[PSObject]]::new()
$script:DPGroupData = [System.Collections.ObjectModel.ObservableCollection[PSObject]]::new()
$grid_DPs.ItemsSource = $script:DPData
$grid_DPGroups.ItemsSource = $script:DPGroupData

# Row-click checkbox toggle for DPs grid
$grid_DPs.Add_PreviewMouseLeftButtonDown({
    param($s, $e)
    $dep = $e.OriginalSource
    while ($null -ne $dep -and $dep -isnot [System.Windows.Controls.DataGridRow]) {
        if ($dep -is [System.Windows.Controls.Primitives.DataGridColumnHeader]) { return }
        $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
    }
    if ($null -ne $dep) {
        $item = $dep.DataContext
        if ($null -ne $item -and $item.PSObject.Properties['Selected']) {
            $item.Selected = -not $item.Selected
            Save-DATDPSelections
        }
    }
})

# Row-click checkbox toggle for DPGroups grid
$grid_DPGroups.Add_PreviewMouseLeftButtonDown({
    param($s, $e)
    $dep = $e.OriginalSource
    while ($null -ne $dep -and $dep -isnot [System.Windows.Controls.DataGridRow]) {
        if ($dep -is [System.Windows.Controls.Primitives.DataGridColumnHeader]) { return }
        $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
    }
    if ($null -ne $dep) {
        $item = $dep.DataContext
        if ($null -ne $item -and $item.PSObject.Properties['Selected']) {
            $item.Selected = -not $item.Selected
            Save-DATDPGroupSelections
        }
    }
})

function Save-DATDPSelections {
    $selectedDPs = @($script:DPData | Where-Object { $_.Selected } | ForEach-Object { $_.Name })
    Set-DATRegistryValue -Name 'SelectedDPs' -Value ($selectedDPs -join '|') -Type String
}

function Save-DATDPGroupSelections {
    $selectedGroups = @($script:DPGroupData | Where-Object { $_.Selected } | ForEach-Object { $_.Name })
    Set-DATRegistryValue -Name 'SelectedDPGroups' -Value ($selectedGroups -join '|') -Type String
}

$grid_DPs.Add_CurrentCellChanged({
    $Window.Dispatcher.InvokeAsync([action]{ Save-DATDPSelections }, [System.Windows.Threading.DispatcherPriority]::Background)
})

$grid_DPGroups.Add_CurrentCellChanged({
    $Window.Dispatcher.InvokeAsync([action]{ Save-DATDPGroupSelections }, [System.Windows.Threading.DispatcherPriority]::Background)
})

# Binary Differential Replication and Distribution Priority persistence
$chk_BinaryDiffReplication = $Window.FindName('chk_BinaryDiffReplication')
$cmb_DistPriority = $Window.FindName('cmb_DistPriority')
$txt_BdrState = $Window.FindName('txt_BdrState')
$link_DPScheduling = $Window.FindName('link_DPScheduling')
$link_ContentManagement = $Window.FindName('link_ContentManagement')

$link_DPScheduling.Add_RequestNavigate({
    param($s, $e)
    Start-Process $e.Uri.AbsoluteUri
    $e.Handled = $true
})
$link_ContentManagement.Add_RequestNavigate({
    param($s, $e)
    Start-Process $e.Uri.AbsoluteUri
    $e.Handled = $true
})

$chk_BinaryDiffReplication.Add_Checked({
    Set-DATRegistryValue -Name 'BinaryDiffReplication' -Value 1 -Type DWord
    $txt_BdrState.Text = 'On'
    $txt_BdrState.Foreground = $Window.FindResource('AccentColor')
})
$chk_BinaryDiffReplication.Add_Unchecked({
    Set-DATRegistryValue -Name 'BinaryDiffReplication' -Value 0 -Type DWord
    $txt_BdrState.Text = 'Off'
    $txt_BdrState.Foreground = $Window.FindResource('InputPlaceholder')
})
$cmb_DistPriority.Add_SelectionChanged({
    if ($null -ne $cmb_DistPriority.SelectedItem) {
        Set-DATRegistryValue -Name 'DistributionPriority' -Value $cmb_DistPriority.SelectedItem.Content -Type String
    }
})

#endregion Distribution Points

#region Issue Reporting

$script:IssueReportPath = Join-Path -Path $global:ScriptDirectory -ChildPath "Settings\ReportedIssues.json"

function Get-DATReportedIssues {
    if (Test-Path -Path $script:IssueReportPath) {
        try {
            $json = Get-Content -Path $script:IssueReportPath -Raw -ErrorAction Stop
            return ($json | ConvertFrom-Json)
        } catch {
            return @()
        }
    }
    return @()
}

function Save-DATReportedIssues {
    param([array]$Issues)
    $dir = Split-Path -Path $script:IssueReportPath -Parent
    if (-not (Test-Path -Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    $Issues | ConvertTo-Json -Depth 5 | Set-Content -Path $script:IssueReportPath -Force
}

function Test-DATPackageReported {
    param([string]$Make, [string]$Model, [string]$Version)
    $issues = Get-DATReportedIssues
    return ($issues | Where-Object { $_.Make -eq $Make -and $_.Model -eq $Model -and $_.Version -eq $Version }).Count -gt 0
}

function Add-DATReportedIssue {
    param([string]$Make, [string]$Model, [string]$Version)
    $issues = @(Get-DATReportedIssues)
    $existing = $issues | Where-Object { $_.Make -eq $Make -and $_.Model -eq $Model -and $_.Version -eq $Version }
    if ($existing.Count -eq 0) {
        $issues += [PSCustomObject]@{ Make = $Make; Model = $Model; Version = $Version }
        Save-DATReportedIssues -Issues $issues
    }
}

function Remove-DATReportedIssue {
    param([string]$Make, [string]$Model, [string]$Version)
    $issues = @(Get-DATReportedIssues)
    $issues = @($issues | Where-Object { -not ($_.Make -eq $Make -and $_.Model -eq $Model -and $_.Version -eq $Version) })
    Save-DATReportedIssues -Issues $issues
}

$script:WarningBrush = [System.Windows.Media.SolidColorBrush]::new(
    [System.Windows.Media.ColorConverter]::ConvertFromString('#55FFAA44'))

function Update-DATPackageRowHighlighting {
    param($DataGrid, $ItemsSource, [string]$MakeProperty, [string]$ModelProperty, [string]$VersionProperty)
    $issues = Get-DATReportedIssues
    $DataGrid.UpdateLayout()
    for ($i = 0; $i -lt $ItemsSource.Count; $i++) {
        $item = $ItemsSource[$i]
        $make = $item.$MakeProperty
        $model = $item.$ModelProperty
        $version = $item.$VersionProperty
        $DataGrid.ScrollIntoView($item)
        $DataGrid.UpdateLayout()
        $row = $DataGrid.ItemContainerGenerator.ContainerFromIndex($i)
        if ($null -ne $row) {
            $isReported = ($issues | Where-Object { $_.Make -eq $make -and $_.Model -eq $model -and $_.Version -eq $version }).Count -gt 0
            if ($isReported) {
                $row.Background = $script:WarningBrush
            } else {
                $row.Background = [System.Windows.Media.Brushes]::Transparent
            }
        }
    }
    # Scroll back to top
    if ($ItemsSource.Count -gt 0) {
        $DataGrid.ScrollIntoView($ItemsSource[0])
    }
}

#endregion Issue Reporting

#region Package Management

$btn_RefreshPkgs = $Window.FindName('btn_RefreshPkgs')
$grid_Packages = $Window.FindName('grid_Packages')
$cmb_PkgPackageType = $Window.FindName('cmb_PkgPackageType')
$cmb_DeploymentState = $Window.FindName('cmb_DeploymentState')
$txt_PkgStatus = $Window.FindName('txt_PkgStatus')
$btn_CmReportIssue = $Window.FindName('btn_CmReportIssue')

$script:PackageData = [System.Collections.ObjectModel.ObservableCollection[PSObject]]::new()
$grid_Packages.ItemsSource = $script:PackageData

# Row-click checkbox toggle for Packages grid
$grid_Packages.Add_PreviewMouseLeftButtonDown({
    param($s, $e)
    $dep = $e.OriginalSource
    $inCheckboxCol = $false
    while ($null -ne $dep -and $dep -isnot [System.Windows.Controls.DataGridRow]) {
        if ($dep -is [System.Windows.Controls.Primitives.DataGridColumnHeader]) { return }
        if ($dep -is [System.Windows.Controls.DataGridCell] -and
            $dep.Column -is [System.Windows.Controls.DataGridCheckBoxColumn]) {
            $inCheckboxCol = $true
        }
        $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
    }
    if ($null -ne $dep -and -not $inCheckboxCol) {
        $item = $dep.DataContext
        if ($null -ne $item -and $item.PSObject.Properties['Selected']) {
            $item.Selected = -not $item.Selected
            $Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{
                Update-DATCmDeleteSelectedState
            })
        }
    }
})

# Space bar: toggle the currently selected row.
$grid_Packages.Add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -ne [System.Windows.Input.Key]::Space) { return }
    $row = $grid_Packages.ItemContainerGenerator.ContainerFromItem($grid_Packages.SelectedItem)
    if ($null -ne $row) {
        $checkbox = Find-DATVisualChild -Parent $row -TypeName 'CheckBox'
        if ($null -ne $checkbox) {
            $checkbox.IsChecked = -not $checkbox.IsChecked
            $Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{
                Update-DATCmDeleteSelectedState
            })
        }
    }
    $e.Handled = $true
})

function Invoke-DATPackageRefresh {
    if ([string]::IsNullOrEmpty($global:SiteCode) -or [string]::IsNullOrEmpty($global:SiteServer)) {
        $txt_PkgStatus.Foreground = $Window.FindResource('StatusWarning')
        $txt_PkgStatus.Text = "Not connected to ConfigMgr. Please connect first."
        $txt_PkgStatus.Visibility = 'Visible'
        Write-DATLogEntry -Value "[Warning] - Not connected to ConfigMgr. Cannot refresh packages." -Severity 2
        return
    }

    # Prevent overlapping refreshes
    if ($null -ne $script:PkgRefreshTimer -and $script:PkgRefreshTimer.IsEnabled) { return }

    $script:PackageData.Clear()

    $pkgType = if ($null -ne $cmb_PkgPackageType.SelectedItem) { $cmb_PkgPackageType.SelectedItem.Content } else { 'Drivers' }
    $deployState = if ($null -ne $cmb_DeploymentState.SelectedItem) { $cmb_DeploymentState.SelectedItem.Content } else { 'Production' }

    # Build the name prefix: "Drivers -", "Drivers Pilot -", "BIOS Update Retired -", etc.
    $typePrefix = switch ($pkgType) {
        'BIOS Update' { 'BIOS Update' }
        default       { 'Drivers' }
    }
    $stateInfix = switch ($deployState) {
        'Pilot'   { ' Pilot' }
        'Retired' { ' Retired' }
        default   { '' }
    }
    $namePrefix = "$typePrefix$stateInfix -*"
    $displayLabel = if ($stateInfix) { "$pkgType ($deployState)" } else { $pkgType }

    $txt_PkgStatus.Foreground = $Window.FindResource('StatusInfo')
    $txt_PkgStatus.Text = "Querying $displayLabel packages..."
    $txt_PkgStatus.Visibility = 'Visible'
    $btn_RefreshPkgs.IsEnabled = $false

    # Run WMI query in a background runspace to keep the UI responsive
    $script:PkgRefreshRunspace = [runspacefactory]::CreateRunspace()
    $script:PkgRefreshRunspace.ApartmentState = 'STA'
    $script:PkgRefreshRunspace.Open()

    $script:PkgRefreshPS = [powershell]::Create()
    $script:PkgRefreshPS.Runspace = $script:PkgRefreshRunspace
    [void]$script:PkgRefreshPS.AddScript({
        param($SiteServer, $SiteCode, $NamePrefix)
        try {
            $wmiFilter = "Name LIKE '$($NamePrefix.Replace('*','%'))'"
            $packages = Get-WmiObject -ComputerName $SiteServer -Namespace "root\SMS\Site_$SiteCode" -Class SMS_Package -Filter $wmiFilter -ErrorAction Stop
            $results = @()
            foreach ($pkg in $packages) {
                $pkgModel = ''
                if ($pkg.Name -match '^(?:Drivers|BIOS Update)(?:\s+(?:Pilot|Retired))?\s*-\s*(.+)$') {
                    $pkgModel = $Matches[1].Trim()
                }
                $results += [PSCustomObject]@{
                    Selected     = $false
                    Name         = $pkg.Name
                    Version      = $pkg.Version
                    PackageID    = $pkg.PackageID
                    SourceDate   = if ($pkg.SourceDate) { [Management.ManagementDateTimeConverter]::ToDateTime($pkg.SourceDate).ToString('yyyy-MM-dd HH:mm') } else { '' }
                    Manufacturer = if ($pkg.Manufacturer) { $pkg.Manufacturer } else { '' }
                    Model        = $pkgModel
                }
            }
            return $results
        } catch {
            return [PSCustomObject]@{ _Error = $_.Exception.Message }
        }
    })
    [void]$script:PkgRefreshPS.AddArgument($global:SiteServer)
    [void]$script:PkgRefreshPS.AddArgument($global:SiteCode)
    [void]$script:PkgRefreshPS.AddArgument($namePrefix)

    $script:PkgRefreshAsyncResult = $script:PkgRefreshPS.BeginInvoke()

    # Poll for completion via DispatcherTimer (keeps UI responsive)
    $script:PkgRefreshDisplayLabel = $displayLabel
    $script:PkgRefreshTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:PkgRefreshTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:PkgRefreshTimer.Add_Tick({
        if ($script:PkgRefreshAsyncResult.IsCompleted) {
            $script:PkgRefreshTimer.Stop()

            try {
                $results = $script:PkgRefreshPS.EndInvoke($script:PkgRefreshAsyncResult)

                # Check for error object
                $errorResult = $results | Where-Object { $_ -is [PSCustomObject] -and $_._Error }
                if ($errorResult) {
                    $txt_PkgStatus.Foreground = $Window.FindResource('StatusError')
                    $txt_PkgStatus.Text = "Error: $($errorResult._Error)"
                    Write-DATLogEntry -Value "[Error] - Failed to query packages: $($errorResult._Error)" -Severity 3
                } else {
                    foreach ($item in $results) {
                        if ($null -ne $item -and $null -eq $item._Error) {
                            $script:PackageData.Add($item)
                        }
                    }

                    $label = $script:PkgRefreshDisplayLabel
                    $txt_PkgStatus.Foreground = $Window.FindResource('StatusSuccess')
                    $txt_PkgStatus.Text = "Loaded $($script:PackageData.Count) $label package$(if ($script:PackageData.Count -ne 1) { 's' })"
                    Write-DATLogEntry -Value "- Loaded $($script:PackageData.Count) packages matching '$label'" -Severity 1

                    # Apply warning highlighting to reported packages
                    Update-DATPackageRowHighlighting -DataGrid $grid_Packages -ItemsSource $script:PackageData -MakeProperty 'Manufacturer' -ModelProperty 'Model' -VersionProperty 'Version'
                }
            } catch {
                $txt_PkgStatus.Foreground = $Window.FindResource('StatusError')
                $txt_PkgStatus.Text = "Error: $($_.Exception.Message)"
                Write-DATLogEntry -Value "[Error] - Failed to query packages: $($_.Exception.Message)" -Severity 3
            } finally {
                $script:PkgRefreshPS.Dispose()
                $script:PkgRefreshRunspace.Dispose()
                $btn_RefreshPkgs.IsEnabled = $true
            }
        }
    })
    $script:PkgRefreshTimer.Start()
}

$btn_RefreshPkgs.Add_Click({ Invoke-DATPackageRefresh })

$cmb_PkgPackageType.Add_SelectionChanged({ Invoke-DATPackageRefresh })
$cmb_DeploymentState.Add_SelectionChanged({ Invoke-DATPackageRefresh })

# ConfigMgr package search filter
$txt_CmPkgSearch = $Window.FindName('txt_CmPkgSearch')
$txt_CmPkgSearch.Add_TextChanged({
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($grid_Packages.ItemsSource)
    if ($null -eq $view) { return }
    $searchText = $txt_CmPkgSearch.Text
    if ([string]::IsNullOrEmpty($searchText)) {
        $view.Filter = $null
    } else {
        $view.Filter = [System.Predicate[object]]{
            param($item)
            $item.Name -like "*$searchText*" -or
            $item.PackageID -like "*$searchText*" -or
            $item.Version -like "*$searchText*"
        }
    }
})

# ConfigMgr Select All / Select None
$btn_CmPkgSelectAll = $Window.FindName('btn_CmPkgSelectAll')
$btn_CmPkgSelectNone = $Window.FindName('btn_CmPkgSelectNone')
$btn_CmPkgSelectAll.Add_Click({
    foreach ($item in $script:PackageData) { $item.Selected = $true }
    $grid_Packages.Items.Refresh()
    Update-DATCmDeleteSelectedState
})
$btn_CmPkgSelectNone.Add_Click({
    foreach ($item in $script:PackageData) { $item.Selected = $false }
    $grid_Packages.Items.Refresh()
    Update-DATCmDeleteSelectedState
})

# ConfigMgr Delete Selected button
$btn_CmDeleteSelected = $Window.FindName('btn_CmDeleteSelected')

function Update-DATCmDeleteSelectedState {
    $selectedCount = @($script:PackageData | Where-Object { $_.Selected -eq $true }).Count
    $btn_CmDeleteSelected.IsEnabled = ($selectedCount -gt 0)
}

$grid_Packages.Add_CellEditEnding({
    $Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{
        Update-DATCmDeleteSelectedState
    })
})
$grid_Packages.Add_CurrentCellChanged({
    $Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{
        Update-DATCmDeleteSelectedState
    })
})

$btn_CmDeleteSelected.Add_Click({
    $selectedPkgs = @($script:PackageData | Where-Object { $_.Selected -eq $true })
    if ($selectedPkgs.Count -eq 0) {
        $txt_PkgStatus.Foreground = $Window.FindResource('StatusWarning')
        $txt_PkgStatus.Text = "No packages selected."
        $txt_PkgStatus.Visibility = 'Visible'
        return
    }

    $confirm = Show-DATConfirmDialog -Title "Delete Packages" -Message "Delete $($selectedPkgs.Count) selected package(s) from ConfigMgr?`n`nThis action cannot be undone."
    if (-not $confirm) { return }

    $btn_CmDeleteSelected.IsEnabled = $false
    $totalCount = $selectedPkgs.Count
    $pkgIds = @($selectedPkgs | ForEach-Object { $_.PackageID })
    $pkgNames = @($selectedPkgs | ForEach-Object { $_.Name })

    # Build progress modal
    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])

    $script:cmDeleteModal = [System.Windows.Window]::new()
    $script:cmDeleteModal.WindowStyle = 'None'
    $script:cmDeleteModal.AllowsTransparency = $true
    $script:cmDeleteModal.Background = [System.Windows.Media.Brushes]::Transparent
    $script:cmDeleteModal.WindowStartupLocation = 'CenterOwner'
    $script:cmDeleteModal.Owner = $Window
    $script:cmDeleteModal.Width = 440
    $script:cmDeleteModal.SizeToContent = 'Height'
    $script:cmDeleteModal.Topmost = $true
    $script:cmDeleteModal.ResizeMode = 'NoResize'
    $script:cmDeleteModal.ShowInTaskbar = $false

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(245, $bgColor.R, $bgColor.G, $bgColor.B))
    $border.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $border.Padding = [System.Windows.Thickness]::new(28, 24, 28, 24)
    $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $border.Effect = $shadow

    $panel = [System.Windows.Controls.StackPanel]::new()

    # Icon
    $iconText = [System.Windows.Controls.TextBlock]::new()
    $iconText.Text = [char]0xE74D
    $iconText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $iconText.FontSize = 28
    $iconText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor']))
    $iconText.HorizontalAlignment = 'Center'
    $iconText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($iconText) | Out-Null

    # Title
    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.Text = "Deleting Packages"
    $titleText.FontSize = 16
    $titleText.FontWeight = [System.Windows.FontWeights]::Bold
    $titleText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $titleText.HorizontalAlignment = 'Center'
    $titleText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($titleText) | Out-Null

    # Progress counter
    $script:cmDeleteProgressText = [System.Windows.Controls.TextBlock]::new()
    $script:cmDeleteProgressText.Text = "Deleting 0 of $totalCount..."
    $script:cmDeleteProgressText.FontSize = 13
    $script:cmDeleteProgressText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $script:cmDeleteProgressText.HorizontalAlignment = 'Center'
    $script:cmDeleteProgressText.TextAlignment = [System.Windows.TextAlignment]::Center
    $script:cmDeleteProgressText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $panel.Children.Add($script:cmDeleteProgressText) | Out-Null

    # Current package name
    $script:cmDeleteCurrentPkg = [System.Windows.Controls.TextBlock]::new()
    $script:cmDeleteCurrentPkg.Text = ""
    $script:cmDeleteCurrentPkg.FontSize = 11
    $script:cmDeleteCurrentPkg.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $script:cmDeleteCurrentPkg.HorizontalAlignment = 'Center'
    $script:cmDeleteCurrentPkg.TextAlignment = [System.Windows.TextAlignment]::Center
    $script:cmDeleteCurrentPkg.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $script:cmDeleteCurrentPkg.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $panel.Children.Add($script:cmDeleteCurrentPkg) | Out-Null

    # Progress bar
    $script:cmDeleteProgressBar = [System.Windows.Controls.ProgressBar]::new()
    $script:cmDeleteProgressBar.Minimum = 0
    $script:cmDeleteProgressBar.Maximum = $totalCount
    $script:cmDeleteProgressBar.Value = 0
    $script:cmDeleteProgressBar.Height = 6
    $script:cmDeleteProgressBar.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor']))
    $script:cmDeleteProgressBar.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputBackground']))
    $progressTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="ProgressBar">
    <Grid>
        <Border x:Name="PART_Track" Background="{TemplateBinding Background}" CornerRadius="3"/>
        <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}" CornerRadius="3" HorizontalAlignment="Left"/>
    </Grid>
</ControlTemplate>
"@)
    $script:cmDeleteProgressBar.Template = $progressTemplate
    $script:cmDeleteProgressBar.Margin = [System.Windows.Thickness]::new(0, 0, 0, 0)
    $panel.Children.Add($script:cmDeleteProgressBar) | Out-Null

    $border.Child = $panel
    $script:cmDeleteModal.Content = $border

    # Synchronized state for background runspace communication
    $script:cmDeleteState = [hashtable]::Synchronized(@{
        Processed = 0
        Deleted   = 0
        Errors    = 0
        Current   = ''
        Done      = $false
    })

    # Background runspace for WMI calls (keeps UI responsive)
    $script:cmDeleteRunspace = [runspacefactory]::CreateRunspace()
    $script:cmDeleteRunspace.ApartmentState = 'STA'
    $script:cmDeleteRunspace.Open()

    $script:cmDeletePS = [powershell]::Create()
    $script:cmDeletePS.Runspace = $script:cmDeleteRunspace
    [void]$script:cmDeletePS.AddScript({
        param ($SiteServer, $SiteCode, $PkgIds, $PkgNames, $State)
        for ($i = 0; $i -lt $PkgIds.Count; $i++) {
            $State.Current = $PkgNames[$i]
            try {
                $pkg = Get-CimInstance -ComputerName $SiteServer -Namespace "root\SMS\Site_$SiteCode" `
                    -ClassName SMS_Package -Filter "PackageID = '$($PkgIds[$i])'" -ErrorAction Stop
                if ($null -ne $pkg) {
                    $pkg | Remove-CimInstance -ErrorAction Stop
                    $State.Deleted++
                }
            } catch {
                $State.Errors++
            }
            $State.Processed = $i + 1
        }
        $State.Done = $true
    })
    [void]$script:cmDeletePS.AddArgument($global:SiteServer)
    [void]$script:cmDeletePS.AddArgument($global:SiteCode)
    [void]$script:cmDeletePS.AddArgument($pkgIds)
    [void]$script:cmDeletePS.AddArgument($pkgNames)
    [void]$script:cmDeletePS.AddArgument($script:cmDeleteState)
    $script:cmDeleteAsync = $script:cmDeletePS.BeginInvoke()

    # Poll timer to update modal UI from background state
    $script:cmDeleteTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:cmDeleteTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:cmDeleteTimer.Add_Tick({
        $state = $script:cmDeleteState
        $total = $script:cmDeleteProgressBar.Maximum

        $script:cmDeleteProgressBar.Value = $state.Processed
        $script:cmDeleteProgressText.Text = "Deleting $($state.Processed) of $([int]$total)..."
        if (-not [string]::IsNullOrEmpty($state.Current)) {
            $script:cmDeleteCurrentPkg.Text = $state.Current
        }

        if ($state.Done) {
            $script:cmDeleteTimer.Stop()

            $deleted = $state.Deleted
            $errors = $state.Errors
            $script:cmDeleteProgressText.Text = "Deleted $deleted of $([int]$total) package$(if ([int]$total -ne 1) { 's' })" +
                $(if ($errors -gt 0) { " ($errors failed)" } else { "" })
            $script:cmDeleteCurrentPkg.Text = ""

            Write-DATActivityLog "ConfigMgr delete complete: $deleted deleted, $errors failed" -Level $(if ($errors -gt 0) { 'Warn' } else { 'Success' })

            # Auto-close after brief pause, then show summary
            $script:cmDeleteCloseTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $script:cmDeleteCloseTimer.Interval = [TimeSpan]::FromMilliseconds(800)
            $script:cmDeleteCloseTimer.Add_Tick({
                $script:cmDeleteCloseTimer.Stop()
                try { $script:cmDeleteModal.Close() } catch {}

                # Clean up runspace
                try { $script:cmDeletePS.EndInvoke($script:cmDeleteAsync) } catch {}
                try { $script:cmDeletePS.Dispose(); $script:cmDeleteRunspace.Dispose() } catch {}

                $panel_PkgDetails.Visibility = 'Collapsed'
                Invoke-DATPackageRefresh
                $delTotal = [int]$script:cmDeleteProgressBar.Maximum
                $delDeleted = $script:cmDeleteState.Deleted
                $delErrors = $script:cmDeleteState.Errors
                $errMsg = if ($delErrors -gt 0) { "`n`n$delErrors package(s) failed to delete." } else { '' }
                $dlgType = if ($delErrors -gt 0) { 'Warning' } else { 'Success' }
                Show-DATInfoDialog -Title "Deletion Complete" `
                    -Message "Successfully deleted $delDeleted of $delTotal package(s) from ConfigMgr.$errMsg" `
                    -Type $dlgType
                $btn_CmDeleteSelected.IsEnabled = $false
            })
            $script:cmDeleteCloseTimer.Start()
        }
    })
    $script:cmDeleteTimer.Start()

    # Show modal (blocks main window interaction)
    $script:cmDeleteModal.ShowDialog() | Out-Null
})

# Package Details Panel
$panel_PkgDetails = $Window.FindName('panel_PkgDetails')
$txt_PkgDetailName = $Window.FindName('txt_PkgDetailName')
$txt_PkgDetailDesc = $Window.FindName('txt_PkgDetailDesc')
$txt_PkgDetailSource = $Window.FindName('txt_PkgDetailSource')
$txt_PkgDetailMfr = $Window.FindName('txt_PkgDetailMfr')
$txt_PkgDetailID = $Window.FindName('txt_PkgDetailID')
$txt_PkgDetailVersion = $Window.FindName('txt_PkgDetailVersion')
$txt_PkgDetailSize = $Window.FindName('txt_PkgDetailSize')
$txt_PkgDetailUpdated = $Window.FindName('txt_PkgDetailUpdated')
$txt_PkgDetailContentStatus = $Window.FindName('txt_PkgDetailContentStatus')
$btn_CmDeletePackage = $Window.FindName('btn_CmDeletePackage')

$grid_Packages.Add_SelectionChanged({
    $selected = $grid_Packages.SelectedItem
    if ($null -eq $selected -or [string]::IsNullOrEmpty($selected.PackageID)) {
        $panel_PkgDetails.Visibility = 'Collapsed'
        $btn_CmReportIssue.IsEnabled = $false
        $btn_CmDeletePackage.IsEnabled = $false
        return
    }

    $btn_CmReportIssue.IsEnabled = $chk_TelemetryOptOut.IsChecked -eq $true
    $btn_CmDeletePackage.IsEnabled = $true

    try {
        $siteServer = $global:SiteServer
        $siteCode = $global:SiteCode
        $pkgID = $selected.PackageID
        $pkg = Get-WmiObject -ComputerName $siteServer -Namespace "root\SMS\Site_$siteCode" -Class SMS_Package -Filter "PackageID = '$pkgID'" -ErrorAction Stop

        if ($null -ne $pkg) {
            $txt_PkgDetailName.Text = if ($pkg.Name) { $pkg.Name } else { [char]0x2014 }
            $txt_PkgDetailDesc.Text = if ($pkg.Description) { $pkg.Description } else { [char]0x2014 }
            $txt_PkgDetailSource.Text = if ($pkg.PkgSourcePath) { $pkg.PkgSourcePath } else { [char]0x2014 }
            $txt_PkgDetailMfr.Text = if ($pkg.Manufacturer) { $pkg.Manufacturer } else { [char]0x2014 }
            $txt_PkgDetailID.Text = if ($pkg.PackageID) { $pkg.PackageID } else { [char]0x2014 }
            $txt_PkgDetailVersion.Text = if ($pkg.Version) { $pkg.Version } else { [char]0x2014 }

            # Package size (stored in KB)
            if ($pkg.PackageSize -gt 0) {
                $sizeKB = $pkg.PackageSize
                if ($sizeKB -ge 1048576) {
                    $txt_PkgDetailSize.Text = "{0:N2} GB" -f ($sizeKB / 1048576)
                } elseif ($sizeKB -ge 1024) {
                    $txt_PkgDetailSize.Text = "{0:N1} MB" -f ($sizeKB / 1024)
                } else {
                    $txt_PkgDetailSize.Text = "$sizeKB KB"
                }
            } else {
                $txt_PkgDetailSize.Text = [char]0x2014
            }

            # Last updated date
            if ($pkg.LastRefreshTime) {
                $txt_PkgDetailUpdated.Text = [Management.ManagementDateTimeConverter]::ToDateTime($pkg.LastRefreshTime).ToString('yyyy-MM-dd HH:mm')
            } else {
                $txt_PkgDetailUpdated.Text = [char]0x2014
            }

            # Content status
            $statusText = switch ([int]$pkg.PkgFlags -band 0x04000000) {
                0 { 'Not distributed' }
                default { 'Content available' }
            }
            $txt_PkgDetailContentStatus.Text = $statusText

            $panel_PkgDetails.Visibility = 'Visible'

            # Update Report Issue button text based on current state
            $make = if ($pkg.Manufacturer) { $pkg.Manufacturer } else { '' }
            $model = $selected.Model
            $ver = if ($pkg.Version) { $pkg.Version } else { '' }
            if (Test-DATPackageReported -Make $make -Model $model -Version $ver) {
                $btn_CmReportIssue.Content = $null
                $tb = New-Object System.Windows.Controls.TextBlock
                $r1 = New-Object System.Windows.Documents.Run; $r1.Text = [char]0xE711; $r1.FontFamily = 'Segoe MDL2 Assets'
                $r2 = New-Object System.Windows.Documents.Run; $r2.Text = '  Clear Report'
                $tb.Inlines.Add($r1); $tb.Inlines.Add($r2)
                $btn_CmReportIssue.Content = $tb
            } else {
                $tb = New-Object System.Windows.Controls.TextBlock
                $r1 = New-Object System.Windows.Documents.Run; $r1.Text = [char]0xE7BA; $r1.FontFamily = 'Segoe MDL2 Assets'
                $r2 = New-Object System.Windows.Documents.Run; $r2.Text = '  Report Issue'
                $tb.Inlines.Add($r1); $tb.Inlines.Add($r2)
                $btn_CmReportIssue.Content = $tb
            }
        }
    } catch {
        Write-DATLogEntry -Value "[Warning] - Failed to load package details: $($_.Exception.Message)" -Severity 2
        $panel_PkgDetails.Visibility = 'Collapsed'
    }
})

# ConfigMgr Report Issue button
$btn_CmReportIssue.Add_Click({
    if ($chk_TelemetryOptOut.IsChecked -ne $true) { return }
    $selected = $grid_Packages.SelectedItem
    if ($null -eq $selected) { return }
    $make = $selected.Manufacturer
    $model = $selected.Model
    $ver = $selected.Version
    if ([string]::IsNullOrEmpty($make) -and [string]::IsNullOrEmpty($model)) { return }

    if (Test-DATPackageReported -Make $make -Model $model -Version $ver) {
        Remove-DATReportedIssue -Make $make -Model $model -Version $ver
        Write-DATActivityLog "Cleared issue report: $make $model v$ver" -Level Info
        $txt_PkgStatus.Foreground = $Window.FindResource('StatusInfo')
        $txt_PkgStatus.Text = "Issue report cleared for: $($selected.Name)"
        $txt_PkgStatus.Visibility = 'Visible'
    } else {
        Add-DATReportedIssue -Make $make -Model $model -Version $ver
        Write-DATActivityLog "Reported issue: $make $model v$ver" -Level Warn
        $txt_PkgStatus.Foreground = $Window.FindResource('StatusWarning')
        $txt_PkgStatus.Text = "Issue reported for: $($selected.Name)"
        $txt_PkgStatus.Visibility = 'Visible'
    }

    # Refresh button text
    if (Test-DATPackageReported -Make $make -Model $model -Version $ver) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $r1 = New-Object System.Windows.Documents.Run; $r1.Text = [char]0xE711; $r1.FontFamily = 'Segoe MDL2 Assets'
        $r2 = New-Object System.Windows.Documents.Run; $r2.Text = '  Clear Report'
        $tb.Inlines.Add($r1); $tb.Inlines.Add($r2)
        $btn_CmReportIssue.Content = $tb
    } else {
        $tb = New-Object System.Windows.Controls.TextBlock
        $r1 = New-Object System.Windows.Documents.Run; $r1.Text = [char]0xE7BA; $r1.FontFamily = 'Segoe MDL2 Assets'
        $r2 = New-Object System.Windows.Documents.Run; $r2.Text = '  Report Issue'
        $tb.Inlines.Add($r1); $tb.Inlines.Add($r2)
        $btn_CmReportIssue.Content = $tb
    }

    # Refresh row highlighting
    Update-DATPackageRowHighlighting -DataGrid $grid_Packages -ItemsSource $script:PackageData -MakeProperty 'Manufacturer' -ModelProperty 'Model' -VersionProperty 'Version'
})

# ConfigMgr Delete Package button
$btn_CmDeletePackage.Add_Click({
    $selected = $grid_Packages.SelectedItem
    if ($null -eq $selected -or [string]::IsNullOrEmpty($selected.PackageID)) { return }

    $confirm = Show-DATConfirmDialog -Title "Delete Package" -Message "Are you sure you want to delete package '$($selected.Name)' ($($selected.PackageID))?`n`nThis action cannot be undone."
    if (-not $confirm) { return }

    try {
        $siteServer = $global:SiteServer
        $siteCode = $global:SiteCode
        $pkg = Get-CimInstance -ComputerName $siteServer -Namespace "root\SMS\Site_$siteCode" -ClassName SMS_Package -Filter "PackageID = '$($selected.PackageID)'" -ErrorAction Stop
        if ($null -ne $pkg) {
            $pkg | Remove-CimInstance -ErrorAction Stop
            Write-DATActivityLog "Deleted package: $($selected.Name) ($($selected.PackageID))" -Level Success
            Write-DATLogEntry -Value "Deleted ConfigMgr package: $($selected.Name) ($($selected.PackageID))" -Severity 1
            $txt_PkgStatus.Foreground = $Window.FindResource('StatusSuccess')
            $txt_PkgStatus.Text = "Deleted: $($selected.Name)"
            $txt_PkgStatus.Visibility = 'Visible'
            $panel_PkgDetails.Visibility = 'Collapsed'
            Invoke-DATPackageRefresh
            Show-DATInfoDialog -Title "Package Deleted" `
                -Message "'$($selected.Name)' ($($selected.PackageID)) has been successfully removed from ConfigMgr." `
                -Type Success
        }
    } catch {
        Write-DATActivityLog "Failed to delete package: $($_.Exception.Message)" -Level Error
        Write-DATLogEntry -Value "[Error] - Failed to delete package $($selected.PackageID): $($_.Exception.Message)" -Severity 3
        $txt_PkgStatus.Foreground = $Window.FindResource('StatusError')
        $txt_PkgStatus.Text = "Failed to delete: $($_.Exception.Message)"
        $txt_PkgStatus.Visibility = 'Visible'
    }
})

# --- Change OS Target action ---

function Show-DATChangeOSTargetDialog {
    <#
    .SYNOPSIS
        Shows an OS targeting modal with a dropdown of Windows 11 versions.
        Returns the selected OS string (e.g. "Windows 11 24H2") or $null if cancelled.
    #>

    $script:osTargetResult = $null
    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])

    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background = [System.Windows.Media.Brushes]::Transparent
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner = $Window
    $dlg.Width = 460
    $dlg.SizeToContent = 'Height'
    $dlg.Topmost = $true
    $dlg.ResizeMode = 'NoResize'
    $dlg.ShowInTaskbar = $false

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(245, $bgColor.R, $bgColor.G, $bgColor.B))
    $border.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $border.Padding = [System.Windows.Thickness]::new(28, 24, 28, 24)
    $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $border.Effect = $shadow

    $panel = [System.Windows.Controls.StackPanel]::new()

    # Icon
    $iconText = [System.Windows.Controls.TextBlock]::new()
    $iconText.Text = [string][char]0xE770
    $iconText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $iconText.FontSize = 28
    $iconText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor']))
    $iconText.HorizontalAlignment = 'Center'
    $iconText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($iconText) | Out-Null

    # Title
    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.Text = "Operating System Targeting"
    $titleText.FontSize = 16
    $titleText.FontWeight = [System.Windows.FontWeights]::Bold
    $titleText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $titleText.HorizontalAlignment = 'Center'
    $titleText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $panel.Children.Add($titleText) | Out-Null

    # Message
    $msgText = [System.Windows.Controls.TextBlock]::new()
    $msgText.Text = "Please specify the version of Windows you wish to move the package to."
    $msgText.FontSize = 13
    $msgText.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $msgText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $msgText.HorizontalAlignment = 'Center'
    $msgText.TextAlignment = [System.Windows.TextAlignment]::Center
    $msgText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 20)
    $panel.Children.Add($msgText) | Out-Null

    # OS Version dropdown — themed to match pill ComboBox style
    $cmbXaml = @"
<ComboBox xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
          xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
          Height="36" FontSize="13" Margin="0,0,0,24"
          HorizontalAlignment="Stretch" SelectedIndex="0"
          Foreground="$($theme['ComboForeground'])">
    <ComboBox.Template>
        <ControlTemplate TargetType="ComboBox">
            <Grid>
                <ToggleButton x:Name="ToggleButton" Focusable="False"
                              IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                              ClickMode="Press">
                    <ToggleButton.Template>
                        <ControlTemplate TargetType="ToggleButton">
                            <Border x:Name="bd" Background="$($theme['ComboBackground'])"
                                    BorderBrush="$($theme['ComboBorder'])" BorderThickness="1"
                                    CornerRadius="10" Padding="16,0,12,0" Cursor="Hand">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="1" Text="&#xE70D;" FontFamily="Segoe MDL2 Assets"
                                               FontSize="10" VerticalAlignment="Center"
                                               Foreground="$($theme['InputPlaceholder'])"/>
                                </Grid>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="bd" Property="BorderBrush" Value="$($theme['AccentColor'])"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </ToggleButton.Template>
                </ToggleButton>
                <ContentPresenter x:Name="ContentSite" IsHitTestVisible="False"
                                  Content="{TemplateBinding SelectionBoxItem}"
                                  ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                  VerticalAlignment="Center" HorizontalAlignment="Left"
                                  Margin="16,0,28,0"/>
                <Popup x:Name="Popup" Placement="Bottom"
                       IsOpen="{TemplateBinding IsDropDownOpen}"
                       AllowsTransparency="True" Focusable="False"
                       PopupAnimation="Slide" VerticalOffset="4">
                    <Border Background="$($theme['ComboBackground'])"
                            BorderBrush="$($theme['ComboBorder'])" BorderThickness="1"
                            CornerRadius="12" Padding="4"
                            MinWidth="{TemplateBinding ActualWidth}"
                            MaxHeight="{TemplateBinding MaxDropDownHeight}">
                        <ScrollViewer SnapsToDevicePixels="True">
                            <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/>
                        </ScrollViewer>
                    </Border>
                </Popup>
            </Grid>
        </ControlTemplate>
    </ComboBox.Template>
    <ComboBox.ItemContainerStyle>
        <Style TargetType="ComboBoxItem">
            <Setter Property="Foreground" Value="$($theme['ComboForeground'])"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="itemBorder" Background="Transparent"
                                CornerRadius="8" Padding="12,7" Margin="0,1" Cursor="Hand">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="itemBorder" Property="Background" Value="$($theme['SidebarHover'])"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="itemBorder" Property="Background" Value="$($theme['ButtonPrimary'])"/>
                                <Setter Property="Foreground" Value="$($theme['ButtonPrimaryForeground'])"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </ComboBox.ItemContainerStyle>
    <ComboBoxItem Content="Windows 11 25H2"/>
    <ComboBoxItem Content="Windows 11 24H2"/>
    <ComboBoxItem Content="Windows 11 23H2"/>
    <ComboBoxItem Content="Windows 11 22H2"/>
</ComboBox>
"@
    $cmbOS = [System.Windows.Markup.XamlReader]::Parse($cmbXaml)
    $panel.Children.Add($cmbOS) | Out-Null

    # Button row
    $btnGrid = [System.Windows.Controls.Grid]::new()
    $col1 = [System.Windows.Controls.ColumnDefinition]::new(); $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col2 = [System.Windows.Controls.ColumnDefinition]::new(); $col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $btnGrid.ColumnDefinitions.Add($col1)
    $btnGrid.ColumnDefinitions.Add($col2)

    # Proceed button (primary style)
    $btnProceed = [System.Windows.Controls.Button]::new()
    $btnProceed.Height = 36
    $btnProceed.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
    $btnProceed.Cursor = [System.Windows.Input.Cursors]::Hand
    $proceedTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonPrimary'])" CornerRadius="8" Padding="16,8">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonPrimaryHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnProceed.Template = $proceedTemplate
    $btnProceed.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonPrimaryForeground']))
    $btnProceed.FontSize = 13
    $btnProceed.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnProceed.Content = "Proceed"
    [System.Windows.Controls.Grid]::SetColumn($btnProceed, 0)
    $btnProceed.Add_Click({
        $script:osTargetResult = $cmbOS.SelectedItem.Content
        $dlg.Close()
    })
    $btnGrid.Children.Add($btnProceed) | Out-Null

    # Cancel button (secondary style)
    $btnCancel = [System.Windows.Controls.Button]::new()
    $btnCancel.Height = 36
    $btnCancel.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
    $btnCancel.Cursor = [System.Windows.Input.Cursors]::Hand
    $cancelTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
    <Border x:Name="bd" Background="$($theme['ButtonSecondary'])" CornerRadius="8" Padding="16,8">
        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="bd" Property="Background" Value="$($theme['ButtonSecondaryHover'])"/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@)
    $btnCancel.Template = $cancelTemplate
    $btnCancel.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['ButtonSecondaryForeground']))
    $btnCancel.FontSize = 13
    $btnCancel.FontWeight = [System.Windows.FontWeights]::SemiBold
    $btnCancel.Content = "Cancel"
    [System.Windows.Controls.Grid]::SetColumn($btnCancel, 1)
    $btnCancel.Add_Click({ $script:osTargetResult = $null; $dlg.Close() })
    $btnGrid.Children.Add($btnCancel) | Out-Null

    $panel.Children.Add($btnGrid) | Out-Null
    $border.Child = $panel
    $dlg.Content = $border

    $dlg.ShowDialog() | Out-Null
    return $script:osTargetResult
}

$cmb_PkgAction.Add_SelectionChanged({
    $action = if ($null -ne $cmb_PkgAction.SelectedItem) { $cmb_PkgAction.SelectedItem.Content } else { $null }
    if ([string]::IsNullOrEmpty($action)) { return }

    # Get checked packages
    $selectedPkgs = @($script:PackageData | Where-Object { $_.Selected -eq $true })
    if ($selectedPkgs.Count -eq 0) {
        $txt_PkgStatus.Foreground = $Window.FindResource('StatusWarning')
        $txt_PkgStatus.Text = "No packages selected. Please check one or more packages first."
        $txt_PkgStatus.Visibility = 'Visible'
        $cmb_PkgAction.SelectedIndex = -1
        return
    }

    if ($action -eq 'Change OS Target') {
        $newOS = Show-DATChangeOSTargetDialog
        if ([string]::IsNullOrEmpty($newOS)) { $cmb_PkgAction.SelectedIndex = -1; return }

        $osPattern = 'Windows\s+1[01]\s+\d{2}H[12]'
        $siteServer = $global:SiteServer
        $siteCode = $global:SiteCode
        $successCount = 0
        $failCount = 0

        foreach ($pkg in $selectedPkgs) {
            try {
                $oldName = $pkg.Name
                if ($oldName -notmatch $osPattern) {
                    Write-DATLogEntry -Value "[Warning] - Package '$oldName' does not contain a recognizable Windows version — skipped" -Severity 2
                    $failCount++
                    continue
                }
                $newName = $oldName -replace $osPattern, $newOS
                if ($newName -eq $oldName) {
                    Write-DATLogEntry -Value "- Package '$oldName' already targets $newOS — skipped" -Severity 1
                    continue
                }
                $wmiPkg = Get-WmiObject -ComputerName $siteServer -Namespace "root\SMS\Site_$siteCode" `
                    -Class SMS_Package -Filter "PackageID = '$($pkg.PackageID)'" -ErrorAction Stop
                if ($null -ne $wmiPkg) {
                    $wmiPkg.Name = $newName
                    $wmiPkg.Put() | Out-Null
                    Write-DATLogEntry -Value "- Renamed package $($pkg.PackageID): '$oldName' -> '$newName'" -Severity 1
                    $pkg.Name = $newName
                    $successCount++
                }
            } catch {
                Write-DATLogEntry -Value "[Error] - Failed to rename package $($pkg.PackageID): $($_.Exception.Message)" -Severity 3
                $failCount++
            }
        }

        if ($failCount -eq 0 -and $successCount -gt 0) {
            $txt_PkgStatus.Foreground = $Window.FindResource('StatusSuccess')
            $txt_PkgStatus.Text = "Renamed $successCount package$(if ($successCount -ne 1) { 's' }) to target $newOS"
        } elseif ($successCount -gt 0) {
            $txt_PkgStatus.Foreground = $Window.FindResource('StatusWarning')
            $txt_PkgStatus.Text = "Renamed $successCount package$(if ($successCount -ne 1) { 's' }), $failCount failed"
        } else {
            $txt_PkgStatus.Foreground = $Window.FindResource('StatusError')
            $txt_PkgStatus.Text = "No packages were renamed"
        }
    }
    elseif ($action -match '^Move to (Production|Pilot|Retired)$') {
        $targetState = $Matches[1]

        # Regex: match the package type prefix — "Drivers", "Drivers Pilot", "Drivers Retired"
        # (or BIOS equivalents) at the start of the name, followed by " -"
        $prefixPattern = '^(Drivers|BIOS Update|Bios Update)(?:\s+(?:Pilot|Retired))?\s+-'

        $siteServer = $global:SiteServer
        $siteCode = $global:SiteCode
        $successCount = 0
        $failCount = 0

        foreach ($pkg in $selectedPkgs) {
            try {
                $oldName = $pkg.Name
                if ($oldName -notmatch $prefixPattern) {
                    Write-DATLogEntry -Value "[Warning] - Package '$oldName' does not match expected naming pattern — skipped" -Severity 2
                    $failCount++
                    continue
                }

                $baseType = $Matches[1]  # "Drivers" or "BIOS Update"
                $newPrefix = switch ($targetState) {
                    'Production' { "$baseType -" }
                    'Pilot'      { "$baseType Pilot -" }
                    'Retired'    { "$baseType Retired -" }
                }
                $newName = $oldName -replace $prefixPattern, $newPrefix

                if ($newName -eq $oldName) {
                    Write-DATLogEntry -Value "- Package '$oldName' is already in $targetState state — skipped" -Severity 1
                    continue
                }

                $wmiPkg = Get-WmiObject -ComputerName $siteServer -Namespace "root\SMS\Site_$siteCode" `
                    -Class SMS_Package -Filter "PackageID = '$($pkg.PackageID)'" -ErrorAction Stop
                if ($null -ne $wmiPkg) {
                    $wmiPkg.Name = $newName
                    $wmiPkg.Put() | Out-Null
                    Write-DATLogEntry -Value "- Renamed package $($pkg.PackageID): '$oldName' -> '$newName'" -Severity 1
                    $pkg.Name = $newName
                    $successCount++
                }
            } catch {
                Write-DATLogEntry -Value "[Error] - Failed to rename package $($pkg.PackageID): $($_.Exception.Message)" -Severity 3
                $failCount++
            }
        }

        if ($failCount -eq 0 -and $successCount -gt 0) {
            $txt_PkgStatus.Foreground = $Window.FindResource('StatusSuccess')
            $txt_PkgStatus.Text = "Moved $successCount package$(if ($successCount -ne 1) { 's' }) to $targetState"
        } elseif ($successCount -gt 0) {
            $txt_PkgStatus.Foreground = $Window.FindResource('StatusWarning')
            $txt_PkgStatus.Text = "Moved $successCount package$(if ($successCount -ne 1) { 's' }) to $targetState, $failCount failed"
        } else {
            $txt_PkgStatus.Foreground = $Window.FindResource('StatusError')
            $txt_PkgStatus.Text = "No packages were moved"
        }
    }

    $txt_PkgStatus.Visibility = 'Visible'
    $grid_Packages.Items.Refresh()

    # Refresh the details panel if a changed package is currently selected
    $currentSel = $grid_Packages.SelectedItem
    if ($null -ne $currentSel -and -not [string]::IsNullOrEmpty($currentSel.PackageID)) {
        $txt_PkgDetailName.Text = $currentSel.Name
    }

    $cmb_PkgAction.SelectedIndex = -1
})

#endregion Package Management

#region Common Settings

function Update-DATDiskFreeSpace {
    param([string]$Path, $ProgressBar, $Label, $Container)
    try {
        if ([string]::IsNullOrWhiteSpace($Path)) { $Container.Visibility = 'Collapsed'; return }
        $root = [System.IO.Path]::GetPathRoot($Path)
        if (-not $root -or $root.StartsWith('\\')) { $Container.Visibility = 'Collapsed'; return }
        $drive = [System.IO.DriveInfo]::new($root)
        if (-not $drive.IsReady) { $Container.Visibility = 'Collapsed'; return }
        $totalGB = [math]::Round($drive.TotalSize / 1GB, 1)
        $freeGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
        $usedPct = [math]::Round((($drive.TotalSize - $drive.AvailableFreeSpace) / $drive.TotalSize) * 100, 0)
        $ProgressBar.Value = $usedPct
        $ProgressBar.Foreground = if ($usedPct -ge 90) { '#EF4444' } elseif ($usedPct -ge 75) { '#F59E0B' } else { '#3B82F6' }
        $Label.Text = "$freeGB GB free of $totalGB GB ($root)"
        $Container.Visibility = 'Visible'
    } catch {
        $Container.Visibility = 'Collapsed'
    }
}

$btn_BrowseTemp.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select Temporary Storage Path (local paths only)"
    if ($dialog.ShowDialog() -eq 'OK') {
        if ($dialog.SelectedPath -match '^\\\\') {
            Show-DATInfoDialog -Title 'Invalid Path' `
                -Message "Temporary Storage Path must be a local path (not a UNC/network path).`nPlease select a local folder." `
                -Type Warning
            return
        }
        $txt_TempStorage.Text = $dialog.SelectedPath
        Set-DATRegistryValue -Name "TempStoragePath" -Value $dialog.SelectedPath -Type String
        Update-DATDiskFreeSpace -Path $dialog.SelectedPath -ProgressBar $progress_TempFreeSpace -Label $txt_TempFreeSpace -Container $grid_TempFreeSpace
    }
})

$btn_BrowsePackage.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select Package Storage Path"
    if ($dialog.ShowDialog() -eq 'OK') {
        $txt_PackageStorage.Text = $dialog.SelectedPath
        Set-DATRegistryValue -Name "PackageStoragePath" -Value $dialog.SelectedPath -Type String
        Update-DATDiskFreeSpace -Path $dialog.SelectedPath -ProgressBar $progress_PackageFreeSpace -Label $txt_PackageFreeSpace -Container $grid_PackageFreeSpace
    }
})

$txt_TempStorage.Add_LostFocus({
    $path = $txt_TempStorage.Text
    if (-not [string]::IsNullOrEmpty($path)) {
        if ($path -match '^\\\\') {
            Show-DATInfoDialog -Title 'Invalid Path' `
                -Message "Temporary Storage Path must be a local path (not a UNC/network path).`nPlease enter a local folder." `
                -Type Warning
            $txt_TempStorage.Text = ''
            return
        }
        Set-DATRegistryValue -Name "TempStoragePath" -Value $path -Type String
    }
    Update-DATDiskFreeSpace -Path $path -ProgressBar $progress_TempFreeSpace -Label $txt_TempFreeSpace -Container $grid_TempFreeSpace
})

$txt_PackageStorage.Add_LostFocus({
    $path = $txt_PackageStorage.Text
    if (-not [string]::IsNullOrEmpty($path)) {
        Set-DATRegistryValue -Name "PackageStoragePath" -Value $path -Type String
    }
    Update-DATDiskFreeSpace -Path $path -ProgressBar $progress_PackageFreeSpace -Label $txt_PackageFreeSpace -Container $grid_PackageFreeSpace
})

$chk_TelemetryOptOut.Add_Checked({
    Set-DATRegistryValue -Name "TelemetryOptOut" -Value 1 -Type DWord
    # Generate GUID on first opt-in; reuse existing one on subsequent toggles
    $existingGuid = (Get-ItemProperty -Path $global:RegPath -Name "TelemetryGuid" -ErrorAction SilentlyContinue).TelemetryGuid
    if ([string]::IsNullOrEmpty($existingGuid)) {
        $existingGuid = [System.Guid]::NewGuid().ToString()
        Set-DATRegistryValue -Name "TelemetryGuid" -Value $existingGuid -Type String
    }
    $txt_TelemetryGuid.Text = $existingGuid
    $panel_TelemetryGuid.Visibility = 'Visible'
    # Enable Report Issue buttons when telemetry is opted in
    if ($null -ne $grid_Packages.SelectedItem) { $btn_CmReportIssue.IsEnabled = $true }
    $btn_IntuneReportIssue.IsEnabled = $true
    # Pre-fetch remote telemetry config so endpoints are cached for the session
    try { $null = Get-DATTelemetryConfig } catch { }
})
$chk_TelemetryOptOut.Add_Unchecked({
    Set-DATRegistryValue -Name "TelemetryOptOut" -Value 0 -Type DWord
    $panel_TelemetryGuid.Visibility = 'Collapsed'
    # Disable Report Issue buttons when telemetry is opted out
    $btn_CmReportIssue.IsEnabled = $false
    $btn_IntuneReportIssue.IsEnabled = $false
})

$btn_CopyTelemetryGuid = $Window.FindName('btn_CopyTelemetryGuid')
$btn_CopyTelemetryGuid.Add_Click({
    if (-not [string]::IsNullOrEmpty($txt_TelemetryGuid.Text)) {
        [System.Windows.Clipboard]::SetText($txt_TelemetryGuid.Text)
        $txt_Status.Text = "Telemetry ID copied to clipboard."
    }
})

$btn_TestTelemetry = $Window.FindName('btn_TestTelemetry')
$txt_TelemetryTestResult = $Window.FindName('txt_TelemetryTestResult')
$btn_TestTelemetry.Add_Click({
    $txt_TelemetryTestResult.Foreground = $Window.FindResource('InputPlaceholder')
    $txt_TelemetryTestResult.Text = "Testing..."
    $btn_TestTelemetry.IsEnabled = $false

    # Flush the render queue so "Testing..." is visible before the blocking network calls
    $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [action]{})

    try {
        $testResult = Test-DATTelemetryConnection

        if ($testResult.ConfigOk -and $testResult.HealthOk) {
            $txt_TelemetryTestResult.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusSuccess']))
            $txt_TelemetryTestResult.Text = "Connected — $($testResult.ApiBaseUrl)"
        } elseif ($testResult.ConfigOk) {
            $txt_TelemetryTestResult.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
            $txt_TelemetryTestResult.Text = "Config OK, API unreachable: $($testResult.Error)"
        } else {
            $txt_TelemetryTestResult.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
            $txt_TelemetryTestResult.Text = "$($testResult.Error)"
        }
    } catch {
        $txt_TelemetryTestResult.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
        $txt_TelemetryTestResult.Text = "Test failed: $($_.Exception.Message)"
    }

    $btn_TestTelemetry.IsEnabled = $true
})

$btn_ExportConfig.Add_Click({
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = "Registry Files (*.reg)|*.reg"
    $dialog.FileName = "DriverAutomationTool_Config.reg"
    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $regExportPath = $global:RegPath -replace "HKLM:", "HKLM"
            $cmd = "reg export `"$regExportPath`" `"$($dialog.FileName)`" /y"
            Invoke-Expression -Command $cmd
            $txt_Status.Text = "Configuration exported to $($dialog.FileName)"
        } catch {
            $txt_Status.Text = "Export failed: $($_.Exception.Message)"
        }
    }
})

$btn_ImportConfig.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "Registry Files (*.reg)|*.reg"
    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $cmd = "reg import `"$($dialog.FileName)`""
            Invoke-Expression -Command $cmd
            $txt_Status.Text = "Configuration imported from $($dialog.FileName)"
        } catch {
            $txt_Status.Text = "Import failed: $($_.Exception.Message)"
        }
    }
})

# Clean Temp on Exit toggle
$chk_CleanTempOnExit = $Window.FindName('chk_CleanTempOnExit')
$chk_CleanTempOnExit.Add_Checked({
    Set-DATRegistryValue -Name "CleanTempOnExit" -Value 1 -Type DWord
    Write-DATActivityLog "Clean temp on exit enabled" -Level Info
})
$chk_CleanTempOnExit.Add_Unchecked({
    Set-DATRegistryValue -Name "CleanTempOnExit" -Value 0 -Type DWord
    Write-DATActivityLog "Clean temp on exit disabled" -Level Info
})

# Teams Notifications save handlers
$chk_TeamsNotifications.Add_Checked({
    Set-DATRegistryValue -Name "TeamsNotificationsEnabled" -Value 1 -Type DWord
    Write-DATActivityLog "Teams notifications enabled" -Level Info
})
$chk_TeamsNotifications.Add_Unchecked({
    Set-DATRegistryValue -Name "TeamsNotificationsEnabled" -Value 0 -Type DWord
    Write-DATActivityLog "Teams notifications disabled" -Level Info
})
$txt_TeamsWebhookUrl.Add_LostFocus({
    $url = $txt_TeamsWebhookUrl.Text
    Set-DATRegistryValue -Name "TeamsWebhookUrl" -Value $url -Type String
})
$btn_TeamsTest.Add_Click({
    $url = $txt_TeamsWebhookUrl.Text
    if ([string]::IsNullOrWhiteSpace($url)) {
        $txt_TeamsTestResult.Text = "Please enter a webhook URL."
        $txt_TeamsTestResult.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
        $txt_TeamsTestResult.Visibility = 'Visible'
        return
    }
    try {
        Send-DATTeamsNotification -WebhookUrl $url -TotalModels 1 -SuccessCount 1 -FailedCount 0 `
            -Platform 'Test' -PackageType 'Test' -Models @([PSCustomObject]@{ OEM = 'Test'; Model = 'Test Notification' })
        $txt_TeamsTestResult.Text = "Test notification sent successfully."
        $txt_TeamsTestResult.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusSuccess']))
    } catch {
        $txt_TeamsTestResult.Text = "Failed: $($_.Exception.Message)"
        $txt_TeamsTestResult.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
    }
    $txt_TeamsTestResult.Visibility = 'Visible'
})

# Schedule Build button + modal handlers
$btn_Schedule.Add_Click({
    # Guard: ensure the target platform is connected before scheduling
    $schedulePlatform = if ($null -ne $cmb_Platform.SelectedItem) { $cmb_Platform.SelectedItem.Content } else { 'Download Only' }
    if ($schedulePlatform -eq 'Configuration Manager' -and [string]::IsNullOrEmpty($global:SiteCode)) {
        Show-DATInfoDialog -Title 'ConfigMgr Not Connected' `
            -Message 'Please connect to Configuration Manager before scheduling a build. Navigate to ConfigMgr Settings to configure the site server connection.' `
            -Type Warning -ButtonLabel 'OK'
        Write-DATActivityLog "Schedule blocked — Configuration Manager not connected" -Level Warn
        return
    }
    if ($schedulePlatform -eq 'Intune') {
        $authCheck = Get-DATIntuneAuthStatus
        if (-not $authCheck.IsAuthenticated) {
            Show-DATInfoDialog -Title 'Intune Not Connected' `
                -Message 'Please connect to Microsoft Intune before scheduling a build. Navigate to Intune Settings > Environment to sign in.' `
                -Type Warning -ButtonLabel 'OK'
            Write-DATActivityLog "Schedule blocked — Intune not connected" -Level Warn
            return
        }
    }

    # Guard: Microsoft models do not support standalone BIOS packages
    $schedBuildPkgType = if ($null -ne $cmb_PackageType -and $null -ne $cmb_PackageType.SelectedItem) { $cmb_PackageType.SelectedItem.Content } else { 'Drivers' }
    if ($schedBuildPkgType -eq 'BIOS') {
        $schedSelectedModels = @($script:ModelData | Where-Object { $_.Selected -eq $true })
        $schedMsModels = @($schedSelectedModels | Where-Object { $_.OEM -eq 'Microsoft' })
        if ($schedMsModels.Count -gt 0 -and $schedMsModels.Count -eq $schedSelectedModels.Count) {
            Show-DATInfoDialog -Title 'BIOS Packages Not Supported' `
                -Message "Microsoft Surface devices receive BIOS/firmware updates through the driver update process. Please select 'Drivers' or 'All' as the package type instead." `
                -Type Info -ButtonLabel 'OK'
            Write-DATActivityLog "Schedule blocked -- BIOS package type not supported for Microsoft models (firmware is included in driver updates)" -Level Warn
            return
        }
    }

    $configPath = Join-Path $global:ScriptDirectory 'Settings\BuildConfig.json'
    $txt_ScheduleConfigPath.Text = $configPath

    # Show overlay immediately with defaults so the UI feels responsive
    $btn_ScheduleRemove.Visibility = 'Collapsed'
    $now = (Get-Date).AddMinutes(5)
    $minRemainder = $now.Minute % 5
    if ($minRemainder -gt 0) {
        $next5 = $now.AddMinutes(5 - $minRemainder).AddSeconds(-$now.Second)
    } else {
        $next5 = $now.AddSeconds(-$now.Second)
    }
    $cmb_ScheduleHour.SelectedIndex = $next5.Hour
    $minIdx = [int]($next5.Minute / 5)
    if ($minIdx -ge 12) { $minIdx = 0 }
    $cmb_ScheduleMinute.SelectedIndex = $minIdx

    $overlay_Schedule.Visibility = 'Visible'
    $Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [action]{})

    # Now query for existing scheduled task (CIM call can be slow)
    $existing = Get-ScheduledTask -TaskPath '\Driver Automation Tool\' -TaskName 'Scheduled Package Build' -ErrorAction SilentlyContinue
    if ($existing) {
        $btn_ScheduleRemove.Visibility = 'Visible'
        # Parse existing trigger info
        foreach ($t in $existing.Triggers) {
            if ($t -is [Microsoft.Management.Infrastructure.CimInstance]) {
                if ($t.CimClass.CimClassName -eq 'MSFT_TaskTimeTrigger') {
                    $cmb_ScheduleFrequency.SelectedIndex = 0
                } elseif ($t.CimClass.CimClassName -eq 'MSFT_TaskDailyTrigger') {
                    $cmb_ScheduleFrequency.SelectedIndex = 1
                } elseif ($t.CimClass.CimClassName -eq 'MSFT_TaskWeeklyTrigger') {
                    $cmb_ScheduleFrequency.SelectedIndex = 2
                }
                if ($t.StartBoundary) {
                    try {
                        $startDt = [datetime]::Parse($t.StartBoundary)
                        $cmb_ScheduleHour.SelectedIndex = $startDt.Hour
                        $minIdx = [math]::Round($startDt.Minute / 5)
                        if ($minIdx -ge 12) { $minIdx = 0 }
                        $cmb_ScheduleMinute.SelectedIndex = $minIdx
                    } catch {}
                }
            }
        }
    }
})

$cmb_ScheduleFrequency.Add_SelectionChanged({
    $selectedFreq = $cmb_ScheduleFrequency.SelectedItem.Content
    $panel_ScheduleDay.Visibility = if ($selectedFreq -eq 'Weekly') { 'Visible' } else { 'Collapsed' }
})

$btn_ScheduleCancel.Add_Click({
    $overlay_Schedule.Visibility = 'Collapsed'
})

$btn_ScheduleSave.Add_Click({
    $configPath = $txt_ScheduleConfigPath.Text
    $frequency = $cmb_ScheduleFrequency.SelectedItem.Content
    $time = '{0}:{1}' -f $cmb_ScheduleHour.SelectedItem.Content, $cmb_ScheduleMinute.SelectedItem.Content

    # Export current UI selections into BuildConfig.json
    $schedModels = $script:ModelData | Where-Object { $_.Selected -eq $true }
    if ($schedModels.Count -eq 0) {
        Show-DATInfoDialog -Title 'No Models Selected' `
            -Message 'Please select at least one model before scheduling.' `
            -Type Warning
        return
    }
    $schedPlatform = if ($null -ne $cmb_Platform.SelectedItem) { $cmb_Platform.SelectedItem.Content } else { 'Download Only' }

    # Intune scheduled builds require App Registration credentials for unattended auth
    if ($schedPlatform -eq 'Intune') {
        $schedTenantId = $txt_IntuneTenantId.Text.Trim()
        $schedAppId = $txt_IntuneAppId.Text.Trim()
        $schedSecret = $txt_IntuneClientSecret.Password
        if ([string]::IsNullOrEmpty($schedTenantId) -or [string]::IsNullOrEmpty($schedAppId) -or [string]::IsNullOrEmpty($schedSecret)) {
            Show-DATInfoDialog -Title "Intune Credentials Required" `
                -Message "Scheduled builds in Intune mode require an App Registration with Client ID and Client Secret for unattended authentication.`n`nPlease configure these under Intune Settings before scheduling a build." `
                -Icon ([char]0xE7BA)
            return
        }
    }

    $schedOS = if ($null -ne $cmb_OS.SelectedItem) { $cmb_OS.SelectedItem.Content } else { $null }
    $schedArch = if ($null -ne $cmb_Architecture.SelectedItem) { $cmb_Architecture.SelectedItem.Content } else { 'x64' }
    $schedPkgType = if ($null -ne $cmb_PackageType -and $null -ne $cmb_PackageType.SelectedItem) { $cmb_PackageType.SelectedItem.Content } else { 'Drivers' }

    # Guard: Microsoft models do not support standalone BIOS packages
    if ($schedPkgType -eq 'BIOS') {
        $schedMsModels = @($schedModels | Where-Object { $_.OEM -eq 'Microsoft' })
        if ($schedMsModels.Count -gt 0 -and $schedMsModels.Count -eq @($schedModels).Count) {
            Show-DATInfoDialog -Title 'BIOS Packages Not Supported' `
                -Message "Microsoft Surface devices receive BIOS/firmware updates through the driver update process. Please select 'Drivers' or 'All' as the package type instead." `
                -Type Info -ButtonLabel 'OK'
            Write-DATActivityLog "Schedule save blocked -- BIOS package type not supported for Microsoft models" -Level Warn
            return
        }
        if ($schedMsModels.Count -gt 0) {
            $schedModels = @($schedModels | Where-Object { $_.OEM -ne 'Microsoft' })
            $msNames = ($schedMsModels | ForEach-Object { $_.Model }) -join ', '
            Show-DATInfoDialog -Title 'Microsoft Models Excluded' `
                -Message "The following Microsoft models have been excluded from the scheduled BIOS build because Surface firmware updates are delivered via the driver update process:`n`n$msNames" `
                -Type Warning -ButtonLabel 'OK'
            Write-DATActivityLog "Schedule save -- excluded $($schedMsModels.Count) Microsoft model(s) from BIOS build: $msNames" -Level Warn
        }
    }

    $schedDisableToast = ($schedPlatform -eq 'Intune') -and ($chk_DisableToastPrompt.IsChecked -eq $true)
    $schedTimeoutAction = if ($cmb_BIOSTimeoutAction.SelectedIndex -eq 1) { 'InstallNow' } else { 'RemindMeLater' }
    $schedMaxDeferrals = if (($chk_EnableMaxDeferrals.IsChecked -eq $true) -and ($txt_MaxDeferrals.Text -match '^\d+$')) { [int]$txt_MaxDeferrals.Text } else { 0 }
    $schedTeamsEnabled = $chk_TeamsNotifications.IsChecked -eq $true
    $schedTeamsUrl = $txt_TeamsWebhookUrl.Text
    $regConfig = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
    $schedTempPath = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.TempStoragePath)) { $regConfig.TempStoragePath } else { '' }
    $schedPkgPath = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.PackageStoragePath)) { $regConfig.PackageStoragePath } else { '' }

    # ConfigMgr settings
    $schedCM = @{
        SiteServer = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.SiteServer)) { $regConfig.SiteServer } else { '' }
        SiteCode = if ($global:SiteCode) { $global:SiteCode } else { '' }
        DistributionPointGroups = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.SelectedDPGroups)) { @($regConfig.SelectedDPGroups -split '\|') } else { @() }
        DistributionPoints = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.SelectedDPs)) { @($regConfig.SelectedDPs -split '\|') } else { @() }
        DistributionPriority = if ($null -ne $cmb_DistPriority -and $null -ne $cmb_DistPriority.SelectedItem) { $cmb_DistPriority.SelectedItem.Content } else { 'Normal' }
    }

    # Intune credentials for unattended auth
    $schedIntune = @{
        TenantId  = if ($schedPlatform -eq 'Intune') { $schedTenantId } else { '' }
        AppId     = if ($schedPlatform -eq 'Intune') { $schedAppId } else { '' }
        AppSecret = if ($schedPlatform -eq 'Intune') { $schedSecret } else { '' }
    }

    try {
        Export-DATBuildConfig -ConfigPath $configPath -Platform $schedPlatform -OS $schedOS -Architecture $schedArch `
            -PackageType $schedPkgType -Models @($schedModels) -TempPath $schedTempPath -PackagePath $schedPkgPath `
            -DisableToast $schedDisableToast -ToastTimeoutAction $schedTimeoutAction -MaxDeferrals $schedMaxDeferrals `
            -TeamsWebhookUrl $schedTeamsUrl -TeamsNotificationsEnabled $schedTeamsEnabled -ConfigMgr $schedCM `
            -Intune $schedIntune
    } catch {
        Show-DATInfoDialog -Title 'Schedule Error' `
            -Message "Failed to export build config:`n`n$($_.Exception.Message)" `
            -Type Error
        return
    }

    $regParams = @{
        ConfigPath      = $configPath
        ScriptDirectory = $global:ScriptDirectory
        Frequency       = if ($frequency -eq 'Once Off') { 'Once' } else { $frequency }
        Time            = $time
    }
    if ($frequency -eq 'Weekly') {
        $regParams['DayOfWeek'] = $cmb_ScheduleDay.SelectedItem.Content
    }

    try {
        $result = Register-DATScheduledBuild @regParams
        Write-DATActivityLog "Scheduled build registered: $($result.Frequency) at $($result.Time)" -Level Info
        $overlay_Schedule.Visibility = 'Collapsed'
        $txt_Status.Text = "Scheduled build saved: $frequency at $time"
        $dayInfo = if ($frequency -eq 'Weekly') { " on $($cmb_ScheduleDay.SelectedItem.Content)" } else { '' }
        $onceNote = if ($frequency -eq 'Once Off') { "`n`nThis is a one-time build. The scheduled task will automatically remove itself after completion." } else { '' }
        Show-DATInfoDialog -Title "Schedule Saved" `
            -Message "Your $($frequency.ToLower()) build has been scheduled$dayInfo at $time.`n`nThe task will run under SYSTEM in the '\Driver Automation Tool\' task folder.$onceNote" `
            -Type Success
    } catch {
        Show-DATInfoDialog -Title 'Schedule Error' `
            -Message "Failed to register scheduled task:`n`n$($_.Exception.Message)" `
            -Type Error
    }
})

$btn_ScheduleRemove.Add_Click({
    try {
        Unregister-DATScheduledBuild
        Write-DATActivityLog "Scheduled build removed" -Level Info
        $overlay_Schedule.Visibility = 'Collapsed'
        $txt_Status.Text = "Scheduled build removed."
    } catch {
        Show-DATInfoDialog -Title 'Schedule Error' `
            -Message "Failed to remove scheduled task:`n`n$($_.Exception.Message)" `
            -Type Error
    }
})

# Purge Downloads handler
$btn_PurgeDownloads.Add_Click({
    $tempPath = $txt_TempStorage.Text
    if ([string]::IsNullOrWhiteSpace($tempPath) -or -not (Test-Path $tempPath)) {
        $txt_PurgeStatus.Text = "Temporary storage path not set or does not exist."
        $txt_PurgeStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
        return
    }

    $confirmed = Show-DATConfirmDialog `
        -Title "Purge Downloads" `
        -Message "This will permanently delete all downloaded and extracted driver packages from:`n`n$tempPath`n`nPackaged output will not be affected." `
        -Icon ([char]0xE74D)

    if (-not $confirmed) { return }

    $btn_PurgeDownloads.IsEnabled = $false
    $txt_PurgeStatus.Text = "Purging downloads..."
    $txt_PurgeStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusInfo']))
    Write-DATActivityLog "Purging downloads from $tempPath..." -Level Info

    try {
        $items = Get-ChildItem -Path $tempPath -Force -ErrorAction SilentlyContinue
        $removedCount = 0
        foreach ($item in $items) {
            try {
                Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                $removedCount++
            } catch {
                Write-DATActivityLog "Failed to remove: $($item.Name) — $($_.Exception.Message)" -Level Warn
            }
        }

        $freedMB = 0
        $txt_PurgeStatus.Text = "Purge complete — $removedCount items removed."
        $txt_PurgeStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusSuccess']))
        Write-DATActivityLog "Purge complete: $removedCount items removed from $tempPath" -Level Success
    } catch {
        $txt_PurgeStatus.Text = "Purge failed: $($_.Exception.Message)"
        $txt_PurgeStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
        Write-DATActivityLog "Purge failed: $($_.Exception.Message)" -Level Error
    }
    $btn_PurgeDownloads.IsEnabled = $true
})

# Proxy Configuration handlers
$cmb_ProxyMode.Add_SelectionChanged({
    $mode = $cmb_ProxyMode.SelectedItem.Content
    $panel_ProxyManual.Visibility = if ($mode -eq 'Manual') { 'Visible' } else { 'Collapsed' }

    $regMode = switch ($mode) {
        'Manual'   { 'Manual' }
        'No Proxy' { 'None' }
        default    { 'System' }
    }
    Set-DATRegistryValue -Name 'ProxyMode' -Value $regMode -Type String
    Write-DATActivityLog "Proxy mode set to $regMode" -Level Info
})

$txt_ProxyServer.Add_LostFocus({
    $val = $txt_ProxyServer.Text.Trim()
    if (-not [string]::IsNullOrEmpty($val)) {
        Set-DATRegistryValue -Name 'ProxyServer' -Value $val -Type String
        Write-DATActivityLog "Proxy server set to $val" -Level Info
    }
})

$txt_ProxyBypass.Add_LostFocus({
    $val = $txt_ProxyBypass.Text.Trim()
    if (-not [string]::IsNullOrEmpty($val)) {
        Set-DATRegistryValue -Name 'ProxyBypassList' -Value $val -Type String
    }
})

$txt_ProxyUsername.Add_LostFocus({
    $val = $txt_ProxyUsername.Text.Trim()
    if (-not [string]::IsNullOrEmpty($val)) {
        Set-DATRegistryValue -Name 'ProxyUsername' -Value $val -Type String
    }
})

$pwd_ProxyPassword.Add_LostFocus({
    $val = $pwd_ProxyPassword.Password
    if (-not [string]::IsNullOrEmpty($val)) {
        $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($val))
        Set-DATRegistryValue -Name 'ProxyPassword' -Value $encoded -Type String
    }
})

$btn_TestProxy.Add_Click({
    $txt_ProxyStatus.Text = "Testing connection..."
    $txt_ProxyStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusInfo']))
    $txt_ProxyStatus.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)

    $result = Test-DATProxyConnection
    if ($result.Success) {
        $txt_ProxyStatus.Text = "Connection successful"
        $txt_ProxyStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusSuccess']))
        Write-DATActivityLog "Proxy test: Connection successful" -Level Success
    } else {
        $txt_ProxyStatus.Text = "Failed: $($result.Message)"
        $txt_ProxyStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
        Write-DATActivityLog "Proxy test failed: $($result.Message)" -Level Error
    }
})

#endregion Common Settings

#region WIM Packaging Options

# WIM Engine selection
$cmb_WimEngine = $Window.FindName('cmb_WimEngine')
$cmbi_Wimlib = $Window.FindName('cmbi_Wimlib')
$cmbi_7Zip = $Window.FindName('cmbi_7Zip')
$txt_WimlibStatusIcon = $Window.FindName('txt_WimlibStatusIcon')
$txt_WimlibStatus = $Window.FindName('txt_WimlibStatus')
$txt_7ZipStatusIcon = $Window.FindName('txt_7ZipStatusIcon')
$txt_7ZipStatus = $Window.FindName('txt_7ZipStatus')
$link_WimlibDownload = $Window.FindName('link_WimlibDownload')
$link_7ZipDownload = $Window.FindName('link_7ZipDownload')

$link_WimlibDownload.Add_RequestNavigate({
    param($s, $e)
    Start-Process $e.Uri.AbsoluteUri
    $e.Handled = $true
})

$link_7ZipDownload.Add_RequestNavigate({
    param($s, $e)
    Start-Process $e.Uri.AbsoluteUri
    $e.Handled = $true
})

# wimlib status check — look for wimlib-imagex.exe in Tools\Wimlib
$wimlibPath = $null
$wimlibDir = Join-Path $global:ToolsDirectory 'Wimlib'
if (Test-Path $wimlibDir) {
    $wimlibPath = Get-ChildItem -Path $wimlibDir -Filter "wimlib-imagex.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not [string]::IsNullOrEmpty($wimlibPath) -and (Test-Path $wimlibPath)) {
    # Unblock wimlib executables and DLLs to prevent Windows blocking downloaded files
    Get-ChildItem -Path $wimlibDir -Include '*.exe','*.dll' -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object { Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue }
    try {
        $wimlibVersionOutput = & $wimlibPath --version 2>&1 | Select-Object -First 1
        $wimlibVersion = if ($wimlibVersionOutput -match 'v?(\d+\.\d+\.\d+)') { $Matches[1] } else { 'unknown' }
    } catch {
        $wimlibVersion = 'unknown'
    }
    $txt_WimlibStatusIcon.Text = [string][char]0xE930
    $txt_WimlibStatusIcon.Foreground = $Window.FindResource('StatusSuccess')
    $txt_WimlibStatus.Text = "Found — wimlib-imagex v$wimlibVersion"
    $txt_WimlibStatus.Foreground = $Window.FindResource('StatusSuccess')
    $cmbi_Wimlib.IsEnabled = $true
    Write-DATActivityLog "wimlib: v$wimlibVersion at $wimlibPath" -Level Info
} else {
    $txt_WimlibStatusIcon.Text = [string][char]0xE946
    $txt_WimlibStatusIcon.Foreground = $Window.FindResource('InputPlaceholder')
    $txt_WimlibStatus.Text = "Not found — place wimlib-imagex.exe in Tools\Wimlib\"
    $txt_WimlibStatus.Foreground = $Window.FindResource('InputPlaceholder')
    # Disable the wimlib option if not available
    $cmbi_Wimlib.IsEnabled = $false
    # Force selection back to DISM if wimlib was previously selected but is now missing
    $cmb_WimEngine.SelectedIndex = 0
}

# 7-Zip status check — look for 7z.exe in standard install paths or PATH
$7zipPath = $null
foreach ($candidate in @(
    (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
    (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'),
    (Get-Command '7z.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
)) {
    if (-not [string]::IsNullOrEmpty($candidate) -and (Test-Path $candidate)) {
        $7zipPath = $candidate
        break
    }
}
if (-not [string]::IsNullOrEmpty($7zipPath)) {
    try {
        $7zipVersionOutput = & $7zipPath 2>&1 | Select-Object -First 2 | Out-String
        $7zipVersion = if ($7zipVersionOutput -match '(\d+\.\d+)') { $Matches[1] } else { 'unknown' }
    } catch {
        $7zipVersion = 'unknown'
    }
    $txt_7ZipStatusIcon.Text = [string][char]0xE930
    $txt_7ZipStatusIcon.Foreground = $Window.FindResource('StatusSuccess')
    $txt_7ZipStatus.Text = "Found — 7-Zip v$7zipVersion"
    $txt_7ZipStatus.Foreground = $Window.FindResource('StatusSuccess')
    $cmbi_7Zip.IsEnabled = $true
    Write-DATActivityLog "7-Zip: v$7zipVersion at $7zipPath" -Level Info
} else {
    $txt_7ZipStatusIcon.Text = [string][char]0xE946
    $txt_7ZipStatusIcon.Foreground = $Window.FindResource('InputPlaceholder')
    $txt_7ZipStatus.Text = "Not found — install from 7-zip.org"
    $txt_7ZipStatus.Foreground = $Window.FindResource('InputPlaceholder')
    $cmbi_7Zip.IsEnabled = $false
    # Force selection back to DISM if 7-Zip was previously selected but is now missing
    $savedEngine = (Get-ItemProperty -Path $global:RegPath -Name 'WimEngine' -ErrorAction SilentlyContinue).WimEngine
    if ($savedEngine -eq '7zip') { $cmb_WimEngine.SelectedIndex = 0 }
}

$cmb_WimEngine.Add_SelectionChanged({
    $selected = $cmb_WimEngine.SelectedItem
    if ($selected) {
        $val = switch ($selected.Content) {
            'wimlib (Multi-threaded)' { 'wimlib' }
            '7-Zip'                   { '7zip' }
            default                   { 'dism' }
        }
        Set-DATRegistryValue -Name 'WimEngine' -Value $val -Type String
        # Update compression description to match selected engine
        $txt_CompressionDescription.Text = switch ($val) {
            '7zip'  { 'Controls compression when creating WIM packages. Fast (-mx=1) is recommended for most scenarios. Maximum (-mx=9) produces smaller files but is significantly slower.' }
            'wimlib' { 'Controls compression when creating WIM packages. Fast (XPRESS) is recommended for most scenarios. Maximum (LZX) produces smaller files but is significantly slower.' }
            default  { 'Controls compression when creating WIM packages. Fast (XPRESS) is recommended for most scenarios. Maximum (LZX) produces smaller files but is significantly slower.' }
        }
    }
})

# WIM Compression Level
$txt_CompressionDescription = $Window.FindName('txt_CompressionDescription')
$cmb_DismCompression = $Window.FindName('cmb_DismCompression')
$cmb_DismCompression.Add_SelectionChanged({
    $selected = $cmb_DismCompression.SelectedItem
    if ($selected) {
        $val = switch ($selected.Content) {
            'Fast (Recommended)' { 'fast' }
            'Maximum'            { 'max' }
            'None'               { 'none' }
            default              { 'fast' }
        }
        Set-DATRegistryValue -Name 'DismCompression' -Value $val -Type String
    }
})

#endregion WIM Packaging Options

#region External Utilities & Modules

$txt_HpcmslStatusIcon = $Window.FindName('txt_HpcmslStatusIcon')
$txt_HpcmslStatus = $Window.FindName('txt_HpcmslStatus')
$btn_InstallHpcmsl = $Window.FindName('btn_InstallHpcmsl')
$txt_CurlStatusIcon = $Window.FindName('txt_CurlStatusIcon')
$txt_CurlStatus = $Window.FindName('txt_CurlStatus')
$link_CurlDownload = $Window.FindName('link_CurlDownload')
$cmb_CurlRunMode = $Window.FindName('cmb_CurlRunMode')
$cmb_CurlSource = $Window.FindName('cmb_CurlSource')
$panel_CurlThirdParty = $Window.FindName('panel_CurlThirdParty')

$link_CurlDownload.Add_RequestNavigate({
    param($s, $e)
    Start-Process $e.Uri.AbsoluteUri
    $e.Handled = $true
})

# HP CMSL status check
function Update-DATHpcmslStatus {
    $hpcmslModule = Get-Module -ListAvailable -Name HPCMSL -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $hpcmslModule) {
        $txt_HpcmslStatusIcon.Text = [string][char]0xE930
        $txt_HpcmslStatusIcon.Foreground = $Window.FindResource('StatusSuccess')
        $txt_HpcmslStatus.Text = "Installed — Version $($hpcmslModule.Version)"
        $txt_HpcmslStatus.Foreground = $Window.FindResource('StatusSuccess')
        $btn_InstallHpcmsl.Visibility = 'Collapsed'

        # Re-enable HP in OEM selection
        $script:HPCMSLAvailable = $true
        if ($null -ne $script:OEMCheckboxes -and $script:OEMCheckboxes.ContainsKey('HP')) {
            $script:OEMCheckboxes['HP'].IsEnabled = $true
            $script:OEMCheckboxes['HP'].Content = 'HP'
            $script:OEMCheckboxes['HP'].ToolTip = $null
            Update-DATOEMDisplayText
        }
    } else {
        $txt_HpcmslStatusIcon.Text = [string][char]0xE7BA
        $txt_HpcmslStatusIcon.Foreground = $Window.FindResource('StatusWarning')
        $txt_HpcmslStatus.Text = "Not installed"
        $txt_HpcmslStatus.Foreground = $Window.FindResource('StatusWarning')
        $btn_InstallHpcmsl.Visibility = 'Visible'
    }
}

Update-DATHpcmslStatus

# Install HPCMSL button handler
$btn_InstallHpcmsl.Add_Click({
    $btn_InstallHpcmsl.IsEnabled = $false
    $txt_HpcmslStatus.Text = "Installing HPCMSL module..."
    $txt_HpcmslStatusIcon.Text = [string][char]0xE946
    $txt_HpcmslStatusIcon.Foreground = $Window.FindResource('InputPlaceholder')
    $txt_HpcmslStatus.Foreground = $Window.FindResource('InputPlaceholder')
    # Determine install scope -- prefer AllUsers for headless/scheduled task compatibility
    $installScope = 'AllUsers'
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        $installScope = 'CurrentUser'
    }
    Write-DATActivityLog "Installing HPCMSL module from PSGallery (Scope: $installScope)..." -Level Info
    Write-DATLogEntry -Value "[HP CMSL] Installing HPCMSL module from PSGallery (Scope: $installScope)..." -Severity 1

    $script:hpcmslInstallJob = [PowerShell]::Create()
    $script:hpcmslInstallJob.AddScript({
        param([string]$Scope)

        # Ensure PowerShellGet is new enough to install from PSGallery reliably
        $psGetVer = (Get-Module -ListAvailable -Name PowerShellGet -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1).Version
        if ($null -eq $psGetVer -or $psGetVer -lt [version]'2.2.5') {
            Write-Verbose "PowerShellGet v$psGetVer is outdated -- upgrading..."
            Install-Module -Name PowerShellGet -Force -AllowClobber -Scope $Scope -ErrorAction Stop
            Import-Module -Name PowerShellGet -Force -ErrorAction SilentlyContinue
            Write-Verbose "PowerShellGet upgraded successfully"
        }

        Write-Verbose "Checking PSGallery for HPCMSL package..."
        $pkg = Find-Module -Name HPCMSL -Repository PSGallery -ErrorAction Stop
        Write-Verbose "Found HPCMSL v$($pkg.Version) -- downloading and installing..."
        Install-Module -Name HPCMSL -Force -AcceptLicense -Scope $Scope -ErrorAction Stop
        Write-Verbose "Module files installed. Validating import..."
        Import-Module -Name HPCMSL -Force -ErrorAction Stop
        $mod = Get-Module -Name HPCMSL
        Write-Verbose "HPCMSL v$($mod.Version) imported successfully. Cleaning up..."
        Remove-Module -Name HPCMSL -Force -ErrorAction SilentlyContinue
        return $mod.Version.ToString()
    }).AddArgument($installScope)
    $script:hpcmslInstallJob.Streams.Verbose.Add_DataAdded({
        # Cannot write to UI directly from stream event — enqueue for drain
    })
    $script:hpcmslAsyncResult = $script:hpcmslInstallJob.BeginInvoke()

    # Track how many verbose messages we've relayed so far
    $script:hpcmslVerboseIndex = 0

    # Poll for completion via dispatcher timer to avoid blocking the UI
    $script:hpcmslInstallTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:hpcmslInstallTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:hpcmslInstallTimer.Add_Tick({
        # Relay any new verbose messages to the activity log
        $verboseStream = $script:hpcmslInstallJob.Streams.Verbose
        while ($script:hpcmslVerboseIndex -lt $verboseStream.Count) {
            $msg = $verboseStream[$script:hpcmslVerboseIndex].Message
            Write-DATActivityLog "HPCMSL: $msg" -Level Info
            Write-DATLogEntry -Value "[HP CMSL] $msg" -Severity 1
            $txt_HpcmslStatus.Text = $msg
            $script:hpcmslVerboseIndex++
        }

        if ($script:hpcmslAsyncResult.IsCompleted) {
            $script:hpcmslInstallTimer.Stop()
            try {
                $version = $script:hpcmslInstallJob.EndInvoke($script:hpcmslAsyncResult)
                if ($script:hpcmslInstallJob.Streams.Error.Count -gt 0) {
                    throw $script:hpcmslInstallJob.Streams.Error[0].Exception
                }
                Write-DATActivityLog "HPCMSL module installed successfully (v$version)" -Level Success
                Write-DATLogEntry -Value "[HP CMSL] HPCMSL module installed successfully (v$version)" -Severity 1
                Update-DATHpcmslStatus
            } catch {
                $errMsg = $_.Exception.Message
                Write-DATActivityLog "Failed to install HPCMSL: $errMsg" -Level Error
                Write-DATLogEntry -Value "[HP CMSL] Failed to install HPCMSL: $errMsg" -Severity 3
                $txt_HpcmslStatusIcon.Text = [string][char]0xEA39
                $txt_HpcmslStatusIcon.Foreground = $Window.FindResource('StatusError')
                $txt_HpcmslStatus.Text = "Installation failed — $errMsg"
                $txt_HpcmslStatus.Foreground = $Window.FindResource('StatusError')
            } finally {
                $script:hpcmslInstallJob.Dispose()
                $script:hpcmslInstallJob = $null
                $script:hpcmslAsyncResult = $null
                $btn_InstallHpcmsl.IsEnabled = $true
            }
        }
    })
    $script:hpcmslInstallTimer.Start()
})

# CURL status check
$curlPath = $null
if (-not [string]::IsNullOrEmpty($global:ToolsDirectory)) {
    $curlPath = Get-ChildItem -Path $global:ToolsDirectory -Recurse -Filter "Curl.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not [string]::IsNullOrEmpty($curlPath) -and (Test-Path -Path $curlPath)) {
    try {
        $curlVersion = (& $curlPath --version 2>&1 | Select-Object -First 1) -replace '^curl\s+', '' -replace '\s.*', ''
    } catch {
        $curlVersion = 'unknown'
    }

    # Validate Authenticode signature (may fail if file is locked or access denied)
    $curlSig = $null
    try {
        $curlSig = Get-AuthenticodeSignature -FilePath $curlPath -ErrorAction Stop
    } catch {
        Write-DATActivityLog "CURL: Could not check signature — $($_.Exception.Message)" -Level Warn
    }
    $isSigned = $curlSig -and $curlSig.Status -eq 'Valid'
    $isTampered = $curlSig -and $curlSig.Status -eq 'HashMismatch'

    if ($isSigned) {
        $signerName = $curlSig.SignerCertificate.Subject -replace '^CN=|,.*$', ''
        $txt_CurlStatusIcon.Text = [string][char]0xE930
        $txt_CurlStatusIcon.Foreground = $Window.FindResource('StatusSuccess')
        $txt_CurlStatus.Text = "v$curlVersion — Signed by $signerName"
        $txt_CurlStatus.Foreground = $Window.FindResource('StatusSuccess')
        Write-DATActivityLog "CURL: v$curlVersion at $curlPath — Signed ($signerName)" -Level Info
    } elseif ($isTampered) {
        $txt_CurlStatusIcon.Text = [string][char]0xE783
        $txt_CurlStatusIcon.Foreground = $Window.FindResource('StatusError')
        $txt_CurlStatus.Text = "v$curlVersion — BLOCKED: Signature hash mismatch (possibly tampered)"
        $txt_CurlStatus.Foreground = $Window.FindResource('StatusError')
        Write-DATActivityLog "CURL: v$curlVersion at $curlPath — BLOCKED: HashMismatch" -Level Error
    } else {
        # Official curl.exe from curl.se is not Authenticode-signed; this is normal
        $txt_CurlStatusIcon.Text = [string][char]0xE930
        $txt_CurlStatusIcon.Foreground = $Window.FindResource('StatusSuccess')
        $txt_CurlStatus.Text = "v$curlVersion — Installed (unsigned)"
        $txt_CurlStatus.Foreground = $Window.FindResource('StatusSuccess')
        Write-DATActivityLog "CURL: v$curlVersion at $curlPath — Unsigned (official curl.exe is not Authenticode-signed)" -Level Info
    }
} else {
    $txt_CurlStatusIcon.Text = [string][char]0xE946
    $txt_CurlStatusIcon.Foreground = $Window.FindResource('InputPlaceholder')
    $txt_CurlStatus.Text = "Not found — using native .NET download methods"
    $txt_CurlStatus.Foreground = $Window.FindResource('InputPlaceholder')
}

# CURL running mode persistence
$cmb_CurlRunMode.Add_SelectionChanged({
    if ($null -ne $cmb_CurlRunMode.SelectedItem) {
        Set-DATRegistryValue -Name 'CurlRunMode' -Value $cmb_CurlRunMode.SelectedItem.Content -Type String
    }
})

# CURL source persistence + toggle third-party section visibility
$cmb_CurlSource.Add_SelectionChanged({
    if ($null -ne $cmb_CurlSource.SelectedItem) {
        Set-DATRegistryValue -Name 'CurlSource' -Value $cmb_CurlSource.SelectedItem.Content -Type String
        $panel_CurlThirdParty.Visibility = if ($cmb_CurlSource.SelectedItem.Content -eq 'Third Party (Bundled)') { 'Visible' } else { 'Collapsed' }
    }
})

#endregion External Utilities & Modules

#region Custom Driver Pack

# Control references
$txt_CustomMake = $Window.FindName('txt_CustomMake')
$txt_CustomModel = $Window.FindName('txt_CustomModel')
$txt_CustomBaseBoard = $Window.FindName('txt_CustomBaseBoard')
$cmb_CustomMethod = $Window.FindName('cmb_CustomMethod')
$cmb_CustomPlatform = $Window.FindName('cmb_CustomPlatform')
$cmb_CustomOS = $Window.FindName('cmb_CustomOS')
$panel_CustomLocalFolder = $Window.FindName('panel_CustomLocalFolder')
$txt_CustomDriverFolder = $Window.FindName('txt_CustomDriverFolder')
$btn_CustomBrowseFolder = $Window.FindName('btn_CustomBrowseFolder')
$btn_CustomBuild = $Window.FindName('btn_CustomBuild')
$btn_CustomAbort = $Window.FindName('btn_CustomAbort')
$btn_CustomRefreshWMI = $Window.FindName('btn_CustomRefreshWMI')
$txt_CustomStatus = $Window.FindName('txt_CustomStatus')
$panel_CustomBuildProgress = $Window.FindName('panel_CustomBuildProgress')
$panel_CustomStatusCard = $Window.FindName('panel_CustomStatusCard')
$scroll_CustomDriverPack = $Window.FindName('scroll_CustomDriverPack')
$txt_CustomBuildStatus = $Window.FindName('txt_CustomBuildStatus')
$progress_CustomBuild = $Window.FindName('progress_CustomBuild')
$txt_CustomBuildPercent = $Window.FindName('txt_CustomBuildPercent')
$txt_CustomBuildStep = $Window.FindName('txt_CustomBuildStep')
$txt_CustomDriverCount = $Window.FindName('txt_CustomDriverCount')
$txt_CustomPackagePath = $Window.FindName('txt_CustomPackagePath')
$txt_CustomBuildElapsed = $Window.FindName('txt_CustomBuildElapsed')

# Method dropdown — show/hide Local Folder panel and update description
$txt_CustomExportDescription = $Window.FindName('txt_CustomExportDescription')

$cmb_CustomMethod.Add_SelectionChanged({
    if ($cmb_CustomMethod.SelectedItem.Content -eq 'Local Folder') {
        $panel_CustomLocalFolder.Visibility = 'Visible'
        $txt_CustomExportDescription.Text = "Drivers from the selected local folder will be packaged into a WIM for the selected platform. The folder must contain valid INF driver files."
    } else {
        $panel_CustomLocalFolder.Visibility = 'Collapsed'
        $txt_CustomExportDescription.Text = "PNPUtil will export all third-party drivers currently installed on this device. OEM (inbox) drivers from Microsoft are excluded. The exported drivers are then compressed and packaged for the selected platform."
    }
})

# Browse button for Local Folder method
$btn_CustomBrowseFolder.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select a folder containing driver INF files"
    if ($dialog.ShowDialog() -eq 'OK') {
        $txt_CustomDriverFolder.Text = $dialog.SelectedPath
    }
})

function Get-DATLocalDeviceInfo {
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $bb = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop
        $txt_CustomMake.Text = ($cs.Manufacturer -replace '^\s+|\s+$','' -replace '\.$','')
        $txt_CustomModel.Text = ($cs.Model -replace '^\s+|\s+$','' -replace '\.$','')
        $txt_CustomBaseBoard.Text = ($bb.Product -replace '^\s+|\s+$','')
        Write-DATActivityLog "Custom Driver Pack: WMI device info loaded — $($cs.Manufacturer) $($cs.Model) ($($bb.Product))" -Level Info
    } catch {
        Write-DATActivityLog "Custom Driver Pack: Failed to read WMI — $($_.Exception.Message)" -Level Warn
        $txt_CustomStatus.Text = "Could not read device information from WMI."
    }
}

# Auto-populate WMI on first load
$script:CustomDriverPackWMILoaded = $false
$nav_CustomDriverPack = $Window.FindName('nav_CustomDriverPack')
$nav_CustomDriverPack.Add_Click({
    if (-not $script:CustomDriverPackWMILoaded) {
        Get-DATLocalDeviceInfo
        $script:CustomDriverPackWMILoaded = $true
    }
})

# Refresh button
$btn_CustomRefreshWMI.Add_Click({
    Get-DATLocalDeviceInfo
})

# Build process state
$script:CustomBuildRunspace = $null
$script:CustomBuildPS = $null
$script:CustomBuildAsyncResult = $null

$btn_CustomBuild.Add_Click({
    # Validate fields
    $make = $txt_CustomMake.Text.Trim()
    $model = $txt_CustomModel.Text.Trim()
    $baseBoard = $txt_CustomBaseBoard.Text.Trim()
    $method = if ($null -ne $cmb_CustomMethod.SelectedItem) { $cmb_CustomMethod.SelectedItem.Content } else { 'Capture System' }

    if ([string]::IsNullOrEmpty($make) -or [string]::IsNullOrEmpty($model)) {
        $txt_CustomStatus.Text = "Make and Model are required."
        Write-DATActivityLog "Custom Driver Pack: Build blocked — Make or Model is empty" -Level Warn
        return
    }

    # Validate Local Folder method
    $driverFolderPath = ''
    if ($method -eq 'Local Folder') {
        $driverFolderPath = $txt_CustomDriverFolder.Text.Trim()
        if ([string]::IsNullOrEmpty($driverFolderPath) -or -not (Test-Path $driverFolderPath)) {
            $txt_CustomStatus.Text = "Please select a valid driver folder."
            Write-DATActivityLog "Custom Driver Pack: Build blocked — driver folder path is empty or invalid" -Level Warn
            return
        }
        $localInfCount = (Get-ChildItem -Path $driverFolderPath -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue).Count
        if ($localInfCount -eq 0) {
            $txt_CustomStatus.Text = "No INF driver files found in the selected folder."
            Write-DATActivityLog "Custom Driver Pack: Build blocked — no INF files in '$driverFolderPath'" -Level Warn
            return
        }
    }

    # Check EULA
    $eulaCheck = (Get-ItemProperty -Path $global:RegPath -Name "EULAAccepted" -ErrorAction SilentlyContinue).EULAAccepted
    if ($eulaCheck -ne "True") {
        Set-DATActiveView -ViewName 'view_About' -NavButtonName 'nav_About'
        $txt_CustomStatus.Text = "Please accept the EULA to continue."
        Write-DATActivityLog "Custom Driver Pack: Build blocked — EULA not accepted" -Level Warn
        return
    }

    # Guard against concurrent builds
    if ($script:CustomBuildPS -and $script:CustomBuildAsyncResult -and -not $script:CustomBuildAsyncResult.IsCompleted) {
        $txt_CustomStatus.Text = "A custom build is already in progress."
        return
    }

    $platform = if ($null -ne $cmb_CustomPlatform.SelectedItem) { $cmb_CustomPlatform.SelectedItem.Content } else { 'Create WIM Only' }
    $isWimOnly = $platform -eq 'Create WIM Only'

    # For Intune platform, validate authentication
    if ($platform -eq 'Intune') {
        $authStatus = Get-DATIntuneAuthStatus
        if (-not $authStatus.IsAuthenticated) {
            $txt_CustomStatus.Text = "Please authenticate to Intune before building packages."
            $txt_CustomStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
            Write-DATActivityLog "Custom Driver Pack: Build blocked — Intune not authenticated" -Level Warn
            return
        }
    }

    # UI state: building
    $btn_CustomBuild.IsEnabled = $false
    $btn_CustomAbort.IsEnabled = $true
    $totalSteps = if ($isWimOnly) { 2 } else { 3 }
    if ($method -eq 'Local Folder') {
        $txt_CustomStatus.Text = "Packaging drivers from local folder..."
        $txt_CustomBuildStatus.Text = "Scanning driver folder..."
        $txt_CustomBuildStep.Text = "Step 1 of $totalSteps — Scanning local driver folder"
    } else {
        $txt_CustomStatus.Text = "Exporting drivers with PNPUtil..."
        $txt_CustomBuildStatus.Text = "Extracting drivers..."
        $txt_CustomBuildStep.Text = "Step 1 of $totalSteps — Exporting installed third-party drivers via PNPUtil"
    }
    $panel_CustomStatusCard.Visibility = 'Visible'
    $panel_CustomBuildProgress.Visibility = 'Visible'
    $txt_CustomBuildPercent.Text = "0%"
    $progress_CustomBuild.IsIndeterminate = $false
    $progress_CustomBuild.Value = 0
    $txt_CustomDriverCount.Visibility = 'Collapsed'
    $txt_CustomPackagePath.Visibility = 'Collapsed'

    # Scroll to bottom so the Status card is visible
    $scroll_CustomDriverPack.ScrollToEnd()

    # Start elapsed timer
    $script:CustomBuildStartTime = Get-Date
    $txt_CustomBuildElapsed.Text = "00:00:00"
    $txt_CustomBuildElapsed.Visibility = 'Visible'

    Write-DATActivityLog "Custom Driver Pack: Starting build — $make $model ($baseBoard) → $platform [Method: $method]" -Level Info

    # Read paths from registry
    $regConfig = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
    $tempStorage = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.TempStoragePath)) { $regConfig.TempStoragePath } else { Join-Path $global:ScriptDirectory 'Temp' }
    $packageStorage = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.PackageStoragePath)) { $regConfig.PackageStoragePath } else { Join-Path $global:ScriptDirectory 'Packages' }

    # Get OS version from dropdown
    $osLabel = if ($null -ne $cmb_CustomOS.SelectedItem) { $cmb_CustomOS.SelectedItem.Content } else { 'Windows 11 - 24H2' }
    $detectedArch = if ([System.Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }

    # Gather Intune token for Intune platform
    $intuneToken = $null
    if ($platform -eq 'Intune') {
        $coreModule = Get-Module -Name DriverAutomationToolCore
        if ($coreModule) { $intuneToken = & $coreModule { $script:IntuneAuthToken } }
    }

    # Gather ConfigMgr settings
    $siteServer = if ($regConfig) { $regConfig.SiteServer } else { $null }
    $siteCode = $global:SiteCode

    # Read the Disable Toast checkbox state (Intune only)
    $disableToast = ($platform -eq 'Intune') -and ($chk_DisableToastPrompt.IsChecked -eq $true)

    # Read the Debug Package Build state (Intune only)
    $debugBuildPath = if (($platform -eq 'Intune') -and ($chk_DebugPackageBuild.IsChecked -eq $true) -and
        (-not [string]::IsNullOrEmpty($txt_DebugBuildPath.Text))) { $txt_DebugBuildPath.Text } else { $null }

    # Set registry values for progress communication
    Set-DATRegistryValue -Name "CustomBuildPhase" -Value "Extracting" -Type String
    Set-DATRegistryValue -Name "CustomBuildPercent" -Value "0" -Type String
    if ($method -eq 'Local Folder') {
        Set-DATRegistryValue -Name "CustomBuildMessage" -Value "Scanning local driver folder..." -Type String
        Set-DATRegistryValue -Name "CustomBuildStep" -Value "Step 1 of $totalSteps — Scanning local driver folder" -Type String
    } else {
        Set-DATRegistryValue -Name "CustomBuildMessage" -Value "Exporting installed third-party drivers..." -Type String
        Set-DATRegistryValue -Name "CustomBuildStep" -Value "Step 1 of $totalSteps — Exporting installed third-party drivers via PNPUtil" -Type String
    }

    # Launch in background runspace
    $modulePath = Join-Path $global:ScriptDirectory "Modules\DriverAutomationToolCore\DriverAutomationToolCore.psd1"
    $script:CustomBuildRunspace = [runspacefactory]::CreateRunspace()
    $script:CustomBuildRunspace.ApartmentState = 'STA'
    $script:CustomBuildRunspace.Open()
    $script:CustomBuildPS = [powershell]::Create()
    $script:CustomBuildPS.Runspace = $script:CustomBuildRunspace
    [void]$script:CustomBuildPS.AddScript({
        param($ModulePath, $Make, $Model, $BaseBoard, $Platform, $TempStorage, $PackageStorage, $RegPath,
              $OSLabel, $Architecture, $Version, $ScriptDir, $IntuneToken, $SiteServer, $SiteCode, $DisableToast, $TotalSteps,
              $Method, $DriverFolderPath, $DPGroups, $DPs, $DistPriority, $DebugBuildPath, $CustomBrandingPath)

        Import-Module $ModulePath -Force
        $global:ScriptDirectory = $ScriptDir
        $global:RegPath = $RegPath

        function Set-Phase {
            param([string]$Phase, [int]$Percent, [string]$Message, [string]$Step)
            Set-DATRegistryValue -Name "CustomBuildPhase" -Value $Phase -Type String
            Set-DATRegistryValue -Name "CustomBuildPercent" -Value "$Percent" -Type String
            Set-DATRegistryValue -Name "CustomBuildMessage" -Value $Message -Type String
            Set-DATRegistryValue -Name "CustomBuildStep" -Value $Step -Type String
        }

        $wimOnly = $Platform -eq 'Create WIM Only'

        # ══════════════════════════════════════════════════════════════════
        # Custom Driver Pack Build
        # ══════════════════════════════════════════════════════════════════
        Write-DATLogEntry -Value "[Custom Driver Pack] - Build started" -Severity 1
        Write-DATLogEntry -Value "- [Configuration] - Build parameters" -Severity 1
        Write-DATLogEntry -Value "-- Make: $Make" -Severity 1
        Write-DATLogEntry -Value "-- Model: $Model" -Severity 1
        Write-DATLogEntry -Value "-- BaseBoard: $BaseBoard" -Severity 1
        Write-DATLogEntry -Value "-- OS: $OSLabel" -Severity 1
        Write-DATLogEntry -Value "-- Architecture: $Architecture" -Severity 1
        Write-DATLogEntry -Value "-- Platform: $Platform" -Severity 1
        Write-DATLogEntry -Value "-- Method: $Method" -Severity 1
        Write-DATLogEntry -Value "-- Version: $Version" -Severity 1
        if ($Method -eq 'Local Folder') {
            Write-DATLogEntry -Value "-- Driver folder: $DriverFolderPath" -Severity 1
        }
        Write-DATLogEntry -Value "- [Storage] - Path configuration" -Severity 1
        Write-DATLogEntry -Value "-- Temp storage: $TempStorage" -Severity 1
        Write-DATLogEntry -Value "-- Package storage: $PackageStorage" -Severity 1

        # ── Disk space validation (only for Capture System — Local Folder doesn't use temp storage) ──
        if ($Method -ne 'Local Folder') {
            $minTempSpaceGB = 10
            $tempDrive = [System.IO.Path]::GetPathRoot($TempStorage)
            Write-DATLogEntry -Value "[Disk Space] - Pre-flight validation" -Severity 1
            Write-DATLogEntry -Value "- [Temp Drive] - $tempDrive" -Severity 1

            if ($tempDrive -match '^\\\\') {
                Write-DATLogEntry -Value "-- UNC path detected; disk space check skipped" -Severity 1
            } else {
                $tempDriveInfo = [System.IO.DriveInfo]::new($tempDrive)
                $tempFreeGB = [math]::Round($tempDriveInfo.AvailableFreeSpace / 1GB, 2)
                Write-DATLogEntry -Value "-- Free space: $tempFreeGB GB" -Severity 1
                Write-DATLogEntry -Value "-- Required: $minTempSpaceGB GB minimum" -Severity 1

                if ($tempFreeGB -lt $minTempSpaceGB) {
                    $errorMsg = "Insufficient disk space on $tempDrive for driver export. Free: $tempFreeGB GB, Required: $minTempSpaceGB GB minimum."
                    Write-DATLogEntry -Value "[Warning] - $errorMsg" -Severity 3
                    Set-Phase -Phase "Error" -Percent 0 -Message $errorMsg -Step ""
                    return [PSCustomObject]@{
                        Success     = $false
                        Message     = $errorMsg
                        DriverCount = 0
                        PackagePath = ''
                        Version     = $Version
                    }
                }
            }
        }

        # ── Phase 1: Obtain drivers (0–33%) ──
        $cleanupExportDir = $false

        if ($Method -eq 'Local Folder') {
            # ── Local Folder method: use user-specified driver folder directly ──
            Write-DATLogEntry -Value "[Driver Source] - Using local folder: $DriverFolderPath" -Severity 1
            Set-Phase -Phase "Extracting" -Percent 5 -Message "Scanning local driver folder..." `
                      -Step "Step 1 of $TotalSteps — Scanning local driver folder"

            $exportDir = $DriverFolderPath
            $infFiles = Get-ChildItem -Path $exportDir -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue
            $driverCount = if ($infFiles) { $infFiles.Count } else { 0 }

            if ($driverCount -eq 0) {
                Write-DATLogEntry -Value "[Warning] - No INF driver files found in folder: $DriverFolderPath" -Severity 2
                Set-Phase -Phase "Error" -Percent 0 -Message "No INF files found in selected folder. No package created." -Step ""
                return [PSCustomObject]@{
                    Success     = $false
                    Message     = "No INF files found in selected folder. No package created."
                    DriverCount = 0
                    PackagePath = ''
                    Version     = $Version
                }
            }
        } else {
            # ── Capture System method: export via PNPUtil ──
            Write-DATLogEntry -Value "[Driver Export] - Exporting third-party drivers via PNPUtil" -Severity 1
            Set-Phase -Phase "Extracting" -Percent 5 -Message "Exporting drivers via PNPUtil..." `
                      -Step "Step 1 of $TotalSteps — Exporting installed third-party drivers via PNPUtil"

            $exportDir = Join-Path $TempStorage "CustomDriverPack_$($Make)_$($Model)"
            $cleanupExportDir = $true
            Write-DATLogEntry -Value "- [PNPUtil] - Export directory: $exportDir" -Severity 1

            if (Test-Path $exportDir) {
                Write-DATLogEntry -Value "-- Removing previous export directory" -Severity 1
                Remove-Item $exportDir -Recurse -Force
            }
            New-Item -Path $exportDir -ItemType Directory -Force | Out-Null
            Write-DATLogEntry -Value "-- Created export directory" -Severity 1

            Write-DATLogEntry -Value "- [PNPUtil] - Running pnputil.exe /export-driver * `"$exportDir`"" -Severity 1
            $pnpResult = & pnputil.exe /export-driver * $exportDir 2>&1

            # Log PNPUtil output summary
            $pnpLines = @($pnpResult) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            if ($pnpLines.Count -gt 0) {
                Write-DATLogEntry -Value "- [PNPUtil] - Command output ($($pnpLines.Count) lines)" -Severity 1
                $pnpSummary = $pnpLines | Select-Object -Last 5
                foreach ($line in $pnpSummary) {
                    Write-DATLogEntry -Value "-- $($line.ToString().Trim())" -Severity 1
                }
            }

            $infFiles = Get-ChildItem -Path $exportDir -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue
            $driverCount = if ($infFiles) { $infFiles.Count } else { 0 }

            if ($driverCount -eq 0) {
                Write-DATLogEntry -Value "[Warning] - PNPUtil exported 0 drivers — no third-party drivers found" -Severity 2
                Write-DATLogEntry -Value "- Check that third-party drivers are installed on this device" -Severity 2
                Set-Phase -Phase "Error" -Percent 0 -Message "PNPUtil exported 0 drivers. No package created." -Step ""
                Remove-Item $exportDir -Recurse -Force -ErrorAction SilentlyContinue
                return [PSCustomObject]@{
                    Success     = $false
                    Message     = "PNPUtil exported 0 drivers. No package created."
                    DriverCount = 0
                    PackagePath = ''
                    Version     = $Version
                }
            }
        }

        # Summarize drivers by provider
        $driverProviders = $infFiles | ForEach-Object {
            try {
                $content = Get-Content $_.FullName -TotalCount 30 -ErrorAction SilentlyContinue
                $providerLine = $content | Where-Object { $_ -match '^\s*Provider\s*=' } | Select-Object -First 1
                if ($providerLine -match '=\s*[%]?([^%,]+)') { $Matches[1].Trim(' "') } else { 'Unknown' }
            } catch { 'Unknown' }
        } | Group-Object | Sort-Object Count -Descending

        Write-DATLogEntry -Value "- [Driver Summary] - $driverCount drivers found" -Severity 1
        Write-DATLogEntry -Value "- [Driver Summary] - Drivers by provider" -Severity 1
        foreach ($provider in $driverProviders | Select-Object -First 10) {
            Write-DATLogEntry -Value "-- $($provider.Name): $($provider.Count) driver(s)" -Severity 1
        }
        if ($driverProviders.Count -gt 10) {
            Write-DATLogEntry -Value "-- ... and $($driverProviders.Count - 10) more providers" -Severity 1
        }

        $exportSize = [math]::Round(($infFiles | ForEach-Object { $_.Directory } | Select-Object -Unique |
            ForEach-Object { (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum } | Measure-Object -Sum).Sum / 1MB, 2)
        Write-DATLogEntry -Value "-- Total export size: $exportSize MB" -Severity 1

        Set-Phase -Phase "Extracting" -Percent 30 -Message "$driverCount drivers found" `
                  -Step "Step 1 of $TotalSteps — $driverCount drivers ready for packaging"

        # ── Phase 2: Create WIM package (33–66% or 33–100% for WIM-only) ──

        # Validate package storage drive has enough free space for WIM output
        $exportSizeBytes = ($infFiles | ForEach-Object { $_.Directory } | Select-Object -Unique |
            ForEach-Object { (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum } | Measure-Object -Sum).Sum
        $requiredSpaceGB = [math]::Round($exportSizeBytes / 1GB, 2)
        $pkgDrive = [System.IO.Path]::GetPathRoot($PackageStorage)
        Write-DATLogEntry -Value "[Disk Space] - WIM output validation" -Severity 1
        Write-DATLogEntry -Value "- [Package Drive] - $pkgDrive" -Severity 1

        if ($pkgDrive -match '^\\\\') {
            Write-DATLogEntry -Value "-- UNC path detected; disk space check skipped" -Severity 1
        } else {
            $pkgDriveInfo = [System.IO.DriveInfo]::new($pkgDrive)
            $pkgFreeGB = [math]::Round($pkgDriveInfo.AvailableFreeSpace / 1GB, 2)
            Write-DATLogEntry -Value "-- Free space: $pkgFreeGB GB" -Severity 1
            Write-DATLogEntry -Value "-- Export size: $requiredSpaceGB GB (WIM worst-case estimate)" -Severity 1

            if ($pkgFreeGB -lt $requiredSpaceGB) {
                if ($cleanupExportDir) { Remove-Item $exportDir -Recurse -Force -ErrorAction SilentlyContinue }
                $errorMsg = "Insufficient disk space on $pkgDrive for WIM creation. Free: $pkgFreeGB GB, Required: $requiredSpaceGB GB (based on exported driver size)."
                Write-DATLogEntry -Value "[Warning] - $errorMsg" -Severity 3
                Set-Phase -Phase "Error" -Percent 0 -Message $errorMsg -Step ""
                return [PSCustomObject]@{
                    Success     = $false
                    Message     = $errorMsg
                    DriverCount = $driverCount
                    PackagePath = ''
                    Version     = $Version
                }
            }
        }

        Write-DATLogEntry -Value "[WIM Creation] - Creating WIM package" -Severity 1

        # Determine WIM engine preference
        $wimEngine = (Get-ItemProperty -Path $global:RegPath -Name 'WimEngine' -ErrorAction SilentlyContinue).WimEngine
        if ([string]::IsNullOrEmpty($wimEngine) -or $wimEngine -notin @('dism','wimlib')) {
            $wimEngine = 'dism'
        }

        # Validate wimlib availability — fall back to DISM if not found
        $wimlibExe = $null
        if ($wimEngine -eq 'wimlib') {
            $wimlibDir = Join-Path $global:ToolsDirectory 'Wimlib'
            $wimlibExe = Join-Path $wimlibDir 'wimlib-imagex.exe'
            if (-not (Test-Path $wimlibExe)) {
                Write-DATLogEntry -Value "[Warning] - wimlib-imagex.exe not found in $wimlibDir — falling back to DISM" -Severity 2
                $wimEngine = 'dism'
                $wimlibExe = $null
            }
        }

        # Read compression level
        $compressionLevel = (Get-ItemProperty -Path $global:RegPath -Name 'DismCompression' -ErrorAction SilentlyContinue).DismCompression
        if ([string]::IsNullOrEmpty($compressionLevel) -or $compressionLevel -notin @('fast','max','none')) {
            $compressionLevel = 'max'
        }

        Set-Phase -Phase "Packaging" -Percent 35 -Message "Creating WIM package ($wimEngine)..." `
                  -Step "Step 2 of $TotalSteps — Packaging drivers to WIM using $wimEngine"

        $pkgFolder = Join-Path $PackageStorage "$Make\$Model\CustomDriverPack\$OSLabel\$Architecture\$Version"
        Write-DATLogEntry -Value "- [DISM] - Output directory: $pkgFolder" -Severity 1

        if (Test-Path $pkgFolder) {
            Write-DATLogEntry -Value "-- Removing existing package directory" -Severity 1
            Remove-Item $pkgFolder -Recurse -Force
        }
        New-Item -Path $pkgFolder -ItemType Directory -Force | Out-Null
        Write-DATLogEntry -Value "-- Created package directory" -Severity 1

        $WimFile = Join-Path $pkgFolder "DriverPackage.wim"
        $WimDescription = "$Make $Model $OSLabel Driver Package"
        Write-DATLogEntry -Value "- WIM Engine: $wimEngine" -Severity 1
        Write-DATLogEntry -Value "- WIM file: $WimFile" -Severity 1
        Write-DATLogEntry -Value "-- WIM description: $WimDescription" -Severity 1

        if ($wimEngine -eq 'wimlib') {
            # ── wimlib-imagex capture ────────────────────────────────────────────
            $wimlibCompressArg = switch ($compressionLevel) {
                'max'  { 'LZX' }
                'none' { 'none' }
                default { 'XPRESS' }
            }
            $wimlibArgs = "capture `"$exportDir`" `"$WimFile`" `"$WimDescription`" --compress=$wimlibCompressArg --threads=0 --no-acls"
            Write-DATLogEntry -Value "- [wimlib] - Command: $wimlibExe $wimlibArgs" -Severity 1
            Write-DATLogEntry -Value "-- Compression: $wimlibCompressArg (multi-threaded)" -Severity 1
            Set-Phase -Phase "Packaging" -Percent 40 -Message "wimlib creating WIM ($wimlibCompressArg)..." `
                      -Step "Step 2 of $TotalSteps — Packaging drivers to WIM using wimlib"

            # Reset ACLs on exported driver folder to ensure wimlib can read all files
            # Some OEM driver packages (e.g. Dell) extract with restrictive ACLs
            Write-DATLogEntry -Value "-- Resetting file permissions on driver folder..." -Severity 1
            try {
                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                $takeownResult = Start-Process -FilePath "takeown.exe" -ArgumentList "/F `"$exportDir`" /R /D Y" `
                    -NoNewWindow -Wait -PassThru -RedirectStandardOutput ([System.IO.Path]::GetTempFileName()) -ErrorAction SilentlyContinue
                $icaclsResult = Start-Process -FilePath "icacls.exe" -ArgumentList "`"$exportDir`" /grant `"${currentUser}:(OI)(CI)R`" /T /Q /C" `
                    -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
                if ($icaclsResult -and $icaclsResult.ExitCode -ne 0) {
                    Write-DATLogEntry -Value "-- Warning: ACL grant returned exit code $($icaclsResult.ExitCode)" -Severity 2
                }
            } catch {
                Write-DATLogEntry -Value "-- Warning: Permission reset failed: $($_.Exception.Message)" -Severity 2
            }

            $wimlibStdout = Join-Path $TempStorage "DAT_wimlib_stdout.log"
            $wimlibStderr = Join-Path $TempStorage "DAT_wimlib_stderr.log"

            $startTime = Get-Date
            try {
                $wimlibProcess = Start-Process -FilePath $wimlibExe -ArgumentList $wimlibArgs `
                    -NoNewWindow -Wait -PassThru `
                    -RedirectStandardOutput $wimlibStdout -RedirectStandardError $wimlibStderr -ErrorAction Stop
            } catch {
                if ($cleanupExportDir) { Remove-Item $exportDir -Recurse -Force -ErrorAction SilentlyContinue }
                $errorMsg = "Failed to launch wimlib-imagex: $($_.Exception.Message)"
                Write-DATLogEntry -Value "[Warning] - $errorMsg" -Severity 3
                Set-Phase -Phase "Error" -Percent 0 -Message $errorMsg -Step ""
                return [PSCustomObject]@{
                    Success = $false; Message = $errorMsg; DriverCount = $driverCount; PackagePath = ''; Version = $Version
                }
            }
            $totalDismTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds)

            # Log output
            $dismLogTail = ''
            if (Test-Path $wimlibStdout) {
                $stdoutContent = Get-Content $wimlibStdout -ErrorAction SilentlyContinue
                foreach ($line in $stdoutContent) {
                    if (-not [string]::IsNullOrWhiteSpace($line)) {
                        Write-DATLogEntry -Value "- [wimlib] - $line" -Severity 1
                    }
                }
                Remove-Item $wimlibStdout -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $wimlibStderr) {
                $stderrLines = Get-Content $wimlibStderr -ErrorAction SilentlyContinue
                $dismLogTail = ($stderrLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
                foreach ($line in $stderrLines) {
                    if (-not [string]::IsNullOrWhiteSpace($line)) {
                        Write-DATLogEntry -Value "- [wimlib error] - $line" -Severity 2
                    }
                }
                Remove-Item $wimlibStderr -Force -ErrorAction SilentlyContinue
            }

            $effectiveExitCode = $wimlibProcess.ExitCode
            Write-DATLogEntry -Value "- [wimlib] - Process exited with code $effectiveExitCode after ${totalDismTime}s" -Severity 1

        } else {
        # ── External dism.exe /Capture-Image ─────────────────────────────────
        # Run DISM as an external process instead of the in-process New-WindowsImage
        # cmdlet. The cmdlet uses COM interop with dismhost.exe — if the user aborts
        # and dismhost is killed, the shared COM state corrupts the PowerShell process
        # causing a crash. External dism.exe is cleanly killable.
        Write-DATLogEntry -Value "- [DISM] - Using dism.exe /Capture-Image (external process)" -Severity 1

        $compressionType = switch ($compressionLevel) {
            'max'  { 'Max' }
            'none' { 'None' }
            default { 'Fast' }
        }
        Write-DATLogEntry -Value "-- Compression: $compressionType" -Severity 1

        Set-Phase -Phase "Packaging" -Percent 40 -Message "dism.exe creating WIM ($compressionType)..." `
                  -Step "Step 2 of $TotalSteps — Packaging drivers to WIM using DISM"

        # Build batch wrapper — cmd.exe shell-level redirection avoids pipe deadlocks
        # in background runspaces. -WindowStyle Hidden allocates a real console (required
        # by DISM; CreateNoWindow causes DISM to hang with 0 CPU).
        $dismLogFile = Join-Path $TempStorage "DAT_DISM_custom_capture.log"
        $dismBatchFile = Join-Path $TempStorage "DAT_DISM_custom_capture.cmd"
        $dismStdoutFile = Join-Path $TempStorage "DAT_DISM_custom_stdout.log"
        $dismCmd = "`"$env:SystemRoot\System32\dism.exe`" /Capture-Image /ImageFile:`"$WimFile`" /CaptureDir:`"$exportDir`" /Name:`"$WimDescription`" /Description:`"$WimDescription`" /Compress:$compressionType /Verify /LogPath:`"$dismLogFile`" /LogLevel:3"
        Set-Content -Path $dismBatchFile -Value "@echo off`r`n$dismCmd > `"$dismStdoutFile`" 2>&1`r`nexit /b %ERRORLEVEL%" -Encoding ASCII
        Write-DATLogEntry -Value "- [DISM] - Command: $dismCmd" -Severity 1

        $startTime = Get-Date
        $dismLogTail = ''
        $dismProcess = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$dismBatchFile`"" `
            -WindowStyle Hidden -PassThru

        # Wait for completion — poll so the abort signal can be detected
        while (-not $dismProcess.HasExited) {
            Start-Sleep -Seconds 2
        }

        $effectiveExitCode = if ($dismProcess.HasExited) { $dismProcess.ExitCode } else { 1 }

        # DISM can hang after completing — detect via stdout and force-kill
        if (-not $dismProcess.HasExited) {
            $stdoutCheck = if (Test-Path $dismStdoutFile) { Get-Content $dismStdoutFile -Raw -ErrorAction SilentlyContinue } else { '' }
            if ($stdoutCheck -match 'The operation completed successfully') {
                Write-DATLogEntry -Value "- [DISM] - Completed but process hung — force-killing" -Severity 2
                try { $dismProcess.Kill() } catch { Stop-Process -Id $dismProcess.Id -Force -ErrorAction SilentlyContinue }
                $effectiveExitCode = 0
            }
        }

        # Wait for dismhost.exe to release file locks
        Start-Sleep -Seconds 3
        Get-Process -Name 'dismhost' -ErrorAction SilentlyContinue | ForEach-Object {
            Write-DATLogEntry -Value "- [DISM] - Killing lingering dismhost.exe (PID: $($_.Id))" -Severity 2
            try { $_.Kill() } catch { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
        }

        # Clean stale DISM mount registry entries
        $mountKey = 'HKLM:\SOFTWARE\Microsoft\WIMMount\Mounted Images'
        if (Test-Path $mountKey) {
            Get-ChildItem $mountKey -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Log DISM stdout
        if (Test-Path $dismStdoutFile) {
            $stdoutLines = Get-Content $dismStdoutFile -ErrorAction SilentlyContinue
            $dismLogTail = ($stdoutLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -match 'Error|error|failed' }) -join "`n"
            foreach ($line in $stdoutLines) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    Write-DATLogEntry -Value "- [DISM] - $line" -Severity 1
                }
            }
            Remove-Item $dismStdoutFile -Force -ErrorAction SilentlyContinue
        }

        # Clean up batch and log files
        Remove-Item $dismBatchFile -Force -ErrorAction SilentlyContinue
        Remove-Item $dismLogFile -Force -ErrorAction SilentlyContinue

        $totalDismTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
        Write-DATLogEntry -Value "- [DISM] - dism.exe /Capture-Image completed with code $effectiveExitCode after ${totalDismTime}s" -Severity 1
        } # end DISM else block

        if ($effectiveExitCode -ne 0) {
            # Clean up temp export directory on failure
            if ($cleanupExportDir) { Remove-Item $exportDir -Recurse -Force -ErrorAction SilentlyContinue }

            $errorDetail = "WIM creation failed ($wimEngine exit code $effectiveExitCode)"
            if ($effectiveExitCode -eq 740) {
                $errorDetail = "WIM creation requires elevation (Run as Administrator). Exit code 740."
            }
            Write-DATLogEntry -Value "[Warning] - $errorDetail" -Severity 3
            if ($dismLogTail) {
                Write-DATLogEntry -Value "- [$wimEngine Log] - Last entries:" -Severity 3
                foreach ($logLine in ($dismLogTail -split "`n")) {
                    Write-DATLogEntry -Value "-- $logLine" -Severity 3
                }
            }
            if ($dismLogTail) { $errorDetail += "`n$dismLogTail" }
            Set-Phase -Phase "Error" -Percent 0 -Message $errorDetail -Step ""
            return [PSCustomObject]@{
                Success     = $false
                Message     = $errorDetail
                DriverCount = $driverCount
                PackagePath = ''
                Version     = $Version
            }
        }

        # Clean up temp export directory on success
        if ($cleanupExportDir) { Remove-Item $exportDir -Recurse -Force -ErrorAction SilentlyContinue }

        $wimSize = [math]::Round((Get-Item $WimFile).Length / 1MB, 2)
        Write-DATLogEntry -Value "- [$wimEngine] - WIM package created successfully" -Severity 1
        Write-DATLogEntry -Value "-- File: $WimFile" -Severity 1
        Write-DATLogEntry -Value "-- Size: $wimSize MB" -Severity 1
        Write-DATLogEntry -Value "-- Compression: $compressionLevel" -Severity 1
        Write-DATLogEntry -Value "-- Duration: ${totalDismTime}s" -Severity 1
        Write-DATLogEntry -Value "-- Engine: $wimEngine" -Severity 1

        # ── WIM-only mode: done after WIM creation ──
        if ($wimOnly) {
            Write-DATLogEntry -Value "[Custom Driver Pack] - Build complete (WIM Only)" -Severity 1
            Write-DATLogEntry -Value "- [Result] - Summary" -Severity 1
            Write-DATLogEntry -Value "-- Drivers: $driverCount" -Severity 1
            Write-DATLogEntry -Value "-- WIM size: $wimSize MB" -Severity 1
            Write-DATLogEntry -Value "-- Output: $pkgFolder" -Severity 1
            Set-Phase -Phase "Complete" -Percent 100 `
                      -Message "WIM created ($wimSize MB)" `
                      -Step "Step 2 of 2 — WIM package created ($wimSize MB)"

            if ($cleanupExportDir) { Remove-Item $exportDir -Recurse -Force -ErrorAction SilentlyContinue }

            return [PSCustomObject]@{
                Success     = $true
                Message     = "WIM package created successfully."
                DriverCount = $driverCount
                PackagePath = $pkgFolder
                WimPath     = $WimFile
                Version     = $Version
                WimSize     = $wimSize
                Platform    = $Platform
            }
        }

        Set-Phase -Phase "Packaging" -Percent 65 -Message "WIM created ($wimSize MB)" `
                  -Step "Step 2 of 3 — WIM package created ($wimSize MB)"

        # ── Phase 3: Create package in platform (66–100%) ──
        $platformLabel = if ($Platform -eq 'Intune') { 'Intune' } else { 'Configuration Manager' }
        Write-DATLogEntry -Value "[Package Creation] - Creating package in $platformLabel" -Severity 1
        Set-Phase -Phase "Creating" -Percent 70 -Message "Creating package in $platformLabel..." `
                  -Step "Step 3 of 3 — Creating package in $platformLabel"

        $packageResult = $null
        try {
            if ($Platform -eq 'Intune') {
                Write-DATLogEntry -Value "- [Intune] - Uploading driver package" -Severity 1
                Write-DATLogEntry -Value "-- WIM file: $WimFile" -Severity 1
                Write-DATLogEntry -Value "-- Disable toast: $DisableToast" -Severity 1
                $intuneCreateParams = @{
                    OEM                = $Make
                    Model              = $Model
                    Baseboards         = $BaseBoard
                    OS                 = $OSLabel
                    Architecture       = $Architecture
                    WimFilePath        = $WimFile
                    PackageDestination = $PackageStorage
                    IntuneAuthToken    = $IntuneToken
                    DisableToast       = $DisableToast
                }
                if (-not [string]::IsNullOrEmpty($DebugBuildPath)) { $intuneCreateParams['DebugBuildPath'] = $DebugBuildPath }
                if (-not [string]::IsNullOrEmpty($CustomBrandingPath)) { $intuneCreateParams['CustomBrandingPath'] = $CustomBrandingPath }
                $packageResult = Invoke-DATIntunePackageCreation @intuneCreateParams
                Write-DATLogEntry -Value "- [Intune] - Package uploaded successfully" -Severity 1
                Set-Phase -Phase "Complete" -Percent 100 `
                          -Message "Intune package uploaded successfully" `
                          -Step "Step 3 of 3 — Package uploaded to Intune"
            } else {
                # Configuration Manager
                if (-not [string]::IsNullOrEmpty($SiteServer) -and -not [string]::IsNullOrEmpty($SiteCode)) {
                    Write-DATLogEntry -Value "- [ConfigMgr] - Creating package on site server" -Severity 1
                    Write-DATLogEntry -Value "-- Site server: $SiteServer" -Severity 1
                    Write-DATLogEntry -Value "-- Site code: $SiteCode" -Severity 1
                    $cmResult = New-DATConfigMgrPkg -DriverPackage $WimFile -OEM $Make -Model $Model `
                        -OS $OSLabel -Architecture $Architecture -Baseboards $BaseBoard `
                        -PackagePath $PackageStorage -SiteServer $SiteServer `
                        -SiteCode $SiteCode -Version $Version -PackageType 'Drivers' `
                        -DistributionPointGroups $DPGroups -DistributionPoints $DPs -Priority $DistPriority
                    if ($cmResult) {
                        Write-DATLogEntry -Value "- [ConfigMgr] - Package created successfully" -Severity 1
                        Set-Phase -Phase "Complete" -Percent 100 `
                                  -Message "ConfigMgr package created successfully" `
                                  -Step "Step 3 of 3 — Package created in Configuration Manager"
                    } else {
                        Write-DATLogEntry -Value "[Warning] - [ConfigMgr] - Package creation failed" -Severity 2
                        Set-Phase -Phase "Complete" -Percent 100 `
                                  -Message "ConfigMgr package creation failed — check log for details" `
                                  -Step "Step 3 of 3 — Package creation failed"
                    }
                } else {
                    Write-DATLogEntry -Value "[Warning] - ConfigMgr not connected — package saved locally only" -Severity 2
                    Write-DATLogEntry -Value "- Connect to a ConfigMgr site to push the package" -Severity 2
                    # No ConfigMgr connection — save WIM package only
                    Set-Phase -Phase "Complete" -Percent 100 `
                              -Message "WIM package created (ConfigMgr not connected — package saved locally)" `
                              -Step "Step 3 of 3 — Package saved locally (connect to ConfigMgr to push)"
                }
            }
        } catch {
            Write-DATLogEntry -Value "[Warning] - Package creation failed in $platformLabel" -Severity 3
            Write-DATLogEntry -Value "- $($_.Exception.Message)" -Severity 3
            Set-Phase -Phase "Error" -Percent 70 `
                      -Message "Package creation failed: $($_.Exception.Message)" -Step ""
            return [PSCustomObject]@{
                Success     = $false
                Message     = "Package creation in $platformLabel failed: $($_.Exception.Message)"
                DriverCount = $driverCount
                PackagePath = $pkgFolder
                Version     = $Version
            }
        }

        Write-DATLogEntry -Value "[Custom Driver Pack] - Build complete" -Severity 1
        Write-DATLogEntry -Value "- [Result] - Summary" -Severity 1
        Write-DATLogEntry -Value "-- Platform: $platformLabel" -Severity 1
        Write-DATLogEntry -Value "-- Drivers: $driverCount" -Severity 1
        Write-DATLogEntry -Value "-- WIM size: $wimSize MB" -Severity 1
        Write-DATLogEntry -Value "-- Version: $Version" -Severity 1
        Write-DATLogEntry -Value "-- Output: $pkgFolder" -Severity 1

        return [PSCustomObject]@{
            Success     = $true
            Message     = "Custom driver package created successfully."
            DriverCount = $driverCount
            PackagePath = $pkgFolder
            Version     = $Version
            WimSize     = $wimSize
            Platform    = $Platform
        }
    })

    $customVersion = Get-Date -Format "ddMMyyyy"
    [void]$script:CustomBuildPS.AddArgument((Resolve-Path $modulePath).Path)
    [void]$script:CustomBuildPS.AddArgument($make)
    [void]$script:CustomBuildPS.AddArgument($model)
    [void]$script:CustomBuildPS.AddArgument($baseBoard)
    [void]$script:CustomBuildPS.AddArgument($platform)
    [void]$script:CustomBuildPS.AddArgument($tempStorage)
    [void]$script:CustomBuildPS.AddArgument($packageStorage)
    [void]$script:CustomBuildPS.AddArgument($global:RegPath)
    [void]$script:CustomBuildPS.AddArgument($osLabel)
    [void]$script:CustomBuildPS.AddArgument($detectedArch)
    [void]$script:CustomBuildPS.AddArgument($customVersion)
    [void]$script:CustomBuildPS.AddArgument($global:ScriptDirectory)
    [void]$script:CustomBuildPS.AddArgument($intuneToken)
    [void]$script:CustomBuildPS.AddArgument($siteServer)
    [void]$script:CustomBuildPS.AddArgument($siteCode)
    [void]$script:CustomBuildPS.AddArgument($disableToast)
    [void]$script:CustomBuildPS.AddArgument($totalSteps)
    [void]$script:CustomBuildPS.AddArgument($method)
    [void]$script:CustomBuildPS.AddArgument($driverFolderPath)
    # ConfigMgr DP group, individual DP, and priority settings
    $customDPGroups = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.SelectedDPGroups)) { @($regConfig.SelectedDPGroups -split '\|') } else { @() }
    $customDPs = if ($regConfig -and -not [string]::IsNullOrEmpty($regConfig.SelectedDPs)) { @($regConfig.SelectedDPs -split '\|') } else { @() }
    $customDistPriority = if ($null -ne $cmb_DistPriority -and $null -ne $cmb_DistPriority.SelectedItem) { $cmb_DistPriority.SelectedItem.Content } else { 'Normal' }
    [void]$script:CustomBuildPS.AddArgument($customDPGroups)
    [void]$script:CustomBuildPS.AddArgument($customDPs)
    [void]$script:CustomBuildPS.AddArgument($customDistPriority)
    [void]$script:CustomBuildPS.AddArgument($debugBuildPath)
    [void]$script:CustomBuildPS.AddArgument($script:CustomBrandingImagePath)
    $script:CustomBuildAsyncResult = $script:CustomBuildPS.BeginInvoke()

    # Poll registry for progress updates
    $script:CustomBuildTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:CustomBuildTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:CustomBuildTimer.Add_Tick({
        # Guard against disposed-object access after window close (#14)
        if ($script:WindowClosing) { $script:CustomBuildTimer.Stop(); return }

        try {
            $regValues = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
            if ($regValues) {
                $phase = $regValues.CustomBuildPhase
                $pct = 0; $null = [int]::TryParse([string]$regValues.CustomBuildPercent, [ref]$pct)
                $msg = $regValues.CustomBuildMessage
                $stepText = $regValues.CustomBuildStep

                if (-not [string]::IsNullOrEmpty($msg)) {
                    $txt_CustomBuildStatus.Text = $msg
                }
                if (-not [string]::IsNullOrEmpty($stepText)) {
                    $txt_CustomBuildStep.Text = $stepText
                }
                $progress_CustomBuild.Value = $pct
                $txt_CustomBuildPercent.Text = "$pct%"

                $txt_CustomStatus.Text = $msg
            }
        } catch { }

        # Update elapsed time
        if ($script:CustomBuildStartTime) {
            $elapsed = (Get-Date) - $script:CustomBuildStartTime
            $txt_CustomBuildElapsed.Text = "{0:hh\:mm\:ss}" -f $elapsed
        }

        if ($script:CustomBuildAsyncResult.IsCompleted) {
            $script:CustomBuildTimer.Stop()

            try {
                $result = $script:CustomBuildPS.EndInvoke($script:CustomBuildAsyncResult)
                $output = $result | Select-Object -Last 1

                if ($output.Success) {
                    $progress_CustomBuild.Value = 100
                    $txt_CustomBuildPercent.Text = "100%"
                    $txt_CustomBuildStatus.Text = "Complete"
                    $txt_CustomBuildStep.Text = ""
                    $txt_CustomDriverCount.Text = "$($output.DriverCount) drivers exported  ·  WIM: $($output.WimSize) MB  ·  Version: $($output.Version)"
                    $txt_CustomDriverCount.Visibility = 'Visible'
                    if ($output.WimPath) {
                        $txt_CustomPackagePath.Text = "WIM: $($output.WimPath)"
                    } else {
                        $txt_CustomPackagePath.Text = "Package: $($output.PackagePath)"
                    }
                    $txt_CustomPackagePath.Visibility = 'Visible'
                    $txt_CustomStatus.Text = $output.Message
                    $txt_CustomStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.ColorConverter]::ConvertFromString(
                            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusSuccess']))
                    Write-DATActivityLog "Custom Driver Pack: $($output.DriverCount) drivers → $($output.PackagePath) (v$($output.Version), $($output.Platform))" -Level Info
                    Show-DATCustomBuildCompleteDialog -DriverCount $output.DriverCount -WimSize $output.WimSize -PackagePath $output.PackagePath
                } else {
                    $txt_CustomBuildStatus.Text = $output.Message
                    $txt_CustomBuildStep.Text = ""
                    $progress_CustomBuild.Value = 0
                    $txt_CustomBuildPercent.Text = ""
                    $txt_CustomStatus.Text = $output.Message
                    $txt_CustomStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.ColorConverter]::ConvertFromString(
                            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
                    Write-DATActivityLog "Custom Driver Pack: $($output.Message)" -Level Warn
                }
            } catch {
                $txt_CustomBuildStatus.Text = "Build failed: $($_.Exception.Message)"
                $txt_CustomBuildStep.Text = ""
                $progress_CustomBuild.Value = 0
                $txt_CustomBuildPercent.Text = ""
                $txt_CustomStatus.Text = "Build failed."
                $txt_CustomStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString(
                        (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
                Write-DATActivityLog "Custom Driver Pack: Build failed — $($_.Exception.Message)" -Level Error
            }

            $btn_CustomBuild.IsEnabled = $true
            $btn_CustomAbort.IsEnabled = $false
            $script:CustomBuildStartTime = $null

            # Dispose runspace
            $script:CustomBuildPS.Dispose()
            $script:CustomBuildRunspace.Dispose()
            $script:CustomBuildPS = $null
            $script:CustomBuildRunspace = $null
            $script:CustomBuildAsyncResult = $null
        }
    })
    $script:CustomBuildTimer.Start()
})

$btn_CustomAbort.Add_Click({
    $txt_CustomStatus.Text = "Aborting..."
    Write-DATActivityLog "Custom Driver Pack: Build aborted by user" -Level Warn

    if ($script:CustomBuildTimer) { $script:CustomBuildTimer.Stop() }

    # Kill orphaned DISM/dismhost processes spawned by the build runspace
    foreach ($procName in @('dismhost', 'dism')) {
        Get-Process -Name $procName -ErrorAction SilentlyContinue | ForEach-Object {
            Write-DATActivityLog "Killing orphaned $procName process (PID: $($_.Id))" -Level Warn
            try { $_.Kill() } catch { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
        }
    }

    # Clean up DISM mount state left by killed processes.
    # DISM PS cmdlets share in-process COM state with the killed dismhost — they
    # fail with 0x80004005 after a force-kill. Use registry cleanup + external dism.exe.
    Start-Sleep -Seconds 2
    $dismMountKey = 'HKLM:\SOFTWARE\Microsoft\WIMMount\Mounted Images'
    if (Test-Path $dismMountKey) {
        Get-ChildItem $dismMountKey -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    try {
        $dismClean = Start-Process -FilePath "$env:SystemRoot\System32\dism.exe" `
            -ArgumentList '/Cleanup-Wim' -WindowStyle Hidden -PassThru
        $dismClean.WaitForExit(15000)
        if (-not $dismClean.HasExited) { $dismClean.Kill() }
    } catch { }

    if ($script:CustomBuildPS) {
        $script:CustomBuildPS.Stop()
        $script:CustomBuildPS.Dispose()
        $script:CustomBuildPS = $null
    }
    if ($script:CustomBuildRunspace) {
        $script:CustomBuildRunspace.Dispose()
        $script:CustomBuildRunspace = $null
    }
    $script:CustomBuildAsyncResult = $null

    $progress_CustomBuild.Value = 0
    $txt_CustomBuildPercent.Text = ""
    $txt_CustomBuildStatus.Text = "Aborted"
    $txt_CustomBuildStep.Text = ""
    $txt_CustomStatus.Text = "Build aborted."
    $txt_CustomStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
    $btn_CustomBuild.IsEnabled = $true
    $btn_CustomAbort.IsEnabled = $false
})

#endregion Custom Driver Pack

#region Debug Package Build

$chk_DebugPackageBuild = $Window.FindName('chk_DebugPackageBuild')
$txt_DebugBuildState   = $Window.FindName('txt_DebugBuildState')
$panel_DebugBuildPath  = $Window.FindName('panel_DebugBuildPath')
$txt_DebugBuildPath    = $Window.FindName('txt_DebugBuildPath')
$btn_BrowseDebugBuild  = $Window.FindName('btn_BrowseDebugBuild')

$chk_DebugPackageBuild.Add_Checked({
    Set-DATRegistryValue -Name "DebugPackageBuild" -Value 1 -Type DWord
    $txt_DebugBuildState.Text = 'On'
    $txt_DebugBuildState.Foreground = $Window.FindResource('AccentColor')
    $panel_DebugBuildPath.Visibility = 'Visible'
    Write-DATActivityLog "Debug Package Build: Enabled" -Level Info
})
$chk_DebugPackageBuild.Add_Unchecked({
    Set-DATRegistryValue -Name "DebugPackageBuild" -Value 0 -Type DWord
    $txt_DebugBuildState.Text = 'Off'
    $txt_DebugBuildState.Foreground = $Window.FindResource('InputPlaceholder')
    $panel_DebugBuildPath.Visibility = 'Collapsed'
    Write-DATActivityLog "Debug Package Build: Disabled" -Level Info
})

$btn_BrowseDebugBuild.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select Debug Output Path"
    if ($dialog.ShowDialog() -eq 'OK') {
        $txt_DebugBuildPath.Text = $dialog.SelectedPath
        Set-DATRegistryValue -Name "DebugBuildPath" -Value $dialog.SelectedPath -Type String
    }
})

$txt_DebugBuildPath.Add_LostFocus({
    $path = $txt_DebugBuildPath.Text
    if (-not [string]::IsNullOrEmpty($path)) {
        Set-DATRegistryValue -Name "DebugBuildPath" -Value $path -Type String
    }
})

#endregion Debug Package Build

#region Toast Behaviour

$chk_EnableMaxDeferrals.Add_Checked({
    $txt_MaxDeferrals.IsEnabled = $true
    Set-DATRegistryValue -Name "BIOSMaxDeferralsEnabled" -Value 1 -Type DWord
    Write-DATActivityLog "Max deferral enforcement: Enabled" -Level Info
})

$chk_EnableMaxDeferrals.Add_Unchecked({
    $txt_MaxDeferrals.IsEnabled = $false
    Set-DATRegistryValue -Name "BIOSMaxDeferralsEnabled" -Value 0 -Type DWord
    Write-DATActivityLog "Max deferral enforcement: Disabled" -Level Info
})

$txt_MaxDeferrals.Add_LostFocus({
    $val = $txt_MaxDeferrals.Text
    if ($val -match '^\d+$' -and [int]$val -ge 1) {
        Set-DATRegistryValue -Name "BIOSMaxDeferrals" -Value ([int]$val) -Type DWord
    } else {
        $txt_MaxDeferrals.Text = '3'
        Set-DATRegistryValue -Name "BIOSMaxDeferrals" -Value 3 -Type DWord
    }
})

$cmb_BIOSTimeoutAction.Add_SelectionChanged({
    $action = if ($cmb_BIOSTimeoutAction.SelectedIndex -eq 1) { 'InstallNow' } else { 'RemindMeLater' }
    Set-DATRegistryValue -Name "BIOSToastTimeoutAction" -Value $action -Type String
    Write-DATActivityLog "Toast timeout action: $action" -Level Info
})

#endregion Toast Behaviour

#region Package Deployment

$chk_DeployAllDevices = $Window.FindName('chk_DeployAllDevices')
$txt_DeployAllState = $Window.FindName('txt_DeployAllState')
$chk_DeployAllDevices.Add_Checked({
    Set-DATRegistryValue -Name "DeployAllDevices" -Value 1 -Type DWord
    $txt_DeployAllState.Text = 'On'
    $txt_DeployAllState.Foreground = $Window.FindResource('AccentColor')
    Write-DATActivityLog "Package Deployment: Deploy to All Devices enabled" -Level Info
})
$chk_DeployAllDevices.Add_Unchecked({
    Set-DATRegistryValue -Name "DeployAllDevices" -Value 0 -Type DWord
    $txt_DeployAllState.Text = 'Off'
    $txt_DeployAllState.Foreground = $Window.FindResource('InputPlaceholder')
    Write-DATActivityLog "Package Deployment: Deploy to All Devices disabled" -Level Info
})

# Package Upload settings
$cmb_IntuneChunkSize = $Window.FindName('cmb_IntuneChunkSize')
$cmb_IntuneParallelUploads = $Window.FindName('cmb_IntuneParallelUploads')

# HP Concurrent Downloads setting
$cmb_HPConcurrentDownloads = $Window.FindName('cmb_HPConcurrentDownloads')
$cmb_HPConcurrentDownloads.Add_SelectionChanged({
    $selected = $cmb_HPConcurrentDownloads.SelectedItem
    if ($selected) {
        $val = [int]$selected.Tag
        Set-DATRegistryValue -Name "HPConcurrentDownloads" -Value $val -Type DWord
        Write-DATActivityLog "HP concurrent downloads set to $val" -Level Info
    }
})

$cmb_IntuneChunkSize.Add_SelectionChanged({
    $selected = $cmb_IntuneChunkSize.SelectedItem
    if ($selected) {
        $val = [int]$selected.Tag
        Set-DATRegistryValue -Name "IntuneChunkSizeMB" -Value $val -Type DWord
        Write-DATActivityLog "Upload chunk size set to $val MB" -Level Info
    }
})
$cmb_IntuneParallelUploads.Add_SelectionChanged({
    $selected = $cmb_IntuneParallelUploads.SelectedItem
    if ($selected) {
        $val = [int]$selected.Tag
        Set-DATRegistryValue -Name "IntuneParallelUploads" -Value $val -Type DWord
        Write-DATActivityLog "Parallel uploads set to $val" -Level Info
    }
})

#endregion Package Deployment

#region Package Retention

$chk_PackageRetentionEnabled = $Window.FindName('chk_PackageRetentionEnabled')
$txt_PackageRetentionState   = $Window.FindName('txt_PackageRetentionState')
$panel_RetentionCount        = $Window.FindName('panel_RetentionCount')
$cmb_RetentionCount          = $Window.FindName('cmb_RetentionCount')

$chk_PackageRetentionEnabled.Add_Checked({
    Set-DATRegistryValue -Name 'PackageRetentionEnabled' -Value 1 -Type DWord
    $txt_PackageRetentionState.Text       = 'On'
    $txt_PackageRetentionState.Foreground = $Window.FindResource('AccentColor')
    $panel_RetentionCount.Visibility      = 'Visible'
    Write-DATActivityLog 'Package Retention: Auto-cleanup enabled' -Level Info
})
$chk_PackageRetentionEnabled.Add_Unchecked({
    Set-DATRegistryValue -Name 'PackageRetentionEnabled' -Value 0 -Type DWord
    $txt_PackageRetentionState.Text       = 'Off'
    $txt_PackageRetentionState.Foreground = $Window.FindResource('InputPlaceholder')
    $panel_RetentionCount.Visibility      = 'Collapsed'
    Write-DATActivityLog 'Package Retention: Auto-cleanup disabled' -Level Info
})

$cmb_RetentionCount.Add_SelectionChanged({
    $selected = $cmb_RetentionCount.SelectedItem
    if ($selected) {
        $n = [int]$selected.Content
        Set-DATRegistryValue -Name 'PackageRetentionCount' -Value $n -Type DWord
        Write-DATActivityLog "Package Retention: Keep $n previous versions" -Level Info
    }
})

#endregion Package Retention

#region Toast Notification Preview

$img_ToastBanner          = $Window.FindName('img_ToastBanner')
$txt_ToastHeading         = $Window.FindName('txt_ToastHeading')
$txt_ToastBody            = $Window.FindName('txt_ToastBody')
$cmb_ToastPreviewType     = $Window.FindName('cmb_ToastPreviewType')
$panel_ToastUpdateMockup  = $Window.FindName('panel_ToastUpdateMockup')
$panel_ToastStatusMockup  = $Window.FindName('panel_ToastStatusMockup')
$bd_ToastStatusOuter      = $Window.FindName('bd_ToastStatusOuter')
$bd_ToastStatusStrip      = $Window.FindName('bd_ToastStatusStrip')
$bd_ToastStatusIcon       = $Window.FindName('bd_ToastStatusIcon')
$txt_ToastStatusIcon      = $Window.FindName('txt_ToastStatusIcon')
$txt_ToastStatusHeading   = $Window.FindName('txt_ToastStatusHeading')
$txt_ToastStatusBody      = $Window.FindName('txt_ToastStatusBody')

# Load banner image
$script:DefaultBannerPath = Join-Path (Split-Path $UIPath -Parent) 'Branding\DATLogo_Wide.png'
$script:CustomBrandingImagePath = $null

function Set-DATToastBannerImage {
    param([string]$ImagePath)
    if (-not [string]::IsNullOrEmpty($ImagePath) -and (Test-Path $ImagePath)) {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.UriSource = New-Object System.Uri($ImagePath, [System.UriKind]::Absolute)
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.EndInit()
        $bitmap.Freeze()
        $img_ToastBanner.ImageSource = $bitmap
    }
}

# Load default banner
Set-DATToastBannerImage -ImagePath $script:DefaultBannerPath

# Restore persisted custom branding path
$savedBrandingPath = (Get-ItemProperty -Path $global:RegPath -Name 'CustomBrandingPath' -ErrorAction SilentlyContinue).CustomBrandingPath
if (-not [string]::IsNullOrEmpty($savedBrandingPath) -and (Test-Path $savedBrandingPath)) {
    $script:CustomBrandingImagePath = $savedBrandingPath
    $txt_CustomBrandingPath = $Window.FindName('txt_CustomBrandingPath')
    $txt_CustomBrandingPath.Text = $savedBrandingPath
    Set-DATToastBannerImage -ImagePath $savedBrandingPath
    # Show validation
    $panel_BrandingValidation = $Window.FindName('panel_BrandingValidation')
    $txt_BrandingValidationIcon = $Window.FindName('txt_BrandingValidationIcon')
    $txt_BrandingValidationText = $Window.FindName('txt_BrandingValidationText')
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile($savedBrandingPath)
    $w = $img.Width; $h = $img.Height; $img.Dispose()
    $panel_BrandingValidation.Visibility = 'Visible'
    $txt_BrandingValidationIcon.Text = [string][char]0xE73E
    $txt_BrandingValidationIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString('#2ECC40'))
    $txt_BrandingValidationText.Text = "Custom branding active — ${w} x ${h} pixels"
    $txt_BrandingValidationText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString('#2ECC40'))
}

# Custom Branding — Browse
$btn_BrowseCustomBranding = $Window.FindName('btn_BrowseCustomBranding')
$btn_ClearCustomBranding = $Window.FindName('btn_ClearCustomBranding')
$txt_CustomBrandingPath = $Window.FindName('txt_CustomBrandingPath')
$panel_BrandingValidation = $Window.FindName('panel_BrandingValidation')
$txt_BrandingValidationIcon = $Window.FindName('txt_BrandingValidationIcon')
$txt_BrandingValidationText = $Window.FindName('txt_BrandingValidationText')

$btn_BrowseCustomBranding.Add_Click({
    $ofd = [Microsoft.Win32.OpenFileDialog]::new()
    $ofd.Title = "Select custom branding image"
    $ofd.Filter = "PNG Images (*.png)|*.png"
    if ($ofd.ShowDialog() -eq $true) {
        $filePath = $ofd.FileName
        try {
            Add-Type -AssemblyName System.Drawing
            $img = [System.Drawing.Image]::FromFile($filePath)
            $w = $img.Width; $h = $img.Height; $img.Dispose()

            $panel_BrandingValidation.Visibility = 'Visible'
            if ($w -eq 460 -and $h -eq 110) {
                $txt_BrandingValidationIcon.Text = [string][char]0xE73E
                $txt_BrandingValidationIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString('#2ECC40'))
                $txt_BrandingValidationText.Text = "Perfect — ${w} x ${h} pixels (recommended dimensions)"
                $txt_BrandingValidationText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString('#2ECC40'))
            } else {
                $txt_BrandingValidationIcon.Text = [string][char]0xE7BA
                $txt_BrandingValidationIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString('#E8A035'))
                $txt_BrandingValidationText.Text = "Image is ${w} x ${h} — recommended 460 x 110 pixels. It will be stretched to fit."
                $txt_BrandingValidationText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString('#E8A035'))
            }

            $txt_CustomBrandingPath.Text = $filePath
            $script:CustomBrandingImagePath = $filePath
            Set-DATToastBannerImage -ImagePath $filePath
            Set-DATRegistryValue -Name 'CustomBrandingPath' -Value $filePath -Type String
        } catch {
            $panel_BrandingValidation.Visibility = 'Visible'
            $txt_BrandingValidationIcon.Text = [string][char]0xEA39
            $txt_BrandingValidationIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString('#E74C3C'))
            $txt_BrandingValidationText.Text = "Invalid image file: $($_.Exception.Message)"
            $txt_BrandingValidationText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString('#E74C3C'))
        }
    }
})

$btn_ClearCustomBranding.Add_Click({
    $txt_CustomBrandingPath.Text = ''
    $script:CustomBrandingImagePath = $null
    $panel_BrandingValidation.Visibility = 'Collapsed'
    Set-DATToastBannerImage -ImagePath $script:DefaultBannerPath
    # Clear the registry value — write empty string so the next launch restore skips it,
    # then remove the property entirely (Remove-ItemProperty can silently fail depending on permissions)
    Set-DATRegistryValue -Name 'CustomBrandingPath' -Value '' -Type String
    Remove-ItemProperty -Path $global:RegPath -Name 'CustomBrandingPath' -ErrorAction SilentlyContinue
})

# Custom Toast Text — Bind controls and restore from registry
$txt_CustomToastTitle = $Window.FindName('txt_CustomToastTitle')
$txt_CustomToastBody  = $Window.FindName('txt_CustomToastBody')

$savedToastTitle = (Get-ItemProperty -Path $global:RegPath -Name 'CustomToastTitle' -ErrorAction SilentlyContinue).CustomToastTitle
$savedToastBody  = (Get-ItemProperty -Path $global:RegPath -Name 'CustomToastBody'  -ErrorAction SilentlyContinue).CustomToastBody
if (-not [string]::IsNullOrEmpty($savedToastTitle)) { $txt_CustomToastTitle.Text = $savedToastTitle }
if (-not [string]::IsNullOrEmpty($savedToastBody))  { $txt_CustomToastBody.Text  = $savedToastBody  }

$txt_CustomToastTitle.Add_TextChanged({
    $val = $txt_CustomToastTitle.Text.Trim()
    Set-DATRegistryValue -Name 'CustomToastTitle' -Value $val -Type String
    $selectedType = if ($null -ne $cmb_ToastPreviewType.SelectedItem) { $cmb_ToastPreviewType.SelectedItem.Content } else { 'Driver Update' }
    Update-DATToastPreview -Type $selectedType
})

$txt_CustomToastBody.Add_TextChanged({
    $val = $txt_CustomToastBody.Text.Trim()
    Set-DATRegistryValue -Name 'CustomToastBody' -Value $val -Type String
    $selectedType = if ($null -ne $cmb_ToastPreviewType.SelectedItem) { $cmb_ToastPreviewType.SelectedItem.Content } else { 'Driver Update' }
    Update-DATToastPreview -Type $selectedType
})

function Update-DATToastPreview {
    param([string]$Type)

    # Read custom text overrides (apply only to Driver Update and BIOS Update previews)
    $customTitle = $txt_CustomToastTitle.Text.Trim()
    $customBody  = $txt_CustomToastBody.Text.Trim()

    switch ($Type) {
        'BIOS Update' {
            $panel_ToastUpdateMockup.Visibility = 'Visible'
            $panel_ToastStatusMockup.Visibility = 'Collapsed'
            $txt_ToastHeading.Text = if (-not [string]::IsNullOrEmpty($customTitle)) { $customTitle } else { 'BIOS Update Pending' }
            $txt_ToastBody.Text    = if (-not [string]::IsNullOrEmpty($customBody)) { $customBody } else { 'Your device has pending updates which are required for security / stability reasons. Pressing the Update button will trigger a restart of your device. DO NOT power off the device during the update process.' }
        }
        'Successfully Updated' {
            $panel_ToastUpdateMockup.Visibility = 'Collapsed'
            $panel_ToastStatusMockup.Visibility = 'Visible'
            $accentGreen = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#16A34A'))
            $iconBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#052e16'))
            $iconFg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#22C55E'))
            $bd_ToastStatusOuter.BorderBrush      = $accentGreen
            $bd_ToastStatusStrip.Background        = $accentGreen
            $bd_ToastStatusIcon.Background         = $iconBg
            $txt_ToastStatusIcon.Foreground        = $iconFg
            $txt_ToastStatusIcon.Text              = [char]0xE930   # CompletedSolid
            $txt_ToastStatusHeading.Text           = 'Drivers Successfully Updated'
            $txt_ToastStatusBody.Text              = 'Your device drivers have been successfully updated. No restart is required unless indicated by your IT department.'
        }
        'BIOS Prestaged' {
            $panel_ToastUpdateMockup.Visibility = 'Collapsed'
            $panel_ToastStatusMockup.Visibility = 'Visible'
            $accentBlue  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#2563EB'))
            $iconBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#172554'))
            $iconFg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#3B82F6'))
            $bd_ToastStatusOuter.BorderBrush      = $accentBlue
            $bd_ToastStatusStrip.Background        = $accentBlue
            $bd_ToastStatusIcon.Background         = $iconBg
            $txt_ToastStatusIcon.Foreground        = $iconFg
            $txt_ToastStatusIcon.Text              = [char]0xE835   # FirmwareUpdate
            $txt_ToastStatusHeading.Text           = 'BIOS Firmware Prestaged'
            $txt_ToastStatusBody.Text              = 'Your system has a pending BIOS update and will be restarted in 180 seconds. Please save your work. Do NOT power off the device during the update process.'
        }
        'Driver Issues' {
            $panel_ToastUpdateMockup.Visibility = 'Collapsed'
            $panel_ToastStatusMockup.Visibility = 'Visible'
            $accentAmber = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#D97706'))
            $iconBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#451a03'))
            $iconFg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#F59E0B'))
            $bd_ToastStatusOuter.BorderBrush      = $accentAmber
            $bd_ToastStatusStrip.Background        = $accentAmber
            $bd_ToastStatusIcon.Background         = $iconBg
            $txt_ToastStatusIcon.Foreground        = $iconFg
            $txt_ToastStatusIcon.Text              = [char]0xE7BA   # Warning
            $txt_ToastStatusHeading.Text           = 'Driver Update Issues Detected'
            $txt_ToastStatusBody.Text              = 'One or more driver updates encountered errors during installation. Please contact your IT department or check the device logs for details.'
        }
        'BIOS Issues' {
            $panel_ToastUpdateMockup.Visibility = 'Collapsed'
            $panel_ToastStatusMockup.Visibility = 'Visible'
            $accentAmber = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#D97706'))
            $iconBg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#451a03'))
            $iconFg      = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString('#F59E0B'))
            $bd_ToastStatusOuter.BorderBrush      = $accentAmber
            $bd_ToastStatusStrip.Background        = $accentAmber
            $bd_ToastStatusIcon.Background         = $iconBg
            $txt_ToastStatusIcon.Foreground        = $iconFg
            $txt_ToastStatusIcon.Text              = [char]0xE7BA   # Warning
            $txt_ToastStatusHeading.Text           = 'BIOS Update Issues Detected'
            $txt_ToastStatusBody.Text              = 'The BIOS firmware update encountered errors during installation. Please contact your IT department or check the device logs for details.'
        }
        default {
            # Driver Update
            $panel_ToastUpdateMockup.Visibility = 'Visible'
            $panel_ToastStatusMockup.Visibility = 'Collapsed'
            $txt_ToastHeading.Text = if (-not [string]::IsNullOrEmpty($customTitle)) { $customTitle } else { 'Driver Updates Pending' }
            $txt_ToastBody.Text    = if (-not [string]::IsNullOrEmpty($customBody)) { $customBody } else { 'Your device has pending updates which are required for security / stability reasons. Pressing the Update button can result in temporary network or display interruption.' }
        }
    }
}

$cmb_ToastPreviewType.Add_SelectionChanged({
    $selectedType = if ($null -ne $cmb_ToastPreviewType.SelectedItem) { $cmb_ToastPreviewType.SelectedItem.Content } else { 'Driver Update' }
    Update-DATToastPreview -Type $selectedType
})

#endregion Toast Notification Preview

#region Intune Settings

$script:IntuneAppsData = [System.Collections.ObjectModel.ObservableCollection[PSObject]]::new()
$grid_IntuneApps.ItemsSource = $script:IntuneAppsData

# Intune context menu: theme sync + state management
$grid_IntuneApps.ContextMenu.Add_Opened({
    # Sync theme resources into the ContextMenu (separate visual tree)
    $ctxMenu = $grid_IntuneApps.ContextMenu
    $themeDict = Get-DATThemeResourceDictionary -ThemeName $script:CurrentTheme
    $ctxMenu.Resources.MergedDictionaries.Clear()
    $ctxMenu.Resources.MergedDictionaries.Add($themeDict)

    # Set DAT logo on the header
    $headerLogo = $ctxMenu.Items[0].Template.FindName('ctx_IntuneHeaderLogo', $ctxMenu.Items[0])
    if ($null -ne $headerLogo -and $null -ne $script:bitmapImage) {
        $headerLogo.Source = $script:bitmapImage
    }

    # Enable assignment options when authenticated and at least one row is checked or highlighted
    $checkedApps = @($script:IntuneAppsData | Where-Object { $_.Selected -eq $true })
    $hasSelection = ($checkedApps.Count -gt 0) -or ($null -ne $grid_IntuneApps.SelectedItem)
    $canAssign = $hasSelection -and (Test-DATIntuneAuth)
    $ctx_AssignAvailable.IsEnabled = $canAssign
    $ctx_AssignRequired.IsEnabled = $canAssign
})

# --- Assignment progress modal helper ---
function Invoke-DATIntuneAssignmentWithProgress {
    <#
    .SYNOPSIS
        Shows a themed modal with per-app progress while assigning packages in a background runspace.
    #>
    param (
        [array]$Apps,
        [hashtable]$GroupResult,
        [ValidateSet('Available','Required')][string]$Intent
    )

    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])
    $fgBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $mutedBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))

    # Build modal window
    $script:AssignDlg = [System.Windows.Window]::new()
    $script:AssignDlg.WindowStyle = 'None'
    $script:AssignDlg.AllowsTransparency = $true
    $script:AssignDlg.Background = [System.Windows.Media.Brushes]::Transparent
    $script:AssignDlg.WindowStartupLocation = 'CenterOwner'
    $script:AssignDlg.Owner = $Window
    $script:AssignDlg.Width = 540
    $script:AssignDlg.SizeToContent = 'Height'
    $script:AssignDlg.MaxHeight = 520
    $script:AssignDlg.Topmost = $false
    $script:AssignDlg.ResizeMode = 'NoResize'
    $script:AssignDlg.ShowInTaskbar = $false

    $asBorder = [System.Windows.Controls.Border]::new()
    $asBorder.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(250, $bgColor.R, $bgColor.G, $bgColor.B))
    $asBorder.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $asBorder.Padding = [System.Windows.Thickness]::new(28, 24, 28, 24)
    $asBorder.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $asBorder.BorderThickness = [System.Windows.Thickness]::new(1)
    $asShadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $asShadow.BlurRadius = 30; $asShadow.ShadowDepth = 0; $asShadow.Opacity = 0.5
    $asShadow.Color = [System.Windows.Media.Colors]::Black
    $asBorder.Effect = $asShadow

    $asPanel = [System.Windows.Controls.StackPanel]::new()

    # Title row with close button
    $asTitleGrid = [System.Windows.Controls.Grid]::new()
    $atc1 = [System.Windows.Controls.ColumnDefinition]::new(); $atc1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $atc2 = [System.Windows.Controls.ColumnDefinition]::new(); $atc2.Width = [System.Windows.GridLength]::Auto
    $asTitleGrid.ColumnDefinitions.Add($atc1)
    $asTitleGrid.ColumnDefinitions.Add($atc2)

    $asTitle = [System.Windows.Controls.TextBlock]::new()
    $asTitle.FontSize = 15
    $asTitle.FontWeight = [System.Windows.FontWeights]::Bold
    $asTitle.Foreground = $fgBrush
    $asTitle.VerticalAlignment = 'Center'
    $tr1 = [System.Windows.Documents.Run]::new([string][char]0xE72E)
    $tr1.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $tr1.FontSize = 14
    $tr2 = [System.Windows.Documents.Run]::new("  Assigning $Intent")
    $asTitle.Inlines.Add($tr1)
    $asTitle.Inlines.Add($tr2)
    [System.Windows.Controls.Grid]::SetColumn($asTitle, 0)
    $asTitleGrid.Children.Add($asTitle) | Out-Null

    $asCloseBtn = [System.Windows.Controls.Button]::new()
    $asCloseBtn.Content = [string][char]0xE711
    $asCloseBtn.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $asCloseBtn.FontSize = 12
    $asCloseBtn.Foreground = $mutedBrush
    $asCloseBtn.Background = [System.Windows.Media.Brushes]::Transparent
    $asCloseBtn.BorderThickness = [System.Windows.Thickness]::new(0)
    $asCloseBtn.Cursor = [System.Windows.Input.Cursors]::Hand
    $asCloseBtn.ToolTip = 'Close'
    [System.Windows.Controls.Grid]::SetColumn($asCloseBtn, 1)
    $asCloseBtn.Add_Click({ $script:AssignDlg.Close() })
    $asTitleGrid.Children.Add($asCloseBtn) | Out-Null

    $asTitleGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
    $asPanel.Children.Add($asTitleGrid) | Out-Null

    # Subtitle — target group
    $script:AssignDlgSubtitle = [System.Windows.Controls.TextBlock]::new()
    $script:AssignDlgSubtitle.Text = "Target group: $($GroupResult.GroupName)"
    $script:AssignDlgSubtitle.FontSize = 12
    $script:AssignDlgSubtitle.Foreground = $mutedBrush
    $script:AssignDlgSubtitle.TextTrimming = 'CharacterEllipsis'
    $script:AssignDlgSubtitle.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)
    $asPanel.Children.Add($script:AssignDlgSubtitle) | Out-Null

    # Scrollable area for app rows
    $asScroll = [System.Windows.Controls.ScrollViewer]::new()
    $asScroll.VerticalScrollBarVisibility = 'Auto'
    $asScroll.MaxHeight = 320
    $asItemsPanel = [System.Windows.Controls.StackPanel]::new()

    # Create a row for each app with a pending icon
    $script:AssignDlgIcons = @{}
    $script:AssignDlgStatusLabels = @{}
    foreach ($app in $Apps) {
        $arRow = [System.Windows.Controls.Grid]::new()
        $arc1 = [System.Windows.Controls.ColumnDefinition]::new()
        $arc1.Width = [System.Windows.GridLength]::new(26, [System.Windows.GridUnitType]::Pixel)
        $arc2 = [System.Windows.Controls.ColumnDefinition]::new()
        $arc2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $arc3 = [System.Windows.Controls.ColumnDefinition]::new()
        $arc3.Width = [System.Windows.GridLength]::Auto
        $arRow.ColumnDefinitions.Add($arc1)
        $arRow.ColumnDefinitions.Add($arc2)
        $arRow.ColumnDefinitions.Add($arc3)
        $arRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)

        $arIcon = [System.Windows.Controls.TextBlock]::new()
        $arIcon.Text = [string][char]0xE916  # Stopwatch / pending
        $arIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $arIcon.FontSize = 14
        $arIcon.VerticalAlignment = 'Center'
        $arIcon.Foreground = $mutedBrush
        [System.Windows.Controls.Grid]::SetColumn($arIcon, 0)
        $arRow.Children.Add($arIcon) | Out-Null
        $script:AssignDlgIcons[$app.AppId] = $arIcon

        $arName = [System.Windows.Controls.TextBlock]::new()
        $arName.Text = $app.DisplayName
        $arName.FontSize = 13
        $arName.Foreground = $fgBrush
        $arName.VerticalAlignment = 'Center'
        $arName.TextTrimming = 'CharacterEllipsis'
        [System.Windows.Controls.Grid]::SetColumn($arName, 1)
        $arRow.Children.Add($arName) | Out-Null

        $arStatus = [System.Windows.Controls.TextBlock]::new()
        $arStatus.Text = 'Pending'
        $arStatus.FontSize = 11
        $arStatus.Foreground = $mutedBrush
        $arStatus.VerticalAlignment = 'Center'
        $arStatus.Margin = [System.Windows.Thickness]::new(12, 0, 0, 0)
        [System.Windows.Controls.Grid]::SetColumn($arStatus, 2)
        $arRow.Children.Add($arStatus) | Out-Null
        $script:AssignDlgStatusLabels[$app.AppId] = $arStatus

        $asItemsPanel.Children.Add($arRow) | Out-Null
    }

    $asScroll.Content = $asItemsPanel
    $asPanel.Children.Add($asScroll) | Out-Null

    # Summary line (hidden until complete)
    $script:AssignDlgSummary = [System.Windows.Controls.TextBlock]::new()
    $script:AssignDlgSummary.FontSize = 12
    $script:AssignDlgSummary.FontWeight = [System.Windows.FontWeights]::SemiBold
    $script:AssignDlgSummary.Margin = [System.Windows.Thickness]::new(0, 14, 0, 0)
    $script:AssignDlgSummary.Visibility = 'Collapsed'
    $asPanel.Children.Add($script:AssignDlgSummary) | Out-Null

    $asBorder.Child = $asPanel
    $script:AssignDlg.Content = $asBorder

    # Prepare data for the background runspace
    $authStatus = Get-DATIntuneAuthStatus
    $token = $authStatus.Token
    $tokenExpiry = $authStatus.ExpiresOn
    $appList = @($Apps | ForEach-Object { @{ AppId = $_.AppId; DisplayName = $_.DisplayName } })

    $script:AssignState = [hashtable]::Synchronized(@{
        Status    = 'Running'
        Completed = [System.Collections.ArrayList]::new()  # list of @{ AppId; Success; Error }
        Total     = $appList.Count
    })

    $script:AssignPS = [powershell]::Create()
    $script:AssignPS.AddScript({
        param ($ModulePath, $State, $Token, $TokenExpiry, $AppList, $GroupId, $Intent)
        Import-Module $ModulePath -Force
        Set-DATIntuneAuthToken -Token $Token -ExpiresOn $TokenExpiry
        foreach ($app in $AppList) {
            $entry = @{ AppId = $app.AppId; DisplayName = $app.DisplayName; Success = $false; Error = '' }
            try {
                Set-DATIntuneAppAssignment -AppId $app.AppId -GroupId $GroupId -Intent $Intent
                $entry.Success = $true
            } catch {
                $entry.Error = $_.Exception.Message
            }
            [void]$State.Completed.Add($entry)
        }
        $State.Status = 'Complete'
    })
    [void]$script:AssignPS.AddArgument($CoreModulePath)
    [void]$script:AssignPS.AddArgument($script:AssignState)
    [void]$script:AssignPS.AddArgument($token)
    [void]$script:AssignPS.AddArgument($tokenExpiry)
    [void]$script:AssignPS.AddArgument($appList)
    [void]$script:AssignPS.AddArgument($GroupResult.GroupId)
    [void]$script:AssignPS.AddArgument($Intent)
    $script:AssignAsync = $script:AssignPS.BeginInvoke()

    # Poll timer to update icons as each assignment completes
    $script:AssignLastSeen = 0
    $script:AssignTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:AssignTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:AssignTimer.Add_Tick({
        $completed = $script:AssignState.Completed
        $count = $completed.Count
        # Update any newly completed items
        while ($script:AssignLastSeen -lt $count) {
            $entry = $completed[$script:AssignLastSeen]
            $icon = $script:AssignDlgIcons[$entry.AppId]
            $label = $script:AssignDlgStatusLabels[$entry.AppId]
            if ($icon) {
                if ($entry.Success) {
                    $icon.Text = [string][char]0xE73E  # Checkmark
                    $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.ColorConverter]::ConvertFromString('#22C55E'))
                    if ($label) { $label.Text = 'Assigned'; $label.Foreground = $icon.Foreground }
                    Write-DATActivityLog "Assigned '$($entry.DisplayName)' as $Intent to group" -Level Info
                } else {
                    $icon.Text = [string][char]0xE711  # X
                    $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.ColorConverter]::ConvertFromString('#EF4444'))
                    if ($label) { $label.Text = 'Failed'; $label.Foreground = $icon.Foreground }
                    Write-DATActivityLog "Assignment failed for '$($entry.DisplayName)': $($entry.Error)" -Level Error
                }
            }
            $script:AssignLastSeen++
        }

        # Update subtitle with progress counter
        $script:AssignDlgSubtitle.Text = "Target group: $($GroupResult.GroupName)  --  $count / $($script:AssignState.Total)"

        if ($script:AssignState.Status -eq 'Complete') {
            $script:AssignTimer.Stop()
            $successes = @($completed | Where-Object { $_.Success }).Count
            $failures = $script:AssignState.Total - $successes
            if ($failures -eq 0) {
                $script:AssignDlgSummary.Text = [string][char]0xE73E + "  All $successes package(s) assigned successfully."
                $script:AssignDlgSummary.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString('#22C55E'))
            } else {
                $script:AssignDlgSummary.Text = [string][char]0xE7BA + "  $successes assigned, $failures failed."
                $script:AssignDlgSummary.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString('#EF4444'))
            }
            $script:AssignDlgSummary.Visibility = 'Visible'
            try { $script:AssignPS.Dispose() } catch { }
            $script:AssignPS = $null
        }
    })
    $script:AssignTimer.Start()

    # Show modal — blocks until closed; DispatcherTimer fires during modal pump
    $script:AssignDlg.ShowDialog() | Out-Null

    # Cleanup if dialog closed before work finished
    if ($script:AssignTimer) { try { $script:AssignTimer.Stop() } catch { } }
    if ($script:AssignPS) { try { $script:AssignPS.Dispose() } catch { }; $script:AssignPS = $null }
}

# Assign Package — Available
$ctx_AssignAvailable.Add_Click({
    $checkedApps = @($script:IntuneAppsData | Where-Object { $_.Selected -eq $true })
    if ($checkedApps.Count -eq 0) {
        $highlighted = $grid_IntuneApps.SelectedItem
        if ($null -eq $highlighted) { return }
        $checkedApps = @($highlighted)
    }

    $appLabel = if ($checkedApps.Count -eq 1) { $checkedApps[0].DisplayName } else { "$($checkedApps.Count) selected packages" }
    $result = Show-DATEntraGroupSearchDialog -AppName $appLabel -Intent 'Available'
    if ($null -ne $result) {
        Invoke-DATIntuneAssignmentWithProgress -Apps $checkedApps -GroupResult $result -Intent 'Available'
    }
})

# Assign Package — Required
$ctx_AssignRequired.Add_Click({
    $checkedApps = @($script:IntuneAppsData | Where-Object { $_.Selected -eq $true })
    if ($checkedApps.Count -eq 0) {
        $highlighted = $grid_IntuneApps.SelectedItem
        if ($null -eq $highlighted) { return }
        $checkedApps = @($highlighted)
    }

    $appLabel = if ($checkedApps.Count -eq 1) { $checkedApps[0].DisplayName } else { "$($checkedApps.Count) selected packages" }
    $result = Show-DATEntraGroupSearchDialog -AppName $appLabel -Intent 'Required'
    if ($null -ne $result) {
        Invoke-DATIntuneAssignmentWithProgress -Apps $checkedApps -GroupResult $result -Intent 'Required'
    }
})

# Row-click checkbox toggle for IntuneApps grid
$grid_IntuneApps.Add_PreviewMouseLeftButtonDown({
    param($s, $e)
    $dep = $e.OriginalSource
    while ($null -ne $dep -and $dep -isnot [System.Windows.Controls.DataGridRow]) {
        if ($dep -is [System.Windows.Controls.Primitives.DataGridColumnHeader]) { return }
        $dep = [System.Windows.Media.VisualTreeHelper]::GetParent($dep)
    }
    if ($null -ne $dep) {
        $item = $dep.DataContext
        if ($null -ne $item -and $item.PSObject.Properties['Selected']) {
            $item.Selected = -not $item.Selected
        }
    }
})

# Space bar: toggle the currently selected row.
$grid_IntuneApps.Add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -ne [System.Windows.Input.Key]::Space) { return }
    $row = $grid_IntuneApps.ItemContainerGenerator.ContainerFromItem($grid_IntuneApps.SelectedItem)
    if ($null -ne $row) {
        $checkbox = Find-DATVisualChild -Parent $row -TypeName 'CheckBox'
        if ($null -ne $checkbox) {
            $checkbox.IsChecked = -not $checkbox.IsChecked
        }
    }
    $e.Handled = $true
})

# Auth mode toggle - show/hide app credential fields
$cmb_IntuneAuthMode.Add_SelectionChanged({
    if ($cmb_IntuneAuthMode.SelectedIndex -eq 2) {
        # App Registration mode
        $panel_AppCredentials.Visibility = 'Visible'
    } else {
        # Interactive modes (Browser or Device Code)
        $panel_AppCredentials.Visibility = 'Collapsed'
    }
})

# Auth status update helper
function Update-DATIntuneAuthUI {
    $authStatus = Get-DATIntuneAuthStatus
    if ($authStatus.IsAuthenticated) {
        $indicator_IntuneAuth.Fill = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusSuccess']))
        $txt_IntuneAuthLabel.Text = "Connected"
        $txt_IntuneGraphStatus.Text = "Connected to Microsoft Graph — Tenant: $($authStatus.TenantId)"
        $txt_IntuneGraphStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusSuccess']))
        $txt_IntuneGraphStatus.Visibility = 'Visible'
        $txt_IntuneTokenExpiry.Text = "Token expires in $($authStatus.MinutesRemaining) minutes"
        $txt_IntuneTokenExpiry.Visibility = 'Visible'
        $btn_ConnectIntune.Visibility = 'Collapsed'
        $btn_DisconnectIntune.Visibility = 'Visible'
        $btn_VerifyIntunePermissions.Visibility = 'Visible'
        $grid_IntuneApps.IsEnabled = $true
        $btn_RefreshIntuneApps.IsEnabled = $true
        $panel_AuthStatus.Visibility = 'Collapsed'
        $txt_IntunePkgStatus.Visibility = 'Collapsed'
        # Enable Intune known model lookup if toggle is on
        if ($chk_IntuneKnownModels.IsChecked) {
            $btn_IntuneKnownModelLookup.IsEnabled = $true
            # Auto-run the lookup if no results cached yet
            if (-not $script:IntuneKnownMakes -and -not $script:IntuneKnownModels) {
                Invoke-DATIntuneKnownModelLookup
            }
        }
    } else {
        $indicator_IntuneAuth.Fill = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString(
                (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
        $txt_IntuneAuthLabel.Text = "Not Connected"
        $txt_IntuneGraphStatus.Visibility = 'Collapsed'
        $txt_IntuneTokenExpiry.Visibility = 'Collapsed'
        $btn_ConnectIntune.Visibility = 'Visible'
        $btn_DisconnectIntune.Visibility = 'Collapsed'
        $btn_VerifyIntunePermissions.Visibility = 'Collapsed'
        $grid_IntuneApps.IsEnabled = $false
        $btn_RefreshIntuneApps.IsEnabled = $false
        $btn_DeleteIntuneApp.IsEnabled = $false
        $btn_IntuneKnownModelLookup.IsEnabled = $false
        $txt_IntunePkgStatus.Text = 'Not connected to Intune. Please connect first.'
        $txt_IntunePkgStatus.Visibility = 'Visible'
        $script:IntuneAppsData.Clear()
        $panel_IntunePermissions.Visibility = 'Collapsed'
        $panel_PermissionItems.Children.Clear()
    }
}

# Permission status display helper
function Update-DATIntunePermissionUI {
    param ([hashtable]$PermissionResult)

    $panel_PermissionItems.Children.Clear()

    if (-not $PermissionResult -or -not $PermissionResult.Permissions) {
        $panel_IntunePermissions.Visibility = 'Collapsed'
        return
    }

    foreach ($perm in $PermissionResult.Permissions) {
        $row = [System.Windows.Controls.Grid]::new()
        $c1 = [System.Windows.Controls.ColumnDefinition]::new()
        $c1.Width = [System.Windows.GridLength]::new(22, [System.Windows.GridUnitType]::Pixel)
        $c2 = [System.Windows.Controls.ColumnDefinition]::new()
        $c2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $row.ColumnDefinitions.Add($c1)
        $row.ColumnDefinitions.Add($c2)
        $row.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)

        $icon = [System.Windows.Controls.TextBlock]::new()
        $icon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $icon.FontSize = 12
        $icon.VerticalAlignment = 'Center'

        if ($perm.Status -eq 'Granted') {
            $icon.Text = [char]0xE73E  # Checkmark
            $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString('#22C55E'))
        } else {
            $icon.Text = [char]0xE711  # X
            $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString('#EF4444'))
        }
        [System.Windows.Controls.Grid]::SetColumn($icon, 0)
        $row.Children.Add($icon) | Out-Null

        $label = [System.Windows.Controls.TextBlock]::new()
        $label.FontSize = 12
        $label.VerticalAlignment = 'Center'
        $r1 = [System.Windows.Documents.Run]::new($perm.Name)
        $r1.FontWeight = [System.Windows.FontWeights]::SemiBold
        $r1.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString('#F8FAFC'))
        $r2 = [System.Windows.Documents.Run]::new("  —  $($perm.Description)")
        $r2.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString('#94A3B8'))
        $label.Inlines.Add($r1)
        $label.Inlines.Add($r2)
        [System.Windows.Controls.Grid]::SetColumn($label, 1)
        $row.Children.Add($label) | Out-Null

        $panel_PermissionItems.Children.Add($row) | Out-Null
    }

    $panel_IntunePermissions.Visibility = 'Visible'
}

function Invoke-DATIntunePermissionCheckAsync {
    <#
    .SYNOPSIS
        Runs Test-DATIntunePermissions in a background runspace to avoid UI freeze.
    #>
    param (
        [scriptblock]$OnComplete
    )

    $authStatus = Get-DATIntuneAuthStatus
    $token = $authStatus.Token
    $tokenExpiry = $authStatus.ExpiresOn
    $script:PermCheckState = [hashtable]::Synchronized(@{
        Status = 'Running'
        Result = $null
    })

    $script:PermCheckPS = [powershell]::Create()
    $script:PermCheckPS.AddScript({
        param ($CoreModulePath, $State, $Token, $TokenExpiry)
        Import-Module $CoreModulePath -Force
        Set-DATIntuneAuthToken -Token $Token -ExpiresOn $TokenExpiry
        $State.Result = Test-DATIntunePermissions
        $State.Status = 'Complete'
    })
    [void]$script:PermCheckPS.AddArgument($CoreModulePath)
    [void]$script:PermCheckPS.AddArgument($script:PermCheckState)
    [void]$script:PermCheckPS.AddArgument($token)
    [void]$script:PermCheckPS.AddArgument($tokenExpiry)
    $script:PermCheckAsync = $script:PermCheckPS.BeginInvoke()

    $script:PermCheckTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:PermCheckTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $onCompleteCopy = $OnComplete
    $script:PermCheckTimer.Add_Tick({
        if ($script:PermCheckState.Status -eq 'Complete') {
            $script:PermCheckTimer.Stop()
            $permResult = $script:PermCheckState.Result
            Update-DATIntunePermissionUI -PermissionResult $permResult
            if ($onCompleteCopy) { & $onCompleteCopy $permResult }
            $script:PermCheckPS.Dispose()
            $script:PermCheckPS = $null
        }
    })
    $script:PermCheckTimer.Start()
}

# Token expiry monitor timer - checks every 30 seconds
$script:IntuneTokenTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:IntuneTokenTimer.Interval = [TimeSpan]::FromSeconds(30)
$script:IntuneTokenTimer.Add_Tick({
    if (-not (Test-DATIntuneAuth)) {
        # Token expired - attempt silent refresh if a refresh token is available
        $refreshResult = Invoke-DATTokenRefresh
        if ($refreshResult.Success) {
            Write-DATActivityLog "Token refreshed silently" -Level Info
            Update-DATIntuneAuthUI
        } else {
            $script:IntuneTokenTimer.Stop()
            Update-DATIntuneAuthUI
            $txt_IntuneStatus.Text = "Session expired - please re-authenticate."
            $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
            $grid_IntuneApps.IsEnabled = $false
            $btn_RefreshIntuneApps.IsEnabled = $false
            $btn_DeleteIntuneApp.IsEnabled = $false
            Write-DATActivityLog "Intune token expired" -Level Warn
        }
    } else {
        $status = Get-DATIntuneAuthStatus
        $txt_IntuneTokenExpiry.Text = "Token expires in $($status.MinutesRemaining) minutes"
        # Proactive refresh when < 5 minutes remaining
        if ($status.MinutesRemaining -lt 5) {
            $refreshResult = Invoke-DATTokenRefresh
            if ($refreshResult.Success) {
                Write-DATActivityLog "Token refreshed proactively (was expiring in $($status.MinutesRemaining) min)" -Level Info
                Update-DATIntuneAuthUI
            } else {
                $txt_IntuneTokenExpiry.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString(
                        (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
            }
        }
    }
})

# Helper to show "Copied!" feedback on a copy button
function Show-DATCopyFeedback {
    param([System.Windows.Controls.Button]$Button)
    $origBg = $Button.Background
    $Button.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['ButtonSuccess']))
    $Button.ToolTip = "Copied!"
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1.5)
    $savedButton = $Button
    $savedBg = $origBg
    $savedTip = $Button.Tag  # store original tooltip in Tag
    $timer.Add_Tick({
        $savedButton.Background = $savedBg
        $savedButton.ToolTip = $savedTip
        $this.Stop()
    }.GetNewClosure())
    $timer.Start()
}

# Copy device code button - extract code and copy to clipboard with visual feedback
$btn_CopyDeviceCode.Tag = $btn_CopyDeviceCode.ToolTip
$btn_CopyDeviceCode.Add_Click({
    $code = $txt_DeviceCodeInfo.Text
    if (-not [string]::IsNullOrWhiteSpace($code)) {
        try {
            [System.Windows.Clipboard]::SetText($code)
            Show-DATCopyFeedback -Button $btn_CopyDeviceCode
            Write-DATActivityLog "Device code copied to clipboard: $code" -Level Info
        } catch {
            Write-DATActivityLog "Failed to copy device code to clipboard" -Level Warn
        }
    }
})

# Click on device code text to copy
$txt_DeviceCodeInfo.Add_MouseLeftButtonUp({
    $code = $txt_DeviceCodeInfo.Text
    if (-not [string]::IsNullOrWhiteSpace($code)) {
        try {
            [System.Windows.Clipboard]::SetText($code)
            Show-DATCopyFeedback -Button $btn_CopyDeviceCode
            Write-DATActivityLog "Device code copied to clipboard (text click): $code" -Level Info
        } catch {
            Write-DATActivityLog "Failed to copy device code to clipboard" -Level Warn
        }
    }
})

# Copy verification URL button - copy URL to clipboard with visual feedback
$btn_CopyDeviceUrl.Tag = $btn_CopyDeviceUrl.ToolTip
$btn_CopyDeviceUrl.Add_Click({
    $url = $txt_DeviceCodeUrl.Text
    if (-not [string]::IsNullOrWhiteSpace($url)) {
        try {
            [System.Windows.Clipboard]::SetText($url)
            Show-DATCopyFeedback -Button $btn_CopyDeviceUrl
            Write-DATActivityLog "Verification URL copied to clipboard: $url" -Level Info
        } catch {
            Write-DATActivityLog "Failed to copy verification URL to clipboard" -Level Warn
        }
    }
})

# Click on URL text to copy
$txt_DeviceCodeUrl.Add_MouseLeftButtonUp({
    $url = $txt_DeviceCodeUrl.Text
    if (-not [string]::IsNullOrWhiteSpace($url)) {
        try {
            [System.Windows.Clipboard]::SetText($url)
            Show-DATCopyFeedback -Button $btn_CopyDeviceUrl
            Write-DATActivityLog "Verification URL copied to clipboard (text click): $url" -Level Info
        } catch {
            Write-DATActivityLog "Failed to copy verification URL to clipboard" -Level Warn
        }
    }
})

# Auth card collapse/expand toggle
$script:AuthCardExpanded = $true
$btn_ToggleAuthCard.Add_Click({
    if ($script:AuthCardExpanded) {
        $panel_AuthContent.Visibility = 'Collapsed'
        $btn_ToggleAuthCard.Content = [string][char]0xE70E
        $btn_ToggleAuthCard.ToolTip = 'Expand'
        $script:AuthCardExpanded = $false
    } else {
        $panel_AuthContent.Visibility = 'Visible'
        $btn_ToggleAuthCard.Content = [string][char]0xE70D
        $btn_ToggleAuthCard.ToolTip = 'Collapse'
        $script:AuthCardExpanded = $true
    }
})

# Combined filter for Intune apps: package type + search text
function Update-DATIntuneAppFilter {
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($grid_IntuneApps.ItemsSource)
    if ($null -eq $view) { return }

    $pkgType = if ($null -ne $cmb_IntunePkgType.SelectedItem) { $cmb_IntunePkgType.SelectedItem.Content } else { 'Drivers' }
    $searchText = $txt_IntuneAppSearch.Text

    # Build the display name prefix to match: "Drivers -" or "BIOS -"
    $typePrefix = switch ($pkgType) {
        'BIOS Update' { 'BIOS ' }
        default       { 'Drivers ' }
    }

    $view.Filter = [System.Predicate[object]]{
        param($item)
        # Package type filter
        if (-not $item.DisplayName.StartsWith($typePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        # Search text filter
        if (-not [string]::IsNullOrEmpty($searchText)) {
            if ($item.DisplayName -notlike "*$searchText*" -and $item.Publisher -notlike "*$searchText*") { return $false }
        }
        return $true
    }
}

# Intune package type filter
$cmb_IntunePkgType.Add_SelectionChanged({ Update-DATIntuneAppFilter })

# Intune apps search filter
$txt_IntuneAppSearch.Add_TextChanged({ Update-DATIntuneAppFilter })

# Intune Select All / Select None
$btn_IntunePkgSelectAll = $Window.FindName('btn_IntunePkgSelectAll')
$btn_IntunePkgSelectNone = $Window.FindName('btn_IntunePkgSelectNone')
$btn_IntunePkgSelectAll.Add_Click({
    foreach ($item in $script:IntuneAppsData) { $item.Selected = $true }
    $grid_IntuneApps.Items.Refresh()
    Update-DATIntuneDeleteButtonState
})
$btn_IntunePkgSelectNone.Add_Click({
    foreach ($item in $script:IntuneAppsData) { $item.Selected = $false }
    $grid_IntuneApps.Items.Refresh()
    Update-DATIntuneDeleteButtonState
})

# Connect button - initiate auth based on selected mode
$btn_ConnectIntune.Add_Click({
    $btn_ConnectIntune.IsEnabled = $false
    $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusInfo']))

    if ($cmb_IntuneAuthMode.SelectedIndex -eq 0) {
        # --- Interactive (Browser) - Auth Code + PKCE ---
        $txt_IntuneStatus.Text = "Opening browser for sign-in..."
        $panel_AuthStatus.Background = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString("#3B82F6"))
        $dot_AuthStatus.Fill = [System.Windows.Media.Brushes]::White
        $txt_AuthStatusMessage.Text = "Waiting for Browser Sign-In"
        $panel_AuthStatus.Visibility = 'Visible'
        $panel_DeviceCode.Visibility = 'Collapsed'
        Write-DATActivityLog "Initiating browser-based interactive authentication (Auth Code + PKCE)" -Level Info

        # Phase 1 — setup listener + open browser (non-blocking)
        $setupResult = Connect-DATIntuneGraphInteractive

        if (-not $setupResult.Success) {
            $txt_IntuneStatus.Text = "Failed to start browser auth: $($setupResult.Error)"
            $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
            $panel_AuthStatus.Visibility = 'Collapsed'
            $btn_ConnectIntune.IsEnabled = $true
            Write-DATActivityLog "Browser auth setup failed: $($setupResult.Error)" -Level Error
            return
        }

        # Phase 2 — poll for the redirect using a DispatcherTimer
        $script:BrowserAuthPollTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:BrowserAuthPollTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $script:BrowserAuthPollTimer.Add_Tick({
            $pollResult = Complete-DATBrowserAuth

            switch ($pollResult.Status) {
                'Pending' {
                    # Still waiting for browser redirect
                }
                'Success' {
                    $script:BrowserAuthPollTimer.Stop()

                    Update-DATIntuneAuthUI
                    $script:IntuneTokenTimer.Start()
                    Invoke-DATIntuneAppRefresh

                    Invoke-DATIntunePermissionCheckAsync -OnComplete {
                        param ($permResult)
                        if ($permResult.Granted) {
                            Write-DATActivityLog "Browser authentication successful - all permissions granted" -Level Success
                        } elseif ($permResult.Permissions) {
                            $denied = ($permResult.Permissions | Where-Object { $_.Status -ne 'Granted' })
                            $deniedNames = ($denied | ForEach-Object { $_.Name }) -join ', '
                            Write-DATActivityLog "Browser authentication successful but missing permissions: $deniedNames" -Level Warn
                            $txt_IntuneStatus.Text = "Connected - missing permissions: $deniedNames"
                            $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                                [System.Windows.Media.ColorConverter]::ConvertFromString(
                                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
                        } else {
                            Write-DATActivityLog "Browser authentication successful" -Level Success
                        }
                    }

                    $panel_AuthStatus.Background = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.ColorConverter]::ConvertFromString("#22C55E"))
                    $dot_AuthStatus.Fill = [System.Windows.Media.Brushes]::White
                    $txt_AuthStatusMessage.Text = "Authenticated"
                    $btn_ConnectIntune.IsEnabled = $true
                }
                'Failed' {
                    $script:BrowserAuthPollTimer.Stop()
                    $txt_IntuneStatus.Text = "Auth failed: $($pollResult.Error)"
                    $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.ColorConverter]::ConvertFromString(
                            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
                    Write-DATActivityLog "Browser auth failed: $($pollResult.Error)" -Level Error
                    $panel_AuthStatus.Visibility = 'Collapsed'
                    $btn_ConnectIntune.IsEnabled = $true
                }
            }
        })
        $script:BrowserAuthPollTimer.Start()

    } elseif ($cmb_IntuneAuthMode.SelectedIndex -eq 2) {
        # --- App Registration (Client Credentials) ---
        $tenantId = $txt_IntuneTenantId.Text.Trim()
        $appId = $txt_IntuneAppId.Text.Trim()
        $secret = $txt_IntuneClientSecret.Password

        if ([string]::IsNullOrEmpty($tenantId) -or [string]::IsNullOrEmpty($appId) -or [string]::IsNullOrEmpty($secret)) {
            $txt_IntuneStatus.Text = "Please fill in Tenant ID, App ID, and Client Secret."
            $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
            $btn_ConnectIntune.IsEnabled = $true
            return
        }

        $txt_IntuneStatus.Text = "Authenticating with client credentials..."
        Write-DATActivityLog "Authenticating with client credentials for tenant $tenantId" -Level Info

        $result = Connect-DATIntuneGraphClientCredential -TenantId $tenantId -AppId $appId -ClientSecret $secret

        if ($result.Success) {
            Update-DATIntuneAuthUI
            $script:IntuneTokenTimer.Start()
            Invoke-DATIntuneAppRefresh
            $btn_ConnectIntune.IsEnabled = $true

            # Persist credentials — TenantId and AppId as plaintext, ClientSecret DPAPI-encrypted
            Set-DATRegistryValue -Name 'IntuneTenantId' -Value $tenantId -Type String
            Set-DATRegistryValue -Name 'IntuneAppId' -Value $appId -Type String
            Set-DATRegistryValue -Name 'IntuneAuthMode' -Value 2 -Type DWord
            try {
                $secSecret = ConvertTo-SecureString -String $secret -AsPlainText -Force
                $encSecret = ConvertFrom-SecureString -SecureString $secSecret
                Set-DATRegistryValue -Name 'IntuneClientSecret' -Value $encSecret -Type String
                Write-DATActivityLog 'Intune client credentials saved to registry (secret DPAPI-encrypted)' -Level Info
            } catch {
                Write-DATActivityLog "Failed to encrypt client secret: $($_.Exception.Message)" -Level Warn
            }

            # Run permission check in background to avoid UI freeze
            Invoke-DATIntunePermissionCheckAsync -OnComplete {
                param ($permResult)
                if ($permResult.Granted) {
                    Write-DATActivityLog "Client credential auth successful - all permissions granted" -Level Success
                } else {
                    $denied = ($permResult.Permissions | Where-Object { $_.Status -ne 'Granted' })
                    $deniedNames = ($denied | ForEach-Object { $_.Name }) -join ', '
                    Write-DATActivityLog "Client credential auth successful but missing permissions: $deniedNames" -Level Warn
                    $txt_IntuneStatus.Text = "Connected - missing permissions: $deniedNames"
                    $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.ColorConverter]::ConvertFromString(
                            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
                }
            }
        } else {
            $txt_IntuneStatus.Text = "Auth failed: $($result.Error)"
            $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
            Write-DATActivityLog "Client credential auth failed: $($result.Error)" -Level Error
        }
        $btn_ConnectIntune.IsEnabled = $true

    } else {
        # --- Interactive (Device Code Flow) --- (SelectedIndex 1)
        $txt_IntuneStatus.Text = "Requesting device code..."
        # Show orange pill for requesting state
        $panel_AuthStatus.Background = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString("#F59E0B"))
        $dot_AuthStatus.Fill = [System.Windows.Media.Brushes]::White
        $txt_AuthStatusMessage.Text = "Requesting Device Code"
        $panel_AuthStatus.Visibility = 'Visible'
        $panel_DeviceCode.Visibility = 'Collapsed'
        Write-DATActivityLog "Initiating Intune Graph device code authentication" -Level Info

        $dcResult = Connect-DATIntuneGraph

        if (-not $dcResult.Success) {
            $txt_IntuneStatus.Text = "Failed to request device code: $($dcResult.Error)"
            $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
            $panel_AuthStatus.Visibility = 'Collapsed'
            $panel_DeviceCode.Visibility = 'Collapsed'
            $btn_ConnectIntune.IsEnabled = $true
            Write-DATActivityLog "Device code request failed: $($dcResult.Error)" -Level Error
            return
        }

        # Show the device code and verification URL separately
        $txt_DeviceCodeInfo.Text = $dcResult.UserCode
        $txt_DeviceCodeUrl.Text = $dcResult.VerificationUri
        $panel_DeviceCode.Visibility = 'Visible'

        # Copy code to clipboard for convenience
        try { [System.Windows.Clipboard]::SetText($dcResult.UserCode) } catch {}

        Write-DATActivityLog "Device code: $($dcResult.UserCode) - verify at $($dcResult.VerificationUri)" -Level Info

        # Poll for token completion using DispatcherTimer
        $script:AuthPollTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:AuthPollTimer.Interval = [TimeSpan]::FromSeconds(5)
        $script:AuthPollTimer.Add_Tick({
            $pollResult = Complete-DATDeviceCodeAuth

            switch ($pollResult.Status) {
                'Pending' {
                    # Still waiting - do nothing, timer will fire again
                }
                'Success' {
                    $script:AuthPollTimer.Stop()

                    Update-DATIntuneAuthUI
                    $script:IntuneTokenTimer.Start()
                    Invoke-DATIntuneAppRefresh

                    # Check permissions in background to avoid UI freeze
                    Invoke-DATIntunePermissionCheckAsync -OnComplete {
                        param ($permResult)
                        if ($permResult.Granted) {
                            Write-DATActivityLog "Intune authentication successful - all permissions granted" -Level Success
                        } elseif ($permResult.Permissions) {
                            $denied = ($permResult.Permissions | Where-Object { $_.Status -ne 'Granted' })
                            $deniedNames = ($denied | ForEach-Object { $_.Name }) -join ', '
                            Write-DATActivityLog "Intune authentication successful but missing permissions: $deniedNames" -Level Warn
                            $txt_IntuneStatus.Text = "Connected - missing permissions: $deniedNames"
                            $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                                [System.Windows.Media.ColorConverter]::ConvertFromString(
                                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusWarning']))
                        } else {
                            Write-DATActivityLog "Intune authentication successful" -Level Success
                        }
                    }

                    # Change pill to green "Authenticated"
                    $panel_AuthStatus.Background = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.ColorConverter]::ConvertFromString("#22C55E"))
                    $dot_AuthStatus.Fill = [System.Windows.Media.Brushes]::White
                    $txt_AuthStatusMessage.Text = "Authenticated"
                    $panel_DeviceCode.Visibility = 'Collapsed'
                    $btn_ConnectIntune.IsEnabled = $true
                }
                'Failed' {
                    $script:AuthPollTimer.Stop()
                    $txt_IntuneStatus.Text = $pollResult.Error
                    $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.ColorConverter]::ConvertFromString(
                            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
                    Write-DATActivityLog "Intune auth failed: $($pollResult.Error)" -Level Error
                    $panel_AuthStatus.Visibility = 'Collapsed'
                    $panel_DeviceCode.Visibility = 'Collapsed'
                    $btn_ConnectIntune.IsEnabled = $true
                }
            }
        })
        $script:AuthPollTimer.Start()
    }
})

# Disconnect button
$btn_DisconnectIntune.Add_Click({
    Disconnect-DATIntuneGraph
    $script:IntuneTokenTimer.Stop()
    Update-DATIntuneAuthUI
    $panel_AuthStatus.Visibility = 'Collapsed'
    $panel_DeviceCode.Visibility = 'Collapsed'
    $panel_IntunePermissions.Visibility = 'Collapsed'
    $panel_PermissionItems.Children.Clear()
    $txt_IntuneStatus.Text = "Disconnected."
    $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['InputPlaceholder']))
    Write-DATActivityLog "Disconnected from Intune Graph" -Level Info
})

# Verify Permissions -- show modal with required Graph permission states
$btn_VerifyIntunePermissions.Add_Click({
    if (-not (Test-DATIntuneAuth)) {
        $txt_IntuneStatus.Text = 'Please connect before verifying permissions.'
        return
    }

    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])

    # Build modal window
    $script:PermDlg = [System.Windows.Window]::new()
    $script:PermDlg.WindowStyle = 'None'
    $script:PermDlg.AllowsTransparency = $true
    $script:PermDlg.Background = [System.Windows.Media.Brushes]::Transparent
    $script:PermDlg.WindowStartupLocation = 'CenterOwner'
    $script:PermDlg.Owner = $Window
    $script:PermDlg.Width = 420
    $script:PermDlg.SizeToContent = 'Height'
    $script:PermDlg.Topmost = $false
    $script:PermDlg.ResizeMode = 'NoResize'
    $script:PermDlg.ShowInTaskbar = $false

    $permBorder = [System.Windows.Controls.Border]::new()
    $permBorder.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(250, $bgColor.R, $bgColor.G, $bgColor.B))
    $permBorder.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $permBorder.Padding = [System.Windows.Thickness]::new(24, 20, 24, 20)
    $permBorder.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $permBorder.BorderThickness = [System.Windows.Thickness]::new(1)
    $permShadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $permShadow.BlurRadius = 30; $permShadow.ShadowDepth = 0; $permShadow.Opacity = 0.5
    $permShadow.Color = [System.Windows.Media.Colors]::Black
    $permBorder.Effect = $permShadow

    $permPanel = [System.Windows.Controls.StackPanel]::new()

    # Title row with close button
    $permTitleGrid = [System.Windows.Controls.Grid]::new()
    $ptc1 = [System.Windows.Controls.ColumnDefinition]::new(); $ptc1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $ptc2 = [System.Windows.Controls.ColumnDefinition]::new(); $ptc2.Width = [System.Windows.GridLength]::Auto
    $permTitleGrid.ColumnDefinitions.Add($ptc1)
    $permTitleGrid.ColumnDefinitions.Add($ptc2)

    $permTitle = [System.Windows.Controls.TextBlock]::new()
    $permTitle.FontSize = 15
    $permTitle.FontWeight = [System.Windows.FontWeights]::Bold
    $permTitle.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $permTitle.VerticalAlignment = 'Center'
    $r1 = [System.Windows.Documents.Run]::new([string][char]0xE8D7)
    $r1.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $r1.FontSize = 14
    $r2 = [System.Windows.Documents.Run]::new('  Graph API Permissions')
    $permTitle.Inlines.Add($r1)
    $permTitle.Inlines.Add($r2)
    [System.Windows.Controls.Grid]::SetColumn($permTitle, 0)
    $permTitleGrid.Children.Add($permTitle) | Out-Null

    $permCloseBtn = [System.Windows.Controls.Button]::new()
    $permCloseBtn.Content = [string][char]0xE711
    $permCloseBtn.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $permCloseBtn.FontSize = 12
    $permCloseBtn.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $permCloseBtn.Background = [System.Windows.Media.Brushes]::Transparent
    $permCloseBtn.BorderThickness = [System.Windows.Thickness]::new(0)
    $permCloseBtn.Cursor = [System.Windows.Input.Cursors]::Hand
    $permCloseBtn.ToolTip = 'Close'
    [System.Windows.Controls.Grid]::SetColumn($permCloseBtn, 1)
    $permCloseBtn.Add_Click({ $script:PermDlg.Close() })
    $permTitleGrid.Children.Add($permCloseBtn) | Out-Null

    $permTitleGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $permPanel.Children.Add($permTitleGrid) | Out-Null

    # Subtitle
    $script:PermDlgSubtitle = [System.Windows.Controls.TextBlock]::new()
    $script:PermDlgSubtitle.Text = 'Checking required Microsoft Graph API permissions...'
    $script:PermDlgSubtitle.FontSize = 12
    $script:PermDlgSubtitle.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $script:PermDlgSubtitle.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $permPanel.Children.Add($script:PermDlgSubtitle) | Out-Null

    # Permission rows container
    $permItemsPanel = [System.Windows.Controls.StackPanel]::new()

    # Create placeholder rows for the three permissions (pending state)
    $requiredPerms = @(
        @{ Name = 'DeviceManagementApps.ReadWrite.All'; Description = 'Create and manage Win32 app packages' }
        @{ Name = 'DeviceManagementManagedDevices.Read.All'; Description = 'Read managed devices for model lookup' }
        @{ Name = 'GroupMember.Read.All'; Description = 'Read group memberships for deployment targeting' }
    )
    $script:PermDlgIcons = @{}
    foreach ($rp in $requiredPerms) {
        $rpRow = [System.Windows.Controls.Grid]::new()
        $rpc1 = [System.Windows.Controls.ColumnDefinition]::new()
        $rpc1.Width = [System.Windows.GridLength]::new(26, [System.Windows.GridUnitType]::Pixel)
        $rpc2 = [System.Windows.Controls.ColumnDefinition]::new()
        $rpc2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $rpRow.ColumnDefinitions.Add($rpc1)
        $rpRow.ColumnDefinitions.Add($rpc2)
        $rpRow.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)

        $rpIcon = [System.Windows.Controls.TextBlock]::new()
        $rpIcon.Text = [string][char]0xE916  # Stopwatch / pending
        $rpIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $rpIcon.FontSize = 14
        $rpIcon.VerticalAlignment = 'Center'
        $rpIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
        [System.Windows.Controls.Grid]::SetColumn($rpIcon, 0)
        $rpRow.Children.Add($rpIcon) | Out-Null
        $script:PermDlgIcons[$rp.Name] = $rpIcon

        $rpLabelPanel = [System.Windows.Controls.StackPanel]::new()
        $rpLabelPanel.Orientation = 'Vertical'
        $rpNameText = [System.Windows.Controls.TextBlock]::new()
        $rpNameText.Text = $rp.Name
        $rpNameText.FontSize = 13
        $rpNameText.FontWeight = [System.Windows.FontWeights]::SemiBold
        $rpNameText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
        $rpLabelPanel.Children.Add($rpNameText) | Out-Null
        $rpDescText = [System.Windows.Controls.TextBlock]::new()
        $rpDescText.Text = $rp.Description
        $rpDescText.FontSize = 11
        $rpDescText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
        $rpLabelPanel.Children.Add($rpDescText) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($rpLabelPanel, 1)
        $rpRow.Children.Add($rpLabelPanel) | Out-Null

        $permItemsPanel.Children.Add($rpRow) | Out-Null
    }

    $permPanel.Children.Add($permItemsPanel) | Out-Null

    # Summary status (updated after check completes)
    $script:PermDlgSummary = [System.Windows.Controls.TextBlock]::new()
    $script:PermDlgSummary.FontSize = 12
    $script:PermDlgSummary.FontWeight = [System.Windows.FontWeights]::SemiBold
    $script:PermDlgSummary.Margin = [System.Windows.Thickness]::new(0, 12, 0, 0)
    $script:PermDlgSummary.Visibility = 'Collapsed'
    $permPanel.Children.Add($script:PermDlgSummary) | Out-Null

    $permBorder.Child = $permPanel
    $script:PermDlg.Content = $permBorder

    # Start the permission check background runspace BEFORE showing the dialog
    $authStatus = Get-DATIntuneAuthStatus
    $token = $authStatus.Token
    $tokenExpiry = $authStatus.ExpiresOn
    $script:PermVerifyState = [hashtable]::Synchronized(@{
        Status = 'Running'
        Result = $null
    })
    $script:PermVerifyPS = [powershell]::Create()
    $script:PermVerifyPS.AddScript({
        param ($ModulePath, $State, $Token, $TokenExpiry)
        Import-Module $ModulePath -Force
        Set-DATIntuneAuthToken -Token $Token -ExpiresOn $TokenExpiry
        $State.Result = Test-DATIntunePermissions
        $State.Status = 'Complete'
    })
    [void]$script:PermVerifyPS.AddArgument($CoreModulePath)
    [void]$script:PermVerifyPS.AddArgument($script:PermVerifyState)
    [void]$script:PermVerifyPS.AddArgument($token)
    [void]$script:PermVerifyPS.AddArgument($tokenExpiry)
    $script:PermVerifyAsync = $script:PermVerifyPS.BeginInvoke()

    # Poll timer fires during the ShowDialog message pump
    $script:PermVerifyTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:PermVerifyTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:PermVerifyTimer.Add_Tick({
        if ($script:PermVerifyState.Status -eq 'Complete') {
            $script:PermVerifyTimer.Stop()
            $result = $script:PermVerifyState.Result
            foreach ($p in $result.Permissions) {
                $icon = $script:PermDlgIcons[$p.Name]
                if (-not $icon) { continue }
                if ($p.Status -eq 'Granted') {
                    $icon.Text = [string][char]0xE73E  # Checkmark
                    $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.ColorConverter]::ConvertFromString('#22C55E'))
                } else {
                    $icon.Text = [string][char]0xE711  # X
                    $icon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.ColorConverter]::ConvertFromString('#EF4444'))
                }
            }
            $script:PermDlgSubtitle.Text = 'Verification complete.'
            if ($result.Granted) {
                $script:PermDlgSummary.Inlines.Clear()
                $iconRun = [System.Windows.Documents.Run]::new([string][char]0xE73E + '  ')
                $iconRun.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
                $script:PermDlgSummary.Inlines.Add($iconRun)
                $script:PermDlgSummary.Inlines.Add([System.Windows.Documents.Run]::new('All required permissions are granted.'))
                $script:PermDlgSummary.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString('#22C55E'))
            } else {
                $denied = ($result.Permissions | Where-Object { $_.Status -ne 'Granted' }).Count
                $script:PermDlgSummary.Inlines.Clear()
                $iconRun = [System.Windows.Documents.Run]::new([string][char]0xE7BA + '  ')
                $iconRun.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
                $script:PermDlgSummary.Inlines.Add($iconRun)
                $script:PermDlgSummary.Inlines.Add([System.Windows.Documents.Run]::new("$denied permission(s) missing -- check your app registration."))
                $script:PermDlgSummary.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                    [System.Windows.Media.ColorConverter]::ConvertFromString('#EF4444'))
            }
            $script:PermDlgSummary.Visibility = 'Visible'
            # Also update the inline permission panel
            Update-DATIntunePermissionUI -PermissionResult $result
            try { $script:PermVerifyPS.Dispose() } catch { }
            $script:PermVerifyPS = $null
        }
    })
    $script:PermVerifyTimer.Start()

    # Show modal -- blocks until closed; DispatcherTimer still fires during modal pump
    $script:PermDlg.ShowDialog() | Out-Null

    # Cleanup if dialog closed before check finished
    if ($script:PermVerifyTimer) { try { $script:PermVerifyTimer.Stop() } catch { } }
    if ($script:PermVerifyPS) { try { $script:PermVerifyPS.Dispose() } catch { }; $script:PermVerifyPS = $null }
})

# Reset Intune auth — clear saved credentials from registry and UI
$btn_ResetIntuneAuth.Add_Click({
    # Disconnect first if currently connected
    if (Test-DATIntuneAuth) {
        Disconnect-DATIntuneGraph
        $script:IntuneTokenTimer.Stop()
    }

    # Stop any in-progress browser auth flow and release the HTTP listener
    if ($script:BrowserAuthPollTimer) {
        try { $script:BrowserAuthPollTimer.Stop() } catch { }
    }
    if ($script:BrowserAuthContext) {
        try { $script:BrowserAuthContext.Listener.Stop(); $script:BrowserAuthContext.Listener.Close() } catch { }
        $script:BrowserAuthContext = $null
    }

    # Remove saved credential values from registry
    Remove-ItemProperty -Path $global:RegPath -Name 'IntuneTenantId' -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $global:RegPath -Name 'IntuneAppId' -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $global:RegPath -Name 'IntuneClientSecret' -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $global:RegPath -Name 'IntuneAuthMode' -Force -ErrorAction SilentlyContinue

    # Clear UI fields
    $txt_IntuneTenantId.Text = ''
    $txt_IntuneAppId.Text = ''
    $txt_IntuneClientSecret.Password = ''
    $cmb_IntuneAuthMode.SelectedIndex = 0

    # Reset auth status UI
    Update-DATIntuneAuthUI
    $panel_AuthStatus.Visibility = 'Collapsed'
    $panel_DeviceCode.Visibility = 'Collapsed'
    $panel_IntunePermissions.Visibility = 'Collapsed'
    $panel_PermissionItems.Children.Clear()
    $txt_IntuneStatus.Text = 'Credentials reset. Please reconfigure to connect.'
    $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['InputPlaceholder']))

    Write-DATActivityLog 'Intune credentials reset -- saved values removed from registry' -Level Info
})

# App refresh function (async to avoid UI freeze)
function Invoke-DATIntuneAppRefresh {
    if (-not (Test-DATIntuneAuth)) {
        $txt_IntuneStatus.Text = "Authentication required - please connect on the Intune Settings page."
        Update-DATIntuneAuthUI
        return
    }

    $btn_RefreshIntuneApps.IsEnabled = $false
    $script:IntuneAppsData.Clear()
    $txt_IntuneStatus.Text = "Loading Intune Win32 applications..."
    $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusInfo']))
    $txt_IntunePkgStatus.Text = "Refreshing Intune Win32 applications..."
    $txt_IntunePkgStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString(
            (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusInfo']))
    $txt_IntunePkgStatus.Visibility = 'Visible'
    Write-DATActivityLog "Loading Intune Win32 applications..." -Level Info

    $script:AppRefreshState = [hashtable]::Synchronized(@{
        Status = 'Running'
        Apps   = $null
        Error  = $null
    })

    $script:AppRefreshPS = [powershell]::Create()
    $script:AppRefreshPS.AddScript({
        param ($CoreModulePath, $State, $Token, $TokenExpiry)
        Import-Module $CoreModulePath -Force
        Set-DATIntuneAuthToken -Token $Token -ExpiresOn $TokenExpiry
        try {
            $allApps = Get-DATIntuneWin32Apps | Where-Object { $_.notes -eq 'Created by the Driver Automation Tool' }
            $State.Apps = @($allApps)
            $State.Status = 'Complete'
        } catch {
            $State.Error = $_.Exception.Message
            $State.Status = 'Failed'
        }
    })
    $authStatus = Get-DATIntuneAuthStatus
    [void]$script:AppRefreshPS.AddArgument($CoreModulePath)
    [void]$script:AppRefreshPS.AddArgument($script:AppRefreshState)
    [void]$script:AppRefreshPS.AddArgument($authStatus.Token)
    [void]$script:AppRefreshPS.AddArgument($authStatus.ExpiresOn)
    $script:AppRefreshAsync = $script:AppRefreshPS.BeginInvoke()

    $script:AppRefreshTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:AppRefreshTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:AppRefreshTimer.Add_Tick({
        if ($script:AppRefreshState.Status -eq 'Running') { return }
        $script:AppRefreshTimer.Stop()

        if ($script:AppRefreshState.Status -eq 'Complete') {
            foreach ($app in $script:AppRefreshState.Apps) {
                $createdDate = ""
                if ($app.createdDateTime) {
                    try { $createdDate = ([datetime]$app.createdDateTime).ToString("yyyy-MM-dd") } catch {}
                }
                $lastModified = ""
                if ($app.lastModifiedDateTime) {
                    try { $lastModified = ([datetime]$app.lastModifiedDateTime).ToString("yyyy-MM-dd") } catch {}
                }
                $script:IntuneAppsData.Add([PSCustomObject]@{
                    Selected    = $false
                    DisplayName = $app.displayName
                    Publisher   = $app.publisher
                    Version     = if ($app.displayVersion) { $app.displayVersion } else { "-" }
                    CreatedDate = $createdDate
                    AppId       = $app.id
                    LastModified = $lastModified
                    Description  = if ($app.description) { $app.description } else { "-" }
                    InstallCmd   = if ($app.installCommandLine) { $app.installCommandLine } else { "-" }
                    Model        = if ($app.displayName -match '^(?:Drivers|Bios Update)\s*-\s*(.+)$') { $Matches[1].Trim() } else { $app.displayName }
                })
            }
            Write-DATActivityLog "Loaded $($script:IntuneAppsData.Count) DAT-created Win32 apps" -Level Success
            $txt_IntuneStatus.Text = "Loaded $($script:IntuneAppsData.Count) Win32 apps"
            $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusSuccess']))
            $txt_IntunePkgStatus.Text = "Loaded $($script:IntuneAppsData.Count) Win32 apps"
            $txt_IntunePkgStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusSuccess']))

            Update-DATPackageRowHighlighting -DataGrid $grid_IntuneApps -ItemsSource $script:IntuneAppsData -MakeProperty 'Publisher' -ModelProperty 'Model' -VersionProperty 'Version'

            # Apply package type + search filter to the refreshed data
            Update-DATIntuneAppFilter
        } else {
            $errMsg = $script:AppRefreshState.Error
            if ($errMsg -match "expired|re-authenticate|401") {
                Update-DATIntuneAuthUI
                $txt_IntuneStatus.Text = "Session expired — please re-authenticate on the Intune Settings page."
            } else {
                $txt_IntuneStatus.Text = "Failed to load apps: $errMsg"
            }
            $txt_IntuneStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
            $txt_IntunePkgStatus.Text = "Failed to load apps: $errMsg"
            $txt_IntunePkgStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
                [System.Windows.Media.ColorConverter]::ConvertFromString(
                    (Get-DATTheme -ThemeName $script:CurrentTheme)['StatusError']))
            Write-DATActivityLog "Failed to load Intune apps: $errMsg" -Level Error
        }

        $btn_RefreshIntuneApps.IsEnabled = $true
        try { $script:AppRefreshPS.Dispose(); $script:AppRefreshPS = $null } catch {}
    })
    $script:AppRefreshTimer.Start()
}

$btn_RefreshIntuneApps.Add_Click({
    Invoke-DATIntuneAppRefresh
})

# Populate detail panel when a row is highlighted
$btn_IntuneReportIssue = $Window.FindName('btn_IntuneReportIssue')
$btn_IntuneReportIssue.IsEnabled = $false
$grid_IntuneApps.Add_SelectionChanged({
    $selected = $grid_IntuneApps.SelectedItem
    if ($null -eq $selected) {
        $panel_IntuneAppDetail.Visibility = 'Collapsed'
        $btn_IntuneReportIssue.IsEnabled = $false
        return
    }
    $txt_Detail_Name.Text        = $selected.DisplayName
    $txt_Detail_Publisher.Text   = $selected.Publisher
    $txt_Detail_AppId.Text       = $selected.AppId
    $txt_Detail_InstallCmd.Text  = $selected.InstallCmd
    $txt_Detail_Description.Text = $selected.Description
    $txt_Detail_Version.Text     = $selected.Version
    $panel_IntuneAppDetail.Visibility = 'Visible'

    # Enable Report Issue only if telemetry is opted in
    $btn_IntuneReportIssue.IsEnabled = $chk_TelemetryOptOut.IsChecked -eq $true

    # Update Report Issue button text
    $make = $selected.Publisher
    $model = $selected.Model
    $ver = $selected.Version
    if (Test-DATPackageReported -Make $make -Model $model -Version $ver) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.FontSize = 11
        $r1 = New-Object System.Windows.Documents.Run; $r1.Text = [char]0xE711; $r1.FontFamily = 'Segoe MDL2 Assets'
        $r2 = New-Object System.Windows.Documents.Run; $r2.Text = '  Clear Report'
        $tb.Inlines.Add($r1); $tb.Inlines.Add($r2)
        $btn_IntuneReportIssue.Content = $tb
    } else {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.FontSize = 11
        $r1 = New-Object System.Windows.Documents.Run; $r1.Text = [char]0xE7BA; $r1.FontFamily = 'Segoe MDL2 Assets'
        $r2 = New-Object System.Windows.Documents.Run; $r2.Text = '  Report Issue'
        $tb.Inlines.Add($r1); $tb.Inlines.Add($r2)
        $btn_IntuneReportIssue.Content = $tb
    }
})

# Intune Report Issue button
$btn_IntuneReportIssue.Add_Click({
    if ($chk_TelemetryOptOut.IsChecked -ne $true) { return }
    $selected = $grid_IntuneApps.SelectedItem
    if ($null -eq $selected) { return }
    $make = $selected.Publisher
    $model = $selected.Model
    $ver = $selected.Version

    if (Test-DATPackageReported -Make $make -Model $model -Version $ver) {
        Remove-DATReportedIssue -Make $make -Model $model -Version $ver
        Write-DATActivityLog "Cleared issue report: $make $model v$ver" -Level Info
    } else {
        Add-DATReportedIssue -Make $make -Model $model -Version $ver
        Write-DATActivityLog "Reported issue: $make $model v$ver" -Level Warn
    }

    # Refresh button text after toggle
    if (Test-DATPackageReported -Make $make -Model $model -Version $ver) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.FontSize = 11
        $r1 = New-Object System.Windows.Documents.Run; $r1.Text = [char]0xE711; $r1.FontFamily = 'Segoe MDL2 Assets'
        $r2 = New-Object System.Windows.Documents.Run; $r2.Text = '  Clear Report'
        $tb.Inlines.Add($r1); $tb.Inlines.Add($r2)
        $btn_IntuneReportIssue.Content = $tb
    } else {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.FontSize = 11
        $r1 = New-Object System.Windows.Documents.Run; $r1.Text = [char]0xE7BA; $r1.FontFamily = 'Segoe MDL2 Assets'
        $r2 = New-Object System.Windows.Documents.Run; $r2.Text = '  Report Issue'
        $tb.Inlines.Add($r1); $tb.Inlines.Add($r2)
        $btn_IntuneReportIssue.Content = $tb
    }

    # Refresh row highlighting
    Update-DATPackageRowHighlighting -DataGrid $grid_IntuneApps -ItemsSource $script:IntuneAppsData -MakeProperty 'Publisher' -ModelProperty 'Model' -VersionProperty 'Version'
})

# Intune Delete Package button (from detail panel)
$btn_IntuneDeletePackage = $Window.FindName('btn_IntuneDeletePackage')
$btn_IntuneDeletePackage.Add_Click({
    $selected = $grid_IntuneApps.SelectedItem
    if ($null -eq $selected -or [string]::IsNullOrEmpty($selected.AppId)) { return }

    if (-not (Test-DATIntuneAuth)) {
        Update-DATIntuneAuthUI
        $txt_IntuneStatus.Text = "Authentication expired - please re-authenticate."
        return
    }

    $confirm = Show-DATConfirmDialog -Title "Delete Application" -Message "Are you sure you want to delete '$($selected.DisplayName)'?`n`nThis action cannot be undone."
    if (-not $confirm) { return }

    try {
        Remove-DATIntuneApp -AppId $selected.AppId
        Write-DATActivityLog "Deleted: $($selected.DisplayName)" -Level Success
        $panel_IntuneAppDetail.Visibility = 'Collapsed'
        Invoke-DATIntuneAppRefresh
        Show-DATInfoDialog -Title "Application Deleted" `
            -Message "'$($selected.DisplayName)' has been successfully removed from Intune." `
            -Type Success
    } catch {
        Write-DATActivityLog "Failed to delete $($selected.DisplayName): $($_.Exception.Message)" -Level Error
    }
})

# Copy App ID from detail panel
$btn_Detail_CopyId.Add_Click({
    $id = $txt_Detail_AppId.Text
    if (-not [string]::IsNullOrWhiteSpace($id)) {
        try {
            [System.Windows.Clipboard]::SetText($id)
            Show-DATCopyFeedback -Button $btn_Detail_CopyId
            Write-DATActivityLog "App ID copied to clipboard: $id" -Level Info
        } catch {
            Write-DATActivityLog "Failed to copy App ID to clipboard" -Level Warn
        }
    }
})

# Delete selected apps
$btn_DeleteIntuneApp.Add_Click({
    $selectedApps = @($script:IntuneAppsData | Where-Object { $_.Selected -eq $true })
    if ($selectedApps.Count -eq 0) {
        $txt_IntuneStatus.Text = "No applications selected."
        return
    }

    if (-not (Test-DATIntuneAuth)) {
        Update-DATIntuneAuthUI
        $txt_IntuneStatus.Text = "Authentication expired - please re-authenticate on the Intune Settings page."
        return
    }

    $confirm = Show-DATConfirmDialog -Title "Delete Applications" -Message "Delete $($selectedApps.Count) selected application(s) from Intune?`n`nThis action cannot be undone."
    if (-not $confirm) { return }

    $btn_DeleteIntuneApp.IsEnabled = $false
    $totalCount = $selectedApps.Count
    $appIds = @($selectedApps | ForEach-Object { $_.AppId })
    $appNames = @($selectedApps | ForEach-Object { $_.DisplayName })

    # Build progress modal
    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])

    $script:deleteModal = [System.Windows.Window]::new()
    $script:deleteModal.WindowStyle = 'None'
    $script:deleteModal.AllowsTransparency = $true
    $script:deleteModal.Background = [System.Windows.Media.Brushes]::Transparent
    $script:deleteModal.WindowStartupLocation = 'CenterOwner'
    $script:deleteModal.Owner = $Window
    $script:deleteModal.Width = 440
    $script:deleteModal.SizeToContent = 'Height'
    $script:deleteModal.Topmost = $true
    $script:deleteModal.ResizeMode = 'NoResize'
    $script:deleteModal.ShowInTaskbar = $false

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(245, $bgColor.R, $bgColor.G, $bgColor.B))
    $border.CornerRadius = [System.Windows.CornerRadius]::new(16)
    $border.Padding = [System.Windows.Thickness]::new(28, 24, 28, 24)
    $border.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 30; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $border.Effect = $shadow

    $panel = [System.Windows.Controls.StackPanel]::new()

    # Spinner icon
    $iconText = [System.Windows.Controls.TextBlock]::new()
    $iconText.Text = [char]0xE74D
    $iconText.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $iconText.FontSize = 28
    $iconText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor']))
    $iconText.HorizontalAlignment = 'Center'
    $iconText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($iconText) | Out-Null

    # Title
    $titleText = [System.Windows.Controls.TextBlock]::new()
    $titleText.Text = "Deleting Applications"
    $titleText.FontSize = 16
    $titleText.FontWeight = [System.Windows.FontWeights]::Bold
    $titleText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $titleText.HorizontalAlignment = 'Center'
    $titleText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $panel.Children.Add($titleText) | Out-Null

    # Progress counter text
    $script:deleteProgressText = [System.Windows.Controls.TextBlock]::new()
    $script:deleteProgressText.Text = "Deleting 0 of $totalCount..."
    $script:deleteProgressText.FontSize = 13
    $script:deleteProgressText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $script:deleteProgressText.HorizontalAlignment = 'Center'
    $script:deleteProgressText.TextAlignment = [System.Windows.TextAlignment]::Center
    $script:deleteProgressText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $panel.Children.Add($script:deleteProgressText) | Out-Null

    # Current app name
    $script:deleteCurrentApp = [System.Windows.Controls.TextBlock]::new()
    $script:deleteCurrentApp.Text = ""
    $script:deleteCurrentApp.FontSize = 11
    $script:deleteCurrentApp.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $script:deleteCurrentApp.HorizontalAlignment = 'Center'
    $script:deleteCurrentApp.TextAlignment = [System.Windows.TextAlignment]::Center
    $script:deleteCurrentApp.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $script:deleteCurrentApp.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $panel.Children.Add($script:deleteCurrentApp) | Out-Null

    # Progress bar
    $script:deleteProgressBar = [System.Windows.Controls.ProgressBar]::new()
    $script:deleteProgressBar.Minimum = 0
    $script:deleteProgressBar.Maximum = $totalCount
    $script:deleteProgressBar.Value = 0
    $script:deleteProgressBar.Height = 6
    $script:deleteProgressBar.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor']))
    $script:deleteProgressBar.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputBackground']))
    $progressTemplate = [System.Windows.Markup.XamlReader]::Parse(@"
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="ProgressBar">
    <Grid>
        <Border x:Name="PART_Track" Background="{TemplateBinding Background}" CornerRadius="3"/>
        <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}" CornerRadius="3" HorizontalAlignment="Left"/>
    </Grid>
</ControlTemplate>
"@)
    $script:deleteProgressBar.Template = $progressTemplate
    $script:deleteProgressBar.Margin = [System.Windows.Thickness]::new(0, 0, 0, 0)
    $panel.Children.Add($script:deleteProgressBar) | Out-Null

    $border.Child = $panel
    $script:deleteModal.Content = $border

    # Background deletion state
    $script:deleteState = [hashtable]::Synchronized(@{
        Processed = 0
        Deleted   = 0
        Errors    = 0
        Current   = ''
        Done      = $false
    })

    # Background runspace for Graph API calls
    $script:deleteRunspace = [runspacefactory]::CreateRunspace()
    $script:deleteRunspace.ApartmentState = 'STA'
    $script:deleteRunspace.Open()

    $script:deletePS = [powershell]::Create()
    $script:deletePS.Runspace = $script:deleteRunspace
    [void]$script:deletePS.AddScript({
        param ($CoreModulePath, $AppIds, $AppNames, $State, $Token, $TokenExpiry)
        Import-Module $CoreModulePath -Force
        Set-DATIntuneAuthToken -Token $Token -ExpiresOn $TokenExpiry
        for ($i = 0; $i -lt $AppIds.Count; $i++) {
            $State.Current = $AppNames[$i]
            try {
                Remove-DATIntuneApp -AppId $AppIds[$i]
                $State.Deleted++
            } catch {
                $State.Errors++
            }
            $State.Processed = $i + 1
        }
        $State.Done = $true
    })
    $authStatus = Get-DATIntuneAuthStatus
    [void]$script:deletePS.AddArgument($CoreModulePath)
    [void]$script:deletePS.AddArgument($appIds)
    [void]$script:deletePS.AddArgument($appNames)
    [void]$script:deletePS.AddArgument($script:deleteState)
    [void]$script:deletePS.AddArgument($authStatus.Token)
    [void]$script:deletePS.AddArgument($authStatus.ExpiresOn)
    $script:deleteAsync = $script:deletePS.BeginInvoke()

    # Poll timer to update modal UI
    $script:deleteTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:deleteTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $script:deleteTimer.Add_Tick({
        $state = $script:deleteState
        $total = $script:deleteProgressBar.Maximum

        $script:deleteProgressBar.Value = $state.Processed
        $script:deleteProgressText.Text = "Deleted $($state.Processed) of $([int]$total)..."
        if (-not [string]::IsNullOrEmpty($state.Current)) {
            $script:deleteCurrentApp.Text = $state.Current
        }

        if ($state.Done) {
            $script:deleteTimer.Stop()

            # Final summary
            $deleted = $state.Deleted
            $errors = $state.Errors
            $script:deleteProgressText.Text = "Deleted $deleted of $([int]$total) application$(if ([int]$total -ne 1) { 's' })" +
                $(if ($errors -gt 0) { " ($errors failed)" } else { "" })
            $script:deleteCurrentApp.Text = ""

            Write-DATActivityLog "Intune delete complete: $deleted deleted, $errors failed" -Level $(if ($errors -gt 0) { 'Warn' } else { 'Success' })

            # Auto-close after a brief pause so user sees the final count
            $script:deleteCloseTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $script:deleteCloseTimer.Interval = [TimeSpan]::FromMilliseconds(800)
            $script:deleteCloseTimer.Add_Tick({
                $script:deleteCloseTimer.Stop()
                try { $script:deleteModal.Close() } catch {}
                $delTotal = [int]$script:deleteProgressBar.Maximum
                $delDeleted = $script:deleteState.Deleted
                $delErrors = $script:deleteState.Errors
                $errMsg = if ($delErrors -gt 0) { "`n`n$delErrors application(s) failed to delete." } else { '' }
                $dlgType = if ($delErrors -gt 0) { 'Warning' } else { 'Success' }
                Show-DATInfoDialog -Title "Deletion Complete" `
                    -Message "Successfully deleted $delDeleted of $delTotal application(s) from Intune.$errMsg" `
                    -Type $dlgType
            })
            $script:deleteCloseTimer.Start()

            # Clean up runspace
            try { $script:deletePS.EndInvoke($script:deleteAsync) } catch {}
            try { $script:deletePS.Dispose(); $script:deleteRunspace.Dispose() } catch {}

            $txt_IntuneStatus.Text = "Deleted $deleted app(s)" + $(if ($errors -gt 0) { ", $errors failed" } else { "" })
            $btn_DeleteIntuneApp.IsEnabled = $false
            Invoke-DATIntuneAppRefresh
        }
    })
    $script:deleteTimer.Start()

    # Show modal (blocks UI interaction with main window)
    $script:deleteModal.ShowDialog() | Out-Null
})

function Update-DATIntuneDeleteButtonState {
    $selectedCount = @($script:IntuneAppsData | Where-Object { $_.Selected -eq $true }).Count
    $btn_DeleteIntuneApp.IsEnabled = ($selectedCount -gt 0)
}

# Enable delete button when checkbox is toggled in the grid
$grid_IntuneApps.Add_CellEditEnding({
    # Defer the check so the binding has committed the new value
    $Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{
        Update-DATIntuneDeleteButtonState
    })
})
$grid_IntuneApps.Add_CurrentCellChanged({
    $Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{
        Update-DATIntuneDeleteButtonState
    })
})

#region BIOS Security

$btn_ExportBIOSRemediation = $Window.FindName('btn_ExportBIOSRemediation')
$txt_BIOSPassword = $Window.FindName('txt_BIOSPassword')
$txt_BIOSPasswordStatus = $Window.FindName('txt_BIOSPasswordStatus')

$btn_ExportBIOSRemediation.Add_Click({
    $password = $txt_BIOSPassword.Password
    if ([string]::IsNullOrWhiteSpace($password)) {
        $txt_BIOSPasswordStatus.Text = "Please enter a BIOS password before exporting."
        $txt_BIOSPasswordStatus.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        return
    }

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select folder to export BIOS remediation scripts"
    $dialog.ShowNewFolderButton = $true

    if ($dialog.ShowDialog() -eq 'OK') {
        try {
            $exportPath = $dialog.SelectedPath
            $templatePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Modules\DriverAutomationToolCore\Templates'

            # Read and update remediation script with the entered password
            $remediationTemplate = Get-Content -Path (Join-Path $templatePath 'Deploy-BIOSPassword-Remediation.ps1') -Raw
            $remediationScript = $remediationTemplate -replace [regex]::Escape("`$BIOSPassword = 'CHANGE_ME'"), "`$BIOSPassword = '$($password -replace "'","''")"

            # Copy detection script as-is
            $detectionScript = Get-Content -Path (Join-Path $templatePath 'Deploy-BIOSPassword-Detection.ps1') -Raw

            Set-Content -Path (Join-Path $exportPath 'Deploy-BIOSPassword-Remediation.ps1') -Value $remediationScript -Force
            Set-Content -Path (Join-Path $exportPath 'Deploy-BIOSPassword-Detection.ps1') -Value $detectionScript -Force

            $txt_BIOSPasswordStatus.Text = "Scripts exported to $exportPath"
            $txt_BIOSPasswordStatus.Foreground = [System.Windows.Media.Brushes]::LimeGreen
            $txt_Status.Text = "BIOS remediation scripts exported successfully."
        } catch {
            $txt_BIOSPasswordStatus.Text = "Export failed: $($_.Exception.Message)"
            $txt_BIOSPasswordStatus.Foreground = [System.Windows.Media.Brushes]::OrangeRed
            $txt_Status.Text = "BIOS script export failed."
        }
    }
})

# Peek button — show password while mouse is held down
$btn_PeekBIOSPassword = $Window.FindName('btn_PeekBIOSPassword')
$txt_BIOSPasswordPlain = $Window.FindName('txt_BIOSPasswordPlain')

$btn_PeekBIOSPassword.Add_PreviewMouseLeftButtonDown({
    $txt_BIOSPasswordPlain.Text = $txt_BIOSPassword.Password
    $txt_BIOSPasswordPlain.Visibility = 'Visible'
    $txt_BIOSPassword.Visibility = 'Hidden'
})

$btn_PeekBIOSPassword.Add_PreviewMouseLeftButtonUp({
    $txt_BIOSPassword.Visibility = 'Visible'
    $txt_BIOSPasswordPlain.Visibility = 'Collapsed'
    $txt_BIOSPasswordPlain.Text = ''
})

$btn_PeekBIOSPassword.Add_MouseLeave({
    if ($txt_BIOSPasswordPlain.Visibility -eq 'Visible') {
        $txt_BIOSPassword.Visibility = 'Visible'
        $txt_BIOSPasswordPlain.Visibility = 'Collapsed'
        $txt_BIOSPasswordPlain.Text = ''
    }
})

# HP Password BIN file browse/clear
$txt_HPPasswordBinPath = $Window.FindName('txt_HPPasswordBinPath')
$btn_BrowseHPPasswordBin = $Window.FindName('btn_BrowseHPPasswordBin')
$btn_ClearHPPasswordBin = $Window.FindName('btn_ClearHPPasswordBin')
$txt_HPPasswordBinStatus = $Window.FindName('txt_HPPasswordBinStatus')

$btn_BrowseHPPasswordBin.Add_Click({
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = 'Select HP Firmware Password BIN File'
    $dialog.Filter = 'BIN files (*.bin)|*.bin|All files (*.*)|*.*'
    $dialog.Multiselect = $false

    if ($dialog.ShowDialog() -eq $true) {
        $selectedPath = $dialog.FileName
        if (Test-Path $selectedPath) {
            $txt_HPPasswordBinPath.Text = $selectedPath
            $btn_ClearHPPasswordBin.IsEnabled = $true
            $script:HPPasswordBinPath = $selectedPath
            $txt_HPPasswordBinStatus.Text = "BIN file selected — will be used for HP BIOS packages."
            $txt_HPPasswordBinStatus.Foreground = [System.Windows.Media.Brushes]::LimeGreen
        } else {
            $txt_HPPasswordBinStatus.Text = "Selected file does not exist."
            $txt_HPPasswordBinStatus.Foreground = [System.Windows.Media.Brushes]::OrangeRed
        }
    }
})

$btn_ClearHPPasswordBin.Add_Click({
    $txt_HPPasswordBinPath.Text = ''
    $btn_ClearHPPasswordBin.IsEnabled = $false
    $script:HPPasswordBinPath = $null
    $txt_HPPasswordBinStatus.Text = "BIN file cleared — HP packages will generate from BIOS password if set."
    $txt_HPPasswordBinStatus.Foreground = [System.Windows.Media.Brushes]::LimeGreen
})

#endregion BIOS Security

#endregion Intune Settings

#region Log Viewer

function Import-DATLogEntries {
    $logPath = Join-Path -Path $global:LogDirectory -ChildPath "$global:ProductName.log"
    $lst_LogEntries.Items.Clear()

    if (-not (Test-Path $logPath)) {
        $txt_LogStats.Text = "No log file found."
        return
    }

    $rawLines = Get-Content -Path $logPath -ErrorAction SilentlyContinue
    if ($null -eq $rawLines -or $rawLines.Count -eq 0) {
        $txt_LogStats.Text = "Log file is empty."
        return
    }

    $infoCount = 0; $warnCount = 0; $errorCount = 0
    $cmtracePattern = '<!\[LOG\[(?<msg>.*?)\]LOG\]!><time="(?<time>[^"]*)" date="(?<date>[^"]*)".*?type="(?<type>\d)"'

    # Get theme colors
    $themeColors = Get-DATTheme -ThemeName $script:CurrentTheme
    $infoColor = [System.Windows.Media.ColorConverter]::ConvertFromString($themeColors['SidebarForeground'])
    $warnColor = [System.Windows.Media.ColorConverter]::ConvertFromString($themeColors['StatusWarning'])
    $errorColor = [System.Windows.Media.ColorConverter]::ConvertFromString($themeColors['StatusError'])
    $infoBg = [System.Windows.Media.ColorConverter]::ConvertFromString($themeColors['SidebarBackground'])
    $warnBg = [System.Windows.Media.ColorConverter]::ConvertFromString("#2D2A1A")
    $errorBg = [System.Windows.Media.ColorConverter]::ConvertFromString("#2D1A1E")
    $dimColor = [System.Windows.Media.ColorConverter]::ConvertFromString($themeColors['InputPlaceholder'])

    if ($script:CurrentTheme -eq 'Light') {
        $warnBg = [System.Windows.Media.ColorConverter]::ConvertFromString("#FFF8E1")
        $errorBg = [System.Windows.Media.ColorConverter]::ConvertFromString("#FFEBEE")
    }

    $infoBrush = [System.Windows.Media.SolidColorBrush]::new($infoBg); $infoBrush.Freeze()
    $warnBrush = [System.Windows.Media.SolidColorBrush]::new($warnBg); $warnBrush.Freeze()
    $errorBrush = [System.Windows.Media.SolidColorBrush]::new($errorBg); $errorBrush.Freeze()
    $infoFgBrush = [System.Windows.Media.SolidColorBrush]::new($infoColor); $infoFgBrush.Freeze()
    $warnFgBrush = [System.Windows.Media.SolidColorBrush]::new($warnColor); $warnFgBrush.Freeze()
    $errorFgBrush = [System.Windows.Media.SolidColorBrush]::new($errorColor); $errorFgBrush.Freeze()
    $dimBrush = [System.Windows.Media.SolidColorBrush]::new($dimColor); $dimBrush.Freeze()

    # Severity icon brushes
    $infoIconBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($themeColors['StatusInfo']))
    $infoIconBrush.Freeze()
    $warnIconBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($themeColors['StatusWarning']))
    $warnIconBrush.Freeze()
    $errorIconBrush = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($themeColors['StatusError']))
    $errorIconBrush.Freeze()

    foreach ($line in $rawLines) {
        if ($line -match $cmtracePattern) {
            $msg = $Matches['msg']
            $timeRaw = $Matches['time']
            $dateRaw = $Matches['date']
            $severity = $Matches['type']

            # Parse time (take HH:mm:ss)
            $timePart = $timeRaw.Split('.')[0]
            if ($timePart.Length -gt 8) { $timePart = $timePart.Substring(0, 8) }

            # Determine styling
            switch ($severity) {
                '1' { $fgBrush = $infoFgBrush; $bgBrush = $infoBrush; $iconChar = [char]0xE946; $iconBrush = $infoIconBrush; $infoCount++ }
                '2' { $fgBrush = $warnFgBrush; $bgBrush = $warnBrush; $iconChar = [char]0xE7BA; $iconBrush = $warnIconBrush; $warnCount++ }
                '3' { $fgBrush = $errorFgBrush; $bgBrush = $errorBrush; $iconChar = [char]0xEA39; $iconBrush = $errorIconBrush; $errorCount++ }
                default { $fgBrush = $infoFgBrush; $bgBrush = $infoBrush; $iconChar = [char]0xE946; $iconBrush = $infoIconBrush; $infoCount++ }
            }

            # Build row
            $grid = New-Object System.Windows.Controls.Grid
            $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = [System.Windows.GridLength]::new(28)
            $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = [System.Windows.GridLength]::new(80)
            $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = [System.Windows.GridLength]::new(80)
            $col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $grid.ColumnDefinitions.Add($col0)
            $grid.ColumnDefinitions.Add($col1)
            $grid.ColumnDefinitions.Add($col2)
            $grid.ColumnDefinitions.Add($col3)

            # Icon
            $icon = New-Object System.Windows.Controls.TextBlock
            $icon.Text = [string]$iconChar
            $icon.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
            $icon.FontSize = 10
            $icon.Foreground = $iconBrush
            $icon.VerticalAlignment = 'Center'
            $icon.HorizontalAlignment = 'Center'
            [System.Windows.Controls.Grid]::SetColumn($icon, 0)
            $grid.Children.Add($icon) | Out-Null

            # Time
            $tbTime = New-Object System.Windows.Controls.TextBlock
            $tbTime.Text = $timePart
            $tbTime.FontFamily = New-Object System.Windows.Media.FontFamily("Cascadia Code,Consolas,monospace")
            $tbTime.FontSize = 11
            $tbTime.Foreground = $dimBrush
            $tbTime.VerticalAlignment = 'Center'
            $tbTime.Padding = [System.Windows.Thickness]::new(8, 0, 0, 0)
            [System.Windows.Controls.Grid]::SetColumn($tbTime, 1)
            $grid.Children.Add($tbTime) | Out-Null

            # Date
            $tbDate = New-Object System.Windows.Controls.TextBlock
            $tbDate.Text = $dateRaw
            $tbDate.FontFamily = New-Object System.Windows.Media.FontFamily("Cascadia Code,Consolas,monospace")
            $tbDate.FontSize = 11
            $tbDate.Foreground = $dimBrush
            $tbDate.VerticalAlignment = 'Center'
            $tbDate.Padding = [System.Windows.Thickness]::new(8, 0, 0, 0)
            [System.Windows.Controls.Grid]::SetColumn($tbDate, 2)
            $grid.Children.Add($tbDate) | Out-Null

            # Message
            $tbMsg = New-Object System.Windows.Controls.TextBlock
            $tbMsg.Text = $msg
            $tbMsg.FontFamily = New-Object System.Windows.Media.FontFamily("Cascadia Code,Consolas,monospace")
            $tbMsg.FontSize = 11
            $tbMsg.Foreground = $fgBrush
            $tbMsg.TextWrapping = 'Wrap'
            $tbMsg.VerticalAlignment = 'Center'
            $tbMsg.Padding = [System.Windows.Thickness]::new(8, 0, 8, 0)
            [System.Windows.Controls.Grid]::SetColumn($tbMsg, 3)
            $grid.Children.Add($tbMsg) | Out-Null

            # ListBoxItem
            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Content = $grid
            $item.Background = $bgBrush
            $item.Padding = [System.Windows.Thickness]::new(0, 4, 0, 4)
            $item.BorderThickness = [System.Windows.Thickness]::new(0)
            $lst_LogEntries.Items.Add($item) | Out-Null
        }
    }

    $txt_LogStats.Text = "$($lst_LogEntries.Items.Count) entries  |  $infoCount info  |  $warnCount warnings  |  $errorCount errors"

    # Scroll to bottom (newest)
    if ($lst_LogEntries.Items.Count -gt 0) {
        $lst_LogEntries.ScrollIntoView($lst_LogEntries.Items[$lst_LogEntries.Items.Count - 1])
    }
}

$btn_OpenLogFile.Add_Click({
    $logPath = Join-Path -Path $global:LogDirectory -ChildPath "$global:ProductName.log"
    if (Test-Path $logPath) {
        Invoke-Item -Path $logPath
    } else {
        $txt_LogStats.Text = "Log file not found."
    }
})

$btn_RefreshLog.Add_Click({
    Import-DATLogEntries
})

# Load log content when navigating to log view
$script:OriginalNavLogClick = $null
$nav_Log.Add_Click({
    Import-DATLogEntries
})

#endregion Log Viewer

#region Update Check

$link_License = $Window.FindName('link_License')
$link_License.Add_RequestNavigate({
    param($s, $e)
    Start-Process $e.Uri.AbsoluteUri
    $e.Handled = $true
})

$link_AuthorGitHub = $Window.FindName('btn_AuthorGitHub')
$link_AuthorGitHub.Add_Click({
    Start-Process "https://github.com/maurice-daly"
})

$link_AuthorLinkedIn = $Window.FindName('btn_AuthorLinkedIn')
$link_AuthorLinkedIn.Add_Click({
    Start-Process "https://www.linkedin.com/in/mauricedaly/"
})

# Modern Driver/BIOS Management link handlers
$Window.FindName('btn_MDMLink').Add_Click({
    Start-Process "https://msendpointmgr.com/modern-driver-management/"
})
$Window.FindName('btn_MBMLink').Add_Click({
    Start-Process "https://msendpointmgr.com/modern-bios-management/"
})
$Window.FindName('btn_MDMGitHub').Add_Click({
    Start-Process "https://github.com/MSEndpointMgr/ModernDriverManagement"
})
$Window.FindName('btn_MBMGitHub').Add_Click({
    Start-Process "https://github.com/MSEndpointMgr/ModernBIOSManagement"
})

$btn_CheckUpdate.Add_Click({
    try {
        $btn_CheckUpdate.IsEnabled = $false
        $txt_AboutVersion.Text = "Version $($global:ScriptRelease.ToString(3)) - Checking..."
        $updateInfo = Get-DATAvailableUpdate
        if ($updateInfo.Error) {
            $txt_AboutVersion.Text = "Version $($global:ScriptRelease.ToString(3)) - Unable to check for updates."
        } elseif ($updateInfo.UpdateAvailable) {
            $txt_AboutVersion.Text = "Version $($global:ScriptRelease.ToString(3)) - Update available: $($updateInfo.LatestVersion)"
            $btn_ApplyUpdate = $Window.FindName('btn_ApplyUpdate')
            $btn_ApplyUpdate.Visibility = 'Visible'
        } else {
            $txt_AboutVersion.Text = "Version $($global:ScriptRelease.ToString(3)) - You are up to date."
        }
    } catch {
        $txt_AboutVersion.Text = "Version $($global:ScriptRelease.ToString(3)) - Unable to check for updates."
    } finally {
        $btn_CheckUpdate.IsEnabled = $true
    }
})

# Apply update button handler
$script:btn_ApplyUpdate = $Window.FindName('btn_ApplyUpdate')
$script:txt_UpdateProgress = $Window.FindName('txt_UpdateProgress')

$script:btn_ApplyUpdate.Add_Click({
    $script:btn_ApplyUpdate.IsEnabled = $false
    $btn_CheckUpdate.IsEnabled = $false
    $script:txt_UpdateProgress.Visibility = 'Visible'
    $script:txt_UpdateProgress.Text = "Preparing update..."
    $script:txt_UpdateProgress.Foreground = $Window.FindResource('InputPlaceholder')
    Write-DATActivityLog "Starting self-update from GitHub..." -Level Info

    # Create a runspace that shares the LogQueue for real-time progress
    $script:updateRunspace = [runspacefactory]::CreateRunspace()
    $script:updateRunspace.Open()
    $script:updateRunspace.SessionStateProxy.SetVariable('LogQueue', $script:LogQueue)

    $script:updateJob = [PowerShell]::Create()
    $script:updateJob.Runspace = $script:updateRunspace
    [void]$script:updateJob.AddScript({
        param([string]$InstallDir, [string]$CoreModulePath)

        function Write-UpdateLog {
            param([string]$Message, [string]$Level = 'Info')
            # Post to UI queue with [UPDATE] prefix so the timer can extract it
            $LogQueue.Enqueue("[UPDATE] $Message")
            $severity = switch ($Level) { 'Error' { '3' } 'Warn' { '2' } default { '1' } }
            try { Write-DATLogEntry -Value "[Update] $Message" -Severity $severity } catch { }
        }

        try {
            Write-UpdateLog "Loading core module..."
            Import-Module $CoreModulePath -Force -ErrorAction Stop

            Write-UpdateLog "Install directory: $InstallDir"

            $downloadUrl = "https://github.com/maurice-daly/DriverAutomationTool/archive/refs/heads/master.zip"
            $tempDir = Join-Path $env:TEMP "DATUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            $zipPath = Join-Path $tempDir "DriverAutomationTool.zip"

            # Create temp directory
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            Write-UpdateLog "Temp directory: $tempDir"

            # Download ZIP
            Write-UpdateLog "Downloading from: $downloadUrl"
            $proxyParams = Get-DATWebRequestProxy
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 120 @proxyParams -ErrorAction Stop

            if (-not (Test-Path $zipPath)) {
                throw "Download failed -- ZIP file not found at $zipPath"
            }
            $zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
            Write-UpdateLog "Downloaded $zipSize MB to: $zipPath"

            # Extract ZIP
            Write-UpdateLog "Extracting update package..."
            $extractPath = Join-Path $tempDir "Extracted"
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

            $extractedRoot = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
            if (-not $extractedRoot) {
                throw "Extracted archive does not contain an expected root folder"
            }
            Write-UpdateLog "Extracted root: $($extractedRoot.FullName)"

            # The GitHub archive nests the app inside a subfolder (e.g. 'Driver Automation Tool').
            # Detect the correct source by looking for the launcher script.
            $sourceDir = $extractedRoot.FullName
            $launcherName = 'Start-DriverAutomationTool.ps1'
            if (-not (Test-Path (Join-Path $sourceDir $launcherName))) {
                $subFolder = Get-ChildItem -Path $sourceDir -Directory | Where-Object {
                    Test-Path (Join-Path $_.FullName $launcherName)
                } | Select-Object -First 1
                if ($subFolder) {
                    $sourceDir = $subFolder.FullName
                    Write-UpdateLog "App files located in subfolder: $($subFolder.Name)"
                } else {
                    throw "Cannot locate $launcherName in extracted archive"
                }
            }
            Write-UpdateLog "Source directory: $sourceDir"

            $sourceContents = (Get-ChildItem -Path $sourceDir | Select-Object -ExpandProperty Name) -join ', '
            Write-UpdateLog "Source contents: $sourceContents"

            # Back up current version
            $backupDir = Join-Path $env:TEMP "DATBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Write-UpdateLog "Backing up current installation to: $backupDir"
            Copy-Item -Path $InstallDir -Destination $backupDir -Recurse -Force
            Write-UpdateLog "Backup complete"

            # Copy new files -- preserve user data folders
            $preserveFolders = @('Settings', 'Logs', 'Temp', 'Packages')
            Write-UpdateLog "Replacing application files (preserving: $($preserveFolders -join ', '))..."
            $sourceItems = Get-ChildItem -Path $sourceDir
            $copiedCount = 0
            $skippedCount = 0
            foreach ($item in $sourceItems) {
                if ($item.PSIsContainer -and $item.Name -in $preserveFolders) {
                    $destFolder = Join-Path $InstallDir $item.Name
                    if (-not (Test-Path $destFolder)) {
                        Copy-Item -Path $item.FullName -Destination $destFolder -Recurse -Force
                        Write-UpdateLog "Created new folder: $($item.Name)"
                        $copiedCount++
                    } else {
                        Write-UpdateLog "Preserved existing: $($item.Name)"
                        $skippedCount++
                    }
                    continue
                }
                $destPath = Join-Path $InstallDir $item.Name
                Copy-Item -Path $item.FullName -Destination $destPath -Recurse -Force
                $copiedCount++
                if ($item.PSIsContainer) {
                    $childCount = (Get-ChildItem -Path $item.FullName -Recurse -File).Count
                    Write-UpdateLog "Replaced folder: $($item.Name) ($childCount files)"
                } else {
                    Write-UpdateLog "Replaced file: $($item.Name)"
                }
            }

            # Clean up temp
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-UpdateLog "Update applied -- $copiedCount items replaced, $skippedCount preserved"

            return @{
                Success   = $true
                BackupDir = $backupDir
                Error     = $null
            }
        } catch {
            Write-UpdateLog "Self-update failed: $($_.Exception.Message)" -Level Error
            # Attempt restore from backup
            if ($backupDir -and (Test-Path $backupDir)) {
                Write-UpdateLog "Restoring from backup..." -Level Warn
                try {
                    Copy-Item -Path "$backupDir\*" -Destination $InstallDir -Recurse -Force
                    Write-UpdateLog "Backup restored successfully"
                } catch {
                    Write-UpdateLog "Backup restore failed: $($_.Exception.Message)" -Level Error
                }
            }
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

            return @{
                Success   = $false
                BackupDir = $backupDir
                Error     = $_.Exception.Message
            }
        }
    })
    $modulePath = Join-Path $global:ScriptDirectory 'Modules\DriverAutomationToolCore\DriverAutomationToolCore.psd1'
    [void]$script:updateJob.AddArgument($global:ScriptDirectory)
    [void]$script:updateJob.AddArgument($modulePath)
    $script:updateAsyncResult = $script:updateJob.BeginInvoke()

    $script:updateTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:updateTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:updateTimer.Add_Tick({
        # Drain log queue -- update txt_UpdateProgress with the latest [UPDATE] message
        $latestUpdateMsg = $null
        $queueMsg = $null
        while ($script:LogQueue.TryDequeue([ref]$queueMsg)) {
            if ($queueMsg -match '^\[UPDATE\]\s*(.+)$') {
                $latestUpdateMsg = $Matches[1]
            }
            # Non-update messages still get written to the log file
            if ($queueMsg -notmatch '^\[UPDATE\]') {
                try { Write-DATLogEntry -Value $queueMsg -Severity 1 } catch { }
            }
        }
        if ($latestUpdateMsg) {
            $script:txt_UpdateProgress.Text = $latestUpdateMsg
        }

        if ($script:updateAsyncResult.IsCompleted) {
            $script:updateTimer.Stop()
            # Final drain
            while ($script:LogQueue.TryDequeue([ref]$queueMsg)) {
                if ($queueMsg -match '^\[UPDATE\]\s*(.+)$') {
                    $latestUpdateMsg = $Matches[1]
                }
            }
            if ($latestUpdateMsg) {
                $script:txt_UpdateProgress.Text = $latestUpdateMsg
            }

            try {
                $updateResult = $script:updateJob.EndInvoke($script:updateAsyncResult)
                if ($script:updateJob.Streams.Error.Count -gt 0) {
                    throw $script:updateJob.Streams.Error[0].Exception
                }
                if ($updateResult.Success) {
                    Write-DATActivityLog "Update applied successfully. Backup at: $($updateResult.BackupDir)" -Level Success
                    $script:txt_UpdateProgress.Text = "Update complete! Please restart to use the new version."
                    $script:txt_UpdateProgress.Foreground = $Window.FindResource('StatusSuccess')
                    $txt_AboutVersion.Text = "Version $($global:ScriptRelease.ToString(3)) - Update installed. Restart required."

                    # Prompt the user to restart
                    $restartConfirmed = Show-DATConfirmDialog -Title 'Update Complete' `
                        -Message "The Driver Automation Tool has been updated successfully.`n`nWould you like to restart now to apply the changes?" `
                        -Type Success -ConfirmLabel 'Restart Now' -CancelLabel 'Later'
                    if ($restartConfirmed) {
                        $launcherPath = Join-Path $global:ScriptDirectory 'Start-DriverAutomationTool.ps1'
                        if (Test-Path $launcherPath) {
                            Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$launcherPath`""
                        }
                        $Window.Close()
                    }
                } else {
                    Write-DATActivityLog "Update failed: $($updateResult.Error)" -Level Error
                    $script:txt_UpdateProgress.Text = "Update failed: $($updateResult.Error)"
                    $script:txt_UpdateProgress.Foreground = $Window.FindResource('StatusError')
                }
            } catch {
                $errMsg = $_.Exception.Message
                Write-DATActivityLog "Update failed: $errMsg" -Level Error
                $script:txt_UpdateProgress.Text = "Update failed: $errMsg"
                $script:txt_UpdateProgress.Foreground = $Window.FindResource('StatusError')
            } finally {
                $script:updateJob.Dispose()
                $script:updateRunspace.Dispose()
                $script:updateJob = $null
                $script:updateRunspace = $null
                $script:updateAsyncResult = $null
                $script:btn_ApplyUpdate.IsEnabled = $true
                $btn_CheckUpdate.IsEnabled = $true
            }
        }
    })
    $script:updateTimer.Start()
})

#endregion Update Check

#region Support This Project

$btn_BuyMeACoffee.Add_Click({
    Start-Process "https://buymeacoffee.com/modaly"
})

#endregion Support This Project

function Show-DATTelemetryConsentModal {
    <#
    .SYNOPSIS
        Modal shown once after EULA acceptance, asking the user to opt in or out of telemetry.
        Sets TelemetryOptOut registry value and generates a GUID on opt-in.
    #>
    $theme = Get-DATTheme -ThemeName $script:CurrentTheme
    $bgColor = [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBackground'])

    $dlg = [System.Windows.Window]::new()
    $dlg.WindowStyle        = 'None'
    $dlg.AllowsTransparency = $true
    $dlg.Background         = [System.Windows.Media.Brushes]::Transparent
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Owner              = $Window
    $dlg.Width              = 520
    $dlg.SizeToContent      = 'Height'
    $dlg.Topmost            = $true
    $dlg.ResizeMode         = 'NoResize'
    $dlg.ShowInTaskbar      = $false

    # Outer wrapper grid with margin so the drop shadow is not clipped
    $wrapper = [System.Windows.Controls.Grid]::new()
    $wrapper.Margin = [System.Windows.Thickness]::new(16)

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(250, $bgColor.R, $bgColor.G, $bgColor.B))
    $border.CornerRadius    = [System.Windows.CornerRadius]::new(20)
    $border.Padding         = [System.Windows.Thickness]::new(32, 28, 32, 28)
    $border.BorderBrush     = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['CardBorder']))
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 32; $shadow.ShadowDepth = 0; $shadow.Opacity = 0.5
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $border.Effect = $shadow

    $panel = [System.Windows.Controls.StackPanel]::new()

    # Icon
    $iconTb = [System.Windows.Controls.TextBlock]::new()
    $iconTb.Text        = [string][char]0xEB51   # Telemetry / chart icon
    $iconTb.FontFamily  = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $iconTb.FontSize    = 36
    $iconTb.Foreground  = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor']))
    $iconTb.HorizontalAlignment = 'Center'
    $iconTb.Margin      = [System.Windows.Thickness]::new(0, 0, 0, 14)
    $panel.Children.Add($iconTb) | Out-Null

    # Title
    $titleTb = [System.Windows.Controls.TextBlock]::new()
    $titleTb.Text       = 'Help Improve Driver Automation Tool'
    $titleTb.FontSize   = 17
    $titleTb.FontWeight = [System.Windows.FontWeights]::Bold
    $titleTb.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
    $titleTb.HorizontalAlignment = 'Center'
    $titleTb.TextAlignment = [System.Windows.TextAlignment]::Center
    $titleTb.TextWrapping   = [System.Windows.TextWrapping]::Wrap
    $titleTb.Margin     = [System.Windows.Thickness]::new(0, 0, 0, 14)
    $panel.Children.Add($titleTb) | Out-Null

    # Body text
    $bodyTb = [System.Windows.Controls.TextBlock]::new()
    $bodyTb.Text = "Would you like to opt in to anonymous usage telemetry?`n`nWhen enabled, this tool reports which device makes and models are being packaged, helping to prioritise supported hardware and track adoption trends.`n`nNo personally identifiable information (PII) is ever collected or transmitted. You will be assigned a random, anonymous ID — your name, email, organisation, and device details are never sent.`n`nYou can change this preference at any time in Common Settings."
    $bodyTb.FontSize    = 12
    $bodyTb.Foreground  = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $bodyTb.TextWrapping   = [System.Windows.TextWrapping]::Wrap
    $bodyTb.TextAlignment  = [System.Windows.TextAlignment]::Left
    $bodyTb.LineHeight     = 19
    $bodyTb.Margin         = [System.Windows.Thickness]::new(0, 0, 0, 20)
    $panel.Children.Add($bodyTb) | Out-Null

    # Privacy bullet points panel
    $bulletPanel = [System.Windows.Controls.Border]::new()
    $bulletPanel.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputBackground']))
    $bulletPanel.CornerRadius   = [System.Windows.CornerRadius]::new(10)
    $bulletPanel.Padding        = [System.Windows.Thickness]::new(16, 12, 16, 12)
    $bulletPanel.Margin         = [System.Windows.Thickness]::new(0, 0, 0, 24)
    $bulletSP = [System.Windows.Controls.StackPanel]::new()
    foreach ($bullet in @(
        [string][char]0xE73E + '  No PII is ever collected or transmitted'
        [string][char]0xE73E + '  No names, email addresses, or device identifiers'
        [string][char]0xE73E + '  Only make, model, and OS version are reported'
        [string][char]0xE73E + '  Your anonymous ID is random and stored locally'
    )) {
        $row = [System.Windows.Controls.TextBlock]::new()
        $icon  = $bullet.Substring(0, 1)
        $label = $bullet.Substring(1)
        $run1  = [System.Windows.Documents.Run]::new($icon)
        $run1.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $run1.FontSize   = 11
        $run1.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString($theme['StatusSuccess']))
        $run2 = [System.Windows.Documents.Run]::new($label)
        $run2.FontSize   = 12
        $run2.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString($theme['WindowForeground']))
        $row.Inlines.Add($run1) | Out-Null
        $row.Inlines.Add($run2) | Out-Null
        $row.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $bulletSP.Children.Add($row) | Out-Null
    }
    $bulletPanel.Child = $bulletSP
    $panel.Children.Add($bulletPanel) | Out-Null

    # Reporting site link
    $linkTb = [System.Windows.Controls.TextBlock]::new()
    $linkTb.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $linkTb.FontSize     = 12
    $linkTb.Margin       = [System.Windows.Thickness]::new(0, 0, 0, 20)
    $linkPreRun = [System.Windows.Documents.Run]::new('To see what is being reported, visit the ')
    $linkPreRun.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $hyperlink = [System.Windows.Documents.Hyperlink]::new()
    $hyperlink.Inlines.Add([System.Windows.Documents.Run]::new('Driver Automation Tool Reports'))
    $hyperlink.NavigateUri = [Uri]::new('https://www.driverautomationtool.com/reports')
    $hyperlink.Foreground  = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['AccentColor']))
    $hyperlink.Add_RequestNavigate({
        param($s, $e)
        Start-Process $e.Uri.AbsoluteUri
        $e.Handled = $true
    })
    $linkPostRun = [System.Windows.Documents.Run]::new(' page.')
    $linkPostRun.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString($theme['InputPlaceholder']))
    $linkTb.Inlines.Add($linkPreRun) | Out-Null
    $linkTb.Inlines.Add($hyperlink) | Out-Null
    $linkTb.Inlines.Add($linkPostRun) | Out-Null
    $panel.Children.Add($linkTb) | Out-Null

    # Helper: build a rounded button with explicit colours (modal has no resource dictionary)
    function New-ModalButton {
        param([string]$Label, [string]$IconChar, [string]$BgColor, [string]$BgHover, [string]$FgColor)
        $btn = [System.Windows.Controls.Button]::new()
        $btn.Height          = 38
        $btn.Cursor          = [System.Windows.Input.Cursors]::Hand
        $btn.BorderThickness = [System.Windows.Thickness]::new(0)
        $btn.FontFamily      = [System.Windows.Media.FontFamily]::new('Segoe UI')
        $btn.FontSize        = 13
        $btn.FontWeight      = [System.Windows.FontWeights]::SemiBold

        # Build a ControlTemplate with a rounded border and hover colour swap
        $xamlTemplate = @"
<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
                 xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
                 TargetType='Button'>
    <Border x:Name='bd' Background='$BgColor' CornerRadius='8' Padding='16,8'>
        <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
    </Border>
    <ControlTemplate.Triggers>
        <Trigger Property='IsMouseOver' Value='True'>
            <Setter TargetName='bd' Property='Background' Value='$BgHover'/>
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>
"@
        $btn.Template = [System.Windows.Markup.XamlReader]::Parse($xamlTemplate)

        $tb = [System.Windows.Controls.TextBlock]::new()
        $tb.HorizontalAlignment = 'Center'
        $iconRun = [System.Windows.Documents.Run]::new($IconChar)
        $iconRun.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $iconRun.FontSize   = 12
        $labelRun = [System.Windows.Documents.Run]::new("  $Label")
        $tb.Inlines.Add($iconRun) | Out-Null
        $tb.Inlines.Add($labelRun) | Out-Null
        $tb.Foreground = [System.Windows.Media.SolidColorBrush]::new(
            [System.Windows.Media.ColorConverter]::ConvertFromString($FgColor))
        $btn.Content = $tb
        return $btn
    }

    # Button row
    $btnGrid = [System.Windows.Controls.Grid]::new()
    $btnGrid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 0)
    $col0 = [System.Windows.Controls.ColumnDefinition]::new(); $col0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col1 = [System.Windows.Controls.ColumnDefinition]::new(); $col1.Width = [System.Windows.GridLength]::new(16)
    $col2 = [System.Windows.Controls.ColumnDefinition]::new(); $col2.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $btnGrid.ColumnDefinitions.Add($col0); $btnGrid.ColumnDefinitions.Add($col1); $btnGrid.ColumnDefinitions.Add($col2)

    # Opt-Out button (secondary)
    $btnOptOut = New-ModalButton -Label 'No Thanks' -IconChar ([string][char]0xE711) `
        -BgColor $theme['ButtonSecondary'] -BgHover $theme['ButtonSecondaryHover'] `
        -FgColor $theme['ButtonSecondaryForeground']
    [System.Windows.Controls.Grid]::SetColumn($btnOptOut, 0)
    $btnGrid.Children.Add($btnOptOut) | Out-Null

    # Opt-In button (primary/accent)
    $btnOptIn = New-ModalButton -Label 'Opt In' -IconChar ([string][char]0xE73E) `
        -BgColor $theme['ButtonPrimary'] -BgHover $theme['ButtonPrimaryHover'] `
        -FgColor $theme['ButtonPrimaryForeground']
    [System.Windows.Controls.Grid]::SetColumn($btnOptIn, 2)
    $btnGrid.Children.Add($btnOptIn) | Out-Null

    $panel.Children.Add($btnGrid) | Out-Null
    $border.Child  = $panel
    $wrapper.Children.Add($border) | Out-Null
    $dlg.Content   = $wrapper

    $btnOptIn.Add_Click({
        # Opt in — generate GUID if needed then set the toggle on
        $chk_TelemetryOptOut.IsChecked = $true   # fires Add_Checked which handles all state
        Write-DATActivityLog 'Telemetry: User opted in via consent modal' -Level Info
        $dlg.Close()
    })

    $btnOptOut.Add_Click({
        Set-DATRegistryValue -Name 'TelemetryOptOut' -Value 0 -Type DWord
        $chk_TelemetryOptOut.IsChecked = $false
        Write-DATActivityLog 'Telemetry: User opted out via consent modal' -Level Info
        $dlg.Close()
    })

    $dlg.ShowDialog() | Out-Null
}

#region EULA Agreement

$btn_EulaReviewAccept = $Window.FindName('btn_EulaReviewAccept')

# Check for existing EULA acceptance
$eulaAccepted = (Get-ItemProperty -Path $global:RegPath -Name "EULAAccepted" -ErrorAction SilentlyContinue).EULAAccepted
$eulaDate = (Get-ItemProperty -Path $global:RegPath -Name "EULAAcceptedDate" -ErrorAction SilentlyContinue).EULAAcceptedDate
if ($eulaAccepted -eq "True" -and -not [string]::IsNullOrEmpty($eulaDate)) {
    $txt_EulaStatus.Text = "Accepted on $eulaDate"
    $btn_AgreeEula.IsEnabled = $false
    ($btn_AgreeEula.Content).Inlines.LastInline.Text = "  Agreed"
    $btn_EulaReviewAccept.Visibility = 'Collapsed'
} else {
    $btn_EulaReviewAccept.Visibility = 'Visible'
}

$btn_EulaReviewAccept.Add_Click({
    # Scroll the EULA card into view — navigate to About then scroll to bottom of the EULA ScrollViewer
    Set-DATActiveView -ViewName 'view_About' -NavButtonName 'nav_About'
    $txt_EulaWarning.Visibility = 'Visible'
})

$btn_AgreeEula.Add_Click({
    $acceptedDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Set-DATRegistryValue -Name "EULAAccepted" -Value "True" -Type String
    Set-DATRegistryValue -Name "EULAAcceptedDate" -Value $acceptedDate -Type String
    $txt_EulaStatus.Text = "Accepted on $acceptedDate"
    $btn_AgreeEula.IsEnabled = $false
    ($btn_AgreeEula.Content).Inlines.LastInline.Text = "  Agreed"
    $txt_EulaWarning.Visibility = 'Collapsed'
    $btn_EulaReviewAccept.Visibility = 'Collapsed'
    $txt_Status.Text = "EULA accepted. You may now build packages."
    Write-DATActivityLog "EULA accepted on $acceptedDate" -Level Info

    # Show telemetry consent modal only if preference not already set
    $existingTelePref = (Get-ItemProperty -Path $global:RegPath -Name "TelemetryOptOut" -ErrorAction SilentlyContinue).TelemetryOptOut
    if ($null -eq $existingTelePref) {
        Show-DATTelemetryConsentModal
    }
})

#endregion EULA Agreement

#region Load Saved Settings

try {
    $savedConfig = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
    if ($null -ne $savedConfig) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  Driver Automation Tool - Configuration" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Version       : " -NoNewline -ForegroundColor DarkGray
        Write-Host $global:ScriptRelease.ToString(3) -ForegroundColor Cyan
        Write-Host "  Registry Path : " -NoNewline -ForegroundColor DarkGray
        Write-Host $global:RegPath -ForegroundColor White

        if (-not [string]::IsNullOrEmpty($savedConfig.SiteServer)) {
            Write-Host "  Site Server   : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.SiteServer -ForegroundColor Green
            $txt_SiteServer.Text = $savedConfig.SiteServer
            # Restore WinRM SSL setting
            $savedSSL = ($null -ne $savedConfig.WinRMSSL -and $savedConfig.WinRMSSL -eq 1)
            $chk_WinRMSSL.IsChecked = $savedSSL
            Write-Host "  WinRM SSL     : " -NoNewline -ForegroundColor DarkGray
            Write-Host $(if ($savedSSL) { 'Enabled' } else { 'Disabled' }) -ForegroundColor $(if ($savedSSL) { 'Green' } else { 'DarkYellow' })
            # Auto-connect to previously configured site server
            Invoke-DATConfigMgrConnect -SiteServer $savedConfig.SiteServer -UseSSL $savedSSL
            if (-not [string]::IsNullOrEmpty($global:SiteCode)) {
                Write-Host "  Site Code     : " -NoNewline -ForegroundColor DarkGray
                Write-Host $global:SiteCode -ForegroundColor Green
            }
        } else {
            Write-Host "  Site Server   : " -NoNewline -ForegroundColor DarkGray
            Write-Host "(not configured)" -ForegroundColor DarkYellow
        }

        if (-not [string]::IsNullOrEmpty($savedConfig.TempStoragePath)) {
            Write-Host "  Temp Storage  : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.TempStoragePath -ForegroundColor White
            $txt_TempStorage.Text = $savedConfig.TempStoragePath
            Update-DATDiskFreeSpace -Path $savedConfig.TempStoragePath -ProgressBar $progress_TempFreeSpace -Label $txt_TempFreeSpace -Container $grid_TempFreeSpace
        } else {
            $defaultTempPath = Join-Path $global:ScriptDirectory 'Temp'
            Write-Host "  Temp Storage  : " -NoNewline -ForegroundColor DarkGray
            Write-Host "$defaultTempPath (default)" -ForegroundColor DarkYellow
            $txt_TempStorage.Text = $defaultTempPath
            Update-DATDiskFreeSpace -Path $defaultTempPath -ProgressBar $progress_TempFreeSpace -Label $txt_TempFreeSpace -Container $grid_TempFreeSpace
        }

        if (-not [string]::IsNullOrEmpty($savedConfig.PackageStoragePath)) {
            Write-Host "  Pkg Storage   : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.PackageStoragePath -ForegroundColor White
            $txt_PackageStorage.Text = $savedConfig.PackageStoragePath
            Update-DATDiskFreeSpace -Path $savedConfig.PackageStoragePath -ProgressBar $progress_PackageFreeSpace -Label $txt_PackageFreeSpace -Container $grid_PackageFreeSpace
        } else {
            Write-Host "  Pkg Storage   : " -NoNewline -ForegroundColor DarkGray
            Write-Host "(not configured)" -ForegroundColor DarkYellow
        }

        # Restore Telemetry opt-out
        Write-Host "  Telemetry     : " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $savedConfig.TelemetryOptOut -and $savedConfig.TelemetryOptOut -eq 1) {
            $chk_TelemetryOptOut.IsChecked = $true
            # Restore existing GUID into the panel
            $existingGuid = (Get-ItemProperty -Path $global:RegPath -Name "TelemetryGuid" -ErrorAction SilentlyContinue).TelemetryGuid
            if ([string]::IsNullOrEmpty($existingGuid)) {
                $existingGuid = [System.Guid]::NewGuid().ToString()
                Set-DATRegistryValue -Name "TelemetryGuid" -Value $existingGuid -Type String
            }
            $txt_TelemetryGuid.Text = $existingGuid
            $panel_TelemetryGuid.Visibility = 'Visible'
            Write-Host "Opted in (ID: $existingGuid)" -ForegroundColor Green

            # Pre-fetch remote telemetry config in the background so it doesn't block startup
            $telemetryJob = Start-Job -ScriptBlock {
                param($ModulePath)
                Import-Module $ModulePath -Force -ErrorAction Stop
                $cfg = Get-DATTelemetryConfig
                if ($null -ne $cfg) { return $cfg.apiBaseUrl } else { return $null }
            } -ArgumentList $CoreModulePath

            # Poll for completion via DispatcherTimer (non-blocking)
            $script:telemetryTimer = [System.Windows.Threading.DispatcherTimer]::new()
            $script:telemetryTimer.Interval = [TimeSpan]::FromMilliseconds(500)
            $script:telemetryTimer.Tag = $telemetryJob
            $script:telemetryTimer.Add_Tick({
                $job = $script:telemetryTimer.Tag
                if ($job.State -ne 'Running') {
                    $script:telemetryTimer.Stop()
                    try {
                        $apiUrl = Receive-Job -Job $job -ErrorAction Stop
                        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                        if (-not [string]::IsNullOrEmpty($apiUrl)) {
                            # Cache the config in the main session now that we know it works
                            try { $null = Get-DATTelemetryConfig } catch { }
                            Write-Host "  Telemetry API : " -NoNewline -ForegroundColor DarkGray
                            Write-Host $apiUrl -ForegroundColor Green
                        }
                    } catch {
                        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                        Write-Host "  Telemetry API : " -NoNewline -ForegroundColor DarkGray
                        Write-Host "Unavailable" -ForegroundColor DarkYellow
                    }
                }
            })
            $script:telemetryTimer.Start()
        } else {
            Write-Host "Not opted in" -ForegroundColor DarkYellow
        }

        # Restore Deploy All Devices
        Write-Host "  Deploy All    : " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $savedConfig.DeployAllDevices -and $savedConfig.DeployAllDevices -eq 1) {
            $chk_DeployAllDevices.IsChecked = $true
            $txt_DeployAllState.Text = 'On'
            $txt_DeployAllState.Foreground = $Window.FindResource('AccentColor')
            Write-Host "Enabled" -ForegroundColor Green
        } else {
            $txt_DeployAllState.Text = 'Off'
            Write-Host "Disabled" -ForegroundColor DarkYellow
        }

        # Restore Package Retention
        Write-Host "  Pkg Retention : " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $savedConfig.PackageRetentionEnabled -and $savedConfig.PackageRetentionEnabled -eq 1) {
            $chk_PackageRetentionEnabled.IsChecked = $true
            $txt_PackageRetentionState.Text       = 'On'
            $txt_PackageRetentionState.Foreground = $Window.FindResource('AccentColor')
            $panel_RetentionCount.Visibility      = 'Visible'
            $retainCount = 0
            if ($null -ne $savedConfig.PackageRetentionCount) {
                [int]::TryParse([string]$savedConfig.PackageRetentionCount, [ref]$retainCount) | Out-Null
            }
            foreach ($item in $cmb_RetentionCount.Items) {
                if ([int]$item.Content -eq $retainCount) { $item.IsSelected = $true; break }
            }
            Write-Host "Enabled (keep $retainCount previous)" -ForegroundColor Green
        } else {
            $txt_PackageRetentionState.Text = 'Off'
            Write-Host "Disabled" -ForegroundColor DarkYellow
        }

        # Restore Debug Package Build
        Write-Host "  Debug Build   : " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $savedConfig.DebugPackageBuild -and $savedConfig.DebugPackageBuild -eq 1) {
            $chk_DebugPackageBuild.IsChecked = $true
            $txt_DebugBuildState.Text = 'On'
            $txt_DebugBuildState.Foreground = $Window.FindResource('AccentColor')
            $panel_DebugBuildPath.Visibility = 'Visible'
            Write-Host "Enabled" -ForegroundColor Green
            if (-not [string]::IsNullOrEmpty($savedConfig.DebugBuildPath)) {
                $txt_DebugBuildPath.Text = $savedConfig.DebugBuildPath
                Write-Host "  Debug Path    : $($savedConfig.DebugBuildPath)" -ForegroundColor White
            }
        } else {
            Write-Host "Disabled" -ForegroundColor DarkYellow
        }

        # Restore Toast Behaviour
        Write-Host "  Toast Timeout : " -NoNewline -ForegroundColor DarkGray
        if (-not [string]::IsNullOrEmpty($savedConfig.BIOSToastTimeoutAction)) {
            if ($savedConfig.BIOSToastTimeoutAction -eq 'InstallNow') {
                $cmb_BIOSTimeoutAction.SelectedIndex = 1
                Write-Host "Auto Install" -ForegroundColor White
            } else {
                $cmb_BIOSTimeoutAction.SelectedIndex = 0
                Write-Host "Remind Me Later" -ForegroundColor White
            }
        } else {
            Write-Host "Remind Me Later (Default)" -ForegroundColor DarkYellow
        }
        Write-Host "  Toast Deferrals: " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $savedConfig.BIOSMaxDeferralsEnabled -and $savedConfig.BIOSMaxDeferralsEnabled -eq 1) {
            $chk_EnableMaxDeferrals.IsChecked = $true
            $txt_MaxDeferrals.IsEnabled = $true
            if ($null -ne $savedConfig.BIOSMaxDeferrals -and $savedConfig.BIOSMaxDeferrals -gt 0) {
                $txt_MaxDeferrals.Text = [string]$savedConfig.BIOSMaxDeferrals
                Write-Host "Force after $($savedConfig.BIOSMaxDeferrals)" -ForegroundColor White
            } else {
                Write-Host "Force after 3 (Default)" -ForegroundColor White
            }
        } else {
            Write-Host "Disabled" -ForegroundColor DarkYellow
        }

        # Restore Upload Chunk Size
        Write-Host "  Chunk Size    : " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $savedConfig.IntuneChunkSizeMB -and $savedConfig.IntuneChunkSizeMB -gt 0) {
            $savedChunk = [int]$savedConfig.IntuneChunkSizeMB
            foreach ($item in $cmb_IntuneChunkSize.Items) {
                if ([int]$item.Tag -eq $savedChunk) {
                    $cmb_IntuneChunkSize.SelectedItem = $item
                    break
                }
            }
            Write-Host "$savedChunk MB" -ForegroundColor White
        } else {
            Write-Host "50 MB (Default)" -ForegroundColor DarkYellow
        }

        # Restore Parallel Uploads
        Write-Host "  Parallel Ups  : " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $savedConfig.IntuneParallelUploads -and $savedConfig.IntuneParallelUploads -gt 0) {
            $savedParallel = [int]$savedConfig.IntuneParallelUploads
            foreach ($item in $cmb_IntuneParallelUploads.Items) {
                if ([int]$item.Tag -eq $savedParallel) {
                    $cmb_IntuneParallelUploads.SelectedItem = $item
                    break
                }
            }
            Write-Host "$savedParallel threads" -ForegroundColor White
        } else {
            Write-Host "2 threads (Default)" -ForegroundColor DarkYellow
        }

        # Restore HP Concurrent Downloads
        Write-Host "  HP Downloads  : " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $savedConfig.HPConcurrentDownloads -and $savedConfig.HPConcurrentDownloads -gt 0) {
            $savedHPDl = [int]$savedConfig.HPConcurrentDownloads
            foreach ($item in $cmb_HPConcurrentDownloads.Items) {
                if ([int]$item.Tag -eq $savedHPDl) {
                    $cmb_HPConcurrentDownloads.SelectedItem = $item
                    break
                }
            }
            Write-Host "$savedHPDl concurrent" -ForegroundColor White
        } else {
            Write-Host "2 (Default)" -ForegroundColor DarkYellow
        }

        # Restore Clean Temp on Exit
        Write-Host "  Clean on Exit : " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $savedConfig.CleanTempOnExit -and $savedConfig.CleanTempOnExit -eq 0) {
            $chk_CleanTempOnExit.IsChecked = $false
            Write-Host "Disabled" -ForegroundColor DarkYellow
        } else {
            $chk_CleanTempOnExit.IsChecked = $true
            Write-Host "Enabled (Default)" -ForegroundColor Green
        }

        # Restore Teams Notifications
        Write-Host "  Teams Notify  : " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $savedConfig.TeamsNotificationsEnabled -and $savedConfig.TeamsNotificationsEnabled -eq 1) {
            $chk_TeamsNotifications.IsChecked = $true
            Write-Host "Enabled" -ForegroundColor Green
        } else {
            Write-Host "Disabled" -ForegroundColor DarkYellow
        }
        if (-not [string]::IsNullOrEmpty($savedConfig.TeamsWebhookUrl)) {
            $txt_TeamsWebhookUrl.Text = $savedConfig.TeamsWebhookUrl
            Write-Host "  Teams URL     : " -NoNewline -ForegroundColor DarkGray
            Write-Host "(configured)" -ForegroundColor White
        }

        # Restore OEM selections
        if (-not [string]::IsNullOrEmpty($savedConfig.SelectedOEMs)) {
            Write-Host "  Selected OEMs : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.SelectedOEMs -ForegroundColor White
            $savedOEMs = $savedConfig.SelectedOEMs -split ','
            foreach ($oem in $savedOEMs) {
                $oem = $oem.Trim()
                if ($script:OEMCheckboxes.ContainsKey($oem) -and $script:OEMCheckboxes[$oem].IsEnabled) {
                    $script:OEMCheckboxes[$oem].IsChecked = $true
                }
            }
            Update-DATOEMDisplayText
            Update-DATOEMSelectionHighlight
        } else {
            Write-Host "  Selected OEMs : " -NoNewline -ForegroundColor DarkGray
            Write-Host "(none)" -ForegroundColor DarkYellow
        }

        # Restore OS selection
        if (-not [string]::IsNullOrEmpty($savedConfig.OS)) {
            Write-Host "  OS            : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.OS -ForegroundColor White
            foreach ($item in $cmb_OS.Items) {
                if ($item.Content -eq $savedConfig.OS) {
                    $cmb_OS.SelectedItem = $item
                    break
                }
            }
        } else {
            Write-Host "  OS            : " -NoNewline -ForegroundColor DarkGray
            Write-Host "(not set)" -ForegroundColor DarkYellow
        }

        # Restore Architecture selection
        if (-not [string]::IsNullOrEmpty($savedConfig.Architecture)) {
            Write-Host "  Architecture  : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.Architecture -ForegroundColor White
            foreach ($item in $cmb_Architecture.Items) {
                if ($item.Content -eq $savedConfig.Architecture) {
                    $cmb_Architecture.SelectedItem = $item
                    break
                }
            }
        } else {
            Write-Host "  Architecture  : " -NoNewline -ForegroundColor DarkGray
            Write-Host "(not set)" -ForegroundColor DarkYellow
        }

        # Restore Platform selection
        if (-not [string]::IsNullOrEmpty($savedConfig.Platform)) {
            Write-Host "  Platform      : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.Platform -ForegroundColor White
            foreach ($item in $cmb_Platform.Items) {
                if ($item.Content -eq $savedConfig.Platform) {
                    $cmb_Platform.SelectedItem = $item
                    break
                }
            }
        } else {
            Write-Host "  Platform      : " -NoNewline -ForegroundColor DarkGray
            Write-Host "(not set)" -ForegroundColor DarkYellow
        }

        # Restore Package Type selection
        if (-not [string]::IsNullOrEmpty($savedConfig.PackageType)) {
            Write-Host "  Package Type  : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.PackageType -ForegroundColor White
            foreach ($item in $cmb_PackageType.Items) {
                if ($item.Content -eq $savedConfig.PackageType) {
                    $cmb_PackageType.SelectedItem = $item
                    break
                }
            }
        } else {
            Write-Host "  Package Type  : " -NoNewline -ForegroundColor DarkGray
            Write-Host "Drivers (default)" -ForegroundColor DarkYellow
        }

        # Restore Binary Differential Replication
        Write-Host "  Binary Diff   : " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $savedConfig.BinaryDiffReplication -and $savedConfig.BinaryDiffReplication -eq 1) {
            $chk_BinaryDiffReplication.IsChecked = $true
            $txt_BdrState.Text = 'On'
            $txt_BdrState.Foreground = $Window.FindResource('AccentColor')
            Write-Host "Enabled" -ForegroundColor Green
        } else {
            $chk_BinaryDiffReplication.IsChecked = $false
            $txt_BdrState.Text = 'Off'
            Write-Host "Disabled" -ForegroundColor DarkYellow
        }

        # Restore Known Models Only
        Write-Host "  Known Models  : " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $savedConfig.KnownModelsOnly -and $savedConfig.KnownModelsOnly -eq 1) {
            $chk_KnownModels.IsChecked = $true
            $txt_KnownModelsState.Text = 'On'
            $txt_KnownModelsState.Foreground = $Window.FindResource('AccentColor')
            Write-Host "Enabled" -ForegroundColor Green
        } else {
            $chk_KnownModels.IsChecked = $false
            $txt_KnownModelsState.Text = 'Off'
            Write-Host "Disabled" -ForegroundColor DarkYellow
        }

        # Restore Intune Known Models Only
        Write-Host "  Intune Models : " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $savedConfig.IntuneKnownModelsOnly -and $savedConfig.IntuneKnownModelsOnly -eq 1) {
            $chk_IntuneKnownModels.IsChecked = $true
            $txt_IntuneKnownModelsState.Text = 'On'
            $txt_IntuneKnownModelsState.Foreground = $Window.FindResource('AccentColor')
            Write-Host "Enabled" -ForegroundColor Green
        } else {
            $chk_IntuneKnownModels.IsChecked = $false
            $txt_IntuneKnownModelsState.Text = 'Off'
            Write-Host "Disabled" -ForegroundColor DarkYellow
        }

        # Restore Intune Auth Mode and App Registration credentials
        if ($null -ne $savedConfig.IntuneAuthMode) {
            $cmb_IntuneAuthMode.SelectedIndex = [int]$savedConfig.IntuneAuthMode
            Write-Host "  Intune Auth   : " -NoNewline -ForegroundColor DarkGray
            $authModeLabel = switch ([int]$savedConfig.IntuneAuthMode) {
                0 { 'Browser (Interactive)' }
                1 { 'Device Code' }
                2 { 'App Registration' }
                default { 'Browser (Interactive)' }
            }
            Write-Host $authModeLabel -ForegroundColor White
        }
        if (-not [string]::IsNullOrEmpty($savedConfig.IntuneTenantId)) {
            $txt_IntuneTenantId.Text = $savedConfig.IntuneTenantId
            Write-Host "  Tenant ID     : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.IntuneTenantId -ForegroundColor White
        }
        if (-not [string]::IsNullOrEmpty($savedConfig.IntuneAppId)) {
            $txt_IntuneAppId.Text = $savedConfig.IntuneAppId
            Write-Host "  App ID        : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.IntuneAppId -ForegroundColor White
        }
        if (-not [string]::IsNullOrEmpty($savedConfig.IntuneClientSecret)) {
            try {
                $secString = ConvertTo-SecureString -String $savedConfig.IntuneClientSecret -ErrorAction Stop
                $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secString)
                try {
                    $plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                    $txt_IntuneClientSecret.Password = $plainSecret
                    Write-Host "  Client Secret : " -NoNewline -ForegroundColor DarkGray
                    Write-Host "(restored from encrypted store)" -ForegroundColor Green
                } finally {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                }
            } catch {
                Write-Host "  Client Secret : " -NoNewline -ForegroundColor DarkGray
                Write-Host "(decryption failed — re-enter manually)" -ForegroundColor DarkYellow
            }
        }

        # Restore WIM Engine
        Write-Host "  WIM Engine    : " -NoNewline -ForegroundColor DarkGray
        $wimEngineVal = if (-not [string]::IsNullOrEmpty($savedConfig.WimEngine)) { $savedConfig.WimEngine } else { 'dism' }
        $wimEngineLabel = switch ($wimEngineVal) {
            'wimlib' { 'wimlib (Multi-threaded)' }
            '7zip'   { '7-Zip' }
            default  { 'DISM (Built-in)' }
        }
        # Only restore wimlib if it's actually available
        if ($wimEngineVal -eq 'wimlib' -and $cmbi_Wimlib.IsEnabled -eq $false) {
            $wimEngineLabel = 'DISM (Built-in)'
            Set-DATRegistryValue -Name 'WimEngine' -Value 'dism' -Type String
            Write-Host "DISM (Built-in) [wimlib unavailable]" -ForegroundColor DarkYellow
        } elseif ($wimEngineVal -eq '7zip' -and $cmbi_7Zip.IsEnabled -eq $false) {
            $wimEngineLabel = 'DISM (Built-in)'
            Set-DATRegistryValue -Name 'WimEngine' -Value 'dism' -Type String
            Write-Host "DISM (Built-in) [7-Zip unavailable]" -ForegroundColor DarkYellow
        } else {
            foreach ($item in $cmb_WimEngine.Items) {
                if ($item.Content -eq $wimEngineLabel) {
                    $cmb_WimEngine.SelectedItem = $item
                    break
                }
            }
            Write-Host $wimEngineLabel -ForegroundColor White
        }
        # Update compression description to match restored engine
        $restoredEngine = (Get-ItemProperty -Path $global:RegPath -Name 'WimEngine' -ErrorAction SilentlyContinue).WimEngine
        $txt_CompressionDescription.Text = switch ($restoredEngine) {
            '7zip'  { 'Controls compression when creating WIM packages. Fast (-mx=1) is recommended for most scenarios. Maximum (-mx=9) produces smaller files but is significantly slower.' }
            default { 'Controls compression when creating WIM packages. Fast (XPRESS) is recommended for most scenarios. Maximum (LZX) produces smaller files but is significantly slower.' }
        }

        # Restore DISM Compression Level
        Write-Host "  DISM Compress : " -NoNewline -ForegroundColor DarkGray
        $dismCompressionVal = if (-not [string]::IsNullOrEmpty($savedConfig.DismCompression)) { $savedConfig.DismCompression } else { 'fast' }
        $dismCompressionLabel = switch ($dismCompressionVal) {
            'max'  { 'Maximum' }
            'none' { 'None' }
            default { 'Fast (Recommended)' }
        }
        foreach ($item in $cmb_DismCompression.Items) {
            if ($item.Content -eq $dismCompressionLabel) {
                $cmb_DismCompression.SelectedItem = $item
                break
            }
        }
        Write-Host $dismCompressionLabel -ForegroundColor White

        # Restore Distribution Priority
        if (-not [string]::IsNullOrEmpty($savedConfig.DistributionPriority)) {
            Write-Host "  Dist Priority : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.DistributionPriority -ForegroundColor White
            foreach ($item in $cmb_DistPriority.Items) {
                if ($item.Content -eq $savedConfig.DistributionPriority) {
                    $cmb_DistPriority.SelectedItem = $item
                    break
                }
            }
        } else {
            Write-Host "  Dist Priority : " -NoNewline -ForegroundColor DarkGray
            Write-Host "Normal (default)" -ForegroundColor DarkYellow
        }

        # Restore CURL Running Mode
        if (-not [string]::IsNullOrEmpty($savedConfig.CurlRunMode)) {
            Write-Host "  CURL Mode     : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.CurlRunMode -ForegroundColor White
            foreach ($item in $cmb_CurlRunMode.Items) {
                if ($item.Content -eq $savedConfig.CurlRunMode) {
                    $cmb_CurlRunMode.SelectedItem = $item
                    break
                }
            }
        } else {
            Write-Host "  CURL Mode     : " -NoNewline -ForegroundColor DarkGray
            Write-Host "Silent (default)" -ForegroundColor DarkYellow
        }

        # Restore CURL Source
        if (-not [string]::IsNullOrEmpty($savedConfig.CurlSource)) {
            Write-Host "  CURL Source   : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.CurlSource -ForegroundColor White
            foreach ($item in $cmb_CurlSource.Items) {
                if ($item.Content -eq $savedConfig.CurlSource) {
                    $cmb_CurlSource.SelectedItem = $item
                    break
                }
            }
        } else {
            Write-Host "  CURL Source   : " -NoNewline -ForegroundColor DarkGray
            Write-Host "Built-in (System) (default)" -ForegroundColor DarkYellow
        }

        # Restore Proxy Configuration
        if (-not [string]::IsNullOrEmpty($savedConfig.ProxyMode)) {
            $proxyDisplay = switch ($savedConfig.ProxyMode) {
                'Manual' { 'Manual' }
                'None'   { 'No Proxy' }
                default  { 'Use System Proxy' }
            }
            foreach ($item in $cmb_ProxyMode.Items) {
                if ($item.Content -eq $proxyDisplay) {
                    $cmb_ProxyMode.SelectedItem = $item
                    break
                }
            }
            if ($savedConfig.ProxyMode -eq 'Manual') {
                $panel_ProxyManual.Visibility = 'Visible'
            }
            Write-Host "  Proxy Mode    : " -NoNewline -ForegroundColor DarkGray
            Write-Host $proxyDisplay -ForegroundColor White
        } else {
            Write-Host "  Proxy Mode    : " -NoNewline -ForegroundColor DarkGray
            Write-Host "System (default)" -ForegroundColor DarkYellow
        }
        if (-not [string]::IsNullOrEmpty($savedConfig.ProxyServer)) {
            $txt_ProxyServer.Text = $savedConfig.ProxyServer
            Write-Host "  Proxy Server  : " -NoNewline -ForegroundColor DarkGray
            Write-Host $savedConfig.ProxyServer -ForegroundColor White
        }
        if (-not [string]::IsNullOrEmpty($savedConfig.ProxyBypassList)) {
            $txt_ProxyBypass.Text = $savedConfig.ProxyBypassList
        }
        if (-not [string]::IsNullOrEmpty($savedConfig.ProxyUsername)) {
            $txt_ProxyUsername.Text = $savedConfig.ProxyUsername
        }
        if (-not [string]::IsNullOrEmpty($savedConfig.ProxyPassword)) {
            try {
                $pwd_ProxyPassword.Password = [System.Text.Encoding]::UTF8.GetString(
                    [System.Convert]::FromBase64String($savedConfig.ProxyPassword))
            } catch { }
        }

        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "  No saved configuration found in registry." -ForegroundColor DarkYellow
        Write-Host ""
    }
} catch { }

#endregion Load Saved Settings

# Enable OS/Architecture change auto-refresh now that saved settings are restored
$script:SuppressModelRefresh = $false

# Auto-refresh models if previous selections were restored
# Deferred to ContentRendered so the Loading Sources modal appears over the main window
$script:AutoRefreshPending = ((Get-DATSelectedOEMs).Count -gt 0 -and $null -ne $cmb_OS.SelectedItem)

# Set sidebar logo image
$logoPath = Join-Path $UIPath "Assets\NewDatLogo.png"
$script:bitmapImage = $null
if (Test-Path $logoPath) {
    $script:bitmapImage = [System.Windows.Media.Imaging.BitmapImage]::new()
    $script:bitmapImage.BeginInit()
    $script:bitmapImage.UriSource = [Uri]::new($logoPath, [UriKind]::Absolute)
    $script:bitmapImage.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $script:bitmapImage.EndInit()
    $script:bitmapImage.Freeze()
    $imgLogo = $Window.FindName('img_Logo')
    if ($null -ne $imgLogo) {
        $imgLogo.Source = $script:bitmapImage
    }
}

# Read version from module manifest
$manifestPath = Join-Path $AppRoot "Modules\DriverAutomationToolCore\DriverAutomationToolCore.psd1"
$script:versionString = "v10.0.15"
if (Test-Path $manifestPath) {
    $manifestData = Import-PowerShellDataFile $manifestPath
    $ver = [version]$manifestData.ModuleVersion
    $script:versionString = "v$($ver.Major).$($ver.Minor).$($ver.Build)"
}

#region Splash Screen

# Build splash screen window programmatically
$script:splash = [System.Windows.Window]::new()
$script:splash.WindowStyle = 'None'
$script:splash.AllowsTransparency = $true
$script:splash.Background = [System.Windows.Media.Brushes]::Transparent
$script:splash.WindowStartupLocation = 'CenterScreen'
$script:splash.Width = 380
$script:splash.Height = 300
$script:splash.Topmost = $true
$script:splash.ResizeMode = 'NoResize'
$script:splash.ShowInTaskbar = $false

# Semi-transparent rounded card
$splashBorder = [System.Windows.Controls.Border]::new()
$splashBorder.Background = [System.Windows.Media.SolidColorBrush]::new(
    [System.Windows.Media.Color]::FromArgb(230, 30, 30, 30))
$splashBorder.CornerRadius = [System.Windows.CornerRadius]::new(20)
$splashBorder.Padding = [System.Windows.Thickness]::new(30, 24, 30, 24)
$splashBorder.HorizontalAlignment = 'Stretch'
$splashBorder.VerticalAlignment = 'Stretch'

# Drop shadow
$shadowEffect = [System.Windows.Media.Effects.DropShadowEffect]::new()
$shadowEffect.BlurRadius = 40
$shadowEffect.ShadowDepth = 0
$shadowEffect.Opacity = 0.6
$shadowEffect.Color = [System.Windows.Media.Colors]::Black
$splashBorder.Effect = $shadowEffect

$splashPanel = [System.Windows.Controls.StackPanel]::new()
$splashPanel.HorizontalAlignment = 'Center'
$splashPanel.VerticalAlignment = 'Center'

# Logo on splash
if ($null -ne $script:bitmapImage) {
    $splashLogo = [System.Windows.Controls.Image]::new()
    $splashLogo.Source = $script:bitmapImage
    $splashLogo.Height = 100
    $splashLogo.Stretch = [System.Windows.Media.Stretch]::Uniform
    $splashLogo.HorizontalAlignment = 'Center'
    $splashLogo.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $splashPanel.Children.Add($splashLogo) | Out-Null
}

# Driver Automation Tool text
$splashTitle = [System.Windows.Controls.TextBlock]::new()
$splashTitle.Text = "Driver Automation Tool"
$splashTitle.FontSize = 22
$splashTitle.FontWeight = [System.Windows.FontWeights]::Bold
$splashTitle.Foreground = [System.Windows.Media.Brushes]::White
$splashTitle.HorizontalAlignment = 'Center'
$splashTitle.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
$splashPanel.Children.Add($splashTitle) | Out-Null

# Version text
$splashVersionText = [System.Windows.Controls.TextBlock]::new()
$splashVersionText.Text = $script:versionString
$splashVersionText.FontSize = 12
$splashVersionText.Foreground = [System.Windows.Media.SolidColorBrush]::new(
    [System.Windows.Media.Color]::FromRgb(140, 140, 140))
$splashVersionText.HorizontalAlignment = 'Center'
$splashVersionText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 20)
$splashPanel.Children.Add($splashVersionText) | Out-Null

# Loading state indicator
$splashLoading = [System.Windows.Controls.TextBlock]::new()
$splashLoading.Text = "Reading Registry Settings..."
$splashLoading.FontSize = 11
$splashLoading.Foreground = [System.Windows.Media.SolidColorBrush]::new(
    [System.Windows.Media.Color]::FromRgb(100, 100, 100))
$splashLoading.HorizontalAlignment = 'Center'
$splashPanel.Children.Add($splashLoading) | Out-Null

$splashBorder.Child = $splashPanel
$script:splash.Content = $splashBorder

# Show splash with cycling state notices (1 second each), then close
$script:splash.Add_Loaded({
    $script:splashStates = @(
        'Starting Logging...',
        'Loading UI...',
        '$CLOSE'
    )
    $script:splashStateIndex = 0
    $script:splashTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:splashTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:splashTimer.Add_Tick({
        $state = $script:splashStates[$script:splashStateIndex]
        if ($state -eq '$CLOSE') {
            $script:splashTimer.Stop()
            $script:splash.Close()
        } else {
            $splashLoading.Text = $state
            $script:splashStateIndex++
        }
    })
    $script:splashTimer.Start()
})

$script:splash.ShowDialog() | Out-Null

#endregion Splash Screen

# Auto-connect Intune if App Registration (client credentials) mode was saved
if ($cmb_IntuneAuthMode.SelectedIndex -eq 2) {
    $autoTenantId = $txt_IntuneTenantId.Text.Trim()
    $autoAppId    = $txt_IntuneAppId.Text.Trim()
    $autoSecret   = $txt_IntuneClientSecret.Password
    if (-not [string]::IsNullOrEmpty($autoTenantId) -and
        -not [string]::IsNullOrEmpty($autoAppId) -and
        -not [string]::IsNullOrEmpty($autoSecret)) {
        Write-Host "  Intune        : " -NoNewline -ForegroundColor DarkGray
        Write-Host "Auto-connecting with saved client credentials..." -ForegroundColor Cyan
        Write-DATActivityLog "Auto-connecting to Intune with saved client credentials (tenant: $autoTenantId)" -Level Info
        $autoResult = Connect-DATIntuneGraphClientCredential -TenantId $autoTenantId -AppId $autoAppId -ClientSecret $autoSecret
        if ($autoResult.Success) {
            Update-DATIntuneAuthUI
            $script:IntuneTokenTimer.Start()
            Invoke-DATIntuneAppRefresh
            Write-Host "  Intune        : " -NoNewline -ForegroundColor DarkGray
            Write-Host "Connected" -ForegroundColor Green
            Write-DATActivityLog "Intune auto-connect successful (tenant: $autoTenantId)" -Level Success
            Invoke-DATIntunePermissionCheckAsync -OnComplete {
                param ($permResult)
                if ($permResult.Granted) {
                    Write-DATActivityLog "Auto-connect: all permissions granted" -Level Success
                } else {
                    $denied = ($permResult.Permissions | Where-Object { $_.Status -ne 'Granted' })
                    $deniedNames = ($denied | ForEach-Object { $_.Name }) -join ', '
                    Write-DATActivityLog "Auto-connect: missing permissions: $deniedNames" -Level Warn
                }
            }
        } else {
            Write-Host "  Intune        : " -NoNewline -ForegroundColor DarkGray
            Write-Host "Auto-connect failed: $($autoResult.Error)" -ForegroundColor Red
            Write-DATActivityLog "Intune auto-connect failed: $($autoResult.Error)" -Level Warn
        }
    }
}

# If platform is Intune and auth mode is interactive (Browser or Device Code),
# navigate straight to the Intune Environment view so the user can re-authenticate
if ($cmb_Platform.SelectedItem -and $cmb_Platform.SelectedItem.Content -eq 'Intune' -and
    $cmb_IntuneAuthMode.SelectedIndex -in @(0, 1)) {
    Write-Host "  Intune        : " -NoNewline -ForegroundColor DarkGray
    Write-Host "Interactive auth required -- navigating to Intune Environment" -ForegroundColor Cyan
    Write-DATActivityLog "Intune interactive auth mode detected -- redirecting to Environment view" -Level Info
    # Expand the Intune sub-panel and show the Environment view
    if ($configMgrSubPanel.Visibility -eq 'Visible') {
        Start-DATPanelAnimation -Panel $configMgrSubPanel -Expand $false
    }
    Start-DATPanelAnimation -Panel $intuneSubPanel -Expand $true
    Set-DATActiveView -ViewName 'view_IntuneSettings' -NavButtonName 'nav_IntuneAuth'
}

# Shutdown handler — shows a modal with status messages during exit
$script:WindowClosing = $false
$Window.Add_Closing({
    $script:WindowClosing = $true

    # Stop all running timers to prevent disposed-object access
    if ($script:BuildProgressTimer) { try { $script:BuildProgressTimer.Stop() } catch { } }
    if ($script:CustomBuildTimer) { try { $script:CustomBuildTimer.Stop() } catch { } }
    if ($script:RefreshTimer) { try { $script:RefreshTimer.Stop() } catch { } }
    if ($script:hpcmslInstallTimer) { try { $script:hpcmslInstallTimer.Stop() } catch { } }

    # Gather temp cleanup info before showing modal
    $cleanTempEnabled = $chk_CleanTempOnExit.IsChecked -eq $true
    $tempPath = $txt_TempStorage.Text
    $tempItems = $null
    if ($cleanTempEnabled -and -not [string]::IsNullOrWhiteSpace($tempPath) -and (Test-Path $tempPath)) {
        $tempItems = Get-ChildItem -Path $tempPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $tempItems -or $tempItems.Count -eq 0) { $tempItems = $null }
    }

    # Build shutdown modal (same visual style as splash screen)
    $shutdownWin = [System.Windows.Window]::new()
    $shutdownWin.WindowStyle = 'None'
    $shutdownWin.AllowsTransparency = $true
    $shutdownWin.Background = [System.Windows.Media.Brushes]::Transparent
    $shutdownWin.WindowStartupLocation = 'CenterScreen'
    $shutdownWin.Width = 460
    $shutdownWin.Height = 300
    $shutdownWin.Topmost = $true
    $shutdownWin.ResizeMode = 'NoResize'
    $shutdownWin.ShowInTaskbar = $false

    $sdBorder = [System.Windows.Controls.Border]::new()
    $sdBorder.Background = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromArgb(230, 30, 30, 30))
    $sdBorder.CornerRadius = [System.Windows.CornerRadius]::new(20)
    $sdBorder.Padding = [System.Windows.Thickness]::new(36, 28, 36, 28)
    $sdBorder.HorizontalAlignment = 'Stretch'
    $sdBorder.VerticalAlignment = 'Stretch'
    $sdShadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $sdShadow.BlurRadius = 40; $sdShadow.ShadowDepth = 0; $sdShadow.Opacity = 0.6
    $sdShadow.Color = [System.Windows.Media.Colors]::Black
    $sdBorder.Effect = $sdShadow

    $sdPanel = [System.Windows.Controls.StackPanel]::new()
    $sdPanel.HorizontalAlignment = 'Center'
    $sdPanel.VerticalAlignment = 'Center'

    # Icon — E7E8 = PowerButton / exit
    $sdIcon = [System.Windows.Controls.TextBlock]::new()
    $sdIcon.Text = [char]0xE7E8
    $sdIcon.FontFamily = [System.Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $sdIcon.FontSize = 32
    $sdIcon.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.ColorConverter]::ConvertFromString('#FFAA44'))
    $sdIcon.HorizontalAlignment = 'Center'
    $sdIcon.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $sdPanel.Children.Add($sdIcon) | Out-Null

    # Title
    $sdTitle = [System.Windows.Controls.TextBlock]::new()
    $sdTitle.Text = "Shutting Down"
    $sdTitle.FontSize = 18
    $sdTitle.FontWeight = [System.Windows.FontWeights]::Bold
    $sdTitle.Foreground = [System.Windows.Media.Brushes]::White
    $sdTitle.HorizontalAlignment = 'Center'
    $sdTitle.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)
    $sdPanel.Children.Add($sdTitle) | Out-Null

    # Subtitle
    $sdSubtitle = [System.Windows.Controls.TextBlock]::new()
    $sdSubtitle.Text = "Please wait while cleanup tasks complete"
    $sdSubtitle.FontSize = 12
    $sdSubtitle.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromRgb(140, 140, 140))
    $sdSubtitle.HorizontalAlignment = 'Center'
    $sdSubtitle.Margin = [System.Windows.Thickness]::new(0, 0, 0, 16)
    $sdPanel.Children.Add($sdSubtitle) | Out-Null

    # Status label
    $sdStatus = [System.Windows.Controls.TextBlock]::new()
    $sdStatus.Text = "Preparing..."
    $sdStatus.FontSize = 11
    $sdStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color]::FromRgb(100, 100, 100))
    $sdStatus.HorizontalAlignment = 'Center'
    $sdStatus.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
    $sdStatus.MaxWidth = 380
    $sdPanel.Children.Add($sdStatus) | Out-Null

    $sdBorder.Child = $sdPanel
    $shutdownWin.Content = $sdBorder

    # Helper to update status and pump the dispatcher so the UI redraws
    $updateStatus = {
        param([string]$msg)
        $sdStatus.Text = $msg
        $shutdownWin.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [action]{})
    }

    # Run all shutdown tasks inside the Loaded event so the modal is visible first
    $shutdownWin.Add_Loaded({
        $shutdownWin.Dispatcher.InvokeAsync([action]{

            # 1. Save model selections
            & $updateStatus "Saving model selections..."
            try { Save-DATModelSelections } catch { }

            # 2. Kill orphaned DISM/dismhost processes
            $dismProcs = @()
            foreach ($procName in @('dismhost', 'dism')) {
                $dismProcs += @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
            }
            if ($dismProcs.Count -gt 0) {
                & $updateStatus "Stopping DISM processes ($($dismProcs.Count) found)..."
                foreach ($proc in $dismProcs) {
                    try { $proc.Kill() } catch { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
                }
            }

            # 3. Clean up DISM mount registry state
            $dismMountKey = 'HKLM:\SOFTWARE\Microsoft\WIMMount\Mounted Images'
            $hasMountedImages = (Test-Path $dismMountKey) -and
                @(Get-ChildItem $dismMountKey -ErrorAction SilentlyContinue).Count -gt 0
            if ($hasMountedImages) {
                & $updateStatus "Cleaning DISM mount registry entries..."
                Get-ChildItem $dismMountKey -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }

            # 4. Run dism.exe /Cleanup-Wim only if mounted images were found
            if ($hasMountedImages) {
                & $updateStatus "Running DISM image cleanup..."
                try {
                    $dismClean = Start-Process -FilePath "$env:SystemRoot\System32\dism.exe" `
                        -ArgumentList '/Cleanup-Wim' -WindowStyle Hidden -PassThru
                    $dismClean.WaitForExit(10000)
                    if (-not $dismClean.HasExited) { $dismClean.Kill() }
                } catch { }
            }

            # 5. Clean temp folder (if enabled)
            if ($null -ne $tempItems) {
                & $updateStatus "Cleaning temporary storage ($($tempItems.Count) items)..."
                $shutdownWin.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [action]{})

                foreach ($item in $tempItems) {
                    try {
                        $itemName = $item.Name
                        $itemType = if ($item.PSIsContainer) { 'folder' } else { 'file' }
                        & $updateStatus "Removing $itemType`: $itemName"

                        Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                        Write-DATLogEntry -Value "Cleanup: Removed $itemType - $($item.FullName)" -Severity 1
                    } catch {
                        Write-DATLogEntry -Value "[Warning] - Cleanup: Failed to remove $($item.FullName): $($_.Exception.Message)" -Severity 2
                    }
                }
                Write-DATLogEntry -Value "Temp folder cleanup finished: $tempPath" -Severity 1
            }

            & $updateStatus "Shutdown complete"
            $shutdownWin.Dispatcher.InvokeAsync([action]{
                $shutdownWin.Close()
            }, [System.Windows.Threading.DispatcherPriority]::Background)
        }, [System.Windows.Threading.DispatcherPriority]::Background)
    })

    $shutdownWin.ShowDialog() | Out-Null
})

# Show the window
# If EULA not yet accepted, navigate to About page on first render so the user sees it immediately
$eulaAtStartup = (Get-ItemProperty -Path $global:RegPath -Name "EULAAccepted" -ErrorAction SilentlyContinue).EULAAccepted
$Window.Add_ContentRendered({
    if ($eulaAtStartup -ne "True") {
        Set-DATActiveView -ViewName 'view_About' -NavButtonName 'nav_About'
        $txt_EulaWarning.Visibility = 'Visible'
        Write-DATActivityLog "EULA not accepted -- navigated to About page on startup" -Level Warn
    }
    # Trigger auto-refresh now that the main window is visible
    if ($script:AutoRefreshPending) {
        $script:AutoRefreshPending = $false
        Invoke-DATRefreshModelsClick
    }
})
$Window.ShowDialog() | Out-Null
