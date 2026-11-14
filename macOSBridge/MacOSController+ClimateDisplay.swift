import AppKit

extension MacOSController {
    private func menuBarClimateSource(reading: MenuBarClimateDisplay.Reading) -> MenuBarClimateDisplay.Source? {
        guard let data = currentMenuData else { return nil }
        let preferences = PreferencesManager.shared
        let selectedId = reading == .temperature
            ? preferences.menuBarTemperatureSensorId : preferences.menuBarHumiditySensorId
        return MenuBarClimateDisplay.sources(in: data, reading: reading).first { $0.serviceId == selectedId }
    }

    func refreshMenuBarClimateSources() {
        menuBarTemperatureSource = menuBarClimateSource(reading: .temperature)
        menuBarHumiditySource = menuBarClimateSource(reading: .humidity)
        updateMenuBarClimateDisplay()
        guard PreferencesManager.shared.menuBarClimateEnabled else { return }
        for source in [menuBarTemperatureSource, menuBarHumiditySource].compactMap({ $0 }) {
            readCharacteristic(identifier: source.characteristicId)
        }
    }

    /// Called before the menu-closed guard so the title remains live at idle.
    func updateMenuBarClimateDisplay(for characteristicId: UUID? = nil) {
        guard let button = statusItem.button else { return }
        guard PreferencesManager.shared.menuBarClimateEnabled else {
            guard characteristicId == nil else { return }
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = nil
            button.setAccessibilityValue("")
            statusItem.length = NSStatusItem.squareLength
            return
        }

        let temperatureSource = menuBarTemperatureSource
        let humiditySource = menuBarHumiditySource
        if let characteristicId,
           characteristicId != temperatureSource?.characteristicId,
           characteristicId != humiditySource?.characteristicId { return }

        func value(_ source: MenuBarClimateDisplay.Source?) -> Double? {
            guard let source else { return nil }
            return getCharacteristicValue(identifier: source.characteristicId).flatMap(ValueConversion.toDouble)
        }
        let text = MenuBarClimateDisplay.text(
            temperature: value(temperatureSource), humidity: value(humiditySource),
            usesFahrenheit: TemperatureFormatter.usesFahrenheit
        )
        statusItem.length = NSStatusItem.variableLength
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.title = " " + text
        button.toolTip = ([text] + [temperatureSource?.title, humiditySource?.title].compactMap { $0 }).joined(separator: "\n")
        button.setAccessibilityValue(text)
    }
}
