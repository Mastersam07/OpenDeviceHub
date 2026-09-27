import XCTest
import OpenDeviceHubEngine

final class OrdinaryButtonTests: XCTestCase {
    func testTheCameraControlTakesAPictureOnAnOrdinaryIPhone() async throws {
        try IntegrationGate.requireEnabled()
        let adapter = try AdapterFactory.make(for: XcodeLocator.locate())
        guard let device = try adapter.devices().first(where: {
            $0.state == .booted && DeviceTypeProfile.hasCameraControl(deviceType: $0.deviceTypeIdentifier)
                && DeviceTypeProfile.displays(forDeviceType: $0.deviceTypeIdentifier).count == 1
        }) else {
            throw XCTSkip("boot an ordinary iPhone with a camera control to run this test")
        }
        let session = try adapter.openInput(device.udid)
        defer { session.close() }

        let before = photos(on: device.udid)
        let pressed = ContinuousClock.now
        try await session.button(.cameraControl, phase: .down)
        try await Task.sleep(for: .milliseconds(60))
        try await session.button(.cameraControl, phase: .up)
        // A just booted guest can take several seconds over its first screenshot.
        while photos(on: device.udid) == before, ContinuousClock.now - pressed < .seconds(15) {
            try await Task.sleep(for: .milliseconds(100))
        }
        print("RESULT \(device.name) \(device.runtimeName): camera roll \(before) -> \(photos(on: device.udid)) after \(ContinuousClock.now - pressed)")
        XCTAssertEqual(photos(on: device.udid), before + 1, "the camera control did not take a picture")
    }

    private func photos(on udid: String) -> Int {
        let roll = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Developer/CoreSimulator/Devices/\(udid)/data/Media/DCIM")
        guard let files = FileManager.default.enumerator(at: roll, includingPropertiesForKeys: nil) else { return 0 }
        return files.compactMap { $0 as? URL }.filter { $0.lastPathComponent.hasPrefix("IMG_") }.count
    }
}
