import Foundation
import Security

/// Errors that can occur during manifest loading.
public enum ManifestLoaderError: Error {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case missingSignature
    case signatureVerificationFailed
    case validationFailed(String)
    case keyNotFound(String)
}

/// Loads and validates the Journey Manifest.
@available(macOS 10.15, iOS 13.0, *)
public class ManifestLoader {
    
    public init() {}
    
    /// Loads the manifest for the given journey ID.
    /// - Parameters:
    ///   - journeyId: The ID of the journey to load.
    ///   - contextToken: The authorization token.
    ///   - config: The SDK configuration.
    ///   - keyStore: The key store to retrieve verification keys.
    /// - Returns: The loaded and validated Manifest.
    public func load(
        journeyId: String,
        contextToken: String,
        config: HSBCInitConfig,
        keyStore: KeyStore
    ) async throws -> Manifest {
        
        let manifestURL = try resolveManifestURL(journeyId: journeyId, config: config)
        let originalData = try await fetchManifestData(from: manifestURL, contextToken: contextToken)
        let data = adjustManifestDataIfNeeded(data: originalData, manifestURL: manifestURL, config: config)
        print("[ManifestLoader] Resolved manifest at \(manifestURL)")
        
        // 3. Decode Manifest
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            throw ManifestLoaderError.decodingError(error)
        }
        
        // 4. Verify Signature
        // Check for bypass flag
        if config.featureFlags["disableManifestSignatureVerification"] != true {
            try verifySignature(manifest: manifest, originalData: data, keyStore: keyStore)
        }
        
        // 5. Validate Manifest
        try validate(manifest: manifest)
        
