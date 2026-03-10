import Foundation

/// A lightweight, JSON-backed configuration system similar to Microsoft.Extensions.Configuration.
public final class Configuration: Sendable {
    public static let shared = Configuration()
    
    private let _store: [String: AnySendable]
    
    public init(store: [String: AnySendable] = [:]) {
        self._store = store
    }
    
    /// Access configuration values using dot-notation (e.g. "Server:Port").
    public subscript(key: String) -> AnySendable? {
        let parts = key.split(separator: ":").map(String.init)
        return getValue(parts: parts, current: _store)
    }
    
    /// Returns a string value for the given key.
    public func getString(_ key: String) -> String? {
        self[key]?.value as? String
    }
    
    /// Returns an integer value for the given key.
    public func getInt(_ key: String) -> Int? {
        if let val = self[key]?.value as? Int { return val }
        if let s = getString(key) { return Int(s) }
        return nil
    }
    
    /// Returns a boolean value for the given key.
    public func getBool(_ key: String) -> Bool? {
        if let val = self[key]?.value as? Bool { return val }
        if let s = getString(key) { return Bool(s) }
        return nil
    }
    
    private func getValue(parts: [String], current: [String: AnySendable]) -> AnySendable? {
        guard let first = parts.first else { return nil }
        let remaining = Array(parts.dropFirst())
        
        guard let value = current[first] else { return nil }
        
        if remaining.isEmpty {
            return value
        }
        
        if let dict = value.value as? [String: AnySendable] {
            return getValue(parts: remaining, current: dict)
        }
        
        return nil
    }
}

/// A wrapper to make Any sendable for configuration storage.
public struct AnySendable: @unchecked Sendable {
    public let value: Any
    public init(_ value: Any) { self.value = value }
}

/// Builder for constructing Configuration objects.
public final class ConfigurationBuilder {
    private var data: [String: Any] = [:]
    
    public init() {}
    
    @discardableResult
    public func addJsonFile(_ path: String, optional: Bool = true) -> Self {
        guard let content = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            if !optional { fatalError("Required configuration file not found: \(path)") }
            return self
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: content) as? [String: Any] else {
            if !optional { fatalError("Failed to parse configuration file: \(path)") }
            return self
        }
        
        merge(json)
        return self
    }
    
    @discardableResult
    public func addEnvironmentVariables() -> Self {
        merge(ProcessInfo.processInfo.environment)
        return self
    }
    
    private func merge(_ dict: [String: Any]) {
        for (key, value) in dict {
            data[key] = value
        }
    }
    
    public func build() -> Configuration {
        Configuration(store: convert(data))
    }
    
    private func convert(_ dict: [String: Any]) -> [String: AnySendable] {
        var result: [String: AnySendable] = [:]
        for (key, value) in dict {
            if let nested = value as? [String: Any] {
                result[key] = AnySendable(convert(nested))
            } else {
                result[key] = AnySendable(value)
            }
        }
        return result
    }
}
