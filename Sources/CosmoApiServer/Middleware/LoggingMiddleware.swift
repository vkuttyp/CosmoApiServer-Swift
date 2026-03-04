import Foundation
import Logging

public struct LoggingMiddleware: Middleware {
    private let logger: Logger

    public init(label: String = "cosmo.http") {
        self.logger = Logger(label: label)
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        let req = context.request
        let qs = req.queryString.isEmpty ? "" : "?\(req.queryString)"
        logger.info("--> \(req.method.rawValue) \(req.path)\(qs)")
        let start = Date()
        try await next(context)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        logger.info("<-- \(context.response.statusCode) (\(ms)ms)")
    }
}
