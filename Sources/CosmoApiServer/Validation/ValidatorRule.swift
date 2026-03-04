import Foundation

/// A single validation rule applied to a value of type `T`.
///
///     errors.check("name", name, [.notEmpty, .count(max: 50)])
///     errors.check("email", email, [.notEmpty, .email])
///     errors.check("age", age, [.range(18...120)])
public struct ValidatorRule<T> {
    public let message: String
    public let passes: (T) -> Bool

    public init(_ message: String, _ passes: @escaping (T) -> Bool) {
        self.message = message
        self.passes = passes
    }
}

// MARK: - String rules

extension ValidatorRule where T == String {

    /// Value must not be empty (or only whitespace).
    public static var notEmpty: ValidatorRule {
        ValidatorRule("must not be empty") { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Number of characters must fall within `range`.
    public static func count(_ range: ClosedRange<Int>) -> ValidatorRule {
        ValidatorRule("must be between \(range.lowerBound) and \(range.upperBound) characters") {
            range.contains($0.count)
        }
    }

    /// Number of characters must be at least `min`.
    public static func count(min: Int) -> ValidatorRule {
        ValidatorRule("must be at least \(min) characters") { $0.count >= min }
    }

    /// Number of characters must be at most `max`.
    public static func count(max: Int) -> ValidatorRule {
        ValidatorRule("must be at most \(max) characters") { $0.count <= max }
    }

    /// Value must match a simple email format (local@domain.tld).
    public static var email: ValidatorRule {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return ValidatorRule("must be a valid email address") {
            $0.range(of: pattern, options: .regularExpression) != nil
        }
    }

    /// Value must be a well-formed URL.
    public static var url: ValidatorRule {
        ValidatorRule("must be a valid URL") { URL(string: $0)?.scheme != nil }
    }

    /// Value must fully match `pattern` (NSRegularExpression).
    public static func regex(_ pattern: String, message: String = "is invalid") -> ValidatorRule {
        ValidatorRule(message) { value in
            guard let re = try? NSRegularExpression(pattern: "^\(pattern)$") else { return false }
            let range = NSRange(value.startIndex..., in: value)
            return re.firstMatch(in: value, range: range) != nil
        }
    }

    /// Value must be one of the allowed values.
    public static func `in`(_ allowed: [String]) -> ValidatorRule {
        ValidatorRule("must be one of: \(allowed.joined(separator: ", "))") { allowed.contains($0) }
    }
}

// MARK: - Comparable / numeric rules

extension ValidatorRule where T: Comparable {

    /// Value must fall within `range`.
    public static func range(_ range: ClosedRange<T>) -> ValidatorRule {
        ValidatorRule("must be between \(range.lowerBound) and \(range.upperBound)") {
            range.contains($0)
        }
    }

    /// Value must be greater than or equal to `minimum`.
    public static func min(_ minimum: T) -> ValidatorRule {
        ValidatorRule("must be at least \(minimum)") { $0 >= minimum }
    }

    /// Value must be less than or equal to `maximum`.
    public static func max(_ maximum: T) -> ValidatorRule {
        ValidatorRule("must be at most \(maximum)") { $0 <= maximum }
    }
}

// MARK: - Optional rules

extension ValidatorRule {

    /// The Optional value must be non-nil (required field).
    public static func required<Wrapped>() -> ValidatorRule where T == Optional<Wrapped> {
        ValidatorRule("is required") { $0 != nil }
    }
}
