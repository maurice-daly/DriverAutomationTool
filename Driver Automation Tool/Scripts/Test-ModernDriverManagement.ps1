<#
.SYNOPSIS
    Test harness for the Modern Driver Management and Modern BIOS Management scripts.

.DESCRIPTION
    Exercises Invoke-CMApplyDriverPackage.ps1 and Invoke-CMDownloadBIOSPackage.ps1 against a
    make / model / baseboard (SystemSKU) combination that you specify, using both package
    sources:

      * AdminService  - the scripts are run in their native -DebugMode against a live
                        ConfigMgr AdminService endpoint.
      * XML Package   - the scripts are run in XMLPackage mode against a DriverPackages.xml
                        logic file, with a simulated task sequence environment.

    The harness runs in full Windows or in WinPE. It reports:

      * Environment prerequisites  - PowerShell version, WinPE detection, elevation, script
                                     presence and syntax, TLS, log paths, endpoint reachability.
      * Task sequence variables    - every variable each script reads or writes for the
                                     selected deployment mode, and whether it is present.
      * Detection                  - what the script derives for manufacturer, model and
                                     SystemSKU from the (simulated) hardware.
      * Matching                   - whether a driver / BIOS package matched the specified
                                     make, model and target OS, and which package was selected.
      * Errors                     - every severity 2 (warning) and severity 3 (error) entry
                                     written by the scripts, plus harness-level findings.

    The target scripts are never modified. They are launched in a child PowerShell process
    with a shimmed Microsoft.SMS.TSEnvironment COM object and shimmed WMI/CIM calls, so any
    make/model can be tested from any machine.

    NOTE: XMLPackage mode is not a debug mode. After the matching phase the driver script
    proceeds to the content download phase, which requires OSDDownloadContent.exe and a live
    task sequence. The harness evaluates everything up to and including package validation and
    reports the download/install phase as "not evaluated".

.PARAMETER Manufacturer
    Computer manufacturer (make) to test. Prompted for when omitted.

.PARAMETER ComputerModel
    Computer model to test, e.g. 'Latitude 7440'. Prompted for when omitted.

.PARAMETER SystemSKU
    Baseboard / SystemSKU value to test, e.g. '0B0C' (Dell), '8A78' (HP), '21F6' (Lenovo
    machine type). Prompted for when omitted.

.PARAMETER TargetOSName
    Target operating system name, 'Windows 10' or 'Windows 11'.

.PARAMETER TargetOSVersion
    Target operating system version, e.g. '24H2'. Accepts the same releases as
    Invoke-CMApplyDriverPackage.ps1, up to and including '26H2'.

.PARAMETER TargetOSArchitecture
    Target operating system architecture, 'x64', 'x86' or 'Arm64'.

.PARAMETER Endpoint
    Internal FQDN of the server hosting the AdminService, e.g. CM01.domain.local.

.PARAMETER UserName
    Service account user name used to authenticate against the AdminService.

.PARAMETER Password
    Service account password used to authenticate against the AdminService.

.PARAMETER CertificateThumbprint
    Expected SHA1 thumbprint of the AdminService certificate, passed to both scripts' own
    -CertificateThumbprint parameter. Only needed when that certificate does not chain to a root
    this machine trusts -- typically in WinPE, where the boot image lacks the issuing CA, or with
    a ConfigMgr self-signed binding. The scripts refuse an untrusted AdminService certificate
    unless it is pinned this way, and in -DebugMode they do not read the task sequence variable.

    When omitted, the harness uses the MDMCertificateThumbprint variable from a live task
    sequence, if it is running inside one. Interactively, it offers to pin the certificate the
    endpoint presents -- check the thumbprint against the server before accepting.

.PARAMETER XMLPackagePath
    Path to the DriverPackages.xml logic file, or to the folder containing it.

.PARAMETER Scope
    Which package sources to test: All, AdminService or XMLPackage.

.PARAMETER Component
    Which scripts to test: All, Drivers or BIOS.

.PARAMETER OutputPath
    Folder to write the run artefacts (per-test logs, report) into. Defaults to a
    timestamped folder under the temp directory. In a task sequence, pass the _SMSTSLogPath
    folder to keep the report with smsts.log.

.PARAMETER UseLocalHardware
    Do not simulate hardware. Let the scripts read real WMI from the machine the harness is
    running on. The make/model/SKU values are still passed as -DebugMode overrides.

.PARAMETER CurrentBIOSVersion
    Simulated value for Win32_BIOS SMBIOSBIOSVersion, used by the BIOS version comparison.

.PARAMETER CurrentBIOSReleaseDate
    Simulated BIOS release date as yyyyMMdd, used by the Lenovo BIOS date comparison.

.PARAMETER NoPatchBIOSXml
    Do not generate a patched copy of Invoke-CMDownloadBIOSPackage.ps1 for the XMLPackage
    test. See the notes below.

.PARAMETER NonInteractive
    Never prompt. Any value not supplied on the command line is treated as unspecified and
    the affected tests are skipped.

.PARAMETER ShowFullLog
    Print every line each target script logged, coloured by severity, plus its stdout and
    stderr, instead of the trimmed summary (25 matching lines, 10 warnings). Use it to follow
    package matching decision by decision on the console.

    Pair it with the common -Verbose parameter to also see what the harness itself does: the
    parameters and task sequence variables passed to each script (passwords masked), the
    simulated hardware, and where every artefact is written.

    Everything shown on the console, verbose output included, is also written to Harness.log
    in the run folder, so the detail survives a WinPE console with no scrollback.

.EXAMPLE
    # Fully interactive - prompts for make, model, baseboard and everything else
    .\Test-ModernDriverManagement.ps1

.EXAMPLE
    # Test a Dell Latitude 7440 against both the AdminService and the XML logic file
    .\Test-ModernDriverManagement.ps1 -Manufacturer Dell -ComputerModel "Latitude 7440" -SystemSKU "0B0C" `
        -TargetOSName "Windows 11" -TargetOSVersion "24H2" -Endpoint "CM01.domain.local" `
        -UserName "DOMAIN\svc_cm" -Password "P@ssw0rd" -XMLPackagePath "C:\Temp\XMLPackage"

.EXAMPLE
    # WinPE, XML logic file only, no AdminService
    .\Test-ModernDriverManagement.ps1 -Manufacturer HP -ComputerModel "EliteBook 840 G10" -SystemSKU "8A78" `
        -TargetOSName "Windows 11" -TargetOSVersion "24H2" -Scope XMLPackage -XMLPackagePath "X:\XMLPackage"

.EXAMPLE
    # WinPE, full matching detail: every log line from both scripts plus the harness's own steps
    .\Test-ModernDriverManagement.ps1 -Manufacturer Lenovo -ComputerModel "ThinkPad T14 Gen 5" -SystemSKU "21ML" `
        -TargetOSName "Windows 11" -TargetOSVersion "26H2" -Scope XMLPackage -XMLPackagePath "X:\XMLPackage" `
        -ShowFullLog -Verbose

.NOTES
    FileName: Test-ModernDriverManagement.ps1
    Author:   Maurice Daly
    Requires: PowerShell 5.1 or later (Windows PowerShell or PowerShell 7). Runs in WinPE.

    Script location:
      Invoke-CMApplyDriverPackage.ps1 and Invoke-CMDownloadBIOSPackage.ps1 are always taken from
      the harness's own folder, so copy all three into the same folder (the tool's Scripts folder
      already has them together). A test therefore always covers the copies it was packaged with.

    BIOS XMLPackage support:
      Invoke-CMDownloadBIOSPackage.ps1 declares an -XMLPackage switch, so the harness runs the
      shipped script in XMLPackage mode. Older copies of the script (before the switch was added)
      had XMLPackage code paths that could never execute; when one of those sits beside the
      harness, it runs a patched *copy* from the run folder with the parameter set added, and
      reports that as a WARN. The original is never touched. Use -NoPatchBIOSXml to skip that
      test instead.
#>
[CmdletBinding()]
param (
    [ValidateSet("HP", "Hewlett-Packard", "Dell", "Lenovo", "Microsoft", "Fujitsu", "Panasonic", "Viglen", "AZW", "Getac", "Intel", "ByteSpeed", "ASUS")]
    [string]$Manufacturer,

    [string]$ComputerModel,

    [string]$SystemSKU,

    [ValidateSet("Windows 11", "Windows 10")]
    [string]$TargetOSName,

    [ValidateSet("26H2", "26H1", "25H2", "24H2", "23H2", "22H2", "21H2", "21H1", "20H2", "2004", "1909", "1903", "1809", "1803", "1709", "1703", "1607")]
    [string]$TargetOSVersion,

    [ValidateSet("x64", "x86", "Arm64")]
    [string]$TargetOSArchitecture = "x64",

    [string]$Endpoint,

    [string]$UserName,

    [string]$Password,

    [string]$CertificateThumbprint,

    [string]$XMLPackagePath,

    [ValidateSet("All", "AdminService", "XMLPackage")]
    [string]$Scope = "All",

    [ValidateSet("All", "Drivers", "BIOS")]
    [string]$Component = "All",

    [ValidateSet("Production", "Pilot")]
    [string]$OperationalMode = "Production",

    [ValidateSet("BareMetal", "OSUpdate", "DriverUpdate", "PreCache")]
    [string]$XMLDeploymentType = "BareMetal",

    [string]$DriverFilter = "Drivers",

    [string]$BIOSFilter = "BIOS",

    [string]$OutputPath,

    [string]$CurrentBIOSVersion,

    [string]$CurrentBIOSReleaseDate,

    [switch]$UseLocalHardware,

    [switch]$NoPatchBIOSXml,

    [switch]$NonInteractive,

    [switch]$ShowFullLog
)

#region ---------------------------------------------------------------- Output helpers

$Script:Results = New-Object -TypeName System.Collections.ArrayList
$Script:Findings = New-Object -TypeName System.Collections.ArrayList
$Script:CurrentPhase = "General"
$Script:DriverAnalysis = $null
$Script:BIOSAnalysis = $null
# Package name / description lookups for the matched packages (Get-PackageDetail)
$Script:XmlPackageCatalog = @()
$Script:AdminServiceCredential = $null
$Script:PackageDetailCache = @{}
# One row per matched package (or per run with no match) for the Summary table
$Script:MatchedPackages = New-Object -TypeName System.Collections.ArrayList

function Write-Banner {
    param ([string]$Text)
    $Line = "=" * 78
    Write-Host ""
    Write-Host $Line -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host $Line -ForegroundColor Cyan
}

function Write-Section {
    param ([string]$Text)
    Write-Host ""
    Write-Host ("-- {0} {1}" -f $Text, ("-" * [Math]::Max(3, (74 - $Text.Length)))) -ForegroundColor White
    $Script:CurrentPhase = $Text
}

function Add-TestResult {
    <#
        Records and prints a single check. Status is one of PASS, FAIL, WARN, INFO or SKIP.
    #>
    param (
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet("PASS", "FAIL", "WARN", "INFO", "SKIP")][string]$Status,
        [string]$Detail = "",
        [string]$Phase
    )
    if ([string]::IsNullOrEmpty($Phase)) { $Phase = $Script:CurrentPhase }

    $null = $Script:Results.Add([PSCustomObject]@{
            Phase  = $Phase
            Name   = $Name
            Status = $Status
            Detail = $Detail
        })

    switch ($Status) {
        "PASS" { $Colour = "Green" }
        "FAIL" { $Colour = "Red" }
        "WARN" { $Colour = "Yellow" }
        "SKIP" { $Colour = "DarkGray" }
        default { $Colour = "Gray" }
    }

    $Label = "[{0}]" -f $Status
    if (-not [string]::IsNullOrEmpty($Detail)) {
        Write-Host ("  {0,-6} {1} : {2}" -f $Label, $Name, $Detail) -ForegroundColor $Colour
    }
    else {
        Write-Host ("  {0,-6} {1}" -f $Label, $Name) -ForegroundColor $Colour
    }
}

function Add-Finding {
    <#
        Records a notable problem for the summary. Severity is Error or Warning.
    #>
    param (
        [Parameter(Mandatory = $true)][ValidateSet("Error", "Warning")][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Source = ""
    )
    $null = $Script:Findings.Add([PSCustomObject]@{
            Severity = $Severity
            Source   = $Source
            Message  = $Message
        })
}

function Write-Detail {
    param ([string]$Text, [string]$Colour = "Gray")
    Write-Host ("         {0}" -f $Text) -ForegroundColor $Colour
}

function Write-HashtableVerbose {
    <#
        Writes each key of a hashtable as a verbose line, masking anything that looks like a
        secret so that -Verbose output and Harness.log never carry the service account password.
    #>
    param ([string]$Title, [hashtable]$Table)
    if ($null -eq $Table -or $Table.Count -eq 0) {
        Write-Verbose ("{0}: (none)" -f $Title)
        return
    }
    Write-Verbose ("{0}:" -f $Title)
    foreach ($Key in ($Table.Keys | Sort-Object)) {
        $Value = $Table[$Key]
        if ($Key -match "Password|Secret|Token") { $Value = "********" }
        elseif ($Value -is [hashtable]) { $Value = "@{ " + ((@($Value.Keys | Sort-Object) | ForEach-Object { "{0} = {1}" -f $_, $Value[$_] }) -join "; ") + " }" }
        Write-Verbose ("    {0} = {1}" -f $Key, $Value)
    }
}

function Show-FullLog {
    <#
        -ShowFullLog: prints every entry a target script logged, coloured by CMTrace severity,
        followed by its stdout and stderr.
    #>
    param ([Parameter(Mandatory = $true)][PSCustomObject]$Run)

    Write-Detail ("Full log for {0} ({1} entries, {2}):" -f $Run.TestName, $Run.Entries.Count, $Run.LogPath) "Cyan"
    foreach ($Entry in $Run.Entries) {
        switch ($Entry.Severity) {
            3 { $Colour = "Red"; $Tag = "ERR " }
            2 { $Colour = "Yellow"; $Tag = "WARN" }
            default { $Colour = "Gray"; $Tag = "INFO" }
        }
        # CMTrace stores the time as HH:mm:ss.fff followed by the UTC bias; show just the clock time
        $Time = [string]$Entry.Time
        if ($Time.Length -gt 12) { $Time = $Time.Substring(0, 12) }
        Write-Detail ("  {0} {1} {2}" -f $Time, $Tag, $Entry.Message) $Colour
    }
    foreach ($Stream in @(@{ Name = "stdout"; Text = $Run.StdOut; Colour = "DarkGray" }, @{ Name = "stderr"; Text = $Run.StdErr; Colour = "Red" })) {
        $Lines = @($Stream.Text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($Lines.Count -eq 0) { continue }
        Write-Detail ("{0} ({1} lines):" -f $Stream.Name, $Lines.Count) "Cyan"
        foreach ($Line in $Lines) { Write-Detail ("  {0}" -f $Line) $Stream.Colour }
    }
}

function Stop-HarnessTranscript {
    if ($Script:TranscriptStarted) {
        try { $null = Stop-Transcript } catch { }
        $Script:TranscriptStarted = $false
    }
}

#endregion

#region ---------------------------------------------------------------- Prompt helpers

function Read-Choice {
    param (
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string[]]$Options,
        [string]$Default
    )
    Write-Host ""
    Write-Host $Title -ForegroundColor White
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("   {0,2}. {1}" -f ($i + 1), $Options[$i])
    }
    while ($true) {
        $Suffix = ""
        if (-not [string]::IsNullOrEmpty($Default)) { $Suffix = " [default: $Default]" }
        $Answer = Read-Host -Prompt ("Select 1-{0}{1}" -f $Options.Count, $Suffix)
        if ([string]::IsNullOrWhiteSpace($Answer) -and (-not [string]::IsNullOrEmpty($Default))) { return $Default }
        $Index = 0
        if ([int]::TryParse($Answer, [ref]$Index)) {
            if (($Index -ge 1) -and ($Index -le $Options.Count)) { return $Options[$Index - 1] }
        }
        # Allow the value itself to be typed
        $Direct = $Options | Where-Object { $_ -eq $Answer }
        if ($Direct) { return $Direct }
        Write-Host "   Invalid selection, try again." -ForegroundColor Yellow
    }
}

function Read-Value {
    param (
        [Parameter(Mandatory = $true)][string]$Prompt,
        [string]$Default,
        [switch]$AllowEmpty
    )
    while ($true) {
        $Suffix = ""
        if (-not [string]::IsNullOrEmpty($Default)) { $Suffix = " [default: $Default]" }
        $Answer = Read-Host -Prompt ("{0}{1}" -f $Prompt, $Suffix)
        if ([string]::IsNullOrWhiteSpace($Answer)) {
            if (-not [string]::IsNullOrEmpty($Default)) { return $Default }
            if ($AllowEmpty) { return "" }
            Write-Host "   A value is required." -ForegroundColor Yellow
            continue
        }
        return $Answer.Trim()
    }
}

#endregion

#region ---------------------------------------------------------------- Environment

function Test-WinPE {
    if (Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT") { return $true }
    if (Test-Path -Path "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\MiniNT") { return $true }
    if ($env:SystemDrive -eq "X:") { return $true }
    return $false
}

function Test-Elevated {
    try {
        $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
        return $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-PowerShellHostPath {
    <#
        Returns the executable used to launch the target scripts. Windows PowerShell 5.1 is
        preferred because that is what a ConfigMgr task sequence uses; fall back to the host
        that is running the harness (WinPE images may only carry one of them).
    #>
    $Candidates = @(
        (Join-Path -Path $env:SystemRoot -ChildPath "System32\WindowsPowerShell\v1.0\powershell.exe"),
        (Join-Path -Path $env:SystemRoot -ChildPath "SysWOW64\WindowsPowerShell\v1.0\powershell.exe")
    )
    foreach ($Candidate in $Candidates) {
        if (Test-Path -Path $Candidate) { return $Candidate }
    }
    return [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
}

function Test-TcpPort {
    param ([string]$ComputerName, [int]$Port = 443, [int]$TimeoutMilliseconds = 5000)
    $Client = New-Object System.Net.Sockets.TcpClient
    try {
        $Async = $Client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $Async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) { return $false }
        $Client.EndConnect($Async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $Client.Close()
    }
}

function Get-EndpointCertificate {
    <#
        Opens a TLS connection to the endpoint, sends nothing over it, and returns the certificate
        presented with the outcome of normal validation on this machine. This is the check the
        target scripts make before they send the service account credential, so it explains why
        they refuse an endpoint and which thumbprint would pin it.
    #>
    param ([string]$ComputerName, [int]$Port = 443, [int]$TimeoutMs = 5000)

    $Result = [PSCustomObject]@{ Certificate = $null; PolicyErrors = $null; ChainStatus = @(); Error = $null }
    $Captured = @{}
    $Client = New-Object -TypeName System.Net.Sockets.TcpClient
    try {
        $Connect = $Client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $Connect.AsyncWaitHandle.WaitOne($TimeoutMs)) { throw ("timed out connecting to port {0}" -f $Port) }
        $Client.EndConnect($Connect)
        $Callback = [System.Net.Security.RemoteCertificateValidationCallback] {
            param ($Source, $Certificate, $Chain, $Errors)
            $Captured.Certificate = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $Certificate
            $Captured.Errors = $Errors
            $Captured.ChainStatus = @($Chain.ChainStatus | ForEach-Object { $_.StatusInformation.Trim() } | Where-Object { $_ })
            # Inspection only: accept so the handshake completes, then close without sending anything
            return $true
        }
        $Ssl = New-Object -TypeName System.Net.Security.SslStream -ArgumentList @($Client.GetStream(), $false, $Callback)
        try {
            $Ssl.AuthenticateAsClient($ComputerName, $null, [System.Security.Authentication.SslProtocols]::Tls12, $false)
        }
        finally {
            $Ssl.Dispose()
        }
        $Result.Certificate = $Captured.Certificate
        $Result.PolicyErrors = $Captured.Errors
        $Result.ChainStatus = $Captured.ChainStatus
    }
    catch {
        $Result.Error = $_.Exception.Message
        if ($_.Exception.InnerException) { $Result.Error = $_.Exception.InnerException.Message }
    }
    finally {
        $Client.Close()
    }
    return $Result
}

function ConvertTo-Thumbprint {
    # Same normalisation as the target scripts: thumbprints copied from the certificate UI carry
    # spaces and an invisible leading mark
    param ([string]$Value)
    return ([string]$Value -replace '[^0-9A-Fa-f]', '').ToUpper()
}

function Add-CertificateThumbprintParameter {
    # Passes -CertificateThumbprint to a target script when one is set and the script declares it
    # (scripts from before certificate pinning do not, and would reject the parameter)
    param ([hashtable]$Parameters, [PSCustomObject]$Analysis, [string]$ScriptName)
    if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) { return }
    if (($null -ne $Analysis) -and $Analysis.Parameters.ContainsKey("CertificateThumbprint")) {
        $Parameters["CertificateThumbprint"] = ConvertTo-Thumbprint $CertificateThumbprint
    }
    else {
        Add-TestResult -Name ("{0} -CertificateThumbprint" -f $ScriptName) -Status "WARN" -Detail "the script declares no such parameter - the thumbprint is not passed"
    }
}

function Get-ScriptUserNameCandidate {
    <#
        Returns the user name formats the driver script will try against the AdminService, in its
        order, by running the script's own Get-AuthUserNameCandidate / Get-AuthDomainName. Lifting
        them out of the script keeps the pre-flight probe in step with what the script does.
        Falls back to the configured name alone when the script predates the retry logic.
    #>
    param ([string]$Path, [string]$UserName, [string]$Endpoint, $TSEnvironment)
    try {
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $Names = @("Get-AuthUserNameCandidate", "Get-AuthDomainName")
        $Definitions = @($Ast.FindAll({
                    param ($Node)
                    $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Names -contains $Node.Name
                }.GetNewClosure(), $true))
        if ($Definitions.Count -ne $Names.Count) { return @($UserName) }
        # A throwaway module gives the functions their own $Script: scope, as they have in the script
        $Code = "param (`$Endpoint, `$TSEnvironment)`nExport-ModuleMember`n`$Script:Endpoint = `$Endpoint`n`$Script:TSEnvironment = `$TSEnvironment`n" +
            (($Definitions | ForEach-Object { $_.Extent.Text }) -join "`n")
        $Module = New-Module -ScriptBlock ([scriptblock]::Create($Code)) -ArgumentList $Endpoint, $TSEnvironment
        $Candidates = @(& $Module { param ($Name) Get-AuthUserNameCandidate -UserName $Name } $UserName | Where-Object { $_ })
        if ($Candidates.Count -eq 0) { return @($UserName) }
        return $Candidates
    }
    catch {
        Write-Verbose ("Could not load the script's user name candidates: {0}" -f $_.Exception.Message)
        return @($UserName)
    }
}

