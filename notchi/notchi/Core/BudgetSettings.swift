import Foundation

/// User-configured spend budget for plans whose real limit is not exposed by any
/// API (for example a work account with a fixed monthly dollar allowance). The
/// app cannot read the true balance, so the user calibrates it manually and the
/// tracker adds locally computed cost on top of that anchor.
enum BudgetSettings {
    static let enabledKey = "budgetEnabled"
    static let limitUSDKey = "budgetLimitUSD"
    static let resetDayKey = "budgetResetDay"
    static let anchorAmountUSDKey = "budgetAnchorAmountUSD"
    static let anchorDayKey = "budgetAnchorDay"
    static let anchorDayCostUSDKey = "budgetAnchorDayCostUSD"
    static let anchorSetAtKey = "budgetAnchorSetAt"
    static let prefersReportedSpendKey = "budgetPrefersReportedSpend"
    static let showsLimitKey = "budgetShowsLimit"

    static let defaultLimitUSD: Double = 100
    static let defaultResetDay = 1

    /// Reset days above 28 do not exist in every month, so they are not offered.
    static let maxResetDay = 28

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            enabledKey: true,
            limitUSDKey: defaultLimitUSD,
            resetDayKey: defaultResetDay,
            prefersReportedSpendKey: false,
            showsLimitKey: true,
        ])
    }

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Whether to trust the provider's own extra-usage figures over the locally
    /// computed cost. Off by default: the figure is meaningful only for an
    /// account whose whole allowance is the extra-usage pool, and only the user
    /// knows whether theirs is.
    static var prefersReportedSpend: Bool {
        get { UserDefaults.standard.object(forKey: prefersReportedSpendKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: prefersReportedSpendKey) }
    }

    /// Whether the notch compares spend against the limit ("$12 / $100", coloured
    /// by pace) or just shows the spend on its own, for plans with no dollar cap.
    static var showsLimit: Bool {
        get { UserDefaults.standard.object(forKey: showsLimitKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showsLimitKey) }
    }

    static var limitUSD: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: limitUSDKey) as? Double ?? defaultLimitUSD
            return stored > 0 ? stored : defaultLimitUSD
        }
        set { UserDefaults.standard.set(max(newValue, 0.01), forKey: limitUSDKey) }
    }

    static var resetDay: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: resetDayKey) as? Int ?? defaultResetDay
            return min(max(stored, 1), maxResetDay)
        }
        set { UserDefaults.standard.set(min(max(newValue, 1), maxResetDay), forKey: resetDayKey) }
    }

    /// The spend the user reported at calibration time.
    static var anchorAmountUSD: Double {
        get { UserDefaults.standard.object(forKey: anchorAmountUSDKey) as? Double ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: anchorAmountUSDKey) }
    }

    /// Day key (`yyyy-MM-dd`) the calibration happened on, or empty when never calibrated.
    static var anchorDay: String {
        get { UserDefaults.standard.string(forKey: anchorDayKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: anchorDayKey) }
    }

    /// Locally computed cost already accumulated on the anchor day at calibration
    /// time. Day buckets have no finer granularity, so this is what makes a
    /// mid-day calibration exact.
    static var anchorDayCostUSD: Double {
        get { UserDefaults.standard.object(forKey: anchorDayCostUSDKey) as? Double ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: anchorDayCostUSDKey) }
    }

    static var anchorSetAt: Date? {
        get { UserDefaults.standard.object(forKey: anchorSetAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: anchorSetAtKey) }
    }

    static func calibrate(amountUSD: Double, dayKey: String, dayCostUSD: Double, at date: Date = Date()) {
        anchorAmountUSD = max(amountUSD, 0)
        anchorDay = dayKey
        anchorDayCostUSD = dayCostUSD
        anchorSetAt = date
    }

    static func clearCalibration() {
        anchorAmountUSD = 0
        anchorDay = ""
        anchorDayCostUSD = 0
        anchorSetAt = nil
    }
}
