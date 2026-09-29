<# Print a read-only inventory of the local reproducing environment. #>

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "== $Title =="
}

function Invoke-VersionCommand {
    param(
        [string]$Name,
        [string]$Command,
        [string[]]$Arguments = @()
    )

    if (-not $Command -or -not (Test-Path -LiteralPath $Command -PathType Leaf)) {
        $resolved = Get-Command $Command -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
        if (-not $resolved) {
            Write-Host "${Name}: not found"
            return
        }
        $Command = $resolved
    }
    Write-Host "${Name}:"
    & $Command @Arguments 2>&1 | ForEach-Object { Write-Host "  $_" }
}

function Write-BinaryReport {
    param(
        [string]$Name,
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Host "${Name}: not found ($Path)"
        return
    }
    $item = Get-Item -LiteralPath $Path
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    Write-Host "$Name"
    Write-Host "  Path: $Path"
    Write-Host "  File version: $($item.VersionInfo.FileVersion)"
    Write-Host "  Product version: $($item.VersionInfo.ProductVersion)"
    Write-Host "  SHA-256: $hash"
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$winrtMonorepo = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot "..\winrt-monorepo"))

Write-Section "Operating system"
$windows = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$productName = $windows.ProductName
if ([int]$windows.CurrentBuild -ge 22000) {
    $productName = $productName -replace "Windows 10", "Windows 11"
}
Write-Host "Product: $productName"
Write-Host "Display version: $($windows.DisplayVersion)"
Write-Host "Build: $($windows.CurrentBuild).$($windows.UBR)"
Write-Host "Process architecture: $env:PROCESSOR_ARCHITECTURE"

Write-Section "Environment"
Write-Host "SWIFT_TOOLCHAIN_PATH=$env:SWIFT_TOOLCHAIN_PATH"
Write-Host "SWIFT_RUNTIME_PATH=$env:SWIFT_RUNTIME_PATH"
Write-Host "SWIFT_BACKTRACE=$env:SWIFT_BACKTRACE"

Write-Section "Swift toolchain metadata"
if ($env:SWIFT_TOOLCHAIN_PATH) {
    $toolchainRoot = [System.IO.Path]::GetFullPath((Join-Path $env:SWIFT_TOOLCHAIN_PATH ".."))
    $toolchainInfoPath = Join-Path $toolchainRoot "ToolchainInfo.plist"
    if (Test-Path -LiteralPath $toolchainInfoPath) {
        [xml]$toolchainInfo = Get-Content -LiteralPath $toolchainInfoPath
        $entries = $toolchainInfo.plist.dict.ChildNodes
        for ($index = 0; $index -lt $entries.Count - 1; $index++) {
            if ($entries[$index].Name -eq "key" -and $entries[$index].InnerText -in @("Identifier", "Version")) {
                Write-Host "$($entries[$index].InnerText): $($entries[$index + 1].InnerText)"
            }
        }
    } else {
        Write-Host "ToolchainInfo.plist: not found ($toolchainInfoPath)"
    }
    Invoke-VersionCommand "Clang" (Join-Path $env:SWIFT_TOOLCHAIN_PATH "bin\clang.exe") @("--version")
    Write-BinaryReport "swiftc.exe" (Join-Path $env:SWIFT_TOOLCHAIN_PATH "bin\swiftc.exe")
} else {
    Write-Host "SWIFT_TOOLCHAIN_PATH is not set."
}

Write-Section "Swift runtime"
if ($env:SWIFT_RUNTIME_PATH) {
    Write-BinaryReport "swiftCore.dll" (Join-Path $env:SWIFT_RUNTIME_PATH "bin\swiftCore.dll")
    Write-BinaryReport "swift-backtrace.exe" (Join-Path $env:SWIFT_RUNTIME_PATH "libexec\swift\swift-backtrace.exe")
} else {
    Write-Host "SWIFT_RUNTIME_PATH is not set."
}

Write-Section "Build tools"
Invoke-VersionCommand "CMake" "cmake.exe" @("--version")
Invoke-VersionCommand "PowerShell" "pwsh.exe" @("--version")
Invoke-VersionCommand "Git" "git.exe" @("--version")
$nuget = Join-Path $repositoryRoot ".tools\nuget-7.9.0.exe"
if (Test-Path -LiteralPath $nuget) {
    Write-Host "NuGet: $((Get-Item -LiteralPath $nuget).VersionInfo.ProductVersion) ($nuget)"
} else {
    Write-Host "NuGet: not restored yet (expected 7.9.0 at $nuget)"
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path -LiteralPath $vswhere) {
    Write-Host "Visual Studio:"
    & $vswhere -latest -products '*' -format json | Write-Host
    $visualStudioPath = & $vswhere -latest -products '*' -property installationPath
    $ninja = Join-Path $visualStudioPath "Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
    Invoke-VersionCommand "Ninja" $ninja @("--version")
    $msvcDirectory = Get-ChildItem -LiteralPath (Join-Path $visualStudioPath "VC\Tools\MSVC") -Directory |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    if ($msvcDirectory) {
        Write-Host "MSVC tools directory: $($msvcDirectory.Name)"
        $linker = Join-Path $msvcDirectory.FullName "bin\Hostx64\x64\link.exe"
        if (Test-Path -LiteralPath $linker) {
            Write-Host "MSVC linker product version: $((Get-Item -LiteralPath $linker).VersionInfo.ProductVersion)"
        }
    }
} else {
    Invoke-VersionCommand "Ninja" "ninja.exe" @("--version")
}

Write-Section "Windows SDK tools"
$sdkToolDirectory = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin\10.0.22621.0\x64"
foreach ($tool in @("makeappx.exe", "makepri.exe", "rc.exe")) {
    $path = Join-Path $sdkToolDirectory $tool
    if (Test-Path -LiteralPath $path) {
        $version = (Get-Item -LiteralPath $path).VersionInfo.ProductVersion
        Write-Host "${tool}: $version ($path)"
    } else {
        Write-Host "${tool}: not found ($path)"
    }
}

Write-Section "Dependency revisions"
if (Test-Path -LiteralPath (Join-Path $winrtMonorepo ".git")) {
    Write-Host "winrt-monorepo: $(& git.exe -c "safe.directory=$winrtMonorepo" -C $winrtMonorepo rev-parse HEAD)"
    Write-Host "winrt-monorepo status: $(& git.exe -c "safe.directory=$winrtMonorepo" -C $winrtMonorepo status --short)"
    $projectionPath = Join-Path $winrtMonorepo "swift-windowsappsdk\projections.json"
    if (Test-Path -LiteralPath $projectionPath) {
        $projection = Get-Content -LiteralPath $projectionPath -Raw | ConvertFrom-Json
        Write-Host "swift-winrt projection: $($projection.'swift-winrt')"
        Write-Host "Windows App SDK package: $($projection.package.version)"
        foreach ($dependency in $projection.dependencies) {
            Write-Host "$($dependency.id): $($dependency.version)"
        }
    }
} else {
    Write-Host "winrt-monorepo: not found ($winrtMonorepo)"
}

