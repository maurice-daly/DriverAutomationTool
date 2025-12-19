<#	
	===========================================================================
	 Created on:   	04/08/2024 16:48
	 Udated on:   	19/12/2025 16:48
	 Created by:   	MauriceDaly
	 Organization: 	MSEndpointMgr / Patch My PC
	 Filename:     	DriverAutomationCore.psm1
	-------------------------------------------------------------------------
	 Module Name:  	DriverAutomationToolCore
	 Purpose:      	Core functions for Driver Automation Tool
	-------------------------------------------------------------------------
	 Version:      	1.0.18.0
	 License:      	MIT License

	===========================================================================
#>

# Requires TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-DATScriptDirectory {
	<#
	.SYNOPSIS
		Get-ScriptDirectory returns the proper location of the script.

	.OUTPUTS
		System.String
	
	.NOTES
		Returns the correct path within a packaged executable.
#>
	[OutputType([string])]
	param ()
	if ($null -ne $hostinvocation) {
		Split-Path $hostinvocation.MyCommand.path
	} else {
		Split-Path $script:MyInvocation.MyCommand.Path
	}
}

# Global variables

#region Variables

# Script Build Numbers
[version]$global:ScriptRelease = "1.0.18.0"
$global:ScriptBuildDate = "19-12-2024"
[version]$global:NewRelease = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data//DriverAutomationToolRev.txt" -UseBasicParsing).Content
$global:ReleaseNotesURL = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/DriverAutomationToolNotes.txt"
$OEMLinksURL = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/OEMLinks.xml"

# Path variables
Write-Verbose -Message "[Driver Automation Tool Running] - Running version is $global:ScriptRelease"
[string]$global:RegPath = "HKLM:\SOFTWARE\MSEndpointMgr\DriverAutomationTool"
Write-Verbose -Message "- Registry path is $global:RegPath"

# Check for installation path from registry
if ([boolean](Test-Path -Path $global:RegPath -ErrorAction SilentlyContinue) -eq $true) {
	$global:ScriptDirectory = (Get-ItemProperty -Path $global:RegPath).InstallDirectory
	Write-Verbose -Message "Script directory is $global:ScriptDirectory"
} else {
	$global:ScriptDirectory = Get-DATScriptDirectory
}
# If running in as a standalone module, set the script directory
if ([string]::IsNullOrEmpty($global:ScriptDirectory) -or $global:ScriptDirectory -like "C:\Windows\Temp*") {
	[string]$global:ScriptDirectory = Join-Path -Path $env:SystemDrive -ChildPath "Program Files\MSEndpointMgr\Driver Automation Tool"
}

# Update registry with install directory
Set-DATRegistryValue -Name "InstallDirectory" -Type String -Value "$global:ScriptDirectory"

Write-Verbose -Message "Script directory is $global:ScriptDirectory"
[string]$global:TempDirectory = Join-Path -Path $global:ScriptDirectory -ChildPath "Temp"
[string]$global:ProductName = "DriverAutomationTool"
[string]$global:SettingsDirectory = Join-Path -Path $global:ScriptDirectory -ChildPath "Settings"
[string]$global:LogDirectory = Join-Path -Path $global:ScriptDirectory -ChildPath "Logs"
[string]$global:ToolsDirectory = Join-Path -Path $global:ScriptDirectory -ChildPath "Tools"

#endregion Variables

# region CoreRequirements

# Create Registry Key
if ([boolean](Test-Path -Path $global:RegPath -ErrorAction SilentlyContinue) -eq $false) {
	Write-Verbose -Message "Creating registry key at path $global:RegPath"
	New-Item -Path $global:RegPath -ItemType directory | Out-Null
}

# Set Running Version in Registry
Set-DATRegistryValue -Name "RunningVersion" -Type String -Value "$global:ScriptRelease"

# Create Temp Directory
if ([boolean](Test-Path -Path $global:TempDirectory -ErrorAction SilentlyContinue) -eq $false) {
	Write-Verbose -Message "Creating temp directory at path $global:TempDirectory"
	New-Item -Path $global:TempDirectory -ItemType dir | Out-Null
	Set-DATRegistryValue -Name "TempDirectory" -Type String -Value "$global:TempDirectory"
}

# Create Settings Directory
if ([boolean](Test-Path -Path $global:SettingsDirectory -ErrorAction SilentlyContinue) -eq $false) {
	Write-Verbose -Message "Creating settings directory at path $global:SettingsDirectory"
	New-Item -Path $global:SettingsDirectory -ItemType dir | Out-Null
	Set-DATRegistryValue -Name "SettingsDirectory" -Type String -Value "$global:SettingsDirectory"
}

# Create Log Directory
if ([boolean](Test-Path -Path $global:LogDirectory -ErrorAction SilentlyContinue) -eq $false) {
	Write-Verbose -Message "Creating log directory at path $global:LogDirectory"
	New-Item -Path $global:LogDirectory -ItemType dir | Out-Null
	Set-DATRegistryValue -Name "LogDirectory" -Type String -Value "$global:LogDirectory"
}


Write-Host "- Writing logs to $($global:LogDirectory)"

# endregion CoreRequirements

# region Functions

<#
	.SYNOPSIS
		A brief description of the Write-LogEntry function.
	
	.DESCRIPTION
		A detailed description of the Write-LogEntry function.
	
	.PARAMETER Value
		Value added to the log file.
	
	.PARAMETER Severity
		Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.
	
	.PARAMETER LogFileName
		Name of the log file that the entry will written to.
	
	.PARAMETER UpdateUI
		Updates a custom UI if running and true value set against the log entry
	
	.PARAMETER FileName
		Name of the log file that the entry will written to.
	
	.EXAMPLE
		PS C:\> Write-LogEntry -Value 'Value1' -Severity 1
	
	.NOTES
		Additional information about the function.
#>
function global:Write-DATLogEntry {
	param
	(
		[Parameter(Mandatory = $true,
			HelpMessage = 'Value added to the log file.')]
		[ValidateNotNullOrEmpty()]
		[string]$Value,
		[Parameter(Mandatory = $false,
			HelpMessage = 'Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.')]
		[ValidateSet('1', '2', '3')]
		[ValidateNotNullOrEmpty()]
		[string]$Severity = '1',
		[Parameter(Mandatory = $false,
			HelpMessage = 'Name of the log file that the entry will written to.')]
		[ValidateNotNullOrEmpty()]
		[string]$LogFileName = "$global:ProductName.log",
		[switch]$UpdateUI
	)
	
	# Determine log file location
	$script:LogFilePath = Join-Path -Path $global:LogDirectory -ChildPath $LogFileName
	
	# Check log file size and rotate if needed (10MB limit)
	$MaxLogSizeBytes = 10MB
	if (Test-Path -Path $script:LogFilePath) {
		$LogFileSize = (Get-Item -Path $script:LogFilePath).Length
		if ($LogFileSize -ge $MaxLogSizeBytes) {
			try {
				# Create archive log name with timestamp
				$ArchiveLogName = "$($LogFileName.TrimEnd('.log'))_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
				$ArchiveLogPath = Join-Path -Path $global:LogDirectory -ChildPath $ArchiveLogName
				
				# Move current log to archive
				Move-Item -Path $script:LogFilePath -Destination $ArchiveLogPath -Force
				
				# Optionally: Keep only last 5 archived logs
				$ArchivedLogs = Get-ChildItem -Path $global:LogDirectory -Filter "$($LogFileName.TrimEnd('.log'))_*.log" | 
				Sort-Object LastWriteTime -Descending | 
				Select-Object -Skip 5
				if ($ArchivedLogs) {
					$ArchivedLogs | Remove-Item -Force
				}
			} catch {
				# If rotation fails, continue with logging to avoid breaking functionality
				Write-Warning "Failed to rotate log file: $($_.Exception.Message)"
			}
		}
	}
	
	# Construct time stamp for log entry
	$Time = -join @((Get-Date -Format "HH:mm:ss.fff"), " ", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
	
	# Construct date for log entry
	$Date = (Get-Date -Format "MM-dd-yyyy")
	
	# Construct context for log entry
	$Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
	
	# Construct final log entry
	$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""$global:ProductName"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
	
	# Add value to log file
	try {
		Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
		if ($Severity -eq 1) {
			Write-Verbose -Message $Value
		} elseif ($Severity -eq 3) {
			Write-Warning -Message $Value
		}
		
		if ($UpdateUI) {
			switch ($Severity) {
				"1" {
					if ((Get-ItemProperty -Path $global:RegPath).RunningState -ne "Running") {
						Set-DATRegistryValue -Name "RunningState" -Type String -Value "Running" -Verbose
					} elseif ($Value -like "*Imaging Completed*") {
						Set-DATRegistryValue -Name "RunningState" -Type String -Value "Completed" -Verbose
					}
				}
				"3" {
					if ((Get-ItemProperty -Path $global:RegPath).RunningState -ne "Error") {
						Set-DATRegistryValue -Name "RunningState" -Type String -Value "Error"
						
					}
				}
			}
			$TrimedValue = $Value.TrimStart("- ")
			Set-DATRegistryValue -Name "RunningMessage" -Type String -Value $TrimedValue -Verbose
			
			Start-Sleep -Seconds 1
		}
	} catch [System.Exception] {
		Write-Warning -Message "Unable to append log entry to $global:ProductName.log file. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
	}
}

<#
	.SYNOPSIS
		A brief description of the Get-OEMSources function.
	
	.DESCRIPTION
		This function loads in the OEM sources from a control file in GitHub
	
	.EXAMPLE
				PS C:\> Get-OEMSources
	
	.NOTES
		Additional information about the function.
#>
function Get-DATOEMSources {
	[CmdletBinding()]
	param ()
	
	try {
		Write-DATLogEntry -Value "[OEM Source Check] - Testing path $global:SettingsDirectory" -Severity 1 -UpdateUI
		$global:OEMXMLPath = Join-Path $global:SettingsDirectory -ChildPath "OEMLinks.xml"
		if (-not ([boolean](Test-Path -Path $OEMXMLPath -ErrorAction SilentlyContinue) -eq $true)) {
			Write-DATLogEntry -Value "- OEM Links: Downloading OEMLinks XML from $OEMLinksURL" -Severity 1 -UpdateUI
			(Invoke-WebRequest -Uri "$OEMLinksURL" -UseBasicParsing).Content | Out-File -FilePath $OEMXMLPath
			[xml]$OEMLinks = Get-Content -Path $OEMXMLPath
		} else {
			[version]$OEMCurrenVersion = ([XML]((Invoke-WebRequest -Uri "$OEMLinksURL" -UseBasicParsing).Content)).OEM.Version
			[version]$OEMDownloadedVersion = ([XML](Get-Content -Path $OEMXMLPath)).OEM.Version
			Write-DATLogEntry -Value "- Comparing online to locally available version" -Severity 1 -UpdateUI
			if ($OEMDownloadedVersion -lt $OEMCurrenVersion) {
				Write-DATLogEntry -Value "- OEM Links: Downloading updated OEMLinks XML ($OEMCurrenVersion)" -Severity 1 -UpdateUI
				(Invoke-WebRequest -Uri "$OEMLinksURL" -UseBasicParsing).Content | Out-File -FilePath $OEMXMLPath -Force
			}
		}
		Write-DATLogEntry -Value "- OEM Links: Reading OEMLinks XML from $OEMXMLPath" -Severity 1 -UpdateUI
		[xml]$OEMLinks = Get-Content -Path $OEMXMLPath
		
		# Set OEM variables
		
		if ($OEMLinks -gt $null) {
			
			# // =================== DELL Variables ================ //
			Write-DATLogEntry -Value "- Setting Dell variables" -Severity 1
			
			# Define Dell Download Sources
			$global:DellDownloadList = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "DownloadList" } | Select-Object -ExpandProperty URL
			$global:DellDownloadBase = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "DownloadBase" } | Select-Object -ExpandProperty URL
			$global:DellDriverListURL = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "DriversList" } | Select-Object -ExpandProperty URL
			$global:DellBaseURL = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "BaseURL" } | Select-Object -ExpandProperty URL
			$global:Dell64BIOSUtil = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "BIOSUtility" } | Select-Object -ExpandProperty URL
			
			# Define Dell Download Sources
			$DellXMLCabinetSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "XMLCabinetSource" } | Select-Object -ExpandProperty URL
			$DellCatalogSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "CatalogSource" } | Select-Object -ExpandProperty URL
			
			# Define Dell Cabinet/XL Names and Paths
			$DellCabFile = [string]($DellXMLCabinetSource | Split-Path -Leaf)
			$DellCatalogFile = [string]($DellCatalogSource | Split-Path -Leaf)
			$DellXMLFile = $DellCabFile.TrimEnd(".cab")
			$DellXMLFile = $DellXMLFile + ".xml"
			$DellCatalogXMLFile = $DellCatalogFile.TrimEnd(".cab") + ".xml"
			$DellFlashExtracted = $false
			
			# Define Dell Global Variables
			New-Variable -Name "DellCatalogXML" -Value $null -Scope Global
			New-Variable -Name "DellModelXML" -Value $null -Scope Global
			New-Variable -Name "DellModelCabFiles" -Value $null -Scope Global
						
			# Define HP Download Sources
			$HPXMLCabinetSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "HP" }).Link | Where-Object { $_.Type -eq "XMLCabinetSource" } | Select-Object -ExpandProperty URL
			$HPSoftPaqSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "HP" }).Link | Where-Object { $_.Type -eq "SoftPaqSource" } | Select-Object -ExpandProperty URL
			$HPPlatFormList = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "HP" }).Link | Where-Object { $_.Type -eq "PlatFormList" } | Select-Object -ExpandProperty URL
			$HPSoftPaqCab = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "HP" }).Link | Where-Object { $_.Type -eq "SoftPaqCab" } | Select-Object -ExpandProperty URL
			
			# Define HP Cabinet/XL Names and Paths
			$HPCabFile = [string]($HPXMLCabinetSource | Split-Path -Leaf)
			$HPXMLFile = $HPCabFile.TrimEnd(".cab")
			$HPXMLFile = $HPXMLFile + ".xml"
			
			# Content path
			$HPXMLFilePath = Join-Path -Path $global:TempDirectory -ChildPath $HPXMLFile
			
			# // =================== LENOVO VARIABLES ================ //
			Write-DATLogEntry -Value "- Setting Lenovo variables" -Severity 1
			
			# Define Lenovo Download Sources
			$LenovoXMLSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Lenovo" }).Link | Where-Object { $_.Type -eq "XMLSource" } | Select-Object -ExpandProperty URL
			$LenovoBIOSBase = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Lenovo" }).Link | Where-Object { $_.Type -eq "BIOSBase" } | Select-Object -ExpandProperty URL
			$LenovoXMLCabFile = $LenovoXMLSource | Split-Path -Leaf
			$LenovoXMLFile = [string]($LenovoXMLSource | Split-Path -Leaf)
			
			# Define Lenovo Global Variables
			New-Variable -Name "LenovoModelDrivers" -Value $null -Scope Global
			New-Variable -Name "LenovoModelXML" -Value $null -Scope Global
			New-Variable -Name "LenovoModelType" -Value $null -Scope Global
			New-Variable -Name "LenovoSystemSKU" -Value $null -Scope Global
			
			# // =================== MICROSOFT VARIABLES ================ //
			Write-DATLogEntry -Value "- Setting Microsoft variables" -Severity 1
			# Define Microsoft Download Sources
			$MicrosoftJSONSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Microsoft" }).Link | Where-Object { $_.Type -eq "JSONSource" } | Select-Object -ExpandProperty URL
			$MicrosoftBaseURL = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Microsoft" }).Link | Where-Object { $_.Type -eq "BaseURL" } | Select-Object -ExpandProperty URL
			$MicrosoftSurfaceDriverSupportURL = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Microsoft" }).Link | Where-Object { $_.Type -eq "SurfaceDriverSupportURL" } | Select-Object -ExpandProperty URL
			
			# // =================== COMMON VARIABLES ================ //
			# ArrayList to store models in
			$DellProducts = New-Object -TypeName System.Collections.ArrayList
			$DellKnownProducts = New-Object -TypeName System.Collections.ArrayList
			$HPProducts = New-Object -TypeName System.Collections.ArrayList
			$HPKnownProducts = New-Object -TypeName System.Collections.ArrayList
			$LenovoProducts = New-Object -TypeName System.Collections.ArrayList
			$LenovoKnownProducts = New-Object -TypeName System.Collections.ArrayList
			$MicrosoftModels = New-Object -TypeName System.Collections.ArrayList
			$MicrosoftKnownProducts = New-Object -TypeName System.Collections.ArrayList
			$XMLSelectedModels = New-Object System.Collections.Generic.List[System.Object]
			$XMLSelectedDPs = New-Object System.Collections.Generic.List[System.Object]
			$XMLSelectedDPGs = New-Object System.Collections.Generic.List[System.Object]
		} else {
			Write-DATLogEntry -Value "[Fatal Error] - Unable to read OEM links XML" -Severity 3
		}
		
	} catch {
		Write-DATLogEntry -Value "[XML Source Error] - $($_.Exception.Message)" -Severity 3
	}
}

