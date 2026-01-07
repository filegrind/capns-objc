//
//  CSMediaSpec.h
//  MediaSpec parsing and handling
//
//  Parses media_spec values in the canonical format:
//  `<media-type>; profile=<url>`
//
//  Examples:
//  - `application/json; profile="https://capns.org/schema/document-outline"`
//  - `image/png; profile="https://capns.org/schema/thumbnail-image"`
//  - `text/plain; profile=https://capns.org/schema/str`
//
//  NOTE: The legacy "content-type:" prefix is NO LONGER SUPPORTED and will cause a hard failure.
//

#import <Foundation/Foundation.h>

@class CSCapUrn;

NS_ASSUME_NONNULL_BEGIN

/// Error domain for MediaSpec errors
FOUNDATION_EXPORT NSErrorDomain const CSMediaSpecErrorDomain;

/// Error codes for MediaSpec operations
typedef NS_ERROR_ENUM(CSMediaSpecErrorDomain, CSMediaSpecError) {
    CSMediaSpecErrorEmptyContentType = 1,
    CSMediaSpecErrorUnterminatedQuote = 2,
    CSMediaSpecErrorLegacyFormat = 3,
    CSMediaSpecErrorUnresolvableSpecId = 4
};

// ============================================================================
// BUILT-IN SPEC ID CONSTANTS
// ============================================================================

/// Well-known built-in spec IDs - these do not need to be declared in mediaSpecs
FOUNDATION_EXPORT NSString * const CSSpecIdStr;      // capns:ms:str.v1
FOUNDATION_EXPORT NSString * const CSSpecIdInt;      // capns:ms:int.v1
FOUNDATION_EXPORT NSString * const CSSpecIdNum;      // capns:ms:num.v1
FOUNDATION_EXPORT NSString * const CSSpecIdBool;     // capns:ms:bool.v1
FOUNDATION_EXPORT NSString * const CSSpecIdObj;      // capns:ms:obj.v1
FOUNDATION_EXPORT NSString * const CSSpecIdStrArray; // capns:ms:str-array.v1
FOUNDATION_EXPORT NSString * const CSSpecIdIntArray; // capns:ms:int-array.v1
FOUNDATION_EXPORT NSString * const CSSpecIdNumArray; // capns:ms:num-array.v1
FOUNDATION_EXPORT NSString * const CSSpecIdBoolArray;// capns:ms:bool-array.v1
FOUNDATION_EXPORT NSString * const CSSpecIdObjArray; // capns:ms:obj-array.v1
FOUNDATION_EXPORT NSString * const CSSpecIdBinary;   // capns:ms:binary.v1

/**
 * A parsed MediaSpec value
 */
@interface CSMediaSpec : NSObject

/// The MIME content type (e.g., "application/json", "image/png")
@property (nonatomic, readonly) NSString *contentType;

/// Optional profile URL
@property (nonatomic, readonly, nullable) NSString *profile;

/// Optional JSON Schema for local validation
@property (nonatomic, readonly, nullable) NSDictionary *schema;

/**
 * Parse a media_spec string in canonical format
 * Format: `<media-type>; profile=<url>` (NO content-type: prefix)
 *
 * IMPORTANT: Legacy "content-type:" prefix is NOT supported and will FAIL HARD
 *
 * @param string The media_spec string
 * @param error Error if parsing fails
 * @return A new CSMediaSpec instance or nil if invalid
 */
+ (nullable instancetype)parse:(NSString *)string error:(NSError * _Nullable * _Nullable)error;

/**
 * Create a MediaSpec from content type, optional profile, and optional schema
 * @param contentType The MIME content type
 * @param profile Optional profile URL
 * @param schema Optional JSON Schema for local validation
 * @return A new CSMediaSpec instance
 */
+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema;

/**
 * Create a MediaSpec from content type and optional profile (no schema)
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
 * Format: <media-type>; profile="<url>" (no content-type: prefix)
 * @return The media_spec as a string
 */
- (NSString *)toString;

@end

// ============================================================================
// SPEC ID RESOLUTION
// ============================================================================

/**
 * Resolve a spec ID to a MediaSpec
 *
 * Resolution algorithm:
 * 1. Look up spec_id in mediaSpecs table
 * 2. If not found AND spec_id is a known built-in (capns:ms:*): use built-in definition
 * 3. If not found and not a built-in: FAIL HARD
 *
 * @param specId The spec ID (e.g., "capns:ms:str.v1")
 * @param mediaSpecs The mediaSpecs lookup table (can be nil)
 * @param error Error if spec ID cannot be resolved
 * @return The resolved MediaSpec or nil on error
 */
CSMediaSpec * _Nullable CSResolveSpecId(NSString *specId,
                                        NSDictionary * _Nullable mediaSpecs,
                                        NSError * _Nullable * _Nullable error);

/**
 * Check if a spec ID is a known built-in
 * @param specId The spec ID to check
 * @return YES if built-in
 */
BOOL CSIsBuiltinSpecId(NSString *specId);

/**
 * Get the canonical media spec string for a built-in spec ID
 * @param specId The built-in spec ID
 * @return The canonical media spec string or nil if not built-in
 */
NSString * _Nullable CSGetBuiltinSpecDefinition(NSString *specId);

/**
 * Helper functions for working with MediaSpec in CapUrn
 */
@interface CSMediaSpec (CapUrn)

/**
 * Extract MediaSpec from a CapUrn's 'out' tag (which now contains a spec ID)
 * @param capUrn The cap URN to extract from
 * @param mediaSpecs The mediaSpecs lookup table for resolution (can be nil)
 * @param error Error if spec ID not found or resolution fails
 * @return The resolved MediaSpec or nil if not found
 */
+ (nullable instancetype)fromCapUrn:(CSCapUrn *)capUrn
                         mediaSpecs:(NSDictionary * _Nullable)mediaSpecs
                              error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
