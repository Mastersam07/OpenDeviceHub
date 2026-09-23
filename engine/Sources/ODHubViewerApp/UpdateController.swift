import AppKit
import OpenDeviceHubEngine
import Sparkle

/// In-app updates, and the gate that decides whether they exist at all.
///
/// The updater only starts when the running bundle carries both a feed to ask and a public key to
/// check the answer against. A source build has no bundle and therefore neither, so it never
/// reaches the release channel: no request is made, no menu item appears, and Sparkle's background
/// scheduler is never created.
@MainActor
final class UpdateController {
    /// What an update needs before it can be trusted. Without the key, a feed is just a stranger
    /// offering software.
    struct Configuration: Equatable {
        let feed: String
        let publicKey: String

        /// Read from the bundle rather than compiled in, so the same binary is a development build
        /// outside a bundle and a release inside one.
        static func fromBundle(_ bundle: Bundle = .main) -> Configuration? {
            guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
                  let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
                  !feed.isEmpty,
                  !key.isEmpty,
                  URL(string: feed)?.scheme == "https" else {
                return nil
            }
            return Configuration(feed: feed, publicKey: key)
        }
    }

    private let controller: SPUStandardUpdaterController

    /// Nil when this build is not configured for updates, which is what keeps the updater out of
    /// source builds entirely rather than merely quiet in them.
    init?(configuration: Configuration? = .fromBundle()) {
        guard configuration != nil else { return nil }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Whether the updater found the feed usable, for reporting rather than for control flow.
    var feedURL: String? {
        controller.updater.feedURL?.absoluteString
    }
}
