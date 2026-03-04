import Foundation
import NIOCore
import NIOHTTP1

/// Per-connection HTTP/1.1 handler: receives complete HttpRequest, invokes the
/// middleware pipeline, writes the HttpResponse.
final class Http11ChannelHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HttpRequest
    typealias OutboundOut = HTTPServerResponsePart

    private let pipeline: RequestDelegate
    private let sseRoutes: [(path: String, handler: SseHandler)]

    init(pipeline: @escaping RequestDelegate, sseRoutes: [(path: String, handler: SseHandler)] = []) {
        self.pipeline = pipeline
        self.sseRoutes = sseRoutes
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = unwrapInboundIn(data)

        // Check for SSE route match first
        if let sseHandler = sseRoutes.first(where: { $0.path == request.path })?.handler {
            handleSSE(context: context, request: request, handler: sseHandler)
            return
        }

        // Normal HTTP: run middleware pipeline then write response
        let keepAlive = request.header("connection")?.lowercased() != "close"
        let ctx = HttpContext(request: request)
        let channel = context.channel
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

    // MARK: - SSE

    private func handleSSE(context: ChannelHandlerContext, request: HttpRequest, handler: @escaping SseHandler) {
        // Write SSE response headers immediately
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/event-stream")
        headers.add(name: "Cache-Control", value: "no-cache")
        headers.add(name: "X-Accel-Buffering", value: "no")
        headers.add(name: "Connection", value: "keep-alive")

        let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
        context.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)
        context.flush()

        let stream = SseStream(channelContext: context)

        Task {
            await handler(request, stream)
            await stream.close()  // safe to call twice — idempotent
        }
    }
}
