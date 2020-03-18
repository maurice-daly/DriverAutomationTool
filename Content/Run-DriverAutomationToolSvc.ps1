<#
.SYNOPSIS
    SCConfigMgr Driver Automation Tool Silent Script

.DESCRIPTION
    This script is designed to work in conjunction with the Driver Automation Tool to automate the silent
	downloading and importing of driver and bios packages in ConfigMgr and MDT.
	The Driver Automation Tool will generate an XML which can then be used with this script to run silently.

.NOTES
    FileName:    Run-DownloadAutomationToolSvc.ps1
    Authors:     Maurice Daly
    Contact:     @modaly_it
    Created:     2017-08-04
    Updated:     2017-08-25
    
    Version history:
    1.0.0 - (2017-08-04) Script created (Maurice Daly)
	1.0.1 - (2017-08-25) Microsoft surface related updates (Maurice Daly)
#>

$ErrorActionPreference = 'Continue'
$WarningPreference = 'Continue'

# // =================== GLOBAL VARIABLES ====================== //

# Script Build Numbers
$ScriptRelease = "1.0.0"
$NewRelease = (Invoke-WebRequest -Uri "http://www.scconfigmgr.com/wp-content/uploads/tools/DriverAutomationToolSVCRev.txt" -UseBasicParsing).Content
$ReleaseNotesURL = "http://www.scconfigmgr.com/wp-content/uploads/tools/DriverAutomationToolSVCNotes.txt"

