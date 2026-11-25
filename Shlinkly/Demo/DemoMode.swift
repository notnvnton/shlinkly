//
//  DemoMode.swift
//  Shlinkly
//
//  Debug builds only. Release, Release-Direct, the App Store build and the DMG
//  contain none of this file.
//

#if DEBUG
import Foundation
import SwiftUI
import ShlinklyCore

/// A demo mode for App Store and website screenshots: the real app, every real
/// code path, but an invented, fixed dataset instead of Anton's servers.
///
/// On only when the app is launched with `-ShlinklyDemo YES` (Xcode: Edit
/// Scheme › Run › Arguments). The argument lands in the volatile argument
/// domain of `UserDefaults`, so nothing about it is ever saved.
///
/// In demo mode the app never touches real data:
/// - the servers live in an in-memory Keychain (``DemoKeychain``), so the real
///   Keychain (and its iCloud sync) is never read or written;
/// - preferences and `@AppStorage` go to a separate suite, wiped at launch;
/// - Spotlight is off (`AppModel(spotlight: nil)`);
/// - every request goes to ``DemoURLProtocol``, which answers Shlink's REST
///   endpoints from ``DemoServer`` in memory; nothing reaches the network;
/// - link previews come from the dataset, not `LPMetadataProvider`.
/// Relaunching without the argument shows the real servers and links.
enum DemoMode {
    /// Whether the app was launched with `-ShlinklyDemo YES`.
    nonisolated static var isOn: Bool {
        UserDefaults.standard.bool(forKey: "ShlinklyDemo")
    }

    /// Preferences and `@AppStorage` in demo mode: a suite of its own, emptied
    /// on first use, so the real values are never written.
    nonisolated(unsafe) static let defaults: UserDefaults = {
        let name = "de.ahodge.Shlinkly.demo"
        let suite = UserDefaults(suiteName: name) ?? UserDefaults()
        suite.removePersistentDomain(forName: name)
        return suite
    }()

    /// A session that can only reach ``DemoURLProtocol``.
    nonisolated static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DemoURLProtocol.self]
        return URLSession(configuration: configuration)
    }()

    /// The demo app model, for the one path that doesn't get it injected (the
    /// App Intent).
    private static var appModel: AppModel?

    /// The app model for demo mode: the two demo servers in memory, Marketing
    /// active, preferences in the demo suite, no Spotlight, the demo session.
    static func makeAppModel() -> AppModel {
        let store = InstanceStore(defaults: defaults, keychain: DemoKeychain())
        for server in DemoData.servers {
            let instance = ServerInstance(id: server.id, name: server.name, baseURL: server.baseURL)
            try? store.add(instance, apiKey: "demo")
        }
        store.setActive(DemoData.servers[0].id)
        let model = AppModel(instanceStore: store,
                             preferences: AppPreferences(defaults: defaults),
                             urlSession: urlSession,
                             spotlight: nil)
        appModel = model
        return model
    }

    /// The active demo server's client (for the App Intent).
    static func activeClient() -> ShlinkClient? {
        appModel?.client
    }

    /// The link preview's title for `url`: the dataset's, so no request goes out.
    nonisolated static func previewTitle(for url: URL) -> String? {
        DemoServer.shared.previewTitle(for: url)
    }
}

extension View {
    /// In demo mode, `@AppStorage` (the Mac's menu-bar-only switch) reads and
    /// writes the demo suite. Without `-ShlinklyDemo YES` the view is returned
    /// as it is.
    @ViewBuilder
    func demoAppStorage() -> some View {
        if DemoMode.isOn {
            defaultAppStorage(DemoMode.defaults)
        } else {
            self
        }
    }
}

// MARK: - The dataset (approved by Anton)

