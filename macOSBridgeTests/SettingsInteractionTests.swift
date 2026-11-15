import AppKit
import XCTest
@testable import macOSBridge

final class SettingsInteractionTests: XCTestCase {
    @MainActor
    func testSensorOnlyRoomExpandsWithSummaryEnabledAndVisibilityControlsWork() throws {
        try withHome(sensorCount: 2) { settings, window, data in
            let home = try XCTUnwrap(descendants(settings).compactMap { $0 as? AccessoriesSettingsView }.first)
            let table = try XCTUnwrap(home.roomsTableView)
            let room = try XCTUnwrap(data.rooms.first)
            let headerIndex = try XCTUnwrap(home.roomTableItems.firstIndex {
                if case .header = $0 { return true }; return false
            })
            let header = try XCTUnwrap(table.view(atColumn: 0, row: headerIndex, makeIfNecessary: true))
            header.layoutSubtreeIfNeeded()
            let disclosure = try button("home.disclosure", in: header)
            click(disclosure, window: window)
            settings.layoutSubtreeIfNeeded()
            XCTAssertTrue(home.expandedSections.contains(room.uniqueIdentifier))
            let serviceIds = Set(home.roomTableItems.compactMap { item -> String? in
                if case .accessory(let service, _, _) = item { return service.uniqueIdentifier }
                return nil
            })
            XCTAssertEqual(serviceIds, Set(data.accessories.flatMap(\.services).map(\.uniqueIdentifier)))

            let newHeader = try XCTUnwrap(table.view(atColumn: 0, row: headerIndex, makeIfNecessary: true))
            newHeader.layoutSubtreeIfNeeded()
            click(try button("home.visibility", in: newHeader), window: window)
            XCTAssertTrue(PreferencesManager.shared.isHidden(roomId: room.uniqueIdentifier))

            let serviceIndex = try XCTUnwrap(home.roomTableItems.firstIndex {
                if case .accessory = $0 { return true }; return false
            })
            guard case .accessory(let service, _, _) = home.roomTableItems[serviceIndex] else { return XCTFail() }
            let serviceRow = try XCTUnwrap(table.view(atColumn: 0, row: serviceIndex, makeIfNecessary: true))
            settings.layoutSubtreeIfNeeded()
            serviceRow.layoutSubtreeIfNeeded()
            click(try button("home.visibility", in: serviceRow), window: window)
            XCTAssertTrue(PreferencesManager.shared.isHidden(serviceId: service.uniqueIdentifier))
            home.configure(with: data)
            XCTAssertTrue(home.expandedSections.contains(room.uniqueIdentifier))
            XCTAssertTrue(PreferencesManager.shared.isHidden(roomId: room.uniqueIdentifier))
            XCTAssertTrue(PreferencesManager.shared.isHidden(serviceId: service.uniqueIdentifier))
        }
    }

    @MainActor
    func testExpandedHomeDocumentScrollsToLastVisibilityButton() throws {
        try withHome(sensorCount: 80) { settings, _, _ in
            let home = try XCTUnwrap(descendants(settings).compactMap { $0 as? AccessoriesSettingsView }.first)
            let room = try XCTUnwrap(home.orderedRooms.first)
            home.toggleSectionExpanded(room.uniqueIdentifier)
            settings.layoutSubtreeIfNeeded()
            let scroll = try contentScroll(in: settings)
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertGreaterThan(document.frame.height, scroll.contentSize.height)
            XCTAssertEqual(document.bounds.height, home.frame.maxY + 20, accuracy: 1)
            document.scroll(NSPoint(x: 0, y: document.bounds.height - scroll.contentSize.height))
            scroll.reflectScrolledClipView(scroll.contentView)
            settings.layoutSubtreeIfNeeded()
            let table = try XCTUnwrap(home.roomsTableView)
            let row = try XCTUnwrap(table.view(atColumn: 0, row: table.numberOfRows - 1, makeIfNecessary: true))
            row.layoutSubtreeIfNeeded()
            let eye = try button("home.visibility", in: row)
            let rect = document.convert(eye.bounds, from: eye)
            XCTAssertTrue(scroll.documentVisibleRect.intersects(rect))
            XCTAssertNotNil(table.window)
        }
    }

