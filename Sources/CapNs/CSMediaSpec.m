//
//  CSMediaSpec.m
//  MediaSpec parsing and handling
//

#import "include/CSMediaSpec.h"
#import "include/CSCapUrn.h"

NSErrorDomain const CSMediaSpecErrorDomain = @"CSMediaSpecErrorDomain";

// ============================================================================
// BUILT-IN MEDIA URN CONSTANTS
// ============================================================================

NSString * const CSMediaString = @"media:type=string;v=1;textable;scalar";
NSString * const CSMediaInteger = @"media:type=integer;v=1;textable;numeric;scalar";
NSString * const CSMediaNumber = @"media:type=number;v=1;textable;numeric;scalar";
NSString * const CSMediaBoolean = @"media:type=boolean;v=1;textable;scalar";
NSString * const CSMediaObject = @"media:type=object;v=1;textable;keyed";
NSString * const CSMediaStringArray = @"media:type=string-array;v=1;textable;sequence";
NSString * const CSMediaIntegerArray = @"media:type=integer-array;v=1;textable;numeric;sequence";
NSString * const CSMediaNumberArray = @"media:type=number-array;v=1;textable;numeric;sequence";
NSString * const CSMediaBooleanArray = @"media:type=boolean-array;v=1;textable;sequence";
NSString * const CSMediaObjectArray = @"media:type=object-array;v=1;textable;keyed;sequence";
NSString * const CSMediaBinary = @"media:type=binary;v=1;binary";
NSString * const CSMediaVoid = @"media:type=void;v=1";

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
            CSMediaVoid: @"application/x-void; profile=https://capns.org/schema/void"
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
@end

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
    CSMediaSpec *spec = [[CSMediaSpec alloc] init];
    spec.contentType = contentType;
    spec.profile = profile;
    spec.schema = schema;
    return spec;
}

+ (instancetype)withContentType:(NSString *)contentType profile:(nullable NSString *)profile {
    return [self withContentType:contentType profile:profile schema:nil];
}

- (BOOL)isBinary {
    NSString *ct = [self.contentType lowercaseString];

    // Binary content types
    return [ct hasPrefix:@"image/"] ||
           [ct hasPrefix:@"audio/"] ||
           [ct hasPrefix:@"video/"] ||
           [ct isEqualToString:@"application/octet-stream"] ||
           [ct isEqualToString:@"application/pdf"] ||
           [ct hasPrefix:@"application/x-"] ||
           [ct containsString:@"+zip"] ||
           [ct containsString:@"+gzip"];
}

- (BOOL)isJSON {
    NSString *ct = [self.contentType lowercaseString];
    return [ct isEqualToString:@"application/json"] || [ct hasSuffix:@"+json"];
}

- (BOOL)isText {
    NSString *ct = [self.contentType lowercaseString];
    return [ct hasPrefix:@"text/"] || (![self isBinary] && ![self isJSON]);
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
            return [CSMediaSpec parse:(NSString *)def error:error];
        } else if ([def isKindOfClass:[NSDictionary class]]) {
            // Object form: { media_type, profile_uri, schema? }
            NSDictionary *objDef = (NSDictionary *)def;
            NSString *mediaType = objDef[@"media_type"] ?: objDef[@"mediaType"];
            NSString *profileUri = objDef[@"profile_uri"] ?: objDef[@"profileUri"];
            NSDictionary *schema = objDef[@"schema"];

            if (!mediaType) {
                if (error) {
                    *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                                 code:CSMediaSpecErrorUnresolvableMediaUrn
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Media URN '%@' has invalid object definition: missing media_type", mediaUrn]}];
                }
                return nil;
            }

            return [CSMediaSpec withContentType:mediaType profile:profileUri schema:schema];
        }
    }

    // Check built-in media URNs
    NSString *builtinDef = CSGetBuiltinMediaUrnDefinition(mediaUrn);
    if (builtinDef) {
        return [CSMediaSpec parse:builtinDef error:error];
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