function Get-HttpStatusCode {
    # Status code of a failed web request on either engine, or 0 when there was no HTTP response
    param ($ErrorRecord)
    try {
        $Response = $ErrorRecord.Exception.Response
        if (($null -ne $Response) -and ($null -ne $Response.StatusCode)) { return [int]$Response.StatusCode }
    }
    catch { }
    return 0
}

function Set-ProbeCertificateValidation {
    <#
        The harness pre-flight authentication probe tests the credentials only; certificate trust
        is reported separately (Get-EndpointCertificate) because the target scripts enforce it.
        So the probe accepts a certificate that validates normally, or the one certificate the
        harness just inspected -- never anything else that might answer for the endpoint.

        Windows PowerShell only: the callback is compiled C#, because a scriptblock callback runs
        on a worker thread with no runspace and fails every HTTPS request ("There is no Runspace
        available..."). PowerShell 7 uses -SkipCertificateCheck on the request instead.
    #>
    param ([string]$Thumbprint)
    if ($PSVersionTable.PSVersion.Major -ge 6) { return $true }

    # Windows PowerShell does not offer TLS 1.2 by default, which the AdminService requires
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    try {
        if (-not ("DATHarnessProbeValidation" -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
public static class DATHarnessProbeValidation
{
    public static string ExpectedThumbprint = String.Empty;
    public static void Enable(string thumbprint)
    {
        ExpectedThumbprint = thumbprint ?? String.Empty;
        ServicePointManager.ServerCertificateValidationCallback =
            delegate(Object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors errors)
            {
                if (errors == SslPolicyErrors.None) { return true; }
                if (certificate == null || ExpectedThumbprint.Length == 0) { return false; }
                return String.Equals(certificate.GetCertHashString(), ExpectedThumbprint, StringComparison.OrdinalIgnoreCase);
            };
    }
}
'@
        }
        [DATHarnessProbeValidation]::Enable($Thumbprint)
        return $true
    }
    catch {
        # No C# compiler (a stripped WinPE image): the probe then succeeds only against a trusted certificate
        Write-Verbose ("Probe certificate callback unavailable: {0}" -f $_.Exception.Message)
        return $false
    }
}

#endregion

#region ---------------------------------------------------------------- Device profile

function New-DeviceProfile {
    <#
        Builds the synthetic WMI/CIM data that the target scripts will read, laid out so each
        manufacturer branch of Get-ComputerData resolves to the requested make/model/SKU using
        the same property that real hardware would supply.
    #>
    param (
        [Parameter(Mandatory = $true)][string]$Manufacturer,
        [string]$Model,
        [string]$SystemSKU,
        [string]$BIOSVersion,
        [string]$BIOSReleaseDate
    )

    # Value reported by Win32_ComputerSystem.Manufacturer on real hardware. Get-ComputerData
    # switches on this with wildcards, so it must contain the vendor token.
    switch ($Manufacturer) {
        "Dell" { $WmiManufacturer = "Dell Inc." }
        "HP" { $WmiManufacturer = "HP" }
        "Hewlett-Packard" { $WmiManufacturer = "Hewlett-Packard" }
        "Lenovo" { $WmiManufacturer = "LENOVO" }
        "Microsoft" { $WmiManufacturer = "Microsoft Corporation" }
        "Fujitsu" { $WmiManufacturer = "FUJITSU" }
        "Panasonic" { $WmiManufacturer = "Panasonic Corporation" }
        "Viglen" { $WmiManufacturer = "Viglen" }
        "AZW" { $WmiManufacturer = "AZW" }
        "Getac" { $WmiManufacturer = "Getac" }
        "Intel" { $WmiManufacturer = "Intel Corporation" }
        "ByteSpeed" { $WmiManufacturer = "ByteSpeed LLC" }
        "ASUS" { $WmiManufacturer = "ASUSTeK COMPUTER INC." }
        default { $WmiManufacturer = $Manufacturer }
    }

    # Win32_ComputerSystem.Model. For Lenovo this is the machine type code, not the friendly
    # name - Get-ComputerData takes SubString(0,4) of it as the SystemSKU.
    $ComputerSystemModel = $Model
    $ComputerSystemProductVersion = $Model
    if ($Manufacturer -eq "Lenovo") {
        $MachineType = $SystemSKU
        if ([string]::IsNullOrEmpty($MachineType)) { $MachineType = "0000" }
        if ($MachineType.Length -lt 4) { $MachineType = $MachineType.PadRight(4, "0") }
        $ComputerSystemModel = $MachineType + "CTO1WW"
    }

    if ([string]::IsNullOrEmpty($ComputerSystemModel)) { $ComputerSystemModel = "Unknown Model" }
    if ([string]::IsNullOrEmpty($ComputerSystemProductVersion)) { $ComputerSystemProductVersion = $ComputerSystemModel }

    if ([string]::IsNullOrEmpty($BIOSVersion)) {
        switch ($Manufacturer) {
            "HP" { $BIOSVersion = "1.00" }
            "Hewlett-Packard" { $BIOSVersion = "1.00" }
            default { $BIOSVersion = "1.0.0" }
        }
    }
    if ([string]::IsNullOrEmpty($BIOSReleaseDate)) { $BIOSReleaseDate = "20200101" }
    $DmtfReleaseDate = "{0}000000.000000+000" -f $BIOSReleaseDate

    # Dell reads the fallback SKU out of the bracketed OEM string
    $OemStrings = @("Dell System", "1[$SystemSKU]", "3[1.0]", "12[www.dell.com]")

    return @{
        Win32_ComputerSystem        = @{
            Manufacturer    = $WmiManufacturer
            Model           = $ComputerSystemModel
            OEMStringArray  = $OemStrings
            SystemSKUNumber = $SystemSKU
        }
        Win32_ComputerSystemProduct = @{
            Name              = $ComputerSystemProductVersion
            Version           = $ComputerSystemProductVersion
            IdentifyingNumber = "SIMULATED"
        }
        Win32_BaseBoard             = @{
            SKU          = $SystemSKU
            Product      = $SystemSKU
            Manufacturer = $WmiManufacturer
        }
        MS_SystemInformation        = @{
            # Dell reads SystemSku; HP / Panasonic / AZW / Getac / ByteSpeed read BaseBoardProduct;
            # Microsoft reads SystemSKU. All are populated with the supplied value.
            SystemSKU        = $SystemSKU
            BaseBoardProduct = $SystemSKU
        }
        Win32_BIOS                  = @{
            SMBIOSBIOSVersion      = $BIOSVersion
            ReleaseDate            = $DmtfReleaseDate
            SystemBiosMajorVersion = 1
            SystemBiosMinorVersion = 0
            Manufacturer           = $WmiManufacturer
            Version                = $BIOSVersion
        }
        Win32_OperatingSystem       = @{
            OSArchitecture = "64-bit"
            Version        = "10.0.26100"
            Caption        = "Simulated"
        }
    }
}

function Get-ExpectedDetection {
    <#
        Mirrors the manufacturer switch in Get-ComputerData so the harness can state up front
        what the scripts should derive from the simulated hardware, and flag any transform
        (such as the Lenovo 4-character truncation) that changes the value the user supplied.
    #>
    param (
        [Parameter(Mandatory = $true)][string]$Manufacturer,
        [string]$Model,
        [string]$SystemSKU
    )

    $Expected = [PSCustomObject]@{
        Manufacturer = $Manufacturer
        Model        = $Model
        SystemSKU    = $SystemSKU
        SKUSource    = "MS_SystemInformation.BaseBoardProduct"
        Notes        = @()
    }

    switch ($Manufacturer) {
        "Dell" { $Expected.SKUSource = "MS_SystemInformation.SystemSku" }
        "Microsoft" { $Expected.SKUSource = "MS_SystemInformation.SystemSKU" }
        "Lenovo" {
            $Expected.SKUSource = "Win32_ComputerSystem.Model (first 4 characters)"
            $Truncated = $SystemSKU
            if (-not [string]::IsNullOrEmpty($Truncated)) {
                if ($Truncated.Length -lt 4) { $Truncated = $Truncated.PadRight(4, "0") }
                $Truncated = $Truncated.Substring(0, 4)
            }
            if ($Truncated -ne $SystemSKU) {
                $Expected.Notes += "Lenovo SystemSKU is the 4-character machine type; '$SystemSKU' resolves to '$Truncated'."
            }
            $Expected.SystemSKU = $Truncated
        }
        "Panasonic" {
            $Expected.Manufacturer = "Panasonic Corporation"
            $Expected.Notes += "Get-ComputerData normalises Panasonic to 'Panasonic Corporation'; driver packages must carry that manufacturer value."
        }
        "Viglen" { $Expected.SKUSource = "Win32_BaseBoard.SKU" }
        "Fujitsu" { $Expected.SKUSource = "Win32_BaseBoard.SKU" }
        "Hewlett-Packard" {
            $Expected.Manufacturer = "HP"
            $Expected.Notes += "Get-ComputerData normalises Hewlett-Packard to 'HP'."
        }
        "ASUS" {
            $Expected.SystemSKU = ""
            $Expected.SKUSource = "not collected"
            $Expected.Notes += "Get-ComputerData does not collect a SystemSKU for ASUS; matching falls back to the computer model."
        }
        "Intel" {
            $Expected.SystemSKU = ""
            $Expected.SKUSource = "not collected"
            $Expected.Notes += "Get-ComputerData does not collect a SystemSKU for Intel; matching falls back to the computer model."
        }
        "ByteSpeed" {
            $Expected.SystemSKU = ""
            $Expected.SKUSource = "not collected"
            $Expected.Notes += "ByteSpeed models containing 'NUC' are re-detected as manufacturer 'Intel' using MS_SystemInformation.BaseBoardProduct as the model."
        }
    }

    return $Expected
}

#endregion

#region ---------------------------------------------------------------- Shim bootstrap

$Script:BootstrapSource = @'
<#
    Generated by Test-ModernDriverManagement.ps1 - do not edit.

    Provides a simulated Microsoft.SMS.TSEnvironment COM object and simulated WMI/CIM data,
    then invokes the target Modern Driver / BIOS Management script unmodified.
#>
param (
    [Parameter(Mandatory = $true)][string]$ContextPath
)

$ErrorActionPreference = "Continue"

# When the harness runs under PowerShell 7 and launches Windows PowerShell 5.1, the inherited
# PSModulePath points at PowerShell 7's module directories first. Windows PowerShell then fails
# to autoload its own core modules (ConvertTo-SecureString and friends). Drop the PowerShell 7
# entries and make sure this host's own module directory is present.
$ModulePaths = @($env:PSModulePath -split ";" | Where-Object {
        (-not [string]::IsNullOrWhiteSpace($_)) -and ($_ -notmatch "\\PowerShell\\7")
    })
$HostModulePath = Join-Path -Path $PSHOME -ChildPath "Modules"
if ($ModulePaths -notcontains $HostModulePath) { $ModulePaths = @($HostModulePath) + $ModulePaths }
$env:PSModulePath = ($ModulePaths | Select-Object -Unique) -join ";"

$Context = Import-Clixml -Path $ContextPath

# ------------------------------------------------------------------ TS environment shim
$TypeSource = @"
using System;
using System.IO;
using System.Collections.Generic;
using System.Runtime.CompilerServices;

public class DATSimulatedTSEnvironment
{
    private Dictionary<string, string> _values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    public string WriteLogPath = null;

    [IndexerName("Value")]
    public string this[string name]
    {
        get
        {
            string result;
            if (_values.TryGetValue(name, out result)) { return result; }
            return String.Empty;
        }
        set
        {
            _values[name] = value;
            if (WriteLogPath != null)
            {
                try { File.AppendAllText(WriteLogPath, name + "=" + value + Environment.NewLine); }
                catch { }
            }
        }
    }

    public string[] GetVariables()
    {
        string[] keys = new string[_values.Keys.Count];
        _values.Keys.CopyTo(keys, 0);
        return keys;
    }
}
"@

$Global:DATTSEnvironment = $null
$Global:DATTSTypeLoaded = $false
try {
    if (-not ("DATSimulatedTSEnvironment" -as [type])) {
        Add-Type -TypeDefinition $TypeSource -Language CSharp -ErrorAction Stop
    }
    $Global:DATTSEnvironment = New-Object -TypeName DATSimulatedTSEnvironment
    $Global:DATTSTypeLoaded = $true
}
catch {
    # Add-Type is unavailable (a stripped WinPE image without the .NET compiler). Fall back to
    # a read-only object; any attempt by the target script to write a task sequence variable
    # raises a terminating error, which the harness reports.
    Write-Warning "DATSHIM: Add-Type unavailable ($($_.Exception.Message)). Task sequence variable writes will fail."
    $Store = @{}
    $Global:DATTSEnvironment = New-Object -TypeName PSObject
    $Global:DATTSEnvironment | Add-Member -MemberType NoteProperty -Name "Store" -Value $Store
    $Global:DATTSEnvironment | Add-Member -MemberType ScriptMethod -Name "Value" -Value {
        param ([string]$Name)
        if ($this.Store.ContainsKey($Name)) { return [string]$this.Store[$Name] }
        return [string]::Empty
    }
    $Global:DATTSEnvironment | Add-Member -MemberType ScriptMethod -Name "GetVariables" -Value { return @($this.Store.Keys) }
}

foreach ($Key in $Context.TSVariables.Keys) {
    if ($Global:DATTSTypeLoaded) {
        $Global:DATTSEnvironment.Value($Key) = [string]$Context.TSVariables[$Key]
    }
    else {
        $Global:DATTSEnvironment.Store[$Key] = [string]$Context.TSVariables[$Key]
    }
}

# Start logging writes only after seeding, so the log holds just what the target script sets
if ($Global:DATTSTypeLoaded) {
    $Global:DATTSEnvironment.WriteLogPath = $Context.TSWriteLog
}

function Global:New-Object {
    [CmdletBinding(DefaultParameterSetName = "Net")]
    param (
        [Parameter(ParameterSetName = "Net", Position = 0)][string]$TypeName,
        [Parameter(ParameterSetName = "Com", Mandatory = $true)][string]$ComObject,
        [Parameter(ParameterSetName = "Net", Position = 1)][object[]]$ArgumentList,
        [Parameter(ParameterSetName = "Com")][switch]$Strict,
        [hashtable]$Property
    )
    if ($PSCmdlet.ParameterSetName -eq "Com") {
        if ($ComObject -eq "Microsoft.SMS.TSEnvironment") {
            return $Global:DATTSEnvironment
        }
        throw "DATSHIM: COM object '$ComObject' is not simulated by the test harness."
    }
    $Splat = @{ TypeName = $TypeName }
    if ($PSBoundParameters.ContainsKey("ArgumentList")) { $Splat["ArgumentList"] = $ArgumentList }
    if ($PSBoundParameters.ContainsKey("Property")) { $Splat["Property"] = $Property }
    Microsoft.PowerShell.Utility\New-Object @Splat
}

# ------------------------------------------------------------------------- WMI/CIM shim
if ($Context.SimulateHardware -eq $true) {

    $Global:DATHardware = $Context.Hardware

    function Global:Get-DATSimulatedInstance {
        param ([string]$ClassName)
        if ([string]::IsNullOrEmpty($ClassName)) { return $null }
        $Key = @($Global:DATHardware.Keys | Where-Object { $_ -eq $ClassName })[0]
        if ($null -eq $Key) {
            Write-Warning "DATSHIM: class '$ClassName' is not simulated; returning null."
            return $null
        }
        $Instance = Microsoft.PowerShell.Utility\New-Object -TypeName PSObject
        foreach ($PropertyName in $Global:DATHardware[$Key].Keys) {
            $Instance | Add-Member -MemberType NoteProperty -Name $PropertyName -Value $Global:DATHardware[$Key][$PropertyName]
        }
        return $Instance
    }

    function Global:Get-WmiObject {
        [CmdletBinding()]
        param (
            [Parameter(Position = 0)][string]$Class,
            [string]$Namespace,
            [string]$Query,
            [string]$ComputerName,
            [string[]]$Property,
            [object]$Filter,
            [switch]$List
        )
        # root\ccm classes need a ConfigMgr client. The scripts use them for AdminService
        # endpoint type detection, which the harness never exercises.
        if ($Class -eq "SMS_ActiveMPCandidate") { return @() }
        if ($Class -eq "ClientInfo") {
            $Info = Microsoft.PowerShell.Utility\New-Object -TypeName PSObject
            $Info | Add-Member -MemberType NoteProperty -Name "InInternet" -Value $false
            return $Info
        }
        return (Get-DATSimulatedInstance -ClassName $Class)
    }

    function Global:Get-CimInstance {
        [CmdletBinding()]
        param (
            [Parameter(Position = 0)][string]$ClassName,
            [string]$Namespace,
            [string]$Query,
            [string[]]$Property,
            [string]$Filter,
            [object]$CimSession
        )
        if ($ClassName -eq "SMS_ActiveMPCandidate") { return @() }
        return (Get-DATSimulatedInstance -ClassName $ClassName)
    }
}

# --------------------------------------------------------------------------- Invocation
$Parameters = @{}
foreach ($Key in $Context.Parameters.Keys) { $Parameters[$Key] = $Context.Parameters[$Key] }

$Rendered = @($Parameters.Keys | Sort-Object | ForEach-Object {
        if ($_ -eq "Password") { "-Password ********" } else { "-$_ $($Parameters[$_])" }
    })
Write-Host "DATSHIM: invoking $($Context.TargetScript)"
Write-Host ("DATSHIM: parameters " + ($Rendered -join " "))
Write-Host ""

try {
    & $Context.TargetScript @Parameters
    $ExitCode = 0
}
catch {
    Write-Host "DATSHIM: terminating error: $($_.Exception.Message)"
    if ($null -ne $_.ScriptStackTrace) { Write-Host "DATSHIM: $($_.ScriptStackTrace)" }
    $ExitCode = 1
}

exit $ExitCode
'@

#endregion

#region ---------------------------------------------------------------- Script analysis

function Get-ScriptParameterSets {
    <#
        Parses a target script with the PowerShell AST and returns every parameter name and
        the parameter set names it belongs to. Used to verify a deployment mode is actually
        invocable before the harness attempts it.
    #>
    param ([Parameter(Mandatory = $true)][string]$Path)

    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$ParseErrors)

    $Result = [PSCustomObject]@{
        Path          = $Path
        ParseErrors   = @($ParseErrors)
        Parameters    = @{}
        ParameterSets = @()
    }

    if ($null -eq $Ast.ParamBlock) { return $Result }

    $Sets = New-Object -TypeName System.Collections.ArrayList
    foreach ($Parameter in $Ast.ParamBlock.Parameters) {
        $Name = $Parameter.Name.VariablePath.UserPath
        $ParameterSetNames = New-Object -TypeName System.Collections.ArrayList
        foreach ($Attribute in $Parameter.Attributes) {
            if ($Attribute -is [System.Management.Automation.Language.AttributeAst]) {
                foreach ($NamedArgument in $Attribute.NamedArguments) {
                    if ($NamedArgument.ArgumentName -eq "ParameterSetName") {
                        $Value = $NamedArgument.Argument.Extent.Text.Trim('"', "'")
                        $null = $ParameterSetNames.Add($Value)
                        if (-not $Sets.Contains($Value)) { $null = $Sets.Add($Value) }
                    }
                }
            }
        }
        $Result.Parameters[$Name] = @($ParameterSetNames)
    }
    $Result.ParameterSets = @($Sets)
    return $Result
}

function Get-ScriptValidateSet {
    <#
        Returns the ValidateSet values declared on a named parameter of a script.
    #>
    param (
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ParameterName
    )
    if (-not (Test-Path -Path $Path)) { return @() }

    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$ParseErrors)
    if ($null -eq $Ast.ParamBlock) { return @() }

    foreach ($Parameter in $Ast.ParamBlock.Parameters) {
        if ($Parameter.Name.VariablePath.UserPath -ne $ParameterName) { continue }
        foreach ($Attribute in $Parameter.Attributes) {
            if ($Attribute.TypeName.Name -eq "ValidateSet") {
                return @($Attribute.PositionalArguments | ForEach-Object { $_.Extent.Text.Trim('"', "'") })
            }
        }
    }
    return @()
}

