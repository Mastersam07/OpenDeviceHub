import AppKit
import IOSurface
import Metal
import OpenDeviceHubEngine
import SceneKit
import simd

/// A foldable drawn as the physical device, bending as the hinge moves, with the guest's screen on
/// its surface.
///
/// The model is Apple's own, read from the installed Xcode and never copied into this project. It is
/// the only way to show the difference between a device lying open and one bent halfway, because the
/// guest draws exactly the same picture in both.
///
/// The asset carries one 37.5 second animation and no documentation. Everything below was either
/// measured from it or taken from prior art that had already measured it, and each is the kind of
/// detail that silently produces a wrong picture rather than an error:
///
/// - A pose is chosen by freezing the animation, not by running a clock. The animations are taken
///   off the nodes and re-added as players with no speed and a time offset. Driving the view's own
///   scene time instead loses the fight with the view, which advances that clock itself.
/// - The fold is the closing clip between 10.833 and 15.833 seconds. Other stretches of the timeline
///   also run flat to shut, but they turn the hardware as well, so the device ends up facing the
///   wrong way.
/// - The framebuffer is tagged sRGB. SceneKit shades in linear space, and an untagged one is read as
///   though already linear, which washes the picture out.
/// - Tone mapping is off, which otherwise lifts the blacks of a picture that is already finished.
@MainActor
public final class DuoModelView: SCNView {
    /// Where each pose sits in the asset's timeline.
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
    private let metalDevice: MTLDevice
    /// How far the panel being shown is built round in its housing. The two panels of a foldable
    /// are built differently, so this follows whichever one the guest is drawing to.
    private var nativeQuarterTurns: Int
    private var activeScreen: SCNNode

