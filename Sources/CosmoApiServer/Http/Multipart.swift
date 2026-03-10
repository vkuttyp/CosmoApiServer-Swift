import Foundation
import NIOCore

// MARK: - Public Types

/// A file extracted from a `multipart/form-data` request.
public struct MultipartFile: Sendable {
    public let name: String
    public let filename: String
    public let contentType: String
    public let data: ByteBuffer
}

public struct MultipartForm: Sendable {
    public let fields: [String: String]
    public let files: [String: MultipartFile]

    public init(fields: [String: String] = [:], files: [String: MultipartFile] = [:]) {
        self.fields = fields
        self.files  = files
    }
}

// MARK: - Parser

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

    public static func parse(_ request: HttpRequest) throws -> MultipartForm {
        guard let ct = request.header("content-type") else { throw ParseError.notMultipart }
        return try parse(body: request.body, contentType: ct)
    }

    public static func parse(body: ByteBuffer, contentType: String) throws -> MultipartForm {
        guard contentType.lowercased().contains("multipart/form-data") else {
            throw ParseError.notMultipart
        }
        guard let boundary = boundaryValue(from: contentType) else {
            throw ParseError.missingBoundary
        }
        return try parse(body: body, boundary: boundary)
    }

    static func parse(body: ByteBuffer, boundary: String) throws -> MultipartForm {
        let delim = "--" + boundary
        let searchDelim = "\r\n--" + boundary
        
        var fields: [String: String] = [:]
        var files: [String: MultipartFile] = [:]
        
        guard let bytes = body.getBytes(at: body.readerIndex, length: body.readableBytes) else {
            return MultipartForm()
        }
        let bodyData = Data(bytes)
        
        guard let first = bodyData.range(of: Data(delim.utf8)) else { throw ParseError.invalidBody }

        var cursor = first.upperBound
        guard cursor + 2 <= bodyData.count,
              bodyData[cursor] == 0x0D, bodyData[cursor + 1] == 0x0A else {
            return MultipartForm()
        }
        cursor += 2

        while cursor < bodyData.count {
            guard let sepRange = bodyData.range(of: Data(searchDelim.utf8), in: cursor..<bodyData.count) else {
                let partBytes = bodyData[cursor...]
                parsePart(Data(partBytes), fields: &fields, files: &files)
                break
            }

            let partBytes = bodyData[cursor..<sepRange.lowerBound]
            parsePart(Data(partBytes), fields: &fields, files: &files)

            cursor = sepRange.upperBound
            guard cursor + 2 <= bodyData.count else { break }

            if bodyData[cursor] == 0x2D && bodyData[cursor + 1] == 0x2D {
                break
            }
            if bodyData[cursor] == 0x0D && bodyData[cursor + 1] == 0x0A {
                cursor += 2
            } else {
                break
            }
        }

        return MultipartForm(fields: fields, files: files)
    }

    private static func parsePart(
        _ data: Data,
        fields: inout [String: String],
        files:  inout [String: MultipartFile]
    ) {
        let crlfcrlf = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let sep = data.range(of: crlfcrlf) else { return }
        let headerData = data[data.startIndex..<sep.lowerBound]
        let bodyData   = data[sep.upperBound...]

        let headers     = parseHeaders(Data(headerData))
        let disposition = headers["content-disposition"] ?? ""
        guard let name  = param("name", in: disposition) else { return }
        let filename    = param("filename", in: disposition)
        let mimeType    = headers["content-type"] ?? "application/octet-stream"

        if let filename {
            var buf = ByteBuffer()
            buf.writeBytes(bodyData)
            files[name] = MultipartFile(name: name, filename: filename,
                                        contentType: mimeType, data: buf)
        } else {
            fields[name] = String(data: bodyData, encoding: .utf8) ?? ""
        }
    }

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
