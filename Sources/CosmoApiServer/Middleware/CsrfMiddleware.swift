import Foundation

public struct CsrfOptions: Sendable {
    public var cookieName: String = "XSRF-TOKEN"
    public var headerName: String = "X-XSRF-TOKEN"
    public init(cookieName: String = "XSRF-TOKEN", headerName: String = "X-XSRF-TOKEN") {
        self.cookieName = cookieName
        self.headerName = headerName
    }
}

public struct CsrfMiddleware: Middleware {
    private let options: CsrfOptions
    public init(options: CsrfOptions = CsrfOptions()) { self.options = options }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        let method = context.request.method
        if method == .get || method == .head || method == .options || context.request.path == "/echo" {
            if !hasCsrfCookie(context) { setCsrfCookie(context) }
            try await next(context)
            return
        }

        let cookieToken = getCsrfCookie(context)
        let headerToken = context.request.header(options.headerName)

        if let cookie = cookieToken, let header = headerToken, !cookie.isEmpty && cookie == header {
            try await next(context)
        } else {
            context.response.setStatus(403)
            try context.response.writeJson([
                "error": "CsrfValidationFailed",
                "message": "CSRF token validation failed."
            ])
        }
    }

    private func hasCsrfCookie(_ context: HttpContext) -> Bool {
        return context.request.headers.first(name: "cookie")?.contains(options.cookieName + "=") ?? false
    }

    private func getCsrfCookie(_ context: HttpContext) -> String? {
        guard let cookieHeader = context.request.headers.first(name: "cookie") else { return nil }
        let cookies = cookieHeader.split(separator: ";")
        for cookie in cookies {
            let trimmed = cookie.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(options.cookieName + "=") {
                return String(trimmed.dropFirst(options.cookieName.count + 1))
            }
        }
        return nil
    }

    private func setCsrfCookie(_ context: HttpContext) {
        let token = generateToken()
        context.response.setHeader("Set-Cookie", "\(options.cookieName)=\(token); Path=/; HttpOnly; SameSite=Lax")
    }

    private func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}
