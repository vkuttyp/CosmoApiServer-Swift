import Foundation
import NIOCore
import NIOHTTP1

/// Writes a completed HttpResponse back as NIOHTTP1 response parts.
enum ResponseWriter {
    static func write(response: HttpResponse, context: ChannelHandlerContext, keepAlive: Bool) {
        // HTTPHeaders is already efficient and provides case-insensitive lookup.
        if !response.headers.contains(name: "Content-Length") {
            response.headers.replaceOrAdd(name: "Content-Length", value: String(response.body.readableBytes))
        }
        response.headers.replaceOrAdd(name: "Connection", value: keepAlive ? "keep-alive" : "close")

        let status = HTTPResponseStatus(statusCode: response.statusCode,
                                        reasonPhrase: response.reasonPhrase)
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: response.headers)

        context.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)

        if response.body.readableBytes > 0 {
            context.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(response.body))), promise: nil)
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
