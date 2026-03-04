import Foundation

public struct RouterMiddleware: Middleware {
    // Frozen (lock-free) snapshot taken once at pipeline build time.
    private let frozen: FrozenRouteTable

    public init(routeTable: RouteTable) {
        self.frozen = routeTable.freeze()
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        if let (handler, routeValues) = frozen.match(method: context.request.method, path: context.request.path) {
            context.request.routeValues = routeValues
            try await handler(context)
        } else {
            try await next(context)
        }
    }
}
