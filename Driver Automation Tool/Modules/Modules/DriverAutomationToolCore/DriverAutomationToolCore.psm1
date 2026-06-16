<#
    ===========================================================================
     Created by:    Maurice Daly
     Organization:  MSEndpointMgr / Patch My PC
     Filename:      DriverAutomationToolCore.psm1
     Purpose:       Core functions for Driver Automation Tool v2.0
     Version:       10.0.15.0
    ===========================================================================
#>

# Requires TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# HPCMSL update check guard -- only check PSGallery once per module load
$script:HPCMSLUpdateChecked = $false

# Ensure System.Net.Http is available (required on PS 5.1 / Server 2016)
if ($PSVersionTable.PSVersion.Major -le 5) {
    try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch { }
}

#region Variables

[version]$global:ScriptRelease = "10.0.15.0"
$global:ScriptBuildDate = "20-04-2026"
$global:ReleaseNotesURL = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/DriverAutomationToolNotes.txt"
$OEMLinksURL = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/OEMLinks.xml"

# Path variables
[string]$global:RegPath = "HKLM:\SOFTWARE\DriverAutomationTool"
[string]$global:ProductName = "DriverAutomationTool"
[string]$global:ExecutionMode = if ([Environment]::UserInteractive -eq $false) { 'Scheduled Task' } else { 'UI Driven' }

function Get-DATScriptDirectory {
    [OutputType([string])]
    param ()
    if ($null -ne $hostinvocation) {
        Split-Path $hostinvocation.MyCommand.path
    } else {
        Split-Path $script:MyInvocation.MyCommand.Path
    }
}

# Determine install directory
if ([boolean](Test-Path -Path $global:RegPath -ErrorAction SilentlyContinue) -eq $true) {
    $global:ScriptDirectory = (Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue).InstallDirectory
}
if ([string]::IsNullOrEmpty($global:ScriptDirectory) -or $global:ScriptDirectory -like "C:\Windows\Temp*") {
    [string]$global:ScriptDirectory = Join-Path -Path $env:SystemDrive -ChildPath "Program Files\MSEndpointMgr\Driver Automation Tool"
}

[string]$global:TempDirectory = Join-Path -Path $global:ScriptDirectory -ChildPath "Temp"
[string]$global:LogDirectory = Join-Path -Path $global:ScriptDirectory -ChildPath "Logs"
[string]$global:ToolsDirectory = Join-Path -Path $global:ScriptDirectory -ChildPath "Tools"

#endregion Variables

#region Proxy Configuration

function Get-DATProxySettings {
    <#
    .SYNOPSIS
        Reads proxy configuration from registry.
    .OUTPUTS
        Hashtable with Mode, Server, BypassList, Username, Password keys.
    #>
    $reg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
    @{
        Mode       = if ($reg -and $reg.ProxyMode) { $reg.ProxyMode } else { 'System' }
        Server     = if ($reg -and $reg.ProxyServer) { $reg.ProxyServer } else { '' }
        BypassList = if ($reg -and $reg.ProxyBypassList) { $reg.ProxyBypassList } else { '' }
        Username   = if ($reg -and $reg.ProxyUsername) { $reg.ProxyUsername } else { '' }
        Password   = if ($reg -and $reg.ProxyPassword) {
            try { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($reg.ProxyPassword)) } catch { '' }
        } else { '' }
    }
}

function Get-DATWebRequestProxy {
    <#
    .SYNOPSIS
        Returns a hashtable suitable for splatting into Invoke-WebRequest / Invoke-RestMethod.
        Handles System, Manual, and None proxy modes.
    #>
    [OutputType([hashtable])]
    param()
    $cfg = Get-DATProxySettings
    $result = @{}
    switch ($cfg.Mode) {
        'None' {
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                $result = @{ NoProxy = $true }
            }
            break
        }
        'Manual' {
            if (-not [string]::IsNullOrWhiteSpace($cfg.Server)) {
                $result = @{ Proxy = $cfg.Server }
                if (-not [string]::IsNullOrWhiteSpace($cfg.Username)) {
                    $result['ProxyCredential'] = [System.Management.Automation.PSCredential]::new(
                        $cfg.Username,
                        (ConvertTo-SecureString $cfg.Password -AsPlainText -Force))
                } else {
                    $result['ProxyUseDefaultCredentials'] = $true
                }
            }
            break
        }
    }
    $result
}

function Get-DATHttpClientHandler {
    <#
    .SYNOPSIS
        Creates a configured HttpClientHandler with proxy settings applied.
    #>
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate

    $cfg = Get-DATProxySettings
    switch ($cfg.Mode) {
        'None' {
            $handler.UseProxy = $false
        }
        'Manual' {
            if (-not [string]::IsNullOrWhiteSpace($cfg.Server)) {
                $handler.UseProxy = $true
                $webProxy = [System.Net.WebProxy]::new($cfg.Server)
                $webProxy.BypassProxyOnLocal = $true
                if (-not [string]::IsNullOrWhiteSpace($cfg.BypassList)) {
                    $webProxy.BypassList = @($cfg.BypassList -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                }
                if (-not [string]::IsNullOrWhiteSpace($cfg.Username)) {
                    $webProxy.Credentials = [System.Net.NetworkCredential]::new($cfg.Username, $cfg.Password)
                } else {
                    $webProxy.UseDefaultCredentials = $true
                }
                $handler.Proxy = $webProxy
            }
        }
        # 'System' -- handler uses default proxy automatically
    }

    return $handler
}

function Get-DATCurlProxyArgs {
    <#
    .SYNOPSIS
        Returns a string of curl proxy arguments based on configured proxy settings.
    #>
    $cfg = Get-DATProxySettings
    switch ($cfg.Mode) {
        'None'   { return '--noproxy "*"' }
        'Manual' {
            if ([string]::IsNullOrWhiteSpace($cfg.Server)) { return '' }
            $args = "--proxy `"$($cfg.Server)`""
            if (-not [string]::IsNullOrWhiteSpace($cfg.Username)) {
                $args += " --proxy-user `"$($cfg.Username):$($cfg.Password)`""
            }
            return $args
        }
        default  { return '' }
    }
}

function Test-DATProxyConnection {
    <#
    .SYNOPSIS
        Tests connectivity through the configured proxy by hitting a known endpoint.
    .OUTPUTS
        Hashtable with Success (bool) and Message (string).
    #>
    $proxyParams = Get-DATWebRequestProxy
    try {
        $null = Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/DriverAutomationToolRev.txt' `
            -UseBasicParsing -TimeoutSec 15 @proxyParams -ErrorAction Stop
        return @{ Success = $true; Message = "Connection successful" }
    } catch {
        return @{ Success = $false; Message = $_.Exception.Message }
    }
}

#endregion Proxy Configuration

#region Bootstrap

# Create Registry Key
if ([boolean](Test-Path -Path $global:RegPath -ErrorAction SilentlyContinue) -eq $false) {
    New-Item -Path $global:RegPath -ItemType directory -Force | Out-Null
}

# Create required directories
foreach ($dir in @($global:TempDirectory, $global:LogDirectory)) {
    if ([boolean](Test-Path -Path $dir -ErrorAction SilentlyContinue) -eq $false) {
        New-Item -Path $dir -ItemType dir -Force | Out-Null
    }
}

#endregion Bootstrap

#region Logging

function global:Write-DATLogEntry {
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value,
        [ValidateSet('1', '2', '3')]
        [string]$Severity = '1',
        [string]$LogFileName = "$global:ProductName.log",
        [switch]$UpdateUI
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return }

    $script:LogFilePath = Join-Path -Path $global:LogDirectory -ChildPath $LogFileName

    # Rotate log if > 1MB -- keep up to 5 previous rolled-over logs
    if (Test-Path -Path $script:LogFilePath) {
        $LogFileSize = (Get-Item -Path $script:LogFilePath).Length
        if ($LogFileSize -ge 1MB) {
            try {
                $ArchiveName = "$($LogFileName.TrimEnd('.log'))_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
                $ArchivePath = Join-Path -Path $global:LogDirectory -ChildPath $ArchiveName
                Move-Item -Path $script:LogFilePath -Destination $ArchivePath -Force
                Get-ChildItem -Path $global:LogDirectory -Filter "$($LogFileName.TrimEnd('.log'))_*.log" |
                    Sort-Object LastWriteTime -Descending | Select-Object -Skip 5 | Remove-Item -Force
            } catch {
                Write-Warning "Log rotation failed: $($_.Exception.Message)"
            }
        }
    }

    # Use .NET TimeZoneInfo instead of WMI for reliability (#9)
    $tzBias = try { [System.TimeZoneInfo]::Local.BaseUtcOffset.TotalMinutes } catch { 0 }
    $Time = -join @((Get-Date -Format "HH:mm:ss.fff"), " ", $tzBias)
    $Date = (Get-Date -Format "MM-dd-yyyy")
    $Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""$global:ProductName"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"

    try {
        # Use FileStream with ReadWrite sharing to avoid locking conflicts between UI and build runspace
        $retries = 3
        for ($i = 0; $i -lt $retries; $i++) {
            try {
                $fs = [System.IO.FileStream]::new($LogFilePath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
                try {
                    $sw = [System.IO.StreamWriter]::new($fs, [System.Text.Encoding]::Default)
                    $sw.WriteLine($LogText)
                    $sw.Flush()
                } finally {
                    if ($sw) { $sw.Dispose() }
                }
                break
            } catch {
                if ($i -eq ($retries - 1)) { throw }
                Start-Sleep -Milliseconds 50
            }
        }
        if ($Severity -eq 1) { Write-Verbose -Message $Value }
        elseif ($Severity -eq 3) { Write-Warning -Message $Value }

        if ($UpdateUI) {
            switch ($Severity) {
                "1" {
                    if ((Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue).RunningState -ne "Running") {
                        Set-DATRegistryValue -Name "RunningState" -Type String -Value "Running"
                    }
                }
                "3" {
                    if ((Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue).RunningState -ne "Error") {
                        Set-DATRegistryValue -Name "RunningState" -Type String -Value "Error"
                    }
                }
            }
            $TrimedValue = $Value.TrimStart("- ")
            Set-DATRegistryValue -Name "RunningMessage" -Type String -Value $TrimedValue
        }
    } catch [System.Exception] {
        Write-Warning -Message "Unable to append log entry to $global:ProductName.log file. Error: $($_.Exception.Message)"
    }
}

#endregion Logging

#region Registry

function Set-DATRegistryValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,
        [Parameter(Mandatory = $true, Position = 2)]
        [AllowEmptyString()]
        [String]$Value,
        [Parameter(Mandatory = $true, Position = 3)]
        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'Qword')]
        [String]$Type,
        [Parameter(Position = 4)]
        [String]$FullOSRegPath
    )

    try {
        if (-not ([string]::IsNullOrEmpty($FullOSRegPath))) {
            if ([boolean](Test-Path -Path $FullOSRegPath -ErrorAction SilentlyContinue) -eq $false) {
                New-Item -Path $FullOSRegPath -Force | Out-Null
            }
            New-ItemProperty -Path $FullOSRegPath -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        } elseif (-not ([string]::IsNullOrEmpty($global:RegPath))) {
            if ((Test-Path -Path $global:RegPath) -eq $false) {
                New-Item -Path $global:RegPath -Force | Out-Null
            }
            New-ItemProperty -Path $global:RegPath -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        }
    } catch [System.Exception] {
        Write-Output "[Registry Setting Error] - Error at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    }
}

function Reset-DATRegistryValues {
    [CmdletBinding()]
    param ()
    Remove-ItemProperty -Path $global:RegPath -Name TotalDriverDownloads -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $global:RegPath -Name CurrentDriverDownload -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $global:RegPath -Name CurrentDriverDownloadCount -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $global:RegPath -Name CompletedDriverDownloads -ErrorAction SilentlyContinue
}

#endregion Registry

#region OEM Sources

function Get-DATOEMSources {
    [CmdletBinding()]
    param ()

    try {
        Write-DATLogEntry -Value "[OEM Source Check] - Testing path $global:TempDirectory" -Severity 1
        $global:OEMXMLPath = Join-Path $global:TempDirectory -ChildPath "OEMLinks.xml"
        if (-not (Test-Path -Path $global:OEMXMLPath -ErrorAction SilentlyContinue)) {
            Write-DATLogEntry -Value "- Downloading OEMLinks XML from $OEMLinksURL" -Severity 1
            $proxyParams = Get-DATWebRequestProxy
            (Invoke-WebRequest -Uri "$OEMLinksURL" -UseBasicParsing @proxyParams).Content | Out-File -FilePath $global:OEMXMLPath
        } else {
            $proxyParams = Get-DATWebRequestProxy
            [version]$OEMCurrentVersion = ([XML]((Invoke-WebRequest -Uri "$OEMLinksURL" -UseBasicParsing @proxyParams).Content)).OEM.Version
            [version]$OEMDownloadedVersion = ([XML](Get-Content -Path $global:OEMXMLPath)).OEM.Version
            if ($OEMDownloadedVersion -lt $OEMCurrentVersion) {
                Write-DATLogEntry -Value "- Downloading updated OEMLinks XML ($OEMCurrentVersion)" -Severity 1
                (Invoke-WebRequest -Uri "$OEMLinksURL" -UseBasicParsing @proxyParams).Content | Out-File -FilePath $global:OEMXMLPath -Force
            }
        }
        [xml]$global:OEMLinks = Get-Content -Path $global:OEMXMLPath
    } catch {
        Write-DATLogEntry -Value "[XML Source Error] - $($_.Exception.Message)" -Severity 3
    }
}

function Find-DATLenovoModelType {
    param (
        [string]$Model,
        [string]$OS,
        [string]$ModelType
    )
    if ($ModelType.Length -gt 0) {
        $global:LenovoModelType = $global:LenovoModelDrivers | Where-Object {
            $_.Types.Type -match $ModelType
        } | Select-Object -ExpandProperty Name -First 1
    }
    if (-not [string]::IsNullOrEmpty($Model)) {
        $global:LenovoModelType = ($global:LenovoModelDrivers | Where-Object {
            $_.Name -eq $Model
        }).Types.Type
    }
    $global:SkuValue = $global:LenovoModelType
    return $global:LenovoModelType
}

function Get-DATOEMModelInfo {
    [CmdletBinding()]
    param (
        [Parameter(Position = 1)]
        [ValidateSet('HP', 'Dell', 'Lenovo', 'Microsoft', 'Acer')]
        [array]$RequiredOEMs,
        [Parameter(Position = 2)]
        [ValidateNotNullOrEmpty()]
        [string]$OS,
        [Parameter(Position = 3)]
        [ValidateSet('x64', 'x86', 'Arm64')]
        [string]$Architecture
    )

    $OEMLinksURL = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/OEMLinks.xml"
    try {
        $proxyParams = Get-DATWebRequestProxy
        $webContent = $null
        for ($i = 1; $i -le 3; $i++) {
            try {
                $webContent = (Invoke-WebRequest -Uri "$OEMLinksURL" -UseBasicParsing @proxyParams).Content
                break
            } catch {
                if ($i -lt 3) {
                    Write-DATLogEntry -Value "[Warning] - OEM catalog attempt $i failed: $($_.Exception.Message). Retrying in 5s..." -Severity 2
                    Start-Sleep -Seconds 5
                } else { throw }
            }
        }
        [xml]$OEMLinks = $webContent
    } catch {
        Write-DATLogEntry -Value "[Error] - Failed to read OEM links XML: $($_.Exception.Message)" -Severity 3
        return @()
    }

    if ((Test-Path -Path $global:TempDirectory) -eq $false) {
        New-Item -Path $global:TempDirectory -ItemType dir -Force | Out-Null
    }

    $WindowsBuild = $($OS).Split(" ")[2]
    $WindowsVersion = $OS.Trim("$WindowsBuild").TrimEnd()
    $OEMSupportedModels = @()

    foreach ($OEM in $RequiredOEMs) {
        Write-DATLogEntry -Value "- Loading $OEM model compatibility" -Severity 1
        switch ($OEM) {
            "HP" {
                $HPXMLCabinetSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "HP" }).Link | Where-Object { $_.Type -eq "XMLCabinetSource" } | Select-Object -ExpandProperty URL -First 1
                $HPCabFile = [string]($HPXMLCabinetSource | Split-Path -Leaf)
                $HPXMLFile = $HPCabFile.TrimEnd(".cab") + ".xml"
                try {
                    Invoke-DATContentDownload -DownloadURL $HPXMLCabinetSource -DownloadDestination $global:TempDirectory
                    Expand "$global:TempDirectory\$HPCabFile" -F:* "$global:TempDirectory" -R | Out-Null
                    [xml]$HPModelXML = Get-Content -Path (Join-Path -Path $global:TempDirectory -ChildPath $HPXMLFile) -Raw
                    $HPModelSoftPaqs = $HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
                    $HPOSSupportedPacks = $HPModelSoftPaqs | Where-Object { $_.OSName -match $WindowsVersion -and $_.OSName -match $WindowsBuild }
                    foreach ($Model in $HPOSSupportedPacks) {
                        $Model.SystemName = $($($Model.SystemName).TrimStart("HP")).Trim()
                        # Null-safe SystemId join (#16)
                        $sysIds = $Model.SystemId | Where-Object { $_ } | Select-Object -Unique
                        $OEMSupportedModels += [PSCustomObject]@{
                            OEM        = "HP"
                            Model      = $Model.SystemName
                            Baseboards = $(if ($sysIds) { $sysIds -join "," } else { "" })
                            OS         = $WindowsVersion
                            'OS Build' = $WindowsBuild
                            Version    = (Get-Date -Format 'ddMMyyyy')
                        }
                    }
                } catch {
                    Write-DATLogEntry -Value "[Error] - HP model retrieval failed: $($_.Exception.Message)" -Severity 3
                }
            }
            "Dell" {
                $DellXMLCabinetSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "XMLCabinetSource" } | Select-Object -ExpandProperty URL -First 1
                $DellCabFile = [string]($DellXMLCabinetSource | Split-Path -Leaf)
                $DellXMLFile = $DellCabFile.TrimEnd(".cab") + ".xml"
                $DellWindowsVersion = $WindowsVersion.Replace(" ", "")
                try {
                    if (-not (Test-Path (Join-Path $global:TempDirectory $DellCabFile))) {
                        Invoke-DATContentDownload -DownloadURL $DellXMLCabinetSource -DownloadDestination $global:TempDirectory
                    }
                    Expand "$global:TempDirectory\$DellCabFile" -F:* "$global:TempDirectory" -R | Out-Null
                    if ($null -eq $global:DellModelXML) {
                        [xml]$global:DellModelXML = Get-Content -Path (Join-Path $global:TempDirectory $DellXMLFile) -Raw
                    }
                    $global:DellModelCabFiles = $global:DellModelXML.driverpackmanifest.driverpackage
                    $DellModels = $global:DellModelCabFiles | Where-Object {
                        ($_.SupportedOperatingSystems.OperatingSystem.osCode -eq "$DellWindowsVersion") -and
                        ($_.SupportedOperatingSystems.OperatingSystem.osArch -match $Architecture)
                    } | Select-Object @{ Name = "SystemName"; Expression = { $_.SupportedSystems.Brand.Model.name | Select-Object -First 1 } },
                    @{ Name = "SystemID"; Expression = { $_.SupportedSystems.Brand.Model.SystemID } },
                    @{ Name = "DellVersion"; Expression = { $_.dellVersion } } -Unique |
                    Where-Object { $_.SystemName -gt $null }
                    foreach ($Model in $DellModels) {
                        # Null-safe SystemId join (#16)
                        $sysIds = $Model.SystemId | Where-Object { $_ } | Select-Object -Unique
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
                    Write-DATLogEntry -Value "[Error] - Dell model retrieval failed: $($_.Exception.Message)" -Severity 3
                }
            }
            "Lenovo" {
                $LenovoXMLSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Lenovo" }).Link | Where-Object { $_.Type -eq "XMLSource" } | Select-Object -ExpandProperty URL -First 1
                $LenovoXMLCabFile = $LenovoXMLSource | Split-Path -Leaf
                try {
                    if (-not (Test-Path "$global:TempDirectory\$LenovoXMLCabFile")) {
                        Invoke-DATContentDownload -DownloadURL $LenovoXMLSource -DownloadDestination $global:TempDirectory
                    }
                    [xml]$global:LenovoModelXML = Get-Content -Path (Join-Path $global:TempDirectory $LenovoXMLCabFile)
                    $global:LenovoModelDrivers = $global:LenovoModelXML.ModelList.Model
                    if (-not ([string]::IsNullOrEmpty($WindowsBuild))) {
                        $LenovoModels = ($global:LenovoModelDrivers | Where-Object {
                            ($_.SCCM.Version -eq $WindowsBuild -and $_.SCCM.OS -eq $("Win" + "$($WindowsVersion.Split(' ')[1])"))
                        } | Sort-Object).Name
                    }
                    foreach ($Model in $LenovoModels) {
                        $modelNode = $global:LenovoModelDrivers | Where-Object { $_.Name -eq $Model } | Select-Object -First 1
                        $BaseboardValues = ([string]$($modelNode.Types.Type)).Replace(" ", ",").Trim()
                        # Get driver pack date from the matching SCCM node
                        $sccmNode = $modelNode.SCCM | Where-Object { $_.Version -eq $WindowsBuild -and $_.OS -eq $("Win" + "$($WindowsVersion.Split(' ')[1])") } | Select-Object -First 1
                        $lenovoDate = if ($sccmNode.date) { $sccmNode.date } else { '' }
                        # Check for supplemental NVIDIA GFX driver package
                        $gfxNode = $modelNode.GFX | Where-Object { $_.os -eq $("Win" + "$($WindowsVersion.Split(' ')[1])") -and $_.version -eq $WindowsBuild } | Select-Object -First 1
                        $hasGFX = $null -ne $gfxNode
                        $gfxBrand = if ($hasGFX) { $gfxNode.brand } else { $null }
                        if ($hasGFX) { Write-DATLogEntry -Value "[Lenovo] $Model has supplemental $gfxBrand GFX driver package" -Severity 1 }
                        $OEMSupportedModels += [PSCustomObject]@{
                            OEM        = "Lenovo"
                            Model      = $Model
                            Baseboards = $BaseboardValues
                            OS         = $WindowsVersion
                            'OS Build' = $WindowsBuild
                            HasGFX     = $hasGFX
                            GFXBrand   = $gfxBrand
                            Version    = $lenovoDate
                        }
                    }
                } catch {
                    Write-DATLogEntry -Value "[Error] - Lenovo model retrieval failed: $($_.Exception.Message)" -Severity 3
                }
            }
            "Microsoft" {
                # OEM LINK Temporary MS Hard Link
                $MicrosoftXMLSource = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/OSDMSDrivers.xml"
                $MicrosoftXMLPath = Join-Path $global:TempDirectory "OSDMSDrivers.xml"
                try {
                    $proxyParams = Get-DATWebRequestProxy
                    Invoke-WebRequest -Uri $MicrosoftXMLSource -OutFile $MicrosoftXMLPath -UseBasicParsing -TimeoutSec 30 @proxyParams
                    $global:MicrosoftModelList = Import-Clixml -Path $MicrosoftXMLPath
                    $MSArchFilter = if ($Architecture -eq 'Arm64') { 'arm64' } else { 'amd64' }
                    $MSFiltered = $global:MicrosoftModelList | Where-Object {
                        $_.OSVersion -match $WindowsVersion -and $_.OSArchitecture -eq $MSArchFilter
                    }
                    $MicrosoftModels = $MSFiltered | Group-Object -Property Model
                    foreach ($MSModelGroup in $MicrosoftModels) {
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
                    Write-DATLogEntry -Value "[Error] - Microsoft model retrieval failed: $($_.Exception.Message)" -Severity 3
                }
            }
            "Acer" {
                $AcerXMLSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Acer" }).Link | Where-Object { $_.Type -eq "XMLSource" } | Select-Object -ExpandProperty URL -First 1
                $AcerXMLFile = [string]($AcerXMLSource | Split-Path -Leaf)
                try {
                    if (-not (Test-Path "$global:TempDirectory\$AcerXMLFile")) {
                        Invoke-DATContentDownload -DownloadURL $AcerXMLSource -DownloadDestination $global:TempDirectory
                    }
                    [xml]$global:AcerModelXML = Get-Content -Path (Join-Path $global:TempDirectory $AcerXMLFile)
                    $global:AcerModelDrivers = $global:AcerModelXML.ModelList.Model
                    if (-not ([string]::IsNullOrEmpty($WindowsBuild))) {
                        $AcerModels = ($global:AcerModelDrivers | Where-Object {
                            ($_.SCCM.Version -eq $WindowsBuild -and $_.SCCM.OS -eq $("Win" + "$($WindowsVersion.Split(' ')[1])"))
                        } | Sort-Object).Name
                    }
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
                    Write-DATLogEntry -Value "[Error] - Acer model retrieval failed: $($_.Exception.Message)" -Severity 3
                }
            }
        }
    }
    return [array]$OEMSupportedModels
}

#endregion OEM Sources

#region Download

function Invoke-DATContentDownload {
    [CmdletBinding()]
    param (
        [ValidateNotNullOrEmpty()]$DownloadDestination,
        [ValidateNotNullOrEmpty()]$DownloadURL
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Ensure DownloadURL is a single string, not an array
    if ($DownloadURL -is [array]) { $DownloadURL = $DownloadURL[0] }

    # Validate URL before attempting anything
    $uriResult = $null
    if (-not ([System.Uri]::TryCreate($DownloadURL, [System.UriKind]::Absolute, [ref]$uriResult)) -or
        $uriResult.Scheme -notin @('http', 'https')) {
        Write-DATLogEntry -Value "[Error] - Invalid or unsupported download URL: '$DownloadURL'" -Severity 3
        throw "Invalid download URL: '$DownloadURL'"
    }

    if (-not (Test-Path -Path $DownloadDestination)) {
        New-Item -Path $DownloadDestination -ItemType Directory -Force | Out-Null
    }

    # Strip query strings from the leaf filename -- URLs like .zip?acerid=... produce invalid filenames on Windows
    $leafName = $DownloadURL | Split-Path -Leaf
    if ($leafName -match '\?') { $leafName = ($leafName -split '\?')[0] }
    $DownloadDestination = Join-Path -Path "$DownloadDestination" -ChildPath $leafName

    $DownloadSize = [long]0
    try {
        $proxyParams = Get-DATWebRequestProxy
        $DownloadState = Invoke-WebRequest -Uri $DownloadURL -Method Head -UseBasicParsing -TimeoutSec 30 @proxyParams
        if ($DownloadState.StatusCode -eq "200") {
            $DownloadHeaders = $DownloadState | Select-Object -ExpandProperty Headers
            $contentLength = $DownloadHeaders.'Content-Length'
            # Content-Length may be a string array in PS7; take the first value
            if ($contentLength -is [array]) { $contentLength = $contentLength[0] }
            if ($contentLength) { $DownloadSize = [long]$contentLength }
        }
    } catch {
        Write-DATLogEntry -Value "[Warning] - HEAD request failed, size unknown: $($_.Exception.Message)" -Severity 2
    }

    # Skip if already downloaded: size matches, or size unknown but file exists (trust it)
    if (Test-Path -Path $DownloadDestination) {
        $DownloadedFileSize = (Get-Item -Path $DownloadDestination).Length
        $sizeMatch = ($DownloadSize -gt 0 -and $DownloadSize -eq $DownloadedFileSize)
        $sizeUnknown = ($DownloadSize -le 0 -and $DownloadedFileSize -gt 0)
        if ($sizeMatch -or $sizeUnknown) {
            Write-DATLogEntry -Value "- File already downloaded and verified: $DownloadDestination" -Severity 1
            $DownloadedSizeMB = [math]::Round(($DownloadedFileSize / 1MB), 2)
            Set-DATRegistryValue -Name "DownloadSize"       -Type String -Value "$DownloadedSizeMB MB"
            Set-DATRegistryValue -Name "DownloadBytes"      -Value "$DownloadedFileSize" -Type String
            Set-DATRegistryValue -Name "BytesTransferred"   -Value "$DownloadedFileSize" -Type String
            Set-DATRegistryValue -Name "DownloadSpeed"      -Value "---"  -Type String
            Set-DATRegistryValue -Name "RunningState"       -Value "Running" -Type String
            Set-DATRegistryValue -Name "RunningMode"        -Value "Download Completed" -Type String
            return
        }
        # Partial / size-mismatch -- remove stale file before retrying
        Write-DATLogEntry -Value "- Removing incomplete/mismatched file before re-download: $DownloadDestination" -Severity 2
        Remove-Item -Path $DownloadDestination -Force -ErrorAction SilentlyContinue
    }

    if ($DownloadSize -gt 0) {
        Set-DATRegistryValue -Name "DownloadURL"   -Type String -Value "$DownloadURL"
        $DownloadSizeMB = [math]::Round(($DownloadSize / 1MB), 2)
        Set-DATRegistryValue -Name "DownloadSize"  -Type String -Value "$DownloadSizeMB MB"
        Set-DATRegistryValue -Name "DownloadBytes" -Value "$DownloadSize" -Type String
    }
    Set-DATRegistryValue -Name "BytesTransferred" -Value "0" -Type String
    Set-DATRegistryValue -Name "DownloadSpeed"    -Value "---" -Type String

    # Detect CURL -- read user preference from registry
    $CurlProcess = $null
    $curlSource = (Get-ItemProperty -Path $global:RegPath -Name 'CurlSource' -ErrorAction SilentlyContinue).CurlSource
    $useBuiltInOnly = ($curlSource -eq 'Built-in (System)')

    if (-not $useBuiltInOnly -and -not [string]::IsNullOrEmpty($global:ToolsDirectory)) {
        $CurlProcess = Get-ChildItem -Path "$global:ToolsDirectory" -Recurse -Filter "Curl.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
    $useCurl = (-not $useBuiltInOnly) -and (-not [string]::IsNullOrEmpty($CurlProcess)) -and (Test-Path -Path "$CurlProcess")

    if ($useCurl) {
        Write-DATLogEntry -Value "- CURL detected at $CurlProcess" -Severity 1

        # Validate Authenticode signature before execution
        $curlSig = Get-AuthenticodeSignature -FilePath $CurlProcess -ErrorAction SilentlyContinue
        if ($curlSig -and $curlSig.Status -eq 'Valid') {
            $signerName = $curlSig.SignerCertificate.Subject -replace '^CN=|,.*$', ''
            Write-DATLogEntry -Value "- CURL signature valid -- Signed by $signerName" -Severity 1
        } elseif ($curlSig -and $curlSig.Status -eq 'HashMismatch') {
            Write-DATLogEntry -Value "[Warning] - CURL binary signature hash mismatch (possibly tampered). Trying system curl." -Severity 2
            $CurlProcess = $null
            $useCurl = $false
        } else {
            $sigStatus = if ($curlSig) { $curlSig.Status } else { 'Unknown' }
            Write-DATLogEntry -Value "- CURL binary is not signed ($sigStatus) -- proceeding (official curl.exe is unsigned)" -Severity 1
        }

        # Quick launch test -- if the bundled binary is blocked by SmartScreen/WDAC, fall back to system curl
        if ($useCurl) {
            try {
                Unblock-File -Path "$CurlProcess" -ErrorAction SilentlyContinue
                $testProc = Start-Process -FilePath $CurlProcess -ArgumentList "--version" -WindowStyle Hidden -PassThru -Wait
                if ($null -eq $testProc) { throw "Start-Process returned null" }
                Write-DATLogEntry -Value "- CURL launch test passed (bundled binary)" -Severity 1
            } catch {
                Write-DATLogEntry -Value "[Warning] - Bundled CURL blocked: $($_.Exception.Message). Checking system curl." -Severity 2
                $CurlProcess = $null
                $useCurl = $false
            }
        }
    }

    # Fall back to system curl.exe (built-in on Windows 10 1803+)
    if (-not $useCurl) {
        if ($useBuiltInOnly) {
            Write-DATLogEntry -Value "- CURL source set to Built-in (System) -- skipping bundled curl" -Severity 1
        }
        $systemCurl = Join-Path $env:SystemRoot "System32\curl.exe"
        if (Test-Path -Path $systemCurl) {
            $CurlProcess = $systemCurl
            $useCurl = $true
            Write-DATLogEntry -Value "- Using system CURL at $systemCurl" -Severity 1
        }
    }

    if ($useCurl) {
        Write-DATLogEntry -Value "- Using CURL for download: $CurlProcess" -Severity 1
    }

    if ($useCurl) {

        # If HEAD request failed to get size, fall back to CURL headers
        if ($DownloadSize -le 0) {
            try {
                Write-DATLogEntry -Value "- Using CURL to obtain file size via response headers" -Severity 1
                # Use -i (include headers) with a real GET request -- many CDNs don't return
                # Content-Length for HEAD requests. --suppress-connect-headers removes proxy noise.
                # --max-time 15 limits the download to 15 seconds (headers arrive within the first second).
                [array]$CurlHeaderOutput = (& "$CurlProcess" --silent --location -i --suppress-connect-headers --max-time 15 $DownloadURL 2>&1)
                $contentLengthLine = $CurlHeaderOutput | Where-Object { $_ -match "Content-Length" } | Select-Object -Last 1
                if ($contentLengthLine) {
                    $parsedSize = ($contentLengthLine -replace "Content-Length:\s*", "").Trim()
                    if ($parsedSize -match '^\d+$' -and [long]$parsedSize -gt 0) {
                        $DownloadSize = [long]$parsedSize
                        $DownloadSizeMB = [math]::Round(($DownloadSize / 1MB), 2)
                        Set-DATRegistryValue -Name "DownloadURL"   -Type String -Value "$DownloadURL"
                        Set-DATRegistryValue -Name "DownloadSize"  -Type String -Value "$DownloadSizeMB MB"
                        Set-DATRegistryValue -Name "DownloadBytes" -Value "$DownloadSize" -Type String
                        Write-DATLogEntry -Value "- Content-Length from CURL response: $DownloadSizeMB MB ($DownloadSize bytes)" -Severity 1
                    }
                }
                if ($DownloadSize -le 0) {
                    Write-DATLogEntry -Value "[Warning] - Could not determine file size from CURL response headers" -Severity 2
                }
            } catch {
                Write-DATLogEntry -Value "[Warning] - CURL header request failed: $($_.Exception.Message)" -Severity 2
            }
        }

        # Build CURL arguments -- dump response headers to a temp file so we can read Content-Length during download
        $CurlHeaderDumpFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "curl_headers_$([System.IO.Path]::GetRandomFileName()).txt"
        $CurlArgs = "--location --output `"$DownloadDestination`" --url `"$DownloadURL`" --dump-header `"$CurlHeaderDumpFile`" --connect-timeout 30 --retry 10 --retry-delay 60 --retry-max-time 600 --retry-connrefused $(Get-DATCurlProxyArgs)"

        try {
            Set-DATRegistryValue -Name "RunningProcess" -Type String -Value "Curl"
            $DownloadStartTime = Get-DATLocalSystemTime
            Set-DATRegistryValue -Name "DownloadStartTime" -Type String -Value "$DownloadStartTime"

            Write-DATLogEntry -Value "- Starting CURL download process. URL: $DownloadURL" -Severity 1
            Write-DATLogEntry -Value "- CURL arguments: $CurlArgs" -Severity 1

            # Read CURL window style from registry (Silent = Hidden, Show Window = Normal)
            $curlRunMode = (Get-ItemProperty -Path $global:RegPath -Name 'CurlRunMode' -ErrorAction SilentlyContinue).CurlRunMode
            $curlWindowStyle = if ($curlRunMode -eq 'Show Window') { 'Normal' } else { 'Hidden' }
            $curlWorkDir = Split-Path -Path $CurlProcess -Parent
            $DownloadProcess = Start-Process -FilePath $CurlProcess -ArgumentList $CurlArgs -PassThru -WindowStyle $curlWindowStyle -WorkingDirectory $curlWorkDir
            Set-DATRegistryValue -Name "RunningProcessID" -Type String -Value "$($DownloadProcess.Id)"
            # Wait for CURL initialization
            Start-Sleep -Seconds 5

            # Monitor CURL progress via WMI WriteTransferCount
            $DownloadProcessCounter = 0
            $headerFileChecked = $false
            $lastSpeedBytes = [long]0
            $lastSpeedTime = $DownloadStartTime
            while (-not $DownloadProcess.HasExited) {
                # Check for abort
                $abortReg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
                if ($abortReg.RunningState -eq 'Aborted') {
                    Write-DATLogEntry -Value "[CURL] Abort detected -- killing curl process" -Severity 2
                    try { $DownloadProcess.Kill() } catch { Stop-Process -Id $DownloadProcess.Id -Force -ErrorAction SilentlyContinue }
                    return
                }
                $CURLBytes = Get-CimInstance -Class Win32_Process -Filter "Name = 'Curl.exe'" -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty WriteTransferCount

                # If size still unknown, try reading Content-Length from CURL's dumped response headers
                if ($DownloadSize -le 0 -and -not $headerFileChecked -and (Test-Path -Path $CurlHeaderDumpFile)) {
                    $headerFileChecked = $true
                    try {
                        $headerContent = Get-Content -Path $CurlHeaderDumpFile -ErrorAction SilentlyContinue
                        $clLine = $headerContent | Where-Object { $_ -match "Content-Length" } | Select-Object -Last 1
                        if ($clLine) {
                            $clVal = ($clLine -replace "Content-Length:\s*", "").Trim()
                            if ($clVal -match '^\d+$' -and [long]$clVal -gt 0) {
                                $DownloadSize = [long]$clVal
                                $DownloadSizeMB = [math]::Round(($DownloadSize / 1MB), 2)
                                Set-DATRegistryValue -Name "DownloadSize"  -Type String -Value "$DownloadSizeMB MB"
                                Set-DATRegistryValue -Name "DownloadBytes" -Value "$DownloadSize" -Type String
                                Write-DATLogEntry -Value "- File size from response headers: $DownloadSizeMB MB ($DownloadSize bytes)" -Severity 1
                            }
                        }
                    } catch {
                        Write-DATLogEntry -Value "- Warning: Could not parse CURL response headers: $($_.Exception.Message)" -Severity 2
                    }
                }

                if ($null -ne $CURLBytes -and $CURLBytes -gt 0) {
                    $DownloadProcessCounter++
                    Set-DATRegistryValue -Name "BytesTransferred" -Value "$CURLBytes" -Type String

                    $CURLMBDownload = [math]::Round($CURLBytes / 1MB, 2)
                    # Calculate speed over recent interval (not total average)
                    $now = Get-Date
                    $intervalSeconds = ($now - $lastSpeedTime).TotalSeconds
                    if ($intervalSeconds -ge 3) {
                        $intervalBytes = $CURLBytes - $lastSpeedBytes
                        $DownloadSpeed = [math]::Round(($intervalBytes / 1MB) / $intervalSeconds, 2)
                        Set-DATRegistryValue -Name "DownloadSpeed" -Value "$DownloadSpeed MB/s" -Type String
                        $lastSpeedBytes = $CURLBytes
                        $lastSpeedTime = $now
                    }

                    if ($DownloadSize -gt 0) {
                        $DownloadSizeMB = [math]::Round(($DownloadSize / 1MB), 2)
                    }
                    $DownloadMsg = "- Downloaded $CURLMBDownload MB of $DownloadSizeMB MB at $DownloadSpeed MB/s"

                    if (($DownloadProcessCounter % 60) -eq 0) {
                        Write-DATLogEntry -Value "$DownloadMsg" -Severity 1
                    } else {
                        Set-DATRegistryValue -Name "RunningMessage" -Type String -Value "$($DownloadMsg.TrimStart('- '))"
                    }
                }

                Start-Sleep -Seconds 1
            }

            # Final file size update
            if (Test-Path -Path $DownloadDestination) {
                $DownloadedFileSize = (Get-Item -Path $DownloadDestination).Length
                Set-DATRegistryValue -Name "BytesTransferred" -Value "$DownloadedFileSize" -Type String
            }

            # Clean up header dump file
            Remove-Item -Path $CurlHeaderDumpFile -Force -ErrorAction SilentlyContinue

            if ($DownloadProcess.ExitCode -eq 0) {
                Write-DATLogEntry -Value "- CURL download completed successfully" -Severity 1
                Set-DATRegistryValue -Name "DownloadSpeed" -Value "---" -Type String
                Set-DATRegistryValue -Name "RunningState"  -Value "Running" -Type String
                Set-DATRegistryValue -Name "RunningMode"   -Value "Download Completed" -Type String
                Set-DATRegistryValue -Name "RunningProcessID" -Value " " -Type String
                Set-DATRegistryValue -Name "RunningProcess"   -Value " " -Type String

                # Verify file size if known
                if ($DownloadSize -gt 0 -and (Test-Path -Path $DownloadDestination)) {
                    $DownloadedFileSize = (Get-Item -Path $DownloadDestination).Length
                    if ($DownloadSize -eq $DownloadedFileSize) {
                        Write-DATLogEntry -Value "- File size verified: $DownloadedFileSize bytes" -Severity 1
                    } else {
                        Write-DATLogEntry -Value "[Warning] - File size mismatch. Expected: $DownloadSize, Actual: $DownloadedFileSize" -Severity 2
                    }
                }
                return
            } else {
                Write-DATLogEntry -Value "[Warning] - CURL exited with code $($DownloadProcess.ExitCode). Falling back to HttpClient" -Severity 2
            }
        } catch {
            Write-DATLogEntry -Value "[Warning] - CURL download failed: $($_.Exception.Message). Falling back to HttpClient" -Severity 2
        } finally {
            # Kill curl if still running (PipelineStoppedException from abort skips catch but runs finally)
            if ($DownloadProcess -and -not $DownloadProcess.HasExited) {
                try { $DownloadProcess.Kill() } catch { Stop-Process -Id $DownloadProcess.Id -Force -ErrorAction SilentlyContinue }
                Write-DATLogEntry -Value "- CURL process killed during abort" -Severity 2
            }
        }

        # Remove partial file from failed CURL attempt before HttpClient fallback
        if (Test-Path -Path $DownloadDestination) {
            Remove-Item -Path $DownloadDestination -Force -ErrorAction SilentlyContinue
        }
    }

    # HttpClient download (primary if no CURL, fallback if CURL failed)
    $maxRetries = 10
    $retryDelaySec = 60
    $maxRetryTimeSec = 600
    $retryTimer = [System.Diagnostics.Stopwatch]::StartNew()

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        # Reset per-attempt counters so the progress bar doesn't jump
        Set-DATRegistryValue -Name "BytesTransferred" -Value "0" -Type String
        Set-DATRegistryValue -Name "DownloadSpeed"    -Value "---" -Type String

        # Remove any partial file left by a previous failed attempt
        if (Test-Path -Path $DownloadDestination) {
            Remove-Item -Path $DownloadDestination -Force -ErrorAction SilentlyContinue
        }

        # Before each attempt, check if the file is being written by another process.
        # If it is, wait up to $retryDelaySec seconds for it to finish rather than fighting over it.
        if (Test-Path -Path $DownloadDestination) {
            $lockedByOther = $false
            try {
                $testStream = [System.IO.FileStream]::new($DownloadDestination, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                $testStream.Dispose()
            } catch [System.IO.IOException] {
                # Only treat IOException (sharing violation) as a lock -- not permissions or other errors (#17)
                if ($_.Exception.HResult -eq 0x80070020 -or $_.Exception.HResult -eq 0x80070021) {
                    $lockedByOther = $true
                } else {
                    Write-DATLogEntry -Value "- File access error (not a lock): $($_.Exception.Message)" -Severity 2
                }
            } catch {
                Write-DATLogEntry -Value "- Unexpected file check error: $($_.Exception.Message)" -Severity 2
            }
            if ($lockedByOther) {
                Write-DATLogEntry -Value "- File is locked by another process -- waiting up to ${retryDelaySec}s for it to complete..." -Severity 2
                $waitSec = 0
                while ($waitSec -lt $retryDelaySec) {
                    Start-Sleep -Seconds 5
                    $waitSec += 5
                    $stillLocked = $false
                    try {
                        $ts = [System.IO.FileStream]::new($DownloadDestination, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
                        $ts.Dispose()
                    } catch { $stillLocked = $true }
                    if (-not $stillLocked) { break }
                }
                # Re-check size -- if it now matches, we're done
                if (Test-Path -Path $DownloadDestination) {
                    $nowSize = (Get-Item -Path $DownloadDestination).Length
                    if (($DownloadSize -gt 0 -and $nowSize -eq $DownloadSize) -or ($DownloadSize -le 0 -and $nowSize -gt 0)) {
                        Write-DATLogEntry -Value "- File completed by another process ($([math]::Round($nowSize/1MB,2)) MB) -- skipping download" -Severity 1
                        Set-DATRegistryValue -Name "BytesTransferred" -Value "$nowSize" -Type String
                        Set-DATRegistryValue -Name "RunningState"     -Value "Running" -Type String
                        Set-DATRegistryValue -Name "RunningMode"      -Value "Download Completed" -Type String
                        return
                    }
                    # Still wrong size -- remove it
                    Remove-Item -Path $DownloadDestination -Force -ErrorAction SilentlyContinue
                }
            } else {
                # File exists and is not locked -- remove stale/partial before this attempt
                Remove-Item -Path $DownloadDestination -Force -ErrorAction SilentlyContinue
            }
        }

        try {
            # Check if System.Net.Http types are available (may fail on older .NET / Server 2016)
            $httpClientAvailable = $null -ne ([System.Management.Automation.PSTypeName]'System.Net.Http.HttpClient').Type

            if (-not $httpClientAvailable) {
                # Fallback to Invoke-WebRequest (BITS transfer) for systems without HttpClient
                Write-DATLogEntry -Value "- HttpClient unavailable -- downloading via Invoke-WebRequest (attempt $attempt/$maxRetries)..." -Severity 1
                $proxyParams = Get-DATWebRequestProxy
                if ($proxyParams -isnot [hashtable]) { $proxyParams = @{} }
                Invoke-WebRequest -Uri $DownloadURL -OutFile $DownloadDestination -UseBasicParsing -TimeoutSec 0 @proxyParams

                if (Test-Path -Path $DownloadDestination) {
                    $downloadedSize = (Get-Item -Path $DownloadDestination).Length
                    Set-DATRegistryValue -Name "BytesTransferred" -Value "$downloadedSize" -Type String
                    Set-DATRegistryValue -Name "DownloadSpeed"    -Value "---" -Type String
                }

                Set-DATRegistryValue -Name "RunningState" -Value "Running" -Type String
                Set-DATRegistryValue -Name "RunningMode"  -Value "Download Completed" -Type String
                return
            }

            Write-DATLogEntry -Value "- Downloading via HttpClient (attempt $attempt/$maxRetries)..." -Severity 1
            $handler = Get-DATHttpClientHandler
            $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
            $httpClient = [System.Net.Http.HttpClient]::new($handler)
            $httpClient.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
            try {
                # Use a cancellation token for 30s connect timeout
                $connectCts = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(30))
                $response = $httpClient.GetAsync($DownloadURL, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $connectCts.Token).GetAwaiter().GetResult()
                $response.EnsureSuccessStatusCode() | Out-Null

                # Fallback: if HEAD request failed, get content-length from GET response headers
                if ($DownloadSize -le 0) {
                    $responseLength = $response.Content.Headers.ContentLength
                    if ($null -ne $responseLength -and $responseLength -gt 0) {
                        $DownloadSize = [long]$responseLength
                        $DownloadSizeMB = [math]::Round(($DownloadSize / 1MB), 2)
                        Set-DATRegistryValue -Name "DownloadURL"   -Type String -Value "$DownloadURL"
                        Set-DATRegistryValue -Name "DownloadSize"  -Type String -Value "$DownloadSizeMB MB"
                        Set-DATRegistryValue -Name "DownloadBytes" -Value "$DownloadSize" -Type String
                        Write-DATLogEntry -Value "- Content-Length from response headers: $DownloadSizeMB MB" -Severity 1
                    }
                }

                $contentStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $fileStream = [System.IO.FileStream]::new($DownloadDestination, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 81920)
                try {
                    $buffer = [byte[]]::new(81920)
                    $totalBytesRead    = [long]0
                    $speedBytesRead    = [long]0
                    $lastRegistryUpdate = [System.Diagnostics.Stopwatch]::StartNew()
                    $speedTimer         = [System.Diagnostics.Stopwatch]::StartNew()
                    while ($true) {
                        $bytesRead = $contentStream.Read($buffer, 0, $buffer.Length)
                        if ($bytesRead -eq 0) { break }
                        $fileStream.Write($buffer, 0, $bytesRead)
                        $totalBytesRead += $bytesRead
                        $speedBytesRead += $bytesRead
                        # Check for abort
                        if ($lastRegistryUpdate.ElapsedMilliseconds -ge 500) {
                            $abortReg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
                            if ($abortReg.RunningState -eq 'Aborted') {
                                Write-DATLogEntry -Value "[HttpClient] Abort detected -- cancelling download" -Severity 2
                                return
                            }
                        }
                        # Update registry every 500ms
                        if ($lastRegistryUpdate.ElapsedMilliseconds -ge 500) {
                            Set-DATRegistryValue -Name "BytesTransferred" -Value "$totalBytesRead" -Type String
                            $elapsedSec = $speedTimer.Elapsed.TotalSeconds
                            if ($elapsedSec -ge 1) {
                                $speedMBps = [math]::Round(($speedBytesRead / 1MB) / $elapsedSec, 2)
                                Set-DATRegistryValue -Name "DownloadSpeed" -Value "$speedMBps MB/s" -Type String
                                $speedBytesRead = 0
                                $speedTimer.Restart()
                            }
                            $lastRegistryUpdate.Restart()
                        }
                    }
                    # Final update
                    Set-DATRegistryValue -Name "BytesTransferred" -Value "$totalBytesRead" -Type String
                    Set-DATRegistryValue -Name "DownloadSpeed"    -Value "---" -Type String
                } finally {
                    $fileStream.Dispose()
                    $contentStream.Dispose()
                }
            } finally {
                $httpClient.Dispose()
            }

            Set-DATRegistryValue -Name "RunningState" -Value "Running" -Type String
            Set-DATRegistryValue -Name "RunningMode"  -Value "Download Completed" -Type String
            return
        } catch {
            $elapsed = $retryTimer.Elapsed.TotalSeconds
            if ($attempt -ge $maxRetries -or $elapsed -ge $maxRetryTimeSec) {
                Write-DATLogEntry -Value "[Error] - Download failed after $attempt attempt(s): $($_.Exception.Message)" -Severity 3
                throw
            }
            Write-DATLogEntry -Value "[Warning] - Download attempt $attempt failed: $($_.Exception.Message). Retrying in ${retryDelaySec}s..." -Severity 2
            Set-DATRegistryValue -Name "RunningMessage" -Value "Download failed (attempt $attempt/$maxRetries) - retrying in ${retryDelaySec}s..." -Type String
            Start-Sleep -Seconds $retryDelaySec
        }
    }
}

function Invoke-DATExecutable {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string]$Arguments
    )

    Unblock-File -Path "$FilePath"
    $SplatArgs = @{
        FilePath    = "$FilePath"
        NoNewWindow = $true
        Passthru    = $true
        ErrorAction = "Stop"
    }
    if (-not ([string]::IsNullOrEmpty($Arguments))) {
        $SplatArgs.Add("ArgumentList", "$Arguments")
    }
    try {
        $Invocation = Start-Process @SplatArgs
        $Invocation.WaitForExit()
    } catch {
        Write-DATLogEntry -Value "[Error] - Execution failed: $($_.Exception.Message)" -Severity 3; break
    }
    return $Invocation.ExitCode
}

function Invoke-DATDriverFilePackaging {
    param (
        [string]$FilePath,
        [Parameter(Mandatory = $true)][string]$OEM,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$OS,
        [Parameter(Mandatory = $true)][string]$Destination,
        [ValidateSet('Configuration Manager', 'Intune', 'WIM Package Only', 'Download Only')]
        [string]$Platform,
        [string[]]$SupplementalFilePaths = @(),
        [string]$CustomDriverPath
    )

    # Always use the temp directory for extraction and WIM creation, then copy the
    # final WIM to the package destination.  This keeps the Package path clean and
    # ensures temp files are cleaned up automatically.  Also handles UNC destinations
    # since DISM cannot create WIMs on network shares.
    $localWorkDir = Join-Path $global:TempDirectory "Build\$OEM\$Model"
    if (Test-Path $localWorkDir) { Remove-Item $localWorkDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -Path $localWorkDir -ItemType Directory -Force | Out-Null
    Write-DATLogEntry -Value "[$OEM] Using local temp working directory: $localWorkDir" -Severity 1

    $DriverFolder = Join-Path -Path $localWorkDir -ChildPath "$OEM\$Model\$OS\Extracted"
    if (-not (Test-Path -Path $DriverFolder)) {
        New-Item -Path $DriverFolder -ItemType Directory -Force | Out-Null
    }

    Set-DATRegistryValue -Name "RunningMessage" -Value "Extracting $OEM $Model drivers..." -Type String
    Set-DATRegistryValue -Name "RunningMode" -Value "Extracting" -Type String
    Write-DATLogEntry -Value "[$OEM] Extracting $Model drivers to $DriverFolder" -Severity 1

    if (Test-Path -Path $DriverFolder) {
        if (Test-Path -Path $FilePath -PathType Container) {
            # HP pre-extracted staging directory -- copy contents directly
            Write-DATLogEntry -Value "[$OEM] Copying pre-extracted drivers from staging directory..." -Severity 1
            Copy-Item -Path "$FilePath\*" -Destination $DriverFolder -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            switch -Wildcard ($FilePath) {
                "*.exe" {
                    # Lenovo SCCM driver packs use Inno Setup; all other OEMs use generic self-extractors
                    if ($OEM -eq 'Lenovo') {
                        $exeArgs = "/VERYSILENT /DIR=`"$DriverFolder`" /SP- /SUPPRESSMSGBOXES /NORESTART"
                    } else {
                        $exeArgs = "/s /e=`"$DriverFolder`""
                    }
                    Write-DATLogEntry -Value "[$OEM] Extracting with: $exeArgs" -Severity 1
                    $exitCode = Invoke-DATExecutable -FilePath $FilePath -Arguments $exeArgs
                    if ($exitCode -ne 0 -and $null -ne $exitCode) {
                        Write-DATLogEntry -Value "[Warning] - EXE extraction returned exit code $exitCode for $FilePath" -Severity 2
                    }
                }
                "*.zip" { Expand-Archive -Path $FilePath -DestinationPath $DriverFolder -Force | Out-Null }
                "*.cab" {
                    try {
                        $ExtractProcess = Start-Process -FilePath "C:\Windows\System32\expand.exe" -ArgumentList "`"$FilePath`" -F:* `"$DriverFolder`"" -WindowStyle Hidden -PassThru -Wait
                        if ($ExtractProcess.ExitCode -ne 0) {
                            Write-DATLogEntry -Value "[Error] - Cabinet extraction failed with exit code $($ExtractProcess.ExitCode)" -Severity 3
                        }
                    } catch {
                        Write-DATLogEntry -Value "[Error] - Cabinet extraction error: $($_.Exception.Message)" -Severity 3
                    }
                }
                "*.msi" {
                    # Microsoft Surface driver packs are MSI -- use administrative install to extract contents
                    try {
                        Write-DATLogEntry -Value "[$OEM] Extracting MSI via administrative install: $FilePath" -Severity 1
                        $msiArgs = "/a `"$FilePath`" /qn TARGETDIR=`"$DriverFolder`""
                        $ExtractProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -WindowStyle Hidden -PassThru -Wait
                        if ($ExtractProcess.ExitCode -ne 0) {
                            Write-DATLogEntry -Value "[Error] - MSI extraction failed with exit code $($ExtractProcess.ExitCode)" -Severity 3
                        } else {
                            # Remove the duplicate MSI left by administrative install
                            $dupMsi = Get-ChildItem -Path $DriverFolder -Filter "*.msi" -File -ErrorAction SilentlyContinue
                            foreach ($msi in $dupMsi) {
                                Remove-Item -Path $msi.FullName -Force -ErrorAction SilentlyContinue
                            }
                        }
                    } catch {
                        Write-DATLogEntry -Value "[Error] - MSI extraction error: $($_.Exception.Message)" -Severity 3
                    }
                }
            }
        }
    }

    # Extract supplemental packages (e.g. NVIDIA GFX) into the same driver folder
    foreach ($suppFile in $SupplementalFilePaths) {
        if (-not (Test-Path $suppFile)) {
            Write-DATLogEntry -Value "[Warning] - Supplemental file not found, skipping: $suppFile" -Severity 2
            continue
        }
        $suppFileName = Split-Path $suppFile -Leaf
        Set-DATRegistryValue -Name "RunningMessage" -Value "Extracting supplemental package: $suppFileName..." -Type String
        Write-DATLogEntry -Value "[$OEM] Extracting supplemental package: $suppFileName to $DriverFolder" -Severity 1

        switch -Wildcard ($suppFile) {
            "*.exe" {
                if ($OEM -eq 'Lenovo') {
                    $suppArgs = "/VERYSILENT /DIR=`"$DriverFolder`" /SP- /SUPPRESSMSGBOXES /NORESTART"
                } else {
                    $suppArgs = "/s /e=`"$DriverFolder`""
                }
                Write-DATLogEntry -Value "[$OEM] Extracting supplemental with: $suppArgs" -Severity 1
                $exitCode = Invoke-DATExecutable -FilePath $suppFile -Arguments $suppArgs
                if ($exitCode -ne 0 -and $null -ne $exitCode) {
                    Write-DATLogEntry -Value "[Warning] - Supplemental EXE extraction returned exit code $exitCode for $suppFile" -Severity 2
                }
            }
            "*.zip" { Expand-Archive -Path $suppFile -DestinationPath $DriverFolder -Force | Out-Null }
            "*.cab" {
                try {
                    $ExtractProcess = Start-Process -FilePath "C:\Windows\System32\expand.exe" -ArgumentList "`"$suppFile`" -F:* `"$DriverFolder`"" -WindowStyle Hidden -PassThru -Wait
                    if ($ExtractProcess.ExitCode -ne 0) {
                        Write-DATLogEntry -Value "[Warning] - Supplemental cabinet extraction failed with exit code $($ExtractProcess.ExitCode)" -Severity 2
                    }
                } catch {
                    Write-DATLogEntry -Value "[Warning] - Supplemental cabinet extraction error: $($_.Exception.Message)" -Severity 2
                }
            }
            default {
                Write-DATLogEntry -Value "[Warning] - Unsupported supplemental file format: $suppFileName" -Severity 2
            }
        }
        $suppExtractedCount = (Get-ChildItem -Path $DriverFolder -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-DATLogEntry -Value "[$OEM] Driver folder now contains $suppExtractedCount files after supplemental extraction" -Severity 1
    }

    $extractedFiles = (Get-ChildItem -Path $DriverFolder -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-DATLogEntry -Value "[$OEM] Extraction complete: $extractedFiles files extracted to $DriverFolder" -Severity 1
    Set-DATRegistryValue -Name "RunningMessage" -Value "Extraction complete ($extractedFiles files) - $OEM $Model" -Type String

    if ($extractedFiles -eq 0) {
        $errorMsg = "Extraction produced 0 files for $OEM $Model. The driver pack may be corrupt or the extraction failed silently. Source: $FilePath"
        Write-DATLogEntry -Value "[Error] - $errorMsg" -Severity 3 -UpdateUI
        throw $errorMsg
    }

    # Inject custom drivers into the extraction folder before WIM creation
    if (-not [string]::IsNullOrEmpty($CustomDriverPath) -and (Test-Path $CustomDriverPath -PathType Container)) {
        $customDriverDest = Join-Path $DriverFolder "CustomDrivers"
        Write-DATLogEntry -Value "[$OEM] Injecting custom drivers from $CustomDriverPath into $customDriverDest" -Severity 1
        Set-DATRegistryValue -Name "RunningMessage" -Value "Injecting custom drivers for $OEM $Model..." -Type String
        if (-not (Test-Path $customDriverDest)) { New-Item -Path $customDriverDest -ItemType Directory -Force | Out-Null }
        Copy-Item -Path (Join-Path $CustomDriverPath '*') -Destination $customDriverDest -Recurse -Force -ErrorAction SilentlyContinue
        $customInfCount = @(Get-ChildItem -Path $customDriverDest -Filter '*.inf' -Recurse -File -ErrorAction SilentlyContinue).Count
        $customFileCount = @(Get-ChildItem -Path $customDriverDest -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-DATLogEntry -Value "[$OEM] Custom drivers injected: $customFileCount files ($customInfCount .inf files)" -Severity 1
    }

    # Create WIM package for ConfigMgr/Intune modes
    if ($Platform -ne 'Download Only') {
        # Validate disk space before WIM creation
        $driverFolderSize = (Get-ChildItem -Path $DriverFolder -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        $requiredSpaceGB = [math]::Round($driverFolderSize / 1GB, 2)
        $pkgDrive = [System.IO.Path]::GetPathRoot($localWorkDir)
        $pkgDriveInfo = [System.IO.DriveInfo]::new($pkgDrive)
        $pkgFreeGB = [math]::Round($pkgDriveInfo.AvailableFreeSpace / 1GB, 2)
        Write-DATLogEntry -Value "[$OEM] Disk space check -- Drive: $pkgDrive Free: $pkgFreeGB GB, Required: $requiredSpaceGB GB" -Severity 1

        if ($pkgFreeGB -lt $requiredSpaceGB) {
            $errorMsg = "Insufficient disk space on $pkgDrive for WIM creation. Free: $pkgFreeGB GB, Required: $requiredSpaceGB GB (based on extracted driver size for $OEM $Model)."
            Write-DATLogEntry -Value "[Error] - $errorMsg" -Severity 3 -UpdateUI
            Set-DATRegistryValue -Name "RunningState" -Value "Error" -Type String
            Set-DATRegistryValue -Name "RunningMessage" -Value $errorMsg -Type String
            throw $errorMsg
        }

        Set-DATRegistryValue -Name "RunningMessage" -Value "Creating WIM package for $OEM $Model..." -Type String
        Set-DATRegistryValue -Name "RunningMode" -Value "Packaging" -Type String
        Write-DATLogEntry -Value "[$OEM] Creating WIM package for $Model..." -Severity 1 -UpdateUI

        try {
            $DriverMountFolder = Join-Path -Path $localWorkDir -ChildPath "Packaged\$OEM\$Model\$OS"
            if (-not (Test-Path -Path $DriverMountFolder)) {
                New-Item -Path $DriverMountFolder -ItemType Directory -Force | Out-Null
            }
            $WimDescription = "$OEM $Model $OS Driver Package"
            $WimFile = Join-Path -Path $DriverMountFolder -ChildPath "DriverPackage.wim"

            # Determine WIM engine preference early so we can skip DISM-specific cleanup for wimlib
            $wimEngine = (Get-ItemProperty -Path $global:RegPath -Name 'WimEngine' -ErrorAction SilentlyContinue).WimEngine
            if ([string]::IsNullOrEmpty($wimEngine) -or $wimEngine -notin @('dism','wimlib','7zip')) {
                $wimEngine = 'dism'
            }

            # Validate wimlib availability -- fall back to DISM if not found
            $wimlibExe = $null
            if ($wimEngine -eq 'wimlib') {
                $wimlibDir = Join-Path $global:ToolsDirectory 'Wimlib'
                $wimlibExe = Join-Path $wimlibDir 'wimlib-imagex.exe'
                if (-not (Test-Path $wimlibExe)) {
                    Write-DATLogEntry -Value "[$OEM] wimlib-imagex.exe not found in $wimlibDir -- falling back to DISM" -Severity 2 -UpdateUI
                    $wimEngine = 'dism'
                    $wimlibExe = $null
                }
            }

            # Validate 7-Zip availability -- fall back to DISM if not found
            $7zipExe = $null
            if ($wimEngine -eq '7zip') {
                foreach ($candidate in @(
                    (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
                    (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe')
                )) {
                    if (Test-Path $candidate) { $7zipExe = $candidate; break }
                }
                if (-not $7zipExe) {
                    try { $7zipExe = (Get-Command '7z.exe' -ErrorAction Stop).Source } catch { }
                }
                if ([string]::IsNullOrEmpty($7zipExe) -or -not (Test-Path $7zipExe)) {
                    Write-DATLogEntry -Value "[$OEM] 7z.exe not found -- falling back to DISM" -Severity 2 -UpdateUI
                    $wimEngine = 'dism'
                    $7zipExe = $null
                }
            }

            Write-DATLogEntry -Value "[$OEM] WIM Engine: $wimEngine" -Severity 1 -UpdateUI

            # DISM-specific pre-flight: kill orphaned processes and clean stale mounts
            if ($wimEngine -eq 'dism') {
            # Kill any orphaned DISM/dismhost processes before starting.
            # dismhost.exe is the actual worker - it must be killed first, then dism.exe.
            foreach ($procName in @('dismhost', 'dism')) {
                Get-Process -Name $procName -ErrorAction SilentlyContinue | ForEach-Object {
                    Write-DATLogEntry -Value "[$OEM] Killing orphaned $procName process (PID: $($_.Id))" -Severity 2
                    try { $_.Kill() } catch { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
                }
            }
            # Wait for handles to release after process kills
            Start-Sleep -Seconds 3

            # Clean stale DISM mount registry entries that block future operations
            $dismMountKey = 'HKLM:\SOFTWARE\Microsoft\WIMMount\Mounted Images'
            if (Test-Path $dismMountKey) {
                try {
                    $mountEntries = Get-ChildItem $dismMountKey -ErrorAction SilentlyContinue
                    if ($mountEntries) {
                        foreach ($entry in $mountEntries) {
                            Write-DATLogEntry -Value "[$OEM] Removing stale DISM mount registry entry: $($entry.PSChildName)" -Severity 2
                            Remove-Item $entry.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                } catch {
                    Write-DATLogEntry -Value "[$OEM] Could not clean DISM mount registry: $($_.Exception.Message)" -Severity 2
                }
            }

            # Run dism.exe /Cleanup-Wim as an external process to clear stale mounts.
            # Do NOT use DISM PowerShell cmdlets (Clear-WindowsCorruptMountPoint,
            # Get-WindowsImage, Dismount-WindowsImage) -- they use in-process COM interop
            # with dismhost.exe and can corrupt the process if dismhost was previously killed.
            Write-DATLogEntry -Value "[$OEM] Running dism.exe /Cleanup-Wim to clear stale mounts..." -Severity 1
            try {
                $dismCleanup = Start-Process -FilePath "$env:SystemRoot\System32\dism.exe" `
                    -ArgumentList '/Cleanup-Wim' -WindowStyle Hidden -PassThru
                $dismCleanup.WaitForExit(15000)
                if (-not $dismCleanup.HasExited) {
                    Write-DATLogEntry -Value "[$OEM] dism.exe /Cleanup-Wim timed out -- force-killing" -Severity 2
                    try { $dismCleanup.Kill() } catch {}
                } else {
                    Write-DATLogEntry -Value "[$OEM] dism.exe /Cleanup-Wim completed (exit code $($dismCleanup.ExitCode))" -Severity 1
                }
            } catch {
                Write-DATLogEntry -Value "[$OEM] Could not run dism.exe /Cleanup-Wim -- $($_.Exception.Message)" -Severity 2
            }

            # Also clean up any DAT temp files from previous crashed runs
            Get-ChildItem -Path $localWorkDir -Filter 'DAT_DISM_*' -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            } # end DISM-specific pre-flight

            # Clean up any existing WIM file from a previous run
            if (Test-Path $WimFile) {
                Write-DATLogEntry -Value "[$OEM] Removing existing WIM file: $WimFile" -Severity 1
                try {
                    Remove-Item $WimFile -Force -ErrorAction Stop
                } catch {
                    Write-DATLogEntry -Value "[$OEM] Cannot remove existing WIM - file may still be locked" -Severity 2
                    Start-Sleep -Seconds 3
                    Remove-Item $WimFile -Force -ErrorAction SilentlyContinue
                }
            }

            # Read compression level setting (applies to both engines)
            $dismCompressionLevel = (Get-ItemProperty -Path $global:RegPath -Name 'DismCompression' -ErrorAction SilentlyContinue).DismCompression
            if ([string]::IsNullOrEmpty($dismCompressionLevel) -or $dismCompressionLevel -notin @('fast','max','none')) {
                $dismCompressionLevel = 'fast'
            }

            $startTime = Get-Date

            if ($wimEngine -eq 'wimlib') {
                # ── wimlib-imagex capture ────────────────────────────────────────────
                # Map compression level to wimlib equivalents
                $wimlibCompressArg = switch ($dismCompressionLevel) {
                    'max'  { 'LZX' }
                    'none' { 'none' }
                    default { 'XPRESS' }
                }
                $wimlibArgs = "capture `"$DriverFolder`" `"$WimFile`" `"$WimDescription`" --compress=$wimlibCompressArg --threads=0 --no-acls"
                Write-DATLogEntry -Value "[$OEM] WIM Engine: wimlib-imagex" -Severity 1 -UpdateUI
                Write-DATLogEntry -Value "[$OEM] Command: $wimlibExe $wimlibArgs" -Severity 1
                Write-DATLogEntry -Value "[$OEM] Compression: $wimlibCompressArg (multi-threaded)" -Severity 1
                Set-DATRegistryValue -Name "RunningMessage" -Value "wimlib creating WIM for $OEM $Model ($wimlibCompressArg)..." -Type String

                # Reset ACLs on extracted driver folder to ensure wimlib can read all files
                # Some OEM driver packages (e.g. Dell) extract with restrictive ACLs
                Write-DATLogEntry -Value "[$OEM] Resetting file permissions on driver folder..." -Severity 1
                try {
                    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
                    $takeownResult = Start-Process -FilePath "takeown.exe" -ArgumentList "/F `"$DriverFolder`" /R /D Y" `
                        -NoNewWindow -Wait -PassThru -RedirectStandardOutput ([System.IO.Path]::GetTempFileName()) -ErrorAction SilentlyContinue
                    $icaclsResult = Start-Process -FilePath "icacls.exe" -ArgumentList "`"$DriverFolder`" /grant `"${currentUser}:(OI)(CI)R`" /T /Q /C" `
                        -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
                    if ($icaclsResult -and $icaclsResult.ExitCode -ne 0) {
                        Write-DATLogEntry -Value "[$OEM] Warning: ACL grant returned exit code $($icaclsResult.ExitCode)" -Severity 2
                    }
                } catch {
                    Write-DATLogEntry -Value "[$OEM] Warning: Permission reset failed: $($_.Exception.Message)" -Severity 2
                }

                $wimlibStdout = Join-Path $localWorkDir "DAT_wimlib_stdout.log"
                $wimlibStderr = Join-Path $localWorkDir "DAT_wimlib_stderr.log"

                # Run wimlib -- retry once on access denied (exit code 47) after forcing permissions
                $wimlibAttempt = 0
                $maxAttempts = 2
                do {
                    $wimlibAttempt++
                    if (Test-Path $wimlibStdout) { Remove-Item $wimlibStdout -Force -ErrorAction SilentlyContinue }
                    if (Test-Path $wimlibStderr) { Remove-Item $wimlibStderr -Force -ErrorAction SilentlyContinue }
                    # Remove partial WIM from failed attempt
                    if ($wimlibAttempt -gt 1 -and (Test-Path $WimFile)) {
                        Remove-Item $WimFile -Force -ErrorAction SilentlyContinue
                    }

                    try {
                        $wimlibProcess = Start-Process -FilePath $wimlibExe -ArgumentList $wimlibArgs `
                            -NoNewWindow -Wait -PassThru `
                            -RedirectStandardOutput $wimlibStdout -RedirectStandardError $wimlibStderr -ErrorAction Stop
                    } catch {
                        Write-DATLogEntry -Value "[$OEM] Failed to launch wimlib-imagex: $($_.Exception.Message)" -Severity 3 -UpdateUI
                        throw "Failed to launch wimlib-imagex: $($_.Exception.Message)"
                    }

                    if ($wimlibProcess.ExitCode -eq 47 -and $wimlibAttempt -lt $maxAttempts) {
                        Write-DATLogEntry -Value "[$OEM] wimlib access denied (exit 47) -- retaking ownership and retrying..." -Severity 2
                        try {
                            Start-Process -FilePath "takeown.exe" -ArgumentList "/F `"$DriverFolder`" /R /A /D Y" `
                                -NoNewWindow -Wait -RedirectStandardOutput ([System.IO.Path]::GetTempFileName()) -ErrorAction SilentlyContinue
                            Start-Process -FilePath "icacls.exe" -ArgumentList "`"$DriverFolder`" /grant *S-1-5-32-545:(OI)(CI)R /T /Q /C" `
                                -NoNewWindow -Wait -ErrorAction SilentlyContinue
                        } catch {
                            Write-DATLogEntry -Value "[$OEM] Warning: Retry permission fix failed: $($_.Exception.Message)" -Severity 2
                        }
                    }
                } while ($wimlibProcess.ExitCode -eq 47 -and $wimlibAttempt -lt $maxAttempts)

                # Log output
                if (Test-Path $wimlibStdout) {
                    $stdoutContent = Get-Content $wimlibStdout -ErrorAction SilentlyContinue
                    foreach ($line in $stdoutContent) {
                        if (-not [string]::IsNullOrWhiteSpace($line)) {
                            Write-DATLogEntry -Value "[$OEM] wimlib: $line" -Severity 1
                        }
                    }
                    Remove-Item $wimlibStdout -Force -ErrorAction SilentlyContinue
                }
                if (Test-Path $wimlibStderr) {
                    $stderrContent = Get-Content $wimlibStderr -ErrorAction SilentlyContinue
                    foreach ($line in $stderrContent) {
                        if (-not [string]::IsNullOrWhiteSpace($line)) {
                            Write-DATLogEntry -Value "[$OEM] wimlib error: $line" -Severity 2
                        }
                    }
                    Remove-Item $wimlibStderr -Force -ErrorAction SilentlyContinue
                }

                $totalTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                $effectiveExitCode = $wimlibProcess.ExitCode
                Write-DATLogEntry -Value "[$OEM] wimlib-imagex exited with code $effectiveExitCode after ${totalTime}s" -Severity 1 -UpdateUI

            } elseif ($wimEngine -eq '7zip') {
                # ── 7-Zip WIM capture ────────────────────────────────────────────────
                # 7-Zip supports WIM creation natively via -twim archive type.
                $7zipCompressArg = switch ($dismCompressionLevel) {
                    'max'  { '-mx=9' }
                    'none' { '-mx=0' }
                    default { '-mx=1' }
                }
                Write-DATLogEntry -Value "[$OEM] WIM Engine: 7-Zip" -Severity 1 -UpdateUI
                Write-DATLogEntry -Value "[$OEM] 7z.exe path: $7zipExe" -Severity 1
                Write-DATLogEntry -Value "[$OEM] Compression: $7zipCompressArg" -Severity 1
                Set-DATRegistryValue -Name "RunningMessage" -Value "7-Zip creating WIM for $OEM $Model..." -Type String

                $7zipStdout = Join-Path $localWorkDir "DAT_7zip_stdout.log"
                $7zipStderr = Join-Path $localWorkDir "DAT_7zip_stderr.log"
                if (Test-Path $7zipStdout) { Remove-Item $7zipStdout -Force -ErrorAction SilentlyContinue }
                if (Test-Path $7zipStderr) { Remove-Item $7zipStderr -Force -ErrorAction SilentlyContinue }

                $7zipArgs = "a -twim `"$WimFile`" `"$DriverFolder\*`" $7zipCompressArg"
                Write-DATLogEntry -Value "[$OEM] Command: `"$7zipExe`" $7zipArgs" -Severity 1

                $7zipProcess = Start-Process -FilePath $7zipExe -ArgumentList $7zipArgs `
                    -WindowStyle Hidden -Wait -PassThru `
                    -RedirectStandardOutput $7zipStdout -RedirectStandardError $7zipStderr

                # Log output
                if (Test-Path $7zipStdout) {
                    $stdoutContent = Get-Content $7zipStdout -ErrorAction SilentlyContinue
                    foreach ($line in $stdoutContent) {
                        if (-not [string]::IsNullOrWhiteSpace($line)) {
                            Write-DATLogEntry -Value "[$OEM] 7zip: $line" -Severity 1
                        }
                    }
                    Remove-Item $7zipStdout -Force -ErrorAction SilentlyContinue
                }
                if (Test-Path $7zipStderr) {
                    $stderrContent = Get-Content $7zipStderr -ErrorAction SilentlyContinue
                    foreach ($line in $stderrContent) {
                        if (-not [string]::IsNullOrWhiteSpace($line)) {
                            Write-DATLogEntry -Value "[$OEM] 7zip error: $line" -Severity 2
                        }
                    }
                    Remove-Item $7zipStderr -Force -ErrorAction SilentlyContinue
                }

                $totalTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                $effectiveExitCode = $7zipProcess.ExitCode
                Write-DATLogEntry -Value "[$OEM] 7-Zip exited with code $effectiveExitCode after ${totalTime}s" -Severity 1 -UpdateUI

            } else {
                # ── External dism.exe /Capture-Image ─────────────────────────────────
                # Run DISM as an external process instead of the in-process New-WindowsImage
                # cmdlet. The cmdlet uses COM interop with dismhost.exe -- if the user aborts
                # and dismhost is killed, the shared COM state corrupts the PowerShell process
                # causing a crash. External dism.exe is cleanly killable.
                Write-DATLogEntry -Value "[$OEM] WIM Engine: DISM (dism.exe /Capture-Image)" -Severity 1 -UpdateUI
                Write-DATLogEntry -Value "[$OEM] WIM output path: $WimFile" -Severity 1
                Write-DATLogEntry -Value "[$OEM] WIM source path: $DriverFolder" -Severity 1
                Write-DATLogEntry -Value "[$OEM] Compression: $dismCompressionLevel" -Severity 1

                $compressionType = switch ($dismCompressionLevel) {
                    'max'  { 'Max' }
                    'none' { 'None' }
                    default { 'Fast' }
                }

                Set-DATRegistryValue -Name "RunningMessage" -Value "Creating WIM for $OEM $Model ($compressionType)..." -Type String

                # Build batch wrapper -- cmd.exe shell-level redirection avoids pipe deadlocks
                # in background runspaces. -WindowStyle Hidden allocates a real console (required
                # by DISM; CreateNoWindow causes DISM to hang with 0 CPU).
                $dismLogFile = Join-Path $localWorkDir "DAT_DISM_capture.log"
                $dismBatchFile = Join-Path $localWorkDir "DAT_DISM_capture.cmd"
                $dismStdoutFile = Join-Path $localWorkDir "DAT_DISM_stdout.log"
                $dismCmd = "`"$env:SystemRoot\System32\dism.exe`" /Capture-Image /ImageFile:`"$WimFile`" /CaptureDir:`"$DriverFolder`" /Name:`"$WimDescription`" /Description:`"$WimDescription`" /Compress:$compressionType /Verify /LogPath:`"$dismLogFile`" /LogLevel:3"
                Set-Content -Path $dismBatchFile -Value "@echo off`r`n$dismCmd > `"$dismStdoutFile`" 2>&1`r`nexit /b %ERRORLEVEL%" -Encoding ASCII
                Write-DATLogEntry -Value "[$OEM] DISM command: $dismCmd" -Severity 1

                $dismProcess = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$dismBatchFile`"" `
                    -WindowStyle Hidden -PassThru
                Set-DATRegistryValue -Name "RunningProcess" -Type String -Value "dism"
                Set-DATRegistryValue -Name "RunningProcessID" -Type String -Value "$($dismProcess.Id)"

                # Wait for completion -- poll so the abort signal can be detected
                while (-not $dismProcess.HasExited) {
                    Start-Sleep -Seconds 2
                    # Check for user abort
                    $abortCheck = Get-ItemProperty -Path $global:RegPath -Name 'RunningState' -ErrorAction SilentlyContinue
                    if ($abortCheck.RunningState -eq 'Aborted') {
                        Write-DATLogEntry -Value "[$OEM] DISM aborted by user -- killing dism.exe" -Severity 2
                        try { $dismProcess.Kill() } catch { Stop-Process -Id $dismProcess.Id -Force -ErrorAction SilentlyContinue }
                        # Also kill dismhost.exe worker
                        Get-Process -Name 'dismhost' -ErrorAction SilentlyContinue | ForEach-Object {
                            try { $_.Kill() } catch { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
                        }
                        break
                    }
                }

                $effectiveExitCode = if ($dismProcess.HasExited) { $dismProcess.ExitCode } else { 1 }

                # DISM can hang after completing -- detect via stdout and force-kill
                if (-not $dismProcess.HasExited) {
                    $stdoutCheck = if (Test-Path $dismStdoutFile) { Get-Content $dismStdoutFile -Raw -ErrorAction SilentlyContinue } else { '' }
                    if ($stdoutCheck -match 'The operation completed successfully') {
                        Write-DATLogEntry -Value "[$OEM] DISM completed but process hung -- force-killing" -Severity 2
                        try { $dismProcess.Kill() } catch { Stop-Process -Id $dismProcess.Id -Force -ErrorAction SilentlyContinue }
                        $effectiveExitCode = 0
                    }
                }

                # Wait for dismhost.exe to release file locks
                Start-Sleep -Seconds 3
                Get-Process -Name 'dismhost' -ErrorAction SilentlyContinue | ForEach-Object {
                    Write-DATLogEntry -Value "[$OEM] Killing lingering dismhost.exe (PID: $($_.Id))" -Severity 2
                    try { $_.Kill() } catch { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
                }

                # Clean stale DISM mount registry entries
                $dismMountKey = 'HKLM:\SOFTWARE\Microsoft\WIMMount\Mounted Images'
                if (Test-Path $dismMountKey) {
                    Get-ChildItem $dismMountKey -ErrorAction SilentlyContinue |
                        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                }

                # Log DISM stdout
                if (Test-Path $dismStdoutFile) {
                    $stdoutLines = Get-Content $dismStdoutFile -ErrorAction SilentlyContinue
                    foreach ($line in $stdoutLines) {
                        if (-not [string]::IsNullOrWhiteSpace($line)) {
                            Write-DATLogEntry -Value "[$OEM] DISM: $line" -Severity 1
                        }
                    }
                    Remove-Item $dismStdoutFile -Force -ErrorAction SilentlyContinue
                }

                # Clean up batch file
                Remove-Item $dismBatchFile -Force -ErrorAction SilentlyContinue
                Remove-Item $dismLogFile -Force -ErrorAction SilentlyContinue

                $totalTime = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
                Write-DATLogEntry -Value "[$OEM] dism.exe /Capture-Image completed with code $effectiveExitCode after ${totalTime}s" -Severity 1 -UpdateUI
                Set-DATRegistryValue -Name "RunningProcessID" -Value " " -Type String
                Set-DATRegistryValue -Name "RunningProcess"   -Value " " -Type String
            } # end DISM else block

            if ($effectiveExitCode -eq 0) {
                # Stage WIM in the temp directory (not the package destination).
                # Only the final ConfigMgr/Intune/standalone package should be in the Package Storage Path.
                $destDriverMountFolder = Join-Path -Path $global:TempDirectory -ChildPath "Packaged\$OEM\$Model\$OS"
                if (-not (Test-Path -Path $destDriverMountFolder)) {
                    New-Item -Path $destDriverMountFolder -ItemType Directory -Force | Out-Null
                }
                $destWimFile = Join-Path -Path $destDriverMountFolder -ChildPath "DriverPackage.wim"
                Write-DATLogEntry -Value "[$OEM] Staging WIM to temp directory: $destWimFile" -Severity 1 -UpdateUI
                Set-DATRegistryValue -Name "RunningMessage" -Value "Staging WIM - $OEM $Model..." -Type String
                Copy-Item -Path $WimFile -Destination $destWimFile -Force
                Write-DATLogEntry -Value "[$OEM] WIM staged in temp directory successfully" -Severity 1
                $WimFile = $destWimFile

                # Clean up local temp working directory (extracted files + temp WIM)
                Remove-Item -Path $localWorkDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-DATLogEntry -Value "[$OEM] Temp working directory cleaned up: $localWorkDir" -Severity 1

                $wimSize = [math]::Round((Get-Item $WimFile).Length / 1MB, 2)
                Set-DATRegistryValue -Name "PackagedDriverPath" -Value "$WimFile" -Type String
                Set-DATRegistryValue -Name "RunningMode" -Value "Extract Ready" -Type String
                Set-DATRegistryValue -Name "RunningMessage" -Value "WIM package created ($wimSize MB) - $OEM $Model" -Type String
                Write-DATLogEntry -Value "[$OEM] WIM package created: $WimFile ($wimSize MB)" -Severity 1 -UpdateUI
            } elseif ($effectiveExitCode -eq 740) {
                $errorMsg = "WIM creation requires elevation (Run as Administrator). DISM exit code 740."
                Set-DATRegistryValue -Name "RunningState" -Value "Error" -Type String
                Set-DATRegistryValue -Name "RunningMessage" -Value "$errorMsg - $OEM $Model" -Type String
                Write-DATLogEntry -Value "[Error] - $errorMsg" -Severity 3 -UpdateUI
                throw $errorMsg
            } else {
                $errorMsg = "WIM creation failed with exit code $effectiveExitCode"
                Set-DATRegistryValue -Name "RunningState" -Value "Error" -Type String
                Set-DATRegistryValue -Name "RunningMessage" -Value "$errorMsg - $OEM $Model" -Type String
                Write-DATLogEntry -Value "[Error] - $errorMsg" -Severity 3 -UpdateUI
                throw $errorMsg
            }
        } catch {
            if ($_.Exception.Message -notmatch 'exit code') {
                Write-DATLogEntry -Value "[Error] - WIM creation failed: $($_.Exception.Message)" -Severity 3 -UpdateUI
                Set-DATRegistryValue -Name "RunningMessage" -Value "WIM creation error - $OEM $Model" -Type String
            }
            # Clean up temp working directory on failure
            if (Test-Path $localWorkDir) {
                Remove-Item -Path $localWorkDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-DATLogEntry -Value "[$OEM] Temp working directory cleaned up after failure" -Severity 2
            }
            throw
        }
    }
}

#endregion Download

#region ConfigMgr

function Get-DATSiteCode {
    param ([Parameter(Mandatory = $true)][string]$SiteServer)
    try {
        Write-DATLogEntry -Value "[WMI] Querying \\$SiteServer\root\SMS : SMS_ProviderLocation for site code" -Severity 1
        $SiteCodeObjects = Get-WmiObject -ComputerName $SiteServer -Namespace "root\SMS" -Class SMS_ProviderLocation -ErrorAction Stop
        foreach ($obj in $SiteCodeObjects) {
            if ($obj.ProviderForLocalSite -eq $true) {
                $global:SiteCode = $obj.SiteCode
                Write-DATLogEntry -Value "[WMI] Site code resolved: $($global:SiteCode)" -Severity 1
                Set-DATRegistryValue -Name "SiteCode" -Value $global:SiteCode -Type String
                return $global:SiteCode
            }
        }
    } catch {
        Write-DATLogEntry -Value "[Error] - Site code query failed: $($_.Exception.Message)" -Severity 3
    }
}

function Connect-DATConfigMgr {
    param (
        [Parameter(Mandatory = $true)][string]$SiteServer,
        [Parameter(Mandatory = $true)][boolean]$WinRMOverSSL,
        [boolean]$KnownModels
    )
    if (-not ([string]::IsNullOrEmpty($SiteServer))) {
        try {
            if ($WinRMOverSSL) {
                [string]$ConfigMgrDiscovery = (Test-WSMan -ComputerName $SiteServer -UseSSL -ErrorAction SilentlyContinue).wsmid
            } else {
                [string]$ConfigMgrDiscovery = (Test-WSMan -ComputerName $SiteServer -ErrorAction SilentlyContinue).wsmid
            }
        } catch {
            Write-DATLogEntry -Value "[Error] - WinRM connection failed: $($_.Exception.Message)" -Severity 3
        }
        if ($null -ne $ConfigMgrDiscovery) {
            try {
                Get-DATSiteCode -SiteServer $SiteServer
                $global:SiteServer = $SiteServer
                Set-DATRegistryValue -Name "SiteServer" -Value $SiteServer -Type String
                if ($null -ne $env:SMS_ADMIN_UI_PATH) {
                    $ModuleName = (Get-Item $env:SMS_ADMIN_UI_PATH | Split-Path -Parent) + "\ConfigurationManager.psd1"
                    Import-Module $ModuleName
                    $global:ConfigMgrValidation = $true
                }
            } catch {
                Write-DATLogEntry -Value "[Error] - ConfigMgr connection failed: $($_.Exception.Message)" -Severity 3
            }
        }
    }
}

function Get-DATConfigMgrKnownModels {
    <#
    .SYNOPSIS
        Queries ConfigMgr hardware inventory via CIM to discover known device makes and models.
    .DESCRIPTION
        Connects to the ConfigMgr site server's SMS WMI namespace and queries hardware inventory
        classes (SMS_G_System_COMPUTER_SYSTEM and SMS_G_System_MS_SYSTEMINFORMATION) to identify
        distinct device makes and models actively deployed in the environment.
        Supports HP, Dell, Lenovo, Microsoft, and Acer.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$SiteServer,
        [Parameter(Mandatory = $true)][string]$SiteCode,
        [Parameter()][scriptblock]$OnProgress
    )

    $namespace = "root/SMS/site_$SiteCode"
    $devicePairs = [System.Collections.Generic.Dictionary[string, PSCustomObject]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $cimSession = $null

    try {
        if ($OnProgress) { & $OnProgress "Connecting to $SiteServer..." }
        Write-DATLogEntry -Value "[ConfigMgr Known Models] Connecting CIM session to $SiteServer" -Severity 1

        $cimSession = New-CimSession -ComputerName $SiteServer -ErrorAction Stop

        # --- OEM query definitions ---
        # Each entry: OEM display name, WQL query, Make property, Model property
        $oemQueries = @(
            @{
                OEM   = 'HP'
                Query = "SELECT DISTINCT Manufacturer, Model FROM SMS_G_System_COMPUTER_SYSTEM WHERE (Manufacturer = 'Hewlett-Packard' OR Manufacturer = 'HP') AND Model NOT LIKE '%Proliant%'"
                MakeProp  = 'Manufacturer'
                ModelProp = 'Model'
                NormalizeMake  = 'HP'
                NormalizeModel = $true
            },
            @{
                OEM   = 'Dell'
                Query = "SELECT DISTINCT Manufacturer, Model FROM SMS_G_System_COMPUTER_SYSTEM WHERE Manufacturer = 'Dell Inc.' AND (Model LIKE '%Optiplex%' OR Model LIKE '%PRO%' OR Model LIKE '%Latitude%' OR Model LIKE '%Precision%' OR Model LIKE '%XPS%' OR Model LIKE '%Vostro%' OR Model LIKE '%Inspiron%')"
                MakeProp  = 'Manufacturer'
                ModelProp = 'Model'
                NormalizeMake  = 'Dell'
                NormalizeModel = $false
            },
            @{
                OEM   = 'Lenovo'
                Query = "SELECT DISTINCT Manufacturer, Model FROM SMS_G_System_COMPUTER_SYSTEM WHERE Manufacturer = 'LENOVO'"
                MakeProp  = 'Manufacturer'
                ModelProp = 'Model'
                NormalizeMake  = 'Lenovo'
                NormalizeModel = $false
            },
            @{
                OEM   = 'Microsoft'
                Query = "SELECT DISTINCT SystemManufacturer, SystemProductName FROM SMS_G_System_MS_SYSTEMINFORMATION WHERE SystemManufacturer LIKE 'Microsoft%' AND SystemProductName LIKE 'Surface%'"
                MakeProp  = 'SystemManufacturer'
                ModelProp = 'SystemProductName'
                NormalizeMake  = 'Microsoft'
                NormalizeModel = $false
            },
            @{
                OEM   = 'Acer'
                Query = "SELECT DISTINCT Manufacturer, Model FROM SMS_G_System_COMPUTER_SYSTEM WHERE Manufacturer = 'Acer'"
                MakeProp  = 'Manufacturer'
                ModelProp = 'Model'
                NormalizeMake  = 'Acer'
                NormalizeModel = $false
            }
        )

        foreach ($oem in $oemQueries) {
            if ($OnProgress) { & $OnProgress "Querying $($oem.OEM) models..." }
            Write-DATLogEntry -Value "[ConfigMgr Known Models] Querying $($oem.OEM): $($oem.Query)" -Severity 1

            try {
                $results = @(Get-CimInstance -CimSession $cimSession -Namespace $namespace -Query $oem.Query -ErrorAction Stop)
                Write-DATLogEntry -Value "[ConfigMgr Known Models] $($oem.OEM): $($results.Count) raw results" -Severity 1

                foreach ($item in $results) {
                    $make = $oem.NormalizeMake
                    $model = $item.($oem.ModelProp)
                    if ([string]::IsNullOrWhiteSpace($model)) { continue }
                    $model = $model.Trim()

                    # HP model name normalization
                    if ($oem.NormalizeModel) {
                        $model = $model -replace '^(HP|Hewlett-Packard|COMPAQ|Hp|Compaq)\s*', ''
                        $model = $model -replace '\sSFF\b', ' Small Form Factor'
                        $model = $model -replace '\sUSDT\b', ' Desktop'
                        $model = $model -replace '\sTWR\b', ' Tower'
                        $model = $model -replace '\s*35W$', ''
                        $model = $model -replace '\s+PC$', ''
                        $model = $model.Trim()
                    }

                    # Lenovo: resolve 4-char machine type to friendly model name
                    if ($oem.OEM -eq 'Lenovo' -and $model.Length -ge 4) {
                        $friendlyName = Find-DATLenovoModelType -ModelType $model.Substring(0, 4)
                        if (-not [string]::IsNullOrEmpty($friendlyName)) {
                            $model = $friendlyName.Trim()
                        }
                    }

                    if (-not [string]::IsNullOrEmpty($model)) {
                        $key = "$make|$model"
                        if (-not $devicePairs.ContainsKey($key)) {
                            $devicePairs[$key] = [PSCustomObject]@{ Make = $make; Model = $model }
                        }
                    }
                }
            }
            catch {
                Write-DATLogEntry -Value "[ConfigMgr Known Models] $($oem.OEM) query failed: $($_.Exception.Message)" -Severity 2
            }
        }
    }
    catch {
        Write-DATLogEntry -Value "[ConfigMgr Known Models] CIM session failed: $($_.Exception.Message)" -Severity 3
        throw
    }
    finally {
        if ($cimSession) {
            Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue
        }
    }

    $devices = @($devicePairs.Values | Sort-Object -Property Make, Model)
    $uniqueMakes = @($devices | Select-Object -ExpandProperty Make -Unique)
    $uniqueModels = @($devices | Select-Object -ExpandProperty Model -Unique)

    if ($OnProgress) { & $OnProgress "Discovered $($uniqueMakes.Count) makes and $($uniqueModels.Count) models" }
    Write-DATLogEntry -Value "[ConfigMgr Known Models] Complete: $($uniqueMakes.Count) makes, $($uniqueModels.Count) models, $($devices.Count) unique combinations" -Severity 1

    return [PSCustomObject]@{
        Makes   = [string[]]$uniqueMakes
        Models  = [string[]]$uniqueModels
        Devices = $devices
    }
}

function Get-DATDistributionPoints {
    param (
        [Parameter(Mandatory = $true)][string]$SiteCode,
        [Parameter(Mandatory = $true)][string]$SiteServer
    )
    Write-DATLogEntry -Value "[WMI] Querying \\$SiteServer\Root\SMS\Site_$SiteCode : SMS_SystemResourceList (Role: Distribution Point)" -Severity 1
    [Array]$DistributionPoints = Get-WmiObject -ComputerName $SiteServer -Namespace "Root\SMS\Site_$SiteCode" -Class SMS_SystemResourceList |
        Where-Object { $_.RoleName -match "Distribution" } | Select-Object -ExpandProperty ServerName -Unique | Sort-Object
    Write-DATLogEntry -Value "[WMI] Distribution Points found: $(@($DistributionPoints).Count) -- $($DistributionPoints -join ', ')" -Severity 1
    return $DistributionPoints
}

function Get-DATDistributionPointGroups {
    param (
        [Parameter(Mandatory = $true)][string]$SiteCode,
        [Parameter(Mandatory = $true)][string]$SiteServer
    )
    Write-DATLogEntry -Value "[WMI] Querying \\$SiteServer\Root\SMS\Site_$SiteCode : SMS_DistributionPointGroup (SELECT Distinct Name)" -Severity 1
    [Array]$DPGroups = Get-WmiObject -ComputerName $SiteServer -Namespace "Root\SMS\Site_$SiteCode" -Query "SELECT Distinct Name FROM SMS_DistributionPointGroup" | Select-Object -ExpandProperty Name
    Write-DATLogEntry -Value "[WMI] DP Groups found: $(@($DPGroups).Count) -- $($DPGroups -join ', ')" -Severity 1
    return $DPGroups
}

function New-DATConfigMgrPkg {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$DriverPackage,
        [Parameter(Mandatory)][string]$OEM,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$OS,
        [Parameter(Mandatory)][string]$Architecture,
        [Parameter(Mandatory)][string]$Baseboards,
        [Parameter(Mandatory)][string]$PackagePath,
        [Parameter(Mandatory)][string]$SiteServer,
        [Parameter(Mandatory)][string]$SiteCode,
        [Parameter(Mandatory)][string]$Version,
        [ValidateSet('Drivers','BIOS')][string]$PackageType = 'Drivers',
        [string[]]$DistributionPointGroups,
        [string[]]$DistributionPoints,
        [ValidateSet('High','Normal','Low')][string]$Priority = 'Normal',
        [switch]$ForceUpdate
    )

    try {
        $smsNamespace = "root\SMS\Site_$SiteCode"
        $packagePrefix = if ($PackageType -eq 'BIOS') { 'BIOS Update' } else { 'Drivers' }
        $CMPackage = if ($PackageType -eq 'BIOS') {
            "$packagePrefix - $OEM $Model"
        } else {
            "$packagePrefix - $OEM $Model - $OS $Architecture"
        }
        $folderName = if ($PackageType -eq 'BIOS') { "BIOS Packages" } else { "Driver Packages" }

        # --- Stage 1: Check existing package via WMI before copying files ---
        Write-DATLogEntry -Value "- [ConfigMgr] Checking for existing package: $CMPackage (version $Version)" -Severity 1
        $wmiQuery = "SELECT PackageID, Name, Version, PkgSourcePath FROM SMS_Package WHERE Name = '$($CMPackage -replace "'","''")'"
        $existingPkgs = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace -Query $wmiQuery -ErrorAction Stop
        $matchingPkg = $existingPkgs | Where-Object { $_.Version -eq $Version }

        if ($matchingPkg -and -not $ForceUpdate) {
            Write-DATLogEntry -Value "- [ConfigMgr] SKIPPED: '$CMPackage' version $Version already exists ($($matchingPkg.PackageID))" -Severity 1
            return $true
        }

        # Force Update path: update existing package in-place
        if ($matchingPkg -and $ForceUpdate) {
            $pkgId = $matchingPkg.PackageID
            Write-DATLogEntry -Value "- [ConfigMgr] FORCE UPDATE: Replacing content for '$CMPackage' ($pkgId)" -Severity 1

            # Get the existing source path from the package
            $existingSourcePath = $matchingPkg.PkgSourcePath
            if ([string]::IsNullOrEmpty($existingSourcePath)) {
                Write-DATLogEntry -Value "[Warning] - Existing package $pkgId has no source path, falling back to default" -Severity 2
                $existingSourcePath = if ($PackageType -eq 'BIOS') {
                    Join-Path -Path $PackagePath -ChildPath "$OEM\$Model\BIOS\$Version"
                } else {
                    Join-Path -Path $PackagePath -ChildPath "$OEM\$Model\$OS\$Architecture\$Version"
                }
            }

            # Clear and replace contents at the source path
            if (Test-Path $existingSourcePath) {
                Get-ChildItem -Path $existingSourcePath -Recurse -Force | Remove-Item -Recurse -Force
            } else {
                New-Item -Path $existingSourcePath -ItemType Directory -Force | Out-Null
            }
            if ($PackageType -eq 'BIOS' -and (Test-Path $DriverPackage -PathType Container)) {
                Write-DATLogEntry -Value "- [ConfigMgr] Replacing BIOS files at $existingSourcePath" -Severity 1
                Copy-Item -Path "$DriverPackage\*" -Destination $existingSourcePath -Recurse -Force
            } else {
                Write-DATLogEntry -Value "- [ConfigMgr] Replacing WIM at $existingSourcePath" -Severity 1
                Copy-Item -Path $DriverPackage -Destination $existingSourcePath -Force
            }

            # Update package version and description via WMI
            $pkgWmi = [wmi]"\\$SiteServer\$($smsNamespace):SMS_Package.PackageID='$pkgId'"
            $pkgWmi.Version = $Version
            $pkgWmi.Description = "Models included: $Baseboards"
            $pkgWmi.Put() | Out-Null
            Write-DATLogEntry -Value "- [ConfigMgr] Package $pkgId metadata updated" -Severity 1

            # Trigger content redistribution via RefreshPkgSource
            try {
                $pkgWmi.RefreshPkgSource() | Out-Null
                Write-DATLogEntry -Value "- [ConfigMgr] Content redistribution triggered for $pkgId" -Severity 1
            } catch {
                Write-DATLogEntry -Value "[Warning] - Failed to trigger redistribution: $($_.Exception.Message)" -Severity 2
            }

            # Also redistribute to selected DP groups
            if ($DistributionPointGroups -and $DistributionPointGroups.Count -gt 0) {
                foreach ($dpGroup in $DistributionPointGroups) {
                    try {
                        $dpgWmi = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
                            -Query "SELECT GroupID FROM SMS_DistributionPointGroup WHERE Name = '$($dpGroup -replace "'","''")'" `
                            -ErrorAction Stop | Select-Object -First 1
                        if ($dpgWmi) {
                            $dpgObj = [wmi]"\\$SiteServer\$($smsNamespace):SMS_DistributionPointGroup.GroupID='$($dpgWmi.GroupID)'"
                            $dpgObj.AddPackages(@($pkgId)) | Out-Null
                            Write-DATLogEntry -Value "- [ConfigMgr] Content redistributed to $dpGroup" -Severity 1
                        }
                    } catch {
                        Write-DATLogEntry -Value "[Warning] - Failed to redistribute to '$dpGroup': $($_.Exception.Message)" -Severity 2
                    }
                }
            }

            # Also redistribute to selected individual distribution points
            if ($DistributionPoints -and $DistributionPoints.Count -gt 0) {
                foreach ($dpServer in $DistributionPoints) {
                    try {
                        Write-DATLogEntry -Value "- [ConfigMgr] Redistributing package $pkgId to DP: $dpServer" -Severity 1
                        $dpNalPath = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
                            -Query "SELECT NALPath FROM SMS_DistributionPointInfo WHERE ServerName = '$($dpServer -replace "'","''")'" `
                            -ErrorAction Stop | Select-Object -First 1 -ExpandProperty NALPath
                        if ($dpNalPath) {
                            $newDP = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_DistributionPoint").CreateInstance()
                            $newDP.PackageID = $pkgId
                            $newDP.ServerNALPath = $dpNalPath
                            $newDP.SiteCode = $SiteCode
                            $newDP.Put() | Out-Null
                            Write-DATLogEntry -Value "- [ConfigMgr] Content redistributed to DP $dpServer" -Severity 1
                        } else {
                            Write-DATLogEntry -Value "[Warning] - DP '$dpServer' NALPath not found" -Severity 2
                        }
                    } catch {
                        Write-DATLogEntry -Value "[Warning] - Failed to redistribute to DP '$dpServer': $($_.Exception.Message)" -Severity 2
                    }
                }
            }

            return $true
        }

        # --- Stage 2: Copy WIM to destination (filesystem, no CM drive needed) ---
        $DestPath = if ($PackageType -eq 'BIOS') {
            Join-Path -Path $PackagePath -ChildPath "$OEM\$Model\BIOS\$Version"
        } else {
            Join-Path -Path $PackagePath -ChildPath "$OEM\$Model\$OS\$Architecture\$Version"
        }
        if (-not (Test-Path $DestPath)) { New-Item -Path $DestPath -ItemType Directory -Force | Out-Null }

        # BIOS ConfigMgr packages use a directory source; drivers use a single WIM file
        if ($PackageType -eq 'BIOS' -and (Test-Path $DriverPackage -PathType Container)) {
            Write-DATLogEntry -Value "- [ConfigMgr] Copying BIOS files to $DestPath" -Severity 1
            Copy-Item -Path "$DriverPackage\*" -Destination $DestPath -Recurse -Force
        } else {
            Write-DATLogEntry -Value "- [ConfigMgr] Copying WIM to $DestPath" -Severity 1
            Copy-Item -Path $DriverPackage -Destination $DestPath -Force
        }

        # --- Stage 3: Create package via WMI ---
        Write-DATLogEntry -Value "- [ConfigMgr] Creating new package: $CMPackage" -Severity 1

        $newPkg = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_Package").CreateInstance()
        $newPkg.Name = $CMPackage
        $newPkg.PkgSourcePath = $DestPath
        $newPkg.Manufacturer = $OEM
        $newPkg.Description = "Models included: $Baseboards"
        $newPkg.Version = $Version
        $newPkg.MIFName = $Model
        $newPkg.MIFVersion = "$OS $Architecture"
        $newPkg.PkgSourceFlag = 2  # Direct source path
        $putResult = $newPkg.Put()
        $packageId = $putResult.RelativePath -replace '.*PackageID="([^"]+)".*', '$1'

        Write-DATLogEntry -Value "- [ConfigMgr] Created package $packageId" -Severity 1

        # --- Stage 4: Move package into console folder (Driver Packages\OEM or BIOS Packages\OEM) ---
        try {
            # Find or create the top-level folder (e.g. "Driver Packages")
            $topFolder = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
                -Query "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE Name = '$folderName' AND ObjectType = 2 AND ParentContainerNodeID = 0" `
                -ErrorAction Stop | Select-Object -First 1
            if (-not $topFolder) {
                $newFolder = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_ObjectContainerNode").CreateInstance()
                $newFolder.Name = $folderName
                $newFolder.ObjectType = 2  # Package
                $newFolder.ParentContainerNodeID = 0
                $newFolder.Put() | Out-Null
                $topFolder = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
                    -Query "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE Name = '$folderName' AND ObjectType = 2 AND ParentContainerNodeID = 0" `
                    -ErrorAction Stop | Select-Object -First 1
            }
            $topFolderID = $topFolder.ContainerNodeID

            # Find or create the OEM sub-folder (e.g. "Driver Packages\Dell")
            $oemFolder = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
                -Query "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE Name = '$($OEM -replace "'","''")' AND ObjectType = 2 AND ParentContainerNodeID = $topFolderID" `
                -ErrorAction Stop | Select-Object -First 1
            if (-not $oemFolder) {
                $newOemFolder = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_ObjectContainerNode").CreateInstance()
                $newOemFolder.Name = $OEM
                $newOemFolder.ObjectType = 2
                $newOemFolder.ParentContainerNodeID = $topFolderID
                $newOemFolder.Put() | Out-Null
                $oemFolder = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
                    -Query "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE Name = '$($OEM -replace "'","''")' AND ObjectType = 2 AND ParentContainerNodeID = $topFolderID" `
                    -ErrorAction Stop | Select-Object -First 1
            }
            $oemFolderID = $oemFolder.ContainerNodeID

            # Move the package into the OEM folder
            $moveItem = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_ObjectContainerItem").CreateInstance()
            $moveItem.InstanceKey = $packageId
            $moveItem.ObjectType = 2
            $moveItem.ContainerNodeID = $oemFolderID
            $moveItem.Put() | Out-Null

            Write-DATLogEntry -Value "- [ConfigMgr] Moved package to $folderName\$OEM" -Severity 1
        } catch {
            Write-DATLogEntry -Value "[Warning] - Failed to move package to folder: $($_.Exception.Message)" -Severity 2
        }

        # --- Stage 5: Distribute content to selected DP groups and individual DPs ---
        if ($DistributionPointGroups -and $DistributionPointGroups.Count -gt 0) {
            foreach ($dpGroup in $DistributionPointGroups) {
                try {
                    Write-DATLogEntry -Value "- [ConfigMgr] Distributing package $packageId to DP group: $dpGroup" -Severity 1
                    $dpgWmi = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
                        -Query "SELECT GroupID FROM SMS_DistributionPointGroup WHERE Name = '$($dpGroup -replace "'","''")'" `
                        -ErrorAction Stop | Select-Object -First 1
                    if ($dpgWmi) {
                        $dpgObj = [wmi]"\\$SiteServer\$($smsNamespace):SMS_DistributionPointGroup.GroupID='$($dpgWmi.GroupID)'"
                        $dpgObj.AddPackages(@($packageId)) | Out-Null
                        Write-DATLogEntry -Value "- [ConfigMgr] Content distributed to $dpGroup" -Severity 1
                    } else {
                        Write-DATLogEntry -Value "[Warning] - DP group '$dpGroup' not found" -Severity 2
                    }
                } catch {
                    Write-DATLogEntry -Value "[Warning] - Failed to distribute to '$dpGroup': $($_.Exception.Message)" -Severity 2
                }
            }
        }

        if ($DistributionPoints -and $DistributionPoints.Count -gt 0) {
            foreach ($dpServer in $DistributionPoints) {
                try {
                    Write-DATLogEntry -Value "- [ConfigMgr] Distributing package $packageId to DP: $dpServer" -Severity 1
                    $dpNalPath = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
                        -Query "SELECT NALPath FROM SMS_DistributionPointInfo WHERE ServerName = '$($dpServer -replace "'","''")'" `
                        -ErrorAction Stop | Select-Object -First 1 -ExpandProperty NALPath
                    if ($dpNalPath) {
                        $newDP = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_DistributionPoint").CreateInstance()
                        $newDP.PackageID = $packageId
                        $newDP.ServerNALPath = $dpNalPath
                        $newDP.SiteCode = $SiteCode
                        $newDP.Put() | Out-Null
                        Write-DATLogEntry -Value "- [ConfigMgr] Content distributed to DP $dpServer" -Severity 1
                    } else {
                        Write-DATLogEntry -Value "[Warning] - DP '$dpServer' not found" -Severity 2
                    }
                } catch {
                    Write-DATLogEntry -Value "[Warning] - Failed to distribute to DP '$dpServer': $($_.Exception.Message)" -Severity 2
                }
            }
        }

        return $true
    } catch {
        Write-DATLogEntry -Value "[Error] - ConfigMgr package creation failed: $($_.Exception.Message)" -Severity 3
        Write-DATLogEntry -Value "[Error] - Stack: $($_.ScriptStackTrace)" -Severity 3
        return $false
    }
}

function Publish-DATConfigMgrPkg {
    param ([string]$Product, [string]$PackageID, [string]$ImportInto)
    # Content distribution handled by New-DATConfigMgrPkg
}

#endregion ConfigMgr

#region Utility

function Get-DATLocalSystemTime {
    return (Get-Date).ToUniversalTime()
}

function Get-DATOEMDownloadLinks {
    [CmdletBinding()]
    param (
        [Parameter(Position = 1)][ValidateSet('HP', 'Dell', 'Lenovo', 'Microsoft', 'Acer')][array]$OEM,
        [Parameter(Position = 2)][string]$OS,
        [Parameter(Position = 3)][ValidateSet('x64', 'x86', 'Arm64')][string]$Architecture,
        [Parameter(Position = 4)][ValidateSet('driver', 'bios', 'all')][string]$DownloadType,
        [Parameter(Position = 5)][string]$Model
    )

    Write-DATLogEntry -Value "[OEM Link Query] - Locating download link for $OEM $Model" -Severity 1

    $OEMLinksURL = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/OEMLinks.xml"
    try {
        $proxyParams = Get-DATWebRequestProxy
        $webContent = $null
        for ($i = 1; $i -le 3; $i++) {
            try {
                $webContent = (Invoke-WebRequest -Uri $OEMLinksURL -UseBasicParsing -TimeoutSec 30 @proxyParams).Content
                break
            } catch {
                if ($i -lt 3) {
                    Write-DATLogEntry -Value "[Warning] - OEM links attempt $i failed: $($_.Exception.Message). Retrying in 5s..." -Severity 2
                    Start-Sleep -Seconds 5
                } else { throw }
            }
        }
        [xml]$OEMLinks = $webContent
    } catch {
        Write-DATLogEntry -Value "[Error] - Failed to download OEM links: $($_.Exception.Message)" -Severity 3
        return $null
    }

    $result = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match $OEM }).Link
    if ($null -eq $result) {
        Write-DATLogEntry -Value "[Error] - No links found for OEM: $OEM" -Severity 3
        return $null
    }

    return $result
}

function Install-DATDriverPackage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][ValidateSet('Windows 10', 'Windows 11')][string]$TargetOS,
        [Parameter(Mandatory)][ValidateSet('22H2', '23H2', '24H2', '25H2')][string]$TargetOSBuild,
        [Parameter(Mandatory)][ValidatePattern('^[A-Z]:$')][string]$TargetDrive
    )
    Write-DATLogEntry -Value "[Driver Install] - $TargetOS $TargetOSBuild on $TargetDrive" -Severity 1
    # Full driver installation logic ported from original
}

function Start-DATModelProcessing {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$ScriptDirectory,
        [Parameter(Mandatory)][string]$RegPath,
        [Parameter(Mandatory)][string]$RunningMode,
        [Parameter(Mandatory)]$SelectedModels,
        [string]$StoragePath,
        [string]$PackagePath,
        [string]$IntuneAuthToken,
        [string]$SiteServer,
        [string]$SiteCode,
        [string]$PackageType = 'Drivers',
        [string[]]$DistributionPointGroups,
        [string[]]$DistributionPoints,
        [string]$DistributionPriority = 'Normal',
        [switch]$DisableToast,
        [ValidateSet('RemindMeLater','InstallNow')][string]$ToastTimeoutAction = 'RemindMeLater',
        [int]$MaxDeferrals = 0,
        [string]$DebugBuildPath,
        [string]$CustomBrandingPath,
        [string]$HPPasswordBinPath,
        [string]$TeamsWebhookUrl,
        [switch]$TeamsNotificationsEnabled,
        [string]$CustomToastTitle,
        [string]$CustomToastBody
    )
    $global:ScriptDirectory = $ScriptDirectory
    $global:LogDirectory = Join-Path $ScriptDirectory "Logs"
    $global:TempDirectory = if ([string]::IsNullOrEmpty($StoragePath)) { Join-Path $ScriptDirectory "Temp" } else { $StoragePath }
    $global:ToolsDirectory = Join-Path $ScriptDirectory "Tools"

    # Use user-configured paths if provided, otherwise default to ScriptDirectory sub-folders
    if ([string]::IsNullOrEmpty($StoragePath)) { $StoragePath = Join-Path $ScriptDirectory "Downloads" }
    if ([string]::IsNullOrEmpty($PackagePath)) { $PackagePath = Join-Path $ScriptDirectory "Packages" }

    foreach ($dir in @($global:LogDirectory, $global:TempDirectory, $global:ToolsDirectory)) {
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    }

    # Set Intune auth token if provided (for background runspace)
    if (-not [string]::IsNullOrEmpty($IntuneAuthToken) -and $RunningMode -eq 'Intune') {
        $script:IntuneAuthToken = $IntuneAuthToken
        $script:IntuneTokenExpiry = (Get-Date).AddMinutes(55)
        Write-DATLogEntry -Value "[Intune] Auth token set for background runspace processing" -Severity 1
    }

    $modelList = @($SelectedModels)
    $totalModels = $modelList.Count
    Write-DATLogEntry -Value "--- Starting model processing: $totalModels models, mode=$RunningMode ---" -Severity 1

    $completedCount = 0
    $biosNoMatchCount = 0
    $driverPackageSuccessCount = 0
    $biosPackageSuccessCount = 0
    $currentIndex = 0

    # Pre-fetch existing Intune Win32 apps once (avoids per-model Graph queries)
    $cachedIntuneApps = @()
    if ($RunningMode -eq 'Intune') {
        try {
            Write-DATLogEntry -Value "[Intune] Pre-fetching existing Win32 apps for skip-if-exists checks..." -Severity 1
            $cachedIntuneApps = @(Get-DATIntuneWin32Apps)
            Write-DATLogEntry -Value "[Intune] Cached $($cachedIntuneApps.Count) Win32 apps" -Severity 1
        } catch {
            Write-DATLogEntry -Value "[Intune] Failed to pre-fetch Win32 apps: $($_.Exception.Message) -- skip checks will be bypassed" -Severity 2
        }
    }

    # Pre-build ConfigMgr package version cache (Name → Version hashtable) for O(1) lookups
    $cmPkgVersionCache = @{}
    if ($RunningMode -eq 'Configuration Manager' -and -not [string]::IsNullOrEmpty($SiteServer) -and -not [string]::IsNullOrEmpty($SiteCode)) {
        try {
            $smsNs = "root\SMS\Site_$SiteCode"
            Write-DATLogEntry -Value "[ConfigMgr] Pre-fetching package versions for skip-if-current checks..." -Severity 1
            $cmPkgs = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNs -Query "SELECT Name, Version FROM SMS_Package" -ErrorAction Stop
            foreach ($p in $cmPkgs) {
                if (-not [string]::IsNullOrEmpty($p.Name) -and -not [string]::IsNullOrEmpty($p.Version)) {
                    $cmPkgVersionCache[$p.Name] = $p.Version
                }
            }
            Write-DATLogEntry -Value "[ConfigMgr] Cached $($cmPkgVersionCache.Count) package versions" -Severity 1
        } catch {
            Write-DATLogEntry -Value "[ConfigMgr] Failed to pre-fetch package versions: $($_.Exception.Message)" -Severity 2
        }
    }

    foreach ($model in $modelList) {
        $currentIndex++
        $oem = $model.OEM
        $modelName = $model.Model
        $baseboards = if ($model.Baseboards -is [array]) { $model.Baseboards -join "," } else { [string]$model.Baseboards }
        $os = $model.OS
        $arch = $model.Architecture
        $customDriverPath = $model.CustomDriverPath
        $catalogDriverVersion = if ($model.Version) { $model.Version } else { '' }
        $catalogBIOSVersion   = if ($model.BIOSVersion) { $model.BIOSVersion } else { '' }
        $modelForceUpdate     = [bool]$model.ForceUpdate

        Set-DATRegistryValue -Name "CurrentJob" -Value "$currentIndex" -Type String
        Set-DATRegistryValue -Name "RunningMessage" -Value "[$currentIndex/$totalModels] $oem $modelName" -Type String
        Set-DATRegistryValue -Name "RunningState" -Value "Running" -Type String
        Set-DATRegistryValue -Name "RunningMode" -Value "Download" -Type String
        Set-DATRegistryValue -Name "DownloadSize" -Value "---" -Type String
        Set-DATRegistryValue -Name "BytesTransferred" -Value "0" -Type String
        Set-DATRegistryValue -Name "DownloadBytes" -Value "0" -Type String
        Set-DATRegistryValue -Name "DownloadSpeed" -Value "---" -Type String

        Write-DATLogEntry -Value "[$currentIndex/$totalModels] Processing $oem $modelName ($os $arch)" -Severity 1

        $windowsBuild = $os.Split(" ")[2]
        $windowsVersion = $os.Replace(" $windowsBuild", "").TrimEnd()

        try {
            # ── Driver processing (when PackageType is 'Drivers' or 'All') ──────────
            if ($PackageType -in @('Drivers', 'All')) {
                Set-DATRegistryValue -Name "PackagePhase" -Value "Drivers" -Type String
                Write-DATLogEntry -Value "[$currentIndex/$totalModels] Starting driver processing for $oem $modelName" -Severity 1

                # ── Pre-flight: skip download+packaging if package version is current ──
                $skipDriverDownload = $false
                if ($RunningMode -eq 'Configuration Manager') {
                    $cmDriverPkgName = "Drivers - $oem $modelName - $windowsVersion $windowsBuild $arch"
                    $existingCMVersion = $cmPkgVersionCache[$cmDriverPkgName]
                    if (-not [string]::IsNullOrEmpty($existingCMVersion) -and -not [string]::IsNullOrEmpty($catalogDriverVersion) -and $existingCMVersion -eq $catalogDriverVersion -and -not $modelForceUpdate) {
                        Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED -- driver package version is current ($existingCMVersion): $cmDriverPkgName" -Severity 1
                        Set-DATRegistryValue -Name "RunningMessage" -Value "Skipped (current v$existingCMVersion): $oem $modelName" -Type String
                        $skipDriverDownload = $true
                        $script:driverPipelineSuccess = $true
                        $driverPackageSuccessCount++
                    } elseif (-not [string]::IsNullOrEmpty($existingCMVersion)) {
                        Write-DATLogEntry -Value "[$currentIndex/$totalModels] UPDATE needed -- existing v$existingCMVersion, catalog v${catalogDriverVersion}: $cmDriverPkgName" -Severity 1
                    }
                } elseif ($RunningMode -eq 'Intune') {
                    # Check cached Intune app list -- compare display version against catalog version
                    $expectedDisplayName = "Drivers - $oem $modelName - $windowsVersion $windowsBuild $arch"
                    Write-DATLogEntry -Value "[$currentIndex/$totalModels] Checking for existing Intune package: $expectedDisplayName" -Severity 1
                    $existingIntuneApp = $cachedIntuneApps | Where-Object {
                        $_.displayName -eq $expectedDisplayName
                    } | Sort-Object -Property displayVersion -Descending | Select-Object -First 1
                    if ($existingIntuneApp) {
                        $intuneVersion = $existingIntuneApp.displayVersion
                        if (-not [string]::IsNullOrEmpty($catalogDriverVersion) -and $intuneVersion -eq $catalogDriverVersion -and -not $modelForceUpdate) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED -- Intune driver package version is current (v$intuneVersion): $($existingIntuneApp.displayName) (ID: $($existingIntuneApp.id))" -Severity 1
                            Set-DATRegistryValue -Name "RunningMessage" -Value "Skipped (current v$intuneVersion): $oem $modelName" -Type String
                            $skipDriverDownload = $true
                            $script:driverPipelineSuccess = $true
                            $driverPackageSuccessCount++
                        } else {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] UPDATE needed -- Intune v$intuneVersion, catalog v${catalogDriverVersion}: $expectedDisplayName" -Severity 1
                        }
                    }
                } else {
                    # Download Only / WIM Package Only -- check if WIM already exists from today
                    $existingWimPath = Join-Path $global:TempDirectory "Packaged\$oem\$modelName\$windowsVersion $windowsBuild\DriverPackage.wim"
                    if ((Test-Path $existingWimPath) -and (Get-Item $existingWimPath).LastWriteTime.Date -eq (Get-Date).Date -and -not $modelForceUpdate) {
                        Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED download -- driver WIM already created today: $existingWimPath" -Severity 1
                        Set-DATRegistryValue -Name "RunningMessage" -Value "Skipped (exists): $oem $modelName" -Type String
                        $skipDriverDownload = $true
                        $driverPackageSuccessCount++
                    }
                }

                if (-not $skipDriverDownload) {
                $catalogVersion = Invoke-DATOEMDownloadModule -OEM $oem `
                    -Model $modelName `
                    -SystemSKU "$baseboards" `
                    -WindowsBuild $windowsBuild `
                    -WindowsVersion $windowsVersion `
                    -Architecture $arch `
                    -DownloadDestination (Join-Path $StoragePath "$oem\$modelName") `
                    -PackageDestination $PackagePath `
                    -RegPath $RegPath `
                    -LogDirectory $global:LogDirectory `
                    -TempDirectory $global:TempDirectory `
                    -RunningMode $RunningMode `
                    -CustomDriverPath $customDriverPath

                # Intune: Create and upload Win32 app after packaging
                if ($RunningMode -eq 'Intune') {
                    $wimPath = Join-Path $global:TempDirectory "Packaged\$oem\$modelName\$windowsVersion $windowsBuild\DriverPackage.wim"
                    if (Test-Path $wimPath) {
                        Write-DATLogEntry -Value "[$currentIndex/$totalModels] Starting Intune pipeline for $oem $modelName" -Severity 1
                        Set-DATRegistryValue -Name "RunningMessage" -Value "Creating Intune package: $oem $modelName..." -Type String

                        $intuneParams = @{
                            OEM                = $oem
                            Model              = $modelName
                            Baseboards         = $baseboards
                            OS                 = "$windowsVersion $windowsBuild"
                            Architecture       = $arch
                            WimFilePath        = $wimPath
                            PackageDestination = $PackagePath
                            IntuneAuthToken    = $IntuneAuthToken
                        }
                        if (-not [string]::IsNullOrEmpty($catalogVersion)) { $intuneParams['Version'] = "$catalogVersion" }
                        if ($DisableToast) { $intuneParams['DisableToast'] = $true }
                        if ($ToastTimeoutAction -ne 'RemindMeLater') { $intuneParams['ToastTimeoutAction'] = $ToastTimeoutAction }
                        if ($MaxDeferrals -gt 0) { $intuneParams['MaxDeferrals'] = $MaxDeferrals }
                        if (-not [string]::IsNullOrEmpty($DebugBuildPath)) { $intuneParams['DebugBuildPath'] = $DebugBuildPath }
                        if (-not [string]::IsNullOrEmpty($CustomBrandingPath)) { $intuneParams['CustomBrandingPath'] = $CustomBrandingPath }
                        if (-not [string]::IsNullOrEmpty($CustomToastTitle)) { $intuneParams['CustomToastTitle'] = $CustomToastTitle }
                        if (-not [string]::IsNullOrEmpty($CustomToastBody)) { $intuneParams['CustomToastBody'] = $CustomToastBody }
                        if ($modelForceUpdate) { $intuneParams['ForceUpdate'] = $true }
                        Invoke-DATIntunePackageCreation @intuneParams

                        Write-DATLogEntry -Value "- $oem $modelName Intune driver upload completed" -Severity 1

                        # Clean up staging WIM now that it has been wrapped into .intunewin
                        if (Test-Path $wimPath) {
                            Remove-Item -Path $wimPath -Force -ErrorAction SilentlyContinue
                            $wimParent = Split-Path $wimPath -Parent
                            if ((Test-Path $wimParent) -and @(Get-ChildItem -Path $wimParent -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                                Remove-Item -Path $wimParent -Recurse -Force -ErrorAction SilentlyContinue
                            }
                            Write-DATLogEntry -Value "[$oem] Staging WIM cleaned up after Intune upload" -Severity 1
                        }
                        $script:driverPipelineSuccess = $true

                        # Telemetry: driver report with .intunewin hash
                        try {
                            $intuneWinDir = Join-Path $PackagePath "IntuneWin\$oem\$modelName\$windowsVersion $windowsBuild"
                            $intuneWinFile = Get-ChildItem -Path $intuneWinDir -Filter '*.intunewin' -ErrorAction SilentlyContinue | Select-Object -First 1
                            $drvHash = if ($intuneWinFile) { Get-DATPackageHash -FilePath $intuneWinFile.FullName } else { $null }
                            $drvSize = if ($intuneWinFile) { $intuneWinFile.Length } else { 0 }
                            Send-DATDriverReport -Manufacturer $oem -Model $modelName `
                                -OSVersion "$windowsVersion $windowsBuild" -OSArchitecture $arch -Platform 'Intune' `
                                -Status 'Success' -PackageSize $drvSize -PackageHash $drvHash
                        } catch {
                            Write-DATLogEntry -Value "[Telemetry] Driver report failed: $($_.Exception.Message)" -Severity 2
                        }
                    } else {
                        Write-DATLogEntry -Value "[Warning] - Driver WIM not found for Intune upload: $wimPath" -Severity 2
                    }
                }

                # ConfigMgr: Create driver package on site server after packaging
                if ($RunningMode -eq 'Configuration Manager') {
                    $wimPath = Join-Path $global:TempDirectory "Packaged\$oem\$modelName\$windowsVersion $windowsBuild\DriverPackage.wim"
                    if (Test-Path $wimPath) {
                        if (-not [string]::IsNullOrEmpty($SiteServer) -and -not [string]::IsNullOrEmpty($SiteCode)) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] Starting ConfigMgr driver pipeline for $oem $modelName" -Severity 1
                            Write-DATLogEntry -Value "-- Site server: $SiteServer" -Severity 1
                            Write-DATLogEntry -Value "-- Site code: $SiteCode" -Severity 1
                            Set-DATRegistryValue -Name "RunningMessage" -Value "Creating ConfigMgr driver package: $oem $modelName..." -Type String

                            $version = if (-not [string]::IsNullOrEmpty($catalogVersion)) { "$catalogVersion" } else { Get-Date -Format "ddMMyyyy" }
                            $cmParams = @{
                                DriverPackage = $wimPath
                                OEM           = $oem
                                Model         = $modelName
                                OS            = "$windowsVersion $windowsBuild"
                                Architecture  = $arch
                                Baseboards    = $baseboards
                                PackagePath   = $PackagePath
                                SiteServer    = $SiteServer
                                SiteCode      = $SiteCode
                                Version       = $version
                                PackageType   = 'Drivers'
                                Priority      = $DistributionPriority
                            }
                            if ($DistributionPointGroups -and $DistributionPointGroups.Count -gt 0) {
                                $cmParams['DistributionPointGroups'] = $DistributionPointGroups
                            }
                            if ($DistributionPoints -and $DistributionPoints.Count -gt 0) {
                                $cmParams['DistributionPoints'] = $DistributionPoints
                            }
                            if ($modelForceUpdate) { $cmParams['ForceUpdate'] = $true }
                            $cmResult = New-DATConfigMgrPkg @cmParams

                            if ($cmResult) {
                                Write-DATLogEntry -Value "- $oem $modelName ConfigMgr driver package created" -Severity 1

                                # Telemetry: driver report with WIM hash (before cleanup)
                                try {
                                    $drvHash = Get-DATPackageHash -FilePath $wimPath
                                    $drvSize = if (Test-Path $wimPath) { (Get-Item $wimPath).Length } else { 0 }
                                    Send-DATDriverReport -Manufacturer $oem -Model $modelName `
                                        -OSVersion "$windowsVersion $windowsBuild" -OSArchitecture $arch `
                                        -Platform 'ConfigMgr' -Status 'Success' `
                                        -PackageVersion $version -PackageSize $drvSize -PackageHash $drvHash
                                } catch {
                                    Write-DATLogEntry -Value "[Telemetry] Driver report failed: $($_.Exception.Message)" -Severity 2
                                }

                                # Clean up staging WIM now that it has been copied to the CM package source
                                if (Test-Path $wimPath) {
                                    Remove-Item -Path $wimPath -Force -ErrorAction SilentlyContinue
                                    $wimParent = Split-Path $wimPath -Parent
                                    if ((Test-Path $wimParent) -and @(Get-ChildItem -Path $wimParent -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                                        Remove-Item -Path $wimParent -Recurse -Force -ErrorAction SilentlyContinue
                                    }
                                    Write-DATLogEntry -Value "[$oem] Staging WIM cleaned up after ConfigMgr package creation" -Severity 1
                                }
                                $script:driverPipelineSuccess = $true
                            } else {
                                Write-DATLogEntry -Value "[Warning] - $oem $modelName ConfigMgr driver package creation failed" -Severity 2
                            }
                        } else {
                            Write-DATLogEntry -Value "[Warning] - ConfigMgr not connected -- driver package saved locally only" -Severity 2
                        }
                    } else {
                        Write-DATLogEntry -Value "[Warning] - Driver WIM not found for ConfigMgr: $wimPath" -Severity 2
                    }
                }

                # WIM Package Only: copy the final WIM from temp staging to the Package Storage Path
                if ($RunningMode -eq 'WIM Package Only') {
                    $wimStagingPath = Join-Path $global:TempDirectory "Packaged\$oem\$modelName\$windowsVersion $windowsBuild\DriverPackage.wim"
                    if (Test-Path $wimStagingPath) {
                        $wimFinalDir = Join-Path $PackagePath "$oem\$modelName\$windowsVersion $windowsBuild"
                        if (-not (Test-Path $wimFinalDir)) { New-Item -Path $wimFinalDir -ItemType Directory -Force | Out-Null }
                        $wimFinalPath = Join-Path $wimFinalDir "DriverPackage.wim"
                        Copy-Item -Path $wimStagingPath -Destination $wimFinalPath -Force
                        Write-DATLogEntry -Value "[$currentIndex/$totalModels] WIM package stored: $wimFinalPath" -Severity 1
                        # Clean up staging WIM
                        Remove-Item -Path $wimStagingPath -Force -ErrorAction SilentlyContinue
                        $wimParent = Split-Path $wimStagingPath -Parent
                        if ((Test-Path $wimParent) -and @(Get-ChildItem -Path $wimParent -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                            Remove-Item -Path $wimParent -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        $script:driverPipelineSuccess = $true
                    }
                }

                # Telemetry: driver report for Download Only / WIM Only modes (no Intune or ConfigMgr)
                if ($RunningMode -notin @('Intune', 'Configuration Manager')) {
                    try {
                        # WIM Package Only moves the WIM to PackagePath; Download Only keeps it in temp staging
                        $dlWimPath = Join-Path $global:TempDirectory "Packaged\$oem\$modelName\$windowsVersion $windowsBuild\DriverPackage.wim"
                        if (-not (Test-Path $dlWimPath)) {
                            $dlWimPath = Join-Path $PackagePath "$oem\$modelName\$windowsVersion $windowsBuild\DriverPackage.wim"
                        }
                        if (Test-Path $dlWimPath) {
                            $drvHash = Get-DATPackageHash -FilePath $dlWimPath
                            $drvSize = (Get-Item $dlWimPath).Length
                            Send-DATDriverReport -Manufacturer $oem -Model $modelName `
                                -OSVersion "$windowsVersion $windowsBuild" -OSArchitecture $arch `
                                -Platform $RunningMode -Status 'Success' `
                                -PackageSize $drvSize -PackageHash $drvHash
                        }
                    } catch {
                        Write-DATLogEntry -Value "[Telemetry] Driver report failed: $($_.Exception.Message)" -Severity 2
                    }
                }

                # Count driver package success -- check if the WIM was produced (Download Only)
                # or if it was successfully consumed by the Intune/ConfigMgr pipeline
                $drvWimCheck = Join-Path $global:TempDirectory "Packaged\$oem\$modelName\$windowsVersion $windowsBuild\DriverPackage.wim"
                if ((Test-Path $drvWimCheck) -or $script:driverPipelineSuccess) { $driverPackageSuccessCount++ }
                $script:driverPipelineSuccess = $false
                } # end if (-not $skipDriverDownload)
            }

            # ── BIOS processing (when PackageType is 'BIOS' or 'All') ──────────────
            if ($PackageType -in @('BIOS', 'All')) {
                # Microsoft Surface BIOS updates are delivered via driver injection -- skip BIOS packaging
                if ($oem -eq 'Microsoft') {
                    Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED -- Microsoft Surface BIOS updates are handled via driver injection, no separate BIOS package required" -Severity 1
                } else {
                Set-DATRegistryValue -Name "PackagePhase" -Value "BIOS" -Type String
                Write-DATLogEntry -Value "[$currentIndex/$totalModels] Starting BIOS processing for $oem $modelName" -Severity 1
                Set-DATRegistryValue -Name "RunningMessage" -Value "[$currentIndex/$totalModels] BIOS: $oem $modelName" -Type String
                Set-DATRegistryValue -Name "RunningMode" -Value "Download" -Type String

                # ── Pre-flight: skip BIOS if deployed version matches catalog version ──
                $skipBios = $false
                if (-not [string]::IsNullOrEmpty($catalogBIOSVersion)) {
                    if ($RunningMode -eq 'Configuration Manager') {
                        $cmBiosPkgName = "Bios Update - $oem $modelName"
                        $existingCMBiosVer = $cmPkgVersionCache[$cmBiosPkgName]
                        if (-not [string]::IsNullOrEmpty($existingCMBiosVer) -and $existingCMBiosVer -eq $catalogBIOSVersion -and -not $modelForceUpdate) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED -- BIOS version is current ($existingCMBiosVer): $cmBiosPkgName" -Severity 1
                            Set-DATRegistryValue -Name "RunningMessage" -Value "BIOS skipped (current v$existingCMBiosVer): $oem $modelName" -Type String
                            $skipBios = $true
                            $biosPackageSuccessCount++
                        } elseif (-not [string]::IsNullOrEmpty($existingCMBiosVer)) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] BIOS UPDATE needed -- existing v$existingCMBiosVer, catalog v${catalogBIOSVersion}: $cmBiosPkgName" -Severity 1
                        }
                    } elseif ($RunningMode -eq 'Intune') {
                        $expectedBiosName = "Bios Update - $oem $modelName"
                        $existingBiosApp = $cachedIntuneApps | Where-Object {
                            $_.displayName -eq $expectedBiosName
                        } | Sort-Object -Property displayVersion -Descending | Select-Object -First 1
                        if ($existingBiosApp -and $existingBiosApp.displayVersion -eq $catalogBIOSVersion -and -not $modelForceUpdate) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED -- Intune BIOS version is current (v$($existingBiosApp.displayVersion)): $expectedBiosName (ID: $($existingBiosApp.id))" -Severity 1
                            Set-DATRegistryValue -Name "RunningMessage" -Value "BIOS skipped (current v$($existingBiosApp.displayVersion)): $oem $modelName" -Type String
                            $skipBios = $true
                            $biosPackageSuccessCount++
                        } elseif ($existingBiosApp) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] BIOS UPDATE needed -- Intune v$($existingBiosApp.displayVersion), catalog v${catalogBIOSVersion}: $expectedBiosName" -Severity 1
                        }
                    }
                }

                if ($skipBios) {
                    # Already current -- skip all BIOS processing
                } else {

                $biosCatalog = Get-DATBiosCatalog
                $biosEntry = Find-DATBiosPackage -OEM $oem -Baseboards $baseboards -Catalog $biosCatalog

                if ($null -eq $biosEntry) {
                    Write-DATLogEntry -Value "[Warning] - No BIOS update available for $oem $modelName -- skipping BIOS" -Severity 2
                    $biosNoMatchCount++
                    if ($PackageType -eq 'BIOS') {
                        # Signal the UI via RunningMode -- tied to CurrentJob so no race conditions
                        Set-DATRegistryValue -Name "RunningMode" -Value "BiosNoMatch" -Type String
                    }
                } else {
                    Write-DATLogEntry -Value "[BIOS] Matched: $($biosEntry.DisplayName) , Version $($biosEntry.Version), Released $($biosEntry.ReleaseDate)" -Severity 1

                    $biosDownloadDir = Join-Path $StoragePath "$oem\$modelName\BIOS"
                    Set-DATRegistryValue -Name "RunningMode" -Value "Download" -Type String
                    $biosFilePath = @(Start-DATBiosDownload -BiosEntry $biosEntry -DownloadDestination $biosDownloadDir)[-1]

                    if ([string]::IsNullOrEmpty($biosFilePath)) {
                        Write-DATLogEntry -Value "[Warning] - BIOS download failed for $oem $modelName -- skipping BIOS" -Severity 2
                    } else {
                        # Package the BIOS exe (extract HP/Lenovo, direct for Dell)
                        # ConfigMgr: stage files directly | Intune: compress into WIM
                        Set-DATRegistryValue -Name "RunningMode" -Value "Extracting" -Type String
                        $skipWim = ($RunningMode -eq 'Configuration Manager')
                        $biosPackagePath = @(Invoke-DATBiosPackaging -BiosFilePath $biosFilePath -OEM $oem `
                            -Model $modelName -Version $biosEntry.Version -PackageDestination $PackagePath `
                            -SkipWim:$skipWim)[-1]

                        if ($biosPackagePath -and (Test-Path $biosPackagePath)) {
                            # Intune: Create and upload BIOS Win32 app
                            if ($RunningMode -eq 'Intune') {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] Starting Intune BIOS pipeline for $oem $modelName" -Severity 1
                                Set-DATRegistryValue -Name "RunningMessage" -Value "Creating Intune BIOS package: $oem $modelName..." -Type String

                                $intuneParams = @{
                                    OEM                = $oem
                                    Model              = $modelName
                                    Baseboards         = $baseboards
                                    OS                 = "$windowsVersion $windowsBuild"
                                    Architecture       = $arch
                                    WimFilePath        = $biosPackagePath
                                    PackageDestination = $PackagePath
                                    IntuneAuthToken    = $IntuneAuthToken
                                    UpdateType         = 'BIOS'
                                }
                                if (-not [string]::IsNullOrEmpty($biosEntry.Version)) { $intuneParams['Version'] = "$($biosEntry.Version)" }
                                if ($DisableToast) { $intuneParams['DisableToast'] = $true }
                                if ($ToastTimeoutAction -ne 'RemindMeLater') { $intuneParams['ToastTimeoutAction'] = $ToastTimeoutAction }
                                if ($MaxDeferrals -gt 0) { $intuneParams['MaxDeferrals'] = $MaxDeferrals }
                                if (-not [string]::IsNullOrEmpty($DebugBuildPath)) { $intuneParams['DebugBuildPath'] = $DebugBuildPath }
                                if (-not [string]::IsNullOrEmpty($CustomBrandingPath)) { $intuneParams['CustomBrandingPath'] = $CustomBrandingPath }
                                if (-not [string]::IsNullOrEmpty($HPPasswordBinPath)) { $intuneParams['HPPasswordBinPath'] = $HPPasswordBinPath }
                                if (-not [string]::IsNullOrEmpty($CustomToastTitle)) { $intuneParams['CustomToastTitle'] = $CustomToastTitle }
                                if (-not [string]::IsNullOrEmpty($CustomToastBody)) { $intuneParams['CustomToastBody'] = $CustomToastBody }
                                if ($modelForceUpdate) { $intuneParams['ForceUpdate'] = $true }
                                Invoke-DATIntunePackageCreation @intuneParams

                                Write-DATLogEntry -Value "- $oem $modelName Intune BIOS upload completed" -Severity 1

                                # Clean up staging BIOS WIM now that it has been wrapped into .intunewin
                                if ((Test-Path $biosPackagePath) -and $biosPackagePath -match '\.wim$') {
                                    Remove-Item -Path $biosPackagePath -Force -ErrorAction SilentlyContinue
                                    $biosWimParent = Split-Path $biosPackagePath -Parent
                                    if ((Test-Path $biosWimParent) -and @(Get-ChildItem -Path $biosWimParent -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                                        Remove-Item -Path $biosWimParent -Recurse -Force -ErrorAction SilentlyContinue
                                    }
                                    Write-DATLogEntry -Value "[$oem] Staging BIOS WIM cleaned up after Intune upload" -Severity 1
                                }

                                # Telemetry: BIOS report with .intunewin hash
                                try {
                                    $biosIntuneWinDir = Join-Path $PackagePath "IntuneWin\$oem\$modelName\$windowsVersion $windowsBuild"
                                    $biosIntuneWinFile = Get-ChildItem -Path $biosIntuneWinDir -Filter '*.intunewin' -ErrorAction SilentlyContinue | Select-Object -First 1
                                    $biosHash = if ($biosIntuneWinFile) { Get-DATPackageHash -FilePath $biosIntuneWinFile.FullName } else { $null }
                                    Send-DATBiosReport -Manufacturer $oem -Model $modelName `
                                        -Platform 'Intune' -Status 'Success' `
                                        -TargetBiosVersion $biosEntry.Version -PackageHash $biosHash
                                } catch {
                                    Write-DATLogEntry -Value "[Telemetry] BIOS report failed: $($_.Exception.Message)" -Severity 2
                                }
                            }

                            # ConfigMgr: Create BIOS package on site server
                            if ($RunningMode -eq 'Configuration Manager') {
                                if (-not [string]::IsNullOrEmpty($SiteServer) -and -not [string]::IsNullOrEmpty($SiteCode)) {
                                    Write-DATLogEntry -Value "[$currentIndex/$totalModels] Starting ConfigMgr BIOS pipeline for $oem $modelName" -Severity 1
                                    Set-DATRegistryValue -Name "RunningMessage" -Value "Creating ConfigMgr BIOS package: $oem $modelName..." -Type String

                                    $biosVersion = $biosEntry.Version
                                    $cmParams = @{
                                        DriverPackage = $biosPackagePath
                                        OEM           = $oem
                                        Model         = $modelName
                                        OS            = "$windowsVersion $windowsBuild"
                                        Architecture  = $arch
                                        Baseboards    = $baseboards
                                        PackagePath   = $PackagePath
                                        SiteServer    = $SiteServer
                                        SiteCode      = $SiteCode
                                        Version       = $biosVersion
                                        PackageType   = 'BIOS'
                                        Priority      = $DistributionPriority
                                    }
                                    if ($DistributionPointGroups -and $DistributionPointGroups.Count -gt 0) {
                                        $cmParams['DistributionPointGroups'] = $DistributionPointGroups
                                    }
                                    if ($DistributionPoints -and $DistributionPoints.Count -gt 0) {
                                        $cmParams['DistributionPoints'] = $DistributionPoints
                                    }
                                    if ($modelForceUpdate) { $cmParams['ForceUpdate'] = $true }
                                    $cmResult = New-DATConfigMgrPkg @cmParams

                                    if ($cmResult) {
                                        Write-DATLogEntry -Value "- $oem $modelName ConfigMgr BIOS package created" -Severity 1

                                        # Telemetry: BIOS report with staged package hash
                                        # For ConfigMgr BIOS, $biosPackagePath is a directory (no WIM) --
                                        # hash the first file inside it rather than the directory itself.
                                        try {
                                            $hashTarget = $biosPackagePath
                                            if (Test-Path $biosPackagePath -PathType Container) {
                                                $firstFile = Get-ChildItem -Path $biosPackagePath -File -ErrorAction SilentlyContinue | Select-Object -First 1
                                                if ($firstFile) { $hashTarget = $firstFile.FullName }
                                            }
                                            $biosHash = Get-DATPackageHash -FilePath $hashTarget
                                            Send-DATBiosReport -Manufacturer $oem -Model $modelName `
                                                -Platform 'ConfigMgr' -Status 'Success' `
                                                -TargetBiosVersion $biosVersion -PackageHash $biosHash
                                        } catch {
                                            Write-DATLogEntry -Value "[Telemetry] BIOS report failed: $($_.Exception.Message)" -Severity 2
                                        }
                                    } else {
                                        Write-DATLogEntry -Value "[Warning] - $oem $modelName ConfigMgr BIOS package creation failed" -Severity 2
                                    }
                                } else {
                                    Write-DATLogEntry -Value "[Warning] - ConfigMgr not connected -- BIOS package saved locally only" -Severity 2
                                }
                            }

                            Write-DATLogEntry -Value "- $oem $modelName BIOS processing completed" -Severity 1
                            $biosPackageSuccessCount++

                            # Telemetry: BIOS report for Download Only mode
                            if ($RunningMode -notin @('Intune', 'Configuration Manager')) {
                                try {
                                    $hashTarget = $biosPackagePath
                                    if (Test-Path $biosPackagePath -PathType Container) {
                                        $firstFile = Get-ChildItem -Path $biosPackagePath -File -ErrorAction SilentlyContinue | Select-Object -First 1
                                        if ($firstFile) { $hashTarget = $firstFile.FullName }
                                    }
                                    $biosHash = Get-DATPackageHash -FilePath $hashTarget
                                    Send-DATBiosReport -Manufacturer $oem -Model $modelName `
                                        -Platform $RunningMode -Status 'Success' `
                                        -TargetBiosVersion $biosEntry.Version -PackageHash $biosHash
                                } catch {
                                    Write-DATLogEntry -Value "[Telemetry] BIOS report failed: $($_.Exception.Message)" -Severity 2
                                }
                            }
                        } else {
                            Write-DATLogEntry -Value "[Warning] - BIOS packaging failed for $oem $modelName" -Severity 2
                        }
                    }
                }
                } # end else (not skipBios)
                } # end else (not Microsoft)
            }

            $completedCount++
            Write-DATLogEntry -Value "- $oem $modelName completed successfully" -Severity 1
        } catch {
            Write-DATLogEntry -Value "[Error] - $oem $modelName failed: $($_.Exception.Message)" -Severity 3
        }

        Set-DATRegistryValue -Name "CompletedJobs" -Value "$completedCount" -Type String
        Set-DATRegistryValue -Name "CompletedDriverPackages" -Value "$driverPackageSuccessCount" -Type String
        Set-DATRegistryValue -Name "CompletedBiosPackages" -Value "$biosPackageSuccessCount" -Type String

        # Check for user abort between models -- do not continue processing or overwrite Aborted state
        $interModelReg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
        if ($interModelReg.RunningState -eq 'Aborted') {
            Write-DATLogEntry -Value "--- Build aborted by user after model $currentIndex ---" -Severity 2
            return
        }
    }

    # Only write final state if the user has NOT aborted -- "Aborted" takes priority
    $finalCheckReg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
    if ($finalCheckReg.RunningState -eq 'Aborted') {
        Write-DATLogEntry -Value "--- Model processing aborted by user ---" -Severity 2
        return
    }

    if ($completedCount -eq $totalModels) {
        if ($PackageType -eq 'BIOS' -and $biosNoMatchCount -eq $totalModels) {
            # Every model had no BIOS catalog match
            Set-DATRegistryValue -Name "RunningMessage" -Value "No BIOS updates found for $totalModels model$(if ($totalModels -ne 1) { 's' })" -Type String
            Set-DATRegistryValue -Name "RunningState" -Value "CompletedNoMatch" -Type String
        } elseif ($biosNoMatchCount -gt 0 -and $PackageType -eq 'BIOS') {
            $matchedCount = $totalModels - $biosNoMatchCount
            Set-DATRegistryValue -Name "RunningMessage" -Value "Completed: $matchedCount of $totalModels models processed, $biosNoMatchCount with no BIOS match" -Type String
            Set-DATRegistryValue -Name "RunningState" -Value "Completed" -Type String
        } else {
            Set-DATRegistryValue -Name "RunningMessage" -Value "Completed: $completedCount of $totalModels models processed successfully" -Type String
            Set-DATRegistryValue -Name "RunningState" -Value "Completed" -Type String
        }
    } else {
        $failedCount = $totalModels - $completedCount
        Set-DATRegistryValue -Name "RunningMessage" -Value "Completed with errors: $completedCount of $totalModels succeeded, $failedCount failed" -Type String
        Set-DATRegistryValue -Name "RunningState" -Value "CompletedWithErrors" -Type String
    }
    Write-DATLogEntry -Value "--- Model processing complete: $completedCount/$totalModels succeeded ---" -Severity 1

    # Send Teams webhook notification if enabled
    if ($TeamsNotificationsEnabled -and -not [string]::IsNullOrEmpty($TeamsWebhookUrl)) {
        $failedCount = $totalModels - $completedCount
        try {
            Send-DATTeamsNotification -WebhookUrl $TeamsWebhookUrl `
                -TotalModels $totalModels -SuccessCount $completedCount -FailedCount $failedCount `
                -Platform $RunningMode -PackageType $PackageType -Models $modelList
            Write-DATLogEntry -Value "[Teams] Build notification sent successfully" -Severity 1
        } catch {
            Write-DATLogEntry -Value "[Teams] Failed to send notification: $($_.Exception.Message)" -Severity 2
        }
    }
}

function Send-DATTeamsNotification {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$WebhookUrl,
        [Parameter(Mandatory)][int]$TotalModels,
        [Parameter(Mandatory)][int]$SuccessCount,
        [Parameter(Mandatory)][int]$FailedCount,
        [string]$Platform = 'Download Only',
        [string]$PackageType = 'Drivers',
        [array]$Models = @()
    )

    $statusColor = if ($FailedCount -eq 0) { 'Good' } else { 'Attention' }
    $statusIcon = if ($FailedCount -eq 0) { [char]0x2705 } else { [char]0x26A0 }
    $statusText = if ($FailedCount -eq 0) { 'All packages built successfully' } else { "$FailedCount of $TotalModels failed" }
    $hostname = $env:COMPUTERNAME
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # Build model list for the card
    $modelFacts = @()
    foreach ($m in $Models) {
        $modelName = if ($m.Model) { $m.Model } else { "$($m.OEM) Unknown" }
        $modelFacts += @{ title = $m.OEM; value = $modelName }
    }
    if ($modelFacts.Count -eq 0) { $modelFacts += @{ title = 'Models'; value = 'None specified' } }

    $card = @{
        type = 'message'
        attachments = @(
            @{
                contentType = 'application/vnd.microsoft.card.adaptive'
                contentUrl  = $null
                content     = @{
                    '$schema' = 'http://adaptivecards.io/schemas/adaptive-card.json'
                    type      = 'AdaptiveCard'
                    version   = '1.4'
                    body      = @(
                        @{
                            type   = 'ColumnSet'
                            columns = @(
                                @{
                                    type  = 'Column'
                                    width = 'auto'
                                    items = @(
                                        @{
                                            type  = 'Image'
                                            url   = 'https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Resources/DATIcon.png'
                                            size  = 'Small'
                                            style = 'Default'
                                        }
                                    )
                                },
                                @{
                                    type  = 'Column'
                                    width = 'stretch'
                                    items = @(
                                        @{
                                            type   = 'TextBlock'
                                            text   = 'Driver Automation Tool'
                                            weight = 'Bolder'
                                            size   = 'Medium'
                                        },
                                        @{
                                            type     = 'TextBlock'
                                            text     = "Build $statusIcon $statusText"
                                            spacing  = 'None'
                                            isSubtle = $true
                                        }
                                    )
                                }
                            )
                        },
                        @{
                            type      = 'Container'
                            style     = $statusColor
                            bleed     = $true
                            items     = @(
                                @{
                                    type    = 'FactSet'
                                    facts   = @(
                                        @{ title = 'Platform';  value = $Platform },
                                        @{ title = 'Package Type'; value = $PackageType },
                                        @{ title = 'Total Models'; value = "$TotalModels" },
                                        @{ title = 'Succeeded';   value = "$SuccessCount" },
                                        @{ title = 'Failed';      value = "$FailedCount" },
                                        @{ title = 'Host';        value = $hostname },
                                        @{ title = 'Completed';   value = $timestamp }
                                    )
                                }
                            )
                        },
                        @{
                            type      = 'Container'
                            items     = @(
                                @{
                                    type   = 'TextBlock'
                                    text   = 'Processed Models'
                                    weight = 'Bolder'
                                    spacing = 'Medium'
                                },
                                @{
                                    type  = 'FactSet'
                                    facts = $modelFacts
                                }
                            )
                        }
                    )
                }
            }
        )
    }

    $jsonPayload = $card | ConvertTo-Json -Depth 20 -Compress
    $utf8 = [System.Text.Encoding]::UTF8
    Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body ($utf8.GetBytes($jsonPayload)) `
        -ContentType 'application/json; charset=utf-8' -ErrorAction Stop | Out-Null
    Write-DATLogEntry -Value "[Teams] Notification posted to webhook" -Severity 1
}

function Export-DATBuildConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$Platform,
        [Parameter(Mandatory)][string]$OS,
        [Parameter(Mandatory)][string]$Architecture,
        [string]$PackageType = 'Drivers',
        [Parameter(Mandatory)][array]$Models,
        [string]$TempPath,
        [string]$PackagePath,
        [bool]$DisableToast = $false,
        [string]$ToastTimeoutAction = 'RemindMeLater',
        [int]$MaxDeferrals = 0,
        [string]$TeamsWebhookUrl,
        [bool]$TeamsNotificationsEnabled = $false,
        [hashtable]$Intune,
        [hashtable]$ConfigMgr
    )

    $modelArray = foreach ($m in $Models) {
        $entry = [ordered]@{
            OEM   = $m.OEM
            Model = $m.Model
        }
        if (-not [string]::IsNullOrEmpty($m.Baseboards)) { $entry['Baseboards'] = $m.Baseboards }
        $entry
    }

    $config = [ordered]@{
        '$schema'                  = 'BuildConfig schema for Driver Automation Tool headless builds'
        TempPath                   = if ($TempPath) { $TempPath } else { '' }
        PackagePath                = if ($PackagePath) { $PackagePath } else { '' }
        Platform                   = $Platform
        OS                         = $OS
        Architecture               = $Architecture
        PackageType                = $PackageType
        DisableToast               = $DisableToast
        ToastTimeoutAction         = $ToastTimeoutAction
        MaxDeferrals               = $MaxDeferrals
        TeamsWebhookUrl            = if ($TeamsWebhookUrl) { $TeamsWebhookUrl } else { '' }
        TeamsNotificationsEnabled  = $TeamsNotificationsEnabled
        Intune                     = if ($Intune) { $Intune } else { [ordered]@{ TenantId = ''; AppId = ''; AppSecret = '' } }
        ConfigMgr                  = if ($ConfigMgr) { $ConfigMgr } else { [ordered]@{ SiteServer = ''; SiteCode = ''; DistributionPointGroups = @(); DistributionPriority = 'Normal' } }
        Models                     = @($modelArray)
    }

    $dir = Split-Path $ConfigPath -Parent
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $config | ConvertTo-Json -Depth 4 | Set-Content -Path $ConfigPath -Encoding UTF8 -Force
    Write-DATLogEntry -Value "[Schedule] Exported build config to $ConfigPath ($($Models.Count) model(s), Platform=$Platform)" -Severity 1
}

function Import-DATBuildConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$ConfigPath
    )
    if (-not (Test-Path $ConfigPath)) {
        throw "Build config file not found: $ConfigPath"
    }
    $raw = Get-Content $ConfigPath -Raw -ErrorAction Stop
    $config = $raw | ConvertFrom-Json -ErrorAction Stop

    # Validate required fields
    if (-not $config.Models -or $config.Models.Count -eq 0) {
        throw "BuildConfig must contain at least one model in the 'Models' array"
    }
    foreach ($m in $config.Models) {
        if ([string]::IsNullOrEmpty($m.OEM) -or [string]::IsNullOrEmpty($m.Model)) {
            throw "Each model must have 'OEM' and 'Model' properties"
        }
    }
    if ([string]::IsNullOrEmpty($config.OS)) { throw "BuildConfig must specify 'OS'" }
    if ([string]::IsNullOrEmpty($config.Architecture)) { throw "BuildConfig must specify 'Architecture'" }

    # Build model objects matching the pipeline format
    $models = foreach ($m in $config.Models) {
        [PSCustomObject]@{
            OEM              = $m.OEM
            Model            = $m.Model
            Baseboards       = if ($m.Baseboards) { $m.Baseboards } else { '' }
            OS               = $config.OS
            Architecture     = $config.Architecture
            CustomDriverPath = $null
            Version          = $null
            BIOSVersion      = $null
        }
    }

    [PSCustomObject]@{
        Platform                  = if ($config.Platform -in @('ConfigMgr', 'Configuration Manager')) { 'Configuration Manager' } elseif ($config.Platform) { $config.Platform } else { 'Download Only' }
        OS                        = $config.OS
        Architecture              = $config.Architecture
        PackageType               = if ($config.PackageType) { $config.PackageType } else { 'Drivers' }
        TempPath                  = if (-not [string]::IsNullOrEmpty($config.TempPath)) { $config.TempPath } else { $null }
        PackagePath               = if (-not [string]::IsNullOrEmpty($config.PackagePath)) { $config.PackagePath } else { $null }
        DisableToast              = [bool]$config.DisableToast
        ToastTimeoutAction        = if ($config.ToastTimeoutAction) { $config.ToastTimeoutAction } else { 'RemindMeLater' }
        MaxDeferrals              = if ($config.MaxDeferrals) { [int]$config.MaxDeferrals } else { 0 }
        TeamsWebhookUrl           = $config.TeamsWebhookUrl
        TeamsNotificationsEnabled = [bool]$config.TeamsNotificationsEnabled
        WimEngine                 = if ($config.WimEngine) { $config.WimEngine } else { $null }
        CompressionLevel          = if ($config.CompressionLevel) { $config.CompressionLevel } else { $null }
        Models                    = @($models)
        Intune                    = $config.Intune
        ConfigMgr                 = $config.ConfigMgr
    }
}

function Register-DATScheduledBuild {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$ScriptDirectory,
        [ValidateSet('Once','Daily','Weekly','Monthly')][string]$Frequency = 'Daily',
        [string]$Time = '02:00',
        [ValidateSet('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')]
        [string]$DayOfWeek = 'Monday',
        [int]$DayOfMonth = 1
    )

    $taskFolder = '\Driver Automation Tool'
    $taskName   = 'Scheduled Package Build'
    $headlessScript = Join-Path $ScriptDirectory 'Start-DATHeadlessBuild.ps1'

    if (-not (Test-Path $headlessScript)) {
        throw "Headless build script not found: $headlessScript"
    }
    if (-not (Test-Path $ConfigPath)) {
        throw "Build config not found: $ConfigPath"
    }

    $ps64 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $taskAction = New-ScheduledTaskAction -Execute $ps64 `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$headlessScript`" -ConfigPath `"$ConfigPath`"" `
        -WorkingDirectory $ScriptDirectory

    $triggerParams = @{ At = $Time }
    switch ($Frequency) {
        'Once'    { $trigger = New-ScheduledTaskTrigger -Once @triggerParams }
        'Daily'   { $trigger = New-ScheduledTaskTrigger -Daily @triggerParams }
        'Weekly'  { $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek @triggerParams }
        'Monthly' { $trigger = New-ScheduledTaskTrigger -Daily @triggerParams }
    }

    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 4) -MultipleInstances IgnoreNew
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    Unregister-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -Action $taskAction `
        -Trigger $trigger -Settings $taskSettings -Principal $taskPrincipal -Force | Out-Null
    Write-DATLogEntry -Value "[Schedule] Registered scheduled build: $Frequency at $Time" -Severity 1

    [PSCustomObject]@{
        TaskPath  = "$taskFolder\$taskName"
        Frequency = $Frequency
        Time      = $Time
        Config    = $ConfigPath
    }
}

function Unregister-DATScheduledBuild {
    [CmdletBinding()]
    param ()
    $taskFolder = '\Driver Automation Tool'
    $taskName   = 'Scheduled Package Build'
    $existing = Get-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -Confirm:$false
        Write-DATLogEntry -Value "[Schedule] Unregistered scheduled build task" -Severity 1
        return $true
    }
    return $false
}

function Get-DATAvailableUpdate {
    <#
    .SYNOPSIS
        Checks GitHub for a newer version of the Driver Automation Tool.
        Returns a hashtable with UpdateAvailable, CurrentVersion, LatestVersion.
    #>
    [CmdletBinding()]
    param ()

    $result = @{ UpdateAvailable = $false; CurrentVersion = $global:ScriptRelease; LatestVersion = $null; Error = $null }
    try {
        $proxyParams = Get-DATWebRequestProxy
        $versionText = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/DriverAutomationToolRev.txt" -UseBasicParsing -TimeoutSec 15 @proxyParams).Content.Trim()
        [version]$latestVersion = $versionText
        $result.LatestVersion = $latestVersion
        if ($latestVersion -gt $global:ScriptRelease) {
            $result.UpdateAvailable = $true
        }
    } catch {
        $result.Error = $_.Exception.Message
        Write-DATLogEntry -Value "[Update] Version check failed: $($_.Exception.Message)" -Severity 2
    }
    return $result
}

function Update-DATApplication {
    <#
    .SYNOPSIS
        Downloads and applies the latest Driver Automation Tool release from GitHub.
        Downloads the master branch ZIP, extracts it over the current install directory,
        and relaunches the application.
    #>
    [CmdletBinding()]
    param (
        [string]$InstallDirectory = $global:ScriptDirectory
    )

    $downloadUrl = "https://github.com/maurice-daly/DriverAutomationTool/archive/refs/heads/master.zip"
    $tempDir = Join-Path $env:TEMP "DATUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $zipPath = Join-Path $tempDir "DriverAutomationTool.zip"

    Write-DATLogEntry -Value "[Update] Starting self-update from GitHub..." -Severity 1
    Write-DATLogEntry -Value "[Update] Install directory: $InstallDirectory" -Severity 1

    try {
        # Create temp directory
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        # Download ZIP
        Write-DATLogEntry -Value "[Update] Downloading release from $downloadUrl..." -Severity 1
        $proxyParams = Get-DATWebRequestProxy
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 120 @proxyParams -ErrorAction Stop

        if (-not (Test-Path $zipPath)) {
            throw "Download failed -- ZIP file not found at $zipPath"
        }
        $zipSize = (Get-Item $zipPath).Length
        Write-DATLogEntry -Value "[Update] Downloaded $([math]::Round($zipSize / 1MB, 2)) MB" -Severity 1

        # Extract ZIP
        Write-DATLogEntry -Value "[Update] Extracting update package..." -Severity 1
        $extractPath = Join-Path $tempDir "Extracted"
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        # The ZIP extracts to a subfolder like DriverAutomationTool-master
        $extractedRoot = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
        if (-not $extractedRoot) {
            throw "Extracted archive does not contain an expected root folder"
        }

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
                Write-DATLogEntry -Value "[Update] App files located in subfolder: $($subFolder.Name)" -Severity 1
            } else {
                throw "Cannot locate $launcherName in extracted archive"
            }
        }

        # Back up current version
        $backupDir = Join-Path $env:TEMP "DATBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Write-DATLogEntry -Value "[Update] Backing up current installation to $backupDir..." -Severity 1
        Copy-Item -Path $InstallDirectory -Destination $backupDir -Recurse -Force

        # Copy new files over existing installation (preserve user data like Settings, Logs, Temp)
        $preserveFolders = @('Settings', 'Logs', 'Temp', 'Packages')
        Write-DATLogEntry -Value "[Update] Applying update files..." -Severity 1
        $sourceItems = Get-ChildItem -Path $sourceDir
        foreach ($item in $sourceItems) {
            if ($item.PSIsContainer -and $item.Name -in $preserveFolders) {
                # Merge -- don't overwrite user data folders, but add new files
                $destFolder = Join-Path $InstallDirectory $item.Name
                if (-not (Test-Path $destFolder)) {
                    Copy-Item -Path $item.FullName -Destination $destFolder -Recurse -Force
                }
                continue
            }
            $destPath = Join-Path $InstallDirectory $item.Name
            Copy-Item -Path $item.FullName -Destination $destPath -Recurse -Force
        }

        Write-DATLogEntry -Value "[Update] Update applied successfully. Backup saved to $backupDir" -Severity 1

        # Clean up temp download
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        return @{
            Success   = $true
            BackupDir = $backupDir
            Error     = $null
        }
    } catch {
        Write-DATLogEntry -Value "[Update] Self-update failed: $($_.Exception.Message)" -Severity 3
        # Attempt restore from backup if it exists
        if ($backupDir -and (Test-Path $backupDir)) {
            Write-DATLogEntry -Value "[Update] Restoring from backup..." -Severity 2
            try {
                Copy-Item -Path "$backupDir\*" -Destination $InstallDirectory -Recurse -Force
                Write-DATLogEntry -Value "[Update] Backup restored successfully" -Severity 1
            } catch {
                Write-DATLogEntry -Value "[Update] Backup restore also failed: $($_.Exception.Message)" -Severity 3
            }
        }
        # Clean up temp
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        return @{
            Success   = $false
            BackupDir = $backupDir
            Error     = $_.Exception.Message
        }
    }
}

function Test-DATHPCMSLReady {
    <#
    .SYNOPSIS
        Validates that the HPCMSL module and all its dependencies are installed and loadable.
        Returns a hashtable with Installed, Version, Ready, and Error properties.
    #>
    [CmdletBinding()]
    param (
        [switch]$AutoInstall
    )

    $result = @{ Installed = $false; Version = $null; Ready = $false; Error = $null }

    # Check if HPCMSL is available
    $hpModule = Get-Module -ListAvailable -Name HPCMSL -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $hpModule) {
        if ($AutoInstall) {
            try {
                Write-DATLogEntry -Value "[HP] HPCMSL not found -- installing from PSGallery..." -Severity 1

                # Ensure PowerShellGet/PackageManagement are recent enough to install from PSGallery
                $psGetVer = (Get-Module -ListAvailable -Name PowerShellGet -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1).Version
                if ($null -eq $psGetVer -or $psGetVer -lt [version]'2.2.5') {
                    Write-DATLogEntry -Value "[HP] PowerShellGet v$psGetVer is outdated -- upgrading to enable PSGallery installs..." -Severity 2
                    Install-Module -Name PowerShellGet -Force -AllowClobber -Scope AllUsers -ErrorAction Stop
                    # Reload the updated module into the current session
                    Import-Module -Name PowerShellGet -Force -ErrorAction SilentlyContinue
                    Write-DATLogEntry -Value "[HP] PowerShellGet upgraded successfully" -Severity 1
                }

                # Install to AllUsers so the module is available for scheduled/headless runs (e.g. SYSTEM context)
                $installScope = 'AllUsers'
                $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                if (-not $isAdmin) {
                    $installScope = 'CurrentUser'
                    Write-DATLogEntry -Value "[HP] Running without admin rights -- falling back to Scope CurrentUser" -Severity 2
                }
                Install-Module -Name HPCMSL -Force -AcceptLicense -Scope $installScope -ErrorAction Stop
                $hpModule = Get-Module -ListAvailable -Name HPCMSL -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
            } catch {
                $result.Error = "Failed to install HPCMSL: $($_.Exception.Message)"
                return $result
            }
        } else {
            $result.Error = "HPCMSL module is not installed. Install it with: Install-Module -Name HPCMSL -Force -AcceptLicense"
            return $result
        }
    }

    $result.Installed = $true
    $result.Version = $hpModule.Version

    # Check for newer version on PSGallery and auto-update if available (once per session)
    if ($AutoInstall -and -not $script:HPCMSLUpdateChecked) {
        try {
            # Ensure PSGallery is trusted so Update-Module/Install-Module won't prompt
            $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
            if ($psGallery -and $psGallery.InstallationPolicy -ne 'Trusted') {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            }
            $galleryModule = Find-Module -Name HPCMSL -Repository PSGallery -ErrorAction Stop
            if ($galleryModule.Version -gt $hpModule.Version) {
                Write-DATLogEntry -Value "[HP] HPCMSL update available: v$($hpModule.Version) → v$($galleryModule.Version) -- updating..." -Severity 1
                Install-Module -Name HPCMSL -Force -AllowClobber -SkipPublisherCheck -Scope AllUsers -ErrorAction Stop
                $hpModule = Get-Module -ListAvailable -Name HPCMSL -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
                $result.Version = $hpModule.Version
                Write-DATLogEntry -Value "[HP] HPCMSL updated to v$($hpModule.Version)" -Severity 1
            }
        } catch {
            Write-DATLogEntry -Value "[HP] HPCMSL update check failed: $($_.Exception.Message) -- continuing with v$($hpModule.Version)" -Severity 2
        }
        $script:HPCMSLUpdateChecked = $true
    }

    # Try to actually import it -- this validates all RequiredModules (HP.Utility, HP.Private, etc.)
    try {
        Import-Module -Name HPCMSL -Force -ErrorAction Stop
        $result.Ready = $true
        Write-DATLogEntry -Value "[HP] HPCMSL v$($hpModule.Version) validated successfully" -Severity 1
    } catch {
        $errMsg = $_.Exception.Message
        # Common cause: required sub-modules not loaded
        if ($errMsg -match "required module '([^']+)'") {
            $missingModule = $Matches[1]
            if ($AutoInstall) {
                try {
                    Write-DATLogEntry -Value "[HP] Required module '$missingModule' missing -- reinstalling HPCMSL..." -Severity 2
                    # Force reinstall to pull all dependencies -- use AllUsers when possible for headless/scheduled task support
                    $repairScope = 'AllUsers'
                    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                    if (-not $isAdmin) { $repairScope = 'CurrentUser' }
                    Install-Module -Name HPCMSL -Force -AcceptLicense -Scope $repairScope -AllowClobber -ErrorAction Stop
                    Import-Module -Name HPCMSL -Force -ErrorAction Stop
                    $result.Ready = $true
                    $result.Version = (Get-Module HPCMSL).Version
                    Write-DATLogEntry -Value "[HP] HPCMSL reinstalled and loaded successfully (v$($result.Version))" -Severity 1
                } catch {
                    $result.Error = "Failed to repair HPCMSL: $($_.Exception.Message)"
                }
            } else {
                $result.Error = "HPCMSL v$($hpModule.Version) cannot load -- required module '$missingModule' is missing. Reinstall with: Install-Module -Name HPCMSL -Force -AcceptLicense -AllowClobber"
            }
        } else {
            $result.Error = "HPCMSL v$($hpModule.Version) cannot load: $errMsg"
        }
    } finally {
        # Remove from current session to avoid interference with the background job
        Remove-Module -Name HPCMSL -Force -ErrorAction SilentlyContinue
    }

    return $result
}

function Invoke-DATOEMDownloadModule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$OEM,
        [string]$Model,
        [string]$SystemSKU,
        [Parameter(Mandatory)][string]$WindowsBuild,
        [string]$WindowsVersion,
        [string]$Architecture = "x64",
        [string]$DownloadDestination,
        [string]$PackageDestination,
        [string]$RegPath,
        [string]$LogDirectory,
        [string]$TempDirectory,
        [string]$RunningMode = "Download Only",
        [string]$CustomDriverPath
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (-not (Test-Path $TempDirectory)) { New-Item -Path $TempDirectory -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $DownloadDestination)) { New-Item -Path $DownloadDestination -ItemType Directory -Force | Out-Null }

    $OEMLinksURL = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/OEMLinks.xml"

    Set-DATRegistryValue -Name "RunningMessage" -Value "Resolving download link for $OEM $Model..." -Type String
    Write-DATLogEntry -Value "[$OEM] Resolving download link for $Model (SKU: $SystemSKU)" -Severity 1

    # Retry helper for catalog downloads (transient network issues)
    function Invoke-CatalogDownload {
        param([string]$Uri, [string]$OutFile, [int]$MaxAttempts = 3, [int]$TimeoutSec = 60)
        for ($i = 1; $i -le $MaxAttempts; $i++) {
            try {
                $proxyParams = Get-DATWebRequestProxy
                Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop @proxyParams
                return
            } catch {
                Write-DATLogEntry -Value "[Warning] - Catalog download attempt $i/$MaxAttempts failed: $($_.Exception.Message)" -Severity 2
                if ($i -lt $MaxAttempts) { Start-Sleep -Seconds 5 } else { throw }
            }
        }
    }

    try {
        $proxyParams = Get-DATWebRequestProxy
        $webContent = $null
        for ($i = 1; $i -le 3; $i++) {
            try {
                $webContent = (Invoke-WebRequest -Uri $OEMLinksURL -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop @proxyParams).Content
                break
            } catch {
                if ($i -lt 3) {
                    Write-DATLogEntry -Value "[Warning] - OEM links catalog attempt $i failed: $($_.Exception.Message). Retrying in 5s..." -Severity 2
                    Start-Sleep -Seconds 5
                } else { throw }
            }
        }
        [xml]$OEMLinks = $webContent
    } catch {
        Write-DATLogEntry -Value "[Error] - Failed to download OEM links catalog: $($_.Exception.Message)" -Severity 3
        throw "OEM links catalog unavailable: $($_.Exception.Message)"
    }

    $downloadURL = $null
    $downloadFileName = $null
    $gfxDownloadURL = $null
    $gfxDownloadFileName = $null
    $gfxBrand = $null
    $catalogVersion = $null

    switch ($OEM) {
        "Dell" {
            $DellLink = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link |
                Where-Object { $_.Type -eq "XMLCabinetSource" } | Select-Object -ExpandProperty URL -First 1
            if ([string]::IsNullOrEmpty($DellLink)) { throw "Dell catalog URL not found in OEM links" }

            $DellCabFile = [string]($DellLink | Split-Path -Leaf)
            $DellXMLFile = $DellCabFile.TrimEnd(".cab") + ".xml"
            $DellCabPath = Join-Path $TempDirectory $DellCabFile
            $DellXMLPath = Join-Path $TempDirectory $DellXMLFile

            if (-not (Test-Path $DellXMLPath)) {
                Write-DATLogEntry -Value "[$OEM] Downloading Dell catalog..." -Severity 1
                Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading Dell driver catalog..." -Type String
                if (-not (Test-Path $DellCabPath)) {
                    $proxyParams = Get-DATWebRequestProxy
                    Invoke-WebRequest -Uri $DellLink -OutFile $DellCabPath -UseBasicParsing -TimeoutSec 60 @proxyParams
                }
                & expand.exe "$DellCabPath" -F:* "$TempDirectory" -R 2>&1 | Out-Null
            }

            if (-not (Test-Path $DellXMLPath)) { throw "Dell catalog XML not found after extraction" }

            [xml]$DellModelXML = Get-Content -Path $DellXMLPath -Raw
            $DellWindowsVersion = $WindowsVersion.Replace(" ", "")

            $matchingPkg = $DellModelXML.driverpackmanifest.driverpackage | Where-Object {
                ($_.SupportedOperatingSystems.OperatingSystem.osCode -eq $DellWindowsVersion) -and
                ($_.SupportedOperatingSystems.OperatingSystem.osArch -match $Architecture) -and
                ($_.SupportedSystems.Brand.Model.name -contains $Model -or
                 $_.SupportedSystems.Brand.Model.SystemID -contains $SystemSKU)
            } | Select-Object -First 1

            if ($null -eq $matchingPkg) {
                $matchingPkg = $DellModelXML.driverpackmanifest.driverpackage | Where-Object {
                    ($_.SupportedOperatingSystems.OperatingSystem.osCode -eq $DellWindowsVersion) -and
                    ($_.SupportedOperatingSystems.OperatingSystem.osArch -match $Architecture) -and
                    ($_.SupportedSystems.Brand.Model.name -like "*$Model*")
                } | Select-Object -First 1
            }

            if ($null -ne $matchingPkg) {
                $catalogVersion = $matchingPkg.dellVersion
                $DellBaseURL = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link |
                    Where-Object { $_.Type -eq "DownloadBase" } | Select-Object -ExpandProperty URL -First 1
                if ([string]::IsNullOrEmpty($DellBaseURL)) { $DellBaseURL = "https://downloads.dell.com" }
                $DellBaseURL = $DellBaseURL.TrimEnd('/')
                $dellPath = $matchingPkg.path.TrimStart('/')
                $downloadURL = "$DellBaseURL/$dellPath"
                $downloadFileName = $matchingPkg.path | Split-Path -Leaf
                Write-DATLogEntry -Value "[$OEM] Found driver pack: $downloadFileName" -Severity 1
            } else {
                throw "No matching Dell driver package found for $Model ($DellWindowsVersion $Architecture)"
            }
        }
        "HP" {
            # HP uses HPCMSL to discover required SoftPaqs, then downloads, extracts, and
            # copies only the INF-targeted driver folders to a staging directory.
            # WIM creation reuses the common Invoke-DATDriverFilePackaging path.

            # Validate HPCMSL
            Write-DATLogEntry -Value "[HP] Validating HPCMSL module before starting build..." -Severity 1
            $hpCheck = Test-DATHPCMSLReady -AutoInstall
            if (-not $hpCheck.Ready) {
                throw "HPCMSL prerequisite check failed: $($hpCheck.Error)"
            }
            Write-DATLogEntry -Value "[HP] Starting driver package build for $Model (SKU: $SystemSKU)" -Severity 1 -UpdateUI
            Write-DATLogEntry -Value "[HP] Parameters: SKU=$SystemSKU, Build=$WindowsBuild, Version=$WindowsVersion" -Severity 1
            Write-DATLogEntry -Value "[HP] Download Destination: $DownloadDestination" -Severity 1
            Write-DATLogEntry -Value "[HP] Temp Directory: $TempDirectory" -Severity 1

            # Determine OS parameter for HPCMSL
            switch -Wildcard ($WindowsVersion) {
                "*Windows 11*" { $HPOS = "Win11" }
                "*Windows 10*" { $HPOS = "Win10" }
                default { $HPOS = "Win11" }
            }

            # Build HP-specific temp path: Temp\HP\Model\OS\OSVer
            $HPTempDirectory = Join-Path $TempDirectory "HP\$Model\$HPOS\$WindowsBuild"
            if (-not (Test-Path $HPTempDirectory)) { New-Item -Path $HPTempDirectory -ItemType Directory -Force | Out-Null }
            $HPExtractDir = Join-Path $HPTempDirectory "Extracted"
            $HPStagingDir = Join-Path $HPTempDirectory "Staging"
            foreach ($dir in @($HPTempDirectory, $HPExtractDir, $HPStagingDir)) {
                if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
            }
            Write-DATLogEntry -Value "[HP] Temp download: $HPTempDirectory" -Severity 1
            Write-DATLogEntry -Value "[HP] Extract: $HPExtractDir" -Severity 1
            Write-DATLogEntry -Value "[HP] Staging: $HPStagingDir" -Severity 1

            # Split comma-separated SKUs; try each in order until one returns SoftPaqs
            $SKUList = $SystemSKU -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[a-fA-F0-9]{4}$' }
            if ($SKUList.Count -eq 0) {
                throw "No valid 4-character platform IDs found in SKU: $SystemSKU"
            }
            Write-DATLogEntry -Value "[HP] Platform IDs to try: $($SKUList -join ', ')" -Severity 1

            # Read concurrent download setting (1-4, default 2)
            $HPConcurrentDownloads = 2
            $regConcurrency = (Get-ItemProperty -Path $global:RegPath -Name 'HPConcurrentDownloads' -ErrorAction SilentlyContinue).HPConcurrentDownloads
            if (-not [string]::IsNullOrEmpty($regConcurrency)) {
                $parsedConcurrency = 0
                if ([int]::TryParse($regConcurrency, [ref]$parsedConcurrency) -and $parsedConcurrency -ge 1 -and $parsedConcurrency -le 4) {
                    $HPConcurrentDownloads = $parsedConcurrency
                }
            }
            Write-DATLogEntry -Value "[HP] Concurrent downloads: $HPConcurrentDownloads" -Severity 1

            # ── Step 1: Discover SoftPaqs using New-HPDriverPack -WhatIf ──────────
            $SoftPaqIDs = @()
            $DiscoveryPlatformID = $null

            foreach ($PlatformID in $SKUList) {
                Write-DATLogEntry -Value "[HP] Querying required SoftPaqs for platform $PlatformID (WhatIf)..." -Severity 1
                Set-DATRegistryValue -Name "RunningMessage" -Value "Querying HP SoftPaqs for platform $PlatformID..." -Type String

                try {
                    $SoftPaqInfo = $null
                    $SoftPaqStdOut = New-HPDriverPack -Platform "$PlatformID" -Os "$HPOS" -OSVer "$WindowsBuild" -Format wim `
                        -Path "$DownloadDestination" -TempDownloadPath "$HPTempDirectory" `
                        -WhatIf -InformationVariable SoftPaqInfo -ErrorVariable SoftPaqError -ErrorAction SilentlyContinue

                    # Parse SoftPaq IDs from all output streams
                    $allLines = @()
                    if ($SoftPaqInfo) {
                        $allLines += @($SoftPaqInfo | ForEach-Object {
                            if ($_ -is [System.Management.Automation.InformationRecord]) { $_.MessageData.ToString() }
                            else { "$_" }
                        })
                    }
                    if ($SoftPaqStdOut) {
                        $allLines += @($SoftPaqStdOut | ForEach-Object { "$_" })
                    }

                    $SoftPaqIDs = @($allLines | Where-Object { $_ -match '^\s+(?:sp)?(\d{4,})' } | ForEach-Object {
                        if ($_ -match '^\s+(?:sp)?(\d{4,})') { $Matches[1] }
                    })

                    if ($SoftPaqIDs.Count -gt 0) {
                        $DiscoveryPlatformID = $PlatformID
                        Write-DATLogEntry -Value "[HP] Found $($SoftPaqIDs.Count) SoftPaqs for platform ${PlatformID}:" -Severity 1
                        foreach ($line in ($allLines | Where-Object { $_ -match '^\s+(?:sp)?(\d{4,})' })) {
                            Write-DATLogEntry -Value "-- Download required - $($line.Trim())" -Severity 1
                        }
                        break
                    } else {
                        Write-DATLogEntry -Value "[HP] No SoftPaqs found for platform $PlatformID -- trying next" -Severity 2
                    }
                } catch {
                    Write-DATLogEntry -Value "[HP] WhatIf failed for ${PlatformID}: $($_.Exception.Message)" -Severity 2
                }
            }

            if ($SoftPaqIDs.Count -eq 0) {
                throw "No HP SoftPaqs found for any platform ID: $($SKUList -join ', ')"
            }

            $totalSoftPaqs = $SoftPaqIDs.Count
            Set-DATRegistryValue -Name "DownloadBytes" -Value "0" -Type String
            Set-DATRegistryValue -Name "BytesTransferred" -Value "0" -Type String

            # ── Step 2: Download SoftPaqs in parallel (separate processes) ────────
            # Check for abort before starting downloads
            $abortReg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
            if ($abortReg.RunningState -eq 'Aborted') { throw "HP download aborted by user" }

            Write-DATLogEntry -Value "[HP] Downloading $totalSoftPaqs SoftPaqs ($HPConcurrentDownloads concurrent processes)..." -Severity 1
            Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading $totalSoftPaqs HP SoftPaqs..." -Type String
            Set-DATRegistryValue -Name "RunningMode" -Value "Download" -Type String

            $DownloadStartTime = Get-Date

            # Build queue of SoftPaqs to download (skip cached)
            $downloadQueue = [System.Collections.Generic.Queue[string]]::new()
            $cachedCount = 0
            foreach ($spId in $SoftPaqIDs) {
                $destFile = Join-Path $HPTempDirectory "SP$spId.exe"
                if (Test-Path $destFile) {
                    Write-DATLogEntry -Value "[HP] SoftPaq SP$spId already cached -- skipping" -Severity 1
                    $cachedCount++
                } else {
                    $downloadQueue.Enqueue($spId)
                }
            }
            $completedDownloads = $cachedCount
            $failedDownloads = @()
            $activeProcs = @{}  # spId -> Process object

            # Resolve powershell executable path
            $pwshExe = if ($PSVersionTable.PSVersion.Major -ge 7) {
                (Get-Process -Id $PID).Path
            } else {
                "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
            }

            try {
                while ($downloadQueue.Count -gt 0 -or $activeProcs.Count -gt 0) {
                    # Check for abort
                    $abortReg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
                    if ($abortReg.RunningState -eq 'Aborted') {
                        Write-DATLogEntry -Value "[HP] Abort detected -- killing download processes" -Severity 2
                        throw "HP download aborted by user"
                    }

                    # Fill slots up to concurrency limit
                    while ($activeProcs.Count -lt $HPConcurrentDownloads -and $downloadQueue.Count -gt 0) {
                        $spId = $downloadQueue.Dequeue()
                        $savePath = Join-Path $HPTempDirectory "SP$spId.exe"
                        $script = "Import-Module HPCMSL -Force; Get-Softpaq -Number $spId -SaveAs '$($savePath -replace "'","''")' -MaxRetries 3 -Quiet"
                        $proc = Start-Process -FilePath $pwshExe -ArgumentList "-NoProfile", "-NoLogo", "-ExecutionPolicy", "Bypass", "-Command", $script `
                            -WindowStyle Hidden -PassThru
                        $activeProcs[$spId] = $proc
                        Write-DATLogEntry -Value "[HP] Started SP$spId download (PID $($proc.Id))" -Severity 1
                    }

                    # Check for completed processes
                    $finishedIds = @($activeProcs.Keys | Where-Object { $activeProcs[$_].HasExited })
                    foreach ($spId in $finishedIds) {
                        $proc = $activeProcs[$spId]
                        $activeProcs.Remove($spId)
                        $savePath = Join-Path $HPTempDirectory "SP$spId.exe"
                        if ($proc.ExitCode -eq 0 -and (Test-Path $savePath)) {
                            $completedDownloads++
                            Write-DATLogEntry -Value "[HP] SP$spId download completed (PID $($proc.Id))" -Severity 1
                        } else {
                            $failedDownloads += $spId
                            Write-DATLogEntry -Value "[HP] SP$spId download failed (exit code $($proc.ExitCode), PID $($proc.Id))" -Severity 3
                        }
                    }

                    # Update progress using actual bytes on disk
                    $spFiles = Get-ChildItem -Path $HPTempDirectory -Filter "SP*.exe" -ErrorAction SilentlyContinue
                    $downloadedBytes = ($spFiles | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if ($null -eq $downloadedBytes) { $downloadedBytes = [long]0 }
                    $downloadedMB = [math]::Round($downloadedBytes / 1MB, 2)

                    # Estimate total size from average file size
                    $completedFiles = @($spFiles | Where-Object { $_.Length -gt 0 })
                    if ($completedDownloads -gt 0 -and $completedFiles.Count -gt 0) {
                        $avgFileSize = $downloadedBytes / [math]::Max(1, $completedFiles.Count)
                        $estimatedTotal = [long]($avgFileSize * $totalSoftPaqs)
                        Set-DATRegistryValue -Name "DownloadBytes" -Value "$estimatedTotal" -Type String
                    }
                    Set-DATRegistryValue -Name "BytesTransferred" -Value "$downloadedBytes" -Type String
                    Set-DATRegistryValue -Name "DownloadSize" -Value "$downloadedMB MB" -Type String

                    $elapsed = ((Get-Date) - $DownloadStartTime).TotalSeconds
                    if ($elapsed -gt 0 -and $downloadedBytes -gt 0) {
                        $speed = [math]::Round(($downloadedMB / $elapsed), 2)
                        Set-DATRegistryValue -Name "DownloadSpeed" -Value "$speed MB/s" -Type String
                    }

                    Set-DATRegistryValue -Name "RunningMessage" -Value "SoftPaq $completedDownloads of $totalSoftPaqs ($($activeProcs.Count) active) -- $downloadedMB MB" -Type String

                    Start-Sleep -Seconds 2
                }
            } finally {
                # Kill all active download processes on abort or error
                foreach ($spId in @($activeProcs.Keys)) {
                    $proc = $activeProcs[$spId]
                    if (-not $proc.HasExited) {
                        try { $proc.Kill() } catch { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
                        Write-DATLogEntry -Value "[HP] Killed SP$spId download process (PID $($proc.Id))" -Severity 2
                    }
                }
                # Kill any orphaned SoftPaq self-extracting processes
                Get-Process -ErrorAction SilentlyContinue | Where-Object {
                    $_.ProcessName -match '^SP\d+$'
                } | ForEach-Object {
                    try { $_.Kill() } catch { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
                }
            }

            # Final download count
            $completedDownloads = $totalSoftPaqs - $failedDownloads.Count
            Write-DATLogEntry -Value "[HP] Downloads complete: $completedDownloads of $totalSoftPaqs succeeded" -Severity 1

            if ($failedDownloads.Count -gt 0) {
                Write-DATLogEntry -Value "[HP] Failed SoftPaqs: $($failedDownloads -join ', ') -- retrying sequentially..." -Severity 2
                Set-DATRegistryValue -Name "RunningMessage" -Value "Retrying $($failedDownloads.Count) failed SoftPaqs..." -Type String

                $retryFailed = @()
                foreach ($spId in $failedDownloads) {
                    $abortReg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
                    if ($abortReg.RunningState -eq 'Aborted') { throw "HP download aborted by user" }

                    $savePath = Join-Path $HPTempDirectory "SP$spId.exe"
                    # Remove any partial file from the first attempt
                    if (Test-Path $savePath) { Remove-Item $savePath -Force -ErrorAction SilentlyContinue }

                    Set-DATRegistryValue -Name "RunningMessage" -Value "Retrying SoftPaq SP$spId..." -Type String
                    Write-DATLogEntry -Value "[HP] Retrying SP$spId download..." -Severity 1

                    try {
                        Get-Softpaq -Number $spId -SaveAs $savePath -MaxRetries 3 -ErrorAction Stop
                        $completedDownloads++
                        Write-DATLogEntry -Value "[HP] SP$spId retry succeeded" -Severity 1
                    } catch {
                        $retryFailed += $spId
                        Write-DATLogEntry -Value "[HP] SP$spId retry failed: $($_.Exception.Message)" -Severity 3
                    }
                }

                $failedDownloads = @($retryFailed)
                if ($failedDownloads.Count -gt 0) {
                    Write-DATLogEntry -Value "[HP] Permanently failed SoftPaqs after retry: $($failedDownloads -join ', ')" -Severity 3
                } else {
                    Write-DATLogEntry -Value "[HP] All SoftPaqs downloaded successfully after retry" -Severity 1
                }
            }

            # Remove failed IDs from the processing list
            $successfulIDs = @($SoftPaqIDs | Where-Object { $_ -notin $failedDownloads })
            if ($successfulIDs.Count -eq 0) {
                throw "All $totalSoftPaqs SoftPaq downloads failed for $Model"
            }

            # ── Step 3: Extract and copy INF-targeted drivers ─────────────────────
            $abortReg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
            if ($abortReg.RunningState -eq 'Aborted') { throw "HP download aborted by user" }

            Set-DATRegistryValue -Name "RunningMode" -Value "Extracting" -Type String
            Write-DATLogEntry -Value "[HP] Extracting $($successfulIDs.Count) SoftPaqs and copying drivers..." -Severity 1

            # OS identifier for INF path lookup
            $OsId = if ($HPOS -eq 'Win11') { 'W11' } else { 'WT64' }
            $fullInfPathName = "$($OsId)_$($WindowsBuild.ToUpper())_INFPath"
            $fallbackInfPathName = "$($OsId)_INFPath"
            Write-DATLogEntry -Value "[HP] INF path keys: primary=$fullInfPathName, fallback=$fallbackInfPathName" -Severity 1

            $extractedCount = 0
            $skippedCount = 0

            foreach ($spId in $successfulIDs) {
                $abortReg = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
                if ($abortReg.RunningState -eq 'Aborted') { throw "HP download aborted by user" }

                $spFile = Join-Path $HPTempDirectory "SP$spId.exe"
                $spExtractDir = Join-Path $HPExtractDir "$spId"
                $spStagingDir = Join-Path $HPStagingDir "$spId"

                $extractedCount++
                Set-DATRegistryValue -Name "RunningMessage" -Value "Extracting SoftPaq SP$spId ($extractedCount of $($successfulIDs.Count))..." -Type String
                Set-DATRegistryValue -Name "BytesTransferred" -Value "$extractedCount" -Type String
                Set-DATRegistryValue -Name "DownloadBytes" -Value "$($successfulIDs.Count)" -Type String

                if (-not (Test-Path $spFile)) {
                    Write-DATLogEntry -Value "[HP] SP$spId.exe not found -- skipping" -Severity 2
                    $skippedCount++
                    continue
                }

                # Extract SoftPaq silently (timeout after 5 minutes to avoid hangs)
                Write-DATLogEntry -Value "[HP] Extracting SP$spId..." -Severity 1
                if (-not (Test-Path $spExtractDir)) { New-Item -Path $spExtractDir -ItemType Directory -Force | Out-Null }
                try {
                    $extractProc = Start-Process -FilePath $spFile -ArgumentList "-e", "-f `"$spExtractDir`"", "-s" `
                        -WindowStyle Hidden -PassThru
                    if (-not $extractProc.WaitForExit(300000)) {
                        try { $extractProc.Kill() } catch {}
                        Write-DATLogEntry -Value "[HP] SP$spId extraction timed out after 5 minutes -- skipping" -Severity 3
                        $skippedCount++
                        continue
                    }
                    if ($extractProc.ExitCode -ne 0) {
                        Write-DATLogEntry -Value "[HP] SP$spId extraction exited with code $($extractProc.ExitCode)" -Severity 2
                    }
                } catch {
                    Write-DATLogEntry -Value "[HP] SP$spId extraction failed: $($_.Exception.Message)" -Severity 3
                    $skippedCount++
                    continue
                }

                # Get metadata for INF path mapping
                try {
                    $metadata = Get-HPSoftpaqMetadata -Number $spId -MaxRetries 3
                } catch {
                    Write-DATLogEntry -Value "[HP] SP$spId metadata lookup failed: $($_.Exception.Message) -- copying all extracted content" -Severity 2
                    # Fallback: copy everything
                    if (-not (Test-Path $spStagingDir)) { New-Item -Path $spStagingDir -ItemType Directory -Force | Out-Null }
                    Copy-Item "$spExtractDir\*" $spStagingDir -Recurse -Force -ErrorAction SilentlyContinue
                    continue
                }

                if ($metadata.ContainsKey('Devices_INFPath')) {
                    # Determine which INF path key to use
                    $infPathName = if ($metadata.Devices_INFPath.ContainsKey($fullInfPathName)) {
                        $fullInfPathName
                    } elseif ($metadata.Devices_INFPath.ContainsKey($fallbackInfPathName)) {
                        $fallbackInfPathName
                    } else { $null }

                    if ($infPathName) {
                        $infPaths = @($metadata.Devices_INFPath[$infPathName])
                        if (-not (Test-Path $spStagingDir)) { New-Item -Path $spStagingDir -ItemType Directory -Force | Out-Null }
                        foreach ($infPath in $infPaths) {
                            $infPath = $infPath.TrimStart('.\')
                            $absoluteInfPath = Join-Path $spExtractDir $infPath
                            if (Test-Path $absoluteInfPath) {
                                Write-DATLogEntry -Value "[HP] SP$spId copying INF path: $infPath" -Severity 1
                                Copy-Item $absoluteInfPath $spStagingDir -Recurse -Force -ErrorAction SilentlyContinue
                            } else {
                                Write-DATLogEntry -Value "[HP] SP$spId INF path not found: $absoluteInfPath" -Severity 2
                            }
                        }
                    } else {
                        Write-DATLogEntry -Value "[HP] SP$spId missing INF path key ($fullInfPathName / $fallbackInfPathName) -- skipping" -Severity 2
                        $skippedCount++
                    }
                } else {
                    Write-DATLogEntry -Value "[HP] SP$spId is not DPB compliant (no Devices_INFPath) -- skipping" -Severity 2
                    $skippedCount++
                }
            }

            # Clean up extracted temp files (keep staging)
            Remove-Item -Path "$HPExtractDir\*" -Recurse -Force -ErrorAction SilentlyContinue

            $stagedFiles = (Get-ChildItem -Path $HPStagingDir -Recurse -File -ErrorAction SilentlyContinue).Count
            Write-DATLogEntry -Value "[HP] Extraction complete: $stagedFiles driver files staged, $skippedCount SoftPaqs skipped" -Severity 1

            if ($stagedFiles -eq 0) {
                throw "No driver files were extracted from HP SoftPaqs for $Model"
            }

            # ── Step 4: Package (WIM creation via common path) ────────────────────
            # HP now flows into common packaging like other OEMs.
            # Create a sentinel file so Invoke-DATDriverFilePackaging can find the staging dir.
            # We bypass the common download+extract and call packaging directly.
            if ($RunningMode -ne "Download Only") {
                $packageDest = if (-not [string]::IsNullOrEmpty($PackageDestination)) { $PackageDestination } else { $DownloadDestination }
                $packagingPlatform = if ($RunningMode -eq 'WIM Package Only') { 'WIM Package Only' } else { $RunningMode }

                # Invoke-DATDriverFilePackaging expects a single file to extract.
                # For HP, the drivers are already extracted to $HPStagingDir.
                # Call the packaging function with a virtual ".dir" path -- the function
                # will detect the HP staging directory and skip extraction.
                Set-DATRegistryValue -Name "RunningMessage" -Value "Creating WIM package for HP $Model..." -Type String
                Set-DATRegistryValue -Name "RunningMode" -Value "Packaging" -Type String
                Write-DATLogEntry -Value "[HP] Creating WIM package from staging directory..." -Severity 1

                Invoke-DATDriverFilePackaging -FilePath $HPStagingDir -OEM $OEM -Model $Model `
                    -OS "$WindowsVersion $WindowsBuild" -Destination $packageDest -Platform $packagingPlatform
            }

            Set-DATRegistryValue -Name "RunningMode" -Value "Download Completed" -Type String
            Write-DATLogEntry -Value "[HP] Driver package process completed successfully" -Severity 1 -UpdateUI

            # HP handles its own multi-SoftPaq download -- skip common single-file download path
            return
        }
        "Lenovo" {
            $LenovoLink = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Lenovo" }).Link |
                Where-Object { $_.Type -eq "XMLSource" } | Select-Object -ExpandProperty URL -First 1
            if ([string]::IsNullOrEmpty($LenovoLink)) { throw "Lenovo catalog URL not found in OEM links" }

            $LenovoFile = [string]($LenovoLink | Split-Path -Leaf)
            $LenovoFilePath = Join-Path $TempDirectory $LenovoFile

            if (-not (Test-Path $LenovoFilePath)) {
                Write-DATLogEntry -Value "[$OEM] Downloading Lenovo catalog..." -Severity 1
                Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading Lenovo driver catalog..." -Type String
                Invoke-CatalogDownload -Uri $LenovoLink -OutFile $LenovoFilePath
            }

            [xml]$LenovoModelXML = Get-Content -Path $LenovoFilePath
            $LenovoDrivers = $LenovoModelXML.ModelList.Model
            $WinVer = "Win" + "$($WindowsVersion.Split(' ')[1])"

            $matchingModel = $LenovoDrivers | Where-Object {
                $_.Name -eq $Model -and $_.SCCM.Version -eq $WindowsBuild -and $_.SCCM.OS -eq $WinVer
            } | Select-Object -First 1

            if ($null -ne $matchingModel -and $null -ne $matchingModel.SCCM) {
                $sccmNode = $matchingModel.SCCM | Where-Object { $_.Version -eq $WindowsBuild -and $_.OS -eq $WinVer } | Select-Object -First 1
                if ($null -eq $sccmNode) { $sccmNode = $matchingModel.SCCM }
                $catalogVersion = if ($sccmNode.date) { $sccmNode.date } else { '' }
                $downloadURL = $matchingModel.SCCM.'#text'
                if ($downloadURL -is [array]) { $downloadURL = $downloadURL[0] }
                if ([string]::IsNullOrEmpty($downloadURL)) { $downloadURL = [string]$matchingModel.SCCM }
                $downloadFileName = $downloadURL | Split-Path -Leaf
                Write-DATLogEntry -Value "[$OEM] Found SCCM pack: $downloadFileName" -Severity 1
                Write-DATLogEntry -Value "[$OEM] Resolved download URL: $downloadURL" -Severity 1

                # Check for supplemental NVIDIA GFX driver package
                $gfxNode = $matchingModel.GFX | Where-Object {
                    $_.os -eq $WinVer -and $_.version -eq $WindowsBuild
                } | Select-Object -First 1

                $gfxDownloadURL = $null
                $gfxDownloadFileName = $null
                if ($null -ne $gfxNode) {
                    $gfxDownloadURL = $gfxNode.'#text'
                    if ([string]::IsNullOrEmpty($gfxDownloadURL)) { $gfxDownloadURL = [string]$gfxNode }
                    $gfxDownloadFileName = $gfxDownloadURL | Split-Path -Leaf
                    $gfxBrand = $gfxNode.brand
                    Write-DATLogEntry -Value "[$OEM] Supplemental $gfxBrand GFX package found: $gfxDownloadFileName" -Severity 1
                    Set-DATRegistryValue -Name "RunningMessage" -Value "$Model has supplemental $gfxBrand GFX drivers - both packages will be downloaded" -Type String
                }
            } else {
                throw "No matching Lenovo driver package found for $Model ($WinVer $WindowsBuild)"
            }
        }
        "Microsoft" {
            $MicrosoftXMLPath = Join-Path $TempDirectory "OSDMSDrivers.xml"
            if (-not (Test-Path $MicrosoftXMLPath)) {
                # OEM LINK Temporary MS Hard Link
                $MicrosoftXMLSource = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/OSDMSDrivers.xml"
                Write-DATLogEntry -Value "[$OEM] Downloading Microsoft catalog..." -Severity 1
                Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading Microsoft driver catalog..." -Type String
                $proxyParams = Get-DATWebRequestProxy
                Invoke-WebRequest -Uri $MicrosoftXMLSource -OutFile $MicrosoftXMLPath -UseBasicParsing -TimeoutSec 30 @proxyParams
            } else {
                Write-DATLogEntry -Value "[$OEM] Using cached Microsoft catalog: $MicrosoftXMLPath" -Severity 1
            }

            $MSModelList = Import-Clixml -Path $MicrosoftXMLPath
            $MSArchFilter = if ($Architecture -eq 'Arm64') { 'arm64' } else { 'amd64' }
            $matchingModel = $MSModelList | Where-Object {
                $_.Model -eq $Model -and $_.OSVersion -match $WindowsVersion -and $_.OSArchitecture -eq $MSArchFilter
            } | Select-Object -First 1

            if ($null -ne $matchingModel -and -not [string]::IsNullOrEmpty($matchingModel.Url)) {
                $downloadURL = $matchingModel.Url
                $downloadFileName = $downloadURL | Split-Path -Leaf
                $catalogVersion = if ($matchingModel.ReleaseDate) { $matchingModel.ReleaseDate } else { '' }
                Write-DATLogEntry -Value "[$OEM] Found Surface driver: $downloadFileName (ReleaseDate: $catalogVersion)" -Severity 1
            } else {
                throw "No matching Microsoft driver package found for $Model ($WindowsVersion)"
            }
        }
        "Acer" {
            $AcerLink = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Acer" }).Link |
                Where-Object { $_.Type -eq "XMLSource" } | Select-Object -ExpandProperty URL -First 1
            if ([string]::IsNullOrEmpty($AcerLink)) { throw "Acer catalog URL not found in OEM links" }

            $AcerFile = [string]($AcerLink | Split-Path -Leaf)
            $AcerFilePath = Join-Path $TempDirectory $AcerFile

            if (-not (Test-Path $AcerFilePath)) {
                Write-DATLogEntry -Value "[$OEM] Downloading Acer catalog..." -Severity 1
                Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading Acer driver catalog..." -Type String
                Invoke-CatalogDownload -Uri $AcerLink -OutFile $AcerFilePath
            } else {
                Write-DATLogEntry -Value "[$OEM] Using cached Acer catalog: $AcerFilePath" -Severity 1
            }

            [xml]$AcerModelXML = Get-Content -Path $AcerFilePath
            $AcerDrivers = $AcerModelXML.ModelList.Model
            $WinVer = "Win" + "$($WindowsVersion.Split(' ')[1])"

            Write-DATLogEntry -Value "[$OEM] Searching catalog for: Name='$Model' OS='$WinVer' Build='$WindowsBuild'" -Severity 1

            $matchingModel = $AcerDrivers | Where-Object {
                $_.Name -eq $Model -and $_.SCCM.Version -eq $WindowsBuild -and $_.SCCM.OS -eq $WinVer
            } | Select-Object -First 1

            if ($null -eq $matchingModel) {
                # Fuzzy fallback -- partial name match
                Write-DATLogEntry -Value "[$OEM] Exact match not found, attempting partial name match for '$Model'" -Severity 2
                $matchingModel = $AcerDrivers | Where-Object {
                    $_.Name -like "*$Model*" -and $_.SCCM.Version -eq $WindowsBuild -and $_.SCCM.OS -eq $WinVer
                } | Select-Object -First 1
            }

            if ($null -ne $matchingModel -and $null -ne $matchingModel.SCCM) {
                $downloadURL = $matchingModel.SCCM.'#text'
                if ($downloadURL -is [array]) { $downloadURL = $downloadURL[0] }
                if ([string]::IsNullOrEmpty($downloadURL)) { $downloadURL = [string]$matchingModel.SCCM }
                $downloadFileName = $downloadURL | Split-Path -Leaf
                Write-DATLogEntry -Value "[$OEM] Found driver pack: $downloadFileName" -Severity 1
                Write-DATLogEntry -Value "[$OEM] Resolved download URL: $downloadURL" -Severity 1
            } else {
                # Log all available models/builds to aid diagnostics
                $available = $AcerDrivers | Where-Object { $_.SCCM.OS -eq $WinVer } | Select-Object -ExpandProperty Name -Unique
                Write-DATLogEntry -Value "[$OEM] Available models for ${WinVer}: $($available -join ', ')" -Severity 2
                throw "No matching Acer driver package found for $Model ($WinVer $WindowsBuild)"
            }
        }
        default {
            throw "Unsupported OEM: $OEM"
        }
    }

    if ([string]::IsNullOrEmpty($downloadURL)) {
        throw "Failed to resolve download URL for $OEM $Model"
    }

    # Pre-download URL reachability check
    Write-DATLogEntry -Value "[$OEM] Validating download URL accessibility..." -Severity 1
    Set-DATRegistryValue -Name "RunningMessage" -Value "Validating download URL for $OEM $Model..." -Type String
    $mainSizeBytes = [long]0
    try {
        $proxyParams = Get-DATWebRequestProxy
        $headCheck = Invoke-WebRequest -Uri $downloadURL -Method Head -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop @proxyParams
        if ($headCheck.Headers.'Content-Length') { $mainSizeBytes = [long]$headCheck.Headers.'Content-Length'[0] }
        $expectedSizeMB = if ($mainSizeBytes -gt 0) { [math]::Round($mainSizeBytes / 1MB, 2) } else { '(unknown)' }
        Write-DATLogEntry -Value "[$OEM] URL reachable - HTTP $($headCheck.StatusCode), size: $expectedSizeMB MB" -Severity 1
    } catch {
        Write-DATLogEntry -Value "[Warning] - URL pre-check failed for $downloadURL : $($_.Exception.Message)" -Severity 2
        Write-DATLogEntry -Value "[$OEM] Proceeding with download attempt despite HEAD failure" -Severity 2
    }

    # Validate and report GFX supplemental download size
    $gfxSizeBytes = [long]0
    if (-not [string]::IsNullOrEmpty($gfxDownloadURL)) {
        Write-DATLogEntry -Value "[$OEM] Validating GFX download URL accessibility..." -Severity 1
        try {
            $proxyParams = Get-DATWebRequestProxy
            $gfxHeadCheck = Invoke-WebRequest -Uri $gfxDownloadURL -Method Head -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop @proxyParams
            if ($gfxHeadCheck.Headers.'Content-Length') { $gfxSizeBytes = [long]$gfxHeadCheck.Headers.'Content-Length'[0] }
            $gfxSizeMB = if ($gfxSizeBytes -gt 0) { [math]::Round($gfxSizeBytes / 1MB, 2) } else { '(unknown)' }
            Write-DATLogEntry -Value "[$OEM] GFX URL reachable - HTTP $($gfxHeadCheck.StatusCode), size: $gfxSizeMB MB" -Severity 1
        } catch {
            Write-DATLogEntry -Value "[Warning] - GFX URL pre-check failed for $gfxDownloadURL : $($_.Exception.Message)" -Severity 2
        }
        # Log combined download size
        if ($mainSizeBytes -gt 0 -and $gfxSizeBytes -gt 0) {
            $totalSizeMB = [math]::Round(($mainSizeBytes + $gfxSizeBytes) / 1MB, 2)
            $mainMB = [math]::Round($mainSizeBytes / 1MB, 2)
            $gfxMB = [math]::Round($gfxSizeBytes / 1MB, 2)
            Write-DATLogEntry -Value "[$OEM] Total download: $totalSizeMB MB (SCCM: $mainMB MB + $($gfxBrand) GFX: $gfxMB MB)" -Severity 1
            Set-DATRegistryValue -Name "RunningMessage" -Value "Total download for ${Model}: $totalSizeMB MB (SCCM: $mainMB MB + $($gfxBrand) GFX: $gfxMB MB)" -Type String
        }
    }

    # Download the driver pack
    Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading $OEM $Model driver pack..." -Type String
    Write-DATLogEntry -Value "[$OEM] Starting download: $downloadURL" -Severity 1

    Invoke-DATContentDownload -DownloadURL $downloadURL -DownloadDestination $DownloadDestination

    $downloadedFile = Join-Path $DownloadDestination $downloadFileName

    if (-not (Test-Path $downloadedFile)) {
        throw "Downloaded file not found after transfer: $downloadedFile"
    }
    $downloadedSize = (Get-Item $downloadedFile).Length
    if ($downloadedSize -eq 0) {
        Remove-Item $downloadedFile -Force -ErrorAction SilentlyContinue
        throw "Downloaded file is empty (0 bytes): $downloadedFile"
    }
    $downloadedSizeMB = [math]::Round($downloadedSize / 1MB, 2)
    Write-DATLogEntry -Value "[$OEM] Download complete: $downloadedFile ($downloadedSizeMB MB)" -Severity 1

    # Download supplemental GFX package if present
    $supplementalFiles = @()
    if (-not [string]::IsNullOrEmpty($gfxDownloadURL)) {
        Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading $OEM $Model $gfxBrand GFX driver pack..." -Type String
        Write-DATLogEntry -Value "[$OEM] Starting GFX download: $gfxDownloadURL" -Severity 1

        Invoke-DATContentDownload -DownloadURL $gfxDownloadURL -DownloadDestination $DownloadDestination

        $gfxDownloadedFile = Join-Path $DownloadDestination $gfxDownloadFileName
        if (Test-Path $gfxDownloadedFile) {
            $gfxFileSize = (Get-Item $gfxDownloadedFile).Length
            if ($gfxFileSize -gt 0) {
                $gfxFileSizeMB = [math]::Round($gfxFileSize / 1MB, 2)
                Write-DATLogEntry -Value "[$OEM] GFX download complete: $gfxDownloadedFile ($gfxFileSizeMB MB)" -Severity 1
                $supplementalFiles += $gfxDownloadedFile
            } else {
                Write-DATLogEntry -Value "[Warning] - GFX download is empty (0 bytes): $gfxDownloadedFile" -Severity 2
                Remove-Item $gfxDownloadedFile -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-DATLogEntry -Value "[Warning] - GFX downloaded file not found: $gfxDownloadedFile" -Severity 2
        }
    }

    # Extract and package (unless Download Only mode)
    if ($RunningMode -ne "Download Only") {
        $packageDest = if (-not [string]::IsNullOrEmpty($PackageDestination)) { $PackageDestination } else { $DownloadDestination }
        # WIM Package Only uses the same packaging pipeline as ConfigMgr/Intune
        $packagingPlatform = if ($RunningMode -eq 'WIM Package Only') { 'WIM Package Only' } else { $RunningMode }
        $packagingParams = @{
            FilePath     = $downloadedFile
            OEM          = $OEM
            Model        = $Model
            OS           = "$WindowsVersion $WindowsBuild"
            Destination  = $packageDest
            Platform     = $packagingPlatform
        }
        if ($supplementalFiles.Count -gt 0) {
            $packagingParams['SupplementalFilePaths'] = $supplementalFiles
        }
        if (-not [string]::IsNullOrEmpty($CustomDriverPath)) {
            $packagingParams['CustomDriverPath'] = $CustomDriverPath
        }
        $null = Invoke-DATDriverFilePackaging @packagingParams
    }

    # Return the catalog version so callers can use it in pipeline metadata
    return $catalogVersion
}

#endregion Utility

#region Intune / Graph API

# Microsoft Graph public client ID for device code / interactive auth
$script:GraphClientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"  # Microsoft Graph PowerShell public client
$script:GraphScopes = @(
    "DeviceManagementApps.ReadWrite.All"
    "DeviceManagementManagedDevices.Read.All"
    "Group.Read.All"
)
$script:GraphBaseUrl = "https://graph.microsoft.com/beta"

# In-memory token store - discarded when the process exits
$script:IntuneAuthToken = $null
$script:IntuneTokenExpiry = [datetime]::MinValue
$script:IntuneTenantId = $null
$script:IntuneRefreshToken = $null

# Device code flow state - active only during sign-in
$script:DeviceCodeContext = $null

function ConvertTo-DATIntuneMinimumOS {
    <#
    .SYNOPSIS
        Converts a DAT OS string (e.g. "Windows 11 24H2") to the Graph API
        minimumOperatingSystem hashtable for Win32 LOB apps.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$OS
    )

    # Build a base object with all flags set to false
    $minOS = @{ "@odata.type" = "#microsoft.graph.windowsMinimumOperatingSystem" }

    # Map DAT OS strings to Graph API property names
    # OS format: "Windows 10 22H2", "Windows 11 24H2", etc.
    $mapped = switch -Regex ($OS) {
        'Windows\s+11.*26H2' { 'v11_26H2'; break }
        'Windows\s+11.*25H2' { 'v11_25H2'; break }
        'Windows\s+11.*24H2' { 'v11_24H2'; break }
        'Windows\s+11.*23H2' { 'v11_23H2'; break }
        'Windows\s+11.*22H2' { 'v11_22H2'; break }
        'Windows\s+11.*21H2' { 'v11_21H2'; break }
        'Windows\s+11'       { 'v11_21H2'; break }
        'Windows\s+10.*22H2' { 'v10_22H2'; break }
        'Windows\s+10.*21H2' { 'v10_21H2'; break }
        'Windows\s+10.*21H1' { 'v10_21H1'; break }
        'Windows\s+10.*20H2' { 'v10_20H2'; break }
        'Windows\s+10.*2004' { 'v10_2004'; break }
        'Windows\s+10.*1909' { 'v10_1909'; break }
        'Windows\s+10.*1903' { 'v10_1903'; break }
        'Windows\s+10'       { 'v10_1903'; break }
        default               { 'v10_1903' }
    }

    $minOS[$mapped] = $true
    Write-DATLogEntry -Value "[Intune] Minimum OS set to $mapped (from: $OS)" -Severity 1
    return $minOS
}

function Connect-DATIntuneGraph {
    <#
    .SYNOPSIS
        Initiates OAuth2 device code flow for Microsoft Graph authentication.
        Returns the device code details so the UI can display the user code.
        Call Complete-DATDeviceCodeAuth repeatedly (e.g. from a timer) to poll
        for completion. No local HTTP listener or background runspace required.
    .OUTPUTS
        Hashtable with UserCode, VerificationUri, ExpiresIn, Message.
    #>
    [CmdletBinding()]
    param ()

    $tenantEndpoint = "organizations"
    $scopeString = ($script:GraphScopes -join " ") + " openid profile offline_access"

    $deviceCodeUrl = "https://login.microsoftonline.com/$tenantEndpoint/oauth2/v2.0/devicecode"

    Write-DATLogEntry -Value "[Intune Auth] Requesting device code for interactive sign-in" -Severity 1

    try {
        $proxyParams = Get-DATWebRequestProxy
        $dcResponse = Invoke-RestMethod -Method POST -Uri $deviceCodeUrl -Body @{
            client_id = $script:GraphClientId
            scope     = $scopeString
        } -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop @proxyParams

        # Store context for polling
        $script:DeviceCodeContext = @{
            DeviceCode   = $dcResponse.device_code
            UserCode     = $dcResponse.user_code
            Interval     = [math]::Max([int]$dcResponse.interval, 5)
            ExpiresAt    = (Get-Date).AddSeconds([int]$dcResponse.expires_in)
        }

        Write-DATLogEntry -Value "[Intune Auth] Device code: $($dcResponse.user_code) - open $($dcResponse.verification_uri)" -Severity 1

        return @{
            Success         = $true
            UserCode        = $dcResponse.user_code
            VerificationUri = $dcResponse.verification_uri
            ExpiresIn       = [int]$dcResponse.expires_in
            Message         = $dcResponse.message
        }
    }
    catch {
        Write-DATLogEntry -Value "[Intune Auth] Device code request failed: $($_.Exception.Message)" -Severity 3
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Complete-DATDeviceCodeAuth {
    <#
    .SYNOPSIS
        Polls the token endpoint once for device code flow completion.
        Call this repeatedly from a DispatcherTimer at the interval returned
        by Connect-DATIntuneGraph.
    .OUTPUTS
        Hashtable - Status is 'Pending', 'Success', or 'Failed'.
    #>
    [CmdletBinding()]
    param ()

    if (-not $script:DeviceCodeContext) {
        return @{ Status = 'Failed'; Error = "No device code flow in progress." }
    }

    # Check expiry
    if ((Get-Date) -ge $script:DeviceCodeContext.ExpiresAt) {
        $script:DeviceCodeContext = $null
        Write-DATLogEntry -Value "[Intune Auth] Device code expired" -Severity 2
        return @{ Status = 'Failed'; Error = "Device code expired. Please try again." }
    }

    $tenantEndpoint = "organizations"
    $tokenUrl = "https://login.microsoftonline.com/$tenantEndpoint/oauth2/v2.0/token"

    try {
        $proxyParams = Get-DATWebRequestProxy
        $tokenResponse = Invoke-RestMethod -Method POST -Uri $tokenUrl -Body @{
            client_id   = $script:GraphClientId
            grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
            device_code = $script:DeviceCodeContext.DeviceCode
        } -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop @proxyParams

        # Success - store token
        $script:IntuneAuthToken = $tokenResponse.access_token
        $script:IntuneTokenExpiry = (Get-Date).AddSeconds([int]$tokenResponse.expires_in - 60)

        # Extract tenant ID from the JWT access token
        $tokenParts = $script:IntuneAuthToken.Split('.')
        $payload = $tokenParts[1]
        switch ($payload.Length % 4) {
            2 { $payload += '==' }
            3 { $payload += '=' }
        }
        $decodedPayload = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
        $tokenClaims = $decodedPayload | ConvertFrom-Json
        $script:IntuneTenantId = $tokenClaims.tid

        $script:DeviceCodeContext = $null
        Write-DATLogEntry -Value "[Intune Auth] Authentication successful - tenant: $($script:IntuneTenantId)" -Severity 1

        return @{
            Status    = 'Success'
            ExpiresOn = $script:IntuneTokenExpiry
            TenantId  = $script:IntuneTenantId
        }
    }
    catch {
        # Parse the OAuth error from the response body
        $errorCode = $null
        try {
            $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
            $errorCode = $errorBody.error
        } catch {}

        if ($errorCode -eq 'authorization_pending') {
            # User hasn't completed sign-in yet - keep polling
            return @{ Status = 'Pending' }
        }
        elseif ($errorCode -eq 'slow_down') {
            # Server asks us to slow down - increase interval
            $script:DeviceCodeContext.Interval = $script:DeviceCodeContext.Interval + 5
            return @{ Status = 'Pending' }
        }
        elseif ($errorCode -eq 'expired_token') {
            $script:DeviceCodeContext = $null
            Write-DATLogEntry -Value "[Intune Auth] Device code expired" -Severity 2
            return @{ Status = 'Failed'; Error = "Device code expired. Please try again." }
        }
        else {
            $errMsg = if ($errorBody.error_description) { $errorBody.error_description } else { $_.Exception.Message }
            $script:DeviceCodeContext = $null
            Write-DATLogEntry -Value "[Intune Auth] Token request failed: $errMsg" -Severity 3
            return @{ Status = 'Failed'; Error = $errMsg }
        }
    }
}

function Connect-DATIntuneGraphClientCredential {
    <#
    .SYNOPSIS
        Authenticates to Microsoft Graph using client credentials (App ID + Secret).
        This is a non-interactive flow for app registrations with application permissions.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$ClientSecret
    )

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    Write-DATLogEntry -Value "[Intune Auth] Authenticating with client credentials for tenant: $TenantId" -Severity 1

    try {
        $proxyParams = Get-DATWebRequestProxy
        $tokenResponse = Invoke-RestMethod -Method POST -Uri $tokenUrl -Body @{
            client_id     = $AppId
            client_secret = $ClientSecret
            scope         = "https://graph.microsoft.com/.default"
            grant_type    = "client_credentials"
        } -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop @proxyParams

        $script:IntuneAuthToken = $tokenResponse.access_token
        $script:IntuneTokenExpiry = (Get-Date).AddSeconds([int]$tokenResponse.expires_in - 60)
        $script:IntuneTenantId = $TenantId

        Write-DATLogEntry -Value "[Intune Auth] Client credential authentication successful - tenant: $TenantId" -Severity 1

        return @{
            Success   = $true
            ExpiresOn = $script:IntuneTokenExpiry
            TenantId  = $TenantId
        }
    }
    catch {
        Write-DATLogEntry -Value "[Intune Auth] Client credential auth failed: $($_.Exception.Message)" -Severity 3
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Connect-DATIntuneGraphInteractive {
    <#
    .SYNOPSIS
        Phase 1 of browser-based Auth Code + PKCE flow. Generates PKCE values,
        starts a localhost HTTP listener, opens the browser, and stores the
        async context for polling. Returns immediately -- the listener waits
        asynchronously. Call Complete-DATBrowserAuth from a DispatcherTimer to
        check for the redirect.
    .OUTPUTS
        Hashtable with Success, ListenerPort.
    #>
    [CmdletBinding()]
    param ()

    $scopeString = ($script:GraphScopes -join " ") + " openid profile offline_access"

    Write-DATLogEntry -Value "[Intune Auth] Starting interactive browser sign-in (Auth Code + PKCE)" -Severity 1

    try {
        # 1. Generate PKCE code verifier & challenge
        $codeVerifierBytes = [byte[]]::new(32)
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($codeVerifierBytes)
        $rng.Dispose()
        $codeVerifier = [Convert]::ToBase64String($codeVerifierBytes) -replace '\+', '-' -replace '/', '_' -replace '='

        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $challengeHash = $sha256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($codeVerifier))
        $sha256.Dispose()
        $codeChallenge = [Convert]::ToBase64String($challengeHash) -replace '\+', '-' -replace '/', '_' -replace '='

        # 2. Start a temporary HTTP listener on a random localhost port
        $port = Get-Random -Minimum 49152 -Maximum 65535
        $redirectUri = "http://localhost:$port/"
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add($redirectUri)
        $listener.Start()
        Write-DATLogEntry -Value "[Intune Auth] Listening on $redirectUri" -Severity 1

        # 3. Build the authorize URL with PKCE and CSRF state
        $state = [guid]::NewGuid().ToString('N')
        $authUrl = "https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize?" + (
            @(
                "client_id=$($script:GraphClientId)"
                "response_type=code"
                "redirect_uri=$([uri]::EscapeDataString($redirectUri))"
                "response_mode=query"
                "scope=$([uri]::EscapeDataString($scopeString))"
                "state=$state"
                "code_challenge=$codeChallenge"
                "code_challenge_method=S256"
                "prompt=select_account"
            ) -join '&'
        )

        # 4. Begin async listen before opening the browser
        $asyncResult = $listener.BeginGetContext($null, $null)

        # 5. Store context for polling by Complete-DATBrowserAuth
        $script:BrowserAuthContext = @{
            Listener     = $listener
            AsyncResult  = $asyncResult
            CodeVerifier = $codeVerifier
            State        = $state
            RedirectUri  = $redirectUri
            ScopeString  = $scopeString
            StartedAt    = Get-Date
            TimeoutSec   = 120
        }

        # 6. Open the browser (on the UI thread so shell association works)
        Write-DATLogEntry -Value "[Intune Auth] Opening browser for sign-in" -Severity 1
        Start-Process $authUrl

        return @{
            Success      = $true
            ListenerPort = $port
        }
    }
    catch {
        try { $listener.Stop(); $listener.Close() } catch {}
        Write-DATLogEntry -Value "[Intune Auth] Browser auth setup failed: $($_.Exception.Message)" -Severity 3
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Complete-DATBrowserAuth {
    <#
    .SYNOPSIS
        Phase 2 -- polls the HTTP listener once. Call from a DispatcherTimer.
        Returns Pending while waiting, Success or Failed when done.
    .OUTPUTS
        Hashtable -- Status is 'Pending', 'Success', or 'Failed'.
    #>
    [CmdletBinding()]
    param ()

    if (-not $script:BrowserAuthContext) {
        return @{ Status = 'Failed'; Error = "No browser auth flow in progress." }
    }

    $ctx = $script:BrowserAuthContext

    # Check timeout
    $elapsed = ((Get-Date) - $ctx.StartedAt).TotalSeconds
    if ($elapsed -ge $ctx.TimeoutSec) {
        try { $ctx.Listener.Stop(); $ctx.Listener.Close() } catch {}
        $script:BrowserAuthContext = $null
        Write-DATLogEntry -Value "[Intune Auth] Browser sign-in timed out after $($ctx.TimeoutSec) seconds" -Severity 3
        return @{ Status = 'Failed'; Error = "Browser sign-in timed out. Please try again." }
    }

    # Check if the browser has redirected back yet
    if (-not $ctx.AsyncResult.IsCompleted) {
        return @{ Status = 'Pending' }
    }

    # Redirect received -- process it
    try {
        $httpContext = $ctx.Listener.EndGetContext($ctx.AsyncResult)
        $query = $httpContext.Request.QueryString

        # Return a friendly page to the user
        $html = '<html><body style="font-family:Segoe UI,sans-serif;text-align:center;padding-top:60px"><h2>Authentication complete</h2><p>You can close this tab and return to Driver Automation Tool.</p></body></html>'
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
        $httpContext.Response.ContentLength64 = $buffer.Length
        $httpContext.Response.ContentType = "text/html"
        $httpContext.Response.OutputStream.Write($buffer, 0, $buffer.Length)
        $httpContext.Response.OutputStream.Close()
        $ctx.Listener.Stop()
        $ctx.Listener.Close()

        # Validate CSRF state
        if ($query['state'] -ne $ctx.State) {
            $script:BrowserAuthContext = $null
            Write-DATLogEntry -Value "[Intune Auth] State mismatch - possible CSRF attack" -Severity 3
            return @{ Status = 'Failed'; Error = "Authentication failed: state mismatch (CSRF protection)." }
        }
        if ($query['error']) {
            $script:BrowserAuthContext = $null
            $errorDesc = $query['error_description']
            Write-DATLogEntry -Value "[Intune Auth] Authorization error: $($query['error']) - $errorDesc" -Severity 3
            return @{ Status = 'Failed'; Error = "Authorization error: $errorDesc" }
        }
        $authCode = $query['code']

        # Exchange auth code + verifier for tokens
        $tokenUrl = "https://login.microsoftonline.com/organizations/oauth2/v2.0/token"
        $proxyParams = Get-DATWebRequestProxy
        $tokenResponse = Invoke-RestMethod -Method POST -Uri $tokenUrl -Body @{
            client_id     = $script:GraphClientId
            scope         = $ctx.ScopeString
            code          = $authCode
            redirect_uri  = $ctx.RedirectUri
            grant_type    = "authorization_code"
            code_verifier = $ctx.CodeVerifier
        } -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop @proxyParams

        # Store tokens in module scope
        $script:IntuneAuthToken   = $tokenResponse.access_token
        $script:IntuneTokenExpiry = (Get-Date).AddSeconds([int]$tokenResponse.expires_in - 60)
        $script:IntuneRefreshToken = $tokenResponse.refresh_token

        # Extract tenant ID from JWT
        $tokenParts = $script:IntuneAuthToken.Split('.')
        $payload = $tokenParts[1]
        switch ($payload.Length % 4) {
            2 { $payload += '==' }
            3 { $payload += '=' }
        }
        $decodedPayload = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload))
        $tokenClaims = $decodedPayload | ConvertFrom-Json
        $script:IntuneTenantId = $tokenClaims.tid

        $script:BrowserAuthContext = $null
        Write-DATLogEntry -Value "[Intune Auth] Interactive authentication successful - tenant: $($script:IntuneTenantId)" -Severity 1

        return @{ Status = 'Success' }
    }
    catch {
        try { $ctx.Listener.Stop(); $ctx.Listener.Close() } catch {}
        $script:BrowserAuthContext = $null
        Write-DATLogEntry -Value "[Intune Auth] Browser auth token exchange failed: $($_.Exception.Message)" -Severity 3
        return @{ Status = 'Failed'; Error = $_.Exception.Message }
    }
}

function Invoke-DATTokenRefresh {
    <#
    .SYNOPSIS
        Silently refreshes the access token using a stored refresh token.
        Called automatically before token expiry when interactive auth was used.
    .OUTPUTS
        Hashtable with Success, ExpiresOn.
    #>
    [CmdletBinding()]
    param ()

    if ([string]::IsNullOrEmpty($script:IntuneRefreshToken)) {
        return @{ Success = $false; Error = "No refresh token available." }
    }

    $scopeString = ($script:GraphScopes -join " ") + " openid profile offline_access"
    $tokenUrl = "https://login.microsoftonline.com/organizations/oauth2/v2.0/token"

    try {
        $proxyParams = Get-DATWebRequestProxy
        $tokenResponse = Invoke-RestMethod -Method POST -Uri $tokenUrl -Body @{
            client_id     = $script:GraphClientId
            scope         = $scopeString
            refresh_token = $script:IntuneRefreshToken
            grant_type    = "refresh_token"
        } -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop @proxyParams

        $script:IntuneAuthToken = $tokenResponse.access_token
        $script:IntuneTokenExpiry = (Get-Date).AddSeconds([int]$tokenResponse.expires_in - 60)
        # Refresh tokens may rotate -- always store the latest
        if ($tokenResponse.refresh_token) {
            $script:IntuneRefreshToken = $tokenResponse.refresh_token
        }

        Write-DATLogEntry -Value "[Intune Auth] Token refreshed silently - expires $($script:IntuneTokenExpiry)" -Severity 1
        return @{ Success = $true; ExpiresOn = $script:IntuneTokenExpiry }
    }
    catch {
        Write-DATLogEntry -Value "[Intune Auth] Token refresh failed: $($_.Exception.Message)" -Severity 2
        $script:IntuneRefreshToken = $null
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Test-DATIntunePermissions {
    <#
    .SYNOPSIS
        Checks if the authenticated user has the required Intune/Graph permissions
        by making test API calls.
    .OUTPUTS
        Hashtable with Granted (bool) and Permissions (array of permission results).
    #>
    [CmdletBinding()]
    param ()

    if (-not (Test-DATIntuneAuth)) {
        return @{ Granted = $false; Error = "Not authenticated"; Permissions = @() }
    }

    $headers = @{
        "Authorization" = "Bearer $($script:IntuneAuthToken)"
        "Content-Type"  = "application/json"
    }

    $permChecks = @(
        @{ Name = "DeviceManagementApps.ReadWrite.All"; TestUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$top=1"; Description = "Create and manage Win32 app packages" }
        @{ Name = "DeviceManagementManagedDevices.Read.All"; TestUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$top=1"; Description = "Read managed devices for model lookup" }
        @{ Name = "GroupMember.Read.All"; TestUri = "https://graph.microsoft.com/v1.0/groups?`$top=1"; Description = "Read group memberships for deployment targeting" }
    )

    $results = @()
    $allGranted = $true

    foreach ($perm in $permChecks) {
        try {
            $proxyParams = Get-DATWebRequestProxy
            Invoke-RestMethod -Method GET -Uri $perm.TestUri -Headers $headers -ErrorAction Stop @proxyParams | Out-Null
            $results += @{ Name = $perm.Name; Description = $perm.Description; Status = "Granted" }
            Write-DATLogEntry -Value "[Intune Auth] Permission check: $($perm.Name) - Granted" -Severity 1
        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            if ($statusCode -eq 403) {
                $results += @{ Name = $perm.Name; Description = $perm.Description; Status = "Denied" }
                $allGranted = $false
                Write-DATLogEntry -Value "[Intune Auth] Permission check: $($perm.Name) - Denied (403)" -Severity 2
            } elseif ($statusCode -eq 401) {
                $results += @{ Name = $perm.Name; Description = $perm.Description; Status = "Unauthorized" }
                $allGranted = $false
                Write-DATLogEntry -Value "[Intune Auth] Permission check: $($perm.Name) - Unauthorized (401)" -Severity 3
            } else {
                # Other errors (e.g. network) - treat as unknown
                $results += @{ Name = $perm.Name; Description = $perm.Description; Status = "Error" }
                $allGranted = $false
                Write-DATLogEntry -Value "[Intune Auth] Permission check: $($perm.Name) - Error: $($_.Exception.Message)" -Severity 3
            }
        }
    }

    return @{
        Granted     = $allGranted
        Permissions = $results
    }
}

function Test-DATIntuneAuth {
    <#
    .SYNOPSIS
        Checks whether the in-memory Intune token is still valid.
    #>
    [OutputType([bool])]
    param ()

    if ([string]::IsNullOrEmpty($script:IntuneAuthToken)) { return $false }
    if ((Get-Date) -ge $script:IntuneTokenExpiry) {
        Write-DATLogEntry -Value "[Intune Auth] Token expired - reauthentication required" -Severity 2
        $script:IntuneAuthToken = $null
        return $false
    }
    return $true
}

function Set-DATIntuneAuthToken {
    <#
    .SYNOPSIS
        Sets the in-memory Intune auth token from an external caller (e.g. background runspace).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][datetime]$ExpiresOn
    )
    $script:IntuneAuthToken = $Token
    $script:IntuneTokenExpiry = $ExpiresOn
}

function Disconnect-DATIntuneGraph {
    <#
    .SYNOPSIS
        Clears the in-memory Intune token.
    #>
    $script:IntuneAuthToken = $null
    $script:IntuneTokenExpiry = [datetime]::MinValue
    $script:IntuneTenantId = $null
    $script:IntuneRefreshToken = $null
    Write-DATLogEntry -Value "[Intune Auth] Disconnected - token discarded" -Severity 1
}

function Invoke-DATGraphRequest {
    <#
    .SYNOPSIS
        Makes an authenticated Graph API request with automatic pagination.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method = 'GET',
        [object]$Body,
        [string]$ContentType = "application/json",
        [switch]$NoPagination,
        [hashtable]$AdditionalHeaders
    )

    if (-not (Test-DATIntuneAuth)) {
        throw "Intune authentication required. Please authenticate first."
    }

    $headers = @{
        "Authorization" = "Bearer $($script:IntuneAuthToken)"
        "Content-Type"  = $ContentType
    }
    if ($AdditionalHeaders) {
        foreach ($key in $AdditionalHeaders.Keys) { $headers[$key] = $AdditionalHeaders[$key] }
    }

    # Build the full URL if relative
    $fullUri = if ($Uri -match '^https://') { $Uri } else { "$($script:GraphBaseUrl)/$($Uri.TrimStart('/'))" }

    $allResults = [System.Collections.ArrayList]::new()

    # Retry configuration for transient failures (5xx, 429)
    $maxRetries = 3
    $retryDelaySec = 5

    try {
        do {
            $splat = @{
                Method      = $Method
                Uri         = $fullUri
                Headers     = $headers
                ErrorAction = 'Stop'
            }
            if ($Body -and $Method -in @('POST', 'PATCH')) {
                $splat['Body'] = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
            }

            $proxyParams = Get-DATWebRequestProxy
            foreach ($key in $proxyParams.Keys) { $splat[$key] = $proxyParams[$key] }

            $response = $null
            for ($attempt = 1; $attempt -le ($maxRetries + 1); $attempt++) {
                try {
                    $response = Invoke-RestMethod @splat
                    break
                } catch {
                    $retryStatusCode = $null
                    if ($_.Exception.Response) {
                        $retryStatusCode = [int]$_.Exception.Response.StatusCode
                    }
                    $isTransient = $retryStatusCode -in @(429, 500, 502, 503, 504)

                    if ($isTransient -and $attempt -le $maxRetries) {
                        # Use Retry-After header if present (for 429), otherwise exponential backoff
                        $waitSec = $retryDelaySec * [math]::Pow(2, $attempt - 1)
                        if ($retryStatusCode -eq 429 -and $_.Exception.Response.Headers) {
                            try {
                                $retryAfter = $_.Exception.Response.Headers | Where-Object { $_.Key -eq 'Retry-After' } | Select-Object -ExpandProperty Value -First 1
                                if ($retryAfter) { $waitSec = [math]::Max([int]$retryAfter, 1) }
                            } catch { }
                        }
                        Write-DATLogEntry -Value "[Graph API] HTTP $retryStatusCode on $Method $Uri -- retry $attempt/$maxRetries in ${waitSec}s..." -Severity 2
                        Start-Sleep -Seconds $waitSec
                        continue
                    }
                    # Non-transient or retries exhausted -- rethrow for outer catch block
                    throw
                }
            }

            # Collect results
            if ($response.value) {
                foreach ($item in $response.value) {
                    [void]$allResults.Add($item)
                }
            }
            else {
                # Single object response (POST/PATCH/DELETE or single GET)
                return $response
            }

            # Pagination - follow @odata.nextLink
            $fullUri = $response.'@odata.nextLink'
        } while (-not $NoPagination -and $fullUri)

        return $allResults
    }
    catch {
        $statusCode = $null
        $responseBody = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            try {
                $responseStream = $_.Exception.Response.GetResponseStream()
                if ($responseStream) {
                    $reader = [System.IO.StreamReader]::new($responseStream)
                    $responseBody = $reader.ReadToEnd()
                    $reader.Dispose()
                    $responseStream.Dispose()
                }
            } catch {
                # Fallback for PS7+ HttpResponseMessage
                try {
                    $responseBody = $_.ErrorDetails.Message
                } catch { }
            }
        }
        if ([string]::IsNullOrEmpty($responseBody) -and $_.ErrorDetails.Message) {
            $responseBody = $_.ErrorDetails.Message
        }
        if ($statusCode -eq 401) {
            $script:IntuneAuthToken = $null
            Write-DATLogEntry -Value "[Graph API] 401 Unauthorized - token invalidated" -Severity 3
            throw "Authentication expired. Please re-authenticate."
        }
        Write-DATLogEntry -Value "[Graph API] Request failed ($Method $Uri): $($_.Exception.Message)" -Severity 3
        if ($responseBody) {
            Write-DATLogEntry -Value "[Graph API] Response body: $responseBody" -Severity 3
        }
        if ($Body -and $Method -in @('POST', 'PATCH')) {
            $bodyJson = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 }
            Write-DATLogEntry -Value "[Graph API] Request body: $bodyJson" -Severity 2
        }
        throw
    }
}

function Get-DATIntuneKnownModels {
    <#
    .SYNOPSIS
        Queries Microsoft Graph for managed devices and returns unique make/model combinations.
    .DESCRIPTION
        Paginates through all managed devices selecting manufacturer and model fields.
        Reports progress via a scriptblock callback.
    #>
    [CmdletBinding()]
    param (
        [Parameter()][scriptblock]$OnProgress,
        [Parameter()][string]$AuthToken,
        [Parameter()][string]$GraphBaseUrl
    )

    # Use provided token/URL or fall back to module-scoped values
    $token = if ($AuthToken) { $AuthToken } else { $script:IntuneAuthToken }
    $baseUrl = if ($GraphBaseUrl) { $GraphBaseUrl } else { $script:GraphBaseUrl }

    if ([string]::IsNullOrEmpty($token)) {
        throw "Intune authentication required. Please authenticate first."
    }

    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type"  = "application/json"
    }

    $uri = "$baseUrl/deviceManagement/managedDevices?`$select=manufacturer,model&`$filter=operatingSystem eq 'Windows'&`$top=999"
    $pageNumber = 0
    $devicePairs = [System.Collections.Generic.Dictionary[string, PSCustomObject]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if ($OnProgress) { & $OnProgress "Querying Graph..." }

    try {
        do {
            $pageNumber++
            if ($OnProgress) { & $OnProgress "Processing Page $pageNumber..." }

            $proxyParams = Get-DATWebRequestProxy
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ErrorAction Stop @proxyParams

            if ($response.value) {
                foreach ($device in $response.value) {
                    $mfr = if ($device.manufacturer) { $device.manufacturer.Trim() } else { $null }
                    $mdl = if ($device.model) { $device.model.Trim() } else { $null }
                    if ($mfr -and $mfr -ne '' -and $mfr -ne 'Unknown' -and $mdl -and $mdl -ne '' -and $mdl -ne 'Unknown') {
                        $key = "$mfr|$mdl"
                        if (-not $devicePairs.ContainsKey($key)) {
                            $devicePairs[$key] = [PSCustomObject]@{ Make = $mfr; Model = $mdl }
                        }
                    }
                }
            }

            if ($OnProgress) { & $OnProgress "Finding Unique Makes / Models... Discovered $($devicePairs.Count) unique combinations" }

            $uri = $response.'@odata.nextLink'
        } while ($uri)
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($statusCode -eq 401) {
            $script:IntuneAuthToken = $null
            Write-DATLogEntry -Value "[Graph API] 401 Unauthorized during known model lookup" -Severity 3
            throw "Authentication expired. Please re-authenticate."
        }
        Write-DATLogEntry -Value "[Graph API] Known model lookup failed: $($_.Exception.Message)" -Severity 3
        throw
    }

    $devices = @($devicePairs.Values | Sort-Object -Property Make, Model)
    $uniqueMakes = @($devices | Select-Object -ExpandProperty Make -Unique)
    $uniqueModels = @($devices | Select-Object -ExpandProperty Model -Unique)

    Write-DATLogEntry -Value "[Graph API] Known model lookup complete: $($uniqueMakes.Count) makes, $($uniqueModels.Count) models, $($devices.Count) unique combinations across $pageNumber pages" -Severity 1

    return [PSCustomObject]@{
        Makes   = [string[]]$uniqueMakes
        Models  = [string[]]$uniqueModels
        Devices = $devices
    }
}

function Get-DATIntuneWin32Apps {
    <#
    .SYNOPSIS
        Retrieves all Win32 LOB applications from Intune with full pagination.
    #>
    [CmdletBinding()]
    param ()

    return Invoke-DATGraphRequest -Uri "/deviceAppManagement/mobileApps?\`$filter=isof('microsoft.graph.win32LobApp')"
}

function Get-DATIntuneAppById {
    <#
    .SYNOPSIS
        Retrieves a single Intune Win32 app by ID.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$AppId)

    return Invoke-DATGraphRequest -Uri "/deviceAppManagement/mobileApps/$AppId"
}

function Remove-DATIntuneApp {
    <#
    .SYNOPSIS
        Deletes an Intune Win32 application.
    #>
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$AppId)

    Write-DATLogEntry -Value "[Intune] Deleting app $AppId" -Severity 1
    return Invoke-DATGraphRequest -Uri "/deviceAppManagement/mobileApps/$AppId" -Method DELETE
}

function Invoke-DATPackageRetention {
    <#
    .SYNOPSIS
        Removes superseded packages for a given make/model/OS from ConfigMgr and/or Intune,
        keeping up to $RetainCount older versions (newest first).
    .OUTPUTS
        Array of [pscustomobject] with properties: Platform, Name, Version, PackageId, Action, Error
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$OEM,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$OS,
        [string]$Architecture = 'x64',
        [ValidateSet('Drivers','BIOS')][string]$PackageType = 'Drivers',
        # How many previous versions to keep (0 = keep only newest/current)
        [int]$RetainCount = 0,
        # ConfigMgr: site server + site code (omit to skip CM cleanup)
        [string]$SiteServer,
        [string]$SiteCode,
        # Intune: pass $true to clean up Intune Win32 apps (requires valid Graph token)
        [switch]$Intune
    )

    $results = [System.Collections.Generic.List[pscustomobject]]::new()

    # --- ConfigMgr cleanup ---
    if ($SiteServer -and $SiteCode) {
        try {
            $smsNamespace = "root\SMS\Site_$SiteCode"
            $packagePrefix = if ($PackageType -eq 'BIOS') { 'BIOS Update' } else { 'Drivers' }
            $pkgName = if ($PackageType -eq 'BIOS') {
                "$packagePrefix - $OEM $Model"
            } else {
                "$packagePrefix - $OEM $Model - $OS $Architecture"
            }

            Write-DATLogEntry -Value "[Retention][CM] Querying superseded packages for: $pkgName" -Severity 1
            $wmiQuery = "SELECT PackageID, Name, Version FROM SMS_Package WHERE Name = '$($pkgName -replace "'","''")'"
            $allPkgs  = @(Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace -Query $wmiQuery -ErrorAction Stop)
            $sorted   = $allPkgs | Sort-Object -Property Version -Descending
            # Keep newest + $RetainCount previous; delete the rest
            $toDelete = if ($sorted.Count -gt ($RetainCount + 1)) { $sorted | Select-Object -Skip ($RetainCount + 1) } else { @() }

            foreach ($pkg in $toDelete) {
                Write-DATLogEntry -Value "[Retention][CM] Removing $($pkg.Name) v$($pkg.Version) ($($pkg.PackageID))" -Severity 1
                try {
                    Get-CimInstance -ComputerName $SiteServer -Namespace $smsNamespace `
                              -Query "SELECT * FROM SMS_Package WHERE PackageID = '$($pkg.PackageID)'" -ErrorAction Stop | Remove-CimInstance -ErrorAction Stop
                    $results.Add([pscustomobject]@{ Platform='ConfigMgr'; Name=$pkg.Name; Version=$pkg.Version; PackageId=$pkg.PackageID; Action='Deleted'; Error='' })
                } catch {
                    $results.Add([pscustomobject]@{ Platform='ConfigMgr'; Name=$pkg.Name; Version=$pkg.Version; PackageId=$pkg.PackageID; Action='Failed'; Error=$_.Exception.Message })
                }
            }
        } catch {
            Write-DATLogEntry -Value "[Retention][CM] Query error: $($_.Exception.Message)" -Severity 3
        }
    }

    # --- Intune cleanup ---
    if ($Intune) {
        try {
            $displayPrefix = if ($PackageType -eq 'BIOS') { 'BIOS' } else { 'Drivers' }
            # Intune display names: "<Prefix> - <OEM> <Model> - <OS> <Arch>" or just "<Prefix> - <OEM> <Model>" for BIOS
            $baseSearch = if ($PackageType -eq 'BIOS') {
                "$displayPrefix - $OEM $Model"
            } else {
                "$displayPrefix - $OEM $Model - $OS $Architecture"
            }

            Write-DATLogEntry -Value "[Retention][Intune] Querying Win32 apps matching: $baseSearch" -Severity 1
            $allApps = Get-DATIntuneWin32Apps -SearchString $baseSearch
            $sorted  = $allApps | Sort-Object -Property { $_.displayVersion } -Descending
            $toDelete = if ($sorted.Count -gt ($RetainCount + 1)) { $sorted | Select-Object -Skip ($RetainCount + 1) } else { @() }

            foreach ($app in $toDelete) {
                Write-DATLogEntry -Value "[Retention][Intune] Removing $($app.displayName) v$($app.displayVersion) ($($app.id))" -Severity 1
                try {
                    Remove-DATIntuneApp -AppId $app.id | Out-Null
                    $results.Add([pscustomobject]@{ Platform='Intune'; Name=$app.displayName; Version=$app.displayVersion; PackageId=$app.id; Action='Deleted'; Error='' })
                } catch {
                    $results.Add([pscustomobject]@{ Platform='Intune'; Name=$app.displayName; Version=$app.displayVersion; PackageId=$app.id; Action='Failed'; Error=$_.Exception.Message })
                }
            }
        } catch {
            Write-DATLogEntry -Value "[Retention][Intune] Query error: $($_.Exception.Message)" -Severity 3
        }
    }

    return $results.ToArray()
}

function Search-DATEntraGroups {
    <#
    .SYNOPSIS
        Searches Entra ID groups by display name using Microsoft Graph.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$SearchText,
        [int]$MaxResults = 25
    )

    if ([string]::IsNullOrWhiteSpace($SearchText) -or $SearchText.Length -lt 2) {
        return @()
    }

    # Sanitise the search term for OData -- escape single quotes
    $safe = $SearchText.Replace("'", "''")
    $uri = "/groups?`$filter=startswith(displayName,'$safe')&`$select=id,displayName,description,groupTypes,mailEnabled,securityEnabled&`$top=$MaxResults&`$orderby=displayName&`$count=true"
    $results = Invoke-DATGraphRequest -Uri $uri -NoPagination -AdditionalHeaders @{ 'ConsistencyLevel' = 'eventual' }
    return $results
}

function Set-DATIntuneAppAssignment {
    <#
    .SYNOPSIS
        Creates a group assignment for an Intune Win32 app (Available or Required).
        Supports regular groups, All Users, and All Devices.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][ValidateSet('Available', 'Required')][string]$Intent
    )

    $intentMap = @{
        'Available' = 'available'
        'Required'  = 'required'
    }

    # Determine the assignment target based on the group ID
    $allUsersId  = 'acacacac-9df4-4c7d-9d50-4ef0226f57a9'
    $allDevicesId = 'adadadad-808e-44e2-905a-0b7873a8a531'

    $target = switch ($GroupId) {
        $allUsersId {
            @{ "@odata.type" = "#microsoft.graph.allLicensedUsersAssignmentTarget" }
        }
        $allDevicesId {
            @{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget" }
        }
        default {
            @{
                "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                groupId       = $GroupId
            }
        }
    }

    $body = @{
        mobileAppAssignments = @(
            @{
                "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                intent        = $intentMap[$Intent]
                target        = $target
                settings      = @{
                    "@odata.type"       = "#microsoft.graph.win32LobAppAssignmentSettings"
                    notifications       = "showAll"
                    installTimeSettings = $null
                    restartSettings     = $null
                    deliveryOptimizationPriority = "notConfigured"
                }
            }
        )
    }

    Write-DATLogEntry -Value "[Intune] Assigning app $AppId to group $GroupId as $Intent" -Severity 1
    return Invoke-DATGraphRequest -Uri "/deviceAppManagement/mobileApps/$AppId/assign" -Method POST -Body $body
}

function New-DATIntuneToastScript {
    <#
    .SYNOPSIS
        Generates the Show-ToastNotification.ps1 script that displays a WPF toast
        notification to the logged-in user during Intune driver/BIOS installations.
        This script runs in the user's interactive session via a scheduled task.

        UpdateType values:
          Drivers - Pending driver update prompt   (Update Now / Remind Me Later)
          BIOS    - Pending BIOS update prompt     (Update Now / Remind Me Later)
          Success - Driver update succeeded        (Close only -- Drivers only)
          Issues  - Update encountered errors      (Close only)
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$OutputPath,
        [ValidateSet('Drivers','BIOS','Success','BIOSSuccess','Issues','BIOSIssues')][string]$UpdateType = 'Drivers',
        [string]$BrandingPath = '',
        [string]$CustomBrandingImagePath = '',
        [string]$CustomToastTitle = '',
        [string]$CustomToastBody = ''
    )

    # Determine layout type and per-type content
    $isStatusType = $UpdateType -in @('Success', 'BIOSSuccess', 'Issues', 'BIOSIssues')

    switch ($UpdateType) {
        'BIOS' {
            $heading = if (-not [string]::IsNullOrEmpty($CustomToastTitle)) { $CustomToastTitle } else { 'BIOS Update Pending' }
            $body    = if (-not [string]::IsNullOrEmpty($CustomToastBody))  { $CustomToastBody  } else { 'Your device has pending updates which are required for security / stability reasons. Pressing the Update button will trigger a restart of your device. DO NOT power off the device during the update process.' }
        }
        'BIOSSuccess' {
            $heading        = 'BIOS Firmware Prestaged'
            $body           = 'Your system has a pending BIOS update and will be restarted in 180 seconds. Please save your work. Do NOT power off the device during the update process.'
            $statusIcon     = '&#xE835;'   # FirmwareUpdate (Segoe MDL2 Assets)
            $iconColor      = '#3B82F6'    # blue-500
            $accentColor    = '#2563EB'    # blue-600
            $iconBackground = '#172554'    # blue-950
        }
        'Success' {
            $heading        = 'Drivers Successfully Updated'
            $body           = 'Your device drivers have been successfully updated. No restart is required unless indicated by your IT department.'
            $statusIcon     = '&#xE930;'   # CompletedSolid (Segoe MDL2 Assets)
            $iconColor      = '#22C55E'    # green-500
            $accentColor    = '#16A34A'    # green-600
            $iconBackground = '#052e16'    # green-950
        }
        'Issues' {
            $heading        = 'Driver Update Issues Detected'
            $body           = 'One or more driver updates encountered errors during installation. Please contact your IT department or check the device logs for details.'
            $statusIcon     = '&#xE7BA;'   # Warning (Segoe MDL2 Assets)
            $iconColor      = '#F59E0B'    # amber-500
            $accentColor    = '#D97706'    # amber-600
            $iconBackground = '#451a03'    # amber-950
        }
        'BIOSIssues' {
            $heading        = 'BIOS Update Issues Detected'
            $body           = 'The BIOS firmware update encountered errors during installation. Please contact your IT department or check the device logs for details.'
            $statusIcon     = '&#xE7BA;'   # Warning (Segoe MDL2 Assets)
            $iconColor      = '#F59E0B'    # amber-500
            $accentColor    = '#D97706'    # amber-600
            $iconBackground = '#451a03'    # amber-950
        }
        default {
            $heading = if (-not [string]::IsNullOrEmpty($CustomToastTitle)) { $CustomToastTitle } else { 'Driver Updates Pending' }
            $body    = if (-not [string]::IsNullOrEmpty($CustomToastBody))  { $CustomToastBody  } else { 'Your device has pending updates which are required for security / stability reasons. Pressing the Update button can result in temporary network or display interruption.' }
        }
    }

    # Read module version from manifest for embedding in generated scripts
    $moduleManifest = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'DriverAutomationToolCore.psd1') -ErrorAction SilentlyContinue
    $scriptVersion = if ($moduleManifest.ModuleVersion) { $moduleManifest.ModuleVersion } else { 'Unknown' }
    $buildTimestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $scriptContent = @"
<#
    Driver Automation Tool - Toast Notification Script
    Update Type : $UpdateType
    Version     : $scriptVersion
    Built       : $buildTimestamp
    This script is executed under the signed-in user's session via a scheduled task
    to present update notifications. The result is written to a shared file that
    the SYSTEM-context install script monitors.
#>

# --- Toast Script Build Info ---
`$DATToastVersion   = '$scriptVersion'
`$DATToastBuildTime = '$buildTimestamp'
`$DATToastType      = '$UpdateType'

# --- Toast Debug Logging ---
`$toastLogPath = Join-Path `$env:ProgramData 'DriverAutomationTool\DAT_Toast.log'
function Write-ToastLog {
    param([string]`$Message, [string]`$Severity = 'INFO')
    try {
        `$logDir = Split-Path `$toastLogPath -Parent
        if (-not (Test-Path `$logDir)) { New-Item -Path `$logDir -ItemType Directory -Force | Out-Null }
        `$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        "`$timestamp [`$Severity] [PID:`$PID] `$Message" | Out-File -FilePath `$toastLogPath -Encoding UTF8 -Append
    } catch { }
}

Write-ToastLog "============================================"
Write-ToastLog "Toast script starting"
Write-ToastLog "  Version    : `$DATToastVersion"
Write-ToastLog "  Built      : `$DATToastBuildTime"
Write-ToastLog "  Type       : `$DATToastType"
Write-ToastLog "  User       : `$env:USERNAME"
Write-ToastLog "  Session    : `$([System.Diagnostics.Process]::GetCurrentProcess().SessionId)"
Write-ToastLog "  PS Version : `$(`$PSVersionTable.PSVersion)"
Write-ToastLog "  64-bit     : `$([Environment]::Is64BitProcess)"
Write-ToastLog "  STA        : `$([System.Threading.Thread]::CurrentThread.GetApartmentState())"
Write-ToastLog "============================================"

# --- Verbose environment diagnostics ---
try {
    `$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if (`$osInfo) {
        Write-ToastLog "[ENV] OS Caption    : `$(`$osInfo.Caption)"
        Write-ToastLog "[ENV] OS Build      : `$(`$osInfo.BuildNumber)"
        Write-ToastLog "[ENV] OS Version    : `$(`$osInfo.Version)"
    }
} catch { Write-ToastLog "[ENV] OS query failed: `$(`$_.Exception.Message)" 'WARN' }

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    `$screens = [System.Windows.Forms.Screen]::AllScreens
    `$primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen
    Write-ToastLog "[ENV] Display count : `$(`$screens.Count)"
    Write-ToastLog "[ENV] Primary screen: `$(`$primaryScreen.Bounds.Width) x `$(`$primaryScreen.Bounds.Height)"
    Write-ToastLog "[ENV] Working area  : `$(`$primaryScreen.WorkingArea.Width) x `$(`$primaryScreen.WorkingArea.Height) (Bottom: `$(`$primaryScreen.WorkingArea.Bottom))"
    `$dpi = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX
    Write-ToastLog "[ENV] DPI scaling   : `$dpi"
} catch { Write-ToastLog "[ENV] Display/DPI query failed: `$(`$_.Exception.Message)" 'WARN' }

try {
    # Focus Assist / Quiet Hours state
    # 0 = Off, 1 = Priority Only, 2 = Alarms Only
    `$focusAssistVal = (Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default`$windows.data.notifications.quiethourssettings\windows.data.notifications.quiethourssettings' -Name 'Data' -ErrorAction SilentlyContinue)
    if (`$null -ne `$focusAssistVal) {
        Write-ToastLog "[ENV] Focus Assist registry key found (quiet hours settings present)" 'WARN'
    } else {
        Write-ToastLog "[ENV] Focus Assist registry key not found (Focus Assist likely Off)"
    }
    `$focusAssistMode = (Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings' -Name 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' -ErrorAction SilentlyContinue)
    if (`$null -ne `$focusAssistMode) {
        Write-ToastLog "[ENV] Toasts enabled (NOC_GLOBAL_SETTING_TOASTS_ENABLED): `$(`$focusAssistMode.NOC_GLOBAL_SETTING_TOASTS_ENABLED)"
    } else {
        Write-ToastLog "[ENV] NOC_GLOBAL_SETTING_TOASTS_ENABLED not set (default -- toasts enabled)"
    }
} catch { Write-ToastLog "[ENV] Focus Assist query failed: `$(`$_.Exception.Message)" 'WARN' }

try {
    `$transcriptPath = Join-Path `$env:ProgramData 'DriverAutomationTool\DAT_Toast_Transcript.log'
    Start-Transcript -Path `$transcriptPath -Append -Force | Out-Null
    Write-ToastLog "[ENV] PowerShell transcript started: `$transcriptPath"
} catch { Write-ToastLog "[ENV] Transcript start failed: `$(`$_.Exception.Message)" 'WARN' }
Write-ToastLog "============================================"

try {
    Write-ToastLog "Loading WPF assemblies..."
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Write-ToastLog "WPF assemblies loaded successfully"
} catch {
    Write-ToastLog "FATAL: Failed to load WPF assemblies -- `$(`$_.Exception.Message)" 'ERROR'
    Write-ToastLog "Stack trace: `$(`$_.ScriptStackTrace)" 'ERROR'
    exit 1
}
"@

    # Append Focus Assist / DND pre-check to the shared script content.
    # Uses SHQueryUserNotificationState (shell32.dll) to detect if Focus Assist,
    # fullscreen apps, or presentation mode would prevent the toast from rendering.
    # Although WPF windows are not suppressed by Focus Assist, we respect the user's
    # DND preference and skip the toast. State 5 (QUNS_ACCEPTS_NOTIFICATIONS) is the
    # only state where we proceed.
    $focusAssistBlock = @'

# --- Focus Assist / DND Pre-check ---
try {
    $focusAssistCSharp = 'using System; using System.Runtime.InteropServices; public class DATFocusAssist { [DllImport("shell32.dll")] public static extern int SHQueryUserNotificationState(out int state); }'
    Add-Type -TypeDefinition $focusAssistCSharp -ErrorAction SilentlyContinue

    $focusState = 0
    [void][DATFocusAssist]::SHQueryUserNotificationState([ref]$focusState)
    $focusStateNames = @{
        1 = 'QUNS_NOT_PRESENT'
        2 = 'QUNS_BUSY'
        3 = 'QUNS_RUNNING_D3D_FULL_SCREEN'
        4 = 'QUNS_PRESENTATION_MODE'
        5 = 'QUNS_ACCEPTS_NOTIFICATIONS'
        6 = 'QUNS_QUIET_TIME'
        7 = 'QUNS_APP'
    }
    $focusStateName = if ($focusStateNames.ContainsKey($focusState)) { $focusStateNames[$focusState] } else { "Unknown ($focusState)" }
    Write-ToastLog "[FocusAssist] SHQueryUserNotificationState returned: $focusState ($focusStateName)"

    if ($focusState -ne 5) {
        Write-ToastLog "[FocusAssist] Notifications blocked (state: $focusStateName) -- skipping toast to respect DND preference" 'WARN'
        # For interactive toasts, write a fallback result so the install script applies its timeout action
        if ($DATToastType -in @('Drivers','BIOS')) {
            $focusResultPath = Join-Path $env:ProgramData 'DriverAutomationTool\DAT_ToastResult.txt'
            $focusResultDir = Split-Path $focusResultPath -Parent
            if (-not (Test-Path $focusResultDir)) { New-Item -Path $focusResultDir -ItemType Directory -Force | Out-Null }
            'Timeout' | Out-File -FilePath $focusResultPath -Encoding UTF8 -Force
            Write-ToastLog "[FocusAssist] Wrote fallback result 'Timeout' -- install script will apply configured timeout action"
        }
        try { Stop-Transcript } catch {}
        exit 0
    }
    Write-ToastLog "[FocusAssist] Notifications accepted -- proceeding with toast display"
} catch {
    Write-ToastLog "[FocusAssist] Pre-check failed: $($_.Exception.Message) -- proceeding with toast display" 'WARN'
}
'@
    $scriptContent += "`n" + $focusAssistBlock

    if ($isStatusType) {
        # ── Status toast (Success / Issues) ─────────────────────────────────────
        # Layout: coloured accent strip + icon circle + heading + body + Close button
        # No hero image required; no user action decision needed.

        $statusXamlTop = @'
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Driver Automation Tool" Width="420" SizeToContent="Height"
        WindowStartupLocation="Manual" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent"
        Topmost="True" ResizeMode="NoResize" ShowInTaskbar="False"
        Left="-9999" Top="-9999">
    <Border CornerRadius="12" Background="#0F172A" Margin="10"
'@
        $statusXamlDynamic = @"
            BorderBrush="$accentColor" BorderThickness="1">
        <Border.Effect>
            <DropShadowEffect BlurRadius="20" Opacity="0.5" ShadowDepth="4"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="4"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <!-- Accent strip -->
            <Border Grid.Row="0" CornerRadius="11,11,0,0" Background="$accentColor"/>
            <!-- Icon + text -->
            <StackPanel Grid.Row="1" HorizontalAlignment="Center" Margin="24,28,24,16">
                <Border Width="68" Height="68" CornerRadius="34" Background="$iconBackground"
                        HorizontalAlignment="Center" Margin="0,0,0,16">
                    <TextBlock Text="$statusIcon" FontFamily="Segoe MDL2 Assets" FontSize="34"
                               Foreground="$iconColor"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <TextBlock Text="$heading" FontSize="18" FontWeight="Bold"
                           Foreground="#F8FAFC" HorizontalAlignment="Center"
                           TextAlignment="Center" TextWrapping="Wrap" Margin="0,0,0,10"/>
                <TextBlock TextWrapping="Wrap" FontSize="13" Foreground="#CBD5E1"
                           HorizontalAlignment="Center" TextAlignment="Center"
                           LineHeight="20">$body</TextBlock>
            </StackPanel>
"@
        $statusCloseButton = @'
            <!-- Close Button -->
            <Grid Grid.Row="2" Margin="24,0,24,20">
                <Button x:Name="btnClose" Content="Close"
                        Height="40" Width="160" FontSize="14" FontWeight="SemiBold"
                        HorizontalAlignment="Center"
                        Foreground="#F8FAFC" Cursor="Hand" BorderThickness="0">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="bd" CornerRadius="8" Background="#334155" Padding="16,8"
                                    BorderBrush="#475569" BorderThickness="1">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="bd" Property="Background" Value="#475569"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </Grid>
        </Grid>
    </Border>
</Window>
"@
'@
        $statusEventBlock = @'

try {
    Write-ToastLog "Parsing XAML for status toast..."
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    Write-ToastLog "XAML parsed -- window object created successfully"
} catch {
    Write-ToastLog "FATAL: Failed to parse XAML -- $($_.Exception.Message)" 'ERROR'
    if ($_.Exception.InnerException) {
        Write-ToastLog "Inner exception: $($_.Exception.InnerException.Message)" 'ERROR'
    }
    Write-ToastLog "Stack trace: $($_.ScriptStackTrace)" 'ERROR'
    exit 1
}

try {
    # Position at bottom-right of the working area (above the taskbar) once rendered
    $window.Add_ContentRendered({
        $workArea = [System.Windows.SystemParameters]::WorkArea
        $this.Left = $workArea.Right - $this.ActualWidth - 20
        $this.Top  = $workArea.Bottom - $this.ActualHeight - 20
    })

    $window.FindName('btnClose').Add_Click({ $window.Close() })

    Write-ToastLog "Showing status toast dialog..."
    $window.ShowDialog() | Out-Null
    Write-ToastLog "Status toast dialog closed by user"
} catch {
    Write-ToastLog "FATAL: Failed to display status toast -- $($_.Exception.Message)" 'ERROR'
    if ($_.Exception.InnerException) {
        Write-ToastLog "Inner exception: $($_.Exception.InnerException.Message)" 'ERROR'
    }
    Write-ToastLog "Stack trace: $($_.ScriptStackTrace)" 'ERROR'
    try { Stop-Transcript } catch {}
    exit 1
}
try { Stop-Transcript } catch {}
'@
        $fullScript = $scriptContent + "`n" + $statusXamlTop + $statusXamlDynamic + $statusCloseButton + $statusEventBlock

    } else {
        # ── Update toast (Drivers / BIOS) ────────────────────────────────────────
        # Layout: hero banner + personalised greeting + two action buttons

        # Convert branding image to Base64 so it can be embedded and dropped on the client
        # Prefer custom branding image if provided, otherwise fall back to default
        $localLogoPath = $null
        if (-not [string]::IsNullOrEmpty($CustomBrandingImagePath) -and (Test-Path $CustomBrandingImagePath)) {
            $localLogoPath = $CustomBrandingImagePath
            Write-DATLogEntry -Value "[Toast] Using custom branding image: $CustomBrandingImagePath" -Severity 1
        } else {
            if ([string]::IsNullOrEmpty($BrandingPath)) {
                $BrandingPath = if ($global:ScriptDirectory) {
                    Join-Path $global:ScriptDirectory 'Branding'
                } else {
                    Join-Path $PSScriptRoot '..\..\Branding'
                }
            }
            $defaultLogoPath = Join-Path $BrandingPath 'DATLogo_Wide.png'
            if (Test-Path $defaultLogoPath) { $localLogoPath = $defaultLogoPath }
        }
        if ($localLogoPath -and (Test-Path $localLogoPath)) {
            $logoBytes  = [System.IO.File]::ReadAllBytes($localLogoPath)
            $logoBase64 = [Convert]::ToBase64String($logoBytes)
        } else {
            $logoBase64 = ""
        }

        $imageDropBlock = @"
`$logoBase64 = '$logoBase64'
try {
    if (-not [string]::IsNullOrEmpty(`$logoBase64)) {
        Write-ToastLog "Decoding and writing branding logo..."
        `$imgBytes = [Convert]::FromBase64String(`$logoBase64)
        `$imgPath = Join-Path `$env:ProgramData "DriverAutomationTool\DATLogo_Wide.png"
        if (-not (Test-Path `$imgPath)) {
            [System.IO.File]::WriteAllBytes(`$imgPath, `$imgBytes)
            Write-ToastLog "Logo written to `$imgPath"
        } else {
            Write-ToastLog "Logo already exists at `$imgPath"
        }
    } else {
        Write-ToastLog "No branding logo embedded in script" 'WARN'
    }
} catch {
    Write-ToastLog "WARNING: Failed to write branding logo -- `$(`$_.Exception.Message)" 'WARN'
}
"@

        $xamlContent = @'
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Driver Automation Tool" Width="460" SizeToContent="Height"
        WindowStartupLocation="Manual" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent"
        Topmost="True" ResizeMode="NoResize" ShowInTaskbar="False"
        Left="-9999" Top="-9999">
    <Border CornerRadius="12" Background="#0F172A" Margin="10"
            BorderBrush="#334155" BorderThickness="1">
        <Border.Effect>
            <DropShadowEffect BlurRadius="20" Opacity="0.5" ShadowDepth="4"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="110"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Hero Banner -->
            <Border Grid.Row="0" CornerRadius="12,12,0,0">
                <Border.Background>
                    <ImageBrush ImageSource="$env:ProgramData\DriverAutomationTool\DATLogo_Wide.png" Stretch="UniformToFill"/>
                </Border.Background>
            </Border>

            <!-- Body Content -->
'@

        $bodyXaml = @"
            <StackPanel Grid.Row="1" Margin="24,20,24,16">
                <TextBlock x:Name="txtGreeting" Text="Hi User" FontSize="16" Foreground="#F8FAFC"
                           FontWeight="SemiBold" Margin="0,0,0,2"/>
                <TextBlock Text="Driver Automation Tool V10" FontSize="12"
                           Foreground="#CBD5E1" Margin="0,0,0,16"/>
                <TextBlock Text="$heading" FontSize="20" FontWeight="Bold"
                           Foreground="#F8FAFC" Margin="0,0,0,10"/>
                <TextBlock TextWrapping="Wrap" FontSize="13" Foreground="#CBD5E1"
                           LineHeight="20">$body</TextBlock>
            </StackPanel>
"@

        $buttonsXaml = @'

            <!-- Action Buttons -->
            <Grid Grid.Row="2" Margin="24,0,24,20">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Button x:Name="btnUpdate" Grid.Column="0" Content="Update Now"
                        Height="40" FontSize="14" FontWeight="SemiBold"
                        Foreground="#FFFFFF" Cursor="Hand" BorderThickness="0">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="bd" CornerRadius="8" Background="#0B84F1" Padding="16,8">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="bd" Property="Background" Value="#3B82F6"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
                <Button x:Name="btnSnooze" Grid.Column="2" Content="Remind Me Later"
                        Height="40" FontSize="14" FontWeight="SemiBold"
                        Foreground="#F8FAFC" Cursor="Hand" BorderThickness="0">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="bd" CornerRadius="8" Background="#334155" Padding="16,8"
                                    BorderBrush="#475569" BorderThickness="1">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="bd" Property="Background" Value="#475569"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </Grid>
        </Grid>
    </Border>
</Window>
"@
'@

        $eventHandlerBlock = @'

try {
    Write-ToastLog "Parsing XAML for update toast..."
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $window.Tag = 'Pending'
    Write-ToastLog "XAML parsed -- window object created successfully"
} catch {
    Write-ToastLog "FATAL: Failed to parse XAML -- $($_.Exception.Message)" 'ERROR'
    if ($_.Exception.InnerException) {
        Write-ToastLog "Inner exception: $($_.Exception.InnerException.Message)" 'ERROR'
    }
    Write-ToastLog "Stack trace: $($_.ScriptStackTrace)" 'ERROR'
    exit 1
}

try {
    # Resolve the signed-in user's display name
    Write-ToastLog "Resolving display name..."
    $displayName = try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $samParts = $identity.Name -split '\\'
        $samName = $samParts[-1]
        Write-ToastLog "SAM account name: $samName"
        # Prefer AD lookup -- givenName/sn are always separate, avoiding concatenated names
        $adName = $null
        try {
            $searcher = [adsisearcher]"(samAccountName=$samName)"
            $searcher.PropertiesToLoad.AddRange(@('givenName','sn','displayName'))
            $adResult = $searcher.FindOne()
            if ($adResult) {
                $givenName = ($adResult.Properties['givenName'] | Select-Object -First 1) -as [string]
                $sn = ($adResult.Properties['sn'] | Select-Object -First 1) -as [string]
                $adDisplayName = ($adResult.Properties['displayName'] | Select-Object -First 1) -as [string]
                if (-not [string]::IsNullOrWhiteSpace($givenName) -and -not [string]::IsNullOrWhiteSpace($sn)) {
                    $adName = "$givenName $sn"
                } elseif (-not [string]::IsNullOrWhiteSpace($adDisplayName)) {
                    $adName = $adDisplayName
                }
                Write-ToastLog "AD lookup result: givenName='$givenName' sn='$sn' displayName='$adDisplayName'"
            }
        } catch {
            Write-ToastLog "AD lookup unavailable: $($_.Exception.Message)" 'WARN'
        }
        if (-not [string]::IsNullOrWhiteSpace($adName)) {
            $adName
        } else {
            # Fallback to WMI
            $userObj = Get-CimInstance -ClassName Win32_UserAccount -Filter "Name='$samName'" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($userObj -and -not [string]::IsNullOrWhiteSpace($userObj.FullName)) { $userObj.FullName } else { $samName }
        }
    } catch {
        Write-ToastLog "Display name lookup failed: $($_.Exception.Message)" 'WARN'
        'User'
    }
    Write-ToastLog "Greeting user as: $displayName"

    $window.FindName('txtGreeting').Text = "Hi $displayName"

    # Position at bottom-right of the working area (above the taskbar) once rendered
    $window.Add_ContentRendered({
        $workArea = [System.Windows.SystemParameters]::WorkArea
        $this.Left = $workArea.Right - $this.ActualWidth - 20
        $this.Top  = $workArea.Bottom - $this.ActualHeight - 20
    })

    $window.FindName('btnUpdate').Add_Click({
        $window.Tag = 'Update'
        $window.Close()
    })
    $window.FindName('btnSnooze').Add_Click({
        $window.Tag = 'Snooze'
        $window.Close()
    })

    # Prepare result file path for the Closing handler
    $resultPath = Join-Path $env:ProgramData 'DriverAutomationTool\DAT_ToastResult.txt'

    # Write result on window Closing -- fires regardless of how the window is closed
    # (user click, DispatcherTimer auto-close, or external process termination).
    # This ensures the Install script always sees a result file.
    $window.Add_Closing({
        $timer.Stop()
        try {
            $resultDir = Split-Path $resultPath -Parent
            if (-not (Test-Path $resultDir)) { New-Item -Path $resultDir -ItemType Directory -Force | Out-Null }
            $window.Tag | Out-File -FilePath $resultPath -Encoding UTF8 -Force
            Write-ToastLog "Result written on window close -- value: $($window.Tag)"
        } catch {
            Write-ToastLog "Failed to write result on close: $($_.Exception.Message)" 'ERROR'
        }
    })

    # Auto-close timer -- closes the window after 300 seconds if the user doesn't respond
    $autoCloseSeconds = 300
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds($autoCloseSeconds)
    $timer.Add_Tick({
        Write-ToastLog "Auto-close timer expired ($autoCloseSeconds seconds) -- closing window"
        $timer.Stop()
        $window.Tag = 'Timeout'
        $window.Close()
    })
    $timer.Start()
    Write-ToastLog "Auto-close timer started ($autoCloseSeconds seconds)"

    Write-ToastLog "Showing update toast dialog..."
    $window.ShowDialog() | Out-Null
    Write-ToastLog "Update toast dialog closed -- result: $($window.Tag)"
} catch {
    Write-ToastLog "FATAL: Failed to display update toast -- $($_.Exception.Message)" 'ERROR'
    if ($_.Exception.InnerException) {
        Write-ToastLog "Inner exception: $($_.Exception.InnerException.Message)" 'ERROR'
    }
    Write-ToastLog "Stack trace: $($_.ScriptStackTrace)" 'ERROR'
    # Write a fallback result file so the install script doesn't hang waiting
    try {
        $resultPath = Join-Path $env:ProgramData 'DriverAutomationTool\DAT_ToastResult.txt'
        $resultDir = Split-Path $resultPath -Parent
        if (-not (Test-Path $resultDir)) { New-Item -Path $resultDir -ItemType Directory -Force | Out-Null }
        'Timeout' | Out-File -FilePath $resultPath -Encoding UTF8 -Force
        Write-ToastLog "Fallback result 'Timeout' written after exception"
    } catch { }
    try { Stop-Transcript } catch {}
    exit 1
}
try { Stop-Transcript } catch {}
'@
        $fullScript = $scriptContent + "`n" + $imageDropBlock + "`n" + $xamlContent + $bodyXaml + $buttonsXaml + $eventHandlerBlock
    }

    [System.IO.File]::WriteAllText($OutputPath, $fullScript, [System.Text.UTF8Encoding]::new($false))
    Write-DATLogEntry -Value "[Intune] Toast notification script generated: $OutputPath (Type: $UpdateType)" -Severity 1
    return $OutputPath
}

function New-DATIntuneInstallScript {
    <#
    .SYNOPSIS
        Generates a PowerShell install script that expands a WIM file and installs drivers via PNPUtil.
        Reads from the Install-Drivers.ps1 template and replaces {{TOKEN}} placeholders.
        Optionally injects a WPF toast notification gate for interactive user sessions.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$OEM,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$OS,
        [Parameter(Mandatory)][string]$Version,
        [ValidateSet('Drivers','BIOS')][string]$UpdateType = 'Drivers',
        [switch]$DisableToast,
        [ValidateSet('RemindMeLater','InstallNow')][string]$ToastTimeoutAction = 'RemindMeLater',
        [int]$MaxDeferrals = 0
    )

    # Select the correct template based on update type
    $templateName = if ($UpdateType -eq 'BIOS') { 'Install-BIOS.ps1' } else { 'Install-Drivers.ps1' }
    $templatePath = Join-Path $PSScriptRoot "Templates\$templateName"
    if (-not (Test-Path $templatePath)) {
        throw "$templateName template not found at: $templatePath"
    }

    # Read the template
    $scriptContent = Get-Content -Path $templatePath -Raw

    # Build toast notification block -- omitted when $DisableToast is set
    if ($DisableToast) {
        $toastBlock = ''
        $toastFunctions = ''
    } else {
        $toastBlock = @'

    # --- Toast Notification Gate ---
    # Scheduled tasks are launched by the 64-bit Task Scheduler service, so we
    # must always specify the real System32 path (Sysnative is a virtual folder
    # visible only to 32-bit processes and does not exist from the task engine).
    $ps64 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $is64 = [Environment]::Is64BitProcess
    Write-CMTraceLog "PowerShell architecture: $(if ($is64) { '64-bit' } else { '32-bit (WOW64)' }) -- scheduled task host: $ps64"

    $snoozeRegPath = 'HKLM:\SOFTWARE\DriverAutomationTool\Toast'
    $maxDeferrals  = {{MAX_DEFERRALS}}
    $forceInstall  = $false
    if (-not (Test-Path $snoozeRegPath)) {
        New-Item -Path $snoozeRegPath -Force | Out-Null
    }

    # Check whether the maximum deferral limit has been reached (when tracking is enabled)
    if ($maxDeferrals -gt 0) {
        $rawDeferralCount = (Get-ItemProperty -Path $snoozeRegPath -Name 'DeferralCount' -ErrorAction SilentlyContinue).DeferralCount
        [int]$currentDeferralCount = if ($null -ne $rawDeferralCount) { $rawDeferralCount } else { 0 }
        Write-CMTraceLog "Deferral count: $currentDeferralCount / $maxDeferrals"
        if ($currentDeferralCount -ge $maxDeferrals) {
            Write-CMTraceLog "Maximum deferrals ($maxDeferrals) reached -- forcing update and resetting deferral counter"
            Remove-ItemProperty -Path $snoozeRegPath -Name 'DeferralCount' -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $snoozeRegPath -Name 'SnoozeUntil'   -Force -ErrorAction SilentlyContinue
            $forceInstall = $true
        }
    }

    if ($forceInstall) {
        Write-CMTraceLog "Proceeding with forced BIOS installation (maximum deferrals reached)"
    } else {
        $snoozeUntil = (Get-ItemProperty -Path $snoozeRegPath -Name 'SnoozeUntil' -ErrorAction SilentlyContinue).SnoozeUntil
        if ($snoozeUntil) {
            try {
                $snoozeTime = [datetime]::Parse($snoozeUntil)
                if ((Get-Date) -lt $snoozeTime) {
                    Write-CMTraceLog "Snooze active until $snoozeUntil -- exiting without action"
                    exit 0
                } else {
                    Write-CMTraceLog "Snooze expired ($snoozeUntil) -- continuing with installation"
                    Remove-ItemProperty -Path $snoozeRegPath -Name 'SnoozeUntil' -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-CMTraceLog "Invalid snooze timestamp -- clearing and continuing" -Severity 2
                Remove-ItemProperty -Path $snoozeRegPath -Name 'SnoozeUntil' -Force -ErrorAction SilentlyContinue
            }
        }

        # Detect if an interactive user is signed in
        $explorerProc = Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($explorerProc) {
            Write-CMTraceLog "Interactive user detected -- showing toast notification"

            # Copy toast script to persistent location -- IMECache can be purged at any time
            $toastPersistDir = Join-Path $env:ProgramData 'DriverAutomationTool'
            if (-not (Test-Path $toastPersistDir)) { New-Item -Path $toastPersistDir -ItemType Directory -Force | Out-Null }
            $toastScriptSource = Join-Path $ScriptDir "Show-ToastNotification.ps1"
            if (-not (Test-Path $toastScriptSource)) {
                Write-CMTraceLog "WARNING: Toast script not found at $toastScriptSource -- proceeding silently" -Severity 2
            } else {
                $toastScriptPath = Join-Path $toastPersistDir "Show-ToastNotification.ps1"
                Copy-Item -Path $toastScriptSource -Destination $toastScriptPath -Force
                Write-CMTraceLog "Copied toast script to persistent path: $toastScriptPath"
                $toastResultFile = Join-Path $env:ProgramData 'DriverAutomationTool\DAT_ToastResult.txt'
                if (Test-Path $toastResultFile) { Remove-Item $toastResultFile -Force }

                # Get the logged-on user -- query explorer.exe process owner (reliable under SYSTEM)
                $loggedOnUser = $null
                try {
                    $explorerWmi = Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" -ErrorAction Stop | Select-Object -First 1
                    if ($explorerWmi) {
                        $owner = Invoke-CimMethod -InputObject $explorerWmi -MethodName GetOwner -ErrorAction Stop
                        if ($owner.ReturnValue -eq 0 -and -not [string]::IsNullOrEmpty($owner.User)) {
                            $loggedOnUser = "$($owner.Domain)\$($owner.User)"
                        }
                    }
                } catch {
                    Write-CMTraceLog "Explorer process owner query failed: $($_.Exception.Message)" -Severity 2
                }
                # Fallback to Win32_ComputerSystem if process owner query failed
                if ([string]::IsNullOrEmpty($loggedOnUser)) {
                    $loggedOnUser = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
                }
                if ([string]::IsNullOrEmpty($loggedOnUser)) {
                    Write-CMTraceLog "Could not determine logged-on user -- proceeding silently" -Severity 2
                } else {
                    Write-CMTraceLog "Running toast notification as $loggedOnUser"

                    # Create a scheduled task to run the toast UI in the user's interactive session
                    $taskName = 'User Toast Notification'
                    $taskFolder = '\Driver Automation Tool'
                    $taskAction = New-ScheduledTaskAction -Execute $ps64 `
                        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File `"$toastScriptPath`""
                    $taskPrincipal = New-ScheduledTaskPrincipal -UserId $loggedOnUser -LogonType Interactive -RunLevel Limited
                    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                        -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

                    Write-CMTraceLog "Registering scheduled task '$taskFolder\$taskName' -- Execute: $ps64"
                    Unregister-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                    try {
                        Register-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -Action $taskAction -Principal $taskPrincipal `
                            -Settings $taskSettings -Force | Out-Null
                        Start-ScheduledTask -TaskPath $taskFolder -TaskName $taskName
                        Write-CMTraceLog "Scheduled task '$taskFolder\$taskName' started successfully"
                    } catch {
                        Write-CMTraceLog "Failed to register/start toast task: $($_.Exception.Message)" -Severity 3
                    }

                    # Wait for the user to respond (up to 5 minutes)
                    # NOTE: The scheduled task fires powershell.exe and then the task
                    # itself transitions to Ready/completes almost immediately.  We must
                    # track the actual toast PowerShell *process* (by PID) rather than
                    # the task state -- otherwise the wait loop exits after the first
                    # 10-second check and treats a still-visible toast as a timeout.
                    $waitTimeout = 300
                    $waited = 0
                    $taskExitedEarly = $false

                    # Discover the toast process PID spawned by the scheduled task.
                    # The task launches powershell.exe with the toast script path -- look
                    # for processes whose command line contains the persistent script path.
                    Start-Sleep -Seconds 3
                    $waited += 3
                    $toastProc = $null
                    try {
                        $toastProc = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
                            Where-Object { $_.CommandLine -and $_.CommandLine -match 'Show-ToastNotification' } |
                            Select-Object -First 1
                        if ($toastProc) {
                            Write-CMTraceLog "Toast process found: PID $($toastProc.ProcessId)"
                        } else {
                            Write-CMTraceLog "Toast process not found via WMI -- will track result file only" -Severity 2
                        }
                    } catch {
                        Write-CMTraceLog "WMI process query failed: $($_.Exception.Message) -- will track result file only" -Severity 2
                    }
                    $toastPid = if ($toastProc) { $toastProc.ProcessId } else { $null }

                    while ($waited -lt $waitTimeout) {
                        Start-Sleep -Seconds 2
                        $waited += 2
                        if (Test-Path $toastResultFile) { break }

                        # Check if the toast process is still running
                        $processAlive = $false
                        if ($null -ne $toastPid) {
                            $processAlive = [bool](Get-Process -Id $toastPid -ErrorAction SilentlyContinue)
                        } else {
                            # No PID captured -- fall back to checking for any toast process
                            $processAlive = [bool](Get-Process -Name 'powershell' -ErrorAction SilentlyContinue |
                                Where-Object { try { (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine -match 'Show-ToastNotification' } catch { $false } } |
                                Select-Object -First 1)
                        }

                        # Log state periodically for diagnostics
                        if ($waited % 30 -eq 0) {
                            Write-CMTraceLog "Toast wait ${waited}s -- process alive: $processAlive"
                        }

                        # Only break if the toast process has exited AND no result file appeared
                        if (-not $processAlive -and -not (Test-Path $toastResultFile)) {
                            Write-CMTraceLog "Toast process (PID: $toastPid) exited without result file at ${waited}s" -Severity 2
                            $taskExitedEarly = $true
                            break
                        }
                    }

                    # Read toast debug log if available for diagnostics
                    $toastDebugLog = Join-Path $env:ProgramData 'DriverAutomationTool\DAT_Toast.log'
                    if (Test-Path $toastDebugLog) {
                        $toastDebugContent = Get-Content $toastDebugLog -Tail 20 -ErrorAction SilentlyContinue
                        if ($toastDebugContent) {
                            Write-CMTraceLog "[ToastDebug] Last entries from toast script log (exited early: $taskExitedEarly, waited: ${waited}s):"
                            foreach ($line in $toastDebugContent) {
                                Write-CMTraceLog "[ToastDebug] $line"
                            }
                        }
                    }

                    # Clean up
                    Unregister-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

                    if (Test-Path $toastResultFile) {
                        $toastResult = (Get-Content $toastResultFile -Raw).Trim()
                        Remove-Item -Path $toastResultFile -Force -ErrorAction SilentlyContinue
                        Write-CMTraceLog "Toast result: $toastResult"

                        if ($toastResult -in @('Snooze','Timeout')) {
                            # Snooze = user clicked Remind Me Later
                            # Timeout = auto-close timer expired (300s) or toast process exited early
                            $isAutoTimeout = ($toastResult -eq 'Timeout')

                            # Check configured timeout action for auto-timeouts
                            if ($isAutoTimeout -and '{{TOAST_TIMEOUT_ACTION}}' -ne 'RemindMeLater') {
                                Write-CMTraceLog "Toast auto-closed after ${waited}s -- proceeding with installation (Auto Install on timeout)" -Severity 2
                            } else {
                                # Increment deferral counter if tracking is active
                                if ($maxDeferrals -gt 0) {
                                    $rawCount  = (Get-ItemProperty -Path $snoozeRegPath -Name 'DeferralCount' -ErrorAction SilentlyContinue).DeferralCount
                                    [int]$prev = if ($null -ne $rawCount) { $rawCount } else { 0 }
                                    Set-ItemProperty -Path $snoozeRegPath -Name 'DeferralCount' -Value ($prev + 1) -Type DWord -Force
                                    Write-CMTraceLog "Deferral count incremented to $($prev + 1) / $maxDeferrals"
                                }
                                $snoozeExpiry = (Get-Date).AddHours(4).ToString('o')
                                Set-ItemProperty -Path $snoozeRegPath -Name 'SnoozeUntil' -Value $snoozeExpiry -Force
                                if ($isAutoTimeout) {
                                    Write-CMTraceLog "Toast auto-closed after ${waited}s -- snoozed until $snoozeExpiry (Remind Me Later on timeout)"
                                } else {
                                    Write-CMTraceLog "User chose Remind Me Later -- rescheduled until $snoozeExpiry"
                                }
                                exit 0
                            }
                        } elseif ($toastResult -eq 'Update') {
                            Write-CMTraceLog "User chose Update Now -- proceeding with installation"
                        } else {
                            Write-CMTraceLog "Unexpected toast result: $toastResult -- proceeding" -Severity 2
                        }
                    } else {
                        Write-CMTraceLog "Toast process exited without result file (waited ${waited}s of ${waitTimeout}s) -- check DAT_Toast.log for Focus Assist state" -Severity 2
                        if ('{{TOAST_TIMEOUT_ACTION}}' -eq 'RemindMeLater') {
                            # Treat timeout as Remind Me Later -- increment deferral counter if tracking is active
                            if ($maxDeferrals -gt 0) {
                                $rawCount  = (Get-ItemProperty -Path $snoozeRegPath -Name 'DeferralCount' -ErrorAction SilentlyContinue).DeferralCount
                                [int]$prev = if ($null -ne $rawCount) { $rawCount } else { 0 }
                                Set-ItemProperty -Path $snoozeRegPath -Name 'DeferralCount' -Value ($prev + 1) -Type DWord -Force
                            Write-CMTraceLog "Toast process exited without result (deferral) -- count incremented to $($prev + 1) / $maxDeferrals"
                            }
                            $snoozeExpiry = (Get-Date).AddHours(4).ToString('o')
                            Set-ItemProperty -Path $snoozeRegPath -Name 'SnoozeUntil' -Value $snoozeExpiry -Force
                            Write-CMTraceLog "Toast process exited without result -- snoozed until $snoozeExpiry (Remind Me Later on no result)"
                            exit 0
                        } else {
                            Write-CMTraceLog "Toast process exited without result -- proceeding with installation (Auto Install on no result)" -Severity 2
                        }
                    }
                }
            }
        } else {
            Write-CMTraceLog "No interactive user session detected -- proceeding silently"
        }
    }
    # --- End Toast Notification Gate ---
'@
        # Bake the timeout action and max deferral count into the generated script
        $toastBlock = $toastBlock.Replace('{{TOAST_TIMEOUT_ACTION}}', $ToastTimeoutAction)
        $toastBlock = $toastBlock.Replace('{{MAX_DEFERRALS}}', [string]$MaxDeferrals)
    }

    # Build status toast blocks (Success on completion, Issues on error)
    $statusToastBlock = ''
    $statusToastErrorBlock = ''
    if (-not $DisableToast) {
        # Reusable function that launches a toast script in the user's interactive session
        $statusToastFunction = @'

function Show-DATStatusToast {
    param ([string]$ToastScript)
    # Always use System32 -- Task Scheduler is 64-bit; Sysnative doesn't exist from its context
    $ps64 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $is64 = [Environment]::Is64BitProcess
    Write-CMTraceLog "[StatusToast] PowerShell architecture: $(if ($is64) { '64-bit' } else { '32-bit (WOW64)' }) -- scheduled task host: $ps64"
    $explorerProc = Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $explorerProc) {
        Write-CMTraceLog "No interactive user session -- skipping status toast"
        return
    }
    if (-not (Test-Path $ToastScript)) {
        Write-CMTraceLog "Status toast script not found: $ToastScript" -Severity 2
        return
    }
    # Copy toast script to persistent location -- IMECache can be purged at any time
    $toastPersistDir = Join-Path $env:ProgramData 'DriverAutomationTool'
    if (-not (Test-Path $toastPersistDir)) { New-Item -Path $toastPersistDir -ItemType Directory -Force | Out-Null }
    $persistedScript = Join-Path $toastPersistDir (Split-Path $ToastScript -Leaf)
    Copy-Item -Path $ToastScript -Destination $persistedScript -Force
    Write-CMTraceLog "[StatusToast] Copied toast script to persistent path: $persistedScript"
    $ToastScript = $persistedScript
    # Get the logged-on user -- query explorer.exe process owner (reliable under SYSTEM)
    $loggedOnUser = $null
    try {
        $explorerWmi = Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" -ErrorAction Stop | Select-Object -First 1
        if ($explorerWmi) {
            $owner = Invoke-CimMethod -InputObject $explorerWmi -MethodName GetOwner -ErrorAction Stop
            if ($owner.ReturnValue -eq 0 -and -not [string]::IsNullOrEmpty($owner.User)) {
                $loggedOnUser = "$($owner.Domain)\$($owner.User)"
            }
        }
    } catch {
        Write-CMTraceLog "Explorer process owner query failed: $($_.Exception.Message)" -Severity 2
    }
    if ([string]::IsNullOrEmpty($loggedOnUser)) {
        $loggedOnUser = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
    }
    if ([string]::IsNullOrEmpty($loggedOnUser)) {
        Write-CMTraceLog "Could not determine logged-on user -- skipping status toast" -Severity 2
        return
    }
    Write-CMTraceLog "Showing status toast to $loggedOnUser"
    try {
        $taskName = 'User Toast Notification'
        $taskFolder = '\Driver Automation Tool'
        $taskAction = New-ScheduledTaskAction -Execute $ps64 `
            -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File `"$ToastScript`""
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId $loggedOnUser -LogonType Interactive -RunLevel Limited
        $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
        Write-CMTraceLog "[StatusToast] Registering task '$taskFolder\$taskName' -- Execute: $ps64"
        Write-CMTraceLog "[StatusToast] Toast script: $ToastScript"
        Unregister-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -Action $taskAction -Principal $taskPrincipal `
            -Settings $taskSettings -Force | Out-Null
        Start-ScheduledTask -TaskPath $taskFolder -TaskName $taskName
        $taskState = (Get-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -ErrorAction SilentlyContinue).State
        Write-CMTraceLog "[StatusToast] Task started -- state: $taskState"
        # Brief delay then clean up the task registration (toast is already running)
        Start-Sleep -Seconds 5
        $taskStateAfter = (Get-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -ErrorAction SilentlyContinue).State
        $taskInfoObj = Get-ScheduledTaskInfo -TaskPath $taskFolder -TaskName $taskName -ErrorAction SilentlyContinue
        $lastResult = if ($taskInfoObj) { "0x{0:X}" -f $taskInfoObj.LastTaskResult } else { 'N/A' }
        Write-CMTraceLog "[StatusToast] After 5s wait -- state: $taskStateAfter, last result: $lastResult"

        # Read toast debug log if available
        $toastDebugLog = Join-Path $env:ProgramData 'DriverAutomationTool\DAT_Toast.log'
        if (Test-Path $toastDebugLog) {
            $toastDebugContent = Get-Content $toastDebugLog -Tail 15 -ErrorAction SilentlyContinue
            if ($toastDebugContent) {
                Write-CMTraceLog "[StatusToast] Toast debug log entries:"
                foreach ($line in $toastDebugContent) {
                    Write-CMTraceLog "[StatusToast][Debug] $line"
                }
            }
        }

        Unregister-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    } catch {
        Write-CMTraceLog "Failed to show status toast: $($_.Exception.Message)" -Severity 2
    }
}
'@
        $statusToastBlock = if ($UpdateType -eq 'BIOS') {
            @"

    # --- Show BIOS Prestaged Status Toast ---
    if (-not `$WhatIf) {
        `$biosSuccessToastScript = Join-Path `$ScriptDir "Show-StatusToast-BIOSSuccess.ps1"
        Show-DATStatusToast -ToastScript `$biosSuccessToastScript
    }
"@
        } else {
            @"

    # --- Show Success Status Toast ---
    if (-not `$WhatIf) {
        `$successToastScript = Join-Path `$ScriptDir "Show-StatusToast-Success.ps1"
        Show-DATStatusToast -ToastScript `$successToastScript
    }
"@
        }
        $statusToastErrorBlock = if ($UpdateType -eq 'BIOS') {
            @"

    # --- Show BIOS Issues Status Toast ---
    `$biosIssuesScript = Join-Path `$ScriptDir "Show-StatusToast-BIOSIssues.ps1"
    Show-DATStatusToast -ToastScript `$biosIssuesScript
"@
        } else {
            @"

    # --- Show Issues Status Toast ---
    `$issuesScript = Join-Path `$ScriptDir "Show-StatusToast-Issues.ps1"
    Show-DATStatusToast -ToastScript `$issuesScript
"@
        }
        # Place the helper function BEFORE the try block (PS 5.1 compatibility --
        # function definitions inside try{} cause MissingCatchOrFinally parse errors)
        $toastFunctions = $statusToastFunction
        # Toast gate code stays inside the try block
    }

    # Replace template tokens (use literal .Replace() -- NOT -replace -- because the
    # toast blocks contain $_ which .NET regex interprets as "entire input string")
    $scriptContent = $scriptContent.Replace('{{OEM}}', $OEM)
    $scriptContent = $scriptContent.Replace('{{Model}}', $Model)
    $scriptContent = $scriptContent.Replace('{{OS}}', $OS)
    $scriptContent = $scriptContent.Replace('{{Version}}', $Version)
    $scriptContent = $scriptContent.Replace('{{Generated}}', (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
    $scriptContent = $scriptContent.Replace('{{TOAST_FUNCTIONS}}', $toastFunctions)
    $scriptContent = $scriptContent.Replace('{{TOAST_BLOCK}}', $toastBlock)
    $scriptContent = $scriptContent.Replace('{{STATUS_TOAST_BLOCK}}', $statusToastBlock)
    $scriptContent = $scriptContent.Replace('{{STATUS_TOAST_ERROR_BLOCK}}', $statusToastErrorBlock)

    [System.IO.File]::WriteAllText($OutputPath, $scriptContent, [System.Text.UTF8Encoding]::new($false))
    Write-DATLogEntry -Value "[Intune] Install script generated: $OutputPath (Toast: $(if ($DisableToast) { 'Disabled' } else { 'Enabled' }))" -Severity 1
    return $OutputPath
}

function New-DATIntuneRequirementScript {
    <#
    .SYNOPSIS
        Generates a requirement rule script that checks:
        - Device manufacturer matches the OEM
        - WMI SystemSKU or Baseboard Product matches one of the model's values
        - OS matches the target OS (Drivers only -- BIOS packages are OS-agnostic)
        - Package version is newer than any previously installed version (ddMMyyyy comparison)
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$OEM,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Baseboards,
        [Parameter(Mandatory)][string]$OS,
        [Parameter(Mandatory)][string]$Version,
        [ValidateSet('Drivers','BIOS')][string]$UpdateType = 'Drivers'
    )

    # Parse OS version (Windows 10/11)
    $osNumber = if ($OS -match 'Windows\s+(\d+)') { $Matches[1] } else { "11" }

    # Build the baseboard values array - split on commas and trim
    $bbValues = ($Baseboards -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) -join "','"

    # Determine registry sub-key and whether to include OS check
    $regSubKey = if ($UpdateType -eq 'BIOS') { 'BIOS' } else { 'Drivers' }
    $osCheckBlock = if ($UpdateType -eq 'BIOS') {
        @'
    # BIOS packages are OS-agnostic -- OS check skipped
'@
    } else {
        @"
    # Check 3: OS version must match
    `$osCaption = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption
    if (`$osCaption -notmatch "Windows $osNumber") {
        Write-Output "OS mismatch: got '`$osCaption', expected 'Windows $osNumber'"
        exit 0
    }
"@
    }

    $scriptContent = @'
<#
    Driver Automation Tool - Requirement Script
    OEM: {0}
    Model: {1}
    OS: {2}
    Version: {3}
    UpdateType: {7}
    Generated: {5}

    Returns JSON output for Intune requirement rule evaluation.
    Output must contain a property that Intune can evaluate.
#>

$RequirementMet = $false

try {{
    # Check 1: Manufacturer must match OEM
    $manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Manufacturer
    $expectedOEM = "{0}"

    $oemMatch = $false
    switch ($expectedOEM) {{
        "HP"        {{ $oemMatch = ($manufacturer -match "HP|Hewlett-Packard") }}
        "Dell"      {{ $oemMatch = ($manufacturer -match "Dell") }}
        "Lenovo"    {{ $oemMatch = ($manufacturer -match "Lenovo") }}
        "Microsoft" {{ $oemMatch = ($manufacturer -match "Microsoft") }}
        "Acer"      {{ $oemMatch = ($manufacturer -match "Acer") }}
        default     {{ $oemMatch = ($manufacturer -match $expectedOEM) }}
    }}

    if (-not $oemMatch) {{
        Write-Output "Manufacturer mismatch: got '$manufacturer', expected '$expectedOEM'"
        exit 0
    }}

    # Check 2: SystemSKU or Baseboard Product must match
    $systemSKU = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).SystemSKUNumber
    $baseboardProduct = (Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop).Product
    $expectedValues = @('{4}')

    $skuMatch = $false
    foreach ($val in $expectedValues) {{
        if ($systemSKU -eq $val -or $baseboardProduct -eq $val) {{
            $skuMatch = $true
            break
        }}
    }}

    if (-not $skuMatch) {{
        Write-Output "SKU/Baseboard mismatch: SKU='$systemSKU', Board='$baseboardProduct', Expected=@('{4}')"
        exit 0
    }}

{8}
    # Check 4: Version check - registry-based installed version
    $packageVersion = "{3}"
    $regPath = "HKLM:\SOFTWARE\DriverAutomationTool\{9}\{0}\{1}"

    if (Test-Path $regPath) {{
        $installedVer = (Get-ItemProperty -Path $regPath -Name 'Version' -ErrorAction SilentlyContinue).Version
        if (-not [string]::IsNullOrEmpty($installedVer)) {{
            try {{
                $pkgDay = [int]$packageVersion.Substring(0, 2)
                $pkgMonth = [int]$packageVersion.Substring(2, 2)
                $pkgYear = [int]$packageVersion.Substring(4, 4)
                $pkgDate = [datetime]::new($pkgYear, $pkgMonth, $pkgDay)

                $instDay = [int]$installedVer.Substring(0, 2)
                $instMonth = [int]$installedVer.Substring(2, 2)
                $instYear = [int]$installedVer.Substring(4, 4)
                $instDate = [datetime]::new($instYear, $instMonth, $instDay)

                if ($pkgDate -le $instDate) {{
                    Write-Output "Version not newer: package=$packageVersion, installed=$installedVer"
                    exit 0
                }}
            }} catch {{ }}
        }}
    }}

    # All checks passed
    $RequirementMet = $true
}}
catch {{
    Write-Output "Requirement check error: $($_.Exception.Message)"
    exit 0
}}

if ($RequirementMet) {{
    Write-Output "Requirement met"
}} else {{
    Write-Output "Requirement not met"
}}
'@ -f $OEM, $Model, $OS, $Version, $bbValues, (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $osNumber, $UpdateType, $osCheckBlock, $regSubKey

    [System.IO.File]::WriteAllText($OutputPath, $scriptContent, [System.Text.UTF8Encoding]::new($false))
    Write-DATLogEntry -Value "[Intune] Requirement script generated: $OutputPath (UpdateType: $UpdateType)" -Severity 1
    return $OutputPath
}

function New-DATIntuneDetectionScript {
    <#
    .SYNOPSIS
        Generates a detection rule script that checks:
        - Device manufacturer matches the OEM
        - WMI SystemSKU or Baseboard Product matches one of the model's values
        - OS matches the target OS (Drivers only -- BIOS packages are OS-agnostic)
        - Installed version matches the package version exactly
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$OEM,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Baseboards,
        [Parameter(Mandatory)][string]$OS,
        [Parameter(Mandatory)][string]$Version,
        [ValidateSet('Drivers','BIOS')][string]$UpdateType = 'Drivers'
    )

    $osNumber = if ($OS -match 'Windows\s+(\d+)') { $Matches[1] } else { "11" }
    $bbValues = ($Baseboards -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) -join "','"

    # Determine registry sub-key and whether to include OS check
    $regSubKey = if ($UpdateType -eq 'BIOS') { 'BIOS' } else { 'Drivers' }
    $detectionLabel = if ($UpdateType -eq 'BIOS') { 'BIOS' } else { 'drivers' }
    $osCheckBlock = if ($UpdateType -eq 'BIOS') {
        @'
    # BIOS packages are OS-agnostic -- OS check skipped
'@
    } else {
        @"
    # Check 3: OS version match
    `$osCaption = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption
    if (`$osCaption -notmatch "Windows $osNumber") { exit 0 }
"@
    }

    $scriptContent = @'
<#
    Driver Automation Tool - Detection Script
    OEM: {0}
    Model: {1}
    OS: {2}
    Version: {3}
    UpdateType: {7}
    Generated: {5}

    Exits 0 with STDOUT = app detected (installed).
    Exits 0 with no STDOUT = app not detected (not installed).
#>

try {{
    # Check 1: Manufacturer match
    $manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Manufacturer
    $expectedOEM = "{0}"

    $oemMatch = $false
    switch ($expectedOEM) {{
        "HP"        {{ $oemMatch = ($manufacturer -match "HP|Hewlett-Packard") }}
        "Dell"      {{ $oemMatch = ($manufacturer -match "Dell") }}
        "Lenovo"    {{ $oemMatch = ($manufacturer -match "Lenovo") }}
        "Microsoft" {{ $oemMatch = ($manufacturer -match "Microsoft") }}
        "Acer"      {{ $oemMatch = ($manufacturer -match "Acer") }}
        default     {{ $oemMatch = ($manufacturer -match $expectedOEM) }}
    }}

    if (-not $oemMatch) {{ exit 0 }}

    # Check 2: SystemSKU or Baseboard Product match
    $systemSKU = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).SystemSKUNumber
    $baseboardProduct = (Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop).Product
    $expectedValues = @('{4}')

    $skuMatch = $false
    foreach ($val in $expectedValues) {{
        if ($systemSKU -eq $val -or $baseboardProduct -eq $val) {{
            $skuMatch = $true
            break
        }}
    }}

    if (-not $skuMatch) {{ exit 0 }}

{8}
    # Check 4: Version marker in registry
    $regPath = "HKLM:\SOFTWARE\DriverAutomationTool\{9}\{0}\{1}"
    if (Test-Path $regPath) {{
        $installedVersion = (Get-ItemProperty -Path $regPath -Name 'Version' -ErrorAction SilentlyContinue).Version
        if ($installedVersion -eq "{3}") {{
            Write-Output "Detected: {0} {1} {10} version {3}"
            exit 0
        }}
    }}

    # Not detected - exit with no output
    exit 0
}}
catch {{
    # Error during detection - treat as not detected
    exit 0
}}
'@ -f $OEM, $Model, $OS, $Version, $bbValues, (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $osNumber, $UpdateType, $osCheckBlock, $regSubKey, $detectionLabel

    [System.IO.File]::WriteAllText($OutputPath, $scriptContent, [System.Text.UTF8Encoding]::new($false))
    Write-DATLogEntry -Value "[Intune] Detection script generated: $OutputPath (UpdateType: $UpdateType)" -Severity 1
    return $OutputPath
}

function New-DATIntuneWinPackage {
    <#
    .SYNOPSIS
        Creates an .intunewin package from a source folder using the Microsoft Win32 Content Prep Tool.
        Downloads the tool automatically if not present.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$SourceFolder,
        [Parameter(Mandatory)][string]$SetupFile,
        [Parameter(Mandatory)][string]$OutputFolder,
        [string]$ToolsDirectory = $global:ToolsDirectory
    )

    if (-not (Test-Path $SourceFolder)) { throw "Source folder not found: $SourceFolder" }
    if (-not (Test-Path (Join-Path $SourceFolder $SetupFile))) { throw "Setup file not found: $SourceFolder\$SetupFile" }
    if (-not (Test-Path $OutputFolder)) { New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null }

    # Locate or download IntuneWinAppUtil.exe
    $contentPrepTool = Join-Path $ToolsDirectory "IntuneWinAppUtil.exe"
    if (-not (Test-Path $contentPrepTool)) {
        Write-DATLogEntry -Value "[Intune] Downloading Microsoft Win32 Content Prep Tool..." -Severity 1
        Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading IntuneWin Content Prep Tool..." -Type String

        $toolUrl = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
        if (-not (Test-Path $ToolsDirectory)) { New-Item -Path $ToolsDirectory -ItemType Directory -Force | Out-Null }

        try {
            $proxyParams = Get-DATWebRequestProxy
            Invoke-WebRequest -Uri $toolUrl -OutFile $contentPrepTool -UseBasicParsing -TimeoutSec 120 @proxyParams
            Unblock-File -Path $contentPrepTool -ErrorAction SilentlyContinue
            Write-DATLogEntry -Value "[Intune] Content Prep Tool downloaded: $contentPrepTool" -Severity 1
        } catch {
            throw "Failed to download IntuneWinAppUtil.exe: $($_.Exception.Message)"
        }
    }

    # Run the content prep tool
    Write-DATLogEntry -Value "[Intune] Creating .intunewin package from $SourceFolder (setup: $SetupFile)" -Severity 1
    Set-DATRegistryValue -Name "RunningMessage" -Value "Creating IntuneWin package..." -Type String

    $arguments = "-c `"$SourceFolder`" -s `"$SetupFile`" -o `"$OutputFolder`" -q"

    # Use System.Diagnostics.Process with redirected output to prevent stdout buffer deadlock
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $contentPrepTool
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $process.Start() | Out-Null

    # Read streams asynchronously to prevent buffer deadlock
    $stdOutTask = $process.StandardOutput.ReadToEndAsync()
    $stdErrTask = $process.StandardError.ReadToEndAsync()

    # Wait up to 10 minutes for packaging to complete
    $timeoutMs = 600000
    if (-not $process.WaitForExit($timeoutMs)) {
        $process.Kill()
        $process.Dispose()
        throw "IntuneWinAppUtil.exe timed out after 10 minutes"
    }

    $stdOut = $stdOutTask.GetAwaiter().GetResult()
    $stdErr = $stdErrTask.GetAwaiter().GetResult()
    $exitCode = $process.ExitCode
    $process.Dispose()

    if ($stdOut) { Write-DATLogEntry -Value "[Intune] Tool output: $stdOut" -Severity 1 }
    if ($stdErr) { Write-DATLogEntry -Value "[Intune] Tool errors: $stdErr" -Severity 2 }

    if ($exitCode -ne 0) {
        throw "IntuneWinAppUtil.exe failed with exit code $exitCode"
    }

    # The tool creates the file with .intunewin extension matching the setup file name
    $setupBaseName = [System.IO.Path]::GetFileNameWithoutExtension($SetupFile)
    $intuneWinFile = Join-Path $OutputFolder "$setupBaseName.intunewin"

    if (-not (Test-Path $intuneWinFile)) {
        # Sometimes the tool uses the original extension
        $intuneWinFile = Get-ChildItem -Path $OutputFolder -Filter "*.intunewin" -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not (Test-Path $intuneWinFile)) {
        throw "IntuneWin package was not created. Check tool output."
    }

    $fileSize = [math]::Round((Get-Item $intuneWinFile).Length / 1MB, 2)
    Write-DATLogEntry -Value "[Intune] IntuneWin package created: $intuneWinFile ($fileSize MB)" -Severity 1
    return $intuneWinFile
}

function Get-DATIntuneWinEncryptionInfo {
    <#
    .SYNOPSIS
        Extracts encryption info and the encrypted content from a .intunewin file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$IntuneWinFile
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    $tempExtract = Join-Path ([System.IO.Path]::GetTempPath()) "intunewin_$(Get-Date -Format 'yyyyMMddHHmmss')"
    if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
    New-Item -Path $tempExtract -ItemType Directory -Force | Out-Null

    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($IntuneWinFile, $tempExtract)

        # Find the detection.xml metadata
        $detectionXml = Get-ChildItem -Path $tempExtract -Filter "Detection.xml" -Recurse -File | Select-Object -First 1
        if (-not $detectionXml) { throw "Detection.xml not found in .intunewin package" }

        [xml]$metadata = Get-Content $detectionXml.FullName -Raw
        $encInfo = $metadata.ApplicationInfo.EncryptionInfo

        # Find the encrypted content file
        $encryptedFile = Get-ChildItem -Path $tempExtract -Filter "*.intunewin" -Recurse -File |
            Where-Object { $_.FullName -ne $IntuneWinFile -and $_.Directory.Name -eq "Contents" } |
            Select-Object -First 1

        if (-not $encryptedFile) {
            # Fallback: look for any .bin file in Contents
            $encryptedFile = Get-ChildItem -Path (Join-Path $tempExtract "IntuneWinPackage\Contents") -File -ErrorAction SilentlyContinue |
                Select-Object -First 1
        }

        if (-not $encryptedFile) { throw "Encrypted content file not found in .intunewin package" }

        $encryptedSize = (Get-Item $encryptedFile.FullName).Length

        return @{
            EncryptionKey        = $encInfo.EncryptionKey
            InitializationVector = $encInfo.InitializationVector
            Mac                  = $encInfo.Mac
            MacKey               = $encInfo.MacKey
            ProfileIdentifier    = $encInfo.ProfileIdentifier
            FileDigest           = $encInfo.FileDigest
            FileDigestAlgorithm  = $encInfo.FileDigestAlgorithm
            EncryptedFilePath    = $encryptedFile.FullName
            EncryptedFileSize    = $encryptedSize
            TempPath             = $tempExtract
            FileName             = $metadata.ApplicationInfo.FileName
            SetupFile            = $metadata.ApplicationInfo.SetupFile
            UnencryptedSize      = [long]$metadata.ApplicationInfo.UnencryptedContentSize
        }
    } catch {
        if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    }
}

function Invoke-DATIntuneWin32AppUpload {
    <#
    .SYNOPSIS
        Full Win32 app creation + content upload pipeline:
        1. Create the app in Intune with requirement/detection rules
        2. Create a content version
        3. Create a content file entry
        4. Get Azure Storage upload URI
        5. Upload the encrypted file in chunks
        6. Commit the file
        7. Commit the content version
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$IntuneWinFile,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$Publisher,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$RequirementScriptPath,
        [Parameter(Mandatory)][string]$DetectionScriptPath,
        [Parameter(Mandatory)][string]$OS,
        [string]$InstallCommandLine = "powershell.exe -ExecutionPolicy Bypass -File Install-Drivers.ps1",
        [string]$UninstallCommandLine = "powershell.exe -ExecutionPolicy Bypass -File Install-Drivers.ps1",
        [int]$ChunkSizeMB = 50,
        [int]$ParallelUploads = 2
    )

    if (-not (Test-DATIntuneAuth)) { throw "Intune authentication required." }

    # Step 1: Extract encryption info from .intunewin
    Write-DATLogEntry -Value "[Intune Upload] Extracting encryption info from IntuneWin package..." -Severity 1
    Set-DATRegistryValue -Name "RunningMessage" -Value "Reading IntuneWin package metadata..." -Type String
    $encInfo = Get-DATIntuneWinEncryptionInfo -IntuneWinFile $IntuneWinFile

    try {
        # Step 2: Read detection and requirement scripts as base64
        $detectionScriptContent = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($DetectionScriptPath))
        $requirementScriptContent = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($RequirementScriptPath))

        # Step 3: Create the Win32 app with full configuration
        Write-DATLogEntry -Value "[Intune Upload] Creating Win32 app: $DisplayName" -Severity 1
        Set-DATRegistryValue -Name "RunningMessage" -Value "Creating Intune Win32 app: $DisplayName..." -Type String

        # Load application icon from Branding folder
        $iconPath = Join-Path -Path $global:ScriptDirectory -ChildPath "Branding\DATLogo.png"
        $largeIcon = $null
        if (Test-Path $iconPath) {
            $iconBase64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($iconPath))
            $largeIcon = @{
                "@odata.type" = "#microsoft.graph.mimeContent"
                type          = "image/png"
                value         = $iconBase64
            }
            Write-DATLogEntry -Value "[Intune Upload] Application icon loaded from $iconPath" -Severity 1
        } else {
            Write-DATLogEntry -Value "[Intune Upload] Application icon not found at $iconPath -- package will use default icon" -Severity 2
        }

        $appBody = @{
            "@odata.type"                            = "#microsoft.graph.win32LobApp"
            displayName                              = $DisplayName
            description                              = $Description
            publisher                                = $Publisher
            developer                                = "Maurice Daly"
            notes                                    = "Created by the Driver Automation Tool"
            informationUrl                           = "https://msendpointmgr.com"
            displayVersion                           = $Version
            fileName                                 = $encInfo.FileName
            setupFilePath                            = $encInfo.SetupFile
            installCommandLine                       = $InstallCommandLine
            uninstallCommandLine                     = $UninstallCommandLine
            applicableArchitectures                  = "x64"
            minimumOperatingSystem                    = (ConvertTo-DATIntuneMinimumOS -OS $OS)
            installExperience                        = @{
                "@odata.type"         = "#microsoft.graph.win32LobAppInstallExperience"
                runAsAccount          = "system"
                deviceRestartBehavior = "suppress"
            }
            largeIcon                                = $largeIcon
            returnCodes                              = @(
                @{ "@odata.type" = "#microsoft.graph.win32LobAppReturnCode"; returnCode = 0; type = "success" }
                @{ "@odata.type" = "#microsoft.graph.win32LobAppReturnCode"; returnCode = 1707; type = "success" }
                @{ "@odata.type" = "#microsoft.graph.win32LobAppReturnCode"; returnCode = 3010; type = "softReboot" }
                @{ "@odata.type" = "#microsoft.graph.win32LobAppReturnCode"; returnCode = 1641; type = "hardReboot" }
                @{ "@odata.type" = "#microsoft.graph.win32LobAppReturnCode"; returnCode = 1618; type = "retry" }
            )
            rules                                    = @(
                @{
                    "@odata.type"            = "#microsoft.graph.win32LobAppPowerShellScriptRule"
                    ruleType                = "detection"
                    scriptContent           = $detectionScriptContent
                    enforceSignatureCheck   = $false
                    runAs32Bit              = $false
                }
                @{
                    "@odata.type"            = "#microsoft.graph.win32LobAppPowerShellScriptRule"
                    ruleType                = "requirement"
                    scriptContent           = $requirementScriptContent
                    enforceSignatureCheck   = $false
                    runAs32Bit              = $false
                    runAsAccount            = "system"
                    displayName             = "DAT Model Requirement"
                    operationType           = "string"
                    comparisonValue         = "Requirement met"
                    operator                = "equal"
                }
            )
        }

        $app = Invoke-DATGraphRequest -Uri "/deviceAppManagement/mobileApps" -Method POST -Body $appBody
        $appId = $app.id
        Write-DATLogEntry -Value "[Intune Upload] App created with ID: $appId" -Severity 1

        # Step 4: Create content version
        Write-DATLogEntry -Value "[Intune Upload] Creating content version..." -Severity 1
        $contentVersion = Invoke-DATGraphRequest -Uri "/deviceAppManagement/mobileApps/$appId/microsoft.graph.win32LobApp/contentVersions" -Method POST -Body @{}
        $contentVersionId = $contentVersion.id
        Write-DATLogEntry -Value "[Intune Upload] Content version ID: $contentVersionId" -Severity 1

        # Step 5: Create content file entry
        Write-DATLogEntry -Value "[Intune Upload] Creating content file entry..." -Severity 1
        Set-DATRegistryValue -Name "RunningMessage" -Value "Preparing upload for $DisplayName..." -Type String

        $fileBody = @{
            "@odata.type" = "#microsoft.graph.mobileAppContentFile"
            name          = $encInfo.FileName
            size          = $encInfo.UnencryptedSize
            sizeEncrypted = $encInfo.EncryptedFileSize
            manifest      = $null
            isDependency  = $false
        }

        $contentFile = Invoke-DATGraphRequest `
            -Uri "/deviceAppManagement/mobileApps/$appId/microsoft.graph.win32LobApp/contentVersions/$contentVersionId/files" `
            -Method POST -Body $fileBody
        $contentFileId = $contentFile.id

        # Step 6: Wait for Azure Storage URI
        Write-DATLogEntry -Value "[Intune Upload] Waiting for Azure Storage upload URI..." -Severity 1
        $maxWait = 120
        $waited = 0
        $azureStorageUri = $null

        do {
            Start-Sleep -Seconds 5
            $waited += 5
            $fileStatus = Invoke-DATGraphRequest `
                -Uri "/deviceAppManagement/mobileApps/$appId/microsoft.graph.win32LobApp/contentVersions/$contentVersionId/files/$contentFileId" `
                -NoPagination
            $azureStorageUri = $fileStatus.azureStorageUri
            $uploadState = $fileStatus.uploadState

            if ($uploadState -eq 'azureStorageUriRequestFailed') {
                throw "Azure Storage URI request failed. Upload state: $uploadState"
            }
        } while ([string]::IsNullOrEmpty($azureStorageUri) -and $waited -lt $maxWait)

        if ([string]::IsNullOrEmpty($azureStorageUri)) {
            throw "Timed out waiting for Azure Storage URI after $maxWait seconds"
        }

        Write-DATLogEntry -Value "[Intune Upload] Azure Storage URI obtained. Starting chunked upload..." -Severity 1
        Set-DATRegistryValue -Name "RunningMode" -Value "Uploading" -Type String
        Set-DATRegistryValue -Name "RunningMessage" -Value "Uploading $DisplayName to Intune..." -Type String
        Set-DATRegistryValue -Name "DownloadSize" -Value "$([math]::Round($encInfo.EncryptedFileSize / 1MB, 2)) MB" -Type String
        Set-DATRegistryValue -Name "DownloadBytes" -Value "$($encInfo.EncryptedFileSize)" -Type String
        Set-DATRegistryValue -Name "BytesTransferred" -Value "0" -Type String
        Set-DATRegistryValue -Name "DownloadSpeed" -Value "---" -Type String

        # Step 7: Upload file in chunks with optional parallelism
        $chunkSize = $ChunkSizeMB * 1024 * 1024
        $encryptedFilePath = $encInfo.EncryptedFilePath
        $fileSize = $encInfo.EncryptedFileSize
        $totalChunks = [math]::Ceiling($fileSize / $chunkSize)
        $blockIds = [System.Collections.ArrayList]::new()
        $uploadStartTime = Get-Date

        Write-DATLogEntry -Value "[Intune Upload] File size: $([math]::Round($fileSize/1MB, 2)) MB, chunk size: $ChunkSizeMB MB, chunks: $totalChunks, parallel: $ParallelUploads" -Severity 1

        # Pre-generate all block IDs in order (required for block list commit)
        for ($i = 0; $i -lt $totalChunks; $i++) {
            [void]$blockIds.Add([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("block-$('{0:D6}' -f $i)")))
        }

        if ($ParallelUploads -le 1) {
            # Sequential upload
            $fileStream = [System.IO.File]::OpenRead($encryptedFilePath)
            try {
                for ($chunk = 0; $chunk -lt $totalChunks; $chunk++) {
                    $bytesToRead = [math]::Min([long]$chunkSize, [long]($fileSize - ($chunk * $chunkSize)))
                    $buffer = [byte[]]::new($bytesToRead)
                    $bytesRead = $fileStream.Read($buffer, 0, $bytesToRead)
                    if ($bytesRead -ne $bytesToRead) { $buffer = $buffer[0..($bytesRead - 1)] }

                    $blockUrl = "$azureStorageUri&comp=block&blockid=$([System.Uri]::EscapeDataString($blockIds[$chunk]))"

                    $proxyParams = Get-DATWebRequestProxy
                    $retries = 0; $maxRetries = 3
                    while ($retries -lt $maxRetries) {
                        try {
                            Invoke-RestMethod -Method PUT -Uri $blockUrl -Body $buffer `
                                -Headers @{ "x-ms-blob-type" = "BlockBlob" } `
                                -ContentType "application/octet-stream" -ErrorAction Stop @proxyParams
                            break
                        } catch {
                            $retries++
                            if ($retries -ge $maxRetries) { throw "Chunk $($chunk + 1)/$totalChunks upload failed after $maxRetries retries: $($_.Exception.Message)" }
                            Start-Sleep -Seconds ($retries * 5)
                            Write-DATLogEntry -Value "[Intune Upload] Chunk $($chunk + 1) retry $retries..." -Severity 2
                        }
                    }

                    $pct = [math]::Round((($chunk + 1) / $totalChunks) * 100, 0)
                    $uploadedBytes = [math]::Min([long](($chunk + 1) * $chunkSize), $fileSize)
                    $uploadedMB = [math]::Round($uploadedBytes / 1MB, 2)
                    $totalMB = [math]::Round($fileSize / 1MB, 2)
                    $elapsedUpload = ((Get-Date) - $uploadStartTime).TotalSeconds
                    $speedMBps = if ($elapsedUpload -gt 0) { [math]::Round($uploadedMB / $elapsedUpload, 2) } else { 0 }
                    $remainingMB = $totalMB - $uploadedMB
                    $eta = if ($speedMBps -gt 0) { [math]::Round($remainingMB / $speedMBps) } else { 0 }
                    $etaStr = if ($eta -gt 60) { "$([math]::Floor($eta / 60))m $($eta % 60)s" } else { "${eta}s" }

                    Set-DATRegistryValue -Name "RunningMessage" -Value "Uploading $DisplayName... ${pct}% -- $uploadedMB / $totalMB MB ($($chunk + 1)/$totalChunks chunks) -- ETA: $etaStr" -Type String
                    Set-DATRegistryValue -Name "BytesTransferred" -Value "$uploadedBytes" -Type String
                    Set-DATRegistryValue -Name "DownloadBytes" -Value "$fileSize" -Type String
                    Set-DATRegistryValue -Name "DownloadSpeed" -Value "$speedMBps MB/s" -Type String
                    if (($chunk + 1) % 10 -eq 0 -or ($chunk + 1) -eq $totalChunks) {
                        Write-DATLogEntry -Value "[Intune Upload] Progress: $pct% -- $uploadedMB / $totalMB MB at $speedMBps MB/s ($($chunk + 1)/$totalChunks chunks)" -Severity 1
                    }
                }
            } finally {
                $fileStream.Dispose()
            }
        } else {
            # Parallel upload using runspaces -- each thread reads its own chunk from disk
            # to avoid loading the entire file into memory (which can hang on large packages)
            Write-DATLogEntry -Value "[Intune Upload] Using $ParallelUploads parallel threads" -Severity 1

            # Resolve proxy settings in main thread -- runspaces don't have module functions
            $parallelProxyParams = Get-DATWebRequestProxy
            if ($parallelProxyParams -isnot [hashtable]) { $parallelProxyParams = @{} }

            $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $ParallelUploads)
            $pool.Open()

            $uploadScript = {
                param ($BlockUrl, $FilePath, $Offset, $Length, $MaxRetries, $ProxyParams)
                try {
                    $fs = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
                    try {
                        [void]$fs.Seek($Offset, [System.IO.SeekOrigin]::Begin)
                        $buffer = [byte[]]::new($Length)
                        $totalRead = 0
                        while ($totalRead -lt $Length) {
                            $read = $fs.Read($buffer, $totalRead, ($Length - $totalRead))
                            if ($read -eq 0) { break }
                            $totalRead += $read
                        }
                        if ($totalRead -ne $Length) {
                            $buffer = $buffer[0..($totalRead - 1)]
                        }
                    } finally {
                        $fs.Dispose()
                    }

                    $retries = 0
                    while ($retries -lt $MaxRetries) {
                        try {
                            Invoke-RestMethod -Method PUT -Uri $BlockUrl -Body $buffer `
                                -Headers @{ "x-ms-blob-type" = "BlockBlob" } `
                                -ContentType "application/octet-stream" -ErrorAction Stop @ProxyParams
                            return @{ Success = $true }
                        } catch {
                            $retries++
                            if ($retries -ge $MaxRetries) {
                                return @{ Success = $false; Error = $_.Exception.Message }
                            }
                            Start-Sleep -Seconds ($retries * 5)
                        }
                    }
                } catch {
                    return @{ Success = $false; Error = $_.Exception.Message }
                }
            }

            $jobs = [System.Collections.ArrayList]::new()
            for ($chunk = 0; $chunk -lt $totalChunks; $chunk++) {
                $blockUrl = "$azureStorageUri&comp=block&blockid=$([System.Uri]::EscapeDataString($blockIds[$chunk]))"
                $offset = [long]$chunk * [long]$chunkSize
                $length = [int]([math]::Min([long]$chunkSize, [long]($fileSize - $offset)))
                $ps = [powershell]::Create()
                $ps.RunspacePool = $pool
                [void]$ps.AddScript($uploadScript)
                [void]$ps.AddArgument($blockUrl)
                [void]$ps.AddArgument($encryptedFilePath)
                [void]$ps.AddArgument($offset)
                [void]$ps.AddArgument($length)
                [void]$ps.AddArgument(3)
                [void]$ps.AddArgument($parallelProxyParams)
                $async = $ps.BeginInvoke()
                [void]$jobs.Add(@{ PS = $ps; Async = $async; Chunk = $chunk })
            }

            $completedCount = 0
            foreach ($job in $jobs) {
                $result = $job.PS.EndInvoke($job.Async)
                $job.PS.Dispose()
                if (-not $result.Success) {
                    $pool.Dispose()
                    throw "Chunk $($job.Chunk + 1)/$totalChunks upload failed: $($result.Error)"
                }
                $completedCount++
                $pct = [math]::Round(($completedCount / $totalChunks) * 100, 0)
                $uploadedBytes = [math]::Min([long]($completedCount * $chunkSize), $fileSize)
                $uploadedMB = [math]::Round($uploadedBytes / 1MB, 2)
                $totalMB = [math]::Round($fileSize / 1MB, 2)
                $elapsedUpload = ((Get-Date) - $uploadStartTime).TotalSeconds
                $speedMBps = if ($elapsedUpload -gt 0) { [math]::Round($uploadedMB / $elapsedUpload, 2) } else { 0 }
                $remainingMB = $totalMB - $uploadedMB
                $eta = if ($speedMBps -gt 0) { [math]::Round($remainingMB / $speedMBps) } else { 0 }
                $etaStr = if ($eta -gt 60) { "$([math]::Floor($eta / 60))m $($eta % 60)s" } else { "${eta}s" }

                Set-DATRegistryValue -Name "RunningMessage" -Value "Uploading $DisplayName... ${pct}% -- $uploadedMB / $totalMB MB ($completedCount/$totalChunks chunks) -- ETA: $etaStr" -Type String
                Set-DATRegistryValue -Name "BytesTransferred" -Value "$uploadedBytes" -Type String
                Set-DATRegistryValue -Name "DownloadBytes" -Value "$fileSize" -Type String
                Set-DATRegistryValue -Name "DownloadSpeed" -Value "$speedMBps MB/s" -Type String
                if ($completedCount % 10 -eq 0 -or $completedCount -eq $totalChunks) {
                    Write-DATLogEntry -Value "[Intune Upload] Progress: $pct% -- $uploadedMB / $totalMB MB at $speedMBps MB/s ($completedCount/$totalChunks chunks)" -Severity 1
                }
            }

            $pool.Dispose()
        }

        # Step 7b: Renew the Azure Storage URI before committing (SAS token may have expired during long uploads)
        Write-DATLogEntry -Value "[Intune Upload] Renewing Azure Storage URI before commit..." -Severity 1
        try {
            Invoke-DATGraphRequest `
                -Uri "/deviceAppManagement/mobileApps/$appId/microsoft.graph.win32LobApp/contentVersions/$contentVersionId/files/$contentFileId/renewUpload" `
                -Method POST

            $renewWait = 0
            $renewMaxWait = 60
            do {
                Start-Sleep -Seconds 5
                $renewWait += 5
                $renewedFileStatus = Invoke-DATGraphRequest `
                    -Uri "/deviceAppManagement/mobileApps/$appId/microsoft.graph.win32LobApp/contentVersions/$contentVersionId/files/$contentFileId" `
                    -NoPagination
            } while ([string]::IsNullOrEmpty($renewedFileStatus.azureStorageUri) -and $renewWait -lt $renewMaxWait)

            if (-not [string]::IsNullOrEmpty($renewedFileStatus.azureStorageUri)) {
                $azureStorageUri = $renewedFileStatus.azureStorageUri
                Write-DATLogEntry -Value "[Intune Upload] Azure Storage URI renewed successfully." -Severity 1
            } else {
                Write-DATLogEntry -Value "[Intune Upload] URI renewal returned empty, using existing URI." -Severity 2
            }
        } catch {
            Write-DATLogEntry -Value "[Intune Upload] URI renewal failed: $($_.Exception.Message). Proceeding with existing URI." -Severity 2
        }

        # Step 8: Commit the block list
        Write-DATLogEntry -Value "[Intune Upload] Committing block list ($($blockIds.Count) blocks)..." -Severity 1
        $blockListXml = '<?xml version="1.0" encoding="utf-8"?><BlockList>'
        foreach ($id in $blockIds) {
            $blockListXml += "<Latest>$id</Latest>"
        }
        $blockListXml += '</BlockList>'

        $proxyParams = Get-DATWebRequestProxy
        Invoke-RestMethod -Method PUT -Uri "$azureStorageUri&comp=blocklist" `
            -Body $blockListXml -ContentType "application/xml" -ErrorAction Stop @proxyParams

        Write-DATLogEntry -Value "[Intune Upload] Block list committed successfully." -Severity 1

        # Step 9: Commit the file with encryption info
        Write-DATLogEntry -Value "[Intune Upload] Committing file with encryption info..." -Severity 1
        Set-DATRegistryValue -Name "RunningMessage" -Value "Finalizing upload for $DisplayName..." -Type String

        $commitBody = @{
            fileEncryptionInfo = @{
                encryptionKey        = $encInfo.EncryptionKey
                initializationVector = $encInfo.InitializationVector
                mac                  = $encInfo.Mac
                macKey               = $encInfo.MacKey
                profileIdentifier    = $encInfo.ProfileIdentifier
                fileDigest           = $encInfo.FileDigest
                fileDigestAlgorithm  = $encInfo.FileDigestAlgorithm
            }
        }

        Invoke-DATGraphRequest `
            -Uri "/deviceAppManagement/mobileApps/$appId/microsoft.graph.win32LobApp/contentVersions/$contentVersionId/files/$contentFileId/commit" `
            -Method POST -Body $commitBody

        # Step 10: Wait for file processing
        Write-DATLogEntry -Value "[Intune Upload] Waiting for file processing..." -Severity 1
        $maxProcessWait = 300
        $processWaited = 0

        do {
            Start-Sleep -Seconds 10
            $processWaited += 10
            $fileStatus = Invoke-DATGraphRequest `
                -Uri "/deviceAppManagement/mobileApps/$appId/microsoft.graph.win32LobApp/contentVersions/$contentVersionId/files/$contentFileId" `
                -NoPagination
            $uploadState = $fileStatus.uploadState

            if ($uploadState -eq 'commitFileFailed') {
                throw "File commit failed. Upload state: $uploadState"
            }

            Set-DATRegistryValue -Name "RunningMessage" -Value "Processing upload... ($uploadState)" -Type String
        } while ($uploadState -ne 'commitFileSuccess' -and $processWaited -lt $maxProcessWait)

        if ($uploadState -ne 'commitFileSuccess') {
            throw "File processing timed out after $maxProcessWait seconds. Final state: $uploadState"
        }

        # Step 11: Update the app to reference this content version
        Write-DATLogEntry -Value "[Intune Upload] Setting committed content version on app..." -Severity 1
        $updateBody = @{
            "@odata.type"            = "#microsoft.graph.win32LobApp"
            committedContentVersion  = $contentVersionId
        }

        Invoke-DATGraphRequest -Uri "/deviceAppManagement/mobileApps/$appId" -Method PATCH -Body $updateBody

        $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
        Write-DATLogEntry -Value "[Intune Upload] SUCCESS: $DisplayName uploaded ($fileSizeMB MB) - App ID: $appId" -Severity 1
        Set-DATRegistryValue -Name "RunningMessage" -Value "Uploaded $DisplayName ($fileSizeMB MB)" -Type String

        return @{
            AppId          = $appId
            DisplayName    = $DisplayName
            Version        = $Version
            ContentVersion = $contentVersionId
            FileSize       = $fileSizeMB
        }
    }
    finally {
        # Clean up temp extraction
        if ($encInfo -and $encInfo.TempPath -and (Test-Path $encInfo.TempPath)) {
            Remove-Item $encInfo.TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-DATIntunePackageCreation {
    <#
    .SYNOPSIS
        Orchestrates the full Intune Win32 app pipeline for a model:
        1. Generate install script
        2. Generate requirement script
        3. Generate detection script
        4. Stage WIM + install script into package folder
        5. Create .intunewin package
        6. Upload to Intune with full metadata
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$OEM,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Baseboards,
        [Parameter(Mandatory)][string]$OS,
        [Parameter(Mandatory)][string]$Architecture,
        [Parameter(Mandatory)][string]$WimFilePath,
        [Parameter(Mandatory)][string]$PackageDestination,
        [string]$IntuneAuthToken,
        [ValidateSet('Drivers','BIOS')][string]$UpdateType = 'Drivers',
        [switch]$DisableToast,
        [ValidateSet('RemindMeLater','InstallNow')][string]$ToastTimeoutAction = 'RemindMeLater',
        [int]$MaxDeferrals = 0,
        [string]$DebugBuildPath,
        [string]$CustomBrandingPath,
        [string]$Version,
        [string]$HPPasswordBinPath,
        [switch]$ForceUpdate,
        [string]$CustomToastTitle,
        [string]$CustomToastBody
    )
    if (-not [string]::IsNullOrEmpty($IntuneAuthToken)) {
        $script:IntuneAuthToken = $IntuneAuthToken
        $script:IntuneTokenExpiry = (Get-Date).AddMinutes(30)  # Reasonable buffer
    }

    if (-not (Test-DATIntuneAuth)) {
        throw "Intune authentication required for Win32 app creation."
    }

    # Use the supplied version (e.g. BIOS catalog version) if available, otherwise fall back to date
    if ([string]::IsNullOrEmpty($Version)) {
        $version = Get-Date -Format "ddMMyyyy"
    } else {
        $version = $Version
    }
    $installScriptName = if ($UpdateType -eq 'BIOS') { 'Install-BIOS.ps1' } else { 'Install-Drivers.ps1' }
    $displayName = "$UpdateType - $OEM $Model - $OS $Architecture"
    $publisher = $OEM
    $description = "$UpdateType package for $OEM $Model`nOS: $OS`nArchitecture: $Architecture`nBaseboards/SKU: $Baseboards`nVersion: $version`nCreated by Driver Automation Tool"

    Write-DATLogEntry -Value "[Intune Pipeline] Starting Intune package creation for $OEM $Model" -Severity 1
    Write-DATLogEntry -Value "[Intune Pipeline] Version: $version | Display Name: $displayName" -Severity 1
    Set-DATRegistryValue -Name "RunningMessage" -Value "Preparing Intune package for $OEM $Model..." -Type String
    Set-DATRegistryValue -Name "RunningMode" -Value "Packaging" -Type String

    # --- Duplicate detection: skip if same displayName + version already exists in Intune ---
    try {
        Write-DATLogEntry -Value "[Intune Pipeline] Checking for existing package: $displayName (version $version)" -Severity 1
        $escapedName = $displayName -replace "'", "''"
        $filterUri = "/deviceAppManagement/mobileApps?`$filter=isof('microsoft.graph.win32LobApp') and displayName eq '$escapedName'"
        $existingApps = Invoke-DATGraphRequest -Uri $filterUri
        if ($existingApps) {
            $matchingApp = $existingApps | Where-Object { $_.displayVersion -eq $version }
            if ($matchingApp -and -not $ForceUpdate) {
                $appId = $matchingApp.id
                if ($appId -is [array]) { $appId = $appId[0] }
                Write-DATLogEntry -Value "[Intune Pipeline] SKIPPED: '$displayName' version $version already exists in Intune (App ID: $appId)" -Severity 1 -UpdateUI
                Set-DATRegistryValue -Name "RunningMessage" -Value "Skipped (exists): $OEM $Model" -Type String
                return @{ AppId = $appId; Skipped = $true }
            }
            if ($matchingApp -and $ForceUpdate) {
                $appId = $matchingApp.id
                if ($appId -is [array]) { $appId = $appId[0] }
                Write-DATLogEntry -Value "[Intune Pipeline] FORCE UPDATE: Removing existing app '$displayName' (App ID: $appId) before re-creation" -Severity 1 -UpdateUI
                Set-DATRegistryValue -Name "RunningMessage" -Value "Force update: removing existing $OEM $Model..." -Type String
                Invoke-DATGraphRequest -Uri "/deviceAppManagement/mobileApps/$appId" -Method DELETE | Out-Null
                Write-DATLogEntry -Value "[Intune Pipeline] Existing app deleted. Proceeding with fresh creation." -Severity 1
            }
        }
        Write-DATLogEntry -Value "[Intune Pipeline] No existing package found -- proceeding with creation" -Severity 1
    } catch {
        Write-DATLogEntry -Value "[Intune Pipeline] Duplicate check failed ($($_.Exception.Message)) -- proceeding with creation" -Severity 2
    }

    # Create staging directory for the package
    $stagingDir = Join-Path $PackageDestination "IntuneStaging\$OEM\$Model\$OS"
    if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
    New-Item -Path $stagingDir -ItemType Directory -Force | Out-Null

    $scriptsDir = Join-Path $PackageDestination "IntuneScripts\$OEM\$Model\$OS"
    if (Test-Path $scriptsDir) { Remove-Item $scriptsDir -Recurse -Force }
    New-Item -Path $scriptsDir -ItemType Directory -Force | Out-Null

    $outputDir = Join-Path $PackageDestination "IntuneWin\$OEM\$Model\$OS"
    if (Test-Path $outputDir) { Remove-Item $outputDir -Recurse -Force }
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

    try {
        # Step 1: Copy WIM to staging
        Write-DATLogEntry -Value "[Intune Pipeline] Copying WIM to staging directory..." -Severity 1 -UpdateUI
        Set-DATRegistryValue -Name "RunningMessage" -Value "Staging WIM for $OEM $Model..." -Type String
        Copy-Item -Path $WimFilePath -Destination (Join-Path $stagingDir "DriverPackage.wim") -Force
        $wimSize = [math]::Round((Get-Item $WimFilePath).Length / 1MB, 2)
        Write-DATLogEntry -Value "[Intune Pipeline] WIM staged: $wimSize MB" -Severity 1

        # Step 1b: Copy HP password BIN file into staging (if provided for HP BIOS packages)
        if ($UpdateType -eq 'BIOS' -and $OEM -match 'HP' -and -not [string]::IsNullOrEmpty($HPPasswordBinPath) -and (Test-Path $HPPasswordBinPath)) {
            $destBinFile = Join-Path $stagingDir 'HPPasswordFile.bin'
            Copy-Item -Path $HPPasswordBinPath -Destination $destBinFile -Force
            Write-DATLogEntry -Value "[Intune Pipeline] HP password BIN file copied to staging: $destBinFile" -Severity 1
        }

        # Step 2: Generate install script into staging
        Set-DATRegistryValue -Name "RunningMessage" -Value "Generating install script for $OEM $Model..." -Type String
        $installScriptPath = Join-Path $stagingDir $installScriptName
        $installScriptParams = @{
            OutputPath  = $installScriptPath
            OEM         = $OEM
            Model       = $Model
            OS          = $OS
            Version     = $version
            UpdateType  = $UpdateType
        }
        if ($DisableToast) { $installScriptParams['DisableToast'] = $true }
        if ($ToastTimeoutAction -ne 'RemindMeLater') { $installScriptParams['ToastTimeoutAction'] = $ToastTimeoutAction }
        if ($MaxDeferrals -gt 0) { $installScriptParams['MaxDeferrals'] = $MaxDeferrals }
        New-DATIntuneInstallScript @installScriptParams
        Write-DATLogEntry -Value "[Intune Pipeline] Install script created: $installScriptPath" -Severity 1 -UpdateUI

        # Step 2b: Generate toast notification scripts into staging (unless disabled)
        if (-not $DisableToast) {
            $toastScriptPath = Join-Path $stagingDir "Show-ToastNotification.ps1"
            $toastParams = @{
                OutputPath   = $toastScriptPath
                UpdateType   = $UpdateType
                BrandingPath = Join-Path $global:ScriptDirectory 'Branding'
            }
            if (-not [string]::IsNullOrEmpty($CustomBrandingPath)) { $toastParams['CustomBrandingImagePath'] = $CustomBrandingPath }
            if (-not [string]::IsNullOrEmpty($CustomToastTitle)) { $toastParams['CustomToastTitle'] = $CustomToastTitle }
            if (-not [string]::IsNullOrEmpty($CustomToastBody))  { $toastParams['CustomToastBody']  = $CustomToastBody  }
            New-DATIntuneToastScript @toastParams
            Write-DATLogEntry -Value "[Intune Pipeline] Toast script created: $toastScriptPath" -Severity 1 -UpdateUI

            # Generate completion status toast scripts (Success / Issues)
            $statusToastParams = @{
                BrandingPath = Join-Path $global:ScriptDirectory 'Branding'
            }
            if (-not [string]::IsNullOrEmpty($CustomBrandingPath)) { $statusToastParams['CustomBrandingImagePath'] = $CustomBrandingPath }

            $successToastPath = Join-Path $stagingDir "Show-StatusToast-Success.ps1"
            New-DATIntuneToastScript -OutputPath $successToastPath -UpdateType 'Success' @statusToastParams
            Write-DATLogEntry -Value "[Intune Pipeline] Success toast script created: $successToastPath" -Severity 1 -UpdateUI

            # Generate BIOS-specific prestaged toast (used only by BIOS install scripts)
            if ($UpdateType -eq 'BIOS') {
                $biosSuccessToastPath = Join-Path $stagingDir "Show-StatusToast-BIOSSuccess.ps1"
                New-DATIntuneToastScript -OutputPath $biosSuccessToastPath -UpdateType 'BIOSSuccess' @statusToastParams
                Write-DATLogEntry -Value "[Intune Pipeline] BIOS prestaged toast script created: $biosSuccessToastPath" -Severity 1 -UpdateUI
            }

            $issuesToastPath = Join-Path $stagingDir "Show-StatusToast-Issues.ps1"
            New-DATIntuneToastScript -OutputPath $issuesToastPath -UpdateType 'Issues' @statusToastParams
            Write-DATLogEntry -Value "[Intune Pipeline] Issues toast script created: $issuesToastPath" -Severity 1 -UpdateUI

            # Generate BIOS-specific issues toast (used only by BIOS install scripts)
            if ($UpdateType -eq 'BIOS') {
                $biosIssuesToastPath = Join-Path $stagingDir "Show-StatusToast-BIOSIssues.ps1"
                New-DATIntuneToastScript -OutputPath $biosIssuesToastPath -UpdateType 'BIOSIssues' @statusToastParams
                Write-DATLogEntry -Value "[Intune Pipeline] BIOS issues toast script created: $biosIssuesToastPath" -Severity 1 -UpdateUI
            }
        }

        # Step 3: Generate requirement script (stored separately, not in the .intunewin)
        Set-DATRegistryValue -Name "RunningMessage" -Value "Generating requirement script for $OEM $Model..." -Type String
        $requirementScriptPath = Join-Path $scriptsDir "Require-$OEM-$($Model -replace '\s+','-').ps1"
        New-DATIntuneRequirementScript -OutputPath $requirementScriptPath -OEM $OEM -Model $Model `
            -Baseboards $Baseboards -OS $OS -Version $version -UpdateType $UpdateType
        Write-DATLogEntry -Value "[Intune Pipeline] Requirement script created: $requirementScriptPath" -Severity 1 -UpdateUI

        # Step 4: Generate detection script (stored separately, not in the .intunewin)
        Set-DATRegistryValue -Name "RunningMessage" -Value "Generating detection script for $OEM $Model..." -Type String
        $detectionScriptPath = Join-Path $scriptsDir "Detect-$OEM-$($Model -replace '\s+','-').ps1"
        New-DATIntuneDetectionScript -OutputPath $detectionScriptPath -OEM $OEM -Model $Model `
            -Baseboards $Baseboards -OS $OS -Version $version -UpdateType $UpdateType
        Write-DATLogEntry -Value "[Intune Pipeline] Detection script created: $detectionScriptPath" -Severity 1 -UpdateUI

        # Debug output: copy staging and script content to debug folder for validation
        if (-not [string]::IsNullOrEmpty($DebugBuildPath)) {
            $debugOutputDir = Join-Path $DebugBuildPath "$OEM\$Model"
            Write-DATLogEntry -Value "[Intune Pipeline] Debug build enabled -- copying staging files to: $debugOutputDir" -Severity 1 -UpdateUI
            Set-DATRegistryValue -Name "RunningMessage" -Value "Copying debug output for $OEM $Model..." -Type String

            if (Test-Path $debugOutputDir) { Remove-Item $debugOutputDir -Recurse -Force }
            New-Item -Path $debugOutputDir -ItemType Directory -Force | Out-Null

            # Copy staging content (WIM, install script, toast scripts)
            $debugStagingDir = Join-Path $debugOutputDir "Staging"
            Copy-Item -Path $stagingDir -Destination $debugStagingDir -Recurse -Force

            # Copy requirement & detection scripts
            $debugScriptsDir = Join-Path $debugOutputDir "Scripts"
            Copy-Item -Path $scriptsDir -Destination $debugScriptsDir -Recurse -Force

            $debugFileCount = (Get-ChildItem -Path $debugOutputDir -Recurse -File -ErrorAction SilentlyContinue).Count
            Write-DATLogEntry -Value "[Intune Pipeline] Debug output complete: $debugFileCount files copied to $debugOutputDir" -Severity 1 -UpdateUI
        }

        # Step 5: Create .intunewin package
        Write-DATLogEntry -Value "[Intune Pipeline] Creating .intunewin package..." -Severity 1 -UpdateUI
        Set-DATRegistryValue -Name "RunningMessage" -Value "Creating IntuneWin package for $OEM $Model..." -Type String
        $intuneWinFile = New-DATIntuneWinPackage -SourceFolder $stagingDir `
            -SetupFile $installScriptName -OutputFolder $outputDir
        if (-not $intuneWinFile -or -not (Test-Path $intuneWinFile)) {
            throw "IntuneWin package creation failed - output file not found"
        }
        $intuneWinSize = [math]::Round((Get-Item $intuneWinFile).Length / 1MB, 2)
        Write-DATLogEntry -Value "[Intune Pipeline] IntuneWin package created: $intuneWinFile ($intuneWinSize MB)" -Severity 1 -UpdateUI

        # Transition to Upload stage now that .intunewin is ready
        Set-DATRegistryValue -Name "RunningMode" -Value "Intune Upload" -Type String

        # Reset download tracking values so the UI progress bar reflects upload progress
        Set-DATRegistryValue -Name "DownloadSize" -Value "$intuneWinSize MB" -Type String
        Set-DATRegistryValue -Name "DownloadBytes" -Value "0" -Type String
        Set-DATRegistryValue -Name "BytesTransferred" -Value "0" -Type String
        Set-DATRegistryValue -Name "DownloadSpeed" -Value "---" -Type String

        # Step 6: Upload to Intune
        # Read upload performance settings from registry
        $savedConfig = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
        $uploadChunkSizeMB = if ($null -ne $savedConfig.IntuneChunkSizeMB -and $savedConfig.IntuneChunkSizeMB -gt 0) { [int]$savedConfig.IntuneChunkSizeMB } else { 6 }
        $uploadParallelCount = if ($null -ne $savedConfig.IntuneParallelUploads -and $savedConfig.IntuneParallelUploads -gt 0) { [int]$savedConfig.IntuneParallelUploads } else { 1 }

        Write-DATLogEntry -Value "[Intune Pipeline] Uploading to Intune (chunk: ${uploadChunkSizeMB}MB, parallel: $uploadParallelCount)..." -Severity 1 -UpdateUI
        Set-DATRegistryValue -Name "RunningMessage" -Value "Uploading to Intune: $OEM $Model ($intuneWinSize MB)..." -Type String
        $result = Invoke-DATIntuneWin32AppUpload -IntuneWinFile $intuneWinFile `
            -DisplayName $displayName `
            -Publisher $publisher `
            -Description $description `
            -Version $version `
            -RequirementScriptPath $requirementScriptPath `
            -DetectionScriptPath $detectionScriptPath `
            -OS $OS `
            -InstallCommandLine "powershell.exe -ExecutionPolicy Bypass -File $installScriptName" `
            -UninstallCommandLine "powershell.exe -ExecutionPolicy Bypass -File $installScriptName" `
            -ChunkSizeMB $uploadChunkSizeMB `
            -ParallelUploads $uploadParallelCount

        Write-DATLogEntry -Value "[Intune Pipeline] SUCCESS: $displayName uploaded to Intune (App ID: $($result.AppId))" -Severity 1 -UpdateUI
        Set-DATRegistryValue -Name "RunningMessage" -Value "Intune package created: $OEM $Model ($intuneWinSize MB)" -Type String

        return $result
    } catch {
        Write-DATLogEntry -Value "[Intune Pipeline] FAILED: $($_.Exception.Message)" -Severity 3
        Set-DATRegistryValue -Name "RunningMessage" -Value "Intune package failed: $OEM $Model" -Type String
        throw
    } finally {
        # Clean up staging directory
        if (Test-Path $stagingDir) {
            Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-DATIntuneWin32App {
    <#
    .SYNOPSIS
        Creates a new Win32 LOB application in Intune (basic, without content upload).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$DisplayName,
        [string]$Description = "",
        [Parameter(Mandatory)][string]$Publisher,
        [string]$InstallCommandLine = "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File Install-Drivers.ps1",
        [string]$UninstallCommandLine = "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -File uninstall.ps1",
        [string]$SetupFileName = "Install-Drivers.ps1"
    )

    $appBody = @{
        "@odata.type"         = "#microsoft.graph.win32LobApp"
        displayName           = $DisplayName
        description           = $Description
        publisher             = $Publisher
        installCommandLine    = $InstallCommandLine
        uninstallCommandLine  = $UninstallCommandLine
        installExperience     = @{
            runAsAccount         = "system"
            deviceRestartBehavior = "suppress"
        }
        setupFilePath         = $SetupFileName
        msiInformation        = $null
    }

    Write-DATLogEntry -Value "[Intune] Creating Win32 app: $DisplayName" -Severity 1
    return Invoke-DATGraphRequest -Uri "/deviceAppManagement/mobileApps" -Method POST -Body $appBody
}

function Get-DATIntuneAuthStatus {
    <#
    .SYNOPSIS
        Returns current auth status for UI display.
    #>
    [OutputType([hashtable])]
    param ()

    return @{
        IsAuthenticated = Test-DATIntuneAuth
        TenantId        = $script:IntuneTenantId
        Token           = $script:IntuneAuthToken
        ExpiresOn       = $script:IntuneTokenExpiry
        MinutesRemaining = if (Test-DATIntuneAuth) {
            [math]::Round(($script:IntuneTokenExpiry - (Get-Date)).TotalMinutes, 1)
        } else { 0 }
    }
}

#endregion Intune / Graph API

#region BIOS Password Management

function Set-DATBIOSPassword {
    <#
    .SYNOPSIS
        Encrypts a BIOS password using DPAPI (machine-scope) and stores it in the registry.
        Must be run as SYSTEM (e.g. via Intune proactive remediation) so that Install-BIOS.ps1
        (also running as SYSTEM on the same machine) can decrypt it.
    .PARAMETER Password
        The plaintext BIOS password to encrypt and store.
    .PARAMETER RegistryPath
        Registry path to store the encrypted password. Defaults to the DAT BIOS key.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Password,
        [string]$RegistryPath = 'HKLM:\SOFTWARE\DriverAutomationTool\BIOS'
    )

    try {
        if (-not (Test-Path $RegistryPath)) {
            New-Item -Path $RegistryPath -Force | Out-Null
        }

        # Convert to SecureString and encrypt via DPAPI (machine-bound when running as SYSTEM)
        $secureString = ConvertTo-SecureString -String $Password -AsPlainText -Force
        $encryptedBlob = ConvertFrom-SecureString -SecureString $secureString

        Set-ItemProperty -Path $RegistryPath -Name 'Password' -Value $encryptedBlob -Force
        Set-ItemProperty -Path $RegistryPath -Name 'PasswordSetDate' -Value (Get-Date -Format 'o') -Force

        Write-DATLogEntry -Value "[BIOS Password] Encrypted password stored at $RegistryPath" -Severity 1
        return $true
    } catch {
        Write-DATLogEntry -Value "[BIOS Password] Failed to store password: $($_.Exception.Message)" -Severity 3
        throw
    }
}

function Get-DATBIOSPassword {
    <#
    .SYNOPSIS
        Retrieves and decrypts the BIOS password from the registry using DPAPI.
        Must be run under the same account (SYSTEM) that encrypted the password.
    .PARAMETER RegistryPath
        Registry path where the encrypted password is stored.
    .OUTPUTS
        The plaintext BIOS password, or $null if not found.
    #>
    [CmdletBinding()]
    param (
        [string]$RegistryPath = 'HKLM:\SOFTWARE\DriverAutomationTool\BIOS'
    )

    try {
        $encryptedBlob = (Get-ItemProperty -Path $RegistryPath -Name 'Password' -ErrorAction SilentlyContinue).Password
        if ([string]::IsNullOrEmpty($encryptedBlob)) {
            return $null
        }

        $secureString = ConvertTo-SecureString -String $encryptedBlob -ErrorAction Stop
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    } catch {
        return $null
    }
}

function Remove-DATBIOSPassword {
    <#
    .SYNOPSIS
        Removes the stored BIOS password from the registry.
    #>
    [CmdletBinding()]
    param (
        [string]$RegistryPath = 'HKLM:\SOFTWARE\DriverAutomationTool\BIOS'
    )

    try {
        if (Test-Path $RegistryPath) {
            Remove-ItemProperty -Path $RegistryPath -Name 'Password' -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $RegistryPath -Name 'PasswordSetDate' -Force -ErrorAction SilentlyContinue
            Write-DATLogEntry -Value "[BIOS Password] Password removed from $RegistryPath" -Severity 1
        }
    } catch {
        Write-DATLogEntry -Value "[BIOS Password] Failed to remove password: $($_.Exception.Message)" -Severity 3
        throw
    }
}

#endregion BIOS Password Management

#region BIOS Catalog & Download

function Get-DATBiosCatalog {
    <#
    .SYNOPSIS
        Downloads and caches the DATBiosCatalog.json file. Returns the parsed catalog array.
        On subsequent calls within the same session, returns the cached copy.
    #>
    [CmdletBinding()]
    param (
        [switch]$Force
    )

    if ($global:BiosCatalog -and -not $Force) {
        Write-DATLogEntry -Value "[BIOS] Using cached BIOS catalog ($($global:BiosCatalog.Count) entries)" -Severity 1
        return $global:BiosCatalog
    }

    $catalogURL = "https://api.driverautomationtool.com/api/catalog/bios"
    $cachePath = Join-Path $global:TempDirectory "DATBiosCatalog.json"

    # Check if cached file is fresh (less than 24 hours old) to avoid unnecessary downloads
    $cacheIsFresh = (Test-Path $cachePath) -and ((Get-Date) - (Get-Item $cachePath).LastWriteTime).TotalHours -lt 24
    if ($cacheIsFresh -and -not $Force) {
        Write-DATLogEntry -Value "[BIOS] Using cached BIOS catalog (less than 24h old)" -Severity 1
    } else {
        Write-DATLogEntry -Value "[BIOS] Downloading BIOS catalog..." -Severity 1
        Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading BIOS catalog..." -Type String

        $downloaded = $false
        for ($i = 1; $i -le 3; $i++) {
            try {
                $proxyParams = Get-DATWebRequestProxy
                Invoke-WebRequest -Uri $catalogURL -OutFile $cachePath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop @proxyParams
                $downloaded = $true
                break
            } catch {
                Write-DATLogEntry -Value "[Warning] - BIOS catalog download attempt $i/3 failed: $($_.Exception.Message)" -Severity 2
                if ($i -lt 3) { Start-Sleep -Seconds 5 } else {
                    # If download fails but we have a cached copy, use it
                    if (Test-Path $cachePath) {
                        Write-DATLogEntry -Value "[BIOS] Using previously cached BIOS catalog" -Severity 2
                        $downloaded = $true
                    } else {
                        throw "BIOS catalog unavailable after 3 attempts: $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    if (-not (Test-Path $cachePath)) {
        throw "BIOS catalog file not found at $cachePath"
    }

    try {
        $global:BiosCatalog = @(Get-Content -Path $cachePath -Raw | ConvertFrom-Json)
        Write-DATLogEntry -Value "[BIOS] Catalog loaded: $($global:BiosCatalog.Count) entries" -Severity 1
        return $global:BiosCatalog
    } catch {
        throw "Failed to parse BIOS catalog JSON: $($_.Exception.Message)"
    }
}

function Find-DATBiosPackage {
    <#
    .SYNOPSIS
        Searches the BIOS catalog for a matching entry by OEM and baseboard values.
        Returns the best match (latest ReleaseDate) or $null if no match found.
        For Acer, uses the Acer XML catalog directly since BIOS entries are embedded there.
    .PARAMETER OEM
        Manufacturer name (Dell, HP, Lenovo, Acer).
    .PARAMETER Baseboards
        Comma-separated baseboard/SystemID values from the model definition.
    .PARAMETER Catalog
        The BIOS catalog array (from Get-DATBiosCatalog). If omitted, calls Get-DATBiosCatalog.
        Not used for Acer (which has its own XML catalog).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$OEM,
        [Parameter(Mandatory)][string]$Baseboards,
        [array]$Catalog
    )

    # ── Acer: BIOS entries live in the Acer XML catalog, not the JSON BIOS catalog ──
    if ($OEM -eq 'Acer') {
        $modelBoards = @($Baseboards -split '[,;\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($modelBoards.Count -eq 0) {
            Write-DATLogEntry -Value "[BIOS] No baseboard/model values provided -- cannot match Acer BIOS" -Severity 2
            return $null
        }
        # Verbose -- suppressed to reduce log noise during bulk model refresh

        # Download/cache the Acer XML catalog
        $acerCatalogUrl = 'https://global-download.acer.com/supportfiles/files/support/sourcefile/msepm/AcerCatalog.xml'
        # Also try the OEM links XML if available
        if ($null -ne $global:OEMLinks) {
            $linkUrl = ($global:OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match 'Acer' }).Link |
                Where-Object { $_.Type -eq 'XMLSource' } | Select-Object -ExpandProperty URL -First 1
            if (-not [string]::IsNullOrEmpty($linkUrl)) { $acerCatalogUrl = $linkUrl }
        }

        $acerFile = [string]($acerCatalogUrl | Split-Path -Leaf)
        $acerFilePath = Join-Path $global:TempDirectory $acerFile

        if (-not (Test-Path $acerFilePath)) {
            Write-DATLogEntry -Value "[BIOS] Downloading Acer catalog for BIOS lookup..." -Severity 1
            try {
                $proxyParams = Get-DATWebRequestProxy
                Invoke-WebRequest -Uri $acerCatalogUrl -OutFile $acerFilePath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop @proxyParams
            } catch {
                Write-DATLogEntry -Value "[BIOS] Failed to download Acer catalog: $($_.Exception.Message)" -Severity 3
                return $null
            }
        } else {
            Write-DATLogEntry -Value "[BIOS] Using cached Acer catalog: $acerFilePath" -Severity 1
        }

        try {
            [xml]$acerXml = Get-Content -Path $acerFilePath -ErrorAction Stop
        } catch {
            Write-DATLogEntry -Value "[BIOS] Failed to parse Acer catalog XML: $($_.Exception.Message)" -Severity 3
            return $null
        }

        $acerModels = $acerXml.ModelList.Model
        if ($null -eq $acerModels -or @($acerModels).Count -eq 0) {
            Write-DATLogEntry -Value "[BIOS] Acer catalog contains no model entries" -Severity 2
            return $null
        }

        # Match by model name -- try exact then partial
        $matched = $null
        foreach ($board in $modelBoards) {
            $matched = $acerModels | Where-Object { $_.name -eq $board } | Select-Object -First 1
            if ($null -ne $matched) { break }
        }
        if ($null -eq $matched) {
            foreach ($board in $modelBoards) {
                $matched = $acerModels | Where-Object { $_.name -like "*$board*" } | Select-Object -First 1
                if ($null -ne $matched) { break }
            }
        }

        if ($null -eq $matched -or $null -eq $matched.BIOS) {
            Write-DATLogEntry -Value "[BIOS] No Acer BIOS entry found for models: $($modelBoards -join ', ')" -Severity 2
            return $null
        }

        # Extract BIOS URL and version from the <BIOS version="x.xx">URL</BIOS> element
        $biosUrl = $matched.BIOS.'#text'
        if ([string]::IsNullOrEmpty($biosUrl)) { $biosUrl = [string]$matched.BIOS }
        $biosVersion = $matched.BIOS.version

        if ([string]::IsNullOrEmpty($biosUrl)) {
            Write-DATLogEntry -Value "[BIOS] Acer BIOS entry for '$($matched.name)' has no download URL" -Severity 2
            return $null
        }

        # FileName must match what Invoke-DATContentDownload saves (query string stripped)
        $fileName = ($biosUrl -split '\?')[0] | Split-Path -Leaf
        Write-DATLogEntry -Value "[BIOS] Matched Acer: $($matched.name) -- BIOS Version $biosVersion" -Severity 1

        return [PSCustomObject]@{
            DisplayName      = "Acer $($matched.name) BIOS"
            Version          = $biosVersion
            DownloadURL      = $biosUrl
            FileName         = $fileName
            FileHash         = $null
            HashMethod       = $null
            ReleaseDate      = $null
            Classification   = 'BIOS'
            MinimumVersion   = $null
            SupportedDevices = $matched.name
        }
    }

    # ── Non-Acer OEMs: use the JSON BIOS catalog ──
    if (-not $Catalog -or $Catalog.Count -eq 0) {
        $Catalog = Get-DATBiosCatalog
    }

    # Split model baseboards (comma, space, or semicolon separated) into a lookup set, trimmed
    $modelBoards = @($Baseboards -split '[,;\s]+' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })

    if ($modelBoards.Count -eq 0) {
        Write-DATLogEntry -Value "[BIOS] No baseboard values provided -- cannot match BIOS" -Severity 2
        return $null
    }

    # Verbose -- suppressed to reduce log noise during bulk model refresh

    # Filter catalog by OEM and non-null download URL
    $oemEntries = @($Catalog | Where-Object {
        $_.Manufacturer -eq $OEM -and -not [string]::IsNullOrEmpty($_.DownloadURL)
    })

    if ($oemEntries.Count -eq 0) {
        Write-DATLogEntry -Value "[BIOS] No $OEM entries with download URLs found in catalog" -Severity 2
        return $null
    }

    # Find entries where any of the model's baseboards match any of the entry's SupportedDevices
    $matches = @()
    foreach ($entry in $oemEntries) {
        if ([string]::IsNullOrEmpty($entry.SupportedDevices)) { continue }
        # SupportedDevices is semicolon-delimited
        $entryDevices = @($entry.SupportedDevices -split ';' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
        foreach ($board in $modelBoards) {
            if ($board -in $entryDevices) {
                $matches += $entry
                break
            }
        }
    }

    if ($matches.Count -eq 0) {
        # No match -- skip logging to reduce noise during bulk refresh
        return $null
    }

    # Pick the entry with the latest ReleaseDate
    $best = $matches | Sort-Object { try { [datetime]$_.ReleaseDate } catch { [datetime]::MinValue } } -Descending | Select-Object -First 1
    $fileName = ($best.DownloadURL -split '/')[-1]

    Write-DATLogEntry -Value "[BIOS] Matched: $($best.DisplayName) -- Version $($best.Version), Released $($best.ReleaseDate)" -Severity 1

    return [PSCustomObject]@{
        DisplayName      = $best.DisplayName
        Version          = $best.Version
        DownloadURL      = $best.DownloadURL
        FileName         = $fileName
        FileHash         = $best.FileHash
        HashMethod       = $best.HashMethod
        ReleaseDate      = $best.ReleaseDate
        Classification   = $best.Classification
        MinimumVersion   = $best.MinimumVersion
        SupportedDevices = $best.SupportedDevices
    }
}

function Start-DATBiosDownload {
    <#
    .SYNOPSIS
        Downloads a BIOS executable from the OEM CDN and verifies its hash.
        Returns the local file path on success, or $null on failure.
    .PARAMETER BiosEntry
        The PSCustomObject from Find-DATBiosPackage containing DownloadURL, FileName, FileHash, HashMethod.
    .PARAMETER DownloadDestination
        Directory to store the downloaded file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]$BiosEntry,
        [Parameter(Mandatory)][string]$DownloadDestination
    )

    if (-not (Test-Path $DownloadDestination)) {
        New-Item -Path $DownloadDestination -ItemType Directory -Force | Out-Null
    }

    $destFile = Join-Path $DownloadDestination $BiosEntry.FileName

    # Check if already downloaded with correct hash
    if (Test-Path $destFile) {
        if (-not [string]::IsNullOrEmpty($BiosEntry.FileHash) -and -not [string]::IsNullOrEmpty($BiosEntry.HashMethod)) {
            $algo = switch ($BiosEntry.HashMethod) {
                'SHA256' { 'SHA256' }
                'MD5'    { 'MD5' }
                default  { 'SHA256' }
            }
            $existingHash = (Get-FileHash -Path $destFile -Algorithm $algo -ErrorAction SilentlyContinue).Hash
            if ($existingHash -eq $BiosEntry.FileHash) {
                Write-DATLogEntry -Value "[BIOS] File already cached with valid hash: $destFile" -Severity 1
                return $destFile
            } else {
                Write-DATLogEntry -Value "[BIOS] Cached file hash mismatch -- re-downloading" -Severity 2
                Remove-Item $destFile -Force -ErrorAction SilentlyContinue
            }
        } else {
            Write-DATLogEntry -Value "[BIOS] File already cached (no hash to verify): $destFile" -Severity 1
            return $destFile
        }
    }

    Write-DATLogEntry -Value "[BIOS] Downloading: $($BiosEntry.DownloadURL)" -Severity 1
    Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading BIOS update: $($BiosEntry.FileName)..." -Type String
    Set-DATRegistryValue -Name "RunningMode" -Value "Download" -Type String

    # Use Invoke-DATContentDownload (existing Curl/HttpClient download with progress tracking)
    try {
        Invoke-DATContentDownload -DownloadURL $BiosEntry.DownloadURL -DownloadDestination $DownloadDestination
    } catch {
        Write-DATLogEntry -Value "[BIOS] Download failed: $($_.Exception.Message)" -Severity 3
        return $null
    }

    if (-not (Test-Path $destFile)) {
        Write-DATLogEntry -Value "[BIOS] Downloaded file not found: $destFile" -Severity 3
        return $null
    }

    $fileSizeMB = [math]::Round((Get-Item $destFile).Length / 1MB, 2)
    Write-DATLogEntry -Value "[BIOS] Download complete: $destFile ($fileSizeMB MB)" -Severity 1

    # Verify hash if available
    if (-not [string]::IsNullOrEmpty($BiosEntry.FileHash) -and -not [string]::IsNullOrEmpty($BiosEntry.HashMethod)) {
        $algo = switch ($BiosEntry.HashMethod) {
            'SHA256' { 'SHA256' }
            'MD5'    { 'MD5' }
            default  { 'SHA256' }
        }
        $downloadedHash = (Get-FileHash -Path $destFile -Algorithm $algo -ErrorAction SilentlyContinue).Hash
        if ($downloadedHash -eq $BiosEntry.FileHash) {
            Write-DATLogEntry -Value "[BIOS] Hash verified ($algo): $downloadedHash" -Severity 1
        } else {
            Write-DATLogEntry -Value "[BIOS] Hash mismatch! Expected: $($BiosEntry.FileHash), Got: $downloadedHash" -Severity 3
            Remove-Item $destFile -Force -ErrorAction SilentlyContinue
            return $null
        }
    }

    return $destFile
}

function Get-DATFlash64W {
    <#
    .SYNOPSIS
        Ensures Flash64W.exe is available in a target directory.
        If not already present, downloads the Flash64W ZIP package from Dell,
        extracts it, and copies Flash64W.exe to the destination.
        The ZIP contains Flash64W.exe in a subfolder.
    .PARAMETER DestinationDir
        Directory where Flash64W.exe should be placed.
    .OUTPUTS
        [bool] $true if Flash64W.exe is present in DestinationDir after the call, $false otherwise.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$DestinationDir
    )

    # Already present -- nothing to do
    $existing = Get-ChildItem -Path $DestinationDir -Filter 'Flash64W.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) {
        Write-DATLogEntry -Value "[Flash64W] Already present: $($existing.FullName)" -Severity 1
        # Ensure it is in the root of DestinationDir (not buried in a sub-folder)
        if ($existing.DirectoryName -ne $DestinationDir) {
            Copy-Item -Path $existing.FullName -Destination $DestinationDir -Force
            Write-DATLogEntry -Value "[Flash64W] Copied to staging root: $DestinationDir\Flash64W.exe" -Severity 1
        }
        return $true
    }

    # Flash64W.exe not found -- download the Dell Flash64W ZIP package
    $flash64Url   = 'https://dl.dell.com/FOLDER12288556M/1/FlashVer3.3.28.zip'
    $tempDir      = Join-Path $env:TEMP 'DAT_Flash64W'
    $zipFile      = Join-Path $tempDir 'FlashVer3.3.28.zip'
    $zipExtract   = Join-Path $tempDir 'Extracted'

    Write-DATLogEntry -Value "[Flash64W] Flash64W.exe not found -- downloading package" -Severity 1
    Write-DATLogEntry -Value "[Flash64W] URL: $flash64Url" -Severity 1

    if (-not (Test-Path $tempDir)) { New-Item -Path $tempDir -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $zipExtract)) { New-Item -Path $zipExtract -ItemType Directory -Force | Out-Null }

    # Download (Dell requires browser-like headers)
    try {
        $proxyParams = Get-DATWebRequestProxy
        if ($proxyParams -isnot [hashtable]) { $proxyParams = @{} }
        $webHeaders = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }
        Invoke-WebRequest -Uri $flash64Url -OutFile $zipFile -UseBasicParsing -TimeoutSec 120 -Headers $webHeaders @proxyParams -ErrorAction Stop
        Write-DATLogEntry -Value "[Flash64W] Download complete: $([math]::Round((Get-Item $zipFile).Length / 1KB, 1)) KB" -Severity 1
    } catch {
        Write-DATLogEntry -Value "[Flash64W] Download failed: $($_.Exception.Message)" -Severity 3
        return $false
    }

    # Extract ZIP and locate Flash64W.exe (may be in a subfolder)
    $extracted = $false
    try {
        Write-DATLogEntry -Value "[Flash64W] Extracting ZIP archive" -Severity 1
        Expand-Archive -Path $zipFile -DestinationPath $zipExtract -Force -ErrorAction Stop
        $flash64File = Get-ChildItem -Path $zipExtract -Filter 'Flash64W.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($flash64File) { $extracted = $true }
    } catch {
        Write-DATLogEntry -Value "[Flash64W] ZIP extraction failed: $($_.Exception.Message)" -Severity 3
    }

    if ($extracted -and $flash64File) {
        Copy-Item -Path $flash64File.FullName -Destination $DestinationDir -Force
        Write-DATLogEntry -Value "[Flash64W] Flash64W.exe v3.3.28 copied to $DestinationDir" -Severity 1
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        return $true
    }

    # Clean up temp download
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-DATLogEntry -Value "[Flash64W] Extraction failed -- Flash64W.exe could not be obtained" -Severity 3
    return $false
}

function Invoke-DATBiosPackaging {
    <#
    .SYNOPSIS
        Packages a downloaded BIOS executable for deployment.
        For Dell, the exe is self-contained and placed directly.
        For HP and Lenovo, the exe is extracted first to expose internal flash utilities.
        When SkipWim is set (ConfigMgr), extracted files are staged directly.
        When SkipWim is not set (Intune), content is captured into a WIM.
    .PARAMETER BiosFilePath
        Path to the downloaded BIOS .exe file.
    .PARAMETER OEM
        Manufacturer name (Dell, HP, Lenovo).
    .PARAMETER Model
        Model name for folder structure.
    .PARAMETER Version
        BIOS version string.
    .PARAMETER PackageDestination
        Root package destination path.
    .PARAMETER SkipWim
        When set, skips WIM compression and returns the staging directory path.
        Used for ConfigMgr deployments where raw files are preferred.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$BiosFilePath,
        [Parameter(Mandatory)][string]$OEM,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$PackageDestination,
        [switch]$SkipWim
    )

    # BIOS packages are OS-agnostic -- use "BIOS" as the subfolder instead of OS name.
    # Build the WIM in the Temporary Storage Path, then copy to the Package Store --
    # same pattern as Invoke-DATDriverFilePackaging (avoids writing temp data into the
    # package store and handles UNC destinations where DISM cannot create WIMs directly).
    $localWorkDir = Join-Path $global:TempDirectory "BIOSBuild\$OEM\$Model"
    $biosStaging = Join-Path $localWorkDir "Packaged\$OEM\$Model\BIOS"
    $extractDir = Join-Path $global:TempDirectory "BIOSExtract\$OEM\$Model"
    $wimFile = Join-Path $biosStaging "DriverPackage.wim"
    $destBiosFolder = Join-Path $PackageDestination "$OEM\$Model\BIOS"

    # Clean previous
    foreach ($dir in @($localWorkDir, $biosStaging, $extractDir)) {
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    Set-DATRegistryValue -Name "RunningMode" -Value "Packaging" -Type String
    Set-DATRegistryValue -Name "RunningMessage" -Value "Packaging BIOS update for $OEM $Model..." -Type String

    switch ($OEM) {
        'Acer' {
            # Acer BIOS packages are ZIP archives -- extract to expose BIOS files
            Write-DATLogEntry -Value "[BIOS] Acer: Extracting BIOS ZIP archive" -Severity 1
            try {
                Expand-Archive -Path $BiosFilePath -DestinationPath $extractDir -Force -ErrorAction Stop
            } catch {
                throw "Acer BIOS extraction failed: $($_.Exception.Message)"
            }
        }
        'Dell' {
            # Dell BIOS exe is self-contained -- copy directly for all deployment modes.
            # The exe handles its own flash process; no extraction is needed.
            Write-DATLogEntry -Value "[BIOS] Dell: Staging self-contained BIOS updater" -Severity 1
            Copy-Item -Path $BiosFilePath -Destination $extractDir -Force
        }
        'HP' {
            # HP BIOS SoftPaq is a self-extracting archive -- use the same expansion flags
            # as the HP driver SoftPaq flow to expose HPFirmwareUpdRec64.exe / HPBIOSUPDREC64.exe etc.
            Write-DATLogEntry -Value "[BIOS] HP: Extracting SoftPaq to expose flash utilities" -Severity 1
            try {
                $extractProc = Start-Process -FilePath $BiosFilePath -ArgumentList "-e", "-f `"$extractDir`"", "-s" `
                    -WindowStyle Hidden -PassThru
                if (-not $extractProc.WaitForExit(300000)) {
                    try { $extractProc.Kill() } catch {}
                    throw "HP BIOS extraction timed out after 5 minutes"
                }
                if ($extractProc.ExitCode -ne 0) {
                    Write-DATLogEntry -Value "[BIOS] HP extraction exited with code $($extractProc.ExitCode)" -Severity 2
                }
            } catch {
                throw "HP BIOS extraction failed: $($_.Exception.Message)"
            }
        }
        'Lenovo' {
            # Lenovo BIOS packages are Inno Setup self-extracting installers containing
            # the flash utilities (Flash64.cmd, WinUPTP64.exe, etc.).
            # The Inno Setup post-install [Run] section launches the firmware update utility,
            # so we cannot use /VERYSILENT alone -- it would trigger a BIOS flash.
            # Instead we start the extraction silently, wait for files to appear in the
            # target directory, then kill the entire process tree to prevent the flash.
            Write-DATLogEntry -Value "[BIOS] Lenovo: Extracting Inno Setup BIOS package to expose flash utilities" -Severity 1
            try {
                Unblock-File -Path $BiosFilePath -ErrorAction SilentlyContinue
                $extractProc = Start-Process -FilePath $BiosFilePath `
                    -ArgumentList "/VERYSILENT /DIR=`"$extractDir`" /SP- /SUPPRESSMSGBOXES /NORESTART" `
                    -WindowStyle Hidden -PassThru

                # Poll until flash-related files appear in the extract directory, confirming
                # that Inno Setup has finished extracting and is about to run [Run] entries.
                $maxWaitSec = 120
                $elapsed = 0
                $extractionDone = $false
                while ($elapsed -lt $maxWaitSec -and -not $extractProc.HasExited) {
                    $extractedFiles = @(Get-ChildItem -Path $extractDir -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match '\.(cmd|cap|rom|bin|exe)$' -and $_.Name -ne (Split-Path $BiosFilePath -Leaf) })
                    if ($extractedFiles.Count -ge 2) {
                        $extractionDone = $true
                        Write-DATLogEntry -Value "[BIOS] Lenovo: Extraction complete -- $($extractedFiles.Count) files detected, terminating installer" -Severity 1
                        break
                    }
                    Start-Sleep -Milliseconds 500
                    $elapsed += 0.5
                }

                # Kill the Inno Setup process tree to prevent the BIOS flash from executing
                if (-not $extractProc.HasExited) {
                    try {
                        # Kill child processes first (wFlashGUIX64.exe, AFUWINx64.EXE, etc.)
                        $children = Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $($extractProc.Id)" -ErrorAction SilentlyContinue
                        foreach ($child in $children) {
                            try { Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
                            Write-DATLogEntry -Value "[BIOS] Lenovo: Killed child process $($child.Name) (PID $($child.ProcessId))" -Severity 1
                        }
                        $extractProc.Kill()
                        Write-DATLogEntry -Value "[BIOS] Lenovo: Killed Inno Setup installer process" -Severity 1
                    } catch {}
                }

                if (-not $extractionDone) {
                    # Process exited on its own -- check if files were extracted
                    $extractedFiles = @(Get-ChildItem -Path $extractDir -File -ErrorAction SilentlyContinue)
                    if ($extractedFiles.Count -lt 2) {
                        throw "Lenovo BIOS extraction produced insufficient files (found: $($extractedFiles.Count))"
                    }
                }

                # Clean up: remove uninstall artifacts left by Inno Setup
                $uninstDir = Join-Path $extractDir 'unins*'
                Get-ChildItem -Path $extractDir -Filter 'unins*' -File -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            } catch {
                throw "Lenovo BIOS extraction failed: $($_.Exception.Message)"
            }
        }
        default {
            # Unknown OEM -- place exe directly
            Write-DATLogEntry -Value "[BIOS] $OEM : Staging BIOS file directly (unknown extraction method)" -Severity 2
            Copy-Item -Path $BiosFilePath -Destination $extractDir -Force
        }
    }

    # Verify extraction produced files
    $extractedFiles = @(Get-ChildItem -Path $extractDir -Recurse -File -ErrorAction SilentlyContinue)
    if ($extractedFiles.Count -eq 0) {
        throw "BIOS extraction produced no files for $OEM $Model"
    }
    Write-DATLogEntry -Value "[BIOS] Extracted $($extractedFiles.Count) files" -Severity 1

    if ($SkipWim) {
        # ConfigMgr: return the temp extraction directory so New-DATConfigMgrPkg can
        # copy its contents into the final versioned path ($PackagePath\$OEM\$Model\BIOS\$Version).
        # Do NOT copy to the package store here -- that would place files at the unversioned
        # $OEM\$Model\BIOS level, and ConfigMgr would then try to copy that into a child
        # directory of itself ($OEM\$Model\BIOS\$Version), causing a self-overwrite error.
        Write-DATLogEntry -Value "[BIOS] Staging $($extractedFiles.Count) files in temp: $extractDir (no WIM)" -Severity 1
        Set-DATRegistryValue -Name "RunningMessage" -Value "Staging BIOS files for $OEM $Model..." -Type String
        return [string]$extractDir
    }

    # Intune: Capture extracted content into WIM using the preferred engine
    Write-DATLogEntry -Value "[BIOS] Creating WIM: $wimFile" -Severity 1
    Set-DATRegistryValue -Name "RunningMessage" -Value "Creating BIOS WIM for $OEM $Model..." -Type String

    $wimEngine = (Get-ItemProperty -Path $global:RegPath -Name 'WimEngine' -ErrorAction SilentlyContinue).WimEngine
    if ([string]::IsNullOrEmpty($wimEngine) -or $wimEngine -notin @('dism','wimlib','7zip')) { $wimEngine = 'dism' }

    try {
        if ($wimEngine -eq 'wimlib') {
            $wimlibExe = Join-Path (Join-Path $global:ToolsDirectory 'Wimlib') 'wimlib-imagex.exe'
            if (Test-Path $wimlibExe) {
                Write-DATLogEntry -Value "[BIOS] Using wimlib-imagex for WIM creation" -Severity 1
                $proc = Start-Process -FilePath $wimlibExe `
                    -ArgumentList "capture `"$extractDir`" `"$wimFile`" `"BIOS - $OEM $Model`" --compress=XPRESS --threads=0 --no-acls" `
                    -WindowStyle Hidden -Wait -PassThru
                if ($proc.ExitCode -ne 0) { throw "wimlib-imagex exited with code $($proc.ExitCode)" }
            } else {
                Write-DATLogEntry -Value "[BIOS] wimlib not found -- falling back to DISM" -Severity 2
                New-WindowsImage -ImagePath $wimFile -CapturePath $extractDir -Name "BIOS - $OEM $Model" -Description "BIOS $Version" -ErrorAction Stop | Out-Null
            }
        } elseif ($wimEngine -eq '7zip') {
            $7zipExe = $null
            foreach ($c in @((Join-Path $env:ProgramFiles '7-Zip\7z.exe'), (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'))) {
                if (Test-Path $c) { $7zipExe = $c; break }
            }
            if (-not $7zipExe) { try { $7zipExe = (Get-Command '7z.exe' -ErrorAction Stop).Source } catch { } }
            if (-not [string]::IsNullOrEmpty($7zipExe) -and (Test-Path $7zipExe)) {
                Write-DATLogEntry -Value "[BIOS] Using 7-Zip for WIM creation" -Severity 1
                $proc = Start-Process -FilePath $7zipExe -ArgumentList "a -twim `"$wimFile`" `"$extractDir\*`" -mx=1" `
                    -WindowStyle Hidden -Wait -PassThru
                if ($proc.ExitCode -ne 0) { throw "7-Zip exited with code $($proc.ExitCode)" }
            } else {
                Write-DATLogEntry -Value "[BIOS] 7-Zip not found -- falling back to DISM" -Severity 2
                New-WindowsImage -ImagePath $wimFile -CapturePath $extractDir -Name "BIOS - $OEM $Model" -Description "BIOS $Version" -ErrorAction Stop | Out-Null
            }
        } else {
            New-WindowsImage -ImagePath $wimFile -CapturePath $extractDir -Name "BIOS - $OEM $Model" -Description "BIOS $Version" -ErrorAction Stop | Out-Null
        }
        $wimSizeMB = [math]::Round((Get-Item $wimFile).Length / 1MB, 2)
        Write-DATLogEntry -Value "[BIOS] WIM created: $wimSizeMB MB" -Severity 1
    } catch {
        throw "BIOS WIM creation failed: $($_.Exception.Message)"
    }

    # Copy WIM from temp to the Package Store destination
    if (Test-Path $destBiosFolder) { Remove-Item $destBiosFolder -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -Path $destBiosFolder -ItemType Directory -Force | Out-Null
    $destWimFile = Join-Path $destBiosFolder "DriverPackage.wim"
    Write-DATLogEntry -Value "[BIOS] Copying WIM to package destination: $destWimFile" -Severity 1
    Copy-Item -Path $wimFile -Destination $destWimFile -Force
    Write-DATLogEntry -Value "[BIOS] WIM copied to package destination successfully" -Severity 1

    # Clean up temp directories
    Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $localWorkDir -Recurse -Force -ErrorAction SilentlyContinue

    return [string]$destWimFile
}

#endregion BIOS Catalog & Download

#region Telemetry

# Session-scoped cache for the remote config (fetched once per module load / tool session)
$script:DATTelemetryConfig = $null

function Get-DATTelemetryConfig {
    <#
    .SYNOPSIS
        Fetches and caches the remote dat-config.json from GitHub.
        Returns $null if the fetch fails or telemetry is disabled remotely.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [switch]$Force
    )

    if ($script:DATTelemetryConfig -and -not $Force) {
        return $script:DATTelemetryConfig
    }

    $configUrl = 'https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/refs/heads/master/Data/DATAPIConfig.json'
    try {
        $proxyParams = Get-DATWebRequestProxy
        if ($proxyParams -isnot [hashtable]) { $proxyParams = @{} }
        $response = Invoke-RestMethod -Uri $configUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop @proxyParams
        $script:DATTelemetryConfig = $response
        Write-DATLogEntry -Value "[Telemetry] Remote config loaded (apiBaseUrl: $($response.apiBaseUrl))" -Severity 1
        return $script:DATTelemetryConfig
    } catch {
        Write-DATLogEntry -Value "[Telemetry] Failed to fetch remote config: $($_.Exception.Message)" -Severity 2
        return $null
    }
}

function Test-DATTelemetryEnabled {
    <#
    .SYNOPSIS
        Returns $true when telemetry is permitted (local opt-in, remote enabled, version check).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param ()

    # 1. Local opt-in (TelemetryOptOut DWord = 1 means opted IN per existing UI convention)
    $regOptOut = (Get-ItemProperty -Path $global:RegPath -Name 'TelemetryOptOut' -ErrorAction SilentlyContinue).TelemetryOptOut
    if ($regOptOut -ne 1) {
        Write-DATLogEntry -Value "[Telemetry] Disabled -- TelemetryOptOut registry value is '$regOptOut' (expected 1) at $($global:RegPath)" -Severity 2
        return $false
    }

    # 2. Remote kill switch
    $config = Get-DATTelemetryConfig
    if ($null -eq $config) { return $false }
    if (-not $config.telemetryEnabled) { return $false }

    # 3. Minimum version check
    if (-not [string]::IsNullOrEmpty($config.minimumDatVersion)) {
        try {
            if ([version]$global:ScriptRelease -lt [version]$config.minimumDatVersion) {
                Write-DATLogEntry -Value "[Telemetry] DAT version $($global:ScriptRelease) is below minimum $($config.minimumDatVersion) -- skipping" -Severity 2
                return $false
            }
        } catch { }
    }

    return $true
}

function Get-DATTelemetryId {
    <#
    .SYNOPSIS
        Returns the persistent telemetry GUID from the registry, or $null if not set.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param ()
    return (Get-ItemProperty -Path $global:RegPath -Name 'TelemetryGuid' -ErrorAction SilentlyContinue).TelemetryGuid
}

function Send-DATTelemetry {
    <#
    .SYNOPSIS
        Posts a telemetry payload to the specified API endpoint.
    .PARAMETER Endpoint
        Relative endpoint path from the config (e.g. 'telemetry/driver-report').
    .PARAMETER Body
        Hashtable to serialize as JSON and POST.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter(Mandatory)]
        [hashtable]$Body
    )

    if (-not (Test-DATTelemetryEnabled)) {
        Write-DATLogEntry -Value "[Telemetry] Skipped POST $Endpoint -- telemetry not enabled" -Severity 2
        return
    }

    $config = Get-DATTelemetryConfig
    if ($null -eq $config -or [string]::IsNullOrEmpty($config.apiBaseUrl)) { return }

    $url = "$($config.apiBaseUrl)/$Endpoint"
    $json = $Body | ConvertTo-Json -Depth 5 -Compress

    try {
        $proxyParams = Get-DATWebRequestProxy
        if ($proxyParams -isnot [hashtable]) { $proxyParams = @{} }
        $null = Invoke-RestMethod -Uri $url -Method POST -Body $json -ContentType 'application/json' `
            -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop @proxyParams
        Write-DATLogEntry -Value "[Telemetry] POST $Endpoint -- success" -Severity 1
        Write-DATLogEntry -Value "[Telemetry] Payload: $json" -Severity 1
        if ($global:ExecutionMode -eq 'Scheduled Task') {
            Write-Host "[Telemetry] POST $Endpoint -- success"
            Write-Host "[Telemetry] Payload: $json"
        }
    } catch {
        Write-DATLogEntry -Value "[Telemetry] POST $Endpoint -- failed: $($_.Exception.Message)" -Severity 2
        if ($global:ExecutionMode -eq 'Scheduled Task') {
            Write-Host "[Telemetry] POST $Endpoint -- failed: $($_.Exception.Message)"
        }
    }
}

function Get-DATPackageHash {
    <#
    .SYNOPSIS
        Computes the MD5 hash of a file. Returns the hex string, or $null on failure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][string]$FilePath
    )
    if (-not (Test-Path -LiteralPath $FilePath)) { return $null }
    try {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $stream = [System.IO.File]::OpenRead($FilePath)
        try {
            $hashBytes = $md5.ComputeHash($stream)
            return [BitConverter]::ToString($hashBytes).Replace('-', '')
        } finally {
            $stream.Close()
            $md5.Dispose()
        }
    } catch {
        Write-DATLogEntry -Value "[Telemetry] MD5 hash failed for $FilePath`: $($_.Exception.Message)" -Severity 2
        return $null
    }
}

function Send-DATDriverReport {
    <#
    .SYNOPSIS
        Submits a driver packaging report to the telemetry API.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Manufacturer,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$OSVersion,
        [Parameter(Mandatory)][string]$OSArchitecture,
        [Parameter(Mandatory)][string]$Platform,
        [Parameter(Mandatory)][ValidateSet('Success','Failed','Warning')][string]$Status,
        [string]$PackageVersion,
        [double]$DownloadTime,
        [long]$PackageSize,
        [string]$PackageHash
    )

    $config = Get-DATTelemetryConfig
    if ($null -eq $config) { return }

    $body = @{
        telemetryId    = Get-DATTelemetryId
        manufacturer   = $Manufacturer
        model          = $Model
        osVersion      = $OSVersion
        osArchitecture = $OSArchitecture
        platform       = $Platform
        packageType    = 'Drivers'
        status         = $Status
        datVersion     = [string]$global:ScriptRelease
        executionMode  = $global:ExecutionMode
    }
    if (-not [string]::IsNullOrEmpty($PackageVersion)) { $body['packageVersion'] = $PackageVersion }
    if ($DownloadTime -gt 0) { $body['downloadTime'] = $DownloadTime }
    if ($PackageSize -gt 0)  { $body['packageSize']  = $PackageSize }
    if (-not [string]::IsNullOrEmpty($PackageHash))    { $body['packageHash']  = $PackageHash; $body['hashMethod'] = 'MD5' }

    Send-DATTelemetry -Endpoint $config.endpoints.driverReport -Body $body
}

function Send-DATBiosReport {
    <#
    .SYNOPSIS
        Submits a BIOS packaging report to the telemetry API.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Manufacturer,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Platform,
        [Parameter(Mandatory)][ValidateSet('Success','Failed','Warning')][string]$Status,
        [string]$CurrentBiosVersion,
        [string]$TargetBiosVersion,
        [bool]$BiosPasswordProtected = $false,
        [string]$PackageHash
    )

    $config = Get-DATTelemetryConfig
    if ($null -eq $config) { return }

    $body = @{
        telemetryId           = Get-DATTelemetryId
        manufacturer          = $Manufacturer
        model                 = $Model
        platform              = $Platform
        status                = $Status
        biosPasswordProtected = $BiosPasswordProtected
        datVersion            = [string]$global:ScriptRelease
        executionMode         = $global:ExecutionMode
    }
    if (-not [string]::IsNullOrEmpty($CurrentBiosVersion)) { $body['currentBiosVersion'] = $CurrentBiosVersion }
    if (-not [string]::IsNullOrEmpty($TargetBiosVersion))  { $body['targetBiosVersion']  = $TargetBiosVersion }
    if (-not [string]::IsNullOrEmpty($PackageHash))        { $body['packageHash']  = $PackageHash; $body['hashMethod'] = 'MD5' }

    Send-DATTelemetry -Endpoint $config.endpoints.biosReport -Body $body
}

function Send-DATReportIssue {
    <#
    .SYNOPSIS
        Reports or clears an issue against a driver or BIOS package version.
    .DESCRIPTION
        Increments or decrements the reportCount on all DriverReports/BIOSReports rows
        matching the given Manufacturer + Model + PackageVersion.
    .PARAMETER Type
        'driver' or 'bios'.
    .PARAMETER Action
        'increment' to report an issue, 'decrement' to clear a previously reported issue.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][ValidateSet('driver', 'bios')][string]$Type,
        [Parameter(Mandatory)][string]$Manufacturer,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$PackageVersion,
        [ValidateSet('increment', 'decrement')]
        [string]$Action = 'increment'
    )

    $config = Get-DATTelemetryConfig
    if ($null -eq $config) { return }

    $body = @{
        type            = $Type
        manufacturer    = $Manufacturer
        model           = $Model
        packageVersion  = $PackageVersion
        action          = $Action
    }

    Send-DATTelemetry -Endpoint $config.endpoints.reportIssue -Body $body
}

function Send-DATSummaryReport {
    <#
    .SYNOPSIS
        Submits a session summary to the telemetry API.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][int]$DriverPackagesCreated,
        [Parameter(Mandatory)][int]$BiosPackagesCreated,
        [Parameter(Mandatory)][int]$ModelsProcessed,
        [Parameter(Mandatory)][string]$Platform,
        [long]$TotalDownloadSize,
        [string]$ExecutionMode
    )

    $config = Get-DATTelemetryConfig
    if ($null -eq $config) { return }

    $body = @{
        telemetryId           = Get-DATTelemetryId
        driverPackagesCreated = $DriverPackagesCreated
        biosPackagesCreated   = $BiosPackagesCreated
        modelsProcessed       = $ModelsProcessed
        platform              = $Platform
        toolVersion           = [string]$global:ScriptRelease
        datVersion            = [string]$global:ScriptRelease
        executionMode         = if (-not [string]::IsNullOrEmpty($ExecutionMode)) { $ExecutionMode } else { $global:ExecutionMode }
    }
    if ($TotalDownloadSize -gt 0) { $body['totalDownloadSize'] = $TotalDownloadSize }

    Send-DATTelemetry -Endpoint $config.endpoints.summary -Body $body
}

function Test-DATTelemetryConnection {
    <#
    .SYNOPSIS
        Tests connectivity to the telemetry API: config fetch from GitHub, then health endpoint.
        Returns a hashtable with ConfigOk, HealthOk, ApiBaseUrl, and Error properties.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param ()

    Write-DATLogEntry -Value "[Telemetry] Starting connectivity test..." -Severity 1

    $result = @{
        ConfigOk   = $false
        HealthOk   = $false
        ApiBaseUrl = $null
        Error      = $null
    }

    # Step 1: Fetch remote config (force refresh)
    Write-DATLogEntry -Value "[Telemetry] Step 1: Fetching remote config from GitHub..." -Severity 1
    try {
        $config = Get-DATTelemetryConfig -Force
        if ($null -eq $config -or [string]::IsNullOrEmpty($config.apiBaseUrl)) {
            $result.Error = "Remote config returned empty or missing apiBaseUrl"
            Write-DATLogEntry -Value "[Telemetry] Config fetch returned empty -- $($result.Error)" -Severity 3
            return $result
        }
        $result.ConfigOk = $true
        $result.ApiBaseUrl = $config.apiBaseUrl
        Write-DATLogEntry -Value "[Telemetry] Config OK -- apiBaseUrl: $($config.apiBaseUrl)" -Severity 1
    } catch {
        $result.Error = "Config fetch failed: $($_.Exception.Message)"
        Write-DATLogEntry -Value "[Telemetry] $($result.Error)" -Severity 3
        return $result
    }

    # Step 2: Hit the health endpoint
    $healthUrl = "$($config.apiBaseUrl)/$($config.endpoints.health)"
    Write-DATLogEntry -Value "[Telemetry] Step 2: Testing health endpoint -- $healthUrl" -Severity 1
    try {
        $proxyParams = Get-DATWebRequestProxy
        if ($proxyParams -isnot [hashtable]) { $proxyParams = @{} }
        $null = Invoke-RestMethod -Uri $healthUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop @proxyParams
        $result.HealthOk = $true
        Write-DATLogEntry -Value "[Telemetry] Health endpoint OK" -Severity 1
    } catch {
        $result.Error = $_.Exception.Message
        Write-DATLogEntry -Value "[Telemetry] Health check failed: $($result.Error)" -Severity 2
    }

    $status = if ($result.ConfigOk -and $result.HealthOk) { "PASSED" } elseif ($result.ConfigOk) { "PARTIAL (config OK, health failed)" } else { "FAILED" }
    Write-DATLogEntry -Value "[Telemetry] Connectivity test result: $status" -Severity $(if ($result.HealthOk) { 1 } else { 2 })

    return $result
}

#endregion Telemetry
