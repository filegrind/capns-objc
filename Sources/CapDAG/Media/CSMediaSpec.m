//
//  CSMediaSpec.m
//  MediaSpec parsing and handling
//

#import "CSMediaSpec.h"
#import "CSCapUrn.h"
#import "CSCap.h"
#import "CSMediaUrn.h"
@import TaggedUrn;

NSErrorDomain const CSMediaSpecErrorDomain = @"CSMediaSpecErrorDomain";

// ============================================================================
// BUILT-IN MEDIA URN CONSTANTS
// ============================================================================

NSString * const CSMediaString = @"media:textable";
NSString * const CSMediaInteger = @"media:integer;textable;numeric";
NSString * const CSMediaNumber = @"media:textable;numeric";
NSString * const CSMediaBoolean = @"media:bool;textable";
NSString * const CSMediaObject = @"media:record";
NSString * const CSMediaStringArray = @"media:list;textable";
NSString * const CSMediaIntegerArray = @"media:integer;list;textable;numeric";
NSString * const CSMediaNumberArray = @"media:list;textable;numeric";
NSString * const CSMediaBooleanArray = @"media:bool;list;textable";
NSString * const CSMediaObjectArray = @"media:list;record";
NSString * const CSMediaBinary = @"media:";
NSString * const CSMediaVoid = @"media:void";
// Semantic content types
NSString * const CSMediaPng = @"media:image;png";
NSString * const CSMediaImage = @"media:image;png"; // alias for CSMediaPng
NSString * const CSMediaAudio = @"media:wav;audio";
NSString * const CSMediaVideo = @"media:video";
// Semantic AI input types
NSString * const CSMediaAudioSpeech = @"media:audio;wav;speech";
NSString * const CSMediaImageThumbnail = @"media:image;png;thumbnail";
// Document types (PRIMARY naming - type IS the format)
NSString * const CSMediaPdf = @"media:pdf";
NSString * const CSMediaEpub = @"media:epub";
// Text format types (PRIMARY naming - type IS the format)
NSString * const CSMediaMd = @"media:md;textable";
NSString * const CSMediaTxt = @"media:txt;textable";
NSString * const CSMediaRst = @"media:rst;textable";
NSString * const CSMediaLog = @"media:log;textable";
NSString * const CSMediaHtml = @"media:html;textable";
NSString * const CSMediaXml = @"media:xml;textable";
NSString * const CSMediaJson = @"media:json;record;textable";
NSString * const CSMediaJsonSchema = @"media:json;json-schema;record;textable";
NSString * const CSMediaYaml = @"media:record;textable;yaml";
// Semantic input types
NSString * const CSMediaModelSpec = @"media:model-spec;textable";
NSString * const CSMediaModelRepo = @"media:model-repo;record;textable";
// File path types
NSString * const CSMediaFilePath = @"media:file-path;textable";
NSString * const CSMediaFilePathArray = @"media:file-path;list;textable";
// Semantic input types (continued)
NSString * const CSMediaFrontmatterText = @"media:frontmatter;textable";
NSString * const CSMediaMlxModelPath = @"media:mlx-model-path;textable";
// Semantic output types
NSString * const CSMediaImageDescription = @"media:image-description;textable";
NSString * const CSMediaModelDim = @"media:integer;model-dim;numeric;textable";
NSString * const CSMediaDownloadOutput = @"media:download-result;record;textable";
NSString * const CSMediaListOutput = @"media:model-list;record;textable";
NSString * const CSMediaStatusOutput = @"media:model-status;record;textable";
NSString * const CSMediaContentsOutput = @"media:model-contents;record;textable";
NSString * const CSMediaAvailabilityOutput = @"media:model-availability;record;textable";
NSString * const CSMediaPathOutput = @"media:model-path;record;textable";
NSString * const CSMediaEmbeddingVector = @"media:embedding-vector;record;textable";
NSString * const CSMediaLlmInferenceOutput = @"media:generated-text;record;textable";
NSString * const CSMediaFileMetadata = @"media:file-metadata;record;textable";
NSString * const CSMediaDocumentOutline = @"media:document-outline;record;textable";
NSString * const CSMediaDisboundPage = @"media:disbound-page;list;textable";
NSString * const CSMediaCaptionOutput = @"media:image-caption;record;textable";
NSString * const CSMediaTranscriptionOutput = @"media:record;textable;transcription";
NSString * const CSMediaDecision = @"media:bool;decision;textable";
NSString * const CSMediaDecisionArray = @"media:bool;decision;list;textable";

