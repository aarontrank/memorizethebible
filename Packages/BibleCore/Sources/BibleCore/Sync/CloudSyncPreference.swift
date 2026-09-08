import Foundation

/// Whether this device keeps its progress in iCloud (§13.1). On unless the user
/// says otherwise.
///
/// Kept in `UserDefaults` rather than in the progress record, because the
/// record is the very thing being synced: a switch stored inside it would be
/// handed from device to device, so turning sync off on a phone would turn it
/// off on the iPad too — or, worse, arrive as "off" and leave nothing to turn
/// it back on with. Where to keep your own data is a decision each device makes
/// for itself.
public struct CloudSyncPreference {
    public static let defaultsKey = "iCloudSyncEnabled"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Default on. Somebody upgrading into this version, or installing it for
    /// the first time, gets their work carried to their next device without
    /// having to know the setting is there — and the setting is one tap away
    /// for anyone who would rather it were not.
    public var isEnabled: Bool {
        get { defaults.object(forKey: Self.defaultsKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }
}
