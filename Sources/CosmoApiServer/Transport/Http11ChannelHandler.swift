import Foundation
import NIOCore
import NIOHTTP1

/// Per-connection HTTP/1.1 handler: receives complete HttpRequest, invokes the
/// middleware pipeline, writes the HttpResponse.
final class Http11ChannelHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HttpRequest
    typealias OutboundOut = HTTPServerResponsePart

    private let pipeline: RequestDelegate

    init(pipeline: @escaping RequestDelegate) {
        self.pipeline = pipeline
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = unwrapInboundIn(data)
        let keepAlive = request.header("connection")?.lowercased() != "close"

        let ctx = HttpContext(request: request)
        let channel = context.channel

        // Run the middleware pipeline on a detached task so NIO's event loop isn't blocked.
        let pipeline = self.pipeline
        Task {
            do {
                try await pipeline(ctx)
            } catch {
                ctx.response.setStatus(500)
                ctx.response.writeText("Internal Server Error")
            }
            channel.eventLoop.execute {
                ResponseWriter.write(response: ctx.response, context: context, keepAlive: keepAlive)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
