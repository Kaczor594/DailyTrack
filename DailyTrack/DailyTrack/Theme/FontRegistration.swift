import CoreText
import Foundation

/// Registers the bundled design-system fonts (Spectral, Archivo, IBM Plex Mono)
/// for the current process. Works identically on iOS, macOS, and inside the
/// widget extension — call once from the app's and the widget bundle's init.
enum FontRegistration {
    static func registerBundledFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            // Ignore individual failures (e.g. already registered on re-init).
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
