import CBOR

/******************************
 *
 * Canonical Block
 *
 ******************************/

/// Type for canonical block type
public typealias CanonicalBlockType = UInt64

/// Block types as defined in the BP7 specification
public enum BlockType: CanonicalBlockType, Equatable, Hashable, Sendable, CaseIterable {
    /// Payload block as defined in 4.2.3.
    case payload = 1
    
    /// Previous Node block as defined in section 4.3.1.
    case previousNode = 6
    
    /// Bundle Age block as defined in section 4.3.2.
    case bundleAge = 7
    
    /// Hop Count block as defined in section 4.3.3.
    case hopCount = 10
    
    /// The minimum block type for extension blocks
    case extensionBlockTypeMin = 192
}

/// Errors related to canonical blocks
public enum CanonicalError: Error, Equatable, Sendable {
    case canonicalBlockError(String)
    case missingData
    case invalidCrc
    case decodingError(String)
    case encodingError(String)
    case cborError(CBORError)
    
    public static func == (lhs: CanonicalError, rhs: CanonicalError) -> Bool {
        switch (lhs, rhs) {
        case (.canonicalBlockError(let lhsMsg), .canonicalBlockError(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.missingData, .missingData):
            return true
        case (.invalidCrc, .invalidCrc):
            return true
        case (.decodingError(let lhsMsg), .decodingError(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.encodingError(let lhsMsg), .encodingError(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.cborError(let lhsError), .cborError(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

/// Data types for canonical blocks
public enum CanonicalData: Equatable, Sendable {
    case hopCount(UInt8, UInt8)
    case data([UInt8])
    case bundleAge(UInt64)
    case previousNode(EndpointID)
    case unknown([UInt8])
    case decodingError
    
    /// Convert the canonical data to CBOR format
    public func toCbor() throws(CanonicalError) -> [UInt8] {
        switch self {
        case .hopCount(let limit, let count):
            // Encode as a tuple (limit, count)
            let array = CBOR.array([.unsignedInt(UInt64(limit)), .unsignedInt(UInt64(count))])
            return array.encode()
        case .data(let buffer):
            return buffer
        case .bundleAge(let age):
            let cbor: CBOR = .unsignedInt(age)
            return cbor.encode()
        case .previousNode(let eid):
            // Use EndpointID's encode method
            let eidCbor = eid.encode()
            return eidCbor.encode()
        case .unknown(let buffer):
            return buffer
        case .decodingError:
            throw CanonicalError.decodingError("Cannot encode decoding error")
        }
    }
}

/// Builder for canonical blocks
public struct CanonicalBlockBuilder {
    private var blockType: CanonicalBlockType
    private var blockNumber: UInt64
    private var blockControlFlags: BlockControlFlagsType
    private var crc: CrcValue
    private var data: CanonicalData?
    
    public init() {
        self.blockType = BlockType.payload.rawValue
        self.blockNumber = 0
        self.blockControlFlags = 0
        self.crc = .crcNo
        self.data = nil
    }
    
    public func blockType(_ blockType: CanonicalBlockType) -> CanonicalBlockBuilder {
        var builder = self
        builder.blockType = blockType
        return builder
    }
    
    public func blockNumber(_ blockNumber: UInt64) -> CanonicalBlockBuilder {
        var builder = self
        builder.blockNumber = blockNumber
        return builder
    }
    
    public func blockControlFlags(_ flags: BlockControlFlagsType) -> CanonicalBlockBuilder {
        var builder = self
        builder.blockControlFlags = flags
        return builder
    }
    
    public func crc(_ crc: CrcValue) -> CanonicalBlockBuilder {
        var builder = self
        builder.crc = crc
        return builder
    }
    
    public func data(_ data: CanonicalData) -> CanonicalBlockBuilder {
        var builder = self
        builder.data = data
        return builder
    }
    
    public func build() throws(CanonicalError) -> CanonicalBlock {
        guard let data = self.data else {
            throw CanonicalError.missingData
        }
        
        return CanonicalBlock(
            blockType: self.blockType,
            blockNumber: self.blockNumber,
            blockControlFlags: self.blockControlFlags,
            crc: self.crc,
            data: data
        )
    }
}

/// Canonical block implementation
public struct CanonicalBlock: Equatable, Sendable {
    public let blockType: CanonicalBlockType
    public let blockNumber: UInt64
    public let blockControlFlags: BlockControlFlagsType
    public var crc: CrcValue
    private var data: CanonicalData
    
    public init(blockType: CanonicalBlockType, blockNumber: UInt64, blockControlFlags: BlockControlFlagsType, crc: CrcValue, data: CanonicalData) {
        self.blockType = blockType
        self.blockNumber = blockNumber
        self.blockControlFlags = blockControlFlags
        self.crc = crc
        self.data = data
    }
    
    /// Create a new canonical block with default values
    public static func new() -> CanonicalBlock {
        return CanonicalBlock(
            blockType: BlockType.payload.rawValue,
            blockNumber: 0,
            blockControlFlags: 0,
            crc: .crcNo,
            data: .data([])
        )
    }
    
    /// Decode a CBOR byte array into a CanonicalBlock
    public static func fromCbor(_ bytes: [UInt8]) throws(CanonicalError) -> CanonicalBlock {
        let decoded = try CBOR.decode(bytes)
        
        guard case .array(let items) = decoded, items.count >= 5 else {
            throw CanonicalError.decodingError("Invalid CBOR format: expected array with at least 5 items")
        }
        
        // Extract block type
        guard case .unsignedInt(let blockType) = items[0] else {
            throw CanonicalError.decodingError("Invalid block type format")
        }
        
        // Extract block number
        guard case .unsignedInt(let blockNumber) = items[1] else {
            throw CanonicalError.decodingError("Invalid block number format")
        }
        
        // Extract block control flags
        guard case .unsignedInt(let blockControlFlags) = items[2] else {
            throw CanonicalError.decodingError("Invalid block control flags format")
        }
        
        // Extract CRC type
        guard case .unsignedInt(let crcType) = items[3] else {
            throw CanonicalError.decodingError("Invalid CRC type format")
        }
        
        // Extract payload data
        guard case .byteString(let rawPayload) = items[4] else {
            throw CanonicalError.decodingError("Invalid payload format")
        }
        
        // Determine CRC value
        let crc: CrcValue
        if crcType == UInt64(BP7CRC.NO) {
            crc = .crcNo
        } else if crcType == UInt64(BP7CRC.CRC16) {
            if items.count < 6 {
                throw CanonicalError.decodingError("Missing CRC-16 data")
            }
            
            guard case .byteString(let crcBytes) = items[5], crcBytes.count == 2 else {
                throw CanonicalError.decodingError("Invalid CRC-16 format")
            }
            
            var crcData = [UInt8](repeating: 0, count: 2)
            crcData[0] = crcBytes[0]
            crcData[1] = crcBytes[1]
            crc = .crc16(crcData)
        } else if crcType == UInt64(BP7CRC.CRC32) {
            if items.count < 6 {
                throw CanonicalError.decodingError("Missing CRC-32 data")
            }
            
            guard case .byteString(let crcBytes) = items[5], crcBytes.count == 4 else {
                throw CanonicalError.decodingError("Invalid CRC-32 format")
            }
            
            var crcData = [UInt8](repeating: 0, count: 4)
            for i in 0..<4 {
                crcData[i] = crcBytes[i]
            }
            crc = .crc32(crcData)
        } else {
            crc = .unknown(UInt8(truncatingIfNeeded: crcType))
        }
        
        // Parse data based on block type
        let data: CanonicalData
        
        if blockType == BlockType.payload.rawValue {
            data = .data(rawPayload)
        } else if blockType == BlockType.bundleAge.rawValue {
            do {
                let bundleAge = try CBOR.decode(rawPayload)
                guard case .unsignedInt(let age) = bundleAge else {
                    throw CanonicalError.decodingError("Invalid bundle age format")
                }
                data = .bundleAge(age)
            } catch {
                throw CanonicalError.decodingError("Error decoding bundle age block: \(error)")
            }
        } else if blockType == BlockType.hopCount.rawValue {
            do {
                let hopCount = try CBOR.decode(rawPayload)
                guard case .array(let hopCountItems) = hopCount, 
                      hopCountItems.count == 2,
                      case .unsignedInt(let limitInt) = hopCountItems[0],
                      case .unsignedInt(let countInt) = hopCountItems[1],
                      limitInt <= UInt64(UInt8.max),
                      countInt <= UInt64(UInt8.max) else {
                    throw CanonicalError.decodingError("Invalid hop count format")
                }
                data = .hopCount(UInt8(limitInt), UInt8(countInt))
            } catch {
                throw CanonicalError.decodingError("Error decoding hop count block: \(error)")
            }
        } else if blockType == BlockType.previousNode.rawValue {
            do {
                let eidCbor = try CBOR.decode(rawPayload)
                let eid = try EndpointID(from: eidCbor)
                data = .previousNode(eid)
            } catch {
                throw CanonicalError.decodingError("Error decoding previous node block: \(error)")
            }
        } else {
            data = .unknown(rawPayload)
        }
        
        return CanonicalBlock(
            blockType: blockType,
            blockNumber: blockNumber,
            blockControlFlags: UInt8(truncatingIfNeeded: blockControlFlags),
            crc: crc,
            data: data
        )
    }
    
    /// Get the data of this block
    public func getData() -> CanonicalData {
        return self.data
    }
    
    /// Set the data of this block
    public mutating func setData(_ data: CanonicalData) {
        self.data = data
    }
    
    /// Get the payload data if this is a payload block
    public func payloadData() -> [UInt8]? {
        if case .data(let data) = self.data {
            return data
        }
        return nil
    }
    
    /// Validate this canonical block
    public func validate() throws(CanonicalError) {
        var errors: [CanonicalError] = []
        
        // Validate block control flags
        // Check if any reserved bits are set (bits 5-7)
        let flags = BlockControlFlags(rawValue: self.blockControlFlags)
        if (flags.rawValue & 0xE0) != 0 {
            errors.append(CanonicalError.canonicalBlockError("Reserved bits set in block control flags"))
        }
        
        // Validate block number for payload block
        if self.blockType == BlockType.payload.rawValue && self.blockNumber != BlockType.payload.rawValue {
            errors.append(CanonicalError.canonicalBlockError("Payload block must have block number 1"))
        }
        
        // Validate extension data
        do {
            try self.validateData()
        } catch {
            errors.append(error)
        }
        
        // If there are errors, throw them
        if !errors.isEmpty {
            throw CanonicalError.canonicalBlockError("Validation errors: \(errors)")
        }
    }
    
    /// Validate the data in this block
    private func validateData() throws(CanonicalError) {
        switch self.data {
        case .hopCount(let limit, let count):
            if self.blockType != BlockType.hopCount.rawValue {
                throw CanonicalError.canonicalBlockError("Hop count data not matching hop count block type")
            }
            if count > limit {
                throw CanonicalError.canonicalBlockError("Hop count exceeds limit")
            }
        case .data(let data):
            if self.blockType != BlockType.payload.rawValue && self.blockType < BlockType.extensionBlockTypeMin.rawValue {
                throw CanonicalError.canonicalBlockError("Data block type must be payload or extension block")
            }
            if data.isEmpty {
                throw CanonicalError.canonicalBlockError("Data block must not be empty")
            }
        case .bundleAge(_):
            if self.blockType != BlockType.bundleAge.rawValue {
                throw CanonicalError.canonicalBlockError("Bundle age data not matching bundle age block type")
            }
        case .previousNode(let prevEid):
            if self.blockType != BlockType.previousNode.rawValue {
                throw CanonicalError.canonicalBlockError("Previous node data not matching previous node block type")
            }
            // Check if the endpoint ID is valid
            if prevEid.getScheme() == 0 {
                throw CanonicalError.canonicalBlockError("Invalid previous node endpoint ID")
            }
        case .unknown(_):
            // For unknown data, we don't validate the block type
            break
        case .decodingError:
            throw CanonicalError.decodingError("Block contains decoding error")
        }
    }
    
    /// Convert this block to CBOR format
    public func toCbor() -> [UInt8] {
        // Create an array with the block elements
        var elements: [CBOR] = [
            .unsignedInt(self.blockType),
            .unsignedInt(self.blockNumber),
            .unsignedInt(UInt64(self.blockControlFlags)),
            .unsignedInt(UInt64(self.crc.toCode()))
        ]
        
        // Add the data
        switch self.data {
        case .data(let data):
            elements.append(.byteString(data))
        case .bundleAge(let age):
            let cbor: CBOR = .unsignedInt(age)
            elements.append(.byteString(cbor.encode()))
        case .hopCount(let limit, let count):
            let cbor: CBOR = .array([.unsignedInt(UInt64(limit)), .unsignedInt(UInt64(count))])
            elements.append(.byteString(cbor.encode()))
        case .previousNode(let eid):
            let eidCbor = eid.encode()
            elements.append(.byteString(eidCbor.encode()))
        case .unknown(let data):
            elements.append(.byteString(data))
        case .decodingError:
            elements.append(.byteString([]))
        }
        
        // Add CRC value if needed
        if case .crc16(let data) = self.crc {
            elements.append(.byteString(data))
        } else if case .crc32(let data) = self.crc {
            elements.append(.byteString(data))
        }
        
        // Encode the array to CBOR
        let cbor: CBOR = .array(elements)
        return cbor.encode()
    }
    
    /// Get hop count if this is a hop count block
    public func getHopCount() -> (UInt8, UInt8)? {
        if self.blockType == BlockType.hopCount.rawValue {
            if case .hopCount(let limit, let count) = self.data {
                return (limit, count)
            }
        }
        return nil
    }
    
    /// Increase hop count if this is a hop count block
    @discardableResult
    public mutating func increaseHopCount() -> Bool {
        if let (limit, count) = self.getHopCount() {
            self.data = .hopCount(limit, count + 1)
            return true
        }
        return false
    }
    
    /// Check if hop count is exceeded
    public func isHopCountExceeded() -> Bool {
        if let (limit, count) = self.getHopCount() {
            return count > limit
        }
        return false
    }
    
    /// Get bundle age if this is a bundle age block
    public func getBundleAge() -> UInt64? {
        if self.blockType == BlockType.bundleAge.rawValue {
            if case .bundleAge(let age) = self.data {
                return age
            }
        }
        return nil
    }
    
    /// Update bundle age if this is a bundle age block
    @discardableResult
    public mutating func updateBundleAge(_ age: UInt64) -> Bool {
        if self.getBundleAge() != nil {
            self.data = .bundleAge(age)
            return true
        }
        return false
    }
    
    /// Get previous node if this is a previous node block
    public func getPreviousNode() -> EndpointID? {
        if self.blockType == BlockType.previousNode.rawValue {
            if case .previousNode(let eid) = self.data {
                return eid
            }
        }
        return nil
    }
    
    /// Update previous node if this is a previous node block
    @discardableResult
    public mutating func updatePreviousNode(_ nodeId: EndpointID) -> Bool {
        if self.getPreviousNode() != nil {
            self.data = .previousNode(nodeId)
            return true
        }
        return false
    }
}

extension CanonicalBlock: CrcBlock {
    public func crcValue() -> CrcValue {
        return self.crc
    }
    
    public mutating func setCrc(_ crc: CrcValue) {
        self.crc = crc
    }
}

// MARK: - Initializers
extension CanonicalBlock {
    /// Create a new hop count block
    public init(
        blockNumber: UInt64,
        blockControlFlags: BlockControlFlags,
        hopLimit: UInt8
    ) {
        self.init(
            blockType: BlockType.hopCount.rawValue,
            blockNumber: blockNumber,
            blockControlFlags: blockControlFlags.rawValue,
            crc: .crcNo,
            data: .hopCount(hopLimit, 0)
        )
    }
    
    /// Create a new payload block
    public init(
        blockControlFlags: BlockControlFlags,
        payloadData: [UInt8]
    ) {
        self.init(
            blockType: BlockType.payload.rawValue,
            blockNumber: BlockType.payload.rawValue,
            blockControlFlags: blockControlFlags.rawValue,
            crc: .crcNo,
            data: .data(payloadData)
        )
    }
    
    /// Create a new previous node block
    public init(
        blockNumber: UInt64,
        blockControlFlags: BlockControlFlags,
        previousNode: EndpointID
    ) {
        self.init(
            blockType: BlockType.previousNode.rawValue,
            blockNumber: blockNumber,
            blockControlFlags: blockControlFlags.rawValue,
            crc: .crcNo,
            data: .previousNode(previousNode)
        )
    }
    
    /// Create a new bundle age block
    public init(
        blockNumber: UInt64,
        blockControlFlags: BlockControlFlags,
        bundleAge: UInt64
    ) {
        self.init(
            blockType: BlockType.bundleAge.rawValue,
            blockNumber: blockNumber,
            blockControlFlags: blockControlFlags.rawValue,
            crc: .crcNo,
            data: .bundleAge(bundleAge)
        )
    }
}
