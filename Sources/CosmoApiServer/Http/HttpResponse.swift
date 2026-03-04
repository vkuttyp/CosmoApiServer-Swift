import Foundation

public final class HttpResponse: @unchecked Sendable {
    public var statusCode: Int = 200
    public var reasonPhrase: String = "OK"
    public var headers: [String: String] = [:]
    public var body: Data = Data()

    public init() {}

    public func write(_ data: Data) {
        body = data
        headers["Content-Length"] = String(data.count)
    }

    public func writeText(_ text: String, contentType: String = "text/plain; charset=utf-8") {
        let data = Data(text.utf8)
        headers["Content-Type"] = contentType
        write(data)
    }

    public func writeJson<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(value)
        headers["Content-Type"] = "application/json; charset=utf-8"
        write(data)
    }

    public func setStatus(_ code: Int) {
        statusCode = code
        reasonPhrase = Self.reasonPhrase(for: code)
    }

    static func reasonPhrase(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 503: return "Service Unavailable"
        default:  return "Unknown"
        }
    }
}
