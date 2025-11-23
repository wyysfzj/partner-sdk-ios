import Foundation
import Security

/// Represents a persisted snapshot of journey progress. Contains no PII.
public struct Snapshot: Codable {
    public let journeyId: String
    public let stepPointer: String
    public let idempotencyKey: String
    public let ts: Date
}

/// Manages session-level identifiers and snapshot persistence.
public final class SessionManager {
    
    public static let shared = SessionManager(store: DefaultKeychainStore())
    
    public private(set) var correlationId: String
    public private(set) var contextToken: String?
    public private(set) var resumeToken: String?
    public private(set) var stepPointer: String?
    public private(set) var idempotencyKey: String
    
    private let store: KeyValueStore
    private let service = "com.hsbc.partnersdk.session"
    private let account = "snapshot"
    
    init(store: KeyValueStore) {
        self.store = store
        self.correlationId = UUID().uuidString
        self.idempotencyKey = UUID().uuidString
    }
    
    /// Resets volatile identifiers for a new session.
    public func startSession(contextToken: String, resumeToken: String?) {
        self.correlationId = UUID().uuidString
        self.contextToken = contextToken
        self.resumeToken = resumeToken
        self.stepPointer = nil
        self.idempotencyKey = UUID().uuidString
    }
    
    /// Saves a PII-free snapshot to the Keychain.
    /// - Parameters:
    ///   - journeyId: The journey identifier.
    ///   - stepId: The current step pointer.
    public func saveSnapshot(journeyId: String, stepId: String) {
        let snapshot = Snapshot(
            journeyId: journeyId,
            stepPointer: stepId,
            idempotencyKey: idempotencyKey,
            ts: Date()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        _ = store.set(data: data, service: service, account: account)
    }
    
    /// Loads a snapshot using the provided resume token.
    /// - Parameter resumeToken: Opaque token provided by the caller (currently unused placeholder for future binding).
    /// - Returns: The decoded snapshot if present.
    public func loadSnapshot(resumeToken: String) -> Snapshot? {
        guard let data = store.get(service: service, account: account),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return nil
        }
        
        // Bind resumed state to current session.
        self.resumeToken = resumeToken
        self.stepPointer = snapshot.stepPointer
        self.idempotencyKey = snapshot.idempotencyKey
        
        return snapshot
    }
}

// MARK: - Keychain Helpers

protocol KeyValueStore {
    @discardableResult
    func set(data: Data, service: String, account: String) -> Bool
    func get(service: String, account: String) -> Data?
    @discardableResult
    func delete(service: String, account: String) -> Bool
}

struct DefaultKeychainStore: KeyValueStore {
    func set(data: Data, service: String, account: String) -> Bool {
        delete(service: service, account: account)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func get(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return data
    }
    
    func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// In-memory store used for tests or environments where Keychain is unavailable.
final class InMemoryStore: KeyValueStore {
    private var storage: [String: Data] = [:]
    
    func set(data: Data, service: String, account: String) -> Bool {
        storage[key(service, account)] = data
        return true
    }
    
    func get(service: String, account: String) -> Data? {
        storage[key(service, account)]
    }
    
    func delete(service: String, account: String) -> Bool {
        storage[key(service, account)] = nil
        return true
    }
    
    private func key(_ service: String, _ account: String) -> String {
        "\(service)::\(account)"
    }
}
