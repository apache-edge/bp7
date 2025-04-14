import CBOR

/******************************
 *
 * Primary Block
 *
 ******************************/

/// Errors that can occur when building a primary block
public enum PrimaryBlockBuilderError: Error, Equatable, CustomStringConvertible {
    case noDestination
    
    public var description: String {
        switch self {
        case .noDestination:
            return "No destination endpoint was provided"
        }
    }
}

/// Builder for creating a primary block with a fluent interface
public struct PrimaryBlockBuilder {
    private var version: UInt8 = PrimaryBlock.DTN_VERSION
    private var bundleControlFlags: BundleControlFlags = []
    private var crc: CrcValue = .crcNo
    private var destination: EndpointID
    private var source: EndpointID?
    private var reportTo: EndpointID?
    private var creationTimestamp: CreationTimestamp?
    private var lifetime: Double = 3600 // Default 1 hour lifetime
    private var fragmentationOffset: UInt64 = 0
    private var totalDataLength: UInt64 = 0
    
    /// Create a new builder with default values
    public init(destination: EndpointID) {
        self.destination = destination
    }
    
    /// Set the bundle protocol version (default is 7)
    public func version(_ version: UInt8) -> PrimaryBlockBuilder {
        var builder = self
        builder.version = version
        return builder
    }
    
    /// Set the bundle control flags
    public func bundleControlFlags(_ flags: BundleControlFlags) -> PrimaryBlockBuilder {
        var builder = self
        builder.bundleControlFlags = flags
        return builder
    }
    
    /// Set the CRC type
    public func crc(_ crc: CrcValue) -> PrimaryBlockBuilder {
        var builder = self
        builder.crc = crc
        return builder
    }
    
    /// Set the destination endpoint
    public func destination(_ destination: EndpointID) -> PrimaryBlockBuilder {
        var builder = self
        builder.destination = destination
        return builder
    }
    
    /// Set the source endpoint
    public func source(_ source: EndpointID) -> PrimaryBlockBuilder {
        var builder = self
        builder.source = source
        return builder
    }
    
    /// Set the report-to endpoint
    public func reportTo(_ reportTo: EndpointID) -> PrimaryBlockBuilder {
        var builder = self
        builder.reportTo = reportTo
        return builder
    }
    
    /// Set the creation timestamp
    public func creationTimestamp(_ timestamp: CreationTimestamp) -> PrimaryBlockBuilder {
        var builder = self
        builder.creationTimestamp = timestamp
        return builder
    }
    
    /// Set the lifetime in seconds
    public func lifetime(_ lifetime: Double) -> PrimaryBlockBuilder {
        var builder = self
        builder.lifetime = lifetime
        return builder
    }
    
    /// Set the fragmentation offset (only used if bundle is a fragment)
    public func fragmentationOffset(_ offset: UInt64) -> PrimaryBlockBuilder {
        var builder = self
        builder.fragmentationOffset = offset
        return builder
    }
    
    /// Set the total application data unit length (only used if bundle is a fragment)
    public func totalDataLength(_ length: UInt64) -> PrimaryBlockBuilder {
        var builder = self
        builder.totalDataLength = length
        return builder
    }
    
    /// Build the primary block
    public func build() -> PrimaryBlock {
        // Use default values for optional fields
        let source = source ?? EndpointID.none()
        let reportTo = reportTo ?? EndpointID.none()
        let creationTimestamp = creationTimestamp ?? CreationTimestamp()
        
        // Create the primary block
        return PrimaryBlock(
            version: version,
            bundleControlFlags: bundleControlFlags,
            crc: crc,
            destination: destination,
            source: source,
            reportTo: reportTo,
            creationTimestamp: creationTimestamp,
            lifetime: lifetime,
            fragmentationOffset: fragmentationOffset,
            totalDataLength: totalDataLength
        )
    }
}

/// Represents the primary block of a bundle
public struct PrimaryBlock: CrcBlock, Equatable, Hashable, Sendable {
    /// The Bundle Protocol version (7)
    public static let DTN_VERSION: UInt8 = 7
    
    /// The Bundle Protocol version
    public let version: UInt8
    
    /// Bundle processing control flags
    public let bundleControlFlags: BundleControlFlags
    
    /// CRC type and value
    private var crc: CrcValue
    
