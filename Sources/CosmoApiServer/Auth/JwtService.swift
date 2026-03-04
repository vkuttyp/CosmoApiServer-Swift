import Foundation
import JWTKit

public struct JwtOptions: Sendable {
    public var secret: String
    public var issuer: String
    public var audience: String
    public var expiryMinutes: Int

    public init(secret: String, issuer: String = "CosmoApiServer",
                audience: String = "CosmoApiServer", expiryMinutes: Int = 60) {
        self.secret = secret
        self.issuer = issuer
        self.audience = audience
        self.expiryMinutes = expiryMinutes
    }
}

/// JWT payload stored in tokens.
struct CosmoPayload: JWTPayload, Equatable {
    var sub: SubjectClaim
    var exp: ExpirationClaim
    var iss: IssuerClaim
    var aud: AudienceClaim
    var claims: [String: String]

    func verify(using _: some JWTAlgorithm) async throws {
        try exp.verifyNotExpired()
    }
}

public final class JwtService: Sendable {
    private let options: JwtOptions
    private let keys: JWTKeyCollection

    public init(options: JwtOptions) {
        self.options = options
        let keyData = Data(options.secret.utf8)
        self.keys = JWTKeyCollection()
        Task {
            await self.keys.add(hmac: HMACKey(from: keyData), digestAlgorithm: .sha256)
        }
    }

    public func generateToken(claims: [String: String]) async throws -> String {
        let expiry = Date().addingTimeInterval(Double(options.expiryMinutes) * 60)
        let payload = CosmoPayload(
            sub: SubjectClaim(value: claims["sub"] ?? ""),
            exp: ExpirationClaim(value: expiry),
            iss: IssuerClaim(value: options.issuer),
            aud: AudienceClaim(value: [options.audience]),
            claims: claims
        )
        return try await keys.sign(payload)
    }

    public func validateToken(_ token: String) async -> Claims? {
        guard let payload = try? await keys.verify(token, as: CosmoPayload.self) else { return nil }
        var values = payload.claims
        values["sub"] = payload.sub.value
        values["iss"] = payload.iss.value
        return Claims(values)
    }
}
