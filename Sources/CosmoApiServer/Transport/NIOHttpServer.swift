import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL

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
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?

    public init(options: ServerOptions) {
        self.options = options
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
        print("Listening on \(scheme)://\(options.host):\(options.port)")
    }

    public func waitForShutdown() async throws {
        try await channel?.closeFuture.get()
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
        return future.flatMap {
            channel.pipeline.configureHTTPServerPipeline(withPipeliningAssistance: true, withErrorHandling: true)
        }.flatMap {
            channel.pipeline.addHandlers([
                RequestAccumulator(),
                Http11ChannelHandler(pipeline: pipeline),
            ])
        }
    }
}
