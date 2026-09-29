import CWinRT
import UWP
import WinUI

import Foundation

/// Minimal WinUI application used to reproduce Swift backtrace failures on Windows.
@main
public final class BacktraceReproducerApp: SwiftApplication {
    override public class var windowsAppSdkSelfContained: Bool { true }

    private var window: Window?

    public required init() {
        super.init()
    }

    /// Terminates the process through Swift's fatal-error path.
    @inline(never)
    private static func crashForSwiftBacktraceTesting() -> Never {
        fatalError("Intentional crash for Swift backtrace testing")
    }

    // MARK: - SwiftApplication

    override public func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        super.onLaunched(args)

        let backtraceValue = ProcessInfo.processInfo.environment["SWIFT_BACKTRACE"] ?? "<not set>"

        let panel = StackPanel()
        panel.padding = Thickness(left: 24, top: 24, right: 24, bottom: 24)
        panel.spacing = 16

        let heading = TextBlock()
        heading.text = "Effective SWIFT_BACKTRACE"
        heading.fontSize = 20
        panel.children.append(heading)

        let value = TextBlock()
        value.text = backtraceValue
        value.textWrapping = .wrap
        panel.children.append(value)

        let crashButton = Button()
        crashButton.content = "Crash me"
        crashButton.horizontalAlignment = .left
        crashButton.click.addHandler { _, _ in
            Self.crashForSwiftBacktraceTesting()
        }
        panel.children.append(crashButton)

        let window = Window()
        window.title = "Swift Backtrace Reproducer"
        window.content = panel
        self.window = window
        try! window.activate()
    }
}

