import Foundation
import CosmoApiServer

public struct NavMenu: Component {
    public var context: HttpContext?
    public init() {}
    
    public var body: HTMLContent {
        #html {
            Div {
                Div(attributes: ["class": "top-row-sidebar ps-3 navbar navbar-dark"]) {
                    Div(attributes: ["class": "container-fluid"]) {
                        A(attributes: ["class": "navbar-brand", "href": "/"]) { "SwiftSqlSample" }
                    }
                }
                
                HTMLElement(tag: "input", attributes: ["type": "checkbox", "title": "Navigation menu", "class": "navbar-toggler"])
                
                Div(attributes: ["class": "nav-scrollable"]) {
                    Nav(attributes: ["class": "nav flex-column"]) {
                        Div(attributes: ["class": "nav-item px-3"]) {
                            A(attributes: ["class": "nav-link", "href": "/"]) { "Home" }
                        }
                        Div(attributes: ["class": "nav-item px-3"]) {
                            A(attributes: ["class": "nav-link", "href": "/query"]) { "SQL Query" }
                        }
                    }
                }
            }
        }
    }
}