    /// Destination endpoint
    public let destination: EndpointID
    
    /// Source endpoint
    public let source: EndpointID
    
    /// Report-to endpoint
    public let reportTo: EndpointID
    
    /// Creation timestamp
    public let creationTimestamp: CreationTimestamp
    
    /// Lifetime in seconds
    public let lifetime: Double
    
    /// Fragmentation offset (only used if bundle is a fragment)
    public let fragmentationOffset: UInt64
    
    /// Total application data unit length (only used if bundle is a fragment)
    public let totalDataLength: UInt64
    
    /// Create a new primary block
    public init(
        version: UInt8 = DTN_VERSION,
        bundleControlFlags: BundleControlFlags = [],
        crc: CrcValue = .crcNo,
        destination: EndpointID,
        source: EndpointID,
        reportTo: EndpointID,
        creationTimestamp: CreationTimestamp,
        lifetime: Double,
        fragmentationOffset: UInt64 = 0,
        totalDataLength: UInt64 = 0
    ) {
        self.version = version
        self.bundleControlFlags = bundleControlFlags
        self.crc = crc
        self.destination = destination
        self.source = source
        self.reportTo = reportTo
        self.creationTimestamp = creationTimestamp
        self.lifetime = lifetime
        self.fragmentationOffset = fragmentationOffset
        self.totalDataLength = totalDataLength
    }
    
    /// Convenience initializer to create a primary block from string endpoints
    public init(
        destination: String,
        source: String,
        creationTimestamp: CreationTimestamp = CreationTimestamp(),
        lifetime: Double = 3600 // Default 1 hour lifetime
    ) {
        // Remove "dtn:" prefix if present
        let dstAddress = destination.replacingOccurrences(of: "dtn:", with: "")
        let srcAddress = source.replacingOccurrences(of: "dtn:", with: "")
        
        let dstEid = EndpointID.dtn(EndpointScheme.DTN, DTNAddress(dstAddress))
        let srcEid = EndpointID.dtn(EndpointScheme.DTN, DTNAddress(srcAddress))
        
        self.init(
            version: PrimaryBlock.DTN_VERSION,
            bundleControlFlags: [],
            crc: .crcNo,
            destination: dstEid,
            source: srcEid,
            reportTo: EndpointID.none(),
            creationTimestamp: creationTimestamp,
            lifetime: lifetime
        )
    }
    
    /// Check if the block has fragmentation information
    public var hasFragmentation: Bool {
        return bundleControlFlags.contains(.bundleIsFragment)
    }
    
    /// Check if the bundle has expired based on its creation timestamp and lifetime
    public func hasExpired() -> Bool {
        if lifetime == 0 {
            return false
        }
        
        let now = DisruptionTolerantNetworkingTime.now()
        return creationTimestamp.getDtnTime() + UInt64(lifetime * 1000) <= now
    }
    
    /// Validate the primary block
    public func validate() throws(BP7Error) {
        var errors: [BP7Error] = []
        
        if version != PrimaryBlock.DTN_VERSION {
            errors.append(.invalidValue)
        }
        
        // Validate bundle control flags
        if bundleControlFlags.contains(.bundleIsFragment) {
            // If bundle is a fragment, check that fragmentation offset and total data length are valid
            if fragmentationOffset == 0 {
                errors.append(.invalidFragmentOffset)
            }
            
            if totalDataLength == 0 {
                errors.append(.invalidTotalADULength)
            }
        }
        
        // If there are any errors, throw them
        if !errors.isEmpty {
            if errors.count == 1 {
                throw errors[0]
            } else {
                // Since there's no multipleErrors case, just throw the first error
                throw errors[0]
            }
        }
    }
    
    // MARK: - CrcBlock Protocol Implementation
    
    /// Get the CRC value
    public func crcValue() -> CrcValue {
        return crc
    }
    
    /// Set the CRC value
    public mutating func setCrc(_ crc: CrcValue) {
        self.crc = crc
    }
    
    /// Check if the block has a CRC
    public func hasCrc() -> Bool {
        return crc != .crcNo
    }
    
