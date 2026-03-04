import Foundation
import Logging

/// Catches all errors thrown by downstream middleware/handlers and converts
/// them to structured JSON HTTP responses.
///
/// - `Abort` errors produce the given status code + reason.
/// - All other errors produce HTTP 500 with the localised description.
///
/// Register early in the pipeline so it wraps all subsequent middleware:
///
///     builder.useErrorHandling()
///     builder.useLogging()
///     builder.useJwtAuthentication(...)
public struct ErrorMiddleware: Middleware {
    private let logger: Logger

    public init(label: String = "cosmo.error") {
        self.logger = Logger(label: label)
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        do {
            try await next(context)
        } catch let abort as Abort {
            context.response.setStatus(abort.statusCode)
            try context.response.writeJson(ErrorBody(error: abort.reason))
        } catch {
            logger.error("Unhandled error: \(error)")
            context.response.setStatus(500)
            try context.response.writeJson(ErrorBody(error: error.localizedDescription))
        }
    }

    private struct ErrorBody: Encodable {
        let error: String
    }
}
