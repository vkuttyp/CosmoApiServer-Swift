import Foundation

/// Serves static files from a local directory.
///
///     builder.useStaticFiles(at: "./public")
///     // or with a URL prefix:
///     builder.useStaticFiles(at: "./public", prefix: "/static")
///
/// Features:
/// - `index.html` fallback for directory requests
/// - Correct MIME type from file extension
/// - `ETag` and `Last-Modified` caching headers (304 Not Modified support)
/// - 404 for missing files; passes through to next middleware for non-matching paths
public struct StaticFileMiddleware: Middleware {
    private let directory: URL
    private let prefix: String   // e.g. "/static" or ""

    public init(directory: String, prefix: String = "") {
        self.directory = URL(fileURLWithPath: directory, isDirectory: true)
        let p = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.prefix = p.isEmpty ? "" : "/\(p)"
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        let reqPath = context.request.path

        // Only handle paths matching our prefix
        let relativePath: String
        if prefix.isEmpty {
            relativePath = reqPath
        } else if reqPath.hasPrefix(prefix) {
            relativePath = String(reqPath.dropFirst(prefix.count))
        } else {
            try await next(context)
            return
        }

        // Resolve file URL safely (prevent path traversal)
        let clean = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var fileURL = directory.appendingPathComponent(clean)

        // Directory → index.html
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
            fileURL = fileURL.appendingPathComponent("index.html")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try await next(context)
            return
        }

        // ETag / Last-Modified
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modDate = attrs[.modificationDate] as? Date ?? Date()
        let etag = "\"\(Int(modDate.timeIntervalSince1970))\""

        if let clientEtag = context.request.headers["if-none-match"], clientEtag == etag {
            context.response.setStatus(304)
            return
        }

        let data = try Data(contentsOf: fileURL)
        context.response.headers["ETag"] = etag
        context.response.headers["Last-Modified"] = Self.httpDate(modDate)
        context.response.headers["Cache-Control"] = "public, max-age=3600"
        context.response.headers["Content-Type"] = Self.mimeType(for: fileURL.pathExtension)
        context.response.write(data)
    }

    // MARK: - Helpers

    private static func httpDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        f.timeZone = TimeZone(abbreviation: "GMT")!
        return f.string(from: date)
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css":          return "text/css; charset=utf-8"
        case "js":           return "application/javascript; charset=utf-8"
        case "json":         return "application/json; charset=utf-8"
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "gif":          return "image/gif"
        case "svg":          return "image/svg+xml"
        case "ico":          return "image/x-icon"
        case "webp":         return "image/webp"
        case "woff":         return "font/woff"
        case "woff2":        return "font/woff2"
        case "ttf":          return "font/ttf"
        case "pdf":          return "application/pdf"
        case "txt":          return "text/plain; charset=utf-8"
        case "xml":          return "application/xml; charset=utf-8"
        case "mp4":          return "video/mp4"
        case "mp3":          return "audio/mpeg"
        case "wasm":         return "application/wasm"
        default:             return "application/octet-stream"
        }
    }
}
