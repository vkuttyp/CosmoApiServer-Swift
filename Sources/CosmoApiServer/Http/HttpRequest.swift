import Foundation
import NIOCore
import NIOHTTP1

public struct HttpRequest: Sendable {
    public let method: HttpMethod
    public let uri: String
    public let headers: HTTPHeaders
    public let body: ByteBuffer
    public var routeValues: [String: String]
    public let bodyStream: BodyStream?

    // Lazy parsing of path and query string to avoid eager allocations
    public var path: String {
        if let qi = uri.firstIndex(of: "?") {
            return String(uri[..<qi])
        }
        return uri
    }

    public var queryString: String {
        if let qi = uri.firstIndex(of: "?") {
            return String(uri[uri.index(after: qi)...])
        }
        return ""
    }

    public var query: [String: String] {
        let qs = queryString
        guard !qs.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in qs.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                let val = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                result[key] = val
            } else if parts.count == 1 {
                result[String(parts[0])] = ""
            }
        }
        return result
    }

    public func header(_ name: String) -> String? {
        headers.first(name: name)
    }

    public func readJson<T: Decodable>(_ type: T.Type) throws -> T {
        return try body.withUnsafeReadableBytes { ptr in
            try JSONResource.decoder.decode(type, from: Data(bytes: ptr.baseAddress!, count: ptr.count))
        }
    }

    public func readMultipart() throws -> MultipartForm {
        try MultipartParser.parse(self)
    }

    public init(
        method: HttpMethod,
        uri: String,
        headers: HTTPHeaders = HTTPHeaders(),
        body: ByteBuffer = ByteBuffer(),
        routeValues: [String: String] = [:],
        bodyStream: BodyStream? = nil
    ) {
        self.method = method
        self.uri = uri
        self.headers = headers
        self.body = body
        self.routeValues = routeValues
        self.bodyStream = bodyStream
    }
}
