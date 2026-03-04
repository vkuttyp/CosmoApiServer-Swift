import Foundation

struct RouteEntry: Sendable {
    let template: RouteTemplate
    let handler: RequestDelegate
}

public final class RouteTable: @unchecked Sendable {
    private var routes: [HttpMethod: [RouteEntry]] = [:]
    private let lock = NSLock()

    public init() {}

    public func add(method: HttpMethod, template: String, handler: @escaping RequestDelegate) {
        let entry = RouteEntry(template: RouteTemplate(template), handler: handler)
        lock.withLock {
            routes[method, default: []].append(entry)
        }
    }

    func match(method: HttpMethod, path: String) -> (handler: RequestDelegate, routeValues: [String: String])? {
        // Strip query string if present
        let cleanPath = path.contains("?") ? String(path.prefix(upTo: path.firstIndex(of: "?")!)) : path

        guard let entries = lock.withLock({ routes[method] }) else { return nil }
        for entry in entries {
            if let values = entry.template.tryMatch(cleanPath) {
                return (entry.handler, values)
            }
        }
        return nil
    }
}
