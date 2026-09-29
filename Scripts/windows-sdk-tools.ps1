<# Shared Windows SDK tool discovery, command execution, PRI, and PE helpers. #>

function Get-WindowsSdkTool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    if (-not (Test-Path -LiteralPath $kitsRoot)) {
        throw "Windows SDK tools directory not found: $kitsRoot"
    }

    $requiredTools = @("makeappx.exe", "makepri.exe", "mt.exe", "signtool.exe")
    $sdkVersions = Get-ChildItem -LiteralPath $kitsRoot -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending
    foreach ($sdkVersion in $sdkVersions) {
        $toolFolder = Join-Path $sdkVersion.FullName "x64"
        $missingTool = $requiredTools | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path $toolFolder $_))
        } | Select-Object -First 1
        if (-not $missingTool) {
            return Join-Path $toolFolder $Name
        }
    }
    throw "A complete Windows SDK packaging toolset containing $Name was not found."
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE."
    }
}

function New-AppResourceIndex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourcesPath,

        [Parameter(Mandatory = $true)]
        [string]$AppxManifestPath,

        [Parameter(Mandatory = $true)]
        [string[]]$DependencyPriFiles,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    if (Test-Path -LiteralPath $WorkingDirectory) {
        Remove-Item -LiteralPath $WorkingDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $WorkingDirectory | Out-Null
    try {
        Copy-Item -LiteralPath (Join-Path $ResourcesPath "Assets") -Destination $WorkingDirectory -Recurse
        $workingManifest = Join-Path $WorkingDirectory "AppxManifest.xml"
        Copy-Item -LiteralPath $AppxManifestPath -Destination $workingManifest
        foreach ($priFile in $DependencyPriFiles) {
            if (-not (Test-Path -LiteralPath $priFile)) {
                throw "Dependency PRI file not found: $priFile"
            }
            Copy-Item -LiteralPath $priFile -Destination $WorkingDirectory
        }

        $configPath = Join-Path $WorkingDirectory "priconfig.xml"
        $makepri = Get-WindowsSdkTool -Name "makepri.exe"
        Invoke-CheckedCommand $makepri createconfig /cf $configPath /dq en-US /pv 10.0.0 /o
        [xml]$priConfig = Get-Content -LiteralPath $configPath
        $priConfig.resources.packaging.RemoveAll()
        $priConfig.Save($configPath)
        Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
        Invoke-CheckedCommand $makepri new /pr $WorkingDirectory /cf $configPath /mn $workingManifest /of $OutputPath /o
        if (-not (Test-Path -LiteralPath $OutputPath)) {
            throw "PRI generation did not produce $OutputPath."
        }
    } finally {
        Remove-Item -LiteralPath $WorkingDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-PeArchitecture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $reader = [System.IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5A4D) {
            throw "$Path is not a PE file."
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadUInt32()
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "$Path has an invalid PE header."
        }
        $machine = $reader.ReadUInt16()
        if ($machine -eq 0x8664) {
            return "x64"
        }
        if ($machine -eq 0xAA64) {
            return "arm64"
        }
        throw "Unsupported PE machine type 0x$($machine.ToString('X4')) in $Path."
    } finally {
        $stream.Dispose()
    }
}

function Assert-PeArchitecture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet("x64", "arm64")]
        [string]$Architecture
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required binary not found: $Path"
    }
    $actualArchitecture = Get-PeArchitecture -Path $Path
    if ($actualArchitecture -ne $Architecture) {
        throw "$Path targets $actualArchitecture, but the requested build targets $Architecture."
    }
}

