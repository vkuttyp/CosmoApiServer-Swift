import Foundation
import NIOCore
import NIOConcurrencyHelpers

/// A lightweight, thread-safe pool for HttpContext objects to reduce allocation overhead.
public final class HttpContextPool: @unchecked Sendable {
    public static let shared = HttpContextPool()
    
    private let lock = NIOLock()
    private var pool: [HttpContext] = []
    private let maxPoolSize = 1024
    
    private init() {
        pool.reserveCapacity(maxPoolSize)
    }
    
    public func rent(request: HttpRequest, application: CosmoWebApplication? = nil) -> HttpContext {
        lock.lock()
        if !pool.isEmpty {
            let context = pool.removeLast()
            lock.unlock()
            context.request = request
            context.application = application
            return context
        }
        lock.unlock()
        let context = HttpContext(request: request)
        context.application = application
        return context
    }
    
    public func `return`(_ context: HttpContext) {
        context.reset()
        context.application = nil
        lock.lock()
        if pool.count < maxPoolSize {
            pool.append(context)
        }
        lock.unlock()
    }
}
