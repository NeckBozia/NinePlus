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
    case syncTravelMonth(String)
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
        case .syncTravelMonth(let displayMonth):
            return "正在获取 \(displayMonth) 行程"
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
