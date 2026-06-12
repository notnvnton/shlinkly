import Foundation
import Observation

/// Top-level application state: which Shlink server is active, and a client
/// configured to talk to it.
///
/// Consumers depend only on ``activeInstance`` and ``client``. *How* the active
/// server and its API key are sourced is deliberately hidden behind
/// ``activate(_:apiKey:)``. In Phase 1 the app calls that once at launch with
/// values from the local dev config; a later layer will instead load them from
/// the Keychain and call the very same method — no consumer changes required.
@MainActor
@Observable
public final class AppModel {
    /// The server currently in use, or `nil` when none is configured.
    public private(set) var activeInstance: ServerInstance?

    /// A client wired to ``activeInstance``, or `nil` when none is configured.
    /// Rebuilt whenever the active server changes.
    public private(set) var client: ShlinkClient?

    /// Session used for every client this model vends. Injected for testability.
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Makes `instance` the active server and (re)builds ``client`` with the
    /// given key. This is the single seam through which credentials enter the
    /// app; the caller owns where `apiKey` comes from (dev config now, Keychain
    /// later).
    public func activate(_ instance: ServerInstance, apiKey: String) {
        activeInstance = instance
        client = ShlinkClient(baseURL: instance.baseURL, apiKey: apiKey, urlSession: urlSession)
    }

    /// Clears the active server and tears down the client.
    public func deactivate() {
        activeInstance = nil
        client = nil
    }
}
