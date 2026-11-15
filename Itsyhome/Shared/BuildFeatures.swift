import Foundation

/// Shared by the Catalyst application and its native menu bar plugin.
public enum BuildFeatures {
    #if HOME_ASSISTANT_ONLY
    public static let isHomeAssistantOnly = true
    #else
    public static let isHomeAssistantOnly = false
    #endif
}
