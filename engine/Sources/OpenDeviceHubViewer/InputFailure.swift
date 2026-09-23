import OpenDeviceHubEngine

/// Tells a refused event apart from a session that has stopped working.
///
/// The difference matters because the two look identical from the window: nothing happens. A guest
/// that will not take three contacts is behaving correctly and the next gesture will work; a
/// session whose device has gone will never take anything again, and the window has to say so
/// rather than swallow every click in silence.
enum InputFailure {
    static func endsTheSession(_ error: any Error) -> Bool {
        switch error {
        case EngineError.capabilityUnavailable:
            // The gesture is not supported. The session is fine.
            false
        case is CancellationError:
            false
        default:
            true
        }
    }

    /// What to put in front of the user. The underlying text names a private selector often enough
    /// that it is worth leading with what it means for them.
    static func message(for error: any Error) -> String {
        "Input stopped reaching the device.\n\(error.localizedDescription)"
    }
}
