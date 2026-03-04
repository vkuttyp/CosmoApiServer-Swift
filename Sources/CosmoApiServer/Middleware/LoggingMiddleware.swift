import Foundation

public struct LoggingMiddleware: Middleware {
    public init() {}

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        let req = context.request
        let qs = req.queryString.isEmpty ? "" : "?\(req.queryString)"
        print("--> \(req.method.rawValue) \(req.path)\(qs)")
        let start = Date()
        try await next(context)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("<-- \(context.response.statusCode) (\(ms)ms)")
    }
}
