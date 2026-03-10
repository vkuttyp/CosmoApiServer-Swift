import Foundation
import NIOCore

public protocol Component: Sendable {
    init()
    var context: HttpContext? { get set }
    @HTMLBuilder var body: HTMLContent { get }
    func onInitialized() async throws
}

extension Component {
    public func onInitialized() async throws {}
    public func write(to buffer: inout ByteBuffer) { body.write(to: &buffer) }
    public var asContent: HTMLContent { HTMLContent { buffer in self.body.write(to: &buffer) } }
}

public protocol LayoutComponent: Component {
    var content: HTMLContent? { get set }
}

@discardableResult
public func HTMLElement(tag: String, attributes: [String: String] = [:], content: HTMLContent? = nil) -> HTMLContent {
    return HTMLContent { buffer in
        buffer.writeString("<")
        buffer.writeString(tag)
        for (name, value) in attributes {
            buffer.writeString(" ")
            buffer.writeString(name)
            buffer.writeString("=\"")
            buffer.writeString(value)
            buffer.writeString("\"")
        }
        if let inner = content {
            buffer.writeString(">")
            inner.write(to: &buffer)
            buffer.writeString("</")
            buffer.writeString(tag)
            buffer.writeString(">")
        } else {
            buffer.writeString(" />")
        }
    }
}

// Added back overload for trailing closures
@discardableResult
public func HTMLElement(tag: String, attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    return HTMLElement(tag: tag, attributes: attributes, content: content())
}

@discardableResult
public func WriteRaw(_ content: String) -> HTMLContent {
    return HTMLContent { buffer in buffer.writeString(content) }
}

@discardableResult
public func Div(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "div", attributes: attributes, content: content())
}
@discardableResult
public func P(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "p", attributes: attributes, content: content())
}
@discardableResult
public func H1(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "h1", attributes: attributes, content: content())
}
@discardableResult
public func Table(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "table", attributes: attributes, content: content())
}
@discardableResult
public func Tr(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "tr", attributes: attributes, content: content())
}
@discardableResult
public func Td(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "td", attributes: attributes, content: content())
}
@discardableResult
public func Th(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "th", attributes: attributes, content: content())
}
@discardableResult
public func Thead(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "thead", attributes: attributes, content: content())
}
@discardableResult
public func Tbody(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "tbody", attributes: attributes, content: content())
}
@discardableResult
public func Ul(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "ul", attributes: attributes, content: content())
}
@discardableResult
public func Li(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "li", attributes: attributes, content: content())
}
@discardableResult
public func Span(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "span", attributes: attributes, content: content())
}
@discardableResult
public func A(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "a", attributes: attributes, content: content())
}
@discardableResult
public func Main(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "main", attributes: attributes, content: content())
}
@discardableResult
public func Article(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "article", attributes: attributes, content: content())
}
@discardableResult
public func Nav(attributes: [String: String] = [:], @HTMLBuilder content: @escaping () -> HTMLContent) -> HTMLContent {
    HTMLElement(tag: "nav", attributes: attributes, content: content())
}
@discardableResult
public func Img(attributes: [String: String] = [:]) -> HTMLContent {
    HTMLElement(tag: "img", attributes: attributes)
}
