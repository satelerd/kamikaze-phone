import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct MediaTimelineTests {
    @Test
    func markersShareInjectedMonotonicOrigin() throws {
        var timeline = CameraRunTimeline(originUptimeS: 100)
        _ = try timeline.mark(.preTalkStart, atUptimeS: 100, source: .frontCamera)
        _ = try timeline.mark(.preTalkEnd, atUptimeS: 101.25, source: .userInterface)
        _ = try timeline.mark(.throwStart, atUptimeS: 101.25, source: .motion)
        _ = try timeline.mark(.throwEnd, atUptimeS: 101.85, source: .motion)
        _ = try timeline.mark(.postTalkStart, atUptimeS: 102, source: .rearCamera)
        _ = try timeline.mark(.postTalkEnd, atUptimeS: 103, source: .rearCamera)

        #expect(timeline.isComplete)
        #expect(timeline.durationS == 3)
        let throwWindow = try #require(timeline.window(for: .throwSegment))
        #expect(abs(throwWindow.lowerBound - 1.25) < 1e-9)
        #expect(abs(throwWindow.upperBound - 1.85) < 1e-9)
        #expect(timeline.marker(for: .throwStart)?.source == .motion)
    }

    @Test
    func markerOrderAndClockRegressionAreRejected() throws {
        var timeline = CameraRunTimeline(originUptimeS: 50)
        do {
            _ = try timeline.mark(.throwStart, atUptimeS: 50, source: .motion)
            Issue.record("An out-of-order marker was accepted.")
        } catch let error as CameraRunTimelineError {
            #expect(error == .markerOutOfOrder(expected: .preTalkStart, received: .throwStart))
        }

        _ = try timeline.mark(.preTalkStart, atUptimeS: 50, source: .userInterface)
        do {
            _ = try timeline.mark(.preTalkEnd, atUptimeS: 49.9, source: .userInterface)
            Issue.record("A timestamp before the monotonic origin was accepted.")
        } catch let error as CameraRunTimelineError {
            #expect(error == .timestampBeforeOrigin)
        }
    }

    @Test
    @MainActor
    func editorChangesOnlyTheEditDescription() throws {
        let sourceFrames = [
            ReplayFrame(timestampMs: 0, progress: 0, quaternion: .identity, accelG: 1, gyroDps: 0),
            ReplayFrame(timestampMs: 1_000, progress: 1, quaternion: .identity, accelG: 1, gyroDps: 10)
        ]
        let timeline = CameraRunTimeline(originUptimeS: 10)
        let clip = try CameraRunDraftClip(replayFrames: sourceFrames, timeline: timeline)
        let editor = CameraRunEditorModel(clip: clip)
        #expect(editor.setTrim(startS: 0.2, endS: 0.8))
        #expect(editor.setLayout(CameraRunLayout(preset: .vertical, width: 540, height: 960)))
        #expect(editor.setCaptions([
            CameraRunCaption(text: "YOUR THROW", startS: 0.2, endS: 0.8, placement: .top)
        ]))

        #expect(editor.clip.replayFrames == sourceFrames)
        #expect(editor.clip.originalDurationS == 1)
        #expect(abs(editor.clip.trimmedDurationS - 0.6) < 1e-9)
        #expect(editor.clip.edit.captions.count == 1)
        #expect(editor.clip.edit.layout.height == 960)
    }
}
