import XCTest
import SprintTimerCore

final class BuildSmokeTests: XCTestCase {
    func testCoreProductIsLinkedOnIOS() {
        var engine = TimingEngine()
        engine.start(at: 100)
        XCTAssertEqual(engine.elapsed(at: 101.25), 1.25, accuracy: 0.000001)
    }
}
