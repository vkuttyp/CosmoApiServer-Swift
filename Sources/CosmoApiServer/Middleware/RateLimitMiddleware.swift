import Foundation

// MARK: - Token bucket (per-IP)

actor TokenBucket {
    private var tokens: Double
    private let maxTokens: Double
    private let refillPerSecond: Double
    private var lastRefill: Date

    init(maxTokens: Double, refillPerSecond: Double) {
        self.tokens = maxTokens
        self.maxTokens = maxTokens
        self.refillPerSecond = refillPerSecond
        self.lastRefill = Date()
    }

    /// Attempt to consume one token. Returns `true` if allowed, `false` if rate-limited.
    func consume() -> Bool {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        tokens = min(maxTokens, tokens + elapsed * refillPerSecond)
        lastRefill = now
        guard tokens >= 1.0 else { return false }
        tokens -= 1.0
        return true
    }
}

// MARK: - Store

actor RateLimitStore {
    private var buckets: [String: TokenBucket] = [:]
    private let maxTokens: Double
    private let refillPerSecond: Double

    init(maxTokens: Double, refillPerSecond: Double) {
        self.maxTokens = maxTokens
        self.refillPerSecond = refillPerSecond
    }

    func bucket(for key: String) -> TokenBucket {
        if let b = buckets[key] { return b }
        let b = TokenBucket(maxTokens: maxTokens, refillPerSecond: refillPerSecond)
        buckets[key] = b
        return b
    }
}

// MARK: - Middleware

/// Per-IP token-bucket rate limiter.
///
/// Returns `429 Too Many Requests` when the limit is exceeded.
///
///     builder.useRateLimit(perMinute: 60)
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
        let bucket = await store.bucket(for: ip)
        let allowed = await bucket.consume()

        guard allowed else {
            context.response.setStatus(429)
            context.response.headers["Retry-After"] = "60"
            context.response.headers["X-RateLimit-Limit"] = String(limit)
            context.response.headers["X-RateLimit-Remaining"] = "0"
            context.response.writeText("429 Too Many Requests")
            return
        }

        try await next(context)
    }

    private func clientIP(from request: HttpRequest) -> String {
        // Prefer X-Forwarded-For (first value, from proxy), then X-Real-IP, then unknown
        if let xff = request.header("x-forwarded-for") {
            return String(xff.split(separator: ",").first ?? Substring(xff))
                .trimmingCharacters(in: .whitespaces)
        }
        return request.header("x-real-ip") ?? "unknown"
    }
}
