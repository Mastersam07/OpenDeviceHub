import AppKit

// The app icon and the social banner, drawn in code so every size comes from one description rather
// than from exported files that drift: two device windows, one in front of the other, which is what
// this app does that the tool it replaces does not.
let plateGradient = NSGradient(
    starting: NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.86, alpha: 1),
    ending: NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.45, alpha: 1)
)!

// The two device outlines, in a 1024 unit design space placed by `unit` and `origin`, so the icon
// and the social banner draw the same artwork rather than two copies of it that drift.
//
// `paintBackground` is what the front device cuts back to. It has to be passed in because the icon
// sits on a rounded plate and the banner on a full bleed gradient.
func drawDevices(unit: CGFloat, origin: CGPoint, paintBackground: () -> Void) {
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(
            x: origin.x + x * unit,
            y: origin.y + y * unit,
            width: width * unit,
            height: height * unit
        )
    }

    func device(
        x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
        line: CGFloat, alpha: CGFloat
    ) {
        let body = NSBezierPath(
            roundedRect: rect(x, y, width, height),
            xRadius: 54 * unit,
            yRadius: 54 * unit
        )
        body.lineWidth = line * unit
        NSColor.white.withAlphaComponent(alpha).setStroke()
        body.stroke()

        let island = NSBezierPath(
            roundedRect: rect(x + 96, y + height - 74, 100, 30),
            xRadius: 15 * unit,
            yRadius: 15 * unit
        )
        NSColor.white.withAlphaComponent(alpha).setFill()
        island.fill()

        let indicator = NSBezierPath(
            roundedRect: rect(x + 96, y + 40, 100, 14),
            xRadius: 7 * unit,
            yRadius: 7 * unit
        )
        NSColor.white.withAlphaComponent(0.8 * alpha).setFill()
        indicator.fill()
    }

    device(x: 286, y: 330, width: 268, height: 500, line: 24, alpha: 0.75)

    // The front device cuts back to the background before it is drawn. Without that the two outlines
    // cross and it reads as a tangle rather than as one window in front of another, which is the
    // whole point of it and the first thing to go at small sizes.
    let front = NSBezierPath(
        roundedRect: rect(452, 214, 292, 548),
        xRadius: 54 * unit,
        yRadius: 54 * unit
    )
    NSGraphicsContext.saveGraphicsState()
    front.addClip()
    paintBackground()
    NSGraphicsContext.restoreGraphicsState()

    device(x: 452, y: 214, width: 292, height: 548, line: 26, alpha: 1)
}

// `edgeToEdge` drops the rounded plate and the transparent margin around it, filling the square
// instead. Avatars are cropped to a circle or a rounded square by whoever displays them, so a
// picture that rounds its own corners first loses a ring of artwork to the second rounding.
func drawIcon(size: CGFloat, edgeToEdge: Bool = false) {
    // Edge to edge scales the artwork so the plate fills the canvas, keeping every proportion inside
    // it, rather than drawing something different.
    let unit = size / (edgeToEdge ? 864 : 1024)
    let inset = edgeToEdge ? 80 * unit : 0
    let plate = NSBezierPath(
        roundedRect: NSRect(
            x: 80 * unit - inset,
            y: 80 * unit - inset,
            width: 864 * unit,
            height: 864 * unit
        ),
        xRadius: edgeToEdge ? 0 : 190 * unit,
        yRadius: edgeToEdge ? 0 : 190 * unit
    )
    func paintPlate() { plateGradient.draw(in: plate, angle: -90) }
    paintPlate()
    drawDevices(
        unit: unit,
        origin: CGPoint(x: -inset, y: -inset),
        paintBackground: paintPlate
    )
}

// Drawn into a bitmap of exactly the asked for pixel size. Going through `NSImage.lockFocus` instead
// hands back the main display's backing scale, so on a Retina Mac every file came out at twice the
// size its name promised.
func png(size: Int, edgeToEdge: Bool = false) -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("could not make a \(size) bitmap")
        exit(1)
    }
    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    drawIcon(size: CGFloat(size), edgeToEdge: edgeToEdge)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        print("could not encode \(size)")
        exit(1)
    }
    return data
}

// GitHub asks for at least 640x320 and shows 1280x640 best. It also crops the edges in some places,
// so everything that matters stays well inside the frame.
func socialPreview(width: Int = 1280, height: Int = 640) -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("could not make the banner bitmap")
        exit(1)
    }
    bitmap.size = NSSize(width: width, height: width == 0 ? 0 : height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
    func paintBackground() {
        plateGradient.draw(in: NSBezierPath(rect: frame), angle: -90)
    }
    paintBackground()

    // The artwork is 1024 units wide whatever it is drawn at, so it is placed by its centre.
    let artwork: CGFloat = 470
    let unit = artwork / 1024
    drawDevices(
        unit: unit,
        origin: CGPoint(x: 245 - 512 * unit, y: CGFloat(height) / 2 - 512 * unit),
        paintBackground: paintBackground
    )

    let left: CGFloat = 470
    let title = "OpenDeviceHub"
    let tagline = "Your iOS simulators in windows again, one per device."
    let footnote = "Open source, MIT licensed. For Xcode 26 and 27 on macOS 14 or later."

    title.draw(
        at: NSPoint(x: left, y: CGFloat(height) / 2 + 16),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 76, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
    )
    tagline.draw(
        at: NSPoint(x: left + 4, y: CGFloat(height) / 2 - 44),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 31, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
        ]
    )
    footnote.draw(
        at: NSPoint(x: left + 4, y: CGFloat(height) / 2 - 100),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 23, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.66),
        ]
    )

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        print("could not encode the banner")
        exit(1)
    }
    return data
}

let outputDirectory = CommandLine.arguments[1]

if CommandLine.arguments.contains("--social") {
    try socialPreview().write(to: URL(fileURLWithPath: "\(outputDirectory)/social-preview.png"))
    print("wrote the social preview to \(outputDirectory)")
    exit(0)
}

if CommandLine.arguments.contains("--marketing") {
    // Sizes people actually ask for: favicons, a README header, an avatar, and one big enough to
    // hand to a designer or to a store listing.
    for size in [16, 32, 48, 64, 128, 180, 256, 512, 1024] {
        try png(size: size).write(to: URL(fileURLWithPath: "\(outputDirectory)/icon-\(size).png"))
    }
    for size in [400, 512, 1024] {
        try png(size: size, edgeToEdge: true)
            .write(to: URL(fileURLWithPath: "\(outputDirectory)/icon-square-\(size).png"))
    }
    print("wrote the marketing icons to \(outputDirectory)")
    exit(0)
}

// The ten slots `iconutil` reads, by the only names it accepts. A file named anything else, such as
// `icon_64x64.png` or `icon_1024x1024.png`, is ignored without a word, which is how the icon came to
// stop at 512 and look soft wherever macOS asks for a bigger one.
let slots: [(pixels: Int, name: String)] = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x"),
]
var rendered: [Int: Data] = [:]
for slot in slots {
    let data = rendered[slot.pixels] ?? png(size: slot.pixels)
    rendered[slot.pixels] = data
    try data.write(to: URL(fileURLWithPath: "\(outputDirectory)/\(slot.name).png"))
}
print("wrote icon set to \(outputDirectory)")
