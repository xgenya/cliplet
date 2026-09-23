import Darwin
import Foundation

/// A kernel lock is released even if the process crashes. The path is shared by
/// every copy of the same build running in this user's temporary directory.
final class AppInstanceLock {
    static var defaultURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppEnvironment.current.bundleIdentifier).instance.lock")
    }

    static var reopenNotification: Notification.Name {
        Notification.Name("\(AppEnvironment.current.bundleIdentifier).showHistory")
    }

    private let descriptor: Int32

    /// Returns nil when another instance holds the lock.
    static func acquire(at url: URL = defaultURL) throws -> AppInstanceLock? {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(descriptor)
            if failure == EWOULDBLOCK { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        return AppInstanceLock(descriptor: descriptor)
    }

    private init(descriptor: Int32) { self.descriptor = descriptor }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

@MainActor
final class AppReopenRequests {
    private var observer: NSObjectProtocol?
    private var requestedDuringLaunch = false
    var onRequest: (() -> Void)? {
        didSet {
            guard requestedDuringLaunch, let onRequest else { return }
            requestedDuringLaunch = false
            onRequest()
        }
    }

    init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: AppInstanceLock.reopenNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.receive() }
        }
    }

    func receive() {
        if let onRequest { onRequest() } else { requestedDuringLaunch = true }
    }

    isolated deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }
}
