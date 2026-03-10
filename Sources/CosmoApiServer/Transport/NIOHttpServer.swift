import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOTLS
import NIOHTTP2
import NIOSSL
import NIOWebSocket
import NIOHTTPCompression
import Logging

public struct ServerOptions: Sendable {
    public var port: Int
    public var host: String
    public var maxRequestBodySize: Int
    public var certificatePath: String?
    public var certificatePassword: String?
    public var enableHttp2: Bool
    public var numberOfThreads: Int

    public var enableCompression: Bool
    public var enableTls: Bool { certificatePath != nil }

    public init(
        port: Int = 8080,
        host: String = "0.0.0.0",
        maxRequestBodySize: Int = 1_073_741_824,
        certificatePath: String? = nil,
        certificatePassword: String? = nil,
        enableHttp2: Bool = false,
        numberOfThreads: Int = System.coreCount,
        enableCompression: Bool = false
    ) {
        self.port = port
        self.host = host
        self.maxRequestBodySize = maxRequestBodySize
        self.certificatePath = certificatePath
        self.certificatePassword = certificatePassword
        self.enableHttp2 = enableHttp2
        self.numberOfThreads = numberOfThreads
        self.enableCompression = enableCompression
    }
}

public final class NIOHttpServer: @unchecked Sendable {
    private let options: ServerOptions
    private let wsRoutes: [(path: String, handler: WebSocketHandler)]
    private let sseRoutes: [(path: String, handler: SseHandler)]
    private let streamingTable: FrozenRouteTable?
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private let logger = Logger(label: "cosmo.server")
    private weak var application: CosmoWebApplication?

    public init(
        options: ServerOptions,
        wsRoutes: [(path: String, handler: WebSocketHandler)] = [],
        sseRoutes: [(path: String, handler: SseHandler)] = [],
        streamingTable: FrozenRouteTable? = nil,
        application: CosmoWebApplication? = nil
    ) {
        self.options = options
        self.wsRoutes = wsRoutes
        self.sseRoutes = sseRoutes
        self.streamingTable = streamingTable
        self.application = application
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
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in try? await self?.channel?.closeFuture.get() }
#if !os(Windows)
            let sigStream = AsyncStream<Int32> { continuation in
                let termSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
                termSrc.setEventHandler { continuation.yield(SIGTERM) }
                termSrc.resume()
                let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
                intSrc.setEventHandler { continuation.yield(SIGINT) }
                intSrc.resume()
                continuation.onTermination = { _ in termSrc.cancel(); intSrc.cancel() }
            }
            signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
            group.addTask { [weak self] in
                for await sig in sigStream {
                    let name = sig == SIGTERM ? "SIGTERM" : "SIGINT"
                    self?.logger.info("Received \(name) — shutting down gracefully")
                    try? await self?.shutdown()
                    break
                }
            }
#endif
            await group.next()
            group.cancelAll()
        }
    }

    public func shutdown() async throws {
        try await channel?.close()
        try await group?.shutdownGracefully()
    }

    private func buildTLSConfig() throws -> NIOSSLContext? {
        guard options.enableTls, let certPath = options.certificatePath else { return nil }
        var config = TLSConfiguration.makeServerConfiguration(
            certificateChain: try NIOSSLCertificate.fromPEMFile(certPath).map { .certificate($0) },
            privateKey: .file(certPath)
        )
        if options.enableHttp2 { config.applicationProtocols = ["h2", "http/1.1"] }
        return try NIOSSLContext(configuration: config)
    }

    private func initializeChannel(_ channel: Channel, pipeline: @escaping RequestDelegate, tlsConfig: NIOSSLContext?) -> EventLoopFuture<Void> {
        if let tls = tlsConfig {
            let sslHandler = try! NIOSSLServerHandler(context: tls)
            if options.enableHttp2 {
                return channel.pipeline.addHandler(sslHandler).flatMap {
                    channel.configureHTTP2SecureUpgrade(
                        h2ChannelConfigurator: { [self] ch in self.configureH2Pipeline(ch, appPipeline: pipeline) },
                        http1ChannelConfigurator: { [self] ch in self.configureHttp1Pipeline(ch, appPipeline: pipeline) }
                    )
                }
            } else {
                return channel.pipeline.addHandler(sslHandler).flatMap {
                    self.configureHttp1Pipeline(channel, appPipeline: pipeline)
                }
            }
        } else if options.enableHttp2 {
            return configureH2Pipeline(channel, appPipeline: pipeline)
        } else {
            return configureHttp1Pipeline(channel, appPipeline: pipeline)
        }
    }

    private func configureH2Pipeline(_ channel: Channel, appPipeline: @escaping RequestDelegate) -> EventLoopFuture<Void> {
        channel.configureHTTP2Pipeline(mode: .server, inboundStreamInitializer: { [self] streamChannel in
            streamChannel.pipeline.addHandlers([
                HTTP2FramePayloadToHTTP1ServerCodec(),
                RequestAccumulator(streamingTable: self.streamingTable),
                Http11ChannelHandler(pipeline: appPipeline, sseRoutes: self.sseRoutes, application: self.application)
            ])
        }).map { _ in }
    }

    private func configureHttp1Pipeline(_ channel: Channel, appPipeline: @escaping RequestDelegate) -> EventLoopFuture<Void> {
        let upgraders: [NIOWebSocketServerUpgrader] = wsRoutes.map { route in
            NIOWebSocketServerUpgrader(
                shouldUpgrade: { _, head in
                    let path = String(head.uri.split(separator: "?").first ?? Substring(head.uri))
                    return path == route.path ? channel.eventLoop.makeSucceededFuture([:]) : channel.eventLoop.makeSucceededFuture(nil)
                },
                upgradePipelineHandler: { wsChannel, head in
                    let ws = WebSocket(channel: wsChannel)
                    let req = HttpRequest(method: HttpMethod(rawValue: head.method.rawValue) ?? .get,
                                          uri: head.uri, headers: head.headers, body: ByteBuffer())
                    let handler = route.handler
                    return wsChannel.pipeline.addHandler(WebSocketFrameHandler(ws: ws)).map {
                        Task { await handler(req, ws) }
                    }
                }
            )
        }
        let upgradeConfig: NIOHTTPServerUpgradeSendableConfiguration? = upgraders.isEmpty ? nil : (upgraders: upgraders, completionHandler: { _ in })
        return channel.eventLoop.makeSucceededFuture(()).flatMap {
            channel.pipeline.configureHTTPServerPipeline(withPipeliningAssistance: true, withServerUpgrade: upgradeConfig, withErrorHandling: true)
        }.flatMap {
            self.options.enableCompression ? channel.pipeline.addHandler(HTTPResponseCompressor()) : channel.eventLoop.makeSucceededFuture(())
        }.flatMap {
            channel.pipeline.addHandlers([
                RequestAccumulator(streamingTable: self.streamingTable),
                Http11ChannelHandler(pipeline: appPipeline, sseRoutes: self.sseRoutes, application: self.application)
            ])
        }
    }
}
