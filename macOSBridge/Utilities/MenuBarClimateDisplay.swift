import Foundation

/// Sources and formatting shared by the main status item and its settings.
enum MenuBarClimateDisplay {
    enum Reading {
        case temperature
        case humidity

        var serviceType: String {
            self == .temperature ? ServiceTypes.temperatureSensor : ServiceTypes.humiditySensor
        }

        func characteristicId(from service: ServiceData) -> UUID? {
            let id = self == .temperature ? service.currentTemperatureId : service.humidityId
            return id.flatMap(UUID.init(uuidString:))
        }
    }

    struct Source {
        let serviceId: String
        let title: String
        let characteristicId: UUID
    }

    /// Include individual sensors even when the dropdown summarises them.
    static func sources(in data: MenuData, reading: Reading) -> [Source] {
        let rooms = Dictionary(data.rooms.map { ($0.uniqueIdentifier, $0.name) }, uniquingKeysWith: { first, _ in first })
        return data.accessories.flatMap(\.services).compactMap { service -> Source? in
            guard service.serviceType == reading.serviceType,
                  let id = reading.characteristicId(from: service) else { return nil }
            let room = service.roomIdentifier.flatMap { rooms[$0] }
            let name = room.map { "\(service.name) – \($0)" } ?? service.name
            // HA entity IDs distinguish identically named sensors in an area.
            let title = service.haEntityId.map { "\(name) (\($0))" } ?? name
            return Source(serviceId: service.uniqueIdentifier, title: title, characteristicId: id)
        }.sorted {
            if $0.title == $1.title { return $0.serviceId < $1.serviceId }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    static func text(temperature: Double?, humidity: Double?, usesFahrenheit: Bool) -> String {
        let unit = usesFahrenheit ? "°F" : "°C"
        let temperatureText: String
        if let temperature, temperature.isFinite {
            let value = usesFahrenheit ? temperature * 9 / 5 + 32 : temperature
            temperatureText = value.isFinite ? String(format: "%.1f", value) + unit : "--" + unit
        } else {
            temperatureText = "--" + unit
        }
        let humidityText: String
        if let humidity, humidity.isFinite, (0...100).contains(humidity) {
            humidityText = String(format: "%.0f%%", humidity)
        } else {
            humidityText = "--%"
        }
        return "\(temperatureText) · \(humidityText)"
    }
}
