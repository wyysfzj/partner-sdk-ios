import XCTest
@testable import HSBCPartnerSDKCore

final class BridgeHandshakeTests: XCTestCase {
    func testBridgeHelloAllowedOriginProducesReady() {
        let allowed = URL(string: "https://example.com")!
        let bridge = Bridge(allowedOrigins: [allowed], allowedMethods: [])
        
        var received: [String: Any]?
        bridge.outboundHook = { envelope in
            if envelope["name"] as? String == "bridge_ready" {
                received = envelope
            }
        }
        
        let message: [String: Any] = [
            "kind": "event",
            "name": "bridge_hello",
            "payload": [
                "origin": allowed.absoluteString,
                "pageNonce": "p1"
            ]
        ]
        
        bridge.process(kind: "event", body: message)
        
        XCTAssertNotNil(received)
        let payload = received?["payload"] as? [String: Any]
        XCTAssertNotNil(payload?["sessionProofJws"])
        XCTAssertNotNil(received?["sig"])
    }
    
    func testBlockedOriginEmitsOriginBlocked() {
        let allowed = URL(string: "https://example.com")!
        let bridge = Bridge(allowedOrigins: [allowed], allowedMethods: [])
        
        var blocked: [String: Any]?
        bridge.outboundHook = { envelope in
            if envelope["name"] as? String == "ORIGIN_BLOCKED" {
                blocked = envelope
            }
        }
        
        let message: [String: Any] = [
            "kind": "event",
            "name": "bridge_hello",
            "payload": [
                "origin": "https://evil.test",
                "pageNonce": "p1"
            ]
        ]
        
        bridge.process(kind: "event", body: message)
        XCTAssertNotNil(blocked)
    }
}
