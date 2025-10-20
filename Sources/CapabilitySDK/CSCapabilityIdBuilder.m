//
//  CSCapabilityIdBuilder.m
//  Capability ID Builder Implementation
//

#import "CSCapabilityIdBuilder.h"

@interface CSCapabilityIdBuilder ()
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableSegments;
@end

@implementation CSCapabilityIdBuilder

+ (instancetype)builder {
    return [[self alloc] init];
}

+ (instancetype)builderFromCapabilityId:(CSCapabilityId *)capabilityId {
    CSCapabilityIdBuilder *builder = [self builder];
    if (capabilityId && capabilityId.segments) {
        [builder.mutableSegments addObjectsFromArray:capabilityId.segments];
    }
    return builder;
}

+ (nullable instancetype)builderFromString:(NSString *)string error:(NSError **)error {
    CSCapabilityId *capabilityId = [CSCapabilityId fromString:string error:error];
    if (!capabilityId) {
        return nil;
    }
    return [self builderFromCapabilityId:capabilityId];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableSegments = [NSMutableArray array];
    }
    return self;
}

- (instancetype)addSegment:(NSString *)segment {
    if (segment) {
        [self.mutableSegments addObject:segment];
    }
    return self;
}

- (instancetype)addSegments:(NSArray<NSString *> *)segments {
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
    return [self addSegment:@"*"];
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
    CSCapabilityIdBuilder *cloned = [[self class] builder];
    [cloned.mutableSegments addObjectsFromArray:self.mutableSegments];
    return cloned;
}

- (nullable CSCapabilityId *)build:(NSError **)error {
    return [CSCapabilityId fromSegments:self.segments error:error];
}

- (nullable NSString *)buildString:(NSError **)error {
    CSCapabilityId *capabilityId = [self build:error];
    if (!capabilityId) {
        return nil;
    }
    return [capabilityId toString];
}

- (NSString *)toString {
    return [self.segments componentsJoinedByString:@":"];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"CSCapabilityIdBuilder(%@)", [self toString]];
}

@end

// Category implementations
@implementation NSString (CSCapabilityIdBuilder)

- (nullable CSCapabilityIdBuilder *)cs_intoBuilder:(NSError **)error {
    return [CSCapabilityIdBuilder builderFromString:self error:error];
}

@end

@implementation CSCapabilityId (CSCapabilityIdBuilder)

- (CSCapabilityIdBuilder *)cs_intoBuilder {
    return [CSCapabilityIdBuilder builderFromCapabilityId:self];
}

@end