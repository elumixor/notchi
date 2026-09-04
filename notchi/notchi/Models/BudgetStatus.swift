import Foundation

/// Where the current spend sits against the budget, relative to how much of the
/// period has elapsed.
nonisolated enum BudgetPace: Equatable, Sendable {
    /// Spending slower than an even burn of the budget.
    case under
    /// Spending faster than an even burn, but still inside the budget.
    case ahead
    /// Budget exhausted.
    case over
}

nonisolated struct BudgetStatus: Equatable, Sendable {
    let spentUSD: Double
    let limitUSD: Double
    let periodStart: Date
    let periodEnd: Date
    let daysInPeriod: Int
    /// 1-based index of today inside the period.
    let dayIndex: Int
    /// True when the period started earlier than the scanned cost window, so the
    /// spend figure can only be a lower bound unless the user has calibrated.
    let isTruncated: Bool

    var remainingUSD: Double { limitUSD - spentUSD }
    var fractionUsed: Double { limitUSD > 0 ? spentUSD / limitUSD : 0 }
    var daysRemaining: Int { max(daysInPeriod - dayIndex, 0) }

    /// What an even burn would have spent by the end of today.
    var expectedByNowUSD: Double {
        guard daysInPeriod > 0 else { return 0 }
        return limitUSD * Double(dayIndex) / Double(daysInPeriod)
    }

    /// Even-burn allowance per day for the whole period.
    var dailyAllowanceUSD: Double {
        guard daysInPeriod > 0 else { return 0 }
        return limitUSD / Double(daysInPeriod)
    }

    /// What is left, spread over the days that are left (today included).
    var remainingPerDayUSD: Double {
        let daysLeft = max(daysInPeriod - dayIndex + 1, 1)
        return max(remainingUSD, 0) / Double(daysLeft)
    }

    var averagePerDayUSD: Double {
        dayIndex > 0 ? spentUSD / Double(dayIndex) : 0
    }

    /// Period total if the current average per day continues.
    var projectedTotalUSD: Double {
        averagePerDayUSD * Double(daysInPeriod)
    }

    var pace: BudgetPace {
        if spentUSD >= limitUSD { return .over }
        return spentUSD > expectedByNowUSD ? .ahead : .under
    }

    static func make(
        buckets: DayModelBuckets,
        limitUSD: Double,
        resetDay: Int,
        anchorAmountUSD: Double,
        anchorDay: String,
        anchorDayCostUSD: Double,
        oldestScannedDay: String?,
        now: Date,
        calendar: Calendar) -> BudgetStatus
    {
        let today = calendar.startOfDay(for: now)
        let periodStart = periodStart(for: today, resetDay: resetDay, calendar: calendar)
        let periodEnd = calendar.date(byAdding: .month, value: 1, to: periodStart) ?? today
        let daysInPeriod = calendar.dateComponents([.day], from: periodStart, to: periodEnd).day ?? 30
        let dayIndex = (calendar.dateComponents([.day], from: periodStart, to: today).day ?? 0) + 1

        let periodStartKey = DailyCostReport.dayKey(periodStart, calendar: calendar)
        let costs = dailyCosts(from: buckets)

        let spent: Double
        if !anchorDay.isEmpty, anchorDay >= periodStartKey {
            // Calibration inside the current period: trust the reported figure and
            // add only what accumulated after it.
            let sameDayDelta = max((costs[anchorDay] ?? 0) - anchorDayCostUSD, 0)
            let laterDays = costs
                .filter { $0.key > anchorDay }
                .values
                .reduce(0, +)
            spent = anchorAmountUSD + sameDayDelta + laterDays
        } else {
            spent = costs
                .filter { $0.key >= periodStartKey }
                .values
                .reduce(0, +)
        }

        let truncated: Bool
        if !anchorDay.isEmpty, anchorDay >= periodStartKey {
            truncated = false
        } else if let oldest = oldestScannedDay {
            truncated = oldest > periodStartKey
        } else {
            truncated = false
        }

        return BudgetStatus(
            spentUSD: spent,
            limitUSD: limitUSD,
            periodStart: periodStart,
            periodEnd: periodEnd,
            daysInPeriod: daysInPeriod,
            dayIndex: dayIndex,
            isTruncated: truncated)
    }

    static func dailyCosts(from buckets: DayModelBuckets) -> [String: Double] {
        buckets.mapValues { models in
            models.values.reduce(0) { $0 + $1.costUSD }
        }
    }

    static func periodStart(for today: Date, resetDay: Int, calendar: Calendar) -> Date {
        let clampedResetDay = min(max(resetDay, 1), BudgetSettings.maxResetDay)
        var components = calendar.dateComponents([.year, .month, .day], from: today)
        let currentDay = components.day ?? 1
        components.day = clampedResetDay
        guard let candidate = calendar.date(from: components) else { return today }
        if currentDay >= clampedResetDay { return calendar.startOfDay(for: candidate) }
        let previous = calendar.date(byAdding: .month, value: -1, to: candidate) ?? candidate
        return calendar.startOfDay(for: previous)
    }
}
