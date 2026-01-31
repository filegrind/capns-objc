//
//  CSMediaSpec.m
//  MediaSpec parsing and handling
//

#import "include/CSMediaSpec.h"
#import "include/CSCapUrn.h"
#import "include/CSCap.h"
@import TaggedUrn;

NSErrorDomain const CSMediaSpecErrorDomain = @"CSMediaSpecErrorDomain";

// ============================================================================
// BUILT-IN MEDIA URN CONSTANTS
// ============================================================================

NSString * const CSMediaString = @"media:textable;form=scalar";
NSString * const CSMediaInteger = @"media:integer;textable;numeric;form=scalar";
NSString * const CSMediaNumber = @"media:textable;numeric;form=scalar";
NSString * const CSMediaBoolean = @"media:bool;textable;form=scalar";
NSString * const CSMediaObject = @"media:form=map;textable";
NSString * const CSMediaStringArray = @"media:textable;form=list";
NSString * const CSMediaIntegerArray = @"media:integer;textable;numeric;form=list";
NSString * const CSMediaNumberArray = @"media:textable;numeric;form=list";
NSString * const CSMediaBooleanArray = @"media:bool;textable;form=list";
NSString * const CSMediaObjectArray = @"media:form=list;textable";
NSString * const CSMediaBinary = @"media:bytes";
NSString * const CSMediaVoid = @"media:void";
// Semantic content types
NSString * const CSMediaImage = @"media:image;png;bytes";
NSString * const CSMediaAudio = @"media:wav;audio;bytes;";
NSString * const CSMediaVideo = @"media:video;bytes";
// Semantic AI input types
NSString * const CSMediaAudioSpeech = @"media:audio;wav;bytes;speech";
NSString * const CSMediaImageThumbnail = @"media:image;png;bytes;thumbnail";
// Document types (PRIMARY naming - type IS the format)
NSString * const CSMediaPdf = @"media:pdf;bytes";
NSString * const CSMediaEpub = @"media:epub;bytes";
// Text format types (PRIMARY naming - type IS the format)
NSString * const CSMediaMd = @"media:md;textable";
NSString * const CSMediaTxt = @"media:txt;textable";
NSString * const CSMediaRst = @"media:rst;textable";
NSString * const CSMediaLog = @"media:log;textable";
NSString * const CSMediaHtml = @"media:html;textable";
NSString * const CSMediaXml = @"media:xml;textable";
NSString * const CSMediaJson = @"media:json;textable;form=map";
NSString * const CSMediaJsonSchema = @"media:json;json-schema;textable;form=map";
NSString * const CSMediaYaml = @"media:yaml;textable;form=map";
// Semantic input types
NSString * const CSMediaModelSpec = @"media:model-spec;textable;form=scalar";
NSString * const CSMediaModelRepo = @"media:model-repo;textable;form=map";
// Semantic output types
NSString * const CSMediaModelDim = @"media:model-dim;integer;textable;numeric;form=scalar";
NSString * const CSMediaDecision = @"media:decision;bool;textable;form=scalar";
NSString * const CSMediaDecisionArray = @"media:decision;bool;textable;form=list";

// ============================================================================
// SCHEMA URL CONFIGURATION
// ============================================================================

static NSString * const CSDefaultSchemaBase = @"https://capns.org/schema";

/**
 * Get the schema base URL from environment variables or default
 *
 * Checks in order:
 * 1. CAPNS_SCHEMA_BASE_URL environment variable
 * 2. CAPNS_REGISTRY_URL environment variable + "/schema"
 * 3. Default: "https://capns.org/schema"
 */
NSString *CSGetSchemaBaseURL(void) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];

    NSString *schemaURL = env[@"CAPNS_SCHEMA_BASE_URL"];
    if (schemaURL.length > 0) {
        return schemaURL;
    }

    NSString *registryURL = env[@"CAPNS_REGISTRY_URL"];
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
@property (nonatomic, readwrite, nullable) NSString *extension;
@end

