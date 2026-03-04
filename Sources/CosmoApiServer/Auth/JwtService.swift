import Foundation
import JWTKit

// MARK: - Algorithm

/// The signing algorithm and key material for JWT tokens.
public enum JwtAlgorithm: Sendable {
    /// HMAC SHA-256 with a shared secret string.
    case hs256(secret: String)
    /// RSA SHA-256. Provide a PEM-encoded private key for signing; optionally
    /// a separate public key PEM for verification-only nodes.
    case rs256(privatePem: String, publicPem: String? = nil)
    /// ECDSA P-256 SHA-256. Provide a PEM-encoded EC private key.
    case es256(privatePem: String)
}

// MARK: - Options

public struct JwtOptions: Sendable {
    public var algorithm: JwtAlgorithm
    public var issuer: String
    public var audience: String
    public var expiryMinutes: Int

    /// Convenience init for HS256 (backward-compatible with previous API).
    public init(secret: String,
                issuer: String = "CosmoApiServer",
                audience: String = "CosmoApiServer",
                expiryMinutes: Int = 60) {
        self.algorithm = .hs256(secret: secret)
        self.issuer = issuer
        self.audience = audience
        self.expiryMinutes = expiryMinutes
    }

    /// Full init accepting any algorithm.
    public init(algorithm: JwtAlgorithm,
                issuer: String = "CosmoApiServer",
                audience: String = "CosmoApiServer",
                expiryMinutes: Int = 60) {
        self.algorithm = algorithm
        self.issuer = issuer
        self.audience = audience
        self.expiryMinutes = expiryMinutes
    }
}

// MARK: - Payload

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

// MARK: - Service

public final class JwtService: Sendable {
    private let options: JwtOptions
    private let keys: JWTKeyCollection

    public init(options: JwtOptions) {
        self.options = options
        self.keys = JWTKeyCollection()
        let algorithm = options.algorithm
        Task {
            do {
                try await Self.configureKeys(keys, algorithm: algorithm)
            } catch {
                print("[JwtService] Key configuration failed: \(error)")
            }
        }
    }

    private static func configureKeys(_ keys: JWTKeyCollection, algorithm: JwtAlgorithm) async throws {
        switch algorithm {
        case .hs256(let secret):
            let keyData = Data(secret.utf8)
            await keys.add(hmac: HMACKey(from: keyData), digestAlgorithm: .sha256)

        case .rs256(let privatePem, let publicPem):
            let privateKey = try Insecure.RSA.PrivateKey(pem: privatePem)
            await keys.add(rsa: privateKey, digestAlgorithm: .sha256, kid: "rs256-private")
            if let pubPem = publicPem {
                let publicKey = try Insecure.RSA.PublicKey(pem: pubPem)
                await keys.add(rsa: publicKey, digestAlgorithm: .sha256, kid: "rs256-public")
            }

        case .es256(let privatePem):
            let privateKey = try ES256PrivateKey(pem: privatePem)
            await keys.add(ecdsa: privateKey)
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
