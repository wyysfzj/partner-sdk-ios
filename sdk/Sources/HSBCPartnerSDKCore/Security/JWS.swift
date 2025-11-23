import Foundation
import CryptoKit
import Security

/// Errors that can occur during JWS operations.
public enum JWSError: Error {
    case invalidFormat
    case invalidHeader
    case invalidSignature
    case unsupportedAlgorithm
    case keyMismatch
    case signingFailed
}

/// Helper for verifying JWS signatures.
public struct JWS {
    
    /// Verifies a compact JWS string using the provided public key.
    /// - Parameters:
    ///   - compact: The JWS string in compact serialization (header.payload.signature).
    ///   - key: The SecKey to verify against.
    /// - Returns: The decoded payload data if verification succeeds.
    /// - Throws: JWSError if verification fails.
    public static func verify(compact: String, key: SecKey) throws -> Data {
        let parts = compact.components(separatedBy: ".")
        guard parts.count == 3 else {
            throw JWSError.invalidFormat
        }
        
        let headerB64 = parts[0]
        let payloadB64 = parts[1]
        let signatureB64 = parts[2]
        
        guard let headerData = Data(base64URLEncoded: headerB64),
              let payloadData = Data(base64URLEncoded: payloadB64),
              let signatureData = Data(base64URLEncoded: signatureB64) else {
            throw JWSError.invalidFormat
        }
        
        // Verify Header
        guard let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let alg = header["alg"] as? String,
              alg == "ES256" else {
            throw JWSError.unsupportedAlgorithm
        }
        
        // Verify Signature
        let signedContent = "\(headerB64).\(payloadB64)"
        guard let signedContentData = signedContent.data(using: .ascii) else {
            throw JWSError.invalidFormat
        }

        // Prefer CryptoKit verification first (expects raw signature).
        if #available(iOS 13.0, macOS 10.15, *),
           let publicKeyData = SecKeyCopyExternalRepresentation(key, nil) as Data? {
            do {
                let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
                let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
                if publicKey.isValidSignature(signature, for: signedContentData) {
                    return payloadData
                }
            } catch {
                // Fall back to SecKey verification below.
            }
        }

        guard let derSignature = rawSignatureToDER(signatureData) else {
            throw JWSError.invalidSignature
        }
        
        var error: Unmanaged<CFError>?
        let algorithm: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA256
        
        guard SecKeyIsAlgorithmSupported(key, .verify, algorithm) else {
            throw JWSError.unsupportedAlgorithm
        }
        
        let result = SecKeyVerifySignature(
            key,
            algorithm,
            signedContentData as CFData,
            derSignature as CFData,
            &error
        )
        
        if result {
            return payloadData
        }
        
        print("JWS Verification failed: \(error?.takeRetainedValue().localizedDescription ?? "Unknown error")")
        throw JWSError.invalidSignature
    }
}

private func rawSignatureToDER(_ raw: Data) -> Data? {
    let halfLength = raw.count / 2
    guard halfLength > 0 else { return nil }
    let r = raw.prefix(halfLength)
    let s = raw.suffix(halfLength)
    
    func derEncodeInteger(_ int: Data) -> Data {
        var bytes = Array(int)
        while bytes.first == 0 { bytes.removeFirst() }
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        var encoded = Data([0x02, UInt8(bytes.count)])
        encoded.append(contentsOf: bytes)
        return encoded
    }
    
    let rEncoded = derEncodeInteger(r)
    let sEncoded = derEncodeInteger(s)
    let length = rEncoded.count + sEncoded.count
    
    var sequence = Data([0x30, UInt8(length)])
    sequence.append(rEncoded)
    sequence.append(sEncoded)
    return sequence
}

/// Helper for signing data to create a JWS.
@available(iOS 13.0, macOS 10.15, *)
public struct JWSSigner {
    private let privateKey: P256.Signing.PrivateKey
    private let kid: String
    
    /// Creates a new signer.
    /// - Parameters:
    ///   - privateKey: The private key to sign with.
    ///   - kid: The Key ID to include in the header.
    public init(privateKey: P256.Signing.PrivateKey, kid: String) {
        self.privateKey = privateKey
        self.kid = kid
    }
    
    /// Signs the payload and returns a compact JWS string.
    /// - Parameter payload: The data to sign.
    /// - Returns: The compact JWS string.
    /// - Throws: JWSError if signing fails.
    public func sign(payload: Data) throws -> String {
        let header: [String: String] = [
            "alg": "ES256",
            "kid": kid
        ]
        
        guard let headerData = try? JSONSerialization.data(withJSONObject: header),
              let headerString = headerData.base64URLEncodedString() else {
            throw JWSError.signingFailed
        }
        
        guard let payloadString = payload.base64URLEncodedString() else {
            throw JWSError.signingFailed
        }
        
        let contentToSign = "\(headerString).\(payloadString)"
        guard let contentData = contentToSign.data(using: .ascii) else {
            throw JWSError.signingFailed
        }
        
        do {
            let signature = try privateKey.signature(for: contentData)
            // P256.Signing.ECDSASignature.rawRepresentation gives P1363 format (r || s)
            // JWS expects this raw format for ES256.
            guard let signatureString = signature.rawRepresentation.base64URLEncodedString() else {
                throw JWSError.signingFailed
            }
            
            return "\(contentToSign).\(signatureString)"
        } catch {
            throw JWSError.signingFailed
        }
    }
}

// MARK: - Base64URL Extensions

extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        
        self.init(base64Encoded: base64)
    }
    
    func base64URLEncodedString() -> String? {
        let base64 = self.base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
