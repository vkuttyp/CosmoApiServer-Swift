import Foundation

/// Conform a `Decodable` type to `Validatable` to add field-level validation.
///
///     struct CreateUser: Decodable, Validatable {
///         let name: String
///         let email: String
///         let age: Int
///
///         func validate() throws {
///             var errors = ValidationErrors()
///             errors.check("name",  name,  [.notEmpty, .count(max: 100)])
///             errors.check("email", email, [.notEmpty, .email])
///             errors.check("age",   age,   [.range(18...120)])
///             try errors.throw()
///         }
///     }
///
///     // In a route handler – decode + validate in one call:
///     let user = try context.request.validateJson(CreateUser.self)
public protocol Validatable: Decodable {
    /// Validate field values and throw `ValidationError` if any rules fail.
    func validate() throws
}

// MARK: - HttpRequest convenience

extension HttpRequest {
    /// Decode the JSON body into `T` and immediately run its validations.
    ///
    /// - Throws: `Abort(400)` when the body cannot be decoded as JSON.
    /// - Throws: `ValidationError` when one or more validation rules fail (→ HTTP 422 via `ErrorMiddleware`).
    public func validateJson<T: Validatable>(_ type: T.Type) throws -> T {
        let value: T
        do {
            value = try readJson(type)
        } catch {
            throw Abort(400, reason: "Invalid JSON: \(error.localizedDescription)")
        }
        try value.validate()
        return value
    }
}
