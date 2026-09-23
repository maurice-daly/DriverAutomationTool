# File Hashes

SHA256 manifest of the core PowerShell files that make up the Driver Automation Tool.
Regenerate with the **update-file-hashes** skill whenever a core `.ps1`, `.psm1` or `.psd1` file changes.

| | |
|---|---|
| Version | `10.2.9.0` |
| Generated (UTC) | 2026-09-23 13:32:15 |
| Files | 18 |
| Algorithm | SHA256 |

## Entry Points

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| Start-DriverAutomationTool.ps1 | `Start-DriverAutomationTool.ps1` | 8.9 | `3173A26B88DA68EC02E1E88C9D7322AA1C3CE1BC167548501E0DFA332A8CE5FE` |
| Start-DATHeadlessBuild.ps1 | `Start-DATHeadlessBuild.ps1` | 45.3 | `F967C68C888AA34C8F01B345AAF7505DA3CCD544F450E0594C12DF6EC68CC075` |

## Core Module

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| DriverAutomationToolCore.psd1 | `Modules/DriverAutomationToolCore/DriverAutomationToolCore.psd1` | 6 | `B4E07B71A4CEA3C8A65A220541CB69BD549D1567CC2ADDBD09F64DA26652FE9F` |
| DriverAutomationToolCore.psm1 | `Modules/DriverAutomationToolCore/DriverAutomationToolCore.psm1` | 1217.7 | `E8EA219F006BF80BF511AA39CA58A7AAEEFB1D59F0702FA45FF644DC930078AC` |
| Deploy-BIOSPassword-Detection.ps1 | `Modules/DriverAutomationToolCore/Templates/Deploy-BIOSPassword-Detection.ps1` | 1.7 | `0BE9C8C804D06690AF90F4D6B691A170C89ABFEA949931C05F21D5111320C3BD` |
| Deploy-BIOSPassword-Remediation.ps1 | `Modules/DriverAutomationToolCore/Templates/Deploy-BIOSPassword-Remediation.ps1` | 2.9 | `36ADD50BA2CD9DC342899985167B3F972424CCEE3B32540BF4D93AA8364FC8C2` |
| Import-CMOfflinePackages.ps1 | `Modules/DriverAutomationToolCore/Templates/Import-CMOfflinePackages.ps1` | 9.9 | `E6DB9F4D3873152AFCA5DC897541E2E5BCB58039AE0AC04B3B9BB5894A5FE15A` |
| Install-BIOS.ps1 | `Modules/DriverAutomationToolCore/Templates/Install-BIOS.ps1` | 72.9 | `747D0CEDBF5E788D96F0E9FE3317812864579EA37D335988F8C3C55590A41BE9` |
| Install-Drivers.ps1 | `Modules/DriverAutomationToolCore/Templates/Install-Drivers.ps1` | 29.2 | `2D426CD6A37372FC5381657B0CA2BBEED2B8EB5F1E6F8E45245FE4B7414AD46C` |
| Test-DATMaintenanceWindow.ps1 | `Modules/DriverAutomationToolCore/Templates/Test-DATMaintenanceWindow.ps1` | 6.9 | `1E45CC1E002C8399C95C1E6244D6610094156F35BC200CB187401B1F2CDE00E0` |

## UI Layer

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| MainApplication.ps1 | `UI/MainApplication.ps1` | 1560.3 | `7ACD103264D2871EABAD5FF91F0711D56F318E84D33FF965B732D6B3CF24DA90` |
| ThemeDefinitions.ps1 | `UI/Themes/ThemeDefinitions.ps1` | 8.1 | `5ED8D12452C0FEC68DFFC559D7C21D8DF913B1D2BBD7BE5028C743A84E45EA38` |

## Deployment Scripts

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| Invoke-CMApplyDriverPackage.ps1 | `Scripts/Invoke-CMApplyDriverPackage.ps1` | 147 | `7326F6BE82BAE21791E4BCCA7D4EAAE83441C69C8CA2D7272E2874F38982FB7D` |
| Invoke-CMDownloadBIOSPackage.ps1 | `Scripts/Invoke-CMDownloadBIOSPackage.ps1` | 95.8 | `C2FC9C7EE74F4A51F890F689C4B59B780DBE54BD50485BA403AF795B0ADF68CA` |
| Remove-DATStaleBIOSMarkers.ps1 | `Scripts/Remove-DATStaleBIOSMarkers.ps1` | 5.2 | `0D2CD832AE710A421E3790D5366D5F6C630418E9E96ED0E35FBA227F59AF0F60` |
| Test-DATAzCopyUpload.ps1 | `Scripts/Test-DATAzCopyUpload.ps1` | 13.4 | `3BAAD8B74B9991599E95FF07541FA5DB5F54F78501D18C03F4EF47F684377F18` |
| Test-DellDCUDriverDownload.ps1 | `Scripts/Test-DellDCUDriverDownload.ps1` | 23.4 | `F2309F8D740DBF7C12AE7178B47AE7F3462214C3515A6E2A24C83773475EC146` |
| Test-LenovoLatestDriverDownload.ps1 | `Scripts/Test-LenovoLatestDriverDownload.ps1` | 18.7 | `2ADCFDC7D5FD1C8578547893F820FF120B55DE505ADD5F247FF4A06840916A0B` |

---

Verify a copy of the tool against this manifest:

```powershell
Get-FileHash -Path .\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1 -Algorithm SHA256
```
