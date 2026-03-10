import Foundation

public struct OpenApiInfo: Sendable, Encodable {
    public var title: String = "Cosmo API"
    public var version: String = "1.0.0"
    public var description: String = "A high-performance Cosmo API"
    
    public init(title: String = "Cosmo API", version: String = "1.0.0", description: String = "A high-performance Cosmo API") {
        self.title = title
        self.version = version
        self.description = description
    }
}

/// Generates a minimal OpenAPI 3.0.0 specification from registered routes.
public enum OpenApiGenerator {
    public static func generate(routes: [HttpMethod: [String]], info: OpenApiInfo) -> [String: AnyEncodable] {
        var paths: [String: [String: AnyEncodable]] = [:]

        for (method, templates) in routes {
            let verb = method.rawValue.lowercased()
            for template in templates {
                // Normalise template for OpenAPI (ensure starts with /)
                let clean = template.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let path = "/\(clean)"
                
                var pathItem = paths[path] ?? [:]
                
                let operation: [String: AnyEncodable] = [
                    "summary": AnyEncodable(path),
                    "responses": AnyEncodable([
                        "200": ["description": "Success"]
                    ])
                ]
                
                pathItem[verb] = AnyEncodable(operation)
                paths[path] = pathItem
            }
        }

        return [
            "openapi": AnyEncodable("3.0.0"),
            "info": AnyEncodable(info),
            "paths": AnyEncodable(paths)
        ]
    }
}

/// Middleware to serve a pre-generated OpenAPI document.
public struct OpenApiMiddleware: Middleware {
    private let path: String
    private let spec: [String: AnyEncodable]

    public init(path: String, spec: [String: AnyEncodable]) {
        self.path = path
        self.spec = spec
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        if context.request.method == .get && context.request.path == path {
            context.response.setStatus(200)
            try context.response.writeJson(spec)
            return
        }

        try await next(context)
    }
}

/// Type-erasing wrapper to allow mixing different types in a dictionary for JSON encoding.
public struct AnyEncodable: Encodable, Sendable {
    private let _encode: @Sendable (Encoder) throws -> Void

    public init<T: Encodable & Sendable>(_ value: T) {
        self._encode = { encoder in try value.encode(to: encoder) }
    }
    
    public init(_ value: [String: AnyEncodable]) {
        self._encode = { encoder in try value.encode(to: encoder) }
    }
    
    public init(_ value: [AnyEncodable]) {
        self._encode = { encoder in try value.encode(to: encoder) }
    }

    public func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
