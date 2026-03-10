import XCTest
import CosmoApiServer
import NIOCore

final class HTMLMacroTests: XCTestCase {
    func testBasicExpansion() {
        let content = #html {
            Div {
                H1 { "Hello" }
                P { "World" }
            }
        }
        
        var buffer = ByteBufferAllocator().buffer(capacity: 1024)
        content.write(to: &buffer)
        let result = buffer.readString(length: buffer.readableBytes)
        XCTAssertEqual(result, "<div><h1>Hello</h1><p>World</p></div>")
    }
    
    func testAttributes() {
        let content = #html {
            Div(attributes: ["class": "test"]) {
                "Text"
            }
        }
        
        var buffer = ByteBufferAllocator().buffer(capacity: 1024)
        content.write(to: &buffer)
        let result = buffer.readString(length: buffer.readableBytes)
        XCTAssertEqual(result, "<div class=\"test\">Text</div>")
    }

    func testForLoop() {
        let items = ["A", "B"]
        let content = #html {
            Ul {
                for item in items {
                    Li { item }
                }
            }
        }
        
        var buffer = ByteBufferAllocator().buffer(capacity: 1024)
        content.write(to: &buffer)
        let result = buffer.readString(length: buffer.readableBytes)
        XCTAssertEqual(result, "<ul><li>A</li><li>B</li></ul>")
    }

    func testIfElse() {
        let show = true
        let content = #html {
            Div {
                if show {
                    P { "Shown" }
                } else {
                    P { "Hidden" }
                }
            }
        }
        
        var buffer = ByteBufferAllocator().buffer(capacity: 1024)
        content.write(to: &buffer)
        let result = buffer.readString(length: buffer.readableBytes)
        XCTAssertEqual(result, "<div><p>Shown</p></div>")
    }

    func testElseIf() {
        let value = 2
        let content = #html {
            Div {
                if value == 1 {
                    P { "One" }
                } else if value == 2 {
                    P { "Two" }
                } else {
                    P { "Other" }
                }
            }
        }
        
        var buffer = ByteBufferAllocator().buffer(capacity: 1024)
        content.write(to: &buffer)
        let result = buffer.readString(length: buffer.readableBytes)
        XCTAssertEqual(result, "<div><p>Two</p></div>")
    }

    func testVariables() {
        let name = "Swift"
        let content = #html {
            Div {
                "Hello, "
                name
                "!"
            }
        }
        
        var buffer = ByteBufferAllocator().buffer(capacity: 1024)
        content.write(to: &buffer)
        let result = buffer.readString(length: buffer.readableBytes)
        XCTAssertEqual(result, "<div>Hello, Swift!</div>")
    }
}
