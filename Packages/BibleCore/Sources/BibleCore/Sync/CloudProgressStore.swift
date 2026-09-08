import Foundation

/// Somewhere the progress record can be left for the user's other devices to
/// find (§13.1).
///
/// Deliberately a protocol over raw bytes. Everything that decides *what* is
/// written and *how two copies are reconciled* lives in this module, where it
/// runs in milliseconds with no iCloud account, no network and no simulator;
/// the app supplies the one implementation that actually talks to iCloud.
public protocol CloudProgressStore: AnyObject {
    /// False when there is nowhere to sync to — nobody signed into iCloud on
    /// this device, most often. Reading and writing stay safe either way; this
    /// is for telling the user why nothing is arriving.
    var isAvailable: Bool { get }

    /// The copy currently in the cloud, or nil if there has never been one.
    func loadPayload() throws -> Data?
    func savePayload(_ data: Data) throws
    /// Removes the copy entirely, for when the user erases their progress.
    func removePayload() throws

    /// Asks the store to pick up anything another device has written. Cheap and
    /// safe to call on every launch.
    func refresh()

    /// Called when the stored copy changes underneath us.
    var onExternalChange: ((CloudProgressChange) -> Void)? { get set }
}

/// Why the stored copy changed without this device writing it.
public enum CloudProgressChange: Equatable, Sendable {
    /// Another device wrote a copy, or the first sync of this launch brought
    /// one down.
    case updated
    /// A different iCloud account is signed in now, so what is in the store
    /// belongs to somebody else and must not be merged into this device's work.
    case accountChanged
    /// The store is full. What was last written may not have arrived.
    case quotaExceeded
}

public enum CloudSyncError: LocalizedError, Equatable {
    /// The record is bigger than the store will take.
    case tooLarge(bytes: Int, limit: Int)
    /// Written by a newer version of the app than this one.
    case newerFormat
    case unreadable

    public var errorDescription: String? {
        switch self {
        case let .tooLarge(bytes, limit):
            return "progress is \(bytes) bytes, over the \(limit)-byte iCloud limit"
        case .newerFormat:
            return "the copy in iCloud was written by a newer version of the app"
        case .unreadable:
            return "the copy in iCloud could not be read"
        }
    }
}

/// A store held in memory: what the tests merge against, and what debug builds
/// get so that driving the UI from the command line never touches real iCloud.
public final class InMemoryCloudProgressStore: CloudProgressStore {
    public var isAvailable: Bool
    public var onExternalChange: ((CloudProgressChange) -> Void)?
    /// Every payload ever written, so a test can assert what was sent.
    public private(set) var writes: [Data] = []

    private var payload: Data?

    public init(payload: Data? = nil, isAvailable: Bool = true) {
        self.payload = payload
        self.isAvailable = isAvailable
    }

    public func loadPayload() throws -> Data? { payload }

    public func savePayload(_ data: Data) throws {
        payload = data
        writes.append(data)
    }

    public func removePayload() throws { payload = nil }

    public func refresh() {}

    /// Stands in for another device writing while this one is running.
    public func simulateExternalWrite(_ data: Data?, reason: CloudProgressChange = .updated) {
        payload = data
        onExternalChange?(reason)
    }
}
