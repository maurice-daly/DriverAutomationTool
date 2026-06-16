<#
    Theme definitions for Driver Automation Tool v10.0
    Provides Dark and Light themes with rounded, modern aesthetics
#>

$script:Themes = @{
    Dark = @{
        # Window — IntuneGuardian dark navy base
        WindowBackground       = "#0F172A"
        WindowForeground       = "#F8FAFC"
        WindowBorder           = "#334155"

        # Sidebar — IntuneGuardian sidebar dark
        SidebarBackground      = "#1A1A1A"
        SidebarForeground      = "#F5F5F5"
        SidebarHover           = "#334155"
        SidebarActive          = "#1E293B"
        SidebarAccent          = "#0B84F1"

        # Cards / Panels
        CardBackground         = "#1E293B"
        CardBorder             = "#334155"
        CardShadow             = "#0F172A"

        # Buttons
        ButtonPrimary          = "#0B84F1"
        ButtonPrimaryHover     = "#3B82F6"
        ButtonPrimaryForeground = "#FFFFFF"
        ButtonSecondary        = "#334155"
        ButtonSecondaryHover   = "#475569"
        ButtonSecondaryForeground = "#F8FAFC"
        ButtonDanger           = "#E74856"
        ButtonDangerHover      = "#F87171"
        ButtonSuccess          = "#107C10"
        ButtonSuccessHover     = "#16A34A"

        # DataGrid
        GridBackground         = "#1A1A1A"
        GridAlternate          = "#0F172A"
        GridHeader             = "#282828"
        GridHeaderForeground   = "#F5F5F5"
        GridBorder             = "#334155"
        GridSelection          = "#334155"
        GridSelectionForeground = "#F8FAFC"

        # Input
        InputBackground        = "#141E33"
        InputForeground        = "#F8FAFC"
        InputBorder            = "#334155"
        InputFocusBorder       = "#0B84F1"
        InputPlaceholder       = "#CBD5E1"

        # ComboBox
        ComboBackground        = "#1E293B"
        ComboForeground        = "#F8FAFC"
        ComboBorder            = "#334155"
        ComboDropdownBg        = "#0F172A"
        ComboHover             = "#334155"

        # CheckBox
        CheckBackground        = "#1E293B"
        CheckBorder            = "#334155"
        CheckMark              = "#0B84F1"

        # ProgressBar
        ProgressBackground     = "#334155"
        ProgressForeground     = "#22C55E"

        # Status — IntuneGuardian semantic colors
        StatusInfo             = "#0B84F1"
        StatusSuccess          = "#4ADE80"
        StatusWarning          = "#FFAA44"
        StatusError            = "#E74856"

        # ScrollBar
        ScrollTrack            = "#0F172A"
        ScrollThumb            = "#334155"
        ScrollThumbHover       = "#475569"

        # Tab
        TabInactive            = "#1A1A1A"
        TabActive              = "#1E293B"
        TabBorder              = "#334155"
        TabForeground          = "#A1A1A1"
        TabActiveForeground    = "#F8FAFC"

        # Accent
        AccentColor            = "#0B84F1"
        AccentColorLight       = "#6DB3F2"

        # Modal / Pipeline
        PipelinePending        = "#4B5563"
        PipelineConnector      = "#374151"
    }
    Light = @{
        # Window — cool grey surface so white cards stand out
        WindowBackground       = "#EEF2F6"
        WindowForeground       = "#0F172A"
        WindowBorder           = "#CBD5E1"

        # Sidebar — distinct panel darker than main surface
        SidebarBackground      = "#E0E5EC"
        SidebarForeground      = "#334155"
        SidebarHover           = "#CBD5E1"
        SidebarActive          = "#CDD5DF"
        SidebarAccent          = "#0078D4"

        # Cards / Panels — white cards pop against grey surface
        CardBackground         = "#FFFFFF"
        CardBorder             = "#C8D1DC"
        CardShadow             = "#D5DBE4"

        # Buttons
        ButtonPrimary          = "#0078D4"
        ButtonPrimaryHover     = "#106EBE"
        ButtonPrimaryForeground = "#F8FAFC"
        ButtonSecondary        = "#DCE2EA"
        ButtonSecondaryHover   = "#CBD5E1"
        ButtonSecondaryForeground = "#1E293B"
        ButtonDanger           = "#E74856"
        ButtonDangerHover      = "#DC2626"
        ButtonSuccess          = "#107C10"
        ButtonSuccessHover     = "#16A34A"

        # DataGrid
        GridBackground         = "#FFFFFF"
        GridAlternate          = "#F3F6F9"
        GridHeader             = "#E3E8EF"
        GridHeaderForeground   = "#1E293B"
        GridBorder             = "#CBD5E1"
        GridSelection          = "#D0DAEA"
        GridSelectionForeground = "#0F172A"

        # Input — subtle grey so fields are distinguishable
        InputBackground        = "#F5F7FA"
        InputForeground        = "#0F172A"
        InputBorder            = "#B8C4D0"
        InputFocusBorder       = "#0078D4"
        InputPlaceholder       = "#64748B"

        # ComboBox
        ComboBackground        = "#F5F7FA"
        ComboForeground        = "#0F172A"
        ComboBorder            = "#B8C4D0"
        ComboDropdownBg        = "#F0F3F7"
        ComboHover             = "#E2E8F0"

        # CheckBox
        CheckBackground        = "#F5F7FA"
        CheckBorder            = "#B8C4D0"
        CheckMark              = "#0078D4"

        # ProgressBar
        ProgressBackground     = "#D5DBE4"
        ProgressForeground     = "#107C10"

        # Status — IntuneGuardian semantic colors
        StatusInfo             = "#0078D4"
        StatusSuccess          = "#107C10"
        StatusWarning          = "#FFAA44"
        StatusError            = "#E74856"

        # ScrollBar
        ScrollTrack            = "#E8ECF1"
        ScrollThumb            = "#B8C4D0"
        ScrollThumbHover       = "#94A3B8"

        # Tab
        TabInactive            = "#E3E8EF"
        TabActive              = "#FFFFFF"
        TabBorder              = "#CBD5E1"
        TabForeground          = "#64748B"
        TabActiveForeground    = "#0F172A"

        # Accent
        AccentColor            = "#0078D4"
        AccentColorLight       = "#6DB3F2"

        # Modal / Pipeline
        PipelinePending        = "#C8D1DC"
        PipelineConnector      = "#D5DBE4"
    }
}

function Get-DATTheme {
    param ([ValidateSet('Dark', 'Light')][string]$ThemeName = 'Dark')
    return $script:Themes[$ThemeName]
}

function Get-DATThemeResourceDictionary {
    param ([ValidateSet('Dark', 'Light')][string]$ThemeName = 'Dark')

    $theme = $script:Themes[$ThemeName]
    $resources = New-Object System.Windows.ResourceDictionary

    foreach ($key in $theme.Keys) {
        $brush = New-Object System.Windows.Media.SolidColorBrush
        $brush.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($theme[$key])
        $brush.Freeze()
        $resources.Add($key, $brush)
    }

    return $resources
}
