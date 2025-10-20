//
//  CSPluginCapabilities.m
//  Plugin capabilities collection implementation
//

#import "CSPluginCapabilities.h"
#import "CSCapabilityMatcher.h"

@interface CSPluginCapabilities ()
@property (nonatomic, strong) NSMutableArray<CSCapability *> *mutableCapabilities;
@end

@implementation CSPluginCapabilities

+ (instancetype)new {
    return [self capabilitiesWithArray:@[]];
}

+ (instancetype)capabilitiesWithArray:(NSArray<CSCapability *> *)capabilities {
    CSPluginCapabilities *instance = [[CSPluginCapabilities alloc] init];
    instance.mutableCapabilities = [capabilities mutableCopy];
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableCapabilities = [NSMutableArray array];
    }
    return self;
}

- (NSArray<CSCapability *> *)capabilities {
    return [self.mutableCapabilities copy];
}

- (void)addCapability:(CSCapability *)capability {
    if (capability) {
        [self.mutableCapabilities addObject:capability];
    }
}

- (void)removeCapability:(CSCapability *)capability {
    [self.mutableCapabilities removeObject:capability];
}

- (BOOL)canHandleCapability:(NSString *)capabilityRequest {
    for (CSCapability *capability in self.mutableCapabilities) {
        if ([capability matchesRequest:capabilityRequest]) {
            return YES;
        }
    }
    return NO;
}

- (NSArray<NSString *> *)capabilityIdentifiers {
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    for (CSCapability *capability in self.mutableCapabilities) {
        [identifiers addObject:[capability idString]];
    }
    return identifiers;
}

- (nullable CSCapability *)findCapabilityWithIdentifier:(NSString *)identifier {
    NSError *error;
    CSCapabilityId *searchId = [CSCapabilityId fromString:identifier error:&error];
    if (!searchId) return nil;
    
    for (CSCapability *capability in self.mutableCapabilities) {
        if ([capability.capabilityId isEqual:searchId]) {
            return capability;
        }
    }
    return nil;
}

- (nullable CSCapability *)findBestCapabilityForRequest:(NSString *)request {
    NSError *error;
    CSCapabilityId *requestId = [CSCapabilityId fromString:request error:&error];
    if (!requestId) return nil;
    
    NSMutableArray<CSCapabilityId *> *capabilityIds = [NSMutableArray array];
    for (CSCapability *capability in self.mutableCapabilities) {
        [capabilityIds addObject:capability.capabilityId];
    }
    
    CSCapabilityId *bestId = [CSCapabilityMatcher findBestMatchInCapabilities:capabilityIds forRequest:requestId];
    if (!bestId) return nil;
    
    for (CSCapability *capability in self.mutableCapabilities) {
        if ([capability.capabilityId isEqual:bestId]) {
            return capability;
        }
    }
    return nil;
}

- (NSArray<CSCapability *> *)capabilitiesWithMetadataKey:(NSString *)key value:(nullable NSString *)value {
    NSMutableArray<CSCapability *> *matches = [NSMutableArray array];
    
    for (CSCapability *capability in self.mutableCapabilities) {
        if (value) {
            NSString *metadataValue = [capability metadataForKey:key];
            if ([metadataValue isEqualToString:value]) {
                [matches addObject:capability];
            }
        } else {
            if ([capability hasMetadataForKey:key]) {
                [matches addObject:capability];
            }
        }
    }
    
    return matches;
}

- (NSArray<NSString *> *)allMetadataKeys {
    NSMutableSet<NSString *> *keys = [NSMutableSet set];
    
    for (CSCapability *capability in self.mutableCapabilities) {
        [keys addObjectsFromArray:[capability.metadata allKeys]];
    }
    
    return [[keys allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<CSCapability *> *)capabilitiesWithVersion:(NSString *)version {
    NSMutableArray<CSCapability *> *matches = [NSMutableArray array];
    
    for (CSCapability *capability in self.mutableCapabilities) {
        if ([capability.version isEqualToString:version]) {
            [matches addObject:capability];
        }
    }
    
    return matches;
}

- (NSUInteger)count {
    return self.mutableCapabilities.count;
}

- (BOOL)isEmpty {
    return self.mutableCapabilities.count == 0;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"CSPluginCapabilities(count: %lu, capabilities: %@)", 
            (unsigned long)self.count, self.capabilities];
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[CSPluginCapabilities class]]) return NO;
    
    CSPluginCapabilities *other = (CSPluginCapabilities *)object;
    return [self.capabilities isEqualToArray:other.capabilities];
}

- (NSUInteger)hash {
    return [self.capabilities hash];
}

- (id)copyWithZone:(NSZone *)zone {
    return [CSPluginCapabilities capabilitiesWithArray:self.capabilities];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.capabilities forKey:@"capabilities"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder {
    NSArray<CSCapability *> *capabilities = [coder decodeObjectOfClass:[NSArray class] forKey:@"capabilities"];
    if (!capabilities) return nil;
    
    return [CSPluginCapabilities capabilitiesWithArray:capabilities];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end