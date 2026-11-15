import XCTest

final class SettingsProbeUITests: XCTestCase {
    func testRoomClicksAndDragsInCatalystWindow() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.hsianyun.itsyhome.ha.settings-probe")
        app.launch()
        defer { app.terminate() }
        let stateLabel = app.staticTexts["probe.state"]
        XCTAssertTrue(stateLabel.waitForExistence(timeout: 20))
        func state() -> [String: Any] {
            let text = stateLabel.value as? String ?? stateLabel.label
            return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        }
        func wait(_ description: String, _ condition: @escaping ([String: Any]) -> Bool) {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition(state()) }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, description)
        }
        wait("fixture ready") { $0["ready"] as? Bool == true }
        let initialUpdates = try XCTUnwrap(state()["dataUpdates"] as? Int)
        let disclosure = app.buttons["probe.disclosure.one"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        disclosure.click()
        wait("room expands through a real window click") { $0["expanded"] as? Bool == true }
        app.buttons["probe.disclosure.one"].click()
        wait("room collapses") { $0["expanded"] as? Bool == false }

        app.buttons["probe.eye.one"].click()
        wait("eye hides the room in the actual menu") { $0["hidden"] as? Bool == true && $0["menuContainsOne"] as? Bool == false }
        app.buttons["probe.eye.one"].click()
        wait("eye restores the room") { $0["hidden"] as? Bool == false && $0["menuContainsOne"] as? Bool == true }

        let source = app.buttons["probe.disclosure.one"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: -18, dy: 0))
        let end = app.buttons["probe.disclosure.three"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: -18, dy: 12))
        source.press(forDuration: 0.3, thenDragTo: end)
        wait("drag persists the new order") { $0["order"] as? [String] == ["two", "three", "one"] && $0["savedOrder"] as? [String] == ["two", "three", "one"] }
        let back = app.buttons["probe.disclosure.one"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: -18, dy: 0))
        let top = app.buttons["probe.disclosure.two"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: -18, dy: -12))
        back.press(forDuration: 0.3, thenDragTo: top)
        wait("a second drag restores the order") { $0["order"] as? [String] == ["one", "two", "three"] && $0["savedOrder"] as? [String] == ["one", "two", "three"] }
        XCTAssertEqual(state()["dataUpdates"] as? Int, initialUpdates, "Local actions must not rebroadcast platform snapshots or reconfigure Settings")
        XCTAssertEqual(state()["climateEnabled"] as? Bool, true)
        XCTAssertEqual(state()["temperatureId"] as? String, "00000000-0000-0000-0001-000000000001")
    }
}
