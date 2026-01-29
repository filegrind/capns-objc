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
@class CSMediaValidation;

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
FOUNDATION_EXPORT NSString * const CSMediaString;       // media:textable;form=scalar
FOUNDATION_EXPORT NSString * const CSMediaInteger;      // media:integer;textable;numeric;form=scalar
FOUNDATION_EXPORT NSString * const CSMediaNumber;       // media:textable;numeric;form=scalar
FOUNDATION_EXPORT NSString * const CSMediaBoolean;      // media:bool;textable;form=scalar
FOUNDATION_EXPORT NSString * const CSMediaObject;       // media:form=map;textable
FOUNDATION_EXPORT NSString * const CSMediaStringArray;  // media:textable;form=list
FOUNDATION_EXPORT NSString * const CSMediaIntegerArray; // media:integer;textable;numeric;form=list
FOUNDATION_EXPORT NSString * const CSMediaNumberArray;  // media:textable;numeric;form=list
FOUNDATION_EXPORT NSString * const CSMediaBooleanArray; // media:bool;textable;form=list
FOUNDATION_EXPORT NSString * const CSMediaObjectArray;  // media:form=list;textable
FOUNDATION_EXPORT NSString * const CSMediaBinary;       // media:bytes
FOUNDATION_EXPORT NSString * const CSMediaVoid;         // media:void
// Semantic content types
FOUNDATION_EXPORT NSString * const CSMediaImage;        // media:image;png;bytes
FOUNDATION_EXPORT NSString * const CSMediaAudio;        // media:wav;audio;bytes;
FOUNDATION_EXPORT NSString * const CSMediaVideo;        // media:video;bytes
// Semantic AI input types
FOUNDATION_EXPORT NSString * const CSMediaAudioSpeech;           // media:audio;wav;bytes;speech
FOUNDATION_EXPORT NSString * const CSMediaImageThumbnail;        // media:image;png;bytes;thumbnail
// Document types (PRIMARY naming - type IS the format)
FOUNDATION_EXPORT NSString * const CSMediaPdf;          // media:pdf;bytes
FOUNDATION_EXPORT NSString * const CSMediaEpub;         // media:epub;bytes
// Text format types (PRIMARY naming - type IS the format)
FOUNDATION_EXPORT NSString * const CSMediaMd;           // media:md;textable
FOUNDATION_EXPORT NSString * const CSMediaTxt;          // media:txt;textable
FOUNDATION_EXPORT NSString * const CSMediaRst;          // media:rst;textable
FOUNDATION_EXPORT NSString * const CSMediaLog;          // media:log;textable
FOUNDATION_EXPORT NSString * const CSMediaHtml;         // media:html;textable
FOUNDATION_EXPORT NSString * const CSMediaXml;          // media:xml;textable
FOUNDATION_EXPORT NSString * const CSMediaJson;         // media:json;textable;form=map
FOUNDATION_EXPORT NSString * const CSMediaJsonSchema;   // media:json;json-schema;textable;form=map
FOUNDATION_EXPORT NSString * const CSMediaYaml;         // media:yaml;textable;form=map
// Semantic input types
FOUNDATION_EXPORT NSString * const CSMediaModelSpec;    // media:model-spec;textable;form=scalar
FOUNDATION_EXPORT NSString * const CSMediaModelRepo;    // media:model-repo;textable;form=map
// Semantic output types
FOUNDATION_EXPORT NSString * const CSMediaModelDim;     // media:model-dim;integer;textable;numeric;form=scalar
FOUNDATION_EXPORT NSString * const CSMediaDecision;     // media:decision;bool;textable;form=scalar
FOUNDATION_EXPORT NSString * const CSMediaDecisionArray;// media:decision;bool;textable;form=list

// ============================================================================
// SCHEMA URL CONFIGURATION
// ============================================================================

/**
 * Get the schema base URL from environment variables or default
 *
 * Checks in order:
 * 1. CAPNS_SCHEMA_BASE_URL environment variable
 * 2. CAPNS_REGISTRY_URL environment variable + "/schema"
 * 3. Default: "https://capns.org/schema"
 */
FOUNDATION_EXPORT NSString *CSGetSchemaBaseURL(void);

/**
 * Get a profile URL for the given profile name
 *
 * @param profileName The profile name (e.g., "string", "integer")
 * @return The full profile URL
 */
FOUNDATION_EXPORT NSString *CSGetProfileURL(NSString *profileName);

// ============================================================================
// MEDIA SPEC PARSING
// ============================================================================

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

/// Optional validation rules (inherent to the semantic type)
@property (nonatomic, readonly, nullable) CSMediaValidation *validation;

/// Optional metadata (arbitrary key-value pairs for display/categorization)
@property (nonatomic, readonly, nullable) NSDictionary *metadata;

/// The media URN this spec was resolved from (if resolved via CSResolveMediaUrn)
@property (nonatomic, readonly, nullable) NSString *mediaUrn;

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
 * Create a MediaSpec with all properties
 * @param contentType The MIME content type
 * @param profile Optional profile URL
 * @param schema Optional JSON Schema for local validation
 * @param title Optional display-friendly title
 * @param descriptionText Optional description
 * @param validation Optional validation rules
 * @param metadata Optional metadata dictionary
 * @return A new CSMediaSpec instance
 */
+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema
                          title:(nullable NSString *)title
                descriptionText:(nullable NSString *)descriptionText
                     validation:(nullable CSMediaValidation *)validation
                       metadata:(nullable NSDictionary *)metadata;

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
 * @return YES if bytes marker tag is present
 */
- (BOOL)isBinary;

/**
 * Check if this media spec represents a map/object structure (form=map)
 * @return YES if form=map tag is present
 */
- (BOOL)isMap;

/**
 * Check if this media spec represents a scalar value (form=scalar)
 * @return YES if form=scalar tag is present
 */
- (BOOL)isScalar;

/**
 * Check if this media spec represents a list/array structure (form=list)
 * @return YES if form=list tag is present
 */
- (BOOL)isList;

/**
 * Check if this media spec represents structured data (map or list)
 * Structured data can be serialized as JSON when transmitted as text.
 * Note: This does NOT check for the explicit `json` tag - use isJSON for that.
 * @return YES if structured (map or list)
 */
- (BOOL)isStructured;

/**
 * Check if this media spec represents JSON representation
 * Note: This only checks for explicit JSON format marker.
 * For checking if data is structured (map/list), use isStructured.
 * @return YES if json marker tag is present
 */
- (BOOL)isJSON;

/**
 * Check if this media spec represents text output
 * @return YES if textable marker tag is present
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
 * 2. If not found AND media URN is a known built-in (media:*): use built-in definition
 * 3. If not found and not a built-in: FAIL HARD
 *
 * @param mediaUrn The media URN (e.g., "media:string")
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
