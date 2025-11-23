import XCTest
@testable import HSBCPartnerSDKCore

final class SessionManagerTests: XCTestCase {
    
    override func setUp() async throws {
        try await super.setUp()
        clearKeychain()
    }
    
    override func tearDown() async throws {
        clearKeychain()
        try await super.tearDown()
    }
    
    func testSaveAndLoadSnapshot() {
        let manager = SessionManager(store: InMemoryStore())
        manager.startSession(contextToken: "ctx", resumeToken: nil)
        let initialIdempotency = manager.idempotencyKey
        
        manager.saveSnapshot(journeyId: "journey-1", stepId: "step-2")
        
        let loaded = manager.loadSnapshot(resumeToken: "opaque-token")
        
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.journeyId, "journey-1")
        XCTAssertEqual(loaded?.stepPointer, "step-2")
        XCTAssertEqual(loaded?.idempotencyKey, initialIdempotency)
        XCTAssertEqual(manager.idempotencyKey, initialIdempotency)
        XCTAssertEqual(manager.resumeToken, "opaque-token")
        XCTAssertEqual(manager.stepPointer, "step-2")
    }
    
    private func clearKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.hsbc.partnersdk.session",
            kSecAttrAccount as String: "snapshot"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
