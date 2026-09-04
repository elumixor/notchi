import SwiftUI

enum NotchConstants {
    static let expandedPanelSize = CGSize(width: 450, height: 450)
    static let expandedPanelHorizontalPadding: CGFloat = 19 * 2
    static let expandedPanelContentInset: CGFloat = 48
    static let expandedPanelHitTestSlack: CGFloat = 48
    static let expandedPanelVerticalInset: CGFloat = 24

    static var expandedPanelContentWidth: CGFloat {
        expandedPanelSize.width - expandedPanelContentInset
    }

    static func expandedContentHeight(notchHeight: CGFloat) -> CGFloat {
        expandedPanelSize.height - notchHeight - expandedPanelVerticalInset
    }

    static var scalablePanelHeight: CGFloat {
        expandedPanelSize.height - expandedPanelVerticalInset
    }

    static func panelSize(scale: CGFloat) -> CGSize {
        CGSize(
            width: expandedPanelContentWidth * scale + expandedPanelHorizontalPadding + expandedPanelHitTestSlack,
            height: scalablePanelHeight * scale + expandedPanelVerticalInset
        )
    }
}

enum PanelTypography {
    static let enlargedFontScale: CGFloat = 1.125

    static func fontScale(panelScale: CGFloat) -> CGFloat {
        panelScale > 1 ? enlargedFontScale : 1
    }
}

private struct PanelScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var panelScale: CGFloat {
        get { self[PanelScaleKey.self] }
        set { self[PanelScaleKey.self] = newValue }
    }
}

extension View {
    func panelIcon(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(PanelIconModifier(size: size, weight: weight))
    }

    func panelFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        transform: @escaping (Font) -> Font = { $0 }
    ) -> some View {
        modifier(PanelFontModifier(size: size, weight: weight, design: design, transform: transform))
    }
}

struct PanelIconModifier: ViewModifier {
    @Environment(\.panelScale) private var panelScale
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(.system(size: size * panelScale, weight: weight))
    }
}

struct PanelFontModifier: ViewModifier {
    @Environment(\.panelScale) private var panelScale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let transform: (Font) -> Font

    func body(content: Content) -> some View {
        let scaledSize = size * PanelTypography.fontScale(panelScale: panelScale)
        return content.font(transform(.system(size: scaledSize, weight: weight, design: design)))
    }
}

extension Notification.Name {
    static let notchiShouldCollapse = Notification.Name("notchiShouldCollapse")
    static let notchiQuestionOptionShortcut = Notification.Name("notchiQuestionOptionShortcut")
    static let notchiCollapsedGeometryDidChange = Notification.Name("notchiCollapsedGeometryDidChange")
}

private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

private enum SpriteHandoffTiming {
    static let expandAnimationDuration = 0.2
    static let collapseAnimationDuration = 0.16
    static let cleanupBufferDuration = 0.02

    static func animationDuration(for expanded: Bool) -> Double {
        expanded ? expandAnimationDuration : collapseAnimationDuration
    }

    static func cleanupDelay(for expanded: Bool) -> Duration {
        let totalMilliseconds = Int(((animationDuration(for: expanded) + cleanupBufferDuration) * 1000).rounded())
        return .milliseconds(totalMilliseconds)
    }
}

private enum LaunchWaveTiming {
    static let startDelay = 1.0
    static let preparationDuration = 0.45
    static let spriteScale: CGFloat = 1.2
    static let horizontalOffset: CGFloat = 5
}

struct NotchContentView: View {
    private enum NotchSide {
        case left, right
    }

    private struct SpriteHandoff {
        enum Direction {
            case expanding
            case collapsing
        }

        let direction: Direction
        let sessionId: String
        let keepsGrassIslandRendered: Bool
    }

    struct LaunchWave: Equatable {
        let state: NotchiState
        let startedAt: Date
    }

    struct HeaderSpriteContent: Equatable {
        let state: NotchiState
        let mirrorSeed: String
        let startedAt: Date
        let repeatsAnimation: Bool
        let scale: CGFloat
        let xOffset: CGFloat

        init(
            state: NotchiState,
            mirrorSeed: String,
            startedAt: Date = SpriteAnimationPhase.sharedLoopAnchor,
            repeatsAnimation: Bool = true,
            scale: CGFloat = 1,
            xOffset: CGFloat = 0
        ) {
            self.state = state
            self.mirrorSeed = mirrorSeed
            self.startedAt = startedAt
            self.repeatsAnimation = repeatsAnimation
            self.scale = scale
            self.xOffset = xOffset
        }
    }

