#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Foundation)
import Foundation
#endif
import CyclicRedundancyCheck

/// Cyclic Redundancy Check (CRC) type raw value
public typealias CrcRawType = UInt8

/// CRC value types
public enum CrcValue: Equatable, Hashable, Sendable {
    /// No CRC
    case crcNo
    
    /// Empty CRC-16 value
    case crc16Empty
    
    /// Empty CRC-32 value
    case crc32Empty
    
    /// CRC-16 with value
    case crc16([UInt8])
    
    /// CRC-32 with value
    case crc32([UInt8])
    
    /// Unknown CRC type
    case unknown(CrcRawType)
    
    /// Check if this CRC value has a CRC
    public func hasCrc() -> Bool {
        self != .crcNo
    }
    
    /// Get the CRC type code
    public func toCode() -> CrcRawType {
        switch self {
        case .crcNo:
            return 0
        case .crc16, .crc16Empty:
            return 1
        case .crc32, .crc32Empty:
            return 2
        case .unknown(let code):
            return code
        }
    }
    
    /// Get the CRC bytes
    public func bytes() -> [UInt8]? {
        switch self {
        case .crcNo, .unknown:
            return nil
        case .crc16(let buf):
            return buf
        case .crc16Empty:
            return [0, 0]
        case .crc32(let buf):
            return buf
        case .crc32Empty:
            return [0, 0, 0, 0]
        }
    }
}

/// Protocol for blocks that support CRC
public protocol CrcBlock {
    /// Get the CRC value
    func crcValue() -> CrcValue
    
    /// Set the CRC value
    mutating func setCrc(_ crc: CrcValue)
    
    /// Convert the block to CBOR data
    func toCbor() -> [UInt8]
}

/// Extension to provide common CRC functionality for CrcBlock
extension CrcBlock {
    /// Check if the block has a CRC
    public func hasCrc() -> Bool {
        return crcValue().hasCrc()
    }
    
    /// Get the raw CRC checksum
    public func crc() -> [UInt8]? {
        return crcValue().bytes()
    }
    
    /// Get the CRC type code
    public func crcType() -> CrcRawType {
        return crcValue().toCode()
    }
    
    /// Reset the CRC field to an empty value
    public mutating func resetCrc() {
        switch crcType() {
        case 0: // No CRC
            setCrc(.crcNo)
        case 1: // CRC-16
            setCrc(.crc16Empty)
        case 2: // CRC-32
            setCrc(.crc32Empty)
        default:
            break
        }
    }
    
    /// Update the CRC value
    public mutating func updateCrc() {
        var mutableSelf = self
        let newCrc = BP7CRC.calculateCrc(&mutableSelf)
        setCrc(newCrc)
    }
    
    /// Check if the CRC value is valid
    public func checkCrc() -> Bool {
        return BP7CRC.checkCrcValue(self)
    }
    
    /// Set the CRC type
    public mutating func setCrcType(_ crcType: CrcRawType) {
        if crcType == 0 {
            setCrc(.crcNo)
        } else if crcType == 1 {
            setCrc(.crc16Empty)
        } else if crcType == 2 {
            setCrc(.crc32Empty)
        } else {
            setCrc(.unknown(crcType))
        }
    }
}

/// Namespace for Cyclic Redundancy Check (CRC) constants and functionality
public enum BP7CRC {
    /// No Cyclic Redundancy Check (CRC)
    public static let NO: CrcRawType = 0
    
    /// Cyclic Redundancy Check (CRC) type
    public static let CRC16: CrcRawType = 1
    
    /// Cyclic Redundancy Check (CRC) type
    public static let CRC32: CrcRawType = 2
    
    /// Calculate Cyclic Redundancy Check (CRC) for a block
    public static func calculateCrc<T: CrcBlock>(_ block: inout T) -> CrcValue {
        switch block.crcType() {
        case NO:
            return .crcNo
        case CRC16:
            let crcBackup = block.crcValue() // Backup original CRC
            block.resetCrc() // Set empty CRC
            let data = block.toCbor() // Convert to CBOR
            
            // Calculate CRC-16 using the external package
            let checksum = crc16(bytes: data)
            let bytes = checksumToBytes(checksum)
            
            block.setCrc(crcBackup) // Restore original CRC
            return .crc16(bytes)
        case CRC32:
            let crcBackup = block.crcValue() // Backup original CRC
            block.resetCrc() // Set empty CRC
            let data = block.toCbor() // Convert to CBOR
            
            // Calculate CRC-32 using the external package
            let checksum = crc32(bytes: data)
            let bytes = checksumToBytes(checksum)
            
            block.setCrc(crcBackup) // Restore original CRC
            return .crc32(bytes)
        default:
            fatalError("Unknown CRC type")
        }
    }
    
    /// Check if the CRC value of a block is valid
    public static func checkCrcValue<T: CrcBlock>(_ block: T) -> Bool {
        if !block.hasCrc() {
            return true
        }
        
        var mutableBlock = block
        let calculatedCrc = calculateCrc(&mutableBlock)
        return calculatedCrc.bytes() == block.crc()
    }
    
    /// Convert a checksum to bytes
    private static func checksumToBytes<T: FixedWidthInteger>(_ checksum: T) -> [UInt8] {
        var value = checksum
        let size = MemoryLayout<T>.size
        var bytes = [UInt8](repeating: 0, count: size)
        
        for i in 0..<size {
            bytes[size - 1 - i] = UInt8(value & 0xFF)
            value >>= 8
        }
        
        return bytes
    }
    
    /// Calculate CRC-16 using the external package
    public static func crc16(bytes: [UInt8]) -> UInt16 {
        // Use the external package directly
        return CyclicRedundancyCheck.crc16(bytes: bytes)
    }
    
    /// Calculate CRC-32 using the external package
    public static func crc32(bytes: [UInt8]) -> UInt32 {
        // Use the external package directly
        return CyclicRedundancyCheck.crc32(bytes: bytes)
    }
}
