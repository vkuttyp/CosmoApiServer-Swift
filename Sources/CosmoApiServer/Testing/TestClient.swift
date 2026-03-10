import Foundation
import NIOCore
import NIOHTTP1

// MARK: - TestResponse

public struct TestResponse: Sendable {
    public let statusCode: Int
    public let headers: HTTPHeaders
    public let body: Data

    public var text: String { String(data: body, encoding: .utf8) ?? "" }

    public func json<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(type, from: body)
    }

    public var isOk: Bool { (200..<300).contains(statusCode) }

    init(context: HttpContext) {
        self.statusCode = context.response.statusCode
        self.headers = context.response.headers
        self.body = context.response.body.withUnsafeReadableBytes { ptr in
            Data(bytes: ptr.baseAddress!, count: ptr.count)
        }
    }
}

// MARK: - TestClient

public final class TestClient: Sendable {
    private let pipeline: RequestDelegate
    private let streamingTable: FrozenRouteTable?
    private weak var application: CosmoWebApplication?

    public init(pipeline: @escaping RequestDelegate, streamingTable: FrozenRouteTable? = nil, application: CosmoWebApplication? = nil) {
        self.pipeline = pipeline
        self.streamingTable = streamingTable
        self.application = application
    }

    public func get(_ path: String, headers: [String: String] = [:]) async throws -> TestResponse {
        try await send(method: .get, path: path, headers: headers, body: ByteBuffer())
    }

    public func post(_ path: String, body: ByteBuffer = ByteBuffer(), headers: [String: String] = [:]) async throws -> TestResponse {
        try await send(method: .post, path: path, headers: headers, body: body)
    }

    public func put(_ path: String, body: ByteBuffer = ByteBuffer(), headers: [String: String] = [:]) async throws -> TestResponse {
        try await send(method: .put, path: path, headers: headers, body: body)
    }

    public func patch(_ path: String, body: ByteBuffer = ByteBuffer(), headers: [String: String] = [:]) async throws -> TestResponse {
        try await send(method: .patch, path: path, headers: headers, body: body)
    }

    public func delete(_ path: String, headers: [String: String] = [:]) async throws -> TestResponse {
        try await send(method: .delete, path: path, headers: headers, body: ByteBuffer())
    }

    public func postJson<T: Encodable>(_ path: String, value: T, headers: [String: String] = [:]) async throws -> TestResponse {
        let data = try JSONEncoder().encode(value)
        var buf = ByteBuffer()
        buf.writeBytes(data)
        var hdrs = headers
        hdrs["Content-Type"] = "application/json"
        return try await send(method: .post, path: path, headers: hdrs, body: buf)
    }

    private func send(
        method: HttpMethod,
        path: String,
        headers: [String: String],
        body: ByteBuffer
    ) async throws -> TestResponse {
        let parts = path.split(separator: "?", maxSplits: 1)
        let cleanPath = String(parts[0])

        var bodyStream: BodyStream? = nil
        var requestBody = body
        if let table = streamingTable, table.isStreaming(method: method, path: cleanPath) {
            var continuation: AsyncStream<Data>.Continuation!
            let asyncStream = AsyncStream<Data> { c in continuation = c }
            bodyStream = BodyStream(stream: asyncStream)
            let bytes = body.getBytes(at: body.readerIndex, length: body.readableBytes) ?? []
            requestBody = ByteBuffer()
            if !bytes.isEmpty { continuation.yield(Data(bytes)) }
            continuation.finish()
        }

        let nioHeaders = HTTPHeaders(headers.map { kv in (kv.key, kv.value) })
        let request = HttpRequest(
            method: method,
            uri: path,
            headers: nioHeaders,
            body: requestBody,
            bodyStream: bodyStream
        )
        let context = HttpContextPool.shared.rent(request: request, application: application)
        do {
            try await pipeline(context)
        } catch {
            context.response.setStatus(500)
            context.response.writeText("Internal Server Error: \(error)")
        }
        let response = TestResponse(context: context)
        HttpContextPool.shared.return(context)
        return response
    }
}
