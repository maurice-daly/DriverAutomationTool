<#
    Driver Automation Tool - BIOS Password Deployment (Detection Script)
    Author: Maurice Daly
    Organization: MSEndpointMgr
    Copyright: (c) Maurice Daly. All rights reserved.

    PURPOSE:
        Detects whether a BIOS password has been deployed to the registry.
        Used as the detection script in an Intune Proactive Remediation pair.

        Exit 0 = password exists and is decryptable (compliant -- no remediation needed)
        Exit 1 = password missing or corrupted  (non-compliant -- remediation will run)
#>

$RegistryPath = 'HKLM:\SOFTWARE\DriverAutomationTool\BIOS'

try {
    $encryptedBlob = (Get-ItemProperty -Path $RegistryPath -Name 'Password' -ErrorAction SilentlyContinue).Password

    if ([string]::IsNullOrEmpty($encryptedBlob)) {
        Write-Output "BIOS password not found in registry"
        exit 1
    }

    # Verify it can be decrypted (DPAPI machine-scope)
    $secureString = ConvertTo-SecureString -String $encryptedBlob -ErrorAction Stop
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    try {
        $plaintext = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }

    if ([string]::IsNullOrEmpty($plaintext)) {
        Write-Output "BIOS password decrypted but is empty"
        exit 1
    }

    $setDate = (Get-ItemProperty -Path $RegistryPath -Name 'PasswordSetDate' -ErrorAction SilentlyContinue).PasswordSetDate
    Write-Output "BIOS password is present and decryptable (set: $setDate)"
    exit 0
} catch {
    Write-Output "BIOS password exists but cannot be decrypted -- $($_.Exception.Message)"
    exit 1
}
