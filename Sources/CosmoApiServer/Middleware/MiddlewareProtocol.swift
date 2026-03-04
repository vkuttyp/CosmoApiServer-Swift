import Foundation

public typealias RequestDelegate = @Sendable (HttpContext) async throws -> Void

public protocol Middleware: Sendable {
    func invoke(_ context: HttpContext, next: RequestDelegate) async throws
}
