import SwiftUI

/// Design-system tokens for DailyTrack (Isaac Kaczor design system:
/// paper + stone + moss natural palette, Spectral/Archivo/IBM Plex Mono).
/// Colors resolve from Theme.xcassets (light + dark appearances).
/// Shared between the main app and the widget extension.
enum Theme {
    // MARK: - Surfaces

    static let background = Color("ThemeBackground")
    static let surface = Color("ThemeSurface")
    static let panel = Color("ThemePanel")
    static let divider = Color("ThemeDivider")

    // MARK: - Text

    static let ink = Color("ThemeInk")
    static let inkSecondary = Color("ThemeInkSecondary")
    static let inkTertiary = Color("ThemeInkTertiary")

    // MARK: - Brand & semantic

    static let brand = Color("ThemeBrand")
    static let brandSubtle = Color("ThemeBrandSubtle")
    static let terra = Color("ThemeTerra")
    static let terraSubtle = Color("ThemeTerraSubtle")
    static let positive = Color("ThemePositive")
    static let negative = Color("ThemeNegative")
    static let info = Color("ThemeInfo")

    // MARK: - Chart colors (single-series app; the full ordered data palette
    // lives in kaczor-design tokens.css if multi-series charts ever come)

    static let chartMoss = Color("ChartMoss")
    static let chartDust = Color("ChartDust")

    // MARK: - Score color (single source of truth for app + widget)

    /// Unified score/progress color ramp. Replaces the previously drifted
    /// per-view threshold helpers (app 0.4/0.7/0.9 vs widget 0.3/0.7).
    static func scoreColor(_ ratio: Double) -> Color {
        guard ratio > 0 else { return inkTertiary }   // not started — quiet, not alarming
        switch ratio {
        case ..<0.4: return negative                  // barn red
        case ..<0.7: return terra                     // terracotta
        case ..<0.9: return chartDust                 // dust gold
        default: return brand                         // moss
        }
    }

    // MARK: - Heatmap (moss ramp; intensity rises with score in both modes)

    static func heatmapColor(score: Double?) -> Color {
        guard let score else { return surface }       // no data
        guard score > 0 else { return Color("HeatmapZero") }
        switch score {
        case ..<0.4: return Color("HeatmapL1")
        case ..<0.7: return Color("HeatmapL2")
        case ..<0.9: return Color("HeatmapL3")
        default: return Color("HeatmapL4")
        }
    }

    /// Label color that stays legible on the heatmap cell fills.
    static func heatmapLabelColor(score: Double?) -> Color {
        guard let score, score >= 0.7 else { return ink }
        return Color("ThemeBackground")               // paper on the two darkest cells
    }

    // MARK: - Radii (small, architectural — no pillowy corners)

    static let radiusCard: CGFloat = 6
    static let radiusControl: CGFloat = 4

    // MARK: - Type (bundled fonts; Font.custom degrades to system on failure)

    /// Serif display — headers, the score number. Spectral, weight 400 (per the
    /// design system, serif weight lives in the forms, not the stroke). Static
    /// face: no optical-size or softness axis to set.
    static func display(_ size: CGFloat) -> Font {
        .custom("Spectral-Regular", size: size)
    }

    /// Sans body/UI — Archivo.
    static func body(_ size: CGFloat) -> Font {
        .custom("Archivo-Regular", size: size)
    }

    static func bodyMedium(_ size: CGFloat) -> Font {
        .custom("Archivo-Medium", size: size)
    }

    /// Mono — tabular numerals anywhere a number is read against another.
    static func mono(_ size: CGFloat) -> Font {
        .custom("IBMPlexMono-Regular", size: size)
    }

    static func monoMedium(_ size: CGFloat) -> Font {
        .custom("IBMPlexMono-Medium", size: size)
    }
}
