import Foundation

/// What the guest says about itself that simctl does not. Xcode 27's `devicectl` sees simulators;
/// Xcode 26's does not, so every answer here is optional.
public struct DevicectlService: Sendable {
    private let run: @Sendable ([String]) -> String?

    public init() {
        self.init { arguments in
            guard let result = try? ProcessRunner.run("/usr/bin/xcrun", arguments),
                  result.status == 0 else { return nil }
            return result.standardOutput
        }
    }

    init(run: @escaping @Sendable ([String]) -> String?) {
        self.run = run
    }

    /// Five seconds is the shortest timeout `devicectl` accepts.
    static func orientationArguments(udid: String) -> [String] {
        ["devicectl", "device", "orientation", "get", "--device", udid,
         "--timeout", "5", "--quiet", "--json-output", "-"]
    }

    /// On a foldable the first answer after a turn repeats the answer given before it, however long
    /// ago the turn was (27A266a, 27A9269), so a foldable is asked twice and the second answer kept.
    /// An ordinary iPhone answers right the first time (27A9269), and each ask costs 150 to 400 ms.
    public func orientation(udid: String, foldable: Bool) -> DeviceOrientation? {
        let arguments = Self.orientationArguments(udid: udid)
        if foldable { guard run(arguments) != nil else { return nil } }
        guard let output = run(arguments) else { return nil }
        return Self.parseOrientation(Data(output.utf8))
    }

    /// `devicectl` names the side the device is turned towards and the viewer names the way the
    /// picture turns, so the two landscapes swap. The plain value reads unknown until the device is
    /// first turned (27A266a) and says nothing useful while it lies flat, so the non flat one is read.
    static func parseOrientation(_ data: Data) -> DeviceOrientation? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let name = result["deviceOrientationNonFlat"] as? String else { return nil }
        switch name {
        case "portrait": return .portrait
        case "portraitUpsideDown": return .portraitUpsideDown
        case "landscapeRight": return .landscapeLeft
        case "landscapeLeft": return .landscapeRight
        default: return nil
        }
    }
}