    var stateMachine: NotchiStateMachine = .shared
    var panelManager: NotchPanelManager = .shared
    var usageService: ClaudeUsageService = .shared
    var codexUsageService: CodexUsageService = .shared
    var haptics: HapticService = .shared
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @ObservedObject private var updateManager = UpdateManager.shared
    @AppStorage(AppSettings.notchLeftItemsKey) private var leftItemsRaw = NotchSlotContent.encode(AppSettings.notchLeftItems)
    @AppStorage(AppSettings.notchRightItemsKey) private var rightItemsRaw = NotchSlotContent.encode(AppSettings.notchRightItems)
    var budgetTracker: BudgetTracker = .shared
    @State private var leftContentWidth: CGFloat = 0
    @State private var rightContentWidth: CGFloat = 0
    @State private var showingPanelSettings = false
    @State private var settingsPath: [SettingsScreen] = []
    @State private var showingUsageDetail = false
    @State private var usageDetailProvider: AgentProvider?
    @State private var showingSessionActivity = false
    @State private var isMuted = AppSettings.isMuted
    @State private var isActivityCollapsed = false
    @AppStorage(AppSettings.showGrassIslandKey) private var showGrassIsland = true
    @State private var hoveredSessionId: String?
    @State private var spriteHandoff: SpriteHandoff?
    @State private var spriteHandoffProgress: CGFloat = 0
    @State private var spriteHandoffGeneration = 0
    @State private var launchGlowVisible = false
    @State private var launchGlowProgress: Double = 0
    @State private var isLaunchWavePreparing = false
    @State private var launchWave: LaunchWave?
    @State private var launchSpriteFamily = AppSettings.lastUsedAgentProvider.spriteFamily
    @MainActor private static var hasPlayedLaunchGlow = false
    @MainActor private static var hasPlayedLaunchWave = false

    private var sessionStore: SessionStore {
        stateMachine.sessionStore
    }

    private var activeSession: SessionData? {
        sessionStore.effectiveSession
    }

    static func panelMode(showGrassIsland: Bool, isActivityCollapsed: Bool) -> ExpandedPanelMode {
        if !showGrassIsland { return .compact }
        return isActivityCollapsed ? .islandOnly : .full
    }

    private var panelMode: ExpandedPanelMode {
        Self.panelMode(showGrassIsland: showGrassIsland, isActivityCollapsed: isActivityCollapsed)
    }

    private var notchSize: CGSize { panelManager.notchSize }
    private var isExpanded: Bool { panelManager.isExpanded }
    private var collapsedMode: NotchPanelManager.CollapsedMode { panelManager.collapsedMode }
    private var isCompactIdle: Bool { !isExpanded && collapsedMode == .compactIdle }
    private var leftItems: [NotchSlotContent] { NotchSlotContent.parse(leftItemsRaw) }
    private var rightItems: [NotchSlotContent] { NotchSlotContent.parse(rightItemsRaw) }

    private func items(on side: NotchSide) -> [NotchSlotContent] {
        side == .left ? leftItems : rightItems
    }

    /// The provider a "latest session" mascot must skip, because the other side
    /// already shows that provider's own mascot.
    private func excludedProvider(for side: NotchSide) -> AgentProvider? {
        items(on: side == .left ? .right : .left).compactMap(\.spriteProvider).first
    }

    private func spriteContent(for content: NotchSlotContent, side: NotchSide) -> HeaderSpriteContent? {
        let excluded = excludedProvider(for: side)
        if let session = sessionForSprite(content, excluding: excluded) {
            return HeaderSpriteContent(state: session.state, mirrorSeed: session.id)
        }
        if let launchWave,
           contentAcceptsSprite(content, spriteFamily: launchWave.state.spriteFamily, excluding: excluded) {
            return HeaderSpriteContent(
                state: launchWave.state,
                mirrorSeed: "launch-wave-\(launchWave.state.spriteFamily.rawValue)",
                startedAt: launchWave.startedAt,
                repeatsAnimation: false,
                scale: LaunchWaveTiming.spriteScale,
                xOffset: LaunchWaveTiming.horizontalOffset
            )
        }
        return nil
    }

    private func sessionForSprite(_ content: NotchSlotContent, excluding excluded: AgentProvider?) -> SessionData? {
        switch content {
        case .claude: sessionStore.latestSession(for: .claude)
        case .codex: sessionStore.latestSession(for: .codex)
        case .latest: sessionStore.latestSession(excluding: excluded)
        case .usageRing, .resetRing, .spend: nil
        }
    }

    private func contentAcceptsSprite(
        _ content: NotchSlotContent,
        spriteFamily: NotchiSpriteFamily,
        excluding excluded: AgentProvider?
    ) -> Bool {
        switch content {
        case .claude: spriteFamily == AgentProvider.claude.spriteFamily
        case .codex: spriteFamily == AgentProvider.codex.spriteFamily
        case .latest: spriteFamily != excluded?.spriteFamily
        case .usageRing, .resetRing, .spend: false
        }
    }

    static func shouldRenderGrassIsland(
        isExpanded: Bool,
        showingPanelSettings: Bool,
        mode: ExpandedPanelMode,
        keepsGrassIslandRenderedForHandoff: Bool = false
    ) -> Bool {
        shouldShowGrassIsland(isExpanded: isExpanded, showingPanelSettings: showingPanelSettings, mode: mode)
            || keepsGrassIslandRenderedForHandoff
    }

