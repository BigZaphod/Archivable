import Foundation

//==---------------------------------------------------------
/// Simply write the values you want to archive into the given
/// ArchiveWriter. If implemented manually, make sure you
/// deocde them in exactly the same order and with exactly the
/// same types or else bad things will happen. Use Archivable
/// instead so that you don't have to worry about this.
///
public protocol ArchiveWriteable {
	func write(to archive: ArchiveWriter) throws
}

//==---------------------------------------------------------
/// Unlike Swift's Codable, the ArchiveReadable implementation
/// requires the ability to initialize an instance of a type
/// before it can fully decode it. This is so we can support
/// reference types automatically - Class type instances are
/// only stored once in the archive. Decoding a reference
/// requires the ability to first make an instance and then
/// fill it in with the values that are read from the archive
/// in a seperate step because Swift is very strict and has
/// strong opinions about these things. Other solutions to
/// this problem are possible but they require more foresight
/// and code redesign than I'd like to be forced to do.
///
public protocol ArchiveReadable {
	init()
	
	mutating func read(from archive: ArchiveReader) throws

	/// If you need to do something after a type instance "wakes up"
	/// then this is where you can do it. Most of the time you don't
	/// so there is an empty default implementation.
	mutating func awake(from archive: ArchiveReader) throws
}

//==---------------------------------------------------------
/// Use this protocol if your type doesn't need to archive
/// any properties. Useful for enums and such.
///
public typealias Archivable = ArchiveReadable & ArchiveWriteable

//==---------------------------------------------------------
/// This is the magic protocol your types should conform to.
/// They will automatically get write(to:) and read(from:).
/// You will need to supply ArchiveReadable's default init()
/// initializer as well as Archivable's archivingKeyPaths
/// static property which lists the key paths you wish to be
/// included in the generated archives.
///
public protocol KeyPathArchivable: ArchiveWriteable & ArchiveReadable {
	typealias Archive = ArchivableKeyPath<Self>

	/// This list is used to determine which properties are
	/// saved and restored from the archive. The order listed
	/// is the same order they are read and written.
	static var archivingKeyPaths: [Archive] { get }
}

// Default implementations can make life easier sometimes.
extension ArchiveReadable {
	public mutating func awake(from archive: ArchiveReader) throws {
	}
}

// here's the magic that makes Archivable read/write using
// the keypaths specified by the static archivingKeyPaths
// property:
public struct ArchivableKeyPath<Root: KeyPathArchivable> {
	fileprivate let valueType: ArchiveReadable.Type
	fileprivate let get: (Root)->ArchiveWriteable
	fileprivate let set: (inout Root, ArchiveReadable)->Void
	
	init<Value: ArchiveWriteable & ArchiveReadable>(_ keyPath: WritableKeyPath<Root, Value>) {
		self.valueType = Value.self
		
		self.get = { instance in
			return instance[keyPath: keyPath] as ArchiveWriteable
		}
		
		self.set = { instance, newValue in
			let value = newValue as! Value
			instance[keyPath: keyPath] = value
		}
	}
}

extension KeyPathArchivable {
	func write(to archive: ArchiveWriter) throws {
		for property in Self.archivingKeyPaths {
			try archive.write(property.get(self))
		}
	}
	
	mutating func read(from archive: ArchiveReader) throws {
		for property in Self.archivingKeyPaths {
			property.set(&self, try archive.readArchiveReadable(property.valueType))
		}
	}
}


//==---------------------------------------------------------
// types that can read/write their raw bytes directly:
//==---------------------------------------------------------

extension Int8: Archivable {}
extension UInt8: Archivable {}
extension Int16: Archivable {}
extension UInt16: Archivable {}
extension Int32: Archivable {}
extension UInt32: Archivable {}
extension Int64: Archivable {}
extension UInt64: Archivable {}
extension Float32: Archivable {}
extension Float64: Archivable {}
extension Data: Archivable {}

// (and this is how they do it...)
extension RawByteConvertable where Self: Archivable {
	public func write(to archive: ArchiveWriter) throws {
		try archive.writeRawBytes(self.rawBytes)
	}

	public mutating func read(from archive: ArchiveReader) throws {
		try self = .init(rawBytes: archive.readRawBytes(count: MemoryLayout<Self>.size))
	}
}


