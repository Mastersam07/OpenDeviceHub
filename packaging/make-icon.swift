import AppKit

// Draws the placeholder app icon: a rounded square with a device outline on it. Deliberately plain,
// and meant to be replaced by real artwork before anyone sees it.
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let unit = size / 1024
    let plate = NSBezierPath(
        roundedRect: NSRect(x: 80 * unit, y: 80 * unit, width: 864 * unit, height: 864 * unit),
        xRadius: 190 * unit,
        yRadius: 190 * unit
    )
    NSGradient(
        starting: NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.86, alpha: 1),
        ending: NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.45, alpha: 1)
    )?.draw(in: plate, angle: -90)

    let body = NSBezierPath(
        roundedRect: NSRect(x: 366 * unit, y: 238 * unit, width: 292 * unit, height: 548 * unit),
        xRadius: 54 * unit,
        yRadius: 54 * unit
    )
    body.lineWidth = 26 * unit
    NSColor.white.setStroke()
    body.stroke()

    let island = NSBezierPath(
        roundedRect: NSRect(x: 462 * unit, y: 712 * unit, width: 100 * unit, height: 30 * unit),
        xRadius: 15 * unit,
        yRadius: 15 * unit
    )
    NSColor.white.setFill()
    island.fill()

    let indicator = NSBezierPath(
        roundedRect: NSRect(x: 462 * unit, y: 278 * unit, width: 100 * unit, height: 14 * unit),
        xRadius: 7 * unit,
        yRadius: 7 * unit
    )
    NSColor.white.withAlphaComponent(0.8).setFill()
    indicator.fill()

    return image
}

let outputDirectory = CommandLine.arguments[1]
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = drawIcon(size: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("could not render \(size)")
        exit(1)
    }
    let scale = size >= 32 && size <= 512 ? "\(size / 2)x\(size / 2)@2x" : "\(size)x\(size)"
    try png.write(to: URL(fileURLWithPath: "\(outputDirectory)/icon_\(scale).png"))
    if size <= 512 {
        try png.write(to: URL(fileURLWithPath: "\(outputDirectory)/icon_\(size)x\(size).png"))
    }
}
print("wrote icon set to \(outputDirectory)")
