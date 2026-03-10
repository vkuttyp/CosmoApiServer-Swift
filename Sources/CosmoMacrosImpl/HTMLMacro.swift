import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin

@main
struct CosmoMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        HTMLMacro.self
    ]
}

public struct HTMLMacro: ExpressionMacro {
    private static let knownTags: Set<String> = [
        "div", "p", "h1", "table", "tr", "td", "th", "thead", "tbody", "ul", "li", "span", "a", "img", "br", "hr", "strong", "em", "form", "input", "textarea", "button", "label", "select", "option", "link", "meta", "title", "head", "body", "html", "main", "article", "nav", "header", "footer", "section", "aside"
    ]
    
    // Tags that should not be self-closed with /> in HTML5
    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"
    ]

    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let closure = node.trailingClosure ?? node.argumentList.first?.expression.as(ClosureExprSyntax.self) else {
            throw MacroError.message("#html requires a trailing closure")
        }
        
        var generatedCode = "HTMLContent { buffer in\n"
        generatedCode += processStatements(closure.statements)
        generatedCode += "}"
        
        return ExprSyntax(stringLiteral: generatedCode)
    }
    
    private static func processStatements(_ statements: CodeBlockItemListSyntax) -> String {
        var result = ""
        for statement in statements {
            result += processItem(statement.item)
        }
        return result
    }
    
    private static func processItem(_ item: CodeBlockItemSyntax.Item) -> String {
        let trimmedItem = item.trimmed
        if let expr = trimmedItem.as(ExprSyntax.self) {
             return processExpression(expr)
        } else if let stmt = trimmedItem.as(StmtSyntax.self) {
             return processStatement(stmt)
        } else {
             return "renderAny(\(trimmedItem), into: &buffer)\n"
        }
    }

    private static func processExpression(_ expr: ExprSyntax) -> String {
        let trimmedExpr = expr.trimmed
        if let call = trimmedExpr.as(FunctionCallExprSyntax.self) {
            return processFunctionCall(call)
        } else if let str = trimmedExpr.as(StringLiteralExprSyntax.self) {
             if str.segments.count == 1, let firstSegment = str.segments.first, firstSegment.is(StringSegmentSyntax.self) {
                return "buffer.writeStaticString(\(str))\n"
            } else {
                return "buffer.writeString(\(str))\n"
            }
        } else if let ifExpr = trimmedExpr.as(IfExprSyntax.self) {
            return processIfExpr(ifExpr)
        } else {
            return "renderAny(\(trimmedExpr), into: &buffer)\n"
        }
    }

    private static func processStatement(_ stmt: StmtSyntax) -> String {
        let trimmedStmt = stmt.trimmed
        if let forStmt = trimmedStmt.as(ForStmtSyntax.self) {
            return processForStmt(forStmt)
        } else if let exprStmt = trimmedStmt.as(ExpressionStmtSyntax.self) {
            return processExpression(exprStmt.expression)
        } else {
            return "renderAny(\(trimmedStmt), into: &buffer)\n"
        }
    }
    
    private static func processFunctionCall(_ call: FunctionCallExprSyntax) -> String {
        guard let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text else {
             return "renderAny(\(call.trimmed), into: &buffer)\n"
        }
        
        let tagName: String
        var manualAttributes: [String: ExprSyntax] = [:]
        
        if name == "HTMLElement" {
            var tagExpr: ExprSyntax?
            for arg in call.arguments {
                if arg.label?.text == "tag" {
                    tagExpr = arg.expression
                } else if arg.label?.text == "attributes" {
                    manualAttributes["attributes"] = arg.expression
                }
            }
            
            if let tagStr = tagExpr?.as(StringLiteralExprSyntax.self)?.segments.first?.as(StringSegmentSyntax.self)?.content.text {
                 tagName = tagStr.lowercased()
            } else {
                 return "renderAny(\(call.trimmed), into: &buffer)\n"
            }
        } else if knownTags.contains(name.lowercased()) {
            tagName = name.lowercased()
            for arg in call.arguments {
                if arg.label?.text == "attributes" {
                    manualAttributes["attributes"] = arg.expression
                }
            }
        } else {
            return "renderAny(\(call.trimmed), into: &buffer)\n"
        }
        
        var result = "buffer.writeStaticString(\"<\(tagName)\")\n"
        
        if let attrExpr = manualAttributes["attributes"] {
             result += "for (name, value) in \(attrExpr.trimmed) {\n"
             result += "buffer.writeStaticString(\" \")\n"
             result += "buffer.writeString(name)\n"
             result += "buffer.writeStaticString(\"=\\\"\")\n"
             result += "buffer.writeString(value)\n"
             result += "buffer.writeStaticString(\"\\\"\")\n"
             result += "}\n"
        }
        
        if let closure = call.trailingClosure {
            result += "buffer.writeStaticString(\">\")\n"
            result += processStatements(closure.statements)
            result += "buffer.writeStaticString(\"</\(tagName)>\")\n"
        } else if voidTags.contains(tagName) {
            result += "buffer.writeStaticString(\">\")\n"
        } else {
            result += "buffer.writeStaticString(\" />\")\n"
        }
        
        return result
    }
    
    private static func processForStmt(_ forStmt: ForStmtSyntax) -> String {
        var result = "for \(forStmt.pattern.trimmed) in \(forStmt.sequence.trimmed) {\n"
        result += processStatements(forStmt.body.statements)
        result += "}\n"
        return result
    }

    private static func processIfExpr(_ ifStmt: IfExprSyntax) -> String {
        var result = "if \(ifStmt.conditions.trimmed) {\n"
        result += processStatements(ifStmt.body.statements)
        result += "}"
        if let elseBody = ifStmt.elseBody {
            if let elseIf = elseBody.as(IfExprSyntax.self) {
                result += " else " + processIfExpr(elseIf)
            } else if let elseBlock = elseBody.as(CodeBlockSyntax.self) {
                result += " else {\n"
                result += processStatements(elseBlock.statements)
                result += "}\n"
            }
        } else {
            result += "\n"
        }
        return result
    }
}

enum MacroError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self {
        case .message(let msg): return msg
        }
    }
}
