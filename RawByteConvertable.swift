// copy the raw bytes of a value
private func unsafeBytes<T>(for value: T) -> [UInt8] {
	return withUnsafeBytes(of: value) { Array($0) }
}

// use raw bytes to recreate a value
private func unsafeValue<T>(from bytes: [UInt8]) -> T {
	return bytes.withUnsafeBytes { $0.baseAddress!.load(as: T.self) }
}

/// Types that conform to this protocol are promising that they can be converted to/from an array of raw bytes.
public protocol RawByteConvertable {
	init(rawBytes: [UInt8])
	var rawBytes: [UInt8] { get }
}

// always uses bigEndian
extension RawByteConvertable where Self: FixedWidthInteger {
	public init(rawBytes: [UInt8]) { self.init(bigEndian: unsafeValue(from: rawBytes)) }
	public var rawBytes: [UInt8] { return unsafeBytes(for: bigEndian) }
}

// this just writes the raw in-memory representation of the floating point - I do not know for sure if that is always safe/correct
extension RawByteConvertable where Self: BinaryFloatingPoint {
	public init(rawBytes: [UInt8]) { self.init(unsafeValue(from: rawBytes) as Self) }
	public var rawBytes: [UInt8] { return unsafeBytes(for: self) }
}

extension Int8: RawByteConvertable {}
extension UInt8: RawByteConvertable {}
extension Int16: RawByteConvertable {}
extension UInt16: RawByteConvertable {}
extension Int32: RawByteConvertable {}
extension UInt32: RawByteConvertable {}
extension Int64: RawByteConvertable {}
extension UInt64: RawByteConvertable {}
extension Float32: RawByteConvertable {}
extension Float64: RawByteConvertable {}

#if canImport(Foundation)
import Foundation
extension Data: RawByteConvertable {
	public init(rawBytes: [UInt8]) { self = Data(bytes: rawBytes) }
	public var rawBytes: [UInt8] { return Array(self) }
}
#endif
