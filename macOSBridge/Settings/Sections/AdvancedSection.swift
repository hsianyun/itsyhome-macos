//
//  AdvancedSection.swift
//  macOSBridge
//
//  Advanced settings section
//

import AppKit
import Combine

class AdvancedSection: SettingsCard, NSMenuDelegate {

    private let temperaturePopUp = NSPopUpButton()
    private let simpleLightSwitch = NSSwitch()
    private let sensorSummarySwitch = NSSwitch()
    private let menuBarClimateSwitch = NSSwitch()
    private let menuBarTemperaturePopUp = NSPopUpButton()
    private let menuBarHumidityPopUp = NSPopUpButton()
    private var menuData: MenuData?
    private var temperatureSources: [MenuBarClimateDisplay.Source] = []
    private var humiditySources: [MenuBarClimateDisplay.Source] = []
    private var isSelectingSensor = false
    private let autoGroupsSwitch = NSSwitch()
    private let historySwitch = NSSwitch()
    private let historyProBadge = AdvancedSection.createProChip()
    private var cancellables = Set<AnyCancellable>()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupContent()
        loadPreferences()
        setupBindings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with data: MenuData) {
        menuData = data
        temperatureSources = MenuBarClimateDisplay.sources(in: data, reading: .temperature)
        humiditySources = MenuBarClimateDisplay.sources(in: data, reading: .humidity)
        loadMenuBarClimatePreferences()
    }

    private func setupContent() {
        // Temperature units box
        let tempBox = createCardBox()
        temperaturePopUp.removeAllItems()
        temperaturePopUp.addItems(withTitles: [
            String(localized: "settings.general.temperature_system", defaultValue: "System default", bundle: .macOSBridge),
            String(localized: "settings.general.temperature_celsius", defaultValue: "Celsius (°C)", bundle: .macOSBridge),
            String(localized: "settings.general.temperature_fahrenheit", defaultValue: "Fahrenheit (°F)", bundle: .macOSBridge)
        ])
        temperaturePopUp.controlSize = .small
        temperaturePopUp.target = self
        temperaturePopUp.action = #selector(temperatureUnitChanged)
        let tempRow = createSettingRow(label: String(localized: "settings.general.temperature_units", defaultValue: "Temperature units", bundle: .macOSBridge), control: temperaturePopUp)
        addContentToBox(tempBox, content: tempRow, verticalInset: 4)
        stackView.addArrangedSubview(tempBox)
        tempBox.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // Combined readings beside the main menu bar icon.
        let climateBox = createCardBox()
        let climateStack = NSStackView()
        climateStack.orientation = .vertical
        climateStack.spacing = 0
        climateStack.alignment = .leading
        climateStack.translatesAutoresizingMaskIntoConstraints = false
        menuBarClimateSwitch.controlSize = .mini
        menuBarClimateSwitch.target = self
        menuBarClimateSwitch.action = #selector(menuBarClimateChanged(_:))
        let climateRow = createSettingRow(
            label: String(localized: "settings.advanced.menu_bar_climate", defaultValue: "Temperature and humidity in menu bar", bundle: .macOSBridge),
            subtitle: String(localized: "settings.advanced.menu_bar_climate_subtitle", defaultValue: "Show selected sensors beside the main icon. Missing readings appear as --.", bundle: .macOSBridge),
            control: menuBarClimateSwitch
        )
        climateStack.addArrangedSubview(climateRow)
        climateRow.widthAnchor.constraint(equalTo: climateStack.widthAnchor).isActive = true
        for (popUp, label, action) in [
            (menuBarTemperaturePopUp, String(localized: "settings.advanced.menu_bar_temperature", defaultValue: "Temperature sensor", bundle: .macOSBridge), #selector(menuBarTemperatureChanged(_:))),
            (menuBarHumidityPopUp, String(localized: "settings.advanced.menu_bar_humidity", defaultValue: "Humidity sensor", bundle: .macOSBridge), #selector(menuBarHumidityChanged(_:)))
        ] {
            popUp.controlSize = .small
            popUp.target = self
            popUp.action = action
            popUp.menu?.autoenablesItems = false
            popUp.menu?.delegate = self
            popUp.setAccessibilityIdentifier(popUp === menuBarTemperaturePopUp ? "climate.temperature" : "climate.humidity")
            popUp.widthAnchor.constraint(equalToConstant: 250).isActive = true
            popUp.cell?.lineBreakMode = .byTruncatingTail
            let row = createSettingRow(label: label, control: popUp)
            climateStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: climateStack.widthAnchor).isActive = true
        }
        addContentToBox(climateBox, content: climateStack, verticalInset: 4)
        stackView.addArrangedSubview(climateBox)
        climateBox.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // Simple light controls box
        let lightBox = createCardBox()
        simpleLightSwitch.controlSize = .mini
        simpleLightSwitch.target = self
        simpleLightSwitch.action = #selector(simpleLightSwitchChanged)
        let simpleLightRow = createSettingRow(
            label: String(localized: "settings.general.simple_light_controls", defaultValue: "Simple light controls", bundle: .macOSBridge),
            subtitle: String(localized: "settings.general.simple_light_controls_subtitle", defaultValue: "Hide brightness and colour controls for lights.", bundle: .macOSBridge),
            control: simpleLightSwitch
        )
        addContentToBox(lightBox, content: simpleLightRow, verticalInset: 4)
        stackView.addArrangedSubview(lightBox)
        lightBox.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // Sensor summary box
        let sensorBox = createCardBox()
        sensorSummarySwitch.controlSize = .mini
        sensorSummarySwitch.target = self
        sensorSummarySwitch.action = #selector(sensorSummarySwitchChanged)
        let sensorRow = createSettingRow(
            label: String(localized: "settings.advanced.sensor_summary", defaultValue: "Summarise temperature and humidity", bundle: .macOSBridge),
            subtitle: String(localized: "settings.advanced.sensor_summary_subtitle", defaultValue: "When off, shows each sensor individually.", bundle: .macOSBridge),
            control: sensorSummarySwitch
        )
        addContentToBox(sensorBox, content: sensorRow, verticalInset: 4)
        stackView.addArrangedSubview(sensorBox)
        sensorBox.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // Auto groups box
        let autoGroupsBox = createCardBox()
        autoGroupsSwitch.controlSize = .mini
        autoGroupsSwitch.target = self
        autoGroupsSwitch.action = #selector(autoGroupsSwitchChanged)
        let autoGroupsRow = createSettingRow(
            label: String(localized: "settings.advanced.auto_groups", defaultValue: "Auto groups", bundle: .macOSBridge),
            subtitle: String(localized: "settings.advanced.auto_groups_subtitle", defaultValue: "Group similar devices (All lights, All blinds, ...) for one-click control, in the menu and in each room.", bundle: .macOSBridge),
            control: autoGroupsSwitch
        )
        addContentToBox(autoGroupsBox, content: autoGroupsRow, verticalInset: 4)
        stackView.addArrangedSubview(autoGroupsBox)
        autoGroupsBox.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // Sensor history: toggle + clear grouped in one card with a separator
        // between the rows (same idiom as the doorbell group in Cameras).
        let historyBox = createCardBox()
        let historyStack = NSStackView()
        historyStack.orientation = .vertical
        historyStack.spacing = 0
        historyStack.alignment = .leading
        historyStack.translatesAutoresizingMaskIntoConstraints = false

        historySwitch.controlSize = .mini
        historySwitch.target = self
        historySwitch.action = #selector(historySwitchChanged(_:))
        let historyRow = createSettingRow(
            label: String(localized: "settings.advanced.history", defaultValue: "Record sensor history", bundle: .macOSBridge),
            badge: historyProBadge,
            subtitle: String(localized: "settings.advanced.history_subtitle", defaultValue: "Keeps 30 days of temperature, humidity and sensor changes. Hover a sensor in the menu to see its chart.", bundle: .macOSBridge),
            control: historySwitch
        )
        historyStack.addArrangedSubview(historyRow)
        historyRow.widthAnchor.constraint(equalTo: historyStack.widthAnchor).isActive = true
        // The two-line footnote fills its fixed-height row, leaving its last
        // line glued to the separator - give the hairline air above it.
        historyStack.setCustomSpacing(8, after: historyRow)

        let historySeparator = createSeparator()
        historyStack.addArrangedSubview(historySeparator)
        historySeparator.widthAnchor.constraint(equalTo: historyStack.widthAnchor).isActive = true

        let clearButton = NSButton(
            title: String(localized: "settings.advanced.history_clear", defaultValue: "Clear history", bundle: .macOSBridge),
            target: self, action: #selector(clearHistory))
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        let clearRow = createSettingRow(
            label: String(localized: "settings.advanced.history_clear_label", defaultValue: "Stored history", bundle: .macOSBridge),
            control: clearButton
        )
        historyStack.addArrangedSubview(clearRow)
        clearRow.widthAnchor.constraint(equalTo: historyStack.widthAnchor).isActive = true

        addContentToBox(historyBox, content: historyStack, verticalInset: 4)
        stackView.addArrangedSubview(historyBox)
        historyBox.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    /// A small "PRO" chip shown next to a Pro-gated row's label while the
    /// user is on the free tier, matching the sidebar's section badge.
    private static func createProChip() -> NSView {
        let chip = NSView()
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.wantsLayer = true
        chip.layer?.backgroundColor = NSColor.systemBlue.cgColor
        chip.layer?.cornerRadius = 3

        let label = NSTextField(labelWithString: "PRO")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 8, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        chip.addSubview(label)

        NSLayoutConstraint.activate([
            chip.widthAnchor.constraint(equalToConstant: 28),
            chip.heightAnchor.constraint(equalToConstant: 14),
            label.centerXAnchor.constraint(equalTo: chip.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: chip.centerYAnchor)
        ])
        return chip
    }

    private func createSettingRow(label: String, badge: NSView? = nil, subtitle: String? = nil, control: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let labelStack = NSStackView()
        labelStack.orientation = .vertical
        labelStack.spacing = 2
        labelStack.alignment = .leading
        labelStack.translatesAutoresizingMaskIntoConstraints = false

        let labelField = createLabel(label, style: .body)
        if let badge = badge {
            let labelLine = NSStackView(views: [labelField, badge])
            labelLine.orientation = .horizontal
            labelLine.spacing = 6
            labelLine.alignment = .centerY
            labelStack.addArrangedSubview(labelLine)
        } else {
            labelStack.addArrangedSubview(labelField)
        }

        if let subtitle = subtitle {
            let subtitleField = createLabel(subtitle, style: .caption)
            subtitleField.lineBreakMode = .byWordWrapping
            subtitleField.maximumNumberOfLines = 2
            subtitleField.cell?.wraps = true
            subtitleField.cell?.isScrollable = false
            // Let the field shrink below its single-line width so long text wraps
            // instead of widening the (fixed-width) settings window.
            subtitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            subtitleField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            labelStack.addArrangedSubview(subtitleField)
        }

        control.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(labelStack)
        container.addSubview(control)

        let rowHeight: CGFloat = subtitle != nil ? 56 : 36

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: rowHeight),
            labelStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            labelStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            labelStack.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -16),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func loadPreferences() {
        switch PreferencesManager.shared.temperatureUnit {
        case "celsius": temperaturePopUp.selectItem(at: 1)
        case "fahrenheit": temperaturePopUp.selectItem(at: 2)
        default: temperaturePopUp.selectItem(at: 0)
        }
        simpleLightSwitch.state = PreferencesManager.shared.simpleLightControls ? .on : .off
        sensorSummarySwitch.state = PreferencesManager.shared.sensorSummary ? .on : .off
        autoGroupsSwitch.state = PreferencesManager.shared.autoGroupsEnabled ? .on : .off
        historySwitch.state = PreferencesManager.shared.historyEnabled ? .on : .off
        // History is a Pro feature; disable (not hide) the switch for free
        // users so it can't look functional while the store refuses to record.
        historySwitch.isEnabled = ProStatusCache.shared.isPro
        historyProBadge.isHidden = ProStatusCache.shared.isPro
        loadMenuBarClimatePreferences()
    }

    private func loadMenuBarClimatePreferences() {
        // A live data/preference notification must not replace the menu's
        // items while AppKit is tracking a click, keyboard or scroll gesture.
        guard !isSelectingSensor else { return }
        let preferences = PreferencesManager.shared
        menuBarClimateSwitch.state = preferences.menuBarClimateEnabled ? .on : .off
        menuBarClimateSwitch.isEnabled = menuData != nil
        configureSensorPopUp(menuBarTemperaturePopUp, reading: .temperature, selectedId: preferences.menuBarTemperatureSensorId)
        configureSensorPopUp(menuBarHumidityPopUp, reading: .humidity, selectedId: preferences.menuBarHumiditySensorId)
    }

    private func configureSensorPopUp(_ popUp: NSPopUpButton, reading: MenuBarClimateDisplay.Reading, selectedId: String?) {
        var options: [(id: String?, title: String)] = [
            (nil, String(localized: "settings.advanced.menu_bar_sensor_none", defaultValue: "None", bundle: .macOSBridge))
        ]
        for source in reading == .temperature ? temperatureSources : humiditySources {
            options.append((source.serviceId, source.title))
        }
        if let selectedId, !options.contains(where: { $0.id == selectedId }) {
            options.append((selectedId, String(localized: "settings.advanced.menu_bar_sensor_unavailable", defaultValue: "Unavailable sensor", bundle: .macOSBridge)))
        }
        let unchanged = popUp.numberOfItems == options.count && zip(popUp.itemArray, options).allSatisfy {
            ($0.0.representedObject as? String) == $0.1.id && $0.0.title == $0.1.title
        }
        if !unchanged {
            popUp.removeAllItems()
            for option in options {
                // Explicit items preserve duplicate names. Disable automatic
                // validation: these options intentionally have no menu action;
                // the pop-up button sends its own selection action.
                let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
                item.representedObject = option.id
                popUp.menu?.addItem(item)
            }
        }
        popUp.selectItem(at: options.firstIndex(where: { $0.id == selectedId }) ?? 0)
        popUp.isEnabled = menuData != nil && PreferencesManager.shared.menuBarClimateEnabled
    }

    func menuWillOpen(_ menu: NSMenu) {
        isSelectingSensor = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isSelectingSensor = false
        // AppKit finishes sending the selected item's action after closing.
        DispatchQueue.main.async { [weak self] in self?.loadMenuBarClimatePreferences() }
    }

    private func setupBindings() {
        NotificationCenter.default.publisher(for: PreferencesManager.preferencesChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadMenuBarClimatePreferences() }
            .store(in: &cancellables)
        // The section is cached for the window's lifetime, so the Pro gate
        // must track purchases made after this pane was first shown.
        ProStatusCache.effectiveStatus(on: ProManager.shared.$isPro)
            .sink { [weak self] isPro in
                self?.historySwitch.isEnabled = isPro
                self?.historyProBadge.isHidden = isPro
            }
            .store(in: &cancellables)
    }

    @objc private func temperatureUnitChanged(_ sender: NSPopUpButton) {
        let values = ["system", "celsius", "fahrenheit"]
        PreferencesManager.shared.temperatureUnit = values[sender.indexOfSelectedItem]
    }

    @objc private func menuBarClimateChanged(_ sender: NSSwitch) {
        PreferencesManager.shared.menuBarClimateEnabled = sender.state == .on
    }

    @objc private func menuBarTemperatureChanged(_ sender: NSPopUpButton) {
        PreferencesManager.shared.menuBarTemperatureSensorId = sender.selectedItem?.representedObject as? String
    }

    @objc private func menuBarHumidityChanged(_ sender: NSPopUpButton) {
        PreferencesManager.shared.menuBarHumiditySensorId = sender.selectedItem?.representedObject as? String
    }

    @objc private func simpleLightSwitchChanged(_ sender: NSSwitch) {
        PreferencesManager.shared.simpleLightControls = sender.state == .on
    }

    @objc private func sensorSummarySwitchChanged(_ sender: NSSwitch) {
        PreferencesManager.shared.sensorSummary = sender.state == .on
    }

    @objc private func autoGroupsSwitchChanged(_ sender: NSSwitch) {
        PreferencesManager.shared.autoGroupsEnabled = sender.state == .on
    }

    @objc private func historySwitchChanged(_ sender: NSSwitch) {
        PreferencesManager.shared.historyEnabled = sender.state == .on
    }

    @objc private func clearHistory() {
        HistoryStore.shared.clearAll()
    }
}
