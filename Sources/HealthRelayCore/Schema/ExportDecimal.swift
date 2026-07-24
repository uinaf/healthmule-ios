import Foundation

enum ExportDecimalError: Error {
    case nonFiniteDerivedValue
}

enum ExportDecimal {
    static func quantized(_ value: Double) -> Double {
        guard value.isFinite else { return value }
        let maximumScalableMagnitude = Double.greatestFiniteMagnitude / 100
        guard abs(value) <= maximumScalableMagnitude else {
            return normalizedZero(value)
        }
        return normalizedZero(
            (value * 100).rounded(.toNearestOrAwayFromZero) / 100
        )
    }

    static func quantized(_ value: Double?) -> Double? {
        value.map(quantized)
    }

    static func quantizedSum(_ values: [Double]) throws -> Double {
        quantized(try sum(values))
    }

    static func sum(_ values: [Double]) throws -> Double {
        var sum = 0.0
        var compensation = 0.0
        for value in values {
            guard value.isFinite else {
                throw ExportDecimalError.nonFiniteDerivedValue
            }
            let adjusted = value - compensation
            let next = sum + adjusted
            guard adjusted.isFinite, next.isFinite else {
                throw ExportDecimalError.nonFiniteDerivedValue
            }
            compensation = (next - sum) - adjusted
            guard compensation.isFinite else {
                throw ExportDecimalError.nonFiniteDerivedValue
            }
            sum = next
        }
        return sum
    }

    private static func normalizedZero(_ value: Double) -> Double {
        value == 0 ? 0 : value
    }
}
