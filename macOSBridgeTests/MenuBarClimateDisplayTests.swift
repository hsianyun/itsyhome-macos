import XCTest
@testable import macOSBridge

final class MenuBarClimateDisplayTests: XCTestCase {
    func testCombinedCelsiusAndFahrenheitReadings() {
        XCTAssertEqual(MenuBarClimateDisplay.text(temperature: 21.5, humidity: 45, usesFahrenheit: false), "21.5°C · 45%")
        XCTAssertEqual(MenuBarClimateDisplay.text(temperature: 20, humidity: 45, usesFahrenheit: true), "68.0°F · 45%")
        XCTAssertEqual(MenuBarClimateDisplay.text(temperature: -10, humidity: 0, usesFahrenheit: false), "-10.0°C · 0%")
    }

    func testUnavailableReadingsAreIndependent() {
        XCTAssertEqual(MenuBarClimateDisplay.text(temperature: nil, humidity: 45, usesFahrenheit: false), "--°C · 45%")
        XCTAssertEqual(MenuBarClimateDisplay.text(temperature: 20, humidity: nil, usesFahrenheit: true), "68.0°F · --%")
        XCTAssertEqual(MenuBarClimateDisplay.text(temperature: nil, humidity: nil, usesFahrenheit: true), "--°F · --%")
    }

    func testNonFiniteAndInvalidHumidityReadingsUsePlaceholders() {
        for temperature in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(MenuBarClimateDisplay.text(temperature: temperature, humidity: 50, usesFahrenheit: false), "--°C · 50%")
        }
        for humidity in [Double.nan, .infinity, -1, 101] {
            XCTAssertEqual(MenuBarClimateDisplay.text(temperature: 20, humidity: humidity, usesFahrenheit: false), "20.0°C · --%")
        }
    }

    func testSourcesKeepDuplicateNamesAndRouteEachReading() {
        let room = RoomData(uniqueIdentifier: UUID(), name: "Bedroom")
        let temperatureId = UUID()
        let humidityId = UUID()
        let temperature = ServiceData(
            uniqueIdentifier: UUID(), name: "Room sensor", serviceType: ServiceTypes.temperatureSensor,
            accessoryName: "Room sensor", roomIdentifier: UUID(uuidString: room.uniqueIdentifier),
            currentTemperatureId: temperatureId
        )
        let secondTemperature = ServiceData(
            uniqueIdentifier: UUID(), name: "Room sensor", serviceType: ServiceTypes.temperatureSensor,
            accessoryName: "Room sensor", roomIdentifier: UUID(uuidString: room.uniqueIdentifier),
            currentTemperatureId: UUID()
        )
        let humidity = ServiceData(
            uniqueIdentifier: UUID(), name: "Room sensor", serviceType: ServiceTypes.humiditySensor,
            accessoryName: "Room sensor", roomIdentifier: UUID(uuidString: room.uniqueIdentifier),
            humidityId: humidityId
        )
        let data = MenuData(homes: [], rooms: [room], accessories: [
            AccessoryData(uniqueIdentifier: UUID(), name: "Sensors", roomIdentifier: nil,
                          services: [humidity, secondTemperature, temperature], isReachable: true)
        ], scenes: [], selectedHomeId: nil)
        let temperatures = MenuBarClimateDisplay.sources(in: data, reading: .temperature)
        XCTAssertEqual(temperatures.count, 2)
        XCTAssertEqual(temperatures.first { $0.serviceId == temperature.uniqueIdentifier }?.characteristicId, temperatureId)
        XCTAssertTrue(temperatures.allSatisfy { $0.title.contains("Bedroom") })
        XCTAssertEqual(MenuBarClimateDisplay.sources(in: data, reading: .humidity).map(\.characteristicId), [humidityId])
    }
}
