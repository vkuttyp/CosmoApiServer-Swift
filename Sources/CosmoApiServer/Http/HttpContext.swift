import Foundation

public final class HttpContext: @unchecked Sendable {
    public weak var application: CosmoWebApplication?
    public var request: HttpRequest
    public let response: HttpResponse
    public var user: Claims?
    public var items: [String: Any] = [:]

    public func reset() {
        response.reset()
        response.httpContext = self
        user = nil
        items.removeAll(keepingCapacity: true)
    }

    public init(request: HttpRequest, response: HttpResponse = HttpResponse()) {
        self.request = request
        self.response = response
        self.response.httpContext = self
    }
}

/// Lightweight claims container (replaces ClaimsPrincipal).
public struct Claims: Sendable {
    public let values: [String: String]

    public subscript(key: String) -> String? { values[key] }

    public var subject: String? { values["sub"] }
    public var name: String? { values["name"] }
    public var email: String? { values["email"] }

    public init(_ values: [String: String]) {
        self.values = values
    }
}
