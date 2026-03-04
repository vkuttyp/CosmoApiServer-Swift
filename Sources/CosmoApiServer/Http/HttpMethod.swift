import Foundation

public enum HttpMethod: String, Hashable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case options = "OPTIONS"

    public init?(rawValue: String) {
        switch rawValue.uppercased() {
        case "GET":     self = .get
        case "POST":    self = .post
        case "PUT":     self = .put
        case "DELETE":  self = .delete
        case "PATCH":   self = .patch
        case "HEAD":    self = .head
        case "OPTIONS": self = .options
        default:        return nil
        }
    }
}
