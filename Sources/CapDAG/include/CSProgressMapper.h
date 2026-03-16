//
//  CSProgressMapper.h
//  CapDAG
//
//  Progress mapping for DAG execution — maps child [0.0, 1.0] into parent range.
//  Mirrors Rust: src/orchestrator/executor.rs (ProgressMapper, map_progress)
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Progress callback: progress (0.0-1.0), cap URN string, human message
typedef void (^CSCapProgressFn)(float progress, NSString *capUrn, NSString *message);

// MARK: - Canonical Progress Mapping

/// Map child progress [0.0, 1.0] into parent range [base, base + weight].
/// Canonical formula used everywhere: DAG execution, ForEach items, peer calls.
/// Child progress is clamped to [0.0, 1.0] before mapping.
float CSMapProgress(float childProgress, float base, float weight);

// MARK: - ProgressMapper

/// Wraps a CSCapProgressFn with progress range subdivision.
/// Maps child [0.0, 1.0] into parent range [base, base + weight].
@interface CSProgressMapper : NSObject

/// The base offset in parent coordinate space
@property (nonatomic, readonly) float base;
/// The weight (range size) in parent coordinate space
@property (nonatomic, readonly) float weight;
/// The parent progress callback
@property (nonatomic, readonly, copy) CSCapProgressFn parent;

/// Create mapper that maps child [0.0, 1.0] into [base, base + weight]
- (instancetype)initWithParent:(CSCapProgressFn)parent
                          base:(float)base
                        weight:(float)weight;

/// Report child progress; clamped to [0.0, 1.0] and mapped to parent range
- (void)report:(float)childProgress capUrn:(NSString *)capUrn message:(NSString *)message;

/// Convert to a CSCapProgressFn for passing to APIs expecting one
- (CSCapProgressFn)asCapProgressFn;

/// Create sub-mapper for nested progress ranges.
/// If this mapper maps to [0.2, 0.8] (base=0.2, weight=0.6),
/// subMapper(0.5, 0.5) maps to [0.5, 0.8] in parent coordinate space.
- (CSProgressMapper *)subMapperWithBase:(float)subBase weight:(float)subWeight;

@end

NS_ASSUME_NONNULL_END
