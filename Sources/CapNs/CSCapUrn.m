//
//  CSCapUrn.m
//  Flat Tag-Based Cap Identifier Implementation with Required Direction
//
//  Uses CSTaggedUrn for parsing to ensure consistency across implementations.
//

#import "CSCapUrn.h"
@import TaggedUrn;

NSErrorDomain const CSCapUrnErrorDomain = @"CSCapUrnErrorDomain";

@interface CSCapUrn ()
@property (nonatomic, strong) NSString *inSpec;
@property (nonatomic, strong) NSString *outSpec;
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

#pragma mark - Media URN Validation

+ (BOOL)isValidMediaUrnOrWildcard:(NSString *)value {
    return [value isEqualToString:@"*"] || [value hasPrefix:@"media:"];
}

#pragma mark - Parsing

/// Convert CSTaggedUrnError to CSCapUrnError with appropriate error code
+ (NSError *)capUrnErrorFromTaggedUrnError:(NSError *)taggedError {
    NSString *msg = taggedError.localizedDescription ?: @"";
    NSString *msgLower = [msg lowercaseString];

    CSCapUrnError code;
    if ([msgLower containsString:@"invalid character"]) {
        code = CSCapUrnErrorInvalidCharacter;
    } else if ([msgLower containsString:@"duplicate"]) {
        code = CSCapUrnErrorDuplicateKey;
    } else if ([msgLower containsString:@"unterminated"] || [msgLower containsString:@"unclosed"]) {
        code = CSCapUrnErrorUnterminatedQuote;
    } else if ([msgLower containsString:@"expected"] && [msgLower containsString:@"after quoted"]) {
        // "expected ';' or end after quoted value" - treat as unterminated quote for compatibility
        code = CSCapUrnErrorUnterminatedQuote;
    } else if ([msgLower containsString:@"numeric"]) {
        code = CSCapUrnErrorNumericKey;
    } else if ([msgLower containsString:@"escape"]) {
        code = CSCapUrnErrorInvalidEscapeSequence;
    } else if ([msgLower containsString:@"incomplete"] || [msgLower containsString:@"missing value"]) {
        code = CSCapUrnErrorInvalidTagFormat;
    } else {
        code = CSCapUrnErrorInvalidFormat;
    }

    return [NSError errorWithDomain:CSCapUrnErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: msg}];
}

