import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.ruban.notchi", category: "SessionResetNotifier")

/// Watches the subscription's five-hour window and says when it rolls over, so a
/// paused session can be resumed the moment tokens come back.
@MainActor
@Observable
final class SessionResetNotifier {
    static let shared = SessionResetNotifier()

    static let notifyOnResetKey = "sessionNotifyOnReset"
    static let notifyOnNearLimitKey = "sessionNotifyNearLimit"
    static let nearLimitPercent = 90

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            notifyOnResetKey: true,
            notifyOnNearLimitKey: true,
        ])
    }

    static var notifiesOnReset: Bool {
        get { UserDefaults.standard.object(forKey: notifyOnResetKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notifyOnResetKey) }
    }

    static var notifiesOnNearLimit: Bool {
        get { UserDefaults.standard.object(forKey: notifyOnNearLimitKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notifyOnNearLimitKey) }
    }

    /// When the window last rolled over, as observed by this app.
    private(set) var lastResetAt: Date?

    private let usageService: ClaudeUsageService
    private var timer: Timer?
    private let pollInterval: TimeInterval = 20
    private var lastSeenResetDate: Date?
    private var lastSeenUtilization: Double?
    private var didWarnNearLimitForWindow = false
    private var didRequestAuthorization = false

    init(usageService: ClaudeUsageService = .shared) {
        self.usageService = usageService
    }

    func start() {
        guard timer == nil else { return }
        requestAuthorizationIfNeeded()
        check()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// The five-hour window, or nil when usage data is unavailable.
    var sessionQuota: QuotaPeriod? { usageService.currentUsage }

    var weeklyQuota: QuotaPeriod? { usageService.currentWeeklyUsage }

    var modelQuota: QuotaPeriod? { usageService.currentModelUsage }

    var modelQuotaName: String? { usageService.currentModelUsageName }

    func check() {
        guard let quota = usageService.currentUsage else { return }
        let resetDate = quota.resetDate

        defer {
            lastSeenResetDate = resetDate
            lastSeenUtilization = quota.utilization
        }

        // A new window shows up either as a later reset timestamp or as
        // utilization dropping back down.
        let windowRolledOver: Bool
        if let previous = lastSeenResetDate, let current = resetDate {
            windowRolledOver = current > previous
        } else if let previous = lastSeenUtilization {
            windowRolledOver = quota.utilization < previous - 1
        } else {
            windowRolledOver = false
        }

        if windowRolledOver {
            lastResetAt = Date()
            didWarnNearLimitForWindow = false
            if Self.notifiesOnReset {
                notify(
                    title: String(localized: "Session limit reset"),
                    body: String(localized: "The five-hour window rolled over — full usage is available again."))
            }
            return
        }

        if Self.notifiesOnNearLimit,
           !didWarnNearLimitForWindow,
           quota.usagePercentage >= Self.nearLimitPercent {
            didWarnNearLimitForWindow = true
            let resetText = quota.formattedResetTime ?? String(localized: "soon")
            notify(
                title: String(localized: "Session limit almost reached"),
                body: String(localized: "\(quota.usagePercentage)% of the five-hour window used — resets in \(resetText)."))
        }
    }

    private func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                logger.info("Notification authorization denied")
            }
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
