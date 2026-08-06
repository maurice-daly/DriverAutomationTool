<#
.SYNOPSIS
    Imports Driver and BIOS packages exported by the Driver Automation Tool
    "Configuration Manager (Offline)" platform option into a Configuration Manager site.

.DESCRIPTION
    This is a fully standalone script (no Driver Automation Tool module dependency). It is
    generated alongside the exported content and a DATOfflinePackages.json manifest. Run it
    on an air-gapped / offline Configuration Manager environment to recreate the driver and
    BIOS packages that were built where internet access was available.

    For each entry in the manifest it:
      1. Copies the package content (a DriverPackage.wim or an expanded BIOS folder) from the
         export folder to the package source location you specify (-PackageSourceRoot).
      2. Creates an SMS_Package via WMI with the same metadata the online tool would set
         (Name, Manufacturer, Description, Version, MIFName, MIFVersion, PkgSourceFlag, Priority).
      3. Files the package into the "Driver Packages\<OEM>" / "BIOS Packages\<OEM>" console folder.

    Content distribution (to distribution points / DP groups) and replication settings are
    intentionally left to the administrator to perform in the Configuration Manager console.

.PARAMETER SiteServer
    The Configuration Manager primary site server hosting the SMS Provider.

.PARAMETER SiteCode
    The Configuration Manager site code (e.g. "PS1").

.PARAMETER PackageSourceRoot
    The root path where package content will be copied and where ConfigMgr will read the
    package source from. This should be reachable by the site server (a UNC share such as
    \\server\Sources\DAT, or a local path if running on the site server).

.PARAMETER SourceRoot
    The folder containing DATOfflinePackages.json and the exported content. Defaults to the
    directory this script lives in.

.PARAMETER Priority
    Replication priority applied to created packages: High, Normal (default) or Low.

.EXAMPLE
    .\Import-CMOfflinePackages.ps1 -SiteServer CM01 -SiteCode PS1 -PackageSourceRoot \\CM01\Sources\DAT
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$SiteServer,
    [Parameter(Mandatory = $true)][string]$SiteCode,
    [Parameter(Mandatory = $true)][string]$PackageSourceRoot,
    [string]$SourceRoot = $PSScriptRoot,
    [ValidateSet('High', 'Normal', 'Low')][string]$Priority = 'Normal'
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param ([string]$Message, [ValidateSet('Info', 'Warn', 'Error')][string]$Level = 'Info')
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $color = switch ($Level) { 'Warn' { 'Yellow' } 'Error' { 'Red' } default { 'Gray' } }
    Write-Host "[$stamp] $Message" -ForegroundColor $color
}

$smsNamespace = "root\SMS\Site_$SiteCode"
$priorityValue = switch ($Priority) { 'High' { 1 } 'Low' { 3 } default { 2 } }

# --- Load the manifest ---
$manifestPath = Join-Path -Path $SourceRoot -ChildPath 'DATOfflinePackages.json'
if (-not (Test-Path -Path $manifestPath)) {
    throw "Manifest not found: $manifestPath. Run this script from the exported 'ConfigMgr Offline' folder or pass -SourceRoot."
}
$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
$packages = @($manifest.packages)
if ($packages.Count -eq 0) {
    Write-Log "Manifest contains no packages -- nothing to import." -Level Warn
    return
}

Write-Log "Importing $($packages.Count) package(s) to site $SiteCode on $SiteServer"
Write-Log "Package source root: $PackageSourceRoot"

if (-not (Test-Path -Path $PackageSourceRoot)) {
    New-Item -Path $PackageSourceRoot -ItemType Directory -Force | Out-Null
}

$created = 0
$updated = 0
$failed = 0

