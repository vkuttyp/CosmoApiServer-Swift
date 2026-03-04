import XCTest
@testable import CosmoApiServer

final class RouteTemplateTests: XCTestCase {

    func testLiteralMatch() {
        let t = RouteTemplate("/health")
        XCTAssertNotNil(t.tryMatch("/health"))
        XCTAssertNil(t.tryMatch("/other"))
    }

    func testSingleParam() {
        let t = RouteTemplate("/users/{id}")
        let vals = t.tryMatch("/users/42")
        XCTAssertEqual(vals?["id"], "42")
        XCTAssertNil(t.tryMatch("/users"))
        XCTAssertNil(t.tryMatch("/users/42/extra"))
    }

    func testMultiParam() {
        let t = RouteTemplate("/buckets/{bucket}/objects/{key}")
        let vals = t.tryMatch("/buckets/my-bucket/objects/myfile.txt")
        XCTAssertEqual(vals?["bucket"], "my-bucket")
        XCTAssertEqual(vals?["key"], "myfile.txt")
    }

    func testCaseInsensitiveLiterals() {
        let t = RouteTemplate("/Health/Ping")
        XCTAssertNotNil(t.tryMatch("/health/ping"))
        XCTAssertNotNil(t.tryMatch("/HEALTH/PING"))
    }

    func testWildcard() {
        let t = RouteTemplate("/files/{*rest}")
        let vals = t.tryMatch("/files/a/b/c")
        XCTAssertEqual(vals?["rest"], "a/b/c")
    }

    func testEmptyPathNoMatch() {
        let t = RouteTemplate("/users/{id}")
        XCTAssertNil(t.tryMatch("/"))
    }
}

final class MiddlewarePipelineTests: XCTestCase {

    func testPipelineOrderIsPreserved() async throws {
        var order: [Int] = []
        let pipeline = MiddlewarePipeline()

        struct M: Middleware {
            let n: Int
            let log: (Int) -> Void
            func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
                log(n)
                try await next(context)
            }
        }

        pipeline.useInstance(M(n: 1, log: { order.append($0) }))
        pipeline.useInstance(M(n: 2, log: { order.append($0) }))
        pipeline.useInstance(M(n: 3, log: { order.append($0) }))

        let terminal: RequestDelegate = { _ in }
        let built = pipeline.build(terminal: terminal)
        let ctx = HttpContext(request: HttpRequest(method: .get, path: "/"))
        try await built(ctx)
        XCTAssertEqual(order, [1, 2, 3])
    }

    func testMiddlewareCanShortCircuit() async throws {
        var reached = false
        let pipeline = MiddlewarePipeline()

        struct Stopper: Middleware {
            func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
                context.response.setStatus(401)
                // deliberately does NOT call next
            }
        }
        struct Downstream: Middleware {
            let mark: () -> Void
            func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
                mark()
                try await next(context)
            }
        }

        pipeline.useInstance(Stopper())
        pipeline.useInstance(Downstream(mark: { reached = true }))

        let built = pipeline.build(terminal: { _ in })
        let ctx = HttpContext(request: HttpRequest(method: .get, path: "/"))
        try await built(ctx)
        XCTAssertFalse(reached)
        XCTAssertEqual(ctx.response.statusCode, 401)
    }
}

final class HttpResponseTests: XCTestCase {

    func testWriteTextSetsBody() {
        let r = HttpResponse()
        r.writeText("hello")
        XCTAssertEqual(r.body, Data("hello".utf8))
        XCTAssertEqual(r.headers["Content-Length"], "5")
    }

    func testWriteJsonEncodesValue() throws {
        let r = HttpResponse()
        try r.writeJson(["key": "value"])
        XCTAssertTrue(r.headers["Content-Type"]?.contains("application/json") == true)
        XCTAssertFalse(r.body.isEmpty)
    }

    func testSetStatus() {
        let r = HttpResponse()
        r.setStatus(404)
        XCTAssertEqual(r.statusCode, 404)
        XCTAssertEqual(r.reasonPhrase, "Not Found")
    }
}

final class RouteTableTests: XCTestCase {

    func testMatchByMethod() async throws {
        let table = RouteTable()
        var got = ""
        table.add(method: .get, template: "/ping") { _ in got = "GET" }
        table.add(method: .post, template: "/ping") { _ in got = "POST" }

        if let (h, _) = table.match(method: .get, path: "/ping") {
            let ctx = HttpContext(request: HttpRequest(method: .get, path: "/ping"))
            try await h(ctx)
        }
        XCTAssertEqual(got, "GET")
    }

