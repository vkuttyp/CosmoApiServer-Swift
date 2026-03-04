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
