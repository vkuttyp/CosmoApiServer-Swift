import Foundation

public final class HttpContext: @unchecked Sendable {
    public var request: HttpRequest
    public let response: HttpResponse
    public var user: Claims?
    public var items: [String: Any] = [:]

    public init(request: HttpRequest, response: HttpResponse = HttpResponse()) {
        self.request = request
        self.response = response
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
