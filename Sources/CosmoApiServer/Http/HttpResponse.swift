import Foundation
import NIOCore
import NIOHTTP1

public final class HttpResponse: @unchecked Sendable {
    public weak var httpContext: HttpContext?
    public var statusCode: Int = 200
    public var reasonPhrase: String = "OK"
    public var headers: HTTPHeaders = HTTPHeaders()
    public var body: ByteBuffer = ByteBuffer()

    public init() {}

    public func reset() {
        statusCode = 200
        reasonPhrase = "OK"
        headers = HTTPHeaders()
        body.clear()
    }

    public func setStatus(_ code: Int, reason: String? = nil) {
        self.statusCode = code
        if let reason = reason {
            self.reasonPhrase = reason
        } else {
            self.reasonPhrase = Self.defaultReasonPhrase(for: code)
        }
    }

    public func setHeader(_ name: String, _ value: String) {
        headers.replaceOrAdd(name: name, value: value)
    }

    public func write(_ data: Data) {
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        write(buffer)
    }

    public func write(_ buffer: ByteBuffer) {
        var mutableBuffer = buffer
        body.writeBuffer(&mutableBuffer)
        headers.replaceOrAdd(name: "Content-Length", value: String(body.readableBytes))
    }

    public func writeText(_ text: String, contentType: String = "text/plain; charset=utf-8") {
        headers.replaceOrAdd(name: "Content-Type", value: contentType)
        body.writeString(text)
        headers.replaceOrAdd(name: "Content-Length", value: String(body.readableBytes))
    }

    public func writeHTML(_ component: any Component) {
        headers.replaceOrAdd(name: "Content-Type", value: "text/html; charset=utf-8")
        component.write(to: &body)
        headers.replaceOrAdd(name: "Content-Length", value: String(body.readableBytes))
    }

    public func writeJson<T: Encodable>(_ value: T) throws {
        let data = try JSONResource.encoder.encode(value)
        headers.replaceOrAdd(name: "Content-Type", value: "application/json")
        body.writeBytes(data)
        headers.replaceOrAdd(name: "Content-Length", value: String(body.readableBytes))
    }

    public static func defaultReasonPhrase(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 307: return "Temporary Redirect"
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
