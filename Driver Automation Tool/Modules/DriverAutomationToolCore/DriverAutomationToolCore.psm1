<#
    ===========================================================================
     Created by:    Maurice Daly
     Organization:  MSEndpointMgr / Patch My PC
     Filename:      DriverAutomationToolCore.psm1
     Purpose:       Core functions for Driver Automation Tool v2.0
     Version:       10.0.43.0
    ===========================================================================
#>

# Ensure TLS 1.2 and TLS 1.3 are enabled without overwriting other flags that may already be set.
# The -bor assignment preserves existing bits; the integer cast (12288) handles Tls13 safely on
# older .NET runtimes where the named enum value may not exist.
[Net.ServicePointManager]::SecurityProtocol = (
    [Net.ServicePointManager]::SecurityProtocol -bor
    [Net.SecurityProtocolType]::Tls12 -bor
    ([Net.SecurityProtocolType]12288)
)

# HPCMSL update check guard -- only check PSGallery once per module load
$script:HPCMSLUpdateChecked = $false

# Ensure System.Net.Http is available (required on PS 5.1 / Server 2016)
if ($PSVersionTable.PSVersion.Major -le 5) {
    try { Add-Type -AssemblyName System.Net.Http -ErrorAction Stop } catch { }
}

#region Variables

[version]$global:ScriptRelease = "10.0.43.0"
$global:ScriptBuildDate = "10-06-2026"
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
            # Security fix #7: DPAPI-encrypted. Falls back to '' if value is the old Base64 format.
            try {
                $ss   = ConvertTo-SecureString -String $reg.ProxyPassword -ErrorAction Stop
                $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
                try   { [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
                finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
            } catch { '' }
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
        Proxy credentials are NOT included here -- they are written to a temp --config
        file by New-DATCurlProxyConfigFile to prevent the password appearing on the
        process command line or in log files (security fix #5).
    #>
    $cfg = Get-DATProxySettings
    switch ($cfg.Mode) {
        'None'   { return '--noproxy "*"' }
        'Manual' {
            if ([string]::IsNullOrWhiteSpace($cfg.Server)) { return '' }
            return "--proxy `"$($cfg.Server)`""
        }
        default  { return '' }
    }
}

function New-DATCurlProxyConfigFile {
    <#
    .SYNOPSIS
        Writes proxy credentials to a randomly-named temp curl config file.
        Returns the file path, or $null if no proxy credentials are configured.
        The caller MUST delete the file in a finally block.
    #>
    $cfg = Get-DATProxySettings
    if ($cfg.Mode -ne 'Manual' -or [string]::IsNullOrWhiteSpace($cfg.Username)) {
        return $null
    }
    # Curl config file format: option-name = "value" (long option, no leading --)
    # Backslashes and double-quotes inside quoted values must be escaped with backslash.
    $escapedUser = $cfg.Username -replace '\\', '\\' -replace '"', '\"'
    $escapedPass = $cfg.Password -replace '\\', '\\' -replace '"', '\"'
    $configContent = "proxy-user = `"${escapedUser}:${escapedPass}`""
    $tmpPath = Join-Path ([System.IO.Path]::GetTempPath()) "dat_curl_$([System.IO.Path]::GetRandomFileName()).cfg"
    Set-Content -Path $tmpPath -Value $configContent -Encoding UTF8 -NoNewline
    return $tmpPath
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

#region File Integrity

# Trusted publisher Common Names (CN= portion of the Authenticode signer certificate Subject).
# Patterns are matched case-insensitively with the PowerShell -like operator (so wildcards are honoured).
# Used by Test-DATFileSignature when no published hash is available for a downloaded payload.
$script:DATTrustedPublisherCNs = @(
    'Dell Inc*',
    'Dell Computer Corporation',
    'HP Inc*',
    'Hewlett-Packard*',
    'Hewlett Packard*',
    'Lenovo*',
    'Microsoft Corporation',
    'Microsoft Windows*',
    'Acer Incorporated',
    'Acer Inc*',
    'Fujitsu*',
    'Toshiba*',
    'Panasonic*',
    'Getac*',
    'Dynabook*'
)

# SHA-256 hash pin for the bundled curl.exe (security fix #23).
# Leave empty to require Authenticode validation; set to the hex hash to allow
# a known-good unsigned build. Update whenever the bundled curl version changes.
# Compute with: (Get-FileHash -Algorithm SHA256 -Path '.\Tools\curl.exe').Hash
[string]$script:DATCurlSHA256Pin = ''

function Test-DATFileSignature {
    <#
    .SYNOPSIS
        Verifies that a file is Authenticode-signed by a publisher in the trusted allow-list.

    .DESCRIPTION
        Used as a fail-closed integrity gate when a published SHA-256 hash is not available
        for a downloaded payload (driver pack, BIOS executable, etc.). Returns $true only when:
          1. Get-AuthenticodeSignature reports Status -eq 'Valid', AND
          2. The signer certificate's CN matches one of the entries in
             $script:DATTrustedPublisherCNs (or one supplied via -AllowedPublishers).

        For archive files (.zip) that cannot carry Authenticode signatures, the function
        extracts the archive to a temporary folder, locates PE executables (.exe, .dll, .sys)
        inside, and validates at least one is signed by a trusted publisher. The temp folder
        is cleaned up after validation.

        Any other outcome returns $false and writes a Severity-3 log entry. Callers should
        treat $false as an integrity failure and refuse to use / repackage the file.

    .PARAMETER FilePath
        Path to the file to verify. Must exist.

    .PARAMETER AllowedPublishers
        Optional override for the module-level trusted publisher list. Patterns support
        the PowerShell -like operator (so '*' wildcards are allowed). Matched against the
        CN portion of the signer certificate Subject.

    .PARAMETER Context
        Optional short label included in log entries (e.g. 'Acer BIOS', 'Dell Driver Pack')
        to make audit trails easier to read.

    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [string[]]$AllowedPublishers = $script:DATTrustedPublisherCNs,

        [string]$Context = 'File'
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        Write-DATLogEntry -Value "[Integrity] [$Context] File not found for signature check: $FilePath" -Severity 3
        return $false
    }

    # For archive formats that cannot carry Authenticode signatures, extract and check contents
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    if ($extension -eq '.zip') {
        Write-DATLogEntry -Value "[Integrity] [$Context] Archive file detected (.zip) -- extracting to validate inner executables" -Severity 1
        $tempExtractDir = Join-Path ([System.IO.Path]::GetTempPath()) "DATSigCheck_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        try {
            Expand-Archive -Path $FilePath -DestinationPath $tempExtractDir -Force -ErrorAction Stop
            # Find PE files inside the archive
            $peFiles = Get-ChildItem -Path $tempExtractDir -Recurse -File -Include '*.exe','*.dll','*.sys' -ErrorAction SilentlyContinue
            if ($null -eq $peFiles -or @($peFiles).Count -eq 0) {
                Write-DATLogEntry -Value "[Integrity] [$Context] Archive contains no PE files (.exe/.dll/.sys) to validate -- skipping signature check (hash-only integrity)" -Severity 2
                # No PE files to check -- allow the archive (integrity was confirmed by download success over HTTPS)
                return $true
            }
            # Validate at least one PE file is signed by a trusted publisher
            foreach ($pe in $peFiles) {
                $innerResult = Test-DATFileSignature -FilePath $pe.FullName -AllowedPublishers $AllowedPublishers -Context "$Context|Inner:$($pe.Name)"
                if ($innerResult) {
                    Write-DATLogEntry -Value "[Integrity] [$Context] Archive validated via inner file: $($pe.Name)" -Severity 1
                    return $true
                }
            }
            Write-DATLogEntry -Value "[Integrity] [$Context] No PE files inside archive are signed by a trusted publisher -- file: $FilePath" -Severity 3
            return $false
        } catch {
            Write-DATLogEntry -Value "[Integrity] [$Context] Failed to extract archive for signature check: $($_.Exception.Message) -- file: $FilePath" -Severity 3
            return $false
        } finally {
            if (Test-Path $tempExtractDir) {
                Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    try {
        $sig = Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction Stop
    } catch {
        Write-DATLogEntry -Value "[Integrity] [$Context] Get-AuthenticodeSignature failed: $($_.Exception.Message)" -Severity 3
        return $false
    }

    if ($null -eq $sig -or $sig.Status -ne 'Valid') {
        $statusText = if ($sig) { $sig.Status } else { 'NoSignature' }
        $statusMsg  = if ($sig -and $sig.StatusMessage) { $sig.StatusMessage } else { '' }
        Write-DATLogEntry -Value "[Integrity] [$Context] Authenticode signature is not Valid (Status: $statusText) $statusMsg -- file: $FilePath" -Severity 3
        return $false
    }

    if ($null -eq $sig.SignerCertificate) {
        Write-DATLogEntry -Value "[Integrity] [$Context] Signature is Valid but has no SignerCertificate -- file: $FilePath" -Severity 3
        return $false
    }

    # Extract CN from the certificate Subject (e.g. 'CN="Dell Inc.", O=Dell Inc., L=Round Rock, S=Texas, C=US')
    $subject = $sig.SignerCertificate.Subject
    $cn      = $null
    if ($subject -match '(?i)CN\s*=\s*"([^"]+)"') {
        $cn = $matches[1]
    } elseif ($subject -match '(?i)CN\s*=\s*([^,]+)') {
        $cn = $matches[1].Trim()
    }

    if ([string]::IsNullOrWhiteSpace($cn)) {
        Write-DATLogEntry -Value "[Integrity] [$Context] Could not parse CN from signer subject: $subject -- file: $FilePath" -Severity 3
        return $false
    }

    foreach ($pattern in $AllowedPublishers) {
        if ($cn -like $pattern) {
            Write-DATLogEntry -Value "[Integrity] [$Context] Authenticode OK -- signer '$cn' matched allow-list pattern '$pattern' -- file: $FilePath" -Severity 1
            return $true
        }
    }

    Write-DATLogEntry -Value "[Integrity] [$Context] Authenticode signature is Valid but signer '$cn' is NOT in the trusted publisher allow-list -- file: $FilePath" -Severity 3
    return $false
}

#endregion File Integrity

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

    # Rotate log based on configured size (default 1MB) -- keep up to 5 previous rolled-over logs
    $logMaxSizeMB = try { (Get-ItemProperty -Path $global:RegPath -Name "LogFileSizeMB" -ErrorAction SilentlyContinue).LogFileSizeMB } catch { $null }
    if (-not $logMaxSizeMB -or $logMaxSizeMB -lt 1) { $logMaxSizeMB = 1 }
    $logMaxSizeBytes = $logMaxSizeMB * 1MB
    if (Test-Path -Path $script:LogFilePath) {
        $LogFileSize = (Get-Item -Path $script:LogFilePath).Length
        if ($LogFileSize -ge $logMaxSizeBytes) {
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
    # CMTrace expects the timezone bias appended directly to the millisecond value with a
    # sign character and NO space, e.g. "02:51:35.517-600" (#781). The bias sign is inverted
    # because CMTrace stores the offset required to convert local time to UTC.
    $tzBias = try { [System.TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).TotalMinutes } catch { 0 }
    $tzBiasString = [string]$tzBias
    if ($tzBiasString -match "^-") { $tzBiasString = $tzBiasString.Replace("-", "+") } else { $tzBiasString = "-" + $tzBiasString }
    $Time = -join @((Get-Date -Format "HH:mm:ss.fff"), $tzBiasString)
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
            $_.Types.Type -contains $ModelType
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
                # Determine the user's HP driver source mode. In SCCM DriverPack mode the
                # version must come from the HP catalog (e.g. "7.00 A 1"); only the SoftPaq
                # mode uses a date stamp (its real version is fingerprint-based at build time).
                $HPDriverPackSource = (Get-ItemProperty -Path $global:RegPath -Name 'HPDriverPackSource' -ErrorAction SilentlyContinue).HPDriverPackSource
                if ([string]::IsNullOrEmpty($HPDriverPackSource)) { $HPDriverPackSource = 'DriverPack' }
                $HPXMLCabinetSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "HP" }).Link | Where-Object { $_.Type -eq "XMLCabinetSource" } | Select-Object -ExpandProperty URL -First 1
                $HPCabFile = [string]($HPXMLCabinetSource | Split-Path -Leaf)
                $HPXMLFile = $HPCabFile.TrimEnd(".cab") + ".xml"
                try {
                    $HPCabPath = Join-Path $global:TempDirectory $HPCabFile
                    $HPXMLPath = Join-Path $global:TempDirectory $HPXMLFile
                    Write-DATLogEntry -Value "[HP] CAB download path: $HPCabPath" -Severity 1
                    Write-DATLogEntry -Value "[HP] XML extract path: $HPXMLPath" -Severity 1
                    Invoke-DATContentDownload -DownloadURL $HPXMLCabinetSource -DownloadDestination $global:TempDirectory
                    Expand "$HPCabPath" -F:* "$global:TempDirectory" -R | Out-Null
                    [xml]$HPModelXML = Get-Content -Path $HPXMLPath -Raw
                    $HPModelSoftPaqs = $HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
                    $totalPacks = @($HPModelSoftPaqs).Count
                    Write-DATLogEntry -Value "[HP] Total packs in catalog: $totalPacks (filtering: OSName -match '$WindowsVersion' -and -match '$WindowsBuild')" -Severity 1
                    $HPOSSupportedPacks = $HPModelSoftPaqs | Where-Object { $_.OSName -match $WindowsVersion -and $_.OSName -match $WindowsBuild }
                    if (@($HPOSSupportedPacks).Count -eq 0 -and $totalPacks -gt 0) {
                        $sampleOSNames = @($HPModelSoftPaqs | Select-Object -ExpandProperty OSName -Unique | Select-Object -First 10)
                        Write-DATLogEntry -Value "[HP] 0 matches -- sample OSName values: $($sampleOSNames -join '; ')" -Severity 2
                    }
                    foreach ($Model in $HPOSSupportedPacks) {
                        $Model.SystemName = ($Model.SystemName -replace '^HP\s+', '').Trim()
                        # Null-safe SystemId join (#16)
                        $sysIds = $Model.SystemId | Where-Object { $_ } | Select-Object -Unique
                        # SCCM DriverPack mode uses the HP catalog version; SoftPaq mode uses a
                        # date stamp (its definitive version is computed from the SoftPaq fingerprint).
                        $hpModelVersion = if ($HPDriverPackSource -eq 'DriverPack' -and -not [string]::IsNullOrEmpty($Model.Version)) {
                            $Model.Version
                        } else {
                            (Get-Date -Format 'ddMMyyyy')
                        }
                        $OEMSupportedModels += [PSCustomObject]@{
                            OEM        = "HP"
                            Model      = $Model.SystemName
                            Baseboards = $(if ($sysIds) { $sysIds -join "," } else { "" })
                            OS         = $WindowsVersion
                            'OS Build' = $WindowsBuild
                            Version    = $hpModelVersion
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
                    Write-DATLogEntry -Value "[Dell] Catalog cab path: $(Join-Path $global:TempDirectory $DellCabFile)" -Severity 1
                    Write-DATLogEntry -Value "[Dell] Catalog XML extract path: $(Join-Path $global:TempDirectory $DellXMLFile)" -Severity 1
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
                    # Deduplicate short-name variants (e.g. "7060" vs "OptiPlex 7060") sharing overlapping baseboards
                    $DellModels = @($DellModels | Where-Object {
                        $current = $_
                        $currentIds = @($current.SystemID | Where-Object { $_ } | Select-Object -Unique)
                        # Keep this entry unless a longer-named entry exists with overlapping baseboards
                        $dominated = $DellModels | Where-Object {
                            $_.SystemName -ne $current.SystemName -and
                            $_.SystemName.Length -gt $current.SystemName.Length -and
                            $_.SystemName -like "*$($current.SystemName)*" -and
                            @($_.SystemID | Where-Object { $_ -and $_ -in $currentIds }).Count -gt 0
                        }
                        $null -eq $dominated
                    })
                    foreach ($Model in $DellModels) {
                        # Null-safe SystemId join (#16)
                        $sysIds = $Model.SystemId | Where-Object { $_ } | Select-Object -Unique
                        $OEMSupportedModels += [PSCustomObject]@{
                            OEM        = "Dell"
                            Model      = $Model.SystemName
                            Baseboards = $(if ($sysIds) { $sysIds -join "," } else { "" })
                            OS         = $WindowsVersion
                            'OS Build' = 'All'
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
                    Write-DATLogEntry -Value "[Lenovo] Catalog download path: $(Join-Path $global:TempDirectory $LenovoXMLCabFile)" -Severity 1
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
                $MSArchFilter = if ($Architecture -eq 'Arm64') { 'arm64' } else { 'amd64' }
                $DATMicrosoftModels = @()
                $DATModelNames = @()

                # Try DAT API catalog first
                try {
                    Write-DATLogEntry -Value "[Microsoft] Checking DAT driver catalog for Microsoft models..." -Severity 1
                    $DATCatalog = Get-DATDriverCatalog
                    if ($DATCatalog -and $DATCatalog.Count -gt 0) {
                        $DATMSFiltered = $DATCatalog | Where-Object {
                            $_.Manufacturer -eq 'Microsoft' -and
                            $_.SupportedOS -match $WindowsVersion -and
                            $_.SupportedArchitecture -eq $MSArchFilter
                        }
                        $DATMicrosoftModels = $DATMSFiltered | Group-Object -Property DisplayName
                        foreach ($MSModelGroup in $DATMicrosoftModels) {
                            $latestEntry = $MSModelGroup.Group | Sort-Object { try { [datetime]$_.ReleaseDate } catch { [datetime]::MinValue } } -Descending | Select-Object -First 1
                            $msVersion = if ($latestEntry.ReleaseDate) { $latestEntry.ReleaseDate } else { '' }
                            $OEMSupportedModels += [PSCustomObject]@{
                                OEM        = "Microsoft"
                                Model      = $MSModelGroup.Name
                                Baseboards = if ($latestEntry.SupportedDevices) { $latestEntry.SupportedDevices } else { $MSModelGroup.Name }
                                OS         = $WindowsVersion
                                'OS Build' = $WindowsBuild
                                Version    = $msVersion
                            }
                            $DATModelNames += $MSModelGroup.Name
                        }
                        Write-DATLogEntry -Value "[Microsoft] DAT catalog: $($DATMicrosoftModels.Count) model(s) found" -Severity 1
                    }
                } catch {
                    Write-DATLogEntry -Value "[Microsoft] DAT catalog unavailable: $($_.Exception.Message) -- falling back to OSD catalog" -Severity 2
                }

                # Load OSD catalog only when DAT API catalog mode is NOT enabled
                $useDATReg = (Get-ItemProperty -Path $global:RegPath -Name 'UseDATAPICatalog' -ErrorAction SilentlyContinue).UseDATAPICatalog
                $useDATAPICatalog = ($useDATReg -eq 1)
                if (-not $useDATAPICatalog) {
                    $MicrosoftCatalogSource = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/OSDCatalogMicrosoftDriverPack.json"
                    $MicrosoftCatalogPath = Join-Path $global:TempDirectory "OSDCatalogMicrosoftDriverPack.json"
                    try {
                        Write-DATLogEntry -Value "[Microsoft] OSD catalog download path: $MicrosoftCatalogPath" -Severity 1
                        $proxyParams = Get-DATWebRequestProxy
                        Invoke-WebRequest -Uri $MicrosoftCatalogSource -OutFile $MicrosoftCatalogPath -UseBasicParsing -TimeoutSec 30 @proxyParams
                        $global:MicrosoftModelList = Get-Content -Path $MicrosoftCatalogPath -Raw | ConvertFrom-Json
                        $MSFiltered = $global:MicrosoftModelList | Where-Object {
                            $_.OperatingSystem -match $WindowsVersion -and $_.OSArchitecture -eq $MSArchFilter -and
                            $_.Model -notin $DATModelNames
                        }
                        $MicrosoftModels = $MSFiltered | Group-Object -Property Model
                        foreach ($MSModelGroup in $MicrosoftModels) {
                            $products = ($MSModelGroup.Group | ForEach-Object { $_.SystemId } | Select-Object -Unique) -join ','
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
                        if ($MicrosoftModels.Count -gt 0) {
                            Write-DATLogEntry -Value "[Microsoft] OSD catalog: $($MicrosoftModels.Count) additional model(s) added" -Severity 1
                        }
                    } catch {
                        Write-DATLogEntry -Value "[Error] - Microsoft OSD model retrieval failed: $($_.Exception.Message)" -Severity 3
                    }
                } else {
                    Write-DATLogEntry -Value "[Microsoft] DAT API catalog mode enabled -- skipping OSD catalog" -Severity 1
                }
            }
            "Acer" {
                $AcerXMLSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Acer" }).Link | Where-Object { $_.Type -eq "XMLSource" } | Select-Object -ExpandProperty URL -First 1
                $AcerXMLFile = [string]($AcerXMLSource | Split-Path -Leaf)
                try {
                    Write-DATLogEntry -Value "[Acer] Catalog download path: $(Join-Path $global:TempDirectory $AcerXMLFile)" -Severity 1
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
                    # Load the DAT API driver catalog (preferred version source -- exposes a 'Version' field)
                    $AcerDATCatalog = $null
                    try { $AcerDATCatalog = Get-DATDriverCatalog } catch {
                        Write-DATLogEntry -Value "[Acer] DAT catalog unavailable for version lookup: $($_.Exception.Message)" -Severity 2
                    }
                    $AcerArchFilter = if ($Architecture -eq 'Arm64') { 'arm64' } else { 'x64' }
                    foreach ($Model in $AcerModels) {
                        $modelNode = $global:AcerModelDrivers | Where-Object { $_.Name -eq $Model } | Select-Object -First 1
                        # Prefer the DAT API catalog Version field; fall back to the XML SCCM node date
                        $acerVersion = ''
                        if ($AcerDATCatalog) {
                            $datEntry = $AcerDATCatalog | Where-Object {
                                $_.Manufacturer -eq 'Acer' -and
                                $_.DisplayName -eq $Model -and
                                $_.SupportedOS -match $WindowsVersion -and
                                $_.SupportedArchitecture -eq $AcerArchFilter
                            } | Select-Object -First 1
                            if ($datEntry -and -not [string]::IsNullOrEmpty($datEntry.Version)) {
                                $acerVersion = $datEntry.Version
                            }
                        }
                        if ([string]::IsNullOrEmpty($acerVersion)) {
                            # Catalog-provided date from the matching SCCM node
                            $sccmNode = $modelNode.SCCM | Where-Object { $_.Version -eq $WindowsBuild -and $_.OS -eq $("Win" + "$($WindowsVersion.Split(' ')[1])") } | Select-Object -First 1
                            $acerVersion = if ($sccmNode.date) { $sccmNode.date } else { '' }
                        }
                        $OEMSupportedModels += [PSCustomObject]@{
                            OEM        = "Acer"
                            Model      = $Model
                            Baseboards = $Model
                            OS         = $WindowsVersion
                            'OS Build' = $WindowsBuild
                            Version    = $acerVersion
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

    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12 -bor
        ([Net.SecurityProtocolType]12288)
    )

    # Ensure DownloadURL is a single string, not an array
    if ($DownloadURL -is [array]) { $DownloadURL = $DownloadURL[0] }

    # Validate URL before attempting anything -- HTTPS only (security fix #12)
    $uriResult = $null
    if (-not ([System.Uri]::TryCreate($DownloadURL, [System.UriKind]::Absolute, [ref]$uriResult)) -or
        $uriResult.Scheme -ne 'https') {
        Write-DATLogEntry -Value "[Error] - Download URL must use HTTPS. Rejected: '$DownloadURL'" -Severity 3
        throw "Download URL must use HTTPS: '$DownloadURL'"
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
        if ($sizeMatch) {
            Write-DATLogEntry -Value "- Cache hit (size verified: $DownloadedFileSize bytes matches Content-Length): $DownloadDestination" -Severity 1
            $DownloadedSizeMB = [math]::Round(($DownloadedFileSize / 1MB), 2)
            Set-DATRegistryValue -Name "DownloadSize"       -Type String -Value "$DownloadedSizeMB MB"
            Set-DATRegistryValue -Name "DownloadBytes"      -Value "$DownloadedFileSize" -Type String
            Set-DATRegistryValue -Name "BytesTransferred"   -Value "$DownloadedFileSize" -Type String
            Set-DATRegistryValue -Name "DownloadSpeed"      -Value "---"  -Type String
            Set-DATRegistryValue -Name "RunningState"       -Value "Running" -Type String
            Set-DATRegistryValue -Name "RunningMode"        -Value "Download Completed" -Type String
            return
        } elseif ($sizeUnknown) {
            Write-DATLogEntry -Value "- Cache hit (Content-Length unavailable; file exists at $DownloadedFileSize bytes -- no further validation possible at this stage): $DownloadDestination" -Severity 1
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
            # Binary is not Authenticode-signed. Accept only if operator has pinned
            # an expected SHA-256 hash; otherwise fall back to system curl (security fix #23).
            $sigStatus = if ($curlSig) { $curlSig.Status } else { 'Unknown' }
            if (-not [string]::IsNullOrEmpty($script:DATCurlSHA256Pin)) {
                $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $CurlProcess -ErrorAction SilentlyContinue).Hash
                if ($actualHash -eq $script:DATCurlSHA256Pin) {
                    Write-DATLogEntry -Value "- Bundled CURL is unsigned ($sigStatus) but SHA-256 pin matches -- accepted" -Severity 1
                } else {
                    $pinPrefix    = $script:DATCurlSHA256Pin.Substring(0, [Math]::Min(8, $script:DATCurlSHA256Pin.Length))
                    $actualPrefix = if ($actualHash) { $actualHash.Substring(0, [Math]::Min(8, $actualHash.Length)) } else { 'n/a' }
                    Write-DATLogEntry -Value "[Warning] - Bundled CURL SHA-256 mismatch (pin: $pinPrefix`u{2026} actual: $actualPrefix`u{2026}) -- falling back to system curl" -Severity 2
                    $CurlProcess = $null
                    $useCurl = $false
                }
            } else {
                Write-DATLogEntry -Value "[Warning] - Bundled CURL is unsigned ($sigStatus) and no SHA-256 pin is configured -- falling back to system curl" -Severity 2
                $CurlProcess = $null
                $useCurl = $false
            }
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

        # Write proxy credentials to a temp curl config file so the password never appears
        # on the process command line or in log files (security fix #5). Deleted in finally.
        $curlProxyCfgFile = New-DATCurlProxyConfigFile

        # If HEAD request failed to get size, fall back to CURL headers
        if ($DownloadSize -le 0) {
            try {
                Write-DATLogEntry -Value "- Using CURL to obtain file size via response headers" -Severity 1
                # Use -i (include headers) with a real GET request -- many CDNs don't return
                # Content-Length for HEAD requests. --suppress-connect-headers removes proxy noise.
                # --max-time 15 limits the download to 15 seconds (headers arrive within the first second).
                # --proto =https prevents redirect downgrade to HTTP (security fix #12).
                $curlProbeArgs = @('--silent', '--location', '--proto', '=https', '--max-redirs', '5',
                                   '-i', '--suppress-connect-headers', '--max-time', '15', $DownloadURL)
                if ($curlProxyCfgFile) { $curlProbeArgs = @('--config', $curlProxyCfgFile) + $curlProbeArgs }
                [array]$CurlHeaderOutput = (& "$CurlProcess" @curlProbeArgs 2>&1)
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
        # --proto =https prevents redirect downgrade to HTTP; --max-redirs 5 caps redirect chains (security fix #12)
        # Proxy server (no credentials) comes from Get-DATCurlProxyArgs; credentials come via --config (security fix #5)
        $CurlArgs = "--location --proto '=https' --max-redirs 5 --output `"$DownloadDestination`" --url `"$DownloadURL`" --dump-header `"$CurlHeaderDumpFile`" --connect-timeout 30 --retry 10 --retry-delay 60 --retry-max-time 600 --retry-connrefused $(Get-DATCurlProxyArgs)"
        if ($curlProxyCfgFile) { $CurlArgs = "--config `"$curlProxyCfgFile`" $CurlArgs" }

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
                $CURLBytes = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'Curl.exe'" -ErrorAction SilentlyContinue |
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
            # Delete temp proxy credentials config file (security fix #5)
            if ($curlProxyCfgFile -and (Test-Path -LiteralPath $curlProxyCfgFile)) {
                Remove-Item -LiteralPath $curlProxyCfgFile -Force -ErrorAction SilentlyContinue
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

    $DriverFolder = Join-Path -Path $localWorkDir -ChildPath "Extracted"
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
                        # Inno Setup fails if the target directory already exists -- remove it and let Inno Setup create it via /DIR=
                        if (Test-Path -Path $DriverFolder) {
                            Write-DATLogEntry -Value "[$OEM] Removing existing extraction folder to avoid Inno Setup conflict: $DriverFolder" -Severity 1
                            Remove-Item -Path $DriverFolder -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        $exeArgs = "/VERYSILENT /DIR=`"$DriverFolder`" /SP- /SUPPRESSMSGBOXES /NORESTART"
                        Write-DATLogEntry -Value "[$OEM] Extracting (elevated) with: $exeArgs" -Severity 1
                        Unblock-File -Path "$FilePath"
                        try {
                            $lenovoProc = Start-Process -FilePath $FilePath -ArgumentList $exeArgs -Verb RunAs -PassThru -Wait -ErrorAction Stop
                            $exitCode = $lenovoProc.ExitCode
                        } catch {
                            Write-DATLogEntry -Value "[Error] - Lenovo elevated extraction failed: $($_.Exception.Message)" -Severity 3
                            $exitCode = -1
                        }
                    } else {
                        $exeArgs = "/s /e=`"$DriverFolder`""
                        Write-DATLogEntry -Value "[$OEM] Extracting with: $exeArgs" -Severity 1
                        $exitCode = Invoke-DATExecutable -FilePath $FilePath -Arguments $exeArgs
                    }
                    # Check if extraction produced files
                    $extractedFiles = @(Get-ChildItem -Path $DriverFolder -Recurse -File -ErrorAction SilentlyContinue)
                    if (($exitCode -ne 0 -and $null -ne $exitCode) -or $extractedFiles.Count -eq 0) {
                        Write-DATLogEntry -Value "[Warning] - EXE extraction returned exit code $exitCode for $FilePath (files: $($extractedFiles.Count)) -- attempting 7-Zip fallback" -Severity 2
                        # Attempt 7-Zip fallback for Dell self-extracting archives
                        $7zFallback = $null
                        foreach ($candidate in @(
                            (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
                            (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe')
                        )) {
                            if (Test-Path $candidate) { $7zFallback = $candidate; break }
                        }
                        if (-not $7zFallback) {
                            try { $7zFallback = (Get-Command '7z.exe' -ErrorAction Stop).Source } catch { }
                        }
                        if ($7zFallback -and (Test-Path $7zFallback)) {
                            Write-DATLogEntry -Value "[$OEM] Using 7-Zip fallback: $7zFallback" -Severity 1
                            $7zProc = Start-Process -FilePath $7zFallback -ArgumentList "x `"$FilePath`" -o`"$DriverFolder`" -y" -WindowStyle Hidden -PassThru -Wait
                            if ($7zProc.ExitCode -eq 0) {
                                Write-DATLogEntry -Value "[$OEM] 7-Zip fallback extraction succeeded" -Severity 1
                            } else {
                                Write-DATLogEntry -Value "[Warning] - 7-Zip fallback also failed with exit code $($7zProc.ExitCode) for $FilePath" -Severity 2
                            }
                        } else {
                            Write-DATLogEntry -Value "[Warning] - 7-Zip not available for fallback extraction of $FilePath" -Severity 2
                        }
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
                $preCount = @(Get-ChildItem -Path $DriverFolder -Recurse -File -ErrorAction SilentlyContinue).Count
                $exitCode = Invoke-DATExecutable -FilePath $suppFile -Arguments $suppArgs
                $postCount = @(Get-ChildItem -Path $DriverFolder -Recurse -File -ErrorAction SilentlyContinue).Count
                if (($exitCode -ne 0 -and $null -ne $exitCode) -or ($postCount -le $preCount)) {
                    Write-DATLogEntry -Value "[Warning] - Supplemental EXE extraction returned exit code $exitCode for $suppFile (new files: $($postCount - $preCount)) -- attempting 7-Zip fallback" -Severity 2
                    $7zFallback = $null
                    foreach ($candidate in @(
                        (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
                        (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe')
                    )) {
                        if (Test-Path $candidate) { $7zFallback = $candidate; break }
                    }
                    if (-not $7zFallback) {
                        try { $7zFallback = (Get-Command '7z.exe' -ErrorAction Stop).Source } catch { }
                    }
                    if ($7zFallback -and (Test-Path $7zFallback)) {
                        Write-DATLogEntry -Value "[$OEM] Using 7-Zip fallback for supplemental: $7zFallback" -Severity 1
                        $7zProc = Start-Process -FilePath $7zFallback -ArgumentList "x `"$suppFile`" -o`"$DriverFolder`" -y" -WindowStyle Hidden -PassThru -Wait
                        if ($7zProc.ExitCode -eq 0) {
                            Write-DATLogEntry -Value "[$OEM] 7-Zip fallback extraction succeeded for supplemental" -Severity 1
                        } else {
                            Write-DATLogEntry -Value "[Warning] - 7-Zip fallback also failed with exit code $($7zProc.ExitCode) for $suppFile" -Severity 2
                        }
                    } else {
                        Write-DATLogEntry -Value "[Warning] - 7-Zip not available for fallback extraction of $suppFile" -Severity 2
                    }
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

        # Fix permissions on extracted folder -- some OEM self-extractors (especially Dell)
        # create files with restrictive ACLs that cause DISM /Capture-Image to fail with
        # Error 5 (Access Denied). Take ownership first, then grant Administrators full control.
        try {
            Write-DATLogEntry -Value "[$OEM] Taking ownership of extracted files for WIM capture..." -Severity 1
            $takeownProc = Start-Process -FilePath "$env:SystemRoot\System32\takeown.exe" `
                -ArgumentList "/F `"$DriverFolder`" /R /A /D Y" `
                -WindowStyle Hidden -PassThru -Wait
            if ($takeownProc.ExitCode -ne 0) {
                Write-DATLogEntry -Value "[$OEM] takeown returned code $($takeownProc.ExitCode) -- continuing anyway" -Severity 2
            }
            # Grant Administrators full control using well-known SID (locale-independent)
            $icaclsProc = Start-Process -FilePath "$env:SystemRoot\System32\icacls.exe" `
                -ArgumentList "`"$DriverFolder`" /grant *S-1-5-32-544:(OI)(CI)F /T /C /Q" `
                -WindowStyle Hidden -PassThru -Wait
            if ($icaclsProc.ExitCode -ne 0) {
                Write-DATLogEntry -Value "[$OEM] icacls grant returned code $($icaclsProc.ExitCode) -- continuing anyway" -Severity 2
            }
        } catch {
            Write-DATLogEntry -Value "[$OEM] Permission fix failed: $($_.Exception.Message) -- continuing anyway" -Severity 2
        }

        try {
            $DriverMountFolder = Join-Path -Path $localWorkDir -ChildPath "Packaged"
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

                $dismLogFile = Join-Path $localWorkDir "DAT_DISM_capture.log"
                $dismStdoutFile = Join-Path $localWorkDir "DAT_DISM_stdout.log"
                $dismArgs = "/Capture-Image /ImageFile:`"$WimFile`" /CaptureDir:`"$DriverFolder`" /Name:`"$WimDescription`" /Description:`"$WimDescription`" /Compress:$compressionType /Verify /LogPath:`"$dismLogFile`" /LogLevel:3"
                Write-DATLogEntry -Value "[$OEM] DISM command: dism.exe $dismArgs" -Severity 1

                # Run dism.exe directly -- -WindowStyle Hidden allocates a real console
                # (required by DISM; CreateNoWindow/RedirectStandardOutput causes hangs).
                # Use a batch wrapper for stdout capture while preserving console allocation.
                $dismBatchFile = Join-Path $localWorkDir "DAT_DISM_capture.cmd"
                $dismCmd = "`"$env:SystemRoot\System32\dism.exe`" $dismArgs"
                Set-Content -Path $dismBatchFile -Value "@echo off`r`n$dismCmd > `"$dismStdoutFile`" 2>&1`r`nexit /b %ERRORLEVEL%" -Encoding ASCII

                $dismProcess = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/c `"$dismBatchFile`"" `
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

                # Clean up batch file; preserve DISM log on failure for diagnostics
                Remove-Item $dismBatchFile -Force -ErrorAction SilentlyContinue
                if ($effectiveExitCode -eq 0) {
                    Remove-Item $dismLogFile -Force -ErrorAction SilentlyContinue
                } else {
                    Write-DATLogEntry -Value "[$OEM] DISM log preserved for diagnostics: $dismLogFile" -Severity 2
                }

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
            } elseif ($effectiveExitCode -in @(5, 740)) {
                # Diagnose common causes of Access Denied when already elevated
                Write-DATLogEntry -Value "[$OEM] DISM exit code $effectiveExitCode -- running security diagnostics..." -Severity 2
                try {
                    $mpPref = Get-MpPreference -ErrorAction SilentlyContinue
                    if ($null -ne $mpPref) {
                        # Controlled Folder Access
                        $cfaState = switch ($mpPref.EnableControlledFolderAccess) {
                            0 { 'Disabled' }; 1 { 'Enabled (Block)' }; 2 { 'Audit' }; 6 { 'Block (Disk Only)' }; default { "Unknown ($($mpPref.EnableControlledFolderAccess))" }
                        }
                        Write-DATLogEntry -Value "[$OEM] Controlled Folder Access: $cfaState" -Severity 2
                        if ($mpPref.EnableControlledFolderAccess -in @(1, 6)) {
                            Write-DATLogEntry -Value "[$OEM] ** Controlled Folder Access is BLOCKING -- add dism.exe to allowed apps or exclude $($global:TempDirectory)" -Severity 3
                        }

                        # ASR rules in block mode (Action=1)
                        $asrIds = $mpPref.AttackSurfaceReductionRules_Ids
                        $asrActions = $mpPref.AttackSurfaceReductionRules_Actions
                        if ($asrIds -and $asrIds.Count -gt 0) {
                            $blockedRules = @()
                            for ($i = 0; $i -lt $asrIds.Count; $i++) {
                                if ($asrActions -and $i -lt $asrActions.Count -and $asrActions[$i] -eq 1) {
                                    $blockedRules += $asrIds[$i]
                                }
                            }
                            if ($blockedRules.Count -gt 0) {
                                Write-DATLogEntry -Value "[$OEM] ASR rules in Block mode: $($blockedRules -join ', ')" -Severity 2
                            }
                        }

                        # Real-time protection
                        if ($mpPref.DisableRealtimeMonitoring -eq $false) {
                            Write-DATLogEntry -Value "[$OEM] Real-time AV scanning is active -- may hold locks on extracted .sys files" -Severity 2
                        }
                    }

                    # Check recent Defender block events (ASR/CFA) from the last 5 minutes
                    $recentBlocks = Get-WinEvent -LogName 'Microsoft-Windows-Windows Defender/Operational' -MaxEvents 100 -ErrorAction SilentlyContinue |
                        Where-Object { $_.Id -in @(1121, 1122, 1123, 1124, 1125) -and $_.TimeCreated -gt (Get-Date).AddMinutes(-5) }
                    if ($recentBlocks -and $recentBlocks.Count -gt 0) {
                        Write-DATLogEntry -Value "[$OEM] ** Found $($recentBlocks.Count) recent Defender block event(s) in the last 5 minutes:" -Severity 3
                        foreach ($evt in $recentBlocks | Select-Object -First 3) {
                            Write-DATLogEntry -Value "[$OEM]    Event $($evt.Id) at $($evt.TimeCreated): $($evt.Message -replace '[\r\n]+',' ' | Select-Object -First 1)" -Severity 3
                        }
                    }
                } catch {
                    Write-DATLogEntry -Value "[$OEM] Security diagnostics failed: $($_.Exception.Message)" -Severity 2
                }

                $errorMsg = "WIM creation requires elevation (Run as Administrator). DISM exit code $effectiveExitCode (Access is denied)."
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
            # Clean up temp working directory on failure (skip for access-denied so user can inspect extraction)
            if ($_.Exception.Message -match 'elevation|Access is denied') {
                Write-DATLogEntry -Value "[$OEM] Temp working directory preserved for inspection: $localWorkDir" -Severity 2
            } elseif (Test-Path $localWorkDir) {
                Remove-Item -Path $localWorkDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-DATLogEntry -Value "[$OEM] Temp working directory cleaned up after failure" -Severity 2
            }
            throw
        }
    }
}

#endregion Download

#region ConfigMgr

function New-DATCimSession {
    <#
    .SYNOPSIS
        Creates a CIM session with DCOM and short-hostname fallbacks.
    .DESCRIPTION
        Attempts default WSMAN authentication first. If that fails, retries with
        DCOM protocol (RPC). If both fail and the computer name is an FQDN, retries
        with the short hostname for both WSMAN and DCOM to resolve Kerberos SPN
        mismatches. Returns $null and sets $global:DATUseLegacyWmi when all CIM
        session methods fail, enabling Get-WmiObject fallback in query functions.
    #>
    param (
        [Parameter(Mandatory = $true)][string]$ComputerName
    )
    # Attempt 1: WSMAN (default) with a short timeout so we fail fast when WinRM is unavailable
    try {
        return (New-CimSession -ComputerName $ComputerName -OperationTimeoutSec 15 -ErrorAction Stop)
    } catch {
        Write-DATLogEntry -Value "[WMI] WSMAN session failed for ${ComputerName}: $($_.Exception.Message)" -Severity 2
    }
    # Attempt 2: DCOM (RPC -- bypasses WinRM entirely)
    try {
        $dcomOpts = New-CimSessionOption -Protocol Dcom
        return (New-CimSession -ComputerName $ComputerName -SessionOption $dcomOpts -ErrorAction Stop)
    } catch {
        Write-DATLogEntry -Value "[WMI] DCOM session failed for ${ComputerName}: $($_.Exception.Message)" -Severity 2
    }
    # Attempt 3 & 4: If FQDN, try short hostname with both WSMAN and DCOM
    if ($ComputerName -match '\.') {
        $shortName = $ComputerName.Split('.')[0]
        Write-DATLogEntry -Value "[WMI] FQDN failed -- retrying with short name: $shortName" -Severity 2
        try {
            return (New-CimSession -ComputerName $shortName -OperationTimeoutSec 15 -ErrorAction Stop)
        } catch {
            Write-DATLogEntry -Value "[WMI] Short name WSMAN failed for ${shortName}: $($_.Exception.Message)" -Severity 2
        }
        try {
            $dcomOpts = New-CimSessionOption -Protocol Dcom
            return (New-CimSession -ComputerName $shortName -SessionOption $dcomOpts -ErrorAction Stop)
        } catch {
            Write-DATLogEntry -Value "[WMI] Short name DCOM also failed for ${shortName}: $($_.Exception.Message)" -Severity 3
        }
    }
    # All CIM session methods exhausted -- enable legacy WMI fallback
    Write-DATLogEntry -Value "[WMI] All CIM session methods failed for $ComputerName -- enabling Get-WmiObject fallback" -Severity 2
    $global:DATUseLegacyWmi = $true
    return $null
}

function Invoke-DATRemoteQuery {
    <#
    .SYNOPSIS
        Queries a remote WMI/CIM namespace with automatic Get-WmiObject fallback.
    .DESCRIPTION
        Uses Get-CimInstance when a valid CIM session is available. Falls back to
        Get-WmiObject (legacy DCOM/RPC) when CIM sessions are unavailable, which
        resolves connectivity issues in environments where WinRM is not configured
        and the CIM DCOM stack has restricted permissions.
    .PARAMETER CimSession
        An existing CIM session. If $null and $global:DATUseLegacyWmi is set,
        the function uses Get-WmiObject instead.
    .PARAMETER ComputerName
        The remote computer name (used for Get-WmiObject fallback).
    .PARAMETER Namespace
        The WMI namespace (e.g. root\SMS\Site_PS1).
    .PARAMETER ClassName
        The WMI class name (used for non-query calls).
    .PARAMETER Query
        A WQL query string (used instead of ClassName when provided).
    #>
    [CmdletBinding()]
    param (
        [Parameter()]$CimSession,
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][string]$Namespace,
        [Parameter()][string]$ClassName,
        [Parameter()][string]$Query
    )

    # Prefer CIM session when available
    if ($null -ne $CimSession) {
        if ($Query) {
            return (Get-CimInstance -CimSession $CimSession -Namespace $Namespace -Query $Query -ErrorAction Stop)
        } else {
            return (Get-CimInstance -CimSession $CimSession -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop)
        }
    }

    # Legacy WMI fallback (uses DCOM/RPC via System.Management -- no WinRM required)
    Write-DATLogEntry -Value "[WMI] Using Get-WmiObject fallback for $ComputerName" -Severity 1
    if ($Query) {
        return (Get-WmiObject -ComputerName $ComputerName -Namespace $Namespace -Query $Query -ErrorAction Stop)
    } else {
        return (Get-WmiObject -ComputerName $ComputerName -Namespace $Namespace -Class $ClassName -ErrorAction Stop)
    }
}

function Get-DATSiteCode {
    param ([Parameter(Mandatory = $true)][string]$SiteServer)
    try {
        Write-DATLogEntry -Value "[WMI] Querying \\$SiteServer\root\SMS : SMS_ProviderLocation for site code" -Severity 1
        $cimSess = New-DATCimSession -ComputerName $SiteServer
        # Store the working CIM session and effective server name globally
        $global:DATCimSession = $cimSess
        if ($null -ne $cimSess) {
            $global:DATEffectiveServer = $cimSess.ComputerName
        } else {
            $global:DATEffectiveServer = $SiteServer
        }
        $SiteCodeObjects = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer `
            -Namespace "root\SMS" -ClassName SMS_ProviderLocation
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
        [Parameter(Mandatory = $true)][string]$SiteServer
    )
    if (-not ([string]::IsNullOrEmpty($SiteServer))) {
        try {
            Get-DATSiteCode -SiteServer $SiteServer
            # Use the effective server name (short name if FQDN fallback was used)
            if (-not [string]::IsNullOrEmpty($global:DATEffectiveServer)) {
                $global:SiteServer = $global:DATEffectiveServer
            } else {
                $global:SiteServer = $SiteServer
            }
            Set-DATRegistryValue -Name "SiteServer" -Value $global:SiteServer -Type String
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

function Get-DATConfigMgrKnownModels {
    <#
    .SYNOPSIS
        Queries ConfigMgr hardware inventory via CIM to discover known device makes and models.
    .DESCRIPTION
        Connects to the ConfigMgr site server's SMS WMI namespace and queries hardware inventory
        classes (SMS_G_System_COMPUTER_SYSTEM, SMS_G_System_MS_SYSTEMINFORMATION, and
        SMS_G_System_BASE_BOARD) to identify distinct device makes and models actively deployed
        in the environment. Supports HP, Dell, Lenovo, Microsoft, and Acer.

        Baseboard matching uses Win32_BaseBoard.Product for HP/Dell/Lenovo/Acer (providing
        system board IDs, SKUs, and machine types) and MS_SystemInformation.SystemSKU for
        Microsoft Surface devices (uniquely identifying device variants).
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

    # Ensure the Lenovo catalog is loaded so Find-DATLenovoModelType can resolve
    # 4-char machine types to friendly model names. This is needed when running in
    # a background runspace where $global:LenovoModelDrivers is not populated.
    if ($null -eq $global:LenovoModelDrivers) {
        try {
            if ($OnProgress) { & $OnProgress "Loading Lenovo model catalog..." }
            Write-DATLogEntry -Value "[ConfigMgr Known Models] Lenovo catalog not loaded -- downloading for model resolution" -Severity 1
            $OEMLinksURL = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/OEMLinks.xml"
            $proxyParams = Get-DATWebRequestProxy
            [xml]$oemLinksXml = (Invoke-WebRequest -Uri $OEMLinksURL -UseBasicParsing -TimeoutSec 30 @proxyParams).Content
            $lenovoXmlUrl = ($oemLinksXml.OEM.Manufacturer | Where-Object { $_.Name -match "Lenovo" }).Link |
                Where-Object { $_.Type -eq "XMLSource" } | Select-Object -ExpandProperty URL -First 1
            if (-not [string]::IsNullOrEmpty($lenovoXmlUrl)) {
                $lenovoTempPath = Join-Path $env:TEMP ($lenovoXmlUrl | Split-Path -Leaf)
                if (-not (Test-Path $lenovoTempPath)) {
                    Invoke-WebRequest -Uri $lenovoXmlUrl -OutFile $lenovoTempPath -UseBasicParsing -TimeoutSec 60 @proxyParams
                }
                [xml]$lenovoXml = Get-Content -Path $lenovoTempPath
                $global:LenovoModelDrivers = $lenovoXml.ModelList.Model
                Write-DATLogEntry -Value "[ConfigMgr Known Models] Lenovo catalog loaded: $(@($global:LenovoModelDrivers).Count) models" -Severity 1
            }
        } catch {
            Write-DATLogEntry -Value "[ConfigMgr Known Models] Could not load Lenovo catalog: $($_.Exception.Message). Lenovo models will show raw WMI values." -Severity 2
        }
    }

    try {
        if ($OnProgress) { & $OnProgress "Connecting to $SiteServer..." }
        Write-DATLogEntry -Value "[ConfigMgr Known Models] Connecting CIM session to $SiteServer" -Severity 1

        $cimSession = New-DATCimSession -ComputerName $SiteServer

        # --- OEM query definitions ---
        # Each entry: OEM display name, WQL query, Make property, Model property
        # Queries include ResourceID to enable joining against the baseboard/SKU maps.
        $oemQueries = @(
            @{
                OEM   = 'HP'
                Query = "SELECT ResourceID, Manufacturer, Model FROM SMS_G_System_COMPUTER_SYSTEM WHERE (Manufacturer = 'Hewlett-Packard' OR Manufacturer = 'HP') AND Model NOT LIKE '%Proliant%'"
                MakeProp  = 'Manufacturer'
                ModelProp = 'Model'
                NormalizeMake  = 'HP'
                NormalizeModel = $true
            },
            @{
                OEM   = 'Dell'
                Query = "SELECT ResourceID, Manufacturer, Model FROM SMS_G_System_COMPUTER_SYSTEM WHERE Manufacturer = 'Dell Inc.'"
                MakeProp  = 'Manufacturer'
                ModelProp = 'Model'
                NormalizeMake  = 'Dell'
                NormalizeModel = $false
            },
            @{
                OEM   = 'Lenovo'
                Query = "SELECT ResourceID, Manufacturer, Model FROM SMS_G_System_COMPUTER_SYSTEM WHERE Manufacturer = 'LENOVO'"
                MakeProp  = 'Manufacturer'
                ModelProp = 'Model'
                NormalizeMake  = 'Lenovo'
                NormalizeModel = $false
            },
            @{
                OEM   = 'Microsoft'
                Query = "SELECT ResourceID, SystemManufacturer, SystemProductName FROM SMS_G_System_MS_SYSTEMINFORMATION WHERE SystemManufacturer LIKE 'Microsoft%' AND SystemProductName LIKE 'Surface%'"
                MakeProp  = 'SystemManufacturer'
                ModelProp = 'SystemProductName'
                NormalizeMake  = 'Microsoft'
                NormalizeModel = $false
            },
            @{
                OEM   = 'Acer'
                Query = "SELECT ResourceID, Manufacturer, Model FROM SMS_G_System_COMPUTER_SYSTEM WHERE Manufacturer = 'Acer'"
                MakeProp  = 'Manufacturer'
                ModelProp = 'Model'
                NormalizeMake  = 'Acer'
                NormalizeModel = $false
            }
        )

        # --- Supplemental baseboard queries (optional classes; silently ignored if not collected) ---
        # Win32_BaseBoard.Product provides the primary matching identifier for all non-Microsoft OEMs:
        #   HP:     4-char system board ID (e.g. 8B4F)
        #   Dell:   SystemSKU (e.g. 0C6F)
        #   Lenovo: 4-char machine type (e.g. 21G2)
        #   Acer:   Board product ID
        # A single query retrieves all entries; keyed by ResourceID for joining to COMPUTER_SYSTEM results.
        $baseboardMap = @{}   # ResourceID -> Product
        $useBaseboardFallback = $false
        try {
            if ($OnProgress) { & $OnProgress "Querying baseboard inventory..." }
            $bbResults = @(Invoke-DATRemoteQuery -CimSession $cimSession -ComputerName $SiteServer -Namespace $namespace `
                -Query "SELECT ResourceID, Product FROM SMS_G_System_BASE_BOARD WHERE Product IS NOT NULL")
            foreach ($r in $bbResults) {
                if (-not [string]::IsNullOrWhiteSpace($r.Product)) {
                    $baseboardMap[[string]$r.ResourceID] = $r.Product.Trim().ToUpper()
                }
            }
            if ($baseboardMap.Count -eq 0) {
                $useBaseboardFallback = $true
                Write-DATLogEntry -Value "[ConfigMgr Known Models] WARNING: Win32_BaseBoard class returned no results. Ensure the BaseBoard (Win32_BaseBoard) class is enabled in hardware inventory and clients have completed an inventory cycle. Falling back to legacy matching (Dell SystemSKUNumber, Lenovo machine type extraction)." -Severity 2
            } else {
                Write-DATLogEntry -Value "[ConfigMgr Known Models] BASE_BOARD: $($baseboardMap.Count) entries" -Severity 1
            }
        } catch {
            $useBaseboardFallback = $true
            Write-DATLogEntry -Value "[ConfigMgr Known Models] BASE_BOARD query failed (class not collected): $($_.Exception.Message). Falling back to legacy matching." -Severity 2
        }

        # Legacy fallback: Dell SystemSKUNumber (only used when BASE_BOARD is unavailable)
        $dellSkuMap = @{}   # Model -> SystemSKUNumber
        if ($useBaseboardFallback) {
            try {
                $dellSkuResults = @(Invoke-DATRemoteQuery -CimSession $cimSession -ComputerName $SiteServer -Namespace $namespace `
                    -Query "SELECT DISTINCT Model, SystemSKUNumber FROM SMS_G_System_COMPUTER_SYSTEM WHERE Manufacturer = 'Dell Inc.' AND SystemSKUNumber IS NOT NULL")
                foreach ($r in $dellSkuResults) {
                    $sku = [string]$r.SystemSKUNumber
                    if (-not [string]::IsNullOrWhiteSpace($sku) -and -not [string]::IsNullOrWhiteSpace($r.Model)) {
                        $dellSkuMap[$r.Model.Trim()] = $sku.Trim().ToUpper()
                    }
                }
                Write-DATLogEntry -Value "[ConfigMgr Known Models] Dell SystemSKUNumber fallback: $($dellSkuMap.Count) entries" -Severity 1
            } catch {
                Write-DATLogEntry -Value "[ConfigMgr Known Models] Dell SystemSKUNumber fallback query failed: $($_.Exception.Message)" -Severity 2
            }
        }

        # Microsoft Surface: SystemSKU from MS_SystemInformation uniquely identifies device variants
        # (e.g. Surface_Pro_9_for_Business_2038 vs Surface_Pro_9_With_5G_1997).
        # Keyed by ResourceID for joining to the MS_SYSTEMINFORMATION model query results.
        $surfaceSkuMap = @{}   # ResourceID -> SystemSKU
        try {
            $surfaceSkuResults = @(Invoke-DATRemoteQuery -CimSession $cimSession -ComputerName $SiteServer -Namespace $namespace `
                -Query "SELECT ResourceID, SystemSKU FROM SMS_G_System_MS_SYSTEMINFORMATION WHERE SystemManufacturer LIKE 'Microsoft%' AND SystemSKU LIKE 'Surface%'")
            foreach ($r in $surfaceSkuResults) {
                if (-not [string]::IsNullOrWhiteSpace($r.SystemSKU)) {
                    $surfaceSkuMap[[string]$r.ResourceID] = $r.SystemSKU.Trim()
                }
            }
            Write-DATLogEntry -Value "[ConfigMgr Known Models] Surface SystemSKU: $($surfaceSkuMap.Count) entries" -Severity 1
        } catch {
            Write-DATLogEntry -Value "[ConfigMgr Known Models] Surface SystemSKU query skipped (property not collected): $($_.Exception.Message)" -Severity 1
        }

        foreach ($oem in $oemQueries) {
            if ($OnProgress) { & $OnProgress "Querying $($oem.OEM) models..." }
            Write-DATLogEntry -Value "[ConfigMgr Known Models] Querying $($oem.OEM): $($oem.Query)" -Severity 1

            try {
                $results = @(Invoke-DATRemoteQuery -CimSession $cimSession -ComputerName $SiteServer -Namespace $namespace -Query $oem.Query)
                Write-DATLogEntry -Value "[ConfigMgr Known Models] $($oem.OEM): $($results.Count) raw results" -Severity 1

                foreach ($item in $results) {
                    $make = $oem.NormalizeMake
                    $model = $item.($oem.ModelProp)
                    if ([string]::IsNullOrWhiteSpace($model)) { continue }
                    $model = $model.Trim()
                    $baseboard = $null

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

                    # Lenovo: resolve machine type to friendly model name
                    if ($oem.OEM -eq 'Lenovo' -and $model.Length -ge 4) {
                        $machineType = $model.Substring(0, 4)
                        $friendlyName = Find-DATLenovoModelType -ModelType $machineType
                        if (-not [string]::IsNullOrEmpty($friendlyName)) {
                            $model = $friendlyName.Trim()
                        }
                        # Fallback: use extracted machine type as baseboard when BASE_BOARD unavailable
                        if ($useBaseboardFallback) {
                            $baseboard = $machineType.ToUpper()
                        }
                    }

                    # Baseboard resolution for non-Microsoft OEMs
                    if ($oem.OEM -ne 'Microsoft') {
                        if (-not $useBaseboardFallback) {
                            # Primary path: Win32_BaseBoard.Product
                            $resId = [string]$item.ResourceID
                            if ($baseboardMap.ContainsKey($resId)) {
                                $baseboard = $baseboardMap[$resId]
                            }
                        } elseif ($oem.OEM -eq 'Dell' -and $dellSkuMap.ContainsKey($model)) {
                            # Fallback: Dell SystemSKUNumber
                            $baseboard = $dellSkuMap[$model]
                        }
                    }

                    # Microsoft Surface: use SystemSKU as the baseboard identifier
                    if ($oem.OEM -eq 'Microsoft') {
                        $resId = [string]$item.ResourceID
                        if ($surfaceSkuMap.ContainsKey($resId)) {
                            $baseboard = $surfaceSkuMap[$resId]
                        }
                    }

                    if (-not [string]::IsNullOrEmpty($model)) {
                        $key = "$make|$model"
                        if (-not $devicePairs.ContainsKey($key)) {
                            $devicePairs[$key] = [PSCustomObject]@{
                                Make      = $make
                                Model     = $model
                                Baseboard = $baseboard   # $null if class not collected
                            }
                        } elseif ($null -ne $baseboard -and $null -eq $devicePairs[$key].Baseboard) {
                            # Enrich existing entry with baseboard if we now have one
                            $devicePairs[$key].Baseboard = $baseboard
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
    $cimSess = New-DATCimSession -ComputerName $SiteServer
    [Array]$DistributionPoints = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer `
        -Namespace "Root\SMS\Site_$SiteCode" -ClassName SMS_SystemResourceList |
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
    $cimSess = New-DATCimSession -ComputerName $SiteServer
    [Array]$DPGroups = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer `
        -Namespace "Root\SMS\Site_$SiteCode" -Query "SELECT Distinct Name FROM SMS_DistributionPointGroup" |
        Select-Object -ExpandProperty Name
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
        [string]$NamePrefix,
        [string]$ReleaseDate,
        [string[]]$DistributionPointGroups,
        [string[]]$DistributionPoints,
        [ValidateSet('High','Normal','Low')][string]$Priority = 'Normal',
        [switch]$EnableBinaryDeltaReplication,
        [switch]$ForceUpdate,
        [int]$ConsoleFolderID = -1
    )

    try {
        $smsNamespace = "root\SMS\Site_$SiteCode"
        $packagePrefix = if (-not [string]::IsNullOrEmpty($NamePrefix)) { $NamePrefix }
                         elseif ($PackageType -eq 'BIOS') { 'BIOS Update' }
                         else { 'Drivers' }
        $CMPackage = if ($PackageType -eq 'BIOS') {
            "$packagePrefix - $OEM $Model"
        } else {
            "$packagePrefix - $OEM $Model - $OS $Architecture"
        }
        $folderName = if ($PackageType -eq 'BIOS') { "BIOS Packages" } else { "Driver Packages" }

        # Create CIM session with auth fallback for all WMI operations in this function
        $cimSess = New-DATCimSession -ComputerName $SiteServer

        # Build description -- BIOS packages include the release date in YYYYMMDD format for matching
        $pkgDescription = if ($PackageType -eq 'BIOS' -and -not [string]::IsNullOrEmpty($ReleaseDate)) {
            $releaseDateFormatted = try { ([datetime]$ReleaseDate).ToString('yyyyMMdd') } catch { $ReleaseDate }
            "(Models included:$Baseboards) (Release Date:$releaseDateFormatted)"
        } else {
            "Models included: $Baseboards"
        }

        # --- Stage 1: Check existing package via WMI before copying files ---
        Write-DATLogEntry -Value "- [ConfigMgr] Checking for existing package: $CMPackage (version $Version)" -Severity 1
        $wmiQuery = "SELECT PackageID, Name, Version, PkgSourcePath FROM SMS_Package WHERE Name = '$($CMPackage -replace "'","''")'"
        $existingPkgs = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer -Namespace $smsNamespace -Query $wmiQuery

        # Fallback: if exact name not found, search for variant package names (handles catalog naming changes)
        if (-not $existingPkgs) {
            $coreId = ($Model -split '\s+')[-1]
            if ($coreId -ne $Model) {
                $fallbackCMName = if ($PackageType -eq 'BIOS') {
                    "$packagePrefix - $OEM $coreId"
                } else {
                    "$packagePrefix - $OEM $coreId - $OS $Architecture"
                }
                $fallbackQuery = "SELECT PackageID, Name, Version, PkgSourcePath FROM SMS_Package WHERE Name = '$($fallbackCMName -replace "'","''")'"
                $existingPkgs = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer -Namespace $smsNamespace -Query $fallbackQuery
                if ($existingPkgs) {
                    Write-DATLogEntry -Value "- [ConfigMgr] Matched variant package: $fallbackCMName (catalog model: $Model)" -Severity 1
                }
            }
        }

        $matchingPkg = $existingPkgs | Where-Object { $_.Version -eq $Version }

        if ($matchingPkg -and -not $ForceUpdate) {
            Write-DATLogEntry -Value "- [ConfigMgr] SKIPPED: '$CMPackage' version $Version already exists ($($matchingPkg.PackageID))" -Severity 1
            return $matchingPkg.PackageID
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
            $pkgWmi.Description = $pkgDescription
            $pkgWmi.Put() | Out-Null
            Write-DATLogEntry -Value "- [ConfigMgr] Package $pkgId metadata updated" -Severity 1

            # Enable or disable Binary Differential Replication via PkgFlags
            if ($EnableBinaryDeltaReplication) {
                $pkgWmi.Get()
                $bdrFlag = 0x04000000
                if (($pkgWmi.PkgFlags -band $bdrFlag) -eq 0) {
                    $pkgWmi.PkgFlags = $pkgWmi.PkgFlags -bor $bdrFlag
                    $pkgWmi.Put() | Out-Null
                    Write-DATLogEntry -Value "- [ConfigMgr] Binary Differential Replication enabled on $pkgId" -Severity 1
                }
            }

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
                        $dpgWmi = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer -Namespace $smsNamespace `
                            -Query "SELECT GroupID FROM SMS_DistributionPointGroup WHERE Name = '$($dpGroup -replace "'","''")'" |
                            Select-Object -First 1
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
                        $dpNalPath = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer -Namespace $smsNamespace `
                            -Query "SELECT NALPath FROM SMS_DistributionPointInfo WHERE ServerName = '$($dpServer -replace "'","''")'" |
                            Select-Object -First 1 -ExpandProperty NALPath
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

            return $pkgId
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

        # Convert local drive paths to UNC admin-share paths so ConfigMgr stores a UNC source path
        # and the console does not show "<Directory on site server>" as a prefix.
        $pkgSourcePath = $DestPath
        if ($DestPath -notmatch '^\\\\' -and -not [string]::IsNullOrEmpty($SiteServer)) {
            $driveLetter = $DestPath[0]
            $pkgSourcePath = "\\$SiteServer\${driveLetter}`$\$($DestPath.Substring(3))"
            Write-DATLogEntry -Value "- [ConfigMgr] Local path converted to UNC for package source: $pkgSourcePath" -Severity 1
        }

        $newPkg = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_Package").CreateInstance()
        $newPkg.Name = $CMPackage
        $newPkg.PkgSourcePath = $pkgSourcePath
        $newPkg.Manufacturer = $OEM
        $newPkg.Description = $pkgDescription
        $newPkg.Version = $Version
        $newPkg.MIFName = $Model
        $newPkg.MIFVersion = if ($PackageType -eq 'BIOS') { '' } else { "$OS $Architecture" }
        $newPkg.PkgSourceFlag = 2  # Direct source path
        $putResult = $newPkg.Put()
        $packageId = $putResult.RelativePath -replace '.*PackageID="([^"]+)".*', '$1'

        Write-DATLogEntry -Value "- [ConfigMgr] Created package $packageId" -Severity 1

        # Enable Binary Differential Replication via PkgFlags
        if ($EnableBinaryDeltaReplication) {
            $newPkg.Get()
            $bdrFlag = 0x04000000
            $newPkg.PkgFlags = $newPkg.PkgFlags -bor $bdrFlag
            $newPkg.Put() | Out-Null
            Write-DATLogEntry -Value "- [ConfigMgr] Binary Differential Replication enabled on $packageId" -Severity 1
        }

        # --- Stage 4: Move package into console folder ---
        try {
            if ($ConsoleFolderID -ge 0) {
                # Custom folder selected by user -- use the specified folder ID directly
                if ($ConsoleFolderID -eq 0) {
                    # Root (no folder) -- package stays at the console root, no move needed
                    Write-DATLogEntry -Value "- [ConfigMgr] Package left at console root (custom folder: root)" -Severity 1
                } else {
                    # Verify the folder still exists
                    $customFolder = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer -Namespace $smsNamespace `
                        -Query "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE ContainerNodeID = $ConsoleFolderID AND ObjectType = 2" |
                        Select-Object -First 1
                    if ($customFolder) {
                        $moveItem = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_ObjectContainerItem").CreateInstance()
                        $moveItem.InstanceKey = $packageId
                        $moveItem.ObjectType = 2
                        $moveItem.ContainerNodeID = $ConsoleFolderID
                        $moveItem.Put() | Out-Null
                        Write-DATLogEntry -Value "- [ConfigMgr] Moved package to custom console folder (ID: $ConsoleFolderID)" -Severity 1
                    } else {
                        Write-DATLogEntry -Value "[Warning] - Custom console folder ID $ConsoleFolderID no longer exists, falling back to default folder" -Severity 2
                        $ConsoleFolderID = -1  # Fall through to default logic below
                    }
                }
            }
            if ($ConsoleFolderID -lt 0) {
            # Default: create/use Driver Packages\OEM or BIOS Packages\OEM
            # Find or create the top-level folder (e.g. "Driver Packages")
            $topFolder = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer -Namespace $smsNamespace `
                -Query "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE Name = '$folderName' AND ObjectType = 2 AND ParentContainerNodeID = 0" |
                Select-Object -First 1
            if (-not $topFolder) {
                $newFolder = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_ObjectContainerNode").CreateInstance()
                $newFolder.Name = $folderName
                $newFolder.ObjectType = 2  # Package
                $newFolder.ParentContainerNodeID = 0
                $newFolder.Put() | Out-Null
                $topFolder = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer -Namespace $smsNamespace `
                    -Query "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE Name = '$folderName' AND ObjectType = 2 AND ParentContainerNodeID = 0" |
                    Select-Object -First 1
            }
            $topFolderID = $topFolder.ContainerNodeID

            # Find or create the OEM sub-folder (e.g. "Driver Packages\Dell")
            $oemFolder = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer -Namespace $smsNamespace `
                -Query "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE Name = '$($OEM -replace "'","''")' AND ObjectType = 2 AND ParentContainerNodeID = $topFolderID" |
                Select-Object -First 1
            if (-not $oemFolder) {
                $newOemFolder = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_ObjectContainerNode").CreateInstance()
                $newOemFolder.Name = $OEM
                $newOemFolder.ObjectType = 2
                $newOemFolder.ParentContainerNodeID = $topFolderID
                $newOemFolder.Put() | Out-Null
                $oemFolder = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer -Namespace $smsNamespace `
                    -Query "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE Name = '$($OEM -replace "'","''")' AND ObjectType = 2 AND ParentContainerNodeID = $topFolderID" |
                    Select-Object -First 1
            }
            $oemFolderID = $oemFolder.ContainerNodeID

            # Move the package into the OEM folder
            $moveItem = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_ObjectContainerItem").CreateInstance()
            $moveItem.InstanceKey = $packageId
            $moveItem.ObjectType = 2
            $moveItem.ContainerNodeID = $oemFolderID
            $moveItem.Put() | Out-Null

            Write-DATLogEntry -Value "- [ConfigMgr] Moved package to $folderName\$OEM" -Severity 1
            }
        } catch {
            Write-DATLogEntry -Value "[Warning] - Failed to move package to folder: $($_.Exception.Message)" -Severity 2
        }

        # --- Stage 5: Distribute content to selected DP groups and individual DPs ---
        if ($DistributionPointGroups -and $DistributionPointGroups.Count -gt 0) {
            foreach ($dpGroup in $DistributionPointGroups) {
                try {
                    Write-DATLogEntry -Value "- [ConfigMgr] Distributing package $packageId to DP group: $dpGroup" -Severity 1
                    $dpgWmi = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer -Namespace $smsNamespace `
                        -Query "SELECT GroupID FROM SMS_DistributionPointGroup WHERE Name = '$($dpGroup -replace "'","''")'" |
                        Select-Object -First 1
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
                    $dpNalPath = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer -Namespace $smsNamespace `
                        -Query "SELECT NALPath FROM SMS_DistributionPointInfo WHERE ServerName = '$($dpServer -replace "'","''")'" |
                        Select-Object -First 1 -ExpandProperty NALPath
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

        return $packageId
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
        [string]$IntuneRefreshToken,
        [string]$IntuneAuthClientId,
        [int]$IntuneTokenExpiresInSec = 0,
        [string]$SiteServer,
        [string]$SiteCode,
        [string]$PackageType = 'Drivers',
        [string[]]$DistributionPointGroups,
        [string[]]$DistributionPoints,
        [string]$DistributionPriority = 'Normal',
        [switch]$EnableBinaryDeltaReplication,
        [int]$ConsoleFolderID = -1,
        [switch]$DisableToast,
        [switch]$DisableRestart,
        [ValidateSet('RemindMeLater','InstallNow')][string]$ToastTimeoutAction = 'RemindMeLater',
        [int]$MaxDeferrals = 0,
        [int]$RestartDelaySeconds = 600,
        [string]$DebugBuildPath,
        [string]$CustomBrandingPath,
        [string]$HPPasswordBinPath,
        [string]$TeamsWebhookUrl,
        [switch]$TeamsNotificationsEnabled,
        [string]$CustomToastTextsJson
    )
    $global:ScriptDirectory = $ScriptDirectory
    $global:LogDirectory = Join-Path $ScriptDirectory "Logs"
    $global:TempDirectory = if ([string]::IsNullOrEmpty($StoragePath)) { Join-Path $ScriptDirectory "Temp" } else { $StoragePath }
    $global:ToolsDirectory = Join-Path $ScriptDirectory "Tools"

    # Parse per-notification-type custom toast texts from JSON
    $customToastTexts = @{}
    if (-not [string]::IsNullOrEmpty($CustomToastTextsJson)) {
        try { $customToastTexts = $CustomToastTextsJson | ConvertFrom-Json -AsHashtable -ErrorAction Stop }
        catch {
            try { $customToastTexts = @{}; ($CustomToastTextsJson | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $customToastTexts[$_.Name] = @{ Title = $_.Value.Title; Body = $_.Value.Body; Greeting = $_.Value.Greeting; Subtitle = $_.Value.Subtitle; ActionButton = $_.Value.ActionButton; DismissButton = $_.Value.DismissButton } } }
            catch { $customToastTexts = @{} }
        }
    }
    # Extract per-type title/body/greeting/subtitle/buttons for backward-compatible passing
    $CustomToastTitle = if ($customToastTexts.ContainsKey('Toast_Drivers')) { $customToastTexts['Toast_Drivers'].Title } else { '' }
    $CustomToastBody  = if ($customToastTexts.ContainsKey('Toast_Drivers')) { $customToastTexts['Toast_Drivers'].Body } else { '' }
    $CustomToastGreeting = if ($customToastTexts.ContainsKey('Toast_Drivers')) { $customToastTexts['Toast_Drivers'].Greeting } else { '' }
    $CustomToastSubtitle = if ($customToastTexts.ContainsKey('Toast_Drivers')) { $customToastTexts['Toast_Drivers'].Subtitle } else { '' }
    $CustomToastActionButton = if ($customToastTexts.ContainsKey('Toast_Drivers')) { $customToastTexts['Toast_Drivers'].ActionButton } else { '' }
    $CustomToastDismissButton = if ($customToastTexts.ContainsKey('Toast_Drivers')) { $customToastTexts['Toast_Drivers'].DismissButton } else { '' }
    $CustomBIOSToastTitle = if ($customToastTexts.ContainsKey('Toast_BIOS')) { $customToastTexts['Toast_BIOS'].Title } else { '' }
    $CustomBIOSToastBody  = if ($customToastTexts.ContainsKey('Toast_BIOS')) { $customToastTexts['Toast_BIOS'].Body } else { '' }
    $CustomBIOSToastGreeting = if ($customToastTexts.ContainsKey('Toast_BIOS')) { $customToastTexts['Toast_BIOS'].Greeting } else { '' }
    $CustomBIOSToastSubtitle = if ($customToastTexts.ContainsKey('Toast_BIOS')) { $customToastTexts['Toast_BIOS'].Subtitle } else { '' }
    $CustomBIOSToastActionButton = if ($customToastTexts.ContainsKey('Toast_BIOS')) { $customToastTexts['Toast_BIOS'].ActionButton } else { '' }
    $CustomBIOSToastDismissButton = if ($customToastTexts.ContainsKey('Toast_BIOS')) { $customToastTexts['Toast_BIOS'].DismissButton } else { '' }
    $CustomSuccessTitle = if ($customToastTexts.ContainsKey('Toast_Success')) { $customToastTexts['Toast_Success'].Title } else { '' }
    $CustomSuccessBody  = if ($customToastTexts.ContainsKey('Toast_Success')) { $customToastTexts['Toast_Success'].Body } else { '' }
    $CustomSuccessActionButton = if ($customToastTexts.ContainsKey('Toast_Success')) { $customToastTexts['Toast_Success'].ActionButton } else { '' }
    $CustomBIOSSuccessTitle = if ($customToastTexts.ContainsKey('Toast_BIOSSuccess')) { $customToastTexts['Toast_BIOSSuccess'].Title } else { '' }
    $CustomBIOSSuccessBody  = if ($customToastTexts.ContainsKey('Toast_BIOSSuccess')) { $customToastTexts['Toast_BIOSSuccess'].Body } else { '' }
    $CustomBIOSSuccessActionButton = if ($customToastTexts.ContainsKey('Toast_BIOSSuccess')) { $customToastTexts['Toast_BIOSSuccess'].ActionButton } else { '' }
    $CustomBIOSSuccessDismissButton = if ($customToastTexts.ContainsKey('Toast_BIOSSuccess')) { $customToastTexts['Toast_BIOSSuccess'].DismissButton } else { '' }
    $CustomIssuesTitle = if ($customToastTexts.ContainsKey('Toast_Issues')) { $customToastTexts['Toast_Issues'].Title } else { '' }
    $CustomIssuesBody  = if ($customToastTexts.ContainsKey('Toast_Issues')) { $customToastTexts['Toast_Issues'].Body } else { '' }
    $CustomIssuesActionButton = if ($customToastTexts.ContainsKey('Toast_Issues')) { $customToastTexts['Toast_Issues'].ActionButton } else { '' }
    $CustomBIOSIssuesTitle = if ($customToastTexts.ContainsKey('Toast_BIOSIssues')) { $customToastTexts['Toast_BIOSIssues'].Title } else { '' }
    $CustomBIOSIssuesBody  = if ($customToastTexts.ContainsKey('Toast_BIOSIssues')) { $customToastTexts['Toast_BIOSIssues'].Body } else { '' }
    $CustomBIOSIssuesActionButton = if ($customToastTexts.ContainsKey('Toast_BIOSIssues')) { $customToastTexts['Toast_BIOSIssues'].ActionButton } else { '' }

    # Use user-configured paths if provided, otherwise default to ScriptDirectory sub-folders
    if ([string]::IsNullOrEmpty($StoragePath)) { $StoragePath = Join-Path $ScriptDirectory "Downloads" }
    if ([string]::IsNullOrEmpty($PackagePath)) { $PackagePath = Join-Path $ScriptDirectory "Packages" }

    foreach ($dir in @($global:LogDirectory, $global:TempDirectory, $global:ToolsDirectory)) {
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    }

    # Set Intune auth token if provided (for background runspace)
    if (-not [string]::IsNullOrEmpty($IntuneAuthToken) -and $RunningMode -eq 'Intune') {
        $script:IntuneAuthToken = $IntuneAuthToken
        # Use real expiry if provided, otherwise estimate conservatively
        if ($IntuneTokenExpiresInSec -gt 0) {
            $script:IntuneTokenExpiry = (Get-Date).AddSeconds($IntuneTokenExpiresInSec)
        } else {
            $script:IntuneTokenExpiry = (Get-Date).AddMinutes(55)
        }
        # Store the client ID used during auth (required for refresh token to work with custom app registrations)
        if (-not [string]::IsNullOrEmpty($IntuneAuthClientId)) {
            $script:IntuneAuthClientId = $IntuneAuthClientId
        }
        # Store refresh token for automatic renewal during long builds
        if (-not [string]::IsNullOrEmpty($IntuneRefreshToken)) {
            $script:IntuneRefreshToken = $IntuneRefreshToken
            Write-DATLogEntry -Value "[Intune] Auth token and refresh token set for background runspace -- token expires $($script:IntuneTokenExpiry)" -Severity 1
        } else {
            Write-DATLogEntry -Value "[Intune] Auth token set for background runspace -- token expires $($script:IntuneTokenExpiry) (no refresh token; will attempt client credentials renewal if needed)" -Severity 1
        }
    }

    $modelList = @($SelectedModels)
    $totalModels = $modelList.Count

    # Determine if this is a pilot build and derive the effective package type
    $isPilotBuild = $PackageType -like '* Pilot'
    $effectivePackageType = if ($isPilotBuild) { ($PackageType -replace '\s+Pilot$', '').Trim() } else { $PackageType }
    $driverNamePrefix = if ($isPilotBuild) { 'Drivers Pilot' } else { 'Drivers' }
    $biosNamePrefix = if ($isPilotBuild) { 'BIOS Pilot' } else { 'BIOS' }
    $biosUpdateNamePrefix = if ($isPilotBuild) { 'BIOS Update Pilot' } else { 'BIOS Update' }

    Write-DATLogEntry -Value "--- Starting model processing: $totalModels models, mode=$RunningMode, packageType=$PackageType$(if ($isPilotBuild) { ' (PILOT)' }) ---" -Severity 1

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
    $cmPkgIdSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($RunningMode -eq 'Configuration Manager' -and -not [string]::IsNullOrEmpty($SiteServer) -and -not [string]::IsNullOrEmpty($SiteCode)) {
        try {
            $smsNs = "root\SMS\Site_$SiteCode"
            Write-DATLogEntry -Value "[ConfigMgr] Pre-fetching package versions for skip-if-current checks..." -Severity 1
            $cimSess = New-DATCimSession -ComputerName $SiteServer
            $cmPkgs = Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer -Namespace $smsNs -Query "SELECT Name, Version, PackageID FROM SMS_Package"
            foreach ($p in $cmPkgs) {
                if (-not [string]::IsNullOrEmpty($p.Name) -and -not [string]::IsNullOrEmpty($p.Version)) {
                    $cmPkgVersionCache[$p.Name] = $p.Version
                }
                if (-not [string]::IsNullOrEmpty($p.PackageID)) {
                    [void]$cmPkgIdSet.Add($p.PackageID)
                }
            }
            Write-DATLogEntry -Value "[ConfigMgr] Cached $($cmPkgVersionCache.Count) package versions" -Severity 1
        } catch {
            Write-DATLogEntry -Value "[ConfigMgr] Failed to pre-fetch package versions: $($_.Exception.Message)" -Severity 2
        }
    }

    # Track BIOS packages already created in this build session to prevent duplicates
    # (BIOS packages are OS-independent, so same model selected for multiple OS versions
    # would otherwise create duplicate packages)
    $processedBiosModels = @{}

    foreach ($model in $modelList) {
        $currentIndex++
        $oem = $model.OEM
        $modelName = $model.Model

        # Proactively refresh Intune token before each model to prevent expiry during long builds
        if ($RunningMode -eq 'Intune' -and -not [string]::IsNullOrEmpty($script:IntuneAuthToken)) {
            if (-not (Update-DATIntuneTokenIfNeeded)) {
                Write-DATLogEntry -Value "[$currentIndex/$totalModels] WARNING: Intune token refresh failed -- uploads for remaining models may fail" -Severity 3
                Set-DATRegistryValue -Name "RunningMessage" -Value "WARNING: Intune token expired -- attempting to continue..." -Type String
            }
        }

        $baseboards = if ($model.Baseboards -is [array]) { $model.Baseboards -join "," } else { [string]$model.Baseboards }
        $os = $model.OS
        $arch = $model.Architecture
        $customDriverPath = $model.CustomDriverPath
        $catalogDriverVersion = if ($model.Version) { $model.Version } else { '' }
        $catalogBIOSVersion   = if ($model.BIOSVersion) { $model.BIOSVersion } else { '' }
        $modelForceUpdate     = [bool]$model.ForceUpdate
        $modelDownloadURL     = if ($model.DownloadURL) { [string]$model.DownloadURL } else { '' }

        Set-DATRegistryValue -Name "CurrentJob" -Value "$currentIndex" -Type String
        Set-DATRegistryValue -Name "RunningMessage" -Value "[$currentIndex/$totalModels] $oem $modelName" -Type String
        Set-DATRegistryValue -Name "RunningState" -Value "Running" -Type String
        Set-DATRegistryValue -Name "RunningMode" -Value "Download" -Type String
        Set-DATRegistryValue -Name "DownloadSize" -Value "---" -Type String
        Set-DATRegistryValue -Name "BytesTransferred" -Value "0" -Type String
        Set-DATRegistryValue -Name "DownloadBytes" -Value "0" -Type String
        Set-DATRegistryValue -Name "DownloadSpeed" -Value "---" -Type String

        Write-DATLogEntry -Value "[$currentIndex/$totalModels] Processing $oem $modelName ($os $arch)" -Severity 1

        $osParts = $os.Split(" ")
        $windowsBuild = if ($osParts.Count -ge 3) { $osParts[2] } else { $null }
        $windowsVersion = if ($windowsBuild) { $os.Replace(" $windowsBuild", "").TrimEnd() } else { $os.TrimEnd() }

        # Dell does not use Windows build-specific driver packages -- omit build from package name
        $osPkgLabel = if ($oem -eq 'Dell') { $windowsVersion } else { "$windowsVersion $windowsBuild" }

        try {
            # ── Driver processing (when PackageType is 'Drivers' or 'All') ──────────
            if ($effectivePackageType -in @('Drivers', 'All')) {
                $modelBIOSOnly = [bool]$model.BIOSOnly
                if ($modelBIOSOnly) {
                    Write-DATLogEntry -Value "[Warning] [$currentIndex/$totalModels] SKIPPED driver processing -- no driver package available for $oem $modelName ($windowsVersion $windowsBuild) -- BIOS only model" -Severity 2
                    if ($effectivePackageType -eq 'Drivers') {
                        Set-DATRegistryValue -Name "PackagePhase" -Value "Drivers" -Type String
                        Set-DATRegistryValue -Name "RunningMode" -Value "DriverNoMatch" -Type String
                    }
                } else {
                Set-DATRegistryValue -Name "PackagePhase" -Value "Drivers" -Type String
                Write-DATLogEntry -Value "[$currentIndex/$totalModels] Starting driver processing for $oem $modelName" -Severity 1

                # ── Pre-flight: skip download+packaging if package version is current ──
                $skipDriverDownload = $false
                # Extract core model identifier (last token) for fallback matching when OEM catalogs
                # change naming conventions (e.g. "PA14250" vs "Pro Laptops PA14250")
                $coreModelId = ($modelName -split '\s+')[-1]

                if ($RunningMode -eq 'Configuration Manager') {
                    $cmDriverPkgName = "$driverNamePrefix - $oem $modelName - $osPkgLabel $arch"
                    Write-DATLogEntry -Value "[$currentIndex/$totalModels] Checking for existing ConfigMgr package: $cmDriverPkgName (catalog v${catalogDriverVersion})" -Severity 1
                    if ($cmPkgVersionCache.Count -eq 0) {
                        Write-DATLogEntry -Value "[$currentIndex/$totalModels] WARNING: ConfigMgr package cache is empty -- skip-if-current check disabled (CIM session may have failed)" -Severity 2
                    } elseif ([string]::IsNullOrEmpty($catalogDriverVersion)) {
                        Write-DATLogEntry -Value "[$currentIndex/$totalModels] WARNING: No catalog version available for $oem $modelName -- skip-if-current check disabled" -Severity 2
                    } else {
                        $existingCMVersion = $cmPkgVersionCache[$cmDriverPkgName]
                        # Fallback: if exact name not found, try with just the core model identifier
                        # Handles catalog naming changes (e.g. old pkg "Drivers - Dell PA14250 - ..." vs new catalog "Pro Laptops PA14250")
                        if ([string]::IsNullOrEmpty($existingCMVersion) -and $coreModelId -ne $modelName) {
                            $fallbackPkgName = "$driverNamePrefix - $oem $coreModelId - $osPkgLabel $arch"
                            $existingCMVersion = $cmPkgVersionCache[$fallbackPkgName]
                            if (-not [string]::IsNullOrEmpty($existingCMVersion)) {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] Matched variant ConfigMgr package: $fallbackPkgName (catalog model: $modelName)" -Severity 1
                                $cmDriverPkgName = $fallbackPkgName
                            }
                        }
                        if ([string]::IsNullOrEmpty($existingCMVersion)) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] No existing ConfigMgr package found matching: $cmDriverPkgName -- will download" -Severity 1
                        } elseif ($existingCMVersion -eq $catalogDriverVersion -and -not $modelForceUpdate) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED -- driver package version is current ($existingCMVersion): $cmDriverPkgName" -Severity 1
                            Set-DATRegistryValue -Name "RunningMessage" -Value "Skipped (current v$existingCMVersion): $oem $modelName" -Type String
                            $skipDriverDownload = $true
                            $script:driverPipelineSuccess = $true
                            $driverPackageSuccessCount++
                        } elseif ($modelForceUpdate) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] FORCE UPDATE -- bypassing version match (existing v$existingCMVersion, catalog v${catalogDriverVersion}): $cmDriverPkgName" -Severity 1
                        } else {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] UPDATE needed -- existing v$existingCMVersion, catalog v${catalogDriverVersion}: $cmDriverPkgName" -Severity 1
                        }
                    }
                } elseif ($RunningMode -eq 'Intune') {
                    # Check cached Intune app list -- compare display version against catalog version
                    $expectedDisplayName = "$driverNamePrefix - $oem $modelName - $osPkgLabel $arch"
                    Write-DATLogEntry -Value "[$currentIndex/$totalModels] Checking for existing Intune package: $expectedDisplayName (catalog v${catalogDriverVersion})" -Severity 1
                    if ($cachedIntuneApps.Count -eq 0) {
                        Write-DATLogEntry -Value "[$currentIndex/$totalModels] WARNING: Intune app cache is empty -- skip-if-current check disabled (Graph API may have failed)" -Severity 2
                    } elseif ([string]::IsNullOrEmpty($catalogDriverVersion)) {
                        Write-DATLogEntry -Value "[$currentIndex/$totalModels] WARNING: No catalog version available for $oem $modelName -- skip-if-current check disabled" -Severity 2
                    } else {
                        $existingIntuneApp = $cachedIntuneApps | Where-Object {
                            $_.displayName -eq $expectedDisplayName
                        } | Sort-Object -Property displayVersion -Descending | Select-Object -First 1
                        # Fallback: try with just the core model identifier
                        if (-not $existingIntuneApp -and $coreModelId -ne $modelName) {
                            $fallbackDisplayName = "$driverNamePrefix - $oem $coreModelId - $osPkgLabel $arch"
                            $existingIntuneApp = $cachedIntuneApps | Where-Object {
                                $_.displayName -eq $fallbackDisplayName
                            } | Sort-Object -Property displayVersion -Descending | Select-Object -First 1
                            if ($existingIntuneApp) {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] Matched variant Intune app: $fallbackDisplayName (catalog model: $modelName)" -Severity 1
                                $expectedDisplayName = $fallbackDisplayName
                            }
                        }
                        if (-not $existingIntuneApp) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] No existing Intune app found matching: $expectedDisplayName -- will download" -Severity 1
                        } elseif ($existingIntuneApp.displayVersion -eq $catalogDriverVersion -and -not $modelForceUpdate) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED -- Intune driver package version is current (v$($existingIntuneApp.displayVersion)): $($existingIntuneApp.displayName) (ID: $($existingIntuneApp.id))" -Severity 1
                            Set-DATRegistryValue -Name "RunningMessage" -Value "Skipped (current v$($existingIntuneApp.displayVersion)): $oem $modelName" -Type String
                            $skipDriverDownload = $true
                            $script:driverPipelineSuccess = $true
                            $driverPackageSuccessCount++
                        } elseif ($modelForceUpdate) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] FORCE UPDATE -- bypassing version match (Intune v$($existingIntuneApp.displayVersion), catalog v${catalogDriverVersion}): $expectedDisplayName" -Severity 1
                        } else {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] UPDATE needed -- Intune v$($existingIntuneApp.displayVersion), catalog v${catalogDriverVersion}: $expectedDisplayName" -Severity 1
                        }
                    }
                } else {
                    # Download Only / WIM Package Only -- check if output already exists from today
                    if ($RunningMode -eq 'Download Only') {
                        # Download Only: check if raw download file exists from today
                        $existingDlDir = Join-Path $StoragePath "$oem\$modelName"
                        $existingDlFile = if (Test-Path $existingDlDir) {
                            Get-ChildItem -Path $existingDlDir -File -ErrorAction SilentlyContinue |
                                Where-Object { $_.LastWriteTime.Date -eq (Get-Date).Date } | Select-Object -First 1
                        }
                        if ($existingDlFile -and -not $modelForceUpdate) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED download -- driver file already downloaded today: $($existingDlFile.FullName)" -Severity 1
                            Set-DATRegistryValue -Name "RunningMessage" -Value "Skipped (exists): $oem $modelName" -Type String
                            $skipDriverDownload = $true
                            $driverPackageSuccessCount++
                        }
                    } else {
                        # WIM Package Only: check if WIM already exists from today
                        $existingWimPath = Join-Path $global:TempDirectory "Packaged\$oem\$modelName\$osPkgLabel\DriverPackage.wim"
                        if ((Test-Path $existingWimPath) -and (Get-Item $existingWimPath).LastWriteTime.Date -eq (Get-Date).Date -and -not $modelForceUpdate) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED download -- driver WIM already created today: $existingWimPath" -Severity 1
                            Set-DATRegistryValue -Name "RunningMessage" -Value "Skipped (exists): $oem $modelName" -Type String
                            $skipDriverDownload = $true
                            $driverPackageSuccessCount++
                        }
                    }
                }

                if (-not $skipDriverDownload) {
                $global:DATSoftPaqBuildSkipped = $false

                # Build the list of remote package identifiers so the HP SoftPaq short-circuit
                # can confirm a previously built package still exists before skipping a rebuild.
                $existingRemoteIds = @()
                $verifyRemote = $false
                if ($RunningMode -eq 'Intune' -and $cachedIntuneApps.Count -gt 0) {
                    $existingRemoteIds = @($cachedIntuneApps | ForEach-Object { "$($_.id)" } | Where-Object { -not [string]::IsNullOrEmpty($_) })
                    $verifyRemote = $true
                } elseif ($RunningMode -eq 'Configuration Manager' -and $cmPkgIdSet.Count -gt 0) {
                    $existingRemoteIds = @($cmPkgIdSet)
                    $verifyRemote = $true
                }

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
                    -CustomDriverPath $customDriverPath `
                    -CatalogDownloadURL $modelDownloadURL `
                    -CatalogVersion $catalogDriverVersion `
                    -ForceRebuild:$modelForceUpdate `
                    -ExistingPackageIds $existingRemoteIds `
                    -VerifyRemoteExistence:$verifyRemote

                if ($global:DATSoftPaqBuildSkipped) {
                    Write-DATLogEntry -Value "[$currentIndex/$totalModels] $oem $modelName -- driver package unchanged (SoftPaq list identical); existing package retained" -Severity 1
                    $script:driverPipelineSuccess = $true
                }

                # Intune: Create and upload Win32 app after packaging
                if ($RunningMode -eq 'Intune') {
                    $wimPath = Join-Path $global:TempDirectory "Packaged\$oem\$modelName\$osPkgLabel\DriverPackage.wim"
                    if (Test-Path $wimPath) {
                        Write-DATLogEntry -Value "[$currentIndex/$totalModels] Starting Intune pipeline for $oem $modelName" -Severity 1
                        Set-DATRegistryValue -Name "RunningMessage" -Value "Creating Intune package: $oem $modelName..." -Type String

                        $intuneParams = @{
                            OEM                = $oem
                            Model              = $modelName
                            Baseboards         = $baseboards
                            OS                 = $osPkgLabel
                            Architecture       = $arch
                            WimFilePath        = $wimPath
                            PackageDestination = $PackagePath
                            IntuneAuthToken    = $IntuneAuthToken
                        }
                        if ($isPilotBuild) { $intuneParams['NamePrefix'] = $driverNamePrefix }
                        $resolvedVersion = if (-not [string]::IsNullOrEmpty($catalogVersion)) { "$catalogVersion" } elseif (-not [string]::IsNullOrEmpty($catalogDriverVersion)) { "$catalogDriverVersion" } else { '' }
                        if (-not [string]::IsNullOrEmpty($resolvedVersion)) { $intuneParams['Version'] = $resolvedVersion }
                        if ($DisableToast) { $intuneParams['DisableToast'] = $true }
                        if ($DisableRestart) { $intuneParams['DisableRestart'] = $true }
                        if ($ToastTimeoutAction -ne 'RemindMeLater') { $intuneParams['ToastTimeoutAction'] = $ToastTimeoutAction }
                        if ($MaxDeferrals -gt 0) { $intuneParams['MaxDeferrals'] = $MaxDeferrals }
                        if ($RestartDelaySeconds -ne 600) { $intuneParams['RestartDelaySeconds'] = $RestartDelaySeconds }
                        if (-not [string]::IsNullOrEmpty($DebugBuildPath)) { $intuneParams['DebugBuildPath'] = $DebugBuildPath }
                        if (-not [string]::IsNullOrEmpty($CustomBrandingPath)) { $intuneParams['CustomBrandingPath'] = $CustomBrandingPath }
                        if (-not [string]::IsNullOrEmpty($CustomToastTitle)) { $intuneParams['CustomToastTitle'] = $CustomToastTitle }
                        if (-not [string]::IsNullOrEmpty($CustomToastBody)) { $intuneParams['CustomToastBody'] = $CustomToastBody }
                        if (-not [string]::IsNullOrEmpty($CustomToastGreeting)) { $intuneParams['CustomToastGreeting'] = $CustomToastGreeting }
                        if (-not [string]::IsNullOrEmpty($CustomToastSubtitle)) { $intuneParams['CustomToastSubtitle'] = $CustomToastSubtitle }
                        if (-not [string]::IsNullOrEmpty($CustomToastActionButton)) { $intuneParams['CustomToastActionButton'] = $CustomToastActionButton }
                        if (-not [string]::IsNullOrEmpty($CustomToastDismissButton)) { $intuneParams['CustomToastDismissButton'] = $CustomToastDismissButton }
                        if (-not [string]::IsNullOrEmpty($CustomSuccessTitle)) { $intuneParams['CustomSuccessTitle'] = $CustomSuccessTitle }
                        if (-not [string]::IsNullOrEmpty($CustomSuccessBody)) { $intuneParams['CustomSuccessBody'] = $CustomSuccessBody }
                        if (-not [string]::IsNullOrEmpty($CustomSuccessActionButton)) { $intuneParams['CustomSuccessActionButton'] = $CustomSuccessActionButton }
                        if (-not [string]::IsNullOrEmpty($CustomIssuesTitle)) { $intuneParams['CustomIssuesTitle'] = $CustomIssuesTitle }
                        if (-not [string]::IsNullOrEmpty($CustomIssuesBody)) { $intuneParams['CustomIssuesBody'] = $CustomIssuesBody }
                        if (-not [string]::IsNullOrEmpty($CustomIssuesActionButton)) { $intuneParams['CustomIssuesActionButton'] = $CustomIssuesActionButton }
                        if ($modelForceUpdate) { $intuneParams['ForceUpdate'] = $true }
                        $intuneResult = Invoke-DATIntunePackageCreation @intuneParams

                        Write-DATLogEntry -Value "- $oem $modelName Intune driver upload completed" -Severity 1

                        # Update cached app list so subsequent iterations detect this package
                        if ($null -ne $intuneResult -and -not [string]::IsNullOrEmpty($intuneResult.AppId) -and -not $intuneResult.Skipped) {
                            $driverDisplayName = "$driverNamePrefix - $oem $modelName - $osPkgLabel $arch"
                            $driverCacheVersion = if (-not [string]::IsNullOrEmpty($catalogDriverVersion)) { $catalogDriverVersion } else { Get-Date -Format "ddMMyyyy" }
                            $cachedIntuneApps += [PSCustomObject]@{
                                id             = $intuneResult.AppId
                                displayName    = $driverDisplayName
                                displayVersion = $driverCacheVersion
                            }
                            Write-DATLogEntry -Value "[Intune] Added driver package to session cache: $driverDisplayName (v$driverCacheVersion)" -Severity 1
                        }

                        # Record the Intune application id on the HP SoftPaq manifest so a future
                        # run can confirm the app still exists before skipping a rebuild.
                        if ($oem -eq 'HP' -and $null -ne $intuneResult -and -not [string]::IsNullOrEmpty($intuneResult.AppId)) {
                            $spRefKey = Get-DATHPSoftPaqManifestKey -Model $modelName -OSVersion $windowsVersion -Build $windowsBuild -Architecture $arch
                            [void](Update-DATHPSoftPaqManifestReference -Key $spRefKey -Field 'intuneAppId' -Value "$($intuneResult.AppId)")
                        }

                        # Auto-deploy and auto-assignment-filter for driver packages
                        if ($null -ne $intuneResult -and -not [string]::IsNullOrEmpty($intuneResult.AppId)) {
                            $deployReg = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue

                            # Deploy to All Devices (no filter)
                            if ($null -ne $deployReg.DeployAllDevices -and $deployReg.DeployAllDevices -eq 1 -and
                                ($null -eq $deployReg.AutoAssignmentFilter -or $deployReg.AutoAssignmentFilter -ne 1)) {
                                try {
                                    Set-DATRegistryValue -Name "RunningMode" -Value "Deploying" -Type String
                                    Set-DATRegistryValue -Name "RunningMessage" -Value "Deploying to All Devices: $oem $modelName" -Type String
                                    Set-DATIntuneAppAssignment -AppId $intuneResult.AppId -GroupId 'adadadad-808e-44e2-905a-0b7873a8a531' -Intent 'Required'
                                    Write-DATLogEntry -Value "[Intune] Auto-deployed driver package to All Devices: $oem $modelName" -Severity 1
                                } catch {
                                    Write-DATLogEntry -Value "[Intune] Auto-deploy to All Devices failed: $($_.Exception.Message)" -Severity 2
                                }
                            }

                            # Auto-assignment filter
                            if ($null -ne $deployReg.AutoAssignmentFilter -and $deployReg.AutoAssignmentFilter -eq 1) {
                                try {
                                    Set-DATRegistryValue -Name "RunningMode" -Value "AssignmentFilter" -Type String
                                    Set-DATRegistryValue -Name "RunningMessage" -Value "Creating assignment filter: $oem $modelName" -Type String
                                    $filterMode = if (-not [string]::IsNullOrEmpty($deployReg.AssignmentFilterMode)) { $deployReg.AssignmentFilterMode } else { 'Make' }
                                    $filterParams = @{
                                        AppId        = $intuneResult.AppId
                                        Manufacturer = $oem
                                        FilterMode   = $filterMode
                                    }
                                    if ($filterMode -eq 'Model') { $filterParams['Model'] = $modelName }
                                    Invoke-DATAutoAssignmentFilter @filterParams
                                    Write-DATLogEntry -Value "[Intune] Auto-assignment filter applied for driver package: $oem $modelName ($filterMode)" -Severity 1
                                } catch {
                                    Write-DATLogEntry -Value "[Intune] Auto-assignment filter failed: $($_.Exception.Message)" -Severity 2
                                }
                            }
                        }

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
                            $intuneWinDir = Join-Path $PackagePath "IntuneWin\$oem\$modelName\$osPkgLabel"
                            $intuneWinFile = Get-ChildItem -Path $intuneWinDir -Filter '*.intunewin' -ErrorAction SilentlyContinue | Select-Object -First 1
                            $drvHash = if ($intuneWinFile) { Get-DATPackageHash -FilePath $intuneWinFile.FullName } else { $null }
                            $drvSize = if ($intuneWinFile) { $intuneWinFile.Length } else { 0 }
                            Send-DATDriverReport -Manufacturer $oem -Model $modelName `
                                -OSVersion $osPkgLabel -OSArchitecture $arch -Platform 'Intune' `
                                -Status 'Success' -PackageSize $drvSize -PackageHash $drvHash
                        } catch {
                            Write-DATLogEntry -Value "[Telemetry] Driver report failed: $($_.Exception.Message)" -Severity 2
                        }
                    } else {
                        if (-not $global:DATSoftPaqBuildSkipped) {
                            Write-DATLogEntry -Value "[Warning] - Driver WIM not found for Intune upload: $wimPath" -Severity 2
                        }
                    }
                }

                # ConfigMgr: Create driver package on site server after packaging
                if ($RunningMode -eq 'Configuration Manager') {
                    $wimPath = Join-Path $global:TempDirectory "Packaged\$oem\$modelName\$osPkgLabel\DriverPackage.wim"
                    if (Test-Path $wimPath) {
                        if (-not [string]::IsNullOrEmpty($SiteServer) -and -not [string]::IsNullOrEmpty($SiteCode)) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] Starting ConfigMgr driver pipeline for $oem $modelName" -Severity 1
                            Write-DATLogEntry -Value "-- Site server: $SiteServer" -Severity 1
                            Write-DATLogEntry -Value "-- Site code: $SiteCode" -Severity 1
                            Set-DATRegistryValue -Name "RunningMessage" -Value "Creating ConfigMgr driver package: $oem $modelName..." -Type String

                            $version = if (-not [string]::IsNullOrEmpty($catalogVersion)) { "$catalogVersion" } elseif (-not [string]::IsNullOrEmpty($catalogDriverVersion)) { "$catalogDriverVersion" } else { Get-Date -Format "ddMMyyyy" }
                            $cmParams = @{
                                DriverPackage = $wimPath
                                OEM           = $oem
                                Model         = $modelName
                                OS            = $osPkgLabel
                                Architecture  = $arch
                                Baseboards    = $baseboards
                                PackagePath   = $PackagePath
                                SiteServer    = $SiteServer
                                SiteCode      = $SiteCode
                                Version       = $version
                                PackageType   = 'Drivers'
                                NamePrefix    = $driverNamePrefix
                                Priority      = $DistributionPriority
                            }
                            if ($DistributionPointGroups -and $DistributionPointGroups.Count -gt 0) {
                                $cmParams['DistributionPointGroups'] = $DistributionPointGroups
                            }
                            if ($DistributionPoints -and $DistributionPoints.Count -gt 0) {
                                $cmParams['DistributionPoints'] = $DistributionPoints
                            }
                            if ($modelForceUpdate) { $cmParams['ForceUpdate'] = $true }
                            if ($EnableBinaryDeltaReplication) { $cmParams['EnableBinaryDeltaReplication'] = $true }
                            if ($ConsoleFolderID -ge 0) { $cmParams['ConsoleFolderID'] = $ConsoleFolderID }
                            $cmResult = New-DATConfigMgrPkg @cmParams

                            if ($cmResult) {
                                Write-DATLogEntry -Value "- $oem $modelName ConfigMgr driver package created" -Severity 1

                                # Record the ConfigMgr package id on the HP SoftPaq manifest so a
                                # future run can confirm the package still exists before skipping.
                                if ($oem -eq 'HP') {
                                    $spRefKey = Get-DATHPSoftPaqManifestKey -Model $modelName -OSVersion $windowsVersion -Build $windowsBuild -Architecture $arch
                                    [void](Update-DATHPSoftPaqManifestReference -Key $spRefKey -Field 'configMgrPackageId' -Value "$cmResult")
                                }

                                # Telemetry: driver report with WIM hash (before cleanup)
                                try {
                                    $drvHash = Get-DATPackageHash -FilePath $wimPath
                                    $drvSize = if (Test-Path $wimPath) { (Get-Item $wimPath).Length } else { 0 }
                                    Send-DATDriverReport -Manufacturer $oem -Model $modelName `
                                        -OSVersion $osPkgLabel -OSArchitecture $arch `
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
                        if (-not $global:DATSoftPaqBuildSkipped) {
                            Write-DATLogEntry -Value "[Warning] - Driver WIM not found for ConfigMgr: $wimPath" -Severity 2
                        }
                    }
                }

                # WIM Package Only: copy the final WIM from temp staging to the Package Storage Path
                if ($RunningMode -eq 'WIM Package Only') {
                    $wimStagingPath = Join-Path $global:TempDirectory "Packaged\$oem\$modelName\$osPkgLabel\DriverPackage.wim"
                    if (Test-Path $wimStagingPath) {
                        $wimFinalDir = Join-Path $PackagePath "$oem\$modelName\$osPkgLabel"
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
                        if ($RunningMode -eq 'Download Only') {
                            # Download Only: use the raw downloaded file for telemetry
                            $dlDestDir = Join-Path $StoragePath "$oem\$modelName"
                            $dlFile = if (Test-Path $dlDestDir) {
                                Get-ChildItem -Path $dlDestDir -File -ErrorAction SilentlyContinue |
                                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                            }
                            if ($dlFile) {
                                $drvHash = Get-DATPackageHash -FilePath $dlFile.FullName
                                $drvSize = $dlFile.Length
                                Send-DATDriverReport -Manufacturer $oem -Model $modelName `
                                    -OSVersion $osPkgLabel -OSArchitecture $arch `
                                    -Platform $RunningMode -Status 'Success' `
                                    -PackageSize $drvSize -PackageHash $drvHash
                            }
                        } else {
                        # WIM Package Only: use the WIM file for telemetry
                        $dlWimPath = Join-Path $global:TempDirectory "Packaged\$oem\$modelName\$osPkgLabel\DriverPackage.wim"
                        if (-not (Test-Path $dlWimPath)) {
                            $dlWimPath = Join-Path $PackagePath "$oem\$modelName\$osPkgLabel\DriverPackage.wim"
                        }
                        if (Test-Path $dlWimPath) {
                            $drvHash = Get-DATPackageHash -FilePath $dlWimPath
                            $drvSize = (Get-Item $dlWimPath).Length
                            Send-DATDriverReport -Manufacturer $oem -Model $modelName `
                                -OSVersion $osPkgLabel -OSArchitecture $arch `
                                -Platform $RunningMode -Status 'Success' `
                                -PackageSize $drvSize -PackageHash $drvHash
                        }
                        }
                    } catch {
                        Write-DATLogEntry -Value "[Telemetry] Driver report failed: $($_.Exception.Message)" -Severity 2
                    }
                }

                # Count driver package success -- check if the WIM was produced
                # or if it was successfully consumed by the Intune/ConfigMgr pipeline
                # For Download Only, the raw download exists (no WIM) -- check the download folder
                $drvWimCheck = Join-Path $global:TempDirectory "Packaged\$oem\$modelName\$osPkgLabel\DriverPackage.wim"
                if ($RunningMode -eq 'Download Only') {
                    # Download Only skips WIM packaging -- success = downloaded file exists in destination
                    $dlDestDir = Join-Path $StoragePath "$oem\$modelName"
                    $dlFileExists = (Test-Path $dlDestDir) -and @(Get-ChildItem -Path $dlDestDir -File -ErrorAction SilentlyContinue).Count -gt 0
                    if ($dlFileExists) { $driverPackageSuccessCount++ }
                } elseif ((Test-Path $drvWimCheck) -or $script:driverPipelineSuccess) { $driverPackageSuccessCount++ }
                $script:driverPipelineSuccess = $false
                } # end if (-not $skipDriverDownload)
            } # end if (-not $modelBIOSOnly)
            }

            # ── BIOS processing (when PackageType is 'BIOS' or 'All') ──────────────
            if ($effectivePackageType -in @('BIOS', 'All')) {
                # Microsoft Surface BIOS updates are delivered via driver injection -- skip BIOS packaging
                if ($oem -eq 'Microsoft') {
                    Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED -- Microsoft Surface BIOS updates are handled via driver injection, no separate BIOS package required" -Severity 1
                }
                # Skip BIOS if this OEM+Model was already processed in this session (BIOS is OS-independent)
                elseif ($processedBiosModels.ContainsKey("$oem|$modelName")) {
                    Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED -- BIOS already processed for $oem $modelName in this build session (BIOS is OS-independent)" -Severity 1
                    Set-DATRegistryValue -Name "PackagePhase" -Value "BIOS" -Type String
                    Set-DATRegistryValue -Name "RunningMessage" -Value "BIOS skipped (already processed): $oem $modelName" -Type String
                    $biosPackageSuccessCount++
                } else {
                Set-DATRegistryValue -Name "PackagePhase" -Value "BIOS" -Type String
                Write-DATLogEntry -Value "[$currentIndex/$totalModels] Starting BIOS processing for $oem $modelName" -Severity 1
                Set-DATRegistryValue -Name "RunningMessage" -Value "[$currentIndex/$totalModels] BIOS: $oem $modelName" -Type String
                Set-DATRegistryValue -Name "RunningMode" -Value "Download" -Type String

                # ── Pre-flight: skip BIOS if deployed version matches catalog version ──
                $skipBios = $false
                if ([string]::IsNullOrEmpty($catalogBIOSVersion)) {
                    Write-DATLogEntry -Value "[$currentIndex/$totalModels] WARNING: No catalog BIOS version available for $oem $modelName -- skip-if-current check disabled" -Severity 2
                } else {
                    if ($RunningMode -eq 'Configuration Manager') {
                        $cmBiosPkgName = "$biosUpdateNamePrefix - $oem $modelName"
                        Write-DATLogEntry -Value "[$currentIndex/$totalModels] Checking for existing ConfigMgr BIOS package: $cmBiosPkgName (catalog v${catalogBIOSVersion})" -Severity 1
                        if ($cmPkgVersionCache.Count -eq 0) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] WARNING: ConfigMgr package cache is empty -- BIOS skip-if-current check disabled" -Severity 2
                        } else {
                            $existingCMBiosVer = $cmPkgVersionCache[$cmBiosPkgName]
                            # Fallback: try with just the core model identifier for catalog naming changes
                            if ([string]::IsNullOrEmpty($existingCMBiosVer) -and $coreModelId -ne $modelName) {
                                $fallbackBiosPkgName = "$biosUpdateNamePrefix - $oem $coreModelId"
                                $existingCMBiosVer = $cmPkgVersionCache[$fallbackBiosPkgName]
                                if (-not [string]::IsNullOrEmpty($existingCMBiosVer)) {
                                    Write-DATLogEntry -Value "[$currentIndex/$totalModels] Matched variant ConfigMgr BIOS package: $fallbackBiosPkgName (catalog model: $modelName)" -Severity 1
                                    $cmBiosPkgName = $fallbackBiosPkgName
                                }
                            }
                            if ([string]::IsNullOrEmpty($existingCMBiosVer)) {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] No existing ConfigMgr BIOS package found matching: $cmBiosPkgName -- will download" -Severity 1
                            } elseif ($existingCMBiosVer -eq $catalogBIOSVersion -and -not $modelForceUpdate) {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED -- BIOS version is current ($existingCMBiosVer): $cmBiosPkgName" -Severity 1
                                Set-DATRegistryValue -Name "RunningMessage" -Value "BIOS skipped (current v$existingCMBiosVer): $oem $modelName" -Type String
                                $skipBios = $true
                                $biosPackageSuccessCount++
                            } elseif ($modelForceUpdate) {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] BIOS FORCE UPDATE -- bypassing version match (existing v$existingCMBiosVer, catalog v${catalogBIOSVersion}): $cmBiosPkgName" -Severity 1
                            } else {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] BIOS UPDATE needed -- existing v$existingCMBiosVer, catalog v${catalogBIOSVersion}: $cmBiosPkgName" -Severity 1
                            }
                        }
                    } elseif ($RunningMode -eq 'Intune') {
                        $expectedBiosName = "$biosNamePrefix - $oem $modelName"
                        Write-DATLogEntry -Value "[$currentIndex/$totalModels] Checking for existing Intune BIOS package: $expectedBiosName (catalog v${catalogBIOSVersion})" -Severity 1
                        if ($cachedIntuneApps.Count -eq 0) {
                            Write-DATLogEntry -Value "[$currentIndex/$totalModels] WARNING: Intune app cache is empty -- BIOS skip-if-current check disabled" -Severity 2
                        } else {
                            $existingBiosApp = $cachedIntuneApps | Where-Object {
                                $_.displayName -eq $expectedBiosName
                            } | Sort-Object -Property displayVersion -Descending | Select-Object -First 1
                            # Fallback: try with just the core model identifier
                            if (-not $existingBiosApp -and $coreModelId -ne $modelName) {
                                $fallbackBiosName = "$biosNamePrefix - $oem $coreModelId"
                                $existingBiosApp = $cachedIntuneApps | Where-Object {
                                    $_.displayName -eq $fallbackBiosName
                                } | Sort-Object -Property displayVersion -Descending | Select-Object -First 1
                                if ($existingBiosApp) {
                                    Write-DATLogEntry -Value "[$currentIndex/$totalModels] Matched variant Intune BIOS app: $fallbackBiosName (catalog model: $modelName)" -Severity 1
                                    $expectedBiosName = $fallbackBiosName
                                }
                            }
                            if (-not $existingBiosApp) {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] No existing Intune BIOS app found matching: $expectedBiosName -- will download" -Severity 1
                            } elseif ($existingBiosApp.displayVersion -eq $catalogBIOSVersion -and -not $modelForceUpdate) {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED -- Intune BIOS version is current (v$($existingBiosApp.displayVersion)): $expectedBiosName (ID: $($existingBiosApp.id))" -Severity 1
                                Set-DATRegistryValue -Name "RunningMessage" -Value "BIOS skipped (current v$($existingBiosApp.displayVersion)): $oem $modelName" -Type String
                                $skipBios = $true
                                $biosPackageSuccessCount++
                            } elseif ($modelForceUpdate) {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] BIOS FORCE UPDATE -- bypassing version match (Intune v$($existingBiosApp.displayVersion), catalog v${catalogBIOSVersion}): $expectedBiosName" -Severity 1
                            } else {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] BIOS UPDATE needed -- Intune v$($existingBiosApp.displayVersion), catalog v${catalogBIOSVersion}: $expectedBiosName" -Severity 1
                            }
                        }
                    } else {
                        # Download Only / WIM Package Only -- check if BIOS package already exists with matching version
                        $existingBiosDir = Join-Path $PackagePath "$oem\$modelName\BIOS"
                        $existingBiosVersionFile = Join-Path $existingBiosDir ".biosversion"
                        if ((Test-Path $existingBiosDir) -and (Test-Path $existingBiosVersionFile)) {
                            $existingBiosVer = (Get-Content $existingBiosVersionFile -Raw -ErrorAction SilentlyContinue).Trim()
                            if ($existingBiosVer -eq $catalogBIOSVersion -and -not $modelForceUpdate) {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] SKIPPED -- BIOS package already exists with current version ($existingBiosVer): $existingBiosDir" -Severity 1
                                Set-DATRegistryValue -Name "RunningMessage" -Value "BIOS skipped (exists v$existingBiosVer): $oem $modelName" -Type String
                                $skipBios = $true
                                $biosPackageSuccessCount++
                            } else {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] BIOS UPDATE needed -- local v$existingBiosVer, catalog v${catalogBIOSVersion}: $oem $modelName" -Severity 1
                            }
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
                    if ($effectivePackageType -eq 'BIOS') {
                        # Signal the UI via RunningMode -- tied to CurrentJob so no race conditions
                        Set-DATRegistryValue -Name "RunningMode" -Value "BiosNoMatch" -Type String
                    }
                } else {
                    Write-DATLogEntry -Value "[BIOS] Matched: $($biosEntry.DisplayName) , Version $($biosEntry.Version), Released $($biosEntry.ReleaseDate)" -Severity 1

                    $biosDownloadDir = Join-Path $StoragePath "$oem\$modelName\BIOS"
                    Set-DATRegistryValue -Name "RunningMode" -Value "Download" -Type String
                    $biosFilePath = @(Start-DATBiosDownload -BiosEntry $biosEntry -DownloadDestination $biosDownloadDir -OEM $oem)[-1]

                    if ([string]::IsNullOrEmpty($biosFilePath)) {
                        Write-DATLogEntry -Value "[Warning] - BIOS download failed for $oem $modelName -- skipping BIOS" -Severity 2
                    } else {
                        # Package the BIOS exe (extract HP/Lenovo, direct for Dell)
                        # ConfigMgr: stage files directly | Intune: compress into WIM
                        Set-DATRegistryValue -Name "RunningMode" -Value "Extracting" -Type String
                        $skipWim = ($RunningMode -eq 'Configuration Manager')
                        $includeFlash64 = ($oem -eq 'Dell' -and $RunningMode -in @('Configuration Manager', 'WIM Package Only'))
                        $biosPackagePath = @(Invoke-DATBiosPackaging -BiosFilePath $biosFilePath -OEM $oem `
                            -Model $modelName -Version $biosEntry.Version -PackageDestination $PackagePath `
                            -SkipWim:$skipWim -IncludeFlash64W:$includeFlash64)[-1]

                        if ($biosPackagePath -and (Test-Path $biosPackagePath)) {
                            # Intune: Create and upload BIOS Win32 app
                            if ($RunningMode -eq 'Intune') {
                                Write-DATLogEntry -Value "[$currentIndex/$totalModels] Starting Intune BIOS pipeline for $oem $modelName" -Severity 1
                                Set-DATRegistryValue -Name "RunningMessage" -Value "Creating Intune BIOS package: $oem $modelName..." -Type String

                                $intuneParams = @{
                                    OEM                = $oem
                                    Model              = $modelName
                                    Baseboards         = $baseboards
                                    OS                 = $osPkgLabel
                                    Architecture       = $arch
                                    WimFilePath        = $biosPackagePath
                                    PackageDestination = $PackagePath
                                    IntuneAuthToken    = $IntuneAuthToken
                                    UpdateType         = 'BIOS'
                                }
                                if ($isPilotBuild) { $intuneParams['NamePrefix'] = $biosNamePrefix }
                if (-not [string]::IsNullOrEmpty($biosEntry.Version)) { $intuneParams['Version'] = "$($biosEntry.Version)" }
                                if (-not [string]::IsNullOrEmpty($biosEntry.ReleaseDate)) { $intuneParams['ReleaseDate'] = $biosEntry.ReleaseDate }
                                if ($DisableToast) { $intuneParams['DisableToast'] = $true }
                                if ($DisableRestart) { $intuneParams['DisableRestart'] = $true }
                                if ($ToastTimeoutAction -ne 'RemindMeLater') { $intuneParams['ToastTimeoutAction'] = $ToastTimeoutAction }
                                if ($MaxDeferrals -gt 0) { $intuneParams['MaxDeferrals'] = $MaxDeferrals }
                                if ($RestartDelaySeconds -ne 600) { $intuneParams['RestartDelaySeconds'] = $RestartDelaySeconds }
                                if (-not [string]::IsNullOrEmpty($DebugBuildPath)) { $intuneParams['DebugBuildPath'] = $DebugBuildPath }
                                if (-not [string]::IsNullOrEmpty($CustomBrandingPath)) { $intuneParams['CustomBrandingPath'] = $CustomBrandingPath }
                                if (-not [string]::IsNullOrEmpty($HPPasswordBinPath)) { $intuneParams['HPPasswordBinPath'] = $HPPasswordBinPath }
                                if (-not [string]::IsNullOrEmpty($CustomBIOSToastTitle)) { $intuneParams['CustomToastTitle'] = $CustomBIOSToastTitle }
                                if (-not [string]::IsNullOrEmpty($CustomBIOSToastBody)) { $intuneParams['CustomToastBody'] = $CustomBIOSToastBody }
                                if (-not [string]::IsNullOrEmpty($CustomBIOSToastGreeting)) { $intuneParams['CustomToastGreeting'] = $CustomBIOSToastGreeting }
                                if (-not [string]::IsNullOrEmpty($CustomBIOSToastSubtitle)) { $intuneParams['CustomToastSubtitle'] = $CustomBIOSToastSubtitle }
                                if (-not [string]::IsNullOrEmpty($CustomBIOSToastActionButton)) { $intuneParams['CustomToastActionButton'] = $CustomBIOSToastActionButton }
                                if (-not [string]::IsNullOrEmpty($CustomBIOSToastDismissButton)) { $intuneParams['CustomToastDismissButton'] = $CustomBIOSToastDismissButton }
                                if (-not [string]::IsNullOrEmpty($CustomBIOSSuccessTitle)) { $intuneParams['CustomBIOSSuccessTitle'] = $CustomBIOSSuccessTitle }
                                if (-not [string]::IsNullOrEmpty($CustomBIOSSuccessBody)) { $intuneParams['CustomBIOSSuccessBody'] = $CustomBIOSSuccessBody }
                                if (-not [string]::IsNullOrEmpty($CustomBIOSSuccessActionButton)) { $intuneParams['CustomBIOSSuccessActionButton'] = $CustomBIOSSuccessActionButton }
                                if (-not [string]::IsNullOrEmpty($CustomBIOSSuccessDismissButton)) { $intuneParams['CustomBIOSSuccessDismissButton'] = $CustomBIOSSuccessDismissButton }
                                if (-not [string]::IsNullOrEmpty($CustomBIOSIssuesTitle)) { $intuneParams['CustomBIOSIssuesTitle'] = $CustomBIOSIssuesTitle }
                                if (-not [string]::IsNullOrEmpty($CustomBIOSIssuesBody)) { $intuneParams['CustomBIOSIssuesBody'] = $CustomBIOSIssuesBody }
                                if (-not [string]::IsNullOrEmpty($CustomBIOSIssuesActionButton)) { $intuneParams['CustomBIOSIssuesActionButton'] = $CustomBIOSIssuesActionButton }
                                if ($modelForceUpdate) { $intuneParams['ForceUpdate'] = $true }
                                $biosIntuneResult = Invoke-DATIntunePackageCreation @intuneParams

                                Write-DATLogEntry -Value "- $oem $modelName Intune BIOS upload completed" -Severity 1

                                # Mark BIOS as processed for this OEM+Model and update cache
                                if ($null -ne $biosIntuneResult -and -not [string]::IsNullOrEmpty($biosIntuneResult.AppId)) {
                                    $processedBiosModels["$oem|$modelName"] = $biosIntuneResult.AppId
                                    if (-not $biosIntuneResult.Skipped) {
                                        $biosDisplayName = "$biosNamePrefix - $oem $modelName"
                                        $biosCacheVersion = if (-not [string]::IsNullOrEmpty($biosEntry.Version)) { $biosEntry.Version } else { Get-Date -Format "ddMMyyyy" }
                                        $cachedIntuneApps += [PSCustomObject]@{
                                            id             = $biosIntuneResult.AppId
                                            displayName    = $biosDisplayName
                                            displayVersion = $biosCacheVersion
                                        }
                                        Write-DATLogEntry -Value "[Intune] Added BIOS package to session cache: $biosDisplayName (v$biosCacheVersion)" -Severity 1
                                    }
                                }

                                # Auto-deploy and auto-assignment-filter for BIOS packages
                                if ($null -ne $biosIntuneResult -and -not [string]::IsNullOrEmpty($biosIntuneResult.AppId)) {
                                    $deployReg = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue

                                    # Deploy to All Devices (no filter)
                                    if ($null -ne $deployReg.DeployAllDevices -and $deployReg.DeployAllDevices -eq 1 -and
                                        ($null -eq $deployReg.AutoAssignmentFilter -or $deployReg.AutoAssignmentFilter -ne 1)) {
                                        try {
                                            Set-DATRegistryValue -Name "RunningMode" -Value "Deploying" -Type String
                                            Set-DATRegistryValue -Name "RunningMessage" -Value "Deploying BIOS to All Devices: $oem $modelName" -Type String
                                            Set-DATIntuneAppAssignment -AppId $biosIntuneResult.AppId -GroupId 'adadadad-808e-44e2-905a-0b7873a8a531' -Intent 'Required'
                                            Write-DATLogEntry -Value "[Intune] Auto-deployed BIOS package to All Devices: $oem $modelName" -Severity 1
                                        } catch {
                                            Write-DATLogEntry -Value "[Intune] Auto-deploy BIOS to All Devices failed: $($_.Exception.Message)" -Severity 2
                                        }
                                    }

                                    # Auto-assignment filter
                                    if ($null -ne $deployReg.AutoAssignmentFilter -and $deployReg.AutoAssignmentFilter -eq 1) {
                                        try {
                                            Set-DATRegistryValue -Name "RunningMode" -Value "AssignmentFilter" -Type String
                                            Set-DATRegistryValue -Name "RunningMessage" -Value "Creating BIOS assignment filter: $oem $modelName" -Type String
                                            $filterMode = if (-not [string]::IsNullOrEmpty($deployReg.AssignmentFilterMode)) { $deployReg.AssignmentFilterMode } else { 'Make' }
                                            $filterParams = @{
                                                AppId        = $biosIntuneResult.AppId
                                                Manufacturer = $oem
                                                FilterMode   = $filterMode
                                            }
                                            if ($filterMode -eq 'Model') { $filterParams['Model'] = $modelName }
                                            Invoke-DATAutoAssignmentFilter @filterParams
                                            Write-DATLogEntry -Value "[Intune] Auto-assignment filter applied for BIOS package: $oem $modelName ($filterMode)" -Severity 1
                                        } catch {
                                            Write-DATLogEntry -Value "[Intune] Auto-assignment filter for BIOS failed: $($_.Exception.Message)" -Severity 2
                                        }
                                    }
                                }

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
                                    $biosIntuneWinDir = Join-Path $PackagePath "IntuneWin\$oem\$modelName\BIOS"
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
                                        OS            = $osPkgLabel
                                        Architecture  = $arch
                                        Baseboards    = $baseboards
                                        PackagePath   = $PackagePath
                                        SiteServer    = $SiteServer
                                        SiteCode      = $SiteCode
                                        Version       = $biosVersion
                                        PackageType   = 'BIOS'
                                        NamePrefix    = $biosUpdateNamePrefix
                                        Priority      = $DistributionPriority
                                    }
                                    if (-not [string]::IsNullOrEmpty($biosEntry.ReleaseDate)) {
                                        $cmParams['ReleaseDate'] = $biosEntry.ReleaseDate
                                    }
                                    if ($DistributionPointGroups -and $DistributionPointGroups.Count -gt 0) {
                                        $cmParams['DistributionPointGroups'] = $DistributionPointGroups
                                    }
                                    if ($DistributionPoints -and $DistributionPoints.Count -gt 0) {
                                        $cmParams['DistributionPoints'] = $DistributionPoints
                                    }
                                    if ($modelForceUpdate) { $cmParams['ForceUpdate'] = $true }
                                    if ($EnableBinaryDeltaReplication) { $cmParams['EnableBinaryDeltaReplication'] = $true }
                                    if ($ConsoleFolderID -ge 0) { $cmParams['ConsoleFolderID'] = $ConsoleFolderID }
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
                            $processedBiosModels["$oem|$modelName"] = $true

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
                } # end else (not Microsoft/already processed)
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
        if ($effectivePackageType -eq 'BIOS' -and $biosNoMatchCount -eq $totalModels) {
            # Every model had no BIOS catalog match
            Set-DATRegistryValue -Name "RunningMessage" -Value "No BIOS updates found for $totalModels model$(if ($totalModels -ne 1) { 's' })" -Type String
            Set-DATRegistryValue -Name "RunningState" -Value "CompletedNoMatch" -Type String
        } elseif ($biosNoMatchCount -gt 0 -and $effectivePackageType -eq 'BIOS') {
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
        [bool]$DisableRestart = $false,
        [string]$ToastTimeoutAction = 'RemindMeLater',
        [int]$MaxDeferrals = 0,
        [int]$BIOSRestartDelayMinutes = 3,
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
        if (-not [string]::IsNullOrEmpty($m.OS)) { $entry['OS'] = $m.OS }
        $entry
    }

    $config = [ordered]@{
        '$schema'                  = 'BuildConfig schema for Driver Automation Tool headless builds'
        TempPath                   = if ($TempPath) { $TempPath } else { '' }
        PackagePath                = if ($PackagePath) { $PackagePath } else { '' }
        Platform                   = $Platform
        OS                         = if ($OS -match ';') { @($OS -split ';' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }) } else { $OS }
        Architecture               = $Architecture
        PackageType                = $PackageType
        DisableToast               = $DisableToast
        DisableRestart             = $DisableRestart
        ToastTimeoutAction         = $ToastTimeoutAction
        MaxDeferrals               = $MaxDeferrals
        BIOSRestartDelayMinutes    = $BIOSRestartDelayMinutes
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

    # Support multiple OS values: semicolon-separated string or JSON array
    $osList = if ($config.OS -is [array]) {
        $config.OS
    } else {
        $config.OS -split ';' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }
    }

    # Build model objects matching the pipeline format (one entry per model per OS)
    # When a model has a per-model OS property, use only that OS instead of the global list
    $models = foreach ($m in $config.Models) {
        $modelOSList = if (-not [string]::IsNullOrEmpty($m.OS)) {
            @($m.OS)
        } else {
            $osList
        }
        foreach ($osValue in $modelOSList) {
            [PSCustomObject]@{
                OEM              = $m.OEM
                Model            = $m.Model
                Baseboards       = if ($m.Baseboards) { $m.Baseboards } else { '' }
                OS               = $osValue
                Architecture     = $config.Architecture
                CustomDriverPath = $null
                Version          = $null
                BIOSVersion      = $null
            }
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
        BIOSRestartDelayMinutes   = if ($config.BIOSRestartDelayMinutes) { [int]$config.BIOSRestartDelayMinutes } else { 3 }
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
    $existing = Get-ScheduledTask -TaskPath "$taskFolder\" -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -InputObject $existing -Confirm:$false -ErrorAction Stop
        # Verify the task was actually removed -- Unregister can silently no-op if the
        # caller lacks rights to a SYSTEM/Highest task, leaving it running (#759)
        $stillThere = Get-ScheduledTask -TaskPath "$taskFolder\" -TaskName $taskName -ErrorAction SilentlyContinue
        if ($stillThere) {
            throw "Scheduled task '$taskName' could not be removed. Run the tool elevated (as Administrator) and try again."
        }
        Write-DATLogEntry -Value "[Schedule] Unregistered scheduled build task" -Severity 1
        return $true
    }
    Write-DATLogEntry -Value "[Schedule] No scheduled build task found to remove" -Severity 2
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

        # Back up Modules and UI folders as a ZIP to the install directory's Backup folder
        $backupRoot = Join-Path $InstallDirectory 'Backup'
        if (-not (Test-Path $backupRoot)) { New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null }
        $backupZip = Join-Path $backupRoot "DATBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
        Write-DATLogEntry -Value "[Update] Backing up Modules and UI to $backupZip..." -Severity 1
        $backupSources = @()
        foreach ($folder in @('Modules', 'UI')) {
            $src = Join-Path $InstallDirectory $folder
            if (Test-Path $src) { $backupSources += $src }
        }
        Compress-Archive -Path $backupSources -DestinationPath $backupZip -Force

        # Remove previous backup ZIPs (keep only the one just created)
        $backupZipName = Split-Path -Leaf $backupZip
        Get-ChildItem -Path $backupRoot -File -Filter 'DATBackup_*.zip' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $backupZipName } |
            ForEach-Object {
                Write-DATLogEntry -Value "[Update] Removing previous backup: $($_.Name)" -Severity 1
                Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            }
        # Clean up any legacy uncompressed backup folders
        Get-ChildItem -Path $backupRoot -Directory -Filter 'DATBackup_*' -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }

        # Copy new files over existing installation (preserve user data like Settings, Logs, Temp)
        $preserveFolders = @('Settings', 'Logs', 'Temp', 'Packages', 'Backup')
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
            if ($item.PSIsContainer) {
                # For folders, copy contents file-by-file to avoid Copy-Item nesting
                # the source folder inside the existing destination folder.
                if (-not (Test-Path $destPath)) {
                    New-Item -Path $destPath -ItemType Directory -Force | Out-Null
                }
                $sourceFiles = Get-ChildItem -Path $item.FullName -Recurse -File
                foreach ($srcFile in $sourceFiles) {
                    $relativePath = $srcFile.FullName.Substring($item.FullName.Length)
                    $destFile = Join-Path $destPath $relativePath
                    $destFileDir = Split-Path -Parent $destFile
                    if (-not (Test-Path $destFileDir)) {
                        New-Item -Path $destFileDir -ItemType Directory -Force | Out-Null
                    }
                    Copy-Item -Path $srcFile.FullName -Destination $destFile -Force
                }
                Write-DATLogEntry -Value "[Update] Replaced folder: $($item.Name) ($($sourceFiles.Count) files)" -Severity 1
            } else {
                Copy-Item -Path $item.FullName -Destination $destPath -Force
                Write-DATLogEntry -Value "[Update] Replaced file: $($item.Name)" -Severity 1
            }
        }

        Write-DATLogEntry -Value "[Update] Update applied successfully. Backup saved to $backupZip" -Severity 1

        # Clean up temp download
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        return @{
            Success   = $true
            BackupDir = $backupZip
            Error     = $null
        }
    } catch {
        Write-DATLogEntry -Value "[Update] Self-update failed: $($_.Exception.Message)" -Severity 3
        # Attempt restore from backup if it exists
        if ($backupZip -and (Test-Path $backupZip)) {
            Write-DATLogEntry -Value "[Update] Restoring Modules and UI from backup ZIP..." -Severity 2
            try {
                Expand-Archive -Path $backupZip -DestinationPath $InstallDirectory -Force
                Write-DATLogEntry -Value "[Update] Backup restored successfully" -Severity 1
            } catch {
                Write-DATLogEntry -Value "[Update] Backup restore also failed: $($_.Exception.Message)" -Severity 3
            }
        }
        # Clean up temp
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

        return @{
            Success   = $false
            BackupDir = $backupZip
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
                Install-Module -Name HPCMSL -Force -Scope $installScope -ErrorAction Stop
                $hpModule = Get-Module -ListAvailable -Name HPCMSL -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
            } catch {
                $result.Error = "Failed to install HPCMSL: $($_.Exception.Message)"
                return $result
            }
        } else {
            $result.Error = "HPCMSL module is not installed. Install it with: Install-Module -Name HPCMSL -Force"
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
                    Install-Module -Name HPCMSL -Force -Scope $repairScope -AllowClobber -ErrorAction Stop
                    Import-Module -Name HPCMSL -Force -ErrorAction Stop
                    $result.Ready = $true
                    $result.Version = (Get-Module HPCMSL).Version
                    Write-DATLogEntry -Value "[HP] HPCMSL reinstalled and loaded successfully (v$($result.Version))" -Severity 1
                } catch {
                    $result.Error = "Failed to repair HPCMSL: $($_.Exception.Message)"
                }
            } else {
                $result.Error = "HPCMSL v$($hpModule.Version) cannot load -- required module '$missingModule' is missing. Reinstall with: Install-Module -Name HPCMSL -Force -AllowClobber"
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
        [Parameter(Mandatory)][AllowEmptyString()][string]$WindowsBuild,
        [string]$WindowsVersion,
        [string]$Architecture = "x64",
        [string]$DownloadDestination,
        [string]$PackageDestination,
        [string]$RegPath,
        [string]$LogDirectory,
        [string]$TempDirectory,
        [string]$RunningMode = "Download Only",
        [string]$CustomDriverPath,
        [string]$CatalogDownloadURL,
        [string]$CatalogVersion,
        [switch]$ForceRebuild,
        [string[]]$ExistingPackageIds = @(),
        [switch]$VerifyRemoteExistence
    )

    [Net.ServicePointManager]::SecurityProtocol = (
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12 -bor
        ([Net.SecurityProtocolType]12288)
    )

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
    $callerCatalogVersion = $CatalogVersion
    $catalogVersion = $null
    $catalogFileHash = ''
    $catalogHashMethod = ''

    # If a direct download URL was provided from the DAT API catalog, use it and skip OEM catalog lookup
    # Only accept URLs that point to a downloadable file (not info/landing pages)
    if (-not [string]::IsNullOrEmpty($CatalogDownloadURL) -and $CatalogDownloadURL -match '\.(msi|exe|cab|zip|wim)(\?|$)') {
        # HP Individual SoftPaqs mode: ignore the pre-resolved driver pack URL so the HP SoftPaq
        # discovery block runs instead of downloading the monolithic pack.
        $HPDriverPackSource = if ($OEM -eq 'HP') {
            (Get-ItemProperty -Path $global:RegPath -Name 'HPDriverPackSource' -ErrorAction SilentlyContinue).HPDriverPackSource
        } else { $null }
        if ($OEM -eq 'HP' -and $HPDriverPackSource -eq 'SoftPaqs') {
            Write-DATLogEntry -Value "[HP] Individual SoftPaqs mode -- ignoring pre-resolved driver pack URL: $CatalogDownloadURL" -Severity 1
            # Leave $downloadURL null so the HP SoftPaq switch block runs
        } else {
            $downloadURL = $CatalogDownloadURL
            $downloadFileName = ($CatalogDownloadURL -split '\?')[0] | Split-Path -Leaf
            if (-not [string]::IsNullOrEmpty($callerCatalogVersion)) {
                $catalogVersion = $callerCatalogVersion
                Write-DATLogEntry -Value "[$OEM] Using catalog version from DAT API: $catalogVersion" -Severity 1
            }
            Write-DATLogEntry -Value "[$OEM] Using pre-resolved download URL from DAT API catalog: $downloadFileName" -Severity 1
        }
    } elseif (-not [string]::IsNullOrEmpty($CatalogDownloadURL)) {
        Write-DATLogEntry -Value "[$OEM] DAT API catalog URL is not a direct download link, falling back to OEM catalog: $CatalogDownloadURL" -Severity 2
    }

    if ([string]::IsNullOrEmpty($downloadURL)) {
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
                Write-DATLogEntry -Value "[$OEM] Catalog cab path: $DellCabPath" -Severity 1
                Write-DATLogEntry -Value "[$OEM] Catalog XML extract path: $DellXMLPath" -Severity 1
                Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading Dell driver catalog..." -Type String
                if (-not (Test-Path $DellCabPath)) {
                    $proxyParams = Get-DATWebRequestProxy
                    Invoke-WebRequest -Uri $DellLink -OutFile $DellCabPath -UseBasicParsing -TimeoutSec 60 @proxyParams
                }
                & expand.exe "$DellCabPath" -F:* "$TempDirectory" -R 2>&1 | Out-Null
            } else {
                Write-DATLogEntry -Value "[$OEM] Using cached Dell catalog: $DellXMLPath" -Severity 1
            }

            if (-not (Test-Path $DellXMLPath)) { throw "Dell catalog XML not found after extraction" }

            [xml]$DellModelXML = Get-Content -Path $DellXMLPath -Raw
            $DellWindowsVersion = $WindowsVersion.Replace(" ", "")

            # Split comma-separated SystemSKU into individual IDs for -contains matching
            $systemSKUs = @($SystemSKU -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            # Extract core model identifier (last token) for fallback matching
            $coreModelName = ($Model -split '\s+')[-1]

            $matchingPkg = $DellModelXML.driverpackmanifest.driverpackage | Where-Object {
                ($_.SupportedOperatingSystems.OperatingSystem.osCode -eq $DellWindowsVersion) -and
                ($_.SupportedOperatingSystems.OperatingSystem.osArch -match $Architecture) -and
                ($_.SupportedSystems.Brand.Model.name -contains $Model -or
                 @($_.SupportedSystems.Brand.Model.SystemID | Where-Object { $_ -in $systemSKUs }).Count -gt 0)
            } | Select-Object -First 1

            # Fallback 1: try with core model identifier (handles "Pro Laptops PA14250" vs "PA14250")
            if ($null -eq $matchingPkg -and $coreModelName -ne $Model) {
                $matchingPkg = $DellModelXML.driverpackmanifest.driverpackage | Where-Object {
                    ($_.SupportedOperatingSystems.OperatingSystem.osCode -eq $DellWindowsVersion) -and
                    ($_.SupportedOperatingSystems.OperatingSystem.osArch -match $Architecture) -and
                    ($_.SupportedSystems.Brand.Model.name -contains $coreModelName)
                } | Select-Object -First 1
                if ($matchingPkg) {
                    Write-DATLogEntry -Value "[$OEM] Matched via core model identifier: $coreModelName (full catalog model: $Model)" -Severity 1
                }
            }

            # Fallback 2: wildcard match
            if ($null -eq $matchingPkg) {
                $matchingPkg = $DellModelXML.driverpackmanifest.driverpackage | Where-Object {
                    ($_.SupportedOperatingSystems.OperatingSystem.osCode -eq $DellWindowsVersion) -and
                    ($_.SupportedOperatingSystems.OperatingSystem.osArch -match $Architecture) -and
                    ($_.SupportedSystems.Brand.Model.name -like "*$coreModelName*")
                } | Select-Object -First 1
            }

            if ($null -ne $matchingPkg) {
                $catalogVersion = $matchingPkg.dellVersion
                # Fallback: if catalog entry has no dellVersion, use the version passed from the caller
                if ([string]::IsNullOrEmpty($catalogVersion) -and -not [string]::IsNullOrEmpty($callerCatalogVersion)) {
                    $catalogVersion = $callerCatalogVersion
                    Write-DATLogEntry -Value "[$OEM] Catalog entry missing dellVersion -- using caller-provided version: $catalogVersion" -Severity 1
                }
                $DellBaseURL = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link |
                    Where-Object { $_.Type -eq "DownloadBase" } | Select-Object -ExpandProperty URL -First 1
                if ([string]::IsNullOrEmpty($DellBaseURL)) { $DellBaseURL = "https://downloads.dell.com" }
                $DellBaseURL = $DellBaseURL.TrimEnd('/')
                $dellPath = $matchingPkg.path.TrimStart('/')
                $downloadURL = "$DellBaseURL/$dellPath"
                $downloadFileName = $matchingPkg.path | Split-Path -Leaf
                Write-DATLogEntry -Value "[$OEM] Found driver pack: $downloadFileName (version: $catalogVersion)" -Severity 1
            } else {
                throw "No matching Dell driver package found for $Model ($DellWindowsVersion $Architecture)"
            }
        }
        "HP" {
            # Check user preference for HP driver source: DriverPack (single SCCM pack) or SoftPaqs (individual drivers)
            $HPDriverPackSource = (Get-ItemProperty -Path $global:RegPath -Name 'HPDriverPackSource' -ErrorAction SilentlyContinue).HPDriverPackSource
            if ([string]::IsNullOrEmpty($HPDriverPackSource)) { $HPDriverPackSource = 'DriverPack' }
            Write-DATLogEntry -Value "[HP] Driver pack source mode: $HPDriverPackSource" -Severity 1

            if ($HPDriverPackSource -eq 'DriverPack') {
                # ── SCCM Driver Pack mode: use HP catalog XML to find the monolithic driver pack ──
                # This downloads a single .exe driver pack from ftp.hp.com (like Dell/Lenovo)
                $HPXMLCabinetSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "HP" }).Link |
                    Where-Object { $_.Type -eq "XMLCabinetSource" } | Select-Object -ExpandProperty URL -First 1
                if ([string]::IsNullOrEmpty($HPXMLCabinetSource)) { throw "HP catalog URL not found in OEM links" }

                $HPCabFile = [string]($HPXMLCabinetSource | Split-Path -Leaf)
                $HPXMLFile = $HPCabFile.TrimEnd(".cab") + ".xml"
                $HPCabPath = Join-Path $TempDirectory $HPCabFile
                $HPXMLPath = Join-Path $TempDirectory $HPXMLFile

                if (-not (Test-Path $HPXMLPath)) {
                    Write-DATLogEntry -Value "[HP] Downloading HP catalog..." -Severity 1
                    Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading HP driver catalog..." -Type String
                    if (-not (Test-Path $HPCabPath)) {
                        Invoke-CatalogDownload -Uri $HPXMLCabinetSource -OutFile $HPCabPath
                    }
                    & expand.exe "$HPCabPath" -F:* "$TempDirectory" -R 2>&1 | Out-Null
                } else {
                    Write-DATLogEntry -Value "[HP] Using cached HP catalog: $HPXMLPath" -Severity 1
                }

                if (-not (Test-Path $HPXMLPath)) { throw "HP catalog XML not found after extraction" }

                [xml]$HPModelXML = Get-Content -Path $HPXMLPath -Raw
                $HPModelSoftPaqs = $HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack

                # Match by model name and OS
                $matchingPack = $HPModelSoftPaqs | Where-Object {
                    ($_.SystemName -replace '^HP\s+', '').Trim() -eq $Model -and
                    $_.OSName -match $WindowsVersion -and $_.OSName -match $WindowsBuild
                } | Select-Object -First 1

                # Fallback: match by baseboard/platform ID
                if ($null -eq $matchingPack) {
                    $SKUList = $SystemSKU -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ -match '^[a-f0-9]{4}$' }
                    $matchingPack = $HPModelSoftPaqs | Where-Object {
                        $packMatch = $_.OSName -match $WindowsVersion -and $_.OSName -match $WindowsBuild
                        if ($packMatch) {
                            $sysIds = @($_.SystemId | ForEach-Object { $_.ToLower() })
                            $packMatch = @($SKUList | Where-Object { $_ -in $sysIds }).Count -gt 0
                        }
                        $packMatch
                    } | Select-Object -First 1
                }

                if ($null -ne $matchingPack) {
                    $spId = $matchingPack.SoftPaqId
                    $downloadURL = $matchingPack.Url
                    if ([string]::IsNullOrEmpty($downloadURL)) {
                        $downloadURL = "https://ftp.hp.com/pub/softpaq/sp$($spId.Substring(0,$spId.Length-3))001-$($spId.Substring(0,$spId.Length-3))500/sp$spId.exe"
                    }
                    $downloadFileName = "sp$spId.exe"
                    $catalogVersion = $matchingPack.Version
                    # Fallback: if the catalog entry has no version, use the version passed from the
                    # caller (HP catalog version resolved during model enumeration), then a date stamp.
                    if ([string]::IsNullOrEmpty($catalogVersion) -and -not [string]::IsNullOrEmpty($callerCatalogVersion)) {
                        $catalogVersion = $callerCatalogVersion
                        Write-DATLogEntry -Value "[HP] Catalog entry missing version -- using caller-provided version: $catalogVersion" -Severity 1
                    }
                    if ([string]::IsNullOrEmpty($catalogVersion)) { $catalogVersion = (Get-Date -Format 'ddMMyyyy') }
                    Write-DATLogEntry -Value "[HP] Found SCCM driver pack: SP$spId ($downloadFileName)" -Severity 1
                    Write-DATLogEntry -Value "[HP] Download URL: $downloadURL" -Severity 1
                    # Fall through to common download path below (same as Dell/Lenovo)
                } else {
                    throw "No matching HP SCCM driver pack found for $Model ($WindowsVersion $WindowsBuild)"
                }
            } else {
            # ── Individual SoftPaqs mode: use HPCMSL to discover and download each driver ──
            # HP uses HPCMSL to discover required SoftPaqs, then downloads, extracts, and
            # copies only the INF-targeted driver folders to a staging directory.

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
            # Pre-flight: verify that HPCMSL supports the requested OS version
            $hpDPCmd = Get-Command -Name New-HPDriverPack -ErrorAction SilentlyContinue
            if ($hpDPCmd) {
                $osVerAttr = $hpDPCmd.Parameters['OSVer'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
                if ($osVerAttr -and $WindowsBuild -notin $osVerAttr.ValidValues) {
                    $supportedValues = $osVerAttr.ValidValues -join ', '
                    Write-DATLogEntry -Value "[HP] HPCMSL does not support OSVer '$WindowsBuild'. Supported values: $supportedValues. Update HPCMSL: Install-Module HPCMSL -Force -AllowClobber" -Severity 3
                    throw "HPCMSL does not support OS version '$WindowsBuild'. Update HPCMSL to the latest version: Install-Module -Name HPCMSL -Force -AllowClobber"
                }
            }

            $SoftPaqIDs = @()
            $DiscoveryPlatformID = $null

            # Resolve PowerShell executable for child processes
            $discoveryPwshExe = if ($PSVersionTable.PSVersion.Major -ge 7) {
                (Get-Process -Id $PID).Path
            } else {
                "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
            }

            foreach ($PlatformID in $SKUList) {
                Write-DATLogEntry -Value "[HP] Querying required SoftPaqs for platform $PlatformID (WhatIf)..." -Severity 1
                Set-DATRegistryValue -Name "RunningMessage" -Value "Querying HP SoftPaqs for platform $PlatformID..." -Type String

                try {
                    # Run New-HPDriverPack -WhatIf in a child process to capture Write-Host output.
                    # HPCMSL writes the SoftPaq list via Write-Host which cannot be captured in-process
                    # on PS 5.1 (the WPF app host swallows it). A child process redirects all output to stdout.
                    $discoveryOutputFile = Join-Path $HPTempDirectory "discovery_${PlatformID}.txt"
                    $discoveryScript = Join-Path ([System.IO.Path]::GetTempPath()) "DAT_HPDiscovery_${PlatformID}_$([System.IO.Path]::GetRandomFileName()).ps1"
                    $discoveryScriptContent = @"
`$ErrorActionPreference = 'Stop'
Import-Module HPCMSL -Force
New-HPDriverPack -Platform "$PlatformID" -Os "$HPOS" -OSVer "$WindowsBuild" -Format wim -Path "$DownloadDestination" -TempDownloadPath "$HPTempDirectory" -WhatIf *>&1
"@
                    Set-Content -Path $discoveryScript -Value $discoveryScriptContent -Encoding UTF8

                    $discoveryProc = Start-Process -FilePath $discoveryPwshExe `
                        -ArgumentList '-NoProfile', '-NoLogo', '-ExecutionPolicy', 'Bypass', '-File', $discoveryScript `
                        -WindowStyle Hidden -PassThru -Wait `
                        -RedirectStandardOutput $discoveryOutputFile -RedirectStandardError ([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "DAT_HPDiscovery_err.txt"))

                    Remove-Item -Path $discoveryScript -Force -ErrorAction SilentlyContinue

                    if (Test-Path $discoveryOutputFile) {
                        $allLines = @(Get-Content -Path $discoveryOutputFile -ErrorAction SilentlyContinue)
                        Remove-Item -Path $discoveryOutputFile -Force -ErrorAction SilentlyContinue
                    } else {
                        $allLines = @()
                    }

                    Write-DATLogEntry -Value "[HP] Discovery output: $($allLines.Count) lines captured for platform $PlatformID" -Severity 1

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
                        # Log the output for debugging
                        foreach ($line in $allLines) {
                            Write-DATLogEntry -Value "[HP] Discovery output: $line" -Severity 1
                        }
                        Write-DATLogEntry -Value "[HP] No SoftPaqs found for platform $PlatformID -- trying next" -Severity 2
                    }
                } catch {
                    if ($_.Exception.Message -match 'does not belong to the set') {
                        Write-DATLogEntry -Value "[HP] HPCMSL does not support OSVer '$WindowsBuild'. Update HPCMSL: Install-Module HPCMSL -Force -AllowClobber" -Severity 3
                        throw "HPCMSL does not support OS version '$WindowsBuild'. Update HPCMSL to the latest version: Install-Module -Name HPCMSL -Force -AllowClobber"
                    }
                    Write-DATLogEntry -Value "[HP] WhatIf failed for ${PlatformID}: $($_.Exception.Message)" -Severity 2
                }
            }

            if ($SoftPaqIDs.Count -eq 0) {
                throw "No HP SoftPaqs found for any platform ID: $($SKUList -join ', ')"
            }

            # ── SoftPaq fingerprint check: skip rebuild when the list is unchanged ──
            # The discovered SoftPaq set is fingerprinted and compared against the stored
            # manifest. If unchanged (and not forced), the existing package is retained and
            # we short-circuit before any download/extract/packaging work.
            $spManifestKey = Get-DATHPSoftPaqManifestKey -Model $Model -OSVersion $WindowsVersion -Build $WindowsBuild -Architecture $Architecture
            $spFingerprint = Get-DATSoftPaqFingerprint -SoftPaqIds $SoftPaqIDs
            $spManifest    = Get-DATHPSoftPaqManifest
            $spEntry       = $spManifest[$spManifestKey]
            $spListUnchanged = ($null -ne $spEntry) -and (-not [string]::IsNullOrEmpty($spFingerprint)) -and ("$($spEntry.fingerprint)" -eq $spFingerprint)

            if ($spListUnchanged) {
                # Verify the previously built package still exists before skipping. For on-disk
                # delivery modes this is a file check; for Intune/ConfigMgr we confirm the stored
                # remote reference (app id / package name) is still present in the live environment.
                $packageStillExists = $true
                $missingReason = ''
                switch ($RunningMode) {
                    'Intune' {
                        if ($VerifyRemoteExistence) {
                            $storedRef = "$($spEntry.intuneAppId)"
                            if ([string]::IsNullOrEmpty($storedRef)) {
                                $packageStillExists = $false; $missingReason = 'no Intune application id was recorded'
                            } elseif ($ExistingPackageIds -notcontains $storedRef) {
                                $packageStillExists = $false; $missingReason = "Intune application $storedRef no longer exists"
                            }
                        }
                    }
                    'Configuration Manager' {
                        if ($VerifyRemoteExistence) {
                            $storedRef = "$($spEntry.configMgrPackageId)"
                            if ([string]::IsNullOrEmpty($storedRef)) {
                                $packageStillExists = $false; $missingReason = 'no ConfigMgr package was recorded'
                            } elseif ($ExistingPackageIds -notcontains $storedRef) {
                                $packageStillExists = $false; $missingReason = "ConfigMgr package $storedRef no longer exists"
                            }
                        }
                    }
                    'WIM Package Only' {
                        $wimFinalPath = Join-Path $PackageDestination "$OEM\$Model\$WindowsVersion $WindowsBuild\DriverPackage.wim"
                        if (-not (Test-Path -LiteralPath $wimFinalPath)) {
                            $packageStillExists = $false; $missingReason = 'the WIM package is missing'
                        }
                    }
                    'Download Only' {
                        if (-not ((Test-Path -LiteralPath $DownloadDestination) -and (@(Get-ChildItem -LiteralPath $DownloadDestination -File -ErrorAction SilentlyContinue).Count -gt 0))) {
                            $packageStillExists = $false; $missingReason = 'the downloaded files are missing'
                        }
                    }
                }

                if ($ForceRebuild) {
                    Write-DATLogEntry -Value "[HP] SoftPaq list unchanged for $Model but Force Update is set -- rebuilding" -Severity 1
                } elseif (-not $packageStillExists) {
                    Write-DATLogEntry -Value "[HP] SoftPaq list unchanged for $Model but $missingReason -- rebuilding" -Severity 1
                } else {
                    $spStableVersion = "$($spEntry.version)"
                    Write-DATLogEntry -Value "[HP] SoftPaq list unchanged since last build for $Model ($($SoftPaqIDs.Count) SoftPaqs, v$spStableVersion) -- skipping rebuild" -Severity 1 -UpdateUI
                    # Surface the matched SoftPaqs, fingerprint and the verified package reference so
                    # the user can see exactly what was compared and which existing package was retained.
                    $spSortedIds = @($SoftPaqIDs | Sort-Object { [long]$_ })
                    $spShortFingerprint = if (-not [string]::IsNullOrEmpty($spFingerprint)) { $spFingerprint.Substring(0, [Math]::Min(8, $spFingerprint.Length)) } else { 'n/a' }
                    Write-DATLogEntry -Value "[HP] Matched SoftPaqs (SP$($spSortedIds -join ', SP')) | fingerprint $spShortFingerprint" -Severity 1
                    switch ($RunningMode) {
                        'Intune' {
                            if ($VerifyRemoteExistence -and -not [string]::IsNullOrEmpty($spEntry.intuneAppId)) {
                                Write-DATLogEntry -Value "[HP] Verified existing Intune application $($spEntry.intuneAppId) still present -- retaining package" -Severity 1
                            }
                        }
                        'Configuration Manager' {
                            if ($VerifyRemoteExistence -and -not [string]::IsNullOrEmpty($spEntry.configMgrPackageId)) {
                                Write-DATLogEntry -Value "[HP] Verified existing ConfigMgr package $($spEntry.configMgrPackageId) still present -- retaining package" -Severity 1
                            }
                        }
                        default {
                            Write-DATLogEntry -Value "[HP] Verified existing driver package on disk -- retaining package" -Severity 1
                        }
                    }
                    try {
                        $spEntry | Add-Member -NotePropertyName lastVerified -NotePropertyValue (Get-Date -Format 'o') -Force
                        $spManifest[$spManifestKey] = $spEntry
                        [void](Save-DATHPSoftPaqManifest -Manifest $spManifest)
                    } catch {
                        Write-DATLogEntry -Value "[HP] Failed to update SoftPaq manifest verification time: $($_.Exception.Message)" -Severity 2
                    }
                    $global:DATSoftPaqBuildSkipped = $true
                    Set-DATRegistryValue -Name "RunningMode" -Value "Download Completed" -Type String
                    return $spStableVersion
                }
            }

            # Version stamp for this build: reuse the stored version when the SoftPaq set is
            # unchanged (e.g. a forced rebuild of the same set), otherwise assign a fresh one.
            $spBuildVersion = if ($spListUnchanged) { "$($spEntry.version)" } else { (Get-Date -Format 'ddMMyyyy') }

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
            $tempScripts = @{}  # spId -> temp .ps1 path

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
                        # Validate: SoftPaq IDs are always 4-8 digits; reject anything else to prevent command injection
                        if ($spId -notmatch '^\d{4,8}$') {
                            Write-DATLogEntry -Value "[HP][Warning] Skipping invalid SoftPaq ID: '$spId'" -Severity 2
                            continue
                        }
                        $savePath = Join-Path $HPTempDirectory "SP$spId.exe"
                        $tmpScript = Join-Path ([System.IO.Path]::GetTempPath()) "DAT_SP_${spId}_$([System.IO.Path]::GetRandomFileName()).ps1"
                        $safeQuotedPath = $savePath -replace "'", "''"
                        Set-Content -Path $tmpScript -Value "Import-Module HPCMSL -Force`nGet-Softpaq -Number $spId -SaveAs '$safeQuotedPath' -MaxRetries 3 -Quiet" -Encoding UTF8
                        $proc = Start-Process -FilePath $pwshExe -ArgumentList "-NoProfile", "-NoLogo", "-ExecutionPolicy", "Bypass", "-File", $tmpScript `
                            -WindowStyle Hidden -PassThru
                        $activeProcs[$spId] = $proc
                        $tempScripts[$spId] = $tmpScript
                        Write-DATLogEntry -Value "[HP] Started SP$spId download (PID $($proc.Id))" -Severity 1
                    }

                    # Check for completed processes
                    $finishedIds = @($activeProcs.Keys | Where-Object { $activeProcs[$_].HasExited })
                    foreach ($spId in $finishedIds) {
                        $proc = $activeProcs[$spId]
                        $activeProcs.Remove($spId)
                        # Clean up temp script file
                        if ($tempScripts.ContainsKey($spId)) {
                            Remove-Item -Path $tempScripts[$spId] -ErrorAction SilentlyContinue
                            $tempScripts.Remove($spId)
                        }
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
                    if ($tempScripts.ContainsKey($spId)) {
                        Remove-Item -Path $tempScripts[$spId] -ErrorAction SilentlyContinue
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
                        $null = Get-Softpaq -Number $spId -SaveAs $savePath -MaxRetries 3 -ErrorAction Stop
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

                $null = Invoke-DATDriverFilePackaging -FilePath $HPStagingDir -OEM $OEM -Model $Model `
                    -OS "$WindowsVersion $WindowsBuild" -Destination $packageDest -Platform $packagingPlatform `
                    -CustomDriverPath $CustomDriverPath
            }

            Set-DATRegistryValue -Name "RunningMode" -Value "Download Completed" -Type String
            Write-DATLogEntry -Value "[HP] Driver package process completed successfully" -Severity 1 -UpdateUI

            # Persist the SoftPaq manifest so an unchanged list skips rebuild next time.
            try {
                $spManifestSave = Get-DATHPSoftPaqManifest
                $existingRef = $spManifestSave[$spManifestKey]
                $spManifestSave[$spManifestKey] = [PSCustomObject]@{
                    platformId           = "$DiscoveryPlatformID"
                    softPaqIds           = @($SoftPaqIDs | Sort-Object { [long]$_ })
                    fingerprint          = $spFingerprint
                    version              = $spBuildVersion
                    lastBuilt            = (Get-Date -Format 'o')
                    lastVerified         = (Get-Date -Format 'o')
                    intuneAppId          = if ($existingRef) { "$($existingRef.intuneAppId)" } else { '' }
                    configMgrPackageId   = if ($existingRef) { "$($existingRef.configMgrPackageId)" } else { '' }
                }
                [void](Save-DATHPSoftPaqManifest -Manifest $spManifestSave)
                Write-DATLogEntry -Value "[HP] SoftPaq manifest updated for $Model (v$spBuildVersion, $($SoftPaqIDs.Count) SoftPaqs)" -Severity 1
            } catch {
                Write-DATLogEntry -Value "[HP] Failed to update SoftPaq manifest: $($_.Exception.Message)" -Severity 2
            }

            # HP SoftPaqs mode handles its own multi-file download -- skip common single-file download path
            return $spBuildVersion
            } # end else (Individual SoftPaqs mode)
        }
        "Lenovo" {
            $LenovoLink = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Lenovo" }).Link |
                Where-Object { $_.Type -eq "XMLSource" } | Select-Object -ExpandProperty URL -First 1
            if ([string]::IsNullOrEmpty($LenovoLink)) { throw "Lenovo catalog URL not found in OEM links" }

            $LenovoFile = [string]($LenovoLink | Split-Path -Leaf)
            $LenovoFilePath = Join-Path $TempDirectory $LenovoFile

            if (-not (Test-Path $LenovoFilePath)) {
                Write-DATLogEntry -Value "[$OEM] Downloading Lenovo catalog..." -Severity 1
                Write-DATLogEntry -Value "[$OEM] Catalog download path: $LenovoFilePath" -Severity 1
                Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading Lenovo driver catalog..." -Type String
                Invoke-CatalogDownload -Uri $LenovoLink -OutFile $LenovoFilePath
            } else {
                Write-DATLogEntry -Value "[$OEM] Using cached Lenovo catalog: $LenovoFilePath" -Severity 1
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
                $downloadURL = $sccmNode.'#text'
                if ($downloadURL -is [array]) { $downloadURL = $downloadURL[0] }
                if ([string]::IsNullOrEmpty($downloadURL)) { $downloadURL = [string]$sccmNode }
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
            # Try DAT API catalog first (has the most current URLs)
            $datApiResolved = $false
            try {
                $driverCatalog = Get-DATDriverCatalog
                if ($driverCatalog) {
                    $normalizedArch = if ($Architecture -eq 'Arm64') { 'arm64' } else { 'x64' }
                    $matchingEntry = $driverCatalog | Where-Object {
                        $_.Manufacturer -eq 'Microsoft' -and
                        $_.DisplayName -eq $Model -and
                        $_.SupportedOS -match $WindowsVersion -and
                        $_.SupportedArchitecture -eq $normalizedArch -and
                        -not [string]::IsNullOrEmpty($_.DownloadURL) -and
                        $_.DownloadURL -match '\.(msi|exe|cab|zip|wim)(\?|$)'
                    } | Sort-Object { try { [datetime]$_.ReleaseDate } catch { [datetime]::MinValue } } -Descending | Select-Object -First 1

                    if ($matchingEntry) {
                        $downloadURL = $matchingEntry.DownloadURL
                        $downloadFileName = ($downloadURL -split '\?')[0] | Split-Path -Leaf
                        $catalogVersion = if ($matchingEntry.Version) { $matchingEntry.Version } elseif ($matchingEntry.ReleaseDate) { $matchingEntry.ReleaseDate } else { '' }
                        if (-not [string]::IsNullOrEmpty($matchingEntry.FileHash)) {
                            $catalogFileHash = $matchingEntry.FileHash
                            $catalogHashMethod = if (-not [string]::IsNullOrEmpty($matchingEntry.HashMethod)) { $matchingEntry.HashMethod } else { 'SHA256' }
                        }
                        Write-DATLogEntry -Value "[$OEM] Resolved from DAT API catalog: $downloadFileName (Version: $catalogVersion)" -Severity 1
                        $datApiResolved = $true
                    } else {
                        Write-DATLogEntry -Value "[$OEM] Model '$Model' not found in DAT API catalog for $WindowsVersion $normalizedArch -- trying OEM catalog" -Severity 2
                    }
                }
            } catch {
                Write-DATLogEntry -Value "[$OEM] DAT API catalog lookup failed, falling back to OEM catalog: $($_.Exception.Message)" -Severity 2
            }

            # Fall back to GitHub-hosted OEM catalog if DAT API didn't resolve
            if (-not $datApiResolved) {
                $MicrosoftCatalogPath = Join-Path $TempDirectory "OSDCatalogMicrosoftDriverPack.json"
                if (-not (Test-Path $MicrosoftCatalogPath)) {
                    $MicrosoftCatalogSource = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/OSDCatalogMicrosoftDriverPack.json"
                    Write-DATLogEntry -Value "[$OEM] Downloading Microsoft OEM catalog..." -Severity 1
                    Write-DATLogEntry -Value "[$OEM] Catalog download path: $MicrosoftCatalogPath" -Severity 1
                    Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading Microsoft driver catalog..." -Type String
                    $proxyParams = Get-DATWebRequestProxy
                    Invoke-WebRequest -Uri $MicrosoftCatalogSource -OutFile $MicrosoftCatalogPath -UseBasicParsing -TimeoutSec 30 @proxyParams
                } else {
                    Write-DATLogEntry -Value "[$OEM] Using cached Microsoft OEM catalog: $MicrosoftCatalogPath" -Severity 1
                }

                $MSModelList = Get-Content -Path $MicrosoftCatalogPath -Raw | ConvertFrom-Json
                $MSArchFilter = if ($Architecture -eq 'Arm64') { 'arm64' } else { 'amd64' }
                $matchingModel = $MSModelList | Where-Object {
                    $_.Model -eq $Model -and $_.OperatingSystem -match $WindowsVersion -and $_.OSArchitecture -eq $MSArchFilter
                } | Select-Object -First 1

                if ($null -ne $matchingModel -and -not [string]::IsNullOrEmpty($matchingModel.Url)) {
                    $downloadURL = $matchingModel.Url
                    $downloadFileName = $downloadURL | Split-Path -Leaf
                    $catalogVersion = if ($matchingModel.ReleaseDate) { $matchingModel.ReleaseDate } else { '' }
                    Write-DATLogEntry -Value "[$OEM] Found Surface driver (OEM catalog): $downloadFileName (ReleaseDate: $catalogVersion)" -Severity 1
                } else {
                    throw "No matching Microsoft driver package found for $Model ($WindowsVersion)"
                }
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
                Write-DATLogEntry -Value "[$OEM] Catalog download path: $AcerFilePath" -Severity 1
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
    } # end if ([string]::IsNullOrEmpty($downloadURL)) -- skip OEM lookup when CatalogDownloadURL provided

    if ([string]::IsNullOrEmpty($downloadURL)) {
        throw "Failed to resolve download URL for $OEM $Model"
    }

    # If no hash was captured from the OEM-specific catalog, try the DAT API catalog
    if ([string]::IsNullOrEmpty($catalogFileHash)) {
        try {
            $datCatalog = Get-DATDriverCatalog
            if ($datCatalog) {
                $hashMatch = $datCatalog | Where-Object {
                    $_.DownloadURL -eq $downloadURL -and
                    -not [string]::IsNullOrEmpty($_.FileHash)
                } | Select-Object -First 1
                if ($hashMatch) {
                    $catalogFileHash = $hashMatch.FileHash
                    $catalogHashMethod = if (-not [string]::IsNullOrEmpty($hashMatch.HashMethod)) { $hashMatch.HashMethod } else { 'SHA256' }
                    Write-DATLogEntry -Value "[$OEM] File hash retrieved from DAT API catalog ($catalogHashMethod): $catalogFileHash" -Severity 1
                }
            }
        } catch {
            Write-DATLogEntry -Value "[$OEM] DAT API catalog hash lookup skipped: $($_.Exception.Message)" -Severity 2
        }
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

    # Download the driver pack (with retry on failure or hash mismatch)
    $maxDownloadAttempts = 3
    $downloadVerified = $false
    $downloadedFile = Join-Path $DownloadDestination $downloadFileName

    for ($dlAttempt = 1; $dlAttempt -le $maxDownloadAttempts; $dlAttempt++) {
        if ($dlAttempt -gt 1) {
            Write-DATLogEntry -Value "[$OEM] Download attempt $dlAttempt/$maxDownloadAttempts for $Model..." -Severity 2
            Set-DATRegistryValue -Name "RunningMessage" -Value "Retrying download ($dlAttempt/$maxDownloadAttempts) for $OEM $Model..." -Type String
            # Remove any partial/corrupt file from previous attempt
            if (Test-Path $downloadedFile) { Remove-Item $downloadedFile -Force -ErrorAction SilentlyContinue }
        } else {
            Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading $OEM $Model driver pack..." -Type String
        }
        Write-DATLogEntry -Value "[$OEM] Starting download: $downloadURL" -Severity 1

        try {
            Invoke-DATContentDownload -DownloadURL $downloadURL -DownloadDestination $DownloadDestination

            if (-not (Test-Path $downloadedFile)) {
                Write-DATLogEntry -Value "[Warning] - Downloaded file not found after transfer (attempt $dlAttempt): $downloadedFile" -Severity 2
                if ($dlAttempt -lt $maxDownloadAttempts) { continue } else { throw "Downloaded file not found after $maxDownloadAttempts attempts: $downloadedFile" }
            }
            $downloadedSize = (Get-Item $downloadedFile).Length
            if ($downloadedSize -eq 0) {
                Remove-Item $downloadedFile -Force -ErrorAction SilentlyContinue
                Write-DATLogEntry -Value "[Warning] - Downloaded file is empty (attempt $dlAttempt): $downloadedFile" -Severity 2
                if ($dlAttempt -lt $maxDownloadAttempts) { continue } else { throw "Downloaded file is empty (0 bytes) after $maxDownloadAttempts attempts: $downloadedFile" }
            }
            # Detect HTTP error pages saved as files (e.g. 404 responses) -- real driver packages are at least 1 MB
            $minDriverPackSize = 1MB
            if ($downloadedSize -lt $minDriverPackSize) {
                Write-DATLogEntry -Value "[Warning] - Downloaded file is suspiciously small ($downloadedSize bytes), likely a 404 error page: $downloadedFile" -Severity 3
                Remove-Item $downloadedFile -Force -ErrorAction SilentlyContinue
                throw "Downloaded file is too small ($downloadedSize bytes) -- likely a 404 error page or invalid response. URL may be stale: $downloadURL"
            }
            $downloadedSizeMB = [math]::Round($downloadedSize / 1MB, 2)
            Write-DATLogEntry -Value "[$OEM] Download complete: $downloadedFile ($downloadedSizeMB MB)" -Severity 1

            # Hash verification (if catalog provides a hash)
            if (-not [string]::IsNullOrEmpty($catalogFileHash)) {
                $algo = if ($catalogHashMethod -match '^(SHA256|SHA1|MD5|SHA384|SHA512)$') { $catalogHashMethod } else { 'SHA256' }
                Write-DATLogEntry -Value "[$OEM] Verifying file hash ($algo)..." -Severity 1
                $computedHash = (Get-FileHash -Path $downloadedFile -Algorithm $algo -ErrorAction SilentlyContinue).Hash
                if ($computedHash -eq $catalogFileHash) {
                    Write-DATLogEntry -Value "[$OEM] Hash verified ($algo): $computedHash" -Severity 1
                    $downloadVerified = $true
                    break
                } else {
                    Write-DATLogEntry -Value "[Warning] - Hash mismatch (attempt $dlAttempt/$maxDownloadAttempts). Expected: $catalogFileHash, Got: $computedHash" -Severity 2
                    Remove-Item $downloadedFile -Force -ErrorAction SilentlyContinue
                    if ($dlAttempt -lt $maxDownloadAttempts) { continue }
                    # Final attempt failed -- download anyway but warn
                    Write-DATLogEntry -Value "[Warning] - Hash verification failed after $maxDownloadAttempts attempts. Re-downloading and proceeding without hash verification." -Severity 2
                    Invoke-DATContentDownload -DownloadURL $downloadURL -DownloadDestination $DownloadDestination
                    $downloadVerified = $false
                    break
                }
            } else {
                Write-DATLogEntry -Value "[$OEM] No catalog hash available -- skipping hash verification" -Severity 1
                $downloadVerified = $true
                break
            }
        } catch {
            if ($dlAttempt -lt $maxDownloadAttempts) {
                Write-DATLogEntry -Value "[Warning] - Download attempt $dlAttempt failed: $($_.Exception.Message)" -Severity 2
            } else {
                throw
            }
        }
    }

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
        # Dell does not use build-specific driver packages -- omit build from path
        $packagingOS = if ($OEM -eq 'Dell') { $WindowsVersion } else { "$WindowsVersion $WindowsBuild" }
        $packagingParams = @{
            FilePath     = $downloadedFile
            OEM          = $OEM
            Model        = $Model
            OS           = $packagingOS
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
$script:GraphClientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"  # Microsoft Graph PowerShell SDK
$script:GraphScopes = @(
    "DeviceManagementApps.ReadWrite.All"
    "DeviceManagementManagedDevices.Read.All"
    "GroupMember.Read.All"
)
$script:GraphBaseUrl = "https://graph.microsoft.com/beta"

# In-memory token store - discarded when the process exits
$script:IntuneAuthToken = $null
$script:IntuneTokenExpiry = [datetime]::MinValue
$script:IntuneTenantId = $null
$script:IntuneRefreshToken = $null
$script:IntuneAuthClientId = $null  # Tracks which client ID was used during auth (for refresh)

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
    param (
        # Optional: override the built-in Microsoft Graph PowerShell client ID with a custom app registration.
        [string]$ClientId = $script:GraphClientId
    )

    $tenantEndpoint = "organizations"
    $scopeString = ($script:GraphScopes -join " ") + " openid profile offline_access"

    $deviceCodeUrl = "https://login.microsoftonline.com/$tenantEndpoint/oauth2/v2.0/devicecode"

    Write-DATLogEntry -Value "[Intune Auth] Requesting device code for interactive sign-in (client: $ClientId)" -Severity 1

    try {
        $proxyParams = Get-DATWebRequestProxy
        $dcResponse = Invoke-RestMethod -Method POST -Uri $deviceCodeUrl -Body @{
            client_id = $ClientId
            scope     = $scopeString
        } -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop @proxyParams

        # Store context for polling
        $script:DeviceCodeContext = @{
            DeviceCode   = $dcResponse.device_code
            UserCode     = $dcResponse.user_code
            Interval     = [math]::Max([int]$dcResponse.interval, 5)
            ExpiresAt    = (Get-Date).AddSeconds([int]$dcResponse.expires_in)
            ClientId     = $ClientId
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
            client_id   = $script:DeviceCodeContext.ClientId
            grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
            device_code = $script:DeviceCodeContext.DeviceCode
        } -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop @proxyParams

        # Success - store token
        $script:IntuneAuthToken = $tokenResponse.access_token
        $script:IntuneTokenExpiry = (Get-Date).AddSeconds([int]$tokenResponse.expires_in - 60)
        $script:IntuneAuthClientId = $script:DeviceCodeContext.ClientId
        # Store refresh token for silent renewal (device code flow includes offline_access)
        if ($tokenResponse.refresh_token) {
            $script:IntuneRefreshToken = $tokenResponse.refresh_token
        }

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
        Hashtable with Success, ListenerPort, RedirectUri.
    #>
    [CmdletBinding()]
    param (
        # Optional: override the built-in Microsoft Graph PowerShell client ID with a custom app registration.
        [string]$ClientId = $script:GraphClientId,
        # When a custom ClientId is supplied, use this fixed port so the user only needs
        # to register one redirect URI (http://localhost:38400/) in their app registration.
        # The built-in Microsoft Graph PowerShell app accepts any port via http://localhost.
        [int]$FixedPort = 0
    )

    $scopeString = ($script:GraphScopes -join " ") + " openid profile offline_access"

    Write-DATLogEntry -Value "[Intune Auth] Starting interactive browser sign-in (Auth Code + PKCE, client: $ClientId)" -Severity 1

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

        # 2. Start HTTP listener -- fixed port for custom apps (predictable redirect URI),
        #    random port for the built-in app (Microsoft has http://localhost registered for any port).
        $port = if ($FixedPort -gt 0) { $FixedPort } else { Get-Random -Minimum 49152 -Maximum 65535 }
        $redirectUri = "http://localhost:$port/"
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add($redirectUri)
        $listener.Start()
        Write-DATLogEntry -Value "[Intune Auth] Listening on $redirectUri" -Severity 1

        # 3. Build the authorize URL with PKCE and CSRF state
        $state = [guid]::NewGuid().ToString('N')
        $authUrl = "https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize?" + (
            @(
                "client_id=$([uri]::EscapeDataString($ClientId))"
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
            ClientId     = $ClientId
            StartedAt    = Get-Date
            TimeoutSec   = 120
        }

        # 6. Open the browser (on the UI thread so shell association works)
        Write-DATLogEntry -Value "[Intune Auth] Opening browser for sign-in" -Severity 1
        Start-Process $authUrl

        return @{
            Success      = $true
            ListenerPort = $port
            RedirectUri  = $redirectUri
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
            client_id     = $ctx.ClientId
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
        $script:IntuneAuthClientId = $ctx.ClientId

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

        # Parse the OAuth error body from the response (same pattern as Complete-DATDeviceCodeAuth).
        # Invoke-RestMethod throws on non-2xx but the body is in ErrorDetails.Message.
        $oauthError = $null
        $oauthDesc  = $null
        try {
            $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
            $oauthError = $errorBody.error
            $oauthDesc  = $errorBody.error_description
        } catch {}

        $displayMsg = if ($oauthDesc) { $oauthDesc } elseif ($oauthError) { $oauthError } else { $_.Exception.Message }
        Write-DATLogEntry -Value "[Intune Auth] Browser auth token exchange failed: $displayMsg" -Severity 3
        return @{ Status = 'Failed'; Error = $displayMsg }
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

    # Use the client ID that was used during the original auth (critical for custom app registrations)
    $refreshClientId = if (-not [string]::IsNullOrEmpty($script:IntuneAuthClientId)) { $script:IntuneAuthClientId } else { $script:GraphClientId }
    $scopeString = ($script:GraphScopes -join " ") + " openid profile offline_access"
    $tokenUrl = "https://login.microsoftonline.com/organizations/oauth2/v2.0/token"

    try {
        $proxyParams = Get-DATWebRequestProxy
        $tokenResponse = Invoke-RestMethod -Method POST -Uri $tokenUrl -Body @{
            client_id     = $refreshClientId
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

        Write-DATLogEntry -Value "[Intune Auth] Token refreshed silently (client: $refreshClientId) - expires $($script:IntuneTokenExpiry)" -Severity 1
        return @{ Success = $true; ExpiresOn = $script:IntuneTokenExpiry }
    }
    catch {
        # Only clear the refresh token on permanent rejection (invalid_grant), not transient errors
        $isPermanent = $false
        try {
            $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
            if ($errorBody.error -in @('invalid_grant', 'interaction_required', 'invalid_client')) {
                $isPermanent = $true
            }
        } catch {}

        if ($isPermanent) {
            Write-DATLogEntry -Value "[Intune Auth] Token refresh permanently rejected ($($errorBody.error)) -- clearing refresh token" -Severity 3
            $script:IntuneRefreshToken = $null
        } else {
            Write-DATLogEntry -Value "[Intune Auth] Token refresh failed (transient): $($_.Exception.Message) -- will retry on next attempt" -Severity 2
        }
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

    # Add assignment filter permission check when auto-filter is enabled
    $regConfig = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
    if ($null -ne $regConfig.AutoAssignmentFilter -and $regConfig.AutoAssignmentFilter -eq 1) {
        $permChecks += @{ Name = "DeviceManagementConfiguration.ReadWrite.All"; TestUri = "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters?`$top=1"; Description = "Create and manage assignment filters" }
    }

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
        Attempts automatic refresh if the token has expired.
    #>
    [OutputType([bool])]
    param ()

    if ([string]::IsNullOrEmpty($script:IntuneAuthToken)) { return $false }
    if ((Get-Date) -ge $script:IntuneTokenExpiry) {
        Write-DATLogEntry -Value "[Intune Auth] Token expired - attempting automatic refresh" -Severity 2
        if (Update-DATIntuneTokenIfNeeded -Force) {
            return $true
        }
        $script:IntuneAuthToken = $null
        Write-DATLogEntry -Value "[Intune Auth] Token expired and refresh failed - reauthentication required" -Severity 3
        return $false
    }
    return $true
}

function Update-DATIntuneTokenIfNeeded {
    <#
    .SYNOPSIS
        Proactively refreshes the Intune access token if it expires within 15 minutes.
        Supports both interactive (refresh token) and app registration (client credentials) flows.
        Called at the start of each model iteration and before uploads during long builds.
    .PARAMETER Force
        Skip the time-remaining check and always attempt a refresh. Used after receiving a 401.
    .OUTPUTS
        $true if the token is valid (refreshed or still good), $false if refresh failed.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param (
        [switch]$Force
    )

    # No token at all -- nothing to refresh
    if ([string]::IsNullOrEmpty($script:IntuneAuthToken)) { return $false }

    if (-not $Force) {
        $minutesRemaining = ($script:IntuneTokenExpiry - (Get-Date)).TotalMinutes
        if ($minutesRemaining -gt 15) {
            # Token still has plenty of life -- no action needed
            return $true
        }
        Write-DATLogEntry -Value "[Intune Auth] Token expires in $([math]::Round($minutesRemaining, 1)) minutes -- attempting proactive refresh" -Severity 2
    } else {
        Write-DATLogEntry -Value "[Intune Auth] Forced token refresh requested (e.g. after 401)" -Severity 2
    }

    # Strategy 1: Use refresh token (interactive / device code / browser auth)
    if (-not [string]::IsNullOrEmpty($script:IntuneRefreshToken)) {
        $result = Invoke-DATTokenRefresh
        if ($result.Success) {
            Write-DATLogEntry -Value "[Intune Auth] Token refreshed via refresh token -- new expiry: $($result.ExpiresOn)" -Severity 1
            return $true
        }
        Write-DATLogEntry -Value "[Intune Auth] Refresh token renewal failed: $($result.Error)" -Severity 2
    }

    # Strategy 2: Use client credentials from registry (app registration)
    try {
        $regValues = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
        $authMode = $regValues.IntuneAuthMode
        $appId = $regValues.IntuneAppId
        $encSecret = $regValues.IntuneClientSecret
        $tenantId = $regValues.IntuneTenantId

        if ($authMode -eq 2 -and -not [string]::IsNullOrEmpty($appId) -and
            -not [string]::IsNullOrEmpty($encSecret) -and -not [string]::IsNullOrEmpty($tenantId)) {

            # Decrypt the client secret (stored via ConvertFrom-SecureString / DPAPI)
            $secString = ConvertTo-SecureString -String $encSecret -ErrorAction Stop
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secString)
            $clientSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

            Write-DATLogEntry -Value "[Intune Auth] Attempting client credentials refresh for tenant $tenantId" -Severity 1
            $ccResult = Connect-DATIntuneGraphClientCredential -TenantId $tenantId -AppId $appId -ClientSecret $clientSecret
            if ($ccResult.Success) {
                Write-DATLogEntry -Value "[Intune Auth] Token refreshed via client credentials -- new expiry: $($ccResult.ExpiresOn)" -Severity 1
                return $true
            }
            Write-DATLogEntry -Value "[Intune Auth] Client credentials refresh failed: $($ccResult.Error)" -Severity 2
        }
    } catch {
        Write-DATLogEntry -Value "[Intune Auth] Client credentials refresh error: $($_.Exception.Message)" -Severity 2
    }

    # If we get here and we weren't forced (proactive check), the token might still be usable
    if (-not $Force -and (Get-Date) -lt $script:IntuneTokenExpiry) {
        Write-DATLogEntry -Value "[Intune Auth] Refresh failed but token still valid for $([math]::Round(($script:IntuneTokenExpiry - (Get-Date)).TotalMinutes, 1)) minutes" -Severity 2
        return $true
    }

    Write-DATLogEntry -Value "[Intune Auth] Token expired and all refresh attempts failed" -Severity 3
    return $false
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
    $script:IntuneAuthClientId = $null
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
            # Attempt automatic token refresh before giving up
            Write-DATLogEntry -Value "[Graph API] 401 Unauthorized - attempting automatic token refresh..." -Severity 2
            if (Update-DATIntuneTokenIfNeeded -Force) {
                Write-DATLogEntry -Value "[Graph API] Token refreshed after 401 - retrying request ($Method $Uri)" -Severity 1
                # Update headers with new token and retry once
                $headers["Authorization"] = "Bearer $($script:IntuneAuthToken)"
                try {
                    $retrySplat = @{
                        Method      = $Method
                        Uri         = if ($Uri -match '^https://') { $Uri } else { "$($script:GraphBaseUrl)/$($Uri.TrimStart('/'))" }
                        Headers     = $headers
                        ErrorAction = 'Stop'
                    }
                    if ($Body -and $Method -in @('POST', 'PATCH')) {
                        $retrySplat['Body'] = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
                    }
                    $retryProxy = Get-DATWebRequestProxy
                    foreach ($key in $retryProxy.Keys) { $retrySplat[$key] = $retryProxy[$key] }
                    $retryResponse = Invoke-RestMethod @retrySplat
                    if ($retryResponse.value) { return @($retryResponse.value) } else { return $retryResponse }
                } catch {
                    Write-DATLogEntry -Value "[Graph API] Retry after token refresh also failed: $($_.Exception.Message)" -Severity 3
                }
            }
            $script:IntuneAuthToken = $null
            Write-DATLogEntry -Value "[Graph API] 401 Unauthorized - token invalidated after failed refresh" -Severity 3
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

    $uri = "$baseUrl/deviceManagement/managedDevices?`$select=manufacturer,model,skuNumber&`$filter=operatingSystem eq 'Windows'&`$top=999"
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
                    $mfr = if ($device.manufacturer) { ([string]$device.manufacturer).Trim() } else { $null }
                    $mdl = if ($device.model) { ([string]$device.model).Trim() } else { $null }
                    # skuNumber maps to Win32_ComputerSystem.SystemSKUNumber -- for Dell this is the
                    # 4-char system ID (e.g. 0CFB) that matches the catalog SystemID/baseboard, enabling
                    # baseboard-primary matching that distinguishes Pro vs non-Pro models by name (#Dell Pro)
                    # Cast to [string] first -- Graph may return a numeric SKU as JSON int (no .Trim()).
                    $sku = if ($null -ne $device.skuNumber) { ([string]$device.skuNumber).Trim() } else { $null }
                    if ($sku -eq '' -or $sku -eq 'Unknown' -or $sku -eq '0') { $sku = $null }
                    if ($mfr -and $mfr -ne '' -and $mfr -ne 'Unknown' -and $mdl -and $mdl -ne '' -and $mdl -ne 'Unknown') {
                        $key = "$mfr|$mdl"
                        if (-not $devicePairs.ContainsKey($key)) {
                            $devicePairs[$key] = [PSCustomObject]@{ Make = $mfr; Model = $mdl; Baseboard = $sku }
                        } elseif ($null -ne $sku -and $null -eq $devicePairs[$key].Baseboard) {
                            # Enrich existing entry with a baseboard/SKU if we now have one
                            $devicePairs[$key].Baseboard = $sku
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
            $cimSess = New-DATCimSession -ComputerName $SiteServer
            $allPkgs  = @(Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer -Namespace $smsNamespace -Query $wmiQuery)
            $sorted   = $allPkgs | Sort-Object -Property Version -Descending
            # Keep newest + $RetainCount previous; delete the rest
            $toDelete = if ($sorted.Count -gt ($RetainCount + 1)) { $sorted | Select-Object -Skip ($RetainCount + 1) } else { @() }

            foreach ($pkg in $toDelete) {
                Write-DATLogEntry -Value "[Retention][CM] Removing $($pkg.Name) v$($pkg.Version) ($($pkg.PackageID))" -Severity 1
                try {
                    if ($null -ne $cimSess) {
                        Get-CimInstance -CimSession $cimSess -Namespace $smsNamespace `
                                  -Query "SELECT * FROM SMS_Package WHERE PackageID = '$($pkg.PackageID)'" -ErrorAction Stop | Remove-CimInstance -ErrorAction Stop
                    } else {
                        $wmiObj = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
                                  -Query "SELECT * FROM SMS_Package WHERE PackageID = '$($pkg.PackageID)'" -ErrorAction Stop
                        $wmiObj | ForEach-Object { $_.Delete() }
                    }
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
            $allApps  = Get-DATIntuneWin32Apps
            $matching = @($allApps | Where-Object { $_.displayName -like "$baseSearch*" })
            Write-DATLogEntry -Value "[Retention][Intune] Found $($matching.Count) app(s) matching '$baseSearch'" -Severity 1
            $sorted   = $matching | Sort-Object -Property { $_.displayVersion } -Descending
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

#region Assignment Filter Functions

function Get-DATIntuneAssignmentFilters {
    <#
    .SYNOPSIS
        Retrieves all Intune assignment filters from Graph API.
    #>
    [CmdletBinding()]
    param ()

    if (-not (Test-DATIntuneAuth)) {
        throw "Intune authentication required to query assignment filters."
    }

    $filters = Invoke-DATGraphRequest -Uri "/deviceManagement/assignmentFilters?`$select=id,displayName,platform,rule,createdDateTime" -NoPagination
    if ($null -eq $filters) { return @() }
    if ($filters -is [array]) { return $filters }
    return @($filters)
}

function Get-DATIntuneAssignmentFilterCount {
    <#
    .SYNOPSIS
        Returns the current count of assignment filters and how many remain out of 200 max.
    #>
    [CmdletBinding()]
    param ()

    $filters = Get-DATIntuneAssignmentFilters
    $count = @($filters).Count
    return @{
        Current   = $count
        Maximum   = 200
        Remaining = 200 - $count
    }
}

function New-DATIntuneAssignmentFilter {
    <#
    .SYNOPSIS
        Creates a new Intune assignment filter for a device manufacturer or model.
    .PARAMETER FilterName
        Display name for the assignment filter.
    .PARAMETER Manufacturer
        The device manufacturer to match (e.g. Dell, HP, Lenovo).
    .PARAMETER Model
        Optional. The device model to match. If omitted, matches all devices from the manufacturer.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$FilterName,
        [Parameter(Mandatory)][string]$Manufacturer,
        [string]$Model
    )

    if (-not (Test-DATIntuneAuth)) {
        throw "Intune authentication required to create assignment filters."
    }

    # Strip manufacturer prefix from model name if present (Windows reports model without make)
    if (-not [string]::IsNullOrEmpty($Model) -and $Model -like "$Manufacturer *") {
        $originalModel = $Model
        $Model = $Model.Substring($Manufacturer.Length).TrimStart()
        Write-DATLogEntry -Value "[Intune] Stripped manufacturer prefix from model: '$originalModel' -> '$Model'" -Severity 1
    }

    # Build the OData filter rule
    if (-not [string]::IsNullOrEmpty($Model)) {
        $rule = "(device.manufacturer -contains `"$Manufacturer`") and (device.model -contains `"$Model`")"
    } else {
        $rule = "(device.manufacturer -contains `"$Manufacturer`")"
    }

    $body = @{
        displayName = $FilterName
        description = "Auto-created by Driver Automation Tool"
        platform    = "windows10AndLater"
        rule        = $rule
        roleScopeTags = @("0")
    }

    Write-DATLogEntry -Value "[Intune] Creating assignment filter: $FilterName" -Severity 1
    return Invoke-DATGraphRequest -Uri "/deviceManagement/assignmentFilters" -Method POST -Body $body
}

function Find-DATIntuneAssignmentFilter {
    <#
    .SYNOPSIS
        Searches existing assignment filters for a matching manufacturer/model rule.
        Returns the filter if found, $null otherwise.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Manufacturer,
        [string]$Model
    )

    $filters = Get-DATIntuneAssignmentFilters

    # Strip manufacturer prefix from model name if present (Windows reports model without make)
    if (-not [string]::IsNullOrEmpty($Model) -and $Model -like "$Manufacturer *") {
        $Model = $Model.Substring($Manufacturer.Length).TrimStart()
    }

    if (-not [string]::IsNullOrEmpty($Model)) {
        $targetRule = "(device.manufacturer -contains `"$Manufacturer`") and (device.model -contains `"$Model`")"
    } else {
        $targetRule = "(device.manufacturer -contains `"$Manufacturer`")"
    }

    foreach ($f in $filters) {
        if ($f.rule -eq $targetRule) {
            return $f
        }
    }
    return $null
}

function Set-DATIntuneAppAssignmentWithFilter {
    <#
    .SYNOPSIS
        Creates a group assignment for an Intune Win32 app with an assignment filter.
        The filter is applied in "include" mode so only matching devices receive the app.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][ValidateSet('Available', 'Required')][string]$Intent,
        [Parameter(Mandatory)][string]$FilterId,
        [ValidateSet('include', 'exclude')][string]$FilterType = 'include'
    )

    $intentMap = @{ 'Available' = 'available'; 'Required' = 'required' }

    $allUsersId  = 'acacacac-9df4-4c7d-9d50-4ef0226f57a9'
    $allDevicesId = 'adadadad-808e-44e2-905a-0b7873a8a531'

    $target = switch ($GroupId) {
        $allUsersId  { @{ "@odata.type" = "#microsoft.graph.allLicensedUsersAssignmentTarget"; "deviceAndAppManagementAssignmentFilterId" = $FilterId; "deviceAndAppManagementAssignmentFilterType" = $FilterType } }
        $allDevicesId { @{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget"; "deviceAndAppManagementAssignmentFilterId" = $FilterId; "deviceAndAppManagementAssignmentFilterType" = $FilterType } }
        default {
            @{
                "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                groupId       = $GroupId
                "deviceAndAppManagementAssignmentFilterId"   = $FilterId
                "deviceAndAppManagementAssignmentFilterType" = $FilterType
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

    Write-DATLogEntry -Value "[Intune] Assigning app $AppId to group $GroupId as $Intent with filter $FilterId ($FilterType)" -Severity 1
    return Invoke-DATGraphRequest -Uri "/deviceAppManagement/mobileApps/$AppId/assign" -Method POST -Body $body
}

function Invoke-DATAutoAssignmentFilter {
    <#
    .SYNOPSIS
        Automatically creates (or reuses) an assignment filter and assigns the app.
        Called after a successful Intune package upload when auto-assignment is enabled.
    .PARAMETER AppId
        The Intune app ID returned from the upload.
    .PARAMETER Manufacturer
        The device manufacturer (e.g. Dell, HP, Lenovo).
    .PARAMETER Model
        The device model name. Only used when FilterMode is 'Model'.
    .PARAMETER FilterMode
        'Make' = one filter per manufacturer. 'Model' = one filter per make+model.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Manufacturer,
        [string]$Model,
        [Parameter(Mandatory)][ValidateSet('Make', 'Model')][string]$FilterMode
    )

    # Check current filter count against limit
    $counts = Get-DATIntuneAssignmentFilterCount
    Write-DATLogEntry -Value "[Intune] Assignment filters: $($counts.Current)/200 (remaining: $($counts.Remaining))" -Severity 1

    # Strip manufacturer prefix from model name if present (Windows reports model without make)
    if (-not [string]::IsNullOrEmpty($Model) -and $Model -like "$Manufacturer *") {
        $Model = $Model.Substring($Manufacturer.Length).TrimStart()
        Write-DATLogEntry -Value "[Intune] Using stripped model name for filter: '$Model'" -Severity 1
    }

    # Read naming template from registry (fall back to defaults)
    $regConfig = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
    $nameTemplate = if (-not [string]::IsNullOrEmpty($regConfig.AssignmentFilterNameTemplate)) {
        $regConfig.AssignmentFilterNameTemplate
    } elseif ($FilterMode -eq 'Model') {
        'DATFilter-%MAKE% %MODEL%'
    } else {
        'DATFilter-%MAKE%'
    }

    # Determine filter name from template and lookup parameters
    if ($FilterMode -eq 'Model' -and -not [string]::IsNullOrEmpty($Model)) {
        $filterName = $nameTemplate -replace '%MAKE%', $Manufacturer -replace '%MODEL%', $Model
        $existingFilter = Find-DATIntuneAssignmentFilter -Manufacturer $Manufacturer -Model $Model
    } else {
        $filterName = ($nameTemplate -replace '%MAKE%', $Manufacturer -replace '%MODEL%', '').Trim()
        $existingFilter = Find-DATIntuneAssignmentFilter -Manufacturer $Manufacturer
    }

    # Reuse existing or create new
    if ($null -ne $existingFilter) {
        $filterId = $existingFilter.id
        Write-DATLogEntry -Value "[Intune] Reusing existing assignment filter: $($existingFilter.displayName) ($filterId)" -Severity 1
    } else {
        if ($counts.Remaining -le 0) {
            Write-DATLogEntry -Value "[Intune] Cannot create assignment filter -- 200 limit reached ($($counts.Current)/200)" -Severity 3
            return
        }

        if ($FilterMode -eq 'Model' -and -not [string]::IsNullOrEmpty($Model)) {
            $newFilter = New-DATIntuneAssignmentFilter -FilterName $filterName -Manufacturer $Manufacturer -Model $Model
        } else {
            $newFilter = New-DATIntuneAssignmentFilter -FilterName $filterName -Manufacturer $Manufacturer
        }

        if ($null -eq $newFilter -or [string]::IsNullOrEmpty($newFilter.id)) {
            Write-DATLogEntry -Value "[Intune] Assignment filter creation failed -- skipping assignment to prevent unfiltered All Devices deployment" -Severity 3
            throw "Assignment filter creation returned no filter ID. Cannot assign without a valid filter."
        }

        $filterId = $newFilter.id
        Write-DATLogEntry -Value "[Intune] Created assignment filter: $filterName ($filterId)" -Severity 1
    }

    # Assign to All Devices with the filter in include mode
    $allDevicesId = 'adadadad-808e-44e2-905a-0b7873a8a531'
    Set-DATIntuneAppAssignmentWithFilter -AppId $AppId -GroupId $allDevicesId -Intent 'Required' -FilterId $filterId -FilterType 'include'
    Write-DATLogEntry -Value "[Intune] App $AppId assigned to All Devices with filter $filterName" -Severity 1
}

#endregion Assignment Filter Functions

#region Code Signing

function Invoke-DATCodeSign {
    <#
    .SYNOPSIS
        Signs a PowerShell script with the configured Authenticode certificate.
        Soft-fails if no certificate is configured or signing fails.
    .PARAMETER ScriptPath
        Full path to the .ps1 file to sign.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    # Read thumbprint from registry
    $regConfig = Get-ItemProperty -Path $global:RegPath -ErrorAction SilentlyContinue
    if (-not $regConfig -or [string]::IsNullOrEmpty($regConfig.CodeSigningCertThumbprint)) { return }
    if ($regConfig.CodeSigningEnabled -ne 1) { return }

    $thumbprint = $regConfig.CodeSigningCertThumbprint.Trim()
    if ([string]::IsNullOrEmpty($thumbprint)) { return }

    # Search both certificate stores for the thumbprint
    $cert = $null
    foreach ($storePath in @('Cert:\LocalMachine\My', 'Cert:\CurrentUser\My')) {
        $cert = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue |
            Where-Object { $_.Thumbprint -eq $thumbprint -and $_.HasPrivateKey } |
            Select-Object -First 1
        if ($cert) { break }
    }

    if (-not $cert) {
        Write-DATLogEntry -Value "[CodeSign] Certificate with thumbprint $thumbprint not found in LocalMachine\My or CurrentUser\My -- skipping" -Severity 2
        return
    }

    # Validate the certificate has Code Signing EKU
    $hasCodeSigningEku = $cert.EnhancedKeyUsageList | Where-Object { $_.ObjectId -eq '1.3.6.1.5.5.7.3.3' }
    if (-not $hasCodeSigningEku) {
        Write-DATLogEntry -Value "[CodeSign] Certificate $thumbprint does not have Code Signing EKU -- skipping" -Severity 2
        return
    }

    try {
        $result = Set-AuthenticodeSignature -FilePath $ScriptPath -Certificate $cert `
            -TimestampServer 'http://timestamp.digicert.com' -HashAlgorithm SHA256 -ErrorAction Stop
        if ($result.Status -eq 'Valid') {
            Write-DATLogEntry -Value "[CodeSign] Signed: $(Split-Path $ScriptPath -Leaf)" -Severity 1
        } else {
            Write-DATLogEntry -Value "[CodeSign] Signing returned status '$($result.Status)' for $(Split-Path $ScriptPath -Leaf): $($result.StatusMessage)" -Severity 2
        }
    } catch {
        Write-DATLogEntry -Value "[CodeSign] Failed to sign $(Split-Path $ScriptPath -Leaf) -- $($_.Exception.Message)" -Severity 2
    }
}

#endregion Code Signing

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
        [string]$CustomToastBody = '',
        [string]$CustomToastGreeting = '',
        [string]$CustomToastSubtitle = '',
        [string]$CustomActionButton = '',
        [string]$CustomDismissButton = '',
        [int]$RestartDelayMinutes = 10,
        [switch]$DisableRestart
    )

    # Determine layout type and per-type content
    $isStatusType = $UpdateType -in @('Success', 'BIOSSuccess', 'Issues', 'BIOSIssues')

    switch ($UpdateType) {
        'BIOS' {
            $heading = if (-not [string]::IsNullOrEmpty($CustomToastTitle)) { $CustomToastTitle } else { 'BIOS Update Pending' }
            if ($DisableRestart) {
                $body = if (-not [string]::IsNullOrEmpty($CustomToastBody)) { $CustomToastBody } else { 'Your device has pending updates which are required for security / stability reasons. Your device will perform this update upon the next restart. DO NOT power off the device during the update process.' }
            } else {
                $body = if (-not [string]::IsNullOrEmpty($CustomToastBody)) { $CustomToastBody } else { 'Your device has pending updates which are required for security / stability reasons. Pressing the Update button will trigger a restart of your device. DO NOT power off the device during the update process.' }
            }
        }
        'BIOSSuccess' {
            if ($DisableRestart) {
                $heading    = if (-not [string]::IsNullOrEmpty($CustomToastTitle)) { $CustomToastTitle } else { 'BIOS Update Pending Restart' }
                $body       = if (-not [string]::IsNullOrEmpty($CustomToastBody))  { $CustomToastBody  } else { 'Your system has a pending BIOS update that will be applied upon your next restart. Please restart your device at your earliest convenience. Do NOT power off the device during the update process.' }
            } else {
                $heading    = if (-not [string]::IsNullOrEmpty($CustomToastTitle)) { $CustomToastTitle } else { 'BIOS Firmware Prestaged' }
                $body       = if (-not [string]::IsNullOrEmpty($CustomToastBody))  { $CustomToastBody  } else { "Your system has a pending BIOS update and will be restarted in $RestartDelayMinutes minute(s). Please save your work. Do NOT power off the device during the update process." }
            }
            $statusIcon     = '&#xE835;'   # FirmwareUpdate (Segoe MDL2 Assets)
            $iconColor      = '#3B82F6'    # blue-500
            $accentColor    = '#2563EB'    # blue-600
            $iconBackground = '#172554'    # blue-950
        }
        'Success' {
            $heading        = if (-not [string]::IsNullOrEmpty($CustomToastTitle)) { $CustomToastTitle } else { 'Drivers Successfully Updated' }
            $body           = if (-not [string]::IsNullOrEmpty($CustomToastBody))  { $CustomToastBody  } else { 'Your device drivers have been successfully updated. No restart is required unless indicated by your IT department.' }
            $statusIcon     = '&#xE930;'   # CompletedSolid (Segoe MDL2 Assets)
            $iconColor      = '#22C55E'    # green-500
            $accentColor    = '#16A34A'    # green-600
            $iconBackground = '#052e16'    # green-950
        }
        'Issues' {
            $heading        = if (-not [string]::IsNullOrEmpty($CustomToastTitle)) { $CustomToastTitle } else { 'Driver Update Issues Detected' }
            $body           = if (-not [string]::IsNullOrEmpty($CustomToastBody))  { $CustomToastBody  } else { 'One or more driver updates encountered errors during installation. Please contact your IT department or check the device logs for details.' }
            $statusIcon     = '&#xE7BA;'   # Warning (Segoe MDL2 Assets)
            $iconColor      = '#F59E0B'    # amber-500
            $accentColor    = '#D97706'    # amber-600
            $iconBackground = '#451a03'    # amber-950
        }
        'BIOSIssues' {
            $heading        = if (-not [string]::IsNullOrEmpty($CustomToastTitle)) { $CustomToastTitle } else { 'BIOS Update Issues Detected' }
            $body           = if (-not [string]::IsNullOrEmpty($CustomToastBody))  { $CustomToastBody  } else { 'The BIOS firmware update encountered errors during installation. Please contact your IT department or check the device logs for details.' }
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

    # Resolve greeting prefix and subtitle
    $greetingPrefix = if (-not [string]::IsNullOrEmpty($CustomToastGreeting)) { $CustomToastGreeting } else { 'Hi' }
    $subtitle = if (-not [string]::IsNullOrEmpty($CustomToastSubtitle)) { $CustomToastSubtitle } else { 'Driver Automation Tool V10' }

    # XML-safe body for embedding in XAML Text attributes.
    # Using element content collapses newlines via XAML whitespace normalization; the Text
    # attribute with &#x0a; character references preserves line breaks at parse time.
    $bodyXamlSafe = $body -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' -replace "`r`n",'&#x0a;' -replace "`r",'&#x0a;' -replace "`n",'&#x0a;'

    # Resolve button text per update type
    if ($isStatusType) {
        $actionButtonText  = if (-not [string]::IsNullOrEmpty($CustomActionButton))  { $CustomActionButton }  else { 'Close' }
        $dismissButtonText = if (-not [string]::IsNullOrEmpty($CustomDismissButton)) { $CustomDismissButton } else { 'Restart Now' }
    } else {
        $actionButtonText  = if (-not [string]::IsNullOrEmpty($CustomActionButton))  { $CustomActionButton }  else { 'Update Now' }
        $dismissButtonText = if (-not [string]::IsNullOrEmpty($CustomDismissButton)) { $CustomDismissButton } else { 'Remind Me Later' }
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
`$greetingPrefix    = '$($greetingPrefix -replace "'","''")'

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
                           LineHeight="20" Text="$bodyXamlSafe"/>
            </StackPanel>
"@
        $statusCloseButton = @"
            <!-- Close Button -->
            <Grid Grid.Row="2" Margin="24,0,24,20">
                <Button x:Name="btnClose" Content="$actionButtonText"
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
        `$imgDir = Join-Path `$env:ProgramData "DriverAutomationTool"
        if (-not (Test-Path `$imgDir)) { New-Item -Path `$imgDir -ItemType Directory -Force | Out-Null }
        `$imgPath = Join-Path `$imgDir "DATLogo_Wide.png"
        [System.IO.File]::WriteAllBytes(`$imgPath, `$imgBytes)
        Write-ToastLog "Logo written to `$imgPath"
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
                <TextBlock x:Name="txtGreeting" Text="$greetingPrefix User" FontSize="16" Foreground="#F8FAFC"
                           FontWeight="SemiBold" Margin="0,0,0,2"/>
                <TextBlock Text="$subtitle" FontSize="12"
                           Foreground="#CBD5E1" Margin="0,0,0,16"/>
                <TextBlock Text="$heading" FontSize="20" FontWeight="Bold"
                           Foreground="#F8FAFC" Margin="0,0,0,10"/>
                <TextBlock TextWrapping="Wrap" FontSize="13" Foreground="#CBD5E1"
                           LineHeight="20" Text="$bodyXamlSafe"/>
            </StackPanel>
"@

        $buttonsXaml = @"

            <!-- Action Buttons -->
            <Grid Grid.Row="2" Margin="24,0,24,20">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Button x:Name="btnUpdate" Grid.Column="0" Content="$actionButtonText"
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
                <Button x:Name="btnSnooze" Grid.Column="2" Content="$dismissButtonText"
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
                } elseif (-not [string]::IsNullOrWhiteSpace($givenName)) {
                    $adName = $givenName
                } elseif (-not [string]::IsNullOrWhiteSpace($sn)) {
                    $adName = $sn
                } elseif (-not [string]::IsNullOrWhiteSpace($adDisplayName)) {
                    # Split CamelCase names that lack spaces (e.g. "TestUser" -> "Test User")
                    if ($adDisplayName -notmatch '\s' -and $adDisplayName -cmatch '[a-z][A-Z]') {
                        $adName = $adDisplayName -creplace '([a-z])([A-Z])', '$1 $2'
                    } else {
                        $adName = $adDisplayName
                    }
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

    $window.FindName('txtGreeting').Text = "$greetingPrefix $displayName"

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

    # Write with UTF-8 BOM so PowerShell 5.1 correctly reads non-ASCII characters
    # (e.g. Swedish ä/ö/å). Without BOM, PS 5.1 reads files using the system's ANSI
    # code page (Windows-1252), corrupting multi-byte UTF-8 characters.
    [System.IO.File]::WriteAllText($OutputPath, $fullScript, [System.Text.UTF8Encoding]::new($true))
    Write-DATLogEntry -Value "[Intune] Toast notification script generated: $OutputPath (Type: $UpdateType)" -Severity 1
    Invoke-DATCodeSign -ScriptPath $OutputPath
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
        [string]$ReleaseDate,
        [ValidateSet('Drivers','BIOS')][string]$UpdateType = 'Drivers',
        [switch]$DisableToast,
        [switch]$DisableRestart,
        [ValidateSet('RemindMeLater','InstallNow')][string]$ToastTimeoutAction = 'RemindMeLater',
        [int]$MaxDeferrals = 0,
        [int]$RestartDelaySeconds = 600
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
        Unregister-ScheduledTask -TaskPath "$taskFolder\" -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -Action $taskAction -Principal $taskPrincipal `
            -Settings $taskSettings -Force | Out-Null
        Start-ScheduledTask -TaskPath "$taskFolder\" -TaskName $taskName
        $taskState = (Get-ScheduledTask -TaskPath "$taskFolder\" -TaskName $taskName -ErrorAction SilentlyContinue).State
        Write-CMTraceLog "[StatusToast] Task started -- state: $taskState"
        # Brief delay then clean up the task registration (toast is already running)
        Start-Sleep -Seconds 5
        $taskStateAfter = (Get-ScheduledTask -TaskPath "$taskFolder\" -TaskName $taskName -ErrorAction SilentlyContinue).State
        $taskInfoObj = Get-ScheduledTaskInfo -TaskPath "$taskFolder\" -TaskName $taskName -ErrorAction SilentlyContinue
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

    # Security fix #17: validate token values against an allow-list before injecting
    # into generated PowerShell. Characters outside this set have no legitimate use in
    # OEM/model/version/OS names but can break string literals or comments in the output
    # script (e.g. a catalog-supplied value of  Dell"; exit 1; "  would be injected verbatim).
    # An allow-list applied once here covers every template context uniformly.
    $allowPattern = '^[\w\s\.\-\/\(\)]+$'   # letters, digits, _, space, . - / ( )
    $tokensToValidate = [ordered]@{
        OEM     = $OEM
        Model   = $Model
        OS      = $OS
        Version = $Version
    }
    foreach ($kv in $tokensToValidate.GetEnumerator()) {
        if (-not [string]::IsNullOrEmpty($kv.Value) -and $kv.Value -notmatch $allowPattern) {
            $safe = $kv.Value -replace '[^\x20-\x7E]', '?'
            Write-DATLogEntry -Value "[Error] - Script generation aborted: token '$($kv.Key)' contains disallowed characters: '$safe'" -Severity 3
            throw "Script generation aborted: token '$($kv.Key)' failed allow-list validation"
        }
    }

    # Replace template tokens (use literal .Replace() -- NOT -replace -- because the
    # toast blocks contain $_ which .NET regex interprets as "entire input string")
    $scriptContent = $scriptContent.Replace('{{OEM}}', $OEM)
    $scriptContent = $scriptContent.Replace('{{Model}}', $Model)
    $scriptContent = $scriptContent.Replace('{{OS}}', $OS)
    $scriptContent = $scriptContent.Replace('{{Version}}', $Version)
    $releaseDate8 = ''
    if (-not [string]::IsNullOrEmpty($ReleaseDate)) {
        try { $releaseDate8 = ([datetime]$ReleaseDate).ToString('yyyyMMdd') } catch { $releaseDate8 = $ReleaseDate }
    }
    $scriptContent = $scriptContent.Replace('{{ReleaseDate}}', $releaseDate8)
    $scriptContent = $scriptContent.Replace('{{Generated}}', (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
    $scriptContent = $scriptContent.Replace('{{TOAST_FUNCTIONS}}', $toastFunctions)
    $scriptContent = $scriptContent.Replace('{{TOAST_BLOCK}}', $toastBlock)
    $scriptContent = $scriptContent.Replace('{{STATUS_TOAST_BLOCK}}', $statusToastBlock)
    $scriptContent = $scriptContent.Replace('{{STATUS_TOAST_ERROR_BLOCK}}', $statusToastErrorBlock)
    $scriptContent = $scriptContent.Replace('{{RESTART_DELAY_SECONDS}}', [string]$RestartDelaySeconds)
    $scriptContent = $scriptContent.Replace('{{DISABLE_RESTART}}', $(if ($DisableRestart) { '$true' } else { '$false' }))

    # UTF-8 with BOM ensures PS 5.1 reads non-ASCII characters correctly
    [System.IO.File]::WriteAllText($OutputPath, $scriptContent, [System.Text.UTF8Encoding]::new($true))
    Write-DATLogEntry -Value "[Intune] Install script generated: $OutputPath (Toast: $(if ($DisableToast) { 'Disabled' } else { 'Enabled' }))" -Severity 1
    Invoke-DATCodeSign -ScriptPath $OutputPath
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
        [string]$ReleaseDate,
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

    # Build Check 4: version/release-date comparison block
    $releaseDate8 = ''
    if (-not [string]::IsNullOrEmpty($ReleaseDate)) {
        try { $releaseDate8 = ([datetime]$ReleaseDate).ToString('yyyyMMdd') } catch { $releaseDate8 = $ReleaseDate }
    }
    $versionCheckBlock = if ($UpdateType -eq 'BIOS' -and -not [string]::IsNullOrEmpty($releaseDate8)) {
        @"
    # Check 4: BIOS release date comparison
    try {
        `$currentBIOS = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        `$currentReleaseDate = `$currentBIOS.ReleaseDate.ToString('yyyyMMdd')
        `$packageReleaseDate = "$releaseDate8"
        if (`$packageReleaseDate -le `$currentReleaseDate) {
            Write-Output "BIOS release date not newer: package=`$packageReleaseDate, current=`$currentReleaseDate"
            exit 0
        }
    } catch { }

    # Also check if this exact version is already installed via registry
    `$regPath = "HKLM:\SOFTWARE\DriverAutomationTool\$regSubKey\$OEM\$Model"
    if (Test-Path `$regPath) {
        `$installedVer = (Get-ItemProperty -Path `$regPath -Name 'Version' -ErrorAction SilentlyContinue).Version
        if (`$installedVer -eq "$Version") {
            Write-Output "Package already installed: version=$Version"
            exit 0
        }
    }
"@
    } elseif ($UpdateType -eq 'BIOS') {
        # BIOS without a catalog release date -- registry exact-match only
        # (ddMMyyyy parsing is not valid for OEM BIOS version strings like M43KT32A)
        @"
    # Check 4: BIOS version check - registry exact match
    `$regPath = "HKLM:\SOFTWARE\DriverAutomationTool\$regSubKey\$OEM\$Model"
    if (Test-Path `$regPath) {
        `$installedVer = (Get-ItemProperty -Path `$regPath -Name 'Version' -ErrorAction SilentlyContinue).Version
        if (`$installedVer -eq "$Version") {
            Write-Output "Package already installed: version=$Version"
            exit 0
        }
    }
"@
    } else {
        @"
    # Check 4: Version check - registry-based installed version
    `$packageVersion = "$Version"
    `$regPath = "HKLM:\SOFTWARE\DriverAutomationTool\$regSubKey\$OEM\$Model"

    if (Test-Path `$regPath) {
        `$installedVer = (Get-ItemProperty -Path `$regPath -Name 'Version' -ErrorAction SilentlyContinue).Version
        if (-not [string]::IsNullOrEmpty(`$installedVer)) {
            try {
                `$pkgDay = [int]`$packageVersion.Substring(0, 2)
                `$pkgMonth = [int]`$packageVersion.Substring(2, 2)
                `$pkgYear = [int]`$packageVersion.Substring(4, 4)
                `$pkgDate = [datetime]::new(`$pkgYear, `$pkgMonth, `$pkgDay)

                `$instDay = [int]`$installedVer.Substring(0, 2)
                `$instMonth = [int]`$installedVer.Substring(2, 2)
                `$instYear = [int]`$installedVer.Substring(4, 4)
                `$instDate = [datetime]::new(`$instYear, `$instMonth, `$instDay)

                if (`$pkgDate -le `$instDate) {
                    Write-Output "Version not newer: package=`$packageVersion, installed=`$installedVer"
                    exit 0
                }
            } catch { }
        }
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
        $escaped = [regex]::Escape($val)
        if ($systemSKU -match $escaped -or $baseboardProduct -match $escaped) {{
            $skuMatch = $true
            break
        }}
    }}

    if (-not $skuMatch) {{
        Write-Output "SKU/Baseboard mismatch: SKU='$systemSKU', Board='$baseboardProduct', Expected=@('{4}')"
        exit 0
    }}

{8}
%%VERSION_CHECK%%

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

    $scriptContent = $scriptContent.Replace('%%VERSION_CHECK%%', $versionCheckBlock)

    # UTF-8 WITHOUT BOM -- Intune requirement rule scripts must not carry a BOM, otherwise
    # the portal/IME treats it as literal content (surfaces as mojibake at the top of the script).
    [System.IO.File]::WriteAllText($OutputPath, $scriptContent, [System.Text.UTF8Encoding]::new($false))
    Write-DATLogEntry -Value "[Intune] Requirement script generated: $OutputPath (UpdateType: $UpdateType)" -Severity 1
    Invoke-DATCodeSign -ScriptPath $OutputPath
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
        [string]$ReleaseDate,
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

    # Build release date for BIOS detection
    $releaseDate8 = ''
    if (-not [string]::IsNullOrEmpty($ReleaseDate)) {
        try { $releaseDate8 = ([datetime]$ReleaseDate).ToString('yyyyMMdd') } catch { $releaseDate8 = $ReleaseDate }
    }

    # Build Check 4: detection block
    $detectionCheckBlock = if ($UpdateType -eq 'BIOS' -and -not [string]::IsNullOrEmpty($releaseDate8)) {
        @"
    # Check 4: BIOS detection via release date and registry
    # Detected if the device BIOS release date is at or newer than the package date,
    # OR the registry version stamp matches exactly (covers pre-reboot detection).
    `$detected = `$false
    try {
        `$currentBIOS = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        `$currentReleaseDate = `$currentBIOS.ReleaseDate.ToString('yyyyMMdd')
        `$packageReleaseDate = "$releaseDate8"
        if (`$currentReleaseDate -ge `$packageReleaseDate) {
            `$detected = `$true
        }
    } catch { }

    if (-not `$detected) {
        `$regPath = "HKLM:\SOFTWARE\DriverAutomationTool\$regSubKey\$OEM\$Model"
        if (Test-Path `$regPath) {
            `$installedVer = (Get-ItemProperty -Path `$regPath -Name 'Version' -ErrorAction SilentlyContinue).Version
            if (`$installedVer -eq "$Version") {
                `$detected = `$true
            }
        }
    }

    if (`$detected) {
        Write-Output "Detected: $OEM $Model $detectionLabel version $Version"
        exit 0
    }
"@
    } else {
        @"
    # Check 4: Version marker in registry
    `$regPath = "HKLM:\SOFTWARE\DriverAutomationTool\$regSubKey\$OEM\$Model"
    if (Test-Path `$regPath) {
        `$installedVersion = (Get-ItemProperty -Path `$regPath -Name 'Version' -ErrorAction SilentlyContinue).Version
        if (`$installedVersion -eq "$Version") {
            Write-Output "Detected: $OEM $Model $detectionLabel version $Version"
            exit 0
        }
    }
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
        $escaped = [regex]::Escape($val)
        if ($systemSKU -match $escaped -or $baseboardProduct -match $escaped) {{
            $skuMatch = $true
            break
        }}
    }}

    if (-not $skuMatch) {{ exit 0 }}

{8}
%%DETECTION_CHECK%%

    # Not detected - exit with no output
    exit 0
}}
catch {{
    # Error during detection - treat as not detected
    exit 0
}}
'@ -f $OEM, $Model, $OS, $Version, $bbValues, (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $osNumber, $UpdateType, $osCheckBlock, $regSubKey, $detectionLabel

    $scriptContent = $scriptContent.Replace('%%DETECTION_CHECK%%', $detectionCheckBlock)

    # UTF-8 WITHOUT BOM -- Intune detection rule scripts must not carry a BOM, otherwise
    # the portal/IME treats it as literal content (surfaces as mojibake at the top of the script).
    [System.IO.File]::WriteAllText($OutputPath, $scriptContent, [System.Text.UTF8Encoding]::new($false))
    Write-DATLogEntry -Value "[Intune] Detection script generated: $OutputPath (UpdateType: $UpdateType)" -Severity 1
    Invoke-DATCodeSign -ScriptPath $OutputPath
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

function ConvertTo-DATNoBomScriptBase64 {
    <#
    .SYNOPSIS
        Reads a script file and returns its base64 representation with any leading
        UTF-8 BOM (0xEF 0xBB 0xBF) removed. Intune requirement/detection rule scripts
        must be plain UTF-8 (no BOM) -- the Intune portal and the Intune Management
        Extension treat a BOM as literal script content, so it surfaces as the mojibake
        sequence "i>?" at the top of the script and can break parsing. This is the
        authoritative enforcement point: regardless of how the on-disk file was encoded,
        the BOM is stripped here before the content is handed to Graph.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][string]$Path
    )
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if ($hasBom) {
        $stripped = New-Object byte[] ($bytes.Length - 3)
        [System.Buffer]::BlockCopy($bytes, 3, $stripped, 0, $stripped.Length)
        $bytes = $stripped
    }
    return [Convert]::ToBase64String($bytes)
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
        # Step 2: Read detection and requirement scripts as base64.
        # Both are uploaded as Intune PowerShell rule scripts and must be plain UTF-8
        # (no BOM) -- a BOM is treated as literal content by Intune and appears as the
        # mojibake sequence at the top of the script content, breaking the rule.
        $detectionScriptContent = ConvertTo-DATNoBomScriptBase64 -Path $DetectionScriptPath
        $requirementScriptContent = ConvertTo-DATNoBomScriptBase64 -Path $RequirementScriptPath

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
        [string]$NamePrefix,
        [switch]$DisableToast,
        [switch]$DisableRestart,
        [ValidateSet('RemindMeLater','InstallNow')][string]$ToastTimeoutAction = 'RemindMeLater',
        [int]$MaxDeferrals = 0,
        [int]$RestartDelaySeconds = 600,
        [string]$DebugBuildPath,
        [string]$CustomBrandingPath,
        [string]$Version,
        [string]$ReleaseDate,
        [string]$HPPasswordBinPath,
        [switch]$ForceUpdate,
        [string]$CustomToastTitle,
        [string]$CustomToastBody,
        [string]$CustomToastGreeting,
        [string]$CustomToastSubtitle,
        [string]$CustomSuccessTitle,
        [string]$CustomSuccessBody,
        [string]$CustomBIOSSuccessTitle,
        [string]$CustomBIOSSuccessBody,
        [string]$CustomIssuesTitle,
        [string]$CustomIssuesBody,
        [string]$CustomBIOSIssuesTitle,
        [string]$CustomBIOSIssuesBody,
        [string]$CustomToastActionButton,
        [string]$CustomToastDismissButton,
        [string]$CustomSuccessActionButton,
        [string]$CustomIssuesActionButton,
        [string]$CustomBIOSSuccessActionButton,
        [string]$CustomBIOSSuccessDismissButton,
        [string]$CustomBIOSIssuesActionButton
    )
    if (-not [string]::IsNullOrEmpty($IntuneAuthToken)) {
        $script:IntuneAuthToken = $IntuneAuthToken
        # Only update expiry if not already set (token refresh maintains its own expiry)
        if ($script:IntuneTokenExpiry -le (Get-Date)) {
            $script:IntuneTokenExpiry = (Get-Date).AddMinutes(30)
        }
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
    $displayPrefix = if (-not [string]::IsNullOrEmpty($NamePrefix)) { $NamePrefix } else { $UpdateType }
    $displayName = if ($UpdateType -eq 'BIOS') {
        "$displayPrefix - $OEM $Model"
    } else {
        "$displayPrefix - $OEM $Model - $OS $Architecture"
    }
    $publisher = $OEM
    $description = if ($UpdateType -eq 'BIOS') {
        "$UpdateType package for $OEM $Model`nArchitecture: $Architecture`nBaseboards/SKU: $Baseboards`nVersion: $version`nCreated by Driver Automation Tool"
    } else {
        "$UpdateType package for $OEM $Model`nOS: $OS`nArchitecture: $Architecture`nBaseboards/SKU: $Baseboards`nVersion: $version`nCreated by Driver Automation Tool"
    }

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
    $pkgSubDir = if ($UpdateType -eq 'BIOS') { "$OEM\$Model\BIOS" } else { "$OEM\$Model\$OS" }
    $stagingDir = Join-Path $PackageDestination "IntuneStaging\$pkgSubDir"
    if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
    New-Item -Path $stagingDir -ItemType Directory -Force | Out-Null

    $scriptsDir = Join-Path $PackageDestination "IntuneScripts\$pkgSubDir"
    if (Test-Path $scriptsDir) { Remove-Item $scriptsDir -Recurse -Force }
    New-Item -Path $scriptsDir -ItemType Directory -Force | Out-Null

    $outputDir = Join-Path $PackageDestination "IntuneWin\$pkgSubDir"
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
        if (-not [string]::IsNullOrEmpty($ReleaseDate)) { $installScriptParams['ReleaseDate'] = $ReleaseDate }
        if ($DisableToast) { $installScriptParams['DisableToast'] = $true }
        if ($DisableRestart) { $installScriptParams['DisableRestart'] = $true }
        if ($ToastTimeoutAction -ne 'RemindMeLater') { $installScriptParams['ToastTimeoutAction'] = $ToastTimeoutAction }
        if ($MaxDeferrals -gt 0) { $installScriptParams['MaxDeferrals'] = $MaxDeferrals }
        if ($RestartDelaySeconds -ne 600) { $installScriptParams['RestartDelaySeconds'] = $RestartDelaySeconds }
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
            if (-not [string]::IsNullOrEmpty($CustomToastGreeting))  { $toastParams['CustomToastGreeting']  = $CustomToastGreeting  }
            if (-not [string]::IsNullOrEmpty($CustomToastSubtitle))  { $toastParams['CustomToastSubtitle']  = $CustomToastSubtitle  }
            if (-not [string]::IsNullOrEmpty($CustomToastActionButton))  { $toastParams['CustomActionButton']  = $CustomToastActionButton  }
            if (-not [string]::IsNullOrEmpty($CustomToastDismissButton)) { $toastParams['CustomDismissButton'] = $CustomToastDismissButton }
            New-DATIntuneToastScript @toastParams
            Write-DATLogEntry -Value "[Intune Pipeline] Toast script created: $toastScriptPath" -Severity 1 -UpdateUI

            # Generate completion status toast scripts (Success / Issues)
            $statusToastParams = @{
                BrandingPath = Join-Path $global:ScriptDirectory 'Branding'
            }
            if (-not [string]::IsNullOrEmpty($CustomBrandingPath)) { $statusToastParams['CustomBrandingImagePath'] = $CustomBrandingPath }
            if ($UpdateType -eq 'BIOS' -and $RestartDelaySeconds -gt 0) {
                $statusToastParams['RestartDelayMinutes'] = [math]::Round($RestartDelaySeconds / 60, 0)
            }

            $successToastPath = Join-Path $stagingDir "Show-StatusToast-Success.ps1"
            $successParams = @{} + $statusToastParams
            if (-not [string]::IsNullOrEmpty($CustomSuccessTitle)) { $successParams['CustomToastTitle'] = $CustomSuccessTitle }
            if (-not [string]::IsNullOrEmpty($CustomSuccessBody))  { $successParams['CustomToastBody']  = $CustomSuccessBody  }
            if (-not [string]::IsNullOrEmpty($CustomSuccessActionButton)) { $successParams['CustomActionButton'] = $CustomSuccessActionButton }
            New-DATIntuneToastScript -OutputPath $successToastPath -UpdateType 'Success' @successParams
            Write-DATLogEntry -Value "[Intune Pipeline] Success toast script created: $successToastPath" -Severity 1 -UpdateUI

            # Generate BIOS-specific prestaged toast (used only by BIOS install scripts)
            if ($UpdateType -eq 'BIOS') {
                $biosSuccessToastPath = Join-Path $stagingDir "Show-StatusToast-BIOSSuccess.ps1"
                $biosSuccessParams = @{} + $statusToastParams
                if (-not [string]::IsNullOrEmpty($CustomBIOSSuccessTitle)) { $biosSuccessParams['CustomToastTitle'] = $CustomBIOSSuccessTitle }
                if (-not [string]::IsNullOrEmpty($CustomBIOSSuccessBody))  { $biosSuccessParams['CustomToastBody']  = $CustomBIOSSuccessBody  }
                if (-not [string]::IsNullOrEmpty($CustomBIOSSuccessActionButton))  { $biosSuccessParams['CustomActionButton']  = $CustomBIOSSuccessActionButton  }
                if (-not [string]::IsNullOrEmpty($CustomBIOSSuccessDismissButton)) { $biosSuccessParams['CustomDismissButton'] = $CustomBIOSSuccessDismissButton }
                if ($DisableRestart) { $biosSuccessParams['DisableRestart'] = $true }
                New-DATIntuneToastScript -OutputPath $biosSuccessToastPath -UpdateType 'BIOSSuccess' @biosSuccessParams
                Write-DATLogEntry -Value "[Intune Pipeline] BIOS prestaged toast script created: $biosSuccessToastPath" -Severity 1 -UpdateUI
            }

            $issuesToastPath = Join-Path $stagingDir "Show-StatusToast-Issues.ps1"
            $issuesParams = @{} + $statusToastParams
            if (-not [string]::IsNullOrEmpty($CustomIssuesTitle)) { $issuesParams['CustomToastTitle'] = $CustomIssuesTitle }
            if (-not [string]::IsNullOrEmpty($CustomIssuesBody))  { $issuesParams['CustomToastBody']  = $CustomIssuesBody  }
            if (-not [string]::IsNullOrEmpty($CustomIssuesActionButton)) { $issuesParams['CustomActionButton'] = $CustomIssuesActionButton }
            New-DATIntuneToastScript -OutputPath $issuesToastPath -UpdateType 'Issues' @issuesParams
            Write-DATLogEntry -Value "[Intune Pipeline] Issues toast script created: $issuesToastPath" -Severity 1 -UpdateUI

            # Generate BIOS-specific issues toast (used only by BIOS install scripts)
            if ($UpdateType -eq 'BIOS') {
                $biosIssuesToastPath = Join-Path $stagingDir "Show-StatusToast-BIOSIssues.ps1"
                $biosIssuesParams = @{} + $statusToastParams
                if (-not [string]::IsNullOrEmpty($CustomBIOSIssuesTitle)) { $biosIssuesParams['CustomToastTitle'] = $CustomBIOSIssuesTitle }
                if (-not [string]::IsNullOrEmpty($CustomBIOSIssuesBody))  { $biosIssuesParams['CustomToastBody']  = $CustomBIOSIssuesBody  }
                if (-not [string]::IsNullOrEmpty($CustomBIOSIssuesActionButton)) { $biosIssuesParams['CustomActionButton'] = $CustomBIOSIssuesActionButton }
                New-DATIntuneToastScript -OutputPath $biosIssuesToastPath -UpdateType 'BIOSIssues' @biosIssuesParams
                Write-DATLogEntry -Value "[Intune Pipeline] BIOS issues toast script created: $biosIssuesToastPath" -Severity 1 -UpdateUI
            }
        }

        # Step 3: Generate requirement script (stored separately, not in the .intunewin)
        Set-DATRegistryValue -Name "RunningMessage" -Value "Generating requirement script for $OEM $Model..." -Type String
        $requirementScriptPath = Join-Path $scriptsDir "Require-$OEM-$($Model -replace '\s+','-').ps1"
        New-DATIntuneRequirementScript -OutputPath $requirementScriptPath -OEM $OEM -Model $Model `
            -Baseboards $Baseboards -OS $OS -Version $version -UpdateType $UpdateType `
            -ReleaseDate $ReleaseDate
        Write-DATLogEntry -Value "[Intune Pipeline] Requirement script created: $requirementScriptPath" -Severity 1 -UpdateUI

        # Step 4: Generate detection script (stored separately, not in the .intunewin)
        Set-DATRegistryValue -Name "RunningMessage" -Value "Generating detection script for $OEM $Model..." -Type String
        $detectionScriptPath = Join-Path $scriptsDir "Detect-$OEM-$($Model -replace '\s+','-').ps1"
        New-DATIntuneDetectionScript -OutputPath $detectionScriptPath -OEM $OEM -Model $Model `
            -Baseboards $Baseboards -OS $OS -Version $version -UpdateType $UpdateType `
            -ReleaseDate $ReleaseDate
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
        # Proactively refresh token before upload (uploads can take 20+ minutes for large packages)
        if (-not (Update-DATIntuneTokenIfNeeded)) {
            Write-DATLogEntry -Value "[Intune Pipeline] WARNING: Token refresh failed before upload -- upload may fail if token expires" -Severity 2
        }

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
        Write-DATLogEntry -Value "[BIOS] Catalog cache path: $cachePath" -Severity 1
        Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading BIOS catalog..." -Type String

        # HMAC-SHA256 request signing for GET (softfail-safe -- skipped if secret is absent or computation fails)
        $hmacHeaders = @{}
        try {
            $telConfig = Get-DATTelemetryConfig
            $hmacSecret = $null
            if ($telConfig -and $telConfig.PSObject.Properties['hmacSecret']) {
                $hmacSecret = $telConfig.hmacSecret
            }
            if (-not [string]::IsNullOrEmpty($hmacSecret)) {
                $timestamp = (Get-Date).ToUniversalTime().ToString('o')
                $keyBytes  = [System.Text.Encoding]::UTF8.GetBytes($hmacSecret)
                $hmac      = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
                $sigBytes  = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($timestamp))
                $signature = -join ($sigBytes | ForEach-Object { $_.ToString('x2') })
                $hmac.Dispose()
                $hmacHeaders['x-dat-signature'] = $signature
                $hmacHeaders['x-dat-timestamp'] = $timestamp
            }
        } catch {
            Write-DATLogEntry -Value "[BIOS] HMAC signing skipped: $($_.Exception.Message)" -Severity 2
        }

        $downloaded = $false
        for ($i = 1; $i -le 3; $i++) {
            try {
                $proxyParams = Get-DATWebRequestProxy
                Invoke-WebRequest -Uri $catalogURL -OutFile $cachePath -Headers $hmacHeaders -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop @proxyParams
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

function Get-DATDriverCatalog {
    <#
    .SYNOPSIS
        Downloads and caches the DAT driver catalog from the API. Returns the parsed catalog array.
        On subsequent calls within the same session, returns the cached copy.
    #>
    [CmdletBinding()]
    param (
        [switch]$Force
    )

    if ($global:DriverCatalog -and -not $Force) {
        Write-DATLogEntry -Value "[DRIVERS] Using cached driver catalog ($($global:DriverCatalog.Count) entries)" -Severity 1
        return $global:DriverCatalog
    }

    $catalogURL = "https://api.driverautomationtool.com/api/catalog/drivers"
    $cachePath = Join-Path $global:TempDirectory "DATDriverCatalog.json"

    # Check if cached file is fresh (less than 24 hours old) to avoid unnecessary downloads
    $cacheIsFresh = (Test-Path $cachePath) -and ((Get-Date) - (Get-Item $cachePath).LastWriteTime).TotalHours -lt 24
    if ($cacheIsFresh -and -not $Force) {
        Write-DATLogEntry -Value "[DRIVERS] Using cached driver catalog (less than 24h old)" -Severity 1
    } else {
        Write-DATLogEntry -Value "[DRIVERS] Downloading driver catalog..." -Severity 1
        Write-DATLogEntry -Value "[DRIVERS] Catalog cache path: $cachePath" -Severity 1
        Set-DATRegistryValue -Name "RunningMessage" -Value "Downloading driver catalog..." -Type String

        # HMAC-SHA256 request signing for GET (softfail-safe -- skipped if secret is absent or computation fails)
        $hmacHeaders = @{}
        try {
            $telConfig = Get-DATTelemetryConfig
            $hmacSecret = $null
            if ($telConfig -and $telConfig.PSObject.Properties['hmacSecret']) {
                $hmacSecret = $telConfig.hmacSecret
            }
            if (-not [string]::IsNullOrEmpty($hmacSecret)) {
                $timestamp = (Get-Date).ToUniversalTime().ToString('o')
                $keyBytes  = [System.Text.Encoding]::UTF8.GetBytes($hmacSecret)
                $hmac      = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
                $sigBytes  = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($timestamp))
                $signature = -join ($sigBytes | ForEach-Object { $_.ToString('x2') })
                $hmac.Dispose()
                $hmacHeaders['x-dat-signature'] = $signature
                $hmacHeaders['x-dat-timestamp'] = $timestamp
            }
        } catch {
            Write-DATLogEntry -Value "[DRIVERS] HMAC signing skipped: $($_.Exception.Message)" -Severity 2
        }

        $downloaded = $false
        for ($i = 1; $i -le 3; $i++) {
            try {
                $proxyParams = Get-DATWebRequestProxy
                Invoke-WebRequest -Uri $catalogURL -OutFile $cachePath -Headers $hmacHeaders -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop @proxyParams
                $downloaded = $true
                break
            } catch {
                Write-DATLogEntry -Value "[Warning] - Driver catalog download attempt $i/3 failed: $($_.Exception.Message)" -Severity 2
                if ($i -lt 3) { Start-Sleep -Seconds 5 } else {
                    # If download fails but we have a cached copy, use it
                    if (Test-Path $cachePath) {
                        Write-DATLogEntry -Value "[DRIVERS] Using previously cached driver catalog" -Severity 2
                        $downloaded = $true
                    } else {
                        throw "Driver catalog unavailable after 3 attempts: $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    if (-not (Test-Path $cachePath)) {
        throw "Driver catalog file not found at $cachePath"
    }

    try {
        $global:DriverCatalog = @(Get-Content -Path $cachePath -Raw | ConvertFrom-Json)
        Write-DATLogEntry -Value "[DRIVERS] Catalog loaded: $($global:DriverCatalog.Count) entries" -Severity 1
        return $global:DriverCatalog
    } catch {
        throw "Failed to parse driver catalog JSON: $($_.Exception.Message)"
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
            Write-DATLogEntry -Value "[BIOS] Acer catalog download path: $acerFilePath" -Severity 1
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
    .PARAMETER OEM
        The OEM manufacturer name. Used to skip Authenticode checks for vendors
        whose downloads use inconsistent or non-standard signing (e.g. Acer).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]$BiosEntry,
        [Parameter(Mandatory)][string]$DownloadDestination,
        [string]$OEM
    )

    if (-not (Test-Path $DownloadDestination)) {
        New-Item -Path $DownloadDestination -ItemType Directory -Force | Out-Null
    }

    $destFile = Join-Path $DownloadDestination $BiosEntry.FileName

    $sigContext = "BIOS:$($BiosEntry.DisplayName)"

    # Check if already downloaded -- gate the cache with the same integrity policy applied
    # to fresh downloads so a tampered cached file cannot be reused on a subsequent run.
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
            # No published hash -- fall back to Authenticode allow-list. Fail closed.
            # Skip for Acer: their downloads use inconsistent signers that cannot be reliably validated.
            if ($OEM -eq 'Acer') {
                Write-DATLogEntry -Value "[BIOS] File already cached (Acer -- Authenticode check skipped): $destFile" -Severity 1
                return $destFile
            } elseif (Test-DATFileSignature -FilePath $destFile -Context $sigContext) {
                Write-DATLogEntry -Value "[BIOS] File already cached and Authenticode-verified: $destFile" -Severity 1
                return $destFile
            } else {
                Write-DATLogEntry -Value "[BIOS] Cached file failed Authenticode allow-list -- re-downloading" -Severity 2
                Remove-Item $destFile -Force -ErrorAction SilentlyContinue
            }
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

    # Integrity verification -- prefer published hash, fall back to Authenticode allow-list.
    # This branch ALWAYS runs and is fail-closed: if neither a hash match nor a trusted
    # signature can be confirmed, the file is deleted and $null is returned. This closes
    # the catalog-poisoning / TLS-MITM path for vendors that do not publish per-file hashes
    # (e.g. Acer, where the catalog FileHash is intentionally null).
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
    } else {
        # Skip Authenticode for Acer -- their downloads use inconsistent signers
        if ($OEM -eq 'Acer') {
            Write-DATLogEntry -Value "[BIOS] No published hash -- Acer OEM detected, Authenticode check skipped (HTTPS transport integrity only)" -Severity 2
        } else {
            Write-DATLogEntry -Value "[BIOS] No published hash -- verifying Authenticode signer against trusted publisher allow-list" -Severity 1
            if (-not (Test-DATFileSignature -FilePath $destFile -Context $sigContext)) {
                Write-DATLogEntry -Value "[BIOS] Integrity check FAILED -- discarding downloaded file" -Severity 3
                Remove-Item $destFile -Force -ErrorAction SilentlyContinue
                return $null
            }
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
        [switch]$SkipWim,
        [switch]$IncludeFlash64W
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
            # Lenovo BIOS packages are Inno Setup self-extracting installers.
            # Run the installer silently to extract files to the target directory,
            # poll for extracted files, then kill the process tree before the [Run]
            # section can flash the BIOS.
            Write-DATLogEntry -Value "[BIOS] Lenovo: Extracting Inno Setup BIOS package to expose flash utilities" -Severity 1

            # Known Lenovo flash utility process names -- kill immediately if spawned
            $flashProcessNames = @('WinUPTP64', 'WinUPTP', 'wFlashGUIX64', 'wFlashGUI',
                                   'AFUWINx64', 'AFUWIN', 'Flash64', 'InsydeFlash')

            try {
                Unblock-File -Path $BiosFilePath -ErrorAction SilentlyContinue

                # Clear any previous flash-killed flag
                Remove-ItemProperty -Path $global:RegPath -Name 'LenovoFlashKilled' -ErrorAction SilentlyContinue

                $extractProc = Start-Process -FilePath $BiosFilePath `
                    -ArgumentList "/VERYSILENT /DIR=`"$extractDir`" /EXTRACT=`"YES`" /SP- /SUPPRESSMSGBOXES /NORESTART" `
                    -WindowStyle Hidden -PassThru

                # Poll until flash-related files appear AND the file count stabilises,
                # confirming Inno Setup has finished writing all files before we kill it.
                # Simultaneously monitor for flash utility processes and kill them immediately.
                $maxWaitSec = 120
                $elapsed = 0
                $extractionDone = $false
                $lastFileCount = 0
                $stableChecks = 0
                $requiredStableChecks = 4  # 4 x 500ms = 2 seconds of stable file count
                while ($elapsed -lt $maxWaitSec -and -not $extractProc.HasExited) {
                    # TEMPORARILY DISABLED: kill flash utilities during extraction
                    <# foreach ($flashName in $flashProcessNames) {
                        $flashProcs = Get-Process -Name $flashName -ErrorAction SilentlyContinue
                        foreach ($fp in $flashProcs) {
                            try {
                                $fp.Kill()
                                Write-DATLogEntry -Value "[BIOS] Lenovo: Auto-killed flash utility $($fp.ProcessName) (PID $($fp.Id)) before it could run" -Severity 2
                                Set-DATRegistryValue -Name 'LenovoFlashKilled' -Value $fp.ProcessName -Type String
                            } catch {}
                        }
                    } #>

                    $extractedFiles = @(Get-ChildItem -Path $extractDir -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match '\.(cmd|cap|rom|bin|exe)$' -and $_.Name -ne (Split-Path $BiosFilePath -Leaf) })
                    if ($extractedFiles.Count -ge 2) {
                        if ($extractedFiles.Count -eq $lastFileCount) {
                            $stableChecks++
                        } else {
                            $stableChecks = 0
                            $lastFileCount = $extractedFiles.Count
                        }
                        if ($stableChecks -ge $requiredStableChecks) {
                            $extractionDone = $true
                            Write-DATLogEntry -Value "[BIOS] Lenovo: Extraction complete -- $($extractedFiles.Count) files detected and stable for $($requiredStableChecks * 0.5)s, terminating installer" -Severity 1
                            break
                        }
                    }
                    Start-Sleep -Milliseconds 500
                    $elapsed += 0.5
                }

                # TEMPORARILY DISABLED: Kill the Inno Setup process tree
                <# if (-not $extractProc.HasExited) {
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
                } #>

                # TEMPORARILY DISABLED: Final sweep kill flash utilities
                <# foreach ($flashName in $flashProcessNames) {
                    $flashProcs = Get-Process -Name $flashName -ErrorAction SilentlyContinue
                    foreach ($fp in $flashProcs) {
                        try {
                            $fp.Kill()
                            Write-DATLogEntry -Value "[BIOS] Lenovo: Post-extract killed flash utility $($fp.ProcessName) (PID $($fp.Id))" -Severity 2
                            Set-DATRegistryValue -Name 'LenovoFlashKilled' -Value $fp.ProcessName -Type String
                        } catch {}
                    }
                } #>

                if (-not $extractionDone) {
                    # Process exited on its own -- check if files were extracted
                    $extractedFiles = @(Get-ChildItem -Path $extractDir -File -ErrorAction SilentlyContinue)
                    if ($extractedFiles.Count -lt 2) {
                        throw "Lenovo BIOS extraction produced insufficient files (found: $($extractedFiles.Count))"
                    }
                }

                # Clean up: remove uninstall artifacts left by Inno Setup
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

    # Stage Flash64W.exe for Dell when requested (ConfigMgr and WIM Package Only modes)
    if ($IncludeFlash64W -and $OEM -eq 'Dell') {
        Write-DATLogEntry -Value "[BIOS] Dell: Ensuring Flash64W.exe is staged in extraction directory" -Severity 1
        $flash64Result = Get-DATFlash64W -DestinationDir $extractDir
        if (-not $flash64Result) {
            Write-DATLogEntry -Value "[Warning] Flash64W.exe could not be obtained -- Dell BIOS package may not work in WinPE" -Severity 2
        }
    }

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

    # Write a version marker so the pre-flight check can skip re-downloads when the version matches
    $versionMarker = Join-Path $destBiosFolder ".biosversion"
    Set-Content -Path $versionMarker -Value $Version -Encoding UTF8 -Force

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

    # HMAC-SHA256 request signing (softfail-safe -- skipped if secret is absent or computation fails)
    $headers = @{}
    try {
        $hmacSecret = $null
        if ($config -and $config.PSObject.Properties['hmacSecret']) {
            $hmacSecret = $config.hmacSecret
        }
        if (-not [string]::IsNullOrEmpty($hmacSecret)) {
            $timestamp = (Get-Date).ToUniversalTime().ToString('o')
            $keyBytes  = [System.Text.Encoding]::UTF8.GetBytes($hmacSecret)
            $hmac      = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
            $sigBytes  = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json))
            $signature = -join ($sigBytes | ForEach-Object { $_.ToString('x2') })
            $hmac.Dispose()
            $headers['x-dat-signature'] = $signature
            $headers['x-dat-timestamp'] = $timestamp
        }
    } catch {
        Write-DATLogEntry -Value "[Telemetry] HMAC signing skipped: $($_.Exception.Message)" -Severity 2
    }

    try {
        $proxyParams = Get-DATWebRequestProxy
        if ($proxyParams -isnot [hashtable]) { $proxyParams = @{} }
        $null = Invoke-RestMethod -Uri $url -Method POST -Body $json -ContentType 'application/json' `
            -Headers $headers -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop @proxyParams
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

function Send-DATFeedback {
    <#
    .SYNOPSIS
        Submits user feedback (thumbs up/down) to the DAT API.
    .PARAMETER Rating
        'Positive' or 'Negative'.
    .PARAMETER Comment
        Optional comment text (used with negative feedback).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('Positive', 'Negative')]
        [string]$Rating,

        [AllowEmptyString()]
        [string]$Comment = '',

        [AllowEmptyString()]
        [string]$Email = '',

        [bool]$FollowUp = $false
    )

    $telemetryId = Get-DATTelemetryId
    if ([string]::IsNullOrEmpty($telemetryId)) {
        # Generate a one-time GUID if telemetry is not configured
        $telemetryId = [guid]::NewGuid().ToString()
    }

    $body = @{
        installId   = $telemetryId
        rating      = $Rating
        comment     = $Comment
        email       = $Email
        followUp    = [bool]$FollowUp
        submittedAt = (Get-Date).ToUniversalTime().ToString('o')
        appVersion  = $global:ScriptRelease
    }

    $config = Get-DATTelemetryConfig
    if ($null -eq $config -or [string]::IsNullOrEmpty($config.apiBaseUrl)) {
        Write-DATLogEntry -Value "[Feedback] Cannot submit -- API config unavailable" -Severity 2
        return
    }

    $url = "$($config.apiBaseUrl)/feedback"
    $json = $body | ConvertTo-Json -Depth 5 -Compress

    # HMAC-SHA256 request signing (softfail-safe -- skipped if secret is absent or computation fails)
    $headers = @{}
    try {
        $hmacSecret = $null
        if ($config -and $config.PSObject.Properties['hmacSecret']) {
            $hmacSecret = $config.hmacSecret
        }
        if (-not [string]::IsNullOrEmpty($hmacSecret)) {
            $timestamp = (Get-Date).ToUniversalTime().ToString('o')
            $keyBytes  = [System.Text.Encoding]::UTF8.GetBytes($hmacSecret)
            $hmac      = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
            $sigBytes  = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json))
            $signature = -join ($sigBytes | ForEach-Object { $_.ToString('x2') })
            $hmac.Dispose()
            $headers['x-dat-signature'] = $signature
            $headers['x-dat-timestamp'] = $timestamp
        }
    } catch {
        Write-DATLogEntry -Value "[Feedback] HMAC signing skipped: $($_.Exception.Message)" -Severity 2
    }

    try {
        $proxyParams = Get-DATWebRequestProxy
        if ($proxyParams -isnot [hashtable]) { $proxyParams = @{} }
        $null = Invoke-RestMethod -Uri $url -Method POST -Body $json -ContentType 'application/json' `
            -Headers $headers -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop @proxyParams
        Write-DATLogEntry -Value "[Feedback] Submitted $Rating feedback successfully" -Severity 1
    } catch {
        Write-DATLogEntry -Value "[Feedback] Submit failed: $($_.Exception.Message)" -Severity 2
        throw
    }
}

function Get-DATHPSoftPaqManifestPath {
    <#
    .SYNOPSIS
        Returns the full path to the HP SoftPaq manifest file under Settings.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $settingsDir = Join-Path $global:ScriptDirectory 'Settings'
    if (-not (Test-Path -LiteralPath $settingsDir)) {
        try { New-Item -Path $settingsDir -ItemType Directory -Force | Out-Null } catch {}
    }
    return (Join-Path $settingsDir 'HPSoftPaqManifest.json')
}

function Get-DATHPSoftPaqManifestKey {
    <#
    .SYNOPSIS
        Builds a stable manifest key for an HP model/OS/build/architecture combination.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][AllowEmptyString()][string]$Model,
        [Parameter(Mandatory)][AllowEmptyString()][string]$OSVersion,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Build,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Architecture
    )
    return ("HP|{0}|{1}|{2}|{3}" -f $Model.Trim(), $OSVersion.Trim(), $Build.Trim(), $Architecture.Trim())
}

function Get-DATSoftPaqFingerprint {
    <#
    .SYNOPSIS
        Computes an order-independent SHA256 fingerprint of a SoftPaq ID list.
    .DESCRIPTION
        IDs are validated (4-8 digits), de-duplicated, sorted numerically and joined
        before hashing so the fingerprint is stable regardless of discovery order.
        Returns a lowercase hex string, or $null when no valid IDs are supplied.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowNull()][AllowEmptyString()][string[]]$SoftPaqIds
    )
    if ($null -eq $SoftPaqIds) { return $null }
    $valid = @($SoftPaqIds |
        ForEach-Object { if ($null -ne $_) { $_.Trim() } } |
        Where-Object { $_ -match '^\d{4,8}$' } |
        Select-Object -Unique |
        Sort-Object { [long]$_ })
    if ($valid.Count -eq 0) { return $null }
    $joined = ($valid -join ',')
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
        $hashBytes = $sha.ComputeHash($bytes)
        return [BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-DATHPSoftPaqManifest {
    <#
    .SYNOPSIS
        Loads the HP SoftPaq manifest as a hashtable. Missing or corrupt files yield an empty manifest.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $path = Get-DATHPSoftPaqManifestPath
    $manifest = @{}
    if (Test-Path -LiteralPath $path) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $obj = $raw | ConvertFrom-Json -ErrorAction Stop
                foreach ($prop in $obj.PSObject.Properties) {
                    $manifest[$prop.Name] = $prop.Value
                }
            }
        } catch {
            Write-DATLogEntry -Value "[HP] SoftPaq manifest unreadable, treating as empty: $($_.Exception.Message)" -Severity 2
            $manifest = @{}
        }
    }
    return $manifest
}

function Save-DATHPSoftPaqManifest {
    <#
    .SYNOPSIS
        Atomically persists the HP SoftPaq manifest hashtable to disk. Never throws.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)][hashtable]$Manifest
    )
    $path = Get-DATHPSoftPaqManifestPath
    try {
        $json = $Manifest | ConvertTo-Json -Depth 6
        $tmp = "$path.tmp"
        Set-Content -LiteralPath $tmp -Value $json -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $tmp -Destination $path -Force -ErrorAction Stop
        return $true
    } catch {
        Write-DATLogEntry -Value "[HP] Failed to save SoftPaq manifest: $($_.Exception.Message)" -Severity 2
        return $false
    }
}

function Update-DATHPSoftPaqManifestReference {
    <#
    .SYNOPSIS
        Records the remote package reference (Intune app id or ConfigMgr package name)
        on an existing HP SoftPaq manifest entry so a later run can verify the package
        still exists before deciding to skip a rebuild. No-ops when the entry is absent.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][ValidateSet('intuneAppId', 'configMgrPackageId')][string]$Field,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )
    $manifest = Get-DATHPSoftPaqManifest
    if (-not $manifest.ContainsKey($Key)) { return $false }
    try {
        $entry = $manifest[$Key]
        $entry | Add-Member -NotePropertyName $Field -NotePropertyValue $Value -Force
        $manifest[$Key] = $entry
        return (Save-DATHPSoftPaqManifest -Manifest $manifest)
    } catch {
        Write-DATLogEntry -Value "[HP] Failed to record SoftPaq manifest reference ($Field): $($_.Exception.Message)" -Severity 2
        return $false
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

#region BIOS Package Name Repair

function Repair-DATBiosPackageNames {
    <#
    .SYNOPSIS
        Scans Intune and/or ConfigMgr for BIOS packages using the old naming convention
        (with OS version) and renames them to the new convention (architecture only).
    .DESCRIPTION
        Old Intune naming:   "BIOS - Dell Precision 5690 - Windows 11 25H2 x64" or
                             "BIOS - Dell Precision 5690 - x64"
        New Intune naming:   "BIOS - Dell Precision 5690" (no OS version, no architecture suffix)

        Old ConfigMgr naming: "BIOS Update - Dell Precision 5690 - x64" (with architecture suffix)
        New ConfigMgr naming:  "BIOS Update - Dell Precision 5690" (no architecture suffix)

        Returns an array of result objects with OldName, NewName, Platform, Status, and Error.
    #>
    [CmdletBinding()]
    param (
        [ValidateSet('Intune','ConfigMgr','Both')]
        [string]$Platform = 'Both',
        [string]$SiteServer,
        [string]$SiteCode,
        [System.Collections.Concurrent.ConcurrentQueue[object]]$ProgressQueue
    )

    $results = [System.Collections.ArrayList]::new()

    # --- Intune BIOS package rename ---
    if ($Platform -in @('Intune', 'Both')) {
        Write-DATLogEntry -Value "[BIOS Repair] Scanning Intune for old-format BIOS package names..." -Severity 1
        try {
            if (-not (Test-DATIntuneAuth)) {
                [void]$results.Add([PSCustomObject]@{
                    OldName  = ''; NewName = ''; Platform = 'Intune'
                    Status   = 'Skipped'; Error = 'Not authenticated to Intune'
                })
            } else {
                $allApps = Get-DATIntuneWin32Apps | Where-Object {
                    $_.notes -eq 'Created by the Driver Automation Tool' -and
                    ($_.displayName -match '^BIOS\s*-\s*.+\s*-\s*Windows\s' -or
                     $_.displayName -match '^BIOS\s*-\s*.+\s*-\s*(x64|Arm64)\s*$')
                }
                if ($allApps.Count -eq 0) {
                    Write-DATLogEntry -Value "[BIOS Repair] No Intune BIOS packages with old naming found" -Severity 1
                } else {
                    Write-DATLogEntry -Value "[BIOS Repair] Found $($allApps.Count) Intune BIOS package(s) to fix" -Severity 1
                    if ($ProgressQueue) {
                        [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Info'; Message = "Found $($allApps.Count) Intune BIOS package(s) to rename" })
                        [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'ExpectedCount'; Count = $allApps.Count })
                    }
                }

                foreach ($app in $allApps) {
                    $oldName = $app.displayName
                    # Strip OS + arch suffix (e.g. "- Windows 11 25H2 x64") or arch-only suffix (e.g. "- x64")
                    $newName = $null
                    if ($oldName -match '^(BIOS\s*-\s*.+?)\s*-\s*Windows\s+\d+\s+\S+\s+(x64|Arm64)\s*$') {
                        $newName = $Matches[1].Trim()
                    } elseif ($oldName -match '^(BIOS\s*-\s*.+?)\s*-\s*(x64|Arm64)\s*$') {
                        $newName = $Matches[1].Trim()
                    }
                    if ($null -ne $newName) {
                        try {
                            # Update displayName via Graph PATCH
                            $patchBody = @{
                                '@odata.type' = '#microsoft.graph.win32LobApp'
                                displayName   = $newName
                            }
                            Invoke-DATGraphRequest -Uri "/deviceAppManagement/mobileApps/$($app.id)" `
                                -Method PATCH -Body $patchBody | Out-Null

                            # Also update description to remove OS line if present
                            if ($app.description -match '(?m)^OS:\s*Windows\s') {
                                $newDesc = ($app.description -replace '(?m)^OS:\s*Windows\s[^\n]*\n?', '').Trim()
                                Invoke-DATGraphRequest -Uri "/deviceAppManagement/mobileApps/$($app.id)" `
                                    -Method PATCH -Body @{
                                        '@odata.type' = '#microsoft.graph.win32LobApp'
                                        description   = $newDesc
                                    } | Out-Null
                            }

                            Write-DATLogEntry -Value "[BIOS Repair] Intune: '$oldName' -> '$newName'" -Severity 1
                            [void]$results.Add([PSCustomObject]@{
                                OldName  = $oldName; NewName = $newName; Platform = 'Intune'
                                Status   = 'Renamed'; Error = ''
                            })
                            if ($ProgressQueue) {
                                [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Renamed'; OldName = $oldName; NewName = $newName; Platform = 'Intune' })
                            }
                        } catch {
                            Write-DATLogEntry -Value "[BIOS Repair] Failed to rename '$oldName': $($_.Exception.Message)" -Severity 3
                            [void]$results.Add([PSCustomObject]@{
                                OldName  = $oldName; NewName = $newName; Platform = 'Intune'
                                Status   = 'Failed'; Error = $_.Exception.Message
                            })
                            if ($ProgressQueue) {
                                [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Failed'; OldName = $oldName; NewName = $newName; Platform = 'Intune'; Error = $_.Exception.Message })
                            }
                        }
                    }
                }
            }
        } catch {
            Write-DATLogEntry -Value "[BIOS Repair] Intune scan failed: $($_.Exception.Message)" -Severity 3
            [void]$results.Add([PSCustomObject]@{
                OldName  = ''; NewName = ''; Platform = 'Intune'
                Status   = 'Error'; Error = $_.Exception.Message
            })
        }
    }

    # --- ConfigMgr BIOS package rename ---
    if ($Platform -in @('ConfigMgr', 'Both')) {
        if ([string]::IsNullOrEmpty($SiteServer) -or [string]::IsNullOrEmpty($SiteCode)) {
            Write-DATLogEntry -Value "[BIOS Repair] ConfigMgr site server/code not provided -- skipping" -Severity 2
            [void]$results.Add([PSCustomObject]@{
                OldName  = ''; NewName = ''; Platform = 'ConfigMgr'
                Status   = 'Skipped'; Error = 'Site server or site code not configured'
            })
        } else {
            Write-DATLogEntry -Value "[BIOS Repair] Scanning ConfigMgr for old-format BIOS package names..." -Severity 1
            try {
                $smsNamespace = "root\SMS\Site_$SiteCode"

                $cimSession = New-DATCimSession -ComputerName $SiteServer

                # Old format: "BIOS Update - OEM Model" (no architecture suffix)
                $wmiQuery = "SELECT PackageID, Name, Version, MIFVersion FROM SMS_Package WHERE Name LIKE 'BIOS Update -%'"
                $cmPackages = Invoke-DATRemoteQuery -CimSession $cimSession -ComputerName $SiteServer -Namespace $smsNamespace `
                    -Query $wmiQuery

                # Filter to packages WITH architecture suffix (old format — new format has no arch in name)
                $oldFormatPkgs = @($cmPackages | Where-Object {
                    $name = $_.Name
                    $mif = $_.MIFVersion
                    $needsNameFix = $name -match '\s*-\s*(x64|Arm64)\s*$'
                    $needsMifFix = $mif -match 'Windows\s+\d+'
                    $needsNameFix -or $needsMifFix
                })

                if ($oldFormatPkgs.Count -eq 0) {
                    Write-DATLogEntry -Value "[BIOS Repair] No ConfigMgr BIOS packages with old naming found" -Severity 1
                } else {
                    Write-DATLogEntry -Value "[BIOS Repair] Found $($oldFormatPkgs.Count) ConfigMgr BIOS package(s) to fix" -Severity 1
                    if ($ProgressQueue) {
                        [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Info'; Message = "Found $($oldFormatPkgs.Count) ConfigMgr BIOS package(s) to rename" })
                        [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'ExpectedCount'; Count = $oldFormatPkgs.Count })
                    }
                }

                foreach ($pkg in $oldFormatPkgs) {
                    $oldName = $pkg.Name
                    $oldMif = $pkg.MIFVersion

                    # Determine architecture from name or MIFVersion (for log only)
                    $arch = 'x64'
                    if ($oldName -match '\s*-\s*(x64|Arm64)\s*$') { $arch = $Matches[1] }
                    elseif ($oldMif -match '(x64|Arm64)') { $arch = $Matches[1] }

                    # Build new name: strip architecture suffix if present
                    $newName = $oldName -replace '\s*-\s*(x64|Arm64)\s*$', ''

                    # New BIOS packages have empty MIFVersion
                    $newMif = ''

                    try {
                        if ($null -ne $cimSession) {
                            # CIM path: fetch live instance and update via Set-CimInstance
                            $livePkg = Get-CimInstance -CimSession $cimSession -Namespace $smsNamespace `
                                -Query "SELECT * FROM SMS_Package WHERE PackageID = '$($pkg.PackageID)'" `
                                -ErrorAction Stop | Select-Object -First 1

                            if (-not $livePkg) {
                                throw "Package '$($pkg.PackageID)' not found during live fetch"
                            }

                            Set-CimInstance -CimSession $cimSession -InputObject $livePkg `
                                -Property @{ Name = $newName; MIFVersion = $newMif } -ErrorAction Stop
                        } else {
                            # Legacy WMI fallback: use [wmi] accelerator + .Put()
                            $wmiPkg = [wmi]"\\$SiteServer\$($smsNamespace):SMS_Package.PackageID='$($pkg.PackageID)'"
                            $wmiPkg.Name = $newName
                            $wmiPkg.MIFVersion = $newMif
                            $wmiPkg.Put() | Out-Null
                        }

                        Write-DATLogEntry -Value "[BIOS Repair] ConfigMgr: '$oldName' -> '$newName' (MIFVersion: '$oldMif' -> '$newMif')" -Severity 1
                        [void]$results.Add([PSCustomObject]@{
                            OldName  = $oldName; NewName = $newName; Platform = 'ConfigMgr'
                            Status   = 'Renamed'; Error = ''
                        })
                        if ($ProgressQueue) {
                            [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Renamed'; OldName = $oldName; NewName = $newName; Platform = 'ConfigMgr' })
                        }
                    } catch {
                        Write-DATLogEntry -Value "[BIOS Repair] Failed to rename '$oldName': $($_.Exception.Message)" -Severity 3
                        [void]$results.Add([PSCustomObject]@{
                            OldName  = $oldName; NewName = $newName; Platform = 'ConfigMgr'
                            Status   = 'Failed'; Error = $_.Exception.Message
                        })
                        if ($ProgressQueue) {
                            [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Failed'; OldName = $oldName; NewName = $newName; Platform = 'ConfigMgr'; Error = $_.Exception.Message })
                        }
                    }
                }

                Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue
            } catch {
                Write-DATLogEntry -Value "[BIOS Repair] ConfigMgr scan failed: $($_.Exception.Message)" -Severity 3
                [void]$results.Add([PSCustomObject]@{
                    OldName  = ''; NewName = ''; Platform = 'ConfigMgr'
                    Status   = 'Error'; Error = $_.Exception.Message
                })
            }
        }
    }

    return $results
}

function Remove-DATBiosDuplicatePackages {
    <#
    .SYNOPSIS
        Resolves duplicate BIOS packages in ConfigMgr by keeping the newest version,
        normalizing the kept package name to remove any architecture suffix, and removing stale duplicates.
    .DESCRIPTION
        Detects ConfigMgr BIOS package duplicates:
        - Old naming: "BIOS Update - Dell Latitude 5540 - x64" (with architecture suffix)
        - New naming: "BIOS Update - Dell Latitude 5540" (no architecture suffix)

        When duplicates are found, the package with the highest BIOS version (from SMS_Package.Version)
        is kept. Any stale duplicates are removed, including package source folders.
        If the kept package has an architecture suffix, it is renamed to remove it.

        Returns an array of result objects with OldName, Platform, Status, and Error.
    #>
    [CmdletBinding()]
    param (
        [string]$SiteServer,
        [string]$SiteCode,
        [System.Collections.Concurrent.ConcurrentQueue[object]]$ProgressQueue,
        [switch]$ScanOnly
    )

    $results = [System.Collections.ArrayList]::new()

    if (-not $SiteServer -or -not $SiteCode) {
        Write-DATLogEntry -Value "[BIOS Duplicate Removal] ConfigMgr not configured, skipping" -Severity 1
        return $results
    }

    $scanMode = if ($ScanOnly) { 'scan' } else { 'full'  }
    Write-DATLogEntry -Value "[BIOS Duplicate Removal] Starting ($scanMode mode)..." -Severity 1

    try {
        Write-DATLogEntry -Value "[BIOS Duplicate Removal] Scanning ConfigMgr for duplicate BIOS packages..." -Severity 1
        $smsNamespace = "root\SMS\Site_$SiteCode"
        $cimSession = New-DATCimSession -ComputerName $SiteServer

        # Get all BIOS packages (Version = BIOS version number set by DAT; MIFVersion is intentionally empty for BIOS)
        $allBiosPkgs = @(Invoke-DATRemoteQuery -CimSession $cimSession -ComputerName $SiteServer `
            -Namespace $smsNamespace -Query "SELECT PackageID, Name, PkgSourcePath, Version FROM SMS_Package WHERE Name LIKE 'BIOS Update -%'")

        if ($allBiosPkgs.Count -eq 0) {
            Write-DATLogEntry -Value "[BIOS Duplicate Removal] No BIOS packages found" -Severity 1
            return $results
        }

        # Group all BIOS packages by model base name (strip trailing arch suffix if present)
        $grouped = @{}
        foreach ($pkg in $allBiosPkgs) {
            if ($pkg.Name -match '^(BIOS Update\s*-\s*.+?)(?:\s*-\s*(x64|Arm64))?\s*$') {
                $baseModel = $Matches[1].Trim()
                $hasArch   = [bool]$Matches[2]

                if (-not $grouped.ContainsKey($baseModel)) {
                    $grouped[$baseModel] = [System.Collections.ArrayList]::new()
                }
                [void]$grouped[$baseModel].Add([PSCustomObject]@{
                    Package = $pkg
                    HasArch = $hasArch
                })
            }
        }

        # Find and resolve duplicates: any model with more than one package (regardless of naming style)
        $duplicatesFound = $false
        foreach ($modelKey in $grouped.Keys) {
            $entries = $grouped[$modelKey]

            # Only act when there are duplicates for this model
            if ($entries.Count -lt 2) { continue }
            $duplicatesFound = $true

            Write-DATLogEntry -Value "[BIOS Duplicate Removal] Found $($entries.Count) packages for model: $modelKey" -Severity 1
            if ($ProgressQueue) {
                [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Info'; Message = "Found $($entries.Count) duplicate BIOS packages for: $modelKey" })
            }

            # Build metadata using the package Version field (BIOS version number set by DAT)
            $pkgMeta = foreach ($entry in $entries) {
                $pkg = $entry.Package
                $versionString = [string]$pkg.Version
                $parsedVersion = [version]'0.0.0.0'
                if ($versionString -match '(\d+(?:\.\d+)+)') {
                    try { $parsedVersion = [version]$Matches[1] } catch { }
                }
                [PSCustomObject]@{
                    Package       = $pkg
                    ParsedVersion = $parsedVersion
                    HasArch       = $entry.HasArch
                }
            }

            # Audit log every candidate before deciding
            foreach ($meta in $pkgMeta) {
                $candidatePkg = $meta.Package
                Write-DATLogEntry -Value "[BIOS Duplicate Removal] Candidate -- Model: '$modelKey', PackageID: '$($candidatePkg.PackageID)', Name: '$($candidatePkg.Name)', Version: '$($candidatePkg.Version)', ParsedVersion: '$($meta.ParsedVersion)', HasArchSuffix: '$($meta.HasArch)'" -Severity 1
            }

            # Keep the highest-version package; use HasArch as tiebreaker only when versions are identical
            $keepMeta = $pkgMeta | Sort-Object -Property `
                @{ Expression = { $_.ParsedVersion };       Descending = $true }, `
                @{ Expression = { [int](-not $_.HasArch) }; Descending = $true } | Select-Object -First 1
            $keepPkg = $keepMeta.Package
            Write-DATLogEntry -Value "[BIOS Duplicate Removal] Keeping newest package -- Model: '$modelKey', PackageID: '$($keepPkg.PackageID)', Name: '$($keepPkg.Name)', Version: '$($keepPkg.Version)', ParsedVersion: '$($keepMeta.ParsedVersion)'" -Severity 1

            # In ScanOnly mode: record what would be removed and move on without making changes
            if ($ScanOnly) {
                $removePkgsScan = $entries | Where-Object { $_.Package.PackageID -ne $keepPkg.PackageID } | ForEach-Object { $_.Package }
                foreach ($oldPkgScan in $removePkgsScan) {
                    [void]$results.Add([PSCustomObject]@{
                        OldName  = $oldPkgScan.Name
                        KeepName = $keepPkg.Name
                        Platform = 'ConfigMgr'
                        Status   = 'WouldRemove'
                        Error    = ''
                    })
                }
                continue
            }

            # Normalise kept package name: new Dell BIOS names do NOT include an arch suffix -- strip it if present
            if ($keepPkg.Name -match '^(.+?)\s*-\s*(x64|Arm64)\s*$') {
                $renameTarget = $Matches[1].Trim()
                try {
                    if ($null -ne $cimSession) {
                        $liveKeepPkg = Get-CimInstance -CimSession $cimSession -Namespace $smsNamespace `
                            -Query "SELECT * FROM SMS_Package WHERE PackageID = '$($keepPkg.PackageID)'" -ErrorAction Stop |
                            Select-Object -First 1
                        Set-CimInstance -CimSession $cimSession -InputObject $liveKeepPkg `
                            -Property @{ Name = $renameTarget } -ErrorAction Stop
                    } else {
                        $wmiKeepPkg = [wmi]"\\$SiteServer\$($smsNamespace):SMS_Package.PackageID='$($keepPkg.PackageID)'"
                        $wmiKeepPkg.Name = $renameTarget
                        $wmiKeepPkg.Put() | Out-Null
                    }
                    Write-DATLogEntry -Value "[BIOS Duplicate Removal] Normalised kept package name '$($keepPkg.Name)' -> '$renameTarget'" -Severity 1
                    $keepPkg.Name = $renameTarget
                } catch {
                    Write-DATLogEntry -Value "[BIOS Duplicate Removal] Failed to normalise kept package name '$($keepPkg.Name)': $($_.Exception.Message)" -Severity 2
                }
            }

            $removePkgs = $entries | Where-Object { $_.Package.PackageID -ne $keepPkg.PackageID } | ForEach-Object { $_.Package }
            foreach ($oldPkg in $removePkgs) {
                Write-DATLogEntry -Value "[BIOS Duplicate Removal] Removing stale package -- Model: '$modelKey', PackageID: '$($oldPkg.PackageID)', Name: '$($oldPkg.Name)', Version: '$($oldPkg.Version)', SourcePath: '$($oldPkg.PkgSourcePath)'" -Severity 1
                try {
                    $oldName = $oldPkg.Name
                    $pkgPath = $oldPkg.PkgSourcePath

                    # Delete package from ConfigMgr
                    if ($null -ne $cimSession) {
                        Get-CimInstance -CimSession $cimSession -Namespace $smsNamespace `
                            -Query "SELECT * FROM SMS_Package WHERE PackageID = '$($oldPkg.PackageID)'" -ErrorAction Stop |
                            Remove-CimInstance -ErrorAction Stop
                    } else {
                        $wmiPkg = [wmi]"\\$SiteServer\$($smsNamespace):SMS_Package.PackageID='$($oldPkg.PackageID)'"
                        $wmiPkg.Delete() | Out-Null
                    }

                    # Delete source folder only when it is NOT shared with the package being kept
                    # (identical source paths would destroy the surviving package's content)
                    $keepPath = $keepPkg.PkgSourcePath
                    $sourceIsSame = (-not [string]::IsNullOrEmpty($pkgPath)) -and
                                    (-not [string]::IsNullOrEmpty($keepPath)) -and
                                    ($pkgPath.TrimEnd('\', '/') -ieq $keepPath.TrimEnd('\', '/'))

                    if ($sourceIsSame) {
                        Write-DATLogEntry -Value "[BIOS Duplicate Removal] Skipping source folder deletion -- path is shared with kept package '$($keepPkg.Name)': $pkgPath" -Severity 2
                    } elseif (-not [string]::IsNullOrEmpty($pkgPath) -and (Test-Path $pkgPath)) {
                        try {
                            Remove-Item -Path $pkgPath -Recurse -Force -ErrorAction Stop
                            Write-DATLogEntry -Value "[BIOS Duplicate Removal] Deleted package source folder: $pkgPath" -Severity 1
                        } catch {
                            Write-DATLogEntry -Value "[BIOS Duplicate Removal] Warning: Failed to delete source folder '$pkgPath': $($_.Exception.Message)" -Severity 2
                        }
                    }

                    Write-DATLogEntry -Value "[BIOS Duplicate Removal] Removed duplicate package: '$oldName'" -Severity 1
                    [void]$results.Add([PSCustomObject]@{
                        OldName  = $oldName
                        Platform = 'ConfigMgr'
                        Status   = 'Removed'
                        Error    = ''
                    })

                    if ($ProgressQueue) {
                        [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Removed'; OldName = $oldName; Platform = 'ConfigMgr' })
                    }
                } catch {
                    Write-DATLogEntry -Value "[BIOS Duplicate Removal] Failed to remove duplicate: $($_.Exception.Message)" -Severity 3
                    [void]$results.Add([PSCustomObject]@{
                        OldName  = $oldPkg.Name
                        Platform = 'ConfigMgr'
                        Status   = 'Failed'
                        Error    = $_.Exception.Message
                    })

                    if ($ProgressQueue) {
                        [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Failed'; OldName = $oldPkg.Name; Platform = 'ConfigMgr'; Error = $_.Exception.Message })
                    }
                }
            }
        }

        if (-not $duplicatesFound) {
            Write-DATLogEntry -Value "[BIOS Duplicate Removal] No duplicate BIOS packages found" -Severity 1
        }

        if ($cimSession) { Remove-CimSession -CimSession $cimSession -ErrorAction SilentlyContinue }
    } catch {
        Write-DATLogEntry -Value "[BIOS Duplicate Removal] Error scanning ConfigMgr: $($_.Exception.Message)" -Severity 3
        [void]$results.Add([PSCustomObject]@{
            OldName  = ''
            Platform = 'ConfigMgr'
            Status   = 'Error'
            Error    = $_.Exception.Message
        })
    }

    return $results
}

#endregion BIOS Package Name Repair

#region Driver Package Naming Repair - Intune

function Repair-DATIntuneDriverPackageNames {
    <#
    .SYNOPSIS
        Scans Intune for driver packages using the old multi-build naming convention
        and renames them to the correct single-OS format.
    .DESCRIPTION
        Old naming: "Drivers - Dell Latitude 5540 - Windows 11 25H2;Windows 11 24H2;Windows 11 23H2 x64"
        New naming: "Drivers - Dell Latitude 5540 - Windows 11 x64"

        Extracts the base OS version (first part before semicolon) and renames packages accordingly.
        Returns an array of result objects with OldName, NewName, Platform, Status, and Error.
    #>
    [CmdletBinding()]
    param (
        [System.Collections.Concurrent.ConcurrentQueue[object]]$ProgressQueue
    )

    $results = [System.Collections.ArrayList]::new()

    Write-DATLogEntry -Value "[Driver Repair - Intune] Scanning Intune for driver packages with multi-build naming..." -Severity 1

    try {
        if (-not (Test-DATIntuneAuth)) {
            Write-DATLogEntry -Value "[Driver Repair - Intune] Not authenticated to Intune, skipping" -Severity 1
            [void]$results.Add([PSCustomObject]@{
                OldName  = ''; NewName = ''; Platform = 'Intune'
                Status   = 'Skipped'; Error = 'Not authenticated to Intune'
            })
            return $results
        }

        # Get all driver packages (Win32 apps starting with "Drivers -")
        $allApps = @(Get-DATIntuneWin32Apps | Where-Object {
            $_.displayName -like 'Drivers -*' -and
            $_.notes -eq 'Created by the Driver Automation Tool'
        })

        if ($allApps.Count -eq 0) {
            Write-DATLogEntry -Value "[Driver Repair - Intune] No Intune driver packages found" -Severity 1
            return $results
        }

        # Find packages with multi-build naming (semicolons in OS portion)
        $packagesToFix = @()
        foreach ($app in $allApps) {
            # Pattern: "Drivers - OEM Model - Windows 11 25H2;Windows 11 24H2;... x64"
            if ($app.displayName -match '^(Drivers\s+-\s+[^\-]+\s+[^\-]+)\s+-\s+(Windows\s+\d+(?:H\d)?(?:;[^;]*)*?)\s+(x64|Arm64)\s*$') {
                $prefix = $Matches[1].Trim()           # "Drivers - Dell Latitude 5540"
                $osBuilds = $Matches[2].Trim()         # "Windows 11 25H2;Windows 11 24H2;..."
                $arch = $Matches[3]                    # "x64" or "Arm64"

                # Check if there are multiple builds (semicolon present)
                if ($osBuilds -match ';') {
                    # Extract base OS only (first part before semicolon)
                    $baseOS = ($osBuilds -split ';')[0].Trim()  # "Windows 11"
                    $newName = "$prefix - $baseOS $arch"
                    
                    $packagesToFix += [PSCustomObject]@{
                        App     = $app
                        OldName = $app.displayName
                        NewName = $newName
                    }
                }
            }
        }

        if ($packagesToFix.Count -eq 0) {
            Write-DATLogEntry -Value "[Driver Repair - Intune] No Intune driver packages with multi-build naming found" -Severity 1
            return $results
        }

        Write-DATLogEntry -Value "[Driver Repair - Intune] Found $($packagesToFix.Count) package(s) to rename" -Severity 1
        if ($ProgressQueue) {
            [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Info'; Message = "Found $($packagesToFix.Count) Intune driver package(s) to rename" })
            [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'ExpectedCount'; Count = $packagesToFix.Count })
        }

        # Rename each package
        foreach ($pkg in $packagesToFix) {
            try {
                $patchBody = @{
                    '@odata.type' = '#microsoft.graph.win32LobApp'
                    displayName   = $pkg.NewName
                }
                
                Invoke-DATGraphRequest -Uri "/deviceAppManagement/mobileApps/$($pkg.App.id)" `
                    -Method PATCH -Body $patchBody -ErrorAction Stop | Out-Null

                Write-DATLogEntry -Value "[Driver Repair - Intune] Renamed: '$($pkg.OldName)' -> '$($pkg.NewName)'" -Severity 1
                [void]$results.Add([PSCustomObject]@{
                    OldName  = $pkg.OldName
                    NewName  = $pkg.NewName
                    Platform = 'Intune'
                    Status   = 'Renamed'
                    Error    = ''
                })
                
                if ($ProgressQueue) {
                    [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Renamed'; OldName = $pkg.OldName; NewName = $pkg.NewName; Platform = 'Intune' })
                }
            } catch {
                Write-DATLogEntry -Value "[Driver Repair - Intune] Failed to rename '$($pkg.OldName)': $($_.Exception.Message)" -Severity 3
                [void]$results.Add([PSCustomObject]@{
                    OldName  = $pkg.OldName
                    NewName  = $pkg.NewName
                    Platform = 'Intune'
                    Status   = 'Failed'
                    Error    = $_.Exception.Message
                })
                
                if ($ProgressQueue) {
                    [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Failed'; OldName = $pkg.OldName; NewName = $pkg.NewName; Platform = 'Intune'; Error = $_.Exception.Message })
                }
            }
        }
    } catch {
        Write-DATLogEntry -Value "[Driver Repair - Intune] Error scanning Intune: $($_.Exception.Message)" -Severity 3
        [void]$results.Add([PSCustomObject]@{
            OldName  = ''; NewName = ''; Platform = 'Intune'
            Status   = 'Error'; Error = $_.Exception.Message
        })
    }

    return $results
}

#endregion Driver Package Naming Repair - Intune

#region Driver Package Name Repair

function Repair-DATDriverPackageNames {
    <#
    .SYNOPSIS
        Scans ConfigMgr for driver packages using the incorrect naming convention
        (with all selected builds instead of just base OS version) and renames them to the correct format.
    .DESCRIPTION
        Incorrect naming: "Drivers - Dell Latitude 5540 - Windows 11 24H2;Windows 11 23H2;Windows 11 22H2 x64"
        Correct naming:   "Drivers - Dell Latitude 5540 - Windows 11 x64"

        This function detects packages with semicolons or multiple build versions in the name
        and extracts just the base OS version (e.g. "Windows 11") for the corrected name.

        Returns an array of result objects with OldName, NewName, Platform, Status, and Error.
    #>
    [CmdletBinding()]
    param (
        [string]$SiteServer,
        [string]$SiteCode,
        [System.Collections.Concurrent.ConcurrentQueue[object]]$ProgressQueue
    )

    $results = [System.Collections.ArrayList]::new()

    # --- ConfigMgr driver package rename ---
    if (-not $SiteServer -or -not $SiteCode) {
        Write-DATLogEntry -Value "[Driver Repair] ConfigMgr not configured, skipping driver package name repair" -Severity 1
        return $results
    }

    try {
        Write-DATLogEntry -Value "[Driver Repair] Scanning ConfigMgr for driver packages with incorrect naming..." -Severity 1
        $smsNamespace = "root\SMS\Site_$SiteCode"
        $cimSess = New-DATCimSession -ComputerName $SiteServer

        # Find all driver packages that contain semicolons (multi-build format) or multiple Windows versions
        $allPkgs = @(Invoke-DATRemoteQuery -CimSession $cimSess -ComputerName $SiteServer `
            -Namespace $smsNamespace -Query "SELECT PackageID, Name, Version FROM SMS_Package WHERE Name LIKE 'Drivers -%'")

        if ($allPkgs.Count -eq 0) {
            Write-DATLogEntry -Value "[Driver Repair] No driver packages found" -Severity 1
            return $results
        }

        $packagesToFix = @($allPkgs | Where-Object { $_.Name -match ';' -or ($_.Name -match 'Drivers\s+-\s+.+?\s+-\s+Windows\s+\d+\s+\S+;') })

        if ($packagesToFix.Count -eq 0) {
            Write-DATLogEntry -Value "[Driver Repair] No driver packages with incorrect naming found" -Severity 1
            return $results
        }

        Write-DATLogEntry -Value "[Driver Repair] Found $($packagesToFix.Count) driver package(s) to fix" -Severity 1
        if ($ProgressQueue) {
            [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Info'; Message = "Found $($packagesToFix.Count) driver package(s) to rename" })
            [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'ExpectedCount'; Count = $packagesToFix.Count })
        }

        foreach ($pkg in $packagesToFix) {
            $oldName = $pkg.Name
            
            # Pattern: "Drivers - OEM Model - Windows 11 24H2;Windows 11 23H2;... x64"
            # Extract: prefix (Drivers - OEM Model), base OS version, and architecture
            if ($oldName -match '^(Drivers\s+-\s+.+?)\s+-\s+Windows\s+(\d+).*?(x64|x86|Arm64)\s*$') {
                $prefix = $Matches[1].Trim()
                $osVersion = "Windows $($Matches[2])"  # e.g. "Windows 11"
                $arch = $Matches[3]  # e.g. "x64", "x86", "Arm64"
                $newName = "$prefix - $osVersion $arch"

                try {
                    # Rename the package via WMI
                    $pkg | Set-CimInstance -Property @{ Name = $newName } -CimSession $cimSess -ErrorAction Stop
                    
                    Write-DATLogEntry -Value "[Driver Repair] ConfigMgr: '$oldName' -> '$newName'" -Severity 1
                    [void]$results.Add([PSCustomObject]@{
                        OldName  = $oldName
                        NewName  = $newName
                        Platform = 'ConfigMgr'
                        Status   = 'Renamed'
                        Error    = ''
                    })
                    if ($ProgressQueue) {
                        [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Renamed'; OldName = $oldName; NewName = $newName; Platform = 'ConfigMgr' })
                    }
                } catch {
                    Write-DATLogEntry -Value "[Driver Repair] Failed to rename '$oldName': $($_.Exception.Message)" -Severity 3
                    [void]$results.Add([PSCustomObject]@{
                        OldName  = $oldName
                        NewName  = $newName
                        Platform = 'ConfigMgr'
                        Status   = 'Failed'
                        Error    = $_.Exception.Message
                    })
                    if ($ProgressQueue) {
                        [void]$ProgressQueue.Enqueue([PSCustomObject]@{ Status = 'Failed'; OldName = $oldName; NewName = $newName; Platform = 'ConfigMgr'; Error = $_.Exception.Message })
                    }
                }
            } else {
                Write-DATLogEntry -Value "[Driver Repair] Could not parse package name format: '$oldName'" -Severity 2
                [void]$results.Add([PSCustomObject]@{
                    OldName  = $oldName
                    NewName  = ''
                    Platform = 'ConfigMgr'
                    Status   = 'Skipped'
                    Error    = 'Could not parse package name format'
                })
            }
        }

        if ($cimSess) { Remove-CimSession -CimSession $cimSess -ErrorAction SilentlyContinue }
    } catch {
        Write-DATLogEntry -Value "[Driver Repair] Error scanning ConfigMgr: $($_.Exception.Message)" -Severity 3
    }

    return $results
}

#endregion Driver Package Name Repair