    func testNoMatchReturnsNil() {
        let table = RouteTable()
        XCTAssertNil(table.match(method: .get, path: "/missing"))
    }
}

// MARK: - Validation Tests

struct CreateUser: Decodable, Validatable {
    let name: String
    let email: String
    let age: Int

    func validate() throws {
        var errors = ValidationErrors()
        errors.check("name",  name,  [.notEmpty, .count(max: 100)])
        errors.check("email", email, [.notEmpty, .email])
        errors.check("age",   age,   [.range(18...120)])
        try errors.throw()
    }
}

final class ValidationTests: XCTestCase {

    func testValidModelPasses() throws {
        var v = ValidationErrors()
        v.check("name", "Alice", [.notEmpty, .count(max: 100)])
        v.check("email", "alice@example.com", [.notEmpty, .email])
        v.check("age", 30, [.range(18...120)])
        XCTAssertTrue(v.isValid)
        XCTAssertNoThrow(try v.throw())
    }

    func testEmptyStringFails() throws {
        var v = ValidationErrors()
        v.check("name", "", [.notEmpty])
        XCTAssertFalse(v.isValid)
        XCTAssertThrowsError(try v.throw())
    }

    func testEmailValidation() {
        var v1 = ValidationErrors()
        v1.check("email", "bad-email", [.email])
        XCTAssertFalse(v1.isValid)

        var v2 = ValidationErrors()
        v2.check("email", "good@example.com", [.email])
        XCTAssertTrue(v2.isValid)
    }

    func testRangeValidation() {
        var v = ValidationErrors()
        v.check("age", 15, [.range(18...120)])
        XCTAssertFalse(v.isValid)
        XCTAssertTrue(v.failures.first?.field == "age")
    }

    func testCountRange() {
        var v1 = ValidationErrors()
        v1.check("code", "AB", [.count(3...6)])
        XCTAssertFalse(v1.isValid)

        var v2 = ValidationErrors()
        v2.check("code", "ABC", [.count(3...6)])
        XCTAssertTrue(v2.isValid)
    }

    func testInValidator() {
        var v = ValidationErrors()
        v.check("role", "superuser", [.in(["admin", "user", "guest"])])
        XCTAssertFalse(v.isValid)
    }

    func testValidateJsonOnRequest() throws {
        let json = #"{"name":"Bob","email":"bob@test.com","age":25}"#
        let req = HttpRequest(method: .post, path: "/users", body: Data(json.utf8))
        let user = try req.validateJson(CreateUser.self)
        XCTAssertEqual(user.name, "Bob")
        XCTAssertEqual(user.email, "bob@test.com")
    }

    func testValidateJsonThrowsOnBadData() throws {
        let json = #"{"name":"","email":"not-an-email","age":5}"#
        let req = HttpRequest(method: .post, path: "/users", body: Data(json.utf8))
        XCTAssertThrowsError(try req.validateJson(CreateUser.self)) { error in
            XCTAssertTrue(error is ValidationError)
            if let ve = error as? ValidationError {
                XCTAssertEqual(ve.failures.count, 3) // name empty, bad email, age < 18
            }
        }
    }

    func testMultipleRulesFired() {
        var v = ValidationErrors()
        v.check("name", "", [.notEmpty, .count(min: 3)])
        XCTAssertEqual(v.failures.count, 2) // both rules fail
    }
}

// MARK: - Environment Tests

final class EnvironmentTests: XCTestCase {

    func testCurrentDefaultsDevelopment() {
        // Without COSMO_ENV or APP_ENV set, should default to .development
        XCTAssertEqual(Environment.current, .development)
        XCTAssertTrue(Environment.current.isDevelopment)
        XCTAssertFalse(Environment.current.isProduction)
    }

    func testGetFallsBackToDefault() {
        let val = Environment.get("COSMO_NONEXISTENT_12345", default: "fallback")
        XCTAssertEqual(val, "fallback")
    }

    func testLoadDotEnvReturnsFalseForMissingFile() {
        let loaded = Environment.loadDotEnv(from: "/tmp/nonexistent_\(UUID().uuidString).env")
        XCTAssertFalse(loaded)
    }

