# CosmoApiServer-Swift

A high-performance HTTP/1.1 server framework for Swift, built on SwiftNIO. The Swift counterpart of [CosmoApiServer](https://github.com/vkuttyp/CosmoApiServer).

## Features

- **SwiftNIO transport** — non-blocking, event-driven I/O
- **Middleware pipeline** — composable, ordered middleware chain
- **Attribute-style routing** — `{id}` path parameters, wildcard `{*rest}` segments
- **Protocol-based controllers** — `Controller` protocol for structured route registration
- **JWT authentication** — Bearer token middleware via JWTKit
- **CORS support** — configurable origins, methods, headers
- **TLS/HTTPS** — via swift-nio-ssl
- **Linux + macOS** — runs on both platforms

## Quick Start

```swift
import CosmoApiServer

let builder = CosmoWebApplicationBuilder()
    .listenOn(port: 8080)
    .useLogging()
    .useCors()

let app = builder.build()

app.get("/ping") { ctx in
    ctx.response.writeText("pong")
}

app.post("/echo") { ctx in
    try ctx.response.writeJson(["body": String(data: ctx.request.body, encoding: .utf8) ?? ""])
}

try await app.run()
```

## Controllers

```swift
class UserController: ControllerBase, Controller {
    static func registerRoutes(on app: CosmoWebApplication) {
        app.get("/users/{id}", handler: { ctx in
            let id = ctx.request.routeValues["id"] ?? ""
            try ctx.response.writeJson(["id": id])
        })
    }
}

app.addController(UserController.self)
```

## JWT Authentication

```swift
let builder = CosmoWebApplicationBuilder()
    .useJwtAuthentication(options: JwtOptions(
        secret: "your-secret-key-32-chars-minimum",
        issuer: "MyApp",
        expiryMinutes: 60
    ))
```

## Requirements

- Swift 5.9+
- macOS 14+ / Linux

## License

MIT
