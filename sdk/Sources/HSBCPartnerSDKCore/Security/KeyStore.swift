import Foundation
import Security

/// Manages the public keys used for verifying JWS signatures.
public final class KeyStore {
    
    /// Shared singleton instance.
    public static let shared = KeyStore()
    
    private var keys: [String: SecKey] = [:]
    private let queue = DispatchQueue(label: "com.hsbc.partnersdk.keystore", attributes: .concurrent)
    
    private init() {
        loadInitialKeys()
    }
    
    /// Retrieves a key for the given Key ID.
    /// - Parameter kid: The Key ID to look up.
    /// - Returns: The SecKey if found, otherwise nil.
    public func key(for kid: String) -> SecKey? {
        queue.sync {
            keys[kid]
        }
    }
    
    /// Updates the key store with a new set of keys.
    /// - Parameter keys: A dictionary mapping Key IDs to Base64 encoded public key strings (P-256 SPKI).
    public func update(keys: [String: String]) {
        queue.async(flags: .barrier) {
            var newKeys: [String: SecKey] = [:]
            for (kid, base64Key) in keys {
                if let key = self.createKey(from: base64Key) {
                    newKeys[kid] = key
                }
            }
            self.keys = newKeys
        }
    }
    
    /// Refreshes keys from the remote configuration.
    /// - Note: This is currently a stub for future implementation.
    public func refresh() {
        // TODO: Implement remote config fetch
        print("KeyStore: Refresh requested (stub)")
    }
    
    // MARK: - Private Helpers
    
    private func loadInitialKeys() {
        // Stub: Load from a bundled JSON or hardcoded set
        // For now, we initialize with an empty set or a test key if provided
        let initialKeys: [String: String] = [:] // Empty for now
        update(keys: initialKeys)
    }
    
    private func createKey(from base64String: String) -> SecKey? {
        guard let data = Data(base64Encoded: base64String) else { return nil }
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256
        ]
        
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
            print("KeyStore: Failed to create key - \(error?.takeRetainedValue().localizedDescription ?? "Unknown error")")
            return nil
        }
        return key
    }
}
