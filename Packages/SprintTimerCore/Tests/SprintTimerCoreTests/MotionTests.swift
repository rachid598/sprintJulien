import Testing
@testable import SprintTimerCore

struct MotionTests {
    @Test func testStaticSceneDoesNotTriggerAndMotionScoreIsNormalized() {
        var detector = MotionDetectionService(threshold: 0.1, cooldown: 1)
        #expect(!(detector.process(luminance: [0, 0, 0, 0], timestamp: 1).triggered))
        #expect(!(detector.process(luminance: [0, 0, 0, 0], timestamp: 2).triggered))
        let detection = detector.process(luminance: [255, 255, 255, 255], timestamp: 3)
        #expect(detection.score == 1)
        #expect(detection.triggered)
        #expect(!(detector.process(luminance: [0, 0, 0, 0], timestamp: 5).triggered))
        #expect(!(detector.process(luminance: [255, 255, 255, 255], timestamp: 6).triggered))
    }

    @Test func testRequiresCalmRearmAndCooldownWithoutDelayedDuplicate() {
        var detector = MotionDetectionService(threshold: 0.1, cooldown: 2)
        _ = detector.process(luminance: [0], timestamp: 0)
        #expect(detector.process(luminance: [255], timestamp: 1).triggered)
        _ = detector.process(luminance: [255], timestamp: 1.1)
        _ = detector.process(luminance: [255], timestamp: 1.2)
        #expect(detector.isArmed)
        #expect(!(detector.process(luminance: [0], timestamp: 1.3).triggered))
        #expect(!(detector.isArmed))
        #expect(!(detector.process(luminance: [255], timestamp: 4).triggered))
        _ = detector.process(luminance: [255], timestamp: 4.1)
        _ = detector.process(luminance: [255], timestamp: 4.2)
        #expect(detector.process(luminance: [0], timestamp: 4.3).triggered)
    }

    @Test func testPartialRegionMovementUsesMeanDifference() {
        var detector = MotionDetectionService(threshold: 0.3)
        _ = detector.process(luminance: [0, 0, 0, 0], timestamp: 1)
        let detection = detector.process(luminance: [255, 0, 0, 0], timestamp: 2)
        #expect(detection.score == 0.25)
        #expect(!(detection.triggered))
    }

    @Test func testResolutionChangeAndBackwardClockRebaseline() {
        var detector = MotionDetectionService()
        _ = detector.process(luminance: [0], timestamp: 10)
        #expect(!(detector.process(luminance: [255, 255], timestamp: 11).triggered))
        #expect(!(detector.process(luminance: [0, 0], timestamp: 9).triggered))
        #expect(detector.process(luminance: [255, 255], timestamp: 10).triggered)
        detector.reset()
        #expect(!(detector.process(luminance: [0, 0], timestamp: 11).triggered))
        #expect(!(detector.process(luminance: [], timestamp: 12).triggered))
        #expect(!(detector.process(luminance: [0, 0], timestamp: .nan).triggered))
    }
}
