import Foundation
import CosmoApiServer

struct BenchItem: Sendable {
    let id: Int; let name: String; let value: Double; let date: String
}

struct BenchComponent: Component {
    var context: HttpContext?; var items: [BenchItem] = []
    public init() {}
    var body: HTMLContent {
        #html {
            Table {
                Thead { Tr { Th { "ID" }; Th { "Name" }; Th { "Value" }; Th { "Date" } } }
                Tbody {
                    for item in items {
                        Tr { Td { "\(item.id)" }; Td { item.name }; Td { "\(item.value)" }; Td { item.date } }
                    }
                }
            }
        }
    }
}

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
}()

let benchItems: [BenchItem] = (1...100).map { i in
    BenchItem(id: i, name: "Item \(i)", value: Double(i) * 1.23, date: isoFormatter.string(from: Date().addingTimeInterval(TimeInterval(i * 86400))))
}

let builder = CosmoWebApplicationBuilder()
builder.listenOn(port: 19000)
builder.useErrorHandling()
let app = builder.build()

app.get("/ping") { ctx in ctx.response.writeText("pong") }
app.get("/json") { ctx in
    try ctx.response.writeJson(["status": "ok", "server": "Swift"])
}
app.get("/bench") { ctx in
    var comp = BenchComponent(); comp.items = benchItems; ctx.response.writeHTML(comp)
}

print("=== Swift Bench Ready on port 19000 ===")
try await app.run()
