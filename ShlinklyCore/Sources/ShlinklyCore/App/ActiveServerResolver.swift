import Foundation

/// Why resolving the active server can fail. Surfaced so a host (the app or a
/// Share Extension) can show the right message instead of a generic error.
public enum ActiveServerError: Error, Equatable {
    /// No server could be resolved: either none is configured, or the stored
    /// active selection is absent/stale *and* the list is ambiguous (more than
    /// one server), so there's nothing safe to fall back to.
    case noActiveServer
    /// The active server was found, but its API key isn't in the Keychain.
    case missingKey
}

/// Resolves the active Shlink server straight from the shared Keychain — no
/// ``AppModel``, no ``InstanceStore``, no SwiftUI — so a separate process (a
/// Share Extension) can obtain a ready-to-use client the same way the app would.
///
/// The Keychain is the single source of truth: each server's non-secret metadata
/// rides in its record, the API key is the record's secret, and the per-device
/// active selection is its own reserved item. This mirrors how ``InstanceStore``
/// resolves the active server, but is deliberately standalone and stateless.
public enum ActiveServerResolver {
    /// Returns the active server and a client wired to its ``ServerInstance/restRoot``.
    ///
    /// Resolution: the stored active id when it matches a configured server;
    /// otherwise, if exactly one server exists, that one; otherwise
    /// ``ActiveServerError/noActiveServer``. (Unlike ``InstanceStore``, an
    /// ambiguous list does *not* silently pick the first — the extension can't
    /// show a picker yet, so it errors instead of guessing.)
    ///
    /// - Parameters:
    ///   - keychain: The shared store. Defaults to a ``KeychainStore`` on the
    ///     shared service (``KeychainStore/sharedService``) so the extension and
    ///     the app read the very same items.
    ///   - urlSession: Session for the returned client. Injected for tests.
    /// - Throws: ``ActiveServerError/noActiveServer`` or
    ///   ``ActiveServerError/missingKey``.
    public static func resolve(
        keychain: KeychainStoring = KeychainStore(service: KeychainStore.sharedService),
        urlSession: URLSession = .shared
    ) throws -> (instance: ServerInstance, client: ShlinkClient) {
        let instances = configuredInstances(from: keychain)

        let instance: ServerInstance
        if let raw = keychain.readActiveInstanceID(),
           let id = UUID(uuidString: raw),
           let match = instances.first(where: { $0.id == id }) {
            instance = match
        } else if instances.count == 1 {
            instance = instances[0]
        } else {
            throw ActiveServerError.noActiveServer
        }

        guard let key = keychain.readSecret(account: instance.id.uuidString), !key.isEmpty else {
            throw ActiveServerError.missingKey
        }

        let client = ShlinkClient(baseURL: instance.restRoot, apiKey: key, urlSession: urlSession)
        return (instance, client)
    }

    /// Every configured server, rebuilt by decoding each record's metadata.
    /// `allRecords()` already drops the reserved active-id item; undecodable
    /// blobs are skipped. Order is unspecified — resolution matches by id or by
    /// being the sole entry, neither of which depends on order.
    private static func configuredInstances(from keychain: KeychainStoring) -> [ServerInstance] {
        let decoder = JSONDecoder()
        return keychain.allRecords().compactMap { record in
            try? decoder.decode(StoredMetadata.self, from: record.metadata).instance
        }
    }
}
