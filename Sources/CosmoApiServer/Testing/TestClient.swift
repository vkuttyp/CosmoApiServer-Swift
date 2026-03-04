import Foundation

// MARK: - TestResponse

/// The result of a `TestClient` request.
public struct TestResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    /// The response body as a UTF-8 string.
    public var text: String {
        String(data: body, encoding: .utf8) ?? ""
    }

    /// Decode the response body as JSON.
    public func json<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(type, from: body)
    }

    /// Returns `true` when the status code indicates success (2xx).
    public var isOk: Bool { (200..<300).contains(statusCode) }

    init(context: HttpContext) {
        self.statusCode = context.response.statusCode
        self.headers = context.response.headers
        self.body = context.response.body
    }
}

// MARK: - TestClient

/// An in-process HTTP test client that calls the middleware pipeline directly —
/// no network binding required.
///
///     let client = app.testClient()
///     let res = try await client.get("/health")
///     XCTAssertEqual(res.statusCode, 200)
///
///     let res2 = try await client.post("/users", body: Data(#"{"name":"Alice"}"#.utf8))
///     XCTAssertEqual(res2.statusCode, 201)
public final class TestClient: Sendable {
    private let pipeline: RequestDelegate
    /// If set, streaming routes are detected and body data is delivered chunk-by-chunk.
    private let streamingTable: FrozenRouteTable?

    /// Create a `TestClient` from a built pipeline delegate.
    public init(pipeline: @escaping RequestDelegate, streamingTable: FrozenRouteTable? = nil) {
        self.pipeline = pipeline
        self.streamingTable = streamingTable
    }

    // MARK: - HTTP methods

    public func get(_ path: String, headers: [String: String] = [:]) async throws -> TestResponse {
        try await send(method: .get, path: path, headers: headers, body: Data())
    }

    public func post(_ path: String, body: Data = Data(), headers: [String: String] = [:]) async throws -> TestResponse {
        try await send(method: .post, path: path, headers: headers, body: body)
    }

    public func put(_ path: String, body: Data = Data(), headers: [String: String] = [:]) async throws -> TestResponse {
        try await send(method: .put, path: path, headers: headers, body: body)
    }

    public func patch(_ path: String, body: Data = Data(), headers: [String: String] = [:]) async throws -> TestResponse {
        try await send(method: .patch, path: path, headers: headers, body: body)
    }

    public func delete(_ path: String, headers: [String: String] = [:]) async throws -> TestResponse {
        try await send(method: .delete, path: path, headers: headers, body: Data())
    }

    /// Send JSON-encodable body; sets `Content-Type: application/json` automatically.
    public func postJson<T: Encodable>(_ path: String, value: T, headers: [String: String] = [:]) async throws -> TestResponse {
        let body = try JSONEncoder().encode(value)
        var hdrs = headers
        hdrs["Content-Type"] = "application/json"
        return try await send(method: .post, path: path, headers: hdrs, body: body)
    }

    // MARK: - Core

    private func send(
        method: HttpMethod,
        path: String,
        headers: [String: String],
        body: Data
    ) async throws -> TestResponse {
        // Parse path and query string
        let parts = path.split(separator: "?", maxSplits: 1)
        let cleanPath = String(parts[0])
        let queryString = parts.count > 1 ? String(parts[1]) : ""

        // For streaming routes, wrap the body in an AsyncStream delivered as a single chunk.
        var bodyStream: BodyStream? = nil
        var requestBody = body
        if let table = streamingTable, table.isStreaming(method: method, path: cleanPath) {
            var continuation: AsyncStream<Data>.Continuation!
            let asyncStream = AsyncStream<Data> { continuation = $0 }
            bodyStream = BodyStream(stream: asyncStream)
            requestBody = Data()  // don't put body in .body; deliver via stream
            if !body.isEmpty { continuation.yield(body) }
            continuation.finish()
        }

        let request = HttpRequest(
            method: method,
            path: cleanPath,
            queryString: queryString,
            headers: headers,
            body: requestBody,
            bodyStream: bodyStream
        )
        let context = HttpContext(request: request)
        do {
            try await pipeline(context)
        } catch {
            context.response.setStatus(500)
            context.response.writeText("Internal Server Error: \(error)")
        }
        return TestResponse(context: context)
    }
}