function Find-DATLenovoModelType {
	param (
		[parameter(Mandatory = $false, HelpMessage = "Enter Lenovo model to query")]
		[string]$Model,
		[parameter(Mandatory = $false, HelpMessage = "Enter Operating System")]
		[string]$OS,
		[parameter(Mandatory = $false, HelpMessage = "Enter Lenovo model type to query")]
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


<#
	.SYNOPSIS
		Obtains supported model and OS information
	
	.DESCRIPTION
		A detailed description of the Get-OEMDownloadLinks function.
	
	.PARAMETER RequiredOEMs
		Specify the OEM to match against.
	
	.PARAMETER OS
		A description of the OS parameter.
	
	.PARAMETER Architecture
		A description of the Architecture parameter.
	
	.PARAMETER OS Build
		A description of the OS Build parameter.
	
	.EXAMPLE
		PS C:\> Add-DriverPreStagedPkg
	
	.NOTES
		Additional information about the function.
#>
function Get-DATOEMModelInfo {
	[CmdletBinding()]
	param
	(
		[Parameter(Position = 1)]
		[ValidateSet('HP', 'Dell', 'Lenovo', 'Microsoft', 'Acer')]
		[array]$RequiredOEMs,
		[Parameter(Position = 2)]
		[ValidateNotNullOrEmpty()]
		[ValidateSet('Windows 11 25H2', 'Windows 11 24H2', 'Windows 11 23H2', 'Windows 11 22H2', 'Windows 11', 'Windows 10 22H2')]
		[string]$OS,
		[Parameter(Position = 3)]
		[ValidateSet('x64', 'x86', 'Arm64')]
		[string]$Architecture
	)
	
	# Call source link function
	Write-DATLogEntry -Value "[OEM Links] - Reading OEM links" -Severity 1
	
	$OEMLinksURL = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/OEMLinks.xml"
	
	# OEM Links Master File
	try {
		Write-DATLogEntry -Value "[OEM Links Check] - Reading OEM links from $OEMLinksURL " -Severity 1
		[xml]$OEMLinks = (Invoke-WebRequest -Uri "$OEMLinksURL" -UseBasicParsing).Content
	} catch {
		Write-DATLogEntry -Value "[Error] - An error occured while attepting to read in the OEM links XML" -Severity 3 -UpdateUI
		Write-DATLogEntry -Value "- Raw message detail - `"$($_.Exception.Message)`"" -Severity 3 -UpdateUI
	}
	
	# Set Temp & Log Location	
	if ((Test-Path -Path $global:TempDirectory) -eq $false) {
		Write-DATLogEntry -Value "- Creating temp directory at path $global:TempDirectory" -Severity 1
		New-Item -Path $global:TempDirectory -ItemType dir | Out-Null
	}
	
	# Split OS Name
	#Write-Host "Selected OS is $($OSList.Text)"
	$WindowsBuild = $($OS).Split(" ")[2]
	$WindowsVersion = $OS.Trim("$WindowsBuild").TrimEnd()
	
	Write-DATLogEntry -Value "- Windows build is $WindowsBuild and version is $WindowsVersion" -Severity 1
	
	# Create supported model array
	$OEMSupportedModels = @()
	
	if ($OEMSupportedModels.Count -gt 0) {
		# Clear array
		$OEMSupportedModels.Clear()
	}
	
	foreach ($OEM in $RequiredOEMs) {
		Write-DATLogEntry -Value "- Loading $OEM model compatibility" -Severity 1
		switch ($OEM) {
			"HP" {
				# Set OEM Name
				$OEM = "HP"
				
				# Import required OEM PS module(s)
				try {
					# Import HP CMSL module
					Import-Module HPCMSL
				} catch [System.Exception] {
					Write-DATLogEntry -Value "[Error] - An error occured while attempting to import the required HP PS module" -Severity 3 -UpdateUI
					Write-DATLogEntry -Value "- Raw message detail - `"$($_.Exception.Message)`"" -Severity 3 -UpdateUI
				}
				
				# Define HP Download Sources
				$HPXMLCabinetSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "HP" }).Link | Where-Object { $_.Type -eq "XMLCabinetSource" } | Select-Object -ExpandProperty URL
				$HPSoftPaqSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "HP" }).Link | Where-Object { $_.Type -eq "SoftPaqSource" } | Select-Object -ExpandProperty URL
				$HPPlatFormList = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "HP" }).Link | Where-Object { $_.Type -eq "PlatFormList" } | Select-Object -ExpandProperty URL
				$HPSoftPaqCab = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "HP" }).Link | Where-Object { $_.Type -eq "SoftPaqCab" } | Select-Object -ExpandProperty URL
				
				# Define HP Cabinet/XL Names and Paths
				$HPCabFile = [string]($HPXMLCabinetSource | Split-Path -Leaf)
				$HPXMLFile = $HPCabFile.TrimEnd(".cab")
				$HPXMLFile = $HPXMLFile + ".xml"
				
				# Content path
				$HPXMLFilePath = Join-Path -Path $global:TempDirectory -ChildPath $HPXMLFile
				
				if ($HPModelSoftPaqs -eq $null) {
					# Download HP product catalog
					try {
						Write-DATLogEntry -Value "- Downloading $HPXMLCabinetSource" -Severity 1
						Invoke-DATContentDownload -DownloadURL $HPXMLCabinetSource -DownloadDestination $global:TempDirectory
						Write-DATLogEntry -Value "- Download background job state is $($global:DownloadBackgroundJob.State)" -Severity 1						
						Write-DATLogEntry -Value "- Expanding cabinet file $($global:TempDirectory)\$($HPCabFile)" -Severity 1
						Write-DATLogEntry -Value "- Destintation $($global:TempDirectory)" -Severity 1
						Expand "$global:TempDirectory\$HPCabFile" -F:* "$global:TempDirectory" -R | Out-Null
						$HPModelXMLPath = $(Join-Path -Path $global:TempDirectory -ChildPath $HPXMLFile)
						Write-DATLogEntry -Value "- Reading cabinet file from $HPModelXMLPath" -Severity 1
						[xml]$HPModelXML = Get-Content -Path "$HPModelXMLPath" -Raw
						$HPModelSoftPaqs = $HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
						Write-DATLogEntry -Value "- A total of $(($HPModelSoftPaqs | Select-Object SystemName).Count) models identified" -Severity 1
						Write-DATLogEntry -Value "- Outputting supported model information file" -Severity 1
						$HPModelSoftPaqs | Select-Object SystemName, SystemId | ConvertTo-Json | Out-File -FilePath $(Join-Path -Path $global:TempDirectory -ChildPath "HPModelMetadata.json") -Encoding ascii -Force
					} catch [System.Exception] {
						Write-DATLogEntry -Value "[Error] - An error occured while attempting to obtain a list of HP models" -Severity 3 -UpdateUI
						Write-DATLogEntry -Value "- Raw message detail - `"$($_.Exception.Message)`"" -Severity 3 -UpdateUI
					}
				}
				
				if ($HPModelSoftPaqs -ne $null) {
					# Create new array
					Write-DATLogEntry -Value "- Creating array for HP device matching" -Severity 1
					$HPOSSupportedPacks = New-Object -TypeName System.Collections.ArrayList
					
					# Create smaller array of supported products
					Write-DATLogEntry -Value "- Adding drivers for $WindowsVersion $WindowsBuild to array" -Severity 1
					
					$HPOSSupportedPacks = $HPModelSoftPaqs | Where-Object { $_.OSName -match $WindowsVersion -and $_.OSName -match $WindowsBuild }
					Write-DATLogEntry -Value "- Adding a total of $($HPOSSupportedPacks.Count) supported driver packages" -Severity 1
					foreach ($Model in $HPOSSupportedPacks) {
						
						# Remove HP from model name
						$Model.SystemName = $($($Model.SystemName).TrimStart($OEM)).Trim()
						
						# Update array
						$ModelDetails = New-Object -TypeName PSObject
						$ModelDetails | Add-Member -MemberType NoteProperty -Name "OEM" -Value "$OEM" -Force
						$ModelDetails | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($Model.SystemName)" -Force
						$ModelDetails | Add-Member -MemberType NoteProperty -Name "Baseboards" -Value "$($Model.SystemId)" -Force
						$ModelDetails | Add-Member -MemberType NoteProperty -Name "OS" -Value "$WindowsVersion" -Force
						$ModelDetails | Add-Member -MemberType NoteProperty -Name "OS Build" -Value "$WindowsBuild" -Force
						
						$OEMSupportedModels += $ModelDetails
					}
				}
			}
			"Dell" {
				# Download Dell product catalog
				try {
					# Set variables
					$OEM = "Dell"
					
					# Define Dell Download Sources
					$DellDownloadList = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "DownloadList" } | Select-Object -ExpandProperty URL
					$DellDownloadBase = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "DownloadBase" } | Select-Object -ExpandProperty URL
					$DellDriverListURL = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "DriversList" } | Select-Object -ExpandProperty URL
					$DellBaseURL = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "BaseURL" } | Select-Object -ExpandProperty URL
					$Dell64BIOSUtil = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "BIOSUtility" } | Select-Object -ExpandProperty URL
					
					# Define Dell Download Sources
					$DellXMLCabinetSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "XMLCabinetSource" } | Select-Object -ExpandProperty URL
					$DellCatalogSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Dell" }).Link | Where-Object { $_.Type -eq "CatalogSource" } | Select-Object -ExpandProperty URL
					
					# Define Dell Cabinet/XL Names and Paths
					$DellCabFile = [string]($DellXMLCabinetSource | Split-Path -Leaf)
					$DellCatalogFile = [string]($DellCatalogSource | Split-Path -Leaf)
					$DellXMLFile = $DellCabFile.TrimEnd(".cab")
					$DellXMLFile = $DellXMLFile + ".xml"
					$DellCatalogXMLFile = $DellCatalogFile.TrimEnd(".cab") + ".xml"
					$DellFlashExtracted = $false
					$DellCabFilePath = (Join-Path -Path "$global:TempDirectory" -ChildPath "$DellCabFile")
					
					# Windows Build Dell formatting
					$WindowsVersion = $WindowsVersion.Replace(" ", "")
					
					Write-DATLogEntry -Value "- Checking for previously downloaded cab file - $DellCabFile in path $($global:TempDirectory)" -Severity 1
					if ((Test-Path -Path (Join-Path -Path "$global:TempDirectory" -ChildPath "$DellCabFile")) -eq $false) {
						Write-DATLogEntry -Value "- Downloading Dell product cabinet file from $DellXMLCabinetSource" -Severity 1
						
						# Download Dell Model Cabinet File
						try {
							Invoke-DATContentDownload -DownloadURL $DellXMLCabinetSource -DownloadDestination $global:TempDirectory							
						} catch {
							Write-DATLogEntry -Value "[Error] - Downloading $OEM driver catalog - $($_.Exception.Message)" -Severity 3
						}
					}
					
					Write-DATLogEntry -Value "- Expanding Dell driver pack cabinet file: $DellCabFilePath" -Severity 1
					if ([boolean](Test-Path -Path $DellCabFilePath -ErrorAction SilentlyContinue) -eq $true) {
						# Download Dell Model Cabinet File
						try {
							# Expand Cabinet File
							Write-DATLogEntry -Value "- Expanding Dell driver pack cabinet file: $DellXMLFile" -Severity 1
							Expand "$global:TempDirectory\$DellCabFile" -F:* "$global:TempDirectory" -R | Out-Null
						} catch {
							Write-DATLogEntry -Value "[Error] - Expanding $OEM $DellXMLFile - $($_.Exception.Message)" -Severity 3
						}
					}
					
					if ($global:DellModelXML -eq $null) {
						# Read XML File
						Write-DATLogEntry -Value "- Reading Dell driver pack XML file - $global:TempDirectory\$DellXMLFile" -Severity 1
						[xml]$global:DellModelXML = Get-Content -Path (Join-Path -Path "$global:TempDirectory" -ChildPath $DellXMLFile) -Raw
						
						# Set XML Object
						$global:DellModelXML.GetType().FullName
					}
					$global:DellModelCabFiles = $global:DellModelXML.driverpackmanifest.driverpackage
					# Find Models Contained Within Downloaded XML
					if (($ArchitectureComboxBox).Text -ne $null) {
						switch -wildcard ($ArchitectureComboxBox.Text) {
							"*32*" {
								$Architecture = "x86"
							}
							"*64*" {
								$Architecture = "x64"
							}
						}
					}
					Write-DATLogEntry -Value "- Looking up $OEM models compatible with $WindowsVersion $Architecture" -Severity 1
					$DellModels = $global:DellModelCabFiles | Where-Object {
						($_.SupportedOperatingSystems.OperatingSystem.osCode -eq "$WindowsVersion") -and ($_.SupportedOperatingSystems.OperatingSystem.osArch -match $Architecture)
					} | Select-Object @{
						Name = "SystemName"; Expression = {
							$_.SupportedSystems.Brand.Model.name | Select-Object -First 1
						}
					}, @{
						Name = "SystemID"; Expression = {
							$_.SupportedSystems.Brand.Model.SystemID
						}
					} -Unique | Where-Object {
						$_.SystemName -gt $null
					}
					
					# Sort models
					$DellModels = $DellModels | Sort-Object SystemName -Descending
					
					foreach ($Model in $DellModels) {
						# Update array
						$ModelDetails = New-Object -TypeName PSObject
						$ModelDetails | Add-Member -MemberType NoteProperty -Name "OEM" -Value "$OEM" -Force
						$ModelDetails | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($Model.SystemName)" -Force
						$ModelDetails | Add-Member -MemberType NoteProperty -Name "Baseboards" -Value "$($Model.SystemId)" -Force
						$ModelDetails | Add-Member -MemberType NoteProperty -Name "OS" -Value "$WindowsVersion" -Force
						$ModelDetails | Add-Member -MemberType NoteProperty -Name "OS Build" -Value "$WindowsBuild" -Force
						
						$OEMSupportedModels += $ModelDetails
					}
				} catch [System.Exception] {
					Write-DATLogEntry -Value "[Error] - An error occured while attempting to obtain a list of HP models" -Severity 3 -UpdateUI
					Write-DATLogEntry -Value "- Raw message detail - `"$($_.Exception.Message)`"" -Severity 3 -UpdateUI
				}
			}
			"Lenovo" {
				# Set variables
				$OEM = "Lenovo"
				
				# Define Lenovo Download Sources
				$LenovoXMLSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Lenovo" }).Link | Where-Object { $_.Type -eq "XMLSource" } | Select-Object -ExpandProperty URL
				$LenovoBIOSBase = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Lenovo" }).Link | Where-Object { $_.Type -eq "BIOSBase" } | Select-Object -ExpandProperty URL
				$LenovoXMLCabFile = $LenovoXMLSource | Split-Path -Leaf
				$LenovoXMLFile = [string]($LenovoXMLSource | Split-Path -Leaf)
				
				try {
					if ((Test-Path -Path $global:TempDirectory\$LenovoXMLCabFile) -eq $false) {
						Write-DATLogEntry -Value "======== Downloading Lenovo Catalog ========" -Severity 1
						# Download HP Model Cabinet File
						Write-DATLogEntry -Value "- Downloading Lenovo XML catalog from $LenovoXMLSource" -Severity 1
						Invoke-DATContentDownload -DownloadURL $LenovoXMLSource -DownloadDestination $global:TempDirectory
					}
					[xml]$global:LenovoModelXML = Get-Content -Path $(Join-Path -Path $global:TempDirectory -ChildPath $LenovoXMLCabFile)
					# Read Web Site
					Write-DATLogEntry -Value "- Reading driver pack URL - $LenovoXMLSource" -Severity 1
					# Set XML Object
					$global:LenovoModelDrivers = $global:LenovoModelXML.ModelList.Model
					
					# Find Models Contained Within Downloaded XML
					if (-not ([string]::IsNullOrEmpty($WindowsBuild))) {
						$LenovoModels = ($global:LenovoModelDrivers | Where-Object {
								($_.SCCM.Version -eq $WindowsBuild -and $_.SCCM.OS -eq $("Win" + "$($WindowsVersion.Split(' ')[1])"))
							} | Sort-Object).Name
					} else {
						$LenovoModels = ($global:LenovoModelDrivers | Where-Object {
								($_.SCCM.Version -eq "*")
							} | Sort-Object).Name
					}
					
					if ($LenovoModels -ne $null) {
						foreach ($Model in $LenovoModels) {
							# Uncomment for debugging
							# Write-DATLogEntry -Value "- Adding $Model" -Severity 1

							$BaseboardValues = ([string]$(Find-DATLenovoModelType -Model $Model)).Replace(" ", ",").Trim()
							
							# Update array
							$ModelDetails = New-Object -TypeName PSObject
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "OEM" -Value "$OEM" -Force
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "Model" -Value "$Model" -Force
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "Baseboards" -Value "$BaseboardValues" -Force
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "OS" -Value "$WindowsVersion" -Force
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "OS Build" -Value "$WindowsBuild" -Force
							
							$OEMSupportedModels += $ModelDetails
						}
					}
				} catch {
					Write-DATLogEntry -Value "[Error] - $($_.Exception.Message)" -Severity 3
				}
			}
			"Acer" {
				# Set variables
				$OEM = "Acer"
				
				# Define Acer Download Sources
				$AcerXMLSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Acer" }).Link | Where-Object { $_.Type -eq "XMLSource" } | Select-Object -ExpandProperty URL
				$AcerXMLFile = [string]($AcerXMLSource | Split-Path -Leaf)
				
				try {
					if ((Test-Path -Path $global:TempDirectory\$AcerXMLFile) -eq $false) {
						Write-DATLogEntry -Value "[Acer OEM] - Downloading Acer Catalog ========" -Severity 1
						# Download HP Model Cabinet File
						Write-DATLogEntry -Value "- Downloading Acer XML catalog from $AcerXMLSource" -Severity 1
						Invoke-DATContentDownload -DownloadURL $AcerXMLSource -DownloadDestination $global:TempDirectory
						
						while ((Get-Job -Id $global:DownloadBackgroundJobID).State -eq "Running") {
							# Wait for process
						}
						
						if ((Get-Job -Id $global:DownloadBackgroundJobID).State -eq "Completed") {
							# Set running state to completed
							Write-DATLogEntry -Value "- File downloaded successfully. Removing background job $global:DownloadBackgroundJobID." -Severity 1
							#Get-Job -Id $global:DownloadBackgroundJobID | Receive-Job | Remove-Job
						}
					}
					[xml]$global:AcerModelXML = Get-Content -Path $(Join-Path -Path $global:TempDirectory -ChildPath $AcerXMLFile)
					# Read Web Site
					Write-DATLogEntry -Value "- Reading driver pack file - $AcerXMLFile" -Severity 1
					# Set XML Object
					$global:AcerModelDrivers = $global:AcerModelXML.ModelList.Model
					
					# Find Models Contained Within Downloaded XML
					if (-not ([string]::IsNullOrEmpty($WindowsBuild))) {
						$AcerModels = ($global:AcerModelDrivers | Where-Object {
								($_.SCCM.Version -eq $WindowsBuild -and $_.SCCM.OS -eq $("Win" + "$($WindowsVersion.Split(' ')[1])"))
							} | Sort-Object).Name
					} else {
						$AcerModels = ($global:AcerModelDrivers | Where-Object {
								($_.SCCM.Version -eq "*")
							} | Sort-Object).Name
					}
					
					if ($AcerModels -ne $null) {
						foreach ($Model in $AcerModels) {
							# Uncomment for debugging
							# Write-DATLogEntry -Value "- Adding $Model" -Severity 1
							
							# Update array
							$ModelDetails = New-Object -TypeName PSObject
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "OEM" -Value "$OEM" -Force
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "Model" -Value "$Model" -Force
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "Baseboards" -Value "$Model" -Force
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "OS" -Value "$WindowsVersion" -Force
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "OS Build" -Value "$WindowsBuild" -Force
							$OEMSupportedModels += $ModelDetails
						}
					}
				} catch {
					Write-DATLogEntry -Value "[Error] - $($_.Exception.Message)" -Severity 3
				}
			}
			"Microsoft" {
				# Set variables
				$OEM = "Microsoft"
				
				# Define Microsoft Download Sources
				$MicrosoftJSONSource = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Microsoft" }).Link | Where-Object { $_.Type -eq "JSONSource" } | Select-Object -ExpandProperty URL
				$MicrosoftBaseURL = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Microsoft" }).Link | Where-Object { $_.Type -eq "BaseURL" } | Select-Object -ExpandProperty URL
				$MicrosoftSurfaceDriverSupportURL = ($OEMLinks.OEM.Manufacturer | Where-Object { $_.Name -match "Microsoft" }).Link | Where-Object { $_.Type -eq "SurfaceDriverSupportURL" } | Select-Object -ExpandProperty URL
				
				try {
					Write-DATLogEntry -Value "[Microsoft OEM] - Catalog ========" -Severity 1
					# Download HP Model Cabinet File
					Write-DATLogEntry -Value "- Reading Microsoft JSON catalog from $MicrosoftJSONSource" -Severity 1
					$MicrosoftJsonDetails = Invoke-WebRequest -Uri $MicrosoftJSONSource -TimeoutSec 5
					Write-DATLogEntry -Value "- Reading driver pack details - $MicrosoftJSONSource" -Severity 1
					$global:MicrosoftModelList = $MicrosoftJsonDetails | ConvertFrom-Json
					
					Write-DATLogEntry -Value "- Looking up $WindowsVersion $WindowsBuild long build number" -Severity 1
					$WindowsBuildNumber = ($WindowsBuildHashTable.Item("$WindowsBuild")).Split(".")[2]
					
					Write-DATLogEntry -Value "- Finding matching models for $WindowsVersion $WindowsBuildNumber" -Severity 1
					$MicrosoftModels = ($global:MicrosoftModelList | Where-Object {
							($_.OSVersion -match $WindowsVersion -and $_.FileName -match $WindowsBuildNumber)
						} | Select-Object Model, Product -Unique)
					
					if ($MicrosoftModels -ne $null) {
						foreach ($Model in $MicrosoftModels) {
							# Uncomment for debugging
							Write-DATLogEntry -Value "- Adding $Model" -Severity 1
							$BaseboardValues = ([string]$(Find-DATLenovoModelType -Model $Model)).Replace(" ", ",").Trim()
							
							# Update array
							$ModelDetails = New-Object -TypeName PSObject
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "OEM" -Value "$OEM" -Force
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "Model" -Value "$Model" -Force
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "Baseboards" -Value "$BaseboardValues" -Force
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "OS" -Value "$WindowsVersion" -Force
							$ModelDetails | Add-Member -MemberType NoteProperty -Name "OS Build" -Value "$WindowsBuild" -Force
							
							$OEMSupportedModels += $ModelDetails
						}
					}
				} catch {
					Write-DATLogEntry -Value "[Error] - $($_.Exception.Message)" -Severity 3
				}
			}
		}
	}
	
	# Output full supported model array
	return [array]$OEMSupportedModels
}

