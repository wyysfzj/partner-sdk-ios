import XCTest

final class PartnerDemoAppUITests: XCTestCase {
    func testHappyPath() throws {
        let app = XCUIApplication()
        app.launch()
        
        app.buttons["Initialize SDK"].tap()
        app.buttons["Start Money Transfer"].tap()
        
        // Wait for result label to change
        let resultText = app.staticTexts.element(boundBy: 0)
        let exists = resultText.waitForExistence(timeout: 5)
        XCTAssertTrue(exists)
        let value = resultText.label.lowercased()
        XCTAssertTrue(value.contains("completed") || value.contains("pending"))
    }
}
