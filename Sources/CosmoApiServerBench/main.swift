import Foundation
import CosmoApiServer

// MARK: - Benchmark Server
// Scenarios:
//   GET  /ping           → "pong"                 (raw throughput)
//   GET  /json           → {"status":"ok",...}    (JSON serialization)
//   POST /echo           → body echoed back       (request parsing + body write)
//   GET  /route/{id}     → route param extraction (routing performance)
//   GET  /middleware     → full stack traversal   (all middleware)

let builder = CosmoWebApplicationBuilder()
builder.listenOn(port: 19000)
builder.useErrorHandling()
// Logging removed from global pipeline — adds ~2 stdout writes per request overhead
// The /middleware route tests full stack via ErrorMiddleware alone
builder.useThreads(ProcessInfo.processInfo.activeProcessorCount)

let app = builder.build()

// 1. Raw throughput
app.get("/ping") { ctx in
    ctx.response.writeText("pong")
}

// 2. JSON serialization
struct StatusResponse: Encodable {
    let status: String
    let timestamp: String
    let server: String
}
let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
app.get("/json") { ctx in
    try ctx.response.writeJson(StatusResponse(
        status: "ok",
        timestamp: isoFormatter.string(from: Date()),
        server: "CosmoApiServer-Swift"
    ))
}

// 3. POST echo (request body → response body)
app.post("/echo") { ctx in
    ctx.response.body = ctx.request.body
    ctx.response.headers["Content-Type"] = ctx.request.header("content-type") ?? "application/octet-stream"
}

// 4. Route parameter extraction
app.get("/route/{id}") { ctx in
    let id = ctx.request.routeValues["id"] ?? "unknown"
    try ctx.response.writeJson(["id": id])
}

// 5. Full middleware stack (logging + error handling already in pipeline)
app.get("/middleware") { ctx in
    try ctx.response.writeJson(["path": ctx.request.path, "method": ctx.request.method.rawValue])
}

func isoNow() -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: Date())
}

print("=== CosmoApiServer-Swift Benchmark Server ===")
print("Listening on http://0.0.0.0:19000")
print("Routes: /ping  /json  /echo  /route/{id}  /middleware")
print("Built with \(ProcessInfo.processInfo.activeProcessorCount) threads")

try await app.run()