    /// Built once per screen: reading and skinning the geometry is not something to do per click.
    private var hitMeshes: [ObjectIdentifier: DuoScreenHitMesh] = [:]
    private var measuredSize = CGSize.zero
    /// Renders small probe frames so the device can be centred by looking at it. The view itself
    /// cannot be asked for a picture until it is on screen, and the pose has to be right before then.
    private let probe = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)

    /// Where the hinge has been put, kept here rather than read back from the view.
    public private(set) var hingeAngle: Double = 180
    /// How the device itself is standing. The picture inside the panel is already turned by the
    /// guest, so the hardware is turned to match by rolling the camera.
    private var guestQuarterTurns = 0

    /// Nil when the installed Xcode ships no foldable model, which leaves the caller on the ordinary
    /// flat renderer rather than showing nothing.
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

        // By shape, not by name: every name in this asset is obfuscated and changes between Xcode
        // releases. A screen is a perfectly flat face, and the two are told apart by size.
        let faces = Self.flatFaces(in: scene.rootNode)
        guard let inner = Self.closest(to: CGSize(width: 15.797, height: 11.082), among: faces),
              let cover = Self.closest(to: CGSize(width: 11.230, height: 7.739), among: faces),
              inner !== cover else { return nil }

        self.metalDevice = metalDevice
        self.nativeQuarterTurns = ((-nativeRotation / 90) % 4 + 4) % 4
        innerScreen = inner
        coverScreen = cover
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
        // Nothing plays: the pose is frozen and only changes when the hinge does.
        isPlaying = false
        loops = false

        setHingeAngle(180)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    /// Bends the device. 0 is shut and 180 is flat open, the same scale the hinge itself uses.
    public func setHingeAngle(_ degrees: Double) {
        hingeAngle = min(max(degrees, 0), 180)
        applyPose(at: Pose.time(forHingeAngle: hingeAngle))
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

    /// Turns the device. Everything on screen turns, the hardware included, because the guest has
    /// already turned its own picture inside the panel.
    public func setOrientation(_ orientation: DeviceOrientation) {
        let turns = ((orientation.degrees / 90) % 4 + 4) % 4
        guard turns != guestQuarterTurns else { return }
        guestQuarterTurns = turns
        frameCamera()
    }

    /// Which panel the guest is drawing to, so the picture goes on the face that is being shown.
    /// The panels are built into the housing at different angles, so the turn comes with it.
    public func setShowingCover(_ showingCover: Bool, nativeRotation: Int) {
        activeScreen = showingCover ? coverScreen : innerScreen
        nativeQuarterTurns = ((-nativeRotation / 90) % 4 + 4) % 4
        frameCamera()
    }

    /// Whether there is hardware under this point of the view. Outside it the view is clear, and a
    /// click there belongs to whatever is behind the window.
    public func hasHardware(at point: CGPoint) -> Bool {
        !hitTest(point, options: [
            .rootNode: content,
            .ignoreHiddenNodes: true,
            .backFaceCulling: false,
            .searchMode: SCNHitTestSearchMode.any.rawValue,
        ]).isEmpty
    }

    /// Puts the guest's picture on the face being shown.
    public func setScreen(_ surface: IOSurfaceRef) {
        setScreen(surface, on: activeScreen, quarterTurns: nativeQuarterTurns)
    }

    /// Puts a panel's picture on its own face, whichever face is being shown. Both panels stay
    /// textured, so the camera can swing from one to the other with the pictures already there.
    public func setScreen(_ surface: IOSurfaceRef, onCover: Bool, nativeRotation: Int) {
        setScreen(
            surface,
            on: onCover ? coverScreen : innerScreen,
            quarterTurns: ((-nativeRotation / 90) % 4 + 4) % 4
        )
    }

    private func setScreen(_ surface: IOSurfaceRef, on screen: SCNNode, quarterTurns: Int) {
        let descriptor = MTLTextureDescriptor()
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

    /// Freezing rather than playing: each animation is taken off its node and put back as a player
    /// with no speed, so the rig sits at one time and stays there.
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

    /// Where the camera stands for a given fold.
    ///
    /// Driven by the hinge angle rather than by any face's normal, because a skinned node keeps the
    /// transform it was authored with whatever its bones do: a screen's "normal" is only true when
    /// the device is flat, which is how a shut device came to be shown edge on. The closing clip
    /// turns the hardware as well, and this turns with it so the cover ends up facing us.
    nonisolated static func cameraOrbit(forHingeAngle degrees: Double) -> Double {
        let handoff = FoldableControl.handoffAngle
        let progress = degrees > handoff
            ? max(0, (40 - degrees) / (40 - handoff))
            : 1 + min(1, max(0, (handoff - degrees) / handoff))
        return -.pi / 4 * progress
    }

    /// Where the hardware is right now, taken from the bones, which are the only part of a skinned
    /// mesh that moves with the pose. They run along the hinge rather than across the panels, so
    /// they say where the device is but not how large it is.
    private func posedCentre() -> SIMD3<Float> {
        let bones = (innerScreen.skinner?.bones ?? []) + (coverScreen.skinner?.bones ?? [])
        guard !bones.isEmpty else { return .zero }
        let points = bones.map { node -> SIMD3<Float> in
            let transform = node.presentation.worldTransform
            return SIMD3<Float>(Float(transform.m41), Float(transform.m42), Float(transform.m43))
        }
        return points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
    }

    /// The open device's extents, measured once from the larger panel as it was authored, which is
    /// flat, and then held. Every pose is framed from these, so nothing lurches while the hinge
    /// moves and the viewport stays the one the open device was sized for.
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

    /// How much of the open device's width the pose takes up on screen. Flat it is all of it; as the
    /// device shuts and the camera swings round to the cover, only one panel is in the way, so the
    /// framing width comes in to half. The fold recedes in depth rather than growing.
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
        // A quarter turn lays the device's long axis across the window, so which of its extents has
        // to fit which field swaps with it.
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
        // A bent device stands taller than a flat one and needs a little more room. Only while bent:
        // open is the common view and should stay tight to the window.
        let bend = Float(sin(.pi * (180 - min(max(hingeAngle, 0), 180)) / 180))
        cameraNode.simdPosition = centre + direction * (heldDistance() * (1 + 0.2 * bend))
        cameraNode.look(
            at: SCNVector3(centre),
            up: SCNVector3(Self.cameraUp(quarterTurns: guestQuarterTurns, direction: direction)),
            localFront: SCNVector3(0, 0, -1)
        )
        recentre()
    }

    /// Where the device is in the picture, as fractions of it, or nil when it is not in it at all.
    private func measureOnScreen() -> (minX: Float, maxX: Float, minY: Float, maxY: Float)? {
        guard let scene else { return nil }
        probe.scene = scene
        probe.pointOfView = cameraNode
        let aspect = Float(max(bounds.width, 1) / max(bounds.height, 1))
        let size = CGSize(width: 160, height: 160 / CGFloat(aspect))
        let image = probe.snapshot(atTime: 0, with: size, antialiasingMode: .none)
        guard let raster = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()) else { return nil }

        var minX = raster.pixelsWide, maxX = -1, minY = raster.pixelsHigh, maxY = -1
        for y in 0..<raster.pixelsHigh {
            for x in 0..<raster.pixelsWide {
                guard let colour = raster.colorAt(x: x, y: y), colour.alphaComponent > 0.3 else {
                    continue
                }
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (
            Float(minX) / Float(raster.pixelsWide),
            Float(maxX + 1) / Float(raster.pixelsWide),
            Float(minY) / Float(raster.pixelsHigh),
            Float(maxY + 1) / Float(raster.pixelsHigh)
        )
    }

    /// Which way is up for the camera, rolled by however the device is standing. The model's own up
    /// is the negative z axis; a quarter turn takes it to the axis across the view instead.
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

    /// Nudges the camera until the device sits in the middle of the picture.
    ///
    /// Measured rather than worked out. Everything in this model that could say where the device is
    /// turns out to be misleading: a skinned node keeps the transform it was authored with, the
    /// bounding box is the rest pose, and the cover panel hangs off a single bone sitting near the
    /// origin. What the camera sees cannot be wrong.
    private func recentre() {
        let aspect = Float(max(bounds.width, 1) / max(bounds.height, 1))
        // A shut device starts a long way from the middle, and while it is off the edge of the
        // picture the measured box is cut short, so each pass corrects less than it should and it
        // takes several to walk it in. Each pass is a small render, so the extra ones are cheap.
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

    /// A face with no thickness at all, which is what a screen is in this model.
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

    /// Turns the picture to match how the panel is built into the device.
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

    /// The device as it is drawn, for a screenshot. Nil before the view has rendered once.
    public func screenshotPNG() -> Data? {
        let image = snapshot()
        guard image.size.width > 1,
              let tiff = image.tiffRepresentation,
              let raster = NSBitmapImageRep(data: tiff) else { return nil }
        return raster.representation(using: .png, properties: [:])
    }

    /// Where a click landed on the shown screen, 0 to 1 across and down.
    public var onTouch: ((CGPoint, TouchEvent.Phase) -> Void)?

    /// A scroll is sent as a finger dragging the content: down on the screen begins a contact under
    /// the pointer, each turn of the wheel moves it, and a pause lifts it. The moved pointer is hit
    /// tested each time, so the drag follows the screen however the device is posed or turned.
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

    public override func mouseDown(with event: NSEvent) { report(event, phase: .began) }
    public override func mouseDragged(with event: NSEvent) { report(event, phase: .moved) }
    public override func mouseUp(with event: NSEvent) { report(event, phase: .ended) }

    /// Where the finger last was on the screen. A drag that runs off the edge of the screen stops
    /// there rather than vanishing, and a release off the screen lifts from there, since a contact
    /// that never lifts leaves the guest holding a finger down.
    private var lastContact: CGPoint?

    private func report(_ event: NSEvent, phase: TouchEvent.Phase) {
        let point = convert(event.locationInWindow, from: nil)
        let guestPoint: CGPoint
        if let hit = screenPoint(at: point) {
            guestPoint = hit
        } else if phase != .began, let last = lastContact {
            guestPoint = last
        } else {
            return
        }
        lastContact = phase == .ended ? nil : guestPoint
        onTouch?(guestPoint, phase)
    }

    /// Where a click on the window lands on the guest's screen, 0 to 1 across and down.
    func screenPoint(at point: CGPoint) -> CGPoint? {
        let mesh = hitMesh()
        let near = unprojectPoint(SCNVector3(point.x, point.y, 0))
        let far = unprojectPoint(SCNVector3(point.x, point.y, 1))
        guard let uv = mesh?.hit(
            from: SIMD3<Float>(Float(near.x), Float(near.y), Float(near.z)),
            to: SIMD3<Float>(Float(far.x), Float(far.y), Float(far.z)),
            bones: activeScreen.skinner?.bones ?? []
        ) else { return nil }

        // The picture was turned to meet the panel, so the same turn is undone to get back to what
        // the guest thinks it is showing. This asset's texture coordinates already run down the
        // picture, the way the guest counts, so nothing is flipped after it: measured on 27A266a by
        // sampling the device's own framebuffer through each turn and flip and keeping the one whose
        // colours match what is drawn under the pointer.
        let turned = Self.unturn(SIMD2<Float>(uv.x, uv.y), quarterTurns: nativeQuarterTurns)
        return CGPoint(x: CGFloat(turned.x), y: CGFloat(turned.y))
    }

    /// The inverse of the turn put on the texture.
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

    private func hitMesh(for screen: SCNNode) -> DuoScreenHitMesh? {
        let key = ObjectIdentifier(screen)
        if let cached = hitMeshes[key] { return cached }
        guard let made = DuoScreenHitMesh(node: screen) else { return nil }
        hitMeshes[key] = made
        return made
    }
}

/// The finger a scroll stands in for: where it went down in the view, how far the scrolling has
/// carried it since, and the last point of it that was on the screen, which is where it lifts.
struct ScrollDrag {
    let anchor: CGPoint
    private(set) var offset = CGSize.zero
    var last: CGPoint

    init(anchor: CGPoint, start: CGPoint) {
        self.anchor = anchor
        last = start
    }

    /// Where the finger is now, in the view. A mouse wheel reports lines rather than points, and a
    /// line is about a dozen of them. The view counts up and a scroll counts down, so a scroll down
    /// moves the finger down.
    mutating func move(deltaX: CGFloat, deltaY: CGFloat, precise: Bool) -> CGPoint {
        let factor: CGFloat = precise ? 1 : 12
        offset.width += deltaX * factor
        offset.height -= deltaY * factor
        return CGPoint(x: anchor.x + offset.width, y: anchor.y + offset.height)
    }
}
