import AppKit
import SwiftUI

/// Menu bar readout combining the manually configured spend budget with the
/// subscription's five-hour window, so both are visible at a glance without
/// expanding the notch panel.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    static let showRingKey = "menuBarShowRing"
    static let showBudgetKey = "menuBarShowBudget"
    static let showSessionKey = "menuBarShowSession"

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            showRingKey: true,
            showBudgetKey: true,
            showSessionKey: true,
        ])
    }

    private var statusItem: NSStatusItem?
    private var hostingView: NSHostingView<MenuBarUsageView>?
    private var refreshTimer: Timer?
    private var defaultsObserver: NSObjectProtocol?
    private let tracker: BudgetTracker
    private let sessionNotifier: SessionResetNotifier
    private let refreshInterval: TimeInterval = 15

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    init(tracker: BudgetTracker = .shared, sessionNotifier: SessionResetNotifier = .shared) {
        self.tracker = tracker
        self.sessionNotifier = sessionNotifier
        super.init()
    }

    func start() {
        tracker.start()
        sessionNotifier.start()
        installStatusItem()
        resizeToFit()
        // Toggling a part on or off changes how wide the item needs to be.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.resizeToFit() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tracker.recompute()
                self?.resizeToFit()
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
            self.defaultsObserver = nil
        }
        sessionNotifier.stop()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            hostingView = nil
        }
    }

    // MARK: - Status item

    private static let horizontalPadding: CGFloat = 6
    /// Kept above zero so the item stays clickable when every part is hidden.
    private static let minimumWidth: CGFloat = 24

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        if let button = item.button {
            let view = NSHostingView(rootView: MenuBarUsageView(
                tracker: tracker, usageService: ClaudeUsageService.shared))
            view.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(view)
            NSLayoutConstraint.activate([
                view.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                view.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            hostingView = view
        }
        statusItem = item
    }

    /// SwiftUI sizes the content, but the status item length has to follow it by hand.
    private func resizeToFit() {
        guard let statusItem, let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let width = hostingView.fittingSize.width + Self.horizontalPadding * 2
        statusItem.length = max(width, Self.minimumWidth)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        tracker.recompute()
        sessionNotifier.check()
        resizeToFit()
        menu.removeAllItems()

        menu.addItem(sectionHeader("Budget"))
        if BudgetSettings.isEnabled, let status = tracker.status {
            for line in budgetLines(for: status) {
                menu.addItem(disabledItem(line))
            }
        } else {
            menu.addItem(disabledItem(String(localized: "Off")))
        }

        menu.addItem(.separator())
        menu.addItem(sectionHeader("Subscription"))
        for line in subscriptionLines() {
            menu.addItem(disabledItem(line))
        }

        menu.addItem(.separator())
        menu.addItem(action(title: "Set Monthly Limit…", selector: #selector(promptForLimit)))
        menu.addItem(action(title: "Set Current Spend…", selector: #selector(promptForCurrentSpend)))
        menu.addItem(action(title: "Set Reset Day…", selector: #selector(promptForResetDay)))
        if !BudgetSettings.anchorDay.isEmpty {
            menu.addItem(action(title: "Clear Calibration", selector: #selector(clearCalibration)))
        }

        menu.addItem(.separator())
        menu.addItem(toggle(
            title: "Track Budget", isOn: BudgetSettings.isEnabled,
            selector: #selector(toggleBudgetTracking)))
        let reportedToggle = toggle(
            title: "Use Claude's Extra Usage Figures",
            isOn: BudgetSettings.prefersReportedSpend,
            selector: #selector(toggleReportedSpend))
        reportedToggle.isEnabled = UsageMetrics
            .extraUsageDisplay(ClaudeUsageService.shared.currentExtraUsage) != nil
        menu.addItem(reportedToggle)
        menu.addItem(toggle(
            title: "Notify on Session Reset", isOn: SessionResetNotifier.notifiesOnReset,
            selector: #selector(toggleNotifyOnReset)))
        menu.addItem(toggle(
            title: "Notify Near Session Limit", isOn: SessionResetNotifier.notifiesOnNearLimit,
            selector: #selector(toggleNotifyNearLimit)))

        menu.addItem(.separator())
        menu.addItem(action(title: "Refresh Now", selector: #selector(refreshNow)))
        menu.addItem(action(title: "Quit", selector: #selector(quit)))
    }

    private func budgetLines(for status: BudgetStatus) -> [String] {
        let percent = Int((status.fractionUsed * 100).rounded())
        var lines = [
            "Spent \(MenuBarFormatter.usd(status.spentUSD)) of \(MenuBarFormatter.usdRounded(status.limitUSD)) (\(percent)%)",
            "Period from \(Self.dayFormatter.string(from: status.periodStart)) — day \(status.dayIndex) of \(status.daysInPeriod)",
            "Even burn would be at \(MenuBarFormatter.usd(status.expectedByNowUSD))",
            "Average \(MenuBarFormatter.usd(status.averagePerDayUSD))/day, projected \(MenuBarFormatter.usd(status.projectedTotalUSD))",
        ]
        if status.remainingUSD > 0 {
            lines.append("Left \(MenuBarFormatter.usd(status.remainingUSD)) — \(MenuBarFormatter.usd(status.remainingPerDayUSD))/day for \(status.daysRemaining + 1) days")
        } else {
            lines.append("Over budget by \(MenuBarFormatter.usd(-status.remainingUSD))")
        }
        switch status.source {
        case .reported:
            lines.append("Reported by Claude — no calibration needed")
        case .calibrated:
            break
        case .estimated:
            lines.append("Estimated from local session logs — not calibrated")
        }
        if status.isTruncated {
            lines.append("Partial — logs do not reach the period start")
        }
        return lines
    }

    private func subscriptionLines() -> [String] {
        var lines: [String] = []
        if let session = sessionNotifier.sessionQuota {
            lines.append("Session \(session.usagePercentage)% — \(resetPhrase(for: session))")
        }
        if let weekly = sessionNotifier.weeklyQuota {
            lines.append("Week \(weekly.usagePercentage)% — \(resetPhrase(for: weekly))")
        }
        if let model = sessionNotifier.modelQuota {
            let name = sessionNotifier.modelQuotaName ?? String(localized: "Model")
            lines.append("\(name) week \(model.usagePercentage)% — \(resetPhrase(for: model))")
        }
        if let extra = UsageMetrics.extraUsageDisplay(ClaudeUsageService.shared.currentExtraUsage) {
            lines.append("Extra usage \(MenuBarFormatter.usd(extra.usedCredits)) of \(MenuBarFormatter.usdRounded(extra.monthlyLimit)) (\(extra.percentUsed)%)")
        }
        if let lastReset = sessionNotifier.lastResetAt {
            lines.append("Last rollover at \(Self.clockFormatter.string(from: lastReset))")
        }
        if lines.isEmpty {
            lines.append(String(localized: "No usage data — connect usage in the panel settings"))
        }
        return lines
    }

    private func resetPhrase(for quota: QuotaPeriod) -> String {
        guard let remaining = quota.formattedResetTime, let date = quota.resetDate else {
            return String(localized: "reset pending")
        }
        return "resets in \(remaining) (\(Self.clockFormatter.string(from: date)))"
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(title: String, selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func toggle(title: String, isOn: Bool, selector: Selector) -> NSMenuItem {
        let item = action(title: title, selector: selector)
        item.state = isOn ? .on : .off
        return item
    }

    // MARK: - Actions

    @objc private func promptForLimit() {
        guard let value = promptForNumber(
            message: String(localized: "Monthly budget"),
            informative: String(localized: "The dollar limit for one budget period."),
            initial: MenuBarFormatter.plain(BudgetSettings.limitUSD)) else { return }
        BudgetSettings.limitUSD = value
        tracker.recompute()
        resizeToFit()
    }

    @objc private func promptForCurrentSpend() {
        let informative = String(localized: """
        Enter the spend your provider currently reports. Usage from this point on is \
        added to it, so the menu bar stays aligned with the real balance.
        """)
        guard let value = promptForNumber(
            message: String(localized: "Current spend this period"),
            informative: informative,
            initial: MenuBarFormatter.plain(tracker.status?.spentUSD ?? 0)) else { return }
        tracker.calibrate(to: value)
        resizeToFit()
    }

    @objc private func promptForResetDay() {
        let informative = String(localized: "Day of the month the budget resets (1–\(BudgetSettings.maxResetDay)).")
        guard let value = promptForNumber(
            message: String(localized: "Reset day"),
            informative: informative,
            initial: String(BudgetSettings.resetDay)) else { return }
        BudgetSettings.resetDay = Int(value.rounded())
        tracker.recompute()
        resizeToFit()
    }

    @objc private func clearCalibration() {
        tracker.clearCalibration()
        resizeToFit()
    }

    @objc private func toggleBudgetTracking() {
        BudgetSettings.isEnabled.toggle()
        tracker.recompute()
        resizeToFit()
    }

    @objc private func toggleReportedSpend() {
        BudgetSettings.prefersReportedSpend.toggle()
        tracker.recompute()
        resizeToFit()
    }

    @objc private func toggleNotifyOnReset() {
        SessionResetNotifier.notifiesOnReset.toggle()
    }

    @objc private func toggleNotifyNearLimit() {
        SessionResetNotifier.notifiesOnNearLimit.toggle()
    }

    @objc private func refreshNow() {
        Task { @MainActor in
            await tracker.refresh()
            sessionNotifier.check()
            resizeToFit()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Input

    private func promptForNumber(message: String, informative: String, initial: String) -> Double? {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let cleaned = field.stringValue
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

}
