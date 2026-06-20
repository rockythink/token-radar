import Foundation

public enum MoneyFormatter {
    public static func usd(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = value < 10 ? 2 : 0
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "$0"
    }

    public static func compactUSD(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        if number >= 1000 {
            return String(format: "$%.1fk", number / 1000)
        }
        if number >= 100 {
            return String(format: "$%.0f", number)
        }
        return String(format: "$%.2f", number)
    }

    public static func percent(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0%"
    }
}

