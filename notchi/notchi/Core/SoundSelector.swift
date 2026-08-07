import Foundation

@MainActor
@Observable
final class SoundSelector {
    var isPickerExpanded = false

    func rowCount(customSoundCount: Int) -> Int {
        1 + customSoundCount + NotificationSound.displayOrder.count
    }
}
