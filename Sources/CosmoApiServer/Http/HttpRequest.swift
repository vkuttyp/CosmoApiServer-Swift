import Foundation

public struct HttpRequest: Sendable {
    public let method: HttpMethod
    public let path: String
    public let queryString: String
    public let headers: [String: String]
    public let body: Data
    public var routeValues: [String: String]
    /// Non-nil when the route was registered with `streaming: true`.
    /// Iterating this stream yields body chunks as they arrive from the client.
    public let bodyStream: BodyStream?

    public var query: [String: String] {
        guard !queryString.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in queryString.split(separator: "&") {
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
        let lower = name.lowercased()
        return headers.first(where: { $0.key.lowercased() == lower })?.value
    }

    public func readJson<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: body)
    }

    public init(
        method: HttpMethod,
        path: String,
        queryString: String = "",
        headers: [String: String] = [:],
        body: Data = Data(),
        routeValues: [String: String] = [:],
        bodyStream: BodyStream? = nil
    ) {
        self.method = method
        self.path = path
        self.queryString = queryString
        self.headers = headers
        self.body = body
        self.routeValues = routeValues
        self.bodyStream = bodyStream
    }
}
