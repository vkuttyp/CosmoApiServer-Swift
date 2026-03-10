import Foundation
import NIOCore

/// An ActionResult that renders a Component to the HTTP response.
public struct ComponentResult: ActionResult {
    public var component: any Component
    public let status: Int
    
    public init(_ component: any Component, status: Int = 200) {
        self.component = component
        self.status = status
    }
    
    public func execute(response: HttpResponse) async throws {
        response.setStatus(status)
        
        let context = response.httpContext
        
        var comp = component
        comp.context = context
        try await comp.onInitialized()
        
        var finalContent: any Component = comp
        
        // Automatic wrapping: Component -> Layout -> App
        if let app = context?.application {
            var contentToWrap = comp.asContent
            
            if var layout = app.mainLayout {
                layout.context = context
                layout.content = comp.asContent
                try await layout.onInitialized()
                finalContent = layout
                contentToWrap = layout.asContent
            }
            
            if var appComp = app.appComponent {
                appComp.context = context
                appComp.content = contentToWrap
                try await appComp.onInitialized()
                finalContent = appComp
            }
        }
        
        response.writeHTML(finalContent)
    }
}
