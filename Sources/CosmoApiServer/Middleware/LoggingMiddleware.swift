import Foundation
import Logging

public struct LoggingMiddleware: Middleware {
    private let logger: Logger

    public init(label: String = "cosmo.http") {
        self.logger = Logger(label: label)
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        // Optimization: Only do string work if we are going to log
        if logger.logLevel <= .info {
            let req = context.request
            let qs = req.queryString.isEmpty ? "" : "?\(req.queryString)"
            logger.info("--> \(req.method.rawValue) \(req.path)\(qs)")
        }
        
        let start = DispatchTime.now()
        try await next(context)
        
        if logger.logLevel <= .info {
            let end = DispatchTime.now()
            let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
            let ms = Double(nanoTime) / 1_000_000
            logger.info("<-- \(context.response.statusCode) (\(String(format: "0.00", ms))ms)")
        }
    }
}
