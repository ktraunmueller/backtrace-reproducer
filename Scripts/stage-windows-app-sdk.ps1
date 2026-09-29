<# Restore and stage the Windows App SDK package pinned by winrt-monorepo. #>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("x64", "arm64")]
    [string]$Architecture,

    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [string]$ApplicationManifest = (Join-Path $PSScriptRoot "..\Resources\SwiftBacktraceReproducer.exe.manifest"),

    [string]$InventoryPath
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\windows-sdk-tools.ps1"

function ConvertTo-XmlAttributeValue {
    param([string]$Value)
    return [System.Security.SecurityElement]::Escape($Value)
}

function New-WindowsAppSdkRegistrationManifest {
    param(
        [Parameter(Mandatory = $true)]
        [xml]$AppxManifest,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $namespaceManager = [System.Xml.XmlNamespaceManager]::new($AppxManifest.NameTable)
    $namespaceManager.AddNamespace("m", "http://schemas.microsoft.com/appx/manifest/foundation/windows10")
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine("<?xml version=`"1.0`" encoding=`"utf-8`" standalone=`"yes`"?>")
    [void]$builder.AppendLine("<assembly manifestVersion=`"1.0`"")
    [void]$builder.AppendLine("          xmlns:asmv3=`"urn:schemas-microsoft-com:asm.v3`"")
    [void]$builder.AppendLine("          xmlns:winrtv1=`"urn:schemas-microsoft-com:winrt.v1`"")
    [void]$builder.AppendLine("          xmlns=`"urn:schemas-microsoft-com:asm.v1`">")

    foreach ($server in $AppxManifest.SelectNodes("//m:InProcessServer", $namespaceManager)) {
        $dllPath = ConvertTo-XmlAttributeValue $server.SelectSingleNode("m:Path", $namespaceManager).InnerText
        if ($dllPath -eq "Microsoft.UI.Xaml.Phone.dll") {
            continue
        }
        [void]$builder.AppendLine("  <asmv3:file name=`"$dllPath`">")
        foreach ($activatableClass in $server.SelectNodes("m:ActivatableClass", $namespaceManager)) {
            $className = ConvertTo-XmlAttributeValue $activatableClass.GetAttribute("ActivatableClassId")
            [void]$builder.AppendLine("    <winrtv1:activatableClass name=`"$className`" threadingModel=`"both`" />")
        }
        [void]$builder.AppendLine("  </asmv3:file>")
    }

    foreach ($proxyStub in $AppxManifest.SelectNodes("//m:ProxyStub", $namespaceManager)) {
        $dllPath = $proxyStub.SelectSingleNode("m:Path", $namespaceManager).InnerText
        if ($dllPath -in @("PushNotificationsLongRunningTask.ProxyStub.dll", "Microsoft.Windows.Widgets.dll")) {
            continue
        }
        $escapedDllPath = ConvertTo-XmlAttributeValue $dllPath
        $classId = ConvertTo-XmlAttributeValue $proxyStub.GetAttribute("ClassId")
        [void]$builder.AppendLine("  <asmv3:file name=`"$escapedDllPath`">")
        [void]$builder.AppendLine("    <asmv3:comClass clsid=`"{$classId}`" />")
        foreach ($interface in $proxyStub.SelectNodes("m:Interface", $namespaceManager)) {
            $name = ConvertTo-XmlAttributeValue $interface.GetAttribute("Name")
            $interfaceId = ConvertTo-XmlAttributeValue $interface.GetAttribute("InterfaceId")
            [void]$builder.AppendLine("    <asmv3:comInterfaceProxyStub name=`"$name`" iid=`"{$interfaceId}`" />")
        }
        [void]$builder.AppendLine("  </asmv3:file>")
    }
    [void]$builder.AppendLine("</assembly>")
    [System.IO.File]::WriteAllText($Path, $builder.ToString(), [System.Text.UTF8Encoding]::new($false))
}

$destinationPath = [System.IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$winrtMonorepo = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot "..\winrt-monorepo"))
$projectionsPath = Join-Path $winrtMonorepo "swift-windowsappsdk\projections.json"
if (-not (Test-Path -LiteralPath $projectionsPath)) {
    throw "swift-windowsappsdk projections not found: $projectionsPath"
}
$projections = Get-Content -LiteralPath $projectionsPath -Raw | ConvertFrom-Json
$packageId = $projections.package.id
$packageVersion = $projections.package.version
if ($packageVersion -ne "1.7.250606001") {
    throw "Expected Windows App SDK 1.7.250606001, but winrt-monorepo pins $packageVersion."
}

$toolsDirectory = Join-Path $repositoryRoot ".tools"
$nuget = Join-Path $toolsDirectory "nuget-7.9.0.exe"
if (-not (Test-Path -LiteralPath $nuget)) {
    New-Item -ItemType Directory -Path $toolsDirectory -Force | Out-Null
    Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/v7.9.0/nuget.exe" -OutFile $nuget
}
$nugetVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($nuget).ProductVersion
if ($nugetVersion -notlike "7.9.0*") {
    throw "Expected NuGet 7.9.0, but $nuget reports $nugetVersion."
}

$packageCache = Join-Path $repositoryRoot ".packages"
$packageRoot = Join-Path $packageCache "$packageId.$packageVersion"
if (-not (Test-Path -LiteralPath $packageRoot)) {
    New-Item -ItemType Directory -Path $packageCache -Force | Out-Null
    Invoke-CheckedCommand $nuget install $packageId -Version $packageVersion -OutputDirectory $packageCache -NonInteractive -DirectDownload
}
if (-not (Test-Path -LiteralPath $packageRoot)) {
    throw "NuGet restore did not produce $packageRoot."
}

$versionInfo = Get-Content -LiteralPath (Join-Path $packageRoot "WindowsAppSDK-VersionInfo.json") -Raw | ConvertFrom-Json
$expectedFrameworkName = ($versionInfo.Runtime.Packages.Framework.PackageFamilyName -split '_')[0]
$expectedRuntimeVersion = $versionInfo.Runtime.Version.String
$msixDirectory = Join-Path $packageRoot "tools\MSIX\win10-$Architecture"
$frameworkMsix = Get-ChildItem -LiteralPath $msixDirectory -File |
    Where-Object { $_.Name -match '^Microsoft\.WindowsAppRuntime\.\d+\.\d+\.msix$' } |
    Select-Object -First 1
if (-not $frameworkMsix) {
    throw "The $Architecture Windows App SDK framework package was not found in $msixDirectory."
}

$workingDirectory = Join-Path $packageCache "self-contained-$packageVersion-$Architecture"
if (Test-Path -LiteralPath $workingDirectory) {
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $workingDirectory | Out-Null
$makeappx = Get-WindowsSdkTool -Name "makeappx.exe"
Invoke-CheckedCommand $makeappx unpack /p $frameworkMsix.FullName /d $workingDirectory /o

$sdkAppxManifestPath = Join-Path $workingDirectory "AppxManifest.xml"
[xml]$sdkAppxManifest = Get-Content -LiteralPath $sdkAppxManifestPath
$sdkIdentity = $sdkAppxManifest.Package.Identity
if ($sdkIdentity.Name -ne $expectedFrameworkName -or $sdkIdentity.Version -ne $expectedRuntimeVersion) {
    throw "The restored framework package identity or version does not match WindowsAppSDK-VersionInfo.json."
}
if ($sdkIdentity.ProcessorArchitecture -ne $Architecture) {
    throw "Framework package targets '$($sdkIdentity.ProcessorArchitecture)', not '$Architecture'."
}

if ($InventoryPath -and (Test-Path -LiteralPath $InventoryPath)) {
    foreach ($relativePath in Get-Content -LiteralPath $InventoryPath) {
        $oldFile = Join-Path $destinationPath $relativePath
        if (Test-Path -LiteralPath $oldFile -PathType Leaf) {
            Remove-Item -LiteralPath $oldFile -Force
        }
    }
}

$payloadExtensions = @(".dll", ".winmd", ".pri", ".mui", ".png", ".xaml", ".xbf")
$excludedPayloadNames = @(
    "Microsoft.UI.Xaml.Phone.dll",
    "Microsoft.UI.Xaml.Phone.dll.mui",
    "Microsoft.WindowsAppRuntime.Bootstrap.dll"
)
$stagedFiles = [System.Collections.Generic.List[string]]::new()
foreach ($file in Get-ChildItem -LiteralPath $workingDirectory -Recurse -File) {
    $relativePath = $file.FullName.Substring($workingDirectory.Length).TrimStart('\', '/')
    $includeNamedFile = $file.Name -like "workloads*.json" -or
        $file.Name -eq "RestartAgent.exe" -or
        $file.Name -eq "map.html"
    if ($file.Name -in $excludedPayloadNames -or
        $relativePath -eq "resources.pri" -or
        ($file.Extension -notin $payloadExtensions -and -not $includeNamedFile)) {
        continue
    }
    $destinationFile = Join-Path $destinationPath $relativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destinationFile) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destinationFile -Force
    $stagedFiles.Add($relativePath)
}

foreach ($requiredFile in @("Microsoft.WindowsAppRuntime.dll", "Microsoft.UI.Xaml.dll", "Microsoft.UI.pri", "Microsoft.UI.Xaml.Controls.pri")) {
    if (-not (Test-Path -LiteralPath (Join-Path $destinationPath $requiredFile))) {
        throw "Required self-contained Windows App SDK payload is missing: $requiredFile"
    }
}
Assert-PeArchitecture -Path (Join-Path $destinationPath "Microsoft.WindowsAppRuntime.dll") -Architecture $Architecture

$registrationManifest = Join-Path $workingDirectory "WindowsAppSDK.manifest"
New-WindowsAppSdkRegistrationManifest -AppxManifest $sdkAppxManifest -Path $registrationManifest
$mergedManifest = Join-Path $destinationPath "SwiftBacktraceReproducer.exe.manifest"
$mt = Get-WindowsSdkTool -Name "mt.exe"
Invoke-CheckedCommand $mt -nologo -manifest $ApplicationManifest $registrationManifest "-out:$mergedManifest"
if (-not (Test-Path -LiteralPath $mergedManifest)) {
    throw "Failed to generate the merged application manifest: $mergedManifest"
}

if ($InventoryPath) {
    $inventoryDirectory = Split-Path -Parent $InventoryPath
    if ($inventoryDirectory) {
        New-Item -ItemType Directory -Path $inventoryDirectory -Force | Out-Null
    }
    $stagedFiles.Add("SwiftBacktraceReproducer.exe.manifest")
    Set-Content -LiteralPath $InventoryPath -Value ($stagedFiles | Sort-Object -Unique) -Encoding utf8
}

