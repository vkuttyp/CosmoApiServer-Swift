import Foundation

/// A scoped view of the route table that prefixes all registered routes
/// and optionally applies a set of middleware (not yet scoped — global pipeline applies).
///
///     app.group("api/v1") { r in
///         r.get("users") { ctx in ... }        // → GET /api/v1/users
///         r.post("users") { ctx in ... }       // → POST /api/v1/users
///         r.group("admin") { a in
///             a.get("stats") { ctx in ... }    // → GET /api/v1/admin/stats
///         }
///     }
public final class RouteGroup: @unchecked Sendable {
    private let prefix: String
    private let routeTable: RouteTable

    init(prefix: String, routeTable: RouteTable) {
        // Normalise: strip leading/trailing slashes then re-add leading
        let clean = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.prefix = clean.isEmpty ? "" : "/\(clean)"
        self.routeTable = routeTable
    }

    // MARK: - Nested groups

    @discardableResult
    public func group(_ prefix: String, configure: (RouteGroup) -> Void) -> Self {
        let child = RouteGroup(prefix: self.prefix + normalise(prefix), routeTable: routeTable)
        configure(child)
        return self
    }

    // MARK: - HTTP method registration

    @discardableResult
    public func get(_ template: String, handler: @escaping RequestDelegate) -> Self {
        add(.get, template, handler); return self
    }
    @discardableResult
    public func post(_ template: String, handler: @escaping RequestDelegate) -> Self {
        add(.post, template, handler); return self
    }
    @discardableResult
    public func put(_ template: String, handler: @escaping RequestDelegate) -> Self {
        add(.put, template, handler); return self
    }
    @discardableResult
    public func delete(_ template: String, handler: @escaping RequestDelegate) -> Self {
        add(.delete, template, handler); return self
    }
    @discardableResult
    public func patch(_ template: String, handler: @escaping RequestDelegate) -> Self {
        add(.patch, template, handler); return self
    }
    @discardableResult
    public func head(_ template: String, handler: @escaping RequestDelegate) -> Self {
        add(.head, template, handler); return self
    }
    @discardableResult
    public func options(_ template: String, handler: @escaping RequestDelegate) -> Self {
        add(.options, template, handler); return self
    }

    // MARK: - Private

    private func add(_ method: HttpMethod, _ template: String, _ handler: @escaping RequestDelegate) {
        routeTable.add(method: method, template: prefix + normalise(template), handler: handler)
    }

    private func normalise(_ segment: String) -> String {
        let s = segment.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return s.isEmpty ? "" : "/\(s)"
    }
}
