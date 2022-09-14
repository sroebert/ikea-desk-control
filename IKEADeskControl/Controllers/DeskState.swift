@preconcurrency import Foundation

struct DeskState: Equatable {
    var peripheralId: UUID
    
    var position: Double
    var speed: Double
    
    var rawPosition: UInt16
}
