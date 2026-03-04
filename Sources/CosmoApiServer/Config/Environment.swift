import Foundation

/// Application environment — controls feature flags, logging verbosity, and behaviour.
///
///     let env = Environment.current   // .development / .staging / .production
///     env.isProduction                // false
///
///     // Load a .env file at startup (before reading any variables):
///     Environment.loadDotEnv()
///
///     // Read a variable (process env takes precedence over .env):
///     let dbUrl = Environment.get("DATABASE_URL", default: "sqlite://./dev.db")
public enum Environment: String, Sendable, CustomStringConvertible {
    case development
    case staging
    case production

    // MARK: - Internal store (populated from .env file)

    private static var _store: [String: String] = [:]

    // MARK: - Current environment

    /// The current environment, determined by the `COSMO_ENV` or `APP_ENV`
    /// environment variable. Defaults to `.development` when not set.
    public static var current: Environment {
        let raw = get("COSMO_ENV") ?? get("APP_ENV") ?? "development"
        return Environment(rawValue: raw.lowercased()) ?? .development
    }

    // MARK: - Variable access

    /// Returns the value for `key`, checking the process environment first,
    /// then any variables loaded from a `.env` file.
    public static func get(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key] ?? _store[key]
    }

    /// Returns the value for `key`, or `defaultValue` if not found.
    public static func get(_ key: String, default defaultValue: String) -> String {
        get(key) ?? defaultValue
    }

    // MARK: - .env file loading

    /// Loads variables from a `.env`-style file into the internal store.
    ///
    /// Rules:
    /// - Lines starting with `#` are comments.
    /// - Blank lines are ignored.
    /// - Values may be wrapped in single or double quotes (stripped automatically).
    /// - Process environment variables always take precedence; `.env` values
    ///   fill in only what is missing.
    ///
    ///     Environment.loadDotEnv()           // reads ".env" in CWD
    ///     Environment.loadDotEnv(from: "/etc/app/.env")
    @discardableResult
    public static func loadDotEnv(from path: String = ".env") -> Bool {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return false
        }
        for raw in content.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            // Support optional `export KEY=VALUE` prefix
            let stripped = line.hasPrefix("export ") ? String(line.dropFirst(7)) : line

            let parts = stripped.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)

            // Strip optional surrounding quotes
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }

            // Don't shadow process environment
            if ProcessInfo.processInfo.environment[key] == nil {
                _store[key] = value
            }
        }
        return true
    }

    // MARK: - Convenience flags

    public var isProduction: Bool  { self == .production }
    public var isDevelopment: Bool { self == .development }
    public var isStaging: Bool     { self == .staging }

    public var description: String { rawValue }
}