/// Helper to check if a media URN has a marker tag using CSTaggedUrn.
/// Requires a valid, non-empty media URN - fails hard otherwise.
static BOOL CSMediaUrnHasTag(NSString *mediaUrn, NSString *tagName) {
    if (mediaUrn == nil || mediaUrn.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSMediaUrnHasTag called with nil/empty mediaUrn - this indicates the CSMediaSpec was not resolved via CSResolveMediaUrn"];
    }
    NSError *error = nil;
    CSTaggedUrn *parsed = [CSTaggedUrn fromString:mediaUrn error:&error];
    if (parsed == nil || error != nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Failed to parse media URN '%@': %@ - this indicates invalid data", mediaUrn, error.localizedDescription];
    }
    return [parsed getTag:tagName] != nil;
}

/// Helper to check if a media URN has a tag with a specific value (e.g., form=map).
/// Requires a valid, non-empty media URN - fails hard otherwise.
static BOOL CSMediaUrnHasTagValue(NSString *mediaUrn, NSString *tagKey, NSString *tagValue) {
    if (mediaUrn == nil || mediaUrn.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSMediaUrnHasTagValue called with nil/empty mediaUrn - this indicates the CSMediaSpec was not resolved via CSResolveMediaUrn"];
    }
    NSError *error = nil;
    CSTaggedUrn *parsed = [CSTaggedUrn fromString:mediaUrn error:&error];
    if (parsed == nil || error != nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Failed to parse media URN '%@': %@ - this indicates invalid data", mediaUrn, error.localizedDescription];
    }
    NSString *value = [parsed getTag:tagKey];
    return value != nil && [value isEqualToString:tagValue];
}

/// Public function to check if a media URN represents binary data.
/// Requires a valid, non-empty media URN.
BOOL CSMediaUrnIsBinary(NSString *mediaUrn) {
    if (mediaUrn == nil || mediaUrn.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSMediaUrnIsBinary called with nil/empty mediaUrn"];
    }
    return CSMediaUrnHasTag(mediaUrn, @"bytes");
}

/// Public function to check if a media URN represents text data.
/// Requires a valid, non-empty media URN.
BOOL CSMediaUrnIsText(NSString *mediaUrn) {
    if (mediaUrn == nil || mediaUrn.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSMediaUrnIsText called with nil/empty mediaUrn"];
    }
    return CSMediaUrnHasTag(mediaUrn, @"textable");
}

/// Public function to check if a media URN represents JSON data.
/// Requires a valid, non-empty media URN.
BOOL CSMediaUrnIsJson(NSString *mediaUrn) {
    if (mediaUrn == nil || mediaUrn.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSMediaUrnIsJson called with nil/empty mediaUrn"];
    }
    return CSMediaUrnHasTag(mediaUrn, @"json");
}

/// Public function to check if a media URN represents a list (form=list).
/// Requires a valid, non-empty media URN.
BOOL CSMediaUrnIsList(NSString *mediaUrn) {
    if (mediaUrn == nil || mediaUrn.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSMediaUrnIsList called with nil/empty mediaUrn"];
    }
    return CSMediaUrnHasTagValue(mediaUrn, @"form", @"list");
}

/// Public function to check if a media URN represents a map (form=map).
/// Requires a valid, non-empty media URN.
BOOL CSMediaUrnIsMap(NSString *mediaUrn) {
    if (mediaUrn == nil || mediaUrn.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSMediaUrnIsMap called with nil/empty mediaUrn"];
    }
    return CSMediaUrnHasTagValue(mediaUrn, @"form", @"map");
}

/// Public function to check if a media URN represents a scalar (form=scalar).
/// Requires a valid, non-empty media URN.
BOOL CSMediaUrnIsScalar(NSString *mediaUrn) {
    if (mediaUrn == nil || mediaUrn.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSMediaUrnIsScalar called with nil/empty mediaUrn"];
    }
    return CSMediaUrnHasTagValue(mediaUrn, @"form", @"scalar");
}

/// Public function to check if a media URN represents image data.
/// Requires a valid, non-empty media URN.
BOOL CSMediaUrnIsImage(NSString *mediaUrn) {
    if (mediaUrn == nil || mediaUrn.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSMediaUrnIsImage called with nil/empty mediaUrn"];
    }
    return CSMediaUrnHasTag(mediaUrn, @"image");
}

/// Public function to check if a media URN represents audio data.
/// Requires a valid, non-empty media URN.
BOOL CSMediaUrnIsAudio(NSString *mediaUrn) {
    if (mediaUrn == nil || mediaUrn.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSMediaUrnIsAudio called with nil/empty mediaUrn"];
    }
    return CSMediaUrnHasTag(mediaUrn, @"audio");
}

