<#
    Driver Automation Tool - BIOS Password Deployment (Remediation Script)
    Author: Maurice Daly
    Organization: MSEndpointMgr
    Copyright: (c) Maurice Daly. All rights reserved.

    PURPOSE:
        Deploy this as an Intune Proactive Remediation (remediation script).
        It encrypts the BIOS password using DPAPI (machine-scope) and stores
        the encrypted blob in the registry. Because both this script and the
        Install-BIOS.ps1 run as SYSTEM on the same machine, DPAPI ensures
        only the local machine can decrypt the password.

    USAGE:
        1. Set the $BIOSPassword variable below to the BIOS password.
        2. Deploy as a Proactive Remediation in Intune:
             - Detection script : Deploy-BIOSPassword-Detection.ps1
             - Remediation script: Deploy-BIOSPassword-Remediation.ps1
             - Run as          : System
             - Run in 64-bit   : Yes
        3. The password is encrypted at rest and bound to each individual machine.

    SECURITY NOTES:
        - The plaintext password exists only in this script file and in memory
          during execution. It is never written to disk in plaintext.
        - Intune stores and transmits the script content encrypted; it is
          decrypted only at execution time in the SYSTEM context.
        - The DPAPI blob in the registry is useless if copied to another machine.
#>

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION -- Set your BIOS password here
# ═══════════════════════════════════════════════════════════════════════════════
$BIOSPassword = 'CHANGE_ME'
# ═══════════════════════════════════════════════════════════════════════════════

$RegistryPath = 'HKLM:\SOFTWARE\DriverAutomationTool\BIOS'

try {
    if (-not (Test-Path $RegistryPath)) {
        New-Item -Path $RegistryPath -Force | Out-Null
    }

    # Encrypt using DPAPI (machine-bound when running as SYSTEM)
    $secureString = ConvertTo-SecureString -String $BIOSPassword -AsPlainText -Force
    $encryptedBlob = ConvertFrom-SecureString -SecureString $secureString

    Set-ItemProperty -Path $RegistryPath -Name 'Password' -Value $encryptedBlob -Force
    Set-ItemProperty -Path $RegistryPath -Name 'PasswordSetDate' -Value (Get-Date -Format 'o') -Force

    Write-Output "BIOS password encrypted and stored successfully"
    exit 0
} catch {
    Write-Output "ERROR: Failed to store BIOS password -- $($_.Exception.Message)"
    exit 1
}