// ============================================================================
// SCHEMA URL CONFIGURATION
// ============================================================================

static NSString * const CSDefaultSchemaBase = @"https://capdag.com/schema";

/**
 * Get the schema base URL from environment variables or default
 *
 * Checks in order:
 * 1. CAPDAG_SCHEMA_BASE_URL environment variable
 * 2. CAPDAG_REGISTRY_URL environment variable + "/schema"
 * 3. Default: "https://capdag.com/schema"
 */
NSString *CSGetSchemaBaseURL(void) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];

    NSString *schemaURL = env[@"CAPDAG_SCHEMA_BASE_URL"];
    if (schemaURL.length > 0) {
        return schemaURL;
    }

    NSString *registryURL = env[@"CAPDAG_REGISTRY_URL"];
    if (registryURL.length > 0) {
        return [registryURL stringByAppendingString:@"/schema"];
    }

    return CSDefaultSchemaBase;
}

/**
 * Get a profile URL for the given profile name
 *
 * @param profileName The profile name (e.g., "string", "integer")
 * @return The full profile URL
 */
NSString *CSGetProfileURL(NSString *profileName) {
    return [NSString stringWithFormat:@"%@/%@", CSGetSchemaBaseURL(), profileName];
}

// ============================================================================
// BUILTIN MEDIA URN DEFINITIONS
// ============================================================================

// ============================================================================
// MEDIA SPEC IMPLEMENTATION
// ============================================================================

@interface CSMediaSpec ()
@property (nonatomic, readwrite) NSString *contentType;
@property (nonatomic, readwrite, nullable) NSString *profile;
@property (nonatomic, readwrite, nullable) NSDictionary *schema;
@property (nonatomic, readwrite, nullable) NSString *title;
@property (nonatomic, readwrite, nullable) NSString *descriptionText;
@property (nonatomic, readwrite, nullable) NSString *mediaUrn;
@property (nonatomic, readwrite, nullable) CSMediaValidation *validation;
@property (nonatomic, readwrite, nullable) NSDictionary *metadata;
@property (nonatomic, readwrite) NSArray<NSString *> *extensions;
@end

/// Helper to check if a media URN has a marker tag using CSTaggedUrn.
/// Requires a valid, non-empty media URN - fails hard otherwise.
/// Nil/empty/whitespace validation is handled by CSTaggedUrn.
static BOOL CSMediaUrnHasTag(NSString *mediaUrn, NSString *tagName) {
    NSError *error = nil;
    CSTaggedUrn *parsed = [CSTaggedUrn fromString:mediaUrn error:&error];
    if (parsed == nil || error != nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Failed to parse media URN '%@': %@ - this indicates the CSMediaSpec was not resolved via CSResolveMediaUrn", mediaUrn, error.localizedDescription];
    }
    return [parsed getTag:tagName] != nil;
}

/// Helper to check if a media URN has a marker tag (tag value is "*").
/// Requires a valid, non-empty media URN - fails hard otherwise.
/// Nil/empty/whitespace validation is handled by CSTaggedUrn.
static BOOL CSMediaUrnHasMarkerTag(NSString *mediaUrn, NSString *tagName) {
    NSError *error = nil;
    CSTaggedUrn *parsed = [CSTaggedUrn fromString:mediaUrn error:&error];
    if (parsed == nil || error != nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Failed to parse media URN '%@': %@ - this indicates the CSMediaSpec was not resolved via CSResolveMediaUrn", mediaUrn, error.localizedDescription];
    }
    NSString *value = [parsed getTag:tagName];
    return value != nil && [value isEqualToString:@"*"];
}

/// Public function to check if a media URN represents binary data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsBinary(NSString *mediaUrn) {
    return !CSMediaUrnHasTag(mediaUrn, @"textable");
}

/// Public function to check if a media URN represents text data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsText(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"textable");
}

/// Public function to check if a media URN represents JSON data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsJson(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"json");
}

/// Public function to check if a media URN represents a list (has list marker tag).
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsList(NSString *mediaUrn) {
    return CSMediaUrnHasMarkerTag(mediaUrn, @"list");
}

