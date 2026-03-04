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
