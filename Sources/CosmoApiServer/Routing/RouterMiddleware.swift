import Foundation

public struct RouterMiddleware: Middleware {
    private let routeTable: RouteTable

    public init(routeTable: RouteTable) {
        self.routeTable = routeTable
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        if let (handler, routeValues) = routeTable.match(method: context.request.method, path: context.request.path) {
            context.request.routeValues = routeValues
            try await handler(context)
        } else {
            try await next(context)
        }
    }
}
