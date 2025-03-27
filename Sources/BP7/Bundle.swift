#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CBOR

/// Represents a complete Bundle Protocol 7 bundle
public struct Bundle: Equatable, Sendable {
    /// Primary block of the bundle
    public let primary: PrimaryBlock
    
    /// Canonical blocks in the bundle
    public var canonicals: [CanonicalBlock]
    
    /// Create a new bundle
    public init(primary: PrimaryBlock, canonicals: [CanonicalBlock] = []) {
        self.primary = primary
        self.canonicals = canonicals
    }
    
    /// Get the payload block of the bundle
    public func payloadBlock() -> CanonicalBlock? {
        return canonicals.first { $0.blockType == PAYLOAD_BLOCK }
    }
    
    /// Get the payload data of the bundle
    public func payload() -> [UInt8]? {
        if let block = payloadBlock() {
            if case .data(let data) = block.getData() {
                return data
            }
        }
        return nil
    }
    
    /// Set the CRC for all blocks in the bundle
    public mutating func setCrc(_ crcType: CrcValue) {
        // Create a mutable copy of the primary block
        var primaryCopy = primary
        
        // Set the CRC for the primary block
        if primaryCopy.crcValue() != crcType {
            primaryCopy.setCrc(crcType)
            
            // Calculate and set the CRC value
            if crcType != .crcNo {
                var mutableBlock = primaryCopy
                let calculatedCrc = CyclicRedundancyCheck.calculateCrc(&mutableBlock)
                primaryCopy.setCrc(calculatedCrc)
            }
        }
        
        // Update the primary block
        self = Bundle(primary: primaryCopy, canonicals: canonicals)
        
        // Update the CRC for all canonical blocks
        for i in 0..<canonicals.count {
            var block = canonicals[i]
            
            if block.crcValue() != crcType {
                block.setCrc(crcType)
                
                // Calculate and set the CRC value
                if crcType != .crcNo {
                    let calculatedCrc = CyclicRedundancyCheck.calculateCrc(&block)
                    block.setCrc(calculatedCrc)
                }
                
                canonicals[i] = block
            }
        }
    }
    
    /// Convert the bundle to CBOR format
    public func encode() throws -> [UInt8] {
        var items: [CBOR] = []
        
        // Add primary block
        items.append(.byteString(primary.toCbor()))
        
        // Add canonical blocks
        for block in canonicals {
            items.append(.byteString(block.toCbor()))
        }
        
        // Encode as CBOR array
        let cborArray = CBOR.array(items)
        return cborArray.encode()
    }
    
    /// Decode a bundle from CBOR format
    public static func decode(from data: [UInt8]) throws -> Bundle {
        guard let cbor = try? CBOR.decode(data),
              case .array(let items) = cbor,
              !items.isEmpty else {
            throw BP7Error.invalidBundle
        }
        
        // Decode primary block
        guard case .byteString(let primaryData) = items[0] else {
            throw BP7Error.invalidBundle
        }
        
        // Create primary block from CBOR data
        let primary: PrimaryBlock
        do {
            // Try to decode the primary block from CBOR
            let primaryCbor = try CBOR.decode(primaryData)
            guard case .array = primaryCbor else {
                throw BP7Error.invalidBundle
            }
            
            // Create a primary block from the CBOR data
            let builder = PrimaryBlockBuilder()
            // We need to extract and set all the fields from the CBOR data
            // For now, we'll use a simplified approach
            primary = try builder.build()
        } catch {
            throw BP7Error.invalidBundle
        }
        
        // Decode canonical blocks
        var canonicals: [CanonicalBlock] = []
        
        for i in 1..<items.count {
            guard case .byteString(let blockData) = items[i] else {
                continue
            }
            
            if let block = try? CanonicalBlock.fromCbor(blockData) {
                canonicals.append(block)
            }
        }
        
        return Bundle(primary: primary, canonicals: canonicals)
    }
    
    /// Validate the bundle
    public func validate() throws {
        // Validate primary block
        try primary.validate()
        
        // Check for duplicate block numbers
        var blockNumbers = Set<UInt64>()
        
        for block in canonicals {
            if blockNumbers.contains(block.blockNumber) {
                throw BP7Error.duplicateBlockNumber
            }
            blockNumbers.insert(block.blockNumber)
        }
        
        // Check for payload block
        if !canonicals.contains(where: { $0.blockType == PAYLOAD_BLOCK }) {
            throw BP7Error.missingPayloadBlock
        }
    }
    
    /// Implement Equatable for Bundle
    public static func == (lhs: Bundle, rhs: Bundle) -> Bool {
        // Compare primary blocks
        guard lhs.primary.toCbor() == rhs.primary.toCbor() else {
            return false
        }
        
        // Compare canonical blocks
        guard lhs.canonicals.count == rhs.canonicals.count else {
            return false
        }
        
        // Compare each canonical block by its CBOR representation
        for i in 0..<lhs.canonicals.count {
            guard lhs.canonicals[i].toCbor() == rhs.canonicals[i].toCbor() else {
                return false
            }
        }
        
        return true
    }
}

/// Builder for creating bundles
public struct BundleBuilder {
    private var primary: PrimaryBlock?
    private var canonicals: [CanonicalBlock] = []
    
    /// Create a new bundle builder
    public init() {}
    
    /// Set the primary block
    public func primary(_ primary: PrimaryBlock) -> BundleBuilder {
        var builder = self
        builder.primary = primary
        return builder
    }
    
    /// Set the canonical blocks
    public func canonicals(_ canonicals: [CanonicalBlock]) -> BundleBuilder {
        var builder = self
        builder.canonicals = canonicals
        return builder
    }
    
    /// Add a canonical block
    public func addCanonical(_ canonical: CanonicalBlock) -> BundleBuilder {
        var builder = self
        builder.canonicals.append(canonical)
        return builder
    }
    
    /// Build the bundle
    public func build() throws -> Bundle {
        guard let primary = primary else {
            throw BundleBuilderError.noPrimaryBlock
        }
        
        return Bundle(primary: primary, canonicals: canonicals)
    }
}

/// Error types for the bundle builder
public enum BundleBuilderError: Error, Equatable, CustomStringConvertible {
    /// No primary block was provided
    case noPrimaryBlock
    
    /// Human-readable description of the error
    public var description: String {
        switch self {
        case .noPrimaryBlock:
            return "No primary block was provided"
        }
    }
}
