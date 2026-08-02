import Foundation

/// Working days per week. Sunday is a rest day (Bavarian Sonntagsruhe), so a
/// weekly benchmark is spread over six days rather than seven and Sunday is
/// excluded from streaks and the average score.
///
/// The period *window* still spans all seven calendar days, so hours logged on
/// a Sunday still count toward the week's cumulative total — only the derived
/// daily target and the streak/average stats treat the week as six days.
let weeklyScoringDays = 6

/// Whether `date` falls on the weekly rest day (Sunday, `Calendar.weekday == 1`).
func isRestDay(_ date: Date) -> Bool {
    Calendar.current.component(.weekday, from: date) == 1
}

/// Computes the start/end date range and day count for a cumulative task's
/// period window (weekly/monthly/yearly) containing `date`. Returns nil for
/// non-cumulative tasks or tasks whose `cumulativePeriod` is nil/"none".
///
/// Week/month/year boundaries follow `Calendar.current` (locale-aware) unless
/// `task.periodAnchor` overrides them:
/// - week: anchor is a weekday (1=Sunday..7=Saturday per `Calendar.weekday`);
///   the window is a 7-day span starting on the most recent anchor weekday ≤ `date`.
/// - month: anchor is a day-of-month (1...31, UI caps at 28); the window starts on
///   the most recent occurrence of that day ≤ `date` (clamped to short months).
/// - year: anchor encodes month*100+day (e.g. 801 = Aug 1); the window starts on
///   the most recent occurrence of that month+day ≤ `date`.
/// Invalid anchors fall back to the locale-default boundary.
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
            periodDays: weeklyScoringDays
        )
    }

    if period == "month", let anchor = task.periodAnchor, (1...31).contains(anchor) {
        let startOfDay = calendar.startOfDay(for: date)
        let comps = calendar.dateComponents([.year, .month], from: startOfDay)
        guard var start = clampedDate(year: comps.year!, month: comps.month!, day: anchor, calendar: calendar) else { return nil }
        if start > startOfDay {
            // Anchor day hasn't occurred yet this month — window began last month.
            guard let prevRef = calendar.date(byAdding: .month, value: -1, to: start) else { return nil }
            let p = calendar.dateComponents([.year, .month], from: prevRef)
            guard let s = clampedDate(year: p.year!, month: p.month!, day: anchor, calendar: calendar) else { return nil }
            start = s
        }
        guard let nextRef = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
        let n = calendar.dateComponents([.year, .month], from: nextRef)
        guard let nextStart = clampedDate(year: n.year!, month: n.month!, day: anchor, calendar: calendar),
              let end = calendar.date(byAdding: .day, value: -1, to: nextStart) else { return nil }
        let days = calendar.dateComponents([.day], from: start, to: nextStart).day ?? 30
        return (
            startDateStr: periodWindowDateFormatter.string(from: start),
            endDateStr: periodWindowDateFormatter.string(from: end),
            periodDays: days
        )
    }

    if period == "year", let anchor = task.periodAnchor, (1...12).contains(anchor / 100), (1...31).contains(anchor % 100) {
        let month = anchor / 100
        let day = anchor % 100
        let startOfDay = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: startOfDay)
        guard var start = clampedDate(year: year, month: month, day: day, calendar: calendar) else { return nil }
        if start > startOfDay {
            // Anchor date hasn't occurred yet this year — window began last year.
            guard let s = clampedDate(year: year - 1, month: month, day: day, calendar: calendar) else { return nil }
            start = s
        }
        let startYear = calendar.component(.year, from: start)
        guard let nextStart = clampedDate(year: startYear + 1, month: month, day: day, calendar: calendar),
              let end = calendar.date(byAdding: .day, value: -1, to: nextStart) else { return nil }
        let days = calendar.dateComponents([.day], from: start, to: nextStart).day ?? 365
        return (
            startDateStr: periodWindowDateFormatter.string(from: start),
            endDateStr: periodWindowDateFormatter.string(from: end),
            periodDays: days
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
    // Weeks are scored over six working days; months/years use their real length.
    let days = period == "week"
        ? weeklyScoringDays
        : (calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
    return (
        startDateStr: periodWindowDateFormatter.string(from: interval.start),
        endDateStr: periodWindowDateFormatter.string(from: endDate),
        periodDays: days
    )
}

/// Date at the given year/month with `day` clamped to the month's actual length
/// (so an anchor of 31 resolves to Feb 28/29, Apr 30, etc.).
private func clampedDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
    var comps = DateComponents(year: year, month: month, day: 1)
    guard let firstOfMonth = calendar.date(from: comps),
          let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return nil }
    comps.day = min(day, range.count)
    return calendar.date(from: comps)
}

private let periodWindowDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()