foreach ($pkg in $packages) {
    try {
        $pkgName = [string]$pkg.name
        Write-Log "Processing '$pkgName' ($($pkg.packageType))"

        # Resolve the exported content and the destination content folder
        $sourceItem = Join-Path -Path $SourceRoot -ChildPath $pkg.sourceRelativePath
        if (-not (Test-Path -Path $sourceItem)) {
            Write-Log "  Source content missing, skipping: $sourceItem" -Level Warn
            $failed++
            continue
        }

        if ($pkg.sourceType -eq 'wim') {
            # sourceRelativePath includes the WIM filename -- the package points at its folder
            $relFolder = Split-Path -Path $pkg.sourceRelativePath -Parent
        } else {
            $relFolder = [string]$pkg.sourceRelativePath
        }
        $destFolder = Join-Path -Path $PackageSourceRoot -ChildPath $relFolder
        if (-not (Test-Path -Path $destFolder)) { New-Item -Path $destFolder -ItemType Directory -Force | Out-Null }

        if ($pkg.sourceType -eq 'wim') {
            Copy-Item -Path $sourceItem -Destination $destFolder -Force
        } else {
            Copy-Item -Path (Join-Path $sourceItem '*') -Destination $destFolder -Recurse -Force
        }
        Write-Log "  Content copied to $destFolder"

        # --- Check for an existing package of the same name ---
        $escapedName = $pkgName -replace "'", "''"
        $existing = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
            -Query "SELECT PackageID, Name, Version, PkgSourcePath FROM SMS_Package WHERE Name = '$escapedName'" -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($existing) {
            $pkgId = $existing.PackageID
            Write-Log "  Existing package $pkgId found -- updating source, version and metadata"
            $pkgWmi = [wmi]"\\$SiteServer\$($smsNamespace):SMS_Package.PackageID='$pkgId'"
            $pkgWmi.PkgSourcePath = $destFolder
            $pkgWmi.Version = [string]$pkg.version
            $pkgWmi.Description = [string]$pkg.description
            $pkgWmi.Priority = $priorityValue
            $pkgWmi.SourceDate = [System.Management.ManagementDateTimeConverter]::ToDmtfDateTime((Get-Date))
            $pkgWmi.Put() | Out-Null
            try { $pkgWmi.RefreshPkgSource() | Out-Null } catch { }
            $updated++
            continue
        }

        # --- Create the package ---
        $newPkg = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_Package").CreateInstance()
        $newPkg.Name = $pkgName
        $newPkg.PkgSourcePath = $destFolder
        $newPkg.Manufacturer = [string]$pkg.manufacturer
        $newPkg.Description = [string]$pkg.description
        $newPkg.Version = [string]$pkg.version
        $newPkg.MIFName = [string]$pkg.mifName
        $newPkg.MIFVersion = [string]$pkg.mifVersion
        $newPkg.PkgSourceFlag = 2  # Direct source path
        $newPkg.Priority = $priorityValue
        $newPkg.SourceDate = [System.Management.ManagementDateTimeConverter]::ToDmtfDateTime((Get-Date))
        $putResult = $newPkg.Put()
        $pkgId = $putResult.RelativePath -replace '.*PackageID="([^"]+)".*', '$1'
        Write-Log "  Created package $pkgId"

        # --- File the package into the console folder (Driver Packages\OEM or BIOS Packages\OEM) ---
        try {
            $folderName = if ($pkg.packageType -eq 'BIOS') { 'BIOS Packages' } else { 'Driver Packages' }
            $oemName = [string]$pkg.manufacturer

            $topFolder = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
                -Query "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE Name = '$($folderName -replace "'","''")' AND ObjectType = 2 AND ParentContainerNodeID = 0" -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if (-not $topFolder) {
                $nf = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_ObjectContainerNode").CreateInstance()
                $nf.Name = $folderName; $nf.ObjectType = 2; $nf.ParentContainerNodeID = 0
                $nf.Put() | Out-Null
                $topFolder = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
                    -Query "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE Name = '$($folderName -replace "'","''")' AND ObjectType = 2 AND ParentContainerNodeID = 0" |
                    Select-Object -First 1
            }
            $topId = $topFolder.ContainerNodeID

            $oemFolder = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
                -Query "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE Name = '$($oemName -replace "'","''")' AND ObjectType = 2 AND ParentContainerNodeID = $topId" -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if (-not $oemFolder) {
                $nof = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_ObjectContainerNode").CreateInstance()
                $nof.Name = $oemName; $nof.ObjectType = 2; $nof.ParentContainerNodeID = $topId
                $nof.Put() | Out-Null
                $oemFolder = Get-WmiObject -ComputerName $SiteServer -Namespace $smsNamespace `
                    -Query "SELECT ContainerNodeID FROM SMS_ObjectContainerNode WHERE Name = '$($oemName -replace "'","''")' AND ObjectType = 2 AND ParentContainerNodeID = $topId" |
                    Select-Object -First 1
            }
            $oemId = $oemFolder.ContainerNodeID

            $moveItem = ([WmiClass]"\\$SiteServer\$($smsNamespace):SMS_ObjectContainerItem").CreateInstance()
            $moveItem.InstanceKey = $pkgId
            $moveItem.ObjectType = 2
            $moveItem.ContainerNodeID = $oemId
            $moveItem.Put() | Out-Null
            Write-Log "  Filed into $folderName\$oemName"
        } catch {
            Write-Log "  Could not file package into console folder: $($_.Exception.Message)" -Level Warn
        }

        $created++
    } catch {
        Write-Log "  Failed to import '$($pkg.name)': $($_.Exception.Message)" -Level Error
        $failed++
    }
}

Write-Log "Import complete. Created: $created, Updated: $updated, Failed: $failed"
Write-Log "Reminder: distribute the new/updated package content to your distribution points in the ConfigMgr console."
