//
//  CSCapCard.m
//  Flat Tag-Based Cap Identifier Implementation
//

#import "CSCapCard.h"

NSErrorDomain const CSCapCardErrorDomain = @"CSCapCardErrorDomain";

@interface CSCapCard ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *mutableTags;
@end

@implementation CSCapCard

- (NSDictionary<NSString *, NSString *> *)tags {
    return [self.mutableTags copy];
}

+ (nullable instancetype)fromString:(NSString *)string error:(NSError **)error {
    if (!string || string.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapCardErrorDomain
                                         code:CSCapCardErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap identifier cannot be empty"}];
        }
        return nil;
    }
    
    // Ensure "cap:" prefix is present
    if (![string hasPrefix:@"cap:"]) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapCardErrorDomain
                                         code:CSCapCardErrorMissingCapPrefix
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap identifier must start with 'cap:'"}];
        }
        return nil;
    }
    
    // Remove the "cap:" prefix
    NSString *tagsPart = [string substringFromIndex:4];
    if (tagsPart.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapCardErrorDomain
                                         code:CSCapCardErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap identifier cannot be empty"}];
        }
        return nil;
    }
    
    NSMutableDictionary<NSString *, NSString *> *tags = [NSMutableDictionary dictionary];
    
    // Remove trailing semicolon if present
    NSString *normalizedTagsPart = tagsPart;
    if ([tagsPart hasSuffix:@";"]) {
        normalizedTagsPart = [tagsPart substringToIndex:tagsPart.length - 1];
    }
    
    NSArray<NSString *> *tagStrings = [normalizedTagsPart componentsSeparatedByString:@";"];
    for (NSString *tagString in tagStrings) {
        NSString *trimmedTag = [tagString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmedTag.length == 0) {
            continue;
        }
        
        NSArray<NSString *> *parts = [trimmedTag componentsSeparatedByString:@"="];
        if (parts.count != 2) {
            if (error) {
                *error = [NSError errorWithDomain:CSCapCardErrorDomain
                                             code:CSCapCardErrorInvalidTagFormat
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid tag format (must be key=value): %@", trimmedTag]}];
            }
            return nil;
        }
        
        NSString *key = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        if (key.length == 0 || value.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:CSCapCardErrorDomain
                                             code:CSCapCardErrorEmptyTag
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Tag key or value cannot be empty: %@", trimmedTag]}];
            }
            return nil;
        }
        
        // Validate key and value characters
        NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-*"];
        if ([key rangeOfCharacterFromSet:[validChars invertedSet]].location != NSNotFound ||
            [value rangeOfCharacterFromSet:[validChars invertedSet]].location != NSNotFound) {
            if (error) {
                *error = [NSError errorWithDomain:CSCapCardErrorDomain
                                             code:CSCapCardErrorInvalidCharacter
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid character in tag (use alphanumeric, _, -, *): %@", trimmedTag]}];
            }
            return nil;
        }
        
        tags[key] = value;
    }
    
    if (tags.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapCardErrorDomain
                                         code:CSCapCardErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap identifier cannot be empty"}];
        }
        return nil;
    }
    
    return [self fromTags:tags error:error];
}

+ (nullable instancetype)fromTags:(NSDictionary<NSString *, NSString *> *)tags error:(NSError **)error {
    if (!tags || tags.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapCardErrorDomain
                                         code:CSCapCardErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap identifier cannot be empty"}];
        }
        return nil;
    }
    
    CSCapCard *instance = [[CSCapCard alloc] init];
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
    return self.mutableTags[key];
}

- (BOOL)hasTag:(NSString *)key withValue:(NSString *)value {
    NSString *tagValue = self.mutableTags[key];
    return tagValue && [tagValue isEqualToString:value];
}

- (CSCapCard *)withTag:(NSString *)key value:(NSString *)value {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    newTags[key] = value;
    return [CSCapCard fromTags:newTags error:nil];
}

- (CSCapCard *)withoutTag:(NSString *)key {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    [newTags removeObjectForKey:key];
    return [CSCapCard fromTags:newTags error:nil];
}

- (BOOL)matches:(CSCapCard *)request {
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

- (BOOL)canHandle:(CSCapCard *)request {
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

- (BOOL)isMoreSpecificThan:(CSCapCard *)other {
    if (!other) {
        return YES;
    }
    
    // First check if they're compatible
    if (![self isCompatibleWith:other]) {
        return NO;
    }
    
    return self.specificity > other.specificity;
}

- (BOOL)isCompatibleWith:(CSCapCard *)other {
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

- (CSCapCard *)withWildcardTag:(NSString *)key {
    if (self.mutableTags[key]) {
        return [self withTag:key value:@"*"];
    }
    return self;
}

- (CSCapCard *)subset:(NSArray<NSString *> *)keys {
    NSMutableDictionary *newTags = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        NSString *value = self.mutableTags[key];
        if (value) {
            newTags[key] = value;
        }
    }
    return [CSCapCard fromTags:newTags error:nil];
}

- (CSCapCard *)merge:(CSCapCard *)other {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    for (NSString *key in other.mutableTags) {
        newTags[key] = other.mutableTags[key];
    }
    return [CSCapCard fromTags:newTags error:nil];
}

- (NSString *)toString {
    if (self.mutableTags.count == 0) {
        return @"";
    }
    
    // Sort keys for canonical representation
    NSArray<NSString *> *sortedKeys = [self.mutableTags.allKeys sortedArrayUsingSelector:@selector(compare:)];
    
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *key in sortedKeys) {
        [parts addObject:[NSString stringWithFormat:@"%@=%@", key, self.mutableTags[key]]];
    }
    
    NSString *tagsString = [parts componentsJoinedByString:@";"];
    return [NSString stringWithFormat:@"cap:%@", tagsString];
}

- (NSString *)description {
    return [self toString];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[CSCapCard class]]) {
        return NO;
    }
    
    CSCapCard *other = (CSCapCard *)object;
    return [self.mutableTags isEqualToDictionary:other.mutableTags];
}

- (NSUInteger)hash {
    return self.mutableTags.hash;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    return [CSCapCard fromTags:self.tags error:nil];
}

#pragma mark - NSCoding

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.mutableTags forKey:@"tags"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _mutableTags = [[coder decodeObjectForKey:@"tags"] mutableCopy];
    }
    return self;
}

@end

#pragma mark - CSCapCardBuilder

@interface CSCapCardBuilder ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *tags;
@end

@implementation CSCapCardBuilder

+ (instancetype)builder {
    return [[CSCapCardBuilder alloc] init];
}

- (instancetype)init {
    if (self = [super init]) {
        _tags = [NSMutableDictionary dictionary];
    }
    return self;
}

- (CSCapCardBuilder *)tag:(NSString *)key value:(NSString *)value {
    self.tags[key] = value;
    return self;
}

- (nullable CSCapCard *)build:(NSError **)error {
    if (self.tags.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapCardErrorDomain
                                         code:CSCapCardErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cap identifier cannot be empty"}];
        }
        return nil;
    }
    
    return [CSCapCard fromTags:self.tags error:error];
}

@end