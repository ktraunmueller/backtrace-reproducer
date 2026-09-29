<# Stage, pack, and sign a self-contained MSIX for the configured build tree. #>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BuildDirectory,

    [string]$CertificateThumbprint
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\windows-sdk-tools.ps1"

if (-not $env:SWIFT_RUNTIME_PATH) {
    throw "SWIFT_RUNTIME_PATH must point to the architecture-matched Swift runtime usr directory."
}
$swiftRuntime = [System.IO.Path]::GetFullPath($env:SWIFT_RUNTIME_PATH)
$buildPath = [System.IO.Path]::GetFullPath($BuildDirectory)
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$manifestPath = Join-Path $buildPath "AppxManifest.xml"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Configured package manifest not found: $manifestPath"
}
[xml]$manifest = Get-Content -LiteralPath $manifestPath
$architecture = $manifest.Package.Identity.ProcessorArchitecture
if ($architecture -notin @("x64", "arm64")) {
    throw "Unsupported package architecture '$architecture'."
}
if ($manifest.Package.Dependencies.PackageDependency | Where-Object { $_.Name -like "Microsoft.WindowsAppRuntime*" }) {
    throw "The self-contained manifest must not declare a Microsoft.WindowsAppRuntime dependency."
}

$installerDirectory = Join-Path $repositoryRoot ".installer"
$stagingDirectory = Join-Path $installerDirectory "staging-$architecture"
$installerFile = Join-Path $installerDirectory "SwiftBacktraceReproducer-$architecture.msix"
New-Item -ItemType Directory -Path $installerDirectory -Force | Out-Null
Remove-Item -LiteralPath $installerFile -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $stagingDirectory | Out-Null

$executable = Join-Path $buildPath "SwiftBacktraceReproducer.exe"
Assert-PeArchitecture -Path $executable -Architecture $architecture
Copy-Item -LiteralPath $executable -Destination $stagingDirectory
Copy-Item -LiteralPath $manifestPath -Destination $stagingDirectory

$runtimeDlls = @("msvcp140.dll", "vcruntime140.dll")
if ($architecture -eq "x64") {
    $runtimeDlls += "vcruntime140_1.dll"
}
$runtimeDlls += @(
    "swiftCRT.dll",
    "swiftCore.dll",
    "swiftDispatch.dll",
    "swiftWinSDK.dll",
    "swift_Concurrency.dll",
    "swift_RegexParser.dll",
    "swift_StringProcessing.dll",
    "swiftObservation.dll",
    "swiftSynchronization.dll",
    "BlocksRuntime.dll",
    "dispatch.dll",
    "Foundation.dll",
    "FoundationEssentials.dll",
    "FoundationInternationalization.dll",
    "FoundationNetworking.dll",
    "_FoundationICU.dll"
)
foreach ($dll in $runtimeDlls) {
    $source = Join-Path $swiftRuntime "bin\$dll"
    Assert-PeArchitecture -Path $source -Architecture $architecture
    Copy-Item -LiteralPath $source -Destination $stagingDirectory
}

$swiftBacktrace = Join-Path $swiftRuntime "libexec\swift\swift-backtrace.exe"
Assert-PeArchitecture -Path $swiftBacktrace -Architecture $architecture
Copy-Item -LiteralPath $swiftBacktrace -Destination $stagingDirectory

& "$PSScriptRoot\generate-assets.ps1" -Destination $stagingDirectory
$sdkInventory = Join-Path $installerDirectory "windowsappsdk-$architecture.inventory.txt"
& "$PSScriptRoot\stage-windows-app-sdk.ps1" `
    -Architecture $architecture `
    -Destination $stagingDirectory `
    -InventoryPath $sdkInventory

$sdkPriFiles = Get-Content -LiteralPath $sdkInventory |
    Where-Object { [System.IO.Path]::GetExtension($_) -eq ".pri" } |
    ForEach-Object { Join-Path $stagingDirectory $_ }
New-AppResourceIndex `
    -ResourcesPath $stagingDirectory `
    -AppxManifestPath (Join-Path $stagingDirectory "AppxManifest.xml") `
    -DependencyPriFiles $sdkPriFiles `
    -WorkingDirectory (Join-Path $installerDirectory "pri-input-$architecture") `
    -OutputPath (Join-Path $stagingDirectory "resources.pri")

$bootstrapper = Get-ChildItem -LiteralPath $stagingDirectory -Recurse -File |
    Where-Object { $_.Name -eq "Microsoft.WindowsAppRuntime.Bootstrap.dll" } |
    Select-Object -First 1
if ($bootstrapper) {
    throw "The self-contained package must not contain $($bootstrapper.FullName)."
}

$makeappx = Get-WindowsSdkTool -Name "makeappx.exe"
Invoke-CheckedCommand $makeappx pack /d $stagingDirectory /p $installerFile /o
if (-not (Test-Path -LiteralPath $installerFile)) {
    throw "MSIX packaging did not produce $installerFile."
}

if (-not $CertificateThumbprint) {
    $thumbprintPath = Join-Path $installerDirectory "certificate-thumbprint.txt"
    if (-not (Test-Path -LiteralPath $thumbprintPath)) {
        throw "No signing certificate was supplied. Run Scripts\generate-certificate.ps1 first."
    }
    $CertificateThumbprint = (Get-Content -LiteralPath $thumbprintPath -Raw).Trim()
}
$certificate = Get-Item -LiteralPath "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction SilentlyContinue
if (-not $certificate) {
    throw "Signing certificate $CertificateThumbprint was not found in Cert:\CurrentUser\My."
}
$signtool = Get-WindowsSdkTool -Name "signtool.exe"
Invoke-CheckedCommand $signtool sign /v /fd SHA256 /sha1 $CertificateThumbprint /s My $installerFile

$debugSymbols = Join-Path $buildPath "SwiftBacktraceReproducer.pdb"
if (Test-Path -LiteralPath $debugSymbols) {
    Copy-Item -LiteralPath $debugSymbols -Destination (Join-Path $installerDirectory "SwiftBacktraceReproducer-$architecture.pdb") -Force
}
Write-Host "Created $installerFile"

