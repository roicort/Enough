//
//  EnoughUITests.swift
//  EnoughUITests
//
//  Created by Rodrigo Cortez on 07/10/26.
//

import XCTest

final class EnoughUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testSettingsLanguageChangesWithoutRestart() throws {
        let app = XCUIApplication()
        app.launch()

#if os(macOS)
        app.buttons["openSettings"].click()
        let languagePicker = app.popUpButtons["appLanguage"]
        XCTAssertTrue(languagePicker.waitForExistence(timeout: 5))
        languagePicker.click()
        app.menuItems["English"].click()
        XCTAssertTrue(app.staticTexts["App language"].waitForExistence(timeout: 5))

        languagePicker.click()
        app.menuItems["Spanish"].click()
        XCTAssertTrue(app.staticTexts["Idioma de la app"].waitForExistence(timeout: 5))

        languagePicker.click()
        app.menuItems["English"].click()
        XCTAssertTrue(app.staticTexts["App language"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Idioma de la app"].exists)
#else
        throw XCTSkip("This regression exercises the macOS settings sheet.")
#endif
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
