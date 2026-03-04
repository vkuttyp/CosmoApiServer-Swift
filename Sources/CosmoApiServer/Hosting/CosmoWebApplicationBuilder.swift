import Foundation

/// Fluent builder for CosmoWebApplication.
public final class CosmoWebApplicationBuilder: @unchecked Sendable {
    private var options: ServerOptions
    private let middlewarePipeline: MiddlewarePipeline
    private let routeTable: RouteTable

    public init() {
        self.options = ServerOptions()
        self.middlewarePipeline = MiddlewarePipeline()
        self.routeTable = RouteTable()
    }

    // MARK: - Server configuration

    @discardableResult
    public func listenOn(port: Int, host: String = "0.0.0.0") -> Self {
        options.port = port
        options.host = host
        return self
    }

    @discardableResult
    public func useHttps(certificatePath: String, password: String? = nil) -> Self {
        options.certificatePath = certificatePath
        options.certificatePassword = password
        return self
    }

    @discardableResult
    public func useHttp2() -> Self {
        options.enableHttp2 = true
        return self
    }

    @discardableResult
    public func useThreads(_ count: Int) -> Self {
        options.numberOfThreads = count
        return self
    }

    // MARK: - Middleware

    @discardableResult
    public func useErrorHandling() -> Self {
        middlewarePipeline.useInstance(ErrorMiddleware())
        return self
    }

    @discardableResult
    public func useLogging() -> Self {
        middlewarePipeline.useInstance(LoggingMiddleware())
        return self
    }

    @discardableResult
    public func useCors(_ corsOptions: CorsOptions = CorsOptions()) -> Self {
        middlewarePipeline.useInstance(CorsMiddleware(options: corsOptions))
        return self
    }

    @discardableResult
    public func useMiddleware(_ middleware: any Middleware) -> Self {
        middlewarePipeline.useInstance(middleware)
        return self
    }

    @discardableResult
    public func useStaticFiles(at directory: String, prefix: String = "") -> Self {
        middlewarePipeline.useInstance(StaticFileMiddleware(directory: directory, prefix: prefix))
        return self
    }

    @discardableResult
    public func useSessions(cookieName: String = "cosmo_sid", secure: Bool = false) -> Self {
        middlewarePipeline.useInstance(SessionMiddleware(cookieName: cookieName, secure: secure))
        return self
    }

    @discardableResult
    public func useRateLimit(perMinute limit: Int) -> Self {
        middlewarePipeline.useInstance(RateLimitMiddleware(perMinute: limit))
        return self
    }

    @discardableResult
    public func useCompression() -> Self {
        options.enableCompression = true
        return self
    }

    @discardableResult
    public func useJwtAuthentication(options jwtOptions: JwtOptions) -> Self {
        let service = JwtService(options: jwtOptions)
        middlewarePipeline.useInstance(JwtMiddleware(service: service))
        return self
    }

    // MARK: - Build

    public func build() -> CosmoWebApplication {
        CosmoWebApplication(
            options: options,
            middlewarePipeline: middlewarePipeline,
            routeTable: routeTable
        )
    }
}
