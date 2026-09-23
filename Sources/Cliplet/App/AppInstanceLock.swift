import CryptoKit
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

    static let processToken = UUID().uuidString
    static var replacementNotification: Notification.Name {
        Notification.Name("\(AppEnvironment.current.bundleIdentifier).quitForReplacement")
    }

    struct Owner: Codable, Equatable {
        let token: String
        let build: String
    }

    static func buildIdentifier() throws -> String {
        guard let executable = Bundle.main.executableURL else { throw POSIXError(.ENOENT) }
        return SHA256.hash(data: try Data(contentsOf: executable, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func owner(at url: URL = defaultURL) -> Owner? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Owner.self, from: data)
    }

    private let descriptor: Int32

    /// Returns nil when another instance holds the lock.
    static func acquire(at url: URL = defaultURL, build: String = "") throws -> AppInstanceLock? {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(descriptor)
            if failure == EWOULDBLOCK { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        let lock = AppInstanceLock(descriptor: descriptor)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: JSONEncoder().encode(Owner(token: processToken, build: build)))
        return lock
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
    private var replacementObserver: NSObjectProtocol?
    private var replacementDuringLaunch = false
    var onReplacement: (() -> Void)? {
        didSet {
            guard replacementDuringLaunch, let onReplacement else { return }
            replacementDuringLaunch = false
            onReplacement()
        }
    }
    private var requestedDuringLaunch = false
    var onRequest: (() -> Void)? {
        didSet {
            guard requestedDuringLaunch, let onRequest else { return }
            requestedDuringLaunch = false
            onRequest()
        }
    }

    init() {
        replacementObserver = DistributedNotificationCenter.default().addObserver(
            forName: AppInstanceLock.replacementNotification,
            object: AppInstanceLock.processToken, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.receiveReplacement() }
        }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: AppInstanceLock.reopenNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.receive() }
        }
    }

    func receive() {
        if let onRequest { onRequest() } else { requestedDuringLaunch = true }
    }

    func receiveReplacement() {
        if let onReplacement { onReplacement() } else { replacementDuringLaunch = true }
    }

    isolated deinit {
        if let replacementObserver { DistributedNotificationCenter.default().removeObserver(replacementObserver) }
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }
}
