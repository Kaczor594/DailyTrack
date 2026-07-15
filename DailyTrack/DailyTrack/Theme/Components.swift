import SwiftUI

// Workbench components for the ledger/instrument design language.
// Shared between the main app and the widget extension.

// MARK: - Eyebrow

/// Mono uppercase section label — the design system's `.eyebrow`.
struct Eyebrow: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = Theme.inkTertiary

    init(_ text: String, size: CGFloat = 10, color: Color = Theme.inkTertiary) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Theme.monoMedium(size))
            .kerning(size * 0.14)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

// MARK: - Hairline

/// 1px rule in the divider color. Internal dividers only, never decoration.
struct Hairline: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(
                width: vertical ? 1 : nil,
                height: vertical ? nil : 1
            )
    }
}

// MARK: - Meter

/// Linear score meter with quartile tick marks — replaces the score ring.
struct MeterBar: View {
    let ratio: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Theme.panel)

                // Quartile ticks on the track
                ForEach(1..<4) { i in
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(width: 1)
                        .offset(x: geo.size.width * CGFloat(i) / 4)
                }

                Rectangle()
                    .fill(Theme.scoreColor(ratio))
                    .frame(width: geo.size.width * min(ratio, 1.0))
                    .animation(.easeInOut(duration: 0.42), value: ratio)
            }
            .clipShape(RoundedRectangle(cornerRadius: 1))
        }
        .frame(height: height)
    }
}

// MARK: - Square gauge

/// Small square that fills bottom-up with the score color — a fuel gauge
/// for numeric task rows.
struct SquareGauge: View {
    let ratio: Double
    var size: CGFloat = 16

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.panel)

            Rectangle()
                .fill(Theme.scoreColor(ratio))
                .frame(height: size * min(ratio, 1.0))
                .animation(.easeInOut(duration: 0.24), value: ratio)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Theme.divider, lineWidth: 1)
        )
        .frame(width: size, height: size)
    }
}

// MARK: - Square check

/// Square checkbox glyph — worksheet style, not a switch. Wrap in a Button.
struct SquareCheckGlyph: View {
    let isOn: Bool
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(isOn ? Theme.brand : Theme.panel)

            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(Theme.background)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(isOn ? Theme.brand : Theme.divider, lineWidth: 1)
        )
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.14), value: isOn)
    }
}

// MARK: - Workbench card

/// Paper card: surface fill + grain + hairline + small radius.
struct WorkbenchCard: ViewModifier {
    var padded = true

    func body(content: Content) -> some View {
        content
            .padding(padded ? 14 : 0)
            .background {
                ZStack {
                    Theme.surface
                    Image("GrainTexture")
                        .resizable(resizingMode: .tile)
                        .opacity(0.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusCard)
                    .stroke(Theme.divider, lineWidth: 1)
            )
    }
}

extension View {
    func workbenchCard(padded: Bool = true) -> some View {
        modifier(WorkbenchCard(padded: padded))
    }
}

// MARK: - Page background

/// Full-page paper background with grain.
struct PaperBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            Image("GrainTexture")
                .resizable(resizingMode: .tile)
                .opacity(0.35)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Source line

/// Provenance footer — smallest text on the page, hairline above.
struct SourceLine: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Hairline()
            Text(text)
                .font(Theme.mono(10))
                .kerning(0.3)
                .foregroundStyle(Theme.inkTertiary)
        }
    }
}
