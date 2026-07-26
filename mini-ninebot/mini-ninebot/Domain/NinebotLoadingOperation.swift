import Foundation

/// What the view model is currently busy with.
///
/// This replaces matching on the Chinese loading message. The dashboard used to
/// decide whether to show its pull-to-refresh indicator with
/// `message.contains("刷新车况")`, which meant editing a single character of
/// user-facing wording silently broke the spinner with nothing to catch it.
enum NinebotLoadingOperation: Equatable {
    case testConnection
    case refreshDashboard
    case updateBatteryChemistry(NinebotBatteryChemistry)
    /// - Parameter month: raw `yyyyMM`. Keeping it unformatted is what lets
    ///   `refreshOperation` persist it without dragging Chinese onto disk.
    case syncTravelMonth(month: String)
    case resolveAddresses
    case enableChargingNotifications
    case syncPushDeviceToken
    case login
    case vehicleAction(NinebotVehicleAction)

    /// The text shown while this operation runs, and the label recorded in the
    /// diagnostics log.
    var message: String {
        switch self {
        case .testConnection:
            return "正在测试连接"
        case .refreshDashboard:
            return "正在刷新车况"
        case .updateBatteryChemistry:
            return "正在更新电池类型"
        case .syncTravelMonth(let month):
            return "正在获取 \(Self.displayMonth(month)) 行程"
        case .resolveAddresses:
            return "正在解析车辆位置"
        case .enableChargingNotifications:
            return "正在开启充电通知"
        case .syncPushDeviceToken:
            return "正在上报设备 Token"
        case .login:
            return "正在密码登录"
        case .vehicleAction(let action):
            return action.loadingTitle
        }
    }

    /// `yyyyMM` as a person reads it. Lives here rather than on the view model
    /// so the enum can carry the raw month and still produce its own wording.
    static func displayMonth(_ month: String) -> String {
        guard month.count == 6 else { return month }
        return "\(month.prefix(4))年\(month.suffix(2))月"
    }

    /// Whether the dashboard's pull-to-refresh indicator should be showing.
    ///
    /// Only the two operations that actually refresh what the dashboard
    /// displays qualify. Sending a vehicle command also refreshes afterwards,
    /// but it has its own loading strip, so showing both would double up.
    var showsDashboardRefreshIndicator: Bool {
        switch self {
        case .refreshDashboard, .resolveAddresses:
            return true
        case .testConnection, .updateBatteryChemistry, .syncTravelMonth,
             .enableChargingNotifications, .syncPushDeviceToken, .login, .vehicleAction:
            return false
        }
    }
}

extension NinebotLoadingOperation {
    /// The ASCII identity recorded in the diagnostics log.
    ///
    /// Deliberately separate from `message`: that one is wording and may be
    /// reworded freely, this one is a persisted value and must not change.
    var refreshOperation: NinebotRefreshOperation {
        switch self {
        case .testConnection: return .testConnection
        case .refreshDashboard: return .dashboard
        case .updateBatteryChemistry(let chemistry): return .batteryChemistryUpdate(chemistry.rawValue)
        case .syncTravelMonth(let month): return .travelMonthSync(month)
        case .resolveAddresses: return .addressResolve
        case .enableChargingNotifications: return .chargingNotificationsEnable
        case .syncPushDeviceToken: return .pushTokenSync
        case .login: return .login
        case .vehicleAction(let action): return action.refreshOperation
        }
    }
}

extension NinebotVehicleAction {
    var refreshOperation: NinebotRefreshOperation {
        switch self {
        case .bell: return .bell
        case .openBucket: return .openBucket
        case .engineStart: return .engineStart
        case .engineStop: return .engineStop
        }
    }
}
