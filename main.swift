#!/usr/bin/env -S swift -swift-version 6 -Xfrontend -strict-concurrency=complete

// LaunchBar Action Script

import Foundation
import os

private let logger = Logger(subsystem: "launchbar-swift-evolution", category: "main")
private let signposter = OSSignposter(subsystem: "launchbar-swift-evolution", category: "network")

enum DebugLogging {
    nonisolated(unsafe) static var enabled = ProcessInfo.processInfo.environment["SWIFT_EV_LOG_DEBUG"] != nil
}

private func debugLog(_ message: @autoclosure () -> String) {
    guard DebugLogging.enabled else { return }
    let text = message()
    logger.debug("\(text)")
    fputs("[debug] \(text)\n", stderr)
}

struct CommandLineOptions {
    var query: String
    var debug: Bool
    var help: Bool
}

private func parseCommandLine(_ arguments: [String]) -> CommandLineOptions {
    var debug = false
    var help = false
    var queryParts: [String] = []

    for arg in arguments {
        switch arg {
        case "--debug", "-d":
            debug = true
        case "--help", "-h":
            help = true
        default:
            queryParts.append(arg)
        }
    }

    return CommandLineOptions(query: queryParts.joined(separator: " "), debug: debug, help: help)
}

struct SwiftEvolution: Decodable {
    static let dataURL = URL(string: "https://download.swift.org/swift-evolution/v1/evolution.json")!

    /// E.g. "2024-05-14T13:38:30Z"
    var creationDate: String
    var proposals: [ProposalDTO]
    /// E.g. "1.0.0"
    var schemaVersion: String
}

/// Data transfer object definition for a Swift Evolution proposal in the
/// JSON format used by swift.org.
struct ProposalDTO: Decodable {
    /// SE-NNNN, e.g. "SE-0147"
    var id: String
    var title: String
    /// Local path to the proposal file, e.g. "0423-dynamic-actor-isolation.md".
    var link: String
    var status: Status
    var upcomingFeatureFlag: UpcomingFeatureFlag?

    struct Status: Decodable {
        var state: String
        /// Swift version in which the proposal was implemented, e.g. "5.6"
        /// Only present if state == "implemented"
        var version: String?
        /// Start and end date of the review period, e.g. "2024-05-08T00:00:00Z"
        /// Only present if state == "activeReview" (and maybe other states?)
        var start: String?
        var end: String?
        /// Reason for error state. Only present if state == "error"
        var reason: String?
    }
}

struct UpcomingFeatureFlag: Decodable {
    /// Name of the feature flag, e.g. "ExistentialAny".
    var flag: String
    /// Language mode version when feature is always enabled.
    /// Field is omitted when there is no announced language mode.
    var enabledInLanguageMode: String?
    /// The language release version (e.g. "5.10") when the flag is
    /// available, if not the same as the release in which the feature is
    /// implemented.
    var available: String?
}

struct Proposal {
    let baseURL = URL(string: "https://github.com/apple/swift-evolution/blob/main/proposals")!

    var id: String
    var title: String
    var url: URL
    var status: Status
    var upcomingFeatureFlag: UpcomingFeatureFlag?

    var number: Int? {
        guard let digits = id.split(separator: "-").last else { return nil }
        return Int(digits)
    }

    var searchText: String {
        "\(id) \(number.map(String.init(describing:)) ?? "") \(title) \(status.description) \(upcomingFeatureFlag?.flag ?? "")"
            .lowercased()
    }

    func matches(_ query: String) -> Bool {
        matchesQuery(query, number: number, searchText: searchText)
    }
}

extension Proposal {
    init(dto: ProposalDTO) {
        self.id = dto.id
        self.title = dto.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = baseURL.appendingPathComponent(dto.link)
        self.status = Status(dto: dto.status)
        self.upcomingFeatureFlag = dto.upcomingFeatureFlag
    }
}

extension Proposal {
    enum Status: CustomStringConvertible {
        case awaitingReview
        case scheduledForReview
        case activeReview(interval: DateInterval?)
        case returnedForRevision
        case withdrawn
        case deferred // status is no longer in use
        case accepted
        case acceptedWithRevisions
        case rejected
        case implemented(version: String?)
        case previewing
        case error(reason: String?)
        case unknown(status: String)

        init(dto: ProposalDTO.Status) {
            switch dto.state {
            case "awaitingReview": self = .awaitingReview
            case "scheduledForReview": self = .scheduledForReview
            case "activeReview":
                let interval: DateInterval?
                if let start = dto.start, let end = dto.end,
                    let startDate = try? Date.ISO8601FormatStyle.iso8601.parse(start),
                    let endDate = try? Date.ISO8601FormatStyle.iso8601.parse(end),
                    startDate <= endDate
                {
                    interval = DateInterval(start: startDate, end: endDate)
                } else {
                    interval = nil
                }
                self = .activeReview(interval: interval)
            case "returnedForRevision": self = .returnedForRevision
            case "withdrawn": self = .withdrawn
            case "deferred": self = .deferred
            case "accepted": self = .accepted
            case "acceptedWithRevisions": self = .acceptedWithRevisions
            case "rejected": self = .rejected
            case "implemented": self = .implemented(version: dto.version)
            case "previewing": self = .previewing
            case "error": self = .error(reason: dto.reason)
            default: self = .unknown(status: dto.state)
            }
        }