function Get-DATOEMDownloadLinks {
	[CmdletBinding()]
	param
	(
		[Parameter(Position = 1)]
		[ValidateSet('HP', 'Dell', 'Lenovo', 'Microsoft', 'Acer')]
		[array]$OEM,
		[Parameter(Position = 2)]
		[ValidateSet('Windows 11 25H2', 'Windows 11 24H2', 'Windows 11 23H2', 'Windows 11 22H2', 'Windows 11', 'Windows 10 22H2')]
		[ValidateNotNullOrEmpty()]
		[string]$OS,
		[Parameter(Position = 3)]
		[ValidateSet('x64', 'x86', 'Arm64')]
		[string]$Architecture,
		[Parameter(Position = 4)]
		[ValidateSet('driver', 'bios', 'all')]
		[string]$DownloadType,
		[Parameter(Position = 5)]
		[ValidateNotNullOrEmpty()]
		[string]$Model
	)

	Write-DATLogEntry -Value "[OEM Link Query] - Locating OEM download link" -Severity 1
	Write-DATLogEntry -Value "- Download type $DownloadType" -Severity 1
	Write-DATLogEntry -Value "- Parameters passed: OEM=$OEM, OS=$OS, Architecture=$Architecture, Model=$Model" -Severity 1
	
	# Get OEM Sources
	Get-DATOEMSources

	switch ($OEM) {
		"Acer" {
			# Look up Acer download link
			switch ($DownloadType) {
				"Driver" { 
					# Look up Acer driver download link from model
					switch -wildcard ($OS) {
						"Windows 11*" { 
							$OSFilter = "win11"
						}
						"Windows 10*" { 
							$OSFilter = "win10" 

						}
					}

					# Get Windows OS Build
					$OSBuildFilter = $OS.Split(" ")[2]

					# Look up Acer driver download link from model based on the OSFiler and version
					$DriverDownloadLink = ($global:AcerModelDrivers | Where-Object { $_.Name -eq $Model }) | Select-Object -ExpandProperty SCCM | Where-Object { $_.OS -eq $OSFilter -and $_.Version -eq $OSBuildFilter } | Select-Object -ExpandProperty "#text"

				}
				"BIOS" {
					# To be implemented. Waiting on update from Acer
				}
			}
		}
		"Dell" {
			switch ($DownloadType) {
				"Driver" {
					
					# OS matching format
					switch -wildcard ($OS) {
						"Windows 11" {
							$WindowsVersion = "Windows11"
						}
						"Windows 10" {
							$WindowsVersion = "Windows10"
						}
					}
					
					Write-DATLogEntry -Value "- Setting Dell variables" -Severity 1 -UpdateUI
					if ($global:DellModelCabFiles -eq $null) {
						[xml]$DellModelXML = Get-Content -Path $(Join-Path -Path $global:TempDirectory -ChildPath $DellXMLFile) -Raw
						
						# Set XML Object
						$DellModelXML.GetType().FullName
						$global:DellModelCabFiles = $DellModelXML.driverpackmanifest.driverpackage
					}
					$global:SkuValue = (($global:DellModelCabFiles.supportedsystems.brand.model | Where-Object {
								$_.Name -eq $Model
							}).systemID) | Select-Object -Unique
					$ModelURL = $global:DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object {
							((($_.SupportedOperatingSystems).OperatingSystem).osCode -eq $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $global:SkuValue)
						}).delta
					if ($global:SkuValue.Count -gt 1) {
						$DellSingleSKU = $global:SkuValue | Select-Object -First 1
						$global:SkuValue = [string]($global:SkuValue -join ";")
						Write-DATLogEntry -Value "- Using SKU : $DellSingleSKU" -Severity 1
						$ModelURL = $global:DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object {
								((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $DellSingleSKU)
							}).delta
						$DriverDownloadLink = $global:DellDownloadBase + "/" + (($global:DellModelCabFiles | Where-Object {
									((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $DellSingleSKU)
								}) | Sort-Object DateTime -Descending | Select-Object -First 1).path
						$DriverCab = ($DriverDownloadLink).Split("/") | Select-Object -Last 1
						
					} else {
						$ModelURL = $global:DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object {
								((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $global:SkuValue)
							}).delta
						$DriverDownloadLink = $global:DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object {
								((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $global:SkuValue)
							} | Sort-Object DateTime -Descending | Select-Object -First 1).path
						$DriverCab = ($DriverDownloadLink).Split("/") | Select-Object -Last 1
					}
					Write-DATLogEntry -Value "- Model URL is $ModelURL" -Severity 1
					Write-DATLogEntry -Value "- Driver download URL is $DriverDownloadLink" -Severity 1
					$ModelURL = $ModelURL.Replace("\", "/")
					if ($DriverCab -match ".cab") {
						$DriverRevision = $Drivercab.Split("-") | Select-Object -Last 2 | Select-Object -First 1
					} else {
						$DriverRevision = (($DriverCab.Split("_") | Select-Object -Last 1).Trim(".exe")).Trim()
					}
					Write-DATLogEntry -Value "- Dell System Model ID is : $global:SkuValue" -Severity 1
				}
				"BIOS" {
					#<code>
				}
	
			}
		}
		"HP" {
			switch ($DownloadType) {
				"Driver" {
					
					# OS matching format
					switch -wildcard ($OS) {
						"Windows 11" {
							$WindowsVersion = "Windows11"
						}
						"Windows 10" {
							$WindowsVersion = "Windows10"
						}
					}
					
					Write-DATLogEntry -Value "- Setting HP variables" -Severity 1 -UpdateUI
					if ($global:DellModelCabFiles -eq $null) {
						[xml]$DellModelXML = Get-Content -Path $(Join-Path -Path $global:TempDirectory -ChildPath $DellXMLFile) -Raw
						
						# Set XML Object
						$DellModelXML.GetType().FullName
						$global:DellModelCabFiles = $DellModelXML.driverpackmanifest.driverpackage
					}
					$global:SkuValue = (($global:DellModelCabFiles.supportedsystems.brand.model | Where-Object {
								$_.Name -eq $Model
							}).systemID) | Select-Object -Unique
					$ModelURL = $global:DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object {
							((($_.SupportedOperatingSystems).OperatingSystem).osCode -eq $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $global:SkuValue)
						}).delta
					if ($global:SkuValue.Count -gt 1) {
						$DellSingleSKU = $global:SkuValue | Select-Object -First 1
						$global:SkuValue = [string]($global:SkuValue -join ";")
						Write-DATLogEntry -Value "- Using SKU : $DellSingleSKU" -Severity 1
						$ModelURL = $global:DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object {
								((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $DellSingleSKU)
							}).delta
						$DriverDownloadLink = $global:DellDownloadBase + "/" + (($global:DellModelCabFiles | Where-Object {
									((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $DellSingleSKU)
								}) | Sort-Object DateTime -Descending | Select-Object -First 1).path
						$DriverCab = ($DriverDownloadLink).Split("/") | Select-Object -Last 1
						
					} else {
						$ModelURL = $global:DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object {
								((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $global:SkuValue)
							}).delta
						$DriverDownloadLink = $global:DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object {
								((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $global:SkuValue)
							} | Sort-Object DateTime -Descending | Select-Object -First 1).path
						$DriverCab = ($DriverDownloadLink).Split("/") | Select-Object -Last 1
					}
					Write-DATLogEntry -Value "- Model URL is $ModelURL" -Severity 1
					Write-DATLogEntry -Value "- Driver download URL is $DriverDownloadLink" -Severity 1
					$ModelURL = $ModelURL.Replace("\", "/")
					if ($DriverCab -match ".cab") {
						$DriverRevision = $Drivercab.Split("-") | Select-Object -Last 2 | Select-Object -First 1
					} else {
						$DriverRevision = (($DriverCab.Split("_") | Select-Object -Last 1).Trim(".exe")).Trim()
					}
					Write-DATLogEntry -Value "- Dell System Model ID is : $global:SkuValue" -Severity 1
				}
				"BIOS" {
					#<code>
				}
				
			}
		}
		"Lenovo" {
			Write-DATLogEntry -Value "- Setting Lenovo variables" -Severity 1
			#Find-DATLenovoModelType -Model $Model -OS $OS
			
			try {
				Write-DATLogEntry -Value "- $OEM $Model matching model type: $global:LenovoModelType" -Severity 1

				# OS matching format
				switch -wildcard ($OS) {
					"Windows 11*" {
						$WindowsVersion = "Win11"
						$OSVersion = $OS.Split(" ")[2]
					}
					"Windows 10*" {
						$WindowsVersion = "Win10"
						$OSVersion = $OS.Split(" ")[2]
					}
				}

				Write-DATLogEntry -Value "- Looking up version based on $WindowsVersion $OSVersion" -Severity 1
				
				switch -wildcard ($WindowsVersion) {
					"1*" {
						$DriverDownloadLink = ($global:LenovoModelDrivers | Where-Object {
								$_.Name -eq "$Model"
							}).SCCM | Where-Object {
							$_.os -match $WindowsVersion -and $_.version -match $OSVersion
						} | Select-Object -ExpandProperty "#text" -First 1
					}
					default {
						$DriverDownloadLink = ($global:LenovoModelDrivers | Where-Object {
								$_.Name -like "$Model*"
							}).SCCM | Where-Object {
							$_.Version -eq $OSVersion
						} | Select-Object -ExpandProperty "#text" -First 1
					}
				}
				
				Write-DATLogEntry -Value "- Driver Download is $DriverDownloadLink and type is $DownloadType" -Severity 1
				
				if (-not ([string]::IsNullOrEmpty($DriverDownloadLink)) -and $DownloadType -notmatch "BIOS") {
					# Fix URL malformation
					Write-DATLogEntry -Value "- Driver package URL - $DriverDownloadLink" -Severity 1
					$ModelURL = $DriverDownloadLink
					$DriverCab = $DriverDownloadLink | Split-Path -Leaf
					$DriverRevision = ($DriverCab.Split("_") | Select-Object -Last 1).Trim(".exe")
				} elseif ($DownloadType -notmatch "BIOS") {
					Write-DATLogEntry -Value "[Error] - Unable to find driver for $Make $Model" -Severity 3
				}
				$global:SkuValue = Find-DATLenovoModelType -Model $Model
				
			} catch [System.Exception] {
				Write-DATLogEntry -Value "[Error] - $($_.Exception.Message)" -Severity 3
				Write-DATLogEntry -Value "[Error] - Unable to find driver for $Make $Model" -Severity 3
			}
		}
	}
	
	# Return "Unknown" if no download link is null or empty, otherwise return the download link
	if ([string]::IsNullOrEmpty($DriverDownloadLink)) {
		return "Unknown"
	} else {
		return $DriverDownloadLink
	}
}
function Get-DATConfigMgrSiteCode {
	param
	(
		[ValidateNotNullOrEmpty()]
		[string]$SiteServer
	)
	
	try {
		Write-DATLogEntry -Value "- Calling WMI on server $SiteServer to obtain root\SMS class information" -Severity 3
		$SiteCodeObjects = Get-CimInstance -ComputerName $SiteServer -Namespace "root\SMS" -Class SMS_ProviderLocation -ErrorAction Stop
	} catch {
		Write-DATLogEntry -Value "[Error] - Issues occurred while attempting to query WMI on server $SiteServer. $($_.Exception.Message)" -Severity 3
	}
	
	if (($SiteCodeObjects.SiteCode).Count -ge 1) {
		foreach ($SiteCodeObject in $SiteCodeObjects) {
			Write-DATLogEntry -Value "- Checking $($SiteCodeObject.Machine) for site code information" -Severity 1
			if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
				$global:SiteCode = $SiteCodeObject.SiteCode
				Write-DATLogEntry -Value "- Site Code Found: $($global:SiteCode)" -Severity 1
			}
		}
	}
}
function Invoke-DATContentDownload {
	[CmdletBinding()]
	param
	(
		[ValidateNotNullOrEmpty()]
		$DownloadDestination,
		[ValidateNotNullOrEmpty()]
		$DownloadURL
	)
	
	# Requires TLS 1.2
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		
	# Check for download destination, creating if not found
	if (-not (Test-Path -Path $DownloadDestination)) {
		Write-DATLogEntry -Value "- Creating download destination directory $DownloadDestination" -Severity 1
		New-Item -Path $DownloadDestination -ItemType Directory -Force
	}

	# Curl arguments
	$DownloadDestination = Join-Path -Path "$DownloadDestination" -ChildPath "$($DownloadURL | Split-Path -Leaf)"
	$CurlArgs = "--insecure --location --output `"$DownloadDestination`" --url `"$DownloadURL`" --connect-timeout 30 --retry 10 --retry-delay 60 --retry-max-time 600 --retry-connrefused"
	
	# Curl detection
	if ([string]::IsNullOrEmpty($CurlProcess)) {
		Write-DATLogEntry -Value "- Obtaining CURL path in source directory $global:ToolsDirectory" -Severity 1
		$CurlProcess = Get-ChildItem -Path "$global:ToolsDirectory" -Recurse -Filter "Curl.exe" | Select-Object -First 1 -ExpandProperty VersionInfo | Select-Object -ExpandProperty FileName
	}
	
	# Test internet connectivity to specified URL
	try {
		Write-DATLogEntry -Value "- Attempting to obtain file size information from $DownloadURL" -Severity 1 -UpdateUI 
		$DownloadState = Invoke-WebRequest -Uri $DownloadURL -Method Head -UseBasicParsing -TimeoutSec 180
		Write-DATLogEntry -Value "- URL $DownloadURL returned status code $($DownloadState.StatusCode)" -Severity 1
		if ($DownloadState.StatusCode -eq "200") {
			Write-DATLogEntry -Value "- Content available, reading HTTP headers" -Severity 1
			$DownloadHeaders = $DownloadState | Select-Object -ExpandProperty Headers
			Write-DATLogEntry -Value "- Server: $($DownloadHeaders.Server)" -Severity 1
			Write-DATLogEntry -Value "- Cache: $($DownloadHeaders.'X-Cache')" -Severity 1
			Write-DATLogEntry -Value "- Last Modified: $($DownloadHeaders.'Last-Modified')" -Severity 1
		} else {
			Write-DATLogEntry -Value "[Error] - Issue occured while attempting download. Error output: $($_.Exception.Message)" -Severity 3
		}
	} catch [System.Exception] {
		Write-DATLogEntry -Value "[Error] - Issue occured while attempting download. Error output: $($_.Exception.Message)" -Severity 3
	}
	
	try {
		# File size and hash details
		if (-not ([string]::IsNullOrEmpty($($DownloadHeaders.'Content-Length')))) {
			$DownloadSize = $DownloadHeaders."Content-Length"
			
		} else {

			# Check if any existing CURL processes running, report the number of instances found, and terminate them
			$ExistingCurlProcesses = Get-Process -Name Curl -ErrorAction SilentlyContinue
			if ($ExistingCurlProcesses.Count -gt 0) {
				Write-DATLogEntry -Value "- Found $($ExistingCurlProcesses.Count) existing CURL process(es). Terminating before proceeding." -Severity 2
				Get-Process -Name Curl -ErrorAction SilentlyContinue | ForEach-Object {
					Write-DATLogEntry -Value "- Terminating existing CURL process with ID $($_.Id)" -Severity 1
					Stop-Process -Id $_.Id -Force
				}
			}
						
			# Invoke CURL and capture output to custom object
			Write-DATLogEntry -Value "[Warning] - Unable to obtain download size from HTTP headers. Falling back to CURL" -Severity 2
			Write-DATLogEntry -Value "- Running CURL ($CurlProcess) to obtain file size" -Severity 1
			[array]$CurlHeaderOutput = (&"$CurlProcess" --silent --location --show-headers --suppress-connect-headers --max-time 10 $DownloadURL)
			
			# Get content length
			$DownloadSize = $CurlHeaderOutput | Where-Object { $_ -match "Content-Length" } | ForEach-Object { $_ -replace "Content-Length: ", "" }
		}
		
		Write-DATLogEntry -Value "- Download size: $($DownloadSize) bytes" -Severity 1
		if (-not ([string]::IsNullOrEmpty($($DownloadHeaders."Content-MD5")))) {
			$DownloadHash = $DownloadHeaders."Content-MD5"
			Write-DATLogEntry -Value "- File Hash (MD5): $DownloadHash" -Severity 1
		}
	} catch [System.Exception] {
		Write-DATLogEntry -Value "[Warning] - Issue occurred while determining file size. Error output: $($_.Exception.Message)" -Severity 3
	}
	
	# Skip download if file already downloaded
	if ((Test-Path -Path $DownloadDestination) -eq $true) {
		Write-DATLogEntry -Value "- File previously downloaded - $DownloadDestination. Verifying download fize size matches expected size." -Severity 1 -UpdateUI
		Start-Sleep -Seconds 1
		
		# Check file size matches expected download size
		$DownloadedFileSize = (Get-Item -Path $DownloadDestination).Length
		
		if ($DownloadSize -eq $DownloadedFileSize) {
			Write-DATLogEntry -Value "- File sizes verified as matching" -Severity 1 -UpdateUI
			Set-DATRegistryValue -Name "RunningState" -Value "Running" -Type String
			Set-DATRegistryValue -Name "RunningMode" -Value "Download Completed" -Type String
			$Redownload = $false
		} else {
			Write-DATLogEntry -Value "[Warning] - Existing file size is different to expected value. Re-downloading." -Severity 2 -UpdateUI
			$Redownload = $true
		}
	}
	
	if ((-not ([string]::IsNullOrEmpty($DownloadSize))) -and ($Redownload -ne $false)) {
		try {
			
			# Set registry download value
			Set-DATRegistryValue -Name "DownloadURL" -Type String -Value "$DownloadURL" -Verbose
			
			# Convert download size to MB and set registry value
			$DownloadSizeMB = [math]::Round(($DownloadSize / 1MB), 2)
			Set-DATRegistryValue -Name "DownloadSize" -Type String -Value "$DownloadSizeMB" -Verbose
			Set-DATRegistryValue -Name "DownloadBytes" -Value "$DownloadSize" -Type String
			
			if ((-not ([string]::IsNullOrEmpty($CurlProcess))) -and ((Test-Path -Path "$CurlProcess") -eq $true)) {
				Write-DATLogEntry -Value "- Path set as $CurlProcess" -Severity 1
				Write-DATLogEntry -Value "- Invoking CURL download process" -Severity 1
				Write-DATLogEntry -Value "- Running command from $CurlProcess" -Severity 1
				Write-DATLogEntry -Value "- Using arguments `"$CurlArgs`"" -Severity 1
				Set-DATRegistryValue -Name "RunningProcess" -Type String -Value "Curl" -Verbose
				
				$DownloadStartTime = Get-DATLocalSystemTime
				Set-DATRegistryValue -Name "DownloadStartTime" -Type String -Value "$DownloadStartTime" -Verbose
				
				# Unblock file (UAC / admin access)
				Unblock-File -Path "$CurlProcess"
				
				# Terminate any existing CURL processes
				Get-Process -Name Curl -ErrorAction SilentlyContinue | ForEach-Object {
					Write-DATLogEntry -Value "- Terminating existing CURL process with ID $($_.Id)" -Severity 1
					Stop-Process -Id $_.Id -Force
				}	
				
				# Start download process
				Write-DATLogEntry -Value "- Starting download process using CURL. Download URL - $DownloadURL" -Severity 1 -UpdateUI
				$DownloadProcess = Start-Process -FilePath $CurlProcess -ArgumentList $CurlArgs -PassThru -WindowStyle Minimized
				$DownloadProcessCounter = 0
				
				# Sleep for CURL initialization
				Start-Sleep -Seconds 5
				
				# Wait for process to complete
				while (Get-Process -Name Curl -ErrorAction SilentlyContinue) {
					# Get IO writes for download process
					$CURLBytes = Get-CimInstance -Class Win32_Process -Filter "Name = 'Curl.exe'" | Select-Object -ExpandProperty WriteTransferCount
					
					# Report download progress if bytes are greater than 0
					if ($CURLBytes -gt 0) {
						# Increment download process counter
						$DownloadProcessCounter++
						
						# Update registry
						Set-DATRegistryValue -Name "BytesTransferred" -Value $CURLBytes -Type String
						
						# Convert bytes to MB/GB
						$CURLMBDownload = [math]::Round($CURLBytes / 1MB, 2)
						$CURLGBDownload = [math]::Round($CURLBytes / 1GB, 2)
						
						# Set download speed in MB/s
						$DownloadSpeed = [math]::Round($CURLMBDownload / ((Get-Date) - $DownloadStartTime).TotalSeconds, 2)
						
						# Set message body for download progress
						$DownloadMsg = "- Downloaded $CURLMBDownload MB of $DownloadSizeMB MB at a rate of $DownloadSpeed MB/s"
						
						# Update log entry with download progreess where $DownloadProcessCount is divisible by 60
						if (($DownloadProcessCounter % 60) -eq 0) {
							# Update log entry with download progress
							Write-DATLogEntry -Value "$DownloadMsg. Next update in 60 seconds." -Severity 1
						} else {
							# Update registry with download progress
							Set-DATRegistryValue -Name "RunningMessage" -Type String -Value "$($DownloadMsg.TrimStart('- '))" -Verbose
						}

						# Sleep for 1 second before next check
						Start-Sleep -Seconds 1
					}
					
					# Final registry update with download progress
					$DownloadedFileSize = (Get-Item -Path $DownloadDestination).Length
					Set-DATRegistryValue -Name "BytesTransferred" -Value "$DownloadedFileSize" -Type String
				}
			}

			# Output the download process exit code
			Write-DATLogEntry -Value "- Download process exited with code $($DownloadProcess.ExitCode)" -Severity 1
			Write-DATLogEntry -Value "- Downloaded file path - $DownloadDestination" -Severity 1
			# Get downloaded file size
			$DownloadedFileSize = (Get-Item -Path $DownloadDestination).Length
			Write-DATLogEntry -Value "- Downloaded file size - $DownloadedFileSize bytes" -Severity 1
			
			if ($DownloadProcess.ExitCode -eq 0) {
				# Gather download information
				$DownloadEndTime = Get-DATLocalSystemTime
				Set-DATRegistryValue -Name "DownloadEndTime" -Value "$DownloadEndTime" -Type String
				Write-DATLogEntry -Value "- Download process complete, verifying download contents" -Severity 1 -UpdateUI
				
				# Verify file size match
				$DownloadedFileName = $DownloadURL | Split-Path -Leaf
				$DownloadedFilePath = Join-Path -Path $DownloadDestination -ChildPath $DownloadedFileName
				if ((Test-Path -Path $DownloadDestination) -eq $true) {
					Write-DATLogEntry -Value "- File present in path $DownloadDestination" -Severity 1 -UpdateUI
					Set-DATRegistryValue -Name "WorkingFile" -Value "$DownloadDestination" -Type String
					Write-DATLogEntry -Value "- Download header length - $DownloadSize" -Severity 1
					Write-DATLogEntry -Value "- Download actual size - $DownloadedFileSize" -Severity 1
					
					if ($DownloadSize -eq $DownloadedFileSize) {
						Write-DATLogEntry -Value "- File sizes match" -Severity 1 -UpdateUI
						Set-DATRegistryValue -Name "RunningState" -Value "Running" -Type String
						Set-DATRegistryValue -Name "RunningMode" -Value "Download Completed" -Type String
					} else {
						Write-DATLogEntry -Value "[Warning] - File sizes are different" -Severity 2 -UpdateUI
						Set-DATRegistryValue -Name "RunningMessage" -Value "Download Failed" -Type String
						Set-DATRegistryValue -Name "RunningState" -Value "Error" -Type String
					}
				} else {
					Write-DATLogEntry -Value "[Error] - File not present at location $DownloadDestination" -Severity 3
				}
			} else {
				# Start download process using invoke-webrequest
				Write-DATLogEntry -Value "- CURL download process failed. Attempting Invoke-WebRequest" -Severity 1
				$DownloadProcess = Invoke-WebRequest -Uri $DownloadURL -OutFile $DownloadDestination -TimeoutSec 180 -UseBasicParsing -DisableKeepAlive
				Write-DATLogEntry -Value "- Doownload process complete" -Severity 1
			}
		} catch [System.Exception] {
			Write-DATLogEntry -Value "[Error] - Issues occurred during download process. Error output: $($_.Exception.Message)" -Severity 3; break
		}
	}
}

<#
	.SYNOPSIS
		Sets registry entries
	
	.DESCRIPTION
		This function is a re-usable code for setting registry information. By default it will use the $global:RegPath value.
	
	.PARAMETER Name
		Registry item name
	
	.PARAMETER Value
		Value you would wish to set
	
	.PARAMETER Type
		Registry value type, example, DWORD, STRING
	
	.PARAMETER FullOSRegPath
		Optional registry path for specifc registry additions
	
	.EXAMPLE
		PS C:\> Set-RegistryValue -Name 'Value1' -Value 'Value2' -Type String
	
	.NOTES
		Additional information about the function.
#>
function Set-DATRegistryValue {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true,
			Position = 1)]
		[ValidateNotNullOrEmpty()]
		[String]$Name,
		[Parameter(Mandatory = $true,
			Position = 2)]
		[String]$Value,
		[Parameter(Mandatory = $true,
			Position = 3)]
		[ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'Qword')]
		[String]$Type,
		[Parameter(Position = 4)]
		[String]$FullOSRegPath
	)
	
	try {
		# This section of code is used to set values to the FullOS software registry hive during provisioning
		if ((-not ([string]::IsNullOrEmpty($FullOSRegPath)))) {
			switch -wildcard ($FullOSRegPath) {
				"*HKEY_LOCAL_MACHINE\System*" {
					$FullOSRegPath = $FullOSRegPath.ToLower()
					$FullOSRegPath = $FullOSRegPath.Replace("hkey_local_machine\system", "HKLM:\FullOSSystem")
					$CustomBaseKey = "HKLM:\FullOSSystem"
					Write-DATLogEntry -Value "- Using system registry hive" -Severity 1
				}
				"*HKEY_LOCAL_MACHINE\Software*" {
					$FullOSRegPath = $FullOSRegPath.ToLower()
					$FullOSRegPath = $FullOSRegPath.Replace("hkey_local_machine\software", "HKLM:\FullOSSoftware")
					$CustomBaseKey = "HKLM:\FullOSoftware"
					Write-DATLogEntry -Value "- Using software registry hive" -Severity 1
				}
			}
			
			# Create path if required
			if ([boolean](Test-Path -Path "$CustomBaseKey" -ErrorAction SilentlyContinue) -eq $false) {
				New-Item -Path $FullOSRegPath -Force | Out-Null
			}

			# Used for debugging model listing
			# Write-DATLogEntry -Value "- Adding $Value to $FullOSRegPath\$Name" -Severity 1

			New-ItemProperty -Path $FullOSRegPath -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
		} elseif (-not ([string]::IsNullOrEmpty($global:RegPath))) {
			# This section of code is used to set registry values to the $global:RegPath path during provisioning
			if ((Test-Path -Path $global:RegPath) -eq $false) {
				Write-Verbose "[Registry] - Creating registry key at path $global:RegPath"
				New-Item -Path $global:RegPath -Force | Out-Null
			}
			
			# Set new item
			Write-Verbose "- Adding registry entry $global:RegPath\$Name with value: $Value"
			New-ItemProperty -Path $global:RegPath -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
		} else {
			Write-DATLogEntry -Value "[Warning] - Registry path not specified in global variables." -Severity 2
		}
	} catch [System.Exception] {
		Write-Output "[Registry Setting Error] - Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
	}
}

<#
	.SYNOPSIS
		This function returns specific common registry values to default
	
	.DESCRIPTION
		A detailed description of the Reset-RegistryValues function.
	
	.EXAMPLE
				PS C:\> Reset-RegistryValues
	
	.NOTES
		Additional information about the function.
#>
function Reset-DATRegistryValues {
	[CmdletBinding()]
	param ()
	
	# Null registry entries
	Remove-ItemProperty -Path $global:RegPath -Name TotalDriverDownloads -ErrorAction SilentlyContinue
	Remove-ItemProperty -Path $global:RegPath -Name CurrentDriverDownload -ErrorAction SilentlyContinue
	Remove-ItemProperty -Path $global:RegPath -Name CurrentDriverDownloadCount -ErrorAction SilentlyContinue
	Remove-ItemProperty -Path $global:RegPath -Name CompletedDriverDownloads -ErrorAction SilentlyContinue
}

function Invoke-DATExecutable {
	param (
		[parameter(Mandatory = $true, HelpMessage = "Specify the file name or path of the executable to be invoked, including the extension")]
		[ValidateNotNullOrEmpty()]
		[string]$FilePath,
		[parameter(Mandatory = $false, HelpMessage = "Specify arguments that will be passed to the executable")]
		[ValidateNotNull()]
		[string]$Arguments
	)
	
	# Unlock file for execution
	Unblock-File -Path "$FilePath"
	
	# Construct a hash-table for default parameter splatting
	$SplatArgs = @{
		FilePath    = "$FilePath"
		NoNewWindow = $true
		Passthru    = $true
		ErrorAction = "Stop"
	}
	
	# Add ArgumentList param if present
	if (-not ([System.String]::IsNullOrEmpty($Arguments))) {
		$SplatArgs.Add("ArgumentList", "$Arguments")
	}
	
	# Invoke executable and wait for process to exit
	try {
		Write-DATLogEntry -Value "[Package Execution] - Running $FilePath and arguments $Arguments" -Severity 1
		$Invocation = Start-Process @SplatArgs
		$InvoationnPID = $Invocation.Id
		Write-DATLogEntry -Value "- Waiting in Process ID:$InvoationnPID to complete."
		$Invocation.WaitForExit()
	} catch [System.Exception] {
		Write-DATLogEntry -Value "[Error] - Failed to complete exection. $_.Exception.Message" -Severity 3; break
	}
	
	Write-DATLogEntry -Value "- Execution completed with exit code $($Invocation.ExitCode)" -Severity 1
	return $Invocation.ExitCode
}

<#
	.SYNOPSIS
		This function works with cached driver images to apply them to the Windows image
	
	.DESCRIPTION
		The function uses pre-staged driver packages, created in WIM files, and stored on the OSDLiteDeploy cache drive. During OS deployment, the baseboard/systemsku value is matched against the content, the WIM is then mounted and the drivers are injected into the offline Windows image.
	
	.PARAMETER TargetOS
		Specify the OS being used, for example, Windows 10
	
	.PARAMETER TargetOSBuild
		Specify the build of the OS being deployed, for example 23H2
	
	.PARAMETER TargetDrive
		A description of the TargetDrive parameter.
	
	.EXAMPLE
		PS C:\> Install-DriverPackage -TargetOS Windows 11 -TargetBuild 23H2
	
	.NOTES
		Additional information about the function.
#>
function Install-DATDriverPackage {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateSet('Windows 10', 'Windows 11')]
		[ValidateNotNullOrEmpty()]
		[String]$TargetOS,
		[Parameter(Mandatory = $true)]
		[ValidateSet('22H2', '23H2', '24H2', '25H2')]
		[ValidateNotNullOrEmpty()]
		[String]$TargetOSBuild,
		[Parameter(Mandatory = $true)]
		[ValidatePattern('^[A-Z]:$')]
		[String]$TargetDrive
	)
	
	try {
		# Set initial running values
		$DriverImageFile = $null
		
		# Create a custom object for computer details gathered from local WMI
		$ComputerDetails = [PSCustomObject]@{
			Manufacturer = $null
			Model        = $null
			SystemSKU    = $null
			FallbackSKU  = $null
		}
		
		# Gather device hardware type information
		$ComputerManufacturer = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Manufacturer).Trim()
		switch -Wildcard ($ComputerManufacturer) {
			"*Microsoft*" {
				$ComputerDetails.Manufacturer = "Microsoft"
				$ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
				$ComputerDetails.SystemSKU = Get-WmiObject -Namespace "root\wmi" -Class "MS_SystemInformation" | Select-Object -ExpandProperty SystemSKU
			}
			"*HP*" {
				$ComputerDetails.Manufacturer = "HP"
				$ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
				$ComputerDetails.SystemSKU = (Get-CimInstance -ClassName "MS_SystemInformation" -Namespace "root\WMI").BaseBoardProduct.Trim()
			}
			"*Hewlett-Packard*" {
				$ComputerDetails.Manufacturer = "HP"
				$ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
				$ComputerDetails.SystemSKU = (Get-CimInstance -ClassName "MS_SystemInformation" -Namespace "root\WMI").BaseBoardProduct.Trim()
			}
			"*Dell*" {
				$ComputerDetails.Manufacturer = "Dell"
				$ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
				$ComputerDetails.SystemSKU = (Get-CimInstance -ClassName "MS_SystemInformation" -Namespace "root\WMI").SystemSku.Trim()
				[string]$OEMString = Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty OEMStringArray
				$ComputerDetails.FallbackSKU = [regex]::Matches($OEMString, '\[\S*]')[0].Value.TrimStart("[").TrimEnd("]")
			}
			"*Lenovo*" {
				$ComputerDetails.Manufacturer = "Lenovo"
				$ComputerDetails.Model = (Get-WmiObject -Class "Win32_ComputerSystemProduct" | Select-Object -ExpandProperty Version).Trim()
				$ComputerDetails.SystemSKU = ((Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).SubString(0, 4)).Trim()
			}
		}
		
		# Stamp computer type details in the registry
		Set-DATRegistryValue -Name "Manufacturer" -Value "$($ComputerDetails.Manufacturer)" -Type String
		Set-DATRegistryValue -Name "Model" -Value "$($ComputerDetails.Model)" -Type String
		Set-DATRegistryValue -Name "SystemSKU" -Value "$($ComputerDetails.SystemSKU)" -Type String
		$SerialNumber = Get-CimInstance -ClassName win32_bios -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SerialNumber
		if (-not ([string]::IsNullOrEmpty($SerialNumber))) {
			Set-DATRegistryValue -Name "SerialNumber" -Value "$SerialNumber" -Type String
		}
		
		Write-DATLogEntry -Value "- Querying local driver cache availability for $($ComputerDetails.Manufacturer) $($ComputerDetails.Model) with matching SysID $($ComputerDetails.SystemSKU)" -Severity 1 -UpdateUI
		$CacheDrives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.VolumeName -match "Cache" } | Select-Object -ExpandProperty DeviceID
		Write-DATLogEntry -Value "- Found $($CacheDrives.Count) cache drives" -Severity 1
		
		# Obtain OS matching values from the registry
		Write-DATLogEntry -Value "- Target OS is $TargetOS" -Severity 1
		Write-DATLogEntry -Value "- Target OS build is $TargetOSBuild" -Severity 1
		
		# Build array for Cached images
		$global:CachedImages = @()
	} catch [System.Exception] {
		Write-DATLogEntry -Value "[Warning] - Errors occured while attempting to identity make/model details. Error message: $($_.Exception.Message)" -Severity 2
	}
	
	if ((-not ([string]::IsNullOrEmpty($TargetOS))) -and (-not ([string]::IsNullOrEmpty($TargetOSBuild)))) {
		foreach ($CacheDrive in $CacheDrives) {
			
			try {
				# Check for manufacturer support JSON
				Write-DATLogEntry -Value "- Attempting to read in OEM support JSON file for OEM - $($ComputerDetails.Manufacturer)" -Severity 1
				$OEMSupportJSON = Get-ChildItem -Path $CacheDrive -File -Filter *.json -Recurse | Where-Object { $_.FullName -like "*$($ComputerDetails.Manufacturer)*Models*" } | Sort-Object CreationTime -Descending | Select-Object -First 1 | Select-Object -ExpandProperty FullName
				
				if (-not ([string]::IsNullOrEmpty($OEMSupportJSON))) {
					# Read in manufacturer JSON
					$SupportedSKUValues = Get-Content -Path $OEMSupportJSON | ConvertFrom-Json
					Write-DATLogEntry -Value "- Attempting to match driver packages to supported SKU values - $SupportedSKUValues" -Severity 1
					$SupportedSKUList = $SupportedSKUValues | Where-Object { $_.SystemId -match $ComputerDetails.SystemSKU } | Select-Object -Property SystemId -Unique
					
					# Create array
					$SupportedSKUs = New-Object -TypeName System.Collections.ArrayList
					
					# Loop through supported SKU list
					foreach ($SKU in $($SupportedSKUList.SystemId).Split(",")) {
						if ($SKU -notin $SupportedSKUs) {
							# Add each supported SKU to the matching array
							$SupportedSKUs.Add($SKU) | Out-Null
						}
					}
					
					# Create array
					$SupportedDriverPacks = New-Object -TypeName System.Collections.ArrayList
					
					# Loop through to attempt to find supported driver package
					Write-DATLogEntry -Value "- Attempting to match supported driver package to supported SKU values" -Severity 1
					foreach ($SKU in $SupportedSKUs) {
						Write-DATLogEntry -Value "- Attempting to match driver package to SKU $SKU in path $CacheDrive" -Severity 1
						$DriverImageFile = Get-ChildItem -Path $CacheDrive -File -Recurse | Where-Object { $_.Name -match ".WIM" -and $_.FullName -like "*$TargetOS*$TargetOSBuild*" -and $_.FullName -match $SKU } | Sort-Object CreationTime -Descending | Select-Object -First 1 | Select-Object -Property FullName, CreationTime
						if (-not ([string]::IsNullOrEmpty($DriverImageFile))) {
							$SupportedDriverPacks.Add($DriverImageFile)
						}
					}
					
					Write-DATLogEntry -Value "- Found $($SupportedDriverPacks.Count) supported driver packages for SKUs $($SupportedSKUs)" -Severity 1
					
					if ($SupportedDriverPacks.Count -ge 1) {
						# Select the most recent driver package
						$DriverImageFile = $SupportedDriverPacks | Sort-Object CreationTime -Descending | Select-Object -First 1 -ExpandProperty FullName
						Write-DATLogEntry -Value "- Selected most recent driver package at path $DriverImageFile" -Severity 1
					}
				} else {
					# Fallback to direct model match
					Write-DATLogEntry -Value "[Warning] - No OEM JSON file found for $ComputerDetails.Manufacturer. Attempting to match directly to model." -Severity 2
					$DriverImageFile = Get-ChildItem -Path $CacheDrive -File -Recurse | Where-Object { $_.Name -match ".WIM" -and $_.FullName -like "*$TargetOS*$TargetOSBuild*" -and $_.FullName -match $ComputerDetails.SystemSKU } | Sort-Object CreationTime -Descending | Select-Object -First 1 | Select-Object -ExpandProperty FullName
					
					# Report matching status or failure
					if (-not ([string]::IsNullOrEmpty($DriverImageFile))) {
						Write-DATLogEntry -Value "- Found matching driver package for $($ComputerDetails.Manufacturer) $($ComputerDetails.Model) with SKU $($ComputerDetails.SystemSKU)" -Severity 1
						Write-DATLogEntry -Value "- Driver package located at $DriverImageFile" -Severity 1
					} else {
						Write-DATLogEntry -Value "[Error] - No matching driver package found for $ComputerDetails.Manufacturer $ComputerDetails.Model with SKU $ComputerDetails.SystemSKU" -Severity 3
					}
				}
			} catch [System.Exception] {
				Write-DATLogEntry -Value "[Warning] - Errors occured while attempting to match SKU to JSON stored OEM values. Error message: $($_.Exception.Message)" -Severity 2
			}
			
			# Process driver installation if supported
			if (-not ([string]::IsNullOrEmpty($DriverImageFile))) {
				Write-DATLogEntry -Value "- Processing driver package" -Severity 1
				
				# Specify temporary mount location
				$ContentLocation = $DriverImageFile | Split-Path -Parent
				
				try {
					# Create mount location for driver package WIM file
					$DriverPackageMountLocation = Join-Path -Path $TargetDrive -ChildPath "DriversTemp"
					Write-DATLogEntry -Value "- Mount location for driver package content: $($DriverPackageMountLocation)" -Severity 1
					
					if (-not (Test-Path -Path $DriverPackageMountLocation)) {
						Write-DATLogEntry -Value "- Creating mount location directory: $($DriverPackageMountLocation)" -Severity 1
						New-Item -Path $DriverPackageMountLocation -ItemType "Directory" -Force | Out-Null
					}
				} catch [System.Exception] {
					Write-DATLogEntry -Value "[Error] - Failed to create mount location for WIM file. Error message: $($_.Exception.Message)" -Severity 3
				}
				
				try {
					# Expand compressed driver package WIM file
					Write-DATLogEntry -Value "- Attempting to mount driver package content WIM file: $($DriverImageFile)" -Severity 1 -UpdateUI
					Mount-WindowsImage -ImagePath $DriverImageFile -Path $DriverPackageMountLocation -Index 1
					Write-DATLogEntry -Value "- Successfully mounted driver package content WIM file" -Severity 1 -UpdateUI
					
					# Copy files to maintain on disk post OSD
					$DriverPackageLocation = Join-Path -Path $TargetDrive -ChildPath "Drivers"
					if (-not (Test-Path -Path $DriverPackageLocation)) {
						Write-DATLogEntry -Value "- Creating mount location directory: $($DriverPackageLocation)" -Severity 1
						New-Item -Path $DriverPackageLocation -ItemType "Directory" -Force | Out-Null
					}
					Write-DATLogEntry -Value "- Copying drivers from mounted WIM to local disk" -Severity 1 -UpdateUI
					Get-ChildItem -Path $DriverPackageMountLocation | Copy-Item -Destination $DriverPackageLocation -Recurse -Container -Force
				} catch [System.Exception] {
					Write-DATLogEntry -Value "[Error] - Failed to mount driver package content WIM file. Error message: $($_.Exception.Message)" -Severity 3
					Dismount-WindowsImage -Path $DriverPackageMountLocation -Discard
				}
				
				try {
					Write-DATLogEntry -Value " - Installing drivers using DISM on $TargetDrive using driver source directory $DriverPackageLocation" -Severity 1 -UpdateUI
					
					# Log location variables
					$DriverInstallOutput = Join-Path -Path $env:SystemRoot -ChildPath $("Temp\DriverInjection.log")
					$DriverInstallErrors = Join-Path -Path $env:SystemRoot -ChildPath $("Temp\DriverInjectionErrors.log")
					
					# Apply drivers recursively
					Write-DATLogEntry -Value " - Starting driver installation using dism.exe" -Severity 1
					$ApplyDriverInvocation = Start-Process dism.exe -ArgumentList "/Image:$($TargetDrive) /Add-Driver /Driver:$($DriverPackageLocation) /Recurse" -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $DriverInstallOutput -RedirectStandardError $DriverInstallErrors
					Write-DATLogEntry -Value " - Dism.exe process completed with exit code $($ApplyDriverInvocation.ExitCode)" -Severity 1
					
					# Validate driver injection
					if ($ApplyDriverInvocation.ExitCode -eq 0) {
						Write-DATLogEntry -Value " - Sucessfully installed drivers recursively in driver package content location using dism.exe" -Severity 1 -UpdateUI
						Set-DATRegistryValue -Name "DriversInstalled" -Value "$true" -Type String
						Set-DATRegistryValue -Name "DriverPkgPath" -Value "$DriverPackageLocation" -Type String
						Write-DATLogEntry -Value " - Dismounting driver image" -Severity 1
						Dismount-WindowsImage -Path $DriverPackageMountLocation -Discard
						Write-DATLogEntry -Value " - Cleaning up driver package mount temporary folder(s)" -Severity 1
						Remove-Item -Path $DriverPackageMountLocation -Force | Out-Null
					} else {
						Write-DATLogEntry -Value " - An error occurred while installing drivers. Continuing with warning code: $($ApplyDriverInvocation). See DISM.log for more details" -Severity 2
						Set-DATRegistryValue -Name "DriversInstalled" -Value "$false" -Type String
						Dismount-WindowsImage -Path $DriverPackageMountLocation -Discard
						Remove-Item -Path $DriverPackageMountLocation -Force | Out-Null
					}
				} catch [System.Exception] {
					Write-DATLogEntry -Value "[Error] - Failed to install OS drivers. Error message: $($_.Exception.Message)" -Severity 3
					Set-DATRegistryValue -Name "DriversInstalled" -Value "$false" -Type String
					Dismount-WindowsImage -Path $DriverPackageMountLocation -Discard
					Remove-Item -Path $DriverPackageMountLocation -Force | Out-Null
				}
			} else {
				Write-DATLogEntry -Value "[Warning] - Unable to find matching driver package on cache drive(s) $CacheDrives" -Severity 2
			}
		}
	} else {
		Write-DATLogEntry -Value "[Warning] - Unable to determine target OS and build." -Severity 2
	}
}

function Invoke-DATBuildPackage {

	# Start the download, build and package process
	Write-DATLogEntry -Value "[Build Process] - Starting the download, build and package process" -Severity 1

	# Create an array for the selected computers
	$global:SelectedModels = New-Object System.Collections.ArrayList

	for ($Row = 0; $Row -lt $datagridview_ModelSelection.RowCount; $Row++) {
		if ($datagridview_ModelSelection.Rows[$Row].Cells[0].Value -eq $true) {

			# Update array
			$ModelDetails = New-Object -TypeName PSObject
			$ModelDetails | Add-Member -MemberType NoteProperty -Name "OEM" -Value "$($datagridview_ModelSelection.Rows[$Row].Cells[1].Value)" -Force
			$ModelDetails | Add-Member -MemberType NoteProperty -Name "Model" -Value "$($datagridview_ModelSelection.Rows[$Row].Cells[2].Value)" -Force
			$ModelDetails | Add-Member -MemberType NoteProperty -Name "Baseboards" -Value "$($datagridview_ModelSelection.Rows[$Row].Cells[4].Value)" -Force
			$ModelDetails | Add-Member -MemberType NoteProperty -Name "OS" -Value "$globaL:WindowsVersion" -Force
			$ModelDetails | Add-Member -MemberType NoteProperty -Name "OS Build" -Value "$global:Architecture" -Force
		
			$global:SelectedModels += $ModelDetails
		}
	}

	Write-DATLogEntry -Value "A total of $($global:SelectedModels | Measure-Object | Select-Object -ExpandProperty Count) have been selected for packaging" -Severity 1
}

function Connect-DATConfigMgr {
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		$SiteServer,
		[Parameter(Mandatory = $true)]
		[boolean]$WinRMOverSSL,
		[Parameter(Mandatory = $false)]
		[boolean]$KnownModels
	)
	
	if (-not ([string]::IsNullOrEmpty($SiteServer))) {
		
		try {
			switch ($WinRMOverSSL) {
				$true {
					Write-DATLogEntry -Value "- Attempting WinRM connection using SSL" -Severity 1
					Set-DATRegistryValue -Name "WinRMSSL" -Value "True" -Type String -Verbose
					[string]$ConfigMgrDiscovery = (Test-WSMan -ComputerName $SiteServer -UseSSL -ErrorAction SilentlyContinue).wsmid
				}
				$false {
					Write-DATLogEntry -Value "- Attempting WinRM connection" -Severity 1
					Set-DATRegistryValue -Name "WinRMSSL" -Value "False" -Type String -Verbose
					[string]$ConfigMgrDiscovery = (Test-WSMan -ComputerName $SiteServer -ErrorAction SilentlyContinue).wsmid
				}
			}
			Write-DATLogEntry -Value "- WinRM connection established" -Severity 1
		} catch [System.Exception] {
			Write-DATLogEntry -Value "[Error] - $($_.Exception.Message)" -Severity 3
			if ([string]::IsNullOrEmpty($ConfigMgrDiscovery)) {
				Write-DATLogEntry -Value "Switching WinRM to non SSL mode" -Severity 1
				try {
					Set-DATRegistryValue -Name "WinRMSSL" -Value "False" -Type String -Verbose
					[string]$ConfigMgrDiscovery = (Test-WSMan -ComputerName $SiteServer).wsmid
				} catch [System.Exception] {
					Write-DATLogEntry -Value "[Error] - $($_.Exception.Message)" -Severity 3
				}
			}
			Write-DATLogEntry -Value "WinRM connection established" -Severity 1
		}
		
		if ($ConfigMgrDiscovery -ne $null) {
			#$ProgressListBox.ForeColor = "Black"
			try {
				if ($global:ConfigMgrValidation -ne $true) {
					Write-DATLogEntry -Value "[Configuration Manager] - Connecting to Configuration Manager Server" -Severity 1
					Write-DATLogEntry -Value "- Querying site code From $SiteServer" -Severity 1
					$global:SiteServer = Get-DATSiteCode -SiteServer $SiteServer
					# Update registry with site server
					Set-DATRegistryValue -Name "SiteServer" -Value $SiteServer -Type String
					
					# Import Configuratio Manager PowerShell Module
					if ($env:SMS_ADMIN_UI_PATH -ne $null) {
						$ModuleName = (Get-Item $env:SMS_ADMIN_UI_PATH | Split-Path -Parent) + "\ConfigurationManager.psd1"
						Write-DATLogEntry -Value "- Loading ConfigMgr PowerShell module" -Severity 1
						Import-Module $ModuleName
						$global:ConfigMgrValidation = $true
					}
				}
			} catch [System.Exception] {
				Write-DATLogEntry -Value "[Error] - $($_.Exception.Message)" -Severity 3
			}
		} else {
			Write-DATLogEntry -Value "[Error] - ConfigMgr server specified not found - $($SiteServerInput.Text)" -Severity 3
		}
		
		if ($KnownModels -eq "Yes") {
			Write-DATLogEntry -Value "- Setting known model query" -Severity 1
			Set-DATRegistryValue -Name "KnownModels" -Value "Yes" -Type String
		} else {
			Set-DATRegistryValue -Name "KnownModels" -Value "No" -Type String
		}
	} else {
		Write-DATLogEntry -Value "[Error] - ConfigMgr site server not specified. Please review in the common settings tab." -Severity 3
	}
}

function Get-DATSiteCode {
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		$SiteServer
	)
	try {
		$SiteCodeObjects = Get-WmiObject -ComputerName $SiteServer -Namespace "root\SMS" -Class SMS_ProviderLocation -ErrorAction Stop
		$SiteCodeError = $false
	} catch {
		Write-DATLogEntry -Value "[Error] - $($_.Exception.Message)" -Severity 3
		$SiteCodeError = $true
	}
	if (($SiteCodeObjects -ne $null) -and ($SiteCodeError -ne $true)) {
		foreach ($SiteCodeObject in $SiteCodeObjects) {
			if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
				$global:SiteCode = $SiteCodeObject.SiteCode
				Write-DATLogEntry -Value "- Site Code Found: $($global:SiteCode)" -Severity 1
				Set-DATRegistryValue -Name "SiteCode" -Value $global:SiteCode -Type String
				return $global:SiteCode
			}
		}
	}
}

function Get-DATDistributionPoints {
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		$SiteCode,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		$SiteServer
	)
	
	# Check if the ConfigMgr module is loaded and load module if not
	if (-not (Get-Module -Name ConfigurationManager)) {
		$ModuleName = (Get-Item $env:SMS_ADMIN_UI_PATH | Split-Path -Parent) + "\ConfigurationManager.psd1"
		Write-DATLogEntry -Value "- Loading ConfigMgr PowerShell module" -Severity 1
		Import-Module $ModuleName
	}


	#Set-Location -Path [string]($SiteCode + ":\")
	[Array]$DistributionPoints = Get-WmiObject -ComputerName $SiteServer -Namespace "Root\SMS\Site_$SiteCode" -Class SMS_SystemResourceList | Where-Object {
		$_.RoleName -match "Distribution"
	} | Select-Object -ExpandProperty ServerName -Unique | Sort-Object


	return $DistributionPoints
}

function Get-DATDistributionPointGroups {
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		$SiteCode,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		$SiteServer
	)
	
	# Check if the ConfigMgr module is loaded and load module if not
	if (-not (Get-Module -Name ConfigurationManager)) {
		$ModuleName = (Get-Item $env:SMS_ADMIN_UI_PATH | Split-Path -Parent) + "\ConfigurationManager.psd1"
		Write-DATLogEntry -Value "- Loading ConfigMgr PowerShell module" -Severity 1
		Import-Module $ModuleName -Verbose
	}

	[Array]$DistributionPointGroups = Get-WmiObject -ComputerName $SiteServer -Namespace "Root\SMS\Site_$SiteCode" -Query "SELECT Distinct Name FROM SMS_DistributionPointGroup" | Select-Object -ExpandProperty Name
	
	return $DistributionPointGroups
}

function Get-DATLocalSystemTime {
	[CmdletBinding()]
	param ()
	
	$Time = Get-Date -DisplayHint Time
	
	# Update to UTC
	$Time = $Time.ToUniversalTime()
	
	return $Time
}

function Invoke-DATDriverFilePackaging {
	param
	(
		[Parameter(Mandatory = $false)]
		[ValidateNotNullOrEmpty()]
		[string]$FilePath,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$OEM,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Model,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$OS,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Destination,
		[ValidateSet('Configuration Manager', 'Intune', 'Download Only')]
		[string]$Platform
	)
	
	try {
		# Create a new folder for the OS, testing if the folder already exists
		$DriverFolder = Join-Path -Path $Destination -ChildPath "$OEM\$Model\$OS\Extracted"
		if (-not (Test-Path -Path $DriverFolder)) {
			New-Item -Path $DriverFolder -ItemType Directory -Force | Out-Null
		}
		
	} catch {
		Write-DATLogEntry -Value "[Error] - Failed to create driver folder $DriverFolder" -Severity 3
	}
	
	# Continue if the folder was created successfully, by testing if the folder exists
	if (Test-Path -Path $DriverFolder) {
		# Extract the driver package using a switch statement to determine the file type
		switch -Wildcard ($FilePath) {
			"*.exe" {
				# Extract the driver package
				Write-DATLogEntry -Value "- Extracting driver package from $FilePath" -Severity 1
				Invoke-DATExecutable -FilePath $FilePath -Arguments "/s /e=`"$DriverFolder`"" | Out-Null
				
				<#
				global:Write-LogEntry -Value "- $($Product): Dell EXE format detected" -Severity 1
				$DellSilentSwitches = "/s /e=" + '"' + $DriverExtractDest + '"'
				global:Write-LogEntry -Value "- $($Product): Using $Make silent switches: $DellSilentSwitches" -Severity 1
				global:Write-LogEntry -Value "- $($Product): Extracting $Make drivers to $DriverExtractDest" -Severity 1
				Unblock-File -Path $($DownloadRoot + $Model + '\Driver Cab\' + $DriverCab)
				Start-Process -FilePath "$($DownloadRoot + $Model + '\Driver Cab\' + $DriverCab)" -ArgumentList $DellSilentSwitches -Verb RunAs
				$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
				# Wait for Lenovo Driver Process To Finish
				While ((Get-Process).name -contains $DriverProcess)
				{
					global:Write-LogEntry -Value "- $($Product): Waiting for extract process (Process: $DriverProcess) to complete..  Next check in 30 seconds" -Severity 1
					Start-Sleep -seconds 30
				}
				#>
				
			}
			"*.msi" {
				# Extract the driver package
				Write-DATLogEntry -Value "- Extracting driver package from $FilePath" -Severity 1
				Invoke-DATExecutable -FilePath $FilePath -Arguments "/a $DriverFolder" | Out-Null
			}
			"*.zip" {
				# Extract the driver package
				Write-DATLogEntry -Value "- Extracting driver package from $FilePath" -Severity 1
				Expand-Archive -Path $FilePath -DestinationPath $DriverFolder -Force | Out-Null
			}
			"*.cab" {
				try {
					# Extact the driver package and monitor for exit code
					Write-DATLogEntry -Value "- Extracting driver cab from $FilePath" -Severity 1 -UpdateUI
					$ExtractProcessPath = "C:\Windows\System32\expand.exe"
					$ExtractProcess = Start-Process -FilePath $ExtractProcessPath -ArgumentList "`"$FilePath`" -F:* `"$DriverFolder`"" -WindowStyle Hidden -PassThru -Wait
					
					# Wait for the extract process to complete
					while ([boolean](Get-Process -Id $ExtractProcess.Id -ErrorAction SilentlyContinue)) {
						# Wait for the process to complete
					}
					
					Write-DATLogEntry -Value "- Extract process terminated with exit code $($ExtractProcess.ExitCode)" -Severity 1
					
					# Check if the process completed successfully
					if ($ExtractProcess.ExitCode -eq 0) {
						Write-DATLogEntry -Value "- Successfully extracted driver package from $FilePath" -Severity 1 -UpdateUI
						
						# perform a recursive check for an x64 folder, up to 2 levels deep, and move the folder to the root
						Write-DATLogEntry -Value "- Moving items from $DriverFolder to parent path $DriverFolder to shorten folder paths" -Severity 1
						Get-ChildItem -Path $DriverFolder -Directory -Recurse -Depth 2 | Where-Object { $_.Name -match "x64" } | Move-Item -Destination $DriverFolder -Force
						
						# Cleanup folder
						if ((-not ([string]::IsNullOrEmpty($DriverFolder))) -and ([boolean](Test-Path -Path $DriverFolder -ErrorAction SilentlyContinue) -eq $true)) {
							# Only keep the x64 folder and its subfolders, clean up the rest
							Get-ChildItem -Path $DriverFolder -Directory | Where-Object { $_.Name -ne "x64" } | Remove-Item -Recurse -Force
						}
						
					} else {
						Write-DATLogEntry -Value "[Error] - Failed to extract driver package from $FilePath" -Severity 3
					}
				} catch {
					Write-DATLogEntry -Value "[Error] - Failed to extract driver package from $FilePath" -Severity 3
				}
			}
		}
	}
	
	# Create a .wim file using DISM with the contents from the driver package
	try {
		# Create a temporary mount folder for the driver package
		$DriverMountFolder = Join-Path -Path $Destination -ChildPath "Packaged\$OEM\$Model\$OS"
		if (-not (Test-Path -Path $DriverMountFolder)) {
			New-Item -Path $DriverMountFolder -ItemType Directory -Force | Out-Null
		}
		
		$WimDescription = "$OEM $Model $OS Driver Package"
		$WimFile = Join-Path -Path $DriverMountFolder -ChildPath "DriverPackage.wim"
		Write-DATLogEntry -Value "- DriverPackage: Mounting UNC path for WIM creation" -Severity 1 -UpdateUI
		
		$DismArgs = "/Capture-Image /ImageFile:`"$WimFile`" /CaptureDir:`"$DriverFolder`" /Name:`"$WimDescription`" /Description:`"$WimDescription`" /Compress:max"
		Write-DATLogEntry -Value "[DISM] - DriverPackage: DISM initiated with the following args- $DismArgs" -Severity 1 -UpdateUI
		$DismProcess = Start-Process "dism.exe" -ArgumentList $DismArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput .\DismAction.log -RedirectStandardError .\DismErrors.log
		
		if ($($DismProcess.ExitCode) -eq 0) {
			Write-DATLogEntry -Value "- DriverPackage: DISM process completed successfully" -Severity 1 -UpdateUI
			Set-DATRegistryValue -Name "PackagedDriverPath" -Value "$WimFile" -Type String
			Set-DATRegistryValue -Name "RunningMode" -Value "Extract Ready" -Type String
		} else {
			Write-DATLogEntry -Value "- DriverPackage: DISM process failed with exit code $($DismProcess.ExitCode)" -Severity 3 -UpdateUI
			Set-DATRegistryValue -Name "RunningState" -Value "Error" -Type String
			Set-DATRegistryValue -Name "RunningMode" -Value "ExtractFailure" -Type String
		}

	} catch {
		Write-DATLogEntry -Value "[Error] - Errors occured while attempting to create wim file." -Severity 3
	}
	
	# Call platformm specific function for Configuration Manager and Intune jobs
	switch -wildcard ($Platform) {
		"Config*" {
			#<code>
		}
		"Intune" {
			#<code>
		}
	}
}

function Create-DATConfigMgrPkg {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$DriverPackage,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$OEM,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Model,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$OS,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Architecture,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$Baseboards,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$PackagePath,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$SiteServer,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$SiteCode,
		[Parameter(Mandatory = $true)]
		[string]$Version
	)
	
	try {
		# Check for the Configuration Manager module, import if not already loaded, if missing log an error
		if (-not (Get-Module -Name ConfigurationManager)) {
			$ModuleName = (Get-Item $env:SMS_ADMIN_UI_PATH | Split-Path -Parent) + "\ConfigurationManager.psd1"
			
			# Test path to the Configuration Manager module, import if found
			if (Test-Path -Path $ModuleName) {
				Write-DATLogEntry -Value "- Loading ConfigMgr PowerShell module" -Severity 1
				Import-Module $ModuleName -Verbose
				$ConfigMgrModuleLoaded = $true
			} else {
				Write-DATLogEntry -Value "[Error] - Configuration Manager module not found" -Severity 3
			}
		} else {
			Write-DATLogEntry -Value "- Configuration Manager module already loaded" -Severity 1
			$ConfigMgrModuleLoaded = $true
		}
	} catch {
		Write-DATLogEntry -Value "[Error] - Failed to load Configuration Manager module" -Severity 3
	}
	
	# Create package if the Configuration Manager module is loaded
	if ($ConfigMgrModuleLoaded -eq $true) {
		# Get list of selected distribution points
		$RunningConfigurationValues = Get-ItemProperty -Path $global:RegPath
		$SelectedDistributionPoints = ($RunningConfigurationValues).SelectedDistributionPoints -split ","
		$SelectedDistributionPointGroups = ($RunningConfigurationValues).SelectedDistributionPointGroups -split ","
		$PackageType = ($RunningConfigurationValues).PackageType
		$InstallLocation = ($RunningConfigurationValues).InstallDirectory
		
		switch ($PackageType) {
			"Drivers" {
				$ConfigMgrPkgPath = "Package\Driver Packages\$OEM"
			}
			"BIOS" {
				$ConfigMgrPkgPath = "Package\BIOS Packages\$OEM"
			}
		}
		
		# Test if the package path root exits and proceed if it does
		if ((Test-Path -Path $PackagePath) -eq $true) {
			# Create a new package for the driver package
			try {
				
				# Connect to the Configuration Manager server
				Write-DATLogEntry -Value "- Connecting to site server $SiteServer" -Severity 1
				Connect-DATConfigMgr -SiteServer $SiteServer -WinRMOverSSL $true
				
				# Variables
				$CMPackage = ("Drivers - " + "$OEM " + $Model + " - " + $OS + " " + $Architecture)
				
				# Check if package with the same version already exists
				Write-DATLogEntry -Value "- Querying existing packages to avoid duplicates" -Severity 1
				Set-Location -Path "$($SiteCode):\"
				$ExistingCMPackage = [boolean](Get-CMPackage -Fast | Select-Object Name, Version | Where-Object { $_.Name -eq "$CMPackage" -and $_.Version -eq "$Version" })
				Set-Location -Path "$InstallLocation"
				
				# Process for newer packages
				if ($ExistingCMPackage -eq $false) {
					# Check for driver package destination folder and create if missing
					$PackagePath = Join-Path -Path $PackagePath -ChildPath "$OEM\$Model\$OS\$Architecture\$Version"
					if (-not (Test-Path -Path $PackagePath)) {
						Write-DATLogEntry -Value "- Creating destination folder at $PackagePath" -Severity 1
						New-Item -Path $PackagePath -ItemType Directory -Force | Out-Null
					}
					
					# Copy the driver package to the package path
					Write-DATLogEntry -Value "- Copying driver package to $PackagePath" -Severity 1
					Copy-Item -Path $DriverPackage -Destination $PackagePath -Force -Verbose
					
					# Create a new package
					try {
						
						Write-DATLogEntry -Value "- Creating $CMPackage package" -Severity 1 -UpdateUI
						Write-DATLogEntry -Value "- Switching to Configuration Manager drive $($SiteCode):\"
						Set-Location -Path "$($SiteCode):\"
						$PackageDetails = New-CMPackage -Name "$CMPackage" -path "$PackagePath" -Manufacturer "$OEM" -Description "Models included:$($Baseboards)" -Version $Version
						$MifVersion = $OS + " " + $Architecture
						Set-CMPackage -Name "$CMPackage" -MifName "$Model" -MifVersion $MifVersion
						Write-DATLogEntry -Value "- Created new Configuration Manager package" -Severity 1 -UpdateUI
						
						# Check For Driver Package
						$ConfiMgrPackage = Get-CMPackage -Name $CMPackage -Fast | Select-Object PackageID, Version, Name | Where-Object {
							$_.Version -eq $Version
						}
						
					} catch {
						Write-DATLogEntry -Value "[Error] - Failed to create Configuration Manager package" -Severity 3
					}
					
					# Move package to OEM folder
					try {
						
						if (-not ([string]::IsNullOrEmpty($($ConfiMgrPackage.PackageID)))) {
							Write-DATLogEntry -Value "- Driver package $($ConfiMgrPackage.PackageID) created successfully" -Severity 1
							Write-DATLogEntry -Value "- Moving package to OEM folder" -Severity 1
							# Check for the OEM folder and create if missing
							if (-not (Test-Path -Path "$ConfigMgrPkgPath")) {
								Write-DATLogEntry -Value "- Creating OEM folder at $ConfigMgrPkgPath" -Severity 1
								New-Item -Path "$ConfigMgrPkgPath" -Force | Out-Null
							}
						}
						# Move package
						Move-CMObject -FolderPath "$ConfigMgrPkgPath" -ObjectID $ConfiMgrPackage.PackageID
					} catch {
						Write-DATLogEntry -Value "[Warning] - Failed to move driver pacakge to OEM folder" -Severity 2
					}
					
					# Distribute the package to the selected distribution points
					try {
						Write-DATLogEntry -Value "- Distributing $($ConfiMgrPackage.PackageID) to selected distribution points / groups " -Severity 1 -UpdateUI
						if ($SelectedDistributionPointGroups -ne $null) {
							# Loop through the selected distribution point groups and distribute the package
							foreach ($DPG in $SelectedDistributionPointGroups) {
								Write-DATLogEntry -Value "- Distributing Package $($ConfiMgrPackage.PackageID) to Distribution Point Group -  $DPG" -Severity 1
								Start-CMContentDistribution -PackageID $ConfiMgrPackage.PackageID -DistributionPointGroupName "$DPG"
								
							}
						} elseif ($SelectedDistributionPoints -ne $null) {
							# Loop through the selected distribution points and distribute the package
							foreach ($DP in $SelectedDistributionPoints) {
								Write-DATLogEntry -Value "- Distributing Package $PackageID to Distribution Point -  $DP" -Severity 1
								Start-CMContentDistribution -PackageID $ConfiMgrPackage.PackageID -DistributionPointName "$DP"
							}
						}
						Write-DATLogEntry -Value "- Successfully started Configuration Manager distribution job for package $($ConfiMgrPackage.PackageID)" -Severity 1 -UpdateUI
					} catch {
						Write-DATLogEntry -Value "[Error] - Failed to distribute Configuration Manager package" -Severity 3
					}
				} else {
					Write-DATLogEntry -Value "- A package exists with the same version number. Skipping package creation." -Severity 1
				}
			} catch {
				Write-DATLogEntry -Value "[Error] - Issues occured while attempting to create Configuration Manager package" -Severity 3
				Write-DATLogEntry -Value "[Error] - $($_.Exception.Message)" -Severity 3
			}
		}
	} else {
		Write-DATLogEntry -Value "[Error] - Configuration Manager module not loaded. Unable to proceed." -Severity 3
	}
}

# Review
function Publish-DATConfigMgrPkg {
	param
	(
		[parameter(Mandatory = $true)]
		[string]$Product,
		[string]$PackageID,
		[string]$ImportInto
		
	)
	# Distribute Content - Selected Distribution Points
	for ($Row = 0; $Row -lt $DPGridView.RowCount; $Row++) {
		if ($DPGridView.Rows[$Row].Cells[0].Value -eq $true) {
			if ($ImportInto -match "Standard") {
				Start-CMContentDistribution -PackageID $PackageID -DistributionPointName $($DPGridView.Rows[$Row].Cells[1].Value)
			}
			if ($ImportInto -match "Driver") {
				Start-CMContentDistribution -DriverPackageID $PackageID -DistributionPointName $($DPGridView.Rows[$Row].Cells[1].Value)
			}
			Write-DATLogEntry -Value "- $($Product): Distributing Package $PackageID to Distribution Point - $($DPGridView.Rows[$Row].Cells[1].Value) " -Severity 1
		}
	}
	# Distribute Content - Selected Distribution Point Groups
	for ($Row = 0; $Row -lt $DPGGridView.RowCount; $Row++) {
		if ($DPGGridView.Rows[$Row].Cells[0].Value -eq $true) {
			if ($ImportInto -match "Standard") {
				Start-CMContentDistribution -PackageID $PackageID -DistributionPointGroupName $($DPGGridView.Rows[$Row].Cells[1].Value)
			}
			if ($ImportInto -match "Driver") {
				Start-CMContentDistribution -DriverPackageID $PackageID -DistributionPointGroupName $($DPGGridView.Rows[$Row].Cells[1].Value)
			}
			Write-DATLogEntry -Value "- $($Product): Distributing Package $PackageID to Distribution Point Group - $($DPGGridView.Rows[$Row].Cells[1].Value) " -Severity 1
		}
	}
}


# Function that exports the $global:regpath is a .reg file
function Export-DATRegistry {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$ExportPath
	)
	
	# Export the registry path to a .reg file
	Export-DATRegistry -Path $global:RegPath -ExportPath $ExportPath
}

# Function that imports the $global:regpath from a .reg file
function Import-DATRegistry {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$ImportPath
	)
	
	# Import the registry path from a .reg file
	Import-DATRegistry -Path $global:RegPath -ImportPath $ImportPath
}

<#
	.SYNOPSIS
		A brief description of the Start-DownloadProcess function.
	
	.DESCRIPTION
		This function starts and waits for each specified model to complete as a background job
	
	.PARAMETER $global:ScriptDirectory
		A description of the $global:ScriptDirectory parameter.
	
	.PARAMETER $global:RegPath
		A description of the $global:RegPath parameter.
	
	.PARAMETER $global:RunningMode
		A description of the $global:RunningMode parameter.
	
	.PARAMETER $global:SeletedModels
		A description of the $global:SeletedModels parameter.
	
	.EXAMPLE
		PS C:\> Start-DownloadProcess
	
	.NOTES
		Additional information about the function.
#>
function Start-DATModelProcessing {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[String]$ScriptDirectory,
		[Parameter(Mandatory = $true)]
		[String]$RegPath,
		[Parameter(Mandatory = $true)]
		[String]$RunningMode,
		[Parameter(Mandatory = $true)]
		[pscustomobject]$SeletedModels
	)
		
	# Import Module
	Import-Module -Name DriverAutomationToolCore
	Write-DATLogEntry -Value "- Running for $($global:SelectedModels.Count) models" -Severity 1
	
	# Variables
	Write-DATLogEntry -Value "- Quering registy for running details using path $global:RegPath" -Severity 1
	$RunningConfigurationValues = Get-ItemProperty -Path $global:RegPath
	$TotalJobs = ($RunningConfigurationValues).TotalJobs
	[int]$CurrentJob = ($RunningConfigurationValues).CurrentJob
	if ([string]::IsNullOrEmpty($CurrentJob)) {
		# Set initial value
		$CurrentJob = 1
	}
		
	# Downlaod content scriptblock
	$BuildPackages = {
		param (
			[parameter(Mandatory = $true)]
			[string]$global:ScriptDirectory,
			[parameter(Mandatory = $true)]
			[string]$global:RegPath,
			[parameter(Mandatory = $true)]
			[string]$global:LogDirectory,
			[parameter(Mandatory = $true)]
			[string]$global:RunningMode,
			[parameter(Mandatory = $true)]
			[pscustomobject]$global:Model
		)
		
		# Import Module
		Import-Module -Name DriverAutomationToolCore
		
		# Get OEM download sources
		Get-DATOEMModelInfo -RequiredOEMs $Model.OEM -OS $Model.OS -Architecture $Model.Architecture
		
		# Set Registry values
		Set-DATRegistryValue -Name "CurrentModel" -Value "$($Model.Model)" -Type String
		Set-DATRegistryValue -Name "CurrentOEM" -Value "$($Model.OEM)" -Type String
		Set-DATRegistryValue -Name "CurrentBaseboards" -Value "$($Model.Baseboards)" -Type String
		# Get the current running process ID
		$RunningProcessID = $PID
		Set-DATRegistryValue -Name "RunningProcessID" -Value $RunningProcessID -Type String

		
		# Obtain download link for model
		Write-DATLogEntry -Value "- Obtaining download link for $($Model.Model)" -Severity 1
		Write-DATLogEntry -Value "-- Model OEM is $($Model.OEM)"
		Write-DATLogEntry -Value "-- Model OS is $($Model.OS)"
		Write-DATLogEntry -Value "-- Model Architecture is $($Model.Architecture)"
		Write-DATLogEntry -Value "-- Model is $($Model.Model)"
		
		<#
		# Create a new PS Custom object that contains the model details
		$Model = New-Object -TypeName PSObject
		$Model | Add-Member -MemberType NoteProperty -Name "OEM" -Value "Acer" -Force
		$Model | Add-Member -MemberType NoteProperty -Name "Model" -Value "TravelMate Spin P414RN-54" -Force
		$Model | Add-Member -MemberType NoteProperty -Name "Baseboards" -Value "TravelMate Spin P414RN-54" -Force
		$Model | Add-Member -MemberType NoteProperty -Name "OS" -Value "Windows 11 24H2" -Force
		$Model | Add-Member -MemberType NoteProperty -Name "Architecture" -Value "x64" -Force
		#>
			
		# Build supported models array
		Get-DATOEMModelInfo -RequiredOEMs $Model.OEM -OS $Model.OS -Architecture $Model.Architecture
		
		# Invoke download for all OEM's except HP
		if ($($Model.OEM) -ne "HP") {
			# Get driver download
			$global:DownloadURL = Get-DATOEMDownloadLinks -OEM $Model.OEM -OS "$($Model.OS)" -Architecture $Model.Architecture -DownloadType driver -Model $Model.Model
			Write-DATLogEntry -Value "- Download URL is $global:DownloadURL" -Severity 1
			Write-DATLogEntry -Value "-- Reg path is $global:RegPath" -Severity 1
			Write-DATLogEntry -Value "-- Setitng download URL to $global:DownloadURL" -Severity 1
		}
		
		if ((-not ([string]::IsNullOrEmpty($global:DownloadURL)) -and ($global:DownloadURL -ne "Unknown")) -or ($($Model.OEM) -eq "HP")) {
			Set-DATRegistryValue -Name "DownloadURL" -Value $global:DownloadURL -Type String
			Set-DATRegistryValue -Name "RunningState" -Value "Running" -Type String
			Set-DATRegistryValue -Name "RunningMode" -Value "Download" -Type String
						
			# Get current status message from the registry
			$RunningConfigurationValues = Get-ItemProperty -Path $global:RegPath
			$CurrentOEM = ($RunningConfigurationValues).CurrentOEM
			$CurrentModel = ($RunningConfigurationValues).CurrentModel
			$CurrentOS = ($RunningConfigurationValues).OS
			$ExtractPath = ($RunningConfigurationValues).TempStoragePath
			$DriverFile = ($RunningConfigurationValues).WorkingFile
			
			# Define full download path
			$DownloadPath = Join-Path -Path "$(($RunningConfigurationValues).TempStoragePath)" -ChildPath "$CurrentOEM\$CurrentModel\$CurrentOS"
			Write-DATLogEntry -Value "- Starting invoke content download for $($global:DownloadURL) to $($DownloadPath)" -Severity 1
			
			# Invoke download for all OEM's except HP
			if ($CurrentOEM -ne "HP") {
				Invoke-DATContentDownload -DownloadURL "$global:DownloadURL" -DownloadDestination "$DownloadPath" -Verbose
			} else {
				# Obtain the first baseboard for matching process;
				$CurrentBaseboard = $($Model.Baseboards).Split(",") | Select-Object -First 1
				# Get OS version from current OS string, splitting on the second space
				$OSVersion = ($CurrentOS -split " ")[2]
				$OS = ($CurrentOS -split " ")[0..1] -join " "
				$SoftPawTempLocation = Join-Path -Path "$(($RunningConfigurationValues).TempStoragePath)" -ChildPath "$CurrentOEM\$CurrentModel\$CurrentOS\SoftPaqs"
				Write-DATLogEntry -Value "- Using $CurrentBaseboard as the matching baseboard value" -Severity 1
				Write-DATLogEntry -Value "- Using $OS as the matching OS value" -Severity 1
				Write-DATLogEntry -Value "- Using $OSVersion as the matching OS version value" -Severity 1

				try {
					Invoke-DATOEMDownloadModule -OEM "$CurrentOEM" -SystemSKU $CurrentBaseboard -WindowsBuild $OS -WindowsVersion $OSVersion  -TempDirectory $SoftPawTempLocation -DownloadDestination $DownloadPath 
				} catch {
					Write-DATLogEntry -Value "- Error invoking OEM download module: $($_.Exception.Message)" -Severity 3
					throw
				}
			}
			
			# Get current status message from the registry
			$RunningConfigurationValues = Get-ItemProperty -Path $global:RegPath
			$RunningMode = ($RunningConfigurationValues).RunningMode
			$PackageType = ($RunningConfigurationValues).PackageType
			
			# OEM specific package naming and versioning
			switch ($CurrentOEM) {
				"Acer" {
					# Driver revision in the format of YYYYMMDD
					$Version = (Get-Date).ToString("yyyyMMdd")
				}
				"HP" {
					# Driver revision in the format of YYYYMMDD
					$Version = (Get-Date).ToString("yyyyMMdd")
				}
			}
			Set-DATRegistryValue -Name "PackageVersion" -Value "$Version" -Type String
			
			if (($RunningMode -eq "Download Completed") -and ($PackageType -eq "Drivers")) {
				Set-DATRegistryValue -Name "Runningmode" -Value "Extracting" -Type String
				
				# Get current status message from the registry
				$RunningConfigurationValues = Get-ItemProperty -Path $global:RegPath
				$CurrentOEM = ($RunningConfigurationValues).CurrentOEM
				$CurrentModel = ($RunningConfigurationValues).CurrentModel
				$CurrentOS = ($RunningConfigurationValues).OS
				$ExtractPath = ($RunningConfigurationValues).TempStoragePath
				$DriverFile = ($RunningConfigurationValues).WorkingFile
				
				# Extract path with version 
				$ExtractPath = Join-Path -Path $ExtractPath -ChildPath $Version
				Write-DATLogEntry -Value "- Extract path set to $ExtractPath" -Severity 2
				
				# Call driver extract function
				Invoke-DATDriverFilePackaging -FilePath "$DriverFile" -OEM $CurrentOEM -Model $CurrentModel -Destination $ExtractPath -OS $CurrentOS
			}
			
			# Get current status message from the registry
			$RunningConfigurationValues = Get-ItemProperty -Path $global:RegPath
			$RunningMode = ($RunningConfigurationValues).RunningMode
			$PackageType = ($RunningConfigurationValues).PackageType
			$Platform = ($RunningConfigurationValues).Platform

			# Start build job
			if (($RunningMode -eq "Extract Ready") -and ($Platform -eq "Configuration Manager")) {
				Set-DATRegistryValue -Name "Runningmode" -Value "Building Driver Package" -Type String
				
				# Get current status message from the registry
				Write-DATLogEntry -Value "- Global reg path is $global:RegPath" -Severity 1
				$RunningConfigurationValues = Get-ItemProperty -Path $global:RegPath
				$CurrentOEM = ($RunningConfigurationValues).CurrentOEM
				$CurrentModel = ($RunningConfigurationValues).CurrentModel
				$CurrentOS = ($RunningConfigurationValues).OS
				$CurrentArchitecture = ($RunningConfigurationValues).Architecture
				$CurrentModelBaseboards = ($RunningConfigurationValues).CurrentBaseboards
				$PackagePath = ($RunningConfigurationValues).PackageStoragePath
				$DriverPackage = ($RunningConfigurationValues).PackagedDriverPath
				$SiteServer = ($RunningConfigurationValues).SiteServer
				$global:Sitecode = ($RunningConfigurationValues).SiteCode
				$PackageVersion = ($RunningConfigurationValues).PackageVersion
				
				Create-DATConfigMgrPkg -DriverPackage $DriverPackage -OEM $CurrentOEM -Model $CurrentModel -Baseboards $CurrentModelBaseboards -OS $CurrentOS -Architecture $CurrentArchitecture -PackagePath $PackagePath -SiteServer $SiteServer -SiteCode $SiteCode -Version $PackageVersion
			}
		} else {
			Set-DATRegistryValue -Name "DownloadURL" -Value "Unkown" -Type String
			Set-DATRegistryValue -Name "RunningState" -Value "Error" -Type String
			Set-DATRegistryValue -Name "RunningMode" -Value "Download" -Type String
		}
	}
	
	# Start downloads
	foreach ($Model in $global:SelectedModels) {
		# Get download URL
		#Write-LogEntry -Value "- Starting build process for model $($Model.Model)" -Severity 1
		Write-DATLogEntry -Value "- Starting build process for model $($Model.Model)" -Severity 2
		$BuildPackageJob = Start-Job -ScriptBlock $BuildPackages -Name "[$global:ProductName] - $($Model.Model) Downloads" -ArgumentList ($global:ScriptDirectory, $global:RegPath, $global:LogDirectory, $global:RunningMode, [pscustomobject]$Model) -Verbose
		
		# Wait for job to start		
		Start-Sleep -Seconds 2
		
		$BuildPackageJobId = $BuildPackageJob.Id
		$BuildPackageJobState = $BuildPackageJob.State
		
		# Monitor job
		while ($(Get-Job -Id $BuildPackageJobId | Select-Object -ExpandProperty State) -eq "Running") {
			# Wait for process1
		}
		
		$BuildPackageJobState = Get-Job -Id $BuildPackageJobId | Select-Object -ExpandProperty State
		
		switch ($BuildPackageJobState) {
			"Completed" {
				Write-DATLogEntry -Value "[Success] - Successfully completed build job for $($Model.Model)" -Severity 2
				Write-DATLogEntry -Value "- Incrementing completed model value" -Severity 2
				Set-DATRegistryValue -Name "CompletedJobs" -Value "$CurrentJob" -Type String -Verbose
				$CurrentJob++
				Set-DATRegistryValue -Name "CurrentJob" -Value $CurrentJob -Type String
			}
		}
	}
}

<#
	.SYNOPSIS
		A brief description of the Invoke-DATOEMContentDownload function.
	
	.DESCRIPTION
		This function uses OEM provided modules to download and compress driver packages.
	
	.PARAMETER OEM
		A description of the OEM parameter.
	
	.PARAMETER SystemSKU
		A description of the SystemSKU parameter.
	
	.PARAMETER WindowsBuild
		A description of the WindowsBuild parameter.
	
	.PARAMETER WindowsVersion
		A description of the WindowsVersion parameter.
	
	.PARAMETER DownloadDestination
		A description of the DownloadDestination parameter.
	
	.PARAMETER RegPath
		A description of the RegPath parameter.
	
	.PARAMETER LogDirectory
		A description of the LogDirectory parameter.
	
	.PARAMETER ScriptDirectory
		A description of the ScriptDirectory parameter.
	
	.PARAMETER TempDirectory
		A description of the TempDirectory parameter.
	
	.EXAMPLE
		PS C:\> Invoke-DATOEMContentDownload
	
	.NOTES
		Additional information about the function.
#>
function Invoke-DATOEMDownloadModule {
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$OEM,
		[ValidateNotNullOrEmpty()]
		[string]$SystemSKU,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$WindowsBuild,
		[ValidateNotNullOrEmpty()]
		[string]$WindowsVersion,
		[ValidateNotNullOrEmpty()]
		[string]$DownloadDestination,
		[ValidateNotNullOrEmpty()]
		[string]$RegPath,
		[ValidateNotNullOrEmpty()]
		[string]$LogDirectory,
		[ValidateNotNullOrEmpty()]
		[string]$TempDirectory
	)
	
	# Import DriverAutomationToolCore Module
	Import-Module -Name DriverAutomationToolCore
	Write-DATLogEntry -Value "- Loading DriverAutomtionToolCore module" -Severity 1 -UpdateUI
	Write-DATLogEntry -Value "[$SystemSKU Driver Job] - Loading pre-requisite PowerShell modules" -Severity 1 -UpdateUI
	
	# Build driver packages specific to vendor requirements
	switch ($OEM) {
		"HP" {
			
			Write-DATLogEntry -Value "- Calling HP CMSL function" -Severity 1
			Write-DATLogEntry -Value "- Selected Windows build is $WindowsBuild" -Severity 1
			Write-DATLogEntry -Value "- Selected Windows version is $WindowsVersion" -Severity 1
			Write-DATLogEntry -Value "- Driver package path is $DownloadDestination" -Severity 1
						
			# Import required PS modules
			Write-DATLogEntry -Value "- Loading HP CMSL module" -Severity 1 -UpdateUI
			Import-Module -Name HPCMSL
			
			switch -wildcard ($WindowsBuild) {
				"*Windows 11*" {
					$TargetWindowsBuild = "Win11"
				}
				"*Windows 10*" {
					$TargetWindowsBuild = "Win10"
				}
			}
			
			# Create new driver package
			Write-DATLogEntry -Value "[Driver Package] - Starting background job for HP SKU $SystemSKU" -Severity 1 -UpdateUI
			Write-DATLogEntry -Value "- Selected OS is $WindowsBuild" -Severity 1
			Write-DATLogEntry -Value "- Selected OS version is $WindowsVersion" -Severity 1
			Write-DATLogEntry -Value "- Download destination $DownloadDestination" -Severity 1
			Write-DATLogEntry -Value "- Registry location is $global:RegPath" -Severity 1
			Write-DATLogEntry -Value "- Log directory is $global:LogDirectory" -Severity 1
			
			try {
				# Create temporary download directory
				if ((Test-Path -Path $TempDirectory) -eq $false) {
					Write-DATLogEntry -Value "- Creating required folder at $TempDirectory" -Severity 1
					New-Item -Path "$TempDirectory" -ItemType Directory -Force | Out-Null
				}
				
				# Create model directory
				if ((Test-Path -Path $DownloadDestination) -eq $false) {
					Write-DATLogEntry -Value "- Creating required folder at $DownloadDestination" -Severity 1
					New-Item -Path "$DownloadDestination" -ItemType Directory -Force | Out-Null
				}
				
				# Clear model directory if re-running
				if ((Get-ChildItem -Path $DownloadDestination -Recurse -Filter *.wim).Count -ge 1) {
					Write-DATLogEntry -Value "- Updating driver package, removing $WindowsBuild $WindowsVersion legacy driver package(s)" -Severity 1
					Get-ChildItem -Path "$DownloadDestination" -Recurse -Filter *.wim | Remove-Item -Force
				}
				
				# Use temp location as base directory
				Set-Location -Path $DownloadDestination
				
				# Create registry entries				
				# Validate file path format using regex for local or network paths
				if (($global:DriverCacheDir -match "^[a-zA-Z]:\\") -or ($global:DriverCacheDir -match "^\\\\")) {
					Set-DATRegistryValue -Name "DriverCacheDir" -Value "$global:DriverCacheDir" -Type String
				}
				if (-not ([string]::IsNullOrEmpty($global:OrganisationName))) {
					Set-DATRegistryValue -Name "OrganisationName" -Value "$global:OrganisationName" -Type String
				}
				if (-not ([string]::IsNullOrEmpty($global:LogDirectory))) {
					Set-DATRegistryValue -Name "LogPath" -Value "$global:LogDirectory" -Type String
				}
				if (-not ([string]::IsNullOrEmpty($global:RegPath))) {
					Set-DATRegistryValue -Name "RegPath" -Value "$global:RegPath" -Type String
				}
				if (-not ([string]::IsNullOrEmpty($global:TrimmedProductName))) {
					Set-DATRegistryValue -Name "TrimmedProductName" -Value "$global:TrimmedProductName" -Type String
				}
				
				# Download driver package
				Write-DATLogEntry -Value "- Downloading drivers for OS $($WindowsBuild.TrimEnd()) $($WindowsVersion.Trim()) on hardware platform HP SKU $SystemSKU" -Severity 1 -UpdateUI
				
				# Script block to download drivers
				$DownloadDrivers = {
					param (
						[parameter(Mandatory = $true)]
						[string]$SystemSKU,
						[parameter(Mandatory = $true)]
						[string]$WindowsBuild,
						[parameter(Mandatory = $true)]
						[string]$WindowsVersion,
						[parameter(Mandatory = $true)]
						[string]$DownloadDestination,
						[parameter(Mandatory = $true)]
						[string]$TempDownloadPath,
						[parameter(Mandatory = $true)]
						[string]$global:regpath
					)

					try {

						# Import DriverAutomationToolCore Module
						Import-Module -Name DriverAutomationToolCore
					
						# Import HP CMSL module
						Write-DATLogEntry -Value "- Importing HP CMSL module" -Severity 1
						Import-Module -Name HPCMSL
					} catch {
						Write-DATLogEntry -Value "[Error] - Failed to import required modules" -Severity 3; break
					}
					try {
					
						# Download drivers
						Write-DATLogEntry -Value "[HP Softpaq Download] - Downloading drivers for HP SKU $SystemSKU" -Severity 1
					
						# Output parameters to the log file for troubleshooting
						Write-DATLogEntry -Value "- HP SKU is $SystemSKU" -Severity 1
						Write-DATLogEntry -Value "- Windows build is $WindowsBuild" -Severity 1
						Write-DATLogEntry -Value "- Windows version is $WindowsVersion" -Severity 1
						Write-DATLogEntry -Value "- Download destination is $DownloadDestination" -Severity 1
						Write-DATLogEntry -Value "- Temp download path is $TempDownloadPath" -Severity 1
						Write-DATLogEntry -Value "- Registry path is $global:regpath" -Severity 1

						switch -wildcard ($WindowsBuild) {
							"Windows 11*" { 
								$OS = "win11"
							}
							"Windows 10*" { 
								$OS = "win10" 
							}
						}

						# Get the current running process ID
						$RunningProcessID = $PID
						$RunningProcess = "PowerShell"
						Set-DATRegistryValue -Name "RunningProcessID" -Value $RunningProcessID -Type String
						Set-DATRegistryValue -Name "RunningProcess" -Value $RunningProcess -Type String
						Set-DATRegistryValue -Name "RunningState" -Value "Running" -Type String
						Set-DATRegistryValue -Name "DownloadedSoftpaqs" -Value "0" -Type String
						Set-DATRegistryValue -Name "TotalSoftPaqsToDownload" -Value "0" -Type String
						Write-DATLogEntry -Value "- Operating System set as `"$OS`" for HP commandlet" -Severity 1
						
						# Calling HP commandlet to download drivers
						Write-DATLogEntry -value "- Starting HP driver download process" -Severity 1
						# Remove existing WIM
						if ((Get-ChildItem -Path $DownloadDestination -Filter *.wim).Count -ge 1) {
							Write-DATLogEntry -Value "- Removing previously created WIM file(s)" -Severity 1
							Get-ChildItem -Path $DownloadDestination -Filter *.wim | Remove-Item -Force
						}

						# Invoke HP driver download with WhatIf parameter to obtain SoftPaq information and count
						Write-DATLogEntry -Value "- Invoking HP driver download to obtain SoftPaq information" -Severity 1
					
						try {
							# Redirect WhatIf output to variables
							$SoftPaqInfo = $null
							$SoftPaqError = $null
							New-HPDriverPack -Platform "$SystemSKU" -Os "$OS" -OSVer "$WindowsVersion" -Format wim -Path "$DownloadDestination" -TempDownloadPath "$TempDownloadPath" -RemoveOlder -WhatIf -InformationVariable SoftPaqInfo -ErrorVariable SoftPaqError
							
							# Log captured information
							if ($SoftPaqInfo) {
								# Convert InformationRecord objects to strings
								$SoftPaqLines = $SoftPaqInfo | ForEach-Object { $_.MessageData.ToString() }
								
								# Foreach line which begins with "sp" write to log
								$SoftPaqLines | Where-Object { $_ -match '^\s+sp\d+' } | ForEach-Object { 
									Write-DATLogEntry -Value "-- Download required - $($_.Trim())" -Severity 1 
								}
								
								# Count the number of SoftPaqs to be downloaded
								$SoftPaqCount = ($SoftPaqLines | Where-Object { $_ -match '^\s+sp\d+' }).Count
								Write-DATLogEntry -Value "- Total SoftPaqs to be downloaded: $SoftPaqCount" -Severity 1
								# Write the SoftPaq count to the registry
								Set-DATRegistryValue -Name "TotalSoftPaqsToDownload" -Value "$SoftPaqCount" -Type String
							}
							
							if ($SoftPaqError) {
								Write-DATLogEntry -Value "- SoftPaq WhatIf Errors: $($SoftPaqError | Out-String)" -Severity 2
							}
						} catch {
							Write-DATLogEntry -Value "- Error during WhatIf operation: $($_.Exception.Message)" -Severity 3; break
						}

						try {
							# Actual download and package creation
							New-HPDriverPack -Platform "$SystemSKU" -Os "$OS" -OSVer "$WindowsVersion" -Format wim -Path "$DownloadDestination" -TempDownloadPath "$TempDownloadPath" -RemoveOlder -InformationVariable SoftPaqInfo -ErrorVariable SoftPaqError
						}
						catch {
							Write-DATLogEntry -Value "[Error] - Issues occured during HP driver download and packaging process. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; break
						}

						try {
							# Set registry values
							$PackageDriverPath = Get-ChildItem -Path $DownloadDestination -Filter *.wim | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1 | Select-Object -ExpandProperty FullName
				
						}
						catch {
							Write-DATLogEntry -Value "[Error] - Issues occured while obtaining the driver package path. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; break
						}

		
						if ([string]::IsNullOrEmpty($PackageDriverPath)) {
							Write-DATLogEntry -Value "[Error] - No driver package was created. Stopping job" -Severity 3; break
						} else {
							# Set registry values
							Set-DATRegistryValue -Name "PackagedDriverPath" -Value "$PackageDriverPath" -Type String
							Write-DATLogEntry -Value "- HP Driver Package WIM created at $PackageDriverPath" -Severity 1
							Write-DATLogEntry -Value "- Driver package job completed successfully" -Severity 1

							# Set completed state
							Set-DATRegistryValue -Name "RunningMode" -Value "Download Completed" -Type String
						}
					} catch {
						Write-DATLogEntry -Value "[Error] - Issues occured while using the HP PowerShell commandlet. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3
					}
				}

				# Start job
				Write-DATLogEntry -Value "- Starting HP driver download job as a background process" -Severity 1
				Write-DATLogEntry -Value "- Job parameters:" -Severity 1
				Write-DATLogEntry -Value "-- System SKU: $SystemSKU" -Severity 1
				Write-DATLogEntry -Value "-- Windows Build: $WindowsBuild" -Severity 1
				Write-DATLogEntry -Value "-- Windows Version: $WindowsVersion" -Severity 1
				Write-DATLogEntry -Value "-- Download Destination: $DownloadDestination" -Severity 1
				Write-DATLogEntry -Value "-- Temp Directory: $TempDirectory" -Severity 1

				$DownloadDriversJob = Start-Job -ScriptBlock $DownloadDrivers -Name "[Driver Automation Tool] - HP Driver Download" -ArgumentList ($SystemSKU, $WindowsBuild, $WindowsVersion, $DownloadDestination, $TempDirectory, $global:RegPath) -Verbose
				$DownloadDriversJobId = $DownloadDriversJob.Id
				
				# Wait for the job to start
				Start-Sleep -Seconds 10

				Write-DATLogEntry -value "- HP download started as a background process. Monitoring for completion. Job ID $DownloadDriversJobId" -severity 1

				# Set initial counter value
				$DownloadStartTime = Get-DATLocalSystemTime
				$DownloadEndTime = $DownloadStartTime.AddMinutes(30)
				Write-DATLogEntry -Value "- HP driver download and packaging process has started" -Severity 1
				Write-DATLogEntry -Value "- Download process will run for a maximum of 30 minutes" -Severity 1

				# Get current status message from the registry
				$RunningConfigurationValues = Get-ItemProperty -Path $global:RegPath
				$RunningProcessID = ($RunningConfigurationValues).RunningProcessID
				Write-DATLogEntry -Value "[HP Job Monitor] - Monitoring process ID $RunningProcessID" -Severity 1
				
				# Monitor job
				$DownloadProcessCounter = 0
				$CurrentSoftPaq = 0
				while ($(Get-Job -Id $DownloadDriversJobId | Select-Object -ExpandProperty State) -eq "Running") {

					# Monitor the total file size of all exe files in the root of the temp download path
					$DownloadedBytes = (Get-ChildItem -Path "$TempDirectory" -Recurse -Filter *.exe | Measure-Object -Property Length -Sum).Sum
					if (-not([string]::IsNullOrEmpty($DownloadedBytes)) -and $DownloadedBytes -gt 0) {
						# Used for debugging download size
						#Write-DATLogEntry -Value "- Downloaded bytes so far: $DownloadedBytes" -Severity 2
					} 

					# Monitor the number of downloaded SoftPaqs
					$TotalSoftPaqsToDownload = (Get-ItemProperty -Path $global:RegPath).TotalSoftPaqsToDownload
					$DownloadedSoftPaqs = (Get-ChildItem -Path "$TempDirectory" -Filter sp*.exe).Count
					if ($DownloadedSoftPaqs -gt $CurrentSoftPaq) {
						$CurrentSoftPaq++
						Write-DATLogEntry -Value "- Downloaded SoftPaqs so far: $DownloadedSoftPaqs of $TotalSoftPaqsToDownload" -Severity 2
						# Write downloaded SoftPaq count to registry
						Set-DATRegistryValue -Name "DownloadedSoftPaqs" -Value "$DownloadedSoftPaqs" -Type String
					}
					
					# Report download progress if bytes are greater than 0
					if ($DownloadedBytes -gt 0) {
						# Increment download process counter
						$DownloadProcessCounter++

						# Convert download size to MB and set registry value
						$DownloadSizeMB = [math]::Round(($DownloadedBytes / 1MB), 2)
						
						# Update registry
						Set-DATRegistryValue -Name "BytesTransferred" -Value $DownloadedBytes -Type String
						Set-DATRegistryValue -Name "DownloadSize" -Type String -Value "$DownloadSizeMB" -Verbose
						
						# Convert bytes to MB/GB
						$DownloadMB = [math]::Round($DownloadedBytes / 1MB, 2)
						$DownloadGB = [math]::Round($DownloadedBytes / 1GB, 2)
						
						# Set download speed in MB/s
						$DownloadSpeed = [math]::Round($DownloadMB / ((Get-Date) - $DownloadStartTime).TotalSeconds, 2)
						
						# Set message body for download progress
						$DownloadMsg = "- Downloaded $DownloadGB GB at a rate of $DownloadSpeed MB/s"
						
						# Update registry with download progress
						Set-DATRegistryValue -Name "RunningMessage" -Type String -Value "$($DownloadMsg.TrimStart('- '))" -Verbose
					}
			
				}
				
				if ((Get-Job -Id $DownloadDriversJobId | Select-Object -ExpandProperty State) -eq "Completed") {
					# Get current status message from the registry
					$RunningConfigurationValues = Get-ItemProperty -Path $global:RegPath
					$CurrentOEM = ($RunningConfigurationValues).CurrentOEM
					$CurrentModel = ($RunningConfigurationValues).CurrentModel
					$CurrentOS = ($RunningConfigurationValues).OS
					$CurrentArchitecture = ($RunningConfigurationValues).Architecture
					$CurrentModelBaseboards = ($RunningConfigurationValues).CurrentBaseboards
					$PackagePath = ($RunningConfigurationValues).PackageStoragePath
					$DriverPackage = ($RunningConfigurationValues).PackagedDriverPath
					$SiteServer = ($RunningConfigurationValues).SiteServer
					$global:Sitecode = ($RunningConfigurationValues).SiteCode
					$PackageVersion = ($RunningConfigurationValues).PackageVersion
					$PackagedDriverPath = ($RunningConfigurationValues).PackagedDriverPath
					
					# Final registry update with download progress
					$DownloadedFileSize = (Get-Item -Path $DownloadDestination).Length
					Set-DATRegistryValue -Name "BytesTransferred" -Value "$DownloadedFileSize" -Type String
				}
				
				#New-HPDriverPack -Platform $SystemSKU -Os $TargetWindowsBuild -OSVer $WindowsVersion -Format wim -Path $DownloadDestination -TempDownloadPath $TempDirectory -RemoveOlder -InformationVariable SoftPaqInfo -ErrorVariable SoftPaqError
				Write-DATLogEntry -Value "- DriverPackage: OEM download process completed successfully" -Severity 1 -UpdateUI
				Set-DATRegistryValue -Name "RunningMode" -Value "Extract Ready" -Type String
				
			} catch [System.Exception] {
				Set-DATRegistryValue -Name "ErrorMessage" -Type String -Value "[Driver Package Error] - Issues occured while attempting create driver package. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Verbose
				Write-DATLogEntry -Value "[Driver Package Error] - Issues occured while attempting create driver package. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3 -UpdateUI
			}
		}
	}
}


# endregion Functions