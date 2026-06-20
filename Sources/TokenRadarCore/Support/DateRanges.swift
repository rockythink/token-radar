import Foundation

public enum DateRanges {
    public static func startOfDay(containing date: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func startOfMonth(containing date: Date = Date(), calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    public static func endOfMonth(containing date: Date = Date(), calendar: Calendar = .current) -> Date {
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth(containing: date, calendar: calendar)) else {
            return date
        }
        return nextMonth
    }

    public static func daysElapsedInMonth(containing date: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = startOfMonth(containing: date, calendar: calendar)
        let elapsed = calendar.dateComponents([.day], from: start, to: date).day ?? 0
        return max(1, elapsed + 1)
    }

    public static func daysInMonth(containing date: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = startOfMonth(containing: date, calendar: calendar)
        let range = calendar.range(of: .day, in: .month, for: start)
        return range?.count ?? 30
    }
}

