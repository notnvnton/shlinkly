import Foundation

extension ShlinkError {
    /// A short, user-facing sentence describing an error thrown by the client.
    ///
    /// Lives here so every store maps failures the same way. Stores filter out
    /// `CancellationError` before presenting, so the catch-all `default` only
    /// ever covers genuinely unexpected errors.
    public static func userFacingMessage(for error: Error) -> String {
        switch error {
        case ShlinkError.unauthorized:
            return "Your API key was rejected. Check the server credentials."
        case ShlinkError.notFound:
            return "The server endpoint could not be found."
        case ShlinkError.networkError(let underlying):
            // Only genuine "the server couldn't be reached" connectivity failures
            // get the connectivity message. Anything else — e.g. the connection
            // dropping *after* the server already processed the request, which is
            // why a successful delete used to report "couldn't reach the server" —
            // keeps its real reason rather than masquerading as unreachable.
            if let urlError = underlying as? URLError, connectivityCodes.contains(urlError.code) {
                return "Couldn't reach the server. Check your connection and try again."
            }
            return "The request couldn't be completed: \(underlying.localizedDescription)"
        case ShlinkError.unexpectedStatus(let code):
            return "The server returned an unexpected response (HTTP \(code))."
        case ShlinkError.slugInUse:
            return "That custom slug is already taken."
        case ShlinkError.deletionForbidden(let threshold):
            return "This link can't be deleted: it has more than \(threshold) visits, and the server protects it from deletion."
        case ShlinkError.invalidData(let elements):
            return elements.isEmpty
                ? "Some fields weren't accepted. Check them and try again."
                : "These fields weren't accepted: \(elements.joined(separator: ", "))."
        case ShlinkError.apiError(let problem):
            return problem.detail ?? problem.title ?? "The server returned an error."
        case ShlinkError.decodingError:
            return "The server sent a response the app couldn't read."
        default:
            return "Something went wrong. Please try again."
        }
    }

    /// The `URLError` codes that genuinely mean "the server couldn't be reached".
    /// Other transport errors (e.g. `networkConnectionLost`, which can fire after
    /// the request was already processed server-side) are deliberately excluded so
    /// they don't masquerade as a connectivity problem.
    private static let connectivityCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .cannotConnectToHost,
        .timedOut,
        .cannotFindHost,
    ]
}
