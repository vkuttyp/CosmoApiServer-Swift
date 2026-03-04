import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL

/// Accumulates NIOHTTP1 request parts into a complete HttpRequest.
final class RequestAccumulator: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HttpRequest

    private var head: HTTPRequestHead?
    private var bodyBuffer: ByteBuffer = ByteBuffer()

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let h):
            head = h
            bodyBuffer.clear()
        case .body(var buf):
            bodyBuffer.writeBuffer(&buf)
        case .end:
            guard let head = head else { return }
            // withUnsafeReadableBytes avoids the intermediate [UInt8] allocation
            let body = bodyBuffer.withUnsafeReadableBytes { ptr -> Data in
                Data(bytes: ptr.baseAddress!, count: ptr.count)
            }
            let request = buildRequest(head: head, body: body)
            context.fireChannelRead(wrapInboundOut(request))
            self.head = nil
        }
    }

    private func buildRequest(head: HTTPRequestHead, body: Data) -> HttpRequest {
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
                           headers: headers, body: body)
    }
}
