import Foundation
import CosmoApiServer

public struct MainLayout: LayoutComponent {
    public var context: HttpContext?
    public var content: HTMLContent?
    
    public init() {}
    
    public var body: HTMLContent {
        #html {
            Div(attributes: ["class": "page"]) {
                Div(attributes: ["class": "sidebar"]) {
                    NavMenu()
                }
                
                Main {
                    Div(attributes: ["class": "top-row px-4"]) {
                        A(attributes: [
                            "href": "https://github.com/vkuttyp/CosmoApiServer",
                            "target": "_blank"
                        ]) { "About CosmoApiServer" }
                    }
                    
                    Article(attributes: ["class": "content px-4"]) {
                        if let content = content {
                            content
                        }
                    }
                }
            }
        }
    }
}
