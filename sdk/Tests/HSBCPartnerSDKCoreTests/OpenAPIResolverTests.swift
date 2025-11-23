import XCTest
@testable import HSBCPartnerSDKCore

final class OpenAPIResolverTests: XCTestCase {
    func testMissingOperationIdFailsValidation() throws {
        let oas = """
        {
          "openapi": "3.0.0",
          "paths": {
            "/widgets": {
              "post": { "operationId": "createWidget" }
            }
          }
        }
        """
        let resolver = try OpenAPIResolver(openAPIData: Data(oas.utf8))
        
        let manifestDict: [String: Any] = [
            "manifestVersion": "1.1",
            "minSdk": "1.0.0",
            "journeyId": "test",
            "oapiBundle": "https://example.com/oas.json",
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
                    "bindings": [
                        [
                            "onEvent": "submit",
                            "call": [
                                "operationId": "missingOp"
                            ]
                        ]
                    ]
                ]
            ],
            "signature": "dummy"
        ]
        let data = try JSONSerialization.data(withJSONObject: manifestDict)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        
        XCTAssertThrowsError(try resolver.validateOperationIds(manifest: manifest))
    }
}
