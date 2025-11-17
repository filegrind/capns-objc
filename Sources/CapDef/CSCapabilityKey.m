//
//  CSCapabilityKey.m
//  Flat Tag-Based Capability Identifier Implementation
//

#import "CSCapabilityKey.h"

NSErrorDomain const CSCapabilityKeyErrorDomain = @"CSCapabilityKeyErrorDomain";

@interface CSCapabilityKey ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *mutableTags;
@end

@implementation CSCapabilityKey

- (NSDictionary<NSString *, NSString *> *)tags {
    return [self.mutableTags copy];
}

+ (nullable instancetype)fromString:(NSString *)string error:(NSError **)error {
    if (!string || string.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapabilityKeyErrorDomain
                                         code:CSCapabilityKeyErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Capability identifier cannot be empty"}];
        }
        return nil;
    }
    
    NSMutableDictionary<NSString *, NSString *> *tags = [NSMutableDictionary dictionary];
    
    NSArray<NSString *> *tagStrings = [string componentsSeparatedByString:@";"];
    for (NSString *tagString in tagStrings) {
        NSString *trimmedTag = [tagString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmedTag.length == 0) {
            continue;
        }
        
        NSArray<NSString *> *parts = [trimmedTag componentsSeparatedByString:@"="];
        if (parts.count != 2) {
            if (error) {
                *error = [NSError errorWithDomain:CSCapabilityKeyErrorDomain
                                             code:CSCapabilityKeyErrorInvalidTagFormat
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid tag format (must be key=value): %@", trimmedTag]}];
            }
            return nil;
        }
        
        NSString *key = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        if (key.length == 0 || value.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:CSCapabilityKeyErrorDomain
                                             code:CSCapabilityKeyErrorEmptyTag
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Tag key or value cannot be empty: %@", trimmedTag]}];
            }
            return nil;
        }
        
        // Validate key and value characters
        NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-*"];
        if ([key rangeOfCharacterFromSet:[validChars invertedSet]].location != NSNotFound ||
            [value rangeOfCharacterFromSet:[validChars invertedSet]].location != NSNotFound) {
            if (error) {
                *error = [NSError errorWithDomain:CSCapabilityKeyErrorDomain
                                             code:CSCapabilityKeyErrorInvalidCharacter
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid character in tag (use alphanumeric, _, -, *): %@", trimmedTag]}];
            }
            return nil;
        }
        
        tags[key] = value;
    }
    
    if (tags.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapabilityKeyErrorDomain
                                         code:CSCapabilityKeyErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Capability identifier cannot be empty"}];
        }
        return nil;
    }
    
    return [self fromTags:tags error:error];
}

+ (nullable instancetype)fromTags:(NSDictionary<NSString *, NSString *> *)tags error:(NSError **)error {
    if (!tags || tags.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapabilityKeyErrorDomain
                                         code:CSCapabilityKeyErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Capability identifier cannot be empty"}];
        }
        return nil;
    }
    
    CSCapabilityKey *instance = [[CSCapabilityKey alloc] init];
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

- (CSCapabilityKey *)withTag:(NSString *)key value:(NSString *)value {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    newTags[key] = value;
    return [CSCapabilityKey fromTags:newTags error:nil];
}

- (CSCapabilityKey *)withoutTag:(NSString *)key {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    [newTags removeObjectForKey:key];
    return [CSCapabilityKey fromTags:newTags error:nil];
}

- (BOOL)matches:(CSCapabilityKey *)request {
    if (!request) {
        return YES;
    }
    
    // Check all tags that the request specifies
    for (NSString *requestKey in request.tags) {
        NSString *requestValue = request.tags[requestKey];
        NSString *capValue = self.mutableTags[requestKey];
        
        if (!capValue) {
            // Missing tag in capability is treated as wildcard - can handle any value
            continue;
        }
        
        if ([capValue isEqualToString:@"*"]) {
            // Capability has wildcard - can handle any value
            continue;
        }
        
        if ([requestValue isEqualToString:@"*"]) {
            // Request accepts any value - capability's specific value matches
            continue;
        }
        
        if (![capValue isEqualToString:requestValue]) {
            // Capability has specific value that doesn't match request's specific value
            return NO;
        }
    }
    
    // If capability has additional specific tags that request doesn't specify, that's fine
    // The capability is just more specific than needed
    return YES;
}

