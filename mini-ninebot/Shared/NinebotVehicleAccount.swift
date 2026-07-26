import Foundation

/// Which account a vehicle belongs to, as an identity rather than a label.
///
/// The vehicle picker used to group by the *displayed* title — a Chinese string
/// like "13800138000 账号". So the grouping key, the `Identifiable` id and the
/// on-screen text were all the same value: rewording "账号" silently changed
/// which vehicles grouped together, and two groups that happened to render
/// alike would have collided in SwiftUI's diff.
enum NinebotVehicleAccount: Hashable {
    /// The payload identified the owning account (phone, uid, …).
    case identified(String)
    /// No account field in the payload; falling back to the signed-in phone.
    case boundPhone(String)
    /// Nothing to identify it by.
    case current

    /// ASCII and stable across any rewording — safe as a list identity.
    var id: String {
        switch self {
        case .identified(let value): return "identified:\(value)"
        case .boundPhone(let phone): return "phone:\(phone)"
        case .current: return "current"
        }
    }

    /// Payload keys that name the owning account, in priority order. The server
    /// is inconsistent about which one it sends, and about snake vs camel case.
    static let accountKeys = [
        "account",
        "account_id",
        "accountId",
        "phone",
        "mobile",
        "user_phone",
        "userPhone",
        "owner_phone",
        "ownerPhone",
        "bind_phone",
        "bindPhone",
        "user_id",
        "userId",
        "business_uid",
        "businessUID",
        "uid",
        "uuid"
    ]

    /// - Parameter boundPhone: the signed-in phone number, or nil when no
    ///   account is bound. Do not pass placeholder wording here.
    init(vehicle: NinebotVehicleInfo, boundPhone: String?) {
        if let raw = vehicle.raw {
            for key in Self.accountKeys {
                if let value = raw[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    self = .identified(value)
                    return
                }
            }
        }
        let phone = boundPhone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self = phone.isEmpty ? .current : .boundPhone(phone)
    }
}
