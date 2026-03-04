import Foundation

public struct JwtMiddleware: Middleware {
    private let service: JwtService

    public init(service: JwtService) {
        self.service = service
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        if let auth = context.request.header("authorization"),
           auth.lowercased().hasPrefix("bearer ") {
            let token = String(auth.dropFirst(7))
            context.user = await service.validateToken(token)
        }
        try await next(context)
    }
}