# Windows Version Hash Table
$WindowsBuildHashTable = @{`
	[int]1703 = "10.0.15063.0";`
	[int]1607 = "10.0.14393.0";`
	
};

# // =================== DELL VARIABLES ================ //

# Define Dell Download Sources
$DellDownloadList = "http://downloads.dell.com/published/Pages/index.html"
$DellDownloadBase = "http://downloads.dell.com"
$DellDriverListURL = "http://en.community.dell.com/techcenter/enterprise-client/w/wiki/2065.dell-command-deploy-driver-packs-for-enterprise-client-os-deployment"
$DellBaseURL = "http://en.community.dell.com"
$Dell64BIOSUtil = "http://en.community.dell.com/techcenter/enterprise-client/w/wiki/12237.64-bit-bios-installation-utility"

# Define Dell Download Sources
$DellXMLCabinetSource = "http://downloads.dell.com/catalog/DriverPackCatalog.cab"
$DellCatalogSource = "http://downloads.dell.com/catalog/CatalogPC.cab"

# Define Dell Cabinet/XL Names and Paths
$DellCabFile = [string]($DellXMLCabinetSource | Split-Path -Leaf)
$DellCatalogFile = [string]($DellCatalogSource | Split-Path -Leaf)
$DellXMLFile = $DellCabFile.Trim(".cab")
$DellXMLFile = $DellXMLFile + ".xml"
$DellCatalogXMLFile = $DellCatalogFile.Trim(".cab") + ".xml"

# Define Dell Global Variables
$global:DellCatalogXML = $null
$global:DellModelXML = $null
$global:DellModelCabFiles = $null

# // =================== HP VARIABLES ================ //

# Define HP Download Sources
$HPXMLCabinetSource = "http://ftp.hp.com/pub/caps-softpaq/cmit/HPClientDriverPackCatalog.cab"
$HPSoftPaqSource = "http://ftp.hp.com/pub/softpaq/"

# Define HP Cabinet/XL Names and Paths
$HPCabFile = [string]($HPXMLCabinetSource | Split-Path -Leaf)
$HPXMLFile = $HPCabFile.Trim(".cab")
$HPXMLFile = $HPXMLFile + ".xml"

# Define HP Global Variables
$global:HPModelSoftPaqs = $null
$global:HPModelXML = $null

# // =================== LENOVO VARIABLES ================ //

# Define Lenovo Download Sources
$LenovoXMLSource = "https://download.lenovo.com/cdrt/td/catalog.xml"

# Define Lenovo Cabinet/XL Names and Paths
$LenovoXMLFile = [string]($LenovoXMLSource | Split-Path -Leaf)
$LenovoBiosBase = "https://download.lenovo.com/catalog//"

# Define Lenovo Global Variables
$global:LenovoModelDrivers = $null
$global:LenovoModelXML = $null
$global:LenovoModelType = $null
$global:LenovoModelTypeList = $null


# // =================== ACER VARIABLES ================ //

# Define Acer Download Sources
$AcerSCCMSource = "http://www.acer.com/sccm/"

# // =================== MICROSOFT VARIABLES ================ //

# Define Microsoft Download Sources
$MicrosoftXMLSource = "http://www.scconfigmgr.com/wp-content/uploads/xml/DownloadLinks.xml"

# // =================== COMMON VARIABLES ================ //

# ArrayList to store models in
$DellProducts = New-Object -TypeName System.Collections.ArrayList
$DellKnownProducts = New-Object -TypeName System.Collections.ArrayList
$HPProducts = New-Object -TypeName System.Collections.ArrayList
$LenovoProducts = New-Object -TypeName System.Collections.ArrayList
$LenovoKnownProducts = New-Object -TypeName System.Collections.ArrayList
$AcerProducts = New-Object -TypeName System.Collections.ArrayList
$MicrosoftProducts = New-Object -TypeName System.Collections.ArrayList

# MDT PS Commandlets
$MDTPSCommandlets = "C:\Program Files\Microsoft Deployment Toolkit\bin\MicrosoftDeploymentToolkit.psd1"

# Proxy Validation Initial State
$ProxyValidated = $false

$global:DistributionPoints = New-Object -TypeName System.Collections.ArrayList
$global:DistributionPointGroups = New-Object -TypeName System.Collections.ArrayList
$global:ImportModels = New-Object -TypeName System.Collections.ArrayList

# // =================== LOAD FUNCTIONS ================ //

function Get-ScriptDirectory
{
	[OutputType([string])]
	param ()
	if ($null -ne $hostinvocation)
	{
		Split-Path $hostinvocation.MyCommand.path
	}
	else
	{
		Split-Path $script:MyInvocation.MyCommand.Path
	}
}

# Set Temp & Log Location
[string]$global:TempDirectory = (Get-ScriptDirectory) + "\Temp"
[string]$global:LogDirectory = (Get-ScriptDirectory) + "\Logs"
[string]$global:SettingsDirectory = (Get-ScriptDirectory) + "\Settings"

# Create Temp Folder 
if ((Test-Path -Path $global:TempDirectory) -eq $false)
{
	New-Item -Path $global:TempDirectory -ItemType Dir
}

# Create Logs Folder 
if ((Test-Path -Path $global:LogDirectory) -eq $false)
{
	New-Item -Path $global:LogDirectory -ItemType Dir
}

# Create Settings Folder 
if ((Test-Path -Path $global:SettingsDirectory) -eq $false)
{
	New-Item -Path $global:SettingsDirectory -ItemType Dir
}

# Logging Function
function global:Write-CMLogEntry
{
	param (
		[parameter(Mandatory = $true, HelpMessage = "Value added to the log file.")]
		[ValidateNotNullOrEmpty()]
		[string]$Value,
		[parameter(Mandatory = $true, HelpMessage = "Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
		[ValidateNotNullOrEmpty()]
		[ValidateSet("1", "2", "3")]
		[string]$Severity,
		[parameter(Mandatory = $false, HelpMessage = "Name of the log file that the entry will written to.")]
		[ValidateNotNullOrEmpty()]
		[string]$FileName = "DriverAutomationTool-Silent.log"
		
	)
	# Determine log file location
	$LogFilePath = Join-Path -Path $global:LogDirectory -ChildPath $FileName
	
	# Construct time stamp for log entry
	$Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
	
	# Construct date for log entry
	$Date = (Get-Date -Format "MM-dd-yyyy")
	
	# Construct context for log entry
	$Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
	
	# Construct final log entry
	$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""DriverAutomationTool"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
	
	# Add value to log file
	try
	{
		Add-Content -Value $LogText -LiteralPath $LogFilePath -ErrorAction Stop
	}
	catch [System.Exception] {
		Write-Warning -Message "Unable to append log entry to DriverAutomationTool.log file. Error message: $($_.Exception.Message)"
	}
}


function Get-VendorSources
{
	param (
		[string]$global:SiteServer,
		[string]$global:SiteCode
	)
	Write-CMLogEntry -Value "======== Querying Model List(s) ========" -Severity 1
	
	# Check for Proxy use and set variables
	if ($ProxyValidated -eq $false)
	{
		if (($UseProxyServerCheckbox.Checked -eq $true) -and ($ProxyValidated -eq $false))
		{
			$ProxyUser = [string]$ProxyUser
			$ProxyPswd = ConvertTo-SecureString $ProxyPswd -AsPlainText -Force
			$GlobalProxyServer = [string]$GlobalProxyServer
			$ProxyCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ProxyUser, $ProxyPswd
			$ProxyCheck = Invoke-WebRequest -Uri $HPXMLCabinetSource -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials
			
			# Try credential method if pass through fails
			if ($ProxyCheck -eq $null)
			{
				$ProxyCheck = Invoke-WebRequest -Uri $HPXMLCabinetSource -Proxy $GlobalProxyServer -ProxyCredential $ProxyCred
			}
			
			if ($ProxyCheck.StatusDescription -eq "OK")
			{
				Write-CMLogEntry -Value "======== Validating Proxy ========" -Severity 1
				Write-CMLogEntry -Value "PROXY: Connection to HP Cab site validated via proxy $GlobalProxyServer" -Severity 1
				$ProxyError = $false
			}
			else
			{
				Write-CMLogEntry -Value "======== Validating Proxy ========" -Severity 3
				Write-CMLogEntry -Value "Error: Please Check Proxy Server Details Are Valid" -Severity 3
				$ProxyError = $true
			}
		}
	}
	
	if ($ProxyError -ne $true)
	{
		
		if ($global:HP -eq $true)
		{
			$HPProducts.Clear()
			
			if ((Test-Path -Path $global:TempDirectory\$HPCabFile) -eq $false)
			{
				Write-CMLogEntry -Value "======== Downloading HP Product List ========" -Severity 1
				# Download HP Model Cabinet File
				$FileName = Get-URLFileName -URI $HPXMLCabinetSource
				Write-CMLogEntry -Value "Info: Downloading HP Driver Pack Cabinet File from $HPXMLCabinetSource" -Severity 1
				
				if ($global:UseProxyServer -eq $true)
				{
					Invoke-WebRequest -Uri $HPXMLCabinetSource -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials -OutFile (Join-Path $global:TempDirectory $FileName) -TimeoutSec 120
				}
				else
				{
					Invoke-WebRequest -Uri $HPXMLCabinetSource -OutFile (Join-Path $global:TempDirectory $FileName) -TimeoutSec 120
				}
				
				# Expand Cabinet File
				Write-CMLogEntry -Value "Info: Expanding HP Driver Pack Cabinet File: $HPXMLFile" -Severity 1
				Expand "$global:TempDirectory\$HPCabFile" -F:* "$global:TempDirectory\$HPXMLFile"
			}
			
			# Read XML File
			if ($global:HPModelSoftPaqs -eq $null)
			{
				Write-CMLogEntry -Value "Info: Reading Driver Pack XML File - $global:TempDirectory\$HPXMLFile" -Severity 1
				[xml]$global:HPModelXML = Get-Content -Path $global:TempDirectory\$HPXMLFile
				# Set XML Object
				$global:HPModelXML.GetType().FullName > $null
				$global:HPModelSoftPaqs = $HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
			}
		}
		
		if ($global:Dell -eq $true)
		{
			$DellProducts.Clear()
			
			if ((Test-Path -Path $global:TempDirectory\$DellCabFile) -eq $false)
			{
				Write-CMLogEntry -Value "Info: Downloading Dell Product List" -Severity 1
				Write-CMLogEntry -Value "Info: Downloading Dell Driver Pack Cabinet File from $DellXMLCabinetSource" -Severity 1
				# Download Dell Model Cabinet File
				$FileName = Get-URLFileName -URI $DellXMLCabinetSource
				if ($global:UseProxyServer -eq $true)
				{
					Invoke-WebRequest -Uri $DellXMLCabinetSource -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials -OutFile (Join-Path $global:TempDirectory $FileName) -TimeoutSec 120
				}
				else
				{
					Invoke-WebRequest -Uri $DellXMLCabinetSource -OutFile (Join-Path $global:TempDirectory $FileName) -TimeoutSec 120
				}
				
				# Expand Cabinet File
				Write-CMLogEntry -Value "Info: Expanding Dell Driver Pack Cabinet File: $DellXMLFile" -Severity 1
				Expand "$global:TempDirectory\$DellCabFile" -F:* "$global:TempDirectory\$DellXMLFile"
			}
			
			if ($global:DellModelXML -eq $null)
			{
				# Read XML File
				Write-CMLogEntry -Value "Info: Reading Driver Pack XML File - $global:TempDirectory\$DellXMLFile" -Severity 1
				[xml]$global:DellModelXML = (Get-Content -Path $global:TempDirectory\$DellXMLFile)
				# Set XML Object
				$global:DellModelXML.GetType().FullName > $null
			}
			$global:DellModelCabFiles = $global:DellModelXML.driverpackmanifest.driverpackage
		}
		
		if ($global:Lenovo -eq $true)
		{
			$LenovoProducts.Clear()
			if ($global:LenovoModelDrivers -eq $null)
			{
				if ($ProxyValidated -eq $true)
				{
					# Try both credential and default methods
					[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials -TimeoutSec 120
					if ($global:LenovoModelXML -eq $null)
					{
						[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource -Proxy $GlobalProxyServer -ProxyCredential $ProxyCred -TimeoutSec 120
					}
				}
				else
				{
					[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource -TimeoutSec 120
				}
				
				# Read Web Site
				Write-CMLogEntry -Value "Info: Reading Driver Pack URL - $LenovoXMLSource" -Severity 1
				
				# Set XML Object
				$global:LenovoModelXML.GetType().FullName > $null
				$global:LenovoModelDrivers = $global:LenovoModelXML.Products > $null
			}
		}
		
		if ($global:Acer -eq $true)
		{
			$AcerProducts.Clear()
			if ($ProxyValidated -eq $true)
			{
				# Try both credential and default methods
				$AcerModelList = Invoke-WebRequest -Uri $AcerSCCMSource -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials -TimeoutSec 120
				if ($AcerModelList -eq $null)
				{
					$AcerModelList = Invoke-WebRequest -Uri $AcerSCCMSource -Proxy $GlobalProxyServer -ProxyCredential $ProxyCred -TimeoutSec 120
				}
			}
			else
			{
				$AcerModelList = Invoke-WebRequest -Uri $AcerSCCMSource -TimeoutSec 120
			}
		}
				
		if ($global:Microsoft -eq $true)
		{
			$MicrosoftProducts.Clear()
			if ($ProxyValidated -eq $true)
			{
				# Try both credential and default methods
				[xml]$MicrosoftModelList = Invoke-WebRequest -Uri $MicrosoftXMLSource -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials -TimeoutSec 120
				if ($MicrosoftModelList -eq $null)
				{
					[xml]$MicrosoftModelList = Invoke-WebRequest -Uri $MicrosoftXMLSource -Proxy $GlobalProxyServer -ProxyCredential $ProxyCred -TimeoutSec 120
				}
			}
			else
			{
				[xml]$MicrosoftModelList = Invoke-WebRequest -Uri $MicrosoftXMLSource -TimeoutSec 120
			}
		}
	}
}

function FindLenovoDriver
{
	
<#
 # This powershell file will extract the link for the specified driver pack or application
 # param $URI The string version of the URL
 # param $64bit A boolean to determine what version to pick if there are multiple
 # param $global:OS A string containing 7, 8, or 10 depending on the os we are deploying 
 #           i.e. 7, Win7, Windows 7 etc are all valid os strings
 #>
	param (
		[parameter(Mandatory = $true, HelpMessage = "Provide the URL to parse.")]
		[ValidateNotNullOrEmpty()]
		[string]$URI,
		[parameter(Mandatory = $true, HelpMessage = "Specify the operating system.")]
		[ValidateNotNullOrEmpty()]
		[string]$OS,
		[string]$Architecture,
		[parameter(Mandatory = $false, HelpMessage = "Proxy server settings.")]
		[ValidateNotNullOrEmpty()]
		$ProxyServer,
		[parameter(Mandatory = $false, HelpMessage = "Proxy server credentials")]
		[ValidateNotNullOrEmpty()]
		$ProxyCred
	)
	
	#Case for direct link to a zip file
	if ($URI.EndsWith(".zip"))
	{
		return $URI
	}
	
	$err = @()
	
	#Get the content of the website
	if ($ProxyCred -gt $null)
	{
		$html = Invoke-WebRequest –Uri $URI -Proxy $ProxyServer -ProxyUseDefaultCredentials -TimeoutSec 120
		# Fall back to using specified credentials
		if ($html -eq $null)
		{
			$html = Invoke-WebRequest –Uri $URI -Proxy $GlobalProxyServer -ProxyCredential $ProxyCred -TimeoutSec 120
		}
	}
	else
	{
		$html = Invoke-WebRequest –Uri $URI -TimeoutSec 120
	}
	
	#Create an array to hold all the links to exe files
	$Links = @()
	$Links.Clear()
	
	#determine if the URL resolves to the old download location
	if ($URI -like "*olddownloads*")
	{
		#Quickly grab the links that end with exe
		$Links = (($html.Links | Where-Object { $_.href -like "*exe" }) | Where class -eq "downloadBtn").href
	}
	
	$Links = ((Select-string '(http[s]?)(:\/\/)([^\s,]+.exe)(?=")' -InputObject ($html).Rawcontent -AllMatches).Matches.Value)
	
	if ($Links.Count -eq 0)
	{
		return $null
	}
	
	# Switch OS architecture
	switch ($Architecture)
	{
		x64 { $Architecture = "64" }
		x86 { $Architecture = "86 " }
	}
	
	#if there are multiple links then narrow down to the proper arc and os (if needed)
	if ($Links.Count -gt 0)
	{
		#Second array of links to hold only the ones we want to target
		$MatchingLink = @()
		$MatchingLink.clear()
		foreach ($Link in $Links)
		{
			if ($Link -like "*w$($OS)$($Architecture)_*" -or $Link -like "*w$($OS)_$($Architecture)*")
			{
				$MatchingLink += $Link
			}
		}
	}
	return $MatchingLink
}

function Get-RedirectedUrl
{
	Param (
		[Parameter(Mandatory = $true)]
		[String]$URL
	)
	
	Write-CMLogEntry -Value "Info: Attempting Microsoft Link Download Discovery" -Severity 1
	
	$Request = [System.Net.WebRequest]::Create($URL)
	$Request.AllowAutoRedirect = $false
	$Request.Timeout = 3000
	$Response = $Request.GetResponse()
	
	if ($Response.ResponseUri)
	{
		$Response.GetResponseHeader("Location")
	}
	$Response.Close()
}

function Get-URLFileName ($URI)
{
	$RequestPage = [System.Net.HttpWebRequest]::Create($URI)
	$RequestPage.Method = "HEAD"
	$Response = $RequestPage.GetResponse()
	$FullURL = $Response.ResponseUri
	$FileName = [System.IO.Path]::GetFileName($FullURL.LocalPath);
	$Response.Close()
	
	return $FileName
}

function DiscoverDPOptions
{
	Write-CMLogEntry -Value "======== Querying ConfigMgr Distribution Options ========" -Severity 1
	Set-Location -Path ($global:SiteCode + ":")
	$global:DistributionPoints = (Get-CMDistributionPoint | Select-Object NetworkOsPath).NetworkOSPath
	$global:DistributionPointGroups = (Get-CMDistributionPointGroup | Select-Object Name).Name
	
	# Populate Distribution Point List Box
	if ($global:DistributionPoints -ne $null)
	{
		foreach ($DP in $global:DistributionPoints)
		{
			$DP = ($DP).TrimStart("\\")
			if ($DP -notin $DPListbox.Items)
			{
				$DPListBox.Items.Add($DP)
			}
		}
		Write-CMLogEntry -Value "Info: Found $($global:DistributionPoints.Count) Distribution Points" -Severity 1
	}
	
	# Populate Distribution Point Group List Box
	if ($global:DistributionPointGroups -ne $null)
	{
		foreach ($DPG in $global:DistributionPointGroups)
		{
			if ($DPG -notin $DPGListBox.Items)
			{
				$DPGListBox.Items.Add($DPG)
			}
		}
		Write-CMLogEntry -Value "Info: Found $($global:DistributionPointGroups.Count) Distribution Point Groups" -Severity 1
	}
	Set-Location -Path $global:TempDirectory
}

function DistributeContent
{
	param
	(
		[parameter(Mandatory = $true)]
		[string]$Product,
		[string]$PackageID
		
	)
	# Distribute Content - Selected Distribution Points
	if (($global:DistributionPoints).Count -gt 0)
	{
		foreach ($DP in $global:DistributionPoints)
		{
			if ($global:ImportInto -match "Standard")
			{
				Start-CMContentDistribution -PackageID $PackageID -DistributionPointName $DP
			}
			if ($global:ImportInto -match "Driver")
			{
				Start-CMContentDistribution -DriverPackageID $PackageID -DistributionPointName $DP
			}
		}
		Write-CMLogEntry -Value "$($Product): Distributing Package $PackageID to $(($DPListBox.SelectedItems).Count) Distribution Point(s)" -Severity 1
	}
	
	# Distribute Content - Selected Distribution Point Groups
	if (($DistributionPointGroups).Count -gt 0)
	{
		foreach ($DPG in $DistributionPointGroups)
		{
			if ($global:ImportInto -match "Standard")
			{
				Start-CMContentDistribution -PackageID $PackageID -DistributionPointGroupName $DPG
			}
			if ($global:ImportInto -match "Driver")
			{
				Start-CMContentDistribution -DriverPackageID $PackageID -DistributionPointGroupName $DPG
			}
		}
		Write-CMLogEntry -Value "$($Product): Distributing Package $PackageID to $(($DPGListBox.SelectedItems).Count) Distribution Point Group(s)" -Severity 1
	}
}

function ConnectSCCM
{
	# Set Site Server Value
	$global:SiteServer = $global:SiteServer
	
	if ((Test-WSMan -ComputerName $global:SiteServer).wsmid -ne $null)
	{
		#Clear-Host
		Write-CMLogEntry -Value "Info: Connected To Site Server: $global:SiteServer" -Severity 1
		Write-CMLogEntry -Value "======== Checking ConfigMgr Prerequisites ========" -Severity 1
		
		# Import SCCM PowerShell Module
		$ModuleName = (Get-Item $env:SMS_ADMIN_UI_PATH).parent.FullName + "\ConfigurationManager.psd1"
		if ($ModuleName -ne $null)
		{
			Write-CMLogEntry -Value "Info: Loading ConfigMgr PowerShell Module" -Severity 1
			Import-Module $ModuleName
			Write-CMLogEntry -Value "======== Connecting to ConfigMgr Server ========" -Severity 1
			Write-CMLogEntry -Value "Info: Querying Site Code From $global:SiteServer" -Severity 1
		}
		else
		{
			Write-CMLogEntry -Value "Error: ConfigMgr PowerShell Module Not Found" -Severity 3
		}
	}
	else
	{
		Write-CMLogEntry -Value "Error: ConfigMgr Server Specified Not Found - $($global:SiteServer)" -Severity 3
	}
}

function DellBiosFinder
{
	param (
		[string]$Model
	)
	
	if ((Test-Path -Path $global:TempDirectory\$DellCatalogXMLFile) -eq $false)
	{
		Write-CMLogEntry -Value "======== Downloading Dell Driver Catalog  ========" -Severity 1
		Write-CMLogEntry -Value "Info: Downloading Dell Driver Catalog Cabinet File from $DellCatalogSource" -Severity 1
		# Download Dell Model Cabinet File
		$FileName = Get-URLFileName -URI $DellCatalogSource
		if ($global:UseProxyServer -eq $true)
		{
			Invoke-WebRequest -Uri $DellCatalogSource -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials -OutFile (Join-Path $global:TempDirectory $FileName) -TimeoutSec 120
		}
		else
		{
			Invoke-WebRequest -Uri $DellCatalogSource -OutFile (Join-Path $global:TempDirectory $FileName) -TimeoutSec 120
		}
		
		# Expand Cabinet File
		Write-CMLogEntry -Value "Info: Expanding Dell Driver Pack Cabinet File: $DellCatalogFile" -Severity 1
		Expand "$global:TempDirectory\$DellCatalogFile" -F:* "$global:TempDirectory\$DellCatalogXMLFile" | Out-Null
		
	}
	
	if ($global:DellCatalogXML -eq $null)
	{
		# Read XML File
		Write-CMLogEntry -Value "Info: Reading Driver Pack XML File - $global:TempDirectory\$DellCatalogXMLFile" -Severity 1
		[xml]$global:DellCatalogXML = Get-Content -Path $global:TempDirectory\$DellCatalogXMLFile
		
		# Set XML Object
		$global:DellCatalogXML.GetType().FullName > $null
	}
	
	# Cater for multiple bios version matches and select the most recent
	$DellBIOSFile = $global:DellCatalogXML.Manifest.SoftwareComponent | Where-Object { ($_.name.display."#cdata-section" -match "BIOS") -and ($_.name.display."#cdata-section" -match "$model") } | Sort-Object ReleaseDate -Descending
	# Cater for multi model updates
	if ($DellBIOSFile -eq $null)
	{
		$global:DellCatalogXML.Manifest.SoftwareComponent | Where-Object { ($_.name.display."#cdata-section" -match "BIOS") -and ($_.name.display."#cdata-section" -like "*$(($model).Split(' ')[1])*") } | Sort-Object ReleaseDate -Descending
	}
	if (($DellBIOSFile -eq $null) -or (($DellBIOSFile).Count -gt 1))
	{
		# Attempt to find BIOS link		
		if ($Model -match "AIO")
		{
			$DellBIOSFile = $DellBIOSFile | Where-Object { $_.SupportedSystems.Brand.Model.Display.'#cdata-section' -match "AIO" } | Sort-Object ReleaseDate -Descending | Select -First 1
		}
		else
		{
			$DellBIOSFile = $DellBIOSFile | Where-Object { $_.SupportedSystems.Brand.Model.Display.'#cdata-section' -eq "$($Model.Split(' ')[1])" } | Sort-Object ReleaseDate -Descending | Select -First 1
		}
	}
	elseif ($DellBIOSFile -eq $null)
	{
		# Attempt to find BIOS link via Dell model number (V-Pro / Non-V-Pro Condition)
		$DellBIOSFile = $global:DellCatalogXML.Manifest.SoftwareComponent | Where-Object { ($_.name.display."#cdata-section" -match "BIOS") -and ($_.name.display."#cdata-section" -match "$($model.Split("-")[0])") } | Sort-Object ReleaseDate -Descending | Select -First 1
	}
	
	Write-CMLogEntry -Value "Info: Found BIOS URL $($DellBIOSFile.Path)" -Severity 1
	# Return BIOS file values
	Return $DellBIOSFile
	
}

function LenovoModelTypeFinder
{
	param (
		[parameter(Mandatory = $false, HelpMessage = "Enter Lenovo model to query")]
		[string]$Model,
		#[parameter(Mandatory = $false, HelpMessage = "Enter Operating System")]

		#[string]$OS,

		[parameter(Mandatory = $false, HelpMessage = "Enter Lenovo model type to query")]
		[string]$ModelType
	)
	
	if ($global:LenovoModelDrivers -eq $null)
	{
		if ($ProxyValidated -eq $true)
		{
			# Try both credential and default methods
			[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials -TimeoutSec 120
			if ($global:LenovoModelXML -eq $null)
			{
				[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource -Proxy $GlobalProxyServer -ProxyCredential $ProxyCred -TimeoutSec 120
			}
		}
		else
		{
			[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource -TimeoutSec 120
		}
		
		# Read Web Site
		Write-CMLogEntry -Value "Info: Reading Driver Pack URL - $LenovoXMLSource" -Severity 1
		
		# Set XML Object
		$global:LenovoModelXML.GetType().FullName > $null
		$global:LenovoModelDrivers = $global:LenovoModelXML.Products
	}
	
	if ($Model.Length -gt 0)
	{
		$global:LenovoModelType = ($global:LenovoModelDrivers.Product | Where-Object { $_.Queries.Version -match "$Model" }).Queries.Types | Select -ExpandProperty Type | Select -first 1
		$global:LenovoModelTypeList = ($global:LenovoModelDrivers.Product | Where-Object { $_.Queries.Version -match "$Model" }).Queries.Types | select -ExpandProperty Type | Get-Unique
	}
	
	if ($ModelType.Length -gt 0)
	{
		$global:LenovoModelType = (($global:LenovoModelDrivers.Product.Queries) | Where-Object { ($_.Types | Select -ExpandProperty Type) -match $ModelType }).Version | Select -first 1
	}
	
	Return $global:LenovoModelType
}

function LenovoBiosFinder
{
	param (
		[string]$Model,
		[string]$OS
	)
	
	# Windows 8.1 Driver Switch
	switch -Wildcard ($OS)
	{
		"8.1*" {
			$OS = "8"
		}
	}
	
	Set-Location -Path $global:TempDirectory
	# Download Lenovo Model Details XML
	if ($global:UseProxyServer -eq $true)
	{
		Invoke-WebRequest -Uri ($LenovoBiosBase + $LenovoModelType + "_Win$OS.xml") -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials -OutFile (Join-Path $global:TempDirectory "$($LenovoModelType)_Win$OS.xml") -TimeoutSec 120
	}
	else
	{
		Invoke-WebRequest -Uri ($LenovoBiosBase + $LenovoModelType + "_Win$OS.xml") -OutFile (Join-Path $global:TempDirectory "$($LenovoModelType)_Win$OS.xml") -TimeoutSec 120
	}
	Write-CMLogEntry -Value "Info: Attempting to download file from $($LenovoBiosBase + $LenovoModelType + "_Win$OS.xml") " -Severity 1
	$Path = (Join-Path $global:TempDirectory "$($LenovoModelType)_Win$OS.xml")
	$LenovoModelBIOSDownloads = ((Select-Xml -path $(Join-Path $global:TempDirectory "$($LenovoModelType)_Win$OS.xml") -XPath "/").Node.Packages.Package | Where-Object { $_.Category -match "BIOS" }) | Sort-Object Location -Descending | Select -First 1
	Return $LenovoModelBIOSDownloads
}

function Read-XMLSettings
{
	Write-CMLogEntry -Value "======== Reading Settings File ========" -Severity 1

	try
	{
		# // Read in settings XML		
		[xml]$global:DATSettingsXML = Get-Content -Path "$global:SettingsDirectory\DATSettings.xml"

		# Set XML Object
		$global:DATSettingsXML.GetType().FullName
		
		# ConfigMgr Site Settings
		Write-CMLogEntry -Value "Setting ConfigMgr Site Settings" -Severity 1
		$global:SiteCode = $Global:DATSettingsXML.Settings.SiteSettings.Site
		$global:SiteServer = $Global:DATSettingsXML.Settings.SiteSettings.Server
		
		# OS & Download Settings
		Write-CMLogEntry -Value "Setting OS & Download Selections" -Severity 1
		$global:OS = $Global:DATSettingsXML.Settings.DownloadSettings.OperatingSystem
		$global:ImportInto = $Global:DATSettingsXML.Settings.DownloadSettings.DeploymentPlatform
		$global:Architecture = $Global:DATSettingsXML.Settings.DownloadSettings.Architecture
		$global:DownloadType = $Global:DATSettingsXML.Settings.DownloadSettings.DownloadType
		
		# // Storage Locations
		Write-CMLogEntry -Value "Setting Storage Locations" -Severity 1
		$global:PackagePath = $Global:DATSettingsXML.Settings.StorageSettings.Package
		$global:RepositoryPath = $Global:DATSettingsXML.Settings.StorageSettings.Repository
		
		# // Manufacturer Selections
		Write-CMLogEntry -Value "Setting Manufacturer Selections" -Severity 1
		if ($Global:DATSettingsXML.Settings.Manufacturer.Acer -eq "True") { $global:Acer = $true }
		if ($Global:DATSettingsXML.Settings.Manufacturer.Dell -eq "True") { $global:Dell = $true }
		if ($Global:DATSettingsXML.Settings.Manufacturer.HP -eq "True") { $global:HP = $true }
		if ($Global:DATSettingsXML.Settings.Manufacturer.Lenovo -eq "True") { $global:Lenovo = $true }
		if ($Global:DATSettingsXML.Settings.Manufacturer.Microsoft -eq "True") { $global:Microsoft = $true }
		
		# // Model Selections
		Write-CMLogEntry -Value "Setting Previously Selected Model(s)" -Severity 1
		foreach ($Model in $Global:DATSettingsXML.Settings.Models.ModelSelected)
		{
			$global:ImportModels.Add($Model) > $null
		}
		
		# // Distribution Point Settings 	
		Write-CMLogEntry -Value "Setting Distribution Point(s) / Point Groups" -Severity 1
		# Select Distribution Points based on previously set index values
		foreach ($DP in $Global:DATSettingsXML.Settings.DistributionSettings.DistributionPointName)
		{
			$global:DistributionPoints.Add($DP) > $null
		}
		# Select Distribution Point Groups based on previously set index values
		foreach ($DPG in $Global:DATSettingsXML.Settings.DistributionSettings.DistributionPointGroupName)
		{
			$global:DistributionPointGroups.Add($DPG) > $null
		}
		if ($Global:DATSettingsXML.Settings.DistributionSettings.BinaryDifferentialReplication -eq "True") { $global:EnableBinaryDif = $true }
		
		# // Clean Up Options	
		Write-CMLogEntry -Value "Setting Clean Up Settings" -Severity 1
		if ($Global:DATSettingsXML.Settings.CleanUpOptions.CleanUnused -eq "True") { $global:CleanUnused = $true }
		if ($Global:DATSettingsXML.Settings.CleanUpOptions.RemoveLegacy -eq "True")
		{
			$global:RemoveLegacyDriver = $true
		}
		if ($Global:DATSettingsXML.Settings.CleanUpOptions.RemoveDriverSource -eq "True")
		{
			$RemoveDriverSource = $true
		}
		
		# // Proxy Server Settings
		if ($Global:DATSettingsXML.Settings.ProxySetting.UseProxy -eq "True")
		{
			$global:UseProxyServer -eq $true
			Write-CMLogEntry -Value "Setting Proxy Server Address" -Severity 1
			$global:ProxyServer = $Global:DATSettingsXML.Settings.ProxySetting.Proxy
		}
		Write-CMLogEntry -Value " " -Severity 1
	}
	catch
	{
		Write-CMLogEntry -Value "An error occured while attempting to apply settings from DATSettings XML: $($_.Exception.Message)" -Severity 2
	}
	
}

function InitiateDownloads
{
	
	Write-CMLogEntry -Value "Info: Importing Into Products: $global:ImportInto" -Severity 1
	Write-CMLogEntry -Value "Info: Download Type: $global:DownloadType" -Severity 1
	
	# Set Initial Validation State
	$ValidationErrors = 0
	
	# ============ Validation Selection Details and Prerequisites ==============
	
	# Validate Selected Models
	if (($global:ImportModels.Count) -lt "1")
	{
		Write-CMLogEntry -Value "Error: No Models Selected" -Severity 3
		$ValidationErrors++
	}
	
	# Validate Repository Path For BIOS & Driver Downloads
	if ((Test-Path -Path $global:RepositoryPath) -eq $true)
	{
		Write-CMLogEntry -Value "Pre-Check: Respository Path Set To $global:RepositoryPath" -Severity 1
	}
	else
	{
		Write-CMLogEntry -Value "Error: UNC Repository Path Specified Could Not Be Found $($global:RepositoryPath)" -Severity 3
		$ValidationErrors++
	}
	
	# Validate Package Path For ConfigMgr Driver Imports
	if (($global:ImportInto -like "ConfigMgr*") -or ($global:ImportInto -like "Both*"))
	{
		if ($global:DownloadType -ne "BIOS")
		{
			if ((Test-Path -path $global:PackagePath) -eq $false)
			{
				Write-CMLogEntry -Value "Error: UNC Package Path Specified Could Not Be Found $($PackagePath)" -Severity 3
				$ValidationErrors++
			}
		}
	}
	
	# Validate OS Selection
	if ($global:OS -ne $null)
	{
		$WindowsVersion = ($global:OS).Split(" ")[1]
	}
	else
	{
		Write-CMLogEntry -Value "Error: Operating System Not Specified" -Severity 3
		$ValidationErrors++
	}
	
	# Validate OS Architecture Selection
	$Architecture = "x" + ($global:Architecture).Trim(" bit")
	
	# Set Proxy Variables
	if ($UseProxyServer -eq $true)
	{
		$ProxyUser = [string]$ProxyUser
		$ProxyPswd = ConvertTo-SecureString $([string]$ProxyPswd) -AsPlainText -Force
		$ProxyCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ProxyUser, $ProxyPswd
		Write-CMLogEntry -Value "Info: Downloading through proxy $GlobalProxyServer" -Severity 1
		$ProxyValidated = $true
	}
	
	# Driver Download ScriptBlock
	$DriverDownloadJob = {
		Param ([string]$DriverRepositoryRoot,
			[string]$Model,
			[string]$DriverCab,
			[string]$DriverDownloadURL,
			$GlobalProxyServer,
			$ProxyCred)
		
		# Start Driver Download	
		
		function Get-URLFileName ($URI)
		{
			$RequestPage = [System.Net.HttpWebRequest]::Create($URI)
			$RequestPage.Method = "HEAD"
			$Response = $RequestPage.GetResponse()
			$FullURL = $Response.ResponseUri
			$FileName = [System.IO.Path]::GetFileName($FullURL.LocalPath);
			$Response.Close()
			
			return $FileName
		}
		
		$DriverCab = Get-URLFileName -URI $DriverDownloadURL
		$DriverModelPath = Join-Path $DriverRepositoryRoot $Model
		$DriverCabPath = Join-Path $DriverModelPath "Driver Cab"
		
		if ($global:UseProxyServer -eq $true)
		{
			Invoke-WebRequest -Uri $DriverDownloadURL -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials -OutFile (Join-Path $DriverCabPath $DriverCab) -TimeoutSec 120
		}
		else
		{
			Invoke-WebRequest -Uri $DriverDownloadURL -OutFile (Join-Path $DriverCabPath $DriverCab) -TimeoutSec 120
		}
	}
	
	# Move HP Driver Function
	$MoveDrivers = {
		Param ($ExtractSource,
			$ExtractDest)
		
		Get-ChildItem -Path "$ExtractSource" | Move-Item -Destination "$ExtractDest" -Verbose
	}
	
	# Copy Drivers To Package Location (Standard)
	$PackageDrivers = {
		Param ($Make,
			$DriverExtractDest,
			$Architecture,
			$DriverPackageDest)
		
		if ($Make -eq "Dell")
		{
			Copy-Item -Path $(Get-ChildItem -Path "$DriverExtractDest" -Recurse -Directory | Where-Object { $_.Name -eq "$Architecture" } | Select-Object -First 1).FullName -Destination "$DriverPackageDest" -Container -Recurse
			Write-CMLogEntry -Value "$($Product): Copying Drivers from $DriverExtractDest to $DriverPackageDest" -Severity 1
		}
		else
		{
			Copy-Item -Path "$DriverExtractDest" -Destination "$DriverPackageDest" -Container -Recurse
			Write-CMLogEntry -Value "$($Product): Copying Drivers from $DriverExtractDest to $DriverPackageDest" -Severity 1
		}
	}
	
	# Validate MDT PowerShell Commandlets / Install 
	if ((($global:ImportInto) -like ("MDT" -or "Both*")) -and ($ValidationErrors -eq 0))
	{
		# Validate MDT PS Commandlets
		if ((Test-Path -Path $MDTPSCommandlets) -eq $true)
		{
			# Import MDT Module
			Write-CMLogEntry -Value "$($Product): Importing: MDT PowerShell Commandlets" -Severity 1
			Import-Module $MDTPSCommandlets
		}
		else
		{
			Write-CMLogEntry -Value "Error: MDT PowerShell Commandlets file not found at $MDTPSCommandlets" -Severity 1
			$ValidationErrors++
		}
	}
	
	if ($ValidationErrors -eq 0)
	{
		Write-CMLogEntry -Value "======== Starting Download Processes ========" -Severity 1
		Write-CMLogEntry -Value "Info: Models selected: $($global:ImportModels)" -Severity 1
		Write-CMLogEntry -Value "Info: Operating System specified: Windows $($WindowsVersion)" -Severity 1
		Write-CMLogEntry -Value "Info: Operating System architecture specified: $($Architecture)" -Severity 1
		Write-CMLogEntry -Value "Info: Site Code specified: $($global:SiteCode)" -Severity 1
		Write-CMLogEntry -Value "Info: Respository Path specified: $($global:RepositoryPath)" -Severity 1
		Write-CMLogEntry -Value "Info: Package Path specified: $($global:PackagePath)" -Severity 1
		
		# Operating System Version
		$OperatingSystem = ("Windows " + $($WindowsVersion))
		
		$TotalModelCount = $global:ImportModels.Count
		$RemainingModels = $TotalModelCount
		
		foreach ($Model in $global:ImportModels)
		{
			Write-CMLogEntry -Value "======== Processing $Model Downloads ========" -Severity 1
			# Vendor Make
			$Make = $($Model).split(" ")[0]
			$Model = $($Model).TrimStart("$Make")
			$Model = $Model.Trim()
			
			# Lookup OS Build Number 
			if ($global:OS -like "Windows 10 1*")
			{
				Write-CMLogEntry -Value "Info: Windows 10 Build Lookup Required" -Severity 1
				# Extract Windows 10 Version Number
				$global:OSVersion = [string]($global:OS).Split(' ')[2]
				# Get Windows Build Number From Version Hash Table
				$global:OSBuild = $WindowsBuildHashTable.Item([int]$global:OSVersion)
				Write-CMLogEntry -Value "Info: Windows 10 Build $global:OSBuild Identified For Driver Match" -Severity 1
			}
			
			Write-CMLogEntry -Value "Info: Starting Download,Extract And Import Processes For $Make Model: $($Model)" -Severity 1
			
			# =================== DEFINE VARIABLES =====================
			
			# Directory used for driver and BIOS downloads
			$DriverRepositoryRoot = ($global:RepositoryPath.Trimend("\") + "\$Make\")
			
			# Directory used by ConfigMgr for driver packages
			if (($global:ImportInto -like "*ConfigMgr*") -and ($global:DownloadType -ne "BIOS")) { $DriverPackageRoot = ($global:PackagePath.Trimend("\") + "\$Make\") }
			
			# =================== VENDOR SPECIFIC UPDATES ====================
			
			if ($Make -eq "Dell")
			{
				Write-CMLogEntry -Value "Info: Setting Dell Variables" -Severity 1
				if ($global:DellModelCabFiles -eq $null)
				{
					[xml]$DellModelXML = Get-Content -Path $global:TempDirectory\$DellXMLFile
					# Set XML Object
					$DellModelXML.GetType().FullName > $null
					$global:DellModelCabFiles = $DellModelXML.driverpackmanifest.driverpackage
				}
				$ModelURL = $DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object { ((($_.SupportedOperatingSystems).OperatingSystem).osCode -like "*$WindowsVersion*") -and ($_.SupportedSystems.Brand.Model.Name -like "*$Model*") }).delta
				$ModelURL = $ModelURL.Replace("\", "/")
				$DriverDownload = $DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object { ((($_.SupportedOperatingSystems).OperatingSystem).osCode -like "*$WindowsVersion*") -and ($_.SupportedSystems.Brand.Model.Name -like "*$Model") }).path
				$DriverCab = (($global:DellModelCabFiles | Where-Object { ((($_.SupportedOperatingSystems).OperatingSystem).osCode -like "*$WindowsVersion*") -and ($_.SupportedSystems.Brand.Model.Name -like "*$Model") }).path).Split("/") | select -Last 1
				$DriverRevision = (($DriverCab).Split("-")[2]).Trim(".cab")
			}
			if ($Make -eq "HP")
			{
				Write-CMLogEntry -Value "Info: Setting HP Variables" -Severity 1
				if ($global:HPModelSoftPaqs -eq $null)
				{
					[xml]$global:HPModelXML = Get-Content -Path $global:TempDirectory\$HPXMLFile
					# Set XML Object
					$global:HPModelXML.GetType().FullName > $null
					$global:HPModelSoftPaqs = $global:HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
				}
				
				if ($global:OS -like "Windows 10 1*")
				{
					$HPSoftPaqSummary = $global:HPModelSoftPaqs | Where-Object { ($_.SystemName -like "*$Model*") -and ($_.OSName -like "Windows*$(($global:OS).Split(' ')[1])*$(($global:Architecture).Trim(' bit'))*$((($global:OS).Split(' ')[2]).Trim())*") } | Sort-Object -Descending | select -First 1
				}
				else
				{
					$HPSoftPaqSummary = $global:HPModelSoftPaqs | Where-Object { ($_.SystemName -like "*$Model*") -and ($_.OSName -like "Windows*$(($global:OS).Split(' ')[1])*$(($global:Architecture).Trim(' bit'))*") } | Sort-Object -Descending | select -First 1
				}
				$HPSoftPaq = $HPSoftPaqSummary.SoftPaqID
				$HPSoftPaqDetails = $global:HPModelXML.newdataset.hpclientdriverpackcatalog.softpaqlist.softpaq | Where-Object { $_.ID -eq "$HPSoftPaq" }
				$ModelURL = $HPSoftPaqDetails.URL
				# Replace FTP for HTTP for Bits Transfer Job
				$DriverDownload = "http:" + ($HPSoftPaqDetails.URL).TrimStart("ftp:")
				$DriverCab = $ModelURL | Split-Path -Leaf
				$DriverRevision = "$($HPSoftPaqDetails.Version)"
			}
			if ($Make -eq "Lenovo")
			{
				Write-CMLogEntry -Value "Info: Setting Lenovo Variables" -Severity 1
				LenovoModelTypeFinder -Model $Model
				Write-CMLogEntry -Value "Info: $Make $Model matching model type: $global:LenovoModelType" -Severity 1
				
				if ($global:LenovoModelDrivers -ne $null)
				{
					[xml]$global:LenovoModelXML = (New-Object System.Net.WebClient).DownloadString("$LenovoXMLSource")
					# Set XML Object
					$global:LenovoModelXML.GetType().FullName > $null
					$global:LenovoModelDrivers = $global:LenovoModelXML.Products
					$LenovoDriver = (($global:LenovoModelDrivers.Product | Where-Object { $_.Queries.Version -eq $Model }).driverPack | Where-Object { $_.id -eq "SCCM" })."#text"
				}
				if ($WindowsVersion -ne "7")
				{
					Write-CMLogEntry -Value "Info: Looking Up Lenovo $Model URL For Windows Version win$(($WindowsVersion).Trim('.'))" -Severity 1
					$ModelURL = (($global:LenovoModelDrivers.Product | Where-Object { ($_.Queries.Version -eq "$Model") -and ($_.os -eq "win$(($WindowsVersion -replace '[.]', ''))") }).driverPack | Where-Object { $_.id -eq "SCCM" })."#text" | Select -First 1
				}
				else
				{
					Write-CMLogEntry -Value "Info: Looking Up Lenovo $Model URL For Windows Version win$(($WindowsVersion).Trim('.'))" -Severity 1
					$ModelURL = (($global:LenovoModelDrivers.Product | Where-Object { ($_.Queries.Version -eq "$Model") -and ($_.os -eq "win$WindowsVersion$(($Architecture).Split(' ')[0])") }).driverPack | Where-Object { $_.id -eq "SCCM" })."#text" | Select -First 1
				}
				
				if ($global:DownloadType -ne "BIOS")
				{
					Write-CMLogEntry -Value "Info: Searching for Lenovo $Model exe file on $ModelURL" -Severity 1
					Write-CMLogEntry -Value "Info: Passing through Windows version as $WindowsVersion" -Severity 1
					Write-CMLogEntry -Value "Info: Passing through Windows Architecture as $Architecture" -Severity 1
					
					if ($GlobalProxyServer -ne $null)
					{
						$DriverDownload = FindLenovoDriver -URI $ModelURL -os $WindowsVersion -Architecture $Architecture -ProxyServer $GlobalProxyServer -ProxyCred $ProxyCred
					}
					else
					{
						$DriverDownload = FindLenovoDriver -URI $ModelURL -os $WindowsVersion -Architecture $Architecture
					}
					
					If ($DriverDownload -ne $null)
					{
						$DriverCab = $DriverDownload | Split-Path -Leaf
						$DriverRevision = ($DriverCab.Split("_") | Select -Last 1).Trim(".exe")
					}
					else
					{
						Write-CMLogEntry -Value "Error: Unable to find driver for $Make $Model" -Severity 1
					}
				}
			}
			if ($Make -eq "Acer")
			{
				Write-CMLogEntry -Value "Info: Setting Acer Variables" -Severity 1
				$AcerModelDrivers = (Invoke-WebRequest -Uri $AcerSCCMSource).Links
				$AcerDriver = $AcerModelDrivers | Where-Object { $_.outerText -match $Model }
				$ModelURL = (($AcerDriver | Where-Object { $_.OuterText -like "*$($WindowsVersion)*$(($Architecture).Split(' ')[0])*" }).href)
				$DriverDownload = "http:" + $ModelURL
				$DriverCab = $DriverDownload | Split-Path -Leaf
				$DriverRevision = "NA"
			}
			if ($Make -eq "Microsoft")
			{
				Write-CMLogEntry -Value "Info: Setting Microsoft Variables" -Severity 1
				[xml]$MicrosoftModelXML = (New-Object System.Net.WebClient).DownloadString("$MicrosoftXMLSource")
				# Set XML Object
				$MicrosoftModelXML.GetType().FullName > $null
				$MicrosoftModelDrivers = $MicrosoftModelXML.Drivers
				$ModelURL = ((($MicrosoftModelDrivers.Model | Where-Object { ($_.name -match "$Model") }).OSSupport) | Where-Object { $_.Name -eq "win$(($WindowsVersion).Trim("."))" }).DownloadURL
				$ModelWMI = (($MicrosoftModelDrivers.model | Where-Object { $_.name -eq "$Model" }).wmi).name
				$DriverDownload = Get-RedirectedUrl -URL "$ModelURL" -ErrorAction Continue -WarningAction Continue
				$DriverCab = $DriverDownload | Split-Path -Leaf
				$DriverRevision = ($DriverCab.Split("_") | Select -Last 2).Trim(".msi")[0]
			}
			
			if ($global:DownloadType -ne "BIOS")
			{
				# Driver variables & switches
				$DriverSourceCab = ($DriverRepositoryRoot + $Model + "\Driver Cab\" + $DriverCab)
				$DriverPackageDir = ($DriverCab).Substring(0, $DriverCab.length - 4)
				$DriverCabDest = $DriverPackageRoot + $DriverPackageDir
			}
			
			# Cater for Dell driver packages (both x86 and x64 drivers contained within a single package)
			if ($Make -eq "Dell")
			{
				$DriverExtractDest = ("$DriverRepositoryRoot" + $Model + "\" + "Windows$WindowsVersion-$DriverRevision")
				Write-CMLogEntry -Value "Info: Driver Extract Location Set - $DriverExtractDest" -Severity 1
				$DriverPackageDest = ("$DriverPackageRoot" + "$Model" + "-" + "Windows$WindowsVersion-$Architecture-$DriverRevision")
				Write-CMLogEntry -Value "Info: Driver Package Location Set - $DriverPackageDest" -Severity 1
				
			}
			else
			{
				If ($global:OSBuild -eq $null)
				{
					$DriverExtractDest = ("$DriverRepositoryRoot" + $Model + "\" + "Windows$WindowsVersion-$Architecture-$DriverRevision")
					Write-CMLogEntry -Value "Info: Driver Extract Location Set - $DriverExtractDest" -Severity 1
					$DriverPackageDest = ("$DriverPackageRoot" + "$Model" + "\" + "Windows$WindowsVersion-$Architecture-$DriverRevision")
					Write-CMLogEntry -Value "Info: Driver Package Location Set - $DriverPackageDest" -Severity 1
				}
				else
				{
					$DriverExtractDest = ("$DriverRepositoryRoot" + $Model + "\" + "Windows$WindowsVersion-$global:OSBuild-$Architecture-$DriverRevision")
					Write-CMLogEntry -Value "Info: Driver Extract Location Set - $DriverExtractDest" -Severity 1
					$DriverPackageDest = ("$DriverPackageRoot" + "$Model" + "\" + "Windows$WindowsVersion-$global:OSBuild-$Architecture-$DriverRevision")
					Write-CMLogEntry -Value "Info: Driver Package Location Set - $DriverPackageDest" -Severity 1
				}
				# Replace HP Model Slash
				$DriverExtractDest = $DriverExtractDest -replace '/', '-'
				$DriverPackageDest = $DriverPackageDest -replace '/', '-'
			}
			
			# Allow for both Driver & Standard Program Packages destinations
			if ($global:ImportInto -like "*Driver*")
			{
				$DriverPackageDest = $DriverPackageDest + "\DriverPkg\"
			}
			if ($global:ImportInto -like "*Standard*")
			{
				$DriverPackageDest = $DriverPackageDest + "\StandardPkg\"
			}
			
			# Driver variables & switches
			$DriverCategoryName = $Make + "-" + $Model + "-" + $OperatingSystem + "-" + $DriverRevision
			
			# =================== INITIATE DOWNLOADS ===================
			
			if ($global:ImportInto -ne "MDT")
			{
				# Product Type Display
				if ($global:ImportInto -eq "Download Only")
				{
					$Product = "Download Only"
				}
				else
				{
					$Product = "ConfigMgr"
				}
				
				if ($global:DownloadType -ne "Drivers")
				{
					Write-CMLogEntry -Value "======== $MODEL BIOS PROCESSING STARTED ========" -Severity 1
					if ($Make -eq "Dell")
					{
						# ================= Dell BIOS Upgrade Download ==================
						
						$DellBIOSDownload = DellBiosFinder -Model $Model
						if ($DellBIOSDownload -ne $null)
						{
							$BIOSDownload = $DellDownloadBase + "/" + $($DellBIOSDownload.Path)
							$BIOSVer = $DellBIOSDownload.DellVersion
							Write-CMLogEntry -Value "Info: Latest available BIOS version is $BIOSVer" -Severity 1
							$BIOSFile = $DellBIOSDownload.Path | Split-Path -Leaf
							$BIOSVerDir = $BIOSVer -replace '\.', '-'
							$BIOSUpdateRoot = ($DriverRepositoryRoot + $Model + "\BIOS\" + $BIOSVerDir + "\")
							$BIOSPackage = "BIOS Update - " + "$Make" + " " + $Model
							
							Set-Location -Path ($global:SiteCode + ":")
							if ((Get-CMPackage -name $BIOSPackage).Version -ne $BIOSVer)
							{
								Set-Location -Path $global:TempDirectory
								if (($BIOSDownload -like "*.exe") -and ($Make -eq "Dell"))
								{
									Write-CMLogEntry -Value "Info: BIOS Download URL Found: $BIOSDownload" -Severity 2
									
									# Check for destination directory, create if required and download the BIOS upgrade file
									if ((Test-Path -Path "$($DriverRepositoryRoot + $Model + '\BIOS\' + $BIOSVerDir + '\' + $BIOSFile)") -eq $false)
									{
										If ((Test-Path -Path $BIOSUpdateRoot) -eq $false)
										{
											Write-CMLogEntry -Value "Info: Creating $BIOSUpdateRoot folder" -Severity 1
											New-Item -Path $BIOSUpdateRoot -ItemType Directory
										}
										Write-CMLogEntry -Value "Info: Downloading $($BIOSFile) BIOS update file" -Severity 1
										if ($global:UseProxyServer -eq $true)
										{
											Invoke-WebRequest -Uri $BIOSDownload -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials -OutFile (Join-Path $BIOSUpdateRoot $BIOSFile) -TimeoutSec 120
										}
										else
										{
											Invoke-WebRequest -Uri $BIOSDownload -OutFile (Join-Path $BIOSUpdateRoot $BIOSFile) -TimeoutSec 120
										}
										
										
									}
									else
									{
										Write-CMLogEntry -Value "Info: Skipping $BIOSFile... File already downloaded." -Severity 2
									}
									
									# ================= Dell Flash 64 Upgrade Download ==================
									
									$FlashUtilDir = $DriverRepositoryRoot + "\Flash64Utility\"
									$Flash64BitDownload = (Invoke-WebRequest -Uri $Dell64BIOSUtil).links | Where-Object { $_.OuterText -eq "Here" }
									$Flash64BitZip = $($FlashUtilDir + $(($Flash64BitDownload).href | Split-Path -Leaf))
									
									if ((Test-Path -Path $Flash64BitZip) -eq $false)
									{
										if ((Test-Path -Path $FlashUtilDir) -eq $false)
										{
											Write-CMLogEntry -Value "Info: Creating Directory - $FlashUtilDir" -Severity 1
											New-Item -ItemType Directory -Path $FlashUtilDir | Out-Null
										}
										
										if ($global:UseProxyServer -eq $true)
										{
											Invoke-WebRequest -Uri ($Flash64BitDownload.href) -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials -OutFile $Flash64BitZip -TimeoutSec 120
										}
										else
										{
											Invoke-WebRequest -Uri ($Flash64BitDownload.href) -OutFile $Flash64BitZip -TimeoutSec 120
										}
										
										# Unzip Flash64 Exe
										Write-CMLogEntry -Value "Info: Unzipping Dell Flash64 EXE" -Severity 1
										Add-Type -assembly "system.io.compression.filesystem"
										[io.compression.zipfile]::ExtractToDirectory("$($Flash64BitZip)", "$($FlashUtilDir)")
										
									}
									Write-CMLogEntry -Value "Info: Copying Dell Flash64Bit EXE To $BIOSUpdateRoot" -Severity 1
									$Flash64BitExe = Get-ChildItem -Path "$($FlashUtilDir)" -Filter *.exe -File
									Get-ChildItem -Path "$($FlashUtilDir)" -Filter *.EXE -File | Copy-Item -Destination "$($BIOSUpdateRoot)"
									
								}
								
								if ($Product -ne "Download Only")
								{
									# ================= Create BIOS Update Package ==================
									
									Set-Location -Path ($global:SiteCode + ":")
									$BIOSUpdatePackage = ("BIOS Update - " + "$Make" + " " + $Model)
									$BIOSModelPackage = Get-CMPackage | Where-Object { $_.Name -match $BIOSUpdatePackage } | Sort-Object SourceDate -Descending | select -First 1
									
									if (($BIOSModelPackage.Version -ne $BIOSVer) -or ($BIOSModelPackage -eq $null))
									{
										Write-CMLogEntry -Value "$($Product): Creating BIOS Package" -Severity 1
										New-CMPackage -Name "$BIOSUpdatePackage" -Path "$BIOSUpdateRoot" -Description "$Make $Model BIOS Updates" -Manufacturer "$Make" -Language English -version $BIOSVer
										if ($global:EnableBinaryDif -eq $true)
										{
											Write-CMLogEntry -Value "$($Product): Enabling Binary Delta Replication" -Severity 1
											Set-CMPackage -Name "$BIOSUpdatePackage" -EnableBinaryDeltaReplication $true
										}
										
										Set-Location -Path $global:TempDirectory
										
										# =============== Distrubute Content =================
										Set-Location -Path ($global:SiteCode + ":")
										$SCCMPackage = Get-CMPackage -Name $BIOSUpdatePackage | Where-Object { $_.Version -eq $BIOSVer }
										DistributeContent -Product $Product -Package $SCCMPackage.PackageID
										Write-CMLogEntry -Value "$($Product): BIOS Update Package $($SCCMPackage.PackageID) Created & Distributing" -Severity 1
										Set-Location -Path $global:TempDirectory
									}
									else
									{
										Write-CMLogEntry -Value "$($Product): BIOS package already exists" -Severity 1
									}
								}
							}
							Set-Location -Path $global:TempDirectory
							Write-CMLogEntry -Value "Info: Latest available BIOS package already exists" -Severity 1
							
						}
						else
						{
							Write-CMLogEntry -Value "Info: Unable to retrieve BIOS Download URL For $Make Client Model: $($Model)" -Severity 2
						}
					}
					if ($Make -eq "Lenovo")
					{
						# ================= Lenovo BIOS Upgrade Download ==================
						
						Write-CMLogEntry -Value "Info: Retrieving BIOS Download URL For $Make Client Model: $($Model)" -Severity 1
						Set-Location -Path $global:TempDirectory
						Write-CMLogEntry -Value "Info: Attempting to find download URL using LenovoBiosFinder function" -Severity 1
						$BIOSDownload = LenovoBiosFinder -Model $Model -OS $WindowsVersion
						
						if ($BIOSDownload -ne $null)
						{
							# Download Lenovo BIOS Details XML
							if ($global:UseProxyServer -eq $true)
							{
								Invoke-WebRequest -Uri $($BIOSDownload.Location) -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials -OutFile (Join-Path $global:TempDirectory $($BIOSDownload.Location | Split-Path -leaf)) -TimeoutSec 120
							}
							else
							{
								Invoke-WebRequest -Uri $($BIOSDownload.Location) -OutFile (Join-Path $global:TempDirectory $($BIOSDownload.Location | Split-Path -leaf)) -TimeoutSec 120
							}
							
							$LenovoBIOSDetails = (Select-Xml -Path ($global:TempDirectory + "\" + ($BIOSDownload.Location | Split-Path -leaf)) -XPath "/").Node.Package
							$BIOSUpdatePackage = ("BIOS Update - " + "$Make" + " " + $Model)
							Set-Location -Path ($global:SiteCode + ":")
							$BIOSModelPackage = Get-CMPackage | Where-Object { $_.Name -match $BIOSUpdatePackage } | Sort-Object SourceDate -Descending | select -First 1
							Set-Location -Path $global:TempDirectory
							
							if (($BIOSModelPackage.Version -ne $BIOSVer) -or ($LenovoBIOSDetails.Name -ne $null))
							{
								$BIOSFile = ($LenovoBIOSDetails.ExtractCommand).Split(" ")[0]
								Write-CMLogEntry -Value "Info: Found exe file link: $BIOSFile" -Severity 1
								$BIOSVer = $LenovoBIOSDetails.version
								$BIOSReleaseDate = ($LenovoBIOSDetails.ReleaseDate).Replace("-", "")
								Write-CMLogEntry -Value "Info: BIOS version is $BIOSVer" -Severity 1
								$BIOSUpdateRoot = ($DriverRepositoryRoot + $Model + "\BIOS\" + $BIOSVer + "\")
								Write-CMLogEntry -Value "Info: BIOS update directory set to $BIOSUpdateRoot" -Severity 1
								
								# Check for destination directory, create if required and download the BIOS upgrade file
								if ((Test-Path -Path "$($BIOSUpdateRoot)") -eq $false)
								{
									New-Item -Path "$BIOSUpdateRoot" -ItemType Directory
									$BIOSFileDownload = ($BIOSDownload.Location | Split-Path -Parent) + "/$BIOSFile"
									# Correct slash direction issues
									$BIOSFileDownload = $BIOSFileDownload.Replace("\", "/")
									Write-CMLogEntry -Value "Info: Downloading BIOS update file from $BIOSFileDownload" -Severity 1
									
									if ($global:UseProxyServer -eq $true)
									{
										Invoke-WebRequest -Uri $BIOSFileDownload -Proxy $GlobalProxyServer -ProxyUseDefaultCredentials -OutFile (Join-Path $BIOSUpdateRoot $BIOSFile) -TimeoutSec 120
									}
									else
									{
										Invoke-WebRequest -Uri $BIOSFileDownload -OutFile (Join-Path $BIOSUpdateRoot $BIOSFile) -TimeoutSec 120
									}
									
									# =============== Extract BIOS Files =================
									
									$BIOSExtractSwitches = ((($LenovoBIOSDetails.ExtractCommand).TrimStart("$BIOSFile")).Trim()).Replace("%PACKAGEPATH%", "$BIOSUpdateRoot")
									Write-CMLogEntry -Value "Info: BIOS Switches = $BIOSExtractSwitches" -Severity 1
									# Cater for BIOS extract issues with UNC paths
									$BIOSExtractSwitches = ((($LenovoBIOSDetails.ExtractCommand).TrimStart("$BIOSFile")).Trim()).Replace("%PACKAGEPATH%", ($global:TempDirectory + "\$($Model.Replace(' ', ''))\$BIOS\$BIOSVer"))
									Start-Process -FilePath $("$BIOSUpdateRoot" + $BIOSFile) -ArgumentList $BIOSExtractSwitches -Wait
									Write-CMLogEntry -Value "Info: Copying extracted files to $BIOSUpdateRoot" -Severity 1
									Get-ChildItem -Path ($global:TempDirectory + "\$($Model.Replace(' ', ''))\$BIOS\$BIOSVer") -Recurse | Move-Item -Destination "$BIOSUpdateRoot"
									Write-CMLogEntry -Value "Info: Removing source BIOS exe file" -Severity 1
									Get-ChildItem -Path "$BIOSUpdateRoot" -Filter "*.exe" | Where-Object { $_.Name -eq $BIOSFile } | Remove-Item
									
									If ($global:ImportInto -notmatch "Download")
									{
										# =============== Create Package =================
										Set-Location -Path ($global:SiteCode + ":")
										Write-CMLogEntry -Value "$($Product): Creating BIOS Package" -Severity 1
										New-CMPackage -Name "$BIOSUpdatePackage" -Path "$BIOSUpdateRoot" -Description "$Make $Model BIOS Updates (Models included:$global:LenovoModelTypeList) (Release Date:$BIOSReleaseDate)" -Manufacturer "$Make" -Language English -version $LenovoBIOSDetails.Version
										if ($global:EnableBinaryDif -eq $true)
										{
											Write-CMLogEntry -Value "$($Product): Enabling Binary Delta Replication" -Severity 1
											Set-CMPackage -Name "$BIOSUpdatePackage" -EnableBinaryDeltaReplication $true
										}
										
										# =============== Distrubute Content =================
										Set-Location -Path ($global:SiteCode + ":")
										$SCCMPackage = Get-CMPackage -Name $BIOSUpdatePackage | Where-Object { $_.Version -eq $BIOSVer }
										DistributeContent -Product $Product -Package $SCCMPackage.PackageID
										Write-CMLogEntry -Value "$($Product): BIOS Update Package $($SCCMPackage.PackageID) Created & Distributing" -Severity 1
									}
									Set-Location -Path $global:TempDirectory
								}
								else
								{
									Write-CMLogEntry -Value "Info: BIOS package already exists" -Severity 2
								}
							}
						}
						else
						{
							Write-CMLogEntry -Value "Error: Unable to find BIOS link" -Severity 2
						}
						Set-Location -Path $global:TempDirectory
					}
				}
				Write-CMLogEntry -Value "======== $Model BIOS PROCESSING FINISHED ========" -Severity 1
			}
			
			if (($global:DownloadType -ne "BIOS") -and ($global:ImportInto -ne "MDT"))
			{
				Write-CMLogEntry -Value "======== $PRODUCT $Model DRIVER PROCESSING STARTED ========" -Severity 1
				# =============== ConfigMgr Driver Cab Download =================				
				Write-CMLogEntry -Value "$($Product): Retrieving ConfigMgr Driver Pack Site For $Make $Model" -Severity 1
				Write-CMLogEntry -Value "$($Product): URL Found: $ModelURL" -Severity 1
				
				if (($ModelURL -ne $Null) -and ($ModelURL -ne "badLink"))
				{
					# Cater for HP / Model Issue
					$Model = $Model -replace '/', '-'
					$Model = $Model.Trim()
					Set-Location -Path $global:TempDirectory
					# Check for destination directory, create if required and download the driver cab
					if ((Test-Path -Path $("$DriverRepositoryRoot" + "$Model" + "\Driver Cab\" + "$DriverCab")) -eq $false)
					{
						Write-CMLogEntry -Value "$($Product): Creating $Model download folder" -Severity 1
						if ((Test-Path -Path $("$DriverRepositoryRoot" + "$Model" + "\Driver Cab")) -eq $false)
						{
							Write-CMLogEntry -Value "$($Product): Creating $("$DriverRepositoryRoot" + "$Model" + "\Driver Cab") folder " -Severity 1
							New-Item -ItemType Directory -Path $("$DriverRepositoryRoot" + "$Model" + "\Driver Cab")
						}
						Write-CMLogEntry -Value "$($Product): Downloading $DriverCab driver cab file" -Severity 1
						Write-CMLogEntry -Value "$($Product): Downloading from URL: $DriverDownload" -Severity 1
						
						Start-Job -Name "$Model-DriverDownload" -ScriptBlock $DriverDownloadJob -ArgumentList ($DriverRepositoryRoot, $Model, $DriverCab, $DriverDownload, $GlobalProxyServer, $ProxyCred)
						sleep -Seconds 5
						$DriverDownloadJob = Get-Job -Name "$Model-DriverDownload"
						while (($DriverDownloadJob).State -eq "Running" -and ($DriverDownloadJob).HasMoreData -eq "True")
						{
							Write-CMLogEntry -Value "$($Product): Downloading $DriverDownload" -Severity 1
							sleep -seconds 30
						}
						Write-CMLogEntry -Value "$($Product): Driver Revision: $DriverRevision" -Severity 1
					}
					else
					{
						Write-CMLogEntry -Value "$($Product): Skipping $DriverCab... Driver pack already downloaded." -Severity 1
					}
					
					# Cater for HP / Model Issue
					$Model = $Model -replace '/', '-'
					
					if (((Test-Path -Path "$($DriverRepositoryRoot + "$Model" + '\Driver Cab\' + $DriverCab)") -eq $true) -and ($DriverCab -ne $null))
					{
						Write-CMLogEntry -Value "$($Product): $DriverCab File Exists - Processing Driver Package" -Severity 1
						# =============== Create Driver Package + Import Drivers =================
						
						if ((Test-Path -Path "$DriverExtractDest") -eq $false)
						{
							New-Item -ItemType Directory -Path "$($DriverExtractDest)"
						}
						if ((Get-ChildItem -Path "$DriverExtractDest" -Recurse -Filter *.inf -File).Count -eq 0)
						{
							Write-CMLogEntry -Value "==================== $PRODUCT DRIVER EXTRACT ====================" -Severity 1
							Write-CMLogEntry -Value "$($Product): Expanding Driver CAB Source File: $DriverCab" -Severity 1
							Write-CMLogEntry -Value "$($Product): Driver CAB Destination Directory: $DriverExtractDest" -Severity 1
							if ($Make -eq "Dell")
							{
								Write-CMLogEntry -Value "$($Product): Extracting $Make Drivers to $DriverExtractDest" -Severity 1
								Expand "$DriverSourceCab" -F:* "$DriverExtractDest"
							}
							
							if ($Make -eq "HP")
							{
								# Driver Silent Extract Switches
								$HPTemp = $global:TempDirectory + "\" + $Model + "\Win" + $WindowsVersion + $Architecture
								$HPTemp = $HPTemp -replace '/', '-'
								
								# HP Work Around For Long Dir
								if ((($HPTemp).Split("-").Count) -gt "1")
								{
									$HPTemp = ($HPTemp).Split("-")[0]
								}
								
								Write-CMLogEntry -Value "$($Product): Extracting $Make Drivers to $HPTemp" -Severity 1
								$HPSilentSwitches = "-PDF -F" + "$HPTemp" + " -S -E"
								Write-CMLogEntry -Value "$($Product): Using $Make Silent Switches: $HPSilentSwitches" -Severity 1
								Start-Process -FilePath "$($DriverRepositoryRoot + $Model + '\Driver Cab\' + $DriverCab)" -ArgumentList $HPSilentSwitches -Verb RunAs
								$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
								
								# Wait for HP SoftPaq Process To Finish
								While ((Get-Process).name -contains $DriverProcess)
								{
									Write-CMLogEntry -Value "$($Product): Waiting For Extract Process (Process: $DriverProcess) To Complete..  Next Check In 30 Seconds" -Severity 1
									sleep -Seconds 30
								}
								
								# Move HP Extracted Drivers To UNC Share 
								$HPExtract = Get-ChildItem -Path $HPTemp -Directory
								# Loop through the HP extracted driver folders to find the extracted folders and reduce directory path
								while ($HPExtract.Count -eq 1)
								{
									$HPExtract = Get-ChildItem -Path $HPExtract.FullName -Directory
								}
								# Set HP extracted folder
								$HPExtract = $HPExtract.FullName | Split-Path -Parent | Select -First 1
								Write-CMLogEntry -Value "$($Product): HP Driver Source Directory Set To $HPExtract" -Severity 1
								if ((Test-Path -Path "$HPExtract") -eq $true)
								{
									Start-Job -Name "$Model-Driver-Move" -ScriptBlock $MoveDrivers -ArgumentList ($HPExtract, $DriverExtractDest)
									while ((Get-Job -Name "$Model-Driver-Move").State -eq "Running")
									{
										Write-CMLogEntry -Value "$($Product): Moving $Make $Model $OperatingSystem $Architecture Driver.. Next Check In 30 Seconds" -Severity 1
										sleep -seconds 30
									}
								}
								else
								{
									Write-CMLogEntry -Value "ERROR: Issues occured during the $Make $Model extract process" -Severity 3
								}
							}
							
							if ($Make -eq "Lenovo")
							{
								# Driver Silent Extract Switches
								$LenovoSilentSwitches = "/VERYSILENT /DIR=" + '"' + $DriverExtractDest + '"' + ' /Extract="Yes"'
								Write-CMLogEntry -Value "$($Product): Using $Make Silent Switches: $LenovoSilentSwitches" -Severity 1
								Write-CMLogEntry -Value "$($Product): Extracting $Make Drivers to $DriverExtractDest" -Severity 1
								Start-Process -FilePath "$($DriverRepositoryRoot + $Model + '\Driver Cab\' + $DriverCab)" -ArgumentList $LenovoSilentSwitches -Verb RunAs
								$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
								# Wait for Lenovo Driver Process To Finish
								While ((Get-Process).name -contains $DriverProcess)
								{
									Write-CMLogEntry -Value "$($Product): Waiting For Extract Process (Process: $DriverProcess) To Complete..  Next Check In 60 Seconds" -Severity 1
									sleep -seconds 30
								}
							}
							
							if ($Make -eq "Acer")
							{
								# Driver Silent Extract Switches
								$AcerSilentSwitches = "x " + '"' + $($DriverRepositoryRoot + $Model + '\Driver Cab\' + $DriverCab) + '"' + " -O" + '"' + $DriverExtractDest + '"'
								Write-CMLogEntry -Value "$($Product): Using $Make Silent Switches: $AcerSilentSwitches" -Severity 1
								Write-CMLogEntry -Value "$($Product): Extracting $Make Drivers to $DriverExtractDest" -Severity 1
								$DriverProcess = Start-Process 'C:\Program Files\7-Zip\7z.exe' -ArgumentList $AcerSilentSwitches -PassThru -NoNewWindow
								# Wait for Acer Driver Process To Finish
								While ((Get-Process).ID -eq $DriverProcess.ID)
								{
									Write-CMLogEntry -Value "$($Product): Waiting For Extract Process (Process ID: $($DriverProcess.ID)) To Complete..  Next Check In 60 Seconds" -Severity 1
									sleep -seconds 30
								}
							}
							
							if ($Make -eq "Microsoft")
							{
								# Driver Silent Extract Switches
								$MicrosoftTemp = $global:TempDirectory + "\" + $Model + "\Win" + $WindowsVersion + $Architecture
								$MicrosoftTemp = $MicrosoftTemp -replace '/', '-'
								
								# Driver Silent Extract Switches
								$MicrosoftSilentSwitches = "/a" + '"' + $($DriverRepositoryRoot + $Model + "\Driver Cab\" + $DriverCab) + '"' + '/QN TARGETDIR="' + $MicrosoftTemp + '"'
								Write-CMLogEntry -Value "$($Product): Extracting $Make Drivers to $MicrosoftTemp" -Severity 1
								$DriverProcess = Start-Process msiexec.exe -ArgumentList $MicrosoftSilentSwitches -PassThru
								
								# Wait for Microsoft Driver Process To Finish
								While ((Get-Process).ID -eq $DriverProcess.ID)
								{
									Write-CMLogEntry -Value "$($Product): Waiting For Extract Process (Process ID: $($DriverProcess.ID)) To Complete..  Next Check In 60 Seconds" -Severity 1
									sleep -seconds 30
								}
								
								# Move Microsoft Extracted Drivers To UNC Share 
								$MicrosoftExtractDirs = Get-ChildItem -Path $MicrosoftTemp -Directory -Recurse | Where-Object { $_.Name -match "Drivers" -or $_.Name -match "Firmware" }
								
								# Set Microsoft extracted folder
								
								$MicrosoftExtract = $MicrosoftExtractDirs.FullName | Split-Path -Parent | Select -First 1
								Write-CMLogEntry -Value "$($Product): Microsoft Driver Source Directory Set To $MicrosoftExtract" -Severity 1
								if ((Test-Path -Path "$MicrosoftExtract") -eq $true)
								{
									Start-Job -Name "$Model-Driver-Move" -ScriptBlock $MoveDrivers -ArgumentList ($MicrosoftExtract, $DriverExtractDest)
									while ((Get-Job -Name "$Model-Driver-Move").State -eq "Running")
									{
										Write-CMLogEntry -Value "$($Product): Moving $Make $Model $OperatingSystem $Architecture Driver.. Next Check In 30 Seconds" -Severity 1
										sleep -seconds 30
									}
								}
								else
								{
									Write-CMLogEntry -Value "ERROR: Issues occured during the $Make $Model extract process" -Severity 3
								}
							}
						}
						else
						{
							Write-CMLogEntry -Value "Skipping.. Drivers already extracted." -Severity 1
						}
						
						if ($global:ImportInto -ne "Download Only")
						{
							Write-CMLogEntry -Value "$($Product): Checking For Extracted Drivers" -Severity 1
							if ($global:ImportInto -like "*Driver*")
							{
								if ((Get-ChildItem -Recurse -Path "$DriverExtractDest" -Filter *.inf -File).count -ne 0)
								{
									Write-CMLogEntry -Value "$($Product): Driver Count In Path $DriverExtractDest - $((Get-ChildItem -Recurse -Path "$DriverExtractDest" -Filter *.inf -File).count) " -Severity 1
									Write-CMLogEntry -Value "==================== $PRODUCT DRIVER IMPORT ====================" -Severity 1
									if ($global:OSBuild -eq $null)
									{
										$CMDriverPackage = ("$Make " + $Model + " - " + $OperatingSystem + " " + $Architecture)
									}
									else
									{
										$CMDriverPackage = ("$Make " + $Model + " - " + $OperatingSystem + " " + $global:OSBuild + " " + $Architecture)
									}
									Set-Location -Path ($global:SiteCode + ":")
									if ((Get-CMDriverPackage -Name "$($CMDriverPackage)" | Where-Object { $_.Version -eq $DriverRevision }) -eq $null)
									{
										Set-Location -Path $global:TempDirectory
										if (("$DriverPackageDest" -ne $null) -and ((Test-Path -Path "$DriverPackageDest") -eq $false))
										{
											New-Item -ItemType Directory -Path "$DriverPackageDest"
										}
										Write-CMLogEntry -Value "$($Product): Creating Driver Package $CMDriverPackage" -Severity 1
										Write-CMLogEntry -Value "$($Product): Searching For Driver INF Files In $DriverExtractDest" -Severity 1
										$DriverINFFiles = Get-ChildItem -Path "$DriverExtractDest" -Recurse -Filter "*.inf" -File | Where-Object { $_.FullName -like "*$Architecture*" }
										if ($DriverINFFiles.Count -ne $null)
										{
											Set-Location -Path ($global:SiteCode + ":")
											if (Get-CMCategory -CategoryType DriverCategories -name $DriverCategoryName)
											{
												Write-CMLogEntry -Value "$($Product): Category already exists" -Severity 1
												$DriverCategory = Get-CMCategory -CategoryType DriverCategories -name $DriverCategoryName
											}
											else
											{
												Write-CMLogEntry -Value "$($Product): Creating Category $DriverCategoryName" -Severity 1
												$DriverCategory = New-CMCategory -CategoryType DriverCategories -name $DriverCategoryName
											}
											Write-CMLogEntry -Value "$($Product): Creating Driver Package for $Make $Model (Version $DriverRevision)" -Severity 1
											New-CMDriverPackage -Name $CMDriverPackage -path "$DriverPackageDest"
											Write-CMLogEntry -Value "$($Product): New CMDriverPacakge Name: $CMDriverPackage | Path $DriverPackageDest" -Severity 1
											Set-CMDriverPackage -Name $CMDriverPackage -Version $DriverRevision
											
											# Check For Driver Package
											$SCCMDriverPackage = Get-CMDriverPackage -Name $CMDriverPackage | Where-Object { $_.Version -eq $DriverRevision }
											Write-CMLogEntry -Value "$($Product): Checking Driver Package Created Successfully" -Severity 1
											
											if ($SCCMDriverPackage.PackageID -ne $null)
											{
												# Import Driver Loop
												$DriverNo = 1
												foreach ($DriverINF in $DriverINFFiles)
												{
													$DriverInfo = Import-CMDriver -UncFileLocation "$($DriverINF.FullName)" -ImportDuplicateDriverOption AppendCategory -EnableAndAllowInstall $True -AdministrativeCategory $DriverCategory | Select-Object *
													Add-CMDriverToDriverPackage -DriverID $DriverInfo.CI_ID -DriverPackageName "$($CMDriverPackage)"
													Write-CMLogEntry -Value "$($Product): Importing Driver INF $DriverNo Of $($DriverINFFiles.count): $($DriverINF.FullName | Split-Path -Leaf)" -Severity 1
													$DriverNo++
												}
												
												Write-CMLogEntry -Value "$($Product): Driver Package $($SCCMDriverPackage.PackageID) Created Succesfully" -Severity 1
												# =============== Distrubute Content =================
												Write-CMLogEntry -Value "$($Product): Distributing $($SCCMDriverPackage.PackageID)" -Severity 1
												DistributeContent -Product $Product -Package $SCCMDriverPackage.PackageID
											}
											else
											{
												Write-CMLogEntry -Value "Error: Errors Occurred While Creating Driver Package" -Severity 3
											}
											Set-Location -Path $global:TempDirectory
										}
										else
										{
											Write-CMLogEntry -Value "$($Product): Extract Folder Empty.. Skipping Driver Import / Package Creation" -Severity 2
										}
									}
									else
									{
										Write-CMLogEntry -Value "$($Product): Driver Package Already Exists.. Skipping" -Severity 2
										Set-Location -Path $global:TempDirectory
									}
								}
								else
								{
									Write-CMLogEntry -Value "======== DRIVER EXTRACT ISSUE DETECTED ========" -Severity 3
									Write-CMLogEntry -Value "$($Product): Issues occurred while reading extracted drivers" -Severity 3
									Write-CMLogEntry -Value "$($Product): Driver count in path $DriverExtractDest - $((Get-ChildItem -Recurse -Path "$DriverExtractDest" -Filter *.inf -File).count) " -Severity 1
								}
							}
							
							#Write-CMLogEntry -Value "$($Product): Checking For Extracted Drivers" -Severity 1 
							if ($global:ImportInto -like "*Standard*")
							{
								Write-CMLogEntry -Value "$($Product): Driver Count In Path $DriverExtractDest - $((Get-ChildItem -Recurse -Path "$DriverExtractDest" -Filter *.inf -File).count) " -Severity 1
								if ((Get-ChildItem -Recurse -Path "$DriverExtractDest" -Filter *.inf -File).Count - $null)
								{
									Write-CMLogEntry -Value "$($Product): Validated Drivers Exist In $DriverExtractDest - Processing Driver Packaging Steps " -Severity 1
									Write-CMLogEntry -Value "==================== $PRODUCT DRIVER PACKAGE  ====================" -Severity 1
									if ($global:OSBuild -eq $null)
									{
										$CMPackage = ("Drivers - " + "$Make " + $Model + " - " + $OperatingSystem + " " + $Architecture)
									}
									else
									{
										$CMPackage = ("Drivers - " + "$Make " + $Model + " - " + $OperatingSystem + " " + $global:OSBuild + " " + $Architecture)
									}
									
									if ($Make -eq "Lenovo")
									{
										$CMPackage = $CMPackage + " ($global:LenovoModelType)"
									}
									
									Set-Location -Path ($global:SiteCode + ":")
									if ((Get-CMPackage -Name $CMPackage | Where-Object { $_.Version -eq $DriverRevision }) -eq $null)
									{
										Set-Location -Path $global:TempDirectory
										if ((Test-Path -Path "$DriverPackageDest") -eq $false)
										{
											New-Item -ItemType Directory -Path "$DriverPackageDest"
										}
										Set-Location -Path ($global:SiteCode + ":")
										Write-CMLogEntry -Value "$($Product): Creating Package for $Make $Model (Version $DriverRevision)" -Severity 1
										
										# Work around for HP WMI when using the ConfigMgr Web Service
										if ($Make -eq "HP")
										{
											$Manufacturer = "Hewlett-Packard"
										}
										else
										{
											$Manufacturer = $Make
										}
										
										# Create Driver Package
										if ($Make -eq "Lenovo")
										{
											New-CMPackage -Name "$CMPackage" -path "$DriverPackageDest" -Manufacturer $Manufacturer -Description "$Make $Model Windows $WindowsVersion $Architecture Drivers (Models included:$global:LenovoModelTypeList)" -Version $DriverRevision	
										}
										elseif ($Make -eq "Microsoft")
										{
											New-CMPackage -Name "$CMPackage" -path "$DriverPackageDest" -Manufacturer $Manufacturer -Description "$Make $Model Windows $WindowsVersion $Architecture Drivers (Models included:$ModelWMI)" -Version $DriverRevision
										}
										else
										{
											New-CMPackage -Name "$CMPackage" -path "$DriverPackageDest" -Manufacturer $Manufacturer -Description "$Make $Model Windows $WindowsVersion $Architecture Drivers" -Version $DriverRevision
										}
										if ($global:EnableBinaryDif -eq $true)
										{
											Write-CMLogEntry -Value "$($Product): Enabling Binary Delta Replication" -Severity 1
											Set-CMPackage -Name "$CMPackage" -EnableBinaryDeltaReplication $true
										}
										$MifVersion = $OperatingSystem + " " + $Architecture
										Set-CMPackage -Name "$CMPackage" -MifName $Model -MifVersion $MifVersion
										# Move Extracted Drivers To Driver Package Directory
										Write-CMLogEntry -Value "$($Product): Source Directory $DriverExtractDest" -Severity 1
										Write-CMLogEntry -Value "$($Product): Destination Directory $DriverPackageDest" -Severity 1
										Set-Location -Path $global:TempDirectory
										# Copy Drivers To Package Location
										Start-Job -Name "$Model-Driver-Package" -ScriptBlock $PackageDrivers -ArgumentList ($Make, $DriverExtractDest, $Architecture, $DriverPackageDest)
										while ((Get-Job -Name "$Model-Driver-Package").State -eq "Running")
										{
											Write-CMLogEntry -Value "$($Product): Copying $Make $Model $OperatingSystem $Architecture Drivers.. Next Check In 30 Seconds" -Severity 1
											sleep -seconds 30
										}
										
										if ((Get-Job -Name "$Model-Driver-Package").State -eq "Completed")
										{
											# Check For Driver Package
											Set-Location -Path ($global:SiteCode + ":")
											$SCCMPackage = Get-CMPackage -Name $CMPackage | Where-Object { $_.Version -eq $DriverRevision }
											if ($SCCMPackage.PackageID -ne $null)
											{
												Write-CMLogEntry -Value "$($Product): Driver Package $($SCCMPackage.PackageID) Created Succesfully" -Severity 1
												
												# =============== Distrubute Content =================
												DistributeContent -Product $Product -Package $SCCMPackage.PackageID
											}
											else
											{
												Write-CMLogEntry -Value "Error: Errors Occurred While Creating Package" -Severity 3
											}
										}
										else
										{
											Write-CMLogEntry -Value "Error: Errors Occurred While Copying Drivers" -Severity 3
										}
										Get-Job -Name "$Model-Driver-Package" | Remove-Job
										Set-Location -Path $global:TempDirectory
									}
									else
									{
										Write-CMLogEntry -Value "$($Product): Driver Package Already Exists.. Skipping" -Severity 2
										Set-Location -Path $global:TempDirectory
									}
								}
								else
								{
									Write-CMLogEntry -Value "======== DRIVER EXTRACT ISSUE DETECTED ========" -Severity 3
									Write-CMLogEntry -Value "$($Product): Issues occurred while reading extracted drivers" -Severity 3
									Write-CMLogEntry -Value "$($Product): Driver Count In Path $DriverExtractDest - $((Get-ChildItem -Recurse -Path "$DriverExtractDest" -Filter *.inf -File).count) " -Severity 1
								}
							}
						}
					}
					else
					{
						Write-CMLogEntry -Value "$($Product): $DriverCab File Download Failed" -Severity 3
					}
				}
				else
				{
					Write-CMLogEntry -Value "$($Product): Operating system driver package download path not found.. Skipping $Model" -Severity 3
				}
				Write-CMLogEntry -Value "======== $PRODUCT $MODEL DRIVER PROCESSING FINISHED ========" -Severity 1
			}
			
			Set-Location -Path $global:TempDirectory
			
			if (($global:ImportInto -like "*Both*") -or ($global:ImportInto -eq "MDT"))
			{
				Write-CMLogEntry -Value "======== $PRODUCT $MODEL DRIVER PROCESSING STARTED ========" -Severity 1
				Set-Location -Path $global:TempDirectory
				# Import MDT Module
				Write-CMLogEntry -Value "======== $Product Prerequisites ========" -Severity 1
				Write-CMLogEntry -Value "$($Product): Importing MDT PowerShell Module" -Severity 1
				$MDTPSLocation = "C:\Program Files\Microsoft Deployment Toolkit\bin\MicrosoftDeploymentToolkit.psd1"
				if ((Test-Path -Path $MDTPSLocation) -eq $true)
				{
					Import-Module "$MDTPSLocation"
					$Product = "MDT"
					
					# =================== MDT Driver Download =====================
					Write-CMLogEntry -Value "========  $Product Driver Download ========" -Severity 1
					Write-CMLogEntry -Value "$($Product): Starting $Product Driver Download Process" -Severity 1
					
					# =================== DEFINE VARIABLES =====================
					
					Write-CMLogEntry -Value "$($Product): Driver Package Base Location Set To $DriverRepositoryRoot" -Severity 1
					
					# Operating System Version
					$OperatingSystem = ("Windows " + $WindowsVersion)
					
					# =============== MDT Driver Cab Download =================
					
					# Cater for HP / Model Issue
					$Model = $Model -replace '/', '-'
					
					if (($ModelURL -ne $null) -and ($ModelURL -ne "badLink"))
					{
						# Check for destination directory, create if required and download the driver cab
						if ((Test-Path -Path ($DriverRepositoryRoot + $Model + "\Driver Cab\" + $DriverCab)) -eq $false)
						{
							Write-CMLogEntry -Value "$($Product): Creating $Model download folder" -Severity 1
							if ((Test-Path -Path ($DriverRepositoryRoot + $Model + "\Driver Cab")) -eq $false)
							{
								New-Item -ItemType Directory -Path "$($DriverRepositoryRoot + $Model + '\Driver Cab')"
							}
							Write-CMLogEntry -Value "$($Product): Downloading $DriverCab driver cab file" -Severity 1
							Write-CMLogEntry -Value "$($Product): Downloading from URL: $DriverDownload" -Severity 1
							Start-Job -Name "$Model-DriverDownload" -ScriptBlock $DriverDownloadJob -ArgumentList ($DriverRepositoryRoot, $Model, $DriverCab, $DriverDownload, $GlobalProxyServer, $ProxyCred)
							sleep -Seconds 5
							Start-Job -Name "$Model-DriverDownload" -ScriptBlock $DriverDownloadJob -ArgumentList ($DriverRepositoryRoot, $Model, $DriverCab, $DriverDownload, $GlobalProxyServer, $ProxyCred)
							sleep -Seconds 5
							$DriverDownloadJob = Get-Job -Name "$Model-DriverDownload"
							while (($DriverDownloadJob).State -eq "Running" -and ($DriverDownloadJob).HasMoreData -eq "True")
							{
								Write-CMLogEntry -Value "$($Product): Downloading $DriverDownload." -Severity 1
								sleep -seconds 30
							}
							Write-CMLogEntry -Value "$($Product): Driver Revision: $DriverRevision" -Severity 1
						}
						else
						{
							Write-CMLogEntry -Value "$($Product): Skipping $DriverCab... Driver pack already downloaded" -Severity 2
						}
						
						# Check for destination directory, create if required and download the driver cab
						if ((Test-Path -Path "$($DriverRepositoryRoot + $Model + '\Driver Cab\' + $DriverCab)") -eq $false)
						{
							if ((Test-Path -Path "($DriverRepositoryRoot + $Model + '\Driver Cab\')") -eq $false)
							{
								Write-CMLogEntry -Value "$($Product): Creating $Model Download Folder" -Severity 1
								New-Item -ItemType Directory -Path "$($DriverRepositoryRoot + $Model + '\Driver Cab')"
							}
							else
							{
								# Remove previous driver cab revisions
								Get-ChildItem -Path "$($DriverRepositoryRoot + $Model + '\Driver Cab\')" | Remove-Item
							}
							Write-CMLogEntry -Value "$($Product): Downloading $DriverCab Driver Cab File" -Severity 1
							Start-Job -Name "$Model-DriverDownload" -ScriptBlock $DriverDownloadJob -ArgumentList ($DriverRepositoryRoot, $Model, $DriverCab, $DriverDownload, $GlobalProxyServer, $ProxyCred)
							sleep -Seconds 5
							$BitsJob = Get-BitsTransfer | Where-Object { $_.DisplayName -eq "$Model-DriverDownload" }
							while (($BitsJob).JobState -eq "Connecting")
							{
								Write-CMLogEntry -Value "$($Product): Establishing Connection to $DriverDownload" -Severity 1
								sleep -seconds 30
							}
							while (($BitsJob).JobState -eq "Transferring")
							{
								$PercentComplete = [int](($BitsJob.BytesTransferred * 100)/$BitsJob.BytesTotal);
								Write-CMLogEntry -Value "$($Product): Downloaded $([int]((($BitsJob).BytesTransferred)/ 1MB)) 1MB of $([int]((($BitsJob).BytesTotal)/ 1MB)) MB ($PercentComplete%). Next update in 30 seconds" -Severity 1
								sleep -seconds 30
							}
							Get-BitsTransfer | Where-Object { $_.DisplayName -eq "$Model-DriverDownload" } | Complete-BitsTransfer
							Write-CMLogEntry -Value "$($Product): Driver Revision: $DriverRevision" -Severity 1
						}
						else
						{
							Write-CMLogEntry -Value "$($Product): Skipping $DriverCab... Driver pack already extracted" -Severity 2
						}
						
						if (((Test-Path -Path "$($DriverRepositoryRoot + $Model + '\Driver Cab\' + $DriverCab)") -eq $true) -and ($DriverCab -ne $null))
						{
							# =============== MDT Driver EXTRACT ====================
							
							if ((Test-Path -Path "$DriverExtractDest") -eq $false)
							{
								# Extract Drivers From Driver							
								New-Item -ItemType Directory -Path "$DriverExtractDest"
							}
							if ((Get-ChildItem -Path "$DriverExtractDest" -Recurse -Filter *.inf -File).Count -eq 0)
							{
								Write-CMLogEntry -Value "======== $PRODUCT DRIVER EXTRACT ========" -Severity 1
								Write-CMLogEntry -Value "$($Product): Expanding Driver CAB Source File: $DriverCab" -Severity 1
								Write-CMLogEntry -Value "$($Product): Driver CAB Destination Directory: $DriverExtractDest" -Severity 1
								if ($Make -eq "Dell")
								{
									Write-CMLogEntry -Value "$($Product): Extracting $Make Drivers to $DriverExtractDest" -Severity 1
									Expand "$DriverSourceCab" -F:* "$DriverExtractDest"
								}
								if ($Make -eq "HP")
								{
									# Driver Silent Extract Switches
									$HPTemp = $global:TempDirectory + "\" + $Model + "\Win" + $WindowsVersion + $Architecture
									$HPTemp = $HPTemp -replace '/', '-'
									
									# HP Work Around For Long Dir
									if ((($HPTemp).Split("-").Count) -gt "1")
									{
										$HPTemp = ($HPTemp).Split("-")[0]
									}
									Write-CMLogEntry -Value "$($Product): Extracting HP Drivers to $HPTemp" -Severity 1
									$HPSilentSwitches = "-PDF -F" + $HPTemp + " -S -E"
									Write-CMLogEntry -Value "$($Product): Using $Make Silent Switches: $HPSilentSwitches" -Severity 1
									Write-CMLogEntry -Value "$($Product): Extracting $Make Drivers to $DriverExtractDest" -Severity 1
									Start-Process -FilePath "$($DriverRepositoryRoot + $Model + '\Driver Cab\' + $DriverCab)" -ArgumentList $HPSilentSwitches -Verb RunAs
									$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
									
									# Wait for HP SoftPaq Process To Finish
									While ((Get-Process).name -contains $DriverProcess)
									{
										Write-CMLogEntry -Value "$($Product): Waiting For Extract Process (Process: $DriverProcess) To Complete..  Next Check In 30 Seconds" -Severity 1
										sleep -Seconds 30
									}
									
									# Move HP Extracted Drivers To UNC Share 
									$HPExtract = Get-ChildItem -Path $HPTemp -Directory
									# Loop through the HP extracted driver folders to find the extracted folders and reduce directory path
									while ($HPExtract.Count -eq 1)
									{
										$HPExtract = Get-ChildItem -Path $HPExtract.FullName -Directory
									}
									# Set HP extracted folder
									$HPExtract = $HPExtract.FullName | Split-Path -Parent | Select -First 1
									# Start HP driver move
									Start-Job -Name "$Model-Driver-Move" -ScriptBlock $MoveDrivers -ArgumentList ($HPExtract, $DriverExtractDest)
									sleep -Seconds 2
									while ((Get-Job -Name "$Model-Driver-Move").State -eq "Running")
									{
										Write-CMLogEntry -Value "$($Product): Moving $Make $Model $OperatingSystem $Architecture Driver.. Next Check In 30 Seconds" -Severity 1
										sleep -seconds 30
									}
								}
								
								if ($Make -eq "Lenovo")
								{
									# Driver Silent Extract Switches
									$LenovoSilentSwitches = "/VERYSILENT /DIR=" + '"' + $DriverExtractDest + '"' + ' /Extract="Yes"'
									Write-CMLogEntry -Value "$($Product): Using $Make Silent Switches: $LenovoSilentSwitches" -Severity 1
									Write-CMLogEntry -Value "$($Product): Extracting $Make Drivers to $DriverExtractDest" -Severity 1
									Start-Process -FilePath $($DriverRepositoryRoot + $Model + "\Driver Cab\" + $DriverCab) -ArgumentList $LenovoSilentSwitches -Verb RunAs
									$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
									
									# Wait for Lenovo Driver Process To Finish
									While ((Get-Process).name -contains $DriverProcess)
									{
										Write-CMLogEntry -Value "$($Product): Waiting For Extract Process (Process: $DriverProcess) To Complete..  Next Check In 60 Seconds" -Severity 1
										sleep -seconds 30
									}
								}
								
								if ($Make -eq "Acer")
								{
									# Driver Silent Extract Switches
									$AcerSilentSwitches = "x " + '"' + $($DriverRepositoryRoot + $Model + "\Driver Cab\" + $DriverCab) + '"' + " -O" + '"' + $DriverExtractDest + '"'
									Write-CMLogEntry -Value "$($Product): Using $Make Silent Switches: $AcerSilentSwitches" -Severity 1
									Write-CMLogEntry -Value "$($Product): Extracting $Make Drivers to $DriverExtractDest" -Severity 1
									$DriverProcess = Start-Process 'C:\Program Files\7-Zip\7z.exe' -ArgumentList $AcerSilentSwitches -PassThru -NoNewWindow
									# Wait for Acer Driver Process To Finish
									While ((Get-Process).ID -eq $DriverProcess.ID)
									{
										Write-CMLogEntry -Value "$($Product): Waiting For Extract Process (Process ID: $($DriverProcess.ID)) To Complete..  Next Check In 60 Seconds" -Severity 1
										sleep -seconds 30
									}
								}
								
								if ($Make -eq "Microsoft")
								{
									# Driver Silent Extract Switches
									$MicrosoftTemp = $global:TempDirectory + "\" + $Model + "\Win" + $WindowsVersion + $Architecture
									$MicrosoftTemp = $MicrosoftTemp -replace '/', '-'
									
									# Driver Silent Extract Switches
									$MicrosoftSilentSwitches = "/a" + '"' + $($DriverRepositoryRoot + $Model + "\Driver Cab\" + $DriverCab) + '"' + '/QN TARGETDIR="' + $MicrosoftTemp + '"'
									Write-CMLogEntry -Value "$($Product): Extracting $Make Drivers to $MicrosoftTemp" -Severity 1
									$DriverProcess = Start-Process msiexec.exe -ArgumentList $MicrosoftSilentSwitches -PassThru
									
									# Wait for Microsoft Driver Process To Finish
									While ((Get-Process).ID -eq $DriverProcess.ID)
									{
										Write-CMLogEntry -Value "$($Product): Waiting For Extract Process (Process ID: $($DriverProcess.ID)) To Complete..  Next Check In 60 Seconds" -Severity 1
										sleep -seconds 30
									}
									
									# Move Microsoft Extracted Drivers To UNC Share 
									$MicrosoftExtractDirs = Get-ChildItem -Path $MicrosoftTemp -Directory -Recurse | Where-Object { $_.Name -match "Drivers" -or $_.Name -match "Firmware" }
									
									# Set Microsoft extracted folder
									
									$MicrosoftExtract = $MicrosoftExtractDirs.FullName | Split-Path -Parent | Select -First 1
									Write-CMLogEntry -Value "$($Product): Microsoft Driver Source Directory Set To $MicrosoftExtract" -Severity 1
									if ((Test-Path -Path "$MicrosoftExtract") -eq $true)
									{
										Start-Job -Name "$Model-Driver-Move" -ScriptBlock $MoveDrivers -ArgumentList ($MicrosoftExtract, $DriverExtractDest)
										while ((Get-Job -Name "$Model-Driver-Move").State -eq "Running")
										{
											Write-CMLogEntry -Value "$($Product): Moving $Make $Model $OperatingSystem $Architecture Driver.. Next Check In 30 Seconds" -Severity 1
											sleep -seconds 30
										}
									}
									else
									{
										Write-CMLogEntry -Value "ERROR: Issues occured during the $Make $Model extract process" -Severity 3
									}
								}
							}
							
							# =============== MDT Driver Import ====================
							
							Write-CMLogEntry -Value "======== $PRODUCT Driver Import ========" -Severity 1
							Write-CMLogEntry -Value "$($Product): Starting MDT Driver Import Process" -Severity 1
							
							# Detect First MDT PSDrive
							Write-CMLogEntry -Value "$($Product): Detecting MDT PSDrive" -Severity 1
							if (!$PSDriveName) { $PSDriveName = (Get-MDTPersistentDrive)[0].name }
							
							# Detect First MDT Deployment Share
							Write-CMLogEntry -Value "$($Product): Detecting MDT Deployment Share" -Severity 1
							if (!$DeploymentShare) { $DeploymentShare = (Get-MDTPersistentDrive)[0].path }
							$MDTDriverPath = $PSDriveName + ':\Out-of-Box Drivers'
							$MDTSelectionProfilePath = $PSDriveName + ':\Selection Profiles'
							
							# Connect to Deployment Share
							Write-CMLogEntry -Value "$($Product): Connecting to MDT share" -Severity 1
							if (!(Get-PSDrive -Name $PSDriveName -ErrorAction SilentlyContinue))
							{
								New-PSDrive -Name $PSDriveName -PSProvider MDTProvider -Root "$DeploymentShare"
								Write-CMLogEntry -Value "$($Product): $PSDriveName connected to $DeploymentShare" -Severity 1
							}
							
							$DSDriverPath = $PSDriveName + ':\Out-of-Box Drivers'
							$DSSelectionProfilePath = $PSDriveName + ':\Selection Profiles'
							
							# Connect to Deployment Share
							if ((Get-PSDrive -Name $PSDriveName -ErrorAction SilentlyContinue) -eq $false)
							{
								New-PSDrive -Name $PSDriveName -PSProvider MDTProvider -Root "$DeploymentShare"
								Write-CMLogEntry -Value "$($Product): $PSDriveName connected to $DeploymentShare" -Severity 1
							}
							
							# Cater for HP / Model Issue
							$Model = $Model -replace '/', '-'
							
							# Modify friendly manufaturer names for MDT total control method
							switch -Wildcard ($Make)
							{
								"*Dell*" {
									$Make = "Dell Inc."
								}
								"*HP*" {
									$Make = "Hewlett-Packard"
								}
								"*Microsoft*"{
									$Make = "Microsoft Corporation"
								}
							}
							
							# =============== MDT Driver Import ====================
							
							if ($global:OSBuild -eq $null)
							{
								$OperatingSystemDir = ($OperatingSystem + " " + $Architecture)
							}
							else
							{
								$OperatingSystemDir = ($OperatingSystem + " " + $global:OSBuild + " " + $Architecture)
							}
							
							$DriverSource = $DriverRepositoryRoot + $Model + '\Driver Cab\' + $DriverCab
							
							if ((Test-Path $MDTDriverPath\$OperatingSystemDir) -eq $false)
							{
								New-Item -path $MDTDriverPath -enable "True" -Name $OperatingSystemDir -ItemType Directory
							}
							if ((Test-Path $MDTSelectionProfilePath"\Drivers - "$OperatingSystemDir) -eq $false)
							{
								New-Item -path $MDTSelectionProfilePath -enable "True" -Name "Drivers - $OperatingSystemDir" -Definition "<SelectionProfile><Include path=`"Out-of-Box Drivers\$global:OS`" /></SelectionProfile>" -ReadOnly "False"
							}
							if ((Test-Path $MDTDriverPath\$OperatingSystemDir\$Make) -eq $false)
							{
								New-Item -path $MDTDriverPath\$OperatingSystemDir -enable "True" -Name $Make -ItemType Directory
							}
							if ((Test-Path $MDTDriverPath\$OperatingSystemDir\$Make\$Model) -eq $false)
							{
								New-Item -path $MDTDriverPath\$OperatingSystemDir\$Make -enable "True" -Name $Model -ItemType Directory
							}
							if ((Test-Path $MDTDriverPath\$OperatingSystemDir\$Make\$Model\$DriverRevision) -eq $false)
							{
								New-Item -path $MDTDriverPath\$OperatingSystemDir\$Make\$Model -enable "True" -Name $DriverRevision -ItemType Directory
								Write-CMLogEntry -Value "$($Product): Importing MDT driver pack for $Make $Model - Revision $DriverRevision" -Severity 1
								Write-CMLogEntry -Value "$($Product): MDT Driver Path = $MDTDriverPath\$OperatingSystemDir\$Make\$Model\$DriverRevision" -Severity 1
								
								# =============== MDT Driver Import ====================
								
								if ($Make -match "Dell")
								{
									$DriverFolder = (Get-ChildItem -Path "$DriverExtractDest" -Recurse -Directory | Where-Object { $_.Name -eq "$Architecture" } | Select -first 1).FullName
									Write-CMLogEntry -Value "$($Product): Importing MDT Drivers from $DriverExtractDest. This might take several minutes." -Severity 1
									Import-MDTDriver -path "$MDTDriverPath\$OperatingSystemDir\$Make\$Model\$DriverRevision" -SourcePath "$DriverFolder"
								}
								else
								{
									Write-CMLogEntry -Value "$($Product): Importing MDT Drivers from $DriverExtractDest. This might take several minutes." -Severity 1
									Import-MDTDriver -path "$MDTDriverPath\$OperatingSystemDir\$Make\$Model\$DriverRevision" -SourcePath "$DriverExtractDest"
								}
							}
							else
							{
								Write-CMLogEntry -Value "$($Product): Driver pack already exists.. Skipping" -Severity 2
							}
						}
						else
						{
							Write-CMLogEntry -Value "$($Product): Error Downloading $DriverCab" -Severity 3
						}
					}
				}
				else
				{
					Write-CMLogEntry -Value "Error: MDT PowerShell Commandlets Not Found - Path Specified $MDTPSLocation" -Severity 3
				}
				
				Write-CMLogEntry -Value "======== $PRODUCT $MODEL PROCESSING FINISHED ========" -Severity 1
			}
			
			
			if ($RemoveLegacyDriverCheckbox.Checked -eq $true)
			{
				Set-Location -Path ($global:SiteCode + ":")
				Write-CMLogEntry -Value "======== Superseded Driver Package Option Processing ========" -Severity 1
				$ModelDriverPacks = Get-CMDriverPackage | Where-Object { $_.Name -like "*$Model*$WindowsVersion*$Architecture*" } | Sort-Object Version -Descending
				if ($ModelDriverPacks.Count -gt "1")
				{
					$LegacyDriverPack = $ModelDriverPacks | select -Last 1
					Write-CMLogEntry -Value "$($Product): Removing $($LegacyDriverPack.Name) / Package ID $($LegacyDriverPack.PackageID)" -Severity 1
					Remove-CMDriverPackage -id $LegacyDriverPack.PackageID -Force
				}
				$ModelPackages = Get-CMPackage | Where-Object { $_.Name -like "*$Model*$WindowsVersion*$Architecture*" } | Sort-Object Version -Descending
				if ($ModelPackages.Count -gt "1")
				{
					$LegacyPackage = $ModelPackages | select -Last 1
					Write-CMLogEntry -Value "$($Product): Removing $($LegacyPackage.Name) / Package ID $($LegacyPackage.PackageID)" -Severity 1
					Remove-CMPackage -id $LegacyPackage.PackageID -Force
				}
				Set-Location -Path $global:TempDirectory
			}
			
			$RemainingModels--
			Write-CMLogEntry -Value "Info: Remaining Models To Process: $RemainingModels" -Severity 1
		}
		
	}
	
	if ($global:CleanUnused -eq $true)
	{
		Set-Location -Path ($global:SiteCode + ":")
		Write-CMLogEntry -Value "======== Clean Up Driver Option Processing ========" -Severity 1
		# Sleep to allow for driver package registration
		sleep -Seconds 10
		# Get list of unused drivers
		$DriverList = Get-CMDriverPackage | Get-CMDriver | Select -Property CI_ID
		$UnusedDrivers = Get-CMDriver | Where-Object { $_.CI_ID -notin $DriverList.CI_ID }
		Write-CMLogEntry -Value "$($Product): Found $($UnusedDrivers.Count) Unused Drivers" -Severity 1
		Write-CMLogEntry -Value "$($Product): Starting Driver Package Clean Up Process" -Severity 1
		foreach ($Driver in $UnusedDrivers)
		{
			Write-CMLogEntry -Value "$($Product): Removing $($Driver.LocalizedDisplayName) from Category $($Driver.LocalizedCategoryInstanceNames)" -Severity 1
			Remove-CMDriver -ID $Driver.CI_ID -Force
		}
		Write-CMLogEntry -Value "$($Product): Driver Clean Up Process Completed" -Severity 1
		Set-Location -Path $global:TempDirectory
	}
	
	if ($RemoveDriverSourceCheckbox.Checked -eq $true)
	{
		# Clean Up Driver Source Files
		if ((($global:RepositoryPath) -ne $null) -and ((Test-Path -Path ($global:RepositoryPath)) -eq $true))
		{
			Write-CMLogEntry -Value "$($Product): Removing Downloaded Driver Files From $($Repository). Extracted Drivers Will Remain" -Severity 1
			Get-ChildItem -Path $($Repository) -Recurse -Directory | Where-Object { $_.FullName -match "Driver Cab" } | Get-ChildItem | Remove-Item -Force
		}
	}
	
	Write-CMLogEntry -Value "======== Finished Processing ========" -Severity 1
}

