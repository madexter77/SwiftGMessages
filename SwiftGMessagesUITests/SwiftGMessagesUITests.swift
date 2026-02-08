//
//  SwiftGMessagesUITests.swift
//  SwiftGMessagesUITests
//
//  Created by Max Weinbach on 12/6/25.
//

import XCTest

final class SwiftGMessagesUITests: XCTestCase {

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
        let app = XCUIApplication()
        activateAndAssertForeground(app)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTOSSignpostMetric.applicationLaunch]) {
            let app = XCUIApplication()
            activateAndAssertForeground(app)
            app.terminate()
        }
    }

    @MainActor
    private func activateAndAssertForeground(_ app: XCUIApplication) {
        app.activate()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "Expected app to be running in foreground but got state \(app.state.rawValue)"
        )
    }
}