#endregion

#region ---------------------------------------------------------------- Log analysis

function ConvertFrom-CMLog {
    <#
        Parses CMTrace formatted log content into message / severity objects.
    #>
    param ([string]$Content)

    $Entries = New-Object -TypeName System.Collections.ArrayList
    if ([string]::IsNullOrEmpty($Content)) { return @() }

    $Pattern = '<!\[LOG\[(?<Message>.*?)\]LOG\]!><time="(?<Time>[^"]*)"\s+date="(?<Date>[^"]*)"\s+component="(?<Component>[^"]*)"\s+context="[^"]*"\s+type="(?<Type>\d)"'
    foreach ($LogMatch in [regex]::Matches($Content, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $null = $Entries.Add([PSCustomObject]@{
                Message  = $LogMatch.Groups["Message"].Value.Trim()
                Severity = [int]$LogMatch.Groups["Type"].Value
                Time     = $LogMatch.Groups["Time"].Value
                Date     = $LogMatch.Groups["Date"].Value
            })
    }
    return @($Entries)
}

function Get-LogFileSize {
    param ([string]$Path)
    if (-not (Test-Path -Path $Path)) { return [long]0 }
    try { return [long](Get-Item -Path $Path).Length } catch { return [long]0 }
}

function Get-LogTail {
    <#
        Returns only the portion of a log file appended since $Offset bytes, plus the new size.
    #>
    param ([string]$Path, [long]$Offset)

    $Result = [PSCustomObject]@{ Content = ""; Size = [long]0 }
    if (-not (Test-Path -Path $Path)) { return $Result }

    try {
        $Stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $Result.Size = $Stream.Length
            if ($Offset -gt $Stream.Length) { $Offset = 0 }
            $null = $Stream.Seek($Offset, [System.IO.SeekOrigin]::Begin)
            $Reader = New-Object System.IO.StreamReader($Stream)
            $Result.Content = $Reader.ReadToEnd()
        }
        finally {
            $Stream.Close()
        }
    }
    catch {
        $Result.Content = ""
    }
    return $Result
}

function Get-MatchedValue {
    param ([object[]]$Entries, [string]$Pattern, [int]$Group = 1)
    foreach ($Entry in $Entries) {
        $ValueMatch = [regex]::Match($Entry.Message, $Pattern)
        if ($ValueMatch.Success) { return $ValueMatch.Groups[$Group].Value.Trim() }
    }
    return $null
}

#endregion

#region ---------------------------------------------------------------- Test runner

function Invoke-TargetScript {
    <#
        Runs one of the target scripts in a child PowerShell process under the shim, captures
        stdout/stderr and the newly written portion of its CMTrace log, and returns a result
        object for analysis.
    #>
    param (
        [Parameter(Mandatory = $true)][string]$TestName,
        [Parameter(Mandatory = $true)][string]$TargetScript,
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [Parameter(Mandatory = $true)][string]$LogFileName,
        [Parameter(Mandatory = $true)][string]$LogDirectory,
        [hashtable]$TSVariables = @{},
        [bool]$SimulateHardware = $true,
        [hashtable]$Hardware = @{}
    )

    $SafeName = ($TestName -replace '[^A-Za-z0-9]+', '_')
    $RunFolder = Join-Path -Path $Script:RunPath -ChildPath $SafeName
    if (-not (Test-Path -Path $RunFolder)) { $null = New-Item -Path $RunFolder -ItemType Directory -Force }

    $ContextPath = Join-Path -Path $RunFolder -ChildPath "context.clixml"
    $StdOutPath = Join-Path -Path $RunFolder -ChildPath "stdout.txt"
    $StdErrPath = Join-Path -Path $RunFolder -ChildPath "stderr.txt"
    $TSWritePath = Join-Path -Path $RunFolder -ChildPath "tsvariable-writes.txt"

    $Context = @{
        TargetScript     = $TargetScript
        Parameters       = $Parameters
        TSVariables      = $TSVariables
        TSWriteLog       = $TSWritePath
        SimulateHardware = $SimulateHardware
        Hardware         = $Hardware
    }
    $Context | Export-Clixml -Path $ContextPath -Force

    $TargetLogPath = Join-Path -Path $LogDirectory -ChildPath $LogFileName
    $StartOffset = Get-LogFileSize -Path $TargetLogPath

    $Arguments = @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-File", ('"{0}"' -f $Script:BootstrapPath)
        "-ContextPath", ('"{0}"' -f $ContextPath)
    )

    Write-Detail ("Running {0} via {1}" -f (Split-Path -Path $TargetScript -Leaf), (Split-Path -Path $Script:HostExecutable -Leaf))
    Write-Verbose ("[{0}] Target script : {1}" -f $TestName, $TargetScript)
    Write-Verbose ("[{0}] Child host    : {1}" -f $TestName, $Script:HostExecutable)
    Write-HashtableVerbose -Title ("[{0}] Script parameters" -f $TestName) -Table $Parameters
    Write-HashtableVerbose -Title ("[{0}] Seeded task sequence variables" -f $TestName) -Table $TSVariables
    if ($SimulateHardware) {
        Write-HashtableVerbose -Title ("[{0}] Simulated WMI/CIM classes" -f $TestName) -Table $Hardware
    }
    else {
        Write-Verbose ("[{0}] Hardware      : real WMI/CIM from this machine (-UseLocalHardware)" -f $TestName)
    }
    Write-Verbose ("[{0}] Watching log  : {1} (from byte {2})" -f $TestName, $TargetLogPath, $StartOffset)
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $ExitCode = -1
    try {
        $Process = Start-Process -FilePath $Script:HostExecutable -ArgumentList $Arguments -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath -ErrorAction Stop
        $ExitCode = $Process.ExitCode
    }
    catch {
        Add-TestResult -Name ("{0}: process launch" -f $TestName) -Status "FAIL" -Detail $_.Exception.Message
        Add-Finding -Severity "Error" -Source $TestName -Message ("Unable to start the child PowerShell process: {0}" -f $_.Exception.Message)
    }

    $StdOut = ""
    if (Test-Path -Path $StdOutPath) { $StdOut = (Get-Content -Path $StdOutPath -Raw) }
    $StdErr = ""
    if (Test-Path -Path $StdErrPath) { $StdErr = (Get-Content -Path $StdErrPath -Raw) }

    $Tail = Get-LogTail -Path $TargetLogPath -Offset $StartOffset
    $CapturedLogPath = Join-Path -Path $RunFolder -ChildPath $LogFileName
    if (-not [string]::IsNullOrEmpty($Tail.Content)) {
        Set-Content -Path $CapturedLogPath -Value $Tail.Content -Encoding UTF8
    }

    $TSWrites = @()
    if (Test-Path -Path $TSWritePath) { $TSWrites = @(Get-Content -Path $TSWritePath) }

    $Stopwatch.Stop()
    Write-Verbose ("[{0}] Exit code {1} after {2:N1}s; {3} bytes of new log" -f $TestName, $ExitCode, $Stopwatch.Elapsed.TotalSeconds, $Tail.Content.Length)
    Write-Verbose ("[{0}] Artefacts     : {1}" -f $TestName, $RunFolder)
    foreach ($Write in $TSWrites) {
        $Name = ($Write -split "=", 2)[0]
        if ($Name -match "Password|Secret|Token") { $Write = "{0}=********" -f $Name }
        Write-Verbose ("[{0}] TS variable set: {1}" -f $TestName, $Write)
    }

    $Run = [PSCustomObject]@{
        TestName   = $TestName
        ExitCode   = $ExitCode
        StdOut     = $StdOut
        StdErr     = $StdErr
        LogPath    = $CapturedLogPath
        LogContent = $Tail.Content
        Entries    = @(ConvertFrom-CMLog -Content $Tail.Content)
        TSWrites   = $TSWrites
        RunFolder  = $RunFolder
    }
    if ($ShowFullLog) { Show-FullLog -Run $Run }
    return $Run
}

