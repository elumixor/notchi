import SwiftUI

/// The menu bar readout: session usage ring, spend against budget, and time
/// until the session window resets. Each part is optional and disappears when
/// it has no data to show.
struct MenuBarUsageView: View {
    var tracker: BudgetTracker = .shared
    var usageService: ClaudeUsageService = .shared

    @AppStorage(MenuBarController.showRingKey) private var showRing = true
    @AppStorage(MenuBarController.showBudgetKey) private var showBudget = true
    @AppStorage(MenuBarController.showSessionKey) private var showSession = true

    static let ringDiameter: CGFloat = 13
    static let fontSize: CGFloat = 12
    private static let spacing: CGFloat = 6
    private static let countdownRefresh: TimeInterval = 30

    private var sessionQuota: QuotaPeriod? { usageService.currentUsage }

    var body: some View {
        // The reset countdown is derived from the current time, so it needs a
        // periodic redraw of its own.
        TimelineView(.periodic(from: .now, by: Self.countdownRefresh)) { _ in
            HStack(spacing: Self.spacing) {
                if showRing, let quota = sessionQuota {
                    UsageRingView(
                        percentage: quota.usagePercentage,
                        diameter: Self.ringDiameter,
                        lineWidth: 2.5,
                        isStale: usageService.isUsageStale)
                }

                if showBudget, let status = tracker.status {
                    Text(spendText(for: status))
                        .foregroundStyle(color(for: status.pace))
                }

                if showSession, let reset = sessionQuota?.formattedResetTime {
                    Text(reset)
                        .foregroundStyle(Color.primary.opacity(0.75))
                }
            }
            .font(.system(size: Self.fontSize).monospacedDigit())
            .fixedSize()
        }
    }

    private func spendText(for status: BudgetStatus) -> String {
        "\(MenuBarFormatter.usd(status.spentUSD)) / \(MenuBarFormatter.usdRounded(status.limitUSD))"
    }

    private func color(for pace: BudgetPace) -> Color {
        switch pace {
        case .under: TerminalColors.green
        case .ahead: TerminalColors.amber
        case .over: TerminalColors.red
        }
    }
}

nonisolated enum MenuBarFormatter {
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

    static func usd(_ amount: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    /// Whole dollars for figures the user typed themselves, which are rarely fractional.
    static func usdRounded(_ amount: Double) -> String {
        amount == amount.rounded() ? "$\(Int(amount))" : usd(amount)
    }

    static func plain(_ amount: Double) -> String {
        amount == amount.rounded() ? String(Int(amount)) : String(format: "%.2f", amount)
    }
}

#Preview {
    MenuBarUsageView()
        .padding()
        .background(Color.black)
}
