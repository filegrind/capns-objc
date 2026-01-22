//
//  CSMediaSpec.m
//  MediaSpec parsing and handling
//

#import "include/CSMediaSpec.h"
#import "include/CSCapUrn.h"
@import TaggedUrn;

NSErrorDomain const CSMediaSpecErrorDomain = @"CSMediaSpecErrorDomain";

// ============================================================================
// BUILT-IN MEDIA URN CONSTANTS
// ============================================================================

NSString * const CSMediaString = @"media:string;textable;scalar";
NSString * const CSMediaInteger = @"media:integer;textable;numeric;scalar";
NSString * const CSMediaNumber = @"media:number;textable;numeric;scalar";
NSString * const CSMediaBoolean = @"media:boolean;textable;scalar";
NSString * const CSMediaObject = @"media:object;textable;keyed";
NSString * const CSMediaStringArray = @"media:string-array;textable;sequence";
NSString * const CSMediaIntegerArray = @"media:integer-array;textable;numeric;sequence";
NSString * const CSMediaNumberArray = @"media:number-array;textable;numeric;sequence";
NSString * const CSMediaBooleanArray = @"media:boolean-array;textable;sequence";
NSString * const CSMediaObjectArray = @"media:object-array;textable;keyed;sequence";
NSString * const CSMediaBinary = @"media:raw;binary";
NSString * const CSMediaVoid = @"media:void";
// Semantic content types
NSString * const CSMediaImage = @"media:png;binary";
NSString * const CSMediaAudio = @"media:wav;audio;binary;";
NSString * const CSMediaVideo = @"media:video;binary";
NSString * const CSMediaText = @"media:text;textable";
// Document types (PRIMARY naming - type IS the format)
NSString * const CSMediaPdf = @"media:pdf;binary";
NSString * const CSMediaEpub = @"media:epub;binary";
// Text format types (PRIMARY naming - type IS the format)
NSString * const CSMediaMd = @"media:md;textable";
NSString * const CSMediaTxt = @"media:txt;textable";
NSString * const CSMediaRst = @"media:rst;textable";
NSString * const CSMediaLog = @"media:log;textable";
NSString * const CSMediaHtml = @"media:html;textable";
NSString * const CSMediaXml = @"media:xml;textable";
NSString * const CSMediaJson = @"media:json;textable;keyed";
NSString * const CSMediaYaml = @"media:yaml;textable;keyed";

// Built-in media URN definitions - maps media URN to canonical media spec string
static NSDictionary<NSString *, NSString *> *_builtinMediaUrns = nil;

static NSDictionary<NSString *, NSString *> *CSGetBuiltinMediaUrns(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _builtinMediaUrns = @{
            CSMediaString: @"text/plain; profile=https://capns.org/schema/string",
            CSMediaInteger: @"text/plain; profile=https://capns.org/schema/integer",
            CSMediaNumber: @"text/plain; profile=https://capns.org/schema/number",
            CSMediaBoolean: @"text/plain; profile=https://capns.org/schema/boolean",
            CSMediaObject: @"application/json; profile=https://capns.org/schema/object",
            CSMediaStringArray: @"application/json; profile=https://capns.org/schema/string-array",
            CSMediaIntegerArray: @"application/json; profile=https://capns.org/schema/integer-array",
            CSMediaNumberArray: @"application/json; profile=https://capns.org/schema/number-array",
            CSMediaBooleanArray: @"application/json; profile=https://capns.org/schema/boolean-array",
            CSMediaObjectArray: @"application/json; profile=https://capns.org/schema/object-array",
            CSMediaBinary: @"application/octet-stream",
            CSMediaVoid: @"application/x-void; profile=https://capns.org/schema/void",
            // Semantic content types
            CSMediaImage: @"image/png; profile=https://capns.org/schema/image",
            CSMediaAudio: @"audio/wav; profile=https://capns.org/schema/audio",
            CSMediaVideo: @"video/mp4; profile=https://capns.org/schema/video",
            CSMediaText: @"text/plain; profile=https://capns.org/schema/text",
            // Document types (PRIMARY naming)
            CSMediaPdf: @"application/pdf",
            CSMediaEpub: @"application/epub+zip",
            // Text format types (PRIMARY naming)
            CSMediaMd: @"text/markdown",
            CSMediaTxt: @"text/plain",
            CSMediaRst: @"text/x-rst",
            CSMediaLog: @"text/plain",
            CSMediaHtml: @"text/html",
            CSMediaXml: @"application/xml",
            CSMediaJson: @"application/json",
            CSMediaYaml: @"application/x-yaml"
        };
    });
    return _builtinMediaUrns;
}

BOOL CSIsBuiltinMediaUrn(NSString *mediaUrn) {
    return CSGetBuiltinMediaUrns()[mediaUrn] != nil;
}

NSString * _Nullable CSGetBuiltinMediaUrnDefinition(NSString *mediaUrn) {
    return CSGetBuiltinMediaUrns()[mediaUrn];
}

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
@end

