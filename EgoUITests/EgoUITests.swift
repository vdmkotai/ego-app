import XCTest

final class EgoUITests: XCTestCase {
    @MainActor func testComposeSearchAndCalendar() throws {
        let app = XCUIApplication(); app.launchArguments = ["--uitest"]; app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]; app.launch()
        if app.buttons["Начать"].exists { app.buttons["Начать"].tap() }
        app.buttons["Запись"].tap()
        app.buttons["Лучше напишу"].tap()
        let editor = app.textViews["Текст записи"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("Ego archive verification")
        app.buttons["Готово"].tap()
        app.buttons["Поиск"].tap()
        let search = app.textFields["searchField"]; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("archive verification")
        XCTAssertTrue(app.staticTexts["Найдено: 1"].waitForExistence(timeout: 5))
        app.buttons["Готово"].tap()
        app.buttons["Календарь"].tap()
        app.buttons["Год"].tap()
        XCTAssertTrue(app.buttons["Выбрать год"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Ego calendar year"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

extension EgoUITests {
    @MainActor func testReferenceScreens() throws {
        let app = XCUIApplication(); app.launchArguments = ["--preview"]; app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]; app.launch()
        if app.buttons["Начать"].exists { capture(app, "00-welcome"); app.buttons["Начать"].tap() }
        XCTAssertTrue(app.buttons["Запись"].waitForExistence(timeout: 8))
        capture(app, "01-journal")
        app.buttons["Запись"].tap()
        XCTAssertTrue(app.buttons["Начать запись"].waitForExistence(timeout: 5)); capture(app, "02-capture-idle")
        app.buttons["Закрыть запись"].tap()
        app.buttons["Настройки"].tap()
        XCTAssertTrue(app.staticTexts["Распознавание речи"].waitForExistence(timeout: 5)); capture(app, "03-settings")
        app.buttons["Готово"].tap()
        app.buttons["Календарь"].tap(); capture(app, "04-calendar-month")
        app.buttons["Год"].tap(); capture(app, "05-calendar-year")
        app.buttons["Выбрать год"].tap(); capture(app, "06-year-picker")
        app.buttons["Готово"].firstMatch.tap()
        app.buttons["Готово"].tap()
        app.buttons["Итоги недели"].tap(); capture(app, "07-review")
    }
    @MainActor func testRecordingPauseResumePlaybackAndRecovery() throws {
        let app = XCUIApplication(); app.launchArguments = ["--uitest"]; app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]; app.launch()
        if app.buttons["Начать"].exists { app.buttons["Начать"].tap() }
        app.buttons["Запись"].tap(); app.buttons["Начать запись"].tap()
        XCTAssertTrue(app.buttons["Пауза"].waitForExistence(timeout: 8))
        let timer = app.staticTexts["recordingTimer"]
        let elapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (Int(timer.value as? String ?? "0") ?? 0) >= 2 }, object: timer)
        XCTAssertEqual(XCTWaiter.wait(for: [elapsed], timeout: 6), .completed)
        capture(app, "08-recording")
        app.buttons["Пауза"].tap(); XCTAssertTrue(app.buttons["Продолжить"].exists); capture(app, "09-paused")
        let pausedTime = Int(timer.value as? String ?? "0") ?? 0
        app.buttons["Продолжить"].tap()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (Int(timer.value as? String ?? "0") ?? 0) > pausedTime }, object: timer)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 5), .completed)
        app.buttons["Сохранить запись"].tap()
        XCTAssertTrue(app.staticTexts["Аудиозапись"].waitForExistence(timeout: 5))
        app.staticTexts["Аудиозапись"].tap()
        XCTAssertTrue(app.buttons["Воспроизвести"].waitForExistence(timeout: 5)); capture(app, "10-saved-audio")
        app.buttons["Воспроизвести"].tap()
        XCTAssertTrue(app.buttons["Пауза воспроизведения"].waitForExistence(timeout: 5))
        app.buttons["Пауза воспроизведения"].tap()
        app.terminate(); app.launchArguments = ["--uitest", "--keep-journal"]; app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]; app.launch()
        XCTAssertTrue(app.staticTexts["Аудиозапись"].waitForExistence(timeout: 5))
        app.staticTexts["Аудиозапись"].tap()
        XCTAssertTrue(app.buttons["Воспроизвести"].waitForExistence(timeout: 5))
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}


