import XCTest
import CryptoKit
@testable import HSBCPartnerSDKCore

final class ManifestTests: XCTestCase {
    
    var keyStore: KeyStore!
    var privateKey: P256.Signing.PrivateKey!
    var publicKeyBase64: String!
    var kid: String!
    
    override func setUp() {
        super.setUp()
        keyStore = KeyStore.shared
        privateKey = P256.Signing.PrivateKey()
        kid = "test-key-1"
        
        let publicKeyData = privateKey.publicKey.x963Representation
        publicKeyBase64 = publicKeyData.base64EncodedString()
        
        keyStore.update(keys: [kid: publicKeyBase64])
    }
    
    func testAllowedOriginsNonEmpty() async throws {
        let manifestDict: [String: Any] = [
            "manifestVersion": "1.1",
            "minSdk": "1.0.0",
            "journeyId": "test-journey",
            "oapiBundle": "https://example.com/bundle",
            "startStep": "step1",
            "headers": [:],
            "security": [
                "allowedOrigins": ["https://example.com"],
                "pinning": false,
                "requireHandshake": false
            ],
            "steps": [
                "step1": [
                    "type": "web",
                    "url": "https://example.com/step1"
                ]
            ],
            "signature": "dummy"
        ]
        let data = try JSONSerialization.data(withJSONObject: manifestDict)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        XCTAssertFalse(manifest.security.allowedOrigins.isEmpty)
    }
    
    func testManifestDecoding() throws {
        let json = """
        {
            "manifestVersion": "1.1",
            "minSdk": "1.0.0",
            "journeyId": "test-journey",
            "oapiBundle": "https://example.com/bundle",
            "startStep": "step1",
            "headers": {},
            "security": {
                "allowedOrigins": ["https://example.com"],
                "pinning": false,
                "requireHandshake": false
            },
            "steps": {
                "step1": {
                    "type": "web",
                    "url": "https://example.com/step1"
                }
            },
            "signature": "dummy"
        }
        """.data(using: .utf8)!
        
        let manifest = try JSONDecoder().decode(Manifest.self, from: json)
        XCTAssertEqual(manifest.journeyId, "test-journey")
        XCTAssertEqual(manifest.steps.count, 1)
    }
    
    func testLoaderValidationSuccess() async throws {
        // Create a valid manifest
        let manifestDict: [String: Any] = [
            "manifestVersion": "1.1",
            "minSdk": "1.0.0",
            "journeyId": "test-journey",
            "oapiBundle": "https://example.com/bundle",
            "startStep": "step1",
            "headers": [:],
            "security": [
                "allowedOrigins": ["https://example.com"],
                "pinning": false,
                "requireHandshake": false
            ],
            "steps": [
                "step1": [
                    "type": "web",
                    "url": "https://example.com/step1"
                ]
            ],
            // signature will be added later
        ]
        
        // Sign it
        let payloadData = try JSONSerialization.data(withJSONObject: manifestDict, options: [.sortedKeys, .withoutEscapingSlashes])
        let signer = JWSSigner(privateKey: privateKey, kid: kid)
        let jws = try signer.sign(payload: payloadData)
        
        // The loader expects 'signature' field to be the detached JWS (header..signature)
        // But JWSSigner returns compact (header.payload.signature).
        // We need to extract header and signature.
        let parts = jws.components(separatedBy: ".")
        let detachedSignature = "\(parts[0])..\(parts[2])"
        
        var signedManifestDict = manifestDict
        signedManifestDict["signature"] = detachedSignature
        
        let signedManifestData = try JSONSerialization.data(withJSONObject: signedManifestDict, options: [])
        
        // Write to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let journeyDir = tempDir.appendingPathComponent("test-journey")
        try? FileManager.default.createDirectory(at: journeyDir, withIntermediateDirectories: true)
        let manifestFile = journeyDir.appendingPathComponent("manifest.json")
        try signedManifestData.write(to: manifestFile)
        
        // Load
        let config = HSBCInitConfig(
            environment: .sandbox,
            partnerId: "pid",
            clientId: "cid",
            redirectScheme: "scheme",
            locale: Locale(identifier: "en_US"),
            remoteConfigURL: tempDir,
            telemetryOptIn: false
        )
        
        let loader = ManifestLoader()
        let manifest = try await loader.load(journeyId: "test-journey", contextToken: "token", config: config, keyStore: keyStore)
        
        XCTAssertEqual(manifest.journeyId, "test-journey")
    }
    
    func testLoaderValidationFailure_MinSdk() async throws {
        // Create a manifest with high minSdk
        let manifestDict: [String: Any] = [
            "manifestVersion": "1.1",
            "minSdk": "99.0.0",
            "journeyId": "test-journey",
            "oapiBundle": "https://example.com/bundle",
            "startStep": "step1",
            "headers": [:],
            "security": [
                "allowedOrigins": ["https://example.com"],
                "pinning": false,
                "requireHandshake": false
            ],
            "steps": [:],
            "signature": "dummy" // Bypass verification for this test
        ]
        
        let manifestData = try JSONSerialization.data(withJSONObject: manifestDict)
        
        // Write to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let journeyDir = tempDir.appendingPathComponent("test-fail-sdk")
        try? FileManager.default.createDirectory(at: journeyDir, withIntermediateDirectories: true)
        let manifestFile = journeyDir.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestFile)
        
        let config = HSBCInitConfig(
            environment: .sandbox,
            partnerId: "pid",
            clientId: "cid",
            redirectScheme: "scheme",
            locale: Locale(identifier: "en_US"),
            remoteConfigURL: tempDir,
            featureFlags: ["disableManifestSignatureVerification": true],
            telemetryOptIn: false
        )
        
        let loader = ManifestLoader()
        
        do {
            _ = try await loader.load(journeyId: "test-fail-sdk", contextToken: "token", config: config, keyStore: keyStore)
            XCTFail("Should have thrown validation error")
        } catch ManifestLoaderError.validationFailed(let msg) {
            XCTAssertTrue(msg.contains("minSdk"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testLoaderValidationFailure_AllowedOrigins() async throws {
        // Create a manifest with empty allowedOrigins
        let manifestDict: [String: Any] = [
            "manifestVersion": "1.1",
            "minSdk": "1.0.0",
            "journeyId": "test-journey",
            "oapiBundle": "https://example.com/bundle",
            "startStep": "step1",
            "headers": [:],
            "security": [
                "allowedOrigins": [],
                "pinning": false,
                "requireHandshake": false
            ],
            "steps": [:],
            "signature": "dummy"
        ]
        
        let manifestData = try JSONSerialization.data(withJSONObject: manifestDict)
        
        // Write to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let journeyDir = tempDir.appendingPathComponent("test-fail-origins")
        try? FileManager.default.createDirectory(at: journeyDir, withIntermediateDirectories: true)
        let manifestFile = journeyDir.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestFile)
        
        let config = HSBCInitConfig(
            environment: .sandbox,
            partnerId: "pid",
            clientId: "cid",
            redirectScheme: "scheme",
            locale: Locale(identifier: "en_US"),
            remoteConfigURL: tempDir,
            featureFlags: ["disableManifestSignatureVerification": true],
            telemetryOptIn: false
        )
        
        let loader = ManifestLoader()
        
        do {
            _ = try await loader.load(journeyId: "test-fail-origins", contextToken: "token", config: config, keyStore: keyStore)
            XCTFail("Should have thrown validation error")
        } catch ManifestLoaderError.validationFailed(let msg) {
            XCTAssertTrue(msg.contains("allowedOrigins"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
