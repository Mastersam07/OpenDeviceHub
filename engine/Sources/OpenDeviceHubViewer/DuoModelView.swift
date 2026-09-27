import AppKit
import IOSurface
import Metal
import OpenDeviceHubEngine
import SceneKit
import simd

/// A foldable drawn as the physical device, bent by the hinge, with the guest's screen on it.
@MainActor
public final class DuoModelView: SCNView {
    /// Times in the asset's closing clip. Its other flat-to-shut stretches also turn the hardware.
    enum Pose {
        static let open: TimeInterval = 260.0 / 24
        static let partlyOpen: TimeInterval = 300.0 / 24
        static let closed: TimeInterval = 380.0 / 24

        static func time(forHingeAngle degrees: Double) -> TimeInterval {
            let angle = min(180, max(0, degrees))
            return open + (closed - open) * (180 - angle) / 180
        }
    }

    private struct FrozenAnimation {
        let node: SCNNode
        let key: String
        let animation: SCNAnimation
    }

    private let content: SCNNode
    private let poses: [FrozenAnimation]
    private let cameraNode = SCNNode()
    private let innerScreen: SCNNode
    private let coverScreen: SCNNode
    private let hardwareButtons: [(button: HardwareButton, node: SCNNode)]
    private struct ButtonLift {
        let node: SCNNode
        let outward: SIMD3<Float>
        let depth: Float
    }
    private let lifts: [HardwareButton: ButtonLift]
    var liftDuration: TimeInterval = 0.12
    private var hoveredButton: HardwareButton?
    private var pressedButton: HardwareButton?
    private var tracking: NSTrackingArea?

    public var onHardwareButton: ((HardwareButton, ButtonPhase) -> Void)?
    private let metalDevice: MTLDevice
    private var nativeQuarterTurns: Int
    private var activeScreen: SCNNode

