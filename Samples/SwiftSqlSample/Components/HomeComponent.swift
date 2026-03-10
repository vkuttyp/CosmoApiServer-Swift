import Foundation
import CosmoApiServer

public struct HomeComponent: Component {
    public var context: HttpContext?
    public init() {}
    
    public var body: HTMLContent {
        #html {
            Div {
                H1 { "Welcome to SwiftSqlSample" }
                P { "This is a Swift implementation of the BlazorSqlSample." }
            }
        }
    }
}