        var description: String {
            switch self {
            case .awaitingReview: return "Awaiting Review"
            case .scheduledForReview: return "Scheduled for Review"
            case .activeReview(let interval?):
                let formatStyle = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
                let start = interval.start.formatted(formatStyle)
                let end = interval.end.formatted(formatStyle)
                return "Active Review (\(start) to \(end))"
            case .activeReview(nil): return "Active Review"
            case .returnedForRevision: return "Returned for Revision"
            case .withdrawn: return "Withdrawn"
            case .deferred: return "Deferred"
            case .accepted: return "Accepted"
            case .acceptedWithRevisions: return "Accepted with Revisions"
            case .rejected: return "Rejected"
            case .implemented(let version?): return "Implemented (Swift \(version))"
            case .implemented(nil): return "Implemented"
            case .previewing: return "Previewing"
            case .error(let reason): return "Error \(reason ?? "unknown reason"))"
            case .unknown(let underlying): return "Unknown status: \(underlying)"
            }
        }
    }
}

/// An item that a LaunchBar action expects to receive from a script.
/// Represents one row in LaunchBar result set.
///
/// Documentation: <https://developer.obdev.at/launchbar-developer-documentation/#/script-output>
struct LBItem: Codable {
    /// The title displayed in the result row.
    var title: String
    /// The subtitle displayed in the result row.
    var subtitle: String?
    var actionArgument: String?
    /// A URL that the item represents. When the user selects the item and hits Enter, this URL is opened.
    var url: String?
    /// The icon for the item. This is a string that is interpreted the same way as CFBundleIconFile
    /// in the action’s Info.plist.
    var icon: String?
    /// An optional text that appears right–aligned.
    var label: String?
    /// An optional text that appears right–aligned. Similar to label, but with a rounded rectangle behind
    /// the text. If both label and badge are set, label appears to the left of badge.
    var badge: String?
    /// If true, subtitle will always be shown if it is set. Otherwise, it will only be shown if the user
    /// has “Show all subtitles” enabled in LaunchBar’s appearance preferences or if the modifier keys
    /// ⌃⌥⌘ are held down.
    var alwaysShowsSubtitle: Bool = true
}

extension LBItem {
    init(proposal: Proposal) {
        self.title = "\(proposal.id): \(proposal.title)"
        var subtitle = proposal.status.description
        if let upcomingFeatureFlag = proposal.upcomingFeatureFlag {
            subtitle.append(" · Feature flag: \(upcomingFeatureFlag.flag)")
            if let languageMode = upcomingFeatureFlag.enabledInLanguageMode {
                subtitle.append(" (enabled in Swift \(languageMode) language version)")
            }
        }
        self.subtitle = subtitle

        self.url = proposal.url.absoluteString
        self.icon = "icon.png"
    }

    init(error: Error) {
        // Dumping an `Error`’s contents seems to be the best way to extract all
        // the salient error information into a semi-readable string. This
        // obviously isn’t ideal for user-facing error messages, but I think
        // it’s acceptable for a developer tool such as this.
        // Unfortunately, `error.localizedDescription` or the various
        // `LocalizedError` properties carry little to no actionable information
        // about the failure reason for typical library errors such as
        // Foundation.CocoaError or Swift.DecodingError.
        let title = "Error: \(error.localizedDescription)"
        var errorInfo = ""
        dump(error, to: &errorInfo)
        self.init(
            title: title,
            subtitle: errorInfo,
            actionArgument: "\(title)\n\(errorInfo)"
        )
    }
}

// MARK: - Cache definitions

private enum CachePaths {
    static let directory: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("launchbar-swift-evolution", isDirectory: true)
    }()
    static let cacheFileURL = directory.appendingPathComponent("evolution-cache.json")
}

private struct CachedProposal: Codable {
    var item: LBItem
    /// Lowercased string used for matching queries quickly.
    var searchText: String
    var number: Int?
}

private struct CachePayload: Codable {
    var etag: String?
    var lastModified: String?
    var cachedAt: Date
    var proposals: [CachedProposal]
}

// MARK: - Cache helpers

private func loadCache() -> CachePayload? {
    guard let data = try? Data(contentsOf: CachePaths.cacheFileURL) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(CachePayload.self, from: data)
}

private func saveCache(_ payload: CachePayload) {
    do {
        try FileManager.default.createDirectory(at: CachePaths.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: CachePaths.cacheFileURL, options: .atomic)
    } catch {
        // Cache writes should never break the action; ignore failures silently.
    }
}

