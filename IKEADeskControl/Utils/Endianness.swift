import Foundation

enum Endianness {
    /// The endianness of the machine running this program.
    static let host: Endianness = hostEndianness()
    
    private static func hostEndianness() -> Endianness {
        let number: UInt32 = 0x12345678
        return number == number.bigEndian ? .big : .little
    }
    
    /// big endian, the most significant byte (MSB) is at the lowest address
    case big
    
    /// little endian, the least significant byte (LSB) is at the lowest address
    case little
}
