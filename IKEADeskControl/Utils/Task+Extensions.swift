import NIO

extension Task where Success == Never, Failure == Never {
    public static func sleep(for timeAmount: TimeAmount) async throws {
        guard timeAmount.nanoseconds >= 0 else {
            fatalError("Cannot sleep a negative amount")
        }
        
        try await sleep(nanoseconds: UInt64(timeAmount.nanoseconds))
    }
}
