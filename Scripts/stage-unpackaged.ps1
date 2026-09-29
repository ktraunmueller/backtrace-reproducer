<# Stage the self-contained Windows App SDK and PRI beside an unpackaged executable. #>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BuildDirectory,

    [Parameter(Mandatory = $true)]
    [ValidateSet("x64", "arm64")]
    [string]$Architecture
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\windows-sdk-tools.ps1"

$buildPath = [System.IO.Path]::GetFullPath($BuildDirectory)
$manifestPath = Join-Path $buildPath "AppxManifest.xml"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Configured package manifest not found: $manifestPath"
}
[xml]$manifest = Get-Content -LiteralPath $manifestPath
if ($manifest.Package.Identity.ProcessorArchitecture -ne $Architecture) {
    throw "The configured manifest does not target $Architecture."
}

$legacyBootstrapFolder = Join-Path $buildPath "swift-windowsappsdk_CWinAppSDK.resources"
if (Test-Path -LiteralPath $legacyBootstrapFolder) {
    Remove-Item -LiteralPath $legacyBootstrapFolder -Recurse -Force
}
Remove-Item -LiteralPath (Join-Path $buildPath "Microsoft.WindowsAppRuntime.Bootstrap.dll") -Force -ErrorAction SilentlyContinue

$inventoryPath = Join-Path $buildPath "windowsappsdk.inventory.txt"
& "$PSScriptRoot\stage-windows-app-sdk.ps1" `
    -Architecture $Architecture `
    -Destination $buildPath `
    -InventoryPath $inventoryPath

$generatedResources = Join-Path $buildPath "generated-resources"
& "$PSScriptRoot\generate-assets.ps1" -Destination $generatedResources
$sdkPriFiles = Get-Content -LiteralPath $inventoryPath |
    Where-Object { [System.IO.Path]::GetExtension($_) -eq ".pri" } |
    ForEach-Object { Join-Path $buildPath $_ }
New-AppResourceIndex `
    -ResourcesPath $generatedResources `
    -AppxManifestPath $manifestPath `
    -DependencyPriFiles $sdkPriFiles `
    -WorkingDirectory (Join-Path $buildPath ".pri-input-$Architecture") `
    -OutputPath (Join-Path $buildPath "resources.pri")

