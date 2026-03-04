import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL
import NIOWebSocket
import Logging

public struct ServerOptions: Sendable {
    public var port: Int
    public var host: String
    public var maxRequestBodySize: Int
    public var certificatePath: String?
    public var certificatePassword: String?
    public var enableHttp2: Bool
    public var numberOfThreads: Int

    public var enableTls: Bool { certificatePath != nil }

    public init(
        port: Int = 8080,
        host: String = "0.0.0.0",
        maxRequestBodySize: Int = 1_073_741_824,
        certificatePath: String? = nil,
        certificatePassword: String? = nil,
        enableHttp2: Bool = false,
        numberOfThreads: Int = System.coreCount
    ) {
        self.port = port
        self.host = host
        self.maxRequestBodySize = maxRequestBodySize
        self.certificatePath = certificatePath
        self.certificatePassword = certificatePassword
        self.enableHttp2 = enableHttp2
        self.numberOfThreads = numberOfThreads
    }
}

/// TCP listener using SwiftNIO. Builds the per-connection NIO channel pipeline
/// and dispatches complete requests through the CosmoApiServer middleware pipeline.
public final class NIOHttpServer: @unchecked Sendable {
    private let options: ServerOptions
    private let wsRoutes: [(path: String, handler: WebSocketHandler)]
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private let logger = Logger(label: "cosmo.server")

    public init(options: ServerOptions, wsRoutes: [(path: String, handler: WebSocketHandler)] = []) {
        self.options = options
        self.wsRoutes = wsRoutes
    }

    public func start(pipeline: @escaping RequestDelegate) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: options.numberOfThreads)
        self.group = group

        let tlsConfig = try buildTLSConfig()

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 512)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                self.initializeChannel(channel, pipeline: pipeline, tlsConfig: tlsConfig)
            }
            .childChannelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)

        channel = try await bootstrap.bind(host: options.host, port: options.port).get()
        let scheme = options.enableTls ? "https" : "http"
        logger.info("Listening on \(scheme)://\(options.host):\(options.port)")
    }

    public func waitForShutdown() async throws {
        // Install POSIX signal handlers so SIGTERM/SIGINT trigger graceful shutdown.
        // We ignore the signals at the process level and route them through DispatchSource.
        let sigStream = AsyncStream<Int32> { continuation in
            let termSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
            termSrc.setEventHandler { continuation.yield(SIGTERM) }
            termSrc.resume()
            let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            intSrc.setEventHandler { continuation.yield(SIGINT) }
            intSrc.resume()
            continuation.onTermination = { _ in termSrc.cancel(); intSrc.cancel() }
        }
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        await withTaskGroup(of: Void.self) { group in
            // Task 1: wait for channel close (e.g. server error or stop() call)
            group.addTask { [weak self] in
                try? await self?.channel?.closeFuture.get()
            }
            // Task 2: wait for a signal, then shut down gracefully
            group.addTask { [weak self] in
                for await sig in sigStream {
                    let name = sig == SIGTERM ? "SIGTERM" : "SIGINT"
                    self?.logger.info("Received \(name) — shutting down gracefully")
                    try? await self?.shutdown()
                    break
                }
            }
            // Whichever finishes first, cancel the rest
            await group.next()
            group.cancelAll()
        }
    }

    public func shutdown() async throws {
        try await channel?.close()
        try await group?.shutdownGracefully()
    }

    // MARK: - Private

    private func buildTLSConfig() throws -> NIOSSLContext? {
        guard options.enableTls, let certPath = options.certificatePath else { return nil }
        var config = TLSConfiguration.makeServerConfiguration(
            certificateChain: try NIOSSLCertificate.fromPEMFile(certPath).map { .certificate($0) },
            privateKey: .file(certPath)
        )
        if options.enableHttp2 {
            config.applicationProtocols = ["h2", "http/1.1"]
        }
        return try NIOSSLContext(configuration: config)
    }

    private func initializeChannel(
        _ channel: Channel,
        pipeline: @escaping RequestDelegate,
        tlsConfig: NIOSSLContext?
    ) -> EventLoopFuture<Void> {
        let future: EventLoopFuture<Void>
        if let tls = tlsConfig {
            let sslHandler = try! NIOSSLServerHandler(context: tls)
            future = channel.pipeline.addHandler(sslHandler)
        } else {
            future = channel.eventLoop.makeSucceededFuture(())
        }

        // Build NIO WebSocket upgraders for each registered WS route
        let upgraders: [NIOWebSocketServerUpgrader] = wsRoutes.map { route in
            NIOWebSocketServerUpgrader(
                shouldUpgrade: { _, head in
                    let path = String(head.uri.split(separator: "?").first ?? Substring(head.uri))
                    return path == route.path
                        ? channel.eventLoop.makeSucceededFuture([:])
                        : channel.eventLoop.makeSucceededFuture(nil)
                },
                upgradePipelineHandler: { wsChannel, head in
                    let ws = WebSocket(channel: wsChannel)
                    let path = String(head.uri.split(separator: "?").first ?? Substring(head.uri))
                    let qs   = head.uri.contains("?") ? String(head.uri.drop(while: { $0 != "?" }).dropFirst()) : ""
                    let req  = HttpRequest(
                        method: HttpMethod(rawValue: head.method.rawValue) ?? .get,
                        path: path, queryString: qs,
                        headers: Dictionary(head.headers.map { ($0.name, $0.value) }, uniquingKeysWith: { $1 }),
                        body: Data()
                    )
                    let handler = route.handler
                    return wsChannel.pipeline.addHandler(WebSocketFrameHandler(ws: ws)).map {
                        Task { await handler(req, ws) }
                    }
                }
            )
        }

        let upgradeConfig: NIOHTTPServerUpgradeSendableConfiguration? = upgraders.isEmpty ? nil : (
            upgraders: upgraders,
            completionHandler: { _ in }
        )

        return future.flatMap {
            channel.pipeline.configureHTTPServerPipeline(
                withPipeliningAssistance: true,
                withServerUpgrade: upgradeConfig,
                withErrorHandling: true
            )
        }.flatMap {
            channel.pipeline.addHandlers([RequestAccumulator(), Http11ChannelHandler(pipeline: pipeline)])
        }
    }
}
