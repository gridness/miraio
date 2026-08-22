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
    app.buttons["authentication.sign-in"].click()
    XCTAssertTrue(app.staticTexts["Войти в Anime365"].waitForExistence(timeout: 2))

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
    let episode = app.buttons["The Journey's End"]
    let translation = app.buttons["AniLibria · dub · ru · 1080p"]
    XCTAssertTrue(series.waitForExistence(timeout: 5))
    series.click()
    XCTAssertTrue(episode.waitForExistence(timeout: 3))
    XCTAssertTrue(translation.exists)
    XCTAssertEqual(episode.value as? String, "Selected")
    XCTAssertEqual(translation.value as? String, "Selected")

    app.buttons["source.search"].click()
    XCTAssertTrue(app.buttons["Close Series inspector"].exists)
    app.buttons["source.catalogue"].click()
    XCTAssertTrue(episode.exists)
    XCTAssertTrue(translation.exists)
    XCTAssertEqual(episode.value as? String, "Selected")
    XCTAssertEqual(translation.value as? String, "Selected")

    let evidence = XCTAttachment(screenshot: app.screenshot())
    evidence.name = "CAT-06 Series inspector context"
    evidence.lifetime = .keepAlways
    add(evidence)
  }

  @MainActor
  func testRejectedSignInClearsPasswordAndPreservesPublicDestinations() throws {
    let app = makeApplication()
    app.launchEnvironment["MIRAIO_UI_AUTH_STATE"] = "signed-out"
    app.launch()

    let signIn = app.buttons["authentication.sign-in"]
    XCTAssertTrue(signIn.waitForExistence(timeout: 5))
    signIn.click()
    let email = app.textFields["authentication.email"]
    let password = app.secureTextFields["authentication.password"]
    XCTAssertTrue(email.waitForExistence(timeout: 2))
    email.click()
    email.typeText("rejected@example.com")
    password.click()
    password.typeText("transient-password")
    app.buttons["authentication.submit"].click()

    XCTAssertTrue(
      app.staticTexts["Anime365 did not accept these sign-in details."]
        .waitForExistence(timeout: 2)
    )
    XCTAssertEqual(password.value as? String, "")
    XCTAssertTrue(app.buttons["source.catalogue"].isEnabled)
    XCTAssertTrue(app.buttons["source.watchHistory"].isEnabled)

    app.buttons["Cancel"].click()
    signIn.click()
    XCTAssertEqual(app.textFields["authentication.email"].value as? String, "")
    XCTAssertEqual(app.secureTextFields["authentication.password"].value as? String, "")
  }

  @MainActor
  func testCredentialUnavailableAndIncompleteSignOutRemainDistinct() throws {
    let unavailable = makeApplication()
    unavailable.launchEnvironment["MIRAIO_UI_AUTH_STATE"] = "credential-unavailable"
    unavailable.launch()
    XCTAssertTrue(
      unavailable.otherElements["authentication.state.credential-unavailable"]
        .waitForExistence(timeout: 5)
        || unavailable.staticTexts["authentication.state.credential-unavailable"]
          .waitForExistence(timeout: 1)
    )
    XCTAssertTrue(unavailable.buttons["source.catalogue"].isEnabled)
    XCTAssertTrue(unavailable.buttons["source.watchHistory"].isEnabled)
    XCTAssertTrue(unavailable.buttons["authentication.sign-out"].isEnabled)
    unavailable.terminate()

    let incomplete = makeApplication()
    incomplete.launchEnvironment["MIRAIO_UI_AUTH_STATE"] = "incomplete-sign-out"
    incomplete.launch()
    XCTAssertTrue(
      incomplete.otherElements["authentication.state.incomplete-sign-out"]
        .waitForExistence(timeout: 5)
        || incomplete.staticTexts["authentication.state.incomplete-sign-out"]
          .waitForExistence(timeout: 1)
    )
    XCTAssertFalse(incomplete.buttons["authentication.sign-in"].exists)
    XCTAssertTrue(incomplete.buttons["source.catalogue"].isEnabled)
    XCTAssertTrue(incomplete.buttons["source.watchHistory"].isEnabled)
  }

  @MainActor
  func testVerifyingProfileAndSubscriberEligibilityStatesRemainDistinct() throws {
    for (fixture, identifier) in [
      ("verifying", "authentication.state.verifying"),
      ("inactive", "authentication.state.inactive"),
      ("subscriber", "authentication.state.subscriber"),
    ] {
      let app = makeApplication()
      app.launchEnvironment["MIRAIO_UI_AUTH_STATE"] = fixture
      app.launch()
      XCTAssertTrue(
        app.descendants(matching: .any)[identifier].waitForExistence(timeout: 5),
        "Missing distinct state \(fixture)"
      )
      XCTAssertTrue(app.buttons["source.catalogue"].isEnabled)
      XCTAssertTrue(app.buttons["source.watchHistory"].isEnabled)
      if fixture == "verifying" {
        XCTAssertTrue(app.buttons["authentication.retry-verification"].isEnabled)
        XCTAssertTrue(app.buttons["authentication.sign-out"].isEnabled)
      }
      app.terminate()
    }
  }

  private func makeApplication() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["MIRAIO_UI_FIXTURE"] = "1"
    return app
  }
}
