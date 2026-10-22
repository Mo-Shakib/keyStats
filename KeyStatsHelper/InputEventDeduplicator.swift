import Foundation

/// Drops a posted copy only when the tap recently saw its matching hardware event.
/// This preserves standalone events created by accessibility tools.
struct InputEventDeduplicator {
    private var recentHardwareEvent: (type: UInt32, detail: Int64, time: TimeInterval)?
    private let duplicateWindow: TimeInterval = 0.08

    mutating func shouldDrop(type: UInt32, detail: Int64, sourcePID: Int64, time: TimeInterval) -> Bool {
        if sourcePID > 0,
           let previous = recentHardwareEvent,
           previous.type == type,
           previous.detail == detail,
           time >= previous.time,
           time - previous.time < duplicateWindow {
            return true
        }
        if sourcePID <= 0 {
            recentHardwareEvent = (type, detail, time)
        }
        return false
    }
}
