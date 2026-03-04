import Foundation

/// Accumulates field-level validation failures.
///
/// Usage inside `Validatable.validate()`:
///
///     var errors = ValidationErrors()
///     errors.check("name",  name,  [.notEmpty, .count(max: 100)])
///     errors.check("email", email, [.notEmpty, .email])
///     errors.check("age",   age,   [.range(18...120)])
///     try errors.throw()
public struct ValidationErrors {
    public private(set) var failures: [(field: String, message: String)] = []

    public init() {}

    /// Applies `rules` to `value`; any failing rules are recorded under `field`.
    public mutating func check<T>(_ field: String, _ value: T, _ rules: [ValidatorRule<T>]) {
        for rule in rules where !rule.passes(value) {
            failures.append((field, rule.message))
        }
    }

    /// `true` when no failures have been recorded.
    public var isValid: Bool { failures.isEmpty }

    /// Throws a `ValidationError` if any failures were recorded; otherwise returns normally.
    public func `throw`() throws {
        guard !failures.isEmpty else { return }
        throw ValidationError(failures: failures)
    }
}

/// Thrown when one or more validation rules fail.
/// `ErrorMiddleware` converts this to HTTP 422 with a structured JSON body.
public struct ValidationError: Error {
    public let failures: [(field: String, message: String)]

    public init(failures: [(field: String, message: String)]) {
        self.failures = failures
    }

    /// Human-readable summary, e.g. "name: must not be empty; email: must be a valid email address"
    public var description: String {
        failures.map { "\($0.field): \($0.message)" }.joined(separator: "; ")
    }
}
