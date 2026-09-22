import AppKit

MainActor.assumeIsolated {
    if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
        do {
            try AppSmokeTest.run()
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Cliplet package smoke test failed: \(error)\n".utf8))
            exit(1)
        }
    }
    let application = NSApplication.shared
    let applicationDelegate = AppDelegate()
    application.delegate = applicationDelegate
    application.run()
}
