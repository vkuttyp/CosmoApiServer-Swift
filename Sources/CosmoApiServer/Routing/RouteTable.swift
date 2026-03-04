import Foundation

struct RouteEntry: Sendable {
    let template: RouteTemplate
    let handler: RequestDelegate
}

// MARK: - Frozen (immutable) route table — zero-lock after build

/// Lock-free route table used during request handling. Built once from `RouteTable`.
final class FrozenRouteTable: @unchecked Sendable {
    private let routes: [HttpMethod: [RouteEntry]]

    init(routes: [HttpMethod: [RouteEntry]]) {
        self.routes = routes
    }

    func match(method: HttpMethod, path: String) -> (handler: RequestDelegate, routeValues: [String: String])? {
        guard let entries = routes[method] else { return nil }
        for entry in entries {
            if let values = entry.template.tryMatch(path) {
                return (entry.handler, values)
            }
        }
        return nil
    }
}

// MARK: - Mutable route table (build time only)

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

    /// Snapshot into a lock-free FrozenRouteTable for use during request handling.
    func freeze() -> FrozenRouteTable {
        FrozenRouteTable(routes: lock.withLock { routes })
    }

    // Legacy path used by tests — delegates to a FrozenRouteTable
    func match(method: HttpMethod, path: String) -> (handler: RequestDelegate, routeValues: [String: String])? {
        freeze().match(method: method, path: path)
    }
}
