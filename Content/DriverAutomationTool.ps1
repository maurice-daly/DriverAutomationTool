<#
.SYNOPSIS
    Driver Automation GUI Tool for Dell,HP,Lenovo and Microsoft systems
.DESCRIPTION
	This script allows you to automate the process of keeping your Dell, Lenovo
	and HP drives packages up to date. The script reads the Dell, Lenovo and HP
	SCCM driver pack site for models you have specified and then downloads
	the corresponding latest driver packs and BIOS updates.
.NOTES
    FileName:    DriverDownloadTool.ps1
	Blog: 		 https://www.scconfigmgr.com
    Author:      Maurice Daly
    Twitter:     @Modaly_IT
    Created:     2017-01-01
    Updated:     2020-06-28
    
    Version history:
	6.0.0 - (2018-03-29)	New verison. Graphical redesign, improved layout, HP individual driver downloads
	6.0.1 - (2018-03-30)	Model matching fix
	6.0.2 - (2018-04-03)	Package storage destination browse button fix
							Duplicate DP/DPG fix
	6.0.3 - (2018-04-06)	A couple of more code tweaks and fixes
	6.0.4 - (2018-04-10)	Fix for Dell system links not being found for some models when downloading BIOS 
							or driver packages.
							DP & DPG's datagrid will now clear on each detection
							Added the ability to provide a custom packages root folder structure or drop all
							packages into the root folder
	6.0.5 - (2018-04-25)	HP model matching logic updated
							Custom packaging updated
	6.0.6 - (2018-05-01)	Added support for Windows 10 build 1803 (HP)
	6.0.7 - (2018-05-28)	Fix for HP driver / firmware catalogue - now single extract of the contained XML
							Removed OS informationin BIOS packages description
							Added Windows 10 build version to HP packages created via the custom package function 
	6.0.8 - (2018-06-06)    HP SoftPaq packaging code changes. Fix for HP 1803 downloads and catalogue XML issuess. 
							SCCM custom folder code optimisation. 
							Bits enabled by default, can be disabled by setting the option manually and then closing 
							the GUI to commit the save. 
							Additional error handling.	
	6.0.9 - (2018-06-19)	Lenovo model lookup failure fix
							Lenovo Windows 10 download matching workaround. Current download will use latest Windows 10 build
							download link until build numbers are available in the XML
							Data grid updates for both Models and Package Management sections to clearer highlight selected values 
	6.0.9 - HF -(2018-08-02)	Hotfix for HP downloads
	6.1.3 - (2018-10-22)	Resolved issue with Bits-Trasnfer module not loading on Windows Server 2012 R2
							TLS set to 1.2
	6.1.4 - (2018-12-21)	Improved GUI response for make and OS selections
							Fix for some Dell models not finding the BIOS download link URL
							Added additional MDT driver path options
	6.1.5 - (2019-01-23)	HP BIOS download fix
							Added move to Windows 10 1809 build in package management	
							Manufacturer correction for Microsoft custom packages
	6.1.6 - (2019-02-22)	Fix: Reset tool form issues resolved
							Fix: Logging timezone issues resolved
							Fix: Source package clean up issues resolved
							Additional checking for MDT and ConfigMgr platforms
							Removal of legacy code
	6.1.7 - (2019-03-04)	Fix: Condition whereby not all selected models are saved within the XML settings file	
	6.2.0 - (2019-04-29)	Now packaged as an MSI installer
							Scaling changed to DPI to support high DPI (4K) screens
							Added support for Windows 10 1903
							Added support for resizing of the tool (minimum size hard coded)
							Fix: Condition where model search would not become enabled without toggling of manufacturer values
	6.3.0 - (2019-07-22)	Added support for all Microsoft Surface models across Windows 10 builds
							Added support for seperately packaged driver and firmware for Microsoft Surface models
							Various bug fixes and code improvements
	6.3.1 - (2019-08-03)	Fixed issues with SKU value change causing download and packaging issues with HP & Lenovo packages
	6.4.0 - (2019-12-02)	Added support for Windows 10 1909
							Removed support for Surface firmware packages
							Fixed Surface driver extraction issues due to external formatting change
							Fixed Dell 2-in-1 driver version issues
							Fixed removal of superseded versions and content source clean up
							Added improved logic for Microsoft Surface known model lookups
							Added additiona UI tweaks including model search now searching on return
							Locked down grid view colum resizing where required
	6.4.1 - (2019-12-04)	Fixed intermittent issues with Lenovo HTML / JavaScript parsing causing driver matching failures
							Fixed issues for Lenovo devices with long SKU listings with description change
							Fixed issues with custom package creation not displaying the SKU value correctly
							Tweak to MS model matching logic
	6.4.3 - (2020-31-01)	OOB release to fix changes in HP driver extraction
	6.4.4 - (2020-22-02)	Fixed issues with Lenovo driver extraction caused back packager change
							Fixed issues with driver imports using native driver packages
							Added support for zipped driver packages
	6.4.5 - (2020-09-03)	Updated Dell Flash64w download location in order to download latest available build
							Fixed UI elements not disabling in the admin control
							Fixed OS selection on initial load not disabling Dell if the previous OS selection was a Windows 10 
							build specific selection
							Updated Find Model button to find but not select, and addded Find + Select button
	6.4.6 - (2020-18-03)	Fixed Lenovo download link logic and added further output
							Updated package creation for all packages just to include the SKU/BaseBoard values
							Updated link within the tool to GitHub as Technet is being retired
							Updated custom package creation to include Windows 10 1909	
	6.4.6 - (2020-28-06)	Added support for Windwos 10 2004
							Added support for HP SoftPaq creation and updated UI to select available SoftPaqs per models	
							Added support for creation of 7zip driver packages
							Added support for XML based modern driver and BIOS management solutions
							Faster UI and XML handling
							Updated Lenovo XML source
	#>
param (
	[parameter(Position = 0, HelpMessage = "Option for preventing XML settings output")]
	[ValidateSet($false, $true)]
	[string]$NoXMLOutput = $false,
	[parameter(Position = 0, HelpMessage = "Option for preventing XML settings output")]
	[ValidateSet($false, $true)]
	[string]$RunSilent = $false,
	[parameter(Position = 0, HelpMessage = "Option for running locked down tabs")]
	[ValidateSet($false, $true)]
	[string]$OptionLocked = $false
)
#region Source: Startup.pss
#----------------------------------------------
#region Import Assemblies
#----------------------------------------------
[void][Reflection.Assembly]::Load('System.Windows.Forms, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')
[void][Reflection.Assembly]::Load('System.Data, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')
[void][Reflection.Assembly]::Load('System.Drawing, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a')
[void][Reflection.Assembly]::Load('System.DirectoryServices, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a')
#endregion Import Assemblies

# Pass through Params
$global:NoXMLOutput = $NoXMLOutput
$global:RunSilent = $RunSilent
$global:OptionLocked = $OptionLocked

# Import required PS modules
Import-Module -Name BitsTransfer -Verbose

function Main {
	Param ([String]$Commandline)

	if ((Show-MainForm_psf) -eq 'OK')
	{
		
	}	
	$script:ExitCode = 0 #Set the exit code for the Packager
}
#endregion Source: Startup.pss

#region Source: MainForm.psf
function Show-MainForm_psf
{
	#----------------------------------------------
	#region Import the Assemblies
	#----------------------------------------------
	[void][reflection.assembly]::Load('System.Windows.Forms, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')
	[void][reflection.assembly]::Load('System.Data, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')
	[void][reflection.assembly]::Load('System.Drawing, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a')
	[void][reflection.assembly]::Load('System.DirectoryServices, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a')
	#endregion Import Assemblies

	#----------------------------------------------
	#region Define SAPIEN Types
	#----------------------------------------------
	try{
		[ProgressBarOverlay] | Out-Null
	}
	catch
	{
        
		Add-Type -ReferencedAssemblies ('System.Windows.Forms', 'System.Drawing') -TypeDefinition  @" 
		using System;
		using System.Windows.Forms;
		using System.Drawing;
        namespace SAPIENTypes
        {
		    public class ProgressBarOverlay : System.Windows.Forms.ProgressBar
	        {
                public ProgressBarOverlay() : base() { SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true); }
	            protected override void WndProc(ref Message m)
	            { 
	                base.WndProc(ref m);
	                if (m.Msg == 0x000F)// WM_PAINT
	                {
	                    if (Style != System.Windows.Forms.ProgressBarStyle.Marquee || !string.IsNullOrEmpty(this.Text))
                        {
                            using (Graphics g = this.CreateGraphics())
                            {
                                using (StringFormat stringFormat = new StringFormat(StringFormatFlags.NoWrap))
                                {
                                    stringFormat.Alignment = StringAlignment.Center;
                                    stringFormat.LineAlignment = StringAlignment.Center;
                                    if (!string.IsNullOrEmpty(this.Text))
                                        g.DrawString(this.Text, this.Font, Brushes.Black, this.ClientRectangle, stringFormat);
                                    else
                                    {
                                        int percent = (int)(((double)Value / (double)Maximum) * 100);
                                        g.DrawString(percent.ToString() + "%", this.Font, Brushes.Black, this.ClientRectangle, stringFormat);
                                    }
                                }
                            }
                        }
	                }
	            }
              
                public string TextOverlay
                {
                    get
                    {
                        return base.Text;
                    }
                    set
                    {
                        base.Text = value;
                        Invalidate();
                    }
                }
	        }
        }
"@ -IgnoreWarnings | Out-Null
	}
	try{
		[FolderBrowserModernDialog] | Out-Null
	}
	catch
	{
		Add-Type -ReferencedAssemblies ('System.Windows.Forms') -TypeDefinition  @" 
		using System;
		using System.Windows.Forms;
		using System.Reflection;

        namespace SAPIENTypes
        {
		    public class FolderBrowserModernDialog : System.Windows.Forms.CommonDialog
            {
                private System.Windows.Forms.OpenFileDialog fileDialog;
                public FolderBrowserModernDialog()
                {
                    fileDialog = new System.Windows.Forms.OpenFileDialog();
                    fileDialog.Filter = "Folders|\n";
                    fileDialog.AddExtension = false;
                    fileDialog.CheckFileExists = false;
                    fileDialog.DereferenceLinks = true;
                    fileDialog.Multiselect = false;
                    fileDialog.Title = "Select a folder";
                }

                public string Title
                {
                    get { return fileDialog.Title; }
                    set { fileDialog.Title = value; }
                }

                public string InitialDirectory
                {
                    get { return fileDialog.InitialDirectory; }
                    set { fileDialog.InitialDirectory = value; }
                }
                
                public string SelectedPath
                {
                    get { return fileDialog.FileName; }
                    set { fileDialog.FileName = value; }
                }

                object InvokeMethod(Type type, object obj, string method, object[] parameters)
                {
                    MethodInfo methInfo = type.GetMethod(method, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                    return methInfo.Invoke(obj, parameters);
                }

                bool ShowOriginalBrowserDialog(IntPtr hwndOwner)
                {
                    using(FolderBrowserDialog folderBrowserDialog = new FolderBrowserDialog())
                    {
                        folderBrowserDialog.Description = this.Title;
                        folderBrowserDialog.SelectedPath = !string.IsNullOrEmpty(this.SelectedPath) ? this.SelectedPath : this.InitialDirectory;
                        folderBrowserDialog.ShowNewFolderButton = false;
                        if (folderBrowserDialog.ShowDialog() == DialogResult.OK)
                        {
                            fileDialog.FileName = folderBrowserDialog.SelectedPath;
                            return true;
                        }
                        return false;
                    }
                }

                protected override bool RunDialog(IntPtr hwndOwner)
                {
                    if (Environment.OSVersion.Version.Major >= 6)
                    {      
                        try
                        {
                            bool flag = false;
                            System.Reflection.Assembly assembly = Assembly.Load("System.Windows.Forms, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089");
                            Type typeIFileDialog = assembly.GetType("System.Windows.Forms.FileDialogNative").GetNestedType("IFileDialog", BindingFlags.NonPublic);
                            uint num = 0;
                            object dialog = InvokeMethod(fileDialog.GetType(), fileDialog, "CreateVistaDialog", null);
                            InvokeMethod(fileDialog.GetType(), fileDialog, "OnBeforeVistaDialog", new object[] { dialog });
                            uint options = (uint)InvokeMethod(typeof(System.Windows.Forms.FileDialog), fileDialog, "GetOptions", null) | (uint)0x20;
                            InvokeMethod(typeIFileDialog, dialog, "SetOptions", new object[] { options });
                            Type vistaDialogEventsType = assembly.GetType("System.Windows.Forms.FileDialog").GetNestedType("VistaDialogEvents", BindingFlags.NonPublic);
                            object pfde = Activator.CreateInstance(vistaDialogEventsType, fileDialog);
                            object[] parameters = new object[] { pfde, num };
                            InvokeMethod(typeIFileDialog, dialog, "Advise", parameters);
                            num = (uint)parameters[1];
                            try
                            {
                                int num2 = (int)InvokeMethod(typeIFileDialog, dialog, "Show", new object[] { hwndOwner });
                                flag = 0 == num2;
                            }
                            finally
                            {
                                InvokeMethod(typeIFileDialog, dialog, "Unadvise", new object[] { num });
                                GC.KeepAlive(pfde);
                            }
                            return flag;
                        }
                        catch
                        {
                            return ShowOriginalBrowserDialog(hwndOwner);
                        }
                    }
                    else
                        return ShowOriginalBrowserDialog(hwndOwner);
                }

                public override void Reset()
                {
                    fileDialog.Reset();
                }
            }
       }
"@ -IgnoreWarnings | Out-Null
	}
	#endregion Define SAPIEN Types

	#----------------------------------------------
	#region Generated Form Objects
	#----------------------------------------------
	[System.Windows.Forms.Application]::EnableVisualStyles()
	$MainForm = New-Object 'System.Windows.Forms.Form'
	$LogoPanel = New-Object 'System.Windows.Forms.Panel'
	$AutomationLabel = New-Object 'System.Windows.Forms.Label'
	$MSEndpointMgrLogo = New-Object 'System.Windows.Forms.PictureBox'
	$DescriptionText = New-Object 'System.Windows.Forms.TextBox'
	$SelectionTabs = New-Object 'System.Windows.Forms.TabControl'
	$MakeModelTab = New-Object 'System.Windows.Forms.TabPage'
	$MakeModelIcon = New-Object 'System.Windows.Forms.PictureBox'
	$MakeModelTabLabel = New-Object 'System.Windows.Forms.Label'
	$PlatformPanel = New-Object 'System.Windows.Forms.Panel'
	$DriverAppTab = New-Object 'System.Windows.Forms.TabControl'
	$ModelDriverTab = New-Object 'System.Windows.Forms.TabPage'
	$FindModelSelect = New-Object 'System.Windows.Forms.Button'
	$SelectAll = New-Object 'System.Windows.Forms.Button'
	$XMLLoading = New-Object 'System.Windows.Forms.Panel'
	$XMLDownloadStatus = New-Object 'System.Windows.Forms.Label'
	$XMLLoadingLabel = New-Object 'System.Windows.Forms.Label'
	$ModelResults = New-Object 'System.Windows.Forms.Label'
	$ClearModelSelection = New-Object 'System.Windows.Forms.Button'
	$FindModel = New-Object 'System.Windows.Forms.Button'
	$labelSearchModels = New-Object 'System.Windows.Forms.Label'
	$ModelSearchText = New-Object 'System.Windows.Forms.TextBox'
	$MakeModelDataGrid = New-Object 'System.Windows.Forms.DataGridView'
	$OSGroup = New-Object 'System.Windows.Forms.GroupBox'
	$ArchitectureComboxBox = New-Object 'System.Windows.Forms.ComboBox'
	$OSComboBox = New-Object 'System.Windows.Forms.ComboBox'
	$ArchitectureCheckBox = New-Object 'System.Windows.Forms.Label'
	$OperatingSysLabel = New-Object 'System.Windows.Forms.Label'
	$DeploymentGroupBox = New-Object 'System.Windows.Forms.GroupBox'
	$DownloadComboBox = New-Object 'System.Windows.Forms.ComboBox'
	$PlatformComboBox = New-Object 'System.Windows.Forms.ComboBox'
	$SelectDeployLabel = New-Object 'System.Windows.Forms.Label'
	$DownloadTypeLabel = New-Object 'System.Windows.Forms.Label'
	$ManufacturerSelectionGroup = New-Object 'System.Windows.Forms.GroupBox'
	$FindModelsButton = New-Object 'System.Windows.Forms.Button'
	$MicrosoftCheckBox = New-Object 'System.Windows.Forms.CheckBox'
	$HPCheckBox = New-Object 'System.Windows.Forms.CheckBox'
	$LenovoCheckBox = New-Object 'System.Windows.Forms.CheckBox'
	$DellCheckBox = New-Object 'System.Windows.Forms.CheckBox'
	$OEMCatalogs = New-Object 'System.Windows.Forms.TabPage'
	$tabcontrol2 = New-Object 'System.Windows.Forms.TabControl'
	$HPCatalog = New-Object 'System.Windows.Forms.TabPage'
	$RefreshSoftPaqSelection = New-Object 'System.Windows.Forms.Button'
	$DownloadSoftPaqs = New-Object 'System.Windows.Forms.Button'
	$ResetSoftPaqSelection = New-Object 'System.Windows.Forms.Button'
	$SelectAllSoftPaqs = New-Object 'System.Windows.Forms.Button'
	$HPSoftPaqGridPopup = New-Object 'System.Windows.Forms.Panel'
	$HPSoftPaqGridStatus = New-Object 'System.Windows.Forms.Label'
	$HPSoftpaqGridNotice = New-Object 'System.Windows.Forms.Label'
	$labelModelFilter = New-Object 'System.Windows.Forms.Label'
	$HPCatalogModels = New-Object 'System.Windows.Forms.ComboBox'
	$SoftpaqResults = New-Object 'System.Windows.Forms.Label'
	$FindSoftPaq = New-Object 'System.Windows.Forms.Button'
	$SoftpaqSearchCatalog = New-Object 'System.Windows.Forms.Label'
	$HPSearchText = New-Object 'System.Windows.Forms.TextBox'
	$HPSoftpaqDataGrid = New-Object 'System.Windows.Forms.DataGridView'
	$picturebox3 = New-Object 'System.Windows.Forms.PictureBox'
	$OEMDriverLabel = New-Object 'System.Windows.Forms.Label'
	$CommonTab = New-Object 'System.Windows.Forms.TabPage'
	$tabcontrol1 = New-Object 'System.Windows.Forms.TabControl'
	$tabpage1 = New-Object 'System.Windows.Forms.TabPage'
	$StoageGroupBox = New-Object 'System.Windows.Forms.GroupBox'
	$textbox8 = New-Object 'System.Windows.Forms.TextBox'
	$textbox7 = New-Object 'System.Windows.Forms.TextBox'
	$StoragePathInstruction = New-Object 'System.Windows.Forms.TextBox'
	$DownloadLabel = New-Object 'System.Windows.Forms.Label'
	$DownloadBrowseButton = New-Object 'System.Windows.Forms.Button'
	$DownloadPathTextBox = New-Object 'System.Windows.Forms.TextBox'
	$tabpage2 = New-Object 'System.Windows.Forms.TabPage'
	$SchedulingGroupBox = New-Object 'System.Windows.Forms.GroupBox'
	$SchedulingInstruction = New-Object 'System.Windows.Forms.TextBox'
	$ScriptDirectoryBrowseButton = New-Object 'System.Windows.Forms.Button'
	$UsernameTextBox = New-Object 'System.Windows.Forms.TextBox'
	$TimeComboBox = New-Object 'System.Windows.Forms.ComboBox'
	$ScheduleJobButton = New-Object 'System.Windows.Forms.Button'
	$ScheduleUserName = New-Object 'System.Windows.Forms.Label'
	$SchedulePassword = New-Object 'System.Windows.Forms.Label'
	$PasswordTextBox = New-Object 'System.Windows.Forms.MaskedTextBox'
	$ScheduleLocation = New-Object 'System.Windows.Forms.Label'
	$ScheduleTime = New-Object 'System.Windows.Forms.Label'
	$ScriptLocation = New-Object 'System.Windows.Forms.TextBox'
	$ProxyGroupBox = New-Object 'System.Windows.Forms.GroupBox'
	$UseProxyServerCheckbox = New-Object 'System.Windows.Forms.CheckBox'
	$ProxyServerText = New-Object 'System.Windows.Forms.TextBox'
	$labelProxyServer = New-Object 'System.Windows.Forms.Label'
	$ProxyPswdInput = New-Object 'System.Windows.Forms.TextBox'
	$labelPassword = New-Object 'System.Windows.Forms.Label'
	$ProxyServerInput = New-Object 'System.Windows.Forms.TextBox'
	$labelUsername = New-Object 'System.Windows.Forms.Label'
	$ProxyUserInput = New-Object 'System.Windows.Forms.TextBox'
	$tabpage3 = New-Object 'System.Windows.Forms.TabPage'
	$AdminControlsInstruction = New-Object 'System.Windows.Forms.TextBox'
	$groupbox4 = New-Object 'System.Windows.Forms.GroupBox'
	$TabControlGroup = New-Object 'System.Windows.Forms.GroupBox'
	$textbox6 = New-Object 'System.Windows.Forms.TextBox'
	$HideCommonSettings = New-Object 'System.Windows.Forms.CheckBox'
	$HideCustomCreation = New-Object 'System.Windows.Forms.CheckBox'
	$HideConfigPkgMgmt = New-Object 'System.Windows.Forms.CheckBox'
	$HideWebService = New-Object 'System.Windows.Forms.CheckBox'
	$HideMDT = New-Object 'System.Windows.Forms.CheckBox'
	$picturebox2 = New-Object 'System.Windows.Forms.PictureBox'
	$labelCommonSettings = New-Object 'System.Windows.Forms.Label'
	$ConfigMgrTab = New-Object 'System.Windows.Forms.TabPage'
	$SettingsIcon = New-Object 'System.Windows.Forms.PictureBox'
	$labelConfigurationManager = New-Object 'System.Windows.Forms.Label'
	$SettingsTabs = New-Object 'System.Windows.Forms.TabControl'
	$ConfigMgrDPOptionsTab = New-Object 'System.Windows.Forms.TabPage'
	$PackageCreation = New-Object 'System.Windows.Forms.GroupBox'
	$textbox9 = New-Object 'System.Windows.Forms.TextBox'
	$CreateXMLLogicPackage = New-Object 'System.Windows.Forms.CheckBox'
	$ZipFormatLabel = New-Object 'System.Windows.Forms.Label'
	$CompressionType = New-Object 'System.Windows.Forms.ComboBox'
	$ZipCompressionText = New-Object 'System.Windows.Forms.TextBox'
	$ZipCompressionCheckBox = New-Object 'System.Windows.Forms.CheckBox'
	$CleanSourceText = New-Object 'System.Windows.Forms.TextBox'
	$RemoveDriverSourceCheckbox = New-Object 'System.Windows.Forms.CheckBox'
	$RemoveBIOSText = New-Object 'System.Windows.Forms.TextBox'
	$RemoveLegacyBIOSCheckbox = New-Object 'System.Windows.Forms.CheckBox'
	$CleanUpText = New-Object 'System.Windows.Forms.TextBox'
	$CleanUnusedCheckBox = New-Object 'System.Windows.Forms.CheckBox'
	$RemoveSuperText = New-Object 'System.Windows.Forms.TextBox'
	$RemoveLegacyDriverCheckbox = New-Object 'System.Windows.Forms.CheckBox'
	$PackageBrowseButton = New-Object 'System.Windows.Forms.Button'
	$PackagePathLabel = New-Object 'System.Windows.Forms.Label'
	$PackagePathTextBox = New-Object 'System.Windows.Forms.TextBox'
	$CustPackageDest = New-Object 'System.Windows.Forms.TextBox'
	$SpecifyCustomPath = New-Object 'System.Windows.Forms.CheckBox'
	$textbox4 = New-Object 'System.Windows.Forms.TextBox'
	$PackageRoot = New-Object 'System.Windows.Forms.CheckBox'
	$groupbox1 = New-Object 'System.Windows.Forms.GroupBox'
	$ConfigMgrImport = New-Object 'System.Windows.Forms.ComboBox'
	$labelSelectKnownModels = New-Object 'System.Windows.Forms.Label'
	$ConifgSiteInstruction = New-Object 'System.Windows.Forms.TextBox'
	$ConnectConfigMgrButton = New-Object 'System.Windows.Forms.Button'
	$SiteCodeText = New-Object 'System.Windows.Forms.TextBox'
	$SiteServerInput = New-Object 'System.Windows.Forms.TextBox'
	$SiteServerLabel = New-Object 'System.Windows.Forms.Label'
	$SiteCodeLabel = New-Object 'System.Windows.Forms.Label'
	$PackageOptionsTab = New-Object 'System.Windows.Forms.TabPage'
	$DPGroupBox = New-Object 'System.Windows.Forms.GroupBox'
	$EnableBinaryDifCheckBox = New-Object 'System.Windows.Forms.CheckBox'
	$PriorityLabel = New-Object 'System.Windows.Forms.Label'
	$DistributionPriorityCombo = New-Object 'System.Windows.Forms.ComboBox'
	$DPSelectionsTabs = New-Object 'System.Windows.Forms.TabControl'
	$DPointTab = New-Object 'System.Windows.Forms.TabPage'
	$DPGridView = New-Object 'System.Windows.Forms.DataGridView'
	$DPGroupTab = New-Object 'System.Windows.Forms.TabPage'
	$DPGGridView = New-Object 'System.Windows.Forms.DataGridView'
	$FallbackPkgGroup = New-Object 'System.Windows.Forms.GroupBox'
	$FallbackManufacturer = New-Object 'System.Windows.Forms.ComboBox'
	$ManufacturerLabel = New-Object 'System.Windows.Forms.Label'
	$FallbackDesc = New-Object 'System.Windows.Forms.TextBox'
	$FallbackArcCombo = New-Object 'System.Windows.Forms.ComboBox'
	$FallbackOSCombo = New-Object 'System.Windows.Forms.ComboBox'
	$ArchitectureLabel = New-Object 'System.Windows.Forms.Label'
	$OperatingSystemLabel = New-Object 'System.Windows.Forms.Label'
	$CreateFallbackButton = New-Object 'System.Windows.Forms.Button'
	$SettingsPanel = New-Object 'System.Windows.Forms.Panel'
	$IntuneTab = New-Object 'System.Windows.Forms.TabPage'
	$labelIntuneAzureADGraphAP = New-Object 'System.Windows.Forms.Label'
	$picturebox1 = New-Object 'System.Windows.Forms.PictureBox'
	$panel1 = New-Object 'System.Windows.Forms.Panel'
	$groupbox7 = New-Object 'System.Windows.Forms.GroupBox'
	$IntuneUniqueDeviceCount = New-Object 'System.Windows.Forms.Label'
	$IntuneUniqueCount = New-Object 'System.Windows.Forms.Label'
	$GraphAuthStatus = New-Object 'System.Windows.Forms.Label'
	$AADAppID = New-Object 'System.Windows.Forms.TextBox'
	$labelAuthenticationStatus = New-Object 'System.Windows.Forms.Label'
	$Win32BIOSCount = New-Object 'System.Windows.Forms.Label'
	$labelTenantName = New-Object 'System.Windows.Forms.Label'
	$labelBIOSPackageCount = New-Object 'System.Windows.Forms.Label'
	$labelAppID = New-Object 'System.Windows.Forms.Label'
	$Win32DriverCount = New-Object 'System.Windows.Forms.Label'
	$AADTenantName = New-Object 'System.Windows.Forms.TextBox'
	$labelDriverPackageCount = New-Object 'System.Windows.Forms.Label'
	$buttonConnectGraphAPI = New-Object 'System.Windows.Forms.Button'
	$labelAppSecret = New-Object 'System.Windows.Forms.Label'
	$IntuneDeviceCount = New-Object 'System.Windows.Forms.Label'
	$APPSecret = New-Object 'System.Windows.Forms.TextBox'
	$labelNumberOfManagedDevic = New-Object 'System.Windows.Forms.Label'
	$groupbox6 = New-Object 'System.Windows.Forms.GroupBox'
	$IntuneAppDataGrid = New-Object 'System.Windows.Forms.DataGridView'
	$groupbox5 = New-Object 'System.Windows.Forms.GroupBox'
	$RefreshIntuneModels = New-Object 'System.Windows.Forms.Button'
	$IntuneSelectKnownModels = New-Object 'System.Windows.Forms.Label'
	$checkboxRemoveUnusedDriverPa = New-Object 'System.Windows.Forms.CheckBox'
	$textbox1 = New-Object 'System.Windows.Forms.TextBox'
	$textbox3 = New-Object 'System.Windows.Forms.TextBox'
	$checkboxRemoveUnusedBIOSPack = New-Object 'System.Windows.Forms.CheckBox'
	$IntuneKnownModels = New-Object 'System.Windows.Forms.ComboBox'
	$MDTTab = New-Object 'System.Windows.Forms.TabPage'
	$MDTTabLabel = New-Object 'System.Windows.Forms.Label'
	$MDTSettingsIcon = New-Object 'System.Windows.Forms.PictureBox'
	$DeploymentShareGrid = New-Object 'System.Windows.Forms.DataGridView'
	$MDTSettingsPanel = New-Object 'System.Windows.Forms.Panel'
	$FolderStructureGroup = New-Object 'System.Windows.Forms.GroupBox'
	$MDTDriverStructureCombo = New-Object 'System.Windows.Forms.ComboBox'
	$TotalControlLabel = New-Object 'System.Windows.Forms.Label'
	$TotalControlExampleLabel = New-Object 'System.Windows.Forms.TextBox'
	$FolderStructureLabel = New-Object 'System.Windows.Forms.Label'
	$MDTScriptGroup = New-Object 'System.Windows.Forms.GroupBox'
	$MDTScriptTextBox = New-Object 'System.Windows.Forms.TextBox'
	$MDTLocationDesc = New-Object 'System.Windows.Forms.TextBox'
	$ImportMDTPSButton = New-Object 'System.Windows.Forms.Button'
	$ScriptLocationLabel = New-Object 'System.Windows.Forms.Label'
	$MDTScriptBrowseButton = New-Object 'System.Windows.Forms.Button'
	$ConfigMgrDriverTab = New-Object 'System.Windows.Forms.TabPage'
	$PkgMgmtTabLabel = New-Object 'System.Windows.Forms.Label'
	$PkgMgmtIcon = New-Object 'System.Windows.Forms.PictureBox'
	$PackageUpdatePanel = New-Object 'System.Windows.Forms.Panel'
	$PackageUpdateNotice = New-Object 'System.Windows.Forms.Label'
	$PackageGrid = New-Object 'System.Windows.Forms.DataGridView'
	$PackagePanel = New-Object 'System.Windows.Forms.Panel'
	$PackageTypeLabel = New-Object 'System.Windows.Forms.Label'
	$DeploymentStateCombo = New-Object 'System.Windows.Forms.ComboBox'
	$DeploymentStateLabel = New-Object 'System.Windows.Forms.Label'
	$SelectNoneButton = New-Object 'System.Windows.Forms.Button'
	$PackageTypeCombo = New-Object 'System.Windows.Forms.ComboBox'
	$SelectAllButton = New-Object 'System.Windows.Forms.Button'
	$ConfigMgrPkgActionCombo = New-Object 'System.Windows.Forms.ComboBox'
	$ActionLabel = New-Object 'System.Windows.Forms.Label'
	$ConfigWSDiagTab = New-Object 'System.Windows.Forms.TabPage'
	$WebDiagsTabLabel = New-Object 'System.Windows.Forms.Label'
	$WebDiagsIcon = New-Object 'System.Windows.Forms.PictureBox'
	$WebServiceDataGrid = New-Object 'System.Windows.Forms.DataGridView'
	$WebDiagsPanel = New-Object 'System.Windows.Forms.Panel'
	$ConfigMgrWebSvcLabel = New-Object 'System.Windows.Forms.Label'
	$WebServiceVersion = New-Object 'System.Windows.Forms.Label'
	$WebSvcDesc = New-Object 'System.Windows.Forms.TextBox'
	$WebServiceVersionLabel = New-Object 'System.Windows.Forms.Label'
	$ConnectWebServiceButton = New-Object 'System.Windows.Forms.Button'
	$WebServiceStatusDescription = New-Object 'System.Windows.Forms.Label'
	$SecretKey = New-Object 'System.Windows.Forms.TextBox'
	$ConfigMgrWebServuceULabel = New-Object 'System.Windows.Forms.Label'
	$StatusDescriptionLabel = New-Object 'System.Windows.Forms.Label'
	$SecretKeyLabel = New-Object 'System.Windows.Forms.Label'
	$StatusCodeLabel = New-Object 'System.Windows.Forms.Label'
	$ConfigMgrWebURL = New-Object 'System.Windows.Forms.TextBox'
	$BIOSPackageCount = New-Object 'System.Windows.Forms.Label'
	$WebServiceResponseTime = New-Object 'System.Windows.Forms.Label'
	$ResponseTimeLabel = New-Object 'System.Windows.Forms.Label'
	$DriverPackageCount = New-Object 'System.Windows.Forms.Label'
	$BIOSPackageCountLabel = New-Object 'System.Windows.Forms.Label'
	$WebServiceStatusCode = New-Object 'System.Windows.Forms.Label'
	$DriverPackageCountLabel = New-Object 'System.Windows.Forms.Label'
	$CustPkgTab = New-Object 'System.Windows.Forms.TabPage'
	$PkgImporting = New-Object 'System.Windows.Forms.Panel'
	$PkgImportingText = New-Object 'System.Windows.Forms.Label'
	$label1 = New-Object 'System.Windows.Forms.Label'
	$CustPkgIcon = New-Object 'System.Windows.Forms.PictureBox'
	$CustomPkgTabLabel = New-Object 'System.Windows.Forms.Label'
	$CustomPkgDataGrid = New-Object 'System.Windows.Forms.DataGridView'
	$CustomPkgPanel = New-Object 'System.Windows.Forms.Panel'
	$CustomPkgGroup = New-Object 'System.Windows.Forms.GroupBox'
	$CustomDeploymentLabel = New-Object 'System.Windows.Forms.Label'
	$CustomPkgPlatform = New-Object 'System.Windows.Forms.ComboBox'
	$groupbox2 = New-Object 'System.Windows.Forms.GroupBox'
	$QuerySystemButton = New-Object 'System.Windows.Forms.Button'
	$ImportExtractedDriveButton = New-Object 'System.Windows.Forms.Button'
	$CustomExtractButton = New-Object 'System.Windows.Forms.Button'
	$ImportCSVButton = New-Object 'System.Windows.Forms.Button'
	$CreatePackagesButton = New-Object 'System.Windows.Forms.Button'
	$LogTab = New-Object 'System.Windows.Forms.TabPage'
	$ProcessTabLabel = New-Object 'System.Windows.Forms.Label'
	$ProcessIcon = New-Object 'System.Windows.Forms.PictureBox'
	$LogPanel = New-Object 'System.Windows.Forms.Panel'
	$RemainingDownloads = New-Object 'System.Windows.Forms.Label'
	$labelRemainingDownloads = New-Object 'System.Windows.Forms.Label'
	$FileSize = New-Object 'System.Windows.Forms.Label'
	$labelFileSizeMB = New-Object 'System.Windows.Forms.Label'
	$CurrentDownload = New-Object 'System.Windows.Forms.RichTextBox'
	$richtextbox2 = New-Object 'System.Windows.Forms.RichTextBox'
	$ErrorsOccurred = New-Object 'System.Windows.Forms.Label'
	$TotalDownloads = New-Object 'System.Windows.Forms.Label'
	$JobStatus = New-Object 'System.Windows.Forms.Label'
	$ProgressListBox = New-Object 'System.Windows.Forms.ListBox'
	$labelWarningsErrors = New-Object 'System.Windows.Forms.Label'
	$labelSelectedDownloads = New-Object 'System.Windows.Forms.Label'
	$labelCurrentDownload = New-Object 'System.Windows.Forms.Label'
	$labelJobStatus = New-Object 'System.Windows.Forms.Label'
	$ProgressLabel = New-Object 'System.Windows.Forms.Label'
	$ModelProgressOverlay = New-Object 'SAPIENTypes.ProgressBarOverlay'
	$ProgressBar = New-Object 'System.Windows.Forms.ProgressBar'
	$AboutTab = New-Object 'System.Windows.Forms.TabPage'
	$AboutPanelRight = New-Object 'System.Windows.Forms.Panel'
	$richtextbox3 = New-Object 'System.Windows.Forms.RichTextBox'
	$MSTechnetSiteLaunchButton = New-Object 'System.Windows.Forms.Button'
	$ReleaseNotesText = New-Object 'System.Windows.Forms.RichTextBox'
	$AboutTabLabel = New-Object 'System.Windows.Forms.Label'
	$NewVersion = New-Object 'System.Windows.Forms.Label'
	$AboutIcon = New-Object 'System.Windows.Forms.PictureBox'
	$AboutPanelLeft = New-Object 'System.Windows.Forms.Panel'
	$ModernDriverDesc = New-Object 'System.Windows.Forms.RichTextBox'
	$richtextbox5 = New-Object 'System.Windows.Forms.RichTextBox'
	$ModernDriverLabel = New-Object 'System.Windows.Forms.RichTextBox'
	$AboutToolDesc = New-Object 'System.Windows.Forms.RichTextBox'
	$GitHubLaunchButton = New-Object 'System.Windows.Forms.Button'
	$NewVersionLabel = New-Object 'System.Windows.Forms.Label'
	$BuildDate = New-Object 'System.Windows.Forms.Label'
	$Version = New-Object 'System.Windows.Forms.Label'
	$lBuildDateLabel = New-Object 'System.Windows.Forms.Label'
	$VersionLabel = New-Object 'System.Windows.Forms.Label'
	$ResetDATSettings = New-Object 'System.Windows.Forms.Button'
	$StartDownloadButton = New-Object 'System.Windows.Forms.Button'
	$DownloadBrowseFolderDialogue = New-Object 'SAPIENTypes.FolderBrowserModernDialog'
	$PackageBrowseFolderDialogue = New-Object 'SAPIENTypes.FolderBrowserModernDialog'
	$ScriptBrowseFolderDialogue = New-Object 'SAPIENTypes.FolderBrowserModernDialog'
	$MDTScriptBrowse = New-Object 'SAPIENTypes.FolderBrowserModernDialog'
	$CustomDriverFolderDialogue = New-Object 'SAPIENTypes.FolderBrowserModernDialog'
	$WebServicePackageName = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$PackageVersionDetails = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$WebServicePackageID = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$Description = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$Path = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$Name = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$Select = New-Object 'System.Windows.Forms.DataGridViewCheckBoxColumn'
	$Date = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$PackageID = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$PackageVersion = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$PackageName = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$Selected = New-Object 'System.Windows.Forms.DataGridViewCheckBoxColumn'
	$checkboxUseAProxyServer = New-Object 'System.Windows.Forms.CheckBox'
	$CustomPackageBrowse = New-Object 'SAPIENTypes.FolderBrowserModernDialog'
	$Win32Package = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$PackageDetails = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$DPSelected = New-Object 'System.Windows.Forms.DataGridViewCheckBoxColumn'
	$DPName = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$DPGSelected = New-Object 'System.Windows.Forms.DataGridViewCheckBoxColumn'
	$DPGName = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$Make = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$Model = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$Baseboard = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$Platform = New-Object 'System.Windows.Forms.DataGridViewComboBoxColumn'
	$OperatingSystem = New-Object 'System.Windows.Forms.DataGridViewComboBoxColumn'
	$Architecture = New-Object 'System.Windows.Forms.DataGridViewComboBoxColumn'
	$Revision = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$SourceDirectory = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$Browse = New-Object 'System.Windows.Forms.DataGridViewButtonColumn'
	$ModelSelected = New-Object 'System.Windows.Forms.DataGridViewCheckBoxColumn'
	$Manufacturer = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$ModelName = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$WindowsVersion = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$WindowsArchitecture = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$KnownModel = New-Object 'System.Windows.Forms.DataGridViewImageColumn'
	$SearchResult = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$HPCatalogueSelected = New-Object 'System.Windows.Forms.DataGridViewCheckBoxColumn'
	$HPSoftPaqTitle = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$HPCatalogueDescription = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$SoftPaqVersion = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$Created = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$HPCatalogueSeverity = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$PackageCreated = New-Object 'System.Windows.Forms.DataGridViewImageColumn'
	$SoftPaqURL = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$SilentSetup = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$BaseBoardModels = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$SoftPaqMatch = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$SupportedBuild = New-Object 'System.Windows.Forms.DataGridViewTextBoxColumn'
	$InitialFormWindowState = New-Object 'System.Windows.Forms.FormWindowState'
	#endregion Generated Form Objects

	#----------------------------------------------
	# User Generated Script
	#----------------------------------------------
	$MainForm_Load = {
		
	
		
	}
	
	$MainForm_Shown = {
		
		# Sleep for UI rendering
		Start-Sleep -Milliseconds 750
		
		# Temp disable Intune functionality - OOB update for 6.4.3
		$SelectionTabs.TabPages["IntuneTab"].Enabled = $false
		$SelectionTabs.TabPages.Remove($IntuneTab)
		
		# Get Registry Stored Prferences
		Set-RegPreferences
		
		# Initialise Form
		global:Write-LogEntry -Value "======== INITIALISING LOG FILE & CHECKING PREREQUISITES ========" -Severity 1
		global:Write-LogEntry -Value "Info: Driver Automation Tool version - $ScriptRelease" -Severity 1
		global:Write-LogEntry -Value "Info: Log File Location - $LogDirectory" -Severity 1
		global:Write-LogEntry -Value "Info: Settings File Location - $SettingsDirectory" -Severity 1
		global:Write-LogEntry -Value "Info: Temp File Location - $TempDirectory" -Severity 1
		
		# Check for 7-Zip instllation
		Set-7ZipOptions
		
		# Check for PowerShell 5.0
		if ($PSVersionTable.PSVersion.Major -lt "5") {
			$PreRequisiteFailure = $true
			global:Write-LogEntry -Value "======== PREREQUISITE FAILURE ========" -Severity 1
			global:Write-LogEntry -Value "CRITIAL FAILURE: PowerShell 5.0 is required for full functionality" -Severity 3
			global:Write-LogEntry -Value "CRITIAL FAILURE: All functions have been disabled" -Severity 3
			global:Write-LogEntry -Value "CRITIAL FAILURE: Please install at least WMF 5.1 and relanch the tool" -Severity 3
			$SelectionTabs.TabPages["MakeModelTab"].Enabled = $false
			$SelectionTabs.TabPages["CommonTab"].Enabled = $false
			$SelectionTabs.TabPages["ConfigMgrTab"].Enabled = $false
			$SelectionTabs.TabPages["MDTTab"].Enabled = $false
			$SelectionTabs.TabPages["ConfigMgrDriverTab"].Enabled = $false
			$SelectionTabs.TabPages["ConfigWSDiagTab"].Enabled = $false
			$SelectionTabs.TabPages["CustPkgTab"].Enabled = $false
			$SelectionTabs.SelectedTab = $LogTab
		}
		
		if ($PreRequisiteFailure -ne $true) {		
			# // Read Previously Selected Values	
			if ((Test-Path -Path $Global:SettingsDirectory\DATSettings.xml) -eq $true) {
				Read-XMLSettings
				Start-Sleep -Milliseconds 250
			}
			
			# Set default distribution value
			if ([string]::IsNullOrEmpty($DistributionPriorityCombo.Text)) {
				$DistributionPriorityCombo.SelectedItem = "Low"
			}
			
			# Set Version Info
			$Version.Text = $ScriptRelease
			$BuildDate.Text = $ScriptBuildDate
			
			global:Write-LogEntry -Value "======== Detecting Deployment Platform ========" -Severity 1
			
			if (((Test-Path -Path $Global:SettingsDirectory\DATSettings.xml) -eq $true) -and ($Global:DATSettingsXML.Settings.DownloadSettings.DeploymentPlatform -eq 'MDT')) {
				$ProgressListBox.ForeColor = "Black"
				global:Write-LogEntry -Value "Deployment Platform: MDT - Skipping SCCM Validation" -Severity 1
				Get-MDTEnvironment
			} elseif (((Test-Path -Path $Global:SettingsDirectory\DATSettings.xml) -eq $true) -and ($Global:DATSettingsXML.Settings.DownloadSettings.DeploymentPlatform -match 'ConfigMgr')) {
				$SiteServer = [string]$SiteServerInput.Text
				$ProgressListBox.ForeColor = "Black"
				global:Write-LogEntry -Value "Deployment Platform: SCCM - Validating ConfigMgr Server Details" -Severity 1
				Connect-ConfigMgr
				if ($Global:DATSettingsXML.Settings.DownloadSettings.DeploymentPlatform -match 'MDT') {
					Get-MDTEnvironment
				}
			} elseif (((Test-Path -Path $Global:SettingsDirectory\DATSettings.xml) -eq $true) -and ($Global:DATSettingsXML.Settings.DownloadSettings.DeploymentPlatform -match 'Download')) {
				$ProgressListBox.ForeColor = "Black"
				global:Write-LogEntry -Value "Deployment Platform: $($Global:DATSettingsXML.Settings.DownloadSettings.DeploymentPlatform)" -Severity 1
			} else {
				global:Write-LogEntry -Value "======== FIRST TIME RUN DETECTED ========" -Severity 1
				
				# Attempt ConfigMgr Site Code & MP Detection
				global:Write-LogEntry -Value "Info: Checking WMI for ConfigMgr SMS_Authority Values" -Severity 1 -SkipGuiLog $true
				try {
					$SCCMWMI = Get-CIMInstance -ClassName SMS_Authority -NameSpace root\ccm -ErrorAction SilentlyContinue
					if ($SCCMWMI.CurrentManagementPoint -ne $null) {
						global:Write-LogEntry -Value "======== ConfigMgr Site Discovery ========" -Severity 1
						$SiteServerInput.Text = $SCCMWMI.CurrentManagementPoint
						global:Write-LogEntry -Value "Info: ConfigMgr WMI Query Results - Site Server (Local MP) Found: $($SiteServerInput.Text)" -Severity 1 -SkipGuiLog $true
						$SiteCodeText.Text = ($SCCMWMI.Name).TrimStart("SMS:")
						global:Write-LogEntry -Value "Info: ConfigMgr WMI Query Results - Site Code Found: $($SiteCodeText.Text)" -Severity 1 -SkipGuiLog $true
						$ConfigMgrDetected = $true
					} else {
						$ConfigMgrDetected = $false
					}
				} catch [System.Exception] {
					global:Write-ErrorOutput -Message "Error: Unable to query ConfigMgr WMI namespace. Error message: $($_.Exception.Message)" -Severity 2
				}
				
				# Set First Time Demo Mode
				switch ($ConfigMgrDetected) {
					$true {
						global:Write-LogEntry -Value "Info: ConfigMgr detected - Running first time demo mode" -Severity 1
						$PlatformComboBox.Text = "ConfigMgr - Standard Pkg"
						$DownloadComboBox.Text = "Drivers"
						$OSComboBox.Text = "Windows 10"
						$ArchitectureComboxBox.Text = "64 Bit"
						$DellCheckBox.Checked = $true
						$HPCheckBox.Checked = $false
						$LenovoCheckBox.Checked = $true
						$MicrosoftCheckBox.Checked = $true
						$ConfigMgrImport.Text = "Yes"
						$FindModelsButton_Click
					}
					$false {
						global:Write-LogEntry -Value "Info: Failed to detect ConfigMgr - Running first time demo mode" -Severity 1
						$PlatformComboBox.Text = "Download Only"
						$DownloadComboBox.Text = "Drivers"
						$OSComboBox.Text = "Windows 10"
						$ArchitectureComboxBox.Text = "64 Bit"
						$DellCheckBox.Checked = $true
						$HPCheckBox.Checked = $false
						$LenovoCheckBox.Checked = $true
						$MicrosoftCheckBox.Checked = $true
						$FindModelsButton_Click
					}
				}
			}
			
			# Check PS Version Compatibilty
			if ($PSVersionTable.PSVersion.Major -lt "3") {
				global:Write-LogEntry -Value "======== COMPATIBILITY ISSUE DETECTED ========" -Severity 3
				global:Write-ErrorOutput -Message "Error: PowerShell Version Incompatible - Please Update PS Installation" -Severity 3
			}
			
			# Check for Internet Explorer .NET Components
			if ((Test-Path -Path (Join-Path -Path "${env:ProgramFiles(x86)}" -ChildPath "Microsoft.NET\Primary Interop Assemblies\Microsoft.mshtml.dll")) -eq $false) {
				global:Write-LogEntry -Value "======== COMPATIBILITY ISSUE DETECTED ========" -Severity 3
				global:Write-ErrorOutput -Message "Error: Required .Net Internet Explorer components missing. Lenovo downloads disabled." -Severity 3
				global:Write-LogEntry -Value "Visual Studio isolated shell components can be downloaded from - https://visualstudio.microsoft.com/vs/older-downloads/isolated-shell/" -Severity 3
				global:Write-LogEntry -Value "No warranties provided, install at your own risk." -Severity 3
				$global:LenovoDisable = $true
				$LenovoCheckBox.Enabled = $false
				$LenovoCheckBox.Checked = $false
			} else {
				$global:LenovoDisable = $false
			}
			
			if ($global:RunSilent -eq "True") {
				global:Write-LogEntry -Value "Mode: Silent running switch enabled" -Severity 2 -SkipGuiLog $true
				$ErrorActionPreference = "Stop"
				Write-Host "=== MSEndpointMgr Download Automation Tool - Silent Running ==="
				If (($ScriptRelease -ne $null) -and ($ScriptRelease -lt $NewRelease)) {
					global:Write-LogEntry -Value "Update Alert: Newer Version Available - $NewRelease" -Severity 2 -SkipGuiLog $true
				}
				$MainForm.WindowState = 'Minimized'
				Write-Host "1. Updating model list based on models found within the XML settings file"
				Update-ModeList $SiteServerInput.Text $SiteCodeText.Text
				Write-Host "2. Starting download and packaging phase"
				Invoke-Downloads
				Write-Host "3. Script finished. Check the DriverAutomationTool log file for verbose output"
				$MainForm.Close()
			} else {
				$MainForm.WindowState = 'Normal'
				$ReleaseNotesText.Text = (Invoke-WebRequest -Uri $ReleaseNotesURL -UseBasicParsing).Content
				If (($ScriptRelease -ne $null) -and ($ScriptRelease -lt $NewRelease)) {
					global:Write-LogEntry -Value "Update Alert: Newer Version Available - $NewRelease" -Severity 2 -SkipGuiLog $true
					global:Write-LogEntry -Value "Update Alert: Opening New Version Form" -Severity 2 -SkipGuiLog $true
					Set-UpdateNotice
					$SelectionTabs.SelectedTab = $AboutTab
				}
				Update-ModeList $SiteServerInput.Text $SiteCodeText.Text
			}
			
			if ((Get-ScheduledTask | Where-Object {
						$_.TaskName -eq 'Driver Automation Tool'
					})) {
				global:Write-LogEntry -Value "======== Disabling Scheduling Options - Schedule Exits ========" -Severity 1
				$TimeComboBox.Enabled = $false
				$ScriptLocation.Enabled = $false
				$ScriptLocation.Text = (Get-ScheduledTask -TaskName "Driver Automation Tool" | Select-Object -ExpandProperty Actions).WorkingDirectory
				$UsernameTextBox.Enabled = $false
				$UsernameTextBox.Text = (Get-ScheduledTask -TaskName "Driver Automation Tool").Author
				$PasswordTextBox.Enabled = $false
				$ScheduleJobButton.Visible = $false
				$ScriptDirectoryBrowseButton.Enabled = $false
			}
			Update-PlatformOptions
			$ModelResults.Text = "Found ($($MakeModelDataGrid.Rows.Count)) models"
		}
	
	}
	
	$StartDownloadButton_Click = {
	    Invoke-RunningLog
		global:Write-LogEntry -Value "Info: Validating all required selections have been made" -Severity 1
		if ($UseProxyServerCheckbox.Checked -eq $true) {
			Confirm-ProxyAccess -ProxyServer $ProxyServerInput.Text -UserName $ProxyUserInput.Text -Password $ProxyPswdInput.Text -URL $URL
		}
		Confirm-Settings
		if ($global:Validation -eq $true) {
			Invoke-Downloads
		}
		else {
			global:Write-ErrorOutput -Message "Error: Please make sure you have made all required selections" -Severity 2
		}
	}
	
	$ConnectConfigMgrButton_Click = {
		$SiteServer = [string]$SiteServerInput.Text
		$ProgressListBox.ForeColor = "Black"
		global:Write-LogEntry -Value "======== Validating ConfigMgr Server Details $(Get-Date) ========" -Severity 1
		Connect-ConfigMgr
	}
	
	$ResetDATSettings_Click = {
		# Reset Windows Form
		
		# Clear site code information
		$SiteServerInput.Enabled = $true
		$SiteServerInput.Text = $null
		$SiteCodeText.Text = $null
		
		#$ProductListBox.Items.Clear()
		$ProgressListBox.Items.Clear()
		$PlatformComboBox.SelectedItem = $null
		$PlatformComboBox.Enabled = $true
		$DownloadComboBox.SelectedItem = $null
		$DownloadComboBox.Enabled = $true
		$SiteCodeText.Enabled = $false
		
		# Clear storage paths
		$DownloadPathTextBox.Text = $null
		$PackagePathTextBox.Text = $null
		$PackagePathTextBox.Enabled = $true
		$StartDownloadButton.Enabled = $false
	
		# Clear manufacturers
		$DellCheckBox.Checked = $false
		$HPCheckBox.Checked = $false
		$LenovoCheckBox.Checked = $false
		$MicrosoftCheckBox.Checked = $false
		
		# Clear data grids
		if ($MakeModelDataGrid.Rows.Count -gt 0) {
			$MakeModelDataGrid.Rows.Clear()
		}
		if ($HPSoftpaqDataGrid.Rows.Count -gt 0) {
			$HPSoftpaqDataGrid.Rows.Clear()
		}
		
		# Clear operating systems
		$OSComboBox.SelectedItem = $null
		$OSComboBox.Enabled = $true
		$ArchitectureComboxBox.SelectedItem = $null
		$ArchitectureComboxBox.Enabled = $true
		
		$SelectionTabs.SelectedTab = $MakeModelTab
		$ProgressListBox.ForeColor = "Black"
	}
	
	$FindModelsButton_Click = {
		Find-AvailableModels
		[int]$ModelCount = $MakeModelDataGrid.Rows.Count
	}
	
	$UseProxyServerCheckbox_CheckedChanged = {
		if ($UseProxyServerCheckbox.Checked -eq $true) {
			$ProxyPswdInput.Enabled = $true
			$ProxyUserInput.Enabled = $true
			$ProxyServerInput.Enabled = $true
		}
		else {
			$ProxyPswdInput.Enabled = $false
			$ProxyUserInput.Enabled = $false
			$ProxyServerInput.Enabled = $false
		}
	}
	
	$DownloadComboBox_SelectedIndexChanged = {
		Set-CompatibilityOptions
	}
	
	$PlatformComboBox_SelectedIndexChanged = {
		Update-PlatformOptions
		
	}
	
	$MSEndpointMgrLink_LinkClicked = {
		Start-Process "https://www.MSEndpointMgr.com/2017/03/01/driver-automation-tool/"
	}
	
	$OSComboBox_SelectedIndexChanged = {
		Confirm-OSCompatibility
	}
	
	$buttonBrowseFolder_Click = {
		if ($DownloadBrowseFolderDialogue.ShowDialog() -eq 'OK') {
			$DownloadPathTextBox.Text = $DownloadBrowseFolderDialogue.SelectedPath
		}
	}
	
	$ScriptDirectoryBrowseButton_Click = {
		if ($ScriptBrowseFolderDialogue.ShowDialog() -eq 'OK') {
			$ScriptLocation.Text = $ScriptBrowseFolderDialogue.SelectedPath
		}
	}
	
	$ImportMDTPSButton_Click = {
		Get-MDTEnvironment
	}
	
	$MDTScriptBrowseButton_Click = {
		if ($MDTScriptBrowse.ShowDialog() -eq 'OK') {
			$MDTScriptTextBox.Text = $MDTScriptBrowse.SelectedPath
		}
	}
	
	$GitHubLaunchButton_Click = {
		Start-Process "https://www.MSEndpointMgr.com/modern-driver-management/"
	}
	
	$DeploymentShareGrid_SelectionChanged = {
		foreach ($SelectedRow in $DeploymentShareGrid.SelectedRows) {
			if ($SelectedRow.Cells[3].Value -ne $true) {
				$SelectedRow.Cells[3].Value = $true
				$ExportMDTShareNames.Add($SelectedRow.Cells["Name"].Value)
			}
			elseif ($SelectedRow.Cells[3].Value -eq $true) {
				$SelectedRow.Cells[3].Value = $false
				$ExportMDTShareNames.Remove($SelectedRow.Cells["Name"].Value)
			}
		}
	}
	
	$DeploymentShareGrid_CurrentCellDirtyStateChanged = {
		$DeploymentShareGrid.CommitEdit('CurrentCellChange')
	}
	
	$SelectAllButton_Click = {
		for ($Row = 0; $Row -lt $PackageGrid.RowCount; $Row++) {
			$PackageGrid.Rows[$Row].Cells[0].Value = $true
		}
	}
	
	$PackageTypeCombo_SelectedIndexChanged = {
		Update-ConfigMgrPkgList
	}
	
	$DeploymentStateCombo_SelectedIndexChanged = {
		Update-ConfigMgrPkgList
	}
	
	$SelectNoneButton_Click = {
		for ($Row = 0; $Row -lt $PackageGrid.RowCount; $Row++) {
			$PackageGrid.Rows[$Row].Cells[0].Value = $false
		}
	}
	$ConfigMgrPkgActionCombo_SelectedIndexChanged = {
		Move-ConfigMgrPkgs
	}
	
	$PackageGrid_CurrentCellDirtyStateChanged = {
		for ($Row = 0; $Row -lt $PackageGrid.RowCount; $Row++) {
			if ($PackageGrid.Rows[$Row].Cells[0].Value -eq $true) {
				$PackageGrid.Rows[$Row].Selected = $true
			}
			else {
				$PackageGrid.Rows[$Row].Cells[0].Value = $false
			}
		}
		$PackageGrid.CommitEdit('CurrentCellChange')
	}
	
	$DownloadBrowseButton_Click = {
		if ($DownloadBrowseFolderDialogue.ShowDialog() -eq 'OK') {
			$DownloadPathTextBox.Text = $DownloadBrowseFolderDialogue.SelectedPath
		}
	}
	
	$PackageBrowseButton_Click = {
		if ($PackageBrowseFolderDialogue.ShowDialog() -eq 'OK') {
			$PackagePathTextBox.Text = $PackageBrowseFolderDialogue.SelectedPath
		}
	}
	
	$CreatePackagesButton_Click = {
		$SelectionTabs.SelectedTab = $LogTab
		Create-CustomPkg
	}
	
	$ImportCSVButton_Click = {
		$CustomPkgDataGrid.Rows.Clear()
		Set-MDTOptions -OptionsEnabled $true
		Set-ConfigMgrOptions -OptionsEnabled $true
		Import-CSVModels
	}
	
	$CustomPkgDataGrid_CurrentCellDirtyStateChanged = {
		$CustomPkgDataGrid.CommitEdit('CurrentCellChange')
		$ExtractDriverDir = Join-Path -Path "$($DownloadPathTextBox.Text)" -ChildPath "$($CustomPkgDataGrid.Rows[0].Cells[0].Value)\$($CustomPkgDataGrid.Rows[0].Cells[1].Value)\$($CustomPkgDataGrid.Rows[0].Cells[2].Value)\$($CustomPkgDataGrid.Rows[0].Cells[4].Value)-$($CustomPkgDataGrid.Rows[0].Cells[5].Value)-$($CustomPkgDataGrid.Rows[0].Cells[6].Value)"
		$CustomPkgDataGrid.Rows[0].Cells[7].Value = $ExtractDriverDir
	}
	
	$CreateFallbackButton_Click = {
		$SelectionTabs.SelectedTab = $LogTab
		Create-DriverFBPkg
	}
	
	$FallbackOSCombo_SelectedIndexChanged = {
		Enable-DriverFBPkg
	}
	
	$FallbackArcCombo_SelectedIndexChanged = {
		Enable-DriverFBPkg
	}
	
	$ScheduleJobButton_Click = {
		$SelectionTabs.SelectedTab = $LogTab
		# Test Active Directory Credentials
		$CredentialVerified = Test-Credentials
		
		if ($CredentialVerified -eq $true) {
			$UsernameTextBox.BackColor = 'White'
			$PasswordTextBox.BackColor = 'White'
			$ProgressListBox.ForeColor = 'Black'
			# Run scheduled job function
			Schedule-Downloads
		}
		else {
			# Prompt User		
			$UsernameTextBox.BackColor = 'Yellow'
			$PasswordTextBox.BackColor = 'Yellow'
		}
	}
	
	$ConnectWebServiceButton_Click = {
		if ((![string]::IsNullOrEmpty($ConfigMgrWebURL.Text)) -and (![string]::IsNullOrEmpty($SecretKey.Text))) {
			global:Write-LogEntry -Value "======== ConfigMgr WebService Diagnostics Running ========" -Severity 1
			Test-ConfigMgrWebSVC
		}
		else {
			global:Write-LogEntry -Value "======== ConfigMgr WebService Diagnostics Error ========" -Severity 3
			global:Write-ErrorOutput -Message "Error: Please ensure you enter the ConfigMgr WebService URL and the required Secret Key value." -Severity 3
		}
	}
	
	$MakeModelDataGrid_KeyPress = [System.Windows.Forms.KeyPressEventHandler]{
		$MakeModelDataGrid.CurrentRow.Cells[0].Value = $true
		for ($Row = 0; $Row -lt $MakeModelDataGrid.RowCount; $Row++) {
			if ($MakeModelDataGrid.Rows[$Row].Cells[0].Value -eq $true) {
				$MakeModelDataGrid.Rows[$Row].Selected = $true
			}
			else {
				$MakeModelDataGrid.Rows[$Row].Cells[0].Value = $false
			}
		}	
	}
	
	
	$MakeModelDataGrid_CurrentCellDirtyStateChanged = {
		for ($Row = 0; $Row -lt $MakeModelDataGrid.RowCount; $Row++) {
			if ($MakeModelDataGrid.Rows[$Row].Cells[0].Value -eq $true) {
				$MakeModelDataGrid.Rows[$Row].Selected = $true
			}
			else {
				$MakeModelDataGrid.Rows[$Row].Cells[0].Value = $false
			}
		}
		$MakeModelDataGrid.CommitEdit('CurrentCellChange')
	}
	
	$DPGGridView_CurrentCellDirtyStateChanged={
		$DPGGridView.CommitEdit('CurrentCellChange')
	}
	
	$DPGridView_CurrentCellDirtyStateChanged={
		$DPGridView.CommitEdit('CurrentCellChange')
	}
	
	$FindModel_Click = {
		Search-ModelList
	}
	
	$FindSoftPaq_Click = {
		Search-HPDriverList
	}
	
	$ClearModelSelection_Click={
		
		# Show notification panel
		$XMLLoading.Visible = $true
		$XMLLoadingLabel.Text = "Clearing all model selections.."
		$XMLLoadingLabel.Visible = $true
		
		Start-Sleep -Seconds 2
	
		for ($Row = 0; $Row -lt $MakeModelDataGrid.RowCount; $Row++) {
			$MakeModelDataGrid.Rows[$Row].Selected = $false
			$MakeModelDataGrid.Rows[$Row].Cells[6].Value = $null
			$MakeModelDataGrid.Rows[$Row].Cells[0].Value = $false
		}
		$MakeModelDataGrid.Sort($MakeModelDataGrid.Columns[1], [System.ComponentModel.ListSortDirection]::Descending)
		
		# Hide notification panel
		$XMLLoading.Visible = $false
		$XMLLoadingLabel.Visible = $false
		
	}
	
	$PackageRoot_CheckedChanged={
		if ($PackageRoot.Checked -eq $true) {
			$CustPackageDest.Enabled = $false
			$SpecifyCustomPath.Enabled = $false
			$SpecifyCustomPath.Checked = $false
		}
		else {
			$SpecifyCustomPath.Enabled = $true
		}	
	}
	
	$SpecifyCustomPath_CheckedChanged={
		if ($SpecifyCustomPath.Checked -eq $true) {
			$CustPackageDest.Enabled = $true
			$PackageRoot.Checked = $false
			$PackageRoot.Enabled = $false
		}
		else {
			$CustPackageDest.Enabled = $false
			$PackageRoot.Checked = $false
			$PackageRoot.Enabled = $true
		}
	}
	
	$PackageGrid_KeyPress=[System.Windows.Forms.KeyPressEventHandler]{
		$PackageGrid.CurrentRow.Cells[0].Value = $true
		for ($Row = 0; $Row -lt $PackageGrid.RowCount; $Row++) {
			if ($PackageGrid.Rows[$Row].Cells[0].Value -eq $true) {
				$PackageGrid.Rows[$Row].Selected = $true
			}
			else {
				$PackageGrid.Rows[$Row].Cells[0].Value = $false
			}
		}
	}
	
	$SelectAll_Click = {
		
		# Show notification panel
		$XMLLoading.Visible = $true
		$XMLLoadingLabel.Text = "Selecting ALL models"
		$XMLLoadingLabel.Visible = $true
		$XMLDownloadStatus.Text = "Caution: Sufficient storage and time is required for this option"
		$XMLDownloadStatus.Visible = $true
		Start-Sleep -Seconds 3
		
		for ($Row = 0; $Row -lt $MakeModelDataGrid.RowCount; $Row++) {
			$MakeModelDataGrid.Rows[$Row].Cells[0].Value = $true
			$MakeModelDataGrid.Rows[$Row].Selected = $true
		}
		$MakeModelDataGrid.Sort($MakeModelDataGrid.Columns[1], [System.ComponentModel.ListSortDirection]::Descending)
		
		# Hide notification panel
		$XMLLoading.Visible = $false
		$XMLLoadingLabel.Visible = $false
		$XMLDownloadStatus.Visible = $false
		
	}
	
	$CustomPkgDataGrid_CellContentClick = [System.Windows.Forms.DataGridViewCellEventHandler]{
		if (($CustomPkgDataGrid.CurrentRow.Cells["Browse"].Selected) -or ($CustomPkgDataGrid.CurrentRow.Cells[7].Selected)) {
			if ($CustomPackageBrowse.ShowDialog() -eq 'OK') {
				$CustomPkgDataGrid.CurrentRow.Cells[7].Value = $CustomPackageBrowse.SelectedPath
			}
		}
	}
	
	$CustomExtractButton_Click = {
		global:Write-LogEntry -Value "======== Extracting Local System Drivers ========" -Severity 1
		$PkgImporting.Visible = $true
		$PkgImportingText.Visible = $true
		$PkgImportingText.Text = "Exporting $($CustomPkgDataGrid.Rows[0].Cells[0].Value) $($CustomPkgDataGrid.Rows[0].Cells[1].Value) drivers. Please wait.."
		$ExtractDriverDir = $($CustomPkgDataGrid.Rows[0].Cells[7].Value)
		if (-not (Test-Path -Path $ExtractDriverDir)) {
			New-Item -Type dir -Path $ExtractDriverDir -Force
		}
		try {
			global:Write-LogEntry -Value "Info: Exporting local system drivers to $ExtractDriverDir" -Severity 1
			if ([boolean](Get-Command Export-WindowsDriver) -eq $false) {
				global:Write-LogEntry -Value "Info: Using Export-WindowsDriver cmdlet to export system drivers" -Severity 1
				Export-WindowsDriver -Online -Destination $ExtractDriverDir -LogPath $(Join-Path -Path $ExtractDriverDir -ChildPath "ExportedDrivers.log")
			}
			else {
				global:Write-LogEntry -Value "Info: Using DISM to export system drivers" -Severity 1
				$DismExtractDriverDir = '"' + "$ExtractDriverDir" + '"'
				Start-Process dism -ArgumentList "/online /export-driver /destination:$($DismExtractDriverDir)" -NoNewWindow -Wait
			}
			global:Write-LogEntry -Value "Info: Creating XML import file" -Severity 1
			Write-XMLModels -XMLPath $ExtractDriverDir -Make $CustomPkgDataGrid.Rows[0].Cells[0].Value -Model $CustomPkgDataGrid.Rows[0].Cells[1].Value -MatchingValues $CustomPkgDataGrid.Rows[0].Cells[2].Value -OperatingSystem $CustomPkgDataGrid.Rows[0].Cells[4].Value -Architecture $CustomPkgDataGrid.Rows[0].Cells[5].Value -Platform $CustomPkgPlatform.SelectedItem
			sleep -Seconds 3
			global:Write-LogEntry -Value "Info: Finished export" -Severity 1
			$PkgImportingText.Text = "Finished export process"
			sleep -Seconds 3
			$PkgImportingText.Visible = $false
			$PkgImporting.Visible = $false
		}
		Catch [System.Exception]{
			global:Write-LogEntry -Value "$($_.Exception.Message)" -Severity 2
		}
	}
	
	$ImportExtractedDriveButton_Click = {
		$CustomPkgDataGrid.Rows.Clear()
		$ImportXMLFileBrowse = New-Object system.windows.forms.openfiledialog
		$ImportXMLFileBrowse.MultiSelect = $false
		$ImportXMLFileBrowse.Filter = "Driver Extract XML (*.xml) | *.xml"
		$ImportXMLFileBrowse.showdialog()
		$ImportXMLFileName = $ImportXMLFileBrowse.FileName
		Read-XMLFile -XMLFile $ImportXMLFileName
	}
	
	$QuerySystemButton_Click = {
		$CustomPkgDataGrid.Rows.Clear()
		global:Write-LogEntry -Value "======== Querying Local System ========" -Severity 1
		# Obtain local system details
		$CurrentSystemOS = Get-CIMInstance -ClassName Win32_OperatingSystem -NameSpace root\CIMV2 | select -Property OSArchitecture, Version, Caption
		$CurrentModel = Get-CIMInstance -ClassName Win32_ComputerSystem -NameSpace root\CIMV2 | select -Property Manufacturer, Model, SystemSKUNumber
		$BaseBoardProduct = (Get-CIMInstance -ClassName MS_SystemInformation -NameSpace root\WMI).BaseBoardProduct
		
		switch -wildcard ($CurrentModel.Manufacturer) {
			"*Dell*" {
				$ExtractMake = "Dell"
				$ExtractSKU = $CurrentModel.SystemSKUNumber
			}
			"*Lenovo*" {
				$ExtractMake = "Lenovo"
				$ExtractSKU = ((Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model).SubString(0, 4)).Trim()
			}
			"*Microsoft*" {
				$ComputerManufacturer = "Microsoft"
				$ComputerModel = (Get-WmiObject -Namespace root\wmi -Class MS_SystemInformation | Select-Object -ExpandProperty SystemSKU).Replace("_", " ")
			}
			default {
				$ExtractMake = $CurrentModel.Manufacturer
				$ExtractSKU = (Get-CIMInstance -ClassName MS_SystemInformation -NameSpace root\WMI).BaseBoardProduct
			}
		}
		
		switch -wildcard ($CurrentSystemOS.Caption) {
			"*Windows 10*" {
				$OSRelease = [version]"10.0"
				$OSName = "Windows 10"
			}
			"*Windows 8.1" {
				$OSRelease = [version]"6.3"
				$OSName = "Windows 8.1"
			}
			"*Windows 8" {
				$OSRelease = [version]"6.2"
				$OSName = "Windows 8"
			}
			"*Windows 7" {
				$OSRelease = [version]"6.1"
				$OSName = "Windows 7"
			}
		}
		
		switch -wildcard ($CurrentSystemOS.OSArchitecture) {
			"64*" {
				$OSArchitecture = "x64"
			}
			"32*" {
				$OSArchitecture = "x86"
			}
		}
		if ($OSName -eq "Windows 10") {
			$Windows10Build = $WindowsBuildHashTable.Keys.Where({
					$WindowsBuildHashTable[$_] -match $CurrentSystemOS.Version
				})
			$OSName = $OSName + " $Windows10Build"
		}
		
		global:Write-LogEntry -Value "$($Product): Model detected $($CurrentModel.Make) $($CurrentModel.Model)" -Severity 1
		global:Write-LogEntry -Value "$($Product): Operating system detected $OSName $OSArchitecture" -Severity 1
		
		$ExtractDriverDir = Join-Path -Path "$($DownloadPathTextBox.Text)" -ChildPath "$ExtractMake\$($CurrentModel.Model)\$OSName-$OSArchitecture"
		$CustomPkgDataGrid.Rows.Add($ExtractMake, $CurrentModel.Model, $ExtractSKU, $CustomPkgPlatform.SelectedItem, $OSName, $OSArchitecture, "ENTER VERSION NUMBER", $ExtractDriverDir)
		$QuerySystemButton.Enabled = $false
		$CustomExtractButton.Enabled = $true
	}
	
	$DPGridView_KeyPress = [System.Windows.Forms.KeyPressEventHandler]{
		for ($Row = 0; $Row -lt $DPGridView.RowCount; $Row++) {
			if (($DPGridView.Rows[$Row].Selected -eq $true) -and ($DPGridView.Rows[$Row].Cells[0].Value -eq $true)) {
				$DPGridView.Rows[$Row].Cells[0].Value = $false
			}
			elseif (($DPGridView.Rows[$Row].Selected -eq $true) -and ($DPGridView.Rows[$Row].Cells[0].Value -eq $false)) {
				$DPGridView.Rows[$Row].Cells[0].Value = $true
			}
		}	
	}
	
	$DPGGridView_KeyPress = [System.Windows.Forms.KeyPressEventHandler]{
		for ($Row = 0; $Row -lt $DPGGridView.RowCount; $Row++) {
			if (($DPGGridView.Rows[$Row].Selected -eq $true) -and ($DPGGridView.Rows[$Row].Cells[0].Value -eq $true)) {
				$DPGGridView.Rows[$Row].Cells[0].Value = $false
			}
			elseif ((($DPGGridView.Rows[$Row].Selected -eq $true) -and ($DPGGridView.Rows[$Row].Cells[0].Value -eq $false)) ) {
				$DPGGridView.Rows[$Row].Cells[0].Value = $true
			}
		}
	}
	
	$DPGridView_CurrentCellDirtyStateChanged = {
		$DPGridView.CommitEdit('CurrentCellChange')
	}
	
	$DPGGridView_CurrentCellDirtyStateChanged = {
		$DPGGridView.CommitEdit('CurrentCellChange')
	}
	
	$HideCommonSettings_CheckedChanged = {
		Set-AdminControl -TabValue "SettingsTab" -CheckedValue $HideCommonSettings.Checked
	}
	
	$HideConfigPkgMgmt_CheckedChanged={
		Set-AdminControl -TabValue "ConfigMgrDriverTab" -CheckedValue $HideConfigPkgMgmt.Checked
	}
	
	$HideWebService_CheckedChanged={
		Set-AdminControl -TabValue "ConfigMgrWebSVCVisible" -CheckedValue $HideWebService.Checked
	}
	
	$HideCustomCreation_CheckedChanged = {
		Set-AdminControl -TabValue "CustPkgTab" -CheckedValue $HideCustomCreation.Checked
	}
	
	$HideMDT_CheckedChanged = {
		Set-AdminControl -TabValue "MDTSettingsVisible" -CheckedValue $HideMDT.Checked
	}
	
	$CustomPkgPlatform_SelectedIndexChanged = {
		$QuerySystemButton.Enabled = $true
		$ImportExtractedDriveButton.Enabled = $true
		$CreatePackagesButton.Enabled = $true
		if ($CustomPkgPlatform.Text -ne "XML"){
			$ImportCSVButton.Enabled = $true
		}
	}
	$LenovoCheckBox_CheckedChanged={
		Enable-FindModels
	}
	
	$DellCheckBox_CheckedChanged={
		Enable-FindModels
	}
	
	$HPCheckBox_CheckedChanged={
		Enable-FindModels
	}
	
	$MicrosoftCheckBox_CheckedChanged={
		Enable-FindModels
	}
	
	$FindModelsButton_EnabledChanged = {
		if ($FindModelsButton.Enabled -eq $true) {
			$SearchSelectionState = $true
		} else {
			$SearchSelectionState = $false
		}
		
		# Set search selection controls
		$SelectAll.Enabled = $SearchSelectionState
		$ClearModelSelection.Enabled = $SearchSelectionState
	}
	
	$MSEndpointMgrLogo_Click={
		Start-Process "https://www.MSEndpointMgr.com"
	}
	
	$MakeModelDataGrid_RowsAdded=[System.Windows.Forms.DataGridViewRowsAddedEventHandler]{
		$SelectAll.Enabled = $true
		$ClearModelSelection.Enabled = $true
	}
	
	$ModelSearchText_KeyDown=[System.Windows.Forms.KeyEventHandler]{
		if (($_.KeyCode -eq "Enter") -and (-not([string]::IsNullOrEmpty($ModelSearchText.Text)))) {
			Search-ModelList
		}
	}
	
	$HPSearchText_KeyDown=[System.Windows.Forms.KeyEventHandler]{
		if (($_.KeyCode -eq "Enter") -and (-not ([string]::IsNullOrEmpty($HPSearchText.Text)))) {
			Search-HPDriverList
		}
	}
	
	$FindModel_MouseEnter={
		$FindModel.BackColor = 'Maroon'
		$FindModel.ForeColor = 'White'
	}
	
	$FindModel_MouseLeave={
		$FindModel.BackColor = 'Silver'
		$FindModel.ForeColor = 'Black'
		
	}
	
	$FindModelsButton_MouseEnter={
		$FindModelsButton.BackColor = 'Maroon'
	}
	
	$FindModelsButton_MouseLeave={
		$FindModelsButton.BackColor = '64,64,64'	
	}
	
	$DownloadComboBox_TextChanged={
		Confirm-OSCompatibility
	}
	
	$OSComboBox_EnabledChanged={
		#Confirm-OSCompatibility
	}
	
	$OSComboBox_TextChanged = {
		Confirm-OSCompatibility
	}
	
	$buttonConnectGraphAPI_Click = {
		$GraphAuthStatus.Text = "Connecting"
		$GraphAuthToken = Get-MSIntuneAuthToken -TenantName $AADTenantName.Text -ClientID $AADAppID.Text -ClientSecret $APPSecret.Text
		$global:ManagedApps = Get-ManagedApps
	    Get-ManagedDevices
		
	}
	
	$RefreshIntuneModels_Click={
		if (($global:Authentication -ne $null) -and ($global:Authentication.ExpiresOn -gt (Get-Date))) {
			global:Write-LogEntry -Value "Graph API: Refreshing Devices" -Severity 1
			Get-ManagedDevices
		} else {
			global:Write-LogEntry -Value "Graph API: Refreshing Auth Token & Devices" -Severity 1
			$GraphAuthStatus.Text = "Connecting"
			$GraphAuthToken = Get-MSIntuneAuthToken -TenantName $AADTenantName.Text -ClientID $AADAppID.Text -ClientSecret $APPSecret.Text
			Get-ManagedDevices
		}
	}
	
	$FindModelSelect_Click={
		Search-ModelList -FindAndSelect $true
	}
	
	$HPCatalogModels_SelectedIndexChanged={
		Get-HPSoftPaqDrivers
	}
	
	$SelectAllSoftPaqs_Click={
		Update-DataGrid -Action SelectAll -GridViewName $HPSoftpaqDataGrid
	}
	
	$ClearSoftPaqSelections_Click = {
		Update-DataGrid -Action ClearSelection -GridViewName $HPSoftpaqDataGrid
	}
	
	$HPSoftpaqDataGrid_CurrentCellDirtyStateChanged={
		$HPSoftpaqDataGrid.CommitEdit('CurrentCellChange')
	}
	
	$ResetSoftPaqSelection_Click = {
		Update-DataGrid -Action ClearSelection -GridViewName $HPSoftpaqDataGrid
		$HPSoftpaqDataGrid.CommitEdit('CurrentCellChange')
	}
	
	$MainForm_FormClosing = [System.Windows.Forms.FormClosingEventHandler]{
		
		$PackageGrid.EndEdit
		$DeploymentShareGrid.EndEdit
		$DeploymentShareGrid.Refresh
		$MakeModelDataGrid.EndEdit
		
		global:Write-LogEntry -Value "======== Cleaning Up Temporary Files ========" -Severity 1
		global:Write-LogEntry -Value "Info: Removing Temp Folders & Source XML/CAB Files" -Severity 1 -SkipGuiLog $true
		# Clean Up Temp Driver Folders
		Get-ChildItem -Path $global:TempDirectory -Recurse -Directory | Remove-Item -Recurse -Force
		# Clean Up Temp XML & CAB Sources
		Get-ChildItem -Path $global:TempDirectory -Recurse -File | Where-Object {
			($_.Name -match ".cab") -or ($_.Name -match ".xml") -and ($_.CreationTime -lt (Get-Date).AddDays(-7))
		} | Remove-Item -Force
		
		if ($global:NoXMLOutput -eq $false) {
			Write-XMLSettings
			global:Write-LogEntry -Value "Info: Updating DATSettings.XML file" -Severity 1 -SkipGuiLog $true
		}
		
		# Copy XML for silent running
		if ((Get-ScheduledTask | Where-Object {
					$_.TaskName -eq 'Driver Automation Tool'
				})) {
			Write-Output "$($ScriptLocation.Text)"
			if ((Test-Path -Path (Join-Path (Get-ScheduledTask -TaskName "Driver Automation Tool" | Select-Object -ExpandProperty Actions).WorkingDirectory "\Settings")) -eq $false) {
				New-Item -Path (Join-Path (Get-ScheduledTask -TaskName "Driver Automation Tool" | Select-Object -ExpandProperty Actions).WorkingDirectory "\Settings") -ItemType dir
			}
			Copy-Item -Path (Join-Path $SettingsDirectory "DATSettings.XML") -Destination (Join-Path (Get-ScheduledTask -TaskName "Driver Automation Tool" | Select-Object -ExpandProperty Actions).WorkingDirectory "\Settings\DATSettings.XML") -Force
			global:Write-LogEntry -Value "Info: Updating scheduled DATSettings.XML file" -Severity 1 -SkipGuiLog $true
		}
		
		# Remove set variables
		Remove-Variables
		
		# Close DriverAutomationTool Process
		Get-Process -Name "DriverAutomationTool*" | Stop-Process -Force
	}
	
	$DownloadSoftPaqs_Click = {
		
		# Set log as focus and start job
		Invoke-RunningLog
		
		# Set default value
		$global:HPSoftPaqDownloads = 0
		
		# Count selected SoftPaqs
		for ($Row = 0; $Row -lt $HPSoftpaqDataGrid.RowCount; $Row++) {
			if ($HPSoftpaqDataGrid.Rows[$Row].Cells[0].Value -eq $true) {
				$global:HPSoftPaqDownloads++
			}
		}
		
		# Call download function
		Invoke-Downloads -DownloadJobType OEMDriverPackages
	}
	
	$ZipCompressionCheckBox_CheckedChanged={
		if ($ZipCompressionCheckBox.CheckState -eq $False) {
			$CompressionType.Enabled = $false
		} else {
			$CompressionType.Enabled = $true
		}
	}
	
	$ZipCompressionCheckBox_EnabledChanged={
		if ($ZipCompressionCheckBox.Enabled -eq $False) {
			$CompressionType.Enabled = $false
		} else {
			$CompressionType.Enabled = $true
		}
	}
	
	$RefreshSoftPaqSelection_Click={
		Get-HPSoftPaqDrivers
		
	}
	
	
	
	# --End User Generated Script--
	#----------------------------------------------
	#region Generated Events
	#----------------------------------------------
	
	$Form_StateCorrection_Load=
	{
		#Correct the initial state of the form to prevent the .Net maximized form issue
		$MainForm.WindowState = $InitialFormWindowState
	}
	
	$Form_StoreValues_Closing=
	{
		#Store the control values
		$script:MainForm_DescriptionText = $DescriptionText.Text
		$script:MainForm_ModelSearchText = $ModelSearchText.Text
		$script:MainForm_MakeModelDataGrid = $MakeModelDataGrid.SelectedCells
		if ($MakeModelDataGrid.SelectionMode -eq 'FullRowSelect')
		{ $script:MainForm_MakeModelDataGrid_SelectedObjects = $MakeModelDataGrid.SelectedRows | Select-Object -ExpandProperty DataBoundItem }
		else { $script:MainForm_MakeModelDataGrid_SelectedObjects = $MakeModelDataGrid.SelectedCells | Select-Object -ExpandProperty RowIndex -Unique | ForEach-Object { if ($_ -ne -1) { $MakeModelDataGrid.Rows[$_].DataBoundItem } } }
		$script:MainForm_ArchitectureComboxBox = $ArchitectureComboxBox.Text
		$script:MainForm_ArchitectureComboxBox_SelectedItem = $ArchitectureComboxBox.SelectedItem
		$script:MainForm_OSComboBox = $OSComboBox.Text
		$script:MainForm_OSComboBox_SelectedItem = $OSComboBox.SelectedItem
		$script:MainForm_DownloadComboBox = $DownloadComboBox.Text
		$script:MainForm_DownloadComboBox_SelectedItem = $DownloadComboBox.SelectedItem
		$script:MainForm_PlatformComboBox = $PlatformComboBox.Text
		$script:MainForm_PlatformComboBox_SelectedItem = $PlatformComboBox.SelectedItem
		$script:MainForm_MicrosoftCheckBox = $MicrosoftCheckBox.Checked
		$script:MainForm_HPCheckBox = $HPCheckBox.Checked
		$script:MainForm_LenovoCheckBox = $LenovoCheckBox.Checked
		$script:MainForm_DellCheckBox = $DellCheckBox.Checked
		$script:MainForm_HPCatalogModels = $HPCatalogModels.Text
		$script:MainForm_HPCatalogModels_SelectedItem = $HPCatalogModels.SelectedItem
		$script:MainForm_HPSearchText = $HPSearchText.Text
		$script:MainForm_HPSoftpaqDataGrid = $HPSoftpaqDataGrid.SelectedCells
		if ($HPSoftpaqDataGrid.SelectionMode -eq 'FullRowSelect')
		{ $script:MainForm_HPSoftpaqDataGrid_SelectedObjects = $HPSoftpaqDataGrid.SelectedRows | Select-Object -ExpandProperty DataBoundItem }
		else { $script:MainForm_HPSoftpaqDataGrid_SelectedObjects = $HPSoftpaqDataGrid.SelectedCells | Select-Object -ExpandProperty RowIndex -Unique | ForEach-Object { if ($_ -ne -1) { $HPSoftpaqDataGrid.Rows[$_].DataBoundItem } } }
		$script:MainForm_textbox8 = $textbox8.Text
		$script:MainForm_textbox7 = $textbox7.Text
		$script:MainForm_StoragePathInstruction = $StoragePathInstruction.Text
		$script:MainForm_DownloadPathTextBox = $DownloadPathTextBox.Text
		$script:MainForm_SchedulingInstruction = $SchedulingInstruction.Text
		$script:MainForm_UsernameTextBox = $UsernameTextBox.Text
		$script:MainForm_TimeComboBox = $TimeComboBox.Text
		$script:MainForm_TimeComboBox_SelectedItem = $TimeComboBox.SelectedItem
		$script:MainForm_ScriptLocation = $ScriptLocation.Text
		$script:MainForm_UseProxyServerCheckbox = $UseProxyServerCheckbox.Checked
		$script:MainForm_ProxyServerText = $ProxyServerText.Text
		$script:MainForm_ProxyPswdInput = $ProxyPswdInput.Text
		$script:MainForm_ProxyServerInput = $ProxyServerInput.Text
		$script:MainForm_ProxyUserInput = $ProxyUserInput.Text
		$script:MainForm_AdminControlsInstruction = $AdminControlsInstruction.Text
		$script:MainForm_textbox6 = $textbox6.Text
		$script:MainForm_HideCommonSettings = $HideCommonSettings.Checked
		$script:MainForm_HideCustomCreation = $HideCustomCreation.Checked
		$script:MainForm_HideConfigPkgMgmt = $HideConfigPkgMgmt.Checked
		$script:MainForm_HideWebService = $HideWebService.Checked
		$script:MainForm_HideMDT = $HideMDT.Checked
		$script:MainForm_textbox9 = $textbox9.Text
		$script:MainForm_CreateXMLLogicPackage = $CreateXMLLogicPackage.Checked
		$script:MainForm_CompressionType = $CompressionType.Text
		$script:MainForm_CompressionType_SelectedItem = $CompressionType.SelectedItem
		$script:MainForm_ZipCompressionText = $ZipCompressionText.Text
		$script:MainForm_ZipCompressionCheckBox = $ZipCompressionCheckBox.Checked
		$script:MainForm_CleanSourceText = $CleanSourceText.Text
		$script:MainForm_RemoveDriverSourceCheckbox = $RemoveDriverSourceCheckbox.Checked
		$script:MainForm_RemoveBIOSText = $RemoveBIOSText.Text
		$script:MainForm_RemoveLegacyBIOSCheckbox = $RemoveLegacyBIOSCheckbox.Checked
		$script:MainForm_CleanUpText = $CleanUpText.Text
		$script:MainForm_CleanUnusedCheckBox = $CleanUnusedCheckBox.Checked
		$script:MainForm_RemoveSuperText = $RemoveSuperText.Text
		$script:MainForm_RemoveLegacyDriverCheckbox = $RemoveLegacyDriverCheckbox.Checked
		$script:MainForm_PackagePathTextBox = $PackagePathTextBox.Text
		$script:MainForm_CustPackageDest = $CustPackageDest.Text
		$script:MainForm_SpecifyCustomPath = $SpecifyCustomPath.Checked
		$script:MainForm_textbox4 = $textbox4.Text
		$script:MainForm_PackageRoot = $PackageRoot.Checked
		$script:MainForm_ConfigMgrImport = $ConfigMgrImport.Text
		$script:MainForm_ConfigMgrImport_SelectedItem = $ConfigMgrImport.SelectedItem
		$script:MainForm_ConifgSiteInstruction = $ConifgSiteInstruction.Text
		$script:MainForm_SiteCodeText = $SiteCodeText.Text
		$script:MainForm_SiteServerInput = $SiteServerInput.Text
		$script:MainForm_EnableBinaryDifCheckBox = $EnableBinaryDifCheckBox.Checked
		$script:MainForm_DistributionPriorityCombo = $DistributionPriorityCombo.Text
		$script:MainForm_DistributionPriorityCombo_SelectedItem = $DistributionPriorityCombo.SelectedItem
		$script:MainForm_DPGridView = $DPGridView.SelectedCells
		if ($DPGridView.SelectionMode -eq 'FullRowSelect')
		{ $script:MainForm_DPGridView_SelectedObjects = $DPGridView.SelectedRows | Select-Object -ExpandProperty DataBoundItem }
		else { $script:MainForm_DPGridView_SelectedObjects = $DPGridView.SelectedCells | Select-Object -ExpandProperty RowIndex -Unique | ForEach-Object { if ($_ -ne -1) { $DPGridView.Rows[$_].DataBoundItem } } }
		$script:MainForm_DPGGridView = $DPGGridView.SelectedCells
		if ($DPGGridView.SelectionMode -eq 'FullRowSelect')
		{ $script:MainForm_DPGGridView_SelectedObjects = $DPGGridView.SelectedRows | Select-Object -ExpandProperty DataBoundItem }
		else { $script:MainForm_DPGGridView_SelectedObjects = $DPGGridView.SelectedCells | Select-Object -ExpandProperty RowIndex -Unique | ForEach-Object { if ($_ -ne -1) { $DPGGridView.Rows[$_].DataBoundItem } } }
		$script:MainForm_FallbackManufacturer = $FallbackManufacturer.Text
		$script:MainForm_FallbackManufacturer_SelectedItem = $FallbackManufacturer.SelectedItem
		$script:MainForm_FallbackDesc = $FallbackDesc.Text
		$script:MainForm_FallbackArcCombo = $FallbackArcCombo.Text
		$script:MainForm_FallbackArcCombo_SelectedItem = $FallbackArcCombo.SelectedItem
		$script:MainForm_FallbackOSCombo = $FallbackOSCombo.Text
		$script:MainForm_FallbackOSCombo_SelectedItem = $FallbackOSCombo.SelectedItem
		$script:MainForm_AADAppID = $AADAppID.Text
		$script:MainForm_AADTenantName = $AADTenantName.Text
		$script:MainForm_APPSecret = $APPSecret.Text
		$script:MainForm_IntuneAppDataGrid = $IntuneAppDataGrid.SelectedCells
		if ($IntuneAppDataGrid.SelectionMode -eq 'FullRowSelect')
		{ $script:MainForm_IntuneAppDataGrid_SelectedObjects = $IntuneAppDataGrid.SelectedRows | Select-Object -ExpandProperty DataBoundItem }
		else { $script:MainForm_IntuneAppDataGrid_SelectedObjects = $IntuneAppDataGrid.SelectedCells | Select-Object -ExpandProperty RowIndex -Unique | ForEach-Object { if ($_ -ne -1) { $IntuneAppDataGrid.Rows[$_].DataBoundItem } } }
		$script:MainForm_checkboxRemoveUnusedDriverPa = $checkboxRemoveUnusedDriverPa.Checked
		$script:MainForm_textbox1 = $textbox1.Text
		$script:MainForm_textbox3 = $textbox3.Text
		$script:MainForm_checkboxRemoveUnusedBIOSPack = $checkboxRemoveUnusedBIOSPack.Checked
		$script:MainForm_IntuneKnownModels = $IntuneKnownModels.Text
		$script:MainForm_IntuneKnownModels_SelectedItem = $IntuneKnownModels.SelectedItem
		$script:MainForm_DeploymentShareGrid = $DeploymentShareGrid.SelectedCells
		if ($DeploymentShareGrid.SelectionMode -eq 'FullRowSelect')
		{ $script:MainForm_DeploymentShareGrid_SelectedObjects = $DeploymentShareGrid.SelectedRows | Select-Object -ExpandProperty DataBoundItem }
		else { $script:MainForm_DeploymentShareGrid_SelectedObjects = $DeploymentShareGrid.SelectedCells | Select-Object -ExpandProperty RowIndex -Unique | ForEach-Object { if ($_ -ne -1) { $DeploymentShareGrid.Rows[$_].DataBoundItem } } }
		$script:MainForm_MDTDriverStructureCombo = $MDTDriverStructureCombo.Text
		$script:MainForm_MDTDriverStructureCombo_SelectedItem = $MDTDriverStructureCombo.SelectedItem
		$script:MainForm_TotalControlExampleLabel = $TotalControlExampleLabel.Text
		$script:MainForm_MDTScriptTextBox = $MDTScriptTextBox.Text
		$script:MainForm_MDTLocationDesc = $MDTLocationDesc.Text
		$script:MainForm_PackageGrid = $PackageGrid.SelectedCells
		if ($PackageGrid.SelectionMode -eq 'FullRowSelect')
		{ $script:MainForm_PackageGrid_SelectedObjects = $PackageGrid.SelectedRows | Select-Object -ExpandProperty DataBoundItem }
		else { $script:MainForm_PackageGrid_SelectedObjects = $PackageGrid.SelectedCells | Select-Object -ExpandProperty RowIndex -Unique | ForEach-Object { if ($_ -ne -1) { $PackageGrid.Rows[$_].DataBoundItem } } }
		$script:MainForm_DeploymentStateCombo = $DeploymentStateCombo.Text
		$script:MainForm_DeploymentStateCombo_SelectedItem = $DeploymentStateCombo.SelectedItem
		$script:MainForm_PackageTypeCombo = $PackageTypeCombo.Text
		$script:MainForm_PackageTypeCombo_SelectedItem = $PackageTypeCombo.SelectedItem
		$script:MainForm_ConfigMgrPkgActionCombo = $ConfigMgrPkgActionCombo.Text
		$script:MainForm_ConfigMgrPkgActionCombo_SelectedItem = $ConfigMgrPkgActionCombo.SelectedItem
		$script:MainForm_WebServiceDataGrid = $WebServiceDataGrid.SelectedCells
		if ($WebServiceDataGrid.SelectionMode -eq 'FullRowSelect')
		{ $script:MainForm_WebServiceDataGrid_SelectedObjects = $WebServiceDataGrid.SelectedRows | Select-Object -ExpandProperty DataBoundItem }
		else { $script:MainForm_WebServiceDataGrid_SelectedObjects = $WebServiceDataGrid.SelectedCells | Select-Object -ExpandProperty RowIndex -Unique | ForEach-Object { if ($_ -ne -1) { $WebServiceDataGrid.Rows[$_].DataBoundItem } } }
		$script:MainForm_WebSvcDesc = $WebSvcDesc.Text
		$script:MainForm_SecretKey = $SecretKey.Text
		$script:MainForm_ConfigMgrWebURL = $ConfigMgrWebURL.Text
		$script:MainForm_CustomPkgDataGrid = $CustomPkgDataGrid.SelectedCells
		if ($CustomPkgDataGrid.SelectionMode -eq 'FullRowSelect')
		{ $script:MainForm_CustomPkgDataGrid_SelectedObjects = $CustomPkgDataGrid.SelectedRows | Select-Object -ExpandProperty DataBoundItem }
		else { $script:MainForm_CustomPkgDataGrid_SelectedObjects = $CustomPkgDataGrid.SelectedCells | Select-Object -ExpandProperty RowIndex -Unique | ForEach-Object { if ($_ -ne -1) { $CustomPkgDataGrid.Rows[$_].DataBoundItem } } }
		$script:MainForm_CustomPkgPlatform = $CustomPkgPlatform.Text
		$script:MainForm_CustomPkgPlatform_SelectedItem = $CustomPkgPlatform.SelectedItem
		$script:MainForm_CurrentDownload = $CurrentDownload.Text
		$script:MainForm_richtextbox2 = $richtextbox2.Text
		$script:MainForm_ProgressListBox = $ProgressListBox.SelectedItems
		$script:MainForm_richtextbox3 = $richtextbox3.Text
		$script:MainForm_ReleaseNotesText = $ReleaseNotesText.Text
		$script:MainForm_ModernDriverDesc = $ModernDriverDesc.Text
		$script:MainForm_richtextbox5 = $richtextbox5.Text
		$script:MainForm_ModernDriverLabel = $ModernDriverLabel.Text
		$script:MainForm_AboutToolDesc = $AboutToolDesc.Text
		$script:MainForm_checkboxUseAProxyServer = $checkboxUseAProxyServer.Checked
	}

	
	$Form_Cleanup_FormClosed=
	{
		#Remove all event handlers from the controls
		try
		{
			$MSEndpointMgrLogo.remove_Click($MSEndpointMgrLogo_Click)
			$FindModelSelect.remove_Click($FindModelSelect_Click)
			$SelectAll.remove_Click($SelectAll_Click)
			$ClearModelSelection.remove_Click($ClearModelSelection_Click)
			$FindModel.remove_Click($FindModel_Click)
			$FindModel.remove_MouseEnter($FindModel_MouseEnter)
			$FindModel.remove_MouseLeave($FindModel_MouseLeave)
			$ModelSearchText.remove_KeyDown($ModelSearchText_KeyDown)
			$MakeModelDataGrid.remove_CurrentCellDirtyStateChanged($MakeModelDataGrid_CurrentCellDirtyStateChanged)
			$MakeModelDataGrid.remove_RowsAdded($MakeModelDataGrid_RowsAdded)
			$MakeModelDataGrid.remove_KeyPress($MakeModelDataGrid_KeyPress)
			$OSComboBox.remove_SelectedIndexChanged($OSComboBox_SelectedIndexChanged)
			$OSComboBox.remove_EnabledChanged($OSComboBox_EnabledChanged)
			$OSComboBox.remove_TextChanged($OSComboBox_TextChanged)
			$DownloadComboBox.remove_SelectedIndexChanged($DownloadComboBox_SelectedIndexChanged)
			$DownloadComboBox.remove_TextChanged($DownloadComboBox_TextChanged)
			$PlatformComboBox.remove_SelectedIndexChanged($PlatformComboBox_SelectedIndexChanged)
			$FindModelsButton.remove_EnabledChanged($FindModelsButton_EnabledChanged)
			$FindModelsButton.remove_Click($FindModelsButton_Click)
			$FindModelsButton.remove_MouseEnter($FindModelsButton_MouseEnter)
			$FindModelsButton.remove_MouseLeave($FindModelsButton_MouseLeave)
			$MicrosoftCheckBox.remove_CheckedChanged($MicrosoftCheckBox_CheckedChanged)
			$HPCheckBox.remove_CheckedChanged($HPCheckBox_CheckedChanged)
			$LenovoCheckBox.remove_CheckedChanged($LenovoCheckBox_CheckedChanged)
			$DellCheckBox.remove_CheckedChanged($DellCheckBox_CheckedChanged)
			$RefreshSoftPaqSelection.remove_Click($RefreshSoftPaqSelection_Click)
			$DownloadSoftPaqs.remove_Click($DownloadSoftPaqs_Click)
			$ResetSoftPaqSelection.remove_Click($ResetSoftPaqSelection_Click)
			$SelectAllSoftPaqs.remove_Click($SelectAllSoftPaqs_Click)
			$HPCatalogModels.remove_SelectedIndexChanged($HPCatalogModels_SelectedIndexChanged)
			$FindSoftPaq.remove_Click($FindSoftPaq_Click)
			$HPSoftpaqDataGrid.remove_CurrentCellDirtyStateChanged($HPSoftpaqDataGrid_CurrentCellDirtyStateChanged)
			$DownloadBrowseButton.remove_Click($DownloadBrowseButton_Click)
			$ScheduleJobButton.remove_Click($ScheduleJobButton_Click)
			$UseProxyServerCheckbox.remove_CheckedChanged($UseProxyServerCheckbox_CheckedChanged)
			$HideCustomCreation.remove_CheckedChanged($HideCustomCreation_CheckedChanged)
			$HideConfigPkgMgmt.remove_CheckedChanged($HideConfigPkgMgmt_CheckedChanged)
			$HideWebService.remove_CheckedChanged($HideWebService_CheckedChanged)
			$HideMDT.remove_CheckedChanged($HideMDT_CheckedChanged)
			$ZipCompressionCheckBox.remove_CheckedChanged($ZipCompressionCheckBox_CheckedChanged)
			$ZipCompressionCheckBox.remove_EnabledChanged($ZipCompressionCheckBox_EnabledChanged)
			$PackageBrowseButton.remove_Click($PackageBrowseButton_Click)
			$SpecifyCustomPath.remove_CheckedChanged($SpecifyCustomPath_CheckedChanged)
			$ConnectConfigMgrButton.remove_Click($ConnectConfigMgrButton_Click)
			$CreateFallbackButton.remove_Click($CreateFallbackButton_Click)
			$buttonConnectGraphAPI.remove_Click($buttonConnectGraphAPI_Click)
			$RefreshIntuneModels.remove_Click($RefreshIntuneModels_Click)
			$DeploymentShareGrid.remove_CurrentCellDirtyStateChanged($DeploymentShareGrid_CurrentCellDirtyStateChanged)
			$DeploymentShareGrid.remove_SelectionChanged($DeploymentShareGrid_SelectionChanged)
			$ImportMDTPSButton.remove_Click($ImportMDTPSButton_Click)
			$MDTScriptBrowseButton.remove_Click($MDTScriptBrowseButton_Click)
			$PackageGrid.remove_CurrentCellDirtyStateChanged($PackageGrid_CurrentCellDirtyStateChanged)
			$PackageGrid.remove_KeyPress($PackageGrid_KeyPress)
			$DeploymentStateCombo.remove_SelectedIndexChanged($DeploymentStateCombo_SelectedIndexChanged)
			$SelectNoneButton.remove_Click($SelectNoneButton_Click)
			$PackageTypeCombo.remove_SelectedIndexChanged($PackageTypeCombo_SelectedIndexChanged)
			$SelectAllButton.remove_Click($SelectAllButton_Click)
			$ConfigMgrPkgActionCombo.remove_SelectedIndexChanged($ConfigMgrPkgActionCombo_SelectedIndexChanged)
			$ConnectWebServiceButton.remove_Click($ConnectWebServiceButton_Click)
			$CustomPkgDataGrid.remove_CellContentClick($CustomPkgDataGrid_CellContentClick)
			$CustomPkgDataGrid.remove_CurrentCellDirtyStateChanged($CustomPkgDataGrid_CurrentCellDirtyStateChanged)
			$CustomPkgPlatform.remove_SelectedIndexChanged($CustomPkgPlatform_SelectedIndexChanged)
			$QuerySystemButton.remove_Click($QuerySystemButton_Click)
			$ImportExtractedDriveButton.remove_Click($ImportExtractedDriveButton_Click)
			$CustomExtractButton.remove_Click($CustomExtractButton_Click)
			$ImportCSVButton.remove_Click($ImportCSVButton_Click)
			$CreatePackagesButton.remove_Click($CreatePackagesButton_Click)
			$GitHubLaunchButton.remove_Click($GitHubLaunchButton_Click)
			$ResetDATSettings.remove_Click($ResetDATSettings_Click)
			$StartDownloadButton.remove_Click($StartDownloadButton_Click)
			$MainForm.remove_FormClosing($MainForm_FormClosing)
			$MainForm.remove_Load($MainForm_Load)
			$MainForm.remove_Shown($MainForm_Shown)
			$MainForm.remove_Load($Form_StateCorrection_Load)
			$MainForm.remove_Closing($Form_StoreValues_Closing)
			$MainForm.remove_FormClosed($Form_Cleanup_FormClosed)
		}
		catch { Out-Null <# Prevent PSScriptAnalyzer warning #> }
	}
	#endregion Generated Events

	#----------------------------------------------
	#region Generated Form Code
	#----------------------------------------------
	$MainForm.SuspendLayout()
	$LogoPanel.SuspendLayout()
	$SelectionTabs.SuspendLayout()
	$MakeModelTab.SuspendLayout()
	$PlatformPanel.SuspendLayout()
	$DriverAppTab.SuspendLayout()
	$ModelDriverTab.SuspendLayout()
	$XMLLoading.SuspendLayout()
	$OSGroup.SuspendLayout()
	$DeploymentGroupBox.SuspendLayout()
	$ManufacturerSelectionGroup.SuspendLayout()
	$OEMCatalogs.SuspendLayout()
	$tabcontrol2.SuspendLayout()
	$HPCatalog.SuspendLayout()
	$HPSoftPaqGridPopup.SuspendLayout()
	$CommonTab.SuspendLayout()
	$tabcontrol1.SuspendLayout()
	$tabpage1.SuspendLayout()
	$StoageGroupBox.SuspendLayout()
	$tabpage2.SuspendLayout()
	$SchedulingGroupBox.SuspendLayout()
	$ProxyGroupBox.SuspendLayout()
	$tabpage3.SuspendLayout()
	$groupbox4.SuspendLayout()
	$TabControlGroup.SuspendLayout()
	$ConfigMgrTab.SuspendLayout()
	$SettingsTabs.SuspendLayout()
	$ConfigMgrDPOptionsTab.SuspendLayout()
	$PackageCreation.SuspendLayout()
	$groupbox1.SuspendLayout()
	$PackageOptionsTab.SuspendLayout()
	$DPGroupBox.SuspendLayout()
	$DPSelectionsTabs.SuspendLayout()
	$DPointTab.SuspendLayout()
	$DPGroupTab.SuspendLayout()
	$FallbackPkgGroup.SuspendLayout()
	$IntuneTab.SuspendLayout()
	$panel1.SuspendLayout()
	$groupbox7.SuspendLayout()
	$groupbox6.SuspendLayout()
	$groupbox5.SuspendLayout()
	$MDTTab.SuspendLayout()
	$MDTSettingsPanel.SuspendLayout()
	$FolderStructureGroup.SuspendLayout()
	$MDTScriptGroup.SuspendLayout()
	$ConfigMgrDriverTab.SuspendLayout()
	$PackageUpdatePanel.SuspendLayout()
	$PackagePanel.SuspendLayout()
	$ConfigWSDiagTab.SuspendLayout()
	$WebDiagsPanel.SuspendLayout()
	$CustPkgTab.SuspendLayout()
	$PkgImporting.SuspendLayout()
	$CustomPkgPanel.SuspendLayout()
	$CustomPkgGroup.SuspendLayout()
	$groupbox2.SuspendLayout()
	$LogTab.SuspendLayout()
	$LogPanel.SuspendLayout()
	$AboutTab.SuspendLayout()
	$AboutPanelRight.SuspendLayout()
	$AboutPanelLeft.SuspendLayout()
	#
	# MainForm
	#
	$MainForm.Controls.Add($LogoPanel)
	$MainForm.Controls.Add($SelectionTabs)
	$MainForm.Controls.Add($ResetDATSettings)
	$MainForm.Controls.Add($StartDownloadButton)
	$MainForm.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
	$MainForm.AutoScaleMode = 'Dpi'
	$MainForm.BackColor = [System.Drawing.Color]::Gray 
	$MainForm.ClientSize = New-Object System.Drawing.Size(1264, 783)
	$MainForm.Cursor = 'Default'
	$MainForm.Font = [System.Drawing.Font]::new('Microsoft Sans Serif', '8.25', [System.Drawing.FontStyle]'Bold')
	#region Binary Data
	$MainForm.Icon = [System.Convert]::FromBase64String('
AAABAAUAEBAAAAEAIABoBAAAVgAAABgYAAABACAAiAkAAL4EAAAgIAAAAQAgAKgQAABGDgAAMDAA
AAEAIACoJQAA7h4AAOLfAAABACAAgC8DAJZEAAAoAAAAEAAAACAAAAABACAAAAAAAAAEAAAjLgAA
Iy4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACENCwAxHRsAJxIREzwpJ1tVRUOcPy0qnDckInk4
JiQpHQ4NBiUUEgAAAAAAAAAAAAAAAAAAAAAAAAAAAD8tKwA6KScBOiYlQllJSL6HfHv3g3Z1/Hls
aumdk5H0tKyr4rSsq5axqKcbsqmoAImBgQAAAAAAAAAAAEk4NwBaTU8AQS8tWGZXVeebko//gnd1
/5iOjP/GwcD/xcC//7WurPLBurjc1M/OjeHe3Qvd2dgAAAAAAGBRTwBDMTAARDIxP2BRT+WVi4f/
em5r/5GHhP+zraj/l46L/35zcf+Uioj8pJya7LixsK3Szs041NDPAAAAAABQPz4ASTc2EFVFQ7t/
c3D/em1q/3tua/+ck4//h3x4/4F1cvynn5vbpJ+j0bKtrdq+ubTpvLe1bKykowNuYF8ATz08AFFA
P1VlVlT5dGll/2haWP+BdnL/f3Rw/3pua+uZj4x8qqKbHi0tbz06O6GTlZGrq6+ooqWYj4wMDgxk
ABAPbSBQQ0qvX1JM/19TTf9nWlb/cGVg/3RoZOiFenZWvbawAoyEkAAZHLgAISTKSDk6xbeYkJSn
p56UEAAAhAAQD3CSXlVt/ntwaf9ZTEb/XFBK/19TTMB7bmtCr6ekApqQjQAAAAAAGxyUABobmBUk
JsDEc2uTsKicexEAAGwQGhmBxn53jP/Pysf/joSB+WVYU/9XSkJrVEdAAHdtZQAAAAAAAAAAABoa
hAAaGoE1IyOw4F9Yj6zBsU8HAwNwHyEhlth+d4/8xcG9/6aenN+rpKLwu7WzQrq0sgAAAAAAAAAA
ABUUbgBPUv8AGhuMiSUkqv9YT4F7DQmwAAcHcR4cHajRbWaS5q+oof+qo5/RoZmX0MG9ukTAu7gA
AAAAAAAAAAAaG38AGBh3Jyosqt06Ob/SV0xzHlFGdgAHBl8MFhitukZDrc6Yjofyo5uW7pqRjZSm
nppNnZSQAJBvMQAAAL0AExBOECcom6Q5OsH/UU61dxAf/wBzY0sAExXWABITpG8cHcrda2SSqJOJ
geyWjIfVkoiDbHdpYjVrW1E+WUxXeDQyjrwwMrv7PDqxr2dcgRRbUogAAAAAAA8QlQAPD4wRExTA
pBkb0MtPTKWfd29/yn50fOJyanvmV1KD9Tw7of8vMb73MzS3ozgvfB8zLpYAmW4AAAAAAAAjHwAA
FhfBABUWrxEVF8xxFhjMyR0fwN8lJrXrJyi1+yQmu/soKr/SMDPHYzc64wk2POwAJQAAAAAAAAAA
AAAAAAAAAAAAAABLS64AX16kAS8wqiosLbN5Kiu1oisstKErLbhpMTPLIEZL/wA2OPAAAAAAAAAA
AAAAAAAAAAAAAPwHAADwAwAA8AEAAOABAADAAAAAwAAAAIAwAACAcAAAAfAAAAHxAAAB4QAAAcMA
AIADAACABwAAwA8AAOA/AAAoAAAAGAAAADAAAAABACAAAAAAAAAJAAAjLgAAIy4AAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOiclAEMyMAQwHBonLhsYXzQhH4U3
JSKJOCYjZzgnJQ9CLywAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAEc1MwBUQ0ICOCUjNDckIpdPPz3ee25s+nZpZ9c8Kyi3QzIv2VNDQbFaSkh7TDw5
MAYAAAIhExIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD///8AQjAvAEY1Mww6JyZ2
SDY15oF1dP+yqqn/jIGA/2hZWPyNgoD8urKx/8zGxf/MxsX/vLWz56ienW6JfXwGlYqJAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAABFMzIASTg2Ej4rKplXRkX6npWS/7GrqP9vYmH/d2lo/7iy
sf/Rzcz/19PS/9fT0v7W0tHv39rZ6N7Z2OzX0tFovLOzAODc2wAAAAAAAAAAAAAAAAAAAAAAAAAA
AEs6OQBOPj0KQS8ulVpKSf2elJH/pp+a/2dZV/+AdHL/ubOv/8C7uP+/u7n/n5aV/3NmZf1oWljn
c2Zkyp2UkqLX09Kj3NjXK9vX1gDi394AAAAAAAAAAAAAAAAAWEhHAAAAAABGNDNvVENC+Y+Egf+e
lZH/bF5c/3hraf+ro5//sKmk/6qjnv94bGn/aVtZ/5SKiP+yrKr/urSz/7Gqqe+zrKuV0s7NW87L
yQTQzMsAAAAAAAAAAAAAAAAATDo5AE08OjFNPDvhe25r/5GHg/94a2j/Z1hW/5mPjP+gl5P/nJKO
/29hX/98b23/qqKe/7Suqve4sq7svriz8cC7uP/Au7nowLu6dr+6uBe+ubgAAAAAAAAAAABbS0oA
bF1cA007OpdkVFP/gXZy/35yb/9gUE7/gnZz/5CGgv+QhoL/cWVi/35xb/+hmJTgqaGciI2HkFhC
QWyeX1yBmKynpJ64sq3ztrCsuaigniqooJ0AAAAAAAAAAABUQ0IAVENCKlVEQ+RvYl//cmdj/2hb
V/9oWVf/gHVx/4N4dP92amb/dmpn/JOJhayakY0tvLWpAQAAAAEoKX4sLC+wnjM1tpeln6OPraah
5J+Xk0CpoZ0A+vr8AOfp9QALE5IIU0NDbl5PTP9lWVP/ZFlT/11PTP9uYV7/cmdj/3NoZP9xZWL7
hnx4lI+FgBCLgX0AlYuHAAAAAAApLMoAKi3LHCQn0sdGRsWRoJeS16WdmUamnpoAJiZ+ACkqgQUJ
CW6KQDZU3WFUTv9URz//WEtE/11QTP9mWlX/ZVlU+21hXeV/c2+clIqHDo2CfwAAAAAAAAAAAAAA
AAA5OZIAExj/AB4ftYUlJ9HWh36Ly5yTjVOZkIwAEBF1AAwNch8NDXTcT0dm/6Oalv93bGb/UUQ9
/15STv9ZTUX/Wk1G3G5iXTmMgH0Qd2lmAP///QAAAAAAAAAAAAAAAAAAAAAAGhuhAB0dnVcfIMvu
bWWP1ZSKf0+PhYEABgZzAAcHckYZGYT3YVly/8jDwP/Uz87/lYyJ/mJVUf9NQDj/TkA5pYiAegNs
YVoAAAAAAAAAAAAAAAAAAAAAAAAAAAAmJogAKCd/BhwcjHYeH8P1YVmO346CcjqGe3cAAABwAAcH
dGgjI5f/aF94/8C7t//Rzcz/uLGw6YB2c/ack4//dmtmcIZ8dwCtp6QAAAAAAAAAAAAAAAAAAAAA
AAAAAAAREXoAFBR7KR4ejt0gIL3/XVWE2It/ZBx8cm4AAABwAAgIeHonKKv9aWB99bStqP/Cvbv/
ubOx2YV7eODKxsX909DPT9LOzQAAAAAAAAAAAAAAAAAAAAAAAAAAADg3iwAQEIYAFhaAah4enP4i
ILX/XlRzoLquRQN4bmoAAAB1AAsLfHkiJLj5XVaI26Sclf+1r6r/uLKu4oV7d7Cxqqj7x8PBUMS/
vgAAAAAAAAAAAAAAAAAAAAAAAAAAABISbwANDGEVIiOTxi8xvf86Ob/YYFNfK1RHZQCoop0AAAB7
AAsLfmEcH7j8RkOpxJKHgPSpoZ3/raWh+52UkIyYj4vPta+rcbKsqAC9uLQAAAAAAAAAAAAAAAAA
GBdpAAAAAAEaGn15MDKx/T5A0f9NSayHAAD/AHhoUwAAAAAACgqBAAwMfDYXGa7xKCrTzHpvdsKZ
j4v/n5eT/6Obl82SiIRhopqVebewrAivqKQAAAAAAAAAAAAODVUAbW7/ABQUalIsLqfrNTjE/0hH
wON1aocxbWOMAAAAAAAAAAAAGBiKABERcAsSE6C2Gh3U+D47s46JfnfKkoiE/5aNif+ZkIyumI6L
QXpubBAAAAABFwoJBUs4MRpYR0JWODBbiSssouIyNcP/OTq+9FJKkmf//wAAtamNAAAAAAAAAAAA
RkahAAkKmAAPEJFGExW/7Bga2N1FQrFqi4B5noyBe+6PhYD/kYeD6Id7d716bWmnc2Zis2ldYtdQ
SXL5Nzeo/y4xxP80Nbj4ODKRfVxCAAVPPjwAAAAAAAAAAAAAAAAAAAAAABgXhgAdGjECERKqZBMV
yuwWGNTkKy3GklxXjIh0a3Wye3F103pyeOVvaHv2VlKB/zw8nf8sL8L/KSzA/zM1wtY1MaNmOSUd
CjgpQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAZGY8AGxllAhcYvEQUFs26FBbP+BkbyvUgIbzm
JSaw5icosPAlJrr7ISPG/yEjw/8pK7f3MjXEqjM34itDRqsAJyv4AAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAbGusAB8gzAAsLcoOISK8Wh0ev64bHMLZHB3C6CIjvfgjJLT7JSev6C4v
uLMxM89VLTHvCzAz4wAdIv8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AP//AABGR14AZmYyBFZXkyZDRKRXODipdDY3r3szNbpjMTPONC4w7Qs3ONIAGBz/AAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/8B/AP8ADwD+AAcA/AAHAPgAAwD4AAEA8AABAOAAAQDg
AAEAwAPBAIAH4QCAD+EAgB/BAIA/wQCAP8EAgD+DAIA/BwCAHwcAgAAPAMAADwDAAB8A4AB/APgA
/wD8A/8AKAAAACAAAABAAAAAAQAgAAAAAAAAEAAAIy4AACMuAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACWjY0AEAAAAEo5Nwk4JiMp
MB4bTzIfHWwzIB5xNSMgVzwqKBE4JiMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABeT00A////AEEv
LRo2IyFkMh8dsjwqKOFSQj/uSjk2vT8tKrA6KCXGNSMghygVEjscCgcZAAAAAgYBAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACpoqEA
PisqAEg2NQ47KCdnNiMh0Ug2NPx7bmz/sKin/66lpPhcTUrGPCon1lVFQ/NuX137eWxq83RnZdZj
VFKIRTUzIq2SjgAFAwIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAZ1lYAC8bGQBFMzEnOygmqz8sK/lyZGP/tK2s/8W/vv+Genn/Tj08/3FjYf+upqT/0szL
/9/b2v/k4N//4t7d/9LMy/+zqqnOlImHPuXh3wBkVVQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAGFSUAAmERAARjQyODwqKM1MOjn/kYaE/7+5t/+xqqn/ZFZU/1hHRv+h
mZf/zMjH/9PPzv/V0dD/2dXU/93Z2P7h3dz65eLh+eXh4P/X0dDYzsjHMc3HxgDb19YAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABaS0oAPiwrAEg2NTY/LCvVU0JA/5mPjP+2sKv/pJyY
/1pLSf9mV1X/samn/8O/vf/EwL7/yMTD/8rGxf+3sK//loyK9H9zccyHfHqvubKwn9/b2s/f29qr
3dnYDN7a2QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwry7AEc1NABMOzoiQjAvyFFAP/+U
iYb/qqKe/6CXk/9cTUv/aFlY/62lof+3saz/uLOu/7y3s/+wqaf/eW5s/1BAPv9aSkn+dGdl/X9z
cfh3a2nWf3NxgNPPzpXZ1dRd2tbVANfU0wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABTQ0IAV0dG
CkY1NKFMOjn/hnp4/52UkP+bko7/aFpX/19PTv+imJX/q6Of/62mof+wqqX/mI+L/11NS/9iUlH/
mY+M/7mzsP/Dvrz/xsLB/8bBwP+3sa/yraalftHNzHTQzMsVz8vKAAAAAAAAAAAAAAAAAAAAAAAA
AAAAbF5dADsoJwBNOzpeSDY193NlY/+Rh4P/koiE/3hsaf9VREP/j4WC/5+Wkv+hmJT/pZyY/4yB
fv9aSkn/e25s/6ykoP+0rqr/t7Gs/7q1r/68trL/vrm2/8K9vP/Cvbzjwr28cMS/vTrBvLsA////
AAAAAAAAAAAAAAAAAAAAAABVREMAVkZFGUo4N8xeTkz/hXp2/4Z7d/+DeHT/WEhG/3ZpZv+Uiob/
lIqH/5iPi/+Ifnr/X1BN/4J2dP+mnZn/qKCc662lobWPipOqf3uKqaahn5q5s63FubOv+by2s/+8
trOusaqoTcjDwQHIw8AAAAAAAAAAAAAAAAAAdmhnAEMwLgBRQD9pUD49/XRoZf96b2v/fXJu/2pc
Wf9dTUv/h3x4/4l+ev+Mgn7/h315/2RYVP99cW7/mpGO8Z2VkZuknJg12c+6BhERTS4YGFypIiRz
u0BAdWaxq6R4s62o8bWvqummn5tom5GPCKeenAAAAAAAAAAAAAAAAABgUU8AYVNRDVA/Pb5fT07/
cWZi/29kYP9wZWH/WUpI/3BjYP9+c2//f3Rw/4J3c/9tYV3/dGhl/5GHg9mTioZUnpaTBpmQjABE
RHkAVVr/AF1gyxI4O858LTDB5D5BuGarpJ2Jraah/6WdmYmBdnQLjoSBAAAAAAAwMHgANDR7AFxF
JABZSkg6U0NB8GhbV/9kWFP/ZlpV/2NXUv9bTEn/dGll/3JnY/92a2f/cmdj/25hXv+IfXrLi4F9
NHhtaACUiocAAAAAAAAAAAAAAAAAOTzWAEVHzgUjJ86cKCzc4WFesWKhmJLqp5+bmI2EgwKXjosA
AAAAACsrfwAlJnsIDA1wZUM4T5VaS0j/YVVO/1pNRf9dUUr/Wk1I/2JVUv9rYFv/aF1Y/2xhXf9t
YV3/gHVx0YuBfTCOhIAAjoeDAAAAAAAAAAAAAAAAAAAAAAAAAAAAGhykAB8goT0fIszzKy7WqZCG
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
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACvp6cAOygmAE4+PB5ALi2qOygn
/D0rKv9yZGL/tK2q/8O+vP/Dv77/qqOi/1xNTP83IyL/YFBP/6yjov/Py8r/0s/O/9PPzv/V0dD/
19PS/9nV1P/c2Nf/3trZ/+Dc2//i3t3/5eHg/+jk4//X0dDyvLS0Z21hXwGxqagAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGtd
XABGNDMATz49IUIwLrg8KSj/RDEw/4R4df+3sKz/ubSv/7y2sv+dlJH/Tz89/z0qKf98b27/vbe2
/8jEw//IxMP/ysbF/8zIx//Oysn/0c3M/9XR0P/X09L+2dXU79vX1t7f29rZ4d3c5eHd3Pnj397/
39va5dvW1jva1dQA4t7dAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAA////AEs6OQBRQUAaQzIwtD4rKv9HNTT/in98/7Grpv+wqqX/s62o/5eO
iv9MOzr/QzEv/4t/ff+9t7T/v7q3/8C7uf/Cvbz/xL++/8bCwf/KxsX/xsHA/6qjof+EeXf8YlRS
1U08OrlNPTufbmBee722tWrg3Nuo3trZ9t/b2q7e2tkN3trZAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVERDAFhIRw5GNDOgQC4t/0Y1NP+I
fHn/q6Kf/6mhnf+spaD/l46K/08/Pf9FMzL/jYJ//7exrP+2saz/ubOu/7q1sP+8t7P/v7q3/7+6
uP+gmJf/Z1lX/z8tK/84JSP/RjQy/1dHRf9fUE7/WUlH9kk4NcJJODZZ08/NXdrX1tva1tVq29fW
ANrW1QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABkVlUA
joOCAkk4N3pDMTD7RDMy/35xb/+jmpb/oZiU/6Sbl/+akY3/WUlH/0MyMf+Genj/sKml/66oo/+w
qqX/sqyn/7Suqf+4sq3/r6ik/3pta/9FNDP/QS8u/2dYV/+XjYv/ta6t/8K9vP/HwsH/xsHA/7ex
sP+UiojvbmFfbs3Ix03W0tG21dHQHtXR0AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAIyCgQA+LCsAUD8+RkY0M+tDMTD/b2Bf/5uSjv+Yj4v/mpGO/5qRjf9oWlj/
QzEw/3dqaP+poJz/p5+b/6mhnf+ro5//raah/7CppP+fl5L/Y1RS/0MxMP9fT07/mpCO/7q0sP+/
urf/v7q4/8C8uv/Cvrz/xMC//8fEwv/KxsX/ubOy8qKamV7QzMtq0MzKaM7KyQDRzcwAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFdHRQBcTEsWSjg3wUUzMv9dTUz/k4iF
/5GHg/+SiIT/lYuI/3pua/9HNTT/Y1RS/5+Vkv+flpL/oZiU/6Oalv+lnZn/qKCc/5aMiP9cTEr/
Szk4/3pta/+tpaH/ta+q/7Wvqv+2sKz/ubOu/7u1sf+9t7P/vrm2/8C7uf/Cvrz/xcC//8K+vNrC
vbtHxsLAh8zIxw7MyMcAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAcmZlAAAA
AABQPj11SDY1/U49PP+FeHb/i4F9/4uAfP+Og3//h3x4/1VFQ/9RPz7/j4SB/5iPi/+Yj4v/mpGN
/52UkP+gl5P/kYeD/11NS/9SQUD/iHt5/6ykoP+spKD/raWh/66oo/+xq6b6tq+p8Lexq++3saz5
uLOu/7q1sf+9t7T/v7m3/8C8uv/BvbuSt7GvZ8C7uTS/urgAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAVkVEAFpKSSNMOzrYSTc2/25gXv+HfHn/gndz/4V6dv+HfHj/a1xa/0o4
N/92aGb/lIqG/5CGgv+SiIX/lIqH/5eNiv+PhYH/YlRR/1ZGRP+Kfnz/pZ2Z/6Oalv+mnZn3qaGc
yq6moYiGgo9+VVNzk2hlfXGemZ1fubSuf7awq8q3saz7ubOu/7u1sf+9t7TlsauoZa+oplCdlZMA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB/c3IAAAAAAFNCQHtLOTj/V0ZF/4F1cv96
b2v/fHFt/390cP96bmr/VENB/1pJSP+MgH3/iX56/4uAfP+Ngn7/j4WB/42Df/9qXlr/V0pG/4V5
dv+dlJH/m5KO+Z+Wkrqkm5dUqqKfEwAAKQAkJF0cDAxKqg8PTugSEk7DFBREZnp2fSW2sKp2s62o
7LWvqv+3saz/tK6pmJ6Vk1jHwb8Ez8rIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABfT00A
YVFQGVA/PtBNOzr/cGFf/3dtaf9zaGT/dWpm/3htaf9nWVb/Tz08/3VnZf+Fenf/gndz/4V6dv+H
fHj/iX56/3RoZf9aTkr/e3Bs/5eNiv+TiYbfmI+Ma6GZlRCck48ApqGdAP///wAkJGIALS1fE0xN
qGY7PbbXMDGe+y0ufao6OmQesqylXa+opPGxqqb/sqynzZWMiWCZkI0MpZyaAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAABOPTsAWEhGWE8+PPpYR0b/d2to/2tgW/9tYl7/b2Rg/29kYP9YSUb/
WEhG/4B1cf96b2v/fHFt/35zb/+BdnL/em9r/2FVUf9wZGD/koeE/o2Df7+UioY16OjmAJ6VkgAA
AAAAAAAAAAAAAAAAAAAAbnT/AAAAsQA8QPAlLjHity0w1P8/QbyvgYC1GaWdmKOro5//raai7pqR
jWuGe3gPkYeEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHpubACUi4gDVUVEo1A/Pf9oWlf/a2Bb
/2RYU/9mW1b/aV5Z/2VYVP9TQ0H/aVtZ/3lua/9zaGT/dmtn/3htaf95bmr/a15a/2hbWP+Kf3z9
iX57qI6EgB2HfXgAnZWSAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHd52wAlKMAAMjTCMiIl0uIp
Ld/+OT3hdI2EgEqgl5P1qKCc/aignGZiVlgBlo2KAAAAAAAAAAAAAAAAAAAAAAA9PYcAOzuGByor
gxFlV1UeVERC2lREQv9uYV3/XlJL/19TTP9hVU//Y1dR/1xPS/9VRkP/c2dk/21iXv9tYl7/b2Rg
/3FmYv9vZGD/Z1pX/390cf6Jf3ukhHt3FYJ4cwDz8vMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAABMTJ4A//8AAR8hrosfI9X/JSnf40hIvUmRh4HLopmV/6WcmHudk48AAAAAAAAAAAAA
AAAAAAAAAAAAAAASEm8AGxt1OgoKbbQ5MV1+U0RC9V5PTP9mWVP/VklB/1lMRP9bT0f/XVBJ/1hL
Rv9cTkv/cmZi/2RZVP9nW1b/aV5Z/2tgW/9sX1v/dGdk/46Ega+Bd3MXfnRvALWxrAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGRmPACMjjzsdH7zwISTd/you3JSDeXWg
mpGN/56Wko+JfXkAycTCAAAAAAAAAAAAAAAAAE9PlwAAADQADg5wggAAaf8hHWb5U0ZG/mdZVv9X
SkP/T0I6/1NGPv9VSED/V0pD/1dKRv9jV1T/aV1X/15SS/9hVU//Y1dR/2tfWslxY1/lhXh1waSc
mSOrop8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANjaV
AC0tgRIcHaPLICPX/yIl3tJvZ4CSk4qF/5iPi5ZxY14At7KvAAAAAAAAAAAAAAAAADAwhgAzM4cP
CAhvwwECbf9APHf/V0lG/5WLiP+Rh4P/UUQ9/0s9Nf9PQTn/U0Y//1hMSP9oXFj/XlJK/1lMRP9b
Tkf/XlJL721iXD98b2w7hnp3Kl1OSwD28vAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAV1enAG1rhgMcHZOmICLN/x4g3u9YUpOgjoN9/5OJhpNvYV0Avrm3
AAAAAAAAAAAAAAAAABUVdwAbG3szAwNt7A4Pev9TTX//WUxH/7evrv/j397/saqm/2ZaVP9IOjL/
UEI8/1tPS/9oXFj/VUhA/1NGPv9VSED/W09HvXtxawx4bWYAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAe3u4AAAAWAAZGYqNISLD/xsd
3flHQpu0in53/I+EgIR+cW0A2dbVAAAAAAAAAAAAAAAAAAAAawASEnhiAABt/iIjkf9VTnz/YFRO
/8G7uv/e2tn/4d3c/9DLyf+RiIT/X1JN/11RTf9mWVT/TT83/00/OP9PQjr/WU1Fey0dFACTjIcA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB/
f7kAb2+wAX18swkREYKBIiO8/xgb2/xBPJ7Jhnpz+4l/e21+c28AAAAAAAAAAAAAAAAAkZHBAAAA
CwANDXePAAFw/zIzq/9TS3T/aV1X/8XAv//W0tH/19PS/9vX1v/e2tn/mZCN/l5STv9kV1P/RTYv
/0Y3L/9KPDX0WUxGQVJFPQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAABJSZsAQUCWCRwcg4EXF4GtIiS5/xYZ2f1GQZvdg3dw9oR6dk2A
dXEAAAAAAAAAAAAAAAAAQkKVAFNTnAYJCXayBQV1/zs8v/9SSWz/b2Ne/8S/vf/Oysn/0MzL/9PP
zv/X1NP8n5eV2l5RTvySiIX/jYR//1pMRv9JOjPcWk1HHVxPSAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAqKokAJiaGHhISftQjI4no
IyS7/xUX1f9QSJD7gHRt5oB2cSmAdnIAAAAAAAAAAAAAAAAAODiRADU1jxAGBnXKDQ19/z0/zv9V
TGz/cWZg/7+6uf/Hw8L/ycXE/8zIx//QzMv9qKGfu19STvSflpT/29fW/8jDwf+knJmxW05HB3Zq
ZQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AMDA2wAJCXUAFxd7TBkahvckJZL/ISPB/xMUzv9TSX3/fXFqwHtybgyEe3cAAAAAAAAAAAAAAAAA
KyuLACkpiRgFBXfXExSJ/z1A2/1cU3X6cGRf/7mzsP/BvLr/w769/8XBwP/IxMP/trCvrGJVUuGR
h4T/0s7N/9XR0P/Y1dSSxL++AN7b2gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAF9fpAD///8BEBB3lCEhlP8dHZP/HiDI/xMTwP9dUW7/eW5m
g2hbVwCOhoIAAAAAAAAAAAAAAAAAICCGAB8fhR0EBHfdGRqS/zU54/VZUX/XbWFb/7Gqpv+7tbH/
vbe0/7+6t//BvLv/wLu6r2lcWLaAdXL/x8PC/83JyP/OysmFy8bFANTQzwAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACMjfwAmJoAjERF52yMk
o/8eHpn/FhbN/x0Zqv9rX2XtdGlhPWleWAAAAAAAAAAAAAAAAAAAAAAAIyOIACIihxwFBXfcGxyX
/y8z5fhRTJe9aVxW+6aemv+1r6r/trCs/7mzrv+7tbH/v7m2zHtwbHlyZmP7t7Kw/8bCwf/IxMOF
w7++AM7LygAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAWFicAAAAKQAPD3F2ISKO/iIjqf8vMLP/KCrk/zcxmepxY1tdeHBnB3NoYgAAAAAAAAAAAAAA
AAAAAAAAMTGRAC8vkBYFBnrUGRqZ/ysv4v5CQbuwZ1pT6peOiv+vqKT/sKml/7Ksp/+0rqn/t7Gs
8Kafm1hrXVrJnpaT/8G8uv/BvbuUrKamAMbCwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHR13ACUleyQODnDXPUC//yYnpf9HSuD/Q0Xu/01Df6mR
eBMGfG5rAAAAAAAAAAAAAAAAAAAAAAAAAAAAODiXADk5lwwGBn3CFxiY/yks3f8wM9m5ZlpZwYZ7
d/+poZ3/qqKe/6yloP+up6L/sKql/7SuqYVuYV1cgnZz9rawrP+8trKwxL67BcK9ugAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA7O4cAYWKdBQ0Na5EnKJH/
Oj3Q/y8xp/9GSvj/QkDA91lKWVNCNFIAopaVAAAAAAAAAAAAAAAAAAAAAAAAAAAAWFeoALm51QIJ
CX6iExOS/ycq2f8kKODbX1d8iXVpZPqflpL/pJuX/6aemf+ooJz/qqOe/6ylodenn5sqcmVikZqS
jf+2sKvWubSvGbmzrwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AGhooQAAAEMAExNtVBMTc/FFSND/JSet/0NGzv8+Qe3/TkWIxYRyTBJ7bWcAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAA////AAAAcgANDYFyDQ2K/yQn0v8gJN37PDzIem1gWcONgn//nZWR/5+Wkv+i
mZX/pJuX/6aemv+poZ2GeW1qFoF2cqKknJj0sqynTK+ppAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAsbPLAAAAXgAeHnAzDAxo2Dw9sv8zNtX/MDKk/0JG8f9EQbb/g3d/
egAACwDc1tQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABMThgAYGIg4CgqE7iAixf8eIdz/
JCfeumlecWB4bGjvlIqH/5iPi/+akY7/nZSQ/6CXk/+imZXspZyYSWlcWQ+SiISGp5+bj7avqwew
qaUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABaW5MACwtiAB4fbiYKCmLEMTKZ/z9D
5f8jJaT/REfU/zk62P9jWYLGyL6qHLasqAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
ADMzlwA6OpoLCgqDtxgZsP8dH9v/HSDa+C8w2WNyZl18gndz+ZKIhP+Uiof/lo2J/5iPi/+bko7/
nZSQ1aGYlDZ7c28Cpp6aMLKrpxOwqKUAAAAAAAAAAAAAAAAAAAAAAAAAAACIfnwAJxEQAF5OTRJa
SEEmJiVoLgoKYL8tLY//Q0bk/yMmuf88PbP/Oj3n/0dAj+aOgHlESDY6APr29gAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAGpqtQAAAHoAEhKFWQ4PmPcbHNP/GhzZ/x8h2tJCQcUweGtk
g4Z7d/aOhID/kIaC/5KIhP+Uiof/lo2J/5mQjNSelZFdfnFwGioZGANINTQAAAAAAAAAAACjnZoA
AAAAAGZYVwdQQD8mSjk3aU8+O8JSQ0vhHRpd3S4vkf9BReL/JSjK/zIzof8/QuT/NjGh71xNWF//
//8By8O7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoKJMAMC+UDQwM
iq4TFLv/GBrX/xkb1/8gItmsTk3AGoB0bGKHfHjcin97/4yBff+OhID/kIaC/5KIhf+WjIj6kIWD
2HhraaNgUE94UEA+YUg3NV5JNzZqSDc2iEw7OrVYSEbialtb/GJZbP81Mm7/OTqi/z1A4/8lKNH/
LC2c/0FE2v8xLq/2QDFOcq6XJgN0ZE8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAB2drsABweEABgYiTIMDJzaFBXN/xYY1f8YGtX+ICLYpDQ44hiRhXAmiH14mIZ8
eO6IfXn/in97/42Cfv+PhID/kYeD/5OIhf+Og4D/hXl3/n5yb/5+cW7/hXl1/42CgP9+doP/TUl1
/y8wfv8+QLz/NDjm/yElzv8qK5r/QEPQ/y8ts/g4KlGDZk8QCFRBLQAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVlarAAAAbgAUFIxNDxCu5BMV0P8V
F9P/FhjU/h4g1r9AQtJRbW2RGol/cz6HfHaYhnt32Yd8ePWJfnr+i4B8/46Dfv+Rh4L+lYuG/JeN
iv6JgYb/aWN4/0A9af8qKnL/Njek/zk81/8oLOT/HiHB/ywtmv8/QtD8Li274jQnT4JROgkKSDUi
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAADY2lQDa1lIAFRWVTBETuNkSFM//ExXR/xQW0v8dH9L4MTLBzjg6nY04OXVcTkpkV2NcZm9t
ZWuMcWhvpG9ncLZkXW2/Uk1p0UNAaPksK2f/KSp+/zY3qv82OdL/KCzh/x8j2f8cHq3/MjSd/zw/
0/guMuWVPTiWJVA4AAdEMBMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA4N4UAAAD/AB0dnzAXGL6tEhTN9xET0P8SFND/
FBbS/x0fzv8oKr78LzCp7i4vlOErK4bbKyuA3iorgecrLInyLzCY+zM0r/8zNcn/LC7a/yIl3/8d
INv/GRzA/yIjmP86PK3/Njna5Ssv4m1BROIKNjnhAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgH6E
ACAhvgA2N6wNICHHWBUWzr4REs73ERLP/xET0P8SFNL/FRfT/xkb1P8eINP/ISPT/yIk1f8hI9f/
HiDa/xsd2/8ZG9v/GBrW/xcYv/8cHZv/MTKb/zo8xvguMd+zKy/gOXN25QFJTOIAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACBgNAAEhTLADw9zxEkJcpZFxjNqBITz9sREtDzERPR
/BET0f8SFNL/ExTT/hQW1P4XGNT/GBrO/xYXvv8VFqX/Hh+Q/zAxmf85Or35MDLZxicp318xNN0O
Gh3bAP///wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAx8aXAP//
twFsbHYWPz9zPDY2j2cuL6KPIiOqph0frbYcHa3BICGpyigpouAwMJj+LS6Q/y8wlP81Nqj7NjjE
5C4w2KwmKN5ZJyncFAAA3ABKTN4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAFFQdwBgX38AQUJuB1pbkSVbXKJbTU6ih0NEoqY+PqK6Ozunxjs7
r8o4OrrDNTbIrS8x1YgoKtxYIyXdJywu2gcDBdgAkJPlAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP///wBS
VP8AfX//AlNU/Qs5OvMTJyjsFyAh6hUkJusPGhzpBQAB8wASFfAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAD///+A//8AAP///AB//wAA///gAA//AAD//8AAA/8AAP//AAAA/wAA
//4AAAB/AAD//AAAAD8AAP/4AAAAPwAA//AAAAAfAAD/4AAAAB8AAP/AAAAADwAA/8AAAAAPAAD/
gAAAAAcAAP+AAAAABwAA/wAAAAAHAAD/AAAAgAMAAP4AAAPAAwAA/gAAD/ADAAD8AAAf+AMAAPAA
AD/4BwAA8AAAf/wHAADwAAD//AcAAOAAAf/8BwAA4AAH//4HAADgAA//+AcAAOAAD//4BwAAwAAP
//gHAADAAA//+AcAAMAAH//wDwAAwAAf//APAADAAB//8A8AAMAAH//gHwAAwAAP/8A/AADAAA//
wD8AAOAAD/+AfwAA4AAH/wB/AADgAAf4AP8AAPAAB8AA/wAA8AAAAAH/AAD4AAAAA/8AAPwAAAAH
/wAA/gAAAA//AAD/AAAAP/8AAP+AAAB//wAA/+AAAf//AAD/4AAH//8AAP/4AB///wAA//8B////
AAAoAAAA4gAAAL4BAAABACAAAAAAAHgTAwAjLgAAIy4AAAAAAAAAAAAA////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADd2toAzcnJAL+6uQC2sK8AtK6tALy1tQDGwcAA3NjY
ALGpqQCflpYAzcnIAKObmgCup6YAjIGBAMO+vQCup6YAqqKhAKujogCtpqUAs6yrAKefngCimZkA
npaVAKeengCjm5oAlIqJAJSKigCelZQAmZCPAIl+fQCxqqoApJybAJ6VlACZkZAAo5uaAKykowCl
nZwAgHR0AJ6WlACspKQAlIuKAJmQjwCck5IAnpWUAK+npwCup6YAqaGgAKegnwCupqcAj4WDAI+E
gwCgl5YArKSkAKaengCdlJMAqaGhAK+oqACSiIgArKSkAJOKiAC7tbUAg3l3ALy1tACGe3oAwry9
D5qQjx9uYF8snZSUSY+FhF9wY2JvWUlIe0w7OoNALyyHUUE/jHFlYqltYF6iRjUyiUIyL4dPPzyB
X1FQd3pvbWmdlJRZlYyLPXxxbyW7tbQXo5ycAZuTkgDJxMQAq6OjAMfCwgCyrKsAoJiXAMzIxwDA
uroAopqZAMjCwgCqo6IAmZCQAJ6WlgCPhoUAi4B/AKmhoQChmZcAqKCgAJOKiQCBdXQAqqKhAJuS
kQCflpYAjYOCAKujogCakZEAjoSDAJWLigCimZgAurSzAKignwCbk5IAl42NAKaengCknJwAsKmp
AJiPjwDEv74AnpaVAH1xcACWjo0A5OLiAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A
393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf
3d0A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA3draAM3JyQC/urkAtrCvALSurQC8tbUAxsHAANzY2ACxqakAn5aW
AM3JyACjm5oArqemAIyBgQDDvr0ArqemAKqioQCro6IAraalALOsqwCnn54AopmZAJ6WlQCnnp4A
o5uaAJSKiQCUiooAnpWUAJmQjwCJfn0AsaqqAKScmwCelZQAmZGQAKObmgCspKMApZ2cAIB0dACe
lpQArKSkAJSLigCZkI8AnJOSAJ6VlACvp6cArqemAKmhoACnoJ8ArqanAI+FgwCPhIMAoJeWAKyk
pACmnp4An5aVAK6npwC3sLEAmI6PAKukowyEencok4mIU19RT3VlV1WlSTk4wEQzMuI6KSbzMiAd
+SgUEf8mEg//JxQR/ygVE/8pFhT/KxgV/ygUEf8iDgv/Ig4L/ykWE/8qFhP/KBUS/ycTEP8lEQ7/
IxAN/ykWE/81IiD2Pi4r7kU0MspvY2Jsz8vLAK2mpgDHwsIAsqyrAKCYlwDMyMcAwLq6AKKamQDI
wsIAqqOiAJmQkACelpYAj4aFAIuAfwCpoaEAoZmXAKigoACTiokAgXV0AKqioQCbkpEAn5aWAI2D
ggCro6IAmpGRAI6EgwCVi4oAopmYALq0swCooJ8Am5OSAJeNjQCmnp4ApJycALCpqQCYj48AxL++
AJ6WlQB9cXAAlo6NAOTi4gDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A
393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN3a2gDNyckAv7q5ALawrwC0rq0AvLW1AMbBwADc2NgAsampAJ+WlgDNycgAo5ua
AK6npgCMgYEAw769AK6npgCqoqEAq6OiAK2mpQCzrKsAp5+eAKKZmQCelpUAp56eAKObmgCUiokA
lIqKAJ6VlACZkI8AiX59ALGqqgCknJsAnpWUAJmRkACjm5oArKSjAKWdnACAdHQAnpaUAKykpACU
i4oAmZCPAJyTkgCelZQAr6enAK6npgCpoaAAp6CfAK6mpwCPhYMAkIWEAKSbmgC0ra0AqqKjAJeO
jRmPhYRGc2dmflhJR7BDMzHbMiAd9ykVEv8qFhP/JhIP/ykWE/8pFhP/KhcU/ywYFv8tGRb/LRoX
/y0aF/8tGhf/LRoX/y0aF/8sGRb/LBkW/ywZFv8sGRb/LBkW/ywZFv8sGRb/KxgV/ysYFf8qFxT/
KRYT/ycTEP8lEg7/JBAO/21hX5qooJ8IzcnJALKsqwCgmJcAzMjHAMC6ugCimpkAyMLCAKqjogCZ
kJAAnpaWAI+GhQCLgH8AqaGhAKGZlwCooKAAk4qJAIF1dACqoqEAm5KRAJ+WlgCNg4IAq6OiAJqR
kQCOhIMAlYuKAKKZmAC6tLMAqKCfAJuTkgCXjY0App6eAKScnACwqakAmI+PAMS/vgCelpUAfXFw
AJaOjQDk4uIA393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A
393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADd2toAzcnJAL+6uQC2sK8AtK6tALy1tQDGwcAA3NjYALGpqQCflpYAzcnIAKObmgCup6YAjIGB
AMO+vQCup6YAqqKhAKujogCtpqUAs6yrAKefngCimZkAnpaVAKeengCjm5oAlIqJAJSKigCelZQA
mZCPAIl+fQCxqqoApJybAJ6VlACZkZAAo5uaAKykowClnZwAgHR0AJ6WlACspKQAlIuKAJmQjwCc
k5IAnpWUAK+npwCup6YAqaGgAKiioQC0rK0AlYuKAI+FgwqMgoE7d2tqf1JCQbg7KSfsLBgV/ygU
Ef8pFRL/KxcU/ywaF/8uGxn/LhsZ/y4bGP8uGxj/LhsY/y4bGP8uGxj/LRoY/ywaGP8tGhf/LRoX
/y0aF/8tGhf/LRoX/y0aF/8sGRb/LBkW/ywZFv8sGRb/LBkW/ywZFv8sGRb/KxgV/ysYFf8rGBX/
KxgV/yoXFP8iDgv/Szs5tLq0sxm1r64AoJiXAMzIxwDAuroAopqZAMjCwgCqo6IAmZCQAJ6WlgCP
hoUAi4B/AKmhoQChmZcAqKCgAJOKiQCBdXQAqqKhAJuSkQCflpYAjYOCAKujogCakZEAjoSDAJWL
igCimZgAurSzAKignwCbk5IAl42NAKaengCknJwAsKmpAJiPjwDEv74AnpaVAH1xcACWjo0A5OLi
AN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A
393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA3draAM3J
yQC/urkAtrCvALSurQC8tbUAxsHAANzY2ACxqakAn5aWAM3JyACjm5oArqemAIyBgQDDvr0Arqem
AKqioQCro6IAraalALOsqwCnn54AopmZAJ6WlQCnnp4Ao5uaAJSKiQCUiooAnpWUAJmQjwCJfn0A
saqqAKScmwCelZQAmZGQAKObmgCspKMApZ2cAIB0dACelpQArKSkAJSLigCZkI8AnJOSAJ6VlACw
qakAtK2sALCpqACknZwSjIGCT15PTp0/LivXMR4b/ykVEv8qFxT/LBoY/y8cGv8vHBr/LxwZ/y8c
Gf8vHBn/LxwZ/y4cGf8vHBn/LhsZ/y4bGP8uGxj/LhsY/y4bGP8uGxj/LRoY/y0aF/8tGhf/LRoX
/y0aF/8tGhf/LRoX/y0aF/8sGRb/LBkW/ywZFv8sGRb/LBkW/ywZFv8sGRb/KxgV/ysYFf8rGBX/
KxgV/yQRDv87KijSlIuJMamhoADMyMcAwLq6AKKamQDIwsIAqqOiAJmQkACelpYAj4aFAIuAfwCp
oaEAoZmXAKigoACTiokAgXV0AKqioQCbkpEAn5aWAI2DggCro6IAmpGRAI6EgwCVi4oAopmYALq0
swCooJ8Am5OSAJeNjQCmnp4ApJycALCpqQCYj48AxL++AJ6WlQB9cXAAlo6NAOTi4gDf3d0A393d
AN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A
393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wDf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN3a2gDNyckAv7q5ALaw
rwC0rq0AvLW1AMbBwADc2NgAsampAJ+WlgDNycgAo5uaAK6npgCMgYEAw769AK6npgCqoqEAq6Oi
AK2mpQCzrKsAp5+eAKKZmQCelpUAp56eAKObmgCUiokAlIqKAJ6VlACZkI8AiX59ALGqqgCknJsA
npWUAJmRkACjm5oArKSjAKWdnACAdHQAnpaUAKykpACUi4oAmZCPAKCXlgCmnZ0ArKSkDY+FhE1h
U1GfQS8t4y0aGP8qFhX/LRoY/y8cGv8wHRr/MB0a/zAdGv8wHRr/MB0a/y8dGv8vHBr/LxwZ/y8c
Gf8vHBn/LxwZ/y8cGf8uGxn/LhsZ/y4bGP8uGxj/LhsY/y4bGP8tGhj/LBkX/ysYFf8oFRL/JxMQ
/yURDv8jEA3/Ig8M/yIOC/8iDwz/Ig8M/yIPDP8iDwz/Ig8M/yIPC/8hDgv/IQ0K/yANCv8iDgv/
HgoG/ysZFuyJfn1O0s7OAMC7uwCimpkAyMLCAKqjogCZkJAAnpaWAI+GhQCLgH8AqaGhAKGZlwCo
oKAAk4qJAIF1dACqoqEAm5KRAJ+WlgCNg4IAq6OiAJqRkQCOhIMAlYuKAKKZmAC6tLMAqKCfAJuT
kgCXjY0App6eAKScnACwqakAmI+PAMS/vgCelpUAfXFwAJaOjQDk4uIA393dAN/d3QDf3d0A393d
AN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A
393dAN/d3QDf3d0A393dAN/d3QD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADd2toAzcnJAL+6uQC2sK8AtK6tALy1
tQDGwcAA3NjYALGpqQCflpYAzcnIAKObmgCup6YAjIGBAMO+vQCup6YAqqKhAKujogCtpqUAs6yr
AKefngCimZkAnpaVAKeengCjm5oAlIqJAJSKigCelZQAmZCPAIl+fQCxqqoApJybAJ6VlACZkZAA
o5uaAKykowClnZwAgHR0AJ6WlACtpaUAmZCQAKCYlwCIfXw0bV9diEQzMdouGRn/KhYV/y4bGP8x
Hhr/MR4b/zEeG/8wHhz/MB0c/zEdG/8wHRv/MB0a/zAdGv8wHRr/MB0a/y8cG/8wHRr/LxwZ/y8c
Gf8vHBn/LxwZ/y4bGP8sGRf/KRYT/yUSD/8kEA3/JxMQ/y0aF/81IyD/QjAu/1A/Pv9eT03/bV1c
/3lraeqDdnTji3595JKFhOSWiojklYmI5JWIh+SShYTjj4KB4oh7eeF4a2nfalta3ltLSd9GNTPn
Piwp5Y6Eg17IxMQBo5uaAMjCwgCqo6IAmZCQAJ6WlgCPhoUAi4B/AKmhoQChmZcAqKCgAJOKiQCB
dXQAqqKhAJuSkQCflpYAjYOCAKujogCakZEAjoSDAJWLigCimZgAurSzAKignwCbk5IAl42NAKae
ngCknJwAsKmpAJiPjwDEv74AnpaVAH1xcACWjo0A5OLiAN/d3QDf3d0A393dAN/d3QDf3d0A393d
AN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A
393dAN/d3QDf3d0A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA3draAM3JyQC/urkAtrCvALSurQC8tbUAxsHAANzY
2ACxqakAn5aWAM3JyACjm5oArqemAIyBgQDDvr0ArqemAKqioQCro6IAraalALOsqwCnn54AopmZ
AJ6WlQCnnp4Ao5uaAJSKiQCUiooAnpWUAJmQjwCJfn0AsaqqAKScmwCelZQAmZGQAKObmgCspKMA
pZ2cAIJ2dgCknZsAq6OjEHRoZ1pWRkW7MyAd+CsXFP8uGxj/MR4b/zIeHf8yHh7/Mh4c/zIfHP8x
Hhv/MR4b/zEeG/8xHhv/MR0c/zEeG/8wHRv/MB0a/zAdGv8wHRr/MB0a/y8dGf8sGRf/KBQS/yYS
D/8oFRL/MyAe/0c2NP9iUlH/gHJx8JyRj+q2q6qzycC/odjQz4Th2tpJ6eLiSu3m50nz7OwT8+zs
CPPs7Aj17u4G7OXlAvDp6QD38fEA7+npANTMzAjAtrYO2tPTGdzW1iLTy8wkxb69KKOZmDF+cnEz
p6CgCaCXlgDSzc0AsauqAJ+WlgCjnJwAkIiHAIyBgACpoaEAoZmXAKigoACTiokAgXV0AKqioQCb
kpEAn5aWAI2DggCro6IAmpGRAI6EgwCVi4oAopmYALq0swCooJ8Am5OSAJeNjQCmnp4ApJycALCp
qQCYj48AxL++AJ6WlQB9cXAAlo6NAOTi4gDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393d
AN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A
393dAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wDf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN3a2gDNyckAv7q5ALawrwC0rq0AvLW1AMbBwADc2NgAsampAJ+W
lgDNycgAo5uaAK6npgCMgYEAw769AK6npgCqoqEAq6OiAK2mpQCzrKsAp5+eAKKZmQCelpUAp56e
AKObmgCUiokAlIqKAJ6VlACZkI8AiX59ALGqqgCknJsAnpWUAJmRkACjm5oAsKinAK2lpQB8cHAf
bmJffEUzMd0uGhj/LRkX/zEeHf8zHx7/Mh8d/zMgHf8yHxz/Mh8c/zIeHP8yHh3/MR4d/zIeHP8x
Hhv/MR4b/zEeG/8xHhv/MR0c/zEdHP8vHBn/KxcU/ycTEP8pFRL/OCYk/1dGRv9+cG//pZmY9ca8
vMXd1dSW6+PjU+/o6Bru6OgO7efnAO3l5QDq4+QA6OHhAOPb2wDk3d0A2NDQANXOzgDb1tUAwLm4
AJyTkR6EeHdFg3d2gmRWVLFBMS7EMR8c0DooJeE7KSfwOykn8D0rKe8/LyzlOyknzz0rKc5MPDrC
Y1RTtmdaWI16bm5ugHV1R4yCgSWKf34FsqurAKegngCspKQAlIuKAIF1dACqoqEAm5KRAJ+WlgCN
g4IAq6OiAJqRkQCOhIMAlYuKAKKZmAC6tLMAqKCfAJuTkgCXjY0App6eAKScnACwqakAmI+PAMS/
vgCelpUAfXFwAJaOjQDk4uIA393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393d
AN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADd2toAzcnJAL+6uQC2sK8AtK6tALy1tQDGwcAA3NjYALGpqQCflpYAzcnIAKOb
mgCup6YAjIGBAMO+vQCup6YAqqKhAKujogCtpqUAs6yrAKefngCimZkAnpaVAKeengCjm5oAlIqJ
AJSKigCelZQAmZCPAIl+fQCxqqoApJybAJ6VlACdlZQAqqKhAJmQjjBnWVeZOSYm6S4ZGP8wHBr/
NCEd/zMgHf8zIB3/Mh8e/zIeHv8zHx//MyAd/zIfHP8yHxz/Mh8c/zEeHf8xHh3/MR4d/zIfHP8y
Hxv/LxwZ/ysXFP8mEw//MBwa/0w7Ov94amj/qJyb/87FxP/l3t7/7efn/+3o51jq5eUA6OHhAObf
3gDl3t4A5d7eAOLc2wDZ0dEA2tTTAM/KyACyq6oA2NLTAKyjohyWi4pXcGRinkU1Msg2JCH1KBUS
/yIPDP8iDgv/JhIP/ygVEv8nFBH/JxQR/ycUEf8nFBH/JxQR/ygVEv8nFBD/JREO/yIPC/8kEA3/
JhMQ/ygVEv80Ih/2PSsp0ltNS6p3a2ltlYyMMpaNjAaHfHsAr6emAJyTkgCflpYAjYOCAKujogCa
kZEAjoSDAJWLigCimZgAurSzAKignwCbk5IAl42NAKaengCknJwAsKmpAJiPjwDEv74AnpaVAH1x
cACWjo0A5OLiAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393d
AN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA3draAM3JyQC/urkAtrCvALSurQC8tbUAxsHAANzY2ACxqakAn5aWAM3JyACjm5oArqemAIyB
gQDDvr0ArqemAKqioQCro6IAraalALOsqwCnn54AopmZAJ6WlQCnnp4Ao5uaAJSKiQCUiooAnpWU
AJmQjwCJfn0AsaqqAKignwCknJsAioB/N15QTqI4JiP2LRoW/zIfHP80IB7/NCAf/zQgH/80IR7/
NCEe/zMgHf8zIB3/Mx8d/zIfHv8yHx7/MyAd/zMgHf8yHxz/Mh8c/zEeG/8rGBf/JxMS/zMgHv9V
RUL/iXt6/7uxsf/d1tb/6+Xl/+zn5v/n4+L/5ODf/+Pf3v/j396z49/eRePf3gvj394A5ODfAN/b
2gDZ1NMAv7m4ANHMywC0rawmfXJwZl1OTLg7KifwKRYT/yMPDP8nExD/KRYT/ysYFf8sGRb/LBkW
/ysYFf8rGBX/KxgV/ysYFf8rGBX/KxgV/ysYFf8rGBX/KxgV/ysYFf8rGBX/KxgV/ysYFf8qFxT/
KRYT/ygUEf8jDwz/JRIP/y4cGftDMzDPVUVEjJOJiEaakZAIp5+fAI+FhACro6IAmpGRAI6EgwCV
i4oAopmYALq0swCooJ8Am5OSAJeNjQCmnp4ApJycALCpqQCYj48AxL++AJ6WlQB9cXAAlo6NAOTi
4gDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393d
AN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wDf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN3a2gDN
yckAv7q5ALawrwC0rq0AvLW1AMbBwADc2NgAsampAJ+WlgDNycgAo5uaAK6npgCMgYEAw769AK6n
pgCqoqEAq6OiAK2mpQCzrKsAp5+eAKKZmQCelpUAp56eAKObmgCUiokAlIqKAJ6VlACZkI8AjIGA
ALmysgCUiokzX1BNojYkIvguGRj/Mh8f/zUhIP81Ih//NSIe/zQhHv80IB7/Mx8f/zMgIP80IB//
NCEe/zQhHf8zIB3/Mx8e/zIfHv8zHx7/MBwb/yoWE/8vHBn/Tj07/4V4d/++s7T/4NrZ/+zn5v/o
4+L/4d3d/9/c2v/f3Nv/4Nzb/+Hd3P/h3dz/4t7d/+Pf3v/j397h5ODfmevn5mPm4+IKysXEHI6E
glthUlC5OCYj9CgVEv8lEQ//KRYU/ywZFv8tGhf/LRoX/y0aF/8sGRb/LBkW/ywZFv8sGRb/LBkW
/ysYFf8rGBX/KxgV/ysYFf8rGBX/KxgV/ysYFf8rGBX/KxgV/ysYFf8rGBX/KxgV/ysYFf8rGBX/
KxgV/ysYFf8qFhP/JxMQ/yUSD/8qFxT/QjEvzm1fXYCFenknsqqqAJ+WlgCOhIMAlYuKAKKZmAC6
tLMAqKCfAJuTkgCXjY0App6eAKScnACwqakAmI+PAMS/vgCelpUAfXFwAJaOjQDk4uIA393dAN/d
3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393d
AN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADd2toAzcnJAL+6uQC2
sK8AtK6tALy1tQDGwcAA3NjYALGpqQCflpYAzcnIAKObmgCup6YAjIGBAMO+vQCup6YAqqKhAKuj
ogCtpqUAs6yrAKefngCimZkAnpaVAKeengCjm5oAlIqJAJSKigCgl5YAoZiXAIB0cyRrXV6ZNyQj
9y8bGP81Ih7/NSIf/zQiIP81ISH/NSAh/zUhIP81Ih//NSIe/zQhHv80IB//MyAf/zQgH/80IB//
NCEe/zMgHf8tGhf/KhYU/zwqKf9wYWD/saal/93W1v/s5ub/5uHg/9/b2v/d2dj/3dnY/93Z2P/e
2tn/3trZ/97a2f/f29r/39va/+Dc2//i397/6ufm/+Xi4f++t7b/em5s3kEwLu4pFRP/JhMQ/ysY
Ff8uGxj/LhsY/y0bGP8tGhj/LRoY/y0aF/8tGhf/LRoX/y0ZF/8sGRb/LBkW/ywZFv8sGRb/LBkW
/ysYFf8rGBX/KxgV/ysYFf8rGBX/KhcU/yoXFP8qFxT/KhcU/yoXFP8qFxT/KxgV/ysYFf8rGBX/
KxgV/ysYFf8rGBX/KhcU/ycTEP8jEAz/MR8c81xOTKeGe3o9lIqJAJmPjwCimZgAurSzAKignwCb
k5IAl42NAKaengCknJwAsKmpAJiPjwDEv74AnpaVAH1xcACWjo0A5OLiAN/d3QDf3d0A393dAN/d
3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393d
AN/d3QDf3d0A393dAN/d3QDf3d0A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA3draAM3JyQC/urkAtrCvALSurQC8
tbUAxsHAANzY2ACxqakAn5aWAM3JyACjm5oArqemAIyBgQDDvr0ArqemAKqioQCro6IAraalALOs
qwCnn54AopmZAJ6WlQCnnp4Ao5uaAJSLigCakJAAmZCPEXJlY3w7KSbpLhoZ/zQfIP81ISL/NiIi
/zYjIf82IyD/NSMf/zUiIP80ISH/NSEh/zUhIf81Ih//NSIe/zQiHv80IR7/Mh8e/ywYF/8tGRj/
Tz48/5GEg//PxsX/6uTj/+bh4f/d2dj/2dbV/9rW1f/a1tX/29fW/9zY1//c2Nf/3NjX/93Z2P/d
2dj/3dnY/+Dc2//n5OP/39va/6ujof9iVFL/MB4b/yUSD/8qFxT/LxwZ/y8cGf8vHBn/LhsZ/y4b
GP8uGxj/LhsY/y4bGP8tGhj/LRoX/y0aF/8tGhf/LRkX/ywZFv8sGRb/KhcU/ycUEf8lEQ7/Iw8M
/yEOC/8iDwz/JBAN/yUSD/8nFBH/KBUS/ygVEv8oFRL/JhIQ/yQQDf8iDwz/IQ4L/yIOC/8kEA3/
JhMQ/ykWE/8rGBX/KxgV/ykWE/8kEA3/KRYT/k8/PbKCdnY/qKCfAL+5uACooJ8Am5OSAJeNjQCm
np4ApJycALCpqQCYj48AxL++AJ6WlQB9cXAAlo6NAOTi4gDf3d0A393dAN/d3QDf3d0A393dAN/d
3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393d
AN/d3QDf3d0A393dAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wDf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN3a2gDNyckAv7q5ALawrwC0rq0AvLW1AMbBwADc
2NgAsampAJ+WlgDNycgAo5uaAK6npgCMgYEAw769AK6npgCqoqEAq6OiAK2mpQCzrKsAp5+eAKKZ
mQCelpUAp56eAKefngCWjYsAgHRyWEMwMdMxHR3/NSEf/zckIf82JCH/NiIg/zUiIf82ISP/NiIi
/zYjIP82IyD/NiMg/zUiH/80ISD/NSAh/zUhIf8zIB3/LBgV/zEeG/9gUE7/qZ2d/97X1v/p5OP/
39va/9jU0//X09L/19PS/9jU0//Y1NP/2dXU/9rW1f/a1tX/29fW/9vX1v/b19b/3trZ/+bi4f/b
19b/opiX/1ZGRP8sGRb/JxQR/y8bGP8wHRr/Lx0a/y8cGv8vHBn/LxwZ/y8cGf8vHBn/LhsZ/y0b
GP8uGxj/LhsY/y4bGP8sGRb/KRYT/yUSD/8jEAz/JRIP/zAdGv9DMS7/WEdF/21eXP+Bc3L/koaE
/6GVlP+roKD/sqen/7Wqqv+1qqr/s6mo/62iof+jl5b/lIiH/4J1dP9tX13/V0dF/0AvLP8tGhf/
Iw8M/yEOCv8lEQ7/KRYT/yoXFP8lEg7/KhgV/FZGRaumnp0wr6inAJ2VlACXjY0App6eAKScnACw
qakAmI+PAMS/vgCelpUAfXFwAJaOjQDk4uIA393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d
3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393d
AN/d3QD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADd2toAzcnJAL+6uQC2sK8AtK6tALy1tQDGwcAA3NjYALGpqQCf
lpYAzcnIAKObmgCup6YAjIGBAMO+vQCup6YAqqKhAKujogCtpqUAs6yrAKefngCimZkAn5eWAK2l
pQCZkI8tU0NArDUiH/80IB7/NiMj/zciJP83IyP/NyQi/zckIf83JCD/NiMh/zUiIf81IiL/NiIi
/zYjIf82IyD/NiMf/zMgHf8rFxb/NSIh/2pbWv+3rKz/5N3d/+bh4P/Z1dT/1NDP/9TRz//W0dD/
1tLR/9bS0f/X09L/19PS/9fT0v/Y1NP/2NTT/9nV1P/a1tX/4t/e/9vX1v+jmpn/VURD/ysYFf8q
FhP/MB0a/zAeG/8wHRv/MR0b/zAdGv8wHRr/Lx0a/zAdGv8vHBn/LxwZ/y8cGf8uHBn/LBkX/ygV
Ev8kEA3/KBUS/zwrKP9bSkn/gXNy/6ebm//Fu7v/2NDQ/+Td3f/s5uX/7+rq//Hs6//w6+z/8evs
//Ds6//x7Oz/8e3s//Ht7f/y7u7/8+/u//Tw7//z7+7/7+rq/+fh4P/Z0tL/w7q6/6CUk/91Z2X/
TDw6/y8cGf8hDQr/IxAN/ygUEf8kEA3/Lx0a9WpeXIOck5MOnJOTAKaengCknJwAsKmpAJiPjwDE
v74AnpaVAH1xcACWjo0A5OLiAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d
3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA3draAM3JyQC/urkAtrCvALSurQC8tbUAxsHAANzY2ACxqakAn5aWAM3JyACj
m5oArqemAIyBgQDDvr0ArqemAKqioQCro6IAraalALOsqwCnn54App6eAKCXlwZ2aWh1PSkq8DId
Hf83JCL/OCUi/zglIv83JCL/NiMj/zciI/83IyP/NyMi/zckIf83JCH/NiMh/zUiIf81ISP/NSAh
/y0ZGP82IyD/bV5c/7yzsv/n4eD/5N7d/9bR0f/Rzcz/0s7N/9PPzv/U0M//1NDP/9XR0P/V0dD/
1dHQ/9bS0f/X09L/19PS/9fT0v/d2tn/3dnY/62lpP9cTUv/LRkX/yoXFP8xHRz/Mh4d/zEeHP8x
Hhv/MR4b/zEdHP8xHRz/MB0a/zAdGv8wHRr/MBwa/y4bGf8qFhP/JREO/y8cGf9MOjn/emxr/6yh
oP/QyMf/5+Df/+7o6P/t6ej/6ubm/+nl5P/n4+P/5+Pi/+fj4v/o5OP/6OTj/+jk5P/p5OT/6eTk
/+nl5f/q5uX/6+fl/+vn5v/s6Of/7Ono/+7q6f/v6+r/8e7t//Tw7//18vH/8+7u/+Pd3P/Cubn/
joKB/1VEQv8uGxj/IQ0K/yMQDf8iDgv/QzIwzIF2dUKupqYApp6eALCpqQCYj48AxL++AJ6WlQB9
cXAAlo6NAOTi4gDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d
3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN3a2gDNyckAv7q5ALawrwC0rq0AvLW1AMbBwADc2NgAsampAJ+WlgDNycgAo5uaAK6npgCM
gYEAw769AK6npgCqoqEAq6OiAK2mpQC0rq0AraemAJOJiDFSQkC/MR4b/zYiIP84JCT/NyMl/zgj
JP84JCP/OCUi/zglIv84JCL/NyMj/zciJP83IiP/NyMi/zckIf82IyD/LxsZ/zIeHv9oWVn/vLKy
/+ji4v/h3Nr/0s7M/8/Lyf/QzMv/0c3M/9HNzP/Szs3/0s7N/9LOzf/Tz87/08/O/9TQz//U0M//
1dHQ/9nV0//f29r/vrm3/21fXf8wHRv/KhcV/zEeHP8yHx3/Mh8c/zIfHP8xHhz/MR4c/zEeG/8x
Hhv/MR4b/zAdHP8xHRz/LRoX/ycTEP8rGBX/STg2/4J0c/+5r67/39jY/+3o6P/r5+b/5+Pi/+Tg
3//j397/49/e/+Pg3//j4N//5ODf/+Xh4P/l4eD/5uLh/+bi4f/n4+L/5+Pi/+jj4//o5OP/6OTk
/+jk5P/p5eT/6ebl/+rm5f/r5+b/6+fm/+zo5//t6ej/7uro/+7q6v/w7Oz/9PDw//by8v/q5eX/
wbi3/39ycP8+LCn/Ig8M/x8LCP8qFxX6b2Jgg6Obmwi1r68AmI+PAMS/vgCelpUAfXFwAJaOjQDk
4uIA393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d
3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADd2toA
zcnJAL+6uQC2sK8AtK6tALy1tQDGwcAA3NjYALGpqQCflpYAzcnIAKObmgCup6YAjIGBAMO+vQCu
p6YAqqKhAKujogCyq6oAtrCuA3hsanQ6JyfyMx4f/zklJP85JiP/OSYj/zgmI/83JSP/OCMk/zcj
JP84JCP/OCUi/zglIv83JCL/NyQj/zYiI/8yHR3/Lxsa/11OS/+1qqn/5+Hg/+Db2v/Py8r/zMjH
/83Jyf/Oysn/z8vK/8/Lyv/QzMv/0MzM/9HNzP/Szs3/0s7M/9LOzf/Szs3/08/P/9vY1//Py8r/
hnt5/zsoJ/8qFxX/Mh8d/zMhHf8yIB3/Mh8e/zIfHv8zIB3/Mh8c/zIfHP8xHxz/MR4d/zEeG/8s
GRb/JhMR/zckI/9uXl3/r6Sj/97X1//s5ub/6OPi/+Hd3P/f29r/4Nzb/+Dc2//h3dz/4d3c/+Le
3f/i3t3/49/e/+Pf3v/j397/49/e/+Tg3//l4eD/5eHg/+bi4f/m4uH/5+Pi/+fj4v/o5OP/6OTj
/+jk5P/o4+T/6eTk/+nl5f/q5uX/6+fm/+vn5v/s6Of/7Ojn/+3p6P/u6un/8Ozr//Tx8f/18fD/
3NXV/5eLiv9JODX/IA0K/x4KB/9HNzW5qaGhJJ2VlQDEv74AnpaVAH1xcACWjo0A5OLiAN/d3QDf
3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d
3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA3draAM3JyQC/urkA
trCvALSurQC8tbUAxsHAANzY2ACxqakAn5aWAM3JyACjm5oArqemAIyBgQDDvr0ArqemAKqioQC0
rawAnZWVJF1OTLczHx3/NyQh/zgmJf84JST/OCUl/zklJf85JiT/OSYj/zkmI/84JST/OCMk/zgj
Jf84JCT/OCUj/zUiH/8tGhf/TDo4/6OXl//j29v/4dzb/8/Lyf/KxsX/y8fG/8zIx//MyMf/zcnI
/83JyP/Oysn/zsrJ/8/Lyv/Py8r/0MzL/9DMy//Rzcz/1dLR/9nW1f+ooJ7/UUBA/ywZFv8xHhv/
NCEf/zMgH/80IB//NCAe/zMgHf8zIB3/Mx8e/zMfHv8zHx3/Mh8b/ywYFv8oFRP/RjUz/4l8e//L
w8L/6ePj/+jk4//g3Nv/3NnX/9zZ2P/d2dj/3dnY/97a2f/e2tn/39va/+Dc2//g3Nv/4d3c/+Hd
3P/i3t3/4t7d/+Pf3v/j397/49/e/+Pf3v/k4N//5ODf/+Xh4P/m4uH/5uLh/+fj4v/n4+L/6OPj
/+jk4//o4+T/6OTk/+nk5P/p5eT/6ubl/+vn5v/r5+b/7Ojn/+zo5//t6ej/7urp//Lu7v/28/L/
49zc/5qPjv9DMzD/GgYC/zQiH+KDeHhCzcnJAJ6WlQB9cXAAlo6NAOTi4gDf3d0A393dAN/d3QDf
3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d
3QDf3d0A393dAN/d3QDf3d0A393dAP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wDf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN3a2gDNyckAv7q5ALawrwC0rq0A
vLW1AMbBwADc2NgAsampAJ+WlgDNycgAo5uaAK6npgCMgYEAw769ALCpqACxq6oAiH58VkEvL+Ay
Hh7/OiYl/zomJf86JyT/OSYk/zgmJP84JST/OCQm/zklJf85JST/OSYj/zkmI/84JST/NyQj/y8a
G/86Jyf/hXh2/9fPz//l397/z8vK/8fDwv/JxcT/ysbF/8rGxv/Lx8b/zMjH/8zIx//MyMf/zMjH
/83JyP/Nycj/zsrJ/87Kyf/Py8r/19TT/8bBwf93a2n/NSIf/y4aGP81ICD/NSIh/zUiH/80IR7/
MyAf/zQgH/80IB//NCEe/zMgHf8zHx3/LRkX/ysXFf9OPTr/mY2M/9jQz//r5eT/4t7d/9rW1f/Z
1tX/2tbV/9vX1v/c2Nf/3NjX/93Z2P/d2dj/3dnY/97a2f/e2tn/3trZ/9/b2v/g3Nv/4Nzb/+Dc
2//h3dz/4t7d/+Pf3v/j397/49/e/+Pf3v/j397/5ODf/+Xh4P/m4uH/5uLh/+fj4v/n4+L/6OTi
/+jk4//o5OP/6OPk/+jk5P/p5OT/6uXk/+vm5f/r5+b/7Ojm/+zo5//t6ef/7eno//Ht7P/28/P/
3dfW/4Z6eP8tGhf/JREP9YZ7emenn54AfXJxAJaOjQDk4uIA393dAN/d3QDf3d0A393dAN/d3QDf
3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d
3QDf3d0A393dAN/d3QD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADd2toAzcnJAL+6uQC2sK8AtK6tALy1tQDGwcAA
3NjYALGpqQCflpYAzcnIAKObmgCup6YAjIGBAMjEwwCspKQHdGdmiTYiIP02JCH/OScl/zkmJf85
JSb/OiYm/zomJv86JyT/Oick/zgmJP84JST/OCQl/zklJf85JiT/NSIf/zAdGv9hUU//wLW2/+ji
4f/Uz87/xsLB/8bCwf/Hw8L/yMTD/8jEw//JxcT/ysbE/8rGxf/KxsX/y8fG/8zIx//MyMf/zMjH
/8zIx//QzMv/1dHQ/6WdnP9OPTv/LBgX/zQhH/82IyD/NiIf/zUhIP80ISH/NCEf/zUiH/80IR7/
NCAf/zQgH/8vHBn/KxgV/007Of+dj5D/3NXU/+rl4//e2dj/19PS/9fT0v/Y1NP/2dTT/9nV1P/a
1tX/2tbV/9vX1v/b19b/3NjX/9zY1//d2dj/3dnY/93Z2P/d2dj/3trZ/97a2f/f29r/39va/+Dc
2//h3dz/4t7d/+Le3f/i3t3/49/e/+Pf3v/j397/5ODf/+Tg3//l4eD/5eHg/+bi4f/m4uH/5+Pi
/+fj4v/o5OP/6OPj/+jj5P/p5OT/6eTl/+rl5f/q5uX/6+fm/+vn5v/s6Of/7eno//Hu7f/28vH/
xb69/1lJR/8fCgj/ZllXeoR5eACXjo4A5OLiAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf
3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d3QDf3d0A393dAN/d
3QDf3d0A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA3draAM3JyQC/urkAtrCvALSurQC8tbUAxsHAANzY2ACxqakA
n5aWAM3JyACjm5oArqemAJGHhwC0rawhWEpItzIeHf86JSb/Oygm/zsoJf86KCX/OScl/zgmJf85
JSb/OiUm/zomJf86JyT/Oick/zgnJP83JST/MBwd/z8tLf+XjIr/49vb/9zX1v/GwsD/w7++/8XB
wP/GwsH/xsLB/8fDwv/Hw8L/x8PC/8jEwv/IxMP/ycXD/8nFxP/KxsX/ysbF/8vHxv/Rzs3/ysbE
/35xcf82IyL/MR0a/zckIf82IiL/NiEi/zYiIf82IyD/NSIg/zQhIP80ISD/NSIg/zIfHP8rFxT/
QzEv/5SHhv/b1NP/6eTj/9vW1f/V0dD/1dHQ/9bS0f/W09L/19PS/9fT0v/X09L/2NTT/9jU0//Z
1dT/2dXU/9rW1f/b19b/29fW/9zY1//c2Nf/3dnY/93Z2P/d2dj/3trZ/97a2f/f29r/39va/+Dc
2//g3Nv/4d3c/+Hd3P/i3t3/4t7d/+Pf3v/j397/49/e/+Tg3//k4N//5eHg/+Xh4P/m4uH/5uLh
/+fj4v/n4+L/6OTj/+jj4//o5OT/6eTk/+nl5f/q5eX/6ubl/+vn5v/r5+b/7eno//Tx8P/q5uX/
joKB/ykWFP9NPjyFnpaWAOvp6QDj4uIA4d/fAN/e3gDg3t4A4N7eAODe3gDg3t4A4N7eAODe3gDg
3t4A4N7eAODe3gDg3t4A4N7eAODe3gDg3t4A4N7eAODe3gDg3t4A4N7eAODe3gDg3t4A4N7eAP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN3a2gDNyckAv7q5ALawrwC0rq0AvLW1AMbBwADc2NgAsampAJ+WlgDNycgA
o5uaALawrwB+c3M6SDc03DQhHv86KCb/OScm/zknJ/86Jyf/Oycm/zsoJv87KCX/OScl/zkmJf85
JSX/OSUm/zomJv83IyH/MR0b/2RVU//JwMD/5+Df/8vGxP/AvLr/wr69/8O/vv/DwL//xMC//8XB
wP/GwsH/xsLB/8bCwv/Hw8L/x8PC/8fDwv/IxML/yMTD/8nFxP/Rzs3/tK6s/1pLSP8vGxn/NSAh
/zcjI/83IyL/NyQh/zYjIf82ISH/NiEi/zYiIf82IyD/NSIf/ywYF/83IyP/gHNy/9XNzP/p5OP/
2tXU/9LOzf/Szs3/08/O/9TQz//U0M//1dHQ/9XS0P/W0tH/1tPS/9fT0f/X09L/19PS/9jU0//Y
1NP/2dXU/9nV1P/a1tX/2tbV/9vX1v/c2Nf/3NjX/93Z2P/d2dj/3dnY/97a2f/e2tn/39va/9/b
2v/g3Nv/4Nzb/+Hd3P/h3dz/4t7d/+Le3f/j397/49/e/+Pf3v/k4N//5ODf/+Xh4P/l4eD/5uLh
/+fj4v/m4+H/5+Pi/+jj4//o5OT/6OTk/+nk5P/p5eT/6uXl/+rn5f/q5uX/7uvq//Xy8f+7s7L/
Piwp/15QTo2/uroAwr29ANPQzwDc2dkA29jYANvY2ADb2NgA29jYANvY2ADb2NgA29jYANvY2ADb
2NgA29jYANvY2ADb2NgA29jYANvY2ADb2NgA29jYANvY2ADb2NgA29jYANvY2AD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADd2toAzcnJAL+6uQC2sK8AtK6tALy1tQDGwcAA3NjYALGpqQCflpYAz8vKAKqjogCDeHdj
PCsq7zYiI/88KCj/PCkm/zwpJv86KCX/OScm/zknJv86Jif/Oycn/zsoJv87KCX/Oicl/zkmJf8x
Hh7/Oygo/5OHh//j3Nv/2NPS/8G9u/+/u7r/wr27/8K9vP/Cvbz/wr28/8O/vv/Dv77/xMC//8TA
v//FwcD/xsLB/8bCwf/GwsH/xsLB/8rGxf/Oy8n/l46M/0IvL/8xHBv/OCQi/zglIv84JCL/NyMj
/zciI/83IyL/NyQh/zYjIf81IiL/MRwd/y4aGP9jVFL/wbe3/+nj4//b19X/0MzL/9DMy//Szs3/
0s7M/9LOzf/Szs3/08/O/9PPzv/U0M//1dHQ/9XR0P/V0tD/1tLR/9fT0v/X09L/19PS/9fT0v/Y
1NP/2dXU/9nV1P/Z1dT/2tbV/9rW1f/b19b/3NjX/9zY1//d2dj/3dnY/93Z2P/e2tn/3trZ/9/b
2v/f29r/4Nzb/+Dc2//h3dz/4d3c/+Le3f/i3t3/49/e/+Pf3v/j397/5ODf/+Tg3//l4eD/5eHg
/+bi4f/m4uH/5+Pi/+fj4v/o4+P/6OPk/+jj5P/o5OT/6eTk/+rl5f/r5+X/9PHw/9jT0v9aSkn/
Sjs5hZiPjwDBvLsA19PTANXR0QDV0dEA1dHRANXR0QDV0dEA1dHRANXR0QDV0dEA1dHRANXR0QDV
0dEA1dHRANXR0QDV0dEA1dHRANXR0QDV0dEA1dHRANXR0QDV0dEA////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA3dra
AM3JyQC/urkAtrCvALSurQC8tbUAxsHAANzY2ACxqakAopqaAM3KyQJ1Z2eCNyMh/jkmJP86KCf/
Oign/zsoJ/88Jyj/PCgn/zwoJv87KCX/Oicm/zknJv86Jyf/Oycn/zonJf8xHhv/VkZD/761tP/n
39//ycTB/7y4tv++urn/v7u7/8C8u//AvLv/wby7/8K9vP/DvLv/wr28/8K+vf/Cvr3/w7++/8TA
v//EwL//xMHA/8rHxv/GwsH/em9u/zYiIf80IR7/OCYj/zgkJP84JCT/OCQj/zglIv84JCL/NyIj
/zcjI/82IiD/LRoW/0QyMf+fk5P/5N3d/+Db2//Py8r/zcnI/8/Lyf/Py8r/0MzL/9DMy//Rzcz/
0c3M/9LOzf/Szs3/0s7N/9PPzv/Tz87/1NDP/9TQz//V0dD/1dHQ/9bS0f/X09H/19PS/9fT0v/X
09L/2NTT/9jU0//Z1dT/2dXU/9rW1f/a1tX/29fW/9zY1//c2Nf/3dnY/93Z2P/d2dj/3dnY/97a
2f/e2tn/39va/+Dc2//g3Nv/4d3c/+Hd3P/i3t3/4t7d/+Pf3v/j397/49/e/+Pf3v/k4N//5eHg
/+Xh4P/m4uH/5uLh/+fj4v/n4+L/6OPj/+jk4//o4+T/6OPk/+nl5P/x7e3/5+Lh/3RnZf9jVVR7
yMPCANrW1gDW0tIA1tLSANbS0gDW0tIA1tLSANbS0gDW0tIA1tLSANbS0gDW0tIA1tLSANbS0gDW
0tIA1tLSANbS0gDW0tIA1tLSANbS0gDW0tIA1tLSAP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wDf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN3a2gDNyckAv7q5
ALawrwC0rq0AvLW1AMbBwADc2NgAtK2tAJ+WlgtrXl2iNCEg/zsnJ/89Kij/PSon/zwpJ/87KCf/
Oign/zooJ/87Jyj/PCgn/zwpJv87KSb/Oigm/zUjI/8zIB//eWpp/9vT0v/c1tT/v7m1/7y2sf+/
ubX/v7i2/765uP++urj/vrq6/7+7uv/AvLv/wLy7/8G8vP/Cvbz/w7y8/8O9vP/Cvr3/wr69/8nG
xf+5tLP/Y1RS/zEdG/82IyP/OSUl/zklJP85JiP/OCUj/zgkJP84IyT/OCUj/zglIv8zHx3/MBwc
/29gX//Qx8f/6OLh/9LOzf/Kx8X/zMjH/83JyP/Nycj/zsrJ/87Kyf/Oy8n/z8vK/9DMy//QzMv/
0c3M/9HNzP/Szs3/0s7N/9LOzf/Tz87/08/O/9TQz//U0M//1dHQ/9XR0P/W0tH/19LR/9fT0v/X
09L/19PS/9jU0//Y1NP/2dXU/9nV1P/a1tX/29fW/9vX1v/c2Nf/3NjX/93Z2P/d2dj/3dnY/93Z
2P/e2tn/3trZ/9/b2v/f29r/4Nzb/+Hd3P/h3dz/4t7d/+Le3f/j397/49/e/+Pf3v/j397/5ODf
/+Tg3//l4eD/5uLh/+bi4f/n4+L/5+Pi/+jk4//o5OP/6OPk/+3p6f/s5+j/hXh3/4V6eWbY1dUA
1tLSANbS0gDW0tIA1tLSANbS0gDW0tIA1tLSANbS0gDW0tIA1tLSANbS0gDW0tIA1tLSANbS0gDW
0tIA1tLSANbS0gDW0tIA1tLSANbS0gD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADd2toAzcnJAL+6uQC2sK8AtK6t
ALy1tQDGwcAA4d7eALKqqxRVREKyNCEf/zspKP87KSj/Oyko/zwpKP88KSj/PSko/zwqJ/87KSf/
Oign/zonKP87KCf/PCgo/zYhIP8+LCn/nJCP/+jg4P/OyMb/ubSx/7q2sv+9uLP/vbiz/764s/+/
uLP/v7m0/765tf+/ubf/v7q5/766uv+/u7r/v7y7/8G8u//BvLz/wr28/8nEw/+qo6D/Tj49/zEd
Hf85JiT/OSYk/zgmJP84JCT/OSUk/zgmI/84JiP/OCUj/zcjJP8vGhr/QjAu/6KVlP/o4eD/2tXU
/8nFxP/JxsX/y8fG/8vHxv/MyMf/zMjH/8zIx//MyMf/zcnI/83JyP/Oysn/z8vK/8/Lyv/QzMv/
0c3L/9HNzP/Rzcz/0s7N/9LOzf/Szs3/08/O/9PPzv/U0M//1NDP/9XR0P/V0dD/1tLR/9bS0f/X
09L/19PS/9fT0v/Y1NP/2NTT/9nV1P/Z1dT/2tbV/9vX1v/b19b/3NjX/9zY1//d2dj/3dnY/93Z
2P/d2dj/3trZ/97a2f/f29r/39va/+Dc2//h3dz/4d3c/+Le3f/i3t3/49/e/+Pf3v/j397/49/e
/+Tg3//k4N//5eHg/+Xh4P/m4uH/5+Pi/+fj4v/o4+P/6+fn/+7p6f+UiYj4gnd3QNHMzADe29sA
29jYANvY2ADb2NgA29jYANvY2ADb2NgA29jYANvY2ADb2NgA29jYANvY2ADb2NgA29jYANvY2ADb
2NgA29jYANvY2ADb2NgA////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA3draAM3JyQC/urkAtrCvALSurQC8tbUAzsrJ
AMG8uyFWRkXNNiMh/z4qKf8+Kyj/PSoo/zsqKP87KSj/Oyko/zwoKf89KSn/PSoo/zwpJ/87KSf/
Oign/zEeHf9PPT3/vbOz/+Xe3f/Curj/uLKs/7u0sf+6tbL/uraz/7u2s/+7t7P/vbez/724s/++
uLP/v7iz/764tP++ubX/v7m3/766uP++urr/wLy7/8fEw/+ZkI//QzEv/zQhHv85JiX/OSYl/zom
Jf86JyT/OSck/zglJP84JST/OSUk/zcjIf8uGxj/YlJS/8vCwv/n4eD/zcnI/8bCwf/IxML/ycXD
/8nFxP/KxsX/ysbF/8vHxv/Lx8b/zMjG/8zIx//MyMf/zMjH/83JyP/Oysn/zsrJ/8/Lyv/Py8r/
0MzK/9DMy//Rzcz/0c3M/9LOzf/Szs3/0s7N/9PPzv/Tz87/1NDP/9TQz//V0dD/1dHQ/9bS0f/W
0tH/19PS/9fT0v/X09L/2NTT/9jU0//Z1dT/2dXU/9rW1f/a1tX/29fW/9vY1//c2Nf/3NjX/93Z
2P/d2dj/3dnY/97a2f/e2tn/39va/9/b2v/g3Nv/4d3c/+Hd3P/i3t3/4t7d/+Pf3v/j397/49/e
/+Pf3v/k4N//5eHg/+Xh4P/m4uH/5uLh/+bj4f/p5eT/7Ojo/56Uk+G0rawn4d7fANzZ2QDc2dkA
3NnZANzZ2QDc2dkA3NnZANzZ2QDc2dkA3NnZANzZ2QDc2dkA3NnZANzZ2QDc2dkA3NnZANzZ2QDc
2dkA3NnZAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wDf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADf3NwA39zcAN3a2gDNyckAv7q5ALawrwC0rq0Aw769ALKrqihOPTvYNSMh
/zwqKf88Kin/PCop/z0qKf8+Kyj/PSoo/zwqKP87KSj/Oyko/zwpKP89KSj/PCgm/zMfHf9mV1X/
1MzL/9vV0/+5s6//trGr/7izrf+5s67/urSu/7q0r/+6tLD/urWy/7q1s/+7trP/vLez/723s/+9
uLP/vriy/7+5s/++uLT/wLu3/8XAvv+Jf33/Oykn/zUiIf87KCb/Oygl/zonJf85JyX/OSYl/zom
Jf86JyT/OSck/zMfH/81IiL/i359/+Pb2//b1tT/xsLA/8XCwf/Hw8L/x8PC/8fDwv/Hw8L/yMTD
/8nFxP/JxcT/ysbF/8rGxf/Lx8b/y8fG/8zIxv/MyMb/zMjH/83JyP/Nycj/zsrJ/87Kyf/Py8r/
z8vK/9DMy//Rzcz/0c3M/9HNzP/Szs3/0s7N/9LOzf/Tz87/08/O/9TQz//U0M//1dHQ/9bS0f/W
0tH/1tLR/9fT0v/X09L/19PS/9jU0//Y1NP/2dXU/9rW1f/a1tX/29fW/9vX1v/b19b/3NjX/9zY
1//d2dj/3dnY/93Z2P/e2tn/3trZ/9/b2v/f29r/4Nzb/+Hd3P/h3dz/4t7d/+Le3f/j397/49/e
/+Pf3v/j397/5ODf/+Xh4P/l4eD/5uLh/+jk4//o5OP/qqGgvMK9vQbg3d0A3NnZANzZ2QDc2dkA
3NnZANzZ2QDc2dkA3NnZANzZ2QDc2dkA3NnZANzZ2QDc2dkA3NnZANzZ2QDc2dkA3NnZANzZ2QD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA39zcAN/c3ADd2toAzcnJAL+6uQC2sK8AvLa1AKefni5LOjndNyQi/z8sKv8+Kyn/PSsp
/zwqKf88Kin/PCop/z0rKP8+Kij/PSoo/zwqKP87KSj/OCYl/zQhIP9+b2//4dnY/9DKyP+0r6r/
trCq/7exrP+3sq3/uLKt/7iyrf+5sq7/ubOu/7q0rv+6tK//u7Ww/7u1sf+7tbP/u7az/7y3s/+9
t7P/v7q2/8G8uP98cW//OCUj/zklI/87KCb/OScm/zonJv87Jyf/Oygm/zonJf85JiX/OSUm/zEd
HP9HNjP/r6Wk/+ji4f/Oysn/wr69/8TAv//FwcD/xcHA/8bCwf/Hw8L/x8PC/8fDwv/Hw8L/x8PC
/8jEwv/IxMP/ycXE/8nFxf/Lx8b/y8fG/8zIx//MyMb/zMjH/8zIx//MyMj/zcnI/83JyP/Oy8n/
z8vK/8/Myv/QzMv/0c3L/9HNzP/Szs3/0s7N/9LOzf/Tz87/08/O/9PPzv/U0M//1dHQ/9XR0P/W
0tH/1tLR/9fT0v/X09L/19PS/9jU0//Y1NP/2NTT/9nV1P/a1tX/2tbV/9vX1v/b19b/3NjX/9zY
1//c2Nf/3dnY/93Z2P/e2tn/3trZ/97a2f/f29r/39va/+Dc2//g3Nv/4d3c/+Le3f/i3t3/4t7d
/+Pf3v/j397/49/e/+Tg3//k4N//5+Tj/+Ld3P+9traA0MzMANTQ0ADUz88A1M/PANTPzwDUz88A
1M/PANTPzwDUz88A1M/PANTPzwDUz88A1M/PANTPzwDUz88A1M/PANTPzwDUz88A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c
3ADf3NwA3draAM3JyQC/urkAvbe2AKKamS9JODbfNyUk/z0rKv89Kyr/Pisq/z8rKf8+Kyn/PSsp
/zwqKf88Kin/PCop/z0qKf8+Kin/OiYk/zkmJP+Th4X/5t/f/8bAvf+xq6b/tK6p/7Wvqv+2sKv/
trCr/7exrP+3sa3/t7Kt/7eyrv+4sq7/uLKu/7mzrv+6s67/urSv/7u1sP+6tbH/vrm2/7y4tf90
Z2T/NSMh/zgmJf87KCf/Oygn/zwpJv87KCb/OScm/zonJ/87Jyb/Oicl/zAdGv9dTUz/zMPC/+Pe
3f/FwL//wLu6/8K+vf/Dvr3/w7++/8PAv//EwL//xcHA/8XBwP/GwsH/xsLB/8fDwv/Hw8L/x8PC
/8jEwv/IxML/ycXD/8nFxP/KxsX/ysbF/8vHxv/MyMf/y8jG/8zIx//MyMf/zcnI/83JyP/Oysn/
zsrJ/8/Lyf/Py8r/0MzL/9DMy//Rzcz/0s7N/9LOzf/Szs3/0s7N/9PPzv/U0M//1NDP/9XR0P/V
0dD/1tLR/9bS0f/X09L/19PS/9fT0v/X09L/2NTT/9jU0//Z1dT/2tbV/9rW1f/b19b/29fW/9vY
1//c2Nf/3dnY/93Z2P/d2dj/3trZ/97a2f/f29r/39va/9/b2v/g3Nv/4d3c/+Hd3P/i3t3/4t7d
/+Pf3v/j397/49/e/+Pf3v/n4+L/3tnZ8Ma/vy7PyckA0MvLANDKywDQyssA0MrLANDKywDQyssA
0MrLANDKywDQyssA0MrLANDKywDQyssA0MrLANDKywDQyssA0MrLAP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wDf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN3a
2gDNyckAxsHAAKOcmi9JODbeOSYk/z8tKv8+Kyr/PSsq/z0rKv89Kyr/PSsq/z4rKf8/Kyr/Pisp
/zwqKf88Kin/NyQj/z4sKv+nnJv/5uDf/763s/+wqqT/s62o/7OtqP+zraj/tK6p/7Suqf+1r6r/
ta+r/7awrP+3saz/t7Gs/7eyrf+3sa3/uLKu/7iyrv+5s67/vbey/7q0r/9rXlz/NCEg/zwpJ/89
Kij/Oykn/zooJ/87KCf/PCgn/zwpJv87KCb/NyUk/zEeHf93aWf/3tbW/9rU1P+/u7r/v7u6/8G8
u//CvLz/wr27/8O9vP/Dvrz/w769/8O/vv/EwL//xMC//8XBwP/FwcD/xsLB/8bCwf/Hw8L/x8PC
/8fDwv/HxML/yMTD/8nFw//JxcT/ysbF/8rGxf/Lx8b/y8fG/8zIxv/MyMf/zMjH/83JyP/Nycj/
zsrJ/87Kyf/Py8n/z8vK/9DMy//QzMv/0c3M/9LOzf/Szs3/0s7N/9LOzf/Tz87/08/O/9TQz//U
0M//1dHQ/9bS0f/W0tH/1tLR/9bS0f/X09Lx2dXU5tjU0+jY1NPo2dXU6NnV1ObZ1dT62tbV/9vX
1v/b19b/3NjX/93Z2P/d2dj/3dnY/97a2f/e2tn/3trZ/9/b2v/f29r/4Nzb/+Hd3P/h3dz/4t7d
/+Le3f/j397/49/e/+Xh4P/e2tm319LSBNjT0wDY09MA2NPTANjT0wDY09MA2NPTANjT0wDY09MA
2NPTANjT0wDY09MA2NPTANjT0wDY09MA2NPTANjT0wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADd2toA1NHRAK2m
pSpJODbeOCUl/z4sK/8+LCv/Pywq/z8sKv8+LCr/PSsq/z0rKv89Kyr/Pisq/z8rKv8/LCn/NyQi
/0QzMv+2raz/4tzb/7awrP+uqKP/saum/7Ksp/+yrKf/s62o/7OtqP+zraj/s62o/7Suqf+0rqr/
ta+q/7awq/+2sKv/t7Gs/7exrP+3sa3/u7Wx/7awrP9mWFb/NSIg/zsoJ/87KSj/PCko/z0pKP88
KSf/Oykn/zooJ/87KCj/OCQj/zckIv+Qg4L/59/f/9DKyP+8t7X/vrq4/7+7uv+/u7r/v7y7/8C8
u//Bvbv/wr27/8K9vP/Cvbz/w768/8O/vf/Dv77/xMC//8TAv//FwcD/xcHA/8bCwf/GwsH/x8PC
/8fDwv/Hw8L/x8TC/8jEw//JxcP/ycXE/8rGxf/KxsX/y8fG/8vIxv/MyMf/zMjH/8zIx//Nycj/
zcnI/87Kyf/Oysn/z8vK/8/Lyv/QzMv/0MzL/9HNzP/Szs3/0s7N/9PPzv/U0dD419PS5NnV1Knb
2Nef3tvaV97b2kPi4N5H3drYF9POzQPY1NMI29jXCtzZ1wzf3NsK4d7dLd/c20/c2NdM3NjXj9vX
1qTb19bU3NjX7tzY1//d2dj/3dnY/93Z2P/d2dj/3trZ/97b2v/f29r/4Nzb/+Dc2//h3dz/4d3c
/+Le3f/i3t3/4+Df/+Hd3Erf29sA4NzbAODc2wDg3NsA4NzbAODc2wDg3NsA4NzbAODc2wDg3NsA
4NzbAODc2wDg3NsA4NzbAODc2wDg3NsA////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3d0A5ePjALq0tCVMOzrbOicl/z8t
K/8+LCv/Piwr/z4sK/8+LCv/Piwr/z8sK/8+LCr/PSsq/z0rKv89Kyr/NiMi/0w7Of/Cubj/3dfV
/7Grp/+tpqH/r6mk/7Cppf+wqqX/saum/7Grpv+yrKf/sqyn/7OtqP+zraj/s62o/7OtqP+0rqn/
ta+q/7Wvqv+1r6r/urSu/7Wvq/9jVVP/NSIh/zwpKf8+Kin/PSoo/zspKP87KSj/PCko/z0pKP89
Kij/NSIh/zwqKv+mmpr/5+Hg/8fCvv+8trH/vriz/7+5tP++ubX/vrm3/766uP+/u7r/v7u6/8C8
u//AvLv/wby7/8G9u//Cvbv/wr28/8K+vP/Dv77/w7++/8TAv//EwL//xcHA/8XBwP/GwsH/xsLB
/8fDwv/Hw8L/x8PC/8jDwv/IxML/ycXD/8nFxP/KxsX/y8fG/8vHxv/Lx8b/zMjH/8zIx//MyMf/
zcnI/83JyP/Oysn/zsrJ/9HNzP/V0tH/2dbU/9jV0//U0dD/0MzLuMfCwSespKMckoiGHZiPjiSw
qagvkYiGIY6EgiWTiYcfvLW1FMXAvwKwqagAioB/AMrFxADMx8YA1dHRAN/c2wDf3NoA4N3cBt3Z
2BTc2NdQ3NjXotzY1+fc2Nf/3dnY/93Z2P/d2dj/3dnY/97a2f/e29r/39va/+Dc2//g3Nv/4d3c
/+Hd3P/i3t3F49/eAOPf3wDj398A49/fAOPf3wDj398A49/fAOPf3wDj398A49/fAOPf3wDj398A
49/fAOPf3wDj398A49/fAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wDf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zc
AN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADe29sA4+DgAMjDwx9RQUDVOCYl/z8tLP8/LSz/Py0r/z8t
K/8+LCv/Piwr/z4sK/8+LCv/Piwr/z8sKv8/LCr/NSIh/1FBP//JwMD/2dLR/62no/+rpaD/raei
/62nov+uqKP/r6ik/6+ppf+wqaX/sKql/7Gqpv+xq6b/sqyn/7Ksp/+zraj/s62o/7OtqP+zraj/
t7Gs/7KsqP9jVVP/NyQi/z4rKf88Kin/PCop/z0qKf89Kyj/PSoo/zwpKP87KSn/NSEg/0c1Mv+2
rKv/5d7e/8C7uP+4tLH/u7ez/723s/++uLP/vriz/764s/+/ubT/v7m1/765t/++urj/vrq6/7+7
uv/AvLv/wLy7/8G9vP/Cvbv/wr27/8K9u//Cvrz/wr69/8O/vv/EwL//xMC//8XBwP/FwcD/xsLB
/8bCwf/Hw8L/x8PC/8fDwv/Iw8L/yMTD/8nFw//JxcT/ysbF/8rGxf/Lx8b/y8fG/8zIx//Nycj/
0s/O/9XS0P/Hw8L/qaGg/390cv9nWlj/WUpH/0o5N/c/LizqNyUi9TMgHvkxHhv8LxwZ/y8dGvsz
IB35OSck9UEwLe9HNzTVUkJAsEEwLoOAdXNbkYaFJK2mpgKvqKgAuLGwAMnFxADV0dAA4NzbAN7a
2QDc2NcR3NjXUNvX1qvc2Nf/3NjX/93Z2P/d2dj/3dnY/93Z2P/e2tn/3trZ/9/b2v/f29r/4Nzb
/+Hd3GTi394A4t/eAOLf3gDi394A4t/eAOLf3gDi394A4t/eAOLf3gDi394A4t/eAOLf3gDi394A
4t/eAOLf3gD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbW
ANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA
2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ
1tYA2dbWANnW1gDZ1tYAyMPDAKWenBBWRkXCOCUk/0AuLP8/LSz/Py0s/z8tLP8/LSz/Py0s/z8t
K/8/LCv/Piwr/z4sK/8+LCv/NiQi/1ZEQ//NxcT/1c/N/6ykoP+so5//rKah/6ymof+spqH/raei
/62nov+tqKP/rqij/6+opP+vqaT/sKml/7Cqpf+wqqX/saum/7Ksp/+yrKf/trCr/7Gsp/9kVlT/
NiQj/z0rKf8+Kyr/Pisp/z0rKf88Kyn/PCop/z0qKf8+Kyj/NSIg/007Ov/Dubn/4dra/7y1sv+4
sq3/u7Ww/7q1sv+7trL/u7a0/7y3s/+9t7P/vriz/764s/++uLP/vriz/765tf+/urf/vrq4/767
uv+/u7r/v7y7/8C8u//Bvbv/wb27/8K9u//Cvbv/wr68/8O+vf/Dv77/xMC//8TAv//FwcD/xcHA
/8bCwf/GwsH/x8PC/8fDwv/Hw8L/yMTC/8jEw//IxMP/ycXE/8zJyP/Sz87/y8jG/62mpP98cG7/
Tz89/zUiIP8sGRf/LRkX/y4bGf8wHRr/MB0a/zEeHP8xHhv/MR4b/zEeG/8wHRv/MB0a/y4bGP8s
GRf/KxgV/ykWE/8sGRb/KhcU/zUjIfRLOznJZFZVhIN4dzilnp0DnpWVAMjEwwDTz84A3trZAOHe
3ADb2NcA29fWOdvX1qrb19b+29fW/9zY1//c2Nf/3dnY/93Z2P/d2dj/3trZ/97a2f/f29r84Nzb
LuPf3gDj394A49/eAOPf3gDj394A49/eAOPf3gDj394A49/eAOPf3gDj394A49/eAOPf3gDj394A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////ANjV
1QDY1dUA2NXVANjV1QDY1dUA2NXVANjV1QDY1dUA2NXVANjV1QDY1dUA2NXVANjV1QDY1dUA2NXV
ANjV1QDY1dUA2NXVANjV1QDY1dUA2NXVANjV1QDY1dUA2NXVANjV1QDY1dUA2NXVANjV1QDY1dUA
2NXVANjV1QDY1dUA2NXVANjV1QDY1dUA2NXVANjV1QDY1dUA2NXVANjV1QDY1dUA2NXVANjV1QDY
1tYA3dvbAMG7uwhdTk2uOCYl/0AuLf9ALi3/Py4s/z8uLP8/LSz/Py0s/z8tLP8/LSz/QC0s/z8t
K/8/LSv/NiMi/1VFRP/Pxsb/0szK/6ihnP+qop3/rKOf/62koP+tpKD/raWg/62lof+spqH/raah
/62nov+tp6L/raei/66oo/+vqKP/r6mk/7Cppf+wqqX/s62o/7Ksp/9nWlj/NyQj/z4sKv8+LCr/
PSsq/z0rKv89Kyr/Pisp/z0rKf88Kin/NCIg/1RDQv/Nw8P/3NbU/7iyrv+3sK3/uLKu/7mzrv+5
s67/urSv/7u1sP+6tbH/u7ay/7u2s/+8t7P/vbez/764s/++uLL/vriz/7+4tP++ubX/vrm3/766
uf+/u7r/v7u7/7+8u//AvLv/wby7/8G8u//Cvbv/wr28/8O+vf/Dvr3/w7++/8TAv//EwL//xcHA
/8XBwP/GwsH/xsLB/8fDwv/Hw8L/y8fG/8/Myv+/urn/koiG/1tMSv84JST/LxsZ/zMfHf82IiH/
NyMh/zYjIf82IyD/NSIf/zUhIP80IR//MyEe/zMgHf8yIB3/Mh8c/zIfHP8xHhz/MR4b/zAeG/8w
HRr/MB0a/y8cGf8tGhf/KRYT/ycUEf8tGhf9STo4yXBjYmqspaQXuLGxALKrqgC4srEA3NnYAN/b
2gDe2tkA29fWOdrW1bfa1tX/29fW/9vX1v/c2Nf/3NjX/93Z2P/d2dj/3dnY/97a2d3h3dwT4t7d
AOLe3QDi3t0A4t7dAOLe3QDi3t0A4t7dAOLe3QDi3t0A4t7dAOLe3QDi3t0A4t7dAP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDZ1tYA2dbWANnW
1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbW
ANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA
2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA2dbWANnW1gDZ1tYA1dLSANDMzABx
ZGOeOCUk/0AuLf9ALi3/QC4t/0AuLf9ALi3/QC4t/z8uLP8/LSz/Py0s/z8tLP8/LSz/NyUk/1ZF
Q//Qx8b/0crI/6eemv+ooJz/qKKd/6minf+qop7/q6Ke/6yjn/+to6D/raSg/62loP+tpaH/raah
/6ynof+tp6L/raei/62oov+uqKP/sKqm/7KsqP9sYF3/OCYk/z4rKv8+LCv/Piwr/z4sKv89Kyr/
PSsq/z0rKv8+LCr/NiIh/1hJR//Sycn/2dLQ/7Wvq/+2sKv/t7Gt/7exrP+3sa3/uLKu/7iyrv+5
s67/urOu/7q0r/+7tbD/u7Wx/7u1s/+7trP/vLez/723s/+9uLL/vriz/764s/++uLT/vrm1/765
t/++ubj/vrq5/7+7uv+/vLv/wLy7/8G8u//CvLv/w727/8K9vP/Cvrz/wr69/8O/vv/Dv7//xMC/
/8TAv//JxcT/zcrJ/7eysf+BdnT/Sjo4/zIfHf8zHx3/NyQi/zklI/84JSL/OCUi/zckIv83IyH/
NiMh/zYiIf81IiD/NSIf/zQhHv8zIB7/MyAe/zMgHf8yHxz/Mh8c/zIfHP8xHhv/MB4b/zAdGv8w
HRr/Lx0Z/y8cGf8vHBn/LRoX/ygVEv8nFBH/Oigl5XVpZ4CWjYwXh3x7ALu1tADW0tIA4d7dAN3a
2QDd2dgD29fWbtnV1O3a1tX/2tbV/9vX1v/c2Nf/3NjX/9zY1//d2dj/3dnYfuDc2wDg3NsA4Nzb
AODc2wDg3NsA4NzbAODc2wDg3NsA4NzbAODc2wDg3NsA4NzbAODc2wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A3traAN7a2gDe2toA3traAN7a
2gDe2toA3traAN7a2gDe2toA3traAN7a2gDe2toA3traAN7a2gDe2toA3traAN7a2gDe2toA3tra
AN7a2gDe2toA3traAN7a2gDe2toA3traAN7a2gDe2toA3traAN7a2gDe2toA3traAN7a2gDe2toA
3traAN7a2gDe2toA3traAN7a2gDe2toA3traAN7a2gDe2toA39vbAMjDwgBuYWB2Oign/0EuLf9B
Ly3/QC4t/0AuLf9ALi3/QC4t/0AuLf9ALi3/QS4s/z8tLP8/LSz/OCYl/1JCQf/OxsX/0MnH/6Wd
mP+nnpr/qaCc/6mgnP+poZ3/qKGd/6minf+oop7/qqKe/6ujn/+so5//raSg/62koP+tpaH/raWh
/6ymof+spqH/rqij/7Ksp/90aGX/Oicn/z8sK/9ALSv/Pywr/z4sK/8+LCv/Piwr/z4sKv8+LCr/
NCIg/1xMS//VzMz/1c7M/7KsqP+zran/ta+q/7awq/+2sKv/t7Gs/7exrP+3sa3/uLKt/7iyrv+4
sq7/ubOu/7q0r/+7tK//urWw/7u1sv+7trP/u7az/7y3s/+8t7P/vbiz/764s/+/uLP/vri0/7+5
tf++urf/vrq5/766uv+/u7r/wLy7/8C8u//Bvbv/wby7/8K9u//Cvbz/wr68/8bCwf/Kx8b/ta+u
/3twbf9FNDL/MyAe/zYjIf86JyX/OScl/zkmJP84JSP/OCYj/zglIv84JSL/OCQi/zckIv83JCH/
NSIh/zYjIP80Ih//NSEf/zQhH/80IR7/MyAe/zIfHf8yHxz/MR0b/zAeG/8wHRr/Lx0a/y8cGv8v
HBr/LxwZ/y8cGf8uGxj/LhsY/yoWE/8mEg//NyUi3WtdW2u0rq0FvLa2ALewsADSz84A4t/eAN7a
2gDa1tUc2NTTqNnV1P/Z1dT/2tbV/9vX1v/b19b/3NjX/9zY1/ne2tkx4t/eAOLe3QDi3t0A4t7d
AOLe3QDi3t0A4t7dAOLe3QDi3t0A4t7dAOLe3QDi3t0A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AN/b2wDf29sA39vbAN/b2wDf29sA39vbAN/b
2wDf29sA39vbAN/b2wDf29sA39vbAN/b2wDf29sA39vbAN/b2wDf29sA39vbAN/b2wDf29sA39vb
AN/b2wDf29sA39vbAN/b2wDf29sA39vbAN/b2wDf29sA39vbAN/b2wDf29sA39vbAN/b2wDf29sA
39vbAN/b2wDf29sA39vbAN/b2wDf29sA39vbAObj4wCVjItcPCop/EAtLP9BLy7/QS8u/0EvLv9B
Ly7/QC4t/0AuLf9ALi3/QC4t/0AuLf9ALi3/OScm/04+PP/JwcD/0cvI/6Oblv+knJj/pp6a/6ee
mv+onpr/qJ+b/6mfnP+poJz/qaGd/6ihnf+oop3/qaKe/6qinv+rop7/rKOf/62jn/+tpKD/rqWh
/7Ksp/99cm//PCop/z4rKv8/LSz/Py0s/z8tLP8/LSv/Pywr/z4sK/8+LCv/NiMi/11MS//Uy8v/
08zK/7Cqpv+yrKf/s62o/7OtqP+0rqn/tK6q/7Wvqv+2r6r/trCr/7axrP+3saz/t7Gt/7iyrf+4
sq7/ubOu/7mzrv+6s67/urSv/7u0sP+7tbH/u7Wz/7u2s/+7trP/vbez/764s/++uLP/vriz/765
tP+/ubX/vrm3/766uP++urr/v7u6/7+8u//AvLv/wr69/8nFw/+5s7H/gHVz/0c2NP8zIR//OCUj
/zsoJ/87KCb/Oigm/zknJf86JiX/OSck/zkmJP84JiP/OCUj/zgkI/84JCL/NyQh/zckIv82IyH/
NCEf/zMfHf8vHBr/LBgV/yoWE/8qFhP/KxkW/ywaF/8uGxj/LRoY/y0aF/8rGBX/KBUS/yUSD/8l
EQ//KBQS/ysYFf8tGhf/LRoX/yoWE/8nFBD/Tj48wp+XljeknZ0AraalAMjDwgDi3t4A3NjXANrW
1QTY1NNw2NTT/tjU0//Z1dT/2tbV/9rW1f/b19b/29fWyt/b2gLg3NsA4NzbAODc2wDg3NsA4Nzb
AODc2wDg3NsA4NzbAODc2wDg3NsA4NzbAP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wDPy8oAz8vKAM/LygDPy8oAz8vKAM/LygDPy8oAz8vKAM/L
ygDPy8oAz8vKAM/LygDPy8oAz8vKAM/LygDPy8oAz8vKAM/LygDPy8oAz8vKAM/LygDPy8oAz8vK
AM/LygDPy8oAz8vKAM/LygDPy8oAz8vKAM/LygDPy8oAz8vKAM/LygDPy8oAz8vKAM/LygDPy8oA
z8vKAM/LygDOysoA0MzLANXS0gChmZg5QzEw9z8tLP9CMC//QS8u/0EvLv9BLy7/QS8u/0EvLv9B
Ly7/QC4t/0AuLf9ALi3/Oign/0o4N//Cubn/1M3M/6Kalv+impb/pJuX/6WcmP+lnZj/pZ2Z/6ed
mf+nnpr/p56a/6ifm/+poJz/qaCc/6mhnf+pop3/qKKd/6minf+qop7/q6Ke/7Kqpf+Jfnv/Py0s
/z4sK/9ALi3/QC0s/z8tLP8/LSz/Py0s/z8tLP8/LSz/NiMi/1pJSf/VzMz/08vJ/66oo/+wqqX/
sqyn/7Ksp/+zraj/s62o/7OtqP+zraj/tK6p/7Suqf+1r6r/tq+r/7awq/+3saz/t7Gs/7eyrf+4
sq3/uLKu/7iyrv+5s67/ubOu/7q0r/+7tLD/u7Wy/7u1s/+7trP/vLez/723s/++uLL/vriz/764
s/++ubT/v7m1/765t/++urj/xMC//7+7uv+OhYP/Tj89/zQiIP84JiX/Oyoo/zspKP87KSf/Oygn
/zsoJv86Jyb/Oicl/zknJf85JiT/OSYk/zkmI/84JiP/OCQj/zUiIP8wHBv/LhoY/zEeHP8+Kyn/
UUA+/2hYV/9+cW//koWE/6CUk/+qn57/sKWk/7Glpf+vpKL/ppua/5qOjP+Ienn/cGFg/1ZFRP89
Kyn/KxgW/yURDv8nFBH/KxgV/yURDv8xHxz2bmFgb62npgGRiIcA0MvKANjU0wDc2dgA2dXUANnV
1GLX09L+19PS/9jU0//Y1NP/2dXU/9nV1P/b19Zg4t/eAOLf3gDi394A4t/eAOLf3gDi394A4t/e
AOLf3gDi394A4t/eAOLf3gD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8AysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXFAMrF
xQDKxcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXF
AMrFxQDKxcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUA
ysbFAMnFxACtpqUaTj082T0qKf9CMC//QjAv/0IwL/9BLy7/QS8u/0EvLv9BLy7/QS8u/0EvLv9B
Ly7/PCop/0IxMP+5r67/2dHQ/6KZlf+hmJT/o5qW/6Oalv+km5f/pJuX/6Sbl/+knJf/pZyY/6Wd
mf+mnZn/p56a/6eemv+on5v/qaCc/6mgnP+poZ3/qKGd/62no/+Tiob/RjQz/z0rKv9ALi3/QC4t
/0AuLf9ALi3/QC4s/z8tLP8/LSz/OCUk/1REQ//Sycn/0szK/6ymof+vqKT/sKml/7Cqpf+xqqX/
saum/7Grpv+yrKf/s62o/7OtqP+zraj/s62o/7Suqf+0rqn/ta+q/7avq/+2sKv/trCr/7exrP+3
sa3/uLGu/7iyrv+4sq7/ubOu/7mzrv+6tK//urSw/7u1sv+7tbP/u7az/7u2s/+9t7P/vriz/764
sv/Bu7b/xL+7/6Sbmf9fUE7/OCUk/zkmJf89Kyr/PSsp/zwqKf88Kij/Oyko/zwpJ/87KSf/Oygn
/zooJv86JyX/Oicl/zknJP82JCH/MB0b/zAdG/8/LCr/X09N/4h7ev+vpKP/y8LB/9vU1P/j3dz/
5N7e/+Hc2//e2dj/3NfX/9vW1v/a1tb/29fW/9zX1//f2tn/4dzc/+Pe3f/d19b/zcbF/6+lpf+D
dnX/UUA+/y4bGP8kEA7/JhIP/yYTD/9XSUellIqKEMO9vQCtpqUA19TSANzZ2ADd2tkA29jWYdbS
0fXX09L/19PS/9fT0v/X09L/2NTT7N7a2RXf3NsA39zbAN/c2wDf3NsA39zbAN/c2wDf3NsA39zb
AN/c2wDf3NsA////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AM/KygDPysoAz8rKAM/KygDPysoAz8rKAM/KygDPysoAz8rKAM/KygDPysoAz8rKAM/K
ygDPysoAz8rKAM/KygDPysoAz8rKAM/KygDPysoAz8rKAM/KygDPysoAz8rKAM/KygDPysoAz8rK
AM/KygDPysoAz8rKAM/KygDPysoAz8rKAM/KygDPysoAz8rKAM/KygDPysoAz8nKANPOzgDEv78G
WElIrzwpKP9CMC//QjAv/0IwL/9CMC//QjAv/0IwL/9BLy7/QS8u/0EvLv9BLy7/Pywr/z0rKv+s
oaH/3NXT/6KZlf+flpL/oZiU/6KZlf+hmZX/opqW/6Kalv+km5f/pJuX/6Sbl/+km5f/pJyY/6Wd
mf+mnZn/p56a/6eemv+on5v/qJ+b/62koP+dlZD/Tj48/zwqKf9BLy7/QS8u/0AuLf9ALi3/QC4t
/0AuLf9ALi3/OSYl/049PP/MxMP/1M7M/6uloP+sp6H/raej/66oo/+vqKT/sKml/7Cppf+wqqX/
saum/7Grpv+yrKf/sqyn/7OtqP+zraj/s62o/7OtqP+0rqn/tK6p/7avqv+2sKv/trCr/7exrP+3
sa3/t7Kt/7exrv+4sq7/uLKu/7mzrv+6tK7/urSv/7q1sP+6tbL/urWz/7u2tP/Cvrr/t7Gt/3lt
a/9BLy3/OSYl/z4sK/8+LCv/Piwq/z0rKv89Kyn/PCop/zwqKf88Kij/Oyko/zspJ/86KCb/Oicl
/zQhH/8xHhv/QS8t/2tdW/+glZT/zcTE/+Lb2//j3Nz/29bV/9LOzf/Lx8b/yMTC/8fDwf/Hw8H/
x8TC/8jEw//JxcT/ycXE/8rGxf/KxsX/y8fG/8vHxv/MyMf/zsrJ/9LOzf/Z1tT/39vb/9vV1P+5
r67/e21r/z0qKP8iDwz/HwsI/0g3NcitpqUmpJ2cAJ+XlgDLx8YA4N3cAOHf3QDX09Iv1dHQ29bS
0f/X09L/19PS/9fT0v/Z1dSD3NnYANzZ2ADc2dgA3NnYANzZ2ADc2dgA3NnYANzZ2ADc2dgA3NnY
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDK
xcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXFAMrF
xQDKxcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXF
AMrFxQDKxcUAysXFAMrFxQDKxcUAysXFAMrFxQDKxcUAysXEAMzHxwDKxcUAd2ppiD0qKf9DMTD/
QzEw/0MxMP9CMC//QjAv/0IwL/9CMC//QjAv/0IwL/9CMC//QC4t/zonJv+bj47/39jX/6SbmP+b
ko7/n5aS/5+Wkv+gl5P/oJeT/6GYlP+hmJT/opmV/6KZlf+jmpb/o5qW/6Obl/+km5f/pJuX/6Sc
mP+lnJj/pZ2Z/6igm/+lnJj/XE1K/zwpKf9BLy7/QS8u/0EvLv9BLy7/QS8u/0EuLf9ALi3/Oygn
/0c2Nf/CuLj/2NHP/6ykn/+spKD/raah/62mof+tp6L/raei/62oo/+uqKP/r6ij/7Cppf+wqaX/
saql/7Gqpf+xq6b/saym/7Ksp/+yrKf/s62o/7OtqP+0rqj/tK6p/7Suqf+1r6r/trCr/7awq/+2
sKz/t7Gs/7eyrf+3sa7/uLKu/7izrv+5s67/urSu/723sv/Bu7f/mpKQ/1VGRP85Jib/Pisq/z8t
LP8/LSz/Py0r/z4sK/8+LCr/Pisq/z0rKv89Kyn/PCop/zwqKP86Jyb/MyAe/zYkIv9bS0n/mIuL
/87Fxf/j29v/3tnX/9DMy//GwsL/w7++/8O/vv/EwL//xcHA/8bCwf/Hw8L/x8PC/8fDwv/Hw8L/
yMTD/8nFw//JxcT/ysbF/8rGxf/Lx8b/y8fG/8zIx//MyMf/zMjH/8zIx//Oy8r/19PS/97a2f/M
xcT/in18/z0sKf8bBwT/Oikm3JGIhzGYj40ApJybANTQzwDj4eAA29fWANfT0j3U0M/+1dHQ/9XR
0P/W0tH/1tLR69rX1hfc2dgA3NnYANzZ2ADc2dgA3NnYANzZ2ADc2dgA3NnYANzZ2AD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8AyMTDAMjEwwDI
xMMAyMTDAMjEwwDIxMMAyMTDAMjEwwDIxMMAyMTDAMjEwwDIxMMAyMTDAMjEwwDIxMMAyMTDAMjE
wwDIxMMAyMTDAMjEwwDIxMMAyMTDAMjEwwDIxMMAyMTDAMjEwwDIxMMAyMTDAMjEwwDIxMMAyMTD
AMjEwwDIxMMAyMTDAMjEwwDIxMMAyMTDAMnEwwDMyMcAlIqIUz4sKvlCMC//QzEw/0MxMP9DMTD/
QzEw/0MxMP9CMC//QjAv/0IwL/9CMC//QjAv/zkmJf+FeHf/4tva/6ignP+akY3/nZSQ/52UkP+d
lJD/npWR/5+Vkf+flpL/oJeT/6CXk/+hmJT/oZiU/6KZlf+imZX/opqW/6Oalv+km5f/pJuX/6Wc
mP+ooJz/bF5b/zwqKf9CMC//QjAv/0IwL/9BLy7/QS8u/0EvLv9BLy7/PSsq/0AvLf+zqaj/3NXU
/6ujn/+rop7/raOg/62koP+tpKD/raWh/6ymof+spqH/raei/62nov+tqKP/rqij/6+opP+wqKT/
sKml/7Gqpf+wqqX/saum/7Grpv+yrKf/sqyn/7OtqP+zraj/s62o/7Suqf+0rqr/ta+q/7Wvq/+2
sKv/trCs/7exrP+3sa3/uLGu/724s/+2sKv/em1r/0IxL/88Kin/QS8u/0EvLv9ALi3/QC4t/z8t
LP8/LSz/Piwr/z4sK/8+LCr/PSsq/zspJ/8zIR//PCsp/25fXv+0qqn/3tfX/+Hc2//Qy8r/xL++
/8C7uf/BvLv/wr28/8K+vf/Dv77/w7++/8TAv//EwL//xcHA/8XBwP/GwsL/x8PC/8fDwv/Hw8L/
x8PC/8jEw//IxMP/ycXE/8nFxP/KxsX/y8fG/8vHxv/MyMf/zMjH/8zIx//MyMf/0s7N/93Z2P/J
wsH/eWtp/ykVEv8wHhvjh3x6N6ihoADDvb0A4N3cAOPg3wDh3t0A1tPSYtPPzvzU0M//1NDP/9XR
0P/X09KE29jWANvY1gDb2NYA29jWANvY1gDb2NYA29jWANvY1gDb2NYA////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AMzIxwDMyMcAzMjHAMzIxwDM
yMcAzMjHAMzIxwDMyMcAzMjHAMzIxwDMyMcAzMjHAMzIxwDMyMcAzMjHAMzIxwDMyMcAzMjHAMzI
xwDMyMcAzMjHAMzIxwDMyMcAzMjHAMzIxwDMyMcAzMjHAMzIxwDMyMcAzMjHAMzIxwDMyMcAzMjH
AMzIxwDMyMcAzMjHAMzIxwDSz84AsKmoJEc2NeNBLy7/RDIx/0MyMf9DMTD/QzEw/0MxMP9DMTD/
QzEw/0MxMP9DMTD/QjAv/zknJv9vYF//4dnZ/6+npP+Xjon/nJOP/5yTj/+ck4//nZSQ/52UkP+d
lJD/npWR/56Vkf+flpL/n5aS/6CXk/+gl5P/oZiU/6GYlP+imZX/opqW/6Oalv+ooJz/fXJv/0Au
Lf9CMC//QjAv/0IwL/9CMC//QjAv/0IwL/9BLy7/Py0s/zspKP+il5b/4NrZ/6ylof+noJv/qKKe
/6qinv+rop7/rKOf/62koP+tpKD/raWg/62lof+tpqH/rKah/62nov+tp6L/raei/66oo/+vqKT/
sKmk/7Cppf+xqqX/saqm/7Grpv+xrKb/sqyn/7Ksp/+zraj/s62o/7OtqP+0rqn/ta6q/7Wvqv+1
r6v/t7Gs/7y4s/+knJj/XU5N/z0pKP9BLy7/QjAv/0IwL/9BLy7/QC8t/0AuLf9ALi3/Py0s/z8t
LP8/LSv/PSsq/zYjIv8+LSv/dmdl/8G2tv/l3d3/29TT/8bBwP+9ubj/vbm4/7+7uv/AvLv/wby7
/8G8vP/Cvbv/wr28/8K+vP/Dvr3/w7++/8TAv//EwL//xcHA/8XBwP/GwsH/x8PC/8bCwf/Hw8L/
x8PC/8fEwv/IxMP/ycXD/8nFxP/KxsX/ysbF/8vHxv/Lx8b/y8fG/8zIx//Lx8b/0s7N/9zY1/+w
qKb/RzY0/y4bGOSSiYgyysXEANbS0QDe29oA4d7eANvY1wDTz85u0s7N/9PPzv/Tz87/08/O7NrX
1Rjd29oA3drZAN3a2QDd2tkA3drZAN3a2QDd2tkA3drZAP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wDZ1tUA2dbVANnW1QDZ1tUA2dbVANnW1QDZ
1tUA2dbVANnW1QDZ1tUA2dbVANnW1QDZ1tUA2dbVANnW1QDZ1tUA2dbVANnW1QDZ1tUA2dbVANnW
1QDZ1tUA2dbVANnW1QDZ1tUA2dbVANnW1QDZ1tUA2dbVANnW1QDZ1tUA2dbVANnW1QDZ1tUA2dbV
ANnW1QDd29kAycXEBl5OTbo+LCv/RDIx/0QyMf9EMjH/RDIx/0MxMP9DMTD/QzEw/0MxMP9DMTD/
QzEw/zwqKP9aS0n/18/P/7myr/+Ui4f/mZCM/5qRjf+akY3/mpGN/5uSjv+ck4//nJOP/52UkP+d
lJD/npWR/52Vkf+elZH/n5aS/5+Wkv+gl5P/oZiU/6GYlP+lnZn/j4WB/0c2NP9BLi3/QzEw/0Mx
MP9DMTD/QjAv/0IwL/9CMC//QjAv/zkmJf+Lf37/49zb/7CopP+mnZn/qaCc/6mhnP+ooZ3/qaKd
/6minv+qop7/q6Oe/6yjn/+to6D/raSg/62lof+tpaH/raah/6ynov+tp6L/raei/66oo/+uqKP/
r6ik/7CppP+wqaX/saql/7Grpv+xq6b/sqyn/7Ksp/+zraj/s62o/7OtqP+zraj/trCr/7mzr/+N
gn//Szo4/z4sK/9DMTD/QzEw/0MxMP9CMC//QjAv/0EvLv9BLy7/QC4t/0AuLf8/LSz/OSYl/zsp
KP9wYmH/wbe3/+bf3v/W0M7/wbu4/7y2sf+9t7P/v7i1/7+5t/++urj/v7q5/7+7uv+/vLv/wLy7
/8G9u//Cvbv/wr27/8K9vP/Cvrz/w769/8O/vv/EwL//xMC//8XBwP/FwcD/xsLB/8bCwf/Hw8L/
x8PC/8jEwv/IxML/yMTD/8jFw//JxcT/ysbF/8rGxf/Lx8b/y8fG/8zIx//MyMf/1tPS/87JyP9r
XFv/NCEg3rCpqCff3NsA1tLRAODd3QDh3t4A3dvaA9PPzqrRzcz/0s7N/9LOzf/W0tGE4N3cAN/d
3ADf3dwA393cAN/d3ADf3dwA393cAN/d3AD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A19TTANfU0wDX1NMA19TTANfU0wDX1NMA19TTANfU0wDX
1NMA19TTANfU0wDX1NMA19TTANfU0wDX1NMA19TTANfU0wDX1NMA19TTANfU0wDX1NMA19TTANfU
0wDX1NMA19TTANfU0wDX1NMA19TTANfU0wDX1NMA19TTANfU0wDX1NMA19TTANfU0wDY1dQA3dra
AIR5eIA8KSj/RTMx/0QyMf9EMjH/RDIx/0QyMf9EMjH/RDIx/0MxMP9DMTD/QzEw/z8tLP9JNzb/
xr28/8fAvf+SiYX/l46K/5iPi/+Yj4v/mI+L/5mQjP+ZkY3/mpGN/5uSjv+bko7/nJOP/5yTj/+d
lJD/nZSQ/52UkP+elZH/npWR/5+Wkv+hmZX/m5KO/1VFQ/9ALi3/RDIx/0MxMP9DMTD/QzEw/0Mx
MP9CMC//QjAv/zknJv9zZGP/4dvb/7auqv+jmpb/p56a/6ifm/+on5v/qaCc/6mgnP+poZ3/qKGd
/6iinf+pop3/qaKe/6ujnv+so5//raOg/62koP+tpaH/raah/62mof+spqL/raei/62nov+tqKL/
rqij/6+opP+vqaT/sKml/7Gqpf+xq6b/saum/7Ksp/+yrKf/trCs/7Ksp/92aWb/QjAv/0IwL/9F
MzL/RDIx/0QyMf9DMTD/QzEw/0IwL/9CMC//QTAu/0EvLv89Kir/NyUk/2BRT/+2rKv/5d7e/9bP
zv++uLb/ubSx/7q2sv+8t7P/vbez/764s/++uLT/vri0/7+5tf++ubf/vrq4/7+6uv+/u7v/v7y7
/8C8u//Bvbz/wr27/8K9u//Cvbz/wr68/8O+vf/Dv77/w8C//8TAv//FwcD/xcHA/8bCwf/GwsH/
x8PC/8fDwv/HxML/yMTC/8jEw//IxcP/ycXE/8rGxf/KxsX/y8fG/8vHxv/PzMv/19TT/4Z6eP9H
NjXTsqyrFNTQzwDY1NQA4N3dAODe3QDX1NIG0MzL0dHNzP/Rzcz/0s7M69fU0hDX1dMA19XTANfV
0wDX1dMA19XTANfV0wDX1dMA////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AM3IyADNyMgAzcjIAM3IyADNyMgAzcjIAM3IyADNyMgAzcjIAM3IyADN
yMgAzcjIAM3IyADNyMgAzcjIAM3IyADNyMgAzcjIAM3IyADNyMgAzcjIAM3IyADNyMgAzcjIAM3I
yADNyMgAzcjIAM3IyADNyMgAzcjIAM3IyADNyMgAzcjIAM3IyADNyMgA1dHRAKOamj5CMC/2QzEw
/0UzMv9FMzL/RDMx/0QyMf9EMjH/RDIx/0QyMf9EMjH/RDIx/0IwL/8+Kyr/rKGh/9XNzP+Viof/
lIuH/5aNif+WjYn/l46K/5eOiv+Xjor/mI+L/5iQjP+ZkIz/mZCM/5qRjf+bko7/m5KO/5yTj/+d
lJD/nZSQ/52UkP+elZH/oZiU/2lbWP8/LSz/RDIx/0QyMf9EMjH/RDIx/0MxMP9DMTD/QzEw/zwq
Kf9bS0n/2dHQ/7+3tf+gmJP/pJyY/6WcmP+lnZn/pp2Z/6eemv+onpv/qJ+b/6mgnP+poJz/qKGc
/6minf+oop3/qaKe/6qinv+ro5//rKOf/62joP+tpKD/raSg/62mof+spqH/raei/62nov+tp6L/
raei/66oo/+vqKP/r6mk/7Gppf+wqqX/trCr/6egm/9jVFL/QS4t/0UzMv9GNDP/RTMy/0UzMv9E
MjH/RDIx/0MxMP9DMTD/QzEw/0EvLv84JiX/TDs6/56Skv/h2dn/2tPS/7+4tf+3saz/ubOu/7u0
sP+7tbL/u7Wz/7u2s/+7t7P/vLez/723s/++uLP/vri0/764tP+/uLX/vrm3/766uf+/u7r/v7u6
/7+8u//AvLv/wby7/8K9u//Cvbz/wr27/8K+vf/Dvr3/w7++/8PAv//EwL//xMDA/8bCwf/GwsH/
x8PB/8fDwf/Hw8L/x8PC/8jEw//IxMP/yMTD/8nFxP/KxsX/ysbF/8zIx//Y1NP/lYuJ/1REQ6/I
w8QF2dXVANfU0wDb2NcA3NnYANXR0DrPy8r50MzL/9DMy//T0M5a2tjWANrY1gDa2NYA2tjWANrY
1gDa2NYA2tjWAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wDNyMgAzcjIAM3IyADNyMgAzcjIAM3IyADNyMgAzcjIAM3IyADNyMgAzcjIAM3IyADN
yMgAzcjIAM3IyADNyMgAzcjIAM3IyADNyMgAzcjIAM3IyADNyMgAzcjIAM3IyADNyMgAzcjIAM3I
yADNyMgAzcjIAM3IyADNyMgAzcjIAM3IyADNyMgA0c3NAMG7ug1VRkTPQC4t/0UzMv9FMzL/RTMy
/0UzMv9FMzL/RTMy/0QzMf9EMjH/RDIx/0QyMf87KCf/i359/97X1v+bko7/kYeE/5WKh/+Wioj/
louI/5WMif+WjYn/lo2J/5aNif+Xjor/mI+L/5iPi/+ZkIz/mZCM/5mQjP+akY3/m5KO/5uSjv+c
k4//oZmV/35zb/9DMS//RDIx/0UzMv9EMjH/RDIx/0QyMf9EMjH/RDIx/z8tLP9JNzb/xLu7/8zF
w/+flpL/o5qW/6Sbl/+km5f/pJuX/6ScmP+lnJj/pZ2Z/6admf+nnpr/p56a/6ifm/+poJz/qaCc
/6mhnf+poZ3/qKKd/6minf+pop7/q6Ke/6yjn/+tpKD/raSg/62lof+tpaH/rKah/6ymof+sp6L/
raei/62nov+uqKP/tK+q/5uSjv9WR0X/QS8u/0c1NP9HNTT/RjQz/0Y0M/9FMzL/RTMy/0UzMv9E
MjH/RDIx/z4sK/89Kir/d2lo/9DHx//j3Nv/xL25/7Wvqv+2sKz/uLKu/7iyrv+5s67/urSu/7q0
r/+6tLD/urWy/7q1sv+7trP/u7ez/7y3s/+9t7P/vriz/764tP+/uLT/v7m2/7+5t/++urj/vrq5
/7+7uv+/vLv/wLy7/8G8u//Cvbv/wr27/8O9u//Cvr3/wr69/8O/vv/DwL//xMC//8XBwP/FwcD/
xsLB/8bCwf/Hw8L/x8PC/8fDwv/IxMP/yMTD/8nFxP/JxcT/ysbF/9XS0f+ckpH/dmlogtHNzQDa
1tYA1tLSANTQzwDTz84AzMjHxc7Kyf/Oy8n/0MzL0dvZ1wfd2tgA3NnYANzZ2ADc2dgA3NnYANzZ
2AD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
z8rKAM/KygDPysoAz8rKAM/KygDPysoAz8rKAM/KygDPysoAz8rKAM/KygDPysoAz8rKAM/KygDP
ysoAz8rKAM/KygDPysoAz8rKAM/KygDPysoAz8rKAM/KygDPysoAz8rKAM/KygDPysoAz8rKAM/K
ygDPysoAz8rKAM/KygDPysoA0MzLANTQ0AB5bGuKPisq/0Y0M/9GNDP/RTQy/0UzMv9FMzL/RTMy
/0UzMv9FMzL/RTMy/0UzMv88Kin/aFlY/97X1v+nnpv/jYSA/5KJhf+SiYX/k4qG/5SKh/+Viof/
loqH/5aLiP+WjIn/lo2J/5aNif+Wjon/l46K/5eOiv+Yj4v/mI+L/5mQjP+ZkIz/nZSQ/5CGg/9N
PTv/QjAv/0UzMv9FMzL/RTMy/0UzMv9EMjH/RDIx/0MxMP8+LCr/ppua/9rT0v+gl5P/oJeT/6KZ
lf+imZX/opqW/6Obl/+km5f/pJuX/6Sbl/+knJj/pZyY/6Wdmf+mnZn/p56a/6eemv+on5v/qZ+b
/6mgnP+poZ3/qaGd/6iinf+pop3/qqKe/6uinv+so5//raOf/62koP+tpKD/raWh/6ymof+tp6L/
sq2o/46Fgv9PPjz/RDIx/0k2Nv9INjX/RzY0/0c1NP9GNDP/RjQz/0U0M/9FMzL/RDIx/zwpKP9R
QD//qp+f/+be3v/PyMb/ta+q/7OuqP+2sKv/trCr/7exrP+3sq3/t7Gu/7iyrf+4sq7/ubOu/7mz
rv+6tK//urSw/7u0sv+7tbP/u7az/7u3s/+8t7P/vbiz/764s/++uLT/v7i0/7+5tf+/ubf/vrm4
/767uf+/u7r/v7y7/8C8u//BvLv/wby7/8K9u//Dvbz/wr28/8O+vf/Dv77/xMC//8TAv//EwL//
xcHA/8bCwf/GwsH/x8PB/8fDwv/Hw8L/yMTC/8jEw//IxMT/0s/N/5mPjvqdlJRI2dbWANbS0QDc
2NcA3drZAMzIxmPLx8b/zcnI/83JyP/U0M853NnYANvY1wDb2NcA29jXANvY1wDb2NcA////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////ANHNzQDRzc0A
0c3NANHNzQDRzc0A0c3NANHNzQDRzc0A0c3NANHNzQDRzc0A0c3NANHNzQDRzc0A0c3NANHNzQDR
zc0A0c3NANHNzQDRzc0A0c3NANHNzQDRzc0A0c3NANHNzQDRzc0A0c3NANHNzQDRzc0A0c3NANHN
zQDRzc0A0c3NANjT0wChmJc+QjAv+UUzMv9GNDP/RjQz/0Y0M/9GNDP/RjQz/0UzMv9FMzL/RTMy
/0UzMv9BLi3/Tj49/83Gxf+5sa7/jYJ9/5KHg/+SiIP/koiE/5GIhP+SiYX/koqG/5OKhv+Uiob/
lYqH/5WKh/+Wi4j/loyI/5aNif+WjYn/lo2J/5eOiv+Xjor/mZCM/5qSjv9gUU//QS8u/0Y0M/9G
NDP/RTMy/0UzMv9FMzL/RTMy/0UzMv87KCf/gnV0/+DZ2f+mnpr/nZSQ/6CXk/+gl5P/oZiU/6GY
lP+imZX/opmV/6Oalv+jmpb/pJuX/6Sbl/+km5f/pJyY/6WcmP+lnZn/pp2Z/6eemv+nnpr/qJ+b
/6mfm/+poJz/qaGc/6mhnf+oop3/qaKe/6qinv+rop7/rKOf/62jn/+upaL/saqm/4V6dv9KOTj/
RjQz/0k3Nv9JNzb/SDc1/0g2Nf9HNjT/RzU0/0c1NP9HNTP/QzEw/z0rKv9zZGP/08rK/+DZ2P+7
tbH/sKql/7OtqP+0rqn/ta+q/7Wvqv+2r6v/trCr/7awrP+3saz/t7Kt/7eyrv+4sq3/uLKu/7mz
rv+5s67/urSv/7q0sP+7tbH/u7Wy/7u2tP+8t7P/vLez/724s/++uLP/v7iz/764tP+/ubX/v7m3
/765uP++urn/v7u6/7+7u//AvLv/wb27/8K9vP/Cvbv/w728/8K9vP/Cvr3/w7++/8O/vv/EwL//
xcHA/8XBwP/GwsD/xsLB/8fDwf/Hw8L/x8PC/8jEw//Oysj/nJOR2LWurRPMx8cA1tPSAOXi4QDX
1NIKv7q4yc3Kyf/MyMf/z8vKptzY2ADc2NgA3NjYANzY2ADc2NgA3NjYAP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDf3NwA39zcAN/c3ADf3NwA
39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf
3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAN/c3ADf3NwA39zcAOLg
4ADRzcwKVkZFz0IwL/9HNTT/RjUz/0Y0M/9GNDP/RjQz/0Y0M/9GNDP/RjQz/0Y0Mv9EMjH/QC0s
/62iof/PyMb/jIJ+/46Egf+QhYL/kYaC/5KHg/+TiIT/k4iE/5KIhP+SiIT/komF/5KJhf+Tiob/
lIqH/5WKh/+Wioj/louI/5aMiP+WjYn/lo2J/5uTj/93bGj/QzEw/0Y0M/9GNDP/RjQz/0Y0M/9G
NDP/RTMy/0UzMv8+LCv/X09O/9rS0v+0rKn/mZCM/56Vkf+elZH/n5aS/5+Wkv+gl5P/oJeT/6GY
lP+hmZX/opmV/6Kalv+jmpb/o5uX/6Sbl/+km5f/pJuX/6WcmP+lnJj/pp2Z/6admf+nnpr/qJ+b
/6ifm/+poJz/qaCc/6mhnf+poZ3/qKKd/6iinf+rpJ//r6ei/31wbf9INzb/STc2/0o4N/9KODf/
Sjg2/0k3Nv9JNzb/SDY1/0g2Nf9HNTT/QS8u/0c1NP+cj47/5d3d/83Gw/+wqqX/r6qk/7Ksp/+z
raj/s62o/7OtqP+zraj/tK6p/7Wvqv+1r6r/trCr/7awq/+3saz/t7Gs/7exrf+4sq3/uLKu/7iy
rv+5s67/ubOu/7q0r/+7tbD/u7Wx/7u2s/+7trP/vLez/723s/++uLP/vriz/764s/+/uLT/v7m1
/7+5t/++urj/v7u5/7+7uv/AvLv/wLy7/8G9vP/BvLv/wr27/8K9vP/Cvrz/w769/8O/vv/EwL//
xMC//8XBwP/FwcD/xsLB/8bCwf/Hw8L/yMTD/8jEwv+on5+Lu7W2AMvHxwDV0tEA1tLRALmysFzF
wb//zMjH/8vHxuvX1NMT2tfWANrX1QDa19UA2tfVANrX1QD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A1tPSANbT0gDW09IA1tPSANbT0gDW09IA
1tPSANbT0gDW09IA1tPSANbT0gDW09IA1tPSANbT0gDW09IA1tPSANbT0gDW09IA1tPSANbT0gDW
09IA1tPSANbT0gDW09IA1tPSANbT0gDW09IA1tPSANbT0gDW09IA1tPSANbT0gDf3NsAg3h2gT4s
Kv9HNTT/RzU0/0c1NP9GNTT/RjQz/0Y0M/9GNDP/RjQz/0Y0M/9GNDP/PCko/4R3dv/c1dT/lYuH
/42Bff+PhYH/j4WB/46Fgf+PhYH/j4WC/5GGgv+Sh4P/k4iE/5KIhP+SiIT/komE/5KJhf+SiYX/
k4qG/5SKh/+ViYf/lYqH/5mOi/+Mgn7/TTw6/0UzMv9HNTT/RzUz/0Y0M/9GNDP/RjQz/0Y0M/9D
MC//RjUz/8K5uP/Gv73/mI6K/5yTj/+dlJD/nZSQ/52UkP+dlJD/npWR/5+Wkv+flpL/oJeT/6CX
k/+hmJT/oZiU/6KZlf+impX/opqW/6Oalv+km5f/pJuX/6Sbl/+lnJj/pZyY/6admf+mnZn/p56a
/6ifm/+on5v/qaCc/6mgnP+ro5//qqOf/3ZqZ/9INjX/Sjk3/0s6OP9LOTj/Szk3/0o4N/9KODf/
STc2/0k3Nv9INjX/Pywr/1lKSP++tLP/49zb/7u1sf+spqH/r6ik/7Gqpf+wqqX/saum/7Grpv+y
rKf/sqyn/7OtqP+zraj/s62o/7Suqf+0rqr/ta+q/7avq/+2sKv/t7Cs/7exrP+3sa3/t7Gu/7iy
rv+4sq7/ubKu/7qzrv+6tK//urSw/7u1sf+7tbL/u7a0/7y3s/+8t7P/vriz/764s/++uLP/vri0
/7+5tf+/ubf/vrq4/766uf+/u7r/v7y7/8C8u//Bvbz/wby7/8K9u//Cvbz/wr68/8K+vf/Dv77/
w7++/8TAv//FwcD/xcHA/8bCwf/Hw8P/wr2888C7ujvj4OAA39vbANrX1gDGwcAHrqelw8zJyP/K
xcT/0MzLVdbU0gDW09IA1tPSANbT0gDW09IA////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////ANTQzwDU0M8A1NDPANTQzwDU0M8A1NDPANTQzwDU0M8A
1NDPANTQzwDU0M8A1NDPANTQzwDU0M8A1NDPANTQzwDU0M8A1NDPANTQzwDU0M8A1NDPANTQzwDU
0M8A1NDPANTQzwDU0M8A1NDPANTQzwDU0M8A1NDPANTQzwDa19YAraalLEg2NPVGNDP/RzU0/0c1
NP9HNTT/RzU0/0c1NP9HNTT/RzU0/0Y0M/9GNDP/QC4t/15OTP/Yz87/p56a/4h9ef+Og3//joN/
/46Df/+PhID/j4WB/46Fgf+OhYH/j4WB/5CFgv+RhoL/koaD/5KHg/+SiIT/koiE/5KJhP+SiYX/
koqF/5OKh/+VjIj/YVNQ/0MxMP9HNTT/RzU0/0c1NP9HNTT/RzU0/0Y0M/9FNDP/Pisq/5mNjP/Z
0tD/mpGN/5mQjP+akY3/m5KO/5yTj/+ck4//nZSQ/52UkP+dlJD/nZSQ/56Vkf+elZH/n5aS/5+W
kv+gl5P/oZiU/6GYlP+imZX/opqW/6Oalv+jm5f/pJuX/6Sbl/+knJj/pZyY/6WcmP+mnZn/pp6a
/6eemv+poZz/qKGc/3NmY/9JNjX/TDo5/0w7Ov9MOjn/TDo4/0s5OP9LOTj/Sjk3/0o4N/9INjX/
QC4s/3JjYv/Vzcz/2NHP/7Cqpf+qpJ//raei/66oo/+vqKP/r6ik/7Gqpf+wqqX/sKql/7Grpv+y
rKf/sqyn/7OtqP+zraj/s62o/7OtqP+0rqn/tK6p/7Wvqv+2r6v/trCr/7ewrP+3sa3/t7Gt/7ex
rv+3sq3/uLKt/7mzrv+6s67/urSv/7q1sP+7tbH/urWz/7u2s/+7trP/vbez/724s/++uLP/vri0
/7+4tP+/ubX/v7m3/766uP++urn/v7u6/7+8u//AvLv/wby7/8K9u//CvLz/wr28/8O9vP/Dvr3/
w7++/8PAv//EwL//xMC//8bCwf/Fwb/V1NDPCdfS0gDAurkAvri3AKafnGW+ubf/ysbF/8rGxajS
zs0A0s/OANLPzgDSz84A0s/OAP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wDLxsUAy8bFAMvGxQDLxsUAy8bFAMvGxQDLxsUAy8bFAMvGxQDLxsUA
y8bFAMvGxQDLxsUAy8bFAMvGxQDLxsUAy8bFAMvGxQDLxsUAy8bFAMvGxQDLxsUAy8bFAMvGxQDL
xsUAy8bFAMvGxQDLxsUAy8bFAMvGxQDMx8YAzsrIA2haWbVBLi3/SDY1/0g2Nf9HNjT/RzY0/0c1
NP9HNTT/RzU0/0c1NP9HNTT/RTMx/0UzMf+8srL/wbi2/4Z7d/+LgHz/i4B8/4yBff+MgX3/jYJ+
/46Df/+Og3//j4SA/4+Fgf+PhYH/joWB/4+Fgf+PhYL/kYaC/5KHg/+Sh4P/koiE/5KIhP+VjYn/
eW9r/0U0M/9HNTT/SDY1/0c2NP9HNTT/RzU0/0c1NP9HNTT/Py0r/2tcW//e1tb/pp2Z/5WMiP+Z
kIz/mZCM/5mRjf+akY3/m5KO/5uSjv+ck4//nJOP/52UkP+dlJD/nZSQ/56Vkf+elZH/n5aS/5+W
kv+gl5P/oJeT/6GYlP+hmJT/oZmV/6KZlf+impb/o5uX/6Sbl/+km5f/pJuX/6WcmP+nnpr/pp6Z
/3FkYP9KNzb/TTs6/048O/9NOzr/TDs5/0w6Of9MOjn/Szo4/0s5OP9INjX/RDIw/4p9fP/i2tr/
y8PB/6ujnv+spJ//raah/6ymof+tp6L/raei/62nov+uqKP/r6ik/7CppP+xqaX/sKql/7Cqpf+x
q6b/sqyn/7Ksp/+zraj/s62o/7OtqP+zraj/tK6p/7Suqf+1r6r/tq+r/7awq/+3sav/t7Gs/7ex
rf+3sq3/uLKu/7iyrf+5s67/ubOu/7q0r/+6tLD/u7Wx/7u1s/+7trT/u7az/723s/+9uLP/vriz
/764tP+/ubT/v7m1/7+5t/++urj/v7q6/7+7uv+/vLv/wLy7/8G8u//Cvbv/wr28/8O9u//Dvrz/
wr69/8O/vv/EwL//xMC+/8rFxF/X09IA2tbVANzZ2ADIw8ERpZ6c4MrHxv/Hw8Hr0c7MFNTSzwDU
0c8A1NHPANTRzwD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A08/PANPPzwDTz88A08/PANPPzwDTz88A08/PANPPzwDTz88A08/PANPPzwDTz88A
08/PANPPzwDTz88A08/PANPPzwDTz88A08/PANPPzwDTz88A08/PANPPzwDTz88A08/PANPPzwDT
z88A08/PANPPzwDTz88A2tfXAJOKiFVBLy3/SDY1/0g2Nf9INjX/SDY1/0g2Nf9HNjT/RzU0/0c1
NP9HNTT/RzU0/z4rKv+OgYD/18/O/4uBff+JfXn/i4B8/4uAfP+LgHz/i4B8/4yBff+MgX3/jYJ+
/42Cfv+Og3//j4SA/4+EgP+PhID/joWB/46Fgf+PhYH/j4WC/5GGgv+TiIX/joN//1NDQf9GNDP/
SDY1/0g2Nf9INjX/SDY1/0c1NP9HNTT/RDIx/0s6Of/Hvr3/vbWy/5GJhP+Xjor/l46K/5iPiv+Y
j4v/mZCM/5mQjP+ZkY3/mpGN/5qSjv+bko7/nJOP/52Tj/+clJD/nZSQ/52UkP+elZH/npWR/5+W
kv+flpL/oJeT/6CXk/+gmJT/oZiU/6GZlf+impb/opqW/6Obl/+lnZj/pZ2Y/3BjYf9LOTf/Tjw7
/089PP9OPDv/Tjw7/008Ov9NOzr/TDs5/0w6Of9HNjT/STc2/6CVlP/m397/vLaz/6efm/+rop7/
raOf/62koP+tpaH/raWh/62mof+spqH/rKeh/62nov+tp6L/rqij/6+oo/+vqaT/sKml/7Cqpf+x
qqb/saum/7Ksp/+yrKf/s62o/7OtqP+zraj/s62o/7Suqf+0rqn/ta+q/7Wvq/+2sKv/trCr/7ax
rP+3sq3/t7Kt/7iyrf+4sq3/ubOu/7qzrv+6tK//urSw/7u1sf+7tbP/u7az/7y3s/+8t7P/vbiz
/764s/++uLP/vri0/764tf+/ubf/v7q4/7+6uv+/u7r/v7y7/8C8u//Bvbz/wr27/8K9u//Cvbv/
wr68/8K+vf/EwL7e19TSGNvY1wDOyskAzcjHAJ+WlHq8trX/x8PC/87LylbX1NMA1tPSANbT0gDW
09IA////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AMzIxwDMyMcAzMjHAMzIxwDMyMcAzMjHAMzIxwDMyMcAzMjHAMzIxwDMyMcAzMjHAMzIxwDMyMcA
zMjHAMzIxwDMyMcAzMjHAMzIxwDMyMcAzMjHAMzIxwDMyMcAzMjHAMzIxwDMyMcAzMjHAMzIxwDM
yMcA0MvLAMfBwRBYSEfaRTIx/0k3Nv9INzX/SDY1/0g2Nf9INjX/SDY1/0g2Nf9INjT/RzY0/0Ev
Lv9fT07/2tLS/52TkP+DeHT/iX56/4l+ev+Kf3v/in97/4uAfP+LgHz/i4B8/4yBff+MgX3/jIF9
/42Cfv+Ngn7/joN//4+EgP+PhID/j4WB/46Fgf+OhYH/komF/2pcWv9FMjH/STc2/0k3Nv9INzX/
SDY1/0g2Nf9INjX/SDY0/z4sKv+ZjYz/1s7N/5SJhv+Viof/loyJ/5aNif+WjYn/lo2J/5eOiv+X
jor/mI+L/5mQjP+ZkIz/mpGN/5qRjf+bko7/m5KO/5yTj/+ck4//nZSQ/52UkP+dlJD/npWR/56V
kf+flpL/n5aS/6CXk/+gl5P/oZiU/6GYlP+jmpb/pJyY/3JmY/9MOjn/Tz48/08+Pf9PPTz/Tz08
/048O/9OPDv/TTs6/007Ov9HNTT/UD89/7OpqP/j3Nv/tKyo/6Wemf+ooZ3/qaKe/6qinv+ro57/
rKOf/62koP+tpKD/raWh/62mof+spqH/rKah/6ynov+tp6L/raei/66oo/+vqKP/sKml/7CppP+w
qqX/saql/7Grpv+yrKf/sqyn/7OtqP+zraj/s62o/7OtqP+0rqn/tK6q/7Wvqv+2sKv/trCr/7aw
q/+3saz/t7Kt/7eyrf+4sq3/uLOu/7mzrv+6tK7/urSv/7q0sP+6tLH/urWz/7u2s/+8t7T/vbez
/724s/++t7P/vriz/7+4tP+/uLX/v7m3/7+6uf+/urn/v7u6/7+8u//AvLv/wb27/8K9u//Cvbv/
wby6/8fDwWTW09EA0MzKAL22tQCooJ4goJeV8cnFxP/JxMOp2NXUANnW1QDZ1tUA2dbVAP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDJxMMAycTD
AMnEwwDJxMMAycTDAMnEwwDJxMMAycTDAMnEwwDJxMMAycTDAMnEwwDJxMMAycTDAMnEwwDJxMMA
ycTDAMnEwwDJxMMAycTDAMnEwwDJxMMAycTDAMnEwwDJxMMAycTDAMnEwwDJxMMAycTEAMzIxwB+
cnF6Qi8u/0k3Nv9JNzb/STc2/0k3Nv9INjX/SDY1/0g2Nf9INjX/SDY1/0Y0M/9FMzL/urGw/720
sv+BdXH/hnt3/4d8eP+HfHj/iH15/4h9ef+Jfnr/in97/4p/e/+LgHz/i4B8/4uAfP+LgHz/jIF9
/4yBff+Ngn7/jYJ+/42Cfv+Og3//kYeD/4J3c/9MOzn/SDY1/0k3Nv9JNzb/STc2/0k3Nv9INjX/
SDY1/0EvLv9oWFf/2tPS/6KZlf+QhoP/lIqH/5WKh/+Wioj/lYuI/5aMif+WjYn/lo2J/5aNif+X
jor/l46K/5iPi/+ZkIz/mZCM/5mQjP+akY3/m5KO/5uSjv+ck4//nZSQ/52UkP+dlJD/nZSQ/56V
kf+elZH/n5aS/5+Wkv+hmJT/o5qW/3VpZv9NPDr/UD89/1FAPv9QPj3/UD49/08+PP9PPTz/Tj07
/049O/9HNTT/V0dF/8G3tv/d19b/raSh/6WcmP+on5v/qaCc/6mhnf+ooZ3/qKKd/6iinf+qop7/
qqOf/6yjn/+to5//raSg/62lof+tpaH/rKah/6ymof+tp6L/raei/62nov+uqKP/rqik/7CppP+w
qaX/sKql/7Cqpf+xq6b/saum/7Ksp/+zraj/s62o/7OtqP+zraj/tK6p/7Wvqv+1r6r/ta+r/7aw
q/+2sKv/t7Gs/7exrf+3sq3/uLKt/7iyrv+5s67/ubOu/7q0r/+7tbD/u7Sy/7q1s/+7trT/vLez
/723s/++t7P/vriz/764s/+/ubT/v7m1/765t/++urj/vru5/7+7u/+/u7v/wLy7/8G9u//BvLvc
1NDPGd3Z2ADQy8oAy8bFAJSKh7G+ubf/xcHA6tTQzxbY1dMA19TSANfU0gD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A3draAN3a2gDd2toA3dra
AN3a2gDd2toA3draAN3a2gDd2toA3draAN3a2gDd2toA3draAN3a2gDd2toA3draAN3a2gDd2toA
3draAN3a2gDd2toA3draAN3a2gDd2toA3draAN3a2gDd2toA3draAOPg4QDDvr4hSzs56Uc1NP9J
Nzb/STc2/0k3Nv9JNzb/STc2/0k3Nv9INjX/SDY1/0g2Nf8/LCv/hnl3/9fQz/+HfHj/g3h0/4V6
dv+Ge3f/hnt3/4Z7d/+HfHj/h3x4/4h9ef+IfXn/iX56/4l+ev+Kf3v/i4B8/4uAfP+LgHz/i4B8
/4yBff+MgX3/jYJ+/4+EgP9gUE7/RzQz/0o4N/9KODf/STc2/0k3Nv9JNzb/STc2/0c1NP9GNTT/
vrS0/7+2tP+Ng37/koiE/5KJhf+SiYX/k4qG/5SKhv+Viof/lYqH/5WLiP+WjIn/lY2J/5aNif+W
jon/l46K/5eOiv+Yj4v/mI+L/5mQjP+ZkIz/mpGN/5uSjv+bko7/nJOP/5yTj/+dlJD/nZSQ/52U
kP+elZH/opmV/3puav9PPTz/UEA+/1FBP/9RQD7/UEA+/1A/Pv9QPz3/UD49/089PP9INjT/XU1M
/8nAv//Y0c//p5+b/6Kalv+mnpr/p56a/6eemv+on5v/qZ+b/6mgnP+poZ3/qKGd/6iinf+pop3/
qqKe/6uin/+so5//raOf/62koP+tpaH/rKWh/62mof+tp6L/raei/62nov+tp6L/rqij/6+oo/+v
qKT/r6mk/7CppP+wqqX/sKql/7Crpf+xq6b/sqyn/7Ksp/+yrKf/s62o/7Suqf+0r6r/ta+q/7Wv
q/+2sKv/trCr/7exrP+3sa3/t7Ku/7eyrf+5s67/ubOu/7mzrv+6tK//urSw/7u1sf+6tbP/u7a0
/7y3s/+9t7P/vrey/764s/++uLP/vri0/7+5tf++ubf/vrq4/766uf+/u7r/v7u6/8TAv43Sz84A
09DPAN3Z2QCooZ9RoZmW/sbCwf/LyMZE09HPANLPzgDSz84A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AM7KyQDOyskAzsrJAM7KyQDOyskAzsrJ
AM7KyQDOyskAzsrJAM7KyQDOyskAzsrJAM7KyQDOyskAzsrJAM7KyQDOyskAzsrJAM7KyQDOyskA
zsrJAM7KyQDOyskAzsrJAM7KyQDOyskAzsrJAM7KyQDT0M8AeGxrmkMwL/9KODf/Sjg3/0o4N/9J
Nzb/STc2/0k3Nv9JNzb/STc2/0k3Nv9EMjH/V0dF/9LKyv+flpP/fnNu/4N5df+EeXX/hHl1/4R5
df+Fenb/hnt3/4Z7d/+Ge3f/h3x4/4d8eP+IfXn/iH15/4l+ev+Jfnr/in97/4p/e/+LgHz/i4B8
/4+EgP95bGn/Sjg3/0o4N/9KODf/Sjg3/0o4N/9KODb/STc2/0k3Nv9BLi3/h3p5/9fQz/+SiIT/
kIWB/5KHg/+SiIT/koiE/5KJhP+SiYX/komF/5OKhv+Uiof/lYmH/5WKiP+Vi4j/lYyJ/5aNif+W
jYn/lo2J/5eOiv+Xjor/mI+L/5mQjP+ZkIz/mpGN/5qRjf+bko7/m5KO/5yTj/+ck4//oZiU/39z
cP9QQT//UkE//1JCQP9SQUD/UUE//1FAP/9QQD7/UD8+/1A/Pf9JNzb/YlJQ/87Gxf/TzMv/o5uX
/6KZlf+knJj/pZyY/6WcmP+lnJn/pp2Z/6aemv+nnpr/qJ+b/6mgnP+poJz/qaGd/6ihnf+pop3/
qaKd/6qinv+rop7/rKOf/6yjn/+tpKD/raSg/62lof+rpKD/q6Wg/6qkn/+tp6L/rqij/bCqpt+z
rKjLtK2qy7Wvqsq1r6vJtbCrybSvqsu0rqrLtK6p3bOtqP2yrKf/saum/7Ksp/+zraj/tK6p/7Wv
qv+1r6v/trCr/7awrP+3saz/t7Gt/7iyrf+3sq3/uLOu/7mzrv+5s67/urSv/7q0sP+7tbH/u7Wz
/7u2s/+7trP/vLez/724s/++uLP/vriz/7+4tP++ubX/v7m3/766uP+9ubjuy8jHH9HOzADKxcQA
vbi3DYuAft/CvLr/ysXDi97c2gDd29kA3dvZAP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wDEv74AxL++AMS/vgDEv74AxL++AMS/vgDEv74AxL++
AMS/vgDEv74AxL++AMS/vgDEv74AxL++AMS/vgDEv74AxL++AMS/vgDEv74AxL++AMS/vgDEv74A
xL++AMS/vgDEv74AxL++AMS/vgDKxcQArKWjLUk3NvZJNjX/Sjg3/0o4N/9KODf/Sjg3/0o4N/9J
Nzb/STc2/0k3Nv9JNzb/Qi8u/6menf/EvLr/e3Bs/4F2cv+Cd3P/gndz/4N4dP+DeHT/hHl1/4R5
df+Fenb/hXp2/4Z7d/+Ge3f/hnt3/4d8eP+HfHj/iH15/4h9ef+Jfnr/iX56/4uAfP+Kf3v/WUlH
/0g2Nf9LOTj/Szk4/0o5N/9KODf/Sjg3/0o4N/9GNDP/VURD/9LKyf+on5z/ioB8/4+Fgv+QhYL/
kYaC/5KHg/+Sh4P/koiE/5KIhP+SiIT/kYmF/5KJhf+Tiob/lImG/5WKh/+Vioj/louI/5WMiP+W
jYn/lo2J/5aOif+Xjor/l46K/5iPi/+Yj4v/mZCM/5mRjf+akY3/npaS/4R6dv9TREL/UUJA/1ND
Qf9TQ0D/UkJA/1JBP/9SQT//UUE//1FAPv9JODb/YlNR/9DHx//Qycf/oJiT/6CYlP+jmpb/o5qW
/6Sbl/+km5f/pJuX/6ScmP+lnJj/pZ2Z/6admf+nnpr/p56a/6ifm/+poJz/qaCc/6mhnf+poZ3/
qaKd/6minf+ooZz/qKCc/6uinvqupaHZs6qmsrexq3/FwLxcu7ayMM/LyCnW0s4OuLOvAL65twDH
wr0AyMK9AMXBvADCvrgAu7axAMzJxg7Lx8Msv7q2OMO/vHC6tbGTtrGs0LOtqOqyrKf/sq2o/7Su
qf+1r6r/ta+r/7awq/+2sKv/t7Gs/7exrf+4sq3/t7Ku/7mzrv+5s67/urOu/7u0r/+6tLD/u7Wy
/7q1s/+7trP/u7az/7y3s/+9t7P/vbiz/764s/++uLT/vri0/8K9u47OyscA0MzKANLNzQCPhIGV
rqel/8fDwdTU0dAD1NHQANTR0AD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8AvLW0ALy1tAC8tbQAvLW0ALy1tAC8tbQAvLW0ALy1tAC8tbQAvLW0
ALy1tAC8tbQAvLW0ALy1tAC8tbQAvLW0ALy1tAC8tbQAvLW0ALy1tAC8tbQAvLW0ALy1tAC8tbQA
vLW0ALy1tAC8trUAwLq6AG9hYKJEMjH/Szk4/0s5N/9KODf/Sjg3/0o4N/9KODf/Sjg3/0o4N/9J
Nzb/QjAv/29hYP/X0M7/in97/31ybv+AdXH/gHVx/4F2cv+BdnL/gndz/4J3c/+DeHT/g3h0/4R5
df+EeXX/hXp2/4V6dv+Ge3f/hnt3/4Z7d/+HfHj/h3x4/4h9ef+LgX3/cmVi/0k4Nv9LOTj/Szk4
/0s5OP9LOTj/Szk4/0o4N/9KODb/QjAv/6GWlf/KwsD/i4B8/4+EgP+PhYD/j4WB/46Fgf+OhYH/
j4aC/5GGgv+Sh4P/koeD/5KIhP+SiIT/kYmE/5KJhf+SiYX/k4qG/5OJhv+ViYf/lYqH/5aKiP+W
jIj/lo2J/5aNif+Wjon/l46K/5eOiv+Yj4v/nJOP/4uBfP9XSUb/UkNA/1NFQv9TREL/U0NB/1JD
Qf9SQ0D/UkFA/1JBP/9KOjf/Y1RS/9DIx//Nx8T/npWR/5+Wkv+hmJT/oZiU/6GZlf+imZX/o5qW
/6Oalv+km5f/pJuX/6Sbl/+lnJj/pZyY/6Wdmf+mnZn/p56a/6eemv+onpr/p52Z/6ifm/+pop3k
sKqmrru3tHTCvboytrCsCsrHxwC8ucIDx8bQAL+/zAHR0NoAcG6NAF1cgACxsMEAq6q5AKimsgCy
sLsAq6mzALGtrwDT0c8AzsrGAMrEwADU0M0Az8zIAMK+ugLCvrodwr26Wbq1saizrajqsqyn/7Ot
qP+0rqn/ta+q/7Wvqv+2sKv/trCs/7exrf+3sa3/t7Kt/7eyrv+4sq3/ubOu/7mzrv+6tK//urSw
/7u0sf+6tbP/u7az/7y2s/+9t7P/vbez/724s/+9t7Lwy8bDIdHNywDRzcwAqaGgRJGIhf7EwMDo
zMnHF9DNywDQzMsA////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////ALmzsgC5s7IAubOyALmzsgC5s7IAubOyALmzsgC5s7IAubOyALmzsgC5s7IAubOy
ALmzsgC5s7IAubOyALmzsgC5s7IAubOyALmzsgC5s7IAubOyALmzsgC5s7IAubOyALmzsgC5s7IA
vrm4AKCYlzRJNzb4Sjg3/0s5OP9LOTj/Szk4/0o4N/9KODf/Sjg3/0o4N/9KODf/STY1/0g3Nf/B
ubf/raSh/3dsZ/9+c2//f3Rv/390cP+AdXH/gHVx/4B1cf+BdXH/gXZy/4J3c/+Cd3P/gndz/4N4
dP+EeXX/hHl1/4R5df+Fenb/hnt3/4Z7d/+HfHj/hHp1/1VFQ/9KNzf/TDo5/0w6Of9LOTj/Szk4
/0s5OP9LOTj/RTIx/2VVVP/Y0c//mI6K/4p/e/+Ngn7/joN//46Df/+PhID/j4WA/4+Fgf+OhYH/
j4WB/4+Fgv+RhoL/koaD/5KHg/+SiIT/koiE/5KJhP+RiYT/komF/5OKhv+UiYf/lIqH/5WKh/+V
i4j/loyJ/5WNif+WjYn/mZCM/4+Ggv9dUEz/UkRB/1VGQ/9URkP/VEVC/1REQv9TQ0H/U0RB/1ND
Qf9MOzn/YVJQ/8/Ix//NxcT/nJOP/52UkP+flpL/n5aS/5+Xk/+gl5P/oJeT/6GYlP+hmZX/opmV
/6Kalv+jm5b/o5uX/6Sbl/+km5f/pZyY/6Oalv+jmpb/p5+b7LKrp6W3sa5MuLGuFMjDwQDOzMkA
ysXDALm0swDJydYAeHmcixwdV+cmJl/dKSlg1QkIRtAjI1vJVlaBolJSfYFyc5VYkJGsLJGRqwqU
lawAr6/AAJCPpgChn64Av73BAMbDwwDEwLsAyMS/AM/LyADOyscAx8TBGr+6tl64sq7Csqyn+bKs
p/+0rqn/tK6p/7Wvqv+1r6r/trCr/7ewrP+3sa3/t7Ks/7eyrf+4sq3/uLOu/7mzrv+5s67/urSv
/7q0sP+7tbH/u7Wz/7u2s/+7trP/u7ay/8O9uo7X1dIA0s/NAMO/vQyBdnPdu7Wz/8jEwkjRzswA
0M3LAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wC3sbAAt7GwALexsAC3sbAAt7GwALexsAC3sbAAt7GwALexsAC3sbAAt7GwALexsAC3sbAAt7Gw
ALexsAC3sbAAt7GwALexsAC3sbAAt7GwALexsAC3sbAAt7GwALexsAC3sbAAt7GwALy2tQBtYF6k
RjMy/0s5OP9LOTj/Szk4/0s5OP9LOTj/Szk4/0o4N/9KODf/Sjg3/0IvLv+HeXj/0MnH/31ybv96
b2v/fXJu/31ybv9+c2//fnNv/390b/9/dHD/gHVx/4B1cf+AdXH/gXZy/4F2cv+Cd3P/gndz/4J4
dP+DeHT/hHl1/4R6dv+FeXb/iX56/21hXf9KNzb/TDo5/0w6Of9MOjn/TDo5/0w6OP9LOTj/Szg3
/0Y0M/+xqKf/vbWy/4Z7dv+LgHz/jIF9/4yBff+Ngn7/jYJ+/46Df/+Pg3//j4SA/4+FgP+OhYH/
joWB/4+Fgv+PhYL/kYaC/5GHg/+Sh4P/koiE/5GIhP+RiIT/komF/5KJhf+Tiob/lImH/5SKh/+V
ioj/l42K/5OKhv9lWFX/UkRB/1VHRP9VR0T/VEZD/1RGQ/9URUL/U0VC/1NEQv9OPjz/XU5M/8vC
wv/Ox8X/m5KO/5uSjv+dlJD/nZSQ/56Vkf+elZH/n5aS/5+Wkv+gl5P/oJeT/6GYlP+hmJT/oZmV
/6Kalv+impb/oZiU/6KZlvqspaHEtq+sZMbBvhzQzMkAv7m2ALmzsADHwr8AzMnGAMnEwQC5tLQA
wcHQALe3yQ5UU4GvAAA4/wAAPv8AAEH/AAA+/wAAOf8AADz/AgJB/w8PSv4oKFvbS0t0p3BwkGR/
gJ0kioukAJWWrQCEhJ8AqKe1ALe1uQDQy8gA0MvHAM3JxgDLx8QAy8jFAbu1sTu3sa2nsqyn+7Ks
p/+zraj/tK6p/7Suqf+1r6r/ta+q/7awq/+2sKz/t7Gs/7eyrf+3sa7/uLKt/7izrv+5s67/urSu
/7q0r/+6tLD/urWy/7u1sv+5tLPw1NHPIdfU0gDMx8YAhXt4maacmf/KxcKH1tLQANXRzwD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8AurSzALq0
swC6tLMAurSzALq0swC6tLMAurSzALq0swC6tLMAurSzALq0swC6tLMAurSzALq0swC6tLMAurSz
ALq0swC6tLMAurSzALq0swC6tLMAurSzALq0swC6tLMAurSzAL+5uQChmJgySzk4+Es5OP9MOjn/
Szk4/0s5OP9LOTj/Szk4/0s5OP9LOTj/Szk4/0g1NP9SQUD/zsbF/5qQjf91amb/e3Bs/3twbP97
cGz/fHFt/31ybv99cm7/fnNu/35zb/9/dHD/f3Rw/4B1cf+AdXH/gHVx/4F2cv+BdnL/gndz/4J3
c/+DeHT/hHl1/4F2cv9VRUP/Szk4/007Ov9NOzn/TDo5/0w6Of9MOjn/TDo5/0QyMP9yZGL/1tDO
/4+EgP+IfXn/in97/4uAfP+LgHz/i4B8/4yBff+MgX3/jYJ+/42Cfv+Og3//j4SA/4+EgP+PhYH/
joWB/4+Fgf+PhYH/kIWC/5CGgv+Rh4P/koeD/5KIg/+SiIT/kYiE/5KJhf+SiYX/k4qH/5WLiP9v
Yl7/U0VC/1VJRf9WSEX/VUhE/1VHRP9VRkP/VEZD/1VFQ/9QQD7/WUlH/8O7uv/Sy8n/mZCM/5mQ
jP+bko7/nJOP/5yTj/+dlJD/nZSQ/52UkP+elZH/npWR/5+Wkv+flpL/oJeT/5+Wkv+flpH/oZiU
562mo528trM5zsvIAMfCvwDLx8QAzsrHAL64tQC5s7AAx8K/AMzJxgDJxMEAubS0AMDAzwC4uMoA
zc3ZBGRkjKQAAD7/AABD/wEAQ/8BAEL/AABA/wAAP/8AAD3/AAA7/wAAOP8AADr/FRVL9j8/artv
b45ggoKeEqOjuACNjqcAnZ2wALOyuwDGwsEAzcnEAMzIxQDAu7cAw7+7AL+7t0a2sKzJsaul/7Ot
qP+zraj/s62o/7Suqf+0rqn/ta+q/7Wvq/+2sKv/trCs/7exrP+3saz/t7Ku/7iyrv+4sq7/ubOt
/7q0rv+6tK//ubOv/8O+unPU0M4AxL+9AJePjFGMgX7/yMO/v9nX1QTa19UA////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AMW/vwDFv78Axb+/AMW/
vwDFv78Axb+/AMW/vwDFv78Axb+/AMW/vwDFv78Axb+/AMW/vwDFv78Axb+/AMW/vwDFv78Axb+/
AMW/vwDFv78Axb+/AMW/vwDFv78Axb+/AMXAvwDLxsUAcWRjokUyMf9MOjn/TDo5/0w6Of9MOjn/
TDo5/0s5OP9LOTj/Szk4/0s5OP9CMC//l4uK/8a+vP91amX/eG1p/3luav96b2v/e3Bs/3twbP97
cGz/e3Bs/3xxbf99cm3/fXJu/35zbv9+c2//f3Rw/390cP9/dHH/gHVx/4B1cf+AdXH/gXZy/4R6
dv9sX1z/Szk4/007Ov9NOzr/TTs6/007Ov9NOzr/TDo5/0s5OP9INzb/u7Kx/7Oqp/+Cd3P/iH15
/4l+ev+Jfnr/in97/4p/e/+LgHz/i4B8/4uAfP+MgX3/jIF9/42Cfv+Ngn7/joN//4+EgP+PhID/
j4WA/4+Fgf+PhYH/joWB/5CFgv+QhoL/koeD/5KIg/+SiIT/koiE/5WMiP93bWn/VEhE/1ZJRv9W
Skb/VklF/1VIRf9VSET/VUdE/1RHRP9RRED/VEVC/7qvr//X0M7/mZCM/5eOiv+ZkIz/mpGN/5qR
jf+bko7/m5KO/5yTj/+ck4//nZSQ/52UkP+dlJD/nZSQ/5ySjv+fl5PnraejhrexrSDCvbsAyMTB
AM3JxwDFwL0AysbDAM7KxwC+uLUAubOwAMfCvwDMycYAycTBALm0tADAwM8AtrbIAMXF1ADY2OIB
bGySmQAAPv8AAEP/AQBD/wEAQv8AAED/AABA/wAAQP8AAED/AAA//wAAOv8AADX/AAA4/yIiVORi
YoSLi4ulJJiYrgCXl68AhoafALy6wgDGwsEAwby3AMK9ugDLx8QAyMTBB7q1sXWxqqXusqyn/7Ks
p/+zraj/s62o/7OtqP+0rqn/tK6p/7Wvqv+1r6v/trCr/7exrP+3saz/t7Gt/7eyrf+4sq3/uLKu
/7iyrf+7tbHU2dXUCdPPzgC1rqwde25r8723te7QzcsL1NHPAP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wDMx8cAzMfHAMzHxwDMx8cAzMfHAMzH
xwDMx8cAzMfHAMzHxwDMx8cAzMfHAMzHxwDMx8cAzMfHAMzHxwDMx8cAzMfHAMzHxwDMx8cAzMfH
AMzHxwDMx8cAzMfHAMzHxwDRzMwAsKmoK007OvZMOTj/TDo5/0w6Of9MOjn/TDo5/0w6Of9MOjn/
TDo5/0s5OP9GNDP/XEtK/9LLyv+LgX7/c2hj/3dsaP94bWn/eW5q/3luav95bmr/em9r/3twbP97
cGz/e3Bs/3twbP98cW3/fHFt/31ybv9+c27/fnNv/390cP+AdXH/gHVx/4F2cv9/c2//VkZE/0w6
Of9OPDv/TTs6/008Ov9NOzr/TTs6/007Ov9FMzH/eWtq/9PMyv+Jfnn/hXp2/4d8eP+HfHj/iH15
/4h9ef+Jfnr/in97/4p/e/+LgHz/i4B8/4uAfP+LgHz/jIF9/4yBff+Ngn7/jYJ+/46Df/+PhID/
j4SA/4+Fgf+PhYH/joWB/46Fgf+PhYL/kIaC/5WKhv+Cd3P/WExI/1ZKRv9XS0f/V0pG/1ZKRv9W
SUb/VkhF/1ZIRf9URkP/T0E+/6yioP/c1NT/mpGN/5SLh/+Xjor/mI+L/5iPi/+Yj4v/mZCM/5mR
jf+akY3/m5KO/5uSjv+bko7/mpGN/52Vkeiup6SEvbi1HcG8uQC7tbIAwLu5AMbCvwDNyccAxcC9
AMrGwwDOyscAvri1ALmzsADHwr8AzMnGAMnEwQC5tLQAwMDPALa2yADDwtIAz8/cAOLi6QBwcJWR
AAA+/wAAQv8BAEP/AQBC/wAAQP8AAED/AAA//wAAQP8AAED/AAA9/wAAO/8AADf/AAA1/xcXSvFd
XYCPl5etG4aGoQCio7gApKO1ALOwtQDGwbwAy8fCAMjFwQDIxMEAwLu3NLGsp8CvqaT/sqyn/7Ks
p/+zraj/s62o/7OtqP+zraj/tK6p/7Suqf+1r6r/tq+r/7awq/+2sKz/t7Gs/7axrf+3sq3/trCs
/8jEwUHT0M4AyMTDAXxxbsiqoZ/61NDOONjW1AD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8AzsnJAM7JyQDOyckAzsnJAM7JyQDOyckAzsnJAM7J
yQDOyckAzsnJAM7JyQDOyckAzsnJAM7JyQDOyckAzsnJAM7JyQDOyckAzsnJAM7JyQDOyckAzsnJ
AM7JyQDNycgA1dHRAH1wb5hFMzH/TTs6/007Ov9NOzr/TDo5/0w6Of9MOjn/TDo5/0w6Of9MOjn/
RDIw/6OXlv+8tLH/b2Rg/3VqZv92a2f/dmxn/3dsaP93bGj/eG1p/3luav95bmr/eW5q/3pva/97
cGz/e3Bs/3twbP97cGz/fHFt/31ybv99cm7/fnNv/35zb/+BdnL/bGBc/0w7Of9OPDv/Tjw7/048
O/9OPDv/TTs6/007Ov9MOjn/Sjg3/7+2tf+so6D/f3Rw/4V6dv+Ge3f/hnt3/4Z7d/+HfHj/h3x4
/4h9ef+IfXn/iX56/4l+ev+Kf3v/in97/4uAfP+LgHz/i4B8/4uAfP+MgX3/jYJ+/42Cfv+Og3//
joN//4+EgP+PhYD/joWB/5CHg/+Jf3v/X1NP/1ZKRv9YTEj/WExI/1dLR/9XSkf/VkpG/1dJRv9V
SEX/TkA8/5uQjv/f19f/n5WS/5KHhf+VjIn/lo2J/5aNif+WjYn/l46K/5eOiv+Yj4v/mI+L/5mQ
jP+Xjor/mZGN+aefnIy2sa4hxb+9AMK9ugC/urcAurSxAMC7uQDGwr8AzcnHAMXAvQDKxsMAzsrH
AL64tQC5s7AAx8K/AMzJxgDJxMEAubS0AMDAzwC2tsgAw8LSAM3N2gDd3eUA0NDbAF1dh4wCAkT/
AAA7/wAAOP8AADf/AAA2/wAAN/8AADf/AAA6/wAAPf8AADv/AAA8/wAAPP8AADj/AAA2/xwcTuZo
aYptrKy+A5+ftACam7IApKOyAMTBwgDKxsEAxsK/AMXBvgDEv7wRurOwr66no/+xqqX/saum/7Gr
pv+yrKf/s62o/7OtqP+zraj/s62o/7Suqf+0rqn/ta+q/7Wvqv+2sKv/trCr/7awq/+8uLOS0M3K
ANLPzgCKgX6AkYaE/8vGxFDOyscA////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AK2mpQCtpqUAraalAK2mpQCtpqUAraalAK2mpQCtpqUAraalAK2m
pQCtpqUAraalAK2mpQCtpqUAraalAK2mpQCtpqUAraalAK2mpQCtpqUAraalAK2mpQCtpqUAsKio
AKOamhhSQUDpSzk4/007Ov9NOzr/TTs6/007Ov9NOzr/TTs5/0w6Of9MOjn/RzU0/2JSUf/Sysn/
g3p1/3FmYf91amX/dWpm/3VqZv91amb/dmtn/3ZrZ/93bGj/d21o/3htaf94bWn/eW5q/3pva/96
b2v/e3Bs/3twbP97cGz/e3Bs/3xxbf99cm7/fXJu/1lJRv9NOzr/Tz08/049O/9OPDv/Tjw7/048
O/9OPDv/RjQz/3lqaf/Qycj/hXp2/4J3c/+DeHT/hHl1/4V6dv+Fenb/hnt3/4Z7d/+Ge3f/h3x4
/4d8eP+HfXn/iH15/4l+ev+Jfnr/in97/4p/e/+LgHz/i4B8/4uAfP+MgX3/jIF9/42Cfv+Ngn7/
joN//4+EgP+OhID/aV1Z/1dLR/9ZTUn/WU1J/1hMSP9YTEj/V0tH/1dLR/9XSkb/T0E9/4d7eP/g
2dj/pZyZ/46Fgf+Uiof/lIqH/5WKiP+Vi4j/lYyI/5aNif+WjYn/lo2J/5aNiP+VjIj/opmWtL65
tjq/u7gAubSxAMK9ugDBvLkAv7q3ALq0sQDAu7kAxsK/AM3JxwDFwL0AysbDAM7KxwC+uLUAubOw
AMfCvwDMycYAycTBALm0tADAwM8AtrbIAMPC0gDNzdoA19fhAOPj6QDMzNkATk57e0BAeb9SUozR
UVKM/1BRh/9HSH3/ODhv/yQlXv8QEEv/AAA8/wAAM/8AADP/AAA3/wAAO/8AADb/AgI7/0NDbL2V
lKwupqe6AIuMpgC2tsUAysfIAMfDvwDDv7sAycXCANjU0gS2sKx+rqei/7Gppf+wqqX/saql/7Gr
pv+xrKb/sqyn/7OtqP+zraj/s62o/7OtqP+0rqn/ta+q/7Wvqv+1r6r/t7Cs3M/KyAq/ubcAjIF/
SXxvbf/LxcOG1dHPAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wDFv74Axb++AMW/vgDFv74Axb++AMW/vgDFv74Axb++AMW/vgDFv74Axb++AMW/
vgDFv74Axb++AMW/vgDFv74Axb++AMW/vgDFv74Axb++AMW/vgDFv74AxL++AMzHxgCIfXx2RzQ0
/048O/9OPDv/TTw6/007Ov9NOzr/TTs6/007Ov9NOzr/TDs5/0QyMP+onJz/tq2q/2tgW/9yZ2T/
c2hk/3NpZP90aWX/dGll/3VqZv91amb/dWpm/3ZrZ/92a2f/d2xo/3dsaP94bWn/eG1p/3luav96
b2v/em9r/3twbP97cGz/fXJu/29iXv9PPTv/Tz08/089PP9PPTz/Tz08/089O/9OPDv/TTs6/0o4
N/+7sbH/qqKf/3xwbP+BdnL/gndz/4N4dP+DeHT/g3h0/4R5df+EeXX/hXp2/4Z7d/+Ge3f/hnt3
/4Z8eP+HfHj/iH15/4h9ef+Jfnr/iX56/4p/e/+Kf3v/i4B8/4uAfP+LgHz/i4B8/4yBff+PhID/
dGhl/1hMSP9aTkr/Wk5K/1pNSf9ZTUn/WExI/1hMSP9YTEj/UURA/3JmY//d1dX/sKej/42Df/+R
iIT/kYmF/5KJhf+Tiob/lIqG/5SKh/+Wioj/lYuI/5OJhv+Yj4zbtK6rYcnFwgLIxMIAvrm2ALiz
sADCvboAwby5AL+6twC6tLEAwLu5AMbCvwDNyccAxcC9AMrGwwDOyscAvri1ALmzsADHwr8AzMnG
AMnEwQC5tLQAwMDPALa2yADDwtIAzc3aANfX4QDh4egAwsLSAGZmjACZmskA3+D/BrCx/6OLjvr/
iYv4/5KU9f+Xme7/lZff/4mKyP9tbqX/RUZ4/xwcUf8AADj/AAAy/wAANv8AADT/FxdK7oWGoFyU
lKwAtrbHAMPD0QC/vcMAxL+7AMfDwADY1dMAxcG+ALq1sXespqH/r6ij/7CppP+wqaX/sKql/7Gq
pv+xq6b/saum/7Ksp/+yrKf/s62o/7OtqP+zraj/tK6p/7Ksp//Hwr9CzMjGALOsqyFwZWH2urOw
r8fDwAD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8ArKWkAKylpACspaQArKWkAKylpACspaQArKWkAKylpACspaQArKWkAKylpACspaQArKWkAKyl
pACspaQArKWkAKylpACspaQArKWkAKylpACspaQArKWkAK6npQCro6IKW0pJ2Es4N/9OPDv/Tjw7
/048O/9OPDv/Tjw6/007Ov9NOzr/TTs6/0k2Nf9jU1L/0MjI/390cP9tYl7/cWZi/3FmYv9yZ2P/
c2dk/3NoZP90aWX/dGll/3RpZf91amb/dWpm/3ZrZv92a2b/dmtn/3dsZ/94bWj/eG1p/3htaf95
bmr/em9r/3txbP9cTkr/TTw7/1A+Pf9QPTz/Tz08/089PP9PPTz/Tz08/0g2Nf9yYmL/0cnI/4N5
dP9/c2//gHVx/4F2cv+BdnL/gXZy/4J3c/+Cd3P/g3h0/4N4dP+Fenb/hXp2/4V6dv+Fenb/hnt3
/4Z7d/+GfHj/h3x4/4h9ef+Ifnr/iX56/4p/e/+Kf3v/i4B8/4uAfP+Ng3//fnNv/1xPS/9bTkr/
W09L/1tOSv9aTkr/Wk1K/1lNSf9ZTUn/VEhE/2JWUv/Rycj/vLSy/4uBfP+RhoL/koeD/5KHg/+S
iIT/komE/5KJhf+Siob/kYiE/5KIhfukmpiQxL+9GcfDwADLx8QAxsK/AL65tgC4s7AAwr26AMG8
uQC/urcAurSxAMC7uQDGwr8AzcnHAMXAvQDKxsMAzsrHAL64tQC5s7AAx8K/AMzJxgDJxMEAubS0
AMDAzwC2tsgAw8LSAM3N2gDX1+EA4eHoAMLC0gBiYokAkpPDANTV/wCpqvQChYftUT5B5MUeIuH/
ISXj/zQ46P9IS+//Ymb0/4CC9/+Pkej/goTC/1RViP8aG07/AAAz/wAAMf8HBz7/U1N6isPD0AHE
xNAAv7/NAM7M0QDKxsQA19PRAMS/vQDNyscAurWxeKuloP+tp6L/rqej/66oo/+wqaT/sKml/7Cq
pf+wqqb/saum/7Gspv+yrKf/sqyn/7OtqP+xq6b/vbi0k8/LyQCzrKoCcmVj3aqioNTf3dsI////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AMG7ugDB
u7oAwbu6AMG7ugDBu7oAwbu6AMG7ugDBu7oAwbu6AMG7ugDBvLsAwbu7AMG7uwDBu7sAwbu7AMG7
uwDBu7sAwbu7AMG7uwDBu7sAwbu7AMG7uwDHwsIAlYyLUUk2Nf5OPTv/Tjw7/048O/9OPDv/Tjw7
/048O/9OPDv/TTs6/007Ov9FMzH/ppyb/7Oqp/9oXVn/cGVh/3BlYf9wZWH/cGVh/3FmYv9yZ2P/
cmdj/3NoZP9zaGT/c2lk/3RpZf90aWX/dWpm/3VqZv92a2b/dmtm/3ZrZ/93bGj/eG1p/3lvav9x
ZWH/UUA+/08+PP9PPz3/UD89/1A+Pf9QPTz/Tz08/089PP9JNzb/saem/66lov94bWn/fnRw/390
cP+AdXH/gHVx/4B1cf+BdnL/gHVx/4F2cv+Cd3P/g3h0/4N4dP+EeXX/hHl1/4R5df+Fenb/hnt3
/4Z7d/+Ge3f/h3x4/4d8eP+IfXn/iH15/4l+ev+KgHv/hnt3/2NXU/9bTkr/XFBM/1xPS/9bT0v/
W05K/1pOSv9aTkr/V0tH/1dKRv+8srH/zMXD/4yCfv+OhID/j4WB/4+Fgv+QhoL/kYaD/5KIhP+S
h4P/joSA/5eOitGxq6hFurOxAMvHxQDEwL0AysbDAMbCvwC+ubYAuLOwAMK9ugDBvLkAv7q3ALq0
sQDAu7kAxsK/AM3JxwDFwL0AysbDAM7KxwC+uLUAubOwAMfCvwDMycYAycTBALm0tADAwM8AtrbI
AMPC0gDNzdoA19fhAOHh6ADCwtIAYmKJAJKTwwDT1P8Ar7H1AKKj8gCLje8ClJbwXUFF5docIN//
HyPg/x8j4P8fI+D/KCvk/0JF7v9rbvX/hojl/29wrP8sLV//AAAx/wAAMP9dXYGqxMTQCsLCzwDT
1N4A1NPbANbS0QDDvrsAzMnGAMvIxQC0sKuBq6Wg/6ynov+tp6L/raei/66oo/+uqKP/sKik/7Cp
pf+wqqX/saqm/7Grpv+xrKf/sqyn/7OtqdTHw8ECzcnHAH5zcaKVi4j+zcnIFP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDCvcAAwr3AAMK9wADC
vcAAwr3AAMK9wADCvcAAwr3AAMO+wADCvb8AwLu7AMK8ugDBu7oAwbu6AMG7ugDBu7oAwbu6AMG7
ugDBu7oAwbu6AMG7ugDBu7oAxsC/AW5gXrpJNzb/Tz08/089PP9OPTv/Tjw7/048O/9OPDv/Tjw7
/048O/9KODf/X09O/8/Ixv99cm7/al9b/25jX/9uY1//b2Rg/29lYf9wZWH/cGVh/3BlYf9xZmL/
cWZi/3JnY/9yZ2P/c2hk/3RpZf90aWX/dGll/3VqZv91amb/dmtn/3ZrZ/94bWj/YVNQ/049PP9R
Pz7/UD49/1A+Pf9PPz3/UD89/1A+Pf9LODf/Z1dW/9HJyP+DeXX/e3Bs/31ybv9+c27/fnNv/350
b/9/dHD/gHVx/4B1cf+AdXH/gXZy/4F2cv+BdnL/gndz/4N4dP+DeHT/hHl1/4R5df+EeXX/hXp2
/4Z7d/+Ge3f/hnt3/4d8eP+HfHj/iX56/21iXv9bT0v/XVFN/1xQTP9cUEz/W09L/1tPS/9bT0v/
Wk5K/1JFQf+glpT/2dLR/5GHg/+MgX3/j4SA/4+FgP+PhYH/joWB/46Fgf+PhID/j4SA/6Oal5i3
sa4Svrm2ALixrwDJxcMAxMC9AMrGwwDGwr8Avrm2ALizsADCvboAwby5AL+6twC6tLEAwLu5AMbC
vwDNyccAxcC9AMrGwwDOyscAvri1ALmzsADHwr8AzMnGAMnEwQC5tLQAwMDPALa2yADDwtIAzc3a
ANfX4QDh4egAwsLSAGJiiQCSk8MA09T/AK6w9QCdn/EAiInuAL2/9wCTlfASY2bpjiww4f8hJeD/
Jirh/yUp4f8iJuD/HiLg/ycr5f9MT/H/d3rr/2tsrf8jI1P/AAAo/0lJcbfHx9IN1tbfANLS3QDT
0toA2tjWAN7c2gDf3dsA2dbUBrCppcSspKD/raah/6ymof+tp6L/raei/62nov+uqKP/rqij/7Cp
pP+wqaX/saql/7Cqpf+vqaT2ycXDK8fBwACOhIJ+fnJv+dbRzw////8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8AvLvUALy71AC8u9QAvLvUALy71AC8
u9QAvLvUALy71AC9vNUAs7TQALCtvwDPyscAy8bGAMzGxgDMxsYAzMbGAMzGxgDMxsYAzMbGAMzG
xgDMxsYA0czMAK6mpSxNOzr2Tjw7/089PP9PPTz/Tz08/089PP9OPDv/Tjw7/048O/9OPDv/RjQz
/56Tkv+0rKr/ZVpV/2thXf9sYV3/bWJe/21iXv9uY1//b2Rg/29kYP9wZWH/cGVh/3BlYf9wZWH/
cWZi/3FmYv9yZ2P/c2hk/3NoZP9zaWX/dGll/3RpZf92a2f/cmdj/1VEQv9QPz3/UEA+/1BAPv9R
Pz3/UD49/08/Pf9PPz3/SDY0/6GVlP+3r6z/dWpm/3twbP98cW3/fHFt/3xxbf99cm7/fXNu/35z
b/9/dHD/f3Rw/4B1cf+AdXH/gHVx/4F2cv+BdnL/gndz/4J3c/+DeHT/g3h0/4R5df+EeXX/hXp2
/4V6dv+Ge3f/iH15/3hsaf9dUU3/XlFO/11RTf9dUU3/XFBM/1xQTP9cUEz/W09M/1NHQ/+CdnT/
3tfW/52Tj/+IfXj/jYF9/42Cfv+Og3//joN//4+EgP+Mgn3/kYeD4a+pplrKxcMAuLKvALy3tAC4
sa8AycXDAMTAvQDKxsMAxsK/AL65tgC4s7AAwr26AMG8uQC/urcAurSxAMC7uQDGwr8AzcnHAMXA
vQDKxsMAzsrHAL64tQC5s7AAx8K/AMzJxgDJxMEAubS0AMDAzwC2tsgAw8LSAM3N2gDX1+EA4eHo
AMLC0gBiYokAkpPDANPU/wCusPUAnZ/xAIiJ7gC3uPYAj5HvAJaY8ACAgu1KOj7j3R4i3/8kKOD/
JSng/yYq4f8lKeH/ICTg/yEl4/9FSfD/c3bi/1dXj/8GBTX/TExxtNnZ4QbW1t8A0tLeANPS2QDI
w8EAyMPCAMrEwwCwqaZTp56a/66kof+tpaH/raWh/6ymof+spqH/rKei/62nov+tp6L/rqij/6+o
o/+wqaX/rqei/8O+unLQzMoAkomHR2xfXPvZ1NNB////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AL+/2QC/v9kAv7/ZAL+/2QC/v9kAv7/ZAL+/2QC/
v9kAwMDaALi41QCqqcYAx8LBAMfBwQDGwcEAxsHBAMbBwQDGwcEAxsHBAMbBwQDGwcEAxsHBAM7J
yQCFenmISDY1/1A+Pf9PPTz/Tz08/089PP9PPTz/Tz08/089PP9PPTz/Szk4/1hIRv/OxcT/f3Rv
/2ZbVf9qX1r/a2Bc/2tgXP9sYV3/bGFd/21iXv9uY1//bmNf/29kYP9vZGD/cGVh/3BlYf9wZWH/
cGVh/3FmYv9xZmL/cmdj/3NoZP9zaGT/dWtm/2ZaVv9PPz3/UkA//1E/Pv9QQD7/T0A+/1E/Pv9R
Pz7/TTs6/1pKSP/KwsH/i4F9/3ZrZ/96b2v/e3Bs/3twbP97cGz/e3Bs/3xxbf99cm3/fXJu/31z
bv9+c2//f3Rv/390cP+AdXH/gHVx/4B1cf+AdXH/gXZy/4J3c/+Cd3P/g3h0/4R5df+EeXX/hXp2
/4F2cf9jV1P/XlFO/19STv9eUk7/XVFN/11RTf9dUU3/XVFN/1hLR/9oXFj/1s7N/7CnpP+Fenb/
i4B8/4uAfP+LgHz/jIF9/4yBff+Jfnr/mpCNvravrCfFwL4Ax8LAALexrgC8t7QAuLGvAMnFwwDE
wL0AysbDAMbCvwC+ubYAuLOwAMK9ugDBvLkAv7q3ALq0sQDAu7kAxsK/AM3JxwDFwL0AysbDAM7K
xwC+uLUAubOwAMfCvwDMycYAycTBALm0tADAwM8AtrbIAMPC0gDNzdoA19fhAOHh6ADCwtIAYmKJ
AJKTwwDT1P8ArrD1AJ2f8QCIie4At7j2AI6Q7wCPke8AjI7vAIqN7hpiZeizHiLf/yMn4P8lKeD/
JSng/yUp4P8mKuH/ISXg/yMn5f9WWfL/dXfF/yQlUv9PT3Ofvb3LANPT3QDQ0NoAxsPFAMS+vADE
v74Awr28B5qSjsyqop3/rKOf/62koP+tpKD/raSh/62lof+tpqH/rKah/6ynov+tp6L/raei/6ym
of+5s6+r0M3LAKKamC9mWVb/ysTCVf///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wC/v9gAv7/YAL+/2AC/v9gAv7/YAL+/2AC/v9gAv7/YAMDA2QC6
utUAnp3EAKehqgCxqqcAsKmoALCpqACwqagAsKmoALCpqACwqagAsKmoALGqqQCvp6cKXk5N10w8
Of9PPz3/UD49/1A+Pf9QPjz/Tz08/089PP9PPTz/Tz08/0c0M/+Rg4P/vLOy/2NYU/9pXlj/aV5Y
/2peWP9qX1n/al9b/2tgW/9rYFz/bGFd/2xhXf9tYl7/bmNf/25jX/9uY1//b2Rg/3BlYf9wZWH/
cGVh/3BlYf9xZmL/cWdj/3JnY/9bS0j/T0A+/1BCP/9RQT//UkA//1E/Pv9QQD7/UEA+/0g3Nf+K
fXz/w7u4/3JoYv93bWj/eG1p/3luav96b2v/em9r/3twbP97cGz/e3Bs/3twbP98cW3/fXJu/31y
bv9+c27/fnNv/350b/9/dHD/f3Rw/4B1cf+AdXH/gHVx/4F2cv+Cd3P/gndz/4R5df9sYFz/X1JO
/2BTUP9fU0//X1JP/15STv9eUk7/XVFN/1xQTP9ZTEn/vLSz/8a+vP+FenX/iX56/4p/e/+Kf3v/
i4B8/4p/e/+IfXn8oJiVkb24tQfBvLkAwbu5AMfCwAC3sa4AvLe0ALixrwDJxcMAxMC9AMrGwwDG
wr8Avrm2ALizsADCvboAwby5AL+6twC6tLEAwLu5AMbCvwDNyccAxcC9AMrGwwDOyscAvri1ALmz
sADHwr8AzMnGAMnEwQC5tLQAwMDPALa2yADDwtIAzc3aANfX4QDh4egAwsLSAGJiiQCSk8MA09T/
AK6w9QCdn/EAiInuALe49gCOkO8Aj5HvAIeJ7gCUle8Aq6zzA1pd6JQhJeD/JCjg/yUp4P8lKeD/
JSng/yUp4P8lKeD/HiLg/zM37P90d+P/Rkd0/3NzjHzZ2eIA0tLcANHR2gDW1NQA2NXTAN3b2gCw
qqhXkIiD/6ymof+pop7/q6Ke/6yjn/+to5//raSg/62koP+tpaH/rKah/6ymof+spqH/rqij3M3I
xgDQy8sNZllV8q+lpF7///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8Av7/YAL+/2AC/v9gAv7/YAL+/2AC/v9gAv7/YAL+/2ADAwNkAurrVAJiYwgCs
qb4A0s3JAM3IyADNyMgAzcjIAM3IyADNyMgAzcjIAM3IyADU0NAAoZiYSUs4N/1QPj3/Tz89/08/
Pf9PPz3/UD49/1A+Pf9PPjz/Tz08/007Ov9SQD//xbu7/4Z8ef9iVlP/Z1xY/2hdWf9oXVn/aV5Y
/2leWP9qXln/al5Z/2pfWv9rYFv/a2Bc/2xhXf9sYV3/bWJe/21iXv9uY1//b2Rg/29kYP9vZWH/
cGVh/3FmYv9qX1r/U0NA/1JAP/9SQD//UEE//1BCP/9RQT//UkA+/1A+Pf9OPjv/vLOy/5mPjP9x
ZmH/dmtn/3dsZ/93bGj/eG1p/3htaf95bmr/eW5q/3pva/97cGz/e3Bs/3twbP98cW3/fHFt/3xx
bf99cm7/fXJu/35zb/9/dHD/f3Rw/4B1cf+AdXH/gHVx/4J3c/92a2f/YVNQ/2FUUf9hVFD/YFRQ
/2BTT/9fU0//X1JO/15STv9WSUX/mI6M/9nS0f+LgHz/hXp2/4h9ef+IfXn/iX56/4d8eP+Ngn7z
opqXXr23tQC/ubcAv7m2AMG7uQDHwsAAt7GuALy3tAC4sa8AycXDAMTAvQDKxsMAxsK/AL65tgC4
s7AAwr26AMG8uQC/urcAurSxAMC7uQDGwr8AzcnHAMXAvQDKxsMAzsrHAL64tQC5s7AAx8K/AMzJ
xgDJxMEAubS0AMDAzwC2tsgAw8LSAM3N2gDX1+EA4eHoAMLC0gBiYokAkpPDANPU/wCusPUAnZ/x
AIiJ7gC3uPYAjpDvAI+R7wCGiO4Ai47vALCx8gCrre4AZWfaqRoe3P8lKeD/JCjf/yUp4P8lKeD/
JSng/yUp4P8iJt//Iifl/2Ro7P9xcpz/lZSmUsnJ1QDFxdMAy8rSANXR0ADW09IA0s7NBYV7d8yh
mZT/qqOe/6iinf+pop3/qaKe/6uinv+so5//rKOf/62koP+tpKD/raWh/6uloPLDv7wrxcC/AHlv
bLORh4Rz////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AL+/2AC/v9gAv7/YAL+/2AC/v9gAv7/YAL+/2AC/v9gAwMDZALq61QCamsIAkpK5AM/LyQDL
x8UAy8fGAMvHxgDLx8YAy8fGAMvHxgDMx8YA0c3MAHdtaqRKOTb/UT8+/1E+Pv9QPj3/UD49/08/
Pf9PPz3/UD49/1A+Pf9JNjT/fm9v/8W8uv9jV1L/ZFlU/2VaVv9mW1f/Z1xY/2dcWP9oXVn/aF1Z
/2leWP9pXln/al5Y/2pfWv9qX1r/a2Bb/2tgXP9sYV3/bGFd/21iXv9tYl7/bmNf/25kYP9xZmL/
YVNQ/1BBPv9SQ0D/UkFA/1NAQP9RQT//UUI//1BCP/9MOzn/cWFg/8nBv/93bGj/dGll/3VqZv91
amb/dmtm/3ZrZ/93bGf/d2xo/3htaf94bWn/eW5q/3luav96b2v/e3Bs/3twbP97cGz/e3Bs/3xx
bf98cW3/fXJu/31ybv9+c2//f3Rw/4B1cf99cm3/ZllW/2FUUf9hVVH/YVVR/2FUUP9gVFD/YFNP
/2BTT/9ZTUn/dmpo/9vT0/+dk4//gXZy/4Z7d/+Ge3f/h3x4/4R5dP+Kf3vXsaunPLu1sgC4sq8A
vri2AL+5tgDBu7kAx8LAALexrgC8t7QAuLGvAMnFwwDEwL0AysbDAMbCvwC+ubYAuLOwAMK9ugDB
vLkAv7q3ALq0sQDAu7kAxsK/AM3JxwDFwL0AysbDAM7KxwC+uLUAubOwAMfCvwDMycYAycTBALm0
tADAwM8AtrbIAMPC0gDNzdoA19fhAOHh6ADCwtIAYmKJAJKTwwDT1P8ArrD1AJ2f8QCIie4At7j2
AI6Q7wCNj+8AjI7vAJ+h7wDX2PAA3N3rAMnK4RY2OcDiHCDe/yUp4P8kKN//JCjf/yQo3/8kKN//
JSng/yQo4P8eIuL/Vlnr/4+QuOqwsLsgwcHPAMHCzwDMycwA0MvJANbS0QClnpxefXNv/6yjn/+p
oJz/qaCc/6mhnf+ooZ3/qaKd/6minv+rop7/rKOf/62jn/+rop7/u7WxS87KyACdlZNHkYeEkv//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wC/v9gA
v7/YAL+/2AC/v9gAv7/YAL+/2AC/v9gAv7/YAMDA2QC6utUAmprBAI2OugDIxMcAw7y6AMO9vADD
vbwAw728AMO9vADDvbwAxr++ALqzshRZSUjnTT47/09APv9QQD7/UT8+/1E/Pv9QPj3/UD49/08/
Pf9PPjz/Szo4/7Wrqv+WjIj/XVFL/2RYUv9lWVP/ZVpU/2VaVf9mW1b/ZltX/2dcWP9nXFj/aF1Z
/2ldWf9pXlj/aV5Z/2peWP9qX1n/al9a/2tgXP9rYFz/bGFd/2xhXf9tYl7/bWJd/1hIRv9TQD//
U0JA/1FDQP9RQ0D/UkFA/1JAP/9SQD//STk3/6KYlv+spKH/bGFd/3RpZf90aWX/dGll/3VqZv91
amb/dWtm/3ZrZ/92a2f/d2xn/3dsaP94bWn/eG1p/3luav95bmr/em9r/3pva/97cGz/e3Bs/3xx
bf98cW3/fXJu/31ybv9+c2//bmJe/2JVUf9jVlL/Y1ZS/2JVUf9iVVH/YVRR/2FUUP9eUk7/YFRQ
/8a9vP+4sK3/fnNu/4R5df+Fenb/hXp2/4N4dP+Ui4fJsaqnI7iyrwC5s7AAuLKvAL64tgC/ubYA
wbu5AMfCwAC3sa4AvLe0ALixrwDJxcMAxMC9AMrGwwDGwr8Avrm2ALizsADCvboAwby5AL+6twC6
tLEAwLu5AMbCvwDNyccAxcC9AMrGwwDOyscAvri1ALmzsADHwr8AzMnGAMnEwQC5tLQAwMDPALa2
yADDwtIAzc3aANfX4QDh4egAwsLSAGJiiQCSk8MA09T/AK6w9QCdn/EAiInuALe49gCMju8Aj5Hv
ALS18ADl5O4A3t7uAN7e7gDp6fIAoKDMUhQWs/8iJuL/JCjf/yQo3/8kKN//JCjf/yQo3/8kKN//
JCjg/xwg4P9RVOn/qqvMk8zM0QHNzdgAy8vUAMG7ugDBurkAvLa1DHFlYt2ZkIz/qqGd/6ifm/+p
n5z/qaCc/6mhnP+ooZ3/qKKd/6minf+qop7/qaCc/7qzr4jHwr8AuLKwCZSKiHf///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8Av7/YAL+/2AC/v9gA
v7/YAL+/2AC/v9gAv7/YAL+/2ADAwNkAurrVAJqawQCPj7wAw8HOAMG7uQDBu7oAwbu6AMG7ugDB
u7oAwbu6AMjCwQCbkZBUTDo5/1E/Pv9RPz7/UEA+/1BAPv9QQD7/UT8+/1E/Pv9QPj3/TDo4/2la
WP/IwL//aV5Z/2FVUP9jWFH/ZFhR/2RYUv9lWVL/ZVhT/2VZVP9lWlX/ZltW/2ZbV/9nXFj/Z1xY
/2hdWf9pXln/aV5Y/2peWP9qX1j/al9Z/2pfWv9rYFz/bGFd/2ZZVf9SREH/UkRB/1NDQf9UQkD/
UkJA/1FDQP9RQ0D/UUA+/1hHRf/FvLv/hXp3/25iXv9yZ2P/c2hk/3NoZP90aWX/dGll/3RpZf91
amb/dWpm/3VqZv92a2f/dmtn/3dsaP94bWj/d21p/3luav95bmr/em9r/3pva/96b2v/e3Bs/3tw
bP99cm7/dmpm/2RXVP9kV1P/ZFZT/2NWU/9jVlL/YlVR/2JVUf9hVVH/WUxJ/6GWlP/Sy8n/gndz
/4F1cf+DeHT/g3h0/4F1cf+OhYGoysXDFLu2swC1r6wAubOwALiyrwC+uLYAv7m2AMG7uQDHwsAA
t7GuALy3tAC4sa8AycXDAMTAvQDKxsMAxsK/AL65tgC4s7AAwr26AMG8uQC/urcAurSxAMC7uQDG
wr8AzcnHAMXAvQDKxsMAzsrHAL64tQC5s7AAx8K/AMzJxgDJxMEAubS0AMDAzwC2tsgAw8LSAM3N
2gDX1+EA4eHoAMLC0gBiYokAkpPDANPU/wCusPUAnZ/xAIiJ7gC2t/YAjI7vAK+w7ADc3OoA1tbq
ANbW6gDW1uoA19fqAODg7gBXV6mpCgy1/yUp5P8jJ97/JCjf/yQo3/8kKN//JCjf/yQo3/8kKN//
Gh7f/1ZZ6P3Jyds62NjcANXV3gDRz9AAz8vIANfU0gCXj4yAdGll/6ignP+mnpn/p56a/6eemv+o
n5v/qaCc/6mgnP+poJz/qKGd/6egm/+wq6eo1tLRAdbS0QCwqacq////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AL+/2AC/v9gAv7/YAL+/2AC/v9gA
v7/YAL+/2AC/v9gAwMDZALq61QCamsEAkJG8ALq60QDDvsAAycTDAMjEwgDIxMIAyMTCAMjEwwDN
yccAdGlmp0o7OP9RQT//UkA//1I/Pv9RPz7/UEA+/1BAPv9QQD7/UT8+/0g2Nf+ekpD/qaCd/1hN
SP9gVVL/YVZS/2JXUv9jV1H/Y1hR/2RYUf9kWFH/ZFhS/2RZU/9lWVT/ZlpW/2VbVv9mW1j/Z1xY
/2dcWf9oXVn/aF1Z/2leWf9pXlj/al5Z/2tgWv9eUEz/U0FA/1NDQf9RREH/UkRB/1NDQf9UQUD/
UkJA/0s8Of9+cXD/wLi2/21iXv9wZWH/cWZi/3FmYv9xZmL/cmdj/3NoZP9zaGT/c2hk/3RpZf91
amb/dWpm/3VqZv92a2f/dmtn/3dsZ/93bGj/d21o/3htaf94bWn/eW5q/3luav97cGv/em9r/2pd
Wv9lV1P/ZVhU/2RXVP9kV1P/Y1ZT/2NWUv9iVlL/XVBM/3ltav/a0tH/lYuI/3xxbP+BdnL/gXZy
/31ybv+bko+Yq6ShBcvIxQC5tLEAta+sALmzsAC4sq8Avri2AL+5tgDBu7kAx8LAALexrgC8t7QA
uLGvAMnFwwDEwL0AysbDAMbCvwC+ubYAuLOwAMK9ugDBvLkAv7q3ALq0sQDAu7kAxsK/AM3JxwDF
wL0AysbDAM7KxwC+uLUAubOwAMfCvwDMycYAycTBALm0tADAwM8AtrbIAMPC0gDNzdoA19fhAOHh
6ADCwtIAYmKJAJKTwwDT1P8ArrD1AJ2f8QCHiO4Atbf2AMHC7gDU1OcA0tLnANLS5wDS0ucA0tLn
ANLS5wDX1+oAxcXfIRsbj/EUF8X/JSnj/yMn3v8jJ97/Iyfe/yQo3/8kKN//JCjf/yQo3/8ZHd//
aGrlt9/f7AHc3e0A1tXjAMbBvwDJxMMAurOyJWRXVPaYjov/p56a/6WcmP+lnZn/pp2Z/6eemv+n
npr/qJ+b/6mgnP+on5v/raai38bCvwfFwL4AxsHABf///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wC/v9gAv7/YAL+/2AC/v9gAv7/YAL+/2AC/v9gA
v7/YAMDA2QC6utUAmprBAJGRvACzs9EAtbK/AM7JxgDLxsUAy8bFAMvGxQDNycgAwbu6EllJR+dP
Pzz/UEI//1BCP/9RQT//UkA//1JAPv9RPz7/UEA+/04+PP9VRkT/w7q5/3pvaP9cT0n/YFRO/19U
UP9gVVH/YFVS/2FWUv9iV1L/YldR/2NXUf9kWFH/ZFhR/2VYUv9kWVP/ZVlU/2ZaVf9mW1b/ZltX
/2dcWP9nXFn/aF1Z/2leWf9oXVj/VklG/1JFQf9UREL/VENB/1NDQf9RRUH/UkRB/1NCQP9NOzn/
rKGg/56Vkv9oXVn/b2Rg/3BlYf9wZWH/cGVh/3FmYv9xZmL/cWZi/3JnY/9yaGT/c2hk/3NpZf90
aWX/dWpm/3VqZv91amb/dWpm/3ZrZv92a2f/d2xn/3htaP94bWn/eW5q/3FlYf9lWFT/ZllV/2VY
Vf9lWFT/ZFhU/2RWU/9kV1P/YlVR/2BTUP/FvLv/tKyp/3htaf9/dHD/f3Rw/3pva/+jnJmLxMC+
AamjoADKxsQAubSxALWvrAC5s7AAuLKvAL64tgC/ubYAwbu5AMfCwAC3sa4AvLe0ALixrwDJxcMA
xMC9AMrGwwDGwr8Avrm2ALizsADCvboAwby5AL+6twC6tLEAwLu5AMbCvwDNyccAxcC9AMrGwwDO
yscAvri1ALmzsADHwr8AzMnGAMnEwQC5tLQAwMDPALa2yADDwtIAzc3aANfX4QDh4egAwsLSAGJi
iQCSk8MA09T/AK6w9QCcnvEAhIbwAMDA7wDNzeQAzc3lAMzM5QDMzOUAzMzlAMzM5QDMzOUAzc3l
ANfX6wBycrWAAACI/x8i1v8jKOD/Iyfe/yMn3v8jJ97/Iyfe/yMn3v8jJ97/Iiff/x0h3/+Fh+98
09T6AMnL+gDQzeAA1NHNANnV1QB7cW66d2to/6ifnP+km5f/pJuX/6ScmP+lnJj/pZ2Z/6admf+n
npr/p56a/6ifm+fNycYU2tbUAM3IxwD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8Av7/YAL+/2AC/v9gAv7/YAL+/2AC/v9gAv7/YAL+/2ADAwNkA
urrVAJqawQCRkbwAsrLRAJKQsgDQy8kAzsrJAM7KyQDOyskA1NHRAKOamVBNPDr/U0A//1JAP/9R
QT//UEI//1BCP/9RQT//UkA//1I/Pv9LODf/fnFw/7y0sf9cUEf/X1JK/2BTS/9gVEz/X1RN/19T
Tv9gVFD/YFRR/2FWUv9hVlL/YldR/2NYUf9kV1H/Y1hR/2RYUv9lWVL/ZVlT/2VZVP9lWlX/ZltW
/2ZbV/9oXVn/Y1dT/1VEQv9TREL/UkZC/1NGQv9UQ0L/VENB/1JEQf9PQz//W01K/8W9vP96cGz/
al9b/21iX/9uY1//b2Rg/29kYP9vZGD/cGVh/3BlYf9wZWH/cWZi/3FmYv9yZ2P/cmdj/3NoZP90
aWX/dGll/3RpZf91amb/dWpm/3VqZv92a2f/d2xo/3VqZf9oXFj/Z1lW/2ZZVv9nWVX/ZVlV/2VY
VP9lV1T/ZFdT/11PS/+Zjo3/0svK/390cP97cGz/fXFu/3pva/+po5+B19PTAMO+vQCoop8AysbE
ALm0sQC1r6wAubOwALiyrwC+uLYAv7m2AMG7uQDHwsAAt7GuALy3tAC4sa8AycXDAMTAvQDKxsMA
xsK/AL65tgC4s7AAwr26AMG8uQC/urcAurSxAMC7uQDGwr8AzcnHAMXAvQDKxsMAzsrHAL64tQC5
s7AAx8K/AMzJxgDJxMEAubS0AMDAzwC2tsgAw8LSAM3N2gDX1+EA4eHoAMLC0gBiYokAkpPDANPU
/wCusPUAnqDxAKKj5QC/v90AuLjaALi42wC4uNsAuLjbALi42wC4uNsAuLjbALi42wC7u9wAurrc
EiQkjeUHCJ3/Iyfg/yIm3v8iJt3/Iyfe/yMn3v8jJ97/Iyfe/yMn3v8gJN7/Jyvf/J+h8T/c3fwA
2NjyANbS0ADb2NcAqKGfY11QTf+elZL/o5uX/6Oalv+jm5f/pJuX/6Sbl/+lnJj/pZyY/6Wdmf+l
nJj+xsG9Q9HOywDKxsQA////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AL+/2AC/v9gAv7/YAL+/2AC/v9gAv7/YAL+/2AC/v9gAwMDZALq61QCamsEA
kZG8ALS00QB9fbAAxMDDAMK9uwDCvbwAw728AMnExAB/dHKdSjw4/1JDQP9SQUD/U0BA/1NAP/9R
QT//UUE//1BCP/9RQT//Sjk4/6+lpP+SiIT/VUlB/15RSv9fUkr/YFJK/2BTS/9gU0v/YFRM/2BU
Tf9gVE7/X1RQ/2BVUf9hVlL/YVZS/2JXUv9jV1L/ZFhR/2RYUf9kWFH/ZFhS/2VZU/9lWVT/ZltW
/1xRTP9TRkL/VUVC/1VEQv9TREL/UkZC/1NFQv9VQ0L/Tjw6/4Bzcf+7s7H/Z1xY/2tgXP9sYV3/
bGFd/21iXv9tYl7/bmNf/29kYP9vZGD/b2Rg/3BlYf9wZWH/cGVh/3FmYv9xZmL/cmdj/3JnY/9z
aGT/c2hk/3RpZf90aWX/dWpm/3ZrZ/9tYV3/Z1pW/2haV/9nWlb/ZlpW/2ZZVf9mWFX/ZVhV/2FU
UP9xZWH/18/P/5aNif92a2f/e29r/3luafyjnJl14+HgANTR0ADCvbsAqKKfAMrGxAC5tLEAta+s
ALmzsAC4sq8Avri2AL+5tgDBu7kAx8LAALexrgC8t7QAuLGvAMnFwwDEwL0AysbDAMbCvwC+ubYA
uLOwAMK9ugDBvLkAv7q3ALq0sQDAu7kAxsK/AM3JxwDFwL0AysbDAM7KxwC+uLUAubOwAMfCvwDM
ycYAycTBALm0tADAwM8AtrbIAMPC0gDNzdoA19fhAOHh6ADCwtIAYmKJAJKTwwDT1P8Aqqz3AMTF
7gDIyOAAx8fiAMfH4gDHx+IAx8fiAMfH4gDHx+IAx8fiAMfH4gDHx+IAx8fiANPT6ACEhMBzAAB5
/xUYvf8kKOL/Iibd/yIm3f8iJt3/Iibd/yMn3v8jJ97/Iyfe/xoe3f9JTeXW09T5DdXW+wDPzeAA
1dDOAMjDwx1gVFDxhHp3/6aemv+hmZX/opmV/6Kalv+jmpb/o5uX/6Sbl/+km5f/pJuX/62mok6v
qKQAsKmlAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wC/v9gAv7/YAL+/2AC/v9gAv7/YAL+/2AC/v9gAv7/YAMDA2QC6utUAm5vCAJGRvAC0tNEA
f3+zAL+9yQDFv70AxcC/AMbCwQDAurkHYFBO1lA+Pf9RQ0D/UENA/1FDQP9SQkD/U0FA/1NAP/9S
QD//Tj48/15QTf/FvLv/aV1W/1lMRf9cT0n/W1BJ/1xRSv9eUUn/X1JK/2BTSv9gU0v/YFNL/2BU
TP9gVE3/YFRP/19UUP9gVVH/YFVS/2FWUv9iV1L/Y1dR/2NYUf9kWFH/ZFhR/2RYUv9ZSkb/U0VC
/1NHQ/9URkP/VUVD/1VEQv9TRUL/UkZC/00+O/+pnp3/mpGN/2RYUf9qX1r/al9a/2tgW/9rYFz/
bGFd/2xhXf9tYl7/bWJe/25jX/9uY1//b2Rg/29kYP9wZWH/cGVh/3BlYf9xZmL/cWZi/3JnY/9y
Z2P/c2hk/3RpZf9yZmL/aVxY/2hbWP9oW1f/Z1tX/2daVv9nWlb/ZllW/2VYVf9gUk//t62r/721
s/90aWT/eW5q/3htaPuMg39suLKwAOPh3wDT0M4Awr27AKiinwDKxsQAubSxALWvrAC5s7AAuLKv
AL64tgC/ubYAwbu5AMfCwAC3sa4AvLe0ALixrwDJxcMAxMC9AMrGwwDGwr8Avrm2ALizsADCvboA
wby5AL+6twC6tLEAwLu5AMbCvwDNyccAxcC9AMrGwwDOyscAvri1ALmzsADHwr8AzMnGAMnEwQC5
tLQAwMDPALa2yADDwtIAzc3aANfX4QDh4egAwsLSAGJiiQCRksMA0NL9AK6v5AC8vNsAvLzbALy8
3AC8vNwAvLzcALy83AC8vNwAvLzcALy83AC8vNwAvLzcALy83AC/v90At7fZEh0di+kBAof/HiLU
/yIm3/8iJt3/Iibd/yIm3f8iJt3/Iibd/yIm3f8iJt3/GR3c/3h664bU1foA0tLxANTQzQDX09MA
e3Ftu2ZaV/+lnZn/oJeT/6CXk/+hmJT/opmV/6KZlf+impb/o5qW/6GYlP+0rKlYy8fEAMnEwQD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8Avb3X
AL291wC9vdcAvb3XAL291wC9vdcAvb3XAL291wC+vtgAu7vWAZ2dwwWUlL4AtLTRAICAswC5uNAA
zMjIAM3JyADTzs4AsquqN1BAPvxTQUD/VEFA/1NBQP9RQ0D/UERA/1FDQP9SQkD/U0FA/0w4OP+J
fHv/sKik/1VIQP9bTkb/XE9H/1xPR/9bT0j/XE9I/1xQSf9dUEr/XlFJ/19SSv9gUkr/YFNK/2BT
S/9gVEz/YFRN/2BUTv9fVFD/YFVR/2BVUv9hVlL/YldR/2NYUv9hVU//VUhE/1ZGRP9VRUP/VEZD
/1NHQ/9URkP/VURD/1NCQP9ZS0n/wbi3/3huaf9lWlb/aV5Y/2leWf9pXln/al5Z/2pfWv9rYFz/
a2Bc/2xhXf9sYV3/bWJe/21iXv9uY1//b2Rg/29kYP9vZGD/cGVh/3BlYf9wZWH/cGVh/3FmYv9y
Z2P/bGBb/2lcWP9pXFj/aFxY/2hcWP9oW1f/Z1pX/2daVv9hU0//h3t4/9jQz/+Bd3L/dGll/3Vp
Zf2el5NzsauoAMG8ugDh390A09DOAMK9uwCoop8AysbEALm0sQC1r6wAubOwALiyrwC+uLYAv7m2
AMG7uQDHwsAAt7GuALy3tAC4sa8AycXDAMTAvQDKxsMAxsK/AL65tgC4s7AAwr26AMG8uQC/urcA
urSxAMC7uQDGwr8AzcnHAMXAvQDKxsMAzsrHAL64tQC5s7AAx8K/AMzJxgDJxMEAubS0AMDAzwC2
tsgAw8LSAM3N2gDX1+EA4eHoAMLC0gBhYYkAlZXBANXW8ADIyOEAxcXgAMXF4QDFxeEAxcXhAMXF
4QDFxeEAxcXhAMXF4QDFxeEAxcXhAMXF4QDFxeEAxcXhANLS5wB2drmKAAB1/w8Rqf8jJ+D/ISXc
/yEl3P8iJt3/Iibd/yIm3f8iJt3/Iibd/x4i3f8wNOD0wsP2JdPU+gDFwcwAyMPAAJaNi3ZVSEX/
m5GO/6GYlP+flpL/n5eT/6CXk/+hmJT/oZiU/6GYlP+elpL/tq+slNTQzgDRzcoA////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AM3N4ADNzeAAzc3g
AM3N4ADNzeAAzc3gAM3N4ADNzeAA0tLkAK+vzyUuLn+8hYW0L7291gCBgrMArq7OALKttgDAu7gA
xcG/AIyCgHRLPjr/UUVB/1NDQf9UQkH/VEJA/1NBQP9RQkD/UENA/1BDQP9NPTv/tKqp/4V6df9T
RT3/Wk1F/1pNRf9bTkb/XE5G/1xPR/9cT0f/W09I/1tPSf9cUEn/XVFK/15RSv9fUkr/YFJK/2BT
S/9gU0v/YFRM/2BTTf9fVE7/X1RQ/2BVUf9hVlL/XVBM/1RHQ/9USET/VUdE/1ZGQ/9VRUP/VEZD
/1NHQ/9PQD3/d2hm/721s/9kWVX/ZltX/2dcWP9oXVn/aF1Z/2leWP9pXlj/al5Y/2pfWf9qX1r/
al9b/2tgXP9sYV3/bGFd/21iXv9tYl7/bmNf/29kYP9vZGD/b2Rg/3BlYf9wZWH/bmNf/2pdWv9q
XVn/al1Z/2lcWf9pXFj/aFtY/2haV/9mWVX/Z1pW/8nAv/+mnZr/b2Rf/3NoYv+ZkY5119XTAOTi
4ADh394A39zaANPQzgDCvbsAqKKfAMrGxAC5tLEAta+sALmzsAC4sq8Avri2AL+5tgDBu7kAx8LA
ALexrgC8t7QAuLGvAMnFwwDEwL0AysbDAMbCvwC+ubYAuLOwAMK9ugDBvLkAv7q3ALq0sQDAu7kA
xsK/AM3JxwDFwL0AysbDAM7KxwC+uLUAubOwAMfCvwDMycYAycTBALm0swDAwM4AtbXHAMPC0QDN
zdoA19fhAOLi6ADAwM8AbGyRALu71gDY2OoA1dXoANXV6ADV1egA1dXoANXV6ADV1egA1dXoANXV
6ADV1egA1dXoANXV6ADV1egA1dXoANXV6ADa2uoAvr7cJw4OhfgCAoL/ICPN/yEl4P8hJdz/ISXc
/yEl3P8hJdz/Iibd/yIm3f8iJt3/GR3c/2Jl55zAwfkAw8HeAMrGwQC1r643V0pG/IZ7eP+mnZn/
nZSQ/56Vkf+flpL/n5aS/6CXk/+gl5P/n5aS/6ujn6O4sq8At7CtAP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wDY1+cA2NfnANjX5wDY1+cA2Nfn
ANjX5wDY1+cA2NfnAOXk7gBzc6t8AABb/xcXcuh9fbBOjY66AKurzQCcm7kAwLq2AL+5uAB0ZmWz
Tz08/1NDQf9RRUH/UUVB/1JEQf9TQ0H/VEFB/1NBQP9PPjz/YVRS/8G6uP9fU0v/VUhA/1hLQ/9Y
S0P/WUxE/1pNRf9aTUX/W05G/1tORv9cT0b/XE9H/1xPSP9bT0n/XFBJ/11RSv9dUUn/X1JK/2BT
Sv9gU0r/YFNL/2BUTP9gU03/YFRO/1pMSP9WRkT/VkdE/1RIRP9USET/VUdE/1ZGQ/9VRUP/TD87
/5qPjf+imZX/XlNN/2VaVf9lWlb/ZltX/2ZbWP9nXFj/aF1Z/2leWf9pXlj/aV5Y/2peWP9qX1n/
al9a/2pfW/9rYFz/bGFd/2xhXf9tYl7/bWJe/25jX/9vZGD/b2Rf/2xgXP9rXlr/a15a/2tdWv9q
XVn/aV1Z/2lcWP9pXFj/YFRQ/5uQjv/NxcT/dGll/25iXv+jm5iI4N/dAODe3ADf3dsA393cAN/c
2gDT0M4Awr27AKiinwDKxsQAubSxALWvrAC5s7AAuLKvAL64tgC/ubYAwbu5AMfCwAC3sa4AvLe0
ALixrwDJxcMAxMC9AMrGwwDGwr8Avrm2ALizsADCvboAwby5AL+6twC6tLEAwLu5AMbCvwDNyccA
xcC9AMrGwwDOyscAvri1ALmzsADHwr8AzMnGAMnEwAC8t7gAxMTUALu7zgDGxdYAzs7cANbW4gDe
3ucAxsbYAJeXvQCzs9cAsLDVALCw1QCwsNUAsLDVALCw1QCwsNUAsLDVALCw1QCwsNUAsLDVALCw
1QCwsNUAsLDVALCw1QCwsNUAsLDVALu72wBKSqO3AAB2/xcYo/8kKOH/ICPd/yEk3f8hJN3/ISXc
/yEl3P8hJdz/ISXc/x4i3P8uMt/1x8f3Jdzc+QDHw8YAxL+9DGpfW+BqX1v/q6Kf/5uSjv+dlJD/
nZSQ/56UkP+elZH/npWR/56Vkf+mnpqiuLKvALiyrwD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8AysrfAMrK3wDKyt8AysrfAMrK3wDKyt8Aysrf
AMzM4ADJyd4GIyN71wAAY/8AAGP/BARn+FtbnG+vrs4AnJzCAMS/vwC0rasSXVBN41JCQP9VQ0H/
VEJB/1NDQf9SREH/UUVB/1JEQf9TQ0H/TTo5/4l8e/+so6D/UEI6/1ZJQf9XSkL/V0pC/1hLQ/9Y
S0P/WEtD/1lMRP9aTUX/Wk1F/1tORv9cT0b/XE9H/1xPR/9cT0j/W1BI/1xQSf9cUUr/XVFK/15S
Sv9fUkr/YFNK/2BTS/9XSkb/VUlF/1ZIRf9XR0X/VkdE/1RIRP9USET/VEZD/1NEQv+2rav/gXdx
/2BUTf9kWFL/ZVlT/2VZVP9lWlX/ZltW/2ZbV/9nXFj/Z1xZ/2hdWf9oXVn/aV5Z/2leWP9qXlj/
al5Z/2pfWv9rX1v/a2Bc/2thXf9sYV3/bWJe/21hXf9tX1v/bF9b/2xfW/9rXVr/al1a/2pdWf9q
XVn/Z1pW/3BjYP/Sysn/k4mF/2ldWf+YkIyV29jXAN/d2wDf3dsA393bAN/d3ADf3NoA09DOAMK9
uwCoop8AysbEALm0sQC1r6wAubOwALiyrwC+uLYAv7m2AMG7uQDHwsAAt7GuALy3tAC4sa8AycXD
AMTAvQDKxsMAxsK/AL65tgC4s7AAwr26AMG8uQC/urcAurSxAMC7uQDGwr8AzcnHAMXAvQDKxsMA
zsrHAL64tQC5s7AAx8K/AMzJxgDJxMAAvLvQAL293wC9vd0Avb3dAL293QC9vd0Avb3cAL6+3gC/
v98Au7vcALu73AC7u9wAu7vcALu73AC7u9wAu7vcALu73AC7u9wAu7vcALu73AC7u9wAu7vcALu7
3AC7u9wAu7vcALu73ADExOAAjY3EXQEBfP8GBoP/KSzN/x8k3v8gJNv/ISTc/yEk3f8hJN3/ISTd
/yEl3P8hJdz/GBzb/3V36o3DxPoAvbrPAMO+uAB8cm+yV0tH/6SbmP+dlJH/m5KO/5yTj/+dlJD/
nZSQ/52UkP+bko7/p6Ccw9/c2wTh3t0A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AMPD2wDDw9sAw8PbAMPD2wDDw9sAw8PbAMPD2wDMzOAAjo67
RQAAZP8AAGf/AQBn/wAAZf8AAGT/RkWOlqGhyAnMytMApp6bPU5APf9RRkL/UkZC/1REQv9VQ0L/
VUJB/1NDQf9SREH/UEVB/00/PP+vpaT/g3hy/05BOf9VSED/VUlB/1ZJQf9WSUH/V0pC/1dKQv9Y
S0P/WEtD/1hMRP9ZTET/Wk1F/1pNRf9bTkb/W05G/1xPR/9cT0f/XE9I/1tQSf9cUEn/XVBJ/15R
Sv9cUEn/VkhG/1ZJRf9VSUX/VUlF/1ZIRf9WR0T/VUdE/1FFQf9lWlb/vrW0/2dbVv9hVlD/ZFhR
/2RYUf9kWFH/ZFhS/2VZU/9lWVT/ZVpW/2ZbVv9mW1f/Z1xY/2dcWP9oXVn/aF1Z/2leWf9pXlj/
al5Y/2pfWf9qX1r/a19b/2tgW/9tYFz/bmBc/21fXP9sX1v/a15a/2teWv9rXVr/al1a/2NWUf+q
oJ7/wLi2/2hcV/+KgXynycXDA9nW1ADd29kA393bAN/d2wDf3dwA39zaANPQzgDBvLoAp6GeAMrG
xAC5tLEAta+sALmzsAC4sq8Avri2AL+5tgDBu7kAx8LAALexrgC8t7QAuLGvAMnFwwDEwL0AysbD
AMbCvwC+ubYAuLOwAMK9ugDBvLkAv7q3ALq0sQDAu7kAxsK/AM3JxwDFwL0AysbDAM7KxwC+uLUA
ubOwAMfCvwDMyMUAysXGAMPD3wDBwd8AwsLfAMLB3wDBwd8AwcHfAMHB3wDBwd8AwsLfAMLC3wDC
wt8AwsLfAMLC3wDCwt8AwsLfAMLC3wDCwt8AwsLfAMLC3wDCwt8AwsLfAMLC3wDCwt8AwsLfAMLC
3wDCwt8AxMTgAL6+3RcdHY3tAAB3/yMlqv8lKOH/HyPc/yAk2/8gJNv/ICTb/yEk3P8hJN3/ISTd
/xsf3P85PODowcP5EsHA4AC/urUAkomGek9CPv+WjIr/o5qW/5mQjP+ako7/m5KO/5yTj/+ck4//
m5KO/6WdmefU0M4L1tLQAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wDLy+AAy8vgAMvL4ADLy+AAy8vgAMvL4ADLy+AA1dXmAE5OlaUAAGH/AABo
/wAAaP8BAGj/AABm/wAAYP82Noa+razLF5GHgm1PPTv/VERC/1NFQv9SRkL/UkZC/1NFQv9VQ0L/
VUJB/1FAPv9eUE7/v7a1/15SS/9QQzv/VEc//1RHP/9VSED/VUhA/1VJQf9WSUH/VklB/1dKQv9X
SkL/V0tD/1hLQ/9ZTET/WUxE/1pNRf9bTkb/W05G/1xPRv9bT0b/XE9H/1tPSP9bUEn/WU1I/1ZK
Rv9XSUb/V0lF/1ZIRf9VSUX/VUlF/1ZIRf9QQD7/gnZz/7Copf9aT0r/YFZS/2FWUv9iV1L/Y1dR
/2RYUf9kWFH/ZFhR/2RYUv9lWVP/ZVpU/2VaVf9mW1b/ZltX/2dcWP9nXVn/aF1Z/2leWf9pXln/
aV5Y/2peWP9rX1r/bmFd/25gXf9tYFz/bWBc/2xfW/9sX1v/a15b/2daV/94bGj/1s7N/4B2cf99
dG+7tbCtC8rGxADY1dMA3dvZAN/d2wDf3dsA393cAN/c2gDU0c8AxMC+AK2opQDLx8UAubSxALWv
rAC5s7AAuLKvAL64tgC/ubYAwbu5AMfCwAC3sa4AvLe0ALixrwDJxcMAxMC9AMrGwwDGwr8Avrm2
ALizsADCvboAwby5AL+6twC6tLEAwLu5AMbCvwDNyccAxcC9AMrGwwDOyscAvri1ALmzsADHwr8A
zcnFAMjH2gDHyOQAx8jiAMfI4gDHyOIAx8jiAMfI4gDHyOIAx8jiAMfI4gDHyOIAx8jiAMfI4gDH
yOIAx8jiAMfI4gDHyOIAx8jiAMfI4gDHyOIAx8jiAMfI4gDHyOIAx8jiAMfI4gDHyOIAx8jiAMfI
4gDS0+gAVFSnrgAAdv8PD4j/MTPX/x4h3v8gI9z/ICPc/yAk3P8gJNv/ICTb/yAk2/8gI9z/HB/c
/4mL7mG7vO4AsautAJ6VkkxRRUH/gXd0/6qhnv+WjYn/mZCM/5mRjf+akY3/mpGN/5qRjf+hmZXl
yMTCDcrGxAD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8Avb3YAL292AC9vdgAvb3YAL292AC9vdgAwcHaAK+vzxgQEHHtAABm/wAAaP8AAGj/AABo
/wAAaP8AAGj/AABh/xwced1ORmLcVEY+/1VFQ/9WREL/VURC/1NFQv9SRkL/UkZC/1NGQv9OPTv/
gHFw/7CnpP9LPjb/UUQ8/1JFPf9SRT3/U0Y+/1RHP/9URz//VUhA/1VIQP9VSUH/VUlB/1ZJQf9X
SkL/V0pC/1hKQv9YS0P/WUxE/1lMRP9aTUX/Wk1F/1tORv9cT0f/XE9H/1lLR/9XSkb/VkpG/1ZK
Rv9XSUb/V0hF/1ZJRf9VSUX/TUE9/6CVlP+XjIj/WU1G/19UTv9gVE//YFVR/2BWUv9hVlL/YldS
/2JYUf9jWFH/ZFhR/2RYUf9lWVL/ZVlT/2VaVP9lWlX/ZltW/2ZbV/9nXFj/Z1xY/2hdWf9oXln/
bmFd/29hXv9uYV3/b2Bd/25gXP9tX1z/bV9b/2xeW/9lWFT/s6mn/7Gppv92bGfVzcrJGtza2QDa
2NcA29nYANvZ2ADb2dgA29nYANvZ2ADb2dgA29nYANrY1wDa2NcA1tPRALawrQC0rqsAubOwALiy
rwC+uLYAv7m2AMG7uQDHwsAAt7GuALy3tAC4sa8AycXDAMTAvQDKxsMAxsK/AL65tgC4s7AAwr26
AMG8uQC/urcAurSxAMC7uQDGwr8AzcnHAMXAvQDKxsMAzsrHAL64tQC5s7AAyMO/AMTBxgC0s9kA
sLDWALGx1gCxsdYAsbHWALGx1gCxsdYAsbHWALGx1gCxsdYAsbHWALGx1gCxsdYAsbHWALGx1gCx
sdYAsbHWALGx1gCxsdYAsbHWALGx1gCxsdYAsbHWALGx1gCxsdYAsbHWALGx1gCxsdYAubnbAIGB
vmQBAXv/AQF6/zEzuv8iJeD/HyPa/x8j2/8gI9v/ICPc/yAj3P8gJNz/ICTb/xYb2f9dYOW6yMr7
AL670QCro58kWExI+GxgXf+vp6T/lYyI/5eOiv+Yj4v/mZCM/5mQjP+ZkIz/npaS57+6txDAvLkA
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////ALCw
zwCwsM8AsLDPALCwzwCwsM8AsLDPALq61gBzc6tjAABi/wAAaP8AAGj/AABo/wAAaP8AAGj/AABo
/wAAaP8AAGX/AABk/zgwVP9XSkL/VEdD/1VGQ/9VREL/VUNC/1REQv9SRkL/Sj46/6KYlv+Ngn3/
STsz/1BDO/9QQzv/UUQ8/1FEPP9SRT3/UkU9/1NGPv9URz//VEc//1RIQP9VSED/VklB/1ZJQf9W
SUH/VklB/1dKQv9YS0P/WEtD/1lLQ/9ZTET/Wk1F/1pNRf9XS0f/V0pH/1hKRv9WSUb/VkpG/1ZK
Rv9XSUb/VkdF/1RGQ/+0q6n/em5o/1xPR/9hVEv/YFNM/2BTTf9fVE//X1RQ/2BVUf9gVlL/YVZS
/2FXUf9jV1H/Y1hR/2RYUf9kWFH/ZVlT/2VZU/9lWlT/ZVpV/2ZbV/9lWlb/aV1Z/3FiX/9wYl7/
b2Je/29hXv9uYV3/bWBd/21fXP9pW1j/fnFu/9LKyf9/dnHrsKqnLtza2QDd29oA3NrZANvZ2ADb
2dgA29nYANvZ2ADb2dgA29nYANvZ2ADc2tkA3dvaANjV0wC5s7AAt7GuALmzsAC4sq8Avri2AL+5
tgDBu7kAx8LAALexrgC8t7QAuLGvAMnFwwDEwL0AysbDAMbCvwC+ubYAuLOwAMK9ugDBvLkAv7q3
ALq0sQDAu7kAxsK/AM3JxwDFwL0AysbDAM7KxwC+uLUAubOvAMnEwgDAwNYAu7vcALu82wC7vNsA
u7zbALu82wC7vNsAu7zbALu82wC7vNsAu7zbALu82wC7vNsAu7zbALu82wC7vNsAu7zbALu82wC7
vNsAu7zbALu82wC7vNsAu7zbALu82wC7vNsAu7zbALu82wC7vNsAu7zbAL6/3QCxsdYoExSH+gAA
d/8jJJr/LjHg/x0f3P8fItz/HyLb/x8j2v8fI9r/HyPb/yAj3P8dINz/Ki3d95aZ9CGmosQApp2W
DWpeW+BaTUn/raWi/5iPi/+WjYn/lo2J/5eOiv+Xjor/l46K/5yUkOi6tLESu7WyAP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wC6u9UAurvVALq7
1QC6u9UAurvVALu71gDAwNgANTaItgAAZP8AAGn/AABp/wAAaP8AAGj/AABo/wAAaP8AAGj/AABn
/wECbv9JQWz/WEhA/1NHQ/9TR0P/U0dD/1VGQ/9WREP/VENB/1ZHRP+4r63/Z1tU/0o9Nf9PQjr/
UEI6/1BDO/9QQzv/UEM7/1FEPP9SRDz/UkU9/1JFPf9TRj7/U0Y+/1RHP/9USED/VEhA/1VJQf9W
SUH/VklB/1dJQf9XSkL/V0pC/1hLQ/9YS0T/V0tH/1dLR/9XS0f/V0pH/1hJRv9WSkb/VkpG/1NH
Q/9lVlT/ubCu/2NXUf9cT0f/X1JK/19SSv9gU0v/YFNL/2BUTP9gU03/X1RP/19UT/9gVVH/YVZS
/2FWUv9iVlH/Y1dR/2RYUf9kWFH/ZFhR/2RYUv9lWVP/ZVpT+XJlYvJvYF3/cGJf/3BiXv9wYV7/
b2Fe/25hXf9uYF3/aFpW/7Opp/+xqKX7s62rTePh4ADf3dwA4N7dAODe3QDg3t0A4N7dAODe3QDg
3t0A4N7dAODe3QDg3t0A4N7dAODe3QDf3dwA3dvaANnV1AC1r6wAuLKvAL64tgC/ubYAwbu5AMfC
wAC3sa4AvLe0ALixrwDJxcMAxMC9AMrGwwDGwr8Avrm2ALizsADCvboAwby5AL+6twC6tLEAwLu5
AMbCvwDNyccAxcC9AMrGwwDOyscAvri1ALqzrgDAvcgAqKnTAKus0gCrrNIAq6zSAKus0gCrrNIA
q6zSAKus0gCrrNIAq6zSAKus0gCrrNIAq6zSAKus0gCrrNIAq6zSAKus0gCrrNIAq6zSAKus0gCr
rNIAq6zSAKus0gCrrNIAq6zSAKus0gCrrNIAq6zSAKus0gCrrNMAsbLVBDMzldIAAHf/DAyC/zw/
0v8cINz/HyLb/x8h3P8fId3/HyLc/x8i2/8fI9r/HyPb/xgb2v+VlvBp1dTuANTQzgB6cGzATkE9
/6SamP+elJH/lIqH/5WMiP+VjYn/lo2J/5WMiP+ako7ptrCtErexrgD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A1dXmANXV5gDV1eYA1dXmANXV
5gDb2+oAt7fUJQsLbvYAAGf/AABp/wAAaf8AAGn/AABo/wAAaP8AAGj/AABo/wAAZP8iI4H/bGFt
/1RDPv9WRUP/VUVD/1NHQ/9TR0P/U0dD/1BCP/9tX13/tq2r/05AOP9NPzf/TkE4/05BOf9OQjr/
T0I6/09COv9QQzv/UEM7/1FDPP9RRDz/UUQ8/1JFPf9SRT3/U0Y+/1NGPv9URz//VEhA/1VIQP9V
SUH/VklB/1ZJQf9WSUH/V0pE/1hLSP9YS0f/V0tH/1dLR/9XS0f/WEpH/1dJRv9RRED/enBt/6+m
o/9WSkL/W09I/1xQSf9dUUn/XlFK/19SSv9fUkr/YFNL/2BTS/9gVEz/YFRN/2BUTv9fVFD/YFVR
/2BWUv9hVlL/YldS/2JXUf9kWFH/X1JM/4d9eKevqKYtfHBtym1eW/9xYl//cGJf/3BiXv9wYV7/
a15a/35xbv/NxcP5o52YaNrY1wDj4uEA4d/eAOHf3gDh394A4d/eAOHf3gDh394A4d/eAOHf3gDh
394A4d/eAOHf3gDh394A4d/eAOPh4ADd2toAs62qALexrgC+uLYAv7m2AMG7uQDHwsAAt7GuALy3
tAC4sa8AycXDAMTAvQDKxsMAxsK/AL65tgC4s7AAwr26AMG8uQC/urcAurSxAMC7uQDGwr8AzcnH
AMXAvQDKxsMAzsrHAL64tAC9t7QApKTIAJaXyQCYmckAmJnJAJiZyQCYmckAmJnJAJiZyQCYmckA
mJnJAJiZyQCYmckAmJnJAJiZyQCYmckAmJnJAJiZyQCYmckAmJnJAJiZyQCYmckAmJnJAJiZyQCY
mckAmJnJAJiZyQCYmckAmJnJAJiZyQCYmckAmJnJAKKizQBYWKiYAAB3/wAAeP87PLn/JCfg/x0h
2f8eItn/HiLa/x4i2/8fIdz/HyLd/x8i2/8XGtn/WlzlsrW27AClnaEAeW5qoU0/PP+WjYr/pJyZ
/5GIhP+Uiof/lYqH/5WLiP+Vi4f/mZGN6bGrpxOyrKgA////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////ALa21AC2ttQAtrbUALa21AC2ttMAwcHaAHFx
q3EAAGX/AABr/wAAaf8AAGn/AABp/wAAaf8AAGn/AABp/wAAaP8AAGT/W1qg/2ldW/9SRUH/VUdE
/1ZGRP9WRUT/VUVD/1RGQ/9MPzv/i4F+/5mPi/9CNCz/Tj83/04+N/9OPzf/TUA4/01AOP9OQTn/
TkE5/09COv9PQjr/UEM7/1BDO/9RQzz/UUQ8/1FEPP9SRT3/UkU9/1NGPv9TRj7/VEc//1VIQP9V
SED/VUhA/1dKRf9YTEj/WExI/1hMSP9XS0f/V0tH/1dLR/9XS0f/UEI//5OIhv+akIz/VEc+/1xP
R/9cT0f/W09I/1tPSP9cUEn/XFBJ/15RSv9eUkr/X1JK/2BTSv9hU0v/YFRM/2BUTf9gVE7/X1RQ
/2BVUf9gVVL/YFVR/2FWUPy8trM/vLa0ALOtqhORh4OjbF1a/3BhXf9wY1//cGJe/2lbV/+soqC3
1c/NUr+6uADW09IA2tfWANrW1QDa1tUA2tbVANrW1QDa1tUA2tbVANrW1QDa1tUA2tbVANrW1QDa
1tUA2tbVANrW1QDa19YA2NTTAMbBvwDCvbsAvLa0AL+5tgDBu7kAx8LAALexrgC8t7QAuLGvAMnF
wwDEwL0AysbDAMbCvwC+ubYAuLOwAMK9ugDBvLkAv7q3ALq0sQDAu7kAxsK/AM3JxwDFwL0AysbD
AM7KxwDAurMAkI2yAHl6ugB/f7oAf3+6AH9/ugB/f7oAf3+6AH9/ugB/f7oAf3+6AH9/ugB/f7oA
f3+6AH9/ugB/f7oAf3+6AH9/ugB/f7oAf3+6AH9/ugB/f7oAf3+6AH9/ugB/f7oAf3+6AH9/ugB/
f7oAf3+6AH9/ugB/f7oAf3+6AH9/ugCEhb0AXF2oZAEBev8AAHb/LC2e/zM14P8bHdv/HiDb/x4h
2v8eItr/HiLZ/x4i2v8eItv/Ghzc/zk74Oilp/IRwLzHAJOLhopLPTj/iH17/6ujoP+OhYH/komF
/5OKhv+Uiob/lImG/5mPjOm0rqsSta+sAP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wCzs9IAs7PSALOz0gCzs9IAtLTSALW20wAuLoS7AABn/wAA
bP8AAGz/AABq/wAAav8AAGn/AABp/wAAaf8AAGb/DxB4/4qHtP9ZSUT/VEZD/1RIRP9USET/VEhE
/1VGRP9WRUT/TTw7/6uhn/+hmZT/QDUt/0U6Mf9LPzb/TD43/00+N/9OPzf/Tj84/05AOP9OQDn/
TkE5/05COv9PQjr/UEI7/1BDO/9QQzv/UUM8/1FEPP9SRDz/UkU9/1JFPf9TRj7/U0Y+/1RHP/9X
S0b/WExI/1hMSP9YTEj/WExI/1hMSP9XS0f/V0tH/1BEP/+onZz/gndx/1RGPv9aTUX/W05G/1tO
Rv9cT0f/XE9H/1tPR/9bT0j/XFBJ/1xQSf9eUUr/X1JK/2BSSv9gU0v/YFNL/2BUTP9gVE3/YFRO
/1tQS/94b2vEwr26ArWvrAC9uLYAuLKvAKCYlnRyZGD5bV9c/25gXf95bGju18/OHtrV1ADW09IA
1NDPANPPzgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A08/OANPPzgDT
z84A08/OANPPzgDX09IAzMjGALu1swC/ubYAwbu5AMfCwAC3sa4AvLe0ALixrwDJxcMAxMC9AMrG
wwDGwr8Avrm2ALizsADCvboAwby5AL+6twC6tLEAwLu5AMbCvwDNyccAxcC9AMrGwwDOysYAxMDC
AKyt0wCjo84ApKXOAKSlzgCkpc4ApKXOAKSlzgCkpc4ApKXOAKSlzgCkpc4ApKXOAKSlzgCkpc4A
pKXOAKSlzgCkpc4ApKXOAKSlzgCkpc4ApKXOAKSlzgCkpc4ApKXOAKSlzgCkpc4ApKXOAKSlzgCk
pc4ApKXOAKSlzgCkpc4Ap6jQAJmZyDYKCYH+AAB4/xkaif9BQ9j/GBva/x0g2f8dINr/HiDb/x4g
2/8eIdr/HiHa/xwh2f8gJNv/mJrwPsnH3wCimZRmTD46/3lua/+yqab/joSA/5KIhP+RiIT/komF
/5GIhP+XjovptbCtEraxrgD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8Aw8PcAMPD3ADDw9wAw8PcAMjI3wCwsNEkDAxy9AAAav8AAGz/AABs/wAA
bP8AAGz/AABr/wAAav8AAGn/AABh/0ZHov+Wkar/UEI7/1dHRf9WRkT/VUdE/1RIRP9USET/U0dD
/1VGQ//Fvbz/8O3s/62mo/9SRj//QDQr/0g9NP9JPjb/Sj42/0s+Nv9NPjf/Tj83/04/OP9NQDj/
TUA4/05BOf9OQTn/T0I6/1BDO/9QQzv/UUM7/1FDPP9RRDz/UUQ8/1JFPf9SRT7/WExH/1lNSf9Z
TUn/WExI/1hMSP9YTEj/WExI/1dLR/9WSkf/sqmo/2xgWf9URz//WUxE/1lMRP9ZTUX/Wk1F/1tO
Rv9bTkb/XE9H/1xPR/9bT0f/W09I/1xQSf9cUEn/XlFJ/15RSv9fUkr/YFNL/2BTS/9aTUb/qaOf
YtfU0gDQzMoAxsLAALGrqADOycgAqaGfR31wbeBmV1T/npSRi+Pd2wDW0dAA09DPANTQzwDU0M8A
1NDPANTQzwDU0M8A1NDPANTQzwDU0M8A1NDPANTQzwDU0M8A1NDPANTQzwDU0M8A1NDPANTQzwDU
0M8A1dHQAMvHxQC6tLIAvri1AMG7uQDHwsAAt7GuALy3tAC4sa8AycXDAMTAvQDKxsMAxsK/AL65
tgC4s7AAwr26AMG8uQC/urcAurSxAMC7uQDGwr8AzcnHAMXAvQDKxsMAzcnGAKmpywCkpdIAp6jR
AKen0QCnp9EAp6fRAKen0QCnp9EAp6fRAKen0QCnp9EAp6fRAKen0QCnp9EAp6fRAKen0QCnp9EA
p6fRAKen0QCnp9EAp6fRAKen0QCnp9EAp6fRAKen0QCnp9EAp6fRAKen0QCnp9EAp6fRAKen0QCn
p9EAp6fRAKmp0gCjo88UHR2K7QAAeP8FBXv/SUvK/x4g3/8dH9r/HR/a/x0g2f8dINn/HSDa/x4g
2/8eINv/FRnZ/4OF8XWxrMAAhHlzUVNFQv9tYF7/tKyq/46DgP+RhoP/koeD/5KIg/+Rh4P/lo6J
6Lm0sRG6trMA////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AKamywCmpssApqbLAKamygCwsNAAbW2qZAAAaP8AAGz/AABr/wAAbP8AAGz/AABs/wAA
bP8AAGz/AABr/wAAZf+Gh9H/fnaH/1BEPP9VSUX/VkhF/1dHRf9WRkT/VUdE/1FDQP9kWFX/29TU
/+zo6P/y7e7/z8nI/3BkX/9CMyv/Rjkx/0k9Nf9IPTX/ST42/0o+Nv9LPjf/TT43/04/N/9OPzj/
TUA4/01AOP9OQTn/T0I6/09COv9PQzv/UEM7/1FDO/9RQzz/UkU9/1lNSf9ZTUn/WU1J/1lNSf9Z
TUn/WExI/1hMSP9WSkb/ZFhU/7OqqP9cUEj/VUg//1dKQv9XSkL/WEtD/1hLQ/9YTET/WU1F/1pN
Rf9bTkb/W05G/1xPR/9cT0f/W09H/1xPSP9cUEn/XFBJ/15RSf9bTkb/bWJb5cTAvhHKxsQAyMTC
AMfEwgCxq6gAx8LBAMC6uQCzrKoiiX17qsC5tyvQysgAzcfGAM3HxgDNx8YAzcfGAM3HxgDNx8YA
zcfGAM3HxgDNx8YAzcfGAM3HxgDNx8YAzcfGAM3HxgDNx8YAzcfGAM3HxgDNx8YAzcfGAM3HxgDK
xMMAysXDAMO9ugDCvLoAx8LAALexrgC8t7QAuLGvAMnFwwDEwL0AysbDAMbCvwC+ubYAuLOwAMK9
ugDBvLkAv7q3ALq0sQDAu7kAxsK/AM3JxwDFwL0AzMjCAMfE0ACfoMwAnp/LAJ+fywCfn8sAn5/L
AJ+fywCfn8sAn5/LAJ+fywCfn8sAn5/LAJ+fywCfn8sAn5/LAJ+fywCfn8sAn5/LAJ+fywCfn8sA
n5/LAJ+fywCfn8sAn5/LAJ+fywCfn8sAn5/LAJ+fywCfn8sAn5/LAJ+fywCfn8sAn5/LAJ+fywCf
n8sAqanQAzo6mM0AAHj/AAB2/0VGtv8qLOH/Gx3b/x0f2/8dH9v/HR/a/x0f2v8dINn/HSDZ/xUZ
2f9YW+iqrqvQAKKZkkBUR0P/YVVS/7Wsqv+PhoL/joWB/4+Fgv+QhoL/kIWB/5iOiubBvLkQw768
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDF
xt0AxcbdAMXG3QDGxt0Azs7hAEBAkK8AAGb/AABs/wAAbP8AAGz/AABs/wAAa/8AAGv/AABs/wAA
aP8dHX//oqPr/1xQZP9VRz//VUlF/1VJRf9VSUX/VUlF/1ZHRf9QQD3/fXFu/+jj4v/o5OP/6OPj
/+/r6//n4+L/mI6L/0s8Nf9DMyv/Sjsz/0k8NP9JPTT/SD01/0g+Nv9JPjb/TD43/00+N/9OPjf/
Tj84/05AOP9NQDj/TkE5/05BOf9PQjr/T0I6/1NFPv9aTkr/Wk5K/1lNSf9ZTUn/WU1J/1lNSf9Z
TUn/VEhE/3RoZf+rop//UUU9/1VIQP9WSUH/VklB/1ZJQf9XSkL/V0pC/1hLQ/9YS0P/WUxE/1lM
RP9aTUX/W05G/1tORv9bTkb/XE9H/1tPR/9cT0j/VEhA/5GJhJHZ1tYA0c7NANLPzgDSz84AsKmn
AMfCwQC9trUAta6tAMnEwgDe2tkA2tbVANvX1gDb19YA29fWANvX1gDb19YA29fWANvX1gDb19YA
29fWANvX1gDb19YA29fWANvX1gDb19YA29fWANvX1gDb19YA29fWANvX1gDb19YA29fWANzY1wDd
2dgAysXDAMXAvgC3sa4AvLe0ALixrwDJxcMAxMC9AMrGwwDGwr8Avrm2ALizsADCvboAwby5AL+6
twC6tLEAwLu5AMbCvwDNyccAxcC9AMfDxADJyeAAzc7lAM7O5ADOzuQAzs7kAM7O5ADOzuQAzs7k
AM7O5ADOzuQAzs7kAM7O5ADOzuQAzs7kAM7O5ADOzuQAzs7kAM7O5ADOzuQAzs7kAM7O5ADOzuQA
zs7kAM7O5ADOzuQAzs7kAM7O5ADOzuQAzs7kAM7O5ADOzuQAzs7kAM7O5ADOzuQAzs7kANjZ6gBT
U6WzAAB3/wAAdv81NqP/ODvi/xga2v8cHtr/HB7a/x0f2/8dH9v/HR/b/x0f2/8WGNj/RUjh1cTE
7gG7tLIvVkdE/1pMSf+zq6n/k4iE/46Ef/+PhYH/joWB/4yDf/+Xjovoy8fFDc3JxwD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8AnJzFAJycxQCc
nMUAnp7GAJeXwhMTE3foAABq/wAAbP8AAGz/AABs/wAAbP8AAGz/AABs/wAAbP8AAGT/Wlut/4+P
5P9OQk7/V0lD/1dIRf9WSEX/VkhF/1VJRf9VSUX/TkE9/5qOjf/s5+f/5uLh/+bi4f/m4uH/6ubl
//Dt7P/Dvbv/ZllU/0AvKP9HNzD/Sjs0/0k7NP9JPDT/SDw0/0g9Nf9JPjb/Sj42/0w+N/9NPjf/
Tj84/00/OP9OQDj/TUA4/01AOP9TRkD/Wk5L/1pOSv9aTkr/Wk1J/1lNSf9ZTUn/WU1J/1NHQ/+G
fHn/nJKO/0w/N/9URz//VEhA/1VIQP9VSUH/VklB/1ZJQf9XSkL/V0pC/1hKQv9YS0P/WExE/1lM
RP9ZTUX/Wk1F/1tORv9bTkb/W05G/1xPR/22sa41y8fGAMjEwgDHw8EAzMjGALCppwDHwsEAvba1
ALStrADIw8EA3trZANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA
3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3trZAMrFwwDF
wL4At7GuALy3tAC4sa8AycXDAMTAvQDKxsMAxsK/AL65tgC4s7AAwr26AMG8uQC/urcAurSxAMC7
uQDGwr8AzcnHAMbBuwClpMMAg4O/AIeHvwCHh78Ah4e/AIeHvwCHh78Ah4e/AIeHvwCHh78Ah4e/
AIeHvwCHh78Ah4e/AIeHvwCHh78Ah4e/AIeHvwCHh78Ah4e/AIeHvwCHh78Ah4e/AIeHvwCHh78A
h4e/AIeHvwCHh78Ah4e/AIeHvwCHh78Ah4e/AIeHvwCHh78Ah4e/AIeHvwCOj8MAV1enkgAAeP8A
AHj/JSWS/0dJ3v8XGdr/HB7a/xwe2v8cHtr/HB7a/xwe2v8dH9v/GRva/zAy3vCvsPATxsLAHlZK
RftTRkP/sKim/5aLh/+Ngn7/joN//4+EgP+Ngn7/mpGN0dzZ2Abe29oA////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AK6u0ACurtAArq7QALa21QCB
grZJAABr/gAAbf8AAGz/AABs/wAAbP8AAGz/AABs/wAAbP8AAGv/AQFp/5CS4P9mZcf/UUVB/1ZK
Rf9WSkb/V0lG/1dIRv9XSEX/VkhF/09DPv+0rKv/6+fm/+Tg3//k4N//5eHg/+Xh4P/m4+H/7urq
/+Le3f+SiYT/STkz/0ExKf9KOTL/Sjoz/0o7M/9KOzP/STw0/0k8NP9IPTX/ST41/0o+Nv9MPjf/
TT43/04+N/9NPjf/VEdC/1tPS/9aTkr/Wk5K/1pOSv9aTkr/Wk1K/1lNSf9SRkL/l42M/4l/ef9L
PTX/UkU9/1NGPv9TRj7/VEc//1RIQP9VSED/VUlB/1VJQf9WSUH/VklB/1dKQv9YS0P/WEtD/1hL
Q/9ZTET/WU1F/1VHP/95b2jK2NbTAtbU0QDW09EA1tPRANjV0wC8t7QAx8LAAL22tQC0rawAx8LA
AN7a2QDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA
3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXAN7a2QDKxcMAxcC+ALexrgC8
t7QAuLGvAMnFwwDEwL0AysbDAMbCvwC+ubYAuLOwAMK9ugDBvLkAv7q3ALq0sQDAu7kAxsK/AM3K
xQDPzNIAxcbhAMfH4QDHx+EAx8fhAMfH4QDHx+EAx8fhAMfH4QDHx+EAx8fhAMfH4QDHx+EAx8fh
AMfH4QDHx+EAx8fhAMfH4QDHx+EAx8fhAMfH4QDHx+EAx8fhAMfH4QDHx+EAx8fhAMfH4QDHx+EA
x8fhAMfH4QDHx+EAx8fhAMfH4QDHx+EAx8fhAMfH4QDHx+EA0dLnAImJwWwAAHf/AAB6/xgYhv9S
U9f/Fhja/xsd2f8cHtr/HB7a/xwe2v8cHtr/HB7a/xoc2v8gItv/u733L4N4ehZTQz/4UUJA/62k
ov+Zj4v/in97/42Cfv+Ngn7/jIF9/5eNiam0raoAtK2qAP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wCrq80Aq6vNAKurzQC1tdMAWFiejwAAZ/8A
AW3/AAFt/wABbf8AAWz/AABs/wAAbP8AAGz/AABn/yUlg/+doP7/S0ek/1hJPP9XSkb/VkpG/1ZK
Rv9WSkb/V0lG/1ZHRP9ZS0j/zMTD/+fk4//j397/49/e/+Pf3v/k4N//5ODf/+Xh4P/p5eT/7uvq
/8G8uf9pXVb/Pi8n/0Q1Lf9JOTL/Sjkz/0o6M/9KOjP/Sjs0/0k8NP9IPDX/ST01/0k+Nv9KPjb/
Sz01/1ZJQ/9cUEz/W09L/1tPS/9aTkr/Wk5K/1pOSv9aTkr/VEhE/6OYl/94bGf/Sz01/1FEPP9R
RDz/UkU9/1JFPf9TRj7/U0Y+/1RHP/9URz//VUhA/1VJQf9WSUH/VklB/1ZJQf9XSkL/V0pC/1hL
Q/9SRTz/nZaRcdTS0ADOysgAzsrIAM7KyADPy8kAx8TBAMnEwgC9trUAtK2sAMfCwADe2tkA3NjX
ANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA
3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDe2tkAysXDAMXAvgC3sa4AvLe0ALixrwDJ
xcMAxMC9AMrGwwDGwr8Avrm2ALizsADCvboAwby5AL+6twC6tLEAwLu5AMfDvwDHxMQAs7PSALi4
2gC4uNgAuLjYALi42AC4uNgAuLjYALi42AC4uNgAuLjYALi42AC4uNgAuLjYALi42AC4uNgAuLjY
ALi42AC4uNgAuLjYALi42AC4uNgAuLjYALi42AC4uNgAuLjYALi42AC4uNgAuLjYALi42AC4uNgA
uLjYALi42AC4uNgAuLjYALi42AC4uNgAuLjYAMHB3QCJib9aAQF6/wAAev8KCn7/VljQ/xsd3P8b
Hdn/Gx3Z/xsd2f8bHdn/HB7a/xwe2v8bHdr/Gh3a/4KF7U5xZnMSVUdA9k5APP+poJ7/nJKO/4l+
ev+LgHz/jIF9/4p/e/+XjYqopJyYAKKZlgD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8ApaXKAKWlygClpcsAqqrNBCgohMkAAGn/AABt/wABbf8A
AW3/AAFt/wABbf8AAW3/AABs/wAAZf9gYK3/gYX//0U/hf9ZTD7/WEpH/1dJRv9XSUb/VkpG/1ZK
Rv9SRkL/aVxZ/9vU1P/j397/4d3c/+He3f/i3t3/4t7d/+Pf3v/j397/49/e/+Tg3//t6en/4t7d
/5mRjP9MQDj/PS8n/0U3MP9IOTH/STky/0o5Mv9KOjP/Sjoz/0o7NP9JPDT/SD00/0g9NP9XS0b/
XFBM/1tPS/9bT0v/W09L/1tPS/9aTkr/Wk5K/1dLR/+roZ//aFxW/0s+Nv9QQzv/UEM7/1FDPP9R
RDz/UUQ8/1JFPf9SRT3/U0Y+/1NHP/9URz//VEhA/1VIQP9VSED/VklB/1ZJQf9VSD//XFBI+Ly2
tCPHwsAAxcC+AMXAvgDFwL4AxL+9AMfCwADOyskAvLa0ALStrADHwsAA3trZANzY1wDc2NcA3NjX
ANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA
3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3trZAMrFwwDFwL4At7GuALy3tAC4sa8AycXDAMTAvQDK
xsMAxsK/AL65tgC4s7AAwr26AMG8uQC/urcAurSxAMC7uQDKxb8Anpy6AGBgqQBjY6kAY2OpAGNj
qQBjY6kAY2OpAGNjqQBjY6kAY2OpAGNjqQBjY6kAY2OpAGNjqQBjY6kAY2OpAGNjqQBjY6kAY2Op
AGNjqQBjY6kAY2OpAGNjqQBjY6kAY2OpAGNjqQBjY6kAY2OpAGNjqQBjY6kAY2OpAGNjqQBjY6kA
Y2OpAGJiqABhYagAYWGoAGFhqABiYqgAXFylSwYHf/8AAHr/AQF4/1dYxv8jJt7/GRvY/xoc2P8b
Hdn/Gx3Z/xsd2f8bHdn/Gx3Z/xgb2f9gYudxcWZ4DVlIQvRNPzv/pZya/56Ukf+HfHj/in97/4uA
fP+IfXn/npaSpby2swC5s7AA////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AKChyACgocgApaXKAIyNvCUICHH3AABs/wAAbf8AAG3/AABt/wABbf8A
AW3/AAFt/wAAbP8CA2v/kJHZ/1hb+v9MQ2z/WExA/1dLR/9XS0f/WEpH/1hJR/9XSUb/UEM//3tw
bf/j3t3/39va/9/b2v/g3Nv/4d3c/+Hd3P/i3t3/4t7d/+Le3f/j397/49/e/+bi4v/t6un/y8XD
/3VrZP8/Mir/PzEp/0U4MP9GODH/SDgx/0k5Mv9JOTL/Sjoz/0o6M/9KOzT/WU1I/11RTf9cUEz/
W09L/1tPS/9bT0v/W09L/1pOSv9cUEz/raSi/1tOR/9LPjb/TkI5/09COv9QQjr/UEM7/1BDO/9R
Qzv/UUQ8/1FEPP9SRT3/UkU9/1NGPv9TRj7/VEc//1RIQP9VSED/T0I6/3lvarzMyMYAx8PBAMfD
wQDHw8EAx8PBAMfDwQDHwsAAzMfGALy2tQC0rawAx8LAAN7a2QDc2NcA3NjXANzY1wDc2NcA3NjX
ANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA
3NjXANzY1wDc2NcA3NjXAN7a2QDKxcMAxcC+ALexrgC8t7QAuLGvAMnFwwDEwL0AysbDAMbCvwC+
ubYAuLOwAMK9ugDBvLkAv7q3ALmzrwDAurYAy8nSAL6/2wDBwdwAwcHcAMHB3ADBwdwAwcHcAMHB
3ADBwdwAwcHcAMHB3ADBwdwAwcHcAMHB3ADBwdwAwcHcAMHB3ADBwdwAwcHcAMHB3ADBwdwAwcHc
AMHB3ADBwdwAwcHcAMHB3ADBwdwAwcHcAMHB3ADBwdwAwcHcAMHB3ADBwdwAwcHcAMPD3QC4uNcA
lZXEAJWVxACVlcQAmJjFAIqKvjYJCYD+AAB7/wAAdf9UVbv/LS/g/xga2P8aHNj/GhzY/xoc2P8a
HNj/Gx3Z/xsd2f8QE9j/f4HshYqAfA1TRUD0TD06/6SZmP+flZL/hXp2/4l+ev+Jfnr/hXp1/6mh
n3zZ1tQA1dHPAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wCcnMYAnJzGAKSkygBycq5YAABq/wAAbf8AAG3/AABt/wAAbf8AAW3/AAFt/wABbf8A
AGj/IyOC/5yf+P88P+j/VEhZ/1hLQ/9XS0f/V0tH/1dLR/9XS0f/WEpG/1FCP/+RhoT/5eHg/93Z
2P/e2tn/3trZ/9/b2v/f29r/4Nzb/+Dc2//h3dz/4t7d/+Le3f/j397/49/e/+nm5f/n4+P/rqaj
/1xOSP88LCT/QjQs/0Q4L/9FODD/Rjgx/0g5Mf9IODH/Szs0/1tOSv9cUE3/XFBM/1xPS/9bT0v/
W09L/1tPS/9aTUn/ZFhV/6uioP9SRDz/TD02/01AOP9OQDn/TkE5/05BOf9PQjr/UEM7/1BDO/9R
Qzz/UUM8/1FEPP9SRD3/UkU9/1JFPf9TRj7/U0c+/05COf+el5Nqy8jFAMTBvgDEwb4AxMG+AMTB
vgDEwb4AxMG+AMTAvQC7tLMAtK6sAMfCwADe2tkA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjX
ANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA
3NjXANzY1wDe2tkAysXDAMXAvgC3sa4AvLe0ALixrwDJxcMAxMC9AMrGwwDGwr8Avrm2ALizsADC
vboAwby5AL65tAC+ubgAx8XTAM3O5QDOzuMAz8/jAM/P4wDPz+MAz8/jAM/P4wDPz+MAz8/jAM/P
4wDPz+MAz8/jAM/P4wDPz+MAz8/jAM/P4wDPz+MAz8/jAM/P4wDPz+MAz8/jAM/P4wDPz+MAz8/j
AM/P4wDPz+MAz8/jAM/P4wDPz+MAz8/jAM/P4wDPz+MAz8/jAM/P4wDR0eQAxcXfALCw1AC7u9oA
urrZAL6+2wCsrNIlCwyA9wAAev8AAHX/Tk+x/zc54v8WGNb/GhzY/xoc2P8aHNj/GhzY/xoc2P8a
HNj/ERPX/2Rm6Jh+cngTVUVA9Es9Ov+gl5b/oJaT/4R4dP+HfHj/h3x4/4d8d/+VjIhYopuXAKGZ
lQD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
sbHSALGx0gC7u9cAUFCbkwAAav8AAG//AABu/wAAbf8AAG3/AABt/wAAbf8AAG3/AABl/1hZqP+E
h///NjfU/1dLTv9ZTEb/WEtI/1dLR/9XS0f/V0tH/1dLR/9RRED/ppyb/+Xg4P/c2Nf/3NjX/93Z
2P/d2dj/3trZ/97a2f/f29r/39va/+Dc2//g3Nv/4t7d/+Le3f/i3t3/5ODf/+vo5//a1tT/komE
/0s8Nf88LCT/RDQt/0Q3L/9ENzD/RDcv/0k8Nf9cUEv/XVBM/1xQTP9cUEz/XFBM/1xQTP9bT0v/
WExI/2xhXf+mnJn/ST41/0s9Nv9NPjf/Tj43/04/OP9OQDj/TkA5/05BOf9OQTn/T0I6/1BDO/9Q
Qzv/UUM8/1FEPP9RRDz/UkQ9/1BDO/9ZTUX2urWyI8fDwADEwL0AxMC9AMTAvQDEwL0AxMC9AMXA
vQDCvroAv7m4ALStqwDHwsAA3trZANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjX
ANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA
3trZAMrFwwDFwL4At7GuALy3tAC4sa8AycXDAMTAvQDKxsMAxsK/AL65tgC4s7AAwr25AMG7twDD
v8MAy8vfAM3N5QDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM
4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMzi
AMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzs7jAMLC3QCurtMA2dnqAObm8QDq6vMA
1dXnFg0OgfEAAHn/AAB1/0VGqf9BQ+P/ExXW/xkb1/8ZG9f/GhzY/xoc2P8aHNj/GhzY/xMV1/9M
TuSvZ1tqGVNDPPdMOzn/oZeV/5+Vkv+Cd3P/hnt3/4Z7d/+Fenb/opuXUqyloQCqo58A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AM7P4wDQ0OQA
0NHkBS8vic4AAGv/AABw/wAAcP8AAG//AABv/wAAbf8AAG3/AABs/wAAav+Gh8//XGD//zs6wf9Y
TEb/WExH/1hMSP9YTEj/WExI/1hLR/9WSkb/VEhD/7iwrv/i3d3/2tbV/9vX1v/c2Nf/3NjX/9zY
1//d2dj/3dnY/97a2f/e2tn/39va/+Dc2//g3Nv/4d3c/+He3f/i3t3/5uLh/+vo5//JxcL/enBq
/0MzLP89LSX/RDQt/0Q1Lv9KPTX/XVFN/11RTf9dUU3/XVBM/1xQTP9cUEz/XFBM/1lMSP90aGX/
oJWS/0Q5MP9IPTX/ST42/0o/Nv9MPjf/TT83/04/N/9NPzf/TkA4/01AOP9OQTn/TkI6/09COv9P
Qjr/UEM7/1FDPP9LPTX/cWdhw8fCwADDvrsAwr27AMK9uwDCvbsAwr27AMK9uwDCvbsAwr26AMXA
vgC0rKoAx8LAAN7a2QDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjX
ANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXAN7a2QDKxcMA
xcC+ALexrgC8t7QAuLGvAMnFwwDEwL0AysbDAMbCvwC+ubYAt7KuAMK9ugDHxc4Azc3kAMzM4wDM
zOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM
4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMzi
AMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAM7O4wDDw90Arq7TAMbG4ACJiMAAjY3CAIKBuxMKC3/w
AAB6/wAAdf89PqL/SUvj/xIU1f8ZG9f/GRvX/xkb1/8ZG9f/GRvX/xoc2P8VF9j/Oj3hwYB4jx5X
Rz/5Sjw5/6Oamf+dlJD/gXZy/4V6dv+EeXX/hHl1/cG7uUDU0c8A0c3LAP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wCDg7gAhYW5AH19tR8PD3j1
AABu/wAAcP8AAHD/AABw/wAAcP8AAHD/AABu/wAAav8YGHr/mpzu/ztA/P9CP67/Wk1C/1hMR/9Y
TEj/WExI/1hMSP9YTEj/VkpG/1pNSv/IwL//3dnY/9nV1P/Z1dT/2tbV/9vX1v/b19b/29fW/9zY
1//d2dj/3dnY/93Z2P/e2tn/3trZ/9/b2v/g3Nv/4Nzb/+Hd3P/i3d3/6OTj/+fk5P+3sq7/aV1X
/z4vJ/89LSX/Sz03/15STv9dUU3/XVFN/11RTf9dUEz/XVBM/1xQTP9YTEf/e3Bt/5iNiv9ENS3/
STs0/0o8NP9IPDT/ST01/0k+Nf9KPzb/TD42/00+N/9OPzj/Tj84/05AOP9NQDj/TkE5/05BOf9P
Qjr/Sjw0/5GJhHvAu7gAurSxALq0sQC6tLEAurSxALq0sQC6tLEAurSxALm0sQC9uLYAsquoAMfC
wQDe2tkA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjX
ANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDe2tkAysXDAMXAvgC3sa4A
vLe0ALixrwDJxcMAxMC9AMrGwwDGwr8Av7q1AL25tgDNzNoA0dHnAM/P5ADPz+QAz8/kAM/P5ADP
z+QAz8/kAM/P5ADPz+QAz8/kAM/P5ADPz+QAz8/kAM/P5ADPz+QAz8/kAM/P5ADPz+QAz8/kAM/P
5ADPz+QAz8/kAM/P5ADPz+QAz8/kAM/P5ADPz+QAz8/kAM/P5ADPz+QAz8/kAM/P5ADPz+QAz8/k
AM/P5ADPz+QAz8/kAM/P5ADR0eUAyMjfALCw1ADLyuIAICCJAAAAbAAAAHITAwN78AAAe/8AAHb/
ODid/09R4/8SFNX/GBrW/xga1v8YGtb/GRvX/xkb1/8ZG9f/FhjX/y0w3s2qpsUrW0tD/Es5OP+n
nZv/m5GO/390cP+DeHT/g3h0/4Z7d+jBu7kVzcnIAMvHxQD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8AqKnNALCw0QCBgbZGAABt/wAAcP8AAHD/
AABw/wAAcP8AAHD/AABw/wAAcP8AAGj/RESa/42Q+/8uMvj/SEOc/1tOQP9ZTUn/WU1J/1hMSP9Y
TEj/WExI/1VJRf9jV1P/08zL/9rW1f/X09L/19PS/9jU0//Z1dT/2dXU/9rW1f/a1tX/29fW/9vX
1v/c2Nf/3dnY/93Z2P/d2dj/3trZ/97a2f/f29r/39va/+Dc2//i3t3/6ebl/+Lf3f+pop7/W05I
/0g5M/9fU0//XlJO/15RTf9dUU3/XVFN/11RTf9dUU3/WEtH/4J2dP+QhID/QTEq/0k5Mv9KOjP/
Sjoz/0o7NP9JPDT/SDw0/0g9Nf9JPjb/Sj42/0s+N/9NPjf/TT43/04/OP9NQDj/TD83/1BDPP65
s7A20M3LAMzIxgDMyMYAzMjGAMzIxgDMyMYAzMjGAMzIxgDMyMYAzsvJALWurADHwsEA3trZANzY
1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjX
ANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3trZAMrFwwDFwL4At7GuALy3tAC4sa8A
ycXDAMTAvQDKxsMAx8K+ALayugCwsNAAtLTWALOz1ACzs9UAs7PVALOz1QCzs9UAs7PVALOz1QCz
s9UAs7PVALOz1QCzs9UAs7PVALOz1QCzs9UAs7PVALOz1QCzs9UAs7PVALOz1QCzs9UAs7PVALOz
1QCzs9UAs7PVALOz1QCzs9UAs7PVALOz1QCzs9UAs7PVALOz1QCzs9UAs7PVALOz1QCzs9UAs7PV
ALOz1QCzs9UAtbXWAKmpzy2oqNAf3NvrALy82gCXl8cAjo7CEwsLffAAAHj/AAB2/zM0mv9VV+P/
ERPV/xga1v8YGtb/GBrW/xga1v8YGtb/GBrW/xYY1/8pLN3Lk42tOFhIP/9LPDn/qqGg/5eNif9+
c2//gXZy/4B1cf+LgX7kurWyC7m0sQC5tLEA////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////ALOz1AC9vdoAYGGleQAAa/8AAXH/AAFx/wABcP8AAG//
AABw/wAAcP8AAHD/AABo/3Jzvv9scPz/LTH2/0tEiv9bTkD/WU1J/1lNSf9ZTUn/WU1J/1hMSP9U
R0P/bmJf/9rU0//W09L/1tLR/9bS0f/X09L/19PS/9jU0//Y1NP/2dXU/9nV1P/a1tX/2tfW/9vX
1v/c2Nf/3NjX/93Z2P/d2dj/3dnY/97a2f/e29r/39va/9/b2v/i3t3/6ebl/93Z2P+OhIH/Wk1J
/15STv9eUk7/XlJO/15RTf9dUU3/XVFN/1dLR/+IfXr/hnx3/z4wKf9GODH/Rzgx/0k5Mv9JOTL/
Sjoz/0o6M/9KOzT/STw0/0g8NP9IPjX/ST42/0o+Nv9LPjf/TT43/0k6Mv9mWVPbvLe0CLu2swC6
tbIAurWyALq1sgC6tbIAurWyALq1sgC6tbIAurWyALu2swC1r60AysXEAN7a2QDc2NcA3NjXANzY
1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjX
ANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXAN7a2QDKxcMAxcC+ALexrgC8t7QAuLGvAMnFwwDEwL0A
ysXDAMrFwQDFxNkAsrLWALS01QC0tNUAtLTVALS01QC0tNUAtLTVALS01QC0tNUAtLTVALS01QC0
tNUAtLTVALS01QC0tNUAtLTVALS01QC0tNUAtLTVALS01QC0tNUAtLTVALS01QC0tNUAtLTVALS0
1QC0tNUAtLTVALS01QC0tNUAtLTVALS01QC0tNUAtLTVALS01QC0tNUAtLTVALS01QC0tNUAtLTV
AL6+2gBnZ6yOOTiT09TU5w7o5/IA6urzANPT5xYNDX7xAAB2/wAAc/8zM5j/WFrk/xAS1P8XGdX/
FxnV/xga1v8YGtb/GBrW/xga1v8VF9b/KCvdyX94l0hWRTz/Tjw6/6+mpP+SiYX/fXJu/4B1cf99
cm7/k4qGudnX1QLa19YA2dbVAP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wCgoMkAqqrOAEFClK8AAGz/AAFx/wABcf8AAXH/AAFx/wABcP8AAG//
AABu/wYGcf+Pkd7/S072/zA19P9PR3r/W05C/1lNSf9ZTUn/WU1J/1lNSf9ZTUn/U0dD/3pvbP/d
2Nf/09DP/9TQz//V0dD/1dHQ/9bS0f/W09L/19PS/9fT0v/Y1NP/2NTT/9nV1P/Z1dT/2tbV/9vX
1v/b19b/3NjX/9zY1//d2df/3dnY/93Z2P/e2tn/3tva/9/b2v/p5eX/rqak/1lLSP9fUk7/XlJO
/15STv9eUk7/XlJO/15RTf9XS0b/jIF//4B0b/8+Lif/RTcv/0U4MP9FODH/Rjgx/0c4Mf9JOTL/
STky/0o5Mv9KOjP/Sjs0/0k8NP9IPTT/SD01/0k+Nv9FODD/cWZgo6egnAChmpYAoZqWAKGalgCh
mpYAoZqWAKGalgChmpYAoZqWAKGalgChmpYAnpeTAMG8uwDf29oA3NjXANzY1wDc2NcA3NjXANzY
1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjXANzY1wDc2NcA3NjX
ANzY1wDc2NcA3NjXANzY1wDe2tkAycTCAMXAvgC3sa4AvLe0ALixrwDJxcMAxMC9AMvGwgCxrsYA
rq7UALKy0wCxsdMAsbHTALGx0wCxsdMAsbHTALGx0wCxsdMAsbHTALGx0wCxsdMAsbHTALGx0wCx
sdMAsbHTALGx0wCxsdMAsbHTALGx0wCxsdMAsbHTALGx0wCxsdMAsbHTALGx0wCxsdMAsbHTALGx
0wCxsdMAsbHTALGx0wCxsdMAsbHTALGx0wCxsdMAsbHTALGx0wCxsdMAsbHTALGx0wC8vNkAVlaj
qwAAa/9WVqS00dDlBMTE3gCtrdIkCwt99wAAdv8AAHP/MTGW/1xe5P8QEtT/FxnV/xcZ1f8XGdX/
FxnV/xga1v8YGtb/FRfW/yot3sd4cI9XUkI5/1BBPv+zqqn/jIJ+/3xxbf9/dHD/fHBt/5uTj5bC
vbsAvrm3AL65twD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8AuLjWALa21QYiI4PUAABu/wAAcf8AAXH/AAFx/wABcf8AAXH/AAFx/wAAbP8kJYX/
lJby/zQ48f8zN+7/Uklt/1tPRP9aTkr/WU1J/1lNSf9ZTUn/WU1J/1JGQv+HfHr/3dnY/9LOzf/S
zs3/08/O/9TQz//U0M//1dHQ/9XR0P/W0tH/1tLR/9fT0v/X09L/2NTT/9jU0//Z1dT/2dXU/9rW
1f/a1tX/29fW/9zY1//c2Nf/3dnY/93Z2P/d2dj/5OHg/6OamP9ZTEj/X1NP/19ST/9fUk7/X1JO
/15STv9eUk7/WEtG/4+Egv96bmn/PS0m/0U1Lv9FNS7/RTYv/0U3L/9FODD/RTgw/0Y4Mf9IODH/
STky/0k5Mv9KOjP/Sjsz/0o7NP9JOzT/RTkx/5SNiWWxrKgArKejAKynowCsp6MArKejAKynowCs
p6MArKejAKynowCsp6MArKejAKqkoADDv7wA4d3dAN7a2gDe2toA3traAN7a2gDe2toA3traAN7a
2gDe2toA3traAN7a2gDe2toA3traAN7a2gDe2toA3traAN7a2gDe2toA3traAN7a2gDe2toA3tra
AN7a2gDe2toA4NzbANDMygDJxMIAt7GuALy3tAC4sa8AycXDAMTAuwDX1doAy8zjAMrK4gDKyuIA
ysriAMrK4gDKyuIAysriAMrK4gDKyuIAysriAMrK4gDKyuIAysriAMrK4gDKyuIAysriAMrK4gDK
yuIAysriAMrK4gDKyuIAysriAMrK4gDKyuIAysriAMrK4gDKyuIAysriAMrK4gDKyuIAysriAMrK
4gDKyuIAysriAMrK4gDKyuIAysriAMrK4gDKyuIAysriAMrK4gDMzOMAzc3jBDMzkNcAAHL/AABy
/1FSoZq7u9kAj4/AMgoKe/0AAHb/AABz/zU1mP9dX+X/DxHT/xYY1P8WGNT/FxnV/xcZ1f8XGdX/
FxnV/xAS1f9GSN/HoJiZc0s4Nf9VRUT/t6+t/4Z7d/97cGz/fXJu/3luaf+impdfysTCAMW/vQDF
v70A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AKiozgCZmcYgEBB79QAAcP8AAHL/AABy/wAAcv8AAXH/AAFx/wABcf8AAGr/Tk+i/4GE+v8sMPD/
NTnp/1RKY/9bT0X/Wk5K/1pOSv9aTkr/Wk5K/1lNSf9SRUH/koiG/9zY1//QzMv/0s7N/9LOzf/S
zs3/0s7N/9PPzv/Tz87/1NDP/9XR0P/V0dD/1tLQ/9bS0f/X09L/19PS/9jU0//Y1NP/2dXU/9nV
1P/a1tX/29fW/9vX1v/c2Nf/3dnY/+Tg3v+hmJX/WkxI/2BST/9fU0//X1NP/19ST/9fUk7/XlJO
/1hMR/+Rh4X/dWhk/zwsJf9DNC3/RDQt/0Q0Lf9FNS7/RTUu/0U2Lv9FNy//RTgw/0U4MP9GODH/
SDky/0k5Mv9KOTL/SDgx/1BBOvq3sa4qysXEAMbCwADGwsAAxsLAAMbCwADGwsAAxsLAAMbCwADG
wsAAxsLAAMbCwADHwsAAxL+9AMK9uwDCvbsAwr27AMK9uwDCvbsAwr27AMK9uwDCvbsAwr27AMK9
uwDCvbsAwr27AMK9uwDCvbsAwr27AMK9uwDCvbsAwr27AMK9uwDCvbsAwr27AMK9uwDCvbsAwr27
AMK9uwDDv70AvLe0ALaxrgC/urcAubKxAM3IwwC0sbcAkJHBAJCRwgCRkcEAkZHBAJGRwQCRkcEA
kZHBAJGRwQCRkcEAkZHBAJGRwQCRkcEAkZHBAJGRwQCRkcEAkZHBAJGRwQCRkcEAkZHBAJGRwQCR
kcEAkZHBAJGRwQCRkcEAkZHBAJGRwQCRkcEAkZHBAJGRwQCRkcEAkZHBAJGRwQCRkcEAkZHBAJGR
wQCRkcEAkZHBAJGRwQCRkcEAkZHBAJGRwQCRkcEAkpLCAJGRwSQXF4H2AAB0/wAAdv8BAXX/fn65
dICAuEEEBHj/AAB2/wAAcf83OJr/W13k/w8R0/8WGNT/FhjU/xYY1P8WGNT/FhjU/xYY1P8QEtb/
SEnVwIt/eZBJODX/W01K/7qxr/+AdXH/em9r/3xxbf97cGz/pp6cRbOsqgCwqqcAsKqnAP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDd3ewAoaHK
QwAAcP4AAHH/AABy/wAAcv8AAHL/AABy/wAAcv8AAXH/AABp/3R2wv9lafr/LDDv/zY54v9XTFv/
W09G/1pOSv9aTkr/Wk5K/1pOSv9aTkr/U0ZC/52Tkf/a1tX/zsrJ/9DMy//QzMv/0c3M/9LOzf/S
zs3/0s7N/9PPzv/Tz87/08/P/9TQz//V0dD/1tLR/9bS0f/X09L/19PS/9fT0v/Y1NP/2NTT/9nV
1P/a1tX/2tbV/9vX1v/i3t3/rKWj/1tOSv9gU0//YFNP/2BST/9fU0//X1NP/19STv9ZTEj/kIaE
/2xeWf81JB3/QTIq/0MzLP9DMyz/RDQt/0Q0Lf9FNS7/RTUu/0U1Lv9FNi//RTcv/0U4MP9FOTD/
Rjgx/0MzLP9iVU/Zv7q4B765tgC9uLYAvbi2AL24tgC9uLYAvbi2AL24tgC9uLYAvbi2AL24tgC9
uLYAvbi2AL24tgC9uLYAvbi2AL24tgC9uLYAvbi2AL24tgC9uLYAvbi2AL24tgC9uLYAvbi2AL24
tgC9uLYAvbi2AL24tgC9uLYAvbi2AL24tgC9uLYAvbi2AL24tgC9uLYAvbi2AL24tgC9uLYAvbi2
AL65twDAu7kAw728AL63tQDFwcAAs7HLAKOjzQCkpMwApKTMAKSkzACkpMwApKTMAKSkzACkpMwA
pKTMAKSkzACkpMwApKTMAKSkzACkpMwApKTMAKSkzACkpMwApKTMAKSkzACkpMwApKTMAKSkzACk
pMwApKTMAKSkzACkpMwApKTMAKSkzACkpMwApKTMAKSkzACkpMwApKTMAKSkzACkpMwApKTMAKSk
zACkpMwApKTMAKSkzACkpMwApKTMAKqqzwCFhbpKAQF0/wAAdv8AAHb/AABy/ysrjd+Dg7plAAB1
/wAAdv8AAHH/Pj6e/1lb5P8OENL/FhjU/xYY1P8WGNT/FhjU/xYY1P8WGNT/DhDV/1JT2LCAcmuj
SDUz/2VWVf+5sa//enBr/3pva/96b2r/fXJu6sbBvxnW09EA09DOANPQzgD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8AlJTCAGVlqGoAAG3/AABy
/wAAcv8AAHL/AABy/wAAcv8AAHL/AABx/wQFcv+Mjdz/SEz0/y8z8P83Odv/WU1V/1xPSP9bT0v/
Wk5K/1pOSv9aTkr/Wk5K/1RHQ/+nnZv/2NPS/83JyP/Oysn/z8vK/8/Lyv/QzMv/0c3M/9HNzP/R
zcz/0s7N/9LOzf/Tz87/08/O/9TQz//U0c//1dHQ/9bS0P/W0tH/19PS/9fT0v/X09L/2NTT/9jU
0//Z1dT/4Nzb+bq0supeUU7/YFNP/2BUUP9gUk//YFNP/19TT/9fU0//WUxI/5GGhP+xqqf/X1JM
/zssJP85KSH/QDAp/0IzLP9DMyz/QzMs/0Q0Lf9ENS3/RTUu/0U1Lv9FNS7/RTYv/0U3L/8+MSn/
eXBqqr65tgC2sa4AtrGuALaxrgC2sa4AtrGuALaxrgC2sa4AtrGuALaxrgC2sa4AtrGuALaxrgC2
sa4AtrGuALaxrgC2sa4AtrGuALaxrgC2sa4AtrGuALaxrgC2sa4AtrGuALaxrgC2sa4AtrGuALax
rgC2sa4AtrGuALaxrgC2sa4AtrGuALaxrgC2sa4AtrGuALaxrgC2sa4AtrGuALaxrgC2sa4AtrGu
ALaxrgC3sq0As7C+AJydygCgoMkAoKDJAKCgyQCgoMkAoKDJAKCgyQCgoMkAoKDJAKCgyQCgoMkA
oKDJAKCgyQCgoMkAoKDJAKCgyQCgoMkAoKDJAKCgyQCgoMkAoKDJAKCgyQCgoMkAoKDJAKCgyQCg
oMkAoKDJAKCgyQCgoMkAoKDJAKCgyQCgoMkAoKDJAKCgyQCgoMkAoKDJAKCgyQCgoMkAoKDJAKCg
yQCgoMkAoKDJAKCgyQCpqc4AYWGniQAAcP8AAHb/AAB2/wAAcP9GRp65lZbGZwAAcv8AAHf/AABx
/0ZHpP9VV+X/DhDR/xUX0/8VF9P/FRfT/xYY1P8WGNT/FhjU/wwO1P9kZuDqfnFo7UQyMf9xYmH/
t66s/3ZqZv94bmr/dmtn/4l/e9LIw8EDx8PAAMfCwADHwsAA////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AMHC3ABRUZ6MAABs/wAAcv8AAHL/AABy
/wAAcv8AAHL/AABy/wAAb/8eHoL/kJPv/zQ47/8wNPH/ODrV/1pOUP9bT0n/W09L/1tPS/9bT0v/
Wk5K/1pOSv9VSUX/rqSj/9XR0P/MyMb/zMjH/83JyP/Oysn/zsrJ/8/Lyf/Py8r/0MzL/9HNzP/R
zcz/0s7N/9LOzf/Szs3/08/O/9PPzv/U0M//1NDP/9XR0P/W0tH/1tLR/9fT0v/X09L/19PS/9vY
19LFwL8+ZFdU/V9STv9hVFD/YFRQ/2BUUP9gU0//YFNP/1lMSP+Mgn//6ubl/9zZ1/+up6T/bWJc
/0ExKv84JyD/Pi0m/0IyK/9CMiv/QzMs/0MzLP9ENC3/RDQt/0U0Lf9FNS7/QTEp/4B2cXmlnpoA
oJmVAKCZlQCgmZUAoJmVAKCZlQCgmZUAoJmVAKCZlQCgmZUAoJmVAKCZlQCgmZUAoJmVAKCZlQCg
mZUAoJmVAKCZlQCgmZUAoJmVAKCZlQCgmZUAoJmVAKCZlQCgmZUAoJmVAKCZlQCgmZUAoJmVAKCZ
lQCgmZUAoJmVAKCZlQCgmZUAoJmVAKCZlQCgmZUAoJmVAKCZlQCgmZUAoJmVAKCZlQCgmZUAoJmS
AKCeuAChoswAoaHJAKGhyQChockAoaHJAKGhyQChockAoaHJAKGhyQChockAoaHJAKGhyQChockA
oaHJAKGhyQChockAoaHJAKGhyQChockAoaHJAKGhyQChockAoaHJAKGhyQChockAoaHJAKGhyQCh
ockAoaHJAKGhyQChockAoaHJAKGhyQChockAoaHJAKGhyQChockAoaHJAKGhyQChockAoaHJAKGh
yQChockAq6vPAEFBl8IAAHH/AAB1/wAAdv8AAHD/YmKyl21usnoAAHL/AQF3/wAAcP9QUav/T1Hk
/w0P0P8UFtL/FRfT/xUX0/8VF9P/FRfT/xUX0/8ND9X/amrW/21eVP9FMjH/gHJx/7Copf9yZmL/
d21o/3NoZP+UjIib0s7NAM/LygDPy8kAz8vJAP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wC4uNYAQECUtQAAbP8AAHL/AABy/wAAcv8AAHL/AABy
/wAAcv8AAGz/P0CY/4OG9/8rL+z/MTTx/zk6zv9bT07/XE9J/1tPS/9bT0v/W09L/1tPS/9aTkr/
WEtH/7Oqqf/Tzs3/ysbF/8vHxv/MyMf/zMjH/83JyP/Nycj/zcnI/87Kyf/Py8n/z8vK/9DMy//Q
zMv/0c3M/9LOzP/Szs3/0s7N/9LOzf/Tz87/1NDP/9TQz//V0dD/1tLR/9bS0f/a19bSxb+9F2db
WOlfUk7/YVRQ/2FUUP9gVFD/YFRQ/2BUUP9aTEj/iX17/+Le3f/f29r/5eLh/+Hd3P+9t7T/fnRv
/0s9Nv84JyD/Oyoj/0AwKf9CMiv/QjIr/0MzLP9DMyz/QzMs/0MzLP+ooZ5ExL++AL+6uAC/urgA
v7q4AL+6uAC/urgAv7q4AL+6uAC/urgAv7q4AL+6uAC/urgAv7q4AL+6uAC/urgAv7q4AL+6uAC/
urgAv7q4AL+6uAC/urgAv7q4AL+6uAC/urgAv7q4AL+6uAC/urgAv7q4AL+6uAC/urgAv7q4AL+6
uAC/urgAv7q4AL+6uAC/urgAv7q4AL+6uAC/urgAv7q4AL+6uAC/urgAwLq4AL+5uACvrs0ArKzS
AK2t0QCtrdEAra3RAK2t0QCtrdEAra3RAK2t0QCtrdEAra3RAK2t0QCtrdEAra3RAK2t0QCtrdEA
ra3RAK2t0QCtrdEAra3RAK2t0QCtrdEAra3RAK2t0QCtrdEAra3RAK2t0QCtrdEAra3RAK2t0QCt
rdEAra3RAK2t0QCtrdEAra3RAK2t0QCtrdEAra3RAK2t0QCtrdEAra3RAK2t0QCtrdEAr6/SAKip
zxkbG4LxAABz/wAAdv8AAHX/AABy/5KT05tfX6qkAABw/wEBd/8AAHD/XF20/0ZI4v8ND9D/FBbS
/xQW0v8UFtL/FBbS/xUX0/8VF9P/DxHX/21sx/9fTUL/RjMy/5GFg/+lnJn/b2Rg/3ZrZ/9yZmL/
pJ2aYcnGwwDEwL4AxMC+AMTAvgD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8Aj5DAASIihMsAAG7/AABy/wAAcv8AAHL/AABy/wAAcv8AAHL/AABr
/2Jjs/9rbvf/KS7q/zA18f87O8n/XFBN/11QS/9cT0z/XE9L/1tPS/9bT0v/Wk5K/1pNSf+3r63/
z8vK/8nFxP/JxcT/ysbF/8vHxv/Lx8b/zMjH/8zIx//MyMf/zcnI/83JyP/Oysn/zsrJ/8/Lyv/Q
zMv/0MzL/9HNzP/Szs3/0s7M/9LOzf/Szs3/08/O/9TQz//U0M//2dXU8cjDwS9wZGHQXlFN/2FV
Uf9hVFH/YlNQ/2FTUP9gVFD/Wk5K/4V6d//g29r/3NjX/9zY1//e2tn/4+Df/+Xi4f/Mx8X/lYyI
/1tNR/88LCX/OCcg/z4tJv9BMSr/QjIr/z8vKP9OQTryn5iUH6KbmAChmpcAoZqXAKGalwChmpcA
oZqXAKGalwChmpcAoZqXAKGalwChmpcAoZqXAKGalwChmpcAoZqXAKGalwChmpcAoZqXAKGalwCh
mpcAoZqXAKGalwChmpcAoZqXAKGalwChmpcAoZqXAKGalwChmpcAoZqXAKGalwChmpcAoZqXAKGa
lwChmpcAoZqXAKGalwChmpcAoZqXAKGalwChmpcAoZqXAJ+ZkwCnoqgAv7/dAL/A3AC/v9sAv7/b
AL+/2wC/v9sAv7/bAL+/2wC/v9sAv7/bAL+/2wC/v9sAv7/bAL+/2wC/v9sAv7/bAL+/2wC/v9sA
v7/bAL+/2wC/v9sAv7/bAL+/2wC/v9sAv7/bAL+/2wC/v9sAv7/bAL+/2wC/v9sAv7/bAL+/2wC/
v9sAv7/bAL+/2wC/v9sAv7/bAL+/2wC/v9sAv7/bAL+/2wC/v9sAv7/bAMbH3wCbm8dQAgJz/wAA
dP8AAHb/AAB0/wsLff+ztOr3TEyf+gAAcP8AAHb/AABw/2hqv/86PN//Dg/Q/xMV0f8UFdL/FBbR
/xQW0v8UFtL/ExbS/xIV2f9saLH/VEE2/0g1NP+hlpX/l46L/29kYP90aWX/dGlk+LSurC7Hw8AA
xL+9AMS/vQDEv70A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AMjJ4BMXF37pAABv/wAAcv8AAHL/AABy/wAAcv8AAHL/AABy/wAAbP98fcv/VFf1
/yww6v8vNPH/OzvF/1xQS/9cUEv/XFBM/1xQTP9cUEz/W09L/1pOSv9bTkr/urGw/83Kyf/Hw8L/
yMTC/8jEw//JxcT/ysbF/8rGxf/Lx8b/y8fG/8zIx//MyMf/zMjI/83JyP/Oysn/zsrJ/8/Lyv/P
y8r/0MzL/9DMy//Rzcz/0s7N/9LOzf/Szs3/08/O/9TR0P/Z1dU2e3Btq15PTP9iVFH/YVVR/2FV
Uf9hVFH/YlNQ/1tOSv+AdXH/3dnY/9rW1f/a1tX/29fW/9vX1v/d2dj/4d3c/+bj4v/a1tX/rqek
/3NoYv9GNi//Nycf/zoqI/86KiL/X1JM1tTR0ATT0M4A0s/NANLPzQDSz80A0s/NANLPzQDSz80A
0s/NANLPzQDSz80A0s/NANLPzQDSz80A0s/NANLPzQDSz80A0s/NANLPzQDSz80A0s/NANLPzQDS
z80A0s/NANLPzQDSz80A0s/NANLPzQDSz80A0s/NANLPzQDSz80A0s/NANLPzQDSz80A0s/NANLP
zQDSz80A0s/NANLPzQDSz80A0s/NANLPzQDU0M0AycfSALa21wC3t9UAt7fWALe31gC3t9YAt7fW
ALe31gC3t9YAt7fWALe31gC3t9YAt7fWALe31gC3t9YAt7fWALe31gC3t9YAt7fWALe31gC3t9YA
t7fWALe31gC3t9YAt7fWALe31gC3t9YAt7fWALe31gC3t9YAt7fWALe31gC3t9YAt7fWALe31gC3
t9YAt7fWALe31gC3t9YAt7fWALe31gC3t9YAt7fWALe31QDDw9wAYWGmlQAAbf8AAHP/AAB0/wAA
cf8tLpP/pqft/yUli/8AAHL/AAB1/wAAcv90dcv/LS/b/w8R0P8TFdH/ExXR/xMV0f8TFdH/FBXS
/xMU0f8XGtv/aGGV/088Mv9LOTj/sKal/4mAfP9wZGD/cWZi/3xxbdm8t7UHw768AMK8uwDCvLsA
wry7AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wB/gLgpDQ16+gAAcf8AAHL/AABy/wAAcv8AAHL/AABy/wAAcP8GBnP/i43g/z9C8P8uMer/LzTy
/zs8wf9dUEr/XVBL/1xQTP9cUEz/XFBM/1xQTP9bT0v/XE9L/7uzsf/MyMf/xsLB/8fDwv/Hw8L/
x8PC/8jEw//IxMP/ycXE/8rGxf/KxsX/y8fG/8vHxv/MyMf/zMjH/83JyP/Nycj/zcnI/87Kyf/P
y8r/z8vK/9DMy//Rzcz/0c3M/9LOzf/U0M//0s7OMIR6d4peUU3/YlVS/2JVUf9iVFH/YVVR/2FV
Uf9dUEz/em5r/9rW1f/Z1dT/2dXU/9nV1P/a1tX/29fW/9vX1v/b19b/3trZ/+Tg4P/i397/x8LA
/5KIhf9bTkf/NSQd/2teWbmtpqMAp6CcAKegnACnoJwAp6CcAKegnACnoJwAp6CcAKegnACnoJwA
p6CcAKegnACnoJwAp6CcAKegnACnoJwAp6CcAKegnACnoJwAp6CcAKegnACnoJwAp6CcAKegnACn
oJwAp6CcAKegnACnoJwAp6CcAKegnACnoJwAp6CcAKegnACnoJwAp6CcAKegnACnoJwAp6CcAKeg
nACnoJwAp6CcAKegnACnn5wApZ6ZAMC+zADNzeMAy8vgAMvL4ADLy+AAy8vgAMvL4ADLy+AAy8vg
AMvL4ADLy+AAy8vgAMvL4ADLy+AAy8vgAMvL4ADLy+AAy8vgAMvL4ADLy+AAy8vgAMvL4ADLy+AA
y8vgAMvL4ADLy+AAy8vgAMvL4ADLy+AAy8vgAMvL4ADLy+AAy8vgAMvL4ADLy+AAy8vgAMvL4ADL
y+AAy8vgAMvL4ADLy+AAy8vgAMvL4ADMzOEA0dHjBDQ0jdQAAG7/AABz/wAAc/8AAGz/V1iw/4SF
5P8NDX3/AABz/wAAdP8HB3j/e33W/x8h1/8QEdD/EhTQ/xIV0P8TFdH/ExXR/xMV0f8REtH/ICPa
/2BVdv9LODD/VENC/7mxr/97cWz/b2Rg/21iXv+Lg3+fx8LAAMK+vADDvrwAw768AMO+vAD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8AgoK5NwQE
dP4AAHL/AABz/wAAcv8AAHL/AABy/wAAcv8AAG//HByB/4uO7v8wNOz/LzLq/y4x8P9AQMT/X1NM
/11RS/9eUEz/XVBM/1xQTP9cUEz/W09L/11STf+8tLP/ycbE/8TAv//FwcD/xsLB/8bCwf/Hw8L/
x8PC/8fEwv/IxMP/yMTD/8nFxP/KxsX/ysbF/8vHxv/Lx8b/zMjH/8zIx//MyMf/zcnI/87Kyf/O
ysn/z8vK/8/Lyv/QzMv/0c3M/9vY1jOrpKJaXU9L/2JWUv9iVlL/YlVS/2NUUf9iVVH/XVFN/3No
ZP/W0M//2NTT/9fT0v/X09L/2NTT/9nV1P/Z1dT/2dbV/9rW1f/b19b/3NjX/+Hd3f/l4uH/2dXU
/66no+upop9PyMTCAMXAvgDFwb4AxcG+AMXBvgDFwb4AxcG+AMXBvgDFwb4AxcG+AMXBvgDFwb4A
xcG+AMXBvgDFwb4AxcG+AMXBvgDFwb4AxcG+AMXBvgDFwb4AxcG+AMXBvgDFwb4AxcG+AMXBvgDF
wb4AxcG+AMXBvgDFwb4AxcG+AMXBvgDFwb4AxcG+AMXBvgDFwb4AxcG+AMXBvgDFwb4AxcG+AMXB
vgDFwb4AxcC+AMbBvgDMy9oAzMzjAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMzi
AMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIA
zMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDMzOIAzMziAMzM4gDM
zOIAzMziAMzM4gDMzOIA0tLlALGx0zUKCnf9AABw/wAAcv8AAHL/AABu/36A0f9SU83/AQF0/wAA
df8AAHP/FheA/31/3/8UF9L/ERPQ/xIU0P8SFND/EhTQ/xIU0f8TFdH/EBLS/yYo0P9XSVr/SDUw
/2VVVP+6sa//b2Vg/29kYP9sYVz/pJ2ZY8nFwgDEwL0AxMC9AMTAvQDEwL0A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AJSUxFwAAHD/AABy/wAA
c/8AAHP/AABz/wAAcv8AAHL/AABt/zY2kv+BhPT/KS3p/y8y6f8rMO//SkrP/2NWUP9cUUv/XVFN
/11RTf9dUEz/XVBM/1tPS/9eUk7/vbWz/8jDwv/Cvr3/w8C//8TAv//EwL//xsLB/8bCwf/Hw8L/
x8PB/8fDwv/HxML/yMTD/8jEw//JxcT/ysbF/8rGxv/Lx8b/zMjH/8zIx//MyMf/zcnI/83JyP/O
ysn/z8vK/8/Lyv/QzMo3qqSiL2VXVP9jVFH/Y1ZS/2JWUv9iVlL/Y1VR/2BRTv9uYV7/0MrJ/9fU
0//W0tH/1tLR/9fT0v/X09L/2NPT/9jU0//Y1NP/2dXU/9rW1f/a1tX/29fW/97a2f/k4N/S3drY
ANnW1ADa1tUA2tbVANrW1QDa1tUA2tbVANrW1QDa1tUA2tbVANrW1QDa1tUA2tbVANrW1QDa1tUA
2tbVANrW1QDa1tUA2tbVANrW1QDa1tUA2tbVANrW1QDa1tUA2tbVANrW1QDa1tUA2tbVANrW1QDa
1tUA2tbVANrW1QDa1tUA2tbVANrW1QDa1tUA2tbVANrW1QDa1tUA2tbVANrW1QDa1tUA2tbVAN3Z
1QDGw9AAqqrPAK2t0ACtrdAAra3QAK2t0ACtrdAAra3QAK2t0ACtrdAAra3QAK2t0ACtrdAAra3Q
AK2t0ACtrdAAra3QAK2t0ACtrdAAra3QAK2t0ACtrdAAra3QAK2t0ACtrdAAra3QAK2t0ACtrdAA
ra3QAK2t0ACtrdAAra3QAK2t0ACtrdAAra3QAK2t0ACtrdAAra3QAK2t0ACtrdAAra3QAK2t0ACt
rdAAra3QALe31QBxca6AAABt/wAAcv8AAHL/AABw/xMUff+Qkur/IiOx/wAAb/8AAHb/AABy/yoq
jf93eeX/DAzO/xERz/8REs//EhPQ/xIU0P8SFND/EhTQ/w4R1P8qKb3/U0JE/0UzMP99b27/sKek
/2leWv9uY1//b2Vg8bKuqiLFwb4Awr67AMK+uwDCvrsAwr67AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wBxcbFuAABx/wAAdP8AAHT/AABz/wAA
c/8AAHP/AABz/wAAa/9QUKb/cXT2/ycr6P8vMun/Ki3t/1FR2f9qXFf/XE9K/11RTf9dUU3/XVFN
/11RTf9cUEv/XlBM/7qxsP/HwsH/wr27/8K9vP/Cvrz/w7++/8TAv//EwL//xcHA/8XBwP/GwsH/
x8PC/8fDwv/Hw8L/x8PC/8jEw//JxcT/ycXE/8rGxf/KxsX/y8fG/8zIx//MyMf/zMjH/83JyP/M
yMf/1tPSSsnFxAluY1/nYFRQ/2NWUv9jVVL/Y1VS/2JWUv9gVFD/aFpX/8jBwP/X09L/1NDP/9XR
0P/V0dD/1tLR/9bT0f/X09L/19PS/9jU0//Y1NP/2dXU/9nV1P/a1tX/29fWx97b2gDe29oA3tva
AN7b2gDe29oA3tvaAN7b2gDe29oA3tvaAN7b2gDe29oA3tvaAN7b2gDe29oA3tvaAN7b2gDe29oA
3tvaAN7b2gDe29oA3tvaAN7b2gDe29oA3tvaAN7b2gDe29oA3tvaAN7b2gDe29oA3tvaAN7b2gDe
29oA3tvaAN7b2gDe29oA3tvaAN7b2gDe29oA3tvaAN7b2gDe29oA3tvaAN7b2gDi39sAxcPTAJ6e
yACioskAoqLJAKKiyQCioskAoqLJAKKiyQCioskAoqLJAKKiyQCioskAoqLJAKKiyQCioskAoqLJ
AKKiyQCioskAoqLJAKKiyQCioskAoqLJAKKiyQCioskAoqLJAKKiyQCioskAoqLJAKKiyQCioskA
oqLJAKKiyQCioskAoqLJAKKiyQCioskAoqLJAKKiyQCioskAoqLJAKKiyQCioskAoqLJAKKiyQCr
q84DNTWNzQAAbf8AAHL/AABy/wAAbP9BQZv/f4Hw/wIDmf8AAG7/AAB0/wAAb/9ERZ//aWvn/wgK
zf8RE8//ERLO/xESz/8REs//ERPP/xIT0P8OEdf/LCij/1A+Nf9EMjD/l4yK/52Ukf9nW1f/al9b
/31zb8m7trQBurWzALq1swC6tbMAurWzALq1swD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8AU1OhegAAcv8AAHb/AAB2/wAAdf8AAHP/AABz/wAA
c/8AAGz/Z2i6/1xg9P8nLOf/LjLp/ygt6/9VV+L/cWVh/1xPSf9fUU3/XlFN/11RTf9dUU3/XFBM
/15RTf+4sK//xcLA/8C8u//Bvbv/wr27/8K9vP/Cvb3/w769/8O/vv/DwL//xMC//8XBwP/FwcD/
xsLB/8fDwv/Hw8L/x8PC/8jEwv/IxMP/ycXE/8nFxP/KxsX/y8fG/8vHxv/MyMf/y8fG/9PQ0JHM
yMcAf3NwwGBRTv9jV1P/Y1dT/2NWUv9kVVL/YlVR/2JVUf++t7X/19PS/9LOzf/Tz87/1NDP/9TQ
z//V0dD/1dHQ/9bS0f/W0tH/19PS/9fT0v/Y1NP/2NTT/9nV1ITd2dgA3dnYAN3Z2ADd2dgA3dnY
AN3Z2ADd2dgA3dnYAN3Z2ADd2dgA3dnYAN3Z2ADd2dgA3dnYAN3Z2ADd2dgA3dnYAN3Z2ADd2dgA
3dnYAN3Z2ADd2dgA3dnYAN3Z2ADd2dgA3dnYAN3Z2ADd2dgA3dnYAN3Z2ADd2dgA3dnYAN3Z2ADd
2dgA3dnYAN3Z2ADd2dgA3dnYAN3Z2ADd2dgA3dnYAN3Z2ADd2dgA3trYAMzL3QC9vdoAvr7ZAL6+
2QC+vtkAvr7ZAL6+2QC+vtkAvr7ZAL6+2QC+vtkAvr7ZAL6+2QC+vtkAvr7ZAL6+2QC+vtkAvr7Z
AL6+2QC+vtkAvr7ZAL6+2QC+vtkAvr7ZAL6+2QC+vtkAvr7ZAL6+2QC+vtkAvr7ZAL6+2QC+vtkA
vr7ZAL6+2QC+vtkAvr7ZAL6+2QC+vtkAvr7ZAL6+2QC+vtkAvr7ZAL6+2QDDw9wApqbLMgkJdf0A
AHD/AABy/wAAcv8AAGv/c3TA/1VW5v8AAIv/AABv/wAAc/8AAGz/X2Cz/1NU5P8HCcz/EBLP/xAT
z/8RE8//ERPP/xESzv8REc//DhDX/zAogv9OOy//SDY1/6+kpP+GfXj/Z1tX/2VaVv+VjYmC1dHQ
AM/LygDPy8oAz8vKAM/LygDPy8oA////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////ADMzkIkAAHT/AAB2/wAAdv8AAHb/AAB2/wAAdP8AAHP/AABu/3h6
y/9KTfH/KS3n/y4y6P8nLOn/WFvq/3txbv9aTkj/XlJO/15RTv9eUU3/XlFN/1xQTP9dUEz/tayq
/8TAv/+/urn/v7u6/7+8u//Bvbz/wby7/8K9u//DvLz/wr28/8O+vv/Dv77/xMC//8TBwP/FwcD/
xsLB/8bCwf/GwsL/x8PC/8fDwv/IxML/yMTD/8nFxP/KxsX/ysbF/8vHxv/Oy8qYysfFAI+Fg4lf
UU7/ZVZT/2RXU/9jV1P/Y1dT/2NVUv9gUU3/samn/9fU0v/Szs3/0s7N/9LOzf/Tz87/08/O/9TQ
z//U0M//1dHQ/9bS0f/W0tH/19PR/9fT0v/Y1NOC19TSANfU0gDX1NIA19TSANfU0gDX1NIA19TS
ANfU0gDX1NIA19TSANfU0gDX1NIA19TSANfU0gDX1NIA19TSANfU0gDX1NIA19TSANfU0gDX1NIA
19TSANfU0gDX1NIA19TSANfU0gDX1NIA19TSANfU0gDX1NIA19TSANfU0gDX1NIA19TSANfU0gDX
1NIA19TSANfU0gDX1NIA19TSANfU0gDX09IA2dXUAMvGxQCuqKwAxsbcAMbH4ADFxd0AxcXdAMXF
3QDFxd0AxcXdAMXF3QDFxd0AxcXdAMXF3QDFxd0AxcXdAMXF3QDFxd0AxcXdAMXF3QDFxd0AxcXd
AMXF3QDFxd0AxcXdAMXF3QDFxd0AxcXdAMXF3QDFxd0AxcXdAMXF3QDFxd0AxcXdAMXF3QDFxd0A
xcXdAMXF3QDFxd0AxcXdAMXF3QDFxd0AxcXdAMXF3QDExd0A0NDjAHZ2sYcAAGz/AABy/wAAcv8A
AHD/CQl1/5SV4v8mKNP/AACB/wAAb/8AAHP/AABt/3d4yP86PN3/CgzM/w8Rzv8PEc7/EBLO/xES
z/8RE8//ERPP/w8S0/85LmX/TDgv/1VEQ/+8s7H/cmhi/2hcVv9oXVf9raekN8fCwQDDvrwAw768
AMO+vADDvrwAw768AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wBCQpiYAABw/wAAdv8AAHb/AAB2/wAAdv8AAHb/AAB1/wUEdf+ChNn/PEDu/ysv
6P8tMej/Jyvo/1hc8f+LgYH/WUxG/15STv9eUk7/XlJO/15STv9eUE3/XE5L/7Gopv/Fv7v/v7i1
/7+5t/++urj/v7u5/7+7u//AvLv/wLy7/8G8u//CvLz/wr28/8K9vf/Dv77/w7++/8TAv//EwL//
xcHA/8bCwf/GwsH/x8PC/8fDwv/Hw8L/yMTD/8jEw//JxMP/zMjHodbT0QCmn5xKYVVR/2RXVP9k
VlP/ZVZT/2RXU/9jV1P/XVFN/6KYlv/W0tH/0MzL/9DMy//Rzcz/0s7M/9LOzf/Szs3/0s7N/9PP
zv/U0M//1NDP/9XR0P/V0dD/19PShNjU0gDY1dMA2NXTANjV0wDY1dMA2NXTANjV0wDY1dMA2NXT
ANjV0wDY1dMA2NXTANjV0wDY1dMA2NXTANjV0wDY1dMA2NXTANjV0wDY1dMA2NXTANjV0wDY1dMA
2NXTANjV0wDY1dMA2NXTANjV0wDY1dMA2NXTANjV0wDY1dMA2NXTANjV0wDY1dMA2NXTANjV0wDY
1dMA2NXTANjV0wDY1NIA2tfVANPPzgCqoqEAn5aUAKOcoAC2tM4AtbbWALW11AC1tdQAtbXUALW1
1AC1tdQAtbXUALW11AC1tdQAtbXUALW11AC1tdQAtbXUALW11AC1tdQAtbXUALW11AC1tdQAtbXU
ALW11AC1tdQAtbXUALW11AC1tdQAtbXUALW11AC1tdQAtbXUALW11AC1tdQAtbXUALW11AC1tdQA
tbXUALW11AC1tdQAtbXUALW11AC1tdQAtrbUALq61wgtLYncAABu/wAAcv8AAHL/AABt/zc3lP+J
i+//CQrA/wAAeP8AAHD/AABx/wgIdf+Fh9z/ICHV/wwMzP8PEM3/EBHN/xASzf8PEc7/DxHO/w8R
0P8TFMf/QjRL/0c0Lv9uX17/ubCu/2VaVf9mWlX/dGpl0bq1sga9uLYAvLe0ALy3tAC8t7QAvLe0
ALy3tAD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8ASkqdtQAAcP8AAHb/AAB2/wAAdf8AAHb/AAB2/wAAdP8PD3z/hYfk/zI16/8sMOf/LTHn/ycr
5/9TV/P/nJSY/1lLRf9gUU7/X1JO/15STv9eUk7/XlJO/1pOSv+so6H/xb+7/724sv++uLP/v7i0
/7+4tf+/ubf/vrq4/7+7uv+/u7r/wLy7/8C8u//BvLz/wry8/8O9u//Cvbz/w7+9/8O/v//EwL//
xMC//8XBwP/FwcD/xsLB/8fDwv/Hw8L/x8PB/8rGxd3Szs0Gv7m4E29iX+tiVVH/ZFhU/2RYVP9l
V1P/ZFdT/15RTf+SiIX/1dHQ/87Kyf/Py8r/z8vK/9DMy//QzMv/0c3M/9LOzf/Szs3/0s7N/9LO
zf/Tz87/08/O/9jV1IXc2tgA3NnYANzZ2ADc2dgA3NnYANzZ2ADc2dgA3NnYANzZ2ADc2dgA3NnY
ANzZ2ADc2dgA3NnYANzZ2ADc2dgA3NnYANzZ2ADc2dgA3NnYANzZ2ADc2dgA3NnYANzZ2ADc2dgA
3NnYANzZ2ADc2dgA3NnYANzZ2ADc2dgA3NnYANzZ2ADc2dgA3NnYANzZ2ADc2dgA3NnYANzZ2ADc
2dgA3tvZANnW1AC6tLMAp5+eAKOamQCQhYIAtrCxANPS4gDS0ucA0dHkANHR5ADR0eQA0dHkANHR
5ADR0eQA0dHkANHR5ADR0eQA0dHkANHR5ADR0eQA0dHkANHR5ADR0eQA0dHkANHR5ADR0eQA0dHk
ANHR5ADR0eQA0dHkANHR5ADR0eQA0dHkANHR5ADR0eQA0dHkANHR5ADR0eQA0dHkANHR5ADR0eQA
0dHkANHR5ADR0eQA0dHkANnZ6QCkpctIAgNv/wAAcP8AAHL/AABy/wAAa/9zdL7/Wlzp/wEBsv8A
AHD/AABx/wAAbv8kJIb/g4Xm/w4Qzv8OD83/Dw/N/w8Pzf8PD83/DxDN/xARzf8NENP/Gxmw/0g3
Ov9DMC3/kYSE/6Oal/9gVVH/YVZS/4qCf4fDvr0Avbm3AL65twC+ubcAvrm3AL65twC+ubcA////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////ADw8lr4A
AHH/AAB2/wAAdv8AAHb/AAB1/wAAdf8AAHP/HR2E/4KF7P8qLuj/Ky/m/yww5/8oLOf/S0/y56eh
rKJbTkf/X1NP/19ST/9fUk7/X1FO/15STv9ZTEj/ppyb/8S/vf+7tbP/vLez/723sv+9uLP/vriz
/764tP++uLX/v7m3/766uP++urr/v7u7/8C8u//BvLv/wr28/8K9u//Cvbz/wr28/8K+vf/Dv77/
xMC//8TBwP/FwcD/xsLB/8bCwf/Hw8HlzcrICsK8uwCAdXK0YVNP/2VXVP9lWFT/ZFhU/2RYVP9g
UU7/gnVy/9HNy//Nycj/zcnI/83JyP/Oysn/z8vK/8/Lyv/QzMv/0MzL/9HNzP/Rzcz/0s7N/9HN
zP/a19ZS4uDeAOHf3QDh390A4d/dAOHf3QDh390A4d/dAOHf3QDh390A4d/dAOHf3QDh390A4d/d
AOHf3QDh390A4d/dAOHf3QDh390A4d/dAOHf3QDh390A4d/dAOHf3QDh390A4d/dAOHf3QDh390A
4d/dAOHf3QDh390A4d/dAOHf3QDh390A4d/dAOHf3QDh390A4d/dAOHf3QDh390A4uDeAOPh3wDG
wcEAqKCgAKqioQCjmpkAk4mHALewrgC+uLoAtbPMALi42AC3t9UAt7fVALe31QC3t9UAt7fVALe3
1QC3t9UAt7fVALe31QC3t9UAt7fVALe31QC3t9UAt7fVALe31QC3t9UAt7fVALe31QC3t9UAt7fV
ALe31QC3t9UAt7fVALe31QC3t9UAt7fVALe31QC3t9UAt7fVALe31QC3t9UAt7fVALe31QC3t9UA
t7fVALe31QDCwtsAVVWeqgAAa/8AAXH/AAFx/wAAcP8MDHf/mJnj/yUm2f8DBKL/AABt/wAAcv8A
AGv/R0if/29w6P8FBsr/Dg/M/w8QzP8PEc3/DxDN/w8Pzf8PD83/DA7V/yYgkf9LOS//RjQz/7Cm
pf+Ge3b/YFRP/2NXU/6qo6A5xsHAAMG9uwDBvbsAwb27AMG9uwDBvbsAwb27AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wA1NZLCAABy/wAAdv8A
AHb/AAB2/wAAdv8AAHb/AABx/ywsj/97fvD/Jirm/ysv5v8sL+b/KSzn/z5D7d+inKxRZFZO/V5S
Tv9fU0//X1NP/19ST/9fUk7/WUtH/56Tkv/Fv7z/urSw/7u0sv+7trP/u7az/7y3s/+9uLP/vriz
/764s/++uLT/v7m1/7+6t/+/urn/v7u6/7+8u//AvLv/wby7/8G8u//Cvbv/wr28/8K+vP/Dvr3/
w7++/8TAv//EwL//xMC/9NXS0TLIw8IAmpKQcGBUT/9lWVX/ZldU/2VXVP9lV1T/YVVR/3JlYv/K
xML/zMnI/8zIxv/MyMf/zMjH/83JyP/Nysj/zsrJ/8/Lyv/Py8r/0MzL/9HNzP/Rzcz/09DPLtXR
0ADV0dAA1dHQANXR0ADV0dAA1dHQANXR0ADV0dAA1dHQANXR0ADV0dAA1dHQANXR0ADV0dAA1dHQ
ANXR0ADV0dAA1dHQANXR0ADV0dAA1dHQANXR0ADV0dAA1dHQANXR0ADV0dAA1dHQANXR0ADV0dAA
1dHQANXR0ADV0dAA1dHQANXR0ADV0dAA1dHQANXR0ADV0dAA1dHQANbS0QC+ubcAqJ+fAK6npgCq
oqEAo5qZAJOJhwC4sbEAtq+tAK2nqQDFxNgAxcbeAMTF3ADFxdwAxcXcAMXF3ADFxdwAxcXcAMXF
3ADFxdwAxcXcAMXF3ADFxdwAxcXcAMXF3ADFxdwAxcXcAMXF3ADFxdwAxcXcAMXF3ADFxdwAxcXc
AMXF3ADFxdwAxcXcAMXF3ADFxdwAxcXcAMXF3ADFxdwAxcXcAMXF3ADFxdwAxcXcAMXF3ADIyN4A
urrWIhUVevYAAG7/AAFx/wABcf8AAGv/QkKa/4mL7/8ICM7/BAWR/wAAbf8AAHL/AABr/25vvP9N
T+L/BQXK/w4OzP8ODsz/Dg/M/w4QzP8OEMz/DxDN/wwO0/8zKW7/STYr/1lISP+/t7X/al9Y/19T
Tf9yaGLRwby5BcO/vQDDvrsAw767AMO+uwDDvrsAw767AMO+uwD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8ALS2OxwAAc/8BAXf/AQF2/wAAdv8A
AHb/AAB2/wAAcP87O5n/cnXy/yQo5f8rL+b/Ky/m/ykt5v8yN+zzk5HFRW1fVOReUE3/YFJP/19T
T/9fU0//X1NP/1lMSP+Uioj/xb+8/7ixrf+5s67/urSv/7q0sf+7tbL/u7az/7u2s/+8t7P/vbez
/764s/++uLT/v7i1/7+5tf+/urj/vrm5/7+6uv+/vLv/wLy7/8G8u//Bvbv/wr27/8K9vP/Cvrz/
w76+/8O/vv/JxsNQ1tPRAMS/vShoWlf5ZFdU/2VZVf9lWFX/ZldU/2RWU/9mWVX/vbW0/83Kyf/K
xsX/y8fG/8vHxv/MyMf/zMjH/8zIx//Nycj/zcnI/87Kyf/Pysn/z8vK/9LOzTPSzs0A0s7NANLO
zQDSzs0A0s7NANLOzQDSzs0A0s7NANLOzQDSzs0A0s7NANLOzQDSzs0A0s7NANLOzQDSzs0A0s7N
ANLOzQDSzs0A0s7NANLOzQDSzs0A0s7NANLOzQDSzs0A0s7NANLOzQDSzs0A0s7NANLOzQDSzs0A
0s7NANLOzQDSzs0A0s7NANLOzQDSzs0A0s7NANfU0gC8trUAmpGQAKujogCup6YAqqKhAKOamQCT
iYcAuLGxALu1tQCVi4gAjIKEALGvyQC0tdUAsrLSALKz0gCys9IAsrPSALKz0gCys9IAsrPSALKz
0gCys9IAsrPSALKz0gCys9IAsrPSALKz0gCys9IAsrPSALKz0gCys9IAsrPSALKz0gCys9IAsrPS
ALKz0gCys9IAsrPSALKz0gCys9IAsrPSALKz0gCys9IAsrPSALKz0gCystIAvr7YAG1tq4AAAGr/
AABw/wAAcP8AAHD/AABs/4KEyv9PUOL/AwPG/wMDgP8AAG//AABx/wICcf+Iitf/KivX/wkJyv8N
Dcv/DQ3L/w4OzP8ODsz/Dg7M/w0Ozv8QEcf/PzFL/0MwKf97bGv/tayp/11RS/9cUEn/koqFe9LP
zQDMyMUAzMjFAMzIxQDMyMUAzMjFAMzIxQDMyMUA////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////ACwsjcgAAHP/AQF3/wEBd/8BAXf/AQF2/wAAdv8A
AG//SEij/2hr8v8jJ+T/Ky/l/ysv5v8qLub/LDHs/5uZ0Dx3a1/LXVBM/2BTT/9gUk//YFNP/19T
T/9ZTUj/in99/8W/vP+1sKz/uLKu/7iyrf+5s67/ubOu/7q0r/+6tbD/u7Wy/7u2s/+7trP/vLez
/723s/++uLP/vriz/7+4tf+/uLb/vrq4/766uf+/u7r/v7u7/8C8u//Bvbz/wry7/8K9vP/BvLv/
y8fGetfT0QDSzs0Ag3d0w2JTUP9mWFX/ZVlV/2VZVf9lWFX/YFJO/6qhn//Py8r/yMTD/8nFxP/K
xsX/ysbF/8vHxv/Lx8b/zMjH/8zIx//Nycj/zcnI/83JyP/Szs0y08/OANPPzgDTz84A08/OANPP
zgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A08/O
ANPPzgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A
08/OANPPzgDTz84A08/OANbS0QDNycgAsquqAJqRkACspKMArqemAKqioQCjmpkAk4mHALixsQC7
tbUAloyLAIl9ewCmnZ4Aw8HTAMjJ4ADHx94AyMfeAMjH3gDIx94AyMfeAMjH3gDIx94AyMfeAMjH
3gDIx94AyMfeAMjH3gDIx94AyMfeAMjH3gDIx94AyMfeAMjH3gDIx94AyMfeAMjH3gDIx94AyMfe
AMjH3gDIx94AyMfeAMjH3gDIx94AyMfeAMjH3gDIx94AycnfAMfH3Q4qKoTiAABr/wAAcP8AAHD/
AABs/x4egv+cnuv/FxjR/wcJuv8AAXX/AABx/wAAbv8fH4P/i43o/xAQzf8MC8v/DQ3L/w0Ny/8N
Dcv/Dg7M/w4NzP8MDNL/Ghes/0c2Nv9BLiv/pJmY/5SLh/9ZTkr/YVVR9qafmye6tLEAtrCtALaw
rQC2sK0AtrCtALawrQC2sK0AtrCtAP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wAnJ4vLAAB0/wEBd/8BAXf/AQF3/wEBd/8BAXf/AABv/1NTrP9f
YvL/Iyjk/you5f8qLuX/KS7l/yYr5/+pqe1Ci4F4nltOSf9gVFD/YFRQ/2FTT/9hU0//W01J/39z
cP/Fvrv/ta+q/7exrP+3saz/t7Kt/7iyrv+4sq3/ubOt/7qzrv+6tK//u7Wx/7u1sv+7trP/u7az
/7y3s/+9t7P/vriz/764s/+/uLX/v7m1/765uP++urn/v7u6/7+7u//AvLv/wLy7/8XAv6vTz80A
0s7NAKCYlmthVFD/ZllV/2dYVf9mWFX/ZVlV/19TT/+TiYb/z8rK/8fDwv/IxML/yMTC/8jEw//J
xcT/ysbF/8rGxf/Lx8b/zMjH/8zIx//MyMf/0s7NM9PPzgDTz84A08/OANPPzgDTz84A08/OANPP
zgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A08/O
ANPPzgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A08/OANPPzgDTz84A
08/OANPQzwDU0dAAt7GwAK2lpACck5IArKSjAK6npgCqoqEAo5qZAJOJhwC4sbEAu7W1AJaMiwCK
f34AoJaUALGpqQDS0d0A0dHlANDQ4wDQ0OIA0NDiANDQ4gDQ0OIA0NDiANDQ4gDQ0OIA0NDiANDQ
4gDQ0OIA0NDiANDQ4gDQ0OIA0NDiANDQ4gDQ0OIA0NDiANDQ4gDQ0OIA0NDiANDQ4gDQ0OIA0NDi
ANDQ4gDQ0OIA0NDiANDQ4gDQ0OIA0NDiANvb6ACUlMBkAABp/wAAbf8AAG//AABw/wAAaP9jY7L/
dnfs/wEDy/8HCKf/AAFt/wAAcf8AAGv/TU6i/3J06f8EBMj/DAzK/w0Ny/8NDcv/DQ3L/w0Ny/8N
Dcv/CgvT/yghhP9INSv/Tz49/761tP9yZ2H/WExF/3hva7jFwb8Awr68AMK9uwDCvbsAwr27AMK9
uwDCvbsAwr27AMK9uwD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8AKiqMyQAAc/8BAXf/AQF3/wEBd/8BAXf/AQF3/wAAcP9dXbb/VFjw/yMn4/8q
LuX/Ki7l/you5f8lKub/fH7sXpuTjmhcTUn/YFRQ/2BUUP9gVFD/YFRQ/11PTP91aGX/wru4/7Su
qf+1r6r/trCr/7awq/+3saz/t7Gt/7eyrf+4sq3/uLKt/7mzrv+6tK//urSv/7u1sf+7tbL/uraz
/7u3s/+8t7P/vbiz/764s/++uLP/v7i0/7+5tv+/ubj/vrq5/766uv/Bvbva09DOC8XAvwC0rKsd
bGBc8mRYVP9mWlb/Z1lV/2dYVf9iVVH/fHFu/8nEw//Gw8L/x8LB/8fDwv/Hw8L/yMTD/8jEw//J
xcT/ycXE/8rGxf/Lx8b/y8fG/9HOzTPSz84A0s/OANLPzgDSz84A0s/OANLPzgDSz84A0s/OANLP
zgDSz84A0s/OANLPzgDSz84A0s/OANLPzgDSz84A0s/OANLPzgDSz84A0s/OANLPzgDSz84A0s/O
ANLPzgDSz84A0s/OANLPzgDSz84A0s/OANLPzgDSz84A0s/OANLPzgDSz84A0s/OANPPzgDW09IA
n5aVAK6npgCvqKcAnJOSAKykowCup6YAqqKhAKOamQCTiYcAuLGxALu1tQCWjIsAin9+AKGYlwCr
oqEAsqqqAKypvACmp80ApqbKAKamygCmpsoApqbKAKamygCmpsoApqbKAKamygCmpsoApqbKAKam
ygCmpsoApqbKAKamygCmpsoApqbKAKamygCmpsoApqbKAKamygCmpsoApqbKAKamygCmpsoApqbK
AKamygCmpsoApqbKAKanygCsrM4FMTKI0wAAaP8AAG3/AABt/wAAbP8KCnP/mpvh/zAy1/8EB8v/
BAWR/wAAbP8AAXH/AABs/3t8xv9HSN//BAXI/wwMyv8MDMr/DAzK/wwMyv8NDcv/DQ3M/wwNzf84
LFr/Qi8n/3NlZP+6sq//WUtD/1VHPv+inJhY19XUANDOzADRzswA0c7MANHOzADRzswA0c7MANHO
zADRzswA////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////ACwsjcgAAHP/AQF3/wEBd/8BAXf/AQF3/wEBd/8AAHD/ZGS9/01Q7/8kKOP/KS3k/ykt5P8p
LeT/ICTk/4SG9H+wqqY0XlFM/2FTUP9iU1D/YVNQ/2BUUP9eUk7/al5b/722sv+0rqn/s62o/7Su
qf+0rqn/ta+q/7awq/+2sKv/t7Gs/7exrf+3sq3/uLKt/7iyrv+5s67/urSv/7q0r/+7tbH/u7Wy
/7u2s/+7trT/vbez/724s/++uLP/vri0/764tP+/ubb/vri399HOzS7U0dAAzsrJAIyBfqtiU1D/
Z1pW/2ZaVv9mWlb/ZVdU/2xeW/+9trT/xsPC/8XBwP/FwcD/xsLB/8bCwf/Hw8L/x8PC/8fDwv/I
xMP/ycXD/8nFxP/QzMs00c3MANHNzADRzcwA0c3MANHNzADRzcwA0c3MANHNzADRzcwA0c3MANHN
zADRzcwA0c3MANHNzADRzcwA0c3MANHNzADRzcwA0c3MANHNzADRzcwA0c3MANHNzADRzcwA0c3M
ANHNzADRzcwA0c3MANHNzADRzcwA0c3MANHNzADRzcwA0c3MANHNzADRzswAwby7AJCFhACup6cA
r6inAJyTkgCspKMArqemAKqioQCjmpkAk4mHALixsQC7tbUAloyLAIp/fgChmJcArKOjAK+oqACu
pqMArKm+AKamzACmpsoApqbKAKamygCmpsoApqbKAKamygCmpsoApqbKAKamygCmpsoApqbKAKam
ygCmpsoApqbKAKamygCmpsoApqbKAKamygCmpsoApqbKAKamygCmpsoApqbKAKamygCmpsoApqbK
AKamygCtrc4Ah4e4VQMDbf8AAGz/AAFt/wAAbf8AAGX/SUqe/42P8P8FBsj/CQvF/wECfP8AAG7/
AABv/w0Od/+UleP/Gx3Q/wcJyP8LDMn/CgvJ/woLyP8KCsj/CQrI/wcIzP8TErX/RDM5/z8sKP+h
lpXNmZCLv2dcVsGIf3mYtbGtC7u3tAC6tbIAurWyALq1sgC6tbIAurWyALq1sgC6tbIAurWyAP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wAxMZHE
AABz/wEBd/8BAXf/AQF3/wEBd/8BAXf/AABx/2hpw/9FSO3/JCji/ykt5P8pLeT/KS3k/yIm4/9h
ZO+pu7fFEG1hWepeU07/YVVR/2JUUP9iU1D/YFNP/2JWUv+zq6n/ta+r/7Ksp/+zraj/s62o/7Su
qf+0rqn/tK6p/7Wvqv+2sKv/trCs/7exrP+3sa3/t7Gu/7iyrv+4sq7/ubOu/7q0r/+6tK//u7Sx
/7u1sv+7trP/vLez/7y3s/++uLP/vriz/722sv/KxcJm29fVANbS0QCzratEZVhU/mdZVv9oWVb/
Z1pW/2ZaVv9iVVH/p56c/8jFw//Dv77/xMC//8TAv//FwcD/xcHA/8bCwf/Hw8L/x8PC/8fDwv/I
xMP/zcrJNc7LygDOy8oAzsvKAM7LygDOy8oAzsvKAM7LygDOy8oAzsvKAM7LygDOy8oAzsvKAM7L
ygDOy8oAzsvKAM7LygDOy8oAzsvKAM7LygDOy8oAzsvKAM7LygDOy8oAzsvKAM7LygDOy8oAzsvK
AM7LygDOy8oAzsvKAM7LygDOy8oAzsvKAM7KygDSz84AubSzAJmRjwCWjIsArqenAK+opwCck5IA
rKSjAK6npgCqoqEAo5qZAJOJhwC4sbEAu7W1AJaMiwCKf34AoZiXAKyjowCwqakAr6elAJeQkwCt
rMkAtLXTALS00QC0tNEAtLTRALS00QC0tNEAtLTRALS00QC0tNEAtLTRALS00QC0tNEAtLTRALS0
0QC0tNEAtLTRALS00QC0tNEAtLTRALS00QC0tNEAtLTRALS00QC0tNEAtLTRALS00QC0tNIAurrV
ATc3is4AAGj/AAFt/wABbf8AAGz/AgJq/5KT1v9ERdv/AADG/wcIsf8AAG//AABv/wAAav87PJX/
hIXr/wQFx/8KDMn/DQ/L/xASzv8UFtL/GBrW/x0f2v8hJOf/MSyX/0UyKP9MOzn/zcbEL4h+egCP
iIQAysfEALmzrwC0r6sAtK+rALSvqwC0r6sAtK+rALSvqwC0r6sAtK+rALSvqwD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8AOTiVwAAAc/8AAHf/
AQF3/wEBd/8BAXf/AQF3/wAAcv9rbMf/P0Ps/yQp4v8oLOP/KCzj/ygs4/8jJ+P/TlLsx8nH2QB/
c22/XVBM/2FVUf9hVVH/YVVR/2FUUP9fUU7/qJ6c/7awrP+wqqX/saum/7Ksp/+yrKf/s62o/7Ot
qP+zraj/tK6p/7Wvqv+1r6v/trCr/7awq/+3saz/t7Gt/7eyrf+4sq7/uLKu/7mzrv+6tK//urSv
/7u0sf+7tbP/u7az/7y2s/+7trH/xL+7pdrX1QDKxsQAu7a0BHpwbMtjV1P/Z1tX/2hZVv9oWVb/
YVRQ/4qAfP/JxMP/wr27/8K9vP/Cvr3/w7++/8PAvv/EwL//xcHA/8bBwP/GwsH/x8PC/8rGxTfK
xsUAysbFAMrGxQDKxsUAysbFAMrGxQDKxsUAysbFAMrGxQDKxsUAysbFAMrGxQDKxsUAysbFAMrG
xQDKxsUAysbFAMrGxQDKxsUAysbFAMrGxQDKxsUAysbFAMrGxQDKxsUAysbFAMrGxQDKxsUAysbF
AMrGxQDKxsUAysbFAMrGxQDLx8YAysbFALKrqgCZkI4AloyLAK6npwCvqKcAnJOSAKykowCup6YA
qqKhAKOamQCTiYcAuLGxALu1tQCWjIsAin9+AKGYlwCso6MAsKmpALCpqACPhYEAoZ60AK2t0ACr
q8wAq6vMAKurzACrq8wAq6vMAKurzACrq8wAq6vMAKurzACrq8wAq6vMAKurzACrq8wAq6vMAKur
zACrq8wAq6vMAKurzACrq8wAq6vMAKurzACrq8wAq6vMAKurzACrq8wAs7PRAIqKuVQDAmz/AABr
/wABbP8AAW3/AABn/zc4kf+fofb/ISXe/yAj4/8OEKL/AABq/wAAcP8AAGn/cXK9/29y+P8tMe7/
OTzz/zxA9/8/Q/r/Qkb8/0RI/v9GSv//R0z//0Y7av8+KyH/cmRj3uvl5A6/trUAjoeCAMO/vAC4
s68AtbCsALWwrAC1sKwAtbCsALWwrAC1sKwAtbCsALWwrAC1sKwA////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AENDm7sAAHL/AAB4/wAAeP8AAHf/
AQF3/wAAd/8AAHP/bW7J/zs/6/8kKOL/Jyvi/ygs4/8oLOP/JCjj/z5C6ujBwOgFl42Ge11OS/9j
VFH/YlVR/2FVUf9hVVH/XE9L/5mPjf+5s67/rqik/7Cppf+wqqX/saum/7Grpv+yrKf/sqyn/7Ot
qP+zraj/s62p/7Suqf+1r6n/ta+r/7awq/+2sKv/t7Gs/7exrf+3sa3/uLKt/7iyrv+5s67/urSv
/7u0sP+7tbL/urWy/724ttrSz80M1dLQANvY1wCtpaNjY1RR/2haV/9nW1f/Z1pX/2ZXU/90ZmL/
vrm3/8K+vf/BvLv/wr27/8O9u//Cvb3/wr69/8O/vv/EwL//xMC//8TAv//Lx8Y1z8vKAM7LygDO
y8oAzsvKAM7LygDOy8oAzsvKAM7LygDOy8oAzsvKAM7LygDOy8oAzsvKAM7LygDOy8oAzsvKAM7L
ygDOy8oAzsvKAM7LygDOy8oAzsvKAM7LygDOy8oAzsvKAM7LygDOy8oAzsvKAM7LygDOy8oAzsvK
AM7LygDPzMsAy8fGAKaenQCxq6kAmZGPAJaMiwCup6cAr6inAJyTkgCspKMArqemAKqioQCjmpkA
k4mHALixsQC7tbUAloyLAIp/fgChmJcArKOjALCpqQCwqagAkIaCAI2HmAChocoAoKDGAKCgxgCg
oMYAoKDGAKCgxgCgoMYAoKDGAKCgxgCgoMYAoKDGAKCgxgCgoMYAoKDGAKCgxgCgoMYAoKDGAKCg
xgCgoMYAoKDGAKCgxgCgoMYAoKDGAKCgxgCgoMYAoKDHAKamygU0NIjQAABn/wAAbP8AAGz/AABr
/wAAaP+Ki87/dXn//z1C//9DSPz/DhCL/wAAaP8AAG7/Cwt1/5mb5f9VWf//Q0f//0VJ//9FSf//
RUn//0VJ//9FSf//REn//0RG3P9ENDf/Pisn/6mdnG/u6OcA6ODgAK2mowC+urcAuLOvALWwrAC1
sKwAtbCsALWwrAC1sKwAtbCsALWwrAC1sKwAtbCsAP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wBPUKKlAABy/wAAeP8AAHj/AAB4/wAAeP8AAHj/
AAB0/21vy/84POn/JCji/ycr4v8nK+L/Jyvi/yYq4/8rL+b8oKHpJqKakzdgVE//YlVR/2NVUf9j
VFH/YlRR/1xPS/+IfXr/urSw/6ymof+uqKP/r6ik/7Cppf+xqqX/sKqm/7Grpv+xrKb/sqyn/7Os
p/+zraj/s62o/7OtqP+0rqn/ta+q/7Wvqv+2sKv/trCs/7exrP+3sa3/uLKt/7iyrf+5s67/urOu
/7q0r/+6s6/7ysXBMdLPzADU0M8Az8rJDHltathlVlP/aVpX/2hbV/9nW1f/ZVhU/6mhoP/Dv77/
v7u7/8C8u//Bvbv/wr28/8K8vP/Cvbz/wr29/8O+vv/Bvbz/0c7NYeDe3QDe3NsA3tzbAN7c2wDe
3NsA3tzbAN7c2wDe3NsA3tzbAN7c2wDe3NsA3tzbAN7c2wDe3NsA3tzbAN7c2wDe3NsA3tzbAN7c
2wDe3NsA3tzbAN7c2wDe3NsA3tzbAN7c2wDe3NsA3tzbAN7c2wDe3NsA3tzbAN7c2wDf3dsA4d/d
AMrGxACimpkAsquqAJmRjwCWjIsArqenAK+opwCck5IArKSjAK6npgCqoqEAo5qZAJOJhwC4sbEA
u7W1AJaMiwCKf34AoZiXAKyjowCwqakAsKmoAI+FggCKgYIAx8fcAMfH3QDHx90Ax8fdAMfH3QDH
x90Ax8fdAMfH3QDHx90Ax8fdAMfH3QDHx90Ax8fdAMfH3QDHx90Ax8fdAMfH3QDHx90Ax8fdAMfH
3QDHx90Ax8fdAMfH3QDHx90AxsbdANHR4wCGhrdhAABn/wAAa/8AAGz/AABs/wAAZv8uL4n/qKr6
/0VJ/f9CRv//NDje/wEBbP8AAGz/AABn/zw7lP+anP7/P0P9/0NH/f9DR/3/Q0f9/0NH/f9DR/3/
Q0f9/0RJ//9DPZr/QS0h/1NDQfTZ0M8a6OHgAOfg3wDX0M8Awb25ALWwrACzrqoAs66qALOuqgCz
rqoAs66qALOuqgCzrqoAs66qALOuqgD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8AODiWjAAAeP8AAHr/AAB5/wAAeP8AAHj/AAB4/wAAdP9sbcv/
Nzrp/yQo4f8mKuH/Jyvi/ycr4v8nK+L/Iyfi/5KT71S5tLwGb2Re4WBTT/9iVlL/Y1VS/2NVUf9f
UE3/eGto/7ixrv+spaH/rKei/62nov+uqKP/rqij/6+opP+vqaT/sKql/7Cqpf+xq6b/saum/7Ks
p/+zraj/s62o/7OtqP+0rqn/tK6p/7Wvqv+1r6r/trCr/7exrP+3sa3/t7Kt/7iyrf+4sq7/t7Gs
/8S/u3vX1NEA1tLRAN/c2wCpoqBpYlVR/2lbWP9pWlf/aFtX/2JVUf+KgH3/xcC8/765t/+/urn/
v7u6/7+7u//AvLv/wLy7/8K8vP/CvLz/wby7/8vHxYrU0c8A09DOANPQzgDT0M4A09DOANPQzgDT
0M4A09DOANPQzgDT0M4A09DOANPQzgDT0M4A09DOANPQzgDT0M4A09DOANPQzgDT0M4A09DOANPQ
zgDT0M4A09DOANPQzgDT0M4A09DOANPQzgDT0M4A09DOANPQzgDT0M4A19TSAKylowCUiokAqqKh
ALKrqgCZkY8AloyLAK6npwCvqKcAnJOSAKykowCup6YAqqKhAKOamQCTiYcAuLGxALu1tQCWjIsA
in9+AKGYlwCso6MAsKmpALCpqACPhYMAjIKBAMDA1ADCwdoAwcHZAMHB2QDBwdkAwcHZAMHB2QDB
wdkAwcHZAMHB2QDBwdkAwcHZAMHB2QDBwdkAwcHZAMHB2QDBwdkAwcHZAMHB2QDBwdkAwcHZAMHB
2QDBwdkAwcHZAMPD2gDExNsOLi6D3wAAZ/8AAGz/AABr/wAAa/8AAGj/iYrN/3l8//85Pfr/REn/
/x8isf8AAGX/AABt/wAAZv96esP/dnr//zs/+/9CRvz/Q0f9/0NH/f9DR/3/Q0f9/0NH/v9DR/b/
QzZV/zsoIf+Henm36+XkAOTd3QDk3d0A5+DgANbQzgC9uLQAvbi1AL24tQC9uLUAvbi1AL24tQC9
uLUAvbi1AL24tQC9uLUA////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AEpKn34AAHj/AAF7/wABe/8AAHr/AAB5/wAAeP8AAHX/aWrL/zQ46P8kKOH/
Jirh/yYq4f8mKuH/Jirh/yEl4f9dYOyNxMLaAI6De6deT0v/Y1ZS/2JWUv9iVlL/YFRQ/2hcWP+z
qqf/rqai/62lof+spaH/rKai/6ynov+tp6L/raei/66oo/+vqKT/r6ml/7Cppf+wqqb/saum/7Ks
p/+yrKf/sqyn/7OtqP+0rqn/tK6p/7Wvqv+1r6r/ta+q/7awq/+2sKz/t7Gt/7awrP+7trHH19PR
AtbT0QDT0M8A0c3MDHtvbNRlWFT/aFxY/2lbV/9nWFX/cGNg/7mzr//AubX/v7m0/764tf++ubf/
vrq4/767uv+/vLv/wLy7/8C8u//FwL6Mx8PAAMfCwADHwsAAx8LAAMfCwADHwsAAx8LAAMfCwADH
wsAAx8LAAMfCwADHwsAAx8LAAMfCwADHwsAAx8LAAMfCwADHwsAAx8LAAMfCwADHwsAAx8LAAMfC
wADHwsAAx8LAAMfCwADHwsAAx8LAAMfCwADGwsAAycTCANDNzACOg4IAkIaFAKujogCyq6oAmZGP
AJaMiwCup6cAr6inAJyTkgCspKMArqemAKqioQCjmpkAk4mHALixsQC7tbUAloyLAIp/fgChmJcA
rKOjALCpqQCwqagAkIaEAIV7eACvq7gAwMHbAL6+1wC+vtcAvr7XAL6+1wC+vtcAvr7XAL6+1wC+
vtcAvr7XAL6+1wC+vtcAvr7XAL6+1wC+vtcAvr7XAL6+1wC+vtcAvr7XAL6+1wC+vtcAvr7XAL6+
1wDIyNwAcHCpfgAAY/8AAGn/AABr/wAAbP8AAGX/MjOM/6ut+/9ESPz/P0P8/z5C9f8LDIX/AABp
/wAAav8VFXn/n6Du/01S/v8/Q/z/Qkb8/0JG/P9CRvz/Qkb8/0NH/P9DSP//QkHC/0EvKv9EMi/4
w7q5Ruzl5QDl3t4A5d/eAObf3gDm398A5t/eAObf3gDm394A5t/eAObf3gDm394A5t/eAObf3gDm
394A5t/eAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wBrbLBwAAB3/wABe/8AAXv/AAF7/wABe/8AAHr/AAB2/2lqyv81Oej/Iyfg/yYq4f8mKuH/
Jirh/yYq4f8fI+D/VFjqvcbF7wCzrKVYXlBN/2RVUv9jVVL/Y1VS/2JWUv9fU0//pZyZ/7GopP+s
o5//raSg/62koP+tpaH/rKah/6ymov+sp6L/raei/62nov+uqKP/r6ik/6+ppP+wqqX/sKql/7Gr
pv+xrKf/sqyn/7OtqP+zraj/s62o/7Suqf+0rqn/ta+q/7avq/+2sKv/trCq+tDMyi3c2tgAzsrJ
AMbBwACelZJXZlZT/2lbWP9oXFj/aFxY/2RXU/+dlJH/wby4/724s/++uLP/vriz/765tP+/ubb/
vrq3/766uf++urn/w7++jc7LyQDOy8kAzsvJAM7LyQDOy8kAzsvJAM7LyQDOy8kAzsvJAM7LyQDO
y8kAzsvJAM7LyQDOy8kAzsvJAM7LyQDOy8kAzsvJAM7LyQDOy8kAzsvJAM7LyQDOy8kAzsvJAM7L
yQDOy8kAzsvJAM7LyQDOy8kA0c7NAL65uAC2sK8AlIqJAJGHhgCro6IAsquqAJmRjwCWjIsArqen
AK+opwCck5IArKSjAK6npgCqoqEAo5qZAJOJhwC4sbEAu7W1AJaMiwCKf34AoZiXAKyjowCwqakA
sKmoAJCGhACFengAuLS5AMrK4QDGxtwAxsbcAMbG3ADGxtwAxsbcAMbG3ADGxtwAxsbcAMbG3ADG
xtwAxsbcAMbG3ADGxtwAxsbcAMbG3ADGxtwAxsbcAMbG3ADGxtwAxsbcAMbG3ADLy98Au7vVIxgY
dfIAAGX/AABp/wAAaf8AAGr/AQJp/4+R0v92ev//OD35/0JH//8uMtP/AABp/wABbP8AAGX/UlOi
/5KV//86Pvv/QUX7/0FF+/9BRfv/Qkb8/0JG/P9CRv3/Qkf//0E4c/87KB3/bV5dxOLb2gDh2dgA
4NjXAODY1wDg2NcA4NjXAODY2ADg2NgA4NjYAODY2ADg2NgA4NjYAODY2ADg2NgA4NjYAODY2AD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8AkJDE
YQAAeP8AAHv/AAF7/wABe/8AAXv/AAB7/wAAdv9maMj/Njro/yIn4P8lKeD/JSng/yUp4P8lKeD/
ISXg/z1B5ua6u/AMubOyEWhdWOlhVVH/ZFZT/2RVUv9kVVL/XlBN/5KHhP+yq6f/qKGd/6qinv+r
o5//rKOf/62koP+tpKD/raWh/62mof+spqH/raei/62nov+tp6L/rqij/6+ppP+wqaX/sKql/7Gr
pv+xq6b/sqyn/7Ksp/+zraj/s62o/7OtqP+0rqn/ta+q/7OtqP/Bvbl71tPRAM3JxwC8tbQAwLq5
A4J3db9lV1P/altY/2lbWP9lWFT/fHFu/723tf+7trP/u7az/7y3s/+9uLP/vriz/7+4tP+/ubX/
vri0/8O+vMPX1NIC19PSANfT0gDX09IA19PSANfT0gDX09IA19PSANfT0gDX09IA19PSANfT0gDX
09IA19PSANfT0gDX09IA19PSANfT0gDX09IA19PSANfT0gDX09IA19PSANfT0gDX09IA19PSANfT
0gDX09IA19TSANnX1gCflpUAqKCfAJaMjACRh4YAq6OiALKrqgCZkY8AloyLAK6npwCvqKcAnJOS
AKykowCup6YAqqKhAKOamQCTiYcAuLGxALu1tQCWjIsAin9+AKGYlwCso6MAsKmpALCpqACQhoQA
hnx5ALCqrADKydwAzMziAMzM4ADMzOAAzMzgAMzM4ADMzOAAzMzgAMzM4ADMzOAAzMzgAMzM4ADM
zOAAzMzgAMzM4ADMzOAAzMzgAMzM4ADMzOAAzMzgAMzM4ADMzOEA1dXlAFJSl6sAAGH/AABo/wAA
af8AAGn/AABh/0FClv+prP7/QET6/z5C+f9BRv7/Fxmg/wAAZP8AAGv/AgJq/5KS2P9laf//Oz/6
/0BE+v9BRfv/QUX7/0FF+/9BRfv/QUb//0FC2/9BMDb/PSom/62jonvr5OMA4traAOLb2gDi29oA
4tvaAOLb2gDi29oA4tvaAOLb2gDi29oA4tvaAOLb2gDi29oA4tvaAOLb2gDi29oA////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AIyMwjsCAnz/AAB7
/wABe/8AAXv/AAF7/wABe/8AAHb/YmPE/zc76P8hJd7/JCjf/yQo3/8lKeD/JSng/yMo4P8mK+H/
pKXxOs3JywCKgHupXlBN/2NXU/9jV1P/Y1dT/2BRTv9+cW7/s6uo/6ifm/+poZ3/qaKd/6minv+q
op7/q6Ke/6yjn/+tpKD/raSg/62lof+tpqH/rKai/62nov+tp6L/raei/66oo/+vqaT/sKml/7Cq
pf+wqqX/saum/7Ksp/+yrKf/sqyn/7OtqP+zraj/trCry83JxwLRzcsA0M3MANLQzgC0rqw3Z1tX
+GhbV/9qXFj/aVtX/2haVv+nn5v/vri0/7q1sf+7tbL/u7az/7y2s/+8t7P/vriz/764s/+/urXd
xcC8B8bBvQDGwL0AxsC9AMbAvQDGwL0AxsC9AMbAvQDGwL0AxsC9AMbAvQDGwL0AxsC9AMbAvQDG
wL0AxsC9AMbAvQDGwL0AxsC9AMbAvQDGwL0AxsC9AMbAvQDGwL0AxsC9AMbAvQDGwL0AxsG8AMjD
vwDFwL4AiX99AKukowCWjIwAkYeGAKujogCyq6oAmZGPAJaMiwCup6cAr6inAJyTkgCspKMArqem
AKqioQCjmpkAk4mHALixsQC7tbUAloyLAIp/fgChmJcArKOjALCpqQCwqagAkIaEAIZ8egCvqKgA
19bkANvc6wDa2ukA2trpANra6QDa2ukA2trpANra6QDa2ukA2trpANra6QDa2ukA2trpANra6QDa
2ukA2trpANra6QDa2ukA2trpANra6QDa2ukA5OTvAKOjyEwGBmj/AABm/wAAaP8AAGj/AABm/wgI
bP+en97/bHD//zc7+P9ARPz/Nzvo/wUFdf8AAGn/AABn/zExi/+ho/r/QUX7/z9D+v9ARPr/QET6
/0BE+v9ARPr/QUX7/0FG//9AOo3/Oygd/11NTPXg2dgl6ODgAOXe3gDl3t4A5d7eAOXe3gDl3t4A
5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wB9fLcqDQ2C+wAAe/8AAHz/AAB8
/wABe/8AAXv/AAB1/15fv/87Puj/ISXe/yQo3/8kKN//JCjf/yQo3/8kKN//HyPf/3Bz7njAv+MA
r6egTGFST/9kVlP/ZFdT/2NXU/9hVVH/a19c/62kof+on5v/qZ+c/6mgnP+poZz/qKGd/6minf+p
op3/qqKe/6uin/+to5//raSg/62koP+tpaH/raah/6ymof+sp6L/raei/66oo/+vqKP/r6mk/7Cp
pf+wqaX/sKql/7Grpv+yrKf/sqyn/7Gqpf3Lx8RC2tjWANXR0ADJxMMAzcnHAJaMio9kVlL/al1Z
/2pdWf9lV1T/g3h1/7u2sf+5s67/urSv/7q0sP+6tLD/urWy/7u2s/+7trP/vLez6NLOzBvX1NEA
1tPRANbT0QDW09EA1tPRANbT0QDW09EA1tPRANbT0QDW09EA1tPRANbT0QDW09EA1tPRANbT0QDW
09EA1tPRANbT0QDW09EA1tPRANbT0QDW09EA1tPRANbT0QDW09EA1tPQANjV0gDb2NcAysXFAIuA
fwCrpKMAloyMAJGHhgCro6IAsquqAJmRjwCWjIsArqenAK+opwCck5IArKSjAK6npgCqoqEAo5qZ
AJOJhwC4sbEAu7W1AJaMiwCKf34AoZiXAKyjowCwqakAsKmoAJCGhACHfXsAqJ+fAMTBygDk5PEA
4ODrAODg6wDg4OsA4ODrAODg6wDg4OsA4ODrAODg6wDg4OsA4ODrAODg6wDg4OsA4ODrAODg6wDg
4OsA4ODrAODg6wDg4OsA4+PuANra6A4uLoHdAABh/wAAaP8AAGj/AABo/wAAX/9cXaj/oqT//zo+
+P89Qfj/QUb//yEkt/8AAGT/AABr/wAAZf98fcP/e37//zg8+f8/Q/n/P0P5/z9D+f9ARPr/QET6
/0BE/v9AQuj/QDFA/zkmIP+ekpGZ7+joAOXe3QDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A
5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8AwMDcEBgYh+QAAHn/AAB8/wAAfP8AAHz/AAB8
/wAAdf9XWLn/P0Lo/x8j3f8jJ97/Iyfe/yQo3/8kKN//JCjf/x0h3v9NUOe2rKzmAMzGwwpzaGTd
YVRQ/2VWU/9lVlP/ZFZT/2BTT/+elZL/q6Of/6admf+nnpr/qJ+b/6ifnP+poJz/qaGd/6ihnf+o
op3/qaKe/6qinv+so5//rKOf/62koP+tpKD/rKWh/62mof+sp6L/raei/62nov+uqKL/r6ij/6+p
pP+wqaX/sKql/7Grpv+wqqT/ubSwnNLOzADSz8wA1tPRANzY1gDRzcsPem1q1WZXVP9rXVn/aVxY
/2ldWf+ooJ3/u7Wx/7iyrf+4s63/ubOu/7q0r/+6tK//urSx/7q0sf/KxsRA0tDOANHOzADRzswA
0c7MANHOzADRzswA0c7MANHOzADRzswA0c7MANHOzADRzswA0c7MANHOzADRzswA0c7MANHOzADR
zswA0c7MANHOzADRzswA0c7MANHOzADRzswA0c7MANPRzwDDv7wAsKmoAM7KyQCLgH8Aq6SjAJaM
jACRh4YAq6OiALKrqgCZkY8AloyLAK6npwCvqKcAnJOSAKykowCup6YAqqKhAKOamQCTiYcAuLGx
ALu1tQCWjIsAin9+AKGYlwCso6MAsKmpALCpqACQhoQAiH18AKWcmgCpoqgA0tPmAM3N4ADNzeAA
zc3gAM3N4ADNzeAAzc3gAM3N4ADNzeAAzc3gAM3N4ADNzeAAzc3gAM3N4ADNzeAAzc3gAM3N4ADN
zeAAzc3gANjZ5wBxcqmRAABg/wEAZ/8BAGf/AABo/wAAY/8ZGnj/rq/v/1pe+/84PPf/PkL5/zxA
9P8KC4P/AABn/wAAaP8bG3v/pqjz/0pO+/88QPj/P0P5/z9D+f8/Q/n/P0P5/z9D+v9ARf//Pzqa
/zwoHv9UQ0Lt2tLRN+nh4QDl3t0A5d7dAOXe3QDl3t0A5d7dAOXe3QDl3t0A5d7dAOXe3QDl3t0A
5d7dAOXe3QDl3t0A5d7dAOXe3QDl3t0A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AIaHvwAmJo7IAAB5/wAAfP8AAHz/AAB8/wAAfP8AAHb/T0+y
/0RH6f8eIt3/Iyfe/yMn3v8jJ97/Iyfe/yMn3v8gJN7/OTzj6q+v9RPGw88AkYiCg15STv9kWFT/
ZFdU/2VWU/9gUU7/iH16/62lof+km5f/pZyY/6admf+mnZn/p56a/6ifm/+on5v/qaCc/6mhnf+p
oZ3/qKKd/6minf+qop7/rKOf/6yjn/+tpKD/rKWg/62lof+spqH/raei/62nov+tp6L/rqej/6+o
pP+vqaT/sKmk/6+ppPDSz8wk4N7cAN3b2gDe29oA4+HgALmzsUJqXVn8aVtY/2tcWf9mWFX/hHh1
/7mzr/+3saz/t7Gs/7eyrf+4sq7/uLKu/7mzrv+4sq3/ysXBcdnW1QDX1NIA19TSANfU0gDX1NIA
19TSANfU0gDX1NIA19TSANfU0gDX1NIA19TSANfU0gDX1NIA19TSANfU0gDX1NIA19TSANfU0gDX
1NIA19TSANfU0gDX1NIA19TSANfU0gDb2dcAqaGgAKCXlgDQy8sAi4B/AKukowCWjIwAkYeGAKuj
ogCyq6oAmZGPAJaMiwCup6cAr6inAJyTkgCspKMArqemAKqioQCjmpkAk4mHALixsQC7tbUAloyL
AIp/fgChmJcArKOjALCpqQCwqagAkIaEAIh9fACmnpwAoJmeAMHB2wC9vtYAvb7WAL2+1gC9vtYA
vb7WAL2+1gC9vtYAvb7WAL2+1gC9vtYAvb7WAL2+1gC9vtYAvb7WAL2+1gC9vtYAvb7WAMXF2wCZ
msFBCAhp/gAAZf8BAGf/AQBn/wAAZv8AAGH/goPF/42Q//81Ofb/PED2/0BE/v8oK8f/AABl/wAA
af8AAGT/aWmz/4uO//83PPj/PkL4/z5C+P8+Qvj/PkL4/z9D+f8/Q/3/PkLt/z8xRv83JB3/lYmI
pO7o6ADm3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A
5d7eAOXe3gDl3t4A5d7eAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wDBv9sARESepwAAd/8AAHz/AAB8/wABe/8AAHz/AAB2/0ZHqf9KTej/HCDc
/yIm3f8iJt3/Iibd/yMn3v8jJ97/Iibe/yEm3v+anfNOycjhAL64syhpXFn0Y1ZS/2RYVP9kWFT/
YlVR/3JmY/+ro5//o5uX/6Sbl/+knJj/pZyY/6WcmP+lnZn/pp2Z/6efm/+on5v/qZ+c/6mgnP+p
oZ3/qKKd/6minf+pop3/qqKe/6yjnv+so5//raSg/62lof+tpaH/raai/6ynof+tp6L/raei/66o
o/+spqH/vLe0gtDNywDNysgA1dLRAN3b2gDh394AmJCNgmRXU/9qXVn/alxY/2pcWP+imZf/ubOv
/7avq/+2saz/t7Gt/7eyrf+4sa7/t7Cs/7+5tZ/T0M0A0s/MANLPzADSz8wA0s/MANLPzADSz8wA
0s/MANLPzADSz8wA0s/MANLPzADSz8wA0s/MANLPzADSz8wA0s/MANLPzADSz8wA0s/MANLPzADS
z8wA0s/MANLPzADU0M0Awr27AJWMiwCkm5oA0MvLAIuAfwCrpKMAloyMAJGHhgCro6IAsquqAJmR
jwCWjIsArqenAK+opwCck5IArKSjAK6npgCqoqEAo5qZAJOJhwC4sbEAu7W1AJaMiwCKf34AoZiX
AKyjowCwqakAsKmoAJCGhACIfXwAqKCfAJaNjgCvrskAsrLRALGxzwCxsc8AsbHPALGxzwCxsc8A
sbHPALGxzwCxsc8AsbHPALGxzwCxsc8AsbHPALGxzwCxsc8AsbHPALS00QCwsM8RLS2A2AAAYv8B
AGf/AQBn/wEAZ/8AAF//PT6S/7Gz/f9FSvj/OT32/z1B9/89Qfj/DxCM/wAAY/8AAGb/ERFz/6Wn
6/9TV/z/OT33/z5C9/8+Qvj/PkL4/z5C+P8+Qvj/PkP//z45nv87KB3/UT8+/NfPzkrp4uIA5d7d
AOXe3QDl3t0A5d7dAOXe3QDl3t0A5d7dAOXe3QDl3t0A5d7dAOXe3QDl3t0A5d7dAOXe3QDl3t0A
5d7dAOXe3QD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8AfXu6AEZFnn4AAHj/AAB8/wAAfP8AAHz/AAB8/wAAdv87O5//UFPo/xwg3P8iJt3/Iibd
/yIm3f8iJt3/Iibd/yMn3v8bH93/Y2Xpl7Gx7ADEwL8AgnZ0qGFRTv9lWFT/ZVhU/2RYU/9kWFT/
npSR/6SdmP+impb/o5uX/6Obl/+km5f/pJuX/6ScmP+lnZn/pZ2Z/6eemv+nnpr/qJ+b/6mgnP+p
oJz/qKGd/6mhnf+oop3/qaKe/6qjn/+so5//raOf/62koP+tpaH/raah/6ymof+tp6L/rKah/66o
o9nIw8ESzsrIAM3KyADW0tEA19TTANHMywaFena5ZVdT/2teWv9nWVb/fHBt/7Suqf+1r6r/ta+q
/7Wvq/+2sKv/t7Gs/7awrP+6tLHU09DNB9XSzwDU0s8A1NLPANTSzwDU0s8A1NLPANTSzwDU0s8A
1NLPANTSzwDU0s8A1NLPANTSzwDU0s8A1NLPANTSzwDU0s8A1NLPANTSzwDU0s8A1NLPANTSzwDV
0s8A1tPRAMK9vACXjowApJuaANDLywCLgH8Aq6SjAJaMjACRh4YAq6OiALKrqgCZkY8AloyLAK6n
pwCvqKcAnJOSAKykowCup6YAqqKhAKOamQCTiYcAuLGxALu1tQCWjIsAin9+AKGYlwCso6MAsKmp
ALCpqACQhoQAiH18AKegnwCVi4oAubbGALq61gC5udMAubnTALm50wC5udMAubnTALm50wC5udMA
ubnTALm50wC5udMAubnTALm50wC5udMAubnTALy81AC/v9cAUlKVnAAAYP8AAGb/AQBn/wEAZ/8A
AGP/Dg5u/6ip5P9scP3/NDj1/zs/9f8+Q/z/LC/R/wEBZv8AAGf/AABh/1xdqf+Wmf//Nzv3/zxA
9/89Qff/PUH3/z5C+P8+Qvj/PkP8/z1A6v8+MEb/NiMc/5SJh9ju5+cC5d7eAOXe3gDl3t4A5d7e
AOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AMfH
4QCLi8JYAAB4/wAAfP8AAHz/AAB8/wAAfP8AAHf/LS6W/1da5v8bH9z/ISXc/yIm3f8iJt3/Iibd
/yIm3f8iJt3/HSHc/z0/4t+kpfEKvrrJALGppUFkV1P9ZVdU/2ZXVP9mV1T/YFJO/4d8eP+ooJz/
oJeT/6KZlf+imZX/o5qW/6Oalv+jm5f/pJuX/6ScmP+lnJj/pZ2Z/6Wdmf+nnpr/p56a/6ifm/+p
oJz/qaGc/6mhnf+ooZ3/qaKe/6minv+qop7/rKOf/62jn/+tpKD/raWh/62mof+qpJ//u7aycNDO
zADOy8gA0M3KANnV1ADc2dgAx8PBG3hraN9oWFX/a11a/2haV/+UjIj/t7Kt/7OtqP+0rqn/tK6p
/7Wvqv+1r6r/ta+q9M7KxyvW09AA1NHPANTRzwDU0c8A1NHPANTRzwDU0c8A1NHPANTRzwDU0c8A
1NHPANTRzwDU0c8A1NHPANTRzwDU0c8A1NHPANTRzwDU0c8A1NHPANTRzwDV0c8A1dLPANTR0ADB
u7sAl46MAKSbmgDQy8sAi4B/AKukowCWjIwAkYeGAKujogCyq6oAmZGPAJaMiwCup6cAr6inAJyT
kgCspKMArqemAKqioQCjmpkAk4mHALixsQC7tbUAloyLAIp/fgChmJcArKOjALCpqQCwqagAkIaE
AIh9fACnoJ8AloyKAMC9yQDBwtoAwMDXAMDA1wDAwNcAwMDXAMDA1wDAwNcAwMDXAMDA1wDAwNcA
wMDXAMDA1wDAwNcAwMDXAMHB2ADGxtsAhYWzXwUFZv8AAGX/AABm/wAAZv8BAGf/AABg/3Z3u/+c
n///NTr0/zo+9f87P/b/PEH4/xETkv8AAGH/AABl/w8PcP+kpuf/WVz7/zc79v88QPb/PUH3/z1B
9/89Qff/PUH3/z1D//89OJf/OiYb/1BAPv/Y0NBU6ePiAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDHx+EAo6PPKwcI
f/oAAHv/AAB8/wAAfP8AAHz/AAB5/x4ejP9bXeP/HB/d/yEl3f8hJdz/ISXc/yEl3P8iJt3/Iibd
/yAk3f8hJd3/pqjzRdrZ7wDZ1tIBgHdzvmBTT/9lWVX/ZVhV/2RVUv9xY2D/pZyY/5+Wkv+gl5P/
oJeT/6GYlP+hmJT/opqV/6Kalv+im5f/o5uX/6Sbl/+knJf/pZyY/6Wdmf+mnZn/p56a/6efm/+o
n5v/qaCc/6mhnf+ooZ3/qKKd/6iinf+pop7/q6Ke/6yjn/+tpKD/raSg/6+motvHwr8RzcnHAMzI
xgDY1dQA3tzbAOTi4gC+t7Y4b2Fe8GpaV/9qW1j/cWRg/6mjnv+0rqn/s62o/7OtqP+zraj/tK6p
/7Ksp//Dv7te09DNANHOywDRzssA0c7LANHOywDRzssA0c7LANHOywDRzssA0c7LANHOywDRzssA
0c7LANHOywDRzssA0c7LANHOywDRzssA0c7LANHOywDRzssA2NbSAJ+WlAC/ubgAxL+/AJeOjACk
m5oA0MvLAIuAfwCrpKMAloyMAJGHhgCro6IAsquqAJmRjwCWjIsArqenAK+opwCck5IArKSjAK6n
pgCqoqEAo5qZAJOJhwC4sbEAu7W1AJaMiwCKf34AoZiXAKyjowCwqakAsKmoAJCGhACIfXwAp6Cf
AJWMigDAvcgAxsfeAMXF2wDFxdsAxcXbAMXF2wDFxdsAxcXbAMXF2wDFxdsAxcXbAMXF2wDFxdsA
xcXbAMXF2wDJyd0Arq7MKRYWce4AAGL/AABl/wAAZv8AAGb/AABe/z49kf+2uPz/SEz2/zY69P86
PvT/PUH7/ywv0v8AAWb/AABn/wAAX/9cXaj/mp3//zY69v88QPb/PED2/zxA9v88QPb/PED2/zxB
/P89P+L/PS49/zYjHP+Zjo3h7ufnDuXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7e
AOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8Arq/VAK2t1AoeHovaAAB5/wAA
fP8AAHz/AAB8/wAAev8SEoP/XmDc/x4i3v8gJNz/ISPd/yEk3f8hJN3/ISXc/yEl3P8hJdz/GBzb
/29y6pnP0PQA1tPYALKsqUtiVFH/ZVlV/2VZVf9lWVX/ZFZT/5SLh/+hmJT/npWR/5+Wkv+fl5P/
oJeT/6CXk/+hmJT/oZmV/6Kalv+jmpb/o5uX/6Sbl/+km5f/pZyY/6ScmP+lnZn/pp2Z/6eemv+n
npr/qJ+b/6mgnP+poJz/qaGd/6iinf+oop3/qaOe/6ujn/+qoJz/ubKve97c2wDd2tkA3drZAN7c
2wDe3NwAz8vKAJiQjk9oXFj5aVxY/2haVv+Bd3P/sqyo/7Ksp/+yrKf/sqyn/7OtqP+xq6b/vbiz
qNzZ1gDb2NYA29jVANvY1QDb2NUA29jVANvY1QDb2NUA29jVANvY1QDb2NUA29jVANvY1QDb2NUA
29jVANvY1QDb2NUA29jVANvY1QDb2NUA4N3aAMjEwgBuX14Awry8AMS/vwCXjowApJuaANDLywCL
gH8Aq6SjAJaMjACRh4YAq6OiALKrqgCZkY8AloyLAK6npwCvqKcAnJOSAKykowCup6YAqqKhAKOa
mQCTiYcAuLGxALu1tQCWjIsAin9+AKGYlwCso6MAsKmpALCpqACQhoQAiH18AKegnwCWjIsAtrC0
AMzN3wDMzN4AzMzeAMzM3gDMzN4AzMzeAMzM3gDMzN4AzMzeAMzM3gDMzN4AzMzeAMzM3wDT0+MA
wcHXCi8vfswAAF//AABm/wAAZv8AAGb/AABh/xUUcv+srej/bXH8/zE28/86PvT/Oj71/zs/9v8R
E5D/AABg/wAAZP8QEHH/pafp/1ld+/82OvX/Oz/1/zs/9f88QPb/PED2/zxA9v88Qf//PDSF/zck
GP9XR0X/3tfWbuji4gDk394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AJ2dygCmps8APT2arQAAd/8AAHz/AAB8/wAA
fP8AAHv/CAh9/11f0v8hJt//ICTb/yAk2/8gJNz/ICPc/yEk3f8hJN3/ISXc/xwh2/83Ot/pvL32
EczK4wDV0MwDgnZ0v2JTUP9nWFX/ZllV/2FVUf97cG3/o5uX/5yTj/+dlJD/nZWR/56Vkf+flpL/
n5eS/6CXk/+hmJT/oZiU/6KZlf+imZX/opqW/6Obl/+km5f/pJuX/6ScmP+lnJj/pZ2Z/6admf+n
npr/qJ+b/6ifm/+poJz/qaGd/6mhnf+oop3/qKKd/6minvHLx8Un1dLRANPQzgDU0dAA3tvaANnV
1ADRzcwAq6SiZmlbV/9pXVn/aVtY/5WMiP+0ran/sKql/7Cqpf+xq6b/saum/7OtqOnW09AW3dvZ
ANza1wDc2tcA3NrXANza1wDc2tcA3NrXANza1wDc2tcA3NrXANza1wDc2tcA3NrXANza1wDc2tcA
3NrXANza1wDc2tcA3dvZAN/d2gCMgoAAZ1lXAMS+vgDEv78Al46MAKSbmgDQy8sAi4B/AKukowCW
jIwAkYeGAKujogCyq6oAmZGPAJaMiwCup6cAr6inAJyTkgCspKMArqemAKqioQCjmpkAk4mHALix
sQC7tbUAloyLAIp/fgChmJcArKOjALCpqQCwqagAkIaEAIh9fACnoJ8AloyLALOtsADPzt8A09Pj
ANLS4gDS0uIA0tLiANLS4gDS0uIA0tLiANLS4gDS0uIA0tLiANPT4gDQ0OEAycncAGJinqIAAF3/
AABi/wAAY/8AAGX/AABl/wABYf+Iicn/lpj//zI38v84PPP/OT3z/zxA+v8pLcz/AQFk/wAAZv8A
AF7/Zmau/5ea//8zOPT/Oj70/zs/9f87P/X/Oz/1/zs/9f87QP7/OzzS/zwrMP83JB//ppub/+7o
5zLk3t4A5N/eAOTf3gDk394A5N/eAOTf3gDk394A5N/eAOTf3gDk394A5N/eAOTf3gDk394A5N/e
AOTf3gDk394A5N/eAOTf3gDk394A5N/eAP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wCenswAp6fRAF9frXEAAHj/AAB8/wAAfP8AAHz/AAB8/wEB
eP9WV8X/KCzh/x4i2/8gI9z/ICPb/yAk2/8gJNv/ICTc/yEk3f8gI93/HB/b/4WH7Fu1tu4A2NTX
ALKsqUBiVVH7ZlhV/2dYVf9mV1T/aFtX/5mQjf+dlJD/nJOP/52UkP+dlJD/nZSQ/52UkP+elZH/
n5aS/5+Xk/+gl5P/oJiU/6GYlP+hmZX/opmV/6Oalv+jm5f/pJuX/6Sbl/+knJj/pZyY/6Wdmf+m
nZn/p56a/6ifm/+on5v/qaCc/6mhnP+noJv/r6mlnc/MygDSzs0A0M3LANnW1QDh3t0A4+HfAOPh
4ACooJ5vaFpW/2haV/9vYl//o5uX/7Grpv+vqKT/sKmk/7Cppf+vqaT/v7q2VMjEwQDHw78Ax8O/
AMfDvwDHw78Ax8O/AMfDvwDHw78Ax8O/AMfDvwDHw78Ax8O/AMfDvwDHw78Ax8O/AMfDvwDHw78A
x8O/AMrGwwChmZcAdGdmAGxeXADEvr4AxL+/AJeOjACkm5oA0MvLAIuAfwCrpKMAloyMAJGHhgCr
o6IAsquqAJmRjwCWjIsArqenAK+opwCck5IArKSjAK6npgCqoqEAo5qZAJOJhwC4sbEAu7W1AJaM
iwCKf34AoZiXAKyjowCwqakAsKmoAJCGhACIfXwAp6CfAJeNjACuqKsA1dThAOPj7gDf3+oA3t7q
AN/f6gDf3+oA39/qAN/f6gDf3+oA3t/qAN/f6gDi4uwA4eHrAHR0p3IAAF//AABi/wAAY/8AAGP/
AABj/wAAXP9ZWaT/sbP//0BE9P81OfL/ODzy/zk98/84PfL/Dg+J/wAAYf8AAGP/GBh2/6ut7/9T
V/n/NTn0/zo+9P86PvT/Oj70/zo+9P87P/b/Oz/7/zsxav80IRX/ZVZV/+Xf3vnl4eAn49/eAOPf
3gDj394A49/eAOPf3gDj394A49/eAOPf3gDj394A49/eAOPf3gDj394A49/eAOPf3gDj394A49/e
AOPf3gDj394A49/eAOPf3gD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8Aq6vSALKy1gCKisE3AgJ7/wAAfP8AAHz/AAB8/wAAfP8AAHb/S0u1/zI2
4/8cINr/HyPa/x8j2/8gI9z/ICPc/yAk3P8gJNv/ICTb/xcb2v9WWOS+0dP7AMjF2AC4sq0AgXd0
qWFVUf9mWlb/Z1lW/2NUUf+Ed3T/n5aS/5qRjf+bko7/m5OP/5yTj/+clJD/nZSQ/52UkP+elZH/
npWR/5+Wkv+flpL/oJeT/6CXk/+hmJT/oZmV/6Kalv+jmpb/o5qW/6Sbl/+km5f/pJyY/6WcmP+l
nZn/pp2Z/6eemv+on5v/qJ+b/6edmfnCvblI29nWANjW0wDY1dMA3NrYAODd3ADd2tkA29jYAKmh
n25pW1j/aFlW/3ptav+qpJ//r6mk/62nov+uqKP/rqei/7iyrpnU0M4A09DOANPQzQDT0M0A09DN
ANPQzQDT0M0A09DNANPQzQDT0M0A09DNANPQzQDT0M0A09DNANPQzQDT0M0A09DNANfU0QDDvrsA
em9tAHZqaABsXlwAxL6+AMS/vwCXjowApJuaANDLywCLgH8Aq6SjAJaMjACRh4YAq6OiALKrqgCZ
kY8AloyLAK6npwCvqKcAnJOSAKykowCup6YAqqKhAKOamQCTiYcAuLGxALu1tQCWjIsAin9+AKGY
lwCso6MAsKmpALCpqACQhoQAiH18AKegnwCXjYwAsautAMTD1gDNzd8A2dnnANra5wDZ2ecA2dnn
ANnZ5wDZ2ecA2dnnANrZ5wDZ2eYA2dnmAKOjxU4MDGj9AABg/wAAY/8AAGP/AABj/wAAXP8vMIT/
ubv4/1hb9/8wNPD/ODzx/zg88v87P/r/Iye//wAAYv8AAGb/AABf/3h4vP+Nkf//Mjbz/zk98/86
PvT/Oj70/zo+9P86PvT/Oj///zo4tv86JyH/PCom/7uxsP/q5uWi4t7dAOLe3QDi3t0A4t7dAOLe
3QDi3t0A4t7dAOLe3QDi3t0A4t7dAOLe3QDi3t0A4t7dAOLe3QDi3t0A4t7dAOLe3QDi3t0A4t7d
AOLe3QDi3t0A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AKKizwCjo9AAo6PQDR0djNwAAHn/AAB8/wAAfP8AAHz/AAB2/zs8pP8/QeT/Gh3c/x8i
3P8fItv/HyPb/x8j2/8fI9z/ICPc/yAj3P8eItv/JSjc/LGy8zLKyu8AyMTEALq1sipqXVnwZFhU
/2ZaVv9lWFT/bF9b/5mQjP+akY3/mZCM/5qRjf+akY3/m5KO/5yTj/+ck4//nJSQ/52UkP+dlJD/
npWR/56Vkf+flpL/oJeT/6GXk/+hmJT/oZiU/6GZlf+impX/o5qW/6Obl/+km5f/pJyY/6WcmP+l
nJj/pp2Z/6admf+mnZn/qaGc19HOyxHe29kA29nWANvY1gDf3NsA3NnYANbS0QDd2tkAraakYWpd
WfZnV1T/hHl1/66oo/+uqKP/raei/62nov+uqKTuysbDGc/MyQDOysgAzsrIAM7KyADOysgAzsrI
AM7KyADOysgAzsrIAM7KyADOysgAzsrIAM7KyADOysgAzsrIAM/LyADQzMkAm5KRAHpvbgB3a2kA
bF5cAMS+vgDEv78Al46MAKSbmgDQy8sAi4B/AKukowCWjIwAkYeGAKujogCyq6oAmZGPAJaMiwCu
p6cAr6inAJyTkgCspKMArqemAKqioQCjmpkAk4mHALixsQC7tbUAloyLAIp/fgChmJcArKOjALCp
qQCwqagAkIaEAIh9fACnoJ8Al42MALawsACWlrgAkJK3AM7O3wDR0OEAzs3fAM7N3wDOzd8Azs3f
AM7N3wDOzd8A0dHhAJ2dwDIUFGvuAABd/wAAY/8AAGP/AABj/wAAXv8UFHD/ra7m/3Z5+/8vM/D/
Nzvx/zc78f84PPT/NDjq/wgJev8AAGL/AABh/yoqgv+wsvj/R0v2/zU58v85PfP/OT3z/zk98/85
PfP/Oj74/zk96/87LUn/Mh0W/31vbv/q5OP44d3cLOHd3ADh3dwA4d3cAOHd3ADh3dwA4d3cAOHd
3ADh3dwA4d3cAOHd3ADh3dwA4d3cAOHd3ADh3dwA4d3cAOHd3ADh3dwA4d3cAOHd3ADh3dwA4d3c
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wCw
sNUAsLDVALq52gBKSqKkAAB5/wAAff8AAHz/AAB8/wAAeP8nJ5L/Sk3g/xgd2f8eItr/HyHb/x8h
3P8fItz/HyLb/x8j2/8fI9v/ICPb/xYZ2v9oauebyMr5AMnG3wDMx8EAk4iGfmNUUP9nWVb/ZlpW
/2NXU/+EeXX/m5KO/5eOiv+Yj4v/mZCM/5mQjP+akY3/mpGN/5uSjv+bko7/nJOP/5yUkP+dlJD/
nZSQ/56Vkf+elZH/n5aS/6CXk/+gl5P/oZiU/6GYlP+hmZX/opqW/6Kalv+jm5f/pJuX/6Sbl/+l
nJj/pZyY/6Kalv+0raqS3tvZAODd2wDe3NoA393aANzZ2ADV0dAA2tfWAMrGxACVjIlNdGhk62ZX
VP+LgX7/sKik/62mof+spqH/qqSe/725tXDb2NYA2NXTANjV0wDY1dMA2NXTANjV0wDY1dMA2NXT
ANjV0wDY1dMA2NXTANjV0wDY1dMA2NXTANjV0gDd2tgAu7WzAIZ7egB+cnEAd2tpAGxeXADEvr4A
xL+/AJeOjACkm5oA0MvLAIuAfwCrpKMAloyMAJGHhgCro6IAsquqAJmRjwCWjIsArqenAK+opwCc
k5IArKSjAK6npgCqoqEAo5qZAJOJhwC4sbEAu7W1AJaMiwCKf34AoZiXAKyjowCwqakAsKmoAJCG
hACIfXwAp6CfAJeNjAC2sLAAmJi5AJOUuQDOzt8A09LiANDP4ADPzuAAz87gAM/O4ADPzuAA1dTj
AMLB1yAsLHneAABa/wEAYP8BAGD/AABj/wAAYP8FBWP/kpLP/5WX//8xNe//NTnw/zY68P82OvH/
Oj75/xsdqv8AAF//AABl/wEBY/+RktD/e37+/zA08f84PPL/ODzy/zg88v84PPL/OT3z/zk+/f85
M4r/NyMW/0o4Nv/RyMj/5eDgeOHd3ADi3t0A4t7dAOLe3QDi3t0A4t7dAOLe3QDi3t0A4t7dAOLe
3QDi3t0A4t7dAOLe3QDi3t0A4t7dAOLe3QDi3t0A4t7dAOLe3QDi3t0A4t7dAOLe3QD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8AxcTgAMXE4ADQ
z+YAgYC+VQAAef8AAX7/AAF+/wAAff8AAHv/EBCC/1BT2P8bHt3/HiHa/x4h2f8eItn/HiLa/x8h
2/8fIdz/HyHc/x8i2/8bHtr/MDTd8ba39CC/wPEAysbMAMzHxQ15bGrPY1RR/2hZVv9mWFT/bWBd
/5WLiP+Xjor/lo2J/5eOiv+Yj4v/mI+L/5mQjP+ZkIz/mpGN/5qRjf+bko7/nJOP/5yTj/+dlJD/
nZSQ/52UkP+elZH/npWR/5+Wkv+gl5P/oJeT/6GYlP+hmJT/opmV/6Oalv+jmpb/pJuX/6Sbl/+k
m5f/opmV+sK9uUng3t0A4N7cAN/e2wDe29oA1dHRANrX1gDEv70AqqKfALCppzR1aWbLZlhV/5GH
g/+wp6P/raSg/6ykn/+vqKTa3NnYDOXi4QDj4N8A4+DfAOPg3wDj4N8A4+DfAOPg3wDj4N8A4+Df
AOPg3wDj4N8A4+DfAOPg3wDk4eEA4uDfAJOJiACIfXwAfnJxAHdraQBsXlwAxL6+AMS/vwCXjowA
pJuaANDLywCLgH8Aq6SjAJaMjACRh4YAq6OiALKrqgCZkY8AloyLAK6npwCvqKcAnJOSAKykowCu
p6YAqqKhAKOamQCTiYcAuLGxALu1tQCWjIsAin9+AKGYlwCso6MAsKmpALCpqACQhoQAiH18AKeg
nwCXjYwAtrCwAJiYuQCTlLkA0dHhAJeXugCRkbcApqbFAKysyQCqqscAoaDCAJCQtxMzMn7PAABa
/wEAYP8BAGD/AQBg/wAAX/8AAFz/dHW5/6ut//85PfD/Mjbv/zY68P82OvD/ODz1/y0x2f8DA2v/
AABk/wAAXf9JSZn/q67//zk+8v81OfH/Nzvx/zg88v84PPL/ODzy/zg9+/84OMn/Oykq/zMfGv+e
kpH/6uXkx9/b2wTh3d0A4d3dAOHd3QDh3d0A4d3dAOHd3QDh3d0A4d3dAOHd3QDh3d0A4d3dAOHd
3QDh3d0A4d3dAOHd3QDh3d0A4d3dAOHd3QDh3d0A4d3dAOHd3QDh3d0A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AJKRxgCSkcYAlJTHAI2NxBgQ
EYbtAAB8/wABfv8AAX7/AAB+/wICev9OUMf/IiXf/x0f2v8eINv/HiDb/x4h2v8eIdr/HiLZ/x4i
2v8fIdz/HyHc/xYY2v9tcOeI0dP6ANPS5QDX1NAAtK6sPmZZVfhmWVb/aFpW/2VWU/+BdnL/mY+L
/5aMiP+WjIn/lo2J/5aNif+Xjor/mI+L/5iPi/+ZkIz/mZCM/5qRjf+akY3/m5KO/5yTj/+ck4//
nZSQ/52UkP+dlZD/npWR/56Vkf+flpL/oJeT/6CXk/+hmJT/opmV/6KZlf+impb/o5qW/6Oalv+k
m5fa0M3KHuDe3ADe3NoA39zbANrY1gDa19YAxL+9AKefnAC2sK4AqqOhE5KJhp9pW1j/kIaC/62m
ov+so5//qqCc/8C6t1/PzMkAzcnGAM3JxgDNycYAzcnGAM3JxgDNycYAzcnGAM3JxgDNycYAzcnG
AM3JxgDNyMYA0c3LAKmhoAB9cXAAjIKAAH5ycQB3a2kAbF5cAMS+vgDEv78Al46MAKSbmgDQy8sA
i4B/AKukowCWjIwAkYeGAKujogCyq6oAmZGPAJaMiwCup6cAr6inAJyTkgCspKMArqemAKqioQCj
mpkAk4mHALixsQC7tbUAloyLAIp/fgChmJcArKOjALCpqQCwqagAkIaEAIh9fACnoJ8Al42MALaw
sACYmLkAk5S5ANLS4QCEha4Afn6qAJmavQChocIAoaHBAJaWuww3OIC8AABZ/wEAYP8BAGD/AQBg
/wAAYP8AAFf/WVqj/7i5//9HS/L/MDTu/zU57/81Oe//Njrx/zY78v8QEY3/AABd/wAAYv8REW//
qavn/2Fl+f8wNPD/Nzvx/zc78f83O/H/Nzvx/zc79P84O/D/OSxY/zIeE/9lVVT/493c++Dc2y/h
3t0A4d7dAOHe3QDh3t0A4d7dAOHe3QDh3t0A4d7dAOHe3QDh3t0A4d7dAOHe3QDh3t0A4d7dAOHe
3QDh3t0A4d7dAOHe3QDh3t0A4d7dAOHe3QDh3t0A4d7dAP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wDFxeAAxcXgAMXF4ADNzeQARUWgrAAAev8A
AH7/AAF+/wABfv8AAHn/QEGy/ywv4v8bHdr/HSDa/x0g2f8dINr/HiDb/x4g2/8eIdr/HiLa/x4i
2f8ZHNn/Mzbe7c7P9xna2vgA19TcAN7c2QCbk5CBYFNP/2dbV/9mWlb/a15a/4+Fgf+Wi4j/lYqH
/5aKiP+WjIn/loyJ/5aNif+Xjor/l46K/5iPi/+Yj4v/mZCM/5mRjf+akY3/mpKO/5uSjv+ck4//
nJSQ/52UkP+dlJD/npWR/56Vkf+flpL/n5aS/6CXk/+gl5P/oZiU/6GZlf+imZX/oJiU/6qinrDU
0c8F3NjWANnV0wDZ1dMA3dnYAMK9uwCmnpwAs6yqALCqpwDKxcMAo5qZWnZpZuKMgn7/q6Wg/6mi
nf+rpJ/C0M3KBNnX1ADY1dIA2NXSANjV0gDY1dIA2NXSANjV0gDY1dIA2NXSANjV0gDY1dIA2tfU
ANHOywB8cW8Af3RzAIyCgAB+cnEAd2tpAGxeXADEvr4AxL+/AJeOjACkm5oA0MvLAIuAfwCrpKMA
loyMAJGHhgCro6IAsquqAJmRjwCWjIsArqenAK+opwCck5IArKSjAK6npgCqoqEAo5qZAJOJhwC4
sbEAu7W1AJaMiwCKf34AoZiXAKyjowCwqakAsKmoAJCGhACIfXwAp6CfAJeNjAC2sLAAmJi5AJOU
uQDS0uEAh4iwAIGBrACbnL4ApaXEAKipxgdJSYuxAABY/wAAXf8BAF//AQBg/wEAYP8AAFf/Q0OR
/7y++/9YW/T/LTHt/zU57/81Oe//NTnv/zg89/8hJLv/AABe/wAAYv8AAFz/dne6/5eZ//8wNO//
Njrw/zY68P83O/H/Nzvx/zc78f83PP3/ODGQ/zgiF/8+LCr/xLu6/+Tg32Xe2toA39vbAN/b2wDf
29sA39vbAN/b2wDf29sA39vbAN/b2wDf29sA39vbAN/b2wDf29sA39vbAN/b2wDf29sA39vbAN/b
2wDf29sA39vbAN/b2wDf29sA39vbAN/b2wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8Av7/dAL+/3QC/v90AycniAIODv1UAAHz/AACA/wAAf/8A
AH//AAB5/yormf87PeD/GBrb/x0f2/8dH9v/HR/a/x0g2f8dINn/HiDa/x4g2/8eIdv/HiHa/xQY
2P98femL4eH7ANnY8gDc2dcAzMjFBYB0cbtjVVH/aFtX/2RZVf92bGj/lIuH/5OKhv+UiYb/lIqH
/5WKiP+Vi4j/loyJ/5aNif+WjYn/l46K/5eOiv+Yj4v/mZCM/5mQjP+ZkY3/mpGN/5uSjv+bko7/
nJOP/5yTj/+dlJD/nZSQ/56Vkf+elZH/n5aS/5+Wkv+gl5P/oJeT/6GYlP+flpL/saungc/JxwDb
1tQA3trYAODc2wDMxsUAqaGfALKrqQCuqKUAxcC+AL65twC6tLIZkoiFnI6EgP2noJv/p5+b/8K+
u2fh390A3dvZAN3b2QDd29kA3dvZAN3b2QDd29kA3dvZAN3b2QDd29kA3dvZAOPi4AC4s7EAc2dl
AIF2dQCMgoAAfnJxAHdraQBsXlwAxL6+AMS/vwCXjowApJuaANDLywCLgH8Aq6SjAJaMjACRh4YA
q6OiALKrqgCZkY8AloyLAK6npwCvqKcAnJOSAKykowCup6YAqqKhAKOamQCTiYcAuLGxALu1tQCW
jIsAin9+AKGYlwCso6MAsKmpALCpqACQhoQAiH18AKegnwCXjYwAtrCwAJiYuQCTlLkA0tLhAIeI
sACBgawAnZ6/AKysyAZPUI6sAABZ/wAAXf8AAF7/AABe/wAAX/8AAFf/MjKD/7y99f9navf/KzDt
/zQ47v80OO7/NDju/zY68/8uMt//BQZw/wAAX/8AAFv/NziL/7O0+v9FSfP/Mjbv/zY68P82OvD/
Njrw/zY68P82O/r/NjbH/zkmK/8wHRf/kYWD/+nk5K/a2NYA3drZAN3a2QDd2tkA3drZAN3a2QDd
2tkA3drZAN3a2QDd2tkA3drZAN3a2QDd2tkA3drZAN3a2QDd2tkA3drZAN3a2QDd2tkA3drZAN3a
2QDd2tkA3drZAN3a2QDd2tkA////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AKqq0wCqqtMAqqrTAKys1ACmp9EPFhaK4gAAfv8AAID/AACA/wAAfv8U
FIf/Q0XW/xga3P8cHtr/HB7a/x0f2/8dH9v/HR/b/x0g2v8dINr/HSDZ/x4h2v8ZHNv/LC/d8r/A
9SDR0foAzcvbANfTzQC9t7Yhb2Fe4mVWVP9oWlf/Z1pW/4R5df+Ui4b/kYmE/5KJhf+Tiob/lIqH
/5WKh/+Viof/louI/5WMiP+WjYn/lo2J/5eOiv+Xjor/mI+L/5iPi/+ZkIz/mpGN/5qRjf+bko7/
m5KO/5yTj/+clJD/nZSQ/52UkP+dlJD/npWR/5+Wkv+flpL/oJeT/52UkPe3sKxb3tnYAOHd3ADg
3NsA49/eANDKyQCvqKYArKajAMXAvgC6tLIAwby6AMnEwwCgmJZImpKOy6Obl/+qop3lzsrHENnX
1QDY1dMA2NXTANjV0wDY1dMA2NXTANjV0wDY1dMA2NXTANnW1ADU0c8AgHRyAHRoZgCBdnUAjIKA
AH5ycQB3a2kAbF5cAMS+vgDEv78Al46MAKSbmgDQy8sAi4B/AKukowCWjIwAkYeGAKujogCyq6oA
mZGPAJaMiwCup6cAr6inAJyTkgCspKMArqemAKqioQCjmpkAk4mHALixsQC7tbUAloyLAIp/fgCh
mJcArKOjALCpqQCwqagAkIaEAIh9fACnoJ8Al42MALawsACYmLkAk5S5ANLS4QCHiLAAg4OtAKSk
xAZQUI6rAABZ/wAAXf8AAF7/AABe/wAAXv8AAFb/JiZ6/7a37/91ePr/Ky/s/zM37f8zN+3/NDju
/zQ47/81OfL/EhSS/wAAW/8AAGD/DAxo/6Sl4f9wc/r/LTHu/zU57/81Oe//NTnv/zY68P82OvX/
Njnr/zcqTv8xHRH/YVBP/+DZ2ejf29of3dvZAN7b2gDe29oA3tvaAN7b2gDe29oA3tvaAN7b2gDe
29oA3tvaAN7b2gDe29oA3tvaAN7b2gDe29oA3tvaAN7b2gDe29oA3tvaAN7b2gDe29oA3tvaAN7b
2gDe29oA3tvaAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wDFxeAAxcXgAMXF4ADFxeAA0NDlAFlZq5IAAHr/AACA/wAAgP8AAID/AQF8/0JDwv8h
I9//Gx3a/xwe2v8cHtr/HB7a/xwe2v8cHtv/HR/b/x0f2/8dINr/HSDZ/xQY2P9laOWfuLnzAK+w
8ADPzNYA3dnXALavrkVpW1j2Z1lV/2hZVv9uYF3/j4SA/5OIhP+SiIT/kYiE/5KJhf+SiYX/komF
/5SKhv+Uiof/lYqI/5WLiP+WjIn/lo2J/5aNif+Wjon/l46K/5iPi/+Yj4v/mZCM/5mQjP+akY3/
m5KO/5yTj/+ck4//nJOP/52UkP+dlJD/npWR/56Vkf+elZH/npSQ9sW/vU3h3dwA3trZAOLe3QDf
2tkAvbazALWvrADDvrwAurSyAL+6uADEv70Ata6tALexrwqim5htpJuX7Lauq5Xe29oA29nYANvZ
1wDb2dcA29nXANvZ1wDb2dcA29nXANvZ1wDf3dsAysXFAGxfXQB4bGoAgXZ1AIyCgAB+cnEAd2tp
AGxeXADEvr4AxL+/AJeOjACkm5oA0MvLAIuAfwCrpKMAloyMAJGHhgCro6IAsquqAJmRjwCWjIsA
rqenAK+opwCck5IArKSjAK6npgCqoqEAo5qZAJOJhwC4sbEAu7W1AJaMiwCKf34AoZiXAKyjowCw
qakAsKmoAJCGhACIfXwAp6CfAJeNjAC2sLAAmJi5AJOUuQDS0uEAiYqxAImJsQlKS4uwAABZ/wAA
Xf8AAF7/AABe/wAAXv8AAFb/Hx91/7Cx6P+BhPv/KzDs/zI27f8zN+3/Mzft/zM37f82Ovb/ICK4
/wAAXP8AAGH/AABb/3V1uP+cn///MTXu/zM37/81Oe//NTnv/zU57/81OfD/NTr5/zYvgP81IBX/
Piwq/8K5uf7m4uFe39zbAODd3ADg3dwA4N3cAODd3ADg3dwA4N3cAODd3ADg3dwA4N3cAODd3ADg
3dwA4N3cAODd3ADg3dwA4N3cAODd3ADg3dwA4N3cAODd3ADg3dwA4N3cAODd3ADg3dwA4N3cAODd
3AD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
y8rjAMvK4wDLyuMAy8rjANLS5wCmptEwBgaC9wAAf/8AAID/AACA/wAAev8wMab/LS/f/xkb2f8b
Hdn/HB7a/xwe2v8cHtr/HB7a/xwe2v8cHtr/HR/b/x0f2/8bHdr/HyLa/IqM6zuqq/MAtLToANrW
1QDV0dAAlo2LY2RYVP9nW1f/ZllV/3htaf+Rh4P/kIaC/5KGgv+Sh4P/koiE/5KIhP+RiYX/komF
/5KJhf+Tiof/lIqH/5WKiP+Wi4j/loyJ/5aNif+WjYn/lo6K/5eOiv+Yj4v/mI+L/5mQjP+akY3/
mpGN/5uSjv+ck4//nJOP/5yTj/+dlJD/nZSQ/5yTj/+elZLuuLGuMcC4tgDY09IA3djXAM7HxQDb
1tQAx8LAALu0sgDAu7kAxL+9ALKrqgC3sK4AsaupAL+5tyOwqaaZwLu4N9TRzwDT0M4A09DOANPQ
zgDT0M4A09DOANPQzgDT0M4A1tPQAMbBwQBuYmAAeGxqAIF2dQCMgoAAfnJxAHdraQBsXlwAxL6+
AMS/vwCXjowApJuaANDLywCLgH8Aq6SjAJaMjACRh4YAq6OiALKrqgCZkY8AloyLAK6npwCvqKcA
nJOSAKykowCup6YAqqKhAKOamQCTiYcAuLGxALu1tQCWjIsAin9+AKGYlwCso6MAsKmpALCpqACQ
hoQAiH18AKegnwCXjYwAtrCwAJiYuQCSlLkA1tbkAJCQthE5OX64AABZ/wAAXf8AAF7/AABe/wAA
Xv8AAFb/Hh5y/6yt5f+JjPz/LC/r/zEz7P8yNuz/Mjbs/zI27P81OfL/Ky7Y/wQFaf8AAFz/AABZ
/zw9jf+2t/z/RUny/y8z7f80OO7/NDju/zQ47v80OO7/NTr6/zUysP83Ix//MB0Y/5mMi//o4+J2
3drYAOHe3gDh3t0A4d7dAOHe3QDh3t0A4d7dAOHe3QDh3t0A4d7dAOHe3QDh3t0A4d7dAOHe3QDh
3t0A4d7dAOHe3QDh3t0A4d7dAOHe3QDh3t0A4d7dAOHe3QDh3t0A4d7dAOHe3QDh3t0A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////ALGw1gCxsNYA
sbDWALGw1gCxsdYAubjaADY2mrIAAHz/AACB/wAAgP8AAH3/FxeM/zk71v8XGdr/Gx3Z/xsd2f8b
Hdn/Gx3Z/xwe2v8cHtr/HB7a/xwe2v8cHtr/HB7a/xUX2v9KTOHIxMX1BMXF9wDV0+YA4NzXAN3a
2ACelpSCYlVR/2dbV/9oW1f/g3h0/5CHg/+PhYH/j4WB/5GGgv+Rh4P/koeD/5KIhP+RiIT/komF
/5KJhf+Tiob/lIqH/5WKh/+Vi4f/louI/5aMiP+WjYn/lo6J/5eOiv+Xjor/mI+L/5mQjP+ZkIz/
mpGN/5qRjf+bko7/m5KO/5yTj/+dlJD/nJKO/56Wktizq6gs2tXUAN7Z2ADNxsQA3NbVANjS0QDD
vb0AvLa0AMbBvwCyq6oAt7CuAK+opgDHwsEAycXDAMC7tyHU0M4F1NDOANTQzgDU0M4A1NDOANPQ
zgDW09EA1tPRANPPzQDGwcEAb2JgAHhsagCBdnUAjIKAAH5ycQB3a2kAbF5cAMS+vgDEv78Al46M
AKSbmgDQy8sAi4B/AKukowCWjIwAkYeGAKujogCyq6oAmZGPAJaMiwCup6cAr6inAJyTkgCspKMA
rqemAKqioQCjmpkAk4mHALixsQC7tbUAloyLAIp/fgChmJcArKOjALKrqwC1r64AkYeFG4uAfwSq
o6IAl42MALawsACYmLkAmpq9AMbG2R09PoDIAABX/wAAXf8AAF7/AABe/wAAXv8AAFf/HR1y/66v
5v+Nj/3/LDDq/zA06/8yNez/MjXs/zI17P8zNu//MTXr/wwNgv8AAFn/AABb/xUUbf+vsOn/aGv4
/ysv7P80OO7/NDju/zQ47v80OO7/NDn2/zQ11P83JzX/LxoS/2tcW//k3t2t3tvZB93a2ADe29kA
3tvZAN7b2QDe29kA3tvZAN7b2QDe29kA3tvZAN7b2QDe29kA3tvZAN7b2QDe29kA3tvZAN7b2QDe
29kA3tvZAN7b2QDe29kA3tvZAN7b2QDe29kA3tvZAN7b2QDe29kA3tvZAP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wCens0Anp7NAJ6ezQCens0A
np7NAKWl0QB6erxIAQF//wAAgf8AAIH/AACA/wQEff85O8H/HB7c/xoc2P8aHNj/Gx3Z/xsd2f8b
Hdn/Gx3Z/xwe2v8cHtr/HB7a/xwe2v8cHdr/FBbZ/4mL62/d3fkA09T3AN7c5QDl4t8A2dbVAJSL
iI9jVVH/Z1pW/2xgXP+Kf3v/kIaB/4+FgP+PhYH/joWB/5CFgv+QhoL/koaD/5KIhP+SiIT/komF
/5KJhf+SiYX/k4qG/5SKhv+Viof/lYqI/5WLiP+WjIn/lo2J/5aOif+Xjor/l46K/5iPi/+Yj4v/
mZCM/5mRjP+akY3/m5KO/5uTj/+bko7/nZWR28jCv0Hd2NcAzcfFANvV1ADY0tEAxb+/AJmQjwCw
qagAt7CvALmzsACvqKYAxsG/AMjEwgDCvboA0c3LANHNywDRzcsA0c3LANTQzgDU0M4Aw728AKuk
owDDvr0AyMPCAG9iYAB4bGoAgXZ1AIyCgAB+cnEAd2tpAGxeXADEvr4AxL+/AJeOjACkm5oA0MvL
AIuAfwCrpKMAloyMAJGHhgCro6IAsquqAJmRjwCWjIsArqenAK+opwCck5IArKSjAK6npgCqoqEA
o5qZAJOJhwC4sbEAu7W1AJaMiwCKf34Ao5qZALKqqgCtpqYggXV0jlNCQe1jVVPCnZSTOJyTkgC3
sbEAn569AIuMsy8xMXjZAABT/wAAXP8AAF7/AABe/wAAXv8AAFb/Hx9z/62v5f+Nj/z/LTLq/y4y
6/8xNev/MTXr/zI26/8yNuz/NDjz/xcZof8AAFn/AABe/wIBXf+Li8n/kZT//ywx7P8yNu3/Mzft
/zM37f8zN+3/Mzjy/zM47P81KFj/MRsS/0k3Nf/SycjY49/eBtzZ1wDd2tgA3drYAN3a2ADd2tgA
3drYAN3a2ADd2tgA3drYAN3a2ADd2tgA3drYAN3a2ADd2tgA3drYAN3a2ADd2tgA3drYAN3a2ADd
2tgA3drYAN3a2ADd2tgA3drYAN3a2ADd2tgA3drYAN3a2AD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8Azs7mAM7O5gDOzuYAzs7mAM7O5gDQ0OcA
0NDnBS8vl8YAAHz/AACB/wAAgf8AAHz/KCii/ykr3f8YGtj/GhzY/xoc2P8bHdn/Gx3Z/xsd2f8b
Hdn/Gx3Z/xsd2f8cHtr/HB7a/xcZ2f8sL9zws7TxJcDB9QC8vfMA2tjfANjV0QDJxcMBj4SClWRV
Uf9nWFX/cmZj/42Cfv+PhID/joN//4+EgP+PhYD/joWB/4+Fgv+QhYL/kYaC/5GHg/+Sh4P/koiE
/5GIhP+SiYX/komF/5OKhv+Uiob/lYqH/5WLiP+Vi4j/loyJ/5aNif+WjYn/l46K/5eOiv+Yj4v/
mI+L/5mQjP+ZkY3/m5KO/5qRjf+bko3owLm2S9HLyQDc1tUA2NLRAMXAvwCVi4oAn5aWAJqRkQCg
mJYAr6mnAMrFwwDLx8UAwr25ANHNywDTz80A1tLQANHNywC5s7EAzMfHAKCYlwCRh4cAxcC/AMjD
wgBvYmAAeGxqAIF2dQCMgoAAfnJxAHdraQBsXlwAxL6+AMS/vwCXjowApJuaANDLywCLgH8Aq6Sj
AJaMjACRh4YAq6OiALKrqgCZkY8AloyLAK6npwCvqKcAnJOSAKykowCup6YAqqKhAKOamQCTiYcA
uLGxALu1tQCYjo0Aj4WEAJ6VlCl/cnKRVURD7EIwLv9FMzL/RDEw/008O/h4a2qSta+vF4uLs0YY
GGjoAABU/wAAWv8AAFr/AABb/wAAXf8AAFX/Jid4/7Cx6P+JjPv/LDDq/y0w6v8xNOv/MTXr/zE1
6/8xNev/NDjz/yEkvf8AAFz/AABd/wAAV/9fX6b/r7H//zg87v8vM+z/Mzft/zM37f8zN+3/Mzfu
/zM49/8zK3z/NB8T/zUiIP+xp6bl6ublLt/b2QDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA
4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg
3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////ANPT6QDT0+kA09PpANPT6QDT0+kA09PpAN/f7gCMjMVT
AAB8/wAAgf8AAIH/AAB//w4OiP8yNND/Fxna/xoc2P8aHNj/GhzY/xoc2P8aHNj/GhzY/xsd2f8b
Hdn/Gx3Z/xsd2f8cHtn/ExbY/0dK4Lm3t/MCvL31AMXF8ADSz9IAx8K/AMO+vQGSiIaRZFZT/2dY
Vf94bGj/jYJ+/42Cfv+Ngn7/joN//4+EgP+PhYD/j4WB/4+Fgf+PhYH/j4WC/5GGgv+RhoP/koiD
/5KIhP+RiIT/kYmF/5KKhv+Tiob/lIqH/5WJh/+Vioj/loyJ/5WMif+WjYn/lo2J/5eOiv+Yj4v/
mI+L/5mQjP+ZkIz/mJCM/5mRjPi3sK1h3tjXANnU0wDFwL8AloyLAKGZmACTiYkAj4aFAJuSkgCq
o6IAurSyAMfCvwDTz80Ax8LAAKihnwDDvb0AjIGAAMfCwgCimpoAlIqKAMXAvwDIw8IAb2JgAHhs
agCBdnUAjIKAAH5ycQB3a2kAbF5cAMS+vgDEv78Al46MAKSbmgDQy8sAi4B/AKukowCWjIwAkYeG
AKujogCyq6oAmZGPAJaMiwCup6cAr6inAJyTkgCspKMArqemAKqioQCjmpkAlIqIAL63twDAu7sA
j4WEPmlbWZ9RQUDzQS4t/0QxMP9HNTT/RzY0/0g2Nf9GNDP/QzAv/1pLR+Y2MFn5AABX/wAAWv8A
AFr/AABa/wAAWf8AAFH/MTKA/7W27P+Ehvr/Ki3p/ywx6v8vM+r/MDPq/zAz6v8wM+r/Mjbx/ygs
0/8EBGj/AABa/wAAVv83N4f/ubr5/1BU8v8rL+v/Mjbs/zI07P8yNez/Mjbs/zI4+P8zL6H/NSEb
/y0YFf+Mf37l7ebmLeHd2wDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA
4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg
3NoA4NzaAODc2gDg3NoA4NzaAP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wDPz+cAz8/nAM/P5wDPz+cAz8/nAM/P5wDR0egA0NDnAy8vmMcAAH3/
AACB/wAAgf8AAHz/LC6z/x0f3P8ZG9f/GRvX/xoc2P8aHNj/GhzY/xoc2P8aHNj/GhzY/xoc2P8b
Hdn/Gx3Z/xoc2f8VGNj/goPqc87O9wDOz/kAz8/tAMbAvADAurgAzsrJAJuSkINlWFX9ZllV/3xw
bP+Ngn7/jIF9/4yBff+Ngn7/joN//46Df/+PhID/j4SA/4+Fgf+OhYH/joWB/4+Ggv+RhoL/koeD
/5KIg/+SiIT/kYiE/5KJhf+SiYX/k4qG/5SKhv+Viof/lYuI/5aMif+WjIn/lo2J/5aNif+Xjor/
mI+L/5iPi/+Yj4v/l46J/7OrqI/X0dAdxb+/A5aNjACim5oAlIqKAJOKiQCXjY0Ain9+AJWLigCu
p6YAraelAJ+WlQB5bm0Aw729AI+EgwDIw8MAopqaAJSKigDFwL8AyMPCAG9iYAB4bGoAgXZ1AIyC
gAB+cnEAd2tpAGxeXADEvr4AxL+/AJeOjACkm5oA0MvLAIuAfwCrpKMAloyMAJGHhgCro6IAsquq
AJmRjwCWjIsArqenAK+opwCck5IArKSjAK+opwCupqUAqaGgAJWLiRaVi4tlbmBfw0k4Nv9BLy7/
QzEw/0Y0M/9HNTT/RzU0/0c1NP9HNTP/QS4u/0w5Nf9nWFf/PDZi/wMDWv8AAFr/AABa/wAAWf8A
AFH/QECK/7u98/95fPj/Jyvo/y0w6f8vMun/LzLp/y8z6v8vM+n/MTXu/y0w4v8JCnn/AABX/wAA
Wf8YGW//sLHq/29y+P8oLOn/MTXr/zE16/8yNuz/MjXs/zI29v8yMcH/NCIn/ysXD/9pW1nk5t/f
LObe3gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA
4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg
3NoA4NzaAODc2gD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A2trrANra6wDa2usA2trrANra6wDa2usA2trrAObm8QCbm8xHAAB9/gAAgP8AAIH/
AAB+/xYWkf8pK9b/FhjX/xkb1/8ZG9f/GRvX/xkb1/8aHNj/GhzY/xoc2P8aHNj/GhzY/xoc2P8b
Hdj/FhjY/x8h2fiwsfI56uv8AN/g/QDRz90Avri0AM3JxwDFwL8Ai4J/ZGpdWvdlWVX/f3Rw/4yC
fv+LgHz/i4B8/4yBff+MgX3/jYJ+/42Cfv+Og3//j4SA/4+EgP+OhID/joWB/4+Fgf+PhoL/kYaC
/5KHg/+SiIT/kYiE/5GIhP+SiYX/koqG/5OJhv+Uiof/lYqH/5aKiP+Wi4j/lYyJ/5aNif+WjYn/
l46K/5eOiv+Ui4f/pp6b9Liwr8qQhYR7l46NJ5aNjQCXjo0AmY+PAI6DggCWjIsAn5eWAKCYlwCd
lJMAf3RzAMO9vQCPhIMAyMPDAKKamgCUiooAxcC/AMjDwgBvYmAAeGxqAIF2dQCMgoAAfnJxAHdr
aQBsXlwAxL6+AMS/vwCXjowApJuaANDLywCLgH8Aq6SjAJaMjACRh4YAq6OiALKrqgCZkY8AloyL
AK6npwCwqagAn5eWALOsqwCwqagLmpGPR3dqaZ1TQ0LoQC4t/z8sK/9EMTD/RTQy/0Y0M/9GNDP/
RjQz/0UzMv9ALSz/QzAv/3ZmYP+TipT/Pjx7/wAAWv8AAFn/AABa/wAAV/8AAFL/V1ed/8DB+/9q
bfT/JSnn/y0x6f8uM+n/LjLp/y8z6f8vMun/MDPr/y8z6/8PEYv/AABW/wAAW/8HB2D/m5zV/4yP
/f8qLen/MDPr/zE16/8xNev/MTXr/zE28/8xM9b/MyM5/y0YDv9OPT3/1s3NN+vk5ADk3NsA4Nza
AODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA
4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg3NoA4NzaAODc2gDg
3NoA////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AMLC3wDCwt8AwsLfAMLC3wDCwt8AwsLfAMLC3wDExOEAwsLfADs7nq4AAHz/AACB/wAAgf8CA3//
KCq8/xkb2v8YGtb/GBrW/xkb1/8ZG9f/GRvX/xkb1/8ZG9f/GhzY/xoc2P8aHNj/GhzY/xoc2P8S
FNf/PT/e2sXG9hbd3vsA3d7+AM7M3ADLx8QAvri2AKOcmgCwqqhIcmVi5GVXU/9/dHD/i4F9/4p/
e/+LgHz/i4B8/4uAfP+MgX3/jYJ+/42Cfv+Og3//joN//4+EgP+PhID/j4WB/46Fgf+PhYH/kIWC
/5GGgv+Sh4P/koeD/5GIhP+SiIT/komF/5KKhv+Tiob/lIqH/5WKh/+Vi4f/loyI/5WNif+WjYn/
l46K/5SLh/+elZH/r6aj/46BgPdlVlaze29vXJiOjhmUiokAmpCPAKObmgCimpkAnpWUAH90cwDD
vb0Aj4SDAMjDwwCimpoAlIqKAMXAvwDIw8IAb2JgAHhsagCBdnUAjIKAAH5ycQB3a2kAbF5cAMS+
vgDEv78Al46MAKSbmgDQy8sAi4B/AKukowCWjIwAkYeGAKujogCzrKsAm5SSAJqRkAC0rq4Ar6in
F42Dgk56bmyZWUpJ3UQzMf8+LCr/QS4t/0QxMP9FMzL/RTMy/0UzMv9FNDL/QzEw/z0rKv9DMTD/
dGVh/7uxrP+Vka7/Hx9s/wAAVP8AAFn/AABZ/wAAVP8DA1j/cnOz/76///9YXPD/JCnm/yww6P8u
Muj/LTLo/y4y6P8uMuj/LzPq/zA17/8VF5z/AABX/wAAW/8AAFj/fn++/6Wn//8xNev/LTDq/zAz
6v8wM+r/MDTq/zE18f8wNOT/MyVP/y8aD/86KCb/wLe2XO/n5wDm3t4A5t7eAOXe3gDl3t4A5d7e
AOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A
5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAOXe3gDl3t4A5d7eAP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wC7u90Au7vd
ALu73QC7u90Au7vdALu73QC7u90Au7vdAMTE4QCfn88qBweF8QAAgv8AAIL/AAB9/xYXl/8hI9f/
FxnW/xga1v8YGtb/GBrW/xga1v8ZG9f/GRvX/xkb1/8ZG9f/GRvX/xoc2P8aHNj/GhzY/w8R1v9X
WeO22dr6BNvc+wDa2/4A19bmALy3sgCdlZMA0MzLAK6npSWBdnO+ZVdT/31ybv+LgHz/iX56/4p/
e/+Kf3v/i4B8/4uAfP+LgHz/i4B9/4yBff+Ngn7/joN//4+Df/+PhID/j4SA/4+Fgf+OhYH/j4WB
/5CGgv+RhoP/koeD/5KHg/+RiIT/kYiE/5KJhf+SiYX/k4qG/5SKhv+Viof/lYuI/5WMif+WjYn/
lIyH/5eOiv+tpaH/p52b/21eXv9LOjnrVUZEqoB1c2mbkpErpZ6dBaWdnACCd3YAyMLCAJCFhADJ
xMQAopqaAJSKigDFwL8AyMPCAG9iYAB4bGoAgXZ1AIyCgAB+cnEAd2tpAGxeXADEvr4AxL+/AJeO
jACkm5oA0czMAIuAfwCuqKcAmZCQAJaNjACwqagAs62rE4+Fgzp8cG96al1csFVFROtCMTD/PSop
/z8sK/9CMC//QzEw/0QyMf9EMjH/RDIx/0MyMP9ALSz/Oyko/0w7Ov9+cW//yL24/9XO0/9jYZT/
AQFX/wAAVf8AAFn/AABZ/wAAUf8UFGX/kJHL/7K0//9GSuz/JCnm/y0x5/8tMef/LTHo/y0x6P8t
Mej/LjLp/zA17/8aHKv/AABZ/wAAXP8AAFb/YmKo/7W2//88QOz/Ki3p/y8z6v8vNOr/MDPq/zAz
7v8wM+z/MSZm/zEcD/8wHRv/ppubaO/o5wDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7e
AObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A
5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8AtLXaALS12gC0tdoAtLXa
ALS12gC0tdoAtLXaALS12gC1tdoAvb7eAF1dr4EAAH//AACE/wAAgv8DA3//ISK9/xga2f8XGdX/
GBrW/xga1v8YGtb/GBrW/xga1v8YGtb/GBrW/xkb1/8ZG9f/GRvX/xkb1/8ZG9j/EhXW/2Zo5ZK8
vvYAx8j5AM7Q/QC9uckAn5eSAMrGwwC6tLIAvLa0B5KIhYdrXlr5eW1p/4l+ev+IfXn/iX56/4l+
ev+Kf3v/i4B8/4uAfP+LgHz/i4B8/4yBff+MgX3/jYJ+/46Df/+Pg3//j4SA/4+EgP+OhYD/joWB
/4+Fgf+QhYL/kYaD/5KHg/+SiIT/koiE/5GIhP+SiYX/komG/5OKhv+Uiof/lYqI/5aLiP+VjIj/
k4mF/5+Xk/+3sK3/pJqY/2RVU/84JiX/PSoo+VZGRNVsX16gbmJhdqqjokCOg4IjysXFCqaengCa
kZEAzsnIANDMywBxZGIAem5sAIN5eACPhYMAgHV0AHltawBuYF4AzMfHAMzIyACdlZMAqJ+eANLN
zQiNgoEempKQN4Z7e2RsXl2Ra11cvFZHRedFMzL/Pisq/zsoJ/8+LCv/QS8u/0IwL/9DMTD/QzEw
/0MxMP9CMC//QC0s/zspKP9BLy7/X1BO/5eLi//Sycb/6OHd/5+asf8jImn/AABQ/wAAV/8AAFn/
AABY/wAAUP8uL3z/q6zi/52f/v82Oej/JSnm/yww5/8sMOf/LDHn/y0x5/8tMef/LTDn/y808P8d
ILb/AQFb/wAAXP8AAFT/S02W/7u9/P9MUO//Jyvo/y8y6f8vMun/LzHp/y8y6/8vNPL/MCh5/zEd
Ef8rFxT/jYF/gOzl5QDn4N8A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7e
AObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A
5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AM/P5wDPz+cAz8/nAM/P5wDPz+cAz8/n
AM/P5wDPz+cAz8/nANTU6QDGxuILIyOTzgAAgP8AAIT/AACA/xESl/8dH9X/FhjW/xcZ1f8XGdX/
GBrW/xga1v8YGtb/GBrW/xga1v8YGtb/GBrW/xga1v8ZG9f/GRvX/xcZ1/8VF9b/fH7qfMzN+QDK
y/kAw8X8AK+szgDJxcAAuLCtALmzsQDIw8EArKSiRHptas92amb/hnt3/4d8eP+IfXn/iH15/4l+
ev+Jfnr/in97/4uAfP+LgHz/i4B8/4uAfP+MgX3/jIF9/42Cfv+Og3//joN//4+EgP+PhYH/j4WB
/4+Fgf+PhYL/kIWC/5GGgv+Sh4P/koiD/5KIhP+SiYT/komF/5OJhv+Uiob/lIqH/5WKiP+ViYf/
komF/6ObmP+8tbL/rqSj/3ZoZ/9CMS7/LhkY/zEeHf84JiT/SDc19FpJSN5fUE/EbF5eqoZ7eZSN
g4GAZlhWcm5hX2x1aWhmfnNxYXJlZGltYF5tZFVTc4uAf4GGfHuUb2JgqWJUU8FeTk3cTj088EIw
L/8+LCr/Oyko/zonJv88Kin/QC0s/0EvLv9BLy7/QS8u/0IwL/9CMC//QC4t/z0qKf87KCf/Py0s
/1ZGRP+Ed3b/urCw/97X1f/l3tj/ta+z/0xJef8AAFT/AABT/wAAWP8AAFj/AABT/wAAVP9VVpv/
vL31/36B+P8pLeb/Jivl/ywv5v8rL+b/LDDm/yww5/8sMOf/LDDn/y8z7/8fIr7/AgJd/wAAV/8A
AFT/OjuJ/7u9+P9dYPL/JSnm/y4y6P8uMuj/LjLp/y8y6v8vM/P/LyiL/zEdFP8pFBD/dWdlmeXd
3QDm394A5t/eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7e
AObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A
5t7eAObe3gDm3t4A5t7eAObe3gDm3t4A5t7eAP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wDY2OsA2NjrANjY6wDY2OsA2NjrANjY6wDY2OsA2Njr
ANjY6wDY2OsA4+PxAJaWyz0EBIP5AACD/wAAhP8BAYH/GBq4/xcZ2f8XGdT/FxnV/xcZ1f8XGdX/
FxnV/xga1v8YGtb/GBrW/xga1v8YGtb/GBrW/xkb1/8ZG9f/FRfX/xkb1/+Pke1q1dX7AMXG+QCw
svoAsbDhALu1sAC4sq4Awry6AMO9uwDCvLoNlYuJgnltaPKCd3P/hnt3/4d8eP+HfHj/h3x4/4h9
ef+Jfnr/in97/4p/e/+Kf3v/i4B8/4uAfP+MgX3/jIF9/42Cfv+Ngn7/joN//4+Df/+PhID/j4WB
/46Fgf+PhYH/j4WC/5CGgv+ShoP/koeD/5KIhP+SiIT/komF/5KJhf+TiYb/lIqG/5SKh/+TiYb/
k4iF/6GYlf+7s7H/vbWz/5qOjf9pWFf/QS8u/zAdHP8uGhj/Mx8c/zUiIP8zIB//NSIg/z0qKP88
Kin/PCko/z0rKP89Kyj/PSsp/z0rKv83JCL/NyQh/zgmJf85JiX/OSYl/zwqKf8+LCv/Py0s/0Au
Lf9ALi3/QC4t/0AuLf9ALi3/Py0s/zwpKP85JiX/Oicm/0QzMf9fUE7/inx8/7iurf/Z0dH/3tfW
/9LLxf+2r6r/amaC/xMTWv8AAFD/AABX/wAAWP8AAFf/AABP/xISY/+Gh8H/urz//1pe7/8iJuP/
KCzl/ysv5v8rL+b/Ky/m/ysv5v8rL+b/Ky/m/y4y7/8gI8P/AwNg/wAAVf8AAFH/Li58/7q78/9r
bvX/JCjm/y0x6P8tMuj/LjLo/y4x6f8tM/T/LimZ/zEeF/8nEw7/ZlZVv+Hb2gzn4eAA5d7dAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8AyMjjAMjI4wDIyOMAyMjjAMjI4wDIyOMAyMjjAMjI4wDIyOMAyMjj
AMjI4wDS0ugAX1+xggAAfv8AAIT/AACB/wgJkP8XGtD/FhjW/xYY1P8WGNT/FxnV/xcZ1f8XGdX/
FxnV/xcZ1f8YGtb/GBrW/xga1v8YGtb/GBrW/xkb1v8UFtb/Gh3W/pSW7mTQ0fsArrD1AKOl9wDJ
yfAAs62xAMK9tgC+uLUAx8LBALmysQCspaMyioF9r390cP+EeXX/hnt3/4Z7d/+HfHj/h3x4/4d8
eP+IfXn/iX56/4p/e/+Kf3v/in97/4uAfP+LgHz/jIF9/4yBff+Ngn7/jYJ+/46Df/+PhH//j4SA
/4+EgP+OhYH/joWB/4+Fgv+RhoL/koeD/5KHg/+SiIT/kYiE/5KJhf+SiYX/k4qG/5SKhv+TiIb/
koaE/5uQjf+wp6X/wrq4/720tP+flJT/eGlp/1ZFQ/9ALSv/NCEg/zEfHv80IR//NyQi/zgmJP85
Jyb/Oygn/z0qKP89Kin/PCop/z0rKf8+Kyr/Pisq/z0rKv89Kyn/PSsq/zspKP86KCf/OCYl/zcl
JP83JST/Oyko/0c2Nf9fT07/fnFw/6WZmP/Iv7//29TT/9nS0f/KwsD/u7Os/6+ooP9+eYn/Kyll
/wAAUv8AAFL/AABU/wAAVf8AAFP/AABP/zw9hf+vsOX/n6H+/zs/6P8iJuP/KS3l/you5f8qLuX/
Ki/l/yov5f8rL+b/Ky/m/y0x7v8hJMb/AwRj/wAAVf8AAFL/JiZ2/7a37v92eff/JSnm/yww5/8t
Mef/LTHo/y0x6P8tMvT/Liqj/zAdG/8nEwz/WEhGx9nR0RPr5eQA5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////ANTU6QDU1OkA1NTpANTU6QDU1OkA1NTpANTU6QDU1OkA1NTpANTU6QDU1OgA2Njr
AM3N5QgtLZi8AAB+/wAAhP8AAID/Cw2o/xcZ2P8WGNT/FhjU/xYY1P8WGNT/FhjU/xcZ1f8XGdX/
FxnV/xcZ1f8XGdX/GBrW/xga1v8YGtb/GBrW/xMV1f8bHdb9j5HuaLq7+ACmp/QAxcf+AKCh6QDE
wNEAv7m0AMXAvgC0rawAvbe2AK6npQCmn5xZiX560YB1cf+DeHT/hnt3/4Z7d/+Ge3f/h3x4/4d8
eP+HfHj/iH15/4l+ev+Kf3v/in97/4uAfP+LgHz/i4B8/4yBff+MgX3/jYJ+/42Cfv+Og3//j4SA
/4+EgP+PhYH/j4WB/4+Fgf+QhYL/kYaC/5GHg/+Sh4P/koiE/5GIhP+RiYX/komF/5OKhv+TiYX/
kYeE/5OIhf+elJH/samm/8K6uP/Gv73/vLOy/6ecm/+Mf37/c2Vk/2BQTv9SQT//RzU0/z8tLP87
KSf/OiYk/zglI/83JCP/NyUk/zonJf88KSj/Py0s/0UzMv9PPj3/W0tK/2xdXP+CdHP/nJCP/7as
q//MxMP/2NHQ/9nS0f/Px8X/vbSx/62lof+qoZr/q6Ka/4uFjf9APW7/BARU/wAAUP8AAFT/AABU
/wAAU/8AAEv/Dw9d/3d4tP+9vvv/dHb1/ycr5P8kKOP/KS3k/ykt5P8pLeT/Ki7l/you5f8qLuX/
Ki7l/y0x7f8gJMX/BARi/wAAVf8AAFL/ISJy/7Kz6f9/gfj/JSnl/you5v8sMOf/LDDn/y0x5/8s
MvP/LSqo/y8dHv8nEwv/TT07z83FxBro4uEA5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wDZ2ewA2dnsANnZ7ADZ2ewA2dnsANnZ7ADZ2ewA2dnsANnZ7ADZ2ewA2dnsANnZ7ADe3u4As7PZ
IhQUjOUAAIH/AACD/wEBhf8QE8L/FhjX/xUX0/8WGNT/FhjU/xYY1P8WGNT/FhjU/xYY1P8XGdX/
FxnV/xcZ1f8XGdX/FxnV/xga1v8YGtb/ExXV/xoc1v97fep2sbL2AMbI+gCeoPYAvb79AMXD3gDD
vb0As6yoALq0sQCtpqQAvLa0ALKrqA+hmZaBhHp26oB0cP+EeXX/hXp2/4Z7d/+Ge3f/hnt3/4Z7
d/+HfHj/h3x4/4h9ef+Jfnr/iX56/4p/e/+LgHz/i4B8/4uAfP+MgX3/jIF9/42Cfv+Og3//joN/
/4+EgP+PhID/j4WA/46Fgf+OhYH/j4aB/5GGgv+Rh4P/koeD/5KIhP+SiIT/komF/5KJhf+Tiob/
k4mF/5KHhP+Rh4P/l42K/6Obl/+yqqf/wLm2/8nCwP/Mw8L/ycHA/8S8u/++tbT/t62t/7Kop/+w
pKT/rKGg/66kpP+yqKf/uK6t/7+2tf/Hvr3/zsXF/9TMy//X0M//1s/N/87GxP/Burf/tKyp/6mi
nv+impb/oJeT/6adlv+qopn/kImO/0pHcf8KClf/AABQ/wAAU/8AAFT/AABU/wAATv8AAE7/Pz+G
/6us4v+nqf//R0rq/x8j4f8mKuP/KS3k/ykt5P8pLeT/KS3k/ykt5P8pLeT/KS3l/ywx7f8fIsH/
AwRh/wAAVP8AAFH/IiJy/6+w5v+Eh/r/JSnl/ykt5v8rL+b/LC/m/yww5/8sMfP/LCmr/y8dIP8n
Ewr/RjUz1cC4tyDh29oA4draAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A2trtANra
7QDa2u0A2trtANra7QDa2u0A2trtANra7QDa2u0A2trtANra7QDa2u0A29vuAOLi8AB+fr9HAgKC
+gAAg/8AAIH/BQaW/xUX0v8VF9T/FRfT/xUX0/8VF9P/FhjU/xYY1P8WGNT/FhjU/xYY1P8WGNT/
FxnV/xcZ1f8XGdX/FxnV/xga1f8TFdX/FBbV/3R26YvJyvsDoqP0AL2++gC/wPwAwMHzAL25wgC8
trMAraWiALiysAC1r6wAv7q4ALiyryaako6kgXdy+oF1cf+EeXX/hHl1/4V6dv+Fenb/hnt3/4Z7
d/+Ge3f/h3x4/4d8eP+IfXn/iX56/4p/e/+Kf3v/i4B8/4uAfP+LgHz/i4F9/4yBff+Ngn7/jYJ+
/46Df/+PhID/j4SA/4+FgP+OhYH/j4WB/5CFgv+RhoP/koaD/5KIg/+SiIT/koiE/5KJhf+SiYX/
k4qG/5SJhv+TiIX/k4eF/5GIhP+TiYX/lo2J/5yTj/+impf/qqGe/7Copf+1rar/uLCt/7mxrv+5
sq7/ubGv/7evrP+zq6j/r6ej/6mhnf+km5j/n5aS/5yTjv+bko7/nJOP/56Vkf+gl5P/p52W/6ig
mP+Mhoz/S0dy/wwMWP8AAE//AABT/wAAVP8AAFT/AABR/wAAS/8bHGj/hITA/72+/f9zdvT/Jyvj
/yEl4f8oLOP/KCzj/ygs4/8oLOP/KCzj/ykt5P8pLeT/KS3l/ysw7P8cH7r/AgNf/wAAVP8AAFH/
IyNz/7Cx5/+Fh/r/JCjk/ygs5P8rL+b/Ky/m/ysv5/8rMPL/Kymq/y4cH/8nEwr/QzEv2LatrCbZ
0tEA2tPSAOHa2gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////ANvb6wDb2+sA29vrANvb
6wDb2+sA29vrANvb6wDb2+sA29vrANvb6wDb2+sA29vrANvb6wDb2+sA39/tAHNzunAAAID/AACD
/wAAgP8KC6z/FRjW/xQW0/8VF9P/FRfT/xUX0/8VF9P/FRfT/xYY1P8WGNT/FhjU/xYY1P8WGNT/
FhjU/xcZ1f8XGdX/FxnV/xUX1f8RFNT/XF/kr6Wm9BLDxPoAv8D6AL/A/QDJyeYAqai8AK+rrwC6
tLIAta+rALq1swDFwL4AxMC+AKqjoDyQhoOwfnNv/4B1cf+DeHT/hHl1/4R5df+Fenb/hXp2/4Z7
d/+Ge3f/hnt3/4d8eP+HfHj/iH15/4l+ev+Jfnr/in97/4uAfP+LgHz/i4B8/4uAfP+MgX3/jIF9
/46Cfv+Og3//joSA/4+EgP+PhYD/j4WB/4+Fgf+PhYL/kYaC/5KHg/+Sh4P/koiD/5KIhP+RiYT/
komF/5OKhv+Uiof/lIqH/5WKh/+Ui4f/lIuH/5OLh/+Ti4b/lIuH/5SLhv+VjIf/lYyI/5aNif+X
jor/mI6K/5mQjP+akY3/m5KO/5yTj/+dlJD/nZSQ/6CXkv+mnZT/pJuU/4J7h/9CP2z/CgtU/wAA
Tv8AAFL/AABU/wAAVP8AAFL/AABL/wgIV/9gYKD/ubnw/5ib/P89QOf/HSHg/yUp4f8nK+L/Jyvi
/ycr4v8nK+L/KCzj/ygs4/8oLOP/KS3k/yov6/8ZHLH/AQJa/wAAVf8AAFH/Jyh2/7W26/+Dhvn/
JCjk/ygs5f8qLuX/Ki7l/yov5v8qL/H/Kyip/y4bHv8mEgn/Py4s26+lpSnOxsUA0crJANrT0gDh
2toA5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wDb2+sA29vrANvb6wDb2+sA29vrANvb
6wDb2+sA29vrANvb6wDb2+sA29vrANvb6wDb2+sA29vrAODg7QDAwN8AQkKjigAAf/8AAIP/AQGE
/w8Qvv8VF9b/FBbS/xQW0v8UFtL/FRfT/xUX0/8VF9P/FRfT/xUX0/8WGNT/FhjU/xYY1P8WGNT/
FhjU/xYY1P8XGdX/FRfU/w4Q0/9AQt7SrrD2NMnK/AC/wPsAyMjjAJycugCursEAmJerAK2prwC/
urYAxb+7AMK9ugC2sK4ArKWjAKylok6RiITCfnNu/4B0cP+Cd3P/g3h0/4R5df+EeXX/hXp2/4V6
dv+Ge3f/hnt3/4d8eP+HfHj/iH15/4h9ef+Jfnr/in97/4p/e/+LgHz/i4B8/4uAfP+MgX3/jIF9
/42Cfv+Og3//joN//4+EgP+PhYD/j4WB/46Fgf+PhYH/j4aC/5GGgv+Sh4P/koeD/5KIhP+RiIT/
kYmF/5KJhf+Tiob/lIqH/5WKh/+Vi4j/lYyI/5WMif+WjYn/lo6J/5eOiv+Xjor/mI+L/5mQjP+Z
kIz/mpGN/5qSjf+ck47/oZeR/6Wck/+ZkI7/bml8/zEvY/8EBFH/AABN/wAAUP8AAlH/AAJR/wAA
Uv8AAEz/AABR/0ZHiv+pqt//ra/+/1hb7f8gJeD/ISXg/yYq4f8mKuH/Jirh/yYq4f8nK+L/Jyvi
/ycr4v8nK+L/KCzl/ykt6P8WGKP/AABW/wAAVP8AAE7/MTJ+/7m67/98gPf/Iyfj/ycr4/8pLeT/
KS3k/you5v8qL/D/Kieh/y0aG/8lEQj/QC8t2q2joynHv74Ax7++ANHKyQDa09IA4draAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A29zsANvc7ADb3OwA29zsANvc7ADb3OwA29zsANvc
7ADb3OwA29zsANvc7ADb3OwA29zsANvc7ADc3ewAzM3lALq63AJLS6ijAAB//wAAgf8DA4//ERPK
/xQW1P8UFtL/FBbS/xQW0v8UFtL/FBbS/xUX0/8VF9P/FRfT/xUX0/8VF9P/FhjU/xYY1P8WGNT/
FhjU/xYY1P8WGNT/DhDT/yos2fGIiu5ry8z+AM3N4wCenroArq7AAIiIpACbnLMAnJqrALe0vADA
u7oAta+rAKminwDHw8EAubSxAqWdmk+QhoK0gHVx+35zb/+BdnL/g3h0/4N4dP+EeXX/hHl1/4V6
dv+Fenb/hnt3/4Z7d/+Ge3f/h3x4/4h9ef+IfXn/iX56/4p/e/+LgHz/i4B8/4uAfP+LgHz/jIF9
/4yBff+Ngn7/joJ//46Df/+PhID/j4WA/46Fgf+OhYH/j4WB/5CGgv+RhoL/koeD/5KIhP+RiIT/
komE/5GJhf+SiYX/k4qG/5SKh/+Vioj/lYuI/5aMiP+WjYn/lo2J/5aOif+Xjor/mI+L/5yTjf+h
mI//nZSO/4N7g/9RTXD/HRxa/wAATf8AAEz/AABP/wAAUP8AAFD/AABQ/wAASf8AAE3/OTl//5ma
0P+2t/3/b3Lz/ykt4f8dId//JCjg/yUp4P8lKeD/Jirh/yYq4f8mKuH/Jirh/yYq4f8mKuH/KCzm
/ycr4v8RE5T/AABS/wAAVP8AAE//QEGJ/7u99P9zdvT/Iibi/ycr4/8pLeT/KS3k/ykt5v8pLu//
KiWV/ywaGP8kEAj/RDMx1bSsqyXGv74AwLe2AMe/vgDRyskA2tPSAOHa2gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////ANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc
7QDb3O0A29ztANvc7QDb3O0A29ztAN3e7gDm5/IA1NXpCT8/orAAAH//AACB/wYHm/8TFdD/ExXS
/xMV0f8UFtH/FBXR/xQW0v8UFtL/FBbS/xUX0v8VF9P/FRfT/xUX0/8VF9P/FhjU/xYY1P8WGNT/
FhjU/xYY1P8QEtP/ExbT/2Vn57K2t+RVo6O5F7CwvwCOjqcAnJyyAISEoACOj6oAb2+NALGtswCp
o6EAyMK+ALixrQC8trQAr6mmAKymojuWjYqbhHp15n5zb/9/dHD/gnZy/4J3c/+DeHT/hHl1/4R5
df+Fenb/hXp2/4Z7d/+Ge3f/h3x4/4d8eP+IfXn/iX56/4l+ev+Kf3v/i4B8/4uAfP+LgHz/i4B8
/4yBff+MgX3/jYJ+/46Df/+Og3//j4SA/4+EgP+OhYH/joWB/4+Fgv+QhoL/kYaD/5KHg/+Sh4P/
koiE/5KJhP+SiYX/komG/5OKhv+Uiof/lYqH/5aLiP+Zj4r/npSM/5qRi/+Hf4P/X1p0/y4sYP8I
CFL/AABM/wAATf8AAE//AQFP/wEBUP8AAE//AABI/wAATf80NHr/kJHI/7m6+/9/gfb/MjXj/xsf
3f8iJt//JCjf/yUp4P8lKeD/JSng/yUp4P8lKeD/Jirh/yYq4f8mKuH/KCzn/yMn2P8MDYD/AABP
/wAAVf8AAE//U1OY/77A+f9oa/L/HyTh/ycr4/8oLOP/KCzj/ygs5v8oLOv/KiOI/ywYE/8kEQn/
Sjo4z8C6uSDQysoAvra2AMC3tgDHv74A0crJANrT0gDh2toA5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc
7QDb3O0A29ztANvc7QDb3O0A3N3uANnZ7ADCwuELOzugswAAf/8AAIH/CAql/xQW1P8TFdL/ExXR
/xMU0f8TFdH/FBXR/xQW0v8UFtL/FBbS/xQW0v8VF9P/FRfT/xUX0/8VF9P/FRfT/xYY1P8WGNT/
FhjU/xQW1P8MDtL/MTPb/3x+1uWQkbGienmSQp6esgONjacAkZGqAFxdggCdnrUAmJitAKalswCt
qKoAvri1AK6nogC9t7MAs66rALOtqhqjm5hmjYSAuIN4dPF+c2//fnNv/4F2cv+DeHT/g3h0/4R5
df+Fenb/hXp2/4V6dv+Ge3f/hnt3/4d8eP+HfHj/iH15/4l+ev+Jfnr/in97/4p/e/+LgHz/i4B8
/4uAfP+MgX3/jYJ+/42Cfv+Og3//j4SA/4+EgP+PhYD/j4WB/46Fgf+PhYH/kIaC/5GGgv+Sh4P/
koiE/5GHg/+Qh4L/k4qE/5qRif+akIr/hnyC/11Wcf8wLWD/DAxS/wAAS/8AAEz/AABO/wEBT/8B
AU//AQFP/wAATf8AAEb/AQFO/zk5ff+Sk8r/ubr7/4OG9/83O+T/Gh7c/x8j3f8kKN//JCjf/yQo
3/8kKN//JCjf/yQo3/8lKeD/JSng/yUp4P8lKeH/Jyzo/x8iyf8HCG7/AABM/wAAUP8AAFL/amur
/76//v9YXO3/HSLg/yYq4v8nK+L/KCzi/yQo5P8mK+P9KCB1/yMOBv8jEAn/RjUzt8XAvxjd2tkA
x8HAAL62tgDAt7YAx7++ANHKyQDa09IA4draAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc
7QDb3O0A29ztANzd7gDU1OkAx8fjAMLC4QlCQqOuAAB+/wAAgv8LDK//FBXU/xMU0f8TFdH/ExXR
/xMV0f8TFNH/FBXR/xQV0v8UFtL/FBbS/xQW0v8UFtL/FRfT/xUX0/8VF9P/FRfT/xYY1P8WGNT/
FhjU/xAS0/8XGdj/UFLe/3Bxt/9kZIjMXV1+cYeHoSFmZokApKW5AJmZsgCBgqAAkJCpAKaltwCq
p7IAt7KzALOsqAC9t7IAurSwALGrqACspqMjpJ2ZZJOKhq2GfHffgHVx/390cP9/dHD/gXZy/4J3
c/+EeXX/hXp2/4Z7d/+Fenb/hnt3/4Z7d/+GfHj/h3x4/4h9ef+Jfnr/iX56/4p/e/+LgHz/i4B8
/4uAfP+LgX3/jIF9/4yBff+Og3//joN//46Df/+PhID/joN//42Cfv+KgXz/jYJ+/5OIgv+dkYn/
o5mU/5OMkP9rZ3//NzZn/wwLUv8AAEv/AABL/wAATP8AAE7/AABO/wABTv8AAE//AABK/wAARf8J
CVT/S0uL/52e0/+3ufz/gIL3/zc64/8ZHtz/HiLd/yMn3v8jJ97/Iyfe/yMn3v8jJ97/JCjf/yQo
3/8kKN//JCjf/yQo3/8lKeL/Jirn/xgbsf8DA13/AABO/wAATf8LC1n/h4jC/7a4//9GSen/HSHf
/yYq4f8nK+L/Jyvi/yAk4f81OejogIHcSouAfkRkVlGaYFJQm5CGhQzNyMcA19PTAMfBwAC+trYA
wLe2AMe/vgDRyskA2tPSAOHa2gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////ANvc7QDb
3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc
7QDc3e4A1NTpAMHC4ADKyeUAxMTiBkdIppoAAH//AACD/w0PtP8UFdT/ExTQ/xMV0P8TFdH/ExXR
/xMV0f8TFdH/ExTR/xMV0f8UFdL/FBbS/xQW0v8UFtL/FBbS/xUX0/8VF9P/FRfT/xUX0/8VF9P/
FBbT/w4Q1P8qLd//YWPc/2Znp/8+PmrxLS5ZsXNzkWOVla0fjI2nAJeXrgCcnbQAmpu0AJ+ftgCa
mKkAoJ2qAKqmrACxrKkAsq2oAL24tAC4sq0AqqOeE56Vkjyfl5Nwlo2Kqol/e8yGfHj0gXZy/39z
b/+CdnL/gHVw/4F2cv+DeHT/hHl1/4R5df+Fenb/hXp2/4Z7d/+Ge3f/h3x4/4h9eP+JfXn/iX56
/4l9ef+HfHj/iX15/4p/ev+Jfnn/kIR++ZaMhemhl5Dqs6uk/7Otq/+dmKP/dXKP/0BAcv8VFVj/
AABK/wAASP8AAEz/AABO/wAATv8AAE7/AABO/wAAS/8AAEX/AABH/x4eZf9mZ6P/rKzj/6+x/v9y
dfP/MTXh/xkd2/8dIdz/Iibd/yIm3f8iJt3/Iibd/yIm3f8jJ97/Iyfe/yMn3v8jJ97/Iyfe/yQo
3v8lKuX/Iyje/xETlP8AAFH/AABQ/wAASv8gIGz/oqTZ/6Wn/v81OeT/HiLf/yYq4f8mKuH/Jirh
/x0h4P82OuPLkJLzKre25ACnn6gAsauoAJqRkACVjIwAycPDANfT0wDHwcAAvra2AMC3tgDHv74A
0crJANrT0gDh2toA5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDb3O0A29ztANvc7QDb
3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A3N3uANTU
6QDBwuAAwcLhANva7QCvr9cASkunggEBg/8AAIT/DxG3/xIU1P8SFND/EhTQ/xIU0P8SFND/ExXR
/xMV0f8TFdH/ExXR/xMV0f8UFdH/FBXS/xQW0v8UFtL/FBbS/xQW0v8VF9P/FRfT/xUX0/8VF9P/
ERPS/xAT1f83OeP/bG7e/2hqqv8xMWT/GhpN8iwtW7pkZId4jIymOJ6etA2horgAlpavAGtrkACd
nrYAk5KpAJ6drQDDwcgAoZ6lAKqlpACooZ4At7GrALu2sQCro6ADsqynJJySjDqtpqNmlYyIe56W
kZ6ZkIy/kIaCyYuBfcyNg3/njYN+9I2CfvWNg372jYN+9Y2Df/SRhoLvjYN+z5KIg8iZj4rAp56Z
sKmgmXqlnZlmtq+sSZGLkjippK1Hk5GonGhokP81NW//Dg5U/wAAR/8AAET/AABI/wAAS/8AAEv/
AABL/wAATf8AAEz/AABG/wAARP8MDFX/QkOD/4uLwv+0tfH/nqD8/11g7f8nKt//GBvb/x0h3P8h
Jdz/ISXc/yEl3P8iJt3/Iibd/yIm3f8iJt3/Iibd/yIm3f8iJt3/Iyfd/yMn3/8lKef/HiHJ/wkL
dv8AAEz/AABP/wAAS/8/QIb/t7jt/4yO+P8nK+D/HiPf/yUp4P8lKeD/JCjg/x0h3/9SVeeymJrx
F5qc9ACwr+MAopqjAKminwCUiokAlIqKAMnDwwDX09MAx8HAAL62tgDAt7YAx7++ANHKyQDa09IA
4draAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A29ztANvc7QDb3O0A29ztANvc7QDb
3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANzd7gDU1OkAwcLgAMLC
4QDX1usAo6PRAJ+g0ABvcLpkBQWE8wAAg/8QEbj/ExTT/xET0P8SFM//EhTQ/xIU0P8SFND/EhXQ
/xMV0f8TFdH/ExXR/xMV0f8TFdD/ExXR/xQW0v8UFtL/FBbS/xQW0v8UFtL/FRfT/xUX0/8VF9P/
DxHS/xET1f85POP/b3Ll/3N1u/9AQXb/CwtD/wMDPf8dHVPiRERxsWVliXhaWoJFnp61IYiIpAWi
o7sAwMHRAICBnwCnp7sAT052AImImwCqqLYAwL3DAK+rrgCLho4Aw769AJyUkgDHwsIAvrm4AKOd
mgCim5gA19LRDdPPzRbMx8YWxcDAFc7JxxLV0c4P3NnXB8C8uQCgmp8At7W8B6emuSB0c5M6ZGOK
a09PgKAnJ2XQDw9T8wAARv8AAD//AABC/wAARv8AAEj/AABK/wAASv8AAEn/AABI/wAAQ/8AAEL/
CAhR/zQ1d/91dq7/qarj/6+w/P+Agvb/QUTl/x0g3P8XG9n/HiLb/yAk3P8hJN3/ISPd/yEk3f8h
Jdz/ISXc/yEl3P8hJdz/Iibd/yIm3f8iJt3/Iibd/yMn4f8jJ+L/Fhmr/wMEXf8AAE3/AABN/wQE
U/9oaKf/vsD7/2xv8f8eIt7/ICTe/yQo3/8lKd//ISXf/yEl3/9VV+eKoKHyBaut8wCUlvMAsK/j
AKKaowCpop8AlIqJAJSKigDJw8MA19PTAMfBwAC+trYAwLe2AMe/vgDRyskA2tPSAOHa2gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////ANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb
3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDc3e4A1NTpAMHC4ADCwuEA19brAKKi
0QCam84Anp7PAHFxuj8fH5HZAACC/xIStf8TFNP/ERHQ/xESz/8RE8//EhTQ/xIU0P8SFND/EhTQ
/xIU0P8TFdH/ExXR/xMV0f8TFdH/ExXR/xMV0f8TFdH/FBbS/xQW0v8UFtL/FBbS/xQW0v8VF9P/
EBHS/w4Q0/8vMeD/Z2nr/4KE1v9maKH/LS5k/wAAO/8AADD/AAA6/xQUTfMkJFraR0d1tmFhiJVi
Yod0fX2cTi4uZD5papAsnp+4GsvM2Q6kpbwGMTFjA1ZUewJZV3sBXFyAAVlYfgA/P2kBqKe5AtbW
3gazs8YPj4+qHVRUgTFvbpM7i4unWV9fiHxhYY2eNzhvviMjX+AQEFL2AABF/wAAQf8AAD//AABD
/wAARv8AAEf/AQBI/wEASP8AAEj/AABG/wAAQv8AAEH/AABD/w4OVf87O3v/dHWu/6an3/+ys/v/
jpH5/1RW6/8mKN//FRnZ/xkd2f8eItv/ICPc/yAj3P8gJNv/ICTb/yAk2/8gJNz/ICTc/yEk3f8h
JNz/ISXc/yEl3P8hJdz/Iibd/yMo5P8fI9H/DQ+E/wAATv8AAE//AABL/xoaZf+Tlcv/s7X//0pN
6P8ZHtz/Iibe/yQo3/8kKN//HyPe/yQo3/CChO1lqqvzAJeZ8ACnqfMAlJbzALCv4wCimqMAqaKf
AJSKiQCUiooAycPDANfT0wDHwcAAvra2AMC3tgDHv74A0crJANrT0gDh2toA5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb
3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A3N3uANTU6QDBwuAAwsLhANfW6wCiotEAmZrOAJKS
ygCbm84AkJDJGTo6nq4AAIH/DxCt/xQW0v8QEtD/ERLP/xERz/8REs//ERPP/xIT0P8SFND/EhTQ
/xIU0P8TFNH/ExXR/xMV0f8TFdH/ExTR/xMV0f8TFdH/FBbS/xQW0v8UFtL/FBbS/xUX0v8UFtL/
ERPS/wwO0f8cH9n/Sk3n/3l76v+HiNH/a2yi/zk6bv8MDEf/AAA0/wAAL/8AADL/AAA5/wAAPP8G
B0X/Dw9L+hkZUuwkJFrkJCRZ3hYVT9wcG1TXIB9Y1B8eV9QeHVbVFhVQ3CUlXd0nJ2DiHBxY6RER
UfQICEv/AABE/wAAQf8AAED/AAA+/wAAQP8AAEL/AABD/wAARf8AAEb/AABG/wAARv8AAEb/AABD
/wAAQf8AAD7/AABA/wgHTf8oKGj/V1eS/4mKwf+sruf/ra/7/4qM+P9WWOz/KSze/xYa2P8XG9j/
HB/b/x8h3P8fIdz/HyLb/x8i2v8fI9r/HyPb/yAj3P8gI9z/ICTb/yAk2/8gJNv/ICTc/yAk3f8h
JN3/IiXh/yIm4f8WGa7/BQVh/wAASf8AAEz/AABK/0REif+2t+z/lJb6/y0x4P8aH9z/Iyfe/yMn
3v8jJ97/Gx/d/zU44c+Pku46uLn0AKip8gCWmPAAp6nzAJSW8wCwr+MAopqjAKminwCUiokAlIqK
AMnDwwDX09MAx8HAAL62tgDAt7YAx7++ANHKyQDa09IA4draAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb
3O0A29ztANvc7QDb3O0A29ztANzd7gDU1OkAwcLgAMLC4QDX1usAoqLRAJmazgCSksoAlJTLAJeX
zAChodEBXl6xcA8PifMLC6P/FBbP/xAS0f8RE87/ERPO/xESz/8REc//ERLP/xIT0P8SFND/EhTQ
/xIU0P8SFND/EhTQ/xMV0f8TFdH/ExXR/xMV0f8TFdH/ExXR/xQW0f8UFtL/FBbS/xQW0v8UFtL/
ExXS/w4Q0f8PEdP/JSjc/1BS6P96fOz/jI7d/3+Au/9cXZL/NjZs/xQVT/8AAD7/AAA2/wAAM/8A
ADT/AAA1/wAAN/8AADz/AAA9/wAAPv8AAD7/AAA//wAAQP8AAD3/AAA+/wAAQP8AAEL/AABD/wAA
RP8AAET/AABE/wAARP8AAEP/AABC/wAAQf8AAD//AAA9/wAAPP8AAD//AwRI/xcYWv84OHb/XV6Y
/4iIvv+mqOD/rq/1/5qc+v90dvT/RUjn/yMm3P8WGdj/FhnY/xsd2v8eINv/HiHb/x4h2v8eItr/
HiLa/x8h2/8fIdz/HyLc/x8i2/8fI9r/HyPa/x8j2/8fI9v/ICPc/yAk2/8gJd3/Iibk/xwfy/8M
DYD/AABN/wAAS/8AAEf/DxBb/3x9t/+9vv3/Z2rv/x0h3P8dItz/Iibd/yIm3f8fJN3/Gh7c/1VY
5qKUlu8Wrq/zALCx8wCnqPIAlpjwAKep8wCUlvMAsK/jAKKaowCpop8AlIqJAJSKigDJw8MA19PT
AMfBwAC+trYAwLe2AMe/vgDRyskA2tPSAOHa2gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////ANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb
3O0A29ztANvc7QDc3e4A1NTpAMHC4ADCwuEA19brAKKi0QCZms4AkpLKAJSUywCUlMsAl5bMALOz
2gCDg8IyJSWSugoKmv8SE8f/EBLS/w8Szv8RE8//ERPP/xETz/8REs//ERLP/xESz/8SE9D/EhTQ
/xIU0P8TFNH/ExTQ/xMU0f8TFdH/ExXR/xMV0f8TFNH/ExXR/xQV0f8UFtH/FBbS/xQW0v8UFtL/
FBbT/xIU0v8ND9H/DhHS/yAi2f9AQuT/Zmjt/4OF7P+PkeH/iYvK/3d3r/9bXJH/QUF3/ysrYv8Z
GVT/CwtI/wIDQf8AADz/AAA7/wAAOv8AADn/AAA4/wAAOP8AADn/AAA6/wAAPP8AADz/AAA+/wAA
QP8AAET/BwdL/xMUVf8iI2H/NTVy/01OiP9ra6P/iIm+/52f2P+oquz/paf2/5OV+f9xc/P/TE7o
/ywu3/8aHNr/ExXY/xYY2f8bHdr/HR/b/x0f2/8dINr/HSDZ/x0g2v8eINv/HiDb/x4h2/8eIdr/
HiLa/x4i2v8fIdv/HyHc/x8h3P8fItv/HyPa/x8j2/8hJOL/HyLa/xIUn/8EBFv/AABI/wAASv8A
AEj/PDx//6ys4f+kpf3/PkHk/xgc2v8gJNz/ISXc/yEl3f8cIdz/JSre7nN26myio/EAo6TxAKan
8gCwsfMAp6jyAJaY8ACnqfMAlJbzALCv4wCimqMAqaKfAJSKiQCUiooAycPDANfT0wDHwcAAvra2
AMC3tgDHv74A0crJANrT0gDh2toA5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDb3O0A
29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb
3O0A3N3uANTU6QDBwuAAwsLhANfW6wCiotEAmZrOAJKSygCUlMsAlJTLAJeWzACqqtYAjo7IAJeY
zAVtbbRxGRmX5w8Quf8PEdH/DxHP/xASzv8QEs7/ERPP/xETz/8REs//ERLP/xESz/8REs//EhPQ
/xIU0P8SFND/EhTQ/xIU0P8TFdH/ExXR/xMV0f8TFdH/ExXR/xQU0v8UFdH/FBbS/xQW0v8UFtL/
FBbS/xQW0v8SFNL/DxHS/wwO0f8QEtP/ICLZ/zg64v9UVur/cHHw/4WH8f+SlOz/lpjk/5SW2v+O
kM7/iInD/4GCuf96e7D/dHWq/29vpf9ub6X/bm+l/29vpf90dav/e3yw/4OEuf+LjMT/lJXP/5yd
2/+io+b/pafv/6Ol9f+Ymfn/hIb3/2ts8f9PUOj/Njjh/yIk2/8VF9j/EhTX/xQW2P8YGtn/Gx3a
/xwe2v8cHtr/HB7a/xwe2v8cHtv/HR/b/x0f2/8dH9r/HSDa/x0g2f8dINr/HiDb/x4g2/8eIdr/
HiHa/x4i2v8eItv/HyHc/yAj4v8gI+D/Fxq1/wcIbv8AAEn/AABK/wAARv8TE1z/enu0/72//P9y
dfH/ISTc/xod2/8hJN3/ISXd/x8j3P8aHtv/ODvgwoGD6zSytPMAnqDwAJ+g8ACmp/IAsLHzAKeo
8gCWmPAAp6nzAJSW8wCwr+MAopqjAKminwCUiokAlIqKAMnDwwDX09MAx8HAAL62tgDAt7YAx7++
ANHKyQDa09IA4draAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A29ztANvc7QDb3O0A
29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANzd7gDU
1OkAwcLgAMLC4QDX1usAoqLRAJmazgCSksoAlJTLAJSUywCXlswAqqrWAImJxgCams4AsLDYAJCQ
xiNNTaieGBmu+gwOy/8OEND/DxHO/w8Szv8QEs7/EBLO/xETz/8RE8//ERPP/xESz/8REc//ERLP
/xIT0P8SFND/EhTQ/xIU0P8SFND/ExXR/xMV0f8TFdH/ExXR/xMV0f8TFdH/ExXR/xQW0v8UFtL/
FBbS/xQW0v8VF9P/FBbT/xMV0v8QEtL/DQ/R/wwO0f8PEdP/FRjW/yEj2v8vMd7/PT/j/0pM5/9W
WOr/X2Lt/2dp7/9tb/H/cXLx/3Fz8v9xc/L/b3Hx/2lr8P9iZO7/WVzs/05R6P9CROX/NTfh/ygq
3P8cHtn/FRfX/xET1v8RE9b/ExXW/xUX1/8YGtj/GhzY/xsd2f8bHdn/Gx3Z/xsd2f8bHdn/HB7a
/xwe2v8cHtr/HB7a/xwe2v8cHtr/HB7a/x0f2/8dH9v/HR/b/x0g2v8dINr/HSDa/x4g2/8eINv/
HyLf/x8j4P8ZHMP/Cwx//wAATP8AAEj/AABI/wAAS/9JSov/sbLm/6Ok/f8+QeT/Fxra/x0i2/8g
JNv/ICTb/xoe2/8gI936Y2bniZye7wuPku4AqqzyAJ2f8ACfoPAApqfyALCx8wCnqPIAlpjwAKep
8wCUlvMAsK/jAKKaowCpop8AlIqJAJSKigDJw8MA19PTAMfBwAC+trYAwLe2AMe/vgDRyskA2tPS
AOHa2gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////ANvc7QDb3O0A29ztANvc7QDb3O0A
29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDc3e4A1NTpAMHC4ADC
wuEA19brAKKi0QCZms4AkpLKAJSUywCUlMsAl5bMAKqq1gCJicYAmJjNAKWl0gCnptMAoKDQAHh4
ujpJSbO1FBXA/gkJzf8OD87/EBHO/w8Rzv8QEs7/DxHO/xASzv8RE8//ERPP/xESz/8REc//ERLP
/xETz/8SE9D/EhTQ/xIU0P8SFND/ExTQ/xMV0f8TFdH/ExXR/xMV0f8TFdH/ExXR/xMV0f8UFtL/
FBbS/xQW0v8UFtL/FRfT/xUX0/8VF9P/FRfT/xQW0/8TFdP/EhTT/xAS0/8PEdL/DhDS/w0P0v8N
D9L/DhDT/w4Q0/8OENP/DhDT/w4Q0/8OENP/DxHU/xAS1P8RE9T/EhTV/xQW1f8VF9b/FxnX/xga
1/8ZG9f/GRvX/xoc2P8aHNj/GhzY/xoc2P8aHNj/GhzY/xsd2f8bHdn/Gx3Z/xsd2f8bHdn/HB7a
/xwe2v8cHtr/HB7a/xwe2v8cHtr/HB7a/x0f2/8dH9v/HR/b/x0f2v8dId7/HyHh/xocyf8NDon/
AQFR/wAAR/8AAEj/AABF/ygobv+TlMr/urv+/2Vo7v8dINv/GBzZ/x8j2/8gI9v/HSHc/xca2v84
O9/PiozsQLGz8wCgou8Aio3tAKqs8gCdn/AAn6DwAKan8gCwsfMAp6jyAJaY8ACnqfMAlJbzALCv
4wCimqMAqaKfAJSKiQCUiooAycPDANfT0wDHwcAAvra2AMC3tgDHv74A0crJANrT0gDh2toA5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A
29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A3N3uANTU6QDBwuAAwsLhANfW6wCi
otEAmZrOAJKSygCUlMsAlJTLAJeWzACqqtYAiYnGAJiYzQClpdIAoqHRAJeXzACbm84Ak5PHAHp6
v0dJScS5ERHJ/wcHzf8ODs3/EBHN/w8Rzv8PEc7/EBLO/w8Szv8QE87/ERPP/xETz/8REs//ERHP
/xESz/8REs//EhPQ/xIU0P8SFND/EhTQ/xIU0f8TFdH/ExXR/xMV0f8TFdH/ExXR/xMV0f8UFtH/
FBbS/xQW0v8UFtL/FBbS/xUX0/8VF9P/FRfT/xUX0/8VF9P/FhjU/xYY1P8WGNT/FhjU/xYY1P8W
GNT/FhjU/xcZ1f8XGdX/FxnV/xcZ1f8XGdX/GBrW/xga1v8YGtb/GBrW/xga1v8YGtb/GRvX/xkb
1/8ZG9f/GRvX/xkb1/8aHNj/GhzY/xoc2P8aHNj/GhzY/xoc2P8aHNj/Gx3Z/xsd2f8bHdn/Gx3Z
/xwe2v8cHtr/HB7a/xwe2v8cHtr/HB7b/x0f3/8eIOP/GRzJ/w0OjP8CA1b/AABG/wAASP8AAEP/
FBRc/3V2rv+8vfb/iYv3/y8z3v8VGdj/HSDb/x8i3P8fIdz/GBva/yAk2/lkZuaHoKLvDq2u8QCp
q/EAnZ/vAIqN7QCqrPIAnZ/wAJ+g8ACmp/IAsLHzAKeo8gCWmPAAp6nzAJSW8wCwr+MAopqjAKmi
nwCUiokAlIqKAMnDwwDX09MAx8HAAL62tgDAt7YAx7++ANHKyQDa09IA4draAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A
29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANzd7gDU1OkAwcLgAMLC4QDX1usAoqLRAJmazgCS
ksoAlJTLAJSUywCXlswAqqrWAImJxgCYmM0ApaXSAKKh0QCXl8wAlpbMAIuLxgChoc8Arq3UAIiI
z0lDQ824Dw/M/wYGzP8ODs3/DxDN/xARzf8QEc7/EBLO/xARzv8QEs7/ERLO/xETz/8RE8//ERLP
/xERz/8REs//EhPP/xIUz/8SFND/EhTQ/xIU0P8SFND/ExXQ/xMV0f8TFdH/ExXR/xMV0f8TFdH/
ExXR/xQW0v8UFtL/FBbS/xQW0v8VF9P/FRfT/xUX0/8VF9P/FRfT/xYY1P8WGNT/FhjU/xYY1P8W
GNT/FhjU/xYY1P8XGdX/FxnV/xcZ1f8XGdX/FxnV/xga1v8YGtb/GBrW/xga1v8YGtb/GBrW/xkb
1/8ZG9f/GRvX/xkb1/8ZG9f/GRvX/xoc2P8aHNj/GhzY/xoc2P8aHNj/GhzY/xsd2f8bHdn/Gx3Z
/xsd2f8bHdr/HR/g/x0f4P8YGsT/DQ6K/wMDVf8AAEP/AABH/wAARP8LC1T/Xl+a/7O06f+govz/
RUnk/xcZ2f8ZHNr/HiHb/x4i2f8aHtn/GRza/zw+4bqQku06s7TzAKWn8ACmp/AAqavxAJ2f7wCK
je0AqqzyAJ2f8ACfoPAApqfyALCx8wCnqPIAlpjwAKep8wCUlvMAsK/jAKKaowCpop8AlIqJAJSK
igDJw8MA19PTAMfBwAC+trYAwLe2AMe/vgDRyskA2tPSAOHa2gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////ANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A
29ztANvc7QDb3O0A29ztANvc7QDc3e4A1NTpAMHC4ADCwuEA19brAKKi0QCZms4AkpLKAJSUywCU
lMsAl5bMAKqq1gCJicYAmJjNAKWl0gCiodEAl5fMAJaWzACLi8YAm5vNAKen1ACwsNgAr6/ZAImJ
2UhAQdK4DQ7M/wYHy/8NDc3/DxDN/xAQzf8QEc3/DxHN/xARzv8QEc7/EBLO/xETzv8RE8//ERPP
/xESz/8REs//ERLP/xETz/8SFM//EhTQ/xIU0P8SFND/ExTR/xMV0P8TFdH/ExXR/xMV0f8TFdH/
ExXR/xQV0f8UFtL/FBbS/xQW0v8UFtL/FRfT/xUX0/8VF9P/FRfT/xUX0/8WGNT/FhjU/xYY1P8W
GNT/FhjU/xYY1P8WGNT/FxnV/xcZ1f8XGdX/FxnV/xga1v8YGtb/GBrW/xga1v8YGtb/GBrW/xga
1v8ZG9f/GRvX/xkb1/8ZG9f/GRvX/xkb1/8aHNj/GhzY/xoc2P8aHNj/GhzY/xsd2/8cHuD/Gx3Z
/xQXuP8LDH//AgJR/wAAQv8AAEX/AABC/wgIT/9RUY7/qqvg/62v/f9aXOv/Gx3a/xUY2P8dINn/
HSDa/xwe2v8XGdr/KSzc4Gxu5mibnO4EqqvxAKyt8gCipPAApqfwAKmr8QCdn+8Aio3tAKqs8gCd
n/AAn6DwAKan8gCwsfMAp6jyAJaY8ACnqfMAlJbzALCv4wCimqMAqaKfAJSKiQCUiooAycPDANfT
0wDHwcAAvra2AMC3tgDHv74A0crJANrT0gDh2toA5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A
29ztANvc7QDb3O0A3N3uANTU6QDBwuAAwsLhANfW6wCiotEAmZrOAJKSygCUlMsAlJTLAJeWzACq
qtYAiYnGAJiYzQClpdIAoqHRAJeXzACWlswAi4vGAJubzQCnp9QAqanXAKio2QCzs+AAuLjjAI6P
4EVERteoEhPN9gYHy/8LDMz/Dw/N/w8Qzf8PEM3/DxHN/xARzv8QEs7/DxHO/xASzv8QEs7/ERPP
/xETz/8REs//ERLP/xESz/8RE8//EhTP/xIU0P8SFND/ExTQ/xIV0P8TFdH/ExXR/xMV0f8TFdH/
ExXR/xMV0f8UFdH/FBbS/xQW0v8UFtL/FBbS/xUX0/8VF9P/FRfT/xUX0/8VF9P/FRfT/xYY1P8W
GNT/FhjU/xYY1P8WGNT/FhjU/xcZ1f8XGdX/FxnV/xcZ1f8YGtb/GBrW/xga1v8YGtb/GBrW/xga
1v8YGtb/GRvX/xkb1/8ZG9f/GRvX/xkb1/8ZG9n/Gx3e/xsd3/8YGs//ERKk/wgIbv8BAEj/AABB
/wAARP8AAED/CAhP/05Oi/+lptz/srT9/2Vo7v8gItv/ExXY/xsd2v8dH9v/HB7b/xUY2v8eIdn0
VVjikJeY7hyWmO0Am5zuAKSl8ACsrfIAoqTwAKan8ACpq/EAnZ/vAIqN7QCqrPIAnZ/wAJ+g8ACm
p/IAsLHzAKeo8gCWmPAAp6nzAJSW8wCwr+MAopqjAKminwCUiokAlIqKAMnDwwDX09MAx8HAAL62
tgDAt7YAx7++ANHKyQDa09IA4draAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A29zt
ANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A
29ztANzd7gDU1OkAwcLgAMLC4QDX1usAoqLRAJmazgCSksoAlJTLAJSUywCXlswAqqrWAImJxgCY
mM0ApaXSAKKh0QCXl8wAlpbMAIuLxgCbm80Ap6fUAKmp1wCoqNkAq6vfALCw4wC7u+sAmprqAIWF
5C9VV9uVGx3P7AYIyv8JCsz/Dg7N/w8Pzf8PEM3/DxHN/w8Rzf8PEc7/DxLO/w8Rzv8QEs//ERLP
/xETz/8RE8//ERLP/xESz/8REs//ERPQ/xIUz/8SFND/EhTQ/xIU0P8SFND/ExXR/xMV0f8TFdH/
ExXR/xMV0f8UFdH/ExbS/xQW0v8UFtL/FBbS/xUX0/8VF9P/FRfT/xUX0/8VF9P/FhjU/xYY1P8W
GNT/FhjU/xYY1P8WGNT/FhjU/xcZ1f8XGdX/FxnV/xcZ1f8YGtb/GBrW/xga1v8YGtb/GBrW/xga
1v8YGtb/GRvY/xoc3P8aHN//GRvX/xMWt/8MDYf/BARZ/wAAQv8AAEL/AABC/wAAPv8ODVL/V1iT
/6mq3v+xsv3/Z2nu/yIl2/8SFdf/GhzZ/xwe2v8bHdr/FhjZ/xkb2f9OUOKvdXfoMZOV7ACjpO8A
j5HsAJqb7gCkpfAArK3yAKKk8ACmp/AAqavxAJ2f7wCKje0AqqzyAJ2f8ACfoPAApqfyALCx8wCn
qPIAlpjwAKep8wCUlvMAsK/jAKKaowCpop8AlIqJAJSKigDJw8MA19PTAMfBwAC+trYAwLe2AMe/
vgDRyskA2tPSAOHa2gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////ANvc7QDb3O0A29zt
ANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDc3e4A
1NTpAMHC4ADCwuEA19brAKKi0QCZms4AkpLKAJSUywCUlMsAl5bMAKqq1gCJicYAmJjNAKWl0gCi
odEAl5fMAJaWzACKisYAmprNAKWl1ACnp9cAp6fZAK+v3gC6ut4AvLzfAJKS4wCZmuwAtbXxAIaI
5BtmZ95wLzDTxg4QzP8GB8v/CgvM/w4Ozf8PD83/Dw/N/xARzf8QEc7/DxLN/w8Rzv8PEc7/EBLO
/xASz/8RE8//ERPP/xESz/8REs//ERLP/xIT0P8SFND/EhTQ/xIU0P8SFND/ExXR/xMV0f8TFdH/
ExXR/xMV0f8TFdH/ExbR/xQV0f8UFtL/FBbS/xQW0v8UFtL/FRfT/xUX0/8VF9P/FRfT/xUX0/8W
GNT/FhjU/xYY1P8WGNT/FhjU/xYY1P8WGNT/FxnV/xcZ1f8XGdX/FxnW/xga2P8ZG9z/GRze/xga
1f8UFbv/DQ6S/wUGZP8AAEf/AAA//wAAQv8AAED/AABA/x0dX/9qa6L/sLHm/6mr/f9iZOz/IiTa
/xIU1/8YGtj/Gx3Z/xoc2f8VF9j/GRvZ/z0/3rl4eudFqqvwAIyO7ACKjOsAoKHvAI+R7ACam+4A
pKXwAKyt8gCipPAApqfwAKmr8QCdn+8Aio3tAKqs8gCdn/AAn6DwAKan8gCwsfMAp6jyAJaY8ACn
qfMAlJbzALCv4wCimqMAqaKfAJSKiQCUiooAycPDANfT0wDHwcAAvra2AMC3tgDHv74A0crJANrT
0gDh2toA5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wDb3O0A29ztANvc7QDb3O0A29zt
ANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A3N3uANTU6QDBwuAA
wsLhANfW6wCiotEAmZrOAJKSygCUlMsAlJTLAJeWzACqqtYAiYnGAJiYzQClpdIAoqDRAJSUywCS
kssAj4/IAJ+fzgCzs9UAu7vWAMLC1QDHx9QAysrTAL6+yACmpr0AqanWAKqq4gCOj+cApabuAI6O
6AOMjOY+UVPakCkq0tcOEMz/CQrM/wkKzP8NDcz/Dw/N/w8Qzf8QEM7/EBHO/xASzv8PEc7/DxHO
/xATzv8REs//ERPP/xETz/8REs//ERLP/xESz/8SE9D/EhTQ/xIU0P8SFND/EhTQ/xMU0f8TFdH/
ExXR/xMV0f8TFdH/ExTR/xQV0v8UFdL/FBbS/xQW0v8UFtL/FRfT/xUX0/8VF9P/FRfT/xUX0/8W
GNT/FhjU/xYY1P8WGNT/FRfU/xQX1f8UFtf/Fxnc/xkb2/8WGM7/EhOz/wwNjv8FBmb/AQFJ/wAA
P/8AAED/AAA//wAAPP8DA0j/Njd1/4SFuv+0tfD/nZ/7/1VX6P8eINn/ERPW/xcZ1/8aHNj/GRvY
/xQW1/8ZG9j/PkDewmZo5E6JiuoBlpjsAKSl7wCIiusAiozrAKCh7wCPkewAmpvuAKSl8ACsrfIA
oqTwAKan8ACpq/EAnZ/vAIqN7QCqrPIAnZ/wAJ+g8ACmp/IAsLHzAKeo8gCWmPAAp6nzAJSW8wCw
r+MAopqjAKminwCUiokAlIqKAMnDwwDX09MAx8HAAL62tgDAt7YAx7++ANHKyQDa09IA4draAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29zt
ANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANzd7gDU1OkAwcLgAMLC4QDX1usA
oqLRAJmazgCSksoAlJTLAJSUywCXlswAqqrWAImJxgCYmM0ApKTSAKWk0gCrq9AAtbXQAMPD0wDG
xtMAysrTAMrK0wDJydMAyMjTAMnJ1AG7u8gLqqq5CLCwvgCbm68Af3+nAJaWxQCLjNYAs7PzAKam
8ACXl+sMf3/kQkBC14gvMNLJFRfN+AkLy/8ICcv/CQnM/wwNzf8OD83/DxHN/xARzv8QEs7/DxHO
/w8Rzv8REs//ERPP/xETz/8REs//ERLP/xESz/8REs//EhPP/xIU0P8SFND/EhTQ/xIU0P8TFND/
ExXR/xMV0f8TFdH/ExXR/xMU0f8TFdH/FBXS/xQW0v8UFtL/FBbS/xQW0v8UFtP/ExXT/xET0/8P
EdX/FBbZ/xsd3P8iI9j/JCbI/x0eqP8PEH7/AwRZ/wAARf8AAD3/AAA//wAAQP8AADz/AABB/x0e
Xf9eXpb/oaHW/7O1+f+GiPb/P0Hi/xYY1v8QEtX/FxnX/xkb1/8YGtf/EhTX/xkb2P87Pt24aGnk
TbCx8ASChOkAhIXqAJGT6wCkpe8AiIrrAIqM6wCgoe8Aj5HsAJqb7gCkpfAArK3yAKKk8ACmp/AA
qavxAJ2f7wCKje0AqqzyAJ2f8ACfoPAApqfyALCx8wCnqPIAlpjwAKep8wCUlvMAsK/jAKKaowCp
op8AlIqJAJSKigDJw8MA19PTAMfBwAC+trYAwLe2AMe/vgDRyskA2tPSAOHa2gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAOXf3gDl394A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////ANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29zt
ANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDc3e4A1NTpAMHC4ADCwuEA19brAKKi0QCZms4A
kpLKAJSUywCUlMsAl5bMAKqq1gCJicYAmJjNAKOj0gCqq9MA0NDWAMvL0wDJydMAycnTAMjI0wDI
yNMAyMjTAMjI0wDKytUByMjSC56esCuFhZ9FfHyXPHNzjhSUk6cAkJCnAJKStACPkMQAj5DPAKOj
4wByct4AiovoAY+Q6Sp1duNkP0HXlywu080ZG87zDQ7M/wgIzP8HB8v/BwjL/wsNzP8NDs3/DhDN
/w8Rzv8PEc7/EBLO/xASzv8RE8//ERLP/xESz/8REs//ERLQ/xITz/8SFND/EhTQ/xIU0P8TFNH/
EhTQ/xMV0f8SFNH/ERPR/w8R0f8ND9D/Cw3Q/wsN0v8PEdX/FRjY/yEj2/8yNNv/PT/Q/0BAuf81
NZb/IiJw/xARUv8CAkD/AAA9/wAAP/8AAD//AAA8/wAAPv8VFlb/TU6H/4+QxP+0tvH/oaL8/2Fj
6/8nKtr/DxHU/xET1P8XGdb/GBrW/xUX1v8RE9X/Gx7X80lL3quAgehCkZPqAIKE6ACtrvAAfX/o
AISF6gCRk+sApKXvAIiK6wCKjOsAoKHvAI+R7ACam+4ApKXwAKyt8gCipPAApqfwAKmr8QCdn+8A
io3tAKqs8gCdn/AAn6DwAKan8gCwsfMAp6jyAJaY8ACnqfMAlJbzALCv4wCimqMAqaKfAJSKiQCU
iooAycPDANfT0wDHwcAAvra2AMC3tgDHv74A0crJANrT0gDh2toA5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gDl394A5d/eAP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29zt
ANvc7QDb3O0A29ztANvc7QDb3O0A3N3uANTU6QDBwuAAwsLhANfW6wCiotEAmZrOAJKSygCUlMsA
lJTLAJeWzACqqtYAiYnGAJiYzQCjo9IAqqrTAM3N1QDIyNMAyMjTAMjI0wDIyNMAyMjTAMjI0wDI
yNMAycnUAM3N1wCfn7EAiYmgEoGAmk9UVHmRQkJsm1paf3NqaoY1cHCMDIuLnwB7e5gAlpa4ALS0
4QCio9kAoaLmAIeI4QCQkecCmpvwIWVm4kVqa+F1TU3anT0+1sUjJNLXGxvQ8BQVz/4RE87/Cw3N
/wUHzP8HCcz/CQzN/wsNzf8MDs7/DA7O/wwNzv8LDM7/CwzO/wsMz/8LDc//CQvP/wgKzv8QEdP/
ExXS/hwe1vgpKtr/Oz3d/05Q3/9fX9r/ZmbN/2Njtf9VVJf/Pj12/yQjWP8LCkL/AAA7/wAAOv8A
ADv/AAA8/wAAOv8AAEL/Hh5d/1FSjP+NjsL/srPt/6ao+/9ydPD/Nzne/xQW1P8OENP/ExXU/xga
1v8WGNX/EBLV/xET1P8oKtneXF3him5w5CqenuwAoqPuAIuN6QB9f+cArK3wAH1/6ACEheoAkZPr
AKSl7wCIiusAiozrAKCh7wCPkewAmpvuAKSl8ACsrfIAoqTwAKan8ACpq/EAnZ/vAIqN7QCqrPIA
nZ/wAJ+g8ACmp/IAsLHzAKeo8gCWmPAAp6nzAJSW8wCwr+MAopqjAKminwCUiokAlIqKAMnDwwDX
09MAx8HAAL62tgDAt7YAx7++ANHKyQDa09IA4draAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
5d/eAOXf3gD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29zt
ANvc7QDb3O0A29ztANzd7gDU1OkAwcLgAMLC4QDX1usAoqLRAJmazgCSksoAlJTLAJSUywCXlswA
qqrWAImJxgCYmM0Ao6PSAKqq0wDNzdUAyMjTAMjI0wDIyNMAyMjTAMjI0wDIyNMAyMjTAMnJ1ADM
zNYAn5+xAI+PpQCxsMAAoaG0BHFwjUFRUHahKSlc0xkZTtkuLlrAMzNeh3V0kFuZmaoxlpapFYWG
pACAgKMAt7fMAGRkmgCNjcMAra3pAMTD7wC0s+oAXF3bAqCg6ReFhuUvRkfWQFVW21CGh+luZWfj
e1JU4IRHSN+JQELdjUFC3o1FRuCLS0zeiE5Q3oVUVd5+XF3ddnl652qOj+teVFXMSGxt00qHh8hp
j421/XZ1nf9aWYD/Ojlk/xwcTv8JCT//AAA4/wAAN/8AADn/AAA4/wAAN/8AAD3/EhFQ/zg5c/9r
bKL/m5zR/6+x8f+eoPn/cXLw/zs93/8YGtX/DQ/S/xAS0/8VF9T/FRfU/xET1P8OENP/Gx7W+EdI
3b12d+VfgILnEqWm7gB6fOUAlZbrAJ2e7QCLjekAfX/nAKyt8AB9f+gAhIXqAJGT6wCkpe8AiIrr
AIqM6wCgoe8Aj5HsAJqb7gCkpfAArK3yAKKk8ACmp/AAqavxAJ2f7wCKje0AqqzyAJ2f8ACfoPAA
pqfyALCx8wCnqPIAlpjwAKep8wCUlvMAsK/jAKKaowCpop8AlIqJAJSKigDJw8MA19PTAMfBwAC+
trYAwLe2AMe/vgDRyskA2tPSAOHa2gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////ANvc
7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29zt
ANvc7QDc3e4A1NTpAMHC4ADCwuEA19brAKKi0QCZms4AkpLKAJSUywCUlMsAl5bMAKqq1gCJicYA
mJjNAKOj0gCqqtMAzc3VAMjI0wDIyNMAyMjTAMjI0wDIyNMAyMjTAMjI0wDJydQAzMzWAJ+fsQCO
jqQAq6q7AJycsACSkqcAwMDLAI6Prwx3eKhEW1uQijQ1bdETE03/BgY//xERRvAWF0jIMTFbrEpK
b44gIE5xXFx9WpGRp0a1tMI8f36dIl1ciReFg58Qj46qCo6MrwSmpb8Bu7rQAKWlywCVlMYChYS/
BnZ2tglmZqwOaWmqE6SjwSuQkbI3bW2XST8/cmBSUnx1V1d8mCwsWrEkJFbWERFH6wICPf8AADb/
AAA0/wAANP8AADT/AAA0/wAAOP8DA0L/GhpW/zs7df9oaJ3/kZLG/6iq5/+nqff/i433/1xe6v8w
Mtv/FRfT/wwO0f8PEdH/FBbT/xMV0/8PEtP/DhDT/xkb1fo1N9nIX2Dhe42O6S+6u/EAsbPwAICC
5wCdnu0Ad3nlAJWW6wCdnu0Ai43pAH1/5wCsrfAAfX/oAISF6gCRk+sApKXvAIiK6wCKjOsAoKHv
AI+R7ACam+4ApKXwAKyt8gCipPAApqfwAKmr8QCdn+8Aio3tAKqs8gCdn/AAn6DwAKan8gCwsfMA
p6jyAJaY8ACnqfMAlJbzALCv4wCimqMAqaKfAJSKiQCUiooAycPDANfT0wDHwcAAvra2AMC3tgDH
v74A0crJANrT0gDh2toA5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wDb3O0A29ztANvc
7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A3N3u
ANTU6QDBwuAAwsLhANfW6wCiotEAmZrOAJKSygCUlMsAlJTLAJeWzACqqtYAiYnGAJiYzQCjo9IA
qqrTAM3N1QDIyNMAyMjTAMjI0wDIyNMAyMjTAMjI0wDIyNMAycnUAMzM1gCfn7EAjo6kAKuquwCc
nLAAjY2jALa2xACPj68Al5jCALi55gC8ve4AtLXnLpaYzoRsbabfRkeB/ycnYP8PD0j/Bwc//wAA
NP8AADD/AAAy/wAAN/QKCj3sEA9D6RYWSOYdHU3jHh1O4hsaTOIfHk7iHx5N4xwcSuUYF0boERBB
7AoKPPEEBDv/AAA2/wAANP8AADT/AAAy/wAAMP8AADL/AAAy/wAANP8AADj/AAE//w4OSv8gIFr/
Oztz/19glP+Bgrb/m5zU/6mq6/+lp/f/i433/2Nk7P86O97/Gx3U/wwOz/8LDM//DxHR/xET0v8Q
EtL/DhDS/w8R0v8dH9T1NznYxV1f4H1/gOQ0kpTqA6Ch7ACjpO0AtLXwAKmr7wB/gecAnZ7tAHd5
5QCVlusAnZ7tAIuN6QB9f+cArK3wAH1/6ACEheoAkZPrAKSl7wCIiusAiozrAKCh7wCPkewAmpvu
AKSl8ACsrfIAoqTwAKan8ACpq/EAnZ/vAIqN7QCqrPIAnZ/wAJ+g8ACmp/IAsLHzAKeo8gCWmPAA
p6nzAJSW8wCwr+MAopqjAKminwCUiokAlIqKAMnDwwDX09MAx8HAAL62tgDAt7YAx7++ANHKyQDa
09IA4draAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A29ztANvc7QDb3O0A29ztANvc
7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANzd7gDU1OkAwcLg
AMLC4QDX1usAoqLRAJmazgCSksoAlJTLAJSUywCXlswAqqrWAImJxgCYmM0Ao6PSAKqq0wDNzdUA
yMjTAMjI0wDIyNMAyMjTAMjI0wDIyNMAyMjTAMnJ1ADMzNYAn5+xAI6OpACrqrsAnJywAI2NowC2
tsQAjo6uAJKTvgCur9wAtbbnAMrL+gDY2v8Az9D/ELS1+naam/G7lZfk9omK0v96fLz/bW6m/11e
kP9ISXz/NTVr/yMkW/8XF0//Dg9H/wgIQf8DAz3/AAA7/wAAOv8AADn/AAA5/wEBO/8DAz3/BgY/
/wsLRP8REUr/GRlR/yMkXP8zNGz/RUZ8/1pajv9vb6L/goO5/5WWzv+kpeH/qqzw/6Gj+P+KjPb/
bW7u/0xO5P8tL9r/FBbR/wsMzv8JC87/DQ/P/w4R0P8ND9D/Cw3P/wwN0P8WGNL7JyjV3EZI2qhp
auFhnJ3rKKam7ACbnOkAk5PoAI6Q6QCYmesAn6DsALS18ACpq+8Af4HnAJ2e7QB3eeUAlZbrAJ2e
7QCLjekAfX/nAKyt8AB9f+gAhIXqAJGT6wCkpe8AiIrrAIqM6wCgoe8Aj5HsAJqb7gCkpfAArK3y
AKKk8ACmp/AAqavxAJ2f7wCKje0AqqzyAJ2f8ACfoPAApqfyALCx8wCnqPIAlpjwAKep8wCUlvMA
sK/jAKKaowCpop8AlIqJAJSKigDJw8MA19PTAMfBwAC+trYAwLe2AMe/vgDRyskA2tPSAOHa2gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////ANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc
7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDc3e4A1NTpAMHC4ADCwuEA19br
AKKi0QCZms4AkpLKAJSUywCUlMsAl5bMAKqq1gCJicYAmJjNAKOj0gCqqtMAzc3VAMjI0wDIyNMA
yMjTAMjI0wDIyNMAyMjTAMjI0wDJydQAzMzWAJ+fsQCOjqQAq6q7AJycsACNjaMAtrbEAI6OrgCS
k74Arq/cALW25wDGx/YA0NH/AMjJ+QCpqe0Ae3zjAH1+5SuAgelteHnrq29w691sbuv6dnjs/4KD
7P+LjOz/k5To/5eZ4/+anN7/mpva/5ia1v+YmdT/lZbQ/5SV0P+ZmtT/m5zX/56f2/+houD/o6Tl
/6Sl7P+ho/H/m5zz/5OU9P+HifP/d3nw/2Nl6/9LTeT/NDbc/x8i1P8SE9D/CwzN/wcIzf8HCMz/
CAnN/wsMzv8ICs7/Cw3P/w8Rz/8cHdL0LjDV01BS3KdxcuBwcXLiM4uL5QyOj+YAmpvpALCw7wCj
ousAk5ToAI+Q5wCOkOkAmJnrAJ+g7AC0tfAAqavvAH+B5wCdnu0Ad3nlAJWW6wCdnu0Ai43pAH1/
5wCsrfAAfX/oAISF6gCRk+sApKXvAIiK6wCKjOsAoKHvAI+R7ACam+4ApKXwAKyt8gCipPAApqfw
AKmr8QCdn+8Aio3tAKqs8gCdn/AAn6DwAKan8gCwsfMAp6jyAJaY8ACnqfMAlJbzALCv4wCimqMA
qaKfAJSKiQCUiooAycPDANfT0wDHwcAAvra2AMC3tgDHv74A0crJANrT0gDh2toA5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gDl394A5d/eAP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc
7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A3N3uANTU6QDBwuAAwsLhANfW6wCiotEAmZrO
AJKSygCUlMsAlJTLAJeWzACqqtYAiYnGAJiYzQCjo9IAqqrTAM3N1QDIyNMAyMjTAMjI0wDIyNMA
yMjTAMjI0wDIyNMAycnUAMzM1gCfn7EAjo6kAKuquwCcnLAAjY2jALa2xACOjq4AkpO+AK6v3AC1
tucAxsf2ANDR/wDIyfkAqantAH5/4wCFhuQAo6TqAJ+f6QCfn+kMYmPcLWts31tHR9eKQEHXtzM0
1doqLNbzJSbV/yIj1v8qK9j/Li/Z/yor2f8uLtr/MDDb/zAx2v8rK9n/JSbX/yAh1f8aHNL/FBbQ
/w0Ozv8HB8z/BATL/wIDyv8AAsn/AALK/wAByv8GCcz/Cg3N/wgKzf8OEM7/GhzQ9ikq0+kzNdbC
UlTcql5f3HZlZd5HX2DeJKam6QehouwAurrsAIKC5QCLi+UAh4jlAJOU6ACsrO4AoqLrAJOU6ACP
kOcAjpDpAJiZ6wCfoOwAtLXwAKmr7wB/gecAnZ7tAHd55QCVlusAnZ7tAIuN6QB9f+cArK3wAH1/
6ACEheoAkZPrAKSl7wCIiusAiozrAKCh7wCPkewAmpvuAKSl8ACsrfIAoqTwAKan8ACpq/EAnZ/v
AIqN7QCqrPIAnZ/wAJ+g8ACmp/IAsLHzAKeo8gCWmPAAp6nzAJSW8wCwr+MAopqjAKminwCUiokA
lIqKAMnDwwDX09MAx8HAAL62tgDAt7YAx7++ANHKyQDa09IA4draAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A5d/eAOXf3gD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc7QDb3O0A29ztANvc
7QDb3O0A29ztANvc7QDb3O0A29ztANzd7gDU1OkAwcLgAMLC4QDX1usAoqLRAJmazgCSksoAlJTL
AJSUywCXlswAqqrWAImJxgCYmM0Ao6PSAKqq0wDNzdUAyMjTAMjI0wDIyNMAyMjTAMjI0wDIyNMA
yMjTAMnJ1ADMzNYAn5+xAI6OpACrqrsAnJywAI2NowC2tsQAjo6uAJKTvgCur9wAtbbnAMbH9gDQ
0f8AyMn5AKmp7QB+f+MAhIXkAJ+g6QCenukAqKjrAICB4wCZmugAkZHlAI2O5ACsrOwKg4PjIUNE
1DZ7fOJXS0zXdDk61IdNTdisNjfTvCgp0MYgIc/LJCXQ3SUl0O8hIdDwIiLQ8SMj0PElJtDwKizS
7ygp0tUoKdLLMTHTxT9A1btWV9utREbYiExN2nWDheVgaWnePWZo3ye3uPAUiYvnALKz7gCam+YA
gYHkAGFi3gCoqOkAmJnqALGx6wB/f+QAiorlAIeI5QCTlOgArKzuAKKi6wCTlOgAj5DnAI6Q6QCY
mesAn6DsALS18ACpq+8Af4HnAJ2e7QB3eeUAlZbrAJ2e7QCLjekAfX/nAKyt8AB9f+gAhIXqAJGT
6wCkpe8AiIrrAIqM6wCgoe8Aj5HsAJqb7gCkpfAArK3yAKKk8ACmp/AAqavxAJ2f7wCKje0Aqqzy
AJ2f8ACfoPAApqfyALCx8wCnqPIAlpjwAKep8wCUlvMAsK/jAKKaowCpop8AlIqJAJSKigDJw8MA
19PTAMfBwAC+trYAwLe2AMe/vgDRyskA2tPSAOHa2gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl
394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf
3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/eAOXf3gDl394A5d/e
AOXf3gDl394A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A
////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD/
//8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP//
/wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////AP///wD///8A////
AP///wD///8A////AP///wD///8A////AP/////////////////////////////////////AAAAA
/////////////////////////////////////8AAAAD/////////////////////////////////
////wAAAAP/////////////////////////////////////AAAAA////////////////////+AAA
H////////////8AAAAD///////////////////4AAAAP////////////wAAAAP//////////////
////4AAAAAP////////////AAAAA//////////////////4AAAAAAf///////////8AAAAD/////
////////////8AAAAAAA////////////wAAAAP////////////////+AAAAAAAB////////////A
AAAA/////////////////gAAAAAAAB///////////8AAAAD////////////////wAAAAAAHAH///
////////wAAAAP///////////////8AAAAAP/AAAP//////////AAAAA////////////////AAAA
Af/AAAAD/////////8AAAAD///////////////wAAAAAfgAAAAB/////////wAAAAP//////////
////8AAAAAAAAAAAAB/////////AAAAA///////////////AAAAAAAAAAAAAB////////8AAAAD/
/////////////wAAAAAAAAAAAAAB////////wAAAAP/////////////+AAAAAAAAAAAAAAB/////
///AAAAA//////////////gAAAAAAAAAAAAAAB///////8AAAAD/////////////4AAAAAAAAAAA
AAAAD///////wAAAAP/////////////AAAAAAAAAAAAAAAAD///////AAAAA/////////////wAA
AAAAAAAAAAAAAAH//////8AAAAD////////////+AAAAAAAAAAAAAAAAAP//////wAAAAP//////
//////wAAAAAAAAAAAAAAAAAf//////AAAAA////////////8AAAAAAAAAAAAAAAAAA//////8AA
AAD////////////gAAAAAAAAAAAAAAAAAB//////wAAAAP///////////8AAAAAAAAAAAAAAAAAA
D//////AAAAA////////////gAAAAAAAAAAAAAAAAAAH/////8AAAAD///////////4AAAAAAAAA
AAAAAAAAAAP/////wAAAAP///////////AAAAAAAAAAAAAAAAAAAAf/////AAAAA///////////4
AAAAAAAAAAAAAAAAAAAA/////8AAAAD///////////AAAAAAAAAAAAAAAAAAAAB/////wAAAAP//
////////4AAAAAAAAAAAAAAAAAAAAD/////AAAAA///////////AAAAAAAAAAAAAAAAAAAAAP///
/8AAAAD//////////4AAAAAAAAAAAAAAAAAAAAAf////wAAAAP//////////AAAAAAAAAAAAAAAA
AAAAAA/////AAAAA//////////4AAAAAAAAAAAAAAAAAAAAAD////8AAAAD//////////AAAAAAA
AAAAAAAAAAAfwAAP////wAAAAP/////////4AAAAAAAAAAAAAAAAAAD8AAf////AAAAA////////
//AAAAAAAAAAAAAAAAAAAB+AA////8AAAAD/////////4AAAAAAAAAAAAAAAAAAAB+AB////wAAA
AP/////////gAAAAAAAAAAAAAAAAAAAB8AH////AAAAA/////////8AAAAAAAAAAAAAAAAAAAAB8
AP///8AAAAD/////////gAAAAAAAAAAAAAAAAAAAAD4Af///wAAAAP////////8AAAAAAAAAAAAA
AAAAAAAAD4B////AAAAA/////////gAAAAAAAAAAAAAAAAAAAAAHwD///8AAAAD////////8AAAA
AAAAAAAAAAAAAAAAAAPgP///wAAAAP////////wAAAAAAAAAAAAAAAAAAAAAAfAf///AAAAA////
////+AAAAAAAAAAAAAAAAAAAAAAA+B///8AAAAD////////wAAAAAAAAAAAAAAAAAAAAAAB8D///
wAAAAP///////+AAAAAAAAAAAAAAAAAAAAAAADwP///AAAAA////////4AAAAAAAAAAAAAAAAAAA
AAAAHgf//8AAAAD////////AAAAAAAAAAAAAAAAAAAAAAAAPB///wAAAAP///////4AAAAAAAAAA
AAAAAAAAAAAAAA+D///AAAAA////////gAAAAAAAAAAAAAAAAAAAAAAAB4P//8AAAAD///////8A
AAAAAAAAAAAAAAAAAAAAAAADg///wAAAAP///////gAAAAAAAAAAAAAAAAAAAAAAAAPB///AAAAA
///////+AAAAAAAAAAAAAAAAAAAAAAAAAcH//8AAAAD///////wAAAAAAAAAAAAAAAAAAAAAAAAA
4f//wAAAAP//////+AAAAAAAAAAAAAAAAAAAAAAAAADg///AAAAA///////4AAAAAAAAAAAAAAAA
AAAAAAAAAHD//8AAAAD///////AAAAAAAAAAAAAAAAAAAAAAAAAAcP//wAAAAP//////8AAAAAAA
AAAAAAAAAAAAAAAAAAA4f//AAAAA///////gAAAAAAAAAAAAAAAAAAAAAAAAADh//8AAAAD/////
/+AAAAAAAAAAAAAAAAAAAAAAAAAAGH//wAAAAP//////wAAAAAAAAAAAAAAAAAAAP4AAAAAcP//A
AAAA///////AAAAAAAAAAAAAAAAAAAr//AAAAAw//8AAAAD//////4AAAAAAAAAAAAAAAAAA+AD/
wAAADD//wAAAAP//////gAAAAAAAAAAAAAAAAAf4AB/wAAAGP//AAAAA//////8AAAAAAAAAAAAA
AAAAP/wAA/4AAAYf/8AAAAD//////wAAAAAAAAAAAAAAAAD//gAA/wAAAh//wAAAAP/////+AAAA
AAAAAAAAAAAAA///gAA/wAACH//AAAAA//////4AAAAAAAAAAAAAAAAP///AAA/gAAMf/8AAAAD/
/////AAAAAAAAAAAAAAAAD///+AAB/AAAR//wAAAAP/////8AAAAAAAAAAAAAAAAf///+AAD/AAB
H//AAAAA//////gAAAAAAAAAAAAAAAH////8AAD+AAEP/8AAAAD/////+AAAAAAAAAAAAAAAB///
//8AAH8AAI//wAAAAP/////wAAAAAAAAAAAAAAAP/////8AAPwAAj//AAAAA//////AAAAAAAAAA
AAAAAD//////8AAfgACP/8AAAAD/////8AAAAAAAAAAAAAAAf//////4AB+AAI//wAAAAP/////g
AAAAAAAAAAAAAAD///////wAD8AAj//AAAAA/////+AAAAAAAAAAAAAAA////////wAHwABP/8AA
AAD/////4AAAAAAAAAAAAAAH////////AAPgAE//wAAAAP/////AAAAAAAAAAAAAAA////////+A
AeAAT//AAAAA/////8AAAAAAAAAAAAAAH////////8AB8AAv/8AAAAD/////wAAAAAAAAAAAAAA/
////////wADwAC//wAAAAP////+AAAAAAAAAAAAAAH/////////gAPgAP//AAAAA/////4AAAAAA
AAAAAAAB/////////+AAeAA//8AAAAD/////gAAAAAAAAAAAAAP/////////8AA4AD//wAAAAP//
//8AAAAAAAAAAAAAB//////////wADwAP//AAAAA///+fwAAAAAAAAAAAAAP//////////gAHAA/
/8AAAAD///4/AAAAAAAAAAAAAB//////////+AAcAD//wAAAAP///h8AAAAAAAAAAAAAP///////
///8AAwAP//AAAAA///8DgAAAAAAAAAAAAB///////////wADgAf/8AAAAD///wCAAAAAAAAAAAA
AH///////////AAGAB//wAAAAP///AAAAAAAAAAAAAAA///////////+AAYAH//AAAAA///4AAAA
AAAAAAAAAAH///////////4ABgAf/8AAAAD///gAAAAAAAAAAAAAA////////////gACAB//wAAA
AP//+AAAAAAAAAAAAAAH///////////+AAMAH//AAAAA///wAAAAAAAAAAAAAA////////////8A
AwAf/8AAAAD///AAAAAAAAAAAABAH////////////wABAB//wAAAAP//8AAAAAAAAAAAAHA/////
////////AAEAH//AAAAA///gAAAAAAAAAAAA+H////////////8AAQAf/8AAAAD//+AAAAAAAAAA
AAD8f////////////wABAB//wAAAAP//4AAAAAAAAAAAAf//////////////gAAAH//AAAAA///A
AAAAAAAAAAAB//////////////+AAAAf/8AAAAD//8AAAAAAAAAAAAH//////////////4AAAD//
wAAAAP//wAAAAAAAAAAAA///////////////gAAAP//AAAAA//+AAAAAAAAAAAAD////////////
//+AAAA//8AAAAD//4AAAAAAAAAAAAf//////////////4AAAD//wAAAAP//gAAAAAAAAAAAB///
////////////gAAAP//AAAAA//+AAAAAAAAAAAAH//////////////+AAAA//8AAAAD//wAAAAAA
AAAAAA///////////////4AAAD//wAAAAP//AAAAAAAAAAAAD///////////////gAAAP//AAAAA
//8AAAAAAAAAAAAP//////////////OAAAA//8AAAAD//wAAAAAAAAAAAA//////////////8YAA
AD//wAAAAP//AAAAAAAAAAAAH//////////////wgAAAf//AAAAA//4AAAAAAAAAAAAf////////
/////+CAAAB//8AAAAD//gAAAAAAAAAAAB//////////////4AAAAH//wAAAAP/+AAAAAAAAAAAA
H//////////////gAAAAf//AAAAA//4AAAAAAAAAAAA//////////////+AAAAB//8AAAAD//gAA
AAAAAAAAAD//////////////4AAAAP//wAAAAP/+AAAAAAAAAAAAP//////////////AAAAA///A
AAAA//wAAAAAAAAAAAA//////////////8AAAAD//8AAAAD//AAAAAAAAAAAAD//////////////
wAAAAP//wAAAAP/8AAAAAAAAAAAAf/////////////+AAAAB///AAAAA//wAAAAAAAAAAAB/////
/////////4AAAAH//8AAAAD//AAAAAAAAAAAAP//////////////gAAAAf//wAAAAP/8AAAAAAAA
AAAA//////////////8AAAAB///AAAAA//wAAAAAAACAAAD//////////////wAAAAP//8AAAAD/
/AAAAAAAAIAAAP//////////////AAAAA///wAAAAP/8AAAAAAAAgAAA//////////////4AAAAD
///AAAAA//wAAAAAAAAAAAD//////////////gAAAAf//8AAAAD//AAAAAAAAEAAAP//////////
///+AAAAB///wAAAAP/8AAAAAAAAQAAA//////////////wAAAAH///AAAAA//wAAAAAAABAAAD/
/////////////AAAAA///8AAAAD//AAAAAAAAGAAAP/////////////4AAAAD///wAAAAP/8AAAA
AAAAYAAA//////////////gAAAAf///AAAAA//wAAAAAAAAgAAD/////////////8AAAAB///8AA
AAD//AAAAAAAADAAAP/////////////wAAAAH///wAAAAP/8AAAAAAAAMAAA/////////////+AA
AAH////AAAAA//wAAgAAAAAwAAD/////////////4AAAAf///8AAAAD//AAAAAAAABgAAP//////
///////AAAAD////wAAAAP/8AAAAAAAAGAAA/////////////8AAAAP////AAAAA//wAAAAAAAAc
AAD/////////////gAAAB////8AAAAD//AABAAAAAAwAAP////////////+AAAAH////wAAAAP/8
AAEAAAAADgAA/////////////wAAAA/////AAAAA//wAAAAAAAAOAAB/////////////AAAAD///
/8AAAAD//AAAgAAAAAcAAH////////////4AAAAP////wAAAAP/8AACAAAAAB4AAf///////////
/AAAAB/////AAAAA//wAAIAAAAAHgAB////////////8AAAAH////8AAAAD//gAAQAAAAAPAAH//
//////////gAAAA/////wAAAAP/+AABAAAAAA+AAf///////////8AAAAD/////AAAAA//4AAGAA
AAAB4AA////////////wAAAAP////8AAAAD//gAAIAAAAAHwAD///////////+AAAAB/////wAAA
AP/+AAAgAAAAAPgAP///////////wAAAAH/////AAAAA//4AADAAAAAA/AA///////////+AAAAA
/////8AAAAD//wAAEAAAAAB+AB///////////4AAAAD/////wAAAAP//AAAYAAAAAH8AH///////
////AAAAAP/////AAAAA//8AABwAAAAAP4Af//////////4AAAAB/////8AAAAD//wAADAAAAAAf
wA///////////AAAAAH/////wAAAAP//gAAOAAAAAB/gD//////////4AAAAA//////AAAAA//+A
AAYAAAAAD/AH//////////AAAAAD/////8AAAAD//4AABwAAAAAH+Af/////////4AAAAAf/////
wAAAAP//wAADgAAAAAP+A//////////AAAAAD//////AAAAA///AAAOAAAAAA/8D/////////4AA
AAAf/////8AAAAD//8AAAcAAAAAB/8H/////////AAAAAB//////wAAAAP//4AAB4AAAAAD/4f//
//////4AAAAAP//////AAAAA///gAADwAAAAAH/4/////////AAAAAB//////8AAAAD///AAAHgA
AAAAP/5///////z4AAAAAH//////wAAAAP//8AAAfAAAAAAf////////8HAAAAAA///////AAAAA
///wAAA8AAAAAA/////////AAAAAAAH//////8AAAAD///gAAB4AAAAAB////////wAAAAAAA///
////wAAAAP//+AAAH4AAAAAA///////4AAAAAAAH///////AAAAA///8AAAPwAAAAAA//////8AA
AAAAAA///////8AAAAD///4AAAfgAAAAAAf////+AAAAAAAAH///////wAAAAP///gAAA/AAAAAA
AH///+AAAAAAAAA////////AAAAA////AAAD+AAAAAAAA//4AAAAAAAAAH///////8AAAAD///8A
AAH+AAAAAAAAAAAAAAAAAAAA////////wAAAAP///4AAAP8AAAAAAAAAAAAAAAAAAAD////////A
AAAA////wAAAf8AAAAAAAAAAAAAAAAAAAf///////8AAAAD////AAAA/8AAAAAAAAAAAAAAAAAAD
////////wAAAAP///+AAAB/4AAAAAAAAAAAAAAAAAAf////////AAAAA////8AAAB/4AAAAAAAAA
AAAAAAAAD////////8AAAAD////4AAAD/4AAAAAAAAAAAAAAAAAf////////wAAAAP////wAAAH/
4AAAAAAAAAAAAAAAAD/////////AAAAA/////AAAAP/wAAAAAAAAAAAAAAAAf////////8AAAAD/
///+AAAAH/4AAAAAAAAAAAAAAAD/////////wAAAAP////8AAAAD/4AAAAAAAAAAAAAAAf//////
///AAAAA/////4AAAAD/8AAAAAAAAAAAAAAD/////////8AAAAD/////wAAAAB/+AAAAAAAAAAAA
AH//////////wAAAAP/////wAAAAAf/gAAAAAAAAAAAA///////////AAAAA//////gAAAAAD//w
GAAAAAAAAAH//////////8AAAAD//////AAAAAAAAEAAAAAAAAAAB///////////wAAAAP/////+
AAAAAAAAAAAAAAAAAAAP///////////AAAAA//////8AAAAAAAAAAAAAAAAAAB///////////8AA
AAD//////8AAAAAAAAAAAAAAAAAAf///////////wAAAAP//////4AAAAAAAAAAAAAAAAAD/////
///////AAAAA///////4AAAAAAAAAAAAAAAAAf///////////8AAAAD///////4AAAAAAAAAAAAA
AAAH////////////wAAAAP///////4AAAAAAAAAAAAAAAA/////////////AAAAA////////4AAA
AAAAAAAAAAAAP////////////8AAAAD////////4AAAAAAAAAAAAAAB/////////////wAAAAP//
//////4AAAAAAAAAAAAAAf/////////////AAAAA/////////4AAAAAAAAAAAAAH////////////
/8AAAAD/////////4AAAAAAAAAAAAB//////////////wAAAAP/////////4AAAAAAAAAAAAP///
///////////AAAAA/////////H8AAAAAAAAAAAD//////////////8AAAAD////////8D+AAAAAA
AAAAB///////////////wAAAAP////////+A/gAAAAAAAAAf///////////////AAAAA////////
/+AH+AAAAAAAAH///////////////8AAAAD//////////AAAMAAAAAAD////////////////wAAA
AP//////////wAAAAAAAAA/////////////////AAAAA///////////wAAAAAAAA////////////
/////8AAAAD///////////4AAAAAAAf/////////////////wAAAAP///////////8AAAAAAf///
///////////////AAAAA/////////////gAAAB///////////////////8AAAAD/////////////
////////////////////////wAAAAP/////////////////////////////////////AAAAA////
/////////////////////////////////8AAAAD/////////////////////////////////////
wAAAAP/////////////////////////////////////AAAAA')
	#endregion
	$MainForm.Margin = '5, 4, 5, 4'
	$MainForm.MaximizeBox = $False
	$MainForm.MinimumSize = New-Object System.Drawing.Size(1280, 800)
	$MainForm.Name = 'MainForm'
	$MainForm.Padding = '0, 0, 0, 10'
	$MainForm.StartPosition = 'CenterScreen'
	$MainForm.Text = 'Driver Automation Tool: Version 6.4.8'
	$MainForm.add_FormClosing($MainForm_FormClosing)
	$MainForm.add_Load($MainForm_Load)
	$MainForm.add_Shown($MainForm_Shown)
	#
	# LogoPanel
	#
	$LogoPanel.Controls.Add($AutomationLabel)
	$LogoPanel.Controls.Add($MSEndpointMgrLogo)
	$LogoPanel.Controls.Add($DescriptionText)
	$LogoPanel.Anchor = 'Top, Left, Right'
	$LogoPanel.BackColor = [System.Drawing.Color]::White 
	$LogoPanel.Location = New-Object System.Drawing.Point(0, 0)
	$LogoPanel.Name = 'LogoPanel'
	$LogoPanel.Size = New-Object System.Drawing.Size(1280, 122)
	$LogoPanel.TabIndex = 43
	#
	# AutomationLabel
	#
	$AutomationLabel.Anchor = 'Right'
	$AutomationLabel.BackColor = [System.Drawing.Color]::White 
	$AutomationLabel.Font = [System.Drawing.Font]::new('Segoe UI', '16.2', [System.Drawing.FontStyle]'Bold')
	$AutomationLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 122, 0, 0)
	$AutomationLabel.Location = New-Object System.Drawing.Point(790, 21)
	$AutomationLabel.Margin = '4, 0, 4, 0'
	$AutomationLabel.Name = 'AutomationLabel'
	$AutomationLabel.Size = New-Object System.Drawing.Size(461, 29)
	$AutomationLabel.TabIndex = 25
	$AutomationLabel.Text = 'Driver Automation Tool'
	$AutomationLabel.TextAlign = 'MiddleRight'
	$AutomationLabel.UseCompatibleTextRendering = $True
	#
	# MSEndpointMgrLogo
	#
	$MSEndpointMgrLogo.BackColor = [System.Drawing.Color]::White 
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
AAEAAAD/////AQAAAAAAAAAMAgAAAFFTeXN0ZW0uRHJhd2luZywgVmVyc2lvbj00LjAuMC4wLCBD
dWx0dXJlPW5ldXRyYWwsIFB1YmxpY0tleVRva2VuPWIwM2Y1ZjdmMTFkNTBhM2EFAQAAABVTeXN0
ZW0uRHJhd2luZy5CaXRtYXABAAAABERhdGEHAgIAAAAJAwAAAA8DAAAASCUAAAL/2P/gABBKRklG
AAEBAQBIAEgAAP/bAEMABQMEBAQDBQQEBAUFBQYHDAgHBwcHDwsLCQwRDxISEQ8RERMWHBcTFBoV
EREYIRgaHR0fHx8TFyIkIh4kHB4fHv/bAEMBBQUFBwYHDggIDh4UERQeHh4eHh4eHh4eHh4eHh4e
Hh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHv/AABEIAFQBaAMBEQACEQEDEQH/xAAf
AAABBQEBAQEBAQAAAAAAAAAAAQIDBAUGBwgJCgv/xAC1EAACAQMDAgQDBQUEBAAAAX0BAgMABBEF
EiExQQYTUWEHInEUMoGRoQgjQrHBFVLR8CQzYnKCCQoWFxgZGiUmJygpKjQ1Njc4OTpDREVGR0hJ
SlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3
uLm6wsPExcbHyMnK0tPU1dbX2Nna4eLj5OXm5+jp6vHy8/T19vf4+fr/xAAfAQADAQEBAQEBAQEB
AAAAAAAAAQIDBAUGBwgJCgv/xAC1EQACAQIEBAMEBwUEBAABAncAAQIDEQQFITEGEkFRB2FxEyIy
gQgUQpGhscEJIzNS8BVictEKFiQ04SXxFxgZGiYnKCkqNTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNk
ZWZnaGlqc3R1dnd4eXqCg4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfI
ycrS09TV1tfY2dri4+Tl5ufo6ery8/T19vf4+fr/2gAMAwEAAhEDEQA/APsugAoAZNLHDGZJXVFH
cmgDmdd8d6LpJIlivZSP7sOz9XK5/Cs5VVHc7KGCqVvh/Jv8kznj8afCcT4u4NRtV/56SRptH47q
z+sx7fl/mdn9i1rfEvmpL80kdR4e8b+FteeOLTdYt3mkGUhkzHIw9lbBb6jNXGtCTsnqc1fLMVQj
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
AKACgAoAKACgAoAKAP/ZCw=='))
	#endregion
	$MSEndpointMgrLogo.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
AAEAAAD/////AQAAAAAAAAAMAgAAAFFTeXN0ZW0uRHJhd2luZywgVmVyc2lvbj00LjAuMC4wLCBD
dWx0dXJlPW5ldXRyYWwsIFB1YmxpY0tleVRva2VuPWIwM2Y1ZjdmMTFkNTBhM2EFAQAAABVTeXN0
ZW0uRHJhd2luZy5CaXRtYXABAAAABERhdGEHAgIAAAAJAwAAAA8DAAAASCUAAAL/2P/gABBKRklG
AAEBAQBIAEgAAP/bAEMABQMEBAQDBQQEBAUFBQYHDAgHBwcHDwsLCQwRDxISEQ8RERMWHBcTFBoV
EREYIRgaHR0fHx8TFyIkIh4kHB4fHv/bAEMBBQUFBwYHDggIDh4UERQeHh4eHh4eHh4eHh4eHh4e
Hh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHv/AABEIAFQBaAMBEQACEQEDEQH/xAAf
AAABBQEBAQEBAQAAAAAAAAAAAQIDBAUGBwgJCgv/xAC1EAACAQMDAgQDBQUEBAAAAX0BAgMABBEF
EiExQQYTUWEHInEUMoGRoQgjQrHBFVLR8CQzYnKCCQoWFxgZGiUmJygpKjQ1Njc4OTpDREVGR0hJ
SlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3
uLm6wsPExcbHyMnK0tPU1dbX2Nna4eLj5OXm5+jp6vHy8/T19vf4+fr/xAAfAQADAQEBAQEBAQEB
AAAAAAAAAQIDBAUGBwgJCgv/xAC1EQACAQIEBAMEBwUEBAABAncAAQIDEQQFITEGEkFRB2FxEyIy
gQgUQpGhscEJIzNS8BVictEKFiQ04SXxFxgZGiYnKCkqNTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNk
ZWZnaGlqc3R1dnd4eXqCg4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfI
ycrS09TV1tfY2dri4+Tl5ufo6ery8/T19vf4+fr/2gAMAwEAAhEDEQA/APsugAoAZNLHDGZJXVFH
cmgDmdd8d6LpJIlivZSP7sOz9XK5/Cs5VVHc7KGCqVvh/Jv8kznj8afCcT4u4NRtV/56SRptH47q
z+sx7fl/mdn9i1rfEvmpL80kdR4e8b+FteeOLTdYt3mkGUhkzHIw9lbBb6jNXGtCTsnqc1fLMVQj
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
AKACgAoAKACgAoAKAP/ZCw=='))
	#endregion
	$MSEndpointMgrLogo.InitialImage = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$MSEndpointMgrLogo.Location = New-Object System.Drawing.Point(18, 21)
	$MSEndpointMgrLogo.Margin = '4, 3, 4, 3'
	$MSEndpointMgrLogo.Name = 'MSEndpointMgrLogo'
	$MSEndpointMgrLogo.Size = New-Object System.Drawing.Size(358, 80)
	$MSEndpointMgrLogo.SizeMode = 'StretchImage'
	$MSEndpointMgrLogo.TabIndex = 24
	$MSEndpointMgrLogo.TabStop = $False
	$MSEndpointMgrLogo.add_Click($MSEndpointMgrLogo_Click)
	#
	# DescriptionText
	#
	$DescriptionText.Anchor = 'Right'
	$DescriptionText.BackColor = [System.Drawing.Color]::White 
	$DescriptionText.BorderStyle = 'None'
	$DescriptionText.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$DescriptionText.Location = New-Object System.Drawing.Point(679, 53)
	$DescriptionText.Multiline = $True
	$DescriptionText.Name = 'DescriptionText'
	$DescriptionText.ReadOnly = $True
	$DescriptionText.Size = New-Object System.Drawing.Size(572, 48)
	$DescriptionText.TabIndex = 41
	$DescriptionText.TabStop = $False
	$DescriptionText.Text = 'Automates the process of downloading, extracting and importing Driver and BIOS updates into Configuration Manager, Intune, MDT and other OS deployment solutions'
	$DescriptionText.TextAlign = 'Right'
	#
	# SelectionTabs
	#
	$SelectionTabs.Controls.Add($MakeModelTab)
	$SelectionTabs.Controls.Add($OEMCatalogs)
	$SelectionTabs.Controls.Add($CommonTab)
	$SelectionTabs.Controls.Add($ConfigMgrTab)
	$SelectionTabs.Controls.Add($IntuneTab)
	$SelectionTabs.Controls.Add($MDTTab)
	$SelectionTabs.Controls.Add($ConfigMgrDriverTab)
	$SelectionTabs.Controls.Add($ConfigWSDiagTab)
	$SelectionTabs.Controls.Add($CustPkgTab)
	$SelectionTabs.Controls.Add($LogTab)
	$SelectionTabs.Controls.Add($AboutTab)
	$SelectionTabs.Anchor = 'Top, Bottom, Left, Right'
	$SelectionTabs.Cursor = 'Hand'
	$SelectionTabs.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$SelectionTabs.HotTrack = $True
	$SelectionTabs.ImeMode = 'NoControl'
	$SelectionTabs.Location = New-Object System.Drawing.Point(12, 127)
	$SelectionTabs.Multiline = $True
	$SelectionTabs.Name = 'SelectionTabs'
	$SelectionTabs.SelectedIndex = 0
	$SelectionTabs.Size = New-Object System.Drawing.Size(1239, 616)
	$SelectionTabs.SizeMode = 'FillToRight'
	$SelectionTabs.TabIndex = 39
	#
	# MakeModelTab
	#
	$MakeModelTab.Controls.Add($MakeModelIcon)
	$MakeModelTab.Controls.Add($MakeModelTabLabel)
	$MakeModelTab.Controls.Add($PlatformPanel)
	$MakeModelTab.AutoScroll = $True
	$MakeModelTab.BackColor = [System.Drawing.Color]::Gray 
	$MakeModelTab.Location = New-Object System.Drawing.Point(4, 48)
	$MakeModelTab.Margin = '4, 4, 4, 4'
	$MakeModelTab.Name = 'MakeModelTab'
	$MakeModelTab.Padding = '3, 3, 3, 3'
	$MakeModelTab.Size = New-Object System.Drawing.Size(1231, 564)
	$MakeModelTab.TabIndex = 14
	$MakeModelTab.Text = 'Make & Model Selection'
	$MakeModelTab.ToolTipText = 'Select your required makes / models and operating system.'
	#
	# MakeModelIcon
	#
	$MakeModelIcon.BackColor = [System.Drawing.Color]::Gray 
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
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
AABJRU5ErkJgggs='))
	#endregion
	$MakeModelIcon.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$MakeModelIcon.Location = New-Object System.Drawing.Point(20, 16)
	$MakeModelIcon.Name = 'MakeModelIcon'
	$MakeModelIcon.Size = New-Object System.Drawing.Size(50, 50)
	$MakeModelIcon.SizeMode = 'StretchImage'
	$MakeModelIcon.TabIndex = 104
	$MakeModelIcon.TabStop = $False
	#
	# MakeModelTabLabel
	#
	$MakeModelTabLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '16', [System.Drawing.FontStyle]'Bold')
	$MakeModelTabLabel.ForeColor = [System.Drawing.Color]::White 
	$MakeModelTabLabel.Location = New-Object System.Drawing.Point(90, 24)
	$MakeModelTabLabel.Name = 'MakeModelTabLabel'
	$MakeModelTabLabel.Size = New-Object System.Drawing.Size(541, 56)
	$MakeModelTabLabel.TabIndex = 103
	$MakeModelTabLabel.Text = 'Make, Model and OS Selection'
	$MakeModelTabLabel.UseCompatibleTextRendering = $True
	#
	# PlatformPanel
	#
	$PlatformPanel.Controls.Add($DriverAppTab)
	$PlatformPanel.Controls.Add($OSGroup)
	$PlatformPanel.Controls.Add($DeploymentGroupBox)
	$PlatformPanel.Controls.Add($ManufacturerSelectionGroup)
	$PlatformPanel.Anchor = 'Top, Bottom, Left, Right'
	$PlatformPanel.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$PlatformPanel.Location = New-Object System.Drawing.Point(0, 83)
	$PlatformPanel.Name = 'PlatformPanel'
	$PlatformPanel.Size = New-Object System.Drawing.Size(1231, 481)
	$PlatformPanel.TabIndex = 105
	#
	# DriverAppTab
	#
	$DriverAppTab.Controls.Add($ModelDriverTab)
	$DriverAppTab.Anchor = 'Top, Bottom, Left, Right'
	$DriverAppTab.Location = New-Object System.Drawing.Point(4, 175)
	$DriverAppTab.Margin = '4, 4, 4, 4'
	$DriverAppTab.Name = 'DriverAppTab'
	$DriverAppTab.SelectedIndex = 0
	$DriverAppTab.Size = New-Object System.Drawing.Size(1223, 306)
	$DriverAppTab.SizeMode = 'FillToRight'
	$DriverAppTab.TabIndex = 66
	#
	# ModelDriverTab
	#
	$ModelDriverTab.Controls.Add($FindModelSelect)
	$ModelDriverTab.Controls.Add($SelectAll)
	$ModelDriverTab.Controls.Add($XMLLoading)
	$ModelDriverTab.Controls.Add($ModelResults)
	$ModelDriverTab.Controls.Add($ClearModelSelection)
	$ModelDriverTab.Controls.Add($FindModel)
	$ModelDriverTab.Controls.Add($labelSearchModels)
	$ModelDriverTab.Controls.Add($ModelSearchText)
	$ModelDriverTab.Controls.Add($MakeModelDataGrid)
	$ModelDriverTab.BackColor = [System.Drawing.Color]::Silver 
	$ModelDriverTab.Location = New-Object System.Drawing.Point(4, 26)
	$ModelDriverTab.Margin = '4, 4, 4, 4'
	$ModelDriverTab.Name = 'ModelDriverTab'
	$ModelDriverTab.Padding = '3, 3, 3, 3'
	$ModelDriverTab.Size = New-Object System.Drawing.Size(1215, 276)
	$ModelDriverTab.TabIndex = 0
	$ModelDriverTab.Text = 'Model Selection'
	#
	# FindModelSelect
	#
	$FindModelSelect.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$FindModelSelect.Cursor = 'Hand'
	$FindModelSelect.Enabled = $False
	$FindModelSelect.FlatStyle = 'Popup'
	$FindModelSelect.ForeColor = [System.Drawing.Color]::White 
	$FindModelSelect.Location = New-Object System.Drawing.Point(481, 9)
	$FindModelSelect.Name = 'FindModelSelect'
	$FindModelSelect.Size = New-Object System.Drawing.Size(126, 27)
	$FindModelSelect.TabIndex = 99
	$FindModelSelect.Text = 'Find + Select'
	$FindModelSelect.UseCompatibleTextRendering = $True
	$FindModelSelect.UseVisualStyleBackColor = $False
	$FindModelSelect.add_Click($FindModelSelect_Click)
	#
	# SelectAll
	#
	$SelectAll.Anchor = 'Top, Right'
	$SelectAll.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$SelectAll.Cursor = 'Hand'
	$SelectAll.Enabled = $False
	$SelectAll.FlatStyle = 'Popup'
	$SelectAll.ForeColor = [System.Drawing.Color]::White 
	$SelectAll.Location = New-Object System.Drawing.Point(881, 7)
	$SelectAll.Name = 'SelectAll'
	$SelectAll.Size = New-Object System.Drawing.Size(157, 27)
	$SelectAll.TabIndex = 12
	$SelectAll.Text = 'Select All'
	$SelectAll.UseCompatibleTextRendering = $True
	$SelectAll.UseVisualStyleBackColor = $False
	$SelectAll.add_Click($SelectAll_Click)
	#
	# XMLLoading
	#
	$XMLLoading.Controls.Add($XMLDownloadStatus)
	$XMLLoading.Controls.Add($XMLLoadingLabel)
	$XMLLoading.Anchor = 'Top, Left, Right'
	$XMLLoading.BackColor = [System.Drawing.Color]::FromArgb(255, 122, 0, 0)
	$XMLLoading.Cursor = 'WaitCursor'
	$XMLLoading.Location = New-Object System.Drawing.Point(359, 120)
	$XMLLoading.Name = 'XMLLoading'
	$XMLLoading.Size = New-Object System.Drawing.Size(449, 87)
	$XMLLoading.TabIndex = 98
	$XMLLoading.Visible = $False
	#
	# XMLDownloadStatus
	#
	$XMLDownloadStatus.Anchor = 'Top, Bottom, Left'
	$XMLDownloadStatus.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$XMLDownloadStatus.ForeColor = [System.Drawing.Color]::White 
	$XMLDownloadStatus.Location = New-Object System.Drawing.Point(0, 50)
	$XMLDownloadStatus.Name = 'XMLDownloadStatus'
	$XMLDownloadStatus.Size = New-Object System.Drawing.Size(446, 18)
	$XMLDownloadStatus.TabIndex = 1
	$XMLDownloadStatus.TextAlign = 'TopCenter'
	$XMLDownloadStatus.UseCompatibleTextRendering = $True
	$XMLDownloadStatus.Visible = $False
	#
	# XMLLoadingLabel
	#
	$XMLLoadingLabel.Anchor = 'Top, Bottom, Left'
	$XMLLoadingLabel.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$XMLLoadingLabel.ForeColor = [System.Drawing.Color]::White 
	$XMLLoadingLabel.Location = New-Object System.Drawing.Point(3, 25)
	$XMLLoadingLabel.Name = 'XMLLoadingLabel'
	$XMLLoadingLabel.Size = New-Object System.Drawing.Size(446, 21)
	$XMLLoadingLabel.TabIndex = 0
	$XMLLoadingLabel.Text = 'Loading XML Sources.. Please Wait..'
	$XMLLoadingLabel.TextAlign = 'TopCenter'
	$XMLLoadingLabel.UseCompatibleTextRendering = $True
	$XMLLoadingLabel.Visible = $False
	#
	# ModelResults
	#
	$ModelResults.AutoSize = $True
	$ModelResults.Location = New-Object System.Drawing.Point(620, 15)
	$ModelResults.Name = 'ModelResults'
	$ModelResults.Size = New-Object System.Drawing.Size(0, 22)
	$ModelResults.TabIndex = 12
	$ModelResults.UseCompatibleTextRendering = $True
	#
	# ClearModelSelection
	#
	$ClearModelSelection.Anchor = 'Top, Right'
	$ClearModelSelection.Cursor = 'Hand'
	$ClearModelSelection.Enabled = $False
	$ClearModelSelection.FlatStyle = 'Popup'
	$ClearModelSelection.Location = New-Object System.Drawing.Point(1044, 7)
	$ClearModelSelection.Name = 'ClearModelSelection'
	$ClearModelSelection.Size = New-Object System.Drawing.Size(160, 27)
	$ClearModelSelection.TabIndex = 13
	$ClearModelSelection.Text = 'Clear Selection'
	$ClearModelSelection.UseCompatibleTextRendering = $True
	$ClearModelSelection.UseVisualStyleBackColor = $True
	$ClearModelSelection.add_Click($ClearModelSelection_Click)
	#
	# FindModel
	#
	$FindModel.Cursor = 'Hand'
	$FindModel.Enabled = $False
	$FindModel.FlatStyle = 'Popup'
	$FindModel.Location = New-Object System.Drawing.Point(400, 9)
	$FindModel.Name = 'FindModel'
	$FindModel.Size = New-Object System.Drawing.Size(75, 27)
	$FindModel.TabIndex = 11
	$FindModel.Text = 'Find'
	$FindModel.UseCompatibleTextRendering = $True
	$FindModel.UseVisualStyleBackColor = $True
	$FindModel.add_Click($FindModel_Click)
	$FindModel.add_MouseEnter($FindModel_MouseEnter)
	$FindModel.add_MouseLeave($FindModel_MouseLeave)
	#
	# labelSearchModels
	#
	$labelSearchModels.AutoSize = $True
	$labelSearchModels.Location = New-Object System.Drawing.Point(17, 15)
	$labelSearchModels.Name = 'labelSearchModels'
	$labelSearchModels.Size = New-Object System.Drawing.Size(96, 23)
	$labelSearchModels.TabIndex = 7
	$labelSearchModels.Text = 'Search Models'
	$labelSearchModels.UseCompatibleTextRendering = $True
	#
	# ModelSearchText
	#
	$ModelSearchText.Enabled = $False
	$ModelSearchText.Location = New-Object System.Drawing.Point(130, 10)
	$ModelSearchText.Name = 'ModelSearchText'
	$ModelSearchText.Size = New-Object System.Drawing.Size(263, 25)
	$ModelSearchText.TabIndex = 10
	$ModelSearchText.add_KeyDown($ModelSearchText_KeyDown)
	#
	# MakeModelDataGrid
	#
	$MakeModelDataGrid.AllowUserToAddRows = $False
	$MakeModelDataGrid.AllowUserToDeleteRows = $False
	$MakeModelDataGrid.AllowUserToResizeRows = $False
	$MakeModelDataGrid.Anchor = 'Top, Bottom, Left, Right'
	$MakeModelDataGrid.AutoSizeColumnsMode = 'AllCells'
	$MakeModelDataGrid.AutoSizeRowsMode = 'AllCells'
	$MakeModelDataGrid.BackgroundColor = [System.Drawing.Color]::White 
	$System_Windows_Forms_DataGridViewCellStyle_1 = New-Object 'System.Windows.Forms.DataGridViewCellStyle'
	$System_Windows_Forms_DataGridViewCellStyle_1.Alignment = 'MiddleLeft'
	$System_Windows_Forms_DataGridViewCellStyle_1.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$System_Windows_Forms_DataGridViewCellStyle_1.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$System_Windows_Forms_DataGridViewCellStyle_1.ForeColor = [System.Drawing.SystemColors]::WindowText 
	$System_Windows_Forms_DataGridViewCellStyle_1.SelectionBackColor = [System.Drawing.SystemColors]::Highlight 
	$System_Windows_Forms_DataGridViewCellStyle_1.SelectionForeColor = [System.Drawing.SystemColors]::HighlightText 
	$System_Windows_Forms_DataGridViewCellStyle_1.WrapMode = 'True'
	$MakeModelDataGrid.ColumnHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_1
	$MakeModelDataGrid.ColumnHeadersHeight = 30
	[void]$MakeModelDataGrid.Columns.Add($ModelSelected)
	[void]$MakeModelDataGrid.Columns.Add($Manufacturer)
	[void]$MakeModelDataGrid.Columns.Add($ModelName)
	[void]$MakeModelDataGrid.Columns.Add($WindowsVersion)
	[void]$MakeModelDataGrid.Columns.Add($WindowsArchitecture)
	[void]$MakeModelDataGrid.Columns.Add($KnownModel)
	[void]$MakeModelDataGrid.Columns.Add($SearchResult)
	$System_Windows_Forms_DataGridViewCellStyle_2 = New-Object 'System.Windows.Forms.DataGridViewCellStyle'
	$System_Windows_Forms_DataGridViewCellStyle_2.Alignment = 'MiddleLeft'
	$System_Windows_Forms_DataGridViewCellStyle_2.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$System_Windows_Forms_DataGridViewCellStyle_2.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$System_Windows_Forms_DataGridViewCellStyle_2.ForeColor = [System.Drawing.SystemColors]::ControlText 
	$System_Windows_Forms_DataGridViewCellStyle_2.SelectionBackColor = [System.Drawing.Color]::Maroon 
	$System_Windows_Forms_DataGridViewCellStyle_2.SelectionForeColor = [System.Drawing.SystemColors]::HighlightText 
	$System_Windows_Forms_DataGridViewCellStyle_2.WrapMode = 'False'
	$MakeModelDataGrid.DefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_2
	$MakeModelDataGrid.GridColor = [System.Drawing.Color]::WhiteSmoke 
	$MakeModelDataGrid.Location = New-Object System.Drawing.Point(0, 44)
	$MakeModelDataGrid.Name = 'MakeModelDataGrid'
	$System_Windows_Forms_DataGridViewCellStyle_3 = New-Object 'System.Windows.Forms.DataGridViewCellStyle'
	$System_Windows_Forms_DataGridViewCellStyle_3.Alignment = 'MiddleLeft'
	$System_Windows_Forms_DataGridViewCellStyle_3.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$System_Windows_Forms_DataGridViewCellStyle_3.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$System_Windows_Forms_DataGridViewCellStyle_3.ForeColor = [System.Drawing.Color]::Black 
	$System_Windows_Forms_DataGridViewCellStyle_3.SelectionBackColor = [System.Drawing.Color]::Maroon 
	$System_Windows_Forms_DataGridViewCellStyle_3.SelectionForeColor = [System.Drawing.SystemColors]::HighlightText 
	$System_Windows_Forms_DataGridViewCellStyle_3.WrapMode = 'True'
	$MakeModelDataGrid.RowHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_3
	$MakeModelDataGrid.RowHeadersVisible = $False
	$MakeModelDataGrid.RowHeadersWidth = 20
	$MakeModelDataGrid.RowTemplate.DefaultCellStyle.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$MakeModelDataGrid.RowTemplate.Height = 24
	$MakeModelDataGrid.SelectionMode = 'FullRowSelect'
	$MakeModelDataGrid.Size = New-Object System.Drawing.Size(1211, 233)
	$MakeModelDataGrid.TabIndex = 2
	$MakeModelDataGrid.add_CurrentCellDirtyStateChanged($MakeModelDataGrid_CurrentCellDirtyStateChanged)
	$MakeModelDataGrid.add_RowsAdded($MakeModelDataGrid_RowsAdded)
	$MakeModelDataGrid.add_KeyPress($MakeModelDataGrid_KeyPress)
	#
	# OSGroup
	#
	$OSGroup.Controls.Add($ArchitectureComboxBox)
	$OSGroup.Controls.Add($OSComboBox)
	$OSGroup.Controls.Add($ArchitectureCheckBox)
	$OSGroup.Controls.Add($OperatingSysLabel)
	$OSGroup.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$OSGroup.ForeColor = [System.Drawing.Color]::Black 
	$OSGroup.Location = New-Object System.Drawing.Point(420, 5)
	$OSGroup.Name = 'OSGroup'
	$OSGroup.Size = New-Object System.Drawing.Size(305, 163)
	$OSGroup.TabIndex = 70
	$OSGroup.TabStop = $False
	$OSGroup.Text = 'Operating System Selection'
	$OSGroup.UseCompatibleTextRendering = $True
	#
	# ArchitectureComboxBox
	#
	$ArchitectureComboxBox.BackColor = [System.Drawing.Color]::White 
	$ArchitectureComboxBox.Cursor = 'Hand'
	$ArchitectureComboxBox.DropDownStyle = 'DropDownList'
	$ArchitectureComboxBox.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$ArchitectureComboxBox.ForeColor = [System.Drawing.Color]::Black 
	$ArchitectureComboxBox.FormattingEnabled = $True
	[void]$ArchitectureComboxBox.Items.Add('64 bit')
	[void]$ArchitectureComboxBox.Items.Add('32 bit')
	$ArchitectureComboxBox.Location = New-Object System.Drawing.Point(22, 119)
	$ArchitectureComboxBox.Margin = '4, 3, 4, 3'
	$ArchitectureComboxBox.Name = 'ArchitectureComboxBox'
	$ArchitectureComboxBox.Size = New-Object System.Drawing.Size(252, 25)
	$ArchitectureComboxBox.TabIndex = 4
	#
	# OSComboBox
	#
	$OSComboBox.BackColor = [System.Drawing.Color]::White 
	$OSComboBox.Cursor = 'Hand'
	$OSComboBox.DropDownStyle = 'DropDownList'
	$OSComboBox.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$OSComboBox.ForeColor = [System.Drawing.Color]::Black 
	$OSComboBox.FormattingEnabled = $True
	[void]$OSComboBox.Items.Add('Windows 10 2004')
	[void]$OSComboBox.Items.Add('Windows 10 1909')
	[void]$OSComboBox.Items.Add('Windows 10 1903')
	[void]$OSComboBox.Items.Add('Windows 10 1809')
	[void]$OSComboBox.Items.Add('Windows 10 1803')
	[void]$OSComboBox.Items.Add('Windows 10 1709')
	[void]$OSComboBox.Items.Add('Windows 10 1703')
	[void]$OSComboBox.Items.Add('Windows 10 1607')
	[void]$OSComboBox.Items.Add('Windows 10')
	$OSComboBox.Location = New-Object System.Drawing.Point(22, 64)
	$OSComboBox.Margin = '4, 3, 4, 3'
	$OSComboBox.Name = 'OSComboBox'
	$OSComboBox.Size = New-Object System.Drawing.Size(252, 25)
	$OSComboBox.TabIndex = 3
	$OSComboBox.add_SelectedIndexChanged($OSComboBox_SelectedIndexChanged)
	$OSComboBox.add_EnabledChanged($OSComboBox_EnabledChanged)
	$OSComboBox.add_TextChanged($OSComboBox_TextChanged)
	#
	# ArchitectureCheckBox
	#
	$ArchitectureCheckBox.AutoSize = $True
	$ArchitectureCheckBox.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10')
	$ArchitectureCheckBox.ForeColor = [System.Drawing.Color]::Black 
	$ArchitectureCheckBox.Location = New-Object System.Drawing.Point(22, 95)
	$ArchitectureCheckBox.Margin = '4, 0, 4, 0'
	$ArchitectureCheckBox.Name = 'ArchitectureCheckBox'
	$ArchitectureCheckBox.Size = New-Object System.Drawing.Size(81, 23)
	$ArchitectureCheckBox.TabIndex = 58
	$ArchitectureCheckBox.Text = 'Architecture'
	$ArchitectureCheckBox.UseCompatibleTextRendering = $True
	#
	# OperatingSysLabel
	#
	$OperatingSysLabel.AutoSize = $True
	$OperatingSysLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10')
	$OperatingSysLabel.ForeColor = [System.Drawing.Color]::Black 
	$OperatingSysLabel.Location = New-Object System.Drawing.Point(22, 41)
	$OperatingSysLabel.Margin = '4, 0, 4, 0'
	$OperatingSysLabel.Name = 'OperatingSysLabel'
	$OperatingSysLabel.Size = New-Object System.Drawing.Size(117, 23)
	$OperatingSysLabel.TabIndex = 57
	$OperatingSysLabel.Text = 'Operating System'
	$OperatingSysLabel.UseCompatibleTextRendering = $True
	#
	# DeploymentGroupBox
	#
	$DeploymentGroupBox.Controls.Add($DownloadComboBox)
	$DeploymentGroupBox.Controls.Add($PlatformComboBox)
	$DeploymentGroupBox.Controls.Add($SelectDeployLabel)
	$DeploymentGroupBox.Controls.Add($DownloadTypeLabel)
	$DeploymentGroupBox.FlatStyle = 'Flat'
	$DeploymentGroupBox.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$DeploymentGroupBox.ForeColor = [System.Drawing.Color]::Black 
	$DeploymentGroupBox.Location = New-Object System.Drawing.Point(11, 5)
	$DeploymentGroupBox.Name = 'DeploymentGroupBox'
	$DeploymentGroupBox.Size = New-Object System.Drawing.Size(403, 163)
	$DeploymentGroupBox.TabIndex = 69
	$DeploymentGroupBox.TabStop = $False
	$DeploymentGroupBox.Text = 'Platform / Download Type'
	$DeploymentGroupBox.UseCompatibleTextRendering = $True
	#
	# DownloadComboBox
	#
	$DownloadComboBox.BackColor = [System.Drawing.Color]::White 
	$DownloadComboBox.Cursor = 'Hand'
	$DownloadComboBox.DropDownStyle = 'DropDownList'
	$DownloadComboBox.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$DownloadComboBox.ForeColor = [System.Drawing.Color]::Black 
	$DownloadComboBox.FormattingEnabled = $True
	[void]$DownloadComboBox.Items.Add('Drivers')
	[void]$DownloadComboBox.Items.Add('BIOS')
	[void]$DownloadComboBox.Items.Add('All')
	$DownloadComboBox.Location = New-Object System.Drawing.Point(32, 120)
	$DownloadComboBox.Margin = '4, 3, 4, 3'
	$DownloadComboBox.Name = 'DownloadComboBox'
	$DownloadComboBox.Size = New-Object System.Drawing.Size(337, 25)
	$DownloadComboBox.TabIndex = 2
	$DownloadComboBox.add_SelectedIndexChanged($DownloadComboBox_SelectedIndexChanged)
	$DownloadComboBox.add_TextChanged($DownloadComboBox_TextChanged)
	#
	# PlatformComboBox
	#
	$PlatformComboBox.BackColor = [System.Drawing.Color]::White 
	$PlatformComboBox.Cursor = 'Hand'
	$PlatformComboBox.DropDownStyle = 'DropDownList'
	$PlatformComboBox.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$PlatformComboBox.ForeColor = [System.Drawing.Color]::Black 
	$PlatformComboBox.FormattingEnabled = $True
	[void]$PlatformComboBox.Items.Add('ConfigMgr - Driver Pkg')
	[void]$PlatformComboBox.Items.Add('ConfigMgr - Standard Pkg')
	[void]$PlatformComboBox.Items.Add('ConfigMgr - Standard Pkg (Pilot)')
	[void]$PlatformComboBox.Items.Add('Intune (Win32 App)')
	[void]$PlatformComboBox.Items.Add('MDT')
	[void]$PlatformComboBox.Items.Add('Both - ConfigMgr Driver Pkg & MDT')
	[void]$PlatformComboBox.Items.Add('Both - ConfigMgr Standard Pkg & MDT')
	[void]$PlatformComboBox.Items.Add('Download Only')
	[void]$PlatformComboBox.Items.Add('Download & Model XML Generation')
	$PlatformComboBox.Location = New-Object System.Drawing.Point(32, 65)
	$PlatformComboBox.Margin = '4, 3, 4, 3'
	$PlatformComboBox.Name = 'PlatformComboBox'
	$PlatformComboBox.Size = New-Object System.Drawing.Size(337, 25)
	$PlatformComboBox.TabIndex = 1
	$PlatformComboBox.add_SelectedIndexChanged($PlatformComboBox_SelectedIndexChanged)
	#
	# SelectDeployLabel
	#
	$SelectDeployLabel.AutoSize = $True
	$SelectDeployLabel.BackColor = [System.Drawing.Color]::Transparent 
	$SelectDeployLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10')
	$SelectDeployLabel.ForeColor = [System.Drawing.Color]::Black 
	$SelectDeployLabel.Location = New-Object System.Drawing.Point(32, 41)
	$SelectDeployLabel.Margin = '4, 0, 4, 0'
	$SelectDeployLabel.Name = 'SelectDeployLabel'
	$SelectDeployLabel.Size = New-Object System.Drawing.Size(139, 23)
	$SelectDeployLabel.TabIndex = 51
	$SelectDeployLabel.Text = 'Deployment Platform'
	$SelectDeployLabel.UseCompatibleTextRendering = $True
	#
	# DownloadTypeLabel
	#
	$DownloadTypeLabel.AutoSize = $True
	$DownloadTypeLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10')
	$DownloadTypeLabel.ForeColor = [System.Drawing.Color]::Black 
	$DownloadTypeLabel.Location = New-Object System.Drawing.Point(32, 96)
	$DownloadTypeLabel.Margin = '4, 0, 4, 0'
	$DownloadTypeLabel.Name = 'DownloadTypeLabel'
	$DownloadTypeLabel.Size = New-Object System.Drawing.Size(103, 23)
	$DownloadTypeLabel.TabIndex = 50
	$DownloadTypeLabel.Text = 'Download Type'
	$DownloadTypeLabel.UseCompatibleTextRendering = $True
	#
	# ManufacturerSelectionGroup
	#
	$ManufacturerSelectionGroup.Controls.Add($FindModelsButton)
	$ManufacturerSelectionGroup.Controls.Add($MicrosoftCheckBox)
	$ManufacturerSelectionGroup.Controls.Add($HPCheckBox)
	$ManufacturerSelectionGroup.Controls.Add($LenovoCheckBox)
	$ManufacturerSelectionGroup.Controls.Add($DellCheckBox)
	$ManufacturerSelectionGroup.Anchor = 'Top, Left, Right'
	$ManufacturerSelectionGroup.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$ManufacturerSelectionGroup.ForeColor = [System.Drawing.Color]::Black 
	$ManufacturerSelectionGroup.Location = New-Object System.Drawing.Point(731, 5)
	$ManufacturerSelectionGroup.Name = 'ManufacturerSelectionGroup'
	$ManufacturerSelectionGroup.Size = New-Object System.Drawing.Size(494, 163)
	$ManufacturerSelectionGroup.TabIndex = 68
	$ManufacturerSelectionGroup.TabStop = $False
	$ManufacturerSelectionGroup.Text = 'Manufacturer Selection'
	$ManufacturerSelectionGroup.UseCompatibleTextRendering = $True
	#
	# FindModelsButton
	#
	$FindModelsButton.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$FindModelsButton.Cursor = 'Hand'
	$FindModelsButton.FlatStyle = 'Popup'
	$FindModelsButton.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$FindModelsButton.ForeColor = [System.Drawing.Color]::White 
	$FindModelsButton.Location = New-Object System.Drawing.Point(214, 52)
	$FindModelsButton.Margin = '4, 3, 4, 3'
	$FindModelsButton.Name = 'FindModelsButton'
	$FindModelsButton.Size = New-Object System.Drawing.Size(158, 67)
	$FindModelsButton.TabIndex = 9
	$FindModelsButton.Text = 'Find Models'
	$FindModelsButton.UseCompatibleTextRendering = $True
	$FindModelsButton.UseVisualStyleBackColor = $False
	$FindModelsButton.add_EnabledChanged($FindModelsButton_EnabledChanged)
	$FindModelsButton.add_Click($FindModelsButton_Click)
	$FindModelsButton.add_MouseEnter($FindModelsButton_MouseEnter)
	$FindModelsButton.add_MouseLeave($FindModelsButton_MouseLeave)
	#
	# MicrosoftCheckBox
	#
	$MicrosoftCheckBox.Cursor = 'Hand'
	$MicrosoftCheckBox.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10')
	$MicrosoftCheckBox.ForeColor = [System.Drawing.Color]::Black 
	$MicrosoftCheckBox.Location = New-Object System.Drawing.Point(24, 125)
	$MicrosoftCheckBox.Name = 'MicrosoftCheckBox'
	$MicrosoftCheckBox.Size = New-Object System.Drawing.Size(124, 24)
	$MicrosoftCheckBox.TabIndex = 8
	$MicrosoftCheckBox.Text = 'Microsoft'
	$MicrosoftCheckBox.UseCompatibleTextRendering = $True
	$MicrosoftCheckBox.UseVisualStyleBackColor = $True
	$MicrosoftCheckBox.add_CheckedChanged($MicrosoftCheckBox_CheckedChanged)
	#
	# HPCheckBox
	#
	$HPCheckBox.Cursor = 'Hand'
	$HPCheckBox.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10')
	$HPCheckBox.ForeColor = [System.Drawing.Color]::Black 
	$HPCheckBox.Location = New-Object System.Drawing.Point(24, 95)
	$HPCheckBox.Name = 'HPCheckBox'
	$HPCheckBox.Size = New-Object System.Drawing.Size(183, 24)
	$HPCheckBox.TabIndex = 7
	$HPCheckBox.Text = 'Hewlett-Packard'
	$HPCheckBox.UseCompatibleTextRendering = $True
	$HPCheckBox.UseVisualStyleBackColor = $True
	$HPCheckBox.add_CheckedChanged($HPCheckBox_CheckedChanged)
	#
	# LenovoCheckBox
	#
	$LenovoCheckBox.Cursor = 'Hand'
	$LenovoCheckBox.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10')
	$LenovoCheckBox.ForeColor = [System.Drawing.Color]::Black 
	$LenovoCheckBox.Location = New-Object System.Drawing.Point(24, 67)
	$LenovoCheckBox.Name = 'LenovoCheckBox'
	$LenovoCheckBox.Size = New-Object System.Drawing.Size(104, 22)
	$LenovoCheckBox.TabIndex = 6
	$LenovoCheckBox.Text = 'Lenovo'
	$LenovoCheckBox.UseCompatibleTextRendering = $True
	$LenovoCheckBox.UseVisualStyleBackColor = $True
	$LenovoCheckBox.add_CheckedChanged($LenovoCheckBox_CheckedChanged)
	#
	# DellCheckBox
	#
	$DellCheckBox.Cursor = 'Hand'
	$DellCheckBox.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10')
	$DellCheckBox.ForeColor = [System.Drawing.Color]::Black 
	$DellCheckBox.Location = New-Object System.Drawing.Point(24, 37)
	$DellCheckBox.Name = 'DellCheckBox'
	$DellCheckBox.Size = New-Object System.Drawing.Size(104, 24)
	$DellCheckBox.TabIndex = 5
	$DellCheckBox.Text = 'Dell'
	$DellCheckBox.UseCompatibleTextRendering = $True
	$DellCheckBox.UseVisualStyleBackColor = $True
	$DellCheckBox.add_CheckedChanged($DellCheckBox_CheckedChanged)
	#
	# OEMCatalogs
	#
	$OEMCatalogs.Controls.Add($tabcontrol2)
	$OEMCatalogs.Controls.Add($picturebox3)
	$OEMCatalogs.Controls.Add($OEMDriverLabel)
	$OEMCatalogs.BackColor = [System.Drawing.Color]::Gray 
	$OEMCatalogs.Location = New-Object System.Drawing.Point(4, 48)
	$OEMCatalogs.Name = 'OEMCatalogs'
	$OEMCatalogs.Size = New-Object System.Drawing.Size(1231, 564)
	$OEMCatalogs.TabIndex = 0
	$OEMCatalogs.Text = 'OEM Driver Catalogs'
	#
	# tabcontrol2
	#
	$tabcontrol2.Controls.Add($HPCatalog)
	$tabcontrol2.Anchor = 'Top, Bottom, Left, Right'
	$tabcontrol2.Location = New-Object System.Drawing.Point(4, 86)
	$tabcontrol2.Margin = '4, 4, 4, 4'
	$tabcontrol2.Name = 'tabcontrol2'
	$tabcontrol2.SelectedIndex = 0
	$tabcontrol2.Size = New-Object System.Drawing.Size(1223, 474)
	$tabcontrol2.SizeMode = 'FillToRight'
	$tabcontrol2.TabIndex = 107
	#
	# HPCatalog
	#
	$HPCatalog.Controls.Add($RefreshSoftPaqSelection)
	$HPCatalog.Controls.Add($DownloadSoftPaqs)
	$HPCatalog.Controls.Add($ResetSoftPaqSelection)
	$HPCatalog.Controls.Add($SelectAllSoftPaqs)
	$HPCatalog.Controls.Add($HPSoftPaqGridPopup)
	$HPCatalog.Controls.Add($labelModelFilter)
	$HPCatalog.Controls.Add($HPCatalogModels)
	$HPCatalog.Controls.Add($SoftpaqResults)
	$HPCatalog.Controls.Add($FindSoftPaq)
	$HPCatalog.Controls.Add($SoftpaqSearchCatalog)
	$HPCatalog.Controls.Add($HPSearchText)
	$HPCatalog.Controls.Add($HPSoftpaqDataGrid)
	$HPCatalog.BackColor = [System.Drawing.Color]::Silver 
	$HPCatalog.Location = New-Object System.Drawing.Point(4, 26)
	$HPCatalog.Margin = '4, 4, 4, 4'
	$HPCatalog.Name = 'HPCatalog'
	$HPCatalog.Size = New-Object System.Drawing.Size(1215, 444)
	$HPCatalog.TabIndex = 1
	$HPCatalog.Text = 'HP Driver Catalog'
	#
	# RefreshSoftPaqSelection
	#
	$RefreshSoftPaqSelection.Anchor = 'Bottom, Right'
	$RefreshSoftPaqSelection.Enabled = $False
	$RefreshSoftPaqSelection.FlatStyle = 'Popup'
	$RefreshSoftPaqSelection.Location = New-Object System.Drawing.Point(354, 405)
	$RefreshSoftPaqSelection.Name = 'RefreshSoftPaqSelection'
	$RefreshSoftPaqSelection.Size = New-Object System.Drawing.Size(157, 30)
	$RefreshSoftPaqSelection.TabIndex = 110
	$RefreshSoftPaqSelection.Text = 'Refresh List'
	$RefreshSoftPaqSelection.UseCompatibleTextRendering = $True
	$RefreshSoftPaqSelection.UseVisualStyleBackColor = $True
	$RefreshSoftPaqSelection.add_Click($RefreshSoftPaqSelection_Click)
	#
	# DownloadSoftPaqs
	#
	$DownloadSoftPaqs.Anchor = 'Bottom, Right'
	$DownloadSoftPaqs.AutoEllipsis = $True
	$DownloadSoftPaqs.BackColor = [System.Drawing.Color]::Maroon 
	$DownloadSoftPaqs.Enabled = $False
	$DownloadSoftPaqs.FlatStyle = 'Popup'
	$DownloadSoftPaqs.ForeColor = [System.Drawing.Color]::White 
	$DownloadSoftPaqs.Location = New-Object System.Drawing.Point(972, 402)
	$DownloadSoftPaqs.Name = 'DownloadSoftPaqs'
	$DownloadSoftPaqs.Size = New-Object System.Drawing.Size(226, 30)
	$DownloadSoftPaqs.TabIndex = 109
	$DownloadSoftPaqs.Text = 'Download SoftPaqs'
	$DownloadSoftPaqs.UseCompatibleTextRendering = $True
	$DownloadSoftPaqs.UseVisualStyleBackColor = $False
	$DownloadSoftPaqs.add_Click($DownloadSoftPaqs_Click)
	#
	# ResetSoftPaqSelection
	#
	$ResetSoftPaqSelection.Anchor = 'Bottom, Right'
	$ResetSoftPaqSelection.Enabled = $False
	$ResetSoftPaqSelection.FlatStyle = 'Popup'
	$ResetSoftPaqSelection.Location = New-Object System.Drawing.Point(182, 405)
	$ResetSoftPaqSelection.Name = 'ResetSoftPaqSelection'
	$ResetSoftPaqSelection.Size = New-Object System.Drawing.Size(157, 30)
	$ResetSoftPaqSelection.TabIndex = 108
	$ResetSoftPaqSelection.Text = 'Select None'
	$ResetSoftPaqSelection.UseCompatibleTextRendering = $True
	$ResetSoftPaqSelection.UseVisualStyleBackColor = $True
	$ResetSoftPaqSelection.add_Click($ResetSoftPaqSelection_Click)
	#
	# SelectAllSoftPaqs
	#
	$SelectAllSoftPaqs.Anchor = 'Bottom, Right'
	$SelectAllSoftPaqs.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$SelectAllSoftPaqs.Enabled = $False
	$SelectAllSoftPaqs.FlatStyle = 'Popup'
	$SelectAllSoftPaqs.ForeColor = [System.Drawing.Color]::White 
	$SelectAllSoftPaqs.Location = New-Object System.Drawing.Point(12, 405)
	$SelectAllSoftPaqs.Name = 'SelectAllSoftPaqs'
	$SelectAllSoftPaqs.Size = New-Object System.Drawing.Size(157, 30)
	$SelectAllSoftPaqs.TabIndex = 100
	$SelectAllSoftPaqs.Text = 'Select All'
	$SelectAllSoftPaqs.UseCompatibleTextRendering = $True
	$SelectAllSoftPaqs.UseVisualStyleBackColor = $False
	$SelectAllSoftPaqs.add_Click($SelectAllSoftPaqs_Click)
	#
	# HPSoftPaqGridPopup
	#
	$HPSoftPaqGridPopup.Controls.Add($HPSoftPaqGridStatus)
	$HPSoftPaqGridPopup.Controls.Add($HPSoftpaqGridNotice)
	$HPSoftPaqGridPopup.Anchor = 'Top, Left, Right'
	$HPSoftPaqGridPopup.BackColor = [System.Drawing.Color]::FromArgb(255, 122, 0, 0)
	$HPSoftPaqGridPopup.Cursor = 'WaitCursor'
	$HPSoftPaqGridPopup.Location = New-Object System.Drawing.Point(383, 182)
	$HPSoftPaqGridPopup.Name = 'HPSoftPaqGridPopup'
	$HPSoftPaqGridPopup.Size = New-Object System.Drawing.Size(449, 87)
	$HPSoftPaqGridPopup.TabIndex = 99
	$HPSoftPaqGridPopup.Visible = $False
	#
	# HPSoftPaqGridStatus
	#
	$HPSoftPaqGridStatus.Anchor = 'Top, Bottom, Left'
	$HPSoftPaqGridStatus.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$HPSoftPaqGridStatus.ForeColor = [System.Drawing.Color]::White 
	$HPSoftPaqGridStatus.Location = New-Object System.Drawing.Point(0, 50)
	$HPSoftPaqGridStatus.Name = 'HPSoftPaqGridStatus'
	$HPSoftPaqGridStatus.Size = New-Object System.Drawing.Size(446, 18)
	$HPSoftPaqGridStatus.TabIndex = 1
	$HPSoftPaqGridStatus.TextAlign = 'TopCenter'
	$HPSoftPaqGridStatus.UseCompatibleTextRendering = $True
	$HPSoftPaqGridStatus.Visible = $False
	#
	# HPSoftpaqGridNotice
	#
	$HPSoftpaqGridNotice.Anchor = 'Top, Bottom, Left'
	$HPSoftpaqGridNotice.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$HPSoftpaqGridNotice.ForeColor = [System.Drawing.Color]::White 
	$HPSoftpaqGridNotice.Location = New-Object System.Drawing.Point(3, 25)
	$HPSoftpaqGridNotice.Name = 'HPSoftpaqGridNotice'
	$HPSoftpaqGridNotice.Size = New-Object System.Drawing.Size(446, 21)
	$HPSoftpaqGridNotice.TabIndex = 0
	$HPSoftpaqGridNotice.Text = 'Loading XML Sources.. Please Wait..'
	$HPSoftpaqGridNotice.TextAlign = 'TopCenter'
	$HPSoftpaqGridNotice.UseCompatibleTextRendering = $True
	$HPSoftpaqGridNotice.Visible = $False
	#
	# labelModelFilter
	#
	$labelModelFilter.AutoSize = $True
	$labelModelFilter.Location = New-Object System.Drawing.Point(805, 18)
	$labelModelFilter.Name = 'labelModelFilter'
	$labelModelFilter.Size = New-Object System.Drawing.Size(80, 23)
	$labelModelFilter.TabIndex = 19
	$labelModelFilter.Text = 'Model Filter'
	$labelModelFilter.UseCompatibleTextRendering = $True
	#
	# HPCatalogModels
	#
	$HPCatalogModels.Enabled = $False
	$HPCatalogModels.FormattingEnabled = $True
	[void]$HPCatalogModels.Items.Add('All Generic Downloads')
	$HPCatalogModels.Location = New-Object System.Drawing.Point(893, 14)
	$HPCatalogModels.Name = 'HPCatalogModels'
	$HPCatalogModels.Size = New-Object System.Drawing.Size(306, 25)
	$HPCatalogModels.Sorted = $True
	$HPCatalogModels.TabIndex = 18
	$HPCatalogModels.add_SelectedIndexChanged($HPCatalogModels_SelectedIndexChanged)
	#
	# SoftpaqResults
	#
	$SoftpaqResults.AutoSize = $True
	$SoftpaqResults.Location = New-Object System.Drawing.Point(600, 15)
	$SoftpaqResults.Name = 'SoftpaqResults'
	$SoftpaqResults.Size = New-Object System.Drawing.Size(24, 23)
	$SoftpaqResults.TabIndex = 16
	$SoftpaqResults.Text = '     '
	$SoftpaqResults.UseCompatibleTextRendering = $True
	#
	# FindSoftPaq
	#
	$FindSoftPaq.Enabled = $False
	$FindSoftPaq.FlatStyle = 'Popup'
	$FindSoftPaq.Location = New-Object System.Drawing.Point(495, 11)
	$FindSoftPaq.Name = 'FindSoftPaq'
	$FindSoftPaq.Size = New-Object System.Drawing.Size(75, 30)
	$FindSoftPaq.TabIndex = 14
	$FindSoftPaq.Text = 'Find'
	$FindSoftPaq.UseCompatibleTextRendering = $True
	$FindSoftPaq.UseVisualStyleBackColor = $True
	$FindSoftPaq.add_Click($FindSoftPaq_Click)
	#
	# SoftpaqSearchCatalog
	#
	$SoftpaqSearchCatalog.AutoSize = $True
	$SoftpaqSearchCatalog.Location = New-Object System.Drawing.Point(10, 17)
	$SoftpaqSearchCatalog.Name = 'SoftpaqSearchCatalog'
	$SoftpaqSearchCatalog.Size = New-Object System.Drawing.Size(173, 23)
	$SoftpaqSearchCatalog.TabIndex = 13
	$SoftpaqSearchCatalog.Text = 'Search HP SoftPaq Catalog'
	$SoftpaqSearchCatalog.UseCompatibleTextRendering = $True
	#
	# HPSearchText
	#
	$HPSearchText.Location = New-Object System.Drawing.Point(194, 14)
	$HPSearchText.Name = 'HPSearchText'
	$HPSearchText.Size = New-Object System.Drawing.Size(289, 25)
	$HPSearchText.TabIndex = 12
	#
	# HPSoftpaqDataGrid
	#
	$HPSoftpaqDataGrid.AllowUserToAddRows = $False
	$HPSoftpaqDataGrid.AllowUserToDeleteRows = $False
	$HPSoftpaqDataGrid.AllowUserToResizeRows = $False
	$HPSoftpaqDataGrid.Anchor = 'Top, Bottom, Left, Right'
	$HPSoftpaqDataGrid.AutoSizeColumnsMode = 'AllCells'
	$HPSoftpaqDataGrid.AutoSizeRowsMode = 'AllCells'
	$HPSoftpaqDataGrid.BackgroundColor = [System.Drawing.Color]::WhiteSmoke 
	$HPSoftpaqDataGrid.ColumnHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_1
	$HPSoftpaqDataGrid.ColumnHeadersHeight = 30
	$HPSoftpaqDataGrid.ColumnHeadersHeightSizeMode = 'DisableResizing'
	[void]$HPSoftpaqDataGrid.Columns.Add($HPCatalogueSelected)
	[void]$HPSoftpaqDataGrid.Columns.Add($HPSoftPaqTitle)
	[void]$HPSoftpaqDataGrid.Columns.Add($HPCatalogueDescription)
	[void]$HPSoftpaqDataGrid.Columns.Add($SoftPaqVersion)
	[void]$HPSoftpaqDataGrid.Columns.Add($Created)
	[void]$HPSoftpaqDataGrid.Columns.Add($HPCatalogueSeverity)
	[void]$HPSoftpaqDataGrid.Columns.Add($PackageCreated)
	[void]$HPSoftpaqDataGrid.Columns.Add($SoftPaqURL)
	[void]$HPSoftpaqDataGrid.Columns.Add($SilentSetup)
	[void]$HPSoftpaqDataGrid.Columns.Add($BaseBoardModels)
	[void]$HPSoftpaqDataGrid.Columns.Add($SoftPaqMatch)
	[void]$HPSoftpaqDataGrid.Columns.Add($SupportedBuild)
	$HPSoftpaqDataGrid.DefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_2
	$HPSoftpaqDataGrid.GridColor = [System.Drawing.Color]::WhiteSmoke 
	$HPSoftpaqDataGrid.Location = New-Object System.Drawing.Point(0, 54)
	$HPSoftpaqDataGrid.Name = 'HPSoftpaqDataGrid'
	$HPSoftpaqDataGrid.RowHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_3
	$HPSoftpaqDataGrid.RowHeadersVisible = $False
	$HPSoftpaqDataGrid.RowHeadersWidth = 31
	$HPSoftpaqDataGrid.RowTemplate.DefaultCellStyle.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$HPSoftpaqDataGrid.RowTemplate.Height = 24
	$HPSoftpaqDataGrid.SelectionMode = 'FullRowSelect'
	$HPSoftpaqDataGrid.Size = New-Object System.Drawing.Size(1212, 338)
	$HPSoftpaqDataGrid.TabIndex = 3
	$HPSoftpaqDataGrid.add_CurrentCellDirtyStateChanged($HPSoftpaqDataGrid_CurrentCellDirtyStateChanged)
	#
	# picturebox3
	#
	$picturebox3.BackColor = [System.Drawing.Color]::Gray 
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
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
AABJRU5ErkJgggs='))
	#endregion
	$picturebox3.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$picturebox3.Location = New-Object System.Drawing.Point(20, 16)
	$picturebox3.Name = 'picturebox3'
	$picturebox3.Size = New-Object System.Drawing.Size(50, 50)
	$picturebox3.SizeMode = 'StretchImage'
	$picturebox3.TabIndex = 106
	$picturebox3.TabStop = $False
	#
	# OEMDriverLabel
	#
	$OEMDriverLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '16', [System.Drawing.FontStyle]'Bold')
	$OEMDriverLabel.ForeColor = [System.Drawing.Color]::White 
	$OEMDriverLabel.Location = New-Object System.Drawing.Point(90, 24)
	$OEMDriverLabel.Name = 'OEMDriverLabel'
	$OEMDriverLabel.Size = New-Object System.Drawing.Size(541, 56)
	$OEMDriverLabel.TabIndex = 105
	$OEMDriverLabel.Text = 'OEM Driver Catalogs'
	$OEMDriverLabel.UseCompatibleTextRendering = $True
	#
	# CommonTab
	#
	$CommonTab.Controls.Add($tabcontrol1)
	$CommonTab.Controls.Add($picturebox2)
	$CommonTab.Controls.Add($labelCommonSettings)
	$CommonTab.BackColor = [System.Drawing.Color]::Gray 
	$CommonTab.Location = New-Object System.Drawing.Point(4, 48)
	$CommonTab.Name = 'CommonTab'
	$CommonTab.Size = New-Object System.Drawing.Size(1231, 564)
	$CommonTab.TabIndex = 16
	$CommonTab.Text = 'Common Settings'
	#
	# tabcontrol1
	#
	$tabcontrol1.Controls.Add($tabpage1)
	$tabcontrol1.Controls.Add($tabpage2)
	$tabcontrol1.Controls.Add($tabpage3)
	$tabcontrol1.Anchor = 'Top, Bottom, Left, Right'
	$tabcontrol1.Location = New-Object System.Drawing.Point(0, 83)
	$tabcontrol1.Name = 'tabcontrol1'
	$tabcontrol1.SelectedIndex = 0
	$tabcontrol1.Size = New-Object System.Drawing.Size(1306, 552)
	$tabcontrol1.TabIndex = 105
	#
	# tabpage1
	#
	$tabpage1.Controls.Add($StoageGroupBox)
	$tabpage1.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$tabpage1.Location = New-Object System.Drawing.Point(4, 26)
	$tabpage1.Name = 'tabpage1'
	$tabpage1.Padding = '3, 3, 3, 3'
	$tabpage1.Size = New-Object System.Drawing.Size(1298, 522)
	$tabpage1.TabIndex = 0
	$tabpage1.Text = 'Storage Locations'
	#
	# StoageGroupBox
	#
	$StoageGroupBox.Controls.Add($textbox8)
	$StoageGroupBox.Controls.Add($textbox7)
	$StoageGroupBox.Controls.Add($StoragePathInstruction)
	$StoageGroupBox.Controls.Add($DownloadLabel)
	$StoageGroupBox.Controls.Add($DownloadBrowseButton)
	$StoageGroupBox.Controls.Add($DownloadPathTextBox)
	$StoageGroupBox.Anchor = 'Top, Bottom, Left, Right'
	$StoageGroupBox.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$StoageGroupBox.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$StoageGroupBox.Location = New-Object System.Drawing.Point(11, 16)
	$StoageGroupBox.Name = 'StoageGroupBox'
	$StoageGroupBox.Size = New-Object System.Drawing.Size(1281, 503)
	$StoageGroupBox.TabIndex = 85
	$StoageGroupBox.TabStop = $False
	$StoageGroupBox.Text = 'Storage Paths'
	$StoageGroupBox.UseCompatibleTextRendering = $True
	#
	# textbox8
	#
	$textbox8.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$textbox8.BorderStyle = 'None'
	$textbox8.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$textbox8.ForeColor = [System.Drawing.Color]::Black 
	$textbox8.Location = New-Object System.Drawing.Point(22, 242)
	$textbox8.Multiline = $True
	$textbox8.Name = 'textbox8'
	$textbox8.ReadOnly = $True
	$textbox8.Size = New-Object System.Drawing.Size(1147, 68)
	$textbox8.TabIndex = 106
	$textbox8.TabStop = $False
	$textbox8.Text = 'NOTE: Configuration Manager jobs require a seperate storage location to be specified for the end packages. This should be configured on the ConfigMgr Settings section.'
	#
	# textbox7
	#
	$textbox7.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$textbox7.BorderStyle = 'None'
	$textbox7.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$textbox7.ForeColor = [System.Drawing.Color]::Black 
	$textbox7.Location = New-Object System.Drawing.Point(22, 188)
	$textbox7.Multiline = $True
	$textbox7.Name = 'textbox7'
	$textbox7.ReadOnly = $True
	$textbox7.Size = New-Object System.Drawing.Size(1147, 95)
	$textbox7.TabIndex = 105
	$textbox7.TabStop = $False
	$textbox7.Text = 'NOTE: When selecting large numbers of models, ensure that you have adequate disk space for the download files and subsequent driver/BIOS extractions. You should use an average of 2GB per model for storage planning, you can recover this space automatically with clean up options selected.'
	#
	# StoragePathInstruction
	#
	$StoragePathInstruction.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$StoragePathInstruction.BorderStyle = 'None'
	$StoragePathInstruction.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$StoragePathInstruction.ForeColor = [System.Drawing.Color]::Black 
	$StoragePathInstruction.Location = New-Object System.Drawing.Point(22, 50)
	$StoragePathInstruction.Multiline = $True
	$StoragePathInstruction.Name = 'StoragePathInstruction'
	$StoragePathInstruction.ReadOnly = $True
	$StoragePathInstruction.Size = New-Object System.Drawing.Size(1147, 28)
	$StoragePathInstruction.TabIndex = 104
	$StoragePathInstruction.TabStop = $False
	$StoragePathInstruction.Text = 'Storage paths are required for downloading, extraction and packaging of your downloads. ConfigMgr packages require a package path, all other options require only a download path.'
	#
	# DownloadLabel
	#
	$DownloadLabel.AutoSize = $True
	$DownloadLabel.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$DownloadLabel.ForeColor = [System.Drawing.Color]::Black 
	$DownloadLabel.Location = New-Object System.Drawing.Point(22, 92)
	$DownloadLabel.Margin = '4, 0, 4, 0'
	$DownloadLabel.Name = 'DownloadLabel'
	$DownloadLabel.Size = New-Object System.Drawing.Size(104, 23)
	$DownloadLabel.TabIndex = 80
	$DownloadLabel.Text = 'Download Path'
	$DownloadLabel.UseCompatibleTextRendering = $True
	#
	# DownloadBrowseButton
	#
	$DownloadBrowseButton.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$DownloadBrowseButton.FlatStyle = 'Popup'
	$DownloadBrowseButton.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$DownloadBrowseButton.ForeColor = [System.Drawing.Color]::White 
	$DownloadBrowseButton.Location = New-Object System.Drawing.Point(461, 127)
	$DownloadBrowseButton.Margin = '4, 4, 4, 4'
	$DownloadBrowseButton.Name = 'DownloadBrowseButton'
	$DownloadBrowseButton.Size = New-Object System.Drawing.Size(116, 27)
	$DownloadBrowseButton.TabIndex = 79
	$DownloadBrowseButton.Text = 'Browse'
	$DownloadBrowseButton.UseCompatibleTextRendering = $True
	$DownloadBrowseButton.UseVisualStyleBackColor = $False
	$DownloadBrowseButton.add_Click($DownloadBrowseButton_Click)
	#
	# DownloadPathTextBox
	#
	$DownloadPathTextBox.AutoCompleteMode = 'SuggestAppend'
	$DownloadPathTextBox.AutoCompleteSource = 'FileSystemDirectories'
	$DownloadPathTextBox.BackColor = [System.Drawing.Color]::White 
	$DownloadPathTextBox.Font = [System.Drawing.Font]::new('Segoe UI', '11.25')
	$DownloadPathTextBox.Location = New-Object System.Drawing.Point(22, 127)
	$DownloadPathTextBox.Margin = '4, 4, 4, 4'
	$DownloadPathTextBox.Name = 'DownloadPathTextBox'
	$DownloadPathTextBox.Size = New-Object System.Drawing.Size(431, 27)
	$DownloadPathTextBox.TabIndex = 78
	$DownloadPathTextBox.Text = '\\server\sharename'
	#
	# tabpage2
	#
	$tabpage2.Controls.Add($SchedulingGroupBox)
	$tabpage2.Controls.Add($ProxyGroupBox)
	$tabpage2.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$tabpage2.Location = New-Object System.Drawing.Point(4, 26)
	$tabpage2.Name = 'tabpage2'
	$tabpage2.Padding = '3, 3, 3, 3'
	$tabpage2.Size = New-Object System.Drawing.Size(1298, 522)
	$tabpage2.TabIndex = 1
	$tabpage2.Text = 'Proxy Server / Auto-Scheduling'
	#
	# SchedulingGroupBox
	#
	$SchedulingGroupBox.Controls.Add($SchedulingInstruction)
	$SchedulingGroupBox.Controls.Add($ScriptDirectoryBrowseButton)
	$SchedulingGroupBox.Controls.Add($UsernameTextBox)
	$SchedulingGroupBox.Controls.Add($TimeComboBox)
	$SchedulingGroupBox.Controls.Add($ScheduleJobButton)
	$SchedulingGroupBox.Controls.Add($ScheduleUserName)
	$SchedulingGroupBox.Controls.Add($SchedulePassword)
	$SchedulingGroupBox.Controls.Add($PasswordTextBox)
	$SchedulingGroupBox.Controls.Add($ScheduleLocation)
	$SchedulingGroupBox.Controls.Add($ScheduleTime)
	$SchedulingGroupBox.Controls.Add($ScriptLocation)
	$SchedulingGroupBox.Anchor = 'Top, Left, Right'
	$SchedulingGroupBox.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$SchedulingGroupBox.Location = New-Object System.Drawing.Point(609, 19)
	$SchedulingGroupBox.Name = 'SchedulingGroupBox'
	$SchedulingGroupBox.Size = New-Object System.Drawing.Size(649, 433)
	$SchedulingGroupBox.TabIndex = 106
	$SchedulingGroupBox.TabStop = $False
	$SchedulingGroupBox.Text = 'Scheduling'
	$SchedulingGroupBox.UseCompatibleTextRendering = $True
	#
	# SchedulingInstruction
	#
	$SchedulingInstruction.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$SchedulingInstruction.BorderStyle = 'None'
	$SchedulingInstruction.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$SchedulingInstruction.ForeColor = [System.Drawing.Color]::Black 
	$SchedulingInstruction.Location = New-Object System.Drawing.Point(17, 57)
	$SchedulingInstruction.Multiline = $True
	$SchedulingInstruction.Name = 'SchedulingInstruction'
	$SchedulingInstruction.ReadOnly = $True
	$SchedulingInstruction.Size = New-Object System.Drawing.Size(576, 93)
	$SchedulingInstruction.TabIndex = 113
	$SchedulingInstruction.TabStop = $False
	$SchedulingInstruction.Text = 'In this section you can schedule daily automated running of the driver automation tool. Note that the user account should have rights to ConfigMgr and run as a service rights'
	#
	# ScriptDirectoryBrowseButton
	#
	$ScriptDirectoryBrowseButton.Location = New-Object System.Drawing.Point(449, 220)
	$ScriptDirectoryBrowseButton.Margin = '4, 4, 4, 4'
	$ScriptDirectoryBrowseButton.Name = 'ScriptDirectoryBrowseButton'
	$ScriptDirectoryBrowseButton.Size = New-Object System.Drawing.Size(45, 25)
	$ScriptDirectoryBrowseButton.TabIndex = 112
	$ScriptDirectoryBrowseButton.Text = '...'
	$ScriptDirectoryBrowseButton.UseCompatibleTextRendering = $True
	$ScriptDirectoryBrowseButton.UseVisualStyleBackColor = $True
	#
	# UsernameTextBox
	#
	$UsernameTextBox.BackColor = [System.Drawing.Color]::White 
	$UsernameTextBox.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$UsernameTextBox.Location = New-Object System.Drawing.Point(227, 259)
	$UsernameTextBox.Margin = '2, 2, 2, 2'
	$UsernameTextBox.Name = 'UsernameTextBox'
	$UsernameTextBox.Size = New-Object System.Drawing.Size(216, 23)
	$UsernameTextBox.TabIndex = 105
	#
	# TimeComboBox
	#
	$TimeComboBox.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$TimeComboBox.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$TimeComboBox.FormatString = 't'
	$TimeComboBox.FormattingEnabled = $True
	[void]$TimeComboBox.Items.Add('00:00')
	[void]$TimeComboBox.Items.Add('01:00')
	[void]$TimeComboBox.Items.Add('02:00')
	[void]$TimeComboBox.Items.Add('03:00')
	[void]$TimeComboBox.Items.Add('04:00')
	[void]$TimeComboBox.Items.Add('05:00')
	[void]$TimeComboBox.Items.Add('06:00')
	[void]$TimeComboBox.Items.Add('07:00')
	[void]$TimeComboBox.Items.Add('08:00')
	[void]$TimeComboBox.Items.Add('09:00')
	[void]$TimeComboBox.Items.Add('10:00')
	[void]$TimeComboBox.Items.Add('11:00')
	[void]$TimeComboBox.Items.Add('12:00')
	[void]$TimeComboBox.Items.Add('13:00')
	[void]$TimeComboBox.Items.Add('14:00')
	[void]$TimeComboBox.Items.Add('15:00')
	[void]$TimeComboBox.Items.Add('16:00')
	[void]$TimeComboBox.Items.Add('17:00')
	[void]$TimeComboBox.Items.Add('18:00')
	[void]$TimeComboBox.Items.Add('19:00')
	[void]$TimeComboBox.Items.Add('20:00')
	[void]$TimeComboBox.Items.Add('21:00')
	[void]$TimeComboBox.Items.Add('22:00')
	[void]$TimeComboBox.Items.Add('23:00')
	$TimeComboBox.Location = New-Object System.Drawing.Point(227, 182)
	$TimeComboBox.Name = 'TimeComboBox'
	$TimeComboBox.Size = New-Object System.Drawing.Size(121, 23)
	$TimeComboBox.TabIndex = 103
	$TimeComboBox.Text = '00:00'
	#
	# ScheduleJobButton
	#
	$ScheduleJobButton.BackColor = [System.Drawing.Color]::DimGray 
	$ScheduleJobButton.Cursor = 'Hand'
	$ScheduleJobButton.FlatAppearance.BorderColor = [System.Drawing.Color]::DarkGray 
	$ScheduleJobButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(255, 37, 37, 37)
	$ScheduleJobButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::Gray 
	$ScheduleJobButton.FlatStyle = 'Flat'
	$ScheduleJobButton.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$ScheduleJobButton.ForeColor = [System.Drawing.Color]::White 
	$ScheduleJobButton.Location = New-Object System.Drawing.Point(227, 340)
	$ScheduleJobButton.Name = 'ScheduleJobButton'
	$ScheduleJobButton.Size = New-Object System.Drawing.Size(216, 31)
	$ScheduleJobButton.TabIndex = 111
	$ScheduleJobButton.Text = 'Schedule Job'
	$ScheduleJobButton.UseCompatibleTextRendering = $True
	$ScheduleJobButton.UseVisualStyleBackColor = $False
	$ScheduleJobButton.add_Click($ScheduleJobButton_Click)
	#
	# ScheduleUserName
	#
	$ScheduleUserName.Font = [System.Drawing.Font]::new('Segoe UI', '8.25', [System.Drawing.FontStyle]'Bold')
	$ScheduleUserName.ForeColor = [System.Drawing.Color]::Black 
	$ScheduleUserName.Location = New-Object System.Drawing.Point(111, 264)
	$ScheduleUserName.Name = 'ScheduleUserName'
	$ScheduleUserName.Size = New-Object System.Drawing.Size(108, 16)
	$ScheduleUserName.TabIndex = 110
	$ScheduleUserName.Text = 'Username'
	$ScheduleUserName.TextAlign = 'MiddleRight'
	$ScheduleUserName.UseCompatibleTextRendering = $True
	#
	# SchedulePassword
	#
	$SchedulePassword.Font = [System.Drawing.Font]::new('Segoe UI', '8.25', [System.Drawing.FontStyle]'Bold')
	$SchedulePassword.ForeColor = [System.Drawing.Color]::Black 
	$SchedulePassword.Location = New-Object System.Drawing.Point(111, 305)
	$SchedulePassword.Name = 'SchedulePassword'
	$SchedulePassword.Size = New-Object System.Drawing.Size(106, 16)
	$SchedulePassword.TabIndex = 109
	$SchedulePassword.Text = 'Password'
	$SchedulePassword.TextAlign = 'MiddleRight'
	$SchedulePassword.UseCompatibleTextRendering = $True
	#
	# PasswordTextBox
	#
	$PasswordTextBox.BackColor = [System.Drawing.Color]::White 
	$PasswordTextBox.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$PasswordTextBox.Location = New-Object System.Drawing.Point(227, 298)
	$PasswordTextBox.Margin = '2, 2, 2, 2'
	$PasswordTextBox.Name = 'PasswordTextBox'
	$PasswordTextBox.PasswordChar = '*'
	$PasswordTextBox.Size = New-Object System.Drawing.Size(216, 23)
	$PasswordTextBox.TabIndex = 106
	#
	# ScheduleLocation
	#
	$ScheduleLocation.Font = [System.Drawing.Font]::new('Segoe UI', '8.25', [System.Drawing.FontStyle]'Bold')
	$ScheduleLocation.ForeColor = [System.Drawing.Color]::Black 
	$ScheduleLocation.Location = New-Object System.Drawing.Point(73, 221)
	$ScheduleLocation.Name = 'ScheduleLocation'
	$ScheduleLocation.Size = New-Object System.Drawing.Size(148, 20)
	$ScheduleLocation.TabIndex = 108
	$ScheduleLocation.Text = 'Script Location'
	$ScheduleLocation.TextAlign = 'MiddleRight'
	$ScheduleLocation.UseCompatibleTextRendering = $True
	#
	# ScheduleTime
	#
	$ScheduleTime.Font = [System.Drawing.Font]::new('Segoe UI', '8.25', [System.Drawing.FontStyle]'Bold')
	$ScheduleTime.ForeColor = [System.Drawing.Color]::Black 
	$ScheduleTime.Location = New-Object System.Drawing.Point(159, 187)
	$ScheduleTime.Name = 'ScheduleTime'
	$ScheduleTime.Size = New-Object System.Drawing.Size(58, 16)
	$ScheduleTime.TabIndex = 107
	$ScheduleTime.Text = 'Time'
	$ScheduleTime.TextAlign = 'MiddleRight'
	$ScheduleTime.UseCompatibleTextRendering = $True
	#
	# ScriptLocation
	#
	$ScriptLocation.AutoCompleteMode = 'SuggestAppend'
	$ScriptLocation.AutoCompleteSource = 'FileSystemDirectories'
	$ScriptLocation.BackColor = [System.Drawing.Color]::White 
	$ScriptLocation.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$ScriptLocation.Location = New-Object System.Drawing.Point(227, 220)
	$ScriptLocation.Margin = '2, 2, 2, 2'
	$ScriptLocation.Name = 'ScriptLocation'
	$ScriptLocation.Size = New-Object System.Drawing.Size(216, 23)
	$ScriptLocation.TabIndex = 104
	#
	# ProxyGroupBox
	#
	$ProxyGroupBox.Controls.Add($UseProxyServerCheckbox)
	$ProxyGroupBox.Controls.Add($ProxyServerText)
	$ProxyGroupBox.Controls.Add($labelProxyServer)
	$ProxyGroupBox.Controls.Add($ProxyPswdInput)
	$ProxyGroupBox.Controls.Add($labelPassword)
	$ProxyGroupBox.Controls.Add($ProxyServerInput)
	$ProxyGroupBox.Controls.Add($labelUsername)
	$ProxyGroupBox.Controls.Add($ProxyUserInput)
	$ProxyGroupBox.Anchor = 'Top, Bottom, Left, Right'
	$ProxyGroupBox.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$ProxyGroupBox.Location = New-Object System.Drawing.Point(6, 19)
	$ProxyGroupBox.Name = 'ProxyGroupBox'
	$ProxyGroupBox.Size = New-Object System.Drawing.Size(597, 429)
	$ProxyGroupBox.TabIndex = 105
	$ProxyGroupBox.TabStop = $False
	$ProxyGroupBox.Text = 'Proxy Server Details'
	$ProxyGroupBox.UseCompatibleTextRendering = $True
	#
	# UseProxyServerCheckbox
	#
	$UseProxyServerCheckbox.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$UseProxyServerCheckbox.ForeColor = [System.Drawing.Color]::Black 
	$UseProxyServerCheckbox.Location = New-Object System.Drawing.Point(59, 159)
	$UseProxyServerCheckbox.Margin = '4, 4, 4, 4'
	$UseProxyServerCheckbox.Name = 'UseProxyServerCheckbox'
	$UseProxyServerCheckbox.Size = New-Object System.Drawing.Size(291, 31)
	$UseProxyServerCheckbox.TabIndex = 27
	$UseProxyServerCheckbox.Text = 'Use A Proxy Server'
	$UseProxyServerCheckbox.UseCompatibleTextRendering = $True
	$UseProxyServerCheckbox.UseVisualStyleBackColor = $True
	$UseProxyServerCheckbox.add_CheckedChanged($UseProxyServerCheckbox_CheckedChanged)
	#
	# ProxyServerText
	#
	$ProxyServerText.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$ProxyServerText.BorderStyle = 'None'
	$ProxyServerText.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$ProxyServerText.ForeColor = [System.Drawing.Color]::Black 
	$ProxyServerText.Location = New-Object System.Drawing.Point(10, 47)
	$ProxyServerText.Multiline = $True
	$ProxyServerText.Name = 'ProxyServerText'
	$ProxyServerText.ReadOnly = $True
	$ProxyServerText.Size = New-Object System.Drawing.Size(542, 155)
	$ProxyServerText.TabIndex = 103
	$ProxyServerText.TabStop = $False
	$ProxyServerText.Text = 'Proxy server support is provided here. 

To set your proxy specify the server and port number along with a username and password. Proxy authentication and other settings can also be set inside the script.'
	#
	# labelProxyServer
	#
	$labelProxyServer.AutoSize = $True
	$labelProxyServer.BackColor = [System.Drawing.Color]::Transparent 
	$labelProxyServer.Font = [System.Drawing.Font]::new('Segoe UI', '8.25', [System.Drawing.FontStyle]'Bold')
	$labelProxyServer.ForeColor = [System.Drawing.Color]::Black 
	$labelProxyServer.Location = New-Object System.Drawing.Point(59, 226)
	$labelProxyServer.Margin = '4, 0, 4, 0'
	$labelProxyServer.Name = 'labelProxyServer'
	$labelProxyServer.Size = New-Object System.Drawing.Size(72, 20)
	$labelProxyServer.TabIndex = 22
	$labelProxyServer.Text = 'Proxy Server'
	$labelProxyServer.UseCompatibleTextRendering = $True
	#
	# ProxyPswdInput
	#
	$ProxyPswdInput.BackColor = [System.Drawing.Color]::White 
	$ProxyPswdInput.Enabled = $False
	$ProxyPswdInput.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$ProxyPswdInput.ForeColor = [System.Drawing.Color]::Black 
	$ProxyPswdInput.Location = New-Object System.Drawing.Point(216, 299)
	$ProxyPswdInput.Margin = '4, 3, 4, 3'
	$ProxyPswdInput.Name = 'ProxyPswdInput'
	$ProxyPswdInput.PasswordChar = '*'
	$ProxyPswdInput.Size = New-Object System.Drawing.Size(326, 25)
	$ProxyPswdInput.TabIndex = 25
	$ProxyPswdInput.UseSystemPasswordChar = $True
	#
	# labelPassword
	#
	$labelPassword.AutoSize = $True
	$labelPassword.BackColor = [System.Drawing.Color]::Transparent 
	$labelPassword.Font = [System.Drawing.Font]::new('Segoe UI', '8.25', [System.Drawing.FontStyle]'Bold')
	$labelPassword.ForeColor = [System.Drawing.Color]::Black 
	$labelPassword.Location = New-Object System.Drawing.Point(59, 308)
	$labelPassword.Margin = '4, 0, 4, 0'
	$labelPassword.Name = 'labelPassword'
	$labelPassword.Size = New-Object System.Drawing.Size(55, 20)
	$labelPassword.TabIndex = 26
	$labelPassword.Text = 'Password'
	$labelPassword.UseCompatibleTextRendering = $True
	#
	# ProxyServerInput
	#
	$ProxyServerInput.BackColor = [System.Drawing.Color]::White 
	$ProxyServerInput.Enabled = $False
	$ProxyServerInput.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$ProxyServerInput.ForeColor = [System.Drawing.Color]::Black 
	$ProxyServerInput.Location = New-Object System.Drawing.Point(216, 221)
	$ProxyServerInput.Margin = '4, 3, 4, 3'
	$ProxyServerInput.Name = 'ProxyServerInput'
	$ProxyServerInput.Size = New-Object System.Drawing.Size(326, 25)
	$ProxyServerInput.TabIndex = 21
	$ProxyServerInput.Text = 'http://server:port'
	#
	# labelUsername
	#
	$labelUsername.AutoSize = $True
	$labelUsername.BackColor = [System.Drawing.Color]::Transparent 
	$labelUsername.Font = [System.Drawing.Font]::new('Segoe UI', '8.25', [System.Drawing.FontStyle]'Bold')
	$labelUsername.ForeColor = [System.Drawing.Color]::Black 
	$labelUsername.Location = New-Object System.Drawing.Point(59, 267)
	$labelUsername.Margin = '4, 0, 4, 0'
	$labelUsername.Name = 'labelUsername'
	$labelUsername.Size = New-Object System.Drawing.Size(57, 20)
	$labelUsername.TabIndex = 24
	$labelUsername.Text = 'Username'
	$labelUsername.UseCompatibleTextRendering = $True
	#
	# ProxyUserInput
	#
	$ProxyUserInput.BackColor = [System.Drawing.Color]::White 
	$ProxyUserInput.Enabled = $False
	$ProxyUserInput.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$ProxyUserInput.ForeColor = [System.Drawing.Color]::Black 
	$ProxyUserInput.Location = New-Object System.Drawing.Point(216, 261)
	$ProxyUserInput.Margin = '4, 3, 4, 3'
	$ProxyUserInput.Name = 'ProxyUserInput'
	$ProxyUserInput.Size = New-Object System.Drawing.Size(326, 25)
	$ProxyUserInput.TabIndex = 23
	#
	# tabpage3
	#
	$tabpage3.Controls.Add($AdminControlsInstruction)
	$tabpage3.Controls.Add($groupbox4)
	$tabpage3.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$tabpage3.Location = New-Object System.Drawing.Point(4, 26)
	$tabpage3.Name = 'tabpage3'
	$tabpage3.Size = New-Object System.Drawing.Size(1298, 522)
	$tabpage3.TabIndex = 2
	$tabpage3.Text = 'Admin Controls'
	#
	# AdminControlsInstruction
	#
	$AdminControlsInstruction.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$AdminControlsInstruction.BorderStyle = 'None'
	$AdminControlsInstruction.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$AdminControlsInstruction.ForeColor = [System.Drawing.Color]::Black 
	$AdminControlsInstruction.Location = New-Object System.Drawing.Point(17, 18)
	$AdminControlsInstruction.Multiline = $True
	$AdminControlsInstruction.Name = 'AdminControlsInstruction'
	$AdminControlsInstruction.ReadOnly = $True
	$AdminControlsInstruction.Size = New-Object System.Drawing.Size(1041, 46)
	$AdminControlsInstruction.TabIndex = 65
	$AdminControlsInstruction.TabStop = $False
	$AdminControlsInstruction.Text = 'Here you can opt to hide individual tabs or lock controls via registry settings'
	#
	# groupbox4
	#
	$groupbox4.Controls.Add($TabControlGroup)
	$groupbox4.Anchor = 'Top, Bottom, Left, Right'
	$groupbox4.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$groupbox4.Location = New-Object System.Drawing.Point(11, 59)
	$groupbox4.Name = 'groupbox4'
	$groupbox4.Size = New-Object System.Drawing.Size(1284, 526)
	$groupbox4.TabIndex = 64
	$groupbox4.TabStop = $False
	$groupbox4.Text = 'Lockable Options'
	$groupbox4.UseCompatibleTextRendering = $True
	#
	# TabControlGroup
	#
	$TabControlGroup.Controls.Add($textbox6)
	$TabControlGroup.Controls.Add($HideCommonSettings)
	$TabControlGroup.Controls.Add($HideCustomCreation)
	$TabControlGroup.Controls.Add($HideConfigPkgMgmt)
	$TabControlGroup.Controls.Add($HideWebService)
	$TabControlGroup.Controls.Add($HideMDT)
	$TabControlGroup.Anchor = 'Top, Bottom, Left, Right'
	$TabControlGroup.Location = New-Object System.Drawing.Point(17, 33)
	$TabControlGroup.Name = 'TabControlGroup'
	$TabControlGroup.Size = New-Object System.Drawing.Size(1261, 473)
	$TabControlGroup.TabIndex = 64
	$TabControlGroup.TabStop = $False
	$TabControlGroup.Text = 'Tab Controls'
	$TabControlGroup.UseCompatibleTextRendering = $True
	#
	# textbox6
	#
	$textbox6.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$textbox6.BorderStyle = 'None'
	$textbox6.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9.75', [System.Drawing.FontStyle]'Bold')
	$textbox6.ForeColor = [System.Drawing.Color]::Black 
	$textbox6.Location = New-Object System.Drawing.Point(41, 58)
	$textbox6.Multiline = $True
	$textbox6.Name = 'textbox6'
	$textbox6.ReadOnly = $True
	$textbox6.Size = New-Object System.Drawing.Size(725, 45)
	$textbox6.TabIndex = 104
	$textbox6.TabStop = $False
	$textbox6.Text = 'Note: This will hide all options and can only be turned on in the registry'
	#
	# HideCommonSettings
	#
	$HideCommonSettings.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$HideCommonSettings.ForeColor = [System.Drawing.Color]::DarkRed 
	$HideCommonSettings.Location = New-Object System.Drawing.Point(25, 28)
	$HideCommonSettings.Name = 'HideCommonSettings'
	$HideCommonSettings.Size = New-Object System.Drawing.Size(334, 24)
	$HideCommonSettings.TabIndex = 0
	$HideCommonSettings.Text = 'Hide Common Settings'
	$HideCommonSettings.UseCompatibleTextRendering = $True
	$HideCommonSettings.UseVisualStyleBackColor = $True
	#
	# HideCustomCreation
	#
	$HideCustomCreation.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9')
	$HideCustomCreation.ForeColor = [System.Drawing.Color]::Black 
	$HideCustomCreation.Location = New-Object System.Drawing.Point(25, 169)
	$HideCustomCreation.Name = 'HideCustomCreation'
	$HideCustomCreation.Size = New-Object System.Drawing.Size(334, 24)
	$HideCustomCreation.TabIndex = 3
	$HideCustomCreation.Text = 'Hide Custom Package Creation'
	$HideCustomCreation.UseCompatibleTextRendering = $True
	$HideCustomCreation.UseVisualStyleBackColor = $True
	$HideCustomCreation.add_CheckedChanged($HideCustomCreation_CheckedChanged)
	#
	# HideConfigPkgMgmt
	#
	$HideConfigPkgMgmt.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9')
	$HideConfigPkgMgmt.ForeColor = [System.Drawing.Color]::Black 
	$HideConfigPkgMgmt.Location = New-Object System.Drawing.Point(25, 109)
	$HideConfigPkgMgmt.Name = 'HideConfigPkgMgmt'
	$HideConfigPkgMgmt.Size = New-Object System.Drawing.Size(334, 24)
	$HideConfigPkgMgmt.TabIndex = 1
	$HideConfigPkgMgmt.Text = 'Hide ConfigMgr Package Mgmt'
	$HideConfigPkgMgmt.UseCompatibleTextRendering = $True
	$HideConfigPkgMgmt.UseVisualStyleBackColor = $True
	$HideConfigPkgMgmt.add_CheckedChanged($HideConfigPkgMgmt_CheckedChanged)
	#
	# HideWebService
	#
	$HideWebService.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9')
	$HideWebService.ForeColor = [System.Drawing.Color]::Black 
	$HideWebService.Location = New-Object System.Drawing.Point(25, 139)
	$HideWebService.Name = 'HideWebService'
	$HideWebService.Size = New-Object System.Drawing.Size(334, 24)
	$HideWebService.TabIndex = 2
	$HideWebService.Text = 'Hide ConfigMgr Web Service Diags'
	$HideWebService.UseCompatibleTextRendering = $True
	$HideWebService.UseVisualStyleBackColor = $True
	$HideWebService.add_CheckedChanged($HideWebService_CheckedChanged)
	#
	# HideMDT
	#
	$HideMDT.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9')
	$HideMDT.ForeColor = [System.Drawing.Color]::Black 
	$HideMDT.Location = New-Object System.Drawing.Point(25, 199)
	$HideMDT.Name = 'HideMDT'
	$HideMDT.Size = New-Object System.Drawing.Size(334, 24)
	$HideMDT.TabIndex = 4
	$HideMDT.Text = 'Hide MDT Settings'
	$HideMDT.UseCompatibleTextRendering = $True
	$HideMDT.UseVisualStyleBackColor = $True
	$HideMDT.add_CheckedChanged($HideMDT_CheckedChanged)
	#
	# picturebox2
	#
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
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
rkJgggs='))
	#endregion
	$picturebox2.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$picturebox2.Location = New-Object System.Drawing.Point(20, 16)
	$picturebox2.Name = 'picturebox2'
	$picturebox2.Size = New-Object System.Drawing.Size(50, 50)
	$picturebox2.SizeMode = 'StretchImage'
	$picturebox2.TabIndex = 104
	$picturebox2.TabStop = $False
	#
	# labelCommonSettings
	#
	$labelCommonSettings.AutoSize = $True
	$labelCommonSettings.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '16', [System.Drawing.FontStyle]'Bold')
	$labelCommonSettings.ForeColor = [System.Drawing.Color]::White 
	$labelCommonSettings.Location = New-Object System.Drawing.Point(90, 24)
	$labelCommonSettings.Name = 'labelCommonSettings'
	$labelCommonSettings.Size = New-Object System.Drawing.Size(186, 35)
	$labelCommonSettings.TabIndex = 103
	$labelCommonSettings.Text = 'Common Settings'
	$labelCommonSettings.UseCompatibleTextRendering = $True
	#
	# ConfigMgrTab
	#
	$ConfigMgrTab.Controls.Add($SettingsIcon)
	$ConfigMgrTab.Controls.Add($labelConfigurationManager)
	$ConfigMgrTab.Controls.Add($SettingsTabs)
	$ConfigMgrTab.Controls.Add($SettingsPanel)
	$ConfigMgrTab.BackColor = [System.Drawing.Color]::Gray 
	$ConfigMgrTab.Location = New-Object System.Drawing.Point(4, 48)
	$ConfigMgrTab.Name = 'ConfigMgrTab'
	$ConfigMgrTab.Size = New-Object System.Drawing.Size(1231, 564)
	$ConfigMgrTab.TabIndex = 7
	$ConfigMgrTab.Text = 'ConfigMgr Settings'
	#
	# SettingsIcon
	#
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
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
rkJgggs='))
	#endregion
	$SettingsIcon.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$SettingsIcon.Location = New-Object System.Drawing.Point(20, 16)
	$SettingsIcon.Name = 'SettingsIcon'
	$SettingsIcon.Size = New-Object System.Drawing.Size(50, 50)
	$SettingsIcon.SizeMode = 'StretchImage'
	$SettingsIcon.TabIndex = 102
	$SettingsIcon.TabStop = $False
	#
	# labelConfigurationManager
	#
	$labelConfigurationManager.AutoSize = $True
	$labelConfigurationManager.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '16', [System.Drawing.FontStyle]'Bold')
	$labelConfigurationManager.ForeColor = [System.Drawing.Color]::White 
	$labelConfigurationManager.Location = New-Object System.Drawing.Point(90, 24)
	$labelConfigurationManager.Name = 'labelConfigurationManager'
	$labelConfigurationManager.Size = New-Object System.Drawing.Size(328, 35)
	$labelConfigurationManager.TabIndex = 101
	$labelConfigurationManager.Text = 'Configuration Manager Settings'
	$labelConfigurationManager.UseCompatibleTextRendering = $True
	#
	# SettingsTabs
	#
	$SettingsTabs.Controls.Add($ConfigMgrDPOptionsTab)
	$SettingsTabs.Controls.Add($PackageOptionsTab)
	$SettingsTabs.Anchor = 'Top, Bottom, Left, Right'
	$SettingsTabs.Location = New-Object System.Drawing.Point(4, 83)
	$SettingsTabs.Margin = '4, 4, 4, 4'
	$SettingsTabs.Name = 'SettingsTabs'
	$SettingsTabs.SelectedIndex = 0
	$SettingsTabs.Size = New-Object System.Drawing.Size(1225, 484)
	$SettingsTabs.SizeMode = 'FillToRight'
	$SettingsTabs.TabIndex = 84
	#
	# ConfigMgrDPOptionsTab
	#
	$ConfigMgrDPOptionsTab.Controls.Add($PackageCreation)
	$ConfigMgrDPOptionsTab.Controls.Add($groupbox1)
	$ConfigMgrDPOptionsTab.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$ConfigMgrDPOptionsTab.Location = New-Object System.Drawing.Point(4, 26)
	$ConfigMgrDPOptionsTab.Name = 'ConfigMgrDPOptionsTab'
	$ConfigMgrDPOptionsTab.Size = New-Object System.Drawing.Size(1217, 454)
	$ConfigMgrDPOptionsTab.TabIndex = 5
	$ConfigMgrDPOptionsTab.Text = 'Site Server Settings | Package Options'
	#
	# PackageCreation
	#
	$PackageCreation.Controls.Add($textbox9)
	$PackageCreation.Controls.Add($CreateXMLLogicPackage)
	$PackageCreation.Controls.Add($ZipFormatLabel)
	$PackageCreation.Controls.Add($CompressionType)
	$PackageCreation.Controls.Add($ZipCompressionText)
	$PackageCreation.Controls.Add($ZipCompressionCheckBox)
	$PackageCreation.Controls.Add($CleanSourceText)
	$PackageCreation.Controls.Add($RemoveDriverSourceCheckbox)
	$PackageCreation.Controls.Add($RemoveBIOSText)
	$PackageCreation.Controls.Add($RemoveLegacyBIOSCheckbox)
	$PackageCreation.Controls.Add($CleanUpText)
	$PackageCreation.Controls.Add($CleanUnusedCheckBox)
	$PackageCreation.Controls.Add($RemoveSuperText)
	$PackageCreation.Controls.Add($RemoveLegacyDriverCheckbox)
	$PackageCreation.Controls.Add($PackageBrowseButton)
	$PackageCreation.Controls.Add($PackagePathLabel)
	$PackageCreation.Controls.Add($PackagePathTextBox)
	$PackageCreation.Controls.Add($CustPackageDest)
	$PackageCreation.Controls.Add($SpecifyCustomPath)
	$PackageCreation.Controls.Add($textbox4)
	$PackageCreation.Controls.Add($PackageRoot)
	$PackageCreation.Anchor = 'Top, Bottom, Left, Right'
	$PackageCreation.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$PackageCreation.ForeColor = [System.Drawing.Color]::Black 
	$PackageCreation.Location = New-Object System.Drawing.Point(563, 3)
	$PackageCreation.Name = 'PackageCreation'
	$PackageCreation.Size = New-Object System.Drawing.Size(637, 475)
	$PackageCreation.TabIndex = 110
	$PackageCreation.TabStop = $False
	$PackageCreation.Text = 'Package Settings | Clean Up Options'
	$PackageCreation.UseCompatibleTextRendering = $True
	#
	# textbox9
	#
	$textbox9.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$textbox9.BorderStyle = 'None'
	$textbox9.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$textbox9.ForeColor = [System.Drawing.Color]::Black 
	$textbox9.Location = New-Object System.Drawing.Point(41, 409)
	$textbox9.Multiline = $True
	$textbox9.Name = 'textbox9'
	$textbox9.ReadOnly = $True
	$textbox9.Size = New-Object System.Drawing.Size(574, 36)
	$textbox9.TabIndex = 124
	$textbox9.TabStop = $False
	$textbox9.Text = 'Creates a packge containing BIOS and driver XML package information, for deployments not using the ConfigMgr Web Service or Admin Service API'
	#
	# CreateXMLLogicPackage
	#
	$CreateXMLLogicPackage.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$CreateXMLLogicPackage.ForeColor = [System.Drawing.Color]::Maroon 
	$CreateXMLLogicPackage.Location = New-Object System.Drawing.Point(45, 383)
	$CreateXMLLogicPackage.Name = 'CreateXMLLogicPackage'
	$CreateXMLLogicPackage.Size = New-Object System.Drawing.Size(264, 24)
	$CreateXMLLogicPackage.TabIndex = 123
	$CreateXMLLogicPackage.Text = 'Create XML Logic Package'
	$CreateXMLLogicPackage.UseCompatibleTextRendering = $True
	$CreateXMLLogicPackage.UseVisualStyleBackColor = $True
	#
	# ZipFormatLabel
	#
	$ZipFormatLabel.AutoSize = $True
	$ZipFormatLabel.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$ZipFormatLabel.ForeColor = [System.Drawing.Color]::Black 
	$ZipFormatLabel.Location = New-Object System.Drawing.Point(355, 324)
	$ZipFormatLabel.Margin = '4, 0, 4, 0'
	$ZipFormatLabel.Name = 'ZipFormatLabel'
	$ZipFormatLabel.Size = New-Object System.Drawing.Size(163, 23)
	$ZipFormatLabel.TabIndex = 122
	$ZipFormatLabel.Text = 'Zip Compression Format'
	$ZipFormatLabel.UseCompatibleTextRendering = $True
	#
	# CompressionType
	#
	$CompressionType.Enabled = $False
	$CompressionType.FormattingEnabled = $True
	[void]$CompressionType.Items.Add('Zip')
	[void]$CompressionType.Items.Add('7-Zip')
	$CompressionType.Location = New-Object System.Drawing.Point(355, 348)
	$CompressionType.Name = 'CompressionType'
	$CompressionType.Size = New-Object System.Drawing.Size(226, 25)
	$CompressionType.TabIndex = 121
	#
	# ZipCompressionText
	#
	$ZipCompressionText.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$ZipCompressionText.BorderStyle = 'None'
	$ZipCompressionText.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$ZipCompressionText.ForeColor = [System.Drawing.Color]::Black 
	$ZipCompressionText.Location = New-Object System.Drawing.Point(41, 348)
	$ZipCompressionText.Multiline = $True
	$ZipCompressionText.Name = 'ZipCompressionText'
	$ZipCompressionText.ReadOnly = $True
	$ZipCompressionText.Size = New-Object System.Drawing.Size(305, 29)
	$ZipCompressionText.TabIndex = 120
	$ZipCompressionText.TabStop = $False
	$ZipCompressionText.Text = 'Reduces driver pack sizes by zipping contents'
	#
	# ZipCompressionCheckBox
	#
	$ZipCompressionCheckBox.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$ZipCompressionCheckBox.ForeColor = [System.Drawing.Color]::Maroon 
	$ZipCompressionCheckBox.Location = New-Object System.Drawing.Point(45, 324)
	$ZipCompressionCheckBox.Name = 'ZipCompressionCheckBox'
	$ZipCompressionCheckBox.Size = New-Object System.Drawing.Size(264, 24)
	$ZipCompressionCheckBox.TabIndex = 119
	$ZipCompressionCheckBox.Text = 'Use ZIP Compression'
	$ZipCompressionCheckBox.UseCompatibleTextRendering = $True
	$ZipCompressionCheckBox.UseVisualStyleBackColor = $True
	$ZipCompressionCheckBox.add_CheckedChanged($ZipCompressionCheckBox_CheckedChanged)
	$ZipCompressionCheckBox.add_EnabledChanged($ZipCompressionCheckBox_EnabledChanged)
	#
	# CleanSourceText
	#
	$CleanSourceText.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$CleanSourceText.BorderStyle = 'None'
	$CleanSourceText.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$CleanSourceText.ForeColor = [System.Drawing.Color]::Black 
	$CleanSourceText.Location = New-Object System.Drawing.Point(352, 286)
	$CleanSourceText.Multiline = $True
	$CleanSourceText.Name = 'CleanSourceText'
	$CleanSourceText.ReadOnly = $True
	$CleanSourceText.Size = New-Object System.Drawing.Size(342, 28)
	$CleanSourceText.TabIndex = 118
	$CleanSourceText.TabStop = $False
	$CleanSourceText.Text = 'Clean up source files post package creation'
	#
	# RemoveDriverSourceCheckbox
	#
	$RemoveDriverSourceCheckbox.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$RemoveDriverSourceCheckbox.ForeColor = [System.Drawing.Color]::Black 
	$RemoveDriverSourceCheckbox.Location = New-Object System.Drawing.Point(355, 263)
	$RemoveDriverSourceCheckbox.Name = 'RemoveDriverSourceCheckbox'
	$RemoveDriverSourceCheckbox.Size = New-Object System.Drawing.Size(260, 24)
	$RemoveDriverSourceCheckbox.TabIndex = 117
	$RemoveDriverSourceCheckbox.Text = 'Remove Driver Source Packages'
	$RemoveDriverSourceCheckbox.UseCompatibleTextRendering = $True
	$RemoveDriverSourceCheckbox.UseVisualStyleBackColor = $True
	#
	# RemoveBIOSText
	#
	$RemoveBIOSText.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$RemoveBIOSText.BorderStyle = 'None'
	$RemoveBIOSText.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$RemoveBIOSText.ForeColor = [System.Drawing.Color]::Black 
	$RemoveBIOSText.Location = New-Object System.Drawing.Point(41, 285)
	$RemoveBIOSText.Multiline = $True
	$RemoveBIOSText.Name = 'RemoveBIOSText'
	$RemoveBIOSText.ReadOnly = $True
	$RemoveBIOSText.Size = New-Object System.Drawing.Size(245, 29)
	$RemoveBIOSText.TabIndex = 116
	$RemoveBIOSText.TabStop = $False
	$RemoveBIOSText.Text = 'Maintain only the latest BIOS package'
	#
	# RemoveLegacyBIOSCheckbox
	#
	$RemoveLegacyBIOSCheckbox.Enabled = $False
	$RemoveLegacyBIOSCheckbox.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$RemoveLegacyBIOSCheckbox.ForeColor = [System.Drawing.Color]::Black 
	$RemoveLegacyBIOSCheckbox.Location = New-Object System.Drawing.Point(45, 263)
	$RemoveLegacyBIOSCheckbox.Name = 'RemoveLegacyBIOSCheckbox'
	$RemoveLegacyBIOSCheckbox.Size = New-Object System.Drawing.Size(264, 24)
	$RemoveLegacyBIOSCheckbox.TabIndex = 115
	$RemoveLegacyBIOSCheckbox.Text = 'Remove Superseded BIOS Packages'
	$RemoveLegacyBIOSCheckbox.UseCompatibleTextRendering = $True
	$RemoveLegacyBIOSCheckbox.UseVisualStyleBackColor = $True
	#
	# CleanUpText
	#
	$CleanUpText.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$CleanUpText.BorderStyle = 'None'
	$CleanUpText.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$CleanUpText.ForeColor = [System.Drawing.Color]::Black 
	$CleanUpText.Location = New-Object System.Drawing.Point(352, 219)
	$CleanUpText.Multiline = $True
	$CleanUpText.Name = 'CleanUpText'
	$CleanUpText.ReadOnly = $True
	$CleanUpText.Size = New-Object System.Drawing.Size(272, 21)
	$CleanUpText.TabIndex = 113
	$CleanUpText.TabStop = $False
	$CleanUpText.Text = 'Remove drivers not referenced by driver packages'
	#
	# CleanUnusedCheckBox
	#
	$CleanUnusedCheckBox.Enabled = $False
	$CleanUnusedCheckBox.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$CleanUnusedCheckBox.ForeColor = [System.Drawing.Color]::Black 
	$CleanUnusedCheckBox.Location = New-Object System.Drawing.Point(355, 199)
	$CleanUnusedCheckBox.Name = 'CleanUnusedCheckBox'
	$CleanUnusedCheckBox.Size = New-Object System.Drawing.Size(226, 24)
	$CleanUnusedCheckBox.TabIndex = 111
	$CleanUnusedCheckBox.Text = 'Clean Up Unused Drivers'
	$CleanUnusedCheckBox.UseCompatibleTextRendering = $True
	$CleanUnusedCheckBox.UseVisualStyleBackColor = $True
	#
	# RemoveSuperText
	#
	$RemoveSuperText.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$RemoveSuperText.BorderStyle = 'None'
	$RemoveSuperText.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$RemoveSuperText.ForeColor = [System.Drawing.Color]::Black 
	$RemoveSuperText.Location = New-Object System.Drawing.Point(41, 220)
	$RemoveSuperText.Multiline = $True
	$RemoveSuperText.Name = 'RemoveSuperText'
	$RemoveSuperText.ReadOnly = $True
	$RemoveSuperText.Size = New-Object System.Drawing.Size(245, 29)
	$RemoveSuperText.TabIndex = 114
	$RemoveSuperText.TabStop = $False
	$RemoveSuperText.Text = 'Maintain only the latest driver package'
	#
	# RemoveLegacyDriverCheckbox
	#
	$RemoveLegacyDriverCheckbox.Enabled = $False
	$RemoveLegacyDriverCheckbox.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$RemoveLegacyDriverCheckbox.ForeColor = [System.Drawing.Color]::Black 
	$RemoveLegacyDriverCheckbox.Location = New-Object System.Drawing.Point(45, 199)
	$RemoveLegacyDriverCheckbox.Name = 'RemoveLegacyDriverCheckbox'
	$RemoveLegacyDriverCheckbox.Size = New-Object System.Drawing.Size(264, 24)
	$RemoveLegacyDriverCheckbox.TabIndex = 112
	$RemoveLegacyDriverCheckbox.Text = 'Remove Superseded Driver Packages'
	$RemoveLegacyDriverCheckbox.UseCompatibleTextRendering = $True
	$RemoveLegacyDriverCheckbox.UseVisualStyleBackColor = $True
	#
	# PackageBrowseButton
	#
	$PackageBrowseButton.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$PackageBrowseButton.FlatStyle = 'Popup'
	$PackageBrowseButton.ForeColor = [System.Drawing.Color]::White 
	$PackageBrowseButton.Location = New-Object System.Drawing.Point(441, 65)
	$PackageBrowseButton.Margin = '4, 4, 4, 4'
	$PackageBrowseButton.Name = 'PackageBrowseButton'
	$PackageBrowseButton.Size = New-Object System.Drawing.Size(116, 27)
	$PackageBrowseButton.TabIndex = 109
	$PackageBrowseButton.Text = 'Browse'
	$PackageBrowseButton.UseCompatibleTextRendering = $True
	$PackageBrowseButton.UseVisualStyleBackColor = $False
	$PackageBrowseButton.add_Click($PackageBrowseButton_Click)
	#
	# PackagePathLabel
	#
	$PackagePathLabel.AutoSize = $True
	$PackagePathLabel.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$PackagePathLabel.ForeColor = [System.Drawing.Color]::Black 
	$PackagePathLabel.Location = New-Object System.Drawing.Point(39, 35)
	$PackagePathLabel.Margin = '4, 0, 4, 0'
	$PackagePathLabel.Name = 'PackagePathLabel'
	$PackagePathLabel.Size = New-Object System.Drawing.Size(149, 23)
	$PackagePathLabel.TabIndex = 110
	$PackagePathLabel.Text = 'Package Storage Path '
	$PackagePathLabel.UseCompatibleTextRendering = $True
	#
	# PackagePathTextBox
	#
	$PackagePathTextBox.AutoCompleteMode = 'SuggestAppend'
	$PackagePathTextBox.AutoCompleteSource = 'FileSystemDirectories'
	$PackagePathTextBox.BackColor = [System.Drawing.Color]::White 
	$PackagePathTextBox.Font = [System.Drawing.Font]::new('Segoe UI', '11.25')
	$PackagePathTextBox.Location = New-Object System.Drawing.Point(40, 65)
	$PackagePathTextBox.Margin = '4, 4, 4, 4'
	$PackagePathTextBox.Name = 'PackagePathTextBox'
	$PackagePathTextBox.Size = New-Object System.Drawing.Size(393, 27)
	$PackagePathTextBox.TabIndex = 108
	$PackagePathTextBox.Text = '\\server\sharename'
	#
	# CustPackageDest
	#
	$CustPackageDest.AutoCompleteMode = 'SuggestAppend'
	$CustPackageDest.AutoCompleteSource = 'FileSystemDirectories'
	$CustPackageDest.BackColor = [System.Drawing.Color]::White 
	$CustPackageDest.Enabled = $False
	$CustPackageDest.Font = [System.Drawing.Font]::new('Segoe UI', '11.25')
	$CustPackageDest.Location = New-Object System.Drawing.Point(355, 147)
	$CustPackageDest.Margin = '4, 4, 4, 4'
	$CustPackageDest.Name = 'CustPackageDest'
	$CustPackageDest.Size = New-Object System.Drawing.Size(214, 27)
	$CustPackageDest.TabIndex = 84
	$CustPackageDest.Text = 'PackageType\Make\Model'
	#
	# SpecifyCustomPath
	#
	$SpecifyCustomPath.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$SpecifyCustomPath.ForeColor = [System.Drawing.Color]::Black 
	$SpecifyCustomPath.Location = New-Object System.Drawing.Point(355, 116)
	$SpecifyCustomPath.Name = 'SpecifyCustomPath'
	$SpecifyCustomPath.Size = New-Object System.Drawing.Size(242, 24)
	$SpecifyCustomPath.TabIndex = 107
	$SpecifyCustomPath.Text = 'Specify Custom Path'
	$SpecifyCustomPath.UseCompatibleTextRendering = $True
	$SpecifyCustomPath.UseVisualStyleBackColor = $True
	$SpecifyCustomPath.add_CheckedChanged($SpecifyCustomPath_CheckedChanged)
	#
	# textbox4
	#
	$textbox4.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$textbox4.BorderStyle = 'None'
	$textbox4.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$textbox4.ForeColor = [System.Drawing.Color]::Black 
	$textbox4.Location = New-Object System.Drawing.Point(41, 139)
	$textbox4.Multiline = $True
	$textbox4.Name = 'textbox4'
	$textbox4.ReadOnly = $True
	$textbox4.Size = New-Object System.Drawing.Size(269, 49)
	$textbox4.TabIndex = 106
	$textbox4.TabStop = $False
	$textbox4.Text = 'Places all BIOS and Driver packages in the root of the packages folder '
	#
	# PackageRoot
	#
	$PackageRoot.Font = [System.Drawing.Font]::new('Segoe UI', '10', [System.Drawing.FontStyle]'Bold')
	$PackageRoot.ForeColor = [System.Drawing.Color]::Black 
	$PackageRoot.Location = New-Object System.Drawing.Point(45, 116)
	$PackageRoot.Name = 'PackageRoot'
	$PackageRoot.Size = New-Object System.Drawing.Size(219, 24)
	$PackageRoot.TabIndex = 76
	$PackageRoot.Text = 'Use Root Package Folder'
	$PackageRoot.UseCompatibleTextRendering = $True
	$PackageRoot.UseVisualStyleBackColor = $True
	#
	# groupbox1
	#
	$groupbox1.Controls.Add($ConfigMgrImport)
	$groupbox1.Controls.Add($labelSelectKnownModels)
	$groupbox1.Controls.Add($ConifgSiteInstruction)
	$groupbox1.Controls.Add($ConnectConfigMgrButton)
	$groupbox1.Controls.Add($SiteCodeText)
	$groupbox1.Controls.Add($SiteServerInput)
	$groupbox1.Controls.Add($SiteServerLabel)
	$groupbox1.Controls.Add($SiteCodeLabel)
	$groupbox1.Anchor = 'Top, Bottom, Left'
	$groupbox1.Font = [System.Drawing.Font]::new('Microsoft Sans Serif', '9.75', [System.Drawing.FontStyle]'Bold')
	$groupbox1.Location = New-Object System.Drawing.Point(12, 3)
	$groupbox1.Name = 'groupbox1'
	$groupbox1.Size = New-Object System.Drawing.Size(542, 475)
	$groupbox1.TabIndex = 92
	$groupbox1.TabStop = $False
	$groupbox1.Text = 'ConfigMgr Site Server Details'
	$groupbox1.UseCompatibleTextRendering = $True
	#
	# ConfigMgrImport
	#
	$ConfigMgrImport.BackColor = [System.Drawing.Color]::White 
	$ConfigMgrImport.DropDownStyle = 'DropDownList'
	$ConfigMgrImport.Font = [System.Drawing.Font]::new('Microsoft Sans Serif', '9.75')
	$ConfigMgrImport.ForeColor = [System.Drawing.Color]::Black 
	$ConfigMgrImport.FormattingEnabled = $True
	[void]$ConfigMgrImport.Items.Add('Yes')
	[void]$ConfigMgrImport.Items.Add('No')
	$ConfigMgrImport.Location = New-Object System.Drawing.Point(201, 278)
	$ConfigMgrImport.Name = 'ConfigMgrImport'
	$ConfigMgrImport.Size = New-Object System.Drawing.Size(230, 24)
	$ConfigMgrImport.TabIndex = 105
	#
	# labelSelectKnownModels
	#
	$labelSelectKnownModels.AutoSize = $True
	$labelSelectKnownModels.Font = [System.Drawing.Font]::new('Microsoft Sans Serif', '9.75', [System.Drawing.FontStyle]'Bold')
	$labelSelectKnownModels.ForeColor = [System.Drawing.Color]::Black 
	$labelSelectKnownModels.Location = New-Object System.Drawing.Point(30, 281)
	$labelSelectKnownModels.Name = 'labelSelectKnownModels'
	$labelSelectKnownModels.Size = New-Object System.Drawing.Size(138, 20)
	$labelSelectKnownModels.TabIndex = 104
	$labelSelectKnownModels.Text = 'Select Known Models'
	$labelSelectKnownModels.UseCompatibleTextRendering = $True
	#
	# ConifgSiteInstruction
	#
	$ConifgSiteInstruction.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$ConifgSiteInstruction.BorderStyle = 'None'
	$ConifgSiteInstruction.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$ConifgSiteInstruction.ForeColor = [System.Drawing.Color]::Black 
	$ConifgSiteInstruction.Location = New-Object System.Drawing.Point(9, 44)
	$ConifgSiteInstruction.Multiline = $True
	$ConifgSiteInstruction.Name = 'ConifgSiteInstruction'
	$ConifgSiteInstruction.ReadOnly = $True
	$ConifgSiteInstruction.Size = New-Object System.Drawing.Size(499, 102)
	$ConifgSiteInstruction.TabIndex = 103
	$ConifgSiteInstruction.TabStop = $False
	$ConifgSiteInstruction.Text = 'Please specify the CAS or primary site server and click on the Connect To ConfigMgr button to establish connectivity to your ConfigMgr environment.

Note: Please ensure that you have the Configuration Manager Console installed and have sufficient rights to the environment
'
	#
	# ConnectConfigMgrButton
	#
	$ConnectConfigMgrButton.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$ConnectConfigMgrButton.FlatStyle = 'Flat'
	$ConnectConfigMgrButton.Font = [System.Drawing.Font]::new('Microsoft Sans Serif', '9.75', [System.Drawing.FontStyle]'Bold')
	$ConnectConfigMgrButton.ForeColor = [System.Drawing.Color]::White 
	$ConnectConfigMgrButton.Location = New-Object System.Drawing.Point(201, 317)
	$ConnectConfigMgrButton.Margin = '4, 3, 4, 3'
	$ConnectConfigMgrButton.Name = 'ConnectConfigMgrButton'
	$ConnectConfigMgrButton.Size = New-Object System.Drawing.Size(230, 41)
	$ConnectConfigMgrButton.TabIndex = 92
	$ConnectConfigMgrButton.Text = 'Connect to ConfigMgr'
	$ConnectConfigMgrButton.UseCompatibleTextRendering = $True
	$ConnectConfigMgrButton.UseVisualStyleBackColor = $False
	$ConnectConfigMgrButton.add_Click($ConnectConfigMgrButton_Click)
	#
	# SiteCodeText
	#
	$SiteCodeText.BackColor = [System.Drawing.Color]::White 
	$SiteCodeText.CharacterCasing = 'Upper'
	$SiteCodeText.Enabled = $False
	$SiteCodeText.Font = [System.Drawing.Font]::new('Microsoft Sans Serif', '9.75')
	$SiteCodeText.ForeColor = [System.Drawing.Color]::Black 
	$SiteCodeText.Location = New-Object System.Drawing.Point(201, 220)
	$SiteCodeText.Margin = '4, 3, 4, 3'
	$SiteCodeText.Name = 'SiteCodeText'
	$SiteCodeText.Size = New-Object System.Drawing.Size(230, 22)
	$SiteCodeText.TabIndex = 91
	$SiteCodeText.Text = 'N/A'
	#
	# SiteServerInput
	#
	$SiteServerInput.BackColor = [System.Drawing.Color]::White 
	$SiteServerInput.Font = [System.Drawing.Font]::new('Microsoft Sans Serif', '9.75')
	$SiteServerInput.ForeColor = [System.Drawing.Color]::Black 
	$SiteServerInput.Location = New-Object System.Drawing.Point(201, 167)
	$SiteServerInput.Margin = '4, 3, 4, 3'
	$SiteServerInput.Name = 'SiteServerInput'
	$SiteServerInput.Size = New-Object System.Drawing.Size(230, 22)
	$SiteServerInput.TabIndex = 90
	#
	# SiteServerLabel
	#
	$SiteServerLabel.AutoSize = $True
	$SiteServerLabel.BackColor = [System.Drawing.Color]::Transparent 
	$SiteServerLabel.Font = [System.Drawing.Font]::new('Microsoft Sans Serif', '9.75', [System.Drawing.FontStyle]'Bold')
	$SiteServerLabel.ForeColor = [System.Drawing.Color]::Black 
	$SiteServerLabel.Location = New-Object System.Drawing.Point(88, 174)
	$SiteServerLabel.Margin = '4, 0, 4, 0'
	$SiteServerLabel.Name = 'SiteServerLabel'
	$SiteServerLabel.Size = New-Object System.Drawing.Size(74, 20)
	$SiteServerLabel.TabIndex = 93
	$SiteServerLabel.Text = 'Site Server'
	$SiteServerLabel.UseCompatibleTextRendering = $True
	#
	# SiteCodeLabel
	#
	$SiteCodeLabel.AutoSize = $True
	$SiteCodeLabel.BackColor = [System.Drawing.Color]::Transparent 
	$SiteCodeLabel.Font = [System.Drawing.Font]::new('Microsoft Sans Serif', '9.75', [System.Drawing.FontStyle]'Bold')
	$SiteCodeLabel.ForeColor = [System.Drawing.Color]::Black 
	$SiteCodeLabel.Location = New-Object System.Drawing.Point(96, 227)
	$SiteCodeLabel.Margin = '4, 0, 4, 0'
	$SiteCodeLabel.Name = 'SiteCodeLabel'
	$SiteCodeLabel.Size = New-Object System.Drawing.Size(66, 20)
	$SiteCodeLabel.TabIndex = 94
	$SiteCodeLabel.Text = 'Site Code'
	$SiteCodeLabel.UseCompatibleTextRendering = $True
	#
	# PackageOptionsTab
	#
	$PackageOptionsTab.Controls.Add($DPGroupBox)
	$PackageOptionsTab.Controls.Add($FallbackPkgGroup)
	$PackageOptionsTab.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$PackageOptionsTab.Location = New-Object System.Drawing.Point(4, 26)
	$PackageOptionsTab.Name = 'PackageOptionsTab'
	$PackageOptionsTab.Padding = '3, 3, 3, 3'
	$PackageOptionsTab.Size = New-Object System.Drawing.Size(1217, 454)
	$PackageOptionsTab.TabIndex = 3
	$PackageOptionsTab.Text = 'Package Distribution | Fallback Package Options'
	#
	# DPGroupBox
	#
	$DPGroupBox.Controls.Add($EnableBinaryDifCheckBox)
	$DPGroupBox.Controls.Add($PriorityLabel)
	$DPGroupBox.Controls.Add($DistributionPriorityCombo)
	$DPGroupBox.Controls.Add($DPSelectionsTabs)
	$DPGroupBox.Anchor = 'Top, Bottom, Left, Right'
	$DPGroupBox.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$DPGroupBox.Location = New-Object System.Drawing.Point(12, 24)
	$DPGroupBox.Name = 'DPGroupBox'
	$DPGroupBox.Size = New-Object System.Drawing.Size(1199, 262)
	$DPGroupBox.TabIndex = 111
	$DPGroupBox.TabStop = $False
	$DPGroupBox.Text = 'ConfigMgr Distribution Point / Groups Selection'
	$DPGroupBox.UseCompatibleTextRendering = $True
	#
	# EnableBinaryDifCheckBox
	#
	$EnableBinaryDifCheckBox.Anchor = 'Bottom, Left'
	$EnableBinaryDifCheckBox.Checked = $True
	$EnableBinaryDifCheckBox.CheckState = 'Checked'
	$EnableBinaryDifCheckBox.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$EnableBinaryDifCheckBox.ForeColor = [System.Drawing.Color]::Black 
	$EnableBinaryDifCheckBox.Location = New-Object System.Drawing.Point(892, 128)
	$EnableBinaryDifCheckBox.Name = 'EnableBinaryDifCheckBox'
	$EnableBinaryDifCheckBox.Size = New-Object System.Drawing.Size(295, 25)
	$EnableBinaryDifCheckBox.TabIndex = 86
	$EnableBinaryDifCheckBox.Text = 'Enable Binary Differential Replication'
	$EnableBinaryDifCheckBox.UseCompatibleTextRendering = $True
	$EnableBinaryDifCheckBox.UseVisualStyleBackColor = $True
	#
	# PriorityLabel
	#
	$PriorityLabel.Anchor = 'Bottom, Left'
	$PriorityLabel.AutoSize = $True
	$PriorityLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$PriorityLabel.ForeColor = [System.Drawing.Color]::Black 
	$PriorityLabel.Location = New-Object System.Drawing.Point(892, 65)
	$PriorityLabel.Name = 'PriorityLabel'
	$PriorityLabel.Size = New-Object System.Drawing.Size(48, 21)
	$PriorityLabel.TabIndex = 85
	$PriorityLabel.Text = 'Priority'
	$PriorityLabel.UseCompatibleTextRendering = $True
	#
	# DistributionPriorityCombo
	#
	$DistributionPriorityCombo.Anchor = 'Bottom, Left'
	$DistributionPriorityCombo.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$DistributionPriorityCombo.DropDownStyle = 'DropDownList'
	$DistributionPriorityCombo.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$DistributionPriorityCombo.FormattingEnabled = $True
	[void]$DistributionPriorityCombo.Items.Add('Low')
	[void]$DistributionPriorityCombo.Items.Add('Normal')
	[void]$DistributionPriorityCombo.Items.Add('High')
	$DistributionPriorityCombo.Location = New-Object System.Drawing.Point(892, 89)
	$DistributionPriorityCombo.Name = 'DistributionPriorityCombo'
	$DistributionPriorityCombo.Size = New-Object System.Drawing.Size(247, 23)
	$DistributionPriorityCombo.TabIndex = 84
	#
	# DPSelectionsTabs
	#
	$DPSelectionsTabs.Controls.Add($DPointTab)
	$DPSelectionsTabs.Controls.Add($DPGroupTab)
	$DPSelectionsTabs.Anchor = 'Top, Bottom, Left, Right'
	$DPSelectionsTabs.Location = New-Object System.Drawing.Point(21, 40)
	$DPSelectionsTabs.Margin = '4, 4, 4, 4'
	$DPSelectionsTabs.Name = 'DPSelectionsTabs'
	$DPSelectionsTabs.SelectedIndex = 0
	$DPSelectionsTabs.Size = New-Object System.Drawing.Size(847, 204)
	$DPSelectionsTabs.SizeMode = 'FillToRight'
	$DPSelectionsTabs.TabIndex = 80
	#
	# DPointTab
	#
	$DPointTab.Controls.Add($DPGridView)
	$DPointTab.BackColor = [System.Drawing.Color]::Gray 
	$DPointTab.Location = New-Object System.Drawing.Point(4, 26)
	$DPointTab.Margin = '4, 4, 4, 4'
	$DPointTab.Name = 'DPointTab'
	$DPointTab.Padding = '3, 3, 3, 3'
	$DPointTab.Size = New-Object System.Drawing.Size(839, 174)
	$DPointTab.TabIndex = 0
	$DPointTab.Text = 'Distribution Points'
	#
	# DPGridView
	#
	$DPGridView.AllowUserToAddRows = $False
	$DPGridView.AllowUserToDeleteRows = $False
	$DPGridView.BackgroundColor = [System.Drawing.Color]::White 
	$DPGridView.ColumnHeadersHeightSizeMode = 'AutoSize'
	[void]$DPGridView.Columns.Add($DPSelected)
	[void]$DPGridView.Columns.Add($DPName)
	$System_Windows_Forms_DataGridViewCellStyle_4 = New-Object 'System.Windows.Forms.DataGridViewCellStyle'
	$System_Windows_Forms_DataGridViewCellStyle_4.Alignment = 'MiddleLeft'
	$System_Windows_Forms_DataGridViewCellStyle_4.BackColor = [System.Drawing.SystemColors]::Window 
	$System_Windows_Forms_DataGridViewCellStyle_4.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$System_Windows_Forms_DataGridViewCellStyle_4.ForeColor = [System.Drawing.SystemColors]::ControlText 
	$System_Windows_Forms_DataGridViewCellStyle_4.SelectionBackColor = [System.Drawing.Color]::Maroon 
	$System_Windows_Forms_DataGridViewCellStyle_4.SelectionForeColor = [System.Drawing.SystemColors]::HighlightText 
	$System_Windows_Forms_DataGridViewCellStyle_4.WrapMode = 'False'
	$DPGridView.DefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_4
	$DPGridView.Dock = 'Fill'
	$DPGridView.GridColor = [System.Drawing.Color]::WhiteSmoke 
	$DPGridView.Location = New-Object System.Drawing.Point(3, 3)
	$DPGridView.Margin = '4, 4, 4, 4'
	$DPGridView.Name = 'DPGridView'
	$DPGridView.RowHeadersVisible = $False
	$DPGridView.RowTemplate.Height = 24
	$DPGridView.SelectionMode = 'FullRowSelect'
	$DPGridView.Size = New-Object System.Drawing.Size(833, 168)
	$DPGridView.TabIndex = 0
	#
	# DPGroupTab
	#
	$DPGroupTab.Controls.Add($DPGGridView)
	$DPGroupTab.BackColor = [System.Drawing.Color]::Gray 
	$DPGroupTab.Location = New-Object System.Drawing.Point(4, 26)
	$DPGroupTab.Margin = '4, 4, 4, 4'
	$DPGroupTab.Name = 'DPGroupTab'
	$DPGroupTab.Padding = '3, 3, 3, 3'
	$DPGroupTab.Size = New-Object System.Drawing.Size(839, 174)
	$DPGroupTab.TabIndex = 1
	$DPGroupTab.Text = 'Distribution Point Groups'
	#
	# DPGGridView
	#
	$DPGGridView.AllowUserToAddRows = $False
	$DPGGridView.AllowUserToDeleteRows = $False
	$DPGGridView.BackgroundColor = [System.Drawing.Color]::WhiteSmoke 
	$DPGGridView.ColumnHeadersHeightSizeMode = 'AutoSize'
	[void]$DPGGridView.Columns.Add($DPGSelected)
	[void]$DPGGridView.Columns.Add($DPGName)
	$DPGGridView.DefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_4
	$DPGGridView.Dock = 'Fill'
	$DPGGridView.GridColor = [System.Drawing.Color]::WhiteSmoke 
	$DPGGridView.Location = New-Object System.Drawing.Point(3, 3)
	$DPGGridView.Margin = '4, 4, 4, 4'
	$DPGGridView.Name = 'DPGGridView'
	$DPGGridView.RowHeadersVisible = $False
	$DPGGridView.RowTemplate.Height = 24
	$DPGGridView.SelectionMode = 'FullRowSelect'
	$DPGGridView.Size = New-Object System.Drawing.Size(833, 168)
	$DPGGridView.TabIndex = 1
	#
	# FallbackPkgGroup
	#
	$FallbackPkgGroup.Controls.Add($FallbackManufacturer)
	$FallbackPkgGroup.Controls.Add($ManufacturerLabel)
	$FallbackPkgGroup.Controls.Add($FallbackDesc)
	$FallbackPkgGroup.Controls.Add($FallbackArcCombo)
	$FallbackPkgGroup.Controls.Add($FallbackOSCombo)
	$FallbackPkgGroup.Controls.Add($ArchitectureLabel)
	$FallbackPkgGroup.Controls.Add($OperatingSystemLabel)
	$FallbackPkgGroup.Controls.Add($CreateFallbackButton)
	$FallbackPkgGroup.Anchor = 'Bottom, Left, Right'
	$FallbackPkgGroup.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$FallbackPkgGroup.ForeColor = [System.Drawing.Color]::Black 
	$FallbackPkgGroup.Location = New-Object System.Drawing.Point(12, 292)
	$FallbackPkgGroup.Name = 'FallbackPkgGroup'
	$FallbackPkgGroup.Size = New-Object System.Drawing.Size(1199, 151)
	$FallbackPkgGroup.TabIndex = 110
	$FallbackPkgGroup.TabStop = $False
	$FallbackPkgGroup.Text = 'Driver Fallback Packages'
	$FallbackPkgGroup.UseCompatibleTextRendering = $True
	#
	# FallbackManufacturer
	#
	$FallbackManufacturer.Anchor = 'Bottom, Left'
	$FallbackManufacturer.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$FallbackManufacturer.DropDownStyle = 'DropDownList'
	$FallbackManufacturer.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$FallbackManufacturer.FormattingEnabled = $True
	[void]$FallbackManufacturer.Items.Add('Dell')
	[void]$FallbackManufacturer.Items.Add('Hewlett-Packard')
	[void]$FallbackManufacturer.Items.Add('Lenovo')
	[void]$FallbackManufacturer.Items.Add('Microsoft')
	$FallbackManufacturer.Location = New-Object System.Drawing.Point(597, 27)
	$FallbackManufacturer.Margin = '4, 3, 4, 3'
	$FallbackManufacturer.Name = 'FallbackManufacturer'
	$FallbackManufacturer.Size = New-Object System.Drawing.Size(247, 23)
	$FallbackManufacturer.TabIndex = 103
	#
	# ManufacturerLabel
	#
	$ManufacturerLabel.Anchor = 'Bottom, Left'
	$ManufacturerLabel.AutoSize = $True
	$ManufacturerLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$ManufacturerLabel.ForeColor = [System.Drawing.Color]::Black 
	$ManufacturerLabel.Location = New-Object System.Drawing.Point(483, 30)
	$ManufacturerLabel.Margin = '4, 0, 4, 0'
	$ManufacturerLabel.Name = 'ManufacturerLabel'
	$ManufacturerLabel.Size = New-Object System.Drawing.Size(84, 21)
	$ManufacturerLabel.TabIndex = 104
	$ManufacturerLabel.Text = 'Manufacturer'
	$ManufacturerLabel.UseCompatibleTextRendering = $True
	#
	# FallbackDesc
	#
	$FallbackDesc.Anchor = 'Bottom, Left'
	$FallbackDesc.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$FallbackDesc.BorderStyle = 'None'
	$FallbackDesc.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$FallbackDesc.ForeColor = [System.Drawing.Color]::Black 
	$FallbackDesc.Location = New-Object System.Drawing.Point(25, 41)
	$FallbackDesc.Multiline = $True
	$FallbackDesc.Name = 'FallbackDesc'
	$FallbackDesc.ReadOnly = $True
	$FallbackDesc.Size = New-Object System.Drawing.Size(390, 58)
	$FallbackDesc.TabIndex = 102
	$FallbackDesc.TabStop = $False
	$FallbackDesc.Text = 'Driver fallback packages can be used as a fallback mechanism when using Modern Driver Management. Refer to the Modern Driver Management page for full documentation.'
	#
	# FallbackArcCombo
	#
	$FallbackArcCombo.Anchor = 'Bottom, Left'
	$FallbackArcCombo.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$FallbackArcCombo.DropDownStyle = 'DropDownList'
	$FallbackArcCombo.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$FallbackArcCombo.FormattingEnabled = $True
	[void]$FallbackArcCombo.Items.Add('64 bit')
	[void]$FallbackArcCombo.Items.Add('32 bit')
	$FallbackArcCombo.Location = New-Object System.Drawing.Point(597, 113)
	$FallbackArcCombo.Margin = '4, 3, 4, 3'
	$FallbackArcCombo.Name = 'FallbackArcCombo'
	$FallbackArcCombo.Size = New-Object System.Drawing.Size(247, 23)
	$FallbackArcCombo.TabIndex = 99
	#
	# FallbackOSCombo
	#
	$FallbackOSCombo.Anchor = 'Bottom, Left'
	$FallbackOSCombo.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$FallbackOSCombo.DropDownStyle = 'DropDownList'
	$FallbackOSCombo.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$FallbackOSCombo.FormattingEnabled = $True
	[void]$FallbackOSCombo.Items.Add('Windows 10')
	[void]$FallbackOSCombo.Items.Add('Windows 8.1')
	[void]$FallbackOSCombo.Items.Add('Windows 8')
	[void]$FallbackOSCombo.Items.Add('Windows 7')
	$FallbackOSCombo.Location = New-Object System.Drawing.Point(597, 70)
	$FallbackOSCombo.Margin = '4, 3, 4, 3'
	$FallbackOSCombo.Name = 'FallbackOSCombo'
	$FallbackOSCombo.Size = New-Object System.Drawing.Size(247, 23)
	$FallbackOSCombo.TabIndex = 98
	#
	# ArchitectureLabel
	#
	$ArchitectureLabel.Anchor = 'Bottom, Left'
	$ArchitectureLabel.AutoSize = $True
	$ArchitectureLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$ArchitectureLabel.ForeColor = [System.Drawing.Color]::Black 
	$ArchitectureLabel.Location = New-Object System.Drawing.Point(491, 116)
	$ArchitectureLabel.Margin = '4, 0, 4, 0'
	$ArchitectureLabel.Name = 'ArchitectureLabel'
	$ArchitectureLabel.Size = New-Object System.Drawing.Size(76, 21)
	$ArchitectureLabel.TabIndex = 101
	$ArchitectureLabel.Text = 'Architecture'
	$ArchitectureLabel.UseCompatibleTextRendering = $True
	#
	# OperatingSystemLabel
	#
	$OperatingSystemLabel.Anchor = 'Bottom, Left'
	$OperatingSystemLabel.AutoSize = $True
	$OperatingSystemLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$OperatingSystemLabel.ForeColor = [System.Drawing.Color]::Black 
	$OperatingSystemLabel.Location = New-Object System.Drawing.Point(459, 73)
	$OperatingSystemLabel.Margin = '4, 0, 4, 0'
	$OperatingSystemLabel.Name = 'OperatingSystemLabel'
	$OperatingSystemLabel.Size = New-Object System.Drawing.Size(108, 21)
	$OperatingSystemLabel.TabIndex = 100
	$OperatingSystemLabel.Text = 'Operating System'
	$OperatingSystemLabel.UseCompatibleTextRendering = $True
	#
	# CreateFallbackButton
	#
	$CreateFallbackButton.Anchor = 'Bottom, Left'
	$CreateFallbackButton.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$CreateFallbackButton.Enabled = $False
	$CreateFallbackButton.FlatStyle = 'Flat'
	$CreateFallbackButton.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$CreateFallbackButton.ForeColor = [System.Drawing.Color]::White 
	$CreateFallbackButton.Location = New-Object System.Drawing.Point(880, 24)
	$CreateFallbackButton.Margin = '4, 3, 4, 3'
	$CreateFallbackButton.Name = 'CreateFallbackButton'
	$CreateFallbackButton.Size = New-Object System.Drawing.Size(259, 113)
	$CreateFallbackButton.TabIndex = 97
	$CreateFallbackButton.Text = 'Create Fallback Package'
	$CreateFallbackButton.UseCompatibleTextRendering = $True
	$CreateFallbackButton.UseVisualStyleBackColor = $False
	$CreateFallbackButton.add_Click($CreateFallbackButton_Click)
	#
	# SettingsPanel
	#
	$SettingsPanel.Anchor = 'Top, Bottom, Left, Right'
	$SettingsPanel.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$SettingsPanel.Location = New-Object System.Drawing.Point(0, 83)
	$SettingsPanel.Name = 'SettingsPanel'
	$SettingsPanel.Size = New-Object System.Drawing.Size(1229, 484)
	$SettingsPanel.TabIndex = 85
	#
	# IntuneTab
	#
	$IntuneTab.Controls.Add($labelIntuneAzureADGraphAP)
	$IntuneTab.Controls.Add($picturebox1)
	$IntuneTab.Controls.Add($panel1)
	$IntuneTab.BackColor = [System.Drawing.Color]::FromArgb(255, 0, 114, 198)
	$IntuneTab.Location = New-Object System.Drawing.Point(4, 48)
	$IntuneTab.Name = 'IntuneTab'
	$IntuneTab.Size = New-Object System.Drawing.Size(1231, 564)
	$IntuneTab.TabIndex = 15
	$IntuneTab.Text = 'Intune Settings'
	#
	# labelIntuneAzureADGraphAP
	#
	$labelIntuneAzureADGraphAP.AutoSize = $True
	$labelIntuneAzureADGraphAP.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '16', [System.Drawing.FontStyle]'Bold')
	$labelIntuneAzureADGraphAP.ForeColor = [System.Drawing.Color]::White 
	$labelIntuneAzureADGraphAP.Location = New-Object System.Drawing.Point(90, 24)
	$labelIntuneAzureADGraphAP.Name = 'labelIntuneAzureADGraphAP'
	$labelIntuneAzureADGraphAP.Size = New-Object System.Drawing.Size(397, 35)
	$labelIntuneAzureADGraphAP.TabIndex = 104
	$labelIntuneAzureADGraphAP.Text = 'Intune | Azure AD | Graph API  Settings'
	$labelIntuneAzureADGraphAP.UseCompatibleTextRendering = $True
	#
	# picturebox1
	#
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
AAEAAAD/////AQAAAAAAAAAMAgAAAFFTeXN0ZW0uRHJhd2luZywgVmVyc2lvbj00LjAuMC4wLCBD
dWx0dXJlPW5ldXRyYWwsIFB1YmxpY0tleVRva2VuPWIwM2Y1ZjdmMTFkNTBhM2EFAQAAABVTeXN0
ZW0uRHJhd2luZy5CaXRtYXABAAAABERhdGEHAgIAAAAJAwAAAA8DAAAA7gQAAAKJUE5HDQoaCgAA
AA1JSERSAAAAMgAAADIIAgAAAJFdH+YAAAAEZ0FNQQAAsY8L/GEFAAAACXBIWXMAAAsMAAALDAE/
QCLIAAAAB3RJTUUH5AEFFiEFr+EUGAAABH1JREFUWEfll99PW2UYx49zXppd7J/QOzUxXu3aRKM3
XhjdjIpI3drSgThx0yw6thnYhWTzF0HDKBuJQjKdUkGxrOdHKQXKaaGllBYOg9Ku7ekPOigtZT5v
T9P0vJZy2p6ak/jkk5N+e97zvt++P57zlCBaGSWCa4WAa4WAa4WAa4WAa4WAa4WAa4WAa4WAa+A0
RXwgNyqK0NJHsYHKgGsdfXtsxeGNsh5eNpZ521KkvdcBzvDhDkIktHTjV7b9/Uf1CN9GgtBUZ0tD
f9xjhy6y+49INjhq8Y9N1crI5IZ7LQ59boYfEmcZoqVouDKIhIY+9z2ylc5kX7pkJRpMRBNZK2/c
uzXqgz79oZptZTLZU10zRLPkOS+Divrpr9X/t60jcIW7cPIhm5zNyYP4z2w9Dlc1derabL/Be2N4
6alPJqHlgc6ayGEjB32G+J06z5aaunrLtbO7By0huM2tFz6zEI2kKH8WaDBpbrC/0eu9d5dRUgWK
74I8Q5X4SSIhxVYLc6zNHIhsC56EWA8m2aWIw1OKZZ51R2acodnFsMPD5yjc5Re8fN+It0SaFQkp
tnTMKx3WVDo/VbVHPJl+un0SrW/xKCIhbbaAtUBS6FQINxejbAGGDVaGPZhKZxPJ9HPna7cFQLMe
RzSxK3ha8EWPf2RGewtLpOV5n4RT/CC6s/Uw/awstlAhoKZPXJzqHHSd/2EezZ+ubI4oSQtztM0c
iqVkswU8BlcdA4cI/MEASFZKPWxVwfE2M/QPw+d/Q3W2TsprS0Nf6HX8OeVHK66lUUKuwhZUEK92
WNEuhneLLLxrau9xQM9uLv7y5WmUSCuyJTwMlaBnLQ5HzCkTkDZX/QnoGYJP7H7evwBLcUSqrWb6
rWuzmb36lKdFASkUzVkLI80W0Ex3D7lJW2BiZrMkxmk/ZELMeji2M271Yy2Bv63+UfM6XI1W/5w7
LDTeDG/rvmHRPw6psyWcfDj2WOorpsH0/KeWwntaCNYTId68h7d8x6T5mjXaAqevzxGvTwjl+Mxi
+JkLFjREBXvrMJBpNd3YPbeXFfzkA4oIYSRRexU1OLYCd/UGL2z5cz324QkO5QihCqrFFjrJOjp/
muD4wBvjDAWrI7gpRCa736F3Eu/lJgmaQWNwqSIH/kBVfN/vXvQldKVG1ivPW/9Gx5zsmr0+vATl
Xp/BN2bZ4MQv6UJAToGlhPn49o6n+2d35+AiPKs3iG0VU5OtJnJoHJW8VcSLX1hvjnjhQx1saenW
7+x36fU75H3p/ELdH5rgnvzQ3J+brd5fl4m3TWhZi4GF1tIPolXZegKu8AqCHaOqBNQeHWdhb41P
+S/+OH9F7/xywNk16Oq87YLPl/XOKwPOWDJd1WzVgooSbBUC9l8wss3HU3mdi/jW7mFloLyoKGHL
FyISSw0ZOZMtkNe5kFA0y4uOfu3qtMUZmvdF7V4EfFjk4q7VmCMn4bqwErtp8KF9gj2La/nI5Twm
n8YOAu4e/odMOeBaIeBaIeBaIeBaIeBaIeBaIeBaCbQy/wDNo/deFMOXnQAAAABJRU5ErkJgggs='))
	#endregion
	$picturebox1.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$picturebox1.Location = New-Object System.Drawing.Point(20, 16)
	$picturebox1.Name = 'picturebox1'
	$picturebox1.Size = New-Object System.Drawing.Size(50, 50)
	$picturebox1.SizeMode = 'StretchImage'
	$picturebox1.TabIndex = 103
	$picturebox1.TabStop = $False
	#
	# panel1
	#
	$panel1.Controls.Add($groupbox7)
	$panel1.Controls.Add($groupbox6)
	$panel1.Controls.Add($groupbox5)
	$panel1.Anchor = 'Top, Bottom, Left, Right'
	$panel1.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$panel1.Location = New-Object System.Drawing.Point(0, 83)
	$panel1.Name = 'panel1'
	$panel1.Size = New-Object System.Drawing.Size(1229, 481)
	$panel1.TabIndex = 114
	#
	# groupbox7
	#
	$groupbox7.Controls.Add($IntuneUniqueDeviceCount)
	$groupbox7.Controls.Add($IntuneUniqueCount)
	$groupbox7.Controls.Add($GraphAuthStatus)
	$groupbox7.Controls.Add($AADAppID)
	$groupbox7.Controls.Add($labelAuthenticationStatus)
	$groupbox7.Controls.Add($Win32BIOSCount)
	$groupbox7.Controls.Add($labelTenantName)
	$groupbox7.Controls.Add($labelBIOSPackageCount)
	$groupbox7.Controls.Add($labelAppID)
	$groupbox7.Controls.Add($Win32DriverCount)
	$groupbox7.Controls.Add($AADTenantName)
	$groupbox7.Controls.Add($labelDriverPackageCount)
	$groupbox7.Controls.Add($buttonConnectGraphAPI)
	$groupbox7.Controls.Add($labelAppSecret)
	$groupbox7.Controls.Add($IntuneDeviceCount)
	$groupbox7.Controls.Add($APPSecret)
	$groupbox7.Controls.Add($labelNumberOfManagedDevic)
	$groupbox7.Anchor = 'Top, Bottom, Left, Right'
	$groupbox7.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$groupbox7.Location = New-Object System.Drawing.Point(3, 3)
	$groupbox7.Name = 'groupbox7'
	$groupbox7.Size = New-Object System.Drawing.Size(1220, 220)
	$groupbox7.TabIndex = 117
	$groupbox7.TabStop = $False
	$groupbox7.Text = 'Azure AD | APP Security Info'
	$groupbox7.UseCompatibleTextRendering = $True
	#
	# IntuneUniqueDeviceCount
	#
	$IntuneUniqueDeviceCount.AutoSize = $True
	$IntuneUniqueDeviceCount.BackColor = [System.Drawing.Color]::Transparent 
	$IntuneUniqueDeviceCount.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$IntuneUniqueDeviceCount.ForeColor = [System.Drawing.Color]::Black 
	$IntuneUniqueDeviceCount.Location = New-Object System.Drawing.Point(1107, 103)
	$IntuneUniqueDeviceCount.Margin = '4, 0, 4, 0'
	$IntuneUniqueDeviceCount.Name = 'IntuneUniqueDeviceCount'
	$IntuneUniqueDeviceCount.Size = New-Object System.Drawing.Size(28, 22)
	$IntuneUniqueDeviceCount.TabIndex = 123
	$IntuneUniqueDeviceCount.Text = '- - -'
	$IntuneUniqueDeviceCount.UseCompatibleTextRendering = $True
	#
	# IntuneUniqueCount
	#
	$IntuneUniqueCount.AutoSize = $True
	$IntuneUniqueCount.BackColor = [System.Drawing.Color]::Transparent 
	$IntuneUniqueCount.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$IntuneUniqueCount.ForeColor = [System.Drawing.Color]::Black 
	$IntuneUniqueCount.Location = New-Object System.Drawing.Point(821, 99)
	$IntuneUniqueCount.Margin = '4, 0, 4, 0'
	$IntuneUniqueCount.Name = 'IntuneUniqueCount'
	$IntuneUniqueCount.Size = New-Object System.Drawing.Size(161, 22)
	$IntuneUniqueCount.TabIndex = 122
	$IntuneUniqueCount.Text = 'Number of unique devices'
	$IntuneUniqueCount.UseCompatibleTextRendering = $True
	#
	# GraphAuthStatus
	#
	$GraphAuthStatus.AutoSize = $True
	$GraphAuthStatus.BackColor = [System.Drawing.Color]::Transparent 
	$GraphAuthStatus.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$GraphAuthStatus.ForeColor = [System.Drawing.Color]::Black 
	$GraphAuthStatus.Location = New-Object System.Drawing.Point(1107, 29)
	$GraphAuthStatus.Margin = '4, 0, 4, 0'
	$GraphAuthStatus.Name = 'GraphAuthStatus'
	$GraphAuthStatus.Size = New-Object System.Drawing.Size(28, 22)
	$GraphAuthStatus.TabIndex = 110
	$GraphAuthStatus.Text = '- - -'
	$GraphAuthStatus.UseCompatibleTextRendering = $True
	#
	# AADAppID
	#
	$AADAppID.BackColor = [System.Drawing.Color]::White 
	$AADAppID.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$AADAppID.ForeColor = [System.Drawing.Color]::Black 
	$AADAppID.Location = New-Object System.Drawing.Point(191, 93)
	$AADAppID.Margin = '4, 3, 4, 3'
	$AADAppID.Name = 'AADAppID'
	$AADAppID.Size = New-Object System.Drawing.Size(326, 25)
	$AADAppID.TabIndex = 109
	#
	# labelAuthenticationStatus
	#
	$labelAuthenticationStatus.AutoSize = $True
	$labelAuthenticationStatus.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$labelAuthenticationStatus.ForeColor = [System.Drawing.Color]::Black 
	$labelAuthenticationStatus.Location = New-Object System.Drawing.Point(821, 29)
	$labelAuthenticationStatus.Name = 'labelAuthenticationStatus'
	$labelAuthenticationStatus.Size = New-Object System.Drawing.Size(142, 22)
	$labelAuthenticationStatus.TabIndex = 109
	$labelAuthenticationStatus.Text = 'Authentication Status'
	$labelAuthenticationStatus.UseCompatibleTextRendering = $True
	#
	# Win32BIOSCount
	#
	$Win32BIOSCount.AutoSize = $True
	$Win32BIOSCount.BackColor = [System.Drawing.Color]::Transparent 
	$Win32BIOSCount.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$Win32BIOSCount.ForeColor = [System.Drawing.Color]::Black 
	$Win32BIOSCount.Location = New-Object System.Drawing.Point(1107, 172)
	$Win32BIOSCount.Margin = '4, 0, 4, 0'
	$Win32BIOSCount.Name = 'Win32BIOSCount'
	$Win32BIOSCount.Size = New-Object System.Drawing.Size(28, 22)
	$Win32BIOSCount.TabIndex = 108
	$Win32BIOSCount.Text = '- - -'
	$Win32BIOSCount.UseCompatibleTextRendering = $True
	#
	# labelTenantName
	#
	$labelTenantName.AutoSize = $True
	$labelTenantName.BackColor = [System.Drawing.Color]::Transparent 
	$labelTenantName.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$labelTenantName.ForeColor = [System.Drawing.Color]::Black 
	$labelTenantName.Location = New-Object System.Drawing.Point(29, 56)
	$labelTenantName.Margin = '4, 0, 4, 0'
	$labelTenantName.Name = 'labelTenantName'
	$labelTenantName.Size = New-Object System.Drawing.Size(83, 21)
	$labelTenantName.TabIndex = 121
	$labelTenantName.Text = 'Tenant Name'
	$labelTenantName.UseCompatibleTextRendering = $True
	#
	# labelBIOSPackageCount
	#
	$labelBIOSPackageCount.AutoSize = $True
	$labelBIOSPackageCount.BackColor = [System.Drawing.Color]::Transparent 
	$labelBIOSPackageCount.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$labelBIOSPackageCount.ForeColor = [System.Drawing.Color]::Black 
	$labelBIOSPackageCount.Location = New-Object System.Drawing.Point(821, 172)
	$labelBIOSPackageCount.Margin = '4, 0, 4, 0'
	$labelBIOSPackageCount.Name = 'labelBIOSPackageCount'
	$labelBIOSPackageCount.Size = New-Object System.Drawing.Size(128, 22)
	$labelBIOSPackageCount.TabIndex = 107
	$labelBIOSPackageCount.Text = 'BIOS Package Count:'
	$labelBIOSPackageCount.UseCompatibleTextRendering = $True
	#
	# labelAppID
	#
	$labelAppID.AutoSize = $True
	$labelAppID.BackColor = [System.Drawing.Color]::Transparent 
	$labelAppID.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$labelAppID.ForeColor = [System.Drawing.Color]::Black 
	$labelAppID.Location = New-Object System.Drawing.Point(29, 96)
	$labelAppID.Margin = '4, 0, 4, 0'
	$labelAppID.Name = 'labelAppID'
	$labelAppID.Size = New-Object System.Drawing.Size(45, 21)
	$labelAppID.TabIndex = 110
	$labelAppID.Text = 'App ID'
	$labelAppID.UseCompatibleTextRendering = $True
	#
	# Win32DriverCount
	#
	$Win32DriverCount.AutoSize = $True
	$Win32DriverCount.BackColor = [System.Drawing.Color]::Transparent 
	$Win32DriverCount.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$Win32DriverCount.ForeColor = [System.Drawing.Color]::Black 
	$Win32DriverCount.Location = New-Object System.Drawing.Point(1107, 140)
	$Win32DriverCount.Margin = '4, 0, 4, 0'
	$Win32DriverCount.Name = 'Win32DriverCount'
	$Win32DriverCount.Size = New-Object System.Drawing.Size(28, 22)
	$Win32DriverCount.TabIndex = 106
	$Win32DriverCount.Text = '- - -'
	$Win32DriverCount.UseCompatibleTextRendering = $True
	#
	# AADTenantName
	#
	$AADTenantName.BackColor = [System.Drawing.Color]::White 
	$AADTenantName.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$AADTenantName.ForeColor = [System.Drawing.Color]::Black 
	$AADTenantName.Location = New-Object System.Drawing.Point(191, 53)
	$AADTenantName.Margin = '4, 3, 4, 3'
	$AADTenantName.Name = 'AADTenantName'
	$AADTenantName.Size = New-Object System.Drawing.Size(326, 25)
	$AADTenantName.TabIndex = 120
	#
	# labelDriverPackageCount
	#
	$labelDriverPackageCount.AutoSize = $True
	$labelDriverPackageCount.BackColor = [System.Drawing.Color]::Transparent 
	$labelDriverPackageCount.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$labelDriverPackageCount.ForeColor = [System.Drawing.Color]::Black 
	$labelDriverPackageCount.Location = New-Object System.Drawing.Point(821, 140)
	$labelDriverPackageCount.Margin = '4, 0, 4, 0'
	$labelDriverPackageCount.Name = 'labelDriverPackageCount'
	$labelDriverPackageCount.Size = New-Object System.Drawing.Size(135, 22)
	$labelDriverPackageCount.TabIndex = 105
	$labelDriverPackageCount.Text = 'Driver Package Count:'
	$labelDriverPackageCount.UseCompatibleTextRendering = $True
	#
	# buttonConnectGraphAPI
	#
	$buttonConnectGraphAPI.BackColor = [System.Drawing.Color]::FromArgb(255, 0, 114, 198)
	$buttonConnectGraphAPI.Enabled = $False
	$buttonConnectGraphAPI.FlatAppearance.BorderSize = 0
	$buttonConnectGraphAPI.FlatStyle = 'Flat'
	$buttonConnectGraphAPI.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$buttonConnectGraphAPI.ForeColor = [System.Drawing.Color]::White 
	$buttonConnectGraphAPI.Location = New-Object System.Drawing.Point(583, 72)
	$buttonConnectGraphAPI.Margin = '4, 3, 4, 3'
	$buttonConnectGraphAPI.Name = 'buttonConnectGraphAPI'
	$buttonConnectGraphAPI.Size = New-Object System.Drawing.Size(184, 65)
	$buttonConnectGraphAPI.TabIndex = 111
	$buttonConnectGraphAPI.Text = 'Connect Graph API'
	$buttonConnectGraphAPI.UseCompatibleTextRendering = $True
	$buttonConnectGraphAPI.UseVisualStyleBackColor = $False
	$buttonConnectGraphAPI.add_Click($buttonConnectGraphAPI_Click)
	#
	# labelAppSecret
	#
	$labelAppSecret.AutoSize = $True
	$labelAppSecret.BackColor = [System.Drawing.Color]::Transparent 
	$labelAppSecret.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$labelAppSecret.ForeColor = [System.Drawing.Color]::Black 
	$labelAppSecret.Location = New-Object System.Drawing.Point(29, 136)
	$labelAppSecret.Margin = '4, 0, 4, 0'
	$labelAppSecret.Name = 'labelAppSecret'
	$labelAppSecret.Size = New-Object System.Drawing.Size(68, 21)
	$labelAppSecret.TabIndex = 119
	$labelAppSecret.Text = 'App Secret'
	$labelAppSecret.UseCompatibleTextRendering = $True
	#
	# IntuneDeviceCount
	#
	$IntuneDeviceCount.AutoSize = $True
	$IntuneDeviceCount.BackColor = [System.Drawing.Color]::Transparent 
	$IntuneDeviceCount.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$IntuneDeviceCount.ForeColor = [System.Drawing.Color]::Black 
	$IntuneDeviceCount.Location = New-Object System.Drawing.Point(1107, 71)
	$IntuneDeviceCount.Margin = '4, 0, 4, 0'
	$IntuneDeviceCount.Name = 'IntuneDeviceCount'
	$IntuneDeviceCount.Size = New-Object System.Drawing.Size(28, 22)
	$IntuneDeviceCount.TabIndex = 103
	$IntuneDeviceCount.Text = '- - -'
	$IntuneDeviceCount.UseCompatibleTextRendering = $True
	#
	# APPSecret
	#
	$APPSecret.BackColor = [System.Drawing.Color]::White 
	$APPSecret.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$APPSecret.ForeColor = [System.Drawing.Color]::Black 
	$APPSecret.Location = New-Object System.Drawing.Point(191, 133)
	$APPSecret.Margin = '4, 3, 4, 3'
	$APPSecret.Name = 'APPSecret'
	$APPSecret.PasswordChar = '*'
	$APPSecret.Size = New-Object System.Drawing.Size(326, 25)
	$APPSecret.TabIndex = 118
	#
	# labelNumberOfManagedDevic
	#
	$labelNumberOfManagedDevic.AutoSize = $True
	$labelNumberOfManagedDevic.BackColor = [System.Drawing.Color]::Transparent 
	$labelNumberOfManagedDevic.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$labelNumberOfManagedDevic.ForeColor = [System.Drawing.Color]::Black 
	$labelNumberOfManagedDevic.Location = New-Object System.Drawing.Point(821, 64)
	$labelNumberOfManagedDevic.Margin = '4, 0, 4, 0'
	$labelNumberOfManagedDevic.Name = 'labelNumberOfManagedDevic'
	$labelNumberOfManagedDevic.Size = New-Object System.Drawing.Size(175, 22)
	$labelNumberOfManagedDevic.TabIndex = 102
	$labelNumberOfManagedDevic.Text = 'Number of managed devices'
	$labelNumberOfManagedDevic.UseCompatibleTextRendering = $True
	#
	# groupbox6
	#
	$groupbox6.Controls.Add($IntuneAppDataGrid)
	$groupbox6.Anchor = 'Top, Bottom, Left, Right'
	$groupbox6.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$groupbox6.Location = New-Object System.Drawing.Point(612, 231)
	$groupbox6.Name = 'groupbox6'
	$groupbox6.Size = New-Object System.Drawing.Size(611, 238)
	$groupbox6.TabIndex = 117
	$groupbox6.TabStop = $False
	$groupbox6.Text = 'Win32 Application Details'
	$groupbox6.UseCompatibleTextRendering = $True
	#
	# IntuneAppDataGrid
	#
	$IntuneAppDataGrid.AllowUserToAddRows = $False
	$IntuneAppDataGrid.AllowUserToDeleteRows = $False
	$IntuneAppDataGrid.Anchor = 'Top, Bottom, Left, Right'
	$IntuneAppDataGrid.BackgroundColor = [System.Drawing.Color]::White 
	$IntuneAppDataGrid.BorderStyle = 'None'
	$System_Windows_Forms_DataGridViewCellStyle_5 = New-Object 'System.Windows.Forms.DataGridViewCellStyle'
	$System_Windows_Forms_DataGridViewCellStyle_5.Alignment = 'MiddleLeft'
	$System_Windows_Forms_DataGridViewCellStyle_5.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$System_Windows_Forms_DataGridViewCellStyle_5.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$System_Windows_Forms_DataGridViewCellStyle_5.ForeColor = [System.Drawing.SystemColors]::WindowText 
	$System_Windows_Forms_DataGridViewCellStyle_5.SelectionBackColor = [System.Drawing.Color]::FromArgb(255, 0, 114, 198)
	$System_Windows_Forms_DataGridViewCellStyle_5.SelectionForeColor = [System.Drawing.SystemColors]::HighlightText 
	$System_Windows_Forms_DataGridViewCellStyle_5.WrapMode = 'True'
	$IntuneAppDataGrid.ColumnHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_5
	$IntuneAppDataGrid.ColumnHeadersHeight = 30
	$IntuneAppDataGrid.ColumnHeadersHeightSizeMode = 'DisableResizing'
	[void]$IntuneAppDataGrid.Columns.Add($Win32Package)
	[void]$IntuneAppDataGrid.Columns.Add($PackageDetails)
	$System_Windows_Forms_DataGridViewCellStyle_6 = New-Object 'System.Windows.Forms.DataGridViewCellStyle'
	$System_Windows_Forms_DataGridViewCellStyle_6.Alignment = 'MiddleLeft'
	$System_Windows_Forms_DataGridViewCellStyle_6.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$System_Windows_Forms_DataGridViewCellStyle_6.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$System_Windows_Forms_DataGridViewCellStyle_6.ForeColor = [System.Drawing.SystemColors]::ControlText 
	$System_Windows_Forms_DataGridViewCellStyle_6.SelectionBackColor = [System.Drawing.Color]::Maroon 
	$System_Windows_Forms_DataGridViewCellStyle_6.SelectionForeColor = [System.Drawing.SystemColors]::HighlightText 
	$System_Windows_Forms_DataGridViewCellStyle_6.WrapMode = 'False'
	$IntuneAppDataGrid.DefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_6
	$IntuneAppDataGrid.GridColor = [System.Drawing.Color]::WhiteSmoke 
	$IntuneAppDataGrid.Location = New-Object System.Drawing.Point(6, 24)
	$IntuneAppDataGrid.Name = 'IntuneAppDataGrid'
	$System_Windows_Forms_DataGridViewCellStyle_7 = New-Object 'System.Windows.Forms.DataGridViewCellStyle'
	$System_Windows_Forms_DataGridViewCellStyle_7.Alignment = 'MiddleLeft'
	$System_Windows_Forms_DataGridViewCellStyle_7.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$System_Windows_Forms_DataGridViewCellStyle_7.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$System_Windows_Forms_DataGridViewCellStyle_7.ForeColor = [System.Drawing.Color]::Black 
	$System_Windows_Forms_DataGridViewCellStyle_7.SelectionBackColor = [System.Drawing.Color]::FromArgb(255, 0, 114, 198)
	$System_Windows_Forms_DataGridViewCellStyle_7.SelectionForeColor = [System.Drawing.SystemColors]::HighlightText 
	$System_Windows_Forms_DataGridViewCellStyle_7.WrapMode = 'True'
	$IntuneAppDataGrid.RowHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_7
	$IntuneAppDataGrid.RowHeadersVisible = $False
	$System_Windows_Forms_DataGridViewCellStyle_8 = New-Object 'System.Windows.Forms.DataGridViewCellStyle'
	$System_Windows_Forms_DataGridViewCellStyle_8.SelectionBackColor = [System.Drawing.Color]::FromArgb(255, 0, 114, 198)
	$IntuneAppDataGrid.RowsDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_8
	$IntuneAppDataGrid.RowTemplate.DefaultCellStyle.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$IntuneAppDataGrid.RowTemplate.Height = 24
	$IntuneAppDataGrid.Size = New-Object System.Drawing.Size(599, 208)
	$IntuneAppDataGrid.TabIndex = 76
	#
	# groupbox5
	#
	$groupbox5.Controls.Add($RefreshIntuneModels)
	$groupbox5.Controls.Add($IntuneSelectKnownModels)
	$groupbox5.Controls.Add($checkboxRemoveUnusedDriverPa)
	$groupbox5.Controls.Add($textbox1)
	$groupbox5.Controls.Add($textbox3)
	$groupbox5.Controls.Add($checkboxRemoveUnusedBIOSPack)
	$groupbox5.Controls.Add($IntuneKnownModels)
	$groupbox5.Anchor = 'Top, Bottom, Left, Right'
	$groupbox5.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$groupbox5.Location = New-Object System.Drawing.Point(3, 231)
	$groupbox5.Name = 'groupbox5'
	$groupbox5.Size = New-Object System.Drawing.Size(603, 238)
	$groupbox5.TabIndex = 116
	$groupbox5.TabStop = $False
	$groupbox5.Text = 'Win32 App Package Options'
	$groupbox5.UseCompatibleTextRendering = $True
	#
	# RefreshIntuneModels
	#
	$RefreshIntuneModels.BackColor = [System.Drawing.Color]::FromArgb(255, 0, 114, 198)
	$RefreshIntuneModels.FlatAppearance.BorderSize = 0
	$RefreshIntuneModels.FlatStyle = 'Flat'
	$RefreshIntuneModels.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$RefreshIntuneModels.ForeColor = [System.Drawing.Color]::White 
	$RefreshIntuneModels.Location = New-Object System.Drawing.Point(279, 76)
	$RefreshIntuneModels.Margin = '4, 3, 4, 3'
	$RefreshIntuneModels.Name = 'RefreshIntuneModels'
	$RefreshIntuneModels.Size = New-Object System.Drawing.Size(238, 26)
	$RefreshIntuneModels.TabIndex = 122
	$RefreshIntuneModels.Text = 'Refresh Known Models'
	$RefreshIntuneModels.UseCompatibleTextRendering = $True
	$RefreshIntuneModels.UseVisualStyleBackColor = $False
	$RefreshIntuneModels.add_Click($RefreshIntuneModels_Click)
	#
	# IntuneSelectKnownModels
	#
	$IntuneSelectKnownModels.AutoSize = $True
	$IntuneSelectKnownModels.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$IntuneSelectKnownModels.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$IntuneSelectKnownModels.ForeColor = [System.Drawing.Color]::Black 
	$IntuneSelectKnownModels.Location = New-Object System.Drawing.Point(31, 40)
	$IntuneSelectKnownModels.Name = 'IntuneSelectKnownModels'
	$IntuneSelectKnownModels.Size = New-Object System.Drawing.Size(129, 21)
	$IntuneSelectKnownModels.TabIndex = 112
	$IntuneSelectKnownModels.Text = 'Select Known Models'
	$IntuneSelectKnownModels.UseCompatibleTextRendering = $True
	#
	# checkboxRemoveUnusedDriverPa
	#
	$checkboxRemoveUnusedDriverPa.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$checkboxRemoveUnusedDriverPa.Enabled = $False
	$checkboxRemoveUnusedDriverPa.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$checkboxRemoveUnusedDriverPa.ForeColor = [System.Drawing.Color]::Black 
	$checkboxRemoveUnusedDriverPa.Location = New-Object System.Drawing.Point(31, 119)
	$checkboxRemoveUnusedDriverPa.Name = 'checkboxRemoveUnusedDriverPa'
	$checkboxRemoveUnusedDriverPa.Size = New-Object System.Drawing.Size(396, 24)
	$checkboxRemoveUnusedDriverPa.TabIndex = 107
	$checkboxRemoveUnusedDriverPa.Text = 'Remove Unused Driver Packages'
	$checkboxRemoveUnusedDriverPa.UseCompatibleTextRendering = $True
	$checkboxRemoveUnusedDriverPa.UseVisualStyleBackColor = $False
	#
	# textbox1
	#
	$textbox1.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$textbox1.BorderStyle = 'None'
	$textbox1.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$textbox1.ForeColor = [System.Drawing.Color]::Black 
	$textbox1.Location = New-Object System.Drawing.Point(47, 206)
	$textbox1.Multiline = $True
	$textbox1.Name = 'textbox1'
	$textbox1.ReadOnly = $True
	$textbox1.Size = New-Object System.Drawing.Size(418, 29)
	$textbox1.TabIndex = 115
	$textbox1.TabStop = $False
	$textbox1.Text = 'Removes BIOS packages where no supported models exist'
	#
	# textbox3
	#
	$textbox3.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$textbox3.BorderStyle = 'None'
	$textbox3.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$textbox3.ForeColor = [System.Drawing.Color]::Black 
	$textbox3.Location = New-Object System.Drawing.Point(43, 149)
	$textbox3.Multiline = $True
	$textbox3.Name = 'textbox3'
	$textbox3.ReadOnly = $True
	$textbox3.Size = New-Object System.Drawing.Size(418, 29)
	$textbox3.TabIndex = 108
	$textbox3.TabStop = $False
	$textbox3.Text = 'Removes driver packages where no supported models exist'
	#
	# checkboxRemoveUnusedBIOSPack
	#
	$checkboxRemoveUnusedBIOSPack.Enabled = $False
	$checkboxRemoveUnusedBIOSPack.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$checkboxRemoveUnusedBIOSPack.ForeColor = [System.Drawing.Color]::Black 
	$checkboxRemoveUnusedBIOSPack.Location = New-Object System.Drawing.Point(31, 184)
	$checkboxRemoveUnusedBIOSPack.Name = 'checkboxRemoveUnusedBIOSPack'
	$checkboxRemoveUnusedBIOSPack.Size = New-Object System.Drawing.Size(396, 24)
	$checkboxRemoveUnusedBIOSPack.TabIndex = 114
	$checkboxRemoveUnusedBIOSPack.Text = 'Remove Unused BIOS Packages'
	$checkboxRemoveUnusedBIOSPack.UseCompatibleTextRendering = $True
	$checkboxRemoveUnusedBIOSPack.UseVisualStyleBackColor = $True
	#
	# IntuneKnownModels
	#
	$IntuneKnownModels.BackColor = [System.Drawing.Color]::White 
	$IntuneKnownModels.DropDownStyle = 'DropDownList'
	$IntuneKnownModels.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$IntuneKnownModels.ForeColor = [System.Drawing.Color]::Black 
	$IntuneKnownModels.FormattingEnabled = $True
	[void]$IntuneKnownModels.Items.Add('Yes')
	[void]$IntuneKnownModels.Items.Add('No')
	$IntuneKnownModels.Location = New-Object System.Drawing.Point(279, 37)
	$IntuneKnownModels.Name = 'IntuneKnownModels'
	$IntuneKnownModels.Size = New-Object System.Drawing.Size(238, 23)
	$IntuneKnownModels.TabIndex = 113
	#
	# MDTTab
	#
	$MDTTab.Controls.Add($MDTTabLabel)
	$MDTTab.Controls.Add($MDTSettingsIcon)
	$MDTTab.Controls.Add($DeploymentShareGrid)
	$MDTTab.Controls.Add($MDTSettingsPanel)
	$MDTTab.BackColor = [System.Drawing.Color]::Gray 
	$MDTTab.Location = New-Object System.Drawing.Point(4, 48)
	$MDTTab.Name = 'MDTTab'
	$MDTTab.Size = New-Object System.Drawing.Size(1231, 564)
	$MDTTab.TabIndex = 5
	$MDTTab.Text = 'MDT Settings'
	#
	# MDTTabLabel
	#
	$MDTTabLabel.AutoSize = $True
	$MDTTabLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '16', [System.Drawing.FontStyle]'Bold')
	$MDTTabLabel.ForeColor = [System.Drawing.Color]::White 
	$MDTTabLabel.Location = New-Object System.Drawing.Point(90, 24)
	$MDTTabLabel.Name = 'MDTTabLabel'
	$MDTTabLabel.Size = New-Object System.Drawing.Size(406, 35)
	$MDTTabLabel.TabIndex = 71
	$MDTTabLabel.Text = 'Microsoft Deployment Toolkit | Settings'
	$MDTTabLabel.UseCompatibleTextRendering = $True
	#
	# MDTSettingsIcon
	#
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
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
rkJgggs='))
	#endregion
	$MDTSettingsIcon.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$MDTSettingsIcon.Location = New-Object System.Drawing.Point(20, 16)
	$MDTSettingsIcon.Name = 'MDTSettingsIcon'
	$MDTSettingsIcon.Size = New-Object System.Drawing.Size(50, 50)
	$MDTSettingsIcon.SizeMode = 'StretchImage'
	$MDTSettingsIcon.TabIndex = 70
	$MDTSettingsIcon.TabStop = $False
	#
	# DeploymentShareGrid
	#
	$DeploymentShareGrid.AllowUserToAddRows = $False
	$DeploymentShareGrid.AllowUserToDeleteRows = $False
	$DeploymentShareGrid.Anchor = 'Top, Bottom, Left, Right'
	$DeploymentShareGrid.BackgroundColor = [System.Drawing.Color]::White 
	$DeploymentShareGrid.BorderStyle = 'None'
	$DeploymentShareGrid.ColumnHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_1
	$DeploymentShareGrid.ColumnHeadersHeight = 30
	$DeploymentShareGrid.ColumnHeadersHeightSizeMode = 'DisableResizing'
	[void]$DeploymentShareGrid.Columns.Add($Select)
	[void]$DeploymentShareGrid.Columns.Add($Name)
	[void]$DeploymentShareGrid.Columns.Add($Path)
	[void]$DeploymentShareGrid.Columns.Add($Description)
	$DeploymentShareGrid.DefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_2
	$DeploymentShareGrid.GridColor = [System.Drawing.Color]::WhiteSmoke 
	$DeploymentShareGrid.Location = New-Object System.Drawing.Point(0, 323)
	$DeploymentShareGrid.Name = 'DeploymentShareGrid'
	$DeploymentShareGrid.RowHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_3
	$DeploymentShareGrid.RowHeadersVisible = $False
	$DeploymentShareGrid.RowTemplate.DefaultCellStyle.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$DeploymentShareGrid.RowTemplate.Height = 24
	$DeploymentShareGrid.Size = New-Object System.Drawing.Size(1226, 262)
	$DeploymentShareGrid.TabIndex = 0
	$DeploymentShareGrid.add_CurrentCellDirtyStateChanged($DeploymentShareGrid_CurrentCellDirtyStateChanged)
	$DeploymentShareGrid.add_SelectionChanged($DeploymentShareGrid_SelectionChanged)
	#
	# MDTSettingsPanel
	#
	$MDTSettingsPanel.Controls.Add($FolderStructureGroup)
	$MDTSettingsPanel.Controls.Add($MDTScriptGroup)
	$MDTSettingsPanel.Anchor = 'Top, Left, Right'
	$MDTSettingsPanel.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$MDTSettingsPanel.Location = New-Object System.Drawing.Point(0, 83)
	$MDTSettingsPanel.Name = 'MDTSettingsPanel'
	$MDTSettingsPanel.Size = New-Object System.Drawing.Size(1230, 404)
	$MDTSettingsPanel.TabIndex = 2
	#
	# FolderStructureGroup
	#
	$FolderStructureGroup.Controls.Add($MDTDriverStructureCombo)
	$FolderStructureGroup.Controls.Add($TotalControlLabel)
	$FolderStructureGroup.Controls.Add($TotalControlExampleLabel)
	$FolderStructureGroup.Controls.Add($FolderStructureLabel)
	$FolderStructureGroup.Anchor = 'Bottom, Left, Right'
	$FolderStructureGroup.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$FolderStructureGroup.ForeColor = [System.Drawing.Color]::Black 
	$FolderStructureGroup.Location = New-Object System.Drawing.Point(727, 12)
	$FolderStructureGroup.Name = 'FolderStructureGroup'
	$FolderStructureGroup.Size = New-Object System.Drawing.Size(489, 222)
	$FolderStructureGroup.TabIndex = 1
	$FolderStructureGroup.TabStop = $False
	$FolderStructureGroup.Text = 'Folder Structure Options'
	$FolderStructureGroup.UseCompatibleTextRendering = $True
	#
	# MDTDriverStructureCombo
	#
	$MDTDriverStructureCombo.BackColor = [System.Drawing.Color]::White 
	$MDTDriverStructureCombo.DropDownStyle = 'DropDownList'
	$MDTDriverStructureCombo.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$MDTDriverStructureCombo.FormattingEnabled = $True
	[void]$MDTDriverStructureCombo.Items.Add('OperatingSystemDir\Make\Model\DriverRevision')
	[void]$MDTDriverStructureCombo.Items.Add('Make\Model\OperatingSystemDir\DriverRevision')
	[void]$MDTDriverStructureCombo.Items.Add('OperatingSystemDir\Make\Model')
	[void]$MDTDriverStructureCombo.Items.Add('Make\Model\OperatingSystemDir')
	$MDTDriverStructureCombo.Location = New-Object System.Drawing.Point(24, 62)
	$MDTDriverStructureCombo.Name = 'MDTDriverStructureCombo'
	$MDTDriverStructureCombo.Size = New-Object System.Drawing.Size(300, 23)
	$MDTDriverStructureCombo.TabIndex = 3
	#
	# TotalControlLabel
	#
	$TotalControlLabel.AutoSize = $True
	$TotalControlLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$TotalControlLabel.ForeColor = [System.Drawing.Color]::Black 
	$TotalControlLabel.Location = New-Object System.Drawing.Point(24, 114)
	$TotalControlLabel.Name = 'TotalControlLabel'
	$TotalControlLabel.Size = New-Object System.Drawing.Size(180, 21)
	$TotalControlLabel.TabIndex = 97
	$TotalControlLabel.Text = 'Total Control Method Naming'
	$TotalControlLabel.UseCompatibleTextRendering = $True
	#
	# TotalControlExampleLabel
	#
	$TotalControlExampleLabel.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$TotalControlExampleLabel.BorderStyle = 'None'
	$TotalControlExampleLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$TotalControlExampleLabel.ForeColor = [System.Drawing.Color]::Black 
	$TotalControlExampleLabel.Location = New-Object System.Drawing.Point(24, 138)
	$TotalControlExampleLabel.Multiline = $True
	$TotalControlExampleLabel.Name = 'TotalControlExampleLabel'
	$TotalControlExampleLabel.ReadOnly = $True
	$TotalControlExampleLabel.Size = New-Object System.Drawing.Size(383, 66)
	$TotalControlExampleLabel.TabIndex = 96
	$TotalControlExampleLabel.TabStop = $False
	$TotalControlExampleLabel.Text = "Example: Make\Model\OperatingSystem$\Revision
Structure: Lenovo\T460S\Windows 10 x64\A08\"
	#
	# FolderStructureLabel
	#
	$FolderStructureLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$FolderStructureLabel.ForeColor = [System.Drawing.Color]::Black 
	$FolderStructureLabel.Location = New-Object System.Drawing.Point(24, 36)
	$FolderStructureLabel.Name = 'FolderStructureLabel'
	$FolderStructureLabel.Size = New-Object System.Drawing.Size(300, 20)
	$FolderStructureLabel.TabIndex = 95
	$FolderStructureLabel.Text = 'Folder Structure'
	$FolderStructureLabel.TextAlign = 'MiddleLeft'
	$FolderStructureLabel.UseCompatibleTextRendering = $True
	#
	# MDTScriptGroup
	#
	$MDTScriptGroup.Controls.Add($MDTScriptTextBox)
	$MDTScriptGroup.Controls.Add($MDTLocationDesc)
	$MDTScriptGroup.Controls.Add($ImportMDTPSButton)
	$MDTScriptGroup.Controls.Add($ScriptLocationLabel)
	$MDTScriptGroup.Controls.Add($MDTScriptBrowseButton)
	$MDTScriptGroup.Anchor = 'Top, Left, Right'
	$MDTScriptGroup.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$MDTScriptGroup.ForeColor = [System.Drawing.Color]::Black 
	$MDTScriptGroup.Location = New-Object System.Drawing.Point(4, 12)
	$MDTScriptGroup.Name = 'MDTScriptGroup'
	$MDTScriptGroup.Size = New-Object System.Drawing.Size(717, 222)
	$MDTScriptGroup.TabIndex = 0
	$MDTScriptGroup.TabStop = $False
	$MDTScriptGroup.Text = 'MDT Script Path'
	$MDTScriptGroup.UseCompatibleTextRendering = $True
	#
	# MDTScriptTextBox
	#
	$MDTScriptTextBox.AutoCompleteMode = 'SuggestAppend'
	$MDTScriptTextBox.AutoCompleteSource = 'FileSystemDirectories'
	$MDTScriptTextBox.BackColor = [System.Drawing.Color]::White 
	$MDTScriptTextBox.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$MDTScriptTextBox.Location = New-Object System.Drawing.Point(23, 62)
	$MDTScriptTextBox.Margin = '2, 2, 2, 2'
	$MDTScriptTextBox.Name = 'MDTScriptTextBox'
	$MDTScriptTextBox.Size = New-Object System.Drawing.Size(411, 25)
	$MDTScriptTextBox.TabIndex = 91
	#
	# MDTLocationDesc
	#
	$MDTLocationDesc.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$MDTLocationDesc.BorderStyle = 'None'
	$MDTLocationDesc.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$MDTLocationDesc.ForeColor = [System.Drawing.Color]::Black 
	$MDTLocationDesc.Location = New-Object System.Drawing.Point(23, 114)
	$MDTLocationDesc.Multiline = $True
	$MDTLocationDesc.Name = 'MDTLocationDesc'
	$MDTLocationDesc.ReadOnly = $True
	$MDTLocationDesc.Size = New-Object System.Drawing.Size(688, 60)
	$MDTLocationDesc.TabIndex = 97
	$MDTLocationDesc.TabStop = $False
	$MDTLocationDesc.Text = 'Here you can specify an alternative location for the MDT installation. Set the location to the BIN subfolder and the script will use the MicrosoftDeploymentToolkit.psd1 contained within. Leaving blank uses the default C: value.
'
	#
	# ImportMDTPSButton
	#
	$ImportMDTPSButton.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$ImportMDTPSButton.FlatStyle = 'Popup'
	$ImportMDTPSButton.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$ImportMDTPSButton.ForeColor = [System.Drawing.Color]::White 
	$ImportMDTPSButton.Location = New-Object System.Drawing.Point(493, 61)
	$ImportMDTPSButton.Margin = '4, 3, 4, 3'
	$ImportMDTPSButton.Name = 'ImportMDTPSButton'
	$ImportMDTPSButton.Size = New-Object System.Drawing.Size(187, 27)
	$ImportMDTPSButton.TabIndex = 94
	$ImportMDTPSButton.Text = 'Import PS Module'
	$ImportMDTPSButton.UseCompatibleTextRendering = $True
	$ImportMDTPSButton.UseVisualStyleBackColor = $False
	$ImportMDTPSButton.add_Click($ImportMDTPSButton_Click)
	#
	# ScriptLocationLabel
	#
	$ScriptLocationLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$ScriptLocationLabel.ForeColor = [System.Drawing.Color]::Black 
	$ScriptLocationLabel.Location = New-Object System.Drawing.Point(23, 36)
	$ScriptLocationLabel.Name = 'ScriptLocationLabel'
	$ScriptLocationLabel.Size = New-Object System.Drawing.Size(411, 24)
	$ScriptLocationLabel.TabIndex = 93
	$ScriptLocationLabel.Text = 'Script Location
'
	$ScriptLocationLabel.TextAlign = 'MiddleLeft'
	$ScriptLocationLabel.UseCompatibleTextRendering = $True
	#
	# MDTScriptBrowseButton
	#
	$MDTScriptBrowseButton.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$MDTScriptBrowseButton.FlatStyle = 'Popup'
	$MDTScriptBrowseButton.ForeColor = [System.Drawing.Color]::White 
	$MDTScriptBrowseButton.Location = New-Object System.Drawing.Point(440, 61)
	$MDTScriptBrowseButton.Margin = '4, 4, 4, 4'
	$MDTScriptBrowseButton.Name = 'MDTScriptBrowseButton'
	$MDTScriptBrowseButton.Size = New-Object System.Drawing.Size(45, 27)
	$MDTScriptBrowseButton.TabIndex = 92
	$MDTScriptBrowseButton.Text = '...'
	$MDTScriptBrowseButton.UseCompatibleTextRendering = $True
	$MDTScriptBrowseButton.UseVisualStyleBackColor = $False
	$MDTScriptBrowseButton.add_Click($MDTScriptBrowseButton_Click)
	#
	# ConfigMgrDriverTab
	#
	$ConfigMgrDriverTab.Controls.Add($PkgMgmtTabLabel)
	$ConfigMgrDriverTab.Controls.Add($PkgMgmtIcon)
	$ConfigMgrDriverTab.Controls.Add($PackageUpdatePanel)
	$ConfigMgrDriverTab.Controls.Add($PackageGrid)
	$ConfigMgrDriverTab.Controls.Add($PackagePanel)
	$ConfigMgrDriverTab.BackColor = [System.Drawing.Color]::Gray 
	$ConfigMgrDriverTab.Location = New-Object System.Drawing.Point(4, 48)
	$ConfigMgrDriverTab.Name = 'ConfigMgrDriverTab'
	$ConfigMgrDriverTab.Size = New-Object System.Drawing.Size(1231, 564)
	$ConfigMgrDriverTab.TabIndex = 10
	$ConfigMgrDriverTab.Text = 'ConfigMgr Package Mgmt'
	#
	# PkgMgmtTabLabel
	#
	$PkgMgmtTabLabel.AutoSize = $True
	$PkgMgmtTabLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '16', [System.Drawing.FontStyle]'Bold')
	$PkgMgmtTabLabel.ForeColor = [System.Drawing.Color]::White 
	$PkgMgmtTabLabel.Location = New-Object System.Drawing.Point(90, 24)
	$PkgMgmtTabLabel.Name = 'PkgMgmtTabLabel'
	$PkgMgmtTabLabel.Size = New-Object System.Drawing.Size(355, 35)
	$PkgMgmtTabLabel.TabIndex = 99
	$PkgMgmtTabLabel.Text = 'ConfigMgr | Package Management'
	$PkgMgmtTabLabel.UseCompatibleTextRendering = $True
	#
	# PkgMgmtIcon
	#
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
AAEAAAD/////AQAAAAAAAAAMAgAAAFFTeXN0ZW0uRHJhd2luZywgVmVyc2lvbj00LjAuMC4wLCBD
dWx0dXJlPW5ldXRyYWwsIFB1YmxpY0tleVRva2VuPWIwM2Y1ZjdmMTFkNTBhM2EFAQAAABVTeXN0
ZW0uRHJhd2luZy5CaXRtYXABAAAABERhdGEHAgIAAAAJAwAAAA8DAAAAWQMAAAKJUE5HDQoaCgAA
AA1JSERSAAAAZAAAAGQIBgAAAHDilVQAAAAEZ0FNQQAAsY8L/GEFAAAACXBIWXMAAAsMAAALDAE/
QCLIAAAC+0lEQVR4Xu3crW5UURTF8SGIiorSBINB8AAUSYLDIDAEhSIYDC2QEIKAtyEYNIa3wIGv
IKGqQfCVwPA/UODkZu1bBi7dm5klfmbN5JzOWulHOk1n8/ncCpGh5ZGh5ZGh5ZGh5ZGh5ZGh5ZGh
5ZGh5ZGh5ZGh5ZGh5ZGh5ZGh5ZGh5ZGh5ZGh5ZFh5Oba7Bge4C3mE3iPpzir7ltFMoxQ3M5BkVN7
hx1156qRYYTSXnclTu0LVn4UGUYGBW7j9F84j8f4iB9nfsZdHFf3rwIZRrrimovqOYvinMv40J3b
PMcNXP1PXcCmer2HkWGES/rSJhmk4axbg7OXQfvB5yEW+myXYaS7rJlskIbzrmG/O39Z3FevNyLD
yOCiSQdpOHMTj/Dq4I5lsK9ea0SGkcFFkw+yLOjmet/V8PExMoz0l8CDBOjmRN/V8PExMoz0l8CD
BOjGg1RCNx6kErrxIJXQjQephG6ObJDdg0veYF09x771tNZ1taueE5FhhMM3cAmn1OP2S9fVhno8
IkPLI0PLI0PLI0PLI8PD8I1qHWds1B/9FCrDMVx0B8v4vsXUWkf38E/foGrvo7c/RlAfgGnbqsuI
DCMcvje4zA63p7qMyDAyuKj9dcg5k27jZ1fDHsfIMNJfAv8uK0A3/uViJXTjQSqhGw9SCd14kEro
xoNUQjcepBK68SCV0I0HqYRuPEgldONBKqEbD1IJ3XiQSujGg1RCNx6kErrxIJXQjQephG48SCV0
40EqoRsPUgndeJBK6MaDVEI3HqQSuvEgldCNB6mEbjxIJXTjQSqhGw9SCd14kEroxoNUQjcepBK6
8SCV0I0HqYRuPEgldONBKqEbD1IJ3Zzsuxo+PkaGkf4SPMEVk1o3RzLIi/4i+y0vVZcRGUY4vP0D
/U/dZTaudbXQl3YZjuGCLTxD+69y6oOw7920jrZUh2NkaHlkaHlkaHlkaHlkaHlkaHlkaHlkaHlk
aHlkaHlkaHlkaHlkaHlkaHlkaHlkaHlkaFnms68WxfyoJ3KVKAAAAABJRU5ErkJgggs='))
	#endregion
	$PkgMgmtIcon.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$PkgMgmtIcon.Location = New-Object System.Drawing.Point(20, 16)
	$PkgMgmtIcon.Name = 'PkgMgmtIcon'
	$PkgMgmtIcon.Size = New-Object System.Drawing.Size(50, 50)
	$PkgMgmtIcon.SizeMode = 'StretchImage'
	$PkgMgmtIcon.TabIndex = 98
	$PkgMgmtIcon.TabStop = $False
	#
	# PackageUpdatePanel
	#
	$PackageUpdatePanel.Controls.Add($PackageUpdateNotice)
	$PackageUpdatePanel.Anchor = 'Top, Bottom, Left, Right'
	$PackageUpdatePanel.Location = New-Object System.Drawing.Point(373, 226)
	$PackageUpdatePanel.Name = 'PackageUpdatePanel'
	$PackageUpdatePanel.Size = New-Object System.Drawing.Size(467, 152)
	$PackageUpdatePanel.TabIndex = 97
	$PackageUpdatePanel.Visible = $False
	#
	# PackageUpdateNotice
	#
	$PackageUpdateNotice.Anchor = 'Top, Bottom, Left, Right'
	$PackageUpdateNotice.AutoSize = $True
	$PackageUpdateNotice.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$PackageUpdateNotice.ForeColor = [System.Drawing.Color]::White 
	$PackageUpdateNotice.Location = New-Object System.Drawing.Point(164, 75)
	$PackageUpdateNotice.Name = 'PackageUpdateNotice'
	$PackageUpdateNotice.Size = New-Object System.Drawing.Size(156, 21)
	$PackageUpdateNotice.TabIndex = 0
	$PackageUpdateNotice.Text = 'Loading Package Details...'
	$PackageUpdateNotice.UseCompatibleTextRendering = $True
	$PackageUpdateNotice.Visible = $False
	#
	# PackageGrid
	#
	$PackageGrid.AllowUserToAddRows = $False
	$PackageGrid.AllowUserToDeleteRows = $False
	$PackageGrid.Anchor = 'Top, Bottom, Left, Right'
	$PackageGrid.BackgroundColor = [System.Drawing.Color]::White 
	$PackageGrid.BorderStyle = 'None'
	$PackageGrid.ColumnHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_1
	$PackageGrid.ColumnHeadersHeight = 30
	$PackageGrid.ColumnHeadersHeightSizeMode = 'DisableResizing'
	[void]$PackageGrid.Columns.Add($Selected)
	[void]$PackageGrid.Columns.Add($PackageName)
	[void]$PackageGrid.Columns.Add($PackageVersion)
	[void]$PackageGrid.Columns.Add($PackageID)
	[void]$PackageGrid.Columns.Add($Date)
	$PackageGrid.DefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_2
	$PackageGrid.GridColor = [System.Drawing.Color]::WhiteSmoke 
	$PackageGrid.Location = New-Object System.Drawing.Point(0, 152)
	$PackageGrid.Name = 'PackageGrid'
	$PackageGrid.RowHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_3
	$PackageGrid.RowHeadersVisible = $False
	$PackageGrid.RowTemplate.DefaultCellStyle.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$PackageGrid.RowTemplate.Height = 24
	$PackageGrid.SelectionMode = 'FullRowSelect'
	$PackageGrid.Size = New-Object System.Drawing.Size(1226, 367)
	$PackageGrid.TabIndex = 1
	$PackageGrid.add_CurrentCellDirtyStateChanged($PackageGrid_CurrentCellDirtyStateChanged)
	$PackageGrid.add_KeyPress($PackageGrid_KeyPress)
	#
	# PackagePanel
	#
	$PackagePanel.Controls.Add($PackageTypeLabel)
	$PackagePanel.Controls.Add($DeploymentStateCombo)
	$PackagePanel.Controls.Add($DeploymentStateLabel)
	$PackagePanel.Controls.Add($SelectNoneButton)
	$PackagePanel.Controls.Add($PackageTypeCombo)
	$PackagePanel.Controls.Add($SelectAllButton)
	$PackagePanel.Controls.Add($ConfigMgrPkgActionCombo)
	$PackagePanel.Controls.Add($ActionLabel)
	$PackagePanel.Anchor = 'Top, Bottom, Left, Right'
	$PackagePanel.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$PackagePanel.Location = New-Object System.Drawing.Point(0, 83)
	$PackagePanel.Name = 'PackagePanel'
	$PackagePanel.Size = New-Object System.Drawing.Size(1229, 481)
	$PackagePanel.TabIndex = 100
	#
	# PackageTypeLabel
	#
	$PackageTypeLabel.AutoSize = $True
	$PackageTypeLabel.BackColor = [System.Drawing.Color]::Transparent 
	$PackageTypeLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$PackageTypeLabel.ForeColor = [System.Drawing.Color]::Black 
	$PackageTypeLabel.Location = New-Object System.Drawing.Point(24, 27)
	$PackageTypeLabel.Margin = '4, 0, 4, 0'
	$PackageTypeLabel.Name = 'PackageTypeLabel'
	$PackageTypeLabel.Size = New-Object System.Drawing.Size(84, 21)
	$PackageTypeLabel.TabIndex = 29
	$PackageTypeLabel.Text = 'Package Type'
	$PackageTypeLabel.UseCompatibleTextRendering = $True
	#
	# DeploymentStateCombo
	#
	$DeploymentStateCombo.BackColor = [System.Drawing.Color]::White 
	$DeploymentStateCombo.DropDownStyle = 'DropDownList'
	$DeploymentStateCombo.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$DeploymentStateCombo.FormattingEnabled = $True
	[void]$DeploymentStateCombo.Items.Add('Production')
	[void]$DeploymentStateCombo.Items.Add('Pilot')
	[void]$DeploymentStateCombo.Items.Add('Retired')
	$DeploymentStateCombo.Location = New-Object System.Drawing.Point(611, 24)
	$DeploymentStateCombo.Name = 'DeploymentStateCombo'
	$DeploymentStateCombo.Size = New-Object System.Drawing.Size(278, 23)
	$DeploymentStateCombo.TabIndex = 0
	$DeploymentStateCombo.add_SelectedIndexChanged($DeploymentStateCombo_SelectedIndexChanged)
	#
	# DeploymentStateLabel
	#
	$DeploymentStateLabel.AutoSize = $True
	$DeploymentStateLabel.BackColor = [System.Drawing.Color]::Transparent 
	$DeploymentStateLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$DeploymentStateLabel.ForeColor = [System.Drawing.Color]::Black 
	$DeploymentStateLabel.Location = New-Object System.Drawing.Point(440, 27)
	$DeploymentStateLabel.Margin = '4, 0, 4, 0'
	$DeploymentStateLabel.Name = 'DeploymentStateLabel'
	$DeploymentStateLabel.Size = New-Object System.Drawing.Size(109, 21)
	$DeploymentStateLabel.TabIndex = 27
	$DeploymentStateLabel.Text = 'Deployment State'
	$DeploymentStateLabel.UseCompatibleTextRendering = $True
	#
	# SelectNoneButton
	#
	$SelectNoneButton.Anchor = 'Bottom, Left'
	$SelectNoneButton.BackColor = [System.Drawing.Color]::Gray 
	$SelectNoneButton.FlatStyle = 'Flat'
	$SelectNoneButton.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$SelectNoneButton.ForeColor = [System.Drawing.Color]::White 
	$SelectNoneButton.Location = New-Object System.Drawing.Point(215, 442)
	$SelectNoneButton.Margin = '4, 3, 4, 3'
	$SelectNoneButton.Name = 'SelectNoneButton'
	$SelectNoneButton.Size = New-Object System.Drawing.Size(187, 30)
	$SelectNoneButton.TabIndex = 96
	$SelectNoneButton.Text = 'Select None'
	$SelectNoneButton.UseCompatibleTextRendering = $True
	$SelectNoneButton.UseVisualStyleBackColor = $False
	$SelectNoneButton.add_Click($SelectNoneButton_Click)
	#
	# PackageTypeCombo
	#
	$PackageTypeCombo.BackColor = [System.Drawing.Color]::White 
	$PackageTypeCombo.DropDownStyle = 'DropDownList'
	$PackageTypeCombo.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$PackageTypeCombo.FormattingEnabled = $True
	[void]$PackageTypeCombo.Items.Add('Drivers')
	[void]$PackageTypeCombo.Items.Add('BIOS Update')
	[void]$PackageTypeCombo.Items.Add('SoftPaqs')
	$PackageTypeCombo.Location = New-Object System.Drawing.Point(164, 24)
	$PackageTypeCombo.Name = 'PackageTypeCombo'
	$PackageTypeCombo.Size = New-Object System.Drawing.Size(230, 23)
	$PackageTypeCombo.TabIndex = 28
	$PackageTypeCombo.add_SelectedIndexChanged($PackageTypeCombo_SelectedIndexChanged)
	#
	# SelectAllButton
	#
	$SelectAllButton.Anchor = 'Bottom, Left'
	$SelectAllButton.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$SelectAllButton.FlatStyle = 'Flat'
	$SelectAllButton.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$SelectAllButton.ForeColor = [System.Drawing.Color]::White 
	$SelectAllButton.Location = New-Object System.Drawing.Point(20, 442)
	$SelectAllButton.Margin = '4, 3, 4, 3'
	$SelectAllButton.Name = 'SelectAllButton'
	$SelectAllButton.Size = New-Object System.Drawing.Size(187, 30)
	$SelectAllButton.TabIndex = 95
	$SelectAllButton.Text = 'Select All'
	$SelectAllButton.UseCompatibleTextRendering = $True
	$SelectAllButton.UseVisualStyleBackColor = $False
	$SelectAllButton.add_Click($SelectAllButton_Click)
	#
	# ConfigMgrPkgActionCombo
	#
	$ConfigMgrPkgActionCombo.Anchor = 'Bottom, Left'
	$ConfigMgrPkgActionCombo.BackColor = [System.Drawing.Color]::White 
	$ConfigMgrPkgActionCombo.DropDownStyle = 'DropDownList'
	$ConfigMgrPkgActionCombo.Font = [System.Drawing.Font]::new('Segoe UI', '9')
	$ConfigMgrPkgActionCombo.FormattingEnabled = $True
	[void]$ConfigMgrPkgActionCombo.Items.Add('Move to Production')
	[void]$ConfigMgrPkgActionCombo.Items.Add('Move to Pilot')
	[void]$ConfigMgrPkgActionCombo.Items.Add('Mark as Retired')
	[void]$ConfigMgrPkgActionCombo.Items.Add('Move to Windows 10 2004')
	[void]$ConfigMgrPkgActionCombo.Items.Add('Move to Windows 10 1909')
	[void]$ConfigMgrPkgActionCombo.Items.Add('Move to Windows 10 1903')
	[void]$ConfigMgrPkgActionCombo.Items.Add('Move to Windows 10 1809')
	[void]$ConfigMgrPkgActionCombo.Items.Add('Move to Windows 10 1803')
	[void]$ConfigMgrPkgActionCombo.Items.Add('Move to Windows 10 1709')
	[void]$ConfigMgrPkgActionCombo.Items.Add('Move to Windows 10 1703')
	[void]$ConfigMgrPkgActionCombo.Items.Add('Move to Windows 10 1607')
	$ConfigMgrPkgActionCombo.Location = New-Object System.Drawing.Point(848, 447)
	$ConfigMgrPkgActionCombo.Name = 'ConfigMgrPkgActionCombo'
	$ConfigMgrPkgActionCombo.Size = New-Object System.Drawing.Size(278, 23)
	$ConfigMgrPkgActionCombo.TabIndex = 30
	$ConfigMgrPkgActionCombo.add_SelectedIndexChanged($ConfigMgrPkgActionCombo_SelectedIndexChanged)
	#
	# ActionLabel
	#
	$ActionLabel.Anchor = 'Bottom, Left'
	$ActionLabel.AutoSize = $True
	$ActionLabel.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$ActionLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$ActionLabel.ForeColor = [System.Drawing.Color]::Black 
	$ActionLabel.Location = New-Object System.Drawing.Point(775, 450)
	$ActionLabel.Margin = '4, 0, 4, 0'
	$ActionLabel.Name = 'ActionLabel'
	$ActionLabel.Size = New-Object System.Drawing.Size(48, 21)
	$ActionLabel.TabIndex = 31
	$ActionLabel.Text = 'Actions'
	$ActionLabel.UseCompatibleTextRendering = $True
	#
	# ConfigWSDiagTab
	#
	$ConfigWSDiagTab.Controls.Add($WebDiagsTabLabel)
	$ConfigWSDiagTab.Controls.Add($WebDiagsIcon)
	$ConfigWSDiagTab.Controls.Add($WebServiceDataGrid)
	$ConfigWSDiagTab.Controls.Add($WebDiagsPanel)
	$ConfigWSDiagTab.BackColor = [System.Drawing.Color]::Gray 
	$ConfigWSDiagTab.Location = New-Object System.Drawing.Point(4, 48)
	$ConfigWSDiagTab.Name = 'ConfigWSDiagTab'
	$ConfigWSDiagTab.Size = New-Object System.Drawing.Size(1231, 564)
	$ConfigWSDiagTab.TabIndex = 13
	$ConfigWSDiagTab.Text = 'ConfigMgr Web Service Diags'
	#
	# WebDiagsTabLabel
	#
	$WebDiagsTabLabel.AutoSize = $True
	$WebDiagsTabLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '16', [System.Drawing.FontStyle]'Bold')
	$WebDiagsTabLabel.ForeColor = [System.Drawing.Color]::White 
	$WebDiagsTabLabel.Location = New-Object System.Drawing.Point(90, 24)
	$WebDiagsTabLabel.Name = 'WebDiagsTabLabel'
	$WebDiagsTabLabel.Size = New-Object System.Drawing.Size(378, 35)
	$WebDiagsTabLabel.TabIndex = 103
	$WebDiagsTabLabel.Text = 'ConfigMgr | Web Service Diagnostics'
	$WebDiagsTabLabel.UseCompatibleTextRendering = $True
	#
	# WebDiagsIcon
	#
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
AAEAAAD/////AQAAAAAAAAAMAgAAAFFTeXN0ZW0uRHJhd2luZywgVmVyc2lvbj00LjAuMC4wLCBD
dWx0dXJlPW5ldXRyYWwsIFB1YmxpY0tleVRva2VuPWIwM2Y1ZjdmMTFkNTBhM2EFAQAAABVTeXN0
ZW0uRHJhd2luZy5CaXRtYXABAAAABERhdGEHAgIAAAAJAwAAAA8DAAAADgIAAAKJUE5HDQoaCgAA
AA1JSERSAAAAMgAAADIIBgAAAB4/iLEAAAAEZ0FNQQAAsY8L/GEFAAAACXBIWXMAAAsMAAALDAE/
QCLIAAABsElEQVRoQ+3WMUoEQRQE0NXEFQMxMd+LqOAlzIw8hIHGnsTEVBFBERZBxNQDKMYeQBDG
KvkDMlVJ4zTTLR28oKv/jPWRXZ11Xfcv2LBGNqyRDWtkwxrZkI7WZqfQFebYdSUb4oHDwQtKcuA6
S0AYPouHdmBRiD34WWbYlyQgDPeLLNz9FNglOuGo9xIQhtsiubBLdMJR7yUgDLdFcmGX6ISj3ktA
GG6L5MIu0QlHvZeAMNwWyYVdohOOei8BYbgtkgu7RCcc9V4CwnBbJBd2iU446r0EhOG2SC7sEp1w
1HsJCMNtkVzYJTrhqPcSEIbbIrmwS3TCUe8lIAy3RXJhl+iEo95LQBhui+TCLtEJR72XgDB8Eg9d
w3khboCdLlxnCQjD27CEr3i4BOxyB1uuswS/4aHVkriOPRvWyIY1smEq/No34AoeEl3C3L0zlQ1T
ocwmvMC7wQ/p5yDrPcO6e2cqG44JRV/h0d2NyYZjaosksuGYJl0EP5h/gOYjeYOnQfYXK66zBITh
W3D/JpTg3nWWgDC8C/zKdC+a0gfsu84S1MqGNbJhjWxYIxvWp5t9A9b2NCA0eqsxAAAAAElFTkSu
QmCCCw=='))
	#endregion
	$WebDiagsIcon.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$WebDiagsIcon.Location = New-Object System.Drawing.Point(20, 16)
	$WebDiagsIcon.Name = 'WebDiagsIcon'
	$WebDiagsIcon.Size = New-Object System.Drawing.Size(50, 50)
	$WebDiagsIcon.SizeMode = 'StretchImage'
	$WebDiagsIcon.TabIndex = 102
	$WebDiagsIcon.TabStop = $False
	#
	# WebServiceDataGrid
	#
	$WebServiceDataGrid.AllowUserToAddRows = $False
	$WebServiceDataGrid.AllowUserToDeleteRows = $False
	$WebServiceDataGrid.Anchor = 'Top, Bottom, Left, Right'
	$WebServiceDataGrid.BackgroundColor = [System.Drawing.Color]::White 
	$WebServiceDataGrid.BorderStyle = 'None'
	$WebServiceDataGrid.ColumnHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_1
	$WebServiceDataGrid.ColumnHeadersHeight = 30
	$WebServiceDataGrid.ColumnHeadersHeightSizeMode = 'DisableResizing'
	[void]$WebServiceDataGrid.Columns.Add($WebServicePackageName)
	[void]$WebServiceDataGrid.Columns.Add($PackageVersionDetails)
	[void]$WebServiceDataGrid.Columns.Add($WebServicePackageID)
	$WebServiceDataGrid.DefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_2
	$WebServiceDataGrid.GridColor = [System.Drawing.Color]::WhiteSmoke 
	$WebServiceDataGrid.Location = New-Object System.Drawing.Point(377, 282)
	$WebServiceDataGrid.Name = 'WebServiceDataGrid'
	$WebServiceDataGrid.RowHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_3
	$WebServiceDataGrid.RowHeadersVisible = $False
	$WebServiceDataGrid.RowTemplate.DefaultCellStyle.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$WebServiceDataGrid.RowTemplate.Height = 24
	$WebServiceDataGrid.Size = New-Object System.Drawing.Size(852, 303)
	$WebServiceDataGrid.TabIndex = 75
	#
	# WebDiagsPanel
	#
	$WebDiagsPanel.Controls.Add($ConfigMgrWebSvcLabel)
	$WebDiagsPanel.Controls.Add($WebServiceVersion)
	$WebDiagsPanel.Controls.Add($WebSvcDesc)
	$WebDiagsPanel.Controls.Add($WebServiceVersionLabel)
	$WebDiagsPanel.Controls.Add($ConnectWebServiceButton)
	$WebDiagsPanel.Controls.Add($WebServiceStatusDescription)
	$WebDiagsPanel.Controls.Add($SecretKey)
	$WebDiagsPanel.Controls.Add($ConfigMgrWebServuceULabel)
	$WebDiagsPanel.Controls.Add($StatusDescriptionLabel)
	$WebDiagsPanel.Controls.Add($SecretKeyLabel)
	$WebDiagsPanel.Controls.Add($StatusCodeLabel)
	$WebDiagsPanel.Controls.Add($ConfigMgrWebURL)
	$WebDiagsPanel.Controls.Add($BIOSPackageCount)
	$WebDiagsPanel.Controls.Add($WebServiceResponseTime)
	$WebDiagsPanel.Controls.Add($ResponseTimeLabel)
	$WebDiagsPanel.Controls.Add($DriverPackageCount)
	$WebDiagsPanel.Controls.Add($BIOSPackageCountLabel)
	$WebDiagsPanel.Controls.Add($WebServiceStatusCode)
	$WebDiagsPanel.Controls.Add($DriverPackageCountLabel)
	$WebDiagsPanel.Anchor = 'Top, Bottom, Left, Right'
	$WebDiagsPanel.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$WebDiagsPanel.Location = New-Object System.Drawing.Point(0, 83)
	$WebDiagsPanel.Name = 'WebDiagsPanel'
	$WebDiagsPanel.Size = New-Object System.Drawing.Size(1575, 481)
	$WebDiagsPanel.TabIndex = 101
	#
	# ConfigMgrWebSvcLabel
	#
	$ConfigMgrWebSvcLabel.AutoSize = $True
	$ConfigMgrWebSvcLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$ConfigMgrWebSvcLabel.ForeColor = [System.Drawing.Color]::Black 
	$ConfigMgrWebSvcLabel.Location = New-Object System.Drawing.Point(42, 199)
	$ConfigMgrWebSvcLabel.Name = 'ConfigMgrWebSvcLabel'
	$ConfigMgrWebSvcLabel.Size = New-Object System.Drawing.Size(210, 22)
	$ConfigMgrWebSvcLabel.TabIndex = 99
	$ConfigMgrWebSvcLabel.Text = 'ConfigMgr Web Service - Details'
	$ConfigMgrWebSvcLabel.UseCompatibleTextRendering = $True
	#
	# WebServiceVersion
	#
	$WebServiceVersion.AutoSize = $True
	$WebServiceVersion.BackColor = [System.Drawing.Color]::Transparent 
	$WebServiceVersion.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$WebServiceVersion.ForeColor = [System.Drawing.Color]::Black 
	$WebServiceVersion.Location = New-Object System.Drawing.Point(253, 241)
	$WebServiceVersion.Margin = '4, 0, 4, 0'
	$WebServiceVersion.Name = 'WebServiceVersion'
	$WebServiceVersion.Size = New-Object System.Drawing.Size(28, 22)
	$WebServiceVersion.TabIndex = 81
	$WebServiceVersion.Text = '- - -'
	$WebServiceVersion.UseCompatibleTextRendering = $True
	#
	# WebSvcDesc
	#
	$WebSvcDesc.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$WebSvcDesc.BorderStyle = 'None'
	$WebSvcDesc.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$WebSvcDesc.ForeColor = [System.Drawing.Color]::Black 
	$WebSvcDesc.Location = New-Object System.Drawing.Point(42, 40)
	$WebSvcDesc.Multiline = $True
	$WebSvcDesc.Name = 'WebSvcDesc'
	$WebSvcDesc.ReadOnly = $True
	$WebSvcDesc.Size = New-Object System.Drawing.Size(607, 110)
	$WebSvcDesc.TabIndex = 60
	$WebSvcDesc.TabStop = $False
	$WebSvcDesc.Text = 'Here you can test obtaining package information from the ConfigMgr Web Service, used to match driver and BIOS downloads.

Enter the ConfigMgr web service URL and secret key, then click on the "Connect ConfigMgr Web Service" button. The results are displayed in the below section.'
	#
	# WebServiceVersionLabel
	#
	$WebServiceVersionLabel.AutoSize = $True
	$WebServiceVersionLabel.BackColor = [System.Drawing.Color]::Transparent 
	$WebServiceVersionLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$WebServiceVersionLabel.ForeColor = [System.Drawing.Color]::Black 
	$WebServiceVersionLabel.Location = New-Object System.Drawing.Point(42, 241)
	$WebServiceVersionLabel.Margin = '4, 0, 4, 0'
	$WebServiceVersionLabel.Name = 'WebServiceVersionLabel'
	$WebServiceVersionLabel.Size = New-Object System.Drawing.Size(125, 22)
	$WebServiceVersionLabel.TabIndex = 80
	$WebServiceVersionLabel.Text = 'WebService Version:'
	$WebServiceVersionLabel.UseCompatibleTextRendering = $True
	#
	# ConnectWebServiceButton
	#
	$ConnectWebServiceButton.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$ConnectWebServiceButton.FlatAppearance.BorderSize = 0
	$ConnectWebServiceButton.FlatStyle = 'Flat'
	$ConnectWebServiceButton.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$ConnectWebServiceButton.ForeColor = [System.Drawing.Color]::White 
	$ConnectWebServiceButton.Location = New-Object System.Drawing.Point(859, 127)
	$ConnectWebServiceButton.Margin = '4, 3, 4, 3'
	$ConnectWebServiceButton.Name = 'ConnectWebServiceButton'
	$ConnectWebServiceButton.Size = New-Object System.Drawing.Size(312, 30)
	$ConnectWebServiceButton.TabIndex = 44
	$ConnectWebServiceButton.Text = 'Connect ConfigMgr Web Service'
	$ConnectWebServiceButton.UseCompatibleTextRendering = $True
	$ConnectWebServiceButton.UseVisualStyleBackColor = $False
	$ConnectWebServiceButton.add_Click($ConnectWebServiceButton_Click)
	#
	# WebServiceStatusDescription
	#
	$WebServiceStatusDescription.AutoSize = $True
	$WebServiceStatusDescription.BackColor = [System.Drawing.Color]::Transparent 
	$WebServiceStatusDescription.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$WebServiceStatusDescription.ForeColor = [System.Drawing.Color]::Black 
	$WebServiceStatusDescription.Location = New-Object System.Drawing.Point(253, 319)
	$WebServiceStatusDescription.Margin = '4, 0, 4, 0'
	$WebServiceStatusDescription.Name = 'WebServiceStatusDescription'
	$WebServiceStatusDescription.Size = New-Object System.Drawing.Size(28, 22)
	$WebServiceStatusDescription.TabIndex = 79
	$WebServiceStatusDescription.Text = '- - -'
	$WebServiceStatusDescription.UseCompatibleTextRendering = $True
	#
	# SecretKey
	#
	$SecretKey.BackColor = [System.Drawing.Color]::White 
	$SecretKey.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$SecretKey.ForeColor = [System.Drawing.Color]::Black 
	$SecretKey.Location = New-Object System.Drawing.Point(859, 82)
	$SecretKey.Margin = '4, 3, 4, 3'
	$SecretKey.Name = 'SecretKey'
	$SecretKey.Size = New-Object System.Drawing.Size(312, 23)
	$SecretKey.TabIndex = 63
	#
	# ConfigMgrWebServuceULabel
	#
	$ConfigMgrWebServuceULabel.AutoSize = $True
	$ConfigMgrWebServuceULabel.BackColor = [System.Drawing.Color]::Transparent 
	$ConfigMgrWebServuceULabel.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$ConfigMgrWebServuceULabel.ForeColor = [System.Drawing.Color]::Black 
	$ConfigMgrWebServuceULabel.Location = New-Object System.Drawing.Point(722, 42)
	$ConfigMgrWebServuceULabel.Margin = '4, 0, 4, 0'
	$ConfigMgrWebServuceULabel.Name = 'ConfigMgrWebServuceULabel'
	$ConfigMgrWebServuceULabel.Size = New-Object System.Drawing.Size(103, 21)
	$ConfigMgrWebServuceULabel.TabIndex = 62
	$ConfigMgrWebServuceULabel.Text = 'Web Service URL'
	$ConfigMgrWebServuceULabel.UseCompatibleTextRendering = $True
	#
	# StatusDescriptionLabel
	#
	$StatusDescriptionLabel.AutoSize = $True
	$StatusDescriptionLabel.BackColor = [System.Drawing.Color]::Transparent 
	$StatusDescriptionLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$StatusDescriptionLabel.ForeColor = [System.Drawing.Color]::Black 
	$StatusDescriptionLabel.Location = New-Object System.Drawing.Point(42, 319)
	$StatusDescriptionLabel.Margin = '4, 0, 4, 0'
	$StatusDescriptionLabel.Name = 'StatusDescriptionLabel'
	$StatusDescriptionLabel.Size = New-Object System.Drawing.Size(115, 22)
	$StatusDescriptionLabel.TabIndex = 78
	$StatusDescriptionLabel.Text = 'Status Description:'
	$StatusDescriptionLabel.UseCompatibleTextRendering = $True
	#
	# SecretKeyLabel
	#
	$SecretKeyLabel.AutoSize = $True
	$SecretKeyLabel.BackColor = [System.Drawing.Color]::Transparent 
	$SecretKeyLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$SecretKeyLabel.ForeColor = [System.Drawing.Color]::Black 
	$SecretKeyLabel.Location = New-Object System.Drawing.Point(760, 82)
	$SecretKeyLabel.Margin = '4, 0, 4, 0'
	$SecretKeyLabel.Name = 'SecretKeyLabel'
	$SecretKeyLabel.Size = New-Object System.Drawing.Size(65, 21)
	$SecretKeyLabel.TabIndex = 64
	$SecretKeyLabel.Text = 'Secret Key'
	$SecretKeyLabel.UseCompatibleTextRendering = $True
	#
	# StatusCodeLabel
	#
	$StatusCodeLabel.AutoSize = $True
	$StatusCodeLabel.BackColor = [System.Drawing.Color]::Transparent 
	$StatusCodeLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$StatusCodeLabel.ForeColor = [System.Drawing.Color]::Black 
	$StatusCodeLabel.Location = New-Object System.Drawing.Point(42, 280)
	$StatusCodeLabel.Margin = '4, 0, 4, 0'
	$StatusCodeLabel.Name = 'StatusCodeLabel'
	$StatusCodeLabel.Size = New-Object System.Drawing.Size(79, 22)
	$StatusCodeLabel.TabIndex = 65
	$StatusCodeLabel.Text = 'Status Code:'
	$StatusCodeLabel.UseCompatibleTextRendering = $True
	#
	# ConfigMgrWebURL
	#
	$ConfigMgrWebURL.BackColor = [System.Drawing.Color]::White 
	$ConfigMgrWebURL.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$ConfigMgrWebURL.ForeColor = [System.Drawing.Color]::Black 
	$ConfigMgrWebURL.Location = New-Object System.Drawing.Point(859, 40)
	$ConfigMgrWebURL.Margin = '4, 3, 4, 3'
	$ConfigMgrWebURL.Name = 'ConfigMgrWebURL'
	$ConfigMgrWebURL.Size = New-Object System.Drawing.Size(311, 23)
	$ConfigMgrWebURL.TabIndex = 61
	#
	# BIOSPackageCount
	#
	$BIOSPackageCount.AutoSize = $True
	$BIOSPackageCount.BackColor = [System.Drawing.Color]::Transparent 
	$BIOSPackageCount.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$BIOSPackageCount.ForeColor = [System.Drawing.Color]::Black 
	$BIOSPackageCount.Location = New-Object System.Drawing.Point(253, 436)
	$BIOSPackageCount.Margin = '4, 0, 4, 0'
	$BIOSPackageCount.Name = 'BIOSPackageCount'
	$BIOSPackageCount.Size = New-Object System.Drawing.Size(28, 22)
	$BIOSPackageCount.TabIndex = 77
	$BIOSPackageCount.Text = '- - -'
	$BIOSPackageCount.UseCompatibleTextRendering = $True
	#
	# WebServiceResponseTime
	#
	$WebServiceResponseTime.AutoSize = $True
	$WebServiceResponseTime.BackColor = [System.Drawing.Color]::Transparent 
	$WebServiceResponseTime.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$WebServiceResponseTime.ForeColor = [System.Drawing.Color]::Black 
	$WebServiceResponseTime.Location = New-Object System.Drawing.Point(253, 358)
	$WebServiceResponseTime.Margin = '4, 0, 4, 0'
	$WebServiceResponseTime.Name = 'WebServiceResponseTime'
	$WebServiceResponseTime.Size = New-Object System.Drawing.Size(28, 22)
	$WebServiceResponseTime.TabIndex = 73
	$WebServiceResponseTime.Text = '- - -'
	$WebServiceResponseTime.UseCompatibleTextRendering = $True
	#
	# ResponseTimeLabel
	#
	$ResponseTimeLabel.AutoSize = $True
	$ResponseTimeLabel.BackColor = [System.Drawing.Color]::Transparent 
	$ResponseTimeLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$ResponseTimeLabel.ForeColor = [System.Drawing.Color]::Black 
	$ResponseTimeLabel.Location = New-Object System.Drawing.Point(42, 358)
	$ResponseTimeLabel.Margin = '4, 0, 4, 0'
	$ResponseTimeLabel.Name = 'ResponseTimeLabel'
	$ResponseTimeLabel.Size = New-Object System.Drawing.Size(97, 22)
	$ResponseTimeLabel.TabIndex = 70
	$ResponseTimeLabel.Text = 'Response Time:'
	$ResponseTimeLabel.UseCompatibleTextRendering = $True
	#
	# DriverPackageCount
	#
	$DriverPackageCount.AutoSize = $True
	$DriverPackageCount.BackColor = [System.Drawing.Color]::Transparent 
	$DriverPackageCount.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$DriverPackageCount.ForeColor = [System.Drawing.Color]::Black 
	$DriverPackageCount.Location = New-Object System.Drawing.Point(253, 397)
	$DriverPackageCount.Margin = '4, 0, 4, 0'
	$DriverPackageCount.Name = 'DriverPackageCount'
	$DriverPackageCount.Size = New-Object System.Drawing.Size(28, 22)
	$DriverPackageCount.TabIndex = 74
	$DriverPackageCount.Text = '- - -'
	$DriverPackageCount.UseCompatibleTextRendering = $True
	#
	# BIOSPackageCountLabel
	#
	$BIOSPackageCountLabel.AutoSize = $True
	$BIOSPackageCountLabel.BackColor = [System.Drawing.Color]::Transparent 
	$BIOSPackageCountLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$BIOSPackageCountLabel.ForeColor = [System.Drawing.Color]::Black 
	$BIOSPackageCountLabel.Location = New-Object System.Drawing.Point(42, 436)
	$BIOSPackageCountLabel.Margin = '4, 0, 4, 0'
	$BIOSPackageCountLabel.Name = 'BIOSPackageCountLabel'
	$BIOSPackageCountLabel.Size = New-Object System.Drawing.Size(128, 22)
	$BIOSPackageCountLabel.TabIndex = 76
	$BIOSPackageCountLabel.Text = 'BIOS Package Count:'
	$BIOSPackageCountLabel.UseCompatibleTextRendering = $True
	#
	# WebServiceStatusCode
	#
	$WebServiceStatusCode.AutoSize = $True
	$WebServiceStatusCode.BackColor = [System.Drawing.Color]::Transparent 
	$WebServiceStatusCode.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$WebServiceStatusCode.ForeColor = [System.Drawing.Color]::Black 
	$WebServiceStatusCode.Location = New-Object System.Drawing.Point(253, 280)
	$WebServiceStatusCode.Margin = '4, 0, 4, 0'
	$WebServiceStatusCode.Name = 'WebServiceStatusCode'
	$WebServiceStatusCode.Size = New-Object System.Drawing.Size(28, 22)
	$WebServiceStatusCode.TabIndex = 72
	$WebServiceStatusCode.Text = '- - -'
	$WebServiceStatusCode.UseCompatibleTextRendering = $True
	#
	# DriverPackageCountLabel
	#
	$DriverPackageCountLabel.AutoSize = $True
	$DriverPackageCountLabel.BackColor = [System.Drawing.Color]::Transparent 
	$DriverPackageCountLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$DriverPackageCountLabel.ForeColor = [System.Drawing.Color]::Black 
	$DriverPackageCountLabel.Location = New-Object System.Drawing.Point(42, 397)
	$DriverPackageCountLabel.Margin = '4, 0, 4, 0'
	$DriverPackageCountLabel.Name = 'DriverPackageCountLabel'
	$DriverPackageCountLabel.Size = New-Object System.Drawing.Size(135, 22)
	$DriverPackageCountLabel.TabIndex = 71
	$DriverPackageCountLabel.Text = 'Driver Package Count:'
	$DriverPackageCountLabel.UseCompatibleTextRendering = $True
	#
	# CustPkgTab
	#
	$CustPkgTab.Controls.Add($PkgImporting)
	$CustPkgTab.Controls.Add($CustPkgIcon)
	$CustPkgTab.Controls.Add($CustomPkgTabLabel)
	$CustPkgTab.Controls.Add($CustomPkgDataGrid)
	$CustPkgTab.Controls.Add($CustomPkgPanel)
	$CustPkgTab.BackColor = [System.Drawing.Color]::Gray 
	$CustPkgTab.Location = New-Object System.Drawing.Point(4, 48)
	$CustPkgTab.Name = 'CustPkgTab'
	$CustPkgTab.Size = New-Object System.Drawing.Size(1231, 564)
	$CustPkgTab.TabIndex = 12
	$CustPkgTab.Text = 'Custom Package Creation'
	#
	# PkgImporting
	#
	$PkgImporting.Controls.Add($PkgImportingText)
	$PkgImporting.Controls.Add($label1)
	$PkgImporting.Anchor = 'Top, Bottom, Left, Right'
	$PkgImporting.BackColor = [System.Drawing.Color]::Maroon 
	$PkgImporting.Cursor = 'WaitCursor'
	$PkgImporting.Location = New-Object System.Drawing.Point(360, 275)
	$PkgImporting.Name = 'PkgImporting'
	$PkgImporting.Size = New-Object System.Drawing.Size(507, 125)
	$PkgImporting.TabIndex = 100
	$PkgImporting.Visible = $False
	#
	# PkgImportingText
	#
	$PkgImportingText.Anchor = 'Top, Left, Right'
	$PkgImportingText.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$PkgImportingText.ForeColor = [System.Drawing.Color]::White 
	$PkgImportingText.Location = New-Object System.Drawing.Point(0, 0)
	$PkgImportingText.Name = 'PkgImportingText'
	$PkgImportingText.Size = New-Object System.Drawing.Size(507, 127)
	$PkgImportingText.TabIndex = 0
	$PkgImportingText.Text = 'Importing CSV File.. Please Wait..'
	$PkgImportingText.TextAlign = 'MiddleCenter'
	$PkgImportingText.UseCompatibleTextRendering = $True
	$PkgImportingText.Visible = $False
	#
	# label1
	#
	$label1.Anchor = 'Top, Bottom, Left, Right'
	$label1.AutoSize = $True
	$label1.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$label1.ForeColor = [System.Drawing.Color]::White 
	$label1.Location = New-Object System.Drawing.Point(106, 42)
	$label1.Name = 'label1'
	$label1.Size = New-Object System.Drawing.Size(0, 18)
	$label1.TabIndex = 1
	$label1.UseCompatibleTextRendering = $True
	$label1.Visible = $False
	#
	# CustPkgIcon
	#
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
AAEAAAD/////AQAAAAAAAAAMAgAAAFFTeXN0ZW0uRHJhd2luZywgVmVyc2lvbj00LjAuMC4wLCBD
dWx0dXJlPW5ldXRyYWwsIFB1YmxpY0tleVRva2VuPWIwM2Y1ZjdmMTFkNTBhM2EFAQAAABVTeXN0
ZW0uRHJhd2luZy5CaXRtYXABAAAABERhdGEHAgIAAAAJAwAAAA8DAAAAOwMAAAKJUE5HDQoaCgAA
AA1JSERSAAAAMgAAADIIBgAAAB4/iLEAAAAEZ0FNQQAAsY8L/GEFAAAACXBIWXMAAAsMAAALDAE/
QCLIAAAC3UlEQVRoQ+3ZT4iNYRTH8fkXSs3WAikWk7KglIaF7CYSpaRspGYjsRIWmpUmisWUEpPC
go2sJBtlgSQLNsoKCynEgjL+zPX91Xnq7b2/eea9muv26l186s45z3POc+69c/+9fa1W679gg3Vk
g3Vkg3Vkg3Vkg3Vkg1WML+5bg1uYQQuzeI5dbn0Ra7bHWu3R3h9QrRG3vgobnA8N1+ETdIj7mMRV
fIUON4UBs28A52KN1mrPadzDb3zBhvK+Kmwwh0b9eIaf2FPKrcQjaMCpYi7yGkK5J1hVyu2GHt2X
GCrmqrDBHJqMQoe5MEd+GGmYA4X4PuiR0BDDxT2FNeehfdtcPscGc2gyHs3GXF7ILcN76KmyIv7+
iA9Y7vYIua1Q7aMun2ODOTQ5GM12unxCfm+s0//Bpbi9361NyI/FusMun2ODOTRZH81uunwRax7g
V3iIfrcuIX8Fqr3J5XNssIiia7Gl5BX0fD9eiDknoYOJbrs1yTGo5ptCLNGrZPZOsMGEzXoZTQfp
tcvujIkNJmzWa/tTHOmxx5h1Z0xsMGGz7omLLvcvcYYJnaUcL7LBpBlkgTWDJM0gC2whBvkOvUFd
6zGdYcadMbHBhM2H8A16ZHpJZ8h+kLTBIgoM4UwUHMGiDulju+5Rl8tRL/VU73m/n9hgGYX0DVBF
V7t8Dnv0rvza5XLUK3pOunyZDZapWBRtBnG5HPWKns0gbVQsijaDuFyOekXPZpA2KhZFd0Df2Tvx
Au9KsSrUq2uD9EJXBjmLEx16i8+lWBXq1bVBmn92l8tRr+jZDNJGxaJoM4jL5ahX9GwGaUOxU1F0
1OVz2PO3g2yMnhMuX2aDZRTbHEXvYqlbMxfWdzwI65fgDtSz0kUfG3QoOB2F9XHjNq5XpIs7ul7o
co5q601UvW4g+yt8YoMOBQehn/51SUG/rqhRN6i2euiSxaA7i2ODdWSDdWSDdWSDdWSD9dPq+wPA
loc0th/dZQAAAABJRU5ErkJgggs='))
	#endregion
	$CustPkgIcon.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$CustPkgIcon.Location = New-Object System.Drawing.Point(20, 16)
	$CustPkgIcon.Name = 'CustPkgIcon'
	$CustPkgIcon.Size = New-Object System.Drawing.Size(50, 50)
	$CustPkgIcon.SizeMode = 'StretchImage'
	$CustPkgIcon.TabIndex = 104
	$CustPkgIcon.TabStop = $False
	#
	# CustomPkgTabLabel
	#
	$CustomPkgTabLabel.AutoSize = $True
	$CustomPkgTabLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '16', [System.Drawing.FontStyle]'Bold')
	$CustomPkgTabLabel.ForeColor = [System.Drawing.Color]::White 
	$CustomPkgTabLabel.Location = New-Object System.Drawing.Point(90, 24)
	$CustomPkgTabLabel.Name = 'CustomPkgTabLabel'
	$CustomPkgTabLabel.Size = New-Object System.Drawing.Size(263, 35)
	$CustomPkgTabLabel.TabIndex = 103
	$CustomPkgTabLabel.Text = 'Custom Package Creation'
	$CustomPkgTabLabel.UseCompatibleTextRendering = $True
	#
	# CustomPkgDataGrid
	#
	$CustomPkgDataGrid.AllowUserToResizeRows = $False
	$CustomPkgDataGrid.Anchor = 'Top, Bottom, Left, Right'
	$CustomPkgDataGrid.BackgroundColor = [System.Drawing.Color]::White 
	$System_Windows_Forms_DataGridViewCellStyle_9 = New-Object 'System.Windows.Forms.DataGridViewCellStyle'
	$System_Windows_Forms_DataGridViewCellStyle_9.Alignment = 'MiddleLeft'
	$System_Windows_Forms_DataGridViewCellStyle_9.BackColor = [System.Drawing.Color]::White 
	$System_Windows_Forms_DataGridViewCellStyle_9.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$System_Windows_Forms_DataGridViewCellStyle_9.ForeColor = [System.Drawing.SystemColors]::WindowText 
	$System_Windows_Forms_DataGridViewCellStyle_9.SelectionBackColor = [System.Drawing.SystemColors]::Highlight 
	$System_Windows_Forms_DataGridViewCellStyle_9.SelectionForeColor = [System.Drawing.SystemColors]::HighlightText 
	$System_Windows_Forms_DataGridViewCellStyle_9.WrapMode = 'True'
	$CustomPkgDataGrid.ColumnHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_9
	$CustomPkgDataGrid.ColumnHeadersHeight = 30
	$CustomPkgDataGrid.ColumnHeadersHeightSizeMode = 'DisableResizing'
	[void]$CustomPkgDataGrid.Columns.Add($Make)
	[void]$CustomPkgDataGrid.Columns.Add($Model)
	[void]$CustomPkgDataGrid.Columns.Add($Baseboard)
	[void]$CustomPkgDataGrid.Columns.Add($Platform)
	[void]$CustomPkgDataGrid.Columns.Add($OperatingSystem)
	[void]$CustomPkgDataGrid.Columns.Add($Architecture)
	[void]$CustomPkgDataGrid.Columns.Add($Revision)
	[void]$CustomPkgDataGrid.Columns.Add($SourceDirectory)
	[void]$CustomPkgDataGrid.Columns.Add($Browse)
	$System_Windows_Forms_DataGridViewCellStyle_10 = New-Object 'System.Windows.Forms.DataGridViewCellStyle'
	$System_Windows_Forms_DataGridViewCellStyle_10.Alignment = 'MiddleLeft'
	$System_Windows_Forms_DataGridViewCellStyle_10.BackColor = [System.Drawing.Color]::White 
	$System_Windows_Forms_DataGridViewCellStyle_10.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$System_Windows_Forms_DataGridViewCellStyle_10.ForeColor = [System.Drawing.SystemColors]::ControlText 
	$System_Windows_Forms_DataGridViewCellStyle_10.SelectionBackColor = [System.Drawing.Color]::Maroon 
	$System_Windows_Forms_DataGridViewCellStyle_10.SelectionForeColor = [System.Drawing.SystemColors]::HighlightText 
	$System_Windows_Forms_DataGridViewCellStyle_10.WrapMode = 'False'
	$CustomPkgDataGrid.DefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_10
	$CustomPkgDataGrid.GridColor = [System.Drawing.Color]::White 
	$CustomPkgDataGrid.Location = New-Object System.Drawing.Point(0, 197)
	$CustomPkgDataGrid.Name = 'CustomPkgDataGrid'
	$System_Windows_Forms_DataGridViewCellStyle_11 = New-Object 'System.Windows.Forms.DataGridViewCellStyle'
	$System_Windows_Forms_DataGridViewCellStyle_11.Alignment = 'MiddleLeft'
	$System_Windows_Forms_DataGridViewCellStyle_11.BackColor = [System.Drawing.Color]::White 
	$System_Windows_Forms_DataGridViewCellStyle_11.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$System_Windows_Forms_DataGridViewCellStyle_11.ForeColor = [System.Drawing.Color]::Black 
	$System_Windows_Forms_DataGridViewCellStyle_11.SelectionBackColor = [System.Drawing.Color]::Maroon 
	$System_Windows_Forms_DataGridViewCellStyle_11.SelectionForeColor = [System.Drawing.SystemColors]::HighlightText 
	$System_Windows_Forms_DataGridViewCellStyle_11.WrapMode = 'True'
	$CustomPkgDataGrid.RowHeadersDefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_11
	$CustomPkgDataGrid.RowHeadersVisible = $False
	$CustomPkgDataGrid.RowTemplate.DefaultCellStyle.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$CustomPkgDataGrid.RowTemplate.Height = 24
	$CustomPkgDataGrid.ShowCellErrors = $False
	$CustomPkgDataGrid.Size = New-Object System.Drawing.Size(1223, 293)
	$CustomPkgDataGrid.TabIndex = 1
	$CustomPkgDataGrid.add_CellContentClick($CustomPkgDataGrid_CellContentClick)
	$CustomPkgDataGrid.add_CurrentCellDirtyStateChanged($CustomPkgDataGrid_CurrentCellDirtyStateChanged)
	#
	# CustomPkgPanel
	#
	$CustomPkgPanel.Controls.Add($CustomPkgGroup)
	$CustomPkgPanel.Controls.Add($groupbox2)
	$CustomPkgPanel.Anchor = 'Top, Bottom, Left, Right'
	$CustomPkgPanel.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$CustomPkgPanel.Location = New-Object System.Drawing.Point(0, 83)
	$CustomPkgPanel.Name = 'CustomPkgPanel'
	$CustomPkgPanel.Size = New-Object System.Drawing.Size(1230, 485)
	$CustomPkgPanel.TabIndex = 101
	#
	# CustomPkgGroup
	#
	$CustomPkgGroup.Controls.Add($CustomDeploymentLabel)
	$CustomPkgGroup.Controls.Add($CustomPkgPlatform)
	$CustomPkgGroup.Anchor = 'Top, Left, Right'
	$CustomPkgGroup.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$CustomPkgGroup.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$CustomPkgGroup.ForeColor = [System.Drawing.Color]::Black 
	$CustomPkgGroup.Location = New-Object System.Drawing.Point(3, 3)
	$CustomPkgGroup.Name = 'CustomPkgGroup'
	$CustomPkgGroup.Size = New-Object System.Drawing.Size(1220, 93)
	$CustomPkgGroup.TabIndex = 98
	$CustomPkgGroup.TabStop = $False
	$CustomPkgGroup.Text = 'Custom Package Details'
	$CustomPkgGroup.UseCompatibleTextRendering = $True
	#
	# CustomDeploymentLabel
	#
	$CustomDeploymentLabel.AutoSize = $True
	$CustomDeploymentLabel.BackColor = [System.Drawing.Color]::Transparent 
	$CustomDeploymentLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$CustomDeploymentLabel.ForeColor = [System.Drawing.Color]::Black 
	$CustomDeploymentLabel.Location = New-Object System.Drawing.Point(21, 46)
	$CustomDeploymentLabel.Margin = '4, 0, 4, 0'
	$CustomDeploymentLabel.Name = 'CustomDeploymentLabel'
	$CustomDeploymentLabel.Size = New-Object System.Drawing.Size(130, 21)
	$CustomDeploymentLabel.TabIndex = 29
	$CustomDeploymentLabel.Text = 'Deployment Platform'
	$CustomDeploymentLabel.UseCompatibleTextRendering = $True
	#
	# CustomPkgPlatform
	#
	$CustomPkgPlatform.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$CustomPkgPlatform.DropDownStyle = 'DropDownList'
	$CustomPkgPlatform.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9', [System.Drawing.FontStyle]'Bold')
	$CustomPkgPlatform.FormattingEnabled = $True
	[void]$CustomPkgPlatform.Items.Add('ConfigMgr')
	[void]$CustomPkgPlatform.Items.Add('MDT')
	[void]$CustomPkgPlatform.Items.Add('XML')
	$CustomPkgPlatform.Location = New-Object System.Drawing.Point(179, 43)
	$CustomPkgPlatform.Name = 'CustomPkgPlatform'
	$CustomPkgPlatform.Size = New-Object System.Drawing.Size(230, 23)
	$CustomPkgPlatform.TabIndex = 28
	$CustomPkgPlatform.add_SelectedIndexChanged($CustomPkgPlatform_SelectedIndexChanged)
	#
	# groupbox2
	#
	$groupbox2.Controls.Add($QuerySystemButton)
	$groupbox2.Controls.Add($ImportExtractedDriveButton)
	$groupbox2.Controls.Add($CustomExtractButton)
	$groupbox2.Controls.Add($ImportCSVButton)
	$groupbox2.Controls.Add($CreatePackagesButton)
	$groupbox2.Anchor = 'Bottom, Left, Right'
	$groupbox2.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$groupbox2.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$groupbox2.ForeColor = [System.Drawing.Color]::Black 
	$groupbox2.Location = New-Object System.Drawing.Point(7, 389)
	$groupbox2.Name = 'groupbox2'
	$groupbox2.Size = New-Object System.Drawing.Size(1220, 89)
	$groupbox2.TabIndex = 99
	$groupbox2.TabStop = $False
	$groupbox2.Text = 'Driver Extract / Import Options'
	$groupbox2.UseCompatibleTextRendering = $True
	#
	# QuerySystemButton
	#
	$QuerySystemButton.Anchor = 'Bottom, Left'
	$QuerySystemButton.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$QuerySystemButton.Enabled = $False
	$QuerySystemButton.FlatStyle = 'Flat'
	$QuerySystemButton.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$QuerySystemButton.ForeColor = [System.Drawing.Color]::White 
	$QuerySystemButton.Location = New-Object System.Drawing.Point(40, 40)
	$QuerySystemButton.Margin = '4, 3, 4, 3'
	$QuerySystemButton.Name = 'QuerySystemButton'
	$QuerySystemButton.Size = New-Object System.Drawing.Size(210, 30)
	$QuerySystemButton.TabIndex = 102
	$QuerySystemButton.Text = 'Query Local System'
	$QuerySystemButton.UseCompatibleTextRendering = $True
	$QuerySystemButton.UseVisualStyleBackColor = $False
	$QuerySystemButton.add_Click($QuerySystemButton_Click)
	#
	# ImportExtractedDriveButton
	#
	$ImportExtractedDriveButton.Anchor = 'Bottom, Left'
	$ImportExtractedDriveButton.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$ImportExtractedDriveButton.Enabled = $False
	$ImportExtractedDriveButton.FlatStyle = 'Flat'
	$ImportExtractedDriveButton.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$ImportExtractedDriveButton.ForeColor = [System.Drawing.Color]::White 
	$ImportExtractedDriveButton.Location = New-Object System.Drawing.Point(484, 40)
	$ImportExtractedDriveButton.Margin = '4, 3, 4, 3'
	$ImportExtractedDriveButton.Name = 'ImportExtractedDriveButton'
	$ImportExtractedDriveButton.Size = New-Object System.Drawing.Size(240, 30)
	$ImportExtractedDriveButton.TabIndex = 101
	$ImportExtractedDriveButton.Text = 'Import Extracted Drivers'
	$ImportExtractedDriveButton.UseCompatibleTextRendering = $True
	$ImportExtractedDriveButton.UseVisualStyleBackColor = $False
	$ImportExtractedDriveButton.add_Click($ImportExtractedDriveButton_Click)
	#
	# CustomExtractButton
	#
	$CustomExtractButton.Anchor = 'Bottom, Left'
	$CustomExtractButton.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$CustomExtractButton.Enabled = $False
	$CustomExtractButton.FlatStyle = 'Flat'
	$CustomExtractButton.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$CustomExtractButton.ForeColor = [System.Drawing.Color]::White 
	$CustomExtractButton.Location = New-Object System.Drawing.Point(252, 40)
	$CustomExtractButton.Margin = '4, 3, 4, 3'
	$CustomExtractButton.Name = 'CustomExtractButton'
	$CustomExtractButton.Size = New-Object System.Drawing.Size(230, 30)
	$CustomExtractButton.TabIndex = 100
	$CustomExtractButton.Text = 'Extract System Drivers'
	$CustomExtractButton.UseCompatibleTextRendering = $True
	$CustomExtractButton.UseVisualStyleBackColor = $False
	$CustomExtractButton.add_Click($CustomExtractButton_Click)
	#
	# ImportCSVButton
	#
	$ImportCSVButton.Anchor = 'Bottom, Left'
	$ImportCSVButton.BackColor = [System.Drawing.Color]::FromArgb(255, 64, 64, 64)
	$ImportCSVButton.Enabled = $False
	$ImportCSVButton.FlatStyle = 'Flat'
	$ImportCSVButton.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$ImportCSVButton.ForeColor = [System.Drawing.Color]::White 
	$ImportCSVButton.Location = New-Object System.Drawing.Point(726, 40)
	$ImportCSVButton.Margin = '4, 3, 4, 3'
	$ImportCSVButton.Name = 'ImportCSVButton'
	$ImportCSVButton.Size = New-Object System.Drawing.Size(220, 30)
	$ImportCSVButton.TabIndex = 96
	$ImportCSVButton.Text = 'Import CSV Model List'
	$ImportCSVButton.UseCompatibleTextRendering = $True
	$ImportCSVButton.UseVisualStyleBackColor = $False
	$ImportCSVButton.add_Click($ImportCSVButton_Click)
	#
	# CreatePackagesButton
	#
	$CreatePackagesButton.Anchor = 'Bottom, Left'
	$CreatePackagesButton.BackColor = [System.Drawing.Color]::FromArgb(255, 101, 7, 0)
	$CreatePackagesButton.Enabled = $False
	$CreatePackagesButton.FlatStyle = 'Flat'
	$CreatePackagesButton.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$CreatePackagesButton.ForeColor = [System.Drawing.Color]::White 
	$CreatePackagesButton.Location = New-Object System.Drawing.Point(948, 40)
	$CreatePackagesButton.Margin = '4, 3, 4, 3'
	$CreatePackagesButton.Name = 'CreatePackagesButton'
	$CreatePackagesButton.Size = New-Object System.Drawing.Size(220, 30)
	$CreatePackagesButton.TabIndex = 95
	$CreatePackagesButton.Text = 'Create Driver Packages'
	$CreatePackagesButton.UseCompatibleTextRendering = $True
	$CreatePackagesButton.UseVisualStyleBackColor = $False
	$CreatePackagesButton.add_Click($CreatePackagesButton_Click)
	#
	# LogTab
	#
	$LogTab.Controls.Add($ProcessTabLabel)
	$LogTab.Controls.Add($ProcessIcon)
	$LogTab.Controls.Add($LogPanel)
	$LogTab.BackColor = [System.Drawing.Color]::Gray 
	$LogTab.Location = New-Object System.Drawing.Point(4, 48)
	$LogTab.Name = 'LogTab'
	$LogTab.Size = New-Object System.Drawing.Size(1231, 564)
	$LogTab.TabIndex = 8
	$LogTab.Text = 'Process Log'
	#
	# ProcessTabLabel
	#
	$ProcessTabLabel.AutoSize = $True
	$ProcessTabLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '16', [System.Drawing.FontStyle]'Bold')
	$ProcessTabLabel.ForeColor = [System.Drawing.Color]::White 
	$ProcessTabLabel.Location = New-Object System.Drawing.Point(90, 24)
	$ProcessTabLabel.Name = 'ProcessTabLabel'
	$ProcessTabLabel.Size = New-Object System.Drawing.Size(126, 35)
	$ProcessTabLabel.TabIndex = 71
	$ProcessTabLabel.Text = 'Process Log'
	$ProcessTabLabel.UseCompatibleTextRendering = $True
	#
	# ProcessIcon
	#
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
AAEAAAD/////AQAAAAAAAAAMAgAAAFFTeXN0ZW0uRHJhd2luZywgVmVyc2lvbj00LjAuMC4wLCBD
dWx0dXJlPW5ldXRyYWwsIFB1YmxpY0tleVRva2VuPWIwM2Y1ZjdmMTFkNTBhM2EFAQAAABVTeXN0
ZW0uRHJhd2luZy5CaXRtYXABAAAABERhdGEHAgIAAAAJAwAAAA8DAAAAswIAAAKJUE5HDQoaCgAA
AA1JSERSAAAAMgAAADIIBgAAAB4/iLEAAAAEZ0FNQQAAsY8L/GEFAAAACXBIWXMAAAsMAAALDAE/
QCLIAAACVUlEQVRoQ+3ZvWsUURQF8I1fQTQJRjsVC62ikEAqwSIE/APETmwE7VSwUfAf0JDG0sIm
hZ0IQSGFlY0INqIIgoWFhRYWgiziB47nLvcth8lJMlnuW5nkFT+ye97MvXNhJuzMdKqq2hJk2EYy
bCMZ1l0Z7ZyG5/ALqmDv4bjquxkyZGgyDz+96R/4Ap8CfIY0jH2eUf2bkiFDg3fe7AkcUtsMArVO
eN3kG8ypbZuQIUPxv97opFofFOrxIC/87w84p7bfiAyZNzATan1QqMeD7Ien/tlO38tqn/XIkHnx
3IPsgN2w5N/tLLit9luLDJkXzj6IZyOwSPk96K1tRIaMimYfhNZuQro2H8IeXldkyLzYUAfx9Uvw
29dXYF99GyZD5oVyD7IAd4VXkLZ5qeokMmRUKHqQY1S7kXoNJkNGhUIHMah5Hq418Aawi65jZMis
gAsfpCn0Xi6DJGWQQGUQti0GQWa/jezHXpSd9R7eJ/sgD8Buf6PYneIB0Sf7IHfge6C3MCb65L9G
kNu9RJSRNXqUi72vDBKoDMLWGwTZFFwNJB8FIc8+yDNaj2D36YdFn+yDnAG7TY1yHVb9C0ZWrpG+
MkigMgjbFoMguwH2ximKPVHcK/pkH+QRrUfowkHRJ/sgo3A00GS9h/cp10jfVhxk1bk7LOjdey1X
z5kMGQrYOz0bZF6t54a+u+CjHUN9jcmQoUB6SWnFLsIsTA/JWXgM1r+rji+RIUOBI/DBi/0v9qjo
gjq+RIZ1KDIOt+A1qEa5fIX7cEodF5NhG8mwjWTYPlXnH3rcbtR1CciLAAAAAElFTkSuQmCCCw=='))
	#endregion
	$ProcessIcon.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$ProcessIcon.Location = New-Object System.Drawing.Point(20, 16)
	$ProcessIcon.Name = 'ProcessIcon'
	$ProcessIcon.Size = New-Object System.Drawing.Size(50, 50)
	$ProcessIcon.SizeMode = 'StretchImage'
	$ProcessIcon.TabIndex = 70
	$ProcessIcon.TabStop = $False
	#
	# LogPanel
	#
	$LogPanel.Controls.Add($RemainingDownloads)
	$LogPanel.Controls.Add($labelRemainingDownloads)
	$LogPanel.Controls.Add($FileSize)
	$LogPanel.Controls.Add($labelFileSizeMB)
	$LogPanel.Controls.Add($CurrentDownload)
	$LogPanel.Controls.Add($richtextbox2)
	$LogPanel.Controls.Add($ErrorsOccurred)
	$LogPanel.Controls.Add($TotalDownloads)
	$LogPanel.Controls.Add($JobStatus)
	$LogPanel.Controls.Add($ProgressListBox)
	$LogPanel.Controls.Add($labelWarningsErrors)
	$LogPanel.Controls.Add($labelSelectedDownloads)
	$LogPanel.Controls.Add($labelCurrentDownload)
	$LogPanel.Controls.Add($labelJobStatus)
	$LogPanel.Controls.Add($ProgressLabel)
	$LogPanel.Controls.Add($ModelProgressOverlay)
	$LogPanel.Controls.Add($ProgressBar)
	$LogPanel.Anchor = 'Top, Bottom, Left, Right'
	$LogPanel.BackColor = [System.Drawing.Color]::LightGray 
	$LogPanel.Location = New-Object System.Drawing.Point(0, 83)
	$LogPanel.Name = 'LogPanel'
	$LogPanel.Size = New-Object System.Drawing.Size(1230, 481)
	$LogPanel.TabIndex = 72
	#
	# RemainingDownloads
	#
	$RemainingDownloads.Anchor = 'Top, Bottom, Left, Right'
	$RemainingDownloads.AutoSize = $True
	$RemainingDownloads.BackColor = [System.Drawing.Color]::Transparent 
	$RemainingDownloads.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$RemainingDownloads.ForeColor = [System.Drawing.Color]::Green 
	$RemainingDownloads.Location = New-Object System.Drawing.Point(1025, 241)
	$RemainingDownloads.Margin = '4, 0, 4, 0'
	$RemainingDownloads.Name = 'RemainingDownloads'
	$RemainingDownloads.Size = New-Object System.Drawing.Size(19, 22)
	$RemainingDownloads.TabIndex = 88
	$RemainingDownloads.Text = '- -'
	$RemainingDownloads.UseCompatibleTextRendering = $True
	#
	# labelRemainingDownloads
	#
	$labelRemainingDownloads.Anchor = 'Top, Bottom, Left, Right'
	$labelRemainingDownloads.AutoSize = $True
	$labelRemainingDownloads.BackColor = [System.Drawing.Color]::Transparent 
	$labelRemainingDownloads.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$labelRemainingDownloads.ForeColor = [System.Drawing.Color]::Black 
	$labelRemainingDownloads.Location = New-Object System.Drawing.Point(865, 241)
	$labelRemainingDownloads.Margin = '4, 0, 4, 0'
	$labelRemainingDownloads.Name = 'labelRemainingDownloads'
	$labelRemainingDownloads.Size = New-Object System.Drawing.Size(146, 22)
	$labelRemainingDownloads.TabIndex = 87
	$labelRemainingDownloads.Text = 'Remaining Downloads'
	$labelRemainingDownloads.UseCompatibleTextRendering = $True
	#
	# FileSize
	#
	$FileSize.Anchor = 'Top, Bottom, Left, Right'
	$FileSize.AutoSize = $True
	$FileSize.BackColor = [System.Drawing.Color]::Transparent 
	$FileSize.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$FileSize.ForeColor = [System.Drawing.Color]::Green 
	$FileSize.Location = New-Object System.Drawing.Point(1025, 165)
	$FileSize.Margin = '4, 0, 4, 0'
	$FileSize.Name = 'FileSize'
	$FileSize.Size = New-Object System.Drawing.Size(19, 22)
	$FileSize.TabIndex = 86
	$FileSize.Text = '- -'
	$FileSize.UseCompatibleTextRendering = $True
	#
	# labelFileSizeMB
	#
	$labelFileSizeMB.Anchor = 'Top, Bottom, Left, Right'
	$labelFileSizeMB.AutoSize = $True
	$labelFileSizeMB.BackColor = [System.Drawing.Color]::Transparent 
	$labelFileSizeMB.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$labelFileSizeMB.ForeColor = [System.Drawing.Color]::Black 
	$labelFileSizeMB.Location = New-Object System.Drawing.Point(866, 165)
	$labelFileSizeMB.Margin = '4, 0, 4, 0'
	$labelFileSizeMB.Name = 'labelFileSizeMB'
	$labelFileSizeMB.Size = New-Object System.Drawing.Size(90, 22)
	$labelFileSizeMB.TabIndex = 85
	$labelFileSizeMB.Text = 'File Size (MB)'
	$labelFileSizeMB.UseCompatibleTextRendering = $True
	#
	# CurrentDownload
	#
	$CurrentDownload.BackColor = [System.Drawing.Color]::LightGray 
	$CurrentDownload.BorderStyle = 'None'
	$CurrentDownload.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9.75', [System.Drawing.FontStyle]'Bold')
	$CurrentDownload.ForeColor = [System.Drawing.Color]::Green 
	$CurrentDownload.Location = New-Object System.Drawing.Point(1025, 68)
	$CurrentDownload.Name = 'CurrentDownload'
	$CurrentDownload.ScrollBars = 'None'
	$CurrentDownload.Size = New-Object System.Drawing.Size(184, 81)
	$CurrentDownload.TabIndex = 84
	$CurrentDownload.Text = '- -'
	#
	# richtextbox2
	#
	$richtextbox2.Anchor = 'Top, Left, Right'
	$richtextbox2.BackColor = [System.Drawing.Color]::LightGray 
	$richtextbox2.BorderStyle = 'None'
	$richtextbox2.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$richtextbox2.ForeColor = [System.Drawing.Color]::Black 
	$richtextbox2.Location = New-Object System.Drawing.Point(866, 388)
	$richtextbox2.Name = 'richtextbox2'
	$richtextbox2.ScrollBars = 'None'
	$richtextbox2.Size = New-Object System.Drawing.Size(346, 85)
	$richtextbox2.TabIndex = 83
	$richtextbox2.Text = 'Note: If errors occur during the model detection or download phase, try clearing the cache in the TEMP folder where the Driver Automation Tool is installed. This will force a re-download of source content files from the supported manufacturers.'
	#
	# ErrorsOccurred
	#
	$ErrorsOccurred.Anchor = 'Top, Bottom, Left, Right'
	$ErrorsOccurred.AutoSize = $True
	$ErrorsOccurred.BackColor = [System.Drawing.Color]::Transparent 
	$ErrorsOccurred.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$ErrorsOccurred.ForeColor = [System.Drawing.Color]::Green 
	$ErrorsOccurred.Location = New-Object System.Drawing.Point(1025, 279)
	$ErrorsOccurred.Margin = '4, 0, 4, 0'
	$ErrorsOccurred.Name = 'ErrorsOccurred'
	$ErrorsOccurred.Size = New-Object System.Drawing.Size(24, 22)
	$ErrorsOccurred.TabIndex = 82
	$ErrorsOccurred.Text = 'No'
	$ErrorsOccurred.UseCompatibleTextRendering = $True
	#
	# TotalDownloads
	#
	$TotalDownloads.Anchor = 'Top, Bottom, Left, Right'
	$TotalDownloads.AutoSize = $True
	$TotalDownloads.BackColor = [System.Drawing.Color]::Transparent 
	$TotalDownloads.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$TotalDownloads.ForeColor = [System.Drawing.Color]::Green 
	$TotalDownloads.Location = New-Object System.Drawing.Point(1025, 203)
	$TotalDownloads.Margin = '4, 0, 4, 0'
	$TotalDownloads.Name = 'TotalDownloads'
	$TotalDownloads.Size = New-Object System.Drawing.Size(19, 22)
	$TotalDownloads.TabIndex = 81
	$TotalDownloads.Text = '- -'
	$TotalDownloads.UseCompatibleTextRendering = $True
	#
	# JobStatus
	#
	$JobStatus.Anchor = 'Top, Bottom, Left, Right'
	$JobStatus.AutoSize = $True
	$JobStatus.BackColor = [System.Drawing.Color]::Transparent 
	$JobStatus.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$JobStatus.ForeColor = [System.Drawing.Color]::Green 
	$JobStatus.Location = New-Object System.Drawing.Point(1025, 29)
	$JobStatus.Margin = '4, 0, 4, 0'
	$JobStatus.Name = 'JobStatus'
	$JobStatus.Size = New-Object System.Drawing.Size(19, 22)
	$JobStatus.TabIndex = 79
	$JobStatus.Text = '- -'
	$JobStatus.UseCompatibleTextRendering = $True
	#
	# ProgressListBox
	#
	$ProgressListBox.Anchor = 'Top, Bottom, Left'
	$ProgressListBox.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$ProgressListBox.BorderStyle = 'None'
	$ProgressListBox.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10')
	$ProgressListBox.ForeColor = [System.Drawing.Color]::Black 
	$ProgressListBox.FormattingEnabled = $True
	$ProgressListBox.ItemHeight = 17
	$ProgressListBox.Location = New-Object System.Drawing.Point(0, 0)
	$ProgressListBox.Margin = '4, 3, 4, 3'
	$ProgressListBox.Name = 'ProgressListBox'
	$ProgressListBox.ScrollAlwaysVisible = $True
	$ProgressListBox.Size = New-Object System.Drawing.Size(837, 476)
	$ProgressListBox.TabIndex = 27
	#
	# labelWarningsErrors
	#
	$labelWarningsErrors.Anchor = 'Top, Bottom, Left, Right'
	$labelWarningsErrors.AutoSize = $True
	$labelWarningsErrors.BackColor = [System.Drawing.Color]::Transparent 
	$labelWarningsErrors.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$labelWarningsErrors.ForeColor = [System.Drawing.Color]::Black 
	$labelWarningsErrors.Location = New-Object System.Drawing.Point(866, 279)
	$labelWarningsErrors.Margin = '4, 0, 4, 0'
	$labelWarningsErrors.Name = 'labelWarningsErrors'
	$labelWarningsErrors.Size = New-Object System.Drawing.Size(116, 22)
	$labelWarningsErrors.TabIndex = 78
	$labelWarningsErrors.Text = 'Warnings / Errors'
	$labelWarningsErrors.UseCompatibleTextRendering = $True
	#
	# labelSelectedDownloads
	#
	$labelSelectedDownloads.Anchor = 'Top, Bottom, Left, Right'
	$labelSelectedDownloads.AutoSize = $True
	$labelSelectedDownloads.BackColor = [System.Drawing.Color]::Transparent 
	$labelSelectedDownloads.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$labelSelectedDownloads.ForeColor = [System.Drawing.Color]::Black 
	$labelSelectedDownloads.Location = New-Object System.Drawing.Point(865, 203)
	$labelSelectedDownloads.Margin = '4, 0, 4, 0'
	$labelSelectedDownloads.Name = 'labelSelectedDownloads'
	$labelSelectedDownloads.Size = New-Object System.Drawing.Size(132, 22)
	$labelSelectedDownloads.TabIndex = 77
	$labelSelectedDownloads.Text = 'Selected Downloads'
	$labelSelectedDownloads.UseCompatibleTextRendering = $True
	#
	# labelCurrentDownload
	#
	$labelCurrentDownload.Anchor = 'Top, Bottom, Left, Right'
	$labelCurrentDownload.AutoSize = $True
	$labelCurrentDownload.BackColor = [System.Drawing.Color]::Transparent 
	$labelCurrentDownload.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$labelCurrentDownload.ForeColor = [System.Drawing.Color]::Black 
	$labelCurrentDownload.Location = New-Object System.Drawing.Point(866, 70)
	$labelCurrentDownload.Margin = '4, 0, 4, 0'
	$labelCurrentDownload.Name = 'labelCurrentDownload'
	$labelCurrentDownload.Size = New-Object System.Drawing.Size(121, 22)
	$labelCurrentDownload.TabIndex = 76
	$labelCurrentDownload.Text = 'Current Download'
	$labelCurrentDownload.UseCompatibleTextRendering = $True
	#
	# labelJobStatus
	#
	$labelJobStatus.Anchor = 'Top, Bottom, Left, Right'
	$labelJobStatus.AutoSize = $True
	$labelJobStatus.BackColor = [System.Drawing.Color]::Transparent 
	$labelJobStatus.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$labelJobStatus.ForeColor = [System.Drawing.Color]::Black 
	$labelJobStatus.Location = New-Object System.Drawing.Point(866, 29)
	$labelJobStatus.Margin = '4, 0, 4, 0'
	$labelJobStatus.Name = 'labelJobStatus'
	$labelJobStatus.Size = New-Object System.Drawing.Size(70, 22)
	$labelJobStatus.TabIndex = 75
	$labelJobStatus.Text = 'Job Status'
	$labelJobStatus.UseCompatibleTextRendering = $True
	#
	# ProgressLabel
	#
	$ProgressLabel.Anchor = 'Top, Bottom, Left, Right'
	$ProgressLabel.AutoSize = $True
	$ProgressLabel.BackColor = [System.Drawing.Color]::Transparent 
	$ProgressLabel.Font = [System.Drawing.Font]::new('Segoe UI', '9.75', [System.Drawing.FontStyle]'Bold')
	$ProgressLabel.ForeColor = [System.Drawing.Color]::Maroon 
	$ProgressLabel.Location = New-Object System.Drawing.Point(866, 317)
	$ProgressLabel.Margin = '4, 0, 4, 0'
	$ProgressLabel.Name = 'ProgressLabel'
	$ProgressLabel.Size = New-Object System.Drawing.Size(108, 22)
	$ProgressLabel.TabIndex = 74
	$ProgressLabel.Text = 'Overall Progress'
	$ProgressLabel.UseCompatibleTextRendering = $True
	#
	# ModelProgressOverlay
	#
	$ModelProgressOverlay.Anchor = 'Top, Left, Right'
	$ModelProgressOverlay.Location = New-Object System.Drawing.Point(866, 341)
	$ModelProgressOverlay.Margin = '4, 3, 4, 3'
	$ModelProgressOverlay.Name = 'ModelProgressOverlay'
	$ModelProgressOverlay.Size = New-Object System.Drawing.Size(338, 34)
	$ModelProgressOverlay.Style = 'Continuous'
	$ModelProgressOverlay.TabIndex = 73
	#
	# ProgressBar
	#
	$ProgressBar.Anchor = 'Top, Left, Right'
	$ProgressBar.Location = New-Object System.Drawing.Point(866, 341)
	$ProgressBar.Margin = '4, 3, 4, 3'
	$ProgressBar.Name = 'ProgressBar'
	$ProgressBar.Size = New-Object System.Drawing.Size(337, 34)
	$ProgressBar.Style = 'Continuous'
	$ProgressBar.TabIndex = 28
	#
	# AboutTab
	#
	$AboutTab.Controls.Add($AboutPanelRight)
	$AboutTab.Controls.Add($AboutTabLabel)
	$AboutTab.Controls.Add($NewVersion)
	$AboutTab.Controls.Add($AboutIcon)
	$AboutTab.Controls.Add($AboutPanelLeft)
	$AboutTab.Controls.Add($NewVersionLabel)
	$AboutTab.Controls.Add($BuildDate)
	$AboutTab.Controls.Add($Version)
	$AboutTab.Controls.Add($lBuildDateLabel)
	$AboutTab.Controls.Add($VersionLabel)
	$AboutTab.BackColor = [System.Drawing.Color]::Gray 
	$AboutTab.Location = New-Object System.Drawing.Point(4, 48)
	$AboutTab.Name = 'AboutTab'
	$AboutTab.Padding = '3, 3, 3, 3'
	$AboutTab.Size = New-Object System.Drawing.Size(1231, 564)
	$AboutTab.TabIndex = 0
	$AboutTab.Text = 'About'
	#
	# AboutPanelRight
	#
	$AboutPanelRight.Controls.Add($richtextbox3)
	$AboutPanelRight.Controls.Add($MSTechnetSiteLaunchButton)
	$AboutPanelRight.Controls.Add($ReleaseNotesText)
	$AboutPanelRight.Anchor = 'Top, Bottom, Right'
	$AboutPanelRight.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$AboutPanelRight.Location = New-Object System.Drawing.Point(711, 83)
	$AboutPanelRight.Name = 'AboutPanelRight'
	$AboutPanelRight.Size = New-Object System.Drawing.Size(505, 485)
	$AboutPanelRight.TabIndex = 68
	#
	# richtextbox3
	#
	$richtextbox3.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$richtextbox3.BorderStyle = 'None'
	$richtextbox3.Font = [System.Drawing.Font]::new('Segoe UI', '11.25', [System.Drawing.FontStyle]'Bold')
	$richtextbox3.ForeColor = [System.Drawing.Color]::Black 
	$richtextbox3.Location = New-Object System.Drawing.Point(35, 28)
	$richtextbox3.Name = 'richtextbox3'
	$richtextbox3.ScrollBars = 'None'
	$richtextbox3.Size = New-Object System.Drawing.Size(200, 34)
	$richtextbox3.TabIndex = 66
	$richtextbox3.Text = 'Latest Release Notes'
	#
	# MSTechnetSiteLaunchButton
	#
	$MSTechnetSiteLaunchButton.Anchor = 'Top, Left, Right'
	$MSTechnetSiteLaunchButton.BackColor = [System.Drawing.Color]::FromArgb(255, 122, 0, 0)
	$MSTechnetSiteLaunchButton.FlatStyle = 'Flat'
	$MSTechnetSiteLaunchButton.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9.75', [System.Drawing.FontStyle]'Bold')
	$MSTechnetSiteLaunchButton.ForeColor = [System.Drawing.Color]::White 
	$MSTechnetSiteLaunchButton.Location = New-Object System.Drawing.Point(35, 427)
	$MSTechnetSiteLaunchButton.Name = 'MSTechnetSiteLaunchButton'
	$MSTechnetSiteLaunchButton.Size = New-Object System.Drawing.Size(438, 40)
	$MSTechnetSiteLaunchButton.TabIndex = 2
	$MSTechnetSiteLaunchButton.Text = 'Launch GitHub'
	$MSTechnetSiteLaunchButton.UseCompatibleTextRendering = $True
	$MSTechnetSiteLaunchButton.UseVisualStyleBackColor = $False
	#
	# ReleaseNotesText
	#
	$ReleaseNotesText.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$ReleaseNotesText.BorderStyle = 'None'
	$ReleaseNotesText.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9.75', [System.Drawing.FontStyle]'Bold')
	$ReleaseNotesText.ForeColor = [System.Drawing.Color]::DarkRed 
	$ReleaseNotesText.Location = New-Object System.Drawing.Point(35, 68)
	$ReleaseNotesText.Margin = '2, 2, 2, 2'
	$ReleaseNotesText.Name = 'ReleaseNotesText'
	$ReleaseNotesText.ReadOnly = $True
	$ReleaseNotesText.Size = New-Object System.Drawing.Size(438, 343)
	$ReleaseNotesText.TabIndex = 35
	$ReleaseNotesText.Text = ''
	#
	# AboutTabLabel
	#
	$AboutTabLabel.AutoSize = $True
	$AboutTabLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '16', [System.Drawing.FontStyle]'Bold')
	$AboutTabLabel.ForeColor = [System.Drawing.Color]::White 
	$AboutTabLabel.Location = New-Object System.Drawing.Point(90, 24)
	$AboutTabLabel.Name = 'AboutTabLabel'
	$AboutTabLabel.Size = New-Object System.Drawing.Size(324, 35)
	$AboutTabLabel.TabIndex = 69
	$AboutTabLabel.Text = 'About | Driver Automation Tool'
	$AboutTabLabel.UseCompatibleTextRendering = $True
	#
	# NewVersion
	#
	$NewVersion.Anchor = 'Top, Right'
	$NewVersion.AutoSize = $True
	$NewVersion.ForeColor = [System.Drawing.Color]::Gold 
	$NewVersion.Location = New-Object System.Drawing.Point(1020, 17)
	$NewVersion.Name = 'NewVersion'
	$NewVersion.Size = New-Object System.Drawing.Size(10, 23)
	$NewVersion.TabIndex = 37
	$NewVersion.Text = '-'
	$NewVersion.UseCompatibleTextRendering = $True
	$NewVersion.Visible = $False
	#
	# AboutIcon
	#
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
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'))
	#endregion
	$AboutIcon.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$AboutIcon.Location = New-Object System.Drawing.Point(20, 16)
	$AboutIcon.Name = 'AboutIcon'
	$AboutIcon.Size = New-Object System.Drawing.Size(50, 50)
	$AboutIcon.SizeMode = 'StretchImage'
	$AboutIcon.TabIndex = 68
	$AboutIcon.TabStop = $False
	#
	# AboutPanelLeft
	#
	$AboutPanelLeft.Controls.Add($ModernDriverDesc)
	$AboutPanelLeft.Controls.Add($richtextbox5)
	$AboutPanelLeft.Controls.Add($ModernDriverLabel)
	$AboutPanelLeft.Controls.Add($AboutToolDesc)
	$AboutPanelLeft.Controls.Add($GitHubLaunchButton)
	$AboutPanelLeft.Anchor = 'Top, Bottom, Left, Right'
	$AboutPanelLeft.AutoSizeMode = 'GrowAndShrink'
	$AboutPanelLeft.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$AboutPanelLeft.Location = New-Object System.Drawing.Point(0, 83)
	$AboutPanelLeft.Name = 'AboutPanelLeft'
	$AboutPanelLeft.Size = New-Object System.Drawing.Size(705, 481)
	$AboutPanelLeft.TabIndex = 67
	#
	# ModernDriverDesc
	#
	$ModernDriverDesc.Anchor = 'Top, Left, Right'
	$ModernDriverDesc.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$ModernDriverDesc.BorderStyle = 'None'
	$ModernDriverDesc.Font = [System.Drawing.Font]::new('Segoe UI', '9.75')
	$ModernDriverDesc.ForeColor = [System.Drawing.Color]::Black 
	$ModernDriverDesc.Location = New-Object System.Drawing.Point(14, 285)
	$ModernDriverDesc.Name = 'ModernDriverDesc'
	$ModernDriverDesc.Size = New-Object System.Drawing.Size(640, 57)
	$ModernDriverDesc.TabIndex = 65
	$ModernDriverDesc.Text = 'This tool can be used as part of a complete automation process which we call Modern Driver Management. This dynamically deploys drivers during OSD, for more info click below;'
	#
	# richtextbox5
	#
	$richtextbox5.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$richtextbox5.BorderStyle = 'None'
	$richtextbox5.Font = [System.Drawing.Font]::new('Segoe UI', '11.25', [System.Drawing.FontStyle]'Bold')
	$richtextbox5.ForeColor = [System.Drawing.Color]::Black 
	$richtextbox5.Location = New-Object System.Drawing.Point(16, 28)
	$richtextbox5.Name = 'richtextbox5'
	$richtextbox5.ScrollBars = 'None'
	$richtextbox5.Size = New-Object System.Drawing.Size(562, 34)
	$richtextbox5.TabIndex = 66
	$richtextbox5.Text = 'Developed by: Maurice Daly (@MoDaly_IT)


'
	#
	# ModernDriverLabel
	#
	$ModernDriverLabel.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$ModernDriverLabel.BorderStyle = 'None'
	$ModernDriverLabel.Font = [System.Drawing.Font]::new('Segoe UI', '11.25', [System.Drawing.FontStyle]'Bold')
	$ModernDriverLabel.ForeColor = [System.Drawing.Color]::Maroon 
	$ModernDriverLabel.Location = New-Object System.Drawing.Point(14, 258)
	$ModernDriverLabel.Name = 'ModernDriverLabel'
	$ModernDriverLabel.ScrollBars = 'None'
	$ModernDriverLabel.Size = New-Object System.Drawing.Size(562, 37)
	$ModernDriverLabel.TabIndex = 64
	$ModernDriverLabel.Text = 'Modern Driver Management'
	#
	# AboutToolDesc
	#
	$AboutToolDesc.Anchor = 'Top, Left, Right'
	$AboutToolDesc.BackColor = [System.Drawing.Color]::WhiteSmoke 
	$AboutToolDesc.BorderStyle = 'None'
	$AboutToolDesc.Font = [System.Drawing.Font]::new('Segoe UI', '10')
	$AboutToolDesc.ForeColor = [System.Drawing.Color]::Black 
	$AboutToolDesc.Location = New-Object System.Drawing.Point(14, 83)
	$AboutToolDesc.Name = 'AboutToolDesc'
	$AboutToolDesc.ScrollBars = 'None'
	$AboutToolDesc.Size = New-Object System.Drawing.Size(641, 254)
	$AboutToolDesc.TabIndex = 62
	$AboutToolDesc.Text = 'LEGAL & SUPPORT INFORMATION:
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

THIS SCRIPT MUST NOT BE EDITED AND REDISTRIBUTED WITHOUT EXPRESS PERMISSION OF THE AUTHOR.


'
	#
	# GitHubLaunchButton
	#
	$GitHubLaunchButton.BackColor = [System.Drawing.Color]::FromArgb(255, 122, 0, 0)
	$GitHubLaunchButton.FlatStyle = 'Flat'
	$GitHubLaunchButton.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9.75', [System.Drawing.FontStyle]'Bold')
	$GitHubLaunchButton.ForeColor = [System.Drawing.Color]::White 
	$GitHubLaunchButton.Location = New-Object System.Drawing.Point(20, 427)
	$GitHubLaunchButton.Name = 'GitHubLaunchButton'
	$GitHubLaunchButton.Size = New-Object System.Drawing.Size(641, 40)
	$GitHubLaunchButton.TabIndex = 5
	$GitHubLaunchButton.Text = 'MSEndpointMgr - Modern Driver Management'
	$GitHubLaunchButton.UseCompatibleTextRendering = $True
	$GitHubLaunchButton.UseVisualStyleBackColor = $False
	$GitHubLaunchButton.add_Click($GitHubLaunchButton_Click)
	#
	# NewVersionLabel
	#
	$NewVersionLabel.Anchor = 'Top, Right'
	$NewVersionLabel.ForeColor = [System.Drawing.Color]::Gold 
	$NewVersionLabel.Location = New-Object System.Drawing.Point(901, 17)
	$NewVersionLabel.Name = 'NewVersionLabel'
	$NewVersionLabel.Size = New-Object System.Drawing.Size(133, 30)
	$NewVersionLabel.TabIndex = 36
	$NewVersionLabel.Text = 'New Version:'
	$NewVersionLabel.UseCompatibleTextRendering = $True
	$NewVersionLabel.Visible = $False
	#
	# BuildDate
	#
	$BuildDate.Anchor = 'Top, Right'
	$BuildDate.AutoSize = $True
	$BuildDate.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9.75', [System.Drawing.FontStyle]'Bold')
	$BuildDate.ForeColor = [System.Drawing.Color]::White 
	$BuildDate.Location = New-Object System.Drawing.Point(823, 45)
	$BuildDate.Name = 'BuildDate'
	$BuildDate.Size = New-Object System.Drawing.Size(10, 22)
	$BuildDate.TabIndex = 4
	$BuildDate.Text = '-'
	$BuildDate.UseCompatibleTextRendering = $True
	#
	# Version
	#
	$Version.Anchor = 'Top, Right'
	$Version.AutoSize = $True
	$Version.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9.75', [System.Drawing.FontStyle]'Bold')
	$Version.ForeColor = [System.Drawing.Color]::White 
	$Version.Location = New-Object System.Drawing.Point(823, 16)
	$Version.Name = 'Version'
	$Version.Size = New-Object System.Drawing.Size(10, 22)
	$Version.TabIndex = 3
	$Version.Text = '-'
	$Version.UseCompatibleTextRendering = $True
	#
	# lBuildDateLabel
	#
	$lBuildDateLabel.Anchor = 'Top, Right'
	$lBuildDateLabel.AutoSize = $True
	$lBuildDateLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9.75', [System.Drawing.FontStyle]'Bold')
	$lBuildDateLabel.ForeColor = [System.Drawing.Color]::White 
	$lBuildDateLabel.Location = New-Object System.Drawing.Point(725, 44)
	$lBuildDateLabel.Name = 'lBuildDateLabel'
	$lBuildDateLabel.Size = New-Object System.Drawing.Size(71, 22)
	$lBuildDateLabel.TabIndex = 1
	$lBuildDateLabel.Text = 'Build Date:'
	$lBuildDateLabel.UseCompatibleTextRendering = $True
	#
	# VersionLabel
	#
	$VersionLabel.Anchor = 'Top, Right'
	$VersionLabel.AutoSize = $True
	$VersionLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '9.75', [System.Drawing.FontStyle]'Bold')
	$VersionLabel.ForeColor = [System.Drawing.Color]::White 
	$VersionLabel.Location = New-Object System.Drawing.Point(725, 16)
	$VersionLabel.Name = 'VersionLabel'
	$VersionLabel.Size = New-Object System.Drawing.Size(54, 22)
	$VersionLabel.TabIndex = 0
	$VersionLabel.Text = 'Version:'
	$VersionLabel.UseCompatibleTextRendering = $True
	#
	# ResetDATSettings
	#
	$ResetDATSettings.Anchor = 'Bottom, Left, Right'
	$ResetDATSettings.AutoSizeMode = 'GrowAndShrink'
	$ResetDATSettings.BackColor = [System.Drawing.Color]::FromArgb(255, 83, 88, 101)
	$ResetDATSettings.Cursor = 'Hand'
	$ResetDATSettings.FlatStyle = 'Popup'
	$ResetDATSettings.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$ResetDATSettings.ForeColor = [System.Drawing.Color]::White 
	$ResetDATSettings.Location = New-Object System.Drawing.Point(12, 749)
	$ResetDATSettings.Margin = '4, 3, 4, 3'
	$ResetDATSettings.MaximumSize = New-Object System.Drawing.Size(566, 30)
	$ResetDATSettings.MinimumSize = New-Object System.Drawing.Size(566, 30)
	$ResetDATSettings.Name = 'ResetDATSettings'
	$ResetDATSettings.Padding = '10, 0, 10, 0'
	$ResetDATSettings.Size = New-Object System.Drawing.Size(566, 30)
	$ResetDATSettings.TabIndex = 35
	$ResetDATSettings.Text = 'Reset Tool
'
	$ResetDATSettings.UseCompatibleTextRendering = $True
	$ResetDATSettings.UseVisualStyleBackColor = $False
	$ResetDATSettings.add_Click($ResetDATSettings_Click)
	#
	# StartDownloadButton
	#
	$StartDownloadButton.Anchor = 'Bottom, Right'
	$StartDownloadButton.AutoSizeMode = 'GrowAndShrink'
	$StartDownloadButton.BackColor = [System.Drawing.Color]::FromArgb(255, 122, 0, 0)
	$StartDownloadButton.Cursor = 'Hand'
	$StartDownloadButton.Enabled = $False
	$StartDownloadButton.FlatAppearance.BorderSize = 0
	$StartDownloadButton.FlatStyle = 'Popup'
	$StartDownloadButton.Font = [System.Drawing.Font]::new('Segoe UI Semibold', '10', [System.Drawing.FontStyle]'Bold')
	$StartDownloadButton.ForeColor = [System.Drawing.Color]::White 
	$StartDownloadButton.Location = New-Object System.Drawing.Point(685, 749)
	$StartDownloadButton.Margin = '4, 3, 4, 3'
	$StartDownloadButton.MaximumSize = New-Object System.Drawing.Size(566, 30)
	$StartDownloadButton.MinimumSize = New-Object System.Drawing.Size(566, 30)
	$StartDownloadButton.Name = 'StartDownloadButton'
	$StartDownloadButton.Padding = '10, 0, 10, 0'
	$StartDownloadButton.Size = New-Object System.Drawing.Size(566, 30)
	$StartDownloadButton.TabIndex = 14
	$StartDownloadButton.Text = 'Start Download | Extract | Import'
	$StartDownloadButton.UseCompatibleTextRendering = $True
	$StartDownloadButton.UseVisualStyleBackColor = $False
	$StartDownloadButton.add_Click($StartDownloadButton_Click)
	#
	# DownloadBrowseFolderDialogue
	#
	#
	# PackageBrowseFolderDialogue
	#
	#
	# ScriptBrowseFolderDialogue
	#
	#
	# MDTScriptBrowse
	#
	$MDTScriptBrowse.Title = 'Select MDT PS Module Location'
	#
	# CustomDriverFolderDialogue
	#
	#
	# WebServicePackageName
	#
	$WebServicePackageName.AutoSizeMode = 'Fill'
	$WebServicePackageName.HeaderText = 'Package Name'
	$WebServicePackageName.Name = 'WebServicePackageName'
	#
	# PackageVersionDetails
	#
	$PackageVersionDetails.AutoSizeMode = 'DisplayedCells'
	$PackageVersionDetails.HeaderText = 'Package Version'
	$PackageVersionDetails.Name = 'PackageVersionDetails'
	$PackageVersionDetails.Width = 135
	#
	# WebServicePackageID
	#
	$WebServicePackageID.AutoSizeMode = 'DisplayedCells'
	$WebServicePackageID.HeaderText = 'Package ID'
	$WebServicePackageID.Name = 'WebServicePackageID'
	$WebServicePackageID.Width = 103
	#
	# Description
	#
	$Description.AutoSizeMode = 'Fill'
	$Description.HeaderText = 'Description'
	$Description.Name = 'Description'
	$Description.ReadOnly = $True
	#
	# Path
	#
	$Path.AutoSizeMode = 'Fill'
	$Path.HeaderText = 'Path'
	$Path.Name = 'Path'
	$Path.ReadOnly = $True
	#
	# Name
	#
	$Name.AutoSizeMode = 'AllCells'
	$Name.HeaderText = 'Name'
	$Name.Name = 'Name'
	$Name.ReadOnly = $True
	$Name.Width = 71
	#
	# Select
	#
	$Select.AutoSizeMode = 'AllCells'
	$Select.Name = 'Select'
	$Select.Width = 53
	#
	# Date
	#
	$Date.AutoSizeMode = 'AllCells'
	$Date.HeaderText = 'Date'
	$Date.Name = 'Date'
	$Date.ReadOnly = $True
	$Date.Width = 63
	#
	# PackageID
	#
	$PackageID.AutoSizeMode = 'AllCells'
	$PackageID.HeaderText = 'ID'
	$PackageID.Name = 'PackageID'
	$PackageID.ReadOnly = $True
	$PackageID.Width = 48
	#
	# PackageVersion
	#
	$PackageVersion.AutoSizeMode = 'AllCells'
	$PackageVersion.HeaderText = 'Version'
	$PackageVersion.Name = 'PackageVersion'
	$PackageVersion.ReadOnly = $True
	$PackageVersion.Width = 80
	#
	# PackageName
	#
	$PackageName.AutoSizeMode = 'Fill'
	$PackageName.HeaderText = 'Name'
	$PackageName.Name = 'PackageName'
	$PackageName.ReadOnly = $True
	#
	# Selected
	#
	$Selected.AutoSizeMode = 'AllCells'
	$Selected.HeaderText = 'Selected'
	$Selected.Name = 'Selected'
	$Selected.Width = 68
	#
	# checkboxUseAProxyServer
	#
	$checkboxUseAProxyServer.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$checkboxUseAProxyServer.ForeColor = [System.Drawing.Color]::White 
	$checkboxUseAProxyServer.Location = New-Object System.Drawing.Point(41, 152)
	$checkboxUseAProxyServer.Margin = '4, 4, 4, 4'
	$checkboxUseAProxyServer.Name = 'checkboxUseAProxyServer'
	$checkboxUseAProxyServer.Size = New-Object System.Drawing.Size(291, 31)
	$checkboxUseAProxyServer.TabIndex = 27
	$checkboxUseAProxyServer.Text = 'Use A Proxy Server'
	$checkboxUseAProxyServer.UseCompatibleTextRendering = $True
	$checkboxUseAProxyServer.UseVisualStyleBackColor = $True
	#
	# CustomPackageBrowse
	#
	#
	# Win32Package
	#
	$Win32Package.AutoSizeMode = 'DisplayedCells'
	$Win32Package.HeaderText = 'Package Name'
	$Win32Package.Name = 'Win32Package'
	$Win32Package.Width = 123
	#
	# PackageDetails
	#
	$PackageDetails.AutoSizeMode = 'Fill'
	$PackageDetails.HeaderText = 'Description'
	$PackageDetails.Name = 'PackageDetails'
	#
	# DPSelected
	#
	$DPSelected.AutoSizeMode = 'ColumnHeader'
	$DPSelected.HeaderText = 'Selected'
	$DPSelected.Name = 'DPSelected'
	$DPSelected.Width = 65
	#
	# DPName
	#
	$DPName.AutoSizeMode = 'Fill'
	$DPName.HeaderText = 'Distribution Point Name'
	$DPName.Name = 'DPName'
	#
	# DPGSelected
	#
	$DPGSelected.AutoSizeMode = 'ColumnHeader'
	$DPGSelected.HeaderText = 'Selected'
	$DPGSelected.Name = 'DPGSelected'
	$DPGSelected.Width = 65
	#
	# DPGName
	#
	$DPGName.AutoSizeMode = 'Fill'
	$DPGName.HeaderText = 'Distribution Point Group Name'
	$DPGName.Name = 'DPGName'
	#
	# Make
	#
	$Make.AutoSizeMode = 'AllCells'
	$Make.HeaderText = 'Make'
	$Make.MinimumWidth = 60
	$Make.Name = 'Make'
	$Make.Width = 68
	#
	# Model
	#
	$Model.AutoSizeMode = 'AllCells'
	$Model.HeaderText = 'Model'
	$Model.Name = 'Model'
	$Model.Width = 74
	#
	# Baseboard
	#
	$Baseboard.AutoSizeMode = 'AllCells'
	$Baseboard.HeaderText = 'BaseBoard'
	$Baseboard.Name = 'Baseboard'
	$Baseboard.Width = 98
	#
	# Platform
	#
	$Platform.AutoSizeMode = 'AllCells'
	$System_Windows_Forms_DataGridViewCellStyle_12 = New-Object 'System.Windows.Forms.DataGridViewCellStyle'
	$System_Windows_Forms_DataGridViewCellStyle_12.ForeColor = [System.Drawing.Color]::Black 
	$Platform.DefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_12
	$Platform.DisplayStyle = 'ComboBox'
	$Platform.HeaderText = 'Platform'
	[void]$Platform.Items.Add('ConfigMgr')
	[void]$Platform.Items.Add('MDT')
	$Platform.Name = 'Platform'
	$Platform.Visible = $False
	#
	# OperatingSystem
	#
	$OperatingSystem.AutoSizeMode = 'AllCells'
	$OperatingSystem.DefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_12
	$OperatingSystem.DisplayStyle = 'ComboBox'
	$OperatingSystem.HeaderText = 'Operating System'
	[void]$OperatingSystem.Items.Add('Windows 10 2004')
	[void]$OperatingSystem.Items.Add('Windows 10 1909')
	[void]$OperatingSystem.Items.Add('Windows 10 1903')
	[void]$OperatingSystem.Items.Add('Windows 10 1809')
	[void]$OperatingSystem.Items.Add('Windows 10 1803')
	[void]$OperatingSystem.Items.Add('Windows 10 1709')
	[void]$OperatingSystem.Items.Add('Windows 10 1703')
	[void]$OperatingSystem.Items.Add('Windows 10 1607')
	[void]$OperatingSystem.Items.Add('Windows 10')
	$OperatingSystem.Name = 'OperatingSystem'
	$OperatingSystem.Width = 127
	#
	# Architecture
	#
	$Architecture.AutoSizeMode = 'ColumnHeader'
	$Architecture.DefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_12
	$Architecture.DisplayStyle = 'ComboBox'
	$Architecture.HeaderText = 'Architecture'
	[void]$Architecture.Items.Add('x86')
	[void]$Architecture.Items.Add('x64')
	$Architecture.Name = 'Architecture'
	$Architecture.Width = 92
	#
	# Revision
	#
	$Revision.AutoSizeMode = 'AllCells'
	$Revision.HeaderText = 'Version'
	$Revision.Name = 'Revision'
	$Revision.Width = 80
	#
	# SourceDirectory
	#
	$SourceDirectory.AutoSizeMode = 'Fill'
	$SourceDirectory.HeaderText = 'Source Directory'
	$SourceDirectory.Name = 'SourceDirectory'
	#
	# Browse
	#
	$System_Windows_Forms_DataGridViewCellStyle_13 = New-Object 'System.Windows.Forms.DataGridViewCellStyle'
	$System_Windows_Forms_DataGridViewCellStyle_13.Alignment = 'MiddleCenter'
	$System_Windows_Forms_DataGridViewCellStyle_13.BackColor = [System.Drawing.Color]::FromArgb(255, 224, 224, 224)
	$System_Windows_Forms_DataGridViewCellStyle_13.Font = [System.Drawing.Font]::new('Segoe UI', '9', [System.Drawing.FontStyle]'Bold')
	$System_Windows_Forms_DataGridViewCellStyle_13.ForeColor = [System.Drawing.Color]::Black 
	$Browse.DefaultCellStyle = $System_Windows_Forms_DataGridViewCellStyle_13
	$Browse.FlatStyle = 'Popup'
	$Browse.HeaderText = 'Browse'
	$Browse.Name = 'Browse'
	$Browse.ReadOnly = $True
	$Browse.Resizable = 'False'
	$Browse.Text = '...'
	$Browse.UseColumnTextForButtonValue = $True
	$Browse.Width = 80
	#
	# ModelSelected
	#
	$ModelSelected.HeaderText = 'Selected'
	$ModelSelected.Name = 'ModelSelected'
	$ModelSelected.SortMode = 'Automatic'
	$ModelSelected.Width = 87
	#
	# Manufacturer
	#
	$Manufacturer.HeaderText = 'Manufacturer'
	$Manufacturer.Name = 'Manufacturer'
	$Manufacturer.ReadOnly = $True
	$Manufacturer.Width = 119
	#
	# ModelName
	#
	$ModelName.AutoSizeMode = 'Fill'
	$ModelName.HeaderText = 'Model'
	$ModelName.Name = 'ModelName'
	$ModelName.ReadOnly = $True
	#
	# WindowsVersion
	#
	$WindowsVersion.HeaderText = 'Windows Version'
	$WindowsVersion.Name = 'WindowsVersion'
	$WindowsVersion.Width = 143
	#
	# WindowsArchitecture
	#
	$WindowsArchitecture.HeaderText = 'Architecture'
	$WindowsArchitecture.Name = 'WindowsArchitecture'
	$WindowsArchitecture.Width = 111
	#
	# KnownModel
	#
	$KnownModel.HeaderText = 'Known Model'
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
AAEAAAD/////AQAAAAAAAAAMAgAAAFFTeXN0ZW0uRHJhd2luZywgVmVyc2lvbj00LjAuMC4wLCBD
dWx0dXJlPW5ldXRyYWwsIFB1YmxpY0tleVRva2VuPWIwM2Y1ZjdmMTFkNTBhM2EFAQAAABVTeXN0
ZW0uRHJhd2luZy5CaXRtYXABAAAABERhdGEHAgIAAAAJAwAAAA8DAAAAagEAAAKJUE5HDQoaCgAA
AA1JSERSAAAADwAAABAIBgAAAMlWJQQAAAAEZ0FNQQAAsY8L/GEFAAAACXBIWXMAAAsMAAALDAE/
QCLIAAAAB3RJTUUH5AUZDQYFihikCwAAAPlJREFUOE+tks8KAWEUxWfjCaTJK3gRWw+hiOIJNAtl
IVlMKGV2VsrKg0i22JlByhOIc3SvuX0zdk796vvOPXe+f+P9VUEQFMEQHMARjEBJyr+FUAPE4OWQ
gJbEskJxZsK/WEg8FcymE3J5gjo4g660fc+Yt1XLQLIncAe+NvNy8hqUveQi44XazFulsQNjGVsq
oOp4sTbzOWhsZN6TOeG4AHjb6pFEm/mOaq7F64OtjJdSs0xZY7EE7JdX4nPFmvGVKyh/milMWqZI
VqAMbsZTOtKWCubcCT2cOYkknhWKbXAxYYVbza7oCiEfhIA/Du9iAtIz/kee9wa6m1b2YpxqlQAA
AABJRU5ErkJgggs='))
	#endregion
	$KnownModel.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$KnownModel.Name = 'KnownModel'
	$KnownModel.Resizable = 'True'
	$KnownModel.SortMode = 'Automatic'
	$KnownModel.Width = 122
	#
	# SearchResult
	#
	$SearchResult.HeaderText = 'SearchResult'
	$SearchResult.Name = 'SearchResult'
	$SearchResult.Visible = $False
	#
	# HPCatalogueSelected
	#
	$HPCatalogueSelected.HeaderText = 'Selected'
	$HPCatalogueSelected.Name = 'HPCatalogueSelected'
	$HPCatalogueSelected.SortMode = 'Automatic'
	$HPCatalogueSelected.Width = 87
	#
	# HPSoftPaqTitle
	#
	$HPSoftPaqTitle.AutoSizeMode = 'AllCells'
	$HPSoftPaqTitle.HeaderText = 'SoftPaq'
	$HPSoftPaqTitle.Name = 'HPSoftPaqTitle'
	$HPSoftPaqTitle.Width = 83
	#
	# HPCatalogueDescription
	#
	$HPCatalogueDescription.AutoSizeMode = 'Fill'
	$HPCatalogueDescription.HeaderText = 'Title'
	$HPCatalogueDescription.Name = 'HPCatalogueDescription'
	$HPCatalogueDescription.Resizable = 'True'
	#
	# SoftPaqVersion
	#
	$SoftPaqVersion.HeaderText = 'Version'
	$SoftPaqVersion.Name = 'SoftPaqVersion'
	$SoftPaqVersion.Width = 80
	#
	# Created
	#
	$Created.HeaderText = 'Modified Date'
	$Created.Name = 'Created'
	$Created.Width = 124
	#
	# HPCatalogueSeverity
	#
	$HPCatalogueSeverity.HeaderText = 'Severity'
	$HPCatalogueSeverity.Name = 'HPCatalogueSeverity'
	$HPCatalogueSeverity.Width = 84
	#
	# PackageCreated
	#
	$PackageCreated.HeaderText = 'Package Created'
	#region Binary Data
	$Formatter_binaryFomatter = New-Object System.Runtime.Serialization.Formatters.Binary.BinaryFormatter
	$System_IO_MemoryStream = New-Object System.IO.MemoryStream (,[byte[]][System.Convert]::FromBase64String('
AAEAAAD/////AQAAAAAAAAAMAgAAAFFTeXN0ZW0uRHJhd2luZywgVmVyc2lvbj00LjAuMC4wLCBD
dWx0dXJlPW5ldXRyYWwsIFB1YmxpY0tleVRva2VuPWIwM2Y1ZjdmMTFkNTBhM2EFAQAAABVTeXN0
ZW0uRHJhd2luZy5CaXRtYXABAAAABERhdGEHAgIAAAAJAwAAAA8DAAAAagEAAAKJUE5HDQoaCgAA
AA1JSERSAAAADwAAABAIBgAAAMlWJQQAAAAEZ0FNQQAAsY8L/GEFAAAACXBIWXMAAAsMAAALDAE/
QCLIAAAAB3RJTUUH5AUZDQYFihikCwAAAPlJREFUOE+tks8KAWEUxWfjCaTJK3gRWw+hiOIJNAtl
IVlMKGV2VsrKg0i22JlByhOIc3SvuX0zdk796vvOPXe+f+P9VUEQFMEQHMARjEBJyr+FUAPE4OWQ
gJbEskJxZsK/WEg8FcymE3J5gjo4g660fc+Yt1XLQLIncAe+NvNy8hqUveQi44XazFulsQNjGVsq
oOp4sTbzOWhsZN6TOeG4AHjb6pFEm/mOaq7F64OtjJdSs0xZY7EE7JdX4nPFmvGVKyh/milMWqZI
VqAMbsZTOtKWCubcCT2cOYkknhWKbXAxYYVbza7oCiEfhIA/Du9iAtIz/kee9wa6m1b2YpxqlQAA
AABJRU5ErkJgggs='))
	#endregion
	$PackageCreated.Image = $Formatter_binaryFomatter.Deserialize($System_IO_MemoryStream)
	$Formatter_binaryFomatter = $null
	$System_IO_MemoryStream = $null
	$PackageCreated.Name = 'PackageCreated'
	$PackageCreated.SortMode = 'Automatic'
	$PackageCreated.ToolTipText = 'Flag if corresponding package exists in Configuration Manager'
	$PackageCreated.Width = 137
	#
	# SoftPaqURL
	#
	$SoftPaqURL.HeaderText = 'URL'
	$SoftPaqURL.Name = 'SoftPaqURL'
	$SoftPaqURL.Visible = $False
	#
	# SilentSetup
	#
	$SilentSetup.HeaderText = 'Silent Setup'
	$SilentSetup.Name = 'SilentSetup'
	$SilentSetup.Visible = $False
	#
	# BaseBoardModels
	#
	$BaseBoardModels.HeaderText = 'BaseBoard'
	$BaseBoardModels.Name = 'BaseBoardModels'
	$BaseBoardModels.Visible = $False
	#
	# SoftPaqMatch
	#
	$SoftPaqMatch.HeaderText = 'Match'
	$SoftPaqMatch.Name = 'SoftPaqMatch'
	$SoftPaqMatch.Visible = $False
	#
	# SupportedBuild
	#
	$SupportedBuild.HeaderText = 'SupportedBuild'
	$SupportedBuild.Name = 'SupportedBuild'
	$SupportedBuild.Visible = $False
	$AboutPanelLeft.ResumeLayout()
	$AboutPanelRight.ResumeLayout()
	$AboutTab.ResumeLayout()
	$LogPanel.ResumeLayout()
	$LogTab.ResumeLayout()
	$groupbox2.ResumeLayout()
	$CustomPkgGroup.ResumeLayout()
	$CustomPkgPanel.ResumeLayout()
	$PkgImporting.ResumeLayout()
	$CustPkgTab.ResumeLayout()
	$WebDiagsPanel.ResumeLayout()
	$ConfigWSDiagTab.ResumeLayout()
	$PackagePanel.ResumeLayout()
	$PackageUpdatePanel.ResumeLayout()
	$ConfigMgrDriverTab.ResumeLayout()
	$MDTScriptGroup.ResumeLayout()
	$FolderStructureGroup.ResumeLayout()
	$MDTSettingsPanel.ResumeLayout()
	$MDTTab.ResumeLayout()
	$groupbox5.ResumeLayout()
	$groupbox6.ResumeLayout()
	$groupbox7.ResumeLayout()
	$panel1.ResumeLayout()
	$IntuneTab.ResumeLayout()
	$FallbackPkgGroup.ResumeLayout()
	$DPGroupTab.ResumeLayout()
	$DPointTab.ResumeLayout()
	$DPSelectionsTabs.ResumeLayout()
	$DPGroupBox.ResumeLayout()
	$PackageOptionsTab.ResumeLayout()
	$groupbox1.ResumeLayout()
	$PackageCreation.ResumeLayout()
	$ConfigMgrDPOptionsTab.ResumeLayout()
	$SettingsTabs.ResumeLayout()
	$ConfigMgrTab.ResumeLayout()
	$TabControlGroup.ResumeLayout()
	$groupbox4.ResumeLayout()
	$tabpage3.ResumeLayout()
	$ProxyGroupBox.ResumeLayout()
	$SchedulingGroupBox.ResumeLayout()
	$tabpage2.ResumeLayout()
	$StoageGroupBox.ResumeLayout()
	$tabpage1.ResumeLayout()
	$tabcontrol1.ResumeLayout()
	$CommonTab.ResumeLayout()
	$HPSoftPaqGridPopup.ResumeLayout()
	$HPCatalog.ResumeLayout()
	$tabcontrol2.ResumeLayout()
	$OEMCatalogs.ResumeLayout()
	$ManufacturerSelectionGroup.ResumeLayout()
	$DeploymentGroupBox.ResumeLayout()
	$OSGroup.ResumeLayout()
	$XMLLoading.ResumeLayout()
	$ModelDriverTab.ResumeLayout()
	$DriverAppTab.ResumeLayout()
	$PlatformPanel.ResumeLayout()
	$MakeModelTab.ResumeLayout()
	$SelectionTabs.ResumeLayout()
	$LogoPanel.ResumeLayout()
	$MainForm.ResumeLayout()
	#endregion Generated Form Code

	#----------------------------------------------

	#Save the initial state of the form
	$InitialFormWindowState = $MainForm.WindowState
	#Init the OnLoad event to correct the initial state of the form
	$MainForm.add_Load($Form_StateCorrection_Load)
	#Clean up the control events
	$MainForm.add_FormClosed($Form_Cleanup_FormClosed)
	#Store the control values when form is closing
	$MainForm.add_Closing($Form_StoreValues_Closing)
	#Show the Form
	return $MainForm.ShowDialog()

}
#endregion Source: MainForm.psf

#region Source: Globals.ps1
	function Get-ScriptDirectory {
		[OutputType([string])]
		param ()
		if ($null -ne $hostinvocation) {
			Split-Path $hostinvocation.MyCommand.path
		} else {
			Split-Path $script:MyInvocation.MyCommand.Path
		}
	}
	
	# Set Temp & Log Location	
	[string]$global:TempDirectory = Join-Path $(Get-ScriptDirectory) -ChildPath "Temp"
	[string]$global:LogDirectory = Join-Path $(Get-ScriptDirectory) -ChildPath "Logs"
	[string]$global:SettingsDirectory = Join-Path $(Get-ScriptDirectory) -ChildPath "Settings"
	
	# Create Temp Folder 
	if ((Test-Path -Path $global:TempDirectory) -eq $false) {
		New-Item -Path $global:TempDirectory -ItemType Dir | Out-Null
	}
	# Create Logs Folder 
	if ((Test-Path -Path $global:LogDirectory) -eq $false) {
		New-Item -Path $global:LogDirectory -ItemType Dir | Out-Null
	}
	# Create Settings Folder 
	if ((Test-Path -Path $global:SettingsDirectory) -eq $false) {
		New-Item -Path $global:SettingsDirectory -ItemType Dir | Out-Null
	}
	
	# Logging Function
	function global:Write-LogEntry {
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
			[string]$FileName = "DriverAutomationTool.log",
			[parameter(Mandatory = $false, HelpMessage = "Variable for skipping verbose output to the GUI.")]
			[ValidateNotNullOrEmpty()]
			[boolean]$SkipGuiLog
		)
		# Determine log file location
		$global:LogFilePath = Join-Path -Path $global:LogDirectory -ChildPath $FileName
		
		# Construct time stamp for log entry
		$Time = -join @((Get-Date -Format "HH:mm:ss.fff"), " ", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
		
		# Construct date for log entry
		$Date = (Get-Date -Format "MM-dd-yyyy")
		
		# Construct context for log entry
		$Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
		
		# Construct final log entry
		$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""DriverAutomationTool"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
		
		# Add value to log file
		try {
			Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $global:LogFilePath -ErrorAction Stop
		} catch [System.Exception] {
			Write-Warning -Message "Unable to append log entry to DriverAutomationTool.log file. Error message: $($_.Exception.Message)"
		}
		
		# GUI Logging Section	
		if ($SkipGuiLog -ne $true) {
			# Set Error GUI Log Window Colour
			if ($Severity -ne "1") {
				$ErrorsOccurred.Forecolor = "Maroon"
				$ErrorsOccurred.Text = "Yes"
			}
			
			# Add GUI Log Window Section Block
			if ($Value -like "*==*==*") {
				$ProgressListBox.Items.Add(" ")
			}
			
			# Update GUI Log Window
			$ProgressListBox.Items.Add("$Value")
			$ProgressListBox.SelectedIndex = $ProgressListBox.Items.Count - 1;
			$ProgressListBox.SelectedIndex = -1;
		}
	}
	
	function global:Write-ErrorOutput {
		param
		(
			[parameter(Mandatory = $true)]
			[string]$Message,
			[parameter(Mandatory = $true)]
			[int]$Severity
		)
		
		global:Write-LogEntry -Value "======== Errors(s) Occurred ========" -Severity $Severity
		global:Write-LogEntry -Value $Message -Severity $Severity
		global:Write-LogEntry -Value " " -Severity $Severity
		#$ProgressListBox.ForeColor = "Maroon"
		$ErrorsOccurred.ForeColor = "Maroon"
		$ErrorsOccurred.Text = "Yes"
		$SelectionTabs.SelectedTab = $LogTab
	}
	
	#region GlobalVariables
	
	# // =================== GLOBAL VARIABLES ====================== //
	# Requires TLS 1.2
	
	# Script Build Numbers
	$ScriptRelease = "6.4.8"
	$ScriptBuildDate = "2020-06-25"
	$NewRelease = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data//DriverAutomationToolRev.txt" -UseBasicParsing).Content
	$ReleaseNotesURL = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/DriverAutomationToolNotes.txt"
	
	# Windows Version Hash Table
	$WindowsBuildHashTable = @{`
		2004 = "10.0.19041.1";`
		1909 = "10.0.18363.1";`
		1903 = "10.0.18362.1";`
		1809 = "10.0.17763.1";`
		1803 = "10.0.17134.1";`
		1709 = "10.0.16299.15";`
		1703 = "10.0.15063.0";`
		1607 = "10.0.14393.0"; `
		
	};
	
	$CheckIcon = Join-Path (Get-Location) -ChildPath "Images\Check.png"
	$UnCheckedIcon = Join-Path (Get-Location) -ChildPath "Images\UnChecked.png"
	
	# // =================== DELL VARIABLES ================ //
	# Define Dell Download Sources
	$DellDownloadList = "https://downloads.dell.com/published/Pages/index.html"
	$DellDownloadBase = "https://downloads.dell.com"
	$DellDriverListURL = "https://en.community.dell.com/techcenter/enterprise-client/w/wiki/2065.dell-command-deploy-driver-packs-for-enterprise-client-os-deployment"
	$DellBaseURL = "https://en.community.dell.com"
	$Dell64BIOSUtil = "https://dl.dell.com/FOLDER06137299M/4/Flash64W_ZPE.exe"
	
	# Define Dell Download Sources
	$DellXMLCabinetSource = "https://downloads.dell.com/catalog/DriverPackCatalog.cab"
	$DellCatalogSource = "https://downloads.dell.com/catalog/CatalogPC.cab"
	
	# Define Dell Cabinet/XL Names and Paths
	$DellCabFile = [string]($DellXMLCabinetSource | Split-Path -Leaf)
	$DellCatalogFile = [string]($DellCatalogSource | Split-Path -Leaf)
	$DellXMLFile = $DellCabFile.TrimEnd(".cab")
	$DellXMLFile = $DellXMLFile + ".xml"
	$DellCatalogXMLFile = $DellCatalogFile.TrimEnd(".cab") + ".xml"
	
	# Define Dell Global Variables
	New-Variable -Name "DellCatalogXML" -Value $null -Scope Global
	New-Variable -Name "DellModelXML" -Value $null -Scope Global
	New-Variable -Name "DellModelCabFiles" -Value $null -Scope Global
	
	# // =================== HP VARIABLES ================ //
	
	# Define HP Download Sources
	$HPXMLCabinetSource = 'https://ftp.hp.com/pub/caps-softpaq/cmit/HPClientDriverPackCatalog.cab'
	$HPSoftPaqSource = 'https://ftp.hp.com/pub/softpaq/'
	$HPPlatFormList = 'https://ftp.hp.com/pub/caps-softpaq/cmit/imagepal/ref/platformList.cab'
	$HPSoftPaqCab = "https://ftp.hp.com/pub/softlib/software/sms_catalog/HpCatalogForSms.latest.cab"
	
	# Define HP Cabinet/XL Names and Paths
	$HPCabFile = [string]($HPXMLCabinetSource | Split-Path -Leaf)
	$HPXMLFile = $HPCabFile.TrimEnd(".cab")
	$HPXMLFile = $HPXMLFile + ".xml"
	$HPPlatformCabFile = [string]($HPPlatFormList | Split-Path -Leaf)
	$HPPlatformXMLFile = $HPPlatformCabFile.TrimEnd(".cab") + ".xml"
	$HPSoftPaqCabFile = [string]($HPSoftPaqCab | Split-Path -Leaf)
	$HPSoftPaqXMLFile = $HPSoftPaqCabFile.Replace(".latest.cab", ".xml")
	
	# Define HP Global Variables
	New-Variable -Name "HPModelSoftPaqs" -Value $null -Scope Global
	New-Variable -Name "HPModelXML" -Value $null -Scope Global
	New-Variable -Name "HPPlatformXML" -Value $null -Scope Global
	New-Variable -Name "HPSoftPaqXML" -Value $null -Scope Global
	New-Variable -Name "HPSoftPaqList" -Value $null -Scope Global
	
	# HP Softpaq Downloads Hashtable
	$global:HPSoftPaqDownloads = @{
	}
	
	# // =================== LENOVO VARIABLES ================ //
	
	# Define Lenovo Download Sources
	#$LenovoXMLSource = "https://download.lenovo.com/cdrt/td/catalog.xml"
	$LenovoXMLSource = "https://download.lenovo.com/cdrt/td/catalogv2.xml"
	
	# Define Lenovo Cabinet/XL Names and Paths
	$LenovoXMLFile = [string]($LenovoXMLSource | Split-Path -Leaf)
	$LenovoBiosBase = "https://download.lenovo.com/catalog/"
	
	# Define Lenovo Global Variables
	New-Variable -Name "LenovoModelDrivers" -Value $null -Scope Global
	New-Variable -Name "LenovoModelXML" -Value $null -Scope Global
	New-Variable -Name "LenovoModelType" -Value $null -Scope Global
	New-Variable -Name "LenovoSystemSKU" -Value $null -Scope Global
	
	# // =================== MICROSOFT VARIABLES ================ //
	# Define Microsoft Download Sources
	$MicrosoftXMLSource = "https://raw.githubusercontent.com/maurice-daly/DriverAutomationTool/master/Data/MSProducts.xml"
	$MicrosoftBaseURL = "https://aka.ms/"
	
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
	New-Variable -Name "PreviousDownload" -Value $null -Scope Global
	New-Variable -Name "SystemSKU" -Value $null -Scope Global
	
	# MDT PS Commandlets
	$MDTPSCommandlets = "C:\Program Files\Microsoft Deployment Toolkit\bin\MicrosoftDeploymentToolkit.psd1"
	
	# MDT Deployment Share Array
	$MDTDeploymentShareNames = New-Object System.Collections.Generic.List[System.Object]
	$ExportMDTShareNames = New-Object System.Collections.Generic.List[System.Object]
	New-Variable -Name "MDTValidation" -Value $null -Scope Global
	
	# Proxy Validation Initial State
	$global:ProxySettingsSet = $false
	$global:ProxySettingsSet = $false
	$global:BitsOptions = @{
		RetryInterval = "60"
		RetryTimeout = "180"
		Priority = "Foreground"
	}
	
	# ConfigMgr Validation Initial State
	New-Variable -Name "ConfigMgrValidation" -Value $null -Scope Global
	
	# GraphAPI
	New-Variable -Name "AuthToken" -Value $null -Scope global
	
	# Import Intune PS module
	#Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath "Modules\IntuneWin32App.psd1")
	
	#endregion GlobalVariables
	
	function Set-Manufacturer {
		param (
			[parameter(Mandatory = $true, HelpMessage = "Provide the manufacturer name.")]
			[ValidateNotNullOrEmpty()]
			[string]$Make
		)
		switch -Wildcard ($Make) {
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
		Return $Make
	}
	
	function Set-ConfigMgrFolder {
		
		# Function used to set location of driver and BIOS packages within the SCCM package folder hierarchy 
		
		Set-Location -Path ($SiteCode + ":")
		if ($PackageRoot.Checked -eq $true) {
			$global:VendorBIOSFolder = ($SiteCode + ":" + "\Package")
			$global:VendorDriverFolder = ($SiteCode + ":" + "\Package")
			global:Write-LogEntry -Value "Info: Using Configuration Manager console root folder for packages " -Severity 1
		} elseif (($SpecifyCustomPath.Checked -eq $true) -and ((Test-Path -Path $CustPackageDest.text) -eq $false)) {
			$CustomPathDirCount = $CustPackageDest.text.split("\").count
			$CustomPathDirStep = 0
			While ($CustomPathDirCount -ne 0) {
				if (![string]::IsNullOrEmpty($CustPackageDest.text)) {
					if ($CustomPathDirStep -ne 0) {
						$CustPackagePath = $CustPackagePath + $CustPackageDest.text.split("\")[$CustomPathDirStep] + "\"
						global:Write-LogEntry -Value "Info: Creating custom package subfolder - $CustPackagePath " -Severity 1
					} elseif ($CustomPathDirStep -eq 0) {
						$CustPackagePath = $CustPackageDest.text.split("\")[$CustomPathDirStep] + "\"
						global:Write-LogEntry -Value "Info: Creating custom package root folder - $CustPackagePath " -Severity 1
					}
					if ((Test-Path -Path ($SiteCode + ":" + "\Package\" + $CustPackagePath.TrimEnd("\"))) -eq $false) {
						New-Item -Path ($SiteCode + ":" + "\Package\" + $CustPackagePath)
					}
				}
				$CustomPathDirStep++
				$CustomPathDirCount--
			}
			$global:VendorBIOSFolder = ($SiteCode + ":" + "\Package\" + $CustPackagePath.TrimEnd("\"))
			$global:VendorDriverFolder = ($SiteCode + ":" + "\Package\" + $CustPackagePath.TrimEnd("\"))
		} else {
			if ((Test-Path -Path ($SiteCode + ":" + "\Package" + "\BIOS Packages")) -eq $false) {
				New-Item -Path ($SiteCode + ":" + "\Package" + "\BIOS Packages")
			}
			if ((Test-Path -Path ($SiteCode + ":" + "\Package" + "\BIOS Packages" + "\$Make")) -eq $false) {
				New-Item -Path ($SiteCode + ":" + "\Package" + "\BIOS Packages" + "\$Make")
			}
			if ((Test-Path -Path ($SiteCode + ":" + "\Package" + "\Driver Packages")) -eq $false) {
				New-Item -Path ($SiteCode + ":" + "\Package" + "\Driver Packages")
			}
			if ((Test-Path -Path ($SiteCode + ":" + "\Package" + "\Driver Packages" + "\$Make")) -eq $false) {
				New-Item -Path ($SiteCode + ":" + "\Package" + "\Driver Packages" + "\$Make")
			}
			$global:VendorBIOSFolder = ($SiteCode + ":" + "\Package" + "\BIOS Packages" + "\$Make")
			$global:VendorDriverFolder = ($SiteCode + ":" + "\Package" + "\Driver Packages" + "\$Make")
			global:Write-LogEntry -Value "Info: Using Configuration Manager console BIOS package folder - $global:VendorBIOSFolder" -Severity 1
			global:Write-LogEntry -Value "Info: Using Configuration Manager console Driver package folder - $global:VendorDriverFolder" -Severity 1
		}
		Set-Location -Path $Global:TempDirectory
	}
	
	function Get-SiteCode ($SiteServer) {
		try {
			$SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop
			$SiteCodeError = $false
		} catch {
			global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
			$SiteCodeError = $true
		}
		if (($SiteCodeObjects -ne $null) -and ($SiteCodeError -ne $true)) {
			foreach ($SiteCodeObject in $SiteCodeObjects) {
				if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
					$global:SiteCode = $SiteCodeObject.SiteCode
					global:Write-LogEntry -Value "Info: Site Code Found: $($global:SiteCode)" -Severity 1
					$SiteCodeText.text = $global:SiteCode
				}
			}
		}
	}
	
	function Set-CompatibilityOptions {
		if ($DownloadComboBox.Text -eq "BIOS") {
			$PackagePathTextBox.Enabled = $false
			
			# Condition based on Lenovo products being enabled
			if ($global:LenovoDisable -eq $false) {
				$LenovoCheckBox.Enabled = $true
			}
			$MicrosoftCheckBox.Enabled = $false
			$DellCheckBox.Enabled = $true
			$HPCheckBox.Enabled = $true
			$CleanUnusedCheckBox.Enabled = $false
			$RemoveLegacyDriverCheckbox.Enabled = $false
			$RemoveLegacyBIOSCheckbox.Enabled = $true
		} elseif ($DownloadComboBox.Text -eq "All") {
			$MicrosoftCheckBox.Enabled = $false
		} else {
			if ($PlatformComboBox.SelectedItem -match "Download|Intune") {
				$OSComboBox.Enabled = $true
				$ArchitectureComboxBox.Enabled = $true
				$PackagePathTextBox.Enabled = $false
				Set-ConfigMgrOptions -OptionsEnabled $false
			} else {
				$PackagePathTextBox.Enabled = $true
				$OSComboBox.Enabled = $true
				$ArchitectureComboxBox.Enabled = $true
				$PackagePathTextBox.Enabled = $true
				Set-ConfigMgrOptions -OptionsEnabled $true
			}
		}
	}
	
	function Confirm-OSCompatibility {
		if ((-not ([string]::IsNullOrEmpty($OSComboBox.Text))) -and (-not ([string]::IsNullOrEmpty($ArchitectureComboxBox.Text)))) {
			Update-OSModelSuppport
		}
		if ($FindModelsButton.Enabled -eq $true) {
			Find-AvailableModels
			[int]$ModelCount = $MakeModelDataGrid.Rows.Count
		}
	}
	
	function Update-ModeList {
		param (
			[string]$SiteServer,
			[string]$SiteCode
		)
		
		# Validate all selections are made prior to starting model query
		if (((-not ([string]::IsNullOrEmpty($PlatformComboBox.Text))) -and (-not ([string]::IsNullOrEmpty($OSComboBox.Text))) -and (-not ([string]::IsNullOrEmpty($DownloadComboBox.Text))) -and (-not ([string]::IsNullOrEmpty($ArchitectureComboxBox.Text)))) -eq $true) {
			global:Write-LogEntry -Value "======== Querying Model List(s) ========" -Severity 1
			
			# Reset Product Listbox
			$HPCatalogModels.Items.Clear()
			$HPCatalogModels.Items.Add("All Generic Downloads")
			$MakeModelDataGrid.ClearSelection()
			$XMLLoadingLabel.Text = "Refreshing Model List"
			$XMLDownloadStatus.Text = "Please Wait..."
			$XMLLoading.Visible = $true
			$XMLDownloadStatus.Visible = $true
			$XMLLoadingLabel.Visible = $true
			Set-Location -Path $Global:TempDirectory
			Start-Sleep -Seconds 2
			
			# Set variable for WMI known models for ConfigMgr 
			if (($SiteCode -ne "N/A") -and (-not ([string]::IsNullOrEmpty($SiteCode))) -and ($ConfigMgrImport.text -eq "yes") -and ($PlatformComboBox.Text -match "ConfigMgr")) {
				$QueryKnownModels = $true
			} elseif ($IntuneKnownModels.SelectedItem -match "Yes") {
				$QueryKnownModels = $true
			} else {
				$QueryKnownModels = $false
			}
			
			if ($HPCheckBox.Checked -eq $true) {
				$HPProducts.Clear()
				$HPSoftpaqDataGrid.ClearSelection()
				if ((Test-Path -Path $(Join-Path -Path $global:TempDirectory -ChildPath $HPCabFile)) -eq $false) {
					global:Write-LogEntry -Value "======== Downloading HP Product List ========" -Severity 1
					# Download HP Model Cabinet File
					$XMLDownloadStatus.Text = "Downloading HP cabinet file"
					global:Write-LogEntry -Value "Info: Downloading HP driver pack cabinet file from $HPXMLCabinetSource" -Severity 1
					try {
						if ($global:ProxySettingsSet -eq $true) {
							Start-BitsTransfer -Source $HPXMLCabinetSource -Destination $global:TempDirectory @global:BitsProxyOptions
						} else {
							Start-BitsTransfer -Source $HPXMLCabinetSource -Destination $global:TempDirectory @global:BitsOptions
						}
						if ((Test-Path -Path $(Join-Path -Path $global:TempDirectory -ChildPath $HPXMLFile)) -eq $false) {
							# Expand Cabinet File
							global:Write-LogEntry -Value "Info: Expanding HP driver pack cabinet file: $HPXMLFile" -Severity 1
							$XMLDownloadStatus.Text = "Expanding HP cabinet file"
							Expand "$global:TempDirectory\$HPCabFile" -F:* "$global:TempDirectory" -R | Out-Null
						}
					} catch {
						global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
					}
				}
				
				# Read XML File
				if ($global:HPModelSoftPaqs -eq $null) {
					$XMLDownloadStatus.Text = "Reading HP XML file"
					global:Write-LogEntry -Value "Info: Reading driver pack XML file - $global:TempDirectory\$HPXMLFile" -Severity 1
					[xml]$global:HPModelXML = Get-Content -Path $(Join-Path -Path $global:TempDirectory -ChildPath $HPXMLFile) -Raw
					# Set XML Object
					$global:HPModelXML.GetType().FullName
					$global:HPModelSoftPaqs = $HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
				}
				
				if ((Test-Path -Path $(Join-Path -Path $global:TempDirectory -ChildPath $HPSoftPaqXMLFile)) -eq $false) {
					try {
						$XMLDownloadStatus.Text = "Downloading HP Softpaq cabinet file"
						if ((Test-Path -Path $global:TempDirectory\$HPSoftPaqCabFile) -eq $false) {
							global:Write-LogEntry -Value "======== Downloading HP SoftPaq List ========" -Severity 1
							# Download HP Model Cabinet File
							global:Write-LogEntry -Value "Info: Downloading HP softpaq cabinet file from $HPSoftPaqCab" -Severity 1
							if ($global:ProxySettingsSet -eq $true) {
								Start-BitsTransfer -Source $HPSoftPaqCab -Destination $global:TempDirectory @global:BitsProxyOptions
							} else {
								Start-BitsTransfer -Source $HPSoftPaqCab -Destination $global:TempDirectory @global:BitsOptions
							}
						}
						if ((Test-Path -Path $(Join-Path $global:TempDirectory -ChildPath $HPSoftPaqXMLFile)) -eq $false) {
							# Expand Cabinet File
							global:Write-LogEntry -Value "Info: Expanding HP softpaq cabinet file: $HPSoftPaqCabFile" -Severity 1
							Expand "$global:TempDirectory\$HPSoftPaqCabFile" -F:"*.XML" "$global:TempDirectory" -R | Out-Null
							$XMLDownloadStatus.Text = "Expanding HP Softpaq cabinet file"
							Start-Sleep -Seconds 5
						}
					} catch {
						global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
					}
				}
				
				# Read SoftPaq XML File
				if ((Test-Path -Path $(Join-Path $global:TempDirectory -ChildPath $HPSoftPaqXMLFile)) -eq $true) {
					try {
						
						if ([string]::IsNullOrEmpty($global:HPSoftPaqXML)) {
							
							$XMLDownloadStatus.Text = "Reading HP SoftPaq XML"
							global:Write-LogEntry -Value "Info: Reading softpaq XML file - $global:TempDirectory\$HPSoftPaqXMLFile" -Severity 1
							[xml]$global:HPSoftPaqXML = Get-Content -Path $(Join-Path -Path $global:TempDirectory -ChildPath $HPSoftPaqXMLFile) -Raw
							
							# HP Version Swtich
							switch -wildcard ($OSComboBox.Text) {
								"Windows 10*" {
									$OSRelease = [version]"10.0"
								}
							}
							
							$XMLDownloadStatus.Text = "Parsing Downloaded HP SoftPaq XML"
							
							# Set XML Object
							$global:HPSoftPaqXML.GetType().FullName
							$global:HPSoftPaqList = $global:HPSoftPaqXML.SystemsManagementCatalog.SoftwareDistributionPackage | Where-Object {
								$_.IsInstallable.AND.OR.AND.WindowsVersion.MajorVersion -match $OSRelease.Major
							}
							$global:HPSoftPaqList = $global:HPSoftPaqList | Where-Object {
								$_.Properties.PublicationState -ne "Expired"
							}
						}
						
						# Enable HP SoftPaq Views & Buttons
						$ResetSoftPaqSelection.enabled = $true
						$FindSoftPaq.enabled = $true
						$HPSearchText.enabled = $true
						$HPSoftpaqDataGrid.enabled = $true
						$HPCatalogModels.Enabled = $true
						$DownloadSoftPaqs.Enabled = $true
						$RefreshSoftPaqSelection.Enabled = $true
						$SelectAllSoftPaqs.Enabled = $true
						
					} catch {
						global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
					}
				} elseif ((Test-Path -Path $(Join-Path $global:TempDirectory -ChildPath $HPSoftPaqXMLFile)) -eq $false) {
					# XML Download Failure
					global:Write-LogEntry -Value "Warning: Failed to find HP XML file: $HPSoftPaqCabFile" -Severity 2
				}
				
				# Find Models Contained Within Downloaded XML
				if ($OSComboBox.Text -like "Windows 10 *") {
					# Windows 10 build query
					global:Write-LogEntry -Value "Info: Searching HP XML with OS variables - Windows*$(($OSComboBox.Text).split(' ')[1])*$(($ArchitectureComboxBox.Text).Split(' ')[0])*$((($OSComboBox.Text).split(' ')[2]).Trim())*" -Severity 1
					$HPModels = $global:HPModelSoftPaqs | Where-Object {
						($_.OSName -like "Windows*$(($OSComboBox.Text).split(' ')[1])*$(($ArchitectureComboxBox.Text).Split(' ')[0])*$((($OSComboBox.Text).split(' ')[2]).Trim())*")
					} | Select-Object SystemName
				} else {
					# Legacy Windows version query
					global:Write-LogEntry -Value "Info: Searching HP XML with OS variables - Windows*$(($OSComboBox.Text).split(' ')[1])*$(($ArchitectureComboxBox.Text).Split(' ')[0])*" -Severity 1
					$HPModels = $global:HPModelSoftPaqs | Where-Object {
						($_.OSName -like "Windows*$(($OSComboBox.Text).split(' ')[1])*$(($ArchitectureComboxBox.Text).Split(' ')[0])*")
					} | Select-Object SystemName
				}
				if ($HPModels -ne $null) {
					$XMLDownloadStatus.Text = "Adding $($HPModels.Count) HP models"
					foreach ($Model in $HPModels.SystemName) {
						$Model = $Model -replace "Win[^;]*", " "
						$Model = $Model.TrimStart("HP")
						$Model.Trim()
						if ($Model -like "*(*)*") {
							$Model = $Model.Split("(")[0]
						}
						if ($HPProducts -notcontains $Model) {
							$HPProducts.Add($Model) | Out-Null
						}
					}
					$StartDownloadButton.Enabled = $true
				}
				$HPProducts = $HPProducts | Sort-Object
				if ($HPProducts -ne $null) {
					foreach ($HPModel in $HPProducts) {
						$MakeModelDataGrid.Rows.Add($false, "Hewlett-Packard", $HPModel, $OSComboBox.Text, $ArchitectureComboxBox.Text)
						$HPCatalogModels.Items.Add($HPModel.Trim())
					}
				}
				# Add Known HP Models
				if ($QueryKnownModels -eq $true) {
					if (-not ([string]::IsNullOrEmpty($SiteServer))) {
						$HPKnownModels = ($HPKnownModels = Get-WmiObject -ComputerName $SiteServer -Namespace "root\SMS\site_$SiteCode" -Class SMS_G_System_COMPUTER_SYSTEM | Select-Object -Property Manufacturer, Model | Where-Object {
								(($_.Manufacturer -match "HP") -or ($_.Manufacturer -match "Hewlett-Packard")) -and ($_.Model -notmatch "Proliant")
							}).Model | Sort-Object | Get-Unique -AsString
					}
					# Add model to ArrayList if not present
					if ($HPKnownModels.Count -gt 0) {
						foreach ($HPKnownModel in $HPKnownModels) {
							# Cater for HP description variations
							$HPKnownModel = $HPKnownModel.Replace("HP", "").Trim()
							$HPKnownModel = $HPKnownModel.Replace("COMPAQ", "").Trim()
							$HPKnownModel = $HPKnownModel.Replace("Hp", "").Trim()
							$HPKnownModel = $HPKnownModel.Replace("Compaq", "").Trim()
							$HPKnownModel = $HPKnownModel.Replace("SFF", "Small Form Factor")
							$HPKnownModel = $HPKnownModel.Replace("USDT", "Desktop")
							$HPKnownModel = $HPKnownModel.Replace(" TWR", " Tower")
							if ($HPKnownModel -match "35W") {
								$HPKnownModel = $HPKnownModel.TrimEnd("35W")
							}
							if ($HPKnownModel -like "* PC") {
								$HPKnownModel = $HPKnownModel.TrimEnd("PC").Trim()
							}
							if ($HPKnownModel -gt $null) {
								if ($HPKnownProducts -notcontains $HPKnownModel) {
									global:Write-LogEntry -Value "Info: Adding $HPKnownModel to HP known models" -Severity 1
									$HPKnownProducts.Add($HPKnownModel) | Out-Null
								}
							}
						}
						global:Write-LogEntry -Value "Info: Found: $(($HPKnownProducts).count) known HP models" -Severity 1
					}
				}
				if (($HPModels).Count -gt "0") {
					global:Write-LogEntry -Value "Info: Found $(($HPModels).count) HP model driver packs for $($OSComboBox.text) $($ArchitectureComboxBox.text)" -Severity 1
				}
			} else {
				# Disable HP SoftPaq Views & Buttons
				$ResetSoftPaqSelection.enabled = $false
				$FindSoftPaq.enabled = $false
				$HPSearchText.enabled = $false
				$HPSoftpaqDataGrid.enabled = $false
				$HPCatalogModels.Enabled = $false
				$DownloadSoftPaqs.Enabled = $false
				$RefreshSoftPaqSelection.Enabled = $false
				$SelectAllSoftPaqs.Enabled = $false
			}
			if ($DellCheckBox.Checked -eq $true) {
				$DellProducts.Clear()
				
				if ((Test-Path -Path $global:TempDirectory\$DellCabFile) -eq $false) {
					$XMLDownloadStatus.Text = "Downloading Dell cabinet file"
					global:Write-LogEntry -Value "Info: Downloading Dell product list" -Severity 1
					global:Write-LogEntry -Value "Info: Downloading Dell product cabinet file from $DellXMLCabinetSource" -Severity 1
					# Download Dell Model Cabinet File
					try {
						if ($global:ProxySettingsSet -eq $true) {
							Start-BitsTransfer -Source $DellXMLCabinetSource -Destination $global:TempDirectory @global:BitsProxyOptions
						} else {
							Start-BitsTransfer -Source $DellXMLCabinetSource -Destination $global:TempDirectory @global:BitsOptions
						}
						if ((Test-Path -Path $global:TempDirectory\$DellXMLFile) -eq $false) {
							# Expand Cabinet File
							global:Write-LogEntry -Value "Info: Expanding Dell driver pack cabinet file: $DellXMLFile" -Severity 1
							$XMLDownloadStatus.Text = "Reading Dell XML file"
							Expand "$global:TempDirectory\$DellCabFile" -F:* "$global:TempDirectory" -R | Out-Null
						}
					} catch {
						global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
					}
				}
				if ($global:DellModelXML -eq $null) {
					# Read XML File
					global:Write-LogEntry -Value "Info: Reading driver pack XML file - $global:TempDirectory\$DellXMLFile" -Severity 1
					[xml]$global:DellModelXML = Get-Content -Path (Join-Path -Path $global:TempDirectory -ChildPath $DellXMLFile) -Raw
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
				$DellModels = $global:DellModelCabFiles | Where-Object {
					($_.SupportedOperatingSystems.OperatingSystem.osCode -like "*$(($OSComboBox.Text).split(' ')[1])*") -and ($_.SupportedOperatingSystems.OperatingSystem.osArch -match $Architecture)
				} | Select-Object @{
					Expression = {
						$_.SupportedSystems.Brand.Model.name
					}; Label = "SystemName";
				} -Unique
				if ($DellModels -ne $null) {
					$XMLDownloadStatus.Text = "Adding $($DellModels.Count) Dell models"
					foreach ($Model in $DellModels.SystemName) {
						if ($Model -ne $null) {
							if ($Model -notin $DellProducts) {
								$DellProducts.Add($Model) | Out-Null
							}
						}
					}
					$StartDownloadButton.Enabled = $true
				}
				$DellProducts = $DellProducts | Sort-Object
				if ($DellProducts -ne $null) {
					foreach ($DellModel in $DellProducts) {
						$MakeModelDataGrid.Rows.Add($false, "Dell", $DellModel, $OSComboBox.Text, $ArchitectureComboxBox.Text)
					}
				}
				# Add Known Dell Models
				if ($QueryKnownModels -eq $true) {
					if (-not ([string]::IsNullOrEmpty($SiteServer))) {
						$DellKnownModels = Get-WmiObject -ComputerName $SiteServer -Namespace "root\SMS\site_$SiteCode" -Class SMS_G_System_COMPUTER_SYSTEM | Select-Object -Property Manufacturer, Model | Where-Object {
							($_.Manufacturer -match "Dell" -and (($_.Model -match "Optiplex") -or ($_.Model -match "Latitude") -or ($_.Model -match "Precision") -or ($_.Model -match "XPS")))
						} | Sort-Object Model | Get-Unique -AsString
					}
					
					# Add model to ArrayList if not present
					if ($DellKnownModels.Count -gt 0) {
						foreach ($DellKnownModel in $DellKnownModels.Model) {
							if ($DellKnownProducts -notcontains $DellKnownModel) {
								$DellKnownProducts.Add($DellKnownModel) | Out-Null
								global:Write-LogEntry -Value "Info: Adding $DellKnownModel to Dell known models" -Severity 1
							}
						}
						global:Write-LogEntry -Value "Info: Found: $(($DellKnownProducts).count) known Dell models" -Severity 1
					}
				}
				if (($DellModels).Count -gt "0") {
					global:Write-LogEntry -Value "Info: Found $(($DellModels).count) Dell model driver packs for $($OSComboBox.text) $($ArchitectureComboxBox.text)" -Severity 1
				} else {
					global:Write-LogEntry -Value "Info: No Dell models found. If you are using a proxy server please specify the proxy in the Proxy Server Settings tab" -Severity 2
				}
			}
			if ($LenovoCheckBox.Checked -eq $true) {
				$LenovoProducts.Clear()
				if ($global:LenovoModelDrivers -eq $null) {
					$XMLDownloadStatus.Text = "Reading Lenovo XML Web Service"
					try {
						if ($global:ProxySettingsSet -eq $true) {
							[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource @global:InvokeProxyOptions
						} else {
							[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource
						}
					} catch {
						global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
					}
					# Read Web Site
					global:Write-LogEntry -Value "Info: Reading driver pack URL - $LenovoXMLSource" -Severity 1
					# Set XML Object
					$global:LenovoModelDrivers = $global:LenovoModelXML.ModelList.Model
				}
				# Find Models Contained Within Downloaded XML
				if ($OSComboBox.Text -match "Windows 10") {
					$OSSelected = "Win10"
					$OSBuild = $($OSComboBox.Text).TrimStart("Windows 10 ")
					if (-not ([string]::IsNullOrEmpty($OSBuild))) {
						$LenovoModels = ($global:LenovoModelDrivers | Where-Object {
								($_.SCCM.Version -match $OSBuild)
							} | Sort-Object).Name
					} else {
						$LenovoModels = ($global:LenovoModelDrivers | Where-Object {
								($_.SCCM.Version -eq "*")
							} | Sort-Object).Name
					}
				}
				
				if ($LenovoModels -ne $null) {
					$XMLDownloadStatus.Text = "Adding $($LenovoModels.Count) Lenovo models"
					foreach ($Model in $LenovoModels) {
						$Model = $Model -replace "Win[^;]*", " "
						$LenovoModelTypes = ($global:LenovoModelDrivers | Where-Object {
								$_.Name -eq $Model
							}).Types.Type
						
					<#if (-not ([string]::IsNullOrEmpty($LenovoModelTypes))) {
						Write-Host "Removing $LenovoModelTypes from $Model "
						foreach ($LenovoModelType in $LenovoModelTypes) {
							$Model = $Model -replace $LenovoModelType, ""
							$Model = ($Model -replace "Type", "").Trim()
						}
					}#>
						if ($Model -notin $LenovoProducts) {
							$LenovoProducts.Add($Model) | Out-Null
						}
					}
					$StartDownloadButton.Enabled = $true
				}
				$LenovoProducts = $LenovoProducts | Sort-Object
				if ($LenovoProducts -ne $null) {
					foreach ($LenovoModel in $LenovoProducts) {
						$MakeModelDataGrid.Rows.Add($false, "Lenovo", $LenovoModel, $OSComboBox.Text, $ArchitectureComboxBox.Text)
					}
				}
				# Add Known Lenovo Models
				if ($QueryKnownModels -eq $true) {
					if (-not ([string]::IsNullOrEmpty($SiteServer))) {
						$LenovoKnownModels = Get-WmiObject -ComputerName $SiteServer -Namespace "root\SMS\site_$SiteCode" -Class SMS_G_System_COMPUTER_SYSTEM | Select-Object -Property Manufacturer, Model | Where-Object {
							$_.Manufacturer -match "Lenovo"
						} | Get-Unique -AsString
					} elseif ([string]$PlatformComboBox.SelectedItem -match "Intune") {
						global:Write-LogEntry -Value "Info: Selecting known Lenovo models from Intune devices" -Severity 1
						$LenovoKnownModels = $global:ManagedDevices | Select-Object -Property Manufacturer, Model | Where-Object {
							$_.Manufacturer -match "Lenovo"
						} | Get-Unique -AsString
						$global:ManagedDevices | Select-Object -Property Manufacturer, Model | Where-Object {
							$_.Manufacturer -match "Lenovo"
						} | Get-Unique -AsString
						$LenovoKnownModels
					}
					# Add model to ArrayList if not present
					if ($LenovoKnownModels.Count -gt 0) {
						foreach ($LenovoKnownModel in $LenovoKnownModels.Model) {
							$LenovoKnownModel = $(Find-LenovoModelType -ModelType $($LenovoKnownModel.Substring(0, 4)))
							If (-not ([string]::IsNullOrEmpty($LenovoKnownModel))) {
								$LenovoKnownModel.Trimend()
							}
							if (($LenovoKnownProducts -notcontains $LenovoKnownModel) -and (([string]::IsNullOrEmpty($LenovoKnownModel)) -ne $true)) {
								$LenovoKnownProducts.Add($LenovoKnownModel) | Out-Null
								global:Write-LogEntry -Value "Info: Adding $LenovoKnownModel to Lenovo known models" -Severity 1
							}
						}
						global:Write-LogEntry -Value "Info: Found: $(($LenovoKnownProducts).count) known Lenovo models" -Severity 1
					}
				}
				if (($LenovoModels).Count -gt "0") {
					global:Write-LogEntry -Value "Info: Found $(($LenovoModels).count) Lenovo model driver packs for $($OSComboBox.text) $($ArchitectureComboxBox.text)" -Severity 1
				} else {
					global:Write-LogEntry -Value "Warning: No Lenovo models found. If you are using a proxy server please specify the proxy in the Proxy Server Settings tab." -Severity 2
				}
			}
			if ($MicrosoftCheckBox.Checked -eq $true) {
				$MicrosoftKnownProducts.Clear()
				try {
					$XMLDownloadStatus.Text = "Reading Microsoft XML Web Service"
					if ($global:ProxySettingsSet -eq $true) {
						[xml]$MicrosoftModelList = Invoke-WebRequest -Uri $MicrosoftXMLSource @global:InvokeProxyOptions
					} else {
						[xml]$MicrosoftModelList = Invoke-WebRequest -Uri $MicrosoftXMLSource
					}
				} catch {
					global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
				}
				# Read Web Site
				global:Write-LogEntry -Value "Info: Reading Driver Pack URL - $MicrosoftXMLSource" -Severity 1
				$MicrosoftModels = $MicrosoftModelList.Drivers.Model
				Write-Verbose "Models = $MicrosoftModels"
				
				if ($MicrosoftModels.Count -gt 0) {
					foreach ($MicrosoftModel in $MicrosoftModels) {
						$MakeModelDataGrid.Rows.Add($false, "Microsoft", $MicrosoftModel.DisplayName, $OSComboBox.Text, $ArchitectureComboxBox.Text)
					}
					global:Write-LogEntry -Value "Info: Found $(($MicrosoftModels).count) Microsoft model driver packs for $($OSComboBox.text) $($ArchitectureComboxBox.text)" -Severity 1
					$XMLDownloadStatus.Text = "Adding $(($MicrosoftModels).count) Microsoft models"
				}
				if (-not ([string]::IsNullOrEmpty($SiteServer))) {
					if ([boolean](Get-WmiObject -ComputerName $SiteServer -Namespace "root\SMS\site_$SiteCode" -Class SMS_G_System_MS_SYSTEMINFORMATION -ErrorAction SilentlyContinue) -eq $true) {
						$MicrosoftKnownModels = (Get-WmiObject -ComputerName $SiteServer -Namespace "root\SMS\site_$SiteCode" -Class SMS_G_System_MS_SYSTEMINFORMATION | Select-Object -Property SystemManufacturer, SystemProductName, SystemSKU | Where-Object {
								(($_.SystemManufacturer -match "Microsoft") -and ($_.SystemProductName -match "Surface"))
							} | Get-Unique -AsString) | Sort-Object
						
						if (($MicrosoftModels).Count -gt 0) {
							if ($MicrosoftKnownModels.Count -gt 0) {
								foreach ($Model in $MicrosoftKnownModels) {
									if ([boolean]($MicrosoftModels.SystemSKU -match $Mmodel.SystemSKU)) {
										$MicrosoftKnownProducts.Add($($MicrosoftModels | Where-Object {
													($_.SystemSKU -eq $Model.SystemSKU) -or ($_.SystemSKU -like "$($Model.SystemSKU),*") -or ($_.SystemSKU -like "*, $($Model.SystemSKU)")
												}).DisplayName) | Out-Null
										global:Write-LogEntry -Value "Info: Adding $Model to Microsoft known models" -Severity 1
									}
								}
								global:Write-LogEntry -Value "Info: Found: $(($MicrosoftKnownProducts).count) known Microsoft models" -Severity 1
								$StartDownloadButton.Enabled = $true
							}
						} else {
							global:Write-LogEntry -Value "Info: No Microsoft models Found. If you are using a proxy server please specify the proxy in the Proxy Server Settings tab" -Severity 2
						}
					} else {
						global:Write-LogEntry -Value "Info: Required WMI class (MS_SYSTEMINFORMATION) is not being inventoried in Configuration Manager. Please refer to the documentation and extend the hardware classes being collected." -Severity 2
					}
				}
			}
			
			Start-Sleep -Seconds 1
			
			if ($QueryKnownModels -eq $true) {
				global:Write-LogEntry -Value "======== Selecting Known Models ========" -Severity 1
				if ($DellKnownModels -ne $null) {
					Select-KnownModels -SearchMake "Dell"
				}
				if ($HPKnownModels -ne $null) {
					Select-KnownModels -SearchMake "Hewlett-Packard"
				}
				if ($LenovoKnownModels -ne $null) {
					Select-KnownModels -SearchMake "Lenovo"
				}
				if ($MicrosoftKnownModels -ne $null) {
					Select-KnownModels -SearchMake "Microsoft"
				}
			}
			
			# Loop for each seleted model
			if ($XMLSelectedModels -ne $null) {
				global:Write-LogEntry -Value "======== Selecting Previously Selected Models ========" -Severity 1
				$XMLLoadingLabel.Text = "Updating selections. Please wait.."
				$XMLLoadingLabel.Visible = $true
				$XMLDownloadStatus.Text = "Selecting previously selected models"
				for ($Row = 0; $Row -lt $MakeModelDataGrid.RowCount; $Row++) {
					foreach ($XMLSelectedModel in $XMLSelectedModels) {
						if ($MakeModelDataGrid.Rows[$Row].Cells[2].Value -eq $XMLSelectedModel) {
							$MakeModelDataGrid.Rows[$Row].Cells[0].Value = $true
							$MakeModelDataGrid.Rows[$Row].Selected = $true
							global:Write-LogEntry -Value "Info: Selecting model $XMLSelectedModel" -Severity 1
						} else {
							$MakeModelDataGrid.Rows[$Row].Cells[0].Selected = $false
						}
					}
				}
				$MakeModelDataGrid.Sort($MakeModelDataGrid.Columns[0], [System.ComponentModel.ListSortDirection]::Descending)
				for ($Row = 0; $Row -lt $MakeModelDataGrid.RowCount; $Row++) {
					foreach ($XMLSelectedModel in $XMLSelectedModels) {
						if ($MakeModelDataGrid.Rows[$Row].Cells[0].Value -eq $true) {
							$MakeModelDataGrid.Rows[$Row].Selected = $true
						}
					}
				}
			}
			
			# Hide notification panel
			$XMLLoading.Visible = $false
			$XMLLoadingLabel.Visible = $false
			$XMLDownloadStatus.Visible = $false
			
			# Enable find model and search button
			if ($($MakeModelDataGrid.Rows.Count) -gt 0) {
				$FindModel.Enabled = $true
				$FindModelSelect.Enabled = $true
				$ModelSearchText.enabled = $true
				$ClearModelSelection.enabled = $true
			} else {
				$FindModel.Enabled = $false
				$ModelSearchText.enabled = $false
				$ClearModelSelection.enabled = $false
			}
			
		}
		
	}
	
	function Find-MicrosoftDriver {
		param (
			[parameter(Mandatory = $true, HelpMessage = "Provide the model to find drivers for")]
			[ValidateNotNullOrEmpty()]
			[string]$MSProductName,
			[parameter(Mandatory = $true, HelpMessage = "Specify the operating system.")]
			[ValidateNotNullOrEmpty()]
			[string]$OSBuild
		)
		
		# Construct Surface download URL
		$MicrosoftSurfaceURL = $MicrosoftBaseURL.TrimEnd("/") + "/" + $MSProductName + "/" + $OSBuild.Split(".")[2]
		global:Write-LogEntry -Value "Info: Microsoft AKA shortlink URL is $MicrosoftSurfaceURL" -Severity 1 -SkipGuiLog $false
		
		# Check URL availability
		[string]$MicrosoftDownloadURL = Get-RedirectedUrl -URL $MicrosoftSurfaceURL
		global:Write-LogEntry -Value "Info: Microsoft redirected URL discovered is $MicrosoftDownloadURL" -Severity 1 -SkipGuiLog $false
		if ($MicrosoftDownloadURL -match ".msi") {
			Return $MicrosoftDownloadURL
		} else {
			Return "badLink"
		}
	}
	
	function Get-RedirectedUrl {
		Param (
			[Parameter(Mandatory = $true)]
			[String]$URL
		)
		
		$Request = [System.Net.WebRequest]::Create($URL)
		$Request.AllowAutoRedirect = $false
		$Request.Timeout = 3000
		$Response = $Request.GetResponse()
		if ($Response.ResponseUri) {
			[string]$ReturnedURL = $Response.GetResponseHeader("Location")
		}
		$Response.Close()
		
		Return $ReturnedURL
	}
	
	function Get-DPOptions {
		global:Write-LogEntry -Value "======== Querying ConfigMgr Distribution Options ========" -Severity 1
		Set-Location -Path ($SiteCode + ":")
		$DistributionPoints = Get-CMDistributionPoint | Select-Object -ExpandProperty NetworkOsPath
		$DistributionPointGroups = Get-CMDistributionPointGroup | Select-Object -ExpandProperty Name
		# Populate Distribution Point List Box
		$DPGridView.Rows.Clear()
		if ($DistributionPoints -ne $null) {
			foreach ($DP in $DistributionPoints) {
				$DP = ($DP).TrimStart("\\")
				global:Write-LogEntry -Value "Info: Adding Distribution Point - $DP" -Severity 1
				if ($XMLSelectedDPs -contains $DP) {
					$DPGridView.Rows.Add($true, $DP)
				} else {
					$DPGridView.Rows.Add($false, $DP)
				}
			}
			global:Write-LogEntry -Value "Info: Found $($DistributionPoints.Count) Distribution Points" -Severity 1
		}
		# Populate Distribution Point Group List Box
		$DPGGridView.Rows.Clear()
		if ($DistributionPointGroups -ne $null) {
			foreach ($DPG in $DistributionPointGroups) {
				global:Write-LogEntry -Value "Info: Adding Distribution Point Group - $DPG" -Severity 1
				if ($XMLSelectedDPGs -contains $DPG) {
					$DPGGridView.Rows.Add($true, $DPG)
				} else {
					$DPGGridView.Rows.Add($false, $DPG)
				}
			}
			global:Write-LogEntry -Value "Info: Found $($DistributionPointGroups.Count) Distribution Point Groups" -Severity 1
		}
		Set-Location -Path $global:TempDirectory
	}
	
	function Set-ConfigMgrOptions {
		param
		(
			[parameter(Mandatory = $true)]
			[Boolean]$OptionsEnabled
		)
		$CleanUnusedCheckBox.Enabled = $OptionsEnabled
		$RemoveLegacyDriverCheckbox.Enabled = $OptionsEnabled
		$SiteServerInput.Enabled = $OptionsEnabled
		$SiteCodeText.Enabled = $OptionsEnabled
		$PackageTypeCombo.Enabled = $OptionsEnabled
		$DeploymentStateCombo.Enabled = $OptionsEnabled
		$PackageGrid.Enabled = $OptionsEnabled
		$ConfigMgrPkgActionCombo.Enabled = $OptionsEnabled
		$SelectAllButton.Enabled = $OptionsEnabled
		$SelectNoneButton.Enabled = $OptionsEnabled
		$DistributionPriorityCombo.Enabled = $OptionsEnabled
		$EnableBinaryDifCheckBox.Enabled = $OptionsEnabled
		$PackagePathTextBox.Enabled = $OptionsEnabled
		$ConfigMgrImport.Enabled = $OptionsEnabled
		$PackageRoot.Enabled = $OptionsEnabled
		$SpecifyCustomPath.Enabled = $OptionsEnabled
		$PackageBrowseButton.Enabled = $OptionsEnabled
		$ConnectConfigMgrButton.Enabled = $OptionsEnabled
		$FallbackOSCombo.Enabled = $OptionsEnabled
		$FallbackArcCombo.Enabled = $OptionsEnabled
		$CreateFallbackButton.Enabled = $OptionsEnabled
		$ZipCompressionCheckBox.Enabled = $OptionsEnabled
		$CreateXMLLogicPackage.Enabled = $OptionsEnabled
		
		if (($PlatformComboBox.SelectedItem -match "ConfigMgr") -and (-not ([string]::IsNullOrEmpty($SiteServerInput.Text)))) {
			Connect-ConfigMgr
		}
	}
	
	function Set-MDTOptions {
		param
		(
			[parameter(Mandatory = $true)]
			[Boolean]$OptionsEnabled
		)
		
		if ($OptionsEnabled -eq $true) {
			global:Write-LogEntry -Value "Info: Enabling MDT Options" -Severity 1
		} else {
			global:Write-LogEntry -Value "Info: Disabling MDT Options" -Severity 1
		}
		$MDTScriptTextBox.Enabled = $OptionsEnabled
		$MDTDriverStructureCombo.Enabled = $OptionsEnabled
		$DeploymentShareGrid.Enabled = $OptionsEnabled
		$MDTScriptBrowseButton.Enabled = $OptionsEnabled
		$ImportMDTPSButton.Enabled = $OptionsEnabled
		$SpecifyCustomPath.Enabled = $false
	}
	
	function Distribute-Content {
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
				global:Write-LogEntry -Value "$($Product): Distributing Package $PackageID to Distribution Point - $($DPGridView.Rows[$Row].Cells[1].Value) " -Severity 1
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
				global:Write-LogEntry -Value "$($Product): Distributing Package $PackageID to Distribution Point Group - $($DPGGridView.Rows[$Row].Cells[1].Value) " -Severity 1
			}
		}
	}
	
	function Connect-ConfigMgr {
		# Set Site Server Value
		$SiteServer = $SiteServerInput.Text
		if (-not ([string]::IsNullOrEmpty($SiteServer))) {
			
			if ((Test-WSMan -ComputerName $SiteServer).wsmid -ne $null) {
				#Clear-Host
				$ProgressListBox.ForeColor = "Black"
				try {
					global:Write-LogEntry -Value "======== Connecting to ConfigMgr Server ========" -Severity 1
					global:Write-LogEntry -Value "Info: Querying site code From $SiteServer" -Severity 1
					Get-SiteCode -SiteServer $SiteServer
					# Import Configuratio Manager PowerShell Module
					if ($env:SMS_ADMIN_UI_PATH -ne $null) {
						$ModuleName = (Get-Item $env:SMS_ADMIN_UI_PATH | Split-Path -Parent) + "\ConfigurationManager.psd1"
						global:Write-LogEntry -Value "Info: Loading ConfigMgr PowerShell module" -Severity 1
						Import-Module $ModuleName
						$global:ConfigMgrValidation = $true
						Get-DPOptions
						$CleanUnusedCheckBox.Enabled = $true
						$RemoveLegacyDriverCheckbox.Enabled = $true
					}
				} catch [System.Exception]{
					global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
				}
			} else {
				global:Write-ErrorOutput -Message "Error: ConfigMgr server specified not found - $($SiteServerInput.Text)" -Severity 3
			}
		} else {
			global:Write-ErrorOutput -Message "Error: ConfigMgr site server not specified. Please review in the common settings tab." -Severity 3
		}
	}
	
	function Find-DellBios {
		param (
			[string]$SKU
		)
		
		if ((Test-Path -Path $global:TempDirectory\$DellCatalogXMLFile) -eq $false) {
			global:Write-LogEntry -Value "======== Downloading Dell XML Catalog  ========" -Severity 1
			global:Write-LogEntry -Value "Info: Downloading Dell XML catalog cabinet file from $DellCatalogSource" -Severity 1
			# Download Dell Model Cabinet File
			try {
				if ($global:ProxySettingsSet -eq $true) {
					Start-BitsTransfer -Source $DellCatalogSource -Destination $global:TempDirectory @global:BitsProxyOptions
				} else {
					Start-BitsTransfer -Source $DellCatalogSource -Destination $global:TempDirectory @global:BitsOptions
				}
				# Expand Cabinet File
				global:Write-LogEntry -Value "Info: Expanding Dell XML catalog cabinet file: $DellCatalogFile" -Severity 1
				Expand "$global:TempDirectory\$DellCatalogFile" -F:* "$global:TempDirectory" -R | Out-Null
			} catch {
				global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
			}
		}
		if ((Test-Path -Path $global:TempDirectory\$DellCatalogXMLFile) -eq $true) {
			if ($global:DellCatalogXML -eq $null) {
				# Read XML File
				global:Write-LogEntry -Value "Info: Reading Dell product XML file - $global:TempDirectory\$DellCatalogXMLFile" -Severity 1
				[xml]$global:DellCatalogXML = Get-Content -Path $(Join-Path -Path $global:TempDirectory -ChildPath $DellCatalogXMLFile) -Raw
				# Set XML Object
				$global:DellCatalogXML.GetType().FullName
			}
			# Cater for multiple bios version matches and select the most recent
			if ($SKU -notmatch ";") {
				$DellBIOSFile = $global:DellCatalogXML.Manifest.SoftwareComponent | Where-Object {
					($_.name.display."#cdata-section" -match "BIOS") -and ($_.SupportedSystems.Brand.Model.SystemID -match $SKU)
				} | Sort-Object ReleaseDate
			} else {
				# Cater for multi model updates
				global:Write-LogEntry -Value "Info: Attempting to match based on multiple model package" -Severity 1
				$DellBIOSFile = $global:DellCatalogXML.Manifest.SoftwareComponent | Where-Object {
					($_.name.display."#cdata-section" -match "BIOS") -and ($_.SupportedSystems.Brand.Model.SystemID -match "$(($SKU).Split(";")[0])")
				} | Sort-Object ReleaseDate | Select-Object -First 1
				if ($DellBIOSFile -eq $null) {
					$DellBIOSFile = $global:DellCatalogXML.Manifest.SoftwareComponent | Where-Object {
						($_.name.display."#cdata-section" -match "BIOS") -and ($_.SupportedSystems.Brand.Model.SystemID -match "$(($SKU).Split(";")[1])")
					} | Sort-Object ReleaseDate | Select-Object -First 1
				}
			}
			if (($DellBIOSFile -eq $null) -or (($DellBIOSFile).Count -gt 1)) {
				global:Write-LogEntry -Value "Info: Attempting to find BIOS link" -Severity 1
				# Attempt to find BIOS link		
				if ($Model -match "AIO") {
					$DellBIOSFile = $DellBIOSFile | Where-Object {
						$_.SupportedSystems.Brand.Model.Display.'#cdata-section' -match "AIO"
					} | Sort-Object ReleaseDate | Select-Object -First 1
				}
				$DellBIOSFile = $global:DellCatalogXML.Manifest.SoftwareComponent | Where-Object {
					($_.name.display."#cdata-section" -match "BIOS") -and ($_.SupportedSystems.Brand.Model.SystemID -match $SKU)
				} | Sort-Object ReleaseDate | Select-Object -First 1
			} elseif ($DellBIOSFile -eq $null) {
				# Attempt to find BIOS link via Dell model number (V-Pro / Non-V-Pro Condition)
				$DellBIOSFile = $global:DellCatalogXML.Manifest.SoftwareComponent | Where-Object {
					($_.name.display."#cdata-section" -match "BIOS") -and ($_.name.display."#cdata-section" -match "$($model.Split("-")[0])")
				} | Sort-Object ReleaseDate | Select-Object -First 1
			}
			if (![string]::IsNullOrEmpty(($DellBIOSFile.Path))) {
				global:Write-LogEntry -Value "Info: Found BIOS URL $($DellBIOSFile.Path)" -Severity 1
				# Return BIOS file values
				Return $DellBIOSFile
			} else {
				global:Write-LogEntry -Value "Error: Failed to find BIOS link in source XML feed" -Severity 2
				Return "BadLink"
			}
		} else {
			global:Write-ErrorOutput -Message "Error: Issues occured while extracting XML file" -Severity 3
			Return "Badlink"
		}
	}
	
	function Find-HPBIOS {
		param (
			[string]$Model,
			[string]$OS,
			[string]$Architecture,
			[string]$SKUValue
		)
		
		global:Write-LogEntry -Value "Info: Checking for existing HP cabinet file $HPPlatformCabFile" -Severity 1
		if ((Test-Path -Path $(Join-Path -Path $global:TempDirectory -ChildPath $HPPlatformCabFile)) -eq $false) {
			try {
				Set-Location -Path $global:TempDirectory
				# Download HP Model Details XML
				
				global:Write-LogEntry -Value "Info: Downloading HP XML from $HPPlatFormList" -Severity 1
				if ($global:ProxySettingsSet -eq $true) {
					Start-BitsTransfer -Source $HPPlatFormList -Destination $global:TempDirectory @global:BitsProxyOptions
				} else {
					Start-BitsTransfer -Source $HPPlatFormList -Destination $global:TempDirectory @global:BitsOptions
				}
				if ((Test-Path -Path $(Join-Path $global:TempDirectory -ChildPath $HPPlatformXMLFile)) -eq $false) {
					# Expand Cabinet File
					global:Write-LogEntry -Value "Info: Expanding HP cabinet file: $HPXMLFile" -Severity 1
					Expand "$global:TempDirectory\$HPPlatformCabFile" -F:* "$global:TempDirectory" -R | Out-Null
				}
			} catch {
				global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
			}
		}
		global:Write-LogEntry -Value "Info: Reading HP XML from $(Join-Path -Path $global:TempDirectory -ChildPath ($HPPlatformXMLFile | Split-Path -Leaf))" -Severity 1
		$global:HPPlatformXML = (Select-Xml (Join-Path -Path $global:TempDirectory -ChildPath ($HPPlatformXMLFile | Split-Path -Leaf)) -XPath "/ImagePal").Node.Platform
		if ($global:HPPlatformXML -ne $null) {
			global:Write-LogEntry -Value "Info: OS pre build strip is $OS" -Severity 1
			global:Write-LogEntry -Value "Info: Model is $Model" -Severity 1
			if ($global:SkuValue -ne $null) {
				# Windows Build Driver Switch
				switch -Wildcard ($OS) {
					"*2004"	{
						$OS = "10.0.2004"
					}
					"*1909"	{
						$OS = "10.0.1909"
					}
					"*1903"	{
						$OS = "10.0.1903"
					}
					"*1809"	{
						$OS = "10.0.1809"
					}
					"*1803"	{
						$OS = "10.0.1803"
					}
					"*1709"	{
						$OS = "10.0.1709"
					}
					"*1703" {
						$OS = "10.0.1703"
					}
					"*1607" {
						$OS = "10.0.1607"
					}
					"*10" {
						$OS = "10.0.1511"
					}
					"8.1" {
						$OS = "6.3"
					}
					"*7" {
						$OS = "6.1"
					}
				}
				global:Write-LogEntry -Value "Info: SystemID is $SKUValue" -Severity 1
				global:Write-LogEntry -Value "Info: OS is $OS" -Severity 1
				global:Write-LogEntry -Value "Info: Architecture is $Architecture" -Severity 1
				$HPXMLCabinetSource = "http://ftp.hp.com/pub/caps-softpaq/cmit/imagepal/ref/" + $($($SKUValue.Split(",") | Select-Object -First 1) + "/" + $($SKUValue.Split(",") | Select-Object -First 1) + "_" + $($Architecture.TrimStart("x")) + "_" + $OS + ".cab")
				global:Write-LogEntry -Value "Info: URL is $HPXMLCabinetSource" -Severity 1
				# Try both credential and default methods
				try {
					if ($global:ProxySettingsSet -eq $true) {
						$HPModelXML = Invoke-WebRequest -Uri $HPXMLCabinetSource @global:InvokeProxyOptions
					} else {
						$HPModelXML = Invoke-WebRequest -Uri $HPXMLCabinetSource -UseBasicParsing
					}
				} catch {
					$HPDownloadError = $true
					global:Write-ErrorOutput -Message "Error: An error occurred while attempting contact $HPXMLCabinetSource - $($_.Exception.Message)" -Severity 2
				}
				if ($HPDownloadError -ne $true) {
					# Download HP Model Cabinet File
					try {
						if ($global:ProxySettingsSet -eq $true) {
							Start-BitsTransfer -Source $HPXMLCabinetSource -Destination $global:TempDirectory @global:BitsProxyOptions
						} else {
							Start-BitsTransfer -Source $HPXMLCabinetSource -Destination $global:TempDirectory @global:BitsOptions
						}
					} catch {
						global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
					}
					$HPCabFile = $HPXMLCabinetSource | Split-Path -Leaf
					$HPXMLFile = $HPCabFile.Replace(".cab", ".xml")
					
					if ((Test-Path -Path $(Join-Path -Path $global:TempDirectory -ChildPath $HPCabFile)) -eq $true) {
						# Expand Cabinet File
						global:Write-LogEntry -Value "Info: Expanding HP SoftPaq cabinet file: $HPCabFile" -Severity 1
						Expand "$global:TempDirectory\$HPCabFile" -F:* "$global:TempDirectory" -R | Out-Null
						
						# Read HP Model XML
						global:Write-LogEntry -Value "Info: Reading model XML $HPXMLFile" -Severity 1
						[xml]$HPSoftPaqDetails = Get-Content -Path $(Join-Path -Path $global:TempDirectory -ChildPath $HPXMLFile) -Raw
						$HPBIOSDetails = ($HPSoftPaqDetails.ImagePal.Solutions.UpdateInfo | Where-Object {
								($_.Category -eq "BIOS") -and ($_.Name -notmatch "Utilities")
							} | Sort-Object Version | Select-Object -First 1)
						global:Write-LogEntry -Value "Info: BIOS download URL is $($HPBIOSDetails.URL)" -Severity 1
						Return $HPBIOSDetails
					} else {
						global:Write-ErrorOutput -Message "Error: Failed to download $HPXMLCabinetSource" -Severity 3
					}
				} else {
					global:Write-LogEntry -Value "Info: Could not download HP $Model BIOS update" -Severity 1
				}
			}
		}
	}
	
	function Invoke-HPSoftPaqExpand {
		param
		(
			[parameter(Mandatory = $true)]
			[ValidateSet("BIOS", "Drivers")]
			[string]$SoftPaqType
		)
		
		# HP Temp directory
		$HPTemp = $global:TempDirectory + "\" + $Model + "\Win" + $WindowsVersion + $Architecture
		$HPTemp = $HPTemp -replace '/', '-'
		
		switch ($SoftPaqType) {
			"BIOS" {
				Unblock-File -Path $HPBIOSSource
				$HPSilentSwitches = "/s /e /f " + '"' + "$HPBIOSTemp\Extract" + '"'
				$HPFallBackSilentSwitches = "-PDF -F" + "$HPBIOSTemp\Extract" + " -S -E"
				global:Write-LogEntry -Value "Info: Unlocking BIOS file located at $HPBIOSSource" -Severity 1
				global:Write-LogEntry -Value "Info: Extracting $Make BIOS update to $HPBIOSTemp" -Severity 1
				global:Write-LogEntry -Value "Info: Using $Make silent switches: $HPSilentSwitches" -Severity 1
				Start-Process -FilePath $HPBIOSSource -ArgumentList $HPSilentSwitches -Verb RunAs
				$BIOSProcess = ($BIOSFile).Substring(0, $BIOSFile.length - 4)
				# Wait for HP SoftPaq Process To Finish
				While ((Get-Process).name -contains $BIOSProcess) {
					global:Write-LogEntry -Value "Info: Waiting for extract process (Process: $BIOSProcess) to complete..  Next check in 10 seconds" -Severity 1
					Start-Sleep -Seconds 10
				}
				$HPBIOSExtract = Join-Path $HPBIOSTemp -ChildPath "Extract"
				# Set HP extracted folder
				[int]$HPFileCount = (Get-ChildItem -Path $HPBIOSExtract -Recurse -File).Count
				if ($HPFileCount -eq 0) {
					global:Write-LogEntry -Value "Info: Issues were detected extracting files. Switching to legacy mode" -Severity 2
					global:Write-LogEntry -Value "Info: Using $Make silent switches: $HPFallBackSilentSwitches" -Severity 1
					Start-Process -FilePath $HPBIOSSource -ArgumentList $HPSilentSwitches -Verb RunAs
					$BIOSProcess = ($BIOSFile).Substring(0, $BIOSFile.length - 4)
					# Wait for HP SoftPaq Process To Finish
					While ((Get-Process).name -contains $BIOSProcess) {
						global:Write-LogEntry -Value "Info: Waiting for extract process (Process: $BIOSProcess) to complete..  Next check in 10 seconds" -Severity 1
						Start-Sleep -Seconds 10
					}
					$HPBIOSExtract = Join-Path $HPBIOSTemp -ChildPath "Extract"
					# Set HP extracted folder
					[int]$HPFileCount = (Get-ChildItem -Path $HPBIOSExtract -Recurse -File).Count
				}
				global:Write-LogEntry -Value "Info: HP BIOS extract is $HPBIOSExtract" -Severity 1
				if ((-not ([string]::IsNullOrEmpty($HPBIOSExtract))) -and (Test-Path -Path "$HPBIOSExtract") -eq $true) {
					Start-Job -Name "$Model-BIOS-Move" -ScriptBlock $MoveDrivers -ArgumentList ($HPBIOSExtract, $BIOSUpdateRoot)
					while ((Get-Job -Name "$Model-BIOS-Move").State -eq "Running") {
						global:Write-LogEntry -Value "Info: Moving $Make $Model $OperatingSystem $Architecture BIOS files. Next check in 10 Seconds" -Severity 1
						global:Write-LogEntry -Value "Info: Destination folder - $BIOSUpdateRoot" -Severity 1
						Start-Sleep -seconds 10
					}
					$HPExtractComplete = $true
				} else {
					global:Write-ErrorOutput -Message "Error: Issues occurred during the $Make $Model extract process" -Severity 3
					$HPExtractComplete = $false
				}
			}
			"Drivers" {
				global:Write-LogEntry -Value "$($Product): Extracting $Make drivers to $HPTemp" -Severity 1
				Unblock-File -Path $($DownloadRoot + $Model + '\Driver Cab\' + $DriverCab)
				$HPSilentSwitches = "/s /e /f " + '"' + $HPTemp + '"'
				$HPFallBackSilentSwitches = "-PDF -F" + "$HPTEMP" + " -S -E"
				global:Write-LogEntry -Value "$($Product): Using $Make silent switches: $HPSilentSwitches" -Severity 1
				global:Write-LogEntry -Value "$($Product): Extracting $Make drivers to $DriverExtractDest" -Severity 1
				Start-Process -FilePath "$($DownloadRoot + $Model + '\Driver Cab\' + $DriverCab)" -ArgumentList $HPSilentSwitches -Verb RunAs
				$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
				# Wait for HP SoftPaq Process To Finish
				While ((Get-Process).name -contains $DriverProcess) {
					global:Write-LogEntry -Value "$($Product): Waiting for extract process (Process: $DriverProcess) to complete..  Next check in 30 seconds" -Severity 1
					Start-Sleep -Seconds 30
				}
				$HPExtract = Get-ChildItem -Path $HPTemp -Directory
				if ($HPExtract.count -eq 0) {
					global:Write-LogEntry -Value "Info: Issues were detected extracting files. Switching to legacy mode" -Severity 2
					global:Write-LogEntry -Value "Info: Using $Make silent switches: $HPFallBackSilentSwitches" -Severity 1
					Start-Process -FilePath "$($DownloadRoot + $Model + '\Driver Cab\' + $DriverCab)" -ArgumentList $HPFallBackSilentSwitches -Verb RunAs
					$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
				}
				# Move HP Extracted Drivers To UNC Share 
				# Loop through the HP extracted driver folders to find the extracted folders and reduce directory path
				while ($HPExtract.Count -eq 1) {
					$HPExtract = Get-ChildItem -Path $HPExtract.FullName -Directory
				}
				# Set HP extracted folder
				$HPExtract = $HPExtract.FullName | Split-Path -Parent | Select-Object -First 1
				global:Write-LogEntry -Value "$($Product): HP driver source directory set to $HPExtract" -Severity 1
				if ((Test-Path -Path "$HPExtract") -eq $true) {
					Start-Job -Name "$Model-Driver-Move" -ScriptBlock $MoveDrivers -ArgumentList ($HPExtract, $DriverExtractDest)
					while ((Get-Job -Name "$Model-Driver-Move").State -eq "Running") {
						global:Write-LogEntry -Value "$($Product): Moving $Make $Model $OperatingSystem $Architecture driver.. Next check in 30 seconds" -Severity 1
						Start-Sleep -seconds 30
					}
				} else {
					global:Write-ErrorOutput -Message "Error: Issues occurred during the $Make $Model extract process" -Severity 3
				}
			}
		}
	}
	
	function Find-LenovoModelType {
		param (
			[parameter(Mandatory = $false, HelpMessage = "Enter Lenovo model to query")]
			[string]$Model,
			[parameter(Mandatory = $false, HelpMessage = "Enter Operating System")]
			[string]$OS,
			[parameter(Mandatory = $false, HelpMessage = "Enter Lenovo model type to query")]
			[string]$ModelType
		)
		<#
		try {
			if ($global:LenovoModelDrivers -eq $null) {
				if ($global:ProxySettingsSet -eq $true) {
					[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource @global:InvokeProxyOptions
				} else {
					[xml]$global:LenovoModelXML = Invoke-WebRequest -Uri $LenovoXMLSource
				}
				
				# Read Web Site
				global:Write-LogEntry -Value "Info: Reading driver pack URL - $LenovoXMLSource" -Severity 1
				
				# Set XML Object
				$global:LenovoModelXML.GetType().FullName
				$global:LenovoModelDrivers = $global:LenovoModelXML.Products
			}
		} catch {
			global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
		}
		
		if ($Model.Length -gt 0) {
			$global:LenovoModelType = ($global:LenovoModelDrivers.Product | Where-Object {
					$_.Queries.Version -eq "$Model"
				}).Queries.Types | Select-Object -ExpandProperty Type | Select-Object -first 1
			$global:SkuValue = ($global:LenovoModelDrivers.Product | Where-Object {
					$_.Queries.Version -eq "$Model"
				}).Queries.Types | Select-Object -ExpandProperty Type | Sort-Object | Get-Unique
		}
		
		if ($ModelType.Length -gt 0) {
			$global:LenovoModelType = (($global:LenovoModelDrivers.Product.Queries) | Where-Object {
					($_.Types | Select-Object -ExpandProperty Type) -match $ModelType
				}).Version | Select-Object -first 1
		}#>
		
		
		$global:LenovoModelType = ($global:LenovoModelDrivers | Where-Object {
				$_.name -eq $Model
			}).Types.Type
		Return $global:LenovoModelType
	}
	
	function Find-LenovoBios {
		param (
			[Parameter(Mandatory = $true)]
			[string]$ModelType
		)
		
		Set-Location -Path $global:TempDirectory
		# Download Lenovo Model Details XML
		$OS = "10"
		
		try {
			if ($global:ProxySettingsSet -eq $true) {
				Start-BitsTransfer -Source ($LenovoBiosBase + $ModelType + "_Win$OS.xml") -Destination $global:TempDirectory @global:BitsProxyOptions
			} else {
				Start-BitsTransfer -Source ($LenovoBiosBase + $ModelType + "_Win$OS.xml") -Destination $global:TempDirectory @global:BitsOptions
			}
			global:Write-LogEntry -Value "Lenovo Base - $LenovoBiosBase, Lenovo Model Type $ModelType" -Severity 1
			global:Write-LogEntry -Value "Info: Quering XML $($LenovoBiosBase + $ModelType + "_Win$OS.xml") for BIOS download links " -Severity 1
			$LenovoModelBIOSDownloads = ((Select-Xml -path ($global:TempDirectory + "\" + $ModelType + "_Win$OS.xml") -XPath "/").Node.Packages.Package | Where-Object {
					$_.Category -match "BIOS"
				}) | Sort-Object Location -Descending | Select-Object -First 1
			Return $LenovoModelBIOSDownloads
		} catch {
			global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
		}
	}
	
	function Invoke-BitsJobMonitor {
		param (
			[parameter(Mandatory = $true)]
			[string]$BitsJobName,
			[parameter(Mandatory = $true)]
			[string]$DownloadSource
		)
		
		try {
			global:Write-LogEntry -Value "BitsTransfer: Checking BITS background job" -Severity 1 -SkipGuiLog $true
			
			$BitsJob = Get-BitsTransfer | Where-Object {
				$_.DisplayName -match "$BitsJobName"
			}
			while (($BitsJob).JobState -eq "Connecting") {
				global:Write-LogEntry -Value "BitsTransfer: Establishing connection to $DownloadSource" -Severity 1
				Start-Sleep -seconds 5
			}
			if (($BitsJob).JobState -eq "Transferring") {
				$global:BitsJobByteSize = $($BitsJob.BytesTotal)
				if (-not ([string]::IsNullOrEmpty($global:BitsJobByteSize))) {
					$FileSize.text = [System.Math]::Round($($global:BitsJobByteSize/1MB), 2)
				}
			}
			while (($BitsJob).JobState -eq "Transferring") {
				if ($BitsJob.BytesTotal -ne $null) {
					$global:BitsJobByteSize = $($BitsJob.BytesTotal)
					$PercentComplete = [int](($BitsJob.BytesTransferred * 100)/$BitsJob.BytesTotal);
					global:Write-LogEntry -Value "BitsTransfer: Downloaded $([System.Math]::Round(((($BitsJob).BytesTransferred)/ 1MB), 2)) MB of $([System.Math]::Round(((($BitsJob).BytesTotal)/ 1MB), 2)) MB ($PercentComplete%). Next update in 30 seconds." -Severity 1
					Start-Sleep -seconds 30
				} else {
					global:Write-LogEntry -Value "BitsTransfer: Download issues detected. Cancelling download process" -Severity 2
					Get-BitsTransfer | Where-Object {
						$_.DisplayName -eq "$Model-DriverDownload"
					} | Remove-BitsTransfer
				}
			}
		} catch {
			global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
		}
		
	}
	
	function Write-XMLSettings {
		# DATSettings.XML location
		$Path = "$global:SettingsDirectory\DATSettings.xml"
		
		# Set XML Structure
		$XmlWriter = New-Object System.XMl.XmlTextWriter($Path, $Null)
		$xmlWriter.Formatting = 'Indented'
		$xmlWriter.Indentation = 1
		$XmlWriter.IndentChar = "`t"
		$xmlWriter.WriteStartDocument()
		$xmlWriter.WriteProcessingInstruction("xml-stylesheet", "type='text/xsl' href='style.xsl'")
		
		# Write Initial Header Comments
		$XmlWriter.WriteComment('Settings used with MSEndpointMgr Driver Automation Tool')
		$xmlWriter.WriteStartElement('Settings')
		$XmlWriter.WriteAttributeString('current', $true)
		
		# Export ConfigMgr Site Settings
		$xmlWriter.WriteStartElement('SiteSettings')
		$xmlWriter.WriteElementString('Server', $SiteServerInput.Text)
		$xmlWriter.WriteElementString('Site', $SiteCodeText.Text)
		$xmlWriter.WriteEndElement()
		
		# Export Download Options Settings
		$xmlWriter.WriteStartElement('DownloadSettings')
		$xmlWriter.WriteElementString('DeploymentPlatform', $PlatformComboBox.Text)
		$xmlWriter.WriteElementString('DownloadType', $DownloadComboBox.Text)
		$xmlWriter.WriteElementString('OperatingSystem', $OSComboBox.Text)
		$xmlWriter.WriteElementString('Architecture', $ArchitectureComboxBox.Text)
		$xmlWriter.WriteEndElement()
		
		# Export Package Locations
		if ($SpecifyCustomPath.Checked -eq $true) {
			$xmlWriter.WriteStartElement('PackageSettings')
			$xmlWriter.WriteElementString('CustomEnabled', $true)
			$xmlWriter.WriteElementString('PackageDestination', $CustPackageDest.Text)
			$xmlWriter.WriteEndElement()
		} elseif ($PackageRoot.Checked -eq $true) {
			$xmlWriter.WriteStartElement('PackageSettings')
			$xmlWriter.WriteElementString('RootEnabled', $true)
			$xmlWriter.WriteEndElement()
		}
		
		# Export Storage Locations
		$xmlWriter.WriteStartElement('StorageSettings')
		$xmlWriter.WriteElementString('Download', $DownloadPathTextBox.Text)
		$xmlWriter.WriteElementString('Package', $PackagePathTextBox.Text)
		$xmlWriter.WriteEndElement()
		
		# Export Manufacturer Selections
		$xmlWriter.WriteStartElement('Manufacturer')
		$xmlWriter.WriteElementString('Dell', $DellCheckBox.checked)
		$xmlWriter.WriteElementString('HP', $HPCheckBox.checked)
		$xmlWriter.WriteElementString('Lenovo', $LenovoCheckBox.checked)
		$xmlWriter.WriteElementString('Microsoft', $MicrosoftCheckBox.checked)
		$xmlWriter.WriteEndElement()
		
		# Export Selected Models
		$xmlWriter.WriteStartElement('Models')
		# Loop for each seleted model
		for ($Row = 0; $Row -lt $MakeModelDataGrid.RowCount; $Row++) {
			if ($MakeModelDataGrid.Rows[$Row].Cells[0].Value -eq $true) {
				$xmlWriter.WriteElementString('ModelSelected', $MakeModelDataGrid.Rows[$Row].Cells[2].Value)
				$ExportMDTShareNames.Add($MakeModelDataGrid.Rows[$Row].Cells[2].Value)
			}
		}
		$xmlWriter.WriteEndElement()
		
		# Export Proxy Server Settings
		$xmlWriter.WriteStartElement('ConfigMgrImport')
		$xmlWriter.WriteElementString('ImportModels', $ConfigMgrImport.text)
		$xmlWriter.WriteEndElement()
		
		# Export Distribution Point Settings
		$xmlWriter.WriteStartElement('DistributionSettings')
		# Loop for each seleted Distribution Point
		for ($Row = 0; $Row -lt $DPGridView.RowCount; $Row++) {
			if ($DPGridView.Rows[$Row].Cells[0].Value -eq $true) {
				$xmlWriter.WriteElementString('DistributionPointName', $DPGridView.Rows[$Row].Cells[1].Value)
			}
		}
		# Loop for each seleted Distribution Point Group
		for ($Row = 0; $Row -lt $DPGGridView.RowCount; $Row++) {
			if ($DPGGridView.Rows[$Row].Cells[0].Value -eq $true) {
				$xmlWriter.WriteElementString('DistributionPointGroupName', $DPGGridView.Rows[$Row].Cells[1].Value)
			}
		}
		$xmlWriter.WriteElementString('BinaryDifferentialReplication', $EnableBinaryDifCheckBox.Checked)
		$XmlWriter.WriteElementString('ReplicationPriority', $DistributionPriorityCombo.Text)
		$xmlWriter.WriteEndElement()
		
		# Export Proxy Server Settings
		$xmlWriter.WriteStartElement('ProxySettings')
		$xmlWriter.WriteElementString('UseProxy', $UseProxyServerCheckbox.Checked)
		$xmlWriter.WriteElementString('Proxy', $ProxyServerInput.Text)
		$xmlWriter.WriteEndElement()
		
		# Export Options Settings
		$xmlWriter.WriteStartElement('Options')
		$xmlWriter.WriteElementString('CleanUnused', $CleanUnusedCheckBox.checked)
		$xmlWriter.WriteElementString('RemoveLegacy', $RemoveLegacyDriverCheckbox.checked)
		$xmlWriter.WriteElementString('RemoveDriverSource', $RemoveDriverSourceCheckbox.checked)
		$xmlWriter.WriteElementString('RemoveLegacyBIOS', $RemoveLegacyBIOSCheckbox.checked)
		$xmlWriter.WriteElementString('ZIPCompression', $ZipCompressionCheckBox.checked)
		$xmlWriter.WriteElementString('XMLLogicPackage', $CreateXMLLogicPackage.checked)
		$xmlWriter.WriteEndElement()
		
		# Export MDT Settings
		$xmlWriter.WriteStartElement('MDTSettings')
		$xmlWriter.WriteElementString('ScriptLocation', $MDTScriptTextBox.Text)
		$xmlWriter.WriteElementString('Structure', $MDTDriverStructureCombo.SelectedIndex)
		for ($Row = 0; $Row -lt $DeploymentShareGrid.RowCount; $Row++) {
			if ($DeploymentShareGrid.Rows[$Row].Cells[0].Value -eq $true) {
				$ExportMDTShareNames.Add($DeploymentShareGrid.Rows[$Row].Cells["Name"].Value)
			}
		}
		foreach ($ExportMDTShareName in $ExportMDTShareNames) {
			$xmlWriter.WriteElementString('DeploymentShare', $ExportMDTShareName)
		}
		$xmlWriter.WriteEndElement()
		
		# Export MDM/MBM Settings
		$xmlWriter.WriteStartElement('DiagSettings')
		$xmlWriter.WriteElementString('ConfigMgrWebServiceURL', $ConfigMgrWebURL.text)
		$xmlWriter.WriteEndElement()
		
		# Save XML Document
		$xmlWriter.WriteEndDocument()
		$xmlWriter.Flush()
		$xmlWriter.Close()
	}
	
	function Read-XMLSettings {
		global:Write-LogEntry -Value "======== Reading Settings File ========" -Severity 1
		
		try {
			# // Read in settings XML		
			[xml]$global:DATSettingsXML = Get-Content -Path $(Join-Path -Path $global:SettingsDirectory -ChildPath "DATSettings.xml") -Raw
			
			# Set XML Object
			$global:DATSettingsXML.GetType().FullName
			
			# ConfigMgr Site Settings
			global:Write-LogEntry -Value "Setting ConfigMgr Site Settings" -Severity 1
			$SiteCodeText.Text = $global:DATSettingsXML.Settings.SiteSettings.Site
			$SiteServerInput.Text = $global:DATSettingsXML.Settings.SiteSettings.Server
			
			# OS & Download Settings
			global:Write-LogEntry -Value "Setting OS & Download Selections" -Severity 1
			$OSComboBox.Text = $global:DATSettingsXML.Settings.DownloadSettings.OperatingSystem
			$PlatformComboBox.Text = $global:DATSettingsXML.Settings.DownloadSettings.DeploymentPlatform
			$ArchitectureComboxBox.Text = $global:DATSettingsXML.Settings.DownloadSettings.Architecture
			$DownloadComboBox.Text = $global:DATSettingsXML.Settings.DownloadSettings.DownloadType
			
			# // Package Locations
			if ($global:DATSettingsXML.Settings.PackageSettings.CustomEnabled -eq $true) {
				global:Write-LogEntry -Value "Setting Custom Package Location" -Severity 1
				$SpecifyCustomPath.Enabled = $true
				$SpecifyCustomPath.Checked = $true
				$CustPackageDest.Text = $global:DATSettingsXML.Settings.PackageSettings.PackageDestination
			} elseif ($global:DATSettingsXML.Settings.PackageSettings.RootEnabled -eq $true) {
				global:Write-LogEntry -Value "Setting Custom Package Location" -Severity 1
				$PackageRoot.Enabled = $true
				$PackageRoot.Checked = $true
			}
			
			# // Storage Locations
			global:Write-LogEntry -Value "Setting Storage Locations" -Severity 1
			$PackagePathTextBox.Text = $global:DATSettingsXML.Settings.StorageSettings.Package
			$DownloadPathTextBox.Text = $global:DATSettingsXML.Settings.StorageSettings.Download
			
			# // Manufacturer Selections
			global:Write-LogEntry -Value "Setting Manufacturer Selections" -Severity 1
			if ($global:DATSettingsXML.Settings.Manufacturer.Dell -eq "True") {
				$DellCheckBox.Checked = $true
			}
			if ($global:DATSettingsXML.Settings.Manufacturer.HP -eq "True") {
				$HPCheckBox.Checked = $true
			}
			if (($global:DATSettingsXML.Settings.Manufacturer.Lenovo -eq "True") -and ($global:LenovoDisable -ne $true)) {
				$LenovoCheckBox.Checked = $true
			}
			if ($global:DATSettingsXML.Settings.Manufacturer.Microsoft -eq "True") {
				$MicrosoftCheckBox.Checked = $true
			}
			
			# // Import ConfigMgr Models
			global:Write-LogEntry -Value "Import ConfigMgr Models Setting" -Severity 1
			$ConfigMgrImport.Text = $global:DATSettingsXML.Settings.ConfigMgrImport.ImportModels
			
			if ($global:DATSettingsXML.Settings.DistributionSettings.BinaryDifferentialReplication -eq "True") {
				$EnableBinaryDifCheckBox.Checked = $true
			} else {
				$EnableBinaryDifCheckBox.Checked = $false
			}
			# Distribution Priority
			$DistributionPriorityCombo.Text = $global:DATSettingsXML.Settings.DistributionSettings.ReplicationPriority
			
			# // Clean Up Options	
			global:Write-LogEntry -Value "Selecting Options" -Severity 1
			if ($global:DATSettingsXML.Settings.Options.CleanUnused -eq "True") {
				$CleanUnusedCheckBox.Checked = $true
			}
			if ($global:DATSettingsXML.Settings.Options.RemoveLegacy -eq "True") {
				$RemoveLegacyDriverCheckbox.Enabled = $true
				$RemoveLegacyDriverCheckbox.Checked = $true
			}
			if ($global:DATSettingsXML.Settings.Options.RemoveLegacyBIOS -eq "True") {
				$RemoveLegacyBIOSCheckbox.Enabled = $true
				$RemoveLegacyBIOSCheckbox.Checked = $true
			}
			if ($global:DATSettingsXML.Settings.Options.RemoveDriverSource -eq "True") {
				$RemoveDriverSourceCheckbox.Enabled = $true
				$RemoveDriverSourceCheckbox.Checked = $true
			}
			if ($global:DATSettingsXML.Settings.Options.ZipCompression -eq "True") {
				$ZipCompressionCheckBox.Enabled = $true
				$ZipCompressionCheckBox.Checked = $true
			}
			if ($global:DATSettingsXML.Settings.Options.XMLLogicPackage -eq "True") {
				$CreateXMLLogicPackage.Enabled = $true
				$CreateXMLLogicPackage.Checked = $true
			}
			
			# // Proxy Server Settings
			if ($global:DATSettingsXML.Settings.ProxySettings.UseProxy -eq "True") {
				global:Write-LogEntry -Value "Enabling proxy server options" -Severity 1
				$UseProxyServerCheckbox.Checked = $true
				global:Write-LogEntry -Value "Setting proxy server address to $($global:DATSettingsXML.Settings.ProxySetting.Proxy)" -Severity 1
				$ProxyServerInput.Text = $global:DATSettingsXML.Settings.ProxySettings.Proxy
			}
			
			# Import MDT Settings
			$MDTScriptTextBox.Text = $global:DATSettingsXML.Settings.MDTSettings.ScriptLocation
			$MDTDriverStructureCombo.SelectedIndex = $global:DATSettingsXML.Settings.MDTSettings.Structure
			
			# Import MDM/MBM Diagnostic Settings
			$ConfigMgrWebURL.Text = $global:DATSettingsXML.Settings.DiagSettings.ConfigMgrWebServiceURL
			
			# Distribution Point Selections
			global:Write-LogEntry -Value "Setting Previously Selected Distribution Points / Distribution Point Groups" -Severity 1
			foreach ($XMLSelectedDP in $global:DATSettingsXML.Settings.DistributionSettings.DistributionPointName) {
				$XMLSelectedDPs.Add($XMLSelectedDP)
			}
			foreach ($XMLSelectedDPG in $global:DATSettingsXML.Settings.DistributionSettings.DistributionPointGroupName) {
				$XMLSelectedDPGs.Add($XMLSelectedDPG)
			}
			
			# Connect to Configuratio Manager Site if selected platform is not MDT
			if ($global:DATSettingsXML.Settings.DownloadSettings.DeploymentPlatform -match 'ConfigMgr') {
				if ($global:ConfigMgrValidation -ne $true) {
					Connect-ConfigMgr
				}
			}
			
			# Model Selections
			global:Write-LogEntry -Value "Setting Previously Selected Model(s)" -Severity 1
			foreach ($Model in $global:DATSettingsXML.Settings.Models.ModelSelected) {
				$XMLSelectedModels.Add($Model)
			}
		} catch {
			global:Write-LogEntry -Value "An error occurred while attempting to apply settings from DATSettings XML: $($_.Exception.Message)" -Severity 2
		}
		
	}
	
	function Write-XMLModels {
		param
		(
			[parameter(Mandatory = $true, ParameterSetName = "XMLModelListing", HelpMessage = "Set the path for the XML file.")]
			[parameter(Mandatory = $true, ParameterSetName = "XMLModelFile")]
			[parameter(Mandatory = $true)]
			[String]$XMLPath,
			[parameter(Mandatory = $true, ParameterSetName = "XMLModelListing", HelpMessage = "Specify the manufacturer")]
			[parameter(Mandatory = $true, ParameterSetName = "XMLModelFile")]
			[parameter(Mandatory = $true)]
			[String]$Make,
			[parameter(Mandatory = $true, ParameterSetName = "XMLModelListing", HelpMessage = "Specify the model name")]
			[parameter(Mandatory = $true, ParameterSetName = "XMLModelFile")]
			[parameter(Mandatory = $true)]
			[String]$Model,
			[parameter(Mandatory = $true, ParameterSetName = "XMLModelListing", HelpMessage = "Specify the matching values")]
			[parameter(Mandatory = $true, ParameterSetName = "XMLModelFile")]
			[parameter(Mandatory = $true)]
			[String]$MatchingValues,
			[parameter(Mandatory = $true, ParameterSetName = "XMLModelFile", HelpMessage = "Specify the OS")]
			[parameter(Mandatory = $true)]
			[String]$OperatingSystem,
			[parameter(Mandatory = $true, ParameterSetName = "XMLModelFile", HelpMessage = "Specify the OS Architecture")]
			[parameter(Mandatory = $true)]
			[String]$Architecture,
			[parameter(Mandatory = $false, ParameterSetName = "XMLModelListing", HelpMessage = "Specify the matching values")]
			[parameter(Mandatory = $true, ParameterSetName = "XMLModelFile")]
			[String]$Platform
		)
		
		if ((Test-Path -Path $XMLPath) -eq $false) {
			New-Item -Path $XMLPath -ItemType Dir -Force
		}
		
		# ModelDetails.XML location
		$Path = Join-Path -Path "$XMLPath" -ChildPath "ModelDetails.xml"
		
		if ((Test-Path -Path $Path) -eq $false) {
			# Create XML File Notice
			global:Write-LogEntry -Value "XML Model List : Creating XML models file in location - $Path" -Severity 1
			
			# Set XML Structure
			$XmlWriter = New-Object System.XML.XmlTextWriter($Path, $Null)
			$xmlWriter.Formatting = 'Indented'
			$xmlWriter.Indentation = 1
			$XmlWriter.IndentChar = "`t"
			$xmlWriter.WriteStartDocument()
			$xmlWriter.WriteProcessingInstruction("xml-stylesheet", "type='text/xsl' href='style.xsl'")
			
			# Write Initial Header Comments
			$XmlWriter.WriteComment('Created with the MSEndpointMgr Driver Automation Tool')
			$xmlWriter.WriteStartElement('Details')
			$XmlWriter.WriteAttributeString('current', $true)
			
			# Export Model Details 
			$xmlWriter.WriteStartElement('ModelDetails')
			$xmlWriter.WriteElementString('Make', $Make)
			$xmlWriter.WriteElementString('Model', $Model)
			$xmlWriter.WriteElementString('SystemSKU', $MatchingValues)
			$xmlWriter.WriteElementString('OperatingSystem', $OperatingSystem)
			$xmlWriter.WriteElementString('Architecture', $Architecture)
			$xmlWriter.WriteElementString('Platform', $Platform)
			$xmlWriter.WriteEndElement()
			global:Write-LogEntry -Value "XML Model List : Adding $Model to XML models file" -Severity 1
			
			# Save XML Document
			$xmlWriter.WriteEndDocument()
			$xmlWriter.Flush()
			$xmlWriter.Close()
			
		} else {
			# Read Existing XML Model List
			$xmlDoc = [System.Xml.XmlDocument](Get-Content $Path -Raw);
			
			# Check For Existing Model Entry + Append
			if ($Model -notin $xmlDoc.Details.ModelDetails.Model) {
				# Create New Make/Model Entry
				$newXmlModel = $xmlDoc.Details.AppendChild($xmlDoc.CreateElement("ModelDetails"));
				
				# Export Make Details
				$newXmlModelElement = $newXmlModel.AppendChild($xmlDoc.CreateElement("Make"));
				$newXmlModelTextNode = $newXmlModelElement.AppendChild($xmlDoc.CreateTextNode("$Make"));
				
				# Export Model Details
				$newXmlModelElement = $newXmlModel.AppendChild($xmlDoc.CreateElement("Model"));
				$newXmlModelTextNode = $newXmlModelElement.AppendChild($xmlDoc.CreateTextNode("$Model"));
				
				# Export Matching Value
				$newXmlSKUElement = $newXmlModel.AppendChild($xmlDoc.CreateElement("SystemSKU"));
				$newXmlSKUNode = $newXmlSKUElement.AppendChild($xmlDoc.CreateTextNode("$MatchingValues"));
				
				# Save XML Document
				$xmlDoc.Save($Path);
				global:Write-LogEntry -Value "XML Model List : Appending $Model to XML models file $Path" -Severity 1
			} else {
				global:Write-LogEntry -Value "XML Model List : $Model already listed in XML models file $Path" -Severity 1
			}
		}
	}
	
	function Write-SoftPaqXML {
		param
		(
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$Path,
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$SetupFile,
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$InstallSwitches,
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$BaseBoardValues,
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$SoftPaqID
		)
		
		# DATSettings.XML location
		$Path = Join-Path -Path $Path -ChildPath "Setup.xml"
		
		# Set XML Structure
		$XmlWriter = New-Object System.XMl.XmlTextWriter($Path, $Null)
		$xmlWriter.Formatting = 'Indented'
		$xmlWriter.Indentation = 1
		$XmlWriter.IndentChar = "`t"
		$xmlWriter.WriteStartDocument()
		$xmlWriter.WriteProcessingInstruction("xml-stylesheet", "type='text/xsl' href='style.xsl'")
		
		# Write Initial Header Comments
		$XmlWriter.WriteComment('Silent HP SoftPaq Installer Switches - Created with MSEndpointMgr Driver Automation Tool')
		$xmlWriter.WriteStartElement('Settings')
		$XmlWriter.WriteAttributeString('current', $true)
		
		# Write Installer Setup Details
		$xmlWriter.WriteStartElement('Installer')
		$xmlWriter.WriteElementString('ProgramName', $($SoftPaqID + " Installer"))
		$xmlWriter.WriteElementString('SetupFile', $SetupFile)
		$xmlWriter.WriteElementString('Switches', $InstallSwitches)
		$xmlWriter.WriteEndElement()
		
		# Write Supported Model Details
		$xmlWriter.WriteStartElement('Models')
		$xmlWriter.WriteElementString('BaseBoards', $BaseBoardValues)
		$xmlWriter.WriteEndElement()
		
		# Save XML Document
		$xmlWriter.WriteEndDocument()
		$xmlWriter.Flush()
		$xmlWriter.Close()
	}
	
	function Get-MSIProperties {
		param (
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[System.IO.FileInfo]$Path
		)
		
		Process {
			global:Write-LogEntry -Value "$($Product): Attempting to open MSI database on file $($Path | Split-Path -Leaf) " -Severity 1
			global:Write-LogEntry -Value "Path full name is $($Path.FullName)" -Severity 1
			
			try {
				# Read property from MSI database
				$WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
				$Database = $WindowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $Null, $WindowsInstaller, @($Path.FullName, 0))
				$Query = "SELECT * FROM Property WHERE Property = 'ProductVersion'"
				$View = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $Null, $Database, ($query))
				$View.GetType().InvokeMember("Execute", "InvokeMethod", $Null, $View, $Null)
				$Record = $View.GetType().InvokeMember("Fetch", "InvokeMethod", $Null, $View, $Null)
				$Value = $Record.GetType().InvokeMember("StringData", "GetProperty", $null, $Record, 1)
				
				# Commit database and close view
				$MSIDatabase.GetType().InvokeMember("Commit", "InvokeMethod", $null, $MSIDatabase, $null)
				$View.GetType().InvokeMember("Close", "InvokeMethod", $null, $View, $null)
				$MSIDatabase = $null
				$View = $null
				
				# Return the value
				return $Value
			} catch {
				Write-ErrorOutput -Message "$_.Exception.Message" -Severity 3
			}
		}
		End {
			# Run garbage collection and release ComObject
			[System.Runtime.Interopservices.Marshal]::ReleaseComObject($WindowsInstaller) | Out-Null
			[System.GC]::Collect()
		}
	}
	
	function Invoke-ContentExtraction {
		param
		(
			[parameter(Mandatory = $true, HelpMessage = "Driver or BIOS packaging required")]
			[ValidateSet("Drivers", "Firmware")]
			[string]$PackageType
		)
		
		# Driver Silent Extract Switches
		$MicrosoftTemp = Join-Path -Path $global:TempDirectory -ChildPath "\$Model\Win$WindowsVersion$Architecture"
		$MicrosoftTemp = $MicrosoftTemp -replace '/', '-'
		
		# Driver Silent Extract Switches
		$MicrosoftSilentSwitches = "/a" + '"' + $($DownloadRoot + $Model + "\Driver Cab\" + $DriverCab) + '"' + '/QN TARGETDIR="' + $MicrosoftTemp + '"'
		global:Write-LogEntry -Value "$($Product): Extracting $Make $($PackageType) to $MicrosoftTemp" -Severity 1
		global:Write-LogEntry -Value "$($Product): Full extraction switch is $MicrosoftSilentSwitches" -Severity 1
		$DriverProcess = Start-Process msiexec.exe -ArgumentList $MicrosoftSilentSwitches -PassThru
		
		# Wait for Microsoft Driver Process To Finish
		While ((Get-Process).ID -eq $DriverProcess.ID) {
			global:Write-LogEntry -Value "$($Product): Waiting for extract process (Process ID: $($DriverProcess.ID)) to complete. Next check in 30 seconds" -Severity 1
			Start-Sleep -seconds 30
		}
		
		# Set Microsoft extracted folder
		$MicrosoftExtractDirs = Get-ChildItem -Path $MicrosoftTemp -Directory -Recurse
		$MicrosoftExtract = $MicrosoftExtractDirs.FullName | Split-Path -Parent | Select-Object -First 1
		global:Write-LogEntry -Value "$($Product): Microsoft $PackageType source directory set to $MicrosoftExtract" -Severity 1
		if ((Test-Path -Path "$MicrosoftExtract") -eq $true) {
			Start-Job -Name "$Model-Driver-Move" -ScriptBlock $MoveDrivers -ArgumentList ($MicrosoftExtract, $DriverExtractDest)
			while ((Get-Job -Name "$Model-Driver-Move").State -eq "Running") {
				global:Write-LogEntry -Value "$($Product): Moving $Make $Model $OperatingSystem $Architecture $PackageType. Next Check In 30 Seconds" -Severity 1
				Start-Sleep -seconds 30
			}
		} else {
			global:Write-ErrorOutput -Message "Error: Issues occurred during the $Make $Model extract process" -Severity 3
		}
	}
	
	function Invoke-PackageCreation {
		param
		(
			[parameter(Mandatory = $true, HelpMessage = "Driver or BIOS packaging required")]
			[ValidateSet("Drivers", "Firmware")]
			[string]$PackageType
		)
		
		global:Write-LogEntry -Value "$($Product): Checking for extracted $($PackageType.ToLower())" -Severity 1
		global:Write-LogEntry -Value "$($Product): Import into is $ImportInto" -Severity 1
		if ($ImportInto -like "*Driver*") {
			if ((Get-ChildItem -Recurse -Path "$DriverExtractDest" -Filter *.inf -File).count -ne 0) {
				global:Write-LogEntry -Value "$($Product): Driver count in path $DriverExtractDest - $((Get-ChildItem -Recurse -Path "$DriverExtractDest" -Filter *.inf -File).count) " -Severity 1
				global:Write-LogEntry -Value "==================== $PRODUCT DRIVER IMPORT ====================" -Severity 1
				Set-Location -Path ($SiteCode + ":")
				Set-Location -Path $global:TempDirectory
				if (("$DriverPackageDest" -ne $null) -and ((Test-Path -Path "$DriverPackageDest") -eq $false)) {
					New-Item -ItemType Directory -Path "$DriverPackageDest"
				}
				global:Write-LogEntry -Value "$($Product): Creating driver package $CMDriverPackage" -Severity 1
				global:Write-LogEntry -Value "$($Product): Searching for driver INF files in $DriverExtractDest" -Severity 1
				$DriverINFFiles = Get-ChildItem -Path "$DriverExtractDest" -Recurse -Filter "*.inf" -File | Select-Object Name, FullName | Where-Object {
					$_.FullName -like "*$Architecture*"
				}
				if ($DriverINFFiles.Count -ne $null) {
					Set-Location -Path ($SiteCode + ":")
					try {
						#=====================
						
						Set-Location -Path $global:TempDirectory
						if (((Test-Path -Path "$DriverPackageDest") -eq $false) -and ($Make -ne "Lenovo")) {
							New-Item -ItemType Directory -Path "$DriverPackageDest"
						}
						# Work around for HP WMI when using the ConfigMgr Web Service
						if ($Make -eq "Hewlett-Packard") {
							$Manufacturer = "Hewlett-Packard"
						} else {
							$Manufacturer = $Make
						}
						
						# Set Package Description
						$PackageDescription = "(Models included:$global:SkuValue)"
						
						# Move Extracted Drivers To Driver Package Directory
						global:Write-LogEntry -Value "$($Product): Source directory $DriverExtractDest" -Severity 1
						global:Write-LogEntry -Value "$($Product): Destination directory $DriverPackageDest" -Severity 1
						global:Write-LogEntry -Value "$($Product): Creating Package for $Make $Model (Version $DriverRevision)" -Severity 1
						Set-Location -Path ($SiteCode + ":")
						
						if (Get-CMCategory -CategoryType DriverCategories -name $DriverCategoryName) {
							global:Write-LogEntry -Value "$($Product): Category already exists" -Severity 1
							$DriverCategory = Get-CMCategory -CategoryType DriverCategories -name $DriverCategoryName
						} else {
							global:Write-LogEntry -Value "$($Product): Creating category $DriverCategoryName" -Severity 1
							$DriverCategory = New-CMCategory -CategoryType DriverCategories -name $DriverCategoryName
						}
						
						global:Write-LogEntry -Value "$($Product): Creating driver package for $Make $Model (Version $DriverRevision)" -Severity 1
						global:Write-LogEntry -Value "$($Product): Driver package name is $CMDriverPackage" -Severity 1
						global:Write-LogEntry -Value "$($Product): Path to drivers is $DriverPackageDest" -Severity 1
						global:Write-LogEntry -Value "$($Product): Creating driver package" -Severity 1
						New-CMDriverPackage -Name $CMDriverPackage -Path "$DriverPackageDest"
						global:Write-LogEntry -Value "$($Product): New driver package name: $CMDriverPackage | Path $DriverPackageDest" -Severity 1
						Set-CMDriverPackage -Name $CMDriverPackage -Version $DriverRevision
						# Check For Driver Package
						$ConfigMgrDriverPackage = Get-CMDriverPackage -Name $CMDriverPackage | Select-Object PackageID, Version | Where-Object {
							$_.Version -eq $DriverRevision
						}
						
					} catch {
						global:Write-ErrorOutput -Message "Error: $($_.Exception.Message) $($_.Exception.InnerException)" -Severity 3
					}
					global:Write-LogEntry -Value "$($Product): Running driver import process (this might take several minutes)" -Severity 1
					if ($ConfigMgrDriverPackage.PackageID -ne $null) {
						# Import Driver Loop
						try {
							$DriverImportStart = (Get-Date)
							$DriverNo = 1
							
							foreach ($DriverINF in $DriverINFFiles) {
								$DriverInfo = Import-CMDriver -UncFileLocation "$($DriverINF.FullName)" -ImportDuplicateDriverOption AppendCategory -EnableAndAllowInstall $True -AdministrativeCategory $DriverCategory | Select-Object CI_ID
								global:Write-LogEntry -Value "$($Product): Adding driver $($DriverINF.FullName | Split-Path -Leaf) to driver pack" -Severity 1
								Add-CMDriverToDriverPackage -DriverID $DriverInfo.CI_ID -DriverPackageName "$($CMDriverPackage)"
								$DriverNo++
							}
							
							$DriverImportEnd = (Get-Date)
							$DriverImportDuration = $DriverImportEnd - $DriverImportStart
							global:Write-LogEntry -Value "$($Product): Import process duration was $($DriverImportDuration.Minutes) minutes $($DriverImportDuration.Minutes) seconds" -Severity 1
							global:Write-LogEntry -Value "$($Product): Driver package $($ConfigMgrDriverPackage.PackageID) created succesfully" -Severity 1
							# =============== Distrubute Content =================
							global:Write-LogEntry -Value "$($Product): Distributing $($ConfigMgrDriverPackage.PackageID)" -Severity 1
							Distribute-Content -Product $Product -PackageID $ConfigMgrDriverPackage.PackageID -ImportInto $ImportInto
						} catch {
							global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
						}
					} else {
						global:Write-ErrorOutput -Message "Error: Errors occurred while creating driver package" -Severity 3
					}
					Set-Location -Path $global:TempDirectory
				} else {
					global:Write-LogEntry -Value "$($Product): Extract folder empty.. Skipping driver import / package creation" -Severity 2
				}
				Set-Location -Path $global:TempDirectory
			} else {
				global:Write-LogEntry -Value "======== DRIVER EXTRACT ISSUE DETECTED ========" -Severity 3
				global:Write-LogEntry -Value "$($Product): Issues occurred while reading extracted drivers" -Severity 3
				global:Write-LogEntry -Value "$($Product): Driver count in path $DriverExtractDest - $((Get-ChildItem -Recurse -Path "$DriverExtractDest" -Filter *.inf -File).count) " -Severity 1
			}
		}
		if ($ImportInto -like "*Standard*") {
			if ($PackageType -match "Drivers") {
				global:Write-LogEntry -Value "$($Product): Driver count in path $DriverExtractDest - $((Get-ChildItem -Recurse -Path "$DriverExtractDest" -Filter *.inf -File).count) " -Severity 1
				if ((Get-ChildItem -Recurse -Path "$DriverExtractDest" -Filter *.inf -File).Count -ne $null) {
					global:Write-LogEntry -Value "$($Product): Validated drivers exist in $DriverExtractDest - Processing driver packaging steps " -Severity 1
					global:Write-LogEntry -Value "==================== $PRODUCT DRIVER PACKAGE  ====================" -Severity 1
					
					if ([string]::IsNullOrEmpty($ExistingPackageID)) {
						Set-Location -Path $global:TempDirectory
						if ((Test-Path -Path "$DriverPackageDest") -eq $false) {
							New-Item -ItemType Directory -Path "$DriverPackageDest"
						}
						# Work around for HP WMI when using the ConfigMgr Web Service
						if ($Make -eq "Hewlett-Packard") {
							$Manufacturer = "Hewlett-Packard"
						} else {
							$Manufacturer = $Make
						}
						
						# Set Package Description
						$PackageDescription = "(Models included:$global:SkuValue)"
						
						# Move Extracted Drivers To Driver Package Directory
						global:Write-LogEntry -Value "$($Product): Source directory $DriverExtractDest" -Severity 1
						global:Write-LogEntry -Value "$($Product): Destination directory $DriverPackageDest" -Severity 1
						
						# Copy Drivers To Package Location
						$DriverPackageCreated = New-DriverPackage -Make $Make -DriverExtractDest $DriverExtractDest -Architecture $Architecture -DriverPackageDest $DriverPackageDest -ZipCompression $ZipCompressionCheckBox.Checked -ZipType $CompressionType.Text
						
						if ($DriverPackageCreated -eq $true) {
							global:Write-LogEntry -Value "$($Product): Drivers copied successfully, creating package." -Severity 1
							global:Write-LogEntry -Value "$($Product): Creating Package for $Make $Model (Version $DriverRevision)" -Severity 1
							Set-Location -Path ($SiteCode + ":")
							
							# Create Driver Package
							New-CMPackage -Name "$CMPackage" -path "$DriverPackageDest" -Manufacturer $Manufacturer -Description "$PackageDescription" -Version $DriverRevision
							$MifVersion = $OperatingSystem + " " + $Architecture
							Set-CMPackage -Name "$CMPackage" -MifName $Model -MifVersion $MifVersion
							
							# Check For Driver Package
							$ConfiMgrPackage = Get-CMPackage -Name $CMPackage -Fast | Select-Object PackageID, Version, Name | Where-Object {
								$_.Version -eq $DriverRevision
							}
							Move-CMObject -FolderPath $global:VendorDriverFolder -ObjectID $ConfiMgrPackage.PackageID
							global:Write-LogEntry -Value "$($Product): Checking for driver package $CMPackage with version number $DriverRevision" -Severity 1
							if ($ConfiMgrPackage.PackageID -ne $null) {
								global:Write-LogEntry -Value "$($Product): Driver package $($ConfiMgrPackage.PackageID) created succesfully" -Severity 1
								if ($EnableBinaryDifCheckBox.Checked -eq $true) {
									global:Write-LogEntry -Value "$($Product): Enabling Binary Delta Replication" -Severity 1
									Set-CMPackage -ID $ConfiMgrPackage.PackageID -EnableBinaryDeltaReplication $true -Priority $DistributionPriorityCombo.Text
								}
								# =============== Distrubute Content =================
								Distribute-Content -Product $Product -PackageID $ConfiMgrPackage.PackageID -ImportInto $ImportInto
							} else {
								global:Write-ErrorOutput -Message "Error: Errors occurred while creating package" -Severity 3
							}
						} else {
							global:Write-ErrorOutput -Message "Error: Errors occurred while copying drivers" -Severity 3
						}
						Set-Location -Path $global:TempDirectory
					} else {
						global:Write-LogEntry -Value "$($Product): Driver package already exists (Package ID: $($ExistingPackageID.PackageID))." -Severity 2
						Set-Location -Path ($SiteCode + ":")
						if (($ExistingPackageID.Description -notcontains "(Models included:") -eq $true) {
							Set-CMPackage -ID $ExistingPackageID.PackageID -Description "(Models included:$global:SkuValue)"
							global:Write-LogEntry -Value "$($Product): Updating driver package description to include system model ID $global:SkuValue" -Severity 1
							Set-Location -Path $global:TempDirectory
						}
					}
				} else {
					global:Write-LogEntry -Value "======== DRIVER EXTRACT ISSUE DETECTED ========" -Severity 3
					global:Write-LogEntry -Value "$($Product): Issues occurred while reading extracted drivers" -Severity 3
					global:Write-LogEntry -Value "$($Product): Driver count in path $DriverExtractDest - $((Get-ChildItem -Recurse -Path "$DriverExtractDest" -Filter *.inf -File).count) " -Severity 1
				}
			} elseif ($PackageType -match "Firmware") {
				# Modify package name
				$CMPackage = ("BIOS - " + "$Make " + $Model)
				
				global:Write-LogEntry -Value "$($Product): Firmware count in path $FirmwareExtractDest - $((Get-ChildItem -Recurse -Path "$FirmwareExtractDest" -Filter *.inf -File).count) " -Severity 1
				if ((Get-ChildItem -Recurse -Path "$FirmwareExtractDest" -Filter *.inf -File).Count - $null) {
					global:Write-LogEntry -Value "$($Product): Validated drivers exist in $FirmwareExtractDest - Processing driver packaging steps " -Severity 1
					global:Write-LogEntry -Value "==================== $PRODUCT FIRMWARE PACKAGE  ====================" -Severity 1
					
					if ([string]::IsNullOrEmpty($ExistingPackageID)) {
						Set-Location -Path $global:TempDirectory
						if ((Test-Path -Path "$FirmwareExtractDest") -eq $false) {
							New-Item -ItemType Directory -Path "$FirmwareExtractDest"
						}
						# Work around for HP WMI when using the ConfigMgr Web Service
						if ($Make -eq "Hewlett-Packard") {
							$Manufacturer = "Hewlett-Packard"
						} else {
							$Manufacturer = $Make
						}
						
						# Set Package Description
						$PackageDescription = "$Make $Model Windows $WindowsVersion $Architecture Firmware (Models included:$global:SkuValue) "
						
						# Move extracted files to firmware package Directory
						global:Write-LogEntry -Value "$($Product): Source directory $FirmwareExtractDest" -Severity 1
						global:Write-LogEntry -Value "$($Product): Destination directory $FirmwarePackageDest" -Severity 1
						Start-Job -Name "$Model-Firmware-Package" -ScriptBlock $PackageDrivers -ArgumentList ($Make, $FirmwareExtractDest, $Architecture, $FirmwarePackageDest)
						while ((Get-Job -Name "$Model-Firmware-Package").State -eq "Running") {
							global:Write-LogEntry -Value "$($Product): Copying $Make $Model $OperatingSystem $Architecture firmware files.. Next check in 30 seconds" -Severity 1
							Start-Sleep -seconds 30
						}
						while ((Get-Job -Name "$Model-Firmware-Package").State -eq "Stopping") {
							Start-Sleep -Seconds 1
						}
						
						if ((Get-Job -Name "$Model-Firmware-Package").State -eq "Completed") {
							Set-Location -Path ($SiteCode + ":")
							
							# Create Firmware Package
							global:Write-LogEntry -Value "$($Product): Creating package for $Make $Model (Version $DriverRevision)" -Severity 1
							New-CMPackage -Name "$CMPackage" -path "$FirmwarePackageDest" -Manufacturer $Manufacturer -Description "$PackageDescription" -Version $DriverRevision
							$MifVersion = $OperatingSystem + " " + $Architecture
							Set-CMPackage -Name "$CMPackage" -MifName $Model -MifVersion $MifVersion
							
							# Check For Driver Package
							$ConfiMgrPackage = Get-CMPackage -Name $CMPackage -Fast | Select-Object PackageID, Version, Name | Where-Object {
								$_.Version -eq $DriverRevision
							}
							Move-CMObject -FolderPath $global:VendorBIOSFolder -ObjectID $ConfiMgrPackage.PackageID
							global:Write-LogEntry -Value "$($Product): Checking for firmware package $CMPackage with version number $DriverRevision" -Severity 1
							if ($ConfiMgrPackage.PackageID -ne $null) {
								global:Write-LogEntry -Value "$($Product): Driver package $($ConfiMgrPackage.PackageID) created succesfully" -Severity 1
								if ($EnableBinaryDifCheckBox.Checked -eq $true) {
									global:Write-LogEntry -Value "$($Product): Enabling Binary Delta Replication" -Severity 1
									Set-CMPackage -ID $ConfiMgrPackage.PackageID -EnableBinaryDeltaReplication $true -Priority $DistributionPriorityCombo.Text
								}
								# =============== Distrubute Content =================
								Distribute-Content -Product $Product -PackageID $ConfiMgrPackage.PackageID -ImportInto $ImportInto
							} else {
								global:Write-ErrorOutput -Message "Error: Errors occurred while creating package" -Severity 3
							}
						} else {
							global:Write-ErrorOutput -Message "Error: Errors occurred while copying firmware" -Severity 3
						}
						Set-Location -Path $global:TempDirectory
					} else {
						global:Write-LogEntry -Value "$($Product): Firmware package already exists (Package ID: $($ExistingPackageID.PackageID))." -Severity 2
						Set-Location -Path ($SiteCode + ":")
						if (($ExistingPackageID.Description -notcontains "(Models included:") -eq $true) {
							Set-CMPackage -ID $ExistingPackageID.PackageID -Description "(Models included:$global:SkuValue)"
							global:Write-LogEntry -Value "$($Product): Updating firmware package description to include system model ID $global:SkuValue" -Severity 1
							Set-Location -Path $global:TempDirectory
						}
					}
				} else {
					global:Write-LogEntry -Value "======== DRIVER FIRMWARE ISSUE DETECTED ========" -Severity 3
					global:Write-LogEntry -Value "$($Product): Issues occurred while reading extracted firmware" -Severity 3
					global:Write-LogEntry -Value "$($Product): Firmware count in path $DriverExtractDest - $((Get-ChildItem -Recurse -Path "$DriverExtractDest" -Filter *.inf -File).count) " -Severity 1
				}
				Get-Job -Name "$Model-Firmware-Package" | Remove-Job
			}
		}
	}
	
	function Read-XMLFile {
		param
		(
			[parameter(Mandatory = $true, HelpMessage = "Set the path for the XML file.")]
			[String]$XMLFile
		)
		
		# // Read in settings XML		
		[xml]$ModelDetails = Get-Content -Path $XMLFile -Raw
		
		# Set XML Object
		$ModelDetails.GetType().FullName
		$CustomPkgDataGrid.Rows.Add($ModelDetails.Details.ModelDetails.Make, $ModelDetails.Details.ModelDetails.Model, $ModelDetails.Details.ModelDetails.SystemSKU, $CustomPkgPlatform.SelectedItem, $ModelDetails.Details.ModelDetails.OperatingSystem, $ModelDetails.Details.ModelDetails.Architecture, 01, $($XMLFile | Split-Path -Parent))
		
	}
	
	function Invoke-SoftPaqCreation {
		param
		(
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqID,
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqTitle,
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqVersion,
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqPkgPath,
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqFileName,
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqOSBuilds,
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqSwitches
		)
		
		# Set Variables
		$Product = "ConfigMgr"
		$Make = "Hewlett-Packard"
		$HPSoftPaqTitle = "SoftPaq - $Make - $HPSoftPaqTitle"
		
		if (($Product -ne "Download Only") -and ((Test-Path -Path $(Join-Path -Path $HPSoftPaqPkgPath -ChildPath $HPSoftPaqFileName))) -eq $true) {
			# ================= Create SoftPaq Update Package ==================			
			Set-Location -Path ($SiteCode + ":")
			$SoftPaqPackage = Get-CMPackage -Name $HPSoftPaqTitle -Fast | Select-Object SourceDate, Version | Sort-Object SourceDate -Descending | Select-Object -First 1
			if (($SoftPaqPackage.Version -ne $HPSoftPaqVersion) -or ($SoftPaqPackage -eq $null)) {
				global:Write-LogEntry -Value "$($Product): Creating SoftPaq Package" -Severity 1
				New-CMPackage -Name "$HPSoftPaqTitle" -Path "$HPSoftPaqPkgPath" -Description "Models included in XML package. Supported Win10 builds ($HPSoftPaqOSBuilds)" -Manufacturer $Make -Language English -version $HPSoftPaqVersion
				if ($EnableBinaryDifCheckBox.Checked -eq $true) {
					global:Write-LogEntry -Value "$($Product): Enabling Binary Delta Replication" -Severity 1
					Set-CMPackage -Name "$HPSoftPaqTitle" -EnableBinaryDeltaReplication $true -Priority "$($DistributionPriorityCombo.Text)"
				}
				$ConfiMgrPackage = Get-CMPackage -Name $HPSoftPaqTitle -Fast | Select-Object PackageID, Version, Name | Where-Object {
					$_.Version -eq $HPSoftPaqVersion
				}
				Start-Sleep -Seconds 5
				global:Write-LogEntry -Value "$($Product): Creating installer program in Package ID $($ConfiMgrPackage.PackageID)" -Severity 1
				New-CMProgram -PackageID $($ConfiMgrPackage.PackageID) -CommandLine "$HPSoftPaqFileName $HPSoftPaqSwitches" -StandardProgramName "$HPSoftPaqID Installer" -duration 15 -ProgramRunType WhetherOrNotUserIsLoggedOn -RunMode RunWithAdministrativeRights
				Start-Sleep -Seconds 5
				global:Write-LogEntry -Value "$($Product): Enabling dynamic deployment for Package ID $($ConfiMgrPackage.PackageID)" -Severity 1
				$PackageQuery = Get-WmiObject -Namespace "Root\sms\Site_$($SiteCodeText.Text)" -Class SMS_Program -ComputerName $SiteServerInput.Text -Filter "PackageID='$($ConfiMgrPackage.PackageID)'"
				foreach ($Program in $PackageQuery) {
					If (($Program.ProgramFlags -band ([math]::pow(2, 0))) -eq 0) {
						global:Write-LogEntry -Value "$($Product): Setting enabled flag on program `"$($Program.ProgramName)`"" -Severity 1
						$Program.ProgramFlags = $Program.ProgramFlags -bor ([math]::pow(2, 0))
						# Commit changes
						$Program.put()
					}
				}
				$SoftPaqFolder = [string](Join-Path -Path $global:VendorDriverFolder -ChildPath "SoftPaqs")
				if ((Test-Path -Path $SoftPaqFolder) -eq $false) {
					global:Write-LogEntry -Value "$($Product): Creating folder for SoftPaqs in the console" -Severity 1
					New-Item -Path $SoftPaqFolder
				}
				global:Write-LogEntry -Value "$($Product): Moving package $($ConfiMgrPackage.PackageID) to SoftPaq folder" -Severity 1
				Move-CMObject -FolderPath $SoftPaqFolder -ObjectID $ConfiMgrPackage.PackageID
				Set-Location -Path $global:TempDirectory
				# =============== Distrubute Content =================
				Set-Location -Path ($SiteCode + ":")
				$ConfiMgrPackage = Get-CMPackage -Name $HPSoftPaqTitle -Fast | Select-Object PackageID, Version | Where-Object {
					$_.Version -eq $HPSoftPaqVersion
				}
				Move-CMObject -FolderPath $SoftPaqFolder -ObjectID $ConfiMgrPackage.PackageID
				#global:Write-LogEntry -Value "$($Product): Distributing content to selected distribut" -Severity 1
				Distribute-Content -Product $Product -PackageID $ConfiMgrPackage.PackageID -ImportInto "Standard"
				Set-Location -Path $global:TempDirectory
			}
		}
	}
	
	function Invoke-ContentDownload {
		param
		(
			[parameter(Mandatory = $true, ParameterSetName = "StandardContent")]
			[parameter(Mandatory = $true, ParameterSetName = "HPSoftPaq")]
			[ValidateNotNullOrEmpty()]
			[ValidateSet("StandardPackages", "DriverAppPackages")]
			[string]$OperationalMode,
			
			[parameter(Mandatory = $true, ParameterSetName = "HPSoftPaq")]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqID,
			
			[parameter(Mandatory = $true, ParameterSetName = "HPSoftPaq")]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqTitle,
			
			[parameter(Mandatory = $true, ParameterSetName = "HPSoftPaq")]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqVersion,
			
			[parameter(Mandatory = $true, ParameterSetName = "HPSoftPaq")]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqURL,
			
			[parameter(Mandatory = $true, ParameterSetName = "HPSoftPaq")]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqSwitches,
			
			[parameter(Mandatory = $true, ParameterSetName = "HPSoftPaq")]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqBaseBoards,
			
			[parameter(Mandatory = $true, ParameterSetName = "HPSoftPaq")]
			[ValidateNotNullOrEmpty()]
			[string]$HPSoftPaqPkgPath
		)
		
		# Content Download ScriptBlock
		$HPSoftPaqDownloadJob = {
			Param (
				[parameter(Mandatory = $true)]
				[string]$HPSoftPaqID,
				[parameter(Mandatory = $false)]
				[string]$HPSoftPaqPkgPath,
				[parameter(Mandatory = $true)]
				[string]$DriverDownloadURL,
				[parameter(Mandatory = $false)]
				$global:BitsProxyOptions,
				[parameter(Mandatory = $false)]
				$global:BitsOptions,
				[parameter(Mandatory = $false)]
				$global:ProxySettingsSet
			)
			
			try {
				# Start SoftPaq Driver Download
				if ($global:ProxySettingsSet -eq $true) {
					Start-BitsTransfer -DisplayName "$HPSoftPaqID-SoftPaqDownload" -Source $DriverDownloadURL.Trim() -Destination $HPSoftPaqPkgPath @global:BitsProxyOptions
				} else {
					Start-BitsTransfer -DisplayName "$HPSoftPaqID-SoftPaqDownload" -Source $DriverDownloadURL.Trim() -Destination $HPSoftPaqPkgPath @global:BitsOptions
				}
			} catch [System.Exception] {
				global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
			}
		}
		
		try {
			switch ($OperationalMode) {
				"StandardPackages" {
					if ((Test-Path -Path $("$DownloadRoot" + "$Model" + "\Driver Cab\" + "$DriverCab")) -eq $false) {
						global:Write-LogEntry -Value "$($Product): Creating $Model download folder" -Severity 1
						if ((Test-Path -Path $("$DownloadRoot" + "$Model" + "\Driver Cab")) -eq $false) {
							global:Write-LogEntry -Value "$($Product): Creating $("$DownloadRoot" + "$Model" + "\Driver Cab") folder " -Severity 1
							New-Item -ItemType Directory -Path $("$DownloadRoot" + "$Model" + "\Driver Cab")
						}
						
						global:Write-LogEntry -Value "$($Product): Downloading $($DriverCab)" -Severity 1
						global:Write-LogEntry -Value "$($Product): Downloading from URL: $($DriverDownload)" -Severity 1
						Start-Job -Name "$Model-DriverDownload" -ScriptBlock $ContentDownloadJob -ArgumentList ($DownloadRoot, $Model, $DriverCab, $DriverDownload, $global:BitsProxyOptions, $global:BitsOptions, $global:ProxySettingsSet)
						Start-Sleep -Seconds 5
						while ((Get-Job -Name "$Model-DriverDownload").State -eq "Running") {
							Invoke-BitsJobMonitor -BitsJobName "$Model-DriverDownload" -DownloadSource $DriverDownload
						}
						Get-BitsTransfer | Where-Object {
							$_.DisplayName -eq "$Model-DriverDownload"
						} | Complete-BitsTransfer
						Start-Sleep -Milliseconds 250
						global:Write-LogEntry -Value "$($Product): Reported file byte size size: $global:BitsJobByteSize" -Severity 1
						global:Write-LogEntry -Value "$($Product): Downloaded file byte size:  $((Get-Item -Path $($DownloadRoot + $Model + '\Driver Cab\' + $DriverCab)).Length)" -Severity 1
						$global:PreviousDownload = $false
					} else {
						$global:PreviousDownload = $true
						global:Write-LogEntry -Value "$($Product): Skipping $DriverCab. Content previously downloaded." -Severity 1
					}
				}
				"DriverAppPackages" {
					if ((Test-Path -Path $HPSoftPaqPkgPath) -eq $false) {
						global:Write-LogEntry -Value "SoftPaq: Creating HP SoftPaq $HPSoftPaqID download folder - $HPSoftPaqPkgPath" -Severity 1
						New-Item -ItemType Directory -Path $HPSoftPaqPkgPath -Force | Out-Null
						global:Write-LogEntry -Value "SoftPaq: Downloading SoftPaq $($HPSoftPaqID)" -Severity 1
						global:Write-LogEntry -Value "SoftPaq: Downloading from URL: $($HPSoftPaqURL)" -Severity 1
						Start-Job -Name "$HPSoftPaqID-SoftPaqDownload" -ScriptBlock $HPSoftPaqDownloadJob -ArgumentList ($HPSoftPaqID, $HPSoftPaqPkgPath, $HPSoftPaqURL, $global:BitsProxyOptions, $global:BitsOptions, $global:ProxySettingsSet)
						Start-Sleep -Seconds 10
						while ((Get-Job -Name "$HPSoftPaqID-SoftPaqDownload").State -eq "Running") {
							Invoke-BitsJobMonitor -BitsJobName "$HPSoftPaqID-SoftPaqDownload" -DownloadSource $HPSoftPaqURL
						}
						Get-BitsTransfer | Where-Object {
							$_.DisplayName -eq "$HPSoftPaqID-SoftPaqDownload"
						} | Complete-BitsTransfer
						Start-Sleep -Milliseconds 250
						global:Write-LogEntry -Value "SoftPaq: Reported file byte size size: $global:BitsJobByteSize" -Severity 1
						$HPSoftPaqFileName = $($HPSoftPaqURL | Split-Path -Leaf)
						global:Write-LogEntry -Value "SoftPaq: Downloaded file byte size: $((Get-Item -Path $(Join-Path -Path $HPSoftPaqPkgPath -ChildPath $HPSoftPaqFileName)).Length)" -Severity 1
						$global:PreviousDownload = $false
					} else {
						$global:PreviousDownload = $true
						global:Write-LogEntry -Value "SoftPaq: Skipping $HPSoftPaqID. Content previously downloaded." -Severity 1
					}
				}
			}
		} catch [System.Exception] {
			global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3; Return $false
		}
	}
	
	function Invoke-Downloads {
		param
		(
			[parameter(Mandatory = $false)]
			[ValidateSet("ModelPackages", "OEMDriverPackages")]
			$DownloadJobType = "ModelPackages"
		)
		
		# Reset file size
		$FileSize.Text = "--"
		
		# Reset Progress Bar
		$ProgressBar.Value = "0"
		$ModelProgressOverlay.Value = "0"
		$ProgressListBox.ForeColor = 'Black'
		
		# Set Variables Retrieved From GUI
		$ImportInto = [string]$PlatformComboBox.SelectedItem
		global:Write-LogEntry -Value "Info: Importing Into Products: $ImportInto" -Severity 1
		$DownloadType = [string]$DownloadComboBox.SelectedItem
		global:Write-LogEntry -Value "Info: Download Type: $DownloadType" -Severity 1
		$SiteCode = $SiteCodeText.Text
		
		# Set Models 
		$ImportModels = New-Object -TypeName System.Collections.ArrayList
		for ($Row = 0; $Row -lt $MakeModelDataGrid.RowCount; $Row++) {
			if ($MakeModelDataGrid.Rows[$Row].Cells[0].Value -eq $true) {
				$ImportModels.Add($MakeModelDataGrid.Rows[$Row].Cells[1].Value + " " + $MakeModelDataGrid.Rows[$Row].Cells[2].Value)
			}
		}
		
		# Set Initial Validation State
		$ValidationErrors = 0
		
		# ============ Validation Selection Details and Prerequisites ==============
		
		# Reset Job Process Log Dialog 
		if (($ProgressListBox.ForeColor) -eq "Maroon") {
			$ProgressListBox.Items.Clear()
		}
		
		# Validate Selected Models
		if ((($ImportModels.Count) -lt "1") -and (($global:HPSoftPaqDownloads.Count) -lt "1")) {
			global:Write-ErrorOutput -Message "Error: No models or softpaqs selected" -Severity 3
			$ValidationErrors++
		}
		
		# Validate Download Path
		if ([string]::IsNullOrEmpty($DownloadPathTextBox.Text)) {
			global:Write-ErrorOutput -Message "Error: Download path not specified on ConfigMgr Settings tab" -Severity 3
			$ValidationErrors++
		}
		
		# Validate Download and Package Paths are different
		if ($DownloadPathTextBox.Text -ne $PackagePathTextBox.Text) {
			# Validate Download Path For BIOS & Driver Downloads
			if ((Test-Path -Path $DownloadPathTextBox.Text) -eq $true) {
				$DownloadPath = [string]$DownloadPathTextBox.Text
				global:Write-LogEntry -Value "Pre-Check: Download path set To $DownloadPath" -Severity 1
			} else {
				global:Write-ErrorOutput -Message "Error: UNC download path specified could not be found $($DownloadPathTextBox.Text)" -Severity 3
				$ValidationErrors++
			}
			# Validate Package Path For ConfigMgr Driver Imports
			if (($ImportInto -like "ConfigMgr*") -or ($ImportInto -like "Both*")) {
				if (![string]::IsNullOrEmpty($PackagePathTextBox.Text)) {
					if ((Test-Path -path $PackagePathTextBox.Text) -eq $true) {
						$PackagePath = [string]$PackagePathTextBox.Text
					} else {
						global:Write-ErrorOutput -Message "Error: UNC package path specified could not be found $($PackagePathTextBox.Text)" -Severity 3
						$ValidationErrors++
					}
				} else {
					global:Write-ErrorOutput -Message "Error: Package path is empty" -Severity 3
					$ValidationErrors++
				}
			}
		} else {
			global:Write-ErrorOutput -Message "Error: Download and package paths must be different." -Severity 3
			$ValidationErrors++
		}
		
		# Validate OS Selection
		if (($OSComboBox).Text -ne $null) {
			$WindowsVersion = (($OSComboBox).Text).Split(" ")[1]
		} else {
			global:Write-ErrorOutput -Message "Error: Operating System not specified" -Severity 3
			$ValidationErrors++
		}
		
		# Validate OS Architecture Selection
		if (($ArchitectureComboxBox).Text -ne $null) {
			switch -wildcard ($ArchitectureComboxBox.Text) {
				"*32*" {
					$Architecture = "x86"
				}
				"*64*" {
					$Architecture = "x64"
				}
			}
		} else {
			global:Write-ErrorOutput -Message "Error: Operating System architecture not specified" -Severity 3
			$ValidationErrors++
		}
		
		# Validate MDT Selections
		if ($ImportInto -match "MDT") {
			$DeploymentShareCount = 0
			$DeploymentShareGrid.Rows | Where-Object {
				$_.Cells[0].Value -eq $true
			} | ForEach-Object {
				$DeploymentShareCount++
			}
			if ($DeploymentShareCount -eq 0) {
				global:Write-ErrorOutput -Message "Error: No MDT deployment shares selected. Please select at least one deployment share." -Severity 3
				$ValidationErrors++
			}
		}
		
		# Validate MDT PowerShell availability
		if ($global:MDTValidation -eq $false) {
			global:Write-ErrorOutput -Message "Error: MDT PowerShell cmdlets have not been loaded." -Severity 3
			$ValidationErrors++
		}
		
		# Content Download ScriptBlock
		$ContentDownloadJob = {
			Param (
				[parameter(Mandatory = $true)]
				[string]$DownloadRoot,
				[parameter(Mandatory = $true)]
				[string]$Model,
				[parameter(Mandatory = $true)]
				[string]$DriverCab,
				[parameter(Mandatory = $true)]
				[string]$DriverDownloadURL,
				[parameter(Mandatory = $false)]
				$global:BitsProxyOptions,
				[parameter(Mandatory = $false)]
				$global:BitsOptions,
				[parameter(Mandatory = $false)]
				$global:ProxySettingsSet,
				[parameter(Mandatory = $false)]
				[string]$HPSoftPaqName,
				[parameter(Mandatory = $false)]
				[boolean]$SoftpaqDownload = $false
			)
			
			try {
				# Start Driver Download
				
				if ($SoftpaqDownload -eq $false) {
					if ($global:ProxySettingsSet -eq $true) {
						Start-BitsTransfer -DisplayName "$Model-DriverDownload" -Source $DriverDownloadURL.Trim() -Destination "$($DownloadRoot + $Model + '\Driver Cab\' + $DriverCab)" @global:BitsProxyOptions
					} else {
						Start-BitsTransfer -DisplayName "$Model-DriverDownload" -Source $DriverDownloadURL.Trim() -Destination "$($DownloadRoot + $Model + '\Driver Cab\' + $DriverCab)" @global:BitsOptions
					}
				} else {
					if ($global:ProxySettingsSet -eq $true) {
						Start-BitsTransfer -DisplayName "$HPSoftPaqName-SoftPaqDownload" -Source $DriverDownloadURL.Trim() -Destination "$($DownloadRoot + 'SoftPaqs\' + $HPSoftPaqName + '\' + $DriverCab)" @global:BitsProxyOptions
					} else {
						Start-BitsTransfer -DisplayName "$HPSoftPaqName-SoftPaqDownload" -Source $DriverDownloadURL.Trim() -Destination "$($DownloadRoot + 'SoftPaqs\' + $HPSoftPaqName + '\' + $DriverCab)" @global:BitsOptions
					}
				}
			} catch [System.Exception] {
				global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
			}
		}
		
		# Driver Download ScriptBlock
		$DriverExtractJob = {
			Param ([string]$DriverSourceCab,
				[string]$DriverExtractDest)
			try {
				Expand $DriverSourceCab -F:* $DriverExtractDest -R | Out-Null
			} catch [System.Exception] {
				global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
			}
		}
		
		# Move HP Driver Function
		$MoveDrivers = {
			Param ($ExtractSource,
				$ExtractDest)
			
			try {
				if ((Test-Path -Path "$ExtractDest") -eq $false) {
					New-Item -Path "$ExtractDest" -ItemType Dir
				}
				Get-ChildItem -Path "$ExtractSource" -Recurse | Move-Item -Destination "$ExtractDest" -Force
				
			} catch [System.Exception] {
				global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
			}
		}
		
		# Validate MDT PowerShell Commandlets / Install 
		if ((($ImportInto) -like ("MDT" -or "Both*")) -and ($ValidationErrors -eq 0)) {
			# Validate MDT PS Commandlets
			if ((Test-Path -Path $MDTPSCommandlets) -eq $true) {
				# Import MDT Module
				global:Write-LogEntry -Value "$($Product): Importing: MDT PowerShell Commandlets" -Severity 1
				Import-Module $MDTPSCommandlets
			} else {
				global:Write-ErrorOutput -Message "Error: MDT PowerShell Commandlets file not found at $MDTPSCommandlets" -Severity 3
				$ValidationErrors++
			}
		}
		
		if ($ValidationErrors -eq 0 -and $DownloadJobType -eq "ModelPackages") {
			global:Write-LogEntry -Value "======== Starting Download Processes ========" -Severity 1
			if ($ProductListBox.SelectedItems -ge 1) {
				#global:Write-LogEntry -Value "Info: Models selected: $($ProductListBox.SelectedItems)" -Severity 1
				global:Write-LogEntry -Value "Info: Models selected: $($ImportModels)" -Severity 1
			} else {
				#global:Write-LogEntry -Value "Info: Models selected: $($ProductListBox.Items)" -Severity 1
				global:Write-LogEntry -Value "Info: Models selected: $($ImportModels)" -Severity 1
			}
			global:Write-LogEntry -Value "Info: Operating System specified: Windows $($WindowsVersion)" -Severity 1
			global:Write-LogEntry -Value "Info: Operating System architecture specified: $($Architecture)" -Severity 1
			global:Write-LogEntry -Value "Info: Site Code specified: $($SiteCode)" -Severity 1
			global:Write-LogEntry -Value "Info: Download Path specified: $($DownloadPath)" -Severity 1
			global:Write-LogEntry -Value "Info: Package Path specified: $($PackagePath)" -Severity 1
			
			# Operating System Version
			$OperatingSystem = ("Windows " + $($WindowsVersion))
			
			# Lookup OS Build Number 
			if ($OSComboBox.Text -like "Windows 10 *") {
				global:Write-LogEntry -Value "Info: Windows 10 build lookup required" -Severity 1
				# Extract Windows 10 Version Number
				$OSVersion = ([string]($OSComboBox).Text).Split(' ')[2]
				# Get Windows Build Number From Version Hash Table
				$OSBuild = $WindowsBuildHashTable.Item([int]$OSVersion)
				global:Write-LogEntry -Value "Info: Windows 10 build $OSBuild and version $OSVersion identified for driver match" -Severity 1
			} else {
				$OSVersion = ([string]($OSComboBox).Text).Split(' ')[1]
			}
			
			# Set Progress Bar Values
			$TotalDownloadsCount = $ImportModels.Count
			if ($global:HPSoftPaqDownloads.Count -ge "1") {
				$TotalDownloadsCount = $TotalDownloadsCount + $global:HPSoftPaqDownloads.Count
			}
			$RemainingModels = $ImportModels.Count
			
			# Initialise Job Progress Bar
			$ProgressBar.Maximum = $TotalDownloadsCount
			$ModelProgressOverlay.Maximum = $TotalDownloadsCount
			
			foreach ($Model in $ImportModels) {
				global:Write-LogEntry -Value "======== Processing $Model Downloads ========" -Severity 1
				# Vendor Make
				$Make = $($Model).split(" ")[0]
				$Model = $($Model).TrimStart("$Make")
				$Model = $Model.Trim()
				
				# Reset SKU variable
				$global:SkuValue = $null
				
				global:Write-LogEntry -Value "Info: Starting Download, extract and import processes for $Make model: $($Model)" -Severity 1
				$CurrentDownload.Text = "$Model"
				$TotalDownloads.Text = "$($ImportModels.Count)"
				
				# =================== DEFINE VARIABLES =====================
				
				# Directory used for driver and BIOS downloads
				$DownloadRoot = ($DownloadPath.Trimend("\") + "\$Make\")
				
				# Directory used by ConfigMgr for packages
				if ($ImportInto -like "*ConfigMgr*") {
					$PackageRoot = ($PackagePath.Trimend("\") + "\$Make\")
				} elseif ($ImportInto -match "Download") {
					$PackageRoot = $DownloadRoot
				}
				
				# =================== VENDOR SPECIFIC SETTINGS ====================
				
				$SetDownloadPaths
				
				switch ($Make) {
					"Dell" {
						global:Write-LogEntry -Value "Info: Setting Dell variables" -Severity 1
						if ($global:DellModelCabFiles -eq $null) {
							[xml]$DellModelXML = Get-Content -Path $(Join-Path -Path $global:TempDirectory -ChildPath $DellXMLFile) -Raw
							
							# Set XML Object
							$DellModelXML.GetType().FullName
							$global:DellModelCabFiles = $DellModelXML.driverpackmanifest.driverpackage
						}
						$global:SkuValue = (($global:DellModelCabFiles.supportedsystems.brand.model | Where-Object {
									$_.Name -eq $Model
								}).systemID) | Select-Object -Unique
						$ModelURL = $DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object {
								((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $global:SkuValue)
							}).delta
						if ($global:SkuValue.Count -gt 1) {
							$DellSingleSKU = $global:SkuValue | Select-Object -First 1
							$global:SkuValue = [string]($global:SkuValue -join ";")
							global:Write-LogEntry -Value "Info: Using SKU : $DellSingleSKU" -Severity 1
							$ModelURL = $DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object {
									((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $DellSingleSKU)
								}).delta
							$DriverDownload = $DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object {
									((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $DellSingleSKU)
								}).path
							$DriverCab = (($global:DellModelCabFiles | Where-Object {
										((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $DellSingleSKU)
									}).path).Split("/") | Select-Object -Last 1
							
						} else {
							$ModelURL = $DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object {
									((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $global:SkuValue)
								}).delta
							$DriverDownload = $DellDownloadBase + "/" + ($global:DellModelCabFiles | Where-Object {
									((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $global:SkuValue)
								}).path
							$DriverCab = (($global:DellModelCabFiles | Where-Object {
										((($_.SupportedOperatingSystems).OperatingSystem).osCode -match $WindowsVersion) -and ($_.SupportedSystems.Brand.Model.SystemID -match $global:SkuValue)
									}).path).Split("/") | Select-Object -Last 1
						}
						
						$ModelURL = $ModelURL.Replace("\", "/")
						$DriverRevision = $Drivercab.Split("-") | Select-Object -Last 2 | Select-Object -First 1
						
						global:Write-LogEntry -Value "Info: Dell System Model ID is : $global:SkuValue" -Severity 1
						
					}
					"Hewlett-Packard" {
						global:Write-LogEntry -Value "Info: Setting Hewlett-Packard variables" -Severity 1
						if ($global:HPModelSoftPaqs -eq $null) {
							[xml]$global:HPModelXML = Get-Content -Path $(Join-Path -Path $global:TempDirectory -ChildPath $HPXMLFile) -Raw
							# Set XML Object
							$global:HPModelXML.GetType().FullName
							$global:HPModelSoftPaqs = $global:HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
						}
						if ($OSComboBox.Text -like "Windows 10 *") {
							$HPSoftPaqSummary = $global:HPModelSoftPaqs | Where-Object {
								($_.SystemName -like "*$Model*") -and ($_.OSName -like "Windows*$(($OSComboBox.Text).Split(' ')[1])*$(($ArchitectureComboxBox.Text).Trim(' bit'))*$((($OSComboBox.Text).Split(' ')[2]).Trim())*")
							} | Sort-Object -Descending | Select-Object -First 1
						} else {
							$HPSoftPaqSummary = $global:HPModelSoftPaqs | Where-Object {
								($_.SystemName -like "*$Model*") -and ($_.OSName -like "Windows*$(($OSComboBox.Text).Split(' ')[1])*$(($ArchitectureComboxBox.Text).Trim(' bit'))*")
							} | Sort-Object -Descending | Select-Object -First 1
						}
						$HPSoftPaq = $HPSoftPaqSummary.SoftPaqID
						$HPSoftPaqDetails = $global:HPModelXML.newdataset.hpclientdriverpackcatalog.softpaqlist.softpaq | Where-Object {
							$_.ID -eq "$HPSoftPaq"
						}
						$ModelURL = $HPSoftPaqDetails.URL
						
						# Replace FTP for HTTP for Bits Transfer Job
						$DriverDownload = ($HPSoftPaqDetails.URL).TrimStart("ftp:")
						$DriverCab = $ModelURL | Split-Path -Leaf
						$DriverRevision = "$($HPSoftPaqDetails.Version)"
						$global:SkuValue = ($global:HPModelSoftPaqs | Where-Object {
								$_.SystemName -eq "HP $Model"
							}).SystemID | Select-Object -Unique
						$global:SkuValue = $global:SkuValue.ToLower()
					}
					"Lenovo" {
						global:Write-LogEntry -Value "Info: Setting Lenovo variables" -Severity 1
						Find-LenovoModelType -Model $Model -OS $OS
						$global:SkuValue = ($global:LenovoModelDrivers | Where-Object{$_.name -eq "$Model"}).Types | Select-Object -ExpandProperty Type | Sort-Object | Get-Unique
						global:Write-LogEntry -Value "Info: $Make $Model matching model type: $global:LenovoModelType" -Severity 1 -SkipGuiLog $false
						
						try {
							global:Write-LogEntry -Value "Info: Looking Up Lenovo $Model URL For Windows version win$(($WindowsVersion).Trim('.'))" -Severity 1
							$DriverDownload = ($global:LenovoModelDrivers | Where-Object {
									$_.Name -like "$Model*"
								}).SCCM | Where-Object {
								$_.Version -eq $OSVersion
							} | Select-Object -ExpandProperty "#text" -First 1
							If (-not ([string]::IsNullOrEmpty($DriverDownload))) {
								# Fix URL malformation
								global:Write-LogEntry -Value "Info: Driver package URL - $DriverDownload" -Severity 1
								$DriverCab = $DriverDownload | Split-Path -Leaf
								$DriverRevision = ($DriverCab.Split("_") | Select-Object -Last 1).Trim(".exe")
							} else {
								global:Write-ErrorOutput -Message "Error: Unable to find driver for $Make $Model" -Severity 3
							}
						} catch [System.Exception] {
							global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
							global:Write-ErrorOutput -Message "Error: Unable to find driver for $Make $Model" -Severity 3
						}
						
					}
					"Microsoft" {
						global:Write-LogEntry -Value "Info: Setting Microsoft variables" -Severity 1
						[xml]$MicrosoftModelXML = (New-Object System.Net.WebClient).DownloadString("$MicrosoftXMLSource")
						# Set XML Object
						$MicrosoftModelXML.GetType().FullName
						$MicrosoftModelDrivers = $MicrosoftModelXML.Drivers
						global:Write-LogEntry -Value "Info: Atteming match for $(($MicrosoftModelDrivers.Model | Where-Object {
									$_.DisplayName -eq $Model
								}).ProductName)" -Severity 1 -SkipGuiLog $false
						[string]$DriverDownload = Find-MicrosoftDriver -MSProductName $(($MicrosoftModelDrivers.Model | Where-Object {
									$_.DisplayName -eq $Model
								}).ProductName) -OSBuild $OSBuild
						$DriverDownload = "https:" + ($DriverDownload.Split(":") | Select-Object -Last 1)
						$ModelURL = $DriverDownload
						$DriverCab = $DriverDownload | Split-Path -Leaf
						$DriverRevision = ($DriverCab.Split("_") | Select-Object -Last 1).Trim(".msi")
						$global:SkuValue = $(($MicrosoftModelDrivers.Model | Where-Object {
									$_.DisplayName -eq $Model
								}).SystemSKU)
					}
				}
				
				# =================== INITIATE DOWNLOADS ===================
				
				if ($ImportInto -ne "MDT") {
					# Product Type Display
					switch -wildcard ($ImportInto) {
						"Download*" {
							$Product = "Download"
						}
						default {
							$Product = "ConfigMgr"
							Set-Location -Path ($SiteCode + ":")
							Set-ConfigMgrFolder
							Set-Location -Path $Global:TempDirectory
						}
					}
					
					if ($DownloadType -ne "Drivers") {
						global:Write-LogEntry -Value "======== $Make $MODEL BIOS PROCESSING STARTED ========" -Severity 1
						$BIOSUpdatePackage = ("BIOS Update - " + "$Make" + " " + $Model)
						# Allow for test/pilot BIOS packages
						if ($ImportInto -match "Pilot") {
							$BIOSUpdatePackage = $BIOSUpdatePackage.Replace("BIOS Update", "BIOS Update Pilot")
						}
						if ($Make -eq "Dell") {
							# ================= Dell BIOS Upgrade Download ==================
							$DellBIOSDownload = Find-DellBios -SKU $global:SkuValue
							if ($DellBIOSDownload -notcontains "BadLink") {
								$BIOSDownload = $DellDownloadBase + "/" + $($DellBIOSDownload.Path)
								$BIOSVer = $DellBIOSDownload.DellVersion
								global:Write-LogEntry -Value "Info: Latest available BIOS version is $BIOSVer" -Severity 1
								$BIOSFile = $DellBIOSDownload.Path | Split-Path -Leaf
								$BIOSVerDir = $BIOSVer -replace '\.', '-'
								if ($ImportInto -match "Download|Intune") {
									$BIOSUpdateRoot = ($DownloadRoot + $Model + "\BIOS\" + $BIOSVerDir + "\")
								} else {
									$BIOSUpdateRoot = ($PackageRoot + $Model + "\BIOS\" + $BIOSVerDir + "\")
								}
								if ($Product -match "Download") {
									global:Write-LogEntry -Value "Info: Checking for existing BIOS release - $BIOSVer" -Severity 1
									if ((Test-Path -Path $BIOSUpdateRoot) -eq $true) {
										if ((Get-ChildItem -Path $BIOSUpdateRoot -File) -contains $BIOSFile) {
											$NewBIOSAvailable = $false
										} else {
											$NewBIOSAvailable = $true
										}
									}
									$NewBIOSAvailable = $true
								} elseif ($Product -eq "ConfigMgr") {
									Set-Location -Path ($SiteCode + ":")
									global:Write-LogEntry -Value "Info: Checking ConfigMgr for existing BIOS release - $BIOSVer" -Severity 1
									$CurrentBIOSPackage = Get-CMPackage -Name $BIOSUpdatePackage -Fast | Select-Object Name, PackageID, SourceDate, Version | Sort-Object SourceDate -Descending | Select-Object -First 1
									if (![string]::IsNullOrEmpty($CurrentBIOSPackage.Version)) {
										global:Write-LogEntry -Value "Info: Comparing BIOS versions" -Severity 1
										if ($BIOSVer -ne $CurrentBIOSPackage.Version) {
											$NewBIOSAvailable = $true
											global:Write-LogEntry -Value "Info: New BIOS download available" -Severity 1
										} else {
											$NewBIOSAvailable = $false
											global:Write-LogEntry -Value "Info: BIOS package already exists for $Make $Model (Version $BIOSVer)." -Severity 2
										}
									} else {
										$NewBIOSAvailable = $true
										global:Write-LogEntry -Value "Info: New BIOS download available" -Severity 1
									}
								}
								Set-Location -Path $global:TempDirectory
								If ($NewBIOSAvailable -eq $true) {
									if (($BIOSDownload -like "*.exe") -and ($Make -eq "Dell")) {
										global:Write-LogEntry -Value "Info: BIOS Download URL Found: $BIOSDownload" -Severity 1
										# Check for destination directory, create if required and download the BIOS upgrade file
										if ((Test-Path -Path "$($DownloadRoot + $Model + '\BIOS\' + $BIOSVerDir + '\' + $BIOSFile)") -eq $false) {
											If ((Test-Path -Path $BIOSUpdateRoot) -eq $false) {
												global:Write-LogEntry -Value "Info: Creating $BIOSUpdateRoot folder" -Severity 1
												New-Item -Path $BIOSUpdateRoot -ItemType Directory
											}
											global:Write-LogEntry -Value "Info: Downloading $($BIOSFile) BIOS update file" -Severity 1
											try {
												if ($global:ProxySettingsSet -eq $true) {
													Start-BitsTransfer $BIOSDownload -Destination "$($BIOSUpdateRoot + $BIOSFile)" @global:BitsProxyOptions -DisplayName "$Make $Model BIOS download"
												} else {
													Start-BitsTransfer $BIOSDownload -Destination "$($BIOSUpdateRoot + $BIOSFile)" @global:BitsOptions -DisplayName "$Make $Model BIOS download"
												}
												Invoke-BitsJobMonitor -BitsJobName "$Make $Model BIOS download" -DownloadSource $BIOSDownload
												if ($global:BitsJobByteSize -eq $((Get-Item -Path ($BIOSUpdateRoot + $BIOSFile))).Length) {
													$DownloadSuccess = $true
												} elseif ((Test-Path -Path $($BIOSUpdateRoot + $BIOSFile)) -eq $true) {
													$DownloadSuccess = $true
												} else {
													$DownloadSuccess = $false
												}
											} catch {
												global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
												$DownloadSuccess = $false
											}
										} else {
											global:Write-LogEntry -Value "Info: Skipping $BIOSFile... File already downloaded." -Severity 2
											$DownloadSuccess = $true
										}
										if ($DownloadSuccess -eq $true) {
											# ================= Dell Flash 64 Upgrade Download ==================
											$FlashUtilDir = Join-Path -Path $PackageRoot -ChildPath "Flash64Utility\"
											$Flash64BitZip = Join-Path -Path $FlashUtilDir -ChildPath ($Dell64BIOSUtil | Split-Path -Leaf)
											$Flash64BitTemp = Join-Path -Path $Global:TempDirectory -ChildPath ($Dell64BIOSUtil | Split-Path -Leaf)
											$Flash64BitExe = "Flash64W.exe"
											
											if ((Test-Path -Path $FlashUtilDir) -eq $false) {
												global:Write-LogEntry -Value "Info: Creating Directory - $FlashUtilDir" -Severity 1
												New-Item -ItemType Directory -Path $FlashUtilDir | Out-Null
											}
											global:Write-LogEntry -Value "Info: Downloading $Make flash update utility" -Severity 1
											try {
												if ($global:ProxySettingsSet -eq $true) {
													Start-BitsTransfer $Dell64BIOSUtil -Destination "$($Flash64BitTemp)" @global:BitsProxyOptions -DisplayName "$Make $Model BIOS download"
												} else {
													Start-BitsTransfer $Dell64BIOSUtil -Destination "$($Flash64BitTemp)" @global:BitsOptions -DisplayName "$Make $Model BIOS download"
												}
												Invoke-BitsJobMonitor -BitsJobName "$Make Flash64w download" -DownloadSource $Dell64BIOSUtil
											} catch {
												global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
												global:Write-ErrorOutput -Message "Error: BIOS flash utility failed to download. Check log for more details" -Severity 3
											}
											
											if ((Test-Path -Path $Flash64BitZip) -eq $true) {
												
												if (Test-Path -Path $Flash64BitExe) {
													global:Write-LogEntry -Value "Info: Existing Dell Flash 64 EXE found" -Severity 1
													$DellFlashExists = $true
													$DellFlashVersion = (Get-Item -Path $Flash64BitExe | Select-Object -ExpandProperty VersionInfo).ProductVersion
													if ([string]::IsNullOrEmpty($DellFlashVersion)) {
														global:Write-LogEntry -Value "Info: Unable to obtain version info from legacy Dell Flash 64 EXE" -Severity 1
														global:Write-LogEntry -Value "Info: Setting version info to version 1.0 for archiving purposes" -Severity 1
														$DellFlashVersion = "1.0"
													} else {
														global:Write-LogEntry -Value "Info: Current production version of Dell Flash 64 EXE is $DellFlashVersion" -Severity 1
													}
													
												}
												global:Write-LogEntry -Value "Info: Unzipping latest Dell Flash64 EXE in $($Flash64BitTemp)" -Severity 1
												if (Test-Path -Path $(Join-Path -Path $Global:TempDirectory -ChildPath $Flash64BitExe)) {
													Remove-Item -Path $(Join-Path -Path $Global:TempDirectory -ChildPath $Flash64BitExe) -Force
												}
												Add-Type -AssemblyName "system.io.compression.filesystem"
												[io.compression.zipfile]::ExtractToDirectory("$($Flash64BitTemp)", "$($global:TempDirectory)")
												Start-Sleep -Milliseconds 100
												$DellTempFlashVersion = (Get-Item -Path $(Join-Path -Path $Global:TempDirectory -ChildPath $Flash64BitExe) | Select-Object -ExpandProperty VersionInfo).ProductVersion
												global:Write-LogEntry -Value "Info: New Dell Flash 64 EXE version is $DellFlashVersion" -Severity 1
												if (([system.Version]$DellTempFlashVersion -gt [System.Version]$DellFlashVersion) -or ($DellFlashExists -ne $true)) {
													global:Write-LogEntry -Value "Info: Latest Dell Flash 64 EXE is $([System.Version]$DellTempFlashVersion)" -Severity 1
													global:Write-LogEntry -Value "Info: Creating new/updated Dell Flash 64 source" -Severity 1
													if ((Test-Path -Path (Join-Path -Path $FlashUtilDir -ChildPath $DellFlashVersion)) -eq $false) {
														global:Write-LogEntry -Value "Info: Creating legacy folder for version: $DellFlashVersion" -Severity 1
														New-Item -Path (Join-Path -Path $FlashUtilDir -ChildPath $DellFlashVersion) -ItemType Dir | Out-Null
													}
													global:Write-LogEntry -Value "Info: Archiving legacy file" -Severity 1
													Get-ChildItem -Path $FlashUtilDir -Filter *.exe | Move-Item -Destination (Join-Path -Path $FlashUtilDir -ChildPath $DellFlashVersion) -Force
													global:Write-LogEntry -Value "Info: Promoting $([System.Version]$DellFlashVersion) release to production" -Severity 1
													Get-ChildItem -Path $global:TempDirectory -Filter ($Flash64BitExe | Split-Path -Leaf) | Move-Item -Destination $FlashUtilDir -Force -Verbose
												} else {
													global:Write-LogEntry -Value "Info: Flash 64 utility is up to date" -Severity 1
												}
												global:Write-LogEntry -Value "Info: Copying Dell Flash64Bit EXE To $BIOSUpdateRoot" -Severity 1
												Get-Item -Path $Flash64BitExe | Copy-Item -Destination "$($BIOSUpdateRoot)" -Force
												if ($Product -match "ConfigMgr") {
													if (($Product -ne "Download Only") -and ((Test-Path -Path "$($BIOSUpdateRoot + $BIOSFile)")) -eq $true) {
														# ================= Create BIOS Update Package ==================			
														Set-Location -Path ($SiteCode + ":")
														$BIOSModelPackage = Get-CMPackage -Name $BIOSUpdatePackage -Fast | Select-Object SourceDate, Version | Sort-Object SourceDate -Descending | Select-Object -First 1
														if (($BIOSModelPackage.Version -ne $BIOSVer) -or ($BIOSModelPackage -eq $null)) {
															global:Write-LogEntry -Value "$($Product): Creating BIOS Package" -Severity 1
															New-CMPackage -Name "$BIOSUpdatePackage" -Path "$BIOSUpdateRoot" -Description "(Models included:$global:SkuValue)" -Manufacturer "$Make" -Language English -version $BIOSVer
															if ($EnableBinaryDifCheckBox.Checked -eq $true) {
																global:Write-LogEntry -Value "$($Product): Enabling Binary Delta Replication" -Severity 1
																Set-CMPackage -Name "$BIOSUpdatePackage" -EnableBinaryDeltaReplication $true -Priority "$($DistributionPriorityCombo.Text)"
															}
															$ConfiMgrPackage = Get-CMPackage -Name $BIOSUpdatePackage -Fast | Select-Object PackageID, Version, Name | Where-Object {
																$_.Version -eq $BIOSVer
															}
															Move-CMObject -FolderPath $global:VendorBIOSFolder -ObjectID $ConfiMgrPackage.PackageID
															Set-Location -Path $global:TempDirectory
															# =============== Distrubute Content =================
															Set-Location -Path ($SiteCode + ":")
															$ConfiMgrPackage = Get-CMPackage -Name $BIOSUpdatePackage -Fast | Select-Object PackageID, Version | Where-Object {
																$_.Version -eq $BIOSVer
															}
															Move-CMObject -FolderPath $global:VendorBIOSFolder -ObjectID $ConfiMgrPackage.PackageID
															Distribute-Content -Product $Product -PackageID $ConfiMgrPackage.PackageID -ImportInto $ImportInto
															Set-Location -Path $global:TempDirectory
														}
													}
												}
											} else {
												global:Write-ErrorOutput -Message "Error: BIOS flash upgrade utility failed to download. Check log for more details" -Severity 3
											}
										} else {
											global:Write-ErrorOutput -Message "Error: BIOS failed to download. Check log for more details" -Severity 3
										}
									} else {
										global:Write-LogEntry -Value "Info: Unable to retrieve BIOS download URL For $Make Client Model: $($Model)" -Severity 2
									}
								} else {
									global:Write-LogEntry -Value "Info: Current BIOS package already exists - $($CurrentBIOSPackage.Name) - $($CurrentBIOSPackage.Version) ($($CurrentBIOSPackage.PackageID))" -Severity 1
								}
							}
						}
						if ($Make -eq "Lenovo") {
							# ================= Lenovo BIOS Upgrade Download ==================
							global:Write-LogEntry -Value "Info: Retrieving BIOS download URL for $Make Client Model: $($Model)" -Severity 1
							Set-Location -Path $global:TempDirectory
							global:Write-LogEntry -Value "Info: Attempting to find download URL using Find-LenovoBios function" -Severity 1
							$BIOSDownload = Find-LenovoBios -ModelType $($global:LenovoModeltype | Select-Object -First 1)
							if (-not ([string]::IsNullOrEmpty($BIOSDownload.Location))) {
								global:Write-LogEntry -Value "Info: Downloading BIOS update from $($BIOSDownload.Location) " -Severity 1
								# Download Lenovo BIOS Details XML
								try {
									if ($global:ProxySettingsSet -eq "OK") {
										Start-BitsTransfer -Source $($BIOSDownload.Location) -Destination $global:TempDirectory @global:BitsProxyOptions
									} else {
										Start-BitsTransfer -Source $($BIOSDownload.Location) -Destination $global:TempDirectory @global:BitsOptions
									}
								} catch {
									global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
								}
								$LenovoBIOSDetails = (Select-Xml -Path ($global:TempDirectory + "\" + ($BIOSDownload.Location | Split-Path -leaf)) -XPath "/").Node.Package
								if ($LenovoBIOSDetails.Name -ne $null) {
									$BIOSFile = ($LenovoBIOSDetails.ExtractCommand).Split(" ")[0]
									global:Write-LogEntry -Value "Info: Found exe file link: $BIOSFile" -Severity 1
									$BIOSVer = $LenovoBIOSDetails.version
									$BIOSReleaseDate = ($LenovoBIOSDetails.ReleaseDate).Replace("-", "")
									if ($ImportInto -match "Download|Intune") {
										$BIOSUpdateRoot = ($DownloadRoot + $Model + "\BIOS\" + $BIOSVer + "\")
									} else {
										$BIOSUpdateRoot = ($PackageRoot + $Model + "\BIOS\" + $BIOSVer + "\")
									}
									global:Write-LogEntry -Value "Info: BIOS version is $BIOSVer" -Severity 1
									if ($Product -match "Download|Intune") {
										if ((Test-Path -Path $BIOSUpdateRoot) -eq $true) {
											if ((Get-ChildItem -Path $BIOSUpdateRoot -File) -contains $BIOSFile) {
												$NewBIOSAvailable = $false
											} else {
												$NewBIOSAvailable = $true
											}
										}
										$NewBIOSAvailable = $true
									} elseif ($Product -eq "ConfigMgr") {
										Set-Location -Path ($SiteCode + ":")
										global:Write-LogEntry -Value "Info: Checking ConfigMgr for existing BIOS release - $BIOSVer" -Severity 1
										$CurrentBIOSPackage = Get-CMPackage -Name $BIOSUpdatePackage -Fast | Select-Object PackageID, SourceDate, Version | Sort-Object SourceDate -Descending | Select-Object -First 1
										if (![string]::IsNullOrEmpty($CurrentBIOSPackage.Version)) {
											global:Write-LogEntry -Value "Info: Comparing BIOS versions" -Severity 1
											if ($BIOSVer -ne $CurrentBIOSPackage.Version) {
												$NewBIOSAvailable = $true
												global:Write-LogEntry -Value "Info: New BIOS download available" -Severity 1
											} else {
												$NewBIOSAvailable = $false
												global:Write-LogEntry -Value "Info: BIOS package already exists for $Make $Model (Version $BIOSVer)." -Severity 2
											}
										} else {
											$NewBIOSAvailable = $true
											global:Write-LogEntry -Value "Info: New BIOS download available" -Severity 1
										}
										Set-Location -Path $global:TempDirectory
									}
									if ($NewBIOSAvailable -eq $true) {
										global:Write-LogEntry -Value "Info: BIOS update directory set to $BIOSUpdateRoot" -Severity 1
										# Check for destination directory, create if required and download the BIOS upgrade file
										if ((Test-Path -Path "$($BIOSUpdateRoot)") -eq $false) {
											New-Item -Path "$BIOSUpdateRoot" -ItemType Directory
										}
										$BIOSFileDownload = ($BIOSDownload.Location | Split-Path -Parent) + "/$BIOSFile"
										# Correct slash direction issues
										$BIOSFileDownload = $BIOSFileDownload.Replace("\", "/")
										global:Write-LogEntry -Value "Info: Downloading BIOS update file from $BIOSFileDownload" -Severity 1
										try {
											if ($global:ProxySettingsSet -eq $true) {
												Start-BitsTransfer $BIOSFileDownload -Destination "$($BIOSUpdateRoot + $BIOSFile)" @global:BitsProxyOptions -DisplayName "$Make $Model BIOS download"
											} else {
												Start-BitsTransfer $BIOSFileDownload -Destination "$($BIOSUpdateRoot + $BIOSFile)" @global:BitsOptions -DisplayName "$Make $Model BIOS download"
											}
											Invoke-BitsJobMonitor -BitsJobName "$Make $Model BIOS download" -DownloadSource $BIOSFileDownload
											if (Test-Path ($BIOSUpdateRoot + $BIOSFile)) {
												$DownloadSuccess = $true
											} else {
												$DownloadSuccess = $false
											}
										} catch {
											global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
											$DownloadSuccess = $false
										}
										if ($DownloadSuccess -eq $true) {
											# =============== Extract BIOS Files =================
											$BIOSExtractSwitches = ((($LenovoBIOSDetails.ExtractCommand).TrimStart("$BIOSFile")).Trim()).Replace("%PACKAGEPATH%", ('"' + $global:TempDirectory + "\$($Model.Replace(' ', ''))" + "\BIOS\$BIOSVer" + '"'))
											Unblock-File -Path ($BIOSUpdateRoot + $BIOSFile)
											global:Write-LogEntry -Value "Info: Unlocking BIOS file located at $($BIOSUpdateRoot + $BIOSFile)" -Severity 1
											global:Write-LogEntry -Value "Info: Starting BIOS file extract process" -Severity 1
											global:Write-LogEntry -Value "Info: BIOS extract switches used = $BIOSExtractSwitches" -Severity 1
											Start-Process -FilePath $($BIOSUpdateRoot + $BIOSFile) -ArgumentList $BIOSExtractSwitches -Wait -NoNewWindow
											$BIOSProcess = ($BIOSFile).Substring(0, $BIOSFile.length - 4)
											# Wait for Lenovo BIOS Extract Process To Finish
											While ((Get-Process).name -contains $BIOSProcess) {
												global:Write-LogEntry -Value "Info: Waiting for extract process (Process: $BIOSProcess) to complete..  Next check in 10 seconds" -Severity 1
												Start-Sleep -Seconds 10
											}
											global:Write-LogEntry -Value "Info: Extract process complete" -Severity 1
											global:Write-LogEntry -Value "Info: Copying extracted files to $BIOSUpdateRoot" -Severity 1
											Get-ChildItem -Path ($global:TempDirectory + "\$($Model.Replace(' ', ''))\BIOS\$BIOSVer") -Recurse | Move-Item -Destination "$BIOSUpdateRoot" -Force
											global:Write-LogEntry -Value "Info: Removing source BIOS exe file" -Severity 1
											Get-ChildItem -Path "$BIOSUpdateRoot" -Filter "*.exe" | Where-Object {
												$_.Name -eq $BIOSFile
											} | Remove-Item
											If ((Get-ChildItem -Path $BIOSUpdateRoot -File).Count -gt 0) {
												If ($ImportInto -notmatch "Download") {
													# =============== Create Package =================
													Set-Location -Path ($SiteCode + ":")
													global:Write-LogEntry -Value "$($Product): Creating BIOS package" -Severity 1
													New-CMPackage -Name "$BIOSUpdatePackage" -Path "$BIOSUpdateRoot" -Description "(Models included:$global:SkuValue) (Release Date:$BIOSReleaseDate)" -Manufacturer "$Make" -Language English -version $LenovoBIOSDetails.Version
													if ($EnableBinaryDifCheckBox.Checked -eq $true) {
														global:Write-LogEntry -Value "$($Product): Enabling Binary Delta Replication" -Severity 1
														Set-CMPackage -Name "$BIOSUpdatePackage" -EnableBinaryDeltaReplication $true -Priority "$($DistributionPriorityCombo.Text)"
													}
													# =============== Distrubute Content =================
													Set-Location -Path ($SiteCode + ":")
													$ConfiMgrPackage = Get-CMPackage -Name $BIOSUpdatePackage -Fast | Select-Object PackageID, Version | Where-Object {
														$_.Version -eq $BIOSVer
													}
													Move-CMObject -FolderPath $global:VendorBIOSFolder -ObjectID $ConfiMgrPackage.PackageID
													Distribute-Content -Product $Product -PackageID $ConfiMgrPackage.PackageID -ImportInto "Standard"
													global:Write-LogEntry -Value "$($Product): BIOS update package $($ConfiMgrPackage.PackageID) created & distributing" -Severity 1
												}
											} else {
												global:Write-ErrorOutput -Message "Error: Extract BIOS folder is empty. Issues occured during extraction." -Severity 3
											}
											Set-Location -Path $global:TempDirectory
										} else {
											global:Write-ErrorOutput -Message "Error: BIOS failed to download. Check log for more details" -Severity 3
										}
									} else {
										global:Write-LogEntry -Value "Info: Current BIOS package already exists - $($CurrentBIOSPackage.PackageID)" -Severity 1
									}
								} else {
									global:Write-ErrorOutput -Message "Error: Unable to find BIOS download for $Make $Model" -Severity 2
								}
							} else {
								global:Write-ErrorOutput -Message "Error: Unable to find BIOS XML link" -Severity 2
							}
							Set-Location -Path $global:TempDirectory
						}
						if ($Make -eq "Hewlett-Packard") {
							# ================= HP BIOS Upgrade Download ==================
							global:Write-LogEntry -Value "Info: Attempting to find HP BIOS download" -Severity 1
							$HPBIOSDownload = Find-HPBios -Model $Model -OS $OSVersion -Architecture $Architecture -SKUValue $(($global:SkuValue).Split(",") | Select-Object -First 1)
							if ($HPBIOSDownload.URL -ne $null) {
								$BIOSDownload = "http://" + $($HPBIOSDownload.URL)
								$BIOSVer = $HPBIOSDownload.Version.Trim()
								$BIOSVerDir = $BIOSVer -replace '\.', '-'
								global:Write-LogEntry -Value "Info: Latest available BIOS version is $BIOSVer" -Severity 1
								if ($ImportInto -match "Download|Intune") {
									$BIOSUpdateRoot = ($DownloadRoot + $Model + "\BIOS\" + $BIOSVerDir + "\")
								} else {
									$BIOSUpdateRoot = ($PackageRoot + $Model + "\BIOS\" + $BIOSVerDir + "\")
								}
								if ($Product -match "Download|Intune") {
									if ((Test-Path -Path $BIOSUpdateRoot) -eq $true) {
										if ((Get-ChildItem -Path $BIOSUpdateRoot -File) -contains $BIOSFile) {
											$NewBIOSAvailable = $false
										} else {
											$NewBIOSAvailable = $true
										}
									}
									$NewBIOSAvailable = $true
								} elseif ($Product -eq "ConfigMgr") {
									Set-Location -Path ($SiteCode + ":")
									global:Write-LogEntry -Value "Info: Checking ConfigMgr for existing BIOS release - $BIOSVer" -Severity 1
									$CurrentBIOSPackage = Get-CMPackage -Name "$BIOSUpdatePackage" -Fast | Select-Object SourceDate, Version, PackageID | Sort-Object SourceDate -Descending | Select-Object -First 1
									if (![string]::IsNullOrEmpty($CurrentBIOSPackage.Version)) {
										global:Write-LogEntry -Value "Info: Comparing BIOS versions" -Severity 1
										if ($BIOSVer -notmatch $CurrentBIOSPackage.Version) {
											$NewBIOSAvailable = $true
											global:Write-LogEntry -Value "Info: New BIOS download available" -Severity 1
										} else {
											$NewBIOSAvailable = $false
											global:Write-LogEntry -Value "Info: BIOS package already exists for $Make $Model (Version $BIOSVer)." -Severity 2
										}
									} else {
										$NewBIOSAvailable = $true
										global:Write-LogEntry -Value "Info: New BIOS download available" -Severity 1
									}
									Set-Location -Path $global:TempDirectory
								}
								if ($NewBIOSAvailable -eq $true) {
									$BIOSFile = $BIOSDownload | Split-Path -Leaf
									$BIOSCVADownload = $BIOSDownload.Replace(".exe", ".cva")
									$BIOSCVAFile = $BIOSCVADownload | Split-Path -Leaf
									$HPBIOSTemp = Join-Path $TempDirectory "HPBIOSTemp\$Model"
									
									if (($BIOSDownload -like "*.exe") -and ($Make -eq "Hewlett-Packard")) {
										global:Write-LogEntry -Value "Info: BIOS Download URL Found: $BIOSDownload" -Severity 1
										# Check for destination directory, create if required and download the BIOS upgrade file
										if ((Test-Path -Path "$($BIOSUpdateRoot + $BIOSFile)") -eq $false) {
											If ((Test-Path -Path $HPBIOSTemp) -eq $false) {
												global:Write-LogEntry -Value "Info: Creating $HPBIOSTemp folder" -Severity 1
												New-Item -Path $HPBIOSTemp -ItemType Directory
											}
											If ((Test-Path -Path "$BIOSUpdateRoot") -eq $false) {
												global:Write-LogEntry -Value "Info: Creating $BIOSUpdateRoot folder" -Severity 1
												New-Item -Path "$BIOSUpdateRoot" -ItemType Directory
											}
											global:Write-LogEntry -Value "Info: Downloading $($BIOSFile) BIOS update file" -Severity 1
											try {
												if ($global:ProxySettingsSet -eq $true) {
													Start-BitsTransfer $BIOSDownload -Destination $HPBIOSTemp @global:BitsProxyOptions
													Start-BitsTransfer $BIOSCVADownload -Destination $HPBIOSTemp @global:BitsProxyOptions
												} else {
													Start-BitsTransfer $BIOSDownload -Destination $HPBIOSTemp @global:BitsOptions
													Start-BitsTransfer $BIOSCVADownload -Destination $HPBIOSTemp @global:BitsOptions
												}
												if ((Test-Path -Path (Join-Path $HPBIOSTemp $BIOSFile)) -and (Test-Path -Path (Join-Path $HPBIOSTemp $BIOSCVA))) {
													global:Write-LogEntry -Value "Info: BIOS file(s) downloaded" -Severity 1
													$HPBIOSSource = (Join-Path $HPBIOSTemp $BIOSFile)
													$DownloadSuccess = $true
												} else {
													$DownloadSuccess = $false
												}
											} catch {
												global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
												$DownloadSuccess = $false
											}
										}
									}
									if ($DownloadSuccess -eq $true) {
										Invoke-HPSoftPaqExpand -SoftPaqType BIOS
										[int]$HPPkgFileCount = (Get-ChildItem -Path $BIOSUpdateRoot -Recurse).Count
										global:Write-LogEntry -Value "Info: Files in HP BIOS folder: $HPPkgFileCount" -Severity 1
										if ($Product -match "ConfigMgr") {
											if ($HPPkgFileCount.Count -gt 0) {
												# ================= Create BIOS Update Package ==================
												Set-Location -Path ($SiteCode + ":")
												$BIOSModelPackage = Get-CMPackage -Name "$BIOSUpdatePackage" -Fast | Select-Object SourceDate, Version | Sort-Object SourceDate -Descending | Select-Object -First 1
												if (($BIOSModelPackage.Version -ne $BIOSVer) -or ($BIOSModelPackage -eq $null)) {
													global:Write-LogEntry -Value "$($Product): Creating BIOS package" -Severity 1
													New-CMPackage -Name "$BIOSUpdatePackage" -Path "$BIOSUpdateRoot" -Description "(Models included:$global:SkuValue)" -Manufacturer "Hewlett-Packard" -Language English -version $BIOSVer
													Start-Sleep -Seconds 5
													if ($EnableBinaryDifCheckBox.Checked -eq $true) {
														global:Write-LogEntry -Value "$($Product): Enabling Binary Delta Replication" -Severity 1
														Set-CMPackage -Name "$BIOSUpdatePackage" -EnableBinaryDeltaReplication $true -Priority "$($DistributionPriorityCombo.Text)"
													}
													Set-Location -Path $global:TempDirectory
													# =============== Distrubute Content =================
													Set-Location -Path ($SiteCode + ":")
													$ConfiMgrPackage = Get-CMPackage -Name $BIOSUpdatePackage -Fast | Select-Object PackageID, Version | Where-Object {
														$_.Version -eq $BIOSVer
													}
													Move-CMObject -FolderPath $global:VendorBIOSFolder -ObjectID $ConfiMgrPackage.PackageID
													Distribute-Content -Product $Product -PackageID $ConfiMgrPackage.PackageID -ImportInto $ImportInto
													global:Write-LogEntry -Value "$($Product): BIOS Update package $($ConfiMgrPackage.PackageID) created & distributing" -Severity 1
													Set-Location -Path $global:TempDirectory
												} else {
													global:Write-LogEntry -Value "$($Product): BIOS package already exists" -Severity 1
												}
											} else {
												global:Write-LogEntry -Value "Warning: BIOS folder does not contain all extracted files. " -Severity 2
											}
										}
									} else {
										global:Write-ErrorOutput -Message "Error: BIOS failed to download. Check log for more details" -Severity 3
									}
								} else {
									global:Write-LogEntry -Value "Info: Current BIOS package already exists - $($CurrentBIOSPackage.PackageID)" -Severity 1
								}
							} else {
								global:Write-LogEntry -Value "Warning: Unable to retrieve BIOS Download URL For $Make Client Model: $($Model)" -Severity 2
							}
						}
						Set-Location -Path $global:TempDirectory
						global:Write-LogEntry -Value "======== $Make $Model BIOS PROCESSING FINISHED ========" -Severity 1
					}
					
					if ((![string]::IsNullOrEmpty($DriverDownload)) -and ($DriverDownload -notmatch "badlink")) {
						if ($DownloadType -ne "BIOS") {
							# Driver variables & switches
							$DriverSourceCab = ($DownloadRoot + $Model + "\Driver Cab\" + $DriverCab)
							$DriverPackageDir = ($DriverCab).Substring(0, $DriverCab.length - 4)
							$DriverCabDest = $PackageRoot + $DriverPackageDir
							
							# Cater for Dell driver packages (both x86 and x64 drivers contained within a single package)
							if ($Make -eq "Dell") {
								$DriverExtractDest = ("$DownloadRoot" + $Model + "\" + "Windows$WindowsVersion-$DriverRevision")
								global:Write-LogEntry -Value "Info: Driver extract location set - $DriverExtractDest" -Severity 1
								$DriverPackageDest = ("$PackageRoot" + "$Model" + "-" + "Windows$WindowsVersion-$Architecture-$DriverRevision")
								global:Write-LogEntry -Value "Info: Driver package location set - $DriverPackageDest" -Severity 1
							} else {
								If ($OSBuild -eq $null) {
									$DriverExtractDest = ("$DownloadRoot" + $Model + "\" + "Windows$WindowsVersion-$Architecture-$DriverRevision")
									global:Write-LogEntry -Value "Info: Driver extract location set - $DriverExtractDest" -Severity 1
									$DriverPackageDest = ("$PackageRoot" + "$Model" + "\" + "Windows$WindowsVersion-$Architecture-$DriverRevision")
									global:Write-LogEntry -Value "Info: Driver package location set - $DriverPackageDest" -Severity 1
								} else {
									$DriverExtractDest = ("$DownloadRoot" + $Model + "\" + "Windows$WindowsVersion-$OSVersion-$Architecture-$DriverRevision")
									global:Write-LogEntry -Value "Info: Driver extract location set - $DriverExtractDest" -Severity 1
									$DriverPackageDest = ("$PackageRoot" + "$Model" + "\" + "Windows$WindowsVersion-$OSVersion-$Architecture-$DriverRevision")
									global:Write-LogEntry -Value "Info: Driver package location set - $DriverPackageDest" -Severity 1
								}
								# Replace HP Model Slash
								$DriverExtractDest = $DriverExtractDest -replace '/', '-'
								$DriverPackageDest = $DriverPackageDest -replace '/', '-'
							}
						}
						
						# Allow for both Driver & Standard Program Packages destinations
						if ($ImportInto -like "*Driver*") {
							$DriverPackageDest = $DriverPackageDest + "\DriverPkg\"
						}
						if ($ImportInto -like "*Standard*") {
							$DriverPackageDest = $DriverPackageDest + "\StandardPkg\"
						}
						# Driver variables & switches
						$DriverCategoryName = $Make + "-" + $Model + "-" + $OperatingSystem + "-" + $DriverRevision
						if (($DownloadType -ne "BIOS") -and ($ImportInto -ne "MDT")) {
							global:Write-LogEntry -Value "======== $Make $PRODUCT $Model DRIVER PROCESSING STARTED ========" -Severity 1
							# =============== Driver Cab Download =================				
							global:Write-LogEntry -Value "$($Product): Latest driver revision found - $DriverRevision" -Severity 1
							if ($ImportInto -match "ConfigMgr") {
								Set-Location -Path ($SiteCode + ":")
								if ($ImportInto -like "*Standard*") {
									if ([string]::IsNullOrEmpty($OSBuild)) {
										$CMPackage = ("Drivers - " + "$Make " + $Model + " - " + $OperatingSystem + " " + $Architecture)
									} else {
										$CMPackage = ("Drivers - " + "$Make " + $Model + " - " + $OperatingSystem + " " + $OSVersion + " " + $Architecture)
									}
									
									global:Write-LogEntry -Value "$($Product): Checking ConfigMgr for driver packages matching - $CMPackage" -Severity 1
									# Allow for test/pilot driver packages
									if ($ImportInto -match "Pilot") {
										$CMPackage = $CMPackage.Replace("Drivers -", "Drivers Pilot -")
									}
									$ExistingPackageID = (Get-CMPackage -Name $CMPackage.Trim() -Fast | Select-Object Name, PackageID, Description, Version, SourceDate | Where-Object {
											$_.Version -eq $DriverRevision
										})
								} elseif ($ImportInto -like "*Driver*") {
									if ([string]::IsNullOrEmpty($OSBuild)) {
										$CMDriverPackage = ("$Make " + $Model + " - " + $OperatingSystem + " " + $Architecture)
									} else {
										$CMDriverPackage = ("$Make " + $Model + " - " + $OperatingSystem + " " + $OSVersion + " " + $Architecture)
									}
									$ExistingPackageID = (Get-CMDriverPackage -Name $CMDriverPackage.Trim() | Select-Object Name, PackageID, Version, SourceDate | Where-Object {
											$_.Version -eq $DriverRevision
										})
								}
								Set-Location -Path $global:TempDirectory
							}
							if ([string]::IsNullOrEmpty($ExistingPackageID)) {
								global:Write-LogEntry -Value "$($Product): New driver package detected - Processing" -Severity 1
								if ((-not ([string]::IsInterned($ModelURL))) -and ($DriverDownload -ne "badLink")) {
									# Cater for HP / Model Issue
									$Model = $Model -replace '/', '-'
									$Model = $Model.Trim()
									Set-Location -Path $global:TempDirectory
									# Check for destination directory, create if required and download the driver cab
									Invoke-ContentDownload -OperationalMode StandardPackages
									
									# Cater for HP / Model Issue
									$Model = $Model -replace '/', '-'
									
									if (((Test-Path -Path "$($DownloadRoot + "$Model" + '\Driver Cab\' + $DriverCab)") -eq $true) -and ($DriverCab -ne $null) -and (($global:BitsJobByteSize -eq $((Get-Item -Path $($DownloadRoot + $Model + '\Driver Cab\' + $DriverCab)).Length)) -or ($PreviousDownload -eq $true))) {
										Invoke-ContentExtract
									} else {
										global:Write-LogEntry -Value "$($Product): $DriverCab file download failed" -Severity 3
									}
								} elseif ($DriverDownload -eq "badLink") {
									global:Write-LogEntry -Value "$($Product): Operating system driver package download path not found.. Skipping $Model" -Severity 3
								} else {
									global:Write-LogEntry -Value "$($Product): Driver package not found for $Model running Windows $WindowsVersion $Architecture. Skipping $Model" -Severity 2
								}
							} else {
								global:Write-LogEntry -Value "$($Product): Driver package ($($ExistingPackageID.Name) - $($ExistingPackageID.Version) ($($ExistingPackageID.PackageID))) already exists." -Severity 1
								
							}
							global:Write-LogEntry -Value "======== $Make $PRODUCT $MODEL DRIVER PROCESSING FINISHED ========" -Severity 1
						}
						Set-Location -Path $global:TempDirectory
					}
				}
				
				if (($ImportInto -like "*Both*") -or ($ImportInto -eq "MDT")) {
					global:Write-LogEntry -Value "======== $Make $PRODUCT $MODEL DRIVER PROCESSING STARTED ========" -Severity 1
					Set-Location -Path $global:TempDirectory
					# Import MDT Module
					$Product = "MDT"
					global:Write-LogEntry -Value "======== $Product Prerequisites ========" -Severity 1
					global:Write-LogEntry -Value "$($Product): Importing MDT PowerShell Module" -Severity 1
					$MDTPSLocation = $MDTScriptTextBox.Text
					Get-MDTDeploymentShares
					If ((Test-Path -Path $MDTPSLocation) -eq $true) {
						Import-Module "$MDTPSLocation"
						# =================== MDT Driver Download =====================
						global:Write-LogEntry -Value "========  $Product Driver Download ========" -Severity 1
						global:Write-LogEntry -Value "$($Product): Starting $Product driver download process" -Severity 1
						# =================== DEFINE VARIABLES =====================					
						global:Write-LogEntry -Value "$($Product): Driver package base location set to $DownloadRoot" -Severity 1
						# Operating System Version
						$OperatingSystem = ("Windows " + $WindowsVersion)
						# =============== MDT Driver Cab Download =================					
						# Cater for HP / Model Issue
						$Model = $Model -replace '/', '-'
						if (($ModelURL -ne $null) -and ($ModelURL -ne "badLink")) {
							Invoke-ContentDownload -OperationalMode StandardPackages
							
							# Check for destination directory, create if required and download the driver cab
							if ((Test-Path -Path "$($DownloadRoot + $Model + '\Driver Cab\' + $DriverCab)") -eq $false) {
								if ((Test-Path -Path "($DownloadRoot + $Model + '\Driver Cab\')") -eq $false) {
									global:Write-LogEntry -Value "$($Product): Creating $Model Download Folder" -Severity 1
									New-Item -ItemType Directory -Path "$($DownloadRoot + $Model + '\Driver Cab')"
								} else {
									# Remove previous driver cab revisions
									Get-ChildItem -Path "$($DownloadRoot + $Model + '\Driver Cab\')" | Remove-Item
								}
								global:Write-LogEntry -Value "$($Product): Downloading $DriverCab Driver Cab File" -Severity 1
								Start-Job -Name "$Model-DriverDownload" -ScriptBlock $ContentDownloadJob -ArgumentList ($DownloadRoot, $Model, $DriverCab, $DriverDownload, $global:BitsProxyOptions, $global:BitsOptions, $global:ProxySettingsSet)
								Start-Sleep -Seconds 5
								Invoke-BitsJobMonitor -BitsJobName "$Model-DriverDownload" -DownloadSource $DriverDownload
								Get-BitsTransfer | Where-Object {
									$_.DisplayName -eq "$Model-DriverDownload"
								} | Complete-BitsTransfer
								global:Write-LogEntry -Value "$($Product): Driver revision: $DriverRevision" -Severity 1
							} else {
								global:Write-LogEntry -Value "$($Product): Skipping $DriverCab.. Driver pack already extracted" -Severity 2
							}
							
							if (((Test-Path -Path "$($DownloadRoot + $Model + '\Driver Cab\' + $DriverCab)") -eq $true) -and ($DriverCab -ne $null)) {
								# =============== MDT Driver EXTRACT ====================							
								if ($DownloadType -ne "BIOS") {
									# Driver variables & switches
									$DriverSourceCab = ($DownloadRoot + $Model + "\Driver Cab\" + $DriverCab)
									$DriverPackageDir = ($DriverCab).Substring(0, $DriverCab.length - 4)
									#$DriverCabDest = $PackageRoot + $DriverPackageDir
								}
								# Cater for Dell driver packages (both x86 and x64 drivers contained within a single package)
								if ($Make -eq "Dell") {
									$DriverExtractDest = ("$DownloadRoot" + $Model + "\" + "Windows$WindowsVersion-$DriverRevision")
									global:Write-LogEntry -Value "Info: Driver extract location set - $DriverExtractDest" -Severity 1
									$DriverPackageDest = ("$PackageRoot" + "$Model" + "-" + "Windows$WindowsVersion-$Architecture-$DriverRevision")
									global:Write-LogEntry -Value "Info: Driver package location set - $DriverPackageDest" -Severity 1
								} else {
									If ($OSBuild -eq $null) {
										$DriverExtractDest = ("$DownloadRoot" + $Model + "\" + "Windows$WindowsVersion-$Architecture-$DriverRevision")
										global:Write-LogEntry -Value "Info: Driver extract location set - $DriverExtractDest" -Severity 1
										$DriverPackageDest = ("$PackageRoot" + "$Model" + "\" + "Windows$WindowsVersion-$Architecture-$DriverRevision")
										global:Write-LogEntry -Value "Info: Driver package location set - $DriverPackageDest" -Severity 1
									} else {
										$DriverExtractDest = ("$DownloadRoot" + $Model + "\" + "Windows$WindowsVersion-$OSVersion-$Architecture-$DriverRevision")
										global:Write-LogEntry -Value "Info: Driver extract location set - $DriverExtractDest" -Severity 1
										$DriverPackageDest = ("$PackageRoot" + "$Model" + "\" + "Windows$WindowsVersion-$OSVersion-$Architecture-$DriverRevision")
										global:Write-LogEntry -Value "Info: Driver package location set - $DriverPackageDest" -Severity 1
									}
									# Replace HP Model Slash
									$DriverExtractDest = $DriverExtractDest -replace '/', '-'
									$DriverPackageDest = $DriverPackageDest -replace '/', '-'
								}
								if ((Test-Path -Path "$DriverExtractDest") -eq $false) {
									# Extract Drivers From Driver							
									New-Item -ItemType Directory -Path "$DriverExtractDest"
								}
								Start-Sleep -Seconds 2
								
								if ((Get-ChildItem -Path "$DriverExtractDest" -Recurse -Filter *.inf -File).Count -eq 0) {
									global:Write-LogEntry -Value "======== $PRODUCT DRIVER EXTRACT ========" -Severity 1
									global:Write-LogEntry -Value "$($Product): Expanding driver CAB source file: $DriverCab" -Severity 1
									global:Write-LogEntry -Value "$($Product): Driver CAB destination directory: $DriverExtractDest" -Severity 1
									if ($Make -eq "Dell") {
										global:Write-LogEntry -Value "$($Product): Extracting $Make Drivers to $DriverExtractDest" -Severity 1
										Expand "$DriverSourceCab" -F:* "$DriverExtractDest" -R | Out-Null
									}
									if ($Make -eq "Hewlett-Packard") {
										Invoke-HPSoftPaqExpand -SoftPaqType Drivers
									}
									if ($Make -eq "Lenovo") {
										# Driver Silent Extract Switches
										$LenovoSilentSwitches = "/VERYSILENT /DIR=" + '"' + $DriverExtractDest + '"'
										global:Write-LogEntry -Value "$($Product): Using $Make silent switches: $LenovoSilentSwitches" -Severity 1
										global:Write-LogEntry -Value "$($Product): Extracting $Make drivers to $DriverExtractDest" -Severity 1
										Start-Process -FilePath $($DownloadRoot + $Model + "\Driver Cab\" + $DriverCab) -ArgumentList $LenovoSilentSwitches -Verb RunAs
										$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
										
										# Wait for Lenovo Driver Process To Finish
										While ((Get-Process).name -contains $DriverProcess) {
											global:Write-LogEntry -Value "$($Product): Waiting for extract process (Process: $DriverProcess) to complete..  Next check in 30 seconds" -Severity 1
											Start-Sleep -seconds 30
										}
									}
									if ($Make -eq "Microsoft") {
										# Driver Silent Extract Switches
										$MicrosoftTemp = $global:TempDirectory + "\" + $Model + "\Win" + $WindowsVersion + $Architecture
										$MicrosoftTemp = $MicrosoftTemp -replace '/', '-'
										# Driver Silent Extract Switches
										$MicrosoftSilentSwitches = "/a" + '"' + $($DownloadRoot + $Model + "\Driver Cab\" + $DriverCab) + '"' + '/QN TARGETDIR="' + $MicrosoftTemp + '"'
										global:Write-LogEntry -Value "$($Product): Extracting $Make drivers to $MicrosoftTemp" -Severity 1
										$DriverProcess = Start-Process msiexec.exe -ArgumentList $MicrosoftSilentSwitches -PassThru
										# Wait for Microsoft Driver Process To Finish
										While ((Get-Process).ID -eq $DriverProcess.ID) {
											global:Write-LogEntry -Value "$($Product): Waiting for extract process (Process ID: $($DriverProcess.ID)) To Complete..  Next check in 30 seconds" -Severity 1
											Start-Sleep -seconds 30
										}
										# Move Microsoft Extracted Drivers To UNC Share 
										$MicrosoftExtractDirs = Get-ChildItem -Path $MicrosoftTemp -Directory -Recurse | Where-Object {
											$_.Name -match "Drivers"
										}
										# Set Microsoft extracted folder
										$MicrosoftExtract = $MicrosoftExtractDirs.FullName | Split-Path -Parent | Select-Object -First 1
										global:Write-LogEntry -Value "$($Product): Microsoft driver source directory set to $MicrosoftExtract" -Severity 1
										if ((Test-Path -Path "$MicrosoftExtract") -eq $true) {
											Start-Job -Name "$Model-Driver-Move" -ScriptBlock $MoveDrivers -ArgumentList ($MicrosoftExtract, $DriverExtractDest)
											while ((Get-Job -Name "$Model-Driver-Move").State -eq "Running") {
												global:Write-LogEntry -Value "$($Product): Moving $Make $Model $OperatingSystem $Architecture driver.. Next check in 30 seconds" -Severity 1
												Start-Sleep -seconds 30
											}
										} else {
											global:Write-ErrorOutput -Message "Error: Issues occurred during the $Make $Model extract process" -Severity 3
										}
									}
								}
								# =============== MDT Driver Import ====================							
								Invoke-MDTImportProcess -OperatingSystem $OperatingSystem -DriverExtractDest $DriverExtractDest
							} else {
								global:Write-LogEntry -Value "$($Product): Error downloading $DriverCab" -Severity 3
							}
						}
					} else {
						global:Write-ErrorOutput -Message "Error: MDT PowerShell Commandlets not found - Path specified $MDTPSLocation" -Severity 3
					}
					
					global:Write-LogEntry -Value "======== $Make $PRODUCT $MODEL PROCESSING FINISHED ========" -Severity 1
				}
				
				# Remove legacy driver packages
				if ($RemoveLegacyDriverCheckbox.Checked -eq $true) {
					Set-Location -Path ($SiteCode + ":")
					global:Write-LogEntry -Value "======== Superseded Driver Package Option Processing ========" -Severity 1
					$ModelDriverPacks = Get-CMDriverPackage -name "*$Model -*$WindowsVersion*$Architecture*" -Fast | Select-Object Name, PackageID, SourceDate | Sort-Object SourceDate -Descending
					$LatestDriverPack = $ModelDriverPacks | Sort-Object SourceDate -Descending | Select-Object -First 1
					if ($ModelDriverPacks.Count -gt "1") {
						foreach ($DriverPackage in $ModelDriverPacks) {
							if ($DriverPackage.PackageID -ne $LatestDriverPack.PackageID) {
								global:Write-LogEntry -Value "$($Product): Removing $($DriverPackage.Name) / Package ID $($DriverPackage.PackageID)" -Severity 1
								Remove-CMPackage -id $DriverPackage.PackageID -Force
							}
						}
					}
					if ($ModelDriverPacks.Count -gt "1") {
						$LegacyDriverPack = $ModelDriverPacks | Select-Object -Last 1
						global:Write-LogEntry -Value "$($Product): Removing $($LegacyDriverPack.Name) / Package ID $($LegacyDriverPack.PackageID)" -Severity 1
						Remove-CMDriverPackage -id $LegacyDriverPack.PackageID -Force
					}
					$ModelDriverPackages = Get-CMPackage -Name "Drivers -*$Model*$WindowsVersion*$Architecture*" -Fast | Select-Object Name, PackageID, Version, SourceDate | Sort-Object SourceDate -Descending
					$LatestDriverPackage = $ModelDriverPackages | Sort-Object SourceDate -Descending | Select-Object -First 1
					if ($ModelDriverPackages.Count -gt "1") {
						foreach ($DriverPackage in $ModelDriverPackages) {
							if ($DriverPackage.PackageID -ne $LatestDriverPackage.PackageID) {
								global:Write-LogEntry -Value "$($Product): Removing $($DriverPackage.Name) / Package ID $($DriverPackage.PackageID)" -Severity 1
								Remove-CMPackage -id $DriverPackage.PackageID -Force
							}
						}
					}
					Set-Location -Path $global:TempDirectory
				}
				
				# Remove legacy BIOS packages
				if ($RemoveLegacyBIOSCheckbox.Checked -eq $true) {
					Set-Location -Path ($SiteCode + ":")
					global:Write-LogEntry -Value "======== Superseded BIOS Package Option Processing ========" -Severity 1
					$ModelBIOSPackages = Get-CMPackage -Name "BIOS Update*$Model" -Fast | Select-Object Name, PackageID, Version, SourceDate | Sort-Object SourceDate -Descending
					$LatestBIOSPackage = $ModelBIOSPackages | Sort-Object SourceDate -Descending | Select-Object -First 1
					if ($ModelBIOSPackages.Count -gt "1") {
						foreach ($BIOSPackage in $ModelBIOSPackages) {
							if ($BIOSPackage.PackageID -ne $LatestBIOSPackage.PackageID) {
								global:Write-LogEntry -Value "$($Product): Removing $($BIOSPackage.Name) / Package ID $($BIOSPackage.PackageID)" -Severity 1
								Remove-CMPackage -id $BIOSPackage.PackageID -Force
							}
						}
					}
					Set-Location -Path $global:TempDirectory
				}
				
				$ProgressBar.Increment(1)
				$ModelProgressOverlay.Increment(1)
				$RemainingModels--
				$RemainingDownloads.Text = $RemainingModels
				global:Write-LogEntry -Value "Info: Remaining models to process: $RemainingModels" -Severity 1
			}
		}
		
		# OEM Catalog Drivers
		if ($ValidationErrors -eq 0 -and $DownloadJobType -eq "OEMDriverPackages") {
			
			# Set Mamufacturer Name
			$Make = "Hewlett-Packard"
			
			# Set Progress Bar Values
			$HPSoftPaqCount = 0
			for ($Row = 0; $Row -lt $HPSoftpaqDataGrid.RowCount; $Row++) {
				if ($HPSoftpaqDataGrid.Rows[$Row].Cells[0].Value -eq $true) {
					$HPSoftPaqCount++
				}
			}
			
			# Initialise Job Progress Bar
			$ProgressBar.Maximum = $HPSoftPaqCount
			$ModelProgressOverlay.Maximum = $HPSoftPaqCount
			$TotalDownloads.Text = $HPSoftPaqCount
			$RemainingDownloadCount = $HPSoftPaqCount
			$RemainingDownloads.Text = $RemainingDownloadCount
			
			
			# Directory used for driver and BIOS downloads
			$DownloadRoot = [string](Join-Path -Path $($DownloadPathTextBox.text) -ChildPath "\$Make\")
			
			# Directory used by ConfigMgr for packages
			if ($ImportInto -like "*ConfigMgr*") {
				$PackageRoot = [string]$(Join-Path -Path $($PackagePathTextBox.text) -ChildPath "\$Make\")
			} elseif ($ImportInto -match "Download") {
				$PackageRoot = $DownloadRoot
			}
			
			# Set Configuration Manager values
			if ($ImportInto -match "ConfigMgr") {
				Set-ConfigMgrFolder
			}
			
			# Loop through all selected rows and download / package content
			for ($Row = 0; $Row -lt $HPSoftpaqDataGrid.RowCount; $Row++) {
				if ($HPSoftpaqDataGrid.Rows[$Row].Cells[0].Value -eq $true) {
					try {
						# Define variables from data grid
						[string]$HPSoftPaqID = $HPSoftpaqDataGrid.Rows[$Row].Cells[1].Value
						[string]$HPSoftPaqTitle = $HPSoftpaqDataGrid.Rows[$Row].Cells[2].Value
						[string]$HPSoftPaqVersion = $HPSoftpaqDataGrid.Rows[$Row].Cells[3].Value
						[string]$HPSoftPaqURL = $HPSoftpaqDataGrid.Rows[$Row].Cells[7].Value
						[string]$HPSoftPaqSwitches = $HPSoftpaqDataGrid.Rows[$Row].Cells[8].Value
						[string]$HPSoftPaqBaseBoards = $HPSoftpaqDataGrid.Rows[$Row].Cells[9].Value
						[string]$HPSoftPaqPkgPath = $(Join-Path -Path $PackageRoot -ChildPath "SoftPaqs\$HPSoftPaqID")
						[string]$HPSoftPaqFileName = $HPSoftPaqURL | Split-Path -Leaf
						[string]$HPSoftPaqOSBuilds = $HPSoftpaqDataGrid.Rows[$Row].Cells[11].Value
						
						# Set Progress Bar Values
						$CurrentDownload.Text = $HPSoftPaqTitle
						$TotalDownloads.Text = $HPSoftPaqCount
						
						global:Write-LogEntry -Value "======== HP SoftPaq Download ========" -Severity 1
						global:Write-LogEntry -Value "SoftPaq: Package path set to $HPSoftPaqPkgPath" -Severity 1
						
						Invoke-ContentDownload -OperationalMode DriverAppPackages -HPSoftPaqID $HPSoftPaqID -HPSoftPaqTitle $HPSoftPaqTitle -HPSoftPaqVersion $HPSoftPaqVersion -HPSoftPaqURL $HPSoftPaqURL -HPSoftPaqSwitches $HPSoftPaqSwitches -HPSoftPaqBaseBoards $HPSoftPaqBaseBoards -HPSoftPaqPkgPath $HPSoftPaqPkgPath
						
						# Write SoftPaq XML
						global:Write-LogEntry -Value "SoftPaq: Writing HP silent install SoftPaq details into XML" -Severity 1
						Write-SoftPaqXML -Path $HPSoftPaqPkgPath -SetupFile $HPSoftPaqFileName -InstallSwitches $HPSoftPaqSwitches -BaseBoardValues $HPSoftPaqBaseBoards -SoftPaqID $HPSoftPaqID
						
						# Call Packaging Function - Configuration Manager
						if ($ImportInto -match "ConfigMgr") {
							global:Write-LogEntry -Value "SoftPaq: Creating HP SoftPaq Package" -Severity 1
							global:Write-LogEntry -Value "SoftPaq: ID = $HPSoftPaqID" -Severity 1
							global:Write-LogEntry -Value "SoftPaq: Title = $HPSoftPaqTitle" -Severity 1
							global:Write-LogEntry -Value "SoftPaq: Version = $HPSoftPaqVersion" -Severity 1
							global:Write-LogEntry -Value "SoftPaq: Switches = $HPSoftPaqSwitches" -Severity 1
							global:Write-LogEntry -Value "SoftPaq: Baseboards = $HPSoftPaqBaseBoards" -Severity 1
							global:Write-LogEntry -Value "SoftPaq: Package Path = $HPSoftPaqPkgPath" -Severity 1
							global:Write-LogEntry -Value "SoftPaq: Filename = $HPSoftPaqFileName" -Severity 1
							global:Write-LogEntry -Value "SoftPaq: OS Build(s) = $HPSoftPaqOSBuilds" -Severity 1
							Invoke-SoftPaqCreation -HPSoftPaqID $HPSoftPaqID -HPSoftPaqTitle $HPSoftPaqTitle -HPSoftPaqVersion $HPSoftPaqVersion -HPSoftPaqPkgPath $HPSoftPaqPkgPath -HPSoftPaqFileName $HPSoftPaqFileName -HPSoftPaqOSBuilds $HPSoftPaqOSBuilds -HPSoftPaqSwitches $HPSoftPaqSwitches
						}
						
						$RemainingDownloadCount--
						$RemainingDownloads.Text = $RemainingDownloadCount
						global:Write-LogEntry -Value "Info: Remaining SoftPaq downloads to process: $RemainingDownloadCount" -Severity 1
						$ProgressBar.Increment(1)
						$ModelProgressOverlay.Increment(1)
					} catch [System.Exception] {
						global:Write-LogEntry -Value "SoftPaq Creation Error: $($_.Exception.Message)" -Severity 3
					}
				}
			}
		}
		
		# Rename legacy SoftPaqs
		if ($HPCheckBox.Checked -eq $true) {
			Set-Location -Path ($SiteCode + ":")
			$SoftPaqList = $ModelDriverPacks = Get-CMPackage -Name "SoftPaq - *" -Fast | Select-Object Name, PackageID, SourceDate | Sort-Object Name
			$LegacySoftPaqList = ($SoftPaqList | Where-Object {
					$_.Name -in ($SoftPaqList | Group-Object -Property Name | Where-Object {
							$_.Count -gt 1
						}).Name
				}) | Select-Object Name -Unique
			
			if ($LegacySoftPaqList.Count -gt 1) {
				global:Write-LogEntry -Value "======== Retiring Superseded SoftPaqs =======" -Severity 1
				foreach ($LegacySoftPaq in $LegacySoftPaqList.Name) {
					$LegacySoftPaqPkgs = Get-CMPackage -Name $LegacySoftPaq -Fast | Select-Object Name, PackageID, SourceDate | Sort-Object SourceDate -Descending
					if ($LegacySoftPaqPkgs.Count -gt 1) {
						$LegacySoftPaqPkgs = $LegacySoftPaqPkgs | Select-Object -Last ($LegacySoftPaqPkgs.Count -1)
						foreach ($Package in $LegacySoftPaqPkgs) {
							global:Write-LogEntry -Value "SoftPaq: Renaming $($Package.Name) package ID $($Package.PackageID) with legacy prefix" -Severity 1
							Set-CMPackage -PackageID $Package.PackageID -NewName $("Legacy " + $Package.Name)
						}
					}
				}
			}
			Set-Location -Path $global:TempDirectory
		}
	
		
		# Clean up processes
		if ($ValidationErrors -eq 0) {
			if (($CleanUnusedCheckBox.Checked -eq $true) -or ($RemoveDriverSourceCheckbox.Checked -eq $true)) {
				global:Write-LogEntry -Value "======== Clean Up Driver Option Processing ========" -Severity 1
				if ($CleanUnusedCheckBox.Checked -eq $true) {
					Set-Location -Path ($SiteCode + ":")
					# Sleep to allow for driver package registration
					Start-Sleep -Seconds 10
					# Get list of unused drivers
					global:Write-LogEntry -Value "$($Product): Building driver list" -Severity 1
					$DriverList = Get-CMDriverPackage | Get-CMDriver | Select-Object -Property CI_ID
					global:Write-LogEntry -Value "$($Product): Building boot image driver list" -Severity 1
					$BootDriverList = (Get-CMBootImage | Select-Object ReferencedDrivers).ReferencedDrivers
					$UnusedDrivers = Get-CMDriver | Where-Object {
						(($_.CI_ID -notin $DriverList.CI_ID) -and ($_.CI_ID -notin $BootDriverList.ID))
					}
					global:Write-LogEntry -Value "$($Product): Found $($UnusedDrivers.Count) unused drivers" -Severity 1
					global:Write-LogEntry -Value "$($Product): Starting driver package clean up process" -Severity 1
					foreach ($Driver in $UnusedDrivers) {
						global:Write-LogEntry -Value "$($Product): Removing $($Driver.LocalizedDisplayName) from category $($Driver.LocalizedCategoryInstanceNames)" -Severity 1
						Remove-CMDriver -ID $Driver.CI_ID -Force
					}
					global:Write-LogEntry -Value "$($Product): Driver clean up process completed" -Severity 1
					Set-Location -Path $global:TempDirectory
				}
				if ($RemoveDriverSourceCheckbox.Checked -eq $true) {
					# Clean Up Driver Source Files
					if ((($DownloadPathTextBox.Text) -ne $null) -and ((Test-Path -Path ($DownloadPathTextBox.text)) -eq $true)) {
						global:Write-LogEntry -Value "$($Product): Removing driver download and extracted source driver files from $($DownloadPathTextBox.Text)" -Severity 1
						# Remove driver cabinets and extracted drivers
						Set-Location -Path $global:TempDirectory
						#Set-Location -Path ($DownloadPathTextBox.Text)		
						$LegacySources = Get-ChildItem -Path ($DownloadPathTextBox.Text) -Recurse -Directory -Depth 2 | Where-Object {
							$_.FullName -match "Driver Cab" -or $_.FullName -match "Windows"
						}
						foreach ($LegacySource in $LegacySources) {
							if ($LegacySource.FullName -like "*$($DownloadPathTextBox.Text)*") {
								global:Write-LogEntry -Value "$($Product): Removing source content from $($LegacySource.FullName)" -Severity 1
								Remove-Item -Path $LegacySource.FullName -Recurse -Force -Verbose
							}
						}
						# Remove empty folders
						$EmptySources = Get-ChildItem -Path ($DownloadPathTextBox.Text) -Recurse -Directory | Where-Object {
							$_.GetFiles().Count -eq 0 -and $_.GetDirectories().Count -eq 0
						}
						foreach ($EmptySource in $EmptySources) {
							if ($EmptySource.FullName -like "*$($DownloadPathTextBox.Text)*") {
								global:Write-LogEntry -Value "$($Product): Removing empty source content from $($EmptySource.FullName)" -Severity 1
								Remove-Item -Path $EmptySource.FullName -Recurse -Force -Verbose
							}
						}
					}
				}
			}
			
			# Increment status counter
			$ProgressBar.Increment(1)
			$ModelProgressOverlay.Increment(1)
			
			# Create XML logic file if required
			if ($CreateXMLLogicPackage.Checked -eq $true -and $ImportInto -match "ConfigMgr") {
				global:Write-LogEntry -Value "======== Creating/Recreating XML Logic Files =======" -Severity 1
				Write-XMLLogicPackage -XMLType Drivers
				Start-Sleep -Milliseconds 100
				Write-XMLLogicPackage -XMLType BIOS
				Start-Sleep -Milliseconds 100
				if ($HPCheckBox.Checked -eq $true) {
					Write-XMLLogicPackage -XMLType SoftPaqs
					Start-Sleep -Milliseconds 100
				}
				Write-XMLLogicPackage -Distribute
			}
			
			$JobStatus.Text = "Completed"
			global:Write-LogEntry -Value "======== FINISHED PROCESSING ========" -Severity 1
		} elseif ($ValidationErrors -gt 0) {
			global:Write-LogEntry -Value "======== Validation Error(s) ========" -Severity 3
			global:Write-LogEntry -Value "$($ValidationErrors) validation errors have occurred. Please review the log located at $global:LogFilePath." -Severity 3
		}
	}
	
	# Used to create scheduled task jobs
	function Schedule-Downloads {
		if ((Get-ScheduledTask | Where-Object {
					$_.TaskName -eq 'Driver Automation Tool'
				}) -eq $null) {
			global:Write-LogEntry -Value "======== Scheduling Job ========" -Severity 1
			global:Write-LogEntry -Value "Scheduling: Copying PowerShell script to $($ScriptLocation.Text)" -Severity 1
			Copy-Item (Join-Path (Get-ScriptDirectory) Run-DriverAutomationToolSvc.ps1) -Destination (Join-Path $ScriptLocation.Text "Run-DriverAutomationToolSvc.ps1")
			global:Write-LogEntry -Value "Scheduling: Creating Driver Automation Tool scheduled task" -Severity 1
			$TaskArguments = "-NoLogo -Noninteractive -ExecutionPolicy Bypass -Command " + '"' + "& $($ScriptLocation.Text)" + "\Run-DriverAutomationToolSVC.ps1" + '"'
			$Action = New-ScheduledTaskAction -Execute '%SystemRoot%\system32\WindowsPowerShell\v1.0\powershell.exe' -Argument $TaskArguments -WorkingDirectory $ScriptLocation.Text
			$Trigger = New-ScheduledTaskTrigger -Once -At "$($TimeComboBox.Text)" -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-Timespan -Days 3650)
			$Settings = New-ScheduledTaskSettingsSet -DontStopOnIdleEnd -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 10 -StartWhenAvailable
			$Settings.ExecutionTimeLimit = "PT0S"
			$SecurePassword = ConvertTo-SecureString "$($PasswordTextBox.Text)" -AsPlainText -Force
			$UserName = "$($UsernameTextBox.Text)"
			$Credentials = New-Object System.Management.Automation.PSCredential -ArgumentList $UserName, $SecurePassword
			$Password = $Credentials.GetNetworkCredential().Password
			$Task = New-ScheduledTask -Action $Action -Trigger $Trigger -Settings $Settings
			$Task | Register-ScheduledTask -TaskName 'Driver Automation Tool' -User $Username -Password $Password
		} else {
			global:Write-LogEntry -Value "WARNING: Scheduled task already exists." -Severity 2
		}
	}
	
	function Invoke-ContentExtract {
		global:Write-LogEntry -Value "$($Product): $DriverCab - File exists processing driver package" -Severity 1
		if (![string]::IsNullOrEmpty($global:BitsJobByteSize)) {
			global:Write-LogEntry -Value "$($Product): $DriverCab - File size verified" -Severity 1
		}
		# =============== Create Driver Package + Import Drivers =================
		if (((Test-Path -Path "$DriverExtractDest") -eq $false) -and ($Make -ne "Lenovo")) {
			New-Item -ItemType Directory -Path "$($DriverExtractDest)"
		}
		if ((Get-ChildItem -Path "$DriverExtractDest" -Recurse -Filter *.inf -File).Count -eq 0) {
			global:Write-LogEntry -Value "==================== $PRODUCT DRIVER EXTRACT ====================" -Severity 1
			global:Write-LogEntry -Value "$($Product): Expanding driver CAB source file: $DriverCab" -Severity 1
			global:Write-LogEntry -Value "$($Product): Driver CAB destination directory: $DriverExtractDest" -Severity 1
			if ($Make -eq "Dell") {
				global:Write-LogEntry -Value "$($Product): Extracting $Make drivers to $DriverExtractDest" -Severity 1
				Start-Job -Name "$Make $Model driver extract" -ScriptBlock $DriverExtractJob -ArgumentList $DriverSourceCab, $DriverExtractDest
				While ((Get-Job -Name "$Make $Model driver extract").State -eq "Running") {
					global:Write-LogEntry -Value "$($Product): Waiting for extract process to complete..  Next check in 30 seconds" -Severity 1
					Start-Sleep -Seconds 30
				}
			}
			if ($Make -eq "Hewlett-Packard") {
				Invoke-HPSoftPaqExpand -SoftPaqType Drivers
			}
			if ($Make -eq "Lenovo") {
				# Driver Silent Extract Switches
				$LenovoSilentSwitches = "/VERYSILENT /DIR=" + '"' + $DriverExtractDest + '"'
				global:Write-LogEntry -Value "$($Product): Using $Make silent switches: $LenovoSilentSwitches" -Severity 1
				global:Write-LogEntry -Value "$($Product): Extracting $Make drivers to $DriverExtractDest" -Severity 1
				Unblock-File -Path $($DownloadRoot + $Model + '\Driver Cab\' + $DriverCab)
				Start-Process -FilePath "$($DownloadRoot + $Model + '\Driver Cab\' + $DriverCab)" -ArgumentList $LenovoSilentSwitches -Verb RunAs
				$DriverProcess = ($DriverCab).Substring(0, $DriverCab.length - 4)
				# Wait for Lenovo Driver Process To Finish
				While ((Get-Process).name -contains $DriverProcess) {
					global:Write-LogEntry -Value "$($Product): Waiting for extract process (Process: $DriverProcess) to complete..  Next check in 30 seconds" -Severity 1
					Start-Sleep -seconds 30
				}
			}
			if ($Make -eq "Microsoft") {
				Invoke-ContentExtraction -PackageType Drivers
			}
		} else {
			global:Write-LogEntry -Value "Skipping.. Drivers already extracted." -Severity 1
		}
		if ($ImportInto -notmatch "Download") {
			# Start package creation process
			Invoke-PackageCreation -PackageType Drivers
		} elseif ($ImportInto -match "XML") {
			# Output or Append XML
			Write-XMLModels -XMLPath $DownloadPath -Make $Make -Model $Model -MatchingValues $([string]$global:SkuValue) -OperatingSystem $OSComboBox.SelectedItem -Architecture $ArchitectureComboxBox.SelectedItem -Platform "XML"
			
			global:Write-LogEntry -Value "======== DRIVER FALLBACK FOLDERS ========" -Severity 1
			# Create driver fall back package folder structure
			foreach ($OS in $($OSComboBox.Items)) {
				if (!(Test-Path -Path (Join-Path -Path $DownloadPath -ChildPath "Fallback\$OS"))) {
					global:Write-LogEntry -Value "$($Product): Creating $OS driver fallback folder" -Severity 1
					New-Item -Path (Join-Path -Path $DownloadPath -ChildPath "Fallback\$OS") -ItemType dir
					foreach ($FallbackArchitecture in "x64", "x86") {
						if (!(Test-Path -Path (Join-Path -Path $DownloadPath -ChildPath "Fallback\$OS\$FallbackArchitecture"))) {
							global:Write-LogEntry -Value "$($Product): Creating $OS $FallbackArchitecture subfolder" -Severity 1
							New-Item -Path (Join-Path -Path $DownloadPath -ChildPath "Fallback\$OS\$FallbackArchitecture") -ItemType dir
						}
					}
				}
			}
		}
	}
	
	# Test Active Directory Credentials
	function Test-Credentials {
		try {
			$Username = $UsernameTextBox.Text
			$Password = $PasswordTextBox.Text
			# Get current domain using logged-on user's credentials
			$CurrentDomain = "LDAP://" + ([ADSI]"").distinguishedName
			if ($CurrentDomain -ne $null) {
				$DomainValidation = New-Object System.DirectoryServices.DirectoryEntry($CurrentDomain, $UserName, $Password)
				if (($DomainValidation | Select-Object Path).path -gt $null) {
					Return $true
				} else {
					Return $false
				}
			} else {
				global:Write-LogEntry -Value "Non Domain environment: Testing local username / password" -Severity 2
				Add-Type -AssemblyName System.DirectoryServices.AccountManagement
				$UserValidation = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('machine', $env:ComputerName)
				if (($UserValidation.ValidateCredentials($UserName, $Password)) -eq $true) {
					Return $true
				} else {
					Return $false
				}
			}
		} catch [System.Exception]
		{
			global:Write-ErrorOutput -Message "Error: Username / Password incorrect" -Severity 3
			Return $false
		}
	}
	
	function Confirm-Settings {
		
		if ((($PlatformComboBox.SelectedText -ne $null -and $DownloadComboBox.SelectedText -ne $null -and $OSComboBox.SelectedText -ne $null -and $ArchitectureComboxBox.Text -ne $null))) {
			$global:Validation = $true
			
		} else {
			$global:Validation = $false
		}
		global:Write-LogEntry -Value "Validation state is $($global:Validation)" -Severity 1
	}
	
	function Confirm-ProxyAccess {
		param (
			[parameter(Mandatory = $true)]
			[String[]][ValidateNotNullOrEmpty()]
			[String]$ProxyServer,
			[parameter(Mandatory = $true)]
			[String[]][ValidateNotNullOrEmpty()]
			[string]$UserName,
			[parameter(Mandatory = $true)]
			[Uri[]][ValidateNotNullOrEmpty()]
			[Uri]$URL,
			[parameter(Mandatory = $true)]
			[String[]][ValidateNotNullOrEmpty()]
			[string]$Password
		)
		
		global:Write-LogEntry -Value "======== PROXY SERVER VALIDATION ========" -Severity 1
		$Proxy = New-Object System.Net.WebProxy($ProxyServer)
		$SecurePassword = $Password | ConvertTo-SecureString -AsPlainText -Force
		$global:ProxyCredentials = New-Object System.Management.Automation.PSCredential $Username, $SecurePassword
		$global:ProxyServer = $Proxy
		$Proxy.Credentials = $global:ProxyCredentials
		$WebClient = New-Object System.Net.WebClient
		$WebClient.Proxy = $global:ProxyServer
		global:Write-LogEntry -Value "Proxy: Proxy server set to $ProxyServer" -Severity 1
		
		Try {
			global:Write-LogEntry -Value "Proxy: Testing authenticated proxy server access to $URL" -Severity 1
			$Content = $WebClient.DownloadString("http://" + $($URL.Host))
			global:Write-LogEntry -Value "Proxy: Connected to $URL successfully" -Severity 1
			$global:InvokeProxyOptions = @{
				'Proxy' = "$global:ProxyServer";
				'ProxyUseDefaultCredentials' = $true
			}
			$global:BitsProxyOptions = @{
				'RetryInterval' = "60";
				'RetryTimeout' = "180";
				'ProxyList' = $global:ProxyServer;
				'ProxyAuthentication' = "Negotiate";
				'ProxyCredential' = $global:ProxyCredentials;
				'ProxyUsage' = "Override";
				'Priority' = "Foreground"
			}
			$global:ProxySettingsSet = $true
			global:Write-LogEntry -Value "Proxy: Global proxy settings set for web/bits transfers" -Severity 1
		} catch [System.Exception] {
			global:Write-LogEntry -Value "Proxy: Unable to access URL: $URL. Error message: $($_.Exception.Message)" -Severity 3
		}
	}
	
	function Get-MDTEnvironment {
		$MDTDeploymentShareNames.Clear()
		$DeploymentShareGrid.Rows.Clear()
		$ProgressListBox.ForeColor = 'Black'
		global:Write-LogEntry -Value "======== Validating MDT PS Script Availability ========" -Severity 1
		if ($MDTScriptTextBox.Text -ne $MDTPSCommandlets) {
			global:Write-LogEntry -Value "Info: Using alternative location for MDT PowerShell cmdlets" -Severity 1
			if (-not ([string]::IsNullOrEmpty($MDTScriptTextBox.Text))) {
				$MDTPSCommandlets = Join-Path -Path $MDTScriptTextBox.Text -ChildPath $($MDTPSCommandlets | Split-Path -Leaf)
			}
		}
		if ((Test-Path -Path $MDTPSCommandlets) -eq $true) {
			$MDTScriptTextBox.BackColor = 'White'
			global:Write-LogEntry -Value "Info: Setting MDT PS module path to default value." -Severity 1
			$MDTScriptTextBox.Text = "$MDTPSCommandlets"
			$MDTPSLocation = $MDTPSCommandlets
			try {
				global:Write-LogEntry -Value "Info: Importing MDT PS cmdlets" -Severity 1
				Import-Module "$MDTPSLocation"
				global:Write-LogEntry -Value "Info: Discovering MDT deployment shares" -Severity 1
				$MDTDeploymentShares = Get-MDTPersistentDrive
				foreach ($DeploymentShare in $MDTDeploymentShares) {
					$DeploymentShareGrid.Rows.Add($false, $DeploymentShare.Name, $DeploymentShare.Path, $DeploymentShare.Description)
					if ($DeploymentShare.Name -notin $MDTDeploymentShareNames) {
						$MDTDeploymentShareNames.Add($DeploymentShare.Name)
					}
				}
				foreach ($DeploymentShare in $global:DATSettingsXML.Settings.MDTSettings.DeploymentShare) {
					[int]$Row = "0"
					while ($Row -lt $DeploymentShareGrid.RowCount) {
						if ($DeploymentShareGrid.Rows[$Row].Cells["Name"].Value -eq $DeploymentShare) {
							$DeploymentShareGrid.Rows[$Row].Cells[0].Value = $true
						}
						$Row++
					}
				}
				$global:MDTValidation = $True
			} catch [System.Exception] {
				global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
			}
		} else {
			$ProgressListBox.ForeColor = 'Maroon'
			global:Write-LogEntry -Value "======== MDT Issue Detected ========" -Severity 1
			global:Write-LogEntry -Value "Warning: Failed to locate MDT PS module. Please specify location on the MDT Settings tab." -Severity 2
			$MDTScriptTextBox.BackColor = 'Yellow'
		}
	}
	
	function Set-UpdateNotice {
		$NewVersionLabel.visible = $true
		$NewVersion.visible = $true
		$NewVersion.text = $NewRelease
		$GitHubLaunchButton.visible = $true
	}
	
	function Update-ConfigMgrPkgList {
		if (($PackageTypeCombo.Text -ne $null) -and ($DeploymentStateCombo.Text -ne $null)) {
			try {
				$PackageUpdateNotice.text = "Updating package list.."
				$PackageUpdatePanel.visible = $true
				$PackageUpdateNotice.visible = $true
				Set-Location -Path ($SiteCodeText.Text + ":")
				$PackageGrid.Rows.clear()
				switch ($DeploymentStateCombo.text) {
					"Production" {
						$PackagePrefix = $PackageTypeCombo.text
					}
					"Pilot" {
						$PackagePrefix = ($PackageTypeCombo.text + " " + $DeploymentStateCombo.Text)
					}
					"Retired" {
						$PackagePrefix = ($PackageTypeCombo.text + " " + $DeploymentStateCombo.Text)
					}
				}
				$ConfigMgrPkgs = Get-CMPackage -Name "$PackagePrefix -*" -fast | Select-Object Name, PackageID, Version, SourceDate | Sort-Object Name
				foreach ($Package in $ConfigMgrPkgs) {
					$PackageGrid.Rows.Add($false, $Package.Name, $Package.Version, $Package.PackageID, $Package.SourceDate)
				}
				Set-Location -Path $global:TempDirectory
				$PackageUpdatePanel.visible = $false
				$PackageUpdateNotice.visible = $false
			} catch [System.Exception] {
				global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
			}
		}
	}
	
	function Update-MakeModelList {
		if (($PackageTypeCombo.Text -ne $null) -and ($DeploymentStateCombo.Text -ne $null)) {
			try {
				$PackageUpdateNotice.text = "Updating package list.."
				$PackageUpdatePanel.visible = $true
				$PackageUpdateNotice.visible = $true
				Set-Location -Path ($SiteCodeText.Text + ":")
				$PackageGrid.Rows.clear()
				switch ($DeploymentStateCombo.text) {
					"Production" {
						$PackagePrefix = $PackageTypeCombo.text
					}
					"Pilot" {
						$PackagePrefix = ($PackageTypeCombo.text + " " + $DeploymentStateCombo.Text)
					}
					"Retired" {
						$PackagePrefix = ($PackageTypeCombo.text + " " + $DeploymentStateCombo.Text)
					}
				}
				$ConfigMgrPkgs = Get-CMPackage -Name "$PackagePrefix -*" -fast | Select-Object Name, PackageID, Version, SourceDate | Sort-Object Name
				foreach ($Package in $ConfigMgrPkgs) {
					$PackageGrid.Rows.Add($false, $Package.Name, $Package.Version, $Package.PackageID, $Package.SourceDate)
				}
				Set-Location -Path $global:TempDirectory
				$PackageUpdatePanel.visible = $false
				$PackageUpdateNotice.visible = $false
			} catch [System.Exception] {
				global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
			}
		}
	}
	
	function Move-ConfigMgrPkgs {
		$PackageUpdateNotice.text = "Changing package state.."
		$PackageUpdatePanel.visible = $true
		$PackageUpdateNotice.visible = $true
		try {
			$RowCount = 0
			switch ($PackageTypeCombo.text) {
				"Drivers"{
					$PackageType = "Drivers"
				}
				"BIOS Update"{
					$PackageType = "BIOS Update"
				}
			}
			switch -wildcard ($ConfigMgrPkgActionCombo.text) {
				"*Production*" {
					$PackagePrefix = "$PackageType "
					$State = "production"
				}
				"*Pilot*" {
					$PackagePrefix = "$PackageType Pilot "
					$State = "pilot"
				}
				"*Retired*" {
					$PackagePrefix = "$PackageType Retired "
					$State = "retired"
				}
				"*Windows 10 2004*"{
					$Win10Version = "2004"
				}
				"*Windows 10 1909*"{
					$Win10Version = "1909"
				}
				"*Windows 10 1903*"{
					$Win10Version = "1903"
				}
				"*Windows 10 1809*"{
					$Win10Version = "1809"
				}
				"*Windows 10 1803*"{
					$Win10Version = "1803"
				}
				"*Windows 10 1709"{
					$Win10Version = "1709"
				}
				"*Windows 10 1703*"{
					$Win10Version = "1703"
				}
				"*Windows 10 1611*"{
					$Win10Version = "1611"
				}
			}
			Set-Location -Path ($SiteCodeText.Text + ":")
			for ($Row = 0; $Row -lt $PackageGrid.RowCount; $Row++) {
				if ($PackageGrid.Rows[$Row].Cells[0].Value -eq $true) {
					$RowCount++
				}
			}
			global:Write-LogEntry -Value "======== Package State Change Processing ========" -Severity 1
			Do {
				for ($Row = 0; $Row -lt $PackageGrid.RowCount; $Row++) {
					if ($PackageGrid.Rows[$Row].Cells[0].Value -eq $true) {
						global:Write-LogEntry -Value "Info: Migrating package ID $($PackageGrid.Rows[$Row].Cells[3].Value) to driver $($ConfigMgrPkgActionCombo.Text) state" -Severity 1
						$CurrentState = ($PackageGrid.Rows[$Row].Cells[1].Value).split("-")[0]
						$CurrentPkgName = $($PackageGrid.Rows[$Row].Cells[1].Value)
						global:Write-LogEntry -Value "Info: Working with package $($PackageGrid.Rows[$Row].Cells[1].Value)" -Severity 1
						global:Write-LogEntry -Value "Info: Updating package ID $($PackageGrid.Rows[$Row].Cells[3].Value) to $State" -Severity 1
						if (-not ([string]::IsNullOrEmpty($State))) {
							$NewPackageName = ($PackageGrid.Rows[$Row].Cells[1].Value).Replace("$CurrentState", "$PackagePrefix")
						} else {
							if ($($PackageGrid.Rows[$Row].Cells[1].Value) -match "Windows 10 x") {
								$NewPackageName = ($PackageGrid.Rows[$Row].Cells[1].Value).Replace("Windows 10", "Windows 10 $Win10Version ")
							} elseif ($($PackageGrid.Rows[$Row].Cells[1].Value) -match "Windows 10 10.") {
								foreach ($WindowsBuild in $WindowsBuildHashTable.Values) {
									if ($CurrentPkgName -match $WindowsBuild) {
										$WindowsVersion = $($WindowsBuildHashTable.Keys.Where({
													$WindowsBuildHashTable[$_] -match $WindowsBuild
												}))
										$NewPackageName = $CurrentPkgName.Replace($WindowsBuild, $WindowsVersion)
									}
								}
							} elseif ($($PackageGrid.Rows[$Row].Cells[1].Value) -match "Windows 10 1") {
								foreach ($WinVersion in $WindowsBuildHashTable.Keys) {
									if ($CurrentPkgName -match $WinVersion) {
										$NewPackageName = $CurrentPkgName.Replace($WinVersion, $Win10Version)
									}
								}
							}
						}
						if (-not ([string]::IsNullOrEmpty($NewPackageName))) {
							
						}
						global:Write-LogEntry -Value "Info: Updating package name to $NewPackageName" -Severity 1
						Get-CMPackage -ID ($PackageGrid.Rows[$Row].Cells[3].Value) -Fast | Set-CMPackage -NewName $NewPackageName
						$PackageGrid.Rows.Remove($PackageGrid.Rows[$Row])
						$PackageGrid.CommitEdit('RowDeletion')
						$RowCount--
					}
				}
			} Until ($RowCount -eq 0)
			Update-ConfigMgrPkgList
			Set-Location -Path $global:TempDirectory
			$ConfigMgrPkgActionCombo.SelectedIndex = "-1"
		} catch [System.Exception] {
			global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
		}
		$PackageUpdatePanel.visible = $false
		$PackageUpdateNotice.visible = $false
	}
	
	function Create-CustomPkg {
		
		$ConfigMgrPkg = {
			# Create ConfigMgr Package
			$PackageRoot = Join-Path -Path $PackagePathTextBox.Text.Trimend("\") -ChildPath "\$Make\"
			$SiteCode = $SiteCodeText.Text
			$DriverPackageDest = ("$PackageRoot" + "$Model" + "\" + "$OperatingSystem-$Architecture-$DriverRevision")
			$CMPackage = ("Drivers - " + "$Make " + $Model + " - " + $OperatingSystem + " " + $Architecture)
			global:Write-LogEntry -Value "Info: Copying source files to package directory" -Severity 1
			Set-Location -Path ($SiteCode + ":")
			$ExistingPackageID = (Get-CMPackage -Name $CMPackage -Fast | Select-Object PackageID, Name, Version | Where-Object {
					$_.Version -eq $DriverRevision
				})
			if ([string]::IsNullOrEmpty($ExistingPackageID)) {
				Set-Location -Path $global:TempDirectory
				if ((Test-Path -Path $DriverPackageDest) -eq $false) {
					try {
						global:Write-LogEntry -Value "Info: Creating driver package destination directory at $DriverPackageDest" -Severity 1
						New-Item -Path $DriverPackageDest -ItemType Dir
						global:Write-LogEntry -Value "Info: Copying source files to package directory" -Severity 1
						Copy-Item -Path $PackageSource -Destination $DriverPackageDest -Recurse
						Set-Location -Path ($SiteCode + ":")
						New-CMPackage -Name "$CMPackage" -path "$DriverPackageDest" -Manufacturer $Make -Description "(Models included:$SystemSKU)" -Version $DriverRevision
						$CustomPackage = Get-CMPackage -Name "$CMPackage" -Fast | Select-Object PackageID, Name, Version | Where-Object {
							$_.Version -eq $DriverRevision
						}
						global:Write-LogEntry -Value "Info: Package created $($CustomPackage.PackageID)" -Severity 1
						Distribute-Content -Product $Platform -PackageID $CustomPackage.PackageID -ImportInto "Standard"
						global:Write-LogEntry -Value "Info: Distributing package $($CustomPackage.PackageID)" -Severity 1
					} catch [System.Exception] {
						Write-Warning -Message "Error: Errors occurred while creating package - $($_.Exception.Message)"
					}
				} else {
					global:Write-LogEntry -Value "Warning: Package destination directory already exists." -Severity 2
					global:Write-LogEntry -Value "Remove files at $DriverPackageDest folder to replace this package" -Severity 2
				}
			} else {
				global:Write-LogEntry -Value "Info: Package already exists (Package ID: $($ExistingPackageID.PackageID))." -Severity 1
			}
			Set-Location -Path $global:TempDirectory
		}
		
		$MDTPkg = {
			# Create MDT Package
			$Product = "MDT"
			Get-MDTDeploymentShares
			Invoke-MDTImportProcess -DriverExtractDest $PackageSource -OperatingSystem $OperatingSystem
		}
		
		$XMLPkg = {
			# Create / Add XML Package
			$Product = "XML"
			$PackageRoot = Join-Path -Path $DownloadPathTextBox.text -ChildPath $($CustomPkgDataGrid.Rows[0].Cells[0].Value)
			$DriverPackageDest = ("$PackageRoot" + "\" + $($CustomPkgDataGrid.Rows[0].Cells[1].Value) + "\" + $($CustomPkgDataGrid.Rows[0].Cells[2].Value) + "\" + $($CustomPkgDataGrid.Rows[0].Cells[4].Value) + "-" + $($CustomPkgDataGrid.Rows[0].Cells[5].Value) + "-" + $($CustomPkgDataGrid.Rows[0].Cells[6].Value))
			try {
				if ((Test-Path -Path $DriverPackageDest) -eq $false) {
					global:Write-LogEntry -Value "$($Platform): Copying drivers to package directory - $PackageSource" -Severity 1
					Copy-Item -Path $PackageSource -Destination $DriverPackageDest -Force -Recurse
				}
				# Output or Append XML
				Write-XMLModels -XMLPath $DownloadPathTextBox.text -Make $Make -Model $Model -MatchingValues $($CustomPkgDataGrid.Rows[0].Cells[2].Value) -OperatingSystem $($CustomPkgDataGrid.Rows[0].Cells[3].Value) -Architecture $($CustomPkgDataGrid.Rows[0].Cells[4].Value) -Platform $Platform
			} catch [system.Exception] {
				global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
			}
		}
		$RemainingModels = $CustomPkgDataGrid.Rows.Count
		# Remove empty row
		$RemainingModels--
		# Initialise Job Progress Bar
		$ProgressBar.Maximum = $CustomPkgDataGrid.Rows.Count
		$ModelProgressOverlay.Maximum = $CustomPkgDataGrid.Rows.Count
		
		global:Write-LogEntry -Value "======== Processing Custom Packages ========" -Severity 1
		Do {
			for ($Row = 0; $Row -lt $CustomPkgDataGrid.Rows.Count; $Row++) {
				if ($RemainingModels -gt "0") {
					global:Write-LogEntry -Value "Info: Remaining Models To Process: $RemainingModels" -Severity 1
				}
				if ((![string]::IsNullOrEmpty($CustomPkgDataGrid.Rows[$Row].Cells["Make"].Value)) -and (![string]::IsNullOrEmpty($CustomPkgDataGrid.Rows[$Row].Cells["Model"].Value))) {
					if (![string]::IsNullOrEmpty($CustomPkgDataGrid.Rows[$Row].Cells["Make"].Value)) {
						$Make = $($CustomPkgDataGrid.Rows[$Row].Cells["Make"].Value)
						switch -wildcard ($Make) {
							"*Microsoft*" {
								$Make = "Microsoft"
							}
							"*HP*" {
								$Make = "Hewlett-Packard"
							}
							"*Hewlett*" {
								$Make = "Hewlett-Packard"
							}
							"*Lenovo*" {
								$Make = "Lenovo"
							}
							"*Dell*" {
								$Make = "Dell"
							}
						}
						if (![string]::IsNullOrEmpty($CustomPkgDataGrid.Rows[$Row].Cells["Model"].Value)) {
							$Model = $($CustomPkgDataGrid.Rows[$Row].Cells["Model"].Value)
							if (![string]::IsNullOrEmpty($CustomPkgDataGrid.Rows[$Row].Cells["BaseBoard"].Value)) {
								$SystemSKU = $($CustomPkgDataGrid.Rows[$Row].Cells["BaseBoard"].Value)
								if (-not ([string]::IsNullOrEmpty($CustomPkgPlatform.SelectedItem))) {
									$Platform = $CustomPkgPlatform.SelectedItem
									if (![string]::IsNullOrEmpty($CustomPkgDataGrid.Rows[$Row].Cells["OperatingSystem"].Value)) {
										$OperatingSystem = $($CustomPkgDataGrid.Rows[$Row].Cells["OperatingSystem"].Value)
										if ($OperatingSystem -like "Windows 10 *") {
											$WindowsVersion = $(($CustomPkgDataGrid.Rows[$Row].Cells["OperatingSystem"].Value).Split(" ") | Select-Object -Last 1)
										}
										if (![string]::IsNullOrEmpty($CustomPkgDataGrid.Rows[$Row].Cells["Architecture"].Value)) {
											$Architecture = $($CustomPkgDataGrid.Rows[$Row].Cells["Architecture"].Value)
											if (![string]::IsNullOrEmpty($CustomPkgDataGrid.Rows[$Row].Cells["Revision"].Value)) {
												$DriverRevision = $($CustomPkgDataGrid.Rows[$Row].Cells["Revision"].Value)
												$PackageSource = $($CustomPkgDataGrid.Rows[$Row].Cells["SourceDirectory"].Value)
												if (![string]::IsNullOrEmpty($CustomPkgDataGrid.Rows[$Row].Cells["SourceDirectory"].Value)) {
													$PackageSource = $($CustomPkgDataGrid.Rows[$Row].Cells["SourceDirectory"].Value)
													if ((Test-Path -Path "$PackageSource") -eq $true) {
														global:Write-LogEntry -Value "Info: Running $Platform import job for $Make $Model" -Severity 1
														if ($Platform -match "ConfigMgr") {
															try {
																Invoke-Command -ScriptBlock $ConfigMgrPkg
															} catch [System.Exception] {
																global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
															}
														}
														if ($Platform -match "MDT") {
															try {
																Invoke-Command -ScriptBlock $MDTPkg
															} catch [System.Exception] {
																global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
															}
														}
														if ($Platform -match "XML") {
															try {
																Invoke-Command -ScriptBlock $XMLPkg
															} catch [System.Exception] {
																global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
															}
														}
													} else {
														global:Write-LogEntry -Value "Warning: Source path does not exist or is not accessible." -Severity 2
													}
												} else {
													global:Write-LogEntry -Value "Warning: Package source field entry on row $Row is empty." -Severity 2
												}
											} else {
												global:Write-LogEntry -Value "Warning: Version field entry on row $Row is empty. " -Severity 2
											}
										} else {
											global:Write-LogEntry -Value "Warning: Architecture field entry on row $Row is empty." -Severity 2
										}
									} else {
										global:Write-LogEntry -Value "Warning: Operating System field entry on row $Row is empty." -Severity 2
									}
								} else {
									global:Write-LogEntry -Value "Warning: Platform field entry on row $Row is empty." -Severity 2
								}
							} else {
								global:Write-LogEntry -Value "Warning: Idenifier field entry on row $Row is empty." -Severity 2
							}
						} else {
							global:Write-LogEntry -Value "Warning: Make field entry on row $Row is empty." -Severity 2
						}
					} else {
						global:Write-LogEntry -Value "Warning: Model field entry on row $Row is empty." -Severity 2
					}
				}
				
				$ProgressBar.Increment(1)
				$ModelProgressOverlay.Increment(1)
				$RemainingModels--
			}
		} While ($Row -lt $CustomPkgDataGrid.Rows.Count)
	}
	
	function Import-CSVModels {
		
		$CSVFileBrowse = New-Object system.windows.forms.openfiledialog
		$CSVFileBrowse.MultiSelect = $false
		$CSVFileBrowse.Filter = "CSV Files (*.csv) | *.csv"
		$CSVFileBrowse.showdialog()
		$CSVFileName = $CSVFileBrowse.FileName
		global:Write-LogEntry -Value "======== CSV Import Process ========" -Severity 1
		global:Write-LogEntry -Value "Info: Importing models from comma separated value source file" -Severity 1
		global:Write-LogEntry -Value "Info: CSV location - $CSVFileName" -Severity 1
		try {
			if ($CSVFileName -match ".csv") {
				$ModelsToImport = Import-Csv -Path $CSVFileName
				global:Write-LogEntry -Value "Info: $($ModelsToImport.Model.Count) models found" -Severity 1
				foreach ($Model in $ModelsToImport) {
					if (!([string]::IsNullOrEmpty($Model.Make))) {
						if (!([string]::IsNullOrEmpty($Model.Model))) {
							if (!([string]::IsNullOrEmpty($Model.BaseBoard))) {
								if (($Model.Platform -match "ConfigMgr") -or ($Model.Platform -match "MDT")) {
									if ($Model.'Operating System' -match "Windows") {
										if (($Model.Architecture -eq "x64") -or ($Model.Architecture -eq "x86")) {
											if (!([string]::IsNullOrEmpty($Model.Version))) {
												if ($Model.'Source Directory') {
													global:Write-LogEntry -Value "Info: All fields have been verified. Adding $($Model.Make) $($Model.Model) to list." -Severity 1
													$CustomPkgDataGrid.Rows.Add($Model.Make, $Model.Model, $Model.Baseboard, $Model.Platform, $Model.'Operating System', $Model.Architecture, $Model.Version, $Model.'Source Directory')
												} else {
													global:Write-LogEntry -Value "Warning: Source directory field is empty." -Severity 2
												}
											} else {
												global:Write-LogEntry -Value "Warning: Version field is empty." -Severity 2
											}
										} else {
											global:Write-LogEntry -Value "Warning: Architecture either incorrectly or not specified." -Severity 2
										}
									} else {
										global:Write-LogEntry -Value "Warning: Operating system either incorrectly or not specified." -Severity 2
									}
								} else {
									global:Write-LogEntry -Value "Warning: Produst must be specified as either ConfigMgr or MDT." -Severity 2
								}
							} else {
								global:Write-LogEntry -Value "Warning: Baseboard product field is empty." -Severity 2
							}
						} else {
							global:Write-LogEntry -Value "Warning: Model field is empty." -Severity 2
						}
					} else {
						global:Write-LogEntry -Value "Warning: Make field is empty." -Severity 2
					}
				}
				global:Write-LogEntry -Value "Info: Finished import process" -Severity 1
			}
		} catch [System.Exception] {
			global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
		}
	}
	
	function Invoke-MDTImportProcess {
		param (
			[parameter(Mandatory = $false)]
			[String[]][ValidateNotNullOrEmpty()]
			[String]$DriverExtractDest,
			[parameter(Mandatory = $false)]
			[String[]][ValidateNotNullOrEmpty()]
			[String]$OperatingSystem
			
		)
		# Get Windows Build Number From Version Hash Table
		if ($OperatingSystem -like "Windows 10 1*") {
			$OSVersion = ($OperatingSystem).Split(" ") | Select-Object -Last 1
			$OSBuild = $WindowsBuildHashTable.Item([int]$OSVersion)
		}
		global:Write-LogEntry -Value "======== $PRODUCT Driver Import ========" -Severity 1
		global:Write-LogEntry -Value "$($Product): Starting MDT Driver Import Process" -Severity 1
		foreach ($MDTDeploymentShare in $global:MDTDeploymentShares) {
			# Detect First MDT PSDrive
			global:Write-LogEntry -Value "$($Product): Connecting MDT PSDrive $($MDTDeploymentShare.Cells["Name"].Value)" -Severity 1
			$PSDriveName = ($MDTDeploymentShare.Cells["Name"].Value)
			# Detect First MDT Deployment Share
			global:Write-LogEntry -Value "$($Product): Using MDT Deployment Path $($MDTDeploymentShare.Cells[1].Value)" -Severity 1
			$DeploymentShare = ($MDTDeploymentShare.Cells["Path"].Value)
			# Set root MDT paths
			$MDTDriverPath = $PSDriveName + ':\Out-of-Box Drivers'
			$MDTSelectionProfilePath = $PSDriveName + ':\Selection Profiles'
			# Connect to deployment share
			global:Write-LogEntry -Value "$($Product): Connecting to MDT share ($PSDriveName)" -Severity 1
			if (!(Get-PSDrive -Name $PSDriveName -ErrorAction SilentlyContinue)) {
				New-PSDrive -Name $PSDriveName -PSProvider MDTProvider -Root "$DeploymentShare"
				global:Write-LogEntry -Value "$($Product): $PSDriveName connected to $DeploymentShare" -Severity 1
			}
			# Cater for HP / Model Issue
			$Model = $Model -replace '/', '-'
			# Modify friendly manufaturer names for MDT total control method
			switch -Wildcard ($Make) {
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
			$Make = Set-Manufacturer -Make $Make
			# =============== MDT Driver Import ====================	
			$OperatingSystemDir = ($OperatingSystem.TrimEnd() + " " + $Architecture)
			global:Write-LogEntry -Value "$($Product): Creating $($MDTDriverStructureCombo.SelectedItem) folder structure" -Severity 1
			
			# Folder structure path selection
			switch -wildcard ($MDTDriverStructureCombo.SelectedItem) {
				"OperatingSystemDir\*" {
					if ((Test-Path $MDTDriverPath\$OperatingSystemDir) -eq $false) {
						New-Item -path $MDTDriverPath -enable "True" -Name $OperatingSystemDir -ItemType Directory
					}
					if ((Test-Path $MDTSelectionProfilePath"\Drivers - "$OperatingSystemDir) -eq $false) {
						New-Item -path $MDTSelectionProfilePath -enable "True" -Name "Drivers - $OperatingSystemDir" -Definition "<SelectionProfile><Include path=`"Out-of-Box Drivers\$OS`" /></SelectionProfile>" -ReadOnly "False"
					}
					if ((Test-Path $MDTDriverPath\$OperatingSystemDir\$Make) -eq $false) {
						New-Item -path $MDTDriverPath\$OperatingSystemDir -enable "True" -Name $Make -ItemType Directory
					}
					if ((Test-Path $MDTDriverPath\$OperatingSystemDir\$Make\$Model) -eq $false) {
						New-Item -path $MDTDriverPath\$OperatingSystemDir\$Make -enable "True" -Name $Model -ItemType Directory
					}
					if (((Test-Path $MDTDriverPath\$OperatingSystemDir\$Make\$Model\$DriverRevision) -eq $false) -and ($($MDTDriverStructureCombo.SelectedItem) -match "DriverRevision")) {
						New-Item -path $MDTDriverPath\$OperatingSystemDir\$Make\$Model -enable "True" -Name $DriverRevision -ItemType Directory
					}
					if ($($MDTDriverStructureCombo.SelectedItem) -match "DriverRevision") {
						$MDTDriverPath = "$MDTDriverPath\$OperatingSystemDir\$Make\$Model\$DriverRevision"
					} else {
						$MDTDriverPath = "$MDTDriverPath\$OperatingSystemDir\$Make\$Model"
					}
				}
				"Make\*" {
					if ((Test-Path $MDTDriverPath\$Make) -eq $false) {
						New-Item -path $MDTDriverPath -enable "True" -Name $Make -ItemType Directory
					}
					if ((Test-Path $MDTSelectionProfilePath"\Drivers - "$Make) -eq $false) {
						New-Item -path $MDTSelectionProfilePath -enable "True" -Name "Drivers - $Make" -Definition "<SelectionProfile><Include path=`"Out-of-Box Drivers\$OS`" /></SelectionProfile>" -ReadOnly "False"
					}
					if ((Test-Path $MDTDriverPath\$Make\$Model) -eq $false) {
						New-Item -path $MDTDriverPath\$Make -enable "True" -Name $Model -ItemType Directory
					}
					if ((Test-Path $MDTDriverPath\$Make\$Model\$OperatingSystemDir) -eq $false) {
						New-Item -path $MDTDriverPath\$Make\$Model -enable "True" -Name $OperatingSystemDir -ItemType Directory
					}
					if (((Test-Path $MDTDriverPath\$Make\$Model\$OperatingSystemDir\$DriverRevision) -eq $false) -and ($($MDTDriverStructureCombo.SelectedItem) -match "DriverRevision")) {
						New-Item -path $MDTDriverPath\$Make\$Model\$OperatingSystemDir -enable "True" -Name $DriverRevision -ItemType Directory
					}
					if ($($MDTDriverStructureCombo.SelectedItem) -match "DriverRevision") {
						$MDTDriverPath = "$MDTDriverPath\$Make\$Model\$OperatingSystemDir\$DriverRevision"
					} else {
						$MDTDriverPath = "$MDTDriverPath\$Make\$Model\$OperatingSystemDir"
					}
				}
			}
			
			global:Write-LogEntry -Value "$($Product): Importing MDT driver pack for $Make $Model - Revision $DriverRevision" -Severity 1
			global:Write-LogEntry -Value "$($Product): MDT Driver Path = $MDTDriverPath" -Severity 1
			try {
				# =============== MDT Driver Import ====================				
				if ($Make -match "Dell") {
					$DriverFolder = (Get-ChildItem -Path "$DriverExtractDest" -Recurse -Directory | Where-Object {
							$_.Name -eq "$Architecture"
						} | Select-Object -first 1).FullName
					global:Write-LogEntry -Value "$($Product): Importing MDT Drivers from $DriverExtractDest. This might take several minutes." -Severity 1
					Import-MDTDriver -path "$MDTDriverPath" -SourcePath "$DriverExtractDest"
					global:Write-LogEntry -Value "$($Product): Dell Driver package added successfully" -Severity 1
				} else {
					global:Write-LogEntry -Value "$($Product): Importing MDT Drivers from $DriverExtractDest. This might take several minutes." -Severity 1
					Import-MDTDriver -path "$MDTDriverPath" -SourcePath "$DriverExtractDest"
					global:Write-LogEntry -Value "$($Product): Driver package added successfully" -Severity 1
				}
			} catch [system.Exception]{
				global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
			}
		}
	}
	
	function Get-MDTDeploymentShares {
		
		$global:MDTDeploymentShares = $($DeploymentShareGrid.Rows | Where-Object {
				$_.Cells[0].Value -eq $true
			} | ForEach-Object {
				Write-Output $_
			})
		global:Write-LogEntry -Value "======== $Product Deployment Share Info ========" -Severity 1
		global:Write-LogEntry -Value "Info: Found $($DeploymentShareGrid.Rows.Count) MDT deployment shares available" -Severity 1
		foreach ($MDTDeploymentShare in $global:MDTDeploymentShares) {
			global:Write-LogEntry -Value "Info: Adding MDT Deployment Share - $($MDTDeploymentShare.Cells[0].Value)" -Severity 1
			global:Write-LogEntry -Value "Info: Adding MDT Deployment Path - $($MDTDeploymentShare.Cells[1].Value)" -Severity 1
		}
		if ([string]::IsNullOrEmpty($global:MDTDeploymentShares)) {
			global:Write-LogEntry -Value "Warning: No MDT deployment shares have been selected" -Severity 2
		}
	}
	
	function Enable-DriverFBPkg {
		if ((![string]::IsNullOrEmpty($FallbackOSCombo.Text)) -and (![string]::IsNullOrEmpty($FallbackArcCombo.Text))) {
			$CreateFallbackButton.Enabled = $true
		}
	}
	
	function Create-DriverFBPkg {
		
		try {
			$WindowsVersion = $FallbackOSCombo.Text
			switch -wildcard ($FallbackArcCombo.Text) {
				"*32*" {
					$Architecture = "x86"
				}
				"*64*" {
					$Architecture = "x64"
				}
			}
			$Manufacturer = $FallbackManufacturer.Text
			
			# Create ConfigMgr Package
			$PackageRoot = Join-Path -Path $(($PackagePathTextBox.Text).Trimend("\")) -ChildPath "Driver Fallback"
			$DriverPackageDest = Join-Path -Path $PackageRoot -ChildPath "$Manufacturer\$WindowsVersion-$Architecture"
			$SiteCode = $SiteCodeText.Text
			$CMPackage = ("Driver Fallback Package - $Manufacturer - " + $WindowsVersion + " " + $Architecture)
			$FallbackDriverFolder = ($SiteCode + ":" + "\Package" + "\Driver Packages" + "\$Manufacturer")
			Set-Location -Path ($SiteCode + ":")
			$ExistingPackageID = Get-CMPackage -Name $CMPackage -Fast | Select-Object PackageID
			if ([string]::IsNullOrEmpty($ExistingPackageID)) {
				Set-Location -Path $global:TempDirectory
				if ((Test-Path -Path $DriverPackageDest) -eq $false) {
					try {
						global:Write-LogEntry -Value "======== Creating $Manufacturer Driver Fallback Package ========" -Severity 1
						global:Write-LogEntry -Value "Info: Creating driver package destination directory at $DriverPackageDest" -Severity 1
						New-Item -Path $DriverPackageDest -ItemType Dir
						Set-Location -Path ($SiteCode + ":")
						New-CMPackage -Name "$CMPackage" -Path "$DriverPackageDest" -Description "Driver Fallback Package - $WindowsVersion $Architecture Drivers" -Manufacturer $Manufacturer
						Start-Sleep -Seconds 2
						$FallbackPackage = Get-CMPackage -Name "$CMPackage" -Fast | Select-Object -ExpandProperty PackageID
						global:Write-LogEntry -Value "Info: $Manufacturer driver fallback package created for $WindowsVersion $Architecture (Package ID $FallbackPackage)" -Severity 1
						global:Write-LogEntry -Value "Info: Moving package ID $FallbackPackage to $FallbackDriverFolder" -Severity 1
						Move-CMObject -ObjectID $FallbackPackage -FolderPath $FallbackDriverFolder
						global:Write-LogEntry -Value "Info: Distributing content to selected distribution points" -Severity 1
						Distribute-Content -Product $Platform -PackageID $CustomPackage.PackageID -ImportInto "Standard"
					} catch [System.Exception] {
						Write-Warning -Message "Error: Errors occurred while creating package - $($_.Exception.Message)"
					}
				} else {
					global:Write-LogEntry -Value "Warning: $Manufacturer driver fallback package destination directory already exists." -Severity 2
				}
			} else {
				global:Write-LogEntry -Value "Info: Package already exists (Package ID: $($ExistingPackageID.PackageID))." -Severity 1
			}
			Set-Location -Path $global:TempDirectory
		} catch [System.Exception] {
			global:Write-ErrorOutput -Message "Error: $($_.Exception.Message)" -Severity 3
		}
	}
	
	function Test-ConfigMgrWebSVC {
		
		# WebService Variables
		[uri]$URL = $ConfigMgrWebURL.Text
		[string]$SecretKeyValue = $SecretKey.Text
		
		# Get ConfigMgr WebService information
		try {
			$WebServiceDetails = Invoke-WebRequest -Uri $URL
		} catch {
			$WebServiceError = $_.Exception
		}
		# Update ConfigMgr WebService information
		$WebServiceResponse = Measure-Command -Expression {
			Invoke-WebRequest -uri $URL -UseBasicParsing
		}
		global:Write-LogEntry -Value "WebService response time - $($WebServiceResponse.Milliseconds)ms" -Severity 1
		$WebServiceResponseTime.Text = "$($WebServiceResponse.Milliseconds)ms"
		if ([string]::IsNullOrEmpty($WebServiceError)) {
			try {
				global:Write-LogEntry -Value "Connecting to the ConfigMgr WebService using URL - $URL" -Severity 1
				# Construct new web service proxy
				$WebService = New-WebServiceProxy -Uri $URL -ErrorAction Stop
				# Upatte WebService info			
				$WebServiceIntro = ($WebServicedetails.ParsedHtml.body.getElementsByClassName('intro') | Select-Object -ExpandProperty InnerText)
				if ($WebServiceIntro -like "*(v*)*") {
					# Legacy Web Service 
					$WebServiceBuild = $WebServiceIntro.Split("(")[1].TrimEnd(")")
				} else {
					# Web Service 1.5.0 onwards
					$WebServiceBuild = $WebService.GetCWVersion()
				}
				global:Write-LogEntry -Value "WebService status version - $WebServiceBuild" -Severity 1
				$WebServiceVersion.Text = $WebServiceBuild
				global:Write-LogEntry -Value "WebService status code - $($WebServiceDetails.StatusCode)" -Severity 1
				$WebServiceStatusCode.Text = $WebServiceDetails.StatusCode
				global:Write-LogEntry -Value "WebService status description - $($WebServiceDetails.StatusDescription)" -Severity 1
				$WebServiceStatusDescription.Text = [string]$WebServiceDetails.StatusDescription
			} catch [System.Exception] {
				global:Write-LogEntry -Value "Errors occured while communicating with the ConfigMgr WebService. Error message: $($_.Exception.Message)" -Severity 3
			}
		} else {
			global:Write-LogEntry -Value "WebService status code - $($WebServiceError.Response.StatusCode.Value__)" -Severity 1
			$WebServiceStatusCode.Text = $WebServiceError.Response.StatusCode.Value__
			global:Write-LogEntry -Value "WebService status description - $($WebServiceError.Response.StatusDescription)" -Severity 1
			$WebServiceStatusDescription.Text = $WebServiceError.Response.StatusDescription
		}
		
		# Call ConfigMgr WebService for a list of packages
		try {
			$WebServiceDriverPackages = $WebService.GetCMPackage($SecretKeyValue, "Driver") | Sort-Object PackageName
			$WebServiceBIOSPackages = $WebService.GetCMPackage($SecretKeyValue, "BIOS") | Sort-Object PackageName
			
			if (($WebServiceDriverPackages.Count -gt 0) -or ($WebServiceBIOSPackages.Count -gt 0)) {
				$DriverPackageCount.Text = $WebServiceDriverPackages.Count
				global:Write-LogEntry -Value "Retrieved a total of $($WebServiceDriverPackages.Count) driver packages from web service" -Severity 1
				
				foreach ($Package in $WebServiceDriverPackages) {
					$WebServiceDataGrid.Rows.Add($Package.PackageName, $Package.PackageVersion, $Package.PackageID)
				}
				global:Write-LogEntry -Value "Retrieved a total of $($WebServiceBIOSPackages.Count) BIOS packages from web service" -Severity 1
				$BIOSPackageCount.Text = $WebServiceBIOSPackages.Count
				
				foreach ($Package in $WebServiceBIOSPackages) {
					$WebServiceDataGrid.Rows.Add($Package.PackageName, $Package.PackageVersion, $Package.PackageID)
				}
			} else {
				global:Write-LogEntry -Value "The ConfigMgr Webservice returned 0 packages. Please ensure that you have added packages and you are using the correct secret key." -Severity 1
			}
		} catch [System.Exception] {
			global:Write-LogEntry -Value "An error occured while calling ConfigMgr WebService for a list of available packages. Error message: $($_.Exception.Message)" -Severity 3
		}
	}
	
	function Select-KnownModels {
		param (
			[parameter(Mandatory = $true)]
			[String[]][ValidateNotNullOrEmpty()]
			[String]$SearchMake
		)
		
		switch ($SearchMake) {
			"Dell" {
				$SearchList = $DellKnownProducts
			}
			"Hewlett-Packard" {
				$SearchList = $HPKnownProducts
			}
			"Lenovo" {
				$SearchList = $LenovoKnownProducts
			}
			"Microsoft"{
				$SearchList = $MicrosoftKnownProducts
			}
		}
		
		$XMLDownloadStatus.Text = "Selecting models known in WMI"
		
		for ($Row = 0; $Row -lt $MakeModelDataGrid.RowCount; $Row++) {
			$MakeModelDataGrid.rows[$row].Selected = $false
			if ($MakeModelDataGrid.Rows[$Row].Cells[1].Value -match $SearchMake) {
				if ($SearchMake -ne "Hewlett-Packard") {
					if ($SearchList -contains $MakeModelDataGrid.Rows[$Row].Cells[2].Value) {
						global:Write-LogEntry -Value "Info: Selecting known model $($MakeModelDataGrid.Rows[$Row].Cells[2].Value)" -Severity 1
						$MakeModelDataGrid.Rows[$Row].Selected = $true
						$MakeModelDataGrid.Rows[$Row].Cells[0].Value = $true
						$MakeModelDataGrid.Rows[$Row].Cells[5].Value = [System.Drawing.Image]::FromFile($CheckIcon)
					} elseif ($MakeModelDataGrid.Rows[$Row].Cells[5].Value -ne $CheckIcon) {
						$MakeModelDataGrid.Rows[$Row].Cells[5].Value = [System.Drawing.Image]::FromFile($UnCheckedIcon)
					}
				} else {
					foreach ($ListedModel in $SearchList) {
						if ($MakeModelDataGrid.Rows[$Row].Cells[2].Value -like "*$ListedModel*") {
							global:Write-LogEntry -Value "Info: Selecting known model $($MakeModelDataGrid.Rows[$Row].Cells[2].Value)" -Severity 1
							$MakeModelDataGrid.Rows[$Row].Selected = $true
							$MakeModelDataGrid.Rows[$Row].Cells[0].Value = $true
							$MakeModelDataGrid.Rows[$Row].Cells[5].Value = [System.Drawing.Image]::FromFile($CheckIcon)
						} elseif ($MakeModelDataGrid.Rows[$Row].Cells[5].Value -ne $CheckIcon) {
							$MakeModelDataGrid.Rows[$Row].Cells[5].Value = [System.Drawing.Image]::FromFile($UnCheckedIcon)
						}
					}
					
				}
			}
		}
		$MakeModelDataGrid.Sort($MakeModelDataGrid.Columns[5], [System.ComponentModel.ListSortDirection]::Descending)
	}
	
	function Set-RegPreferences {
		# Establish Registry Settings
		$global:RegistryPath = "HKLM:\SOFTWARE\MSEndpointMgr\DriverAutomationTool"
		if (-not (Test-Path -Path $global:RegistryPath)) {
			global:Write-LogEntry -Value "======== CREATING REGISTRY ENTRIES ========" -Severity 1
			New-Item -Path $global:RegistryPath -Force
			New-ItemProperty -Path $global:RegistryPath -Name "CommonOptionsVisible" -Value $true -PropertyType "Dword"
			New-ItemProperty -Path $global:RegistryPath -Name "ConfigMgrPkgOptionsVisible" -Value $true -PropertyType "Dword"
			New-ItemProperty -Path $global:RegistryPath -Name "ConfigMgrWebSvcVisible" -Value $true -PropertyType "Dword"
			New-ItemProperty -Path $global:RegistryPath -Name "CustomPkgVisible" -Value $true -PropertyType "Dword"
			New-ItemProperty -Path $global:RegistryPath -Name "MDTSettingsVisible" -Value $true -PropertyType "Dword"
		} else {
			# Lock tabs and controls
			$RegistryValues = (Get-ItemProperty -Path $global:RegistryPath)
			if ($RegistryValues.CommonOptionsVisible -eq $false) {
				$HideCommonSettings.Checked = $true
				$SelectionTabs.TabPages.Remove($SettingsTab)
			}
			if ($RegistryValues.ConfigMgrPkgOptionsVisible -eq $false) {
				$HideConfigPkgMgmt.Checked = $true
				$SelectionTabs.TabPages.Remove($ConfigMgrDriverTab)
			} elseif (($RegistryValues.ConfigMgrPkgOptionsVisible -eq $true) -and ($SelectionTabs.TabPages.Contains($ConfigMgrDriverTab) -ne $true)) {
				$HideConfigPkgMgmt.Checked = $false
				$SelectionTabs.TabPages.Add($ConfigMgrDriverTab)
			}
			if ($RegistryValues.ConfigMgrWebSVCVisible -eq $false) {
				$HideWebService.Checked = $true
				$SelectionTabs.TabPages.Remove($ConfigWSDiagTab)
			} elseif (($RegistryValues.ConfigMgrWebSVCVisible -eq $true) -and ($SelectionTabs.TabPages.Contains($ConfigWSDiagTab) -ne $true)) {
				$HideWebService.Checked = $false
				$SelectionTabs.TabPages.Add($ConfigWSDiagTab)
			}
			if ($RegistryValues.CustomPkgVisible -eq $false) {
				$HideCustomCreation.Checked = $true
				$SelectionTabs.TabPages.Remove($CustPkgTab)
			} elseif (($RegistryValues.CustomPkgVisible -eq $true) -and ($SelectionTabs.TabPages.Contains($CustPkgTab) -ne $true)) {
				$HideCustomCreation.Checked = $false
				$SelectionTabs.TabPages.Add($CustPkgTab)
			}
			if ($RegistryValues.MDTSettingsVisible -eq $false) {
				$HideMDT.Checked = $true
				$SelectionTabs.TabPages.Remove($MDTTab)
			} elseif (($RegistryValues.MDTSettingsVisible -eq $true) -and ($SelectionTabs.TabPages.Contains($MDTTab) -ne $true)) {
				$HideMDT.Checked = $false
				$SelectionTabs.TabPages.Add($MDTTab)
			}
		}
	}
	
	function Set-AdminControl {
		param (
			[parameter(Mandatory = $false)]
			[string]$TabValue,
			[parameter(Mandatory = $true)]
			[boolean]$CheckedValue
		)
		if (-not ([string]::IsNullOrEmpty($TabValue))) {
			switch ($TabValue) {
				"SettingsTab" {
					$TabValue = "CommonOptionsVisible"
				}
				"ConfigMgrDriverTab" {
					$TabValue = "ConfigMgrPkgOptionsVisible"
				}
				"ConfigMgrWebSVCVisible" {
					$TabValue = "ConfigMgrWebSvcVisible"
				}
				"CustPkgTab" {
					$TabValue = "CustomPkgVisible"
				}
				"MDTSettingsVisible" {
					$TabValue = "MDTSettingsVisible"
				}
			}
			If ($CheckedValue -eq $true) {
				Set-ItemProperty -Path $global:RegistryPath -Name $TabValue -Value $false
			} else {
				Set-ItemProperty -Path $global:RegistryPath -Name $TabValue -Value $true
			}
			Set-RegPreferences
		}
	}
	
	function Update-OSModelSuppport {
		if ($OSComboBox.SelectedItem -eq "Windows 10") {
			$DellCheckBox.Enabled = $true
			if ($global:LenovoDisable -eq $false) {
				$LenovoCheckBox.Enabled = $true
			}
			if ($DellCheckBox.Checked -ne $true) {
				$DellCheckBox.Checked = $false
			}
			if ($global:LenovoDisable -eq $false) {
				if ($LenovoCheckBox.Checked -ne $true) {
					$LenovoCheckBox.Checked = $false
				}
			}
			$MicrosoftCheckBox.Enabled = $false
			$MicrosoftCheckBox.Checked = $false
			$HPCheckBox.Enabled = $false
			$HPCheckBox.Checked = $false
			
		} elseif ($OSComboBox.SelectedItem -like "Windows 10 *") {
			$DellCheckBox.Enabled = $false
			$HPCheckBox.Enabled = $true
			$DellCheckBox.Checked = $false
			if ($DownloadComboBox.SelectedItem -ne "BIOS") {
				$MicrosoftCheckBox.Enabled = $true
				if ($MicrosoftCheckBox.Checked -eq $true) {
					# Cater for already checked tickbox
				} else {
					$MicrosoftCheckBox.Checked = $false
				}
			}
			
			if ($HPCheckBox.Checked -eq $true) {
				# Cater for already checked tickbox
			} else {
				$HPCheckBox.Checked = $false
			}
			if ($global:LenovoDisable -eq $false) {
				$LenovoCheckBox.Enabled = $true
				if ($LenovoCheckBox.Checked -eq $true) {
					# Cater for already checked tickbox
				} else {
					$LenovoCheckBox.Checked = $false
				}
			}
		} else {
			$DellCheckBox.Enabled = $true
			$HPCheckBox.Enabled = $true
			$MicrosoftCheckBox.Enabled = $false
			if ($DellCheckBox.Checked -eq $true) {
				# Cater for already checked tickbox
			} else {
				$DellCheckBox.Checked = $false
			}
			if ($MicrosoftCheckBox.Checked -eq $true) {
				# Cater for already checked tickbox
			} else {
				$MicrosoftCheckBox.Checked = $false
			}
			if ($HPCheckBox.Checked -eq $true) {
				# Cater for already checked tickbox
			} else {
				$HPCheckBox.Checked = $false
			}
			if ($global:LenovoDisable -eq $false) {
				$LenovoCheckBox.Enabled = $true
				if ($LenovoCheckBox.Checked -eq $true) {
					# Cater for already checked tickbox
				} else {
					$LenovoCheckBox.Checked = $false
				}
			}
		}
		Enable-FindModels
	}
	
	function Search-ModelList {
		param (
			[parameter(Mandatory = $false)]
			[boolean]$FindAndSelect = $false
		)
		# Highlight search results for Models
		[int]$ModelSearchResults = 0
		if (-not ([string]::IsNullOrEmpty($ModelSearchText.Text))) {
			$MakeModelDataGrid.ClearSelection()
			$XMLLoading.Visible = $true
			$XMLLoadingLabel.Visible = $true
			$XMLLoadingLabel.Text = "Searching model listings..."
			global:Write-LogEntry -Value "======== Searching For Model : $($ModelSearchText.Text) ========" -Severity 1
			for ($Row = 0; $Row -lt $MakeModelDataGrid.RowCount; $Row++) {
				if ($MakeModelDataGrid.Rows[$Row].Cells[2].Value -match $ModelSearchText.Text) {
					global:Write-LogEntry -Value "Model found: $($MakeModelDataGrid.Rows[$Row].Cells[2].Value)" -Severity 1
					if ($FindAndSelect -eq $true) {
						$MakeModelDataGrid.Rows[$Row].Cells[0].Value = $true
					}
					$MakeModelDataGrid.Rows[$Row].Selected = $true
					$MakeModelDataGrid.Rows[$Row].Cells[6].Value = "Match"
					$ModelSearchResults++
				} else {
					$MakeModelDataGrid.Rows[$Row].Cells[6].Value = $null
				}
			}
			$MakeModelDataGrid.Sort($MakeModelDataGrid.Columns[6], [System.ComponentModel.ListSortDirection]::Descending)
			$MakeModelDataGrid.FirstDisplayedScrollingRowIndex = 0
			$XMLDownloadStatus.Text = "Found ($ModelSearchResults) matches"
			$XMLDownloadStatus.Visible = $true
			$ModelResults.Text = "Found ($ModelSearchResults) matches"
			Start-Sleep -Seconds 3
			$XMLLoading.Visible = $false
			$XMLLoadingLabel.Visible = $false
			$XMLDownloadStatus.Visible = $false
		} else {
			global:Write-LogEntry -Value "Info: Please enter text to search for into the model search field" -Severity 2
		}
	}
	
	function Search-HPDriverList {
		if (([string]$HPSearchText.Text::IsNullOrEmpty) -ne $true) {
			#Highlight search results for HP catalogue
			[int]$HPSearchResults = 0
			$HPSoftpaqDataGrid.ClearSelection()
			global:Write-LogEntry -Value "======== Searching For HP Driver : $($HPSearchText.Text) ========" -Severity 1
			for ($Row = 0; $Row -lt $HPSoftpaqDataGrid.RowCount; $Row++) {
				if ($HPSoftpaqDataGrid.Rows[$Row].Cells[2].Value -match $HPSearchText.Text) {
					global:Write-LogEntry -Value "Driver found: $($HPSoftpaqDataGrid.Rows[$Row].Cells[2].Value)" -Severity 1
					$HPSoftpaqDataGrid.Rows[$Row].Selected = $true
					$HPSoftpaqDataGrid.Rows[$Row].Cells[10].Value = "Match"
					$HPSearchResults++
				} else {
					$HPSoftpaqDataGrid.Rows[$Row].Cells[10].Value = $null
				}
			}
			$HPSoftpaqDataGrid.Sort($HPSoftpaqDataGrid.Columns[10], [System.ComponentModel.ListSortDirection]::Descending)
			$HPSoftpaqDataGrid.FirstDisplayedScrollingRowIndex = 0
			$SoftpaqResults.Text = "Found ($HPSearchResults) matches"
		} else {
			global:Write-LogEntry -Value "Error: Search text criteria required" -Severity 2
		}
	}
	
	function Find-AvailableModels {
		if (($global:ConfigMgrValidation -ne $true) -and ($PlatformComboBox.Text -match "ConfigMgr")) {
			Connect-ConfigMgr
		}
		if (($global:ProxySettingsSet -ne $true) -and ($UseProxyServerCheckbox.Checked -eq $true)) {
			Confirm-ProxyAccess -ProxyServer $ProxyServerInput.Text -UserName $ProxyUserInput.Text -Password $ProxyPswdInput.Text -URL "https://www.MSEndpointMgr.com"
		}
		$MakeModelDataGrid.Rows.Clear()
		Update-ModeList $SiteServerInput.Text $SiteCodeText.Text
		Start-Sleep -Seconds 2
		[int]$ModelCount = $MakeModelDataGrid.Rows.Count
		if ($ModelCount -gt 0) {
			$SelectAll.Enabled = $true
			$ClearModelSelection.Enabled = $true
		}
		$ModelResults.Text = "Found ($ModelCount) models"
	}
	
	function Enable-FindModels {
		If (($LenovoCheckBox.Checked -eq $false) -and ($DellCheckBox.Checked -eq $false) -and ($MicrosoftCheckBox.Checked -eq $false) -and ($HPCheckBox.Checked -eq $false)) {
			$FindModelsButton.Enabled = $false
		} else {
			$FindModelsButton.Enabled = $true
		}
	}
	
	function Update-PlatformOptions {
		$CleanUnusedCheckBox.Enabled = $false
		if ($PlatformComboBox.SelectedItem -eq "MDT") {
			$DownloadComboBox.Text = "Drivers"
			$DownloadComboBox.Enabled = $false
			$RemoveLegacyDriverCheckbox.Enabled = $false
			$RemoveLegacyBIOSCheckbox.Enabled = $false
			Set-ConfigMgrOptions -OptionsEnabled $false
			Set-MDTOptions -OptionsEnabled $true
			if ([string]::IsNullOrEmpty($MDTScriptTextBox.Text)) {
				$SelectionTabs.SelectedTab = $MDTTab
			}
		} elseif ($PlatformComboBox.SelectedItem -match "Both") {
			$DownloadComboBox.Text = "Drivers"
			$DownloadComboBox.Enabled = $false
			$RemoveLegacyDriverCheckbox.Enabled = $true
			$RemoveLegacyBIOSCheckbox.Enabled = $true
			Set-MDTOptions -OptionsEnabled $true
			Set-ConfigMgrOptions -OptionsEnabled $true
		} elseif ($PlatformComboBox.SelectedItem -match "Standard") {
			$DownloadComboBox.Enabled = $true
			$RemoveLegacyDriverCheckbox.Enabled = $true
			$RemoveLegacyBIOSCheckbox.Enabled = $true
			Set-MDTOptions -OptionsEnabled $false
			Set-ConfigMgrOptions -OptionsEnabled $true
		} elseif ($PlatformComboBox.SelectedItem -match "Driver") {
			$DownloadComboBox.Enabled = $true
			$CleanUnusedCheckBox.Enabled = $true
			$RemoveLegacyDriverCheckbox.Enabled = $true
			$RemoveLegacyBIOSCheckbox.Enabled = $false
			Set-MDTOptions -OptionsEnabled $false
			Set-ConfigMgrOptions -OptionsEnabled $true
		} elseif ($PlatformComboBox.SelectedItem -match "XML") {
			$DownloadComboBox.Text = "Drivers"
			$DownloadComboBox.Enabled = $false
			$RemoveLegacyDriverCheckbox.Enabled = $true
			$RemoveLegacyBIOSCheckbox.Enabled = $true
			Set-MDTOptions -OptionsEnabled $false
			Set-ConfigMgrOptions -OptionsEnabled $false
		} elseif ($PlatformComboBox.SelectedItem -match "Download") {
			$DownloadComboBox.Enabled = $true
			$RemoveLegacyDriverCheckbox.Enabled = $true
			$RemoveLegacyBIOSCheckbox.Enabled = $true
			Set-MDTOptions -OptionsEnabled $false
			Set-ConfigMgrOptions -OptionsEnabled $false
		} elseif ($PlatformComboBox.SelectedItem -match "Intune") {
			#$SelectionTabs.TabPages.Insert(3, $IntuneTab)
		}
		$StartDownloadButton.Enabled = $true
	}
	
	function Set-7ZipOptions {
		
		# Check if 7ZIP is installed
		$7ZipFileManagerKey = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\7zFM.exe"
		global:Write-LogEntry -Value "======== Checking for 7-Zip Installation ========" -Severity 1
		if ([boolean](Get-ItemProperty -Path $7ZipFileManagerKey -ErrorAction SilentlyContinue)) {
			global:Write-LogEntry -Value "Feature: 7-Zip discovered, enabling support" -Severity 1
			$CompressionType.Enabled = $true
			$global:7ZIPLocation = Get-ItemProperty -Path $7ZipFileManagerKey | Select-Object -ExpandProperty Path
			if ([string]::IsNullOrEmpty($CompressionType.SelectedItem)) {
				global:Write-LogEntry -Value "Feature: Defaulting zip compression to 7-Zip format" -Severity 1
				$CompressionType.SelectedItem = "7-Zip"
			}
		} else {
			global:Write-LogEntry -Value "Feature: 7-Zip not found, support disabled" -Severity 1
			$global:7ZIPLocation = $null
		}
	}
	
	function Write-XMLLogicPackage {
		param
		(
			[parameter(Mandatory = $false, HelpMessage = "Driver or BIOS packaging required")]
			[ValidateSet("Drivers", "BIOS", "SoftPaqs")]
			[string]$XMLType,
			[switch]$Distribute
		)
		
		Set-Location -Path $global:TempDirectory
		
		if ($CMPackages.Count -gt 0) {
			global:Write-LogEntry -Value "======== MSEndpointMgr XML Logic Package ========" -Severity 1
		}
		
		# Set package path
		$LogicPackagePath = Join-Path -Path $PackagePathTextBox.Text -ChildPath "MSEndpointMgr\XML Logic Package"
		if ((Test-Path -Path $LogicPackagePath) -eq $false) {
			global:Write-LogEntry -Value "XML Logic Package: Creating package folder" -Severity 1
			New-Item -Path $LogicPackagePath -ItemType Dir
		}
		$LogicFilePath = Join-Path -Path $LogicPackagePath -ChildPath "$XMLFileName"
		
		Set-Location -Path ($SiteCode + ":")
		
		if ($Distribute -ne $true) {
			# Obtain list of MDM / MBM packages from Configuration Manager and sef file name
			switch ($XMLType) {
				"Drivers" {
					$CMPackages = Get-CMPackage -Fast | Where-Object {
						$_.Name -like "*Drivers -*" -or $_.Name -like "Driver Fallback*"
					} | Select-Object Name, PackageID, Description, Manufacturer, Version, SourceDate, PkgSourcePath
					$XMLFileName = "DriverPackages.xml"
				}
				"BIOS" {
					$CMPackages = Get-CMPackage -Fast | Where-Object {
						$_.Name -like "*BIOS -*"
					} | Select-Object Name, PackageID, Description, Manufacturer, Version, SourceDate, PkgSourcePath
					$XMLFileName = "BIOSPackages.xml"
				}
				"SoftPaqs" {
					$CMPackages = Get-CMPackage -Fast | Where-Object {
						$_.Name -like "SoftPaq -*"
					} | Select-Object Name, PackageID, Description, Manufacturer, Version, SourceDate, PkgSourcePath
					$XMLFileName = "SoftPaqPackages.xml"
				}
			}
			
			Set-Location -Path $global:TempDirectory
			
			# Set XML Structure
			$XmlWriter = New-Object System.XML.XmlTextWriter($LogicFilePath, $Null)
			$xmlWriter.Formatting = 'Indented'
			$xmlWriter.Indentation = 1
			$XmlWriter.IndentChar = "`t"
			$xmlWriter.WriteStartDocument()
			$XmlWriter.WriteComment('Created with the MSEndpointMgr Driver Automation Tool - DO NOT DELETE')
			$xmlWriter.WriteProcessingInstruction("xml-stylesheet", "type='text/xsl' href='style.xsl'")
			
			# Write Initial Header Comments
			$xmlWriter.WriteStartElement('ArrayOfCMPackage')
			$XmlWriter.WriteAttributeString('xmlns:xsd', "http://www.w3.org/2001/XMLSchema")
			$XmlWriter.WriteAttributeString('xmlns:xsi', "http://www.w3.org/2001/XMLSchema-Instance")
			$XmlWriter.WriteAttributeString('xmlns', "http://www.msendpointmgr.com")
			
			$XMLBody = {
				# Write CM Package  Header Comments
				$xmlWriter.WriteStartElement('CMPackage')
				
				# Export Model Details 
				global:Write-LogEntry -Value "XML Logic Package: Adding package $($Package.PackageID) to XML logic file" -Severity 1 -SkipGuiLog $true
				global:Write-LogEntry -Value "XML Logic Package: Added $(($Package.PackageID).count) package(s) to XML logic file" -Severity 1 -SkipGuiLog $true
				
				$xmlWriter.WriteElementString('PackageName', $Package.Name)
				$xmlWriter.WriteElementString('PackageID', $Package.PackageID)
				$xmlWriter.WriteElementString('PackageDescription', $Package.Description)
				$xmlWriter.WriteElementString('PackageManufacturer', $Package.Manufacturer)
				$xmlWriter.WriteElementString('PackageVersion', $Package.Version)
				$xmlWriter.WriteElementString('PackageCreated', $Package.SourceDate)
			}
			
			switch ($XMLType) {
				"SoftPaqs" {
					foreach ($Package in $CMPackages) {
						if (Test-Path -Path $($Package.PkgSourcePath)) {
							[xml]$SoftPaqInfo = (Get-Content -Path (Join-Path -Path $($Package.PkgSourcePath) -ChildPath "Setup.xml") -Raw)
							$BaseBoardSupport = [string]($SoftPaqInfo.Settings.Models.Baseboards)
							$SetupFile = [string]($SoftPaqInfo.Settings.Installer.SetupFile)
							$SetupSwitches = [string]($SoftPaqInfo.Settings.Installer.Switches)
							$ProgramName = [string]($SoftPaqInfo.Settings.Installer.ProgramName)
							
							if ((-not ([string]::IsNullOrEmpty($BaseBoardSupport))) -and (-not ([string]::IsNullOrEmpty($ProgramName)))) {
								# Write XML Addition
								& $XMLBody
								$xmlWriter.WriteElementString('SupportedOSes', $((($Package.Description).Split("(") | Select-Object -Last 1).TrimEnd(")")))
								$XmlWriter.WriteElementString('SupportedBaseBoards', $BaseBoardSupport)
								$XmlWriter.WriteElementString('ProgramName', $ProgramName)
								$XmlWriter.WriteElementString('SetupFile', $SetupFile)
								$XmlWriter.WriteElementString('SetupSwitches', $SetupSwitches)
								$xmlWriter.WriteEndElement()
							}
						}
					}
				}
				"BIOS" {
					foreach ($Package in $CMPackages) {
						# Write XML Addition
						& $XMLBody
						$xmlWriter.WriteEndElement()
					}
				}
				"Drivers" {
					foreach ($Package in $CMPackages) {
						# Write XML Addition
						& $XMLBody
						$xmlWriter.WriteEndElement()
					}
				}
			}
			
			# Save XML Document
			$xmlWriter.WriteEndDocument()
			$xmlWriter.Flush()
			$xmlWriter.Close()
			
		} else {
		
			# Create Configuration Manager package containing XML and distribute
			$XMLPackageName = "MSEndpointMgr XML Logic Package"
			$XMLPackageVersion = Get-Date -Format yyyydd
			
			Set-Location -Path ($SiteCode + ":")
			if ([boolean](Get-CMPackage -Name $XMLPackageName -fast) -eq $false) {
				# Create XML logic package
				try {
					global:Write-LogEntry -Value "XML Logic Package: Creating XML logic file in location - $LogicFilePath" -Severity 1
					New-CMPackage -Name "$XMLPackageName" -path "$LogicPackagePath" -Manufacturer "MSEndpointMgr" -Description "Package containing XML formatted package information for modern driver and bios management" -Version $XMLPackageVersion
					Start-Sleep -Seconds 5
					$XMLPackageID = Get-CMPackage -Name $XMLPackageName -Fast | Select-Object -ExpandProperty PackageID
					global:Write-LogEntry -Value "XML Logic Package: Package $($XMLPackageID) created successfully" -Severity 1
					global:Write-LogEntry -Value "XML Logic Package: Distributing package to selected distribution points" -Severity 1
					if ($EnableBinaryDifCheckBox.Checked -eq $true) {
						global:Write-LogEntry -Value "XML Logic Package: Enabling Binary Delta Replication" -Severity 1
						Set-CMPackage -ID $XMLPackageID -EnableBinaryDeltaReplication $true -Priority $DistributionPriorityCombo.Text
					}
					Distribute-Content -Product $XMLPackageName -PackageID $XMLPackageID -ImportInto "Standard"
				} catch [System.Exception] {
					Write-Warning -Message "Error: $($_.Exception.Message)"
				}
			} else {
				global:Write-LogEntry -Value "XML Logic Package: Updating XML package $(Get-CMPackage -Name $XMLPackageName -Fast | Select-Object -ExpandProperty PackageID) on distribution points" -Severity 1
				Get-CMPackage -Name $XMLPackageName -Fast | Invoke-CMContentRedistribution
			}
		}
		
		Set-Location -Path $global:TempDirectory
	}
	
	function New-DriverPackage {
		param
		(
			$Make,
			$DriverExtractDest,
			$Architecture,
			$DriverPackageDest,
			$ZipCompression,
			$ZipType
		)
		
		try {
			if ($ZipCompression -eq $true) {
				global:Write-LogEntry -Value "$($Product): Zip compression is $($ZipCompressionCheckBox.Checked)" -Severity 1
				global:Write-LogEntry -Value "$($Product): Zip compression type is $($CompressionType.Text)" -Severity 1
				if ($ZipType -eq "7-Zip") {
					global:Write-LogEntry -Value "DriverPackage: Compressing files in $DriverExtractDest" -Severity 1
					global:Write-LogEntry -Value "DriverPackage: Creating self expanding 7-Zip exe file in the following location - $(Join-Path -path $DriverPackageDest -ChildPath 'DriverPackage.exe')" -Severity 1
					$7ZipArgs = "a -sfx7z.sfx DriverPackage.exe -r " + ' "' + $DriverExtractDest + '"'
					global:Write-LogEntry -Value "DriverPackage: 7-Zip location is $(Join-Path -Path $global:7ZIPLocation -ChildPath "7z.exe") " -Severity 1
					global:Write-LogEntry -Value "DriverPackage: 7-Zip arguments are $7ZipArgs" -Severity 1
					global:Write-LogEntry -Value "DriverPackage: Creating temporary PS drive for 7-Zip" -Severity 1
					New-PSDrive -Name "Drivers" -PSProvider FileSystem -Root $DriverExtractDest
					Set-Location -Path "Drivers:\"
					global:Write-LogEntry -Value "DriverPackage: Invoking 7Zip appliction to package content" -Severity 1
					$7ZipProcess = Start-Process (Join-Path -Path $global:7ZIPLocation -ChildPath "7z.exe") -ArgumentList $7ZipArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput .\7zipAction.txt
					if ($7ZipProcess.ExitCode -eq 1) {
						global:Write-LogEntry -Value "Error: Issues occrured during 7Zip compression progress. Review the 7zipAction.txt log." -Severity 2
					} else {
						if ([boolean](Get-ChildItem -Path $DriverExtractDest -Filter "DriverPackage.exe")) {
							global:Write-LogEntry -Value "DriverPackage: Self-extracting 7-Zip driver package created" -Severity 1
							global:Write-LogEntry -Value "DriverPackage: Copying DriverPackage.exe to $($DriverPackageDest)" -Severity 1
							Get-ChildItem -Path $DriverExtractDest -Filter "DriverPackage.exe" | Copy-Item -Destination "$DriverPackageDest" -Force
							Return $true
						} else {
							global:Write-LogEntry -Value "Error: Failed to locate DriverPackage.exe. Please review the 7Zip log file located in $DriverExtractDest" -Severity 1
							Return $false
						}
					}
					Set-Location -Path $global:TempDirectory
				} else {
					global:Write-LogEntry -Value "DriverPackage: Compressing files in $DriverExtractDest" -Severity 1
					global:Write-LogEntry -Value "DriverPackage: Creating zip file in the following location - $(Join-Path -path $DriverPackageDest -ChildPath 'DriverPackage.zip')" -Severity 1
					Compress-Archive -Path $DriverExtractDest -DestinationPath (Join-Path -path $DriverPackageDest -ChildPath "DriverPackage.zip") -CompressionLevel Fastest -Force
					if ([boolean](Get-ChildItem -Path (Join-Path -path $DriverPackageDest -ChildPath "DriverPackage.zip"))) {
						Return $true
					} else {
						Return $false
					}
				}
				
			} else {
				if ($Make -eq "Dell") {
					$CopyFileCount = (Get-ChildItem -Path "$DriverExtractDest" -File).Count
					Copy-Item -Path $(Get-ChildItem -Path "$DriverExtractDest" -Recurse -Directory | Where-Object {
							$_.Name -eq "$Architecture"
						} | Select-Object -First 1).FullName -Destination "$DriverPackageDest" -Container -Recurse -Force
				} else {
					Get-ChildItem -Path "$DriverExtractDest" | Copy-Item -Destination "$DriverPackageDest" -Container -Recurse -Force
				}
				global:Write-LogEntry -Value "DriverPackage: Drivers copied to - $DriverPackageDest" -Severity 1
				Return $true
			}
		} catch [System.Exception] {
			Write-Warning -Message "Error: $($_.Exception.Message)"
			Write-Warning -Message "Error: Check security permissions and specified path"
			Return $false
		}
	}
	
	function Get-HPSoftPaqDrivers {
		
		# Clear datagrid prior to search
		$HPSoftpaqDataGrid.Rows.Clear()
		Start-Sleep -Milliseconds 100
		
		try {
			
			global:Write-LogEntry -Value "======== Updating HP SoftPaq List ========" -Severity 1
			
			# Get OS Version
			$OSVersion = [string]((($OSComboBox).Text).Split(' ')[2]).Trim()
			
			# Set Configuration Manager values
			if ($PlatformComboBox.Text -match "ConfigMgr") {
				Set-Location -Path ($SiteCode + ":")
				$HPModelSoftPaqs = Get-CMPackage -Fast | Where-Object {
					$_.Name -like "SoftPaq -*"
				} | Select-Object -Property Name, Version
				global:Write-LogEntry -Value "Info: Discovered $($HPModelSoftPaqs.Count) SoftPaqs already created in ConfigMgr" -Severity 1
				Set-Location -Path $global:TempDirectory
			}
			
			# Obtain HP baseboard value for filtering
			if ($global:HPModelSoftPaqs -eq $null) {
				[xml]$global:HPModelXML = Get-Content -Path $(Join-Path -Path $global:TempDirectory -ChildPath $HPXMLFile) -Raw
				# Set XML Object
				$global:HPModelXML.GetType().FullName
				$global:HPModelSoftPaqs = $global:HPModelXML.NewDataSet.HPClientDriverPackCatalog.ProductOSDriverPackList.ProductOSDriverPack
			}
			
			global:Write-LogEntry -Value "SoftPaq: HP XML file location is $($global:TempDirectory)\$HPXMLFile)" -Severity 1
			$HPSoftpaqGridNotice.Text = "Running Search Query"
			if ((-not ([string]::IsNullOrEmpty($HPCatalogModels.Text))) -and $HPCatalogModels.Text -notmatch "Generic") {
				# Use specific model search
				$HPSoftPaqBaseBoard = $global:HPModelSoftPaqs | Where-Object {
					$_.SystemName -match $HPCatalogModels.text
				} | Select-Object -ExpandProperty SystemID -Unique
				$HPSoftpaqGridStatus.Text = "Searching for SoftPaqs supporting HP baseboard value(s) $HPSoftPaqBaseBoard"
				global:Write-LogEntry -Value "SoftPaq: Searching based on baseboard values - `"$HPSoftPaqBaseBoard`"" -Severity 1
			} else {
				# Use generic search
				$HPCatalogModels.Text = "All Generic Downloads"
				$HPSoftPaqBaseBoard = "Hewlett-Packard"
				$HPSoftpaqGridStatus.Text = "Searching for all generic HP SoftPaqs"
				global:Write-LogEntry -Value "SoftPaq: Displaying all generic SoftPaq matches" -Severity 1
			}
			
			# Notify user of running search
			$HPSoftPaqGridPopup.Visible = $true
			$HPSoftpaqGridNotice.Visible = $true
			$HPSoftPaqGridStatus.Visible = $true
			
			# Run query based on HP baseboard value of the selected model
			switch ($HPSoftPaqBaseBoard) {
				"Hewlett-Packard" {
					$global:HPAvailableSoftPaqs = $global:HPSoftPaqXML.SystemsManagementCatalog.SoftwareDistributionPackage | Where-Object {
						$_.IsInstallable.And.WmiQuery.WQLQuery -match $HPSoftPaqBaseBoard -and $_.InstallableItem.ApplicabilityRules.IsInstalled.And.Or.And.WindowsVersion.MajorVersion -eq "10" -and $_.InstallableItem.ApplicabilityRules.IsInstalled.And.Or.And.RegsZ.Data -eq $OSVersion -and $_.Properties.PublicationState -ne "Expired"
					}
				}
				default {
					if ($HPSoftPaqBaseBoard -match ",") {
						$HPSoftPaqBaseBoard = $HPSoftPaqBaseBoard.Replace(",", " ")
						$HPSoftPaqBaseBoard = $HPSoftPaqBaseBoard.Replace(" ", "|")
					}
					$global:HPAvailableSoftPaqs = $global:HPSoftPaqXML.SystemsManagementCatalog.SoftwareDistributionPackage | Where-Object {
						$_.InstallableItem.ApplicabilityRules.IsInstalled.And.WmiQuery.WQLQuery -match $HPSoftPaqBaseBoard -and $_.InstallableItem.ApplicabilityRules.IsInstalled.And.Or.And.WindowsVersion.MajorVersion -eq "10" -and $_.InstallableItem.ApplicabilityRules.IsInstalled.And.Or.And.RegsZ.Data -eq $OSVersion -and $_.Properties.PublicationState -ne "Expired"
					}
				}
			}
			
			# Select required properties
			$global:HPAvailableSoftPaqs = $global:HPAvailableSoftPaqs | Select-Object -Property @{
				l = "Title"; e = {
					$_.LocalizedProperties.Title
				}
			}, @{
				l = "SoftPaq"; e = {
					$_.UpdateSpecificData.KBArticleID
				}
			}, @{
				l = "Modified"; e = {
					$_.InstallableItem.OriginFile.Modified
				}
			}, @{
				l = "Setup File"; e = {
					$_.InstallableItem.CommandLineInstallerData.Program
				}
			}, @{
				l = "Arguements"; e = {
					$_.InstallableItem.CommandLineInstallerData.Arguments
				}
			}, @{
				l = "Namespace"; e = {
					$_.InstallableItem.ApplicabilityRules.IsInstallable.And.WMIQuery.Namespace | Select-Object -First 1
				}
			}, @{
				l = "WQLQuery"; e = {
					$_.InstallableItem.ApplicabilityRules.IsInstallable.And.WMIQuery.WQLQuery
				}
			}, @{
				l = "Severity"; e = {
					$_.UpdateSpecificData.MsrcSeverity
				}
			}, @{
				l = "URL"; e = {
					$_.InstallableItem.OriginFile.OriginURI
				}
			}, @{
				l = "SupportedBuilds"; e = {
					[string]($_.InstallableItem.ApplicabilityRules.IsInstalled.And.Or.And.RegsZ.Data | Sort-Object -Unique)
				}
			}
			
			# Limit to unique entries
			$global:HPAvailableSoftPaqs = ($global:HPAvailableSoftPaqs | Sort-Object Title -Unique)
			
			# Add matched Softpaq downloads to the HP SoftPaq datagrid
			if ($HPSoftPaqBaseBoard -ne "Hewlett-Packard") {
				global:Write-LogEntry -Value "Info: Adding $($global:HPAvailableSoftPaqs.Count) available SoftPaq downloads for selected model `"$($HPCatalogModels.text)` on Windows 10 $OSVersion" -Severity 1
			} else {
				global:Write-LogEntry -Value "Info: Adding $($global:HPAvailableSoftPaqs.Count) generic SoftPaq downloads for Windows 10 $OSVersion" -Severity 1
			}
			
			foreach ($SoftPaq in $global:HPAvailableSoftPaqs) {
				
				# Version information
				if ([string]$SoftPaq.Title -like "*]*") {
					$HPSoftPaqVersion = ([string]($SoftPaq.Title).Split("[")[1]).TrimEnd("]")
				} else {
					$HPSoftPaqVersion = "Not Available"
				}
				
				# Extract baseboard values from WQLQuery	
				$HPBaseBoardModels = [string]($SoftPaq.WQLQuery | Select-String -Pattern '\%(\w+)\%' -AllMatches | ForEach-Object {
						$_.Matches
					} | Sort-Object -Unique)
				$HPBaseBoardModels = $HPBaseBoardModels.Replace("%", "")
				
				# Set title variable without version info
				$HPSoftPaqTitle = [string](($SoftPaq.Title).TrimEnd("[$HPSoftPaqVersion]")).Trim()
				
				# Set Configuration Manager values
				if ($PlatformComboBox.SelectedItem -match "ConfigMgr") {
					# Select created packages
					foreach ($Package in $HPModelSoftPaqs) {
						#global:Write-LogEntry -Value "Attempting to match $HPSoftPaqTitle and $HPSoftPaqVersion" -Severity 1 -SkipGuiLog $true
						#global:Write-LogEntry -Value "To $($Package.Name) version $($Package.Version) " -Severity 1 -SkipGuiLog $true
						
						if (($Package.Version -eq $HPSoftPaqVersion) -and ($Package.Name -match $HPSoftPaqTitle)) {
							global:Write-LogEntry -Value "Match found with $($Package.Name) $($Package.Version)" -Severity 1 -SkipGuiLog $true
							$HPSoftPaqExists = $true; break
						} else {
							$HPSoftPaqExists = $false
						}
					}
				} else {
					$HPSoftPaqPackageIcon = $null
				}
				if ($HPSoftPaqExists -eq $true) {
					global:Write-LogEntry -Value "Info: SoftPaq $($SoftPaq.Title) package already created, highlighting in UI" -Severity 1 -SkipGuiLog $true
					$HPSoftPaqPackageIcon = [System.Drawing.Image]::FromFile($CheckIcon)
				} else {
					$HPSoftPaqPackageIcon = [System.Drawing.Image]::FromFile($UnCheckedIcon)
				}
				# Add entry to HP data Softpaq datagrid		
				$HPSoftpaqDataGrid.Rows.Add($False, [string]($SoftPaq.Softpaq).ToUpper(), $HPSoftPaqTitle, $HPSoftPaqVersion, [datetime]$SoftPaq.Modified, [string]$SoftPaq.Severity, $HPSoftPaqPackageIcon, [string]$SoftPaq.URL, [string]$SoftPaq.Arguements, $HPBaseBoardModels, [string]$HPSoftPaqExists, [string]$SoftPaq.SupportedBuilds)
			}
			$HPSoftpaqDataGrid.CommitEdit('CurrentCellChange')
			# Wait for last entry
			Start-Sleep -Milliseconds 100
			
			# Flag critical updates
			global:Write-LogEntry -Value "Info: Highlighting critical SoftPaq updates" -Severity 1
			Set-SoftPaqSelections
			Start-Sleep -Milliseconds 250
			
			# Sort datagrid view
			global:Write-LogEntry -Value "Info: Sorting SoftPaqs by date modified" -Severity 1
			$HPSoftpaqDataGrid.Sort($HPSoftpaqDataGrid.Columns[4], [System.ComponentModel.ListSortDirection]::Descending)
			
			# Remove search notification
			$HPSoftpaqGridNotice.Visible = $false
			$HPSoftPaqGridStatus.Visible = $false
			$HPSoftPaqGridPopup.Visible = $false
			
			$SoftpaqResults.Text = "$($HPSoftpaqDataGrid.Rows.Count) items"
			
		} catch [System.Exception] {
			Write-Warning -Message "Error: $($_.Exception.Message)"
		}
	}
	
	function Set-SoftPaqSelections {
		# Obtain current list of SoftPaq packages from Configuration Mananger
		foreach ($SoftPaqRow in $HPSoftpaqDataGrid.rows) {
			if ($SoftPaqRow.Cells[5].Value -match "Critical") {
				$SoftPaqRow.DefaultCellStyle.ForeColor = 'Maroon'
			}
			
			if ($SoftPaqRow.Cells[10].Value -eq $true) {
				$SoftPaqRow.DefaultCellStyle.ForeColor = 'Green'
				$SoftPaqRow.Cells[0].ReadOnly = $true
			}
		}
		#$HPSoftpaqDataGrid.CommitEdit('CurrentCellChange')
	}
	
	function Invoke-RunningLog {
		# Resetting error state
		$ErrorsOccurred.ForeColor = "Green"
		$ErrorsOccurred.Text = "No"
		$JobStatus.Text = "Running"
		
		# Select log tab and
		$SelectionTabs.SelectedTab = $LogTab
		
	}
	
	function Update-DataGrid {
		param
		(
			[parameter(Mandatory = $true)]
			[ValidateNotNullOrEmpty()]
			[ValidateSet("ClearSelection", "SelectAll")]
			[string]$Action,
			[parameter(Mandatory = $true)]
			$GridViewName,
			[parameter(Mandatory = $false)]
			[int]$SortColumn
		)
		
		try {
			# Perform actions on passed through datagrid object depending on the selected switch
			switch ($Action) {
				"ClearSelection" {
					global:Write-LogEntry -Value "Info: Clearing HP Softpaq selections" -Severity 1
					for ($Row = 0; $Row -lt $GridViewName.RowCount; $Row++) {
						if ($GridViewName.Rows[$Row].Cells[0].ReadOnly -ne $true) {
							$GridViewName.Rows[$Row].Cells[0].Value = $false
							$GridViewName.Rows[$Row].Selected = $false
						}
					}
				}
				"SelectAll" {
					global:Write-LogEntry -Value "Info: Selecting all available HP SoftPaqs for current model selection" -Severity 1
					for ($Row = 0; $Row -lt $GridViewName.RowCount; $Row++) {
						if ($GridViewName.Rows[$Row].Cells[0].ReadOnly -ne $true) {
							$GridViewName.Rows[$Row].Cells[0].Value = $true
							$GridViewName.Rows[$Row].Selected = $true
						}
					}
				}
			}
			
			# Sort by column index where available
			if ($SortColumn -ne $null) {
				$GridViewName.Sort($GridViewName.Columns[$SortColumn], [System.ComponentModel.ListSortDirection]::Descending)
			}
			$GridViewName.CommitEdit('CurrentCellChange')
			
		} catch [System.Exception] {
			global:Write-LogEntry -Value "Error: $($_.Exception.Message)" -Severity 2
		}
	}
	
	function Invoke-SoftPaqXML {
		param
		(
			[Parameter(Mandatory = $true)]
			[ValidateSet('ClearSelection', 'SelectAll')]
			[ValidateNotNullOrEmpty()]
			[string]$Action,
			[Parameter(Mandatory = $true)]
			$GridViewName,
			[Parameter(Mandatory = $false)]
			[int]$SortColumn
		)
		
		# Define XML Template
		$PackageTemplate = [xml]@'
	<CMPackage>
		<PackageName>$($Package.PackageName)</PackageName>
		<PackageID>$($Package.PackageID)</PackageID>
		<PackageManufacturer>$($Package.PackageManufacturer)</PackageManufacturer>
		<PackageVersion>$($Package.PackageVersion)</PackageVersion>
		<PackageCreated>$($Package.PackageCreated)</PackageCreated>
		<SupportedOSes>$($Package.SupportedOSes)</SupportedOSes>
		<BaseBoardValues>$($Package.BaseBoardValues)</BaseBoardValues>
	</CMPackage>
'@
		
		$CMPackages = Get-CMPackage -Fast | Where-Object {
			$_.Name -like "Softpaq -"
		}
		
		
		
	}
	
	
	function Remove-Variables {
		Remove-Variable -Name "DellCatalogXML" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "DellModelXML" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "DellModelCabFiles" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "HPModelSoftPaqs" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "HPModelXML" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "HPPlatformXML" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "HPSoftPaqXML" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "HPSoftPaqList" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "LenovoModelDrivers" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "LenovoModelXML" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "LenovoModelType" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "LenovoSystemSKU" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "MDTValidation" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "ConfigMgrValidation" -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name "PreviousDownload" -Scope Global -ErrorAction SilentlyContinue
	}
#endregion Source: Globals.ps1

#Start the application
Main ($CommandLine)