function StartProcesses
{
	Write-CMLogEntry -Value "======== INITIALISING LOG FILE & CHECKING PREREQUISITES ========" -Severity 1
	Write-CMLogEntry -Value "Info: Log File Location - $global:LogDirectory" -Severity 1
	Write-CMLogEntry -Value "Info: Settings File Location - $global:SettingsDirectory" -Severity 1
	Write-CMLogEntry -Value "Info: Temp File Location - $global:TempDirectory" -Severity 1
	
	# Attempt ConfigMgr Site Code & MP Detection
	Write-CMLogEntry -Value "Info: Checking WMI for ConfigMgr SMS_Authority Values" -Severity 1
	$SCCMWMI = Get-CIMInstance -ClassName SMS_Authority -NameSpace root\ccm
	if ($SCCMWMI.CurrentManagementPoint -ne $null)
	{
		Write-CMLogEntry -Value "======== ConfigMgr Site Discovery ========" -Severity 1
		$global:SiteServer = $SCCMWMI.CurrentManagementPoint
		Write-CMLogEntry -Value "Info: ConfigMgr WMI Query Results - Site Server (Local MP) Found: $($global:SiteServer)" -Severity 1
		$global:SiteCode = ($SCCMWMI.Name).TrimStart("SMS:")
		Write-CMLogEntry -Value "Info: ConfigMgr WMI Query Results - Site Code Found: $($global:SiteCode)" -Severity 1
		ConnectSCCM
	}
	
	# Check PS Version Compatibilty
	if ($PSVersionTable.PSVersion.Major -lt "3")
	{
		Write-CMLogEntry -Value "======== COMPATIBILITY ISSUE DETECTED ========" -Severity 3
		Write-CMLogEntry -Value "Error: PowerShell Version Incompatible - Please Update PS Installation" -Severity 3
	}
	
	# Check for 7Zip Installation for Acer Drivers
	Write-CMLogEntry -Value "Info: Checking For 7-Zip Installation" -Severity 1
	
	# Read registry installed applications
	$64BitApps = Get-ChildItem -Path HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall -Recurse | Get-ItemProperty
	$32BitApps = Get-ChildItem -Path HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall -Recurse | Get-ItemProperty
	
	foreach ($App in $64BitApps)
	{
		if ($App.DisplayName -match "7-Zip")
		{
			$7ZipInstalled = $true
		}
	}
	
	foreach ($App in $32BitApps)
	{
		if ($App.DisplayName -match "7-Zip")
		{
			$7ZipInstalled = $true
		}
	}
	
	
	if ($7ZipInstalled -eq $true)
	{
		$Acer = $true
	}
	else
	{
		$Acer = $false
		Write-CMLogEntry -Value "======== ACER COMPATIBILITY ISSUE DETECTED ========" -Severity 3
		Write-CMLogEntry -Value "Error: Prerequisite 7-Zip Not Found - Acer Support Disabled" -Severity 3
	}
	
	# // Read Previously Selected Values	
	if ((Test-Path -Path $global:SettingsDirectory\DATSettings.xml) -eq $true)
	{
		Write-Host "attempting to read $($global:SettingsDirectory + '\DATSettings.xml') "
		Read-XMLSettings
	}
	
	if ($Global:DATSettingsXML.Settings.SiteSettings.Server -ne $null)
	{
		$global:SiteServer = [string]$global:SiteServer
		Write-CMLogEntry -Value "======== Validating ConfigMgr Server Details $(Get-Date) ========" -Severity 1
		ConnectSCCM
	}
	
	Write-CMLogEntry -Value "Mode: Silent running switch enabled" -Severity 2
	$ErrorActionPreference = "Stop"
	Write-Host "=== SCConfigMgr Download Automation Tool - Silent Running ==="
	If (($ScriptRelease -ne $null) -and ($ScriptRelease -lt $NewRelease))
	{
		Write-CMLogEntry -Value "Update Alert: Newer Version Available - $NewRelease" -Severity 2
	}
	Write-Host "1. Updating model list based on models found within the XML settings file"
	Get-VendorSources $global:SiteServer $global:SiteCode
	Write-Host "2. Starting download and packaging phase"
	InitiateDownloads
	Write-Host "3. Script finished. Check the DriverAutomationTool log file for verbose output"
}

# // =================== START DOWNLOAD JOBS ================ //
StartProcesses

# // =================== CLEANUP TASKS ================ //

Write-CMLogEntry -Value "======== Cleaning Up Temporary Files ========" -Severity 1
Write-CMLogEntry -Value "Info: Removing Temp Folders & Source XML/CAB Files" -Severity 1
# Clean Up Temp Driver Folders
if ($global:TempDirectory -ne $null)
{
	Get-ChildItem -Path $global:TempDirectory -Recurse -Directory | Remove-Item -Recurse
	# Clean Up Temp XML & CAB Sources
	Get-ChildItem -Path $global:TempDirectory -Recurse -Filter *.xml -File | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force
}