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
#import "CSMediaUrn.h"

@class CSCapUrn;
@class CSMediaValidation;

NS_ASSUME_NONNULL_BEGIN

/// Error domain for MediaSpec errors
FOUNDATION_EXPORT NSErrorDomain const CSMediaSpecErrorDomain;

/// Error codes for MediaSpec operations
typedef NS_ERROR_ENUM(CSMediaSpecErrorDomain, CSMediaSpecError) {
    CSMediaSpecErrorUnresolvableMediaUrn = 1,
    CSMediaSpecErrorDuplicateMediaUrn = 2
};

// ============================================================================
// BUILT-IN MEDIA URN CONSTANTS
// ============================================================================

/// Well-known built-in media URNs with coercion tags - these do not need to be declared in mediaSpecs
FOUNDATION_EXPORT NSString * const CSMediaString;       // media:textable
FOUNDATION_EXPORT NSString * const CSMediaInteger;      // media:integer;textable;numeric
FOUNDATION_EXPORT NSString * const CSMediaNumber;       // media:textable;numeric
FOUNDATION_EXPORT NSString * const CSMediaBoolean;      // media:bool;textable
FOUNDATION_EXPORT NSString * const CSMediaObject;       // media:record
FOUNDATION_EXPORT NSString * const CSMediaStringArray;  // media:list;textable
FOUNDATION_EXPORT NSString * const CSMediaIntegerArray; // media:integer;list;textable;numeric
FOUNDATION_EXPORT NSString * const CSMediaNumberArray;  // media:list;textable;numeric
FOUNDATION_EXPORT NSString * const CSMediaBooleanArray; // media:bool;list;textable
FOUNDATION_EXPORT NSString * const CSMediaObjectArray;  // media:list;record
FOUNDATION_EXPORT NSString * const CSMediaBinary;       // media:
FOUNDATION_EXPORT NSString * const CSMediaVoid;         // media:void
// Semantic content types
FOUNDATION_EXPORT NSString * const CSMediaPng;          // media:image;png
FOUNDATION_EXPORT NSString * const CSMediaImage;        // media:image;png (alias for CSMediaPng)
FOUNDATION_EXPORT NSString * const CSMediaAudio;        // media:wav;audio
FOUNDATION_EXPORT NSString * const CSMediaVideo;        // media:video
// Semantic AI input types
FOUNDATION_EXPORT NSString * const CSMediaAudioSpeech;           // media:audio;wav;speech
FOUNDATION_EXPORT NSString * const CSMediaImageThumbnail;        // media:image;png;thumbnail
// Document types (PRIMARY naming - type IS the format)
FOUNDATION_EXPORT NSString * const CSMediaPdf;          // media:pdf
FOUNDATION_EXPORT NSString * const CSMediaEpub;         // media:epub
// Text format types (PRIMARY naming - type IS the format)
FOUNDATION_EXPORT NSString * const CSMediaMd;           // media:md;textable
FOUNDATION_EXPORT NSString * const CSMediaTxt;          // media:txt;textable
FOUNDATION_EXPORT NSString * const CSMediaRst;          // media:rst;textable
FOUNDATION_EXPORT NSString * const CSMediaLog;          // media:log;textable
FOUNDATION_EXPORT NSString * const CSMediaHtml;         // media:html;textable
FOUNDATION_EXPORT NSString * const CSMediaXml;          // media:xml;textable
FOUNDATION_EXPORT NSString * const CSMediaJson;         // media:json;record;textable
FOUNDATION_EXPORT NSString * const CSMediaJsonSchema;   // media:json;json-schema;record;textable
FOUNDATION_EXPORT NSString * const CSMediaYaml;         // media:record;textable;yaml
// Semantic input types
FOUNDATION_EXPORT NSString * const CSMediaModelSpec;    // media:model-spec;textable
FOUNDATION_EXPORT NSString * const CSMediaModelRepo;    // media:model-repo;record;textable
// File path types
FOUNDATION_EXPORT NSString * const CSMediaFilePath;     // media:file-path;textable
FOUNDATION_EXPORT NSString * const CSMediaFilePathArray; // media:file-path;list;textable
// Semantic input types (continued)
FOUNDATION_EXPORT NSString * const CSMediaFrontmatterText; // media:frontmatter;textable
FOUNDATION_EXPORT NSString * const CSMediaMlxModelPath;    // media:mlx-model-path;textable
// Semantic output types
FOUNDATION_EXPORT NSString * const CSMediaImageDescription;   // media:image-description;textable
FOUNDATION_EXPORT NSString * const CSMediaModelDim;        // media:integer;model-dim;numeric;textable
FOUNDATION_EXPORT NSString * const CSMediaDownloadOutput;  // media:download-result;record;textable
FOUNDATION_EXPORT NSString * const CSMediaListOutput;      // media:model-list;record;textable
FOUNDATION_EXPORT NSString * const CSMediaStatusOutput;    // media:model-status;record;textable
FOUNDATION_EXPORT NSString * const CSMediaContentsOutput;  // media:model-contents;record;textable
FOUNDATION_EXPORT NSString * const CSMediaAvailabilityOutput; // media:model-availability;record;textable
FOUNDATION_EXPORT NSString * const CSMediaPathOutput;      // media:model-path;record;textable
FOUNDATION_EXPORT NSString * const CSMediaEmbeddingVector; // media:embedding-vector;record;textable
FOUNDATION_EXPORT NSString * const CSMediaLlmInferenceOutput; // media:generated-text;record;textable
FOUNDATION_EXPORT NSString * const CSMediaFileMetadata;    // media:file-metadata;record;textable
FOUNDATION_EXPORT NSString * const CSMediaDocumentOutline; // media:document-outline;record;textable
FOUNDATION_EXPORT NSString * const CSMediaDisboundPage;    // media:disbound-page;list;textable
FOUNDATION_EXPORT NSString * const CSMediaCaptionOutput;   // media:image-caption;record;textable
FOUNDATION_EXPORT NSString * const CSMediaTranscriptionOutput; // media:record;textable;transcription
FOUNDATION_EXPORT NSString * const CSMediaDecision;        // media:bool;decision;textable
FOUNDATION_EXPORT NSString * const CSMediaDecisionArray;   // media:bool;decision;list;textable

