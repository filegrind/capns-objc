//
//  CSMediaSpec.m
//  MediaSpec parsing and handling
//

#import "include/CSMediaSpec.h"
#import "include/CSCapUrn.h"

NSErrorDomain const CSMediaSpecErrorDomain = @"CSMediaSpecErrorDomain";

@interface CSMediaSpec ()
@property (nonatomic, readwrite) NSString *contentType;
@property (nonatomic, readwrite, nullable) NSString *profile;
@end

@implementation CSMediaSpec

+ (nullable instancetype)parse:(NSString *)string error:(NSError * _Nullable * _Nullable)error {
    NSString *trimmed = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // Must start with "content-type:" (case-insensitive)
    NSString *lower = [trimmed lowercaseString];
    if (![lower hasPrefix:@"content-type:"]) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                         code:CSMediaSpecErrorMissingContentType
                                     userInfo:@{NSLocalizedDescriptionKey: @"media_spec must start with 'content-type:'"}];
        }
        return nil;
    }

    // Get everything after "content-type:"
    NSString *afterPrefix = [[trimmed substringFromIndex:13] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    // Split by semicolon to separate mime type from parameters
    NSArray<NSString *> *parts = [afterPrefix componentsSeparatedByString:@";"];

    NSString *contentType = [[parts firstObject] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (contentType.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                         code:CSMediaSpecErrorEmptyContentType
                                     userInfo:@{NSLocalizedDescriptionKey: @"content-type value cannot be empty"}];
        }
        return nil;
    }

    // Parse profile if present
    NSString *profile = nil;
    if (parts.count > 1) {
        NSMutableString *params = [NSMutableString string];
        for (NSUInteger i = 1; i < parts.count; i++) {
            if (i > 1) [params appendString:@";"];
            [params appendString:parts[i]];
        }

        NSString *parsedProfile = [self parseProfile:[params stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                                               error:error];
        if (*error != nil) {
            return nil;
        }
        profile = parsedProfile;
    }

    CSMediaSpec *spec = [[CSMediaSpec alloc] init];
    spec.contentType = contentType;
    spec.profile = profile;
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

+ (instancetype)withContentType:(NSString *)contentType profile:(nullable NSString *)profile {
    CSMediaSpec *spec = [[CSMediaSpec alloc] init];
    spec.contentType = contentType;
    spec.profile = profile;
    return spec;
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
    if (self.profile) {
        return [NSString stringWithFormat:@"content-type: %@; profile=\"%@\"", self.contentType, self.profile];
    }
    return [NSString stringWithFormat:@"content-type: %@", self.contentType];
}

- (NSString *)description {
    return [self toString];
}

@end

@implementation CSMediaSpec (CapUrn)

+ (nullable instancetype)fromCapUrn:(CSCapUrn *)capUrn error:(NSError * _Nullable * _Nullable)error {
    NSString *spec = [capUrn getTag:@"out"];

    if (!spec) {
        if (error) {
            *error = [NSError errorWithDomain:CSMediaSpecErrorDomain
                                         code:CSMediaSpecErrorMissingContentType
                                     userInfo:@{NSLocalizedDescriptionKey: @"no 'out' tag found in cap URN"}];
        }
        return nil;
    }

    return [CSMediaSpec parse:spec error:error];
}

@end
