import Testing
@testable import Kamikaze

struct CameraRunFlowTests {
    @Test func recordersAttachOnlyToAFullyRunningPreview() {
        #expect(CameraRunStartGate(
            isPreparingPreview: false,
            isSessionRunning: true,
            activeMode: .singleCamera
        ).canAttachRecorders)

        #expect(!CameraRunStartGate(
            isPreparingPreview: true,
            isSessionRunning: true,
            activeMode: .singleCamera
        ).canAttachRecorders)
        #expect(!CameraRunStartGate(
            isPreparingPreview: false,
            isSessionRunning: false,
            activeMode: .singleCamera
        ).canAttachRecorders)
        #expect(!CameraRunStartGate(
            isPreparingPreview: false,
            isSessionRunning: true,
            activeMode: nil
        ).canAttachRecorders)
    }
}
