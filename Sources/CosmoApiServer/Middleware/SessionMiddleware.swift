import Foundation

// MARK: - Session

/// A per-request, cookie-backed in-memory session.
///
///     // Register before handlers that need sessions:
///     builder.useSessions()
///
///     // In a route handler:
///     context.session?["userId"] = "42"
///     let id = context.session?["userId"]  // → "42"
///     context.session?.clear()
public final class Session: @unchecked Sendable {
    let id: String
    private var data: [String: String] = [:]
    private let lock = NSLock()

    init(id: String) {
        self.id = id
    }

    public subscript(key: String) -> String? {
        get { lock.withLock { data[key] } }
        set { lock.withLock { data[key] = newValue } }
    }

    public func clear() {
        lock.withLock { data.removeAll() }
    }

    public var isEmpty: Bool {
        lock.withLock { data.isEmpty }
    }
}

// MARK: - SessionStore

actor SessionStore {
    static let shared = SessionStore()
    private var sessions: [String: Session] = [:]

    /// Returns the existing session or creates a new one.
    /// The returned Bool indicates whether the session is newly created.
    func getOrCreate(id: String) -> (Session, isNew: Bool) {
        if let s = sessions[id] { return (s, false) }
        let s = Session(id: id)
        sessions[id] = s
        return (s, true)
    }

    func delete(id: String) {
        sessions.removeValue(forKey: id)
    }
}

// MARK: - Middleware

/// Attaches an in-memory session to every request, backed by a cookie.
///
/// Register via `builder.useSessions()`.
public struct SessionMiddleware: Middleware {
    public let cookieName: String
    public let secure: Bool
    public let sameSite: String

    public init(cookieName: String = "cosmo_sid", secure: Bool = false, sameSite: String = "Strict") {
        self.cookieName = cookieName
        self.secure = secure
        self.sameSite = sameSite
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        let existingId = parseCookie(context.request.header("Cookie") ?? "")
        let (session, isNew) = await SessionStore.shared.getOrCreate(id: existingId ?? UUID().uuidString)
        context.items["_session"] = session

        try await next(context)

        if isNew {
            var cookie = "\(cookieName)=\(session.id); HttpOnly; SameSite=\(sameSite); Path=/"
            if secure { cookie += "; Secure" }
            context.response.setHeader("Set-Cookie", cookie)
        }
    }

    private func parseCookie(_ header: String) -> String? {
        for part in header.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = String(kv[0]).trimmingCharacters(in: .whitespaces)
            if key == cookieName {
                return String(kv[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

// MARK: - HttpContext extension

extension HttpContext {
    /// The current session. Non-nil when `SessionMiddleware` is registered.
    public var session: Session? {
        items["_session"] as? Session
    }
}
