//
//  CSCapUrn.m
//  Flat Tag-Based Cap Identifier Implementation
//

#import "CSCapUrn.h"

NSErrorDomain const CSCapUrnErrorDomain = @"CSCapUrnErrorDomain";

// Parser states for state machine
typedef NS_ENUM(NSInteger, CSParseState) {
    CSParseStateExpectingKey,
    CSParseStateInKey,
    CSParseStateExpectingValue,
    CSParseStateInUnquotedValue,
    CSParseStateInQuotedValue,
    CSParseStateInQuotedValueEscape,
    CSParseStateExpectingSemiOrEnd
};

@interface CSCapUrn ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *mutableTags;
@end

@implementation CSCapUrn

- (NSDictionary<NSString *, NSString *> *)tags {
    return [self.mutableTags copy];
}

#pragma mark - Helper Methods

+ (BOOL)isValidKeyChar:(unichar)c {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
           c == '_' || c == '-' || c == '/' || c == ':' || c == '.';
}

+ (BOOL)isValidUnquotedValueChar:(unichar)c {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
           c == '_' || c == '-' || c == '/' || c == ':' || c == '.' || c == '*';
}

+ (BOOL)isPurelyNumeric:(NSString *)s {
    if (s.length == 0) return NO;
    NSCharacterSet *numericSet = [NSCharacterSet decimalDigitCharacterSet];
    NSCharacterSet *nonNumericSet = [numericSet invertedSet];
    return [s rangeOfCharacterFromSet:nonNumericSet].location == NSNotFound;
}

+ (BOOL)needsQuoting:(NSString *)value {
    for (NSUInteger i = 0; i < value.length; i++) {
        unichar c = [value characterAtIndex:i];
        if (c == ';' || c == '=' || c == '"' || c == '\\' || c == ' ') {
            return YES;
        }
        // Check for uppercase letter
        if (c >= 'A' && c <= 'Z') {
            return YES;
        }
    }
    return NO;
}

+ (NSString *)quoteValue:(NSString *)value {
    NSMutableString *result = [NSMutableString stringWithString:@"\""];
    for (NSUInteger i = 0; i < value.length; i++) {
        unichar c = [value characterAtIndex:i];
        if (c == '"' || c == '\\') {
            [result appendString:@"\\"];
        }
        [result appendFormat:@"%C", c];
    }
    [result appendString:@"\""];
    return result;
}

#pragma mark - Parsing

