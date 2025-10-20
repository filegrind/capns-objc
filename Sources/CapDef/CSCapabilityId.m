//
//  CSCapabilityId.m
//  Formal Capability Identifier Implementation
//

#import "CSCapabilityId.h"

NSErrorDomain const CSCapabilityIdErrorDomain = @"CSCapabilityIdErrorDomain";

@implementation CSCapabilityId

+ (nullable instancetype)fromString:(NSString *)string error:(NSError **)error {
    if (!string || string.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapabilityIdErrorDomain
                                         code:CSCapabilityIdErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Capability identifier cannot be empty"}];
        }
        return nil;
    }
    
    NSArray<NSString *> *segments = [string componentsSeparatedByString:@":"];
    return [self fromSegments:segments error:error];
}

+ (nullable instancetype)fromSegments:(NSArray<NSString *> *)segments error:(NSError **)error {
    if (!segments || segments.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:CSCapabilityIdErrorDomain
                                         code:CSCapabilityIdErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Capability identifier must have at least one segment"}];
        }
        return nil;
    }
    
    // Validate segments
    for (NSString *segment in segments) {
        if (segment.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:CSCapabilityIdErrorDomain
                                             code:CSCapabilityIdErrorEmptySegment
                                         userInfo:@{NSLocalizedDescriptionKey: @"Capability identifier segments cannot be empty"}];
            }
            return nil;
        }
        
        // Check for valid characters (alphanumeric, underscore, hyphen, or wildcard)
        NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-*"];
        if ([segment rangeOfCharacterFromSet:[validChars invertedSet]].location != NSNotFound) {
            if (error) {
                *error = [NSError errorWithDomain:CSCapabilityIdErrorDomain
                                             code:CSCapabilityIdErrorInvalidCharacter
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid character in segment: %@", segment]}];
            }
            return nil;
        }
    }
    
    CSCapabilityId *capabilityId = [[CSCapabilityId alloc] init];
    capabilityId->_segments = [segments copy];
    return capabilityId;
}

- (BOOL)canHandle:(CSCapabilityId *)request {
    if (!request) return NO;
    
    // Check each segment up to the minimum of both lengths
    NSUInteger minLength = MIN(self.segments.count, request.segments.count);
    
    for (NSUInteger i = 0; i < minLength; i++) {
        NSString *mySegment = self.segments[i];
        NSString *requestSegment = request.segments[i];
        
        // Wildcard in capability matches anything and consumes all remaining segments
        if ([mySegment isEqualToString:@"*"]) {
            return YES;
        }
        
        // Exact match required
        if (![mySegment isEqualToString:requestSegment]) {
            return NO;
        }
    }
    
    // If we've checked all capability segments and none were wildcards,
    // then we can only handle if the request has no more segments
    return request.segments.count <= self.segments.count;
}

- (BOOL)isCompatibleWith:(CSCapabilityId *)other {
    if (!other) return NO;
    
    NSUInteger minLength = MIN(self.segments.count, other.segments.count);
    
    for (NSUInteger i = 0; i < minLength; i++) {
        NSString *mySegment = self.segments[i];
        NSString *otherSegment = other.segments[i];
        
        // Wildcards are compatible with anything
        if ([mySegment isEqualToString:@"*"] || [otherSegment isEqualToString:@"*"]) {
            continue;
        }
        
        // Must match exactly
        if (![mySegment isEqualToString:otherSegment]) {
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)isMoreSpecificThan:(CSCapabilityId *)other {
    if (!other) return YES;
    
    NSUInteger mySpecificity = [self specificityLevel];
    NSUInteger otherSpecificity = [other specificityLevel];
    
    if (mySpecificity != otherSpecificity) {
        return mySpecificity > otherSpecificity;
    }
    
    // Same specificity level, check segment count
    return self.segments.count > other.segments.count;
}

- (NSUInteger)specificityLevel {
    NSUInteger count = 0;
    for (NSString *segment in self.segments) {
        if (![segment isEqualToString:@"*"]) {
            count++;
        }
    }
    return count;
}

- (BOOL)isWildcardAtLevel:(NSUInteger)level {
    if (level >= self.segments.count) {
        return NO;
    }
    return [self.segments[level] isEqualToString:@"*"];
}

- (NSString *)toString {
    return [self.segments componentsJoinedByString:@":"];
}

- (NSString *)description {
    return [self toString];
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSCapabilityId class]]) return NO;
    
    CSCapabilityId *other = (CSCapabilityId *)object;
    return [self.segments isEqualToArray:other.segments];
}

- (NSUInteger)hash {
    return [self.segments hash];
}

- (id)copyWithZone:(NSZone *)zone {
    CSCapabilityId *copy = [[CSCapabilityId alloc] init];
    copy->_segments = [self.segments copy];
    return copy;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.segments forKey:@"segments"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSSet *classes = [NSSet setWithObjects:[NSArray class], [NSString class], nil];
    NSArray<NSString *> *segments = [coder decodeObjectOfClasses:classes forKey:@"segments"];
    if (!segments) return nil;
    
    return [CSCapabilityId fromSegments:segments error:nil];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end