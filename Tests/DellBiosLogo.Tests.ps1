BeforeAll {
    $script:hadRegPath = $null -ne (Get-Variable -Name RegPath -Scope Global -ErrorAction SilentlyContinue)
    $script:savedRegPath = $global:RegPath
    $global:RegPath = 'HKLM:\DellBiosLogoGuiTests'
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repoRoot 'Driver Automation Tool\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1'
    $moduleManifestPath = Join-Path $repoRoot 'Driver Automation Tool\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psd1'
    $templatePath = Join-Path $repoRoot 'Driver Automation Tool\Modules\DriverAutomationToolCore\Templates\Install-BIOS.ps1'
    $headlessPath = Join-Path $repoRoot 'Driver Automation Tool\Start-DATHeadlessBuild.ps1'
    $coreAst = [Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$null, [ref]$null)
    foreach ($name in @('Resolve-DATDellBiosLogoAction', 'Get-DATDellBiosLogoSwitch', 'Export-DATBuildConfig', 'Import-DATBuildConfig')) {
        $node = $coreAst.Find({
            param($item)
            $item -is [Management.Automation.Language.FunctionDefinitionAst] -and $item.Name -eq $name
        }.GetNewClosure(), $true)
        if ($null -eq $node) { throw "Core function not found: $name" }
        . ([scriptblock]::Create($node.Extent.Text))
    }

    $uiPath = Join-Path $repoRoot 'Driver Automation Tool\UI\MainApplication.ps1'
    $uiAst = [Management.Automation.Language.Parser]::ParseFile($uiPath, [ref]$null, [ref]$null)
    foreach ($name in @('Set-DATDellBiosLogoActionSelection', 'Sync-DATDellBiosLogoActionSelection')) {
        $node = $uiAst.Find({
            param($item)
            $item -is [Management.Automation.Language.FunctionDefinitionAst] -and $item.Name -eq $name
        }.GetNewClosure(), $true)
        if ($null -eq $node) { throw "UI function not found: $name" }
        . ([scriptblock]::Create($node.Extent.Text))
    }

    $templateAst = [Management.Automation.Language.Parser]::ParseFile($templatePath, [ref]$null, [ref]$null)
    $argumentNode = $templateAst.Find({
        param($item)
        $item -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $item.Name -eq 'Set-DATDellBiosLogoArguments'
    }, $true)
    if ($null -eq $argumentNode) { throw 'Dell BIOS logo argument helper not found in install template' }
    . ([scriptblock]::Create($argumentNode.Extent.Text))

    $script:registryWrites = @()
    $script:activityEntries = @()
    function Set-DATRegistryValue {
        param ([string]$Name, [object]$Value, [string]$Type)
        $script:registryWrites += [pscustomobject]@{ Name = $Name; Value = $Value; Type = $Type }
    }
    function Write-DATActivityLog {
        param ([string]$Message, [string]$Level)
        $script:activityEntries += [pscustomobject]@{ Message = $Message; Level = $Level }
    }
    function Write-DATLogEntry {
        param ([string]$Value, [int]$Severity)
    }
}

