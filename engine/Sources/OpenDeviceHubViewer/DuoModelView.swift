import AppKit
import IOSurface
import Metal
import OpenDeviceHubEngine
import os
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
    private let tracks: [PoseTrack]
    /// A copy only the probe renders: measuring on it never changes the pose on screen.
    private struct Twin {
        let scene: SCNScene
        let camera: SCNNode
        let bones: [SCNNode]
        let tracks: [PoseTrack]
    }
    private let twin: Twin
    private struct Framing {
        let centre: SIMD3<Float>
        let correction: SIMD3<Float>
        let distanceScale: Float
        let silhouette: (width: Int, height: Int, pixels: [Bool])?
    }
    private var framings: [Int: Framing] = [:]
    private var fits: [Int: Float] = [:]
    /// The most of the picture the device may cover; the shut phone sits at 0.97 down and stays.
    static let fillLimit: Float = 0.98
    /// What it is backed off to when it covers more, between 45 and 10 degrees, where it stands.
    static let fillTarget: Float = 0.95
    static let standingBand: Double = 50
    private var measuredTurns = 0
    private struct Move {
        let from: Double
        let to: Double
        let start: SIMD3<Float>
        let end: SIMD3<Float>
        /// How far the camera stands back at the angles sampled along the way, in order.
        let scales: [(angle: Double, scale: Float)]
        func fraction(of angle: Double) -> Double? {
            guard to != from else { return nil }
            let fraction = (angle - from) / (to - from)
            guard fraction > -0.001, fraction < 1.001 else { return nil }
            return min(max(fraction, 0), 1)
        }
        func scale(at angle: Double) -> Float {
            guard let above = scales.firstIndex(where: { $0.angle >= angle }) else { return scales.last?.scale ?? 1 }
            guard above > 0 else { return scales[above].scale }
            let below = scales[above - 1]
            let span = scales[above].angle - below.angle
            let mix = span > 0 ? Float((angle - below.angle) / span) : 0
            return below.scale + (scales[above].scale - below.scale) * mix
        }
    }
    private var move: Move?
    /// How much of the picture the device covers at this angle from where the camera is now.
    func drawnExtent(at angle: Double) -> CGSize {
        twin.camera.simdTransform = cameraNode.simdTransform
        _ = twinCentre(at: angle)
        guard let box = measureOnScreen(twin.scene, from: twin.camera).box else { return .zero }
        return CGSize(width: CGFloat(box.maxX - box.minX), height: CGFloat(box.maxY - box.minY))
    }

    /// How many probe renders have been made, for a test that expects a move to make none.
    var probeRenders = 0
    /// SceneKit calls back on its render thread, so the count is kept behind a lock.
    private let renders = OSAllocatedUnfairLock(initialState: 0)
    public var renderCount: Int { renders.withLock { $0 } }
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
        // No animation players: a player churn per pose blocks behind the render thread for most
        // of a frame, while setting thirty transforms by hand is free.
        tracks = Self.freeze(scene.rootNode).flatMap { PoseTrack.tracks(of: $0.animation, on: $0.node) }
        // A source hands out its clips once, so the twin comes from a source of its own.
        guard let twinSource = SCNSceneSource(url: asset, options: nil),
              let twinScene = twinSource.scene(options: [
                  .animationImportPolicy: SCNSceneSource.AnimationImportPolicy.play,
              ]) else { return nil }
        let twinFaces = Self.flatFaces(in: twinScene.rootNode)
        guard let twinInner = Self.closest(to: CGSize(width: 15.797, height: 11.082), among: twinFaces),
              let twinCover = Self.closest(to: CGSize(width: 11.230, height: 7.739), among: twinFaces) else { return nil }
        let twinCamera = SCNNode()
        twinCamera.camera = SCNCamera()
        twinCamera.camera?.fieldOfView = 31
        twinCamera.camera?.zNear = 0.01
        twinCamera.camera?.zFar = 200
        twinScene.rootNode.addChildNode(twinCamera)
        // No renderer that only takes snapshots evaluates a clip, so the twin's clips are read as
        // keyframe tracks and its nodes are posed by hand.
        let twinTracks = Self.freeze(twinScene.rootNode).flatMap { PoseTrack.tracks(of: $0.animation, on: $0.node) }
        twin = Twin(
            scene: twinScene,
            camera: twinCamera,
            bones: (twinInner.skinner?.bones ?? []) + (twinCover.skinner?.bones ?? []),
            tracks: twinTracks
        )

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
        // Drawn when the scene changes, so a still screen costs nothing. SceneKit keeps drawing for
        // about a quarter of a second after each change, a new frame from the device included
        // (Xcode 27.1, 27A9269).
        rendersContinuously = false
        // Asked for 30, SceneKit draws at 24 on a 120 Hz display, and the rate cannot be changed
        // once the view exists; a fold needs 60 to look like one.
        preferredFramesPerSecond = 60
        isPlaying = false
        loops = false
        delegate = self

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
        if let move, let fraction = move.fraction(of: hingeAngle) {
            let correction = move.start + (move.end - move.start) * Float(fraction)
            // The twin's bones, not this scene's: a read here waits behind the render thread.
            place(
                cameraNode, angle: hingeAngle, centre: twinCentre(at: hingeAngle),
                correction: correction, distanceScale: move.scale(at: hingeAngle)
            )
        } else {
            frameCamera()
        }
    }

    /// Framed from both ends, measured on the twin now; a probe render costs more than a frame, so
    /// none happens per step.
    public func beginMove(to target: Double) {
        let to = min(max(target, 0), 180)
        guard abs(to - hingeAngle) > 0.01 else { return }
        settleFraming()
        let start = framing(at: hingeAngle)
        let end = framing(at: to)
        // The device stands tallest below 50 degrees, so that stretch of the way is sampled every
        // five degrees; above it the open device is the widest thing and always fits.
        var scales = [(angle: hingeAngle, scale: start.distanceScale), (angle: to, scale: end.distanceScale)]
        let low = min(hingeAngle, to)
        let high = min(max(hingeAngle, to), Self.standingBand)
        for sample in stride(from: (low / 5).rounded(.up) * 5, through: high, by: 5) where sample > low && sample < max(hingeAngle, to) {
            let fraction = Float((sample - hingeAngle) / (to - hingeAngle))
            scales.append((sample, fit(at: sample, correction: start.correction + (end.correction - start.correction) * fraction)))
        }
        scales.sort { $0.angle < $1.angle }
        move = Move(from: hingeAngle, to: to, start: start.correction, end: end.correction, scales: scales)
    }

    /// How far back the camera has to stand at this angle for the device to fit, from one look.
    private func fit(at angle: Double, correction: SIMD3<Float>) -> Float {
        let key = Int((angle * 100).rounded())
        if let kept = fits[key] { return kept }
        let centre = twinCentre(at: angle)
        place(twin.camera, angle: angle, centre: centre, correction: correction, distanceScale: 1)
        let scale = scaleToFit(measureOnScreen(twin.scene, from: twin.camera).box, at: angle, centre: centre, from: 1)
        fits[key] = scale
        return scale
    }

    /// A device cut off by the picture's edge measures as exactly full, so a clipped look is sized
    /// again from twice as far.
    private func scaleToFit(
        _ box: (minX: Float, maxX: Float, minY: Float, maxY: Float)?, at angle: Double, centre: SIMD3<Float>, from scale: Float
    ) -> Float {
        guard let box else { return scale }
        var fill = max(box.maxX - box.minX, box.maxY - box.minY)
        guard fill > Self.fillLimit else { return scale }
        if fill >= 0.999 {
            place(twin.camera, angle: angle, centre: centre, correction: .zero, distanceScale: scale * 2)
            if let far = measureOnScreen(twin.scene, from: twin.camera).box {
                fill = max(fill, max(far.maxX - far.minX, far.maxY - far.minY) * 2)
            }
        }
        // A little more than measured: the way between two looks can stand taller than either.
        return scale * fill / Self.fillTarget * 1.02
    }

    public func endMove() {
        guard move != nil else { return }
        move = nil
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
        // The guest changes screens part way through a move; the move's end frames the pose.
        if move == nil { frameCamera() }
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
        for track in tracks { track.apply(at: time) }
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
    private var visibleBones: [SCNNode] {
        (innerScreen.skinner?.bones ?? []) + (coverScreen.skinner?.bones ?? [])
    }

    private func posedCentre(of bones: [SCNNode]) -> SIMD3<Float> {
        guard !bones.isEmpty else { return .zero }
        let points = bones.map { node -> SIMD3<Float> in
            let transform = node.worldTransform
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

    private func heldDistance(at angle: Double) -> Float {
        let orbit = Self.cameraOrbit(forHingeAngle: angle)
        let orbitProgress = Float(min(1, abs(orbit) / (.pi / 2)))
        let fraction = Self.projectedWidthFraction(hingeAngle: angle, orbit: orbit)
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
        settleFraming()
        let framing = framing(at: hingeAngle)
        // The twin's centre, not this scene's: off screen, nothing has drawn this pose yet.
        place(
            cameraNode, angle: hingeAngle, centre: framing.centre,
            correction: framing.correction, distanceScale: framing.distanceScale
        )
        silhouette = framing.silhouette
        projectButtons()
    }

    /// Measurements belong to a window size and a way up; either changing throws them away.
    private func settleFraming() {
        guard referenceHalfAcross == 0 || bounds.size != measuredSize || guestQuarterTurns != measuredTurns else { return }
        measuredSize = bounds.size
        measuredTurns = guestQuarterTurns
        measureFlat()
        framings.removeAll()
        fits.removeAll()
    }

    /// Measured on the twin once per angle and kept.
    private func framing(at angle: Double) -> Framing {
        let key = Int((angle * 100).rounded())
        if let kept = framings[key] { return kept }
        let centre = twinCentre(at: angle)
        var scale: Float = 1
        var analytic = place(twin.camera, angle: angle, centre: centre, correction: .zero, distanceScale: scale)
        var seen = recentre(twin.camera, in: twin.scene)
        for _ in 0..<3 {
            let fitted = scaleToFit(seen.box, at: angle, centre: centre, from: scale)
            guard fitted > scale else { break }
            scale = fitted
            analytic = place(twin.camera, angle: angle, centre: centre, correction: .zero, distanceScale: scale)
            seen = recentre(twin.camera, in: twin.scene)
        }
        let made = Framing(
            centre: centre, correction: twin.camera.simdPosition - analytic,
            distanceScale: scale, silhouette: seen.silhouette
        )
        framings[key] = made
        return made
    }

    /// Where the hinge is once the twin is posed at this angle.
    private func twinCentre(at angle: Double) -> SIMD3<Float> {
        let time = Pose.time(forHingeAngle: angle)
        for track in twin.tracks { track.apply(at: time) }
        return posedCentre(of: twin.bones)
    }

    @discardableResult
    private func place(
        _ camera: SCNNode, angle: Double, centre: SIMD3<Float>, correction: SIMD3<Float>, distanceScale: Float
    ) -> SIMD3<Float> {
        let orbit = Self.cameraOrbit(forHingeAngle: angle)
        let direction = SIMD3<Float>(Float(sin(orbit)), Float(cos(orbit)), 0)
        // A bent device stands taller and needs more room; open stays tight to the window.
        let bend = Float(sin(.pi * (180 - min(max(angle, 0), 180)) / 180))
        let analytic = centre + direction * (heldDistance(at: angle) * (1 + 0.2 * bend) * distanceScale)
        camera.simdPosition = analytic
        camera.look(
            at: SCNVector3(centre),
            up: SCNVector3(Self.cameraUp(quarterTurns: guestQuarterTurns, direction: direction)),
            localFront: SCNVector3(0, 0, -1)
        )
        camera.simdPosition = analytic + correction
        return analytic
    }

    private func measureOnScreen(
        _ scene: SCNScene,
        from camera: SCNNode
    ) -> (box: (minX: Float, maxX: Float, minY: Float, maxY: Float)?, silhouette: (width: Int, height: Int, pixels: [Bool])) {
        probeRenders += 1
        probe.scene = scene
        probe.pointOfView = camera
        let aspect = Float(max(bounds.width, 1) / max(bounds.height, 1))
        let size = CGSize(width: 160, height: 160 / CGFloat(aspect))
        let image = probe.snapshot(atTime: 0, with: size, antialiasingMode: .none)
        guard let raster = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()) else {
            return (nil, (0, 0, []))
        }

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
        let seen = (raster.pixelsWide, raster.pixelsHigh, pixels)
        guard maxX >= minX, maxY >= minY else { return (nil, seen) }
        return ((
            Float(minX) / Float(raster.pixelsWide),
            Float(maxX + 1) / Float(raster.pixelsWide),
            Float(minY) / Float(raster.pixelsHigh),
            Float(maxY + 1) / Float(raster.pixelsHigh)
        ), seen)
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
    /// Walks the camera until the device is centred, and hands back what was seen from there.
    private func recentre(
        _ camera: SCNNode, in scene: SCNScene
    ) -> (box: (minX: Float, maxX: Float, minY: Float, maxY: Float)?, silhouette: (width: Int, height: Int, pixels: [Bool])?) {
        let aspect = Float(max(bounds.width, 1) / max(bounds.height, 1))
        var last: (box: (minX: Float, maxX: Float, minY: Float, maxY: Float)?, silhouette: (width: Int, height: Int, pixels: [Bool])?) = (nil, nil)
        // A box cut off by the picture's edge under-corrects; several passes walk it in.
        for _ in 0..<8 {
            let (box, seen) = measureOnScreen(scene, from: camera)
            last = (box, seen)
            guard let box else { return last }
            let offsetX = (box.minX + box.maxX) / 2 - 0.5
            let offsetY = (box.minY + box.maxY) / 2 - 0.5
            if abs(offsetX) < 0.004, abs(offsetY) < 0.004 { return last }

            let transform = camera.simdTransform
            let right = simd_normalize(simd_make_float3(transform.columns.0))
            let up = simd_normalize(simd_make_float3(transform.columns.1))
            let distance = simd_length(camera.simdPosition)
            let visibleHeight = 2 * distance * tan(Float(31) * .pi / 360)
            camera.simdPosition += right * (offsetX * visibleHeight * aspect)
                - up * (offsetY * visibleHeight)
        }
        return last
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
                let projected = viewPoint(of: position)
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
        let position = lift.outward * amount
        let scale = SIMD3<Float>(repeating: 1) + abs(lift.outward) * (amount / lift.depth)
        // An explicit transaction commits behind the render thread, which costs most of a frame
        // in a live window; a plain set costs nothing and the run loop commits it.
        if liftDuration > 0 {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = liftDuration
            lift.node.simdPosition = position
            lift.node.simdScale = scale
            SCNTransaction.commit()
        } else {
            lift.node.simdPosition = position
            lift.node.simdScale = scale
        }
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
        let transform = simd_float4x4(bone.worldTransform)
        let origin = simd_make_float3(transform.columns.3)
        let tip = origin + simd_make_float3(transform * SIMD4<Float>(lift.outward, 0)) * amount
        let from = viewPoint(of: origin)
        let to = viewPoint(of: tip)
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
        let (near, far) = ray(through: point)
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

/// One node property of the closing clip, read from its keyframes so a pose can be set by hand.
struct PoseTrack {
    enum Property { case position, orientation, scale }
    let node: SCNNode
    let property: Property
    let duration: Double
    let keyTimes: [Double]
    let values: [SIMD4<Float>]

    /// The clip is a group of keyframe tracks, each keyed by a path naming the node it drives.
    static func tracks(of animation: SCNAnimation, on attached: SCNNode) -> [PoseTrack] {
        guard let group = CAAnimation(scnAnimation: animation) as? CAAnimationGroup else { return [] }
        return (group.animations ?? []).compactMap { member -> PoseTrack? in
            guard let keyframes = member as? CAKeyframeAnimation, let path = keyframes.keyPath,
                  let dot = path.lastIndex(of: "."), keyframes.duration > 0 else { return nil }
            let name = String(path[path.index(after: path.startIndex)..<dot])
            let property: Property
            switch path[path.index(after: dot)...] {
            case "position": property = .position
            case "orientation": property = .orientation
            case "scale": property = .scale
            default: return nil
            }
            guard let node = attached.name == name ? attached : attached.childNode(withName: name, recursively: true) else { return nil }
            let keyTimes = (keyframes.keyTimes ?? []).map(\.doubleValue)
            let values = (keyframes.values ?? []).compactMap { value -> SIMD4<Float>? in
                // SceneKit keeps a clip's vectors as four doubles in a rect shaped value.
                guard let rect = (value as? NSValue)?.rectValue else { return nil }
                return SIMD4<Float>(Float(rect.origin.x), Float(rect.origin.y), Float(rect.size.width), Float(rect.size.height))
            }
            guard keyTimes.count == values.count, !values.isEmpty else { return nil }
            return PoseTrack(node: node, property: property, duration: keyframes.duration, keyTimes: keyTimes, values: values)
        }
    }

    func apply(at time: TimeInterval) {
        let fraction = min(max(time / duration, 0), 1)
        var upper = keyTimes.firstIndex { $0 >= fraction } ?? keyTimes.count - 1
        upper = max(upper, 0)
        let lower = max(upper - 1, 0)
        let span = keyTimes[upper] - keyTimes[lower]
        let mix = span > 0 ? Float((fraction - keyTimes[lower]) / span) : 0
        var a = values[lower]
        let b = values[upper]
        if property == .orientation, simd_dot(a, b) < 0 { a = -a }
        var value = a + (b - a) * mix
        switch property {
        case .position: node.simdPosition = SIMD3(value.x, value.y, value.z)
        case .scale: node.simdScale = SIMD3(value.x, value.y, value.z)
        case .orientation:
            value = simd_normalize(value)
            node.simdOrientation = simd_quatf(ix: value.x, iy: value.y, iz: value.z, r: value.w)
        }
    }
}

/// The view's own projection reads the camera as last drawn, which off screen is never; these read
/// the camera as placed.
extension DuoModelView {
    private var cameraFrame: (world: simd_float4x4, tanHalfWidth: Float, tanHalfHeight: Float) {
        let tanHalfHeight = tan(Float(pointOfView?.camera?.fieldOfView ?? 31) * .pi / 360)
        let aspect = Float(max(bounds.width, 1) / max(bounds.height, 1))
        return (pointOfView?.simdWorldTransform ?? matrix_identity_float4x4, tanHalfHeight * aspect, tanHalfHeight)
    }

    func viewPoint(of world: SIMD3<Float>) -> CGPoint {
        let frame = cameraFrame
        let local = simd_inverse(frame.world) * SIMD4<Float>(world, 1)
        let depth = max(-local.z, 0.0001)
        let x = local.x / depth / frame.tanHalfWidth
        let y = local.y / depth / frame.tanHalfHeight
        return CGPoint(x: CGFloat(x + 1) / 2 * bounds.width, y: CGFloat(y + 1) / 2 * bounds.height)
    }

    func ray(through point: CGPoint) -> (SCNVector3, SCNVector3) {
        let frame = cameraFrame
        let x = Float(point.x / max(bounds.width, 1)) * 2 - 1
        let y = Float(point.y / max(bounds.height, 1)) * 2 - 1
        let direction = SIMD4<Float>(x * frame.tanHalfWidth, y * frame.tanHalfHeight, -1, 0)
        let origin = simd_make_float3(frame.world.columns.3)
        let far = origin + simd_normalize(simd_make_float3(frame.world * direction)) * 200
        return (SCNVector3(origin), SCNVector3(far))
    }
}

extension DuoModelView: SCNSceneRendererDelegate {
    public nonisolated func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        renders.withLock { $0 += 1 }
    }
}