/// Public function to check if a media URN represents a record (has record marker tag).
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsRecord(NSString *mediaUrn) {
    return CSMediaUrnHasMarkerTag(mediaUrn, @"record");
}

/// Public function to check if a media URN is opaque (no record marker tag).
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsOpaque(NSString *mediaUrn) {
    return !CSMediaUrnHasMarkerTag(mediaUrn, @"record");
}

/// Public function to check if a media URN represents a scalar (no list marker tag).
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsScalar(NSString *mediaUrn) {
    return !CSMediaUrnHasMarkerTag(mediaUrn, @"list");
}

/// Public function to check if a media URN represents image data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsImage(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"image");
}

/// Public function to check if a media URN represents audio data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsAudio(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"audio");
}

/// Public function to check if a media URN represents video data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsVideo(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"video");
}

/// Public function to check if a media URN represents numeric data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsNumeric(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"numeric");
}

/// Public function to check if a media URN represents boolean data.
/// Validation is handled by CSTaggedUrn.
BOOL CSMediaUrnIsBool(NSString *mediaUrn) {
    return CSMediaUrnHasTag(mediaUrn, @"bool");
}

@implementation CSMediaSpec

+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema {
    return [self withContentType:contentType profile:profile schema:schema title:nil descriptionText:nil];
}

+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema
                          title:(nullable NSString *)title
                descriptionText:(nullable NSString *)descriptionText {
    return [self withContentType:contentType profile:profile schema:schema title:title descriptionText:descriptionText validation:nil];
}

+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema
                          title:(nullable NSString *)title
                descriptionText:(nullable NSString *)descriptionText
                     validation:(nullable CSMediaValidation *)validation {
    return [self withContentType:contentType profile:profile schema:schema title:title descriptionText:descriptionText validation:validation metadata:nil extensions:@[]];
}

+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema
                          title:(nullable NSString *)title
                descriptionText:(nullable NSString *)descriptionText
                     validation:(nullable CSMediaValidation *)validation
                       metadata:(nullable NSDictionary *)metadata
                     extensions:(NSArray<NSString *> *)extensions {
    CSMediaSpec *spec = [[CSMediaSpec alloc] init];
    spec.contentType = contentType;
    spec.profile = profile;
    spec.schema = schema;
    spec.title = title;
    spec.descriptionText = descriptionText;
    spec.validation = validation;
    spec.metadata = metadata;
    spec.extensions = extensions ?: @[];
    return spec;
}

+ (instancetype)withContentType:(NSString *)contentType profile:(nullable NSString *)profile {
    return [self withContentType:contentType profile:profile schema:nil];
}

- (BOOL)isBinary {
    return !CSMediaUrnHasTag(self.mediaUrn, @"textable");
}

- (BOOL)isRecord {
    return CSMediaUrnHasMarkerTag(self.mediaUrn, @"record");
}

- (BOOL)isOpaque {
    return !CSMediaUrnHasMarkerTag(self.mediaUrn, @"record");
}

- (BOOL)isScalar {
    return !CSMediaUrnHasMarkerTag(self.mediaUrn, @"list");
}

- (BOOL)isList {
    return CSMediaUrnHasMarkerTag(self.mediaUrn, @"list");
}

- (BOOL)isJSON {
    return CSMediaUrnHasTag(self.mediaUrn, @"json");
}

- (BOOL)isText {
    return CSMediaUrnHasTag(self.mediaUrn, @"textable");
}

- (NSString *)primaryType {
    NSArray<NSString *> *parts = [self.contentType componentsSeparatedByString:@"/"];
    return [parts firstObject] ?: self.contentType;
}

- (nullable NSString *)subtype {
    NSArray<NSString *> *parts = [self.contentType componentsSeparatedByString:@"/"];
    if (parts.count > 1) {
        return parts[1];
    }
    return nil;
}

- (NSString *)toString {
    // Canonical format: <media-type>; profile="<url>" (no content-type: prefix)
    if (self.profile) {
        return [NSString stringWithFormat:@"%@; profile=\"%@\"", self.contentType, self.profile];
    }
    return self.contentType;
}

- (NSString *)description {
    return [self toString];
}

@end

// ============================================================================
// MEDIA URN RESOLUTION
// ============================================================================

