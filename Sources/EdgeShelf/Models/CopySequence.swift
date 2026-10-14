import Foundation

/// Counts physical C presses. Releasing Command is allowed between presses.
struct CopySequence {
    private var count = 0
    private var lastTime: TimeInterval = 0
    var hasPendingPresses: Bool { count > 0 }

    mutating func press(isCommandC: Bool, isRepeat: Bool, time: TimeInterval,
                        required: Int, interval: TimeInterval) -> Bool {
        guard !isRepeat else { return false }
        guard isCommandC else { reset(); return false }
        count = time - lastTime <= interval ? count + 1 : 1
        lastTime = time
        if count >= max(2, required) { reset(); return true }
        return false
    }

    mutating func reset() { count = 0; lastTime = 0 }
}
