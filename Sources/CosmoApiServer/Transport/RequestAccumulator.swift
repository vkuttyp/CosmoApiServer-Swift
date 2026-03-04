import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL

/// Accumulates NIOHTTP1 request parts into a complete HttpRequest.
///
/// When a route is registered with `streaming: true`, the accumulator fires the request
/// IMMEDIATELY on `.head` with `bodyStream` set. Subsequent `.body` chunks are yielded
/// into the stream as they arrive from the client. The handler and NIO run concurrently.
final class RequestAccumulator: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HttpRequest

    // Injected at server build time; nil ⇒ no streaming routes registered.
    let streamingTable: FrozenRouteTable?

    private var head: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer = ByteBuffer()
    // Non-nil only when the current request is in streaming mode.
    private var streamWriter: BodyStreamWriter?

    init(streamingTable: FrozenRouteTable? = nil) {
        self.streamingTable = streamingTable
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let h):
            head = h
            bodyBuffer.clear()
            streamWriter = nil

            // Check if this request matches a streaming route.
            if let table = streamingTable {
                let method = HttpMethod(rawValue: h.method.rawValue) ?? .get
                var path = h.uri
                if let qi = path.firstIndex(of: "?") { path = String(path[path.startIndex..<qi]) }
                if table.isStreaming(method: method, path: path) {
                    // Streaming: deliver request immediately with a live BodyStream.
                    var continuation: AsyncStream<Data>.Continuation!
                    let asyncStream = AsyncStream<Data> { continuation = $0 }
                    let writer = BodyStreamWriter(continuation: continuation)
                    streamWriter = writer
                    let request = buildRequest(head: h, body: Data(),
                                               bodyStream: BodyStream(stream: asyncStream))
                    context.fireChannelRead(wrapInboundOut(request))
                }
            }

        case .body(var buf):
            if let writer = streamWriter {
                writer.yield(buf)
            } else {
                bodyBuffer.writeBuffer(&buf)
            }

        case .end:
            if let writer = streamWriter {
                writer.finish()
                streamWriter = nil
                head = nil
            } else {
                guard let h = head else { return }
                let body = bodyBuffer.withUnsafeReadableBytes { ptr -> Data in
                    Data(bytes: ptr.baseAddress!, count: ptr.count)
                }
                context.fireChannelRead(wrapInboundOut(buildRequest(head: h, body: body)))
                self.head = nil
            }
        }
    }

    private func buildRequest(head: HTTPRequestHead, body: Data,
                               bodyStream: BodyStream? = nil) -> HttpRequest {
        let method = HttpMethod(rawValue: head.method.rawValue) ?? .get
        var path = head.uri
        var queryString = ""
        if let qi = path.firstIndex(of: "?") {
            queryString = String(path[path.index(after: qi)...])
            path = String(path[path.startIndex..<qi])
        }
        var headers: [String: String] = [:]
        for (name, value) in head.headers {
            headers[name.lowercased()] = value
        }
        return HttpRequest(method: method, path: path, queryString: queryString,
                           headers: headers, body: body, bodyStream: bodyStream)
    }
}
