import Foundation

/// Atomic, versioned, on-device persistence for `Progress` (§5).
///
/// A Codable JSON snapshot rather than Core Data or SwiftData: the whole
/// document is a few hundred KB at most, and the migration surface should stay
/// near zero.
public final class ProgressStore {
    public enum LoadOutcome: Equatable {
        case fresh
        case loaded
        /// The file was unreadable and was set aside; progress starts over.
        case recovered(from: String)
        /// The file came from a newer build of the app.
        case refusedNewerSchema(version: Int)
    }

    public let fileURL: URL
    public private(set) var lastLoadOutcome: LoadOutcome = .fresh

    private let clock: any AppClock
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, clock: any AppClock = SystemClock(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.clock = clock
        self.fileManager = fileManager

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// The shipping location: Application Support, excluded from nothing —
    /// progress rides along in device backups but is never synced (§13).
    public static func defaultFileURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("MemorizeBible", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("progress.json")

        // The app was called Memorize Psalms before it covered the whole Bible,
        // and its progress lived in a folder of that name. Carry it across on
        // first launch rather than silently starting somebody from nothing.
        //
        // This only helps within one app container. The bundle identifier
        // changed in the same rename, so a build installed under the old
        // identifier is a different app to iOS and keeps its own data.
        let legacy = base
            .appendingPathComponent("MemorizePsalms", isDirectory: true)
            .appendingPathComponent("progress.json")
        if !fileManager.fileExists(atPath: fileURL.path),
            fileManager.fileExists(atPath: legacy.path)
        {
            try? fileManager.moveItem(at: legacy, to: fileURL)
        }
        return fileURL
    }

    public func load() -> ProgressSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            lastLoadOutcome = .fresh
            return ProgressSnapshot()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let progress = try decoder.decode(ProgressSnapshot.self, from: data)
            if progress.schemaVersion > ProgressSnapshot.currentSchemaVersion {
                // Never rewrite a file written by a newer build: doing so would
                // silently drop fields this build does not know about.
                lastLoadOutcome = .refusedNewerSchema(version: progress.schemaVersion)
                return progress
            }
            lastLoadOutcome = .loaded
            return migrate(progress)
        } catch {
            let backup = quarantineCorruptFile()
            lastLoadOutcome = .recovered(from: backup)
            return ProgressSnapshot()
        }
    }

    /// Writes atomically: `Data.write(.atomic)` stages a temporary file and
    /// renames it, so a crash mid-write can never leave a truncated snapshot.
    public func save(_ progress: ProgressSnapshot) throws {
        guard case .refusedNewerSchema = lastLoadOutcome else {
            var snapshot = progress
            snapshot.schemaVersion = ProgressSnapshot.currentSchemaVersion
            let data = try encoder.encode(snapshot)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            return
        }
        throw ContentError("refusing to overwrite progress written by a newer version of the app")
    }

    /// §8.4: destructive reset, behind a two-step confirmation in the UI.
    public func reset() throws -> ProgressSnapshot {
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        lastLoadOutcome = .fresh
        let fresh = ProgressSnapshot(lastOpenedAt: clock.now)
        try save(fresh)
        return fresh
    }

    private func migrate(_ progress: ProgressSnapshot) -> ProgressSnapshot {
        var progress = progress
        // Version 1 is the first shipping schema; nothing to migrate yet. New
        // versions add their step here and bump currentSchemaVersion.
        progress.schemaVersion = ProgressSnapshot.currentSchemaVersion
        return progress
    }

    private func quarantineCorruptFile() -> String {
        let stamp = ISO8601DateFormatter().string(from: clock.now).replacingOccurrences(of: ":", with: "-")
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("progress-corrupt-\(stamp).json")
        try? fileManager.moveItem(at: fileURL, to: backup)
        return backup.lastPathComponent
    }
}