/// Public function to check if a media URN represents video data.
/// Requires a valid, non-empty media URN.
BOOL CSMediaUrnIsVideo(NSString *mediaUrn) {
    if (mediaUrn == nil || mediaUrn.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSMediaUrnIsVideo called with nil/empty mediaUrn"];
    }
    return CSMediaUrnHasTag(mediaUrn, @"video");
}

/// Public function to check if a media URN represents numeric data.
/// Requires a valid, non-empty media URN.
BOOL CSMediaUrnIsNumeric(NSString *mediaUrn) {
    if (mediaUrn == nil || mediaUrn.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSMediaUrnIsNumeric called with nil/empty mediaUrn"];
    }
    return CSMediaUrnHasTag(mediaUrn, @"numeric");
}

/// Public function to check if a media URN represents boolean data.
/// Requires a valid, non-empty media URN.
BOOL CSMediaUrnIsBool(NSString *mediaUrn) {
    if (mediaUrn == nil || mediaUrn.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"CSMediaUrnIsBool called with nil/empty mediaUrn"];
    }
    return CSMediaUrnHasTag(mediaUrn, @"bool");
}

@implementation CSMediaSpec

+ (nullable instancetype)parse:(NSString *)string error:(NSError * _Nullable * _Nullable)error {
    NSString *trimmed = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *lower = [trimmed lowercaseString];

    // FAIL HARD on legacy format - no backward compatibility
    if ([lower hasPrefix:@"content-type:"]) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                         code:CSMediaSpecErrorLegacyFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Legacy 'content-type:' prefix is no longer supported. Use canonical format: '<media-type>; profile=<url>'"}];
        }
        return nil;
    }

    // Split by semicolon to separate mime type from parameters
    NSRange semicolonRange = [trimmed rangeOfString:@";"];
    NSString *contentType;
    NSString *paramsStr = nil;

    if (semicolonRange.location == NSNotFound) {
        contentType = [trimmed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    } else {
        contentType = [[trimmed substringToIndex:semicolonRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        paramsStr = [[trimmed substringFromIndex:semicolonRange.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }

    if (contentType.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                         code:CSMediaSpecErrorEmptyContentType
                                     userInfo:@{NSLocalizedDescriptionKey: @"media_type cannot be empty"}];
        }
        return nil;
    }

    // Parse profile if present
    NSString *profile = nil;
    if (paramsStr) {
        profile = [self parseProfile:paramsStr error:error];
        if (error && *error != nil) {
            return nil;
        }
    }

    CSMediaSpec *spec = [[CSMediaSpec alloc] init];
    spec.contentType = contentType;
    spec.profile = profile;
    spec.schema = nil;
    return spec;
}

+ (NSString *)parseProfile:(NSString *)params error:(NSError * _Nullable * _Nullable)error {
    // Look for profile= (case-insensitive)
    NSRange range = [[params lowercaseString] rangeOfString:@"profile="];
    if (range.location == NSNotFound) {
        return nil;
    }

    NSString *afterProfile = [params substringFromIndex:range.location + range.length];

    // Handle quoted value
    if ([afterProfile hasPrefix:@"\""]) {
        NSString *rest = [afterProfile substringFromIndex:1];
        NSRange endQuote = [rest rangeOfString:@"\""];
        if (endQuote.location == NSNotFound) {
            if (error) {
                *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                             code:CSMediaSpecErrorUnterminatedQuote
                                         userInfo:@{NSLocalizedDescriptionKey: @"unterminated quote in profile value"}];
            }
            return nil;
        }
        return [rest substringToIndex:endQuote.location];
    }

    // Unquoted value - take until semicolon or end
    NSRange semicolon = [afterProfile rangeOfString:@";"];
    if (semicolon.location != NSNotFound) {
        return [[afterProfile substringToIndex:semicolon.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    return [afterProfile stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

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
    return [self withContentType:contentType profile:profile schema:schema title:title descriptionText:descriptionText validation:validation metadata:nil extension:nil];
}

+ (instancetype)withContentType:(NSString *)contentType
                        profile:(nullable NSString *)profile
                         schema:(nullable NSDictionary *)schema
                          title:(nullable NSString *)title
                descriptionText:(nullable NSString *)descriptionText
                     validation:(nullable CSMediaValidation *)validation
                       metadata:(nullable NSDictionary *)metadata
                      extension:(nullable NSString *)extension {
    CSMediaSpec *spec = [[CSMediaSpec alloc] init];
    spec.contentType = contentType;
    spec.profile = profile;
    spec.schema = schema;
    spec.title = title;
    spec.descriptionText = descriptionText;
    spec.validation = validation;
    spec.metadata = metadata;
    spec.extension = extension;
    return spec;
}

+ (instancetype)withContentType:(NSString *)contentType profile:(nullable NSString *)profile {
    return [self withContentType:contentType profile:profile schema:nil];
}

- (BOOL)isBinary {
    return CSMediaUrnHasTag(self.mediaUrn, @"bytes");
}

- (BOOL)isMap {
    return CSMediaUrnHasTagValue(self.mediaUrn, @"form", @"map");
}

- (BOOL)isScalar {
    return CSMediaUrnHasTagValue(self.mediaUrn, @"form", @"scalar");
}

- (BOOL)isList {
    return CSMediaUrnHasTagValue(self.mediaUrn, @"form", @"list");
}

- (BOOL)isStructured {
    return [self isMap] || [self isList];
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
                                          NSDictionary * _Nullable mediaSpecs,
                                          NSError * _Nullable * _Nullable error) {
    // First check local mediaSpecs table
    if (mediaSpecs && mediaSpecs[mediaUrn]) {
        id def = mediaSpecs[mediaUrn];

        if ([def isKindOfClass:[NSString class]]) {
            // String form: canonical media spec string
            CSMediaSpec *spec = [CSMediaSpec parse:(NSString *)def error:error];
            if (spec) spec.mediaUrn = mediaUrn;
            return spec;
        } else if ([def isKindOfClass:[NSDictionary class]]) {
            // Object form: { media_type, profile_uri, schema?, title?, description?, validation?, metadata? }
            NSDictionary *objDef = (NSDictionary *)def;
            NSString *mediaType = objDef[@"media_type"] ?: objDef[@"mediaType"];
            NSString *profileUri = objDef[@"profile_uri"] ?: objDef[@"profileUri"];
            NSDictionary *schema = objDef[@"schema"];
            NSString *title = objDef[@"title"];
            NSString *descriptionText = objDef[@"description"];

            // Parse validation if present
            CSMediaValidation *validation = nil;
            NSDictionary *validationDict = objDef[@"validation"];
            if (validationDict && [validationDict isKindOfClass:[NSDictionary class]]) {
                NSError *validationError = nil;
                validation = [CSMediaValidation validationWithDictionary:validationDict error:&validationError];
                // Ignore validation parse errors - validation is optional
            }

            // Extract metadata if present
            NSDictionary *metadata = nil;
            id metadataValue = objDef[@"metadata"];
            if (metadataValue && [metadataValue isKindOfClass:[NSDictionary class]]) {
                metadata = (NSDictionary *)metadataValue;
            }

            // Extract extension if present
            NSString *extension = nil;
            id extensionValue = objDef[@"extension"];
            if (extensionValue && [extensionValue isKindOfClass:[NSString class]]) {
                extension = (NSString *)extensionValue;
            }

            if (!mediaType) {
                if (error) {
                    *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                                 code:CSMediaSpecErrorUnresolvableMediaUrn
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Media URN '%@' has invalid object definition: missing media_type", mediaUrn]}];
                }
                return nil;
            }

            CSMediaSpec *spec = [CSMediaSpec withContentType:mediaType profile:profileUri schema:schema title:title descriptionText:descriptionText validation:validation metadata:metadata extension:extension];
            spec.mediaUrn = mediaUrn;
            return spec;
        }
    }

    // FAIL HARD - media URN must be in mediaSpecs table
    if (error) {
        *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                     code:CSMediaSpecErrorUnresolvableMediaUrn
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Cannot resolve media URN: '%@'. Not found in mediaSpecs table.", mediaUrn]}];
    }
    return nil;
}

// ============================================================================
// CAP URN EXTENSION
// ============================================================================

@implementation CSMediaSpec (CapUrn)

+ (nullable instancetype)fromCapUrn:(CSCapUrn *)capUrn
                         mediaSpecs:(NSDictionary * _Nullable)mediaSpecs
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