    /// Convert the block to CBOR format
    public func toCbor() -> [UInt8] {
        var cborItems: [CBOR] = []
        
        // Add version
        cborItems.append(.unsignedInt(UInt64(version)))
        
        // Add bundle processing control flags
        cborItems.append(.unsignedInt(UInt64(bundleControlFlags.rawValue)))
        
        // Add CRC type
        cborItems.append(.unsignedInt(UInt64(crc.toCode())))
        
        // Add destination
        cborItems.append(destination.encode())
        
        // Add source
        cborItems.append(source.encode())
        
        // Add report-to
        cborItems.append(reportTo.encode())
        
        // Add creation timestamp as an array
        cborItems.append(.array([
            .unsignedInt(creationTimestamp.getDtnTime()),
            .unsignedInt(creationTimestamp.getSequenceNumber())
        ]))
        
        // Add lifetime
        cborItems.append(.unsignedInt(UInt64(lifetime)))
        
        // Add fragmentation offset and total data length if bundle is a fragment
        if bundleControlFlags.contains(.bundleIsFragment) {
            cborItems.append(.unsignedInt(fragmentationOffset))
            cborItems.append(.unsignedInt(totalDataLength))
        }
        
        // Create CBOR array
        let cborArray = CBOR.array(cborItems)
        
        // Encode as CBOR
        return cborArray.encode()
    }
    
    /// Initialize a PrimaryBlock from CBOR data
    public init(from cbor: [UInt8]) throws {
        // Decode CBOR data
        guard let cborData = try? CBOR.decode(cbor),
              case .array(let items) = cborData else {
            throw BP7Error.invalidBlock
        }
        
        // Check minimum number of items
        if items.count < 8 {
            throw BP7Error.invalidBlock
        }
        
        // Extract version
        guard case .unsignedInt(let versionValue) = items[0] else {
            throw BP7Error.invalidBlock
        }
        
        // Extract bundle control flags
        guard case .unsignedInt(let flagsValue) = items[1] else {
            throw BP7Error.invalidBlock
        }
        
        // Extract CRC type
        guard case .unsignedInt(let crcTypeValue) = items[2] else {
            throw BP7Error.invalidBlock
        }
        
        // Extract destination
        let destination = try EndpointID(from: items[3])
        
        // Extract source
        let source = try EndpointID(from: items[4])
        
        // Extract report-to
        let reportTo = try EndpointID(from: items[5])
        
        // Extract creation timestamp
        guard case .array(let timestampArray) = items[6],
              timestampArray.count == 2,
              case .unsignedInt(let dtnTime) = timestampArray[0],
              case .unsignedInt(let sequenceNumber) = timestampArray[1] else {
            throw BP7Error.invalidBlock
        }
        let creationTimestamp = CreationTimestamp(time: dtnTime, sequenceNumber: sequenceNumber)
        
        // Extract lifetime
        guard case .unsignedInt(let lifetimeValue) = items[7] else {
            throw BP7Error.invalidBlock
        }
        
        // Extract fragmentation information if present
        var fragmentationOffset: UInt64 = 0
        var totalDataLength: UInt64 = 0
        
        let bundleControlFlags = BundleControlFlags(rawValue: flagsValue)
        if bundleControlFlags.contains(.bundleIsFragment) {
            if items.count < 10 {
                throw BP7Error.invalidBlock
            }
            
            guard case .unsignedInt(let fragOffset) = items[8],
                  case .unsignedInt(let totalLength) = items[9] else {
                throw BP7Error.invalidBlock
            }
            
            fragmentationOffset = fragOffset
            totalDataLength = totalLength
        }
        
        // Create CRC value based on code
        let crcCode = UInt8(crcTypeValue)
        let crcValue: CrcValue
        switch crcCode {
        case BP7CRC.NO:
            crcValue = .crcNo
        case BP7CRC.CRC16:
            crcValue = .crc16Empty
        case BP7CRC.CRC32:
            crcValue = .crc32Empty
        default:
            crcValue = .unknown(crcCode)
        }
        
        // Initialize the primary block
        self.init(
            version: UInt8(versionValue),
            bundleControlFlags: bundleControlFlags,
            crc: crcValue,
            destination: destination,
            source: source,
            reportTo: reportTo,
            creationTimestamp: creationTimestamp,
            lifetime: Double(lifetimeValue),
            fragmentationOffset: fragmentationOffset,
            totalDataLength: totalDataLength
        )
    }
}
