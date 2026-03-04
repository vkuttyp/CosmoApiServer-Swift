import Foundation
import NIOCore
import NIOHTTP1

/// Handler signature for Server-Sent Events endpoints.
///
///     app.sse("/events") { req, stream in
///         for i in 1...5 {
///             try await stream.send(data: "tick \(i)", event: "tick")
///             try await Task.sleep(nanoseconds: 1_000_000_000)
///         }
///         await stream.close()
///     }
public typealias SseHandler = @Sendable (HttpRequest, SseStream) async -> Void

/// Represents an open Server-Sent Events connection to a single client.
///
/// Use `send(data:event:id:)` to push events and `close()` to end the stream.
public final class SseStream: @unchecked Sendable {
    private let channelContext: ChannelHandlerContext
    private var _closed = false

    init(channelContext: ChannelHandlerContext) {
        self.channelContext = channelContext
    }

    // MARK: - Public API

    /// Send an SSE event to the connected client.
    ///
    /// - Parameters:
    ///   - data: The payload (may contain newlines; split into multiple `data:` lines).
    ///   - event: Optional event name sent as `event: <name>`.
    ///   - id: Optional event ID sent as `id: <id>` (for reconnect resume).
    public func send(data: String, event: String? = nil, id: String? = nil) async throws {
        guard !_closed else { return }

        var text = ""
        if let event { text += "event: \(event)\n" }
        if let id    { text += "id: \(id)\n" }
        for line in data.components(separatedBy: "\n") {
            text += "data: \(line)\n"
        }
        text += "\n" // blank line terminates the event

        let ctx = channelContext
        try await ctx.eventLoop.submit {
            var buf = ctx.channel.allocator.buffer(capacity: text.utf8.count)
            buf.writeString(text)
            ctx.writeAndFlush(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buf))), promise: nil)
        }.get()
    }

    /// Close the SSE stream gracefully (sends HTTP end part and closes channel).
    public func close() async {
        guard !_closed else { return }
        _closed = true
        let ctx = channelContext
        try? await ctx.eventLoop.submit {
            ctx.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil))).whenComplete { _ in
                ctx.close(promise: nil)
            }
        }.get()
    }
}
