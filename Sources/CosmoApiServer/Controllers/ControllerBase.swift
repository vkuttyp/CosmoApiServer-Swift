import Foundation

/// Base class for route controllers. Subclass and implement `registerRoutes(on:)`.
open class ControllerBase: @unchecked Sendable {
    public var context: HttpContext!

    public var request: HttpRequest { context.request }
    public var response: HttpResponse { context.response }

    public required init() {}

    // MARK: - Action result helpers

    public func ok<T: Encodable & Sendable>(_ value: T) -> any ActionResult {
        JsonResult(value, status: 200)
    }

    public func ok() -> any ActionResult {
        StatusCodeResult(200)
    }

    public func created<T: Encodable & Sendable>(at location: String, _ value: T) -> any ActionResult {
        CreatedResult(at: location, value: value)
    }

    public func noContent() -> any ActionResult {
        NoContentResult()
    }

    public func notFound(_ message: String = "Not Found") -> any ActionResult {
        TextResult(message, status: 404)
    }

    public func badRequest(_ message: String = "Bad Request") -> any ActionResult {
        TextResult(message, status: 400)
    }

    public func unauthorized(_ message: String = "Unauthorized") -> any ActionResult {
        TextResult(message, status: 401)
    }

    public func statusCode(_ code: Int) -> any ActionResult {
        StatusCodeResult(code)
    }
}

/// Protocol that controllers implement to register their routes.
public protocol Controller: ControllerBase {
    static func registerRoutes(on app: CosmoWebApplication)
}
