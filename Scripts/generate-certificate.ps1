<# Create and optionally trust a disposable per-user development signing certificate. #>

[CmdletBinding()]
param(
    [switch]$Trust
)

$ErrorActionPreference = "Stop"
$installerDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.installer"))
New-Item -ItemType Directory -Path $installerDirectory -Force | Out-Null

$certificate = New-SelfSignedCertificate `
    -Type Custom `
    -Subject "CN=Swift Backtrace Reproducer" `
    -FriendlyName "Swift Backtrace Reproducer development certificate" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -KeyExportPolicy NonExportable `
    -KeyUsage DigitalSignature `
    -NotAfter (Get-Date).AddYears(1)

$certificatePath = Join-Path $installerDirectory "development-certificate.cer"
Export-Certificate -Cert $certificate -FilePath $certificatePath -Force | Out-Null
[System.IO.File]::WriteAllText(
    (Join-Path $installerDirectory "certificate-thumbprint.txt"),
    $certificate.Thumbprint,
    [System.Text.UTF8Encoding]::new($false)
)

if ($Trust) {
    Import-Certificate -FilePath $certificatePath -CertStoreLocation "Cert:\CurrentUser\Root" | Out-Null
}

Write-Host "Certificate thumbprint: $($certificate.Thumbprint)"
Write-Host "Public certificate: $certificatePath"
if (-not $Trust) {
    Write-Host "The certificate was not trusted. Re-run with -Trust before installing the package."
}

