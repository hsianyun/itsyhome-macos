//
//  HomeAssistantPlatform+Delegate.swift
//  Itsyhome
//
//  HomeAssistantClientDelegate conformance
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.nickustinov.itsyhome", category: "HomeAssistantPlatform")

// MARK: - HomeAssistantClientDelegate

extension HomeAssistantPlatform: HomeAssistantClientDelegate {
    func clientDidConnect(_ client: HomeAssistantClient) {
        logger.info("Client connected")
    }

    func clientDidDisconnect(_ client: HomeAssistantClient, error: Error?) {
        logger.info("Client disconnected: \(error?.localizedDescription ?? "no error")")
        delegate?.platformDidDisconnect(self)
    }

    func client(_ client: HomeAssistantClient, didReceiveStateChange entityId: String, newState: HAEntityState, oldState: HAEntityState?) {
        logger.debug("State change: \(entityId, privacy: .public) -> \(newState.state)")

        // Update mapper
        mapper.updateState(newState)

        // Non-numeric sensor states produce no characteristic value. Notify the
        // status display explicitly so it does not retain the last good reading.
        if newState.domain == "sensor", newState.numericState?.isFinite != true {
            let characteristic: String?
            switch newState.deviceClass ?? oldState?.deviceClass {
            case "temperature": characteristic = "current_temp"
            case "humidity": characteristic = "humidity"
            default: characteristic = nil
            }
            if let characteristic {
                delegate?.platformDidInvalidateCharacteristic(
                    self, identifier: mapper.characteristicUUID(entityId, characteristic)
                )
            }
        }

        // Clear pending color writes now that HA has confirmed
        if newState.domain == "light" {
            pendingColorLock.withLock {
                pendingHue.removeValue(forKey: entityId)
                pendingSaturation.removeValue(forKey: entityId)
            }
        }

        // Notify delegate of characteristic changes
        let values = mapper.getCharacteristicValues(for: entityId)
        for (uuid, value) in values {
            delegate?.platformDidUpdateCharacteristic(self, identifier: uuid, value: value)
        }

        // Check for doorbell events
        if newState.domain == "event" && newState.deviceClass == "doorbell" {
            for cameraUUID in findAssociatedCameras(for: entityId) {
                delegate?.platformDidReceiveDoorbellEvent(self, cameraIdentifier: cameraUUID)
            }
        }

        // Check for motion events (binary_sensor with device_class "motion" turning on)
        if newState.domain == "binary_sensor" && newState.deviceClass == "motion" && newState.state == "on" {
            for cameraUUID in findAssociatedCameras(for: entityId) {
                delegate?.platformDidReceiveMotionEvent(self, cameraIdentifier: cameraUUID)
            }
        }
    }

    func client(_ client: HomeAssistantClient, didReceiveEvent event: HAEvent) {
        // HA removes an entity with new_state: null, which has no numeric
        // update. Keep a selected sensor unavailable until the next full reload.
        guard event.eventType == "state_changed", event.data["new_state"] is NSNull,
              let oldJSON = event.data["old_state"] as? [String: Any],
              let oldState = HAEntityState(json: oldJSON), oldState.domain == "sensor",
              oldState.deviceClass == "temperature" || oldState.deviceClass == "humidity",
              let unavailable = HAEntityState(json: [
                "entity_id": oldState.entityId, "state": "unavailable", "attributes": oldState.attributes
              ]) else { return }
        self.client(client, didReceiveStateChange: oldState.entityId, newState: unavailable, oldState: oldState)
    }

    func client(_ client: HomeAssistantClient, didEncounterError error: Error) {
        delegate?.platformDidEncounterError(self, message: error.localizedDescription)
    }

    private func findAssociatedCameras(for entityId: String) -> [UUID] {
        mapper.findCamerasOnSameDevice(as: entityId)
    }
}