    func testLoadDotEnvParsesFile() throws {
        let path = "/tmp/test_\(UUID().uuidString).env"
        try "COSMO_TEST_KEY=hello_world\n# comment\nQUOTED=\"with spaces\"".write(toFile: path, atomically: true, encoding: .utf8)
        Environment.loadDotEnv(from: path)
        // Only check if not already set by process env
        if ProcessInfo.processInfo.environment["COSMO_TEST_KEY"] == nil {
            XCTAssertEqual(Environment.get("COSMO_TEST_KEY"), "hello_world")
        }
        try FileManager.default.removeItem(atPath: path)
    }
}

// MARK: - Session Tests

final class SessionTests: XCTestCase {

    func testSessionSubscript() {
        let session = Session(id: "test-id")
        session["userId"] = "42"
        XCTAssertEqual(session["userId"], "42")
    }

    func testSessionClear() {
        let session = Session(id: "test-id")
        session["a"] = "1"
        session["b"] = "2"
        XCTAssertFalse(session.isEmpty)
        session.clear()
        XCTAssertTrue(session.isEmpty)
    }

    func testSessionMiddlewareSetsSessionOnContext() async throws {
        let middleware = SessionMiddleware()
        var reached = false
        let next: RequestDelegate = { ctx in
            XCTAssertNotNil(ctx.session)
            reached = true
        }
        let ctx = HttpContext(request: HttpRequest(method: .get, path: "/"))
        try await middleware.invoke(ctx, next: next)
        XCTAssertTrue(reached)
        // New session → Set-Cookie should be present
        XCTAssertNotNil(ctx.response.headers["Set-Cookie"])
    }

    func testSessionMiddlewareReusesExistingSession() async throws {
        // First request — creates session
        let middleware = SessionMiddleware()
        var sessionId: String?
        let first: RequestDelegate = { ctx in
            ctx.session?["key"] = "value"
            sessionId = ctx.session?.id
        }
        let ctx1 = HttpContext(request: HttpRequest(method: .get, path: "/"))
        try await middleware.invoke(ctx1, next: first)

        // Second request with the same session cookie — no new Set-Cookie
        let sid = sessionId!
        let headers = ["Cookie": "cosmo_sid=\(sid)"]
        let second: RequestDelegate = { ctx in
            XCTAssertEqual(ctx.session?.id, sid)
        }
        let ctx2 = HttpContext(request: HttpRequest(method: .get, path: "/", headers: headers))
        try await middleware.invoke(ctx2, next: second)
        // Existing session — Set-Cookie should NOT be set
        XCTAssertNil(ctx2.response.headers["Set-Cookie"])
    }
}

// MARK: - RateLimit Tests

final class RateLimitTests: XCTestCase {

    func testAllowsRequestsUnderLimit() async throws {
        let middleware = RateLimitMiddleware(perMinute: 100)
        let ctx = HttpContext(request: HttpRequest(method: .get, path: "/"))
        try await middleware.invoke(ctx) { _ in }
        XCTAssertEqual(ctx.response.statusCode, 200) // not rate limited
    }

    func testRateLimitsAfterBurst() async throws {
        // 1 per minute → after first, second should be rate limited (bucket empty)
        let middleware = RateLimitMiddleware(perMinute: 1)
        var limited = false
        for _ in 0..<5 {
            let ctx = HttpContext(request: HttpRequest(
                method: .get, path: "/",
                headers: ["X-Real-IP": "1.2.3.4"]
            ))
            try await middleware.invoke(ctx) { _ in }
            if ctx.response.statusCode == 429 { limited = true }
        }
        XCTAssertTrue(limited)
    }
}

// MARK: - TestClient Tests

final class TestClientTests: XCTestCase {

    private func makeApp() -> CosmoWebApplication {
        let builder = CosmoWebApplicationBuilder()
        builder.useErrorHandling()
        let app = builder.build()
        app.get("/ping") { ctx in ctx.response.writeText("pong") }
        app.post("/echo") { ctx in
            ctx.response.body = ctx.request.body
            ctx.response.headers["Content-Type"] = "text/plain"
        }
        app.get("/json") { ctx in
            try ctx.response.writeJson(["key": "value"])
        }
        app.get("/fail") { _ in throw Abort.notFound("not here") }
        return app
    }