nonisolated enum DemoData {
    struct Server {
        let id: UUID
        let name: String
        let baseURL: URL
        let links: [Link]
        var host: String { baseURL.host() ?? "" }
    }

    struct Link {
        let title: String
        let code: String
        let longURL: String
        let tags: [String]
        let people: Int
        let bots: Int
        let daysAgo: Int
        /// A launch: quiet before its day, a clear peak on days 1–2, then decay.
        var isLaunch = false
        /// Country code (nil = Unknown) and weight, or exact counts for launch-3.
        let countries: [(code: String?, weight: Double)]
        /// Referer (nil = Direct) and weight, or exact counts for launch-3.
        let sources: [(referer: String?, weight: Double)]
        /// Exact counts instead of weights (launch-3).
        var exact = false
        /// The link preview's title, when it isn't the link's own.
        var previewTitle: String?
    }

    static let countryNames: [String: String] = [
        "DE": "Germany", "US": "United States", "GB": "United Kingdom", "NL": "Netherlands",
        "FR": "France", "CH": "Switzerland", "AT": "Austria", "CA": "Canada", "SE": "Sweden",
        "ES": "Spain", "PL": "Poland",
    ]

    static let servers: [Server] = [
        Server(
            id: UUID(uuidString: "D3E0A000-0000-4000-8000-000000000001")!,
            name: "Marketing",
            baseURL: URL(string: "https://go.shlinkly.com")!,
            links: [
                Link(title: "Shlinkly 3.0 launch post", code: "launch-3",
                     longURL: "https://shlinkly.com/?utm_source=linkedin&utm_campaign=v3-launch",
                     tags: ["launch", "linkedin"], people: 1036, bots: 212, daysAgo: 9, isLaunch: true,
                     countries: [("DE", 412), ("US", 298), ("GB", 121), ("NL", 88), ("FR", 64),
                                 ("CH", 58), ("AT", 52), ("CA", 47), ("SE", 41), ("ES", 37), (nil, 30)],
                     sources: [("https://www.linkedin.com/", 702), (nil, 241), ("https://www.google.com/", 93),
                               ("https://t.co/", 71), ("https://news.ycombinator.com/", 54),
                               ("https://mastodon.social/", 39), ("https://duckduckgo.com/", 28),
                               ("https://www.bing.com/", 20)],
                     exact: true,
                     previewTitle: "Shlinkly 3.0: a full redesign and QR codes"),
                Link(title: "r/selfhosted thread", code: "selfhosted",
                     longURL: "https://shlinkly.com/?utm_source=reddit&utm_campaign=v3-launch",
                     tags: ["launch", "reddit"], people: 790, bots: 74, daysAgo: 8,
                     countries: [("DE", 30), ("US", 28), ("GB", 10), ("NL", 8), ("FR", 6), ("CA", 6),
                                 ("SE", 4), ("PL", 4), (nil, 4)],
                     sources: [("https://www.reddit.com/r/selfhosted/", 74), (nil, 16),
                               ("https://old.reddit.com/r/selfhosted/", 4), ("https://www.google.com/", 4),
                               ("https://duckduckgo.com/", 2)]),
                Link(title: "November newsletter", code: "nov-news",
                     longURL: "https://ahodge.de/shlinkly?utm_source=newsletter&utm_campaign=nov",
                     tags: ["newsletter"], people: 501, bots: 31, daysAgo: 6,
                     countries: [("DE", 62), ("AT", 12), ("CH", 10), ("NL", 5), ("US", 5), ("GB", 3), (nil, 3)],
                     sources: [(nil, 71), ("https://mail.google.com/", 17), ("https://outlook.live.com/", 8),
                               ("https://www.linkedin.com/", 4)]),
                Link(title: "Booth poster QR", code: "booth-qr",
                     longURL: "https://shlinkly.com/?utm_source=poster&utm_medium=qr",
                     tags: ["events", "qr"], people: 384, bots: 5, daysAgo: 14,
                     countries: [("DE", 86), ("AT", 6), ("CH", 5), ("NL", 2), (nil, 1)],
                     sources: [(nil, 1)]),
                Link(title: "Podcast show notes", code: "podcast",
                     longURL: "https://shlinkly.com/?utm_source=podcast",
                     tags: ["podcast"], people: 188, bots: 23, daysAgo: 20,
                     countries: [("DE", 40), ("US", 25), ("GB", 10), ("AT", 7), ("CH", 6), ("NL", 5), (nil, 7)],
                     sources: [(nil, 58), ("https://podcasts.apple.com/", 22), ("https://open.spotify.com/", 14),
                               ("https://overcast.fm/", 6)]),
                Link(title: "Conference talk slides", code: "talk-slides",
                     longURL: "https://ahodge.de/talks/campaign-links",
                     tags: ["events"], people: 139, bots: 8, daysAgo: 27,
                     countries: [("DE", 55), ("NL", 15), ("AT", 10), ("CH", 8), ("GB", 7), (nil, 5)],
                     sources: [(nil, 62), ("https://www.linkedin.com/", 20), ("https://t.co/", 10),
                               ("https://mastodon.social/", 8)]),
                Link(title: "Case study: campaign links", code: "case-study",
                     longURL: "https://ahodge.de/shlinkly",
                     tags: ["portfolio"], people: 81, bots: 15, daysAgo: 45,
                     countries: [("DE", 55), ("US", 15), ("GB", 10), ("AT", 8), ("CH", 7), (nil, 5)],
                     sources: [("https://ahodge.de/", 35), ("https://www.linkedin.com/", 30), (nil, 25),
                               ("https://www.google.com/", 10)]),
                Link(title: "Self-hosting guide", code: "docs",
                     longURL: "https://shlinkly.com/docs/self-hosting",
                     tags: ["docs"], people: 44, bots: 14, daysAgo: 60,
                     countries: [("DE", 30), ("US", 30), ("GB", 10), ("NL", 10), ("FR", 10), (nil, 10)],
                     sources: [("https://www.google.com/", 45), ("https://github.com/", 25), (nil, 20),
                               ("https://duckduckgo.com/", 10)]),
            ]
        ),
        Server(
            id: UUID(uuidString: "D3E0A000-0000-4000-8000-000000000002")!,
            name: "Personal",
            baseURL: URL(string: "https://s.ahodge.de")!,
            links: [
                Link(title: "Sourdough notes", code: "bread", longURL: "https://ahodge.de/notes/sourdough",
                     tags: ["recipes"], people: 31, bots: 3, daysAgo: 18,
                     countries: [("DE", 85), ("AT", 10), (nil, 5)],
                     sources: [(nil, 70), ("https://mastodon.social/", 30)]),
                Link(title: "Reading list 2026", code: "books", longURL: "https://ahodge.de/notes/reading-2026",
                     tags: ["reading"], people: 25, bots: 2, daysAgo: 33,
                     countries: [("DE", 80), ("CH", 10), (nil, 10)],
                     sources: [(nil, 80), ("https://ahodge.de/", 20)]),
                Link(title: "Trail run route", code: "trail", longURL: "https://ahodge.de/notes/trail-run",
                     tags: ["running"], people: 12, bots: 0, daysAgo: 5,
                     countries: [("DE", 1)],
                     sources: [(nil, 1)]),
            ]
        ),
    ]
}

