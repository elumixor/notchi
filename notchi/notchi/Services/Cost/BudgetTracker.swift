import Foundation
import Observation

/// Tracks locally computed Claude Code spend against a user-configured budget.
///
/// It keeps its own cost store rather than reusing `CostHistoryStore.shared`
/// because the dashboard window (30 days) is one day short of covering a full
/// calendar month, and a budget period must never silently drop its first day.
@MainActor
@Observable
final class BudgetTracker {
    static let shared = BudgetTracker()

    /// Long enough to cover any calendar month plus slack for a late reset day.
    static let windowDays = 40

    private(set) var status: BudgetStatus?

    private let costStore: CostHistoryStore
    private let calendar: Calendar
    private var timer: Timer?
    private let recomputeInterval: TimeInterval = 30

    init(costStore: CostHistoryStore? = nil, calendar: Calendar = .current) {
        self.costStore = costStore ?? Self.makeCostStore()
        self.calendar = calendar
    }

    private static func makeCostStore() -> CostHistoryStore {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let pricing = PricingCatalog(
            config: .claude, fallbackBundle: .main,
            snapshotURL: PricingCatalog.defaultSnapshotURL(for: .claude))
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent(".notchi")
        return CostHistoryStore(
            windowDays: windowDays,
            provider: .claude,
            pricing: pricing,
            projectsRoots: [home.appendingPathComponent(".claude/projects", isDirectory: true)],
            cacheURL: cacheRoot.appendingPathComponent("CostUsage/budget.json"))
    }

    func start() {
        guard timer == nil else { return }
        costStore.start()
        recompute()
        timer = Timer.scheduledTimer(withTimeInterval: recomputeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
    }

    func refresh() async {
        await costStore.refresh()
        recompute()
    }

    /// Cost accumulated today so far, used to anchor a mid-day calibration.
    var todayCostUSD: Double {
        BudgetStatus.dailyCosts(from: costStore.buckets)[todayKey] ?? 0
    }

    var todayKey: String {
        DailyCostReport.dayKey(Date(), calendar: calendar)
    }

    func calibrate(to amountUSD: Double) {
        BudgetSettings.calibrate(amountUSD: amountUSD, dayKey: todayKey, dayCostUSD: todayCostUSD)
        recompute()
    }

    func clearCalibration() {
        BudgetSettings.clearCalibration()
        recompute()
    }

    /// The earliest day the scanner could have seen, whether or not it had activity.
    private func oldestScannedDay(now: Date) -> String {
        let start = calendar.date(
            byAdding: .day, value: -(costStore.windowDays - 1),
            to: calendar.startOfDay(for: now)) ?? now
        return DailyCostReport.dayKey(start, calendar: calendar)
    }

    func recompute() {
        guard BudgetSettings.isEnabled else {
            status = nil
            return
        }
        let now = Date()
        status = BudgetStatus.make(
            buckets: costStore.buckets,
            limitUSD: BudgetSettings.limitUSD,
            resetDay: BudgetSettings.resetDay,
            anchorAmountUSD: BudgetSettings.anchorAmountUSD,
            anchorDay: BudgetSettings.anchorDay,
            anchorDayCostUSD: BudgetSettings.anchorDayCostUSD,
            oldestScannedDay: oldestScannedDay(now: now),
            now: now,
            calendar: calendar)
    }
}
