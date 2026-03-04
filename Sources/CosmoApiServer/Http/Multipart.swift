import Foundation

// MARK: - Public Types

/// A file extracted from a `multipart/form-data` request.
public struct MultipartFile: Sendable {
    /// The form field name (from `Content-Disposition: name="…"`).
    public let name: String
    /// The original filename supplied by the client.
    public let filename: String
    /// The MIME type of the file (e.g. `"image/jpeg"`). Defaults to
    /// `"application/octet-stream"` when the client omits `Content-Type`.
    public let contentType: String
    /// The raw file bytes.
    public let data: Data
}

/// The parsed result of a `multipart/form-data` request.
public struct MultipartForm: Sendable {
    /// Plain-text fields keyed by field name.
    public let fields: [String: String]
    /// File uploads keyed by field name. Only the last file is kept when a
    /// field name appears more than once.
    public let files: [String: MultipartFile]

    public init(fields: [String: String] = [:], files: [String: MultipartFile] = [:]) {
        self.fields = fields
        self.files  = files
    }
}

// MARK: - Parser

/// Parses `multipart/form-data` bodies.
public enum MultipartParser {

    public enum ParseError: Error, CustomStringConvertible {
        case notMultipart
        case missingBoundary
        case invalidBody

        public var description: String {
            switch self {
            case .notMultipart:    return "Content-Type is not multipart/form-data"
            case .missingBoundary: return "boundary parameter missing from Content-Type"
            case .invalidBody:     return "multipart body is malformed"
            }
        }
    }

    // MARK: Public entry points

    /// Parse the body of `request` as `multipart/form-data`.
    public static func parse(_ request: HttpRequest) throws -> MultipartForm {
        guard let ct = request.header("content-type") else { throw ParseError.notMultipart }
        return try parse(body: request.body, contentType: ct)
    }

    /// Parse raw bytes given an explicit `Content-Type` value.
    public static func parse(body: Data, contentType: String) throws -> MultipartForm {
        guard contentType.lowercased().contains("multipart/form-data") else {
            throw ParseError.notMultipart
        }
        guard let boundary = boundaryValue(from: contentType) else {
            throw ParseError.missingBoundary
        }
        return try parse(body: body, boundary: boundary)
    }

    // MARK: Core parser

    static func parse(body: Data, boundary: String) throws -> MultipartForm {
        // Each part is separated by "\r\n--{boundary}".
        // The body begins with "--{boundary}\r\n" and ends with "--{boundary}--".
        let dash2     = Data("--".utf8)
        let delim     = Data(("--" + boundary).utf8)
        let crlf      = Data([0x0D, 0x0A])
        let crlfcrlf  = Data([0x0D, 0x0A, 0x0D, 0x0A])

        // Locate the opening boundary.
        guard let first = body.range(of: delim) else { throw ParseError.invalidBody }

        var cursor = first.upperBound
        // Opening boundary must be followed by CRLF (not "--" which is the final boundary).
        guard cursor + 2 <= body.count,
              body[cursor] == 0x0D, body[cursor + 1] == 0x0A else {
            return MultipartForm() // empty / final boundary immediately
        }
        cursor += 2 // skip \r\n after opening boundary

        var fields: [String: String]   = [:]
        var files:  [String: MultipartFile] = [:]

        while cursor < body.count {
            // Find the next delimiter (which terminates the current part).
            // Parts are separated by \r\n--{boundary}.
            let searchDelim = Data(("\r\n--" + boundary).utf8)
            guard let sepRange = body.range(of: searchDelim, in: cursor..<body.count) else {
                // No more separators — parse remaining bytes as the last part.
                let partBytes = Data(body[cursor...])
                parsePart(partBytes, crlfcrlf: crlfcrlf, fields: &fields, files: &files)
                break
            }

            let partBytes = Data(body[cursor..<sepRange.lowerBound])
            parsePart(partBytes, crlfcrlf: crlfcrlf, fields: &fields, files: &files)

            // Advance past "\r\n--{boundary}". What follows is either:
            //   "\r\n"  → another part
            //   "--"    → final boundary, we're done
            cursor = sepRange.upperBound
            guard cursor + 2 <= body.count else { break }

            if body[cursor] == 0x2D && body[cursor + 1] == 0x2D { // "--"
                break
            }
            if body[cursor] == 0x0D && body[cursor + 1] == 0x0A { // "\r\n"
                cursor += 2
            } else {
                break // unexpected byte — stop
            }
        }

        return MultipartForm(fields: fields, files: files)
    }

    // MARK: Part parsing

    private static func parsePart(
        _ data: Data,
        crlfcrlf: Data,
        fields: inout [String: String],
        files:  inout [String: MultipartFile]
    ) {
        // A well-formed part is:  {headers}\r\n\r\n{body}
        guard let sep = data.range(of: crlfcrlf) else { return }
        let headerData = Data(data[data.startIndex..<sep.lowerBound])
        let bodyData   = Data(data[sep.upperBound...])

        let headers     = parseHeaders(headerData)
        let disposition = headers["content-disposition"] ?? ""
        guard let name  = param("name", in: disposition) else { return }
        let filename    = param("filename", in: disposition)
        let mimeType    = headers["content-type"] ?? "application/octet-stream"

        if let filename {
            files[name] = MultipartFile(name: name, filename: filename,
                                        contentType: mimeType, data: bodyData)
        } else {
            fields[name] = String(data: bodyData, encoding: .utf8) ?? ""
        }
    }

    // MARK: Helpers

    /// Parse header lines into a lowercased-key dictionary.
    private static func parseHeaders(_ data: Data) -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in text.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let val = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            result[key] = val
        }
        return result
    }

    /// Extract a named parameter from a `Content-Disposition` value.
    /// e.g. `name="avatar"` → `"avatar"`, `filename="photo.jpg"` → `"photo.jpg"`
    static func param(_ name: String, in disposition: String) -> String? {
        let search = name.lowercased() + "="
        for component in disposition.components(separatedBy: ";") {
            let t = component.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix(search) {
                let value = String(t.dropFirst(search.count))
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }

    /// Extract the `boundary` value from a `Content-Type` header.
    static func boundaryValue(from contentType: String) -> String? {
        for component in contentType.components(separatedBy: ";") {
            let t = component.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("boundary=") {
                let value = String(t.dropFirst("boundary=".count))
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }
}
