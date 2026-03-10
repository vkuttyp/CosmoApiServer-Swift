import Foundation

// Optimized token bucket logic stored inside the store actor to reduce context switching.
actor RateLimitStore {
    private struct Bucket {
        var tokens: Double
        var lastRefill: Date
    }
    
    private var buckets: [String: Bucket] = [:]
    private let maxTokens: Double
    private let refillPerSecond: Double

    init(maxTokens: Double, refillPerSecond: Double) {
        self.maxTokens = maxTokens
        self.refillPerSecond = refillPerSecond
    }

    func isAllowed(key: String) -> Bool {
        let now = Date()
        var b = buckets[key] ?? Bucket(tokens: maxTokens, lastRefill: now)
        
        let elapsed = now.timeIntervalSince(b.lastRefill)
        b.tokens = min(maxTokens, b.tokens + elapsed * refillPerSecond)
        b.lastRefill = now
        
        if b.tokens >= 1.0 {
            b.tokens -= 1.0
            buckets[key] = b
            return true
        }
        
        buckets[key] = b
        return false
    }
}

public struct RateLimitMiddleware: Middleware {
    private let store: RateLimitStore
    private let limit: Int

    public init(perMinute limit: Int) {
        self.limit = limit
        let perSecond = Double(limit) / 60.0
        self.store = RateLimitStore(maxTokens: Double(limit), refillPerSecond: perSecond)
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        let ip = clientIP(from: context.request)
        let allowed = await store.isAllowed(key: ip)

        guard allowed else {
            context.response.setStatus(429)
            context.response.setHeader("Retry-After", "60")
            context.response.setHeader("X-RateLimit-Limit", String(limit))
            context.response.setHeader("X-RateLimit-Remaining", "0")
            context.response.writeText("429 Too Many Requests")
            return
        }

        try await next(context)
    }

    private func clientIP(from request: HttpRequest) -> String {
        if let xff = request.header("x-forwarded-for") {
            return String(xff.split(separator: ",").first ?? Substring(xff))
                .trimmingCharacters(in: .whitespaces)
        }
        return request.header("x-real-ip") ?? "unknown"
    }
}