    static func shouldShowGrassIsland(
        isExpanded: Bool,
        showingPanelSettings: Bool,
        mode: ExpandedPanelMode
    ) -> Bool {
        isExpanded && !showingPanelSettings && mode != .compact
    }

    private var shouldRenderGrassIsland: Bool {
        Self.shouldRenderGrassIsland(
            isExpanded: isExpanded,
            showingPanelSettings: showingPanelSettings,
            mode: panelMode,
            keepsGrassIslandRenderedForHandoff: spriteHandoff?.keepsGrassIslandRendered == true
        )
    }

    private var shouldShowGrassIsland: Bool {
        Self.shouldShowGrassIsland(
            isExpanded: isExpanded,
            showingPanelSettings: showingPanelSettings,
            mode: panelMode
        )
    }

    private var collapsedHoverHorizontalInset: CGFloat {
        !isExpanded && panelManager.isCollapsedHovered
            ? NotchPanelManager.collapsedHoverHorizontalInset
            : 0
    }

    private var collapsedHoverBottomInset: CGFloat {
        !isExpanded && panelManager.isCollapsedHovered
            ? NotchPanelManager.collapsedHoverBottomInset
            : 0
    }

    private var panelAnimation: Animation {
        isExpanded
            ? .spring(response: 0.5, dampingFraction: 0.78)
            : .spring(response: 0.36, dampingFraction: 0.88)
    }

    private var collapsedHoverAnimation: Animation {
        panelManager.isCollapsedHovered
            ? .spring(response: 0.36, dampingFraction: 0.74)
            : .spring(response: 0.28, dampingFraction: 0.96)
    }