// MARK: - Deterministic visits

/// SplitMix64: a small, fixed-seed generator, so every launch shows the same
/// visits.
nonisolated struct DemoRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            let j = Int(next() % UInt64(i + 1))
            array.swapAt(i, j)
        }
    }
}

nonisolated enum DemoVisits {
    /// `total` split by `weights` into whole numbers that add up exactly
    /// (largest remainder; ties go to the earlier entry).
    static func split(_ total: Int, _ weights: [Double]) -> [Int] {
        let sum = weights.reduce(0, +)
        guard total > 0, sum > 0 else { return weights.map { _ in 0 } }
        let raw = weights.map { Double(total) * $0 / sum }
        var counts = raw.map { Int($0.rounded(.down)) }
        var rest = total - counts.reduce(0, +)
        let order = raw.indices.sorted { lhs, rhs in
            let l = raw[lhs] - Double(counts[lhs]), r = raw[rhs] - Double(counts[rhs])
            return l != r ? l > r : lhs < rhs
        }
        for index in order where rest > 0 {
            counts[index] += 1
            rest -= 1
        }
        return counts
    }

    /// The link's visits, newest first: exactly `people` and `bots`, countries
    /// and sources dealt out to the exact counts.
    static func make(for link: DemoData.Link, created: Date, now: Date, seed: UInt64) -> [Visit] {
        var random = DemoRandom(seed: seed)
        let calendar = Calendar(identifier: .gregorian)
        let firstDay = calendar.startOfDay(for: created)
        let days = max(0, calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: now)).day ?? 0)

        // Per-day weights from the link's creation day (0) to today.
        let peopleWeights: [Double] = (0...days).map { day in
            let d = Double(day)
            if link.isLaunch {
                switch day {
                case 0: return 0.35
                case 1: return 1.0
                case 2: return 0.92
                default: return 0.92 * exp(-(d - 2) / 2.2) + 0.03
                }
            }
            switch day {
            case 0: return 0.55
            case 1: return 1.0
            default: return 0.85 * exp(-(d - 1) / 4.0) + 0.06
            }
        }
        let botWeights = [Double](repeating: 1, count: days + 1)

        // A moment on day `day`, after creation and not after now.
        func moment(on day: Int) -> Date {
            let dayStart = calendar.date(byAdding: .day, value: day, to: firstDay) ?? firstDay
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let start = max(dayStart, created), end = min(dayEnd, now)
            guard end > start else { return start }
            return start.addingTimeInterval(random.unit() * end.timeIntervalSince(start))
        }

        var slots: [(date: Date, bot: Bool)] = []
        for (day, count) in split(link.people, peopleWeights).enumerated() {
            for _ in 0..<count { slots.append((moment(on: day), false)) }
        }
        for (day, count) in split(link.bots, botWeights).enumerated() {
            for _ in 0..<count { slots.append((moment(on: day), true)) }
        }

        let total = slots.count
        let countryCounts = link.exact ? link.countries.map { Int($0.weight) } : split(total, link.countries.map(\.weight))
        let sourceCounts = link.exact ? link.sources.map { Int($0.weight) } : split(total, link.sources.map(\.weight))
        var countries: [String?] = []
        for (entry, count) in zip(link.countries, countryCounts) {
            countries += [String?](repeating: entry.code, count: count)
        }
        var sources: [String?] = []
        for (entry, count) in zip(link.sources, sourceCounts) {
            sources += [String?](repeating: entry.referer, count: count)
        }
        random.shuffle(&countries)
        random.shuffle(&sources)

        var visits: [Visit] = []
        for (index, slot) in slots.enumerated() {
            let code = index < countries.count ? countries[index] : nil
            let location = code.map {
                Visit.VisitLocation(countryCode: $0, countryName: DemoData.countryNames[$0])
            }
            visits.append(Visit(referer: index < sources.count ? sources[index] : nil,
                                date: slot.date, potentialBot: slot.bot, visitLocation: location))
        }
        return visits.sorted { $0.date > $1.date }
    }
}

