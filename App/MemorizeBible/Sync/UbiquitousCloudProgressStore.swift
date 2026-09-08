import BibleCore
import Foundation

/// The real cloud store: one value in the user's own iCloud key-value store
/// (§13.1).
///
/// Key-value storage rather than a CloudKit database or a document in a
/// ubiquity container, because the progress record is already exactly what this
/// store wants — one small blob, written whole, last writer wins. It brings no
/// schema to keep in step with a server, no account to sign into beyond the one
/// the device already has, and no file coordination. What it does bring is a
/// 1 MB ceiling, which `CloudProgressPayload` answers by compressing: the whole
/// Bible memorized still comes to a fraction of it.
///
/// Nothing is read or written until the app asks. If iCloud is switched off in
/// Settings, this object is never built.
final class UbiquitousCloudProgressStore: CloudProgressStore {
    /// Versioned in the key, so a future format that cannot be read by this one
    /// can be given its own home rather than made to share.
    private static let payloadKey = "progress.v1"

    private let store: NSUbiquitousKeyValueStore
    private var isReachable = true
    private var observer: NSObjectProtocol?

    var onExternalChange: ((CloudProgressChange) -> Void)?

    init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
        // Delivered on the main queue, because everything downstream of it
        // touches the app's state.
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] notification in
            self?.storeChangedExternally(notification)
        }
        refresh()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// `synchronize()` is the honest answer to "is there anywhere to sync to":
    /// it returns false when the iCloud entitlement is missing or iCloud is
    /// unavailable on the device. Asking `FileManager` for a ubiquity token
    /// would be answering a different question — that one is about iCloud
    /// Drive, which this app does not use.
    var isAvailable: Bool { isReachable }

    func loadPayload() throws -> Data? { store.data(forKey: Self.payloadKey) }

    func savePayload(_ data: Data) throws {
        store.set(data, forKey: Self.payloadKey)
        refresh()
    }

    func removePayload() throws {
        store.removeObject(forKey: Self.payloadKey)
        refresh()
    }

    func refresh() {
        isReachable = store.synchronize()
    }

    private func storeChangedExternally(_ notification: Notification) {
        // A notification with no reason at all is treated as an ordinary change
        // from another device, which is the one it would be.
        let reason =
            notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            ?? NSUbiquitousKeyValueStoreServerChange
        let changedKeys =
            notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]

        let change: CloudProgressChange
        switch reason {
        case NSUbiquitousKeyValueStoreAccountChange:
            change = .accountChanged
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            change = .quotaExceeded
        default:
            // Server change or first sync. Anything else in the store is not
            // ours to react to.
            guard changedKeys?.contains(Self.payloadKey) ?? true else { return }
            change = .updated
        }

        onExternalChange?(change)
    }
}
