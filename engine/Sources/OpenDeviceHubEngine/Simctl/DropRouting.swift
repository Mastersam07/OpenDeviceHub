import Foundation

/// What dropping a file on a device window should do, decided by its extension. Pure, so the
/// routing is tested without touching a device.
public enum DropAction: Sendable, Hashable {
    case installApp(URL)
    case addMedia([URL])
    case addRootCertificate(URL)
    case openURL(String)
    case unsupported(URL)

    /// Adding a root certificate changes what the device trusts, so it is confirmed first.
    public var needsConfirmation: Bool {
        if case .addRootCertificate = self { return true }
        return false
    }
}

public enum DropRouting {
    static let mediaExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "bmp",
        "mov", "mp4", "m4v", "vcf",
    ]
    static let certificateExtensions: Set<String> = ["cer", "pem", "der", "crt"]

    /// Media files are grouped into one action, since `simctl addmedia` takes several paths, while
    /// everything else is decided per file.
    public static func actions(for urls: [URL]) -> [DropAction] {
        var actions: [DropAction] = []
        var media: [URL] = []

        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "app" {
                actions.append(.installApp(url))
            } else if certificateExtensions.contains(ext) {
                actions.append(.addRootCertificate(url))
            } else if mediaExtensions.contains(ext) {
                media.append(url)
            } else {
                actions.append(.unsupported(url))
            }
        }

        if !media.isEmpty {
            actions.insert(.addMedia(media), at: 0)
        }
        return actions
    }
}
