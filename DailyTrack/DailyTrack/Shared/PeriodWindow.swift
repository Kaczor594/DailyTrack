import Foundation

/// Computes the start/end date range and day count for a cumulative task's
/// period window (weekly/monthly/yearly) containing `date`. Returns nil for
/// non-cumulative tasks or tasks whose `cumulativePeriod` is nil/"none".
///
/// Week/month/year boundaries follow `Calendar.current` (locale-aware) unless
/// `task.periodAnchor` overrides them. For weekly tasks with an anchor
/// (1=Sunday..7=Saturday per `Calendar.weekday`), the window is a 7-day span
/// starting on the most recent anchor weekday ≤ `date`.
func periodWindow(for task: TaskDefinition, on date: Date) -> (startDateStr: String, endDateStr: String, periodDays: Int)? {
    guard let period = task.cumulativePeriod else { return nil }
    let calendar = Calendar.current

    if period == "week", let anchor = task.periodAnchor, (1...7).contains(anchor) {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let offset = (weekday - anchor + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: startOfDay),
              let end = calendar.date(byAdding: .day, value: 6, to: start) else { return nil }
        return (
            startDateStr: periodWindowDateFormatter.string(from: start),
            endDateStr: periodWindowDateFormatter.string(from: end),
            periodDays: 7
        )
    }

    let component: Calendar.Component
    switch period {
    case "week": component = .weekOfYear
    case "month": component = .month
    case "year": component = .year
    default: return nil
    }
    guard let interval = calendar.dateInterval(of: component, for: date) else { return nil }
    let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end)!
    let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1
    return (
        startDateStr: periodWindowDateFormatter.string(from: interval.start),
        endDateStr: periodWindowDateFormatter.string(from: endDate),
        periodDays: days
    )
}

private let periodWindowDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()