// MARK: - In-memory server

/// The demo servers' links and visits, in memory. Created once, at first use,
/// relative to that moment; writes (create, edit, delete) change only this.
nonisolated final class DemoServer: @unchecked Sendable {
    static let shared = DemoServer()

    private struct Store {
        var links: [ShortURL]
        var visits: [String: [Visit]]
    }

    private let lock = NSLock()
    private var stores: [String: Store] = [:]
    private var previewTitles: [String: String] = [:]
    private var createdCount = 0

    private init() {
        let now = Date()
        for (serverIndex, server) in DemoData.servers.enumerated() {
            var store = Store(links: [], visits: [:])
            for (linkIndex, link) in server.links.enumerated() {
                let created = now.addingTimeInterval(-Double(link.daysAgo) * 86_400 - 3_600)
                let seed = 0x5EED_0000 &+ UInt64(serverIndex * 100 + linkIndex) &* 7_919
                store.visits[link.code] = DemoVisits.make(for: link, created: created, now: now, seed: seed)
                store.links.append(ShortURL(
                    shortCode: link.code,
                    shortUrl: "https://\(server.host)/\(link.code)",
                    longUrl: link.longURL,
                    dateCreated: created,
                    visitsSummary: VisitsSummary(total: link.people + link.bots, nonBots: link.people, bots: link.bots),
                    title: link.title,
                    tags: link.tags
                ))
                previewTitles[link.longURL] = link.previewTitle ?? link.title
            }
            stores[server.host] = store
        }
    }

    func previewTitle(for url: URL) -> String? {
        lock.withLock {
            if let title = previewTitles[url.absoluteString] { return title }
            return stores.values.lazy.flatMap(\.links).first { $0.longUrl == url.absoluteString }?.title
        }
    }

    /// Answers one request: a status code and a JSON body (nil = no content),
    /// or nil for a host that isn't a demo server.
    func respond(to request: URLRequest, body: Data?) -> (status: Int, json: Data?)? {
        guard let url = request.url, let host = url.host() else { return nil }
        return lock.withLock {
            guard var store = stores[host] else { return nil }
            defer { stores[host] = store }
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let query = components?.queryItems ?? []
            let path = url.pathComponents.drop { $0 != "v3" }.dropFirst()
            let method = request.httpMethod ?? "GET"
            return route(method: method, path: Array(path), query: query, body: body, host: host, store: &store)
        }
    }

    private func route(method: String, path: [String], query: [URLQueryItem], body: Data?,
                       host: String, store: inout Store) -> (status: Int, json: Data?) {
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        func values(_ name: String) -> [String] { query.filter { $0.name == name }.compactMap(\.value) }

        switch (method, path.count) {
        case ("GET", 1) where path[0] == "health":
            return (200, Data(#"{"status":"pass","version":"4.4.0"}"#.utf8))

        case ("GET", 1) where path[0] == "tags":
            let tags = Array(Set(store.links.flatMap(\.tags))).sorted()
            return (200, wrap("tags", page(tags, value("page"), value("itemsPerPage"))))

        case ("GET", 1) where path[0] == "short-urls":
            var links = store.links
            if let term = value("searchTerm")?.lowercased(), !term.isEmpty {
                links = links.filter { link in
                    link.shortCode.lowercased().contains(term) || link.longUrl.lowercased().contains(term)
                        || (link.title ?? "").lowercased().contains(term)
                        || link.tags.contains { $0.lowercased().contains(term) }
                }
            }
            let tags = values("tags[]")
            if !tags.isEmpty {
                links = links.filter { !Set($0.tags).isDisjoint(with: tags) }
            }
            switch value("orderBy") {
            case "dateCreated-ASC": links.sort { $0.dateCreated < $1.dateCreated }
            case "visits-DESC": links.sort { $0.visitsSummary.total > $1.visitsSummary.total }
            case "visits-ASC": links.sort { $0.visitsSummary.total < $1.visitsSummary.total }
            default: links.sort { $0.dateCreated > $1.dateCreated }
            }
            return (200, wrap("shortUrls", page(links, value("page"), value("itemsPerPage"))))

        case ("POST", 1) where path[0] == "short-urls":
            guard let body = decodeBody(body), let longUrl = body.longUrl else {
                return (400, problem(type: "https://shlink.io/api/error/invalid-data", title: "Invalid data"))
            }
            let slug = body.customSlug.flatMap { $0.isEmpty ? nil : $0 }
            if let slug, store.links.contains(where: { $0.shortCode == slug }) {
                return (400, problem(type: "https://shlink.io/api/error/non-unique-slug",
                                     title: "Invalid custom slug", customSlug: slug))
            }
            createdCount += 1
            let code = slug ?? "demo\(createdCount)"
            let link = ShortURL(
                shortCode: code, shortUrl: "https://\(host)/\(code)", longUrl: longUrl, dateCreated: Date(),
                title: body.title, tags: body.tags ?? [], crawlable: body.crawlable ?? false,
                forwardQuery: body.forwardQuery ?? true,
                meta: .init(validSince: body.validSince.flatMap(Self.date), validUntil: body.validUntil.flatMap(Self.date),
                            maxVisits: body.maxVisits)
            )
            store.links.insert(link, at: 0)
            store.visits[code] = []
            return (200, encode(link))

        case ("GET", 2) where path[0] == "short-urls":
            guard let link = store.links.first(where: { $0.shortCode == path[1] }) else { return notFound() }
            return (200, encode(link))

        case ("PATCH", 2) where path[0] == "short-urls":
            guard let index = store.links.firstIndex(where: { $0.shortCode == path[1] }),
                  let body = decodeBody(body) else { return notFound() }
            let old = store.links[index]
            let link = ShortURL(
                shortCode: old.shortCode, shortUrl: old.shortUrl, longUrl: body.longUrl ?? old.longUrl,
                dateCreated: old.dateCreated, visitsSummary: old.visitsSummary, title: body.title,
                tags: body.tags ?? old.tags, domain: old.domain, crawlable: body.crawlable ?? old.crawlable,
                forwardQuery: body.forwardQuery ?? old.forwardQuery,
                meta: .init(validSince: body.validSince.flatMap(Self.date), validUntil: body.validUntil.flatMap(Self.date),
                            maxVisits: body.maxVisits)
            )
            store.links[index] = link
            return (200, encode(link))

        case ("DELETE", 2) where path[0] == "short-urls":
            guard store.links.contains(where: { $0.shortCode == path[1] }) else { return notFound() }
            store.links.removeAll { $0.shortCode == path[1] }
            store.visits[path[1]] = nil
            return (204, nil)

        case ("GET", 3) where path[0] == "short-urls" && path[2] == "visits":
            guard var visits = store.visits[path[1]] else { return notFound() }
            if let start = value("startDate").flatMap(Self.date) { visits = visits.filter { $0.date >= start } }
            if let end = value("endDate").flatMap(Self.date) { visits = visits.filter { $0.date <= end } }
            if value("excludeBots") == "true" { visits = visits.filter { !$0.potentialBot } }
            return (200, wrap("visits", page(visits, value("page"), value("itemsPerPage"))))

        default:
            return notFound()
        }
    }

    // MARK: JSON

    private struct Body: Decodable {
        var longUrl: String?
        var title: String?
        var tags: [String]?
        var customSlug: String?
        var validSince: String?
        var validUntil: String?
        var maxVisits: Int?
        var crawlable: Bool?
        var forwardQuery: Bool?
    }

    private func decodeBody(_ data: Data?) -> Body? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Body.self, from: data)
    }

    private static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    /// One page of `items`, in Shlink's `{ data, pagination }` shape. No
    /// `itemsPerPage` (or a negative one) means everything on one page.
    private func page<T: Codable & Sendable & Equatable>(_ items: [T], _ page: String?, _ perPage: String?) -> Pagination<T> {
        let current = max(1, Int(page ?? "") ?? 1)
        let size = Int(perPage ?? "").flatMap { $0 > 0 ? $0 : nil } ?? max(items.count, 1)
        let pages = max(1, Int((Double(items.count) / Double(size)).rounded(.up)))
        let start = min(items.count, (current - 1) * size)
        let slice = Array(items[start..<min(items.count, start + size)])
        return Pagination(data: slice, pagination: PaginationMeta(
            currentPage: current, pagesCount: pages, itemsPerPage: size,
            itemsInCurrentPage: slice.count, totalItems: items.count))
    }

    /// `{ "<key>": <value> }`, the way Shlink nests its paginated payloads.
    private func wrap<T: Encodable>(_ key: String, _ value: T) -> Data {
        Data("{\"\(key)\":".utf8) + encode(value) + Data("}".utf8)
    }

    private func problem(type: String, title: String, customSlug: String? = nil) -> Data {
        var object: [String: Any] = ["type": type, "title": title, "status": 400, "detail": title]
        if let customSlug { object["customSlug"] = customSlug }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private func notFound() -> (status: Int, json: Data?) {
        (404, problem(type: "https://shlink.io/api/error/short-url-not-found", title: "Short URL not found"))
    }
}

// MARK: - URL protocol

/// Answers every request of ``DemoMode/urlSession`` from ``DemoServer``. Hosts
/// that aren't demo servers fail as unreachable: nothing goes to the network.
nonisolated final class DemoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let answer = DemoServer.shared.respond(to: request, body: Self.body(of: request)) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let headers = answer.json == nil ? [:] : ["Content-Type": "application/json"]
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let json = answer.json {
            client?.urlProtocol(self, didLoad: json)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// The request body: `httpBody`, or the stream URLSession turns it into.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

// MARK: - In-memory Keychain

/// The demo servers' "Keychain": the same records ``InstanceStore`` writes to
/// the real Keychain, kept in memory, so the real one is never opened.
nonisolated final class DemoKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: KeychainRecord] = [:]
    private var order: [String] = []
    private var activeID: String?

    func save(_ record: KeychainRecord) throws {
        lock.withLock {
            if records[record.account] == nil { order.append(record.account) }
            records[record.account] = record
        }
    }

    func readSecret(account: String) -> String? {
        lock.withLock { records[account]?.secret }
    }

    func delete(account: String) throws {
        lock.withLock {
            records[account] = nil
            order.removeAll { $0 == account }
        }
    }

    func allRecords() -> [KeychainRecord] {
        lock.withLock { order.compactMap { records[$0] } }
    }

    func readActiveInstanceID() -> String? {
        lock.withLock { activeID }
    }

    func writeActiveInstanceID(_ id: String?) throws {
        lock.withLock { activeID = id }
    }
}
#endif
