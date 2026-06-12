import Foundation
import Observation

/// An in-memory cache of every tag name on the server, shared by the list
/// screen's search suggestions (iPhone) and the tag sidebar (macOS).
///
/// Tags rarely change within a session and the full set is small, so this loads
/// the whole list once and keeps it in memory — no paging cursor, no disk cache.
/// Loading is best-effort: a failure leaves the cache empty and unmarked so the
/// next appearance retries, and tag *suggestions* are only ever an enhancement
/// over the URL/code search, never a blocker.
@MainActor
@Observable
public final class TagsStore {
    /// Every known tag name, sorted case-insensitively. Empty until loaded.
    public private(set) var tags: [String] = []
    /// Whether a successful load has populated ``tags``. Stays `false` after a
    /// failure so ``loadIfNeeded()`` will try again.
    public private(set) var isLoaded = false

    private let client: ShlinkClient
    private var loadTask: Task<Void, Never>?

    public init(client: ShlinkClient) {
        self.client = client
    }

    /// Loads and caches all tag names once. No-op if already loaded or a load is
    /// already in flight. Safe to call from several `.task` modifiers (list +
    /// sidebar) — only the first does work.
    public func loadIfNeeded() {
        guard !isLoaded, loadTask == nil else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            defer { self.loadTask = nil }
            do {
                let names = try await self.client.allTags()
                guard !Task.isCancelled else { return }
                self.tags = names.sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
                self.isLoaded = true
            } catch {
                // Leave isLoaded false so a later appearance retries.
            }
        }
    }

    /// Tag names that contain `query` (case-insensitive), capped at `limit`.
    /// An empty query yields nothing — suggestions appear only while typing.
    public func suggestions(for query: String, limit: Int = 8) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return tags
            .filter { $0.localizedCaseInsensitiveContains(trimmed) }
            .prefix(limit)
            .map { $0 }
    }
}