    private var hitMeshes: [ObjectIdentifier: DuoScreenHitMesh] = [:]
    private var measuredSize = CGSize.zero
    /// The view cannot snapshot until it is on screen, and the pose has to be framed before then.
    private let probe = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)

    public private(set) var hingeAngle: Double = 180
    private var guestQuarterTurns = 0

    /// Nil when the installed Xcode ships no foldable model.
    public init?(metalDevice: MTLDevice, showingCover: Bool, nativeRotation: Int = 0) {
        guard let install = try? XcodeLocator.locate() else { return nil }
        let asset = install.appRoot.appending(
            path: "Contents/SharedFrameworks/DeviceKit.framework/Versions/A/PlugIns/CoreDevicePopDeviceKitExtension.devicekitplugin/Contents/Resources/V68.usdz"
        )
        guard FileManager.default.fileExists(atPath: asset.path(percentEncoded: false)),
              let source = SCNSceneSource(url: asset, options: nil),
              let scene = source.scene(options: [
                  .animationImportPolicy: SCNSceneSource.AnimationImportPolicy.play,
              ]) else { return nil }

        // Names in this asset are obfuscated and change with Xcode, so screens are found by shape.
        let faces = Self.flatFaces(in: scene.rootNode)
        guard let inner = Self.closest(to: CGSize(width: 15.797, height: 11.082), among: faces),
              let cover = Self.closest(to: CGSize(width: 11.230, height: 7.739), among: faces),
              inner !== cover else { return nil }

        self.metalDevice = metalDevice
        self.nativeQuarterTurns = ((-nativeRotation / 90) % 4 + 4) % 4
        innerScreen = inner
        coverScreen = cover
        hardwareButtons = Self.hardwareButtons(in: scene.rootNode)
        lifts = Self.lifts(for: hardwareButtons, in: scene.rootNode)
        activeScreen = showingCover ? cover : inner
        content = scene.rootNode
        poses = Self.freeze(scene.rootNode)

        super.init(frame: .zero, options: [
            SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue,
        ])

        let camera = SCNCamera()
        camera.fieldOfView = 31
        camera.zNear = 0.01
        camera.zFar = 200
        // The framebuffer is already display referred, so tone mapping only lifts its blacks.
        camera.wantsHDR = false
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        installLighting(in: scene)

        self.scene = scene
        pointOfView = cameraNode
        backgroundColor = .clear
        wantsLayer = true
        layer?.isOpaque = false
        antialiasingMode = .multisampling4X
        allowsCameraControl = false
        rendersContinuously = true
        preferredFramesPerSecond = 30
        isPlaying = false
        loops = false

        setHingeAngle(180)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    /// 0 is shut and 180 is flat open, the same scale the hinge itself uses.
    public func setHingeAngle(_ degrees: Double) {
        hingeAngle = min(max(degrees, 0), 180)
        applyPose(at: Pose.time(forHingeAngle: hingeAngle))
        settleLifts()
        SCNTransaction.flush()
        frameCamera()
    }

    public override func layout() {
        super.layout()
        frameCamera()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    /// The hardware turns too: the guest has already turned its picture inside the panel.
    public func setOrientation(_ orientation: DeviceOrientation) {
        let turns = ((orientation.degrees / 90) % 4 + 4) % 4
        guard turns != guestQuarterTurns else { return }
        guestQuarterTurns = turns
        frameCamera()
    }

    /// The panels are built into the housing at different angles, so the turn comes with the panel.
    public func setShowingCover(_ showingCover: Bool, nativeRotation: Int) {
        activeScreen = showingCover ? coverScreen : innerScreen
        nativeQuarterTurns = ((-nativeRotation / 90) % 4 + 4) % 4
        frameCamera()
    }

    /// Read from a render: SceneKit's hit test uses a skinned mesh's authored pose and misses.
    public func hasHardware(at point: CGPoint) -> Bool {
        guard let silhouette else { return true }
        let x = Int(point.x / bounds.width * CGFloat(silhouette.width))
        let y = Int((1 - point.y / bounds.height) * CGFloat(silhouette.height))
        // A silhouette pixel is a few view points, so the edge errs towards hardware.
        for dy in -1...1 {
            for dx in -1...1 {
                let column = x + dx, row = y + dy
                guard column >= 0, row >= 0, column < silhouette.width, row < silhouette.height else { continue }
                if silhouette.pixels[row * silhouette.width + column] { return true }
            }
        }
        return false
    }

    private var silhouette: (width: Int, height: Int, pixels: [Bool])?

    public func setScreen(_ surface: IOSurfaceRef) {
        setScreen(surface, on: activeScreen, quarterTurns: nativeQuarterTurns)
    }

    public func setScreen(_ surface: IOSurfaceRef, onCover: Bool, nativeRotation: Int) {
        setScreen(
            surface,
            on: onCover ? coverScreen : innerScreen,
            quarterTurns: ((-nativeRotation / 90) % 4 + 4) % 4
        )
    }

    private func setScreen(_ surface: IOSurfaceRef, on screen: SCNNode, quarterTurns: Int) {
        let descriptor = MTLTextureDescriptor()
        // Tagged sRGB: SceneKit shades in linear space and reads an untagged framebuffer as linear.
        descriptor.pixelFormat = .bgra8Unorm_srgb
        descriptor.width = IOSurfaceGetWidth(surface)
        descriptor.height = IOSurfaceGetHeight(surface)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = metalDevice.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else {
            return
        }
        for material in screen.geometry?.materials ?? [] {
            material.diffuse.contents = texture
            material.diffuse.contentsTransform = Self.textureTransform(quarterTurns: quarterTurns)
            material.diffuse.wrapS = .clamp
            material.diffuse.wrapT = .clamp
            material.lightingModel = .constant
        }
    }

    /// Frozen players rather than the view's scene time, which the view advances itself.
    private func applyPose(at time: TimeInterval) {
        for pose in poses {
            pose.node.removeAnimation(forKey: pose.key, blendOutDuration: 0)
            pose.animation.timeOffset = time
            let player = SCNAnimationPlayer(animation: pose.animation)
            player.speed = 0
            pose.node.addAnimationPlayer(player, forKey: pose.key)
            player.play()
        }
    }

    private static func freeze(_ root: SCNNode) -> [FrozenAnimation] {
        var frozen: [FrozenAnimation] = []
        root.enumerateHierarchy { node, _ in
            for key in node.animationKeys {
                guard let player = node.animationPlayer(forKey: key) else { continue }
                player.animation.repeatCount = 0
                player.animation.isRemovedOnCompletion = false
                player.animation.usesSceneTimeBase = false
                frozen.append(FrozenAnimation(node: node, key: key, animation: player.animation))
                node.removeAnimation(forKey: key, blendOutDuration: 0)
            }
        }
        return frozen
    }

    /// By hinge angle, not a face's normal, which a skinned node keeps from its authored pose.
    nonisolated static func cameraOrbit(forHingeAngle degrees: Double) -> Double {
        let handoff = FoldableControl.handoffAngle
        let progress = degrees > handoff
            ? max(0, (40 - degrees) / (40 - handoff))
            : 1 + min(1, max(0, (handoff - degrees) / handoff))
        return -.pi / 4 * progress
    }

    /// The bones are the only part of a skinned mesh that moves with the pose.
    private func posedCentre() -> SIMD3<Float> {
        let bones = (innerScreen.skinner?.bones ?? []) + (coverScreen.skinner?.bones ?? [])
        guard !bones.isEmpty else { return .zero }
        let points = bones.map { node -> SIMD3<Float> in
            let transform = node.presentation.worldTransform
            return SIMD3<Float>(Float(transform.m41), Float(transform.m42), Float(transform.m43))
        }
        return points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
    }

    /// Measured once from the flat authored pose and held, so the framing does not lurch.
    private var referenceHalfAcross: Float = 0
    private var referenceHalfUp: Float = 0

    private func measureFlat() {
        let box = innerScreen.boundingBox
        let world = simd_float4x4(innerScreen.presentation.worldTransform)
        var points: [SIMD3<Float>] = []
        for x in [box.min.x, box.max.x] {
            for y in [box.min.y, box.max.y] {
                for z in [box.min.z, box.max.z] {
                    points.append(simd_make_float3(
                        world * SIMD4<Float>(Float(x), Float(y), Float(z), 1)
                    ))
                }
            }
        }
        let centre = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        func half(_ axis: SIMD3<Float>) -> Float {
            points.map { abs(simd_dot($0 - centre, axis)) }.max() ?? 1
        }
        referenceHalfAcross = half(SIMD3<Float>(1, 0, 0))
        referenceHalfUp = half(SIMD3<Float>(0, 0, -1))
    }

    /// Comes in to half as the device shuts and the camera swings round to the cover.
    nonisolated static func projectedWidthFraction(hingeAngle: Double, orbit: Double) -> Float {
        Float(max(sin(min(max(hingeAngle, 0), 180) * .pi / 360), abs(orbit) / .pi))
    }

    private func heldDistance() -> Float {
        let orbit = Self.cameraOrbit(forHingeAngle: hingeAngle)
        let orbitProgress = Float(min(1, abs(orbit) / (.pi / 2)))
        let fraction = Self.projectedWidthFraction(hingeAngle: hingeAngle, orbit: orbit)
        let halfAcross = referenceHalfAcross * (1 - orbitProgress * (1 - fraction))

        let aspect = Float(max(bounds.width, 1) / max(bounds.height, 1))
        let verticalField = Float(31) * .pi / 180
        let horizontalField = 2 * atan(tan(verticalField / 2) * aspect)
        let upright = guestQuarterTurns.isMultiple(of: 2)
        return max(
            (upright ? referenceHalfUp : halfAcross) / tan(verticalField / 2),
            (upright ? halfAcross : referenceHalfUp) / tan(horizontalField / 2)
        ) * 1.12
    }

    private func frameCamera() {
        if referenceHalfAcross == 0 || bounds.size != measuredSize {
            measuredSize = bounds.size
            measureFlat()
        }
        let orbit = Self.cameraOrbit(forHingeAngle: hingeAngle)
        let direction = SIMD3<Float>(Float(sin(orbit)), Float(cos(orbit)), 0)
        let centre = posedCentre()
        // A bent device stands taller and needs more room; open stays tight to the window.
        let bend = Float(sin(.pi * (180 - min(max(hingeAngle, 0), 180)) / 180))
        cameraNode.simdPosition = centre + direction * (heldDistance() * (1 + 0.2 * bend))
        cameraNode.look(
            at: SCNVector3(centre),
            up: SCNVector3(Self.cameraUp(quarterTurns: guestQuarterTurns, direction: direction)),
            localFront: SCNVector3(0, 0, -1)
        )
        recentre()
        projectButtons()
    }

    private func measureOnScreen() -> (minX: Float, maxX: Float, minY: Float, maxY: Float)? {
        guard let scene else { return nil }
        probe.scene = scene
        probe.pointOfView = cameraNode
        let aspect = Float(max(bounds.width, 1) / max(bounds.height, 1))
        let size = CGSize(width: 160, height: 160 / CGFloat(aspect))
        let image = probe.snapshot(atTime: 0, with: size, antialiasingMode: .none)
        guard let raster = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()) else { return nil }

        var minX = raster.pixelsWide, maxX = -1, minY = raster.pixelsHigh, maxY = -1
        var pixels = [Bool](repeating: false, count: raster.pixelsWide * raster.pixelsHigh)
        for y in 0..<raster.pixelsHigh {
            for x in 0..<raster.pixelsWide {
                guard let colour = raster.colorAt(x: x, y: y), colour.alphaComponent > 0.3 else {
                    continue
                }
                pixels[y * raster.pixelsWide + x] = true
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        silhouette = (raster.pixelsWide, raster.pixelsHigh, pixels)
        guard maxX >= minX, maxY >= minY else { return nil }
        return (
            Float(minX) / Float(raster.pixelsWide),
            Float(maxX + 1) / Float(raster.pixelsWide),
            Float(minY) / Float(raster.pixelsHigh),
            Float(maxY + 1) / Float(raster.pixelsHigh)
        )
    }

    /// The model's own up is negative z.
    nonisolated static func cameraUp(quarterTurns: Int, direction: SIMD3<Float>) -> SIMD3<Float> {
        let modelUp = SIMD3<Float>(0, 0, -1)
        let across = simd_normalize(simd_cross(modelUp, direction))
        switch ((quarterTurns % 4) + 4) % 4 {
        case 1: return -across
        case 2: return -modelUp
        case 3: return across
        default: return modelUp
        }
    }

    /// Measured from a render: a skinned node's transform and bounding box are its rest pose.
    private func recentre() {
        let aspect = Float(max(bounds.width, 1) / max(bounds.height, 1))
        // A box cut off by the picture's edge under-corrects; several passes walk it in.
        for _ in 0..<8 {
            guard let seen = measureOnScreen() else { return }
            let offsetX = (seen.minX + seen.maxX) / 2 - 0.5
            let offsetY = (seen.minY + seen.maxY) / 2 - 0.5
            if abs(offsetX) < 0.004, abs(offsetY) < 0.004 { return }

            let transform = cameraNode.simdTransform
            let right = simd_normalize(simd_make_float3(transform.columns.0))
            let up = simd_normalize(simd_make_float3(transform.columns.1))
            let distance = simd_length(cameraNode.simdPosition)
            let visibleHeight = 2 * distance * tan(Float(31) * .pi / 360)
            cameraNode.simdPosition += right * (offsetX * visibleHeight * aspect)
                - up * (offsetY * visibleHeight)
        }
    }

    private func installLighting(in scene: SCNScene) {
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 700
        key.position = SCNVector3(0, 40, 30)
        key.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 450
        scene.rootNode.addChildNode(fill)
    }

    /// A screen in this model is a face with no thickness.
    private static func flatFaces(in root: SCNNode) -> [(node: SCNNode, size: CGSize)] {
        var faces: [(SCNNode, CGSize)] = []
        root.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            let box = node.boundingBox
            let sides = [
                CGFloat(box.max.x - box.min.x),
                CGFloat(box.max.y - box.min.y),
                CGFloat(box.max.z - box.min.z),
            ].sorted()
            guard sides[0] < 0.01, sides[2] > 1 else { return }
            faces.append((node, CGSize(width: sides[2], height: sides[1])))
        }
        return faces
    }

    private static func closest(
        to wanted: CGSize,
        among faces: [(node: SCNNode, size: CGSize)]
    ) -> SCNNode? {
        faces.min {
            let a = abs($0.size.width - wanted.width) + abs($0.size.height - wanted.height)
            let b = abs($1.size.width - wanted.width) + abs($1.size.height - wanted.height)
            return a < b
        }?.node
    }

    nonisolated static func textureTransform(quarterTurns: Int) -> SCNMatrix4 {
        switch ((quarterTurns % 4) + 4) % 4 {
        case 1:
            SCNMatrix4(m11: 0, m12: -1, m13: 0, m14: 0,
                       m21: 1, m22: 0, m23: 0, m24: 0,
                       m31: 0, m32: 0, m33: 1, m34: 0,
                       m41: 0, m42: 1, m43: 0, m44: 1)
        case 2:
            SCNMatrix4(m11: -1, m12: 0, m13: 0, m14: 0,
                       m21: 0, m22: -1, m23: 0, m24: 0,
                       m31: 0, m32: 0, m33: 1, m34: 0,
                       m41: 1, m42: 1, m43: 0, m44: 1)
        case 3:
            SCNMatrix4(m11: 0, m12: 1, m13: 0, m14: 0,
                       m21: -1, m22: 0, m23: 0, m24: 0,
                       m31: 0, m32: 0, m33: 1, m34: 0,
                       m41: 1, m42: 0, m43: 0, m44: 1)
        default:
            SCNMatrix4Identity
        }
    }

    /// Nil before the view has rendered once.
    public func screenshotPNG() -> Data? {
        let image = snapshot()
        guard image.size.width > 1,
              let tiff = image.tiffRepresentation,
              let raster = NSBitmapImageRep(data: tiff) else { return nil }
        return raster.representation(using: .png, properties: [:])
    }

    /// By place at the flat authored pose: the top edge bars are volume down then up going right,
    /// the right edge's upper part is power and its lower is camera control. Names are obfuscated.
    nonisolated static func hardwareButtons(in root: SCNNode) -> [(button: HardwareButton, node: SCNNode)] {
        struct Part {
            let node: SCNNode
            let centre: SIMD3<Float>
            let size: SIMD3<Float>
        }
        var parts: [Part] = []
        root.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            let (low, high) = node.boundingBox
            let world = simd_float4x4(node.worldTransform)
            var corners: [SIMD3<Float>] = []
            for x in [low.x, high.x] {
                for y in [low.y, high.y] {
                    for z in [low.z, high.z] {
                        corners.append(simd_make_float3(world * SIMD4<Float>(Float(x), Float(y), Float(z), 1)))
                    }
                }
            }
            let lowest = corners.reduce(corners[0]) { simd_min($0, $1) }
            let highest = corners.reduce(corners[0]) { simd_max($0, $1) }
            parts.append(Part(node: node, centre: (lowest + highest) / 2, size: highest - lowest))
        }
        let body = parts.map { abs($0.centre.x) + $0.size.x / 2 }.max() ?? 0
        let top = parts.map { abs($0.centre.z) + $0.size.z / 2 }.max() ?? 0
        // The top edge also carries a flat decal strip with no height, which is not a button.
        func isBar(_ part: Part) -> Bool {
            let longest = max(part.size.x, part.size.z)
            let shortest = min(part.size.x, part.size.z)
            return longest > 1 && longest < 2 && part.size.y > 0.1 && shortest > 0.05
        }
        let volume = parts
            .filter { isBar($0) && $0.centre.z < -(top - 0.5) && $0.size.x > $0.size.z }
            .sorted { $0.centre.x < $1.centre.x }
        let side = parts.filter { isBar($0) && $0.centre.x > body - 0.5 && $0.size.z > $0.size.x }
        let power = side.filter { $0.centre.z < 0 }.sorted { $0.size.x > $1.size.x }.first
        let camera = side.filter { $0.centre.z > 0 }.sorted { $0.size.x > $1.size.x }.first
        var found: [(HardwareButton, SCNNode)] = []
        if volume.count == 2 {
            found.append((.volumeDown, volume[0].node))
            found.append((.volumeUp, volume[1].node))
        }
        if let power {
            found.append((.lock, power.node))
        }
        if let camera {
            found.append((.cameraControl, camera.node))
        }
        return found
    }

    /// A skinned node does not move itself, so each button is re-skinned to a node under its bone.
    /// At the authored pose the top edge faces negative z and the right edge positive x.
    private static func lifts(
        for buttons: [(button: HardwareButton, node: SCNNode)],
        in root: SCNNode
    ) -> [HardwareButton: ButtonLift] {
        var lifts: [HardwareButton: ButtonLift] = [:]
        for (button, node) in buttons {
            guard let skinner = node.skinner, skinner.bones.count == 1, let bone = skinner.bones.first else { continue }
            let raiser = SCNNode()
            bone.addChildNode(raiser)
            root.enumerateHierarchy { part, _ in
                guard let old = part.skinner, old.bones.count == 1, old.bones[0] === bone else { return }
                let reskinned = SCNSkinner(
                    baseGeometry: old.baseGeometry,
                    bones: [raiser],
                    boneInverseBindTransforms: old.boneInverseBindTransforms,
                    boneWeights: old.boneWeights,
                    boneIndices: old.boneIndices
                )
                reskinned.baseGeometryBindTransform = old.baseGeometryBindTransform
                reskinned.skeleton = old.skeleton
                part.skinner = reskinned
            }
            let outward: SIMD3<Float> = Self.isOnTopEdge(button) ? SIMD3(0, 0, -1) : SIMD3(1, 0, 0)
            let boneWorld = simd_float4x4(bone.worldTransform)
            let local = simd_make_float3(simd_inverse(boneWorld) * SIMD4<Float>(outward, 0))
            let (low, high) = node.boundingBox
            let world = simd_float4x4(node.worldTransform)
            var innermost = Float.greatestFiniteMagnitude
            for x in [low.x, high.x] {
                for y in [low.y, high.y] {
                    for z in [low.z, high.z] {
                        let corner = simd_make_float3(world * SIMD4<Float>(Float(x), Float(y), Float(z), 1))
                        innermost = min(innermost, simd_dot(corner, outward))
                    }
                }
            }
            let origin = simd_dot(simd_make_float3(boneWorld.columns.3), outward)
            lifts[button] = ButtonLift(
                node: raiser,
                outward: simd_normalize(local),
                depth: max(origin - innermost, 0.01)
            )
        }
        return lifts
    }

    /// The buttons stand only a few points proud of the body at a window's size.
    private static let buttonReach: CGFloat = 6

    private var buttonRects: [(button: HardwareButton, rect: CGRect)] = []

    private func projectButtons() {
        buttonRects = hardwareButtons.compactMap { button, node in
            guard let mesh = hitMesh(for: node), let posed = posedPart(node, mesh) else { return nil }
            var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
            for position in posed {
                let projected = projectPoint(SCNVector3(position.x, position.y, position.z))
                minX = min(minX, CGFloat(projected.x))
                maxX = max(maxX, CGFloat(projected.x))
                minY = min(minY, CGFloat(projected.y))
                maxY = max(maxY, CGFloat(projected.y))
            }
            guard minX < maxX, minY < maxY else { return nil }
            let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            return (button, rect.insetBy(dx: -Self.buttonReach, dy: -Self.buttonReach))
        }
    }

    /// A point on the screen is a touch whatever button is near; the reach is for the bezel side.
    func hardwareButton(at point: CGPoint) -> HardwareButton? {
        let button: HardwareButton?
        if let hoveredButton, let liftedReach, liftedReach.contains(point) {
            button = hoveredButton
        } else {
            button = buttonRects.first(where: { $0.rect.contains(point) })?.button
        }
        guard let button else { return nil }
        return screenPoint(at: point) == nil ? button : nil
    }

    func hardwareButtonRect(_ button: HardwareButton) -> CGRect? {
        buttonRects.first { $0.button == button }?.rect
    }

    private var posedParts: [ObjectIdentifier: (hinge: Double, positions: [SIMD3<Float>])] = [:]

    private func posedPart(_ node: SCNNode, _ mesh: DuoScreenHitMesh) -> [SIMD3<Float>]? {
        let key = ObjectIdentifier(node)
        if let cached = posedParts[key], cached.hinge == hingeAngle { return cached.positions }
        let bones = node.skinner?.bones ?? []
        guard !bones.isEmpty else { return nil }
        let positions = mesh.posedPositions(bones: bones)
        posedParts[key] = (hingeAngle, positions)
        return positions
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    public override func mouseMoved(with event: NSEvent) {
        hover(hardwareButton(at: convert(event.locationInWindow, from: nil)))
    }

    public override func mouseExited(with event: NSEvent) {
        hover(nil)
    }

    private func hover(_ button: HardwareButton?) {
        guard button != hoveredButton else { return }
        if let hoveredButton {
            lift(hoveredButton, by: 0)
            light(hoveredButton, false)
        }
        hoveredButton = button
        if let button {
            lift(button, by: Self.hoverRise)
            light(button, true)
            NSCursor.pointingHand.set()
            showBadge(for: button, pressed: false)
        } else {
            NSCursor.arrow.set()
            badge.isHidden = true
        }
    }

    /// The buttons stand a tenth of a unit proud of the body.
    private static let hoverRise: Float = 0.08
    private static let pressRise: Float = 0.03

    /// Shut, the front edge hides the volume buttons by a tenth of a unit and shows power edge on.
    private func restLift(of button: HardwareButton) -> Float {
        let shut = Float(min(max((FoldableControl.handoffAngle - hingeAngle) / FoldableControl.handoffAngle, 0), 1))
        let hidden: Float = Self.isOnTopEdge(button) ? 0.1 : 0
        return (hidden + 0.06) * shut
    }

    private static func isOnTopEdge(_ button: HardwareButton) -> Bool {
        button == .volumeUp || button == .volumeDown
    }

    /// Scaled as it moves so the inner face stays in the body rather than floating off.
    private func lift(_ button: HardwareButton, by rise: Float) {
        guard let lift = lifts[button] else { return }
        let amount = restLift(of: button) + rise
        SCNTransaction.begin()
        SCNTransaction.animationDuration = liftDuration
        lift.node.simdPosition = lift.outward * amount
        lift.node.simdScale = SIMD3<Float>(repeating: 1) + abs(lift.outward) * (amount / lift.depth)
        SCNTransaction.commit()
        liftedReach = rise > 0 ? reach(of: button, lifted: amount) : nil
    }

    private func settleLifts() {
        let animated = liftDuration
        liftDuration = 0
        for button in lifts.keys {
            lift(button, by: button == pressedButton ? Self.pressRise : button == hoveredButton ? Self.hoverRise : 0)
        }
        liftDuration = animated
    }

    /// Grown to the lifted position, so the pointer can follow the button out and keep the hover.
    private var liftedReach: CGRect?

    private func reach(of button: HardwareButton, lifted amount: Float) -> CGRect? {
        guard let rect = hardwareButtonRect(button), let lift = lifts[button],
              let bone = lift.node.parent else { return nil }
        let transform = simd_float4x4(bone.presentation.worldTransform)
        let origin = simd_make_float3(transform.columns.3)
        let tip = origin + simd_make_float3(transform * SIMD4<Float>(lift.outward, 0)) * amount
        let from = projectPoint(SCNVector3(origin))
        let to = projectPoint(SCNVector3(tip))
        return rect.union(rect.offsetBy(dx: CGFloat(to.x - from.x), dy: CGFloat(to.y - from.y)))
    }

    private func light(_ button: HardwareButton, _ lit: Bool) {
        guard let node = hardwareButtons.first(where: { $0.button == button })?.node else { return }
        for material in node.geometry?.materials ?? [] {
            material.emission.contents = lit ? NSColor(white: 0.35, alpha: 1) : NSColor.black
        }
    }

    func liftOffset(of button: HardwareButton) -> Float {
        guard let lift = lifts[button] else { return 0 }
        return simd_length(lift.node.simdPosition) - restLift(of: button)
    }

    private let badge = HardwareButtonBadge()

    private func showBadge(for button: HardwareButton, pressed: Bool) {
        guard let rect = hardwareButtonRect(button) else { return }
        badge.show(Self.name(of: button), symbol: Self.symbol(of: button), pressed: pressed)
        let size = badge.fittingSize
        let onTop = rect.width > rect.height
        var origin = onTop
            ? CGPoint(x: rect.midX - size.width / 2, y: rect.maxY + 4)
            : CGPoint(x: rect.maxX + 4, y: rect.midY - size.height / 2)
        origin.x = min(max(origin.x, 2), bounds.width - size.width - 2)
        origin.y = min(max(origin.y, 2), bounds.height - size.height - 2)
        badge.frame = CGRect(origin: origin, size: size)
        if badge.superview == nil { addSubview(badge) }
        badge.isHidden = false
    }

    nonisolated static func symbol(of button: HardwareButton) -> String {
        switch button {
        case .volumeUp: "speaker.plus"
        case .volumeDown: "speaker.minus"
        case .lock: "lock"
        case .home: "house"
        case .siri: "waveform"
        case .actionButton: "button.horizontal"
        case .cameraControl: "camera"
        }
    }

    nonisolated static func name(of button: HardwareButton) -> String {
        switch button {
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .lock: "Lock"
        case .home: "Home"
        case .siri: "Siri"
        case .actionButton: "Action Button"
        case .cameraControl: "Camera Control"
        }
    }

    /// The point is 0 to 1 across and down the shown screen.
    public var onTouch: ((CGPoint, TouchEvent.Phase) -> Void)?

    /// A scroll is a finger drag: the first turn touches down, each moves it, a pause lifts it.
    public override func scrollWheel(with event: NSEvent) {
        let pointer = convert(event.locationInWindow, from: nil)
        if scrollDrag == nil {
            guard let start = screenPoint(at: pointer) else { return }
            scrollDrag = ScrollDrag(anchor: pointer, start: start)
            onTouch?(start, .began)
        }
        guard var drag = scrollDrag else { return }
        let moved = drag.move(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            precise: event.hasPreciseScrollingDeltas
        )
        if let point = screenPoint(at: moved) {
            drag.last = point
            onTouch?(point, .moved)
        }
        scrollDrag = drag

        scrollLift?.cancel()
        let lift = DispatchWorkItem { [weak self] in
            guard let self, let drag = scrollDrag else { return }
            scrollDrag = nil
            onTouch?(drag.last, .ended)
        }
        scrollLift = lift
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: lift)
    }

    private var scrollDrag: ScrollDrag?
    private var scrollLift: DispatchWorkItem?

    public override func mouseDown(with event: NSEvent) {
        if let button = hardwareButton(at: convert(event.locationInWindow, from: nil)) {
            pressedButton = button
            lift(button, by: Self.pressRise)
            showBadge(for: button, pressed: true)
            onHardwareButton?(button, .down)
            return
        }
        report(event, phase: .began)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard pressedButton == nil else { return }
        report(event, phase: .moved)
    }

    public override func mouseUp(with event: NSEvent) {
        if let pressedButton {
            self.pressedButton = nil
            lift(pressedButton, by: pressedButton == hoveredButton ? Self.hoverRise : 0)
            showBadge(for: pressedButton, pressed: false)
            onHardwareButton?(pressedButton, .up)
            return
        }
        report(event, phase: .ended)
    }

    /// A release off the screen lifts from here, or the guest is left holding a finger down.
    private var lastContact: CGPoint?

    /// A home swipe begun on the bezel just under the screen is meant for its bottom edge.
    private static let pressReach: CGFloat = 24
    private static let dragReach: CGFloat = 60

    private func report(_ event: NSEvent, phase: TouchEvent.Phase) {
        let point = convert(event.locationInWindow, from: nil)
        let guestPoint: CGPoint
        if let hit = screenPoint(at: point) {
            guestPoint = hit
        } else if let near = nearestScreenPoint(
            to: point,
            within: phase == .began ? Self.pressReach : Self.dragReach
        ) {
            guestPoint = near
        } else if phase != .began, let last = lastContact {
            guestPoint = last
        } else {
            return
        }
        lastContact = phase == .ended ? nil : guestPoint
        onTouch?(guestPoint, phase)
    }

    private func nearestScreenPoint(to point: CGPoint, within reach: CGFloat) -> CGPoint? {
        var distance: CGFloat = 3
        while distance <= reach {
            for eighth in 0..<8 {
                let angle = CGFloat(eighth) * .pi / 4
                let candidate = CGPoint(x: point.x + cos(angle) * distance, y: point.y + sin(angle) * distance)
                if let hit = screenPoint(at: candidate) { return hit }
            }
            distance += 3
        }
        return nil
    }

    /// 0 to 1 across and down the guest's screen.
    func screenPoint(at point: CGPoint) -> CGPoint? {
        guard let mesh = hitMesh(), let posed = posedScreen(mesh) else { return nil }
        let near = unprojectPoint(SCNVector3(point.x, point.y, 0))
        let far = unprojectPoint(SCNVector3(point.x, point.y, 1))
        guard let uv = mesh.hit(
            from: SIMD3<Float>(Float(near.x), Float(near.y), Float(near.z)),
            to: SIMD3<Float>(Float(far.x), Float(far.y), Float(far.z)),
            posed: posed
        ) else { return nil }

        // The asset's texture coordinates already run down the picture, so nothing is flipped after
        // the unturn: measured on 27A266a by sampling the guest's framebuffer under the pointer.
        let turned = Self.unturn(SIMD2<Float>(uv.x, uv.y), quarterTurns: nativeQuarterTurns)
        // The guest sometimes drops a contact on an edge's last pixel, where a bezel swipe lands.
        return CGPoint(
            x: min(max(CGFloat(turned.x), Self.inset), 1 - Self.inset),
            y: min(max(CGFloat(turned.y), Self.inset), 1 - Self.inset)
        )
    }

    private static let inset: CGFloat = 0.005

    nonisolated static func unturn(_ uv: SIMD2<Float>, quarterTurns: Int) -> SIMD2<Float> {
        switch ((quarterTurns % 4) + 4) % 4 {
        case 1: SIMD2<Float>(uv.y, 1 - uv.x)
        case 2: SIMD2<Float>(1 - uv.x, 1 - uv.y)
        case 3: SIMD2<Float>(1 - uv.y, uv.x)
        default: uv
        }
    }

    var activeScreenForTesting: SCNNode { activeScreen }

    func hitMesh() -> DuoScreenHitMesh? {
        hitMesh(for: activeScreen)
    }

    private var posedCache: (screen: ObjectIdentifier, hinge: Double, positions: [SIMD3<Float>])?

    private func posedScreen(_ mesh: DuoScreenHitMesh) -> [SIMD3<Float>]? {
        let key = ObjectIdentifier(activeScreen)
        if let posedCache, posedCache.screen == key, posedCache.hinge == hingeAngle {
            return posedCache.positions
        }
        let bones = activeScreen.skinner?.bones ?? []
        guard !bones.isEmpty else { return nil }
        let positions = mesh.posedPositions(bones: bones)
        posedCache = (key, hingeAngle, positions)
        return positions
    }

    private func hitMesh(for screen: SCNNode) -> DuoScreenHitMesh? {
        let key = ObjectIdentifier(screen)
        if let cached = hitMeshes[key] { return cached }
        guard let made = DuoScreenHitMesh(node: screen) else { return nil }
        hitMeshes[key] = made
        return made
    }
}

