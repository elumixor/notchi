import SwiftUI

/// Time left in a window, drawn as a ring that empties as the reset approaches,
/// with the remaining time written in the middle.
struct ResetRingView: View {
    /// Share of the window still ahead, 1 at the start and 0 at the reset.
    let fractionRemaining: Double
    let label: String
    var diameter: CGFloat = 22
    var lineWidth: CGFloat = 2

    private var clamped: Double { min(max(fractionRemaining, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.7), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.system(size: diameter * 0.36, weight: .semibold).monospacedDigit())
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(lineWidth + 1)
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.3), value: clamped)
    }
}
