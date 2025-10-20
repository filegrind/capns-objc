//
//  CSCapability.m
//  Formal capability implementation
//

#import "CSCapability.h"

@implementation CSCapability

+ (instancetype)capabilityWithId:(CSCapabilityId *)capabilityId version:(NSString *)version {
    return [self capabilityWithId:capabilityId version:version description:nil metadata:@{}];
}

+ (instancetype)capabilityWithId:(CSCapabilityId *)capabilityId 
                         version:(NSString *)version 
                     description:(NSString *)description {
    return [self capabilityWithId:capabilityId version:version description:description metadata:@{}];
}

+ (instancetype)capabilityWithId:(CSCapabilityId *)capabilityId 
                         version:(NSString *)version 
                        metadata:(NSDictionary<NSString *, NSString *> *)metadata {
    return [self capabilityWithId:capabilityId version:version description:nil metadata:metadata];
}

+ (instancetype)capabilityWithId:(CSCapabilityId *)capabilityId 
                         version:(NSString *)version 
                     description:(nullable NSString *)description 
                        metadata:(NSDictionary<NSString *, NSString *> *)metadata {
    CSCapability *capability = [[CSCapability alloc] init];
    capability->_capabilityId = [capabilityId copy];
    capability->_version = [version copy];
    capability->_capabilityDescription = [description copy];
    capability->_metadata = [metadata copy] ?: @{};
    return capability;
}

- (BOOL)matchesRequest:(NSString *)request {
    NSError *error;
    CSCapabilityId *requestId = [CSCapabilityId fromString:request error:&error];
    if (!requestId) {
        return NO;
    }
    return [self.capabilityId canHandle:requestId];
}

- (BOOL)canHandleRequest:(CSCapabilityId *)request {
    return [self.capabilityId canHandle:request];
}

- (BOOL)isMoreSpecificThan:(CSCapability *)other {
    if (!other) {
        return YES;
    }
    return [self.capabilityId isMoreSpecificThan:other.capabilityId];
}

- (nullable NSString *)metadataForKey:(NSString *)key {
    return self.metadata[key];
}

- (BOOL)hasMetadataForKey:(NSString *)key {
    return self.metadata[key] != nil;
}

- (NSString *)idString {
    return [self.capabilityId toString];
}

- (NSString *)description {
    NSMutableString *desc = [NSMutableString stringWithFormat:@"CSCapability(id: %@, version: %@", 
                            [self.capabilityId toString], self.version];
    
    if (self.capabilityDescription) {
        [desc appendFormat:@", description: %@", self.capabilityDescription];
    }
    
    if (self.metadata.count > 0) {
        [desc appendFormat:@", metadata: %@", self.metadata];
    }
    
    [desc appendString:@")"];
    return desc;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSCapability class]]) return NO;
    
    CSCapability *other = (CSCapability *)object;
    return [self.capabilityId isEqual:other.capabilityId] &&
           [self.version isEqualToString:other.version] &&
           ((self.capabilityDescription == nil && other.capabilityDescription == nil) ||
            [self.capabilityDescription isEqualToString:other.capabilityDescription]) &&
           [self.metadata isEqualToDictionary:other.metadata];
}

- (NSUInteger)hash {
    return [self.capabilityId hash] ^ [self.version hash] ^ [self.metadata hash];
}

- (id)copyWithZone:(NSZone *)zone {
    return [CSCapability capabilityWithId:self.capabilityId 
                                   version:self.version 
                               description:self.capabilityDescription 
                                  metadata:self.metadata];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.capabilityId forKey:@"capabilityId"];
    [coder encodeObject:self.version forKey:@"version"];
    [coder encodeObject:self.capabilityDescription forKey:@"capabilityDescription"];
    [coder encodeObject:self.metadata forKey:@"metadata"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    CSCapabilityId *capabilityId = [coder decodeObjectOfClass:[CSCapabilityId class] forKey:@"capabilityId"];
    NSString *version = [coder decodeObjectOfClass:[NSString class] forKey:@"version"];
    NSString *description = [coder decodeObjectOfClass:[NSString class] forKey:@"capabilityDescription"];
    NSDictionary *metadata = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"metadata"];
    
    if (!capabilityId || !version) return nil;
    
    return [CSCapability capabilityWithId:capabilityId 
                                   version:version 
                               description:description 
                                  metadata:metadata ?: @{}];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end