private func buildCachedPayload(from evolution: SwiftEvolution, etag: String?, lastModified: String?) -> CachePayload {
    let proposals = evolution.proposals.map { dto -> CachedProposal in
        let proposal = Proposal(dto: dto)
        return CachedProposal(
            item: LBItem(proposal: proposal),
            searchText: proposal.searchText,
            number: proposal.number
        )
    }
    return CachePayload(etag: etag, lastModified: lastModified, cachedAt: Date(), proposals: proposals)
}

private func matchesQuery(_ query: String, number: Int?, searchText: String) -> Bool {
    let words = query
        .split { $0.isWhitespace || $0.isNewline }
        .map { $0.lowercased() }
    if words.isEmpty { return true }
    if words.count == 1, let queryNumber = Int(words[0]) {
        return number == queryNumber
    }
    return words.contains { searchText.contains($0) }
}

private enum FetchResult {
    case notModified
    case newData(Data, etag: String?, lastModified: String?)
}

private func fetchEvolution(etag: String?, lastModified: String?) async throws -> FetchResult {
    debugLog("Starting fetch; etag=\(etag ?? "nil"), lastModified=\(lastModified ?? "nil")")
    var request = URLRequest(url: SwiftEvolution.dataURL)
    request.timeoutInterval = 8
    if let etag {
        request.addValue(etag, forHTTPHeaderField: "If-None-Match")
    }
    if let lastModified {
        request.addValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
    }

    let signpostID = signposter.makeSignpostID()
    let state = signposter.beginInterval("fetchEvolution", id: signpostID, "etag=\(etag ?? "nil"), lm=\(lastModified ?? "nil")")
    let (data, response) = try await URLSession.shared.data(for: request)
    signposter.endInterval("fetchEvolution", state)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }

    let responseETag = httpResponse.value(forHTTPHeaderField: "Etag")
    let responseLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

    switch httpResponse.statusCode {
    case 304:
        debugLog("Fetch 304 Not Modified")
        return .notModified
    case 200:
        debugLog("Fetch 200 OK, bytes=\(data.count), etag=\(responseETag ?? "nil"), lm=\(responseLastModified ?? "nil")")
        return .newData(data, etag: responseETag, lastModified: responseLastModified)
    default:
        debugLog("Fetch error status=\(httpResponse.statusCode)")
        throw URLError(.badServerResponse)
    }
}

private func resolveResult(for query: String) async -> [LBItem] {
    do {
        let cache = loadCache()
        debugLog("Loaded cache: \(cache?.proposals.count ?? 0) proposals; etag=\(cache?.etag ?? "nil"), lm=\(cache?.lastModified ?? "nil")")

        let payload: CachePayload
        do {
            let fetchResult = try await fetchEvolution(etag: cache?.etag, lastModified: cache?.lastModified)
            switch fetchResult {
            case .notModified:
                if let cache {
                    debugLog("Using cached payload (not modified)")
                    payload = cache
                } else {
                    throw URLError(.badServerResponse)
                }
            case .newData(let data, let etag, let lastModified):
                if let cache, let etag, etag == cache.etag {
                    debugLog("Received 200 with matching ETag; reusing cache")
                    payload = cache
                    break
                }
                if let cache, let lastModified, lastModified == cache.lastModified {
                    debugLog("Received 200 with matching Last-Modified; reusing cache")
                    payload = cache
                    break
                }
                let decoder = JSONDecoder()
                let swiftEvolution = try decoder.decode(SwiftEvolution.self, from: data)
                let builtPayload = buildCachedPayload(from: swiftEvolution, etag: etag, lastModified: lastModified)
                saveCache(builtPayload)
                debugLog("Saved new cache with \(builtPayload.proposals.count) proposals; etag=\(etag ?? "nil"), lm=\(lastModified ?? "nil")")
                payload = builtPayload
            }
        } catch {
            if let cache {
                debugLog("Fetch failed; falling back to cache: \(error.localizedDescription)")
                payload = cache
            } else {
                throw error
            }
        }

        let filtered = payload.proposals
            .filter { matchesQuery(query, number: $0.number, searchText: $0.searchText) }
            .sorted { ($0.number ?? 0) > ($1.number ?? 0) }
            .map(\.item)
        debugLog("Filtered \(filtered.count) results for query=\(query)")
        return filtered
    } catch {
        debugLog("Returning error item: \(error.localizedDescription)")
        return [LBItem(error: error)]
    }
}

// MARK: - Main program
let options = parseCommandLine(Array(CommandLine.arguments.dropFirst()))
if options.help {
    print("""
    Usage: main.swift [--debug|-d] [--help|-h] [query...]
      --debug, -d   Enable verbose logging
      --help, -h    Show this help message
    """)
    exit(0)
}
DebugLogging.enabled = DebugLogging.enabled || options.debug
debugLog("Debug logging enabled via \(options.debug ? "flag" : "environment")")

let result = await resolveResult(for: options.query)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

do {
    let resultData = try encoder.encode(result)
    print(String(decoding: resultData, as: UTF8.self))
} catch {
    let fallback = [LBItem(error: error)]
    let fallbackData = (try? encoder.encode(fallback)) ?? Data()
    print(String(decoding: fallbackData, as: UTF8.self))
}
