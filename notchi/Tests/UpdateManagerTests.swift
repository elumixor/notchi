import Foundation
import Sparkle
import XCTest
@testable import notchi

@MainActor
final class UpdateManagerTests: XCTestCase {
    private let manager = UpdateManager.shared

    private let defaultCheckTimeout: TimeInterval = 60
    private var retainedStubs: [StubUpdateChecker] = []

    override func setUp() {
        super.setUp()
        manager.state = .idle
        manager.hasPendingUpdate = false
        manager.checkTimeout = defaultCheckTimeout
    }

    override func tearDown() {
        manager.finishUpdateSession()
        manager.state = .idle
        manager.hasPendingUpdate = false
        manager.checkTimeout = defaultCheckTimeout
        super.tearDown()
    }

    func testNoUpdateAbortErrorIsIgnored() {
        let error = NSError(domain: SUSparkleErrorDomain, code: UpdateManager.noUpdateErrorCode)

        XCTAssertTrue(UpdateManager.shouldIgnoreAbortError(error))
    }

    func testUpdateErrorUsesShortInlineLabel() {
        manager.updateError()

        guard case .error(let failure) = manager.state else {
            return XCTFail("Expected error state")
        }

        XCTAssertEqual(failure.label, "Try again")
    }

    func testBeginCheckingReplacesPreviousFailureState() {
        manager.updateError()

        manager.beginChecking()

        XCTAssertEqual(manager.state, .checking)
    }

    func testCheckForUpdatesDoesNotEnterCheckingUntilSparkleStartsOne() {
        let updater = StubUpdateChecker(canCheckForUpdates: true)
        retainedStubs.append(updater)
        manager.setUpdater(updater)

        manager.checkForUpdates()

        XCTAssertEqual(updater.checkCount, 1)
        XCTAssertEqual(
            manager.state,
            .idle,
            "Sparkle can silently no-op, so .checking must come from showUserInitiatedUpdateCheck"
        )

        manager.beginChecking()
        XCTAssertEqual(manager.state, .checking)
    }

    func testCheckForUpdatesIsNotForwardedWhenSparkleCannotCheck() {
        let updater = StubUpdateChecker(canCheckForUpdates: false)
        retainedStubs.append(updater)
        manager.setUpdater(updater)

        manager.checkForUpdates()

        XCTAssertEqual(updater.checkCount, 0)
        XCTAssertEqual(manager.state, .idle)
    }

    func testStalledCheckTimesOutBackToIdleAndCancelsSparkleSession() async {
        var cancellationCount = 0
        manager.checkTimeout = 0.1

        manager.beginChecking { cancellationCount += 1 }
        XCTAssertEqual(manager.state, .checking)

        try? await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(manager.state, .idle)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testTerminalOutcomeCancelsTheTimeoutSoStateIsNotReset() async {
        var cancellationCount = 0
        manager.checkTimeout = 0.1

        manager.beginChecking { cancellationCount += 1 }
        manager.updateFound(version: "9.9.9")

        try? await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(manager.state, .updateAvailable(version: "9.9.9"))
        XCTAssertEqual(cancellationCount, 0)
    }

    func testTimeOutCheckingLeavesSettledStateAlone() {
        var cancellationCount = 0

        manager.beginChecking { cancellationCount += 1 }
        manager.noUpdateFound()
        manager.timeOutChecking()

        XCTAssertEqual(manager.state, .upToDate)
        XCTAssertEqual(cancellationCount, 0)
    }

    func testClearTransientStatusClearsUpToDateAndErrorStates() {
        manager.noUpdateFound()
        manager.clearTransientStatus()
        XCTAssertEqual(manager.state, .idle)

        manager.updateError()
        manager.clearTransientStatus()
        XCTAssertEqual(manager.state, .idle)
    }
}

@MainActor
private final class StubUpdateChecker: UpdateChecking {
    let canCheckForUpdates: Bool
    let sessionInProgress: Bool
    private(set) var checkCount = 0

    init(canCheckForUpdates: Bool, sessionInProgress: Bool = false) {
        self.canCheckForUpdates = canCheckForUpdates
        self.sessionInProgress = sessionInProgress
    }

    func checkForUpdates() {
        checkCount += 1
    }
}
