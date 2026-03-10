import Foundation

public struct HttpsRedirectionOptions: Sendable {
    public var httpsPort: Int? = 443
    public var statusCode: Int = 307
    
    public init(httpsPort: Int? = 443, statusCode: Int = 307) {
        self.httpsPort = httpsPort
        self.statusCode = statusCode
    }
}

/// Middleware to redirect HTTP requests to HTTPS.
public struct HttpsRedirectionMiddleware: Middleware {
    private let options: HttpsRedirectionOptions

    public init(options: HttpsRedirectionOptions = HttpsRedirectionOptions()) {
        self.options = options
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        if isHttps(context) {
            try await next(context)
            return
        }

        var host = context.request.header("host") ?? "localhost"
        if let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }

        if let port = options.httpsPort, port != 443 {
            host += ":\(port)"
        }

        let destination = "https://\(host)\(context.request.path)\(context.request.queryString.isEmpty ? "" : "?" + context.request.queryString)"
        
        context.response.setStatus(options.statusCode)
        context.response.setHeader("Location", destination)
    }

    private func isHttps(_ context: HttpContext) -> Bool {
        if let isHttps = context.items["__IsHttps"] as? Bool, isHttps {
            return true
        }
        if context.request.header("x-forwarded-proto") == "https" {
            return true
        }
        return false
    }
}

public struct HstsOptions: Sendable {
    public var maxAge: Int = 31536000
    public var includeSubDomains: Bool = true
    public var preload: Bool = false
    
    public init(maxAge: Int = 31536000, includeSubDomains: Bool = true, preload: Bool = false) {
        self.maxAge = maxAge
        self.includeSubDomains = includeSubDomains
        self.preload = preload
    }
}

/// Middleware to add the Strict-Transport-Security header.
public struct HstsMiddleware: Middleware {
    private let options: HstsOptions

    public init(options: HstsOptions = HstsOptions()) {
        self.options = options
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        if isHttps(context) {
            var headerValue = "max-age=\(options.maxAge)"
            if options.includeSubDomains { headerValue += "; includeSubDomains" }
            if options.preload { headerValue += "; preload" }
            
            context.response.setHeader("Strict-Transport-Security", headerValue)
        }

        try await next(context)
    }

    private func isHttps(_ context: HttpContext) -> Bool {
        if let isHttps = context.items["__IsHttps"] as? Bool, isHttps {
            return true
        }
        if context.request.header("x-forwarded-proto") == "https" {
            return true
        }
        return false
    }
}
