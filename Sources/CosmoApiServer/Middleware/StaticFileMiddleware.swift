import Foundation

/// Serves static files from a local directory.
public struct StaticFileMiddleware: Middleware {
    private let directory: String
    private let prefix: String

    public init(directory: String, prefix: String = "") {
        self.directory = directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.prefix = prefix.hasPrefix("/") ? prefix : "/\(prefix)"
    }

    public func invoke(_ context: HttpContext, next: RequestDelegate) async throws {
        let path = context.request.path
        
        guard path.hasPrefix(prefix) else {
            try await next(context)
            return
        }

        var relativePath = String(path.dropFirst(prefix.count))
        if relativePath.hasPrefix("/") { relativePath.removeFirst() }
        if relativePath.isEmpty { relativePath = "index.html" }

        let fileURL = URL(fileURLWithPath: directory).appendingPathComponent(relativePath)
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir) {
            if isDir.boolValue {
                let indexURL = fileURL.appendingPathComponent("index.html")
                if FileManager.default.fileExists(atPath: indexURL.path) {
                    try serve(fileURL: indexURL, context: context)
                    return
                }
            } else {
                try serve(fileURL: fileURL, context: context)
                return
            }
        }

        try await next(context)
    }

    private func serve(fileURL: URL, context: HttpContext) throws {
        let attr = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modDate = attr[.modificationDate] as? Date ?? Date()
        let etag = "\"\(Int(modDate.timeIntervalSince1970))\""

        if context.request.headers.first(name: "if-none-match") == etag {
            context.response.setStatus(304)
            return
        }

        let data = try Data(contentsOf: fileURL)
        context.response.setHeader("ETag", etag)
        context.response.setHeader("Last-Modified", Self.httpDate(modDate))
        context.response.setHeader("Cache-Control", "public, max-age=3600")
        context.response.setHeader("Content-Type", Self.mimeType(for: fileURL.pathExtension))
        context.response.write(data)
    }

    private static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss \"GMT\""
        return formatter.string(from: date)
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm":  return "text/html; charset=utf-8"
        case "css":          return "text/css"
        case "js":           return "application/javascript"
        case "json":         return "application/json"
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "gif":          return "image/gif"
        case "svg":          return "image/svg+xml"
        case "pdf":          return "application/pdf"
        case "txt":          return "text/plain; charset=utf-8"
        case "xml":          return "application/xml; charset=utf-8"
        default:             return "application/octet-stream"
        }
    }
}
