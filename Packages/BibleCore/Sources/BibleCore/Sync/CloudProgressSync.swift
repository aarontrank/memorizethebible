import Foundation

/// Keeping one copy of the progress record in the cloud, and this device's copy
/// in step with it (§13.1).
///
/// The whole record goes up as a single value, and coming down it is *merged*
/// rather than swapped in — see `ProgressMerge`. That is what makes the setting
/// safe to leave on: the worst an unlucky moment can do is send the same record
/// twice, never take a memorized verse away.
///
/// This type knows nothing about iCloud itself; it is handed a
/// `CloudProgressStore`. It also knows nothing about the setting that switches
/// it on — the app does not call it when the user has said no.
public final class CloudProgressSync {
    public enum Status: Equatable, Sendable {
        /// Nothing has happened yet.
        case idle
        case synced(at: Date)
        /// Nobody is signed into iCloud on this device.
        case unavailable
        /// The copy in iCloud was written by a newer version of the app. It is
        /// neither adopted nor overwritten: it may hold work this build cannot
        /// even represent. The same rule `ProgressStore` applies to a file on
        /// disk that came from the future.
        case refusedNewerRecord
        /// The record no longer fits in the cloud store.
        case tooLarge
        /// A different iCloud account signed in. Nothing more is read or
        /// written until the app is next launched, so that one account's work
        /// can never be filed under another's.
        case accountChanged
        case failed(String)
    }

    public private(set) var status: Status = .idle

    private let store: CloudProgressStore
    private let clock: any AppClock
    /// The bytes known to be in the cloud, so a push that would say exactly the
    /// same thing is skipped.
    private var lastKnownPayload: Data?
    private var isSuspended = false
    private var isRefusingRemote = false

    public init(store: CloudProgressStore, clock: any AppClock = SystemClock()) {
        self.store = store
        self.clock = clock
    }

    public var isAvailable: Bool { store.isAvailable }

    /// Called when the stored copy changes underneath this device. Passed
    /// straight through to the store, so the app has one thing to talk to.
    public var onRemoteChange: ((CloudProgressChange) -> Void)? {
        get { store.onExternalChange }
        set { store.onExternalChange = newValue }
    }

    /// Asks the store to pick up anything another device has written.
    public func refresh() {
        guard !isSuspended else { return }
        store.refresh()
    }

    /// Merges the copy in iCloud into `local`, returning the record to adopt —
    /// or nil when there is nothing to change.
    public func pull(into local: ProgressSnapshot) -> ProgressSnapshot? {
        guard !isSuspended else { return nil }
        let payload: Data?
        do {
            payload = try store.loadPayload()
        } catch {
            status = .failed(error.localizedDescription)
            return nil
        }
        guard let payload else {
            // Nothing up there yet: this device is the first to sync, which is
            // not a failure and not a reason to hold back its own copy.
            status = store.isAvailable ? .idle : .unavailable
            isRefusingRemote = false
            return nil
        }

        let record: CloudProgressRecord
        do {
            record = try CloudProgressPayload.decode(payload)
        } catch CloudSyncError.newerFormat {
            isRefusingRemote = true
            status = .refusedNewerRecord
            return nil
        } catch {
            status = .failed(error.localizedDescription)
            return nil
        }
        guard !record.isFromNewerSchema else {
            isRefusingRemote = true
            status = .refusedNewerRecord
            return nil
        }

        isRefusingRemote = false
        lastKnownPayload = payload
        status = availableStatus
        let merged = ProgressMerge.merge(local: local, remote: record.snapshot)
        return merged.hasSameContent(as: local) ? nil : merged
    }

    /// Writes `snapshot` to iCloud unless the copy already there says the same
    /// thing.
    public func push(_ snapshot: ProgressSnapshot) {
        guard !isSuspended, !isRefusingRemote else { return }
        let payload: Data
        do {
            payload = try CloudProgressPayload.encode(snapshot)
        } catch let error as CloudSyncError {
            if case .tooLarge = error {
                status = .tooLarge
            } else {
                status = .failed(error.localizedDescription)
            }
            return
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        guard payload != lastKnownPayload else { return }
        do {
            try store.savePayload(payload)
            lastKnownPayload = payload
            status = availableStatus
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Saving to the key-value store succeeds whether or not anyone is signed
    /// into iCloud — it keeps a copy on disk either way — so the store saying
    /// yes is not evidence that anything left the device. Only claim a send
    /// when there was somewhere for it to go.
    private var availableStatus: Status {
        store.isAvailable ? .synced(at: clock.now) : .unavailable
    }

    /// Takes the record out of iCloud, for when the user erases their progress.
    /// Another device that still holds it will put its copy back the next time
    /// it opens, which the reset confirmation says in as many words.
    public func removeStoredCopy() {
        lastKnownPayload = nil
        isRefusingRemote = false
        do {
            try store.removePayload()
            status = store.isAvailable ? .idle : .unavailable
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// What to do about a change that came from somewhere else.
    ///
    /// Everything but an account change is an invitation to pull; an account
    /// change stops this device syncing until it is next launched, because the
    /// store now belongs to a different person.
    @discardableResult
    public func handle(_ change: CloudProgressChange) -> Bool {
        switch change {
        case .updated:
            return true
        case .accountChanged:
            isSuspended = true
            lastKnownPayload = nil
            status = .accountChanged
            return false
        case .quotaExceeded:
            status = .tooLarge
            return false
        }
    }
}
