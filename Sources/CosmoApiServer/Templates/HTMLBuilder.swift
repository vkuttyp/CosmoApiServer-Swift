import Foundation
import NIOCore

public struct HTMLContent: Sendable {
    private let _write: @Sendable (inout ByteBuffer) -> Void
    public init(_ write: @Sendable @escaping (inout ByteBuffer) -> Void) { self._write = write }
    public func write(to buffer: inout ByteBuffer) { _write(&buffer) }
    public static let empty = HTMLContent { _ in }
}

public struct RawHTML: Sendable {
    let content: String
    public init(_ content: String) { self.content = content }
}

@resultBuilder
public struct HTMLBuilder {
    // Single variadic buildBlock is most reliable. 
    // Swift compiler optimizes this well when inlined.
    public static func buildBlock(_ components: HTMLContent...) -> HTMLContent {
        return HTMLContent { buffer in
            for c in components {
                c.write(to: &buffer)
            }
        }
    }
    
    public static func buildOptional(_ component: HTMLContent?) -> HTMLContent {
        component ?? .empty
    }
    
    public static func buildEither(first component: HTMLContent) -> HTMLContent {
        component
    }
    
    public static func buildEither(second component: HTMLContent) -> HTMLContent {
        component
    }
    
    public static func buildArray(_ components: [HTMLContent]) -> HTMLContent {
        return HTMLContent { buffer in
            for c in components {
                c.write(to: &buffer)
            }
        }
    }
    
    public static func buildExpression(_ expression: String) -> HTMLContent {
        return HTMLContent { buffer in buffer.writeString(expression) }
    }
    
    public static func buildExpression(_ expression: any Component) -> HTMLContent {
        return expression.asContent
    }

    public static func buildExpression(_ expression: HTMLContent) -> HTMLContent {
        expression
    }
    
    public static func buildExpression(_ expression: RawHTML) -> HTMLContent {
        return HTMLContent { buffer in buffer.writeString(expression.content) }
    }
}

/// A helper function used by the #html macro to render various types at runtime.
public func renderAny(_ value: Any?, into buffer: inout ByteBuffer) {
    guard let value = value else { return }
    
    if let string = value as? String {
        buffer.writeString(string)
    } else if let content = value as? HTMLContent {
        content.write(to: &buffer)
    } else if let component = value as? any Component {
        component.asContent.write(to: &buffer)
    } else if let raw = value as? RawHTML {
        buffer.writeString(raw.content)
    } else if let array = value as? [Any] {
        for item in array {
            renderAny(item, into: &buffer)
        }
    } else {
        buffer.writeString("\(value)")
    }
}

@freestanding(expression)
public macro html(_ content: () -> Void) -> HTMLContent = #externalMacro(module: "CosmoMacrosImpl", type: "HTMLMacro")
