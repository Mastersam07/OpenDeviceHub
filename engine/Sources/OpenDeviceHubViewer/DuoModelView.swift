import AppKit
import IOSurface
import Metal
import OpenDeviceHubEngine
import SceneKit

/// A foldable drawn as the physical device, bending as the hinge moves, with the guest's screen on
/// its inner surface.
///
/// The model is Apple's own, read from the installed Xcode and never copied into this project. It is
/// the only way to show the difference between a device lying open and one bent halfway, because the
/// guest draws exactly the same picture in both.
///
/// Everything here was measured from the asset rather than taken from documentation, because there
/// is none. The findings, and how they were arrived at, are worth knowing before changing any of it:
///
/// - Every node and material name in the asset is obfuscated and changes between Xcode releases, so
///   nothing is looked up by name. The screen is found by shape instead: a perfectly flat face whose
///   proportions match a panel the device itself reports.
/// - The fold is one baked animation of 93 keyframe tracks, not a joint that can be set. A pose is
///   chosen by seeking it, and the fold occupies its first five seconds: flat at zero, shut at five.
///   The remainder is a demonstration reel that ends static.
/// - The inner screen faces up, so the camera looks down at it.
@MainActor
public final class DuoModelView: SCNView {
    /// Where the fold lives in the asset's timeline. Beyond this the animation is a reel of poses
    /// that has nothing to do with a hinge angle.
    nonisolated static let foldDuration: TimeInterval = 5

    private let screenNode: SCNNode
    private let cameraNode: SCNNode
    private let metalDevice: MTLDevice

    /// Nil when the installed Xcode has no foldable model, which leaves the caller on the ordinary
    /// flat renderer rather than showing nothing.
    public init?(metalDevice: MTLDevice, panelRatio: CGFloat) {
        guard let install = try? XcodeLocator.locate() else { return nil }
        let asset = install.appRoot.appending(
            path: "Contents/SharedFrameworks/DeviceKit.framework/Versions/A/PlugIns/CoreDevicePopDeviceKitExtension.devicekitplugin/Contents/Resources/V68.usdz"
        )
        guard FileManager.default.fileExists(atPath: asset.path(percentEncoded: false)),
              let scene = try? SCNScene(url: asset),
              let screen = Self.screenNode(in: scene, matching: panelRatio) else { return nil }

        self.screenNode = screen
        self.metalDevice = metalDevice

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 11
        camera.zNear = 0.1
        camera.zFar = 400
        cameraNode = SCNNode()
        cameraNode.camera = camera
        // Looking down at the inner screen, which is the face that carries the picture. The up
        // vector is the device's own length, so the landscape panel lands landscape.
        cameraNode.position = SCNVector3(0, 60, 0)
        cameraNode.look(
            at: SCNVector3(0, 0, 0),
            up: SCNVector3(0, 0, -1),
            localFront: SCNVector3(0, 0, -1)
        )
        scene.rootNode.addChildNode(cameraNode)

        super.init(frame: .zero, options: nil)

        self.scene = scene
        pointOfView = cameraNode
        backgroundColor = .clear
        autoenablesDefaultLighting = true
        allowsCameraControl = false
        // Time based animations do not advance on their own: they follow the scene time, which is
        // what makes a pose selectable. Pausing the scene as well stops that time being applied at
        // all, which looked at first like the fold not working.
        Self.makeTimeBased(scene)
        isPlaying = true
        sceneTime = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    /// Where the hinge has been put, kept here rather than read back from the view: a view that is
    /// not on screen never renders, and its scene time does not hold a value it never applied.
    public private(set) var hingeAngle: Double = 180

    /// Bends the device. 0 is shut and 180 is flat open, the same scale the hinge itself uses.
    public func setHingeAngle(_ degrees: Double) {
        hingeAngle = min(max(degrees, 0), 180)
        sceneTime = Self.sceneTime(forHingeAngle: hingeAngle)
    }

    /// Where in the asset's timeline a given fold sits. Flat is the start and shut is five seconds
    /// in, measured by rendering the model across its timeline and reading the silhouette.
    nonisolated static func sceneTime(forHingeAngle degrees: Double) -> TimeInterval {
        let clamped = min(max(degrees, 0), 180)
        return foldDuration * (180 - clamped) / 180
    }

    /// Puts the guest's picture on the inner screen. The surface becomes a texture rather than being
    /// copied, the same way the flat renderer uses it.
    public func setScreen(_ surface: IOSurfaceRef) {
        let descriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.width = IOSurfaceGetWidth(surface)
        descriptor.height = IOSurfaceGetHeight(surface)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = metalDevice.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else {
            return
        }
        let material = screenNode.geometry?.firstMaterial
        material?.diffuse.contents = texture
        // The picture is the surface, not something to be lit: shading it would dim the screen.
        material?.lightingModel = .constant
        material?.emission.contents = texture
    }

    /// A screen is a perfectly flat face whose proportions match a panel the device reports. Found
    /// by shape because every name in the asset is obfuscated and changes between Xcode releases.
    private static func screenNode(in scene: SCNScene, matching ratio: CGFloat) -> SCNNode? {
        var best: (node: SCNNode, difference: CGFloat)?
        scene.rootNode.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            let box = node.boundingBox
            let sides = [
                CGFloat(box.max.x - box.min.x),
                CGFloat(box.max.y - box.min.y),
                CGFloat(box.max.z - box.min.z),
            ].sorted()
            guard sides[0] < 0.001, sides[2] > 1 else { return }
            let difference = abs(sides[1] / sides[2] - ratio)
            guard difference < 0.05 else { return }
            if best == nil || difference < best!.difference {
                best = (node, difference)
            }
        }
        return best?.node
    }

    private static func makeTimeBased(_ scene: SCNScene) {
        scene.rootNode.enumerateHierarchy { node, _ in
            for key in node.animationKeys {
                guard let player = node.animationPlayer(forKey: key) else { continue }
                player.animation.usesSceneTimeBase = true
                player.animation.repeatCount = 1
            }
        }
    }
}