/// Helper to check if a media URN has a marker tag using CSTaggedUrn
static BOOL CSMediaUrnHasTag(NSString *mediaUrn, NSString *tagName) {
    if (!mediaUrn) return NO;
    NSError *error = nil;
    CSTaggedUrn *parsed = [CSTaggedUrn fromString:mediaUrn error:&error];
    if (error || !parsed) return NO;
    return [parsed getTag:tagName] != nil;
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
    CSMediaSpec *spec = [[CSMediaSpec alloc] init];
    spec.contentType = contentType;
    spec.profile = profile;
    spec.schema = schema;
    spec.title = title;
    spec.descriptionText = descriptionText;
    return spec;
}

+ (instancetype)withContentType:(NSString *)contentType profile:(nullable NSString *)profile {
    return [self withContentType:contentType profile:profile schema:nil];
}

- (BOOL)isBinary {
    return CSMediaUrnHasTag(self.mediaUrn, @"binary");
}

- (BOOL)isJSON {
    return CSMediaUrnHasTag(self.mediaUrn, @"keyed");
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
            // Object form: { media_type, profile_uri, schema?, title?, description? }
            NSDictionary *objDef = (NSDictionary *)def;
            NSString *mediaType = objDef[@"media_type"] ?: objDef[@"mediaType"];
            NSString *profileUri = objDef[@"profile_uri"] ?: objDef[@"profileUri"];
            NSDictionary *schema = objDef[@"schema"];
            NSString *title = objDef[@"title"];
            NSString *descriptionText = objDef[@"description"];

            if (!mediaType) {
                if (error) {
                    *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                                 code:CSMediaSpecErrorUnresolvableMediaUrn
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Media URN '%@' has invalid object definition: missing media_type", mediaUrn]}];
                }
                return nil;
            }

            CSMediaSpec *spec = [CSMediaSpec withContentType:mediaType profile:profileUri schema:schema title:title descriptionText:descriptionText];
            spec.mediaUrn = mediaUrn;
            return spec;
        }
    }

    // Check built-in media URNs
    NSString *builtinDef = CSGetBuiltinMediaUrnDefinition(mediaUrn);
    if (builtinDef) {
        CSMediaSpec *spec = [CSMediaSpec parse:builtinDef error:error];
        if (spec) spec.mediaUrn = mediaUrn;
        return spec;
    }

    // FAIL HARD - no fallbacks, no guessing
    if (error) {
        *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                     code:CSMediaSpecErrorUnresolvableMediaUrn
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Cannot resolve media URN: '%@'. Not found in mediaSpecs table and not a known built-in.", mediaUrn]}];
    }
    return nil;
}

// ============================================================================
// MEDIA URN SATISFIES
// ============================================================================

/// Helper to extract a tag value from a media URN string
static NSString * _Nullable CSExtractMediaUrnTag(NSString *mediaUrn, NSString *tagName) {
    // Media URN format: media:X;ext=Y;...
    NSString *prefix = [NSString stringWithFormat:@"%@=", tagName];
    NSRange range = [mediaUrn rangeOfString:prefix];
    if (range.location == NSNotFound) {
        return nil;
    }

    NSUInteger start = range.location + range.length;
    NSRange semicolonRange = [mediaUrn rangeOfString:@";" options:0 range:NSMakeRange(start, mediaUrn.length - start)];

    if (semicolonRange.location == NSNotFound) {
        return [mediaUrn substringFromIndex:start];
    }
    return [mediaUrn substringWithRange:NSMakeRange(start, semicolonRange.location - start)];
}

BOOL CSMediaUrnSatisfies(NSString *providedUrn, NSString *requirementUrn) {
    if (!providedUrn || !requirementUrn) {
        return NO;
    }

    // Extract type from both URNs
    NSString *providedType = CSExtractMediaUrnTag(providedUrn, @"type");
    NSString *requiredType = CSExtractMediaUrnTag(requirementUrn, @"type");

    // Type must match if required
    if (requiredType) {
        if (!providedType || ![providedType isEqualToString:requiredType]) {
            return NO;
        }
    }

    // Extension must match if specified in requirement
    NSString *requiredExt = CSExtractMediaUrnTag(requirementUrn, @"ext");
    if (requiredExt) {
        NSString *providedExt = CSExtractMediaUrnTag(providedUrn, @"ext");
        if (!providedExt || ![providedExt isEqualToString:requiredExt]) {
            return NO;
        }
    }

    // Version must match if specified in requirement
    NSString *requiredVersion = CSExtractMediaUrnTag(requirementUrn, @"v");
    if (requiredVersion) {
        NSString *providedVersion = CSExtractMediaUrnTag(providedUrn, @"v");
        if (!providedVersion || ![providedVersion isEqualToString:requiredVersion]) {
            return NO;
        }
    }

    return YES;
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
