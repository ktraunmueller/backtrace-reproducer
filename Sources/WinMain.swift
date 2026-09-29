import WinSDK

import WinUI

/// Windows GUI subsystem entry point that forwards to Swift's generated application entry point.
@_cdecl("wWinMain")
public func wWinMain(
    _ hInstance: HINSTANCE?,
    _ hPrevInstance: HINSTANCE?,
    _ lpCmdLine: PWSTR?,
    _ nCmdShow: INT32
) -> INT32 {
    BacktraceReproducerApp.main()
    return 0
}

