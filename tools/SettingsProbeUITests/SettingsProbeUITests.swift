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
            let result = XCTWaiter.wait(for: [ready], timeout: 10)
            if result != .completed { print("PROBE_STATE \(state())"); print(app.debugDescription) }
            XCTAssertEqual(result, .completed, description)
        }
        wait("fixture ready") { $0["ready"] as? Bool == true }
        let initialUpdates = try XCTUnwrap(state()["dataUpdates"] as? Int)
        let window = app.windows["Settings"]
        func point(_ kind: String, _ room: String) throws -> XCUICoordinate {
            let controls = state()["controls"] as? [String: [String: [Double]]]
            let p = try XCTUnwrap(controls?[room]?[kind])
            XCTAssertEqual(p.count, 2)
            return window.coordinate(withNormalizedOffset: CGVector(dx: CGFloat(p[0]), dy: CGFloat(p[1])))
        }
        // These are real OS mouse events at the controls' measured positions,
        // not calls to the table, button actions or preference setters.
        try point("disclosure", "one").click()
        wait("room expands through a real window click") { $0["expanded"] as? Bool == true }
        try point("disclosure", "one").click()
        wait("room collapses") { $0["expanded"] as? Bool == false }
        try point("eye", "one").click()
        wait("eye hides the room in the actual menu") { $0["hidden"] as? Bool == true && $0["menuContainsOne"] as? Bool == false }
        try point("eye", "one").click()
        wait("eye restores the room") { $0["hidden"] as? Bool == false && $0["menuContainsOne"] as? Bool == true }
        try point("drag", "one").click(forDuration: 0.3, thenDragTo: point("after", "three"))
        wait("drag persists the new order") { $0["order"] as? [String] == ["two", "three", "one"] && $0["savedOrder"] as? [String] == ["two", "three", "one"] }
        try point("drag", "one").click(forDuration: 0.3, thenDragTo: point("before", "two"))
        wait("a second drag restores the order") { $0["order"] as? [String] == ["one", "two", "three"] && $0["savedOrder"] as? [String] == ["one", "two", "three"] }
        XCTAssertEqual(state()["dataUpdates"] as? Int, initialUpdates, "Local actions must not rebroadcast platform snapshots or reconfigure Settings")
        XCTAssertEqual(state()["climateEnabled"] as? Bool, true)
        XCTAssertEqual(state()["temperatureId"] as? String, "00000000-0000-0000-0001-000000000001")
    }
}
