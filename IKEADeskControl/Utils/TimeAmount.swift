import Foundation

public struct TimeAmount: Hashable {
    
    // MARK: - Public Vars
    
    public let nanoseconds: Int64
    
    // MARK: - Lifecycle
    
    private init(_ nanoseconds: Int64) {
        self.nanoseconds = nanoseconds
    }
    
    // MARK: - Utils
    
    public static func nanoseconds(_ amount: Int64) -> TimeAmount {
        return TimeAmount(amount)
    }
    
    public static func microseconds(_ amount: Int64) -> TimeAmount {
        return TimeAmount(amount * 1000)
    }
    
    public static func milliseconds(_ amount: Int64) -> TimeAmount {
        return TimeAmount(amount * (1000 * 1000))
    }
    
    public static func seconds(_ amount: Int64) -> TimeAmount {
        return TimeAmount(amount * (1000 * 1000 * 1000))
    }
    
    public static func minutes(_ amount: Int64) -> TimeAmount {
        return TimeAmount(amount * (1000 * 1000 * 1000 * 60))
    }
    
    public static func hours(_ amount: Int64) -> TimeAmount {
        return TimeAmount(amount * (1000 * 1000 * 1000 * 60 * 60))
    }
}

extension TimeAmount: Comparable {
    public static func < (lhs: TimeAmount, rhs: TimeAmount) -> Bool {
        return lhs.nanoseconds < rhs.nanoseconds
    }
}

extension TimeAmount: AdditiveArithmetic {
    public static var zero: TimeAmount {
        return TimeAmount.nanoseconds(0)
    }
    
    public static func + (lhs: TimeAmount, rhs: TimeAmount) -> TimeAmount {
        return TimeAmount(lhs.nanoseconds + rhs.nanoseconds)
    }
    
    public static func += (lhs: inout TimeAmount, rhs: TimeAmount) {
        // swiftlint:disable:next shorthand_operator
        lhs = lhs + rhs
    }
    
    public static func - (lhs: TimeAmount, rhs: TimeAmount) -> TimeAmount {
        return TimeAmount(lhs.nanoseconds - rhs.nanoseconds)
    }
    
    public static func -= (lhs: inout TimeAmount, rhs: TimeAmount) {
        // swiftlint:disable:next shorthand_operator
        lhs = lhs - rhs
    }
    
    public static func * <T: BinaryInteger>(lhs: T, rhs: TimeAmount) -> TimeAmount {
        return TimeAmount(Int64(lhs) * rhs.nanoseconds)
    }
    
    public static func * <T: BinaryInteger>(lhs: TimeAmount, rhs: T) -> TimeAmount {
        return TimeAmount(lhs.nanoseconds * Int64(rhs))
    }
}

extension Task where Success == Never, Failure == Never {
    public static func sleep(for timeAmount: TimeAmount) async throws {
        guard timeAmount.nanoseconds >= 0 else {
            fatalError("Cannot sleep a negative amount")
        }
        
        try await sleep(nanoseconds: UInt64(timeAmount.nanoseconds))
    }
}
