import XCTest
import NIOCore
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
    }
}

final class MiddlewarePipelineTests: XCTestCase {
    func testPipelineOrderIsPreserved() async throws {
        var order: [Int] = []
        let pipeline = MiddlewarePipeline()
        struct M: Middleware {
            let n: Int; let log: @Sendable (Int) -> Void
            func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
                log(n); try await next(context)
            }
        }
        pipeline.useInstance(M(n: 1, log: { val in order.append(val) }))
        pipeline.useInstance(M(n: 2, log: { val in order.append(val) }))
        let built = pipeline.build(terminal: { _ in })
        try await built(HttpContext(request: HttpRequest(method: .get, uri: "/")))
        XCTAssertEqual(order, [1, 2])
    }
}

final class HttpResponseTests: XCTestCase {
    func testWriteTextSetsBody() {
        let r = HttpResponse()
        r.writeText("hello")
        XCTAssertEqual(r.body.withUnsafeReadableBytes { ptr in Data(bytes: ptr.baseAddress!, count: ptr.count) }, Data("hello".utf8))
    }
}

final class TestClientTests: XCTestCase {
    func testGetReturns200() async throws {
        let app = CosmoWebApplicationBuilder().build()
        app.get("/ping") { ctx in ctx.response.writeText("pong") }
        let res = try await app.testClient().get("/ping")
        XCTAssertEqual(res.statusCode, 200)
        XCTAssertEqual(res.text, "pong")
    }
}

// MARK: - OpenAPI Tests
final class OpenApiTests: XCTestCase {
    func testOpenApiSpecGenerated() async throws {
        let builder = CosmoWebApplicationBuilder()
        builder.useOpenApi("/spec.json")
        let app = builder.build()
        app.get("/hello") { _ in }
        let res = try await app.testClient().get("/spec.json")
        XCTAssertEqual(res.statusCode, 200)
        let json = try JSONSerialization.jsonObject(with: res.body) as? [String: Any]
        XCTAssertEqual(json?["openapi"] as? String, "3.0.0")
    }
}

// MARK: - Component Tests
struct CounterComponent: Component {
    var context: HttpContext?; var count: Int = 0
    public init() {}
    var body: HTMLContent {
        Div {
            H1 { "Counter" }
            P { "Count is: \(count)" }
            if let ctx = context { P { "Path: \(ctx.request.path)" } }
        }
    }
}

final class ComponentTests: XCTestCase {
    func testComponentResult() async throws {
        let app = CosmoWebApplicationBuilder().build()
        app.get("/counter") { ctx in
            var c = CounterComponent(); c.count = 7
            try await ComponentResult(c).execute(response: ctx.response)
        }
        let res = try await app.testClient().get("/counter")
        XCTAssertEqual(res.statusCode, 200)
        XCTAssertTrue(res.text.contains("Count is: 7"))
    }
}

// MARK: - Layout Tests
struct MyLayout: LayoutComponent {
    public init() {}; var context: HttpContext?; var content: HTMLContent?
    var body: HTMLContent {
        Div(attributes: ["class": "layout"]) {
            H1 { "Layout Header" }
            if let content = content { content }
        }
    }
}

final class LayoutTests: XCTestCase {
    func testLayoutWrapping() async throws {
        let app = CosmoWebApplicationBuilder().build()
        app.mainLayout = MyLayout()
        app.get("/layout") { ctx in
            var c = CounterComponent(); c.count = 10
            try await ComponentResult(c).execute(response: ctx.response)
        }
        let res = try await app.testClient().get("/layout")
        XCTAssertEqual(res.statusCode, 200)
        XCTAssertTrue(res.text.contains("class=\"layout\""))
        XCTAssertTrue(res.text.contains("Layout Header"))
        XCTAssertTrue(res.text.contains("Count is: 10"))
    }
}
