<p align="center">
  <img src="Content/Screenshots/Dat_Logo.png" alt="Driver Automation Tool" width="150" />
</p>

<h1 align="center">Driver Automation Tool</h1>

<p align="center">
  Enterprise-grade automation for downloading, extracting, and packaging OEM driver and BIOS update packages for ConfigMgr and Intune.
  <br /><br />
  <a href="https://www.driverautomationtool.com"><strong>Website</strong></a> · <a href="https://www.driverautomationtool.com/setup-guide"><strong>Setup Guide</strong></a> · <a href="https://www.driverautomationtool.com/reports"><strong>Reports</strong></a>
  <br /><br />
  A free community tool — created by <strong>Maurice Daly</strong>
</p>

---

## Overview

The Driver Automation Tool is a PowerShell WPF desktop application that automates the full lifecycle of OEM driver and BIOS package management — from catalog discovery and download through extraction, WIM packaging, and deployment to Configuration Manager or Microsoft Intune.

<p align="center">
  <img src="Content/Screenshots/MainUI.png" alt="Driver Automation Tool — Main Interface" width="900" />
</p>

## Supported OEMs

| OEM | Drivers | BIOS Updates |
|-----|---------|--------------|
| HP | ✅ | ✅ |
| Dell | ✅ | ✅ |
| Lenovo | ✅ | ✅ |
| Microsoft Surface | ✅ | — |
| Acer | ✅ | ✅ |

## Core Features

- **Automated Driver Downloads** — Accelerated downloads via `curl.exe` with HTTP resume support, configurable retry logic (10 retries, 60s delay), and automatic hash verification
- **Multi-OEM Support** — Full support for HP, Dell, Lenovo, Microsoft Surface, and Acer with automatic catalog discovery
- **BIOS Update Management** — Version comparison, release classification (Recommended/Critical), minimum version validation, and hash verification
- **WIM Packaging** — Create WIM packages using DISM (built-in), wimlib (multi-threaded), or 7-Zip (recommended) with configurable compression
- **ConfigMgr Integration** — Automatic package creation, content distribution to DPs, WinRM/WMI connectivity, and deployment state tracking
- **Intune Integration** — Device code or app registration auth, chunked Azure Blob uploads, parallel threading, and Win32 app packaging

## Deployment Platforms

| Platform | Description |
|----------|-------------|
| **Configuration Manager** | Download → Extract → Create WIM → Create ConfigMgr package → Distribute to DPs |
| **Microsoft Intune** | Download → Extract → Create WIM → Wrap as .intunewin → Upload and create Win32 app |
| **WIM Package Only** | Download → Extract → Create WIM file only (no deployment) |
| **Download Only** | Download and extract packages without any WIM packaging or deployment |

## Getting Started

### 1. Download

Download the latest release from this repository. The tool is a portable PowerShell application with no installer required.

<p align="center">
  <img src="Content/Screenshots/GitHubDownload.png" alt="GitHub Download" width="700" />
</p>

### 2. Extract

Extract the downloaded ZIP to a permanent location on your local machine:

```
C:\DriverAutomationTool
```

> **Important:** Ensure the extracted folder is not blocked by Windows. Right-click the ZIP file before extracting, go to Properties, and check "Unblock" if present.

### 3. Launch

Open PowerShell as Administrator and run:

```powershell
cd C:\DriverAutomationTool
.\Start-DriverAutomationTool.ps1

# Or launch with dark theme
.\Start-DriverAutomationTool.ps1 -Theme Dark
```

If you see an execution policy error:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

<p align="center">
  <img src="Content/Screenshots/Launch.png" alt="Launching from PowerShell" width="700" />
</p>

### 4. Accept EULA

On first launch, review and accept the End User License Agreement.

<p align="center">
  <img src="Content/Screenshots/EULA.png" alt="EULA" width="700" />
</p>

### 5. Configure

