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
    // Register before competing for the lock, so an early second launch cannot
    // send its reopen request before the winning process has a listener.
    let reopenRequests = AppReopenRequests()
    // A second launch asks the running copy to open its history, then exits
    // before it can register another hotkey or write to the same history.
    let instanceLock: AppInstanceLock
    do {
        guard let acquired = try AppInstanceLock.acquire() else {
            DistributedNotificationCenter.default().postNotificationName(
                AppInstanceLock.reopenNotification, object: nil, userInfo: nil, deliverImmediately: true)
            exit(0)
        }
        instanceLock = acquired
    } catch {
        FileHandle.standardError.write(Data("Cliplet could not establish its instance lock: \(error)\n".utf8))
        exit(1)
    }
    withExtendedLifetime(instanceLock) {
        let application = NSApplication.shared
        let applicationDelegate = AppDelegate()
        applicationDelegate.reopenRequests = reopenRequests
        application.delegate = applicationDelegate
        application.run()
    }
}
