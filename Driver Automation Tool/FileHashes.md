# File Hashes

SHA256 manifest of the core PowerShell files that make up the Driver Automation Tool.
Regenerate with the **update-file-hashes** skill whenever a core `.ps1`, `.psm1` or `.psd1` file changes.

| | |
|---|---|
| Version | `10.2.6.0` |
| Generated (UTC) | 2026-09-03 09:34:49 |
| Files | 18 |
| Algorithm | SHA256 |

## Entry Points

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| Start-DriverAutomationTool.ps1 | `Start-DriverAutomationTool.ps1` | 8.9 | `3173A26B88DA68EC02E1E88C9D7322AA1C3CE1BC167548501E0DFA332A8CE5FE` |
| Start-DATHeadlessBuild.ps1 | `Start-DATHeadlessBuild.ps1` | 39 | `23205BE23AEDB73485775315695829D46E4913030707E848B5852D45EDC9A8C7` |

## Core Module

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| DriverAutomationToolCore.psd1 | `Modules/DriverAutomationToolCore/DriverAutomationToolCore.psd1` | 5.3 | `4EE9CF6C66FE76A3FC8D705DFB6A70530B7CA12671B2C910F4D66C920EF96618` |
| DriverAutomationToolCore.psm1 | `Modules/DriverAutomationToolCore/DriverAutomationToolCore.psm1` | 1095.5 | `14127FE09F9AF83537FB4FB3D400A9BD0DCEB788FBF92FD435A7E00FFF82C7EB` |
| Deploy-BIOSPassword-Detection.ps1 | `Modules/DriverAutomationToolCore/Templates/Deploy-BIOSPassword-Detection.ps1` | 1.7 | `0BE9C8C804D06690AF90F4D6B691A170C89ABFEA949931C05F21D5111320C3BD` |
| Deploy-BIOSPassword-Remediation.ps1 | `Modules/DriverAutomationToolCore/Templates/Deploy-BIOSPassword-Remediation.ps1` | 2.9 | `36ADD50BA2CD9DC342899985167B3F972424CCEE3B32540BF4D93AA8364FC8C2` |
| Import-CMOfflinePackages.ps1 | `Modules/DriverAutomationToolCore/Templates/Import-CMOfflinePackages.ps1` | 9.9 | `E6DB9F4D3873152AFCA5DC897541E2E5BCB58039AE0AC04B3B9BB5894A5FE15A` |
| Install-BIOS.ps1 | `Modules/DriverAutomationToolCore/Templates/Install-BIOS.ps1` | 61.6 | `86F88CC9F44310B13C99E5274A7C4256CC384EBA095790A7F45C7B7A32C57E70` |
| Install-Drivers.ps1 | `Modules/DriverAutomationToolCore/Templates/Install-Drivers.ps1` | 29.2 | `ED2D6E597B3FDA122088E00C9A517AAABD4C42D165FCD8478D91DCBE54210B72` |
| Test-DATMaintenanceWindow.ps1 | `Modules/DriverAutomationToolCore/Templates/Test-DATMaintenanceWindow.ps1` | 6.9 | `1E45CC1E002C8399C95C1E6244D6610094156F35BC200CB187401B1F2CDE00E0` |

## UI Layer

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| MainApplication.ps1 | `UI/MainApplication.ps1` | 1517.5 | `E8386E18CC2C87FA6CA5924C8B2C89FF66F5E7899C1B3201836AA753C9F19B4C` |
| ThemeDefinitions.ps1 | `UI/Themes/ThemeDefinitions.ps1` | 8.1 | `5ED8D12452C0FEC68DFFC559D7C21D8DF913B1D2BBD7BE5028C743A84E45EA38` |

## Deployment Scripts

| File | Path | Size (KB) | SHA256 |
|------|------|-----------|--------|
| Invoke-CMApplyDriverPackage.ps1 | `Scripts/Invoke-CMApplyDriverPackage.ps1` | 149.7 | `B117A5227AE3E386E55C45EB49AD3FF61D07600B488F5DFEC2CE67E136904C39` |
| Invoke-CMDownloadBIOSPackage.ps1 | `Scripts/Invoke-CMDownloadBIOSPackage.ps1` | 97.6 | `38147D95DB148F94405F08021873BE6DF44097C952E30F9FAE9003E4AC310AAD` |
| Remove-DATStaleBIOSMarkers.ps1 | `Scripts/Remove-DATStaleBIOSMarkers.ps1` | 5.2 | `0D2CD832AE710A421E3790D5366D5F6C630418E9E96ED0E35FBA227F59AF0F60` |
| Test-DATAzCopyUpload.ps1 | `Scripts/Test-DATAzCopyUpload.ps1` | 13.4 | `3BAAD8B74B9991599E95FF07541FA5DB5F54F78501D18C03F4EF47F684377F18` |
| Test-DellDCUDriverDownload.ps1 | `Scripts/Test-DellDCUDriverDownload.ps1` | 23.4 | `F2309F8D740DBF7C12AE7178B47AE7F3462214C3515A6E2A24C83773475EC146` |
| Test-LenovoLatestDriverDownload.ps1 | `Scripts/Test-LenovoLatestDriverDownload.ps1` | 19.1 | `629F67B3F9ECF119137D71789EE1167D65CB8797D303AD033DBB33CE92E784D9` |

---

Verify a copy of the tool against this manifest:

```powershell
Get-FileHash -Path .\Modules\DriverAutomationToolCore\DriverAutomationToolCore.psm1 -Algorithm SHA256
```
