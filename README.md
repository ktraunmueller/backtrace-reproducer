# Swift Backtrace Reproducer for Windows

This repository isolates a failure in which the Swift 6.4 runtime does not create a crash log on Windows even though `SWIFT_BACKTRACE` requests file output. 

The behavior this project is intended to reproduce is: the app receives the exact `SWIFT_BACKTRACE` value, the deliberate `fatalError` terminates it, and no file appears in the requested output directory. 

The corresponding Swift forums thread can be found here: [Trying to get crash backtracing to work on Windows](https://forums.swift.org/t/trying-to-get-crash-backtracing-to-work-on-windows/89054/7).

**Notes:** 

- This repository is modeled after my own app's Windows build, Swift/WinRT startup, self-contained Windows App SDK deployment, and MSIX packaging topology.
- The scripts use the following variables to point to the Swift toolchain:
  - `SWIFT_TOOLCHAIN_PATH` must identify the toolchain's `usr` directory. 
  - `SWIFT_RUNTIME_PATH` must identify the architecture-matched runtime's `usr` directory. The latter is the only setting that needs to change when testing an instrumented replacement runtime.
- The dependencies and exact version of all tools on my system can be found below.
- This project was created with AI assistance.

## Repository layout

Clone this repository and [winrt-monorepo](https://github.com/ktraunmueller/winrt-monorepo) as siblings. CMake adds the latter with `add_subdirectory` and links only `CWinRT`, `UWP`, `WinAppSDK`, `WindowsFoundation`, and `WinUI`.

```text
parent/
├── backtrace-reproducer/
│   ├── Resources/
│   │   ├── AppxManifest.xml.in
│   │   └── SwiftBacktraceReproducer.exe.manifest
│   ├── Scripts/
│   │   ├── report-environment.ps1
│   │   ├── stage-unpackaged.ps1
│   │   ├── stage-windows-app-sdk.ps1
│   │   ├── generate-certificate.ps1
│   │   └── make-msix.ps1
│   ├── Sources/
│   │   ├── BacktraceReproducerApp.swift
│   │   └── WinMain.swift
│   ├── CMakeLists.txt
│   ├── CMakePresets.json
│   └── README.md
└── winrt-monorepo/
    ├── swift-cwinrt/
    ├── swift-uwp/
    ├── swift-windowsappsdk/
    ├── swift-windowsfoundation/
    └── swift-winui/
```

Generated `build/`, `.packages/`, `.tools/`, and `.installer/` folders are intentionally omitted from the tree and ignored by Git.

## Obtain the sources

Run these commands from the directory that will contain both repositories:

```powershell
git clone https://github.com/ktraunmueller/backtrace-reproducer.git
git clone https://github.com/ktraunmueller/winrt-monorepo.git
git -C .\winrt-monorepo checkout f0badd45f0b046deb9d77b36e5b04b86a8a4bb2b
```

Start an x64 Native Tools PowerShell for Visual Studio 2022 for x64 builds. Use the corresponding ARM64 cross-tools environment and architecture-matched Swift installation for ARM64 builds.

## Configure the environment

These were the paths in the reference environment; adjust them for another installation:

```powershell
$env:SWIFT_TOOLCHAIN_PATH = 'C:\Swift\Toolchains\6.4.0+Asserts\usr'
$env:SWIFT_RUNTIME_PATH = 'C:\Swift\Runtimes\6.4.0\usr'
$env:SWIFT_BACKTRACE = 'output-to=C:\tmp\CrashLogs'
New-Item -ItemType Directory -Path 'C:\tmp\CrashLogs' -Force
```

For the installed MSIX test, persist the same backtrace setting before signing out and back in so Explorer and the packaged full-trust process receive it:

```powershell
[Environment]::SetEnvironmentVariable(
    'SWIFT_BACKTRACE',
    'output-to=C:\tmp\CrashLogs',
    'User'
)
```

The read-only report script prints local versions, dependency revisions, Swift runtime file versions, and hashes without changing the installation:

```powershell
pwsh -NoProfile -File .\Scripts\report-environment.ps1
```

To retain the report with the test evidence:

```powershell
pwsh -NoProfile -File .\Scripts\report-environment.ps1 *>&1 |
    Tee-Object -FilePath .\environment-report.txt
```

## Unpackaged reproduction

Build and launch Debug:

```powershell
cmake --preset debug-x64
cmake --build --preset debug-x64
$env:PATH = "$env:SWIFT_RUNTIME_PATH\bin;$env:PATH"
& .\build\debug-x64\SwiftBacktraceReproducer.exe
```

Build and launch RelWithDebInfo:

```powershell
cmake --preset relwithdebinfo-x64
cmake --build --preset relwithdebinfo-x64
$env:PATH = "$env:SWIFT_RUNTIME_PATH\bin;$env:PATH"
& .\build\relwithdebinfo-x64\SwiftBacktraceReproducer.exe
```

Equivalent `release-x64`, `debug-arm64`, `release-arm64`, and `relwithdebinfo-arm64` presets are provided. ARM64 requires ARM64 Swift toolchain/runtime paths and a matching Visual Studio cross-tools environment.

Confirm that the value shown in the window exactly matches the environment setting, then click **Crash me**.

## Packaged self-contained MSIX reproduction

Create a disposable, non-exportable signing certificate in the current user's certificate store and trust its public certificate for the current user. No password, PFX, or private key is written to the repository:

```powershell
pwsh -NoProfile -File .\Scripts\generate-certificate.ps1 -Trust
```

Build, package, sign, and install:

```powershell
cmake --preset relwithdebinfo-x64
cmake --build --preset relwithdebinfo-x64
pwsh -NoProfile -File .\Scripts\make-msix.ps1 `
    -BuildDirectory .\build\relwithdebinfo-x64
Add-AppxPackage -Path .\.installer\SwiftBacktraceReproducer-x64.msix
```

The packaging script validates PE architecture, copies Compositor's Swift and VC runtime DLL set plus `swift-backtrace.exe`, stages the Windows App SDK self-contained payload, generates a merged PRI, confirms that no Windows App Runtime bootstrap DLL is present, then signs the package. The package manifest intentionally has no Windows App Runtime package dependency.

After signing out and back in to refresh the persisted environment, launch without a debugger:

```powershell
$package = Get-AppxPackage -Name SwiftBacktraceReproducer
Start-Process explorer.exe `
    -ArgumentList "shell:AppsFolder\$($package.PackageFamilyName)!SwiftBacktraceReproducer"
```

Verify the displayed setting, start ProcMon if desired, and click **Crash me**. 

## Substituting an instrumented runtime

Point `SWIFT_RUNTIME_PATH` at the instrumented runtime's `usr` directory, prepend its `bin` directory to `PATH` for unpackaged execution, and rebuild the MSIX for packaged execution. No source or CMake change is required:

```powershell
$env:SWIFT_RUNTIME_PATH = 'C:\path\to\instrumented-runtime\usr'
$env:PATH = "$env:SWIFT_RUNTIME_PATH\bin;$env:PATH"
```

The package script will reject a runtime whose `swiftCore.dll` or `swift-backtrace.exe` architecture does not match the configured package.

## Minimum requirements

- Windows 11 on x64 or ARM64.
- CMake 3.29 or newer and Ninja.
- A Swift for Windows toolchain and matching Swift runtime.
- Visual Studio 2022 with the C++ desktop workload.
- A Windows 10/11 SDK containing MakeAppx, MakePri, MT, and SignTool.
- PowerShell 7 (Windows PowerShell also works for build scripts).
- Git and network access for the pinned NuGet package restore.

## Exact reference environment

Here's a list of installed dependencies on my system that reproduces the problem: 

| Component | Exact version |
|---|---|
| Operating system | Windows 11 25H2, build `26200.9457`, x64 |
| Swift distribution | `swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-09-26-a-windows10` |
| Swift toolchain identifier | `swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-09-26-a.Asserts` |
| Swift toolchain version | `6.4.0` |
| Swift runtime / swift-backtrace | `6.4.4.160` |
| Clang | `21.1.6`, target `x86_64-unknown-windows-msvc`, assertions enabled |
| CMake | minimum `3.29`; tested with `4.0.0` |
| Ninja | `1.12.1` |
| Visual Studio Community 2022 | `17.13.5` (`17.13.35919.96`) |
| MSVC tools / linker | `14.43.34808` / `14.43.34809.0` |
| Windows SDK | `10.0.22621.0` |
| MakeAppx / MakePri / RC product version | `10.0.22621.3233` |
| PowerShell | `7.6.5` |
| Git for Windows | `2.52.0.windows.1` |
| NuGet CLI | `7.9.0` (fixed download URL in the staging script) |
| Windows App SDK package | `1.7.250606001` |
| Windows SDK Contracts package | `10.0.18362.2005` |
| swift-winrt projection | `0.6.0` |
| winrt-monorepo revision | `f0badd45f0b046deb9d77b36e5b04b86a8a4bb2b` |
