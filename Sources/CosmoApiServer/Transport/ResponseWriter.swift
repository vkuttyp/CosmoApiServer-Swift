import Foundation
import NIOCore
import NIOHTTP1

/// Writes a completed HttpResponse back as NIOHTTP1 response parts.
enum ResponseWriter {
    static func write(response: HttpResponse, context: ChannelHandlerContext, keepAlive: Bool) {
        var headers = HTTPHeaders()
        for (k, v) in response.headers {
            headers.add(name: k, value: v)
        }
        if headers["Content-Length"].isEmpty {
            headers.replaceOrAdd(name: "Content-Length", value: String(response.body.count))
        }
        headers.replaceOrAdd(name: "Connection", value: keepAlive ? "keep-alive" : "close")

        let status = HTTPResponseStatus(statusCode: response.statusCode,
                                        reasonPhrase: response.reasonPhrase)
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)

        context.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)

        if !response.body.isEmpty {
            var buf = context.channel.allocator.buffer(capacity: response.body.count)
            buf.writeBytes(response.body)
            context.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buf))), promise: nil)
        }

        if keepAlive {
            context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
        } else {
            context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil))).whenComplete { _ in
                context.close(promise: nil)
            }
        }
    }
}
