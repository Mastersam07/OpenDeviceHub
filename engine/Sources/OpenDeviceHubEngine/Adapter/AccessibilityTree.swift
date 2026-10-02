import CoreGraphics
import Foundation
import OpenDeviceHubPrivate

/// One element of a guest app's accessibility tree.
public struct AccessibilityElement: Codable, Sendable, Hashable {
    public var role: String?
    public var roleDescription: String?
    public var label: String?
    public var title: String?
    public var identifier: String?
    public var value: String?
    /// In the guest's points.
    public var frame: CGRect
    public var children: [AccessibilityElement]

    /// The centre in the portrait native coordinates `tap` takes, undoing the guest's rotation.
    /// Nil for an empty frame or a centre off screen.
    public func normalizedCenter(in screen: CGRect, orientation: DeviceOrientation = .portrait) -> CGPoint? {
        guard screen.width > 0, screen.height > 0, !frame.isEmpty else { return nil }
        let point = CGPoint(
            x: (frame.midX - screen.minX) / screen.width,
            y: (frame.midY - screen.minY) / screen.height
        )
        guard (0...1).contains(point.x), (0...1).contains(point.y) else { return nil }
        return CoordinateMapper.portraitNativePoint(from: point, orientation: orientation)
    }
}

// On Xcode 27 (27A266a), AXPTranslator traps on the main thread and when supportsDelegateTokens or
// accessibilityEnabled is set. The work queue keeps reads off main and serializes the singleton.
final class AccessibilityTreeReader: @unchecked Sendable {
    private static let maximumDepth = 64
    private static let workQueue = DispatchQueue(label: "\(Brand.commandName).accessibility.work")

    private let device: any ODHSimDevice
    private let timeout: DispatchTimeInterval

    init(device: any ODHSimDevice, timeout: DispatchTimeInterval = .seconds(2)) {
        self.device = device
        self.timeout = timeout
    }

    /// `async` and a wait, not `sync`, which may run the block on the calling main thread.
    func read() throws -> AccessibilityElement {
        let handoff = Handoff<Result<AccessibilityElement, any Error>>()
        Self.workQueue.async { [self] in
            handoff.set(Result { try readOnWorkQueue() })
        }
        guard let result = handoff.wait(timeout: .distantFuture) else {
            throw EngineError.privateCall(symbol: "AXPTranslator", message: "the read ended without a result")
        }
        return try result.get()
    }

    private func readOnWorkQueue() throws -> AccessibilityElement {
        let translator = try Self.translator()
        let token = UUID().uuidString
        // Held weakly by the translator, so this frame keeps it alive.
        let delegate = AccessibilityBridgeDelegate(device: device, timeout: timeout)
        translator.setBridgeTokenDelegate(delegate)
        defer { translator.setBridgeTokenDelegate(nil) }

        guard let translation = translator.frontmostApplication(withDisplayId: 0, bridgeDelegateToken: token) else {
            throw EngineError.capabilityUnavailable(
                name: "the accessibility tree, no app answered and the guest may still be starting"
            )
        }
        try Self.setToken(token, on: translation)
        guard let root = translator.macPlatformElement(fromTranslation: translation) else {
            throw EngineError.privateCall(
                symbol: "-[AXPTranslator macPlatformElementFromTranslation:]",
                message: "no element for the frontmost app"
            )
        }
        return try element(from: root, token: token, depth: 0)
    }

    private func element(from object: Any, token: String, depth: Int) throws -> AccessibilityElement {
        try AccessibilitySelectorCheck.require(on: object as AnyObject, selectors: [
            "translation", "accessibilityChildren", "accessibilityRole", "accessibilityRoleDescription",
            "accessibilityLabel", "accessibilityTitle", "accessibilityIdentifier", "accessibilityValue",
            "accessibilityFrame",
        ])
        // Bit cast, not `as?`: the private classes do not formally adopt these protocols.
        let platform = unsafeBitCast(object as AnyObject, to: (any ODHAXPMacPlatformElement).self)
        // Without the token, the element's requests reach no delegate.
        if let translation = platform.translation {
            try Self.setToken(token, on: translation)
        }
        let children = try depth < Self.maximumDepth
            ? (platform.accessibilityChildren ?? []).map { try element(from: $0, token: token, depth: depth + 1) }
            : []

        return AccessibilityElement(
            role: platform.accessibilityRole,
            roleDescription: platform.accessibilityRoleDescription,
            label: platform.accessibilityLabel.nonEmpty,
            title: platform.accessibilityTitle.nonEmpty,
            identifier: platform.accessibilityIdentifier.nonEmpty,
            value: platform.accessibilityValue.map { "\($0)" }.nonEmpty,
            frame: platform.accessibilityFrame,
            children: children
        )
    }