extension EgoUITests {
    @MainActor func testFaceIDProtectsSettingsAfterBackground() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Face ID protection is verified with the owner on the physical iPhone.")
        #else
        let app = XCUIApplication(); app.launchArguments = ["--uitest", "--manual-unlock"]; app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]; app.launch()
        if app.buttons["Начать"].exists { app.buttons["Начать"].tap() }
        app.buttons["Настройки"].tap()
        let toggle = app.switches["Face ID"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let initiallyEnabled = toggle.value as? String == "1"
        if !initiallyEnabled { toggle.tap() }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)
        guard XCTWaiter.wait(for: [enabled], timeout: 45) == .completed else { XCTFail("Complete Face ID authentication on the device to enable diary protection."); return }
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["Открыть дневник"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Распознавание речи"].exists)
        capture(app, "11-locked-over-settings")
        app.buttons["Открыть дневник"].tap()
        XCTAssertTrue(app.staticTexts["Распознавание речи"].waitForExistence(timeout: 45))
        if !initiallyEnabled {
            app.switches["Face ID"].tap()
            let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: app.switches["Face ID"])
            XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 45), .completed)
        }
        #endif
    }
}

extension EgoUITests {
    @MainActor func testEnglishInterfaceAndRussianContent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-onboarded", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["A place for\nyour thoughts."].waitForExistence(timeout: 8))
        capture(app, "en-00-welcome")
        app.buttons["Start"].tap()
        // Argument-domain defaults intentionally force onboarding for its screenshot.
        // Relaunch without that override before testing the rest of the app.
        app.terminate(); app.launchArguments = ["--uitest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Entry"].tap()
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 5))
        capture(app, "en-02-capture")
        app.buttons["Type it instead"].tap()
        let editor = app.textViews["Entry text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        editor.typeText("Russian language remains independent of the interface.")
        app.buttons["Done"].tap()
        app.buttons["Search"].tap()
        app.textFields["searchField"].tap(); app.textFields["searchField"].typeText("independent")
        XCTAssertTrue(app.staticTexts["Found: 1"].waitForExistence(timeout: 5))
        capture(app, "en-03-search")
        app.buttons["Done"].tap()
        app.buttons["Calendar"].tap(); app.buttons["Year"].tap()
        XCTAssertTrue(app.staticTexts["January"].exists)
        capture(app, "en-04-year")
        app.buttons["Done"].tap()
        app.buttons["Weekly review"].tap()
        XCTAssertTrue(app.staticTexts["Your week, in your words."].waitForExistence(timeout: 5))
        capture(app, "en-05-review")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["interfaceLanguage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Speech recognition"].exists)
        XCTAssertTrue(app.staticTexts["Russian"].exists)
        capture(app, "en-06-settings")
        app.swipeUp()
        app.buttons["Action button"].tap()
        XCTAssertTrue(app.staticTexts["One button.\nA new thought."].waitForExistence(timeout: 5))
        capture(app, "en-07-action-button")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Widgets"].tap()
        XCTAssertTrue(app.staticTexts["A thought away."].waitForExistence(timeout: 5))
        capture(app, "en-08-widgets")
        app.terminate()
        // Real Russian content stays verbatim under an English interface.
        app.launchArguments = ["--preview", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Entry"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["«Впервые за неделю никуда не торопился.»"].exists)
        capture(app, "en-01-journal-russian-content")
    }
}

extension EgoUITests {
    @MainActor func testSwipeDeletionAndCenteredConfirmation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--uitest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        if app.buttons["Start"].exists { app.buttons["Start"].tap() }
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entryRow-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(rows.count, 2)
        capture(app, "polish-01-home")
        let microphone = app.buttons["Entry"]
        XCTAssertEqual(microphone.frame.width, microphone.frame.height, accuracy: 2)
        microphone.tap()
        XCTAssertTrue(app.buttons["Start recording"].waitForExistence(timeout: 5))
        app.buttons["Close recording"].tap()
        let firstID = rows.firstMatch.identifier
        app.buttons[firstID].swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        capture(app, "polish-02-swipe")
        app.buttons["Delete"].tap()
        let confirmation = app.alerts["Delete this entry?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        capture(app, "polish-03-confirmation")
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons[firstID].exists)
        app.buttons[firstID].swipeLeft(); app.buttons["Delete"].tap()
        confirmation.buttons["Delete entry"].tap()
        XCTAssertTrue(app.buttons[firstID].waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
        // The same native gesture works in the calendar's selected-day list.
        app.buttons["Calendar"].tap()
        let calendarList = app.collectionViews["calendarEntries"]
        let remaining = calendarList.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "entryRow-")).firstMatch
        if !remaining.isHittable { calendarList.swipeUp() }
        XCTAssertTrue(remaining.waitForExistence(timeout: 5))
        remaining.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
        capture(app, "polish-04-calendar-swipe")
        app.buttons["Delete"].tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Cancel"].tap()
        remaining.tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        capture(app, "polish-05-detail-confirmation")
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Edit text"].exists)
        app.buttons["Delete"].tap(); confirmation.buttons["Delete entry"].tap()
        XCTAssertTrue(app.staticTexts["No entries"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--uitest", "--keep-journal", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["What’s on your mind?"].waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 0)
    }
}