+ (nullable instancetype)fromString:(NSString *)string error:(NSError **)error {
    if (!string || string.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap identifier cannot be empty"}];
        }
        return nil;
    }

    // Check for "cap:" prefix early to give better error messages
    if (string.length < 4 || ![[string substringToIndex:4] caseInsensitiveCompare:@"cap:"] == NSOrderedSame) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorMissingCapPrefix
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap identifier must start with 'cap:'"}];
        }
        return nil;
    }

    // Use CSTaggedUrn for parsing
    NSError *parseError = nil;
    CSTaggedUrn *taggedUrn = [CSTaggedUrn fromString:string error:&parseError];
    if (parseError) {
        if (error) {
            *error = [self capUrnErrorFromTaggedUrnError:parseError];
        }
        return nil;
    }

    // Double-check prefix (should always be 'cap' after the early check above)
    if (![[taggedUrn.prefix lowercaseString] isEqualToString:@"cap"]) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorMissingCapPrefix
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Expected 'cap:' prefix, got '%@:'", taggedUrn.prefix]}];
        }
        return nil;
    }

    // Extract required 'in' and 'out' tags
    NSString *inSpecValue = [taggedUrn getTag:@"in"];
    NSString *outSpecValue = [taggedUrn getTag:@"out"];

    if (!inSpecValue) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorMissingInSpec
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap URN requires 'in' tag for input media URN"}];
        }
        return nil;
    }
    if (!outSpecValue) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorMissingOutSpec
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap URN requires 'out' tag for output media URN"}];
        }
        return nil;
    }

    // Validate in/out are media URNs or wildcards
    if (![self isValidMediaUrnOrWildcard:inSpecValue]) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid 'in' media URN: %@. Must start with 'media:' or be '*'", inSpecValue]}];
        }
        return nil;
    }
    if (![self isValidMediaUrnOrWildcard:outSpecValue]) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid 'out' media URN: %@. Must start with 'media:' or be '*'", outSpecValue]}];
        }
        return nil;
    }

    // Build remaining tags (excluding in/out)
    NSMutableDictionary<NSString *, NSString *> *remainingTags = [NSMutableDictionary dictionary];
    for (NSString *key in taggedUrn.tags) {
        NSString *keyLower = [key lowercaseString];
        if (![keyLower isEqualToString:@"in"] && ![keyLower isEqualToString:@"out"]) {
            remainingTags[keyLower] = taggedUrn.tags[key];
        }
    }

    return [self fromInSpec:inSpecValue outSpec:outSpecValue tags:remainingTags error:error];
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

    // Extract required 'in' and 'out' tags
    NSString *inSpecValue = normalizedTags[@"in"];
    NSString *outSpecValue = normalizedTags[@"out"];

    if (!inSpecValue) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorMissingInSpec
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap URN requires 'in' tag for input media URN"}];
        }
        return nil;
    }
    if (!outSpecValue) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorMissingOutSpec
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap URN requires 'out' tag for output media URN"}];
        }
        return nil;
    }

    // Validate in/out are media URNs or wildcards
    if (![self isValidMediaUrnOrWildcard:inSpecValue]) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid 'in' media URN: %@. Must start with 'media:' or be '*'", inSpecValue]}];
        }
        return nil;
    }
    if (![self isValidMediaUrnOrWildcard:outSpecValue]) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid 'out' media URN: %@. Must start with 'media:' or be '*'", outSpecValue]}];
        }
        return nil;
    }

    // Build remaining tags (excluding in/out)
    NSMutableDictionary<NSString *, NSString *> *remainingTags = [NSMutableDictionary dictionary];
    for (NSString *key in normalizedTags) {
        if (![key isEqualToString:@"in"] && ![key isEqualToString:@"out"]) {
            remainingTags[key] = normalizedTags[key];
        }
    }

    return [self fromInSpec:inSpecValue outSpec:outSpecValue tags:remainingTags error:error];
}

+ (nullable instancetype)fromInSpec:(NSString *)inSpec
                            outSpec:(NSString *)outSpec
                               tags:(NSDictionary<NSString *, NSString *> *)tags
                              error:(NSError **)error {
    CSCapUrn *instance = [[CSCapUrn alloc] init];
    instance.inSpec = inSpec;
    instance.outSpec = outSpec;
    instance.mutableTags = [tags mutableCopy];
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _mutableTags = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)getInSpec {
    return self.inSpec;
}

- (NSString *)getOutSpec {
    return self.outSpec;
}

- (nullable NSString *)getTag:(NSString *)key {
    NSString *keyLower = [key lowercaseString];
    if ([keyLower isEqualToString:@"in"]) {
        return self.inSpec;
    }
    if ([keyLower isEqualToString:@"out"]) {
        return self.outSpec;
    }
    return self.mutableTags[keyLower];
}

- (BOOL)hasTag:(NSString *)key withValue:(NSString *)value {
    NSString *keyLower = [key lowercaseString];
    NSString *tagValue;
    if ([keyLower isEqualToString:@"in"]) {
        tagValue = self.inSpec;
    } else if ([keyLower isEqualToString:@"out"]) {
        tagValue = self.outSpec;
    } else {
        tagValue = self.mutableTags[keyLower];
    }
    // Case-sensitive value comparison
    return tagValue && [tagValue isEqualToString:value];
}