// ============================================================================
// STANDARD CAP URN CONSTANTS
// ============================================================================

/// Standard echo capability URN
/// Accepts any media type as input and outputs any media type
FOUNDATION_EXPORT NSString * const CSCapIdentity;           // cap:in=media:;out=media:

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
 * A resolved MediaSpec value
 */
@interface CSMediaSpec : NSObject

/// The media URN identifier (e.g., "media:pdf")
@property (nonatomic, readonly, nullable) NSString *mediaUrn;

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

/// File extensions for storing this media type (e.g., @[@"pdf"], @[@"jpg", @"jpeg"])
@property (nonatomic, readonly) NSArray<NSString *> *extensions;

/**
 * Create a MediaSpec with all properties
 * @param contentType The MIME content type
 * @param profile Optional profile URL
 * @param schema Optional JSON Schema for local validation
 * @param title Optional display-friendly title
 * @param descriptionText Optional description
 * @param validation Optional validation rules
 * @param metadata Optional metadata dictionary
 * @param extensions File extensions for storing this media type (can be empty array)
 * @return A new CSMediaSpec instance
 */
+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema
                          title:(nullable NSString *)title
                descriptionText:(nullable NSString *)descriptionText
                     validation:(nullable CSMediaValidation *)validation
                       metadata:(nullable NSDictionary *)metadata
                     extensions:(NSArray<NSString *> *)extensions;

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
 * @return YES if textable marker tag is absent
 */
- (BOOL)isBinary;

/**
 * Check if this media spec represents a record (has record marker tag)
 * A record has internal key-value structure (e.g., JSON object).
 * @return YES if record marker tag is present
 */
- (BOOL)isRecord;

/**
 * Check if this media spec is opaque (no record marker tag)
 * Opaque is the default structure - no internal fields recognized.
 * @return YES if opaque (no record marker)
 */
- (BOOL)isOpaque;

/**
 * Check if this media spec represents a scalar value (no list marker tag)
 * Scalar is the default cardinality.
 * @return YES if scalar (no list marker)
 */
