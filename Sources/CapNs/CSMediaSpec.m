//
//  CSMediaSpec.m
//  MediaSpec parsing and handling
//

#import "include/CSMediaSpec.h"
#import "include/CSCapUrn.h"

NSErrorDomain const CSMediaSpecErrorDomain = @"CSMediaSpecErrorDomain";

// ============================================================================
// BUILT-IN SPEC ID CONSTANTS
// ============================================================================

NSString * const CSSpecIdStr = @"std:str.v1";
NSString * const CSSpecIdInt = @"std:int.v1";
NSString * const CSSpecIdNum = @"std:num.v1";
NSString * const CSSpecIdBool = @"std:bool.v1";
NSString * const CSSpecIdObj = @"std:obj.v1";
NSString * const CSSpecIdStrArray = @"std:str-array.v1";
NSString * const CSSpecIdIntArray = @"std:int-array.v1";
NSString * const CSSpecIdNumArray = @"std:num-array.v1";
NSString * const CSSpecIdBoolArray = @"std:bool-array.v1";
NSString * const CSSpecIdObjArray = @"std:obj-array.v1";
NSString * const CSSpecIdBinary = @"std:binary.v1";

// Built-in spec ID definitions - maps spec ID to canonical media spec string
static NSDictionary<NSString *, NSString *> *_builtinSpecs = nil;

static NSDictionary<NSString *, NSString *> *CSGetBuiltinSpecs(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _builtinSpecs = @{
            CSSpecIdStr: @"text/plain; profile=https://capns.org/schema/str",
            CSSpecIdInt: @"text/plain; profile=https://capns.org/schema/int",
            CSSpecIdNum: @"text/plain; profile=https://capns.org/schema/num",
            CSSpecIdBool: @"text/plain; profile=https://capns.org/schema/bool",
            CSSpecIdObj: @"application/json; profile=https://capns.org/schema/obj",
            CSSpecIdStrArray: @"application/json; profile=https://capns.org/schema/str-array",
            CSSpecIdIntArray: @"application/json; profile=https://capns.org/schema/int-array",
            CSSpecIdNumArray: @"application/json; profile=https://capns.org/schema/num-array",
            CSSpecIdBoolArray: @"application/json; profile=https://capns.org/schema/bool-array",
            CSSpecIdObjArray: @"application/json; profile=https://capns.org/schema/obj-array",
            CSSpecIdBinary: @"application/octet-stream"
        };
    });
    return _builtinSpecs;
}

BOOL CSIsBuiltinSpecId(NSString *specId) {
    return CSGetBuiltinSpecs()[specId] != nil;
}

NSString * _Nullable CSGetBuiltinSpecDefinition(NSString *specId) {
    return CSGetBuiltinSpecs()[specId];
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
// SPEC ID RESOLUTION
// ============================================================================

CSMediaSpec * _Nullable CSResolveSpecId(NSString *specId,
                                        NSDictionary * _Nullable mediaSpecs,
                                        NSError * _Nullable * _Nullable error) {
    // First check local mediaSpecs table
    if (mediaSpecs && mediaSpecs[specId]) {
        id def = mediaSpecs[specId];

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
                                                 code:CSMediaSpecErrorUnresolvableSpecId
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Spec ID '%@' has invalid object definition: missing media_type", specId]}];
                }
                return nil;
            }

            return [CSMediaSpec withContentType:mediaType profile:profileUri schema:schema];
        }
    }

    // Check built-in specs
    NSString *builtinDef = CSGetBuiltinSpecDefinition(specId);
    if (builtinDef) {
        return [CSMediaSpec parse:builtinDef error:error];
    }

    // FAIL HARD - no fallbacks, no guessing
    if (error) {
        *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                     code:CSMediaSpecErrorUnresolvableSpecId
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Cannot resolve spec ID: '%@'. Not found in mediaSpecs table and not a known built-in.", specId]}];
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
    NSString *specId = [capUrn getTag:@"out"];

    if (!specId) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                         code:CSMediaSpecErrorUnresolvableSpecId
                                     userInfo:@{NSLocalizedDescriptionKey: @"no 'out' tag found in cap URN"}];
        }
        return nil;
    }

    // Resolve the spec ID to a MediaSpec
    return CSResolveSpecId(specId, mediaSpecs, error);
}

@end
