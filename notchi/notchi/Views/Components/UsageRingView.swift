import SwiftUI

struct UsageRingView: View {
    let percentage: Int
    var diameter: CGFloat = 15
    var lineWidth: CGFloat = 3
    var isStale: Bool = false
    /// Text drawn in the middle of the ring, for example the percentage.
    var label: String? = nil

    @State private var drawProgress: CGFloat = 0

    private var clampedPercentage: Int {
        min(max(percentage, 0), 100)
    }

    private var ringColor: Color {
        let base: Color
        switch clampedPercentage {
        case ..<50: base = TerminalColors.green
        case ..<80: base = TerminalColors.amber
        default: base = TerminalColors.red
        }
        return isStale ? base.opacity(0.5) : base
    }

    var body: some View {
        ZStack {
            UsageRingArc(fraction: Double(drawProgress))
                .stroke(
                    ringColor.opacity(0.28),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                )
            UsageRingArc(fraction: Double(clampedPercentage) / 100 * Double(drawProgress))
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            if let label {
                Text(label)
                    .font(.system(size: diameter * 0.36, weight: .semibold).monospacedDigit())
                    .foregroundColor(ringColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(lineWidth + 1)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) { drawProgress = 1 }
        }
        .animation(.easeInOut(duration: 0.3), value: clampedPercentage)
    }
}

private struct UsageRingArc: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * fraction),
            clockwise: false
        )
        return path
    }
}

#Preview {
    HStack(spacing: 12) {
        UsageRingView(percentage: 25)
        UsageRingView(percentage: 65)
        UsageRingView(percentage: 95)
    }
    .padding()
    .background(Color.black)
}
