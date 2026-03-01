//
//  CSStdinSource.h
//  CapDAG
//
//  Represents the source for stdin data - either raw bytes or a file reference.
//  For plugins (via gRPC/XPC), using file references avoids size limits
//  by letting the receiving side read the file locally.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Types of stdin sources
 */
typedef NS_ENUM(NSInteger, CSStdinSourceKind) {
    /// Raw byte data for stdin
    CSStdinSourceKindData,
    /// File reference for stdin - used for plugins to read files locally
    CSStdinSourceKindFileReference
};

/**
 * Represents the source for stdin data.
 * Can be either raw bytes (Data) or a file reference (FileReference).
 */
@interface CSStdinSource : NSObject

/// The type of this stdin source
@property (nonatomic, readonly) CSStdinSourceKind kind;

/// Raw byte data (only valid when kind == CSStdinSourceKindData)
@property (nonatomic, readonly, nullable) NSData *data;

/// Tracked file ID for lifecycle management (only valid when kind == CSStdinSourceKindFileReference)
@property (nonatomic, readonly, nullable) NSString *trackedFileID;

/// Original file path for logging/debugging (only valid when kind == CSStdinSourceKindFileReference)
@property (nonatomic, readonly, nullable) NSString *originalPath;

/// Security bookmark data (only valid when kind == CSStdinSourceKindFileReference)
@property (nonatomic, readonly, nullable) NSData *securityBookmark;

/// Media URN describing the expected type (only valid when kind == CSStdinSourceKindFileReference)
@property (nonatomic, readonly, nullable) NSString *mediaUrn;

/**
 * Create a stdin source from raw data
 * @param data The raw byte data for stdin
 * @return A new CSStdinSource instance with kind == CSStdinSourceKindData
 */
+ (instancetype)sourceWithData:(NSData *)data;

/**
 * Create a stdin source from a file reference
 * @param trackedFileID The tracked file ID for lifecycle management
 * @param originalPath The original file path for logging
 * @param securityBookmark The security bookmark data for sandbox access
 * @param mediaUrn The media URN describing the expected type
 * @return A new CSStdinSource instance with kind == CSStdinSourceKindFileReference
 */
+ (instancetype)sourceWithFileReference:(NSString *)trackedFileID
                           originalPath:(NSString *)originalPath
                        securityBookmark:(NSData *)securityBookmark
                                mediaUrn:(NSString *)mediaUrn;

/// Returns YES if this is a data source
- (BOOL)isData;

/// Returns YES if this is a file reference source
- (BOOL)isFileReference;

@end

NS_ASSUME_NONNULL_END
