import Carbon.HIToolbox
import Foundation

/// The language the Mac's keyboard is currently typing in.
///
/// The input source rather than the locale: someone in Lagos typing on a French keyboard wants the
/// guest set to French, and their locale would say otherwise.
public enum KeyboardLanguage {
    public static func current() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return fallback()
        }
        let languages = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String]
        return languages?.first ?? fallback()
    }

    /// A keyboard with no language of its own, which some input sources genuinely have.
    private static func fallback() -> String? {
        Locale.current.language.languageCode?.identifier
    }
}
