import SwiftUI

// Shared layout tokens keep the settings panel spacing consistent across rows and pickers.
@MainActor
enum SettingsLayout {
    static var scale: CGFloat = 1

    static var panelHorizontalPadding: CGFloat { 14 * scale }
    static var topPadding: CGFloat { 5 * scale }
    static var sectionSpacing: CGFloat { 8 * scale }
    static var rowVerticalPadding: CGFloat { 4 * scale }
    static var apiKeySpacing: CGFloat { 4 * scale }
    static var fieldHorizontalPadding: CGFloat { 8 * scale }
    static var fieldVerticalPadding: CGFloat { 5 * scale }
    static var fieldLeadingInset: CGFloat { 28 * scale }
    static var quitButtonVerticalPadding: CGFloat { 8 * scale }
    static var quitButtonHorizontalPadding: CGFloat { 4 * scale }
    static var pickerInset: CGFloat { 6 * scale }
    static var pickerOptionHorizontalPadding: CGFloat { 10 * scale }
    static var pickerOptionVerticalPadding: CGFloat { 5 * scale }
    static var pickerRowHeight: CGFloat { 28 * scale }
    static var pickerRowSpacing: CGFloat { 4 * scale }

    static func pickerViewportHeight(rowCount: Int, maxVisibleRows: Int = 6) -> CGFloat {
        let visibleCount = min(rowCount, maxVisibleRows)
        return CGFloat(visibleCount) * pickerRowHeight
            + CGFloat(max(visibleCount - 1, 0)) * pickerRowSpacing
    }
}