- (BOOL)isScalar;

/**
 * Check if this media spec represents a list/array structure (has list marker tag)
 * @return YES if list marker tag is present
 */
- (BOOL)isList;

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
 * 1. Iterate mediaSpecs array and find by URN
 * 2. If not found: FAIL HARD
 *
 * @param mediaUrn The media URN (e.g., "media:textable;form=scalar")
 * @param mediaSpecs The mediaSpecs array (can be nil)
 * @param error Error if media URN cannot be resolved
 * @return The resolved MediaSpec or nil on error
 */
CSMediaSpec * _Nullable CSResolveMediaUrn(NSString *mediaUrn,
                                          NSArray<NSDictionary *> * _Nullable mediaSpecs,
                                          NSError * _Nullable * _Nullable error);

/**
 * Validate that there are no duplicate URNs in mediaSpecs array
 *
 * @param mediaSpecs The mediaSpecs array to validate
 * @param error Error if duplicate URNs are found
 * @return YES if no duplicates, NO if duplicates found
 */
BOOL CSValidateNoMediaSpecDuplicates(NSArray<NSDictionary *> * _Nullable mediaSpecs,
                                     NSError * _Nullable * _Nullable error);

/**
 * Check if a media URN represents binary data by checking absence of 'textable' tag.
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN does not have the 'textable' marker tag
 */
BOOL CSMediaUrnIsBinary(NSString *mediaUrn);

/**
 * Check if a media URN represents text data by checking for 'textable' tag.
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'textable' marker tag
 */
BOOL CSMediaUrnIsText(NSString *mediaUrn);

/**
 * Check if a media URN represents JSON data by checking for 'json' tag.
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'json' marker tag
 */
BOOL CSMediaUrnIsJson(NSString *mediaUrn);

/**
 * Check if a media URN represents a list/array (has list marker tag).
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has list marker tag
 */
BOOL CSMediaUrnIsList(NSString *mediaUrn);

/**
 * Check if a media URN represents a record (has record marker tag).
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has record marker tag
 */
BOOL CSMediaUrnIsRecord(NSString *mediaUrn);

/**
 * Check if a media URN is opaque (no record marker tag).
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has no record marker (opaque is default)
 */
BOOL CSMediaUrnIsOpaque(NSString *mediaUrn);

/**
 * Check if a media URN represents a scalar value (no list marker tag).
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has no list marker (scalar is default)
 */
BOOL CSMediaUrnIsScalar(NSString *mediaUrn);

/**
 * Check if a media URN represents image data by checking for 'image' tag.
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'image' marker tag
 */
BOOL CSMediaUrnIsImage(NSString *mediaUrn);

/**
 * Check if a media URN represents audio data by checking for 'audio' tag.
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'audio' marker tag
 */
BOOL CSMediaUrnIsAudio(NSString *mediaUrn);

/**
 * Check if a media URN represents video data by checking for 'video' tag.
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'video' marker tag
 */
BOOL CSMediaUrnIsVideo(NSString *mediaUrn);

/**
 * Check if a media URN represents numeric data by checking for 'numeric' tag.
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'numeric' marker tag
 */
BOOL CSMediaUrnIsNumeric(NSString *mediaUrn);

/**
 * Check if a media URN represents boolean data by checking for 'bool' tag.
 * This is a pure syntax check - no resolution required.
 * @param mediaUrn The media URN to check (must be non-empty)
 * @return YES if the media URN has the 'bool' marker tag
 */
BOOL CSMediaUrnIsBool(NSString *mediaUrn);

/**
 * Helper functions for working with MediaSpec in CapUrn
 */
@interface CSMediaSpec (CapUrn)

/**
 * Extract MediaSpec from a CapUrn's 'out' tag (which now contains a media URN)
 * @param capUrn The cap URN to extract from
 * @param mediaSpecs The mediaSpecs array for resolution (can be nil)
 * @param error Error if media URN not found or resolution fails
 * @return The resolved MediaSpec or nil if not found
 */
+ (nullable instancetype)fromCapUrn:(CSCapUrn *)capUrn
                         mediaSpecs:(NSArray<NSDictionary *> * _Nullable)mediaSpecs
                              error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
