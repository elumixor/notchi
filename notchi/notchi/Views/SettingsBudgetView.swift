import SwiftUI

/// Monthly spend budget: limit, reset day, manual calibration, and the
/// notifications tied to the subscription's session window.
struct SettingsBudgetView: View {
    var tracker: BudgetTracker = .shared
    var usageService: ClaudeUsageService = .shared

    @State private var isEnabled = BudgetSettings.isEnabled
    @State private var prefersReportedSpend = BudgetSettings.prefersReportedSpend
    @State private var limitInput = BudgetFormatter.plain(BudgetSettings.limitUSD)
    @State private var resetDayInput = String(BudgetSettings.resetDay)
    @State private var spendInput = ""
    @State private var notifyOnReset = SessionResetNotifier.notifiesOnReset
    @State private var notifyNearLimit = SessionResetNotifier.notifiesOnNearLimit
    @FocusState private var focusedField: Field?

    private enum Field { case limit, resetDay, spend }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private var hasReportedSpend: Bool {
        UsageMetrics.extraUsageDisplay(usageService.currentExtraUsage) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                toggleRow(icon: "chart.line.uptrend.xyaxis", title: "Track Budget", isOn: isEnabled) {
                    isEnabled.toggle()
                    BudgetSettings.isEnabled = isEnabled
                    tracker.recompute()
                }

                if isEnabled {
                    fieldRow(icon: "dollarsign.circle", title: "Monthly Limit", text: $limitInput, field: .limit, commit: saveLimit)
                    fieldRow(icon: "calendar", title: "Reset Day", text: $resetDayInput, field: .resetDay, commit: saveResetDay)

                    Divider().background(Color.white.opacity(0.08))

                    calibrationSection

                    toggleRow(
                        icon: "cloud", title: "Use Claude's Extra Usage Figures",
                        isOn: prefersReportedSpend, isEnabled: hasReportedSpend
                    ) {
                        prefersReportedSpend.toggle()
                        BudgetSettings.prefersReportedSpend = prefersReportedSpend
                        tracker.recompute()
                    }

                    Divider().background(Color.white.opacity(0.08))

                    summarySection
                }

                Divider().background(Color.white.opacity(0.08))

