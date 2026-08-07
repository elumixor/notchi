import Foundation

@MainActor
@Observable
final class SoundSelector {
    var isPickerExpanded = false

    func expandedHeight(customSoundCount: Int) -> CGFloat {
        let soundCount = 1 + customSoundCount + NotificationSound.allCases.count
        return SettingsLayout.pickerViewportHeight(rowCount: soundCount)
    }
}
