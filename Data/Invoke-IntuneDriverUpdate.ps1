# // =================== GLOBAL VARIABLES ====================== //

$TempLocation = "C:\SCConfigmgr"

# Set Temp & Log Location
[string]$TempDirectory = Join-Path $TempLocation "\Temp"
[string]$LogDirectory = Join-Path $TempLocation "\Logs"

# Create Temp Folder 
if ((Test-Path -Path $TempDirectory) -eq $false) {
	New-Item -Path $TempDirectory -ItemType Dir
}

# Create Logs Folder 
if ((Test-Path -Path $LogDirectory) -eq $false) {
	New-Item -Path $LogDirectory -ItemType Dir
}

# Create Settings Folder 
if ((Test-Path -Path $global:SettingsDirectory) -eq $false) {
	New-Item -Path $global:SettingsDirectory -ItemType Dir
}

# Logging Function
function global:Write-CMLogEntry {
	param (
		[parameter(Mandatory = $true, HelpMessage = "Value added to the log file.")]
		[ValidateNotNullOrEmpty()]
		[string]
		$Value,
		[parameter(Mandatory = $true, HelpMessage = "Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
		[ValidateNotNullOrEmpty()]
		[ValidateSet("1", "2", "3")]
		[string]
		$Severity,
		[parameter(Mandatory = $false, HelpMessage = "Name of the log file that the entry will written to.")]
		[ValidateNotNullOrEmpty()]
		[string]
		$FileName = "Invoke-IntuneDriverUpdate.log",
		[parameter(Mandatory = $false, HelpMessage = "Variable for skipping verbose output to the GUI.")]
		[ValidateNotNullOrEmpty()]
		[boolean]
		$SkipGuiLog
	)
	# Determine log file location
	$LogFilePath = Join-Path -Path $LogDirectory -ChildPath $FileName
	
	# Construct time stamp for log entry
	$Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
	
	# Construct date for log entry
	$Date = (Get-Date -Format "MM-dd-yyyy")
	
	# Construct context for log entry
	$Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
	
	# Construct final log entry
	$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""DriverAutomationTool"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
	
	# Add value to log file
	try {
		Add-Content -Value $LogText -LiteralPath $LogFilePath -ErrorAction Stop
	}
	catch [System.Exception] {
		Write-Warning -Message "Unable to append log entry to DriverAutomationTool.log file. Error message: $($_.Exception.Message)"
	}
}

# Script Build Numbers
$ScriptRelease = "1.0.0"
$ScriptBuildDate = "2017-12-01"
$NewRelease = (Invoke-WebRequest -Uri "http://www.scconfigmgr.com/wp-content/uploads/tools/DriverAutomationToolRev.txt" -UseBasicParsing).Content
$ReleaseNotesURL = "http://www.scconfigmgr.com/wp-content/uploads/tools/DriverAutomationToolNotes.txt"

# Windows Version Hash Table
$WindowsBuildHashTable = @{`
	[int]1709   = "10.0.16299.15";`
	[int]1703 = "10.0.15063.0";`
	[int]1607 = "10.0.14393.0";`
};


# // =================== DELL VARIABLES ================ //

# Define Dell Download Sources
$DellDownloadList = "http://downloads.dell.com/published/Pages/index.html"
$DellDownloadBase = "http://downloads.dell.com"
$DellDriverListURL = "http://en.community.dell.com/techcenter/enterprise-client/w/wiki/2065.dell-command-deploy-driver-packs-for-enterprise-client-os-deployment"
$DellBaseURL = "http://en.community.dell.com"

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
$DellCatalogXML = $null
$DellModelXML = $null
$DellModelCabFiles = $null

# // =================== HP VARIABLES ================ //

# Define HP Download Sources
$HPXMLCabinetSource = "http://ftp.hp.com/pub/caps-softpaq/cmit/HPClientDriverPackCatalog.cab"
$HPSoftPaqSource = "http://ftp.hp.com/pub/softpaq/"
$HPPlatFormList = "http://ftp.hp.com/pub/caps-softpaq/cmit/imagepal/ref/platformList.cab"

# Define HP Cabinet/XL Names and Paths
$HPCabFile = [string]($HPXMLCabinetSource | Split-Path -Leaf)
$HPXMLFile = $HPCabFile.Trim(".cab")
$HPXMLFile = $HPXMLFile + ".xml"
$HPPlatformCabFile = [string]($HPPlatFormList | Split-Path -Leaf)
$HPPlatformXMLFile = $HPPlatformCabFile.Trim(".cab")
$HPPlatformXMLFile = $HPPlatformXMLFile + ".xml"

# Define HP Global Variables
$global:HPModelSoftPaqs = $null
$global:HPModelXML = $null
$global:HPPlatformXML = $null

# // =================== LENOVO VARIABLES ================ //

# Define Lenovo Download Sources
$LenovoXMLSource = "https://download.lenovo.com/cdrt/td/catalog.xml"

# Define Lenovo Cabinet/XL Names and Paths
$LenovoXMLFile = [string]($LenovoXMLSource | Split-Path -Leaf)

# Define Lenovo Global Variables
$global:LenovoModelDrivers = $null
$global:LenovoModelXML = $null
$global:LenovoModelType = $null
$global:LenovoSystemSKU = $null

# // =================== MICROSOFT VARIABLES ================ //

# Define Microsoft Download Sources
$MicrosoftXMLSource = "http://www.scconfigmgr.com/wp-content/uploads/xml/downloadlinks.xml"

# // =================== COMMON VARIABLES ================ //

# ArrayList to store models in
$DellProducts = New-Object -TypeName System.Collections.ArrayList
$DellKnownProducts = New-Object -TypeName System.Collections.ArrayList
$HPProducts = New-Object -TypeName System.Collections.ArrayList
$HPKnownProducts = New-Object -TypeName System.Collections.ArrayList
$LenovoProducts = New-Object -TypeName System.Collections.ArrayList
$LenovoKnownProducts = New-Object -TypeName System.Collections.ArrayList
$MicrosoftProducts = New-Object -TypeName System.Collections.ArrayList

# Determine manufacturer
$ComputerManufacturer = (Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Manufacturer).Trim()
Write-CMLogEntry -Value "Manufacturer determined as: $($ComputerManufacturer)" -Severity 1

# Determine manufacturer name and hardware information
switch -Wildcard ($ComputerManufacturer) {
	"*Microsoft*" {
		$ComputerManufacturer = "Microsoft"
		$ComputerModel = Get-WmiObject -Namespace root\wmi -Class MS_SystemInformation | Select-Object -ExpandProperty SystemSKU
	}
	"*HP*" {
		$ComputerManufacturer = "Hewlett-Packard"
		$ComputerModel = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model
		$SystemSKU = (Get-CIMInstance -ClassName MS_SystemInformation -NameSpace root\WMI).BaseBoardProduct
	}
	"*Hewlett-Packard*" {
		$ComputerManufacturer = "Hewlett-Packard"
		$ComputerModel = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model
		$SystemSKU = (Get-CIMInstance -ClassName MS_SystemInformation -NameSpace root\WMI).BaseBoardProduct
	}
	"*Dell*" {
		$ComputerManufacturer = "Dell"
		$ComputerModel = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model
		$SystemSKU = (Get-CIMInstance -ClassName MS_SystemInformation -NameSpace root\WMI).SystemSku
	}
	"*Lenovo*" {
		$ComputerManufacturer = "Lenovo"
		$ComputerModel = Get-WmiObject -Class Win32_ComputerSystemProduct | Select-Object -ExpandProperty Version
		$SystemSKU = ((Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model).SubString(0, 4)).Trim()
	}
}
Write-CMLogEntry -Value "Computer model determined as: $($ComputerModel)" -Severity 1

if (-not [string]::IsNullOrEmpty($SystemSKU)) {
	Write-CMLogEntry -Value "Computer SKU determined as: $($SystemSKU)" -Severity 1
}

# Get operating system name from version
switch -wildcard (Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty Version) {
	"10.0*" {
		$OSName = "Windows 10"
	}
	"6.3*" {
		$OSName = "Windows 8.1"
	}
	"6.1*" {
		$OSName = "Windows 7"
	}
}
Write-CMLogEntry -Value "Operating system determined as: $OSName" -Severity 1

$OSArchitecture = (Get-CimInstance Win32_operatingsystem).OSArchitecture
Write-CMLogEntry -Value "Architecture determined as: $OSArchitecture" -Severity 1

$WindowsVersion = ($OSName).Split(" ")[1]

function DownloadDriverList {
	global:Write-CMLogEntry -Value "======== Download Model Link Information ========" -Severity 1
	if ($ComputerManufacturer -eq "Hewlett-Packard") {
		if ((Test-Path -Path $TempDirectory\$HPCabFile) -eq $false) {
			global:Write-CMLogEntry -Value "======== Downloading HP Product List ========" -Severity 1
			# Download HP Model Cabinet File
			global:Write-CMLogEntry -Value "Info: Downloading HP driver pack cabinet file from $HPXMLCabinetSource" -Severity 1
			try {
				Start-BitsTransfer -Source $HPXMLCabinetSource -Destination $TempDirectory
								# Expand Cabinet File
				global:Write-CMLogEntry -Value "Info: Expanding HP driver pack cabinet file: $HPXMLFile" -Severity 1
				Expand "$TempDirectory\$HPCabFile" -F:* "$TempDirectory\$HPXMLFile"
			}
			catch {
				global:Write-CMLogEntry -Value "Error: $($_.Exception.Message)" -Severity 3
			}
		}
		# Read XML File
		if ($global:HPModelSoftPaqs -eq $null) {
			global:Write-CMLogEntry -Value "Info: Reading driver pack XML file - $TempDirectory\$HPXMLFile" -Severity 1
			[xml]$global:HPModelXML = Get-Content -Path $TempDirectory\$HPXMLFile
			# Set XML Object
			$global:HPModelXML.GetType().FullName
			$global:HPModelSoftPaqs = $HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
		}
		# Find Models Contained Within Downloaded XML
		if ($OSName -eq "Windows 10*") {
			# Windows 10 build query
			global:Write-CMLogEntry -Value "Info: Searching HP XML with OS variables - Windows*$(($OSComboBox.Text).split(' ')[1])*$(($ArchitectureComboxBox.Text).Split(' ')[0])*$((($OSComboBox.Text).split(' ')[2]).Trim())*" -Severity 1
			$HPModels = $global:HPModelSoftPaqs | Where-Object {
				($_.OSName -like "Windows*$(($OSComboBox.Text).split(' ')[1])*$(($ArchitectureComboxBox.Text).Split(' ')[0])*$((($OSComboBox.Text).split(' ')[2]).Trim())*")
			} | Select-Object SystemName
		}
		else {
			# Legacy Windows version query
			global:Write-CMLogEntry -Value "Info: Searching HP XML with OS variables - Windows*$(($OSComboBox.Text).split(' ')[1])*$(($ArchitectureComboxBox.Text).Split(' ')[0])*" -Severity 1
			$HPModels = $global:HPModelSoftPaqs | Where-Object {
				($_.OSName -like "Windows*$(($OSComboBox.Text).split(' ')[1])*$(($ArchitectureComboxBox.Text).Split(' ')[0])*")
			} | Select-Object SystemName
		}
		
		if (($HPModels).Count -gt "0") {
			global:Write-CMLogEntry -Value "Info: Found $(($HPModels).count) HP Model driver packs for $($OSComboBox.text) $($ArchitectureComboxBox.text)" -Severity 1
		}
		else {
			global:Write-CMLogEntry -Value "Info: No HP Models Found. If you are using a proxy server please specify the proxy in the Proxy Server Settings tab." -Severity 2
		}
	}
	if ($ComputerManufacturer -eq "Dell") {
		if ((Test-Path -Path $TempDirectory\$DellCabFile) -eq $false) {
			global:Write-CMLogEntry -Value "Info: Downloading Dell product list" -Severity 1
			global:Write-CMLogEntry -Value "Info: Downloading Dell driver pack cabinet file from $DellXMLCabinetSource" -Severity 1
			# Download Dell Model Cabinet File
			try {
				Start-BitsTransfer -Source $DellXMLCabinetSource -Destination $TempDirectory				
				# Expand Cabinet File
				global:Write-CMLogEntry -Value "Info: Expanding Dell driver pack cabinet file: $DellXMLFile" -Severity 1
				Expand "$TempDirectory\$DellCabFile" -F:* "$TempDirectory\$DellXMLFile"
			}
			catch {
				global:Write-CMLogEntry -Value "Error: $($_.Exception.Message)" -Severity 3
			}
		}		
		if ($DellModelXML -eq $null) {
			# Read XML File
			global:Write-CMLogEntry -Value "Info: Reading driver pack XML file - $TempDirectory\$DellXMLFile" -Severity 1
			[xml]$DellModelXML = (Get-Content -Path $TempDirectory\$DellXMLFile)
			# Set XML Object
			$DellModelXML.GetType().FullName
		}
		
		$DellModelCabFiles = $DellModelXML.driverpackmanifest.driverpackage
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
	}
	if ($ComputerManufacturer -eq "Lenovo") {
		$LenovoProducts.Clear()
		if ($global:LenovoModelDrivers -eq $null) {
			try {
				if ($global:ProxySettingsSet -eq $true) {
					[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource @global:InvokeProxyOptions
				}
				else {
					[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource
				}
			}
			catch {
				global:Write-CMLogEntry -Value "Error: $($_.Exception.Message)" -Severity 3
			}
			
			# Read Web Site
			global:Write-CMLogEntry -Value "Info: Reading driver pack URL - $LenovoXMLSource" -Severity 1
			
			# Set XML Object
			$global:LenovoModelXML.GetType().FullName
			$global:LenovoModelDrivers = $global:LenovoModelXML.Products
		}
		# Find Models Contained Within Downloaded XML
		if ($OSComboBox.Text -eq "Windows 10") {
			$OSSelected = "Win10"
			$LenovoModels = ($global:LenovoModelDrivers).Product | Where-Object {
				($_.OS -like $OSSelected)
			}
		}
		if ($OSComboBox.Text -eq "Windows 8.1") {
			$OSSelected = "Win81"
			$LenovoModels = ($global:LenovoModelDrivers).Product | Where-Object {
				($_.OS -like $OSSelected)
			}
		}
		if ($OSComboBox.Text -eq "Windows 7") {
			$LenovoModels = ($global:LenovoModelDrivers).Product | Where-Object {
				($_.OS -like "*Win*$(($OSComboBox.Text).split(' ')[1])*$(($ArchitectureComboxBox.Text).Split(' ')[0])*")
			}
		}		
	}
	if ($ComputerManufacturer -eq "Microsoft") {
		$MicrosoftProducts.Clear()
		try {
			if ($global:ProxySettingsSet -eq $true) {
				
				[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource @global:InvokeProxyOptions
				[xml]$MicrosoftModelList = Invoke-WebRequest -Uri $MicrosoftXMLSource @global:InvokeProxyOptions
			}
			else {
				[xml]$MicrosoftModelList = Invoke-WebRequest -Uri $MicrosoftXMLSource
			}
		}
		catch {
			global:Write-CMLogEntry -Value "Error: $($_.Exception.Message)" -Severity 3
		}
		
		# Read Web Site
		global:Write-CMLogEntry -Value "Info: Reading Driver Pack URL - $MicrosoftXMLSource" -Severity 1
		
		# Find Models Contained Within Downloaded XML
		if ($OSComboBox.SelectedItem -eq "Windows 10") {
			$OSSelected = "Win10"
			$MicrosoftModels = ($MicrosoftModelList).Drivers.Model | Where-Object {
				($_.OSSupport.Name -like "*$OSSelected*")
			}
		}
		if ($OSComboBox.SelectedItem -eq "Windows 8.1") {
			$OSSelected = "Win81"
			$MicrosoftModels = ($MicrosoftModelList).Drivers.Model | Where-Object {
				($_.OSSupport.Name -like "*$OSSelected*")
			}
		}
		if ($OSComboBox.SelectedItem -eq "Windows 7") {
			$OSSelected = "Win7"
			$MicrosoftModels = ($MicrosoftModelList).Drivers.Model | Where-Object {
				($_.OSSupport.Name -like "*$OSSelected*")
			}
		}
	}
}

function FindLenovoDriver {
	
<#
 # This powershell file will extract the link for the specified driver pack or application
 # param $URI The string version of the URL
 # param $64bit A boolean to determine what version to pick if there are multiple
 # param $os A string containing 7, 8, or 10 depending on the os we are deploying 
 #           i.e. 7, Win7, Windows 7 etc are all valid os strings
 #>
	param (
		[parameter(Mandatory = $true, HelpMessage = "Provide the URL to parse.")]
		[ValidateNotNullOrEmpty()]
		[string]
		$URI,
		[parameter(Mandatory = $true, HelpMessage = "Specify the operating system.")]
		[ValidateNotNullOrEmpty()]
		[string]
		$OS,
		[string]
		$Architecture
	)
	
	#Case for direct link to a zip file
	if ($URI.EndsWith(".zip")) {
		return $URI
	}
	
	$err = @()
	
	#Get the content of the website
	try {
		if ($global:ProxySettingsSet -eq $true) {
			$html = Invoke-WebRequest –Uri $URI @global:InvokeProxyOptions
			# Fall back to using specified credentials
			if ($html -eq $null) {
				$html = Invoke-WebRequest –Uri $URI @global:InvokeProxyOptions
			}
		}
		else {
			$html = Invoke-WebRequest –Uri $URI
		}
	}
	catch {
		global:Write-CMLogEntry -Value "Error: $($_.Exception.Message)" -Severity 3
	}
	
	#Create an array to hold all the links to exe files
	$Links = @()
	$Links.Clear()
	
	#determine if the URL resolves to the old download location
	if ($URI -like "*olddownloads*") {
		#Quickly grab the links that end with exe
		$Links = (($html.Links | Where-Object {
					$_.href -like "*exe"
				}) | Where class -eq "downloadBtn").href
	}
	
	$Links = ((Select-string '(http[s]?)(:\/\/)([^\s,]+.exe)(?=")' -InputObject ($html).Rawcontent -AllMatches).Matches.Value)
	
	if ($Links.Count -eq 0) {
		return $null
	}
	
	# Switch OS architecture
	switch -wildcard ($Architecture) {
		"*64*" {
			$Architecture = "64"
		}
		"*86*" {
			$Architecture = "32"
		}
	}
	
	#if there are multiple links then narrow down to the proper arc and os (if needed)
	if ($Links.Count -gt 0) {
		#Second array of links to hold only the ones we want to target
		$MatchingLink = @()
		$MatchingLink.clear()
		foreach ($Link in $Links) {
			if ($Link -like "*w$($OS)$($Architecture)_*" -or $Link -like "*w$($OS)_$($Architecture)*") {
				$MatchingLink += $Link
			}
		}
	}
	
	if ($MatchingLink -ne $null) {
		return $MatchingLink
	}
	else {
		return "badLink"
	}
}

function Get-RedirectedUrl {
	Param (
		[Parameter(Mandatory = $true)]
		[String]
		$URL
	)
	
	$Request = [System.Net.WebRequest]::Create($URL)
	$Request.AllowAutoRedirect = $false
	$Request.Timeout = 3000
	$Response = $Request.GetResponse()
	
	if ($Response.ResponseUri) {
		$Response.GetResponseHeader("Location")
	}
	$Response.Close()
}

function LenovoModelTypeFinder {
	param (
		[parameter(Mandatory = $false, HelpMessage = "Enter Lenovo model to query")]
		[string]
		$ComputerModel,
		[parameter(Mandatory = $false, HelpMessage = "Enter Operating System")]
		[string]
		$OS,
		[parameter(Mandatory = $false, HelpMessage = "Enter Lenovo model type to query")]
		[string]
		$ComputerModelType
	)
	try {
		if ($global:LenovoModelDrivers -eq $null) {
			if ($global:ProxySettingsSet -eq $true) {
				[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource @global:InvokeProxyOptions
			}
			else {
				[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource
			}
			
			# Read Web Site
			global:Write-CMLogEntry -Value "Info: Reading driver pack URL - $LenovoXMLSource" -Severity 1
			
			# Set XML Object
			$global:LenovoModelXML.GetType().FullName
			$global:LenovoModelDrivers = $global:LenovoModelXML.Products
		}
	}
	catch {
		global:Write-CMLogEntry -Value "Error: $($_.Exception.Message)" -Severity 3
	}
	
	if ($ComputerModel.Length -gt 0) {
		$global:LenovoModelType = ($global:LenovoModelDrivers.Product | Where-Object {
				$_.Queries.Version -match "$ComputerModel"
			}).Queries.Types | Select -ExpandProperty Type | Select -first 1
		$global:LenovoSystemSKU = ($global:LenovoModelDrivers.Product | Where-Object {
				$_.Queries.Version -match "$ComputerModel"
			}).Queries.Types | select -ExpandProperty Type | Get-Unique
	}
	
	if ($ComputerModelType.Length -gt 0) {
		$global:LenovoModelType = (($global:LenovoModelDrivers.Product.Queries) | Where-Object {
				($_.Types | Select -ExpandProperty Type) -match $ComputerModelType
			}).Version | Select -first 1
	}
	
	Return $global:LenovoModelType
}

function InitiateDownloads {
	
	$Product = "Intune"
	
	# Driver Download ScriptBlock
	$DriverDownloadJob = {
		Param ([string]
			$TempDirectory,
			[string]
			$ComputerModel,
			[string]
			$DriverCab,
			[string]
			$DriverDownloadURL
		)
		
		try {
			# Start Driver Download	
			Start-BitsTransfer -DisplayName "$ComputerModel-DriverDownload" -Source $DriverDownloadURL -Destination "$($TempDirectory + '\Driver Cab\' + $DriverCab)"
		}
		catch [System.Exception] {
			global:Write-CMLogEntry -Value "Error: $($_.Exception.Message)" -Severity 3
		}
	}
	
	global:Write-CMLogEntry -Value "======== Starting Download Processes ========" -Severity 1
	global:Write-CMLogEntry -Value "Info: Operating System specified: Windows $($WindowsVersion)" -Severity 1
	global:Write-CMLogEntry -Value "Info: Operating System architecture specified: $($Architecture)" -Severity 1

	# Operating System Version
	$OperatingSystem = ("Windows " + $($WindowsVersion))
	
	# Vendor Make
	#$ComputerManufacturer = $($ComputerModel).split(" ")[0]
	#$ComputerModel = $($ComputerModel).TrimStart("$ComputerManufacturer")
	$ComputerModel = $ComputerModel.Trim()
	
	# Lookup OS Build Number 
	if ($OSComboBox.Text -like "Windows 10 1*") {
		global:Write-CMLogEntry -Value "Info: Windows 10 build lookup required" -Severity 1
		# Get Windows Build Number From Version Hash Table
		$OSBuild = $WindowsBuildHashTable.Item([int]$OSVersion)
		global:Write-CMLogEntry -Value "Info: Windows 10 build $OSBuild identified for driver match" -Severity 1
	}
	else {
		$OSVersion = ($OSName).Split(' ')[1]
	}
	
	global:Write-CMLogEntry -Value "Info: Starting Download,Extract And Import Processes For $ComputerManufacturer Model: $($ComputerModel)" -Severity 1
	
	# =================== DEFINE VARIABLES =====================
	
	# Directory used for driver and BIOS downloads
	#$TempDirectory = ($RepositoryPath.Trimend("\") + "\$ComputerManufacturer\")
	
	# =================== VENDOR SPECIFIC UPDATES ====================
	
	if ($ComputerManufacturer -eq "Dell") {
		global:Write-CMLogEntry -Value "Info: Setting Dell variables" -Severity 1
		if ($DellModelCabFiles -eq $null) {
			[xml]$DellModelXML = Get-Content -Path $TempDirectory\$DellXMLFile
			# Set XML Object
			$DellModelXML.GetType().FullName
			$DellModelCabFiles = $DellModelXML.driverpackmanifest.driverpackage
		}
		$ComputerModelURL = $DellDownloadBase + "/" + ($DellModelCabFiles | Where-Object {
				((($_.SupportedOperatingSystems).OperatingSystem).osCode -like "*$WindowsVersion*") -and ($_.SupportedSystems.Brand.Model.Name -like "*$ComputerModel*")
			}).delta
		$ComputerModelURL = $ComputerModelURL.Replace("\", "/")
		$DriverDownload = $DellDownloadBase + "/" + ($DellModelCabFiles | Where-Object {
				((($_.SupportedOperatingSystems).OperatingSystem).osCode -like "*$WindowsVersion*") -and ($_.SupportedSystems.Brand.Model.Name -like "*$ComputerModel")
			}).path
		$DriverCab = (($DellModelCabFiles | Where-Object {
					((($_.SupportedOperatingSystems).OperatingSystem).osCode -like "*$WindowsVersion*") -and ($_.SupportedSystems.Brand.Model.Name -like "*$ComputerModel")
				}).path).Split("/") | select -Last 1
		$DriverRevision = (($DriverCab).Split("-")[2]).Trim(".cab")
		$DellSystemSKU = ($DellModelCabFiles.supportedsystems.brand.model | Where-Object {
				$_.Name -eq $ComputerModel
			} | Get-Unique).systemID
		if ($DellSystemSKU.count -gt 1) {
			$DellSystemSKU = [string]($DellSystemSKU -join ";")
		}
		global:Write-CMLogEntry -Value "Info: Dell System Model ID is : $DellSystemSKU" -Severity 1
	}
	if ($ComputerManufacturer -eq "HP") {
		global:Write-CMLogEntry -Value "Info: Setting HP variables" -Severity 1
		if ($global:HPModelSoftPaqs -eq $null) {
			[xml]$global:HPModelXML = Get-Content -Path $TempDirectory\$HPXMLFile
			# Set XML Object
			$global:HPModelXML.GetType().FullName
			$global:HPModelSoftPaqs = $global:HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
		}
		if ($OSComboBox.Text -like "Windows 10 1*") {
			$HPSoftPaqSummary = $global:HPModelSoftPaqs | Where-Object {
				($_.SystemName -like "*$ComputerModel*") -and ($_.OSName -like "Windows*$(($OSComboBox.Text).Split(' ')[1])*$(($ArchitectureComboxBox.Text).Trim(' bit'))*$((($OSComboBox.Text).Split(' ')[2]).Trim())*")
			} | Sort-Object -Descending | select -First 1
		}
		else {
			$HPSoftPaqSummary = $global:HPModelSoftPaqs | Where-Object {
				($_.SystemName -like "*$ComputerModel*") -and ($_.OSName -like "Windows*$(($OSComboBox.Text).Split(' ')[1])*$(($ArchitectureComboxBox.Text).Trim(' bit'))*")
			} | Sort-Object -Descending | select -First 1
		}
		$HPSoftPaq = $HPSoftPaqSummary.SoftPaqID
		$HPSoftPaqDetails = $global:HPModelXML.newdataset.hpclientdriverpackcatalog.softpaqlist.softpaq | Where-Object {
			$_.ID -eq "$HPSoftPaq"
		}
		$ComputerModelURL = $HPSoftPaqDetails.URL
		# Replace FTP for HTTP for Bits Transfer Job
		$DriverDownload = ($HPSoftPaqDetails.URL).TrimStart("ftp:")
		$DriverCab = $ComputerModelURL | Split-Path -Leaf
		$DriverRevision = "$($HPSoftPaqDetails.Version)"
		$HPSystemSKU = ($global:HPModelSoftPaqs | Where-Object {
				$_.SystemName -match $ComputerModel
			} | select -first 1).SystemID
		$HPSystemSKU = $HPSystemSKU.ToLower()
	}
	if ($ComputerManufacturer -eq "Lenovo") {
		global:Write-CMLogEntry -Value "Info: Setting Lenovo variables" -Severity 1
		LenovoModelTypeFinder -Model $ComputerModel -OS $OS
		global:Write-CMLogEntry -Value "Info: $ComputerManufacturer $ComputerModel matching model type: $global:LenovoModelType" -Severity 1 -SkipGuiLog $false
		
		if ($global:LenovoModelDrivers -ne $null) {
			[xml]$global:LenovoModelXML = (New-Object System.Net.WebClient).DownloadString("$LenovoXMLSource")
			# Set XML Object
			$global:LenovoModelXML.GetType().FullName
			$global:LenovoModelDrivers = $global:LenovoModelXML.Products
			$LenovoDriver = (($global:LenovoModelDrivers.Product | Where-Object {
						$_.Queries.Version -eq $ComputerModel
					}).driverPack | Where-Object {
					$_.id -eq "SCCM"
				})."#text"
		}
		if ($WindowsVersion -ne "7") {
			global:Write-CMLogEntry -Value "Info: Looking Up Lenovo $ComputerModel URL For Windows version win$(($WindowsVersion).Trim('.'))" -Severity 1
			$ComputerModelURL = (($global:LenovoModelDrivers.Product | Where-Object {
						($_.Queries.Version -eq "$ComputerModel") -and ($_.os -eq "win$(($WindowsVersion -replace '[.]', ''))")
					}).driverPack | Where-Object {
					$_.id -eq "SCCM"
				})."#text" | Select -First 1
		}
		else {
			global:Write-CMLogEntry -Value "Info: Looking Up Lenovo $ComputerModel URL For Windows version win$(($WindowsVersion).Trim('.'))" -Severity 1
			$ComputerModelURL = (($global:LenovoModelDrivers.Product | Where-Object {
						($_.Queries.Version -eq "$ComputerModel") -and ($_.os -eq "win$WindowsVersion$(($ArchitectureComboxBox.Text).Split(' ')[0])")
					}).driverPack | Where-Object {
					$_.id -eq "SCCM"
				})."#text" | Select -First 1
		}
		
		if ($DownloadType -ne "BIOS") {
			global:Write-CMLogEntry -Value "Info: Searching for Lenovo $ComputerModel exe file on $ComputerModelURL" -Severity 1
			global:Write-CMLogEntry -Value "Info: Passing through Windows version as $WindowsVersion" -Severity 1
			global:Write-CMLogEntry -Value "Info: Passing through Windows architecture as $Architecture" -Severity 1
			
			if ($global:ProxySettingsSet -eq $true) {
				$DriverDownload = FindLenovoDriver -URI $ComputerModelURL -os $WindowsVersion -Architecture $Architecture
			}
			else {
				$DriverDownload = FindLenovoDriver -URI $ComputerModelURL -os $WindowsVersion -Architecture $Architecture
			}
			
			If ($DriverDownload -ne $null) {
				$DriverCab = $DriverDownload | Split-Path -Leaf
				$DriverRevision = ($DriverCab.Split("_") | Select -Last 1).Trim(".exe")
			}
			else {
				global:Write-CMLogEntry -Value "Error: Unable to find driver for $ComputerManufacturer $ComputerModel" -Severity 1 -SkipGuiLog $false
			}
		}
	}
	if ($ComputerManufacturer -eq "Microsoft") {
		global:Write-CMLogEntry -Value "Info: Setting Microsoft variables" -Severity 1
		[xml]$MicrosoftModelXML = (New-Object System.Net.WebClient).DownloadString("$MicrosoftXMLSource")
		# Set XML Object
		$MicrosoftModelXML.GetType().FullName
		$MicrosoftModelDrivers = $MicrosoftModelXML.Drivers
		$ComputerModelURL = ((($MicrosoftModelDrivers.Model | Where-Object {
						($_.name -eq "$ComputerModel")
					}).OSSupport) | Where-Object {
				$_.Name -eq "win$(($WindowsVersion).Trim("."))"
			}).DownloadURL
		$MSSystemSKU = (($MicrosoftModelDrivers.model | Where-Object {
					$_.name -eq "$ComputerModel"
				}).wmi).name
		if ($ComputerModelURL -notmatch ".msi") {
			$DriverDownload = Get-RedirectedUrl -URL "$ComputerModelURL" -ErrorAction Continue -WarningAction Continue
		}
		else {
			$DriverDownload = $ComputerModelURL
		}
		$DriverCab = $DriverDownload | Split-Path -Leaf
		$DriverRevision = ($DriverCab.Split("_") | Select -Last 2).Trim(".msi")[0]
	}
	
	# Driver variables & switches
	$DriverSourceCab = ($TempDirectory + "\Driver Cab\" + $DriverCab)
	$DriverPackageDir = ($DriverCab).Substring(0, $DriverCab.length - 4)
	$DriverCabDest = $DriverPackageRoot + $DriverPackageDir
	
	# Cater for Dell driver packages (both x86 and x64 drivers contained within a single package)
	if ($ComputerManufacturer -eq "Dell") {
		$DriverExtractDest = ("$TempDirectory" + "\Driver Files")
		global:Write-CMLogEntry -Value "Info: Driver extract location set - $DriverExtractDest" -Severity 1
		$DriverPackageDest = ("$DriverPackageRoot" + "$ComputerModel" + "-" + "Windows$WindowsVersion-$Architecture-$DriverRevision")
		global:Write-CMLogEntry -Value "Info: Driver package location set - $DriverPackageDest" -Severity 1
		
	}
	else {
		If ($OSBuild -eq $null) {
			$DriverExtractDest = ("$TempDirectory" + $ComputerModel + "\" + "Windows$WindowsVersion-$Architecture-$DriverRevision")
			global:Write-CMLogEntry -Value "Info: Driver extract location set - $DriverExtractDest" -Severity 1
			$DriverPackageDest = ("$DriverPackageRoot" + "$ComputerModel" + "\" + "Windows$WindowsVersion-$Architecture-$DriverRevision")
			global:Write-CMLogEntry -Value "Info: Driver package location set - $DriverPackageDest" -Severity 1
		}
		else {
			$DriverExtractDest = ("$TempDirectory" + $ComputerModel + "\" + "Windows$WindowsVersion-$OSBuild-$Architecture-$DriverRevision")
			global:Write-CMLogEntry -Value "Info: Driver extract location set - $DriverExtractDest" -Severity 1
			$DriverPackageDest = ("$DriverPackageRoot" + "$ComputerModel" + "\" + "Windows$WindowsVersion-$OSBuild-$Architecture-$DriverRevision")
			global:Write-CMLogEntry -Value "Info: Driver package location set - $DriverPackageDest" -Severity 1
		}
		# Replace HP Model Slash
		$DriverExtractDest = $DriverExtractDest -replace '/', '-'
		$DriverPackageDest = $DriverPackageDest -replace '/', '-'
	}
	
	# =================== INITIATE DOWNLOADS ===================			
	
	global:Write-CMLogEntry -Value "======== $Product - $ComputerManufacturer $ComputerModel DRIVER PROCESSING STARTED ========" -Severity 1
	
	# =============== ConfigMgr Driver Cab Download =================				
	global:Write-CMLogEntry -Value "$($Product): Retrieving ConfigMgr driver pack site For $ComputerManufacturer $ComputerModel" -Severity 1
	global:Write-CMLogEntry -Value "$($Product): URL found: $ComputerModelURL" -Severity 1
	
	if (($ComputerModelURL -ne $null) -and ($DriverDownload -ne "badLink")) {
		# Cater for HP / Model Issue
		$ComputerModel = $ComputerModel -replace '/', '-'
		$ComputerModel = $ComputerModel.Trim()
		Set-Location -Path $TempDirectory
		# Check for destination directory, create if required and download the driver cab
		if ((Test-Path -Path $($TempDirectory + "\Driver Cab\" + $DriverCab)) -eq $false) {
			New-Item -ItemType Directory -Path $($TempDirectory + "\Driver Cab")
			global:Write-CMLogEntry -Value "$($Product): Downloading $DriverCab driver cab file" -Severity 1
			global:Write-CMLogEntry -Value "$($Product): Downloading from URL: $DriverDownload" -Severity 1
			
			Start-Job -Name "$ComputerModel-DriverDownload" -ScriptBlock $DriverDownloadJob -ArgumentList ($TempDirectory, $ComputerModel, $DriverCab, $DriverDownload)
			sleep -Seconds 5
			$BitsJob = Get-BitsTransfer | Where-Object {
				$_.DisplayName -match "$ComputerModel-DriverDownload"
			}
			while (($BitsJob).JobState -eq "Connecting") {
				global:Write-CMLogEntry -Value "$($Product): Establishing connection to $DriverDownload" -Severity 1
				sleep -seconds 30
			}
			while (($BitsJob).JobState -eq "Transferring") {
				if ($BitsJob.BytesTotal -ne $null) {
					$PercentComplete = [int](($BitsJob.BytesTransferred * 100)/$BitsJob.BytesTotal);
					global:Write-CMLogEntry -Value "$($Product): Downloaded $([int]((($BitsJob).BytesTransferred)/ 1MB)) MB of $([int]((($BitsJob).BytesTotal)/ 1MB)) MB ($PercentComplete%). Next update in 30 seconds." -Severity 1
					sleep -seconds 30
				}
				else {
					global:Write-CMLogEntry -Value "$($Product): Download issues detected. Cancelling download process" -Severity 2
					Get-BitsTransfer | Where-Object {
						$_.DisplayName -eq "$ComputerModel-DriverDownload"
					} | Remove-BitsTransfer
				}
			}
			Get-BitsTransfer | Where-Object {
				$_.DisplayName -eq "$ComputerModel-DriverDownload"
			} | Complete-BitsTransfer
			global:Write-CMLogEntry -Value "$($Product): Driver revision: $DriverRevision" -Severity 1
		}
		else {
			global:Write-CMLogEntry -Value "$($Product): Skipping $DriverCab. Driver pack already downloaded." -Severity 1
		}
		
		# Cater for HP / Model Issue
		$ComputerModel = $ComputerModel -replace '/', '-'
		
		if (((Test-Path -Path "$($TempDirectory + '\Driver Cab\' + $DriverCab)") -eq $true) -and ($DriverCab -ne $null)) {
			global:Write-CMLogEntry -Value "$($Product): $DriverCab File exists - Starting driver update process" -Severity 1
			# =============== Create Driver Package + Import Drivers =================
			
			if ((Test-Path -Path "$DriverExtractDest") -eq $false) {
				New-Item -ItemType Directory -Path "$($DriverExtractDest)"
			}
			if ((Get-ChildItem -Path "$DriverExtractDest" -Recurse -Filter *.inf -File).Count -eq 0) {
				global:Write-CMLogEntry -Value "==================== $PRODUCT DRIVER EXTRACT ====================" -Severity 1
				global:Write-CMLogEntry -Value "$($Product): Expanding driver CAB source file: $DriverCab" -Severity 1
				global:Write-CMLogEntry -Value "$($Product): Driver CAB destination directory: $DriverExtractDest" -Severity 1
				if ($ComputerManufacturer -eq "Dell") {
					global:Write-CMLogEntry -Value "$($Product): Extracting $ComputerManufacturer drivers to $DriverExtractDest" -Severity 1
					Expand "$DriverSourceCab" -F:* "$DriverExtractDest"
				}				
				if ($ComputerManufacturer -eq "HP") {
					# Driver Silent Extract Switches
					$HPTemp = $TempDirectory + "\" + $ComputerModel + "\Win" + $WindowsVersion + $Architecture
					$HPTemp = $HPTemp -replace '/', '-'
					
					# HP Work Around For Long Dir
					if ((($HPTemp).Split("-").Count) -gt "1") {
						$HPTemp = ($HPTemp).Split("-")[0]
					}
					
					global:Write-CMLogEntry -Value "$($Product): Extracting $ComputerManufacturer drivers to $HPTemp" -Severity 1
					$HPSilentSwitches = "-PDF -F" + "$HPTemp" + " -S -E"
					global:Write-CMLogEntry -Value "$($Product): Using $ComputerManufacturer silent switches: $HPSilentSwitches" -Severity 1
					Start-Process -FilePath "$($TempDirectory + '\Driver Cab\' + $DriverCab)" -ArgumentList $HPSilentSwitches -Verb RunAs
					$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
					
					# Wait for HP SoftPaq Process To Finish
					While ((Get-Process).name -contains $DriverProcess) {
						global:Write-CMLogEntry -Value "$($Product): Waiting for extract process (Process: $DriverProcess) to complete..  Next check in 30 seconds" -Severity 1
						sleep -Seconds 30
					}

				}				
				if ($ComputerManufacturer -eq "Lenovo") {
					# Driver Silent Extract Switches
					$LenovoSilentSwitches = "/VERYSILENT /DIR=" + '"' + $DriverExtractDest + '"' + ' /Extract="Yes"'
					global:Write-CMLogEntry -Value "$($Product): Using $ComputerManufacturer silent switches: $LenovoSilentSwitches" -Severity 1
					global:Write-CMLogEntry -Value "$($Product): Extracting $ComputerManufacturer drivers to $DriverExtractDest" -Severity 1
					Unblock-File -Path $($TempDirectory + '\Driver Cab\' + $DriverCab)
					Start-Process -FilePath "$($TempDirectory + '\Driver Cab\' + $DriverCab)" -ArgumentList $LenovoSilentSwitches -Verb RunAs
					$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
					# Wait for Lenovo Driver Process To Finish
					While ((Get-Process).name -contains $DriverProcess) {
						global:Write-CMLogEntry -Value "$($Product): Waiting for extract process (Process: $DriverProcess) to complete..  Next check in 30 seconds" -Severity 1
						sleep -seconds 30
					}
				}				
				if ($ComputerManufacturer -eq "Microsoft") {
					# Driver Silent Extract Switches
					$MicrosoftTemp = Join-Path -Path $TempDirectory -ChildPath "\$ComputerModel\Win$WindowsVersion$Architecture"
					$MicrosoftTemp = $MicrosoftTemp -replace '/', '-'
					
					# Driver Silent Extract Switches
					$MicrosoftSilentSwitches = "/a" + '"' + $($TempDirectory + "\Driver Cab\" + $DriverCab) + '"' + '/QN TARGETDIR="' + $MicrosoftTemp + '"'
					global:Write-CMLogEntry -Value "$($Product): Extracting $ComputerManufacturer drivers to $MicrosoftTemp" -Severity 1
					$DriverProcess = Start-Process msiexec.exe -ArgumentList $MicrosoftSilentSwitches -PassThru
					
					# Wait for Microsoft Driver Process To Finish
					While ((Get-Process).ID -eq $DriverProcess.ID) {
						global:Write-CMLogEntry -Value "$($Product): Waiting for extract process (Process ID: $($DriverProcess.ID)) to complete..  Next check in 30 seconds" -Severity 1
						sleep -seconds 30
					}
				}
			}
			else {
				global:Write-CMLogEntry -Value "Skipping. Drivers already extracted." -Severity 1
			}
		}
		else {
			global:Write-CMLogEntry -Value "$($Product): $DriverCab file download failed" -Severity 3
		}
	}
	elseif ($DriverDownload -eq "badLink") {
		global:Write-CMLogEntry -Value "$($Product): Operating system driver package download path not found.. Skipping $ComputerModel" -Severity 3
	}
	else {
		global:Write-CMLogEntry -Value "$($Product): Driver package not found for $ComputerModel running Windows $WindowsVersion $Architecture. Skipping $ComputerModel" -Severity 2
	}
	global:Write-CMLogEntry -Value "======== $PRODUCT - $ComputerManufacturer $ComputerModel DRIVER PROCESSING FINISHED ========" -Severity 1
	
	
	if ($ValidationErrors -eq 0) {
		
	}
	if ($ValidationErrors -gt 0) {
		global:Write-CMLogEntry -Value "======== Validation Error(s) ========" -Severity 3
		global:Write-CMLogEntry -Value "Validation errors have occurred. Please review the log." -Severity 3
	}
}

function Update-Drivers {
	$DriverPackagePath = Join-Path $TempDirectory "\Driver Files" 
	Write-CMLogEntry -Value "Starting driver installation process" -Severity 1
	Write-CMLogEntry -Value "Reading drivers from $DriverPackagePath" -Severity 1
	# Apply driver maintenance package
	try {
		if ((Get-ChildItem -Path $DriverPackagePath -Filter *.inf -Recurse).count -gt 0) {
			Get-ChildItem -Path $DriverPackagePath -Filter *.inf -Recurse | ForEach-Object {
				pnputil /add-driver $_.FullName /install
			} | Out-File -FilePath (Join-Path -Path $LogDirectory -ChildPath Run-IntuneDriverUpdate.log) -Force
			Write-CMLogEntry -Value "Driver installation complete. Restart required" -Severity 1; exit 0
		}
		else {
			Write-CMLogEntry -Value "No driver inf files found in $DriverPackagePath." -Severity 3; exit 1
		}
	}
	catch [System.Exception] {
		Write-CMLogEntry -Value "An error occurred while attempting to apply the driver maintenance package. Error message: $($_.Exception.Message)" -Severity 3; exit 1
	}
	Write-CMLogEntry -Value "Finished driver maintenance." -Severity 1
	Return $LastExitCode
}

DownloadDriverList

InitiateDownloads

Update-Drivers