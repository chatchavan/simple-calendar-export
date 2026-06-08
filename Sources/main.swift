import AppKit
import SwiftUI

// CLI mode: any recognized flag present → headless, no GUI
let cliFlags = ["--list", "--start", "--end", "--format", "--output"]
let isCLI = CommandLine.arguments.dropFirst().contains(where: { cliFlags.contains($0) })

if isCLI {
    CLIRunner().run()
    exit(0)
}

// GUI mode
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