/// The finger a scroll stands in for.
struct ScrollDrag {
    let anchor: CGPoint
    private(set) var offset = CGSize.zero
    var last: CGPoint

    init(anchor: CGPoint, start: CGPoint) {
        self.anchor = anchor
        last = start
    }

    /// A wheel reports lines of about a dozen points; the view's y counts up and a scroll's down.
    mutating func move(deltaX: CGFloat, deltaY: CGFloat, precise: Bool) -> CGPoint {
        let factor: CGFloat = precise ? 1 : 12
        offset.width += deltaX * factor
        offset.height -= deltaY * factor
        return CGPoint(x: anchor.x + offset.width, y: anchor.y + offset.height)
    }
}

final class HardwareButtonBadge: NSView {
    private let symbol = NSImageView()
    private static let diameter: CGFloat = 28

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Self.diameter / 2
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
        symbol.imageScaling = .scaleProportionallyDown
        symbol.contentTintColor = .white
        addSubview(symbol)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    /// The pointer passes through to the button the badge names.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ name: String, symbol symbolName: String, pressed: Bool) {
        symbol.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: name)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        symbol.contentTintColor = pressed ? .systemBlue : .white
        needsLayout = true
    }

    override var fittingSize: NSSize {
        NSSize(width: Self.diameter, height: Self.diameter)
    }

    override func layout() {
        super.layout()
        symbol.frame = bounds.insetBy(dx: 5, dy: 5)
    }
}