    private static func setToken(_ token: String, on translation: Any) throws {
        try AccessibilitySelectorCheck.require(on: translation as AnyObject, selectors: ["setBridgeDelegateToken:"])
        unsafeBitCast(translation as AnyObject, to: (any ODHAXPTranslationObject).self)
            .setBridgeDelegateToken(token)
    }

    private static func translator() throws -> any ODHAXPTranslator {
        guard let classObject = NSClassFromString("AXPTranslator").map({ $0 as AnyObject }),
              classObject.responds(to: NSSelectorFromString("sharedInstance")),
              let shared = unsafeBitCast(classObject, to: (any ODHAXPTranslatorClass).self).sharedInstance() else {
            throw EngineError.symbolNotFound(
                name: "+[AXPTranslator sharedInstance]",
                framework: PrivateFramework.accessibilityPlatformTranslation.rawValue
            )
        }
        try AccessibilitySelectorCheck.require(on: shared as AnyObject, selectors: [
            "setBridgeTokenDelegate:", "frontmostApplicationWithDisplayId:bridgeDelegateToken:",
            "macPlatformElementFromTranslation:",
        ])
        return unsafeBitCast(shared as AnyObject, to: (any ODHAXPTranslator).self)
    }
}

enum AccessibilitySelectorCheck {
    static func require(on object: AnyObject, selectors: [String]) throws {
        for name in selectors where !object.responds(to: NSSelectorFromString(name)) {
            throw EngineError.symbolNotFound(
                name: "-[\(type(of: object)) \(name)]",
                framework: PrivateFramework.accessibilityPlatformTranslation.rawValue
            )
        }
    }
}

/// The three required methods of `AXPTranslationTokenDelegateHelper`, a protocol only visible at runtime.
final class AccessibilityBridgeDelegate: NSObject {
    typealias BridgeCallback = @convention(block) (AnyObject?) -> AnyObject?

    private let device: any ODHSimDevice
    private let timeout: DispatchTimeInterval
    /// Answers land here because the caller blocks while it waits.
    private let queue = DispatchQueue(label: "\(Brand.commandName).accessibility")

    private static let conformance: Void = {
        if let helper = objc_getProtocol("AXPTranslationTokenDelegateHelper") {
            class_addProtocol(AccessibilityBridgeDelegate.self, helper)
        }
    }()

    init(device: any ODHSimDevice, timeout: DispatchTimeInterval) {
        _ = Self.conformance
        self.device = device
        self.timeout = timeout
        super.init()
    }

    @objc(accessibilityTranslationDelegateBridgeCallbackWithToken:)
    func bridgeCallback(withToken token: String) -> BridgeCallback {
        { [device, queue, timeout] request in
            guard let request else { return Self.emptyResponse() }
            let handoff = Handoff<AnyObject?>()
            device.sendAccessibilityRequestAsync(request, completionQueue: queue) { response in
                handoff.set(response as AnyObject?)
            }
            return handoff.wait(timeout: .now() + timeout).flatMap { $0 } ?? Self.emptyResponse()
        }
    }

    /// Frames already come back in the guest's points.
    @objc(accessibilityTranslationConvertPlatformFrameToSystem:withToken:)
    func convertPlatformFrameToSystem(_ frame: CGRect, withToken token: String) -> CGRect {
        frame
    }

    @objc(accessibilityTranslationRootParentWithToken:)
    func rootParent(withToken token: String) -> AnyObject? {
        nil
    }

    /// The translator does not expect nil from the callback.
    private static func emptyResponse() -> AnyObject? {
        let selector = NSSelectorFromString("emptyResponse")
        guard let responseClass = NSClassFromString("AXPTranslatorResponse").map({ $0 as AnyObject }),
              responseClass.responds(to: selector) else { return nil }
        return responseClass.perform(selector)?.takeUnretainedValue()
    }
}

private final class Handoff<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var value: Value?

    func set(_ value: Value) {
        lock.withLock { self.value = value }
        semaphore.signal()
    }

    func wait(timeout: DispatchTime) -> Value? {
        guard semaphore.wait(timeout: timeout) == .success else { return nil }
        return lock.withLock { value }
    }
}

private extension Optional<String> {
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
