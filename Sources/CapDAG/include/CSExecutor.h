//
//  CSExecutor.h
//  CapDAG
//
//  Plan Executor — generic execution engine for cap execution plans
//  Mirrors Rust: src/planner/executor.rs
//

#import <Foundation/Foundation.h>
#import "CSPlan.h"

@class CSCapExecutionPlan;
@class CSCapInputFile;
@class CSCapChainExecutionResult;
@class CSCap;

NS_ASSUME_NONNULL_BEGIN

// MARK: - CapExecutor Protocol

/// Protocol for executing caps
/// Implemented by:
/// - machfab: via CapService.execute_cap() through the relay
/// - macino: by spawning plugin binaries
@protocol CSCapExecutorProtocol <NSObject>

/// Execute a cap and return the raw output bytes
- (void)executeCapWithUrn:(NSString *)capUrn
                arguments:(NSArray<NSDictionary *> *)arguments
            preferredCap:(nullable NSString *)preferredCap
              completion:(void (^)(NSData * _Nullable output, NSError * _Nullable error))completion;

/// Check if a cap is available (has a provider)
- (void)hasCap:(NSString *)capUrn completion:(void (^)(BOOL has))completion;

/// Get the cap definition from the registry
- (void)getCap:(NSString *)capUrn completion:(void (^)(CSCap * _Nullable cap, NSError * _Nullable error))completion;

@end

// MARK: - CapSettingsProvider Protocol

/// Provides overridden default values for cap arguments
@protocol CSCapSettingsProviderProtocol <NSObject>

/// Get overridden default values for a cap's arguments
/// Keys are media URNs (argument identifiers), values are JSON values
- (void)getSettingsForCap:(NSString *)capUrn
               completion:(void (^)(NSDictionary<NSString *, id> * _Nullable settings, NSError * _Nullable error))completion;

@end

// MARK: - PlanExecutor

/// Generic plan executor parameterized by a cap execution backend
@interface CSPlanExecutor : NSObject

/// Create a new plan executor
- (instancetype)initWithExecutor:(id<CSCapExecutorProtocol>)executor
                            plan:(CSCapExecutionPlan *)plan
                      inputFiles:(NSArray<CSCapInputFile *> *)inputFiles;

/// Set user-provided slot values for argument binding (raw bytes)
- (instancetype)withSlotValues:(NSDictionary<NSString *, NSData *> *)slotValues;

/// Set the settings provider for cap argument overrides
- (instancetype)withSettingsProvider:(id<CSCapSettingsProviderProtocol>)provider;

/// Execute the plan and return the result
- (void)execute:(void (^)(CSCapChainExecutionResult * _Nullable result, NSError * _Nullable error))completion;

@end

// MARK: - JSON Path Functions

/// Apply edge type transformation to extract data from a source output
NSError *_Nullable CSApplyEdgeType(
    id sourceOutput,
    CSEdgeType edgeType,
    NSString * _Nullable field,
    NSString * _Nullable path,
    id _Nullable *_Nullable outValue
);

/// Extract a value using a simple JSON path expression
NSError *_Nullable CSExtractJSONPath(
    id json,
    NSString *path,
    id _Nullable *_Nullable outValue
);

NS_ASSUME_NONNULL_END
