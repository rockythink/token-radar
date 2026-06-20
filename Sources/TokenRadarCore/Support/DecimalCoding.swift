import Foundation

public enum DecimalCoding {
    public static func decimal(from value: Any?) -> Decimal {
        switch value {
        case let number as NSNumber:
            return number.decimalValue
        case let string as String:
            return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        case let decimal as Decimal:
            return decimal
        default:
            return 0
        }
    }

    public static func double(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }

    public static func int(from value: Any?) -> Int {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string) ?? 0
        default:
            return 0
        }
    }
}

public extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

