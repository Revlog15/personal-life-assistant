import Foundation

/// Whole Indonesian Rupiah value stored strictly as Int64 (no floating-point errors).
public struct Money: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public static let maxAllowedRupiah: Int64 = 999_999_999_999
    public static let zero = Money(0)

    public let rupiah: Int64

    public init(_ rupiah: Int64) {
        self.rupiah = rupiah
    }

    public var isPositive: Bool { rupiah > 0 }
    public var isNegative: Bool { rupiah < 0 }
    public var isZero: Bool { rupiah == 0 }
    public var isWithinTransactionBounds: Bool { rupiah > 0 && rupiah <= Self.maxAllowedRupiah }

    public var description: String { "\(rupiah)" }

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.rupiah < rhs.rupiah }
    public static func + (lhs: Money, rhs: Money) -> Money { Money(lhs.rupiah + rhs.rupiah) }
    public static func - (lhs: Money, rhs: Money) -> Money { Money(lhs.rupiah - rhs.rupiah) }
    public static prefix func - (value: Money) -> Money { Money(-value.rupiah) }
}
