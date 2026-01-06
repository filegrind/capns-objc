//
//  CSMediaSpec.h
//  MediaSpec parsing and handling
//
//  Parses media_spec values in the format:
//  `content-type: <mime-type>; profile=<url>`
//
//  Examples:
//  - `content-type: application/json; profile="https://capns.org/schema/document-outline"`
//  - `content-type: image/png; profile="https://capns.org/schema/thumbnail-image"`
//  - `content-type: text/plain; profile=https://capns.org/schema/utf8-text`
//

#import <Foundation/Foundation.h>

@class CSCapUrn;

NS_ASSUME_NONNULL_BEGIN

/// Error domain for MediaSpec errors
FOUNDATION_EXPORT NSErrorDomain const CSMediaSpecErrorDomain;

/// Error codes for MediaSpec operations
typedef NS_ERROR_ENUM(CSMediaSpecErrorDomain, CSMediaSpecError) {
    CSMediaSpecErrorMissingContentType = 1,
    CSMediaSpecErrorEmptyContentType = 2,
    CSMediaSpecErrorUnterminatedQuote = 3
};

/**
 * A parsed MediaSpec value
 */
@interface CSMediaSpec : NSObject

/// The MIME content type (e.g., "application/json", "image/png")
@property (nonatomic, readonly) NSString *contentType;

/// Optional profile URL
@property (nonatomic, readonly, nullable) NSString *profile;

/**
 * Parse a media_spec string
 * Format: `content-type: <mime-type>; profile=<url>`
 * @param string The media_spec string
 * @param error Error if parsing fails
 * @return A new CSMediaSpec instance or nil if invalid
 */
+ (nullable instancetype)parse:(NSString *)string error:(NSError * _Nullable * _Nullable)error;

/**
 * Create a MediaSpec from content type and optional profile
 * @param contentType The MIME content type
 * @param profile Optional profile URL
 * @return A new CSMediaSpec instance
 */
+ (instancetype)withContentType:(NSString *)contentType profile:(nullable NSString *)profile;

/**
 * Check if this media spec represents binary output
 * @return YES if binary (image/*, audio/*, video/*, application/octet-stream, etc.)
 */
- (BOOL)isBinary;

/**
 * Check if this media spec represents JSON output
 * @return YES if application/json or *+json
 */
- (BOOL)isJSON;

/**
 * Check if this media spec represents text output
 * @return YES if text/* or neither binary nor JSON
 */
- (BOOL)isText;

/**
 * Get the primary type (e.g., "image" from "image/png")
 * @return The primary type
 */
- (NSString *)primaryType;

/**
 * Get the subtype (e.g., "png" from "image/png")
 * @return The subtype or nil if not present
 */
- (nullable NSString *)subtype;

/**
 * Get the canonical string representation
 * @return The media_spec as a string
 */
- (NSString *)toString;

@end

/**
 * Helper functions for working with MediaSpec in CapUrn
 */
@interface CSMediaSpec (CapUrn)

/**
 * Extract MediaSpec from a CapUrn, checking 'out' first, then 'media_spec'
 * @param capUrn The cap URN to extract from
 * @param error Error if no media_spec found or parsing fails
 * @return The parsed MediaSpec or nil if not found
 */
+ (nullable instancetype)fromCapUrn:(CSCapUrn *)capUrn error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
