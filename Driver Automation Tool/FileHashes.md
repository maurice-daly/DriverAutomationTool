# File Hashes

SHA256 manifest of the core PowerShell files that make up the Driver Automation Tool.
Regenerate with the **update-file-hashes** skill whenever a core `.ps1`, `.psm1` or `.psd1` file changes.

| | |
|---|---|
| Version | `10.3.6.0` |
| Generated (UTC) | 2026-11-03 18:08:28 |
| Files | 20 |
| Algorithm | SHA256 |

## Entry Points

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| Start-DriverAutomationTool.ps1 | `Start-DriverAutomationTool.ps1` | 8.9 | `3173A26B88DA68EC02E1E88C9D7322AA1C3CE1BC167548501E0DFA332A8CE5FE` |
| Start-DATHeadlessBuild.ps1 | `Start-DATHeadlessBuild.ps1` | 46.2 | `02B468BBE6A8CDDCBE4E6E8DAE54FC563EC2091D52E9160B1C66953A9A114A9D` |

## Core Module

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| DriverAutomationToolCore.psd1 | `Modules/DriverAutomationToolCore/DriverAutomationToolCore.psd1` | 7.4 | `8BA5326B01ABF9D614D7118323CE18BF98D1D3991A8841E955CBF9D185CF12D8` |
| DriverAutomationToolCore.psm1 | `Modules/DriverAutomationToolCore/DriverAutomationToolCore.psm1` | 1548.5 | `CEC1BD775E81C89F1FFB0AF66469B9A80A4DE7E5A58F36DE8136F977771BF68C` |
| Deploy-BIOSPassword-Detection.ps1 | `Modules/DriverAutomationToolCore/Templates/Deploy-BIOSPassword-Detection.ps1` | 1.7 | `0BE9C8C804D06690AF90F4D6B691A170C89ABFEA949931C05F21D5111320C3BD` |
| Deploy-BIOSPassword-Remediation.ps1 | `Modules/DriverAutomationToolCore/Templates/Deploy-BIOSPassword-Remediation.ps1` | 2.9 | `36ADD50BA2CD9DC342899985167B3F972424CCEE3B32540BF4D93AA8364FC8C2` |
| Import-CMOfflinePackages.ps1 | `Modules/DriverAutomationToolCore/Templates/Import-CMOfflinePackages.ps1` | 9.9 | `E6DB9F4D3873152AFCA5DC897541E2E5BCB58039AE0AC04B3B9BB5894A5FE15A` |
| Install-BIOS.ps1 | `Modules/DriverAutomationToolCore/Templates/Install-BIOS.ps1` | 112.0 | `371129EAFF4AC66C88E4B321D0CF4C8D9CB47042F9464CD9C90B39D6E0756226` |
| Install-Drivers.ps1 | `Modules/DriverAutomationToolCore/Templates/Install-Drivers.ps1` | 67.5 | `109F75DA03B2E74CAD82411C17CED5ED32BCE1A418E29F2EA096753279AA69C3` |
| Invoke-DATToastTest.ps1 | `Modules/DriverAutomationToolCore/Templates/Invoke-DATToastTest.ps1` | 29.7 | `B57BEF1E6128B9CE9CC65E36428EBB7F82268C311F84B0D9D8FEE0CDCBFC4B96` |
| Test-DATMaintenanceWindow.ps1 | `Modules/DriverAutomationToolCore/Templates/Test-DATMaintenanceWindow.ps1` | 6.9 | `1E45CC1E002C8399C95C1E6244D6610094156F35BC200CB187401B1F2CDE00E0` |

## UI Layer

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| MainApplication.ps1 | `UI/MainApplication.ps1` | 1728.0 | `3E9246F37D3F0B723A35765D764F215E569618ED9D17C471C2E0726C2A7759DB` |
| ThemeDefinitions.ps1 | `UI/Themes/ThemeDefinitions.ps1` | 8.9 | `B7C6D8D529D3581C7EDCD79092F24F2550BE2B3DD7CB647DF690CC161520933A` |

## Deployment Scripts

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| Invoke-CMApplyDriverPackage.ps1 | `Scripts/Invoke-CMApplyDriverPackage.ps1` | 173.3 | `F768748988B4029738E13504A2431FA85756131A84F0CD4D58332970D6201D9D` |
| Invoke-CMDownloadBIOSPackage.ps1 | `Scripts/Invoke-CMDownloadBIOSPackage.ps1` | 101.3 | `91F63D156110266BED3F3A7BF521D6CB5BC4B2856EA9128C31B79A00E2165FB2` |
| Remove-DATStaleBIOSMarkers.ps1 | `Scripts/Remove-DATStaleBIOSMarkers.ps1` | 5.2 | `0D2CD832AE710A421E3790D5366D5F6C630418E9E96ED0E35FBA227F59AF0F60` |
| Test-DATAzCopyUpload.ps1 | `Scripts/Test-DATAzCopyUpload.ps1` | 13.4 | `3BAAD8B74B9991599E95FF07541FA5DB5F54F78501D18C03F4EF47F684377F18` |
| Test-DellDCUDriverDownload.ps1 | `Scripts/Test-DellDCUDriverDownload.ps1` | 23.4 | `F2309F8D740DBF7C12AE7178B47AE7F3462214C3515A6E2A24C83773475EC146` |
| Test-LenovoLatestDriverDownload.ps1 | `Scripts/Test-LenovoLatestDriverDownload.ps1` | 19.2 | `E970A7800B4F6DE0952C18765C4582ACDF9647D5518B972E11F9A5421E28FB8A` |
| Test-ModernDriverManagement.ps1 | `Scripts/Test-ModernDriverManagement.ps1` | 129.2 | `8B60EF98C3EA9EF896032A7456BC12EC727CBF20F126735104C936A9F9388DE5` |

---

Verify a copy of the tool against this manifest:

```powershell
Get-FileHash -Path .\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1 -Algorithm SHA256
```
