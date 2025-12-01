//
//  CSResponseWrapper.h
//  Response wrapper for unified plugin output handling with validation
//
//  Unified response wrapper for all plugin operations
//  Provides type-safe deserialization of plugin output
//

#import <Foundation/Foundation.h>
#import "CSCap.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CSResponseContentType) {
    CSResponseContentTypeJson,
    CSResponseContentTypeText,
    CSResponseContentTypeBinary
};

/**
 * Unified response wrapper for all plugin operations
 * Provides type-safe deserialization of plugin output
 */
@interface CSResponseWrapper : NSObject

@property (nonatomic, readonly) NSData *rawBytes;
@property (nonatomic, readonly) CSResponseContentType contentType;

/**
 * Create response wrapper from raw bytes
 * @param data The raw response data
 * @return A new CSResponseWrapper instance
 */
+ (instancetype)responseWithData:(NSData *)data;

/**
 * Create JSON response wrapper
 * @param data The raw response data
 * @return A new CSResponseWrapper instance with JSON content type
 */
+ (instancetype)jsonResponseWithData:(NSData *)data;

/**
 * Create text response wrapper  
 * @param data The raw response data
 * @return A new CSResponseWrapper instance with text content type
 */
+ (instancetype)textResponseWithData:(NSData *)data;

/**
 * Create binary response wrapper
 * @param data The raw response data
 * @return A new CSResponseWrapper instance with binary content type
 */
+ (instancetype)binaryResponseWithData:(NSData *)data;

/**
 * Get response as string
 * @param error Pointer to error for error reporting
 * @return String representation or nil if conversion fails
 */
- (NSString * _Nullable)asStringWithError:(NSError * _Nullable * _Nullable)error;

/**
 * Get response as raw bytes
 * @return Raw bytes of the response
 */
- (NSData *)asBytes;

/**
 * Get response size
 * @return Size of raw bytes
 */
- (NSUInteger)size;

/**
 * Validate response against cap output definition
 * @param cap The capability definition to validate against
 * @param error Pointer to error for validation errors
 * @return YES if validation passes, NO otherwise
 */
- (BOOL)validateAgainstCap:(CSCap *)cap error:(NSError * _Nullable * _Nullable)error;

/**
 * Get content type as string
 * @return Content type string
 */
- (NSString *)getContentTypeString;

/**
 * Check if response matches expected output type
 * @param cap The capability definition
 * @return YES if types match, NO otherwise
 */
- (BOOL)matchesOutputTypeForCap:(CSCap *)cap;

@end

NS_ASSUME_NONNULL_END