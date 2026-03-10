import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL

/// Accumulates NIOHTTP1 request parts into a complete HttpRequest.
final class RequestAccumulator: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HttpRequest

    let streamingTable: FrozenRouteTable?

    private var head: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer = ByteBuffer()
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

            if let table = streamingTable {
                let method = HttpMethod(rawValue: h.method.rawValue) ?? .get
                let uri = h.uri
                // Minimal path extraction for streaming check
                let path = uri.split(separator: "?", maxSplits: 1).first.map(String.init) ?? uri
                
                if table.isStreaming(method: method, path: path) {
                    var continuation: AsyncStream<Data>.Continuation!
                    let asyncStream = AsyncStream<Data> { c in continuation = c }
                    let writer = BodyStreamWriter(continuation: continuation)
                    streamWriter = writer
                    let request = buildRequest(head: h, body: ByteBuffer(),
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
                let body = bodyBuffer
                context.fireChannelRead(wrapInboundOut(buildRequest(head: h, body: body)))
                self.head = nil
            }
        }
    }

    private func buildRequest(head: HTTPRequestHead, body: ByteBuffer,
                               bodyStream: BodyStream? = nil) -> HttpRequest {
        return HttpRequest(
            method: HttpMethod(rawValue: head.method.rawValue) ?? .get,
            uri: head.uri,
            headers: head.headers,
            body: body,
            bodyStream: bodyStream
        )
    }
}
