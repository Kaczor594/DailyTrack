import SwiftUI

/// Design-system tokens for DailyTrack (Isaac Kaczor design system:
/// paper + stone + moss natural palette, Fraunces/Geist/Geist Mono).
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
    static let warning = Color("ThemeWarning")
    static let info = Color("ThemeInfo")

    // MARK: - Chart series (use in order; moss is the focal series)

    static let chartMoss = Color("ChartMoss")
    static let chartTerra = Color("ChartTerra")
    static let chartSky = Color("ChartSky")
    static let chartDust = Color("ChartDust")
    static let chartStone = Color("ChartStone")
    static let chartSage = Color("ChartSage")

    static let chartSeries: [Color] = [chartMoss, chartTerra, chartSky, chartDust, chartStone, chartSage]

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

    static let radiusCard: CGFloat = 8
    static let radiusControl: CGFloat = 4
    static let radiusBar: CGFloat = 2

    // MARK: - Type (bundled fonts; Font.custom degrades to system on failure)

    /// Serif display — headers, the score number. Fraunces 72pt optical, weight 400
    /// (per the design system, serif weight lives in the forms, not the stroke).
    static func display(_ size: CGFloat) -> Font {
        .custom("Fraunces72pt-Regular", size: size)
    }

    static func displaySemiBold(_ size: CGFloat) -> Font {
        .custom("Fraunces72pt-SemiBold", size: size)
    }

    /// Sans body/UI — Geist.
    static func body(_ size: CGFloat) -> Font {
        .custom("Geist-Regular", size: size)
    }

    static func bodyMedium(_ size: CGFloat) -> Font {
        .custom("Geist-Medium", size: size)
    }

    static func bodySemiBold(_ size: CGFloat) -> Font {
        .custom("Geist-SemiBold", size: size)
    }

    /// Mono — tabular numerals anywhere a number is read against another.
    static func mono(_ size: CGFloat) -> Font {
        .custom("GeistMono-Regular", size: size)
    }

    static func monoMedium(_ size: CGFloat) -> Font {
        .custom("GeistMono-Medium", size: size)
    }
}