                toggleRow(icon: "bell", title: "Notify on Session Reset", isOn: notifyOnReset) {
                    notifyOnReset.toggle()
                    SessionResetNotifier.notifiesOnReset = notifyOnReset
                }
                toggleRow(icon: "bell.badge", title: "Notify Near Session Limit", isOn: notifyNearLimit) {
                    notifyNearLimit.toggle()
                    SessionResetNotifier.notifiesOnNearLimit = notifyNearLimit
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.3), value: isEnabled)
        .onAppear {
            tracker.recompute()
            spendInput = BudgetFormatter.plain(tracker.status?.spentUSD ?? 0)
        }
        .onChange(of: focusedField) { previous, _ in
            switch previous {
            case .limit: saveLimit()
            case .resetDay: saveResetDay()
            case .spend, nil: break
            }
        }
    }

    // MARK: - Sections

    private var calibrationSection: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.apiKeySpacing) {
            HStack {
                Image(systemName: "scope")
                    .panelIcon(size: 12)
                    .foregroundColor(TerminalColors.secondaryText)
                    .frame(width: 20)
                Text("Current Spend")
                    .panelFont(size: 12)
                    .foregroundColor(TerminalColors.primaryText)
                Spacer()
                HStack(spacing: 6) {
                    numberField(text: $spendInput, field: .spend, commit: calibrate)
                        .frame(width: 90)
                    Button(action: calibrate) {
                        Image(systemName: "checkmark.circle.fill")
                            .panelFont(size: 14)
                            .foregroundColor(TerminalColors.green)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, SettingsLayout.rowVerticalPadding)

            Text("Enter what your provider reports right now. Usage from here on is added to it.")
                .panelFont(size: 10)
                .foregroundColor(TerminalColors.dimmedText)
                .padding(.leading, SettingsLayout.fieldLeadingInset)

            if let setAt = BudgetSettings.anchorSetAt, !BudgetSettings.anchorDay.isEmpty {
                HStack {
                    Text("Calibrated \(Self.dayFormatter.string(from: setAt)) at \(BudgetFormatter.usd(BudgetSettings.anchorAmountUSD))")
                        .panelFont(size: 10)
                        .foregroundColor(TerminalColors.secondaryText)
                    Spacer()
                    Button(action: { tracker.clearCalibration() }) {
                        Text("Clear")
                            .panelFont(size: 10, weight: .medium)
                            .foregroundColor(TerminalColors.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, SettingsLayout.fieldLeadingInset)
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if let status = tracker.status {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(summaryLines(for: status), id: \.self) { line in
                    Text(line)
                        .panelFont(size: 10)
                        .foregroundColor(TerminalColors.secondaryText)
                }
            }
            .padding(.leading, SettingsLayout.fieldLeadingInset)
            .padding(.vertical, SettingsLayout.rowVerticalPadding)
        }
    }

    private func summaryLines(for status: BudgetStatus) -> [String] {
        let percent = Int((status.fractionUsed * 100).rounded())
        var lines = [
            "Spent \(BudgetFormatter.usd(status.spentUSD)) of \(BudgetFormatter.usdRounded(status.limitUSD)) (\(percent)%)",
            "Period from \(Self.dayFormatter.string(from: status.periodStart)), day \(status.dayIndex) of \(status.daysInPeriod)",
            "Even burn would be at \(BudgetFormatter.usd(status.expectedByNowUSD))",
            "Average \(BudgetFormatter.usd(status.averagePerDayUSD))/day, projected \(BudgetFormatter.usd(status.projectedTotalUSD))",
        ]
        if status.remainingUSD > 0 {
            lines.append("Left \(BudgetFormatter.usd(status.remainingUSD)): \(BudgetFormatter.usd(status.remainingPerDayUSD))/day for \(status.daysRemaining + 1) days")
        } else {
            lines.append("Over budget by \(BudgetFormatter.usd(-status.remainingUSD))")
        }
        switch status.source {
        case .reported: lines.append("Reported by Claude, no calibration needed")
        case .calibrated: break
        case .estimated: lines.append("Estimated from local session logs, not calibrated")
        }
        if status.isTruncated {
            lines.append("Partial: logs do not reach the period start")
        }
        return lines
    }

    // MARK: - Rows

    private func toggleRow(
        icon: String, title: LocalizedStringKey, isOn: Bool, isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SettingsRowView(icon: icon, title: title) {
                ToggleSwitch(isOn: isOn)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }

    private func fieldRow(
        icon: String, title: LocalizedStringKey, text: Binding<String>, field: Field,
        commit: @escaping () -> Void
    ) -> some View {
        SettingsRowView(icon: icon, title: title) {
            numberField(text: text, field: field, commit: commit)
                .frame(width: 90)
        }
    }

    private func numberField(text: Binding<String>, field: Field, commit: @escaping () -> Void) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .panelFont(size: 11, design: .monospaced)
            .foregroundColor(TerminalColors.primaryText)
            .padding(.horizontal, SettingsLayout.fieldHorizontalPadding)
            .padding(.vertical, SettingsLayout.fieldVerticalPadding)
            .background(Color.white.opacity(0.06))
            .cornerRadius(6)
            .focused($focusedField, equals: field)
            .onSubmit(commit)
    }

    // MARK: - Actions

    private func parseNumber(_ raw: String) -> Double? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private func saveLimit() {
        if let value = parseNumber(limitInput), value > 0 {
            BudgetSettings.limitUSD = value
            tracker.recompute()
        }
        limitInput = BudgetFormatter.plain(BudgetSettings.limitUSD)
    }

    private func saveResetDay() {
        if let value = parseNumber(resetDayInput) {
            BudgetSettings.resetDay = Int(value.rounded())
            tracker.recompute()
        }
        resetDayInput = String(BudgetSettings.resetDay)
    }

    private func calibrate() {
        guard let value = parseNumber(spendInput) else { return }
        focusedField = nil
        tracker.calibrate(to: value)
        spendInput = BudgetFormatter.plain(tracker.status?.spentUSD ?? value)
    }
}