    func testGetReturns200() async throws {
        let client = makeApp().testClient()
        let res = try await client.get("/ping")
        XCTAssertEqual(res.statusCode, 200)
        XCTAssertEqual(res.text, "pong")
    }

    func testPostWithBody() async throws {
        let client = makeApp().testClient()
        let body = Data("hello".utf8)
        let res = try await client.post("/echo", body: body)
        XCTAssertEqual(res.statusCode, 200)
        XCTAssertEqual(res.text, "hello")
    }

    func testJsonResponse() async throws {
        let client = makeApp().testClient()
        let res = try await client.get("/json")
        let decoded = try res.json([String: String].self)
        XCTAssertEqual(decoded["key"], "value")
    }

    func testMissingRouteReturns404() async throws {
        let client = makeApp().testClient()
        let res = try await client.get("/nonexistent")
        XCTAssertEqual(res.statusCode, 404)
    }

    func testErrorMiddlewareCatchesAbort() async throws {
        let client = makeApp().testClient()
        let res = try await client.get("/fail")
        XCTAssertEqual(res.statusCode, 404)
        XCTAssertTrue(res.text.contains("not here"))
    }

    func testQueryStringParsed() async throws {
        let builder = CosmoWebApplicationBuilder()
        let app = builder.build()
        app.get("/search") { ctx in
            let q = ctx.request.query["q"] ?? "none"
            ctx.response.writeText(q)
        }
        let client = app.testClient()
        let res = try await client.get("/search?q=swift")
        XCTAssertEqual(res.text, "swift")
    }
}

// MARK: - Streaming body tests

final class StreamingBodyTests: XCTestCase {
    func testStreamingRouteReceivesChunks() async throws {
        let builder = CosmoWebApplicationBuilder()
        let app = builder.build()
        var received = Data()
        app.put("/upload", streaming: true) { ctx in
            if let stream = ctx.request.bodyStream {
                for await chunk in stream { received.append(chunk) }
            }
            ctx.response.writeText("ok")
        }
        let client = app.testClient()
        let body = Data("hello streaming world".utf8)
        let res = try await client.put("/upload", body: body)
        XCTAssertEqual(res.statusCode, 200)
        XCTAssertEqual(res.text, "ok")
        XCTAssertEqual(received, body)
    }

    func testNonStreamingRouteBodyUnchanged() async throws {
        let builder = CosmoWebApplicationBuilder()
        let app = builder.build()
        app.post("/echo") { ctx in
            ctx.response.setStatus(200)
            ctx.response.write(ctx.request.body)
        }
        let client = app.testClient()
        let body = Data("no streaming here".utf8)
        let res = try await client.post("/echo", body: body)
        XCTAssertEqual(String(data: res.body, encoding: .utf8), "no streaming here")
        // Non-streaming routes receive body in req.body (bodyStream is nil)
        XCTAssertEqual(res.statusCode, 200)
    }
}

final class MultipartParserTests: XCTestCase {

    // Build a minimal multipart/form-data body.
    private func makeBody(boundary: String, parts: [(headers: String, body: String)]) -> Data {
        var s = ""
        for part in parts {
            s += "--\(boundary)\r\n"
            s += part.headers + "\r\n"
            s += part.body + "\r\n"
        }
        s += "--\(boundary)--\r\n"
        return Data(s.utf8)
    }

    func testPlainTextField() throws {
        let boundary = "TestBoundary123"
        let body = makeBody(boundary: boundary, parts: [
            (headers: "Content-Disposition: form-data; name=\"username\"\r\n",
             body:    "alice"),
        ])
        let form = try MultipartParser.parse(body: body,
                                             contentType: "multipart/form-data; boundary=\(boundary)")
        XCTAssertEqual(form.fields["username"], "alice")
        XCTAssertTrue(form.files.isEmpty)
    }

    func testMultipleTextFields() throws {
        let boundary = "Bound42"
        let body = makeBody(boundary: boundary, parts: [
            (headers: "Content-Disposition: form-data; name=\"first\"\r\n",  body: "John"),
            (headers: "Content-Disposition: form-data; name=\"last\"\r\n",   body: "Doe"),
            (headers: "Content-Disposition: form-data; name=\"age\"\r\n",    body: "30"),
        ])
        let form = try MultipartParser.parse(body: body,
                                             contentType: "multipart/form-data; boundary=\(boundary)")
        XCTAssertEqual(form.fields["first"], "John")
        XCTAssertEqual(form.fields["last"],  "Doe")
        XCTAssertEqual(form.fields["age"],   "30")
    }