function Get-PackageDetail {
    <#
        Name and description of a matched ConfigMgr package. The scripts log the package ID but not
        its description, so it is looked up in the source the run used: the parsed XML logic file,
        or the AdminService with the credential that passed the pre-flight probe. Falls back to the
        name the script logged when the source cannot be read.
    #>
    param ([string]$PackageId, [string]$Source, [string]$LoggedName)

    $Detail = [PSCustomObject]@{ PackageID = $PackageId; Name = $LoggedName; Description = $null }
    if ([string]::IsNullOrEmpty($PackageId)) { return $Detail }
    $Key = "{0}|{1}" -f $Source, $PackageId.ToUpper()

    if (-not $Script:PackageDetailCache.ContainsKey($Key)) {
        $Found = $null
        if ($Source -eq "XMLPackage") {
            $Found = $Script:XmlPackageCatalog | Where-Object { $_.PackageID -eq $PackageId } | Select-Object -First 1
        }
        elseif (($Source -eq "AdminService") -and ($null -ne $Script:AdminServiceCredential) -and ($PackageId -match '^[A-Za-z0-9]{8}$')) {
            $Uri = "https://{0}/AdminService/wmi/SMS_Package?`$filter=PackageID eq '{1}'&`$select=PackageID,Name,Description" -f $Endpoint, $PackageId
            try {
                $Splat = @{ Uri = $Uri; Method = "Get"; Credential = $Script:AdminServiceCredential; ErrorAction = "Stop" }
                if ($PSVersionTable.PSVersion.Major -ge 6) { $Splat["SkipCertificateCheck"] = $true }
                $Found = @((Invoke-RestMethod @Splat).value) | Select-Object -First 1
            }
            catch {
                Write-Verbose ("AdminService lookup of package {0} failed: {1}" -f $PackageId, $_.Exception.Message)
            }
        }
        $Script:PackageDetailCache[$Key] = $Found
    }

    $Found = $Script:PackageDetailCache[$Key]
    if ($null -ne $Found) {
        if (-not [string]::IsNullOrEmpty([string]$Found.Name)) { $Detail.Name = [string]$Found.Name }
        $Detail.Description = [string]$Found.Description
    }
    return $Detail
}

function Show-PackageDetail {
    # Prints the matched package and records it in the report
    param ([string]$TestName, [PSCustomObject]$Detail, [string]$Label = "matched package")
    $Name = $Detail.Name
    if ([string]::IsNullOrEmpty($Name)) { $Name = "(name not available)" }
    $Description = $Detail.Description
    if ($null -eq $Description) { $Description = "(not available from this source)" }
    elseif ($Description -eq "") { $Description = "(empty)" }
    Add-TestResult -Name ("{0}: {1}" -f $TestName, $Label) -Status "INFO" -Detail ("{0} - {1}" -f $Detail.PackageID, $Name)
    Write-Detail ("Description : {0}" -f $Description) "Gray"
    $null = $Script:Results.Add([PSCustomObject]@{ Phase = $Script:CurrentPhase; Name = ("{0}: {1} description" -f $TestName, $Label); Status = "INFO"; Detail = $Description })
    Add-MatchedPackageRow -TestName $TestName -PackageID $Detail.PackageID -Name $Name -Description $Description
}

function Add-MatchedPackageRow {
    # Records a row for the Summary table. TestName is "<Drivers|BIOS>-<AdminService|XMLPackage>".
    param ([string]$TestName, [string]$PackageID = "-", [string]$Name, [string]$Description = "")
    $Parts = $TestName -split "-", 2
    $Source = $Parts[1]
    if ($Source -eq "XMLPackage") { $Source = "XML logic file" }
    $null = $Script:MatchedPackages.Add([PSCustomObject]@{
            Source         = $Source
            Type           = $Parts[0]
            "Package ID"   = $PackageID
            "Package Name" = $Name
            Description    = $Description
        })
}

function Split-TextToWidth {
    # Word-wraps text into lines of at most $Width characters, breaking a word only when it is longer than a line
    param ([string]$Text, [int]$Width)
    $Lines = New-Object -TypeName System.Collections.Generic.List[string]
    $Current = ""
    foreach ($Word in ([string]$Text -split "\s+" | Where-Object { $_ })) {
        while ($Word.Length -gt $Width) {
            if ($Current) { $Lines.Add($Current); $Current = "" }
            $Lines.Add($Word.Substring(0, $Width))
            $Word = $Word.Substring($Width)
        }
        if (-not $Current) { $Current = $Word }
        elseif (($Current.Length + 1 + $Word.Length) -le $Width) { $Current = "$Current $Word" }
        else { $Lines.Add($Current); $Current = $Word }
    }
    if ($Current -or $Lines.Count -eq 0) { $Lines.Add($Current) }
    return , $Lines.ToArray()
}

function Format-MatchedPackageTable {
    <#
        The Summary table as text, fitted to $Width. Source, Type and Package ID keep their full
        width; Package Name and Description share what is left and word-wrap, so the table stays
        readable in a narrow WinPE console instead of squeezing the last column.
    #>
    param ([int]$Width)
    if ($Script:MatchedPackages.Count -eq 0) { return "" }
    $Columns = @("Source", "Type", "Package ID", "Package Name", "Description")
    $Natural = @{}
    foreach ($Column in $Columns) {
        $Natural[$Column] = [Math]::Max($Column.Length, (@($Script:MatchedPackages | ForEach-Object { ([string]$_.$Column).Length }) | Measure-Object -Maximum).Maximum)
    }
    $Gap = 2
    $Fixed = $Natural["Source"] + $Natural["Type"] + $Natural["Package ID"] + (4 * $Gap)
    $Flexible = [Math]::Max(30, $Width - $Fixed)
    $ColumnWidth = @{ "Source" = $Natural["Source"]; "Type" = $Natural["Type"]; "Package ID" = $Natural["Package ID"] }
    if (($Natural["Package Name"] + $Natural["Description"]) -le $Flexible) {
        $ColumnWidth["Package Name"] = $Natural["Package Name"]
        $ColumnWidth["Description"] = $Natural["Description"]
    }
    else {
        # Give the name up to 55% of the space, and the description the rest
        $ColumnWidth["Package Name"] = [Math]::Min($Natural["Package Name"], [Math]::Max(15, [int]($Flexible * 0.55)))
        $ColumnWidth["Description"] = [Math]::Max(12, $Flexible - $ColumnWidth["Package Name"])
    }

    $Separator = " " * $Gap
    $Output = New-Object -TypeName System.Collections.Generic.List[string]
    $Output.Add((($Columns | ForEach-Object { $_.PadRight($ColumnWidth[$_]) }) -join $Separator).TrimEnd())
    $Output.Add((($Columns | ForEach-Object { ("-" * $_.Length).PadRight($ColumnWidth[$_]) }) -join $Separator).TrimEnd())
    foreach ($Row in $Script:MatchedPackages) {
        $Cells = @{}
        $Height = 1
        foreach ($Column in $Columns) {
            $Cells[$Column] = Split-TextToWidth -Text ([string]$Row.$Column) -Width $ColumnWidth[$Column]
            $Height = [Math]::Max($Height, $Cells[$Column].Count)
        }
        for ($i = 0; $i -lt $Height; $i++) {
            $Line = foreach ($Column in $Columns) {
                $Value = ""
                if ($i -lt $Cells[$Column].Count) { $Value = $Cells[$Column][$i] }
                $Value.PadRight($ColumnWidth[$Column])
            }
            $Output.Add(($Line -join $Separator).TrimEnd())
        }
    }
    return ($Output -join [Environment]::NewLine)
}

function Show-MatchDiagnostics {
    <#
        When nothing matched, print the per-package detection lines so the reason is visible.
    #>
    param ([object[]]$Entries)

    $Diagnostic = @($Entries | Where-Object {
            # Per-package lines, including each check that passed and the N/M verdict, so a
            # mismatch shows which check failed (the one missing between Processing and Skipping)
            $_.Message -match "Processing driver package|Attempting to find a match|Unable to match|was skipped due to|does not meet computer model|Count of driver packages after filter|Filtering driver package|^\s*-?\s*Matched |Skipping driver package|checks was matched|Match found for"
        })
    if ($Diagnostic.Count -eq 0) { return }

    # -ShowFullLog has already printed every line, so keep the summary short only without it
    $Limit = 25
    if ($ShowFullLog) { $Limit = $Diagnostic.Count }

    Write-Detail "Matching diagnostics:" "Yellow"
    foreach ($Entry in ($Diagnostic | Select-Object -First $Limit)) {
        Write-Detail ("  {0}" -f $Entry.Message) "DarkYellow"
    }
    if ($Diagnostic.Count -gt $Limit) { Write-Detail ("  ... {0} more lines in the captured log (use -ShowFullLog to print them)" -f ($Diagnostic.Count - $Limit)) "DarkYellow" }
}

