![SCConfigMgr Driver Auatomation Tool](https://i1.wp.com/msendpointmgr.com/wp-content/uploads/2020/04/MSEndpoingMgrDat.jpg?resize=1024%2C641&ssl=1)

# Driver Automation Tool

Welcome to the new home of the **MSEndpointMgr Driver Automation Tool**.

**If you would like to donate to the development of this tool, then please use the sponsor button at the top of the page.**

**FAQ**

**Q** Can you please add model x to the list

**A** *The manufacturer provides the model listings for Dell, Lenovo and HP. For Microsoft I am manually adding them, so in that instance yes.*

**Scripts, MSIs and downloads contained within are provided with no warranty or liabilities. They are provided as is**

Implemenation guides for modern driver management and modern bios management can be found here;

[https://www.msendpointmgr.com/modern-driver-management/](https://www.msendpointmgr.com/modern-driver-management/)

[https://www.msendpointmgr.com/modern-bios-management/](https://www.msendpointmgr.com/modern-bios-management/)

All source code and installers will be maintained here from 11-March-2020. 

**SHA256 Hash Values for build 6.5.6**

Driver Automation Tool.msi - 1d2f547628fed9bd9e671c2bbe8c85897dd064ad624b2409f445d080dd03c263


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
	6.4.8 - (2020-15-07)	Added support for Windwos 10 2004
							Added support for HP SoftPaq creation and updated UI to select available SoftPaqs per models	
							Added support for creation of 7zip driver packages
							Added support for XML based modern driver and BIOS management solutions
							Faster UI and XML handling
							Updated Lenovo XML source
							Dell Flash 64w handling updated
	6.4.9 - (2020-15-09)	Added WIM Support
							Updated model and distribution point WMI queries for better performance
							Updated XML logic file creation function
							Updated Dell XML handling
	6.4.9 Hotfix - (2020-21-10)	Lenovo XML hotfix
	6.5.6 - (2021-20-08)	Updated manufacturer sources, with feeds from GitHub repo for imporoved maintenance and additions for Microsoft Surface devices
				Fix for Microsoft Surface model detection on download
				Fixes for other bugs and typos
						


