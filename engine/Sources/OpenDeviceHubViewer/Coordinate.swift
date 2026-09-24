import Foundation

/// A latitude and longitude typed by a person.
///
/// Its own type in the library rather than a helper beside the dialog, because parsing what someone
/// typed is the part that can be got wrong quietly, and it can only be tested here.
public struct Coordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init?(parsing text: String) {
        let parts = text.split(separator: ",")
        guard parts.count == 2,
              let latitude = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let longitude = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return nil
        }
        self.latitude = latitude
        self.longitude = longitude
    }
}