- (CSCapUrn *)withTag:(NSString *)key value:(NSString *)value {
    NSString *keyLower = [key lowercaseString];
    // Silently ignore attempts to set in/out via withTag - use withInSpec/withOutSpec instead
    if ([keyLower isEqualToString:@"in"] || [keyLower isEqualToString:@"out"]) {
        return self;
    }
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    // Key lowercase, value preserved
    newTags[keyLower] = value;
    return [CSCapUrn fromInSpec:self.inSpec outSpec:self.outSpec tags:newTags error:nil];
}

- (CSCapUrn *)withInSpec:(NSString *)inSpec {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    return [CSCapUrn fromInSpec:inSpec outSpec:self.outSpec tags:newTags error:nil];
}

- (CSCapUrn *)withOutSpec:(NSString *)outSpec {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    return [CSCapUrn fromInSpec:self.inSpec outSpec:outSpec tags:newTags error:nil];
}

- (CSCapUrn *)withoutTag:(NSString *)key {
    NSString *keyLower = [key lowercaseString];
    // Silently ignore attempts to remove in/out
    if ([keyLower isEqualToString:@"in"] || [keyLower isEqualToString:@"out"]) {
        return self;
    }
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    [newTags removeObjectForKey:keyLower];
    return [CSCapUrn fromInSpec:self.inSpec outSpec:self.outSpec tags:newTags error:nil];
}

