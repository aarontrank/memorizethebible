import Foundation

/// Sharing a plan as a link.
///
/// A plan is only an ordering over references — a few hundred bytes — so the
/// whole plan travels inside the link itself. There is no server to publish to,
/// no account to look the plan up under, and nothing to go stale: the same
/// bargain the rest of the app makes (§13).
///
/// The link carries the sender's plan id, so receiving the same plan twice
/// updates the copy you already saved rather than leaving you with two.
public enum PlanSharing {
    /// Where a shared plan is written to. A universal link, so the link is
    /// tappable in a message and a recipient without the app lands on a page
    /// that explains it rather than on nothing.
    ///
    /// The matching half is served from
    /// `https://aarontrank.com/.well-known/apple-app-site-association`, which
    /// claims this path. Changing either without the other silently stops
    /// links from opening the app.
    public static let webHost = "aarontrank.com"
    public static let webPath = "/projects/memorize-the-bible/plan"

    /// The original custom scheme, still registered in `Info.plist` and still
    /// read here. Links written before the move to a universal link are out in
    /// people's messages and have to keep working.
    public static let scheme = "memorizethebible"
    public static let host = "plan"

    private static let payloadKey = "d"

    /// Bumped only for a change the current reader cannot make sense of.
    /// A reader refuses a version it does not know rather than guessing.
    static let formatVersion = 1

    // Caps, so a corrupt or hostile link becomes a rejected link rather than an
    // unusable plan. Generous enough that no plan a person would actually build
    // comes close.
    static let maxTitleLength = 120
    static let maxSummaryLength = 400
    static let maxSections = 50
    static let maxPassagesPerSection = 500

    public static func isPlanLink(_ url: URL) -> Bool {
        isWebPlanLink(url) || isCustomSchemePlanLink(url)
    }

    private static func isWebPlanLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        guard host == webHost else { return false }
        // The association file claims `plan*`, so both the bare path and the
        // trailing-slash form the site redirects to are ours.
        var path = url.path
        if path.hasSuffix("/") { path.removeLast() }
        return path == webPath
    }

    private static func isCustomSchemePlanLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == host
    }

    // MARK: - Writing

    public static func link(for plan: MemoryPlan) throws -> URL {
        let payload = Payload(
            v: formatVersion,
            i: plan.id,
            t: plan.title,
            s: plan.summary,
            x: plan.sections.map { section in
                Payload.Section(t: section.title, p: section.passages.map(encode))
            }
        )
        let encoder = JSONEncoder()
        // Stable output, so the same plan always yields the same link.
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        var components = URLComponents()
        components.scheme = "https"
        components.host = webHost
        components.path = webPath
        components.queryItems = [URLQueryItem(name: payloadKey, value: base64URL(data))]
        guard let url = components.url else { throw PlanSharingError.malformed }
        return url
    }

    // MARK: - Reading

    public static func plan(from url: URL) throws -> MemoryPlan {
        guard isPlanLink(url) else { throw PlanSharingError.notAPlanLink }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard
            let encoded = components?.queryItems?.first(where: { $0.name == payloadKey })?.value,
            let data = data(fromBase64URL: encoded)
        else { throw PlanSharingError.malformed }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw PlanSharingError.malformed
        }
        guard payload.v <= formatVersion else { throw PlanSharingError.newerVersion }

        let sections = payload.x.prefix(maxSections).enumerated().compactMap {
            index, section -> MemoryPlan.Section? in
            let passages = section.p.prefix(maxPassagesPerSection).compactMap(decodePassage)
            guard !passages.isEmpty else { return nil }
            return MemoryPlan.Section(
                // Section ids are derived rather than carried: they only have
                // to be unique within this plan, and deriving them means a
                // malformed one cannot arrive.
                id: "\(payload.i)-s\(index)",
                title: clamp(section.t, to: maxTitleLength),
                passages: passages
            )
        }
        guard !sections.isEmpty else { throw PlanSharingError.noVerses }

        let title = clamp(payload.t, to: maxTitleLength)
        return MemoryPlan(
            id: payload.i,
            title: title.isEmpty ? "Shared plan" : title,
            summary: clamp(payload.s, to: maxSummaryLength),
            sections: sections,
            isBuiltIn: false,
            origin: .shared
        )
    }

    // MARK: - Passages
    //
    // "ROM.3.23" or "ROM.10.9-10". Passages are most of the payload, so they
    // are written as text rather than as objects with keys repeated per entry.

    static func encode(_ passage: PassageRef) -> String {
        let base = "\(passage.book.rawValue).\(passage.chapter).\(passage.firstVerse)"
        return passage.isSingleVerse ? base : "\(base)-\(passage.lastVerse)"
    }

    static func decodePassage(_ text: String) -> PassageRef? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, let chapter = Int(parts[1]), chapter >= 1
        else { return nil }
        let verses = parts[2].split(separator: "-", omittingEmptySubsequences: false)
        guard verses.count <= 2, let first = Int(verses[0]) else { return nil }
        // Verse 0 is a psalm's superscription, so 0 is a legitimate first verse.
        guard first >= 0 else { return nil }
        let last = verses.count == 2 ? Int(verses[1]) : first
        guard let last, last >= first else { return nil }
        return PassageRef(BookID(String(parts[0])), chapter, first, last)
    }

    // MARK: - Base64URL
    //
    // Plain base64 uses "+" and "/", which have to be percent-escaped in a
    // query and make the link both longer and easier to break in transit.

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(fromBase64URL text: String) -> Data? {
        var base64 =
            text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Padding is dropped when writing, so it has to be put back.
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }

    private static func clamp(_ text: String, to limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit))
    }

    /// Keys are one letter because they repeat once per section and the whole
    /// payload has to survive being pasted into a message.
    private struct Payload: Codable {
        struct Section: Codable {
            var t: String
            var p: [String]
        }

        var v: Int
        var i: String
        var t: String
        var s: String
        var x: [Section]
    }
}

public enum PlanSharingError: Error, Equatable {
    /// Some other link entirely.
    case notAPlanLink
    /// A plan link, but damaged — truncated in a message, most likely.
    case malformed
    /// Written by a newer version of the app than this one.
    case newerVersion
    /// Decoded cleanly but names no verses this app can read.
    case noVerses

    public var message: String {
        switch self {
        case .notAPlanLink, .malformed:
            return "That link is incomplete. Ask for it again — links can get cut short when they are forwarded."
        case .newerVersion:
            return "That plan was shared from a newer version of the app. Update to open it."
        case .noVerses:
            return "That plan does not name any verses."
        }
    }
}