AfterAll {
    if ($script:hadRegPath) {
        $global:RegPath = $script:savedRegPath
    } else {
        Remove-Variable -Name RegPath -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe 'Dell BIOS logo actions' {
    It 'defaults missing, null, and empty values to no management' {
        (Resolve-DATDellBiosLogoAction) | Should -BeExactly 'DoNotManage'
        (Get-DATDellBiosLogoSwitch) | Should -BeExactly ''
        (Get-DATDellBiosLogoSwitch -Action $null) | Should -BeExactly ''
        (Get-DATDellBiosLogoSwitch -Action '') | Should -BeExactly ''
    }

    It 'maps <Action> to exactly <LogoSwitch>' -ForEach @(
        @{ Action = 'DoNotManage'; LogoSwitch = '' }
        @{ Action = 'Preserve'; LogoSwitch = '/keeplogo' }
        @{ Action = 'Restore'; LogoSwitch = '/DellLogo' }
    ) {
        (Get-DATDellBiosLogoSwitch -Action $Action) | Should -BeExactly $LogoSwitch
    }

    It 'rejects unsupported actions, including custom-logo application' {
        { Get-DATDellBiosLogoSwitch -Action 'Apply' } | Should -Throw '*Invalid Dell BIOS logo action*'
        { Get-DATDellBiosLogoSwitch -Action 'Unknown' } | Should -Throw '*Invalid Dell BIOS logo action*'
    }

    It 'replaces duplicate and conflicting complete switch arguments without changing other arguments' {
        $arguments = @(
            '/s'
            '/l=C:\Temp Folder\BIOS.log'
            '/p=password with spaces'
            '/keeplogo'
            '/DellLogo'
            '/keeplogo'
        )

        $result = @(Set-DATDellBiosLogoArguments -Arguments $arguments -LogoSwitch '/keeplogo')
        $result.Count | Should -Be 4
        $result[0] | Should -BeExactly '/s'
        $result[1] | Should -BeExactly '/l=C:\Temp Folder\BIOS.log'
        $result[2] | Should -BeExactly '/p=password with spaces'
        $result[3] | Should -BeExactly '/keeplogo'
        @($result | Where-Object { $_ -match '(?i)^/(?:keeplogo|delllogo)$' }).Count | Should -Be 1
    }

    It 'removes existing logo switches when the action is DoNotManage' {
        $result = @(Set-DATDellBiosLogoArguments -Arguments @('/s', '/keeplogo', '/DellLogo', '/p=password with spaces') -LogoSwitch '')
        $result.Count | Should -Be 2
        $result[0] | Should -BeExactly '/s'
        $result[1] | Should -BeExactly '/p=password with spaces'
    }

    It 'rejects a switch outside the supported Dell logo actions' {
        { Set-DATDellBiosLogoArguments -Arguments @('/s') -LogoSwitch '/applylogo' } |
            Should -Throw '*Unsupported Dell BIOS logo switch*'
    }

    It 'exports the logo action resolver for GUI callers' {
        $moduleManifest = Import-PowerShellDataFile -Path $moduleManifestPath
        $moduleManifest.FunctionsToExport | Should -Contain 'Resolve-DATDellBiosLogoAction'
    }

    It 'passes the action through headless builds and replaces the template switch only for Dell BIOS packages' {
        $headlessText = Get-Content -LiteralPath $headlessPath -Raw
        $coreText = Get-Content -LiteralPath $modulePath -Raw
        $templateText = Get-Content -LiteralPath $templatePath -Raw

        $headlessText | Should -Match 'DellBiosLogoAction\s*=\s*\$config\.DellBiosLogoAction'
        $coreText | Should -Match 'DellBiosLogoAction\s*=\s*\$DellBiosLogoAction'
        $coreText.Contains('$UpdateType -eq ''BIOS'' -and $OEM -ieq ''Dell''') | Should -BeTrue
        $coreText | Should -Match '\{\{DELL_BIOS_LOGO_SWITCH\}\}'
        $templateText.Contains('Set-DATDellBiosLogoArguments -Arguments $flashArgList -LogoSwitch ''{{DELL_BIOS_LOGO_SWITCH}}''') | Should -BeTrue
    }

    It 'generates logo arguments only for Dell BIOS packages' {
        Import-Module -Name $moduleManifestPath -Force -ErrorAction Stop
        try {
            $cases = @(
                @{ OEM = 'Dell'; Type = 'BIOS'; Action = 'DoNotManage'; Expected = "-LogoSwitch ''" }
                @{ OEM = 'Dell'; Type = 'BIOS'; Action = 'Preserve'; Expected = "-LogoSwitch '/keeplogo'" }
                @{ OEM = 'Dell'; Type = 'BIOS'; Action = 'Restore'; Expected = "-LogoSwitch '/DellLogo'" }
                @{ OEM = 'HP'; Type = 'BIOS'; Action = 'Preserve'; Expected = "-LogoSwitch ''" }
                @{ OEM = 'Dell'; Type = 'Drivers'; Action = 'Preserve'; Expected = $null }
            )

            foreach ($case in $cases) {
                $outputPath = Join-Path $TestDrive "$($case.OEM)-$($case.Type)-$($case.Action).ps1"
                New-DATIntuneInstallScript -OutputPath $outputPath -OEM $case.OEM -Model 'RegressionModel' `
                    -OS 'Windows 11' -Version '1.2.3' -UpdateType $case.Type -DisableToast -DisableRestart `
                    -DellBiosLogoAction $case.Action | Out-Null
                $generated = Get-Content -LiteralPath $outputPath -Raw
                $logoLines = @($generated -split "`r?`n" | Where-Object { $_ -match 'Set-DATDellBiosLogoArguments -Arguments' })

                if ($null -eq $case.Expected) {
                    $logoLines.Count | Should -Be 0
                } else {
                    $logoLines.Count | Should -Be 1
                    $logoLines[0] | Should -BeLike "*$($case.Expected)*"
                }

                $tokens = $null
                $errors = $null
                [Management.Automation.Language.Parser]::ParseFile($outputPath, [ref]$tokens, [ref]$errors) | Out-Null
                $errors.Count | Should -Be 0
            }
        } finally {
            Remove-Module DriverAutomationToolCore -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Dell BIOS logo configuration round trips' {
    BeforeEach {
        $configPath = Join-Path $TestDrive "BuildConfig-$([guid]::NewGuid().ToString('N')).json"
        $exportParams = @{
            ConfigPath = $configPath
            Platform = 'Download Only'
            OS = 'Windows 11'
            Architecture = 'x64'
            Models = @([pscustomobject]@{ OEM = 'Dell'; Model = 'Latitude 7455' })
        }
    }

    It 'defaults configurations written before the setting existed to DoNotManage' {
        Export-DATBuildConfig @exportParams
        $raw = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $raw.PSObject.Properties.Remove('DellBiosLogoAction')
        [System.IO.File]::WriteAllText($configPath, ($raw | ConvertTo-Json -Depth 5))

        (Import-DATBuildConfig -ConfigPath $configPath).DellBiosLogoAction | Should -BeExactly 'DoNotManage'
    }

    It 'round trips supported action <Action>' -ForEach @(
        @{ Action = 'DoNotManage' }
        @{ Action = 'Preserve' }
        @{ Action = 'Restore' }
    ) {
        Export-DATBuildConfig @exportParams -DellBiosLogoAction $Action
        (Import-DATBuildConfig -ConfigPath $configPath).DellBiosLogoAction | Should -BeExactly $Action
    }

    It 'defaults an empty action to DoNotManage' {
        Export-DATBuildConfig @exportParams -DellBiosLogoAction ''
        (Import-DATBuildConfig -ConfigPath $configPath).DellBiosLogoAction | Should -BeExactly 'DoNotManage'
    }

    It 'rejects an explicit JSON null action' {
        Export-DATBuildConfig @exportParams
        $raw = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $raw.DellBiosLogoAction = $null
        [System.IO.File]::WriteAllText($configPath, ($raw | ConvertTo-Json -Depth 5))

        { Import-DATBuildConfig -ConfigPath $configPath } | Should -Throw "*Invalid Dell BIOS logo action 'null'*"
    }

    It 'rejects an unsupported action in an explicit build config' {
        Export-DATBuildConfig @exportParams
        $raw = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $raw.DellBiosLogoAction = 'Apply'
        [System.IO.File]::WriteAllText($configPath, ($raw | ConvertTo-Json -Depth 5))

        { Import-DATBuildConfig -ConfigPath $configPath } | Should -Throw '*Invalid Dell BIOS logo action*'
    }
}

Describe 'Dell BIOS logo GUI synchronization' {
    BeforeEach {
        $script:registryWrites = @()
        $script:activityEntries = @()
        $script:cmb_DellBiosLogoAction = [pscustomobject]@{
            Items = @(
                [pscustomobject]@{ Tag = 'DoNotManage' }
                [pscustomobject]@{ Tag = 'Preserve' }
                [pscustomobject]@{ Tag = 'Restore' }
            )
            SelectedItem = [pscustomobject]@{ Tag = 'DoNotManage' }
        }
    }

    It 'loads the imported action into the selector and registry' {
        $result = Sync-DATDellBiosLogoActionSelection -ConfigContent '"DellBiosLogoAction"="Preserve"' -ImportedAction 'Preserve'

        $script:cmb_DellBiosLogoAction.SelectedItem.Tag | Should -BeExactly 'Preserve'
        $script:registryWrites[-1].Value | Should -BeExactly 'Preserve'
        $result.WasInvalid | Should -BeFalse
    }

    It 'resets a legacy import without the setting instead of retaining a stale selection' {
        $script:cmb_DellBiosLogoAction.SelectedItem = $script:cmb_DellBiosLogoAction.Items[2]
        $result = Sync-DATDellBiosLogoActionSelection -ConfigContent '"DisableRestart"=dword:00000000' -ImportedAction 'Restore'

        $script:cmb_DellBiosLogoAction.SelectedItem.Tag | Should -BeExactly 'DoNotManage'
        $script:registryWrites[-1].Value | Should -BeExactly 'DoNotManage'
        $result.WasInvalid | Should -BeFalse
    }

    It 'resets an invalid imported action and records a warning' {
        $result = Sync-DATDellBiosLogoActionSelection -ConfigContent '"DellBiosLogoAction"="Apply"' -ImportedAction 'Apply'

        $script:cmb_DellBiosLogoAction.SelectedItem.Tag | Should -BeExactly 'DoNotManage'
        $script:registryWrites[-1].Value | Should -BeExactly 'DoNotManage'
        $result.WasInvalid | Should -BeTrue
        $script:activityEntries[-1].Level | Should -BeExactly 'Warn'
    }
}
