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
    CSMediaSpecErrorUnresolvableMediaUrn = 4
};

// ============================================================================
// BUILT-IN MEDIA URN CONSTANTS
// ============================================================================

/// Well-known built-in media URNs with coercion tags - these do not need to be declared in mediaSpecs
FOUNDATION_EXPORT NSString * const CSMediaString;       // media:type=string;v=1;textable;scalar
FOUNDATION_EXPORT NSString * const CSMediaInteger;      // media:type=integer;v=1;textable;numeric;scalar
FOUNDATION_EXPORT NSString * const CSMediaNumber;       // media:type=number;v=1;textable;numeric;scalar
FOUNDATION_EXPORT NSString * const CSMediaBoolean;      // media:type=boolean;v=1;textable;scalar
FOUNDATION_EXPORT NSString * const CSMediaObject;       // media:type=object;v=1;textable;keyed
FOUNDATION_EXPORT NSString * const CSMediaStringArray;  // media:type=string-array;v=1;textable;sequence
FOUNDATION_EXPORT NSString * const CSMediaIntegerArray; // media:type=integer-array;v=1;textable;numeric;sequence
FOUNDATION_EXPORT NSString * const CSMediaNumberArray;  // media:type=number-array;v=1;textable;numeric;sequence
FOUNDATION_EXPORT NSString * const CSMediaBooleanArray; // media:type=boolean-array;v=1;textable;sequence
FOUNDATION_EXPORT NSString * const CSMediaObjectArray;  // media:type=object-array;v=1;textable;keyed;sequence
FOUNDATION_EXPORT NSString * const CSMediaBinary;       // media:type=raw;v=1;binary
FOUNDATION_EXPORT NSString * const CSMediaVoid;         // media:type=void;v=1
// Semantic content types
FOUNDATION_EXPORT NSString * const CSMediaImage;        // media:type=png;v=1;binary
FOUNDATION_EXPORT NSString * const CSMediaAudio;        // media:type=wav;audio;binary;v=1;
FOUNDATION_EXPORT NSString * const CSMediaVideo;        // media:type=video;v=1;binary
FOUNDATION_EXPORT NSString * const CSMediaText;         // media:type=text;v=1;textable
// Document types (PRIMARY naming - type IS the format)
FOUNDATION_EXPORT NSString * const CSMediaPdf;          // media:type=pdf;v=1;binary
FOUNDATION_EXPORT NSString * const CSMediaEpub;         // media:type=epub;v=1;binary
// Text format types (PRIMARY naming - type IS the format)
FOUNDATION_EXPORT NSString * const CSMediaMd;           // media:type=md;v=1;textable
FOUNDATION_EXPORT NSString * const CSMediaTxt;          // media:type=txt;v=1;textable
FOUNDATION_EXPORT NSString * const CSMediaRst;          // media:type=rst;v=1;textable
FOUNDATION_EXPORT NSString * const CSMediaLog;          // media:type=log;v=1;textable
FOUNDATION_EXPORT NSString * const CSMediaHtml;         // media:type=html;v=1;textable
FOUNDATION_EXPORT NSString * const CSMediaXml;          // media:type=xml;v=1;textable
FOUNDATION_EXPORT NSString * const CSMediaJson;         // media:type=json;v=1;textable;keyed
FOUNDATION_EXPORT NSString * const CSMediaYaml;         // media:type=yaml;v=1;textable;keyed

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

/// Optional display-friendly title
@property (nonatomic, readonly, nullable) NSString *title;

/// Optional description
@property (nonatomic, readonly, nullable) NSString *descriptionText;

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
// MEDIA URN RESOLUTION
// ============================================================================

/**
 * Resolve a media URN to a MediaSpec
 *
 * Resolution algorithm:
 * 1. Look up media URN in mediaSpecs table
 * 2. If not found AND media URN is a known built-in (media:type=*): use built-in definition
 * 3. If not found and not a built-in: FAIL HARD
 *
 * @param mediaUrn The media URN (e.g., "media:type=string;v=1")
 * @param mediaSpecs The mediaSpecs lookup table (can be nil)
 * @param error Error if media URN cannot be resolved
 * @return The resolved MediaSpec or nil on error
 */
CSMediaSpec * _Nullable CSResolveMediaUrn(NSString *mediaUrn,
                                          NSDictionary * _Nullable mediaSpecs,
                                          NSError * _Nullable * _Nullable error);

/**
 * Check if a media URN is a known built-in
 * @param mediaUrn The media URN to check
 * @return YES if built-in
 */
BOOL CSIsBuiltinMediaUrn(NSString *mediaUrn);

/**
 * Get the canonical media spec string for a built-in media URN
 * @param mediaUrn The built-in media URN
 * @return The canonical media spec string or nil if not built-in
 */
NSString * _Nullable CSGetBuiltinMediaUrnDefinition(NSString *mediaUrn);

/**
 * Check if a media URN satisfies another media URN's requirements.
 * Used for cap matching - checks if a provided media type can satisfy a cap's input requirement.
 *
 * Matching rules:
 * - Type must match (e.g., "image" != "binary")
 * - Extension must match if specified in requirement
 * - Version must match if specified in requirement
 *
 * @param providedUrn The media URN being provided (e.g., from a listing)
 * @param requirementUrn The media URN required (e.g., from a cap's input spec)
 * @return YES if providedUrn satisfies requirementUrn
 */
BOOL CSMediaUrnSatisfies(NSString *providedUrn, NSString *requirementUrn);

/**
 * Helper functions for working with MediaSpec in CapUrn
 */
@interface CSMediaSpec (CapUrn)

/**
 * Extract MediaSpec from a CapUrn's 'out' tag (which now contains a media URN)
 * @param capUrn The cap URN to extract from
 * @param mediaSpecs The mediaSpecs lookup table for resolution (can be nil)
 * @param error Error if media URN not found or resolution fails
 * @return The resolved MediaSpec or nil if not found
 */
+ (nullable instancetype)fromCapUrn:(CSCapUrn *)capUrn
                         mediaSpecs:(NSDictionary * _Nullable)mediaSpecs
                              error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
