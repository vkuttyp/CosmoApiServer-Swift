import Foundation
import NIOCore
import NIOHTTP1
import NIOWebSocket

/// A live WebSocket connection. Passed to the user's handler closure.
public final class WebSocket: @unchecked Sendable {
    private let channel: Channel
    private var _onText:   (@Sendable (WebSocket, String) async -> Void)?
    private var _onBinary: (@Sendable (WebSocket, Data)   async -> Void)?
    private var _onClose:  (@Sendable (WebSocket)          async -> Void)?

    public var isOpen: Bool { channel.isActive }

    init(channel: Channel) {
        self.channel = channel
    }

    // MARK: - Event handlers

    @discardableResult
    public func onText(_ handler: @Sendable @escaping (WebSocket, String) async -> Void) -> Self {
        _onText = handler; return self
    }
    @discardableResult
    public func onBinary(_ handler: @Sendable @escaping (WebSocket, Data) async -> Void) -> Self {
        _onBinary = handler; return self
    }
    @discardableResult
    public func onClose(_ handler: @Sendable @escaping (WebSocket) async -> Void) -> Self {
        _onClose = handler; return self
    }

    // MARK: - Send

    public func send(_ text: String) async throws {
        var buffer = channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        try await channel.writeAndFlush(frame)
    }

    public func send(_ data: Data) async throws {
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let frame = WebSocketFrame(fin: true, opcode: .binary, data: buffer)
        try await channel.writeAndFlush(frame)
    }

    public func close() async throws {
        var buffer = channel.allocator.buffer(capacity: 2)
        buffer.writeInteger(UInt16(1000))  // Normal closure code
        let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: buffer)
        try await channel.writeAndFlush(frame)
        try await channel.close()
    }

    // MARK: - Internal dispatch (called by WebSocketFrameHandler)

    func didReceiveText(_ text: String) {
        guard let h = _onText else { return }
        Task { await h(self, text) }
    }
    func didReceiveBinary(_ data: Data) {
        guard let h = _onBinary else { return }
        Task { await h(self, data) }
    }
    func didClose() {
        guard let h = _onClose else { return }
        Task { await h(self) }
    }
}

// MARK: - NIO channel handler for an established WebSocket

final class WebSocketFrameHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let ws: WebSocket
    private var frameAccumulator: ByteBuffer?
    private var accumulatedOpcode: WebSocketOpcode = .text

    init(ws: WebSocket) {
        self.ws = ws
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .text, .binary:
            // Start of a new message (possibly fragmented)
            var buf = frame.unmaskedData
            frameAccumulator = buf
            accumulatedOpcode = frame.opcode
            if frame.fin { dispatchMessage(context: context) }

        case .continuation:
            var buf = frame.unmaskedData
            frameAccumulator?.writeBuffer(&buf)
            if frame.fin { dispatchMessage(context: context) }

        case .ping:
            var pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)

        case .connectionClose:
            ws.didClose()
            context.close(promise: nil)

        default:
            break
        }
    }

    private func dispatchMessage(context: ChannelHandlerContext) {
        guard let buf = frameAccumulator else { return }
        frameAccumulator = nil
        if accumulatedOpcode == .text {
            let text = buf.getString(at: buf.readerIndex, length: buf.readableBytes) ?? ""
            ws.didReceiveText(text)
        } else {
            let bytes = buf.getBytes(at: buf.readerIndex, length: buf.readableBytes) ?? []
            ws.didReceiveBinary(Data(bytes))
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        ws.didClose()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

