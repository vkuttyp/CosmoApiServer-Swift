import Foundation

public struct CorsOptions: Sendable {
    public var allowedOrigins: [String]
    public var allowedMethods: [String]
    public var allowedHeaders: [String]

    public init(
        allowedOrigins: [String] = ["*"],
        allowedMethods: [String] = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
        allowedHeaders: [String] = ["Content-Type", "Authorization"]
    ) {
        self.allowedOrigins = allowedOrigins
        self.allowedMethods = allowedMethods
        self.allowedHeaders = allowedHeaders
    }
}

public struct CorsMiddleware: Middleware {
    private let options: CorsOptions
    private let allowedMethodsValue: String
    private let allowedHeadersValue: String

    public init(options: CorsOptions = CorsOptions()) {
        self.options = options
        self.allowedMethodsValue = options.allowedMethods.joined(separator: ", ")
        self.allowedHeadersValue = options.allowedHeaders.joined(separator: ", ")
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        let origin = context.request.header("Origin") ?? "*"
        let allowed = options.allowedOrigins.contains("*") || options.allowedOrigins.contains(origin)

        if allowed {
            let responseOrigin = options.allowedOrigins.contains("*") ? "*" : origin
            context.response.headers["Access-Control-Allow-Origin"] = responseOrigin
            context.response.headers["Access-Control-Allow-Methods"] = allowedMethodsValue
            context.response.headers["Access-Control-Allow-Headers"] = allowedHeadersValue
        }

        if context.request.method == .options {
            context.response.setStatus(204)
            return
        }

        try await next(context)
    }
}