Set your storage paths, select your deployment platform, and configure proxy settings if needed. See the [Setup Guide](https://www.driverautomationtool.com/setup-guide) for detailed configuration instructions.

## Platform Configuration

### Configuration Manager

Connect to your ConfigMgr site server via WinRM/WMI for automated package creation and content distribution.

<p align="center">
  <img src="Content/Screenshots/ConfigMgr1.png" alt="ConfigMgr Connection" width="700" />
</p>

| Setting | Description |
|---------|-------------|
| Site Server FQDN | Fully qualified domain name of your ConfigMgr site server |
| WinRM SSL | Enable SSL/TLS encryption for WinRM communications |
| Known Model Lookup | Query hardware inventory to highlight models in your environment |
| Replication Priority | Set content distribution priority (High / Normal / Low) |
| Binary Differential Replication | Transmit only changed binary blocks to reduce bandwidth |

<p align="center">
  <img src="Content/Screenshots/ConfigMgr2.png" alt="ConfigMgr Package Management" width="700" />
  <br /><em>ConfigMgr package management view</em>
</p>

<p align="center">
  <img src="Content/Screenshots/ConfigMgr3.png" alt="ConfigMgr Distribution" width="700" />
  <br /><em>Distribution point configuration</em>
</p>

### Microsoft Intune

Three authentication methods are supported for connecting to Intune via the Microsoft Graph API:

| Method | Description |
|--------|-------------|
| **Interactive (Browser)** | Browser-based sign-in with full MFA and Conditional Access support (Recommended) |
| **Interactive (Device Code)** | Device code flow for restricted environments |
| **App Registration** | Tenant ID, App ID, and Client Secret for automated/scheduled runs |

**Required Graph API Permissions (Application):**
- `DeviceManagementApps.ReadWrite.All`
- `DeviceManagementManagedDevices.Read.All`
- `GroupMember.Read.All`

<p align="center">
  <img src="Content/Screenshots/Intune1.png" alt="Intune Authentication" width="700" />
  <br /><em>Intune authentication method selection</em>
</p>

<p align="center">
  <img src="Content/Screenshots/Intune4.png" alt="Intune Upload Options" width="700" />
  <br /><em>Package upload and deployment options</em>
</p>

#### Package Assignment

Assign packages directly to Entra ID groups from the Package Management section. Right-click any package to access assignment options — deploy as **Required** (automatic) or **Available** (user-initiated from Company Portal).

<p align="center">
  <img src="Content/Screenshots/IntuneAssignment1.png" alt="Intune Assignment" width="700" />
  <br /><em>Right-click to assign packages to Entra ID groups</em>
</p>

#### BIOS Security

For environments requiring BIOS passwords for firmware updates, the tool encrypts passwords using DPAPI with machine-scope protection and embeds them in detection/remediation scripts for Intune deployments. HP devices also support BIN files generated by HP BIOS Configuration Utility (BCU).

<p align="center">
  <img src="Content/Screenshots/IntuneBIOS.png" alt="BIOS Security Configuration" width="700" />
  <br /><em>BIOS security configuration</em>
</p>

## Intune Client Experience

Once published, packages deploy through the Intune Company Portal with toast notifications at every stage:

<p align="center">
  <img src="Content/Screenshots/IntuneClient1.png" alt="Company Portal — Available App" width="350" />
  <img src="Content/Screenshots/IntuneClient4.png" alt="Toast Notification" width="350" />
  <br /><em>Company Portal install flow with toast notification prompts</em>
</p>

### Toast Notifications

Fully customisable Windows toast notifications keep end users informed — from pending updates through to successful completion. Replace the default branding with your own logo and messaging.

<p align="center">
  <img src="Content/Screenshots/Toast1.png" alt="BIOS Update Pending" width="350" />
  <img src="Content/Screenshots/Toast2.png" alt="Driver Updates Pending" width="350" />
</p>
<p align="center">
  <img src="Content/Screenshots/Toast3.png" alt="BIOS Firmware Prestaged" width="350" />
  <img src="Content/Screenshots/Toast4.png" alt="Drivers Successfully Updated" width="350" />
</p>
<p align="center">
  <img src="Content/Screenshots/ToastCustomise.png" alt="Custom Branding" width="500" />
  <br /><em>Custom branding and messaging configuration</em>
</p>

## Common Settings

### WIM Packaging Engine

Three engines are supported for WIM creation:

| Engine | Description | Benchmark (~2551 MB) |
|--------|-------------|----------------------|
| DISM | Built-in Windows engine, single-threaded | ~3m 51s |
| wimlib | Multi-threaded third-party engine | ~2m 53s |
| **7-Zip** ✅ | High-performance multi-threaded (Recommended) | **~36s** |

*Estimates based on benchmark testing — actual times will vary based on hardware.*

### Compression Levels

| Level | Description |
|-------|-------------|
| Fast (XPRESS) | Fastest creation speed, moderate file size (Default) |
| Maximum (LZX) | Slower creation, smallest file size |
| None | Uncompressed — fastest creation, largest file size |

### Additional Options

<p align="center">
  <img src="Content/Screenshots/Options1.png" alt="Common Settings" width="700" />
  <br /><em>Common settings — General options</em>
</p>

| Setting | Description |
|---------|-------------|
| Proxy | System default, manual host:port, or bypass |
| CURL Engine | Bundled or system curl.exe with signature validation |
| Temporary Storage | Local path for downloads, extraction, and WIM staging |
| Package Storage | Final output path for WIM and .intunewin packages (supports UNC) |
| Config Export/Import | Backup and restore all settings via .reg file |
| Telemetry | Opt-in anonymous telemetry — only package counts and model data, no PII |

## Custom Driver Pack

Create custom driver packages from the drivers installed on the current system (via PNPUtil) or from a local folder of INF files — ideal for devices not covered by OEM catalogs.

<p align="center">
  <img src="Content/Screenshots/CustomDriverPack.png" alt="Custom Driver Pack" width="700" />
  <br /><em>Custom Driver Pack creation interface</em>
</p>

### Custom OEM Driver Injection

Supplement OEM packages with additional drivers by right-clicking a model in Package Management and selecting **Add Custom Drivers**. Useful for missing or outdated drivers in standard OEM packages.

<p align="center">
  <img src="Content/Screenshots/CustomDrivers.png" alt="Add Custom Drivers" width="700" />
  <br /><em>Add Custom Drivers via right-click context menu</em>
</p>

## Logging

All operations are logged in CMTrace-compatible XML format with a built-in log viewer and real-time activity display.

| Feature | Description |
|---------|-------------|
| Log Format | CMTrace-compatible XML — readable in ConfigMgr Trace Log Tool |
| Log Location | `<AppRoot>\Logs\DriverAutomationTool.log` |
| Severity Levels | Information, Warning, Error — color-coded in CMTrace |
| Auto-Rotation | Rotates at 1 MB with 5 archived copies retained |
| Activity Log | Real-time in-app display during builds (60,000 char buffer) |

<p align="center">
  <img src="Content/Screenshots/Logging.png" alt="Log Viewer" width="700" />
  <br /><em>Built-in log viewer and activity log</em>
</p>

## Theme Support

The tool supports both light and dark themes with instant runtime switching.

<p align="center">
  <img src="Content/Screenshots/LightMode.png" alt="Light Mode" width="400" />
  <img src="Content/Screenshots/DarkMode.png" alt="Dark Mode" width="400" />
</p>

## Platform Requirements

- **OS:** Windows 11 / Windows 10 / Windows Server 2016+
- **Architecture:** x64, Arm64
- **PowerShell:** Windows PowerShell 5.1+
- **Privileges:** Administrator (for registry access and DISM operations)

## Links

- 🌐 [Driver Automation Tool Website](https://www.driverautomationtool.com)
- 📖 [Setup Guide](https://www.driverautomationtool.com/setup-guide)
- 📊 [Reports & Statistics](https://www.driverautomationtool.com/reports)
- ℹ️ [About](https://www.driverautomationtool.com/about)

## License

This tool is provided **as-is**, without warranty of any kind. Use is entirely at your own risk. See the [LICENSE](LICENSE) file for details.

## Sponsor

If you find this tool useful and would like to support its continued development, please use the **Sponsor** button at the top of this page.

## Virus Warning

Due to the nature of how the PowerShell script downloads EXEs and extracts / interacts with them, the code can be picked up as a false positive on some AV solutions. The code is all available for clear text review with your security team in this instance. 

