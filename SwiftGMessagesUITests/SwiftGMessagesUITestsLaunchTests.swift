//
//  SwiftGMessagesUITestsLaunchTests.swift
//  SwiftGMessagesUITests
//
//  Created by Max Weinbach on 12/6/25.
//

import XCTest

final class SwiftGMessagesUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        activateAndAssertForeground(app)

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
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