    @MainActor
    func testLongSensorMenusStaySelectableAndStableDuringLiveUpdates() throws {
        try withHome(sensorCount: 160) { settings, _, data in
            settings.selectSection(at: 5) // Advanced in Home Assistant mode.
            settings.layoutSubtreeIfNeeded()
            let section = try XCTUnwrap(descendants(settings).compactMap { $0 as? AdvancedSection }.first)
            let temperature = try XCTUnwrap(descendants(section).compactMap { $0 as? NSPopUpButton }
                .first { $0.accessibilityIdentifier() == "climate.temperature" })
            let humidity = try XCTUnwrap(descendants(section).compactMap { $0 as? NSPopUpButton }
                .first { $0.accessibilityIdentifier() == "climate.humidity" })
            for popUp in [temperature, humidity] {
                XCTAssertEqual(popUp.numberOfItems, 81)
                XCTAssertTrue(popUp.isEnabled)
                popUp.menu?.update()
                XCTAssertTrue(popUp.itemArray.allSatisfy(\.isEnabled))
                let items = popUp.itemArray
                section.configure(with: data)
                XCTAssertTrue(zip(items, popUp.itemArray).allSatisfy { $0.0 === $0.1 })
                popUp.selectItem(at: popUp.numberOfItems - 1)
                XCTAssertTrue(popUp.sendAction(popUp.action, to: popUp.target))
            }
            XCTAssertEqual(PreferencesManager.shared.menuBarTemperatureSensorId, temperature.selectedItem?.representedObject as? String)
            XCTAssertEqual(PreferencesManager.shared.menuBarHumiditySensorId, humidity.selectedItem?.representedObject as? String)

            let menu = try XCTUnwrap(temperature.menu)
            section.menuWillOpen(menu)
            let originalItems = temperature.itemArray
            let smaller = MenuData(homes: data.homes, rooms: data.rooms, accessories: [], scenes: [], selectedHomeId: UUID(uuidString: data.selectedHomeId!))
            section.configure(with: smaller)
            XCTAssertEqual(temperature.numberOfItems, originalItems.count)
            XCTAssertTrue(zip(originalItems, temperature.itemArray).allSatisfy { $0.0 === $0.1 })
            section.menuDidClose(menu)
        }
    }

    @MainActor
    private func withHome(sensorCount: Int, body: (SettingsView, NSWindow, MenuData) throws -> Void) throws {
        _ = NSApplication.shared
        let preferences = PreferencesManager.shared
        let previousHome = preferences.currentHomeId
        let previousSummary = preferences.sensorSummary
        let previousPlatform = PlatformManager.shared.selectedPlatform
        let homeId = UUID()
        let roomId = UUID()
        preferences.currentHomeId = homeId.uuidString
        preferences.sensorSummary = true
        preferences.menuBarClimateEnabled = true
        PlatformManager.shared.selectedPlatform = .homeAssistant
        defer {
            for key in preferences.defaults.dictionaryRepresentation().keys where key.hasSuffix("_" + homeId.uuidString) {
                preferences.defaults.removeObject(forKey: key)
            }
            preferences.currentHomeId = previousHome
            preferences.sensorSummary = previousSummary
            PlatformManager.shared.selectedPlatform = previousPlatform
        }
        let services = (0..<sensorCount).map { index in
            ServiceData(uniqueIdentifier: UUID(), name: "Sensor \(index / 2)",
                        serviceType: index.isMultiple(of: 2) ? ServiceTypes.temperatureSensor : ServiceTypes.humiditySensor,
                        accessoryName: "Sensor", roomIdentifier: roomId,
                        currentTemperatureId: index.isMultiple(of: 2) ? UUID() : nil,
                        humidityId: index.isMultiple(of: 2) ? nil : UUID())
        }
        let data = MenuData(homes: [], rooms: [RoomData(uniqueIdentifier: roomId, name: "Sensors")],
                            accessories: [AccessoryData(uniqueIdentifier: UUID(), name: "Sensors", roomIdentifier: roomId, services: services, isReachable: true)],
                            scenes: [], selectedHomeId: homeId)
        let settings = SettingsView(frame: NSRect(x: 0, y: 0, width: 750, height: 350))
        settings.configure(with: data)
        settings.selectSection(at: 2) // Home in Home Assistant mode.
        let window = NSWindow(contentRect: settings.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = settings
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        settings.layoutSubtreeIfNeeded()
        try body(settings, window, data)
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    @MainActor
    private func button(_ identifier: String, in view: NSView) throws -> NSButton {
        try XCTUnwrap(descendants(view).compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == identifier })
    }

    @MainActor
    private func contentScroll(in settings: SettingsView) throws -> NSScrollView {
        try XCTUnwrap(settings.subviews.compactMap { $0 as? NSScrollView }.first { $0.documentView is FlippedView })
    }

    @MainActor
    private func click(_ button: NSButton, window: NSWindow) {
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0.01,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
    }
}
