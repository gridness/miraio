import XCTest

final class MiraioLaunchTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testMacOSApplicationLaunches() throws {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(app.staticTexts["Miraio"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.state, .runningForeground)

    let evidence = XCTAttachment(screenshot: app.screenshot())
    evidence.name = "FND-01 macOS launch"
    evidence.lifetime = .keepAlways
    add(evidence)
  }
}
