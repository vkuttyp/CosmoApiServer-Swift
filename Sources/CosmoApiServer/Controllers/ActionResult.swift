import Foundation

public protocol ActionResult: Sendable {
    func execute(response: HttpResponse) async throws
}

// MARK: - Concrete results

public struct StatusCodeResult: ActionResult {
    let code: Int
    public init(_ code: Int) { self.code = code }
    public func execute(response: HttpResponse) async { response.setStatus(code) }
}

public struct TextResult: ActionResult {
    let code: Int
    let text: String
    let contentType: String
    public init(_ text: String, status: Int = 200, contentType: String = "text/plain; charset=utf-8") {
        self.text = text; self.code = status; self.contentType = contentType
    }
    public func execute(response: HttpResponse) async throws {
        response.setStatus(code)
        response.writeText(text, contentType: contentType)
    }
}

public struct JsonResult<T: Encodable & Sendable>: ActionResult {
    let value: T
    let code: Int
    public init(_ value: T, status: Int = 200) { self.value = value; self.code = status }
    public func execute(response: HttpResponse) async throws {
        response.setStatus(code)
        try response.writeJson(value)
    }
}

public struct CreatedResult<T: Encodable & Sendable>: ActionResult {
    let value: T
    let location: String
    public init(at location: String, value: T) { self.location = location; self.value = value }
    public func execute(response: HttpResponse) async throws {
        response.setStatus(201)
        response.setHeader("Location", location)
        try response.writeJson(value)
    }
}

public struct NoContentResult: ActionResult {
    public init() {}
    public func execute(response: HttpResponse) async { response.setStatus(204) }
}