    func testFileUpload() throws {
        let boundary = "FileBoundary"
        let fileContent = "Hello, file!"
        var s = ""
        s += "--\(boundary)\r\n"
        s += "Content-Disposition: form-data; name=\"avatar\"; filename=\"photo.txt\"\r\n"
        s += "Content-Type: text/plain\r\n"
        s += "\r\n"
        s += fileContent + "\r\n"
        s += "--\(boundary)--\r\n"

        let form = try MultipartParser.parse(body: Data(s.utf8),
                                             contentType: "multipart/form-data; boundary=\(boundary)")
        XCTAssertTrue(form.fields.isEmpty)
        let file = try XCTUnwrap(form.files["avatar"])
        XCTAssertEqual(file.filename, "photo.txt")
        XCTAssertEqual(file.contentType, "text/plain")
        XCTAssertEqual(String(data: file.data, encoding: .utf8), fileContent)
    }

    func testMixedFieldsAndFile() throws {
        let boundary = "MixedBound"
        let fileBytes = Data([0x89, 0x50, 0x4E, 0x47]) // PNG magic bytes
        var body = Data()
        body += Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nMy Photo\r\n".utf8)
        body += Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"img.png\"\r\nContent-Type: image/png\r\n\r\n".utf8)
        body += fileBytes
        body += Data("\r\n--\(boundary)--\r\n".utf8)

        let form = try MultipartParser.parse(body: body,
                                             contentType: "multipart/form-data; boundary=\(boundary)")
        XCTAssertEqual(form.fields["title"], "My Photo")
        let file = try XCTUnwrap(form.files["image"])
        XCTAssertEqual(file.filename, "image/png" == file.contentType ? "img.png" : "img.png")
        XCTAssertEqual(file.contentType, "image/png")
        XCTAssertEqual(file.data, fileBytes)
    }

    func testBoundaryWithQuotes() throws {
        let boundary = "quotedBound"
        let body = makeBody(boundary: boundary, parts: [
            (headers: "Content-Disposition: form-data; name=\"x\"\r\n", body: "y"),
        ])
        // boundary value wrapped in quotes in Content-Type
        let form = try MultipartParser.parse(body: body,
                                             contentType: "multipart/form-data; boundary=\"\(boundary)\"")
        XCTAssertEqual(form.fields["x"], "y")
    }

    func testNotMultipartThrows() {
        XCTAssertThrowsError(
            try MultipartParser.parse(body: Data(), contentType: "application/json")
        )
    }

    func testMissingBoundaryThrows() {
        XCTAssertThrowsError(
            try MultipartParser.parse(body: Data(), contentType: "multipart/form-data")
        )
    }

    func testReadMultipartViaRequest() throws {
        let boundary = "ReqBound"
        let body = makeBody(boundary: boundary, parts: [
            (headers: "Content-Disposition: form-data; name=\"msg\"\r\n", body: "hello"),
        ])
        let request = HttpRequest(
            method: .post, path: "/upload",
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
            body: body
        )
        let form = try request.readMultipart()
        XCTAssertEqual(form.fields["msg"], "hello")
    }

    func testEndToEndUploadRoute() async throws {
        let builder = CosmoWebApplicationBuilder()
        let app = builder.build()

        app.post("/upload") { ctx in
            let form = try ctx.request.readMultipart()
            struct UploadResult: Encodable {
                let name: String
                let size: Int
            }
            let name = form.fields["name"] ?? "unknown"
            let size = form.files["file"]?.data.count ?? 0
            try ctx.response.writeJson(UploadResult(name: name, size: size))
        }

        let boundary = "E2EBound"
        var body = Data()
        body += Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\nAlice\r\n".utf8)
        body += Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"data.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
        body += Data(repeating: 0xFF, count: 512)
        body += Data("\r\n--\(boundary)--\r\n".utf8)

        let client = app.testClient()
        let res = try await client.post(
            "/upload", body: body,
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"]
        )
        XCTAssertEqual(res.statusCode, 200)
        struct UploadResult: Decodable { let name: String; let size: Int }
        let json = try res.json(UploadResult.self)
        XCTAssertEqual(json.size, 512)
    }
}
