import Foundation
import CosmoApiServer

public struct AppComponent: LayoutComponent {
    public var context: HttpContext?
    public var content: HTMLContent?
    
    public init() {}
    
    public var body: HTMLContent {
        #html {
            WriteRaw("<!DOCTYPE html>")
            HTMLElement(tag: "html", attributes: ["lang": "en"]) {
                HTMLElement(tag: "head") {
                    HTMLElement(tag: "meta", attributes: ["charset": "utf-8"])
                    HTMLElement(tag: "meta", attributes: ["name": "viewport", "content": "width=device-width, initial-scale=1.0"])
                    HTMLElement(tag: "link", attributes: [
                        "rel": "stylesheet",
                        "href": "https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css"
                    ])
                    HTMLElement(tag: "link", attributes: ["rel": "stylesheet", "href": "/app.css"])
                    HTMLElement(tag: "title") { "SwiftSqlSample - CosmoApiServer" }
                }
                HTMLElement(tag: "body") {
                    if let content = content {
                        content
                    }
                }
            }
        }
    }
}