- (BOOL)canHandle:(CSCapabilityKey *)request {
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

- (BOOL)isMoreSpecificThan:(CSCapabilityKey *)other {
    if (!other) {
        return YES;
    }
    
    // First check if they're compatible
    if (![self isCompatibleWith:other]) {
        return NO;
    }
    
    return self.specificity > other.specificity;
}

- (BOOL)isCompatibleWith:(CSCapabilityKey *)other {
    if (!other) {
        return YES;
    }
    
    // Get all unique tag keys from both capabilities
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

- (nullable NSString *)capabilityType {
    return [self getTag:@"type"];
}

- (nullable NSString *)action {
    return [self getTag:@"action"];
}

- (nullable NSString *)target {
    return [self getTag:@"target"];
}

- (nullable NSString *)format {
    return [self getTag:@"format"];
}

- (nullable NSString *)output {
    return [self getTag:@"output"];
}

- (BOOL)isBinary {
    return [self hasTag:@"output" withValue:@"binary"];
}

- (CSCapabilityKey *)withWildcardTag:(NSString *)key {
    if (self.mutableTags[key]) {
        return [self withTag:key value:@"*"];
    }
    return self;
}

- (CSCapabilityKey *)subset:(NSArray<NSString *> *)keys {
    NSMutableDictionary *newTags = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        NSString *value = self.mutableTags[key];
        if (value) {
            newTags[key] = value;
        }
    }
    return [CSCapabilityKey fromTags:newTags error:nil];
}

- (CSCapabilityKey *)merge:(CSCapabilityKey *)other {
    NSMutableDictionary *newTags = [self.mutableTags mutableCopy];
    for (NSString *key in other.mutableTags) {
        newTags[key] = other.mutableTags[key];
    }
    return [CSCapabilityKey fromTags:newTags error:nil];
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
    
    return [parts componentsJoinedByString:@";"];
}

- (NSString *)description {
    return [self toString];
}

- (BOOL)isEqual:(id)object {
    if (![object isKindOfClass:[CSCapabilityKey class]]) {
        return NO;
    }
    
    CSCapabilityKey *other = (CSCapabilityKey *)object;
    return [self.mutableTags isEqualToDictionary:other.mutableTags];
}

- (NSUInteger)hash {
    return self.mutableTags.hash;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    return [CSCapabilityKey fromTags:self.tags error:nil];
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

#pragma mark - CSCapabilityKeyBuilder

@interface CSCapabilityKeyBuilder ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *tags;
@end

@implementation CSCapabilityKeyBuilder

+ (instancetype)builder {
    return [[CSCapabilityKeyBuilder alloc] init];
}

- (instancetype)init {
    if (self = [super init]) {
        _tags = [NSMutableDictionary dictionary];
    }
    return self;
}

- (CSCapabilityKeyBuilder *)tag:(NSString *)key value:(NSString *)value {
    self.tags[key] = value;
    return self;
}

- (CSCapabilityKeyBuilder *)type:(NSString *)value {
    return [self tag:@"type" value:value];
}

- (CSCapabilityKeyBuilder *)action:(NSString *)value {
    return [self tag:@"action" value:value];
}

- (CSCapabilityKeyBuilder *)target:(NSString *)value {
    return [self tag:@"target" value:value];
}

- (CSCapabilityKeyBuilder *)format:(NSString *)value {
    return [self tag:@"format" value:value];
}

- (CSCapabilityKeyBuilder *)output:(NSString *)value {
    return [self tag:@"output" value:value];
}

- (CSCapabilityKeyBuilder *)binaryOutput {
    return [self output:@"binary"];
}

- (CSCapabilityKeyBuilder *)jsonOutput {
    return [self output:@"json"];
}

- (nullable CSCapabilityKey *)build:(NSError **)error {
    if (self.tags.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapabilityKeyErrorDomain
                                         code:CSCapabilityKeyErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Capability identifier cannot be empty"}];
        }
        return nil;
    }
    
    return [CSCapabilityKey fromTags:self.tags error:error];
}

@end