- (BOOL)matches:(CSCapUrn *)request {
    if (!request) {
        return YES;
    }

    // Check direction (inSpec) FIRST
    if (![self.inSpec isEqualToString:@"*"] &&
        ![request.inSpec isEqualToString:@"*"] &&
        ![self.inSpec isEqualToString:request.inSpec]) {
        return NO;
    }

    // Check direction (outSpec)
    if (![self.outSpec isEqualToString:@"*"] &&
        ![request.outSpec isEqualToString:@"*"] &&
        ![self.outSpec isEqualToString:request.outSpec]) {
        return NO;
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

    // Count non-wildcard direction specs
    if (![self.inSpec isEqualToString:@"*"]) {
        count++;
    }
    if (![self.outSpec isEqualToString:@"*"]) {
        count++;
    }

    // Count non-wildcard tags
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

    // Check direction compatibility (inSpec)
    if (![self.inSpec isEqualToString:@"*"] &&
        ![other.inSpec isEqualToString:@"*"] &&
        ![self.inSpec isEqualToString:other.inSpec]) {
        return NO;
    }

    // Check direction compatibility (outSpec)
    if (![self.outSpec isEqualToString:@"*"] &&
        ![other.outSpec isEqualToString:@"*"] &&
        ![self.outSpec isEqualToString:other.outSpec]) {
        return NO;
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
    NSString *keyLower = [key lowercaseString];

    // Handle direction keys specially
    if ([keyLower isEqualToString:@"in"]) {
        return [self withInSpec:@"*"];
    }
    if ([keyLower isEqualToString:@"out"]) {
        return [self withOutSpec:@"*"];
    }

    // For regular tags, only set wildcard if tag already exists
    if (self.mutableTags[keyLower]) {
        return [self withTag:key value:@"*"];
    }
    return self;
}

- (CSCapUrn *)subset:(NSArray<NSString *> *)keys {
    // Always preserve direction specs, subset only applies to other tags
    NSMutableDictionary *newTags = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        NSString *normalizedKey = [key lowercaseString];
        // Skip in/out keys - direction is always preserved
        if ([normalizedKey isEqualToString:@"in"] || [normalizedKey isEqualToString:@"out"]) {
            continue;
        }
        NSString *value = self.mutableTags[normalizedKey];
        if (value) {
            newTags[normalizedKey] = value;
        }
    }
    return [CSCapUrn fromInSpec:self.inSpec outSpec:self.outSpec tags:newTags error:nil];
}

- (CSCapUrn *)merge:(CSCapUrn *)other {
    // Direction comes from other (other takes precedence)
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    for (NSString *key in other.mutableTags) {
        newTags[key] = other.mutableTags[key];
    }
    return [CSCapUrn fromInSpec:other.inSpec outSpec:other.outSpec tags:newTags error:nil];
}

- (NSString *)toString {
    // Build complete tags map including in and out
    NSMutableDictionary *allTags = [self.mutableTags mutableCopy];
    allTags[@"in"] = self.inSpec;
    allTags[@"out"] = self.outSpec;

    // Use CSTaggedUrn for serialization to ensure consistent output
    NSError *error = nil;
    CSTaggedUrn *taggedUrn = [CSTaggedUrn fromPrefix:@"cap" tags:allTags error:&error];
    if (taggedUrn) {
        return [taggedUrn toString];
    }

    // Fallback to manual serialization if TaggedUrn fails (should not happen)
    // Sort keys for canonical representation (alphabetical order including in/out)
    NSArray<NSString *> *sortedKeys = [allTags.allKeys sortedArrayUsingSelector:@selector(compare:)];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *key in sortedKeys) {
        NSString *value = allTags[key];
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
    // Compare direction specs first
    if (![self.inSpec isEqualToString:other.inSpec]) {
        return NO;
    }
    if (![self.outSpec isEqualToString:other.outSpec]) {
        return NO;
    }
    // Then compare tags
    return [self.mutableTags isEqualToDictionary:other.mutableTags];
}

- (NSUInteger)hash {
    // Include direction specs in hash
    return self.inSpec.hash ^ self.outSpec.hash ^ self.mutableTags.hash;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    return [CSCapUrn fromInSpec:self.inSpec outSpec:self.outSpec tags:self.tags error:nil];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.inSpec forKey:@"inSpec"];
    [coder encodeObject:self.outSpec forKey:@"outSpec"];
    [coder encodeObject:self.mutableTags forKey:@"tags"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _inSpec = [coder decodeObjectOfClass:[NSString class] forKey:@"inSpec"];
        _outSpec = [coder decodeObjectOfClass:[NSString class] forKey:@"outSpec"];
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
@property (nonatomic, strong) NSString *builderInSpec;
@property (nonatomic, strong) NSString *builderOutSpec;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *tags;
@end

@implementation CSCapUrnBuilder

+ (instancetype)builder {
    return [[CSCapUrnBuilder alloc] init];
}

- (instancetype)init {
    if (self = [super init]) {
        _tags = [NSMutableDictionary dictionary];
        _builderInSpec = nil;
        _builderOutSpec = nil;
    }
    return self;
}

- (CSCapUrnBuilder *)inSpec:(NSString *)spec {
    self.builderInSpec = spec;
    return self;
}

- (CSCapUrnBuilder *)outSpec:(NSString *)spec {
    self.builderOutSpec = spec;
    return self;
}

- (CSCapUrnBuilder *)tag:(NSString *)key value:(NSString *)value {
    NSString *keyLower = [key lowercaseString];
    // Silently ignore in/out keys - use inSpec:/outSpec: instead
    if ([keyLower isEqualToString:@"in"] || [keyLower isEqualToString:@"out"]) {
        return self;
    }
    // Key lowercase, value preserved
    self.tags[keyLower] = value;
    return self;
}

- (nullable CSCapUrn *)build:(NSError **)error {
    // Require inSpec
    if (!self.builderInSpec) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorMissingInSpec
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap URN requires 'in' spec - use inSpec: method"}];
        }
        return nil;
    }

    // Require outSpec
    if (!self.builderOutSpec) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapUrnErrorDomain
                                         code:CSCapUrnErrorMissingOutSpec
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap URN requires 'out' spec - use outSpec: method"}];
        }
        return nil;
    }

    return [CSCapUrn fromInSpec:self.builderInSpec outSpec:self.builderOutSpec tags:self.tags error:error];
}


@end
