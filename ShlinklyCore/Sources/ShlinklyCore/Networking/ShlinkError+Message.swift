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
        case ShlinkError.networkError:
            return "Couldn't reach the server. Check your connection and try again."
        case ShlinkError.apiError(let problem):
            return problem.detail ?? problem.title ?? "The server returned an error."
        case ShlinkError.decodingError:
            return "The server sent a response the app couldn't read."
        default:
            return "Something went wrong. Please try again."
        }
    }
}