        return manifest
    }
    
    private func resolveManifestURL(journeyId: String, config: HSBCInitConfig) throws -> URL {
        if let override = config.remoteConfigURL {
            // Allow pointing directly to a manifest file for local/demo scenarios.
            if override.pathExtension.lowercased() == "json" {
                return override
            }
            return override
                .appendingPathComponent(journeyId, isDirectory: true)
                .appendingPathComponent("manifest.json")
        }
        
        guard let baseURL = URL(string: "https://api.hsbc.com/journeys") else {
            throw ManifestLoaderError.invalidURL
        }
        return baseURL
            .appendingPathComponent(journeyId, isDirectory: true)
            .appendingPathComponent("manifest.json")
    }
    
    private func fetchManifestData(from url: URL, contextToken: String) async throws -> Data {
        if url.isFileURL {
            do {
                return try Data(contentsOf: url)
            } catch {
                throw ManifestLoaderError.networkError(error)
            }
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(contextToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response): (Data, URLResponse)
            if #available(macOS 12.0, iOS 15.0, *) {
                (data, response) = try await URLSession.shared.data(for: request)
            } else {
                (data, response) = try await withCheckedThrowingContinuation { continuation in
                    URLSession.shared.dataTask(with: request) { data, response, error in
                        if let error {
                            continuation.resume(throwing: ManifestLoaderError.networkError(error))
                            return
                        }
                        guard let data, let response else {
                            continuation.resume(throwing: ManifestLoaderError.invalidResponse)
                            return
                        }
                        continuation.resume(returning: (data, response))
                    }.resume()
                }
            }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw ManifestLoaderError.invalidResponse
            }
            
            return data
        } catch let error as ManifestLoaderError {
            throw error
        } catch {
            throw ManifestLoaderError.networkError(error)
        }
    }
    
    private func verifySignature(manifest: Manifest, originalData: Data, keyStore: KeyStore) throws {
        let signature = manifest.signature
        guard !signature.isEmpty else {
            throw ManifestLoaderError.missingSignature
        }
        
        // Parse JWS header to get 'kid'
        let parts = signature.components(separatedBy: ".")
        guard parts.count >= 1,
              let headerData = Data(base64URLEncoded: parts[0]),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let kid = header["kid"] as? String else {
            throw ManifestLoaderError.invalidResponse // Invalid JWS format
        }
        
        guard let key = keyStore.key(for: kid) else {
            throw ManifestLoaderError.keyNotFound(kid)
        }
        
        // Reconstruct payload
        // We need to remove the 'signature' field from the JSON and canonicalize it.
        // Since we don't have the exact canonicalization rules, we'll assume the payload
        // is the JSON representation of the manifest without the signature field,
        // encoded with sorted keys.
        
        // Create a copy of the manifest without the signature (or rather, a dictionary representation)
        // This is tricky because we need to match the server's payload exactly.
        // If the signature is detached, the payload is usually the content.
        // Let's try to decode to [String: Any], remove "signature", and re-encode.
        
        guard var jsonDict = try? JSONSerialization.jsonObject(with: originalData) as? [String: Any] else {
            throw ManifestLoaderError.decodingError(NSError(domain: "ManifestLoader", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON for verification"]))
        }
        
        jsonDict.removeValue(forKey: "signature")
        
        let payloadData = try JSONSerialization.data(withJSONObject: jsonDict, options: [.sortedKeys, .withoutEscapingSlashes])
        
        // Construct compact JWS: header.payload.signature
        // The 'signature' field in manifest is likely "header..signature" (detached)
        // So we take the header and signature parts from it, and insert the payload.
        
        guard parts.count == 3 else {
             throw ManifestLoaderError.signatureVerificationFailed
        }
        
        let headerB64 = parts[0]
        let signatureB64 = parts[2]
        
        guard let payloadB64 = payloadData.base64URLEncodedString() else {
            throw ManifestLoaderError.signatureVerificationFailed
        }
        
        let compactJWS = "\(headerB64).\(payloadB64).\(signatureB64)"
        
        do {
            _ = try JWS.verify(compact: compactJWS, key: key)
        } catch {
            print("Signature verification failed: \(error)")
            throw ManifestLoaderError.signatureVerificationFailed
        }
    }
    
    private func validate(manifest: Manifest) throws {
        if manifest.manifestVersion.hasPrefix("1.1") == false {
            throw ManifestLoaderError.validationFailed("Unsupported manifestVersion \(manifest.manifestVersion)")
        }
        
        // Validate minSdk
        let currentVersion = HSBCPartnerSDKCore.version
        if manifest.minSdk.compare(currentVersion, options: .numeric) == .orderedDescending {
            throw ManifestLoaderError.validationFailed("Manifest minSdk \(manifest.minSdk) requires SDK version \(currentVersion) or higher")
        }
        
        // Validate allowedOrigins
        if manifest.security.allowedOrigins.isEmpty {
            throw ManifestLoaderError.validationFailed("security.allowedOrigins must not be empty")
        }
        
        try validateAgainstSchema(manifest)
    }
    
    /// Placeholder for schema-level validation that can be expanded as the manifest evolves.
    private func validateAgainstSchema(_ manifest: Manifest) throws {
        guard manifest.steps[manifest.startStep] != nil else {
            throw ManifestLoaderError.validationFailed("startStep \(manifest.startStep) not found in steps")
        }
    }
    
    /// Allows relative OpenAPI bundle references when loading a local manifest (e.g. demo resources) and rewrites relative step URLs to file URLs.
    private func adjustManifestDataIfNeeded(data: Data, manifestURL: URL, config: HSBCInitConfig) -> Data {
        guard manifestURL.isFileURL,
              config.featureFlags["disableManifestSignatureVerification"] == true,
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return data
        }
        
        let baseDir = manifestURL.deletingLastPathComponent()
        
        if let oapiString = json["oapiBundle"] as? String,
           let oapiURL = URL(string: oapiString),
           oapiURL.scheme == nil {
            let resolved = baseDir.appendingPathComponent(oapiString)
            json["oapiBundle"] = resolved.absoluteString
            print("[ManifestLoader] Rewrote oapiBundle to \(resolved)")
        }
        
        if var steps = json["steps"] as? [String: Any] {
            for (key, value) in steps {
                guard var stepDict = value as? [String: Any],
                      let urlString = stepDict["url"] as? String,
                      let url = URL(string: urlString),
                      url.scheme == nil else {
                    continue
                }
                let resolved = baseDir.appendingPathComponent(urlString)
                stepDict["url"] = resolved.absoluteString
                steps[key] = stepDict
                print("[ManifestLoader] Rewrote step \(key) url to \(resolved)")
            }
            json["steps"] = steps
        }
        
        return (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? data
    }
}
