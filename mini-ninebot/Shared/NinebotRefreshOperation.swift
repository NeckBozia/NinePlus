import Foundation

/// What a recorded refresh event was doing, as an ASCII identity.
///
/// `NinebotRefreshEvent.operation` used to be the Chinese loading message,
/// written straight into `UserDefaults` — including `NinebotLoadingOperation`'s
/// display text, the very enum that was extracted to stop wording from driving
/// behaviour. That welded the display wording to the persisted format: editing
/// a label changed the data on disk.
///
/// The vocabulary lives here in Shared because both the app and the widget
/// extension record events, and neither can see the other's types. Each side
/// maps its own enum into these cases; the wording lives in the diagnostics
/// view.
enum NinebotRefreshOperation: Equatable, Hashable {
    case testConnection
    /// Refreshing the dashboard. Covers both the pull-to-refresh path and the
    /// Shortcut that does the same thing.
    case dashboard
    case batteryQuery
    case locationQuery
    case addressResolve
    case batteryChemistryUpdate(String?)
    /// - Parameter month: `yyyyMM`, kept so diagnostics can still say which one.
    case travelMonthSync(String?)
    case chargingNotificationsEnable
    case pushTokenSync
    case login
    case bell
    case openBucket
    case engineStart
    case engineStop
    /// The widget rebuilding its timeline.
    case widgetTimeline
    case backgroundRefresh
    /// A code this build does not know — including the Chinese text written by
    /// builds from before this type existed. Kept so old records still display
    /// instead of failing to decode and vanishing from the diagnostics page.
    case legacy(String)

    /// Separates a case from its payload. Not a character any case name or
    /// `yyyyMM` month contains.
    static let payloadSeparator = ":"

    var code: String {
        switch self {
        case .testConnection: return "test_connection"
        case .dashboard: return "dashboard"
        case .batteryQuery: return "battery_query"
        case .locationQuery: return "location_query"
        case .addressResolve: return "address_resolve"
        case .batteryChemistryUpdate(let chemistry):
            return Self.join("battery_chemistry_update", chemistry)
        case .travelMonthSync(let month):
            return Self.join("travel_month_sync", month)
        case .chargingNotificationsEnable: return "charging_notifications_enable"
        case .pushTokenSync: return "push_token_sync"
        case .login: return "login"
        case .bell: return "bell"
        case .openBucket: return "open_bucket"
        case .engineStart: return "engine_start"
        case .engineStop: return "engine_stop"
        case .widgetTimeline: return "widget_timeline"
        case .backgroundRefresh: return "background_refresh"
        case .legacy(let raw): return raw
        }
    }

    init(code: String) {
        let name: String
        let payload: String?
        if let index = code.firstIndex(of: Character(Self.payloadSeparator)) {
            name = String(code[code.startIndex..<index])
            payload = String(code[code.index(after: index)...])
        } else {
            name = code
            payload = nil
        }

        switch name {
        case "test_connection": self = .testConnection
        case "dashboard": self = .dashboard
        case "battery_query": self = .batteryQuery
        case "location_query": self = .locationQuery
        case "address_resolve": self = .addressResolve
        case "battery_chemistry_update": self = .batteryChemistryUpdate(payload)
        case "travel_month_sync": self = .travelMonthSync(payload)
        case "charging_notifications_enable": self = .chargingNotificationsEnable
        case "push_token_sync": self = .pushTokenSync
        case "login": self = .login
        case "bell": self = .bell
        case "open_bucket": self = .openBucket
        case "engine_start": self = .engineStart
        case "engine_stop": self = .engineStop
        case "widget_timeline": self = .widgetTimeline
        case "background_refresh": self = .backgroundRefresh
        default: self = .legacy(code)
        }
    }

    private static func join(_ name: String, _ payload: String?) -> String {
        guard let payload, !payload.isEmpty else { return name }
        return name + payloadSeparator + payload
    }
}

extension NinebotRefreshOperation: Codable {
    init(from decoder: Decoder) throws {
        let code = try decoder.singleValueContainer().decode(String.self)
        self.init(code: code)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }
}

/// Which process recorded the event. ASCII already, but naming it keeps the
/// three literals from drifting apart across three files.
enum NinebotRefreshSource: String, Codable, Equatable, CaseIterable {
    case app = "App"
    case widget = "Widget"
    case shortcut = "Shortcut"
    case background = "Background"
}
