import XCTest
@testable import notchi

final class BudgetStatusTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func buckets(_ costsByDay: [String: Double]) -> DayModelBuckets {
        costsByDay.mapValues { cost in
            ["claude-opus-4": ModelTokenTotals(costNanos: Int(cost * 1_000_000_000))]
        }
    }

    private func status(
        costsByDay: [String: Double],
        limitUSD: Double = 100,
        resetDay: Int = 1,
        anchorAmountUSD: Double = 0,
        anchorDay: String = "",
        anchorDayCostUSD: Double = 0,
        oldestScannedDay: String? = nil,
        now: Date) -> BudgetStatus
    {
        BudgetStatus.make(
            buckets: buckets(costsByDay),
            limitUSD: limitUSD,
            resetDay: resetDay,
            anchorAmountUSD: anchorAmountUSD,
            anchorDay: anchorDay,
            anchorDayCostUSD: anchorDayCostUSD,
            oldestScannedDay: oldestScannedDay,
            now: now,
            calendar: calendar)
    }

    func testPeriodStartsOnResetDayOfCurrentMonthWhenAlreadyPassed() {
        let start = BudgetStatus.periodStart(
            for: date(2026, 3, 17), resetDay: 5, calendar: calendar)
        XCTAssertEqual(start, date(2026, 3, 5))
    }

    func testPeriodStartsInPreviousMonthBeforeResetDay() {
        let start = BudgetStatus.periodStart(
            for: date(2026, 3, 2), resetDay: 5, calendar: calendar)
        XCTAssertEqual(start, date(2026, 2, 5))
    }

    func testUncalibratedSpendSumsDaysFromPeriodStart() {
        let result = status(
            costsByDay: [
                "2026-02-28": 9,   // previous period
                "2026-03-01": 4,
                "2026-03-02": 6,
            ],
            now: date(2026, 3, 2))
        XCTAssertEqual(result.spentUSD, 10, accuracy: 1e-9)
        XCTAssertEqual(result.dayIndex, 2)
        XCTAssertEqual(result.daysInPeriod, 31)
    }

    func testCalibrationAnchorsSpendAndAddsOnlyLaterCost() {
        // Calibrated at $40 on 3 March, when $5 had already accrued that day.
        let result = status(
            costsByDay: [
                "2026-03-01": 100,
                "2026-03-03": 7,
                "2026-03-04": 3,
            ],
            anchorAmountUSD: 40,
            anchorDay: "2026-03-03",
            anchorDayCostUSD: 5,
            now: date(2026, 3, 4))
        // 40 anchor + 2 remaining on the anchor day + 3 the day after.
        XCTAssertEqual(result.spentUSD, 45, accuracy: 1e-9)
        XCTAssertFalse(result.isTruncated)
    }

    func testCalibrationFromPreviousPeriodIsIgnored() {
        let result = status(
            costsByDay: ["2026-03-01": 12],
            anchorAmountUSD: 90,
            anchorDay: "2026-02-20",
            anchorDayCostUSD: 0,
            now: date(2026, 3, 1))
        XCTAssertEqual(result.spentUSD, 12, accuracy: 1e-9)
    }

    func testPaceIsUnderWhenBelowEvenBurn() {
        let result = status(
            costsByDay: ["2026-03-01": 1],
            now: date(2026, 3, 1))
        XCTAssertEqual(result.pace, .under)
        XCTAssertEqual(result.expectedByNowUSD, 100.0 / 31.0, accuracy: 1e-9)
    }

    func testPaceIsAheadWhenAboveEvenBurnButInsideLimit() {
        let result = status(
            costsByDay: ["2026-03-01": 20],
            now: date(2026, 3, 1))
        XCTAssertEqual(result.pace, .ahead)
    }

    func testPaceIsOverWhenLimitReached() {
        let result = status(
            costsByDay: ["2026-03-01": 120],
            now: date(2026, 3, 1))
        XCTAssertEqual(result.pace, .over)
        XCTAssertEqual(result.remainingUSD, -20, accuracy: 1e-9)
        XCTAssertEqual(result.remainingPerDayUSD, 0, accuracy: 1e-9)
    }

    func testProjectionExtrapolatesCurrentAverage() {
        let result = status(
            costsByDay: ["2026-03-01": 2, "2026-03-02": 4],
            now: date(2026, 3, 2))
        XCTAssertEqual(result.averagePerDayUSD, 3, accuracy: 1e-9)
        XCTAssertEqual(result.projectedTotalUSD, 93, accuracy: 1e-9)
    }

    func testReportedSpendOverridesLocalCostAndLimit() {
        let result = BudgetStatus.make(
            buckets: buckets(["2026-03-01": 12]),
            reportedSpend: .init(spentUSD: 40, limitUSD: 250),
            limitUSD: 100,
            resetDay: 1,
            anchorAmountUSD: 90,
            anchorDay: "2026-03-01",
            anchorDayCostUSD: 0,
            oldestScannedDay: "2026-03-01",
            now: date(2026, 3, 1),
            calendar: calendar)
        XCTAssertEqual(result.source, .reported)
        XCTAssertEqual(result.spentUSD, 40, accuracy: 1e-9)
        XCTAssertEqual(result.limitUSD, 250, accuracy: 1e-9)
        XCTAssertFalse(result.isTruncated)
    }

    func testSourceIsCalibratedWhenAnchorIsInPeriod() {
        let result = status(
            costsByDay: ["2026-03-02": 4],
            anchorAmountUSD: 10,
            anchorDay: "2026-03-01",
            now: date(2026, 3, 2))
        XCTAssertEqual(result.source, .calibrated)
    }

    func testSourceIsEstimatedWithoutAnchorOrReport() {
        let result = status(costsByDay: ["2026-03-01": 4], now: date(2026, 3, 1))
        XCTAssertEqual(result.source, .estimated)
    }

    func testTruncatedWhenScanWindowStartsAfterPeriodStart() {
        let result = status(
            costsByDay: ["2026-03-10": 5],
            oldestScannedDay: "2026-03-05",
            now: date(2026, 3, 10))
        XCTAssertTrue(result.isTruncated)
    }

    func testNotTruncatedWhenScanWindowCoversPeriodStart() {
        let result = status(
            costsByDay: ["2026-03-10": 5],
            oldestScannedDay: "2026-02-25",
            now: date(2026, 3, 10))
        XCTAssertFalse(result.isTruncated)
    }
}
