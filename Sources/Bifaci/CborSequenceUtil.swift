//
//  CborSequenceUtil.swift
//  Bifaci
//
//  RFC 8742 CBOR Sequence split/assemble utilities.
//
//  A CBOR sequence is a concatenation of independently-encoded CBOR data items
//  with no array wrapper. Each item is a complete, self-delimiting CBOR value.
//  This is the canonical format for list-tagged media URN data in the DAG.

import Foundation
@preconcurrency import SwiftCBOR

/// Errors from CBOR sequence and array operations.
public enum CborSequenceError: Error, LocalizedError {
    case emptySequence
    case notAnArray
    case emptyArray
    case deserializationError(String)
    case serializationError(String)

    public var errorDescription: String? {
        switch self {
        case .emptySequence: return "Empty CBOR sequence — nothing to split"
        case .notAnArray: return "CBOR value is not an array"
        case .emptyArray: return "CBOR array is empty"
        case .deserializationError(let msg): return "CBOR deserialization error: \(msg)"
        case .serializationError(let msg): return "CBOR serialization error: \(msg)"
        }
    }
}

/// Split an RFC 8742 CBOR sequence into individually-serialized CBOR items.
///
/// A CBOR sequence is a concatenation of independently-encoded CBOR data items.
/// This function iterates through the sequence by decoding values one at a time
/// from the byte stream, tracking exact byte consumption.
///
/// Returns each item as its independent CBOR-encoded `Data`.
///
/// - Parameter data: The raw bytes of a CBOR sequence
/// - Returns: Array of individually-encoded CBOR items
/// - Throws: `CborSequenceError.emptySequence` if input is empty,
///           `CborSequenceError.deserializationError` if any value is malformed
public func splitCborSequence(_ data: Data) throws -> [Data] {
    if data.isEmpty {
        throw CborSequenceError.emptySequence
    }

    let bytes = [UInt8](data)
    var items: [Data] = []
    var offset = 0

    while offset < bytes.count {
        let remaining = Array(bytes[offset...])
        let decoder = CBORDecoder(input: remaining)

        let decoded: CBOR?
        do {
            decoded = try decoder.decodeItem()
        } catch {
            throw CborSequenceError.deserializationError(
                "Failed to decode CBOR value at offset \(offset) (\(bytes.count - offset) bytes remaining): \(error)"
            )
        }

        guard let value = decoded else {
            throw CborSequenceError.deserializationError(
                "Unexpected nil CBOR item at offset \(offset)"
            )
        }

        // Re-encode the decoded value to get the canonical serialized form
        let encoded = value.encode()
        items.append(Data(encoded))
        offset += encoded.count
    }

    if items.isEmpty {
        throw CborSequenceError.emptySequence
    }

    return items
}

/// Assemble individually-serialized CBOR items into an RFC 8742 CBOR sequence.
///
/// Each input item must be a complete CBOR value. The result is their raw
/// concatenation (no array wrapper). This is the inverse of `splitCborSequence`.
///
/// - Parameter items: Array of individually-encoded CBOR items
/// - Returns: The concatenated CBOR sequence bytes
/// - Throws: `CborSequenceError.deserializationError` if any item is not valid CBOR
public func assembleCborSequence(_ items: [Data]) throws -> Data {
    var result = Data()
    for (i, item) in items.enumerated() {
        // Validate each item is valid CBOR
        guard let _ = try? CBOR.decode([UInt8](item)) else {
            throw CborSequenceError.deserializationError("Item \(i): not valid CBOR")
        }
        result.append(item)
    }
    return result
}

// MARK: - CBOR Array split/assemble

/// Split a CBOR array into individually-serialized CBOR items.
///
/// Decodes the input as a CBOR array, then re-encodes each element
/// as an independent CBOR value. This is distinct from CBOR sequences:
/// an array is a single CBOR value containing multiple items, while a
/// sequence is a concatenation of independent CBOR values.
///
/// - Parameter data: The raw bytes of a CBOR array
/// - Returns: Array of individually-encoded CBOR items
/// - Throws: `CborSequenceError.notAnArray` if the input is not a CBOR array,
///           `CborSequenceError.emptyArray` if the array is empty,
///           `CborSequenceError.deserializationError` if the value is malformed
public func splitCborArray(_ data: Data) throws -> [Data] {
    let bytes = [UInt8](data)

    let decoded: CBOR
    do {
        guard let value = try CBOR.decode(bytes) else {
            throw CborSequenceError.deserializationError("Failed to decode CBOR value")
        }
        decoded = value
    } catch let error as CborSequenceError {
        throw error
    } catch {
        throw CborSequenceError.deserializationError("CBOR decode failed: \(error)")
    }

    guard case .array(let items) = decoded else {
        throw CborSequenceError.notAnArray
    }

    if items.isEmpty {
        throw CborSequenceError.emptyArray
    }

    return items.map { item in
        Data(item.encode())
    }
}

/// Assemble individually-serialized CBOR items into a single CBOR array.
///
/// Each input item must be a complete CBOR value. The result is a CBOR array
/// containing all items in order.
///
/// - Parameter items: Array of individually-encoded CBOR items
/// - Returns: The CBOR array bytes
/// - Throws: `CborSequenceError.deserializationError` if any item is not valid CBOR,
///           `CborSequenceError.serializationError` if the array cannot be serialized
public func assembleCborArray(_ items: [Data]) throws -> Data {
    var values: [CBOR] = []
    for (i, item) in items.enumerated() {
        guard let value = try? CBOR.decode([UInt8](item)) else {
            throw CborSequenceError.deserializationError("Item \(i): not valid CBOR")
        }
        values.append(value)
    }

    let array = CBOR.array(values)
    return Data(array.encode())
}
