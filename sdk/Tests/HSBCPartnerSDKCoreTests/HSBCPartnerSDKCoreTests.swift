import XCTest
@testable import HSBCPartnerSDKCore

final class HSBCPartnerSDKCoreTests: XCTestCase {
    func testInitialization() {
        let instance = HSBCPartnerSDKCore()
        XCTAssertNotNil(instance)
    }
}
