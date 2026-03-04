import Foundation

public typealias WebSocketHandler = @Sendable (HttpRequest, WebSocket) async -> Void

/// The running web application. Holds the route table, middleware pipeline, and server.
public final class CosmoWebApplication: @unchecked Sendable {
    let routeTable: RouteTable
    let middlewarePipeline: MiddlewarePipeline
    let options: ServerOptions
    private(set) var wsRoutes: [(path: String, handler: WebSocketHandler)] = []
    private(set) var sseRoutes: [(path: String, handler: SseHandler)] = []
    private var server: NIOHttpServer?
    private var _pipeline: RequestDelegate?

    init(options: ServerOptions, middlewarePipeline: MiddlewarePipeline, routeTable: RouteTable) {
        self.options = options
        self.middlewarePipeline = middlewarePipeline
        self.routeTable = routeTable
    }

    // MARK: - Route registration

    @discardableResult
    public func get(_ template: String, handler: @escaping RequestDelegate) -> Self {
        routeTable.add(method: .get, template: template, handler: handler)
        return self
    }

    @discardableResult
    public func post(_ template: String, streaming: Bool = false, handler: @escaping RequestDelegate) -> Self {
        routeTable.add(method: .post, template: template, handler: handler, streaming: streaming)
        return self
    }

    @discardableResult
    public func put(_ template: String, streaming: Bool = false, handler: @escaping RequestDelegate) -> Self {
        routeTable.add(method: .put, template: template, handler: handler, streaming: streaming)
        return self
    }

    @discardableResult
    public func delete(_ template: String, handler: @escaping RequestDelegate) -> Self {
        routeTable.add(method: .delete, template: template, handler: handler)
        return self
    }

    @discardableResult
    public func patch(_ template: String, streaming: Bool = false, handler: @escaping RequestDelegate) -> Self {
        routeTable.add(method: .patch, template: template, handler: handler, streaming: streaming)
        return self
    }

    @discardableResult
    public func head(_ template: String, handler: @escaping RequestDelegate) -> Self {
        routeTable.add(method: .head, template: template, handler: handler)
        return self
    }

    @discardableResult
    public func options(_ template: String, handler: @escaping RequestDelegate) -> Self {
        routeTable.add(method: .options, template: template, handler: handler)
        return self
    }

    /// Register a controller type and its routes.
    @discardableResult
    public func addController<T: Controller>(_ type: T.Type) -> Self {
        T.registerRoutes(on: self)
        return self
    }

    /// Register a WebSocket endpoint.
    ///
    ///     app.webSocket("/ws/chat") { req, ws in
    ///         ws.onText { ws, text in try? await ws.send("Echo: \(text)") }
    ///         ws.onClose { _ in print("closed") }
    ///     }
    @discardableResult
    public func webSocket(_ path: String, handler: @escaping WebSocketHandler) -> Self {
        wsRoutes.append((path: path, handler: handler))
        return self
    }

    /// Register a Server-Sent Events endpoint.
    ///
    ///     app.sse("/events") { req, stream in
    ///         try await stream.send(data: "hello", event: "greeting")
    ///         await stream.close()
    ///     }
    @discardableResult
    public func sse(_ path: String, handler: @escaping SseHandler) -> Self {
        sseRoutes.append((path: path, handler: handler))
        return self
    }

    /// Group routes under a common path prefix.
    ///
    ///     app.group("api/v1") { r in
    ///         r.get("ping") { ctx in try ctx.response.writeJson(["ok": true]) }
    ///     }
    @discardableResult
    public func group(_ prefix: String, configure: (RouteGroup) -> Void) -> Self {
        let g = RouteGroup(prefix: prefix, routeTable: routeTable)
        configure(g)
        return self
    }

    // MARK: - Lifecycle

    public func run() async throws {
        let frozen = routeTable.freeze()
        let pipeline = buildPipeline(frozen: frozen)
        let server = NIOHttpServer(options: options, wsRoutes: wsRoutes, sseRoutes: sseRoutes,
                                   streamingTable: frozen)
        self.server = server
        try await server.start(pipeline: pipeline)
        try await server.waitForShutdown()
    }

    public func start() async throws {
        let frozen = routeTable.freeze()
        let pipeline = buildPipeline(frozen: frozen)
        let server = NIOHttpServer(options: options, wsRoutes: wsRoutes, sseRoutes: sseRoutes,
                                   streamingTable: frozen)
        self.server = server
        try await server.start(pipeline: pipeline)
    }

    /// Create an in-process test client backed by this application's pipeline.
    /// No network port is bound; requests are dispatched directly through the middleware stack.
    ///
    ///     let client = app.testClient()
    ///     let res = try await client.get("/health")
    public func testClient() -> TestClient {
        let frozen = routeTable.freeze()
        return TestClient(pipeline: buildPipeline(frozen: frozen), streamingTable: frozen)
    }

    public func stop() async throws {
        try await server?.shutdown()
    }

    // MARK: - Internal

    private func buildPipeline(frozen: FrozenRouteTable? = nil) -> RequestDelegate {
        if let cached = _pipeline { return cached }
        let routeTable = self.routeTable
        let ft = frozen ?? routeTable.freeze()
        let terminal: RequestDelegate = { ctx in
            ctx.response.setStatus(404)
            ctx.response.writeText("404 Not Found")
        }
        let router = RouterMiddleware(routeTable: ft)
        middlewarePipeline.useInstance(router)
        let p = middlewarePipeline.build(terminal: terminal)
        _pipeline = p
        return p
    }
}
