import CoreMedia
import Foundation

/// The timer and converted camera timestamps share the mach host clock.
enum HostClock {
    static var now: Double { CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())) }
}

enum SprintError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

