import Foundation
import CosmoApiServer

// MARK: - Benchmark Server
// HTTP/1.1 on port 19000, h2c (cleartext HTTP/2) on port 19002
// Scenarios:
//   GET  /ping           → "pong"                 (raw throughput)
//   GET  /json           → {"status":"ok",...}    (JSON serialization)
//   POST /echo           → body echoed back       (request parsing + body write)
//   GET  /route/{id}     → route param extraction (routing performance)
//   GET  /middleware     → full stack traversal   (all middleware)

func makeApp(port: Int, http2: Bool) -> CosmoWebApplication {
    let builder = CosmoWebApplicationBuilder()
    builder.listenOn(port: port)
    builder.useErrorHandling()
    if http2 { builder.useHttp2() }
    builder.useThreads(ProcessInfo.processInfo.activeProcessorCount)
    return builder.build()
}

// Shared ISO 8601 formatter (cached — ISO8601DateFormatter() is expensive)
let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

struct StatusResponse: Encodable {
    let status: String; let timestamp: String; let server: String
}

func registerRoutes(_ app: CosmoWebApplication, label: String) {
    app.get("/ping") { ctx in
        ctx.response.writeText("pong")
    }
    app.get("/json") { ctx in
        try ctx.response.writeJson(StatusResponse(
            status: "ok",
            timestamp: isoFormatter.string(from: Date()),
            server: label
        ))
    }
    app.post("/echo") { ctx in
        ctx.response.body = ctx.request.body
        ctx.response.headers["Content-Type"] = ctx.request.header("content-type") ?? "application/octet-stream"
    }
    app.get("/route/{id}") { ctx in
        let id = ctx.request.routeValues["id"] ?? "unknown"
        try ctx.response.writeJson(["id": id])
    }
    app.get("/middleware") { ctx in
        try ctx.response.writeJson(["path": ctx.request.path, "method": ctx.request.method.rawValue])
    }
}

let h1App  = makeApp(port: 19000, http2: false)
let h2cApp = makeApp(port: 19002, http2: true)

registerRoutes(h1App,  label: "CosmoApiServer-Swift/h1")
registerRoutes(h2cApp, label: "CosmoApiServer-Swift/h2c")

print("=== CosmoApiServer-Swift Benchmark ===")
print("HTTP/1.1  → http://127.0.0.1:19000")
print("h2c       → http://127.0.0.1:19002")
print("Threads: \(ProcessInfo.processInfo.activeProcessorCount)")

// Run both servers concurrently
try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask { try await h1App.run() }
    group.addTask { try await h2cApp.run() }
    try await group.next()
}
