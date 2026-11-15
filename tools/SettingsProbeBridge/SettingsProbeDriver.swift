import AppKit

/// Compiled only by project-settings-probe.yml. Exercises the full production
/// controller, menu builder, notifications and Settings in a Catalyst host.
@objc(SettingsProbeDriver)
final class SettingsProbeDriver: NSObject, SettingsProbe {
    private var controller: MacOSController!
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var dataUpdates = 0
    private var eventMonitor: Any?
    private var lastMouseHit = "none"
    private let stateLabel = NSTextField(wrappingLabelWithString: "starting")
    private var stateWindow: NSWindow!
    private let roomIds = (1...3).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }

    required override init() { super.init() }

    func start() {
        let prefs = PreferencesManager.shared
        let probeId = "com.hsianyun.itsyhome.ha.settings-probe"
        precondition(Bundle.main.bundleIdentifier == probeId)
        prefs.defaults.removePersistentDomain(forName: probeId)
        prefs.currentHomeId = nil // HA's actual menu snapshots use nil.
        prefs.sensorSummary = true
        prefs.autoGroupsEnabled = false
        prefs.menuBarClimateEnabled = true
        prefs.menuBarTemperatureSensorId = "00000000-0000-0000-0001-000000000001"
        observer = NotificationCenter.default.addObserver(forName: SettingsView.menuDataChangedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.dataUpdates += 1
        }
        controller = MacOSController()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let root = event.window?.contentView, let parent = root.superview {
                let point = parent.convert(event.locationInWindow, from: nil)
                let hit = root.hitTest(point)
                self?.lastMouseHit = "\(event.window?.title ?? "none"): \(hit.map { String(describing: type(of: $0)) } ?? "nil")"
            }
            return event
        }
        // Let the normal missing-credentials navigation finish before loading
        // a synthetic platform snapshot; no real HA server or token is used.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showFixture() }
    }

    private func showFixture() {
        let rooms = zip(roomIds, ["one", "two", "three"]).map { RoomData(uniqueIdentifier: $0.0, name: "Probe Room \($0.1)") }
        let accessories = roomIds.enumerated().map { index, roomId -> AccessoryData in
            let sensorId = UUID(uuidString: String(format: "00000000-0000-0000-0001-%012d", index + 1))!
            let service = ServiceData(uniqueIdentifier: sensorId, name: "Probe sensor", serviceType: ServiceTypes.temperatureSensor,
                                      accessoryName: "Probe sensor", roomIdentifier: roomId, currentTemperatureId: UUID())
            return AccessoryData(uniqueIdentifier: UUID(), name: "Probe sensor", roomIdentifier: roomId, services: [service], isReachable: true)
        }
        let data = MenuData(homes: [], rooms: rooms, accessories: accessories, scenes: [], selectedHomeId: nil)
        let json = String(decoding: try! JSONEncoder().encode(data), as: UTF8.self)
        controller.platformDidUpdateMenuData(HomeAssistantPlatform(), jsonString: json)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let settings = SettingsWindowController.shared
            settings.configure(with: data)
            settings.showWindow(nil)
            settings.selectTab(index: 2)
            self.showStateWindow()
            self.publishState()
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.publishState() }
        }
    }

    private func showStateWindow() {
        stateWindow = ProbeStateWindow(contentRect: NSRect(x: 10, y: 5, width: 340, height: 70),
                                       styleMask: [.titled], backing: .buffered, defer: false)
        stateWindow.title = "Probe state"
        stateLabel.setAccessibilityIdentifier("probe.state")
        stateLabel.frame = NSRect(x: 8, y: 8, width: 324, height: 54)
        stateWindow.contentView?.addSubview(stateLabel)
        stateWindow.orderFront(nil)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func publishState() {
        guard let root = SettingsWindowController.shared.window?.contentView,
              let home = descendants(root).compactMap({ $0 as? AccessoriesSettingsView }).first else { return }
        root.layoutSubtreeIfNeeded()
        var displayed: [String] = []
        var controls: [String: [String: [Double]]] = [:]
        func position(_ point: NSPoint, in view: NSView) -> [Double] {
            let point = view.convert(point, to: nil)
            let frame = view.window!.frame
            return [Double(point.x / frame.width), Double(1 - point.y / frame.height)]
        }
        for (row, item) in home.roomTableItems.enumerated() {
            guard case .header(let room, _, _, _) = item,
                  let index = roomIds.firstIndex(where: { $0.uuidString == room.uniqueIdentifier }) else { continue }
            let name = ["one", "two", "three"][index]
            displayed.append(name)
            guard let cell = home.roomsTableView.view(atColumn: 0, row: row, makeIfNecessary: false) else { continue }
            cell.layoutSubtreeIfNeeded()
            var positions: [String: [Double]] = [:]
            // Identify the real controls for UI automation; never invoke them.
            for button in descendants(cell).compactMap({ $0 as? NSButton }) {
                switch button.action.map(NSStringFromSelector) {
                case "eyeTapped":
                    button.setAccessibilityIdentifier("probe.eye.\(name)")
                    positions["eye"] = position(NSPoint(x: button.bounds.midX, y: button.bounds.midY), in: button)
                case "chevronTapped":
                    button.setAccessibilityIdentifier("probe.disclosure.\(name)")
                    positions["disclosure"] = position(NSPoint(x: button.bounds.midX, y: button.bounds.midY), in: button)
                default: break
                }
            }
            if let handle = descendants(cell).first(where: { $0 is DragHandleView }) {
                positions["drag"] = position(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), in: handle)
            }
            let rect = home.roomsTableView.rect(ofRow: row)
            positions["before"] = position(NSPoint(x: rect.minX + 13, y: rect.minY + 5), in: home.roomsTableView)
            positions["after"] = position(NSPoint(x: rect.minX + 13, y: rect.maxY - 5), in: home.roomsTableView)
            controls[name] = positions
        }
        let prefs = PreferencesManager.shared
        let state: [String: Any] = [
            "ready": true,
            "expanded": home.expandedSections.contains(roomIds[0].uuidString),
            "hidden": prefs.isHidden(roomId: roomIds[0].uuidString),
            "menuContainsOne": controller.mainMenu.items.contains { $0.title == "Probe Room one" },
            "order": displayed,
            "savedOrder": prefs.roomOrder.compactMap { id in roomIds.firstIndex { $0.uuidString == id }.map { ["one", "two", "three"][$0] } },
            "dataUpdates": dataUpdates,
            "climateEnabled": prefs.menuBarClimateEnabled,
            "temperatureId": prefs.menuBarTemperatureSensorId ?? "",
            "controls": controls, "lastMouseHit": lastMouseHit
        ]
        let text = String(decoding: try! JSONSerialization.data(withJSONObject: state, options: .sortedKeys), as: UTF8.self)
        if stateLabel.stringValue != text {
            stateLabel.stringValue = text
            print("SETTINGS_PROBE_STATE " + text)
            fflush(stdout)
        }
    }
}

private final class ProbeStateWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
