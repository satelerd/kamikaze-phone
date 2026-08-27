import CoreGraphics
import Testing
@testable import Kamikaze

struct CameraRunVideoOrientationPolicyTests {
    @Test
    func frontAndRearUseTheirPhysicalPortraitRotations() {
        #expect(CameraRunVideoOrientationPolicy.portraitRotationAngle(for: .front) == 270)
        #expect(CameraRunVideoOrientationPolicy.portraitRotationAngle(for: .rear) == 90)
    }

    @Test
    func frontPixelsAreNotMirroredAgainAfterPortraitRotation() {
        #expect(CameraRunVideoOrientationPolicy.connectionIsMirrored(for: .front) == false)
        #expect(CameraRunVideoOrientationPolicy.connectionIsMirrored(for: .rear) == false)
    }

    @Test
    func writerDoesNotRotateAlreadyPortraitCapturePixelsAgain() {
        let front = CameraRunVideoOrientationPolicy.recordingTransform(for: .front)
        let rear = CameraRunVideoOrientationPolicy.recordingTransform(for: .rear)
        #expect(front == .identity)
        #expect(rear == .identity)
    }
}
