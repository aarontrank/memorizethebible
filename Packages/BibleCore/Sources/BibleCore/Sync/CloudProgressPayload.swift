import Foundation

/// What is actually written to iCloud: the progress record, compressed, with
/// enough left in the clear to decide whether this build should touch it.
///
/// The envelope is versioned separately from the record inside it. The record's
/// schema says what the *progress* looks like; the format version says what
/// this wrapper looks like, so the two can move independently.
public struct CloudProgressEnvelope: Codable, Equatable, Sendable {
    public enum Compression: String, Codable, Sendable {
        case none
        case zlib
    }

    public static let currentFormatVersion = 1

    public var formatVersion: Int
    /// `ProgressSnapshot.schemaVersion` of the record inside, readable without
    /// unpacking it — a copy written by a newer build is refused rather than
    /// guessed at, exactly as `ProgressStore` refuses a newer file on disk.
    public var schemaVersion: Int
    /// When the record it carries last changed. Copied out of the record so
    /// two devices can be compared without decompressing either.
    public var updatedAt: Date
    public var compression: Compression
    public var payload: Data

    public init(
        formatVersion: Int = CloudProgressEnvelope.currentFormatVersion,
        schemaVersion: Int,
        updatedAt: Date,
        compression: Compression,
        payload: Data
    ) {
        self.formatVersion = formatVersion
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.compression = compression
        self.payload = payload
    }
}

/// A copy read back out of the cloud.
public struct CloudProgressRecord: Equatable, Sendable {
    public var snapshot: ProgressSnapshot
    public var schemaVersion: Int
    public var updatedAt: Date

    /// Written by a newer build of the app: it may hold fields this build knows
    /// nothing about, so it is neither adopted nor overwritten.
    public var isFromNewerSchema: Bool { schemaVersion > ProgressSnapshot.currentSchemaVersion }
}

/// Packs and unpacks the record the cloud store holds.
public enum CloudProgressPayload {
    /// `NSUbiquitousKeyValueStore` takes 1 MB for one key and 1 MB in total.
    /// 900 KB leaves the store its own headroom and still holds far more than
    /// the whole Bible memorized: the record is repetitive JSON, which zlib
    /// takes down by roughly a factor of ten.
    public static let sizeLimit = 900_000

    public static func encode(_ snapshot: ProgressSnapshot) throws -> Data {
        var record = snapshot
        record.schemaVersion = ProgressSnapshot.currentSchemaVersion
        let json = try recordEncoder.encode(record)

        var compression = CloudProgressEnvelope.Compression.none
        var payload = json
        if let squashed = compressed(json), squashed.count < json.count {
            payload = squashed
            compression = .zlib
        }

        let data = try envelopeEncoder.encode(
            CloudProgressEnvelope(
                schemaVersion: record.schemaVersion,
                updatedAt: record.updatedAt,
                compression: compression,
                payload: payload
            )
        )
        guard data.count <= sizeLimit else {
            throw CloudSyncError.tooLarge(bytes: data.count, limit: sizeLimit)
        }
        return data
    }

    public static func decode(_ data: Data) throws -> CloudProgressRecord {
        guard let envelope = try? envelopeDecoder.decode(CloudProgressEnvelope.self, from: data) else {
            throw CloudSyncError.unreadable
        }
        guard envelope.formatVersion <= CloudProgressEnvelope.currentFormatVersion else {
            throw CloudSyncError.newerFormat
        }
        let json: Data
        switch envelope.compression {
        case .none:
            json = envelope.payload
        case .zlib:
            guard let expanded = decompressed(envelope.payload) else { throw CloudSyncError.unreadable }
            json = expanded
        }
        guard let snapshot = try? recordDecoder.decode(ProgressSnapshot.self, from: json) else {
            throw CloudSyncError.unreadable
        }
        return CloudProgressRecord(
            snapshot: snapshot,
            schemaVersion: envelope.schemaVersion,
            updatedAt: envelope.updatedAt
        )
    }

    // MARK: - Compression
    //
    // Optional in both directions: an uncompressed payload is marked as such
    // and read back the same way, so a platform without the compression API
    // still writes something every other platform can read.

    private static func compressed(_ data: Data) -> Data? {
        #if canImport(Darwin)
            return try? (data as NSData).compressed(using: .zlib) as Data
        #else
            return nil
        #endif
    }

    private static func decompressed(_ data: Data) -> Data? {
        #if canImport(Darwin)
            return try? (data as NSData).decompressed(using: .zlib) as Data
        #else
            return nil
        #endif
    }

    // MARK: - Coders
    //
    // Sorted keys throughout, so encoding the same record twice gives the same
    // bytes and "has anything actually changed?" is a comparison rather than a
    // guess.

    private static var recordEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var recordDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var envelopeEncoder: JSONEncoder { recordEncoder }
    private static var envelopeDecoder: JSONDecoder { recordDecoder }
}
