import Foundation
import Testing
@testable import SprintTimerCore

struct TimingTests {
    @Test func testStartStopAndResetKeepMonotoneReference() {
        var engine = TimingEngine()
        #expect(engine.state == .idle)
        #expect(engine.elapsed(at: 1234) == 0)
        engine.start(at: 100)
        engine.start(at: 101)
        #expect(engine.startHostSeconds == 100)
        #expect(abs((engine.elapsed(at: 112.345)) - (12.345)) <= 0.0000001)
        engine.stop(at: 112.345)
        #expect(engine.state == .stopped)
        #expect(abs((engine.elapsed(at: 999)) - (12.345)) <= 0.0000001)
        engine.start(at: 500)
        #expect(engine.state == .stopped)
        engine.reset()
        #expect(engine.startHostSeconds == nil)
        engine.start(at: 500)
        #expect(engine.elapsed(at: 501) == 1)
    }

    @Test func testOffsetIsAppliedOnceWithDocumentedSign() {
        var engine = TimingEngine()
        engine.start(at: 100, offset: 0.25)
        #expect(engine.startEventHostSeconds == 100)
        #expect(engine.startHostSeconds == 99.75)
        #expect(engine.elapsed(at: 110) == 10.25)
        engine.stop(at: 110)
        #expect(engine.elapsed(at: 111) == 10.25)
        engine.reset()
        engine.start(at: 100, offset: -0.25)
        #expect(engine.elapsed(at: 100.1) == 0)
        #expect(engine.elapsed(at: 110) == 9.75)
    }

    @Test func testInvalidInputsCannotStartOrStopRace() {
        var engine = TimingEngine()
        engine.start(at: .nan)
        engine.start(at: 1, offset: .infinity)
        #expect(engine.state == .idle)
        engine.start(at: 10)
        engine.stop(at: 9)
        engine.stop(at: .infinity)
        #expect(engine.state == .running)
        #expect(engine.elapsed(at: .nan) == 0)
        #expect(engine.elapsed(at: 9) == 0)
    }

    @Test func testCentisecondDisplayCarriesAndUsesFrenchLocale() {
        #expect(TimeDisplay.format(1.25) == "1,25")
        #expect(TimeDisplay.format(9.999) == "10,00")
        #expect(TimeDisplay.format(60.01) == "60,01")
        #expect(TimeDisplay.format(-1) == "—")
        #expect(TimeDisplay.format(.nan) == "—")
    }
}

struct TimelineTests {
    private func frame(_ index: Int, _ elapsed: Double) -> FrameStamp {
        FrameStamp(index: index, presentationSeconds: 100 + elapsed, hostSeconds: 100 + elapsed, elapsedSeconds: elapsed)
    }

    @Test func testRealTimestampGapIsPreservedInPixelMapping() {
        let timeline = FrameTimeline(frames: [frame(0, 10), frame(1, 10.01), frame(2, 10.1)])
        #expect(timeline.isValid)
        #expect(timeline.time(atPixel: 0, stripWidth: 2) == 10)
        #expect(timeline.time(atPixel: 2.5, stripWidth: 2) == 10.01)
        #expect(timeline.time(atPixel: 4, stripWidth: 2) == 10.1)
        #expect(timeline.time(atPixel: 6, stripWidth: 2) == 10.1)
        #expect(abs((timeline.maxFrameGap ?? 0) - (0.09)) <= 0.000001)
        #expect(abs((timeline.effectiveFPS) - (20)) <= 0.000001)
        #expect(timeline.nearestIndex(elapsedSeconds: 10.06) == 2)
        #expect(timeline.nearestIndex(elapsedSeconds: -100) == 0)
        #expect(timeline.nearestIndex(elapsedSeconds: 1000) == 2)
        #expect(timeline.time(atPixel: -1, stripWidth: 2) == nil)
        #expect(timeline.time(atPixel: 7, stripWidth: 2) == nil)
        #expect(timeline.time(atPixel: 0, stripWidth: 0) == nil)
        #expect(timeline.nearestIndex(elapsedSeconds: .nan) == nil)
    }

    @Test func testNearestReturnsArrayOffsetForNonContiguousFrameIDs() {
        let timeline = FrameTimeline(frames: [frame(5, 1), frame(8, 2), frame(10, 3)])
        #expect(timeline.nearestIndex(elapsedSeconds: 2) == 1)
        #expect(timeline.nearestIndex(elapsedSeconds: 1.5) == 0)
    }

    @Test func testMalformedTimelinesAreRejectedWithoutSortingAwayEvidence() {
        for frames in [[frame(0, 2), frame(1, 1)], [frame(0, 1), frame(1, 1)], [frame(0, 1), frame(0, 2)], [frame(0, .nan)]] {
            let timeline = FrameTimeline(frames: frames)
            #expect(!(timeline.isValid))
            #expect(timeline.nearestIndex(elapsedSeconds: 1) == nil)
            #expect(timeline.time(atPixel: 0, stripWidth: 2) == nil)
            #expect(timeline.maxFrameGap == nil)
            #expect(timeline.effectiveFPS == 0)
            #expect(timeline.frames.count == frames.count)
        }
    }

    @Test func testEmptyAndSingleFrameHaveNoInventedFrameRate() {
        let empty = FrameTimeline(frames: [])
        #expect(empty.nearestIndex(elapsedSeconds: 0) == nil)
        #expect(empty.time(atPixel: 0, stripWidth: 1) == nil)
        #expect(empty.effectiveFPS == 0)
        let single = FrameTimeline(frames: [frame(0, 4.12)])
        #expect(single.time(atPixel: 0.5, stripWidth: 1) == 4.12)
        #expect(single.effectiveFPS == 0)
        #expect(single.maxFrameGap == nil)
    }
}