+ (nullable instancetype)fromString:(NSString *)string error:(NSError **)error {
    if (!string || string.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap identifier cannot be empty"}];
        }
        return nil;
    }

    // Check for "cap:" prefix (case-insensitive)
    if (string.length < 4 || ![[string substringToIndex:4] caseInsensitiveCompare:@"cap:"] == NSOrderedSame) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorMissingCapPrefix
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap identifier must start with 'cap:'"}];
        }
        return nil;
    }

    NSString *tagsPart = [string substringFromIndex:4];
    NSMutableDictionary<NSString *, NSString *> *tags = [NSMutableDictionary dictionary];

    // Handle empty cap URN (cap: with no tags or just semicolon)
    if (tagsPart.length == 0 || [tagsPart isEqualToString:@";"]) {
        return [self fromTagsInternal:tags error:error];
    }

    CSParseState state = CSParseStateExpectingKey;
    NSMutableString *currentKey = [NSMutableString string];
    NSMutableString *currentValue = [NSMutableString string];
    NSUInteger pos = 0;

    while (pos < tagsPart.length) {
        unichar c = [tagsPart characterAtIndex:pos];

        switch (state) {
            case CSParseStateExpectingKey:
                if (c == ';') {
                    // Empty segment, skip
                    pos++;
                    continue;
                } else if ([self isValidKeyChar:c]) {
                    [currentKey appendFormat:@"%c", tolower(c)];
                    state = CSParseStateInKey;
                } else {
                    if (error) {
                        *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                                     code:CSCapUrnErrorInvalidCharacter
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"invalid character '%C' at position %lu", c, (unsigned long)pos]}];
                    }
                    return nil;
                }
                break;

            case CSParseStateInKey:
                if (c == '=') {
                    if (currentKey.length == 0) {
                        if (error) {
                            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                                         code:CSCapUrnErrorEmptyTag
                                                     userInfo:@{NSLocalizedDescriptionKey: @"empty key"}];
                        }
                        return nil;
                    }
                    state = CSParseStateExpectingValue;
                } else if ([self isValidKeyChar:c]) {
                    [currentKey appendFormat:@"%c", tolower(c)];
                } else {
                    if (error) {
                        *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                                     code:CSCapUrnErrorInvalidCharacter
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"invalid character '%C' in key at position %lu", c, (unsigned long)pos]}];
                    }
                    return nil;
                }
                break;

            case CSParseStateExpectingValue:
                if (c == '"') {
                    state = CSParseStateInQuotedValue;
                } else if (c == ';') {
                    if (error) {
                        *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                                     code:CSCapUrnErrorEmptyTag
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"empty value for key '%@'", currentKey]}];
                    }
                    return nil;
                } else if ([self isValidUnquotedValueChar:c]) {
                    [currentValue appendFormat:@"%c", tolower(c)];
                    state = CSParseStateInUnquotedValue;
                } else {
                    if (error) {
                        *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                                     code:CSCapUrnErrorInvalidCharacter
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"invalid character '%C' in value at position %lu", c, (unsigned long)pos]}];
                    }
                    return nil;
                }
                break;

            case CSParseStateInUnquotedValue:
                if (c == ';') {
                    if (![self finishTag:tags key:currentKey value:currentValue error:error]) {
                        return nil;
                    }
                    [currentKey setString:@""];
                    [currentValue setString:@""];
                    state = CSParseStateExpectingKey;
                } else if ([self isValidUnquotedValueChar:c]) {
                    [currentValue appendFormat:@"%c", tolower(c)];
                } else {
                    if (error) {
                        *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                                     code:CSCapUrnErrorInvalidCharacter
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"invalid character '%C' in unquoted value at position %lu", c, (unsigned long)pos]}];
                    }
                    return nil;
                }
                break;

            case CSParseStateInQuotedValue:
                if (c == '"') {
                    state = CSParseStateExpectingSemiOrEnd;
                } else if (c == '\\') {
                    state = CSParseStateInQuotedValueEscape;
                } else {
                    // Any character allowed in quoted value, preserve case
                    [currentValue appendFormat:@"%C", c];
                }
                break;

            case CSParseStateInQuotedValueEscape:
                if (c == '"' || c == '\\') {
                    [currentValue appendFormat:@"%C", c];
                    state = CSParseStateInQuotedValue;
                } else {
                    if (error) {
                        *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                                     code:CSCapUrnErrorInvalidEscapeSequence
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"invalid escape sequence at position %lu (only \\\" and \\\\ allowed)", (unsigned long)pos]}];
                    }
                    return nil;
                }
                break;

            case CSParseStateExpectingSemiOrEnd:
                if (c == ';') {
                    if (![self finishTag:tags key:currentKey value:currentValue error:error]) {
                        return nil;
                    }
                    [currentKey setString:@""];
                    [currentValue setString:@""];
                    state = CSParseStateExpectingKey;
                } else {
                    if (error) {
                        *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                                     code:CSCapUrnErrorInvalidCharacter
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"expected ';' or end after quoted value, got '%C' at position %lu", c, (unsigned long)pos]}];
                    }
                    return nil;
                }
                break;
        }

        pos++;
    }

    // Handle end of input
    switch (state) {
        case CSParseStateInUnquotedValue:
        case CSParseStateExpectingSemiOrEnd:
            if (![self finishTag:tags key:currentKey value:currentValue error:error]) {
                return nil;
            }
            break;
        case CSParseStateExpectingKey:
            // Valid - trailing semicolon or empty input after prefix
            break;
        case CSParseStateInQuotedValue:
        case CSParseStateInQuotedValueEscape:
            if (error) {
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorUnterminatedQuote
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"unterminated quote at position %lu", (unsigned long)pos]}];
            }
            return nil;
        case CSParseStateInKey:
            if (error) {
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorInvalidTagFormat
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"incomplete tag '%@'", currentKey]}];
            }
            return nil;
        case CSParseStateExpectingValue:
            if (error) {
                *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                             code:CSCapUrnErrorEmptyTag
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"empty value for key '%@'", currentKey]}];
            }
            return nil;
    }

    return [self fromTagsInternal:tags error:error];
}

