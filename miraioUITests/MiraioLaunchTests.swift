import XCTest

final class MiraioLaunchTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testMacOSApplicationLaunches() throws {
    let app = makeApplication()
    app.launch()

    XCTAssertTrue(app.staticTexts["Miraio"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.state, .runningForeground)

    XCTAssertTrue(app.buttons["source.catalogue"].exists)
    XCTAssertTrue(app.buttons["source.search"].exists)
    XCTAssertTrue(app.buttons["source.watchHistory"].exists)

    let evidence = XCTAttachment(screenshot: app.screenshot())
    evidence.name = "CAT-06 Catalogue destination"
    evidence.lifetime = .keepAlways
    add(evidence)
  }

  @MainActor
  func testSearchQuerySurvivesDestinationChanges() throws {
    let app = makeApplication()
    app.launch()

    app.buttons["source.search"].click()
    let search = app.textFields["catalogue.search"]
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.click()
    search.typeText("frieren")

    app.buttons["source.catalogue"].click()
    XCTAssertTrue(app.staticTexts["Catalogue"].waitForExistence(timeout: 2))
    app.buttons["source.search"].click()

    XCTAssertEqual(search.value as? String, "frieren")
    let evidence = XCTAttachment(screenshot: app.screenshot())
    evidence.name = "CAT-02 Search context preserved"
    evidence.lifetime = .keepAlways
    add(evidence)
  }

  @MainActor
  func testRussianChromeIsAvailable() throws {
    let app = makeApplication()
    app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
    app.launch()

    XCTAssertTrue(app.staticTexts["Каталог"].waitForExistence(timeout: 5))
    app.buttons["source.search"].click()
    XCTAssertTrue(app.staticTexts["Найти сериал"].waitForExistence(timeout: 2))

    let evidence = XCTAttachment(screenshot: app.screenshot())
    evidence.name = "UX-01 Russian Search destination"
    evidence.lifetime = .keepAlways
    add(evidence)
  }

  @MainActor
  func testSeriesInspectorPreservesEpisodeAndTranslationSelection() throws {
    let app = makeApplication()
    app.launch()

    let series = app.buttons["series.41"]
    XCTAssertTrue(series.waitForExistence(timeout: 5))
    series.click()
    XCTAssertTrue(app.buttons["The Journey's End"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["AniLibria · dub · ru · 1080p"].exists)

    app.buttons["source.search"].click()
    XCTAssertTrue(app.buttons["Close Series inspector"].exists)
    app.buttons["source.catalogue"].click()
    XCTAssertTrue(app.buttons["The Journey's End"].exists)
    XCTAssertTrue(app.buttons["AniLibria · dub · ru · 1080p"].exists)

    let evidence = XCTAttachment(screenshot: app.screenshot())
    evidence.name = "CAT-06 Series inspector context"
    evidence.lifetime = .keepAlways
    add(evidence)
  }

  private func makeApplication() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["MIRAIO_UI_FIXTURE"] = "1"
    return app
  }
}
