import Foundation

/// Links that name a device.
///
/// Xcode and other tools open `devices://` links, which Device Hub owns. This app can take that
/// over, which is only useful if it can tell a link it understands from one it does not: a link
/// naming a physical device, or asking for something only Device Hub does, has to be handed back
/// rather than swallowed.
public enum DeviceLink {
    public enum Destination: Equatable, Sendable {
        /// A simulator this app can show, by UDID.
        case simulator(udid: String)
        /// Anything else on the `devices` scheme, to be passed to Device Hub untouched.
        case deviceHub
        case notADeviceLink
    }

    /// The routes Device Hub uses, learned by inspection. Anything else on the scheme is still a
    /// Device Hub link, it is just not one this app claims to understand.
    static let deviceHubRoutes = ["/device/open", "/manage/select"]

    public static func destination(for url: URL, ownScheme: String = Brand.urlScheme) -> Destination {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else {
            return .notADeviceLink
        }
        // A link carrying credentials, a port or a fragment is not one of ours, whatever it says.
        guard components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil else {
            return scheme == "devices" ? .deviceHub : .notADeviceLink
        }

        let host = components.host?.lowercased() ?? ""
        let route = (host.isEmpty ? "" : "/" + host) + components.path

        if scheme == ownScheme.lowercased() {
            let isOpen = host == "open" && ["", "/"].contains(components.path)
            guard isOpen, let udid = onlyQueryValue(components, named: "udid") else {
                return .notADeviceLink
            }
            return .simulator(udid: udid)
        }

        guard scheme == "devices" else { return .notADeviceLink }
        guard deviceHubRoutes.contains(route),
              let id = onlyQueryValue(components, named: "id") else {
            return .deviceHub
        }
        return .simulator(udid: id)
    }

    /// Exactly one query item with the expected name, and a real UUID. More than one means the link
    /// is asking for something extra that only Device Hub knows how to honour.
    private static func onlyQueryValue(_ components: URLComponents, named name: String) -> String? {
        guard let items = components.queryItems, items.count == 1, items[0].name == name,
              let value = items[0].value, let uuid = UUID(uuidString: value) else {
            return nil
        }
        return uuid.uuidString
    }
}