    private var expandedChromeTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: -12)
                .combined(with: .opacity)
                .animation(.easeOut(duration: 0.22).delay(0.08)),
            removal: .offset(y: -6)
                .combined(with: .opacity)
                .animation(.easeIn(duration: 0.12))
        )
    }

    private var expandedHeaderTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: -8)
                .combined(with: .opacity)
                .animation(.easeOut(duration: 0.2).delay(0.12)),
            removal: .offset(y: -4)
                .combined(with: .opacity)
                .animation(.easeIn(duration: 0.1))
        )
    }

    private var collapsedHeaderSpriteVisibilityAnimation: Animation {
        isExpanded
            ? .easeOut(duration: 0.14).delay(0.05)
            : .easeOut(duration: 0.16)
    }

    private var collapsedHeaderSpriteScale: CGFloat {
        let hoverScale: CGFloat = !isExpanded && panelManager.isCollapsedHovered ? 1.08 : 1
        return hoverScale * Self.headerSpriteFitScale(
            notchHeight: notchSize.height,
            screenHasNotch: panelManager.screenHasNotch
        )
    }

    static func headerSpriteFitScale(notchHeight: CGFloat, screenHasNotch: Bool) -> CGFloat {
        guard !screenHasNotch else { return 1 }
        let referenceNotchHeight: CGFloat = 38
        let minimumScale: CGFloat = 0.8
        return min(1, max(minimumScale, notchHeight / referenceNotchHeight))
    }

    private var collapsedHeaderSpriteOffsetX: CGFloat {
        let baseOffset: CGFloat = 15
        guard !isExpanded && panelManager.isCollapsedHovered else { return baseOffset }
        return baseOffset + 6
    }

    private var collapsedHeaderSpriteOffsetY: CGFloat {
        let baseOffset: CGFloat = -2
        guard !isExpanded && panelManager.isCollapsedHovered else { return baseOffset }
        return baseOffset + 3
    }

    private func ringOffsetX(side: NotchSide) -> CGFloat {
        var magnitude = sideWidth / 4 + cornerRadiusInsets.closed.top
        if !isExpanded && panelManager.isCollapsedHovered {
            magnitude += 6
        }
        return side == .left ? -magnitude : magnitude
    }

    private func spriteOffsetX(side: NotchSide) -> CGFloat {
        side == .left ? -collapsedHeaderSpriteOffsetX : collapsedHeaderSpriteOffsetX
    }

    private var collapsedUsageRingOffsetY: CGFloat {
        !isExpanded && panelManager.isCollapsedHovered ? 2 : -1
    }

    private var isLaunchWaveActive: Bool {
        launchWave != nil || isLaunchWavePreparing
    }

    private var collapsedHeaderSpriteVisuals: (opacity: Double, blur: CGFloat) {
        guard let activeSession, let spriteHandoff, spriteHandoff.sessionId == activeSession.id else {
            return (opacity: isExpanded ? 0 : 1, blur: 0)
        }

        let isSource = spriteHandoff.direction == .expanding
        return (
            opacity: SpriteHandoffVisuals.opacity(for: spriteHandoffProgress, isSource: isSource),
            blur: SpriteHandoffVisuals.blur(for: spriteHandoffProgress, isSource: isSource)
        )
    }

    private var sideWidth: CGFloat {
        max(0, notchSize.height - 12) + 24
    }

    private var collapsedSpriteSession: SessionData? {
        for side in [NotchSide.left, .right] {
            for item in items(on: side) where item.isSprite {
                if let session = sessionForSprite(item, excluding: excludedProvider(for: side)) {
                    return session
                }
            }
        }
        return nil
    }

    private var ringProvider: AgentProvider {
        Self.collapsedRingProvider(
            spriteSession: collapsedSpriteSession,
            effectiveSession: activeSession,
            lastUsedProvider: AppSettings.lastUsedAgentProvider
        )
    }

    static func collapsedRingProvider(
        spriteSession: SessionData?,
        effectiveSession: SessionData?,
        lastUsedProvider: AgentProvider
    ) -> AgentProvider {
        (spriteSession ?? effectiveSession)?.provider ?? lastUsedProvider
    }

    private var ringIsStale: Bool {
        ringProvider == .codex ? codexUsageService.isUsageStale : usageService.isUsageStale
    }

    static func collapsedRingUsage(
        provider: AgentProvider,
        claudeUsage: QuotaPeriod?,
        codexSessionUsage: QuotaPeriod?,
        codexWeeklyUsage: QuotaPeriod?
    ) -> QuotaPeriod? {
        provider == .codex ? (codexSessionUsage ?? codexWeeklyUsage) : claudeUsage
    }

    static func collapsedRingPercentage(
        isUsageEnabled: Bool,
        provider: AgentProvider,
        claudeUsage: QuotaPeriod?,
        codexSessionUsage: QuotaPeriod?,
        codexWeeklyUsage: QuotaPeriod?
    ) -> Int? {
        guard isUsageEnabled else { return nil }
        guard let percentage = collapsedRingUsage(
            provider: provider,
            claudeUsage: claudeUsage,
            codexSessionUsage: codexSessionUsage,
            codexWeeklyUsage: codexWeeklyUsage
        )?.usagePercentage, percentage > 0 else { return nil }
        return percentage
    }

    private var usageRingPercentage: Int? {
        Self.collapsedRingPercentage(
            isUsageEnabled: AppSettings.isUsageEnabled,
            provider: ringProvider,
            claudeUsage: usageService.currentUsage,
            codexSessionUsage: codexUsageService.currentUsage,
            codexWeeklyUsage: codexUsageService.currentWeeklyUsage
        )
    }

    private var isCollapsedRingVisible: Bool {
        [NotchSide.left, .right].contains { side in
            items(on: side).contains { !$0.isSprite && isItemVisible($0, side: side) }
        }
    }

    // MARK: - Collapsed usage items

    private static let itemSpacing: CGFloat = 5
    private static let readoutFontSize: CGFloat = 11
    private var collapsedRingDiameter: CGFloat { 20 }

    /// Five-hour session window; the reset ring follows the session quota.
    private static let sessionWindowLength: TimeInterval = 5 * 3600

    private var ringQuota: QuotaPeriod? {
        guard AppSettings.isUsageEnabled else { return nil }
        return Self.collapsedRingUsage(
            provider: ringProvider,
            claudeUsage: usageService.currentUsage,
            codexSessionUsage: codexUsageService.currentUsage,
            codexWeeklyUsage: codexUsageService.currentWeeklyUsage
        )
    }

    private var resetText: String? { ringQuota?.compactResetTime }

    private func isItemVisible(_ item: NotchSlotContent, side: NotchSide) -> Bool {
        switch item {
        case .usageRing: usageRingPercentage != nil
        case .resetRing: resetText != nil
        case .spend: budgetTracker.status != nil
        case .latest, .claude, .codex: spriteContent(for: item, side: side) != nil
        }
    }

    private func visibleItems(on side: NotchSide) -> [NotchSlotContent] {
        items(on: side).filter { isItemVisible($0, side: side) }
    }

    /// A side holding only a mascot keeps the original sprite layout; anything
    /// else is laid out as a row that can grow past the slot.
    private func usesRowLayout(on side: NotchSide) -> Bool {
        let items = items(on: side)
        return !(items.count == 1 && items[0].isSprite)
    }

    /// Outward shift shared by the row and the ring, without the hover bump so
    /// the hit rect does not change while the cursor is over it.
    private var ringOffsetMagnitude: CGFloat {
        sideWidth / 4 + cornerRadiusInsets.closed.top
    }

    /// Gap between the notch edge and the row, so text clears the notch curve.
    private var rowInnerInset: CGFloat {
        (sideWidth - collapsedRingDiameter) / 2
    }

    /// Width a side needs beyond its normal share to fit its row.
    private func extraWidth(on side: NotchSide) -> CGFloat {
        guard usesRowLayout(on: side) else { return 0 }
        let width = side == .left ? leftContentWidth : rightContentWidth
        guard width > 0 else { return 0 }
        return max(0, width + ringOffsetMagnitude - sideWidth)
    }

    private var collapsedExtraWidth: (left: CGFloat, right: CGFloat) {
        (extraWidth(on: .left), extraWidth(on: .right))
    }

    /// Keeps the notch cut-out over the physical notch when one side is wider.
    private var collapsedContentOffsetX: CGFloat {
        guard !isExpanded else { return 0 }
        let extra = collapsedExtraWidth
        return (extra.right - extra.left) / 2
    }

    private func paceColor(for pace: BudgetPace) -> Color {
        switch pace {
        case .under: TerminalColors.green
        case .ahead: TerminalColors.amber
        case .over: TerminalColors.red
        }
    }

    private var collapsedRing: some View {
        UsageRingView(
            percentage: usageRingPercentage ?? 0,
            diameter: collapsedRingDiameter,
            lineWidth: 2.5,
            isStale: ringIsStale,
            label: String(usageRingPercentage ?? 0)
        )
    }

    private var collapsedResetRing: some View {
        ResetRingView(
            fractionRemaining: ringQuota?.fractionRemaining(windowLength: Self.sessionWindowLength) ?? 0,
            label: resetText ?? "",
            diameter: collapsedRingDiameter + 2
        )
    }

    @ViewBuilder
    private var collapsedSpend: some View {
        if let status = budgetTracker.status {
            Group {
                if BudgetSettings.showsLimit {
                    Text("\(BudgetFormatter.usdCompact(status.spentUSD)) / \(BudgetFormatter.usdRounded(status.limitUSD))")
                        .foregroundColor(paceColor(for: status.pace))
                } else {
                    Text(BudgetFormatter.usdCompact(status.spentUSD))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .font(.system(size: Self.readoutFontSize, weight: .medium).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
        }
    }

    private var compactContentWidth: CGFloat {
        max(0, panelManager.compactNotchRect.width - (cornerRadiusInsets.closed.bottom * 2))
    }

    private var topCornerRadius: CGFloat {
        isExpanded ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        isExpanded ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom
    }

    /// Uses the system notch curve in collapsed mode when available.
    private var notchClipShape: AnyShape {
        if !isExpanded, let systemPath = panelManager.systemNotchPath {
            return AnyShape(SystemNotchShape(cgPath: systemPath))
        }
        return AnyShape(NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        ))
    }

    private var grassHeight: CGFloat {
        let contentHeight = NotchConstants.expandedContentHeight(notchHeight: notchSize.height)
        return (contentHeight * 0.3 + notchSize.height) * panelManager.panelScale
    }

    private var shouldShowBackButton: Bool {
        showingPanelSettings ||
        (showingUsageDetail && panelMode != .islandOnly) ||
        (sessionStore.activeSessionCount >= 2 && showingSessionActivity)
    }

    static let islandOnlyPanelHeight: CGFloat = 155
    static let expandedHeaderTopPadding: CGFloat = 4

    static var expandedHeaderRowHeight: CGFloat {
        PanelHeaderButton.baseSize + expandedHeaderTopPadding
    }

    static func expandedPanelHeight(mode: ExpandedPanelMode, notchHeight: CGFloat) -> CGFloat {
        mode == .islandOnly
            ? islandOnlyPanelHeight
            : NotchConstants.expandedContentHeight(notchHeight: notchHeight)
    }

    private var panelScale: CGFloat { panelManager.panelScale }

    private var expandedPanelHeight: CGFloat {
        Self.expandedPanelHeight(mode: panelMode, notchHeight: notchSize.height)
    }

    private var launchWavePreparationAnimation: Animation {
        .easeInOut(duration: LaunchWaveTiming.preparationDuration)
    }

    private var grassIslandOpacityAnimation: Animation {
        .easeOut(duration: SpriteHandoffTiming.collapseAnimationDuration)
    }

    var body: some View {
        VStack(spacing: 0) {
            notchLayout
        }
        .padding(
            .horizontal,
            isExpanded
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.bottom + collapsedHoverHorizontalInset
        )
        .padding(.bottom, isExpanded ? 12 : collapsedHoverBottomInset)
        .background {
            ZStack(alignment: .top) {
                Color.black
                if shouldRenderGrassIsland {
                    GrassIslandView(
                        sessions: sessionStore.sortedSessions,
                        selectedSessionId: sessionStore.selectedSessionId,
                        hoveredSessionId: hoveredSessionId,
                        handoffSessionId: spriteHandoff?.sessionId,
                        handoffProgress: spriteHandoffProgress,
                        isHandoffCollapsing: spriteHandoff?.direction == .collapsing
                    )
                    .environment(\.panelScale, panelScale)
                    .frame(height: grassHeight, alignment: .bottom)
                    .opacity(shouldShowGrassIsland ? 1 : 0)
                    .animation(grassIslandOpacityAnimation, value: shouldShowGrassIsland)
                }
            }
        }
        .overlay(alignment: .top) {
            if shouldShowGrassIsland {
                GrassTapOverlay(
                    sessions: sessionStore.sortedSessions,
                    selectedSessionId: sessionStore.selectedSessionId,
                    hoveredSessionId: $hoveredSessionId,
                    handoffSessionId: spriteHandoff?.sessionId,
                    handoffProgress: spriteHandoffProgress,
                    isHandoffCollapsing: spriteHandoff?.direction == .collapsing,
                    onSelectSession: { sessionId in
                        selectGrassSession(sessionId)
                    }
                )
                .environment(\.panelScale, panelScale)
                .frame(height: grassHeight, alignment: .bottom)
            }
        }
        .overlay(alignment: .topTrailing) {
            if shouldShowGrassIsland {
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isActivityCollapsed.toggle()
                    }
                }) {
                    Image(systemName: isActivityCollapsed ? "chevron.down" : "chevron.up")
                        .panelFont(size: 12, weight: .medium)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(8 * panelScale)
                }
                .buttonStyle(.plain)
                .offset(y: grassHeight - 30)
                .padding(.trailing, 30)
            }
        }
        .clipShape(notchClipShape)
        .overlay {
            if !isExpanded && launchGlowVisible {
                LaunchIridescentGlow(
                    progress: launchGlowProgress,
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius,
                    systemNotchPath: panelManager.systemNotchPath,
                    reduceMotion: accessibilityReduceMotion
                )
                .padding(-LaunchIridescentGlow.bleed)
            }
        }
        .shadow(
            color: isExpanded
                ? .black.opacity(0.7)
                : (panelManager.isCollapsedHovered ? .black.opacity(0.3) : .clear),
            radius: 6
        )
        .offset(x: collapsedContentOffsetX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(panelAnimation, value: isExpanded)
        .animation(.easeInOut(duration: 0.18), value: collapsedMode)
        .animation(collapsedHoverAnimation, value: panelManager.isCollapsedHovered)
        .animation(launchWavePreparationAnimation, value: isLaunchWavePreparing)
        .onAppear(perform: startLaunchGlow)
        .task {
            await startLaunchWave()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchiShouldCollapse)) { _ in
            if let activeSession, !activeSession.pendingQuestions.isEmpty {
                sessionStore.cancelPendingQuestion(in: activeSession.sessionKey)
                return
            }
            panelManager.collapse()
        }
        .onChange(of: isExpanded) { wasExpanded, expanded in
            startSpriteHandoff(
                for: expanded,
                keepsGrassIslandRendered: wasExpanded && !showingPanelSettings
            )
            updateKeyboardFocus(for: expanded)
            if !expanded {
                showingPanelSettings = false
                settingsPath = []
                showingSessionActivity = false
                showingUsageDetail = false
                usageDetailProvider = nil
                hoveredSessionId = nil
            }
        }
        .onChange(of: sessionStore.activeSessionCount) { _, count in
            if count < 2 {
                showingSessionActivity = false
            }
        }
        .onChange(of: isCollapsedRingVisible) { _, _ in
            panelManager.refreshIdleMode()
        }
        .onChange(of: collapsedExtraWidth.left) { _, _ in syncCollapsedExtraWidth() }
        .onChange(of: collapsedExtraWidth.right) { _, _ in syncCollapsedExtraWidth() }
        .onAppear(perform: syncCollapsedExtraWidth)
    }

    @ViewBuilder
    private var notchLayout: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .center, spacing: 0) {
                headerRow
                    .frame(height: notchSize.height)

                if isExpanded {
                    Spacer()
                        .frame(height: notchSize.height * (panelScale - 1))

                    ExpandedPanelView(
                        sessionStore: sessionStore,
                        usageService: usageService,
                        codexUsageService: CodexUsageService.shared,
                        usageDetailProvider: usageDetailProvider,
                        showingSettings: $showingPanelSettings,
                        settingsPath: $settingsPath,
                        showingSessionActivity: $showingSessionActivity,
                        showingUsageDetail: $showingUsageDetail,
                        isActivityCollapsed: $isActivityCollapsed,
                        hoveredSessionId: $hoveredSessionId
                    )
                    .environment(\.panelScale, panelScale)
                    .frame(
                        width: NotchConstants.expandedPanelContentWidth * panelScale,
                        height: expandedPanelHeight * panelScale
                    )
                    .transition(expandedChromeTransition)
                }
            }

            if isExpanded {
                HStack {
                    if shouldShowBackButton {
                        backButton
                            .padding(.leading, 15 * panelScale)
                    } else {
                        HStack(spacing: 8 * panelScale) {
                            PanelHeaderButton(
                                sfSymbol: panelManager.isPinned ? "pin.fill" : "pin",
                                action: { panelManager.togglePin() }
                            )
                            PanelHeaderButton(
                                sfSymbol: isMuted ? "bell.slash" : "bell",
                                action: toggleMute
                            )
                        }
                        .padding(.leading, 12 * panelScale)
                    }
                    Spacer()
                    headerButtons
                }
                .padding(.top, Self.expandedHeaderTopPadding * panelScale)
                .padding(.horizontal, 8 * panelScale)
                .environment(\.panelScale, panelScale)
                .frame(
                    width: NotchConstants.expandedPanelContentWidth * panelScale,
                    height: Self.expandedHeaderRowHeight * panelScale,
                    alignment: .top
                )
                .transition(expandedHeaderTransition)
            }
        }
    }

    private var headerButtons: some View {
        HStack(spacing: 8 * panelScale) {
            if !showingPanelSettings {
                PanelHeaderButton(
                    sfSymbol: "gearshape",
                    showsIndicator: updateManager.hasPendingUpdate,
                    action: {
                        haptics.playNavigationTap()
                        settingsPath = []
                        showingPanelSettings = true
                    }
                )
            } else {
                PanelHeaderButton(
                    sfSymbol: panelManager.isPinned ? "pin.fill" : "pin",
                    action: { panelManager.togglePin() }
                )
            }
            PanelHeaderButton(sfSymbol: "xmark", action: { panelManager.collapse() })
        }
        .padding(.trailing, 8)
    }

    private var backButton: some View {
        Button(action: goBack) {
            HStack(spacing: 5 * panelScale) {
                Image(systemName: "chevron.left")
                    .panelFont(size: 11, weight: .semibold)
                Text("Back")
                    .panelFont(size: 12, weight: .medium)
            }
            .foregroundColor(.white.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    private func goBack() {
        if showingPanelSettings {
            switch SettingsScreen.backAction(for: settingsPath) {
            case .popScreen:
                settingsPath.removeLast()
            case .exitSettings:
                showingPanelSettings = false
            }
        } else if showingUsageDetail {
            showingUsageDetail = false
            usageDetailProvider = nil
        } else if showingSessionActivity {
            showingSessionActivity = false
            sessionStore.clearSelectedSession()
        }
    }

    private func selectGrassSession(_ sessionId: String) {
        showingUsageDetail = false
        usageDetailProvider = nil
        guard sessionStore.activeSessionCount >= 2 else {
            if let sessionKey = ProviderSessionKey(stableId: sessionId),
               let session = sessionStore.session(for: sessionKey) {
                TerminalJumpService.shared.jump(to: session)
            }
            return
        }

        let shouldPlayHaptic = sessionStore.selectedSessionId != sessionId || !showingSessionActivity
        if shouldPlayHaptic {
            haptics.playSessionSelection()
        }

        if let session = sessionStore.selectSession(matchingStableId: sessionId) {
            TerminalJumpService.shared.jump(to: session)
        }
        showingSessionActivity = true
    }

    @ViewBuilder
    private var headerRow: some View {
        if isCompactIdle && launchWave == nil && !isLaunchWavePreparing {
            Color.clear
                .frame(width: compactContentWidth)
        } else {
            HStack(spacing: 0) {
                sideView(side: .left)

                Color.clear
                    .frame(width: notchSize.width - cornerRadiusInsets.closed.top - sideWidth)

                sideView(side: .right)
            }
        }
    }

    @ViewBuilder
    private func sideView(side: NotchSide) -> some View {
        let items = items(on: side)
        if items.isEmpty {
            Color.clear.frame(width: sideWidth)
        } else if !usesRowLayout(on: side) {
            spriteSlot(content: spriteContent(for: items[0], side: side), side: side)
                .simultaneousGesture(collapsedSpriteGesture(for: items[0], side: side))
        } else {
            rowSlot(side: side)
        }
    }

    private func collapsedSpriteGesture(for content: NotchSlotContent, side: NotchSide) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isExpanded else { return }
                guard let session = sessionForSprite(content, excluding: excludedProvider(for: side)) else { return }
                sessionStore.selectSession(matchingStableId: session.id)
                showingSessionActivity = true
                panelManager.expand()
            }
    }

    private var usageDetailGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isExpanded else { return }
                isActivityCollapsed = false
                usageDetailProvider = ringProvider
                showingUsageDetail = true
                panelManager.expand()
            }
    }

    /// Items in their configured order, reading left to right, kept clear of the notch.
    @ViewBuilder
    private func rowSlot(side: NotchSide) -> some View {
        let visible = visibleItems(on: side)
        if !visible.isEmpty, !isLaunchWaveActive {
            // The reset countdown is derived from the current time, so it needs its own tick.
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                HStack(spacing: Self.itemSpacing) {
                    ForEach(visible) { item in
                        rowItem(item, side: side)
                    }
                }
            }
            .padding(side == .left ? .trailing : .leading, rowInnerInset)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                if side == .left { leftContentWidth = width } else { rightContentWidth = width }
            }
            .opacity(collapsedHeaderSpriteVisuals.opacity)
            .animation(collapsedHeaderSpriteVisibilityAnimation, value: isExpanded)
            .frame(width: sideWidth + extraWidth(on: side), alignment: side == .left ? .trailing : .leading)
            .scaleEffect(collapsedHeaderSpriteScale, anchor: .bottom)
            .offset(x: ringOffsetX(side: side), y: collapsedUsageRingOffsetY)
        } else {
            Color.clear.frame(width: sideWidth)
        }
    }

    @ViewBuilder
    private func rowItem(_ item: NotchSlotContent, side: NotchSide) -> some View {
        switch item {
        case .usageRing:
            collapsedRing
                .contentShape(Rectangle())
                .simultaneousGesture(usageDetailGesture)
        case .resetRing:
            collapsedResetRing
                .contentShape(Rectangle())
                .simultaneousGesture(usageDetailGesture)
        case .spend:
            collapsedSpend
                .contentShape(Rectangle())
                .simultaneousGesture(usageDetailGesture)
        case .latest, .claude, .codex:
            if let content = spriteContent(for: item, side: side) {
                SessionSpriteView(
                    state: content.state,
                    isPrimarySprite: true,
                    mirrorSeed: content.mirrorSeed,
                    animationStartDate: content.startedAt,
                    repeatsAnimation: content.repeatsAnimation
                )
                .scaleEffect(content.scale, anchor: .bottom)
                .frame(width: sideWidth * 0.7)
                .contentShape(Rectangle())
                .simultaneousGesture(collapsedSpriteGesture(for: item, side: side))
            }
        }
    }

    @ViewBuilder
    private func spriteSlot(content: HeaderSpriteContent?, side: NotchSide) -> some View {
        if let content {
            SessionSpriteView(
                state: content.state,
                isPrimarySprite: true,
                mirrorSeed: content.mirrorSeed,
                animationStartDate: content.startedAt,
                repeatsAnimation: content.repeatsAnimation
            )
            .scaleEffect(collapsedHeaderSpriteScale * content.scale, anchor: .bottom)
            .offset(x: content.xOffset)
            .offset(x: spriteOffsetX(side: side), y: collapsedHeaderSpriteOffsetY)
            .frame(width: sideWidth)
            .opacity(collapsedHeaderSpriteVisuals.opacity)
            .blur(radius: collapsedHeaderSpriteVisuals.blur)
            .animation(collapsedHeaderSpriteVisibilityAnimation, value: isExpanded)
        } else {
            Color.clear.frame(width: sideWidth)
        }
    }

    private func syncCollapsedExtraWidth() {
        let extra = collapsedExtraWidth
        panelManager.setCollapsedExtraWidth(left: extra.left, right: extra.right)
    }

    private func startSpriteHandoff(for expanded: Bool, keepsGrassIslandRendered: Bool) {
        spriteHandoffGeneration += 1
        let generation = spriteHandoffGeneration

        guard let activeSession, panelMode != .compact else {
            spriteHandoff = nil
            spriteHandoffProgress = 0
            return
        }

        let animationDuration = SpriteHandoffTiming.animationDuration(for: expanded)

        spriteHandoff = SpriteHandoff(
            direction: expanded ? .expanding : .collapsing,
            sessionId: activeSession.id,
            keepsGrassIslandRendered: keepsGrassIslandRendered
        )
        spriteHandoffProgress = 0

        withAnimation(.easeOut(duration: animationDuration)) {
            spriteHandoffProgress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: SpriteHandoffTiming.cleanupDelay(for: expanded))
            guard generation == spriteHandoffGeneration else { return }
            spriteHandoff = nil
            spriteHandoffProgress = 0
        }
    }

    private func updateKeyboardFocus(for expanded: Bool) {
        guard expanded,
              let panel = NSApp.windows.first(where: { $0 is NotchPanel }) else { return }
        panel.makeKey()
    }

    private func startLaunchGlow() {
        guard !Self.hasPlayedLaunchGlow else { return }
        Self.hasPlayedLaunchGlow = true

        guard !accessibilityReduceMotion else { return }

        let duration = LaunchIridescentGlowTiming.duration(reduceMotion: accessibilityReduceMotion)
        launchGlowProgress = 0
        launchGlowVisible = true

        Task {
            // Commit the hidden 0 state before animating so the glow blooms from nothing.
            await Task.yield()
            withAnimation(.linear(duration: duration)) {
                launchGlowProgress = 1
            }

            try? await Task.sleep(for: .seconds(duration))
            launchGlowVisible = false
        }
    }

    private func startLaunchWave() async {
        guard !Self.hasPlayedLaunchWave else { return }

        let provider = AppSettings.lastUsedAgentProvider
        launchSpriteFamily = provider.spriteFamily

        isLaunchWavePreparing = true

        try? await Task.sleep(for: .seconds(LaunchWaveTiming.startDelay))

        guard !Task.isCancelled, !Self.hasPlayedLaunchWave else {
            isLaunchWavePreparing = false
            return
        }

        Self.hasPlayedLaunchWave = true
        isLaunchWavePreparing = false
        launchWave = LaunchWave(
            state: NotchiState(task: .waving, spriteFamily: provider.spriteFamily),
            startedAt: Date()
        )

        try? await Task.sleep(for: .seconds(NotchiState.launchWaveDuration))

        guard !Task.isCancelled else {
            launchWave = nil
            return
        }

        withAnimation(launchWavePreparationAnimation) {
            launchWave = nil
        }
    }

    private func toggleMute() {
        haptics.playToggle()
        AppSettings.toggleMute()
        isMuted = AppSettings.isMuted
    }
}

#Preview {
    NotchContentView()
        .frame(width: 400, height: 200)
}
