import Foundation

public struct SqlQueryModel: Sendable {
    public var sql: String = "SELECT * FROM sys.objects"
    public var columns: [String] = []
    public var rows: [[String?]] = []
    public var error: String?
    public var elapsedSeconds: Double = 0
    
    public init() {}
}
