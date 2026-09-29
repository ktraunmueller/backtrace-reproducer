cmake_minimum_required(VERSION 3.29)
project(SwiftBacktraceReproducer LANGUAGES C CXX Swift)

if(NOT DEFINED ENV{SWIFT_TOOLCHAIN_PATH} OR "$ENV{SWIFT_TOOLCHAIN_PATH}" STREQUAL "")
    message(FATAL_ERROR "SWIFT_TOOLCHAIN_PATH must point to the Swift toolchain usr directory.")
endif()
if(NOT DEFINED ENV{SWIFT_RUNTIME_PATH} OR "$ENV{SWIFT_RUNTIME_PATH}" STREQUAL "")
    message(FATAL_ERROR "SWIFT_RUNTIME_PATH must point to the Swift runtime usr directory.")
endif()

file(TO_CMAKE_PATH "$ENV{SWIFT_TOOLCHAIN_PATH}" SWIFT_TOOLCHAIN_PATH)
file(TO_CMAKE_PATH "$ENV{SWIFT_RUNTIME_PATH}" SWIFT_RUNTIME_PATH)
set(EXPECTED_SWIFT_COMPILER "${SWIFT_TOOLCHAIN_PATH}/bin/swiftc.exe")
if(NOT EXISTS "${EXPECTED_SWIFT_COMPILER}")
    message(FATAL_ERROR "Swift compiler not found: ${EXPECTED_SWIFT_COMPILER}")
endif()
if(NOT CMAKE_Swift_COMPILER STREQUAL EXPECTED_SWIFT_COMPILER)
    message(FATAL_ERROR
        "CMake selected '${CMAKE_Swift_COMPILER}', but SWIFT_TOOLCHAIN_PATH selects "
        "'${EXPECTED_SWIFT_COMPILER}'. Configure with the supplied presets.")
endif()
if(NOT EXISTS "${SWIFT_RUNTIME_PATH}/bin/swiftCore.dll")
    message(FATAL_ERROR "Swift runtime not found under SWIFT_RUNTIME_PATH: ${SWIFT_RUNTIME_PATH}")
endif()
if(NOT EXISTS "${SWIFT_RUNTIME_PATH}/libexec/swift/swift-backtrace.exe")
    message(FATAL_ERROR "swift-backtrace.exe not found under SWIFT_RUNTIME_PATH: ${SWIFT_RUNTIME_PATH}")
endif()

if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(AMD64|amd64|x86_64)$")
    set(REPRODUCER_ARCHITECTURE "x64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(ARM64|arm64|aarch64)$")
    set(REPRODUCER_ARCHITECTURE "arm64")
else()
    message(FATAL_ERROR "Unsupported architecture: ${CMAKE_SYSTEM_PROCESSOR}")
endif()

set(CMAKE_Swift_LANGUAGE_VERSION 5)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_STATIC_LIBRARY_PREFIX "lib")

set(CMAKE_Swift_FLAGS_DEBUG
    "-DDEBUG -Onone -g -use-ld=lld -diagnostic-style=llvm -Xlinker /DEBUG:FULL -Xlinker -debug:dwarf"
)
set(CMAKE_CXX_FLAGS_DEBUG "-g -Og")
set(CMAKE_C_FLAGS_DEBUG "-g -Og")
set(CMAKE_EXE_LINKER_FLAGS_DEBUG "-fuse-ld=lld -Wl,/DEBUG:FULL")

set(CMAKE_Swift_FLAGS_RELEASE
    "-O -whole-module-optimization -use-ld=lld -Xlinker /INCREMENTAL:NO"
)
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -DNDEBUG")
set(CMAKE_C_FLAGS_RELEASE "-O3 -DNDEBUG")
set(CMAKE_EXE_LINKER_FLAGS_RELEASE "-fuse-ld=lld -Wl,/INCREMENTAL:NO")

set(CMAKE_Swift_FLAGS_RELWITHDEBINFO
    "-O -g -debug-info-format=codeview -whole-module-optimization -use-ld=lld -diagnostic-style=llvm -Xlinker /DEBUG:FULL"
)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO "-g -O2 -DNDEBUG")
set(CMAKE_C_FLAGS_RELWITHDEBINFO "-g -O2 -DNDEBUG")
set(CMAKE_EXE_LINKER_FLAGS_RELWITHDEBINFO "-fuse-ld=lld -Wl,/DEBUG:FULL,/INCREMENTAL:NO")

configure_file(
    Resources/AppxManifest.xml.in
    ${CMAKE_BINARY_DIR}/AppxManifest.xml
    @ONLY
)

find_program(POWERSHELL_EXECUTABLE NAMES pwsh powershell REQUIRED)

add_executable(SwiftBacktraceReproducer
    Sources/BacktraceReproducerApp.swift
    Sources/WinMain.swift
)
set_target_properties(SwiftBacktraceReproducer PROPERTIES
    Swift_MODULE_NAME SwiftBacktraceReproducer
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)
target_compile_options(SwiftBacktraceReproducer PRIVATE
    -cxx-interoperability-mode=default
    -parse-as-library
)
target_link_options(SwiftBacktraceReproducer PRIVATE
    -Xlinker /SUBSYSTEM:WINDOWS
)

add_subdirectory(
    "${CMAKE_CURRENT_SOURCE_DIR}/../winrt-monorepo"
    "${CMAKE_BINARY_DIR}/winrt-monorepo-build"
    EXCLUDE_FROM_ALL
)
target_link_libraries(SwiftBacktraceReproducer PRIVATE
    CWinRT
    UWP
    WinAppSDK
    WindowsFoundation
    WinUI
)

add_custom_command(TARGET SwiftBacktraceReproducer POST_BUILD
    COMMAND "${POWERSHELL_EXECUTABLE}"
            -NoProfile
            -ExecutionPolicy Bypass
            -File "${CMAKE_CURRENT_SOURCE_DIR}/Scripts/stage-unpackaged.ps1"
            -BuildDirectory "${CMAKE_BINARY_DIR}"
            -Architecture "${REPRODUCER_ARCHITECTURE}"
    COMMENT "Staging the self-contained Windows App SDK"
    VERBATIM
)

