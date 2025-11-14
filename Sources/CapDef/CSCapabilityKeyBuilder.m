//
//  CSCapabilityKeyBuilder.m
//  Capability ID Builder Implementation
//

#import "CSCapabilityKeyBuilder.h"

@interface CSCapabilityKeyBuilder ()
@property (nonatomic, strong, nonnull) NSMutableArray<NSString *> *mutableSegments;
@end

@implementation CSCapabilityKeyBuilder

+ (instancetype)builder {
    return [[self alloc] init];
}

+ (instancetype)builderFromCapabilityKey:(CSCapabilityKey *)capabilityKey {
    CSCapabilityKeyBuilder *builder = [self builder];
    if (capabilityKey && capabilityKey.segments) {
        [builder.mutableSegments addObjectsFromArray:capabilityKey.segments];
    }
    return builder;
}

+ (nullable instancetype)builderFromString:(NSString *)string error:(NSError **)error {
    CSCapabilityKey *capabilityKey = [CSCapabilityKey fromString:string error:error];
    if (!capabilityKey) {
        return nil;
    }
    return [self builderFromCapabilityKey:capabilityKey];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableSegments = [NSMutableArray array];
    }
    return self;
}

- (instancetype)sub:(NSString *)segment {
    if (segment) {
        [self.mutableSegments addObject:segment];
    }
    return self;
}

- (instancetype)subs:(NSArray<NSString *> *)segments {
    if (segments) {
        [self.mutableSegments addObjectsFromArray:segments];
    }
    return self;
}

- (instancetype)replaceSegmentAtIndex:(NSUInteger)index withSegment:(NSString *)segment {
    if (segment && index < self.mutableSegments.count) {
        self.mutableSegments[index] = segment;
    }
    return self;
}

- (instancetype)makeMoreGeneral {
    if (self.mutableSegments.count > 0) {
        [self.mutableSegments removeLastObject];
    }
    return self;
}

- (instancetype)makeGeneralToLevel:(NSUInteger)level {
    if (level < self.mutableSegments.count) {
        NSRange rangeToRemove = NSMakeRange(level, self.mutableSegments.count - level);
        [self.mutableSegments removeObjectsInRange:rangeToRemove];
    }
    return self;
}

- (instancetype)addWildcard {
    return [self sub:@"*"];
}

- (instancetype)makeWildcard {
    if (self.mutableSegments.count > 0) {
        self.mutableSegments[self.mutableSegments.count - 1] = @"*";
    }
    return self;
}

- (instancetype)makeWildcardFromLevel:(NSUInteger)level {
    if (level < self.mutableSegments.count) {
        // Remove segments after level and replace segment at level with wildcard
        NSRange rangeToRemove = NSMakeRange(level + 1, self.mutableSegments.count - level - 1);
        [self.mutableSegments removeObjectsInRange:rangeToRemove];
        self.mutableSegments[level] = @"*";
    } else if (level == self.mutableSegments.count) {
        // Add wildcard at the specified level
        [self addWildcard];
    }
    return self;
}

- (NSArray<NSString *> *)segments {
    return [self.mutableSegments copy];
}

- (NSUInteger)count {
    return self.mutableSegments.count;
}

- (BOOL)isEmpty {
    return self.mutableSegments.count == 0;
}

- (instancetype)clear {
    [self.mutableSegments removeAllObjects];
    return self;
}

- (instancetype)clone {
    CSCapabilityKeyBuilder *cloned = [[self class] builder];
    [cloned.mutableSegments addObjectsFromArray:self.mutableSegments];
    return cloned;
}

- (nullable CSCapabilityKey *)build:(NSError **)error {
    return [CSCapabilityKey fromSegments:self.segments error:error];
}

- (nullable NSString *)buildString:(NSError **)error {
    CSCapabilityKey *capabilityKey = [self build:error];
    if (!capabilityKey) {
        return nil;
    }
    return [capabilityKey toString];
}

- (NSString *)toString {
    return [self.segments componentsJoinedByString:@":"];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"CSCapabilityKeyBuilder(%@)", [self toString]];
}

@end

// Category implementations
@implementation NSString (CSCapabilityKeyBuilder)

- (nullable CSCapabilityKeyBuilder *)cs_intoBuilder:(NSError **)error {
    return [CSCapabilityKeyBuilder builderFromString:self error:error];
}

@end

@implementation CSCapabilityKey (CSCapabilityKeyBuilder)

- (CSCapabilityKeyBuilder *)cs_intoBuilder {
    return [CSCapabilityKeyBuilder builderFromCapabilityKey:self];
}

@end