CSMediaSpec * _Nullable CSResolveMediaUrn(NSString *mediaUrn,
                                          NSArray<NSDictionary *> * _Nullable mediaSpecs,
                                          NSError * _Nullable * _Nullable error) {
    // Find in the provided media_specs array
    if (mediaSpecs) {
        for (NSDictionary *def in mediaSpecs) {
            NSString *urn = def[@"urn"];
            if (urn && [urn isEqualToString:mediaUrn]) {
                // Object form: { urn, media_type, profile_uri?, schema?, title?, description?, validation?, metadata?, extensions? }
                NSString *mediaType = def[@"media_type"] ?: def[@"mediaType"];
                NSString *profileUri = def[@"profile_uri"] ?: def[@"profileUri"];
                NSDictionary *schema = def[@"schema"];
                NSString *title = def[@"title"];
                NSString *descriptionText = def[@"description"];

                // Parse validation if present
                CSMediaValidation *validation = nil;
                NSDictionary *validationDict = def[@"validation"];
                if (validationDict && [validationDict isKindOfClass:[NSDictionary class]]) {
                    NSError *validationError = nil;
                    validation = [CSMediaValidation validationWithDictionary:validationDict error:&validationError];
                    // Ignore validation parse errors - validation is optional
                }

                // Extract metadata if present
                NSDictionary *metadata = nil;
                id metadataValue = def[@"metadata"];
                if (metadataValue && [metadataValue isKindOfClass:[NSDictionary class]]) {
                    metadata = (NSDictionary *)metadataValue;
                }

                // Extract extensions array if present
                NSArray<NSString *> *extensions = @[];
                id extensionsValue = def[@"extensions"];
                if (extensionsValue && [extensionsValue isKindOfClass:[NSArray class]]) {
                    extensions = (NSArray<NSString *> *)extensionsValue;
                }

                if (!mediaType) {
                    if (error) {
                        *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                                     code:CSMediaSpecErrorUnresolvableMediaUrn
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Media URN '%@' has invalid object definition: missing media_type", mediaUrn]}];
                    }
                    return nil;
                }

                CSMediaSpec *spec = [CSMediaSpec withContentType:mediaType profile:profileUri schema:schema title:title descriptionText:descriptionText validation:validation metadata:metadata extensions:extensions];
                spec.mediaUrn = mediaUrn;
                return spec;
            }
        }
    }

    // FAIL HARD - media URN must be in mediaSpecs array
    if (error) {
        *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                     code:CSMediaSpecErrorUnresolvableMediaUrn
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Cannot resolve media URN: '%@'. Not found in mediaSpecs array.", mediaUrn]}];
    }
    return nil;
}

// Validate no duplicate URNs in mediaSpecs array
BOOL CSValidateNoMediaSpecDuplicates(NSArray<NSDictionary *> * _Nullable mediaSpecs,
                                     NSError * _Nullable * _Nullable error) {
    if (!mediaSpecs) {
        return YES;
    }

    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *def in mediaSpecs) {
        NSString *urn = def[@"urn"];
        if (urn) {
            if ([seen containsObject:urn]) {
                if (error) {
                    *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                                 code:CSMediaSpecErrorDuplicateMediaUrn
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Duplicate media URN '%@' in mediaSpecs array", urn]}];
                }
                return NO;
            }
            [seen addObject:urn];
        }
    }
    return YES;
}

// ============================================================================
// CAP URN EXTENSION
// ============================================================================

@implementation CSMediaSpec (CapUrn)

+ (nullable instancetype)fromCapUrn:(CSCapUrn *)capUrn
                         mediaSpecs:(NSArray<NSDictionary *> * _Nullable)mediaSpecs
                              error:(NSError * _Nullable * _Nullable)error {
    // Use getOutSpec directly - outSpec is now a required first-class field containing a media URN
    NSString *mediaUrn = [capUrn getOutSpec];

    // Note: Since outSpec is now required, this should never be nil for a valid capUrn
    // But we keep the check for safety
    if (!mediaUrn) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                         code:CSMediaSpecErrorUnresolvableMediaUrn
                                     userInfo:@{NSLocalizedDescriptionKey: @"no 'out' media URN found in cap URN"}];
        }
        return nil;
    }

    // Resolve the media URN to a MediaSpec
    return CSResolveMediaUrn(mediaUrn, mediaSpecs, error);
}

@end
