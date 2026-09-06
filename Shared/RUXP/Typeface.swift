import CoreText
import Foundation
import SwiftUI

/// Season 01 typefaces, bundled in `Shared/Fonts` and registered at launch on both
/// iPhone and Apple Watch (no Info.plist `UIAppFonts` needed with runtime registration).
///
/// - Orbitron: wide geometric techno. Wordmark, event titles, HUD numbers.
/// - Exo 2: extended sans with a real italic. Taglines, buttons, UI text.
/// - JetBrains Mono: terminal readouts. XP, timers, eyebrows, set/rep data.
///
/// All three are SIL Open Font License; the licenses ship next to the files.
enum Typeface {
    // Orbitron
    static let orbitronBlack = "Orbitron-Black"
    static let orbitronExtraBold = "Orbitron-ExtraBold"
    static let orbitronBold = "Orbitron-Bold"
    static let orbitronMedium = "Orbitron-Medium"

    // Exo 2
    static let exoBlack = "Exo2-Black"
    static let exoExtraBold = "Exo2-ExtraBold"
    static let exoBold = "Exo2-Bold"
    static let exoSemiBold = "Exo2-SemiBold"
    static let exoMedium = "Exo2-Medium"
    static let exoRegular = "Exo2-Regular"
    static let exoBlackItalic = "Exo2-BlackItalic"
    static let exoExtraBoldItalic = "Exo2-ExtraBoldItalic"
    static let exoBoldItalic = "Exo2-BoldItalic"
    static let exoSemiBoldItalic = "Exo2-SemiBoldItalic"
    static let exoMediumItalic = "Exo2-MediumItalic"

    // JetBrains Mono
    static let monoExtraBold = "JetBrainsMono-ExtraBold"
    static let monoBold = "JetBrainsMono-Bold"
    static let monoMedium = "JetBrainsMono-Medium"

    /// Exo 2 face for a SwiftUI weight.
    static func exo(_ weight: Font.Weight, italic: Bool = false) -> String {
        switch weight {
        case .black: return italic ? exoBlackItalic : exoBlack
        case .heavy: return italic ? exoExtraBoldItalic : exoExtraBold
        case .bold: return italic ? exoBoldItalic : exoBold
        case .semibold: return italic ? exoSemiBoldItalic : exoSemiBold
        case .regular, .light, .thin, .ultraLight: return italic ? exoMediumItalic : exoRegular
        default: return italic ? exoMediumItalic : exoMedium
        }
    }

    /// JetBrains Mono face for a SwiftUI weight.
    static func mono(_ weight: Font.Weight) -> String {
        switch weight {
        case .black, .heavy: return monoExtraBold
        case .bold, .semibold: return monoBold
        default: return monoMedium
        }
    }

    /// Orbitron face for a SwiftUI weight.
    static func orbitron(_ weight: Font.Weight) -> String {
        switch weight {
        case .black: return orbitronBlack
        case .heavy: return orbitronExtraBold
        case .bold, .semibold: return orbitronBold
        default: return orbitronMedium
        }
    }

    private static var didRegister = false

    /// Registers every bundled `.ttf` with CoreText. Safe to call more than once.
    static func registerFonts() {
        guard !didRegister else { return }
        didRegister = true
        let bundle = Bundle.main
        var urls = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        urls += bundle.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        guard !urls.isEmpty else {
            #if DEBUG
            print("[Typeface] no .ttf resources found in \(bundle.bundleURL.lastPathComponent)")
            #endif
            return
        }
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                #if DEBUG
                // Already-registered is the only expected failure (e.g. app relaunch in previews).
                if let error = error?.takeRetainedValue(),
                   CFErrorGetCode(error) != CTFontManagerError.alreadyRegistered.rawValue {
                    print("[Typeface] failed to register \(url.lastPathComponent): \(error)")
                }
                #endif
            }
        }
    }
}