function Show-RunAnalysis {
    <#
        Interprets a run result: detection values, package counts, the selected package, and
        every warning and error the target script logged.
    #>
    param (
        [Parameter(Mandatory = $true)][PSCustomObject]$Run,
        [Parameter(Mandatory = $true)][ValidateSet("Drivers", "BIOS")][string]$Kind,
        [PSCustomObject]$Expected,
        # Regex matching the first log entry of the content download phase. Everything from
        # that entry onwards needs a live task sequence, so it is reported but not judged.
        [string]$PostMatchPattern
    )

    $Entries = $Run.Entries

    if ($Entries.Count -eq 0) {
        Add-TestResult -Name ("{0}: log output" -f $Run.TestName) -Status "FAIL" -Detail "no CMTrace log entries produced - the script did not reach its logging stage"
        Add-Finding -Severity "Error" -Source $Run.TestName -Message ("The script produced no log output. Check stdout in {0}." -f $Run.RunFolder)
        if (-not [string]::IsNullOrWhiteSpace($Run.StdOut)) {
            foreach ($Line in (@($Run.StdOut -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -Last 10)) {
                Write-Detail ("stdout: {0}" -f $Line) "Red"
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($Run.StdErr)) {
            foreach ($Line in (@($Run.StdErr -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -First 10)) {
                Write-Detail ("stderr: {0}" -f $Line) "Red"
            }
        }
        return
    }

    Add-TestResult -Name ("{0}: log output" -f $Run.TestName) -Status "PASS" -Detail ("{0} log entries captured" -f $Entries.Count)

    # ---- detection values
    $DetectedManufacturer = Get-MatchedValue -Entries $Entries -Pattern "Computer manufacturer determined as:\s*(.+)$"
    $DetectedModel = Get-MatchedValue -Entries $Entries -Pattern "Computer model determined as:\s*(.+)$"
    $DetectedSKU = Get-MatchedValue -Entries $Entries -Pattern "Computer SystemSKU determined as:\s*(.+)$"
    $DetectionMethod = Get-MatchedValue -Entries $Entries -Pattern "Determined (?:primary|fallback) computer detection method:\s*(.+)$"

    if ($null -ne $DetectedManufacturer) {
        Add-TestResult -Name ("{0}: manufacturer detection" -f $Run.TestName) -Status "PASS" -Detail $DetectedManufacturer
        if (($null -ne $Expected) -and (-not [string]::IsNullOrEmpty($Expected.Manufacturer)) -and ($DetectedManufacturer -ne $Expected.Manufacturer)) {
            Add-TestResult -Name ("{0}: manufacturer matches expectation" -f $Run.TestName) -Status "WARN" -Detail ("expected '{0}', script derived '{1}'" -f $Expected.Manufacturer, $DetectedManufacturer)
            Add-Finding -Severity "Warning" -Source $Run.TestName -Message ("Manufacturer normalisation differs from expectation: expected '{0}', got '{1}'." -f $Expected.Manufacturer, $DetectedManufacturer)
        }
    }
    else {
        Add-TestResult -Name ("{0}: manufacturer detection" -f $Run.TestName) -Status "FAIL" -Detail "not reported in the log"
    }

    if ($null -ne $DetectedModel) {
        Add-TestResult -Name ("{0}: model detection" -f $Run.TestName) -Status "PASS" -Detail $DetectedModel
    }
    else {
        Add-TestResult -Name ("{0}: model detection" -f $Run.TestName) -Status "FAIL" -Detail "not reported in the log"
    }

    if (($null -ne $DetectedSKU) -and ($DetectedSKU -ne "<null>")) {
        Add-TestResult -Name ("{0}: SystemSKU detection" -f $Run.TestName) -Status "PASS" -Detail $DetectedSKU
        if (($null -ne $Expected) -and (-not [string]::IsNullOrEmpty($Expected.SystemSKU)) -and ($DetectedSKU -ne $Expected.SystemSKU)) {
            Add-TestResult -Name ("{0}: SystemSKU matches expectation" -f $Run.TestName) -Status "WARN" -Detail ("expected '{0}', script derived '{1}'" -f $Expected.SystemSKU, $DetectedSKU)
        }
    }
    else {
        Add-TestResult -Name ("{0}: SystemSKU detection" -f $Run.TestName) -Status "WARN" -Detail "SystemSKU is null - matching falls back to the computer model"
    }

    if ($null -ne $DetectionMethod) {
        Add-TestResult -Name ("{0}: detection method" -f $Run.TestName) -Status "INFO" -Detail $DetectionMethod
    }

    # ---- OS targeting (drivers only)
    if ($Kind -eq "Drivers") {
        $OSName = Get-MatchedValue -Entries $Entries -Pattern "Target operating system name configured as:\s*(.+)$"
        $OSArch = Get-MatchedValue -Entries $Entries -Pattern "Target operating system architecture configured as:\s*(.+)$"
        $OSVersion = Get-MatchedValue -Entries $Entries -Pattern "Target operating system version configured as:\s*(.+)$"
        if ($null -ne $OSName) {
            Add-TestResult -Name ("{0}: target OS" -f $Run.TestName) -Status "INFO" -Detail ("{0} {1} {2}" -f $OSName, $OSVersion, $OSArch)
        }
    }

    # ---- package retrieval
    $RetrievedCount = Get-MatchedValue -Entries $Entries -Pattern "Retrieved a total of '(\d+)' (?:driver|BIOS) packages"
    if ($null -ne $RetrievedCount) {
        if ([int]$RetrievedCount -gt 0) {
            Add-TestResult -Name ("{0}: package retrieval" -f $Run.TestName) -Status "PASS" -Detail ("{0} package(s) returned from the source" -f $RetrievedCount)
        }
        else {
            Add-TestResult -Name ("{0}: package retrieval" -f $Run.TestName) -Status "FAIL" -Detail "0 packages returned - check the name filter and operational mode"
            Add-Finding -Severity "Error" -Source $Run.TestName -Message "The package source returned zero packages. Verify the name filter and that packages exist for the selected operational mode."
        }
    }
    else {
        Add-TestResult -Name ("{0}: package retrieval" -f $Run.TestName) -Status "FAIL" -Detail "the script did not reach the package retrieval stage"
    }

    # ---- matching outcome
    $PackageSource = "AdminService"
    if ($Run.TestName -match "XMLPackage") { $PackageSource = "XMLPackage" }
    if ($Kind -eq "Drivers") {
        $Selected = Get-MatchedValue -Entries $Entries -Pattern "Selected driver package '([^']+)' with name:"
        $SelectedName = Get-MatchedValue -Entries $Entries -Pattern "Selected driver package '[^']+' with name:\s*(.+)$"
        $ValidatedCount = Get-MatchedValue -Entries $Entries -Pattern "Amount of driver packages detected by validation process:\s*(\d+)"
        $SingleMatch = @($Entries | Where-Object { $_.Message -match "Successfully completed validation with a single driver package" })
        $MatchLines = @($Entries | Where-Object { $_.Message -match "Match found between driver package and computer" })

        if (($null -ne $ValidatedCount) -and ([int]$ValidatedCount -gt 0)) {
            if ($null -ne $Selected) {
                Add-TestResult -Name ("{0}: package match" -f $Run.TestName) -Status "PASS" -Detail ("{0} candidate(s); selected {1} - {2}" -f $ValidatedCount, $Selected, $SelectedName)
                Show-PackageDetail -TestName $Run.TestName -Label "selected package" -Detail (Get-PackageDetail -PackageId $Selected -Source $PackageSource -LoggedName $SelectedName)
            }
            elseif ($SingleMatch.Count -gt 0) {
                $SingleId = Get-MatchedValue -Entries $Entries -Pattern "\[DriverPackage:([^\]]+)\]: Match found between driver package and computer"
                Add-TestResult -Name ("{0}: package match" -f $Run.TestName) -Status "PASS" -Detail ("single match: package {0}" -f $SingleId)
                $LoggedName = Get-MatchedValue -Entries $Entries -Pattern ("\[DriverPackage:{0}\]: Processing driver package with \d+ detection methods:\s*(.+)$" -f [regex]::Escape([string]$SingleId))
                Show-PackageDetail -TestName $Run.TestName -Detail (Get-PackageDetail -PackageId $SingleId -Source $PackageSource -LoggedName $LoggedName)
            }
            else {
                Add-TestResult -Name ("{0}: package match" -f $Run.TestName) -Status "PASS" -Detail ("{0} package(s) validated" -f $ValidatedCount)
                Add-MatchedPackageRow -TestName $Run.TestName -Name ("({0} packages validated - see the log)" -f $ValidatedCount)
            }
        }
        elseif ($MatchLines.Count -gt 0) {
            Add-TestResult -Name ("{0}: package match" -f $Run.TestName) -Status "PASS" -Detail ("{0} package(s) matched" -f $MatchLines.Count)
            Add-MatchedPackageRow -TestName $Run.TestName -Name ("({0} packages matched - see the log)" -f $MatchLines.Count)
        }
        else {
            Add-MatchedPackageRow -TestName $Run.TestName -Name "(no match)"
            Add-TestResult -Name ("{0}: package match" -f $Run.TestName) -Status "FAIL" -Detail "no driver package matched the specified make, model and OS"
            Add-Finding -Severity "Error" -Source $Run.TestName -Message ("No driver package matched. See the per-package detection lines in {0}." -f $Run.LogPath)
            Show-MatchDiagnostics -Entries $Entries
        }
    }
    else {
        $BIOSMatches = @($Entries | Where-Object { $_.Message -match "Match found for computer model and manufacturer" })
        $NewBIOS = @($Entries | Where-Object { $_.Message -match "A new version of the BIOS has been detected" })
        $CurrentBIOS = Get-MatchedValue -Entries $Entries -Pattern "Current BIOS version determined as:\s*(.+)$"

        if ($null -ne $CurrentBIOS) {
            Add-TestResult -Name ("{0}: installed BIOS version" -f $Run.TestName) -Status "INFO" -Detail $CurrentBIOS
        }
        if ($BIOSMatches.Count -gt 0) {
            $Names = @($BIOSMatches | ForEach-Object { ([regex]::Match($_.Message, "manufacturer:\s*(.+)$")).Groups[1].Value.Trim() })
            Add-TestResult -Name ("{0}: package match" -f $Run.TestName) -Status "PASS" -Detail ("{0} BIOS package(s) matched: {1}" -f $BIOSMatches.Count, ($Names -join "; "))
            # Logged as "<name> (<package ID>)"
            foreach ($Logged in $Names) {
                $BIOSMatch = [regex]::Match($Logged, "^(?<Name>.+?)\s*\((?<Id>[A-Za-z0-9]{8})\)$")
                if ($BIOSMatch.Success) {
                    Show-PackageDetail -TestName $Run.TestName -Detail (Get-PackageDetail -PackageId $BIOSMatch.Groups["Id"].Value -Source $PackageSource -LoggedName $BIOSMatch.Groups["Name"].Value)
                }
            }
        }
        else {
            Add-MatchedPackageRow -TestName $Run.TestName -Name "(no match)"
            Add-TestResult -Name ("{0}: package match" -f $Run.TestName) -Status "FAIL" -Detail "no BIOS package matched the specified make and model"
            Add-Finding -Severity "Error" -Source $Run.TestName -Message ("No BIOS package matched. See the per-package detection lines in {0}." -f $Run.LogPath)
            Show-MatchDiagnostics -Entries $Entries
        }
        if ($NewBIOS.Count -gt 0) {
            Add-TestResult -Name ("{0}: BIOS version comparison" -f $Run.TestName) -Status "INFO" -Detail "a newer BIOS release was detected against the simulated installed version"
        }
    }

    # ---- warnings and errors written by the target script
    $PostMatchIndex = -1
    if (-not [string]::IsNullOrEmpty($PostMatchPattern)) {
        for ($i = 0; $i -lt $Entries.Count; $i++) {
            if ($Entries[$i].Message -match $PostMatchPattern) { $PostMatchIndex = $i; break }
        }
    }

    $Evaluated = $Entries
    $NotEvaluated = @()
    if ($PostMatchIndex -gt 0) {
        $Evaluated = @($Entries[0..($PostMatchIndex - 1)])
        $NotEvaluated = @($Entries[$PostMatchIndex..($Entries.Count - 1)])
    }

    $ScriptErrors = @($Evaluated | Where-Object { $_.Severity -eq 3 })
    $ScriptWarnings = @($Evaluated | Where-Object { $_.Severity -eq 2 })

    if ($ScriptErrors.Count -gt 0) {
        Add-TestResult -Name ("{0}: script errors" -f $Run.TestName) -Status "FAIL" -Detail ("{0} severity 3 entries logged" -f $ScriptErrors.Count)
        foreach ($ErrorEntry in ($ScriptErrors | Select-Object -First 15)) {
            Write-Detail ("ERROR: {0}" -f $ErrorEntry.Message) "Red"
            Add-Finding -Severity "Error" -Source $Run.TestName -Message $ErrorEntry.Message
        }
        if ($ScriptErrors.Count -gt 15) { Write-Detail ("... and {0} more, see {1}" -f ($ScriptErrors.Count - 15), $Run.LogPath) "Red" }
    }
    else {
        Add-TestResult -Name ("{0}: script errors" -f $Run.TestName) -Status "PASS" -Detail "no severity 3 entries"
    }

    if ($ScriptWarnings.Count -gt 0) {
        Add-TestResult -Name ("{0}: script warnings" -f $Run.TestName) -Status "WARN" -Detail ("{0} severity 2 entries logged" -f $ScriptWarnings.Count)
        $WarningLimit = 10
        if ($ShowFullLog) { $WarningLimit = $ScriptWarnings.Count }
        foreach ($WarningEntry in ($ScriptWarnings | Select-Object -First $WarningLimit)) {
            Write-Detail ("WARN : {0}" -f $WarningEntry.Message) "Yellow"
        }
        if ($ScriptWarnings.Count -gt $WarningLimit) { Write-Detail ("... and {0} more, see {1} (or use -ShowFullLog)" -f ($ScriptWarnings.Count - $WarningLimit), $Run.LogPath) "Yellow" }
    }
    else {
        Add-TestResult -Name ("{0}: script warnings" -f $Run.TestName) -Status "PASS" -Detail "no severity 2 entries"
    }

    if ($NotEvaluated.Count -gt 0) {
        $NotEvaluatedErrors = @($NotEvaluated | Where-Object { $_.Severity -eq 3 })
        Add-TestResult -Name ("{0}: content download / install phase" -f $Run.TestName) -Status "SKIP" `
            -Detail ("{0} entries ({1} error(s)) not evaluated - the download and install phases need a live task sequence and OSDDownloadContent.exe" -f $NotEvaluated.Count, $NotEvaluatedErrors.Count)
    }

    # ---- task sequence variables the script wrote
    if ($Run.TSWrites.Count -gt 0) {
        $Written = @($Run.TSWrites | ForEach-Object { ($_ -split "=", 2)[0] } | Select-Object -Unique)
        Add-TestResult -Name ("{0}: task sequence variables written" -f $Run.TestName) -Status "INFO" -Detail ($Written -join ", ")
    }

    if ($Run.ExitCode -ne 0) {
        Add-TestResult -Name ("{0}: exit code" -f $Run.TestName) -Status "WARN" -Detail ("{0} - expected for modes that continue into the download phase outside a task sequence" -f $Run.ExitCode)
    }
    else {
        Add-TestResult -Name ("{0}: exit code" -f $Run.TestName) -Status "PASS" -Detail "0"
    }
}

#endregion

#region ---------------------------------------------------------------- Main

# Same branding as the Driver Automation Tool launch banner (Start-DriverAutomationTool.ps1)
$DATBanner = @'

    ____       _
   / __ \_____(_)   _____  _____
  / / / / ___/ / | / / _ \/ ___/
 / /_/ / /  / /| |/ /  __/ /
/_____/_/  /_/ |___/\___/_/              __  _
   /   | __  __/ /_____  ____ ___  ____/ /_(_)___  ____
  / /| |/ / / / __/ __ \/ __ `__ \/ __  / __/ / __ \/ __ \
 / ___ / /_/ / /_/ /_/ / / / / / / /_/ / /_/ / /_/ / / / /
/_/  |_\__,_/\__/\____/_/ /_/ /_/\__,_/\__/_/\____/_/ /_/
  /_  __/___  ____  / /
   / / / __ \/ __ \/ /
  / / / /_/ / /_/ / /
 /_/  \____/\____/_/
'@
Write-Host $DATBanner -ForegroundColor Cyan

Write-Banner "Modern Driver / BIOS Management - Test Harness"

# ---- Resolve script locations
# Always the harness's own folder: it ships beside the scripts in Scripts\ and is packaged flat with
# them, so it tests exactly the copies the task sequence runs and never a copy from somewhere else.
$ScriptPath = $PSScriptRoot
$DriverScript = Join-Path -Path $ScriptPath -ChildPath "Invoke-CMApplyDriverPackage.ps1"
$BIOSScript = Join-Path -Path $ScriptPath -ChildPath "Invoke-CMDownloadBIOSPackage.ps1"

# ---- Run folder
if ([string]::IsNullOrEmpty($OutputPath)) { $OutputPath = [System.IO.Path]::GetTempPath() }
$Script:RunPath = Join-Path -Path $OutputPath -ChildPath ("DATTest_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$null = New-Item -Path $Script:RunPath -ItemType Directory -Force
$Script:BootstrapPath = Join-Path -Path $Script:RunPath -ChildPath "Invoke-ShimmedScript.ps1"
Set-Content -Path $Script:BootstrapPath -Value $Script:BootstrapSource -Encoding UTF8

$Script:HostExecutable = Get-PowerShellHostPath
$Script:IsWinPE = Test-WinPE

# Everything on the console (verbose output included) also goes to Harness.log, so the detail
# survives a WinPE console with no scrollback. Some WinPE images lack Start-Transcript.
$Script:TranscriptStarted = $false
$Script:HarnessLogPath = Join-Path -Path $Script:RunPath -ChildPath "Harness.log"
if (Get-Command -Name Start-Transcript -ErrorAction SilentlyContinue) {
    try {
        $null = Start-Transcript -Path $Script:HarnessLogPath -Force -ErrorAction Stop
        $Script:TranscriptStarted = $true
    }
    catch {
        Write-Host ("Harness.log could not be started: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host ("Run folder    : {0}" -f $Script:RunPath)
Write-Host ("Script folder : {0}" -f $ScriptPath)
Write-Host ("Child host    : {0}" -f $Script:HostExecutable)

# ---- Interactive input
if (-not $NonInteractive) {
    if ([string]::IsNullOrEmpty($Manufacturer)) {
        $Manufacturer = Read-Choice -Title "Select the computer manufacturer (make) to test:" -Options @(
            "Dell", "HP", "Hewlett-Packard", "Lenovo", "Microsoft", "Fujitsu", "Panasonic", "Viglen", "AZW", "Getac", "Intel", "ByteSpeed", "ASUS"
        )
    }
    if ([string]::IsNullOrEmpty($SystemSKU)) {
        switch ($Manufacturer) {
            "Dell" { $SKUPrompt = "Enter the baseboard / SystemSKU value (Dell SystemSku, e.g. 0B0C)" }
            "Lenovo" { $SKUPrompt = "Enter the baseboard value (Lenovo 4-character machine type, e.g. 21F6)" }
            "Microsoft" { $SKUPrompt = "Enter the baseboard / SystemSKU value (e.g. Surface_Pro_9_2038)" }
            default { $SKUPrompt = "Enter the baseboard value (BaseBoardProduct / BaseBoard SKU, e.g. 8A78)" }
        }
        $SystemSKU = Read-Value -Prompt $SKUPrompt -AllowEmpty
    }
    if ([string]::IsNullOrEmpty($ComputerModel)) {
        $ComputerModel = Read-Value -Prompt "Enter the computer model (blank to match on the baseboard only)" -AllowEmpty
    }
    if ([string]::IsNullOrEmpty($TargetOSName)) {
        $TargetOSName = Read-Choice -Title "Select the target operating system:" -Options @("Windows 11", "Windows 10") -Default "Windows 11"
    }
    if ([string]::IsNullOrEmpty($TargetOSVersion)) {
        $TargetOSVersion = Read-Choice -Title "Select the target operating system version:" -Options @("26H2", "26H1", "25H2", "24H2", "23H2", "22H2", "21H2", "21H1", "20H2", "2004", "1909") -Default "24H2"
    }
    if (-not $PSBoundParameters.ContainsKey("TargetOSArchitecture")) {
        $TargetOSArchitecture = Read-Choice -Title "Select the target architecture:" -Options @("x64", "Arm64", "x86") -Default "x64"
    }
    if (-not $PSBoundParameters.ContainsKey("Scope")) {
        $Scope = Read-Choice -Title "Which package source do you want to test?" -Options @("All", "AdminService", "XMLPackage") -Default "All"
    }
    if (-not $PSBoundParameters.ContainsKey("Component")) {
        $Component = Read-Choice -Title "Which scripts do you want to test?" -Options @("All", "Drivers", "BIOS") -Default "All"
    }
    if (($Scope -ne "XMLPackage") -and [string]::IsNullOrEmpty($Endpoint)) {
        $Endpoint = Read-Value -Prompt "AdminService endpoint FQDN (e.g. CM01.domain.local), blank to skip the AdminService tests" -AllowEmpty
    }
    if ((-not [string]::IsNullOrEmpty($Endpoint)) -and [string]::IsNullOrEmpty($UserName)) {
        $UserName = Read-Value -Prompt "AdminService service account user name" -AllowEmpty
    }
    if ((-not [string]::IsNullOrEmpty($UserName)) -and [string]::IsNullOrEmpty($Password)) {
        $SecureInput = Read-Host -Prompt "AdminService service account password" -AsSecureString
        $Bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureInput)
        try { $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($Bstr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr) }
    }
    if (($Scope -ne "AdminService") -and [string]::IsNullOrEmpty($XMLPackagePath)) {
        $XMLPackagePath = Read-Value -Prompt "Path to DriverPackages.xml (or the folder holding it), blank to skip the XML tests" -AllowEmpty
    }
}

if ([string]::IsNullOrEmpty($Manufacturer)) {
    Write-Host "A manufacturer is required. Re-run with -Manufacturer." -ForegroundColor Red
    Stop-HarnessTranscript
    exit 2
}
if ([string]::IsNullOrEmpty($TargetOSName)) { $TargetOSName = "Windows 11" }
if ([string]::IsNullOrEmpty($TargetOSVersion)) { $TargetOSVersion = "24H2" }

# Normalise the XML path: accept the file itself or the folder holding it
$XMLPackageFolder = ""
$XMLLogicFile = ""
if (-not [string]::IsNullOrEmpty($XMLPackagePath)) {
    if ($XMLPackagePath -like "*.xml") {
        $XMLLogicFile = $XMLPackagePath
        $XMLPackageFolder = Split-Path -Path $XMLPackagePath -Parent
    }
    else {
        $XMLPackageFolder = $XMLPackagePath
        $XMLLogicFile = Join-Path -Path $XMLPackagePath -ChildPath "DriverPackages.xml"
    }
}

$TestDrivers = ($Component -eq "All") -or ($Component -eq "Drivers")
$TestBIOS = ($Component -eq "All") -or ($Component -eq "BIOS")
$TestAdminService = (($Scope -eq "All") -or ($Scope -eq "AdminService")) -and (-not [string]::IsNullOrEmpty($Endpoint))
$TestXMLPackage = (($Scope -eq "All") -or ($Scope -eq "XMLPackage")) -and (-not [string]::IsNullOrEmpty($XMLLogicFile))

Write-Verbose ("Test plan: Drivers={0} BIOS={1} AdminService={2} XMLPackage={3} SimulatedHardware={4} ShowFullLog={5}" -f `
        $TestDrivers, $TestBIOS, $TestAdminService, $TestXMLPackage, (-not $UseLocalHardware), [bool]$ShowFullLog)
Write-Verbose ("Target: {0} / '{1}' / '{2}' -> {3} {4} {5}, {6} mode, XML deployment type {7}" -f `
        $Manufacturer, $ComputerModel, $SystemSKU, $TargetOSName, $TargetOSVersion, $TargetOSArchitecture, $OperationalMode, $XMLDeploymentType)
if ($TestXMLPackage) { Write-Verbose ("XML logic file: {0} (package folder {1})" -f $XMLLogicFile, $XMLPackageFolder) }
if (-not [string]::IsNullOrEmpty($Endpoint)) { Write-Verbose ("AdminService endpoint: {0} as '{1}'" -f $Endpoint, $UserName) }
Write-Verbose ("Driver script: {0}" -f $DriverScript)
Write-Verbose ("BIOS script  : {0}" -f $BIOSScript)

#region ---- Phase 1: environment

Write-Banner "Phase 1 - Environment prerequisites"
Write-Section "Host"

Add-TestResult -Name "PowerShell version" -Status "INFO" -Detail ("{0} ({1})" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Add-TestResult -Name "PowerShell 5.1 or later" -Status "FAIL" -Detail "the target scripts require PowerShell 5.1 or later"
    Add-Finding -Severity "Error" -Source "Environment" -Message ("PowerShell {0} is below the 5.1 minimum required by the target scripts." -f $PSVersionTable.PSVersion)
}
else {
    Add-TestResult -Name "PowerShell 5.1 or later" -Status "PASS"
}

if ($Script:IsWinPE) {
    Add-TestResult -Name "Operating system phase" -Status "INFO" -Detail "WinPE"
}
else {
    Add-TestResult -Name "Operating system phase" -Status "INFO" -Detail ("Full OS - {0}" -f [System.Environment]::OSVersion.VersionString)
}
Add-TestResult -Name "Child PowerShell host" -Status "INFO" -Detail $Script:HostExecutable

if (Test-Elevated) {
    Add-TestResult -Name "Running elevated" -Status "PASS"
}
else {
    Add-TestResult -Name "Running elevated" -Status "WARN" -Detail "not elevated - WMI reads and log writes under %SystemRoot%\Temp may fail"
    Add-Finding -Severity "Warning" -Source "Environment" -Message "The harness is not running elevated. Run as administrator (or as SYSTEM) to mirror task sequence conditions."
}

if ([System.Environment]::Is64BitProcess) {
    Add-TestResult -Name "Process architecture" -Status "INFO" -Detail "64-bit"
}
else {
    Add-TestResult -Name "Process architecture" -Status "INFO" -Detail "32-bit"
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Add-TestResult -Name "TLS 1.2 available" -Status "PASS"
}
catch {
    Add-TestResult -Name "TLS 1.2 available" -Status "FAIL" -Detail $_.Exception.Message
    Add-Finding -Severity "Error" -Source "Environment" -Message "TLS 1.2 could not be enabled; AdminService calls will fail."
}

try {
    if (-not ("DATHarnessAddTypeProbe" -as [type])) {
        Add-Type -TypeDefinition "public class DATHarnessAddTypeProbe { }" -Language CSharp -ErrorAction Stop
    }
    Add-TestResult -Name "Add-Type (C# compiler) available" -Status "PASS" -Detail "the simulated task sequence environment supports variable writes"
}
catch {
    Add-TestResult -Name "Add-Type (C# compiler) available" -Status "WARN" -Detail "unavailable - simulated task sequence variable writes will raise errors"
    Add-Finding -Severity "Warning" -Source "Environment" -Message "Add-Type is unavailable in this image. The XMLPackage tests still validate detection and matching, but terminate when the script first writes a task sequence variable."
}

$SystemTempLog = Join-Path -Path $env:SystemRoot -ChildPath "Temp"
if (Test-Path -Path $SystemTempLog) {
    Add-TestResult -Name "DebugMode log directory" -Status "PASS" -Detail $SystemTempLog
}
else {
    Add-TestResult -Name "DebugMode log directory" -Status "FAIL" -Detail ("{0} does not exist - DebugMode logging will fail" -f $SystemTempLog)
    Add-Finding -Severity "Error" -Source "Environment" -Message ("{0} does not exist. The scripts write ApplyDriverPackage.log / ApplyBIOSPackage.log there in DebugMode." -f $SystemTempLog)
}

# Real task sequence environment, if one happens to be present
$RealTSEnvironment = $null
try {
    $RealTSEnvironment = New-Object -ComObject "Microsoft.SMS.TSEnvironment" -ErrorAction Stop
    Add-TestResult -Name "Microsoft.SMS.TSEnvironment COM object" -Status "PASS" -Detail "a live task sequence environment is available on this host"
    # The scripts ignore MDMCertificateThumbprint in -DebugMode, so carry the live task sequence's
    # value over to their -CertificateThumbprint parameter
    if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        $LiveThumbprint = [string]$RealTSEnvironment.Value("MDMCertificateThumbprint")
        if (-not [string]::IsNullOrWhiteSpace($LiveThumbprint)) {
            $CertificateThumbprint = $LiveThumbprint
            Add-TestResult -Name "AdminService certificate thumbprint" -Status "INFO" -Detail ("taken from the live MDMCertificateThumbprint variable: {0}" -f (ConvertTo-Thumbprint $LiveThumbprint))
        }
    }
}
catch {
    Add-TestResult -Name "Microsoft.SMS.TSEnvironment COM object" -Status "INFO" -Detail "not available - the harness simulates it"
}

Write-Section "Target scripts"

foreach ($Target in @(
        @{ Name = "Invoke-CMApplyDriverPackage.ps1"; Path = $DriverScript },
        @{ Name = "Invoke-CMDownloadBIOSPackage.ps1"; Path = $BIOSScript }
    )) {
    if (Test-Path -Path $Target.Path) {
        $Analysis = Get-ScriptParameterSets -Path $Target.Path
        if ($Analysis.ParseErrors.Count -gt 0) {
            Add-TestResult -Name ("{0} parses" -f $Target.Name) -Status "FAIL" -Detail ("{0} syntax error(s)" -f $Analysis.ParseErrors.Count)
            foreach ($ParseFailure in ($Analysis.ParseErrors | Select-Object -First 5)) {
                Add-Finding -Severity "Error" -Source $Target.Name -Message ("Syntax error at line {0}: {1}" -f $ParseFailure.Extent.StartLineNumber, $ParseFailure.Message)
                Write-Detail ("line {0}: {1}" -f $ParseFailure.Extent.StartLineNumber, $ParseFailure.Message) "Red"
            }
        }
        else {
            Add-TestResult -Name ("{0} present and parses" -f $Target.Name) -Status "PASS" -Detail ("parameter sets: {0}" -f (($Analysis.ParameterSets | Sort-Object) -join ", "))
        }
        if ($Target.Name -like "*ApplyDriverPackage*") { $Script:DriverAnalysis = $Analysis } else { $Script:BIOSAnalysis = $Analysis }
    }
    else {
        Add-TestResult -Name ("{0} present" -f $Target.Name) -Status "FAIL" -Detail ("not found at {0}" -f $Target.Path)
        Add-Finding -Severity "Error" -Source "Environment" -Message ("{0} was not found at {1}. Copy it into the harness's own folder ({2}); the harness only tests the scripts beside it." -f $Target.Name, $Target.Path, $ScriptPath)
    }
}

# XMLPackage invocability
$DriverSupportsXML = $false
if ($null -ne $Script:DriverAnalysis) {
    $DriverSupportsXML = $Script:DriverAnalysis.Parameters.ContainsKey("XMLPackage")
    if ($DriverSupportsXML) {
        Add-TestResult -Name "Driver script supports -XMLPackage" -Status "PASS"
    }
    else {
        Add-TestResult -Name "Driver script supports -XMLPackage" -Status "FAIL" -Detail "no XMLPackage parameter declared"
        Add-Finding -Severity "Error" -Source "Invoke-CMApplyDriverPackage.ps1" -Message "The script declares no -XMLPackage parameter, so XML logic file deployments cannot be invoked."
    }
}

$BIOSSupportsXML = $false
if ($null -ne $Script:BIOSAnalysis) {
    $BIOSSupportsXML = $Script:BIOSAnalysis.Parameters.ContainsKey("XMLPackage")
    if ($BIOSSupportsXML) {
        Add-TestResult -Name "BIOS script supports -XMLPackage" -Status "PASS"
    }
    else {
        Add-TestResult -Name "BIOS script supports -XMLPackage" -Status "FAIL" -Detail "XMLPackage code paths exist but no -XMLPackage parameter is declared"
        Add-Finding -Severity "Error" -Source "Invoke-CMDownloadBIOSPackage.ps1" -Message "Get-DeploymentType and Get-BIOSPackages both branch on a parameter set named 'XMLPackage', but the param block declares no -XMLPackage switch, so those branches are unreachable. XML logic file BIOS deployments cannot be run with the shipped script."
    }
}

# Manufacturer coverage in each script
$Expected = Get-ExpectedDetection -Manufacturer $Manufacturer -Model $ComputerModel -SystemSKU $SystemSKU

if ($null -ne $Script:DriverAnalysis) {
    $DriverManufacturers = Get-ScriptValidateSet -Path $DriverScript -ParameterName "Manufacturer"
    if ($DriverManufacturers -contains $Manufacturer) {
        Add-TestResult -Name ("Driver script -Manufacturer accepts '{0}'" -f $Manufacturer) -Status "PASS"
    }
    else {
        Add-TestResult -Name ("Driver script -Manufacturer accepts '{0}'" -f $Manufacturer) -Status "WARN" -Detail "not in the ValidateSet - the debug override cannot be passed"
        Add-Finding -Severity "Warning" -Source "Invoke-CMApplyDriverPackage.ps1" -Message ("'{0}' is not in the -Manufacturer ValidateSet, so it cannot be overridden in DebugMode. Detection relies on the simulated WMI values instead." -f $Manufacturer)
    }
}
if ($null -ne $Script:BIOSAnalysis) {
    $BIOSManufacturers = Get-ScriptValidateSet -Path $BIOSScript -ParameterName "Manufacturer"
    if ($BIOSManufacturers -contains $Manufacturer) {
        Add-TestResult -Name ("BIOS script -Manufacturer accepts '{0}'" -f $Manufacturer) -Status "PASS"
    }
    else {
        Add-TestResult -Name ("BIOS script -Manufacturer accepts '{0}'" -f $Manufacturer) -Status "WARN" -Detail "not in the ValidateSet - the debug override cannot be passed"
        Add-Finding -Severity "Warning" -Source "Invoke-CMDownloadBIOSPackage.ps1" -Message ("'{0}' is not in the -Manufacturer ValidateSet." -f $Manufacturer)
    }
    # Get-BIOSUpdate filters matches against a hard-coded manufacturer allow-list
    $BIOSAllowList = @("Dell", "Hewlett-Packard", "Lenovo", "Microsoft", "HP")
    if ($BIOSAllowList -contains $Expected.Manufacturer) {
        Add-TestResult -Name ("BIOS matching allow-list covers '{0}'" -f $Expected.Manufacturer) -Status "PASS"
    }
    else {
        Add-TestResult -Name ("BIOS matching allow-list covers '{0}'" -f $Expected.Manufacturer) -Status "WARN" -Detail ("Get-BIOSUpdate only matches {0}" -f ($BIOSAllowList -join ", "))
        Add-Finding -Severity "Warning" -Source "Invoke-CMDownloadBIOSPackage.ps1" -Message ("Get-BIOSUpdate filters matched packages against a hard-coded list ({0}). '{1}' is not in it, so no BIOS package can ever match for this make." -f ($BIOSAllowList -join ", "), $Expected.Manufacturer)
    }
}

Write-Section "Package sources"

if ($TestAdminService) {
    Add-TestResult -Name "AdminService endpoint supplied" -Status "PASS" -Detail $Endpoint
    if (Test-TcpPort -ComputerName $Endpoint -Port 443) {
        Add-TestResult -Name "AdminService TCP 443 reachable" -Status "PASS"
    }
    else {
        Add-TestResult -Name "AdminService TCP 443 reachable" -Status "FAIL" -Detail "no TCP connection to port 443"
        Add-Finding -Severity "Error" -Source "AdminService" -Message ("TCP 443 on {0} is not reachable. In WinPE confirm networking and name resolution are up before the script runs." -f $Endpoint)
    }

    # ---- Certificate trust: the scripts send the credential only to a certificate that validates
    # on this machine or matches the pinned thumbprint
    $EndpointCert = Get-EndpointCertificate -ComputerName $Endpoint
    if ($null -eq $EndpointCert.Certificate) {
        Add-TestResult -Name "AdminService certificate" -Status "WARN" -Detail ("could not be read: {0}" -f $EndpointCert.Error)
    }
    else {
        $Cert = $EndpointCert.Certificate
        $PresentedThumbprint = ConvertTo-Thumbprint $Cert.Thumbprint
        Add-TestResult -Name "AdminService certificate" -Status "INFO" -Detail ("{0}, issued by {1}, thumbprint {2}" -f $Cert.Subject, $Cert.Issuer, $PresentedThumbprint)
        Write-Verbose ("AdminService certificate valid {0:yyyy-MM-dd} to {1:yyyy-MM-dd}; validation result: {2}" -f $Cert.NotBefore, $Cert.NotAfter, $EndpointCert.PolicyErrors)
        if ($Cert.NotAfter -lt (Get-Date)) {
            Add-TestResult -Name "AdminService certificate expiry" -Status "FAIL" -Detail ("expired {0:yyyy-MM-dd}" -f $Cert.NotAfter)
            Add-Finding -Severity "Error" -Source "AdminService" -Message ("The AdminService certificate on {0} expired on {1:yyyy-MM-dd}. Renew the IIS binding on the SMS Provider." -f $Endpoint, $Cert.NotAfter)
        }

        if ($EndpointCert.PolicyErrors -eq [System.Net.Security.SslPolicyErrors]::None) {
            Add-TestResult -Name "AdminService certificate trusted" -Status "PASS" -Detail "validates on this machine, no thumbprint needed"
        }
        else {
            $Reasons = New-Object -TypeName System.Collections.Generic.List[string]
            if ($EndpointCert.PolicyErrors -band [System.Net.Security.SslPolicyErrors]::RemoteCertificateChainErrors) {
                $ChainText = ""
                if ($EndpointCert.ChainStatus.Count -gt 0) { $ChainText = " ({0})" -f ($EndpointCert.ChainStatus -join "; ") }
                $Reasons.Add(("does not chain to a root this machine trusts{0}" -f $ChainText))
            }
            if ($EndpointCert.PolicyErrors -band [System.Net.Security.SslPolicyErrors]::RemoteCertificateNameMismatch) {
                $Reasons.Add(("its name does not match '{0}'" -f $Endpoint))
            }
            Add-TestResult -Name "AdminService certificate trusted" -Status "WARN" -Detail ($Reasons -join "; ")

            # Interactively, offer to pin what the endpoint presents. Pinning a certificate without
            # checking it would trust whoever answered, so the thumbprint is shown for comparison.
            if ([string]::IsNullOrWhiteSpace($CertificateThumbprint) -and (-not $NonInteractive)) {
                Write-Host ""
                Write-Host ("  The AdminService certificate is not trusted here, so the scripts will refuse to send the credential.") -ForegroundColor Yellow
                Write-Host ("  Presented thumbprint: {0}" -f $PresentedThumbprint) -ForegroundColor Yellow
                Write-Host ("  Compare it with the certificate bound to IIS on {0} before accepting." -f $Endpoint) -ForegroundColor Yellow
                $PinAnswer = Read-Host -Prompt "  Pin this thumbprint for this run? [y/N]"
                if ($PinAnswer -match '^(y|yes)$') { $CertificateThumbprint = $PresentedThumbprint }
            }

            if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
                Add-TestResult -Name "AdminService certificate pinned" -Status "FAIL" -Detail "no thumbprint supplied - the scripts will not send the service account credential"
                Add-Finding -Severity "Error" -Source "AdminService" -Message ("The AdminService certificate {0}. Either import the issuing root CA into the boot image (WinPE) or machine store, or re-run with -CertificateThumbprint {1} after checking it on the server. In a task sequence, set the MDMCertificateThumbprint variable." -f ($Reasons -join "; "), $PresentedThumbprint)
            }
            elseif ((ConvertTo-Thumbprint $CertificateThumbprint) -eq $PresentedThumbprint) {
                Add-TestResult -Name "AdminService certificate pinned" -Status "PASS" -Detail "matches the supplied thumbprint - the scripts will accept it"
            }
            else {
                Add-TestResult -Name "AdminService certificate pinned" -Status "FAIL" -Detail ("supplied {0}, endpoint presented {1}" -f (ConvertTo-Thumbprint $CertificateThumbprint), $PresentedThumbprint)
                Add-Finding -Severity "Error" -Source "AdminService" -Message ("The pinned thumbprint does not match the certificate {0} presents, so the scripts will refuse it. Check the IIS binding on the SMS Provider, or whether something is intercepting the connection." -f $Endpoint)
            }
        }
    }

    if ((-not [string]::IsNullOrEmpty($UserName)) -and (-not [string]::IsNullOrEmpty($Password))) {
        $ProbeThumbprint = ""
        if (($null -ne $EndpointCert) -and ($null -ne $EndpointCert.Certificate)) { $ProbeThumbprint = ConvertTo-Thumbprint $EndpointCert.Certificate.Thumbprint }
        $null = Set-ProbeCertificateValidation -Thumbprint $ProbeThumbprint
        $ProbeUri = "https://{0}/AdminService/wmi/SMS_Package?`$top=1" -f $Endpoint
        $ProbeSecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force

        # Try the user name formats in the order the scripts do: the configured value, then the
        # alternatives they fall back to after a 401 (ConfigMgr 2603+ rejects bare user names)
        $Candidates = @(Get-ScriptUserNameCandidate -Path $DriverScript -UserName $UserName -Endpoint $Endpoint -TSEnvironment $RealTSEnvironment)
        Write-Verbose ("AdminService user name formats to try: {0}" -f ($Candidates -join ", "))
        $Rejected = New-Object -TypeName System.Collections.Generic.List[string]
        $AcceptedName = $null
        $ProbeError = $null
        foreach ($Candidate in $Candidates) {
            try {
                $ProbeCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList @($Candidate, $ProbeSecurePassword)
                $ProbeSplat = @{ Uri = $ProbeUri; Method = "Get"; Credential = $ProbeCredential; ErrorAction = "Stop" }
                if ($PSVersionTable.PSVersion.Major -ge 6) { $ProbeSplat["SkipCertificateCheck"] = $true }
                $null = Invoke-RestMethod @ProbeSplat
                $AcceptedName = $Candidate
                $Script:AdminServiceCredential = $ProbeCredential
                break
            }
            catch {
                # Only a rejected credential is worth another format, exactly as in the scripts
                if ((Get-HttpStatusCode -ErrorRecord $_) -eq 401) {
                    $Rejected.Add($Candidate)
                    Write-Verbose ("AdminService rejected '{0}' (401)" -f $Candidate)
                    continue
                }
                $ProbeError = $_.Exception.Message
                break
            }
        }

        if ($null -ne $AcceptedName) {
            if ($Rejected.Count -gt 0) {
                Add-TestResult -Name "AdminService authentication" -Status "WARN" -Detail ("'{0}' was rejected (401) but '{1}' was accepted - the scripts retry the same way, so they will authenticate. Set the service account to '{1}' to skip the failed attempt" -f ($Rejected -join "', '"), $AcceptedName)
                Add-Finding -Severity "Warning" -Source "AdminService" -Message ("The configured user name '{0}' is rejected by the AdminService; the scripts recover by retrying as '{1}'. Use '{1}' in the task sequence (MDMUserName) and the harness." -f $UserName, $AcceptedName)
            }
            elseif ($AcceptedName -notmatch "@") {
                Add-TestResult -Name "AdminService authentication" -Status "WARN" -Detail ("accepted as '{0}', but it is not a UPN - ConfigMgr 2603 and later reject bare user names, so use user@domain.com before upgrading" -f $AcceptedName)
            }
            else {
                Add-TestResult -Name "AdminService authentication" -Status "PASS" -Detail ("accepted as '{0}'" -f $AcceptedName)
            }
        }
        elseif ($null -ne $ProbeError) {
            Add-TestResult -Name "AdminService authentication" -Status "FAIL" -Detail $ProbeError
            Add-Finding -Severity "Error" -Source "AdminService" -Message ("Pre-flight query to {0} failed: {1}" -f $ProbeUri, $ProbeError)
        }
        else {
            Add-TestResult -Name "AdminService authentication" -Status "FAIL" -Detail ("every user name format was rejected (401): {0}" -f ($Rejected -join ", "))
            Add-Finding -Severity "Error" -Source "AdminService" -Message ("The AdminService rejected the service account in every format the scripts try ({0}). Check the password and that the account has the required ConfigMgr role." -f ($Rejected -join ", "))
        }
    }
    else {
        Add-TestResult -Name "AdminService credentials supplied" -Status "FAIL" -Detail "DebugMode requires both -UserName and -Password"
        $TestAdminService = $false
        Add-Finding -Severity "Error" -Source "AdminService" -Message "The AdminService tests need a service account user name and password; both are mandatory parameters of the scripts' Debug parameter set."
    }
}
else {
    Add-TestResult -Name "AdminService tests" -Status "SKIP" -Detail "no endpoint supplied, or excluded by -Scope"
}

if ($TestXMLPackage) {
    if (Test-Path -Path $XMLLogicFile) {
        Add-TestResult -Name "DriverPackages.xml present" -Status "PASS" -Detail $XMLLogicFile
        try {
            $XmlDocument = [xml](Get-Content -Path $XMLLogicFile -Raw)
            $XmlPackages = @($XmlDocument.ArrayOfCMPackage.CMPackage)
            $Script:XmlPackageCatalog = $XmlPackages
            if ($XmlPackages.Count -gt 0) {
                Add-TestResult -Name "DriverPackages.xml parses" -Status "PASS" -Detail ("{0} CMPackage entries" -f $XmlPackages.Count)
            }
            else {
                Add-TestResult -Name "DriverPackages.xml parses" -Status "FAIL" -Detail "no CMPackage entries under ArrayOfCMPackage"
                Add-Finding -Severity "Error" -Source "XMLPackage" -Message "The XML logic file contains no CMPackage entries. Regenerate it from ConfigMgr Settings > Logic Package."
            }

            $XMLDriverPackageCount = @($XmlPackages | Where-Object { $_.Name -match $DriverFilter }).Count
            $XMLBIOSPackageCount = @($XmlPackages | Where-Object { $_.Name -match $BIOSFilter }).Count
            if ($XMLDriverPackageCount -gt 0) {
                Add-TestResult -Name ("XML entries matching driver filter '{0}'" -f $DriverFilter) -Status "PASS" -Detail $XMLDriverPackageCount
            }
            else {
                Add-TestResult -Name ("XML entries matching driver filter '{0}'" -f $DriverFilter) -Status "WARN" -Detail "0 - the driver matching phase will find nothing"
            }
            if ($XMLBIOSPackageCount -gt 0) {
                Add-TestResult -Name ("XML entries matching BIOS filter '{0}'" -f $BIOSFilter) -Status "PASS" -Detail $XMLBIOSPackageCount
            }
            else {
                Add-TestResult -Name ("XML entries matching BIOS filter '{0}'" -f $BIOSFilter) -Status "WARN" -Detail "0 - the BIOS matching phase will find nothing"
            }

            # Entries with an empty Description are dropped by Confirm-DriverPackage
            $NoDescription = @($XmlPackages | Where-Object { [string]::IsNullOrEmpty($_.Description) })
            if ($NoDescription.Count -gt 0) {
                Add-TestResult -Name "XML entries with a populated Description" -Status "WARN" -Detail ("{0} of {1} entries have an empty description and are filtered out during driver matching" -f $NoDescription.Count, $XmlPackages.Count)
                Add-Finding -Severity "Warning" -Source "XMLPackage" -Message ("{0} XML package entries have an empty Description. Confirm-DriverPackage discards those, and SystemSKU values are read from that field." -f $NoDescription.Count)
            }
            else {
                Add-TestResult -Name "XML entries with a populated Description" -Status "PASS"
            }

            # Show whether the requested baseboard appears anywhere in the catalog at all
            if (-not [string]::IsNullOrEmpty($SystemSKU)) {
                $SKUHits = @($XmlPackages | Where-Object { $_.Description -match [regex]::Escape($SystemSKU) })
                if ($SKUHits.Count -gt 0) {
                    Add-TestResult -Name ("Baseboard '{0}' present in the XML catalog" -f $SystemSKU) -Status "PASS" -Detail ("{0} package(s)" -f $SKUHits.Count)
                    foreach ($Hit in ($SKUHits | Select-Object -First 5)) {
                        Write-Detail ("{0} [{1}]" -f $Hit.Name, $Hit.PackageID)
                    }
                }
                else {
                    Add-TestResult -Name ("Baseboard '{0}' present in the XML catalog" -f $SystemSKU) -Status "WARN" -Detail "no package description contains this value"
                    Add-Finding -Severity "Warning" -Source "XMLPackage" -Message ("No package in the XML catalog carries baseboard '{0}' in its description. SystemSKU matching cannot succeed against this catalog." -f $SystemSKU)
                }
            }
        }
        catch {
            Add-TestResult -Name "DriverPackages.xml parses" -Status "FAIL" -Detail $_.Exception.Message
            Add-Finding -Severity "Error" -Source "XMLPackage" -Message ("The XML logic file could not be parsed: {0}" -f $_.Exception.Message)
            $TestXMLPackage = $false
        }
    }
    else {
        Add-TestResult -Name "DriverPackages.xml present" -Status "FAIL" -Detail ("not found at {0}" -f $XMLLogicFile)
        Add-Finding -Severity "Error" -Source "XMLPackage" -Message ("DriverPackages.xml was not found at {0}. In a task sequence it is pre-downloaded by a Download Package Content step mapped to MDMXMLPackage01." -f $XMLLogicFile)
        $TestXMLPackage = $false
    }
}
else {
    Add-TestResult -Name "XML package tests" -Status "SKIP" -Detail "no XML path supplied, or excluded by -Scope"
}

#endregion

#region ---- Phase 2: task sequence variables

Write-Banner "Phase 2 - Task sequence environment variables"

# Every variable the two scripts read or write, with the modes that need it.
$TSVariableMap = @(
    @{ Name = "_SMSTSLogPath"; Access = "Read"; Modes = "all modes except DebugMode"; Purpose = "directory the CMTrace log is written to"; Required = $true },
    @{ Name = "_SMSTSInWinPE"; Access = "Read"; Modes = "BareMetal"; Purpose = "confirms the WinPE phase before selecting the internal AdminService endpoint"; Required = $false },
    @{ Name = "MDMXMLPackage01"; Access = "Read"; Modes = "XMLPackage"; Purpose = "folder holding the pre-downloaded DriverPackages.xml"; Required = $true; Source = "XMLPackage" },
    @{ Name = "MDMUserName"; Access = "Read"; Modes = "AdminService (non-debug)"; Purpose = "service account for the AdminService"; Required = $true; Source = "AdminService" },
    @{ Name = "MDMPassword"; Access = "Read"; Modes = "AdminService (non-debug)"; Purpose = "service account password for the AdminService"; Required = $true; Source = "AdminService" },
    @{ Name = "MDMExternalEndpoint"; Access = "Read"; Modes = "AdminService via CMG"; Purpose = "external AdminService URL"; Required = $false },
    @{ Name = "MDMClientID"; Access = "Read"; Modes = "AdminService via CMG"; Purpose = "Entra ID application (client) ID"; Required = $false },
    @{ Name = "MDMTenantName"; Access = "Read"; Modes = "AdminService via CMG"; Purpose = "Entra ID tenant name"; Required = $false },
    @{ Name = "MDMApplicationIDURI"; Access = "Read"; Modes = "AdminService via CMG"; Purpose = "application ID URI, defaults to https://ConfigMgrService"; Required = $false },
    @{ Name = "_SMSTSMDataPath"; Access = "Read"; Modes = "download phase"; Purpose = "root of the custom download location"; Required = $false },
    @{ Name = "OSDTargetSystemDrive"; Access = "Read"; Modes = "BareMetal install phase"; Purpose = "drive DISM injects drivers into"; Required = $false },
    @{ Name = "OSDDriverPackage01"; Access = "Read"; Modes = "download phase (drivers)"; Purpose = "location of the downloaded driver package"; Required = $false },
    @{ Name = "OSDBIOSPackage01"; Access = "Read"; Modes = "download phase (BIOS)"; Purpose = "location of the downloaded BIOS package"; Required = $false },
    @{ Name = "SMSTSForceBIOSDownload"; Access = "Read"; Modes = "BIOS, optional"; Purpose = "forces a BIOS re-download when the installed version already matches"; Required = $false },
    @{ Name = "OSDDownloadDownloadPackages"; Access = "Write"; Modes = "download phase"; Purpose = "package ID handed to OSDDownloadContent.exe"; Required = $false },
    @{ Name = "OSDDownloadDestinationLocationType"; Access = "Write"; Modes = "download phase"; Purpose = "download destination type"; Required = $false },
    @{ Name = "OSDDownloadDestinationVariable"; Access = "Write"; Modes = "download phase"; Purpose = "variable receiving the download path"; Required = $false },
    @{ Name = "OSDDownloadDestinationPath"; Access = "Write"; Modes = "download phase"; Purpose = "custom download path"; Required = $false },
    @{ Name = "SMSTSDownloadRetryCount"; Access = "Write"; Modes = "download phase"; Purpose = "download retry count"; Required = $false },
    @{ Name = "OSDUpgradeStagedContent"; Access = "Write"; Modes = "OSUpgrade"; Purpose = "staged driver content for the upgrade step"; Required = $false },
    @{ Name = "NewBIOSAvailable"; Access = "Write"; Modes = "BIOS"; Purpose = "set when a newer BIOS release is matched"; Required = $false }
)

Write-Section "Variables used by the target scripts"

foreach ($Variable in $TSVariableMap) {
    $Detail = "{0} | {1} | {2}" -f $Variable.Access, $Variable.Modes, $Variable.Purpose
    # A variable that belongs to one package source is only required when that source is tested
    $SourceTested = $true
    switch ($Variable.Source) {
        "XMLPackage" { $SourceTested = $TestXMLPackage }
        "AdminService" { $SourceTested = $TestAdminService }
    }
    if ($Variable.Required -and (-not $SourceTested)) {
        if ($null -ne $RealTSEnvironment) {
            $Value = ""
            try { $Value = $RealTSEnvironment.Value($Variable.Name) } catch { }
            if (-not [string]::IsNullOrEmpty($Value)) {
                $Shown = $Value
                if ($Variable.Name -eq "MDMPassword") { $Shown = "********" }
                Add-TestResult -Name $Variable.Name -Status "INFO" -Detail ("present ({0}) | not checked - {1} is not being tested" -f $Shown, $Variable.Source)
                continue
            }
        }
        Add-TestResult -Name $Variable.Name -Status "SKIP" -Detail ("{0} is not being tested | {1}" -f $Variable.Source, $Detail)
        continue
    }
    if ($null -ne $RealTSEnvironment) {
        $Value = ""
        try { $Value = $RealTSEnvironment.Value($Variable.Name) } catch { }
        if (-not [string]::IsNullOrEmpty($Value)) {
            $Shown = $Value
            if ($Variable.Name -eq "MDMPassword") { $Shown = "********" }
            Add-TestResult -Name $Variable.Name -Status "PASS" -Detail ("present ({0})" -f $Shown)
        }
        elseif ($Variable.Access -eq "Write") {
            Add-TestResult -Name $Variable.Name -Status "INFO" -Detail ("written by the script | {0}" -f $Variable.Purpose)
        }
        elseif ($Variable.Required) {
            Add-TestResult -Name $Variable.Name -Status "FAIL" -Detail ("not set in the live task sequence | {0}" -f $Detail)
            Add-Finding -Severity "Error" -Source "TaskSequence" -Message ("Required task sequence variable '{0}' is not set: {1}." -f $Variable.Name, $Variable.Purpose)
        }
        else {
            Add-TestResult -Name $Variable.Name -Status "INFO" -Detail ("not set | {0}" -f $Detail)
        }
    }
    else {
        Add-TestResult -Name $Variable.Name -Status "INFO" -Detail $Detail
    }
}

if ($null -eq $RealTSEnvironment) {
    Write-Host ""
    Write-Detail "No live task sequence is running, so the list above is the required set rather than live readings." "DarkGray"
    Write-Detail "The harness supplies _SMSTSLogPath, MDMXMLPackage01, _SMSTSInWinPE and _SMSTSMDataPath to the simulated environment." "DarkGray"
}

#endregion

#region ---- Phase 3: device under test

Write-Banner "Phase 3 - Device under test"

$Hardware = New-DeviceProfile -Manufacturer $Manufacturer -Model $ComputerModel -SystemSKU $SystemSKU `
    -BIOSVersion $CurrentBIOSVersion -BIOSReleaseDate $CurrentBIOSReleaseDate

Write-Section "Requested"
Add-TestResult -Name "Make" -Status "INFO" -Detail $Manufacturer
if ([string]::IsNullOrEmpty($ComputerModel)) {
    Add-TestResult -Name "Model" -Status "INFO" -Detail "<not specified>"
}
else {
    Add-TestResult -Name "Model" -Status "INFO" -Detail $ComputerModel
}
if ([string]::IsNullOrEmpty($SystemSKU)) {
    Add-TestResult -Name "Baseboard / SystemSKU" -Status "INFO" -Detail "<not specified>"
}
else {
    Add-TestResult -Name "Baseboard / SystemSKU" -Status "INFO" -Detail $SystemSKU
}
Add-TestResult -Name "Target OS" -Status "INFO" -Detail ("{0} {1} {2}" -f $TargetOSName, $TargetOSVersion, $TargetOSArchitecture)
Add-TestResult -Name "Operational mode" -Status "INFO" -Detail $OperationalMode

if ([string]::IsNullOrEmpty($ComputerModel) -and [string]::IsNullOrEmpty($SystemSKU)) {
    Add-TestResult -Name "Detection input" -Status "FAIL" -Detail "neither a model nor a baseboard value was supplied"
    Add-Finding -Severity "Error" -Source "Input" -Message "Test-ComputerDetails fails closed when both the model and SystemSKU are empty. Supply at least one."
}

Write-Section "What the scripts should derive"
Add-TestResult -Name "Normalised manufacturer" -Status "INFO" -Detail $Expected.Manufacturer
Add-TestResult -Name "SystemSKU source" -Status "INFO" -Detail $Expected.SKUSource
if ([string]::IsNullOrEmpty($Expected.SystemSKU)) {
    Add-TestResult -Name "Expected SystemSKU" -Status "INFO" -Detail "<none>"
}
else {
    Add-TestResult -Name "Expected SystemSKU" -Status "INFO" -Detail $Expected.SystemSKU
}
foreach ($Note in $Expected.Notes) {
    Add-TestResult -Name "Note" -Status "WARN" -Detail $Note
}

if ($UseLocalHardware) {
    Add-TestResult -Name "Hardware source" -Status "INFO" -Detail "local WMI (hardware simulation disabled)"
}
else {
    Add-TestResult -Name "Hardware source" -Status "INFO" -Detail "simulated WMI/CIM built from the values above"
}

#endregion

#region ---- Phase 4: script execution

Write-Banner "Phase 4 - Script execution"

$SimulateHardware = (-not $UseLocalHardware)

# --- Driver script via the AdminService (DebugMode)
if ($TestDrivers) {
    Write-Section "Drivers via AdminService (DebugMode)"
    if ($TestAdminService) {
        $Parameters = @{
            DebugMode            = $true
            Endpoint             = $Endpoint
            UserName             = $UserName
            Password             = $Password
            TargetOSName         = $TargetOSName
            TargetOSVersion      = $TargetOSVersion
            TargetOSArchitecture = $TargetOSArchitecture
            OperationalMode      = $OperationalMode
            Filter               = $DriverFilter
        }
        if ((Get-ScriptValidateSet -Path $DriverScript -ParameterName "Manufacturer") -contains $Manufacturer) {
            $Parameters["Manufacturer"] = $Manufacturer
        }
        if (-not [string]::IsNullOrEmpty($ComputerModel)) { $Parameters["ComputerModel"] = $ComputerModel }
        if (-not [string]::IsNullOrEmpty($SystemSKU)) { $Parameters["SystemSKU"] = $SystemSKU }
        Add-CertificateThumbprintParameter -Parameters $Parameters -Analysis $Script:DriverAnalysis -ScriptName "Invoke-CMApplyDriverPackage.ps1"

        $Run = Invoke-TargetScript -TestName "Drivers-AdminService" -TargetScript $DriverScript -Parameters $Parameters `
            -LogFileName "ApplyDriverPackage.log" -LogDirectory $SystemTempLog -SimulateHardware $SimulateHardware -Hardware $Hardware
        Show-RunAnalysis -Run $Run -Kind "Drivers" -Expected $Expected
    }
    else {
        Add-TestResult -Name "Drivers via AdminService" -Status "SKIP" -Detail "no reachable endpoint or credentials"
    }
}

# --- Driver script via the XML logic file
if ($TestDrivers) {
    Write-Section "Drivers via XML logic file"
    if (-not $TestXMLPackage) {
        Add-TestResult -Name "Drivers via XML package" -Status "SKIP" -Detail "no XML logic file supplied"
    }
    elseif (-not $DriverSupportsXML) {
        Add-TestResult -Name "Drivers via XML package" -Status "SKIP" -Detail "the script declares no -XMLPackage parameter"
    }
    else {
        $Parameters = @{
            XMLPackage           = $true
            XMLDeploymentType    = $XMLDeploymentType
            TargetOSName         = $TargetOSName
            TargetOSVersion      = $TargetOSVersion
            TargetOSArchitecture = $TargetOSArchitecture
            OperationalMode      = $OperationalMode
            Filter               = $DriverFilter
        }
        $XMLLogDirectory = Join-Path -Path $Script:RunPath -ChildPath "Drivers_XMLPackage_Logs"
        $null = New-Item -Path $XMLLogDirectory -ItemType Directory -Force

        $TSVariables = @{
            "_SMSTSLogPath"   = $XMLLogDirectory
            "MDMXMLPackage01" = $XMLPackageFolder
            "_SMSTSInWinPE"   = "true"
            "_SMSTSMDataPath" = (Join-Path -Path $Script:RunPath -ChildPath "MDataPath")
        }

        $Run = Invoke-TargetScript -TestName "Drivers-XMLPackage" -TargetScript $DriverScript -Parameters $Parameters `
            -LogFileName "ApplyDriverPackage.log" -LogDirectory $XMLLogDirectory -TSVariables $TSVariables `
            -SimulateHardware $SimulateHardware -Hardware $Hardware
        Show-RunAnalysis -Run $Run -Kind "Drivers" -Expected $Expected -PostMatchPattern "\[DriverPackageDownload\]|Setting task sequence variable OSDDownloadDownloadPackages"
    }
}

# --- BIOS script via the AdminService (DebugMode)
if ($TestBIOS) {
    Write-Section "BIOS via AdminService (DebugMode)"
    if ($TestAdminService) {
        $Parameters = @{
            DebugMode       = $true
            Endpoint        = $Endpoint
            UserName        = $UserName
            Password        = $Password
            OperationalMode = $OperationalMode
        }
        if ((Get-ScriptValidateSet -Path $BIOSScript -ParameterName "Manufacturer") -contains $Manufacturer) {
            $Parameters["Manufacturer"] = $Manufacturer
        }
        if (-not [string]::IsNullOrEmpty($ComputerModel)) { $Parameters["ComputerModel"] = $ComputerModel }
        if (-not [string]::IsNullOrEmpty($SystemSKU)) { $Parameters["SystemSKU"] = $SystemSKU }
        Add-CertificateThumbprintParameter -Parameters $Parameters -Analysis $Script:BIOSAnalysis -ScriptName "Invoke-CMDownloadBIOSPackage.ps1"

        $Run = Invoke-TargetScript -TestName "BIOS-AdminService" -TargetScript $BIOSScript -Parameters $Parameters `
            -LogFileName "ApplyBIOSPackage.log" -LogDirectory $SystemTempLog -SimulateHardware $SimulateHardware -Hardware $Hardware
        Show-RunAnalysis -Run $Run -Kind "BIOS" -Expected $Expected
    }
    else {
        Add-TestResult -Name "BIOS via AdminService" -Status "SKIP" -Detail "no reachable endpoint or credentials"
    }
}

# --- BIOS script via the XML logic file
if ($TestBIOS) {
    Write-Section "BIOS via XML logic file"

    $BIOSTargetScript = $BIOSScript
    $CanRunBIOSXml = $BIOSSupportsXML

    if ($TestXMLPackage -and (-not $BIOSSupportsXML) -and (-not $NoPatchBIOSXml)) {
        # The shipped script cannot be invoked in XMLPackage mode. Run a patched copy from the
        # run folder so the XML matching logic is still exercised. The repository file is untouched.
        try {
            $PatchedPath = Join-Path -Path $Script:RunPath -ChildPath "Invoke-CMDownloadBIOSPackage.XMLPatched.ps1"
            $Content = Get-Content -Path $BIOSScript -Raw

            $Insert = "`t[parameter(Mandatory = `$true, ParameterSetName = `"XMLPackage`", HelpMessage = `"Set the script to operate in 'XMLPackage' deployment type mode.`")]`r`n" +
            "`t[switch]`$XMLPackage,`r`n`t`r`n"

            $Anchor = '[switch]$BIOSUpdate,'
            $AnchorIndex = $Content.IndexOf($Anchor)
            if ($AnchorIndex -lt 0) { throw "Could not locate the -BIOSUpdate switch to anchor the patch." }
            $InsertionPoint = $Content.IndexOf("`n", $AnchorIndex) + 1
            $Patched = $Content.Substring(0, $InsertionPoint) + "`r`n" + $Insert + $Content.Substring($InsertionPoint)

            # Filter and OperationalMode are not declared for the XMLPackage set; add them so
            # Get-BIOSPackages can filter XML entries the way it does for the AdminService.
            # Attribute order within a parameter declaration is not significant, so the extra
            # [parameter()] attribute is inserted immediately before a unique anchor line.
            $XMLAttribute = "[parameter(Mandatory = `$false, ParameterSetName = `"XMLPackage`")]`r`n`t"
            foreach ($Anchor in @('[string]$Filter = "BIOS",', '[ValidateSet("Production", "Pilot")]')) {
                if ($Patched.IndexOf($Anchor) -lt 0) { throw ("Could not locate the patch anchor: {0}" -f $Anchor) }
                $Patched = $Patched.Replace($Anchor, ($XMLAttribute + $Anchor))
            }

            Set-Content -Path $PatchedPath -Value $Patched -Encoding UTF8

            $PatchAnalysis = Get-ScriptParameterSets -Path $PatchedPath
            if ($PatchAnalysis.ParseErrors.Count -gt 0) {
                Add-TestResult -Name "BIOS XMLPackage patched copy" -Status "FAIL" -Detail ("the patched copy does not parse ({0} error(s))" -f $PatchAnalysis.ParseErrors.Count)
            }
            elseif (-not $PatchAnalysis.Parameters.ContainsKey("XMLPackage")) {
                Add-TestResult -Name "BIOS XMLPackage patched copy" -Status "FAIL" -Detail "the -XMLPackage parameter was not added"
            }
            else {
                Add-TestResult -Name "BIOS XMLPackage patched copy" -Status "WARN" -Detail ("running a patched copy from {0} - the repository script is unchanged" -f $PatchedPath)
                $BIOSTargetScript = $PatchedPath
                $CanRunBIOSXml = $true
            }
        }
        catch {
            Add-TestResult -Name "BIOS XMLPackage patched copy" -Status "FAIL" -Detail $_.Exception.Message
        }
    }

    if (-not $TestXMLPackage) {
        Add-TestResult -Name "BIOS via XML package" -Status "SKIP" -Detail "no XML logic file supplied"
    }
    elseif (-not $CanRunBIOSXml) {
        Add-TestResult -Name "BIOS via XML package" -Status "SKIP" -Detail "the script cannot be invoked in XMLPackage mode"
    }
    else {
        $Parameters = @{
            XMLPackage      = $true
            OperationalMode = $OperationalMode
            Filter          = $BIOSFilter
        }
        $XMLLogDirectory = Join-Path -Path $Script:RunPath -ChildPath "BIOS_XMLPackage_Logs"
        $null = New-Item -Path $XMLLogDirectory -ItemType Directory -Force

        $TSVariables = @{
            "_SMSTSLogPath"   = $XMLLogDirectory
            "MDMXMLPackage01" = $XMLPackageFolder
            "_SMSTSInWinPE"   = "true"
            "_SMSTSMDataPath" = (Join-Path -Path $Script:RunPath -ChildPath "MDataPath")
        }

        $Run = Invoke-TargetScript -TestName "BIOS-XMLPackage" -TargetScript $BIOSTargetScript -Parameters $Parameters `
            -LogFileName "ApplyBIOSPackage.log" -LogDirectory $XMLLogDirectory -TSVariables $TSVariables `
            -SimulateHardware $SimulateHardware -Hardware $Hardware
        Show-RunAnalysis -Run $Run -Kind "BIOS" -Expected $Expected -PostMatchPattern "Setting task sequence variable OSDDownloadDownloadPackages"
    }
}

#endregion

#region ---- Phase 5: summary

Write-Banner "Summary"

$Counts = @{}
foreach ($Status in @("PASS", "FAIL", "WARN", "INFO", "SKIP")) {
    $Counts[$Status] = @($Script:Results | Where-Object { $_.Status -eq $Status }).Count
}

Write-Host ""
Write-Host ("  Passed   : {0}" -f $Counts["PASS"]) -ForegroundColor Green
if ($Counts["FAIL"] -gt 0) {
    Write-Host ("  Failed   : {0}" -f $Counts["FAIL"]) -ForegroundColor Red
}
else {
    Write-Host ("  Failed   : 0") -ForegroundColor Green
}
if ($Counts["WARN"] -gt 0) {
    Write-Host ("  Warnings : {0}" -f $Counts["WARN"]) -ForegroundColor Yellow
}
else {
    Write-Host ("  Warnings : 0") -ForegroundColor Green
}
Write-Host ("  Skipped  : {0}" -f $Counts["SKIP"]) -ForegroundColor DarkGray

if ($Script:MatchedPackages.Count -gt 0) {
    # Fit the console; a redirected or host-less run has no usable width, so fall back to 160
    $TableWidth = 160
    try {
        $ConsoleWidth = $Host.UI.RawUI.BufferSize.Width
        if ($ConsoleWidth -ge 60) { $TableWidth = $ConsoleWidth - 4 }
    }
    catch { }
    Write-Host ""
    Write-Host "  Matched packages:" -ForegroundColor White
    foreach ($Line in ((Format-MatchedPackageTable -Width $TableWidth) -split "`r?`n")) {
        $Colour = "Gray"
        if ($Line -match "\(no match\)") { $Colour = "Red" }
        Write-Host ("  {0}" -f $Line) -ForegroundColor $Colour
    }
}

$Failures = @($Script:Results | Where-Object { $_.Status -eq "FAIL" })
if ($Failures.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($Failure in $Failures) {
        if ($Failure.Detail) {
            Write-Host ("    - [{0}] {1} : {2}" -f $Failure.Phase, $Failure.Name, $Failure.Detail) -ForegroundColor Red
        }
        else {
            Write-Host ("    - [{0}] {1}" -f $Failure.Phase, $Failure.Name) -ForegroundColor Red
        }
    }
}

$ErrorFindings = @($Script:Findings | Where-Object { $_.Severity -eq "Error" })
$WarningFindings = @($Script:Findings | Where-Object { $_.Severity -eq "Warning" })

if ($ErrorFindings.Count -gt 0) {
    Write-Host ""
    Write-Host "  Errors highlighted:" -ForegroundColor Red
    foreach ($Finding in $ErrorFindings) {
        Write-Host ("    - [{0}] {1}" -f $Finding.Source, $Finding.Message) -ForegroundColor Red
    }
}
if ($WarningFindings.Count -gt 0) {
    Write-Host ""
    Write-Host "  Warnings highlighted:" -ForegroundColor Yellow
    foreach ($Finding in $WarningFindings) {
        Write-Host ("    - [{0}] {1}" -f $Finding.Source, $Finding.Message) -ForegroundColor Yellow
    }
}

# ---- Written report
$ReportPath = Join-Path -Path $Script:RunPath -ChildPath "TestReport.txt"
$Report = New-Object -TypeName System.Text.StringBuilder
$null = $Report.AppendLine("Modern Driver / BIOS Management - Test Report")
$null = $Report.AppendLine(("Generated : {0}" -f (Get-Date)))
$null = $Report.AppendLine(("Host      : {0} (WinPE: {1}, PowerShell {2})" -f $env:COMPUTERNAME, $Script:IsWinPE, $PSVersionTable.PSVersion))
$null = $Report.AppendLine(("Make      : {0}" -f $Manufacturer))
$null = $Report.AppendLine(("Model     : {0}" -f $ComputerModel))
$null = $Report.AppendLine(("Baseboard : {0}" -f $SystemSKU))
$null = $Report.AppendLine(("Target OS : {0} {1} {2}" -f $TargetOSName, $TargetOSVersion, $TargetOSArchitecture))
$null = $Report.AppendLine(("Scope     : {0} / {1}" -f $Scope, $Component))
$null = $Report.AppendLine("")
$null = $Report.AppendLine("Results")
$null = $Report.AppendLine("-------")
foreach ($Result in $Script:Results) {
    if ($Result.Detail) {
        $null = $Report.AppendLine(("[{0,-4}] [{1}] {2} : {3}" -f $Result.Status, $Result.Phase, $Result.Name, $Result.Detail))
    }
    else {
        $null = $Report.AppendLine(("[{0,-4}] [{1}] {2}" -f $Result.Status, $Result.Phase, $Result.Name))
    }
}
$null = $Report.AppendLine("")
$null = $Report.AppendLine("Matched packages")
$null = $Report.AppendLine("----------------")
if ($Script:MatchedPackages.Count -eq 0) {
    $null = $Report.AppendLine("None - no package matching test ran.")
}
else {
    $null = $Report.AppendLine((Format-MatchedPackageTable -Width 250))
}
$null = $Report.AppendLine("")
$null = $Report.AppendLine("Findings")
$null = $Report.AppendLine("--------")
if ($Script:Findings.Count -eq 0) {
    $null = $Report.AppendLine("None.")
}
else {
    foreach ($Finding in $Script:Findings) {
        $null = $Report.AppendLine(("{0}: [{1}] {2}" -f $Finding.Severity.ToUpper(), $Finding.Source, $Finding.Message))
    }
}
Set-Content -Path $ReportPath -Value $Report.ToString() -Encoding UTF8

Write-Host ""
Write-Host ("  Report     : {0}" -f $ReportPath) -ForegroundColor Cyan
Write-Host ("  Run folder : {0}" -f $Script:RunPath) -ForegroundColor Cyan
Write-Host "  Each test's captured CMTrace log and stdout are in its own subfolder." -ForegroundColor DarkGray
if ($Script:TranscriptStarted) { Write-Host ("  Console log: {0}" -f $Script:HarnessLogPath) -ForegroundColor Cyan }
Write-Host ""

Stop-HarnessTranscript
if ($Counts["FAIL"] -gt 0) { exit 1 }
exit 0

#endregion
