import Foundation

/// An error that carries an HTTP status code and human-readable reason.
/// Throw this inside any route handler to return a structured error response.
///
///     throw Abort(404, reason: "User not found")
///     throw Abort(400, reason: "Missing required field")
public struct Abort: Error, Sendable {
    public let statusCode: Int
    public let reason: String

    public init(_ statusCode: Int, reason: String = "") {
        self.statusCode = statusCode
        self.reason = reason.isEmpty ? HttpResponse.defaultReasonPhrase(for: statusCode) : reason
    }

    // Convenience static constructors
    public static func badRequest(_ reason: String = "Bad Request") -> Abort { Abort(400, reason: reason) }
    public static func unauthorized(_ reason: String = "Unauthorized") -> Abort { Abort(401, reason: reason) }
    public static func forbidden(_ reason: String = "Forbidden") -> Abort { Abort(403, reason: reason) }
    public static func notFound(_ reason: String = "Not Found") -> Abort { Abort(404, reason: reason) }
    public static func conflict(_ reason: String = "Conflict") -> Abort { Abort(409, reason: reason) }
    public static func internalError(_ reason: String = "Internal Server Error") -> Abort { Abort(500, reason: reason) }
}