//==---------------------------------------------------------
// string is an exception because of built-in support for
// uniquing strings so they are only stored once the actual
// encoding/decoding is handled by ArchiveWriter/ArchiveReader
//==---------------------------------------------------------

extension String: Archivable {
	public mutating func read(from archive: ArchiveReader) throws { try self = archive.read() }
	public func write(to archive: ArchiveWriter) throws { try archive.write(self) }
}


//==---------------------------------------------------------
// Types that are encoded in terms of other archivable types:
//==---------------------------------------------------------

extension Bool: Archivable {
	public mutating func read(from archive: ArchiveReader) throws { try self = (archive.read() as UInt8 > 0) }
	public func write(to archive: ArchiveWriter) throws { try archive.write(UInt8(self ? 1 : 0)) }
}

// Int is always stored as an Int64
extension Int: Archivable {
	public mutating func read(from archive: ArchiveReader) throws { try self = Int(archive.read() as Int64) }
	public func write(to archive: ArchiveWriter) throws { try archive.write(Int64(self)) }
}

// UInt is always stored as a UInt64
extension UInt: Archivable {
	public mutating func read(from archive: ArchiveReader) throws { try self = UInt(archive.read() as UInt64) }
	public func write(to archive: ArchiveWriter) throws { try archive.write(UInt64(self)) }
}

extension Array: Archivable where Element: Archivable {
	public mutating func read(from archive: ArchiveReader) throws {
		let count: Int = try archive.read()
		self = try (0..<count).map({ _ in try archive.read() })
	}

	public func write(to archive: ArchiveWriter) throws {
		try archive.write(count)
		try forEach({ try archive.write($0) })
	}
}

extension Dictionary: Archivable where Key: Archivable, Value: Archivable {
	public func write(to archive: ArchiveWriter) throws {
		try archive.write(Array(keys))
		try archive.write(Array(values))
	}

	public mutating func read(from archive: ArchiveReader) throws {
		let keys: [Key] = try archive.read()
		let values: [Value] = try archive.read()
		zip(keys, values).forEach({ updateValue($1, forKey: $0) })
	}
}

extension Set: Archivable where Element: Archivable {
	public mutating func read(from archive: ArchiveReader) throws {
		self = Set(try archive.read() as [Element])
	}

	public func write(to archive: ArchiveWriter) throws {
		try archive.write(Array(self))
	}
}

extension Optional: Archivable where Wrapped: Archivable {
	public func write(to archive: ArchiveWriter) throws {
		if let value = self {
			try archive.write(true)
			try archive.write(value)
		} else {
			try archive.write(false)
		}
	}

	public init() { self = .none }
	
	public mutating func read(from archive: ArchiveReader) throws {
		if try archive.read() as Bool {
			try self = .some(archive.read())
		} else {
			self = .none
		}
	}
}

//==---------------------------------------------------------
// enums, OptionSets, etc can be archived automatically
// if they are represented by a raw value that is archivable
//==---------------------------------------------------------

extension ArchiveWriteable where Self: RawRepresentable, Self.RawValue: ArchiveWriteable {
	func write(to archive: ArchiveWriter) throws { try archive.write(rawValue) }
}

extension ArchiveReadable where Self: RawRepresentable, Self.RawValue: ArchiveReadable {
	mutating func read(from archive: ArchiveReader) throws {
		guard let value = Self.init(rawValue: try archive.read()) else {
			throw ArchivingError.readFailed
		}
		self = value
	}
}


/// Errors that may be thrown by the archiving system.
public enum ArchivingError: Error {
	case writeFailed
	case readFailed
	case incompatibleArchiver
}

/// This takes an object/value and converts it and everything it references into an archive.
public final class ArchiveWriter {
	public static let encodingVersion: Int = 1
	
	public let userInfo: Any?
	
	private let stream: OutputStream
	private var objectIds: [ObjectIdentifier : Int]
	private var stringIds: [String : Int]
	
	public static func write<T: ArchiveWriteable>(_ value: T, as type: T.Type, to stream: OutputStream, userInfo: Any? = nil, version: Int = 0) throws {
		// make a writer instance
		let archive = ArchiveWriter(to: stream, userInfo: userInfo)
		
		// immediately write the simplest header ever
		try archive.write(ArchiveWriter.encodingVersion as Int)
		try archive.write(version as Int)

		// write the value
		try archive.write(value)
	}
	
