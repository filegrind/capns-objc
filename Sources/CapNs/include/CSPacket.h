//
//  CSPacket.h
//  Binary Packet Framing for Plugin Communication
//
//  All plugin stdin/stdout communication uses length-prefixed binary packets.
//  This provides a clean transport layer that can carry any payload type.
//
//  Packet format:
//  ┌─────────────────────────────────────────────────────────┐
//  │  4 bytes: u32 big-endian length                         │
//  ├─────────────────────────────────────────────────────────┤
//  │  N bytes: payload                                       │
//  └─────────────────────────────────────────────────────────┘
//
//  The payload can be:
//  - JSON envelope for structured messages
//  - Raw binary data for binary transfers
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Maximum packet size (16 MB) to prevent memory exhaustion
extern const uint32_t CSPacketMaxSize;

/// Error domain for packet operations
extern NSString * const CSPacketErrorDomain;

/// Packet error codes
typedef NS_ENUM(NSInteger, CSPacketErrorCode) {
    CSPacketErrorCodeIOError = 1,
    CSPacketErrorCodePacketTooLarge = 2,
    CSPacketErrorCodeUnexpectedEOF = 3,
    CSPacketErrorCodeInvalidPacket = 4,
};

#pragma mark - CSPacketReader

/**
 * Reads binary packets from a file handle.
 */
@interface CSPacketReader : NSObject

/// The underlying file handle
@property (nonatomic, readonly) NSFileHandle *fileHandle;

/**
 * Create a packet reader for a file handle
 * @param fileHandle The file handle to read from
 * @return A new CSPacketReader instance
 */
+ (instancetype)readerWithFileHandle:(NSFileHandle *)fileHandle;

/**
 * Read the next packet from the file handle.
 * Blocks until a complete packet is available or EOF is reached.
 *
 * @param error Error pointer for error reporting
 * @return The packet payload data, or nil on EOF or error.
 *         Check error to distinguish between EOF (no error) and actual errors.
 */
- (nullable NSData *)readPacketWithError:(NSError * _Nullable * _Nullable)error;

/**
 * Read the next packet with a timeout.
 *
 * @param timeoutMs Timeout in milliseconds (0 = no timeout)
 * @param error Error pointer for error reporting
 * @return The packet payload data, or nil on EOF, timeout, or error.
 */
- (nullable NSData *)readPacketWithTimeout:(uint32_t)timeoutMs error:(NSError * _Nullable * _Nullable)error;

@end

#pragma mark - CSPacketWriter

/**
 * Writes binary packets to a file handle.
 */
@interface CSPacketWriter : NSObject

/// The underlying file handle
@property (nonatomic, readonly) NSFileHandle *fileHandle;

/**
 * Create a packet writer for a file handle
 * @param fileHandle The file handle to write to
 * @return A new CSPacketWriter instance
 */
+ (instancetype)writerWithFileHandle:(NSFileHandle *)fileHandle;

/**
 * Write a packet to the file handle.
 * Automatically prepends the 4-byte length prefix.
 *
 * @param data The payload data to write
 * @param error Error pointer for error reporting
 * @return YES on success, NO on error
 */
- (BOOL)writePacket:(NSData *)data error:(NSError * _Nullable * _Nullable)error;

@end

#pragma mark - Utility Functions

/**
 * Read a single packet from a file handle (convenience function).
 *
 * @param fileHandle The file handle to read from
 * @param error Error pointer for error reporting
 * @return The packet payload data, or nil on EOF or error
 */
NSData * _Nullable CSPacketRead(NSFileHandle *fileHandle, NSError * _Nullable * _Nullable error);

/**
 * Write a single packet to a file handle (convenience function).
 *
 * @param fileHandle The file handle to write to
 * @param data The payload data to write
 * @param error Error pointer for error reporting
 * @return YES on success, NO on error
 */
BOOL CSPacketWrite(NSFileHandle *fileHandle, NSData *data, NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
