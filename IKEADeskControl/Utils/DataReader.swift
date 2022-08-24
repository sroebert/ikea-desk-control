import Foundation

struct DataReader {
    
    // MARK: - Public Vars
    
    private(set) var data: Data
    var readerIndex: Int = 0
    
    // MARK: - Move
    
    @discardableResult
    mutating func move(to offset: Int) -> Bool {
        guard data.count >= offset else {
            return false
        }
        
        readerIndex = offset
        return true
    }
    
    @discardableResult
    mutating func move(forwardBy offset: Int) -> Bool {
        return move(to: readerIndex + offset)
    }
    
    // MARK: - Bytes
    
    mutating func getBytes(
        at index: Int,
        length: Int
    ) -> [UInt8]? {
        guard let range = rangeWithinReadableBytes(index: index, length: length) else {
            return nil
        }
        return Array(data[range])
    }
    
    mutating func readBytes(length: Int) -> [UInt8]? {
        return getBytes(at: readerIndex, length: length).map {
            move(forwardBy: length)
            return $0
        }
    }
    
    // MARK: - Integers
    
    mutating func getInteger<T: FixedWidthInteger>(
        at index: Int,
        endianness: Endianness = .little,
        as type: T.Type = T.self
    ) -> T? {
        guard let range = rangeWithinReadableBytes(index: index, length: MemoryLayout<T>.size) else {
            return nil
        }

        if T.self == UInt8.self {
            return data.withUnsafeBytes { ptr in
                ptr[range.startIndex] as! T // swiftlint:disable:this force_cast
            }
        }

        return data.withUnsafeBytes { ptr in
            var value: T = 0
            withUnsafeMutableBytes(of: &value) { valuePtr in
                valuePtr.copyMemory(from: UnsafeRawBufferPointer(rebasing: ptr[range]))
            }
            return toEndianness(value: value, endianness: endianness)
        }
    }
    
    mutating func readInteger<T: FixedWidthInteger>(
        endianness: Endianness = .little,
        as type: T.Type = T.self
    ) -> T? {
        guard let integer = getInteger(at: readerIndex, endianness: endianness, as: type) else {
            return nil
        }
        
        move(forwardBy: MemoryLayout<T>.size)
        return integer
    }
    
    // MARK: - Utils
    
    private func rangeWithinReadableBytes(index: Int, length: Int) -> Range<Int>? {
        guard index >= 0 && length >= 0 && index <= data.count - length else {
            return nil
        }
        return index ..< (index + length)
    }
    
    private func toEndianness<T: FixedWidthInteger> (value: T, endianness: Endianness) -> T {
        switch endianness {
        case .little:
            return value.littleEndian
        case .big:
            return value.bigEndian
        }
    }
}
