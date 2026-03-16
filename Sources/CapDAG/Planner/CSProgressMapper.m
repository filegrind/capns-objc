//
//  CSProgressMapper.m
//  CapDAG
//
//  Progress mapping for DAG execution.
//  Mirrors Rust: src/orchestrator/executor.rs
//

#import "CSProgressMapper.h"

// MARK: - Canonical Progress Mapping

float CSMapProgress(float childProgress, float base, float weight) {
    float clamped = fminf(1.0f, fmaxf(0.0f, childProgress));
    return base + clamped * weight;
}

// MARK: - ProgressMapper

@implementation CSProgressMapper

- (instancetype)initWithParent:(CSCapProgressFn)parent
                          base:(float)base
                        weight:(float)weight {
    self = [super init];
    if (self) {
        _parent = [parent copy];
        _base = base;
        _weight = weight;
    }
    return self;
}

- (void)report:(float)childProgress capUrn:(NSString *)capUrn message:(NSString *)message {
    float mapped = CSMapProgress(childProgress, self.base, self.weight);
    self.parent(mapped, capUrn, message);
}

- (CSCapProgressFn)asCapProgressFn {
    CSProgressMapper *mapper = self;
    return ^(float progress, NSString *capUrn, NSString *message) {
        [mapper report:progress capUrn:capUrn message:message];
    };
}

- (CSProgressMapper *)subMapperWithBase:(float)subBase weight:(float)subWeight {
    float newBase = self.base + subBase * self.weight;
    float newWeight = subWeight * self.weight;
    return [[CSProgressMapper alloc] initWithParent:self.parent
                                               base:newBase
                                             weight:newWeight];
}

@end
