import Foundation

public final class MiddlewarePipeline: @unchecked Sendable {
    // Each component is a factory: (next) -> next-wrapping-delegate
    private var components: [(@Sendable (@escaping RequestDelegate) -> RequestDelegate)] = []

    public init() {}

    public func use(_ factory: @Sendable @escaping (@escaping RequestDelegate) -> RequestDelegate) {
        components.append(factory)
    }

    public func useInstance(_ middleware: any Middleware) {
        use { next in
            { @Sendable context in
                try await middleware.invoke(context, next: next)
            }
        }
    }

    /// Build the composed pipeline with the given terminal handler.
    public func build(terminal: @escaping RequestDelegate) -> RequestDelegate {
        var pipeline: RequestDelegate = terminal
        for factory in components.reversed() {
            pipeline = factory(pipeline)
        }
        return pipeline
    }
}
