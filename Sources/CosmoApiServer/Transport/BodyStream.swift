import Foundation
import NIOCore

// MARK: - BodyStream

/// An async sequence of `Data` chunks for streaming request bodies.
///
/// Usage in a streaming route handler:
/// ```swift
/// app.put("/upload/{bucket}/{key:path}", streaming: true) { ctx in
///     guard let stream = ctx.request.bodyStream else { return }
///     for await chunk in stream {
///         // write chunk to disk / forward to storage …
///     }
///     try ctx.response.write(HttpResponse(status: 200))
/// }
/// ```
public struct BodyStream: AsyncSequence, Sendable {
    public typealias Element = Data

    let stream: AsyncStream<Data>

    init(stream: AsyncStream<Data>) {
        self.stream = stream
    }

    public func makeAsyncIterator() -> AsyncStream<Data>.AsyncIterator {
        stream.makeAsyncIterator()
    }
}

// MARK: - BodyStreamWriter (internal — used by RequestAccumulator)

/// Thread-safe wrapper that feeds NIO ByteBuffer chunks into a BodyStream.
final class BodyStreamWriter: @unchecked Sendable {
    private let continuation: AsyncStream<Data>.Continuation

    init(continuation: AsyncStream<Data>.Continuation) {
        self.continuation = continuation
    }

    func yield(_ buf: ByteBuffer) {
        guard buf.readableBytes > 0 else { return }
        let data = buf.withUnsafeReadableBytes { ptr in
            Data(bytes: ptr.baseAddress!, count: ptr.count)
        }
        continuation.yield(data)
    }

    func finish() {
        continuation.finish()
    }
}