+ (BOOL)finishTag:(NSMutableDictionary *)tags key:(NSString *)key value:(NSString *)value error:(NSError **)error {
    if (key.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorEmptyTag
                                     userInfo:@{NSLocalizedDescriptionKey: @"empty key"}];
        }
        return NO;
    }
    if (value.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorEmptyTag
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"empty value for key '%@'", key]}];
        }
        return NO;
    }

    // Check for duplicate keys
    if (tags[key] != nil) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorDuplicateKey
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Duplicate tag key: %@", key]}];
        }
        return NO;
    }

    // Validate key cannot be purely numeric
    if ([self isPurelyNumeric:key]) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorNumericKey
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Tag key cannot be purely numeric: %@", key]}];
        }
        return NO;
    }

    // Copy strings to prevent mutation after storage
    tags[[key copy]] = [value copy];
    return YES;
}

+ (nullable instancetype)fromTags:(NSDictionary<NSString *, NSString *> *)tags error:(NSError **)error {
    if (!tags) {
        tags = @{};
    }

    // Normalize keys to lowercase; values preserved as-is
    NSMutableDictionary<NSString *, NSString *> *normalizedTags = [NSMutableDictionary dictionary];
    for (NSString *key in tags) {
        NSString *value = tags[key];
        normalizedTags[[key lowercaseString]] = value;
    }

    return [self fromTagsInternal:normalizedTags error:error];
}

+ (nullable instancetype)fromTagsInternal:(NSDictionary<NSString *, NSString *> *)tags error:(NSError **)error {
    CSCapUrn *instance = [[CSCapUrn alloc] init];
    instance.mutableTags = [tags mutableCopy];
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _mutableTags = [NSMutableDictionary dictionary];
    }
    return self;
}

- (nullable NSString *)getTag:(NSString *)key {
    return self.mutableTags[[key lowercaseString]];
}

- (BOOL)hasTag:(NSString *)key withValue:(NSString *)value {
    NSString *tagValue = self.mutableTags[[key lowercaseString]];
    // Case-sensitive value comparison
    return tagValue && [tagValue isEqualToString:value];
}

- (CSCapUrn *)withTag:(NSString *)key value:(NSString *)value {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    // Key lowercase, value preserved
    newTags[[key lowercaseString]] = value;
    return [CSCapUrn fromTagsInternal:newTags error:nil];
}

- (CSCapUrn *)withoutTag:(NSString *)key {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    [newTags removeObjectForKey:[key lowercaseString]];
    return [CSCapUrn fromTagsInternal:newTags error:nil];
}

- (BOOL)matches:(CSCapUrn *)request {
    if (!request) {
        return YES;
    }

    // Check all tags that the request specifies
    for (NSString *requestKey in request.tags) {
        NSString *requestValue = request.tags[requestKey];
        NSString *capValue = self.mutableTags[requestKey];

        if (!capValue) {
            // Missing tag in cap is treated as wildcard - can handle any value
            continue;
        }

        if ([capValue isEqualToString:@"*"]) {
            // Cap has wildcard - can handle any value
            continue;
        }

        if ([requestValue isEqualToString:@"*"]) {
            // Request accepts any value - cap's specific value matches
            continue;
        }

        if (![capValue isEqualToString:requestValue]) {
            // Cap has specific value that doesn't match request's specific value
            return NO;
        }
    }

    // If cap has additional specific tags that request doesn't specify, that's fine
    // The cap is just more specific than needed
    return YES;
}

- (BOOL)canHandle:(CSCapUrn *)request {
    return [self matches:request];
}

- (NSUInteger)specificity {
    NSUInteger count = 0;
    for (NSString *value in self.mutableTags.allValues) {
        if (![value isEqualToString:@"*"]) {
            count++;
        }
    }
    return count;
}