	public static func data<T: ArchiveWriteable>(for value: T, as type: T.Type, userInfo: Any? = nil) throws -> Data {
		let stream = OutputStream.toMemory()
		stream.open()
		
		try write(value, as: type, to: stream, userInfo: userInfo)
		
		guard let data = stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
			throw ArchivingError.writeFailed
		}
		
		return data
	}
	
	private init(to stream: OutputStream, userInfo: Any?) {
		self.stream = stream
		self.objectIds = [:]
		self.stringIds = [:]
		self.userInfo = userInfo
	}
	
	private func encodeString(_ string: String) throws {
		if let idx = stringIds[string] {
			try write(idx)
		} else {
			let idx = stringIds.count
			stringIds[string] = idx
			try write(idx)
			try write(Array(string.utf8))
		}
	}
	
	private func encodeReference(_ obj: AnyObject & ArchiveWriteable) throws {
		let ref = ObjectIdentifier(obj)
		if let idx = objectIds[ref] {
			try write(idx)
		} else {
			let idx = objectIds.count
			objectIds[ref] = idx
			try write(idx)
			try obj.write(to: self)
		}
	}
	
	public func write(_ value: ArchiveWriteable) throws {
		if type(of: value) is String.Type {
			try encodeString(value as! String)
		} else if type(of: value) is AnyClass {
			try encodeReference(value as! AnyObject & ArchiveWriteable)
		} else {
			try value.write(to: self)
		}
	}
	
	public func writeRawBytes(_ bytes: [UInt8]) throws {
		let written = stream.write(bytes, maxLength: bytes.count)
		guard bytes.count == written else {
			throw ArchivingError.readFailed
		}
	}
}

/// This is the opposite of the ArchiveWriter.
public final class ArchiveReader {
	public let userInfo: Any?
	public private(set) var version: Int = 0
	
	private let stream: InputStream
	private var strings: [Int : String]
	private var objects: [Int : ArchiveReadable]
	
	public static func read<T: ArchiveReadable>(_ type: T.Type, from stream: InputStream, userInfo: Any? = nil) throws -> T {
		// make and reader
		let archive = ArchiveReader(forReadingFrom: stream, userInfo: userInfo)
		
		// immediately read the header
		let encodingVersion = try archive.read() as Int
		archive.version = try archive.read() as Int

		// we only support this version for now
		guard encodingVersion == ArchiveWriter.encodingVersion else { throw ArchivingError.incompatibleArchiver }
		
		// load the value
		return try archive.read()
	}
	
	public static func read<T: ArchiveReadable>(_ type: T.Type, from source: Data, userInfo: Any? = nil) throws -> T {
		let stream = InputStream(data: source)
		stream.open()
		return try read(type, from: stream, userInfo: userInfo)
	}
	
	private init(forReadingFrom stream: InputStream, userInfo: Any?) {
		self.stream = stream
		self.strings = [:]
		self.objects = [:]
		self.userInfo = userInfo
	}
	
	private func decodeString() throws -> String {
		let id: Int = try read()
		
		if let str = strings[id] {
			return str
		}
		
		let input: [UInt8] = try read()
		
		guard let str = String(bytes: input, encoding: .utf8) else {
			throw ArchivingError.readFailed
		}
		
		strings[id] = str
		return str
	}
	
	private func decodeReference(of type: ArchiveReadable.Type) throws -> ArchiveReadable {
		let id: Int = try read()
		
		if let obj = objects[id] {
			return obj
		}
		
		var obj = type.init()
		objects[id] = obj
		try obj.read(from: self)
		try obj.awake(from: self)
		return obj
	}
	
	fileprivate func readArchiveReadable(_ type: ArchiveReadable.Type) throws -> ArchiveReadable {
		if type is String.Type {
			return try decodeString()
		} else if type is AnyClass {
			return try decodeReference(of: type)
		} else {
			var value = type.init()
			try value.read(from: self)
			try value.awake(from: self)
			return value
		}
	}

	public func read<T: ArchiveReadable>() throws -> T {
		return try readArchiveReadable(T.self) as! T
	}

	public func readRawBytes(count: Int) throws -> [UInt8] {
		var buffer: [UInt8] = Array(repeating: 0, count: count)
		let got = stream.read(&buffer, maxLength: count)
		guard got == count else {
			throw ArchivingError.readFailed
		}
		return buffer
	}
}
