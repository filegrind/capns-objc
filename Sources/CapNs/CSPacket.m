//
//  CSPacket.m
//  Binary Packet Framing for Plugin Communication
//

#import "CSPacket.h"

/// Maximum packet size (16 MB) to prevent memory exhaustion
const uint32_t CSPacketMaxSize = 16 * 1024 * 1024;

/// Error domain for packet operations
NSString * const CSPacketErrorDomain = @"CSPacketErrorDomain";

#pragma mark - CSPacketReader

@implementation CSPacketReader {
    NSFileHandle *_fileHandle;
}

+ (instancetype)readerWithFileHandle:(NSFileHandle *)fileHandle {
    CSPacketReader *reader = [[CSPacketReader alloc] init];
    if (reader) {
        reader->_fileHandle = fileHandle;
    }
    return reader;
}

- (NSFileHandle *)fileHandle {
    return _fileHandle;
}

- (nullable NSData *)readPacketWithError:(NSError * _Nullable * _Nullable)error {
    return [self readPacketWithTimeout:0 error:error];
}

- (nullable NSData *)readPacketWithTimeout:(uint32_t)timeoutMs error:(NSError * _Nullable * _Nullable)error {
    // Read 4-byte length prefix (big-endian)
    NSData *lengthData;

    @try {
        lengthData = [_fileHandle readDataOfLength:4];
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:CSPacketErrorDomain
                                         code:CSPacketErrorCodeIOError
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Read failed"}];
        }
        return nil;
    }

    // Check for EOF
    if (lengthData == nil || lengthData.length == 0) {
        // Clean EOF - no error
        return nil;
    }

    if (lengthData.length < 4) {
        // Partial read - unexpected EOF
        if (error) {
            *error = [NSError errorWithDomain:CSPacketErrorDomain
                                         code:CSPacketErrorCodeUnexpectedEOF
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unexpected end of stream reading length prefix"}];
        }
        return nil;
    }

    // Parse big-endian length
    const uint8_t *bytes = (const uint8_t *)lengthData.bytes;
    uint32_t length = ((uint32_t)bytes[0] << 24) |
                      ((uint32_t)bytes[1] << 16) |
                      ((uint32_t)bytes[2] << 8) |
                      ((uint32_t)bytes[3]);

    // Validate length
    if (length > CSPacketMaxSize) {
        if (error) {
            *error = [NSError errorWithDomain:CSPacketErrorDomain
                                         code:CSPacketErrorCodePacketTooLarge
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Packet too large: %u bytes (max %u)", length, CSPacketMaxSize]
                                     }];
        }
        return nil;
    }

    // Handle zero-length packet
    if (length == 0) {
        return [NSData data];
    }

    // Read payload
    NSData *payload;
    @try {
        payload = [_fileHandle readDataOfLength:length];
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:CSPacketErrorDomain
                                         code:CSPacketErrorCodeIOError
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Read failed"}];
        }
        return nil;
    }

    if (payload == nil || payload.length < length) {
        if (error) {
            *error = [NSError errorWithDomain:CSPacketErrorDomain
                                         code:CSPacketErrorCodeUnexpectedEOF
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unexpected end of stream reading payload"}];
        }
        return nil;
    }

    return payload;
}

@end

#pragma mark - CSPacketWriter

@implementation CSPacketWriter {
    NSFileHandle *_fileHandle;
}

+ (instancetype)writerWithFileHandle:(NSFileHandle *)fileHandle {
    CSPacketWriter *writer = [[CSPacketWriter alloc] init];
    if (writer) {
        writer->_fileHandle = fileHandle;
    }
    return writer;
}

- (NSFileHandle *)fileHandle {
    return _fileHandle;
}

- (BOOL)writePacket:(NSData *)data error:(NSError * _Nullable * _Nullable)error {
    uint32_t length = (uint32_t)data.length;

    // Validate length
    if (length > CSPacketMaxSize) {
        if (error) {
            *error = [NSError errorWithDomain:CSPacketErrorDomain
                                         code:CSPacketErrorCodePacketTooLarge
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Packet too large: %u bytes (max %u)", length, CSPacketMaxSize]
                                     }];
        }
        return NO;
    }

    // Build length prefix (big-endian)
    uint8_t lengthBytes[4];
    lengthBytes[0] = (length >> 24) & 0xFF;
    lengthBytes[1] = (length >> 16) & 0xFF;
    lengthBytes[2] = (length >> 8) & 0xFF;
    lengthBytes[3] = length & 0xFF;

    NSData *lengthData = [NSData dataWithBytes:lengthBytes length:4];

    @try {
        [_fileHandle writeData:lengthData];
        if (data.length > 0) {
            [_fileHandle writeData:data];
        }
        // Note: synchronizeFile is deprecated, but we need to ensure data is flushed
        // In modern code, use try/catch with synchronizeAndReturnError:
        if (@available(macOS 10.15, iOS 13.0, *)) {
            NSError *syncError = nil;
            [_fileHandle synchronizeAndReturnError:&syncError];
            if (syncError && error) {
                *error = syncError;
                return NO;
            }
        }
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:CSPacketErrorDomain
                                         code:CSPacketErrorCodeIOError
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Write failed"}];
        }
        return NO;
    }

    return YES;
}

@end

#pragma mark - Utility Functions

NSData * _Nullable CSPacketRead(NSFileHandle *fileHandle, NSError * _Nullable * _Nullable error) {
    CSPacketReader *reader = [CSPacketReader readerWithFileHandle:fileHandle];
    return [reader readPacketWithError:error];
}

BOOL CSPacketWrite(NSFileHandle *fileHandle, NSData *data, NSError * _Nullable * _Nullable error) {
    CSPacketWriter *writer = [CSPacketWriter writerWithFileHandle:fileHandle];
    return [writer writePacket:data error:error];
}
