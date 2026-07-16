import Foundation

/// Display formatting for task values: whole numbers without decimals,
/// otherwise one decimal place ("4", "9.5"). Shared with the widget target.
func decimalString(_ n: Double) -> String {
    if n == n.rounded() { return String(Int(n)) }
    return String(format: "%.1f", n)
}
