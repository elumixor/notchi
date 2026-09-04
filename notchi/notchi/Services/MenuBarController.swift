import AppKit

/// Menu bar readout combining the manually configured spend budget with the
/// subscription's five-hour window, so both are visible at a glance without
/// expanding the notch panel.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    static let showBudgetKey = "menuBarShowBudget"
    static let showSessionKey = "menuBarShowSession"

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            showBudgetKey: true,
            showSessionKey: true,
        ])
    }

    static var showsBudget: Bool {
        get { UserDefaults.standard.object(forKey: showBudgetKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showBudgetKey) }
    }

    static var showsSession: Bool {
        get { UserDefaults.standard.object(forKey: showSessionKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showSessionKey) }
    }

    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private let tracker: BudgetTracker
    private let sessionNotifier: SessionResetNotifier
    private let refreshInterval: TimeInterval = 15

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

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
        updateTitle()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tracker.recompute()
                self?.updateTitle()
            }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        sessionNotifier.stop()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: - Status item

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let budget = tracker.status
        var segments: [String] = []
        if Self.showsBudget, let budget {
            segments.append("\(Self.usd(budget.spentUSD)) / \(Self.usdRounded(budget.limitUSD))")
        }
        if Self.showsSession, let reset = sessionNotifier.sessionQuota?.formattedResetTime {
            segments.append(reset)
        }
        let text = segments.isEmpty ? "usage" : segments.joined(separator: " · ")
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: budget.map { color(for: $0.pace) } ?? NSColor.labelColor,
        ])
    }

    private func color(for pace: BudgetPace) -> NSColor {
        switch pace {
        case .under: .systemGreen
        case .ahead: .systemOrange
        case .over: .systemRed
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        tracker.recompute()
        sessionNotifier.check()
        updateTitle()
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
        menu.addItem(toggle(
            title: "Show Budget in Menu Bar", isOn: Self.showsBudget,
            selector: #selector(toggleShowBudget)))
        menu.addItem(toggle(
            title: "Show Session Reset in Menu Bar", isOn: Self.showsSession,
            selector: #selector(toggleShowSession)))
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
            "Spent \(Self.usd(status.spentUSD)) of \(Self.usdRounded(status.limitUSD)) (\(percent)%)",
            "Period from \(Self.dayFormatter.string(from: status.periodStart)) — day \(status.dayIndex) of \(status.daysInPeriod)",
            "Even burn would be at \(Self.usd(status.expectedByNowUSD))",
            "Average \(Self.usd(status.averagePerDayUSD))/day, projected \(Self.usd(status.projectedTotalUSD))",
        ]
        if status.remainingUSD > 0 {
            lines.append("Left \(Self.usd(status.remainingUSD)) — \(Self.usd(status.remainingPerDayUSD))/day for \(status.daysRemaining + 1) days")
        } else {
            lines.append("Over budget by \(Self.usd(-status.remainingUSD))")
        }
        if BudgetSettings.anchorDay.isEmpty {
            lines.append("Not calibrated — estimated from local session logs")
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
            initial: Self.plain(BudgetSettings.limitUSD)) else { return }
        BudgetSettings.limitUSD = value
        tracker.recompute()
        updateTitle()
    }

    @objc private func promptForCurrentSpend() {
        let informative = String(localized: """
        Enter the spend your provider currently reports. Usage from this point on is \
        added to it, so the menu bar stays aligned with the real balance.
        """)
        guard let value = promptForNumber(
            message: String(localized: "Current spend this period"),
            informative: informative,
            initial: Self.plain(tracker.status?.spentUSD ?? 0)) else { return }
        tracker.calibrate(to: value)
        updateTitle()
    }

    @objc private func promptForResetDay() {
        let informative = String(localized: "Day of the month the budget resets (1–\(BudgetSettings.maxResetDay)).")
        guard let value = promptForNumber(
            message: String(localized: "Reset day"),
            informative: informative,
            initial: String(BudgetSettings.resetDay)) else { return }
        BudgetSettings.resetDay = Int(value.rounded())
        tracker.recompute()
        updateTitle()
    }

    @objc private func clearCalibration() {
        tracker.clearCalibration()
        updateTitle()
    }

    @objc private func toggleBudgetTracking() {
        BudgetSettings.isEnabled.toggle()
        tracker.recompute()
        updateTitle()
    }

    @objc private func toggleShowBudget() {
        Self.showsBudget.toggle()
        updateTitle()
    }

    @objc private func toggleShowSession() {
        Self.showsSession.toggle()
        updateTitle()
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
            updateTitle()
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

    // MARK: - Formatting

    private static func usd(_ amount: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    /// Whole dollars for figures the user typed themselves, which are rarely fractional.
    private static func usdRounded(_ amount: Double) -> String {
        amount == amount.rounded() ? "$\(Int(amount))" : usd(amount)
    }

    private static func plain(_ amount: Double) -> String {
        amount == amount.rounded() ? String(Int(amount)) : String(format: "%.2f", amount)
    }
}