- (BOOL)isMoreSpecificThan:(CSCapUrn *)other {
    if (!other) {
        return YES;
    }

    // First check if they're compatible
    if (![self isCompatibleWith:other]) {
        return NO;
    }

    return self.specificity > other.specificity;
}

- (BOOL)isCompatibleWith:(CSCapUrn *)other {
    if (!other) {
        return YES;
    }

    // Get all unique tag keys from both caps
    NSMutableSet<NSString *> *allKeys = [NSMutableSet setWithArray:self.mutableTags.allKeys];
    [allKeys addObjectsFromArray:other.mutableTags.allKeys];

    for (NSString *key in allKeys) {
        NSString *v1 = self.mutableTags[key];
        NSString *v2 = other.mutableTags[key];

        if (v1 && v2) {
            // Both have the tag - they must match or one must be wildcard
            if (![v1 isEqualToString:@"*"] && ![v2 isEqualToString:@"*"] && ![v1 isEqualToString:v2]) {
                return NO;
            }
        }
        // If only one has the tag, it's compatible (missing tag is wildcard)
    }

    return YES;
}

- (CSCapUrn *)withWildcardTag:(NSString *)key {
    if (self.mutableTags[[key lowercaseString]]) {
        return [self withTag:key value:@"*"];
    }
    return self;
}

- (CSCapUrn *)subset:(NSArray<NSString *> *)keys {
    NSMutableDictionary *newTags = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        NSString *normalizedKey = [key lowercaseString];
        NSString *value = self.mutableTags[normalizedKey];
        if (value) {
            newTags[normalizedKey] = value;
        }
    }
    return [CSCapUrn fromTagsInternal:newTags error:nil];
}

- (CSCapUrn *)merge:(CSCapUrn *)other {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    for (NSString *key in other.mutableTags) {
        newTags[key] = other.mutableTags[key];
    }
    return [CSCapUrn fromTagsInternal:newTags error:nil];
}

- (NSString *)toString {
    if (self.mutableTags.count == 0) {
        return @"cap:";
    }

    // Sort keys for canonical representation
    NSArray<NSString *> *sortedKeys = [self.mutableTags.allKeys sortedArrayUsingSelector:@selector(compare:)];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *key in sortedKeys) {
        NSString *value = self.mutableTags[key];
        if ([CSCapUrn needsQuoting:value]) {
            [parts addObject:[NSString stringWithFormat:@"%@=%@", key, [CSCapUrn quoteValue:value]]];
        } else {
            [parts addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
        }
    }

    NSString *tagsString = [parts componentsJoinedByString:@";"];
    return [NSString stringWithFormat:@"cap:%@", tagsString];
}

- (NSString *)description {
    return [self toString];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[CSCapUrn class]]) {
        return NO;
    }

    CSCapUrn *other = (CSCapUrn *)object;
    return [self.mutableTags isEqualToDictionary:other.mutableTags];
}

- (NSUInteger)hash {
    return self.mutableTags.hash;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    return [CSCapUrn fromTagsInternal:self.tags error:nil];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.mutableTags forKey:@"tags"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _mutableTags = [[coder decodeObjectOfClass:[NSMutableDictionary class] forKey:@"tags"] mutableCopy];
        if (!_mutableTags) {
            _mutableTags = [NSMutableDictionary dictionary];
        }
    }
    return self;
}

@end

#pragma mark - CSCapUrnBuilder

@interface CSCapUrnBuilder ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *tags;
@end

@implementation CSCapUrnBuilder

+ (instancetype)builder {
    return [[CSCapUrnBuilder alloc] init];
}

- (instancetype)init {
    if (self = [super init]) {
        _tags = [NSMutableDictionary dictionary];
    }
    return self;
}

- (CSCapUrnBuilder *)tag:(NSString *)key value:(NSString *)value {
    // Key lowercase, value preserved
    self.tags[[key lowercaseString]] = value;
    return self;
}

- (nullable CSCapUrn *)build:(NSError **)error {
    if (self.tags.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap identifier cannot be empty"}];
        }
        return nil;
    }

    return [CSCapUrn fromTagsInternal:self.tags error:error];
}


@end
